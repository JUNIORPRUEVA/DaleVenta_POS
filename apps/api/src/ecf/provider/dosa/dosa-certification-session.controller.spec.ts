import { ConflictException } from "@nestjs/common";
import type { Request } from "express";

import { PERMISSIONS_KEY } from "../../../auth/roles.decorator";
import type { TenantUser } from "../../../auth/tenant-context";
import { DosaCertificationSessionController } from "./dosa-certification-session.controller";
import type {
  DosaCertificationSessionService,
  DosaSessionOpenResult,
} from "./dosa-certification-session.service";

const SUCCESS: DosaSessionOpenResult = {
  ok: true,
  sessionUrl: "https://dosasystem.com/sesion/abc",
  expiresAt: new Date(Date.now() + 3600_000).toISOString(),
  attemptNo: 1,
  providerPostulationId: "post-1",
  reused: false,
};

function request(companyId: string): Request {
  return {
    user: { id: "user-1", companyId, role: "ADMIN" } as unknown as TenantUser,
  } as unknown as Request;
}

function controllerWith(
  open: (input: { companyId: string; userId?: string | null }) => Promise<DosaSessionOpenResult>,
) {
  const service = { open } as unknown as DosaCertificationSessionService;
  return new DosaCertificationSessionController(service);
}

describe("DosaCertificationSessionController", () => {
  it("exige el permiso administrativo manageEcfOnboarding", () => {
    const permissions = Reflect.getMetadata(
      PERMISSIONS_KEY,
      DosaCertificationSessionController.prototype.open,
    );
    expect(permissions).toEqual(["manageEcfOnboarding"]);
  });

  it("la empresa sale del token y se devuelve en la respuesta", async () => {
    const seen: string[] = [];
    const controller = controllerWith(async (input) => {
      seen.push(input.companyId);
      return SUCCESS;
    });

    const response = await controller.open(request("company-a"));

    expect(seen).toEqual(["company-a"]);
    expect(response.companyId).toBe("company-a");
    expect(response.sessionUrl).toBe(SUCCESS.ok ? SUCCESS.sessionUrl : "");
    expect(response.fiscalAuthorizationGranted).toBe(false);
  });

  it("doble clic: la segunda petición simultánea se rechaza como IN_PROGRESS", async () => {
    let release!: (value: DosaSessionOpenResult) => void;
    const pending = new Promise<DosaSessionOpenResult>((resolve) => {
      release = resolve;
    });
    const controller = controllerWith(() => pending);

    const first = controller.open(request("company-a"));
    await expect(controller.open(request("company-a"))).rejects.toBeInstanceOf(
      ConflictException,
    );
    release(SUCCESS);
    await expect(first).resolves.toMatchObject({ ok: true });
  });

  it("empresa sin correo: responde 409 con el código del dominio", async () => {
    const controller = controllerWith(async () => ({
      ok: false,
      code: "ECF_DOSA_SESSION_EMAIL_REQUIRED",
      message: "falta correo",
    }));

    await expect(controller.open(request("company-a"))).rejects.toMatchObject({
      response: { message: "ECF_DOSA_SESSION_EMAIL_REQUIRED" },
      status: 409,
    });
  });
});
