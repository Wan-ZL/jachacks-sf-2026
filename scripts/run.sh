#!/usr/bin/env bash
# CareGraph launcher.
#   ./scripts/run.sh        start backend (jac start, port 8000) + frontend (http.server, port 8080)
#   ./scripts/run.sh stop   kill both
#
# Ports: API = http://localhost:8000 (POST /walker/<name>), frontend = http://localhost:8080
#
# HTTPS note for the live wearable demo: Web Speech API on a PHONE requires a secure
# context (https). Two options:
#   1. Tunnel both ports:  cloudflared tunnel --url http://localhost:8080
#      plus a SECOND tunnel: cloudflared tunnel --url http://localhost:8000
#      then open  <frontend-https-url>/patient.html?api=<api-https-url>
#   2. Demo patient.html on the LAPTOP at http://localhost:8080/patient.html —
#      localhost IS a secure context, no tunnel needed.
# CORS is not an issue: jac start hardwires Access-Control-Allow-Origin: *.
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_PID=/tmp/caregraph-backend.pid
FRONTEND_PID=/tmp/caregraph-frontend.pid
BACKEND_LOG=/tmp/caregraph-backend.log
FRONTEND_LOG=/tmp/caregraph-frontend.log

stop_all() {
    for pf in "$BACKEND_PID" "$FRONTEND_PID"; do
        if [ -f "$pf" ]; then
            pid=$(cat "$pf")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                echo "stopped pid $pid ($pf)"
            fi
            rm -f "$pf"
        fi
    done
}

if [ "${1:-}" = "stop" ]; then
    stop_all
    exit 0
fi

# conda env
source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source ~/anaconda3/etc/profile.d/conda.sh
conda activate jachacks

# API key — fail loud
KEY_FILE="$HOME/Desktop/Keys/anthropic_key.txt"
if [ ! -s "$KEY_FILE" ]; then
    echo "FATAL: $KEY_FILE missing or empty — byLLM extraction needs ANTHROPIC_API_KEY" >&2
    exit 1
fi
export ANTHROPIC_API_KEY="$(cat "$KEY_FILE")"

stop_all  # idempotent restart

cd "$REPO_DIR/backend"
jac start main.jac --no_client -p 8000 > "$BACKEND_LOG" 2>&1 &
echo $! > "$BACKEND_PID"
echo "backend starting (pid $(cat $BACKEND_PID), ~10s to ready) — log: $BACKEND_LOG"

cd "$REPO_DIR/frontend"
python3 -m http.server 8080 > "$FRONTEND_LOG" 2>&1 &
echo $! > "$FRONTEND_PID"
echo "frontend serving (pid $(cat $FRONTEND_PID)) — log: $FRONTEND_LOG"

echo ""
echo "  dashboard:  http://localhost:8080/dashboard.html"
echo "  patient:    http://localhost:8080/patient.html"
echo "  doctor:     http://localhost:8080/doctor.html"
echo "  api:        http://localhost:8000  (POST /walker/<name>)"
echo ""
if command -v cloudflared >/dev/null 2>&1; then
    echo "phone demo: cloudflared tunnel --url http://localhost:8080  (+ second tunnel for 8000; see header comment)"
else
    echo "hint: cloudflared not installed (brew install cloudflared) — needed only for the phone"
    echo "      wearable demo; on the laptop, localhost is already a secure context."
fi
