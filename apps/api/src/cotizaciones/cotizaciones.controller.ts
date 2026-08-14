import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Role } from "@prisma/client";
import { Request } from "express";
import { Permissions, Roles } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import { CotizacionesService } from "./cotizaciones.service";
import { AnalyzeCotizacionAiDto } from "./dto/analyze-cotizacion-ai.dto";
import { ChatCotizacionAiDto } from "./dto/chat-cotizacion-ai.dto";
import { CreateCotizacionPdfShareLinkDto } from "./dto/create-cotizacion-pdf-share-link.dto";
import { CotizacionesQueryDto } from "./dto/cotizaciones-query.dto";
import { CreateCotizacionDto } from "./dto/create-cotizacion.dto";
import { SendCotizacionWhatsappDto } from "./dto/send-cotizacion-whatsapp.dto";
import { UpdateCotizacionDto } from "./dto/update-cotizacion.dto";

@UseGuards(AuthGuard("jwt"), RolesGuard)
@Controller("cotizaciones")
export class CotizacionesController {
  constructor(private readonly cotizaciones: CotizacionesService) {}

  @Get()
  @Permissions("viewQuotes")
  @Roles(
    Role.ADMIN,
    Role.CAJERO,
    Role.ASISTENTE,
    Role.VENDEDOR,
    Role.TECNICO,
    Role.MARKETING,
  )
  list(@Req() req: Request, @Query() query: CotizacionesQueryDto) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.list(user, query);
  }

  @Get(":id")
  @Permissions("viewQuotes")
  @Roles(
    Role.ADMIN,
    Role.CAJERO,
    Role.ASISTENTE,
    Role.VENDEDOR,
    Role.TECNICO,
    Role.MARKETING,
  )
  getOne(@Req() req: Request, @Param("id") id: string) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.findOne(user, id);
  }

  @Post("ai/analyze")
  @Permissions("viewQuotes")
  @Roles(
    Role.ADMIN,
    Role.CAJERO,
    Role.ASISTENTE,
    Role.VENDEDOR,
    Role.TECNICO,
    Role.MARKETING,
  )
  analyzeAi(@Req() req: Request, @Body() dto: AnalyzeCotizacionAiDto) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.analyzeAssistant(user, dto);
  }

  @Post("ai/chat")
  @Permissions("viewQuotes")
  @Roles(
    Role.ADMIN,
    Role.CAJERO,
    Role.ASISTENTE,
    Role.VENDEDOR,
    Role.TECNICO,
    Role.MARKETING,
  )
  chatAi(@Req() req: Request, @Body() dto: ChatCotizacionAiDto) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.chatAssistant(user, dto);
  }

  @Post()
  @Permissions("viewQuotes")
  @Roles(
    Role.ADMIN,
    Role.CAJERO,
    Role.ASISTENTE,
    Role.VENDEDOR,
    Role.TECNICO,
    Role.MARKETING,
  )
  create(@Req() req: Request, @Body() dto: CreateCotizacionDto) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.create(user, dto);
  }

  @Patch(":id")
  @Permissions("viewQuotes")
  @Roles(
    Role.ADMIN,
    Role.CAJERO,
    Role.ASISTENTE,
    Role.VENDEDOR,
    Role.TECNICO,
    Role.MARKETING,
  )
  update(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: UpdateCotizacionDto,
  ) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.update(user, id, dto);
  }

  @Post("send-whatsapp")
  @Permissions("viewQuotes")
  @Roles(
    Role.ADMIN,
    Role.CAJERO,
    Role.ASISTENTE,
    Role.VENDEDOR,
    Role.TECNICO,
    Role.MARKETING,
  )
  sendWhatsApp(@Req() req: Request, @Body() dto: SendCotizacionWhatsappDto) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.sendWhatsApp(user, dto);
  }

  @Post("pdf-share-link")
  @Permissions("viewQuotes")
  @Roles(
    Role.ADMIN,
    Role.CAJERO,
    Role.ASISTENTE,
    Role.VENDEDOR,
    Role.TECNICO,
    Role.MARKETING,
  )
  createPdfShareLink(
    @Req() req: Request,
    @Body() dto: CreateCotizacionPdfShareLinkDto,
  ) {
    const user = req.user as { id: string; role: Role };
    const forwardedProto = `${req.headers["x-forwarded-proto"] ?? ""}`
      .split(",")[0]
      .trim();
    const proto = forwardedProto || req.protocol || "http";
    const host = req.get("host") ?? "";
    const requestBaseUrl = host ? `${proto}://${host}` : undefined;
    return this.cotizaciones.createPdfShareLink(user, dto, requestBaseUrl);
  }

  @Delete("debug/purge")
  @Roles(Role.ADMIN)
  purgeAllForDebug(@Req() req: Request) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.purgeAllForDebug(user);
  }

  @Delete(":id")
  @Permissions("viewQuotes")
  @Roles(
    Role.ADMIN,
    Role.CAJERO,
    Role.ASISTENTE,
    Role.VENDEDOR,
    Role.TECNICO,
    Role.MARKETING,
  )
  remove(@Req() req: Request, @Param("id") id: string) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.remove(user, id);
  }
}
