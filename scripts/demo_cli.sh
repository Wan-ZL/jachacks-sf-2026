#!/bin/bash
# Terminal demo of the full CareGraph story (no browser, keyless by default).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
cp "$ROOT"/*.jac "$ROOT"/*.py "$ROOT"/jac.toml "$TMP"/
cp "$ROOT"/tests/demo_cli.jac "$TMP"/
source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source ~/anaconda3/etc/profile.d/conda.sh
conda activate jachacks
cd "$TMP"
: "${CAREGRAPH_MOCK_LLM:=1}"
export CAREGRAPH_MOCK_LLM
jac run demo_cli.jac
