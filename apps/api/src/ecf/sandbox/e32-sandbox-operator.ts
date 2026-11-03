import { JwtService } from "@nestjs/jwt";
import type { JwtUser } from "../../auth/jwt-user.type";
import { normalizeJwtSecret } from "../../auth/jwt.util";
import type { TenantUser } from "../../auth/tenant-context";

// Signature first, then the application's existing session/member/license
// validator. No login request, JWT decoding shortcut or client companyId.
export async function authenticateE32Operator(token: string | undefined, expectedActorId: string | undefined,
  secret: string | undefined, validate: (payload: JwtUser) => Promise<TenantUser>): Promise<TenantUser | null> {
  const key = normalizeJwtSecret(secret);
  if (!key || !token || token.length > 8192) return null;
  try {
    const payload = new JwtService().verify<JwtUser & {exp?: number}>(token,{secret:key,algorithms:["HS256"]});
    if (payload.tokenType !== "access" || !payload.sub || !payload.sessionId || !payload.exp ||
        (expectedActorId && payload.sub !== expectedActorId)) return null;
    const actor = await validate(payload);
    return actor.id === payload.sub && actor.companyId && actor.role === "ADMIN" ? actor : null;
  } catch { return null; } // Report blocked context, never token-bearing errors.
}
