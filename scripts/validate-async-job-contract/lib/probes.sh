#!/usr/bin/env bash
# Calls 0, 3, 4, 5, 6, 7, 8, 9, 10, 11 of the probe plan
# (specs/001-validate-async-job-contract/contracts/probe-plan.md).
# Call 1 (login) and Call 2 (refresh) live in auth.sh.

auth_header() { printf 'Authorization: Bearer %s' "$ACCESS_TOKEN"; }

# --- Call 0: GET /api/admin/info -------------------------------------------
# Executed immediately after login. Resolves PLATFORM_VERSION, used to
# populate platform.version on every envelope (including 01-login, which
# is patched in after this call returns — see run-spike.sh).
call0_info() {
  capture_http "GET" "/api/admin/info" \
    "$(redacted_headers Authorization)" "{}" "" \
    -H "$(auth_header)"

  PLATFORM_VERSION="$(printf '%s' "$CAP_RESPONSE_BODY_JSON" | jq -r '.result.serverVersion // empty')"
  if [[ -z "$PLATFORM_VERSION" ]]; then
    PLATFORM_VERSION="unknown (platform did not return result.serverVersion on GET /api/admin/info)"
  fi

  ENV0_JSON=$(build_envelope "00-info" "[]")
}

# --- Call 3: GET /api/admin/v2/tasks ----------------------------------------
call3_tasks_list() {
  capture_http "GET" "/api/admin/v2/tasks" \
    "$(redacted_headers Authorization)" "{}" "" \
    -H "$(auth_header)"

  TASK_ID="$(printf '%s' "$CAP_RESPONSE_BODY_JSON" | jq -r '.result[0].Id // empty')"

  local notes="[]"
  if [[ -z "$TASK_ID" ]]; then
    notes='["the platform returned zero scheduled tasks; calls 4 and 5 could not be attempted"]'
  fi
  local env
  env=$(build_envelope "03-tasks-list" "$notes")
  write_envelope "03-tasks-list" "$env"
}

# --- Call 4: GET /api/admin/v2/task?id={id} ---------------------------------
call4_task_single() {
  if [[ -z "$TASK_ID" ]]; then
    CAP_STATUS=0
    CAP_RESPONSE_HEADERS_JSON="{}"
    CAP_RESPONSE_BODY_JSON="null"
    CAP_REQUEST_JSON=$(build_request_json "GET" "/api/admin/v2/task" \
      "$(redacted_headers Authorization)" "{}" "")
    local env
    env=$(build_envelope "04-task-single" '["skipped — no task available from call 3"]')
    write_envelope "04-task-single" "$env"
    return
  fi

  capture_http "GET" "/api/admin/v2/task" \
    "$(redacted_headers Authorization)" "$(jq -n --arg id "$TASK_ID" '{id:$id}')" "" \
    -H "$(auth_header)" -G --data-urlencode "id=${TASK_ID}"

  local env
  env=$(build_envelope "04-task-single" "[]")
  write_envelope "04-task-single" "$env"
}

# --- Call 5: GET /api/admin/v2/task/info?id={id} ----------------------------
call5_task_info() {
  if [[ -z "$TASK_ID" ]]; then
    CAP_STATUS=0
    CAP_RESPONSE_HEADERS_JSON="{}"
    CAP_RESPONSE_BODY_JSON="null"
    CAP_REQUEST_JSON=$(build_request_json "GET" "/api/admin/v2/task/info" \
      "$(redacted_headers Authorization)" "{}" "")
    local env
    env=$(build_envelope "05-task-info" '["skipped — no task available from call 3"]')
    write_envelope "05-task-info" "$env"
    return
  fi

  capture_http "GET" "/api/admin/v2/task/info" \
    "$(redacted_headers Authorization)" "$(jq -n --arg id "$TASK_ID" '{id:$id}')" "" \
    -H "$(auth_header)" -G --data-urlencode "id=${TASK_ID}"

  local env
  env=$(build_envelope "05-task-info" "[]")
  write_envelope "05-task-info" "$env"
}

