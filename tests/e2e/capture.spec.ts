import { test, expect, type Page } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

declare global {
  interface Window {
    __captureHarness: {
      created: number;
      stopped: number;
      emit: (type: string, data: unknown) => void;
    };
  }
}
const sessionId = '59a37c62-3cf7-4d2f-8558-a5c4b978264d';
const emptyUsage = {
  plan: 'free',
  usedSeconds: 0,
  remainingSeconds: 7200,
  meetingLimitSeconds: 3600,
  resetAt: '2026-10-01T00:00:00Z',
  activeSessionId: null,
};

async function configure(page: Page) {
  await page.addInitScript(() => {
    const events = new Set<{ listeners: Map<string, ((event: MessageEvent) => void)[]> }>();
    window.__captureHarness = {
      created: 0,
      stopped: 0,
      emit(type, data) {
        for (const target of events)
          for (const listener of target.listeners.get(type) || []) {
            listener(new MessageEvent(type, { data: JSON.stringify(data) }));
          }
      },
    };
    Object.defineProperty(navigator.mediaDevices, 'getUserMedia', {
      configurable: true,
      value: async () => {
        window.__captureHarness.created += 1;
        const track = {
          enabled: true,
          onended: null,
          stop: () => {
            window.__captureHarness.stopped += 1;
          },
        };
        return { getTracks: () => [track], getAudioTracks: () => [track] };
      },
    });
    class Peer {
      connectionState = 'new';
      onconnectionstatechange: (() => void) | null = null;
      channel = {
        readyState: 'connecting',
        onopen: null as (() => void) | null,
        onclose: null as (() => void) | null,
        onmessage: null,
        send() {},
        close() {},
      };
      addTrack() {}
      createDataChannel() {
        return this.channel;
      }
      async createOffer() {
        return { type: 'offer', sdp: 'v=0\r\no=synthetic-browser-test-offer\r\n' };
      }
      async setLocalDescription() {}
      async setRemoteDescription() {
        this.channel.readyState = 'open';
        this.channel.onopen?.();
      }
      close() {
        this.connectionState = 'closed';
      }
    }
    class Events {
      listeners = new Map<string, ((event: MessageEvent) => void)[]>();
      onerror: (() => void) | null = null;
      constructor() {
        events.add(this);
        setTimeout(() => {
          for (const listener of this.listeners.get('ready') || [])
            listener(new MessageEvent('ready', { data: '{}' }));
        }, 0);
      }
      addEventListener(type: string, listener: (event: MessageEvent) => void) {
        this.listeners.set(type, [...(this.listeners.get(type) || []), listener]);
      }
      close() {
        events.delete(this);
      }
    }
    Object.defineProperty(window, 'RTCPeerConnection', { configurable: true, value: Peer });
    Object.defineProperty(window, 'EventSource', { configurable: true, value: Events });
  });
  await page.route('**/api/config', async (route) => {
    const response = await route.fetch();
    const config = await response.json();
    await route.fulfill({
      json: {
        ...config,
        capture: { ready: true, reason: 'Live microphone transcription is available.' },
      },
    });
  });
  await page.route('**/api/capture/pages/*', (route) =>
    route.fulfill({ json: { sessions: [], segments: [], usage: emptyUsage } }),
  );
  await page.route('**/api/capture/usage', (route) => route.fulfill({ json: emptyUsage }));
  await page.route('**/api/capture/sessions', (route) =>
    route.fulfill({
      json: {
        id: sessionId,
        sdp: 'synthetic provider answer',
        expiresAt: new Date(Date.now() + 60000).toISOString(),
        maxSeconds: 60,
        heartbeatSeconds: 10,
      },
    }),
  );
  await page.route('**/api/capture/sessions/*/stop', (route) =>
    route.fulfill({ json: { stopped: true, usage: emptyUsage } }),
  );
  await page.route('**/api/capture/sessions/*/heartbeat', (route) =>
    route.fulfill({
      json: {
        expiresAt: new Date(Date.now() + 60000).toISOString(),
        remainingSeconds: 60,
        state: 'live',
      },
    }),
  );
}

