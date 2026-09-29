#!/usr/bin/env bash
# Spec 011 US4: a few lines on the demo's health (data-model §4). Exits 1 when an instance is not
# healthy, so cron can alert on it.
#   scripts/demo/status.sh [--env-file .env]
. "$(dirname "$0")/lib.sh"
parse_common_args "$@"

status=0
for service in iris iris-target caddy; do
	h="$(health_of "$service")"
	echo "$service: $h"
	case "$h" in healthy|running) ;; *) status=1 ;; esac
done
for service in iris iris-target; do
	s="$(monitor_state "$service")"
	echo "$service alert state: $s (0 normal, 1 warning, 2 alert)"
done
out="$(printf 'set st=##class(sentai.demo.Demo).Status()\nwrite "RESULT:",st.%%ToJSON(),!\n' | iris_session iris IRISAPP)"
echo "demo: $(echo "$out" | result_of)"
exit $status
