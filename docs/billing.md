# Billing and assisted usage

Billing is not implemented in this slice. Settings shows a clearly labeled plan preview. There is no checkout, portal, webhook endpoint, StoreKit purchase, Pro flag, charge, or hidden simulated entitlement. No paid resources have been created.

## Product configuration

`FREE_MONTHLY_MINUTES=120`, `FREE_MEETING_MINUTES=60`, and `PRO_PRICE_USD=29` are configurable launch-test defaults. Free ordinary note-taking is not metered. Saved pages and exports are always accessible to their owner in the current build. Pro is intended to have unlimited assisted minutes with no product-imposed duration or monthly cap and one active assisted session per account.

The preview is not an offer to charge a customer. There is no allowance period or reset date yet because assisted sessions do not exist. Do not display fictitious usage or enable capture before the metering slice is implemented.

## Required implementation

1. Persist one authoritative entitlement record per user, independent of purchase channel. Never trust a client plan, local cache, checkout redirect, or unsigned notification.
2. Store allowance-period start/end instants and publish the exact reset timestamp in the user's timezone. Store active intervals in milliseconds, idempotent usage-event IDs and authenticated session leases. Serialize lease creation so reconnects cannot create concurrent assisted sessions.
3. Exclude pauses and known provider/capture interruptions. Reserve only a bounded lease window and reconcile monotonic accepted intervals. Offline native assisted entitlements must not grant unlimited unmetered time; choose and document a bounded signed lease policy. Offline manual notes stay unlimited.
4. Warn before exhaustion. Stop accepting new assisted capture at the free limit, release microphone tracks and finalize received text without discarding notes. Provider-imposed session limits require a real tested rollover strategy or an honest interruption.
5. Web: implement Stripe subscription Checkout and customer portal, verify webhook signatures against the raw body, deduplicate event IDs, fetch authoritative subscription state for reordered events, and cover upgrade, cancellation, delinquency, refund and revocation. Avoid creating a second subscription when an active purchase exists on either channel.
6. Native: use StoreKit subscriptions and verified transactions, link the transaction to the authenticated backend account, validate server notifications and transaction history, and implement restore purchases. Do not embed web checkout until the target storefront's current rules and any required entitlements have been reviewed.
7. Test signed/invalid/replayed/out-of-order events, revocation, billing failures, expired leases, concurrent streams, offline reconciliation and account isolation. Only then connect the product's paid controls.

## Official references reviewed 2026-09-06

Stripe's [subscription webhook documentation](https://docs.stripe.com/billing/subscriptions/webhooks) covers asynchronous changes, payment failures and refunds and requires verifying webhook authenticity. Subscription state must drive access rather than the checkout return page.

Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) govern in-app digital purchases and storefront-specific purchase-link rules. Native purchase implementation and a storefront review are still outstanding. This document does not claim that every storefront permits the same external checkout flow.

## Economics to validate before launch

Unlimited usage transfers long-session and heavy-user cost risk to the service. Measure only non-content quantities: active seconds, provider request counts, token counts, model/provider IDs, processing latency and estimated service cost. Do not log transcripts or preparation as cost telemetry.

Evaluate the $29 test price against the selected provider's non-training price, text-model consumption, infrastructure, payment/store fees, support costs and the distribution of heavy usage. One active session and transparent anti-abuse controls are the intended protections. A hidden monthly cap is not a substitute for validating the economics. No current provider cost estimate is asserted here, since no provider or purchase account was configured.
