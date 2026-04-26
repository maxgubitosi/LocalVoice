# LocalVoice

A free macOS app for local, private voice-to-text. 100% local, no cloud, no APIs, no subscription.

**Your voice never leaves your machine.**

## Features

- **Hold mode**: hold Right Command (⌘) → speak → release → text appears in any app
- **Latch mode**: double-tap Right Command → speak → tap again → text appears
- **Mode 1 — Direct Transcription**: speech → Whisper → inserted instantly
- **Mode 2 — LLM Rewrite**: speech → Whisper → MLX in-process (Qwen3.5) → polished text inserted
- Powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Apple Neural Engine optimized)
- Local LLM via [mlx-swift](https://github.com/ml-explore/mlx-swift) — runs entirely on your Mac, no external server
- Smart text insertion: AXUIElement API (no clipboard pollution) with pasteboard fallback
- Skips password fields automatically (`AXSecureTextField`)
- Transcription history with stats and CSV export (⌘H)
- Animated floating overlay while recording

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon Mac (M1 or later)
- Xcode installed (required to compile Metal shaders — not just Command Line Tools)

## Setup

```bash
# 1. Clone
git clone https://github.com/maxgubitosi/LocalVoice.git
cd LocalVoice

# 2. Build
make build

# 3. Run
make run
```

Mode 1 (Direct Transcription) works immediately. Mode 2 (LLM Rewrite) will prompt you to download a Qwen3.5 model on first use — this happens inside the app, no manual steps needed.

## Permissions

On first launch, LocalVoice will request:


| Permission           | Why                                            |
| -------------------- | ---------------------------------------------- |
| **Microphone**       | To capture your voice                          |
| **Accessibility**    | To insert text into other apps via AXUIElement |
| **Input Monitoring** | To detect the global hotkey                    |


Go to **System Settings → Privacy & Security** to grant these. The app won't work without Accessibility and Input Monitoring.

## Hotkey

**Right Command (⌘)** — the default hotkey. Two modes available from the menu bar:


| Mode      | Gesture                                 |
| --------- | --------------------------------------- |
| **Hold**  | Hold to record, release to transcribe   |
| **Latch** | Double-tap to start, single tap to stop |


## Whisper Models


| Model              | Speed | Accuracy               | RAM     |
| ------------------ | ----- | ---------------------- | ------- |
| tiny               | ~0.1s | Good                   | ~75 MB  |
| base               | ~0.2s | Better                 | ~145 MB |
| small              | ~0.5s | Great                  | ~465 MB |
| medium             | ~1.5s | Excellent              | ~1.5 GB |
| **large-v3-turbo** | ~2s   | **Best (recommended)** | ~800 MB |
| large-v3           | ~3s   | Best                   | ~3 GB   |


Default: `large-v3-turbo` — best quality-to-speed ratio. Switch models from Settings.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full technical design.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT