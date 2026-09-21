#!/usr/bin/env bash
# Entry point for the validate-async-job-contract spike.
# See specs/001-validate-async-job-contract/contracts/script-cli.md for
# the full operator contract (env vars, exit codes, filesystem effects).
set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/auth.sh
source "$LIB_DIR/auth.sh"
# shellcheck source=lib/probes.sh
source "$LIB_DIR/probes.sh"
# shellcheck source=lib/cleanup.sh
source "$LIB_DIR/cleanup.sh"
# shellcheck source=lib/report.sh
source "$LIB_DIR/report.sh"

OUTSTANDING_JOB_PATH=""
ACCESS_TOKEN=""
IMAGE_DIGEST=""

# Best-effort image digest: only attempted if the operator names the
# running container via IRIS_CONTAINER and docker is available. Never
# required — platform.image_digest is optional per
# contracts/evidence-envelope.md.
#
# IRIS_CONTAINER names a CONTAINER, not an image. Its .Image field is
# the content-addressed id of the image it was created from, already in
# the exact "sha256:<64 hex>" form contracts/evidence-envelope.md
# requires — unlike a registry RepoDigest, which is prefixed with the
# repo name ("myrepo@sha256:...") and would need stripping, and which a
# locally-built image frequently doesn't have at all. Using .Image
# directly is correct and schema-compliant for both cases.
if [[ -n "${IRIS_CONTAINER:-}" ]] && command -v docker >/dev/null 2>&1; then
  IMAGE_DIGEST="$(docker inspect --format='{{.Image}}' "${IRIS_CONTAINER}" 2>/dev/null)"
fi

preflight
archive_prior_run

if ! do_login; then
  PLATFORM_VERSION="unknown (login failed before /api/admin/info could be reached)"
  ENV1_JSON=$(patch_platform_version "$ENV1_JSON" "$PLATFORM_VERSION")
  write_envelope "01-login" "$ENV1_JSON"
  log_error "Login failed. See evidence/01-login.json."
  exit 3
fi

call0_info
ENV1_JSON=$(patch_platform_version "$ENV1_JSON" "$PLATFORM_VERSION")
write_envelope "01-login" "$ENV1_JSON"
write_envelope "00-info" "$ENV0_JSON"

do_refresh

call3_tasks_list
call4_task_single
call5_task_info

call6_start_job
call7_poll_job
call8_transitions

call9_wqm_read
call10_wqm_write_verify

call11_chaining_probe

generate_report

log_info "Spike run complete. See specs/001-validate-async-job-contract/compatibility.md and decision.md."
exit 0
