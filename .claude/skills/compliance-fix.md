---
name: compliance-fix
description: Use when the user asks to fix compliance failures — "fix compliance", "why is the compliance check failing", "make this PS PublicStack-compliant", "what's wrong with my data_export check", "address compliance findings". Runs `publicstack-compliance run --format json`, parses findings, proposes targeted fixes per rule_id (DEX/CTR/GRD/SEC/OBS/A11Y).
---

# compliance-fix

Run the PublicStack compliance suite, parse its findings, and walk the
user through targeted fixes per rule. Wraps `publicstack-compliance
run --format json`.

## When this fires

User says any of:

- "Fix the compliance failures"
- "Why is data_export failing"
- "Make this Public Service compliant"
- "Address the compliance findings"
- "What does CSP-missing mean"

Do NOT use this skill on a freshly-generated v0.4.0 PS — those report
green by default. If the user invokes it on a clean PS, the skill
runs the check, surfaces "no breaking findings," and exits.

## Prerequisites (verify first)

1. CWD is inside a Public Service. Walk up looking for
   `BLUEPRINT_VERSION`. If missing → suggest `new-service`. HALT.

2. `publicstack-compliance` on PATH. If missing → point at
   `~/publicstack/install.sh`. HALT.

3. Optional but useful for the `accessibility` check: Chromium browser
   for Playwright. If absent, that check warn-skips. Don't HALT.

## Primary flow

1. **Run the suite with JSON output:**

   ```bash
   publicstack-compliance run --format json
   ```

   Capture stdout. Exit code 0 = no breaking findings; 1 = breaking;
   2 = tool error.

2. **Parse the JSON.** Structure (from
   `compliance/src/publicstack_compliance/report.py`):

   ```json
   {
     "version": "0.1.0",
     "ps_root": "/Users/.../parking",
     "findings": [
       {"check": "data_export", "rule": "DEX-001", "severity": "breaking",
        "location": "...", "message": "...", "suggestion": "..."}
     ],
     "summary": {"breaking": N, "warn": N, "info": N}
   }
   ```

3. **Summarize what's wrong.** Group findings by `check`, then by
   `severity`. Tell the user: "X breaking, Y warn, Z info across N
   checks." If `breaking == 0`, tell them they're green; exit unless
   they explicitly want `--strict` (which upgrades warns to breaking).

4. **For each breaking finding, propose a concrete fix** using the
   per-rule table below. Don't apply edits yet — gather all proposed
   fixes first, then ask the user which to apply.

5. **Ask the user which fixes to apply.** Group them so multi-rule
   fixes (e.g., adding CSP middleware fixes SEC-003 + part of
   OBS-004) get bundled.

6. **Apply chosen fixes** via Edit / Write. For each, document what
   changed in the commit message.

7. **Re-run** `publicstack-compliance run` (without `--format json`,
   the text format is more readable for the final check). Confirm
   green; if still red, iterate.

## Per-rule fix proposals

### Data export (DEX-NNN)

- **`DEX-001 missing-export-route`** → "I'll add a `/export/<entity>`
  route to `services/api/api/routers/v1/export_router.py`. Streams
  newline-delimited JSON. Model on the existing `/export/items`
  endpoint (the template ships it)."
  Suggested edit: append a new `@router.get("/<entity_snake>")`
  function patterned on `export_items`.

- **`DEX-002 missing-export-test`** → "I'll add an integration test to
  `services/api/tests/test_export.py` that hits `/v1/export/<entity>`
  and asserts at least one NDJSON line."

- **`DEX-003 export-not-streaming`** (info, not breaking) → "The
  existing route should return `StreamingResponse`. I'll update its
  return type and body to stream."

- **`DEX-004 model-discovery-failed`** (warn) → "Probably a model file
  parse error. Open `libraries/core/core/db/models.py` and confirm it
  parses (Python syntax)."

### Contract compat (CTR-NNN)

- **`CTR-001 invalid-contract`** → "Open `<location>`; the validator
  says `<message>`. Common causes: missing required metadata
  (`info.x-publicstack-contract-name`/`-version`), invalid OpenAPI/
  JSON Schema structure, ambiguous format detection."

- **`CTR-002 ambiguous-format`** → "The file has both an `openapi:`
  key and a `$schema:` field. Pick one — see
  `blueprint/contracts/README.md` §Two formats."

- **`CTR-003 breaking-diff`** → "Versioned contract has breaking
  changes vs the prior version. Either:
  1. Revert the breaking change (the diff finding names the rule —
     JS001 = removed required field, JS003 = type change, JS004 =
     removed enum value, JS005 = tightened constraint).
  2. Bump the major version (rename file to `v<N+1>`) and let
     v<N> stay for the deprecation window.
  The user picks."

