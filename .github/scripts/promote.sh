#!/usr/bin/env bash
#
# promote.sh — cut a Stable release by promoting nightly → main.
#
# Run this INSTEAD of clicking GitHub's "Squash & merge" on a nightly → main PR.
# Every promotion adds a commit to `main` that never lands on `nightly`, so the two
# branches don't share recent history — GitHub's merge button then does a 3-way
# merge against a stale base and conflicts every time.
#
# This sidesteps the merge entirely: it sets `main`'s tree to *exactly*
# `origin/nightly` as one new commit and pushes it normally. No merge → no conflict;
# no rewind → no force-push. `main` gets exactly one commit per release, so the
# Stable version stays `0.<commit count on main>`. Pushing to `main` triggers
# ci.yml's release job (build + publish DMG + cask bump).
#
#   Usage:  .github/scripts/promote.sh        # promote, with a confirmation prompt
#           .github/scripts/promote.sh --yes  # skip the prompt (non-interactive / CI)
#
# Requires: git (and gh, optionally, to auto-close any open promotion PR).

set -euo pipefail

REPO="rafay99-epic/Quill"

# In this repo "nightly" is both a branch AND a release tag, so a bare `nightly`
# ref is ambiguous. Use fully-qualified remote-tracking refs everywhere.
ORIGIN_MAIN="refs/remotes/origin/main"
ORIGIN_NIGHTLY="refs/remotes/origin/nightly"

assume_yes=false
case "${1:-}" in
  -y | --yes) assume_yes=true ;;
  "") ;;
  *) echo "Unknown argument: $1 (use --yes to skip the prompt)"; exit 2 ;;
esac

git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not inside a git repository."; exit 1; }

# We move HEAD around, so refuse to run on a dirty tree.
if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree isn't clean — commit or stash your changes first."
  exit 1
fi

start_ref="$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)"

echo "Fetching latest main + nightly…"
git fetch --quiet origin \
  "+refs/heads/main:${ORIGIN_MAIN}" \
  "+refs/heads/nightly:${ORIGIN_NIGHTLY}"

# Nothing to ship if main's content already equals nightly's.
if git diff --quiet "${ORIGIN_MAIN}" "${ORIGIN_NIGHTLY}"; then
  echo "main is already identical to nightly — nothing to promote."
  exit 0
fi

# Stable version = 0.<commit count on main AFTER this promotion commit>.
version="0.$(( $(git rev-list --count "${ORIGIN_MAIN}") + 1 ))"

echo
echo "About to cut Stable ${version}. Changes since the last Stable cut:"
git --no-pager log --oneline "${ORIGIN_MAIN}..${ORIGIN_NIGHTLY}" | sed 's/^/  /'
echo
echo "This sets main's contents to exactly origin/nightly, commits, and pushes to"
echo "main — which triggers the release build that publishes the DMG to Stable users."
if [ "$assume_yes" = false ]; then
  printf 'Proceed? [y/N] '
  read -r reply
  case "$reply" in
    y | Y | yes | YES) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

# Land on main at its current tip, then replace its tree with nightly's wholesale.
git checkout --quiet main
git reset --quiet --hard "${ORIGIN_MAIN}"
git read-tree -u --reset "${ORIGIN_NIGHTLY}"

# Safety net: the staged tree MUST equal nightly exactly. If not, back out cleanly.
if ! git diff --quiet --cached "${ORIGIN_NIGHTLY}"; then
  echo "Aborting: staged tree doesn't match nightly (unexpected)."
  git reset --quiet --hard "${ORIGIN_MAIN}"
  git checkout --quiet "$start_ref"
  exit 1
fi

git commit --quiet \
  -m "Promote nightly → main: Stable ${version}" \
  --trailer "Promoted-nightly: $(git rev-parse "${ORIGIN_NIGHTLY}")"
git push origin main

# Return to where we started.
git checkout --quiet "$start_ref"

# Best-effort: close any open nightly → main PR.
if command -v gh >/dev/null 2>&1; then
  pr="$(gh pr list --base main --head nightly --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)"
  if [ -n "$pr" ]; then
    gh pr close "$pr" --comment "Promoted via \`.github/scripts/promote.sh\` (Stable ${version}). main now matches nightly exactly." >/dev/null 2>&1 \
      && echo "Closed promotion PR #${pr}." || true
  fi
fi

echo
echo "✅ Pushed Stable ${version}. Release build:"
echo "   https://github.com/${REPO}/actions/workflows/ci.yml"
