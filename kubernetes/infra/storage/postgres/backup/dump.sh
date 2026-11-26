#!/bin/sh
# Dumps every connectable non-template database except "postgres" in custom
# format, packs the dumps into one tar stream and encrypts it to an OpenPGP
# public key. The cluster holds no private key, so it cannot read old backups.
#
# Inputs: PG* connection variables, RECIPIENT_FILE, WORK_DIR, MAX_OBJECT_BYTES.
# Output: $WORK_DIR/backup.tar.gpg for the upload container.
set -eu

fail() {
  printf 'dump: %s\n' "$1" >&2
  exit 1
}

: "${RECIPIENT_FILE:?}" "${WORK_DIR:?}" "${MAX_OBJECT_BYTES:?}"
[ -s "$RECIPIENT_FILE" ] || fail "recipient public key is missing"

# A database name is passed as a quoted dbname= keyword, so a name that
# contains "=" is never parsed as a connection string.
conninfo_db() {
  printf "dbname='%s'" "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")"
}

umask 077
stage="$WORK_DIR/stage"
out="$WORK_DIR/backup.tar.gpg"
rm -rf "$stage" "$out"
mkdir -p "$stage" "$GNUPGHOME"

psql -X -A -t -v ON_ERROR_STOP=1 -d postgres -c \
  "SELECT datname FROM pg_catalog.pg_database
   WHERE datallowconn AND NOT datistemplate AND datname <> 'postgres'
   ORDER BY datname" > "$WORK_DIR/databases"
[ -s "$WORK_DIR/databases" ] || fail "no database to dump"

# Files are numbered so a database name never becomes a path.
index=0
: > "$stage/manifest.tsv"
while IFS= read -r db; do
  index=$((index + 1))
  file=$(printf '%03d.dump' "$index")
  pg_dump --format=custom --file="$stage/$file" --dbname="$(conninfo_db "$db")" < /dev/null
  printf '%s\t%s\t%s\n' "$file" "$(sha256sum "$stage/$file" | cut -d' ' -f1)" "$db" >> "$stage/manifest.tsv"
done < "$WORK_DIR/databases"
printf 'dump: %d database(s) dumped\n' "$index"

# No pipeline: POSIX sh would hide a tar failure behind a successful gpg.
tar -C "$stage" -cf "$WORK_DIR/backup.tar" .
rm -rf "$stage"
gpg --batch --no-tty --quiet --trust-model always --compress-algo none \
  --recipient-file "$RECIPIENT_FILE" --output "$out" --encrypt "$WORK_DIR/backup.tar"
rm -f "$WORK_DIR/backup.tar"

size=$(wc -c < "$out" | tr -d ' ')
[ "$size" -gt 0 ] || fail "encrypted backup is empty"
[ "$size" -le "$MAX_OBJECT_BYTES" ] || fail "encrypted backup is $size bytes, above the $MAX_OBJECT_BYTES-byte object bound"
printf 'dump: encrypted backup is %s bytes\n' "$size"
