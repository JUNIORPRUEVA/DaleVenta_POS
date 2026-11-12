/**
 * Datos compartidos del sitio publico.
 * Fuente: repositorio y web aprobada actual.
 * Nada aqui es inventado: los enlaces salen de la configuracion real de la app.
 */

export const site = {
  name: 'FullPOS Cloud',
  company: 'FULLTECH SRL',
  tagline: 'Sistema POS en la nube para ventas, inventario y caja',
  /** Firma discreta bajo la marca. */
  byline: 'by FULLTECH SRL',
  description:
    'Ventas, inventario, compras, contabilidad, clientes y facturación electrónica en un solo sistema. Rápido en caja y con hasta 48 horas de trabajo sin internet. Prueba gratis 7 días.',
  url: 'https://fullposcloud.fulltechrd.com',
  supportEmail: 'fulltechsd@gmail.com',
  supportPhoneLabel: '829-436-3936',
  supportWhatsapp: '18294363936',
  supportHours: 'Lunes a viernes de 9:00 a.m. a 6:00 p.m. AST',
} as const;

export const waLink = `https://wa.me/${site.supportWhatsapp}`;

/**
 * Canales oficiales tomados de `AppAccessLinks` de la app real.
 * Windows: endpoint oficial que redirige al instalador publicado.
 */
export const appLinks = {
  pwa: 'https://fullposcloud.fulltechrd.com/',
  windows:
    'https://daleventapos-backend.gcdndd.easypanel.host/api/app-updates/windows/latest/download',
  android:
    'https://github.com/JUNIORPRUEVA/fullpos_cluouds/releases/latest/download/app-release.apk',
  ios: 'https://apps.apple.com/do/app/fullpos-cloud/id6801349002',
} as const;

