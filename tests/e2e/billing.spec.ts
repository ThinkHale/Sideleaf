import { test, expect, type Page } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

const billing = {
  plan: 'free',
  provider: null,
  status: 'free',
  currentPeriodEnd: null,
  cancelAtPeriodEnd: false,
  paymentReview: false,
  checkoutReady: false,
  portalReady: false,
  mode: 'live',
  price: { amount: 29, currency: 'USD', interval: 'month' },
  message: 'Subscriptions are not available for purchase yet.',
};
const usage = {
  plan: 'free',
  usedSeconds: 300,
  remainingSeconds: 6900,
  meetingLimitSeconds: 3600,
  resetAt: '2026-10-01T00:00:00.000Z',
  activeSessionId: null,
};

async function register(page: Page) {
  await page.goto('/');
  await page.getByLabel('Your name').fill('Billing QA');
  await page
    .getByLabel('Email', { exact: true })
    .fill(`billing-${crypto.randomUUID()}@example.test`);
  await page.getByLabel('Password', { exact: false }).fill('local-billing-Password-123');
  await page.getByRole('button', { name: 'Create account', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your notebooks' })).toBeVisible();
}

test('plan and usage wait for the server, and unavailable purchases remain disabled', async ({
  page,
}) => {
  let ready!: () => void;
  const responseReady = new Promise<void>((resolve) => {
    ready = resolve;
  });
  await page.route('**/api/billing', async (route) => {
    await responseReady;
    await route.fulfill({ json: billing });
  });
  await page.route('**/api/capture/usage', (route) => route.fulfill({ json: usage }));
  await register(page);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const plans = page.getByRole('region', { name: 'Plan and usage' });
  await expect(plans.getByText('Loading your plan and usage...')).toBeVisible();
  await expect(plans.getByText('Current plan: Free', { exact: true })).toHaveCount(0);
  ready();
  await expect(plans.getByText('Current plan: Free', { exact: true })).toBeVisible();
  await expect(plans.getByText('5 min', { exact: true })).toBeVisible();
  await expect(plans.getByText('115 min', { exact: true })).toBeVisible();
  await expect(plans.getByText('Pro · $29.00/month', { exact: true })).toBeVisible();
  await expect(plans.getByRole('button', { name: 'Upgrade to Pro', exact: true })).toBeDisabled();
  await expect(plans.getByText(billing.message, { exact: true })).toBeVisible();
  const evidence = path.join(tmpdir(), 'sideleaf-billing-qa');
  await mkdir(evidence, { recursive: true });
  await page.screenshot({ path: path.join(evidence, 'desktop-plans.png') });
  await page.setViewportSize({ width: 390, height: 844 });
  await plans.scrollIntoViewIfNeeded();
  await page.screenshot({ path: path.join(evidence, 'phone-plans.png') });
  expect(
    await page.locator('dialog').evaluate((element) => element.scrollWidth <= element.clientWidth),
  ).toBe(true);
});

test('a failed usage request reports failure instead of inventing an allowance', async ({
  page,
}) => {
  let fail = true;
  await page.route('**/api/billing', (route) => route.fulfill({ json: billing }));
  await page.route('**/api/capture/usage', (route) =>
    fail
      ? route.fulfill({ status: 503, json: { error: 'Temporarily unavailable' } })
      : route.fulfill({ json: usage }),
  );
  await register(page);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const plans = page.getByRole('region', { name: 'Plan and usage' });
  await expect(plans.getByRole('alert')).toHaveText(
    'We could not load your plan and usage. Your notes are still available.',
  );
  await expect(plans.getByText('Current plan: Free', { exact: true })).toHaveCount(0);
  fail = false;
  await plans.getByRole('button', { name: 'Refresh status', exact: true }).click();
  await expect(plans.getByText('115 min', { exact: true })).toBeVisible();
});

test('test checkout is explicit and a success URL cannot grant Pro', async ({ page }) => {
  await page.route('**/api/billing', (route) =>
    route.fulfill({
      json: {
        ...billing,
        mode: 'test',
        checkoutReady: true,
        message: null,
      },
    }),
  );
  await page.route('**/api/capture/usage', (route) => route.fulfill({ json: usage }));
  let submitted: unknown;
  await page.route('**/api/billing/checkout', (route) => {
    submitted = route.request().postDataJSON();
    return route.fulfill({
      json: { url: 'https://checkout.stripe.com/c/pay/synthetic-test-session' },
    });
  });
  await page.route('https://checkout.stripe.com/**', (route) =>
    route.fulfill({
      contentType: 'text/html',
      body: '<h1>Synthetic Stripe checkout</h1>',
    }),
  );
  await register(page);
  await page.evaluate(() => history.replaceState(null, '', '/?billing=success'));
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const plans = page.getByRole('region', { name: 'Plan and usage' });
  await expect(plans.getByText('Current plan: Free', { exact: true })).toBeVisible();
  await expect(
    plans.getByText('Test mode. Checkout uses Stripe test payments. No real payment is collected.'),
  ).toBeVisible();
  await expect(plans.getByText(/Waiting for payment confirmation/)).toBeVisible();
  await plans.getByRole('button', { name: 'Test Pro checkout', exact: true }).click();
  await expect(page).toHaveURL('https://checkout.stripe.com/c/pay/synthetic-test-session');
  expect(submitted).toEqual({});
});

test('an active Pro subscription opens the server-created management portal', async ({ page }) => {
  await page.route('**/api/billing', (route) =>
    route.fulfill({
      json: {
        ...billing,
        plan: 'pro',
        provider: 'stripe',
        status: 'active',
        currentPeriodEnd: '2026-10-07T00:00:00.000Z',
        cancelAtPeriodEnd: true,
        portalReady: true,
        checkoutReady: true,
        message: null,
      },
    }),
  );
  await page.route('**/api/capture/usage', (route) =>
    route.fulfill({
      json: {
        ...usage,
        plan: 'pro',
        remainingSeconds: null,
        meetingLimitSeconds: null,
      },
    }),
  );
  await page.route('**/api/billing/portal', (route) =>
    route.fulfill({
      json: {
        url: 'https://billing.stripe.com/p/session/synthetic-test-session',
      },
    }),
  );
  await page.route('https://billing.stripe.com/**', (route) =>
    route.fulfill({
      contentType: 'text/html',
      body: '<h1>Synthetic Stripe portal</h1>',
    }),
  );
  await register(page);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const plans = page.getByRole('region', { name: 'Plan and usage' });
  await expect(plans.getByText('Current plan: Pro', { exact: true })).toBeVisible();
  await expect(plans.getByText(/Pro access ends Oct 7, 2026/)).toBeVisible();
  await expect(plans.getByText('Unlimited', { exact: true })).toBeVisible();
  await expect(plans.getByRole('button', { name: 'Upgrade to Pro', exact: true })).toHaveCount(0);
  await plans.getByRole('button', { name: 'Manage subscription', exact: true }).click();
  await expect(page).toHaveURL('https://billing.stripe.com/p/session/synthetic-test-session');
});
