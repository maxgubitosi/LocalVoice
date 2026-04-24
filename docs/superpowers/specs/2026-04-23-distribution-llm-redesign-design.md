# LocalVoice — Distribution & LLM Performance Redesign

**Date:** 2026-04-23  
**Status:** Approved for planning  
**Scope:** LLM stack migration (Ollama → MLX), in-app model management, distribution as downloadable .app

---

## Context

LocalVoice currently works well as a developer tool run from the terminal. The next milestone is making it a product end users can download and use without ever opening a terminal. Two blockers stand out:

1. **LLM latency is the main UX friction** — the Refine step with Ollama takes several seconds on M1 8GB. Ollama runs as a separate background service, doesn't use Apple's Neural Engine, and requires the user to manually pull models via CLI.

2. **No distributable artifact** — the app is a raw binary produced by `make build`. There is no `.app` bundle, no DMG, no signing with a real Developer ID, and no update mechanism.

This spec covers both problems together because they share a root cause: the Ollama dependency. Removing it in favor of MLX solves the speed problem and eliminates the hardest part of bundling (shipping and launching a separate service).

---

## Decision 1: Replace Ollama with MLX

### Why MLX

Ollama is a general-purpose inference server. It runs as a separate OS process, communicates over HTTP localhost, and doesn't use Apple's Neural Engine or GPU memory bandwidth efficiently on Apple Silicon.

MLX is Apple's framework for machine learning on Apple Silicon. It runs in-process, uses the Neural Engine and unified memory directly, and is designed specifically for the M-series chips. For the same model size, MLX is typically **2–4× faster** than Ollama on M1, and the gap grows on M2/M3/M4.

For a menu-bar app on Apple Silicon, MLX is the right primitive.

### What changes architecturally

`OllamaClient.swift` is replaced by an `MLXClient` (or similar name) that:
- Loads an MLX model from disk into memory on demand
- Runs inference in-process (no HTTP, no subprocess)
- Exposes a `generate(prompt:) async throws -> String` interface identical to today's

`AppDelegate` and the rest of the pipeline are unaffected — the interface stays the same.

The `DeviceCapability` model-recommendation logic is updated to recommend MLX model identifiers instead of Ollama model tags.

### Ollama is removed entirely

Users no longer need to install Ollama. The app ships self-contained.

---

## Decision 2: In-App Model Management (no terminal)

### Principle

Users never run a command to download a model. All model acquisition happens inside the app with a progress indicator.

### Whisper models

WhisperKit already handles downloading and caching Whisper models to `~/Library/Application Support/LocalVoice/Models/`. This stays as-is. The default model on first launch is `large-v3-turbo`.

The Settings window shows available Whisper models with their download status:
- Downloaded models: selectable immediately
- Not-yet-downloaded models: show a download button with size estimate
- Downloading: progress bar inline

### LLM models (MLX)

MLX models are stored in `~/Library/Application Support/LocalVoice/MLXModels/`. The app ships with a curated list of supported models (see Model Tiers below). On first launch, the recommended model for the user's hardware downloads automatically with a progress indicator.

The Settings window shows the model list with the same pattern as Whisper: downloaded, downloadable, downloading.

### Model list is curated, not open-ended

Unlike today's free-text Ollama model field, users pick from a fixed list of tested, supported MLX models. This prevents support issues from untested models and keeps the UX simple. Advanced users can still add custom MLX models via a separate "custom model path" field (out of scope for v1).

---

## Decision 3: Model Recommendation Tiers

`DeviceCapability.swift` already detects chip generation (M1–M4) and physical RAM. This logic is extended to recommend MLX models with explanatory labels.

### LLM model tiers

| Device | Recommended model | Label shown to user |
|---|---|---|
| M1 / M2, 8 GB | Qwen2.5-1.5B-Instruct (4-bit) | "Fast — recommended for your Mac" |
| M1 / M2, 16 GB | Qwen2.5-3B-Instruct (4-bit) | "Balanced — good quality, fast" |
| M3 / M4, 8–16 GB | Phi-3.5-mini-Instruct (4-bit) | "Balanced — recommended for your Mac" |
| M3 / M4, 16–32 GB | Gemma-3-4B-Instruct (4-bit) | "High quality — recommended for your Mac" |
| M4, 32 GB+ | Gemma4-MoE or Qwen2.5-14B-Instruct (4-bit) | "Best quality — your Mac can handle this" |

