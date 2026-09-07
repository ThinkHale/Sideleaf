# Supabase database certificate

`supabase-root-2021.crt` is the public Supabase root certificate downloaded on 2026-09-07 from [Supabase's certificate distribution](https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt). The download URL was verified against the [official dashboard configuration](https://github.com/supabase/supabase/blob/master/apps/studio/hooks/custom-content/custom-content.json), key `ssl:certificate_url`. It is not a private key or account credential.

SHA-256 fingerprint: `80:70:25:AD:50:D4:ED:21:9D:2C:9C:7D:29:9C:00:4F:82:4E:B0:0C:F7:F6:5A:FE:F6:07:D0:7B:72:E6:CA:FA`. The certificate expires on 2031-04-26.

The deployed PostgreSQL connection uses `sslmode=verify-full` and `sslrootcert=server/certs/supabase-root-2021.crt`. Vercel includes the certificate in its API function bundle. Keep hostname and certificate verification enabled when rotating this CA. Source guidance: https://supabase.com/docs/guides/platform/ssl-enforcement.
