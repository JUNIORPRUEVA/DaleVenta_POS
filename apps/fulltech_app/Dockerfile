# syntax=docker/dockerfile:1

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
    --dart-define=META_PIXEL_ID=${META_PIXEL_ID} \
    --dart-define=MARKETING_ANALYTICS_DEBUG=${MARKETING_ANALYTICS_DEBUG}

RUN BUILD_ID="$(date -u +%Y%m%d%H%M%S)" \
  && sed -i "s@main.dart.js@main.dart.js?v=${BUILD_ID}@g" build/web/flutter_bootstrap.js \
  && sed -i "s@href=\"main.dart.js\"@href=\"main.dart.js?v=${BUILD_ID}\"@g" build/web/index.html \
  && sed -i "s@src=\"flutter_bootstrap.js\"@src=\"flutter_bootstrap.js?v=${BUILD_ID}\"@g" build/web/index.html

FROM nginx:alpine

ARG META_PIXEL_ID=411890861585278
ARG MARKETING_ANALYTICS_DEBUG=false
ENV META_PIXEL_ID=${META_PIXEL_ID}
ENV MARKETING_ANALYTICS_DEBUG=${MARKETING_ANALYTICS_DEBUG}

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN sed -i 's/\r$//' /docker-entrypoint.sh \
  && chmod +x /docker-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]
