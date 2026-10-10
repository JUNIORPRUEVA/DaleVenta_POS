# Windows Release Process

Last updated: 2026-10-07.

This document defines the Windows release and UAT process for FullPOS Cloud. It complements `docs/RELEASE.md` and does not authorize production deployment.

## Version Source Of Truth

`apps/fulltech_app/pubspec.yaml` is the only release version source for Windows.
The official release script reads the `version: x.y.z+build` value and passes it to:

- Flutter `--build-name=x.y.z`;
- Flutter `--build-number=build`;
- Inno Setup `/DMyAppVersion=x.y.z`;
- Inno Setup `/DMyAppBuildNumber=build`;
- Inno Setup `/DMyAppVersionInfo=x.y.z.build`;
- installer filename `FullPOS-Setup-x.y.z-build.exe`;
- release metadata `version=x.y.z` and `buildNumber=build`.

Do not edit `installer/setup.iss` manually for a release version. Change
`pubspec.yaml` first, then run the official script.

## Required Worktree

Use a real short worktree, for example:

```text
C:\src\fullpos-update
```

Do not use `subst` for Windows release builds. Flutter, CMake, MSBuild, native plugins, and generated files can mix physical and mapped paths.

## Release Build Command

The official Windows release build path is:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build/build_windows_release.ps1
```

The script creates a temporary non-secret `.env` asset when the file is missing
and removes it afterward. It compiles Flutter, packages the installer with Inno
Setup, and prints version, build, commit SHA, installer path, size, SHA-256, and
Authenticode status. Do not commit `.env`.

Raw commands such as `flutter build windows --release` are useful validation steps, but they are not the official DaleVentas Windows release path.

### Signing Options

Production Windows releases must be signed. The build script can sign the
runtime executable, `FullposUpdater.exe`, and the final installer when signing
material is supplied out of band:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build/build_windows_release.ps1 `
  -SignArtifacts `
  -RequireSigning `
  -SigningCertificateThumbprint <cert-thumbprint> `
  -ExpectedSignerSubject "<publisher subject fragment>"
```

or, for a PFX file:

```powershell
$env:FULLPOS_SIGNING_CERT_PASSWORD = '<set outside command history>'
powershell -ExecutionPolicy Bypass -File scripts/build/build_windows_release.ps1 `
  -SignArtifacts `
  -RequireSigning `
  -SigningCertificatePath C:\secure\fullpos-code-signing.pfx `
  -SigningCertificatePasswordEnv FULLPOS_SIGNING_CERT_PASSWORD `
  -ExpectedSignerSubject "<publisher subject fragment>"
```

Do not store certificate passwords, private keys, PFX files, or certificate
material in the repository. If `-RequireSigning` is set and any required artifact
is not `Authenticode Valid`, the build aborts. UAT may use unsigned artifacts
only when the UAT policy explicitly passes the unsigned exception flags in the
prepare/publish flow.

## Prepare / Publish Automation

Windows release automation is intentionally split into two explicit steps.
Preparing a release must never publish it to clients.

Prepare a Windows release candidate:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/release/prepare_windows_release.ps1 `
  -ApiBaseUrl https://<uat-or-admin-api> `
  -PublicBaseUrl https://<artifact-public-base> `
  -StorageMode Local `
  -StorageRoot C:\fullpos-uat-storage `
  -AllowUnsignedUat
```

The prepare script reads `apps/fulltech_app/pubspec.yaml`, runs the official
Windows builder unless `-SkipBuild` is supplied, computes size and SHA-256,
checks Authenticode status, uploads the installer without overwriting an
existing object, verifies HTTPS download size/hash, and creates an AppRelease
`DRAFT`. The script prints `READY_TO_PUBLISH=YES` only after all of those
checks pass.

Dry-run a candidate plan without uploading, verifying a remote object, or
creating the draft:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/release/prepare_windows_release.ps1 `
  -ApiBaseUrl https://<uat-or-admin-api> `
  -PublicBaseUrl https://<artifact-public-base> `
  -StorageMode AwsCli `
  -S3BucketUri s3://<bucket> `
  -S3EndpointUrl https://<r2-account-endpoint> `
  -SkipBuild `
  -DryRun `
  -AllowUnsignedUat
