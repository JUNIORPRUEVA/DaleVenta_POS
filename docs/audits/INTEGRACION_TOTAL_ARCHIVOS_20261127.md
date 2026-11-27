# Archivos de la integración total — 27/11/2026

Lista obtenida mediante `git diff --name-status <base> HEAD` en cada worktree propio.
Los worktrees fuente se conservaron. No incluye secretos, logs o bases locales.

## FullPOS

Base: `afa566eb`. Worktree: `C:/t/fp-total-20261127`.

```text
M	.gitignore
A	apps/api/src/guardian/ai/crm-guardian-ai.provider.spec.ts
A	apps/api/src/guardian/ai/crm-guardian-ai.provider.ts
M	apps/api/src/guardian/ai/guardian.ai.runtime.ts
A	apps/api/src/guardian/guardian-worker.runner.spec.ts
M	apps/api/src/guardian/guardian-worker.runner.ts
M	apps/api/src/guardian/guardian.alert.readiness.pg.integration-spec.ts
M	apps/api/src/guardian/guardian.alert.readiness.spec.ts
M	apps/api/src/guardian/guardian.alert.readiness.ts
M	apps/api/src/guardian/guardian.alert.service.ts
M	apps/api/src/guardian/guardian.auto-enrollment.service.ts
M	apps/api/src/guardian/guardian.auto-enrollment.spec.ts
A	apps/api/src/guardian/guardian.backend-capture.service.spec.ts
M	apps/api/src/guardian/guardian.backend-capture.service.ts
A	apps/api/src/guardian/guardian.durable-outbox.ts
M	apps/api/src/guardian/guardian.ingest.service.ts
M	apps/api/src/guardian/guardian.module.ts
M	apps/api/src/guardian/guardian.platform.service.ts
A	apps/api/src/guardian/guardian.repair.pg.integration-spec.ts
M	apps/api/src/guardian/telemetry/guardian.telemetry.bridge.service.spec.ts
M	apps/api/src/guardian/telemetry/guardian.telemetry.bridge.service.ts
M	apps/api/src/reports/reports.credit-collection.spec.ts
M	apps/api/src/reports/reports.service.ts
M	apps/api/src/sales/sales.controller.ts
A	apps/api/src/sales/sales.credit-accounting.spec.ts
A	apps/api/src/sales/sales.credit-payment-regression.spec.ts
M	apps/api/src/sales/sales.service.inventory-optional.spec.ts
M	apps/api/src/sales/sales.service.tenant.spec.ts
M	apps/api/src/sales/sales.service.ts
A	apps/fulltech_app/assets/fonts/RobotoCondensed-Medium.ttf
A	apps/fulltech_app/assets/fonts/RobotoCondensed-OFL.txt
A	apps/fulltech_app/assets/fonts/RobotoCondensed-Regular.ttf
A	apps/fulltech_app/integration_test/credit_exact_print_payload_test.dart
A	apps/fulltech_app/integration_test/credit_ticket_native_test.dart
M	apps/fulltech_app/lib/core/api/api_client.dart
M	apps/fulltech_app/lib/core/app_update/app_update_controller.dart
M	apps/fulltech_app/lib/core/app_update/app_update_mini_control.dart
M	apps/fulltech_app/lib/core/app_update/app_update_models.dart
M	apps/fulltech_app/lib/core/app_update/app_update_persistence.dart
M	apps/fulltech_app/lib/core/app_update/app_update_persistence_store_io.dart
A	apps/fulltech_app/lib/core/app_update/update_critical_operation_gate.dart
M	apps/fulltech_app/lib/core/app_update/update_downloader_io.dart
M	apps/fulltech_app/lib/core/app_update/update_downloader_stub.dart
M	apps/fulltech_app/lib/core/app_update/update_restart_guard.dart
M	apps/fulltech_app/lib/core/app_update/update_signature_verifier_io.dart
M	apps/fulltech_app/lib/core/app_update/update_signature_verifier_stub.dart
M	apps/fulltech_app/lib/core/guardian/guardian_auto_transport.dart
M	apps/fulltech_app/lib/core/guardian/guardian_bootstrap.dart
M	apps/fulltech_app/lib/core/guardian/guardian_client.dart
M	apps/fulltech_app/lib/core/guardian/guardian_config.dart
M	apps/fulltech_app/lib/core/guardian/guardian_dio_transport.dart
M	apps/fulltech_app/lib/core/guardian/guardian_enrollment.dart
M	apps/fulltech_app/lib/core/guardian/guardian_event.dart
A	apps/fulltech_app/lib/core/guardian/guardian_identity.dart
M	apps/fulltech_app/lib/core/guardian/guardian_install_credential_store.dart
M	apps/fulltech_app/lib/core/guardian/guardian_machine_transport.dart
M	apps/fulltech_app/lib/core/guardian/guardian_reporter.dart
M	apps/fulltech_app/lib/core/guardian/guardian_sqflite_store.dart
M	apps/fulltech_app/lib/core/guardian/guardian_store.dart
M	apps/fulltech_app/lib/core/guardian/guardian_transport.dart
M	apps/fulltech_app/lib/core/guardian/guardian_web_store.dart
M	apps/fulltech_app/lib/core/offline/sync_queue_service.dart
M	apps/fulltech_app/lib/core/printing/ecf_print_footer.dart
M	apps/fulltech_app/lib/core/printing/esc_pos/fullpos_esc_pos_receipt_renderer.dart
M	apps/fulltech_app/lib/core/printing/esc_pos/thermal_receipt_view_model.dart
M	apps/fulltech_app/lib/core/printing/html/html_thermal_receipt_pdf_renderer.dart
M	apps/fulltech_app/lib/core/printing/html/html_thermal_receipt_renderer.dart
M	apps/fulltech_app/lib/core/printing/invoice_letter_pdf.dart
M	apps/fulltech_app/lib/core/printing/models/ticket_builder.dart
M	apps/fulltech_app/lib/core/printing/models/ticket_data.dart
M	apps/fulltech_app/lib/core/printing/models/ticket_renderer.dart
M	apps/fulltech_app/lib/core/printing/unified_ticket_printer.dart
M	apps/fulltech_app/lib/core/update/print_activity_tracker.dart
M	apps/fulltech_app/lib/core/widgets/fulltech_dialog.dart
M	apps/fulltech_app/lib/core/widgets/history_presentation.dart
A	apps/fulltech_app/lib/core/widgets/square_pos_dialog.dart
M	apps/fulltech_app/lib/features/account/account_menu_screens.dart
M	apps/fulltech_app/lib/features/reports/ui/reports_page.dart
M	apps/fulltech_app/lib/modules/cash/cash_dialogs.dart
M	apps/fulltech_app/lib/modules/cash/cash_repository.dart
M	apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart
M	apps/fulltech_app/lib/modules/cotizaciones/presentation/widgets/mobile_sales_controls.dart
M	apps/fulltech_app/lib/modules/cotizaciones/presentation/widgets/sales_ticket_bar.dart
M	apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart
M	apps/fulltech_app/lib/modules/ventas/sales_credit_screen.dart
M	apps/fulltech_app/lib/modules/ventas/tpv_sales_history_screen.dart
M	apps/fulltech_app/lib/modules/ventas/utils/sales_pdf_service.dart
M	apps/fulltech_app/test/core/app_update/app_update_controller_test.dart
M	apps/fulltech_app/test/core/app_update/update_downloader_io_test.dart
A	apps/fulltech_app/test/core/app_update/update_manifest_contract_regression_test.dart
A	apps/fulltech_app/test/core/app_update/update_operation_integration_test.dart
A	apps/fulltech_app/test/core/app_update/update_recovery_regression_test.dart
M	apps/fulltech_app/test/core/guardian/guardian_client_test.dart
M	apps/fulltech_app/test/core/guardian/guardian_machine_transport_test.dart
M	apps/fulltech_app/test/core/guardian/guardian_sqflite_store_test.dart
A	apps/fulltech_app/test/core/guardian/guardian_web_store_test.dart
A	apps/fulltech_app/test/core/printing/credit_invoice_pdf_unification_test.dart
A	apps/fulltech_app/test/core/printing/credit_ticket_test.dart
M	apps/fulltech_app/test/core/printing/html_thermal_receipt_renderer_test.dart
A	apps/fulltech_app/test/core/printing/thermal_80_fiscal_footer_test.dart
A	apps/fulltech_app/test/core/printing/thermal_80_layout_test.dart
A	apps/fulltech_app/test/core/printing/thermal_80_minimal_totals_test.dart
A	apps/fulltech_app/test/features/reports/credit_accounting_kpis_test.dart
M	apps/fulltech_app/test/features/ventas/ventas_recent_sales_repository_test.dart
A	apps/fulltech_app/test/modules/cash/cash_movement_dialog_design_test.dart
M	apps/fulltech_app/test/modules/cotizaciones/billing_ecf_selector_visible_test.dart
A	apps/fulltech_app/test/modules/ventas/credit_payment_durability_test.dart
A	apps/fulltech_app/test/modules/ventas/goldens/credit_compact_1266.png
A	apps/fulltech_app/test/modules/ventas/goldens/credit_compact_860.png
A	apps/fulltech_app/test/modules/ventas/goldens/credit_detail_390.png
M	apps/fulltech_app/test/modules/ventas/goldens/credit_empty_1024.png
M	apps/fulltech_app/test/modules/ventas/goldens/credit_empty_1920.png
M	apps/fulltech_app/test/modules/ventas/goldens/credit_history_1024.png
M	apps/fulltech_app/test/modules/ventas/goldens/credit_history_1920.png
M	apps/fulltech_app/test/modules/ventas/goldens/credit_history_2560.png
M	apps/fulltech_app/test/modules/ventas/goldens/credit_history_390.png
A	apps/fulltech_app/test/modules/ventas/goldens/linux/credit_compact_1266.png
A	apps/fulltech_app/test/modules/ventas/goldens/linux/credit_compact_860.png
A	apps/fulltech_app/test/modules/ventas/goldens/linux/credit_detail_390.png
M	apps/fulltech_app/test/modules/ventas/goldens/linux/credit_empty_1024.png
M	apps/fulltech_app/test/modules/ventas/goldens/linux/credit_empty_1920.png
M	apps/fulltech_app/test/modules/ventas/goldens/linux/credit_history_1024.png
M	apps/fulltech_app/test/modules/ventas/goldens/linux/credit_history_1920.png
M	apps/fulltech_app/test/modules/ventas/goldens/linux/credit_history_2560.png
M	apps/fulltech_app/test/modules/ventas/goldens/linux/credit_history_390.png
M	apps/fulltech_app/test/modules/ventas/related_history_design_test.dart
M	apps/fulltech_app/windows/updater/main.cpp
M	docs/ARCHITECTURE.md
M	docs/DESIGN_SYSTEM.md
M	docs/ENVIRONMENTS.md
M	docs/TESTING.md
M	docs/WINDOWS_UPDATE_ARCHITECTURE.md
A	docs/audits/CREDIT_TICKET_ABONOS_20261126.md
A	docs/audits/GUARDIAN_CIERRE_20261127.txt
A	docs/audits/INTEGRACION_TOTAL_20261127.md
A	docs/audits/POS_DIALOGOS_CUADRADOS_20261127.md
M	installer/setup.iss
M	scripts/build/build_windows_release.ps1
A	scripts/uat/credit-accounting-flow.cjs
A	scripts/uat/credit-ticket-flow.cjs
A	scripts/uat/guardian-real-fault-verification.cjs
A	scripts/uat/windows-updater-native-regression.ps1
```

