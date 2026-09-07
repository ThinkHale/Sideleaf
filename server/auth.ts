import { betterAuth } from 'better-auth';
import { drizzleAdapter } from '@better-auth/drizzle-adapter';
import type { Database } from './database';
import type { Config } from './config';
import * as schema from './schema';
export function createAuth(db: Database, config: Config) {
  return betterAuth({
    appName: config.name,
    baseURL: config.origin,
    secret: config.secret,
    database: drizzleAdapter(db, { provider: 'pg', schema }),
    trustedOrigins: [config.origin],
    emailAndPassword: { enabled: !config.production, minPasswordLength: 10 },
    socialProviders:
      process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET
        ? {
            google: {
              clientId: process.env.GOOGLE_CLIENT_ID,
              clientSecret: process.env.GOOGLE_CLIENT_SECRET,
            },
          }
        : {},
    session: { expiresIn: 60 * 60 * 24 * 7, updateAge: 60 * 60 * 24 },
    advanced: { useSecureCookies: config.production },
    rateLimit: {
      enabled: true,
      window: 60,
      max: 60,
      ...(!config.production
        ? {
            customRules: {
              '/sign-up/email': { window: 60, max: 30 },
              '/sign-in/email': { window: 60, max: 30 },
            },
          }
        : {}),
    },
    logger: { disabled: true },
  });
}
