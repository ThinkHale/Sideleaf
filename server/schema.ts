import {
  pgTable,
  text,
  boolean,
  timestamp,
  integer,
  jsonb,
  primaryKey,
  index,
  bigint,
} from 'drizzle-orm/pg-core';
import type { NotebookDocument } from '../shared/domain.js';
export { billingCustomers, billingSubscriptions, billingEvents } from './billing-schema.js';
export {
  captureSessions,
  captureUsage,
  captureWatchdog,
  meetingTranscripts,
} from './capture-schema.js';

export const rateLimit = pgTable('auth_rate_limit', {
  id: text().primaryKey(),
  key: text().notNull().unique(),
  count: integer().notNull(),
  lastRequest: bigint('last_request', { mode: 'number' }).notNull(),
});

export const user = pgTable('auth_user', {
  id: text().primaryKey(),
  name: text().notNull(),
  email: text().notNull().unique(),
  emailVerified: boolean('email_verified').notNull().default(false),
  image: text(),
  createdAt: timestamp('created_at').notNull(),
  updatedAt: timestamp('updated_at').notNull(),
});
export const legalAcceptances = pgTable(
  'legal_acceptances',
  {
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    termsVersion: text('terms_version').notNull(),
    acceptedAt: timestamp('accepted_at', { withTimezone: true }).notNull().defaultNow(),
    recordingLawAcknowledgedAt: timestamp('recording_law_acknowledged_at', {
      withTimezone: true,
    })
      .notNull()
      .defaultNow(),
    legalBundleSha256: text('legal_bundle_sha256').notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.termsVersion] }),
    index('legal_acceptances_owner').on(t.userId),
  ],
);
export const session = pgTable('auth_session', {
  id: text().primaryKey(),
  expiresAt: timestamp('expires_at').notNull(),
  token: text().notNull().unique(),
  createdAt: timestamp('created_at').notNull(),
  updatedAt: timestamp('updated_at').notNull(),
  ipAddress: text('ip_address'),
  userAgent: text('user_agent'),
  userId: text('user_id')
    .notNull()
    .references(() => user.id, { onDelete: 'cascade' }),
});
export const account = pgTable('auth_account', {
  id: text().primaryKey(),
  accountId: text('account_id').notNull(),
  providerId: text('provider_id').notNull(),
  userId: text('user_id')
    .notNull()
    .references(() => user.id, { onDelete: 'cascade' }),
  accessToken: text('access_token'),
  refreshToken: text('refresh_token'),
  idToken: text('id_token'),
  accessTokenExpiresAt: timestamp('access_token_expires_at'),
  refreshTokenExpiresAt: timestamp('refresh_token_expires_at'),
  scope: text(),
  password: text(),
  createdAt: timestamp('created_at').notNull(),
  updatedAt: timestamp('updated_at').notNull(),
});
export const verification = pgTable('auth_verification', {
  id: text().primaryKey(),
  identifier: text().notNull(),
  value: text().notNull(),
  expiresAt: timestamp('expires_at').notNull(),
  createdAt: timestamp('created_at'),
  updatedAt: timestamp('updated_at'),
});
export const notebooks = pgTable(
  'notebooks',
  {
    id: text().primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    name: text().notNull(),
    color: text().notNull().default('#687354'),
    createdAt: timestamp('created_at').notNull().defaultNow(),
  },
  (t) => [index('notebooks_owner').on(t.userId)],
);
export const pages = pgTable(
  'pages',
  {
    id: text().primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    notebookId: text('notebook_id')
      .notNull()
      .references(() => notebooks.id, { onDelete: 'cascade' }),
    title: text().notNull(),
    document: jsonb().$type<NotebookDocument>().notNull(),
    version: integer().notNull().default(1),
    updatedAt: timestamp('updated_at').notNull().defaultNow(),
  },
  (t) => [index('pages_owner_notebook').on(t.userId, t.notebookId)],
);
export const revisions = pgTable(
  'page_revisions',
  {
    pageId: text('page_id')
      .notNull()
      .references(() => pages.id, { onDelete: 'cascade' }),
    version: integer().notNull(),
    title: text().notNull(),
    document: jsonb().$type<NotebookDocument>().notNull(),
    mutationId: text('mutation_id').notNull(),
    createdAt: timestamp('created_at').notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.pageId, t.version] })],
);
