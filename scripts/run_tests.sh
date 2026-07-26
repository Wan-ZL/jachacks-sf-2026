#!/bin/bash
# Run the Jac smoke suite in an isolated temp dir: fresh graph state, no API
# key needed (CAREGRAPH_MOCK_LLM=1 uses the deterministic byLLM fallback).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
cp "$ROOT"/*.jac "$ROOT"/*.py "$ROOT"/jac.toml "$TMP"/
cp "$ROOT"/tests/*.jac "$TMP"/
source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source ~/anaconda3/etc/profile.d/conda.sh
conda activate jachacks
cd "$TMP"
CAREGRAPH_MOCK_LLM=1 jac run smoke.jac
rm -rf .jac
CAREGRAPH_MOCK_LLM=1 jac run provenance.jac
rm -rf .jac
CAREGRAPH_MOCK_LLM=1 jac run integration.jac
