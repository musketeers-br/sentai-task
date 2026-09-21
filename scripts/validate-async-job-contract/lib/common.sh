#!/usr/bin/env bash
# Shared helpers for run-spike.sh: preflight, rerun-safety archive, the
# redacting HTTP capture path, and the envelope writer. Sourced, not
# executed directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEATURE_DIR="$(cd "$LIB_DIR/../../../specs/001-validate-async-job-contract" && pwd)"
EVIDENCE_DIR="$FEATURE_DIR/evidence"
ARCHIVE_DIR="$EVIDENCE_DIR/.archive"
REDACT_FILTER="$LIB_DIR/redact.jq"

IRIS_BASE_URL="${IRIS_BASE_URL:-http://localhost:52773}"

log_info()  { printf '%s\n' "$*" >&2; }
log_error() { printf 'ERROR: %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
preflight() {
  local missing=0

  if ! command -v curl >/dev/null 2>&1; then
    log_error "curl is required but was not found on \$PATH. Install curl and retry."
    missing=1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq (>=1.6) is required but was not found on \$PATH. Install jq and retry."
    missing=1
  fi
  if [[ "$missing" -eq 1 ]]; then
    exit 2
  fi

  if [[ -z "${IRIS_USER:-}" || -z "${IRIS_PASSWORD:-}" ]]; then
    log_error "IRIS_USER and IRIS_PASSWORD must both be set in the environment. Neither is read from a file or CLI argument."
    exit 2
  fi

  local probe_status
  probe_status=$(curl -sS -o /dev/null -w '%{http_code}' "${IRIS_BASE_URL}/api/" 2>/dev/null) || probe_status=""
  if [[ -z "$probe_status" || "$probe_status" == "000" ]]; then
    log_error "Could not reach ${IRIS_BASE_URL}/api/. Is the IRIS container running and is IRIS_BASE_URL correct?"
    exit 2
  fi
  log_info "Preflight OK: curl and jq present, IRIS_USER/IRIS_PASSWORD set, ${IRIS_BASE_URL}/api/ routable (HTTP ${probe_status})."
}

# ---------------------------------------------------------------------------
# Rerun safety: archive any prior evidence + compat/decision docs before
# writing anything new.
# ---------------------------------------------------------------------------
archive_prior_run() {
  local has_evidence=0 has_compat=0 has_decision=0
  [[ -d "$EVIDENCE_DIR" ]] && find "$EVIDENCE_DIR" -maxdepth 1 -name '*.json' -print -quit | grep -q . && has_evidence=1
  [[ -f "$FEATURE_DIR/compatibility.md" ]] && has_compat=1
  [[ -f "$FEATURE_DIR/decision.md" ]] && has_decision=1

  if [[ "$has_evidence" -eq 0 && "$has_compat" -eq 0 && "$has_decision" -eq 0 ]]; then
    ARCHIVED_TO=""
    return 0
  fi

  local ts
  ts="$(date -u +%Y%m%d-%H%M%SZ)"
  local dest="$ARCHIVE_DIR/$ts"
  if ! mkdir -p "$dest/evidence" 2>/dev/null; then
    log_error "Rerun-safety failure: could not create archive directory $dest."
    exit 5
  fi

  if [[ "$has_evidence" -eq 1 ]]; then
    find "$EVIDENCE_DIR" -maxdepth 1 -name '*.json' -exec mv {} "$dest/evidence/" \; || {
      log_error "Rerun-safety failure: could not archive prior evidence files."
      exit 5
    }
  fi
  [[ "$has_compat" -eq 1 ]] && mv "$FEATURE_DIR/compatibility.md" "$dest/compatibility.md"
  [[ "$has_decision" -eq 1 ]] && mv "$FEATURE_DIR/decision.md" "$dest/decision.md"

  log_info "Archived prior run to evidence/.archive/${ts}/"
  ARCHIVED_TO="evidence/.archive/${ts}/"
}

# ---------------------------------------------------------------------------
# Redacting HTTP capture.
#
# capture_http METHOD PATH REQ_HEADERS_JSON REQ_QUERY_JSON REQ_BODY_JSON [curl-opt...]
#
# REQ_HEADERS_JSON: the request headers to RECORD in the envelope (already
#   redacted by the caller — this function never inspects real secret
#   values, it only ever writes literal "<REDACTED>" for header names the
#   caller marks as sensitive).
# REQ_QUERY_JSON: flat object of query params to record (also used to
#   build the actual URL query string).
# REQ_BODY_JSON: the JSON body actually sent, or "" for none. Recorded in
#   the envelope after being passed through the redaction filter (so a
#   real secret sent in a request body, like a refresh token, is
#   redacted on disk without our needing to special-case it).
# Remaining args are extra curl options (e.g. -u user:pass, -H "Authorization: ...").
#
# On success, sets the following globals (consumed by write_envelope):
#   CAP_STATUS, CAP_RESPONSE_HEADERS_JSON, CAP_RESPONSE_BODY_JSON,
#   CAP_REQUEST_JSON, CAP_LOCATION_HEADER (raw, unredacted — never secret)
# ---------------------------------------------------------------------------
capture_http() {
  local method="$1" path="$2" req_headers_json="$3" req_query_json="$4" req_body_json="$5"
  shift 5
  local extra_curl_args=("$@")

  local url="${IRIS_BASE_URL}${path}"
  local curl_args=(-sS -i -X "$method")
  if [[ -n "$req_body_json" ]]; then
    curl_args+=(-H "Content-Type: application/json" --data "$req_body_json")
  fi
  curl_args+=("${extra_curl_args[@]}")

  local raw
  raw="$(curl "${curl_args[@]}" "$url" 2>/dev/null)"
  local curl_exit=$?

  if [[ "$curl_exit" -ne 0 ]]; then
    CAP_STATUS=0
    CAP_RESPONSE_HEADERS_JSON="{}"
    CAP_RESPONSE_BODY_JSON="null"
    CAP_LOCATION_HEADER=""
    CAP_REQUEST_JSON=$(build_request_json "$method" "$path" "$req_headers_json" "$req_query_json" "$req_body_json")
    return 1
  fi

  local normalized
  normalized="$(printf '%s' "$raw" | tr -d '\r')"

  # head -n1 / awk's early `exit` below can close their stdin pipe before
  # printf finishes feeding a large body (e.g. a verbose job Console
  # array), causing a harmless SIGPIPE on printf; 2>/dev/null suppresses
  # that specific write-error message without discarding output already
  # captured via command substitution.
  CAP_STATUS="$(printf '%s\n' "$normalized" 2>/dev/null | head -n1 | awk '{print $2}')"
  [[ "$CAP_STATUS" =~ ^[0-9]+$ ]] || CAP_STATUS=0

  local headers_block
  headers_block="$(printf '%s\n' "$normalized" 2>/dev/null | awk 'NR==1{next} $0==""{exit} {print}')"

  local body
  body="$(printf '%s\n' "$normalized" | awk 'f{print} $0==""{f=1}')"

  # awk's early `exit` can close its stdin pipe before printf finishes
  # feeding it, causing a harmless SIGPIPE on printf; suppress that
  # specific write-error message without discarding the extracted value.
  CAP_LOCATION_HEADER="$(printf '%s\n' "$headers_block" 2>/dev/null | awk -F': ' '{ if (tolower($1)=="location") { sub(/^[^:]*: /,""); print; exit } }')"

  CAP_RESPONSE_HEADERS_JSON="$(printf '%s\n' "$headers_block" | jq -R -s '
    split("\n") | map(select(length>0)) |
    map(capture("^(?<k>[^:]+):[ ]?(?<v>.*)$")? // {k:"?",v:""}) |
    map(
      if (.k | ascii_downcase) as $k
         | ($k == "set-cookie" or $k == "authorization" or ($k | test("^x-.*-token$")))
      then {(.k): "<REDACTED>"}
      else {(.k): .v}
      end
    ) |
    (reduce .[] as $o ({}; . + $o))
  ')"

  # CAP_RAW_RESPONSE_BODY is the UNREDACTED body, kept only in this
  # in-memory variable so a caller that must chain a secret forward
  # (e.g. extracting a fresh access_token to authorize the next call)
  # can do so without ever writing the unredacted value to disk. Only
  # CAP_RESPONSE_BODY_JSON (redacted) is ever passed to write_envelope.
  CAP_RAW_RESPONSE_BODY="$body"

  if [[ -n "$body" ]] && printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
    CAP_RESPONSE_BODY_JSON="$(printf '%s' "$body" | jq -f "$REDACT_FILTER")"
  elif [[ -n "$body" ]]; then
    CAP_RESPONSE_BODY_JSON="$(printf '%s' "$body" | jq -Rs '.')"
  else
    CAP_RESPONSE_BODY_JSON="null"
  fi

  CAP_REQUEST_JSON=$(build_request_json "$method" "$path" "$req_headers_json" "$req_query_json" "$req_body_json")
  return 0
}

build_request_json() {
  local method="$1" path="$2" req_headers_json="$3" req_query_json="$4" req_body_json="$5"
  local body_field
  if [[ "$method" == "GET" || "$method" == "HEAD" || -z "$req_body_json" ]]; then
    body_field="null"
  else
    body_field="$(printf '%s' "$req_body_json" | jq -f "$REDACT_FILTER")"
  fi
  jq -n \
    --arg method "$method" \
    --arg url_path "$path" \
    --argjson headers "$req_headers_json" \
    --argjson query "$req_query_json" \
    --argjson body "$body_field" \
    '{method: $method, url_path: $url_path, query: $query, headers: $headers, body: $body}'
}

# ---------------------------------------------------------------------------
# Envelope assembly + write-once file write.
#
# build_envelope CALL_ID
# Uses CAP_REQUEST_JSON, CAP_STATUS, CAP_RESPONSE_HEADERS_JSON,
# CAP_RESPONSE_BODY_JSON (set by capture_http) plus $PLATFORM_VERSION and
# $IMAGE_DIGEST (globals, may be empty before Call 0 resolves them — the
# caller is responsible for patching platform.version in with
# patch_platform_version before writing to disk for calls captured prior
# to Call 0).
# ---------------------------------------------------------------------------
build_envelope() {
  local call_id="$1"
  shift
  local notes_json="${1:-[]}"

  local platform_json
  if [[ -n "${IMAGE_DIGEST:-}" ]]; then
    platform_json=$(jq -n --arg v "${PLATFORM_VERSION:-}" --arg d "$IMAGE_DIGEST" '{version:$v, image_digest:$d}')
  else
    platform_json=$(jq -n --arg v "${PLATFORM_VERSION:-}" '{version:$v}')
  fi

  jq -n \
    --arg call_id "$call_id" \
    --arg captured_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson platform "$platform_json" \
    --argjson request "$CAP_REQUEST_JSON" \
    --argjson status "$CAP_STATUS" \
    --argjson response_headers "$CAP_RESPONSE_HEADERS_JSON" \
    --argjson response_body "$CAP_RESPONSE_BODY_JSON" \
    --argjson notes "$notes_json" \
    '{
      call_id: $call_id,
      captured_at: $captured_at,
      platform: $platform,
      request: $request,
      response: { status: $status, headers: $response_headers, body: $response_body },
      notes: $notes
    }'
}

patch_platform_version() {
  local envelope_json="$1" version="$2"
  printf '%s' "$envelope_json" | jq --arg v "$version" '.platform.version = $v'
}

write_envelope() {
  local call_id="$1" envelope_json="$2"
  mkdir -p "$EVIDENCE_DIR"
  local dest="$EVIDENCE_DIR/${call_id}.json"
  printf '%s\n' "$envelope_json" | jq '.' > "$dest"
  local status
  status=$(printf '%s' "$envelope_json" | jq -r '.response.status')
  printf '%s %s %s\n' "$call_id" "$status" "specs/001-validate-async-job-contract/evidence/${call_id}.json"
}

redacted_headers() {
  # redacted_headers KEY1 KEY2 ... -> {"KEY1":"<REDACTED>", ...} for headers
  # we deliberately never place a real secret into.
  local json="{}"
  for k in "$@"; do
    json=$(printf '%s' "$json" | jq --arg k "$k" '. + {($k): "<REDACTED>"}')
  done
  printf '%s' "$json"
}
