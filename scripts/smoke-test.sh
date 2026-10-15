#!/usr/bin/env bash
# smoke-test.sh — verify a running SmallThinker instance end-to-end.
#
# Checks, in order:
#   1. GET /health                     -> {"status":"ok"}
#   2. GET /v1/models                  -> model id present
#   3. POST /v1/chat/completions       -> coherent short reply
#
# Usage:
#   ./smoke-test.sh                # port from ST_PORT (default 8321)
#   ST_PORT=8322 ./smoke-test.sh

set -euo pipefail

PORT="${ST_PORT:-8321}"
BASE="http://127.0.0.1:${PORT}"
MODEL_ID="${ST_MODEL_ID:-qwen3-30b-a3b-abliterated}"

echo "==> [1/3] GET ${BASE}/health"
curl -sf --noproxy '*' --max-time 5 "${BASE}/health" | grep -q '"status":"ok"' \
    || { echo "FAIL: /health not ok"; exit 1; }
echo "    OK"

echo "==> [2/3] GET ${BASE}/v1/models (expect ${MODEL_ID})"
curl -sf --noproxy '*' --max-time 5 "${BASE}/v1/models" | grep -q "${MODEL_ID}" \
    || { echo "FAIL: model id not found in /v1/models"; exit 1; }
echo "    OK"

echo "==> [3/3] POST ${BASE}/v1/chat/completions"
curl -sf --noproxy '*' --max-time 180 "${BASE}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL_ID}\",\"messages\":[{\"role\":\"user\",\"content\":\"用一句话介绍你自己。\"}],\"max_tokens\":64,\"temperature\":0.6}" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print("    reply:", d["choices"][0]["message"]["content"][:100]); print("    usage:", d.get("usage"))'

echo "==> Smoke test passed."
