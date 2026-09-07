BEGIN;
-- pg_net is not relocatable. Recreate this newly installed watchdog extension
-- under extensions rather than exposing its extension entry in public.
-- Its short-lived HTTP request/response telemetry is cleared by this change.
DROP EXTENSION pg_net;
CREATE EXTENSION pg_net WITH SCHEMA extensions;
REVOKE USAGE ON SCHEMA net FROM PUBLIC, anon, authenticated, sideleaf_runtime;
COMMIT;
