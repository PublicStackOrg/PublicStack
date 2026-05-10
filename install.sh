#!/usr/bin/env bash
# install.sh — bootstrap PublicStackOrg dev environment.
#
# What it does:
#   1. Clones every repo in the PublicStackOrg GitHub org that isn't already
#      checked out alongside this script.
#   2. Symlinks the shared `.claude/` config (settings.json, agents/,
#      commands/, skills/, hooks/) from this directory into each repo so that
#      Claude Code picks them up at the project root.
#   3. Ensures each repo's .gitignore includes `.claude/` so the symlinks
#      don't leak into commits.
#
# Idempotent — safe to re-run. Run it again whenever a new repo appears in
# the org or you add new shared content under `.claude/`.
#
# Requirements: bash, git, and the GitHub CLI (`gh`) authenticated against an
# account with access to the org.

set -euo pipefail

ORG="PublicStackOrg"
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SHARED_CLAUDE="${ROOT_DIR}/.claude"

# Name of the org repo this directory itself represents — derived from the
# parent's origin URL when available. Used to skip self-cloning into a
# subdirectory of itself.
SELF_REPO=""
if [[ -d "${ROOT_DIR}/.git" ]]; then
  origin_url="$(git -C "${ROOT_DIR}" remote get-url origin 2>/dev/null || true)"
  if [[ -n "${origin_url}" ]]; then
    # strip trailing .git, then take everything after the last : or /
    stripped="${origin_url%.git}"
    SELF_REPO="${stripped##*[:/]}"
  fi
fi

# Items inside .claude/ to expose to each repo. Each entry is symlinked into
# <repo>/.claude/<name> as a relative link pointing at ../../.claude/<name>.
SHARED_ITEMS=(settings.json agents commands skills hooks)

color() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
info()  { printf '%s %s\n' "$(color '1;34' '==>')" "$*"; }
ok()    { printf '%s %s\n' "$(color '1;32' ' ok')" "$*"; }
warn()  { printf '%s %s\n' "$(color '1;33' '  !')" "$*" >&2; }
err()   { printf '%s %s\n' "$(color '1;31' 'err')" "$*" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || { err "missing dependency: $1"; exit 1; }
}

require git
require gh

if ! gh auth status >/dev/null 2>&1; then
  err "gh is not authenticated. Run: gh auth login"
  exit 1
fi

if [[ ! -d "${SHARED_CLAUDE}" ]]; then
  err "shared .claude/ not found at ${SHARED_CLAUDE}"
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Clone any missing org repos into ROOT_DIR.
# ---------------------------------------------------------------------------
info "fetching repo list for org ${ORG}"
REPOS=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && REPOS+=("${line}")
done < <(gh repo list "${ORG}" --limit 200 --json name --jq '.[].name')

if [[ ${#REPOS[@]} -eq 0 ]]; then
  warn "no repos found under ${ORG}; nothing to clone"
fi

for repo in "${REPOS[@]}"; do
  if [[ -n "${SELF_REPO}" && "${repo}" == "${SELF_REPO}" ]]; then
    ok "${repo} is this directory — skipping self-clone"
    continue
  fi
  target="${ROOT_DIR}/${repo}"
  if [[ -d "${target}/.git" ]]; then
    ok "${repo} already cloned"
    continue
  fi
  if [[ -e "${target}" ]]; then
    warn "${repo}: ${target} exists but is not a git repo — skipping clone"
    continue
  fi
  info "cloning ${ORG}/${repo}"
  gh repo clone "${ORG}/${repo}" "${target}"
done

# ---------------------------------------------------------------------------
# 2. Symlink shared .claude/ contents into each repo.
# ---------------------------------------------------------------------------
link_into_repo() {
  local repo_dir="$1"
  local repo_name
  repo_name="$(basename "${repo_dir}")"

  mkdir -p "${repo_dir}/.claude"

  for item in "${SHARED_ITEMS[@]}"; do
    local src="${SHARED_CLAUDE}/${item}"
    local dst="${repo_dir}/.claude/${item}"

    if [[ ! -e "${src}" ]]; then
      # Source missing — skip silently. Lets the script tolerate, e.g., no
      # hooks/ yet.
      continue
    fi

    if [[ -e "${dst}" && ! -L "${dst}" ]]; then
      warn "${repo_name}: ${dst#${ROOT_DIR}/} exists and is not a symlink — leaving it alone"
      continue
    fi

    # Relative target so the link survives directory moves as long as the
    # tree is moved as a whole.
    ln -sfn "../../.claude/${item}" "${dst}"
  done

  ok "${repo_name}: linked $(printf '%s ' "${SHARED_ITEMS[@]}")"
}

# ---------------------------------------------------------------------------
# 3. Ensure each repo's .gitignore excludes .claude/ so symlinks don't leak.
# ---------------------------------------------------------------------------
ignore_in_repo() {
  local repo_dir="$1"
  local gitignore="${repo_dir}/.gitignore"
  local repo_name
  repo_name="$(basename "${repo_dir}")"

  touch "${gitignore}"
  if grep -qxF '.claude/' "${gitignore}" || grep -qxF '/.claude/' "${gitignore}"; then
    return 0
  fi
  {
    printf '\n# Claude Code: managed by ../install.sh\n'
    printf '.claude/\n'
  } >> "${gitignore}"
  ok "${repo_name}: added .claude/ to .gitignore"
}

shopt -s nullglob
for repo_dir in "${ROOT_DIR}"/*/; do
  repo_dir="${repo_dir%/}"
  [[ -d "${repo_dir}/.git" ]] || continue
  link_into_repo "${repo_dir}"
  ignore_in_repo "${repo_dir}"
done

# ---------------------------------------------------------------------------
# 4. Install the publicstack CLI (Phase 3 of blueprint/docs/PLAN.md).
# ---------------------------------------------------------------------------
if [[ -d "${ROOT_DIR}/blueprint/cli" ]]; then
  if command -v pipx >/dev/null 2>&1; then
    info "installing publicstack CLI via pipx"
    if pipx install --force "${ROOT_DIR}/blueprint/cli" >/dev/null; then
      ok "publicstack CLI installed/updated"
    else
      warn "pipx install of publicstack failed (continuing)"
    fi
  else
    warn "pipx not found — skipping publicstack CLI install (install pipx and re-run)"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Install the publicstack-contracts CLI (Phase 4 of blueprint/docs/PLAN.md).
# ---------------------------------------------------------------------------
if [[ -d "${ROOT_DIR}/blueprint/contracts/tooling" ]]; then
  if command -v pipx >/dev/null 2>&1; then
    info "installing publicstack-contracts CLI via pipx"
    if pipx install --force "${ROOT_DIR}/blueprint/contracts/tooling" >/dev/null; then
      ok "publicstack-contracts CLI installed/updated"
    else
      warn "pipx install of publicstack-contracts failed (continuing)"
    fi
  fi
fi

info "done. Open any repo and Claude Code should see the shared config."
