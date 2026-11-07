#!/usr/bin/env node
/**
 * Verificación del DESTINO DE RED que un artefacto compilado va a usar.
 *
 * Motivo (incidente reproducido en la validación e-CF de 2026-11-07):
 * `flutter build web` SIN `--dart-define=API_BASE_URL` compila un paquete cuyo
 * `Env.apiBaseUrl` cae en `ProductConfig.productionApiBaseUrl`. El artefacto
 * arranca sin ningún aviso y habla con PRODUCCIÓN. Una configuración correcta
 * no demuestra nada: hay que mirar el binario.
 *
 * Por qué NO se busca "host productivo ausente"
 * ---------------------------------------------
 * Los hosts productivos son **constantes de compilación** de `ProductConfig`
 * (valor por defecto y lista de hosts prohibidos del guardia UAT). Aparecen
 * SIEMPRE en el paquete, incluso en un build de validación correcto; usarlos
 * como criterio produce un falso positivo permanente.
 *
 * La señal fiable es la contraria: `String.fromEnvironment('API_BASE_URL')` se
 * INLINEA en el paquete solo si se pasó `--dart-define`. Un literal como
 * `127.0.0.1:4004` no existe en el código fuente, así que si aparece es porque
 * se compiló con esa URL.
 *
 * Uso:
 *   node scripts/release/verify_build_env.cjs --expect-api 127.0.0.1:4004
 *   node scripts/release/verify_build_env.cjs --expect-api mi-backend.com \
 *        --forbid-api 127.0.0.1:4004
 *
 *   --bundle <ruta>     Artefacto a inspeccionar. Por defecto busca
 *                       `build/web/main.dart.js` (cwd y `apps/fulltech_app`).
 *   --expect-api <txt>  El paquete DEBE contener este texto (la URL con la que
 *                       se compiló). Repetible.
 *   --forbid-api <txt>  El paquete NO debe contener este texto. Repetible.
 *
 * Códigos de salida:
 *   0  el artefacto coincide con lo declarado
 *   1  el artefacto NO coincide (motivo impreso)
 *   2  uso incorrecto o artefacto inexistente
 */

const fs = require("node:fs");
const path = require("node:path");

/**
 * Hosts productivos conocidos. Se informan, NO deciden: son constantes del
 * código y aparecen en cualquier build.
 */
const PRODUCTION_CODE_CONSTANTS = [
  "daleventapos-backend.gcdndd.easypanel.host",
  "fullpos-backend-fullposlicenciaswed.onqyr1.easypanel.host",
  "fullpos-backend-fullpos-backend.onqyr1.easypanel.host",
  "fulltech-tienda-fulltechapppwa.gcdndd.easypanel.host",
  "31.97.99.70",
];

function usage(message) {
  if (message) console.error(`ERROR: ${message}`);
  console.error(
    "Uso: node scripts/release/verify_build_env.cjs --expect-api <texto> [--forbid-api <texto>] [--bundle <ruta>]",
  );
  process.exit(2);
}

function defaultBundle() {
  const candidates = [
    path.resolve(process.cwd(), "build", "web", "main.dart.js"),
    path.resolve(
      process.cwd(),
      "apps",
      "fulltech_app",
      "build",
      "web",
      "main.dart.js",
    ),
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) ?? candidates[0];
}

function parseArgs(argv) {
  const args = { bundle: null, expect: [], forbid: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const value = argv[index + 1];
    if (arg === "--bundle") {
      args.bundle = value;
      index += 1;
    } else if (arg === "--expect-api") {
      if (!value) usage("--expect-api requiere un valor");
      args.expect.push(value);
      index += 1;
    } else if (arg === "--forbid-api") {
      if (!value) usage("--forbid-api requiere un valor");
      args.forbid.push(value);
      index += 1;
    } else if (arg === "--help" || arg === "-h") {
      usage();
    } else {
      usage(`argumento no reconocido: ${arg}`);
    }
  }
  if (args.expect.length === 0 && args.forbid.length === 0) {
    usage("indica al menos --expect-api o --forbid-api");
  }
  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const bundlePath = args.bundle ? path.resolve(args.bundle) : defaultBundle();

  if (!fs.existsSync(bundlePath)) {
    usage(`no existe el artefacto: ${bundlePath}`);
  }

  const content = fs.readFileSync(bundlePath, "utf8");
  const problems = [];

  const missing = args.expect.filter((needle) => !content.includes(needle));
  for (const needle of missing) {
    problems.push(
      `falta la URL declarada "${needle}": el paquete no se compiló con --dart-define=API_BASE_URL=${needle}`,
    );
  }

  const forbiddenFound = args.forbid.filter((needle) => content.includes(needle));
  for (const needle of forbiddenFound) {
    problems.push(`el paquete contiene la URL prohibida "${needle}"`);
  }

  const report = {
    bundle: bundlePath,
    bytes: Buffer.byteLength(content, "utf8"),
    expected: args.expect,
    missing,
    forbidden: args.forbid,
    forbiddenFound,
    // Informativo: estas cadenas son constantes del código, no prueba del
    // destino activo. No hacen fallar la verificación.
    productionCodeConstantsPresent: PRODUCTION_CODE_CONSTANTS.filter((marker) =>
      content.includes(marker),
    ),
    ok: problems.length === 0,
  };

  if (!report.ok) {
    console.error("VERIFICACIÓN FALLIDA");
    for (const problem of problems) console.error(` - ${problem}`);
    console.error(JSON.stringify(report, null, 2));
    process.exit(1);
  }

  console.log("VERIFICACIÓN CORRECTA");
  console.log(JSON.stringify(report, null, 2));
  process.exit(0);
}

main();