## CRM

Base: `3651996`. Worktree: `C:/t/crm-total-20261127`.

```text
A	app/lib/features/guardian/guardian_screen.dart
M	app/lib/features/shell/crm_shell.dart
A	app/test/guardian_screen_test.dart
A	app/test/guardian_visual_test.dart
M	app/test/navigation_scope_test.dart
M	backend/scripts/check-daleventas-bridge.mjs
M	backend/server/crm-server.mjs
A	backend/server/guardian.mjs
A	backend/tests/guardian.test.js
A	docs/implementation/GUARDIAN_INTEGRATION_20261127.txt
A	docs/implementation/INTEGRACION_TOTAL_20261127.md
```

## APPYRA IA

Base: `8ee0458`. Worktree: `C:/t/ai-total-20261127`.

```text
M	AGENTS.md
A	apps/api/prisma/migrations/20261127190000_agent_customer_memory/migration.sql
A	apps/api/prisma/migrations/20261127210000_customer_memory_controls/migration.sql
M	apps/api/prisma/schema.prisma
M	apps/api/public/academy/api.js
M	apps/api/public/academy/app.js
M	apps/api/public/academy/biblioteca.js
A	apps/api/public/academy/chat-audio.js
M	apps/api/public/academy/conexiones.js
A	apps/api/public/academy/icons/nav-back.png
M	apps/api/public/academy/index.html
A	apps/api/public/academy/memoria.js
M	apps/api/public/academy/styles.css
M	apps/api/public/academy/sw.js
M	apps/api/src/modules/agent-runtime/agent-runtime.controller.ts
M	apps/api/src/modules/agent-runtime/agent-runtime.module.ts
M	apps/api/src/modules/agent-runtime/agent-runtime.service.ts
M	apps/api/src/modules/agent-runtime/dto/agent-runtime.dto.ts
M	apps/api/src/modules/audit/audit.module.ts
A	apps/api/src/modules/chat-audio.spec.ts
M	apps/api/src/modules/conversations/prompt/prompt-builder.ts
A	apps/api/src/modules/customer-memory/customer-memory.controller.ts
A	apps/api/src/modules/customer-memory/customer-memory.module.ts
A	apps/api/src/modules/customer-memory/customer-memory.service.spec.ts
A	apps/api/src/modules/customer-memory/customer-memory.service.ts
M	apps/api/src/modules/pwa-assets.spec.ts
M	apps/api/src/modules/simulator/session/session-answer.ts
A	apps/api/test/customer-memory.e2e-spec.ts
A	docs/PLAN_MEMORIA_Y_ENTRENAMIENTO_20261127.md
A	docs/PWA_MOVIL_20261127.md
A	docs/REVISION_BIBLIOTECA_MEMORIA_CHAT_20261127.md
```

