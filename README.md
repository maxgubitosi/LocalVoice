# LocalVoice

A macOS menu bar app for local, private voice-to-text. 100% local, no cloud, no subscription.

**Your voice never leaves your machine.**

## Features

- **Hold mode**: hold Right Command (⌘) → speak → release → text appears in any app
- **Latch mode**: double-tap Right Command → speak → tap again → text appears
- **Mode 1 — Direct Transcription**: speech → Whisper → inserted instantly
- **Mode 2 — LLM Rewrite**: speech → Whisper → Ollama (Gemma4) → polished text inserted
- Powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) v0.18 (Apple Neural Engine optimized)
- Local LLM via [Ollama](https://ollama.com) — runs entirely on your Mac
- Smart text insertion: AXUIElement API (no clipboard pollution) with pasteboard fallback
- Skips password fields automatically (`AXSecureTextField`)
- Transcription history with stats and CSV export (⌘H)
- Animated floating overlay while recording

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon Mac recommended (M1/M2/M3/M4)
- [Ollama](https://ollama.com) installed and running (for Mode 2 only)

## Setup

```bash
# 1. Clone
git clone https://github.com/maxgubitosi/LocalVoice.git
cd LocalVoice

# 2. Build
swift build -c release

# 3. Run
.build/release/LocalVoice
```

### For Mode 2 (LLM Rewrite)

```bash
# Install Ollama
brew install ollama

# Pull the recommended model for your hardware
ollama pull gemma4:e2b   # M1/M2 or <16 GB RAM
ollama pull gemma4:e4b   # M3/M4 or ≥16 GB RAM

# Start the server
ollama serve
```

## Permissions

On first launch, LocalVoice will request:

| Permission | Why |
|---|---|
| **Microphone** | To capture your voice |
| **Accessibility** | To insert text into other apps via AXUIElement |
| **Input Monitoring** | To detect the global hotkey |

Go to **System Settings → Privacy & Security** to grant these. The app won't work without Accessibility and Input Monitoring.

## Hotkey

**Right Command (⌘)** — the default hotkey. Two modes available from the menu bar:

| Mode | Gesture |
|---|---|
| **Hold** | Hold to record, release to transcribe |
| **Latch** | Double-tap to start, single tap to stop |

## Whisper Models

| Model | Speed | Accuracy | RAM |
|---|---|---|---|
| tiny | ~0.1s | Good | ~75 MB |
| base | ~0.2s | Better | ~145 MB |
| small | ~0.5s | Great | ~465 MB |
| medium | ~1.5s | Excellent | ~1.5 GB |
| **large-v3-turbo** | ~2s | **Best (recommended)** | ~800 MB |
| large-v3 | ~3s | Best | ~3 GB |

Default: `large-v3-turbo` — best quality-to-speed ratio. Uses OpenAI's turbo decoder (4-layer vs 32 in large-v3) for 6× faster inference with minimal quality loss. Runs comfortably on M1 8 GB. Switch models from the menu bar or Settings.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full technical design.

## License

MIT
