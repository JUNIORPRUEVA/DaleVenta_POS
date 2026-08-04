import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Role } from "@prisma/client";
import { Request } from "express";
import { Roles } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import { CashService } from "./cash.service";
import {
  CloseCashSessionDto,
  CreateCashMovementDto,
  OpenCashSessionDto,
} from "./dto/cash.dto";

const CASH_ROLES = [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR] as const;

@UseGuards(AuthGuard("jwt"), RolesGuard)
@Roles(...CASH_ROLES)
@Controller("cash")
export class CashController {
  constructor(private readonly cash: CashService) {}

  @Get("state")
  state(@Req() req: Request) {
    return this.cash.gateState(req.user as { id: string; role: Role });
  }

  @Post("sessions/open")
  open(@Req() req: Request, @Body() dto: OpenCashSessionDto) {
    return this.cash.startSession(req.user as { id: string; role: Role }, dto);
  }

  @Post("sessions/close")
  close(@Req() req: Request, @Body() dto: CloseCashSessionDto) {
    return this.cash.closeSession(req.user as { id: string; role: Role }, dto);
  }

  @Get("summary")
  summary(@Req() req: Request) {
    return this.cash.summary(req.user as { id: string; role: Role });
  }

  @Get("movements")
  movements(@Req() req: Request) {
    return this.cash.movements(req.user as { id: string; role: Role });
  }

  @Get("movements/history")
  movementHistory(@Req() req: Request, @Query() query: Record<string, string>) {
    return this.cash.movementHistory(
      req.user as { id: string; role: Role },
      query,
    );
  }

  @Post("movements")
  addMovement(@Req() req: Request, @Body() dto: CreateCashMovementDto) {
    return this.cash.addMovement(req.user as { id: string; role: Role }, dto);
  }

  @Get("sessions/closed")
  closedSessions(@Req() req: Request) {
    return this.cash.closedSessions(req.user as { id: string; role: Role });
  }

  @Get("sessions/:id")
  sessionDetail(@Req() req: Request, @Param("id") id: string) {
    return this.cash.sessionDetail(
      req.user as { id: string; role: Role },
      id,
    );
  }
}
