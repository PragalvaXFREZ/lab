#!/bin/sh
# Measures every object in the bucket, including other components' objects,
# and fails when the total is above WARN_BYTES. The failed Job is the
# bucket-size warning; it writes nothing.
#
# Inputs: AWS_* credentials, S3_ENDPOINT_URL, S3_BUCKET, WARN_BYTES.
set -eu

fail() {
  printf 'bucket-usage: %s\n' "$1" >&2
  exit 1
}

: "${AWS_ACCESS_KEY_ID:?}" "${AWS_SECRET_ACCESS_KEY:?}" "${S3_ENDPOINT_URL:?}" "${S3_BUCKET:?}" "${WARN_BYTES:?}"
case "$WARN_BYTES" in
  '' | *[!0-9]*) fail "WARN_BYTES must be a non-negative integer" ;;
esac

# JSON output, not text: with text output the CLI applies --query to each
# page separately and the totals would cover only the first 1000 objects.
listing=$(aws --endpoint-url "$S3_ENDPOINT_URL" --output json s3api list-objects-v2 --bucket "$S3_BUCKET" \
  --query '{objects: length(Contents || `[]`), bytes: sum(Contents[].Size || `[]`)}') \
  || fail "cannot list the bucket"
objects=$(printf '%s' "$listing" | jq -er '.objects') || fail "unexpected listing"
bytes=$(printf '%s' "$listing" | jq -er '.bytes | floor') || fail "unexpected listing"

printf 'bucket-usage: objects=%s bucket_bytes=%s warn_bytes=%s\n' "$objects" "$bytes" "$WARN_BYTES"
[ "$bytes" -le "$WARN_BYTES" ] || fail "bucket usage is above the warning threshold"
printf 'bucket-usage: below the warning threshold\n'
