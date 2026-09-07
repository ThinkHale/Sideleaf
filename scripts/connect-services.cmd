@echo off
setlocal
set "SIDELEAF_CLI_BIN=%LOCALAPPDATA%\Sideleaf\cli\node_modules\.bin"
if not exist "%SIDELEAF_CLI_BIN%\vercel.cmd" (
  echo Sideleaf CLI tools are missing on this computer. Ask Codex to install them here first.
  exit /b 1
)
if not exist "%SIDELEAF_CLI_BIN%\supabase.cmd" (
  echo Sideleaf CLI tools are missing on this computer. Ask Codex to install them here first.
  exit /b 1
)
echo Sign in to Vercel using the browser flow shown below.
call "%SIDELEAF_CLI_BIN%\vercel.cmd" login
if errorlevel 1 exit /b 1
echo Sign in to Supabase, then complete its verification prompt in this terminal.
call "%SIDELEAF_CLI_BIN%\supabase.cmd" login --agent no
if errorlevel 1 exit /b 1
echo Both sign-ins completed. Tell Codex to continue.
endlocal
