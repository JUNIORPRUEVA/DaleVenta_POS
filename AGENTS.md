# Project Agent Instructions

Binding policy for **every** AI agent working in this repository (GitHub Copilot, Codex, DeepSeek, or any other).
FullPOS Cloud is a live product used by real businesses: treat every change as production-adjacent.

Entry points:

- `AGENTS.md` (this file) — the canonical agent policy.
- `.github/copilot-instructions.md` — short pointer used by GitHub Copilot Chat. It must not become a parallel policy.
- `.github/instructions/*.instructions.md` — path-scoped rules (Flutter / API / Prisma) loaded when matching files are touched.

If a user request conflicts with a rule here, state the conflict before acting instead of silently ignoring either side.

## 1. Purpose

An agent working here must be:

1. **Accurate** — every factual claim comes from real code, real config, real test output, or consulted documentation. Nothing is invented.
2. **Safe** — production is protected, tenant isolation is preserved, no destructive data operation happens without explicit authorization in the current task.
3. **Complete** — the original request is fully covered and verified before reporting success. Partial work is reported as partial, never as done.
4. **Minimal** — only the files and lines required by the task change. No opportunistic refactors.
5. **Honest** — failed checks, skipped validations, and environment blockers are reported, never hidden.

## 2. Project Architecture

Verified from the repository (not assumed):

| Area | Path | Stack actually used |
| --- | --- | --- |
| Client app (Android, iOS, Web/PWA, Windows) | `apps/fulltech_app` | Flutter 3.41.6 / Dart 3.11.4 (`environment.sdk: ^3.10.1`), package `daleventa_pos`, version `1.0.5+124`; Riverpod 2, go_router 10, dio 5, flutter_secure_storage, shared_preferences, freezed / json_serializable, intl, cached_network_image |
| Backend API | `apps/api` | NestJS 11, TypeScript 5.6, Prisma 5.22 (`prisma-client-js`), PostgreSQL, Jest 30 + ts-jest + supertest, socket.io, ioredis, pdfkit, sharp, AWS S3 SDK (R2 media) |
| Data layer | `apps/api/prisma` | `schema.prisma` (provider `postgresql`), migrations, `seed.cjs` |
| Monorepo tooling | root `package.json` | npm workspaces (`apps/*`); Node 24.x locally, Node 20 in CI; PowerShell scripts under `scripts/` |
| CI (backend + Flutter gates) | `.github/workflows/multi-tenant-security.yml` | `prisma validate`, tenant/endpoint audits, Jest, API build, `flutter analyze`, `flutter test` |
| Mobile release CI | `codemagic.yaml` | iOS release without codesign, iOS TestFlight |
| Desktop release + installer | `scripts/release/`, `installer/` | `build_windows_release.ps1`, Inno Setup (`installer/setup.iss`) |
| Local task shortcuts | `.vscode/tasks.json` | `fullpos-windows-preflight`, `fullpos-flutter-pub-get`, `fullpos-flutter-analyze`, `fullpos-test-cotizaciones`, `fullpos-build-windows-release` |
| Governance docs | `docs/`, root audit reports | canonical project source of truth (see §3) |

Code layout: client `apps/fulltech_app/lib/{core,features,modules}`; backend `apps/api/src/<domain>` (auth, sales, cash, inventory, products, clients, purchases, tax, warehouses, license, users, reports, contabilidad, cotizaciones, payroll, notifications, storage, order-document-flow, ai-assistant, ...).

Architecture rules: UI → state → data separation; one data source of truth (backend/database); shared Riverpod state instead of per-screen copies; no duplicated models.

Always preserve the existing architecture, tenant isolation, licensing behavior, and business behavior unless the current task explicitly requires a change.

## 3. Source of Truth

Canonical project documents (read the relevant one **before** working; do not duplicate or contradict them):

- Business rules and product behavior: `docs/PRODUCT_SPEC.md`
- Architecture, data, backend, Prisma, auth, tenant boundaries: `docs/ARCHITECTURE.md`
- Environment, server, database, deployment target, production safety: `docs/ENVIRONMENTS.md`
- UI/UX, visual system, reusable components: `docs/DESIGN_SYSTEM.md`
- Testing, validation, GO/NO-GO: `docs/TESTING.md`
- Release process and safeguards: `docs/RELEASE.md`
- Development workflow, phases, checkpoints: `docs/WORKFLOW.md`

