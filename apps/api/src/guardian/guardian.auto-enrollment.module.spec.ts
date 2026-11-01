import { ConfigService } from '@nestjs/config';
import { Reflector } from '@nestjs/core';
import { Test } from '@nestjs/testing';
import { PrismaService } from '../prisma/prisma.service';
import { GuardianAutoEnrollmentController } from './guardian.auto-enrollment.controller';
import { GuardianAutoEnrollmentService } from './guardian.auto-enrollment.service';

/**
 * Regresión del defecto detectado en el despliegue a UAT:
 *
 * El servicio se inyectaba con un **tipo estructural** (`GuardianAutoEnrollmentStore`),
 * así que Nest emitía `Object` en `design:paramtypes` y el arranque fallaba con
 * `UnknownDependenciesException` — el build y las pruebas unitarias no lo veían
 * porque instanciaban la clase directamente.
 *
 * Esta prueba levanta un módulo real de Nest: si alguien vuelve a cambiar el
 * constructor por un tipo no inyectable, falla aquí y no en producción.
 */
describe('GuardianAutoEnrollment — inyeccion de dependencias', () => {
  it('el modulo resuelve el servicio y el controlador con PrismaService', async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [GuardianAutoEnrollmentController],
      providers: [
        GuardianAutoEnrollmentService,
        Reflector,
        { provide: ConfigService, useValue: { get: () => undefined } },
        { provide: PrismaService, useValue: { company: {}, guardianMachineCredential: {} } },
      ],
    }).compile();

    const service = moduleRef.get(GuardianAutoEnrollmentService);
    expect(service).toBeDefined();
    // El controlador solo debe construirse si el servicio se inyectó de verdad.
    expect(moduleRef.get(GuardianAutoEnrollmentController)).toBeDefined();
  });
});
