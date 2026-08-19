const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

const apiDir = path.resolve(__dirname, '..');
const repoRoot = path.resolve(apiDir, '..', '..');
const flutterDir = path.join(repoRoot, 'apps', 'fulltech_app');

function readEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const env = {};
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const index = trimmed.indexOf('=');
    if (index <= 0) continue;
    const key = trimmed.slice(0, index).trim();
    let value = trimmed.slice(index + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    env[key] = value;
  }
  return env;
}

function command(name) {
  if (process.platform === 'win32' && name === 'flutter') return 'flutter.bat';
  return process.platform === 'win32' ? `${name}.cmd` : name;
}

function run(cmd, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, {
      cwd: options.cwd,
      env: options.env,
      stdio: options.stdio ?? 'inherit',
      shell:
        process.platform === 'win32' &&
        (cmd.endsWith('.cmd') || cmd.endsWith('.bat')),
    });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${cmd} ${args.join(' ')} exited with code ${code}`));
    });
  });
}

async function waitForHealth(url, child) {
  const started = Date.now();
  let lastError = '';
  while (Date.now() - started < 60000) {
    if (child.exitCode !== null) {
      throw new Error(`API process exited before health check (code ${child.exitCode})`);
    }
    try {
      const res = await fetch(url);
      if (res.ok) return;
      lastError = `HTTP ${res.status}`;
    } catch (error) {
      lastError = error.message;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`API did not become healthy at ${url}: ${lastError}`);
}

async function createDatabase(adminUrl, dbName) {
  const client = new Client({ connectionString: adminUrl.toString() });
  await client.connect();
  try {
    await client.query(`CREATE DATABASE "${dbName}"`);
  } finally {
    await client.end();
  }
}

async function dropDatabase(adminUrl, dbName) {
  const client = new Client({ connectionString: adminUrl.toString() });
  await client.connect();
  try {
    await client.query(
      `SELECT pg_terminate_backend(pid)
       FROM pg_stat_activity
       WHERE datname = $1 AND pid <> pg_backend_pid()`,
      [dbName],
    );
    await client.query(`DROP DATABASE IF EXISTS "${dbName}"`);
  } finally {
    await client.end();
  }
}

async function main() {
  const fileEnv = readEnvFile(path.join(apiDir, '.env'));
  const baseDatabaseUrl = process.env.DATABASE_URL ?? fileEnv.DATABASE_URL;
  if (!baseDatabaseUrl) {
    throw new Error('DATABASE_URL is required in env or apps/api/.env');
  }

  const dbName = `fullpos_flutter_offline_e2e_${Date.now()}`;
  const appUrl = new URL(baseDatabaseUrl);
  const adminUrl = new URL(baseDatabaseUrl);
  adminUrl.pathname = '/postgres';
  appUrl.pathname = `/${dbName}`;

  const port = String(49100 + Math.floor(Math.random() * 1000));
  const apiBaseUrl = `http://127.0.0.1:${port}`;
  const env = {
    ...process.env,
    ...fileEnv,
    NODE_ENV: 'test',
    DATABASE_URL: appUrl.toString(),
    JWT_SECRET: process.env.JWT_SECRET ?? fileEnv.JWT_SECRET ?? 'offline-flutter-e2e-secret',
    PORT: port,
    API_BASE_URL: apiBaseUrl,
    PUBLIC_BASE_URL: apiBaseUrl,
    UPLOAD_DIR: path.join(apiDir, '.runtime_audit_logs', 'offline-flutter-e2e-uploads'),
    NODE_PATH: [
      path.join(apiDir, 'node_modules'),
      process.env.NODE_PATH,
    ].filter(Boolean).join(path.delimiter),
  };

  let apiProcess;
  try {
    console.log(`[offline-flutter-e2e] creating database ${dbName}`);
    await createDatabase(adminUrl, dbName);

    console.log('[offline-flutter-e2e] applying Prisma migrations');
    await run(command('npx'), ['prisma', 'migrate', 'deploy'], {
      cwd: apiDir,
      env,
    });

    console.log(`[offline-flutter-e2e] starting API at ${apiBaseUrl}`);
    const tsNode = require.resolve('ts-node/dist/bin.js', { paths: [apiDir] });
    apiProcess = spawn(process.execPath, [tsNode, '--transpile-only', 'src/main.ts'], {
      cwd: apiDir,
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    apiProcess.stdout.on('data', (data) => process.stdout.write(`[api] ${data}`));
    apiProcess.stderr.on('data', (data) => process.stderr.write(`[api] ${data}`));

    await waitForHealth(`${apiBaseUrl}/health`, apiProcess);

    console.log('[offline-flutter-e2e] running Flutter integration test');
    await run(
      command('flutter'),
      [
        'test',
        'test/e2e/offline_sales_e2e_test.dart',
        `--dart-define=API_BASE_URL=${apiBaseUrl}`,
        '--dart-define=API_TIMEOUT_MS=5000',
      ],
      {
        cwd: flutterDir,
        env: { ...process.env, API_BASE_URL: apiBaseUrl },
      },
    );
  } finally {
    if (apiProcess && apiProcess.exitCode === null) {
      apiProcess.kill();
      await new Promise((resolve) => setTimeout(resolve, 1000));
      if (apiProcess.exitCode === null) apiProcess.kill('SIGKILL');
    }
    console.log(`[offline-flutter-e2e] dropping database ${dbName}`);
    await dropDatabase(adminUrl, dbName).catch((error) => {
      console.warn(`[offline-flutter-e2e] database cleanup failed: ${error.message}`);
    });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
