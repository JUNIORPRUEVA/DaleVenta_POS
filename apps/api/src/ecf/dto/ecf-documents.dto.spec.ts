import "reflect-metadata";
import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import {
  RegisterEcfSequenceDto,
  RenewEcfSequenceDto,
} from "./ecf-documents.dto";
import { ECF_SEQUENCE_TYPES } from "../documents/ecf-dgii-authorized-sequences.policy";

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
