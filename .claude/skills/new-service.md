---
name: new-service
description: Use when the user asks to scaffold a new Public Service from blueprint — "create a new public service", "scaffold permits / parking / 311", "start a new PublicStackOrg repo", "make a new civic app". Wraps `publicstack new service`, asks about Grid + Contracts, optionally creates the GitHub repo via `--push`.
---

# new-service

Scaffold a new PublicStack Public Service. Wraps the `publicstack new service`
CLI with judgment about naming, Grid wiring, initial Contracts, and the
optional GitHub repo creation.

## When this fires

User says any of:

- "Create a new Public Service called X"
- "Scaffold permits / 311 / licensing"
- "Start a new PublicStackOrg repo"
- "Make a new civic app for parking citations"

Do NOT use this skill for adding internal services / apps / contracts to an
existing PS — those have their own skills (`add-internal-service`,
`add-app`, `add-contract`).

## Prerequisites (verify first)

1. `publicstack` is on PATH. Run `shutil.which("publicstack")` or
   `command -v publicstack`. If missing:
   - Surface the error: "`publicstack` CLI not installed."
   - Suggest: "Run `~/publicstack/install.sh` from the workspace root, or
     `pipx install ~/publicstack/blueprint/cli`."
   - HALT until installed.

2. CWD is NOT inside an existing Public Service. Walk up from the user's
   CWD looking for `BLUEPRINT_VERSION`. If found:
   - Note to the user: "You're already inside `<existing-ps>`. Generating
     a new PS will create a sibling directory."
   - Confirm intent before proceeding.

3. If the user wants `--push`: `gh` on PATH AND `gh auth status` succeeds.
   If not, prompt the user to `gh auth login` first. HALT until authenticated.

## Primary flow

1. **Gather inputs.** Ask the user (use AskUserQuestion for multi-choice):
   - **Service name** (slug, lowercase, `[a-z][a-z0-9_-]{1,49}$`).
     Validate; if invalid, suggest a corrected slug.
   - **Display name** (optional; defaults to the slug capitalized).
   - **Description** (one line; goes into README + cookiecutter context).
   - **Push to PublicStackOrg?** (yes/no). Default no — local-only.
   - **Output directory** (defaults to the workspace root —
     `/Users/leonidbelyi/publicstack/` — so the new PS sits as a sibling
     of `blueprint/` and existing PSes).

2. **Run the CLI:**

   ```bash
   publicstack new service <slug> \
     [--description "<one-liner>"] \
     [--output-dir <dir>] \
     [--push]
   ```

   Surface stdout/stderr. The CLI handles cookiecutter rendering + git init
   + (optionally) `gh repo create` + push.

3. **Review the generated tree.** Run `ls <new-ps>/` and read its
   `README.md`. Confirm:
   - `BLUEPRINT_VERSION` is the current blueprint version.
   - `apps/{resident,staff,kiosk}/` exist.
   - `services/{api,worker,migrator}/` exist.
   - `grid/<6 services>.yaml` exist (Phase 4 ships all six by default).

4. **Ask about Grid wiring.** The default `grid/` YAMLs are wired with
   safe development backends (identity=none, audit=postgres, others=
   log_only / local / in_memory). Ask: "Want to wire any Grid service
   to a real backend now (Keycloak for identity, S3 for document_storage,
   Stripe for payments, …)?"
   - If yes: invoke `add-grid-integration` for each chosen service.
   - If no: tell the user they can run `publicstack add grid <service>`
     later, or invoke `add-grid-integration` from any future Claude
     session.

5. **Ask about initial Contracts.** Most PSes don't expose any at
   generation time. If the user wants to draft one upfront:
   - Invoke `add-contract` for each — pass `name`, `version=v1`,
     `--exposes`.

6. **Print next steps:**

   ```
   cd <new-ps>
   npm install && poetry install
   docker compose up -d db redis migrator
   ./scripts/dev.sh
   ```

   Plus a pointer to `deploy/HOSTING.md` for hosting choices and
   `publicstack-compliance run` for the compliance baseline.

## Branches

### User wants to push but `gh` isn't authenticated

Prompt:

> `gh auth status` reports not authenticated. Run `gh auth login` (or
> `gh auth login --hostname github.com -p ssh`) and re-run when ready.

HALT until the user confirms `gh auth status` is OK; do NOT retry the
publicstack call automatically.

### User picks a name that conflicts with an existing PublicStackOrg repo

If `--push` and `gh repo view PublicStackOrg/<slug>` succeeds (returns
exit 0), the CLI refuses. Surface the message and ask the user to pick a
different name.

### User asks "what's a Grid service?"

Defer to the glossary:

> See `blueprint/docs/GLOSSARY.md` — the Grid is PublicStack's set of
> contracts for shared backbone capabilities. Six services: identity,
> payments, notifications, audit, document_storage, accessibility. Each
> Public Service implements them locally via adapters; nothing routes
> through a central server.

### User asks for hyphens in the name (e.g., `parking-citations`)

The CLI's slug regex allows hyphens, but the `python_package` derivation
converts hyphens to underscores. That causes a mismatch with the GHCR
image-tag convention (which lowercases + converts hyphens → underscores
the same way). Functional but confusing. Suggest underscores instead
(`parking_citations`) if they have flexibility.

## Failure recovery

- **Target directory already exists.** The CLI fails fast. Ask the user
  to remove or rename the target, or pick a different slug.
- **`gh repo create` 422 (name already taken on GitHub).** Suggest a
  different name; do NOT retry with `--force` (that would orphan the
  local-only state).
- **Cookiecutter post-gen hook fails.** The tree is partially generated.
  Tell the user; suggest `rm -rf <slug>` and retry.

## Worked example

User says: "Create a new public service called permits, pushed to GitHub."

1. AskUserQuestion confirms:
   - name: `permits` (valid slug)
   - display: `Permits`
   - description: "Building and contractor permits for cities"
   - push: yes
   - output-dir: `/Users/leonidbelyi/publicstack/`

2. Verify prereqs: `publicstack` on PATH ✓, `gh auth status` ✓.

3. Run:

   ```bash
   publicstack new service permits \
     --description "Building and contractor permits for cities" \
     --output-dir /Users/leonidbelyi/publicstack/ \
     --push
   ```

4. CLI generates `/Users/leonidbelyi/publicstack/permits/`, creates
   `PublicStackOrg/Permits`, pushes initial commit.

5. AskUserQuestion: "Want to wire any Grid service to a real backend now?"
   User says no.

6. AskUserQuestion: "Any initial Contracts to expose?" User says yes,
   `attestations.v1`. Invoke `add-contract` with
   `name=attestations, version=v1, kind=exposed`.

7. Print next steps. Mention `deploy/HOSTING.md` + `publicstack-compliance
   run` for the baseline.

End state: `/Users/leonidbelyi/publicstack/permits/` is a working PS,
pushed to `PublicStackOrg/Permits`, with one exposed Contract draft.
