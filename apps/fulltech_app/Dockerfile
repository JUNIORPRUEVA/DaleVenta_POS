# syntax=docker/dockerfile:1

# Pinned so the ngx_brotli dynamic module compiled below is ABI compatible with
# the nginx used at runtime (the official image is built with --with-compat).
ARG NGINX_VERSION=1.31.6

FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

ARG META_PIXEL_ID=411890861585278
ARG MARKETING_ANALYTICS_DEBUG=false

# Copy only what is needed for a Flutter Web build.
COPY pubspec.yaml pubspec.lock ./
COPY analysis_options.yaml ./
COPY lib ./lib
COPY assets ./assets
COPY web ./web
COPY .env.example ./.env.example

# The app references .env as an asset; create it from .env.example for CI/builds.
RUN cp .env.example .env

RUN git config --global --add safe.directory /sdks/flutter

RUN flutter --version \
  && flutter config --enable-web \
  && flutter pub get \
  && flutter build web --release --no-wasm-dry-run --no-source-maps --optimization-level=4 \
    --no-web-resources-cdn \
    --dart-define=META_PIXEL_ID=${META_PIXEL_ID} \
    --dart-define=MARKETING_ANALYTICS_DEBUG=${MARKETING_ANALYTICS_DEBUG}

RUN BUILD_ID="$(date -u +%Y%m%d%H%M%S)" \
  && sed -i "s@main.dart.js@main.dart.js?v=${BUILD_ID}@g" build/web/flutter_bootstrap.js \
  && sed -i "s@href=\"main.dart.js\"@href=\"main.dart.js?v=${BUILD_ID}\"@g" build/web/index.html \
  && sed -i "s@src=\"flutter_bootstrap.js\"@src=\"flutter_bootstrap.js?v=${BUILD_ID}\"@g" build/web/index.html

# Runtime files the browser never requests: debug symbols and the dart2wasm /
# skwasm variants (this build only ships the dart2js + CanvasKit build).
RUN cd build/web \
  && rm -f canvaskit/*.symbols canvaskit/chromium/*.symbols \
  && rm -f canvaskit/skwasm.js canvaskit/skwasm.wasm \
  && rm -f canvaskit/skwasm_heavy.js canvaskit/skwasm_heavy.wasm \
  && rm -f canvaskit/wimp.js canvaskit/wimp.wasm

# Pre-compressed Brotli variants, served statically (no dynamic brotli CPU).
RUN apt-get update \
  && apt-get install -y --no-install-recommends brotli \
  && rm -rf /var/lib/apt/lists/* \
  && cd build/web \
  && find . -type f \
       \( -name '*.js' -o -name '*.mjs' -o -name '*.css' -o -name '*.wasm' \
          -o -name '*.json' -o -name '*.html' -o -name '*.svg' -o -name '*.txt' \
          -o -name '*.xml' -o -name '*.ttf' -o -name '*.otf' -o -name '*.frag' \) \
       ! -name 'env.js' ! -name 'public-config.js' \
       -exec brotli -q 11 -k -f {} + \
  && test -f main.dart.js.br \
  && test -f canvaskit/canvaskit.wasm \
  && test -f canvaskit/chromium/canvaskit.wasm

# ngx_brotli compiled as a dynamic module against the exact nginx version that
# runs at runtime (both stages use the same pinned tag).
FROM nginx:${NGINX_VERSION}-alpine AS brotli-module
ARG NGINX_VERSION
# pcre2-dev + zlib-dev satisfy the default rewrite/gzip module checks during
# ./configure; those libs are never linked into the produced module.
# cmake builds the brotli dependencies (deps/brotli) as static libs, which is
# required before ./configure --add-dynamic-module (see ngx_brotli README).
RUN apk add --no-cache --virtual .brotli-build build-base git linux-headers pcre2-dev zlib-dev cmake \
  && git clone --depth 1 --recurse-submodules https://github.com/google/ngx_brotli /tmp/ngx_brotli \
  && mkdir -p /tmp/ngx_brotli/deps/brotli/out \
  && cd /tmp/ngx_brotli/deps/brotli/out \
  && cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBROTLI_DISABLE_TESTS=ON .. > /dev/null \
  && cmake --build . --config Release -j"$(nproc)" \
  && wget -qO- "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" | tar xz -C /tmp \
  && cd "/tmp/nginx-${NGINX_VERSION}" \
  && ./configure --with-compat --add-dynamic-module=/tmp/ngx_brotli \
  && make -j"$(nproc)" modules \
  && mkdir -p /modules \
  && cp objs/ngx_http_brotli_filter_module.so objs/ngx_http_brotli_static_module.so /modules/ \
  && ls -la /modules \
  && { readelf -d /modules/ngx_http_brotli_filter_module.so 2>/dev/null | grep -i 'NEEDED' || echo "DIAG: readelf unavailable"; }

FROM nginx:${NGINX_VERSION}-alpine

ARG META_PIXEL_ID=411890861585278
ARG MARKETING_ANALYTICS_DEBUG=false
ENV META_PIXEL_ID=${META_PIXEL_ID}
ENV MARKETING_ANALYTICS_DEBUG=${MARKETING_ANALYTICS_DEBUG}

COPY --from=brotli-module /modules/ngx_http_brotli_filter_module.so /usr/lib/nginx/modules/
COPY --from=brotli-module /modules/ngx_http_brotli_static_module.so /usr/lib/nginx/modules/

# load_module must live in the main context of nginx.conf.
RUN printf 'load_module modules/ngx_http_brotli_filter_module.so;\nload_module modules/ngx_http_brotli_static_module.so;\n' > /tmp/load_modules.txt \
  && cat /tmp/load_modules.txt /etc/nginx/nginx.conf > /tmp/nginx.conf.new \
  && mv /tmp/nginx.conf.new /etc/nginx/nginx.conf \
  && rm -f /tmp/load_modules.txt

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY nginx-maps.conf /etc/nginx/conf.d/00-maps.conf
COPY --from=build /app/build/web /usr/share/nginx/html

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN sed -i 's/\r$//' /docker-entrypoint.sh \
  && chmod +x /docker-entrypoint.sh

# Fails the build if the modules did not load or the config is invalid.
RUN nginx -t

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]
