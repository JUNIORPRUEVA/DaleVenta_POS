import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  S3Client,
  DeleteObjectsCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  GetObjectCommandOutput,
  HeadObjectCommand,
  HeadObjectCommandOutput,
  PutObjectCommand,
  ListObjectsV2Command,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import type { Readable } from 'node:stream';

@Injectable()
export class R2Service {
  private readonly s3: S3Client;
  private readonly bucket: string;
  private readonly publicBaseUrl: string;

  constructor(private readonly config: ConfigService) {
    // IMPORTANT: env vars are assumed to already exist in deployment.
    // We only read them; we don't try to configure or validate secrets here.
    const endpoint = (
      this.config.get<string>('R2_ENDPOINT') ??
      this.config.get<string>('R2_S3_ENDPOINT') ??
      this.config.get<string>('CLOUDFLARE_R2_ENDPOINT') ??
      ''
    ).trim();

    const region = (this.config.get<string>('R2_REGION') ?? 'auto').trim() || 'auto';

    const accessKeyId = (
      this.config.get<string>('R2_ACCESS_KEY_ID') ??
      this.config.get<string>('AWS_ACCESS_KEY_ID') ??
      ''
    ).trim();

    const secretAccessKey = (
      this.config.get<string>('R2_SECRET_ACCESS_KEY') ??
      this.config.get<string>('AWS_SECRET_ACCESS_KEY') ??
      ''
    ).trim();

    this.bucket = (
      this.config.get<string>('R2_BUCKET') ??
      this.config.get<string>('R2_BUCKET_NAME') ??
      ''
    ).trim();

    this.publicBaseUrl = (
      this.config.get<string>('R2_PUBLIC_BASE_URL') ??
      this.config.get<string>('PUBLIC_R2_BASE_URL') ??
      this.config.get<string>('R2_PUBLIC_URL_BASE') ??
      ''
    )
      .trim()
      .replace(/\/$/, '');

    this.s3 = new S3Client({
      region,
      endpoint: endpoint || undefined,
      credentials:
        accessKeyId && secretAccessKey
          ? { accessKeyId, secretAccessKey }
          : undefined,
      forcePathStyle: true,
    });
  }

