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

The 80mm thermal PDF uses its own print typography: embedded Roboto Condensed
Regular at 9pt for headings, labels and data; Medium at the same size only for
emphasized totals. Preserve the compact right-aligned totals and complete
single-line product text (scale down only when the available width requires
it). This exception does not change the app theme or the 58mm receipt.
For a simple 80mm cash sale, show only TOTAL and DEVUELTA (including zero).
Show SUBTOTAL when discounts, fiscal breakdown or a differing subtotal explain
the total. Credit adds ABONADO and PENDIENTE; mixed payments preserve each
allocation once. Do not repeat cash tender. Below the totals, retain a thin
separator and NOTA with the payment method once, followed by the thank-you
footer. Deduplicate automatic payment lines while preserving customer notes
and all applicable fiscal fields, including the authentic e-CF stamp.

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

POS modal refinement requested2026-11-27: ticket rename/delete, item/general
discounts, checkout and cash movement forms use square cards, inputs, toggles
and actions. Interactive fields/actions are44px tall, with standard density
inside this scope. Ticket rename inputs span the content width. Delete uses
the existing outlined trash image. Invoice type is selected only in the sale
detail; checkout retains that selection and its fiscal validation. Other
dialogs retain the existing global appearance.

Owner refinement: these POS forms use a shared1px corner radius, keeping the
nearly square appearance with a slight softening; heights and behavior stay
unchanged.

Action notices (owner clarification, 2026-11-21): AppFeedback transient notices
use a compact paragraph with a bold short title, icon and close action, at 12 px
from the top and right safe edges. Product lifecycle notices use the same upper
right position; the previous lower corner instruction is superseded. Technical
record identifiers are hidden in customer-facing product labels and these
notices; persisted identifiers and commercial product codes remain unchanged.

- Elevated/Filled buttons use role primary color and white foreground.
- Outlined/Text buttons use role primary color.
- Buttons use Manrope label styling and minimum 40px size.
- Inputs are filled white, with 16px radius, soft border, stronger focused border, and status error styling.
- Dropdown menus follow the input styling.

Fiscal tray refinement approved by the owner (2026-11-14): status/type filters
and search use compact rectangular corners (6px), with white text on selected
primary controls. Document rows use a thin border and compact status indicators.
This is scoped to the fiscal tray; the global chip/input theme is unchanged.
The pending fiscal completion view combines its header and embedded numbering
into one EcfSurface, without nesting white bordered sections.
Fiscal configuration19 also uses6px rectangular buttons and compact panels,
with a two-column desktop layout and a single mobile column. Numbering summaries
wrap metadata without ellipsis in this view; global summary defaults are unchanged.

History refinement requested on2026-11-15: sales, quotation and credit history
search remains36px tall and is limited to560px on desktop. Filter controls use
6px corners; side panels are capped at380px, with compact headers and40px footer
actions. Other modules keep their existing toolbar defaults. Public marketing
includes a compact e-CF announcement within its navigation header; auth on mobile uses
document scrolling so browser chrome can respond naturally to user gestures.

Credit history owner refinement (2026-11-26): its filter is square and36px tall,
matching search. Move the selected-credit title/count into the toolbar at the
right and omit the duplicated appbar metric and list refresh header. The detail
starts with the document, uses orange for pending status, and presents only
Registrar abono, Saldar and administrator-only Eliminar crédito as square
actions on one line, with short captions in compact widths. Printing and PDF belong to each list row. No create-credit
action is offered in this history or its empty state; credit sales originate
in Facturación through its existing payment method. The amount paid is shown
once in the detail totals; retain channel amounts and custom notes, omitting
the redundant automatic note «Pago: Crédito». Mobile details share this content
and the same three resolution actions. These overrides are scoped to credit
history and retain backend authorization and financial validation.

The subsequent compact-detail refinement uses two columns for client/contact
and cashier/status, side-by-side payment channels and three columns for the
totals. Product sections use reduced padding. Below1360px, the history has12px
side margins and prioritizes a wider detail column; compact actions read Abonar,
Saldar and Eliminar with full tooltips. Preserve every monetary digit in narrow
credit list rows. The appbar orders the cash-turn control before Refresh.

Public website refinement (2026-11-20): at widths up to900px the marketing header
scrolls with the document. Desktop keeps its sticky navigation. The mobile menu
has an explicit close action and closes on section links. Plan carousels accept
keyboard focus, leave room above recommendation badges and use larger mobile
body text. Preserve root document scrolling; browser toolbar visibility remains
controlled by the browser, not by page scripts.

Final header refinement (2026-11-20): the e-CF notice is one24px white line inside
the header, with a subtle animated1px accent (static for reduced motion). No
second geographic line. The mobile menu is a full-height rectangular right drawer,
up to340px wide, with square outer and action corners, a close button and
bottom registration/plan actions. Omit the phone number from this drawer.

