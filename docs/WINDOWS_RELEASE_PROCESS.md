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
