const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const WebSocket = require('ws');

const root = path.resolve(__dirname, '..', '..');
const evidenceDir = path.join(root, 'docs', 'onboarding-phase2b-uat-evidence');
const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const webBase = process.env.PHASE2D_WEB_BASE || 'http://127.0.0.1:18083';
const apiBase = process.env.PHASE2D_API_BASE || 'http://127.0.0.1:4000';
const password = 'MiNegocio26';

class Cdp {
  constructor(wsUrl) {
    this.nextId = 1;
    this.pending = new Map();
    this.ws = new WebSocket(wsUrl);
    this.ws.on('message', (data) => {
      const message = JSON.parse(String(data));
      if (!message.id) return;
      const waiter = this.pending.get(message.id);
      if (!waiter) return;
      this.pending.delete(message.id);
      if (message.error) waiter.reject(new Error(message.error.message));
      else waiter.resolve(message.result);
    });
  }

  ready() {
    return new Promise((resolve, reject) => {
      this.ws.once('open', resolve);
      this.ws.once('error', reject);
    });
  }

  send(method, params = {}) {
    const id = this.nextId++;
    const payload = JSON.stringify({ id, method, params });
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(payload);
    });
  }

  close() {
    this.ws.close();
  }
}

async function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForJson(url, timeoutMs = 12000) {
  const start = Date.now();
  let lastError;
  while (Date.now() - start < timeoutMs) {
    try {
      const response = await fetch(url);
      if (response.ok) return response.json();
      lastError = new Error(`HTTP ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await delay(250);
  }
  throw lastError ?? new Error(`Timeout waiting for ${url}`);
}

async function connectTab(port, url) {
  const response = await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent(url)}`, {
    method: 'PUT',
  });
  const created = await response.json();
  const tab = created.webSocketDebuggerUrl
    ? created
    : (await waitForJson(`http://127.0.0.1:${port}/json/list`)).find((item) => item.id === created.id);
  if (!tab?.webSocketDebuggerUrl) throw new Error('No CDP page target found');
  const cdp = new Cdp(tab.webSocketDebuggerUrl);
  await cdp.ready();
  await cdp.send('Page.enable');
  await cdp.send('Runtime.enable');
  await cdp.send('DOM.enable');
  await cdp.send('Emulation.setFocusEmulationEnabled', { enabled: true });
  return cdp;
}

async function evalJs(cdp, expression, awaitPromise = true) {
  const result = await cdp.send('Runtime.evaluate', {
    expression,
    awaitPromise,
    returnByValue: true,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.text || 'Runtime.evaluate failed');
  }
  return result.result.value;
}

async function setViewport(cdp, width, height, mobile = true) {
  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width,
    height,
    deviceScaleFactor: 1,
    mobile,
    screenWidth: width,
    screenHeight: height,
  });
}

async function waitFor(cdp, predicateSource, timeoutMs = 20000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const ok = await evalJs(cdp, `Boolean((${predicateSource})())`);
    if (ok) return;
    await delay(300);
  }
  const text = await evalJs(cdp, `(() => {
    const labels = Array.from(document.querySelectorAll('*'))
      .map((el) => el.getAttribute('aria-label') || '')
      .filter(Boolean)
      .join('\\n');
    return ((document.body.innerText || '') + '\\n' + labels).slice(0, 1400);
  })()`);
  throw new Error(`Timed out waiting. Page text: ${text}`);
}

async function clickText(cdp, text) {
  const escaped = JSON.stringify(text);
  const clicked = await evalJs(
    cdp,
    `(() => {
      const textOf = (el) => el.getAttribute('aria-label') || el.innerText || el.textContent || '';
      const interactive = Array.from(document.querySelectorAll('button,[role="button"],flt-semantics'));
      const candidates = interactive
        .filter((el) => textOf(el).includes(${escaped}))
        .sort((a, b) => {
          const ar = a.getBoundingClientRect();
          const br = b.getBoundingClientRect();
          return (ar.width * ar.height) - (br.width * br.height);
        });
      const node = candidates[0];
      if (!node) return false;
      node.click();
      return true;
    })()`,
  );
  if (!clicked) throw new Error(`Could not click text: ${text}`);
}

