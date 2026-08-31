import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  Delete,
  Get,
  Header,
  Param,
  Patch,
  Post,
  Query,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { AuthGuard } from "@nestjs/passport";
import { Role } from "@prisma/client";
import { memoryStorage } from "multer";
import { extname, join, posix } from "node:path";
import type { Express, Request, Response } from "express";
import { Permissions, Roles } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import { requireTenant, type TenantUser } from "../auth/tenant-context";
import { AdjustProductStockDto } from "./dto/adjust-product-stock.dto";
import { CreateProductDto } from "./dto/create-product.dto";
import { UpdateProductDto } from "./dto/update-product.dto";
import { ImportProductImageUrlDto } from "./dto/import-product-image-url.dto";
import { ProductCostInterceptor } from "./product-cost.interceptor";
import { ProductsService } from "./products.service";
import { FileInterceptor } from "@nestjs/platform-express";
import * as fs from "node:fs";
import { R2Service } from "../storage/r2.service";
import {
  buildTenantObjectKey,
  sanitizeFileName,
} from "../storage/helpers/storage_helpers";
import sharp from "sharp";

@UseInterceptors(ProductCostInterceptor)
@Controller("products")
export class ProductsController {
  private readonly uploadDir: string;
  private readonly publicBaseUrl: string;
  private readonly fullposBaseUrl: string;

  private resolveUploadDir(config: ConfigService): string {
    const fromEnv = (config.get<string>("UPLOAD_DIR") ?? "").trim();
    const volumeDir = "/uploads";
    const volumeExists = fs.existsSync(volumeDir);

    if (fromEnv.length > 0) {
      if ((fromEnv == "./uploads" || fromEnv == "uploads") && volumeExists) {
        return volumeDir;
      }
      return fromEnv;
    }

    if (volumeExists) return volumeDir;
    return join(process.cwd(), "uploads");
  }

  constructor(
    private readonly products: ProductsService,
    private readonly r2: R2Service,
    config: ConfigService,
  ) {
    const dir = this.resolveUploadDir(config);
    this.uploadDir = dir.trim();
    const base =
      config.get<string>("PUBLIC_BASE_URL") ??
      config.get<string>("API_BASE_URL") ??
      "";
    this.publicBaseUrl = this.normalizePublicBaseUrl(base);
    this.fullposBaseUrl = (
      config.get<string>("FULLPOS_INTEGRATION_BASE_URL") ?? ""
    )
      .trim()
      .replace(/\/$/, "");
    fs.mkdirSync(this.uploadDir, { recursive: true });
  }

  @UseGuards(AuthGuard("jwt"))
  @Header(
    "Cache-Control",
    "no-store, no-cache, must-revalidate, proxy-revalidate",
  )
  @Header("Pragma", "no-cache")
  @Header("Expires", "0")
  @Header("Surrogate-Control", "no-store")
  @Get()
  findAll(@Req() req: Request) {
    return this.products.findAll(req.user as TenantUser);
  }

  @UseGuards(AuthGuard("jwt"))
  @Header(
    "Cache-Control",
    "no-store, no-cache, must-revalidate, proxy-revalidate",
  )
  @Header("Pragma", "no-cache")
  @Header("Expires", "0")
  @Header("Surrogate-Control", "no-store")
  @Get("source")
  source(@Req() req: Request) {
    return this.products.sourceInfo(req.user as TenantUser);
  }

  @Header(
    "Cache-Control",
    "no-store, no-cache, must-revalidate, proxy-revalidate",
  )
  @Header("Pragma", "no-cache")
  @Header("Expires", "0")
  @Header("Surrogate-Control", "no-store")
  @UseGuards(AuthGuard("jwt"))
  @Get("unit-of-measures")
  unitOfMeasures(@Req() req: Request) {
    return this.products.listUnitOfMeasures(req.user as TenantUser);
  }

