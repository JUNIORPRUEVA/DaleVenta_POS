/**
 * Retención de Guardian — punto de entrada para tareas programadas.
 *
 * Ejecuta `GuardianRetentionService` fuera del API. Sin `GUARDIAN_RETENTION_APPLY=true`
 * el servicio funciona en modo simulación (solo cuenta, no borra), que es el modo
 * por defecto y el único permitido mientras no haya autorización explícita.
 *
 *   npm --workspace apps/api run guardian:retention
 *   npm --workspace apps/api run guardian:retention -- --apply   # borra de verdad
 */
import { NestFactory } from '@nestjs/core';
import { Logger } from '@nestjs/common';
import { AppModule } from '../../src/app.module';
import { GuardianRetentionService } from '../../src/guardian/guardian.retention.service';

async function main() {
  const apply = process.argv.includes('--apply');
  const logger = new Logger('GuardianRetention');
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });

  try {
    const retention = app.get(GuardianRetentionService);
    const result = await retention.run({ dryRun: !apply });
    logger.log(`resultado: ${JSON.stringify(result)}`);
    if (apply !== true) {
      logger.log('modo simulación: no se borró ninguna fila (use --apply para aplicar)');
    }
  } finally {
    await app.close();
  }
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error('[guardian-retention] fallo', error);
  process.exit(1);
});
