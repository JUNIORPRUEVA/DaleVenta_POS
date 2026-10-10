param(
  [string]$Prefix = 'releases/windows/',
  [string]$SpecificKey = '',
  [string[]]$EnvFile = @('.env', 'apps\api\.env'),
  [int]$MaxKeys = 1000
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  $scriptDir = Split-Path -Parent $PSCommandPath
  return (Resolve-Path -LiteralPath (Join-Path $scriptDir '..\..')).Path
}

$repoRoot = Get-RepoRoot
$envFiles = @()
foreach ($file in $EnvFile) {
  $path = if ([IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $repoRoot $file }
  if (Test-Path -LiteralPath $path) {
    $envFiles += (Resolve-Path -LiteralPath $path).Path
  }
}

$nodeScript = @'
const fs = require('fs');

for (const file of process.env.FULLPOS_RELEASE_ENV_FILES.split(';').filter(Boolean)) {
  if (!fs.existsSync(file)) continue;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match || process.env[match[1]] != null) continue;
    process.env[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
  }
}

let s3Module;
try {
  s3Module = require('@aws-sdk/client-s3');
} catch (error) {
  console.log(JSON.stringify({
    storageReadonly: false,
    status: 'BLOCKED_DEPENDENCY',
    reason: 'The @aws-sdk/client-s3 package is not installed in this worktree. Run npm ci before storage audit.',
  }, null, 2));
  process.exit(2);
}

const {
  S3Client,
  ListObjectsV2Command,
  HeadObjectCommand,
} = s3Module;

const endpoint = (
  process.env.R2_ENDPOINT ||
  process.env.R2_S3_ENDPOINT ||
  process.env.CLOUDFLARE_R2_ENDPOINT ||
  process.env.FULLPOS_RELEASE_S3_ENDPOINT_URL ||
  ''
).trim();
const bucket = (
  process.env.R2_BUCKET ||
  process.env.R2_BUCKET_NAME ||
  process.env.FULLPOS_RELEASE_BUCKET ||
  ''
).trim();
const accessKeyId = (
  process.env.R2_ACCESS_KEY_ID ||
  process.env.AWS_ACCESS_KEY_ID ||
  ''
).trim();
const secretAccessKey = (
  process.env.R2_SECRET_ACCESS_KEY ||
  process.env.AWS_SECRET_ACCESS_KEY ||
  ''
).trim();
const region = (process.env.R2_REGION || process.env.AWS_REGION || 'auto').trim() || 'auto';

if (!bucket || !accessKeyId || !secretAccessKey) {
  console.log(JSON.stringify({
    storageReadonly: false,
    status: 'BLOCKED_CONFIG',
    reason: 'Missing non-secret bucket name or credentials in the current environment.',
    bucketConfigured: Boolean(bucket),
    endpointConfigured: Boolean(endpoint),
    accessKeyConfigured: Boolean(accessKeyId),
    secretKeyConfigured: Boolean(secretAccessKey),
  }, null, 2));
  process.exit(2);
}

const s3 = new S3Client({
  region,
  endpoint: endpoint || undefined,
  credentials: { accessKeyId, secretAccessKey },
  forcePathStyle: true,
  maxAttempts: 2,
});

(async () => {
  const prefix = process.env.FULLPOS_RELEASE_AUDIT_PREFIX || 'releases/windows/';
  const specificKey = process.env.FULLPOS_RELEASE_AUDIT_KEY || '';
  const maxKeys = Number(process.env.FULLPOS_RELEASE_AUDIT_MAX_KEYS || '1000');
  const listed = await s3.send(new ListObjectsV2Command({
    Bucket: bucket,
    Prefix: prefix,
    MaxKeys: maxKeys,
  }));
  const objects = (listed.Contents || []).map((item) => ({
    key: item.Key,
    size: item.Size,
    lastModified: item.LastModified,
    etag: item.ETag,
  }));

  let head = null;
  if (specificKey) {
    try {
      const result = await s3.send(new HeadObjectCommand({
        Bucket: bucket,
        Key: specificKey,
      }));
      head = {
        key: specificKey,
        exists: true,
        size: result.ContentLength,
        lastModified: result.LastModified,
        etag: result.ETag,
        contentType: result.ContentType,
      };
    } catch (error) {
      head = {
        key: specificKey,
        exists: false,
        error: error.name || error.Code || error.message,
      };
    }
  }

  console.log(JSON.stringify({
    storageReadonly: true,
    status: 'OK',
    endpointConfigured: Boolean(endpoint),
    bucketName: bucket,
    prefix,
    count: objects.length,
    objects,
    specificKey: head,
  }, null, 2));
})().catch((error) => {
  console.log(JSON.stringify({
    storageReadonly: false,
    status: 'ERROR',
    endpointConfigured: Boolean(endpoint),
    bucketName: bucket || null,
    error: error.name || error.Code || error.message,
    message: error.message,
  }, null, 2));
  process.exit(1);
});
'@

$env:FULLPOS_RELEASE_ENV_FILES = ($envFiles -join ';')
$env:FULLPOS_RELEASE_AUDIT_PREFIX = $Prefix
$env:FULLPOS_RELEASE_AUDIT_KEY = $SpecificKey
$env:FULLPOS_RELEASE_AUDIT_MAX_KEYS = [string]$MaxKeys

node -e $nodeScript
exit $LASTEXITCODE
