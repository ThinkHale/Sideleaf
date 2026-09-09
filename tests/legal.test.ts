import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { createHash } from 'node:crypto';
import type Stripe from 'stripe';
import { eq } from 'drizzle-orm';
import { createApp } from '../server/app';
import { openDatabase } from '../server/database';
import { billingCustomers } from '../server/billing-schema';
import { captureSessions } from '../server/capture-schema';
import type { CaptureProvider } from '../server/openai-capture';
import { legalAcceptances, notebooks, pages, user } from '../server/schema';
import { emptyDocument } from '../shared/domain';
import {
  CURRENT_LEGAL_BUNDLE_SHA256,
  CURRENT_TERMS_VERSION,
  PRIVACY_SECTIONS,
  RECORDING_LAW_ACKNOWLEDGEMENT,
  TERMS_EFFECTIVE_AT,
  TERMS_SECTIONS,
} from '../shared/legal';

const origin = 'https://sideleaf-legal.example';
let storage: Awaited<ReturnType<typeof openDatabase>>;
let app: ReturnType<typeof createApp>;
let openCheckouts: Array<Record<string, unknown>> = [];
const stripe = {
  subscriptions: {
    list: vi.fn(async () => ({ has_more: false, data: [] })),
  },
  checkout: {
    sessions: {
      list: vi.fn(async ({ customer }: { customer: string }) => ({
        has_more: false,
        data: openCheckouts.filter(
          (session) => session.customer === customer && session.status === 'open',
        ),
      })),
      expire: vi.fn(async (id: string) => {
        const session = openCheckouts.find((candidate) => candidate.id === id);
        if (!session) throw new Error('Synthetic checkout not found.');
        session.status = 'expired';
        return session;
      }),
      retrieve: vi.fn(async (id: string) => {
        const session = openCheckouts.find((candidate) => candidate.id === id);
        if (!session) throw new Error('Synthetic checkout not found.');
        return session;
      }),
    },
  },
};
const captureHangup = vi.fn(async () => undefined);
const captureProvider = {
  create: vi.fn(),
  observe: vi.fn(),
  hangup: captureHangup,
} as unknown as CaptureProvider;

