import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import PDFDocument from 'pdfkit';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class ServiceOrderQuotationPdfService {
  constructor(private readonly prisma: PrismaService) {}

  async buildForOrder(orderId: string) {
    const order = await this.prisma.serviceOrder.findUnique({
      where: { id: orderId },
      include: {
        client: true,
        quotation: {
          include: {
            items: {
              orderBy: {
                createdAt: 'asc',
              },
            },
          },
        },
      },
    });

    if (!order) {
      throw new NotFoundException('Orden de servicio no encontrada para generar PDF');
    }

    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: {
        companyName: true,
        rnc: true,
        phone: true,
        address: true,
      },
    });

    const quote = order.quotation;
    if (!quote) {
      throw new BadRequestException('La orden no tiene cotización vinculada para generar PDF');
    }

    const createdAt = quote.createdAt;
    const fileName = `cotizacion_${createdAt.toISOString().slice(0, 10)}_${order.id.slice(0, 8)}.pdf`;

    const doc = new PDFDocument({ margin: 40, size: 'A4' });
    const chunks: Buffer[] = [];

    const pdfBuffer = new Promise<Buffer>((resolve, reject) => {
      doc.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);
    });

    const companyName = (appConfig?.companyName ?? 'FULLTECH').trim() || 'FULLTECH';
    const companyRnc = (appConfig?.rnc ?? '').trim();
    const companyPhone = (appConfig?.phone ?? '').trim();
    const companyAddress = (appConfig?.address ?? '').trim();

    doc.fontSize(20).text(companyName, { align: 'left' });
    doc.moveDown(0.3);
    if (companyRnc) doc.fontSize(10).text(`RNC: ${companyRnc}`);
    if (companyPhone) doc.fontSize(10).text(`Tel: ${companyPhone}`);
    if (companyAddress) doc.fontSize(10).text(`Dirección: ${companyAddress}`);

    doc.moveDown(1);
    doc.fontSize(18).text('Cotización de orden de servicio');
    doc.moveDown(0.5);
    doc.fontSize(11).text(`Orden ID: ${order.id}`);
    doc.text(`Cotización ID: ${quote.id}`);
    doc.text(`Fecha: ${createdAt.toLocaleString('es-DO')}`);
    doc.text(`Cliente: ${order.client.nombre}`);
    doc.text(`Teléfono: ${order.client.telefono}`);
    doc.text(`Tipo de servicio: ${order.serviceType}`);
    doc.text(`Categoría: ${order.category}`);
    doc.moveDown(0.8);

    if (quote.note?.trim()) {
      doc.fontSize(11).text(`Nota: ${quote.note.trim()}`);
      doc.moveDown(0.6);
    }

    doc.fontSize(12).text('Detalle', { underline: true });
    doc.moveDown(0.4);

    const startX = doc.x;
    const width = doc.page.width - doc.page.margins.left - doc.page.margins.right;
    const productWidth = Math.round(width * 0.48);
    const qtyWidth = Math.round(width * 0.12);
    const unitWidth = Math.round(width * 0.18);
    const totalWidth = width - productWidth - qtyWidth - unitWidth;

    const writeRow = (columns: [string, string, string, string], bold = false) => {
      const rowY = doc.y;
      if (bold) {
        doc.font('Helvetica-Bold');
      } else {
        doc.font('Helvetica');
      }
      doc.text(columns[0], startX, rowY, { width: productWidth });
      doc.text(columns[1], startX + productWidth, rowY, { width: qtyWidth, align: 'right' });
      doc.text(columns[2], startX + productWidth + qtyWidth, rowY, { width: unitWidth, align: 'right' });
      doc.text(columns[3], startX + productWidth + qtyWidth + unitWidth, rowY, { width: totalWidth, align: 'right' });
      doc.moveDown(0.4);
    };

    writeRow(['Producto', 'Cant.', 'Precio', 'Total'], true);
    doc.moveTo(startX, doc.y).lineTo(startX + width, doc.y).stroke();
    doc.moveDown(0.3);

    for (const item of quote.items) {
      writeRow([
        item.productNameSnapshot,
        Number(item.qty).toFixed(Number(item.qty) % 1 === 0 ? 0 : 2),
        `RD$ ${Number(item.unitPrice).toFixed(2)}`,
        `RD$ ${Number(item.lineTotal).toFixed(2)}`,
      ]);
    }

    doc.moveDown(0.8);
    doc.font('Helvetica-Bold').text(`Subtotal: RD$ ${Number(quote.subtotal).toFixed(2)}`, { align: 'right' });
    doc.text(
      quote.includeItbis
        ? `ITBIS (${(Number(quote.itbisRate) * 100).toFixed(0)}%): RD$ ${Number(quote.itbisAmount).toFixed(2)}`
        : 'ITBIS: No aplicado',
      { align: 'right' },
    );
    doc.fontSize(13).text(`Total: RD$ ${Number(quote.total).toFixed(2)}`, { align: 'right' });
    doc.end();

    return {
      bytes: await pdfBuffer,
      fileName,
      order,
    };
  }
}