/** Iconos (trazo, 24x24). Markup interno de <svg>. */
export const icons = {
  check: '<path d="M20 6 9 17l-5-5"/>',
  arrowRight: '<path d="M5 12h14M13 5l7 7-7 7"/>',
  chevronDown: '<path d="m6 9 6 6 6-6"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  close: '<path d="M6 6l12 12M18 6 6 18"/>',
  download: '<path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/>',
  monitor: '<rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8M12 17v4"/>',
  smartphone: '<rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M11 18h2"/>',
  tablet: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M11 18h2"/>',
  globe:
    '<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a15 15 0 0 1 0 18 15 15 0 0 1 0-18z"/>',
  receipt:
    '<path d="M6 3h12a1 1 0 0 1 1 1v16l-3-2-3 2-3-2-3 2V4a1 1 0 0 1 1-1z"/><path d="M9 8h6M9 12h6"/>',
  box: '<path d="M3 8.5 12 3l9 5.5v7L12 21l-9-5.5z"/><path d="m3 8.5 9 5.5 9-5.5"/><path d="M12 14v7"/>',
  users:
    '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M17 5.5a3.5 3.5 0 0 1 0 6.6"/><path d="M19 20a6 6 0 0 0-3-5.2"/>',
  truck:
    '<path d="M3 6h11v9H3z"/><path d="M14 9h4l3 3v3h-7z"/><circle cx="7" cy="18" r="1.8"/><circle cx="17.5" cy="18" r="1.8"/>',
  fileText:
    '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6M9 17h4"/>',
  chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  bars: '<path d="M4 19h16"/><rect x="6" y="9" width="3" height="7" rx="1"/><rect x="11" y="5" width="3" height="11" rx="1"/><rect x="16" y="12" width="3" height="4" rx="1"/>',
  building:
    '<path d="M4 21V5a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v16"/><path d="M15 9h3a2 2 0 0 1 2 2v10"/><path d="M4 21h18"/><path d="M8 7h3M8 11h3M8 15h3"/>',
  shield: '<path d="M12 3l8 3v6c0 5-3.4 8.2-8 9-4.6-.8-8-4-8-9V6z"/><path d="m9 12 2 2 4-4"/>',
  spark: '<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z"/>',
  sparkles:
    '<path d="M12 3l1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6z"/><path d="M18.5 15.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/>',
  bolt: '<path d="M13 2 4.5 13.5H11l-1 8.5 8.5-11.5H12z"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',
  lock: '<rect x="4" y="10" width="16" height="10" rx="2"/><path d="M8 10V7.5a4 4 0 0 1 8 0V10"/>',
  cloud: '<path d="M7 18a4.5 4.5 0 0 1-.6-8.96A5.5 5.5 0 0 1 17.4 8.5 4 4 0 0 1 17 18z"/>',
  headphones:
    '<path d="M4 14v-2a8 8 0 0 1 16 0v2"/><path d="M4 14h3v6H5.5A1.5 1.5 0 0 1 4 18.5z"/><path d="M20 14h-3v6h1.5A1.5 1.5 0 0 0 20 18.5z"/>',
  play: '<path d="M8 5.5v13l11-6.5z"/>',
  tag: '<path d="M20.6 13.4 13.4 20.6a2 2 0 0 1-2.8 0l-7.2-7.2A2 2 0 0 1 3 12V5a2 2 0 0 1 2-2h7a2 2 0 0 1 1.4.6l7.2 7.2a2 2 0 0 1 0 2.6z"/><circle cx="8" cy="8" r="1.3"/>',
  scale:
    '<path d="M12 4v16M7 20h10"/><path d="M4 9h16"/><path d="m4 9 3 5a3 3 0 0 1-6 0z"/><path d="m20 9-3 5a3 3 0 0 0 6 0z"/>',
  card: '<rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M2.5 10h19"/><path d="M6.5 15h3"/>',
  whatsapp:
    '<path d="M20.5 11.6a8.4 8.4 0 0 1-12.4 7.4L3.5 20.5l1.6-4.5a8.4 8.4 0 1 1 15.4-4.4z"/><path d="M8.7 8.6c.4-.1.8 0 1 .4l.7 1.2c.1.3.1.5-.1.7l-.5.5c-.1.2-.2.4-.1.6a6 6 0 0 0 2.8 2.5c.2.1.4 0 .6-.1l.5-.5c.2-.2.4-.2.7-.1l1.2.6c.4.2.5.6.4 1a2 2 0 0 1-1.6 1.4c-2.4.3-6.4-2.6-7-5.2a2 2 0 0 1 1-2.2z"/>',
  /** Glifo solido de WhatsApp para el boton flotante (viewBox 0 0 16 16). */
  whatsappSolid:
    '<path d="M13.601 2.326A7.854 7.854 0 0 0 7.994 0C3.627 0 .068 3.558.064 7.926c0 1.399.366 2.76 1.057 3.965L0 16l4.204-1.102a7.933 7.933 0 0 0 3.79.965h.004c4.368 0 7.926-3.558 7.93-7.93A7.898 7.898 0 0 0 13.6 2.326zM7.994 14.521a6.573 6.573 0 0 1-3.356-.92l-.24-.144-2.494.654.666-2.433-.156-.251a6.56 6.56 0 0 1-1.007-3.505c0-3.626 2.957-6.584 6.591-6.584a6.56 6.56 0 0 1 4.66 1.931 6.557 6.557 0 0 1 1.928 4.66c-.004 3.639-2.961 6.592-6.592 6.592zm3.615-4.934c-.197-.099-1.17-.578-1.353-.646-.182-.065-.315-.099-.445.099-.133.197-.513.646-.627.775-.114.133-.232.148-.43.05-.197-.1-.836-.308-1.592-.985-.59-.525-.985-1.175-1.103-1.372-.114-.198-.011-.304.088-.403.087-.088.197-.232.296-.346.1-.114.133-.198.198-.33.065-.134.034-.248-.015-.347-.05-.099-.445-1.076-.612-1.47-.16-.389-.323-.335-.445-.34-.114-.007-.247-.007-.38-.007a.729.729 0 0 0-.529.247c-.182.198-.691.677-.691 1.654 0 .977.71 1.916.81 2.049.098.133 1.394 2.132 3.383 2.992.47.205.84.326 1.129.418.475.152.904.129 1.246.08.38-.058 1.171-.48 1.338-.943.164-.464.164-.86.114-.943-.049-.084-.182-.133-.38-.232z"/>',
  mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3.5 7 8.5 6 8.5-6"/>',
  phone:
    '<path d="M6.5 3h3l1.5 4-2 1.5a12 12 0 0 0 5.5 5.5L16 12l4 1.5v3a2 2 0 0 1-2.2 2A16 16 0 0 1 4.5 5.2 2 2 0 0 1 6.5 3z"/>',
  gift: '<rect x="3" y="8" width="18" height="5" rx="1.5"/><path d="M5 13v8h14v-8"/><path d="M12 8v13"/><path d="M12 8S9 3 6.8 4.6C4.8 6 6.5 8 12 8z"/><path d="M12 8s3-5 5.2-3.4C19.2 6 17.5 8 12 8z"/>',
  rocket:
    '<path d="M13.5 4.5c3-2 6-1.5 6-1.5s.5 3-1.5 6l-4.2 6.2-4-4z"/><path d="M9.8 15.2 8 19l-3-3 3.8-1.8"/><circle cx="15" cy="9" r="1.4"/>',
  eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
  layers: '<path d="m12 3 9 5-9 5-9-5z"/><path d="m3 13 9 5 9-5"/>',
  wifi: '<path d="M4 9a13 13 0 0 1 16 0"/><path d="M7 12.5a9 9 0 0 1 10 0"/><path d="M10 16a4.5 4.5 0 0 1 4 0"/><circle cx="12" cy="19" r="1"/>',
} as const;

