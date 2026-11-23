#!/bin/bash
# Runs once, when the data directory is empty (postgres entrypoint initdb phase),
# after the demo dump (40-dhis2-dump.sql.gz, fetched at build time) has been loaded.
#   DHIS2_ADMIN_PASSWORD    replaces the publicly known demo password of user "admin"
#   DHIS2_DISABLE_DEMO_USERS=true  disables every other account in the demo DB
set -euo pipefail
PSQL=(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -q)

if ! "${PSQL[@]}" -tAc "SELECT to_regclass('public.userinfo')" | grep -q userinfo; then
  echo "dhis2-init: no demo dump loaded; DHIS2 will initialise an empty database (default login admin/district!)" >&2
  exit 0
fi

if [ -n "${DHIS2_ADMIN_PASSWORD:-}" ]; then
  "${PSQL[@]}" -v pw="$DHIS2_ADMIN_PASSWORD" -v disable="${DHIS2_DISABLE_DEMO_USERS:-false}" <<'SQL'
-- Own schema: the DHIS2 dump defines public.gen_random_uuid(), which clashes with pgcrypto in public.
CREATE SCHEMA IF NOT EXISTS dhis2init;
CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA dhis2init;
SELECT set_config('dhis2init.pw', :'pw', false), set_config('dhis2init.disable', :'disable', false);
-- DHIS2 stores BCrypt hashes in userinfo.password; pgcrypto 'bf' produces compatible $2a$ hashes.
-- Guarded so an unexpected schema warns instead of aborting database initialisation.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'userinfo' AND column_name = 'password') THEN
    UPDATE userinfo SET password = dhis2init.crypt(current_setting('dhis2init.pw'), dhis2init.gen_salt('bf', 10)) WHERE username = 'admin';
    RAISE NOTICE 'dhis2-init: admin password replaced';
  ELSE
    RAISE WARNING 'dhis2-init: userinfo.password not found — change the admin password in the DHIS2 UI';
  END IF;
  IF current_setting('dhis2init.disable') = 'true'
     AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'userinfo' AND column_name = 'disabled') THEN
    UPDATE userinfo SET disabled = true WHERE username <> 'admin';
    RAISE NOTICE 'dhis2-init: demo users disabled';
  END IF;
END $$;
SQL
else
  echo "dhis2-init: WARNING DHIS2_ADMIN_PASSWORD not set — demo login admin/district is active" >&2
fi
