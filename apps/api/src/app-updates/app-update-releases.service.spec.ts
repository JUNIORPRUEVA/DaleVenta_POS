import {
  AppReleaseChannel,
  AppReleasePlatform,
  AppReleaseStatus,
  Role,
} from "@prisma/client";
import { GUARDS_METADATA } from "@nestjs/common/constants";
import { AuthGuard } from "@nestjs/passport";
import { ROLES_KEY } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import { AppUpdateReleasesController } from "./app-update-releases.controller";
import { AppUpdatesService } from "./app-updates.service";

const validSha = "b".repeat(64);
const now = new Date("2026-10-06T12:00:00.000Z");

function draft(overrides: Record<string, unknown> = {}) {
  return {
    id: `release-${Math.random().toString(16).slice(2)}`,
    platform: AppReleasePlatform.WINDOWS,
    channel: AppReleaseChannel.STABLE,
    version: "1.0.7",
    buildNumber: 131,
    status: AppReleaseStatus.DRAFT,
    mandatory: false,
    minimumSupportedBuild: null,
    fileName: "Fullpos-Setup-1.0.7+131.exe",
    fileSize: BigInt(123456789),
    sha256: validSha,
    downloadUrl: "https://downloads.example.com/Fullpos-Setup-1.0.7+131.exe",
    storageKey: "releases/windows/stable/1.0.7-131/Fullpos-Setup-1.0.7+131.exe",
    releaseNotes: [],
    publishedAt: null,
    revokedAt: null,
    storageDeletedAt: null,
    commitSha: "abcdef1",
    signed: true,
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}

function createDto(overrides: Record<string, unknown> = {}) {
  return {
    platform: "windows" as const,
    channel: "stable" as const,
    version: "1.0.7",
    buildNumber: 131,
    fileName: "Fullpos-Setup-1.0.7+131.exe",
    fileSize: 123456789,
    sha256: validSha,
    downloadUrl: "https://downloads.example.com/Fullpos-Setup-1.0.7+131.exe",
    storageKey: "releases/windows/stable/1.0.7-131/Fullpos-Setup-1.0.7+131.exe",
    releaseNotes: [],
    commitSha: "abcdef1",
    signed: true,
    ...overrides,
  };
}

function buildService(initial: ReturnType<typeof draft>[] = [], env: Record<string, string> = {}) {
  let sequence = 1;
  const rows = initial.map((item) => ({ ...item }));

  const matchesWhere = (row: any, where: any = {}) => {
    if (where.id && typeof where.id === "string" && row.id !== where.id) return false;
    if (where.id?.not && row.id === where.id.not) return false;
    if (where.platform && row.platform !== where.platform) return false;
    if (where.channel && row.channel !== where.channel) return false;
    if (where.status?.in && !where.status.in.includes(row.status)) return false;
    if (where.status && !where.status.in && row.status !== where.status) return false;
    if (where.buildNumber && row.buildNumber !== where.buildNumber) return false;
    if (Object.prototype.hasOwnProperty.call(where, "storageDeletedAt")) {
      if (row.storageDeletedAt !== where.storageDeletedAt) return false;
    }
    return true;
  };

  const appRelease = {
    findFirst: jest.fn(async ({ where }: any) => rows.find((row) => matchesWhere(row, where)) ?? null),
    findMany: jest.fn(async ({ where }: any = {}) =>
      rows
        .filter((row) => matchesWhere(row, where))
        .sort((a, b) => b.buildNumber - a.buildNumber),
    ),
    findUnique: jest.fn(async ({ where }: any) => rows.find((row) => row.id === where.id) ?? null),
    findUniqueOrThrow: jest.fn(async ({ where }: any) => {
      const row = rows.find((item) => item.id === where.id);
      if (!row) throw new Error("not found");
      return row;
    }),
    create: jest.fn(async ({ data }: any) => {
      const row = {
        ...draft(),
        ...data,
        id: `created-${sequence++}`,
        fileSize: BigInt(data.fileSize),
        createdAt: now,
        updatedAt: now,
      };
      rows.push(row);
      return row;
    }),
    update: jest.fn(async ({ where, data }: any) => {
      const row = rows.find((item) => item.id === where.id);
      if (!row) throw new Error("not found");
      Object.assign(row, data, { updatedAt: now });
      return row;
    }),
    updateMany: jest.fn(async ({ where, data }: any) => {
      const affected = rows.filter((row) => matchesWhere(row, where));
      for (const row of affected) Object.assign(row, data, { updatedAt: now });
      return { count: affected.length };
    }),
  };

  const prisma = {
    appRelease,
    $transaction: jest.fn(async (callback: (tx: unknown) => unknown) => callback(prisma)),
  };
  const r2 = { deleteObject: jest.fn(async () => ({ ok: true })) };
  const service = new AppUpdatesService(prisma as any, {
    get: jest.fn((key: string) => env[key]),
  } as any, r2 as any);

  jest.spyOn((service as any).logger, "log").mockImplementation(() => undefined);
  jest.spyOn((service as any).logger, "error").mockImplementation(() => undefined);

  return { service, prisma, rows, r2 };
}

describe("App release administration", () => {
  it("creates a DRAFT release", async () => {
    const { service } = buildService();

    await expect(service.createRelease(createDto())).resolves.toMatchObject({
      platform: "windows",
      channel: "stable",
      status: "draft",
      buildNumber: 131,
    });
  });

  it("rejects invalid SHA metadata", async () => {
    const { service } = buildService();

    await expect(service.createRelease(createDto({ sha256: "bad" }) as any)).rejects.toThrow(
      "sha256",
    );
  });

  it("rejects non-HTTPS download URLs", async () => {
    const { service } = buildService();

    await expect(
      service.createRelease(createDto({ downloadUrl: "http://downloads.example.com/setup.exe" })),
    ).rejects.toThrow("HTTPS");
  });

  it("rejects fileSize zero", async () => {
    const { service } = buildService();

    await expect(service.createRelease(createDto({ fileSize: 0 }))).rejects.toThrow("fileSize");
  });

  it("rejects duplicate platform/channel/build", async () => {
    const { service } = buildService([draft({ id: "existing" })]);

    await expect(service.createRelease(createDto())).rejects.toThrow("Ya existe");
  });

  it("rejects path traversal file names", async () => {
    const { service } = buildService();

    await expect(service.createRelease(createDto({ fileName: "../setup.exe" }))).rejects.toThrow(
      "fileName",
    );
  });

  it("edits a draft release", async () => {
    const { service } = buildService([draft({ id: "draft-1" })]);

    await expect(
      service.updateRelease("draft-1", { version: "1.0.8", buildNumber: 132 }),
    ).resolves.toMatchObject({
      version: "1.0.8",
      buildNumber: 132,
      status: "draft",
    });
  });

  it("rejects editing a published release", async () => {
    const { service } = buildService([
      draft({ id: "published-1", status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
    ]);

    await expect(service.updateRelease("published-1", { version: "1.0.8" })).rejects.toThrow(
      "DRAFT",
    );
  });

  it("publishes a draft release", async () => {
    const { service } = buildService([draft({ id: "draft-1", signed: false })]);

    await expect(service.publishRelease("draft-1")).resolves.toMatchObject({
      id: "draft-1",
      status: "published",
      publishedAt: expect.any(String),
    });
  });

  it("rejects double publish", async () => {
    const { service } = buildService([
      draft({ id: "published-1", status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
    ]);

    await expect(service.publishRelease("published-1")).rejects.toThrow("ya fue publicado");
  });

  it("enforces signed policy when configured", async () => {
    const { service } = buildService([draft({ id: "draft-1", signed: false })], {
      REQUIRE_SIGNED_APP_RELEASES: "true",
    });

    await expect(service.publishRelease("draft-1")).rejects.toThrow("firmados");
  });

  it("revokes a published release", async () => {
    const { service } = buildService([
      draft({ id: "published-1", status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
    ]);

    await expect(service.revokeRelease("published-1")).resolves.toMatchObject({
      id: "published-1",
      status: "revoked",
      revokedAt: expect.any(String),
    });
  });

  it("rejects double revoke", async () => {
    const { service } = buildService([
      draft({ id: "revoked-1", status: AppReleaseStatus.REVOKED, revokedAt: now }),
    ]);

    await expect(service.revokeRelease("revoked-1")).rejects.toThrow("ya fue revocado");
  });

  it("rejects revoking drafts", async () => {
    const { service } = buildService([draft({ id: "draft-1" })]);

    await expect(service.revokeRelease("draft-1")).rejects.toThrow("DRAFT");
  });

  it("lists releases with filters", async () => {
    const { service } = buildService([
      draft({ id: "stable", channel: AppReleaseChannel.STABLE }),
      draft({ id: "beta", channel: AppReleaseChannel.BETA }),
    ]);

    await expect(service.listReleases({ channel: "beta" })).resolves.toEqual([
      expect.objectContaining({ id: "beta", channel: "beta" }),
    ]);
  });

  it("returns release detail", async () => {
    const { service } = buildService([draft({ id: "draft-1" })]);

    await expect(service.getRelease("draft-1")).resolves.toMatchObject({
      id: "draft-1",
      buildNumber: 131,
    });
  });

  it("published releases appear in public check", async () => {
    const { service } = buildService([
      draft({ id: "published-1", status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
    ]);

    await expect(
      service.check(
        { platform: "windows", channel: "stable", version: "1.0.6", build: 130 },
        "published-check",
      ),
    ).resolves.toMatchObject({
      updateAvailable: true,
      buildNumber: 131,
    });
  });

  it("revoked releases disappear from public check", async () => {
    const { service } = buildService([
      draft({ id: "revoked-1", status: AppReleaseStatus.REVOKED, revokedAt: now }),
    ]);

    await expect(
      service.check(
        { platform: "windows", channel: "stable", version: "1.0.6", build: 130 },
        "revoked-check",
      ),
    ).resolves.toEqual({ updateAvailable: false });
  });

  it("publish retention keeps current and previous, deletes only the third-oldest exact key", async () => {
    const { service, rows, r2 } = buildService([
      draft({
        id: "release-133",
        buildNumber: 133,
        status: AppReleaseStatus.DRAFT,
        fileName: "Fullpos-Setup-1.0.7+133.exe",
        storageKey: "releases/windows/stable/1.0.7-133/Fullpos-Setup-1.0.7+133.exe",
      }),
      draft({
        id: "release-132",
        buildNumber: 132,
        status: AppReleaseStatus.PUBLISHED,
        publishedAt: now,
        fileName: "Fullpos-Setup-1.0.7+132.exe",
        storageKey: "releases/windows/stable/1.0.7-132/Fullpos-Setup-1.0.7+132.exe",
      }),
      draft({
        id: "release-131",
        buildNumber: 131,
        status: AppReleaseStatus.PUBLISHED,
        publishedAt: now,
        fileName: "Fullpos-Setup-1.0.7+131.exe",
        storageKey: "releases/windows/stable/1.0.7-131/Fullpos-Setup-1.0.7+131.exe",
      }),
    ]);

    const result = await service.publishRelease("release-133");

    expect(result).toMatchObject({
      id: "release-133",
      status: "published",
      retention: {
        dryRun: false,
        status: "COMPLETE",
        keep: [
          expect.objectContaining({ buildNumber: 133, action: "keep" }),
          expect.objectContaining({ buildNumber: 132, action: "keep" }),
        ],
        candidates: [expect.objectContaining({ buildNumber: 131, action: "deleted" })],
      },
    });
    expect(r2.deleteObject).toHaveBeenCalledWith(
      "releases/windows/stable/1.0.7-131/Fullpos-Setup-1.0.7+131.exe",
    );
    expect(r2.deleteObject).toHaveBeenCalledTimes(1);
    expect(rows.find((row) => row.id === "release-131")).toMatchObject({
      status: AppReleaseStatus.ARCHIVED,
      storageDeletedAt: expect.any(Date),
    });
    expect(rows.find((row) => row.id === "release-132")?.status).toBe(
      AppReleaseStatus.PUBLISHED,
    );
    expect(rows.find((row) => row.id === "release-133")?.status).toBe(
      AppReleaseStatus.PUBLISHED,
    );
  });

  it("retention dry-run reports delete candidates without deleting or archiving", async () => {
    const { service, rows, r2 } = buildService([
      draft({ id: "release-133", buildNumber: 133, status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
      draft({ id: "release-132", buildNumber: 132, status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
      draft({ id: "release-131", buildNumber: 131, status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
    ]);

    const result = await service.applyWindowsStableRetention({ dryRun: true });

    expect(result).toMatchObject({
      dryRun: true,
      status: "DRY_RUN",
      candidates: [expect.objectContaining({ buildNumber: 131, action: "delete-candidate" })],
    });
    expect(r2.deleteObject).not.toHaveBeenCalled();
    expect(rows.find((row) => row.id === "release-131")?.status).toBe(
      AppReleaseStatus.PUBLISHED,
    );
  });

  it("publish failure does not run retention cleanup", async () => {
    const { service, r2 } = buildService([
      draft({ id: "published-1", status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
    ]);

    await expect(service.publishRelease("published-1")).rejects.toThrow("ya fue publicado");
    expect(r2.deleteObject).not.toHaveBeenCalled();
  });

  it("storage delete failure keeps the new current published and reports partial cleanup", async () => {
    const { service, rows, r2 } = buildService([
      draft({
        id: "release-133",
        buildNumber: 133,
        status: AppReleaseStatus.DRAFT,
        fileName: "Fullpos-Setup-1.0.7+133.exe",
        storageKey: "releases/windows/stable/1.0.7-133/Fullpos-Setup-1.0.7+133.exe",
      }),
      draft({ id: "release-132", buildNumber: 132, status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
      draft({ id: "release-131", buildNumber: 131, status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
    ]);
    r2.deleteObject.mockRejectedValueOnce(new Error("R2 down"));

    const result = await service.publishRelease("release-133");

    expect(result).toMatchObject({
      status: "published",
      retention: {
        status: "PARTIAL",
        candidates: [expect.objectContaining({ buildNumber: 131, action: "failed" })],
      },
    });
    expect(rows.find((row) => row.id === "release-133")?.status).toBe(
      AppReleaseStatus.PUBLISHED,
    );
    expect(rows.find((row) => row.id === "release-131")?.status).toBe(
      AppReleaseStatus.PUBLISHED,
    );
  });

  it("retention never deletes DRAFT, other platform, other channel, current or previous", async () => {
    const { service, r2 } = buildService([
      draft({ id: "win-134", buildNumber: 134, status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
      draft({ id: "win-133", buildNumber: 133, status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
      draft({ id: "win-draft", buildNumber: 132, status: AppReleaseStatus.DRAFT }),
      draft({
        id: "android-130",
        platform: AppReleasePlatform.ANDROID,
        buildNumber: 130,
        status: AppReleaseStatus.PUBLISHED,
        publishedAt: now,
      }),
      draft({
        id: "beta-129",
        channel: AppReleaseChannel.BETA,
        buildNumber: 129,
        status: AppReleaseStatus.PUBLISHED,
        publishedAt: now,
      }),
    ]);

    const result = await service.applyWindowsStableRetention({ dryRun: false });

    expect(result).toMatchObject({ status: "COMPLETE", candidates: [] });
    expect(r2.deleteObject).not.toHaveBeenCalled();
  });

  it("retention skips unsafe or missing storage keys instead of deleting by prefix", async () => {
    const { service, r2 } = buildService([
      draft({ id: "release-133", buildNumber: 133, status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
      draft({ id: "release-132", buildNumber: 132, status: AppReleaseStatus.PUBLISHED, publishedAt: now }),
      draft({
        id: "release-131",
        buildNumber: 131,
        status: AppReleaseStatus.PUBLISHED,
        publishedAt: now,
        storageKey: "uploads/companies/company-a/not-a-release.exe",
      }),
    ]);

    const result = await service.applyWindowsStableRetention({ dryRun: false });

    expect(result).toMatchObject({
      status: "PARTIAL",
      candidates: [expect.objectContaining({ buildNumber: 131, action: "skipped" })],
    });
    expect(r2.deleteObject).not.toHaveBeenCalled();
  });

  it("protects admin release routes with JWT roles", () => {
    const guards = Reflect.getMetadata(GUARDS_METADATA, AppUpdateReleasesController);
    const roles = Reflect.getMetadata(ROLES_KEY, AppUpdateReleasesController);

    expect(guards).toEqual(expect.arrayContaining([expect.any(Function), RolesGuard]));
    expect(guards[0]).toBe(AuthGuard("jwt"));
    expect(roles).toEqual([Role.ADMIN]);
  });
});