/* ------------------------------------------------------------------ */
/* Estrategia de conversion                                            */
/* ------------------------------------------------------------------ */

/**
 *  header  -> "Regístrate gratis"
 *  hero    -> "Empezar gratis"
 *  planes  -> "Elegir <plan>"
 *  pasos   -> "Hablar por WhatsApp"
 *  movil   -> "Empezar gratis"
 *  auth    -> "Crear mi cuenta"
 */
export const cta = {
  header: { login: 'Ingresar', primary: 'Regístrate gratis' },
  hero: {
    primary: 'Empezar gratis',
    secondary: 'Ver planes y precios',
    eyebrow: 'Prueba FullPOS gratis por 7 días',
  },
  final: { primary: 'Empezar gratis', secondary: 'Escribir por WhatsApp' },
  mobile: { secondary: 'Precios', primary: 'Empezar gratis' },
  auth: 'Crear mi cuenta',
} as const;

/** Pilares de marca. No repiten funcionalidades: hablan de la experiencia. */
export const pillars = [
  'Facilidad de uso',
  'Rapidez en caja',
  'Organización total',
  'Control de tu negocio',
  'Confianza en tus datos',
];

/** Tres datos de un vistazo. Sin precios: el precio vive en los planes. */
export const heroProof = [
  '7 días de prueba gratis',
  'Hasta 48 horas sin internet',
  'Soporte humano por WhatsApp',
];

/** Tipos de negocio que pueden usar FullPOS Cloud. */
export const businessTypes = [
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
];

export type FeatureItem = { title: string; text: string; svg: string };
export type FeatureGroup = { key: string; title: string; note: string; items: FeatureItem[] };

/**
 * Funciones agrupadas por la decision del cliente: vender, controlar y crecer.
 * Orden comercial: primero lo esencial del mostrador, luego el control y al final
 * la operacion avanzada de negocios con mas volumen.
 */
