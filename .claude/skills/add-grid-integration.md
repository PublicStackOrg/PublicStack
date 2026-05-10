---
name: add-grid-integration
description: Use when the user asks to wire a Grid service in a Public Service — "wire payments", "set up identity", "configure document_storage for S3", "add an audit backend", "switch notifications to SES", "use Keycloak for auth". Wraps `publicstack add grid <service>` plus per-service backend choice + adapter notes. Reads SPIKES.md for unresolved decisions.
---

# add-grid-integration

Wire a Grid service into a Public Service: write `grid/<service>.yaml`,
make sure the adapter slot exists, walk through backend-specific
choices. Wraps `publicstack add grid` plus per-service judgment.

## When this fires

User says any of:

- "Wire payments to Stripe"
- "Set up identity with Keycloak"
- "Switch document_storage to S3"
- "Add an audit backend"
- "Use Cognito for auth in this PS"

Do NOT use this skill for the abstract Grid spec — that lives in
`blueprint/grid/<service>/contract.yaml` and is upstream. This skill
is about per-PS *integration*.

## Prerequisites (verify first)

1. CWD is inside a Public Service. Walk up looking for
   `BLUEPRINT_VERSION`. If missing → suggest `new-service`. HALT.

2. `publicstack` on PATH. Otherwise point at `~/publicstack/install.sh`.

3. (Optional but useful.) Have
   `~/publicstack/blueprint/docs/SPIKES.md` open mentally:
   - **#1 (payments execution)** — payments contract is settled
     city-direct; backend choice (Stripe vs local-bank vs city-merchant)
     is per-deployment.
   - **#2 (identity provider)** — no default identity provider has
     been picked at the blueprint level; Keycloak / ZITADEL /
     Authentik are all candidates.

## Primary flow

1. **Identify the Grid service.** Ask via AskUserQuestion which one:
   `identity`, `payments`, `notifications`, `audit`, `document_storage`,
   `accessibility`.

2. **Run the CLI:**

   ```bash
   publicstack add grid <service>
   ```

   The CLI:
   - Creates `grid/<service>.yaml` with the default backend (if missing).
   - Copies the bundled adapter stub into
     `libraries/grid_adapters/grid_adapters/<service>/` (if missing).
   - Idempotent: if both exist, prints `unchanged`.

3. **Walk per-service backend choice** (see below). Edit
   `grid/<service>.yaml` to the chosen backend; tell the user what
   else they need (env vars, secrets, adapter implementation if a
   non-default backend is chosen).

4. **Run the compliance check** to confirm the wiring is right:

   ```bash
   publicstack-compliance run --check grid_integration
   ```

   Surface any findings; if there are breaking `GRD-*` rules, walk the
   user through them (likely missing `get_<service>_adapter` in
   `services/api/api/dependencies.py` — usually the cookiecutter
   handles that, but verify).

## Per-service walks

### identity

Reads SPIKES.md #2. Ask the user which backend:

| Backend | Status | When |
|---|---|---|
| `none` | works (NoAuthAdapter) | dev only — returns a hardcoded test user |
| `keycloak` | adapter NOT yet shipped in v0.4.0 | most common self-hostable |
| `zitadel` | adapter NOT yet shipped | Go-based, lighter than Keycloak |
| `authentik` | adapter NOT yet shipped | Python-based, growing |
| `auth0` | adapter NOT yet shipped | managed |
| `clerk` | adapter NOT yet shipped | managed |
| `cognito` | adapter NOT yet shipped | AWS-managed |

For any non-`none` backend, surface honestly:

> The blueprint Grid contract is solid (token-claims shape in
> `blueprint/grid/identity/contract.yaml`) but the adapter for
> `<backend>` doesn't ship in blueprint v0.4.0. You'd implement
> `libraries/grid_adapters/grid_adapters/identity/<backend>.py` —
> normalize the provider's claims into the contract shape. The
> existing `NoAuthAdapter` is a 30-line reference.

Edit `grid/identity.yaml` to set `backend: <choice>`. Note that
`AUTH_MODE=<choice>` also needs to be set in `.env` / `.env.prod` for
the dependency injection in `services/api/api/dependencies.py` to
route to the right adapter.

### payments

Reads SPIKES.md #1. Ask the user which processor:

| Backend | Status | Notes |
|---|---|---|
| `log_only` | works (LogOnlyPaymentsAdapter) | dev — records intents in memory; never moves money |
| `stripe` | adapter NOT yet shipped | most common managed processor |
| `local_bank` | adapter NOT yet shipped | city has a direct integration with its bank |
| `city_merchant` | adapter NOT yet shipped | city's existing merchant gateway |

Same honest note: backend shipped only for `log_only` in v0.4.0. For
any real processor, the user implements
`libraries/grid_adapters/grid_adapters/payments/<backend>.py`.

PublicStack does NOT move money — the adapter creates an intent and
returns a `redirect_url` to the processor's hosted page. Document
this in the user's choice ("you'll never see card data") to set
expectations.

### audit

Default `postgres` works out of the box (`PostgresAuditAdapter` is
the only real adapter shipped in v0.4.0). Ask: any reason to deviate?

- Future `qldb` (AWS QLDB) — tamper-evidence via the cloud
- Future `s3_object_lock` — write-once-read-many on S3

Both are SPIKES.md #6 follow-ups. Recommend keeping `postgres` unless
the user has a compelling reason.

