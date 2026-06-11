FROM node:20-bullseye-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates openssl wget && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=development
COPY package*.json ./
RUN npm install --include=dev --no-audit --no-fund
COPY prisma ./prisma
RUN npx prisma generate
COPY tsconfig*.json ./
COPY src ./src
COPY scripts ./scripts
RUN npm run build

FROM node:20-bullseye-slim AS runner
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates openssl wget && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=4000
ENV RUN_MIGRATIONS=true
ENV MIGRATION_STRICT=false
ENV REDIS_ENABLED=false
ENV PRODUCTS_SOURCE=LOCAL
COPY package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/scripts ./scripts
# Normalize line endings for Linux containers (Windows CRLF can break /bin/sh)
RUN sed -i 's/\r$//' scripts/start-prod.sh && chmod +x scripts/start-prod.sh
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=10 CMD sh -c 'wget -q -O - "http://127.0.0.1:${PORT:-4000}/health" >/dev/null 2>&1 || exit 1'
CMD ["sh", "scripts/start-prod.sh"]
