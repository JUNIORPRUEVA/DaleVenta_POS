import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { SettingsController } from './settings.controller';
import { SettingsService } from './settings.service';
import { normalizeJwtSecret } from '../auth/jwt.util';

@Module({
  imports: [
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: normalizeJwtSecret(config.get<string>('JWT_SECRET')) ?? 'change-me',
        signOptions: { expiresIn: '10m' },
      }),
    }),
  ],
  controllers: [SettingsController],
  providers: [SettingsService],
})
export class SettingsModule {}