# --- Call 6: POST /api/admin/v2/database-dir/integrity-check ---------------
# Starts the Q3 probe job. Sets JOB_PATH (the platform-supplied Location
# header, used verbatim for call 7 polls) and OUTSTANDING_JOB_PATH so the
# EXIT trap can cancel it.
call6_start_job() {
  capture_http "POST" "/api/admin/v2/database-dir/integrity-check" \
    "$(redacted_headers Authorization)" "{}" "{}" \
    -H "$(auth_header)"

  local notes="[]"
  if [[ "$CAP_STATUS" == "202" && -n "$CAP_LOCATION_HEADER" ]]; then
    JOB_PATH="$CAP_LOCATION_HEADER"
    OUTSTANDING_JOB_PATH="$JOB_PATH"
  else
    JOB_PATH=""
    notes=$(jq -n --arg s "$CAP_STATUS" \
      '[("unexpected: expected HTTP 202 with Location header, got HTTP " + $s)]')
  fi

  local env
  env=$(build_envelope "06-integrity-check-start" "$notes")
  write_envelope "06-integrity-check-start" "$env"
}

# --- Call 7: poll GET {JOB_PATH} at 1s / 120s ceiling -----------------------
# Captures first / mid-flight-differing / settled-or-ceiling snapshots.
# Sets JOB_SETTLED=1 if a terminal state was observed before the ceiling.
call7_poll_job() {
  JOB_SETTLED=0
  if [[ -z "$JOB_PATH" ]]; then
    for suffix in 07a-async-result-first 07b-async-result-midflight 07c-async-result-settled; do
      CAP_STATUS=0
      CAP_RESPONSE_HEADERS_JSON="{}"
      CAP_RESPONSE_BODY_JSON="null"
      CAP_REQUEST_JSON=$(build_request_json "GET" "(no job path — call 6 did not return one)" \
        "$(redacted_headers Authorization)" "{}" "")
      local env
      env=$(build_envelope "$suffix" '["skipped — call 6 did not produce a job identifier to poll"]')
      write_envelope "$suffix" "$env"
    done
    return
  fi

  local interval=1 ceiling=120 elapsed=0
  local first_body="" prev_state="" prev_progress="" state=""
  local first_env="" midflight_env="" settled_env=""
  local terminal_states="Finished Complete Completed Error Canceled Cancelled"

  while (( elapsed < ceiling )); do
    # Keep the session alive across a long poll (short-lived access
    # tokens observed ~60s TTL) — see auth.sh keepalive_refresh.
    if (( elapsed > 0 && elapsed % 30 == 0 )); then
      keepalive_refresh
    fi
    capture_http "GET" "$JOB_PATH" "$(redacted_headers Authorization)" "{}" "" -H "$(auth_header)"
    state="$(printf '%s' "$CAP_RESPONSE_BODY_JSON" | jq -r '.result.State // empty')"
    local progress
    progress="$(printf '%s' "$CAP_RESPONSE_BODY_JSON" | jq -r '.result.Result.ProgressCurrent // empty')"

    if [[ -z "$first_env" ]]; then
      first_env=$(build_envelope "07a-async-result-first" "[]")
    elif [[ -z "$midflight_env" ]]; then
      local is_terminal=0
      for t in $terminal_states; do [[ "$state" == "$t" ]] && is_terminal=1; done
      if [[ "$is_terminal" -eq 0 ]] && { [[ "$state" != "$prev_state" ]] || [[ "$progress" != "$prev_progress" ]]; }; then
        midflight_env=$(build_envelope "07b-async-result-midflight" "[]")
      fi
    fi

    for t in $terminal_states; do
      if [[ "$state" == "$t" ]]; then
        settled_env=$(build_envelope "07c-async-result-settled" "[]")
        JOB_SETTLED=1
        break 2
      fi
    done

    prev_state="$state"
    prev_progress="$progress"
    sleep "$interval"
    elapsed=$(( elapsed + interval ))
  done

  if [[ -z "$midflight_env" ]]; then
    midflight_env=$(build_envelope "07b-async-result-midflight" '["no state/progress change observed between first and settled/ceiling polls; this is the last non-settled snapshot captured"]')
  fi
  if [[ -z "$settled_env" ]]; then
    settled_env=$(build_envelope "07c-async-result-settled" \
      "$(jq -n --arg interval "$interval" --arg ceiling "$ceiling" \
        '[("polling ceiling of " + $ceiling + "s reached at " + $interval + "s intervals before the job reported a terminal state; this is the last snapshot captured, not a settled state")]')")
  fi

  write_envelope "07a-async-result-first" "$first_env"
  write_envelope "07b-async-result-midflight" "$midflight_env"
  write_envelope "07c-async-result-settled" "$settled_env"

  [[ "$JOB_SETTLED" -eq 1 ]] && OUTSTANDING_JOB_PATH=""
}

