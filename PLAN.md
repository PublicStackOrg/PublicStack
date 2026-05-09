# Plan: PublicStack `blueprint` repo + Claude tooling

## Context

PublicStack is a federated civic-software ecosystem under
`github.com/PublicStackOrg`. To stay coherent without central control, every
**Public Service** (Parking, Permits, 311, etc.) needs to start from a shared
template — `blueprint` — that fixes the project shape, defines how Public
Services talk to each other (Conduits) and to shared infrastructure (the
Grid), and bakes in the org's non-negotiables: AGPL-3.0, accessibility, data
export, observability.

The user's headline goal: **make it as easy as possible for an outside
organization to land on `parking.publicstack.org`, find the blueprint, and
get their own Parking deployment running self-hosted.** That goal pushes
every design choice toward portability and self-host ergonomics.

Stack is locked: **Flutter (frontends) + Python (backend) + Terraform
(infra)**, modeled on `~/personal/palateful` (NX + Poetry monorepo, FastAPI
services, Alembic migrations, Docker-Compose dev loop).

User decisions captured before planning:

- **Cloud:** cloud-agnostic from day one (Terraform modules per provider).
- **Generator:** custom `publicstack` CLI (separate maintained product).
- **Frontends:** multiple Flutter apps per Public Service
  (`apps/resident`, `apps/staff`, `apps/kiosk` …).
- **Vocabulary:** Public Service (external/deployable unit) vs
  internal service / backend service (microservice inside one Public
  Service). No "Block" language anywhere.

## Vocabulary (used throughout)

| Term | Meaning |
|---|---|
| **PublicStack** | The ecosystem / org / standard. |
| **Public Service** | One deployable civic application — its own monorepo, its own AGPL repo. Ex: Parking, Permits, 311. Replaces "Block". |
| **internal service** / **backend service** | A microservice inside one Public Service. Ex: `api`, `worker`, `migrator`, `parser`. |
| **app** / **frontend** | A Flutter app inside one Public Service. Ex: `apps/resident`. |
| **library** | Shared Python or Dart package inside one Public Service. |
| **Conduit** | A versioned contract that one Public Service exposes to others. (Parking exposes `citations.v1`; Permits consumes it.) |
| **Grid** | Shared backbone services (identity, payments, notifications, audit, document storage, accessibility primitives) consumed by every Public Service via adapters. |
| **Compliance suite** | Test pack that verifies a Public Service meets PublicStack standards. |
| **`blueprint`** | This repo. The template + spec. Not a runtime framework. |

Every Public Service is generated from `blueprint`, then evolves
independently. `blueprint` provides scaffolding, contracts, and the
compliance suite — not a library you import at runtime.

---

## 1. `blueprint` repo layout

