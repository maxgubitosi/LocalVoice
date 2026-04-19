# LocalVoice

A macOS menu bar app for local, private voice-to-text — similar to Wispr Flow but 100% local and open source.

**No cloud. No subscription. Your voice stays on your machine.**

## Features

- **Hold hotkey → speak → release** → text appears in any app
- **Mode 1 — Direct Transcription**: speech → text, inserted instantly
- **Mode 2 — LLM Rewrite**: speech → Whisper → Ollama → polished text inserted
- Powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Apple Neural Engine, Apple Silicon optimized)
- Local LLM via [Ollama](https://ollama.com) — runs entirely on your Mac
- Smart text insertion: AXUIElement API (no clipboard pollution) with pasteboard fallback
- Detects and skips password fields (`AXSecureTextField`)
- Animated floating overlay while recording

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon Mac recommended (M1/M2/M3/M4)
- [Ollama](https://ollama.com) installed and running (for Mode 2)

## Setup

```bash
# 1. Clone
git clone https://github.com/yourusername/LocalVoice.git
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

# Pull a model
ollama pull llama3.2

# Start the server
ollama serve
```

## Permissions

On first launch, LocalVoice will request:

| Permission | Why |
|---|---|
| **Microphone** | To capture your voice |
| **Accessibility** | To insert text into other apps via AXUIElement |
| **Input Monitoring** | To detect the global hotkey (Right Option key) |

Go to **System Settings → Privacy & Security** to grant these.

## Default Hotkey

**Right Option (⌥) key** — hold to record, release to transcribe.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full technical design.

## Models

| Whisper Model | Speed | Accuracy | VRAM |
|---|---|---|---|
| tiny | ~0.1s | Good | ~75 MB |
| base | ~0.2s | Better | ~145 MB |
| small | ~0.5s | Great | ~465 MB |
| medium | ~1.5s | Excellent | ~1.5 GB |
| large-v3 | ~3s | Best | ~3 GB |

Default: `base` — best balance of speed and accuracy for real-time use.

## License

MIT
