import { Module } from '@nestjs/common';
import { CatalogProductsController } from './catalog-products.controller';
import { CatalogRealtimeRelayService } from './catalog-realtime-relay.service';
import { CatalogProductsService } from './catalog-products.service';
import { ProductsService } from './products.service';
import { ProductsController } from './products.controller';
import { StorageModule } from '../storage/storage.module';

@Module({
  imports: [StorageModule],
  providers: [ProductsService, CatalogProductsService, CatalogRealtimeRelayService],
  controllers: [ProductsController, CatalogProductsController],
  exports: [ProductsService, CatalogProductsService, CatalogRealtimeRelayService],
})
export class ProductsModule {}
