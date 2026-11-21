import path from "node:path";
import { fileURLToPath } from "node:url";
import playwright from "../../ui/node_modules/playwright/index.js";

const { chromium, request } = playwright;
const here = path.dirname(fileURLToPath(import.meta.url));
const port = process.argv[2] || process.env.KHALA_STUDIO_TEST_PORT;
const baseURL = process.env.KHALA_STUDIO_BROWSER_URL || `http://127.0.0.1:${port}`;
const characterName = `Sera Browser ${Date.now()}`;
const concept = "一个生活在蒸汽朋克世界的年轻机械师，性格独立，不喜欢依赖别人。";

function check(name, condition) {
  if (!condition) throw new Error(`Character Studio browser test failed: ${name}`);
  console.log(`ok ${name}`);
}

async function main() {
  if (!port) throw new Error("KHALA_STUDIO_TEST_PORT or an explicit port is required");

  const api = await request.newContext();
  const workplaceResponse = await api.post(`${baseURL}/studio/api/v1/workplaces`, {
    data: {
      title: `Character Studio Browser ${Date.now()}`,
      description: "Fake-service Character Studio browser smoke test",
      cover_color: "#713D3B",
    },
  });
  const workplaceBody = await workplaceResponse.text();
  if (!workplaceResponse.ok()) {
    throw new Error(`fixture Workplace failed: HTTP ${workplaceResponse.status()} ${workplaceBody}`);
  }
  const workplace = JSON.parse(workplaceBody).data;
  check("browser-fixture-workplace-created", !!workplace?.id);

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  const pageErrors = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));

  try {
    await page.goto(`${baseURL}/studio`, { waitUntil: "networkidle" });
    await page.locator(".book-card", { hasText: workplace.title }).click();
    await page.getByRole("navigation", { name: "Workplace sections" }).waitFor();
    await page.getByRole("button", { name: /^角色\s*CHARACTERS$/ }).click();
    await page.getByRole("heading", { name: "角色工作室" }).waitFor();

    await page.getByRole("button", { name: /新建角色/ }).click();
    await page.getByLabel("人物概念").fill(concept);
    await page.getByLabel("角色名（可选）").fill(characterName);
    await page.getByRole("button", { name: "建立角色并补全" }).click();

    await page.getByRole("heading", { name: characterName }).first().waitFor();
    await page.getByText("AI PROPOSAL · NOT CANON").waitFor();
    await page.getByText("Raised among repair yards", { exact: false }).waitFor();
    check("browser-ai-drafts-visible", true);

    await page.getByRole("button", { name: "应用为正式 文学身份" }).click();
    await page.getByText("文学身份已确认进入 Canon").waitFor();
    check("browser-draft-applied", true);

    await page.getByRole("button", { name: /^服装\s*OUTFITS$/ }).click();
    await page.getByRole("button", { name: /建立服装/ }).click();
    const outfitEditor = page.locator(".outfit-editor");
    await outfitEditor.getByLabel("名称").fill("Workshop Standard");
    await outfitEditor.getByLabel("服装组成").fill("long coat, reinforced trousers");
    await outfitEditor.getByLabel("材料").fill("leather, brass, wool");
    await outfitEditor.getByLabel("颜色").fill("charcoal, brass, oxblood");
    await outfitEditor.getByRole("button", { name: "保存服装" }).click();
    await page.getByText("Workshop Standard").first().waitFor();
    check("browser-outfit-created", true);

    await page.getByRole("button", { name: /^视觉作品\s*ARTWORK$/ }).click();
    await page.getByLabel("额外创作说明").fill("standing beside the workshop window, restrained expression");
    await page.getByRole("button", { name: "组合并生成" }).click();
    await page.locator(".artwork-stage img").waitFor({ timeout: 30_000 });
    check("browser-artwork-generated", true);

    await page.getByRole("button", { name: "设为正式 Avatar" }).click();
    await page.getByText("已确认为正式 Avatar").waitFor();
    check("browser-avatar-approved", true);

    await page.getByRole("button", { name: "设为正式全身立绘" }).click();
    await page.getByText("已确认为正式全身立绘").waitFor();
    check("browser-full-body-approved", true);

    await page.getByRole("button", { name: /^正式设定\s*CANON$/ }).click();
    await page.getByText("作者已确认这张图片为正式头像。").waitFor();
    await page.getByText("全身立绘也已确认", { exact: false }).waitFor();
    await page.getByRole("heading", { name: "Workshop Standard" }).waitFor();
    check("browser-canon-visible", true);

    await page.reload({ waitUntil: "networkidle" });
    await page.locator(".book-card", { hasText: workplace.title }).click();
    await page.getByRole("navigation", { name: "Workplace sections" }).waitFor();
    await page.getByRole("button", { name: /^角色\s*CHARACTERS$/ }).click();
    await page.getByRole("button", { name: new RegExp(characterName) }).waitFor();
    await page.getByRole("button", { name: new RegExp(characterName) }).click();
    await page.getByRole("heading", { name: characterName }).first().waitFor();
    await page.getByRole("button", { name: /^服装\s*OUTFITS$/ }).click();
    await page.getByText("Workshop Standard").first().waitFor();
    await page.getByRole("button", { name: /^视觉作品\s*ARTWORK$/ }).click();
    await page.locator(".artwork-stage img").waitFor({ timeout: 30_000 });
    check("browser-reload-persistence", true);

    check("browser-no-page-errors", pageErrors.length === 0);
  } finally {
    await browser.close();
    await api.dispose();
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
