import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { RecoveryReviewController } from './recovery-review.controller';
import { RecoveryReviewService } from './recovery-review.service';
@Module({imports:[PrismaModule],providers:[RecoveryReviewService],controllers:[RecoveryReviewController]})
export class RecoveryReviewModule {}
