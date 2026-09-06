import { ConfigService } from "@nestjs/config";
import { BackupsScheduler } from "./backups.scheduler";

describe("BackupsScheduler", () => {
  it("defaults automatic backups to disabled", () => {
    const backups = { runAutomaticBackups: jest.fn() };
    const scheduler = new BackupsScheduler(
      backups as never,
      { get: jest.fn().mockReturnValue(undefined) } as unknown as ConfigService,
    );

    expect(scheduler.schedulerEnabled()).toBe(false);
  });

  it("does not run automatic backups when disabled", async () => {
    const backups = { runAutomaticBackups: jest.fn() };
    const scheduler = new BackupsScheduler(
      backups as never,
      { get: jest.fn().mockReturnValue("false") } as unknown as ConfigService,
    );

    await scheduler.runDailyAutomaticBackups();

    expect(backups.runAutomaticBackups).not.toHaveBeenCalled();
    expect(scheduler.schedulerEnabled()).toBe(false);
  });

  it("runs automatic backups only when explicitly enabled", async () => {
    const backups = { runAutomaticBackups: jest.fn() };
    const scheduler = new BackupsScheduler(
      backups as never,
      { get: jest.fn().mockReturnValue("true") } as unknown as ConfigService,
    );

    await scheduler.runDailyAutomaticBackups();

    expect(backups.runAutomaticBackups).toHaveBeenCalledTimes(1);
    expect(scheduler.schedulerEnabled()).toBe(true);
  });
});
