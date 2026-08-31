const LOCAL_UAT_DB_NAME = "daleventa_uat_local";
const SERVER_UAT_DB_NAME = "daleventa_uat";
const PROTECTED_DATABASES = new Set(["daleventa", "daleventa_pos"]);
const KNOWN_REMOTE_HOST_PATTERNS = [
  /easypanel/i,
  /gcdndd/i,
  /31\.97\.99\.70/,
  /hostinger/i,
];

function isUatMode(env: NodeJS.ProcessEnv) {
  return (
    (env.APP_ENV ?? "").trim().toLowerCase() === "uat" ||
    (env.UAT_LOCAL_ONLY ?? "").trim().toLowerCase() === "true"
  );
}

function isServerUatMode(env: NodeJS.ProcessEnv) {
  return (env.UAT_SERVER_MODE ?? "").trim().toLowerCase() === "true";
}

function expectedUatDatabase(env: NodeJS.ProcessEnv) {
  return isServerUatMode(env) ? SERVER_UAT_DB_NAME : LOCAL_UAT_DB_NAME;
}

function parseDatabaseUrl(rawUrl: string) {
  try {
    const parsed = new URL(rawUrl);
    const database = parsed.pathname.replace(/^\/+/, "").split("?")[0];
    return {
      host: parsed.hostname,
      database,
      port: parsed.port || "5432",
    };
  } catch {
    throw new Error("UAT safety refused startup: DATABASE_URL is invalid.");
  }
}

export function assertSafeUatEnvironment(env = process.env) {
  if (!isUatMode(env)) return;

  const rawUrl = (env.DATABASE_URL ?? "").trim();
  if (!rawUrl) {
    throw new Error("UAT safety refused startup: DATABASE_URL is required.");
  }

  const { host, database } = parseDatabaseUrl(rawUrl);
  const normalizedDatabase = database.toLowerCase();
  const normalizedHost = host.toLowerCase();
  const localHosts = new Set(["localhost", "127.0.0.1", "::1"]);
  const serverUat = isServerUatMode(env);
  const expectedDatabase = expectedUatDatabase(env);

  if (PROTECTED_DATABASES.has(normalizedDatabase)) {
    throw new Error(
      `UAT safety refused startup: protected database "${database}" is forbidden.`,
    );
  }

  if (normalizedDatabase !== expectedDatabase) {
    throw new Error(
      `UAT safety refused startup: database must be "${expectedDatabase}", got "${database}".`,
    );
  }

  if (!serverUat && !localHosts.has(normalizedHost)) {
    throw new Error(
      `UAT safety refused startup: host must be localhost/127.0.0.1/::1, got "${host}".`,
    );
  }

  if (!serverUat) {
    for (const pattern of KNOWN_REMOTE_HOST_PATTERNS) {
      if (pattern.test(rawUrl)) {
        throw new Error(
          "UAT safety refused startup: DATABASE_URL matches known remote production infrastructure.",
        );
      }
    }
  }
}

export function buildSafeUatBanner(env = process.env) {
  const rawUrl = (env.DATABASE_URL ?? "").trim();
  const parsed = rawUrl
    ? parseDatabaseUrl(rawUrl)
    : { host: "missing", database: "missing", port: "missing" };
  const serverUat = isServerUatMode(env);
  const port = (env.PORT ?? "4000").trim();
  const api = serverUat
    ? (env.API_BASE_URL ?? `http://0.0.0.0:${port}`).trim()
    : `http://127.0.0.1:${port}`;

  return [
    serverUat ? "ENVIRONMENT: UAT SERVER" : "ENVIRONMENT: UAT LOCAL",
    `DATABASE: ${parsed.database}`,
    `DATABASE_HOST: ${parsed.host}`,
    `DATABASE_PORT: ${parsed.port}`,
    `API: ${api}`,
    `PRODUCT SOURCE: ${(env.PRODUCTS_SOURCE ?? "LOCAL").trim() || "LOCAL"}`,
    "PRODUCTION: NOT CONNECTED",
  ].join("\n");
}
