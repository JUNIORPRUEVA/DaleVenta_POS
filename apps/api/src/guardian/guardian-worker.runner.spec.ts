jest.mock('../app.module', () => ({ AppModule: class {} }));
import { NestFactory } from '@nestjs/core';
import { PrismaService } from '../prisma/prisma.service';
import { GuardianAlertService } from './guardian.alert.service';
import { GuardianDiagnosisService } from './guardian.diagnosis.service';
import { GuardianAiBalanceMonitor } from './guardian.ai.balance.monitor';
import { runGuardianWorker } from './guardian-worker.runner';

describe('Guardian worker independent alert lane', () => {
  const env = { ...process.env };
  afterEach(() => {
    jest.clearAllTimers(); jest.useRealTimers(); jest.restoreAllMocks(); process.env = { ...env };
  });

  it('continues alert delivery and recovery while AI and balance lookups remain hung', async () => {
    jest.useFakeTimers();
    const alerts = {
      processDue: jest.fn(async () => ({ processed: 0, sent: 0, failed: 0 })),
      planMissingAlerts: jest.fn(async () => 0),
    };
    const diagnosis = { runBatch: jest.fn(() => new Promise(() => {})) };
    const balance = { check: jest.fn(() => new Promise(() => {})) };
    const prisma = { guardianWorkerHeartbeat: { upsert: jest.fn(async () => ({})) } };
    const values = new Map<unknown, unknown>([
      [GuardianAlertService, alerts], [GuardianDiagnosisService, diagnosis],
      [GuardianAiBalanceMonitor, balance], [PrismaService, prisma],
    ]);
    jest.spyOn(NestFactory, 'createApplicationContext').mockResolvedValue({ get: (type: unknown) => values.get(type), close: async () => {} } as any);
    jest.spyOn(process, 'on').mockReturnValue(process);
    const exit = jest.spyOn(process, 'exit').mockImplementation((() => { throw new Error('Unexpected process exit'); }) as never);
    await runGuardianWorker();
    await jest.advanceTimersByTimeAsync(5000);
    expect(alerts.processDue).toHaveBeenCalledTimes(2);
    expect(alerts.planMissingAlerts).toHaveBeenCalledTimes(2);
    expect(diagnosis.runBatch).toHaveBeenCalledTimes(1);
    expect(prisma.guardianWorkerHeartbeat.upsert.mock.calls.every((call: any[]) => call[0].where.workerName === 'alerts')).toBe(true);
    expect(exit).not.toHaveBeenCalled();
  });
});