Owner's public website button style (2026-11-20): square corners, using
`--button-radius: 0` for marketing, navigation, drawer, plan, download and
authentication actions. The floating WhatsApp button and its pulse stay circular
as an explicit owner-approved exception. Keep existing colors, focus states and touch
areas. The standalone preparation page uses the same0px corners. Decorative
chips, cards and status indicators retain their own shapes.

## Tables, Lists, Menus

Owner-approved recovery refinement (2026-11-20): keep the Recovery Center in a
920px bounded card, with compact 12–13px rows, square actions and a single
top sync control. The empty state contains only a success icon and «Todo en
orden». Uncertain charges first offer verification; a valid absent-record
result replaces it with the two resolution actions. Omit import/export menus
and diagnostic histories from this customer flow; retain their stored evidence.

Native phone billing refinement approved on2026-11-21: Android/iOS phones use
compact horizontal product cards and matching64px assistant/calculator controls
inside Actions. The owner then requested the hint visually flush to the right
edge; its gesture surface still extends inward beyond the OS back-gesture inset,
and the hint can also be tapped. Do not disable Android system navigation.
The final approved phone layout keeps only search above the catalog. Customer,
voucher and enabled price lists appear in the same flat Actions list as Tickets
and the existing tools, without section headings or nested cards. The panel uses
60% of the screen width, with a narrow transparent-to-white fade on the edge
facing the catalog, thin row separators and circular assistant/calculator
controls. A separate category icon on a white36px square matches the search
field. Existing selection handlers are reused. Checkout repeats the current customer,
voucher selector and optional price mode before confirmation. Normal cash sales
retain Cliente general without requiring customer selection. The owner authorized refining the phone
cart: small item count, no product thumbnails, rectangular line editor and
checkout surfaces flush with the side edges. Existing calculations and actions
are reused. These overrides exclude web, Windows and desktop tablet layouts.
The phone cart count is a small left label with its drag indicator independently
centered. Rows retain tap/double-tap editing and a single transparent trash
control with a22px icon inside a44px touch area; no duplicate edit action.
Phone product images use60px square areas, retaining contain fitting. The totals
surface has a subtle upward shadow and44px action buttons.
The native phone appbar reuses BrandedMenuButton (logo and menu); Tickets is
available inside Actions. Search/category/customer/
price icons use the owner's supplied PNG set; other platforms retain their icons.
Native phone drawers use75% width, flat48px group rows and a full-width square
account footer. Profile, users, settings, logout and user-management icons use
the supplied mobile_navigation assets with44px touch targets. Settings on phones
uses neutral list rows and dividers, reusing the shared destination list; App y
actualizaciones and Planes expose the existing update and plans routes. The global
floating assistant is hidden on native phone routes; the billing Actions entry
remains available. Desktop/web presentation stays unchanged.
Phone billing shows the existing CashTurnMenuButton with a compact state label
beside Actions. Scanning is inside Actions. The native phone drawer omits its
duplicate Turno group; other platforms retain their navigation and turn styling.

Native phone module review (2026-11-21): CustomAppBar prioritizes Back outside
billing and uses the billing blue gradient. MobilePageAppBar adapts direct bars;
Windows/web return the original widget. MobileActionIcon supplies the approved
back/search/filter/refresh PNGs only on Android/iOS phones. Shared mobile lists
use compact spacing while preserving touch areas and text scaling. Reportes
keeps its four primary KPIs visible and reveals detailed sections on request.
Fiscal pages without a desktop-independent header receive a native-only bar.
Coverage and remaining visual checks: AUDITORIA_UI_MOVIL_MODULOS_20261121.md.

Owner refinement after PR53 (2026-11-21): native phone Actions uses a solid white
75%-width panel with square edges, without a faded edge. The account footer has
one Users entry and the supplied outline logout icon. Usuario shows Back, PIN
and Filter without a department subtitle, search action or avatar; its Permisos
menu entry opens the existing permission editor directly. Native phone settings
omit the Windows update destination. Mobile printer settings retain all controls,
with square buttons and less common options under Opciones avanzadas. These
overrides do not change Windows/web presentation or authorization behavior.

Native phone refinement (2026-11-22): client detail uses the shared gradient
header, compact metric and information surfaces, and square form/dialog actions.
Native quotation history opens detail from the record tap and omits its duplicate
Ver detalle menu entry. Record-leading document ornaments are omitted on phone
quotation, purchase-invoice, client-timeline, fiscal-document and recent-report
lists; product photos, selection indicators and functional navigation icons stay.
The approved more.png asset replaces option ellipses through MobileActionIcon
and AppIcon only on native phones. Native popup menus use square corners.
The phone assistant fills the usable screen height, retaining system/keyboard
insets. Windows/web, including narrow Windows windows, keep their existing
presentation. Evidence: AJUSTES_MOVILES_CLIENTES_COTIZACIONES_IA_20261122.md.

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
- `CompactSquareSwitch` for compact company module controls: rectangular visual
  track, 44×40 interaction area, keyboard activation and toggled/disabled semantics.
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
