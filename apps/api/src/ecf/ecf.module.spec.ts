import { Global, Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Test } from "@nestjs/testing";
import { PrismaService } from "../prisma/prisma.service";
import { EcfModule } from "./ecf.module";
import { EcfSecretResolverService } from "./ecf-secret-resolver.service";

@Global()
@Module({
  providers: [
    { provide: ConfigService, useValue: new ConfigService({ ALANUBE_ENV: "sandbox", ALANUBE_ENABLE_REAL_CALLS: "false" }) },
    { provide: PrismaService, useValue: {} },
  ],
  exports: [ConfigService, PrismaService],
})
class OfflineDependencies {}

describe("EcfModule dependency composition", () => {
  it("constructs the real module without attempting to inject the optional provider array", async () => {
    const network = jest.spyOn(globalThis, "fetch").mockRejectedValue(new Error("No network allowed"));
    const module = await Test.createTestingModule({ imports: [OfflineDependencies, EcfModule] }).compile();
    try {
      const resolver = module.get(EcfSecretResolverService);
      expect(await resolver.inspect("env://ECF_SYNTHETIC_ABSENT_CREDENTIAL", { environment: "sandbox" }))
        .toMatchObject({ referenceConfigured: true, credentialFound: false });
      await expect(resolver.resolve("env://ECF_SYNTHETIC_ABSENT_CREDENTIAL", { environment: "production" }))
        .rejects.toMatchObject({ code: "PRODUCTION_BLOCKED" });
      expect(network).not.toHaveBeenCalled();
    } finally { await module.close(); network.mockRestore(); }
  });
});
