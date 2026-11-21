import { ForbiddenException, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { Role } from '@prisma/client';
import { AiAssistantService } from './ai-assistant.service';
import { AppyraIaError } from './appyra-ia.client';

describe('AI library company boundary', () => {
  const resourceId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const principal = { id:'user-a', role:Role.VENDEDOR, companyId:'company-a' };
  function fixture() {
    const appyraIa = { libraryResource: jest.fn() };
    return { appyraIa, call: (user: typeof principal) => AiAssistantService.prototype.libraryResource.call({ appyraIa, logger:{warn:jest.fn()} }, user, resourceId) };
  }
  it('requires an authenticated company before requesting any file', async () => {
    const {call,appyraIa}=fixture();
    await expect(call({...principal,companyId:''})).rejects.toBeInstanceOf(ForbiddenException);
    expect(appyraIa.libraryResource).not.toHaveBeenCalled();
  });
  it('does not expose provider messages when a resource is withdrawn or unavailable', async () => {
    const {call,appyraIa}=fixture();
    appyraIa.libraryResource.mockRejectedValue(new AppyraIaError('http','Internal provider detail',404));
    await expect(call(principal)).rejects.toBeInstanceOf(NotFoundException);
    appyraIa.libraryResource.mockRejectedValue(new Error('Internal provider detail'));
    await expect(call(principal)).rejects.toBeInstanceOf(ServiceUnavailableException);
  });
});
