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
import { PunchModule } from './punch/punch.module';
import { ContabilidadModule } from './contabilidad/contabilidad.module';
import { SalesModule } from './sales/sales.module';
import { PayrollModule } from './payroll/payroll.module';
import { AdminModule } from './admin/admin.module';
import { SettingsModule } from './settings/settings.module';
import { CotizacionesModule } from './cotizaciones/cotizaciones.module';
import { LocationsModule } from './locations/locations.module';
import { WorkSchedulingModule } from './work-scheduling/work-scheduling.module';
import { CompanyManualModule } from './company-manual/company-manual.module';
import { AiAssistantModule } from './ai-assistant/ai-assistant.module';
import { NotificationsModule } from './notifications/notifications.module';
import { MediaGalleryModule } from './media-gallery/media-gallery.module';
import { PublicidadImagesModule } from './publicidad-images/publicidad-images.module';
import { ServiceOrdersModule } from './service-orders/service-orders.module';
import { StorageModule } from './storage/storage.module';
import { WarrantyConfigsModule } from './warranty-configs/warranty-configs.module';
import { WhatsappModule } from './whatsapp/whatsapp.module';
import { WhatsappInboxModule } from './whatsapp-inbox/whatsapp-inbox.module';
import { EmployeeWarningsModule } from './employee-warnings/employee-warnings.module';
import { MarketingModule } from './marketing/marketing.module';
import { CrmCommercialModule } from './crm-commercial/crm-commercial.module';
import { CashModule } from './cash/cash.module';
import { ReportsModule } from './reports/reports.module';

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
    ClientsModule,
    PunchModule,
    ContabilidadModule,
    SalesModule,
    PayrollModule,
    AdminModule,
    SettingsModule,
    CotizacionesModule,
    LocationsModule,
    WorkSchedulingModule,
    CompanyManualModule,
    AiAssistantModule,
    NotificationsModule,
    MediaGalleryModule,
    PublicidadImagesModule,
    ServiceOrdersModule,
    StorageModule,
    WarrantyConfigsModule,
    WhatsappModule,
    WhatsappInboxModule,
    EmployeeWarningsModule,
    MarketingModule,
    CrmCommercialModule,
    CashModule,
    ReportsModule,
  ]
})
export class AppModule {}

