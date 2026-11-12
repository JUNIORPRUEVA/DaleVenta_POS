# FullPOS Cloud — Sitio público (Astro)

Sitio de marketing **estático** de FullPOS Cloud. Convive con la web actual
(`apps/fulltech_app/web`), que **no se ha modificado ni eliminado**.

## Requisitos

- Node 20+
- npm

## Desarrollo

```powershell
cd website
npm install
npm run dev      # http://localhost:4321
```

## Validación

```powershell
npm run check    # astro check (TypeScript + plantillas)
npm run build    # genera dist/
npm run preview  # sirve dist/ en http://localhost:4321
```

## Estructura

```
src/
  config/site.ts         Datos de marca, planes, funciones, plataformas, FAQ
  styles/global.css      Tokens y estilos (paleta del sitio aprobado actual)
  layouts/BaseLayout.astro
  components/SiteHeader.astro | SiteFooter.astro
  pages/
    index.astro          Home
    precios.astro        4 planes
    funciones.astro      Funcionalidades reales
    descargas.astro      Web/PWA + Windows/Android/iOS
    soporte.astro        Contacto + FAQ
    terminos.astro       Contenido legal existente
    privacidad.astro     Contenido legal existente
    login.astro          UI preparada (sin integración)
    registro.astro       UI preparada (4 campos obligatorios)
    recuperar.astro      UI preparada
    404.astro
```

## Alcance de la Fase 1

- **Solo interfaz.** Login, registro y recuperación **no** están conectados a la API:
  la integración es la Fase 2 (ver `data-phase="2"` en los formularios).
- **Sin enlaces inventados.** Windows/Android/iOS remiten a WhatsApp de soporte
  mientras no exista una URL oficial publicada.
- **Sin precios de infraestructura ni cuotas inventadas:** los límites se
  confirman al activar la licencia.
