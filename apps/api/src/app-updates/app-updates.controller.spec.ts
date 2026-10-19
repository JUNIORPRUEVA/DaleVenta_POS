import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import request from "supertest";
import { AppUpdatesController } from "./app-updates.controller";
import { AppUpdatesService } from "./app-updates.service";

describe("AppUpdatesController", () => {
  let app: INestApplication;
  const check = jest.fn().mockResolvedValue({ updateAvailable: false });
  const usesPrivateUpdateCheckCache = jest.fn().mockReturnValue(false);

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [AppUpdatesController],
      providers: [
        { provide: AppUpdatesService, useValue: { check, usesPrivateUpdateCheckCache } },
      ],
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
    usesPrivateUpdateCheckCache.mockClear();
    usesPrivateUpdateCheckCache.mockReturnValue(false);
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

  it("accepts an optional deviceId for future targeted clients", async () => {
    await request(app.getHttpServer())
      .get("/api/app-updates/check")
      .query({
        platform: "windows",
        channel: "stable",
        version: "1.0.6",
        build: "130",
        deviceId: "install-123",
      })
      .expect(200);

    expect(check).toHaveBeenCalledWith(
      {
        platform: "windows",
        channel: "stable",
        version: "1.0.6",
        build: 130,
        deviceId: "install-123",
      },
      expect.any(String),
    );
  });

  it("uses private no-store cache headers while pilot targeting is configured", async () => {
    usesPrivateUpdateCheckCache.mockReturnValue(true);

    const response = await request(app.getHttpServer())
      .get("/api/app-updates/check")
      .query({ platform: "windows", channel: "stable", version: "1.0.6", build: "130" })
      .expect(200);

    expect(response.headers["cache-control"]).toBe("private, no-store");
  });

  it("returns 400 for malformed build", async () => {
    await request(app.getHttpServer())
      .get("/api/app-updates/check")
      .query({ platform: "windows", channel: "stable", version: "1.0.6", build: "abc" })
      .expect(400);
  });

  it("redirects the stable public Windows link to the latest verified manifest", async () => {
    check.mockResolvedValueOnce({ updateAvailable: true, buildNumber: 143, downloadUrl: "https://downloads.example.test/installer.exe" });
    const response = await request(app.getHttpServer())
      .get("/api/app-updates/windows/latest/download")
      .expect(302);
    expect(response.headers.location).toBe("https://downloads.example.test/installer.exe");
    expect(response.headers["cache-control"]).toBe("no-store");
    expect(check).toHaveBeenCalledWith(
      { platform: "windows", channel: "stable", version: "0.0.0", build: 0 },
      expect.any(String),
    );
  });

  it("does not redirect to an old installer when none is published", async () => {
    await request(app.getHttpServer())
      .get("/api/app-updates/windows/latest/download")
      .expect(404);
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
