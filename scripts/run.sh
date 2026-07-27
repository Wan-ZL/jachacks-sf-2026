#!/bin/bash
# Memory Book — single-server run: Jac backend + static frontend, one port.
#   ./scripts/run.sh        start server on :8000 (walkers + assets/)
#   ./scripts/run.sh stop   stop it
# URLs: http://localhost:8000/static/dashboard.html | /patient.html
# Phone demo needs HTTPS (Web Speech secure context): use the jachammer sandbox
# deploy URL, or `cloudflared tunnel --url http://localhost:8000`
# (brew install cloudflared). On this laptop, localhost is already secure.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIDF=/tmp/caregraph-server.pid

if [ "$1" = "stop" ]; then
  [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null && rm -f "$PIDF" && echo "stopped" || echo "not running"
  exit 0
fi

source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source ~/anaconda3/etc/profile.d/conda.sh
conda activate jachacks

KEYFILE="$HOME/Desktop/Keys/anthropic_key.txt"
if [ -z "$ANTHROPIC_API_KEY" ]; then
  [ -s "$KEYFILE" ] || { echo "FATAL: no ANTHROPIC_API_KEY and $KEYFILE missing/empty"; exit 1; }
  export ANTHROPIC_API_KEY="$(cat "$KEYFILE")"
fi

cd "$ROOT"
nohup jac start main.jac --no_client -p 8000 > /tmp/caregraph-server.log 2>&1 &
echo $! > "$PIDF"
echo "server starting (log: /tmp/caregraph-server.log)"
echo "  dashboard: http://localhost:8000/static/dashboard.html"
echo "  patient:   http://localhost:8000/static/patient.html"
command -v cloudflared >/dev/null || echo "hint: brew install cloudflared for the phone HTTPS tunnel"
