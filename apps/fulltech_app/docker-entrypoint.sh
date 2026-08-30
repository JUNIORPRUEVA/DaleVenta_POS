#!/bin/sh
set -eu

WEB_ROOT="/usr/share/nginx/html"
ENV_FILE="$WEB_ROOT/assets/.env"
EXAMPLE_FILE="$WEB_ROOT/assets/.env.example"
NGINX_CONF="/etc/nginx/conf.d/default.conf"

js_escape() {
  # Escape backslashes and double quotes for safe JS string literals.
  printf '%s' "$1" | sed 's/\\\\/\\\\\\\\/g; s/"/\\"/g'
}

# Ensure the env file exists (so flutter_dotenv can load it as an asset).
if [ ! -f "$ENV_FILE" ] && [ -f "$EXAMPLE_FILE" ]; then
  cp "$EXAMPLE_FILE" "$ENV_FILE"
fi

# If EasyPanel provides runtime env vars, write them into the asset env file.
# This avoids rebuilding the image just to change API endpoints.
if [ "${API_BASE_URL:-}" != "" ] || [ "${API_TIMEOUT_MS:-}" != "" ]; then
  {
    echo "# Generated at container start"
    if [ "${API_BASE_URL:-}" != "" ]; then
      echo "API_BASE_URL=${API_BASE_URL}"
    fi
    if [ "${API_TIMEOUT_MS:-}" != "" ]; then
      echo "API_TIMEOUT_MS=${API_TIMEOUT_MS}"
    fi
  } > "$ENV_FILE"
fi

# Generate runtime config for Flutter Web (NOT part of flutter_service_worker RESOURCES).
# This avoids stale config caused by PWA caching of assets.
API_BASE_URL_ESC="$(js_escape "${API_BASE_URL:-}")"
API_TIMEOUT_MS_ESC="$(js_escape "${API_TIMEOUT_MS:-}")"
SUPPORT_EMAIL_ESC="$(js_escape "${SUPPORT_EMAIL:-ventas@fulltechrd.com}")"
SUPPORT_PHONE_ESC="$(js_escape "${SUPPORT_PHONE:-829-531-9442}")"
SUPPORT_WHATSAPP_ESC="$(js_escape "${SUPPORT_WHATSAPP:-18295319442}")"
SUPPORT_HOURS_ESC="$(js_escape "${SUPPORT_HOURS:-Lunes a viernes de 9:00 a.m. a 6:00 p.m. AST}")"
cat > "$WEB_ROOT/env.js" <<EOF
// Generated at container start
window.__ENV = window.__ENV || {};
// Primary (string) values for current builds
window.API_BASE_URL = "${API_BASE_URL_ESC}";
window.API_TIMEOUT_MS = "${API_TIMEOUT_MS_ESC}";

// Backwards compatibility for older cached builds that expect functions:
//   __ENV.API_BASE_URL() / __ENV.API_TIMEOUT_MS()
// Also keep value mirrors for any code that reads __ENV.* as strings.
window.__ENV.API_BASE_URL_VALUE = window.API_BASE_URL;
window.__ENV.API_TIMEOUT_MS_VALUE = window.API_TIMEOUT_MS;
window.__ENV.API_BASE_URL = function () { return window.__ENV.API_BASE_URL_VALUE; };
window.__ENV.API_TIMEOUT_MS = function () { return window.__ENV.API_TIMEOUT_MS_VALUE; };

// Convenience aliases (string)
window.__ENV.API_BASE_URL_STR = window.API_BASE_URL;
window.__ENV.API_TIMEOUT_MS_STR = window.API_TIMEOUT_MS;
EOF

cat > "$WEB_ROOT/public-config.js" <<EOF
// Generated at container start
window.FULLPOS_PUBLIC_CONFIG = {
  supportEmail: "${SUPPORT_EMAIL_ESC}",
  supportPhone: "${SUPPORT_PHONE_ESC}",
  supportWhatsapp: "${SUPPORT_WHATSAPP_ESC}",
  supportHours: "${SUPPORT_HOURS_ESC}"
};
EOF

# Optional: same-origin reverse proxy to avoid CORS/XHR issues in browsers.
# Configure:
# - API_BASE_URL=/api
# - API_UPSTREAM_URL=https://your-api.example.com
if [ "${API_UPSTREAM_URL:-}" != "" ]; then
  escape_sed_repl() {
    # Escape '&' and delimiter '@' for safe sed replacement.
    printf '%s' "$1" | sed 's/[&@]/\\&/g'
  }

  UPSTREAM="${API_UPSTREAM_URL%/}"
  UPSTREAM_HOST="$(printf '%s' "$UPSTREAM" | sed -E 's|^https?://([^/]+).*|\1|')"
  UPSTREAM_ESC="$(escape_sed_repl "$UPSTREAM")"
  UPSTREAM_HOST_ESC="$(escape_sed_repl "$UPSTREAM_HOST")"

  cat > "$NGINX_CONF" <<'EOF'
server {
  listen 80;
  server_name _;
  client_max_body_size 64m;

  add_header Strict-Transport-Security "max-age=31536000" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;

  gzip on;
  gzip_comp_level 6;
  gzip_min_length 1024;
  gzip_vary on;
  gzip_types
    application/javascript
    application/json
    application/manifest+json
    application/wasm
    font/ttf
    image/svg+xml
    text/css
    text/javascript
    text/plain;

  root /usr/share/nginx/html;
  index index.html;

  location = /index.html {
    add_header Cache-Control "no-cache";
  }

  location = /flutter_service_worker.js {
    add_header Cache-Control "no-cache";
  }

  location = /flutter_bootstrap.js {
    add_header Cache-Control "no-cache";
    try_files $uri =404;
  }

  location = /main.dart.js {
    add_header Cache-Control "no-cache";
    try_files $uri =404;
  }

  location = /manifest.json {
    add_header Cache-Control "no-cache";
  }

  location = /assets/.env {
    add_header Cache-Control "no-cache";
  }

  location = /assets/.env.example {
    add_header Cache-Control "no-cache";
  }

  location = /env.js {
    add_header Cache-Control "no-cache";
  }

  location = /public-config.js {
    add_header Cache-Control "no-cache";
  }

  location ~* \.(js|wasm|css|ttf|png|jpg|jpeg|webp|svg)$ {
    add_header Cache-Control "public, max-age=31536000, immutable";
    try_files $uri =404;
  }

  location ~ ^/(support|privacy|terms|account-deletion|contact)$ {
    try_files /$1/index.html =404;
  }

  # Reverse proxy: /api/* -> API_UPSTREAM_URL/*
  location /api/ {
    proxy_ssl_server_name on;
    proxy_pass __UPSTREAM__/;
    proxy_http_version 1.1;
    proxy_set_header Host __UPSTREAM_HOST__;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }

  # Uploaded media generated by the API may resolve to same-origin /uploads/*
  # when requests arrive through the web proxy.
  location /uploads/ {
    proxy_ssl_server_name on;
    proxy_pass __UPSTREAM__/uploads/;
    proxy_http_version 1.1;
    proxy_set_header Host __UPSTREAM_HOST__;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }

  location / {
    try_files $uri $uri/ /index.html;
  }
}
EOF

  sed -i \
    -e "s@__UPSTREAM__@${UPSTREAM_ESC}@g" \
    -e "s@__UPSTREAM_HOST__@${UPSTREAM_HOST_ESC}@g" \
    "$NGINX_CONF"
fi

exec nginx -g "daemon off;"
