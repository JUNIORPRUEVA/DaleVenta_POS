#!/bin/sh
set -eu

escape_js() {
  printf '%s' "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g"
}

API_BASE="$(escape_js "${FULLTECH_API_BASE_URL:-}")"

cat > /usr/share/nginx/html/env.js <<EOF
window.FULLTECH_API_BASE_URL = '${API_BASE}';
EOF
