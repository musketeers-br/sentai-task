#!/usr/bin/env bash
# Checks that every specs/*/spec.md **Status** agrees with its tasks.md ("Spec status" in AGENTS.md).
# Exit 0 = consistent, 1 = at least one spec says something its tasks contradict.
set -u
cd "$(dirname "$0")/.."
VALID='^(Draft|Planned|In Progress|Implemented|Merged|Superseded by [0-9]{3})$'
bad=0
for spec in specs/*/spec.md; do
  dir=$(dirname "$spec"); name=$(basename "$dir")
  status=$(grep -m1 -E '^\*\*Status\*\*:' "$spec" | sed -E 's/^\*\*Status\*\*:[[:space:]]*//; s/[[:space:]]*<!--.*$//; s/[[:space:]]+$//')
  tasks="$dir/tasks.md"
  if [[ -f $tasks ]]; then
    done_n=$(grep -cE '^- \[[xX]\]' "$tasks")
    open_n=$(grep -E '^- \[ \]' "$tasks" | grep -vc '\[external\]')
  else
    done_n=0; open_n=0
  fi
  fail() { echo "FAIL $name: Status '$status' but $1"; bad=1; }
  if [[ ! $status =~ $VALID ]]; then fail "that is not one of Draft|Planned|In Progress|Implemented|Merged|Superseded by NNN"; continue; fi
  case $status in
    Draft|Planned)        [[ $done_n -gt 0 ]] && fail "$done_n task(s) are already checked (use In Progress)";;
    "In Progress")        [[ $done_n -eq 0 ]] && fail "no task is checked yet (use Planned)"
                          [[ $open_n -eq 0 && -f $tasks ]] && fail "every non-[external] task is done (use Implemented)";;
    Implemented|Merged)   [[ -f $tasks ]] || fail "there is no tasks.md"
                          [[ $open_n -gt 0 ]] && fail "$open_n non-[external] task(s) are still open";;
  esac
done
[[ $bad -eq 0 ]] && echo "spec status: consistent"
exit $bad
