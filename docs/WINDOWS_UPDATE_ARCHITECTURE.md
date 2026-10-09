# Windows Auto-Update Architecture

Last updated: 2026-10-07.

This document records the Windows auto-update architecture used by FullPOS Cloud and the UAT findings from Phase 8. Production release is not approved by this document.

## Scope

The Windows updater flow is designed for installed Windows clients only:

1. The app checks the release API silently.
2. A newer Windows build downloads in the background.
3. The downloaded package is validated by file size, SHA-256, and signature policy.
4. The app persists `READY_TO_INSTALL`.
5. The shell shows only a discreet `Actualizar` control, with a dismiss button for the current build.
6. The user explicitly starts installation.
7. Safe restart coordination waits for active critical work before handing off to `FullposUpdater.exe`.
8. The updater launches the prepared Inno installer and writes an installer result.
9. On next startup the app reconciles installer result and installed build.

## User Experience Contract

- No update popup, blocking overlay, modal, or forced navigation is shown while checking, downloading, or verifying.
- The main shell shows the mini control only when the state is `READY_TO_INSTALL`, `INSTALL_REQUESTED`, or `WAITING_SAFE_STATE`.
- Dismiss stores `dismissedBuild`; it hides only that build in the shell and does not remove the package.
- `Configuración -> App -> Actualizaciones` remains the complete user-facing place for update status, release notes, and manual retry.
- Technical values such as SHA, paths, URLs, HTTP status, stack traces, PIDs, mutex names, and installer exit codes must not be shown to cashiers.

## Safe Restart

`UpdateRestartGuard` blocks restart only for active critical work:

- explicit update critical-operation gate;
- active critical print jobs tracked by `PrintActivityTracker`;
- financial sync currently processing through the offline sync queue service.

It does not block because a shift is open, a user session exists, the sales screen is open, a package is downloaded, the user is navigating, or a persisted offline queue exists.

Open shift preservation is a hard requirement. Updating FullPOS must not create `cash.close`, create a new shift, change `cashSessionId`, change `businessDate`, reassign sales, or mutate cash state.

## Installer Result Reconciliation

On startup the app reads persisted update state and `installer_result.json` where applicable.

- `SUCCESS` plus installed build matching target build becomes `INSTALLED_CONFIRMED`; stale package for the target build is discarded when safe, logs remain, and dismissed build is reset.
- `UAC_CANCELLED` returns to `READY_TO_INSTALL`; package remains and there is no automatic retry.
- `INSTALLER_FAILED` becomes `INSTALL_FAILED`; package remains and retry is manual.
- `SUCCESS` with installed build below target becomes `INSTALL_FAILED` with `POST_UPDATE_MISMATCH`; package remains and there is no automatic retry.
- Missing result after an updater-started state becomes a failure, not an automatic loop.

## Telemetry

The app emits minimal update events:

- `UPDATE_READY`
- `UPDATE_DISMISSED`
- `UPDATE_INSTALL_REQUESTED`
- `UPDATE_INSTALL_SUCCESS`
- `UPDATE_INSTALL_FAILED`
- `UPDATE_UAC_CANCELLED`

Allowed fields are installed build number, update state, target build, last update check timestamp, and last update result. Paths, SHA values, URLs, and secrets are not logged through this telemetry helper.

## Phase 8 UAT Findings

- Phase 7 implementation commit: `118f86246fee24745d557559e11aa84744ff31d6`.
- Phase 8 documentation commit: `677ec93655b498a020a37cbf97c69a9d4fbca5ab`.
- Source worktree: `C:\src\fullpos-update`.
- App version currently declared by Flutter: `1.0.6+130`.
- Local installer output compiled for Phase 8B pre-commit validation: `installer\output\FullPOS-Setup-1.0.6-130.exe`.
- Local installer SHA-256: `2BEA6E2A5E1FAE4E7E64B8194A2FCBE06A98F38C6B51808A3816D655E2A9B4D0`.
- Local installer size: `40165198` bytes.
- Authenticode status: `NotSigned`.
- Production Authenticode certificate: not available in this workspace.

The complete real end-to-end UAT was not executed in this workspace because the required non-production infrastructure was not available here: UAT API/DB identity, HTTPS artifact storage, UAT AppRelease creation/publishing credentials, a signed production certificate or explicit UAT unsigned release configuration, and a controlled installed N -> N+1 Windows test machine with business fixtures.

## Bootstrap Readiness

The bootstrap release can be technically prepared only after:

- the build is created from a known clean commit;
- the first installer is manually installed once on the target Windows device;
- subsequent updates use a strictly higher build number;
- UAT release metadata points to HTTPS storage, not `file://` or local paths;
- the update package passes size, SHA-256, and signature policy validation in UAT.

Production readiness additionally requires a production Authenticode certificate and a production-safe Inno Setup toolchain. Without those, production release remains NO-GO.

## Phase 8B Versioning Preparation

Windows release versioning is now prepared to use `apps/fulltech_app/pubspec.yaml`
as the single source of truth. With `version: 1.0.6+130`, the official release
script builds Flutter as `1.0.6+130`, passes `1.0.6` and `130` to Inno, and
produces `FullPOS-Setup-1.0.6-130.exe`.

For UAT N -> N+1, the bootstrap N must already include this updater. The next UAT
candidate must increment the build number in `pubspec.yaml` before building, for
example `1.0.6+131` or the next owner-approved marketing version. Do not reuse
build `130` for the UAT release record.

Unsigned packages are acceptable only when the UAT release policy explicitly
allows unsigned Windows packages. Production must continue to require a trusted
Authenticode signature and expected publisher validation.
