BEGIN;

DROP POLICY sideleaf_backend ON sideleaf.legal_acceptances;
CREATE POLICY sideleaf_backend_select ON sideleaf.legal_acceptances
  FOR SELECT TO sideleaf_runtime
  USING (true);
CREATE POLICY sideleaf_backend_insert ON sideleaf.legal_acceptances
  FOR INSERT TO sideleaf_runtime
  WITH CHECK (true);

COMMIT;
