#!/usr/bin/env bash
# Spec 011 US2: starts the public demo (plan D-9). Visitors can reach nothing until the last step.
#   scripts/demo/up.sh [--env-file .env]
# Requires SENTAI_DEMO_SECRET; optional DEMO_HOST for HTTPS. Safe to run again: it rebuilds,
# re-secures and re-seeds.
. "$(dirname "$0")/lib.sh"
parse_common_args "$@"

# (1) Refuse before starting anything.
if [ -z "${SENTAI_DEMO_SECRET:-}" ]; then
	echo "SENTAI_DEMO_SECRET is not set (in $ENV_FILE or the environment): refusing to start a public demo" >&2
	echo "with the platform's default passwords. Set a long random value and run again." >&2
	exit 2
fi
take_lock

echo "== (2) building and starting IRIS (no host port is published)"
compose up -d --build --wait iris iris-target

echo "== (3) securing the privileged accounts on both instances"
for service in iris iris-target; do
	out="$({ printf 'set secret="%s"\n' "$SENTAI_DEMO_SECRET"; cat scripts/demo/secure-accounts.script; } | iris_session "$service" "%SYS")"
	echo "$out" | grep -E '^(SECURED|FAILED) ' | sed "s/^/   $service: /" || true
	[ "$(echo "$out" | result_of)" = "OK" ] || { echo "securing $service failed: $(echo "$out" | result_of)" >&2; exit 1; }
done

echo "== (4) demo account $DEMO_ACCOUNT on both instances"
r="$(apply_demo_account iris "$PRIMARY_RESOURCES" 'set sqlschema="sentai_model"')"
[ "$r" = "OK" ] || { echo "demo account on iris: $r" >&2; exit 1; }
r="$(apply_demo_account iris-target "$TARGET_RESOURCES" '')"
[ "$r" = "OK" ] || { echo "demo account on iris-target: $r" >&2; exit 1; }

echo "== (5) marking the demo, registering the target, seeding the flows"
out="$(printf 'set out=##class(sentai.demo.Demo).Setup(1)\nwrite "JSON:",out.%%ToJSON(),!\nwrite "RESULT:",$select(out.ok:"OK",1:"FAILED"),!\n' | iris_session iris IRISAPP)"
{ echo "$out" | grep -o 'JSON:.*' || true; } | cut -c6- | sed 's/^/   /'
[ "$(echo "$out" | result_of)" = "OK" ] || { echo "Demo.Setup failed" >&2; exit 1; }

echo "== (5b) sign-in hint (demo.json, public: it holds only the published demo account)"
printf '{"account":"%s","password":"%s","showcase":"%s"}\n' "$DEMO_ACCOUNT" "$DEMO_PASSWORD" "Showcase: nightly checks across servers" \
	| docker exec -i "$(container_of iris)" sh -c 'cat > /opt/sentai-web/demo.json'

echo "== (6) opening the proxy"
compose up -d caddy
site="${DEMO_HOST:-localhost:${DEMO_HTTP_PORT:-80}}"
scheme="http"; [ -n "${DEMO_HOST:-}" ] && scheme="https"
echo "Demo is up: $scheme://$site/csp/sentai/  (sign in as $DEMO_ACCOUNT / $DEMO_PASSWORD)"