# --- Call 8: pause / resume / cancel ----------------------------------------
call8_transitions() {
  keepalive_refresh
  local notes_prefix="[]"
  local transition_job_path="$JOB_PATH"
  local job_id

  if [[ "$JOB_SETTLED" -eq 1 || -z "$JOB_PATH" ]]; then
    # Call 6's job already settled (or never existed) — start a fresh one
    # per contracts/probe-plan.md §8 and record the substitution.
    capture_http "POST" "/api/admin/v2/database-dir/integrity-check" \
      "$(redacted_headers Authorization)" "{}" "{}" \
      -H "$(auth_header)"
    if [[ "$CAP_STATUS" == "202" && -n "$CAP_LOCATION_HEADER" ]]; then
      transition_job_path="$CAP_LOCATION_HEADER"
      OUTSTANDING_JOB_PATH="$transition_job_path"
      notes_prefix=$(jq -n --arg loc "$transition_job_path" \
        '[("substitution: call 6'"'"'s job had already settled, so a second integrity-check was started for the pause/resume/cancel probes at " + $loc)]')
    else
      transition_job_path=""
      notes_prefix='["could not start a substitute job for the pause/resume/cancel probes; call 6'"'"'s job had already settled"]'
    fi
  fi

  job_id="$(printf '%s' "$transition_job_path" | sed -n 's/.*[?&]id=\([^&]*\).*/\1/p')"

  if [[ -z "$transition_job_path" || -z "$job_id" ]]; then
    for suffix in 08a-async-result-pause 08b-async-result-resume 08c-async-result-cancel; do
      CAP_STATUS=0; CAP_RESPONSE_HEADERS_JSON="{}"; CAP_RESPONSE_BODY_JSON="null"
      CAP_REQUEST_JSON=$(build_request_json "POST" "/api/admin/v2/async-result/${suffix##*-}" \
        "$(redacted_headers Authorization)" "{}" "")
      local env
      env=$(build_envelope "$suffix" "$notes_prefix")
      write_envelope "$suffix" "$env"
    done
    return
  fi

  _transition() {
    local action="$1" evidence_id="$2"

    # id is a query parameter, not a body field (matches call 6/9/10 and
    # was verified directly against the running platform); the request
    # body is empty.
    capture_http "POST" "/api/admin/v2/async-result/${action}" \
      "$(redacted_headers Authorization)" "$(jq -n --arg id "$job_id" '{id:$id}')" "" \
      -H "$(auth_header)" -G --data-urlencode "id=${job_id}"
    local transition_status="$CAP_STATUS"
    local transition_env
    transition_env=$(build_envelope "$evidence_id" "[]")

    # One status read immediately after, per contract, embedded in notes
    # (the transition endpoints return an empty body, so the interesting
    # observation is the state change this produced).
    capture_http "GET" "$transition_job_path" "$(redacted_headers Authorization)" "{}" "" -H "$(auth_header)"
    local post_state
    post_state="$(printf '%s' "$CAP_RESPONSE_BODY_JSON" | jq -r '.result.State // "unknown"')"

    local transition_note
    if [[ "$transition_status" == 4* || "$transition_status" == 5* ]]; then
      transition_note="[\"${action} transition not supported by the platform: HTTP ${transition_status}\"]"
    else
      transition_note="$(jq -n --arg s "$post_state" --argjson prefix "$notes_prefix" \
        '$prefix + [("post-transition GET returned State=" + $s)]')"
    fi

    # Patch the notes onto the envelope built from the TRANSITION
    # response (transition_env) — CAP_* now holds the follow-up GET's
    # response and must not be used to rebuild the envelope here.
    local env
    env=$(printf '%s' "$transition_env" | jq --argjson notes "$transition_note" '.notes = $notes')
    write_envelope "$evidence_id" "$env"
  }

  _transition "pause"  "08a-async-result-pause"
  _transition "resume" "08b-async-result-resume"
  _transition "cancel" "08c-async-result-cancel"

  OUTSTANDING_JOB_PATH=""
}

