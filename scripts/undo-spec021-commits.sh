#!/usr/bin/env bash
# Undoes the four spec 021 commits on feat/spec021 — nothing else.
# The work stays in the working tree, uncommitted, so development can continue.
# To re-create the commits later (same order and messages, fresh date/time),
# follow specs/021-first-time-tour/commits-021.md.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

die() { echo "undo-spec021-commits: $*" >&2; exit 1; }

[ "$(git branch --show-current)" = feat/spec021 ] || die "run this on feat/spec021 (you are on '$(git branch --show-current)')"
[ "$(git rev-list --count master..HEAD)" = 4 ] || die "expected 4 commits ahead of master, found $(git rev-list --count master..HEAD)"

# Safety: the original commits (including their exact intermediate diffs, which the
# working tree no longer represents) stay reachable until the redo is accepted.
git branch spec021-backup

# The undo itself: branch tip back to master; every change stays in the tree.
git reset --mixed master

echo "Undone. The 021 work remains in the working tree, uncommitted."
echo "Redo later by following specs/021-first-time-tour/commits-021.md."
echo "Do not delete spec021-backup until the redo is verified."
