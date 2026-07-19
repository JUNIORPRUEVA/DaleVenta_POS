# syntax=docker/dockerfile:1

FROM node:22-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
COPY apps/api/package.json ./apps/api/package.json
COPY apps/web/package.json ./apps/web/package.json
RUN npm ci --workspace apps/web --include-workspace-root=false

COPY apps/web ./apps/web
RUN npm run web:build

FROM nginx:1.27-alpine AS runtime

ENV FULLTECH_API_BASE_URL="https://fulltech-tienda-fulltechapppwa.gcdndd.easypanel.host"

COPY apps/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY apps/web/docker-entrypoint.sh /docker-entrypoint.d/40-fulltech-web-env.sh
COPY --from=build /app/apps/web/dist /usr/share/nginx/html

RUN chmod +x /docker-entrypoint.d/40-fulltech-web-env.sh

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/healthz >/dev/null || exit 1
