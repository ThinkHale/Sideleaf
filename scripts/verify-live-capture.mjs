/**
 * Opt-in production smoke test. Uses Chromium's synthetic audio device only.
 * Required: SIDELEAF_LIVE_TEST=true and SIDELEAF_TEST_AUDIO=/absolute/synthetic.wav
 * Optional: SIDELEAF_EXPECT_TRANSCRIPT, SIDELEAF_TEST_DISCONNECT=true,
 * SIDELEAF_TEST_ROLLOVER=true (waits for the real 225-second server rollover)
 * No API keys, passwords, cookies, or browser storage state are written to disk.
 */
import { chromium, expect } from '@playwright/test';
import { randomBytes, randomUUID } from 'node:crypto';
import { mkdir, open, realpath, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

const origin = 'https://sideleaf.vercel.app';
const activeStates = new Set(['starting', 'live', 'stopping']);

if (process.env.SIDELEAF_LIVE_TEST !== 'true') {
  console.log('Live capture smoke test skipped. Explicit SIDELEAF_LIVE_TEST=true is required.');
  process.exit(0);
}

const suppliedAudio = process.env.SIDELEAF_TEST_AUDIO;
if (!suppliedAudio || !path.isAbsolute(suppliedAudio)) {
  console.error(
    'SIDELEAF_TEST_AUDIO must identify an absolute path to a synthetic spoken WAV file.',
  );
  process.exit(1);
}

const password = `Qa!${randomBytes(32).toString('base64url')}`;
const email = `sideleaf-capture-${randomUUID()}@example.test`;
const title = `Synthetic microphone QA ${randomUUID().slice(0, 8)}`;
const evidence = path.join(tmpdir(), `sideleaf-live-capture-${randomUUID()}`);
let browser;
let context;
let page;
let signupAttempted = false;
let pageId;
let stage = 'validate synthetic audio';
let failed = false;
let cleanupComplete = false;
const responses = [];
const report = { origin, syntheticAudioOnly: true, checks: [], evidence };

function safeText(value) {
  return String(value)
    .replaceAll(password, '[redacted password]')
    .replace(/\b(?:sk-|sb_secret_)[A-Za-z0-9_-]+/g, '[redacted key]')
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, '[redacted token]')
    .slice(0, 2400);
}

async function api(endpoint, method = 'GET', data) {
  const response = await context.request.fetch(`${origin}/api${endpoint}`, {
    method,
    data,
    headers: { Origin: origin },
    timeout: 30000,
    maxRedirects: 0,
    failOnStatusCode: false,
  });
  const body = await response.json().catch(() => ({}));
  return { status: response.status(), ok: response.ok(), body };
}

async function requireApi(endpoint, method = 'GET', data) {
  const result = await api(endpoint, method, data);
  if (!result.ok) throw new Error(`HTTP ${result.status} from ${endpoint}`);
  return result.body;
}

async function captureMessages() {
  if (!page || page.isClosed()) return [];
  return page
    .locator('.live-capture .error, .live-capture .notice, .live-capture [role="status"]')
    .allTextContents()
    .then((items) => items.map(safeText))
    .catch(() => []);
}

async function microphoneReleased() {
  return page.evaluate(() => {
    const tracks = window.__sideleafSyntheticTracks || [];
    return {
      count: tracks.length,
      allEnded: tracks.length > 0 && tracks.every((track) => track.readyState === 'ended'),
    };
  });
}

