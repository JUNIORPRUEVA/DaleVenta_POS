# GitHub Copilot Instructions for FullPOS Cloud

The repository policy is `AGENTS.md` at the workspace root. Read it before any substantial work and follow it. This file is only a short pointer: do not create a parallel source of truth and do not duplicate project documentation here.

## Before editing

1. Restate the requirement and its acceptance criteria.
2. Read the relevant code, configuration, and canonical docs. `AGENTS.md` §3 routes which one applies (`docs/PRODUCT_SPEC.md`, `docs/ARCHITECTURE.md`, `docs/ENVIRONMENTS.md`, `docs/DESIGN_SYSTEM.md`, `docs/TESTING.md`, `docs/RELEASE.md`, `docs/WORKFLOW.md`).
3. Trace the real flow (UI → state → API → data) before changing any contract.
4. If the request is an audit: report findings with evidence and change nothing.

## Non-negotiable rules

- Do not invent business rules, endpoints, models, commands, test results, or documentation. Label claims: HECHO (verified), HIPÓTESIS (plausible, unverified), RECOMENDACIÓN (proposal).
- Preserve multi-tenant isolation, company data boundaries, licensing behavior, and the existing architecture.
- Keep changes inside the requested scope. No unrelated refactors, no opportunistic cleanups, no silent phase advancement.
- Reuse the existing design system, shared widgets, and theme tokens (`docs/DESIGN_SYSTEM.md`).
- Never print, log, or commit secrets, tokens, credentials, private keys, or `.env` values.
- Production is read-only by default: no deploy, no migration, no seed, no data modification, no destructive operation without explicit authorization in the current task.
- Use tools when they raise accuracy: Context7 for versioned framework/library questions, Figma as the visual source of truth for UI work, Playwright for web/PWA evidence, Vision only when the image can actually be rendered. Never claim a tool was used if it was not executed.

## Validation and completion

Use the real commands of `AGENTS.md` §11 (`flutter pub get` / `flutter analyze` / `flutter test` from `apps/fulltech_app`; `npm run api:build`, `npm --workspace apps/api test`, `npx prisma validate` for the API). Do not invent alternative commands.

Compilation alone is not completion. Before reporting "done", "listo", "fixed", or "completed":

- Re-read the original request and check each requirement item by item.
- Review the final diff: no debug code, no temporary `TODO`s, no hardcoded values, no secrets, no out-of-scope edits.
- Run static analysis, the relevant automated tests, and functional/visual validation when UI changed.
- If a failure was caused by your change, fix it before reporting (max 3 correction attempts on the same failure).
- If a mandatory check fails or cannot be executed, the status is NO-GO — never present the task as finished.

Report using the format in `AGENTS.md` §14: Resultado / Archivos modificados / Qué cambió / Validaciones realizadas / Herramientas utilizadas / Requisitos verificados / Riesgos y pendientes / Estado (GO or NO-GO).


<!-- The block below is generated. The content above is project-owned and was NOT modified. -->
<!-- AI-GOVERNANCE:BEGIN global-agent-policy v1 -->
<!-- GENERATED FROM AI-GOVERNANCE - DO NOT EDIT THIS SECTION MANUALLY.
     Source: C:\Users\pc\DEV\AI-GOVERNANCE\GLOBAL_AGENT_POLICY.md
     Regenerate: Sync-AgentPolicy.ps1 -Project DaleVentas-POS -Mode Apply -->

Project policy: `AGENTS.md` in this repository. Company-wide policy: `C:\Users\pc\DEV\AI-GOVERNANCE\GLOBAL_AGENT_POLICY.md`.

- Read `AGENTS.md` before substantial work. Audit before editing; report with evidence; never invent facts, endpoints, commands, or results.
- Multiple agents allowed; **one writer per worktree**. A writing agent needs its own worktree and its own `agent/<task>` branch.
- Pre-flight before writing: `git rev-parse --show-toplevel`, `git branch --show-current`, `git status --short`, `git worktree list`. Suspicious state → **stop**, change nothing, report `CONCURRENT WRITER RISK`.
- Minimal change, root cause, requested scope only. No unrelated refactors, no debug leftovers, no temporary TODOs.
- Never print, log, commit, or paste secrets, tokens, credentials, private keys, or `.env` values.
- Production is **read-only** by default: no deploy, migration, seed, or data write without explicit authorization in the current task.
- Compilation is not completion: run the project's real analysis/build/test commands, functional validation, and visual validation when UI changed.
- End every task with `GO`, `GO WITH ISSUES`, or `NO-GO`. A failed or unexecuted mandatory check means `NO-GO`.
<!-- AI-GOVERNANCE:END global-agent-policy -->

