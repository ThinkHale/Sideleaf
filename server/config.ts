import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { z } from 'zod';
import { join } from 'node:path';
import { appDataDirectory } from './paths';
export async function configuration() {
  const production = process.env.NODE_ENV === 'production';
  const origin = process.env.APP_ORIGIN || 'http://127.0.0.1:5173';
  let secret = process.env.BETTER_AUTH_SECRET;
  if (
    production &&
    (!process.env.DATABASE_URL || !secret || secret.length < 32 || !origin.startsWith('https://'))
  )
    throw new Error(
      'Production requires DATABASE_URL, a strong BETTER_AUTH_SECRET and an HTTPS APP_ORIGIN.',
    );
  if (!secret) {
    await mkdir(appDataDirectory, { recursive: true });
    const secretPath = join(appDataDirectory, 'auth-secret');
    try {
      secret = await readFile(secretPath, 'utf8');
    } catch {
      secret = randomBytes(48).toString('base64url');
      await writeFile(secretPath, secret, { mode: 0o600 });
    }
  }
  const positive = z.coerce.number().positive();
  return {
    production,
    origin,
    secret,
    name: process.env.PRODUCT_NAME || 'Sideleaf',
    freeMinutes: positive.parse(process.env.FREE_MONTHLY_MINUTES || 120),
    meetingMinutes: positive.parse(process.env.FREE_MEETING_MINUTES || 60),
    price: positive.parse(process.env.PRO_PRICE_USD || 29),
  };
}
export type Config = Awaited<ReturnType<typeof configuration>>;
