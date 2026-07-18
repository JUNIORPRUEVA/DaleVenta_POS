import { Controller, Get, NotFoundException, Param, Res } from "@nestjs/common";
import { Response } from "express";
import { SalesService } from "./sales.service";

@Controller("sales/public")
export class SalesPublicController {
  constructor(private readonly sales: SalesService) {}

  @Get("invoice-pdf/:saleId/:fileName")
  async downloadInvoicePdf(
    @Param("saleId") saleId: string,
    @Param("fileName") fileName: string,
    @Res() res: Response,
  ) {
    const file = await this.sales.resolvePublicInvoicePdfDownload(
      saleId,
      fileName,
    );

    return res.download(file.absolutePath, file.fileName, (error) => {
      if (!error || res.headersSent) return;
      throw new NotFoundException("PDF de factura no encontrado.");
    });
  }
}
