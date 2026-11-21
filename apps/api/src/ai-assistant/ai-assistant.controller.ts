import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Req,
  StreamableFile,
  Header,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FileInterceptor } from '@nestjs/platform-express';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { memoryStorage } from 'multer';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { ChatAiAssistantDto } from './dto/chat-ai-assistant.dto';
import { AiAssistantService } from './ai-assistant.service';
import { SupportReplyDto } from './dto/support-reply.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('ai')
export class AiAssistantController {
  constructor(private readonly ai: AiAssistantService) {}

  @Get('support/:ticketId')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO)
  @Header('Cache-Control', 'private, no-store')
  supportCase(@Req() req: Request, @Param('ticketId') ticketId: string) {
    return this.ai.supportCase(req.user as { id: string; role: Role; companyId?: string | null }, ticketId);
  }

  @Post('support/:ticketId/messages')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO)
  supportReply(@Req() req: Request, @Param('ticketId') ticketId: string, @Body() dto: SupportReplyDto) {
    return this.ai.supportCase(req.user as { id: string; role: Role; companyId?: string | null }, ticketId, dto);
  }

  @Get('resources/:resourceId')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO)
  @Header('Cache-Control', 'private, no-store')
  @Header('Vary', 'Authorization')
  @Header('X-Content-Type-Options', 'nosniff')
  async resource(@Req() req: Request, @Param('resourceId', new ParseUUIDPipe()) resourceId: string) {
    const file = await this.ai.libraryResource(req.user as { id: string; role: Role; companyId?: string | null }, resourceId);
    return new StreamableFile(file.bytes, { type: file.mimeType, disposition: 'attachment', length: file.bytes.length });
  }

  @Post('chat')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO)
  chat(@Req() req: Request, @Body() dto: ChatAiAssistantDto) {
    // `companyId` viene del JWT verificado: es la empresa activa del usuario, no un dato del cliente.
    const user = req.user as { id: string; role: Role; companyId?: string | null };
    return this.ai.chat(user, dto);
  }

  /**
   * Sube una imagen o un documento para que el asistente lo lea en el siguiente mensaje.
   *
   * El archivo va en memoria y se reenvía a APPYRA IA; no se guarda en FullPOS ni en el disco
   * del servidor.
   */
  @Post('attachments')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO)
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: { fileSize: 15 * 1024 * 1024 },
    }),
  )
  attachment(@UploadedFile() file?: Express.Multer.File) {
    if (!file || file.buffer === undefined || file.buffer.length === 0) {
      throw new BadRequestException('Adjunta un archivo.');
    }
    return this.ai.uploadAttachment({
      buffer: file.buffer,
      originalname: file.originalname ?? 'adjunto',
      mimetype: file.mimetype ?? 'application/octet-stream',
    });
  }
}
