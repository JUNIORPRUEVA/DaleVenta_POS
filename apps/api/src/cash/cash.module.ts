import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { CashController } from './cash.controller';
import { CashService } from './cash.service';
import { TerminalResolutionService } from '../terminals/terminal-resolution.service';

@Module({
  imports: [PrismaModule],
  controllers: [CashController],
  providers: [CashService, TerminalResolutionService],
  exports: [CashService],
})
export class CashModule {}
