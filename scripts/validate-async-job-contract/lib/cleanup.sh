#!/usr/bin/env bash
# EXIT/SIGINT/SIGTERM trap: cancels any job this script accepted that is
# still outstanding when the process is about to terminate, per
# contracts/script-cli.md "Signals". OUTSTANDING_JOB_PATH is maintained by
# probes.sh (call6_start_job / call7_poll_job / call8_transitions).

on_exit() {
  local exit_code=$?

  if [[ -n "${OUTSTANDING_JOB_PATH:-}" && -n "${ACCESS_TOKEN:-}" ]]; then
    local job_id
    job_id="$(printf '%s' "$OUTSTANDING_JOB_PATH" | sed -n 's/.*[?&]id=\([^&]*\).*/\1/p')"
    if [[ -n "$job_id" ]]; then
      log_info "Cleanup: cancelling outstanding job ${job_id} before exit."
      curl -sS -o /dev/null -X POST \
        "${IRIS_BASE_URL}/api/admin/v2/async-result/cancel?id=${job_id}" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" 2>/dev/null || true
    fi
  fi

  exit "$exit_code"
}

trap on_exit EXIT
trap 'exit 130' INT TERM
