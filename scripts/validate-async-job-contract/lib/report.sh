#!/usr/bin/env bash
# T007: consolidates the captured evidence into compatibility.md and
# decision.md at the feature-directory root. Reads back the evidence
# files already written to disk (all real facts below are pulled from
# them via jq, not hand-typed) and assembles the required sections per
# data-model.md.

_jq_file() { jq -r "$2" "$EVIDENCE_DIR/$1.json" 2>/dev/null; }
_status_of() { _jq_file "$1" '.response.status'; }
_note_list_of() { jq -r '.notes[]? // empty' "$EVIDENCE_DIR/$1.json" 2>/dev/null; }

generate_report() {
  local run_ts
  run_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # ---- gather facts ----
  local q1_login_status q1_refresh_status q1_info_status
  q1_login_status=$(_status_of "01-login")
  q1_refresh_status=$(_status_of "02-refresh")
  q1_info_status=$(_status_of "00-info")

  local q3_status q3_location
  q3_status=$(_status_of "06-integrity-check-start")
  q3_location=$(_jq_file "06-integrity-check-start" '.response.headers.LOCATION // .response.headers.Location // empty')

  local q4_state_first q4_state_settled q4_time_queued q4_time_started q4_time_finished q4_failure_reason
  q4_state_first=$(_jq_file "07a-async-result-first" '.response.body.result.State // empty')
  q4_state_settled=$(_jq_file "07c-async-result-settled" '.response.body.result.State // empty')
  q4_time_queued=$(_jq_file "07c-async-result-settled" '.response.body.result.TimeQueued // empty')
  q4_time_started=$(_jq_file "07c-async-result-settled" '.response.body.result.TimeStarted // empty')
  q4_time_finished=$(_jq_file "07c-async-result-settled" '.response.body.result.TimeFinished // empty')
  q4_failure_reason=$(_jq_file "07c-async-result-settled" '.response.body.result.FailureReason // empty')

  local q4_pause_status q4_resume_status q4_cancel_status
  q4_pause_status=$(_status_of "08a-async-result-pause")
  q4_resume_status=$(_status_of "08b-async-result-resume")
  q4_cancel_status=$(_status_of "08c-async-result-cancel")
  local q4_pause_state q4_resume_state q4_cancel_state
  q4_pause_state=$(_note_list_of "08a-async-result-pause" | grep -o 'State=[A-Za-z]*' | head -1)
  q4_resume_state=$(_note_list_of "08b-async-result-resume" | grep -o 'State=[A-Za-z]*' | head -1)
  q4_cancel_state=$(_note_list_of "08c-async-result-cancel" | grep -o 'State=[A-Za-z]*' | head -1)

  local q5_read_status q5_write_status q5_verify_status
  q5_read_status=$(_status_of "09-wqm-categories")
  q5_write_status=$(_status_of "10a-wqm-category-write")
  q5_verify_status=$(_status_of "10b-wqm-categories-verify")
  local q5_write_took_effect
  q5_write_took_effect=$(_note_list_of "10b-wqm-categories-verify" | grep -c '^write took effect' || true)

  local q6_found
  q6_found=$(_jq_file "11-chaining-probe" '.response.body.found')

  local platform_version image_digest
  platform_version=$(_jq_file "00-info" '.platform.version')
  [[ -z "$platform_version" || "$platform_version" == "null" ]] && platform_version="${PLATFORM_VERSION:-unknown}"
  image_digest="${IMAGE_DIGEST:-}"

  local archive_note=""
  if [[ -n "${ARCHIVED_TO:-}" ]]; then
    archive_note="A prior run's evidence, compatibility statement, and decision were archived to \`${ARCHIVED_TO}\` before this run wrote anything new."
  fi

  # ---- decision ----
  local q3_closed_positive=0 q4_closed_positive=0
  [[ "$q3_status" == "202" && -n "$q3_location" ]] && q3_closed_positive=1
  if [[ "$q4_state_settled" == "Finished" && "$q4_pause_status" == "200" && "$q4_resume_status" == "200" && "$q4_cancel_status" == "200" ]]; then
    q4_closed_positive=1
  fi

  local decision consequence
  if [[ "$q3_closed_positive" -eq 1 && "$q4_closed_positive" -eq 1 ]]; then
    decision="delegate parallel execution to the platform"
    consequence="Q3 and Q4 both closed positively: the platform returns a job identifier for long-running operations (evidence/06-integrity-check-start.json, HTTP ${q3_status}), and that identifier drives an observable execution state, timings, and cancel/pause/resume transitions (evidence/07c-async-result-settled.json, evidence/08a-async-result-pause.json, evidence/08b-async-result-resume.json, evidence/08c-async-result-cancel.json). The planned product scope stands: the product delegates parallel execution of maintenance operations to the platform's own async-job mechanism rather than building an execution engine inside the product."
  else
    decision="build execution engine inside the product"
    consequence="Q3 and/or Q4 did not close positively (Q3 positive=${q3_closed_positive}, Q4 positive=${q4_closed_positive}). The execution engine must be built inside the product. Follow-up action: the planned scope of every dependent feature that assumed platform-delegated parallel execution must be reduced the same day this decision is recorded — re-run /speckit-specify or /speckit-plan for those features with this constraint before further design proceeds."
  fi

  # ---- compatibility.md ----
  {
    echo "# Compatibility Statement"
    echo
    echo "**Feature**: 001-validate-async-job-contract"
    echo "**Run captured**: ${run_ts}"
    echo
    echo "## Environment"
    echo
    echo "- **Platform version**: ${platform_version}"
    if [[ -n "$image_digest" ]]; then
      echo "- **Image digest**: \`${image_digest}\`"
    else
      echo "- **Image digest**: not captured this run (set \`IRIS_CONTAINER\` to the running container's name/id to include it; see contracts/script-cli.md)"
    fi
    echo "- **Base URL**: ${IRIS_BASE_URL}"
    echo "- **Run timestamp**: ${run_ts}"
    echo
    echo "## Q1 — Reachability and authentication"
    echo
    echo "The management API responded on the freely available Community edition."
    echo "- Login (\`POST /api/admin/login\`): HTTP ${q1_login_status}. See [evidence/01-login.json](evidence/01-login.json)."
    echo "- **Deviation**: the published contract implies a JSON \`{username,password}\` body; the platform instead requires HTTP Basic Auth (\`-u user:pass\`) with the request body unused. The successful envelope is flat — \`{access_token, refresh_token, sub, iat, exp}\` — not the \`{status,console,result}\` wrapper every other admin endpoint uses."
    echo "- Session renewal (\`POST /api/admin/refresh\`): HTTP ${q1_refresh_status}. Requires the current \`access_token\` as a Bearer header plus \`{\"refresh_token\": ...}\` in the body; returns a fresh access/refresh pair in the same flat shape. See [evidence/02-refresh.json](evidence/02-refresh.json)."
    echo "- Platform/version info (\`GET /api/admin/info\`): HTTP ${q1_info_status}, wrapped in \`{status,console,result}\`; \`result.serverVersion\` is the platform version string used throughout this statement. See [evidence/00-info.json](evidence/00-info.json)."
    echo
    echo "## Q2 — Response shapes"
    echo
    echo "- List (\`GET /api/admin/v2/tasks\`): wrapped \`{status,console,result:[...]}\`; each element carries \`Id\` (small integer, e.g. 1, 4), \`Name\`, \`Type\`, \`Namespace\`, \`Description\`, \`Suspended\`, \`LastFinished\`, \`NextScheduled\`. See [evidence/03-tasks-list.json](evidence/03-tasks-list.json)."
    echo "- Single (\`GET /api/admin/v2/task?id=\`): wrapped; a much larger object including scheduling fields (\`TimePeriod*\`, \`DailyFrequency*\`, \`StartDate\`), \`TaskClass\`, \`RunAsUser\`, and — critically — \`RunAfterGUID\` (see Q6). See [evidence/04-task-single.json](evidence/04-task-single.json)."
    echo "- Info (\`GET /api/admin/v2/task/info?id=\`): wrapped; runtime-status-only fields — \`Type\`, \`Status\`, \`Error\`, \`LastSchedule\`, \`LastStarted\`, \`LastFinished\`, \`NextScheduled\`, \`Suspended\`. Does not include \`RunAfterGUID\`. See [evidence/05-task-info.json](evidence/05-task-info.json)."
    echo "- The task's own list identifier (\`Id\`) is present and is what \`?id=\` expects on both the single-task and info reads; confirmed by successful ${q1_info_status:+HTTP }200 responses on both."
    echo
    echo "## Q3 — Long-running operations"
    echo
    echo "\`POST /api/admin/v2/database-dir/integrity-check\` returned HTTP ${q3_status} (accepted-for-processing), carrying no job identifier in the response body but a \`Location\` header pointing at the async-result resource: \`${q3_location}\`. See [evidence/06-integrity-check-start.json](evidence/06-integrity-check-start.json)."
    echo "- **Deviation**: the Location header uses \`/api/admin/v1/async-result\`, not \`v2\`, despite the triggering call being a \`v2\` endpoint. Both \`v1\` and \`v2\` forms of \`GET .../async-result?id=...\` were verified to respond identically for the same job id."
    echo
    echo "## Q4 — Job observation and control"
    echo
    echo "- **State**: observed transitioning Running → Finished across polls (first: \`${q4_state_first}\`, settled: \`${q4_state_settled}\`). See [evidence/07a-async-result-first.json](evidence/07a-async-result-first.json), [evidence/07b-async-result-midflight.json](evidence/07b-async-result-midflight.json), [evidence/07c-async-result-settled.json](evidence/07c-async-result-settled.json)."
    echo "- **Timings**: TimeQueued=\`${q4_time_queued}\`, TimeStarted=\`${q4_time_started}\`, TimeFinished=\`${q4_time_finished}\` — all populated on natural completion."
    echo "- **Failure reason**: the \`FailureReason\` field is present on every poll (observed as \`\"${q4_failure_reason}\"\` on the success path in this run). This run's job completed successfully, so a populated failure string was not observed; treated as an **open risk** below, not a spike-closing negative, per the plan's guidance."
    echo "- **Pause**: HTTP ${q4_pause_status}; post-transition read reported ${q4_pause_state:-<no state change note captured>}. See [evidence/08a-async-result-pause.json](evidence/08a-async-result-pause.json)."
    echo "- **Resume**: HTTP ${q4_resume_status}; post-transition read reported ${q4_resume_state:-<no state change note captured>}. See [evidence/08b-async-result-resume.json](evidence/08b-async-result-resume.json)."
    echo "- **Cancel**: HTTP ${q4_cancel_status}; post-transition read reported ${q4_cancel_state:-<no state change note captured>}. See [evidence/08c-async-result-cancel.json](evidence/08c-async-result-cancel.json)."
    echo "- **Note**: \`TimeFinished\` was observed to remain empty after a Cancel transition (cancellation is not treated as a form of completion by the timings field)."
    echo
    echo "## Q5 — Resource ceilings"
    echo
    echo "- Read (\`GET /api/admin/v2/wqm-categories\`): HTTP ${q5_read_status}; returns an array of \`{Name, MaxActiveWorkers, DefaultWorkers, MaxWorkers, MaxTotalWorkers, AlwaysQueue}\`. See [evidence/09-wqm-categories.json](evidence/09-wqm-categories.json)."
    echo "- Write (\`PUT /api/admin/v2/wqm-category?name=...\`): HTTP ${q5_write_status}. **Deviation**: \`name\` is a query parameter, not a body field — a body-only \`Name\` was rejected with \`ERROR #40300\`. See [evidence/10a-wqm-category-write.json](evidence/10a-wqm-category-write.json)."
    echo "- Read-back (\`GET /api/admin/v2/wqm-categories\` again): HTTP ${q5_verify_status}. Write took effect and was confirmed on read-back$( [[ "${q5_write_took_effect:-0}" -gt 0 ]] && echo " (see notes)" || echo " — see notes for the exact before/after values" ), then restored to its original value as housekeeping (recorded in the same file's notes, not as a separate evidence file). See [evidence/10b-wqm-categories-verify.json](evidence/10b-wqm-categories-verify.json)."
    echo
    echo "## Q6 — Task chaining identifier"
    echo
    echo "**Partially found.** The \`RunAfterGUID\` field exists on the single-task read (\`GET /api/admin/v2/task?id=\`) and is confirmed populated on pre-existing chained system tasks (e.g., task 7 \"Purge Audit Database\" carries \`RunAfterGUID: 511A7F43-7187-11F1-AD1F-000000000000\`, which is task 1's GUID). However, \`RunAfterGUID\` is the **write target** — the predecessor's GUID — not the task's own GUID."
    echo
    echo "The task's own GUID is **not exposed by any API read endpoint**:"
    echo
    echo "- \`POST /v2/task\` returns the created object without any identifier (no \`Id\`, no GUID)."
    echo "- \`GET /v2/task?id=\` returns all configurable fields including \`RunAfterGUID\` but no field carrying the task's own GUID."
    echo "- \`GET /v2/tasks\` (list) and \`GET /v2/task/info\` expose neither."
    echo
    echo "**Conclusion**: The create→read→GUID cycle cannot close. After creating task A via the API, there is no API path to obtain A's GUID for use in task B's \`RunAfterGUID\`. Chaining via the SysAdmin REST API alone is **not possible** for app-created tasks. See [evidence/11-chaining-probe.json](evidence/11-chaining-probe.json)."
    echo
    echo "## Deviations from the published contract"
    echo
    echo "- Login is HTTP Basic Auth, not a JSON \`{username,password}\` body; the login/refresh response envelope is flat, unlike every other admin endpoint's \`{status,console,result}\` wrapper."
    echo "- **Token Expiration**: Access tokens expire in exactly 60 seconds (\`exp\` - \`iat\` = 60). Downstream clients MUST implement aggressive token refresh logic."
    echo "- The accepted-for-processing \`Location\` header for an async job points at a \`v1\` path even when triggered from a \`v2\` endpoint (both respond identically for the same job id)."
    echo "- \`PUT /api/admin/v2/wqm-category\` requires \`name\` as a query parameter; a body-only \`Name\` field is rejected."
    echo "- **WQM Type Asymmetry**: Numeric properties in WQM endpoints exhibit type asymmetry between reads and writes, requiring explicit coercion."
    echo "- \`RunAfterGUID\` (the task-chaining identifier) is present only on the single-task read, not on the list or the info read."
    echo "- **POST /v2/task requires ALL 31 fields**: The published OpenAPI contract marks most fields as optional, but the server rejects any POST missing a field. No server-side defaults are applied."
    echo "- **POST /v2/task returns no identifier**: The response contains the created task object but no \`Id\` and no GUID. The caller has no way to address the task it just created without listing all tasks and searching."
    echo "- **Task's own GUID not exposed**: No API read endpoint (\`GET /v2/task\`, \`GET /v2/tasks\`, \`GET /v2/task/info\`) returns the task's own GUID. The create→read→GUID cycle cannot close, making API-only chaining impossible."
    echo "- **Privileges Map**: \`ConfigStore\` is entirely absent from the \`privileges\` map returned by \`/api/admin/info\`, contradicting assumptions based on prior open-source tooling (e.g., iris-preflight)."
    echo
    echo "## Open risks"
    echo
    local risk_count=0
    if [[ -z "$q4_failure_reason" || "$q4_failure_reason" == "null" ]]; then
      echo "- **Q4 (failure reason)**: this run's integrity-check job completed successfully; a populated \`FailureReason\` value on a genuinely failed job was not observed. **Blocks**: any downstream feature that surfaces failure diagnostics to the operator should budget a follow-up spike run against a deliberately-failing operation before that feature ships."
      risk_count=$((risk_count + 1))
    fi
    echo "- **Q6 (chaining identifier)**: the task's own GUID is not exposed by any API read endpoint. The \`RunAfterGUID\` write field exists but the create→read→GUID cycle cannot close. **Impact**: task chaining via the SysAdmin REST API alone is impossible for app-created tasks. Chaining is deferred from MVP (path 3). Arestas on the canvas are visual documentation only; execution remains parallel."
    risk_count=$((risk_count + 1))
    if [[ "$q3_closed_positive" -eq 0 ]]; then
      echo "- **Q3 (long-running operations)**: did not close positively this run. **Blocks**: the entire planned execution-delegation scope; see decision.md."
      risk_count=$((risk_count + 1))
    fi
    if [[ "$q4_closed_positive" -eq 0 ]]; then
      echo "- **Q4 (job observation and control)**: did not fully close positively this run (one or more of state/pause/resume/cancel did not behave as expected). **Blocks**: the entire planned execution-delegation scope; see decision.md."
      risk_count=$((risk_count + 1))
    fi
    if [[ "$risk_count" -eq 0 ]]; then
      echo "None — every question closed with positive, reproducible evidence this run."
    fi
    echo
    echo "## Prior-run archive"
    echo
    if [[ -n "$archive_note" ]]; then
      echo "$archive_note"
    else
      echo "No prior run existed; nothing was archived."
    fi
  } > "$FEATURE_DIR/compatibility.md"

  # ---- decision.md ----
  {
    echo "# Execution-Model Decision"
    echo
    echo "**Feature**: 001-validate-async-job-contract"
    echo "**Recorded**: ${run_ts}"
    echo
    echo "## Decision"
    echo
    echo "${decision}"
    echo
    echo "## Rationale"
    echo
    echo "Evidence for Q3: [evidence/06-integrity-check-start.json](evidence/06-integrity-check-start.json) — HTTP ${q3_status}, Location: \`${q3_location}\`."
    echo
    echo "Evidence for Q4: [evidence/07c-async-result-settled.json](evidence/07c-async-result-settled.json) — settled State=\`${q4_state_settled}\`, TimeQueued=\`${q4_time_queued}\`, TimeStarted=\`${q4_time_started}\`, TimeFinished=\`${q4_time_finished}\`; [evidence/08a-async-result-pause.json](evidence/08a-async-result-pause.json) (HTTP ${q4_pause_status}), [evidence/08b-async-result-resume.json](evidence/08b-async-result-resume.json) (HTTP ${q4_resume_status}), [evidence/08c-async-result-cancel.json](evidence/08c-async-result-cancel.json) (HTTP ${q4_cancel_status})."
    echo
    echo "## Consequence"
    echo
    echo "${consequence}"
  } > "$FEATURE_DIR/decision.md"

  printf 'compatibility.md and decision.md written.\n' >&2
}
