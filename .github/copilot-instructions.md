# GitHub Copilot Instructions for FullPOS Cloud

FullPOS Cloud already has an established project governance system. Do not create a parallel source of truth in Copilot output.

Before substantial implementation work, read and follow the root `AGENTS.md`. Treat the canonical governance documents under `docs/` as the project source of truth:

- Business rules and product behavior: `docs/PRODUCT_SPEC.md`
- Architecture, data, backend, Prisma, auth, tenant boundaries: `docs/ARCHITECTURE.md`
- Environment, server, database, production safety: `docs/ENVIRONMENTS.md`
- UI/UX, visual system, reusable components: `docs/DESIGN_SYSTEM.md`
- Testing, validation, GO/NO-GO: `docs/TESTING.md`
- Release process and safeguards: `docs/RELEASE.md`
- Development workflow and phased work: `docs/WORKFLOW.md`

Permanent rules:

- Do not invent business rules.
- Preserve multi-tenant isolation and company data boundaries.
- Preserve existing architecture unless the task explicitly requires an approved architectural change.
- Keep changes within the requested scope and avoid unrelated refactors.
- Reuse existing shared UI components, theme tokens, and design-system conventions.
- Never expose secrets, credentials, tokens, private keys, or `.env` values.
- Production is protected by default.
- Do not run production seeds.
- Do not perform destructive production database operations.
- Do not run production migrations without explicit authorization.
- Follow the project's testing requirements; compilation alone is not completion.
- User-facing changes require applicable functional and visual validation.
- Critical validation failures mean NO-GO.
