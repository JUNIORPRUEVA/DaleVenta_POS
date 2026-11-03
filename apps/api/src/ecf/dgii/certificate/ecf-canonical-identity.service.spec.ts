import { EcfCanonicalIdentityService } from "./ecf-canonical-identity.service";

/**
 * Identidad canónica del expediente.
 *
 * Regla que estas pruebas protegen: la cédula del representante legal es un dato
 * del BACKEND (configuración fiscal de la empresa). Si no se recuperaba, un
 * certificado legítimo emitido a la persona que representa a la empresa se
 * rechazaba por identidad.
 */

type SnapshotRow = { payload: unknown } | null;
type ConfigRow = {
  rnc: string;
  companyName: string;
  legalRepresentativeName: string;
  legalRepresentativeCedula: string;
} | null;

function build(snapshot: SnapshotRow, config: ConfigRow) {
  const findSnapshot = jest.fn().mockResolvedValue(snapshot);
  const findConfig = jest.fn().mockResolvedValue(config);
  const prisma = {
    ecfDgiiApplicationSnapshot: { findFirst: findSnapshot },
    appConfig: { findFirst: findConfig },
  };
  return {
    service: new EcfCanonicalIdentityService(prisma as never),
    findSnapshot,
    findConfig,
  };
}

const EMPTY_CONFIG: ConfigRow = {
  rnc: "",
  companyName: "",
  legalRepresentativeName: "",
  legalRepresentativeCedula: "",
};

const COMPANY_ID = "165e3fca-6225-479b-8805-d2205f10536c";

describe("identidad canónica — configuración fiscal", () => {
  it("recupera la cédula del representante legal cuando no hay expediente enviado", async () => {
    const { service } = build(null, {
      rnc: "133020232",
      companyName: "FULLTECH SRL",
      legalRepresentativeName: "JUAN PEREZ GOMEZ",
      legalRepresentativeCedula: "001-1234567-8",
    });

    const identity = await service.resolve(COMPANY_ID);

    expect(identity.taxId).toBe("133020232");
    expect(identity.legalName).toBe("FULLTECH SRL");
    expect(identity.representativeName).toBe("JUAN PEREZ GOMEZ");
    // Este es el arreglo: antes era `null` y el certificado personal se rechazaba.
    expect(identity.representativeId).toBe("001-1234567-8");
    expect(identity.source).toBe("FISCAL_CONFIG");
    expect(identity.representativeIdSource).toBe("FISCAL_CONFIG");
    expect(identity.missing).toEqual([]);
  });

  it("declara qué falta cuando la empresa no tiene cédula registrada", async () => {
    const { service } = build(null, {
      rnc: "133020232",
      companyName: "FULLTECH SRL",
      legalRepresentativeName: "JUAN PEREZ GOMEZ",
      legalRepresentativeCedula: "",
    });

    const identity = await service.resolve(COMPANY_ID);

    expect(identity.representativeId).toBeNull();
    expect(identity.missing).toEqual(["representative.identification"]);
  });

  it("no inventa datos cuando no hay nada registrado", async () => {
    const { service } = build(null, EMPTY_CONFIG);

    const identity = await service.resolve(COMPANY_ID);

    expect(identity).toMatchObject({
      taxId: null,
      legalName: null,
      representativeName: null,
      representativeId: null,
      source: "NONE",
      representativeIdSource: "NONE",
    });
    expect(identity.missing).toEqual([
      "company.rnc",
      "representative.identification",
    ]);
  });
});

describe("identidad canónica — expediente enviado", () => {
  it("da prioridad a los datos del expediente sobre la configuración fiscal", async () => {
    const { service } = build(
      {
        payload: {
          company: { rnc: "133020232", legalName: "FULLTECH SRL" },
          representative: {
            fullName: "JUAN PEREZ GOMEZ",
            identification: "001-1234567-8",
          },
        },
      },
      {
        rnc: "999999999",
        companyName: "OTRO NOMBRE",
        legalRepresentativeName: "OTRA PERSONA",
        legalRepresentativeCedula: "402-0000000-0",
      },
    );

    const identity = await service.resolve(COMPANY_ID);

    expect(identity.taxId).toBe("133020232");
    expect(identity.representativeId).toBe("001-1234567-8");
    expect(identity.source).toBe("APPLICATION_SNAPSHOT");
    expect(identity.representativeIdSource).toBe("APPLICATION_SNAPSHOT");
  });

  it("completa campo por campo: expediente sin cédula + configuración con cédula", async () => {
    // Caso real del piloto: el expediente se envió sin la cédula del
    // representante, pero la empresa sí la tiene guardada en su configuración.
    const { service } = build(
      {
        payload: {
          company: { rnc: "133020232", legalName: "FULLTECH SRL" },
          representative: { fullName: "JUAN PEREZ GOMEZ" },
        },
      },
      {
        rnc: "133020232",
        companyName: "FULLTECH SRL",
        legalRepresentativeName: "JUAN PEREZ GOMEZ",
        legalRepresentativeCedula: "001-1234567-8",
      },
    );

    const identity = await service.resolve(COMPANY_ID);

    expect(identity.taxId).toBe("133020232");
    expect(identity.representativeId).toBe("001-1234567-8");
    expect(identity.source).toBe("APPLICATION_SNAPSHOT");
    expect(identity.representativeIdSource).toBe("FISCAL_CONFIG");
    expect(identity.missing).toEqual([]);
  });

  it("solo consulta la empresa indicada", async () => {
    const { service, findSnapshot, findConfig } = build(null, EMPTY_CONFIG);

    await service.resolve(COMPANY_ID);

    expect(findSnapshot).toHaveBeenCalledWith(
      expect.objectContaining({ where: { companyId: COMPANY_ID } }),
    );
    expect(findConfig).toHaveBeenCalledWith(
      expect.objectContaining({ where: { companyId: COMPANY_ID } }),
    );
  });

  it("ignora un payload que no es un objeto", async () => {
    const { service } = build(
      { payload: "no-es-un-objeto" },
      { ...EMPTY_CONFIG, rnc: "133020232" },
    );

    const identity = await service.resolve(COMPANY_ID);

    expect(identity.taxId).toBe("133020232");
    expect(identity.representativeId).toBeNull();
  });
});
