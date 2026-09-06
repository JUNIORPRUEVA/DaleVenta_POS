import { Injectable, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Cron, CronExpression } from "@nestjs/schedule";
import { BackupsService } from "./backups.service";

@Injectable()
export class BackupsScheduler {
  private readonly logger = new Logger(BackupsScheduler.name);

  constructor(
    private readonly backups: BackupsService,
    private readonly config: ConfigService,
  ) {}

  @Cron(CronExpression.EVERY_DAY_AT_2AM)
  async runDailyAutomaticBackups() {
    if (!this.schedulerEnabled()) {
      this.logger.log("Canonical automatic backup scheduler disabled by configuration");
      return;
    }
    this.logger.log("Running canonical automatic backup eligibility check");
    await this.backups.runAutomaticBackups();
  }

  schedulerEnabled() {
    const raw = (this.config.get<string>("BACKUP_SCHEDULER_ENABLED") ?? "false")
      .trim()
      .toLowerCase();
    return ["1", "true", "yes", "on", "enabled"].includes(raw);
  }
}
