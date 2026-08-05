import { Role } from '@prisma/client';

export type JwtUser = {
  sub: string;
  companyId?: string | null;
  email?: string;
  role?: Role;
  memberRole?: string | null;
  tokenType?: 'access' | 'refresh';
  sessionId?: string | null;
};
