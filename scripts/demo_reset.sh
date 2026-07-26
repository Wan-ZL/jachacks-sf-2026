#!/usr/bin/env bash
# Reset the CareGraph demo: stop backend, wipe graph state, restart, reseed.
# Usage: ./scripts/demo_reset.sh
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_PID=/tmp/caregraph-backend.pid
BACKEND_LOG=/tmp/caregraph-backend.log

# stop backend if running
if [ -f "$BACKEND_PID" ]; then
    pid=$(cat "$BACKEND_PID")
    kill "$pid" 2>/dev/null && echo "stopped backend pid $pid" || true
    rm -f "$BACKEND_PID"
    sleep 1
fi

# fresh graph — persistence lives in backend/.jac (env-verified.md)
rm -rf "$REPO_DIR/backend/.jac"
echo "wiped backend/.jac"

source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source ~/anaconda3/etc/profile.d/conda.sh
conda activate jachacks

KEY_FILE="$HOME/Desktop/Keys/anthropic_key.txt"
if [ ! -s "$KEY_FILE" ]; then
    echo "FATAL: $KEY_FILE missing or empty" >&2
    exit 1
fi
export ANTHROPIC_API_KEY="$(cat "$KEY_FILE")"

cd "$REPO_DIR/backend"
jac start main.jac --no_client -p 8000 > "$BACKEND_LOG" 2>&1 &
echo $! > "$BACKEND_PID"
echo "backend restarting (pid $(cat $BACKEND_PID)) — log: $BACKEND_LOG"

# wait for port (jac start takes ~10s)
for i in $(seq 1 60); do
    if curl -s -o /dev/null http://localhost:8000/walker/init_patient -X POST \
         -H 'Content-Type: application/json' -d '{"name":"Margaret"}'; then
        break
    fi
    sleep 1
    if [ "$i" = 60 ]; then echo "FATAL: backend never came up — see $BACKEND_LOG" >&2; exit 1; fi
done

echo "seeding..."
init_resp=$(curl -s -X POST http://localhost:8000/walker/init_patient \
    -H 'Content-Type: application/json' -d '{"name":"Margaret"}')
seed_resp=$(curl -s -X POST http://localhost:8000/walker/seed_load \
    -H 'Content-Type: application/json' -d '{}')

echo ""
echo "=== demo reset complete ==="
echo "init_patient: $init_resp"
echo "seed_load:    $seed_resp"
echo "api: http://localhost:8000 | dashboard: http://localhost:8080/dashboard.html"
