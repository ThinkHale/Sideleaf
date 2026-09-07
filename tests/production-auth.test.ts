import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { eq } from 'drizzle-orm';
import { createApp } from '../server/app';
import { openDatabase } from '../server/database';
import { rateLimit, user } from '../server/schema';
import type { Config } from '../server/config';

const origin = 'https://sideleaf-beta.example';
const password = 'synthetic-beta-password-47';
const config: Config = {
  origin,
  production: true,
  secret: 'synthetic-test-secret-0000000000000000000000000',
  name: 'Sideleaf test',
  freeMinutes: 120,
  meetingMinutes: 60,
  price: 29,
};
let storage: Awaited<ReturnType<typeof openDatabase>>;

function request(
  app: ReturnType<typeof createApp>,
  path: string,
  body?: unknown,
  options: { cookie?: string; ip?: string; origin?: string } = {},
) {
  return app.request(`${origin}/api${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: {
      origin: options.origin ?? origin,
      'content-type': 'application/json',
      'x-forwarded-for': options.ip ?? '203.0.113.20',
      ...(options.cookie ? { cookie: options.cookie } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

beforeAll(async () => {
  // The storage is isolated in memory; the app below uses real production auth options.
  vi.stubEnv('NODE_ENV', 'test');
  storage = await openDatabase(undefined, ':memory:');
});

beforeEach(async () => {
  vi.stubEnv('ENABLE_PASSWORD_AUTH', 'true');
  vi.stubEnv('GOOGLE_CLIENT_ID', undefined);
  vi.stubEnv('GOOGLE_CLIENT_SECRET', undefined);
  await storage.db.delete(rateLimit);
});

afterEach(() => vi.unstubAllEnvs());
afterAll(async () => storage.close());

describe.sequential('production email/password beta', () => {
  it('disables both the advertised option and auth endpoints by default', async () => {
    vi.stubEnv('ENABLE_PASSWORD_AUTH', undefined);
    const app = createApp(storage.db, config);
    const advertised = await (await request(app, '/config')).json();
    expect(advertised).toMatchObject({ development: false, passwordAuth: false });
    const credentials = { email: 'disabled@example.test', password };
    const signup = await request(app, '/auth/sign-up/email', { ...credentials, name: 'Disabled' });
    expect(signup.status).toBe(400);
    expect((await signup.json()).code).toBe('EMAIL_PASSWORD_SIGN_UP_DISABLED');
    const signin = await request(app, '/auth/sign-in/email', credentials);
    expect(signin.status).toBe(400);
    expect((await signin.json()).code).toBe('EMAIL_PASSWORD_DISABLED');
    expect(await storage.db.select().from(user).where(eq(user.email, credentials.email))).toEqual(
      [],
    );
  });

  it('enables signup and signin with secure sessions that survive a new app instance', async () => {
    const app = createApp(storage.db, config);
    expect(await (await request(app, '/config')).json()).toMatchObject({
      development: false,
      passwordAuth: true,
    });
    const credentials = { email: 'beta-user@example.test', password };
    const short = await request(app, '/auth/sign-up/email', {
      ...credentials,
      name: 'Beta user',
      password: 'short',
    });
    expect(short.status).toBe(400);
    expect(await storage.db.select().from(user).where(eq(user.email, credentials.email))).toEqual(
      [],
    );

    const signup = await request(app, '/auth/sign-up/email', { ...credentials, name: 'Beta user' });
    expect(signup.status, await signup.clone().text()).toBe(200);
    const signupCookies = signup.headers.getSetCookie();
    expect(
      signupCookies.some((cookie) => cookie.includes('Secure') && cookie.includes('HttpOnly')),
    ).toBe(true);
    const freshApp = createApp(storage.db, config);
    const signin = await request(freshApp, '/auth/sign-in/email', credentials);
    expect(signin.status, await signin.clone().text()).toBe(200);
    const cookie = signin.headers
      .getSetCookie()
      .map((value) => value.split(';')[0])
      .join('; ');
    expect(
      (await request(createApp(storage.db, config), '/pages', undefined, { cookie })).status,
    ).toBe(200);
    expect((await request(freshApp, '/pages')).status).toBe(401);
  });

  it('rejects a signup from another origin after production password login is enabled', async () => {
    const app = createApp(storage.db, config);
    const email = 'foreign-origin@example.test';
    const response = await request(
      app,
      '/auth/sign-up/email',
      {
        email,
        password,
        name: 'Foreign origin',
      },
      { origin: 'https://untrusted.example' },
    );
    expect(response.status).toBe(403);
    expect(await storage.db.select().from(user).where(eq(user.email, email))).toEqual([]);
  });

  it('shares a database sign-in limit across new app instances and keeps client IPs separate', async () => {
    const credentials = { email: 'missing-account@example.test', password };
    for (let attempt = 0; attempt < 3; attempt++) {
      const response = await request(
        createApp(storage.db, config),
        '/auth/sign-in/email',
        credentials,
      );
      expect(response.status, await response.clone().text()).toBe(401);
    }
    const limited = await request(
      createApp(storage.db, config),
      '/auth/sign-in/email',
      credentials,
    );
    expect(limited.status).toBe(429);
    expect(Number(limited.headers.get('x-retry-after'))).toBeGreaterThan(0);
    const rows = await storage.db.select().from(rateLimit);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ key: '203.0.113.20|/sign-in/email', count: 3 });
    expect(typeof rows[0].lastRequest).toBe('number');

    const anotherClient = await request(
      createApp(storage.db, config),
      '/auth/sign-in/email',
      credentials,
      { ip: '203.0.113.21' },
    );
    expect(anotherClient.status).toBe(401);
    expect(await storage.db.select().from(rateLimit)).toHaveLength(2);
  });
});
