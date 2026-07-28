import {
  BadRequestException,
  Body,
  Controller,
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
}
