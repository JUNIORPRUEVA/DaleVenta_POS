import { LicenseService } from './license.service';

/**
 * Borrado permanente de una empresa.
 *
 * La version anterior recorria ~90 tablas en orden alfabetico y fallaba con 500
 * porque `warehouses` se vaciaba antes que `terminals` (clave foranea
 * RESTRICT). La base ya cae en cascada desde `companies`, asi que ahora solo se
 * limpia la unica tabla con datos de empresa que **no** cascada y el grafo lo
 * borra Postgres en una sola sentencia.
 */
describe('borrado permanente de la empresa', () => {
  function build() {
    const statements: string[] = [];
    const tx = {
      $executeRawUnsafe: jest.fn(async (sql: string) => {
        statements.push(sql);
        return 1;
      }),
      $queryRaw: jest.fn(),
    };
    const service = new LicenseService(
      {} as never,
      {} as never,
      {} as never,
      {} as never,
    ) as never as { deleteCompanyOwnedRows: (tx: unknown, id: string) => Promise<void> };
    return { service, tx, statements };
  }

  it('limpia la tabla sin cascada y no intenta borrar tabla por tabla', async () => {
    const { service, tx, statements } = build();

    await service.deleteCompanyOwnedRows(tx as never, 'company-1');

    expect(statements).toHaveLength(1);
    expect(statements[0]).toContain('"password_reset_audit_logs"');
    // Ya no se consulta el catalogo ni se borran 90 tablas a mano: si volviera
    // el bucle alfabetico, esta prueba lo detecta.
    expect(tx.$queryRaw).not.toHaveBeenCalled();
    expect(statements.some((sql) => sql.includes('"warehouses"'))).toBe(false);
  });
});