Routing for UI work: always read `docs/DESIGN_SYSTEM.md` before touching screens, widgets, navigation, layout, typography, colors, spacing, icons, dialogs, empty/loading/error states, responsive behavior, or visual assets. Add `docs/PRODUCT_SPEC.md` when the UI displays, edits, filters, hides, validates, or labels products, inventory, warehouses, sales, cash, fiscal/tax, licenses, users, roles, tenants, clients, purchases, service orders, or accounting. Add `docs/ARCHITECTURE.md` when routing, state management, API contracts, offline/cache/sync, auth/authorization, tenant boundaries, storage, printing/PDF, or backend data flow are involved. Add `docs/ENVIRONMENTS.md` when API targets, runtime config, `.env`, seeded data, uploaded media, external services, or any database-adjacent validation are involved.

Supporting evidence (audits, reports, visual evidence folders) may be used as context but never as a replacement for the canonical docs. If reality and documentation disagree, report the discrepancy instead of silently following one.

## 4. Tool Usage Policy

Tools must be used when they raise accuracy, and skipped when they only consume context or carry risk. Verified availability in this workspace (checked during the policy audit that created this file):

| Tool | Real status | Use it when | Do not use it when |
| --- | --- | --- | --- |
| Terminal (`pwsh`) | Available | running the documented commands of §11, `git` inspection, builds, tests | as a way to edit files; for destructive or production-touching operations |
| File read / search / edit tools | Available | always, as the first step of any task | — |
| Context7 MCP | Verified working (`resolve-library-id`, `query-docs`) | the task depends on a framework, SDK, package, or external API — Flutter, Dart, Riverpod, go_router, dio, Material, NestJS, Node, Prisma, PostgreSQL | general programming concepts, refactors, code review, business-logic questions, or when the installed version is already known and stable |
| Figma MCP | Verified authenticated (Figma user `JR Digital`, starter-tier plan → limited tool-call quota) | UI/UX, design, responsive, layout, spacing, typography, color, components — when an approved design exists or the user asks for a design/concept first | backend/data tasks; speculative or exploratory calls that burn quota; assuming a design exists when it does not |
| Playwright MCP | Configured in `.vscode/mcp.json` (`microsoft/playwright-mcp`); browser tools exposed | validating browser-reachable surfaces (Flutter web/PWA): load, routing, buttons, forms, console errors, overflow, responsive basics, after UI changes | as a substitute for unit/widget tests; against production or any environment whose data must not change |
| Vision / images | `view_image` works on local image files; screenshots returned by the Figma MCP may arrive without usable image content in this environment | the user attaches a screenshot, design, or visual error to inspect | claiming an image was inspected when it could not be rendered — say so explicitly instead |
| GitHub integration | **Not available** as a tool in this session. Remote is `https://github.com/JUNIORPRUEVA/DaleVenta_POS.git`, branch `production-main`, `git` CLI available | history, blame, diff, branch and change inspection through `git` | `commit`, `push`, `merge`, PR, tag, or release without explicit authorization in the current task |
| Subagent `fulltech-super` | Available (`.github/agents/fulltech-general.agent.md`) | large, multi-step FULLTECH work that benefits from isolated context | trivial single-file edits |
| Pylance / VS Code API docs tools | Present but **not applicable** (Python tooling and extension development) | — | this repository |

Policy details:

- **Context7**: identify the version the project really uses first (`pubspec.yaml`, `package.json`, `pubspec.lock`, `package-lock.json`), then look up documentation compatible with **that** version. Never silently upgrade a pattern to the newest release. If current documentation contradicts the existing implementation, report the risk before making a significant change.
- **Figma**: an approved design is the visual source of truth. Do not invent padding, margin, gap, radius, color, size, typography, or visual hierarchy when a corresponding design is available. When the user asks for a visual concept first, produce/agree the design before changing Flutter code.
- **Playwright**: it is browser evidence, not functional proof of business logic. Prefer local/dev targets; never drive production data.
- **Vision**: image inspection failure must be declared. Structural inspection (layout measurement, overflow detection, placeholder search) is a weaker substitute and must be labelled as such.
- Never state that a tool was used if it was not executed in that task.

## 5. Before Editing

For any non-trivial change, in order:

1. Restate the requirement and its acceptance criteria.
2. Locate and read the related code, configuration, and docs (§3).
3. Identify the real execution flow end-to-end (UI → state → API → data).
4. Identify the files responsible for each layer.
5. Look for side effects, callers, and dependents before changing a contract.
6. Detect existing tests covering the behavior.
7. Consult external documentation (§4) when a dependency version matters.
8. Confirm the change is the smallest one that satisfies the request.

