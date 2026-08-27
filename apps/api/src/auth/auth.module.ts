import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { PassportModule } from "@nestjs/passport";
import { ConfigService } from "@nestjs/config";
import { AuthService } from "./auth.service";
import { AuthController } from "./auth.controller";
import { JwtStrategy } from "./jwt.strategy";
import { normalizeJwtSecret } from "./jwt.util";
import { StorageModule } from "../storage/storage.module";
import { PasswordResetEmailService } from "./password-reset-email.service";
import { RedisModule } from "../common/redis/redis.module";

@Module({
  imports: [
    PassportModule,
    StorageModule,
    RedisModule,
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret:
          normalizeJwtSecret(config.get<string>("JWT_SECRET")) ?? "change-me",
        signOptions: {
          expiresIn: (config.get<string>("JWT_EXPIRES_IN") ?? "15m") as any,
        },
      }),
    }),
  ],
  providers: [AuthService, JwtStrategy, PasswordResetEmailService],
  controllers: [AuthController],
  exports: [AuthService],
})
export class AuthModule {}
