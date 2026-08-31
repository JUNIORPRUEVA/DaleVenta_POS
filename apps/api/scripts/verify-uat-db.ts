import { Client } from "pg";

function requiredDbName() {
  return (process.env.UAT_SERVER_MODE ?? "").trim().toLowerCase() === "true"
    ? "daleventa_uat"
    : "daleventa_uat_local";
}

function assertUatUrl(rawUrl: string) {
  if (!rawUrl) throw new Error("DATABASE_URL is required.");
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new Error("DATABASE_URL is invalid.");
  }

  const database = parsed.pathname.replace(/^\/+/, "").split("?")[0];
  const expectedDb = requiredDbName();
  if (database !== expectedDb) {
    throw new Error(
      `Refusing UAT DB verification: expected ${expectedDb}, got ${database}.`,
    );
  }
  const serverUat =
    (process.env.UAT_SERVER_MODE ?? "").trim().toLowerCase() === "true";
  if (
    !serverUat &&
    !["localhost", "127.0.0.1", "::1"].includes(parsed.hostname)
  ) {
    throw new Error(
      `Refusing UAT DB verification: host must be local, got ${parsed.hostname}.`,
    );
  }
  if (/\/daleventa($|\?)|\/daleventa_pos($|\?)/i.test(rawUrl)) {
    throw new Error(
      "Refusing UAT DB verification: URL looks remote or protected.",
    );
  }
}

async function main() {
  const appEnv = (process.env.APP_ENV ?? "").trim().toLowerCase();
  const localOnly = (process.env.UAT_LOCAL_ONLY ?? "").trim().toLowerCase();
  const serverUat = (process.env.UAT_SERVER_MODE ?? "").trim().toLowerCase();
  if (appEnv !== "uat" || (localOnly !== "true" && serverUat !== "true")) {
    throw new Error(
      "APP_ENV=uat and UAT_LOCAL_ONLY=true or UAT_SERVER_MODE=true are required.",
    );
  }

  const databaseUrl = (process.env.DATABASE_URL ?? "").trim();
  assertUatUrl(databaseUrl);

  const client = new Client({ connectionString: databaseUrl });
  await client.connect();
  try {
    const result = await client.query<{
      current_database: string;
      current_user: string;
      inet_server_addr: string | null;
      inet_server_port: number;
    }>(
      "SELECT current_database(), current_user, inet_server_addr(), inet_server_port()",
    );
    const row = result.rows[0];
    const expectedDb = requiredDbName();
    if (row.current_database !== expectedDb) {
      throw new Error(
        `Connected to ${row.current_database}, expected ${expectedDb}.`,
      );
    }
    console.log("UAT database identity verified:", {
      database: row.current_database,
      user: row.current_user,
      serverAddress: row.inet_server_addr ?? "local-socket",
      serverPort: row.inet_server_port,
    });
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
