#!/usr/bin/env bash
# Call 1 (login) and Call 2 (refresh). Login uses HTTP Basic Auth against
# /api/admin/login (discovered at run time — the published contract does
# not document the request shape); this deviates from the plan's original
# assumption of a JSON {username,password} body, and is recorded as such
# in compatibility.md.
#
# Sets globals: ACCESS_TOKEN, REFRESH_TOKEN (never printed, never written
# to disk — extracted from CAP_RAW_RESPONSE_BODY, the in-memory-only
# unredacted body capture_http exposes for exactly this purpose).
# Returns envelopes via ENV1_JSON / ENV2_JSON (already redacted, built but
# not yet written — Call 1's file is written after Call 0 resolves
# PLATFORM_VERSION so both 00-info and 01-login land with a correct,
# complete platform.version; see run-spike.sh).

do_login() {
  capture_http "POST" "/api/admin/login" \
    "$(redacted_headers Authorization)" "{}" "{}" \
    -u "${IRIS_USER}:${IRIS_PASSWORD}"
  local ok=$?

  local notes="[]"
  if [[ "$ok" -eq 0 ]] && printf '%s' "$CAP_RAW_RESPONSE_BODY" | jq -e . >/dev/null 2>&1; then
    ACCESS_TOKEN="$(printf '%s' "$CAP_RAW_RESPONSE_BODY" | jq -r '.access_token // empty')"
    REFRESH_TOKEN="$(printf '%s' "$CAP_RAW_RESPONSE_BODY" | jq -r '.refresh_token // empty')"
    if [[ -z "$ACCESS_TOKEN" ]]; then
      notes='["login response did not contain an access_token field; see response.body for the actual shape returned"]'
    fi
  else
    ACCESS_TOKEN=""
    REFRESH_TOKEN=""
    notes='["login request did not return a parseable response"]'
  fi

  ENV1_JSON=$(build_envelope "01-login" "$notes")
  [[ -n "$ACCESS_TOKEN" ]]
}

do_refresh() {
  local req_body
  req_body=$(jq -n --arg rt "$REFRESH_TOKEN" '{refresh_token: $rt}')

  capture_http "POST" "/api/admin/refresh" \
    "$(redacted_headers Authorization)" "{}" "$req_body" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}"
  local ok=$?

  local notes="[]"
  if [[ "$ok" -eq 0 ]] && printf '%s' "$CAP_RAW_RESPONSE_BODY" | jq -e . >/dev/null 2>&1; then
    local new_access new_refresh
    new_access="$(printf '%s' "$CAP_RAW_RESPONSE_BODY" | jq -r '.access_token // empty')"
    new_refresh="$(printf '%s' "$CAP_RAW_RESPONSE_BODY" | jq -r '.refresh_token // empty')"
    if [[ -n "$new_access" ]]; then
      ACCESS_TOKEN="$new_access"
      [[ -n "$new_refresh" ]] && REFRESH_TOKEN="$new_refresh"
    else
      notes='["refresh response did not contain an access_token field; continuing with the pre-refresh session token"]'
    fi
  else
    notes='["refresh request did not return a parseable response; continuing with the pre-refresh session token"]'
  fi

  ENV2_JSON=$(build_envelope "02-refresh" "$notes")
  write_envelope "02-refresh" "$ENV2_JSON"
}

# Internal session-keepalive: the platform's access tokens are
# short-lived (observed ~60s TTL). Calls 7/8/9/10 can run well past that
# during a long poll, so the script refreshes silently in the background
# to stay authenticated. This performs the SAME request as Call 2 but is
# not itself an evidence-producing probe (Call 2's envelope already
# answers spec Q1's renewal question) — it writes no file, per
# Constitution Principle II: it is not a new capability, just the
# ordinary use of the one already demonstrated and captured in
# evidence/02-refresh.json.
keepalive_refresh() {
  local req_body
  req_body=$(jq -n --arg rt "$REFRESH_TOKEN" '{refresh_token: $rt}')
  local raw
  raw="$(curl -sS -X POST "${IRIS_BASE_URL}/api/admin/refresh" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" --data "$req_body" 2>/dev/null)"
  if printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
    local new_access new_refresh
    new_access="$(printf '%s' "$raw" | jq -r '.access_token // empty')"
    new_refresh="$(printf '%s' "$raw" | jq -r '.refresh_token // empty')"
    [[ -n "$new_access" ]] && ACCESS_TOKEN="$new_access"
    [[ -n "$new_refresh" ]] && REFRESH_TOKEN="$new_refresh"
  fi
}