export const featureGroups: FeatureGroup[] = [
  {
    key: 'vender',
    title: 'Para vender',
    note: 'Lo esencial del día a día en el mostrador.',
    items: [
      {
        title: 'Ventas y facturación',
        text: 'Cobra rápido y emite el comprobante de cada venta.',
        svg: icons.receipt,
      },
      {
        title: 'Caja y turnos',
        text: 'Controla aperturas, cierres y arqueos por turno.',
        svg: icons.card,
      },
      {
        title: 'Inventarios y recuentos',
        text: 'Lleva existencias reales con ajustes y conteos.',
        svg: icons.box,
      },
      {
        title: 'Clientes y crédito',
        text: 'Administra fichas, historial y cuentas por cobrar.',
        svg: icons.users,
      },
      {
        title: 'Cotizaciones',
        text: 'Prepara cotizaciones y conviértelas en ventas.',
        svg: icons.fileText,
      },
    ],
  },
  {
    key: 'controlar',
    title: 'Para controlar',
    note: 'Orden en la operación y números a la vista.',
    items: [
      {
        title: 'Compras y proveedores',
        text: 'Registra entradas de mercancía y controla tus compras.',
        svg: icons.truck,
      },
      {
        title: 'Reportes',
        text: 'Consulta ventas, utilidad e inventario sin esperar al cierre.',
        svg: icons.bars,
      },
      {
        title: 'Contabilidad',
        text: 'Organiza movimientos y cierres para tu contador.',
        svg: icons.chart,
      },
      {
        title: 'Usuarios y permisos',
        text: 'Da a cada usuario solo el acceso que le corresponde.',
        svg: icons.lock,
      },
      {
        title: 'Respaldos en la nube',
        text: 'Mantén tu información segura y disponible en tus equipos.',
        svg: icons.cloud,
      },
    ],
  },
  {
    key: 'crecer',
    title: 'Para crecer',
    note: 'Más operación, más sucursales, más funciones.',
    items: [
      {
        title: 'Multi almacén',
        text: 'Controla varias sucursales o almacenes con stock separado.',
        svg: icons.building,
      },
      {
        title: 'Multi unidad de medida',
        text: 'Vende por unidad, caja, libra, metro y más.',
        svg: icons.scale,
      },
      {
        title: 'Órdenes de servicio',
        text: 'Da seguimiento desde la recepción hasta la entrega.',
        svg: icons.layers,
      },
      {
        title: 'Hasta 48 h sin internet',
        text: 'Sigue operando y sincroniza cuando vuelva la conexión.',
        svg: icons.wifi,
      },
      {
        title: 'Facturación electrónica',
        text: 'Activa e-CF con guía paso a paso y apoyo en la postulación.',
        svg: icons.shield,
      },
    ],
  },
];

/** Pasos de inicio, en el orden real del cliente. */
export const startSteps = [
  {
    n: '1',
    title: 'Crea tu cuenta gratis',
    text: 'Regístrate en pocos minutos desde este navegador o desde FullPOS para Windows.',
  },
  {
    n: '2',
    title: 'Configura tu negocio',
    text: 'Carga tus productos, precios y datos del negocio para empezar a operar.',
  },
  {
    n: '3',
    title: 'Prueba FullPOS durante 7 días',
    text: 'Inicia sesión con la misma cuenta en tus dispositivos compatibles durante la prueba.',
  },
  {
    n: '4',
    title: 'Activa el plan que necesites',
    text: 'Al terminar la prueba eliges tu plan y el pago se realiza con tarjeta.',
  },
];

/** Cómo funciona el pago, en tres pasos claros. */
export const billing = [
  {
    n: '01',
    title: 'Prueba 7 días',
    text: 'Creas tu cuenta y usas el sistema completo sin costo.',
  },
  {
    n: '02',
    title: 'Eliges tu plan',
    text: 'Al terminar la prueba decides con cuál seguir.',
  },
  {
    n: '03',
    title: 'Pagas con tarjeta',
    text: 'El pago del plan se realiza con tarjeta.',
  },
];

export type PlanSpec = { svg: string; label: string };

export type Plan = {
  id: string;
  name: string;
  short: string;
  price: string;
  monthly: number;
  period: string;
  summary: string;
  trial: string;
  badge?: string;
  highlight?: boolean;
  specs: PlanSpec[];
  cta: string;
  ctaHint: string;
};

/**
 * Precios y limites definidos por el negocio.
 * Todos los planes incluyen la misma plataforma (Windows, Android, iPhone y web).
 */
