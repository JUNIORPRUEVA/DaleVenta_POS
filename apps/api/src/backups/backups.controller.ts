import {
  Body,
  Controller,
  Delete,
  Get,
  Header,
  Param,
  Post,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { AuthGuard } from "@nestjs/passport";
import type { Request, Response } from "express";
import type { Express } from "express";
import { TenantUser } from "../auth/tenant-context";
import { CreateBackupDto } from "./dto/create-backup.dto";
import { BackupsService } from "./backups.service";
import { BackupsRestoreService } from "./backups-restore.service";

@Controller("backups")
@UseGuards(AuthGuard("jwt"))
export class BackupsController {
  constructor(
    private readonly backups: BackupsService,
    private readonly restoreService: BackupsRestoreService,
  ) {}

  @Post()
  create(@Req() req: Request, @Body() _dto: CreateBackupDto) {
    return this.backups.createManual(req.user as TenantUser);
  }

  @Get()
  list(@Req() req: Request) {
    return this.backups.list(req.user as TenantUser);
  }

  @Get("audit/inventory")
  auditInventory() {
    return this.backups.auditInventory();
  }

  @Post("validate-upload")
  @UseInterceptors(FileInterceptor("file", { limits: { fileSize: 100 * 1024 * 1024 } }))
  validateUpload(@Req() req: Request, @UploadedFile() file?: Express.Multer.File) {
    return this.backups.validateUploadedArchive(req.user as TenantUser, file?.buffer);
  }

  @Post("import")
  @UseInterceptors(FileInterceptor("file", { limits: { fileSize: 100 * 1024 * 1024 } }))
  import(@Req() req: Request, @UploadedFile() file?: Express.Multer.File) {
    return this.backups.importCanonicalArchive(req.user as TenantUser, file?.buffer);
  }

  @Post(":id/restore")
  restore(@Req() req: Request, @Param("id") id: string) {
    return this.restoreService.restore(req.user as TenantUser, id);
  }

  @Get(":id/download")
  @Header("Content-Type", "application/vnd.daleventas.backup+zip")
  async download(@Req() req: Request, @Param("id") id: string, @Res() res: Response) {
    const result = await this.backups.download(req.user as TenantUser, id);
    res.setHeader("Content-Disposition", `attachment; filename="${result.fileName}"`);
    res.setHeader("Content-Length", String(result.archive.length));
    res.send(result.archive);
  }

  @Delete(":id")
  remove(@Req() req: Request, @Param("id") id: string) {
    return this.backups.deleteManual(req.user as TenantUser, id);
  }
}
