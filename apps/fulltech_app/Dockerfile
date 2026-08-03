# syntax=docker/dockerfile:1

FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

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
  && flutter build web --release --no-wasm-dry-run --no-source-maps --optimization-level=4

FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]
