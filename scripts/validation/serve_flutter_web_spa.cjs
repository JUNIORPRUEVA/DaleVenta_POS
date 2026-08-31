const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

const root = path.resolve(process.env.FLUTTER_WEB_ROOT || "apps/fulltech_app/build/web");
const host = process.env.FLUTTER_WEB_HOST || "127.0.0.1";
const port = Number(process.env.FLUTTER_WEB_PORT || 5004);

const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".wasm": "application/wasm",
};

function resolveAsset(urlPath) {
  const clean = decodeURIComponent(urlPath.split("?")[0]).replace(/^\/+/, "");
  if (!clean) return path.join(root, "index.html");

  let candidate = path.join(root, clean);
  if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) return candidate;

  let relative = clean;
  while (relative.includes("/")) {
    relative = relative.replace(/^[^/]+\//, "");
    candidate = path.join(root, relative);
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) return candidate;
  }

  return path.join(root, "index.html");
}

http
  .createServer((request, response) => {
    const file = resolveAsset(request.url || "/");
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("Content-Type", types[path.extname(file)] || "application/octet-stream");
    fs.createReadStream(file).pipe(response);
  })
  .listen(port, host, () => {
    console.log(`Serving Flutter web from ${root} at http://${host}:${port}`);
  });
