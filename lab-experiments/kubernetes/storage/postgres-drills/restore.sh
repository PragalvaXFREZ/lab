#!/bin/sh
# Restores one backup object into the scratch cluster and prints the table
# checksums of every restored database. Runs on the operator workstation,
# where the OpenPGP private key is; the key never enters the cluster.
#
# usage: restore.sh OUTPUT_DIR [OBJECT_NAME]
#
# OBJECT_NAME is a name under the backup prefix, for example
# postgres-20261128T031700Z.tar.gpg. The newest backup is used when omitted.
# Requires gpg, kubectl, jq, docker or a local aws CLI, and AWS_ACCESS_KEY_ID,
# AWS_SECRET_ACCESS_KEY, S3_ENDPOINT_URL, S3_BUCKET and S3_PREFIX in the
# environment, loaded without printing them. Set KUBE_CONTEXT to name the
# kubectl context when the default context is not the cluster.
set -eu

fail() {
  printf 'restore: %s\n' "$1" >&2
  exit 1
}

out=${1:-}
[ -n "$out" ] || fail "usage: restore.sh OUTPUT_DIR [OBJECT_NAME]"
: "${AWS_ACCESS_KEY_ID:?}" "${AWS_SECRET_ACCESS_KEY:?}" "${S3_ENDPOINT_URL:?}" "${S3_BUCKET:?}" "${S3_PREFIX:?}"
for tool in gpg kubectl jq; do
  command -v "$tool" > /dev/null || fail "$tool is required"
done
command -v docker > /dev/null || command -v aws > /dev/null || fail "docker or aws is required"

here=$(cd -- "$(dirname -- "$0")" && pwd)
image=amazon/aws-cli:2.36.1@sha256:406ca32d31e640a56e8d52921b40528cc64bfa59ec9cb4ee1456db6746cb7292
namespace=postgres-restore-drill
pod=scratch-1
prefix="${S3_PREFIX%/}/"
mkdir -p "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sha256() {
  if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

# A database name is passed as a quoted dbname= keyword, so a name that
# contains "=" is never parsed as a connection string.
conninfo_db() {
  printf "dbname='%s'" "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")"
}

# The pinned client image when docker is present, a local aws CLI otherwise.
# s3_work is the download directory as the client sees it.
if command -v docker > /dev/null; then
  s3_work=/work
  s3() {
    docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=auto \
      -e AWS_REQUEST_CHECKSUM_CALCULATION=when_required -e AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
      -v "$work:/work" "$image" --endpoint-url "$S3_ENDPOINT_URL" --output json s3api "$@"
  }
else
  s3_work=$work
  s3() {
    AWS_DEFAULT_REGION=auto AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
      AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
      aws --endpoint-url "$S3_ENDPOINT_URL" --output json s3api "$@"
  }
fi

kubectl() {
  command kubectl ${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"} "$@"
}

name=${2:-}
if [ -z "$name" ]; then
  # Only the backup job's own names: postgres-YYYYMMDDTHHMMSSZ.tar.gpg.
  keys=$(s3 list-objects-v2 --bucket "$S3_BUCKET" --prefix "${prefix}postgres-" --query 'Contents[].Key || `[]`')
  key=$(printf '%s' "$keys" \
    | jq -r --arg p "${prefix}postgres-" \
        '.[] | select(startswith($p) and (.[($p | length):] | test("^[0-9]{8}T[0-9]{6}Z\\.tar\\.gpg$")))' \
    | LC_ALL=C sort | tail -n 1)
  [ -n "$key" ] || fail "no backup found under the prefix"
else
  key="${prefix}${name}"
fi
printf 'restore: object %s\n' "${key#"$prefix"}"

meta=$(s3 get-object --bucket "$S3_BUCKET" --key "$key" "$s3_work/backup.tar.gpg")
expected=$(printf '%s' "$meta" | jq -er '.Metadata.sha256')
[ "$(sha256 "$work/backup.tar.gpg")" = "$expected" ] || fail "downloaded object does not match its sha256 metadata"

gpg --batch --quiet --output "$work/backup.tar" --decrypt "$work/backup.tar.gpg"
mkdir "$work/dumps"
tar -C "$work/dumps" -xf "$work/backup.tar"
[ -s "$work/dumps/manifest.tsv" ] || fail "backup has no manifest"
cp "$work/dumps/manifest.tsv" "$out/manifest.tsv"

# pg_restore reads each dump from a file in the pod, not from stdin, which
# is not seekable.
remote=/controller/restore-drill
kubectl -n "$namespace" exec "$pod" -c postgres -- mkdir -p "$remote" < /dev/null

tab=$(printf '\t')
while IFS="$tab" read -r file digest db; do
  [ "$(sha256 "$work/dumps/$file")" = "$digest" ] || fail "dump of $db does not match the manifest"
  if [ "$db" != app ]; then
    kubectl -n "$namespace" exec "$pod" -c postgres -- createdb "$db" < /dev/null
  fi
  kubectl -n "$namespace" cp -c postgres "$work/dumps/$file" "$pod:$remote/$file" < /dev/null
  kubectl -n "$namespace" exec "$pod" -c postgres -- \
    pg_restore --dbname="$(conninfo_db "$db")" --no-owner --no-privileges --exit-on-error "$remote/$file" < /dev/null
  kubectl -n "$namespace" exec "$pod" -c postgres -- rm -f "$remote/$file" < /dev/null
  kubectl -n "$namespace" exec -i "$pod" -c postgres -- \
    psql -X -A -t -v ON_ERROR_STOP=1 -d "$(conninfo_db "$db")" < "$here/checksum.sql" > "$out/after-$file.txt"
  printf 'restore: %s restored, checksums in %s\n' "$db" "$out/after-$file.txt"
done < "$work/dumps/manifest.tsv"
