import { AppReleaseChannel, AppReleasePlatform, AppReleaseStatus } from "@prisma/client";
import { AppUpdatesService } from "./app-updates.service";

const validSha = "a".repeat(64);

function release(overrides: Record<string, unknown> = {}) {
  return {
    version: "1.0.7",
    buildNumber: 131,
    fileName: "Fullpos-Setup-1.0.7+131.exe",
    fileSize: BigInt(123456789),
    sha256: validSha,
    downloadUrl: "https://downloads.example.com/Fullpos-Setup-1.0.7+131.exe",
    storageDeletedAt: null,
    mandatory: false,
    minimumSupportedBuild: null,
    releaseNotes: [],
    publishedAt: new Date("2026-10-06T12:00:00.000Z"),
    ...overrides,
  };
}

function buildService(releases: ReturnType<typeof release>[]) {
  const findMany = jest.fn().mockResolvedValue(releases);
  const service = new AppUpdatesService({
    appRelease: { findMany },
  } as any, { get: jest.fn() } as any, { deleteObject: jest.fn() } as any);

  jest.spyOn((service as any).logger, "log").mockImplementation(() => undefined);
  jest.spyOn((service as any).logger, "error").mockImplementation(() => undefined);

  return { service, findMany };
}

const query = {
  platform: "windows" as const,
  channel: "stable" as const,
  version: "1.0.6",
  build: 130,
};

describe("AppUpdatesService", () => {
  it("returns false when there are no releases", async () => {
    const { service } = buildService([]);

    await expect(service.check(query, "test-no-releases")).resolves.toEqual({
      updateAvailable: false,
    });
  });

  it("queries only PUBLISHED releases", async () => {
    const { service, findMany } = buildService([]);

    await service.check(query, "test-published-filter");

    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          platform: AppReleasePlatform.WINDOWS,
          channel: AppReleaseChannel.STABLE,
          status: AppReleaseStatus.PUBLISHED,
          storageDeletedAt: null,
        },
      }),
    );
  });

  it("does not return an archived artifact even if it is greater", async () => {
    const { service } = buildService([release({ buildNumber: 131, storageDeletedAt: new Date() })]);

    await expect(service.check(query, "test-archived-artifact")).resolves.toEqual({
      updateAvailable: false,
    });
  });

  it("returns false when only DRAFT exists outside the query result", async () => {
    const { service } = buildService([]);

    await expect(service.check(query, "test-draft")).resolves.toEqual({
      updateAvailable: false,
    });
  });

  it("returns false when only REVOKED exists outside the query result", async () => {
    const { service } = buildService([]);

    await expect(service.check(query, "test-revoked")).resolves.toEqual({
      updateAvailable: false,
    });
  });

  it("returns false for a published release with the same build", async () => {
    const { service } = buildService([release({ buildNumber: 130 })]);

    await expect(service.check(query, "test-same-build")).resolves.toEqual({
      updateAvailable: false,
    });
  });

  it("returns false for a published release with a lower build", async () => {
    const { service } = buildService([release({ buildNumber: 129 })]);

    await expect(service.check(query, "test-lower-build")).resolves.toEqual({
      updateAvailable: false,
    });
  });

  it("returns manifest for a published release with a greater build", async () => {
    const { service } = buildService([release()]);

    await expect(service.check(query, "test-greater-build")).resolves.toEqual({
      updateAvailable: true,
      version: "1.0.7",
      buildNumber: 131,
      fileName: "Fullpos-Setup-1.0.7+131.exe",
      fileSize: 123456789,
      sha256: validSha,
      downloadUrl: "https://downloads.example.com/Fullpos-Setup-1.0.7+131.exe",
      mandatory: false,
      minimumSupportedBuild: null,
      releaseNotes: [],
      publishedAt: "2026-10-06T12:00:00.000Z",
    });
  });

  it("chooses the greatest published build returned by Prisma ordering", async () => {
    const { service } = buildService([
      release({ buildNumber: 140, version: "1.0.9" }),
      release({ buildNumber: 131, version: "1.0.7" }),
    ]);

    await expect(service.check(query, "test-greatest")).resolves.toMatchObject({
      updateAvailable: true,
      buildNumber: 140,
      version: "1.0.9",
    });
  });

  it("skips a revoked greater build because revoked releases are not queried", async () => {
    const { service, findMany } = buildService([release({ buildNumber: 131 })]);

    await expect(service.check(query, "test-revoked-greater")).resolves.toMatchObject({
      updateAvailable: true,
      buildNumber: 131,
    });
    expect(findMany.mock.calls[0][0].where.status).toBe(AppReleaseStatus.PUBLISHED);
  });

  it("does not mix platforms", async () => {
    const { service, findMany } = buildService([]);

    await service.check({ ...query, platform: "android" }, "test-platform");

    expect(findMany.mock.calls[0][0].where.platform).toBe(AppReleasePlatform.ANDROID);
  });

  it("does not mix channels", async () => {
    const { service, findMany } = buildService([]);

    await service.check({ ...query, channel: "beta" }, "test-channel");

    expect(findMany.mock.calls[0][0].where.channel).toBe(AppReleaseChannel.BETA);
  });

  it("does not return a release with invalid sha256", async () => {
    const { service } = buildService([release({ sha256: "nope" })]);

    await expect(service.check(query, "test-invalid-sha")).resolves.toEqual({
      updateAvailable: false,
    });
  });

  it("does not return a release with a non-https download URL", async () => {
    const { service } = buildService([
      release({ downloadUrl: "http://downloads.example.com/setup.exe" }),
    ]);

    await expect(service.check(query, "test-http-url")).resolves.toEqual({
      updateAvailable: false,
    });
  });

  it("does not return a release with fileSize <= 0", async () => {
    const { service } = buildService([release({ fileSize: BigInt(0) })]);

    await expect(service.check(query, "test-file-size")).resolves.toEqual({
      updateAvailable: false,
    });
  });

  it("does not expose internal fields in the manifest", async () => {
    const { service } = buildService([release()]);

    const result = await service.check(query, "test-public-response");

    expect(result).not.toHaveProperty("id");
    expect(result).not.toHaveProperty("status");
    expect(result).not.toHaveProperty("platform");
    expect(result).not.toHaveProperty("channel");
    expect(result).not.toHaveProperty("createdAt");
    expect(result).not.toHaveProperty("updatedAt");
  });
});
