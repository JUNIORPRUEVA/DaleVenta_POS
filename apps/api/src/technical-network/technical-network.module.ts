import { Module } from '@nestjs/common';
import { TechnicalNetworkController } from './technical-network.controller';
import { TechnicalNetworkService } from './technical-network.service';

@Module({
  controllers: [TechnicalNetworkController],
  providers: [TechnicalNetworkService],
})
export class TechnicalNetworkModule {}
