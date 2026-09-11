import { defineConfig, devices } from "@playwright/test";
const fixture = process.env.GAME_TEST_FIXTURE === "1";
export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: !fixture,
  // The CI fixture is one shared game world; economic tests must not race it.
  workers: fixture ? 1 : undefined,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: "list",
  use: { baseURL: "http://localhost:3000", trace: "retain-on-failure" },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: [
    ...(fixture ? [{command:"node tests/fixtures/supabase.mjs",url:"http://127.0.0.1:54329/health",reuseExistingServer:false}] : []),
    { command: "npm run start", url: "http://localhost:3000", reuseExistingServer: !process.env.CI, timeout: 120000 },
  ],
});
