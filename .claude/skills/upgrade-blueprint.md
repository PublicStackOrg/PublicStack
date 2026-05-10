---
name: upgrade-blueprint
description: Use when the user asks to upgrade a Public Service from one blueprint version to another — "upgrade to v0.4.0", "bump blueprint", "how do I get the new compliance suite", "migrate from 0.1 to 0.3". Walks the per-version migration guides one section at a time, since `publicstack upgrade --to <v>` is still a stub.
---

# upgrade-blueprint

Walk a Public Service through a blueprint version bump by applying the
per-version migration guide(s) interactively. The `publicstack upgrade
--to <v>` CLI is still a stub in blueprint v0.4.0; this skill is the
manual fallback that walks the migration guides.

## When this fires

User says any of:

- "Upgrade to v0.4.0"
- "Bump blueprint"
- "How do I get the new compliance suite"
- "Migrate from 0.2 to 0.3"
- "Catch up to the latest blueprint"

Do NOT use this skill for forking a PS at a different version —
that's a `new-service` flow at the desired blueprint version.

## Prerequisites (verify first)

1. CWD is inside a Public Service. Walk up looking for
   `BLUEPRINT_VERSION`. If missing → suggest `new-service`. HALT.

2. Read `BLUEPRINT_VERSION` — that's the source version.

3. Read `~/publicstack/blueprint/VERSION` — that's the latest target
   available locally. The user may want an earlier target (e.g.,
   v0.3.0 specifically) — ask.

4. Confirm migration guide(s) exist for the chain. Migration guides
   live at:

   ```
   ~/publicstack/blueprint/docs/migration-guides/
     v0.1_to_v0.2.md
     v0.2_to_v0.3.md
     v0.3_to_v0.4.md
   ```

   If a guide is missing for any link in the chain, surface honestly:
   "I can't auto-walk a v<X>→v<Y> step because the migration guide
   doesn't exist. Worth writing it before continuing."

## Primary flow

1. **Determine the chain.** Source from `BLUEPRINT_VERSION`, target
   from user ask (or latest if unspecified). Sequence the chain:
   v0.1 → v0.2 → v0.3 → v0.4 (in order). Skipping versions is not
   supported by the guides; walk each link.

2. **Tell the user the plan:**

   > Current: v<source>. Target: v<target>. Chain: v0.1→v0.2,
   > v0.2→v0.3, v0.3→v0.4. I'll walk each one and apply edits per
   > the migration guide. Between major links, I'll run the
   > compliance suite to catch regressions early.

3. **For each link in the chain, walk
   `blueprint/docs/migration-guides/v<old>_to_v<new>.md`:**

   a. Read the full guide.

   b. For each numbered section, surface the changes the guide
      prescribes (diff hunks, new files, env vars, etc.).

   c. Apply the edits via Edit/Write — one section at a time, not
      bulk. Stop and confirm with the user after each section that
      meaningfully changes the PS shape (rename, new dependency,
      breaking middleware addition).

   d. Note any "user-decision" sections — the v0.2_to_v0.3 guide for
      example asks the user to add OpenTelemetry deps; the user might
      already have them. Confirm before re-adding.

4. **Between major links, run the compliance suite** to catch issues:

   ```bash
   publicstack-compliance run
   ```

   - If green: proceed to the next link.
   - If red: walk the findings via `compliance-fix` (or invoke it as
     a skill). Don't proceed to the next link with broken state.

5. **Update `BLUEPRINT_VERSION`** at the end of the chain to the
   target value.

6. **Run final checks:**

   ```bash
   publicstack-compliance run --strict       # confirm zero findings
   docker compose up -d db redis migrator    # confirm migrator runs cleanly
   poetry install && poetry run pytest       # confirm tests pass
   ```

7. **Suggest committing as one logical change.** A version bump is a
   self-contained PR; commit the per-link edits as separate commits
   (one per migration guide), then push as one PR for review.

## Per-link summary

### v0.1 → v0.2 (Phase 4: Grid + Contracts)

Key changes:
- Rename `storage/` → `document_storage/` (adapter dir + dependencies.py
  function `get_storage_adapter` → `get_document_storage_adapter`)
- Drop `STORAGE_*` env vars; add `DOCUMENT_STORAGE_*`
- Add Protocol stubs + minimal defaults for `payments/`, `audit/`,
  `accessibility/`
- Apply Alembic migration `0002_audit_log`
- Wire all six Grid adapters via DI in `services/api/api/dependencies.py`
- `NotificationsAdapter` shape change: async, channel/template_id

Watch out for: the `NotificationsAdapter` change is breaking — any
hand-written code calling `adapter.send(to=..., subject=...)` needs
the new shape (`await adapter.send(channel=..., to=...,
template_id=...)`)

### v0.2 → v0.3 (Phase 5: Compliance suite + baseline)

Key changes:
- Add `opentelemetry-sdk`, `opentelemetry-instrumentation-fastapi`,
  `opentelemetry-exporter-otlp`, `python-json-logger` to
  `services/api/pyproject.toml`
- Add CSPMiddleware + HTTPSRedirectMiddleware to `main.py` (gated on
  `environment != "local"`)
