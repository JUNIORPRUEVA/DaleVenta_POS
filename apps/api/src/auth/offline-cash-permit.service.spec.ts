import { BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomBytes } from 'node:crypto';
import { OfflineCashPermitService } from './offline-cash-permit.service';

describe('signed historical cash opening evidence',()=>{
  const claims={companyId:'company-a',userId:'user-a',sessionId:'authorization-a',deviceFingerprint:'device-a',
    validFrom:'2026-11-20T12:00:00.000Z',validUntil:'2026-11-22T12:00:00.000Z'};
  const service=new OfflineCashPermitService(new ConfigService({JWT_SECRET:randomBytes(32).toString('hex')}));
  const receipt=service.issue(claims)!;
  const input={receipt,companyId:'company-a',userId:'user-a',deviceFingerprint:'device-a',
    openedAt:'2026-11-20T12:10:00.000Z',now:new Date('2026-11-25T12:00:00Z')};
  it('accepts an opening inside its original 48h authority even when transmission arrives later',()=>{
    expect(service.verify(input)).toMatchObject({openedAt:new Date(input.openedAt),authorizationSessionId:'authorization-a'});
    expect(service.verify(input).evidenceHash).toHaveLength(64);
    expect(receipt.startsWith('fpcash1.')).toBe(true);
    expect(()=>JSON.parse(Buffer.from(receipt.split('.')[0],'base64url').toString())).toThrow();
  });
  it.each([
    {companyId:'company-b'}, {userId:'user-b'}, {deviceFingerprint:'device-b'},
    {openedAt:'2026-11-20T11:59:00Z'}, {openedAt:'2026-11-22T12:01:00Z'},
    {openedAt:'2026-11-20T12:10:00'}, {receipt:receipt+'modified'}, {receipt:'untrusted'},
    {openedAt:'2026-11-20T13:00:00Z',now:new Date('2026-11-20T12:00:00Z')},
  ])('rejects scope, signature or timestamp manipulation: %j',change=>{
    expect(()=>service.verify({...input,...change})).toThrow(BadRequestException);
  });
  it('fails closed when the signing key is missing or has changed',()=>{
    expect(new OfflineCashPermitService(new ConfigService()).issue(claims)).toBeNull();
    const changed=new OfflineCashPermitService(new ConfigService({JWT_SECRET:randomBytes(32).toString('hex')}));
    expect(()=>changed.verify(input)).toThrow(BadRequestException);
  });
});
