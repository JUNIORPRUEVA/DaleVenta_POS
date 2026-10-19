import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Post,
  Req,
  UseGuards,
} from "@nestjs/common";
import { AuthService } from "./auth.service";
import { LoginDto } from "./dto/login.dto";
import { AuthGuard } from "@nestjs/passport";
import { Request } from "express";
import { RefreshDto } from "./dto/refresh.dto";
import { ForgotPasswordDto } from "./dto/forgot-password.dto";
import { ResetPasswordDto } from "./dto/reset-password.dto";

@Controller("auth")
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post("login")
  async login(@Body() dto: LoginDto) {
    const identifier = (dto.email ?? dto.identifier ?? "").trim();
    if (!identifier) {
      throw new BadRequestException("email o identifier es requerido");
    }
    return this.auth.login(identifier, dto.password);
  }

  @Post("register-business")
  async registerBusiness(@Body() dto: Record<string, unknown>) {
    return this.auth.registerBusiness(dto as any);
  }

  @Post("forgot-password")
  async forgotPassword(@Body() dto: ForgotPasswordDto, @Req() req: Request) {
    return this.auth.forgotPassword(dto.email, {
      ipAddress: req.ip,
      userAgent: req.get("user-agent") ?? null,
    });
  }

  @Post("reset-password")
  async resetPassword(@Body() dto: ResetPasswordDto, @Req() req: Request) {
    return this.auth.resetPassword(dto.token, dto.password, {
      ipAddress: req.ip,
      userAgent: req.get("user-agent") ?? null,
    });
  }

  @Post("refresh")
  async refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @UseGuards(AuthGuard("jwt"))
  @Get("me")
  async me(@Req() req: Request) {
    const user = req.user as any;
    return this.auth.me(user.id);
  }

  @UseGuards(AuthGuard("jwt"))
  @Post("offline-emergency/authorize")
  async authorizeOfflineEmergency(@Req() req: Request) {
    const user = req.user as any;
    return this.auth.authorizeOfflineEmergency(user, {
      deviceFingerprint: this.headerValue(req, "x-client-device-id"),
      platform: this.headerValue(req, "x-client-platform"),
      appVersion: this.headerValue(req, "x-client-app-version"),
    });
  }

  @UseGuards(AuthGuard("jwt"))
  @Get("account/deletion-preview")
  async deletionPreview(@Req() req: Request) {
    const user = req.user as any;
    return this.auth.deletionPreview(user.id, user.companyId);
  }

  @UseGuards(AuthGuard("jwt"))
  @Delete("account")
  async deleteAccount(
    @Req() req: Request,
    @Body() dto: Record<string, unknown>,
  ) {
    const user = req.user as any;
    return this.auth.deleteAccount(user.id, user.companyId, dto);
  }

  private headerValue(req: Request, name: string) {
    const value = req.headers[name.toLowerCase()];
    return Array.isArray(value) ? value[0] : value;
  }
}
