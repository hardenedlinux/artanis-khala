import { execFileSync } from "node:child_process";
import { expect, test } from "@playwright/test";

const privateRoot = "/home/alexon/Project/khala-private";
const runRoot = process.env.KHALA_RUN_DIR ?? "/tmp/khala-run7";

test.beforeAll(() => {
  execFileSync(`${privateRoot}/tests/browser/e2e-start.sh`, [], {
    env: { ...process.env, KHALA_SRC: "/home/alexon/Project/khala", KHALA_RUN_DIR: runRoot },
  });
});

test.afterAll(() => {
  execFileSync(`${privateRoot}/tests/browser/e2e-stop.sh`, [], {
    env: { ...process.env, KHALA_RUN_DIR: runRoot },
  });
});

test("generate, install, cancel, and switch language", async ({ page }) => {
  await page.goto("./");
  await page.getByPlaceholder("Describe the image you want to create").fill("e2e lake");
  await page.getByRole("button", { name: "Enhance prompt" }).click();
  await expect(page.getByLabel("Enhanced prompt")).toContainText("Detailed image");
  await page.getByRole("button", { name: "Generate" }).click();
  await expect(page.getByText(/Generating:/)).toBeVisible();
  await expect(page.getByRole("img", { name: "Result" })).toBeVisible({ timeout: 20_000 });

  await page.getByRole("link", { name: "Models" }).click();
  await page.getByRole("button", { name: "Install" }).first().click();
  await expect(page.getByText("downloading")).toBeVisible();
  await expect(page.getByText("Installed")).toBeVisible({ timeout: 20_000 });
  await page.getByRole("button", { name: "Install" }).first().click();
  await expect(page.getByText("downloading")).toBeVisible();
  await page.getByRole("button", { name: "Cancel download" }).click();
  await expect(page.getByText("cancelled")).toBeVisible({ timeout: 20_000 });

  await page.getByRole("link", { name: "Settings" }).click();
  await page.getByText("Language").click();
  await page.getByRole("option", { name: "ja" }).click();
  await expect(page.getByText("設定")).toBeVisible();
});
