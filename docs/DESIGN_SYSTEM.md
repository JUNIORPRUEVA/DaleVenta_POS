# FullPOS Cloud Design System

Last audited: 2026-09-02.

This document records the current UI system. Do not redesign FullPOS as part of ordinary feature work.

## Source of Truth

- Colors: `apps/fulltech_app/lib/core/theme/app_colors.dart`
- Theme: `apps/fulltech_app/lib/core/theme/app_theme.dart`
- Typography: `apps/fulltech_app/lib/core/design_system/typography/app_typography.dart`
- Role branding: `apps/fulltech_app/lib/core/theme/role_branding.dart`
- Icons and sizes: `apps/fulltech_app/lib/core/design_system/icons/`
- Shared widgets: `apps/fulltech_app/lib/core/widgets/`

## Typography

Primary font family is Manrope. The app defines display, headline, title, body, and label styles through `AppTypography.textTheme()`. Use existing text theme and `AppTextStyles` before adding custom text styles.

Observed sizes include:

- Display: 34
- Headline: 28
- Title: 22, 17, 15
- Body: 15, 14, 12
- Labels: 14, 12, 11

## Colors

Use `AppColors` tokens:

- Primary/secondary: `0xFF1957E6`
- Primary dark: `0xFF123A75`
- Accent: `0xFF26B6A6`
- Background: `0xFFEFF5F8`
- Surface: white
- Alternate/subtle surfaces: `surfaceAlt`, `surfaceSubtle`, `surfaceMuted`
- Text: `textPrimary`, `textSecondary`, `textMuted`
- Status: `success`, `warning`, `error` with soft and border variants
- Borders/shadows/overlay: `border`, `borderStrong`, `shadow`, `overlay`

Role-specific branding can change primary/secondary/tertiary colors. Check `role_branding.dart`.

## Surfaces and Layout

- Scaffold background uses `AppColors.background`.
- App bars are white, flat, with a bottom border.
- Cards are zero elevation, softly tinted surfaces, and currently use rounded corners around 18px in the app theme.
- Dialogs use rounded 20px shapes.
- Chips are pill-shaped.
- Responsive navigation uses shared shell/drawer/navigation widgets.

## Buttons and Inputs

- Elevated/Filled buttons use role primary color and white foreground.
- Outlined/Text buttons use role primary color.
- Buttons use Manrope label styling and minimum 40px size.
- Inputs are filled white, with 16px radius, soft border, stronger focused border, and status error styling.
- Dropdown menus follow the input styling.

## Tables, Lists, Menus

- `DataTableTheme` uses muted heading row and medium body weight.
- `ListTileTheme` uses rounded 16px shape and role primary icons.
- Popup menus are white, transparent tint, rounded 14px.

## Navigation

Reusable navigation components:

- `responsive_shell.dart`
- `app_drawer.dart`
- `app_navigation.dart`
- `custom_app_bar.dart`
- `fulltech_page_header.dart`

Navigation must respect route permissions and responsive behavior.

## Icons

Use Material icons and the local icon abstraction in `core/design_system/icons`. Existing icon sizes:

- compact 16
- small 18
- normal/button 20
- navigation/medium 22
- large 28
- empty state 44
- hero 56

## Reusable Components

Use these before creating new primitives:

- `FullTechDialog`
- `CustomAppBar`
- `FullTechPageHeader`
- `FulltechGlobalBackground`
- `ResponsiveShell`
- `AppDrawer`
- `AppNavigation`
- `PrimaryButton`
- `ErrorBanner`
- `SyncStatusBanner`
- `ProductNetworkImage`
- `PdfActionMenu`
- `UserAvatar`
- Printing/PDF helpers under `core/printing` and `core/pdf`
- Accounting widgets under `features/contabilidad/widgets`

## Empty, Loading, Error, and Sync States

The app has shared error and sync UI (`ErrorBanner`, `SyncStatusBanner`) and loading infrastructure under `core/loading`. New screens should use existing loading/error conventions and avoid one-off spinners or unsupported language.

## Responsive Behavior

The app supports mobile, desktop, PWA, and Windows. Existing routing and layout code differentiates desktop settings layout at widths around 900px and uses shared responsive shell widgets. New UI must be checked on mobile and desktop sizes when user-facing.

## Project UI Rules

- Do not introduce arbitrary colors when a token exists.
- Do not introduce a new typography family without approval.
- Reuse existing shared components and module widgets.
- New screens must visually belong to the same product.
- Visual changes require real visual validation when tooling allows it.
- Do not perform unrelated UI redesigns during feature work.
- Respect role branding and permission-based navigation.
- Keep text fitting within buttons, cards, dialogs, and mobile layouts.

## Design Debt

- Some feature screens use local constants or inline status colors instead of central tokens.
- Root and historical visual evidence folders are extensive; OWNER VALIDATION REQUIRED to decide which screenshots are the current visual baseline.
- Theme card/dialog corner radii vary by component and feature; avoid adding more variation without design approval.
