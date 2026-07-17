#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s PLANNED_DATA_BYTES\n' "$0" >&2
  exit 2
}

planned_bytes=${1:-}
[[ "$planned_bytes" =~ ^[0-9]+$ ]] || usage
[[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || { printf 'AWS_ACCESS_KEY_ID is required\n' >&2; exit 2; }
[[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] || { printf 'AWS_SECRET_ACCESS_KEY is required\n' >&2; exit 2; }
command -v docker >/dev/null || { printf 'docker is required\n' >&2; exit 2; }

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
values_file="$script_dir/values.yaml"
bucket=$(awk '/^[[:space:]]*bucket:/ { value=$2; gsub(/"/, "", value); print value; exit }' "$values_file")
endpoint=$(awk '/^[[:space:]]*s3Url:/ { value=$2; gsub(/"/, "", value); print value; exit }' "$values_file")

hard_ceiling_bytes=1000000000
metadata_reserve_bytes=100000000
aws_cli_image=${AWS_CLI_IMAGE:-amazon/aws-cli@sha256:406ca32d31e640a56e8d52921b40528cc64bfa59ec9cb4ee1456db6746cb7292}
docker_env=(-e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=auto)
if [[ -n "${AWS_SESSION_TOKEN:-}" ]]; then
  docker_env+=(-e AWS_SESSION_TOKEN)
fi

read -r object_count current_bytes < <(
  docker run --rm "${docker_env[@]}" "$aws_cli_image" \
    --endpoint-url "$endpoint" \
    s3api list-objects-v2 \
    --bucket "$bucket" \
    --query '[length(Contents || `[]`),sum(Contents[].Size || `[]`)]' \
    --output text
)

worst_case_bytes=$((current_bytes + planned_bytes + metadata_reserve_bytes))
printf 'objects=%d current_bytes=%d\n' "$object_count" "$current_bytes"
printf 'planned_data_bytes=%d metadata_reserve_bytes=%d\n' "$planned_bytes" "$metadata_reserve_bytes"
printf 'worst_case_projected_bytes=%d hard_ceiling_bytes=%d\n' "$worst_case_bytes" "$hard_ceiling_bytes"

if (( worst_case_bytes >= hard_ceiling_bytes )); then
  printf 'capacity guard failed: the planned backup does not leave the required safety reserve\n' >&2
  exit 1
fi

printf 'capacity guard passed\n'
