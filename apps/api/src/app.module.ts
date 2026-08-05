import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { join } from 'path';
import { PrismaModule } from './prisma/prisma.module';
import { RedisModule } from './common/redis/redis.module';
import { HealthModule } from './health/health.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { ProductsModule } from './products/products.module';
import { ClientsModule } from './clients/clients.module';
import { ContabilidadModule } from './contabilidad/contabilidad.module';
import { SalesModule } from './sales/sales.module';
import { PayrollModule } from './payroll/payroll.module';
import { CotizacionesModule } from './cotizaciones/cotizaciones.module';
import { LocationsModule } from './locations/locations.module';
import { WorkSchedulingModule } from './work-scheduling/work-scheduling.module';
import { AiAssistantModule } from './ai-assistant/ai-assistant.module';
import { NotificationsModule } from './notifications/notifications.module';
import { StorageModule } from './storage/storage.module';
import { WarrantyConfigsModule } from './warranty-configs/warranty-configs.module';
import { CashModule } from './cash/cash.module';
import { ReportsModule } from './reports/reports.module';
import { PurchasesModule } from './purchases/purchases.module';
import { SettingsModule } from './settings/settings.module';
import { LicenseModule } from './license/license.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: [
        join(process.cwd(), '.env'),
        join(process.cwd(), '..', '.env'),
        join(process.cwd(), '..', '..', '.env'),
      ]
    }),
    ScheduleModule.forRoot(),
    RedisModule,
    PrismaModule,
    HealthModule,
    AuthModule,
    UsersModule,
    ProductsModule,
    LicenseModule,
    ClientsModule,
    ContabilidadModule,
    SalesModule,
    PayrollModule,
    CotizacionesModule,
    LocationsModule,
    WorkSchedulingModule,
    AiAssistantModule,
    NotificationsModule,
    StorageModule,
    WarrantyConfigsModule,
    CashModule,
    ReportsModule,
    PurchasesModule,
    SettingsModule,
  ]
})
export class AppModule {}