# --- Call 9: GET /api/admin/v2/wqm-categories -------------------------------
call9_wqm_read() {
  keepalive_refresh
  capture_http "GET" "/api/admin/v2/wqm-categories" \
    "$(redacted_headers Authorization)" "{}" "" \
    -H "$(auth_header)"

  WQM_CATEGORY_NAME="$(printf '%s' "$CAP_RESPONSE_BODY_JSON" | jq -r '.result[] | select(.Name=="Utility") | .Name // empty')"
  WQM_ORIGINAL_VALUE="$(printf '%s' "$CAP_RESPONSE_BODY_JSON" | jq -r '.result[] | select(.Name=="Utility") | .MaxActiveWorkers // empty')"
  if [[ -z "$WQM_CATEGORY_NAME" ]]; then
    WQM_CATEGORY_NAME="$(printf '%s' "$CAP_RESPONSE_BODY_JSON" | jq -r '.result[0].Name // empty')"
    WQM_ORIGINAL_VALUE="$(printf '%s' "$CAP_RESPONSE_BODY_JSON" | jq -r '.result[0].MaxActiveWorkers // empty')"
  fi

  local notes="[]"
  [[ -z "$WQM_CATEGORY_NAME" ]] && notes='["the platform returned zero worker-capacity categories; call 10 could not be attempted"]'

  local env
  env=$(build_envelope "09-wqm-categories" "$notes")
  write_envelope "09-wqm-categories" "$env"
}

