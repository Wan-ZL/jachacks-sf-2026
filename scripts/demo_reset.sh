#!/bin/bash
# Wipe graph state, restart server, load the 7-day simulated corpus.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/run.sh" stop || true
rm -rf "$ROOT/.jac"
bash "$ROOT/scripts/run.sh"
for i in $(seq 1 60); do curl -s -o /dev/null http://localhost:8000/ && break; sleep 1; done
echo "seeding..."
echo "init_patient: $(curl -s -X POST http://localhost:8000/walker/init_patient -H 'Content-Type: application/json' -d '{"name":"Margaret"}')" | head -c 200; echo
echo "seed_load:    $(curl -s -X POST http://localhost:8000/walker/seed_load -H 'Content-Type: application/json' -d '{}')" | head -c 200; echo
echo "=== demo reset complete === http://localhost:8000/dashboard.html"
