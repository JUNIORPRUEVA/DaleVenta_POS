import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// The root lock is authoritative. EasyPanel's API build context is apps/api,
// so materialize only that workspace's reachable, already-locked dependency
// graph. CI checks this generated artifact instead of resolving versions again.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'apps/api/package.json'), 'utf8'));
const lock = JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json'), 'utf8'));
if (lock.lockfileVersion !== 3 || !lock.packages?.['apps/api']) {
  throw new Error('API_DOCKER_LOCK_ROOT_FORMAT_UNSUPPORTED');
}

function resolveDependency(from, name) {
  let directory = from || '.';
  while (true) {
    if (path.posix.basename(directory) !== 'node_modules') {
      const candidate = path.posix.join(directory === '.' ? '' : directory, 'node_modules', name);
      if (lock.packages[candidate]) return candidate;
    }
    if (directory === '.') return null;
    directory = path.posix.dirname(directory);
  }
}

const selected = new Set();
function visit(from, dependencies, optional = new Set()) {
  for (const name of Object.keys(dependencies || {})) {
    const key = resolveDependency(from, name);
    if (!key) {
      if (optional.has(name)) continue;
      throw new Error(`API_DOCKER_LOCK_DEPENDENCY_MISSING: ${name}`);
    }
    if (selected.has(key)) continue;
    const entry = lock.packages[key];
    if (entry.link || !key.startsWith('node_modules/')) {
      throw new Error('API_DOCKER_LOCK_EXTERNAL_WORKSPACE_REQUIRES_REVIEW');
    }
    selected.add(key);
    const optionalNames = new Set(Object.keys(entry.optionalDependencies || {}));
    visit(key, { ...entry.dependencies, ...entry.optionalDependencies }, optionalNames);
    const optionalPeers = new Set(Object.entries(entry.peerDependenciesMeta || {})
      .filter(([, metadata]) => metadata.optional).map(([peer]) => peer));
    visit(key, entry.peerDependencies, optionalPeers);
  }
}
visit('apps/api', { ...manifest.dependencies, ...manifest.devDependencies, ...manifest.optionalDependencies },
  new Set(Object.keys(manifest.optionalDependencies || {})));

const workspace = {};
for (const key of ['name', 'version', 'license', 'dependencies', 'devDependencies', 'optionalDependencies', 'engines']) {
  if (manifest[key] !== undefined) workspace[key] = manifest[key];
}
const generated = { name: manifest.name, version: manifest.version, lockfileVersion: 3, requires: true,
  packages: { '': workspace, ...Object.fromEntries([...selected].sort().map(key => [key, lock.packages[key]])) } };
const output = JSON.stringify(generated, null, 2) + '\n';
const target = path.join(root, 'apps/api/package-lock.json');
if (process.argv.includes('--check')) {
  if (!fs.existsSync(target) || fs.readFileSync(target, 'utf8').replaceAll('\r\n', '\n') !== output) {
    throw new Error('API_DOCKER_LOCK_STALE: run node scripts/release/sync_api_docker_lock.mjs');
  }
  console.log(`API Docker lock verified: ${selected.size} packages, root versions preserved.`);
} else {
  fs.writeFileSync(target, output);
  console.log(`API Docker lock generated: ${selected.size} packages, no registry resolution.`);
}
