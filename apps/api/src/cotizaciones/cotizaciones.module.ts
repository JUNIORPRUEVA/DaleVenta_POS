import { Module } from "@nestjs/common";
import { NotificationsModule } from "../notifications/notifications.module";
import { PrismaModule } from "../prisma/prisma.module";
import { CotizacionesPublicController } from "./cotizaciones-public.controller";
import { CotizacionesController } from "./cotizaciones.controller";
import { CotizacionesService } from "./cotizaciones.service";
import { PriceListsModule } from "../price-lists/price-lists.module";

@Module({
  imports: [PrismaModule, NotificationsModule, PriceListsModule],
  controllers: [CotizacionesController, CotizacionesPublicController],
  providers: [CotizacionesService],
  exports: [CotizacionesService],
})
export class CotizacionesModule {}
