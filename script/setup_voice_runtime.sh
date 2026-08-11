#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$ROOT_DIR/.venv"
UV_CACHE_DIR="${UV_CACHE_DIR:-/private/tmp/leo-uv-cache}"

command -v uv >/dev/null || {
  echo "uv is required; install it from https://docs.astral.sh/uv/" >&2
  exit 1
}

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  UV_CACHE_DIR="$UV_CACHE_DIR" uv venv "$VENV_DIR"
fi

UV_CACHE_DIR="$UV_CACHE_DIR" uv pip install \
  --python "$VENV_DIR/bin/python" \
  parakeet-mlx mlx-audio 'misaki[en]'

# Misaki's English G2P frontend requires spaCy's small English pipeline. Keep
# VIRTUAL_ENV set because spaCy may use uv to install the model when missing.
VIRTUAL_ENV="$VENV_DIR" "$VENV_DIR/bin/python" -m spacy download en_core_web_sm

echo "Voice runtime ready at $VENV_DIR"
echo "Parakeet executable: $VENV_DIR/bin/parakeet-mlx"
echo "Kokoro model: mlx-community/Kokoro-82M-bf16 (lazy-loaded on first TTS use)"
echo "Kokoro phonemizer: misaki[en]"