async function register(page: Page) {
  await page.goto('/');
  await page.getByLabel('Your name').fill('Capture QA');
  await page
    .getByLabel('Email', { exact: true })
    .fill(`capture-${crypto.randomUUID()}@example.test`);
  await page.getByLabel('Password', { exact: false }).fill('local-capture-Password-123');
  const agreements = page.getByRole('group', { name: 'Agreements required to continue' });
  await agreements.getByRole('checkbox').nth(0).check();
  await agreements.getByRole('checkbox').nth(1).check();
  await page.getByRole('button', { name: 'Create account', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your notebooks' })).toBeVisible();
}
async function openPage(page: Page) {
  await page.getByRole('button', { name: 'Open a synthetic example' }).click();
  await expect(page.locator('.sync-status')).toHaveText('Saved');
  await expect(page.getByRole('region', { name: 'Live transcription', exact: true })).toBeVisible();
}

test('live capture updates the microphone indicator, shows confirmed text, and blocks unsafe page exit', async ({
  page,
}) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await configure(page);
  await register(page);
  await openPage(page);
  const capture = page.getByRole('region', { name: 'Live transcription', exact: true });
  const start = capture.getByRole('button', { name: 'Start live capture', exact: true });
  await expect(start).toBeEnabled();
  await start.click();
  await expect(capture.getByRole('status')).toHaveText('Listening');
  await expect(page.locator('.mic-status')).toHaveAttribute(
    'aria-label',
    'Your microphone is live',
  );
  await expect(page.locator('.margin-privacy')).toContainText('Your microphone is live.');
  await page.evaluate(
    (id) =>
      window.__captureHarness.emit('transcript', {
        id: 'saved-segment',
        sessionId: id,
        pageId: 'synthetic-page',
        itemId: 'item_confirmed',
        previousItemId: null,
        text: 'The team agreed to review the prototype on Friday.',
        createdAt: new Date().toISOString(),
      }),
    sessionId,
  );
  await expect(
    capture.getByText('The team agreed to review the prototype on Friday.', { exact: true }),
  ).toBeVisible();
  const evidence = path.join(tmpdir(), 'sideleaf-capture-qa');
  await mkdir(evidence, { recursive: true });
  for (const [name, width, height] of [
    ['desktop', 1536, 1024],
    ['ipad', 820, 1180],
    ['phone', 390, 844],
  ] as const) {
    await page.setViewportSize({ width, height });
    await capture.scrollIntoViewIfNeeded();
    await page.screenshot({ path: path.join(evidence, `${name}-listening.png`) });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
    await expect(page.locator('.mic-status')).toHaveAttribute(
      'aria-label',
      'Your microphone is live',
    );
  }
  await capture.getByRole('button', { name: 'Pause', exact: true }).click();
  await expect.poll(() => page.evaluate(() => window.__captureHarness.stopped)).toBe(1);
  await expect(page.locator('.mic-status')).toHaveAttribute('aria-label', 'Your microphone is off');
  await expect(page.locator('.margin-privacy')).toContainText('Your microphone is off.');
  await expect(capture.getByRole('status')).toHaveText('Microphone paused');
  await capture.getByRole('button', { name: 'Resume capture', exact: true }).click();
  await expect(capture.getByRole('status')).toHaveText('Listening');
  await page.getByRole('button', { name: 'Back to pages', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('Finish live transcription before leaving');
  await expect(capture.getByRole('status')).toHaveText('Listening');
  await expect.poll(() => page.evaluate(() => window.__captureHarness.stopped)).toBe(1);
  await capture.getByRole('button', { name: 'Pause', exact: true }).click();
  await expect.poll(() => page.evaluate(() => window.__captureHarness.stopped)).toBe(2);
  await expect(capture.getByRole('status')).toHaveText('Microphone paused');
  await page.getByRole('button', { name: 'Back to pages', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your notebooks' })).toBeVisible();
  await expect(page.locator('.mic-status')).toHaveAttribute('aria-label', 'Your microphone is off');
  expect(errors).toEqual([]);
});

test('a Terms update waits for live capture to reach a safe state', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await configure(page);
  await register(page);
  await openPage(page);
  const capture = page.getByRole('region', { name: 'Live transcription', exact: true });
  await capture.getByRole('button', { name: 'Start live capture', exact: true }).click();
  await expect(capture.getByRole('status')).toHaveText('Listening');

  await page.evaluate(() => {
    window.dispatchEvent(
      new CustomEvent('sideleaf:legal-acceptance-required', {
        detail: {
          termsVersion: '2026-09-10.1',
          effectiveAt: '2026-09-10',
          termsUrl: '/terms',
          privacyUrl: '/privacy',
          recordingLawAcknowledgement:
            'I am responsible for determining and following applicable recording requirements.',
        },
      }),
    );
  });

  await expect(page.getByRole('alert')).toContainText(
    'The Terms of Service changed. Finish live transcription',
  );
  await expect(capture.getByRole('status')).toHaveText('Listening');
  await capture.getByRole('button', { name: 'Pause', exact: true }).click();
  await expect.poll(() => page.evaluate(() => window.__captureHarness.stopped)).toBe(1);
  await expect(page.getByRole('heading', { name: 'Before you continue' })).toBeVisible();
  await expect(page.getByText('2026-09-10.1', { exact: true })).toBeVisible();
  expect(errors).toEqual([]);
});

test('capture cannot start while page edits are unsynced or the browser is offline', async ({
  page,
  context,
}) => {
  await configure(page);
  await register(page);
  await openPage(page);
  const capture = page.getByRole('region', { name: 'Live transcription', exact: true });
  const start = capture.getByRole('button', { name: 'Start live capture', exact: true });
  await expect(start).toBeEnabled();
  let saved!: () => void;
  const pending = new Promise<void>((resolve) => {
    saved = resolve;
  });
  await page.route('**/api/pages/*', async (route) => {
    if (route.request().method() === 'PUT') await pending;
    await route.continue();
  });
  await page
    .getByLabel('Note text', { exact: true })
    .first()
    .fill('Wait for this edited note to sync.');
  await expect(start).toBeDisabled();
  await expect(
    capture.getByText('Wait for this page to finish syncing before starting live transcription.'),
  ).toBeVisible();
  saved();
  await expect(page.locator('.sync-status')).toHaveText('Saved');
  await expect(start).toBeEnabled();
  await context.setOffline(true);
  await expect(start).toBeDisabled();
  await expect(capture.getByText(/Reconnect to the internet/)).toBeVisible();
  expect(await page.evaluate(() => window.__captureHarness.created)).toBe(0);
  await context.setOffline(false);
});

test('Stripe return opens settings and still displays the server-confirmed free plan', async ({
  page,
}) => {
  await configure(page);
  await page.route('**/api/billing', (route) =>
    route.fulfill({
      json: {
        plan: 'free',
        provider: null,
        status: 'free',
        currentPeriodEnd: null,
        cancelAtPeriodEnd: false,
        paymentReview: false,
        checkoutReady: false,
        portalReady: false,
        mode: 'live',
        price: { amount: 29, currency: 'USD', interval: 'month' },
        message: 'Subscriptions are not available for purchase yet.',
      },
    }),
  );
  await register(page);
  await page.goto('/?billing=success');
  await expect(page.getByRole('dialog', { name: 'Your notebook, your data' })).toBeVisible();
  await expect(page.getByText('Current plan: Free', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Close dialog', exact: true }).click();
  await expect(page).toHaveURL('http://127.0.0.1:5173/');
});