```
blueprint/
├── README.md                 # the user's already-written README
├── LICENSE                   # AGPL-3.0
├── LICENSING.md              # why AGPL (org-wide doc)
├── CODE_OF_CONDUCT.md
├── SECURITY.md               # disclosure process
├── CONTRIBUTING.md           # RFC process for blueprint changes
├── GOVERNANCE.md             # pointer to PublicStack stewarding entity
├── CHANGELOG.md              # blueprint versioning is real — Public Services
│                             # declare which version they were generated from
├── VERSION                   # current blueprint version (semver)
│
├── CLAUDE.md                 # blueprint-level conventions; copied into each
│                             # generated Public Service as a starter
│
├── template/                 # the cookiecutter / scaffold tree the CLI
│   │                         # materializes when you run `publicstack new …`
│   ├── cookiecutter.json
│   ├── hooks/                # post-gen hooks (rename, init git, etc.)
│   └── {{cookiecutter.public_service_name}}/
│       ├── README.md
│       ├── LICENSE                       # AGPL-3.0, prefilled
│       ├── CLAUDE.md                     # per-Public-Service Claude context
│       ├── BLUEPRINT_VERSION             # records template version
│       ├── package.json                  # Nx workspace
│       ├── nx.json
│       ├── pyproject.toml                # Poetry root for libs+services
│       ├── poetry.lock
│       ├── .env.example                  # all required env vars documented
│       ├── docker-compose.yml            # local dev stack
│       ├── docker-compose.e2e.yml
│       │
│       ├── apps/                         # Flutter apps
│       │   ├── resident/                 # resident-facing Flutter app
│       │   ├── staff/                    # city staff dashboard (Flutter web)
│       │   └── kiosk/                    # in-person terminal (Flutter web)
│       │
│       ├── services/                     # Python backend services
│       │   ├── api/                      # FastAPI HTTP server
│       │   ├── worker/                   # async tasks (RQ default,
│       │   │                             # SQS/Celery adapters available)
│       │   ├── migrator/                 # Alembic
│       │   └── e2e/                      # cross-service integration tests
│       │
│       ├── libraries/                    # shared Python + Dart libs
│       │   ├── core/                     # SQLAlchemy models, config, db
│       │   ├── grid_adapters/            # auth, payments, notifications,
│       │   │                             # audit, storage adapters
│       │   ├── conduits/                 # generated client/server stubs
│       │   ├── ui/                       # shared Flutter design system
│       │   └── test_helper/
│       │
│       ├── conduits/                     # Conduit definitions this Public
│       │   ├── exposed/                  # …Service publishes
│       │   │   └── citations.v1.yaml     # versioned schema (OpenAPI/AsyncAPI)
│       │   └── consumed/                 # …and consumes from others
│       │       └── permits.identity.v1.yaml
│       │
│       ├── grid/                         # Grid integration configs
│       │   ├── identity.yaml             # what auth this PS needs
│       │   ├── payments.yaml
│       │   ├── notifications.yaml
│       │   └── audit.yaml
│       │
│       ├── exports/                      # required: data export endpoints
│       │   ├── README.md                 # documented schemas
│       │   └── …
│       │
│       ├── deploy/                       # deployment manifests
│       │   ├── compose/                  # docker-compose for tiny self-host
│       │   ├── k8s/                      # Helm chart for K8s self-host
│       │   ├── terraform/
│       │   │   ├── modules/              # cloud-agnostic + provider-specific
│       │   │   │   ├── postgres/         # has aws/, gcp/, hetzner/, k8s/
│       │   │   │   ├── object_storage/   # s3 / gcs / r2 / minio
│       │   │   │   ├── queue/            # sqs / redis / rabbitmq
│       │   │   │   ├── compute/          # ecs / cloud-run / nomad / k8s
│       │   │   │   └── cdn/              # cloudfront / cloudflare / nginx
│       │   │   └── environments/
│       │   │       ├── dev/
│       │   │       ├── staging/
│       │   │       └── prod/
│       │   └── HOSTING.md                # "Hosted Ourselves" vs "Host Yourself"
│       │                                 # decision guide
│       │
│       ├── docs/                         # operator + resident-facing docs
│       │   ├── operators/
│       │   ├── residents/
│       │   ├── api/
│       │   └── compliance.md
│       │
│       ├── tests/                        # unit/integration/compliance
│       │   ├── compliance/               # blueprint-compliance tests
│       │   └── …
│       │
│       ├── scripts/                      # dev-loop helpers (dev.sh, etc.)
│       ├── tools/                        # CI grep guards (silent-catch, etc.)
│       ├── seeds/                        # SQL fixtures
│       ├── secrets/                      # gitignored
│       └── .github/workflows/            # CI/CD
│
├── compliance/                           # the suite that runs against any
│   │                                    # generated Public Service
│   ├── README.md
│   ├── pyproject.toml
│   ├── src/publicstack_compliance/
│   │   ├── checks/
│   │   │   ├── grid_integration.py       # auth/payments/etc. wired correctly
│   │   │   ├── conduit_contracts.py      # schemas valid + back-compat rules
│   │   │   ├── accessibility.py          # WCAG 2.2 AA on Flutter web builds
│   │   │   ├── data_export.py            # required endpoints exist + work
│   │   │   ├── security.py               # baseline (deps, secrets, headers)
│   │   │   └── observability.py          # logs/metrics/traces emitted
│   │   └── cli.py                        # `publicstack-compliance run`
│   └── tests/
│
├── cli/                                  # the `publicstack` CLI
│   ├── pyproject.toml
│   ├── src/publicstack/
│   │   ├── __main__.py                   # entrypoint: `publicstack ...`
│   │   ├── commands/
│   │   │   ├── new.py                    # `new service|conduit`
│   │   │   ├── add.py                    # `add api|app|conduit|grid`
│   │   │   ├── lint.py                   # `lint` → compliance suite
│   │   │   ├── upgrade.py                # `upgrade --to <version>` migrations
│   │   │   └── doctor.py                 # `doctor` → env+toolchain checks
│   │   └── codegen/                      # cookiecutter wrappers
│   └── tests/
│
├── conduits/                             # blueprint-defined CORE conduits
│   ├── README.md                         # contract format spec
│   ├── examples/                         # exemplar conduits (audit log,
│   │                                     # identity, etc.)
│   └── tooling/                          # schema validators, codegen
│
├── grid/                                 # blueprint-defined Grid contracts
│   ├── README.md                         # what each Grid service must offer
│   ├── identity/                         # auth contract + Keycloak-default
│   ├── payments/                         # contract + Stripe/Local-bank
│   ├── notifications/                    # contract + email/SMS providers
│   ├── audit/
│   ├── document_storage/
│   └── accessibility/
│
├── docs/
│   ├── HOSTING.md                        # the big one: how a city hosts
│   ├── ARCHITECTURE.md
│   ├── RFCs/                             # RFCs for blueprint changes
│   └── migration-guides/
│
└── tools/                                # blueprint-repo tooling (release,
                                          # version bumps, docs builds)
```

