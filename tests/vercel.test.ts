import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Hono } from 'hono';

const mocks = vi.hoisted(() => ({
  configure: vi.fn(),
  open: vi.fn(),
  createApp: vi.fn(),
  attach: vi.fn(),
  close: vi.fn(),
  query: vi.fn(),
}));
vi.mock('../server/config', () => ({ configuration: mocks.configure }));
vi.mock('../server/database', () => ({ openDatabase: mocks.open }));
vi.mock('../server/app', () => ({ createApp: mocks.createApp }));
vi.mock('@vercel/functions', () => ({ attachDatabasePool: mocks.attach }));

const origin = 'https://sideleaf.example';
const connection = 'postgresql://synthetic.invalid/sideleaf';
const pool = { query: mocks.query };

async function entry() {
  return (await import('../api/index')).default;
}

beforeEach(() => {
  vi.resetModules();
  vi.resetAllMocks();
  vi.stubEnv('NODE_ENV', 'production');
  vi.stubEnv('DATABASE_URL', connection);
  mocks.configure.mockResolvedValue({ production: true, origin });
  mocks.open.mockResolvedValue({ db: {}, pool, close: mocks.close });
  mocks.close.mockResolvedValue(undefined);
  mocks.query.mockResolvedValue({ rows: [] });
  mocks.createApp.mockImplementation(() => {
    const app = new Hono();
    app.all('/api/echo/nested', async (c) =>
      c.json({
        path: c.req.path,
        method: c.req.method,
        query: c.req.query('page'),
        cookie: c.req.header('cookie'),
        body: await c.req.text(),
      }),
    );
    return app;
  });
  vi.spyOn(console, 'error').mockImplementation(() => undefined);
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

describe('Vercel cloud entry', () => {
  it.each([
    ['NODE_ENV', 'development'],
    ['DATABASE_URL', ''],
  ])('rejects missing cloud configuration before local setup: %s', async (key, value) => {
    vi.stubEnv(key, value);
    const handler = await entry();
    const response = await handler.fetch(new Request(`${origin}/api/health`));
    expect(response.status).toBe(503);
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(response.headers.get('content-type')).toContain('application/json');
    expect(mocks.configure).not.toHaveBeenCalled();
    expect(mocks.open).not.toHaveBeenCalled();
  });

  it('shares one initialization and forwards nested API requests unchanged', async () => {
    const handler = await entry();
    expect(mocks.open).not.toHaveBeenCalled();
    const requests = Array.from({ length: 3 }, () =>
      handler.fetch(
        new Request(`${origin}/api/echo/nested?page=2`, {
          method: 'PUT',
          headers: { cookie: 'session=synthetic' },
          body: 'draft notes',
        }),
      ),
    );
    const responses = await Promise.all(requests);
    expect(mocks.configure).toHaveBeenCalledTimes(1);
    expect(mocks.open).toHaveBeenCalledExactlyOnceWith(connection, undefined, { migrate: false });
    expect(mocks.attach).toHaveBeenCalledExactlyOnceWith(pool);
    expect(mocks.query).toHaveBeenCalledExactlyOnceWith('SELECT id FROM auth_user LIMIT 0');
    expect(await responses[0].json()).toEqual({
      path: '/api/echo/nested',
      method: 'PUT',
      query: '2',
      cookie: 'session=synthetic',
      body: 'draft notes',
    });
  });

  it('retries a failed cold start without exposing connection errors', async () => {
    const privateMessage = 'postgresql://private-user:private-password@database.invalid/db';
    mocks.open.mockRejectedValueOnce(new Error(privateMessage));
    const handler = await entry();
    const failed = await handler.fetch(new Request(`${origin}/api/echo/nested`));
    expect(failed.status).toBe(503);
    expect(await failed.text()).not.toContain(privateMessage);
    expect(JSON.stringify(vi.mocked(console.error).mock.calls)).not.toContain(privateMessage);
    const recovered = await handler.fetch(new Request(`${origin}/api/echo/nested`));
    expect(recovered.status).toBe(200);
    expect(mocks.open).toHaveBeenCalledTimes(2);
  });

  it('closes the pool when app initialization fails and can recover', async () => {
    mocks.createApp.mockImplementationOnce(() => {
      throw new Error('Synthetic initialization failure');
    });
    const handler = await entry();
    expect((await handler.fetch(new Request(`${origin}/api/health`))).status).toBe(503);
    expect(mocks.close).toHaveBeenCalledTimes(1);
    expect(mocks.attach).not.toHaveBeenCalled();
    expect((await handler.fetch(new Request(`${origin}/api/echo/nested`))).status).toBe(200);
  });

  it('closes an unusable pool and retries after a failed schema or permission check', async () => {
    const privateMessage =
      'Authentication failed for postgresql://user:private-password@db.invalid';
    mocks.query.mockRejectedValueOnce(new Error(privateMessage));
    const handler = await entry();
    const failed = await handler.fetch(new Request(`${origin}/api/health`));
    expect(failed.status).toBe(503);
    expect(failed.headers.get('cache-control')).toBe('no-store');
    expect(await failed.text()).not.toContain(privateMessage);
    expect(JSON.stringify(vi.mocked(console.error).mock.calls)).not.toContain(privateMessage);
    expect(mocks.close).toHaveBeenCalledTimes(1);
    expect(mocks.createApp).not.toHaveBeenCalled();
    expect(mocks.attach).not.toHaveBeenCalled();

    const recovered = await handler.fetch(new Request(`${origin}/api/echo/nested`));
    expect(recovered.status).toBe(200);
    expect(mocks.open).toHaveBeenCalledTimes(2);
    expect(mocks.query).toHaveBeenCalledTimes(2);
    expect(mocks.attach).toHaveBeenCalledExactlyOnceWith(pool);
  });

  it('returns JSON for an unknown API path without serving the web shell', async () => {
    const handler = await entry();
    const response = await handler.fetch(new Request(`${origin}/api/not-a-route`));
    expect(response.status).toBe(404);
    expect(response.headers.get('content-type')).toContain('application/json');
    expect(await response.json()).toEqual({ error: 'API route not found.' });
  });
});
