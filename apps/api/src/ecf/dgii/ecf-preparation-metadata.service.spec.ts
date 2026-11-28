import { ConfigService } from "@nestjs/config";
import { Logger } from "@nestjs/common";
import { EcfPreparationMetadataService } from "./ecf-preparation-metadata.service";
import { R2Service } from "../../storage/r2.service";

describe("welcome tutorial metadata", () => {
  const key = "uploads/tutorials/ecf/tutorial-example.mp4";
  function setup(values: Record<string, string> = {}) {
    const sign = jest.fn().mockResolvedValue("https://example.test/tutorial.mp4");
    const service = new EcfPreparationMetadataService(
      new ConfigService(values),
      { createPresignedGetUrl: sign } as unknown as R2Service,
    );
    return { service, sign };
  }

  it("preserves existing HTTPS configuration and avoids signing", async () => {
    const { service, sign } = setup({ ECF_HABILITATION_VIDEO_URL: "https://example.test/existing.mp4", ECF_HABILITATION_VIDEO_OBJECT_KEY: key });
    expect((await service.get("company-a")).videoUrl).toBe("https://example.test/existing.mp4");
    expect(sign).not.toHaveBeenCalled();
  });

  it("signs only the configured global tutorial again on every metadata request", async () => {
    const { service, sign } = setup({ ECF_HABILITATION_VIDEO_OBJECT_KEY: key });
    sign.mockResolvedValueOnce("https://example.test/first.mp4").mockResolvedValueOnce("https://example.test/second.mp4");
    expect((await service.get("company-a")).videoUrl).toBe("https://example.test/first.mp4");
    expect((await service.get("company-b")).videoUrl).toBe("https://example.test/second.mp4");
    expect(sign).toHaveBeenNthCalledWith(1, { objectKey: key, expiresInSeconds: 86400 });
    expect(sign).toHaveBeenCalledTimes(2);
  });

  it.each(["", "uploads/companies/a/private.mp4", "uploads/tutorials/ecf/../private.mp4", "uploads/tutorials/ecf/file.mp4?key=x", "uploads/tutorials/ecf/certificate.pdf"])("rejects non-tutorial keys: %s", async (objectKey) => {
    const { service, sign } = setup({ ECF_HABILITATION_VIDEO_OBJECT_KEY: objectKey });
    expect((await service.get("company-a")).videoUrl).toBeNull();
    expect(sign).not.toHaveBeenCalled();
  });

  it("does not expose signing errors or block onboarding", async () => {
    const warn = jest.spyOn(Logger.prototype, "warn").mockImplementation();
    try {
      const { service, sign } = setup({ ECF_HABILITATION_VIDEO_OBJECT_KEY: key });
      sign.mockRejectedValue(new Error("sensitive SDK details"));
      expect((await service.get("company-a")).videoUrl).toBeNull();
      expect(JSON.stringify(warn.mock.calls)).not.toContain("sensitive SDK details");
    } finally { warn.mockRestore(); }
  });

  it("keeps simulation scoped to its configured company", async () => {
    const { service } = setup({ ECF_HABILITATION_VIDEO_OBJECT_KEY: key, ECF_CERTIFICATION_ORCHESTRATOR: "enabled", ALANUBE_ENV: "sandbox", ECF_ACTIVATION_TRANSPORT: "simulated", ECF_SIMULATION_COMPANY_ID: "company-a" });
    expect((await service.get("company-a")).simulation.available).toBe(true);
    expect((await service.get("company-b")).simulation.available).toBe(false);
  });
});
