-- Prints one line per ordinary table: name, row count, and an MD5 digest of
-- the rows in a fixed order. Run with psql -X -A -t so the output can be
-- diffed between the source cluster and a restore.
SELECT format(
         'SELECT %L, count(*), md5(coalesce(string_agg(t::text, E''\n'' ORDER BY t::text), '''')) FROM %I.%I AS t',
         n.nspname || '.' || c.relname, n.nspname, c.relname)
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg\_toast%'
ORDER BY n.nspname, c.relname
\gexec