```

`-DryRun` still validates the local installer metadata and signing policy. It
prints the exact storage key, download URL, and release payload, but does not
upload, publish, or delete anything.

Publish a prepared release:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/release/publish_windows_release.ps1 `
  -ReleaseId <draft-release-id> `
  -ApiBaseUrl https://<uat-or-admin-api> `
  -ConfirmPublish `
  -RetentionDryRun `
  -AllowUnsignedUat
```

Remove `-RetentionDryRun` only after reviewing the dry-run report. Publishing
validates the draft, re-downloads the artifact over HTTPS, verifies SHA-256 and
size, applies the signature policy, publishes the AppRelease, confirms
`GET /api/app-updates/check`, and then applies Windows/STABLE retention.
`-ConfirmPublish` is required so a release cannot be published accidentally by
running the publish script without an explicit publish intent.

Dry-run a prepared draft without publishing it:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/release/publish_windows_release.ps1 `
  -ReleaseId <draft-release-id> `
  -ApiBaseUrl https://<uat-or-admin-api> `
  -DryRun `
  -RetentionDryRun `
  -AllowUnsignedUat
```

The publish dry-run reads the draft, verifies the artifact download, size, hash,
and signature policy, then prints the publish payload and check URLs. It does not
change release status and never runs retention.

Both scripts read the admin bearer token from `FULLPOS_RELEASE_API_TOKEN` or
`-ApiToken`. Do not place tokens, access keys, or storage secrets in the
repository or in command transcripts.

## Windows/STABLE Retention

After a Windows/STABLE release is successfully published, FullPOS keeps only:

1. current release: newest published build;
2. previous release: immediate prior published build.

Older Windows/STABLE published releases are archived by deleting only their
exact storage object and preserving the AppRelease row for audit. `REVOKED`
remains reserved for untrusted/revoked releases; retention uses `ARCHIVED` and
`storageDeletedAt`.

Safe deletion rules:

- retention runs only after publish succeeds;
- dry-run is available and should be executed first;
- current and previous are never deleted;
- DRAFT releases are never deleted;
- other platforms and channels are ignored;
- deletion requires an exact `storageKey`;
- the key must be under `releases/windows/stable/` and end with the exact
  installer filename;
- no prefix, wildcard, recursive, or folder delete is used;
- storage delete failure does not roll back the newly published release and is
  reported as partial cleanup.

Storage provider:

- Production/default deletion uses `R2Service.deleteObject(storageKey)`, which
  calls the configured S3/R2 bucket with an exact object key.
- Local UAT may set `FULLPOS_RELEASE_STORAGE_MODE=local` and
  `FULLPOS_RELEASE_STORAGE_ROOT=<isolated-root>`; in that mode the release
  storage adapter deletes only the exact resolved file under that root.
- Production must not use the local UAT provider.

Read-only storage audit:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/release/audit_windows_release_storage.ps1 `
  -Prefix releases/windows/ `
  -SpecificKey releases/windows/stable/1.0.6-132/FullPOS-Setup-1.0.6-132.exe
```

The audit script loads R2/S3-compatible configuration from the current
environment and ignored env files, lists object metadata only, and never prints
access keys or secrets. It is read-only; it performs `ListObjectsV2` and
optional `HeadObject`.

Example rotation:

```text
Before publish: 131, 132
Publish:        133
Keep:           133, 132
Archive/delete: 131 artifact only

Next publish:   134
Keep:           134, 133
Archive/delete: 132 artifact only
```

## Inno Setup Requirement

Do not build production installers with Inno Setup preview builds.

