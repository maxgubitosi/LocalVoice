#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: scripts/smoke-test-refine-model.sh <model-id>" >&2
  echo "Example: scripts/smoke-test-refine-model.sh mlx-community/gemma-3-1b-it-qat-4bit" >&2
  exit 64
fi

swift run -c release MLXSmokeTest "$1"
