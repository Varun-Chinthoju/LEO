#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIO_FILE="${1:-/tmp/leo-test.wav}"
OUTPUT_DIR="${2:-/tmp/leo-parakeet}"

if [[ ! -f "$AUDIO_FILE" ]]; then
  echo "Audio file not found: $AUDIO_FILE" >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

"$ROOT_DIR/.venv/bin/parakeet-mlx" "$AUDIO_FILE" \
  --model "${LEO_PARAKEET_MODEL:-mlx-community/parakeet-tdt_ctc-110m}" \
  --output-format txt \
  --output-dir "$OUTPUT_DIR" \
  --output-template result

echo
echo "Transcript:"
cat "$OUTPUT_DIR/result.txt"
