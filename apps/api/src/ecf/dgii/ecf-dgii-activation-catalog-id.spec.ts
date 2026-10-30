import { ECF_DGII_REQUIREMENT_CATALOG } from "./ecf-dgii-habilitation.policy";
import { resolveCatalogEntry } from "./ecf-dgii-activation.policy";

/**
 * Identificadores de paso del motor de activación.
 *
 * El catálogo publica dos nombres por paso (`key` del requisito y `stepKey` de
 * la etapa persistida) y en el primer paso NO coinciden. Estos tests fijan que
 * cualquier nombre que devuelva la API se pueda usar para reintentar, y que se
 * resuelva siempre a la etapa canónica antes de escribir en la base.
 */
describe("motor de activación e-CF — identificadores de paso", () => {
  it("resuelve el requisito FISCAL_DATA a la etapa FISCAL_CONFIG", () => {
    const entry = resolveCatalogEntry("FISCAL_DATA");
    expect(entry).not.toBeNull();
    expect(entry?.key).toBe("FISCAL_DATA");
    expect(entry?.stepKey).toBe("FISCAL_CONFIG");
  });

  it("resuelve la etapa FISCAL_CONFIG al mismo paso que el requisito", () => {
    const byStep = resolveCatalogEntry("FISCAL_CONFIG");
    const byKey = resolveCatalogEntry("FISCAL_DATA");
    expect(byStep).toEqual(byKey);
  });

  it("todos los pasos del catálogo se resuelven por ambos nombres", () => {
    for (const item of ECF_DGII_REQUIREMENT_CATALOG) {
      expect(resolveCatalogEntry(item.key)?.stepKey).toBe(item.stepKey);
      expect(resolveCatalogEntry(item.stepKey)?.key).toBe(item.key);
    }
  });

  it("normaliza mayúsculas y espacios sobrantes", () => {
    expect(resolveCatalogEntry("  fiscal_config ")?.key).toBe("FISCAL_DATA");
  });

  it("devuelve null para un paso desconocido o vacío", () => {
    expect(resolveCatalogEntry("NO_EXISTE")).toBeNull();
    expect(resolveCatalogEntry("   ")).toBeNull();
  });
});
