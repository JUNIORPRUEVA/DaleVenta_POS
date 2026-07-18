import { Controller, Get, NotFoundException, Param, Res } from "@nestjs/common";
import { Response } from "express";
import { CotizacionesService } from "./cotizaciones.service";

@Controller("cotizaciones/public")
export class CotizacionesPublicController {
  constructor(private readonly cotizaciones: CotizacionesService) {}

  @Get("pdf/:quotationId/:fileName")
  async downloadPdf(
    @Param("quotationId") quotationId: string,
    @Param("fileName") fileName: string,
    @Res() res: Response,
  ) {
    const file = await this.cotizaciones.resolvePublicPdfDownload(
      quotationId,
      fileName,
    );

    return res.download(file.absolutePath, file.fileName, (error) => {
      if (!error || res.headersSent) return;
      throw new NotFoundException("PDF de cotización no encontrado.");
    });
  }
}
