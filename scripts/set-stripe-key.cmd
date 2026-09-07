@echo off
echo This saves your Stripe server key to Vercel. Input stays hidden.
echo Purchases remain disabled until billing is configured and explicitly enabled.
node "%~dp0set-provider-secret.mjs" STRIPE_SECRET_KEY %*
