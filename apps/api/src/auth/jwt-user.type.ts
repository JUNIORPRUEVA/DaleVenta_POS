import { Role } from '@prisma/client';

export type JwtUser = {
  sub: string;
  companyId?: string | null;
  email?: string;
  role?: Role;
  tokenType?: 'access' | 'refresh';
};
