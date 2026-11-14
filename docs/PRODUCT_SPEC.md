# FullPOS Cloud Product Spec

Last audited: 2026-09-02.

This document describes confirmed product behavior from repository evidence only. Business rules not directly evidenced here are marked for owner validation.

## Product Purpose

FullPOS Cloud is a cloud-connected point-of-sale and business operations product for companies that need sales, inventory, clients, cash, purchasing, accounting/fiscal documents, staff, and operational workflows in one system.

Evidence: `apps/fulltech_app/README.md`, `apps/fulltech_app/lib/core/routing/routes.dart`, `apps/api/src/app.module.ts`, and `apps/api/prisma/schema.prisma`.

## Supported Platforms

- Flutter mobile: Android and iOS.
- Flutter Web/PWA.
- Flutter Windows desktop.
- Backend API: NestJS service intended for Docker/EasyPanel deployment.

Evidence: Flutter platform folders under `apps/fulltech_app/`, PWA Dockerfile, Windows runner files, Codemagic iOS workflows, and app README.

## Main User Types and Roles

Confirmed roles exist in Flutter and Prisma:

- `ADMIN`
- `CAJERO`
- `ASISTENTE`
- `VENDEDOR`
- `MARKETING`
- `TECNICO`

Role permissions are centralized on the Flutter side in `apps/fulltech_app/lib/core/auth/app_permissions.dart`. Backend role checks use JWT user context, `RolesGuard`, and Prisma role values.

## Main Modules

Confirmed application/API modules include:

- Authentication, registration, session restore, password recovery, account deletion.
- Users, profile, permissions, payroll, punch/time tracking.
- Catalog/products, product images, categories, inventory count, stock, Kardex.
- Warehouses, terminals, warehouse stock, transfers.
- POS sales, sales history, credits, reports.
- Cash box, sessions, movements, expenses, turn history.
- Clients, client detail, map/location features, CRM/commercial features.
- Quotations/cotizaciones and quotation PDFs.
- Purchases, suppliers, purchase orders, invoices, receipts, purchase PDFs.
- Accounting/contabilidad, daily closes, bank deposits, fiscal invoices, pending payments.
- Tax/NCF fiscal behavior for Dominican invoicing.
- Licenses and usage telemetry.
- Internal manual/company manual.
- AI assistant.
- Notifications.
- Storage/uploads/media gallery, including R2 presigned upload support.
- Service orders, technical operations, warranties, technical network, work scheduling.
- Marketing/publicidad, WhatsApp CRM, website-related modules.
- App updates and release download support.

## Core Business Capabilities

Confirmed capabilities:

- Tenant-scoped product/catalog, sale, purchase, cash, warehouse, and reporting operations.
- Product creation/update with stock and warehouse stock support.
- Product creation/editing can reuse the normal category creation dialog from the product form, preserving entered product data and selecting the newly created category.
- Inventory movements and Kardex-style history.
- Optional inventory tracking is honored for sales. New sale lines affect
  physical inventory only when company inventory is enabled, the catalog item is
  a `PRODUCT`, the product tracks inventory, and the line is a supported local
  catalog product. Manual/service/non-tracked lines still sell normally without
  stock validation or physical stock movement.
- The effective physical-inventory rule is
  `company.inventoryEnabled && product.itemType == PRODUCT &&
  product.trackInventory`. It also applies to purchase receipts that request
  stock updates, product stock adjustments/recounts, warehouse transfers, low
  stock warnings, valuation/stock views, and zero-config stock rows. Purchase
  orders/receipts may contain tracked products, non-inventory products, and
  services; only tracked physical products mutate stock.
- When measurement units are enabled for the company, quick/manual sale items can carry a configured unit-of-measure snapshot such as Unidad, Yarda, or Libra through sale creation.
- Multi-warehouse feature flag and terminal warehouse assignment.
- Cash session/movement workflows and close ticket printing.
- Cash drawer / money drawer support through a compatible thermal ESC/POS printer: a centralized cash-drawer service sends only the standard `ESC p` kick pulse through the configured receipt printer (Windows RAW spooler; mobile Bluetooth/LAN ESC/POS path). Includes a "Probar apertura de caja" action and optional automatic opening after eligible cash-sale prints (OFF by default).
- Sales fiscal payloads, tax calculation, NCF sequences and audit logs.
- Quotation and purchase document PDF generation.
- Product image upload and storage through API uploads and/or external object storage.
- Role and permission-based navigation/action access.
- Offline/cache/sync behavior for some frontend flows.

