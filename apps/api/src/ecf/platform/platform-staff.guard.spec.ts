import { ForbiddenException } from "@nestjs/common";
import {
  PlatformStaffGuard,
  parsePlatformStaffIds,
} from "./platform-staff.guard";

function contextFor(user: unknown) {
  return {
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
  } as never;
}

function configWith(value?: string) {
  return { get: () => value } as never;
}

describe("guard de personal de plataforma", () => {
  it("normaliza la lista de identificadores", () => {
    const ids = parsePlatformStaffIds(" A, b ,, C ,,a ");
    expect([...ids].sort()).toEqual(["a", "b", "c"]);
  });

  it("una variable ausente no concede nada (fail-closed)", () => {
    expect(parsePlatformStaffIds(undefined).size).toBe(0);
    expect(parsePlatformStaffIds("").size).toBe(0);
    expect(parsePlatformStaffIds("  ,  ").size).toBe(0);
  });

  it("sin usuario autenticado rechaza", () => {
    const guard = new PlatformStaffGuard(configWith("user-a"));
    expect(() => guard.canActivate(contextFor(undefined))).toThrow(
      ForbiddenException,
    );
  });

  it("con la lista vacía rechaza aunque haya usuario", () => {
    const guard = new PlatformStaffGuard(configWith(""));
    expect(() => guard.canActivate(contextFor({ id: "user-a" }))).toThrow(
      ForbiddenException,
    );
  });

  it("rechaza a un usuario que no está en la lista", () => {
    const guard = new PlatformStaffGuard(configWith("user-a,user-b"));
    expect(() => guard.canActivate(contextFor({ id: "user-z" }))).toThrow(
      ForbiddenException,
    );
  });

  it("acepta al personal listado, sin distinguir mayúsculas", () => {
    const guard = new PlatformStaffGuard(configWith("USER-A, user-b"));
    expect(guard.canActivate(contextFor({ id: "user-a" }))).toBe(true);
  });

  it("el rol de empresa no influye: un ADMIN no listado es rechazado", () => {
    const guard = new PlatformStaffGuard(configWith("user-a"));
    expect(() =>
      guard.canActivate(contextFor({ id: "admin-de-otra-empresa", role: "ADMIN" })),
    ).toThrow(ForbiddenException);
  });
});
