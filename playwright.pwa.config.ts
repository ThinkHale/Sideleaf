import { defineConfig } from '@playwright/test';
import { tmpdir } from 'node:os';
import path from 'node:path';
export default defineConfig({
  testDir: './tests/pwa',
  timeout: 40000,
  expect: { timeout: 10000 },
  workers: 1,
  reporter: 'list',
  use: {
    baseURL: 'http://127.0.0.1:4173',
    browserName: 'chromium',
    viewport: { width: 1180, height: 820 },
  },
  webServer: {
    command: 'npm run preview',
    url: 'http://127.0.0.1:4173/api/health',
    timeout: 90000,
    env: {
      PORT: '4173',
      APP_ORIGIN: 'http://127.0.0.1:4173',
      APP_DATA_DIR: path.join(tmpdir(), 'meeting-notebook-pwa-test'),
    },
  },
});