  buildPublicUrl(objectKey: string): string {
    if (!this.publicBaseUrl) return objectKey; // fallback (caller can still store key)
    const key = objectKey.replace(/^\//, '');
    return `${this.publicBaseUrl}/${key}`;
  }

  async createPresignedPutUrl(params: {
    objectKey: string;
    contentType: string;
    expiresInSeconds: number;
  }) {
    if (!this.bucket) {
      throw new InternalServerErrorException('R2 bucket no configurado');
    }

    const cmd = new PutObjectCommand({
      Bucket: this.bucket,
      Key: params.objectKey,
      ContentType: params.contentType,
    });

    const uploadUrl = await getSignedUrl(this.s3, cmd, {
      expiresIn: params.expiresInSeconds,
    });

    return uploadUrl;
  }

  async putObject(params: { objectKey: string; body: Buffer | Uint8Array; contentType: string }) {
    if (!this.bucket) {
      throw new InternalServerErrorException('R2 bucket no configurado');
    }

    await this.s3.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: params.objectKey,
        Body: params.body,
        ContentType: params.contentType,
      }),
    );

    return { ok: true };
  }

  async createPresignedGetUrl(params: { objectKey: string; expiresInSeconds: number }) {
    if (!this.bucket) {
      throw new InternalServerErrorException('R2 bucket no configurado');
    }

    const cmd = new GetObjectCommand({
      Bucket: this.bucket,
      Key: params.objectKey,
    });

    return getSignedUrl(this.s3, cmd, {
      expiresIn: params.expiresInSeconds,
    });
  }

  async getObject(objectKey: string) {
    if (!this.bucket) {
      throw new InternalServerErrorException('R2 bucket no configurado');
    }

    const res = (await this.s3.send(
      new GetObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
      }),
    )) as GetObjectCommandOutput;

    if (!res.Body) {
      throw new InternalServerErrorException('R2 no devolvió contenido');
    }

    const bytes = Buffer.from(await res.Body.transformToByteArray());
    return {
      body: bytes,
      contentType: typeof res.ContentType === 'string' ? res.ContentType : null,
      contentLength: typeof res.ContentLength === 'number' ? res.ContentLength : bytes.length,
    };
  }

  async getObjectStream(objectKey: string) {
    if (!this.bucket) {
      throw new InternalServerErrorException('R2 bucket no configurado');
    }

    const res = (await this.s3.send(
      new GetObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
      }),
    )) as GetObjectCommandOutput;

    if (!res.Body) {
      throw new InternalServerErrorException('R2 no devolvió contenido');
    }

    return {
      body: res.Body as Readable,
      contentType: typeof res.ContentType === 'string' ? res.ContentType : null,
      contentLength: typeof res.ContentLength === 'number' ? res.ContentLength : null,
      etag: typeof res.ETag === 'string' ? res.ETag : null,
      lastModified: res.LastModified ?? null,
    };
  }

  async getObjectRange(objectKey: string, range: string) {
    if (!this.bucket) {
      throw new InternalServerErrorException('R2 bucket no configurado');
    }

    const res = (await this.s3.send(
      new GetObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
        Range: range,
      }),
    )) as GetObjectCommandOutput;

    if (!res.Body) {
      throw new InternalServerErrorException('R2 no devolvió contenido');
    }

    const bytes = Buffer.from(await res.Body.transformToByteArray());
    return {
      body: bytes,
      contentType: typeof res.ContentType === 'string' ? res.ContentType : null,
      contentLength: typeof res.ContentLength === 'number' ? res.ContentLength : bytes.length,
      contentRange: typeof res.ContentRange === 'string' ? res.ContentRange : null,
    };
  }

  async headObject(objectKey: string) {
    if (!this.bucket) {
      throw new InternalServerErrorException('R2 bucket no configurado');
    }

    const res = (await this.s3.send(
      new HeadObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
      }),
    )) as HeadObjectCommandOutput;

    return {
      contentLength: typeof res.ContentLength === 'number' ? res.ContentLength : null,
      contentType: typeof res.ContentType === 'string' ? res.ContentType : null,
      etag: typeof res.ETag === 'string' ? res.ETag : null,
      lastModified: res.LastModified ?? null,
    };
  }

  async deleteObject(objectKey: string) {
    if (!this.bucket) {
      throw new InternalServerErrorException('R2 bucket no configurado');
    }

    await this.s3.send(
      new DeleteObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
      }),
    );

    return { ok: true };
  }

  async deleteAllCompanyObjects(companyId: string) {
    const normalizedCompanyId = (companyId ?? '').trim();
    if (!/^[0-9a-fA-F-]{36}$/.test(normalizedCompanyId)) {
      throw new InternalServerErrorException('Company id invalido para limpieza de storage');
    }
    if (!this.bucket) {
      return { ok: true, skipped: true, deleted: 0, prefix: null };
    }

    const prefix = `uploads/companies/${normalizedCompanyId}/`;
    let continuationToken: string | undefined;
    let deleted = 0;

    do {
      const listed = await this.s3.send(
        new ListObjectsV2Command({
          Bucket: this.bucket,
          Prefix: prefix,
          ContinuationToken: continuationToken,
          MaxKeys: 1000,
        }),
      );

      const objects = (listed.Contents ?? [])
        .map((item) => item.Key)
        .filter((key): key is string => typeof key === 'string' && key.startsWith(prefix));

      for (let i = 0; i < objects.length; i += 1000) {
        const batch = objects.slice(i, i + 1000);
        if (!batch.length) continue;
        await this.s3.send(
          new DeleteObjectsCommand({
            Bucket: this.bucket,
            Delete: {
              Objects: batch.map((Key) => ({ Key })),
              Quiet: true,
            },
          }),
        );
        deleted += batch.length;
      }

      continuationToken = listed.IsTruncated ? listed.NextContinuationToken : undefined;
    } while (continuationToken);

    return { ok: true, skipped: false, deleted, prefix };
  }
}
