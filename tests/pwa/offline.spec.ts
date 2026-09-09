import { test, expect } from '@playwright/test';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { mkdir } from 'node:fs/promises';
test('built PWA reloads offline, syncs recovered text, and prints without excluded text', async ({
  page,
  context,
}) => {
  await page.goto('/');
  await page.getByLabel('Your name').fill('Synthetic Offline QA');
  await page.getByLabel('Email', { exact: true }).fill(`pwa-${crypto.randomUUID()}@example.test`);
  await page.getByLabel('Password').fill('local-pwa-Password-47');
  const agreements = page.getByRole('group', { name: 'Agreements required to continue' });
  await agreements.getByRole('checkbox').nth(0).check();
  await agreements.getByRole('checkbox').nth(1).check();
  await page.getByRole('button', { name: 'Create account', exact: true }).click();
  await page.getByRole('button', { name: 'Create a blank page', exact: true }).click();
  await page.getByLabel('Page title').fill('Offline recovery');
  await page.getByLabel('Note text', { exact: true }).fill('Visible note.');
  await expect(page.locator('.sync-status')).toHaveText('Saved');
  await page.evaluate(() => navigator.serviceWorker.ready);
  await context.setOffline(true);
  await page.getByLabel('Note text', { exact: true }).fill('This note survived an offline reload.');
  await expect(page.locator('.sync-status')).toHaveText('Saved on device');
  await page.reload();
  await page.getByRole('button', { name: /Offline recovery.*Personal notes/ }).click();
  await expect(page.getByLabel('Note text', { exact: true })).toHaveValue(
    'This note survived an offline reload.',
  );
  await context.setOffline(false);
  await expect(page.locator('.sync-status')).toHaveText('Saved');
  await page.getByRole('button', { name: 'Add a note', exact: true }).click();
  await page
    .getByLabel('Note text', { exact: true })
    .nth(1)
    .fill('DO NOT EXPORT THIS PRIVATE TEXT');
  await page.getByLabel('Note text', { exact: true }).nth(1).hover();
  await page.getByRole('button', { name: 'Exclude note from exports', exact: true }).last().click();
  await page.emulateMedia({ media: 'print' });
  await expect(page.locator('.print-document')).toBeVisible();
  await expect(page.locator('.print-document')).toContainText(
    'This note survived an offline reload.',
  );
  await expect(page.locator('.print-document')).not.toContainText('DO NOT EXPORT');
  await mkdir(path.join(tmpdir(), 'meeting-notebook-qa'), { recursive: true });
  await page.pdf({
    path: path.join(tmpdir(), 'meeting-notebook-qa', 'notebook-export.pdf'),
    format: 'A4',
    printBackground: true,
  });
});
