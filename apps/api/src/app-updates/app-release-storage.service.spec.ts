import { AppReleaseStorageService } from "./app-release-storage.service";

describe("AppReleaseStorageService download URLs", () => {
  const release = {
    storageKey: "releases/windows/stable/1.0.6-143/FullPOS-Setup-1.0.6-143.exe",
    fileName: "FullPOS-Setup-1.0.6-143.exe",
    downloadUrl: "https://storage.example.test/expired",
  };

  function setup(env: Record<string, string> = {}) {
    const createPresignedGetUrl = jest.fn()
      .mockResolvedValueOnce("https://storage.example.test/fresh-first")
      .mockResolvedValueOnce("https://storage.example.test/fresh-second");
    const service = new AppReleaseStorageService(
      { get: (key: string) => env[key] } as any,
      { createPresignedGetUrl } as any,
    );
    return { service, createPresignedGetUrl };
  }

  it("signs a fresh URL on every check instead of reusing the stored expired URL", async () => {
    const { service, createPresignedGetUrl } = setup();
    await expect(service.resolveDownloadUrl(release)).resolves.toBe("https://storage.example.test/fresh-first");
    await expect(service.resolveDownloadUrl(release)).resolves.toBe("https://storage.example.test/fresh-second");
    expect(createPresignedGetUrl).toHaveBeenCalledTimes(2);
    expect(createPresignedGetUrl).toHaveBeenCalledWith({ objectKey: release.storageKey, expiresInSeconds: 604800 });
  });

  it("preserves legacy releases without a storage key", async () => {
    const { service, createPresignedGetUrl } = setup();
    await expect(service.resolveDownloadUrl({ ...release, storageKey: null })).resolves.toBe(release.downloadUrl);
    expect(createPresignedGetUrl).not.toHaveBeenCalled();
  });

  it("preserves local-storage download URLs", async () => {
    const { service, createPresignedGetUrl } = setup({ FULLPOS_RELEASE_STORAGE_MODE: "local", FULLPOS_RELEASE_STORAGE_ROOT: "/releases" });
    await expect(service.resolveDownloadUrl(release)).resolves.toBe(release.downloadUrl);
    expect(createPresignedGetUrl).not.toHaveBeenCalled();
  });

  it.each(["uploads/companies/private/file.exe", "releases/windows/../private/file.exe", "releases/windows/wrong-file.exe"])("refuses non-release objects: %s", async storageKey => {
    const { service, createPresignedGetUrl } = setup();
    await expect(service.resolveDownloadUrl({ ...release, storageKey })).rejects.toThrow("Invalid Windows release storage key.");
    expect(createPresignedGetUrl).not.toHaveBeenCalled();
  });
});
