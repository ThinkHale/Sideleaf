BEGIN;
SET LOCAL search_path = sideleaf;

CREATE TABLE legal_acceptances (
  user_id text NOT NULL REFERENCES auth_user(id) ON DELETE CASCADE,
  terms_version text NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  recording_law_acknowledged_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, terms_version)
);
CREATE INDEX legal_acceptances_owner ON legal_acceptances(user_id);

ALTER TABLE sideleaf.legal_acceptances ENABLE ROW LEVEL SECURITY;
CREATE POLICY sideleaf_backend ON sideleaf.legal_acceptances
  FOR ALL TO sideleaf_runtime
  USING (true)
  WITH CHECK (true);
REVOKE ALL ON sideleaf.legal_acceptances FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON sideleaf.legal_acceptances TO sideleaf_runtime;

COMMIT;