## Multi-Company Behavior

The data model uses `Company` as the tenant root. Many backend services require a `companyId` from the authenticated user via `requireTenant`. Services and tests show tenant-specific querying and protection, especially products, clients, sales, tax, users, warehouses, and cotizaciones.

Important invariant: tenant/company data must not mix across authenticated contexts.

Electronic invoicing postulations, fiscal identities, credentials and numbering
belong to each company. Dispatch uses the company's configured environment, so
authorized production companies and test companies can dispatch independently.
The server production permission does not replace that company's production
opt-in and certification. A prepared document is never redirected to another
environment or sent with a different environment's credentials.

FULLTECH SRL is the pilot for FullPOS integration trials. Those engineering
trials are not an extra manual onboarding step for every customer. Each customer
must still have its own DGII emitter authorization. The existing DOSA assistant
captures the certificate, its password and the certification portal password;
FullPOS does not duplicate that capture. The signed completion event bound to
the current postulation supplies the existing approval evidence, and the company
records its own authorization to emit. The customer requests authorized numbering
through the Oficina Virtual and registers it in the existing company flow.
Provider-assisted certification remains distinct from FullPOS engineering tests.
No new customer-facing TEST step or hardcoded FULLTECH restriction is introduced
by company environment routing. Existing assistant and certification work is
preserved. A final company action can activate production only after verified
certification, its own active production credential and explicit server gates.
Unresolved TEST outcomes block the transition. Strictly reviewed terminal
engineering trials can close readiness without changing their fiscal status;
commercial invoices and uncertain/pending results remain blocking. This action emits no invoice;
production numbering must then be registered separately for that company.

## Important Business Rules Evidenced

- Empresa activates the electronic invoicing module with one switch. Enabling
  it also enables company taxes in the same transaction, using the existing tax
  service to preserve a configured default tax or create the initial ITBIS. Disabling
  the module does not disable taxes or change historical sales.
- With the module enabled, Empresa exposes the price mode (ITBIS included or
  price plus ITBIS) and the optional sale without a voucher. The latter requires
  confirmation and defaults every new ticket to Normal when enabled. A deliberate
  electronic selection belongs to that ticket and survives draft restoration;
  it does not become the default for subsequent tickets.
- An explicit Normal sale persists `fiscalVoucherType=NORMAL`, with no NCF or
  expiry. It cannot be prepared as E31/E32, consumes no fiscal number and is
  never sent to DOSA/DGII. Its ticket and PDF remain ordinary documents, including
  applicable ITBIS, without electronic QR or fiscal identity. Tax calculation is
  independent of electronic emission. Existing ordinary offline permissions
  still apply. Historical NULL intents are not rewritten or reclassified.
- The drawer exposes electronic invoicing when enabled and authorized. The POS
  voucher selector additionally requires backend-confirmed readiness and an
  active, unexpired E31/E32 numbering range with remaining numbers. Turning on
  the module alone does not authorize fiscal emission or bypass checkout checks.
- Fiscal preparation freezes the original payment breakdown in the document.
  Subsequent credit collections are excluded when reconstructing that breakdown.
  DOSA dispatch preserves the prepared income type, payment terms and sequence expiry.
- DOSA consumer receipts below RD$250,000 may omit TrackId. Correlation then
  requires the official DGII consumer receipt URL, matching issuer/e-NCF/amount,
  a complete QR and a consumed sequence. Correlation alone does not grant fiscal
  acceptance. An explicitly enabled server DOSA contract can record its documented
  HTTP 200 accepted/conditionally accepted result only with a matching persisted
  response receipt, fiscal identity, fingerprints and valid QR. The audit identifies
  DOSA as the authority reporting the DGII result. Pending, rejected, mismatched or
  incomplete responses never qualify. E34 application remains subject to the
  original accepted document, evidence and available fiscal balance.
  An RFCE with no TrackId uses a clearly identified local receipt reference
  bound to environment/RNC/e-NCF; this is not a fabricated DGII TrackId.
