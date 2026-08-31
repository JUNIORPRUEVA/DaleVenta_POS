const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("playwright-core");

const chromePath = "C:/Program Files/Google/Chrome/Application/chrome.exe";
const appUrl = process.env.W11_APP_URL || "http://127.0.0.1:5005";
const apiUrl = process.env.W11_API_URL || "http://127.0.0.1:4000";
const outputDir =
  process.env.W11_OUTPUT_DIR ||
  "C:/Users/pc/DEV/PROYECTOS/PRODUCTOS/DaleVentas POS/docs/uom-visual-evidence";
const email = process.env.W11_EMAIL || "w11.kardex@daleventa.local";
const password = process.env.W11_PASSWORD;
const suffix = process.env.W11_SUFFIX || "desktop";
const viewport = {
  width: Number(process.env.W11_WIDTH || 1366),
  height: Number(process.env.W11_HEIGHT || 768),
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

async function authenticate(page) {
  const login = await api("/auth/login", {
    method: "POST",
    body: JSON.stringify({ email, password }),
  });
  const me = await api("/auth/me", {
    headers: { authorization: `Bearer ${login.accessToken}` },
  });
  const authPayload = {
    accessToken: login.accessToken,
    refreshToken: login.refreshToken || "",
    user: me,
  };
  const writeAuthStorage = ({ accessToken, refreshToken, user }) => {
    const encodedUser = JSON.stringify(user);
    localStorage.setItem("flutter.accessToken", JSON.stringify(accessToken));
    localStorage.setItem("flutter.refreshToken", JSON.stringify(refreshToken));
    localStorage.setItem("flutter.authUserSnapshot", JSON.stringify(encodedUser));
    localStorage.setItem("flutter.authUser", JSON.stringify(encodedUser));
    localStorage.setItem("accessToken", accessToken);
    localStorage.setItem("refreshToken", refreshToken);
    localStorage.setItem("authUserSnapshot", encodedUser);
  };
  await page.addInitScript(writeAuthStorage, authPayload);
  await page.goto(appUrl, { waitUntil: "networkidle", timeout: 60000 });
  await page.evaluate(writeAuthStorage, authPayload);
  await page.reload({ waitUntil: "networkidle", timeout: 60000 });
  await page.waitForTimeout(3000);
  return authPayload;
}

async function openKardex(page) {
  const navKardex = page.getByText("Kardex", { exact: true }).first();
  if (await navKardex.isVisible().catch(() => false)) {
    await navKardex.click();
    await page.waitForTimeout(5000);
  }
  if (!(await page.getByText("Movimientos").first().isVisible().catch(() => false))) {
    await page.goto(`${appUrl}/catalogo/kardex`, {
      waitUntil: "networkidle",
      timeout: 60000,
    });
    await page.waitForTimeout(5000);
  }
  if (!(await page.getByText("Movimientos").first().isVisible().catch(() => false))) {
    await page.evaluate(() => {
      window.history.pushState({}, "", "/catalogo/kardex");
      window.dispatchEvent(new PopStateEvent("popstate"));
    });
    await page.waitForTimeout(5000);
  }
  await page.waitForTimeout(2500);
}

async function screenshot(page, name) {
  await page.screenshot({
    path: path.join(outputDir, `w11-${name}-${suffix}.png`),
    fullPage: true,
  });
}

async function main() {
  if (!password) throw new Error("W11_PASSWORD is required");
  fs.mkdirSync(outputDir, { recursive: true });

  const browser = await chromium.launch({ executablePath: chromePath, headless: true });
  try {
    const page = await browser.newPage({ viewport });
    page.on("console", (message) => console.log(`[console:${message.type()}] ${message.text()}`));
    page.on("pageerror", (error) => console.log(`[pageerror] ${error.message}`));
    page.on("requestfailed", (request) =>
      console.log(`[requestfailed] ${request.url()} ${request.failure()?.errorText || ""}`),
    );

    const authPayload = await authenticate(page);
    await openKardex(page);
    await screenshot(page, "kardex");

    if (viewport.width < 700) {
      await page.mouse.click(276, 28);
      await page.waitForTimeout(1000);
      await screenshot(page, "filters");
      await page.keyboard.press("Escape");
      await page.waitForTimeout(600);
      await page.mouse.click(Math.floor(viewport.width / 2), 405);
      await page.waitForTimeout(1000);
      await screenshot(page, "movement-detail");
      await page.keyboard.press("Escape");
      await page.waitForTimeout(600);
    }

    await page.mouse.click(viewport.width < 700 ? 250 : 250, 80);
    await page.waitForTimeout(viewport.width < 700 ? 6000 : 2500);
    await screenshot(page, "stock-report");

    await page.mouse.click(viewport.width < 700 ? 365 : 405, 80);
    await page.waitForTimeout(2500);
    await screenshot(page, "reconciliation");

    const auth = { authorization: `Bearer ${authPayload.accessToken}` };
    const movements = await api("/inventory/movements?take=50", { headers: auth });
    const stock = await api("/inventory/stock-report", { headers: auth });
    const reconciliation = await api("/inventory/reconciliation", { headers: auth });
    const movementText = JSON.stringify(movements);
    const stockText = JSON.stringify(stock);
    const checks = {
      hasMovements: movements.total === 7,
      hasTransferPair:
        movements.items.filter((item) => item.reference?.sourceType === "WAREHOUSE_TRANSFER")
          .length === 2,
      hasSyntheticProduct: movementText.includes("Tela Azul W11 Kardex"),
      hasInactiveWarehouse: stockText.includes("Almacen Inactivo W11"),
      hasDecimalYard:
        movementText.includes("20.875") &&
        movementText.includes("15.375") &&
        movementText.includes("5.5"),
      noMisleadingUnitTotal: !stockText.includes("17.875 unidades"),
      reconciliationReadOnly: reconciliation.readOnly === true && reconciliation.driftCount === 0,
    };
    if (Object.values(checks).some((value) => !value)) {
      throw new Error(`W11 visual checks failed: ${JSON.stringify(checks)}`);
    }

    console.log(JSON.stringify({ suffix, appUrl, apiUrl, screenshots: outputDir, checks }, null, 2));
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
