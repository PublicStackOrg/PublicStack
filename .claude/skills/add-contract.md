---
name: add-contract
description: Use when the user asks to expose or consume a PublicStack Contract — "expose a citations contract", "consume permits.identity", "add a contract for X", "publish a schema", "create a v2 of the citations contract". Wraps `publicstack add contract` plus `publicstack-contracts validate` and (for v2+) `publicstack-contracts diff` to catch breaking changes.
---

# add-contract

Add a Contract YAML to a Public Service's `contracts/exposed/` (it
publishes) or `contracts/consumed/` (it depends on someone else's).
Wraps `publicstack add contract` + `publicstack-contracts validate`.

## When this fires

User says any of:

- "Expose a citations contract"
- "Add a v1 contract for permits/identity"
- "Consume permits.identity from this PS"
- "Publish a new schema for audit_entry"
- "Add v2 of the citations contract"

Do NOT use this skill to flesh out an existing contract's schema —
that's normal file editing.

## Prerequisites (verify first)

1. CWD is inside a Public Service. Walk up looking for
   `BLUEPRINT_VERSION`. If missing → suggest `new-service`. HALT.

2. `publicstack` and `publicstack-contracts` on PATH. If either is
   missing → point at `~/publicstack/install.sh`. HALT.

3. (Read context.) `blueprint/contracts/README.md` is the format spec.
   The skill should be ready to quote rules from it when the user
   asks "what's the difference between OpenAPI and JSON Schema?".

## Primary flow

1. **Gather inputs.** Ask via AskUserQuestion:
   - **Contract name** (slug, `[a-z][a-z0-9_-]{1,49}$`). For
     consumed-from-another-PS contracts, use the
     `<producer>.<name>` convention (e.g., `permits.identity`).
   - **Version** (`v1` by default; for adding a new major to an
     existing contract, `v2` / `v3` / …).
   - **Kind**: `--exposes` (this PS owns the contract) or
     `--consumes` (this PS depends on another PS's).

2. **Check existing versions.** Before generating, look for prior
   versions:

   ```bash
   ls contracts/<kind_dir>/<name>.v*.yaml 2>/dev/null
   ```

   - If `vN-1` exists, note it. We'll diff against it after
     generation.
   - If `vN` already exists, the CLI will error; ask the user to pick
     a different version.

3. **Run the CLI:**

   ```bash
   publicstack add contract <name> --version <vN> {--exposes|--consumes}
   ```

   This generates `contracts/<kind_dir>/<name>.<vN>.yaml` as a minimal
   OpenAPI 3.1 stub with PublicStack required metadata
   (`x-publicstack-contract-name`, `x-publicstack-contract-version`).

4. **Validate immediately:**

   ```bash
   publicstack-contracts validate contracts/<kind_dir>/<name>.<vN>.yaml
   ```

   The stub passes by construction; if it doesn't, that's a CLI bug —
   surface and stop.

5. **If a prior version exists, diff:**

   ```bash
   publicstack-contracts diff \
     contracts/<kind_dir>/<name>.v<N-1>.yaml \
     contracts/<kind_dir>/<name>.v<N>.yaml
   ```

   Since v<N> is a fresh stub, this will show as "no breaking changes
   yet" (the stub has empty `paths:` + `components:`). Note this — once
   the user fleshes out v<N>, they should re-run the diff.

6. **Nudge the user about the schema body.** Reference
   `blueprint/contracts/README.md` and point at relevant exemplars:

   - For an OpenAPI-shaped HTTP contract → see
     `blueprint/contracts/examples/citations.v1.yaml`.
   - For a JSON-Schema-shaped data contract → switch the file's top to
     `$schema: https://json-schema.org/draft/2020-12/schema` and
     follow `blueprint/contracts/examples/audit_entry.v1.yaml`.

   The default the CLI emits is OpenAPI 3.1.

7. **Suggest validating again after edits:**

   ```bash
   publicstack-contracts validate contracts/<kind_dir>/<name>.<vN>.yaml
   publicstack-contracts diff contracts/<kind_dir>/<name>.v<N-1>.yaml \
                              contracts/<kind_dir>/<name>.v<N>.yaml   # if v<N-1> exists
   ```

   Reinforce: a `diff` exit code of 1 means breaking. The user
   intentionally breaking back-compat MUST be a v<N> bump, not an
   edit-in-place.

## Branches

### Format is JSON Schema, not OpenAPI

The CLI's contract cookiecutter ships an OpenAPI stub. For JSON
Schema:

1. Run the CLI as normal (generates the OpenAPI stub).
2. Rewrite the file's top: replace `openapi: 3.1.0\ninfo: …\npaths:
   {}\ncomponents:\n  schemas: {}` with:

   ```yaml
   $schema: https://json-schema.org/draft/2020-12/schema
   $id: https://contracts.publicstack.org/<name>.<version>.json
   title: <name>
   description: |
     ...
   x-publicstack-contract-name: <name>
   x-publicstack-contract-version: <version>
   type: object
   properties: { }
   required: [ ]
   ```

3. Re-run `publicstack-contracts validate` to confirm.

The format spec at `blueprint/contracts/README.md` covers detection
rules: tooling checks for `openapi:` vs `$schema:` and routes the
right validator.

### Adding v2 with a breaking change

The user wants to break back-compat. Walk them through:

1. Generate the v2 stub (this skill's primary flow).
2. Edit the v2 to add the breaking change.
3. Run `publicstack-contracts diff v1 v2`. Surface the findings.
4. Confirm: "These look intentional? (DEX-001 / JS001 / etc.)" If yes,
   proceed. If no, suggest reverting the change and bumping nothing.
5. Note: v1 stays in `contracts/exposed/` for a deprecation window;
   the producer ships both for a while.

### Consumed contract — pinning

For `--consumes`, the user is pinning a copy of another PS's exposed
contract. The skill should:

1. Ask which producer PS owns the contract.
2. After CLI generation, replace the stub content with a byte-for-byte
   copy of the producer's `contracts/exposed/<name>.<version>.yaml`.
3. Surface the Phase 5 compliance check: `contract_compat` validates
   that consumed copies byte-match an upstream exposed source (when
   cross-PS pinning ships in Phase 8). For now, the user manages
   alignment manually.

### Contract validates green but the schema is empty

The stub has empty `paths: {}` and `components.schemas: {}`. That's
valid OpenAPI but not useful. Nudge: "The validator is green but the
schema is a stub. Want me to draft a starting schema for X?"

## Failure recovery

- **`publicstack add contract` fails on invalid name/version.**
  Surface the message; ask the user to fix.
- **`publicstack-contracts validate` fails on the freshly-generated
  stub.** That's a CLI bug — file the regression; the stub should
  always pass validate by construction.
- **The diff reports unintended breaking changes after user edits.**
  Walk through the rule findings; help the user understand if each is
  intentional (then bump to vN+1) or accidental (revert).

## Worked example

User says: "Expose a citations contract."

1. Verify CWD is `Parking/`. `publicstack-contracts version` ✓.

2. AskUserQuestion:
   - name: `citations` ✓
   - version: `v1`
   - kind: `--exposes`

3. Check `ls Parking/contracts/exposed/citations.v*.yaml` — none. Fresh v1.

4. Run:

   ```bash
   publicstack add contract citations --version v1 --exposes
   ```

5. CLI generates `contracts/exposed/citations.v1.yaml`.

6. Validate:

   ```bash
   publicstack-contracts validate contracts/exposed/citations.v1.yaml
   # → ok: contracts/exposed/citations.v1.yaml valid (openapi)
   ```

7. Nudge: "The stub is valid OpenAPI 3.1 but `paths:` and
   `components.schemas:` are empty. Reference
   `blueprint/contracts/examples/citations.v1.yaml` for a fleshed-out
   example. Want me to seed the schema with the Citation shape from
   that exemplar?"

8. (If user says yes) Edit `contracts/exposed/citations.v1.yaml` to
   add a `Citation` schema (id, subject_id, status, amount_cents,
   currency, …) and a `GET /citations/{id}` path.

9. Re-validate to confirm.

End state: a valid v1 OpenAPI contract under
`contracts/exposed/citations.v1.yaml` with a working starter schema
the user can iterate on.
