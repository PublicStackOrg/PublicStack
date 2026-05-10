# PublicStack Claude skills

Eight skills that orchestrate the `publicstack` / `publicstack-contracts` /
`publicstack-compliance` CLIs with judgment — asking the right
questions, branching on Public Service state, parsing tool output,
suggesting concrete fixes.

Skills live in this workspace's `.claude/skills/` directory. The
workspace `install.sh` symlinks `.claude/skills/` into every cloned
PublicStackOrg repo, so any skill file added here is immediately
available everywhere.

## Index

| Skill | What it does | Wraps |
|---|---|---|
| [`new-service`](new-service.md) | Scaffold a new Public Service from blueprint | `publicstack new service` |
| [`add-internal-service`](add-internal-service.md) | Add an api / worker to an existing PS | `publicstack add api` |
| [`add-app`](add-app.md) | Add a Flutter app to an existing PS | `publicstack add app` |
| [`add-contract`](add-contract.md) | Expose or consume a Contract | `publicstack add contract` + `publicstack-contracts validate` |
| [`add-grid-integration`](add-grid-integration.md) | Wire a Grid service (identity/payments/audit/...) | `publicstack add grid` |
| [`compliance-fix`](compliance-fix.md) | Parse compliance findings and propose per-rule fixes | `publicstack-compliance run --format json` |
| [`upgrade-blueprint`](upgrade-blueprint.md) | Walk a PS through a blueprint version bump | `blueprint/docs/migration-guides/` |
| [`hosting-runbook`](hosting-runbook.md) | Walk a deploy on the three on-ramps | `deploy/HOSTING.md` |

## Skill file format

Each skill is a single Markdown file with YAML frontmatter:

```markdown
---
name: skill-name
description: One concrete sentence describing when the skill fires. Front-load the trigger phrases — Claude routes user messages to skills based on this field. (e.g., "Use when the user asks to scaffold a new Public Service / create a new PublicStack civic app / start a new PublicStackOrg repo")
---

# Heading

## When this fires

## Prerequisites (read first)
- Verify A
- Verify B

## Primary flow
1. Step
2. Step
3. Step

## Branches
- If X: do Y
- If Z: do W

## Failure recovery
Common errors and the right rescue path.

## Worked example
A concrete user message → expected actions → final state.
```

`description` is the routing handle — Claude reads it on every user
message to decide whether to invoke this skill. Keep it ≤ 280 chars
and front-load trigger phrases.

## Authoring a new skill

1. Pick a clear trigger surface — what user phrases should fire it?
2. Decide on prereqs that the skill verifies before doing anything.
3. Map the primary flow as 3-7 steps. If more, split into multiple
   skills.
4. List branches the user might force (e.g., `--push` flag,
   non-default options).
5. Write a worked example so the user can see what success looks
   like.

## Conventions

### Detect + redirect

Every skill that operates on a Public Service starts by verifying
`BLUEPRINT_VERSION` is present (walking up from CWD). If not, the
skill refuses with a useful message and suggests the right skill
(`new-service`) — it does NOT silently start scaffolding.

### Honest about stubs

Some CLI surfaces are still stubs in blueprint v0.4.0
(`publicstack upgrade`, custom Grid adapter implementations).
Skills that touch those areas say so honestly — they don't pretend
the runner exists. `upgrade-blueprint` walks the migration guide
manually instead.

### One CLI per step

Each step in a primary flow should be one CLI invocation or one file
edit. Multi-step bash one-liners are smells.

### No automated tests

Skill files are Markdown read by Claude at runtime — there's no
"compile" step. Verification is manual: type the trigger phrase
against a real Public Service and confirm the playbook gets followed.
The blueprint repo's own CI doesn't test these.

### Regenerate on CLI bump

Skills assume the CLI surfaces as of blueprint v0.4.0. If a future
blueprint version changes a CLI's flags or behavior, the affected
skill needs an update. Treat skill files as part of the CLI's
documented contract — a CLI change without a skill update is a regression.

## Skill discovery conflicts

If a user's message could trigger multiple skills (e.g., "set up
payments and add a new app"), Claude picks one and asks the user
which to do first. There's no skill chaining — each skill runs
on its own.

## Vocabulary

Skill bodies use the precise PublicStack vocabulary from
[blueprint/docs/GLOSSARY.md](../../blueprint/docs/GLOSSARY.md). When
in doubt, defer there:

- **Public Service** = the whole repo (Parking, Permits, …). One per
  city deployment.
- **internal service** = a microservice inside a PS (services/api/,
  services/worker/).
- **app** = a Flutter app under apps/.
- **Contract** = a versioned schema one PS exposes to others.
- **Grid** = the six shared backbone capabilities (identity,
  payments, notifications, audit, document_storage, accessibility).

## See also

- [`blueprint/docs/PLAN.md`](../../blueprint/docs/PLAN.md) — the
  phased plan for the whole ecosystem.
- [`blueprint/docs/SPIKES.md`](../../blueprint/docs/SPIKES.md) — open
  hard problems some skills consult (identity provider choice,
  payments execution).
- [`blueprint/cli/README.md`](../../blueprint/cli/README.md),
  [`blueprint/contracts/tooling/README.md`](../../blueprint/contracts/tooling/README.md),
  [`blueprint/compliance/README.md`](../../blueprint/compliance/README.md) — the
  three CLIs that the skills delegate to.
