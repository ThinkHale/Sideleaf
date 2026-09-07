@echo off
setlocal
set "SIDELEAF_STRIPE=%LOCALAPPDATA%\Sideleaf\cli\stripe\stripe.exe"
if not exist "%SIDELEAF_STRIPE%" (
  echo The Sideleaf Stripe CLI is not installed on this computer.
  exit /b 1
)
if not exist "%LOCALAPPDATA%\Sideleaf\secrets" mkdir "%LOCALAPPDATA%\Sideleaf\secrets"
"%SIDELEAF_STRIPE%" --config "%LOCALAPPDATA%\Sideleaf\secrets\stripe-cli.toml" --project-name sideleaf login
if errorlevel 1 exit /b 1
echo Stripe sign-in completed. Tell Codex it is ready.
endlocal