### Why this shape (vs palateful)

- Keeps palateful's NX+Poetry monorepo, services/libraries/, Docker-Compose
  dev loop, Alembic, FastAPI patterns — those are battle-tested.
- Adds `apps/` (plural Flutter) where palateful had a single `app/`.
- Adds `conduits/` and `grid/` — PublicStack-specific contracts not in
  palateful.
- Adds `exports/` as a first-class top-level dir to enforce "easy to leave."
- Adds `deploy/` with cloud-agnostic Terraform module structure
  (per-cloud subdirs under each module). Supersedes palateful's AWS-only
  Terraform layout.
- Drops palateful-specific patterns: `_bmad/`, MutationBus naming
  (kept the *pattern* of typed event bus + service-layer emit, but renamed
  to `EventBus` and made domain-agnostic), recipe/cook domain.

---

## 2. Stack choices

### Backend (Python)

- **Python 3.13**, FastAPI (palateful match), SQLAlchemy 2.0 async, Alembic.
- **Queue:** RQ (Redis-backed) as the **default** — runs anywhere Redis runs,
  zero AWS dependency. Adapters in `libraries/grid_adapters/queue/` for
  Celery+SQS (AWS), Celery+RabbitMQ, Cloud Tasks (GCP). Queue choice is
  a deploy-time decision, not a code decision.
- **DB:** Postgres 16 (with optional pgvector extension if a Public Service
  needs embeddings). Single mandatory dependency.
- **Cache:** Redis (also serves as queue broker).

### Frontends (Flutter)

- **Flutter 3.41+, Dart 3.x.**
- **Riverpod** for state, **GoRouter** for routing — palateful match.
- **Shared design system** in `libraries/ui` (Dart package) — tokens,
  components, accessibility helpers (semantic labels, focus management,
  contrast guards). All apps consume it.