  @Header(
    "Cache-Control",
    "no-store, no-cache, must-revalidate, proxy-revalidate",
  )
  @Header("Pragma", "no-cache")
  @Header("Expires", "0")
  @Header("Surrogate-Control", "no-store")
  @Get("image-proxy")
  async imageProxy(
    @Query("url") rawUrl: string | undefined,
    @Res() res: Response,
  ) {
    const url = (rawUrl ?? "").trim();
    if (!url) {
      throw new BadRequestException("url es requerido");
    }

    let parsedUrl: URL;
    try {
      parsedUrl = new URL(url);
    } catch {
      throw new BadRequestException("url inválida");
    }

    if (!this.fullposBaseUrl) {
      throw new BadRequestException(
        "image-proxy solo está disponible para imágenes heredadas de FullPOS",
      );
    }

    let fullposUrl: URL;
    try {
      fullposUrl = new URL(this.fullposBaseUrl);
    } catch {
      throw new BadRequestException("Origen FullPOS inválido");
    }

    const sameFullposHost =
      parsedUrl.host.toLowerCase() == fullposUrl.host.toLowerCase();
    if (!sameFullposHost) {
      throw new BadRequestException(
        "Solo se permiten imágenes del host de FULLPOS",
      );
    }

    const upstream = await fetch(parsedUrl.toString(), {
      headers: { Accept: "image/*,*/*;q=0.8" },
    });

    if (!upstream.ok) {
      const text = await upstream.text().catch(() => "");
      res.status(upstream.status).send(text);
      return;
    }

    const contentType =
      upstream.headers.get("content-type") ?? "application/octet-stream";
    if (!contentType.toLowerCase().startsWith("image/")) {
      res.status(415).send("El recurso remoto no es una imagen");
      return;
    }
    const contentLength = upstream.headers.get("content-length");
    const body = Buffer.from(await upstream.arrayBuffer());

    res.setHeader("Content-Type", contentType);
    if (contentLength) {
      res.setHeader("Content-Length", contentLength);
    }
    res.setHeader("Cache-Control", "public, max-age=3600");
    // eslint-disable-next-line no-console
    console.log(`[media] FullPOS external proxy used host=${parsedUrl.host}`);
    res.send(body);
  }

  @UseGuards(AuthGuard("jwt"))
  @Header(
    "Cache-Control",
    "no-store, no-cache, must-revalidate, proxy-revalidate",
  )
  @Header("Pragma", "no-cache")
  @Header("Expires", "0")
  @Header("Surrogate-Control", "no-store")
  @Get(":id")
  findOne(@Req() req: Request, @Param("id") id: string) {
    return this.products.findOne(req.user as TenantUser, id);
  }

