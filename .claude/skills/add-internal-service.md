---
name: add-internal-service
description: Use when the user asks to add a backend microservice to an existing Public Service — "add a worker called X", "add a new api", "add an internal service for Y", "scaffold a new service under services/". Wraps `publicstack add api <name>`; handles compose + pyproject wiring.
---

# add-internal-service

Add a new backend service (FastAPI app or RQ worker) under an existing
Public Service's `services/` directory. Wraps `publicstack add api`.

## When this fires

User says any of:

- "Add a new api called scrubber"
- "Add a worker named ingestion"
- "Scaffold a new internal service for X"
- "Add a microservice for searching citations"

Do NOT use this skill if there's no Public Service to add the service to —
that's `new-service`'s job. Do NOT use this skill for frontend Flutter apps
(`add-app`).

## Prerequisites (verify first)

1. CWD is inside a Public Service. Walk up from CWD looking for
   `BLUEPRINT_VERSION`. If missing:
   - Surface: "You're not inside a Public Service (no BLUEPRINT_VERSION
     found above CWD)."
   - Suggest: invoke `new-service` first, or `cd` into an existing PS.
   - HALT.

2. `publicstack` is on PATH. Run `command -v publicstack`. If missing,
   point at `~/publicstack/install.sh`. HALT until installed.

3. (Implicit) PS shape is intact — at minimum `services/`,
   `docker-compose.yml`, and `pyproject.toml` exist at the PS root. The
   CLI verifies these and errors out if missing; surface its message.

## Primary flow

1. **Gather inputs.** Ask via AskUserQuestion:
   - **Service name** (slug, `[a-z][a-z0-9_-]{1,49}$`). Reject reserved
     names: `db`, `redis`, `migrator`, `api`, `worker`. Suggest
     alternatives.
   - **Kind**: `api` (FastAPI HTTP service) or `worker` (background tasks).
     Note: as of blueprint v0.4.0, only `api` is fully scaffolded by the
     CLI. For `worker` see §Branches.

2. **Run the CLI:**

   ```bash
   publicstack add api <slug>
   ```

   The CLI does three things atomically:
   - Generates `services/<slug>/` from the bundled cookiecutter
     (Dockerfile, pyproject.toml, `<slug>/main.py`, project.json, tests).
   - Edits `docker-compose.yml` to add a `<slug>:` service block
     (modeled on the existing `api:` block; preserves comments via
     ruamel.yaml round-trip).
   - Edits root `pyproject.toml` to add a path-dep:
     `[tool.poetry.dependencies.<slug>] path = "services/<slug>"
     develop = true`.

3. **Verify the wiring landed.** Read the diff:

   ```bash
   cat services/<slug>/pyproject.toml
   grep -A 10 "<slug>:" docker-compose.yml
   grep -A 2 "\\[tool.poetry.dependencies.<slug>\\]" pyproject.toml
   ```

4. **Suggest next steps:**

   ```bash
   poetry lock                          # refresh the lockfile
   docker compose build <slug>          # build the new image
   docker compose up -d <slug>          # bring it up alongside existing
   curl http://localhost:8000/health    # smoke-check the existing api
   ```

   Note: the new service exposes `:8000` internally but no host port is
   bound by default (the CLI drops the host-port mapping to avoid
   conflicts; the user adds one in `docker-compose.yml` when needed).

## Branches

### User asks for `worker` kind

As of blueprint v0.4.0, `publicstack add api` only scaffolds the
HTTP/FastAPI shape. For an RQ-style worker, options:

1. **Quick path:** run `publicstack add api <slug>`, then hand-edit
   `services/<slug>/Dockerfile` to replace the `uvicorn …` CMD with
   `python -m <slug>.main` and `services/<slug>/<slug>/main.py` to
   import RQ + define `Worker(['default']).work()`. Model on the
   existing `services/worker/`.
2. **Defer:** wait for a future blueprint version that adds
   `publicstack add worker <name>`. Open an issue in PublicStackOrg/
   blueprint if this is blocking.

Tell the user, recommend (1) with explicit edits.

### User picks a reserved name

The CLI rejects `db`/`redis`/`migrator`/`api`/`worker`. Suggest the
intent-clearer alternative: `audit-api`, `search-api`,
`citations-worker`, etc.

### Service name collides with an existing entry in
`docker-compose.yml`

The CLI's `add_service_block` editor raises `AlreadyApplied`. The CLI
deletes the partially-generated `services/<slug>/` and exits. Surface
the message; ask the user to pick a different name.

## Failure recovery

- **Partial generation on disk.** If `publicstack add api` errored
  midway, `services/<slug>/` may exist with no compose/pyproject wiring.
  Suggest `rm -rf services/<slug>/` before retry.
- **Lockfile drift.** After the CLI succeeds, `poetry lock` may fail if
  the new service's pyproject pins something incompatible. Surface the
  poetry error verbatim; suggest editing `services/<slug>/pyproject.toml`
  to relax the constraint.

## Worked example

User says: "Add a worker called search."

1. Verify CWD is inside a PS (yes — `Parking/`).
2. AskUserQuestion:
   - name: `search` ✓
   - kind: `worker`

3. Note the v0.4.0 limitation (worker kind not yet scaffolded):

   > As of blueprint v0.4.0, `publicstack add api` only generates the
   > FastAPI shape. I'll scaffold the file tree as `api`, then hand-edit
   > Dockerfile + main.py to be RQ-shaped. Proceed?

4. User confirms.

5. Run `publicstack add api search`. CLI generates the tree + wires
   compose + pyproject.

6. Edit `services/search/Dockerfile`:

   ```diff
   - CMD ["uvicorn", "search.main:app", "--host", "0.0.0.0", "--port", "8000"]
   + CMD ["python", "-m", "search.main"]
   ```

7. Edit `services/search/search/main.py` to model on
   `services/worker/worker/main.py`:

   ```python
   from rq import Worker, Queue, Connection
   import redis, os
   ...
   ```

8. Suggest:

   ```bash
   poetry lock
   docker compose build search
   docker compose up -d search
   ```

End state: `services/search/` is a working RQ worker wired into compose
+ pyproject, with a clear note in the commit message that this was a
v0.4.0 hand-edit pending `publicstack add worker`.
