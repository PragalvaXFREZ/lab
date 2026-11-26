-- Prints one line per ordinary table (schema, table, row count, MD5 of the
-- rows in a fixed order), one line per sequence (schema, sequence, last
-- value, is_called), and a last line with the MD5 of all lines above.
-- Run with psql -X -A -t -v ON_ERROR_STOP=1 and compare two runs with diff.
-- Quiet mode keeps command tags such as INSERT 0 1 out of the output.
\set QUIET on
SET TimeZone = 'UTC';
SET DateStyle = 'ISO, YMD';
SET IntervalStyle = 'postgres';
SET bytea_output = 'hex';
SET extra_float_digits = 1;

CREATE TEMPORARY TABLE checksum_lines (line text NOT NULL);

SELECT format(
         'INSERT INTO checksum_lines SELECT %L || ''|'' || count(*) || ''|'' || '
         'md5(coalesce(string_agg(t::text, E''\n'' ORDER BY t::text COLLATE "C"), '''')) '
         'FROM %I.%I AS t',
         'table|' || n.nspname || '|' || c.relname, n.nspname, c.relname)
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND c.relpersistence <> 't'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg\_toast%'
  AND n.nspname NOT LIKE 'pg\_temp\_%'
ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C"
\gexec

SELECT format(
         'INSERT INTO checksum_lines SELECT %L || ''|'' || last_value || ''|'' || is_called FROM %I.%I',
         'sequence|' || n.nspname || '|' || c.relname, n.nspname, c.relname)
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'S'
  AND c.relpersistence <> 't'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg\_toast%'
  AND n.nspname NOT LIKE 'pg\_temp\_%'
ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C"
\gexec

SELECT line FROM checksum_lines ORDER BY line COLLATE "C";
SELECT 'overall|' || md5(coalesce(string_agg(line, E'\n' ORDER BY line COLLATE "C"), '')) FROM checksum_lines;
