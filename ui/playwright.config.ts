import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  timeout: 60_000,
  use: {
    baseURL: `http://127.0.0.1:${process.env.KHALA_TEST_PORT ?? "3130"}/khala/`,
    headless: true,
  },
  webServer: undefined,
});