function request(
  path: string,
  cookie = '',
  method = 'GET',
  body?: unknown,
  requestOrigin = origin,
) {
  return app.request(`${origin}/api${path}`, {
    method,
    headers: {
      origin: requestOrigin,
      cookie,
      'content-type': 'application/json',
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

async function register(email: string) {
  const response = await request('/auth/sign-up/email', '', 'POST', {
    name: 'Legal Test User',
    email,
    password: 'Synthetic-legal-password-47',
  });
  expect(response.status, await response.clone().text()).toBe(200);
  return response.headers
    .getSetCookie()
    .map((value) => value.split(';')[0])
    .join('; ');
}

const acceptance = {
  termsVersion: CURRENT_TERMS_VERSION,
  acceptedTerms: true,
  recordingLawAcknowledged: true,
};

beforeAll(async () => {
  vi.stubEnv('STRIPE_SECRET_KEY', 'sk_test_synthetic');
  vi.stubEnv('STRIPE_MODE', 'test');
  storage = await openDatabase(undefined, ':memory:');
  app = createApp(
    storage.db,
    {
      origin,
      secret: 'synthetic-legal-secret-0000000000000000000000000',
      production: false,
      name: 'Sideleaf',
      freeMinutes: 120,
      meetingMinutes: 60,
      price: 29,
    },
    {
      stripe: stripe as unknown as Stripe,
      captureProvider,
    },
  );
});

afterAll(async () => {
  await storage.close();
  vi.unstubAllEnvs();
});

describe.sequential('versioned legal acceptance', () => {
  let alice = '';

  it('publishes the current legal metadata without authentication', async () => {
    const response = await request('/config');
    expect(response.status).toBe(200);
    expect((await response.json()).legal).toMatchObject({
      termsVersion: CURRENT_TERMS_VERSION,
      effectiveAt: '2026-09-09',
      termsUrl: `${origin}/terms`,
      privacyUrl: `${origin}/privacy`,
    });
  });

  it('pins the accepted legal copy to the declared version fingerprint', () => {
    const canonical = JSON.stringify({
      termsVersion: CURRENT_TERMS_VERSION,
      effectiveAt: TERMS_EFFECTIVE_AT,
      recordingLawAcknowledgement: RECORDING_LAW_ACKNOWLEDGEMENT,
      termsSections: TERMS_SECTIONS,
      privacySections: PRIVACY_SECTIONS,
    });
    expect(createHash('sha256').update(canonical).digest('hex')).toBe(CURRENT_LEGAL_BUNDLE_SHA256);
  });

  it('requires authentication for legal status and acceptance', async () => {
    expect((await request('/legal/status')).status).toBe(401);
    expect((await request('/legal/acceptance', '', 'POST', acceptance)).status).toBe(401);
  });

  it('gates a new account without inventing an acceptance record', async () => {
    alice = await register('legal-alice@example.test');
    const status = await request('/legal/status', alice);
    expect(await status.json()).toMatchObject({
      accepted: false,
      acceptedAt: null,
      recordingLawAcknowledgedAt: null,
    });
    const blocked = await request('/notebooks', alice);
    expect(blocked.status).toBe(428);
    expect(await blocked.json()).toMatchObject({
      code: 'TERMS_ACCEPTANCE_REQUIRED',
      legal: { termsVersion: CURRENT_TERMS_VERSION },
    });
    expect(await storage.db.select().from(legalAcceptances)).toEqual([]);
  });

  it('requires the exact current legal bundle fingerprint', async () => {
    const [aliceUser] = await storage.db
      .select({ id: user.id })
      .from(user)
      .where(eq(user.email, 'legal-alice@example.test'));
    const now = new Date();
    await storage.db.insert(legalAcceptances).values({
      userId: aliceUser.id,
      termsVersion: CURRENT_TERMS_VERSION,
      acceptedAt: now,
      recordingLawAcknowledgedAt: now,
      legalBundleSha256: '0'.repeat(64),
    });

    expect(await (await request('/legal/status', alice)).json()).toMatchObject({ accepted: false });
    expect((await request('/notebooks', alice)).status).toBe(428);

    await storage.db.delete(legalAcceptances).where(eq(legalAcceptances.userId, aliceUser.id));
  });

  it('rejects incomplete, false, and cross-origin assent', async () => {
    for (const body of [
      { ...acceptance, acceptedTerms: false },
      { ...acceptance, recordingLawAcknowledged: false },
      { termsVersion: CURRENT_TERMS_VERSION },
    ]) {
      const response = await request('/legal/acceptance', alice, 'POST', body);
      expect(response.status).toBe(400);
    }
    expect(
      (await request('/legal/acceptance', alice, 'POST', acceptance, 'https://untrusted.example'))
        .status,
    ).toBe(403);
    expect(await storage.db.select().from(legalAcceptances)).toEqual([]);
  });

  it('returns the current metadata when submitted assent is stale', async () => {
    const response = await request('/legal/acceptance', alice, 'POST', {
      ...acceptance,
      termsVersion: '2026-01-01.1',
    });
    expect(response.status).toBe(428);
    expect(await response.json()).toMatchObject({
      code: 'TERMS_ACCEPTANCE_REQUIRED',
      legal: {
        termsVersion: CURRENT_TERMS_VERSION,
        effectiveAt: TERMS_EFFECTIVE_AT,
        termsUrl: `${origin}/terms`,
        privacyUrl: `${origin}/privacy`,
      },
    });
    expect(await storage.db.select().from(legalAcceptances)).toEqual([]);
  });

  it('rejects malformed acceptance JSON without converting it to a server error', async () => {
    const response = await app.request(`${origin}/api/legal/acceptance`, {
      method: 'POST',
      headers: {
        origin,
        cookie: alice,
        'content-type': 'application/json',
      },
      body: '{',
    });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: 'Invalid legal acceptance data.' });
  });

  it('records server-owned timestamps and is idempotent', async () => {
    const first = await request('/legal/acceptance', alice, 'POST', {
      ...acceptance,
      acceptedAt: '2000-01-01T00:00:00.000Z',
    });
    expect(first.status).toBe(400);

    const accepted = await request('/legal/acceptance', alice, 'POST', acceptance);
    expect(accepted.status, await accepted.clone().text()).toBe(200);
    const value = await accepted.json();
    expect(value).toMatchObject({
      accepted: true,
      legal: { termsVersion: CURRENT_TERMS_VERSION },
    });
    expect(new Date(value.acceptedAt).getTime()).toBeGreaterThan(Date.UTC(2026, 0, 1));
    expect(value.recordingLawAcknowledgedAt).toBe(value.acceptedAt);
    expect((await request('/legal/acceptance', alice, 'POST', acceptance)).status).toBe(200);

    const rows = await storage.db
      .select()
      .from(legalAcceptances)
      .where(eq(legalAcceptances.termsVersion, CURRENT_TERMS_VERSION));
    expect(rows).toHaveLength(1);
    expect(rows[0].legalBundleSha256).toBe(CURRENT_LEGAL_BUNDLE_SHA256);
    expect((await request('/notebooks', alice)).status).toBe(200);
  });

  it('exports the acceptance while keeping account exit and capture teardown available', async () => {
    const exported = await request('/account/export', alice);
    expect(exported.status).toBe(200);
    expect((await exported.json()).legalAcceptances).toHaveLength(1);

    const unaccepted = await register('legal-bob@example.test');
    const [bob] = await storage.db
      .select({ id: user.id })
      .from(user)
      .where(eq(user.email, 'legal-bob@example.test'));
    const notebookId = crypto.randomUUID();
    const pageId = crypto.randomUUID();
    await storage.db.insert(notebooks).values({ id: notebookId, userId: bob.id, name: 'Exit' });
    await storage.db.insert(pages).values({
      id: pageId,
      userId: bob.id,
      notebookId,
      title: 'Active meeting',
      document: emptyDocument(),
    });
    await storage.db.insert(billingCustomers).values({
      userId: bob.id,
      livemode: false,
      customerId: 'cus_legal_bob',
      checkoutAttempt: crypto.randomUUID(),
      checkoutSessionId: 'cs_legal_bob_cleanup',
    });
    const seedCapture = async (suffix: string) => {
      const now = new Date();
      const id = crypto.randomUUID();
      await storage.db.insert(captureSessions).values({
        id,
        userId: bob.id,
        pageId,
        callId: `call_legal_bob_${suffix}`,
        state: 'live',
        createdAt: now,
        activeAt: now,
        lastBilledAt: now,
        leaseExpiresAt: new Date(now.getTime() + 25_000),
        deadlineAt: new Date(now.getTime() + 60_000),
      });
      return id;
    };
    const seedCheckout = async (suffix: string) => {
      const id = `cs_legal_bob_${suffix}`;
      openCheckouts.push({
        id,
        status: 'open',
        customer: 'cus_legal_bob',
        mode: 'subscription',
        client_reference_id: bob.id,
        metadata: { sideleaf_price_id: 'price_pro' },
      });
      await storage.db
        .update(billingCustomers)
        .set({ checkoutAttempt: crypto.randomUUID(), checkoutSessionId: id })
        .where(eq(billingCustomers.userId, bob.id));
      return id;
    };

    expect((await request('/account/export', unaccepted)).status).toBe(200);
    expect((await request('/notebooks', unaccepted)).status).toBe(428);
    expect(
      (
        await request(`/capture/sessions/${crypto.randomUUID()}/stop`, unaccepted, 'POST', {
          reason: 'stopped',
        })
      ).status,
    ).toBe(404);
    expect(
      (await request(`/capture/sessions/${crypto.randomUUID()}/heartbeat`, unaccepted, 'POST', {}))
        .status,
    ).toBe(428);
    expect(
      (await request(`/capture/sessions/${crypto.randomUUID()}/events`, unaccepted)).status,
    ).toBe(428);

    captureHangup.mockClear();
    stripe.checkout.sessions.expire.mockClear();
    const routeCaptureId = await seedCapture('route');
    const routeCheckoutId = await seedCheckout('route');
    const stopped = await request('/capture/sessions/stop-all', unaccepted, 'POST', {});
    expect(stopped.status, await stopped.clone().text()).toBe(200);
    expect(await stopped.json()).toEqual({ stopped: 1 });
    expect(captureHangup).toHaveBeenCalledWith('call_legal_bob_route');
    expect(
      (
        await storage.db
          .select()
          .from(captureSessions)
          .where(eq(captureSessions.id, routeCaptureId))
      )[0].state,
    ).toBe('stopped');
    const expired = await request('/billing/checkout/expire', unaccepted, 'POST', {});
    expect(expired.status, await expired.clone().text()).toBe(200);
    expect(await expired.json()).toEqual({ expired: 1 });
    expect(stripe.checkout.sessions.expire).toHaveBeenCalledWith(routeCheckoutId);

    await seedCapture('delete');
    const deleteCheckoutId = await seedCheckout('delete');
    expect(
      (await request('/account', unaccepted, 'DELETE', { confirmation: 'DELETE' })).status,
    ).toBe(200);
    expect(captureHangup).toHaveBeenCalledWith('call_legal_bob_delete');
    expect(stripe.checkout.sessions.expire).toHaveBeenCalledWith(deleteCheckoutId);
    expect(await storage.db.select().from(user).where(eq(user.id, bob.id))).toEqual([]);
  });

  it('cascades immutable acceptance history when the account is deleted', async () => {
    const [aliceUser] = await storage.db
      .select({ id: user.id })
      .from(user)
      .where(eq(user.email, 'legal-alice@example.test'));
    expect(aliceUser).toBeTruthy();
    expect((await request('/account', alice, 'DELETE', { confirmation: 'DELETE' })).status).toBe(
      200,
    );
    expect(
      await storage.db
        .select()
        .from(legalAcceptances)
        .where(eq(legalAcceptances.userId, aliceUser.id)),
    ).toEqual([]);
  });
});
