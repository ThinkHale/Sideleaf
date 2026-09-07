import { test, expect } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

test('focus keeps the notebook centered and readable across desktop, tablet and phone widths', async ({
  page,
}) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    // The sandbox can block the optional Google font; the system font remains readable.
    if (
      message.location().url.startsWith('https://fonts.googleapis.com/') &&
      message.text().includes('net::ERR_NETWORK_ACCESS_DENIED')
    ) {
      return;
    }
    if (message.type() === 'error') errors.push(`${message.location().url}: ${message.text()}`);
  });
  const evidence = path.join(tmpdir(), 'sideleaf-focus-qa');
  await mkdir(evidence, { recursive: true });
  await page.goto('/');
  await expect(page).toHaveTitle(/Sideleaf/);
  await page.getByLabel('Your name').fill('Focus QA');
  await page.getByLabel('Email', { exact: true }).fill(`focus-${crypto.randomUUID()}@example.test`);
  await page.getByLabel('Password', { exact: false }).fill('local-focus-Password-123');
  await page.getByRole('button', { name: 'Create account', exact: true }).click();
  await page.getByRole('button', { name: 'Open a synthetic example' }).click();
  const note = page.getByLabel('Note text', { exact: true }).first();
  const text =
    'A complete meeting note should stay readable when the notebook enters focus mode. Keep the discussion, decisions and next steps together, with room to write and comfortable space on both sides of the page.';
  await note.fill(text);
  await expect(page.locator('.sync-status')).toHaveText('Saved');

  for (const [name, width, height] of [
    ['desktop', 1536, 1024],
    ['wide-desktop', 1920, 1080],
    ['laptop', 1280, 900],
    ['ipad-landscape', 1180, 820],
    ['ipad-portrait', 820, 1180],
    ['phone', 390, 844],
  ] as const) {
    await page.setViewportSize({ width, height });
    await page.getByRole('button', { name: 'Focus', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Exit focus', exact: true })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    await expect(page.locator('.sidebar')).toBeHidden();
    await expect(page.locator('.margin')).toBeHidden();
    await expect(page.locator('.paper')).toBeVisible();
    await expect(page.locator('.writing-toolbar')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Back to pages', exact: true })).toBeVisible();
    await expect(page.locator('.mic-status')).toBeVisible();
    await expect(note).toHaveValue(text);
    await expect
      .poll(() => note.evaluate((element) => element.scrollHeight <= element.clientHeight + 1))
      .toBe(true);
    await page.screenshot({ path: path.join(evidence, `${name}-focus.png`), fullPage: true });

    const paper = (await page.locator('.paper').boundingBox())!;
    expect(Math.abs(paper.x + paper.width / 2 - width / 2), `${name}: centered paper`).toBeLessThan(
      1,
    );
    expect(paper.width, `${name}: readable paper width`).toBeCloseTo(
      Math.min(900, width - (width <= 700 ? 24 : 64)),
      0,
    );
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
      `${name}: no horizontal scrolling`,
    ).toBe(true);
    await expect(page.locator('vite-error-overlay')).toHaveCount(0);

    await page.getByRole('button', { name: 'Exit focus', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Focus', exact: true })).toHaveAttribute(
      'aria-pressed',
      'false',
    );
    if (width > 700) await expect(page.locator('.sidebar')).toBeVisible();
    if (width > 1000) await expect(page.locator('.margin')).toBeVisible();
    await expect(note).toHaveValue(text);
  }

  // Entering focus from the mobile margin must still reveal the notebook, then restore the tab.
  await page.getByRole('button', { name: 'Preparation & follow-ups' }).click();
  await expect(page.locator('.paper')).toBeHidden();
  await page.getByRole('button', { name: 'Focus', exact: true }).click();
  await expect(page.locator('.paper')).toBeVisible();
  await expect(note).toHaveValue(text);
  await page.getByRole('button', { name: 'Exit focus', exact: true }).click();
  await expect(page.locator('.margin')).toBeVisible();
  await expect(page.locator('.paper')).toBeHidden();
  expect(errors).toEqual([]);
});
