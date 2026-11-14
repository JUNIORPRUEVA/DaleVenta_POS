# PR43 PWA image — verified preparation

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

Current/rollback PWA:

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
or a physical printer test; that live preview remains pending after owner deploy.

Initial QA setup guards rejected unsuitable previous test schemas before any
commercial operation. A fresh labelled empty database was used instead. The
first smoke failed health because UAT_LOCAL_ONLY bound the QA API to container
loopback; the documented Docker server-UAT binding corrected that local fixture,
retaining database restrictions and disabled fiscal/startup flags. The full
smoke then passed. No product code was altered to hide a failed check.

Initial Python YAML validation lacked PyYAML and its private install failed.
The existing Playwright YAML parser validated the workflow successfully without
introducing a repository dependency. Neither tooling issue affects the image.

## Production source proposal and operator control

The read-only plan sees current API4e6fb33c and PWA542cc3d8 running, automatic
deploy disabled, production fiscal flags false, migrations false and seed off.
The proposed operation changes only EasyPanel daleventapos/pwa's image source
to d56a9c97 using installed2.37.0 updateAppSourceImage. It does not call deploy.
Backend configuration must remain byte-equivalent; PWA protected configuration,
registry credentials and running container IDs must retain their fingerprints.

At this checkpoint the new source has NOT been saved. The earlier explicit
source authorization named PR42 images. Present this exact verified PWA proposal
for authorization before changing productive configuration. The owner retains
Implementar. No backend redeployment is needed for this UI-only correction.

Keep production emission, company production opt-in, migrations and seed off.
Do not repeat the already accepted E31/E34 TEST sends. PWA rollback uses542cc3d8
with the retained API and current database; no database restore or counter rewind.
Private receipts and captures:
C:/Users/pc/.codex/backups/fullpos-pr43-pwa-20261114/.

Artifact/source proposal: GO. Source save requires the specific authorization;
owner deployment and live E34 preview remain pending. Productive fiscal emission
is not authorized by this artifact preparation.
