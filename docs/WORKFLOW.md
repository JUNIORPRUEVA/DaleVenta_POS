# FullPOS Cloud Workflow

Last audited: 2026-09-02.

Standard workflow:

```text
REQUEST
-> REQUIREMENTS
-> IMPACT ANALYSIS
-> SCOPE
-> OUT OF SCOPE
-> ACCEPTANCE CRITERIA
-> IMPLEMENTATION
-> TESTING
-> FUNCTIONAL/VISUAL QA
-> REGRESSION
-> GO / NO-GO
-> GIT CHECKPOINT
-> NEXT PHASE
```

Large features must be divided into controlled phases. Do not automatically continue to the next phase after finishing one.

## New Feature

1. Confirm user goal and affected modules.
2. Read product, architecture, environment, design, and testing docs as relevant.
3. Identify tenant, license, inventory, fiscal, and data ownership impact.
4. Define in-scope and out-of-scope behavior.
5. Establish acceptance criteria.
6. Implement minimal, reversible changes.
7. Run static analysis and automated tests.
8. Perform functional QA and visual QA when user-facing.
9. Run focused regression checks.
10. Report GO/NO-GO and unresolved risks.

## Bug Fix

1. Reproduce or reason from failing evidence.
2. Identify root cause and blast radius.
3. Check whether the bug touches protected areas.
4. Make the smallest targeted fix.
5. Add or update regression tests when feasible.
6. Validate the exact bug path and nearby paths.
7. Report what failed before, what changed, and final status.

## UI/UX Change

1. Read `docs/DESIGN_SYSTEM.md`.
2. Inspect nearby screens and shared widgets.
3. Reuse tokens, typography, navigation, dialogs, and component patterns.
4. Avoid unrelated redesigns.
5. Validate mobile and desktop where applicable.
6. Capture or inspect visuals when tooling allows.
7. Report visual verification and any design debt.

## Database Change

1. Confirm target environment.
2. Identify affected Prisma models, services, and tenant boundaries.
3. Determine whether migration is required.
4. For shared/prod environments, require explicit authorization and backup/checkpoint.
5. Never edit applied migrations in shared/prod DBs.
6. Run local migration/test workflow first.
7. Validate data ownership, rollback limits, and service behavior.
8. Report GO/NO-GO before shared/prod execution.

## Release

1. Read `docs/RELEASE.md`.
2. Confirm owner approval and target environment.
3. Verify git status and release scope.
4. Run required tests/builds.
5. Complete QA/UAT and smoke test plan.
6. Verify migration/seed flags and backups.
7. Deploy only if explicitly authorized.
8. Run production verification and report GO/NO-GO.

## Production Incident

1. Stop and identify severity, affected users, and data risk.
2. Do not run destructive commands.
3. Gather read-only logs/status/config at a safe level.
4. Confirm production target before any action.
5. Prefer reversible mitigation.
6. Require explicit authorization for config, database, migration, purge, repair, or deployment actions.
7. Preserve evidence and document timeline.
8. Validate recovery with smoke tests.
9. Report residual risk and follow-up work.

## Git Checkpoint

After a phase is validated:

- Review `git status --short`.
- Review `git diff`.
- Confirm changed files match scope.
- Do not commit unless the user asks for a commit.

## NO-GO Stop Conditions

Stop with NO-GO when:

- Environment or database target cannot be verified.
- Critical validation fails.
- Tenant isolation risk is unresolved.
- Secrets were exposed or may be committed.
- Production migration/seed/destructive action is requested without explicit authorization.
- Required functional or visual validation cannot be performed for a user-facing critical change.
