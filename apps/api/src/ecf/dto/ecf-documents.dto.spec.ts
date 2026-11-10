import "reflect-metadata";
import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { EcfElectronicDocumentType } from "@prisma/client";
import {
  DeclareEcfAuthorizedSequenceDto,
  ListEcfDocumentsQueryDto,
  RegisterEcfSequenceDto,
  RenewEcfSequenceDto,
} from "./ecf-documents.dto";
import { ECF_SEQUENCE_TYPES } from "../documents/ecf-dgii-authorized-sequences.policy";
import { ECF_ALLOWED_DOCUMENT_TYPES } from "../ecf.constants";

/**
 * Regresión: `ECF_SEQUENCE_TYPES` (declaración) y `ALLOCATABLE` (servicio) ya
 * incluían E32, pero este DTO solo admitía E31/E34. Declarar la autorización de
 * consumo funcionaba (201) y registrar el rango fallaba con un 400, dejando la
 * factura de consumo sin numeración. El DTO no puede volver a divergir.
 */
describe("RegisterEcfSequenceDto · tipos de comprobante numerables", () => {
  const options = { whitelist: true, forbidNonWhitelisted: true };

  function messages(errors: Array<{ constraints?: Record<string, string> }>) {
    return errors.flatMap((error) =>
      error.constraints ? Object.values(error.constraints) : [],
    );
  }

  function payload(documentType: string) {
    return {
      documentType,
      startNumber: 1,
      endNumber: 1000,
      validUntil: "2027-12-31",
    };
  }

  it.each([...ECF_SEQUENCE_TYPES])("acepta el tipo %s", async (type) => {
    const dto = plainToInstance(RegisterEcfSequenceDto, payload(type));
    const errors = await validate(dto, options);
    expect(messages(errors)).toEqual([]);
  });

  it("acepta E32, el tipo de la factura de consumo", async () => {
    const dto = plainToInstance(RegisterEcfSequenceDto, payload("E32"));
    const errors = await validate(dto, options);
    expect(errors).toHaveLength(0);
    expect(dto.documentType).toBe("E32");
  });

  it("acepta la renovación de un rango E32", async () => {
    const dto = plainToInstance(RenewEcfSequenceDto, payload("E32"));
    const errors = await validate(dto, options);
    expect(errors).toHaveLength(0);
  });

  it("sigue rechazando un tipo que no consume rango e-CF", async () => {
    const dto = plainToInstance(RegisterEcfSequenceDto, payload("E33"));
    const errors = await validate(dto, options);
    expect(messages(errors).join(" ")).toContain("documentType must be one of");
  });

  it("admite el rango sin fecha de vencimiento", async () => {
    const dto = plainToInstance(RegisterEcfSequenceDto, {
      documentType: "E32",
      startNumber: 1,
      endNumber: 1000,
    });
    const errors = await validate(dto, options);
    expect(errors).toHaveLength(0);
  });
});

/**
 * El fallo original fue una lista escrita a mano en un DTO que dejó de coincidir
 * con la constante que usan la política y el servicio. Estas pruebas obligan a
 * que TODO DTO e-CF recorra la constante correspondiente y a que esa constante
 * siga coincidiendo con lo que acepta la base de datos, de modo que la próxima
 * vez que se añada o cambie un tipo de comprobante la suite falle aquí y no en
 * producción.
 */
describe("DTOs e-CF · coherencia con las constantes de tipo de comprobante", () => {
  const options = { whitelist: true, forbidNonWhitelisted: true };

  it("la declaración DGII acepta cada tipo con rango autorizado", async () => {
    for (const type of ECF_SEQUENCE_TYPES) {
      const dto = plainToInstance(DeclareEcfAuthorizedSequenceDto, {
        documentType: type,
        authorizationNumber: "6005190129",
        rangeFrom: 1,
        rangeTo: 1000,
        approvedQuantity: 1000,
        declarationAccepted: true,
      });
      const errors = await validate(dto, options);
      expect({ type, errors: errors.length }).toEqual({ type, errors: 0 });
    }
  });

  it("el filtro de documentos acepta cada tipo permitido", async () => {
    for (const type of ECF_ALLOWED_DOCUMENT_TYPES) {
      const dto = plainToInstance(ListEcfDocumentsQueryDto, {
        documentType: type,
      });
      const errors = await validate(dto, options);
      expect({ type, errors: errors.length }).toEqual({ type, errors: 0 });
    }
  });

  it("todo tipo con rango es un tipo de documento permitido", () => {
    for (const type of ECF_SEQUENCE_TYPES) {
      expect(ECF_ALLOWED_DOCUMENT_TYPES).toContain(type);
    }
  });

  it("los tipos del código coinciden con el enum de la base de datos", () => {
    const fromDatabase = [...Object.values(EcfElectronicDocumentType)].sort();
    const fromCode = [...ECF_ALLOWED_DOCUMENT_TYPES].sort();
    expect(fromCode).toEqual(fromDatabase);
  });
});
