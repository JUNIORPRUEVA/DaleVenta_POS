import { Module } from "@nestjs/common";
import { NotificationsModule } from "../notifications/notifications.module";
import { PrismaModule } from "../prisma/prisma.module";
import { CotizacionesPublicController } from "./cotizaciones-public.controller";
import { CotizacionesController } from "./cotizaciones.controller";
import { CotizacionesService } from "./cotizaciones.service";

@Module({
  imports: [PrismaModule, NotificationsModule],
  controllers: [CotizacionesController, CotizacionesPublicController],
  providers: [CotizacionesService],
  exports: [CotizacionesService],
})
export class CotizacionesModule {}