async function dismissPwaBanner(cdp) {
  await evalJs(
    cdp,
    `(() => {
      const textOf = (el) => el.getAttribute('aria-label') || el.innerText || el.textContent || '';
      const candidates = Array.from(document.querySelectorAll('button,[role="button"],flt-semantics'))
        .filter((el) => textOf(el).includes('Ahora no'))
        .sort((a, b) => {
          const ar = a.getBoundingClientRect();
          const br = b.getBoundingClientRect();
          return (ar.width * ar.height) - (br.width * br.height);
        });
      if (!candidates[0]) return false;
      candidates[0].click();
      return true;
    })()`,
  ).catch(() => {});
}

async function capture(cdp, fileName, width, height, mobile = true) {
  await setViewport(cdp, width, height, mobile);
  await delay(700);
  const metrics = await evalJs(
    cdp,
    `(() => ({
      url: location.href,
      width: innerWidth,
      height: innerHeight,
      scrollWidth: document.documentElement.scrollWidth,
      scrollHeight: document.documentElement.scrollHeight,
      overflowX: document.documentElement.scrollWidth > innerWidth,
      text: (() => {
        const labels = Array.from(document.querySelectorAll('*')).map((el) => el.getAttribute('aria-label') || '').filter(Boolean).join('\\n');
        return ((document.body.innerText || '') + '\\n' + labels).slice(0, 1200);
      })()
    }))()`,
  );
  const screenshot = await cdp.send('Page.captureScreenshot', {
    format: 'png',
    captureBeyondViewport: false,
    fromSurface: true,
  });
  const target = path.join(evidenceDir, fileName);
  await fs.writeFile(target, Buffer.from(screenshot.data, 'base64'));
  return { file: target, ...metrics };
}

async function registerThroughPage(cdp) {
  const stamp = Date.now();
  const email = `uat.phase2d.visual.${stamp}@daleventa.local`;
  await setViewport(cdp, 390, 844, true);
  await cdp.send('Page.navigate', { url: `${webBase}/registro?phase2d=${stamp}` });
  await waitFor(cdp, "() => !!document.querySelector('#firstName')");
  await evalJs(
    cdp,
    `(() => {
      const data = {
        firstName: 'UAT Visual',
        commercialName: 'Phase2D Visual ${stamp}',
        phone: '8095550199',
        email: '${email}',
        password: '${password}'
      };
      for (const [id, value] of Object.entries(data)) {
        const el = document.getElementById(id);
        el.value = value;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }
      document.getElementById('terms').click();
      document.getElementById('submitButton').click();
    })()`,
  );
  await waitFor(cdp, "() => location.pathname === '/onboarding'", 30000);
  await delay(5000);
  await dismissPwaBanner(cdp);
  await delay(1200);
  await waitFor(
    cdp,
    `() => {
      const labels = Array.from(document.querySelectorAll('*')).map((el) => el.getAttribute('aria-label') || '').join('\\n');
      const text = (document.body.innerText || '') + '\\n' + labels;
      return text.includes('Enable accessibility') || text.includes('Tu cuenta');
    }`,
    20000,
  );
  await dismissPwaBanner(cdp);
  await evalJs(
    cdp,
    `(() => {
      const textOf = (el) => el.getAttribute('aria-label') || el.innerText || el.textContent || '';
      const enable = Array.from(document.querySelectorAll('button,[role="button"],flt-semantics'))
        .find((el) => textOf(el).includes('Enable accessibility'));
      if (enable) enable.click();
    })()`,
  ).catch(() => {});
  await delay(3000);
  await waitFor(cdp, `() => {
    const labels = Array.from(document.querySelectorAll('*')).map((el) => el.getAttribute('aria-label') || '').join('\\n');
    const text = (document.body.innerText || '') + '\\n' + labels;
    return text.includes('Tu cuenta está lista') || text.includes('Tu cuenta esta lista');
  }`);
  return email;
}

