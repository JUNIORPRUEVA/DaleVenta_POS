import "reflect-metadata";
import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { SalesRangeQueryDto } from "./sales-range-query.dto";

describe("SalesRangeQueryDto (limit compatibility / version skew)", () => {
  const options = { whitelist: true, forbidNonWhitelisted: true };

  function messages(errors: Array<{ constraints?: Record<string, string> }>) {
    return errors.flatMap((error) =>
      error.constraints ? Object.values(error.constraints) : [],
    );
  }

  it("BACKEND NUEVO acepta limit=20", async () => {
    const dto = plainToInstance(SalesRangeQueryDto, {
      from: "2026-08-01T00:00:00.000Z",
      to: "2026-08-20T00:00:00.000Z",
      includeDeleted: "true",
      limit: 20,
    });
    const errors = await validate(dto, options);
    expect(errors).toHaveLength(0);
  });

  it("BACKEND NUEVO rechaza limit por encima del máximo configurado", async () => {
    const dto = plainToInstance(SalesRangeQueryDto, { limit: 9999 });
    const errors = await validate(dto, options);
    expect(errors.length).toBeGreaterThan(0);
    const all = messages(errors).join(" ");
    expect(all.toLowerCase()).toContain("must not be greater");
  });

  it("BACKEND NUEVO funciona sin limit (clientes antiguos)", async () => {
    const dto = plainToInstance(SalesRangeQueryDto, {
      from: "2026-08-01T00:00:00.000Z",
    });
    const errors = await validate(dto, options);
    expect(errors).toHaveLength(0);
  });

  it("DEMOSTRACIÓN VERSION SKEW: una propiedad desconocida es rechazada como 'should not exist'", async () => {
    // Simula el backend ANTERIOR (DTO sin `limit`): cualquier propiedad no
    // declarada genera exactamente el error que el usuario ve:
    //   "property <name> should not exist"
    const dto = plainToInstance(SalesRangeQueryDto, { unknownProp: 1 });
    const errors = await validate(dto, options);
    const all = messages(errors).join(" ");
    expect(all).toContain("unknownProp should not exist");
  });
});