The "recommended" model is pre-selected on first launch and auto-downloaded. Other models in the list are available to download and switch to. Each model entry shows:
- Name and parameter count
- Estimated RAM usage
- Speed label (Fast / Balanced / High quality)
- Download size
- "Recommended for your Mac" badge if it matches the device tier

### Whisper model tiers

| Device | Default | Notes |
|---|---|---|
| All | `large-v3-turbo` | Best quality/speed tradeoff |
| M1 / 8 GB (low RAM warning) | suggest `small` as alternative | If user has multiple apps open |

`large-v3-turbo` is the default for everyone. Smaller models (tiny, base, small, medium) are available to download for users who want faster transcription at the cost of accuracy.

---

## Decision 4: Distribution

### Format

**Direct download DMG** — a disk image containing a drag-to-Applications installer. No App Store (the App Store sandbox breaks `AXUIElement` text insertion and the `CGEventTap` hotkey — both are core features).

### Code signing

Signed with a real Apple Developer ID (not the current ad-hoc `-` signing). This is required for Gatekeeper to allow the app on other Macs without a "damaged app" warning.

### Notarization

The DMG is notarized with Apple's notarization service. Required for macOS 15+ systems where Gatekeeper rejects non-notarized apps from unidentified developers.

### Auto-update: Sparkle

[Sparkle](https://sparkle-project.org) is the standard macOS auto-update framework. The app checks a hosted appcast XML file for new versions and presents a native update UI. Users can update with one click, no terminal required.

The appcast is hosted on GitHub Releases or a simple static server. Each release includes:
- The signed + notarized DMG
- The `appcast.xml` with version info and download URL

### Build system

The `Makefile` is committed to the repo and remains the developer build command (`make build`). A separate build script (`scripts/build-release.sh` or similar) handles the full release pipeline: `swift build -c release → codesign → create-dmg → notarize → update appcast`. End users never interact with either.

---

## First-Run Experience

On first launch, the app shows a brief setup flow (not a full wizard — just the overlay or a small modal):

1. **Microphone permission** — standard macOS prompt, already implemented
2. **Accessibility permission** — standard macOS prompt, already implemented  
3. **Downloading Whisper model** — progress bar, "Downloading transcription model (large-v3-turbo, 1.5 GB)…"
4. **Downloading LLM model** — progress bar, "Downloading AI model for Refine mode (recommended for your Mac)…"
5. **Ready** — "LocalVoice is ready. Hold Right ⌘ to start recording."

Steps 3 and 4 happen in parallel where memory allows. The app is usable for Direct Transcription mode as soon as Whisper finishes (step 3); Refine mode enables once the LLM finishes (step 4).

---

## What This Spec Does NOT Cover

- **UI/visual redesign** — the Settings, History, and overlay windows stay as-is for now. A separate design pass will happen after the core distribution work is done.
- **App Store distribution** — not viable without removing AX and CGEventTap.
- **Windows / Linux** — macOS only.
- **Custom MLX model paths** — v2 feature.
- **Cloud LLM fallback** — would break the "fully local" premise.

---

## Open Questions Before Implementation

1. **MLX Swift bindings maturity** — `mlx-swift` exists and is maintained by Apple, but needs a spike to confirm it integrates cleanly with Swift Package Manager and the existing build setup.
2. **Model download hosting** — MLX models come from Hugging Face. WhisperKit already pulls from HuggingFace via its own downloader. MLX models would need a similar downloader or we use `mlx-swift`'s built-in fetch utilities.
3. **Model storage size** — a 1.5B 4-bit model is ~1 GB. The 14B model is ~8 GB. The Settings UI needs to communicate this clearly before the user initiates a download.
4. **Sparkle hosting** — needs a GitHub repo (public or private) or a static hosting setup for the appcast XML. Decide before starting the distribution work.
