# Execution State

Last updated: 2026-10-07 12:35 local.

## Objective

Implement safe Windows release retention automation for FullPOS Cloud:
prepare/publish separation plus Windows/STABLE current+previous artifact
retention.

## Mode

`CONTINUOUS_CONTROLLED_EXECUTION`

## Environment

- Repository worktree: `C:\src\fullpos-update`
- Branch: `agent/windows-autoupdate-phase6b-build`
- Production authorization: not granted
- Production deployment: blocked
- Production Authenticode certificate: not available
- UAT unsigned update exception: enabled only for local UAT
- UAT API: `http://127.0.0.1:4000`
- UAT DB: `127.0.0.1:55432/daleventa_uat_local`
- UAT HTTPS artifact storage: `https://localhost:9443`
- Windows release retention target: keep current + previous, archive older
  Windows/STABLE artifacts only after publish verification.

## Final Builds

- Installed build N: `1.0.6+130`
- Installed update build N+1: `1.0.6+131`
- Final N+1 UAT installer SHA-256 used in the successful upgrade:
  `265EFDAB1A2CF27EE4E51DC8839B954AF5A1CDCCBBAA9B643737976613685D61`
- Final N+1 UAT installer size: `40167704`
- Authenticode status: unsigned, accepted only by the explicit local UAT policy.

## Completed

- Audited current AppRelease API and confirmed existing statuses were
  `DRAFT`, `PUBLISHED`, `REVOKED`; `REVOKED` is not reused for retention.
- Added AppRelease retention metadata:
  - `ARCHIVED` status.
  - exact `storageKey`.
  - `storageDeletedAt`.
- Implemented Windows/STABLE retention after publish:
  - keeps newest published build.
  - keeps immediate previous published build.
  - skips DRAFT, other platform, other channel, current, previous, unsafe keys,
    and missing keys.
  - deletes only an exact `storageKey` through the release storage adapter.
  - uses R2 by default and local exact-file deletion only for explicit local UAT.
  - marks deleted historical rows `ARCHIVED` and preserves DB history.
  - reports partial cleanup without reverting a successful publish.
- Added admin retention dry-run endpoint:
  `POST /api/app-updates/releases/retention/windows-stable`.
- Updated public update check to ignore releases whose artifact has been
  removed.
- Created release scripts:
  - `scripts/release/prepare_windows_release.ps1`
  - `scripts/release/publish_windows_release.ps1`
- Added surgical `.gitignore` exceptions so the release scripts are tracked
  without unignoring release artifact output directories.
- Updated `docs/WINDOWS_RELEASE_PROCESS.md` with prepare/publish/retention
  workflow.
- Resolved local Prisma `EPERM` by stopping the repo-local backend dev process
  that held the Prisma Windows query engine DLL.
- Applied migration `20261007130000_app_release_retention` to local UAT only
  after verifying DB identity and creating a logical UAT backup.
- Executed real local-UAT retention rotation:
  - `131/132 -> publish 133`: kept `133` and `132`, archived `131`, physically
    deleted artifact `131`, and update checks for builds `130`, `131`, `132`
    offered `133`; build `133` was up to date.
  - `132/133 -> publish 134`: kept `134` and `133`, archived `132`, physically
    deleted artifact `132`, and update checks for builds `132`, `133` offered
    `134`; build `134` was up to date.
- Verified controlled retention failure behavior in local UAT:
  - storage delete failure reports `PARTIAL`;
  - newly published current and previous remain `PUBLISHED`;
  - publish failure does not run cleanup;
  - DRAFT, other channels/platforms, and shared storage keys are preserved.

- Verified elevated agent privileges: `IsAdministrator=True`.
- Verified local UAT API, DB, and HTTPS storage.
- Built and installed build `1.0.6+130`.
- Published UAT AppRelease for build `1.0.6+131`.
- Verified update check returned build `131`.
- Verified silent download, size validation, SHA-256 validation, and `READY_TO_INSTALL`.
- Verified dismiss persistence: `dismissedBuild=131` persisted and did not delete the prepared package.
- Verified menu access from the real Windows topbar company menu: `Actualizaciones` is visible and navigates to the update screen.
- Verified UAC cancel path:
  - `installer_result.json` wrote `UAC_CANCELLED`.
  - exit code was `1223` (`ERROR_CANCELLED`).
  - installed build remained `1.0.6+130`.
  - package remained ready.
  - state returned to `READY_TO_INSTALL`.
  - no updater loop remained.
- Verified and corrected installer handoff bugs found during UAT:
  - local UAT official build URL validation needed an explicit localhost UAT exception.
  - same-build ready artifacts must not be cleared by a re-check.
  - Windows account menu needed an `Actualizaciones` entry in the real POS topbar.
  - native updater must materialize `.exe.ready` to `.exe` before invoking UAC.
  - Flutter must stage `FullposUpdater.exe` outside `Program Files` before launching so Inno can replace the installed updater.
- Verified upgrade path:
  - Inno installer exited `0`.
  - updater log recorded `INSTALLER_SUCCESS`.
  - app relaunched.
  - Windows registry reports `FullPOS 1.0.6 (build 131)`.
  - update state reconciled to `IDLE` / `UP_TO_DATE`.
  - prepared build directory was cleaned.
- Verified data preservation:
  - same cash session remained `OPEN`.
  - same business date remained `2026-10-07`.
  - company/user/product fixture remained scoped to the UAT tenant.
  - local app DB files remained present.
- Executed post-update UAT sale:
  - sale id `5815a377-8c0a-4d46-b59e-cd5761ac020b`.
  - product stock moved from `19` to `18`.
  - warehouse stock moved from `19` to `18`.
- Verified financial regression after update:
  - sales count moved from `3` to `4`.
  - net total sold moved from `100` to `150`.
  - total cost moved from `40` to `60`.
  - total profit moved from `60` to `90`.
  - commission total moved from `12` to `15`.

## Validation

- `npx prisma validate` with dummy local-safe `DATABASE_URL`: PASS.
- `npx prisma generate`: PASS after stopping the repo-local backend dev process
  that held the Prisma engine DLL.
- `npm run api:build`: PASS after Prisma DLL lock was released.
- `npm --workspace apps/api test -- app-updates`: PASS.
- `npm --workspace apps/api exec -- tsc -p tsconfig.build.json`: PASS.
- PowerShell parser validation for release scripts: PASS.
- `git check-ignore` for release scripts: PASS; scripts are no longer ignored.
- `prisma migrate deploy` against local UAT: PASS.
- `prisma migrate status` against local UAT: PASS.
- Real local-UAT retention rotation and failure scenarios: PASS.
- `flutter analyze`: PASS.
- Focused Flutter regression:
  `flutter test test\core\app_update\app_update_controller_test.dart test\core\config\product_config_test.dart test\modules\cotizaciones\company_account_menu_navigation_test.dart`: PASS.
- `npx prisma validate` with local UAT `DATABASE_URL`: PASS.
- Physical Windows UAT N -> N+1: PASS in local UAT with unsigned exception.

## Findings

- Production remains blocked because a production Authenticode certificate is not available.
- No production deployment, production database, customer data, or bridge changes were performed.
- The successful UAT used local-only unsigned policy; production must require trusted signing.
- Retention is code/test validated and real local-UAT rotation was executed
  against an isolated local storage root. Production storage was not touched.

## Next Action

Sign production Windows artifacts and execute signed final release UAT before
production rollout. Production remains NO-GO until signing and owner approval
exist.

## Status

READY_FOR_WINDOWS_RELEASE_AUTOMATION. Production NO-GO until Authenticode
certificate and explicit production approval exist.
