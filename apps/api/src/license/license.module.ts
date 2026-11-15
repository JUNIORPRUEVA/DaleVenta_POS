import { Global, Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { LicenseController } from './license.controller';
import { LicenseService } from './license.service';
import { CrmLicenseService } from './crm-license.service';
import { CrmLicenseController } from './crm-license.controller';

@Global()
@Module({
  imports: [PrismaModule],
  controllers: [LicenseController, CrmLicenseController],
  providers: [LicenseService, CrmLicenseService],
  exports: [LicenseService],
})
export class LicenseModule {}