If the user asks for an **audit**: do not modify code. Report findings with evidence.
If the user asks for a **fix or implementation**: audit enough to know the real cause, then modify.

**Concurrency**: other agents, editor tabs, or running processes may write to this workspace at the same time. Attribute only your own edits — check them with `git diff -- <your files>` — and never report a third-party change as yours. While another writer may be active, avoid workspace-wide operations (global formatters, `git checkout .`, mass renames, repo-wide `--fix`) and re-run the validation of your area before reporting GO.

## 6. Implementation Rules

**Scope**: change only what the requirement needs. Forbidden: refactoring unrelated areas, mass renaming, unapproved architectural changes, unnecessary dependencies, renaming persistent identifiers for aesthetics, and fixing unrelated defects. If you find an unrelated problem, report it and do not expand the scope silently.

**No inventing**: never invent files, endpoints, models, tables, methods, commands, test results, production behavior, image content, or external documentation. Every important claim must be traceable to real code, real configuration, a real test run, a real tool result, or consulted documentation. Label claims as **HECHO** (verified), **HIPÓTESIS** (plausible, not verified), or **RECOMENDACIÓN** (opinion/proposal).

**Single source of truth**: data comes from the backend/database. Never hardcode dynamic values, duplicate models, or create parallel data structures. If data changes, it must update everywhere consistently.

**Root cause over symptoms**: never "force a UI refresh" to hide a state or backend problem. Fix the synchronization or backend cause.

**Compatibility**: before changing behavior, verify existing data, existing clients, and existing caches keep working (backend defaults, model parsing, backward compatibility).

**Error handling**: never fail silently. Log errors with stack traces, surface clear user-facing messages, and keep loading/error/empty states meaningful.

**No leftovers**: no debug prints, no temporary `TODO`s, no commented-out code, no hardcoded test values in committed code.

**High-risk change protocol** (auth, payments, cash, inventory, credits, accounting, permissions, migrations, multi-company/tenant, sync, offline, printing/fiscal, release, production): AUDIT → PLAN → IMPLEMENT → VALIDATE → REVIEW DIFF → REVALIDATE → REPORT GO/NO-GO. Do not skip the plan step, and do not advance to another phase automatically.

**Phases**: if the task describes phases, complete and validate the current phase only, then stop and report. Do not continue to the next phase without approval.

## 7. UI/UX Rules

1. Reuse the existing design system, shared widgets, and theme tokens (`docs/DESIGN_SYSTEM.md`); do not invent a separate visual language for a new screen.
2. If an approved Figma design exists, it is the visual source of truth (§4).
3. Avoid arbitrary values: keep spacing, typography, radius, elevation, color, and sizing consistent with existing conventions.
4. Never sacrifice usability for decoration; keep dynamic UI rules — hide sections that are irrelevant to the current state.
5. Always check: overflow, truncation, contrast, touch target size, responsive behavior, real text length, and loading / error / empty states.
6. Do not change business logic during a visual redesign unless explicitly requested.
7. User-facing text follows the product's existing language and tone; keep Spanish user-facing strings consistent with the rest of the app.
8. Performance: avoid unnecessary rebuilds and heavy work inside build methods; keep long lists efficient.

## 8. Backend/Data Rules

Before modifying backend behavior: understand existing contracts, review the frontend call sites, review validation, review transactions, check idempotency where relevant (sales, cash, sync, payments), and verify tenant/company isolation is preserved.

- Multi-tenant isolation and company data boundaries are non-negotiable: every query and mutation stays scoped to the authenticated tenant/company.
- Preserve API response shapes unless the task explicitly changes the contract; when it changes, update the client mapping in the same task.
- Reuse existing DTO/validation patterns; do not weaken validation.
- Never add a query that can read another tenant's data, even in scripts or reports.
- Never execute destructive operations (DROP, TRUNCATE, mass DELETE/UPDATE, production migration, purge, repair, backfill with `--apply`) without explicit authorization in the current task.
- Licenses, tenant ownership, inventory, sales, cash, fiscal, payroll, and accounting behavior changes require explicit authorization in the current task.

## 9. Security Rules

Never print, log, echo, or include in a response: API keys, access tokens, passwords, `DATABASE_URL`, JWT secrets, private keys, credentials, or any `.env` value. Never add secrets to the repository. If a tool returns a secret, redact it. Do not weaken authentication, authorization, or tenant scoping to make a test pass.

## 10. Production Safety