- **`CTR-004 no-contracts`** (info) → "Empty contracts/ dirs are
  fine. No action needed unless this PS should expose at least one
  contract — in which case invoke `add-contract`."

### Grid integration (GRD-NNN)

- **`GRD-001 missing-grid-yaml`** → "Run
  `publicstack add grid <service>` (or invoke `add-grid-integration`).
  Required services (audit, identity) fail breaking; recommended
  (notifications, document_storage, accessibility) fail warn."

- **`GRD-002 invalid-backend`** → "Edit `grid/<service>.yaml`. Valid
  backends listed in the finding's message; if user wants a value not
  in the allowlist, that's a Grid contract violation — they need to
  pick from the supported set."

- **`GRD-003 adapter-package-missing`** → "The adapter package at
  `libraries/grid_adapters/grid_adapters/<service>/__init__.py` is
  missing. Run `publicstack add grid <service>` — the CLI copies a
  bundled stub if absent."

- **`GRD-004 dependency-not-wired`** (warn) → "Add a
  `get_<service>_adapter` function to
  `services/api/api/dependencies.py`. Mirror the pattern of
  `get_identity_adapter` for the rule's service."

- **`GRD-005 payments-detected-without-backend`** (warn) → "The
  models look like they handle money (column named amount/fee/price).
  Either run `publicstack add grid payments`, or set
  `grid/payments.yaml: backend: none` to silence the heuristic."

### Security (SEC-NNN)

- **`SEC-001 dependency-vulnerability`** → "Vulnerability in `<pkg>`
  via pip-audit. Run `poetry update <pkg>` (or pin a patched
  version). If no patch available, suppress with caution after
  reviewing the CVE."

- **`SEC-002 secret-leaked`** → "gitleaks found a secret in
  `<file>:<line>`. Rotate the secret IMMEDIATELY (assume it's
  compromised), then remove from git history with
  `git filter-repo` and force-push. Move the secret to your secret
  manager (SSM, Vault, .env outside git)."

- **`SEC-003 csp-missing`** → "Migration guide
  `blueprint/docs/migration-guides/v0.2_to_v0.3.md` §2 has the canonical
  diff. Add `CSPMiddleware` (BaseHTTPMiddleware that sets
  `Content-Security-Policy: default-src 'self'`) and `app.add_middleware
  (CSPMiddleware)` to `services/api/api/main.py`."

- **`SEC-004 https-redirect-missing`** → "Add `HTTPSRedirectMiddleware`
  to main.py, gated by `settings.environment != 'local'`. Same
  migration guide has the snippet."

- **`SEC-005 hardcoded-credential`** → "Found a hardcoded
  `password`/`secret`/`api_key`/`token` literal in `<file>:<line>`.
  Move to `os.environ` / Pydantic Settings, never commit."

- **`SEC-006 tool-not-installed`** (warn) → "pip-audit or gitleaks
  isn't on PATH. Install (`pip install pip-audit`,
  `brew install gitleaks`) for the full scan. The check warn-skipped
  in this run."

### Observability (OBS-NNN)

- **`OBS-001 metrics-endpoint-missing`** → "Add prometheus-fastapi-
  instrumentator to `services/api/api/main.py`:
  `Instrumentator().instrument(app).expose(app, endpoint='/metrics')`."

