import { Module, forwardRef } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { WhatsappInboxService } from './whatsapp-inbox.service';
import { WhatsappInboxController, WhatsappInboxWebhookController } from './whatsapp-inbox.controller';
import { WhatsappModule } from '../whatsapp/whatsapp.module';
import { ProductsModule } from '../products/products.module';
import { StorageModule } from '../storage/storage.module';
import { RedisModule } from '../common/redis/redis.module';
import { CrmCommercialModule } from '../crm-commercial/crm-commercial.module';

@Module({
  imports: [PrismaModule, WhatsappModule, ProductsModule, StorageModule, RedisModule, forwardRef(() => CrmCommercialModule)],
  providers: [WhatsappInboxService],
  controllers: [WhatsappInboxController, WhatsappInboxWebhookController],
  exports: [WhatsappInboxService],
})
export class WhatsappInboxModule {}
