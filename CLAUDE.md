# PublicStack — org context

This file lives one level above each PublicStack repo. Claude Code walks parent
directories looking for `CLAUDE.md`, so anything here is inherited by every
repo cloned under this directory. Per-repo `CLAUDE.md` files override or extend
this file.

## What PublicStack is

Open-source civic software, built for the public good. GitHub org:
[`PublicStackOrg`](https://github.com/PublicStackOrg). Default license is
**AGPL-3.0** for every repo unless explicitly stated otherwise.

## Default tech stack

Inferred from current repos — adjust per-repo as needed:

- **Runtime:** Node 20+
- **Frontend:** Vite + React 19 + TypeScript
- **Hosting / edge:** Cloudflare Pages and Cloudflare Workers (via Wrangler)
- **Lint:** ESLint (flat config, `eslint.config.js`)
- **Package manager:** npm (presence of `package-lock.json`)

## Conventions

- Source of truth for org-wide defaults is this file. Per-repo nuances go in
  the repo's own `CLAUDE.md`.
- Prefer editing existing files. Don't introduce abstractions until there are
  three real callers.
- Default to no comments unless the *why* is non-obvious.
- For Cloudflare-deployed repos: never commit `.dev.vars*` or `.env*` files.
  Use `.dev.vars.example` / `.env.example` for documentation.

## Common commands (when applicable)

```bash
npm install
npm run dev        # local dev server
npm run build      # type-check + bundle
npm run lint
npm run preview    # build + wrangler dev (Workers/Pages preview)
npm run deploy     # build + wrangler deploy
```

## Self-healing context

This setup is meant to grow. When you notice something that would have helped
you (or future-you) work better — a non-obvious convention, a repeated manual
workflow, a permission prompt that keeps recurring, a tool you keep
re-discovering — capture or propose it. Don't let the same discovery happen
twice.

Where things go:

- **Org-wide convention or insight** → propose an edit to this file
- **Repo-specific convention** → propose an edit to that repo's own `CLAUDE.md`
- **Repeated automated behavior** ("run X before Y", "remind me when Z") →
  propose a hook in `.claude/settings.json` (these are shared via `install.sh`)
- **Repeated multi-step workflow** → propose a slash command in
  `.claude/commands/` or a skill in `.claude/skills/`
- **Permission prompt that keeps recurring** → propose adding it to
  `.claude/settings.json` `permissions.allow`
- **Personal preferences about how to collaborate with the user** → the
  memory system, not this file

Always *propose* before editing shared org config — every repo inherits it,
so changes have blast radius. State the proposal briefly with the rationale
("I keep grepping for X — worth a `/find-x` command?") and let the user
approve before committing.

Avoid capturing: what code does (the code says that), commit-message-style
"added X" notes, or anything likely to be stale within a week.

## Placeholders to fill in over time

- [ ] Coding-style notes specific to PublicStack
- [ ] Branching / PR workflow
- [ ] Secrets handling and Cloudflare account setup
- [ ] Common review checklist
