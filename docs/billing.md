# Billing and assisted usage

Sideleaf has a Free plan and a proposed $29 USD monthly Pro subscription. Manual notes, saved pages and exports remain available on Free. Free assisted usage defaults to 120 minutes per month and 60 minutes per meeting. Pro is intended to remove those product limits while allowing one active assisted session per account. Provider limits and reliability still apply; the recording implementation describes its current duration behavior separately.

Stripe web billing is implemented behind configuration flags. No Stripe account, product, price, live charge or native purchase integration has been created by this change. Checkout stays unavailable until the server has matching credentials, a monthly Price and a webhook signing secret, and an operator enables billing.

## Web purchase flow

The authenticated application sends an empty body to `POST /api/billing/checkout`. The server creates or reuses the account's Stripe customer and opens hosted Checkout in subscription mode. The customer and Price IDs come from the backend. Checkout validates that the configured Price is active, recurring monthly, quantity one, USD and equal to `PRO_PRICE_USD`. An existing subscription or unfinished checkout is reused or sent to management rather than starting a second purchase.

`POST /api/billing/portal` creates a short-lived Stripe customer portal link for the signed-in account. The portal provides billing details, payment method management, invoices and cancellation according to the Stripe account's configured portal settings. The application never handles card details. [Stripe Checkout Sessions](https://docs.stripe.com/api/checkout/sessions/create), [customer portal integration](https://docs.stripe.com/customer-management/integrate-customer-portal).

`GET /api/billing` returns the authenticated account's plan, provider, status, renewal or access-end timestamp, pending cancellation, payment review state, availability of checkout/portal, environment and displayed price. A checkout return URL never grants Pro.

## Authoritative access and privacy

The private Supabase schema stores Stripe customer mappings, subscription snapshots and processed webhook event IDs. Stripe test and live records have separate mode fields, and a test purchase cannot unlock the production entitlement. Only server-side provider verification writes subscriptions. The model names Apple and Google as future providers; there are no client-accessible native entitlement grants or pretend receipt validators.

