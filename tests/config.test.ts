import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { configuration, passwordAuthEnabled } from '../server/config';

beforeEach(() => {
  vi.stubEnv('NODE_ENV', 'production');
  vi.stubEnv('DATABASE_URL', 'postgresql://synthetic.invalid/sideleaf');
  vi.stubEnv('BETTER_AUTH_SECRET', 'synthetic-test-secret-0000000000000000000000000');
  for (const name of [
    'APP_ORIGIN',
    'VERCEL',
    'VERCEL_ENV',
    'VERCEL_URL',
    'VERCEL_PROJECT_PRODUCTION_URL',
    'ENABLE_PASSWORD_AUTH',
  ])
    vi.stubEnv(name, undefined);
});

afterEach(() => vi.unstubAllEnvs());

describe('production password authentication opt-in', () => {
  it.each([undefined, '', 'false', 'TRUE', '1'])('stays disabled for %s', (value) => {
    vi.stubEnv('ENABLE_PASSWORD_AUTH', value);
    expect(passwordAuthEnabled({ production: true })).toBe(false);
  });

  it('enables the production beta only with the explicit true value', () => {
    vi.stubEnv('ENABLE_PASSWORD_AUTH', 'true');
    expect(passwordAuthEnabled({ production: true })).toBe(true);
  });

  it('preserves local development sign-in without a cloud opt-in', () => {
    expect(passwordAuthEnabled({ production: false })).toBe(true);
  });
});

describe('deployment origin selection', () => {
  it('uses a preview deployment address instead of the production address', async () => {
    vi.stubEnv('VERCEL', '1');
    vi.stubEnv('VERCEL_ENV', 'preview');
    vi.stubEnv('VERCEL_URL', 'sideleaf-preview-123.vercel.app');
    vi.stubEnv('VERCEL_PROJECT_PRODUCTION_URL', 'sideleaf.vercel.app');
    expect((await configuration()).origin).toBe('https://sideleaf-preview-123.vercel.app');
  });

  it('uses the stable production address instead of the deployment hash', async () => {
    vi.stubEnv('VERCEL', '1');
    vi.stubEnv('VERCEL_ENV', 'production');
    vi.stubEnv('VERCEL_URL', 'sideleaf-deployment-123.vercel.app');
    vi.stubEnv('VERCEL_PROJECT_PRODUCTION_URL', 'sideleaf.vercel.app');
    expect((await configuration()).origin).toBe('https://sideleaf.vercel.app');
  });

  it('falls back to the production deployment address when no stable address exists', async () => {
    vi.stubEnv('VERCEL', '1');
    vi.stubEnv('VERCEL_ENV', 'production');
    vi.stubEnv('VERCEL_URL', 'sideleaf-deployment-123.vercel.app');
    expect((await configuration()).origin).toBe('https://sideleaf-deployment-123.vercel.app');
  });

  it('honors an explicit custom domain over Vercel addresses', async () => {
    vi.stubEnv('APP_ORIGIN', 'https://notes.example.com');
    vi.stubEnv('VERCEL', '1');
    vi.stubEnv('VERCEL_ENV', 'production');
    vi.stubEnv('VERCEL_PROJECT_PRODUCTION_URL', 'sideleaf.vercel.app');
    expect((await configuration()).origin).toBe('https://notes.example.com');
  });

  it('does not borrow a production address when a preview address is missing', async () => {
    vi.stubEnv('VERCEL', '1');
    vi.stubEnv('VERCEL_ENV', 'preview');
    vi.stubEnv('VERCEL_PROJECT_PRODUCTION_URL', 'sideleaf.vercel.app');
    await expect(configuration()).rejects.toThrow('HTTPS APP_ORIGIN');
  });

  it('ignores Vercel host variables outside a Vercel runtime', async () => {
    vi.stubEnv('VERCEL_PROJECT_PRODUCTION_URL', 'sideleaf.vercel.app');
    vi.stubEnv('VERCEL_URL', 'sideleaf-preview-123.vercel.app');
    await expect(configuration()).rejects.toThrow('HTTPS APP_ORIGIN');
  });

  it('keeps the existing local development address', async () => {
    vi.stubEnv('NODE_ENV', 'development');
    const config = await configuration();
    expect(config.production).toBe(false);
    expect(config.origin).toBe('http://127.0.0.1:5173');
  });
});