## Puente (solo local, publicación bloqueada)

Base: `afa4230`. Worktree: `C:/t/bridge-total-20261127`.

```text
M	.dockerignore
A	.githooks/pre-commit
A	.githooks/pre-push
M	.gitignore
M	Dockerfile
A	INTEGRACION_TOTAL_20261127.md
A	backend/auth/issueCrmServiceCredential.js
A	backend/auth/serviceCredentials.js
M	backend/controllers/daleventasLicenseController.js
M	backend/controllers/publicLicenseController.js
A	backend/db/migrations/054_create_service_credentials.sql
A	backend/db/migrations/055_create_bank_transfer_payments.sql
M	backend/db/runMigrations.js
D	backend/keys/license_sign_private.pem
A	backend/middleware/paymentPolicy.js
A	backend/middleware/serviceAuth.js
M	backend/models/licensesModel.js
A	backend/routes/serviceBankTransferRoutes.js
A	backend/routes/serviceDaleventasRoutes.js
A	backend/routes/serviceLicenseOpsRoutes.js
A	backend/routes/serviceRoutes.js
M	backend/server.js
A	backend/services/bankTransferService.js
A	backend/utils/licenseTrustPolicy.js
M	package-lock.json
M	package.json
A	scripts/check-secrets.js
A	scripts/create-crm-service-credential-private.js
A	scripts/create-service-credential.js
A	tests/bank-transfer.test.js
A	tests/business-id-policy.test.js
A	tests/crm-private-credential.test.js
A	tests/license-trust-policy.test.js
A	tests/payment-app-resolver.test.js
A	tests/payment-policy.test.js
A	tests/paypal-payments.test.js
A	tests/secret-guard.test.js
A	tests/service-auth.test.js
A	tests/service-daleventas-read.test.js
A	tests/service-license-ops.test.js
```
