const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("playwright");

const appUrl = process.env.W14_APP_URL || "http://127.0.0.1:53214";
const email = process.env.W14_EMAIL || "w14.multi@daleventas.test";
const password = process.env.W14_PASSWORD;
const outDir = path.resolve(process.cwd(), "docs/w14-visual-evidence");

if (!password) {
  throw new Error("W14_PASSWORD is required");
}

const routes = [
  ["pos", "/ventas/nueva"],
  ["warehouse-management", "/configuracion/almacenes"],
  ["product-stock-by-warehouse", "/catalogo/stock"],
  ["stock-adjustment", "/catalogo/conteo"],
  ["terminal", "/configuracion/almacenes"],
  ["transfer", "/configuracion/almacenes"],
  ["kardex-movements", "/catalogo/kardex"],
  ["kardex-stock", "/catalogo/kardex"],
  ["kardex-reconciliation", "/catalogo/kardex"],
  ["permissions-admin-pin", "/users"],
  ["offline-conflict", "/ventas/nueva"],
  ["single-warehouse-ux", "/catalogo/stock", "w14.single@daleventas.test"],
  ["zero-config-company-ux", "/catalogo/stock", "w14.zero@daleventas.test"],
  ["second-warehouse-ux", "/configuracion/almacenes"],
];

async function login(page, userEmail) {
  await page.goto(`${appUrl}/login`, { waitUntil: "domcontentloaded" });
  await page.waitForLoadState("networkidle", { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(2500);
  const viewport = page.viewportSize() || { width: 1366, height: 768 };
  const centerX = Math.floor(viewport.width / 2);
  await page.mouse.click(centerX, Math.floor(viewport.height * 0.38));
  await page.keyboard.type(userEmail);
  await page.mouse.click(centerX, Math.floor(viewport.height * 0.455));
  await page.keyboard.type(password);
  await page.mouse.click(centerX, Math.floor(viewport.height * 0.61));
  await page.waitForURL((url) => !url.pathname.includes("/login"), {
    timeout: 30000,
  }).catch(() => {});
  await page.waitForLoadState("networkidle", { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(5000);
}

async function captureRoute(browser, viewportName, viewport, name, route, userEmail) {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  page.on("console", (msg) => {
    if (msg.type() === "error") {
      console.log(`[browser:${viewportName}:${name}] ${msg.text()}`);
    }
  });
  await login(page, userEmail || email);
  await page.evaluate((nextRoute) => {
    history.pushState({}, "", nextRoute);
    window.dispatchEvent(new PopStateEvent("popstate"));
  }, route);
  await page.waitForLoadState("networkidle", { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(1500);
  await page.evaluate((nextRoute) => {
    history.pushState({}, "", nextRoute);
    window.dispatchEvent(new PopStateEvent("popstate"));
  }, route);
  await page.waitForTimeout(2500);
  if (name === "kardex-stock") {
    await page.mouse.click(Math.floor(viewport.width * 0.18), Math.floor(viewport.height * 0.105));
    await page.waitForTimeout(1200);
  }
  if (name === "kardex-reconciliation") {
    await page.mouse.click(Math.floor(viewport.width * 0.30), Math.floor(viewport.height * 0.105));
    await page.waitForTimeout(1200);
  }
  await page.screenshot({
    path: path.join(outDir, `${name}-${viewportName}.png`),
    fullPage: false,
  });
  const title = await page.title().catch(() => "");
  const bodyText = await page.locator("body").innerText({ timeout: 5000 }).catch(() => "");
  await context.close();
  return {
    name,
    viewport: viewportName,
    route,
    url: `${appUrl}${route}`,
    title,
    textSample: bodyText.slice(0, 500).replace(/\s+/g, " ").trim(),
  };
}

async function main() {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  const results = [];
  for (const [viewportName, viewport] of [
    ["desktop-1366x768", { width: 1366, height: 768 }],
    ["mobile-390x844", { width: 390, height: 844 }],
  ]) {
    for (const [name, route, userEmail] of routes) {
      results.push(await captureRoute(browser, viewportName, viewport, name, route, userEmail));
    }
  }
  await browser.close();
  fs.writeFileSync(
    path.join(outDir, "w14-visual-capture-manifest.json"),
    JSON.stringify({ capturedAt: new Date().toISOString(), appUrl, results }, null, 2),
  );
  console.log(JSON.stringify({ ok: true, count: results.length, outDir }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
