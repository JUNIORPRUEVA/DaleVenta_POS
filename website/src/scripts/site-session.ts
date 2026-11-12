/**
 * Sesion del sitio publico (Astro).
 *
 * Guarda los tokens que devuelve el API en `sessionStorage`:
 * - vive solo en esta pestaña (no se comparte ni persiste al cerrar),
 * - no viaja nunca en la URL,
 * - se borra explícitamente al cerrar sesión o al expirar.
 *
 * Sirve de puente entre el registro/login y la pantalla de bienvenida
 * mientras el sitio no tenga una sesion httpOnly propia.
 */

const STORAGE_KEY = 'fullpos.site.session.v1';

export class SiteSessionStorageError extends Error {
  constructor() {
    super('Tu navegador no permite guardar la sesión. Habilita el almacenamiento del sitio e inicia sesión de nuevo.');
    this.name = 'SiteSessionStorageError';
  }
}

export type SiteSession = {
  accessToken: string;
  refreshToken: string;
  email: string;
  companyName: string;
  requiresOnboarding: boolean;
};

type ApiAuthResponse = {
  accessToken?: string;
  refreshToken?: string;
  user?: { email?: string } | null;
  activeCompany?: { name?: string } | null;
  requiresOnboarding?: boolean;
};

function readRaw(): SiteSession | null {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<SiteSession>;
    if (!parsed?.accessToken || !parsed?.refreshToken) return null;
    return {
      accessToken: parsed.accessToken,
      refreshToken: parsed.refreshToken,
      email: parsed.email ?? '',
      companyName: parsed.companyName ?? '',
      requiresOnboarding: parsed.requiresOnboarding === true,
    };
  } catch {
    return null;
  }
}

export function readSession(): SiteSession | null {
  return readRaw();
}

export function saveSessionFromAuth(
  response: ApiAuthResponse,
  fallbackEmail = '',
): SiteSession {
  if (!response.accessToken?.trim() || !response.refreshToken?.trim()) {
    throw new Error('El servidor no devolvió una sesión completa. Inicia sesión de nuevo.');
  }
  const session: SiteSession = {
    accessToken: response.accessToken ?? '',
    refreshToken: response.refreshToken ?? '',
    email: response.user?.email ?? fallbackEmail,
    companyName: response.activeCompany?.name ?? '',
    requiresOnboarding: response.requiresOnboarding === true,
  };
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(session));
    if (readRaw()?.accessToken !== session.accessToken) throw new Error('storage');
  } catch {
    clearSession();
    throw new SiteSessionStorageError();
  }
  return session;
}

export function clearSession(): void {
  try {
    sessionStorage.removeItem(STORAGE_KEY);
  } catch {
    /* nada que limpiar */
  }
}

/**
 * Devuelve un access token util. Si el guardado expiró, intenta refrescarlo
 * una vez y guarda el par nuevo. Devuelve `null` si ya no hay sesion válida.
 */
export async function getAccessToken(apiBase: string): Promise<string | null> {
  const session = readRaw();
  if (!session) return null;

  try {
    const response = await fetch(`${apiBase}/auth/me`, {
      headers: { Authorization: `Bearer ${session.accessToken}` },
    });
    if (response.ok) return session.accessToken;
    if (response.status !== 401) return session.accessToken;
  } catch {
    return session.accessToken;
  }

  try {
    const refreshed = await fetch(`${apiBase}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken: session.refreshToken }),
    });
    if (!refreshed.ok) {
      clearSession();
      return null;
    }
    const data = (await refreshed.json()) as ApiAuthResponse;
    if (!data.accessToken) {
      clearSession();
      return null;
    }
    const next = saveSessionFromAuth(
      {
        ...data,
        refreshToken: data.refreshToken ?? session.refreshToken,
        user: data.user ?? { email: session.email },
        activeCompany: data.activeCompany ?? { name: session.companyName },
        requiresOnboarding: data.requiresOnboarding ?? session.requiresOnboarding,
      },
      session.email,
    );
    return next.accessToken;
  } catch {
    clearSession();
    return null;
  }
}
