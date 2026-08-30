import { Global, Module } from '@nestjs/common';
import { CatalogProductsController } from './catalog-products.controller';
import { CatalogRealtimeRelayService } from './catalog-realtime-relay.service';
import { CatalogProductsService } from './catalog-products.service';
import { ProductSourceResolver } from './product-source.resolver';
import { ProductsService } from './products.service';
import { ProductsController } from './products.controller';
import { StorageModule } from '../storage/storage.module';

@Global()
@Module({
  imports: [StorageModule],
  providers: [ProductsService, CatalogProductsService, ProductSourceResolver, CatalogRealtimeRelayService],
  controllers: [ProductsController, CatalogProductsController],
  exports: [ProductsService, CatalogProductsService, ProductSourceResolver, CatalogRealtimeRelayService],
})
export class ProductsModule {}