Validated local toolchains on 2026-10-07:

- Inno Setup 7.0.0-preview-3 at `C:\Program Files\Inno Setup 7\ISCC.exe`: validation only, not production.
- Inno Setup 6.7.3 at `C:\Users\pc\AppData\Local\Programs\Inno Setup 6\ISCC.exe`: stable compiler used for the Phase 8 local installer compile.

For production, prefer the current stable Inno Setup version approved by the release owner. If using Inno Setup 7, use a stable release, not a preview. If signing is configured through Inno, keep signing inside the Inno `SignTool` flow so uninstaller and temporary setup copies are handled consistently.

If manual installer compilation is required for diagnosis, compile with the
stable compiler explicitly and pass values from `pubspec.yaml`:

```powershell
& 'C:\Users\pc\AppData\Local\Programs\Inno Setup 6\ISCC.exe' installer\setup.iss /DMyAppVersion=1.0.6 /DMyAppBuildNumber=130 /DMyAppVersionInfo=1.0.6.130
```

## Artifact Metadata

Every UAT or production candidate must record:

- commit SHA;
- Flutter version/build from `apps/fulltech_app/pubspec.yaml`;
- installer filename;
- file size;
- SHA-256;
- Authenticode status and signer;
- Inno Setup compiler version;
- release channel and environment;
- release notes;
- whether the package is signed.

Phase 8B local pre-commit validation artifact:

```text
Commit: pre-versioning-commit validation run
Flutter version: 1.0.6+130
Installer: installer\output\FullPOS-Setup-1.0.6-130.exe
Size: 40165198 bytes
SHA-256: 2BEA6E2A5E1FAE4E7E64B8194A2FCBE06A98F38C6B51808A3816D655E2A9B4D0
Authenticode: NotSigned
Inno compiler: 6.7.3
```

## UAT Release Requirements

UAT must not use production API, production database, production storage, or production release records.

Required UAT infrastructure:

- API local or UAT;
- DB local or UAT;
- HTTPS artifact storage for the installer;
- UAT AppRelease record with unique build number;
- non-production company and user fixtures;
- controlled installed Windows machine or VM;
- explicit unsigned UAT policy if no certificate is available.

The installer download URL in release metadata must be HTTPS. Do not use `file://` or a local path in the manifest.

## UAT Procedure Summary

1. Install version N.
2. Capture pre-UAT snapshot: installed build, company, user, open shift, local DB path, relevant row counts, pending queue count, printer settings, device identity, and non-sensitive config.
3. Publish version N+1 only in UAT.
4. Confirm silent check and background download.
5. Confirm size, SHA-256, and signature policy validation.
6. Confirm `READY_TO_INSTALL` and discreet mini control.
7. Test dismiss and settings visibility.
8. Keep an open shift and prove it does not block update.
9. Test critical operation wait.
10. Accept UAC and verify Inno upgrade.
11. Confirm relaunch, build match, state cleanup, and no success popup.
12. Compare pre/post data preservation.
13. Test post-update sale, cash movement, refund, credit payment, and offline replay if the UAT fixtures permit them.
14. Execute failure tests with controlled artifacts and harnesses.

## Manual UAT Script

### UAT A: No Install

1. Open the installed FullPOS build and go to `Configuración -> App -> Actualizaciones`.
2. Capture the displayed installed version/build.
3. Confirm the screen is usable and does not show a blocking update dialog.
4. Close and reopen the app.
5. Confirm the same build is still reported and no same-version update is offered.

Return: installed build, screenshot of the update screen, and whether any update
prompt appeared.

### UAT B: N -> N+1

1. Install build `N` with the official installer.
2. Open FullPOS and confirm the installed build in the update screen.
3. Publish only the UAT release record for build `N+1`.
4. Reopen FullPOS or resume it from background.
5. Wait up to one minute for the silent update check and background download.
6. Confirm the shell shows only the discreet `Actualizar` control when ready.
7. Open `Configuración -> App -> Actualizaciones` and confirm build `N+1` is
   shown with release notes and no technical SHA/path/URL details.