- During the original DOSA dispatch, a timeout, network error or HTTP 5xx may
  trigger up to two audited repetitions of the identical request. No new e-NCF
  is assigned. The company's environment, authorization and credential must
  still match; accepted, conditionally accepted, rejected and HTTP 202 responses
  stop these immediate repetitions. After a lost response, process restart or
  HTTP202, an authorized user can verify using the identical original request
  only after the persisted lease expires. Stored hashes bind the destination,
  body, path, credential, document and environment. A row lock and ownership
  checks exclude competing/stale workers. No new e-NCF or financial sale is
  created; missing original identity requires review. A separate invoice GET
  is not required by the provider's confirmed contract.
- HTTP202 remains pending DGII. A complete validated provider stamp plus its
  contingency legend can print a QR in the existing ticket/PDF; it does not
  imply acceptance. Later verification must preserve that same fiscal identity.
- Users must be authenticated for tenant operations and must have an assigned company.
- `ADMIN` has broad backend access in `RolesGuard` and broad Flutter permissions.
- Non-admin access is controlled by role defaults and optional `userPermissions` overrides.
- UAT startup refuses protected production-like database names and remote hosts unless server UAT mode is explicitly configured.
- Products can be protected from hard deletion when business history exists; archival/idempotent behavior is tested in product service tenant tests.
- Measurement Units can be disabled only when no ACTIVE product uses a unit of measure other than the canonical `UNIT`. An active product is one whose `archivedAt` is null (state "activo"); an archived product (`archivedAt` set, state "archivado") never blocks disabling and keeps its historical UoM, sales/quotation/purchase snapshots, and inventory history unchanged. The disable validation is strictly company-scoped.
- `SaleItem.inventoryTrackedSnapshot` records whether that original sale line
  physically affected inventory. Cancellation and refund/return inventory
  restoration use this historical snapshot, not current company/product
  configuration, so later config changes do not alter the physical meaning of
  an existing sale.
- Product source can be `LOCAL` or an external FullPOS integration source.
- Cash drawer automatic opening is OFF by default (`autoOpenCashDrawer` for Windows/desktop). On Windows it opens only after a successful print of a NEW sale that involves cash (cash amount > 0 or method `cash`/`mixed`) and never on reprints (`isCopy`). On mobile (Android/iOS) automatic opening is governed by the existing mobile "Abrir gaveta" toggle (`openCashDrawer`) embedded in the ESC/POS print. A drawer failure never rolls back or corrupts a completed sale; it only surfaces a professional, non-blocking hardware warning. The physical output channel is configurable (`cashDrawerChannel`: Automatic / Drawer 1 Pin 2 / Drawer 2 Pin 5) because the RJ11/RJ12 pinout differs between printer and drawer models; Automatic keeps the historical Pin 2 behavior. The drawer test action also offers a one-shot "Drawer 2 (Pin 5)" probe for diagnosis without changing the saved configuration.
- Multi-warehouse access is gated in routing by company settings.
- API Docker startup can run migrations; seeds are controlled by `RUN_SEED`.
- Receipt payment section (EFECTIVO RECIBIDO / DEVUELTA): every sale can
  persist two distinct cash concepts alongside the net cash: `cashReceived`
  (cash the customer actually tendered) and `changeAmount` (DEVUELTA returned).
  `paymentCashAmount` ALWAYS keeps its accounting meaning of NET cash retained
  by the sale (`cashReceived - changeAmount == paymentCashAmount`). Both fields
  are nullable: legacy/historical sales whose tender was never stored keep
  `NULL`, and tickets for those sales must NOT fabricate EFECTIVO RECIBIDO or
  DEVUELTA rows. New cash sales (including exact tender) print
  `EFECTIVO RECIBIDO` and `DEVUELTA` (RD$ 0.00 for exact) from the persisted
  values; transfer/card-only and credit-without-cash transactions do not print
  cash rows. Reprints use the persisted tender so the reprint matches the
  original checkout. Cash sessions, shift closing, cash reports, and cash
  drawer eligibility all continue to use the NET `paymentCashAmount`.
