import { mkdir, open, readdir, readFile, rename, unlink, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';

/** One writer per directory. Mount GUARDIAN_OUTBOX_DIR on the instance's persistent volume. */
export class GuardianDurableOutbox<T> {
  private writes: Promise<void> = Promise.resolve();
  private draining: Promise<void> | null = null;
  private readonly unsaved = new Map<string,T>();
  private static readonly storageFailures = new Set<string>();
  constructor(readonly directory: string) {}

  static directory(channel: string): string {
    const root = resolve(process.env.GUARDIAN_OUTBOX_DIR || 'data/guardian-outbox');
    return process.env.GUARDIAN_PROCESS_ROLE === 'worker' ? join(root,'worker',channel) : join(root,channel);
  }

  static async status(channel: string) {
    const directory = this.directory(channel);
    try {
      const files = (await readdir(directory)).filter(file=>file.endsWith('.json'));
      let deferred = 0, corrupt = 0;
      for (const file of files) {
        try {
          const entry = JSON.parse(await readFile(join(directory,file),'utf8'));
          if (!entry || typeof entry !== 'object' || !('value' in entry) || !Number.isFinite(entry.nextAt)) corrupt++;
          else if (entry.nextAt > Date.now()) deferred++;
        } catch { corrupt++; }
      }
      return {available:!this.storageFailures.has(directory),pending:files.length,deferred,corrupt};
    } catch(error) {
      return {available:!this.storageFailures.has(directory) && (error as NodeJS.ErrnoException)?.code === 'ENOENT',pending:0,deferred:0,corrupt:0};
    }
  }

  enqueue(value: T): Promise<void> {
    const path = join(this.directory, `${Date.now()}-${randomUUID()}.json`);
    this.unsaved.set(path,value);
    return this.persist(path,value);
  }

  private persist(path:string,value:T): Promise<void> {
    const write = this.writes.then(async () => {
      await mkdir(this.directory, { recursive: true, mode: 0o700 });
      await this.atomic(path, {
        value, attempts: 0, nextAt: 0,
      });
      this.unsaved.delete(path);
      GuardianDurableOutbox.storageFailures.delete(this.directory);
    });
    this.writes = write.catch(() => { GuardianDurableOutbox.storageFailures.add(this.directory); });
    return write;
  }

  private async atomic(path: string, value: unknown) {
    const temporary = `${path}.${randomUUID()}.tmp`;
    const file = await open(temporary, 'wx', 0o600);
    try { await file.writeFile(JSON.stringify(value)); await file.sync(); }
    finally { await file.close(); }
    await rename(temporary, path);
  }

  flush(deliver: (value: T) => Promise<void>, limit = 100): Promise<void> {
    if (this.draining) return this.draining;
    const work = this.drain(deliver, limit);
    this.draining = work.finally(() => { this.draining = null; });
    return this.draining;
  }

  private async drain(deliver: (value: T) => Promise<void>, limit: number) {
    {
      await this.writes;
      for (const [path,value] of [...this.unsaved]) await this.persist(path,value);
      await mkdir(this.directory, { recursive: true, mode: 0o700 });
      // Recover a fully written file left before rename by a process/power interruption.
      for (const file of (await readdir(this.directory)).filter(name=>name.endsWith('.tmp'))) {
        const path = join(this.directory,file);
        try {
          if (Date.now() - (await stat(path)).mtimeMs < 60_000) continue;
          const entry = JSON.parse(await readFile(path,'utf8'));
          if (!entry || !('value' in entry) || !Number.isFinite(entry.nextAt)) continue;
          const destination = path.replace(/\.[0-9a-f-]+\.tmp$/, '');
          if (destination === path) continue;
          try { await stat(destination); } catch(error) {
            if ((error as NodeJS.ErrnoException).code === 'ENOENT') await rename(path,destination);
          }
        } catch { /* Preserve the damaged file for inspection. */ }
      }
      const files = (await readdir(this.directory)).filter(file => file.endsWith('.json')).sort();
      let processed = 0;
      for (const file of files) {
        const path = join(this.directory, file);
        // A corrupt record remains on disk; it must not prevent healthy records from being delivered.
        let entry: { value: T; attempts: number; nextAt: number };
        try {
          entry = JSON.parse(await readFile(path, 'utf8'));
          if (!entry || typeof entry !== 'object' || !('value' in entry) || !Number.isFinite(entry.nextAt) || !Number.isFinite(entry.attempts)) continue;
        }
        catch { continue; }
        if (entry.nextAt > Date.now()) continue;
        if (++processed > limit) break;
        try { await deliver(entry.value); }
        catch (error) {
          entry.attempts += 1;
          const retryAfterMs = Number((error as { retryAfterMs?: number })?.retryAfterMs) || 0;
          entry.nextAt = Date.now() + Math.max(retryAfterMs, Math.min(300_000, 1000 * 2 ** Math.min(entry.attempts, 8)));
          await this.atomic(path, entry);
          continue;
        }
        // Remove only after confirmed delivery. A crash before this point safely replays the same eventId.
        await unlink(path);
      }
    }
  }
}
