import argparse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--lang-code", default="a")
    parser.add_argument("--text", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    import numpy as np
    import soundfile as sf
    from mlx_audio.tts.utils import load_model

    model = load_model(args.model)
    generation = {
        "text": args.text,
        "voice": args.voice,
    }
    if args.model.lower().find("qwen3-tts") >= 0:
        # Qwen3-TTS calls this argument language; Kokoro calls it lang_code.
        generation["language"] = args.lang_code
    else:
        generation["lang_code"] = args.lang_code
    result = next(model.generate(**generation))
    audio = np.asarray(result.audio, dtype=np.float32).reshape(-1)
    # Compress quiet speech upward before peak normalization. Kokoro output
    # can have a low average level even when its peak is already near 1.0.
    if audio.size:
        audio = np.tanh(audio * 2.2)
    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    if peak > 0:
        # Kokoro output can be conservative in level. Normalize without
        # clipping so short responses remain intelligible at low system volume.
        audio = audio * (0.95 / peak)
    sf.write(args.output, audio, 24_000, subtype="PCM_16")


if __name__ == "__main__":
    main()