Production is **read-only and protected by default**. Without explicit authorization in the current task, do not: deploy, restart services, run migrations, modify data, create users/sales/payments, delete anything, change infrastructure, or run seeds (`npm run api:seed`, `prisma:seed`).

Explicit authorization in the current task is required for:

- Seeds, purge scripts, destructive scripts, repair/backfill/fix scripts, and any `--apply` variant.
- Prisma migrations against any shared, staging, UAT, or production database.
- Production deployment, production configuration, or release artifact generation (`scripts/release/*`, `installer/*`, Codemagic publishing).
- Changes to credentials, secrets, `.env` values, license enforcement, tenant ownership, inventory, sales, cash, fiscal, payroll, or accounting behavior.

Prefer LOCAL / TEST / UAT / ACCEPTANCE environments for validation. Use checkpoints and backups where `docs/WORKFLOW.md` and `docs/RELEASE.md` require them.

## 11. Testing and Validation

`CODE PASS` is not `FUNCTIONAL PASS`. Commands below are the real ones of this repository — use them, do not invent alternatives.

Flutter (working directory `apps/fulltech_app`):

- Install deps: `flutter pub get`
- Static analysis: `flutter analyze`
- All tests: `flutter test`
- Scoped tests: `flutter test test/modules/cotizaciones` or `flutter test test/path/to_test.dart`
- Integration tests: `flutter test integration_test/<file>.dart`
- Builds: `flutter build web --release`, `flutter build apk --release`, `flutter build windows --release`
- Official DaleVentas Windows release artifact: `scripts/release/build_windows_release.ps1` — a raw `flutter build windows` is not the release path (`docs/RELEASE.md`)

Backend (from repository root):

- Install deps: `npm ci`
- Build / typecheck: `npm run api:build` (runs `prisma generate` + `tsc`)
- Schema validation: `npx prisma validate` from `apps/api`
- All non-e2e tests: `npm --workspace apps/api test`
- Scoped suites: `npm --workspace apps/api run test:unit | test:integration | test:e2e | test:security | test:tenant | test:deletion`
- Local API and smoke: `npm run api:dev`, `npm run api:smoke`, `npm --workspace apps/api run test:smoke`

CI parity: `.github/workflows/multi-tenant-security.yml` runs `prisma validate`, tenant/endpoint audits, backend tests, backend build, `flutter analyze`, and `flutter test`. Local validation should cover what applies to the change.

Validation order:

```text
IMPLEMENTATION -> STATIC ANALYSIS -> AUTOMATED TESTS -> FUNCTIONAL VALIDATION -> VISUAL VALIDATION -> REGRESSION -> GO / NO-GO
```

Rules:

- Run the tests closest to the change first, then widen for medium/high-risk changes.
- A task is not complete if the modified area does not analyze/build, unless an external blocker is demonstrated with evidence. Never say "it should compile".
- If a pre-existing failure blocks the full build/test run: prove it is pre-existing, run the most specific validation possible on the changed area, and report it.
- Never hide a failing test. Determine whether the failure was caused by the change; if yes, fix it before reporting; if no, document it with evidence.
- User-facing changes require functional validation; UI changes require visual validation on the relevant form factor when tooling allows.
- Changes to tenant/auth, inventory/warehouse, sales/fiscal/tax, cash, offline/sync, or releases require the extra regression scope described in `docs/TESTING.md`.
- Hardware-dependent behavior (cash drawer / printer) cannot receive a GO from automated tests alone. Hardware results must never be fabricated.

## 12. Definition of Done

Before reporting an implementation as finished, all applicable items must be true:

- [ ] Original requirement fully covered (re-read the request and check it item by item).
- [ ] Scope respected (no unrelated files, no unrelated refactors).
- [ ] Final diff reviewed: no accidental changes, no leftover debug code, no temporary `TODO`s, no hardcoded values, no secrets, no out-of-scope edits.
- [ ] Static analysis / lint PASS (`flutter analyze`; backend build/typecheck).
- [ ] Compilation PASS for the modified area.
- [ ] Relevant tests PASS; broader tests PASS when the change is medium/high risk.
- [ ] Failures not caused by the change documented with evidence.
- [ ] UI validated functionally, and visually when modified.
- [ ] Playwright used for web/PWA validation when it added real evidence.
- [ ] Figma compared when it was the visual source of truth.
- [ ] Context7 consulted when the change depended on external/versioned documentation.
- [ ] No production, production data, or shared database was modified.
- [ ] Remaining risks, pending items, and blockers documented.

If a mandatory item fails, the final status is **NO-GO**. Never present the task as finished.

## 13. Failure / NO-GO Rules

