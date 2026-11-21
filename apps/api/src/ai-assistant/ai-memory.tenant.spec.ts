import { ConfigService } from '@nestjs/config';
import { Role } from '@prisma/client';
import { AiAssistantService } from './ai-assistant.service';
import { PrismaService } from '../prisma/prisma.service';
import { CatalogProductsService } from '../products/catalog-products.service';
import { AppyraIaClient } from './appyra-ia.client';

describe('memoria del asistente aislada por empresa y usuario', () => {
  const companyA = '11111111-1111-4111-8111-111111111111';
  const companyB = '22222222-2222-4222-8222-222222222222';
  const id = '33333333-3333-4333-8333-333333333333';
  function fixture() {
    const raw = {user: {findFirst: jest.fn().mockResolvedValue({id})}, $queryRaw: jest.fn().mockResolvedValue([]), $executeRaw: jest.fn().mockResolvedValue(1)};
    const service = new AiAssistantService(raw as unknown as PrismaService, {} as ConfigService, {} as CatalogProductsService, {} as AppyraIaClient);
    return {raw,service};
  }
  const dto = {message: 'Cómo se utiliza esta pantalla', context: {module:'general'}};
  it('conserva el alcance activo aunque el mismo usuario cambie de empresa', async () => {
    const {raw,service} = fixture();
    for (const companyId of [companyA,companyB]) {
      raw.$queryRaw.mockClear();
      await service['buildPersistentMemoryKnowledge']({id,role:Role.ADMIN,companyId},dto);
      expect(raw.user.findFirst).toHaveBeenLastCalledWith(expect.objectContaining({where:{role:Role.ADMIN,companyId}}));
      expect(raw.$queryRaw).toHaveBeenCalledTimes(2);
      for (const [sql] of raw.$queryRaw.mock.calls) {
        expect(sql.strings.join('')).toContain('company_id = CAST(');
        expect(sql.values).toContain(companyId);
        expect(sql.values).toContain(id);
      }
    }
  });
  it('no lee memoria sin empresa ni persiste consultas denegadas', async () => {
    const {raw,service} = fixture();
    expect(await service['buildPersistentMemoryKnowledge']({id,role:Role.ADMIN},dto)).toEqual([]);
    await service['persistLearningArtifacts']({id,role:Role.ADMIN,companyId:companyA},dto,{source:'policy',content:'Solicitud no permitida',citations:[],denied:true},[]);
    expect(raw.$queryRaw).not.toHaveBeenCalled();expect(raw.$executeRaw).not.toHaveBeenCalled();
  });
});
