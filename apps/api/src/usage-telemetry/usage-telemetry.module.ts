import { Module } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { PrismaModule } from '../prisma/prisma.module';
import { UsageTelemetryController } from './usage-telemetry.controller';
import { UsageTelemetryInterceptor } from './usage-telemetry.interceptor';
import { UsageTelemetryService } from './usage-telemetry.service';

@Module({
  imports: [PrismaModule],
  controllers: [UsageTelemetryController],
  providers: [
    UsageTelemetryService,
    { provide: APP_INTERCEPTOR, useClass: UsageTelemetryInterceptor },
  ],
  exports: [UsageTelemetryService],
})
export class UsageTelemetryModule {}
