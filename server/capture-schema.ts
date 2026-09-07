import {
  pgTable,
  text,
  timestamp,
  integer,
  bigint,
  primaryKey,
  index,
  uniqueIndex,
} from 'drizzle-orm/pg-core';
import { user, pages } from './schema.js';

export const captureSessions = pgTable(
  'capture_sessions',
  {
    id: text().primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    pageId: text('page_id')
      .notNull()
      .references(() => pages.id, { onDelete: 'cascade' }),
    callId: text('call_id'),
    state: text().notNull().default('starting'),
    stopReason: text('stop_reason'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    activeAt: timestamp('active_at', { withTimezone: true }),
    endedAt: timestamp('ended_at', { withTimezone: true }),
    leaseExpiresAt: timestamp('lease_expires_at', { withTimezone: true }).notNull(),
    deadlineAt: timestamp('deadline_at', { withTimezone: true }).notNull(),
    lastBilledAt: timestamp('last_billed_at', { withTimezone: true }),
    billedMs: integer('billed_ms').notNull().default(0),
    observerId: text('observer_id'),
  },
  (t) => [
    index('capture_sessions_owner').on(t.userId, t.state),
    index('capture_sessions_expiry').on(t.state, t.leaseExpiresAt),
  ],
);

export const captureUsage = pgTable(
  'capture_usage',
  {
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    periodStart: timestamp('period_start', { withTimezone: true }).notNull(),
    periodEnd: timestamp('period_end', { withTimezone: true }).notNull(),
    usedMs: bigint('used_ms', { mode: 'number' }).notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.userId, t.periodStart] })],
);

export const meetingTranscripts = pgTable(
  'meeting_transcripts',
  {
    id: text().primaryKey(),
    sessionId: text('session_id')
      .notNull()
      .references(() => captureSessions.id, { onDelete: 'cascade' }),
    pageId: text('page_id')
      .notNull()
      .references(() => pages.id, { onDelete: 'cascade' }),
    itemId: text('item_id').notNull(),
    previousItemId: text('previous_item_id'),
    text: text().notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex('transcript_provider_item').on(t.sessionId, t.itemId),
    index('transcript_page').on(t.pageId),
  ],
);

export const captureWatchdog = pgTable('capture_watchdog', {
  id: text().primaryKey(),
  checkedAt: timestamp('checked_at', { withTimezone: true }).notNull(),
});
