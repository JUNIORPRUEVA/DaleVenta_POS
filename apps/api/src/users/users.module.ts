import { Module } from '@nestjs/common';
import { UsersService } from './users.service';
import { UsersController } from './users.controller';
import { StorageModule } from '../storage/storage.module';
import { ProductsModule } from '../products/products.module';

@Module({
  imports: [StorageModule, ProductsModule],
  providers: [UsersService],
  controllers: [UsersController]
})
export class UsersModule {}
