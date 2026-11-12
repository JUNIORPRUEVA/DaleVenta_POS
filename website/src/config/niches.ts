/**
 * Nichos de negocio que acepta el backend.
 *
 * Fuente unica: `apps/api/src/onboarding/onboarding.constants.ts`
 * (`WELCOME_BUSINESS_TYPES`). El servidor rechaza cualquier otro valor, asi que
 * esta lista debe copiarse tal cual si cambia alli.
 */
export const niches = [
  'Farmacia',
  'Colmado',
  'Minimarket',
  'Supermercado',
  'Ferretería',
  'Boutique',
  'Licorería',
  'Restaurante',
  'Cafetería',
  'Panadería',
  'Repostería',
  'Barbería',
  'Salón de belleza',
  'Distribuidora',
  'Repuestos',
  'Taller mecánico',
  'Librería',
  'Papelería',
  'Tienda de celulares',
  'Agropecuaria',
  'Hotel',
  'Vinatería',
  'Heladería',
  'Joyería',
  'Zapatería',
  'Tienda de ropa',
  'Bodega',
  'Almacén',
  'Otros',
] as const;
