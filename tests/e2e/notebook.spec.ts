import { test, expect, type Page } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
const evidence = path.join(tmpdir(), 'meeting-notebook-qa');
async function register(page: Page) {
  await page.goto('/');
  await page.getByLabel('Your name').fill('Synthetic QA');
  await page.getByLabel('Email', { exact: true }).fill(`qa-${crypto.randomUUID()}@example.test`);
  await page.getByLabel('Password', { exact: false }).fill('local-qa-Password-123');
  await page.getByRole('button', { name: 'Create account', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your notebooks' })).toBeVisible();
}
async function waitSaved(page: Page) {
  await expect(page.locator('.sync-status')).toHaveText('Saved');
}
test.beforeAll(async () => {
  await mkdir(evidence, { recursive: true });
});

test('real account, preparation, note persistence, selection, source changes and export', async ({
  page,
}) => {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await register(page);
  await page.getByRole('button', { name: 'Open a synthetic example' }).click();
  await expect(page.getByLabel('Page title')).toHaveValue('Project conversation (example)');
  await page.getByLabel('Page title').fill('Project conversation');
  await waitSaved(page);
  await page.getByRole('button', { name: 'Select', exact: true }).click();
  await page
    .locator('[data-start]')
    .filter({ hasText: /^priorities$/ })
    .click();
  await page.getByRole('button', { name: 'Follow up', exact: true }).click();
  await expect(page.getByLabel('Follow-up question')).toHaveValue(
    'What should we clarify about "priorities"?',
  );
  await page.getByLabel('Follow-up question').fill('Which priority should we address first?');
  await page
    .locator('[data-start]')
    .filter({ hasText: /^clear$/ })
    .click();
  await page.getByRole('button', { name: 'Important', exact: true }).click();
  await expect(page.locator('.marked-word')).toHaveCount(2);
  await waitSaved(page);
  await page.screenshot({ path: path.join(evidence, 'desktop.png'), fullPage: true });
  await page.getByRole('button', { name: 'Prepare a meeting', exact: true }).click();
  await page.getByLabel('Meeting type').selectOption('Discovery');
  await page.getByRole('button', { name: 'Fill empty fields from template' }).click();
  await expect(page.getByLabel('Desired outcome')).toHaveValue(
    'Understand the problem before proposing a solution.',
  );
  await page.getByLabel('Participants', { exact: true }).fill('Alex, Jamie (synthetic)');
  await page.getByRole('checkbox').check();
  await page.getByRole('button', { name: 'Check capture readiness' }).click();
  await expect(
    page.getByText('Live transcription is not connected in this build.', { exact: false }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Save preparation' }).click();
  await waitSaved(page);
  await page.reload();
  await page.getByRole('button', { name: /Project conversation.*Prepared meeting/ }).click();
  await expect(page.getByLabel('Follow-up question')).toHaveValue(
    'Which priority should we address first?',
  );
  const text = await page.getByLabel('Note text').nth(1).inputValue();
  await page.getByLabel('Note text').nth(1).fill(text.replace('priorities', 'budgets'));
  await expect(page.getByText('Source changed', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Export', exact: true }).click();
  const download = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Markdown', exact: true }).click();
  expect((await download).suggestedFilename()).toBe('Project conversation.md');
  await page.getByRole('button', { name: 'Close dialog' }).click();
  expect(errors).toEqual([]);
});

test('ink circles stay ordinary ink in Write, Mark performs geometric text selection', async ({
  page,
}) => {
  await register(page);
  await page.getByRole('button', { name: 'Open a synthetic example' }).click();
  await waitSaved(page);
  await page.getByRole('button', { name: 'Write', exact: true }).click();
  const target = page.locator('[data-start]').filter({ hasText: /^priorities$/ });
  const bounds = (await target.boundingBox())!;
  async function circle() {
    const cx = bounds.x + bounds.width / 2,
      cy = bounds.y + bounds.height / 2,
      rx = bounds.width / 2 + 6,
      ry = bounds.height / 2 + 5;
    await page.mouse.move(cx + rx, cy);
    await page.mouse.down();
    for (let i = 1; i <= 40; i++) {
      const a = (i * Math.PI * 2) / 40;
      await page.mouse.move(cx + Math.cos(a) * rx, cy + Math.sin(a) * ry);
    }
    await page.mouse.up();
  }
  await circle();
  await expect(page.locator('.page-footer')).toContainText('1 ink strokes');
  await expect(page.locator('.important-item')).toHaveCount(0);
  await page.getByRole('button', { name: 'Select', exact: true }).click();
  const ink = page.getByRole('button', { name: 'Ink stroke 1', exact: true });
  const originalPath = await ink.getAttribute('d');
  await ink.focus();
  await ink.press('ArrowRight');
  await expect(ink).not.toHaveAttribute('d', originalPath!);
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await expect(ink).toHaveAttribute('d', originalPath!);
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await expect(page.locator('.page-footer')).toContainText('0 ink strokes');
  await page.getByRole('button', { name: 'Mark', exact: true }).click();
  await circle();
  await expect(page.locator('.important-item')).toContainText('priorities');
  await expect(page.locator('.page-footer')).toContainText('0 ink strokes');
  await page.setViewportSize({ width: 820, height: 1180 });
  await expect(page.locator('.marked-word')).toHaveText('priorities');
  await page.screenshot({ path: path.join(evidence, 'ipad-portrait.png'), fullPage: true });
});

test('offline manual editing reconnects without losing notes', async ({ page, context }) => {
  await register(page);
  await page.getByRole('button', { name: 'Create a blank page', exact: true }).click();
  await page.getByLabel('Page title').fill('Offline notebook');
  await waitSaved(page);
  await context.setOffline(true);
  await page
    .getByLabel('Note text', { exact: true })
    .fill('This thought was written while offline.');
  await expect(page.locator('.sync-status')).toHaveText('Saved on device');
  await context.setOffline(false);
  await waitSaved(page);
  await page.reload();
  await page.getByRole('button', { name: /Offline notebook.*Personal notes/ }).click();
  await expect(page.getByLabel('Note text', { exact: true })).toHaveValue(
    'This thought was written while offline.',
  );
});

test('two browser tabs recover conflicting edits as separate pages', async ({ page, context }) => {
  await register(page);
  await page.getByRole('button', { name: 'Create a blank page', exact: true }).click();
  await page.getByLabel('Page title').fill('Concurrent note');
  await waitSaved(page);
  const other = await context.newPage();
  await other.goto('/');
  await other.getByRole('button', { name: /Concurrent note.*Personal notes/ }).click();
  await page.getByLabel('Note text', { exact: true }).fill('First writer');
  await waitSaved(page);
  await other.getByLabel('Note text', { exact: true }).fill('Second writer');
  await expect(other.getByText('There’s another saved version.')).toBeVisible();
  await other.getByRole('button', { name: 'Keep both versions' }).click();
  await expect(other.getByLabel('Page title')).toHaveValue('Concurrent note (recovered copy)');
  await expect(other.getByLabel('Note text', { exact: true })).toHaveValue('Second writer');
  await waitSaved(other);
  await other.getByRole('button', { name: 'Back to pages' }).click();
  await expect(other.locator('.page-row')).toHaveCount(2);
});

test('phone and iPad landscape layouts preserve controls and microphone status', async ({
  page,
}) => {
  await register(page);
  await page.getByRole('button', { name: 'Open a synthetic example' }).click();
  await waitSaved(page);
  for (const [name, width, height] of [
    ['phone', 390, 844],
    ['ipad-landscape', 1180, 820],
  ] as const) {
    await page.setViewportSize({ width, height });
    await expect(page.getByLabel('Page title')).toBeVisible();
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    ).toBe(true);
    await expect(page.locator('.mic-status')).toBeVisible();
    await page.screenshot({ path: path.join(evidence, `${name}.png`), fullPage: true });
  }
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole('button', { name: 'Preparation & follow-ups' }).click();
  await expect(page.getByRole('button', { name: 'Prepare a meeting', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Notebook', exact: true }).click();
  await page.getByRole('button', { name: 'Focus', exact: true }).click();
  await expect(page.locator('.mic-status')).toBeVisible();
  await expect(page.getByLabel('Page title')).toBeVisible();
});
