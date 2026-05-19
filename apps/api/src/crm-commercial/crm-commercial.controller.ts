import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { CrmCommercialService } from './crm-commercial.service';
import { ChangeCrmCommercialStatusDto } from './dto/change-crm-commercial-status.dto';
import { CreateCrmCommercialActivityDto } from './dto/create-crm-commercial-activity.dto';
import { CreateCrmCommercialCustomerDto } from './dto/create-crm-commercial-customer.dto';
import { CreateCrmCommercialNoteDto } from './dto/create-crm-commercial-note.dto';
import { CrmCommercialQueryDto } from './dto/crm-commercial-query.dto';
import { UpdateCrmCommercialCustomerDto } from './dto/update-crm-commercial-customer.dto';
import { CreateCrmCommercialFollowupTaskDto } from './dto/create-crm-commercial-followup-task.dto';
import { UpdateCrmCommercialFollowupTaskDto } from './dto/update-crm-commercial-followup-task.dto';
import { CrmCommercialFollowupTaskQueryDto } from './dto/crm-commercial-followup-task-query.dto';
import { UpdateCrmCommercialSettingsDto } from './dto/update-crm-commercial-settings.dto';
import { SendCrmCommercialMessageDto } from './dto/send-crm-commercial-message.dto';
import { SuggestCrmCommercialOrthographyDto } from './dto/suggest-crm-commercial-orthography.dto';
import { SuggestCrmCommercialReplyDto } from './dto/suggest-crm-commercial-reply.dto';
import {
  SendCrmCommercialMediaMessageDto,
  StartCrmCommercialMediaMessageDto,
  ReplyCrmCommercialMediaMessageDto,
} from './dto/send-crm-commercial-media-message.dto';
import {
  CreateCrmCommercialLibraryItemDto,
  CrmCommercialLibraryItemQueryDto,
  UpdateCrmCommercialLibraryItemDto,
} from './dto/crm-commercial-library-item.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('crm-commercial')
export class CrmCommercialController {
  constructor(private readonly crmCommercial: CrmCommercialService) {}

  private userOrThrow(req: Request) {
    const user = req.user as { id?: string; role?: Role } | undefined;
    if (!user?.id || !user.role) {
      throw new UnauthorizedException('Usuario no autenticado');
    }
    return { id: user.id, role: user.role };
  }

  @Get('settings')
  @Roles(Role.ADMIN)
  getSettings(@Req() req: Request) {
    return this.crmCommercial.getSettings(this.userOrThrow(req));
  }

  @Patch('settings')
  @Roles(Role.ADMIN)
  updateSettings(
    @Req() req: Request,
    @Body() dto: UpdateCrmCommercialSettingsDto,
  ) {
    return this.crmCommercial.updateSettings(this.userOrThrow(req), dto);
  }

  @Get('available-whatsapp-instances')
  @Roles(Role.ADMIN)
  getAvailableWhatsappInstances(@Req() req: Request) {
    return this.crmCommercial.getAvailableWhatsappInstances(this.userOrThrow(req));
  }

  @Get('conversations')
  @Roles(Role.ADMIN)
  getConversations(
    @Req() req: Request,
    @Query('limit') limit?: string,
    @Query('updatedAfter') updatedAfter?: string,
  ) {
    return this.crmCommercial.getConversations(this.userOrThrow(req), {
      limit,
      updatedAfter,
    });
  }

  @Get('conversations/:id/messages')
  @Roles(Role.ADMIN)
  getConversationMessages(
    @Req() req: Request,
    @Param('id') id: string,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
    @Query('after') after?: string,
  ) {
    return this.crmCommercial.getConversationMessages(this.userOrThrow(req), id, {
      limit,
      before,
      after,
    });
  }

  @Post('conversations/start-message')
  @Roles(Role.ADMIN)
  startConversationMessage(
    @Req() req: Request,
    @Body() dto: SendCrmCommercialMessageDto,
  ) {
    return this.crmCommercial.startConversationMessage(this.userOrThrow(req), dto);
  }

  @Post('conversations/:id/reply')
  @Roles(Role.ADMIN)
  replyConversation(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: SendCrmCommercialMessageDto,
  ) {
    return this.crmCommercial.replyConversation(
      this.userOrThrow(req),
      id,
      dto,
    );
  }

  @Post('ai/orthography-suggestion')
  @Roles(Role.ADMIN)
  suggestOrthography(
    @Req() req: Request,
    @Body() dto: SuggestCrmCommercialOrthographyDto,
  ) {
    return this.crmCommercial.suggestOrthography(this.userOrThrow(req), dto);
  }

  @Post('ai/suggest-reply')
  @Roles(Role.ADMIN)
  suggestReply(
    @Req() req: Request,
    @Body() dto: SuggestCrmCommercialReplyDto,
  ) {
    return this.crmCommercial.suggestReply(this.userOrThrow(req), dto);
  }

  @Post('conversations/:id/reply-media')
  @Roles(Role.ADMIN)
  replyConversationMedia(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: ReplyCrmCommercialMediaMessageDto,
  ) {
    return this.crmCommercial.replyConversationMedia(
      this.userOrThrow(req),
      id,
      dto,
    );
  }

