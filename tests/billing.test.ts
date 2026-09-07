import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import Stripe from 'stripe';
import { Hono } from 'hono';
import { eq } from 'drizzle-orm';
import { openDatabase } from '../server/database';
import { billingConfiguration, createBilling, subscriptionEntitlement } from '../server/billing';
import { billingCustomers, billingEvents, billingSubscriptions } from '../server/billing-schema';
import { user } from '../server/schema';

const origin = 'https://sideleaf.example';
const secret = 'whsec_synthetic_billing_test';
const config = {
  production: false,
  origin,
  secret: 'test-auth-secret',
  name: 'Sideleaf',
  freeMinutes: 120,
  meetingMinutes: 60,
  price: 29,
};
let storage: Awaited<ReturnType<typeof openDatabase>>;
let billing: ReturnType<typeof createBilling>;
let app: Hono<{ Variables: { userId: string; signedInAt: Date } }>;
const signer = new Stripe('sk_test_synthetic');
const stripe = {
  webhooks: signer.webhooks,
  prices: { retrieve: vi.fn() },
  customers: { create: vi.fn() },
  subscriptions: { retrieve: vi.fn(), list: vi.fn() },
  checkout: { sessions: { create: vi.fn(), list: vi.fn() } },
  billingPortal: { sessions: { create: vi.fn() } },
  charges: { retrieve: vi.fn() },
  disputes: { retrieve: vi.fn() },
  invoicePayments: { list: vi.fn() },
  invoices: { retrieve: vi.fn() },
};
const price = {
  id: 'price_pro',
  active: true,
  type: 'recurring',
  livemode: false,
  currency: 'usd',
  unit_amount: 2900,
  recurring: { interval: 'month', interval_count: 1 },
};
function subscription(overrides: Record<string, unknown> = {}) {
  return {
    id: 'sub_alice',
    object: 'subscription',
    customer: 'cus_alice',
    livemode: false,
    status: 'active',
    cancel_at_period_end: false,
    pause_collection: null,
    latest_invoice: 'in_current',
    metadata: { sideleaf_user_id: 'bob' },
    items: {
      has_more: false,
      data: [
        {
          id: 'si_pro',
          quantity: 1,
          price,
          current_period_start: Math.floor(Date.now() / 1000),
          current_period_end: Math.floor(Date.now() / 1000) + 86400,
        },
      ],
    },
    ...overrides,
  };
}
function setup() {
  billing = createBilling(storage.db, config, stripe as unknown as Stripe);
  app = new Hono<{ Variables: { userId: string; signedInAt: Date } }>();
  app.post('/api/billing/webhook', billing.webhook);
  app.use('/api/*', async (c, next) => {
    const uid = c.req.header('x-test-user');
    if (!uid) return c.json({ error: 'Sign in' }, 401);
    c.set('userId', uid);
    c.set('signedInAt', new Date());
    await next();
  });
  app.get('/api/billing', billing.status);
  app.post('/api/billing/checkout', billing.checkout);
  app.post('/api/billing/portal', billing.portal);
}
function request(path = '', uid = 'alice', method = 'GET', body?: unknown) {
  return app.request(`${origin}/api/billing${path}`, {
    method,
    headers: { 'x-test-user': uid, 'Content-Type': 'application/json', origin },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}
async function customer(uid = 'alice', livemode = false) {
  await storage.db.insert(billingCustomers).values({
    userId: uid,
    livemode,
    customerId: `cus_${uid}${livemode ? '_live' : ''}`,
    checkoutAttempt: crypto.randomUUID(),
  });
}
function delivery(eventId: string, type: string, object = subscription(), extra = {}) {
  const payload = JSON.stringify({
    id: eventId,
    object: 'event',
    type,
    livemode: false,
    created: Math.floor(Date.now() / 1000),
    data: { object },
    ...extra,
  });
  return app.request(`${origin}/api/billing/webhook`, {
    method: 'POST',
    body: payload,
    headers: { 'stripe-signature': signer.webhooks.generateTestHeaderString({ payload, secret }) },
  });
}
beforeAll(async () => {
  storage = await openDatabase(undefined, ':memory:');
});
afterAll(async () => {
  await storage.close();
});
beforeEach(async () => {
  vi.stubEnv('STRIPE_SECRET_KEY', 'sk_test_synthetic');
  vi.stubEnv('STRIPE_PRICE_PRO_MONTHLY', 'price_pro');
  vi.stubEnv('STRIPE_WEBHOOK_SECRET', secret);
  vi.stubEnv('STRIPE_BILLING_ENABLED', 'true');
  vi.stubEnv('STRIPE_MODE', 'test');
  vi.clearAllMocks();
  await storage.db.delete(billingEvents);
  await storage.db.delete(user);
  await storage.db.insert(user).values(
    ['alice', 'bob'].map((uid) => ({
      id: uid,
      email: `${uid}@example.test`,
      name: uid,
      createdAt: new Date(),
      updatedAt: new Date(),
    })),
  );
  stripe.prices.retrieve.mockResolvedValue(price);
  stripe.customers.create.mockImplementation(async ({ metadata }) => ({
    id: `cus_${metadata.sideleaf_user_id}`,
  }));
  stripe.subscriptions.list.mockResolvedValue({ data: [], has_more: false });
  stripe.subscriptions.retrieve.mockResolvedValue(subscription());
  stripe.checkout.sessions.list.mockResolvedValue({ data: [], has_more: false });
  stripe.checkout.sessions.create.mockResolvedValue({
    id: 'cs_alice',
    status: 'open',
    url: 'https://checkout.stripe.com/test',
  });
  stripe.billingPortal.sessions.create.mockResolvedValue({
    url: 'https://billing.stripe.com/test',
  });
  setup();
});
afterEach(() => {
  vi.unstubAllEnvs();
});

describe.sequential('Stripe billing boundaries', () => {
  it('keeps purchases disabled when credentials or the explicit switch are missing', async () => {
    vi.stubEnv('STRIPE_WEBHOOK_SECRET', '');
    setup();
    const response = await request('/checkout', 'alice', 'POST', {});
    expect(response.status).toBe(503);
    expect((await (await request()).json()).checkoutReady).toBe(false);
    expect(stripe.customers.create).not.toHaveBeenCalled();
    vi.stubEnv('STRIPE_MODE', 'live');
    expect(billingConfiguration(config).providerReady).toBe(false);
  });
  it('rejects unsigned or modified webhook bodies without recording them', async () => {
    const payload = JSON.stringify({ id: 'evt_forged' });
    const response = await app.request(`${origin}/api/billing/webhook`, {
      method: 'POST',
      body: `${payload} `,
      headers: {
        'stripe-signature': signer.webhooks.generateTestHeaderString({ payload, secret }),
      },
    });
    expect(response.status).toBe(400);
    expect(await storage.db.select().from(billingEvents)).toEqual([]);
  });
  it('uses the authenticated customer and fixed price and does not grant access on Checkout creation', async () => {
    expect((await request('/checkout', 'alice', 'POST', { priceId: 'price_cheaper' })).status).toBe(
      400,
    );
    const response = await request('/checkout', 'alice', 'POST', {});
    expect(response.status, await response.clone().text()).toBe(200);
    expect(stripe.checkout.sessions.create).toHaveBeenCalledWith(
      expect.objectContaining({
        customer: 'cus_alice',
        client_reference_id: 'alice',
        mode: 'subscription',
        line_items: [{ price: 'price_pro', quantity: 1 }],
        success_url: `${origin}/?billing=success`,
      }),
      expect.objectContaining({ idempotencyKey: expect.stringMatching(/^sideleaf-checkout-/) }),
    );
    expect((await (await request()).json()).plan).toBe('free');
    expect((await request('/checkout', '', 'POST', {})).status).toBe(401);
  });
  it('refuses a mismatched Stripe amount before creating a billing account', async () => {
    stripe.prices.retrieve.mockResolvedValueOnce({ ...price, unit_amount: 100 });
    expect((await request('/checkout', 'alice', 'POST', {})).status).toBe(503);
    expect(stripe.customers.create).not.toHaveBeenCalled();
  });
  it('reuses an open Checkout instead of starting a second purchase', async () => {
    await customer();
    stripe.checkout.sessions.list.mockResolvedValue({
      has_more: false,
      data: [
        {
          id: 'cs_existing',
          mode: 'subscription',
          client_reference_id: 'alice',
          metadata: { sideleaf_price_id: 'price_pro' },
          url: 'https://checkout.stripe.com/existing',
        },
      ],
    });
    const response = await request('/checkout', 'alice', 'POST', {});
    expect(await response.json()).toEqual({ url: 'https://checkout.stripe.com/existing' });
    expect(stripe.checkout.sessions.create).not.toHaveBeenCalled();
  });
  it('serializes concurrent Checkout requests for the same customer', async () => {
    const openSession = {
      id: 'cs_concurrent',
      status: 'open',
      mode: 'subscription',
      client_reference_id: 'alice',
      metadata: { sideleaf_price_id: 'price_pro' },
      url: 'https://checkout.stripe.com/concurrent',
    };
    stripe.checkout.sessions.create.mockImplementationOnce(async () => {
      stripe.checkout.sessions.list.mockResolvedValue({ data: [openSession], has_more: false });
      return openSession;
    });
    const responses = await Promise.all([
      request('/checkout', 'alice', 'POST', {}),
      request('/checkout', 'alice', 'POST', {}),
    ]);
    expect(responses.map((response) => response.status)).toEqual([200, 200]);
    expect(stripe.customers.create).toHaveBeenCalledTimes(1);
    expect(stripe.checkout.sessions.create).toHaveBeenCalledTimes(1);
  });
  it('checks Stripe for an existing purchase when its webhook has not arrived', async () => {
    await customer();
    stripe.subscriptions.list.mockResolvedValue({ has_more: false, data: [subscription()] });
    expect((await request('/checkout', 'alice', 'POST', {})).status).toBe(409);
    expect((await billing.entitlement('alice')).plan).toBe('pro');
    expect(stripe.checkout.sessions.create).not.toHaveBeenCalled();
  });
  it('uses customer ownership instead of webhook metadata and deduplicates deliveries', async () => {
    await customer();
    await customer('bob');
    expect((await delivery('evt_first', 'customer.subscription.created')).status).toBe(200);
    expect((await billing.entitlement('alice')).plan).toBe('pro');
    expect((await billing.entitlement('bob')).plan).toBe('free');
    expect((await delivery('evt_first', 'customer.subscription.created')).status).toBe(200);
    expect(stripe.subscriptions.retrieve).toHaveBeenCalledTimes(1);
    expect((await storage.db.select().from(billingEvents)).length).toBe(1);
  });
  it('deduplicates concurrently delivered copies before provider reconciliation', async () => {
    await customer();
    const responses = await Promise.all([
      delivery('evt_parallel', 'customer.subscription.updated'),
      delivery('evt_parallel', 'customer.subscription.updated'),
    ]);
    expect(responses.map((response) => response.status)).toEqual([200, 200]);
    expect(stripe.subscriptions.retrieve).toHaveBeenCalledTimes(1);
  });
  it('ignores unknown customers and events from another Stripe mode', async () => {
    expect((await delivery('evt_unknown', 'customer.subscription.created')).status).toBe(200);
    await customer();
    expect(
      (
        await delivery('evt_live', 'customer.subscription.created', subscription(), {
          livemode: true,
        })
      ).status,
    ).toBe(200);
    expect((await billing.entitlement('alice')).plan).toBe('free');
    expect(stripe.subscriptions.retrieve).not.toHaveBeenCalled();
  });
  it('rejects a retrieved subscription belonging to a different customer and retries failures', async () => {
    await customer();
    stripe.subscriptions.retrieve.mockResolvedValueOnce(subscription({ customer: 'cus_bob' }));
    expect((await delivery('evt_retry', 'customer.subscription.updated')).status).toBe(503);
    expect(await storage.db.select().from(billingEvents)).toEqual([]);
    expect((await delivery('evt_retry', 'customer.subscription.updated')).status).toBe(200);
    expect((await billing.entitlement('alice')).plan).toBe('pro');
  });
  it('retrieves the current subscription for stale events and removes delinquent access', async () => {
    await customer();
    await delivery('evt_active', 'customer.subscription.created');
    stripe.subscriptions.retrieve.mockResolvedValue(subscription({ status: 'past_due' }));
    await delivery('evt_older_active', 'customer.subscription.updated', subscription());
    expect((await billing.entitlement('alice')).plan).toBe('free');
    expect((await billing.entitlement('alice')).status).toBe('past_due');
  });
  it('keeps a paid cancellation until period end, then revokes cancellation and expiry', async () => {
    await customer();
    stripe.subscriptions.retrieve.mockResolvedValue(subscription({ cancel_at_period_end: true }));
    await delivery('evt_cancel_scheduled', 'customer.subscription.updated');
    expect(await billing.entitlement('alice')).toMatchObject({
      plan: 'pro',
      cancelAtPeriodEnd: true,
    });
    const rows = await storage.db.select().from(billingSubscriptions);
    expect(subscriptionEntitlement(rows, new Date(Date.now() + 2 * 86400000)).plan).toBe('free');
    stripe.subscriptions.retrieve.mockResolvedValue(subscription({ status: 'canceled' }));
    await delivery('evt_canceled', 'customer.subscription.deleted');
    expect((await billing.entitlement('alice')).plan).toBe('free');
  });
  it('caps access at a flexible billing cancellation timestamp', async () => {
    await customer();
    const cancelAt = Math.floor(Date.now() / 1000) + 3600;
    stripe.subscriptions.retrieve.mockResolvedValue(subscription({ cancel_at: cancelAt }));
    await delivery('evt_flexible_cancel', 'customer.subscription.updated');
    expect(await billing.entitlement('alice')).toMatchObject({
      cancelAtPeriodEnd: true,
      currentPeriodEnd: new Date(cancelAt * 1000).toISOString(),
    });
  });
  it('does not grant Pro for an unrelated price or non-unit subscription quantity', async () => {
    await customer();
    const wrong = subscription();
    wrong.items.data[0].quantity = 2;
    stripe.subscriptions.retrieve.mockResolvedValue(wrong);
    await delivery('evt_wrong_quantity', 'customer.subscription.created');
    expect((await billing.entitlement('alice')).plan).toBe('free');
  });
  it('reads the current Invoice parent subscription format', async () => {
    await customer();
    const invoice = {
      id: 'in_current',
      object: 'invoice',
      customer: 'cus_alice',
      parent: { type: 'subscription_details', subscription_details: { subscription: 'sub_alice' } },
    };
    expect(
      (
        await delivery(
          'evt_invoice',
          'invoice.paid',
          invoice as unknown as ReturnType<typeof subscription>,
        )
      ).status,
    ).toBe(200);
    expect((await billing.entitlement('alice')).plan).toBe('pro');
  });
  it('revokes a fully refunded current invoice and restores access after a new paid period', async () => {
    await customer();
    await delivery('evt_original', 'customer.subscription.created');
    const charge = {
      id: 'ch_current',
      object: 'charge',
      customer: 'cus_alice',
      livemode: false,
      payment_intent: 'pi_current',
      refunded: true,
    };
    stripe.charges.retrieve.mockResolvedValue(charge);
    stripe.invoicePayments.list.mockResolvedValue({
      has_more: false,
      data: [{ invoice: 'in_current' }],
    });
    stripe.invoices.retrieve.mockResolvedValue({
      id: 'in_current',
      customer: 'cus_alice',
      parent: { subscription_details: { subscription: 'sub_alice' } },
    });
    expect(
      (
        await delivery(
          'evt_refund',
          'charge.refunded',
          charge as unknown as ReturnType<typeof subscription>,
        )
      ).status,
    ).toBe(200);
    expect(await billing.entitlement('alice')).toMatchObject({ plan: 'free', paymentReview: true });
    await delivery('evt_repeat_active', 'customer.subscription.updated');
    expect((await billing.entitlement('alice')).plan).toBe('free');
    stripe.subscriptions.retrieve.mockResolvedValue(subscription({ latest_invoice: 'in_renewal' }));
    await delivery('evt_renewed', 'customer.subscription.updated');
    expect((await billing.entitlement('alice')).plan).toBe('pro');
  });
  it('keeps sandbox entitlements out of live status', async () => {
    await customer();
    await delivery('evt_test', 'customer.subscription.created');
    expect((await billing.entitlement('alice')).plan).toBe('pro');
    vi.stubEnv('STRIPE_MODE', 'live');
    vi.stubEnv('STRIPE_SECRET_KEY', 'sk_live_synthetic');
    setup();
    expect((await billing.entitlement('alice')).plan).toBe('free');
  });
  it('suspends disputed current payments and restores a won dispute', async () => {
    await customer();
    await delivery('evt_paid_before_dispute', 'customer.subscription.created');
    const dispute = {
      id: 'dp_current',
      object: 'dispute',
      charge: 'ch_current',
      status: 'needs_response',
    };
    stripe.disputes.retrieve.mockResolvedValue(dispute);
    stripe.charges.retrieve.mockResolvedValue({
      id: 'ch_current',
      customer: 'cus_alice',
      livemode: false,
      payment_intent: 'pi_current',
      refunded: false,
      disputed: true,
    });
    stripe.invoicePayments.list.mockResolvedValue({
      has_more: false,
      data: [{ invoice: 'in_current' }],
    });
    stripe.invoices.retrieve.mockResolvedValue({
      id: 'in_current',
      customer: 'cus_alice',
      parent: { subscription_details: { subscription: 'sub_alice' } },
    });
    expect(
      (
        await delivery(
          'evt_dispute',
          'charge.dispute.created',
          dispute as unknown as ReturnType<typeof subscription>,
        )
      ).status,
    ).toBe(200);
    expect((await billing.entitlement('alice')).plan).toBe('free');
    stripe.disputes.retrieve.mockResolvedValue({ ...dispute, status: 'won' });
    expect(
      (
        await delivery(
          'evt_dispute_won',
          'charge.dispute.closed',
          dispute as unknown as ReturnType<typeof subscription>,
        )
      ).status,
    ).toBe(200);
    expect((await billing.entitlement('alice')).plan).toBe('pro');
  });
  it('opens only the signed-in customer portal and blocks orphaning an active subscription', async () => {
    await customer();
    await customer('bob');
    expect((await request('/portal', 'alice', 'POST', { customer: 'cus_bob' })).status).toBe(400);
    expect((await request('/portal', 'alice', 'POST', {})).status).toBe(200);
    expect(stripe.billingPortal.sessions.create).toHaveBeenCalledWith({
      customer: 'cus_alice',
      return_url: `${origin}/?billing=returned`,
    });
    await delivery('evt_delete_guard', 'customer.subscription.created');
    await expect(billing.beforeAccountDeletion('alice')).rejects.toMatchObject({ status: 409 });
    expect((await storage.db.select().from(user).where(eq(user.id, 'alice'))).length).toBe(1);
  });
  it('checks billing inside the account deletion transaction without a second database connection', async () => {
    await customer();
    await storage.db.transaction(async (tx) => {
      await tx.select().from(user).where(eq(user.id, 'alice')).for('update');
      await billing.beforeAccountDeletion('alice', tx);
      await tx.delete(user).where(eq(user.id, 'alice'));
    });
    expect(await storage.db.select().from(user).where(eq(user.id, 'alice'))).toEqual([]);
    expect(await storage.db.select().from(billingCustomers)).toEqual([]);
  });
});
