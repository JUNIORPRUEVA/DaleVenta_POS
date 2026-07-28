import { Module } from '@nestjs/common';
import { StorageController } from './storage.controller';
import { UploadsController } from './uploads.controller';
import { R2Service } from './r2.service';

@Module({
  controllers: [StorageController, UploadsController],
  providers: [R2Service],
  exports: [R2Service],
})
export class StorageModule {}
