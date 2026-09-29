#!/usr/bin/env bash
# Spec 011: shared helpers for the public demo scripts (up.sh, reset.sh, status.sh).
# Needs only bash, Docker (Compose v2.24+) and curl on the host.
#
# Options every script accepts:
#   --env-file <file>   variables to load (default: .env in the repository root)
# Variables:
#   SENTAI_DEMO_SECRET  password for the platform's privileged accounts (up.sh only; never printed)
#   DEMO_HOST           DNS name for automatic HTTPS (empty: plain HTTP on DEMO_HTTP_PORT)
#   DEMO_HTTP_PORT, DEMO_HTTPS_PORT   host ports of the proxy (default 80 / 443)
#   COMPOSE_PROJECT_NAME              isolates a second demo stack (acceptance runs)

set -euo pipefail
export MSYS_NO_PATHCONV=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# The published demo account (README "Try it"). Not a secret.
DEMO_ACCOUNT="sentai-demo"
DEMO_PASSWORD="sentai-demo-2026"
# Least privilege proven by spec 011 T001 (specs/011-demo-readiness/evidence/t001-demo-role.md).
PRIMARY_RESOURCES="%DB_IRISAPP_CODE:R,%DB_IRISAPP_DATA:RW,%Admin_Manage:U,%DB_IRISSYS:RW,%Admin_Operate:U"
TARGET_RESOURCES="%DB_USER:R,%Admin_Manage:U,%DB_IRISSYS:RW,%Admin_Operate:U"

ENV_FILE=".env"
parse_common_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
			--env-file) ENV_FILE="$2"; shift 2 ;;
			*) echo "unknown option: $1" >&2; exit 64 ;;
		esac
	done
	if [ -f "$ENV_FILE" ]; then
		set -a
		# shellcheck disable=SC1090
		. "$ENV_FILE"
		set +a
	fi
}

compose() {
	docker compose -f docker-compose.yml -f docker-compose.demo.yml "$@"
}

# Container id of a compose service (empty when it does not run).
container_of() {
	compose ps -q "$1" 2>/dev/null | head -n 1
}

# Runs ObjectScript read from stdin in `namespace` of the service's IRIS (OS authentication as
# irisowner inside the container; nothing goes on a command line).
iris_session() {
	local service="$1" namespace="$2" id
	id="$(container_of "$service")"
	[ -n "$id" ] || { echo "RESULT:service $service is not running"; return 0; }
	{ cat; echo "halt"; } | docker exec -i "$id" iris session iris -U "$namespace"
}

# First "RESULT:" value in the text on stdin.
result_of() {
	grep -o 'RESULT:.*' | head -n 1 | cut -d: -f2- | tr -d '\r'
}

# Applies the demo role and account on one service (restores the published password).
apply_demo_account() {
	local service="$1" resources="$2" extra="$3"
	{ printf 'set demopw="%s"\nset resources="%s"\n%s\n' "$DEMO_PASSWORD" "$resources" "$extra"; cat scripts/demo/demo-account.script; } \
		| iris_session "$service" "%SYS" | result_of
}

health_of() {
	local id
	id="$(container_of "$1")"
	[ -n "$id" ] || { echo "not running"; return 0; }
	docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id"
}

# 0 = normal, 1 = warning, 2 = alert (IRIS monitor state).
monitor_state() {
	printf 'write "RESULT:",$SYSTEM.Monitor.State(),!\n' | iris_session "$1" "%SYS" | result_of
}

clear_alert() {
	printf 'do $SYSTEM.Monitor.Clear()\nwrite "RESULT:",$SYSTEM.Monitor.State(),!\n' | iris_session "$1" "%SYS" | result_of
}

# A lock without flock (not in Git Bash): mkdir is atomic. Waits up to 10 minutes.
take_lock() {
	local waited=0
	# After parse_common_args, so a project name from the env file isolates the lock too.
	LOCK_DIR="${TMPDIR:-/tmp}/sentai-demo-${COMPOSE_PROJECT_NAME:-sentai-task}.lock"
	until mkdir "$LOCK_DIR" 2>/dev/null; do
		[ $waited -ge 600 ] && { echo "another demo script holds $LOCK_DIR for 10 minutes; giving up" >&2; exit 75; }
		sleep 5; waited=$((waited + 5))
	done
	trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
}
