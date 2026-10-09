import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import request from "supertest";
import { AppUpdatesController } from "./app-updates.controller";
import { AppUpdatesService } from "./app-updates.service";

describe("AppUpdatesController", () => {
  let app: INestApplication;
  const check = jest.fn().mockResolvedValue({ updateAvailable: false });

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [AppUpdatesController],
      providers: [{ provide: AppUpdatesService, useValue: { check } }],
    }).compile();

    app = moduleRef.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => {
    check.mockClear();
  });

  it("accepts a valid public unauthenticated request and sets short cache headers", async () => {
    const response = await request(app.getHttpServer())
      .get("/api/app-updates/check")
      .query({ platform: "windows", channel: "stable", version: "1.0.6", build: "130" })
      .expect(200);

    expect(response.headers["cache-control"]).toBe("public, max-age=60");
    expect(response.body).toEqual({ updateAvailable: false });
    expect(check).toHaveBeenCalledWith(
      { platform: "windows", channel: "stable", version: "1.0.6", build: 130 },
      expect.any(String),
    );
  });

  it("returns 400 for malformed build", async () => {
    await request(app.getHttpServer())
      .get("/api/app-updates/check")
      .query({ platform: "windows", channel: "stable", version: "1.0.6", build: "abc" })
      .expect(400);
  });

  it("returns 400 for invalid platform", async () => {
    await request(app.getHttpServer())
      .get("/api/app-updates/check")
      .query({ platform: "linux", channel: "stable", version: "1.0.6", build: "130" })
      .expect(400);
  });

  it("returns 400 for invalid channel", async () => {
    await request(app.getHttpServer())
      .get("/api/app-updates/check")
      .query({ platform: "windows", channel: "nightly", version: "1.0.6", build: "130" })
      .expect(400);
  });
});
