-- This provider-created function is used only by the ensure_rls event trigger.
-- Keep its definition, ownership, trigger, and administrative grants intact.
-- API roles have no reason to execute this SECURITY DEFINER function directly.
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable()
  FROM PUBLIC, anon, authenticated;