  @UseGuards(AuthGuard("jwt"), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Permissions("editProducts")
  @Post()
  create(@Req() req: Request, @Body() dto: CreateProductDto) {
    return this.products.create(req.user as TenantUser, dto);
  }

  @UseGuards(AuthGuard("jwt"), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Permissions("editProducts")
  @Post("upload")
  @UseInterceptors(
    FileInterceptor("file", {
      storage: memoryStorage(),
      fileFilter: (
        _req: Express.Request,
        file: Express.Multer.File,
        cb: (error: Error | null, acceptFile: boolean) => void,
      ) => {
        const original = sanitizeFileName(file.originalname ?? "");
        const ext = extname(original).toLowerCase();
        const mime = (file.mimetype ?? "").toLowerCase();
        const isImage =
          /^image\/(png|jpe?g|webp)$/.test(mime) ||
          ((mime === "application/octet-stream" || mime === "") &&
            /\.(png|jpe?g|webp)$/.test(ext));
        if (!isImage)
          return cb(
            new BadRequestException("Solo se permiten imágenes PNG/JPG/WEBP"),
            false,
          );
        cb(null, true);
      },
      limits: { fileSize: 15 * 1024 * 1024 },
    }),
  )
  async upload(
    @Req() req: Request,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (await this.products.isReadOnly(req.user as TenantUser)) {
      throw new ConflictException(
        "Productos en modo solo-lectura: no se permite subir imágenes aquí.",
      );
    }
    if (!file) throw new BadRequestException("No se subió ningún archivo");
    if (!file.buffer?.length) {
      throw new BadRequestException("No se pudo leer la imagen subida");
    }

    const original = sanitizeFileName(file.originalname ?? "producto");
    const ext = extname(original).toLowerCase();
    const safeExt = ext && /\.(png|jpe?g|webp)$/.test(ext) ? ext : ".jpg";
    const contentType = /^image\/(png|jpe?g|webp)$/.test(file.mimetype)
      ? file.mimetype
      : safeExt === ".png"
        ? "image/png"
        : safeExt === ".webp"
          ? "image/webp"
          : "image/jpeg";
    const optimized = await this.prepareProductImageBuffer(
      file.buffer,
      contentType,
    );
    return this.saveProductImage(req.user as TenantUser, optimized.buffer, {
      original,
      safeExt,
      contentType: optimized.contentType,
      source: "upload",
    });
  }

  @UseGuards(AuthGuard("jwt"), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Permissions("editProducts")
  @Post("import-image-url")
  async importImageUrl(
    @Req() req: Request,
    @Body() dto: ImportProductImageUrlDto,
  ) {
    if (await this.products.isReadOnly(req.user as TenantUser)) {
      throw new ConflictException(
        "Productos en modo solo-lectura: no se permite subir imágenes aquí.",
      );
    }
    const remoteUrl = dto.url.trim();
    let parsedUrl: URL;
    try {
      parsedUrl = new URL(remoteUrl);
    } catch {
      throw new BadRequestException("URL de imagen inválida");
    }
    if (!/^https?:$/i.test(parsedUrl.protocol)) {
      throw new BadRequestException("Solo se permiten URLs http o https");
    }

    const upstream = await fetch(parsedUrl.toString(), {
      headers: {
        Accept: "image/png,image/jpeg,image/webp,image/*;q=0.8,*/*;q=0.2",
      },
      redirect: "follow",
    });
    if (!upstream.ok) {
      throw new BadRequestException(
        `No se pudo descargar la imagen remota (${upstream.status})`,
      );
    }

    const contentType = (upstream.headers.get("content-type") ?? "")
      .split(";")[0]
      .trim()
      .toLowerCase();
    if (!/^image\/(png|jpe?g|webp)$/.test(contentType)) {
      throw new BadRequestException(
        "La URL no devuelve una imagen PNG/JPG/WEBP válida",
      );
    }
    const body = Buffer.from(await upstream.arrayBuffer());
    if (!body.length) {
      throw new BadRequestException("La imagen remota está vacía");
    }
    if (body.length > 15 * 1024 * 1024) {
      throw new BadRequestException(
        "La imagen remota excede el límite permitido de 15 MB",
      );
    }

    const extFromType = contentType.includes("png")
      ? ".png"
      : contentType.includes("webp")
        ? ".webp"
        : ".jpg";
    const baseName = sanitizeFileName(
      dto.productName?.trim() ||
        parsedUrl.pathname.split("/").pop() ||
        "producto",
    );
    const original = `${baseName.replace(/\.(png|jpe?g|webp)$/i, "")}${extFromType}`;

    const optimized = await this.prepareProductImageBuffer(body, contentType);
    return this.saveProductImage(req.user as TenantUser, optimized.buffer, {
      original,
      safeExt: extFromType,
      contentType: optimized.contentType,
      source: "import-url",
    });
  }

  private async prepareProductImageBuffer(buffer: Buffer, contentType: string) {
    try {
      const normalizedType = contentType.toLowerCase();
      const pipeline = sharp(buffer, { failOn: "none" }).rotate().resize({
        width: 1600,
        height: 1600,
        fit: "inside",
        withoutEnlargement: true,
      });

      if (normalizedType == "image/png") {
        return {
          buffer: await pipeline.png({ compressionLevel: 8 }).toBuffer(),
          contentType: "image/png",
        };
      }

      if (normalizedType == "image/webp") {
        return {
          buffer: await pipeline.webp({ quality: 84, effort: 4 }).toBuffer(),
          contentType: "image/webp",
        };
      }

      return {
        buffer: await pipeline.jpeg({ quality: 86, mozjpeg: true }).toBuffer(),
        contentType: "image/jpeg",
      };
    } catch (error) {
      console.warn(
        "[products/image] optimization failed; storing original image",
        error,
      );
      return { buffer, contentType };
    }
  }

  private async saveProductImage(
    user: TenantUser,
    buffer: Buffer,
    options: {
      original: string;
      safeExt: string;
      contentType: string;
      source: string;
    },
  ) {
    const companyId = requireTenant(user);
    const original = sanitizeFileName(options.original || "producto");
    const objectKey = buildTenantObjectKey({
      companyId,
      area: "products",
      kind: "images",
      ownerId: user.id,
      fileName: original,
      extension: options.safeExt,
    });

    const r2Key = `uploads/${objectKey}`;

    try {
      await this.r2.putObject({
        objectKey: r2Key,
        body: buffer,
        contentType: options.contentType,
      });
      const url = this.buildMediaObjectUrl(r2Key);
      // eslint-disable-next-line no-console
      console.log(
        `[products/${options.source}] R2 upload successful bucket=daleventa-media companyId=${companyId} key=${r2Key}`,
      );
      // eslint-disable-next-line no-console
      console.log(`[R2] PutObject successful key=${r2Key}`);
      return {
        filename: original,
        originalFileName: original,
        storageProvider: "r2",
        key: r2Key,
        objectKey: r2Key,
        path: url,
        url,
        mimeType: options.contentType,
        companyId,
      };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.warn(
        `[products/${options.source}] R2 upload failed fallback=local`,
        error,
      );
    }

    const absoluteFilePath = join(this.uploadDir, ...objectKey.split("/"));
    const absoluteDir = join(
      this.uploadDir,
      ...objectKey.split("/").slice(0, -1),
    );
    fs.mkdirSync(absoluteDir, { recursive: true });
    fs.writeFileSync(absoluteFilePath, buffer);

    const relativePath = `/${posix.join("uploads", objectKey)}`;
    const baseUrl = this.publicBaseUrl;
    const url = baseUrl ? `${baseUrl}${relativePath}` : relativePath;
    // eslint-disable-next-line no-console
    console.warn(
      `[products/${options.source}] legacy local fallback used file=${absoluteFilePath} path=${relativePath}`,
    );
    return {
      filename: original,
      originalFileName: original,
      storageProvider: "local",
      objectKey: r2Key,
      path: relativePath,
      url,
      mimeType: options.contentType,
      companyId,
    };
  }

  private buildMediaObjectUrl(objectKey: string) {
    const path = `/media/object?key=${encodeURIComponent(objectKey)}`;
    return this.publicBaseUrl ? `${this.publicBaseUrl}${path}` : path;
  }

  private normalizePublicBaseUrl(raw: string) {
    const value = raw.trim().replace(/\/$/, "");
    if (!value) return "";
    if (value.includes(" ") || value.includes('"') || value.includes("'")) {
      console.warn(
        "[config] PUBLIC_BASE_URL/API_BASE_URL contiene caracteres inválidos; no se usará para media",
      );
      return "";
    }
    if (/localhost|31\.97\.99\.70/i.test(value)) {
      console.warn(
        "[config] PUBLIC_BASE_URL/API_BASE_URL apunta a localhost/IP antigua; no se usará para media",
      );
      return "";
    }
    if (
      process.env.NODE_ENV === "production" &&
      !value.startsWith("https://")
    ) {
      console.warn(
        "[config] PUBLIC_BASE_URL/API_BASE_URL debe usar https:// en producción; no se usará para media",
      );
      return "";
    }
    return value;
  }

  @UseGuards(AuthGuard("jwt"), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Permissions("addStock")
  @Patch(":id/stock")
  adjustStock(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: AdjustProductStockDto,
  ) {
    return this.products.adjustStock(req.user as TenantUser, id, dto);
  }

  @UseGuards(AuthGuard("jwt"), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Permissions("editProducts")
  @Patch(":id")
  update(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: UpdateProductDto,
  ) {
    return this.products.update(req.user as TenantUser, id, dto);
  }

  @UseGuards(AuthGuard("jwt"), RolesGuard)
  @Roles(Role.ADMIN)
  @Permissions("editProducts")
  @Delete("debug/purge")
  purgeAllForDebug(@Req() req: Request) {
    return this.products.purgeAllForDebug(req.user as TenantUser);
  }

  @UseGuards(AuthGuard("jwt"), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Permissions("editProducts")
  @Delete(":id")
  remove(@Req() req: Request, @Param("id") id: string) {
    return this.products.remove(req.user as TenantUser, id);
  }
}
