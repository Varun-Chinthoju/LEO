# LEO voice model selection

## Decision

### Speech recognition

Use `mlx-community/parakeet-tdt_ctc-110m` through the `parakeet-mlx` Apple-Silicon runtime for the default English voice path.

Reasons:

- The 110M checkpoint is a substantially smaller English model and reduces first-use memory and load cost for short commands.
- The MLX port supports Apple Silicon and the `parakeet-mlx` CLI accepts the checkpoint directly.
- The previous 0.6B multilingual model remains available with `LEO_PARAKEET_MODEL=mlx-community/parakeet-tdt-0.6b-v3`.
- The current Swift adapter keeps the runtime injectable and fails closed when
  `parakeet-mlx` is not installed.

The adapter currently emits a final transcript after a captured utterance. True
partial/live decoding remains a follow-up because the command-line bridge starts
one transcription job per utterance; a persistent worker should be used before
claiming low-latency streaming.

### Text to speech

Use `mlx-community/Kokoro-82M-bf16` through MLX-Audio as LEO's default English TTS.

Reasons:

- 82M parameters keeps voice memory and startup cost small.
- MLX-Audio documents Kokoro as fast, multilingual, and available with 54 voices.
- The model card identifies the weights as Apache-2.0 licensed.
- It is a better fit for LEO's compact, low-latency voice responses than a 1.7B+
  voice-design model.

Default voice: `af_heart`.

Fallback evaluation candidate: `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16` when
multilingual output, voice design, or cloning becomes more important than memory
and response latency.

## Installation prerequisites

These are intentionally not run by the app at launch:

```sh
uv tool install parakeet-mlx
uv pip install --system mlx-audio
```

The Parakeet model is downloaded on first use by the runtime. Kokoro can be
selected with:

```sh
python -m mlx_audio.tts.generate \
  --model mlx-community/Kokoro-82M-bf16 \
  --text "Hello from LEO"
```

## Evidence

- [Parakeet MLX runtime](https://github.com/senstella/parakeet-mlx)
- [Parakeet TDT-CTC 110M MLX model card](https://huggingface.co/mlx-community/parakeet-tdt_ctc-110m)
- [MLX-Audio model/runtime documentation](https://github.com/Blaizzy/mlx-audio)
- [Kokoro original model card and license](https://huggingface.co/hexgrad/Kokoro-82M)
- [MLX Kokoro checkpoint](https://huggingface.co/mlx-community/Kokoro-82M-bf16)