Action: confirm `grid/audit.yaml: backend: postgres`. Walk the user
through running migration 0002_audit_log:

```bash
docker compose up -d db migrator
# the migrator runs 0002_audit_log automatically as part of `up`
```

### document_storage

Ask: local / S3 / GCS / R2 / MinIO / Azure?

| Backend | Status | Notes |
|---|---|---|
| `local` | works (LocalFilesystemAdapter) | dev / single-VPS |
| `s3` | adapter NOT yet shipped | most common managed; works against S3-compatible APIs (MinIO, R2) |
| `gcs` | not yet shipped |
| `r2` | not yet shipped (Cloudflare R2 is S3-compatible — the `s3` adapter could work) |

For non-`local`, edit `grid/document_storage.yaml`:

```yaml
backend: s3
s3_bucket: <bucket-name>
s3_region: us-east-1
# secrets via .env / .env.prod:
#   DOCUMENT_STORAGE_S3_ACCESS_KEY=...
#   DOCUMENT_STORAGE_S3_SECRET_KEY=...
```

When using the deploy/terraform AWS modules, the bucket name comes from
`terraform output -raw documents_bucket_name`.

### notifications

Ask: which channel + provider?

| Backend | Status | Notes |
|---|---|---|
| `log_only` | works (LogOnlyAdapter) | dev — async send() that logs and pretends success |
| `ses` | NOT yet shipped | email via AWS SES |
| `postmark` | NOT yet shipped | email via Postmark |
| `smtp` | NOT yet shipped | generic SMTP |
| `twilio` | NOT yet shipped | SMS |
| `fcm` | NOT yet shipped | push notifications via FCM |

For non-`log_only`, edit `grid/notifications.yaml`; provider creds via
env.

### accessibility

Only `in_memory` ships in v0.4.0 (the in-memory adapter buffers
A11yViolation records). Not much to choose. Confirm
`grid/accessibility.yaml: backend: in_memory`.

The Phase 5 compliance suite's `accessibility` check is what
populates this — Playwright + axe-core against the Flutter web
builds.

## Branches

### User asks "which identity should I pick?"

Reference SPIKES.md #2 — no default chosen at the blueprint level. The
honest answer:

- **Most self-host-friendly:** Keycloak (battle-tested, heavy Java
  runtime). Authentik is a Python-based alternative gaining traction.
- **Smallest ops surface:** ZITADEL (Go, lighter than Keycloak,
  smaller community).
- **Managed (paid):** Auth0, Clerk, Cognito (the latter if you're on
  AWS — close to the default per project memory).

Recommend based on the user's hosting choice: AWS deploys → Cognito
if you want managed; Keycloak if you want self-host. Other clouds →
Keycloak by default.

### User wants to switch from `none` to a real backend mid-development

The skill should:

1. Update `grid/identity.yaml` and `.env`/`.env.prod` to the new
   `AUTH_MODE`.
2. Implement (or point at the user implementing) the adapter at
   `libraries/grid_adapters/grid_adapters/identity/<backend>.py`.
3. Run `publicstack-compliance run --check grid_integration` to
   confirm.
4. The dev-loop `AUTH_MODE=none` still works locally; production sets
   the real backend via the env file.

### Multiple Grid services to wire at once

The skill runs `publicstack add grid <service>` per service. If the
user asks "wire identity, audit, and document_storage", invoke the
primary flow three times.

## Failure recovery

- **`publicstack add grid` fails because the service name isn't valid.**
  CLI rejects unknown services. Suggest the right name (case matters,
  underscores not hyphens).
- **Compliance check still fails after wiring.** Read the rule_id:
  - `GRD-001` → YAML missing; the CLI should have created it. Bug.
  - `GRD-002` → backend value not in the allowlist; fix the YAML.
  - `GRD-003` → adapter package missing; check that the CLI ran the
    stub-copy step.
  - `GRD-004` → `get_<service>_adapter` not in dependencies.py; the
    cookiecutter ships this for the six default services, so this
    fires only after a hand-edit.

## Worked example

User says: "Wire payments to Stripe."

1. Verify CWD is `Parking/`. `publicstack` ✓.

2. AskUserQuestion service: `payments`.

3. Run `publicstack add grid payments`. Output:

   ```
   info: grid/payments.yaml unchanged; adapter slot already present
   ```

   (Fresh PS already shipped the slot.)

4. Per-service walk: payments. The user picks `stripe`.

5. Surface SPIKES.md #1 note: blueprint v0.4.0 ships the contract +
   `LogOnlyPaymentsAdapter` only. The Stripe adapter doesn't exist
   yet.

6. Walk the user through:

   - Edit `grid/payments.yaml`:

     ```yaml
     backend: stripe
     ```

   - Note that they'll need to implement
     `libraries/grid_adapters/grid_adapters/payments/stripe.py`. Point
     at the contract at `blueprint/grid/payments/contract.yaml` for the
     surface to implement.

   - Add `PAYMENTS_BACKEND=stripe` + `STRIPE_API_KEY=...` to
     `.env.prod`.

7. Run `publicstack-compliance run --check grid_integration`. If the
   adapter file is missing, `GRD-003 adapter-package-missing` fires as
   `warn`. The user knows to fill it in.

End state: `grid/payments.yaml` set to `stripe`, env vars
documented, user has a clear next step (implement the adapter).
