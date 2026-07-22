import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Put,
  Query,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Request } from 'express';
import { memoryStorage } from 'multer';
import { randomUUID } from 'node:crypto';
import { extname, join, posix } from 'node:path';
import * as fs from 'node:fs';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { R2Service } from '../storage/r2.service';
import { sanitizeFileName } from '../storage/helpers/storage_helpers';
import { ContabilidadService } from './contabilidad.service';
import {
  BulkDeleteClosesDto,
  CloseFinancialSummaryQueryDto,
  CloseStatus,
  CreateCloseDto,
  DeleteCloseDto,
  ReviewCloseDto,
  ToggleCloseCashDepositDto,
  UpdateCloseDto,
} from './close.dto';
import {
  CreateDepositOrderDto,
  DepositOrdersQueryDto,
  ReviewDepositOrderDto,
  UpdateDepositOrderDto,
} from './deposit-order.dto';
import {
  CreateFiscalInvoiceDto,
  FiscalInvoicesQueryDto,
  UpdateFiscalInvoiceDto,
} from './fiscal-invoice.dto';
import {
  CreatePayableServiceDto,
  PayablePaymentsQueryDto,
  PayableServicesQueryDto,
  RegisterPayablePaymentDto,
  UpdatePayablePaymentDto,
  UpdatePayableServiceDto,
} from './payable.dto';

type RequestActor = { id?: string; role?: string };
const CLOSING_ROLES: Role[] = [
  Role.ADMIN,
  Role.ASISTENTE,
];
const DEPOSIT_ROLES: Role[] = [Role.ADMIN, Role.ASISTENTE];

@Controller('contabilidad')
@UseGuards(AuthGuard('jwt'), RolesGuard)
export class ContabilidadController {
  constructor(
    private readonly contabilidadService: ContabilidadService,
    private readonly r2: R2Service,
  ) {}

