import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { WhatsappModule } from '../whatsapp/whatsapp.module';
import { WhatsappInboxModule } from '../whatsapp-inbox/whatsapp-inbox.module';
import { AiAssistantModule } from '../ai-assistant/ai-assistant.module';
import { CrmCommercialController } from './crm-commercial.controller';
import { CrmCommercialService } from './crm-commercial.service';
import { CrmBotService } from './crm-bot.service';

@Module({
  imports: [PrismaModule, WhatsappModule, WhatsappInboxModule, AiAssistantModule],
  controllers: [CrmCommercialController],
  providers: [CrmCommercialService, CrmBotService],
  exports: [CrmBotService],
})
export class CrmCommercialModule {}
