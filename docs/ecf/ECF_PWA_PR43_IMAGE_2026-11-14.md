# PR43 PWA image — preparation and owner deployment verified

HECHO: owner merged PR43 as38142fce54030bdac611bcbf3f928d9d6be0cbbf.
Its complete tree dd011e11f072ba8056445d27774ab6a1a6eac535 matches validated
source076db49462df5489b8eb6b46f16149d1344f2427. No API build input changed
from3217f0cd; retain the currently deployed API image below.

## Provenance

- PR: https://github.com/JUNIORPRUEVA/DaleVenta_POS/pull/43
- PR controls: https://github.com/JUNIORPRUEVA/DaleVenta_POS/actions/runs/43616522615 —4/4 PASS.
- Post-merge controls: https://github.com/JUNIORPRUEVA/DaleVenta_POS/actions/runs/43617862689 —4/4 PASS.
- PWA build/publication: https://github.com/JUNIORPRUEVA/DaleVenta_POS/actions/runs/43618174331 —PASS.
- Preparation branch: agent/ecf-pr43-pwa-image-20261114. Its workflow checks out
  only frozen076db494, verifies the merged tree and PR gates, publishes web only,
  and verifies the existing assistant publishable-key fingerprint in memory.
  No fiscal credentials, production build, deployment or database operation is
  performed by that workflow. Do not merge this one-off preparation branch.

New PWA, linux/amd64; OCI revision076db494 verified after immutable pull:

```text
ghcr.io/juniorprueva/fullpos-cloud-web@sha256:d56a9c9700f6e4c0273ef0700d9c8dd372ff328305f0f7f42ce8a0bb0bc40387
```

Retained API:

```text
ghcr.io/juniorprueva/fullpos-cloud-api@sha256:4e6fb33c823b8f93978da3b3a3e0ef17ff0a8d22e168841986295aab7c4990af
```

Previous PWA, retained rollback artifact:

```text
ghcr.io/juniorprueva/fullpos-cloud-web@sha256:542cc3d8f94d9c900e11a4928465e712307554efd851e508039f632a736f230b
```

## Exact artifact acceptance

The published image was pulled by digest and started locally without substitute
mounts. The retained API image ran against a newly created empty PostgreSQL
container, explicitly labelled for this task. Prisma5.22 created its schema
with db push --skip-generate only in that new isolated local database; no seed,
shared migration, restored production data or fiscal provider call was used.
API/database had an internal network; only the QA web port bound to127.0.0.1.
All emission flags, automatic migrations and seeds were false in the QA API.

| Actual command/check | Result |
| --- | --- |
| node [private]/validate-workflow.cjs | YAML/source/merged-tree guard, web-only matrix and2 Node scripts PASS |
| docker pull [new PWA digest above] | PASS, exact digest/linux-amd64/revision |
| PUBLIC_WEB_TEST_URL=http://127.0.0.1:54939 node website/tests/public-web-smoke.mjs |9 groups PASS |
| docker exec fullpos-pr43-artifact-qa-web nginx -t | PASS |
| PDF_QA_PROXY_ORIGIN=[same loopback] node [private]/pdf-browser-qa.cjs | E31 document,1280/390, local worker,0 page errors, only loopback PASS |
| same PDF executor with explicit E34 input projection | E34 document,1280/390, local worker,0 page errors, only loopback PASS |
| private prepare-pwa-source-076db494.py over SSH, without --apply | Source plan/readback/protected configuration and unchanged running containers PASS |

The smoke exercised registration/login, duplicate/invalid credentials,
company/owner isolation, one-use handoff with concurrent exchange, onboarding,
public/Flutter routes,16 assets, certification/webhook/uploads routing and
same-origin PDF modules/worker/MIME/cache/404 through the runtime API proxy.
Both PDF renderings were visually inspected. E31 used the actual downloaded
accepted TEST document; E34 used its read-only persisted public projection,
rendered with the unchanged Flutter renderer. This is not a live PWA E34 preview
or a physical printer test. The later live preview result is recorded below.

Initial QA setup guards rejected unsuitable previous test schemas before any
commercial operation. A fresh labelled empty database was used instead. The
first smoke failed health because UAT_LOCAL_ONLY bound the QA API to container
loopback; the documented Docker server-UAT binding corrected that local fixture,
retaining database restrictions and disabled fiscal/startup flags. The full
smoke then passed. No product code was altered to hide a failed check.

Initial Python YAML validation lacked PyYAML and its private install failed.
The existing Playwright YAML parser validated the workflow successfully without
introducing a repository dependency. Neither tooling issue affects the image.

