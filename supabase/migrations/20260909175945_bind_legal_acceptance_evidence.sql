BEGIN;
SET LOCAL search_path = sideleaf;

ALTER TABLE legal_acceptances
  ADD COLUMN legal_bundle_sha256 text NOT NULL
  DEFAULT 'ea207ddf60331f6b136fe4fdf3749484827d97315dc8e8a726c5febecdc5af64';
ALTER TABLE legal_acceptances ALTER COLUMN legal_bundle_sha256 DROP DEFAULT;
ALTER TABLE legal_acceptances
  ADD CONSTRAINT legal_acceptances_bundle_sha256
  CHECK (legal_bundle_sha256 ~ '^[0-9a-f]{64}$');

COMMIT;