- Credit sales are ACCRUAL for sales and profit (`Sale.totalSold` /
  `Sale.totalProfit` are recognized at `saleDate`; inventory decreases at sale
  time) and CASH / event-based for money. `Sale.paymentCashAmount` and
  `Sale.paymentTransferAmount` are the CUMULATIVE (lifetime) cash/transfer
  retained by that sale: the payment received at creation plus every later
  `SaleCreditPayment` abono. `SaleCreditPayment` (`sale_credit_payments`,
  `paidAt` / `cashSessionId` / `userId`) is the dated ledger of those abonos and
  is never added again on top of the cumulative fields (doing so counted the
  same money twice in cash sessions and under-registered credit refunds).
  Cash sessions therefore read `salesCashTotal` (cash retained when the shift's
  sales were created) plus `creditPaymentsCashTotal` (abonos collected in that
  shift), and reports attribute the initial payment to `saleDate` while each
  abono is attributed to its real `paidAt`; `Sale.creditBalance` is the
  accounts-receivable balance. Shared helpers and the exact derivation live in
  `apps/api/src/common/utils/sale-credit-payment.util.ts`.
- Reports > Ventas represents net sales performance, not cash flow. For the
  selected sale period, each non-deleted invoice contributes only its remaining
  economic value after returns: net sales, net historical snapshot cost, gross
  profit, category breakdowns, time series, tickets, and PDF metrics all derive
  from the same remaining-line calculation. Refund documents are not counted as
  negative sales. A fully returned sale contributes sales 0, cost 0, gross
  profit 0, and ticket count 0; a partially returned sale contributes only the
  remaining proportional revenue and cost. Net profit is gross profit minus
  expenses that affect profit. Credit sales remain accrual sales when issued;
  later credit payments affect collections/cash/accounts receivable, not sales
  performance.

## Date/Time Policy

- Storage: timestamps are stored and exchanged as real instants in UTC.
- Business timezone: DaleVentas uses `America/Santo_Domingo` as the canonical
  business timezone.
- UI/PDF/tickets: any date or time visible to the business or customer is
  converted to `America/Santo_Domingo` before formatting.
- Reports and daily cash boundaries: business days run from
  `00:00:00 America/Santo_Domingo` inclusive to the next business midnight
  exclusive, then those bounds are converted to UTC for database queries.
- Network: API timestamps must be ISO 8601 with `Z` or an explicit offset.
  Ambiguous timestamps without timezone must not be introduced.
- Manual offsets such as subtracting four hours are not allowed; use the
  canonical timezone helpers instead.

## Integrations

### Numeración electrónica por empresa y ambiente

- Emitir una factura electrónica exige conexión con el servidor. Sin conexión,
  aparece un aviso breve en la esquina superior derecha durante cuatro segundos.
  Una respuesta perdida se identifica como resultado pendiente y requiere revisar
  el estado antes de repetir; nunca se presenta como aceptación fiscal.
- El historial de ventas conserva la presentación habitual de ventas normales.
  Las electrónicas añaden tipo, e-NCF y estado; el detalle permite consultar el
  original y sus E34, imprimir y continuar acciones fiscales pendientes según
  permisos. TEST y aceptación condicional se identifican expresamente.
- Una venta electrónica se devuelve o anula mediante su devolución y nota E34;
  no utiliza la cancelación ordinaria. Una devolución financiera confirmada y una
  nota fiscal pendiente son resultados distintos y se muestran como tales. La
  recuperación de la nota no vuelve a devolver dinero ni inventario. Cuando el
  plazo fiscal requiere revisión, la nota no se prepara automáticamente.
- El PDF de una factura electrónica exige su representación fiscal persistida.
  Si falta, se informa del problema en lugar de descargar una factura ordinaria
  sin los datos fiscales. Los documentos pendientes no incorporan un QR inventado.

- La factura y el ticket electrónicos recuperan su identificación fiscal del
  documento persistido de la venta, con empresa, propietario autorizado y ambiente
  verificados en el servidor. Un QR firmado no se reconstruye desde datos actuales
  del cliente ni se fabrica para documentos pendientes o rechazados.
- La impresión incluye la URL pública DGII validada, código de seguridad y fecha
  de firma al pie. TEST se identifica sin validez fiscal. En A4 se repiten los
  datos fiscales y de consulta en cada página; las páginas intermedias presentan
  subtotales de las partidas realmente dibujadas. El monto de la venta debe
  coincidir con el comprobante antes de imprimir. Las ventas locales pendientes
  de sincronizar conservan su ticket interno sin inventar identidad fiscal.
