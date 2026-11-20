import { PrismaClient } from '@prisma/client';
import { readdirSync, existsSync, accessSync, constants } from 'node:fs';
import { join } from 'node:path';

/**
 * Comprobaciones previas al despliegue. **No escribe nada.**
 *
 * Responde a las preguntas que se hacen justo antes de subir:
 *  - ¿Hay conexion con la base y estan todas las migraciones aplicadas?
 *  - ¿Esta el catalogo de planes sembrado y completo?
 *  - ¿Estan las variables que la licencia necesita?
 *  - ¿Cuantas empresas ACTIVO siguen sin plan (lo que migra el backfill)?
 *
 * Uso (desde apps/api, con el entorno del servidor cargado):
 *   npx ts-node --transpile-only -P tsconfig.scripts.json scripts/deploy-preflight.ts
 *
 * Codigo de salida: 0 todo correcto · 2 avisos · 1 errores.
 */

type Linea = { nivel: 'OK' | 'AVISO' | 'ERROR'; texto: string };

const PLANS_REQUIRED = ['basico', 'negocio', 'pro', 'empresa'];

async function main() {
  const lineas: Linea[] = [];
  const ok = (texto: string) => lineas.push({ nivel: 'OK', texto });
  const aviso = (texto: string) => lineas.push({ nivel: 'AVISO', texto });
  const error = (texto: string) => lineas.push({ nivel: 'ERROR', texto });

  // --- Variables -----------------------------------------------------------
  const secret = (process.env.JWT_SECRET ?? '').trim();
  if (!secret) error('JWT_SECRET no esta definido.');
  else if (secret === 'change-me') error('JWT_SECRET usa el valor por defecto "change-me".');
  else if (secret.length < 32) aviso(`JWT_SECRET tiene ${secret.length} caracteres; se recomiendan 32 o mas.`);
  else ok('JWT_SECRET definido y con longitud suficiente.');

  const bank = (process.env.LICENSE_BANK_ACCOUNT ?? '').replace(/\D/g, '');
  if (!bank) {
    aviso('LICENSE_BANK_ACCOUNT no esta definido: los comprobantes no podran validar la cuenta destino y quedaran en revision.');
  } else if (bank.length < 4) {
    error('LICENSE_BANK_ACCOUNT tiene menos de 4 digitos: la validacion del comprobante fallaria siempre (A3).');
  } else {
    ok(`LICENSE_BANK_ACCOUNT configurado (termina en ${bank.slice(-4)}).`);
  }

  const evidenceDir = (process.env.LICENSE_EVIDENCE_DIR ?? '').trim();
  if (!evidenceDir) {
    aviso('LICENSE_EVIDENCE_DIR no esta definido: se usara el directorio por defecto del contenedor.');
  } else if (!existsSync(evidenceDir)) {
    error(`LICENSE_EVIDENCE_DIR no existe: ${evidenceDir}`);
  } else {
    try {
      accessSync(evidenceDir, constants.W_OK);
      ok(`LICENSE_EVIDENCE_DIR existe y se puede escribir: ${evidenceDir}`);
    } catch {
      error(`LICENSE_EVIDENCE_DIR no es escribible: ${evidenceDir}`);
    }
  }

  const cors = (process.env.CORS_ORIGIN ?? '').trim();
  if (!cors) aviso('CORS_ORIGIN no esta definido: la app web puede quedar bloqueada.');
  else ok('CORS_ORIGIN definido.');

  if ((process.env.RUN_MIGRATIONS ?? 'true') !== 'true') {
    aviso('RUN_MIGRATIONS no esta en true: las migraciones no se aplicarian al arrancar.');
  } else {
    ok('RUN_MIGRATIONS activo.');
  }
  if (['true', '1'].includes(process.env.RUN_SEED ?? '')) {
    aviso('RUN_SEED esta activo: ejecuta el seed completo en cada arranque. Para planes usa solo seed-license-plans.');
  }
  if (['true', '1'].includes(process.env.CRM_LICENSE_MANAGEMENT_ENABLED ?? '')) {
    ok('CRM_LICENSE_MANAGEMENT_ENABLED activo (el panel de licencias puede gestionar empresas).');
  } else {
    aviso('CRM_LICENSE_MANAGEMENT_ENABLED no esta activo: el CRM no podra consultar ni conceder excepciones.');
  }
  if ((process.env.LICENSE_WA_DRY_RUN ?? 'true') !== 'false') {
    aviso('LICENSE_WA_DRY_RUN no esta en false: los avisos de vencimiento no se enviarian de verdad.');
  } else {
    ok('LICENSE_WA_DRY_RUN en false: los avisos saldrian por WhatsApp.');
  }

  // --- Base de datos -------------------------------------------------------
  const prisma = new PrismaClient();
  try {
    try {
      await prisma.$queryRaw`SELECT 1`;
      ok('Conexion con la base de datos correcta.');
    } catch (e) {
      error(`No se pudo conectar con la base: ${(e as Error).message}`);
      print(lineas);
      process.exitCode = 1;
      return;
    }

    // Migraciones aplicadas frente a las que hay en el repositorio.
    const enDisco = readdirSync(join(process.cwd(), 'prisma', 'migrations')).filter(
      (name: string) => /^\d{14}_/.test(name),
    );
    const aplicadas = await prisma.$queryRaw<Array<{ migration_name: string }>>`
      SELECT migration_name FROM _prisma_migrations WHERE finished_at IS NOT NULL
    `;
    const setAplicadas = new Set(aplicadas.map((r) => r.migration_name));
    const pendientes = enDisco.filter((name: string) => !setAplicadas.has(name));
    if (pendientes.length) {
      error(`Migraciones sin aplicar (${pendientes.length}): ${pendientes.join(', ')}`);
    } else {
      ok(`Migraciones al dia (${enDisco.length}).`);
    }

    // Catalogo de planes.
    const planes = await prisma.licensePlan.findMany({ orderBy: { monthlyPrice: 'asc' } });
    const codes = new Set(planes.filter((p) => p.active).map((p) => p.code));
    const faltan = PLANS_REQUIRED.filter((code) => !codes.has(code));
    if (!planes.length) {
      error('El catalogo de planes esta vacio: ejecuta scripts/seed-license-plans.ts.');
    } else if (faltan.length) {
      error(`Faltan planes activos en el catalogo: ${faltan.join(', ')}`);
    } else {
      ok(`Catalogo con ${planes.length} planes activos (${[...codes].join(', ')}).`);
    }

    // Empresas que el backfill tiene que tocar.
    const activasSinPlan = await prisma.company.count({
      where: { licenseStatus: 'ACTIVE', planCode: null, status: { not: 'ARCHIVED' } },
    });
    if (activasSinPlan > 0) {
      aviso(`${activasSinPlan} empresa(s) ACTIVO sin plan: el backfill las migrara al plan basico conservando sus meses y funciones.`);
    } else {
      ok('No hay empresas ACTIVO sin plan.');
    }

    const planesDesconocidos = await prisma.$queryRaw<Array<{ slug: string; plan_code: string }>>`
      SELECT c.slug, c.plan_code FROM companies c
      LEFT JOIN license_plans p ON p.code = c.plan_code
      WHERE c.plan_code IS NOT NULL AND p.code IS NULL
    `;
    if (planesDesconocidos.length) {
      error(`Empresas con un plan que no existe en el catalogo: ${planesDesconocidos.map((r) => `${r.slug}(${r.plan_code})`).join(', ')}`);
    } else {
      ok('Todas las empresas con plan usan un codigo del catalogo.');
    }

    const sinVencimiento = await prisma.company.count({
      where: { licenseStatus: 'ACTIVE', licenseExpiresAt: null, status: { not: 'ARCHIVED' } },
    });
    if (sinVencimiento > 0) {
      aviso(`${sinVencimiento} empresa(s) ACTIVO sin fecha de vencimiento: confirmar si son perpetuas.`);
    }

    const vencidas = await prisma.company.count({
      where: { licenseStatus: 'EXPIRED', status: { not: 'ARCHIVED' } },
    });
    if (vencidas > 0) aviso(`${vencidas} empresa(s) con licencia vencida (no se tocan en la migracion).`);
  } finally {
    await prisma.$disconnect();
  }

  print(lineas);
  if (lineas.some((l) => l.nivel === 'ERROR')) process.exitCode = 1;
  else if (lineas.some((l) => l.nivel === 'AVISO')) process.exitCode = 2;
}

function print(lineas: Linea[]) {
  for (const l of lineas) {
    console.log(`${l.nivel.padEnd(6)} ${l.texto}`);
  }
  const cuenta = (n: Linea['nivel']) => lineas.filter((l) => l.nivel === n).length;
  console.log(
    `\nResumen: ${cuenta('OK')} correctas · ${cuenta('AVISO')} avisos · ${cuenta('ERROR')} errores`,
  );
}

main().catch((e) => {
  console.error('error en la comprobacion previa', e);
  process.exitCode = 1;
});
