import { defineConfig, devices } from '@playwright/test';

// 生产门禁默认打公网；本地可用 COCO_SMOKE_BASE_URL 覆盖
const baseURL = process.env.COCO_SMOKE_BASE_URL ?? 'https://coco.xyfit.top';

export default defineConfig({
  testDir: '.',
  timeout: 90_000,
  expect: { timeout: 30_000 },
  fullyParallel: false,
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL,
    ...devices['Desktop Chrome'],
    headless: true,
    trace: 'off',
  },
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }],
});