  @Post('closes')
  @Roles(...CLOSING_ROLES)
  async createClose(@Body() dto: CreateCloseDto, @Req() req: Request) {
    return this.contabilidadService.createClose(
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Get('closes')
  @Roles(...CLOSING_ROLES)
  async getCloses(
    @Req() req: Request,
    @Query('date') date?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('type') type?: string,
  ) {
    return this.contabilidadService.getCloses(
      { date, from, to, type },
      (req.user ?? {}) as RequestActor,
    );
  }

  @Get('closes/financial-summary')
  @Roles('ADMIN')
  async getFinancialSummary(
    @Query() query: CloseFinancialSummaryQueryDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.getCloseFinancialSummary(
      query,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Get('closes/:id')
  @Roles(...CLOSING_ROLES)
  async getCloseById(@Param('id') id: string, @Req() req: Request) {
    return this.contabilidadService.getCloseById(
      id,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Put('closes/:id')
  @Roles(Role.ADMIN)
  async updateClose(
    @Param('id') id: string,
    @Body() dto: UpdateCloseDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.updateClose(
      id,
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Delete('closes/:id')
  @Roles('ADMIN')
  async deleteClose(
    @Param('id') id: string,
    @Body() dto: DeleteCloseDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.deleteClose(
      id,
      dto.adminPassword,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Post('closes/delete-bulk')
  @Roles('ADMIN')
  async bulkDeleteCloses(
    @Body() dto: BulkDeleteClosesDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.deleteClosesBulk(
      dto.closeIds,
      dto.adminPassword,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Post('closes/:id/approve')
  @Roles(Role.ADMIN)
  async approveClose(
    @Param('id') id: string,
    @Req() req: Request,
    @Body() dto: ReviewCloseDto,
  ) {
    return this.contabilidadService.reviewCloseWithNote(
      id,
      CloseStatus.APPROVED,
      (req.user ?? {}) as RequestActor,
      dto.reviewNote,
    );
  }

  @Post('closes/:id/reject')
  @Roles(Role.ADMIN)
  async rejectClose(
    @Param('id') id: string,
    @Req() req: Request,
    @Body() dto: ReviewCloseDto,
  ) {
    return this.contabilidadService.reviewCloseWithNote(
      id,
      CloseStatus.REJECTED,
      (req.user ?? {}) as RequestActor,
      dto.reviewNote,
    );
  }

  @Post('closes/:id/ai-report')
  @Roles(Role.ADMIN)
  async aiReport(@Param('id') id: string, @Req() req: Request) {
    return this.contabilidadService.generateAiReport(
      id,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Patch('closes/:id/cash-deposit')
  @Roles(Role.ADMIN)
  async toggleCloseCashDeposit(
    @Param('id') id: string,
    @Body() dto: ToggleCloseCashDepositDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.toggleCloseCashDeposit(
      id,
      dto.cashDeposited,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Post('closes/vouchers/upload')
  @Roles(...CLOSING_ROLES)
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      fileFilter: (_req, file, cb) => {
        const isAllowed =
          /^image\/(png|jpe?g|webp)$/.test(file.mimetype) ||
          file.mimetype === 'application/pdf';
        if (!isAllowed) {
          return cb(
            new BadRequestException(
              'Solo se permiten vouchers en PNG/JPG/WEBP/PDF',
            ),
            false,
          );
        }
        cb(null, true);
      },
      limits: { fileSize: 10 * 1024 * 1024 },
    }),
  )
  async uploadClosingVoucher(
    @Req() req: Request,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!file?.buffer?.length) {
      throw new BadRequestException('No se pudo leer el voucher subido');
    }
    const actor = (req.user ?? {}) as RequestActor;
    const original = sanitizeFileName(file.originalname ?? 'voucher-cierre');
    const ext = extname(original).toLowerCase();
    const safeExt =
      ext && /\.(png|jpe?g|webp|pdf)$/.test(ext)
        ? ext
        : file.mimetype === 'application/pdf'
          ? '.pdf'
          : '.jpg';
    const contentType =
      /^image\/(png|jpe?g|webp)$/.test(file.mimetype) ||
      file.mimetype === 'application/pdf'
        ? file.mimetype
        : safeExt === '.png'
          ? 'image/png'
          : safeExt === '.webp'
            ? 'image/webp'
            : safeExt === '.pdf'
              ? 'application/pdf'
              : 'image/jpeg';
    const now = new Date();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    const baseName = original.replace(/\.[^/.]+$/, '') || 'voucher';
    const objectKey =
      `contabilidad/daily-close-vouchers/${now.getUTCFullYear()}/${month}/${actor.id ?? 'anon'}/${randomUUID()}-${baseName}${safeExt}`
        .replace(/\s+/g, '_')
        .replace(/[^a-zA-Z0-9/_\-.]/g, '');
    await this.r2.putObject({
      objectKey,
      body: file.buffer,
      contentType,
    });
    return {
      storageKey: objectKey,
      fileUrl: this.r2.buildPublicUrl(objectKey),
      fileName: original,
      mimeType: contentType,
    };
  }

  @Post('deposit-orders')
  @Roles(...DEPOSIT_ROLES)
  async createDepositOrder(
    @Body() dto: CreateDepositOrderDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.createDepositOrder(
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Get('deposit-orders')
  @Roles(...DEPOSIT_ROLES)
  async getDepositOrders(@Query() query: DepositOrdersQueryDto, @Req() req: Request) {
    const actor = (req.user ?? {}) as RequestActor;
    // Temporary diagnostics for persistent 500 on deposit list.
    // eslint-disable-next-line no-console
    console.log('[deposit-orders][controller] GET /contabilidad/deposit-orders', {
      actorId: actor.id ?? null,
      actorRole: actor.role ?? null,
      queryParams: req.query ?? {},
      from: query.from ?? null,
      to: query.to ?? null,
      status: query.status ?? null,
    });
    try {
      return await this.contabilidadService.getDepositOrders(
        query,
        actor,
      );
    } catch (error: unknown) {
      const err = error as {
        name?: unknown;
        message?: unknown;
        code?: unknown;
        meta?: unknown;
        stack?: unknown;
      };
      // eslint-disable-next-line no-console
      console.error('[deposit-orders][controller] ERROR GET /contabilidad/deposit-orders', {
        actorId: actor.id ?? null,
        actorRole: actor.role ?? null,
        queryParams: req.query ?? {},
        from: query.from ?? null,
        to: query.to ?? null,
        status: query.status ?? null,
        errorName: err?.name,
        errorMessage: err?.message,
        errorCode: err?.code,
        errorMeta: err?.meta,
        errorStack: err?.stack,
      });
      throw error;
    }
  }

  @Get('deposit-orders/:id')
  @Roles(...DEPOSIT_ROLES)
  async getDepositOrderById(@Param('id') id: string, @Req() req: Request) {
    return this.contabilidadService.getDepositOrderById(
      id,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Put('deposit-orders/:id')
  @Roles('ADMIN')
  async updateDepositOrder(
    @Param('id') id: string,
    @Body() dto: UpdateDepositOrderDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.updateDepositOrder(
      id,
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Post('deposit-orders/:id/approve')
  @Roles(Role.ADMIN)
  async approveDepositOrder(
    @Param('id') id: string,
    @Body() dto: ReviewDepositOrderDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.approveDepositOrder(
      id,
      dto.reviewNote,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Post('deposit-orders/:id/cancel')
  @Roles(Role.ADMIN)
  async cancelDepositOrder(
    @Param('id') id: string,
    @Body() dto: ReviewDepositOrderDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.cancelDepositOrder(
      id,
      dto.reviewNote,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Delete('deposit-orders/:id')
  @Roles('ADMIN')
  async deleteDepositOrder(@Param('id') id: string, @Req() req: Request) {
    return this.contabilidadService.deleteDepositOrder(
      id,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Post('deposit-orders/:id/voucher')
  @Roles(...DEPOSIT_ROLES)
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      fileFilter: (_req, file, cb) => {
        const isAllowed =
          /^image\/(png|jpe?g|webp)$/.test(file.mimetype) ||
          file.mimetype === 'application/pdf';
        if (!isAllowed) {
          return cb(
            new BadRequestException(
              'Solo se permiten voucher en PNG/JPG/WEBP/PDF',
            ),
            false,
          );
        }
        cb(null, true);
      },
      limits: { fileSize: 10 * 1024 * 1024 },
    }),
  )
  async uploadDepositVoucher(
    @Param('id') id: string,
    @Req() req: Request,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!file) throw new BadRequestException('No se subió ningún voucher');
    if (!file.buffer?.length) {
      throw new BadRequestException('No se pudo leer el voucher subido');
    }

    const original = sanitizeFileName(file.originalname ?? 'voucher-deposito');
    const ext = extname(original).toLowerCase();
    const safeExt =
      ext && /\.(png|jpe?g|webp|pdf)$/.test(ext)
        ? ext
        : file.mimetype === 'application/pdf'
          ? '.pdf'
          : '.jpg';
    const contentType =
      /^image\/(png|jpe?g|webp)$/.test(file.mimetype) ||
      file.mimetype === 'application/pdf'
        ? file.mimetype
        : safeExt === '.png'
          ? 'image/png'
          : safeExt === '.webp'
            ? 'image/webp'
            : safeExt === '.pdf'
              ? 'application/pdf'
              : 'image/jpeg';

    const actor = (req.user ?? {}) as RequestActor;
    const ownerSegment = (actor.id ?? 'anon').trim() || 'anon';
    const now = new Date();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    const baseName = original.replace(/\.[^/.]+$/, '') || 'voucher';
    const objectKey =
      `contabilidad/deposit-orders/${now.getUTCFullYear()}/${month}/${ownerSegment}/${randomUUID()}-${baseName}${safeExt}`
        .replace(/\s+/g, '_')
        .replace(/[^a-zA-Z0-9/_\-.]/g, '');

    const uploadDirEnv = (process.env['UPLOAD_DIR'] ?? '').trim();
    const volumeDir = '/uploads';
    const volumeExists = fs.existsSync(volumeDir);
    const uploadDir =
      uploadDirEnv.length > 0
        ? (uploadDirEnv === './uploads' || uploadDirEnv === 'uploads') &&
          volumeExists
          ? volumeDir
          : uploadDirEnv
        : volumeExists
          ? volumeDir
          : join(process.cwd(), 'uploads');

    const relativePath = `/${posix.join('uploads', objectKey)}`;
    const segments = objectKey.split('/');
    const absoluteFilePath = join(uploadDir, ...segments);
    const absoluteDir = join(uploadDir, ...segments.slice(0, -1));

    fs.mkdirSync(absoluteDir, { recursive: true });
    fs.writeFileSync(absoluteFilePath, file.buffer);

    const host = (req.get('host') ?? '').trim();
    const protocol = (req.protocol ?? 'https').trim();
    const url = host ? `${protocol}://${host}${relativePath}` : relativePath;

    try {
      await this.r2.putObject({
        objectKey: `uploads/${objectKey}`,
        body: file.buffer,
        contentType,
      });
    } catch (r2Err) {
      // eslint-disable-next-line no-console
      console.warn(
        '[deposit-orders/voucher] R2 mirror failed, local file is used:',
        r2Err,
      );
    }

    return this.contabilidadService.attachDepositOrderVoucher(
      id,
      {
        voucherUrl: url,
        voucherFileName: original,
        voucherMimeType: contentType,
      },
      actor,
    );
  }

  @Post('fiscal-invoices/upload')
  @Roles('ADMIN', 'ASISTENTE')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      fileFilter: (_req, file, cb) => {
        const isAllowed =
          /^image\/(png|jpe?g|webp)$/.test(file.mimetype) ||
          file.mimetype === 'application/pdf';
        if (!isAllowed) {
          return cb(
            new BadRequestException('Solo se permiten imágenes PNG/JPG/WEBP o PDF'),
            false,
          );
        }
        cb(null, true);
      },
      limits: { fileSize: 15 * 1024 * 1024 },
    }),
  )
  async uploadFiscalInvoiceImage(
    @Req() req: Request,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!file) throw new BadRequestException('No se subió ningún archivo');
    if (!file.buffer?.length) {
      throw new BadRequestException('No se pudo leer la imagen subida');
    }

    const original = sanitizeFileName(file.originalname ?? 'factura');
    const ext = extname(original).toLowerCase();
    const safeExt = ext && /\.(png|jpe?g|webp|pdf)$/.test(ext)
      ? ext
      : file.mimetype === 'application/pdf'
        ? '.pdf'
        : '.jpg';
    const contentType = file.mimetype === 'application/pdf'
      ? 'application/pdf'
      : /^image\/(png|jpe?g|webp)$/.test(file.mimetype)
      ? file.mimetype
      : safeExt === '.png'
        ? 'image/png'
        : safeExt === '.webp'
          ? 'image/webp'
          : 'image/jpeg';

    const actor = (req.user ?? {}) as RequestActor;
    const ownerSegment = (actor.id ?? 'anon').trim() || 'anon';
    const now = new Date();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    const baseName = original.replace(/\.[^/.]+$/, '') || 'factura';
    const objectKey =
      `contabilidad/fiscal-invoices/${now.getUTCFullYear()}/${month}/${ownerSegment}/${randomUUID()}-${baseName}${safeExt}`
        .replace(/\s+/g, '_')
        .replace(/[^a-zA-Z0-9/_\-.]/g, '');

    // Resolve local upload directory (same logic as main.ts / StorageController).
    const uploadDirEnv = (process.env['UPLOAD_DIR'] ?? '').trim();
    const volumeDir = '/uploads';
    const volumeExists = fs.existsSync(volumeDir);
    const uploadDir =
      uploadDirEnv.length > 0
        ? (uploadDirEnv === './uploads' || uploadDirEnv === 'uploads') &&
          volumeExists
          ? volumeDir
          : uploadDirEnv
        : volumeExists
          ? volumeDir
          : join(process.cwd(), 'uploads');

    const relativePath = `/${posix.join('uploads', objectKey)}`;
    const segments = objectKey.split('/');
    const absoluteFilePath = join(uploadDir, ...segments);
    const absoluteDir = join(uploadDir, ...segments.slice(0, -1));

    fs.mkdirSync(absoluteDir, { recursive: true });
    fs.writeFileSync(absoluteFilePath, file.buffer);

    // Build a full absolute URL the Flutter app can reach.
    const host = (req.get('host') ?? '').trim();
    const protocol = (req.protocol ?? 'https').trim();
    const url = host ? `${protocol}://${host}${relativePath}` : relativePath;

    // Optional R2 mirror — failure is non-fatal.
    try {
      await this.r2.putObject({
        objectKey: `uploads/${objectKey}`,
        body: file.buffer,
        contentType,
      });
    } catch (r2Err) {
      // eslint-disable-next-line no-console
      console.warn(
        '[fiscal-invoices/upload] R2 mirror failed, local file is used:',
        r2Err,
      );
    }

    return {
      fileName: original,
      objectKey,
      url,
    };
  }

  @Post('fiscal-invoices')
  @Roles('ADMIN', 'ASISTENTE')
  async createFiscalInvoice(
    @Body() dto: CreateFiscalInvoiceDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.createFiscalInvoice(
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Get('fiscal-invoices')
  @Roles('ADMIN', 'ASISTENTE')
  async getFiscalInvoices(@Query() query: FiscalInvoicesQueryDto) {
    return this.contabilidadService.getFiscalInvoices(query);
  }

  @Put('fiscal-invoices/:id')
  @Roles('ADMIN', 'ASISTENTE')
  async updateFiscalInvoice(
    @Param('id') id: string,
    @Body() dto: UpdateFiscalInvoiceDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.updateFiscalInvoice(
      id,
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Delete('fiscal-invoices/:id')
  @Roles('ADMIN', 'ASISTENTE')
  async deleteFiscalInvoice(@Param('id') id: string, @Req() req: Request) {
    return this.contabilidadService.deleteFiscalInvoice(
      id,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Post('payables/services')
  @Roles('ADMIN', 'ASISTENTE')
  async createPayableService(
    @Body() dto: CreatePayableServiceDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.createPayableService(
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Get('payables/services')
  @Roles('ADMIN', 'ASISTENTE')
  async getPayableServices(@Query() query: PayableServicesQueryDto) {
    return this.contabilidadService.getPayableServices(query);
  }

  @Put('payables/services/:id')
  @Roles('ADMIN', 'ASISTENTE')
  async updatePayableService(
    @Param('id') id: string,
    @Body() dto: UpdatePayableServiceDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.updatePayableService(
      id,
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Post('payables/services/:id/payments')
  @Roles('ADMIN', 'ASISTENTE')
  async registerPayablePayment(
    @Param('id') id: string,
    @Body() dto: RegisterPayablePaymentDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.registerPayablePayment(
      id,
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Get('payables/payments')
  @Roles('ADMIN', 'ASISTENTE')
  async getPayablePayments(@Query() query: PayablePaymentsQueryDto) {
    return this.contabilidadService.getPayablePayments(query);
  }

  @Delete('payables/services/:id')
  @Roles('ADMIN')
  async deletePayableService(@Param('id') id: string, @Req() req: Request) {
    return this.contabilidadService.deletePayableService(
      id,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Delete('payables/payments/:id')
  @Roles('ADMIN')
  async deletePayablePayment(@Param('id') id: string, @Req() req: Request) {
    return this.contabilidadService.deletePayablePayment(
      id,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Put('payables/payments/:id')
  @Roles('ADMIN')
  async updatePayablePayment(
    @Param('id') id: string,
    @Body() dto: UpdatePayablePaymentDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.updatePayablePayment(
      id,
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }
}