- **EventBus pattern** (palateful's MutationBus, generalized): sealed event
  hierarchy in `libraries/ui/event_bus`, emit on service success branches.

### Monorepo tooling

- **NX 22+ with @nxlv/python plugin** — runs Python tasks across services.
- **Poetry** — Python deps per service + shared libs via `develop = true`.
- **Yarn 1.x** — NX CLI + JS dev tooling.
- `npx nx affected -t test|lint|build` drives CI efficiency.

### Identity / Grid defaults

- **Keycloak** as the Grid's default identity provider — self-hostable,
  AGPL-friendly, supports OIDC, social, MFA. The Grid identity contract is
  the abstraction; Keycloak is the reference implementation.
- **Auth0 / Clerk / Cognito** available as adapter implementations for
  managed-tier deployments.
- All other Grid services follow the same pattern: contract + a default
  self-hostable implementation + adapter slots for managed providers.

---

## 3. Hosting: "Hosted Ourselves" vs "Host Yourself"

Two tiers, one codebase, one deployment artifact set. The blueprint produces
**every artifact for every tier in one CI pass**:

### Tier A: Hosted Ourselves (managed PublicStack)

- We pick a primary cloud (proposal: **AWS**, since palateful's modules
  are most mature there). Possibly multi-region later.
- Terraform `deploy/terraform/environments/prod/` references the AWS module
  variants of every component. Standard ECS Fargate + RDS + S3 + ElastiCache
  + (CloudFront *or* Cloudflare in front, deploy-time toggle).
- Continuous deployment from `main` of each Public Service repo to the
  managed environment.

### Tier B: Host Yourself

- **Three on-ramps**, ordered by friction:
  1. **`docker compose up -d`** — single-VPS deploy. Postgres, Redis, the
     internal services, all Flutter web apps behind nginx. For small cities
     and hobbyists. Documented in `deploy/HOSTING.md` with a copy-pasteable
     runbook.
  2. **Helm chart** in `deploy/k8s/` — for cities with K8s ops.
     Cloud-agnostic.
  3. **Terraform per provider** — `deploy/terraform/environments/prod/` is
     parameterized via `var.cloud = "aws" | "gcp" | "hetzner" | "k8s"`.
     Each module under `deploy/terraform/modules/<component>/<cloud>/`
     exposes the same interface (input/output variables) so swapping
     clouds is a one-flag operation.

### What makes it actually easy to host

- A **single doc** (`deploy/HOSTING.md`) shipped with every Public Service,
  generated from blueprint, with three sections: "I want it on a VPS in 30
  minutes", "I have a K8s cluster", "I have a cloud account and want IaC".
- **Default config that works** — `.env.example` has sane defaults; every
  required value has a comment explaining what it is and where to get it.
- **`publicstack doctor` CLI** — runs from a clone, checks toolchain (docker,
  python, flutter, kubectl, tf), validates `.env`, reports what's missing.
- **No proprietary deps in the default path** — Keycloak, Postgres, Redis,
  MinIO. Cities can swap in managed providers via the Grid adapter layer
  without touching the Public Service code.

---

## 4. CI/CD per Public Service

Reuses palateful's `.github/workflows/ci.yml` shape but generalized:

**On every PR:**
1. `nx affected -t lint`
2. `nx affected -t test` (with Postgres service container)
3. `nx run migrator:check-models` (Alembic drift)
4. `flutter analyze` + `flutter test` per app in `apps/`
5. CI grep guards (silent-catch, accessibility violations, etc.)
6. `publicstack-compliance run --pr` (compliance suite)
7. `terraform fmt + validate + plan` per environment

**On merge to main:**
8. Build Flutter web for `apps/staff` and `apps/kiosk` → Cloudflare Pages
   *or* S3+CloudFront (deploy-time toggle, both supported)
9. Build Docker images for each internal service → push to GHCR (default)
   or ECR (managed tier)
10. `terraform apply` in managed-tier prod environment
11. ECS/K8s rolling update

**Mobile builds** in a separate workflow (release-tag triggered): Flutter
iOS+Android signing, store uploads.

---

## 5. The `publicstack` CLI

Single Python package (`cli/`) installable via pipx. Commands:

```bash
publicstack new service <name>         # generate a new Public Service from blueprint
publicstack add api <name>             # add an internal service to current PS
publicstack add app <name> --kind flutter|web
publicstack add conduit <name> --version v1 [--exposes|--consumes]
publicstack add grid <service>         # wire a Grid integration
publicstack lint                       # run compliance suite locally
publicstack doctor                     # toolchain + env health check
publicstack upgrade --to <version>     # migrate to a newer blueprint version
publicstack version                    # report blueprint + CLI version
```

`publicstack new service` wraps **cookiecutter** under the hood (template
lives in `blueprint/template/`). The CLI handles repo init, GitHub repo
creation under `PublicStackOrg`, AGPL header insertion, and post-gen
sanity checks.

`publicstack upgrade` is the migration story: a Public Service generated
from blueprint v1.2 can move to v1.5 by running this. It applies each
inter-version migration script from `blueprint/docs/migration-guides/`.

---

## 6. Compliance suite

Lives at `blueprint/compliance/`. Installed in each Public Service via
Poetry: `compliance = { path = "../../compliance", develop = true }`
(or pinned to a blueprint version for outside orgs).

`publicstack-compliance run` checks:

- **Grid integration**: required Grid contracts implemented (auth,
  payments if relevant, audit always, etc.)
- **Conduits**: schemas validate against the Conduit format spec; no
  breaking changes vs the previous version of the same Conduit.
- **Accessibility**: Flutter web builds in `apps/` pass axe-core +
  WCAG 2.2 AA checks.
- **Data export**: every entity defined in `libraries/core/models/` has
  a working export endpoint covered by an integration test.
- **Security**: `pip-audit` clean, no secrets in git history (gitleaks),
  CSP headers on Flutter web, HTTPS enforced.
- **Observability**: structured logs with required fields, Prometheus
  metrics endpoint exposed, tracing enabled.

CI runs it. The suite is also runnable standalone, so an outside org
forking a Public Service can verify it stays compliant.

---

## 7. Claude skills (delivered alongside blueprint)

Lives in `/Users/leonidbelyi/publicstack/.claude/skills/` (parent shared
config). All skills auto-propagate to every PublicStackOrg repo via
`install.sh`.

| Skill | Trigger | What it does |
|---|---|---|
| **`new-service`** | "create a new public service", "scaffold a new PublicStack service" | Wraps `publicstack new service`. Asks name, primary domain, which Grid services it needs, which Conduits to expose. Creates GitHub repo. |
| **`add-internal-service`** | "add a backend service", "add an api/worker" | Wraps `publicstack add api/worker/…`. Materializes the new service inside `services/`, wires Nx project.json, adds Dockerfile, registers in docker-compose. |
| **`add-app`** | "add a frontend", "add a Flutter app" | Wraps `publicstack add app`. Generates new Flutter app under `apps/`, wires shared `libraries/ui` import, adds GH workflow build step. |
| **`add-conduit`** | "expose a conduit", "consume a conduit" | Generates the schema, the publisher/consumer stubs, and the back-compat tests. Validates against the Conduit format spec. |
| **`compliance-fix`** | "fix compliance failures", "make this PS PublicStack-compliant" | Runs `publicstack-compliance run`, parses the report, proposes targeted fixes for each failure (missing export endpoint → generates one; missing audit logging → adds it; etc.). |
| **`upgrade-blueprint`** | "upgrade blueprint", "bump blueprint version" | Runs `publicstack upgrade --to <v>`, walks the migration steps interactively, raises questions for ambiguous migrations. |
| **`hosting-runbook`** | "help me self-host", "set up hosting for this PS" | Walks an outside org through `deploy/HOSTING.md` with their context (cloud preference, scale, budget). Edits `.env`, generates `terraform.tfvars`, runs `publicstack doctor`. |
| **`add-grid-integration`** | "wire payments", "add identity provider" | Picks the right Grid adapter (Keycloak/Auth0/Clerk for identity; Stripe/local-bank for payments), wires config, adds the integration test. |

Each skill is a single-file Markdown playbook with frontmatter
(`description`, trigger phrases). They lean on the CLI for the heavy
lifting — skills are orchestration + judgment, not code generators.

---

## 8. Phased implementation

Building all of the above in one shot is too much. Phased order, each
phase shippable on its own:

### Phase 1 — Repo skeleton (1–2 sessions)

- Init `blueprint` repo at `git@github.com:PublicStackOrg/blueprint.git`.
- Top-level docs (README, LICENSE, LICENSING, CODE_OF_CONDUCT, SECURITY,
  CONTRIBUTING, GOVERNANCE), version files, CLAUDE.md.
- Empty directories for `template/`, `compliance/`, `cli/`, `conduits/`,
  `grid/`, `docs/` with placeholder READMEs.
- Wire into `install.sh` so `blueprint` lands alongside the other
  PublicStackOrg repos in the parent.

### Phase 2 — Template tree (3–4 sessions)

- Build `template/{{cookiecutter.public_service_name}}/` with the full
  Nx + Poetry monorepo: `apps/`, `services/`, `libraries/`, etc.
- Populate `services/api/` (FastAPI), `services/worker/` (RQ),
  `services/migrator/` (Alembic).
- Populate `apps/resident/` (Flutter starter), `apps/staff/`, `apps/kiosk/`.
- `libraries/core/`, `libraries/ui/`, `libraries/grid_adapters/`
  (stubs).
- `docker-compose.yml` working end-to-end.
- `.github/workflows/ci.yml` (lint/test/build).
- Smoke test: cookiecutter the template into `Parking/`, get
  `docker compose up && flutter run` green.

### Phase 3 — `publicstack` CLI (2–3 sessions)

- Build `cli/` with `new service`, `doctor`, `version` commands.
- pipx-installable. Wire into `install.sh` to install on each dev
  machine.
- Add `add api`, `add app`, `add conduit` once `new service` is solid.

### Phase 4 — Grid + Conduit contracts (2–3 sessions)

- Define Conduit format spec in `conduits/README.md`.
- Define each Grid service contract in `grid/<service>/`.
- Reference Keycloak adapter for identity in `libraries/grid_adapters/`.
- Reference audit-log adapter (Postgres-backed default).

### Phase 5 — Compliance suite (2–3 sessions)

- Build `compliance/` package.
- Implement checks one at a time: data_export → conduit_contracts →
  grid_integration → security → observability → accessibility.
- Wire into template's CI.

### Phase 6 — Hosting paths (3–4 sessions)

- `deploy/compose/` working VPS recipe.
- `deploy/k8s/` Helm chart.
- `deploy/terraform/modules/` with at minimum AWS + bare-K8s variants
  for: postgres, object_storage, queue, compute, cdn.
- `deploy/HOSTING.md` (the big one) with three on-ramp paths.

### Phase 7 — Claude skills (1–2 sessions)

- Author the eight skills above in
  `/Users/leonidbelyi/publicstack/.claude/skills/`.
- Re-run `install.sh` so they propagate.

### Phase 8 — Apply to Parking (1–2 sessions)

- `publicstack new service parking` (or, if CLI not ready, cookiecutter
  the template directly).
- Push to `git@github.com:PublicStackOrg/Parking.git` (currently empty).
- Set up `parking.publicstack.org` per the public-facing hosting page
  the user described.

---

## 9. Critical files to create / reference

### To create (new)

- `/Users/leonidbelyi/publicstack/blueprint/` (entire tree above)
- `/Users/leonidbelyi/publicstack/.claude/skills/new-service.md`
- `/Users/leonidbelyi/publicstack/.claude/skills/add-internal-service.md`
- `/Users/leonidbelyi/publicstack/.claude/skills/add-app.md`
- `/Users/leonidbelyi/publicstack/.claude/skills/add-conduit.md`
- `/Users/leonidbelyi/publicstack/.claude/skills/compliance-fix.md`
- `/Users/leonidbelyi/publicstack/.claude/skills/upgrade-blueprint.md`
- `/Users/leonidbelyi/publicstack/.claude/skills/hosting-runbook.md`
- `/Users/leonidbelyi/publicstack/.claude/skills/add-grid-integration.md`

### To modify

- `/Users/leonidbelyi/publicstack/install.sh` — list `blueprint` as a known
  org repo (auto-handled by `gh repo list`, no edit needed); install the
  `publicstack` CLI via `pipx install ./blueprint/cli` once Phase 3 lands.
- `/Users/leonidbelyi/publicstack/CLAUDE.md` — add a vocabulary section
  (Public Service / internal service / Conduit / Grid) once Phase 1 ships.

### Reference (read for patterns; do not modify)

- `/Users/leonidbelyi/personal/palateful/CLAUDE.md` — convention spec style
- `/Users/leonidbelyi/personal/palateful/nx.json` and root `package.json` —
  NX + Poetry orchestration
- `/Users/leonidbelyi/personal/palateful/services/api/pyproject.toml` —
  FastAPI service layout
- `/Users/leonidbelyi/personal/palateful/services/api/src/main.py` —
  FastAPI entrypoint pattern (lifespan, middleware, routers)
- `/Users/leonidbelyi/personal/palateful/services/migrator/` — Alembic
  layout
- `/Users/leonidbelyi/personal/palateful/libraries/utils/` — shared lib
  pattern (config, models, db, develop=true)
- `/Users/leonidbelyi/personal/palateful/app/lib/core/state/` — MutationBus
  → generalize to EventBus
- `/Users/leonidbelyi/personal/palateful/docker-compose.yml` — dev-loop
  pattern
- `/Users/leonidbelyi/personal/palateful/.github/workflows/ci.yml` — CI
  pattern to generalize
- `/Users/leonidbelyi/personal/palateful/terraform/` — current AWS
  modules, to be re-shaped per cloud-agnostic layout

---

## 10. Verification

End-to-end check after each phase:

**Phase 1:** `cd blueprint && ls` shows top-level skeleton; `gh repo view
PublicStackOrg/blueprint` shows the README rendered.

**Phase 2:** `cookiecutter ./blueprint/template --no-input
public_service_name=parking` produces a working `parking/` tree;
`cd parking && docker compose up -d && curl :8000/health` returns 200;
`cd apps/resident && flutter run -d chrome` opens a working app shell.

**Phase 3:** `pipx install ./blueprint/cli && publicstack --version`
prints version; `publicstack new service permits` produces the same
working tree as Phase 2's cookiecutter call.

**Phase 4:** `publicstack add conduit citations.v1 --exposes` writes a
schema; `publicstack-compliance run` validates it; intentionally break
back-compat in v2 and confirm the compliance check fails.

**Phase 5:** Inside a generated Public Service, `publicstack-compliance
run` reports green on all six check categories; remove an export
endpoint and confirm the data-export check fails with a useful message.

**Phase 6:** `cd parking && docker compose -f deploy/compose/prod.yml up
-d` on a fresh Ubuntu VPS results in a fully functional deployment
reachable on port 80; `helm install` on a kind cluster works; `terraform
apply -var cloud=aws` in `deploy/terraform/environments/prod/` provisions
ECS+RDS+S3 cleanly; same with `cloud=k8s` provisions K8s manifests
against an existing cluster.

**Phase 7:** From a Claude session in `Parking/`, the user types
"scaffold a new public service called permits" → the `new-service` skill
fires, the user is walked through choices, the new repo is created and
pushed.

**Phase 8:** `parking.publicstack.org` resolves to a Cloudflare Pages
deployment of `apps/resident` (web build); the staff dashboard at
`parking.publicstack.org/staff` works; an outside org clones
`PublicStackOrg/Parking`, follows `deploy/HOSTING.md`, and gets a
working deployment in under an hour.

---

## 11. Open questions / known unknowns to resolve in execution

- **Primary cloud for "Hosted Ourselves":** plan above proposes AWS
  (palateful match). Alternative: Cloudflare for Tier A (matches existing
  publicstack.org), AWS only as a Tier B option. Worth one more decision
  point before Phase 6.
- **Grid as a service vs as a library:** is the Grid an *actual deployed
  shared service* (cities point all their Public Services at one Grid
  instance) or just a *contract layer* each Public Service implements
  locally? Plan above assumes the latter (contract + adapter), which is
  more portable. May need a concrete decision when Phase 4 starts.
- **Block registry:** the user's blueprint README mentions an "official
  Block registry" — out of scope for this plan; deferred until after
  Phase 8.
- **CLA vs DCO:** flagged in the README as "to be finalized." Defer.
- **i18n provider:** plan assumes Flutter `intl` + ARB files. Confirm.
- **Telemetry stack:** OpenTelemetry as the contract; reference impl
  with Prometheus + Grafana + Tempo. Confirm during Phase 5.
