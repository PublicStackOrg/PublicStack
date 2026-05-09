#!/usr/bin/env bash
# update.sh — pull every repo in this directory safely.
#
# Designed to never destroy in-progress work. For each repo it:
#
#   1. Skips if the working tree is dirty (uncommitted changes).
#   2. Skips if the current branch has commits not yet pushed upstream.
#   3. Skips if HEAD is detached or the branch has no upstream.
#   4. Otherwise runs `git pull --ff-only` so a divergent remote is reported,
#      not silently merged or rebased.
#
# Also pulls the parent repo (this directory) under the same rules and runs
# install.sh at the end to re-link any newly-added shared config.
#
# Idempotent — safe to re-run. Re-run after pulling new repos in the org.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

color() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
info()  { printf '%s %s\n' "$(color '1;34' '==>')" "$*"; }
ok()    { printf '%s %s\n' "$(color '1;32' ' ok')" "$*"; }
skip()  { printf '%s %s\n' "$(color '1;33' 'skip')" "$*"; }
err()   { printf '%s %s\n' "$(color '1;31' ' err')" "$*" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || { err "missing dependency: $1"; exit 1; }
}
require git

# Returns 0 (clean) or 1 (dirty). Considers untracked files dirty too.
is_dirty() {
  local repo="$1"
  ! git -C "${repo}" diff --quiet --ignore-submodules HEAD 2>/dev/null && return 0
  ! git -C "${repo}" diff --cached --quiet --ignore-submodules HEAD 2>/dev/null && return 0
  if [[ -n "$(git -C "${repo}" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
    return 0
  fi
  return 1
}

update_repo() {
  local repo="$1"
  local name
  name="$(basename "${repo}")"

  # 1. Detached HEAD?
  local branch
  branch="$(git -C "${repo}" symbolic-ref --quiet --short HEAD || true)"
  if [[ -z "${branch}" ]]; then
    skip "${name}: detached HEAD — leaving alone"
    return
  fi

  # 2. Working tree clean?
  if is_dirty "${repo}"; then
    skip "${name}: uncommitted changes on '${branch}' — not pulling"
    return
  fi

  # 3. Upstream configured?
  local upstream
  upstream="$(git -C "${repo}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ -z "${upstream}" ]]; then
    skip "${name}: '${branch}' has no upstream — leaving alone"
    return
  fi

  # 4. Refresh remote refs without modifying the working tree.
  if ! git -C "${repo}" fetch --quiet --prune; then
    err "${name}: fetch failed"
    return
  fi

  # 5. Unpushed local commits?
  local ahead behind
  read -r ahead behind < <(git -C "${repo}" rev-list --left-right --count "@{u}...HEAD" 2>/dev/null || echo "0 0")
  if [[ "${ahead:-0}" -gt 0 ]]; then
    # The "left" count in @{u}...HEAD is commits in HEAD not in upstream — i.e.
    # local commits not yet pushed. Don't risk a fast-forward against unpushed
    # work; just report it.
    skip "${name}: '${branch}' has ${ahead} unpushed commit(s) — not pulling"
    return
  fi

  # 6. Already up to date?
  if [[ "${behind:-0}" -eq 0 ]]; then
    ok "${name}: up to date on '${branch}'"
    return
  fi

  # 7. Fast-forward.
  if git -C "${repo}" pull --ff-only --quiet; then
    ok "${name}: fast-forwarded '${branch}' (${behind} commit(s))"
  else
    err "${name}: pull --ff-only failed (divergent history?). Resolve manually."
  fi
}

# ---------------------------------------------------------------------------
# 1. Parent repo (this directory).
# ---------------------------------------------------------------------------
if [[ -d "${ROOT_DIR}/.git" ]]; then
  info "updating parent repo"
  update_repo "${ROOT_DIR}"
fi

# ---------------------------------------------------------------------------
# 2. Sibling repos.
# ---------------------------------------------------------------------------
info "updating sibling repos"
shopt -s nullglob
for repo in "${ROOT_DIR}"/*/; do
  repo="${repo%/}"
  [[ -d "${repo}/.git" ]] || continue
  update_repo "${repo}"
done

# ---------------------------------------------------------------------------
# 3. Re-run install.sh so any newly-added shared config / new org repos get
#    wired up. install.sh is idempotent.
# ---------------------------------------------------------------------------
if [[ -x "${ROOT_DIR}/install.sh" ]]; then
  info "re-running install.sh to pick up any new shared config / repos"
  "${ROOT_DIR}/install.sh"
fi