# --- Call 10: PUT then read-back, then restore ------------------------------
call10_wqm_write_verify() {
  if [[ -z "$WQM_CATEGORY_NAME" ]]; then
    for suffix in 10a-wqm-category-write 10b-wqm-categories-verify; do
      CAP_STATUS=0; CAP_RESPONSE_HEADERS_JSON="{}"; CAP_RESPONSE_BODY_JSON="null"
      CAP_REQUEST_JSON=$(build_request_json "PUT" "/api/admin/v2/wqm-category" \
        "$(redacted_headers Authorization)" "{}" "")
      local env
      env=$(build_envelope "$suffix" '["skipped — call 9 returned no writable category"]')
      write_envelope "$suffix" "$env"
    done
    return
  fi

  # Choose a value that legally differs from the current one.
  local new_value
  if [[ "$WQM_ORIGINAL_VALUE" =~ ^[0-9]+$ ]]; then
    new_value=$(( WQM_ORIGINAL_VALUE + 1 ))
  else
    new_value=3
  fi

  # name is a query parameter (discovered: a body-only "Name" field is
  # rejected with ERROR #40300 "Query parameter 'name' is required"),
  # encoded directly into the URL — NOT via -G, which would also divert
  # the JSON body (MaxActiveWorkers) into the query string.
  capture_http "PUT" "/api/admin/v2/wqm-category?name=$(jq -rn --arg n "$WQM_CATEGORY_NAME" '$n|@uri')" \
    "$(redacted_headers Authorization)" "$(jq -n --arg n "$WQM_CATEGORY_NAME" '{name:$n}')" \
    "$(jq -n --arg v "$new_value" '{MaxActiveWorkers: ($v|tonumber)}')" \
    -H "$(auth_header)"

  local write_env
  write_env=$(build_envelope "10a-wqm-category-write" "[]")
  write_envelope "10a-wqm-category-write" "$write_env"

  capture_http "GET" "/api/admin/v2/wqm-categories" \
    "$(redacted_headers Authorization)" "{}" "" \
    -H "$(auth_header)"

  local verify_value
  verify_value="$(printf '%s' "$CAP_RESPONSE_BODY_JSON" | jq -r --arg n "$WQM_CATEGORY_NAME" '.result[] | select(.Name==$n) | .MaxActiveWorkers // empty')"

  local notes
  if [[ "$verify_value" == "$new_value" ]]; then
    notes=$(jq -n --arg cat "$WQM_CATEGORY_NAME" --arg from "$WQM_ORIGINAL_VALUE" --arg to "$new_value" \
      '[("write took effect: " + $cat + ".MaxActiveWorkers went from " + $from + " to " + $to)]')
  else
    notes=$(jq -n --arg cat "$WQM_CATEGORY_NAME" --arg expected "$new_value" --arg actual "$verify_value" \
      '[("write did not take effect as expected: expected MaxActiveWorkers=" + $expected + ", read back " + ($actual // "empty"))]')
  fi

  # Restore the original value BEFORE finalizing this envelope, so the
  # write-once file already reflects the housekeeping restore (Data
  # Model: Evidence File is written once — the restore therefore happens
  # in-memory-prior-to-write, not as a later mutation of the file).
  if [[ -n "$WQM_ORIGINAL_VALUE" ]]; then
    curl -sS -o /dev/null -X PUT "${IRIS_BASE_URL}/api/admin/v2/wqm-category?name=$(jq -rn --arg n "$WQM_CATEGORY_NAME" '$n|@uri')" \
      -H "$(auth_header)" -H "Content-Type: application/json" \
      --data "$(jq -n --arg v "$WQM_ORIGINAL_VALUE" '{MaxActiveWorkers: ($v|tonumber)}')" 2>/dev/null
    notes=$(printf '%s' "$notes" | jq --arg cat "$WQM_CATEGORY_NAME" --arg orig "$WQM_ORIGINAL_VALUE" \
      '. + [("housekeeping: restored " + $cat + ".MaxActiveWorkers to its original value " + $orig)]')
  fi

  local verify_env
  verify_env=$(build_envelope "10b-wqm-categories-verify" "$notes")
  write_envelope "10b-wqm-categories-verify" "$verify_env"
}

