$ErrorActionPreference = 'Stop'
$sideleafCliBin = Join-Path $env:LOCALAPPDATA 'Sideleaf\cli\node_modules\.bin'
$sideleafVercel = Join-Path $sideleafCliBin 'vercel.cmd'
$sideleafSupabase = Join-Path $sideleafCliBin 'supabase.cmd'

if (-not (Test-Path -LiteralPath $sideleafVercel) -or -not (Test-Path -LiteralPath $sideleafSupabase)) {
    throw 'The Sideleaf CLI tools are missing on this computer. Ask Codex to install them here first.'
}

Write-Host 'Sign in to Vercel using the browser flow shown below.'
& $sideleafVercel login
if ($LASTEXITCODE -ne 0) { throw 'Vercel sign-in did not complete. Run this script again to retry.' }

Write-Host 'Sign in to Supabase. Complete its browser flow and any verification prompt in this terminal.'
& $sideleafSupabase login --agent no
if ($LASTEXITCODE -ne 0) { throw 'Supabase sign-in did not complete. Run this script again to retry.' }

Write-Host 'Both sign-ins completed. Tell Codex to continue. No provider API keys are needed in chat.'