`POST /api/billing/webhook` verifies Stripe's signature against the unparsed request body before processing. It is exempt only from browser session and Origin checks. Delivery IDs are deduplicated within the same database transaction as the subscription update. A failed update rolls back its event receipt so Stripe can retry. Reconciliation locks the customer's billing row and then retrieves the subscription from Stripe, preventing older event payloads or simultaneous deliveries from overwriting authoritative state. Ownership comes from the server-created customer mapping, never from email or user IDs in event metadata. Payment payloads, card details and user notes are not retained in the event table. [Stripe webhook handling](https://docs.stripe.com/webhooks).

Active and trialing subscriptions with a recognized Price grant Pro only through their verified access-end timestamp. Period information is read from the subscription item. Scheduled cancellation preserves access until its end. Delinquency, paused collection, cancellation, expiration or an unrecognized price removes Pro without deleting notes. A full refund of the latest invoice or a disputed current payment suspends its Pro access. Winning or closing a warning dispute can restore access, and a subsequent valid paid period clears a prior invoice hold. Refunding an older invoice does not revoke a newer paid period. A refund alone does not cancel future Stripe renewals; cancellation remains an explicit billing operation. [Stripe subscription object](https://docs.stripe.com/api/subscriptions/object), [subscription events](https://docs.stripe.com/billing/subscriptions/webhooks), [invoice payment linkage](https://docs.stripe.com/api/invoice-payment/list).

Account deletion checks for active or pending purchases before removing the billing link. The delete operation must hold the account row lock while checking and deleting, using the same lock order as checkout. An account with unresolved billing receives an actionable error instead of losing the relationship needed to stop future renewals. Financial records retained by Stripe follow the Stripe account's retention obligations.

## Configuration and activation

Keep these values in Vercel server environment variables, never `VITE_*`, source control, native configuration or a client bundle:

| Variable                   | Purpose                                                                    |
| -------------------------- | -------------------------------------------------------------------------- |
| `STRIPE_SECRET_KEY`        | Server SDK credential, `sk_test_...` or `sk_live_...` in the matching mode |
| `STRIPE_WEBHOOK_SECRET`    | `whsec_...` signing secret for this exact endpoint and environment         |
| `STRIPE_PRICE_PRO_MONTHLY` | Configured recurring monthly Price ID                                      |
| `STRIPE_MODE`              | `test` for sandbox validation, `live` for production                       |
| `STRIPE_BILLING_ENABLED`   | Explicit `true` enables new purchases; default is unavailable              |
| `PRO_PRICE_USD`            | Displayed price and server validation amount, default `29`                 |

No publishable Stripe key is needed for the hosted redirect flow. The SDK version is pinned in the lockfile; Stripe 22.6.1 uses API `2026-08-26.dahlia`. Configure the webhook endpoint to use this same API version so invoice parent and subscription item fields match.

Stripe CLI 1.50.10 is installed on this Windows computer at `%LOCALAPPDATA%\Sideleaf\cli\stripe\stripe.exe`. `scripts/connect-stripe.cmd` starts Stripe's browser sign-in with project profile `sideleaf`. The CLI configuration is stored outside OneDrive at `%LOCALAPPDATA%\Sideleaf\secrets\stripe-cli.toml`. The owner needs to create a Stripe account before signing in. CLI sign-in does not create a Price, enable purchases or replace the deployed runtime/webhook credentials. Stripe activation remains pending.

On the configured Windows checkout, `scripts/set-stripe-key.cmd preview` prompts with hidden input and sends a sandbox key to Vercel's preview environment. Without the `preview` argument, the launcher targets production. The shared helper also accepts `STRIPE_WEBHOOK_SECRET`. It writes no secret file and sends the value through CLI stdin. Updated server environment variables require a new deployment. A production key must match `STRIPE_MODE=live`; configuring keys alone never enables purchases.

The production webhook URL is `https://sideleaf.vercel.app/api/billing/webhook`. Subscribe to `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `customer.subscription.paused`, `customer.subscription.resumed`, `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `invoice.paid`, `invoice.payment_failed`, `invoice.payment_action_required`, `charge.refunded`, `charge.dispute.created` and `charge.dispute.closed`. Use a separate sandbox endpoint and secret when testing. Webhook delivery must reach a public endpoint; Vercel preview protection needs a deliberate testing configuration.

Before enabling live purchases, connect the Stripe account, create the agreed monthly Price in a sandbox, configure and exercise the customer portal, and complete a real sandbox checkout through signed webhook delivery. Cover payment recovery, cancellation, refund, dispute and re-subscription. Configure customer-facing business details and cancellation/tax settings for the intended launch market. Then create the corresponding live Price and endpoint, set live secrets, and explicitly enable production billing. Local tests use the real Stripe signature verifier with mocked provider calls; they do not replace a Stripe sandbox purchase.

## iOS, iPadOS and Android

Stripe, Apple's App Store and Google Play are separate purchase channels. Stripe supports Apple Pay and Google Pay as payment wallets in eligible web checkouts; those wallets are different from StoreKit subscriptions and Google Play Billing. Stripe does not turn a web subscription into an App Store or Play subscription. Sideleaf can make the purchased benefits follow the same authenticated account across devices. [Stripe wallet support](https://docs.stripe.com/payments/wallets).

The recommended native implementation is StoreKit for iOS/iPadOS and Google Play Billing for a future Android app. Each channel sends verified server-side purchase state into the same Sideleaf entitlement model. Restore purchases, store server notifications, renewals, refunds and revocations remain native implementation work. Before presenting a purchase, check the account for an existing entitlement from any channel; management should lead back to the original seller.

Apple's current guideline 3.1.3(b) permits access to subscriptions bought on other platforms or a website when those items are also available as in-app purchases in the app. The current U.S. storefront rules permit external purchase links; other storefronts have different conditions and programs. A note-taking app should not assume it qualifies for the reader-app exception. Review the selected storefronts immediately before submitting the native purchase flow. [Apple App Review Guidelines, sections 3.1.1 and 3.1.3](https://developer.apple.com/app-store/review/guidelines/).

Google Play generally requires Play Billing for in-app digital subscriptions unless a relevant exception or enrolled alternative billing program applies. Regional programs have their own eligibility, disclosures, reporting and fees. Google states that U.S. developers enrolled in its external-link or alternative-billing programs must report transactions and pay applicable service fees starting October 1, 2026. These regional options should be evaluated separately from the shared entitlement design. [Google Play Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738), [Google's current U.S. policy updates](https://support.google.com/googleplay/android-developer/answer/15582165?hl=en).

Official provider and storefront references were reviewed on September 7, 2026. Native purchase policies can change before Sideleaf's store launch.

## Economics

Validate the proposed $29 price against measured transcription usage, text-model costs, infrastructure, payment/store fees and support. Keep usage telemetry limited to non-content quantities such as active seconds, provider/model IDs, request counts and estimated cost. Unlimited assisted usage transfers heavy-user cost to Sideleaf; one active session and transparent anti-abuse controls are the intended protection, not an undisclosed monthly cap. This change does not claim a verified gross margin or a completed store economics review.
