#!/usr/bin/env bash
# Spec 011 US4: returns the demo to its initial state (plan D-14). Run it daily from cron, or by hand.
#   scripts/demo/reset.sh [--env-file .env]
# Removes visitor flows and their runs, re-seeds the example and showcase, keeps the target
# registered and online, restores the demo account's published password, and clears the IRIS
# alert state on both instances. Exits non-zero when anything failed (for example the target is
# down), after doing everything it could.
. "$(dirname "$0")/lib.sh"
parse_common_args "$@"
take_lock

status=0
echo "== $(date -u '+%Y-%m-%d %H:%M:%S') UTC demo reset"

out="$(printf 'set out=##class(sentai.demo.Demo).Reset()\nwrite "JSON:",out.%%ToJSON(),!\nwrite "RESULT:",$select(out.ok:"OK",1:"FAILED"),!\n' | iris_session iris IRISAPP)"
{ echo "$out" | grep -o 'JSON:.*' || true; } | cut -c6- | sed 's/^/   /'
r="$(echo "$out" | result_of)"
echo "   product data: $r"
[ "$r" = "OK" ] || status=1

r="$(apply_demo_account iris "$PRIMARY_RESOURCES" 'set sqlschema="sentai_model"')"
echo "   demo account on iris: $r"; [ "$r" = "OK" ] || status=1
r="$(apply_demo_account iris-target "$TARGET_RESOURCES" '')"
echo "   demo account on iris-target: $r"; [ "$r" = "OK" ] || status=1

# The only place the alert state is ever cleared (FR-020): an explicit host action.
for service in iris iris-target; do
	r="$(clear_alert "$service")"
	echo "   alert state on $service after clearing: $r"
	[ "$r" = "0" ] || status=1
done

echo "== reset $([ $status -eq 0 ] && echo ok || echo 'finished with problems')"
exit $status