8. Click `Actualizar ahora`.
9. Accept UAC when Windows asks.
10. Confirm FullPOS closes once, the installer runs, and FullPOS reopens once.
11. Confirm the installed build is now `N+1`.
12. Close and reopen FullPOS.
13. Confirm build `N+1` is not offered again.
14. Run one sale/cash smoke path in the UAT company and confirm the previous
   cash session/company context was preserved.

Return: screenshots of pre-version, ready state, post-version, and a note of
whether UAC was accepted or cancelled.

### UAT Failure Checks

- No internet: disable network before opening FullPOS; expected result is normal
  app usage and a non-blocking update failure state.
- 404 URL: publish a UAT draft/release with an intentionally missing artifact;
  expected result is no installer execution and retry available from settings.
- Bad SHA: publish a UAT release with mismatched SHA; expected result is hash
  failure, no `.ready` package, and no installer execution.
- Interrupted download: stop the UAT artifact server mid-download; expected
  result is a discarded `.part` file and no installer execution.

Return: the visible state, whether FullPOS remained usable, and any non-secret
update log lines from `%LOCALAPPDATA%\DaleVentas POS\logs\updates`.

## Final Pre-Publication Checklist

- [ ] Large Dataset integrated into the release candidate branch.
- [ ] Suite global green for affected frontend and backend areas.
- [ ] `apps/fulltech_app/pubspec.yaml` incremented; build number not reused.
- [ ] Official Windows build generated from a clean short worktree.
- [ ] `fullpos_cloud.exe` signed and `Authenticode Valid`.
- [ ] `FullposUpdater.exe` signed and `Authenticode Valid`.
- [ ] Final installer signed and `Authenticode Valid`.
- [ ] SHA-256 and size recorded.
- [ ] Remote object uploaded to exact `releases/windows/stable/<version-build>/...` key.
- [ ] Remote object size/hash verified by download.
- [ ] AppRelease `DRAFT` created.
- [ ] AppRelease published only after owner approval.
- [ ] `/api/app-updates/check` announces the new build for previous builds.
- [ ] Real download URL works over HTTPS.
- [ ] UAT N -> N+1 PASS.
- [ ] Previous release preserved.
- [ ] Retention dry-run reviewed.
- [ ] Retention live run executed only after publish verification.
- [ ] Current build no longer offers itself as an update.

## Failure Recovery Tests

The UAT matrix must cover:

- network interruption during download;
- network interruption near completion;
- app closed during download;
- wrong SHA;
- invalid or disallowed signature;
- UAC cancelled;
- installer failure;
- build mismatch after reported success;
- disk-full or equivalent harness failure;
- revoked release after download.

Do not fill the host disk to simulate disk-full unless a safe bounded harness is available.

## Production Gate

Production remains NO-GO unless all are true:

- complete UAT passed with evidence;
- production Authenticode certificate is available and used;
- installer is compiled with an approved stable Inno Setup toolchain;
- release metadata uses HTTPS artifact storage;
- rollback path is defined;
- owner explicitly approves production release in the current task;
- no production database or infrastructure change is hidden inside the release.

Phase 8 status: implementation can continue to UAT, but controlled production release is NO-GO because real UAT was not completed and the local installer is not Authenticode-signed.

Phase 8B UAT preparation status:

- versioning consistency is corrected in code and script;
- local UAT Docker workflow exists, but Docker is not installed in this session;
- `.env.uat.local` was not present in this worktree during the audit;
- port `127.0.0.1:55432` responded, but DB identity was not proven from repository tooling;
- no UAT migration, seed, AppRelease publication, or release revocation was executed;
- no HTTPS UAT storage credentials or R2/S3 UAT variables were available in this shell.
