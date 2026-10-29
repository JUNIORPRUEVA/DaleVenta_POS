import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { NotificationsService } from './notifications.service';
import { ServiceOrderNotificationJobsProcessor } from './service-order-notification-jobs.processor';
import { reportGuardianJobFailure } from '../guardian/telemetry/guardian.telemetry.reporter';

@Injectable()
export class NotificationsDispatcher implements OnModuleInit, OnModuleDestroy {
  constructor(
    private readonly notifications: NotificationsService,
    private readonly serviceOrderJobs: ServiceOrderNotificationJobsProcessor,
  ) {}

  private timer: NodeJS.Timeout | null = null;
  private running = false;

  onModuleInit() {
    const enabled = (process.env.NOTIFICATIONS_ENABLED ?? '').trim().toLowerCase();
    if (enabled === '0' || enabled === 'false') return;

    this.timer = setInterval(() => {
      if (this.running) return;
      this.running = true;
      Promise.all([
        this.serviceOrderJobs.processDueJobsBatch(10),
        this.notifications.processOutboxBatch(25),
      ])
        .catch((error) => {
          // best-effort: el ciclo no se interrumpe, pero el fallo ya no se pierde.
          // La telemetría es asíncrona y fail-open: no altera este flujo.
          reportGuardianJobFailure({
            module: 'network',
            operation: 'notificationsOutboxCycle',
            error,
          });
        })
        .finally(() => {
          this.running = false;
        });
    }, 8_000);

    // Don't keep the process alive just for this loop.
    this.timer.unref?.();
  }

  onModuleDestroy() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }
}
