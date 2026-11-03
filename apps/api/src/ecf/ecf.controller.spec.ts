import { GUARDS_METADATA } from "@nestjs/common/constants";
import { PERMISSIONS_KEY } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import { EcfController } from "./ecf.controller";

describe("EcfController security metadata", () => {
  it("protects endpoints with auth/roles guards and explicit permissions", () => {
    const guards = Reflect.getMetadata(GUARDS_METADATA, EcfController);
    expect(guards).toEqual(expect.arrayContaining([expect.any(Function), RolesGuard]));

    expect(
      Reflect.getMetadata(PERMISSIONS_KEY, EcfController.prototype.getConfig),
    ).toEqual(["viewEcfConfig"]);
    expect(
      Reflect.getMetadata(PERMISSIONS_KEY, EcfController.prototype.updateConfig),
    ).toEqual(["manageEcfConfig"]);
    expect(
      Reflect.getMetadata(PERMISSIONS_KEY, EcfController.prototype.getOnboarding),
    ).toEqual(["viewEcfOnboarding"]);
    expect(
      Reflect.getMetadata(PERMISSIONS_KEY, EcfController.prototype.updateStep),
    ).toEqual(["manageEcfOnboarding"]);
    expect(
      Reflect.getMetadata(PERMISSIONS_KEY, EcfController.prototype.getProviderStatus),
    ).toEqual(["viewEcfConfig"]);
  });
});

