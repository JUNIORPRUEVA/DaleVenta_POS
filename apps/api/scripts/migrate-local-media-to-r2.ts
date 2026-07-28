import { PrismaClient } from '@prisma/client';
import { HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import * as fs from 'node:fs';
import { join } from 'node:path';

const prisma = new PrismaClient();

const dryRun = process.argv.includes('--dry-run');

function requiredEnv(name: string) {
  const value = (process.env[name] ?? '').trim();
  if (!value) throw new Error(`Falta ${name}`);
  return value;
}

function resolveUploadDir() {
  const fromEnv = (process.env.UPLOAD_DIR ?? '').trim();
  const volumeDir = '/uploads';
  if (fromEnv) {
    if ((fromEnv === './uploads' || fromEnv === 'uploads') && fs.existsSync(volumeDir)) {
      return volumeDir;
    }
    return fromEnv;
  }
  return fs.existsSync(volumeDir) ? volumeDir : join(process.cwd(), 'uploads');
}

function extractObjectKey(raw?: string | null) {
  const value = (raw ?? '').trim().replace(/\\/g, '/');
  if (!value || value.includes('..')) return null;
  if (value.startsWith('uploads/')) return value;
  if (value.startsWith('./uploads/')) return value.substring(2);
  const marker = '/uploads/';
  const markerIndex = value.indexOf(marker);
  if (markerIndex >= 0) return value.substring(markerIndex + 1);
  return null;
}

function localPathForObjectKey(uploadDir: string, objectKey: string) {
  const withoutUploads = objectKey.startsWith('uploads/')
    ? objectKey.substring('uploads/'.length)
    : objectKey;
  return join(uploadDir, ...withoutUploads.split('/'));
}

function guessMimeType(filePath: string) {
  const value = filePath.toLowerCase();
  if (value.endsWith('.png')) return 'image/png';
  if (value.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

async function objectExists(s3: S3Client, bucket: string, key: string) {
  try {
    await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const endpoint = requiredEnv('R2_ENDPOINT');
  const bucket = requiredEnv('R2_BUCKET');
  const accessKeyId = requiredEnv('R2_ACCESS_KEY_ID');
  const secretAccessKey = requiredEnv('R2_SECRET_ACCESS_KEY');
  const region = (process.env.R2_REGION ?? 'auto').trim() || 'auto';
  const uploadDir = resolveUploadDir();

  const s3 = new S3Client({
    region,
    endpoint,
    credentials: { accessKeyId, secretAccessKey },
    forcePathStyle: true,
  });

  const products = await prisma.product.findMany({
    where: {
      OR: [
        { imagen: { contains: '/uploads/' } },
        { imagen: { startsWith: 'uploads/' } },
        { imagen: { startsWith: './uploads/' } },
      ],
    },
  });

  let migrated = 0;
  let alreadyExisting = 0;
  let missing = 0;
  let errors = 0;

  for (const product of products) {
    const currentKey = (product as any).imageKey as string | null | undefined;
    if (currentKey?.trim()) {
      alreadyExisting += 1;
      continue;
    }

    const objectKey = extractObjectKey(product.imagen);
    if (!objectKey || !objectKey.startsWith('uploads/companies/')) {
      missing += 1;
      console.warn(`[media:migrate] skip product=${product.id} reason=invalid-key imagen=${product.imagen ?? ''}`);
      continue;
    }

    try {
      const exists = await objectExists(s3, bucket, objectKey);
      if (!exists) {
        const localPath = localPathForObjectKey(uploadDir, objectKey);
        if (!fs.existsSync(localPath)) {
          missing += 1;
          console.warn(`[media:migrate] missing product=${product.id} key=${objectKey}`);
          continue;
        }
        if (!dryRun) {
          await s3.send(
            new PutObjectCommand({
              Bucket: bucket,
              Key: objectKey,
              Body: fs.createReadStream(localPath),
              ContentType: guessMimeType(localPath),
            }),
          );
        }
      }

      if (!dryRun) {
        await prisma.product.update({
          where: { id: product.id },
          data: {
            imageStorageProvider: 'r2',
            imageKey: objectKey,
            imageMimeType: guessMimeType(objectKey),
            imageUpdatedAt: new Date(),
          },
        });
      }

      migrated += 1;
      console.log(`[media:migrate] ${dryRun ? 'would migrate' : 'migrated'} product=${product.id} key=${objectKey}`);
    } catch (error) {
      errors += 1;
      console.error(`[media:migrate] error product=${product.id} key=${objectKey}`, error);
    }
  }

  console.log(
    `[media:migrate] done dryRun=${dryRun} total=${products.length} migrated=${migrated} alreadyExisting=${alreadyExisting} missing=${missing} errors=${errors}`,
  );
}

main()
  .catch((error) => {
    console.error('[media:migrate] fatal', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
