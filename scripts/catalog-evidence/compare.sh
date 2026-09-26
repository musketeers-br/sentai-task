#!/usr/bin/env bash
# Spec 006 quickstart (a) — SC-001 / SC-002: compares, for EVERY task on the instance, each value
# the product's catalog returns with the platform's own reads (list, single, info), and checks
# that the item read equals the list item (US-1 scenario 4).
#
#   IRIS_USER=… IRIS_PASSWORD=… scripts/catalog-evidence/compare.sh
#
# Credentials come only from the environment. The access token is kept in memory (do_login from
# the spec 001 helpers) and is never printed or written. The platform's serialized %Status is
# decoded by the platform itself ($SYSTEM.Status.GetErrorText, in the container), never here.
# Output: specs/006-task-catalog-api/evidence/a-field-compare.json. Exit 1 on any mismatch.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$ROOT/scripts/validate-async-job-contract/lib"
# shellcheck source=../validate-async-job-contract/lib/common.sh
source "$LIB/common.sh"
# shellcheck source=../validate-async-job-contract/lib/auth.sh
source "$LIB/auth.sh"

OUT_DIR="$ROOT/specs/006-task-catalog-api/evidence"
OUT="$OUT_DIR/a-field-compare.json"
CONTAINER="${IRIS_CONTAINER:-sentai-task-iris-1}"
API="${IRIS_BASE_URL}/csp/sentai/api/v1"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

preflight
do_login || { log_error "login failed"; exit 2; }

get() { # path → body on stdout; the bearer header is built here and never echoed
  curl -sS -H "Authorization: Bearer ${ACCESS_TOKEN}" "${IRIS_BASE_URL}$1"
}

log_info "Reading the product catalog and the platform's reads…"
get "/csp/sentai/api/v1/catalog/tasks" > "$WORK/product.json"
get "/api/admin/v2/tasks" > "$WORK/list.json"

jq -r '.result[].Id' "$WORK/list.json" > "$WORK/ids.txt"
echo '{}' > "$WORK/platform.json"
while read -r id; do
  get "/api/admin/v2/task?id=${id}" > "$WORK/single.json"
  get "/api/admin/v2/task/info?id=${id}" > "$WORK/info.json"
  get "/csp/sentai/api/v1/catalog/tasks/${id}" > "$WORK/item.json"
  jq --arg id "$id" --slurpfile s "$WORK/single.json" --slurpfile i "$WORK/info.json" --slurpfile it "$WORK/item.json" \
    '.[$id] = {single: $s[0], info: $i[0], item: $it[0]}' "$WORK/platform.json" > "$WORK/p.tmp" && mv "$WORK/p.tmp" "$WORK/platform.json"
done < "$WORK/ids.txt"

# Serialized %Status values ("0 …") decoded by the platform's own function.
jq '[to_entries[] | select((.value.info.result.Status // "") | startswith("0 ")) | {id: .key, s: .value.info.result.Status}]' \
  "$WORK/platform.json" > "$WORK/serialized.json"
echo '{}' > "$WORK/decoded.json"
if [[ "$(jq length "$WORK/serialized.json")" -gt 0 ]]; then
  docker cp "$WORK/serialized.json" "$CONTAINER:/tmp/sentai-006-serialized.json" >/dev/null
  docker exec -i "$CONTAINER" iris session IRIS -U IRISAPP > "$WORK/decoded.raw" 2>&1 <<'X'
set f=##class(%Stream.FileCharacter).%New() set f.TranslateTable="UTF8" do f.LinkToFile("/tmp/sentai-006-serialized.json") set a={}.%FromJSON(f) set o={} set it=a.%GetIterator() while it.%GetNext(.k,.e) { do o.%Set(e.id,$SYSTEM.Status.GetErrorText(e.s)) } write !,"DECODED:",o.%ToJSON(),!
halt
X
  docker exec -u root "$CONTAINER" rm -f /tmp/sentai-006-serialized.json
  sed -n 's/^DECODED://p' "$WORK/decoded.raw" > "$WORK/decoded.json"
fi

jq -n \
  --slurpfile product "$WORK/product.json" \
  --slurpfile list "$WORK/list.json" \
  --slurpfile platform "$WORK/platform.json" \
  --slurpfile decoded "$WORK/decoded.json" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  def documented: ["taskId","name","namespace","class","runAsUser","timePeriod","nextRun","lastStarted",
    "lastFinished","status","lastError","suspended","destructive","destructiveUnknown","origin",
    "unavailable","isDestructive","lastRun"];
  def ok(r): (r.status.errors // []) | length == 0;
  ($product[0]) as $p | ($list[0].result) as $rows | ($platform[0]) as $pl | ($decoded[0]) as $dec
  | ($p.items | map({key: (.taskId|tostring), value: .}) | from_entries) as $byId
  | [ $rows[] | (.Id|tostring) as $id | . as $l | ($pl[$id]) as $r | ($byId[$id]) as $t
      | ($r.single.result // null) as $s | ($r.info.result // null) as $i
      | [ ["name", $l.Name], ["namespace", $l.Namespace],
          ["class", $s.TaskClass], ["runAsUser", $s.RunAsUser], ["timePeriod", $s.TimePeriod],
          ["nextRun", $i.NextScheduled], ["lastStarted", $i.LastStarted], ["lastFinished", $i.LastFinished],
          ["lastError", $i.Error], ["suspended", $i.Suspended],
          ["status", (if ($i.Status // "" | startswith("0 ")) then $dec[$id] else $i.Status end)] ][]
      | . as [$field, $platformValue]
      | ($t | has($field)) as $present
      | ([($t.unavailable // [])[] | .fields[]] | index($field)) as $flagged
      | {taskId: ($id|tonumber), field: $field,
         product: (if $present then $t[$field] else (if $flagged != null then "<unavailable>" else "<absent>" end) end),
         platform: $platformValue,
         equal: (if $present then ($t[$field] == $platformValue) else ($flagged != null and $platformValue == null) end)} ]
    as $compare
  | [ $p.items[] | . as $t | (keys - documented)[] | {taskId: $t.taskId, key: .} ] as $undocumented
  | [ $rows[] | (.Id|tostring) as $id | select(($pl[$id].item | del(.recentRuns)) != $byId[$id]) | ($id|tonumber) ] as $itemMismatch
  | { captured_at: $at,
      total_product: $p.total, total_platform: ($rows|length),
      rows: $compare,
      mismatches: [ $compare[] | select(.equal | not) ],
      undocumented_keys: $undocumented,
      item_read_differs_from_list: $itemMismatch,
      pass: (($p.total == ($rows|length)) and ([ $compare[] | select(.equal | not) ] | length == 0)
             and ($undocumented | length == 0) and ($itemMismatch | length == 0)) }' > "$WORK/result.json"

mkdir -p "$OUT_DIR"
cp "$WORK/result.json" "$OUT"
jq -r '"tasks: product \(.total_product), platform \(.total_platform) · rows \(.rows|length) · mismatches \(.mismatches|length) · undocumented keys \(.undocumented_keys|length) · item≠list \(.item_read_differs_from_list|length) · pass \(.pass)"' "$OUT" >&2
jq -e '.pass' "$OUT" >/dev/null
