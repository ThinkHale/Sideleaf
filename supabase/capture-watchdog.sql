-- Run as the project administrator after creating sideleaf_capture_cron in Vault.
-- The job stores only a Vault reference, never a literal secret.
SELECT cron.schedule('sideleaf-capture-watchdog', '30 seconds', $job$
  SELECT net.http_get(
    url := 'https://sideleaf.vercel.app/api/capture/maintenance',
    headers := jsonb_build_object('Authorization', 'Bearer ' ||
      (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'sideleaf_capture_cron')),
    timeout_milliseconds := 20000
  );
$job$);
SELECT cron.schedule('sideleaf-capture-cron-history', '17 3 * * *', $job$
  DELETE FROM cron.job_run_details
  WHERE jobid IN (SELECT jobid FROM cron.job WHERE jobname IN ('sideleaf-capture-watchdog', 'sideleaf-capture-cron-history'))
    AND end_time < now() - interval '7 days';
$job$);
