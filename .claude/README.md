# Shared `.claude/` for PublicStackOrg

This directory holds Claude Code config that is shared across every repo in
the org. The parent `CLAUDE.md` is auto-loaded by Claude Code as you walk into
any subdirectory, but `.claude/settings.json`, agents, commands, and skills
**only load from a project root or `~/.claude/`** — they are not inherited
from parent directories.

To make them available inside each repo, run [`../install.sh`](../install.sh)
from the parent directory. It symlinks:

```
<repo>/.claude/settings.json -> ../../.claude/settings.json
<repo>/.claude/agents        -> ../../.claude/agents
<repo>/.claude/commands      -> ../../.claude/commands
<repo>/.claude/skills        -> ../../.claude/skills
<repo>/.claude/hooks         -> ../../.claude/hooks
```

It also adds `.claude/` to each repo's `.gitignore` so symlinks don't leak.

To pull every repo (and re-run `install.sh` afterwards), use [`../update.sh`](../update.sh).
It refuses to touch any repo with uncommitted changes, unpushed commits, or a
detached HEAD, and only ever does `git pull --ff-only`.

## Layout

- `settings.json` — permissions allow-list + (optionally) hooks
- `agents/` — shared subagents
- `commands/` — shared slash commands
- `skills/` — shared skills
- `hooks/` — shared hook scripts referenced from `settings.json`

Drop new content in here, then re-run `install.sh` to propagate (symlinks make
this a no-op for already-installed repos).