- **`OBS-002 otel-tracing-missing`** → "Add `FastAPIInstrumentor().
  instrument_app(app)` after `app = FastAPI(...)`. Add
  `opentelemetry-sdk` + `opentelemetry-instrumentation-fastapi` +
  `opentelemetry-exporter-otlp` to services/api/pyproject.toml. The
  v0.2_to_v0.3 migration guide has the full diff."

- **`OBS-003 structured-logging-missing`** → "Configure root logger
  with `pythonjsonlogger.jsonlogger.JsonFormatter`. Replace
  `logging.basicConfig(...)` with the formatter setup. Same migration
  guide."

- **`OBS-004 missing-log-fields`** (warn) → "The unhandled-exception
  handler's `extra={...}` is missing required fields: <list from
  message>. Add `request_id`, `path`, `trace_id`, `service` keys to
  the dict. `trace_id` comes from
  `opentelemetry.trace.get_current_span().get_span_context().trace_id`."

### Accessibility (A11Y-NNN)

- **`A11Y-001 wcag-violation-critical` / `A11Y-002
  wcag-violation-serious`** → Surface honestly: "axe-core flagged a
  critical/serious WCAG violation in `<app>/<route>`: `<rule_id>:
  <help>`. I can't auto-fix Flutter widgets — open the file at
  `<location>` and fix per the help message. axe-core docs:
  `<help_url>`."

- **`A11Y-003 wcag-violation-moderate` / `A11Y-004
  wcag-violation-minor`** (warn / info) → "Lower-severity violations.
  Worth addressing but not breaking."

- **`A11Y-005 no-web-build`** (info) → "Run `cd apps/<app> && flutter
  build web --release` to make the build scannable."

- **`A11Y-006 tool-not-installed`** (warn) → "Run `playwright install
  chromium` once. The check warn-skipped in this run."

## Branches

### User wants strict mode

If user says "make it green under strict" or "fix all warnings too":

1. Re-run with `--strict`: `publicstack-compliance run --strict
   --format json`. Warnings get upgraded to breaking.
2. Re-walk the same fix table; the warn-tier rules now produce
   actionable findings.

### Some fixes can't be automated

A11y rule failures are the canonical example. Surface honestly: the
skill says what needs changing, but the user makes the edit. After
they do, ask if they want to re-run the check.

### Findings reference Phase 5+ infrastructure that wasn't there before

E.g., if the user is on blueprint v0.2.0 and their compliance suite
runs at v0.3.0 standards, OBS rules will fire because v0.2.0 didn't
have OTel wired. Suggest `upgrade-blueprint` first — that's the right
path, not patch-on-top.

### Iterate until green

After applying chosen fixes:

1. Re-run `publicstack-compliance run`.
2. If still breaking, walk new findings the same way.
3. If green, suggest committing the fix bundle as a single commit.

## Failure recovery

- **`publicstack-compliance run` exits 2 (tool error).** Read the
  stderr verbatim; surface to the user. Common cause: a missing
  external tool (`pip-audit`, `gitleaks`, Playwright Chromium). The
  finding `SEC-006` / `A11Y-006` already covers this.

- **Suggested fix doesn't fully resolve the rule.** Iterate — re-run
  the check after each fix, walk the new findings. Some rules cascade
  (fix OBS-003 also helps OBS-004).

## Worked example

User says: "Fix the compliance failures."

1. Verify CWD is a v0.3.0 PS. `publicstack-compliance` ✓.

2. Run `publicstack-compliance run --format json`. Parse:

   ```json
   {"summary": {"breaking": 3, "warn": 2, "info": 1}, "findings": [
     {"check": "data_export", "rule": "DEX-001", "severity":
      "breaking", "location": "libraries/core/core/db/models.py",
      "message": "Citation has no /export/citation(s) route"},
     {"check": "security", "rule": "SEC-003", "severity": "breaking",
      "location": "services/api/api/main.py",
      "message": "no Content-Security-Policy middleware detected"},
     {"check": "observability", "rule": "OBS-002", "severity":
      "breaking", "location": "services/api/api/main.py",
      "message": "no OpenTelemetry FastAPI instrumentation detected"},
     {"check": "security", "rule": "SEC-006", "severity": "warn",
      "location": "", "message": "gitleaks not on PATH"},
     {"check": "data_export", "rule": "DEX-002", "severity": "warn",
      "location": "libraries/core/core/db/models.py",
      "message": "Citation has no integration test"}
   ]}
   ```

3. Summarize: "3 breaking + 2 warn. Breaking: missing
   `/export/citations` route (DEX-001), no CSP middleware (SEC-003),
   no OpenTelemetry tracing (OBS-002)."

4. Propose fixes:
   - DEX-001 → "I'll add `/export/citations` to
     `services/api/api/routers/v1/export_router.py` patterned on
     export_items."
   - SEC-003 + OBS-002 → "Both are addressed by following the
     v0.2_to_v0.3 migration guide. I can apply the relevant edits to
     `services/api/api/main.py`."

5. AskUserQuestion: which to apply now? User picks all.

6. Apply:
   - Edit `services/api/api/routers/v1/export_router.py`: add the
     export_citations function.
   - Edit `services/api/api/main.py`: add CSPMiddleware +
     FastAPIInstrumentor + JsonFormatter (full v0.2_to_v0.3 diff).

7. Re-run `publicstack-compliance run`. Now reports:
   - 2 warn (SEC-006 missing gitleaks, DEX-002 missing citations
     test), no breaking.

8. Suggest the user install gitleaks and add the export test. Both
   warns, not breaking, so the PS now passes default compliance.

End state: PS reports green on default compliance. Commit the fix
bundle, surface remaining warns as follow-ups.