Self-correction loop: when a validation failure is caused by your own change, do not stop and report immediately — fix it within scope and repeat EDIT → VALIDATE → CORRECT → VALIDATE until it passes. Limit: **3** correction attempts on the same failure; then stop and report NO-GO with evidence and the exact failure. Never enter an infinite loop, and never weaken a test or a check to make it pass.

NO-GO conditions: requirement not fully covered; a mandatory validation failed; required validation could not be executed; environment or production safety is uncertain; tenant/data isolation risk remains; hardware-dependent validation is pending; the modified area does not compile.

Report NO-GO as clearly as GO, with: what failed, the exact command, the observed output, and what is needed to unblock it.

## 14. Final Response Contract

After any modification, respond with exactly these sections:

## Resultado

Short summary of what was done.

## Archivos modificados

Real list of files changed (paths).

## Qué cambió

Concrete functional changes, per file when useful.

## Validaciones realizadas

```
<command>
<result>
```

Only commands actually executed.

## Herramientas utilizadas

Only the tools actually used in this task: Context7, Figma, Playwright, Vision, git/GitHub, terminal, subagent, other. Do not claim a tool that was not executed.

## Requisitos verificados

Checklist mapping each original requirement to its completion state.

## Riesgos / pendientes

Only if they exist.

## Estado

GO

or

NO-GO



<!-- The block below is generated. The content above is project-owned and was NOT modified. -->
<!-- AI-GOVERNANCE:BEGIN global-agent-policy v1 -->
<!-- GENERATED FROM AI-GOVERNANCE - DO NOT EDIT THIS SECTION MANUALLY.
     Source: C:\Users\pc\DEV\AI-GOVERNANCE\GLOBAL_AGENT_POLICY.md
     Regenerate: Sync-AgentPolicy.ps1 -Project DaleVentas-POS -Mode Apply -->

**This project follows the AI Agent Governance System.** Full policy: `C:\Users\pc\DEV\AI-GOVERNANCE\GLOBAL_AGENT_POLICY.md`.

**Before editing**

1. Identify the correct repository root, current branch, and worktree.
2. Run `git status --short`; never start on top of unexplained changes.
3. Read the project documentation that applies, and the real code of the area you will touch.
4. Restate the requirement and its acceptance criteria; confirm the smallest change that satisfies it.
5. If the request is an audit: report with evidence, change nothing.

**Parallel work**

- Multiple agents are allowed. **One writer per worktree.** A writing agent uses its own worktree + its own `agent/<task>` branch.
- Read-only agents (audit/review) may run in parallel anywhere.
- If another agent may be writing in the same working tree: **STOP**, do not edit, report `CONCURRENT WRITER RISK`.

**Implementation**

- Minimum change that satisfies the request; no unrelated refactors, no renames for taste.
- Fix the root cause; never hide a symptom with a patch or a forced refresh.
- Do not invent facts, endpoints, models, commands, test results, or documentation. Distinguish **FACT** (verified), **HYPOTHESIS** (plausible, unverified), **RECOMMENDATION** (proposal).
- Preserve compatibility when compatibility is a requirement (existing data, clients, caches).
- Stay inside the task scope; report unrelated findings instead of fixing them silently.

**Security**

- Never print, log, or commit secrets: passwords, tokens, API keys, private keys, credentials, real `.env` values.
- No production access by default. Production is **read-only** unless the current task explicitly authorizes more.
- Destructive operations need explicit authorization in the current task: deploy, migration, seed, mass update/delete, service restart, infrastructure or DNS change, license change.

**Validation (compilation alone is not completion)**

- Review the final diff: no debug leftovers, no temporary TODOs, no out-of-scope edits, no secrets.
- Run static analysis and build for the modified area; run the tests closest to the change.
- Functional verification for behavior changes; visual verification when UI changed.
- Regression checks for high-risk areas (auth, payments, cash, inventory, accounting, permissions, tenants, migrations, sync, release).
- Report failures that you did not cause, with evidence. Never hide a failing check.

**Definition of Done**

- Requirement fully covered, item by item.
- Scope respected; diff reviewed.
- Analysis/build/tests pass on the modified area.
- Validation actually executed (not assumed); blocked validation reported as blocked.
- Risks and pending items documented.

**Final verdict**

- `GO` — everything above is true.
- `GO WITH ISSUES` — usable, with named non-blocking issues.
- `NO-GO` — something mandatory failed or could not be executed; never report it as finished.
<!-- AI-GOVERNANCE:END global-agent-policy -->

