import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { parseServerInstant } from '../common/utils/business-time.util';
import { resolveClockSkewMs } from '../cash/cash-operation-window';

type CashPermitClaims = {
  version: 1;
  companyId: string;
  userId: string;
  deviceFingerprint: string;
  sessionId: string;
  validFrom: string;
  validUntil: string;
};

/** Historical evidence, never a bearer credential. The request still requires
 * a current JWT and the normal cash permissions. HMAC purpose separation and
 * a non-JWT envelope prevent a receipt from authenticating an API request. */
@Injectable()
export class OfflineCashPermitService {
  constructor(private readonly config: ConfigService) {}

  issue(claims: Omit<CashPermitClaims, 'version'>): string | null {
    const key = this.key();
    if (!key) return null;
    const body = Buffer.from(JSON.stringify({ version: 1, ...claims })).toString('base64url');
    return `fpcash1.${body}.${this.signature(body, key)}`;
  }

  verify(input: {
    receipt: string;
    companyId: string;
    userId: string;
    deviceFingerprint: string;
    openedAt: string;
    now?: Date;
  }): { openedAt: Date; evidenceHash: string; authorizationSessionId: string } {
    const reject = (): never => {
      throw new BadRequestException({
        code: 'CASH_OFFLINE_OPEN_EVIDENCE_INVALID',
        message: 'No pudimos comprobar la autorización original de esta apertura. Se necesita revisión; no cambies su fecha ni la repitas con otro identificador.',
      });
    };
    const key = this.key();
    if (!key || !input.deviceFingerprint || input.receipt.length > 4096) return reject();
    const [prefix, body, supplied, extra] = input.receipt.split('.');
    if (prefix !== 'fpcash1' || !body || !supplied || extra !== undefined) return reject();
    const expected = Buffer.from(this.signature(body, key));
    const actual = Buffer.from(supplied);
    if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) return reject();
    let claims: CashPermitClaims;
    try { claims = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')); }
    catch { return reject(); }
    if (claims.version !== 1 || claims.companyId !== input.companyId ||
        claims.userId !== input.userId || claims.deviceFingerprint !== input.deviceFingerprint ||
        typeof claims.sessionId !== 'string' || !claims.sessionId ||
        typeof claims.validFrom !== 'string' || typeof claims.validUntil !== 'string') return reject();
    const from = parseServerInstant(claims.validFrom);
    const until = parseServerInstant(claims.validUntil);
    const openedAt = parseServerInstant(input.openedAt);
    if (until.getTime() < from.getTime() || until.getTime() - from.getTime() > 48 * 3600_000 ||
        openedAt < from || openedAt > until ||
        openedAt.getTime() > (input.now ?? new Date()).getTime() + resolveClockSkewMs()) return reject();
    return { openedAt, evidenceHash: createHmac('sha256', key).update(input.receipt).digest('hex'),
      authorizationSessionId:claims.sessionId };
  }

  private key(): Buffer | null {
    const secret = this.config.get<string>('JWT_SECRET')?.trim();
    if (!secret) return null;
    return createHmac('sha256', secret).update('fullpos.offline.cash.open.evidence.v1').digest();
  }
  private signature(body: string, key: Buffer): string {
    return createHmac('sha256', key).update(`fpcash1.${body}`).digest('base64url');
  }
}
