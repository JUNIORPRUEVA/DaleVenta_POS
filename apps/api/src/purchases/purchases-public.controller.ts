import { Controller, Get, NotFoundException, Param, Res } from "@nestjs/common";
import { Response } from "express";
import { PurchasesService } from "./purchases.service";

@Controller("purchases/public")
export class PurchasesPublicController {
  constructor(private readonly purchases: PurchasesService) {}

  @Get("pdf/:purchaseOrderId/:fileName")
  async downloadPdf(
    @Param("purchaseOrderId") purchaseOrderId: string,
    @Param("fileName") fileName: string,
    @Res() res: Response,
  ) {
    const file = await this.purchases.resolvePublicPdfDownload(purchaseOrderId, fileName);
    return res.download(file.absolutePath, file.fileName, (error) => {
      if (!error || res.headersSent) return;
      throw new NotFoundException("PDF de orden de compra no encontrado.");
    });
  }
}
