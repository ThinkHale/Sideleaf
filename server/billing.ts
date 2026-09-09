import Stripe from 'stripe';
import { and, eq } from 'drizzle-orm';
import type { Context } from 'hono';
import { z } from 'zod';
import type { Config } from './config.js';
import type { Database } from './database.js';
import { user } from './schema.js';
import { billingCustomers, billingEvents, billingSubscriptions } from './billing-schema.js';

type BillingContext = Context<{ Variables: { userId: string; signedInAt: Date } }>;
type Transaction = Parameters<Parameters<Database['transaction']>[0]>[0];
type Customer = typeof billingCustomers.$inferSelect;
type Subscription = typeof billingSubscriptions.$inferSelect;
const emptyInput = z.object({}).strict();
const terminal = new Set(['canceled', 'incomplete_expired']);
const active = new Set(['active', 'trialing']);
const id = (value: string | { id: string } | null | undefined) =>
  typeof value === 'string' ? value : value?.id;
async function parseEmptyInput(c: BillingContext) {
  try {
    return emptyInput.parse(await c.req.json());
  } catch {
    throw new BillingError('This billing request is invalid.', 400);
  }
}

export function billingConfiguration(config: Pick<Config, 'production'>) {
  const mode = process.env.STRIPE_MODE || (config.production ? 'live' : 'test');
  const key = process.env.STRIPE_SECRET_KEY || '';
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET || '';
  const priceId = process.env.STRIPE_PRICE_PRO_MONTHLY || '';
  const livemode = mode === 'live';
  const keyMatches = new RegExp(`^(sk|rk)_${livemode ? 'live' : 'test'}_`).test(key);
  const configured =
    ['test', 'live'].includes(mode) &&
    keyMatches &&
    webhookSecret.startsWith('whsec_') &&
    priceId.startsWith('price_');
  return {
    key,
    webhookSecret,
    priceId,
    livemode,
    enabled: configured && process.env.STRIPE_BILLING_ENABLED === 'true',
    // Existing purchases remain manageable while new sales are paused.
    providerReady: ['test', 'live'].includes(mode) && keyMatches,
  };
}

export class BillingError extends Error {
  constructor(
    message: string,
    readonly status: 400 | 404 | 409 | 503 = 503,
  ) {
    super(message);
  }
}

export function subscriptionEntitlement(rows: Subscription[], now = new Date()) {
  const entitled = rows.filter(
    (row) =>
      row.plan === 'pro' &&
      active.has(row.status) &&
      row.currentPeriodEnd &&
      row.currentPeriodEnd > now &&
      (!row.revokedInvoiceId || row.revokedInvoiceId !== row.latestInvoiceId),
  );
  const current = entitled.sort(
    (a, b) => b.currentPeriodEnd!.getTime() - a.currentPeriodEnd!.getTime(),
  )[0];
  const latest =
    current || [...rows].sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime())[0];
  return {
    plan: current ? ('pro' as const) : ('free' as const),
    provider: latest?.provider ?? null,
    status: latest?.status ?? 'free',
    currentPeriodEnd: latest?.currentPeriodEnd?.toISOString() ?? null,
    cancelAtPeriodEnd: latest?.cancelAtPeriodEnd ?? false,
    paymentReview: Boolean(
      latest?.revokedInvoiceId && latest.revokedInvoiceId === latest.latestInvoiceId,
    ),
  };
}