async function validateFocus(cdp) {
  await setViewport(cdp, 412, 915, true);
  const result = await evalJs(
    cdp,
    `(() => {
      const textOf = (el) => el.getAttribute('aria-label') || el.innerText || el.textContent || '';
      const targets = Array.from(document.querySelectorAll('input, textarea, [contenteditable="true"], flt-semantics, [role="textbox"]'))
        .filter((el) => textOf(el).match(/Producto|Precio|Teléfono|Direccion|Dirección|Nombre/))
        .sort((a, b) => {
          const ar = a.getBoundingClientRect();
          const br = b.getBoundingClientRect();
          return (ar.width * ar.height) - (br.width * br.height);
        });
      const target = targets[0];
      if (!target) return { found: false };
      target.click();
      target.scrollIntoView({ block: 'center' });
      if (target.focus) target.focus();
      const rect = target.getBoundingClientRect();
      return {
        found: true,
        label: textOf(target).slice(0, 80),
        activeTag: document.activeElement ? document.activeElement.tagName : null,
        top: rect.top,
        bottom: rect.bottom,
        viewport: innerHeight,
        visible: rect.top >= 0 && rect.bottom <= innerHeight
      };
    })()`,
  );
  return result;
}

async function main() {
  await fs.mkdir(evidenceDir, { recursive: true });
  const port = 9300 + Math.floor(Math.random() * 500);
  const profile = await fs.mkdtemp(path.join(os.tmpdir(), 'fullpos-phase2d-'));
  const chrome = spawn(chromePath, [
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--window-size=390,844',
    'about:blank',
  ], { stdio: 'ignore' });

  let cdp;
  try {
    await waitForJson(`http://127.0.0.1:${port}/json/version`);
    cdp = await connectTab(port, `${webBase}/registro`);
    const email = await registerThroughPage(cdp);
    const captures = [];

    captures.push(await capture(cdp, 'welcome-320x568.png', 320, 568));
    await clickText(cdp, 'Comenzar configuración');
    await waitFor(cdp, "() => Array.from(document.querySelectorAll('*')).some((el) => ((el.getAttribute('aria-label') || el.innerText || '')).includes('Datos de tu negocio'))");
    captures.push(await capture(cdp, 'company-360x800.png', 360, 800));
    await clickText(cdp, 'Guardar y continuar');
    await waitFor(cdp, "() => Array.from(document.querySelectorAll('*')).some((el) => ((el.getAttribute('aria-label') || el.innerText || '')).includes('Facturación'))");
    captures.push(await capture(cdp, 'billing-390x844.png', 390, 844));
    await clickText(cdp, 'Guardar y continuar');
    await waitFor(cdp, "() => Array.from(document.querySelectorAll('*')).some((el) => ((el.getAttribute('aria-label') || el.innerText || '')).includes('Tu primer producto'))");
    captures.push(await capture(cdp, 'product-412x915.png', 412, 915));
    const focus = await validateFocus(cdp);
    await clickText(cdp, 'Guardar y continuar');
    await waitFor(cdp, "() => Array.from(document.querySelectorAll('*')).some((el) => ((el.getAttribute('aria-label') || el.innerText || '')).includes('Listo para vender'))");
    captures.push(await capture(cdp, 'ready-430x932.png', 430, 932));
    captures.push(await capture(cdp, 'tablet-768x1024.png', 768, 1024, true));
    await clickText(cdp, 'Ir al sistema');
    await waitFor(cdp, "() => Array.from(document.querySelectorAll('*')).some((el) => ((el.getAttribute('aria-label') || el.innerText || '')).includes('Primera vez usando FullPOS'))");
    await clickText(cdp, 'Ver recorrido');
    await waitFor(cdp, "() => Array.from(document.querySelectorAll('*')).some((el) => ((el.getAttribute('aria-label') || el.innerText || '')).includes('1/3 - Navegación'))");
    captures.push(await capture(cdp, 'tutorial-390x844.png', 390, 844));

    await setViewport(cdp, 844, 390, true);
    await delay(700);
    const landscape = await evalJs(cdp, `(() => ({
      text: (document.body.innerText || document.body.textContent || '').slice(0, 800),
      overflowX: document.documentElement.scrollWidth > innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      innerWidth,
      innerHeight
    }))()`);

    const resize = [];
    for (const [width, height, mobile] of [[1366, 768, false], [1920, 1080, false], [390, 844, true], [768, 1024, true], [1366, 768, false]]) {
      resize.push(await capture(cdp, `resize-${width}x${height}.png`, width, height, mobile));
    }

    console.log(JSON.stringify({ email, captures, focus, landscape, resize }, null, 2));
  } finally {
    if (cdp) cdp.close();
    chrome.kill();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
