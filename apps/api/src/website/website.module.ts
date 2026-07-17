import { Module } from '@nestjs/common';
import { ProductsModule } from '../products/products.module';
import { WebsiteController } from './website.controller';
import { WebsiteService } from './website.service';

@Module({
  imports: [ProductsModule],
  controllers: [WebsiteController],
  providers: [WebsiteService],
})
export class WebsiteModule {}
