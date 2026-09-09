import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { Hono } from 'hono';
import { eq } from 'drizzle-orm';
import { openDatabase } from '../server/database';
import { createApp } from '../server/app';
import { calendarPeriod, createCapture, usageIntervals } from '../server/capture';
import {
  captureSessions,
  captureUsage,
  captureWatchdog,
  meetingTranscripts,
} from '../server/capture-schema';
import { notebooks, pages, user } from '../server/schema';
import { emptyDocument } from '../shared/domain';
import { CURRENT_TERMS_VERSION } from '../shared/legal';
import type { CaptureObserver, CaptureProvider, ProviderEvent } from '../server/openai-capture';

const origin = 'https://sideleaf.example';
const config = {
  production: false,
  origin,
  secret: 'synthetic-capture-test-secret',
  name: 'Sideleaf',
  freeMinutes: 120,
  meetingMinutes: 60,
  price: 29,
};
const alicePage = '3aba1592-76a3-4c81-b006-3d482a854160';
const bobPage = '476bb3df-a0df-49e6-8b9d-fe4571609a4c';
const sdp = 'v=0\r\no=synthetic browser offer for testing\r\n';
let storage: Awaited<ReturnType<typeof openDatabase>>;
let capture: ReturnType<typeof createCapture>;
let app: Hono<{ Variables: { userId: string; signedInAt: Date } }>;
let now: Date;
let plan: 'free' | 'pro';

class Observer implements CaptureObserver {
  private pending: ProviderEvent[] = [];
  private ended = false;
  private wake: (() => void) | undefined;
  commit = vi.fn();
  close = vi.fn(() => {
    this.ended = true;
    this.wake?.();
  });
  push(event: ProviderEvent) {
    this.pending.push(event);
    this.wake?.();
  }
  events = { [Symbol.asyncIterator]: () => this.read() };
  private async *read() {
    while (!this.ended || this.pending.length) {
      while (this.pending.length) yield this.pending.shift()!;
      if (!this.ended)
        await new Promise<void>((resolve) => {
          this.wake = resolve;
        });
    }
  }
}

let observer: Observer;
const provider = {
  create: vi.fn<CaptureProvider['create']>(),
  observe: vi.fn<CaptureProvider['observe']>(),
  hangup: vi.fn<CaptureProvider['hangup']>(),
};

function setup() {
  capture = createCapture(
    storage.db,
    config,
    async () => ({ plan }),
    provider,
    () => now,
  );
  app = new Hono<{ Variables: { userId: string; signedInAt: Date } }>();
  app.get('/api/capture/maintenance', capture.maintenance);
  app.use('/api/*', async (c, next) => {
    const uid = c.req.header('x-test-user');
    if (!uid) return c.json({ error: 'Sign in' }, 401);
    c.set('userId', uid);
    c.set('signedInAt', now);
    await next();
  });
  app.get('/api/capture/usage', capture.usageRoute);
  app.get('/api/capture/pages/:pageId', capture.page);
  app.post('/api/capture/start', capture.start);
  app.post('/api/capture/stop-all', capture.stopAllRoute);
  app.get('/api/capture/:id/events', capture.events);
  app.post('/api/capture/:id/heartbeat', capture.heartbeat);
  app.post('/api/capture/:id/stop', capture.stop);
}

