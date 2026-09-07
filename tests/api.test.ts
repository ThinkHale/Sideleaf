import { beforeAll, afterAll, describe, expect, it } from 'vitest';
import { openDatabase } from '../server/database';
import { createApp } from '../server/app';
import { emptyDocument } from '../shared/domain';
const origin = 'http://127.0.0.1:5173';
let storage: Awaited<ReturnType<typeof openDatabase>>;
let app: ReturnType<typeof createApp>;
let alice = '',
  bob = '',
  notebookId = '',
  pageId = '';
const doc = emptyDocument();
doc.blocks[1].text = 'A locally saved thought.';
const mutationId = crypto.randomUUID();
function request(
  path: string,
  cookie = alice,
  method = 'GET',
  body?: unknown,
  requestOrigin = origin,
) {
  return app.request(`${origin}/api${path}`, {
    method,
    headers: { origin: requestOrigin, cookie, 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}
beforeAll(async () => {
  storage = await openDatabase(undefined, ':memory:');
  app = createApp(storage.db, {
    origin,
    secret: 'test-secret-only-0000000000000000000000000000000',
    production: false,
    name: 'Test Notebook',
    freeMinutes: 120,
    meetingMinutes: 60,
    price: 29,
  });
  async function register(email: string) {
    const response = await request('/auth/sign-up/email', '', 'POST', {
      name: 'Synthetic Tester',
      email,
      password: 'test-notebook-Password-47',
    });
    expect(response.status, await response.clone().text()).toBe(200);
    return response.headers
      .getSetCookie()
      .map((c) => c.split(';')[0])
      .join('; ');
  }
  alice = await register('alice@example.test');
  bob = await register('bob@example.test');
});
afterAll(async () => storage.close());
describe.sequential('authenticated notebook API', () => {
  it('rejects unauthenticated reads and cross-origin writes', async () => {
    expect((await request('/pages', '')).status).toBe(401);
    expect(
      (await request('/notebooks', alice, 'POST', {}, 'https://untrusted.example')).status,
    ).toBe(403);
  });
  it('persists a notebook and page', async () => {
    notebookId = crypto.randomUUID();
    expect(
      (await request('/notebooks', alice, 'POST', { id: notebookId, name: 'Work' })).status,
    ).toBe(201);
    pageId = crypto.randomUUID();
    const response = await request(`/pages/${pageId}`, alice, 'PUT', {
      title: 'Conversation',
      notebookId,
      document: doc,
      baseVersion: 0,
      mutationId,
    });
    expect(response.status, await response.clone().text()).toBe(200);
    expect((await response.json()).version).toBe(1);
  });
  it('deduplicates a retried save', async () => {
    const response = await request(`/pages/${pageId}`, alice, 'PUT', {
      title: 'Conversation',
      notebookId,
      document: doc,
      baseVersion: 0,
      mutationId,
    });
    expect(response.status).toBe(200);
    expect((await response.json()).version).toBe(1);
    expect((await (await request(`/pages/${pageId}/history`)).json()).length).toBe(1);
  });
  it('denies another account page, history, export and notebook access', async () => {
    for (const suffix of ['', '/history', '/export'])
      expect((await request(`/pages/${pageId}${suffix}`, bob)).status).toBe(404);
    expect((await request(`/pages/${pageId}`, bob, 'DELETE')).status).toBe(404);
    expect((await request('/pages', bob)).status).toBe(200);
    expect(await (await request('/pages', bob)).json()).toEqual([]);
    expect(
      (
        await request(`/pages/${crypto.randomUUID()}`, bob, 'PUT', {
          title: 'Attempt',
          notebookId,
          document: doc,
          baseVersion: 0,
          mutationId: crypto.randomUUID(),
        })
      ).status,
    ).toBe(404);
  });
  it('returns a conflict instead of overwriting accepted notes', async () => {
    const response = await request(`/pages/${pageId}`, alice, 'PUT', {
      title: 'Stale edit',
      notebookId,
      document: doc,
      baseVersion: 0,
      mutationId: crypto.randomUUID(),
    });
    expect(response.status).toBe(409);
    expect((await response.json()).current.title).toBe('Conversation');
  });
  it('serializes concurrent writes to the same revision', async () => {
    const responses = await Promise.all(
      ['One', 'Two'].map((title) =>
        request(`/pages/${pageId}`, alice, 'PUT', {
          title,
          notebookId,
          document: doc,
          baseVersion: 1,
          mutationId: crypto.randomUUID(),
        }),
      ),
    );
    expect(responses.map((r) => r.status).sort()).toEqual([200, 409]);
  });
  it('rejects fake provenance and audio fields', async () => {
    const forged = structuredClone(doc);
    forged.blocks[1].source = 'transcript';
    expect(
      (
        await request(`/pages/${pageId}`, alice, 'PUT', {
          title: 'Forged',
          notebookId,
          document: forged,
          baseVersion: 2,
          mutationId: crypto.randomUUID(),
        })
      ).status,
    ).toBe(422);
    expect(
      (
        await request(`/pages/${pageId}`, alice, 'PUT', {
          title: 'Audio',
          notebookId,
          document: { ...doc, audio: 'bad' },
          baseVersion: 2,
          mutationId: crypto.randomUUID(),
        })
      ).status,
    ).toBe(400);
  });
  it('fails capture honestly and preserves notes', async () => {
    expect((await request('/capture/start', alice, 'POST', {})).status).toBe(503);
    expect((await request(`/pages/${pageId}`)).status).toBe(200);
  });
  it('exports owned data and cascades page deletion into history', async () => {
    const data = await (await request('/account/export')).json();
    expect(data.pages.length).toBe(1);
    expect(data.revisions.length).toBe(2);
    expect((await request(`/pages/${pageId}`, alice, 'DELETE')).status).toBe(200);
    expect((await request(`/pages/${pageId}/history`)).status).toBe(404);
    expect((await (await request('/account/export')).json()).revisions).toEqual([]);
  });
  it('deletes the account and invalidates its sessions', async () => {
    expect((await request('/account', bob, 'DELETE', { confirmation: 'DELETE' })).status).toBe(200);
    expect((await request('/notebooks', bob)).status).toBe(401);
  });
});