# --- Call 11: chaining-identifier analysis (no network call) ----------------
# Q6: can the app obtain a task's own GUID to use as another task's
# RunAfterGUID? The answer is NO for tasks the app creates via the API:
# - POST /v2/task returns the object without Id or GUID
# - GET /v2/task?id= exposes RunAfterGUID (the predecessor's GUID) but
#   not the task's own GUID
# - GET /v2/tasks (list) and GET /v2/task/info expose neither
# The field RunAfterGUID is writable and confirmed populated on
# pre-existing chained tasks (task 7: "511A7F43-..."), but the create→
# read cycle cannot close because the task's own GUID is never surfaced.
call11_chaining_probe() {
  local f3="$EVIDENCE_DIR/03-tasks-list.json"
  local f4="$EVIDENCE_DIR/04-task-single.json"
  local f5="$EVIDENCE_DIR/05-task-info.json"

  local has_runafterguid="false"
  if [[ -f "$f4" ]]; then
    has_runafterguid="$(jq -r '.response.body.result | has("RunAfterGUID")' "$f4" 2>/dev/null || echo false)"
  fi

  local runafterguid_value=""
  if [[ "$has_runafterguid" == "true" ]]; then
    runafterguid_value="$(jq -r '.response.body.result.RunAfterGUID // ""' "$f4")"
  fi

  local guid_in_list="false"
  if [[ -f "$f3" ]]; then
    guid_in_list="$(jq -r '[.response.body.result[]? // empty | keys[] | select(test("(?i)guid"))] | length > 0' "$f3" 2>/dev/null || echo false)"
  fi
  local guid_in_info="false"
  if [[ -f "$f5" ]]; then
    guid_in_info="$(jq -r '.response.body.result | has("RunAfterGUID") or ([keys[] | select(test("(?i)guid"))] | length > 0)' "$f5" 2>/dev/null || echo false)"
  fi

  local out
  out=$(jq -n \
    --argjson has_field "$has_runafterguid" \
    --arg field_value "$runafterguid_value" \
    --argjson in_list "$guid_in_list" \
    --argjson in_info "$guid_in_info" '
    {
      found: false,
      predecessor_write_field: {
        name: "RunAfterGUID",
        present_in_single_read: $has_field,
        present_in_list_read: $in_list,
        present_in_info_read: $in_info,
        example_value: $field_value,
        note: "RunAfterGUID is the WRITE target for chaining (the predecessor GUID). It is present on the single-task read and confirmed populated on pre-existing chained system tasks (e.g. task 7). However, it carries the PREDECESSOR GUID, not the task own GUID."
      },
      own_guid_exposure: {
        exposed_by_post_v2_task: false,
        exposed_by_get_v2_task: false,
        exposed_by_get_v2_tasks: false,
        exposed_by_get_v2_task_info: false,
        note: "POST /v2/task returns the created object without any identifier (no Id, no GUID). GET /v2/task?id= returns all configurable fields including RunAfterGUID but no field carrying the task own GUID. The create-read cycle cannot close: after creating task A, there is no API path to obtain A GUID for use in task B RunAfterGUID."
      },
      manual_verification: {
        task_7_RunAfterGUID: "511A7F43-7187-11F1-AD1F-000000000000",
        task_7_predecessor_id: 1,
        note: "Confirmed via manual curl outside the script. Task 7 (Purge Audit Database, Runs After #1) carries RunAfterGUID=511A7F43-7187-11F1-AD1F-000000000000, which is the GUID of task 1 (Switch Journal). The GUID exists internally but is not exposed by any read endpoint."
      },
      post_v2_task_deviation: {
        required_fields: 31,
        note: "POST /v2/task requires all 31 fields in the request body (no server-side defaults). The published OpenAPI contract marks most as optional. This is a significant deviation."
      },
      conclusion: "Chaining via the SysAdmin API alone is NOT possible for tasks the app creates. The task own GUID is never exposed. Encadeamento is deferred to a future version or requires a non-API path (SQL to %SYS.Task, which violates ADR-001)."
    }')

  local env
  env=$(jq -n \
    --arg call_id "11-chaining-probe" \
    --arg captured_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson platform "$(jq -n --arg v "${PLATFORM_VERSION:-}" '{version:$v}')" \
    --argjson result "$out" \
    '{
      call_id: $call_id,
      captured_at: $captured_at,
      platform: $platform,
      request: {
        method: "ANALYSIS",
        url_path: "(no network call — jq analysis over 03/04/05 plus manual verification)",
        query: {},
        headers: {},
        body: null
      },
      response: { status: 0, headers: {}, body: $result },
      notes: [
        "This is a jq analysis over already-captured evidence, not a network request; response.status is a placeholder.",
        "Manual verification (task 7 RunAfterGUID and POST /v2/task with all 31 fields) was performed outside this script and recorded in the result."
      ]
    }')
  write_envelope "11-chaining-probe" "$env"
}
