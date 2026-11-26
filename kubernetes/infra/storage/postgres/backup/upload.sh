#!/bin/sh
# Uploads the encrypted backup under a fixed retention count, after a guard on
# the whole bucket. The bound on what this job stores does not depend on the
# database write rate:
#
#   objects under the prefix <= KEEP + 1 at any time
#   bytes under the prefix   <= (KEEP + 1) * MAX_OBJECT_BYTES
#
# because an object above MAX_OBJECT_BYTES is never uploaded, this job's
# objects are pruned to KEEP before and after each upload, a job never
# retries, and no manual run overlaps a scheduled one.
# The job also fails, without uploading, when the whole bucket would cross
# CEILING_BYTES - RESERVE_BYTES. The bucket-size warning is a separate job.
#
# Only keys named <prefix><BACKUP_NAME>-YYYYMMDDTHHMMSSZ.tar.gpg belong to this
# job. Any other key under the prefix is never counted or deleted.
#
# Inputs: AWS_* credentials, S3_ENDPOINT_URL, S3_BUCKET, S3_PREFIX, BACKUP_NAME,
# KEEP, MAX_OBJECT_BYTES, CEILING_BYTES, RESERVE_BYTES, WORK_DIR.
set -eu
# Object keys are split on newlines below; never expand them as globs.
set -f

fail() {
  printf 'upload: %s\n' "$1" >&2
  exit 1
}

is_count() {
  case "$1" in
    '' | *[!0-9]*) return 1 ;;
  esac
}

: "${AWS_ACCESS_KEY_ID:?}" "${AWS_SECRET_ACCESS_KEY:?}"
: "${S3_ENDPOINT_URL:?}" "${S3_BUCKET:?}" "${S3_PREFIX:?}" "${BACKUP_NAME:?}" "${WORK_DIR:?}"
for value in "${KEEP:?}" "${MAX_OBJECT_BYTES:?}" "${CEILING_BYTES:?}" "${RESERVE_BYTES:?}"; do
  is_count "$value" || fail "numeric settings must be non-negative integers"
done
[ "$KEEP" -ge 1 ] || fail "KEEP must be at least 1"

prefix="${S3_PREFIX%/}/"
file="$WORK_DIR/backup.tar.gpg"
key="${prefix}${BACKUP_NAME}-$(date -u +%Y%m%dT%H%M%SZ).tar.gpg"

s3() {
  aws --endpoint-url "$S3_ENDPOINT_URL" --output json s3api "$@"
}

# JSON output, not text: with text output the CLI applies --query to each
# page separately and a sum would cover only the first 1000 objects.
bucket_bytes() {
  listing=$(s3 list-objects-v2 --bucket "$S3_BUCKET" --query 'sum(Contents[].Size || `[]`)') || return 1
  printf '%s' "$listing" | jq -er 'floor'
}

# This job's objects, oldest first. Timestamped names sort chronologically.
own_keys() {
  listing=$(s3 list-objects-v2 --bucket "$S3_BUCKET" --prefix "$prefix" --query 'Contents[].Key || `[]`') || return 1
  printf '%s' "$listing" \
    | jq -r --arg p "${prefix}${BACKUP_NAME}-" \
        '.[] | select(startswith($p) and (.[($p | length):] | test("^[0-9]{8}T[0-9]{6}Z\\.tar\\.gpg$")))' \
    | LC_ALL=C sort
}

count_lines() {
  printf '%s' "$1" | grep -c . || true
}

prune() {
  keys=$(own_keys) || fail "cannot list existing backups"
  count=$(count_lines "$keys")
  if [ "$count" -gt "$KEEP" ]; then
    for old in $(printf '%s\n' "$keys" | head -n "$((count - KEEP))"); do
      s3 delete-object --bucket "$S3_BUCKET" --key "$old" > /dev/null || fail "cannot delete an old backup"
      printf 'upload: pruned %s\n' "${old#"$prefix"}"
    done
  fi
  keys=$(own_keys) || fail "cannot list existing backups"
  count=$(count_lines "$keys")
  [ "$count" -le "$KEEP" ] || fail "retention left $count objects, more than $KEEP"
}

# Base64 of the binary MD5 digest, for Content-MD5. The aws-cli image has no
# xxd, so the hex digest is converted with awk and printf octal escapes.
content_md5() {
  escapes=$(md5sum "$1" | cut -c1-32 | awk '{
    d = "0123456789abcdef"
    for (i = 1; i < length($0); i += 2)
      printf "\\%03o", (index(d, substr($0, i, 1)) - 1) * 16 + index(d, substr($0, i + 1, 1)) - 1
  }')
  # shellcheck disable=SC2059
  printf "$escapes" | base64
}

[ -s "$file" ] || fail "no encrypted backup to upload"
size=$(wc -c < "$file" | tr -d ' ')
[ "$size" -le "$MAX_OBJECT_BYTES" ] || fail "encrypted backup is $size bytes, above the $MAX_OBJECT_BYTES-byte object bound"
sha256=$(sha256sum "$file" | cut -d' ' -f1)

# A previous run may have stopped between upload and prune.
prune

current=$(bucket_bytes) || fail "cannot measure bucket usage"
projected=$((current + size + RESERVE_BYTES))
printf 'upload: bucket_bytes=%s object_bytes=%s reserve_bytes=%s ceiling_bytes=%s\n' \
  "$current" "$size" "$RESERVE_BYTES" "$CEILING_BYTES"
[ "$projected" -lt "$CEILING_BYTES" ] || fail "capacity guard failed: upload would leave less than the reserve below the ceiling"

s3 put-object --bucket "$S3_BUCKET" --key "$key" --body "$file" \
  --content-md5 "$(content_md5 "$file")" --metadata "sha256=$sha256" > /dev/null

stored=$(s3 head-object --bucket "$S3_BUCKET" --key "$key") || fail "uploaded object is not readable"
stored_size=$(printf '%s' "$stored" | jq -er '.ContentLength')
stored_sha=$(printf '%s' "$stored" | jq -er '.Metadata.sha256')
[ "$stored_size" = "$size" ] || fail "stored object is $stored_size bytes, expected $size"
[ "$stored_sha" = "$sha256" ] || fail "stored object metadata does not carry the expected sha256"
printf 'upload: stored %s (%s bytes, sha256 %s)\n' "${key#"$prefix"}" "$size" "$sha256"

prune

printf 'upload: done\n'
