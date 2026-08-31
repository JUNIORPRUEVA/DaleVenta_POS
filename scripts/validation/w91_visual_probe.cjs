const { chromium } = require("playwright-core");

const chromePath = "C:/Program Files/Google/Chrome/Application/chrome.exe";
const appUrl = process.env.W91_APP_URL || "http://127.0.0.1:5000";
const probeUrl = process.env.W91_PROBE_URL || appUrl;
const outputDir =
  process.env.W91_OUTPUT_DIR ||
  "C:/Users/pc/DEV/PROYECTOS/PRODUCTOS/DaleVentas POS/docs/uom-visual-evidence";
const email = process.env.W91_EMAIL || "w9.visual@daleventa.local";
const password = process.env.W91_PASSWORD;
const suffix = process.env.W91_SUFFIX || "desktop";
const viewport = {
  width: Number(process.env.W91_WIDTH || 1366),
  height: Number(process.env.W91_HEIGHT || 768),
};

async function main() {
  if (!password) {
    throw new Error("W91_PASSWORD is required");
  }
  const browser = await chromium.launch({
    executablePath: chromePath,
    headless: true,
  });
  const page = await browser.newPage({ viewport });
  page.on("console", (message) => console.log(`[console:${message.type()}] ${message.text()}`));
  page.on("pageerror", (error) => console.log(`[pageerror] ${error.message}`));
  page.on("requestfailed", (request) =>
    console.log(`[requestfailed] ${request.url()} ${request.failure()?.errorText || ""}`),
  );
  await page.goto(probeUrl, { waitUntil: "networkidle", timeout: 60000 });
  await page.screenshot({ path: `${outputDir}/w91-login-${suffix}.png`, fullPage: true });
  if (!probeUrl.includes("login")) {
    if (viewport.width < 700) {
      await page.mouse.click(Math.min(viewport.width - 95, 250), 704);
    } else {
      await page.mouse.click(1000, 52);
    }
  }
  await page.waitForTimeout(2000);
  await page.screenshot({
    path: `${outputDir}/w91-login-form-${suffix}.png`,
    fullPage: true,
  });
  const centerX = Math.floor(viewport.width / 2);
  await page.mouse.click(viewport.width < 700 ? centerX : 650, viewport.width < 700 ? 355 : 288);
  await page.keyboard.type(email);
  await page.mouse.click(viewport.width < 700 ? centerX : 650, viewport.width < 700 ? 420 : 350);
  await page.keyboard.type(password);
  await page.mouse.click(viewport.width < 700 ? centerX : 684, viewport.width < 700 ? 535 : 466);
  await page.waitForTimeout(6000);
  await page.evaluate(() => {
    window.history.pushState({}, "", "/configuracion/almacenes");
    window.dispatchEvent(new PopStateEvent("popstate"));
  });
  await page.waitForTimeout(5000);
  await page.screenshot({
    path: `${outputDir}/w91-warehouses-${suffix}.png`,
    fullPage: true,
  });
  await page.mouse.click(viewport.width >= 700 ? viewport.width - 195 : viewport.width - 70, 92);
  await page.waitForTimeout(1000);
  await page.screenshot({
    path: `${outputDir}/w91-warehouse-form-${suffix}.png`,
    fullPage: true,
  });
  const text = await page.locator("body").innerText({ timeout: 10000 });
  console.log(text.slice(0, 2000));
  await browser.close();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
