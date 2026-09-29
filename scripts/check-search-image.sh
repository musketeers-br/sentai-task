#!/usr/bin/env bash
# Spec 017 T026: checks that the running stack serves semantic search in-process.
#   - the compose file declares no `ollama` service;
#   - the primary container has the model library, and no GPU (nvidia-*) packages;
#   - the container runs offline (HF_HUB_OFFLINE=1, TRANSFORMERS_OFFLINE=1);
#   - the `sentai-steps` row names sentai.search.LocalEmbedding.
# Run from the repository root with the stack up. Exit 0 = all hold; 1 = at least one does not.
# Override the container with SENTAI_CONTAINER (default sentai-task-iris-1).
set -u
cd "$(dirname "$0")/.."
C=${SENTAI_CONTAINER:-sentai-task-iris-1}
bad=0
check() { if [ "$2" = "ok" ]; then echo "ok    $1"; else echo "FAIL  $1: $2"; bad=1; fi; }

if docker compose config --services 2>/dev/null | grep -qx ollama; then
  check "no ollama service in docker-compose.yml" "ollama is still declared"
else
  check "no ollama service in docker-compose.yml" ok
fi

py=$(docker exec "$C" irispython -c "import sentence_transformers, torch; print(torch.__version__, torch.version.cuda)" 2>&1 | tail -1)
case "$py" in
  *" None") check "sentence-transformers and CPU-only torch import ($py)" ok ;;
  *) check "sentence-transformers and CPU-only torch import" "$py" ;;
esac

gpu=$(docker exec "$C" sh -c 'irispython -m pip list 2>/dev/null | grep -ci "^nvidia-"' 2>/dev/null)
if [ "${gpu:-0}" = "0" ]; then check "no nvidia-* packages" ok; else check "no nvidia-* packages" "$gpu found"; fi

for v in HF_HUB_OFFLINE TRANSFORMERS_OFFLINE; do
  val=$(docker exec "$C" printenv "$v" 2>/dev/null)
  if [ "$val" = "1" ]; then check "$v=1" ok; else check "$v=1" "is '${val}'"; fi
done

row=$(docker exec -i "$C" iris session iris -U IRISAPP <<'EOF' 2>/dev/null | grep '^row=' | tr -d '\r'
set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT EmbeddingClass FROM %EMBEDDING.Config WHERE Name = 'sentai-steps'") write "row=",$s(rs.%Next():rs.EmbeddingClass,1:"(none)"),!
halt
EOF
)
if [ "$row" = "row=sentai.search.LocalEmbedding" ]; then check "sentai-steps names LocalEmbedding" ok; else check "sentai-steps names LocalEmbedding" "${row#row=}"; fi

exit $bad
