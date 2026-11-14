# FULLTECH TEST acceptance and persistent numbering management

## Scope and release identity

HECHO: after the owner reported deploying both services, read-only container
inspection confirmed the approved images:

- API: ghcr.io/juniorprueva/fullpos-cloud-api@sha256:4e6fb33c823b8f93978da3b3a3e0ef17ff0a8d22e168841986295aab7c4990af
- PWA: ghcr.io/juniorprueva/fullpos-cloud-web@sha256:542cc3d8f94d9c900e11a4928465e712307554efd851e508039f632a736f230b
- Application source3217f0cd; merged PR42 ac729b16 has the identical full tree.
- API healthy, Node22.23.4. Both production fiscal permissions remain false,
  FULLTECH remains SANDBOX with productionEnabled=false, migrations/seed off.

Only the already-authorized FULLTECH TEST setup and bounded E31/E34 acceptance
were written. No credentials were exported or changed. No agent deployment,
restart, migration, production activation or production invoice occurred.

## Observed acceptance

Alejandro's owner-supplied TEST confirmation authorizes1–10000000 with expiry
31/12/2028. The operator reference CONFIRMACION-DOSA-TEST denotes that
confirmation, not an official production authorization number.

E31 was declared in the PWA. The backend rejected starting again at1 and
reported frontier3. The second explicit save retained the full authorization
and used start3. Production numbering was never copied or rewound.

After that first range the completed view hid numbering management. E34 setup
therefore used the existing compiled declaration/range services with the real
PWA operator verified against the persisted owner/admin membership, same company,
SANDBOX environment and confirmed TEST authorization. Its reviewed frontier is2.
Private guarded helpers start no Nest application, decrypt/export no credential,
and never dispatch. Every write requires the specific --phase and --apply.

| Trial | e-NCF | Amount | PWA dispatch | Persisted result |
| --- | --- | --- | --- | --- |
| E31 | E310000000003 | DOP118.00 | one logical send | DGII_ACCEPTED |
| Total E34 | E340000000002 | DOP118.00 | one logical send | DGII_ACCEPTED |

Both local drafts were created with existing services and stable request UUIDs.
They use MANUAL source, a single synthetic taxable item and no commercial sale.
E31 local preparation was enclosed in the existing transaction/numbering lock.
E34 preparation required the newly accepted E31's immutable snapshot and used
the existing credit balance/reservation rules.

Each actual send was clicked once in the deployed PWA. Independent readback
confirmed one SEND_TO_PROVIDER attempt, HTTP200 provider-response receipt,
document fingerprint/receipt hash binding, fiscal snapshot and
DOSA_CONFIRMED_DGII_ACCEPTED transition. The original generic quarantined
observation remains preserved; it is not rewritten to impersonate official
schema evidence. The separate DOSA contract recorder supplies the confirmed
transition for these native SANDBOX dispatches.

E34 references E310000000003, uses total annulment and has one118.00 reservation
transition to APPLIED. No second credit or retry with a new number was created.
Both stamped official testecf QR URLs returned HTTP200 and displayed Aceptado.
No historical document was manually promoted.

## Preservation checks

HECHO: all comparisons below passed against the captured pretrial baseline.

| Protected data | Before and after |
| --- | --- |
| Sales |130 rows; whole-row aggregate fingerprint unchanged |
| Cash sessions |49 rows; whole-row aggregate fingerprint unchanged |
| Cash movements |24 rows; whole-row aggregate fingerprint unchanged |
| Inventory movements |128 rows; whole-row aggregate fingerprint unchanged |
| Historical fiscal documents | five complete row fingerprints unchanged |
| Production authorizations | aggregate fingerprint unchanged |
| Production E31 | start1/next3/end150 unchanged |
| Production E32 | start1/next3/end1000 unchanged |
| Production E34 | start1/next2/end50 unchanged |

Only the authorized TEST ranges/authorizations and two new manual fiscal
documents with their associated audit/evidence/credit records were added.
After allocation, TEST next values are E31=4 and E34=3.

## Documents and printing

HECHO: E31 preview opened in the deployed PWA and the downloaded PDF contains
issuer/receptor identity, e-NCF, issue/expiry dates, item, taxable base100.00,
ITBIS18.00, total118.00, TEST legend, security code, signing date and QR.

Both fresh public print projections were read through the existing deployed
EcfDocumentQueryService using the verified persisted operator. The unchanged
Flutter A4 and thermal renderers generated their representations locally.
Decoded QR matches each stored stamp. A4 includes the E34 original reference,
original date, annulment text and reason;58/80mm outputs retain those fields.
All six representations have one page and matching totals/ITBIS. Rendered A4
E34 and58mm E34 were visually inspected. This does not certify physical paper,
printer transport or drawer behavior; those were intentionally not exercised.

Deployed E34 preview remains unverified: on two attempts the browser returned
to the public website. The cause is not established and must not be represented
as a confirmed PDF generation defect. A user availability question is pending.
Local projection rendering is separate evidence, not a substituted live preview.

## Minimal UI correction

HECHO: EcfCompletedView hides its numbering slot when posReady becomes true.
EcfConfigPage previously showed registered ranges read-only, so adding E34 or
renewing after completing onboarding was inaccessible to the customer.

The correction adds the existing EcfSequenceRangeSection to configuration when
the module is enabled and the user has manageEcfSequences. Its key includes
company, user and environment, disposing the previous form on context changes.
The original read-only overview remains available. No backend contracts, routes,
permissions, provider mapping, counters, dependencies or schema are changed.

Six regressions prove adding E34 after E31 readiness in SANDBOX and PRODUCTION,
read-only/disabled behavior, cancellation of the second write after a company
switch, and accessible390/1280 layouts. The first SANDBOX regression failed
against the unchanged page because the action was absent; it passes with the
minimal correction. Existing declaration/frontier/renewal tests are retained.

## Executed validation

- flutter pub get: PASS. A fresh worktree initially lacked the ignored .env
  asset; only a synthetic loopback QA configuration was created, never copied
  from production or committed.
- flutter analyze --no-pub: PASS, no issues.
- flutter build web --release --no-pub: PASS. The existing optional Wasm dry-run
  warns about incompatible dependencies; the requested JavaScript release builds.
- flutter test --no-pub test/features/ecf/ecf_config_numbering_test.dart:
  six PASS, including visual captures390/1280 inspected.
- flutter test --no-pub test/_live_fiscal_print_probe_test.dart
  test/features/ecf test/core/printing --reporter compact:661 PASS.
  The temporary read-only projection probe is removed from the candidate.
- Private verify-live-acceptance.py over SSH: exact deployed digests, bound
  receipts, production protections and preservation comparisons PASS.
- Private verify-acceptance-pdfs.py --source=projection: both A4 fields,
  decoded stamps and official TEST accepted queries PASS.
- Private verify-acceptance-thermal.py: four58/80mm outputs and decoded stamps
  PASS. One initial comparison needed whitespace normalization for wrapped text.
- git diff --check: PASS.

Publication/CI are not yet complete at this checkpoint. No backend
retest is claimed for this UI-only change; the deployed backend is unchanged.

## Decision

TEST E31/E34 dispatch and confirmed outcomes: PASS. Shared business/production
data preservation: PASS. Small numbering-access correction is local and tested;
web compilation passes; publication and CI remain pending. Live E34 PDF preview remains
pending. Productive emission is NO-GO until those release/acceptance items and
the separate owner-controlled production readiness/activation are completed.