  @Delete('conversations/:conversationId/messages/:messageId')
  @Roles(Role.ADMIN)
  deleteConversationMessage(
    @Req() req: Request,
    @Param('conversationId') conversationId: string,
    @Param('messageId') messageId: string,
  ) {
    return this.crmCommercial.deleteConversationMessage(
      this.userOrThrow(req),
      conversationId,
      messageId,
    );
  }

  @Post('conversations/start-media')
  @Roles(Role.ADMIN)
  startConversationMediaMessage(
    @Req() req: Request,
    @Body() dto: StartCrmCommercialMediaMessageDto,
  ) {
    return this.crmCommercial.startConversationMediaMessage(
      this.userOrThrow(req),
      dto,
    );
  }

  @Get('library')
  @Roles(Role.ADMIN)
  listLibrary(
    @Req() req: Request,
    @Query() query: CrmCommercialLibraryItemQueryDto,
  ) {
    return this.crmCommercial.listLibrary(this.userOrThrow(req), query);
  }

  @Post('library')
  @Roles(Role.ADMIN)
  createLibraryItem(
    @Req() req: Request,
    @Body() dto: CreateCrmCommercialLibraryItemDto,
  ) {
    return this.crmCommercial.createLibraryItem(this.userOrThrow(req), dto);
  }

  @Patch('library/:id')
  @Roles(Role.ADMIN)
  updateLibraryItem(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: UpdateCrmCommercialLibraryItemDto,
  ) {
    return this.crmCommercial.updateLibraryItem(this.userOrThrow(req), id, dto);
  }

  @Post('library/:id/use')
  @Roles(Role.ADMIN)
  useLibraryItem(@Req() req: Request, @Param('id') id: string) {
    return this.crmCommercial.useLibraryItem(this.userOrThrow(req), id);
  }

  @Delete('library/:id')
  @Roles(Role.ADMIN)
  deleteLibraryItem(@Req() req: Request, @Param('id') id: string) {
    return this.crmCommercial.deleteLibraryItem(this.userOrThrow(req), id);
  }

  // Phase 1: Customers

  @Post('customers')
  @Roles(Role.ADMIN)
  create(@Req() req: Request, @Body() dto: CreateCrmCommercialCustomerDto) {
    return this.crmCommercial.create(this.userOrThrow(req), dto);
  }

  @Get('customers')
  @Roles(Role.ADMIN)
  findAll(@Req() req: Request, @Query() query: CrmCommercialQueryDto) {
    return this.crmCommercial.findAll(this.userOrThrow(req), query);
  }

  @Get('customers/:id')
  @Roles(Role.ADMIN)
  findOne(@Req() req: Request, @Param('id') id: string) {
    return this.crmCommercial.findOne(this.userOrThrow(req), id);
  }

  @Patch('customers/:id')
  @Roles(Role.ADMIN)
  update(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: UpdateCrmCommercialCustomerDto,
  ) {
    return this.crmCommercial.update(this.userOrThrow(req), id, dto);
  }

  @Patch('customers/:id/status')
  @Roles(Role.ADMIN)
  changeStatus(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: ChangeCrmCommercialStatusDto,
  ) {
    return this.crmCommercial.changeStatus(this.userOrThrow(req), id, dto);
  }

  @Post('customers/:id/notes')
  @Roles(Role.ADMIN)
  addNote(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: CreateCrmCommercialNoteDto,
  ) {
    return this.crmCommercial.addNote(this.userOrThrow(req), id, dto);
  }

  @Post('customers/:id/activities')
  @Roles(Role.ADMIN)
  addActivity(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: CreateCrmCommercialActivityDto,
  ) {
    return this.crmCommercial.addActivity(this.userOrThrow(req), id, dto);
  }

  // Phase 2: Follow-up Tasks

  @Get('followup-tasks')
  @Roles(Role.ADMIN)
  listFollowupTasks(
    @Req() req: Request,
    @Query() query: CrmCommercialFollowupTaskQueryDto,
  ) {
    return this.crmCommercial.listFollowupTasks(this.userOrThrow(req), query);
  }

  @Post('customers/:id/followup-tasks')
  @Roles(Role.ADMIN)
  createFollowupTask(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: CreateCrmCommercialFollowupTaskDto,
  ) {
    return this.crmCommercial.createFollowupTask(this.userOrThrow(req), id, dto);
  }

  @Patch('followup-tasks/:id')
  @Roles(Role.ADMIN)
  updateFollowupTask(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: UpdateCrmCommercialFollowupTaskDto,
  ) {
    return this.crmCommercial.updateFollowupTask(this.userOrThrow(req), id, dto);
  }

  @Patch('followup-tasks/:id/complete')
  @Roles(Role.ADMIN)
  completeFollowupTask(@Req() req: Request, @Param('id') id: string) {
    return this.crmCommercial.completeFollowupTask(this.userOrThrow(req), id);
  }

  @Patch('followup-tasks/:id/cancel')
  @Roles(Role.ADMIN)
  cancelFollowupTask(@Req() req: Request, @Param('id') id: string) {
    return this.crmCommercial.cancelFollowupTask(this.userOrThrow(req), id);
  }
}