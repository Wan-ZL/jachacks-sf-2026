#!/bin/bash
# Wipe graph state, restart server, load the 7-day simulated corpus.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/run.sh" stop || true
rm -rf "$ROOT/.jac"
bash "$ROOT/scripts/run.sh"
for i in $(seq 1 60); do curl -s -o /dev/null http://localhost:8000/ && break; sleep 1; done
echo "seeding (as demo user — same root the browser pages use)..."
curl -s -X POST http://localhost:8000/user/register -H 'Content-Type: application/json' \
  -d '{"identities":[{"type":"username","value":"caregraph-demo"}],"credential":{"type":"password","password":"caregraph-demo-2026"}}' > /dev/null
TOK=$(curl -s -X POST http://localhost:8000/user/login -H 'Content-Type: application/json' \
  -d '{"identity":{"type":"username","value":"caregraph-demo"},"credential":{"type":"password","password":"caregraph-demo-2026"}}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['token'])")
echo "init_patient: $(curl -s -X POST http://localhost:8000/walker/init_patient -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{"name":"Margaret"}')" | head -c 200; echo
echo "seed_load:    $(curl -s -X POST http://localhost:8000/walker/seed_load -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{}')" | head -c 200; echo
echo "=== demo reset complete === http://localhost:8000/static/dashboard.html"
