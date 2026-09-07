import {
  boolean,
  index,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
} from 'drizzle-orm/pg-core';
import { user } from './schema.js';

export const billingCustomers = pgTable(
  'billing_customers',
  {
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    livemode: boolean().notNull(),
    customerId: text('customer_id'),
    checkoutAttempt: text('checkout_attempt').notNull(),
    checkoutSessionId: text('checkout_session_id'),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.livemode] }),
    uniqueIndex('billing_customer_stripe_id').on(t.customerId),
  ],
);

export const billingSubscriptions = pgTable(
  'billing_subscriptions',
  {
    id: text().primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    provider: text().$type<'stripe' | 'apple' | 'google'>().notNull(),
    providerSubscriptionId: text('provider_subscription_id').notNull(),
    livemode: boolean().notNull(),
    priceId: text('price_id'),
    plan: text().$type<'free' | 'pro'>().notNull().default('free'),
    status: text().notNull(),
    currentPeriodEnd: timestamp('current_period_end', { withTimezone: true }),
    cancelAtPeriodEnd: boolean('cancel_at_period_end').notNull().default(false),
    latestInvoiceId: text('latest_invoice_id'),
    revokedInvoiceId: text('revoked_invoice_id'),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex('billing_subscription_provider_id').on(
      t.provider,
      t.providerSubscriptionId,
      t.livemode,
    ),
    index('billing_subscriptions_owner').on(t.userId, t.livemode),
  ],
);

// Retain only delivery identifiers and timestamps, never the payment payload.
export const billingEvents = pgTable('billing_events', {
  id: text().primaryKey(),
  type: text().notNull(),
  livemode: boolean().notNull(),
  processedAt: timestamp('processed_at', { withTimezone: true }).notNull().defaultNow(),
});