export const plans: Plan[] = [
  {
    id: 'basico',
    name: 'FullPOS Básico',
    short: 'Básico',
    price: 'RD$1,000',
    monthly: 1000,
    period: 'al mes',
    summary: 'Para empezar a vender sin complicarte.',
    trial: '7 días gratis',
    specs: [
      { svg: icons.box, label: '100 productos' },
      { svg: icons.users, label: '2 usuarios' },
      { svg: icons.building, label: '1 almacén' },
      { svg: icons.fileText, label: 'Facturación electrónica opcional' },
      { svg: icons.headphones, label: 'Soporte estándar' },
    ],
    cta: 'Elegir Básico',
    ctaHint: 'Prueba de 7 días antes de pagar',
  },
  {
    id: 'negocio',
    name: 'FullPOS Negocio',
    short: 'Negocio',
    price: 'RD$2,000',
    monthly: 2000,
    period: 'al mes',
    summary: 'El equilibrio entre precio y capacidad.',
    trial: '7 días gratis',
    badge: 'Más elegido',
    highlight: true,
    specs: [
      { svg: icons.box, label: '400 productos' },
      { svg: icons.users, label: '5 usuarios' },
      { svg: icons.building, label: '1 a 2 almacenes' },
      { svg: icons.fileText, label: 'Facturación electrónica incluida' },
      { svg: icons.shield, label: 'Postulación e-CF gratis con asistente guiado' },
      { svg: icons.headphones, label: 'Soporte prioritario' },
    ],
    cta: 'Elegir Negocio',
    ctaHint: 'El favorito de los negocios',
  },
  {
    id: 'pro',
    name: 'FullPOS Pro',
    short: 'Pro',
    price: 'RD$3,000',
    monthly: 3000,
    period: 'al mes',
    summary: 'Para operaciones con más movimiento.',
    trial: '7 días gratis',
    specs: [
      { svg: icons.box, label: '1,000 productos' },
      { svg: icons.users, label: '10 usuarios' },
      { svg: icons.building, label: 'Multi-almacén' },
      { svg: icons.fileText, label: 'Mayor capacidad de facturación' },
      { svg: icons.shield, label: 'Postulación e-CF gratis con asistente guiado' },
      { svg: icons.headphones, label: 'Soporte más rápido' },
    ],
    cta: 'Elegir Pro',
    ctaHint: 'Incluye todo lo de Negocio',
  },
  {
    id: 'empresa',
    name: 'FullPOS Empresa',
    short: 'Empresa',
    price: 'RD$4,500',
    monthly: 4500,
    period: 'al mes',
    summary: 'Capacidad máxima y acompañamiento.',
    trial: '7 días gratis',
    specs: [
      { svg: icons.box, label: '5,000 productos' },
      { svg: icons.users, label: '20 usuarios' },
      { svg: icons.building, label: 'Mayor capacidad operativa' },
      { svg: icons.fileText, label: 'Facturación electrónica ampliada' },
      { svg: icons.shield, label: 'Postulación e-CF gratis con asistente guiado' },
      { svg: icons.headphones, label: 'Soporte extendido y arranque' },
    ],
    cta: 'Elegir Empresa',
    ctaHint: 'Con acompañamiento desde el día 1',
  },
];

/** Plataforma incluida en todos los planes. */
export const planPlatform = 'Windows, Android, iPhone y web';


/** Lo que incluyen los cuatro planes, sin excepcion. */
export const planIncludes = [
  'Prueba de 7 días gratis',
  'Windows, Android, iPhone y web',
  'Los mismos datos en todos los dispositivos',
  'Datos separados por empresa',
  'Actualizaciones incluidas',
  'Soporte por WhatsApp',
];

export type ModuleGroup = {
  title: string;
  items: { name: string; svg: string }[];
};

/** Modulos del sistema, agrupados para la pagina de funciones. */
export const moduleGroups: ModuleGroup[] = [
  {
    title: 'Operación diaria',
    items: [
      { name: 'Ventas y cotizaciones', svg: icons.receipt },
      { name: 'Inventarios y recuentos', svg: icons.box },
      { name: 'Gestión de compras', svg: icons.truck },
    ],
  },
  {
    title: 'Gestión del negocio',
    items: [
      { name: 'Contabilidad', svg: icons.chart },
      { name: 'Gestión de clientes', svg: icons.users },
      { name: 'Multi almacenes', svg: icons.building },
      { name: 'Multi unidad de medida', svg: icons.scale },
      { name: 'Mayoreo y detalle', svg: icons.tag },
    ],
  },
  {
    title: 'Siempre disponible',
    items: [
      { name: 'Hasta 48 horas sin internet', svg: icons.wifi },
      { name: 'Facturación electrónica', svg: icons.fileText },
      { name: 'Todo en un solo lugar', svg: icons.cloud },
    ],
  },
];