## Authorized source preparation and operator control

The read-only plan sees current API4e6fb33c and PWA542cc3d8 running, automatic
deploy disabled, production fiscal flags false, migrations false and seed off.
After explicit owner authorization, the operation changed only EasyPanel
daleventapos/pwa's image source to d56a9c97 using installed2.37.0
updateAppSourceImage. It did not call deploy. Backend configuration remains
byte-equivalent; PWA protected configuration, registry credentials and running
container IDs retained their fingerprints. An independent persisted readback
confirms the new stored digest and unchanged running images/containers.

The owner authorized: "si correcto prepara la fuente yo depliego" after the
specific new-image proposal. The source is saved and preparation is complete.
The owner retains Implementar for pwa only. No backend redeployment is needed
for this UI-only correction. No restart, migration, seed, credential creation,
fiscal activation or POS database write was performed in this source operation.
Current containers remain API ca6026999fda and PWA276854145ee5, with their prior
4e6fb33c/542cc3d8 images; automatic deploy remains off.

Fresh plan, authorized application and independent readback receipts are
source-authorized-before.json, source-authorized-after.json and
source-final-readback.json in the private evidence directory below. They retain
only image references, fingerprints and safe state metadata, never secrets.

Keep production emission, company production opt-in, migrations and seed off.
Do not repeat the already accepted E31/E34 TEST sends. PWA rollback uses542cc3d8
with the retained API and current database; no database restore or counter rewind.
Private receipts and captures:
C:/Users/pc/.codex/backups/fullpos-pr43-pwa-20261114/.

## Owner deployment and live document acceptance

The owner reported deployment complete. A fresh read-only runtime check confirms
PWA d56a9c97 running and API4e6fb33c still running/healthy on Node22.23.4.
FULLTECH remains SANDBOX/productionEnabled=false. Global production emission,
production confirmed outcomes, RUN_MIGRATIONS and RUN_SEED remain false.

The authenticated PWA at fullposcloud.fulltechrd.com displays the accepted E34
E340000000002 and its E31 E310000000003 reference. Its already-open old UI did
not contain print controls; a normal reload loaded them and retained the seven
draft tickets/current cart. Ver PDF fiscal now renders the E34 successfully.
Compartir > Guardar en descargas saves the actual E340000000002.pdf; nothing
was shared externally or sent to the fiscal provider by these read operations.

| Actual post-deploy check | Result |
| --- | --- |
| verify-postdeploy-pr43.py piped through existing-key SSH to python3 - | Exact web/API digests, API health, protected flags and tenant-scoped receipts PASS |
| FULLTECH PWA > existing accepted E34 > Ver PDF fiscal > Guardar en descargas | Preview and completed download PASS; API GET print HTTP200 |
| python [private]/verify-acceptance-pdfs.py, without projection override | Actual deployed E31/E34 downloads, one page each, required fiscal fields, decoded QR matching stored stamp, official DGII TEST HTTP200/Aceptado PASS |
| Rendered actual E31/E34 download pages inspected visually | Legible issuer/receiver, numbering, taxes/totals, TEST legend, QR/signing; E34 original document/date/reason PASS |
| Post-preview preservation compared with pretrial checkpoint | Business counts/whole-row hashes, five legacy documents, production ranges/counters and authorization fingerprint PASS |

Actual downloaded E31 SHA256:
3e35364035846e21de403b1ebc5ec2d97b51ddfc42a001d8063b430338042a99.
Actual downloaded E34 SHA256:
edcf6935ea71abaa64cb69d7b02d9d6d5025803c1b54dd8d98534df34f365f79.
The actual E34 contains net100.00 + ITBIS18.00 = total118.00, original E31/date,
annulment reason, TEST legend, matching QR/security/signing fields. Both remain
DGII_ACCEPTED with exactly one SEND_TO_PROVIDER attempt each. E34 credit118.00
is APPLIED once; available/reserved/unknown balances are0.00.

Private evidence: postdeploy-final-readonly-receipt.json and
deployed-pwa-pdf-validation.json in the evidence directory above. Initial local
comparison used serialized key order and rejected equivalent range objects;
canonical recursive key comparison confirmed every original value matches.
No application change was made to obtain these results.

Owner deployment, runtime preservation and live accepted TEST PDF validation:
GO. No further deploy is required for this correction. Physical printer output
was not exercised again. Production fiscal emission remains NO-GO pending
reconciliation of official FULLTECH production authorizations (stored production
expiry values remain null) and separately authorized activation. This verification
did not deploy/restart, migrate/seed, change configuration/permissions or issue
another TEST/production document.
