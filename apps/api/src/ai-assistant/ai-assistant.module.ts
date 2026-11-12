import { Module } from '@nestjs/common';
import { ProductsModule } from '../products/products.module';
import { AiAssistantController } from './ai-assistant.controller';
import { AiAssistantService } from './ai-assistant.service';
import { AppyraIaClient } from './appyra-ia.client';

@Module({
  imports: [ProductsModule],
  controllers: [AiAssistantController],
  providers: [AiAssistantService, AppyraIaClient],
  exports: [AiAssistantService],
})
export class AiAssistantModule {}
