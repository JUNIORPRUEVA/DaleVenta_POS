import { Controller, Get, Header, Req, UseGuards, UseInterceptors } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { Request } from 'express';
import { requireTenant, type TenantUser } from '../auth/tenant-context';
import { CatalogProductsService } from './catalog-products.service';
import { ProductSourceResolver } from './product-source.resolver';
import { ProductCostInterceptor } from './product-cost.interceptor';

@UseInterceptors(ProductCostInterceptor)
@Controller('catalog')
export class CatalogProductsController {
  constructor(
    private readonly catalogProducts: CatalogProductsService,
    private readonly productSourceResolver: ProductSourceResolver,
  ) {}

  @UseGuards(AuthGuard('jwt'))
  @Header('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate')
  @Header('Pragma', 'no-cache')
  @Header('Expires', '0')
  @Header('Surrogate-Control', 'no-store')
  @Get('products')
  async findAll(@Req() req: Request) {
    const user = req.user as TenantUser;
    const companyId = requireTenant(user);
    const sourceContext = await this.productSourceResolver.resolveForCompany(companyId);
    if (sourceContext.source === 'LOCAL') {
      return {
        source: 'LOCAL',
        readOnly: false,
        total: 0,
        fetchedAt: new Date().toISOString(),
        items: [],
      };
    }
    return this.catalogProducts.findAll({
      companyId,
      source: sourceContext.source,
      fullposCompanyId: sourceContext.fullposCompanyId,
    });
  }
}