- Alcance, evidencia y pendientes de impresión:
  [validación RI](ecf/ECF_PRINT_REPRESENTATION_2026-11-13.md).
  Las notas E34 también pueden imprimirse desde el detalle del comprobante:
  ticket con la impresora ya configurada o PDF fiscal A4. Se representan los
  artículos e importes acreditados, el e-NCF y fecha del original y el motivo
  de modificación; no se crea una venta o devolución nueva para imprimir.
  Ver [cierre de impresión E34](ecf/ECF_E34_PRINT_COMPLETION_2026-11-13.md).

- La numeración, autorización, contador e idempotencia fiscal pertenecen a una
  empresa y a un ambiente (`SANDBOX` / `PRODUCTION`). Cambiar de ambiente no copia
  rangos ni reinicia contadores. Un mismo texto de e-NCF puede existir en ambos
  ambientes, siempre que cada rango haya sido confirmado para ese ambiente.
- TEST requiere rangos y vencimientos confirmados por el proveedor para la
  empresa. Un correo de alta en producción o disponer de una clave TEST no
  demuestra que el rango productivo también esté autorizado para pruebas.
- El webhook DOSA conserva una proyección segura de los campos reconocidos de
  numeración como evidencia; no registra ni activa automáticamente esos rangos.
  Los eventos históricos cuyo resumen descartó esos datos no se reconstruyen.
- El despacho comprueba el ambiente persistido del documento, el configurado por
  la empresa y el de ejecución. Los documentos antiguos sin ambiente identificado
  no se despachan por inferencia; requieren revisión antes del despliegue.
- Evidencia y limitaciones de la implementación local:
  [separación TEST/producción](ecf/ECF_ENVIRONMENT_NUMBERING_2026-11-13.md).

Confirmed or configured integrations:

- PostgreSQL through Prisma.
- Redis optional cache/infrastructure.
- Cloudflare R2-compatible object storage through S3 SDK/presigned uploads.
- EasyPanel/Docker deployment.
- Codemagic iOS workflows.
- External FullPOS product integration via `FULLPOS_INTEGRATION_*`.
- Appyra usage telemetry settings.
- Email/password reset configuration using `RESEND_API_KEY` and mail sender variables.
- Maps/location packages on Flutter.
- Socket.IO realtime catalog relay.

## Current Important Limitations

- Root `README.md` is minimal and does not describe the current project.
- Existing documentation is extensive but scattered across root audit reports, phase reports, and `docs/`.
- Secret-bearing `.env` files exist in the local workspace and must not be exposed.
- Some modules appear broad and may contain legacy behavior; owner validation is required before changing fiscal, inventory, license, tenant, or production workflows.
- Cash drawer automatic opening is supported for POS/cash sale prints only. The web/PWA browser cannot issue low-level drawer commands; the drawer is a Windows or mobile Bluetooth/LAN hardware action. Manual drawer opening from other cash interfaces and drawer behavior on shift-close prints are pending owner decisions (see CASH-DRAWER-01 report).

## Unfinished or Experimental Areas

OWNER VALIDATION REQUIRED:

- Which marketing, WhatsApp CRM, technical network, AI assistant, and website features are production-ready versus experimental.
- Which visual evidence folders represent current accepted UI versus historical validation.
- Exact paid plan/license commercial limits beyond the code-level license service behavior.

### Reviewed legacy TEST numbering

Historical TEST classification preserves original allocation ledgers and counters.
A new Sandbox declaration/renewal/allocation must stay above its reviewed
frontier, including the original range counter; an unclassified TEST history
requires review before further TEST numbering. No production authorization is
copied to TEST and no historic counter is reset.

### Admission and ordinary printing

E31/E32 checkout must be authorized and locally preparable before confirming
the financial operation. If local fiscal preparation fails, no sale, stock
movement or committed numbering allocation remains. Provider transmission is a
subsequent operation with persisted recovery for uncertain results.

An ordinary sale can include ITBIS without being electronic. Explicit NORMAL
and older ordinary sales without an electronic fiscal link print their existing
taxes without requesting an e-CF projection. A linked historical electronic sale
still requires its fiscal projection; missing fiscal data cannot silently turn
it into an ordinary invoice.
