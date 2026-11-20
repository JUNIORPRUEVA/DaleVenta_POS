import { Global, Module } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { PrismaModule } from '../prisma/prisma.module';
import { LicenseController } from './license.controller';
import { LicenseService } from './license.service';
import { CrmLicenseService } from './crm-license.service';
import { CrmLicenseController } from './crm-license.controller';
import { CompanyActivityService } from './company-activity.service';
import { CompanyActivityController } from './company-activity.controller';
import { LicensePlansService } from './plans/license-plans.service';
import { LicenseEntitlementsService } from './plans/license-entitlements.service';
import { LicenseActivationService } from './orders/license-activation.service';
import { LicenseEvidenceStorage } from './orders/license-evidence.storage';
import { LicenseOrdersService } from './orders/license-orders.service';
import { LicenseRenewalService } from './renewal/license-renewal.service';
import { LicensePlanRequestService } from './renewal/license-plan-request.service';
import { LicenseProvisionalService } from './orders/license-provisional.service';
import { LicenseProvisionalScheduler } from './orders/license-provisional.scheduler';
import { OcrEngine } from './evidence/ocr.engine';
import { MetaCloudClient } from './notifications/meta-cloud.client';
import { LicenseNotifierService } from './notifications/license-notifier.service';
import { LicenseReminderScheduler } from './notifications/license-reminder.scheduler';
import { LicenseAccessInterceptor } from './license-access.interceptor';

@Global()
@Module({
  imports: [PrismaModule],
  controllers: [LicenseController, CrmLicenseController, CompanyActivityController],
  providers: [
    LicenseService,
    CrmLicenseService,
    CompanyActivityService,
    LicensePlansService,
    LicenseEntitlementsService,
    LicenseActivationService,
    LicenseEvidenceStorage,
    LicenseOrdersService,
    LicenseRenewalService,
    LicensePlanRequestService,
    LicenseProvisionalService,
    LicenseProvisionalScheduler,
    OcrEngine,
    MetaCloudClient,
    LicenseNotifierService,
    LicenseReminderScheduler,
    { provide: APP_INTERCEPTOR, useClass: LicenseAccessInterceptor },
  ],
  exports: [
    LicenseService,
    LicensePlansService,
    LicenseEntitlementsService,
    LicenseOrdersService,
    LicenseRenewalService,
    LicensePlanRequestService,
  ],
})
export class LicenseModule {}