try {
  const audio = await realpath(suppliedAudio);
  const file = await stat(audio);
  if (!file.isFile() || file.size < 44 || file.size > 128 * 1024 * 1024)
    throw new Error('Synthetic WAV size is invalid.');
  const handle = await open(audio, 'r');
  try {
    const header = Buffer.alloc(12);
    await handle.read(header, 0, header.length, 0);
    if (header.toString('ascii', 0, 4) !== 'RIFF' || header.toString('ascii', 8, 12) !== 'WAVE') {
      throw new Error('Synthetic fixture is not a RIFF WAV file.');
    }
  } finally {
    await handle.close();
  }
  await mkdir(evidence, { recursive: true });

  stage = 'launch Chromium with synthetic microphone';
  browser = await chromium.launch({
    headless: true,
    args: [
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
      `--use-file-for-fake-audio-capture=${audio}`,
    ],
  });
  context = await browser.newContext({
    baseURL: origin,
    permissions: ['microphone'],
    viewport: { width: 1440, height: 1080 },
    serviceWorkers: 'block',
  });
  await context.addInitScript(() => {
    window.__sideleafSyntheticTracks = [];
    const original = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    navigator.mediaDevices.getUserMedia = async (constraints) => {
      if (constraints?.video) throw new Error('The synthetic smoke test does not permit video.');
      const stream = await original(constraints);
      window.__sideleafSyntheticTracks.push(...stream.getAudioTracks());
      return stream;
    };
  });

  stage = 'check production capture readiness';
  const config = await requireApi('/config');
  if (!config.capture?.ready)
    throw new Error(
      `Capture is disabled: ${safeText(config.capture?.reason || 'no reason returned')}`,
    );
  if (!config.passwordAuth)
    throw new Error(
      'The hosted beta must enable email/password authentication for this QA account.',
    );

  stage = 'create temporary synthetic account';
  signupAttempted = true;
  await requireApi('/auth/sign-up/email', 'POST', {
    name: 'Synthetic microphone QA',
    email,
    password,
  });
  page = await context.newPage();
  page.on('dialog', (dialog) => dialog.dismiss());
  page.on('response', (response) => {
    const url = new URL(response.url());
    if (url.origin === origin && url.pathname.startsWith('/api/capture/')) {
      responses.push({
        endpoint: url.pathname.replace(/[0-9a-f]{8}-[0-9a-f-]{27}/gi, ':id'),
        status: response.status(),
      });
    }
  });
  await page.goto(origin, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await expect(page.getByRole('heading', { name: 'Your notebooks' })).toBeVisible({
    timeout: 30000,
  });
  await page.getByRole('button', { name: 'Create a blank page', exact: true }).click();
  await page.getByLabel('Page title').fill(title);
  await expect(page.locator('.sync-status')).toHaveText('Saved', { timeout: 30000 });
  const pages = await requireApi('/pages');
  pageId = pages.find((entry) => entry.title === title)?.id;
  if (!pageId) throw new Error('The synthetic test page was not saved.');
  const capture = page.getByRole('region', { name: 'Live transcription' });
  await expect(capture).toBeVisible();
  await capture.getByRole('checkbox').check();

  stage = 'connect real OpenAI transcription using synthetic audio';
  await capture.getByRole('button', { name: 'Start live capture', exact: true }).click();
  const connectDeadline = Date.now() + 80000;
  while (Date.now() < connectDeadline) {
    const state = await capture.getByRole('status').textContent();
    if (state === 'Listening') break;
    if (state === 'Capture interrupted') throw new Error((await captureMessages()).join(' '));
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  await expect(capture.getByRole('status')).toHaveText('Listening', { timeout: 1000 });
  await expect(page.locator('.mic-status')).toContainText('Mic live');
  report.checks.push('WebRTC microphone connected with server observer ready');

  stage = 'receive a real provider transcript saved by the backend';
  const savedParagraphs = capture.locator('.capture-transcript > p:not(.fine-print)');
  await expect
    .poll(
      async () => {
        const error = await capture.locator('.error').allTextContents();
        if (error.length) throw new Error(safeText(error.join(' ')));
        return (await savedParagraphs.allTextContents()).join(' ').trim().length;
      },
      {
        timeout: 90000,
        intervals: [500, 1000, 2000],
        message: 'Waiting for server-confirmed synthetic speech',
      },
    )
    .toBeGreaterThan(8);
  const expected = process.env.SIDELEAF_EXPECT_TRANSCRIPT?.trim();
  if (expected) {
    await expect
      .poll(async () => (await savedParagraphs.allTextContents()).join(' ').toLowerCase(), {
        timeout: 45000,
        intervals: [500, 1000],
      })
      .toContain(expected.toLowerCase());
  }
  const stored = await requireApi(`/capture/pages/${pageId}`);
  if (
    !stored.segments?.some(
      (segment) => typeof segment.text === 'string' && segment.text.trim().length > 8,
    )
  ) {
    throw new Error('Visible transcript was not present in the server transcript table.');
  }
  report.checks.push('Real OpenAI transcript received and confirmed in the database');
  report.transcript = safeText(stored.segments.map((segment) => segment.text).join(' ')).slice(
    0,
    800,
  );
  report.segmentCount = stored.segments.length;
  await page.screenshot({ path: path.join(evidence, 'listening.png'), fullPage: true });

  if (process.env.SIDELEAF_TEST_ROLLOVER === 'true') {
    stage = 'verify the real 225-second automatic session rollover';
    console.log(JSON.stringify({ stage, status: 'waiting for server rollover' }));
    const originalSession = stored.sessions.find((session) => session.state === 'live');
    if (!originalSession)
      throw new Error('The original live session was not found before rollover.');
    const originalTrackCount = await page.evaluate(() => window.__sideleafSyntheticTracks.length);
    const rolloverDeadline = Date.now() + 280000;
    let newSessionId;
    let lastSessionStates = [];
    while (Date.now() < rolloverDeadline) {
      const state = await capture.getByRole('status').textContent();
      if (state === 'Capture interrupted') throw new Error((await captureMessages()).join(' '));
      const data = await requireApi(`/capture/pages/${pageId}`);
      lastSessionStates = data.sessions.map((session) => ({
        state: session.state,
        billedMs: session.billedMs,
        original: session.id === originalSession.id,
      }));
      const original = data.sessions.find((session) => session.id === originalSession.id);
      const next = data.sessions.find(
        (session) => session.id !== originalSession.id && session.state === 'live',
      );
      if (original?.state === 'rollover' && next) {
        newSessionId = next.id;
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 2500));
    }
    report.rolloverSessions = lastSessionStates;
    if (!newSessionId)
      throw new Error(
        'The original session did not reach rollover with a replacement session live within 280 seconds.',
      );
    await expect(capture.getByRole('status')).toHaveText('Listening', { timeout: 40000 });
    await expect(page.locator('.mic-status')).toContainText('Mic live');
    await expect
      .poll(
        async () =>
          page.evaluate((count) => {
            const tracks = window.__sideleafSyntheticTracks;
            return (
              tracks.length > count &&
              tracks.slice(0, count).every((track) => track.readyState === 'ended') &&
              tracks.slice(count).some((track) => track.readyState === 'live' && track.enabled)
            );
          }, originalTrackCount),
        { timeout: 5000 },
      )
      .toBe(true);
    stage = 'receive a real transcript from the replacement session';
    let replacementSegments = [];
    await expect
      .poll(
        async () => {
          const data = await requireApi(`/capture/pages/${pageId}`);
          replacementSegments = data.segments.filter(
            (segment) => segment.sessionId === newSessionId,
          );
          return replacementSegments
            .map((segment) => segment.text)
            .join(' ')
            .trim().length;
        },
        { timeout: 60000, intervals: [1000, 2000] },
      )
      .toBeGreaterThan(8);
    report.rolloverTranscript = safeText(
      replacementSegments.map((segment) => segment.text).join(' '),
    ).slice(0, 800);
    report.checks.push(
      'The real 225-second rollover closed the original session, replaced microphone tracks, and saved speech in a new live session',
    );
    await page.screenshot({ path: path.join(evidence, 'after-rollover.png'), fullPage: true });
    console.log(JSON.stringify({ stage: 'automatic rollover', status: 'passed' }));
  }

  stage = 'pause and verify all microphone tracks end';
  await capture.getByRole('button', { name: 'Pause', exact: true }).click();
  await expect
    .poll(async () => (await microphoneReleased()).allEnded, { timeout: 5000 })
    .toBe(true);
  await expect(capture.getByRole('status')).toHaveText('Microphone paused', { timeout: 30000 });
  await expect(page.locator('.mic-status')).toContainText('Mic off');
  await expect
    .poll(
      async () => {
        const data = await requireApi(`/capture/pages/${pageId}`);
        return data.sessions.filter((session) => activeStates.has(session.state)).length;
      },
      { timeout: 30000, intervals: [1000, 2000] },
    )
    .toBe(0);
  report.checks.push('Pause released every microphone track and closed the server session');
  await page.screenshot({ path: path.join(evidence, 'paused.png'), fullPage: true });

  if (process.env.SIDELEAF_TEST_DISCONNECT === 'true') {
    stage = 'verify connection-loss cleanup';
    await capture.getByRole('button', { name: 'Resume capture', exact: true }).click();
    await expect(capture.getByRole('status')).toHaveText('Listening', { timeout: 40000 });
    await context.setOffline(true);
    await expect
      .poll(async () => (await microphoneReleased()).allEnded, { timeout: 5000 })
      .toBe(true);
    await context.setOffline(false);
    await expect
      .poll(
        async () => {
          const data = await requireApi(`/capture/pages/${pageId}`);
          return data.sessions.filter((session) => activeStates.has(session.state)).length;
        },
        { timeout: 100000, intervals: [2000, 5000] },
      )
      .toBe(0);
    report.checks.push(
      'Connection loss released the microphone and server cleanup closed the abandoned session',
    );
  }
  report.status = 'passed';
} catch (error) {
  failed = true;
  report.status = 'failed';
  report.stage = stage;
  report.error = safeText(error instanceof Error ? error.message : error);
  report.captureUi = await captureMessages();
  if (page && !page.isClosed()) {
    await page
      .screenshot({ path: path.join(evidence, 'failure.png'), fullPage: true })
      .catch(() => undefined);
  }
} finally {
  if (context) {
    await context.setOffline(false).catch(() => undefined);
    if (page && !page.isClosed()) {
      await page
        .evaluate(() => {
          for (const track of window.__sideleafSyntheticTracks || []) track.stop();
        })
        .catch(() => undefined);
    }
    if (signupAttempted) {
      try {
        // Refresh authentication so the five-minute account-deletion window also covers long tests.
        const signedIn = await api('/auth/sign-in/email', 'POST', { email, password });
        if (signedIn.ok) {
          if (pageId) {
            const data = await requireApi(`/capture/pages/${pageId}`);
            for (const session of data.sessions.filter((entry) => activeStates.has(entry.state))) {
              await api(`/capture/sessions/${session.id}/stop`, 'POST', { reason: 'stopped' });
            }
          }
          for (let attempt = 0; attempt < 12; attempt++) {
            const deleted = await api('/account', 'DELETE', { confirmation: 'DELETE' });
            if (deleted.ok) {
              cleanupComplete = true;
              break;
            }
            if (deleted.status !== 409)
              throw new Error(`Account cleanup returned HTTP ${deleted.status}.`);
            await new Promise((resolve) => setTimeout(resolve, 3000));
          }
          if (!cleanupComplete)
            throw new Error('The temporary account still has a closing capture session.');
        } else {
          throw new Error(`Cleanup sign-in returned HTTP ${signedIn.status}.`);
        }
      } catch (error) {
        failed = true;
        report.cleanupError = safeText(error instanceof Error ? error.message : error);
        report.temporaryAccount = email;
      }
    }
    await context.close().catch(() => undefined);
  }
  await browser?.close().catch(() => undefined);
  report.cleanup = signupAttempted
    ? cleanupComplete
      ? 'Temporary account deleted'
      : 'Cleanup needs attention'
    : 'No account created';
  report.captureResponses = responses;
  if (failed) report.status = 'failed';
  console.log(JSON.stringify(report, null, 2));
  process.exitCode = failed ? 1 : 0;
}
