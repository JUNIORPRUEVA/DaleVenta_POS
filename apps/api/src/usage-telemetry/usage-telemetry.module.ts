import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { UsageTelemetryController } from './usage-telemetry.controller';
import { UsageTelemetryService } from './usage-telemetry.service';

@Module({
  imports: [PrismaModule],
  controllers: [UsageTelemetryController],
  providers: [UsageTelemetryService],
  exports: [UsageTelemetryService],
})
export class UsageTelemetryModule {}