export type Download = {
  id: string;
  name: string;
  icon: string;
  status: string;
  detail: string;
  /** URL oficial. Vacia solo cuando el canal todavia no existe. */
  url: string;
  /** true = el boton descarga directamente (sin dialogo). */
  direct?: boolean;
  /** Canal anunciado pero sin URL verificada: se muestra desactivado. */
  pending?: boolean;
};

/**
 * Canales oficiales reales (AppAccessLinks de la app).
 * Windows descarga el instalador publicado; iOS y Web abren su canal.
 * Android: Google Play esta anunciado pero aun no hay URL verificada; el APK
 * publicado se conserva como canal aparte para no romper una descarga real.
 */
export const downloads: Download[] = [
  {
    id: 'windows',
    name: 'Windows',
    icon: icons.monitor,
    status: 'Descargar',
    detail: 'Aplicación para PC',
    url: appLinks.windows,
    direct: true,
  },
  {
    id: 'android',
    name: 'Android',
    icon: icons.smartphone,
    status: 'Google Play',
    detail: 'Disponible en Google Play',
    url: '',
    pending: true,
  },
  {
    id: 'android',
    name: 'Android (APK)',
    icon: icons.smartphone,
    status: 'Descargar APK',
    detail: 'Instalador directo',
    url: appLinks.android,
  },
  {
    id: 'ios',
    name: 'iPhone / iPad',
    icon: icons.tablet,
    status: 'App Store',
    detail: 'App para Apple',
    url: appLinks.ios,
  },
  {
    id: 'web',
    name: 'Web',
    icon: icons.globe,
    status: 'Abrir',
    detail: 'Sin instalación',
    url: appLinks.pwa,
  },
];

export const faqs = [
  {
    q: '¿Qué incluye la prueba de 7 días?',
    a: 'Incluye el sistema completo: ventas, inventario, compras, caja, clientes, reportes y los demás módulos, en todos tus dispositivos. No se cobra nada durante esos 7 días.',
  },
  {
    q: '¿Necesito tarjeta para empezar la prueba?',
    a: 'No. Creas tu cuenta y empiezas a usar el sistema sin registrar ningún método de pago. La tarjeta se usa al terminar la prueba, solo si decides continuar.',
  },
  {
    q: '¿Cómo se paga después de los 7 días?',
    a: 'El pago del plan se realiza con tarjeta. Eliges el plan que vas a usar y desde ese momento queda activa tu suscripción.',
  },
  {
    q: '¿Qué pasa si decido no continuar?',
    a: 'Si no activas un plan al terminar la prueba, no se realiza ningún cobro.',
  },
  {
    q: '¿Cuánto cuesta FullPOS Cloud?',
    a: 'Los planes van desde RD$1,000 al mes. Tienes el detalle completo, con lo que incluye cada uno, en la sección de planes y precios.',
  },
  {
    q: '¿Cómo descargo la aplicación de Windows?',
    a: 'En la sección de descargas pulsa “Windows” y el instalador (.exe) se descarga desde el canal oficial. Luego lo abres y sigues el asistente.',
  },
  {
    q: '¿Funciona sin internet?',
    a: 'Sí. Puedes seguir operando hasta 48 horas sin conexión; los datos quedan guardados de forma segura y se sincronizan cuando vuelve el internet.',
  },
  {
    q: '¿Los datos se mezclan entre empresas?',
    a: 'No. Cada empresa tiene sus propios datos, usuarios y permisos; el acceso está separado por empresa.',
  },
  {
    q: '¿En qué dispositivos puedo usarlo?',
    a: 'Windows, Android, iPhone y navegador, con la misma cuenta y los mismos datos en todos.',
  },
  {
    q: '¿Puedo tener varios usuarios?',
    a: 'Sí. Puedes crear usuarios y asignarles permisos por rol. La cantidad incluida en cada plan se confirma al contratar.',
  },
  {
    q: '¿Incluye facturación electrónica?',
    a: 'Sí, es uno de los módulos del sistema. Se configura según las reglas fiscales de tu negocio y el equipo te acompaña en el proceso.',
  },
  {
    q: '¿Qué soporte ofrecen?',
    a: 'Soporte humano por WhatsApp y correo, de lunes a viernes de 9:00 a.m. a 6:00 p.m., incluido en todos los planes.',
  },
];
