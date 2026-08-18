import { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { AuthGuard } from "@nestjs/passport";
import request from "supertest";
import { RolesGuard } from "../auth/roles.guard";
import { SalesController } from "./sales.controller";
import { SalesService } from "./sales.service";

describe("Sales fiscal HTTP routes", () => {
  let app: INestApplication;
  const user = {
    id: "11111111-1111-4111-8111-111111111111",
    role: "ADMIN",
    companyId: "22222222-2222-4222-8222-222222222222",
    authorizedPermissions: ["refundSales"],
  };
  const sales = {
    create: jest.fn(),
    returnSale: jest.fn(),
    listMine: jest.fn().mockResolvedValue([]),
    listInvoices: jest.fn().mockResolvedValue([]),
    listCredits: jest.fn().mockResolvedValue([]),
    summaryMine: jest.fn().mockResolvedValue({}),
    calculate: jest.fn().mockResolvedValue({}),
    createInvoicePdfShareLink: jest.fn(),
    purgeAllForDebug: jest.fn(),
    remove: jest.fn(),
    addCreditPayment: jest.fn(),
  };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [SalesController],
      providers: [{ provide: SalesService, useValue: sales }],
    })
      .overrideGuard(AuthGuard("jwt"))
      .useValue({
        canActivate: (context: any) => {
          context.switchToHttp().getRequest().user = user;
          return true;
        },
      })
      .overrideGuard(RolesGuard)
      .useValue({ canActivate: () => true })
      .compile();

    app = moduleRef.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("posts a B01 fiscal sale through the HTTP controller with tenant user", async () => {
    sales.create.mockResolvedValueOnce({
      id: "sale-a",
      fiscalVoucherType: "B01",
      ncf: "B0100000001",
      taxableBase: "1000",
      taxAmount: "180",
      totalSold: "1180",
    });

    const res = await request(app.getHttpServer())
      .post("/sales")
      .send({
        fiscalVoucherType: "B01",
        fiscalCustomerTaxId: "101010101",
        fiscalCustomerName: "Cliente Fiscal",
        clientRequestId: "http-b01-1",
        items: [{ productName: "Servicio", qty: 1, priceSoldUnit: 1180 }],
      })
      .expect(201);

    expect(res.body.ncf).toBe("B0100000001");
    expect(sales.create).toHaveBeenCalledWith(
      expect.objectContaining({ companyId: user.companyId }),
      expect.objectContaining({
        fiscalVoucherType: "B01",
        clientRequestId: "http-b01-1",
      }),
    );
  });

  it("posts a refund through HTTP using the refund permission route", async () => {
    sales.returnSale.mockResolvedValueOnce({
      id: "refund-a",
      kind: "refund",
      totalSold: "-1180",
    });

    const res = await request(app.getHttpServer())
      .post("/sales/sale-a/return")
      .send({ items: [{ saleItemId: "item-a", qty: 1 }] })
      .expect(201);

    expect(res.body.id).toBe("refund-a");
    expect(sales.returnSale).toHaveBeenCalledWith(
      expect.objectContaining({ companyId: user.companyId }),
      "sale-a",
      expect.objectContaining({ items: [{ saleItemId: "item-a", qty: 1 }] }),
    );
  });
});