- Replace `logging.basicConfig` with `pythonjsonlogger.JsonFormatter`
- Wire `FastAPIInstrumentor().instrument_app(app)`
- Add `environment: Literal["local","staging","prod"]` to APISettings
- Add `/export/items` endpoint + integration test
- Add `OTEL_SDK_DISABLED=true` to `services/api/tests/conftest.py`
- Rename `get_storage_adapter` → `get_document_storage_adapter` (if
  not done in v0.2_to_v0.3 already)

Watch out for: this is the biggest delta. The compliance suite is
strict about every one of these — running `publicstack-compliance run
--strict` after applying should report green.

### v0.3 → v0.4 (Phase 6: Hosting paths)

Key changes:
- Copy `deploy/` tree from a fresh v0.4.0 PS (the simplest path)
- Allowlist `.env.prod.example` in `.gitignore`
- Add the GHCR `docker-push` job to `.github/workflows/ci.yml`

This link is mostly additive — `deploy/` was empty placeholders
before. No application code changes. Watch out for: the user might
have customized `deploy/README.md` (a stub before v0.4.0); the new
version is fuller.

## Branches

### User wants to skip a step in a migration guide

Each step in the guides is there for a reason — usually a compliance
check enforces it. Tell the user which check will fire if they skip:

> Skipping section 4 (NotificationsAdapter shape change) means
> GRD-004 will fire — `get_notifications_adapter` won't match the
> Phase 4 contract. Compliance suite will catch this. Skip anyway?

If they confirm, document the skip in the commit message so it's
visible to future maintainers.

### Migration guide missing for a link

E.g., user wants v0.0.5 → v0.1, but no guide exists. Surface
honestly:

> No migration guide at
> `blueprint/docs/migration-guides/v0.0.5_to_v0.1.md`. Either:
> 1. Write it now (with the diffs from blueprint's history) before
>    walking.
> 2. Skip directly to a generate-from-scratch + manual port (effectively
>    `new-service` at the target version, copying business logic
>    forward).
> 3. Defer the upgrade until the guide exists.
> The user picks.

### Chain has multiple links

E.g., user is at v0.1.0 and wants v0.4.0. Walk all three guides in
order. Run the compliance suite between major links. Commit per
link.

### Mid-chain failure

If `publicstack-compliance run` fires breaking findings mid-chain,
STOP. The user is partway through. Invoke `compliance-fix` to address
the findings, then resume.

### CLI's `publicstack upgrade --to` runner ships

When it does (future blueprint version), this skill should detect
that and prefer the CLI:

```bash
publicstack upgrade --to <target>
```

For now (v0.4.0), the CLI is a stub; the skill does the manual walk.

## Failure recovery

- **Edit conflicts.** If the user has hand-modified a file the guide
  wants to edit, surface the conflict. Don't blindly overwrite —
  show the diff and ask the user how to resolve.

- **Lock file drift after deps added.** Run `poetry lock` after each
  link. If it fails (incompatible version constraints), surface the
  Poetry error verbatim; ask the user to relax a pin if needed.

- **Migration fails to run.** If `docker compose up -d migrator`
  errors during the v0.1_to_v0.2 step (adding `0002_audit_log`), the
  schema is partly applied. Suggest:

  ```bash
  docker compose down -v   # drop the database
  docker compose up -d db redis migrator   # rerun fresh
  ```

  Only safe in dev / staging; production needs careful migration
  rollback.

## Worked example

User says: "Upgrade Parking to v0.4.0. We're on v0.2.0 today."

1. Verify CWD is `Parking/`. `BLUEPRINT_VERSION` says `0.2.0`.

2. Target: v0.4.0. Chain: v0.2.0 → v0.3.0 → v0.4.0.

3. Confirm both guides exist (v0.2_to_v0.3.md, v0.3_to_v0.4.md).

4. Walk v0.2 → v0.3:

   - Read `blueprint/docs/migration-guides/v0.2_to_v0.3.md`.
   - Edit `services/api/pyproject.toml`: add the four new deps.
   - Edit `services/api/api/main.py`: add CSPMiddleware,
     HTTPSRedirectMiddleware, JsonFormatter, FastAPIInstrumentor,
     update exception handler `extra=` to include trace_id +
     service.
   - Edit `services/api/api/config.py`: add `environment` field.
   - Create `services/api/api/routers/v1/export_router.py` + mount it
     in `v1_router.py`.
   - Create `services/api/tests/test_export.py`.
   - Create `services/api/tests/conftest.py` with
     `OTEL_SDK_DISABLED=true`.
   - Rename `get_storage_adapter` → `get_document_storage_adapter`.
   - Update `BLUEPRINT_VERSION` to `0.3.0`.
   - Run `poetry lock && pytest && publicstack-compliance run`.
     All green.
   - Commit "Migrate v0.2 → v0.3: compliance baseline."

5. Walk v0.3 → v0.4:

   - Read `blueprint/docs/migration-guides/v0.3_to_v0.4.md`.
   - Copy the `deploy/` tree from a freshly-generated v0.4.0 PS.
   - Allowlist `.env.prod.example` in `.gitignore`.
   - Append the `docker-push` GHCR job to `.github/workflows/ci.yml`.
   - Update `BLUEPRINT_VERSION` to `0.4.0`.
   - Run final compliance check — `publicstack-compliance run
     --strict` reports green.
   - Commit "Migrate v0.3 → v0.4: deploy/ landing."

6. Push.

End state: Parking is on v0.4.0, all compliance checks pass, two
clear migration commits in the history.
