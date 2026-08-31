const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("playwright-core");

const chromePath = "C:/Program Files/Google/Chrome/Application/chrome.exe";
const appUrl = process.env.W10_APP_URL || "http://127.0.0.1:5000";
const apiUrl = process.env.W10_API_URL || "http://127.0.0.1:4000";
const outputDir =
  process.env.W10_OUTPUT_DIR ||
  "C:/Users/pc/DEV/PROYECTOS/PRODUCTOS/DaleVentas POS/docs/uom-visual-evidence";
const email = process.env.W10_EMAIL || "w10.visual@daleventa.local";
const password = process.env.W10_PASSWORD;
const suffix = process.env.W10_SUFFIX || "desktop";
const viewport = {
  width: Number(process.env.W10_WIDTH || 1366),
  height: Number(process.env.W10_HEIGHT || 768),
};

async function api(pathname, options = {}) {
  const response = await fetch(`${apiUrl}${pathname}`, {
    ...options,
    headers: {
      "content-type": "application/json",
      ...(options.headers || {}),
    },
  });
  if (!response.ok) {
    throw new Error(`${pathname} failed: ${response.status} ${await response.text()}`);
  }
  return response.json();
}

async function createApiTransfer() {
  const login = await api("/auth/login", {
    method: "POST",
    body: JSON.stringify({ email, password }),
  });
  const auth = { authorization: `Bearer ${login.accessToken}` };
  const warehouses = await api("/warehouses", { headers: auth });
  const products = await api("/products", { headers: auth });
  const source = warehouses.find((warehouse) => warehouse.code === "PRI") || warehouses[0];
  const destination =
    warehouses.find((warehouse) => warehouse.id !== source.id) || warehouses[1];
  const product =
    products.find((item) => item.nombre === "Tela Azul W10 Visual") || products[0];
  const transfer = await api("/warehouses/transfers", {
    method: "POST",
    headers: auth,
    body: JSON.stringify({
      sourceWarehouseId: source.id,
      destinationWarehouseId: destination.id,
      clientRequestId: `w10-visual-${suffix}-${Date.now()}`,
      notes: `W10 visual ${suffix}`,
      items: [{ productId: product.id, quantity: "0.5" }],
    }),
  });
  return { source, destination, product, transfer };
}

async function openWarehousesScreen(page, authPayload, writeAuthStorage) {
  await page.goto(appUrl, { waitUntil: "networkidle", timeout: 60000 });
  await page.waitForTimeout(1500);
  await page.evaluate(writeAuthStorage, authPayload);
  await page.reload({ waitUntil: "networkidle", timeout: 60000 });
  await page.waitForTimeout(5000);

  if (viewport.width < 700) {
    await page.mouse.click(24, 24);
    await page.waitForTimeout(1000);
    await page.mouse.click(232, 759);
    await page.waitForTimeout(2500);
    await page.mouse.click(165, 205);
    await page.waitForTimeout(5000);
    return;
  }

  await page.goto(`${appUrl}/configuracion/almacenes`, {
    waitUntil: "networkidle",
    timeout: 60000,
  });
  await page.waitForTimeout(5000);
}

async function main() {
  if (!password) throw new Error("W10_PASSWORD is required");
  fs.mkdirSync(outputDir, { recursive: true });

  const browser = await chromium.launch({
    executablePath: chromePath,
    headless: true,
  });
  const page = await browser.newPage({ viewport });
  const login = await api("/auth/login", {
    method: "POST",
    body: JSON.stringify({ email, password }),
  });
  const me = await api("/auth/me", {
    headers: { authorization: `Bearer ${login.accessToken}` },
  });
  const authPayload = {
    accessToken: login.accessToken,
    refreshToken: login.refreshToken,
    user: me,
  };
  const writeAuthStorage = ({ accessToken, refreshToken, user }) => {
    localStorage.setItem("flutter.accessToken", JSON.stringify(accessToken));
    localStorage.setItem("flutter.refreshToken", JSON.stringify(refreshToken || ""));
    localStorage.setItem("flutter.authUserSnapshot", JSON.stringify(JSON.stringify(user)));
  };
  await page.addInitScript(writeAuthStorage, authPayload);
  page.on("console", (message) =>
    console.log(`[console:${message.type()}] ${message.text()}`),
  );
  page.on("pageerror", (error) => console.log(`[pageerror] ${error.message}`));
  page.on("requestfailed", (request) =>
    console.log(`[requestfailed] ${request.url()} ${request.failure()?.errorText || ""}`),
  );

  await openWarehousesScreen(page, authPayload, writeAuthStorage);
  if (viewport.width < 700) {
    await page.mouse.wheel(0, 620);
    await page.waitForTimeout(1000);
  }
  await page.screenshot({
    path: path.join(outputDir, `w10-transfer-form-${suffix}.png`),
    fullPage: true,
  });
  if (viewport.width < 700) {
    await page.mouse.click(195, 475);
    await page.waitForTimeout(1200);
    await page.screenshot({
      path: path.join(outputDir, `w10-transfer-product-menu-${suffix}.png`),
      fullPage: true,
    });
    await page.mouse.click(135, 480);
    await page.waitForTimeout(1000);
    await page.mouse.click(120, 562);
    await page.keyboard.type("0.5");
    await page.waitForTimeout(800);
    await page.screenshot({
      path: path.join(outputDir, `w10-transfer-selected-${suffix}.png`),
      fullPage: true,
    });
  }

  const apiResult = await createApiTransfer();
  await openWarehousesScreen(page, authPayload, writeAuthStorage);
  if (viewport.width < 700) {
    await page.mouse.wheel(0, 620);
    await page.waitForTimeout(1000);
  }
  await page.screenshot({
    path: path.join(outputDir, `w10-transfer-history-${suffix}.png`),
    fullPage: true,
  });

  console.log(
    JSON.stringify({
      suffix,
      appUrl,
      apiUrl,
      source: apiResult.source.code,
      destination: apiResult.destination.code,
      product: apiResult.product.nombre,
      transferId: apiResult.transfer.id,
      quantity: apiResult.transfer.items[0]?.quantityDecimal,
    }),
  );
  await browser.close();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