export function createBilling(db: Database, config: Config, injectedStripe?: Stripe) {
  const settings = billingConfiguration(config);
  const stripe =
    injectedStripe ||
    (settings.providerReady
      ? new Stripe(settings.key, { timeout: 6000, maxNetworkRetries: 0 })
      : undefined);
  const ownedCustomer = (uid: string) =>
    and(eq(billingCustomers.userId, uid), eq(billingCustomers.livemode, settings.livemode));
  const ownedSubscriptions = (uid: string) =>
    and(eq(billingSubscriptions.userId, uid), eq(billingSubscriptions.livemode, settings.livemode));
  const requireProvider = () => {
    if (!stripe || !settings.providerReady)
      throw new BillingError('Billing is not connected yet. Your notes remain available.');
    return stripe;
  };
  const guard =
    (handler: (c: BillingContext) => Promise<Response>) => async (c: BillingContext) => {
      try {
        return await handler(c);
      } catch (error) {
        if (error instanceof BillingError) return c.json({ error: error.message }, error.status);
        if (error instanceof z.ZodError)
          return c.json({ error: 'This billing request is invalid.' }, 400);
        return c.json({ error: 'Billing could not be reached. Please try again shortly.' }, 503);
      }
    };
  async function entitlement(uid: string) {
    return subscriptionEntitlement(
      await db.select().from(billingSubscriptions).where(ownedSubscriptions(uid)),
    );
  }
  async function lockCustomer(tx: Transaction, uid: string) {
    const [record] = await tx
      .select()
      .from(billingCustomers)
      .where(ownedCustomer(uid))
      .for('update');
    if (!record) throw new BillingError('Billing account was not found.', 404);
    return record;
  }
  async function syncSubscription(tx: Transaction, customer: Customer, subscriptionId: string) {
    // Retrieve while holding the customer lock. Concurrent/reordered webhooks cannot
    // commit snapshots fetched before a newer reconciliation acquired the lock.
    const subscription = await requireProvider().subscriptions.retrieve(subscriptionId);
    if (
      id(subscription.customer) !== customer.customerId ||
      subscription.livemode !== settings.livemode
    )
      throw new BillingError('The subscription does not belong to this billing account.', 409);
    const [existing] = await tx
      .select()
      .from(billingSubscriptions)
      .where(
        and(
          eq(billingSubscriptions.provider, 'stripe'),
          eq(billingSubscriptions.providerSubscriptionId, subscription.id),
          eq(billingSubscriptions.livemode, settings.livemode),
        ),
      );
    if (existing && existing.userId !== customer.userId)
      throw new BillingError('This subscription is already linked to a different account.', 409);
    const item =
      subscription.items.data.length === 1 && !subscription.items.has_more
        ? subscription.items.data[0]
        : undefined;
    const correctPrice =
      item?.price.id === settings.priceId &&
      item.quantity === 1 &&
      item.price.currency === 'usd' &&
      item.price.unit_amount === Math.round(config.price * 100) &&
      item.price.recurring?.interval === 'month' &&
      item.price.recurring.interval_count === 1;
    const latestInvoiceId = id(subscription.latest_invoice) ?? null;
    const accessEnds = [
      item?.current_period_end,
      subscription.cancel_at,
      ...(subscription.status === 'trialing' ? [subscription.trial_end] : []),
    ].filter((value): value is number => typeof value === 'number' && value > 0);
    const values = {
      userId: customer.userId,
      provider: 'stripe' as const,
      providerSubscriptionId: subscription.id,
      livemode: subscription.livemode,
      priceId: item?.price.id ?? null,
      plan: correctPrice ? ('pro' as const) : ('free' as const),
      status: subscription.pause_collection ? 'paused' : subscription.status,
      currentPeriodEnd: item?.current_period_end ? new Date(Math.min(...accessEnds) * 1000) : null,
      cancelAtPeriodEnd: subscription.cancel_at_period_end || Boolean(subscription.cancel_at),
      latestInvoiceId,
      revokedInvoiceId:
        existing?.revokedInvoiceId === latestInvoiceId ? existing.revokedInvoiceId : null,
      updatedAt: new Date(),
    };
    await tx
      .insert(billingSubscriptions)
      .values({ id: crypto.randomUUID(), ...values })
      .onConflictDoUpdate({
        target: [
          billingSubscriptions.provider,
          billingSubscriptions.providerSubscriptionId,
          billingSubscriptions.livemode,
        ],
        set: values,
      });
    return subscription;
  }

  const status = guard(async (c) => {
    const uid = c.get('userId');
    const [customer] = await db.select().from(billingCustomers).where(ownedCustomer(uid));
    return c.json({
      ...(await entitlement(uid)),
      checkoutReady: settings.enabled,
      portalReady: Boolean(settings.providerReady && customer?.customerId),
      mode: settings.livemode ? 'live' : 'test',
      price: { amount: config.price, currency: 'USD', interval: 'month' },
      message: settings.enabled ? null : 'Subscriptions are not available for purchase yet.',
    });
  });

  const checkout = guard(async (c) => {
    await parseEmptyInput(c);
    if (!settings.enabled)
      throw new BillingError('Subscriptions are not available for purchase yet.');
    const client = requireProvider();
    const uid = c.get('userId');
    const price = await client.prices.retrieve(settings.priceId);
    if (
      !price.active ||
      price.livemode !== settings.livemode ||
      price.type !== 'recurring' ||
      price.currency !== 'usd' ||
      price.unit_amount !== Math.round(config.price * 100) ||
      price.recurring?.interval !== 'month' ||
      price.recurring.interval_count !== 1
    )
      throw new BillingError('The subscription price is not configured correctly.');
    // Commit the attempt ID before any external mutation, preserving idempotency
    // even when a Stripe response arrives after the database transaction fails.
    await db
      .insert(billingCustomers)
      .values({
        userId: uid,
        livemode: settings.livemode,
        checkoutAttempt: crypto.randomUUID(),
      })
      .onConflictDoNothing();
    for (let attempt = 0; attempt < 2; attempt++) {
      const result = await db.transaction(async (tx) => {
        const [account] = await tx.select().from(user).where(eq(user.id, uid)).for('update');
        if (!account) throw new BillingError('The account no longer exists.', 404);
        const customer = await lockCustomer(tx, uid);
        const purchases = await tx
          .select()
          .from(billingSubscriptions)
          .where(ownedSubscriptions(uid));
        if (purchases.some((row) => !terminal.has(row.status)))
          throw new BillingError(
            'You already have a subscription. Manage the existing purchase instead.',
            409,
          );
        let customerId = customer.customerId;
        if (!customerId) {
          const created = await client.customers.create(
            {
              email: account.email,
              name: account.name,
              metadata: { sideleaf_user_id: uid },
            },
            { idempotencyKey: `sideleaf-customer-${settings.livemode}-${uid}` },
          );
          customerId = created.id;
          await tx
            .update(billingCustomers)
            .set({ customerId, updatedAt: new Date() })
            .where(ownedCustomer(uid));
        }
        const current = { ...customer, customerId };
        // Check Stripe too, covering Checkout completion whose webhook is delayed.
        const subscriptions = await client.subscriptions.list({
          customer: customerId,
          status: 'all',
          limit: 100,
        });
        if (subscriptions.has_more)
          throw new BillingError('This billing account needs a support review.', 409);
        const ongoing = subscriptions.data.find((row) => !terminal.has(row.status));
        if (ongoing) {
          await syncSubscription(tx, current, ongoing.id);
          return { existing: true as const };
        }
        const open = await client.checkout.sessions.list({
          customer: customerId,
          status: 'open',
          limit: 100,
        });
        if (open.has_more)
          throw new BillingError('This billing account needs a support review.', 409);
        const reusable = open.data.find(
          (session) =>
            session.mode === 'subscription' &&
            session.client_reference_id === uid &&
            session.metadata?.sideleaf_price_id === settings.priceId,
        );
        if (reusable?.url) return { url: reusable.url };
        if (open.data.some((session) => session.mode === 'subscription'))
          throw new BillingError(
            'Finish or close your existing checkout before starting another.',
            409,
          );
        const session = await client.checkout.sessions.create(
          {
            mode: 'subscription',
            customer: customerId,
            client_reference_id: uid,
            line_items: [{ price: settings.priceId, quantity: 1 }],
            success_url: `${config.origin}/?billing=success`,
            cancel_url: `${config.origin}/?billing=canceled`,
            metadata: { sideleaf_user_id: uid, sideleaf_price_id: settings.priceId },
            subscription_data: { metadata: { sideleaf_user_id: uid } },
          },
          { idempotencyKey: `sideleaf-checkout-${customer.checkoutAttempt}` },
        );
        if (session.status !== 'open' || !session.url) {
          await tx
            .update(billingCustomers)
            .set({
              checkoutAttempt: crypto.randomUUID(),
              checkoutSessionId: null,
              updatedAt: new Date(),
            })
            .where(ownedCustomer(uid));
          return { retry: true as const };
        }
        await tx
          .update(billingCustomers)
          .set({ checkoutSessionId: session.id, updatedAt: new Date() })
          .where(ownedCustomer(uid));
        return { url: session.url };
      });
      if ('existing' in result)
        throw new BillingError(
          'You already have a subscription. Manage the existing purchase instead.',
          409,
        );
      if ('url' in result) return c.json({ url: result.url });
    }
    throw new BillingError('Your previous checkout has expired. Please try again.');
  });

  const portal = guard(async (c) => {
    await parseEmptyInput(c);
    const [customer] = await db
      .select()
      .from(billingCustomers)
      .where(ownedCustomer(c.get('userId')));
    if (!customer?.customerId) throw new BillingError('No web billing account was found.', 404);
    const session = await requireProvider().billingPortal.sessions.create({
      customer: customer.customerId,
      return_url: `${config.origin}/?billing=returned`,
    });
    return c.json({ url: session.url });
  });

  async function expireOpenCheckouts(uid: string) {
    try {
      const [snapshot] = await db.select().from(billingCustomers).where(ownedCustomer(uid));
      if (!snapshot) return { expired: 0 };
      let expired = 0;
      if (snapshot.customerId) {
        const client = requireProvider();
        const sessions = await client.checkout.sessions.list({
          customer: snapshot.customerId,
          status: 'open',
          limit: 100,
        });
        if (sessions.has_more)
          throw new BillingError('This billing account needs a support review.', 409);
        const owned = sessions.data.filter(
          (session) =>
            session.id === snapshot.checkoutSessionId ||
            (session.mode === 'subscription' &&
              session.client_reference_id === uid &&
              session.metadata?.sideleaf_user_id === uid &&
              session.metadata?.sideleaf_price_id === settings.priceId),
        );
        for (const session of owned) {
          try {
            await client.checkout.sessions.expire(session.id);
          } catch (error) {
            let current: Stripe.Checkout.Session;
            try {
              current = await client.checkout.sessions.retrieve(session.id);
            } catch {
              throw error;
            }
            if (id(current.customer) && id(current.customer) !== snapshot.customerId)
              throw new BillingError('The checkout does not belong to this billing account.', 409);
            if (current.status === 'open') throw error;
          }
        }
        expired = owned.length;
      }
      const stable = await db.transaction(async (tx) => {
        const [account] = await tx
          .select({ id: user.id })
          .from(user)
          .where(eq(user.id, uid))
          .for('update');
        if (!account) throw new BillingError('The account no longer exists.', 404);
        const [current] = await tx
          .select()
          .from(billingCustomers)
          .where(ownedCustomer(uid))
          .for('update');
        if (!current) return false;
        if (
          current.customerId !== snapshot.customerId ||
          current.checkoutAttempt !== snapshot.checkoutAttempt ||
          current.checkoutSessionId !== snapshot.checkoutSessionId
        )
          return false;
        await tx
          .update(billingCustomers)
          .set({
            checkoutAttempt: crypto.randomUUID(),
            checkoutSessionId: null,
            updatedAt: new Date(),
          })
          .where(ownedCustomer(uid));
        return true;
      });
      if (!stable)
        throw new BillingError(
          'Billing activity changed while cleanup was running. Please retry.',
          409,
        );
      return { expired };
    } catch (error) {
      if (error instanceof BillingError) throw error;
      throw new BillingError(
        'Unfinished checkout cleanup could not be completed. Please retry shortly.',
      );
    }
  }

  const expireOpenCheckoutsRoute = guard(async (c) => {
    await parseEmptyInput(c);
    return c.json(await expireOpenCheckouts(c.get('userId')));
  });

  async function reconcileCharge(tx: Transaction, customer: Customer, event: Stripe.Event) {
    const client = requireProvider();
    const isDispute = event.type.startsWith('charge.dispute.');
    const object = event.data.object as Stripe.Charge | Stripe.Dispute;
    const dispute = isDispute ? await client.disputes.retrieve(object.id) : undefined;
    const chargeId = dispute ? id(dispute.charge) : object.id;
    if (!chargeId) return;
    const charge = await client.charges.retrieve(chargeId);
    if (id(charge.customer) !== customer.customerId || charge.livemode !== settings.livemode)
      return;
    const intentId = id(charge.payment_intent);
    if (!intentId) return;
    const payments = await client.invoicePayments.list({
      payment: { type: 'payment_intent', payment_intent: intentId },
      limit: 100,
    });
    if (payments.has_more) throw new BillingError('The payment needs additional reconciliation.');
    for (const payment of payments.data) {
      const invoice = await client.invoices.retrieve(id(payment.invoice)!);
      const subscriptionId = id(invoice.parent?.subscription_details?.subscription);
      if (!subscriptionId || id(invoice.customer) !== customer.customerId) continue;
      const subscription = await syncSubscription(tx, customer, subscriptionId);
      if (id(subscription.latest_invoice) !== invoice.id) continue;
      const revoke =
        charge.refunded || Boolean(dispute && !['won', 'warning_closed'].includes(dispute.status));
      if (revoke || dispute)
        await tx
          .update(billingSubscriptions)
          .set({
            revokedInvoiceId: revoke ? invoice.id : null,
            updatedAt: new Date(),
          })
          .where(
            and(
              eq(billingSubscriptions.provider, 'stripe'),
              eq(billingSubscriptions.providerSubscriptionId, subscription.id),
              eq(billingSubscriptions.livemode, settings.livemode),
            ),
          );
    }
  }

  // This route is intentionally authenticated by Stripe's raw-body signature,
  // not by a browser Origin header or the user's session cookie.
  const webhook = async (c: BillingContext) => {
    c.header('Cache-Control', 'no-store');
    if (!stripe || !settings.webhookSecret)
      return c.json({ error: 'Billing webhook is not configured.' }, 503);
    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(
        await c.req.text(),
        c.req.header('stripe-signature') || '',
        settings.webhookSecret,
      );
    } catch {
      return c.json({ error: 'Invalid billing signature.' }, 400);
    }
    if (event.livemode !== settings.livemode) return c.json({ received: true });
    const relevant =
      event.type.startsWith('customer.subscription.') ||
      [
        'checkout.session.completed',
        'checkout.session.async_payment_succeeded',
        'invoice.paid',
        'invoice.payment_failed',
        'invoice.payment_action_required',
        'charge.refunded',
        'charge.dispute.created',
        'charge.dispute.closed',
      ].includes(event.type);
    if (!relevant) return c.json({ received: true });
    try {
      await db.transaction(async (tx) => {
        const inserted = await tx
          .insert(billingEvents)
          .values({ id: event.id, type: event.type, livemode: event.livemode })
          .onConflictDoNothing()
          .returning({ id: billingEvents.id });
        if (!inserted.length) return;
        const object = event.data.object;
        let customerId: string | undefined;
        if ('customer' in object)
          customerId = id(object.customer as string | { id: string } | null);
        if (event.type.startsWith('charge.dispute.')) {
          const charge = await requireProvider().charges.retrieve(
            id((object as Stripe.Dispute).charge)!,
          );
          customerId = id(charge.customer);
        }
        if (!customerId) return;
        const [customer] = await tx
          .select()
          .from(billingCustomers)
          .where(
            and(
              eq(billingCustomers.customerId, customerId),
              eq(billingCustomers.livemode, settings.livemode),
            ),
          )
          .for('update');
        // Metadata and customer email never establish ownership.
        if (!customer) return;
        if (event.type.startsWith('charge.')) return reconcileCharge(tx, customer, event);
        let subscriptionId: string | undefined;
        if (object.object === 'subscription') subscriptionId = object.id;
        else if (object.object === 'checkout.session') subscriptionId = id(object.subscription);
        else if (object.object === 'invoice')
          subscriptionId = id(object.parent?.subscription_details?.subscription);
        if (subscriptionId) await syncSubscription(tx, customer, subscriptionId);
      });
      return c.json({ received: true });
    } catch {
      // No event is recorded on failure. Stripe's retry can safely reconcile it.
      return c.json({ error: 'Billing update could not be processed. Please retry.' }, 503);
    }
  };

  async function beforeAccountDeletion(uid: string, executor: Database | Transaction = db) {
    const purchases = await executor
      .select()
      .from(billingSubscriptions)
      .where(eq(billingSubscriptions.userId, uid));
    if (purchases.some((row) => !terminal.has(row.status)))
      throw new BillingError(
        'End your subscription before deleting the account so future billing can be stopped.',
        409,
      );
    const customers = await executor
      .select()
      .from(billingCustomers)
      .where(eq(billingCustomers.userId, uid));
    for (const customer of customers) {
      if (!customer.customerId) continue;
      if (customer.livemode !== settings.livemode)
        throw new BillingError(
          'This account has billing in another environment. Contact support before deletion.',
          409,
        );
      const subscriptions = await requireProvider().subscriptions.list({
        customer: customer.customerId,
        status: 'all',
        limit: 100,
      });
      const sessions = await requireProvider().checkout.sessions.list({
        customer: customer.customerId,
        status: 'open',
        limit: 100,
      });
      if (
        subscriptions.has_more ||
        subscriptions.data.some((row) => !terminal.has(row.status)) ||
        sessions.has_more ||
        sessions.data.length
      )
        throw new BillingError(
          'Finish or cancel pending billing before deleting your account.',
          409,
        );
    }
  }
  return {
    webhook,
    status,
    checkout,
    portal,
    expireOpenCheckouts,
    expireOpenCheckoutsRoute,
    entitlement,
    beforeAccountDeletion,
  };
}