function request(path: string, uid = 'alice', method = 'GET', body?: unknown) {
  return app.request(`${origin}/api/capture${path}`, {
    method,
    headers: { 'x-test-user': uid, 'Content-Type': 'application/json', origin },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}
function start(pageId = alicePage, uid = 'alice', extra = {}) {
  return request('/start', uid, 'POST', { pageId, sdp, ...extra });
}
function maintenance(token = 'synthetic-watchdog-secret') {
  return app.request(`${origin}/api/capture/maintenance`, {
    headers: { authorization: `Bearer ${token}` },
  });
}
async function seededSession(overrides: Partial<typeof captureSessions.$inferInsert> = {}) {
  const session = {
    id: crypto.randomUUID(),
    userId: 'alice',
    pageId: alicePage,
    callId: 'call_synthetic',
    state: 'live',
    createdAt: now,
    activeAt: now,
    lastBilledAt: now,
    leaseExpiresAt: new Date(now.getTime() + 25000),
    deadlineAt: new Date(now.getTime() + 60000),
    ...overrides,
  };
  await storage.db.insert(captureSessions).values(session);
  return session;
}

beforeAll(async () => {
  storage = await openDatabase(undefined, ':memory:');
});
afterAll(async () => {
  await storage.close();
});
beforeEach(async () => {
  vi.stubEnv('OPENAI_API_KEY', 'synthetic-api-key');
  vi.stubEnv('CAPTURE_ENABLED', 'true');
  vi.stubEnv('CAPTURE_WATCHDOG_ENABLED', 'true');
  vi.stubEnv('CAPTURE_CRON_SECRET', 'synthetic-watchdog-secret');
  now = new Date('2026-09-15T12:00:00.000Z');
  plan = 'free';
  vi.resetAllMocks();
  observer = new Observer();
  provider.create.mockImplementation(async () => ({
    callId: `call_${crypto.randomUUID()}`,
    sdp: 'synthetic provider answer',
  }));
  provider.observe.mockResolvedValue(observer);
  provider.hangup.mockResolvedValue(undefined);
  await storage.db.delete(user);
  await storage.db.delete(captureWatchdog);
  await storage.db.insert(user).values(
    ['alice', 'bob'].map((uid) => ({
      id: uid,
      name: uid,
      email: `${uid}@example.test`,
      createdAt: now,
      updatedAt: now,
    })),
  );
  await storage.db
    .insert(notebooks)
    .values(['alice', 'bob'].map((uid) => ({ id: `${uid}-notebook`, userId: uid, name: 'Work' })));
  await storage.db.insert(pages).values([
    {
      id: alicePage,
      userId: 'alice',
      notebookId: 'alice-notebook',
      title: 'Alice meeting',
      document: emptyDocument(),
    },
    {
      id: bobPage,
      userId: 'bob',
      notebookId: 'bob-notebook',
      title: 'Bob meeting',
      document: emptyDocument(),
    },
  ]);
  await storage.db.insert(captureWatchdog).values({ id: 'primary', checkedAt: now });
  setup();
});
afterEach(() => {
  observer.close();
  vi.unstubAllEnvs();
});

describe.sequential('server-owned capture and usage', () => {
  it('splits elapsed usage at UTC month boundaries, including a year change', () => {
    const intervals = usageIntervals(
      new Date('2026-12-31T23:59:55Z'),
      new Date('2027-01-01T00:00:05Z'),
    );
    expect(intervals.map((entry) => [entry.start.toISOString(), entry.milliseconds])).toEqual([
      ['2026-12-01T00:00:00.000Z', 5000],
      ['2027-01-01T00:00:00.000Z', 5000],
    ]);
    expect(calendarPeriod(new Date('2028-02-29T22:00:00Z')).end.toISOString()).toBe(
      '2028-03-01T00:00:00.000Z',
    );
    expect(usageIntervals(now, now)).toEqual([]);
  });

  it('requires configuration and a fresh session watchdog before upstream creation', async () => {
    vi.stubEnv('CAPTURE_ENABLED', 'false');
    expect((await start()).status).toBe(503);
    vi.stubEnv('CAPTURE_ENABLED', 'true');
    expect((await start(alicePage, 'alice', { transcript: 'client-forged text' })).status).toBe(
      400,
    );
    await storage.db.update(captureWatchdog).set({ checkedAt: new Date(now.getTime() - 90001) });
    expect((await start()).status).toBe(503);
    expect(provider.create).not.toHaveBeenCalled();
  });

  it('allows only one concurrent session and meters bounded provider setup time', async () => {
    const responses = await Promise.all([start(), start()]);
    expect(responses.map((response) => response.status).sort()).toEqual([200, 409]);
    expect(provider.create).toHaveBeenCalledTimes(1);
    now = new Date(now.getTime() + 9000);
    const usage = await capture.usage('alice');
    expect(usage.usedSeconds).toBe(9);
    expect(usage.remainingSeconds).toBe(7191);
    expect(usage.activeSessionId).toBeTruthy();
    expect((await storage.db.select().from(captureSessions)).length).toBe(1);
  });

  it('closes an expired unobserved connection before accepting another session', async () => {
    const stale = await seededSession({
      state: 'starting',
      activeAt: null,
      lastBilledAt: null,
      leaseExpiresAt: new Date(now.getTime() - 1),
    });
    expect((await start()).status).toBe(200);
    expect(provider.hangup).toHaveBeenCalledWith(stale.callId);
    expect(
      (await storage.db.select().from(captureSessions).where(eq(captureSessions.id, stale.id)))[0]
        .state,
    ).toBe('interrupted');
    expect((await capture.usage('alice')).usedSeconds).toBe(0);
  });

  it('caps free sessions at both the monthly balance and accumulated duration for the page', async () => {
    const period = calendarPeriod(now);
    await storage.db.insert(captureUsage).values({
      userId: 'alice',
      periodStart: period.start,
      periodEnd: period.end,
      usedMs: 7190000,
    });
    const response = await start();
    expect(response.status).toBe(200);
    expect((await response.json()).maxSeconds).toBe(10);
    await storage.db.delete(captureSessions);
    await storage.db.delete(captureUsage);
    await seededSession({ state: 'paused', billedMs: 3595000, endedAt: now });
    const remaining = await start();
    expect(remaining.status).toBe(200);
    expect((await remaining.json()).maxSeconds).toBe(5);
  });

  it('denies exhausted free capture but keeps saved transcripts readable', async () => {
    const session = await seededSession({ state: 'stopped', billedMs: 3600000, endedAt: now });
    await storage.db.insert(meetingTranscripts).values({
      id: crypto.randomUUID(),
      sessionId: session.id,
      pageId: alicePage,
      itemId: 'item_saved',
      text: 'A saved decision.',
    });
    expect((await start()).status).toBe(402);
    const saved = await request(`/pages/${alicePage}`);
    expect(saved.status).toBe(200);
    expect((await saved.json()).segments[0].text).toBe('A saved decision.');
    expect(provider.create).not.toHaveBeenCalled();
  });

  it('uses server subscription entitlement for Pro and never trusts a client plan field', async () => {
    expect((await start(alicePage, 'alice', { plan: 'pro' })).status).toBe(400);
    plan = 'pro';
    const period = calendarPeriod(now);
    await storage.db.insert(captureUsage).values({
      userId: 'alice',
      periodStart: period.start,
      periodEnd: period.end,
      usedMs: 9000000,
    });
    expect((await start()).status).toBe(200);
    expect(await capture.usage('alice')).toMatchObject({
      plan: 'pro',
      remainingSeconds: null,
      meetingLimitSeconds: null,
    });
  });

  it('isolates session controls, transcripts and pages by the authenticated account', async () => {
    const session = await seededSession();
    expect((await start(alicePage, 'bob')).status).toBe(404);
    expect((await request(`/pages/${alicePage}`, 'bob')).status).toBe(404);
    expect((await request(`/${session.id}/events`, 'bob')).status).toBe(404);
    expect((await request(`/${session.id}/heartbeat`, 'bob', 'POST')).status).toBe(404);
    expect(
      (await request(`/${session.id}/stop`, 'bob', 'POST', { reason: 'stopped' })).status,
    ).toBe(404);
    expect((await request('/usage', '')).status).toBe(401);
    expect(provider.hangup).not.toHaveBeenCalled();
    expect(provider.observe).not.toHaveBeenCalled();
    expect(await capture.accountExport('bob')).toEqual([]);
  });

  it('ends only the signed-in account capture sessions and is idempotent', async () => {
    const aliceSession = await seededSession({ callId: 'call_alice_cleanup' });
    const bobSession = await seededSession({
      userId: 'bob',
      pageId: bobPage,
      callId: 'call_bob_cleanup',
    });

    const stopped = await request('/stop-all', 'alice', 'POST', {});
    expect(stopped.status, await stopped.clone().text()).toBe(200);
    expect(await stopped.json()).toEqual({ stopped: 1 });
    expect(provider.hangup).toHaveBeenCalledWith('call_alice_cleanup');
    expect(provider.hangup).not.toHaveBeenCalledWith('call_bob_cleanup');
    expect(
      (
        await storage.db
          .select()
          .from(captureSessions)
          .where(eq(captureSessions.id, aliceSession.id))
      )[0].state,
    ).toBe('stopped');
    expect(
      (
        await storage.db.select().from(captureSessions).where(eq(captureSessions.id, bobSession.id))
      )[0].state,
    ).toBe('live');

    const repeated = await request('/stop-all', 'alice', 'POST', {});
    expect(await repeated.json()).toEqual({ stopped: 0 });
    expect(provider.hangup).toHaveBeenCalledTimes(1);
  });

  it('keeps failed account capture cleanup retryable without exposing provider details', async () => {
    const session = await seededSession({ state: 'stopping', callId: 'call_cleanup_retry' });
    provider.hangup.mockRejectedValueOnce(new Error('synthetic provider credential detail'));

    const failed = await request('/stop-all', 'alice', 'POST', {});
    expect(failed.status).toBe(503);
    expect(await failed.text()).not.toContain('credential detail');
    expect(
      (await storage.db.select().from(captureSessions).where(eq(captureSessions.id, session.id)))[0]
        .state,
    ).toBe('stopping');

    const retried = await request('/stop-all', 'alice', 'POST', {});
    expect(retried.status, await retried.clone().text()).toBe(200);
    expect(await retried.json()).toEqual({ stopped: 1 });
    expect(
      (await storage.db.select().from(captureSessions).where(eq(captureSessions.id, session.id)))[0]
        .state,
    ).toBe('stopped');
    expect(provider.hangup).toHaveBeenCalledTimes(2);
  });

  it('has no authenticated client route for writing confirmed transcript text', async () => {
    const actualApp = createApp(storage.db, config);
    const signedIn = await actualApp.request(`${origin}/api/auth/sign-up/email`, {
      method: 'POST',
      headers: { origin, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: 'Synthetic transcript test',
        email: 'transcript-route@example.test',
        password: 'Synthetic-password-123',
      }),
    });
    expect(signedIn.status).toBe(200);
    const cookie = signedIn.headers
      .getSetCookie()
      .map((value) => value.split(';')[0])
      .join('; ');
    const accepted = await actualApp.request(`${origin}/api/legal/acceptance`, {
      method: 'POST',
      headers: { origin, cookie, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        termsVersion: CURRENT_TERMS_VERSION,
        acceptedTerms: true,
        recordingLawAcknowledged: true,
      }),
    });
    expect(accepted.status, await accepted.clone().text()).toBe(200);
    const forged = await actualApp.request(
      `${origin}/api/capture/sessions/${crypto.randomUUID()}/transcript`,
      {
        method: 'POST',
        headers: { origin, cookie, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          segments: [{ itemId: 'client-forged', text: 'This was never transcribed.' }],
        }),
      },
    );
    expect(forged.status).toBe(404);
    expect(await storage.db.select().from(meetingTranscripts)).toEqual([]);
  });

  it('cleans failed provider starts without consuming usage or blocking the next attempt', async () => {
    provider.create.mockRejectedValueOnce(
      new Error('synthetic upstream failure containing sensitive detail'),
    );
    const failed = await start();
    expect(failed.status).toBe(503);
    expect(await failed.text()).not.toContain('sensitive detail');
    expect((await storage.db.select().from(captureSessions))[0].state).toBe('interrupted');
    expect((await capture.usage('alice')).usedSeconds).toBe(0);
    expect((await start()).status).toBe(200);
  });

  it('hangs up a call when its provider observer cannot connect', async () => {
    const started = await (await start()).json();
    provider.observe.mockRejectedValueOnce(new Error('synthetic observer failure'));
    expect((await request(`/${started.id}/events`)).status).toBe(503);
    expect(provider.hangup).toHaveBeenCalledTimes(1);
    expect((await storage.db.select().from(captureSessions))[0].state).toBe('interrupted');
    expect((await capture.usage('alice')).usedSeconds).toBe(0);
  });

  it('settles a lost session once, allocating usage to the right calendar months', async () => {
    now = new Date('2026-10-01T00:00:06Z');
    await seededSession({
      createdAt: new Date('2026-09-30T23:59:55Z'),
      activeAt: new Date('2026-09-30T23:59:55Z'),
      lastBilledAt: new Date('2026-09-30T23:59:55Z'),
      leaseExpiresAt: new Date('2026-10-01T00:00:05Z'),
      deadlineAt: new Date('2026-10-01T00:01:00Z'),
    });
    expect((await maintenance()).status).toBe(200);
    expect((await maintenance()).status).toBe(200);
    const rows = await storage.db.select().from(captureUsage);
    expect(rows.map((row) => [row.periodStart.toISOString(), row.usedMs]).sort()).toEqual([
      ['2026-09-01T00:00:00.000Z', 5000],
      ['2026-10-01T00:00:00.000Z', 5000],
    ]);
    expect((await capture.usage('alice')).usedSeconds).toBe(5);
    expect(provider.hangup).toHaveBeenCalledTimes(1);
  });

  it('keeps failed termination eligible for watchdog retry and does not double-charge after recovery', async () => {
    const session = await seededSession({
      activeAt: new Date(now.getTime() - 15000),
      lastBilledAt: new Date(now.getTime() - 15000),
      leaseExpiresAt: new Date(now.getTime() - 5000),
    });
    provider.hangup.mockRejectedValueOnce(new Error('upstream temporarily down'));
    expect((await maintenance()).status).toBe(503);
    expect((await storage.db.select().from(captureSessions))[0].state).toBe('live');
    expect(await storage.db.select().from(captureUsage)).toEqual([]);
    expect((await maintenance()).status).toBe(200);
    expect((await maintenance()).status).toBe(200);
    expect((await capture.usage('alice')).usedSeconds).toBe(10);
    expect(
      (await storage.db.select().from(captureSessions).where(eq(captureSessions.id, session.id)))[0]
        .billedMs,
    ).toBe(10000);
  });

  it('clamps pending usage and repeated stop requests to the server-enforced deadline', async () => {
    const session = await seededSession({
      activeAt: new Date(now.getTime() - 10000),
      lastBilledAt: new Date(now.getTime() - 10000),
      deadlineAt: new Date(now.getTime() - 4000),
    });
    expect((await capture.usage('alice')).usedSeconds).toBe(6);
    const stopped = await request(`/${session.id}/stop`, 'alice', 'POST', { reason: 'paused' });
    expect(stopped.status).toBe(200);
    expect((await stopped.json()).usage.usedSeconds).toBe(6);
    now = new Date(now.getTime() + 1000);
    expect(
      (await request(`/${session.id}/stop`, 'alice', 'POST', { reason: 'paused' })).status,
    ).toBe(200);
    expect((await capture.usage('alice')).usedSeconds).toBe(6);
    expect(provider.hangup).toHaveBeenCalledTimes(1);
    expect((await storage.db.select().from(captureSessions))[0]).toMatchObject({
      state: 'paused',
      billedMs: 6000,
    });
  });

  it('requires the watchdog secret and refuses deletion while a meeting is active', async () => {
    await seededSession();
    expect((await maintenance('wrong')).status).toBe(401);
    await expect(capture.beforeDelete('alice')).rejects.toThrow('Stop the active meeting');
    await expect(capture.beforeDelete('alice', bobPage)).resolves.toBeUndefined();
    await expect(capture.beforeDelete('bob')).resolves.toBeUndefined();
  });

  it('persists only provider-final text, deduplicates events and streams the saved segment', async () => {
    const originalDocument = (
      await storage.db.select().from(pages).where(eq(pages.id, alicePage))
    )[0].document;
    const started = await (await start()).json();
    const response = await request(`/${started.id}/events`);
    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toContain('text/event-stream');
    const output = response.text();
    observer.push({
      type: 'input_audio_buffer.committed',
      item_id: 'item_one',
      previous_item_id: null,
    });
    observer.push({
      type: 'conversation.item.input_audio_transcription.completed',
      item_id: 'item_one',
      transcript: 'A provider-confirmed decision.',
    });
    observer.push({
      type: 'conversation.item.input_audio_transcription.completed',
      item_id: 'item_one',
      transcript: 'Duplicate must not overwrite.',
    });
    await expect
      .poll(async () => (await storage.db.select().from(meetingTranscripts)).length)
      .toBe(1);
    now = new Date(now.getTime() + 4000);
    observer.close();
    const events = await output;
    expect(events).toContain('event: ready');
    expect(events).toContain('event: transcript');
    expect(events).toContain('A provider-confirmed decision.');
    expect(events).not.toContain('Duplicate must not overwrite.');
    expect((await capture.usage('alice')).usedSeconds).toBe(4);
    const transcript = (await storage.db.select().from(meetingTranscripts))[0];
    expect(transcript).toMatchObject({
      sessionId: started.id,
      pageId: alicePage,
      itemId: 'item_one',
      text: 'A provider-confirmed decision.',
    });
    expect(
      (await storage.db.select().from(pages).where(eq(pages.id, alicePage)))[0].document,
    ).toEqual(originalDocument);
  });

  it('does not reactivate a session stopped while its observer was connecting', async () => {
    const started = await (await start()).json();
    let connected!: (observer: CaptureObserver) => void;
    provider.observe.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          connected = resolve;
        }),
    );
    const connection = request(`/${started.id}/events`);
    await expect.poll(() => provider.observe.mock.calls.length).toBe(1);
    await storage.db
      .update(captureSessions)
      .set({ state: 'interrupted', endedAt: now })
      .where(eq(captureSessions.id, started.id));
    connected(observer);
    const response = await connection;
    if (response.status === 200) await response.body?.cancel();
    expect([409, 503]).toContain(response.status);
    expect((await storage.db.select().from(captureSessions))[0].state).toBe('interrupted');
    expect(observer.close).toHaveBeenCalled();
  });
});
