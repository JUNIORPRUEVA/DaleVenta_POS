import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { CashController } from './cash.controller';
import { CashService } from './cash.service';
import { TerminalResolutionService } from '../terminals/terminal-resolution.service';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [PrismaModule, AuthModule],
  controllers: [CashController],
  providers: [CashService, TerminalResolutionService],
  exports: [CashService],
})
export class CashModule {}
