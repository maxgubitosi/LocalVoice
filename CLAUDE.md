# CLAUDE.md — LocalVoice

Guide for AI agents working in this codebase.

## What This Is

macOS menu bar app for local, private voice-to-text. No cloud, no subscription. All processing runs on-device.

- **Hold mode:** hold Right Command → record, release → transcribe
- **Latch mode:** double-tap Right Command → start recording, tap → stop and transcribe
- **Mode 1 (Direct):** audio → Whisper → text inserted into the active app
- **Mode 2 (Refine):** audio → Whisper → MLX in-process (Qwen3.5) → rewritten text → inserted

## Build & Run

```bash
make build                # swift build + Metal shaders + ad-hoc codesign
make run                  # build + launch
.build/release/LocalVoice # run without rebuilding
make bundle               # create LocalVoice.app in the project root
```

`make build` runs three steps in order:
1. `swift build -c release`
2. `scripts/build-metallib.sh` — compile MLX Metal shaders → `.build/release/mlx.metallib`
3. `codesign --force --sign -` — ad-hoc sign (required for macOS to recognize the bundle ID)

**Requires full Xcode** (not just CLT) — Metal shader compilation uses `xcrun metal`. macOS 14+, Apple Silicon.

### Metal shaders

MLX requires `mlx.metallib` next to the binary. `scripts/build-metallib.sh` compiles the pre-generated shaders from mlx-swift:
```
.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal/*.metal
```
Staleness check: if the metallib exists and is newer than all `.metal` files, compilation is skipped.

## Module Structure

```
Sources/LocalVoice/
├── App/
│   ├── LocalVoiceApp.swift        # @main, NSApplication.accessory (no Dock icon)
│   ├── AppDelegate.swift          # orchestrates the full pipeline
│   ├── AppSettings.swift          # UserDefaults-backed, ObservableObject
│   ├── Config.swift               # compile-time constants
│   └── DeviceCapability.swift     # detects chip/RAM, recommends MLX model
├── Audio/
│   ├── AudioCapture.swift         # AVAudioEngine → Float32 16kHz mono
│   └── HotkeyManager.swift        # CGEventTap on Right Command key
├── Transcription/
│   └── TranscriptionEngine.swift  # WhisperKit wrapper, returns TranscriptionOutput {text, language}
├── LLM/
│   ├── MLXClient.swift            # in-process inference via MLXLLM + ChatSession
│   ├── MLXModelCatalog.swift      # curated Qwen3.5 model list with RAM/size metadata
│   ├── MLXModelManager.swift      # download, progress, deletion of MLX models
│   ├── LLMPrompt.swift            # prompt model: name, text, optional shortcut
│   └── PromptStore.swift          # persists and manages user-defined prompts
├── Persistence/
│   └── TranscriptionRecord.swift  # @Model SwiftData — local transcription history
├── TextInsertion/
│   └── TextInserter.swift         # AXUIElement (tier 1) + pasteboard (tier 2)
└── UI/
    ├── MenuBarManager.swift        # NSStatusItem + NSMenu + "Check for Updates…"
    ├── RecordingOverlayWindow.swift # animated floating SwiftUI overlay
    ├── SettingsWindow.swift        # NSWindow + SwiftUI Form (model download UI)
    ├── HistoryWindow.swift         # history window with stats and CSV export
    ├── PromptsManagementView.swift # UI for creating/editing/deleting prompts
    └── FirstRunView.swift          # first-run onboarding and model download flow
```

## Data Pipeline

```
HotkeyManager.onHotkeyDown
  → AudioCapture.startRecording()
  → RecordingOverlayWindow.show()

HotkeyManager.onHotkeyUp
  → AudioCapture.stopRecording() → [Float] (PCM 16kHz)
  → RecordingOverlayWindow.hide()
  → TranscriptionEngine.transcribe([Float]) → TranscriptionOutput
  → [if Mode 2] MLXClient.rewrite(transcript:prompt:appContext:detectedLanguage:) → String
  → TextInserter.insert(String)
```

## Default MLX Model Selection

`DeviceCapability.recommendedMLXModel` auto-selects based on chip and RAM:

| Device | Model | ~RAM required |
|---|---|---|
| M4, 32 GB+ | `mlx-community/Qwen3.5-27B-4bit` | ~16 GB |
| M3/M4, 16 GB+ | `mlx-community/Qwen3.5-9B-MLX-4bit` | ~5.5 GB |
| Any, 16 GB+ | `mlx-community/Qwen3.5-4B-MLX-4bit` | ~3 GB |
| Default (M1/M2 8 GB) | `mlx-community/Qwen3.5-2B-MLX-4bit` | ~1.5 GB |

Models download on first use of Refine mode. Stored at:
`~/Library/Application Support/LocalVoice/MLXModels/models/<org>/<model>/`

**Qwen3 no-think mode:** `/no_think` is appended to the prompt to disable chain-of-thought, significantly reducing latency for short rewrite tasks.

## MLXClient — Implementation Details

`MLXClient` uses a manual bridge (no `MLXHuggingFace` macros) because the `HuggingFace` package is incompatible with this setup:

- `HubDownloader`: implements `MLXLMCommon.Downloader` via `Hub.HubApi.snapshot()`
- `TransformersTokenizerLoader`: implements `MLXLMCommon.TokenizerLoader` via `AutoTokenizer.from(modelFolder:)`
- `TokenizerBridge`: adapts `Tokenizers.Tokenizer` → `MLXLMCommon.Tokenizer`
  - Key difference: `decode(tokenIds:)` in MLXLMCommon vs `decode(tokens:)` in Tokenizers

A new chat session is created per request (or `session.clear()` is called) to prevent context from accumulating across separate transcriptions.

## Text Insertion — Security Invariant

`TextInserter` has two tiers:

1. **AXUIElement** — direct, no clipboard. Checks `kAXSecureTextFieldRole` and **never inserts into password fields**.
2. **NSPasteboard + Cmd+V** — universal fallback. Saves and restores clipboard after 500 ms.

**Never skip the secure text field check.** This is a hard security invariant.

## Threading

- **Main thread:** UI, NSApplication, menu
- **AVAudioEngine callback:** only accumulates samples into `[Float]`, nothing else
- **`Task { }`:** transcription + MLX inference (structured concurrency)
- **`MainActor.run { }`:** all UI updates and text insertion
- **`MLXModelManager`:** `@MainActor` — updates `@Published` from async download tasks

## Conventions

- No comments unless the WHY is non-obvious
- No error handling for cases that cannot occur
- No abstractions without a concrete need
- `async/await` for all async work; callbacks only where AVAudioEngine requires it
- Files organized by functional module, not by type (no `Models/`, `Protocols/` folders)

## Hard Rules

- Never insert text into `kAXSecureTextFieldRole` (password fields)
- Never block the main thread with transcription or LLM inference
- Never add dependencies without verifying Apple Silicon native support
- Never hot-swap the Whisper model without calling `loadModel()` again
- Never use `UserDefaults` outside of `AppSettings`
- Never use the `MLXHuggingFace` package (requires the incompatible `HuggingFace` package) — use the manual bridge in `MLXClient.swift`

## Common Tasks

**Change the default Whisper model:**
Modify `AppSettings.init()` → `whisperModel` field.

**Add a new MLX model to the catalog:**
Modify `MLXModelCatalog.swift` → `models` array. Verify the actual size on HuggingFace before adding.

**Change the recommended MLX model by tier:**
Modify `DeviceCapability.recommendedMLXModel` in `DeviceCapability.swift`.

**Change the hotkey:**
`HotkeyManager.monitoredKeyCode` — current keycode is `0x36` (Right Command).

**Add a new mode (e.g. summarize):**
1. Add case to `AppMode` in `AppSettings.swift`
2. Add case in `AppDelegate.stopAndProcess()`
3. Add menu item in `MenuBarManager.buildMenu()`

**Create a signed DMG for distribution:**
```bash
./scripts/build-release.sh 1.0.0
# Requires: Developer ID cert in keychain, notarytool profile, create-dmg
```

## Distribution

The app ships as a signed + notarized DMG via GitHub Releases. No App Store.
Sparkle appcast URL is in `Info.plist` → `SUFeedURL`. `SUEnableAutomaticChecks` is `false` until a real appcast is published.

To sign with a real Developer ID:
1. Export `DEVELOPER_ID_IDENTITY` with the certificate name
2. Set up `xcrun notarytool store-credentials notarytool`
3. Run `./scripts/build-release.sh <version>`

## Roadmap

### Done
- Direct transcription (Whisper / WhisperKit, Apple Neural Engine)
- LLM rewrite mode (MLX in-process, Qwen3.5, auto-download)
- In-app model management (download, progress, deletion) for both Whisper and MLX
- Transcription history with stats and CSV export (SwiftData)
- Hold and latch hotkey modes
- User-defined prompts with shortcuts (`PromptStore`, `PromptsManagementView`)
- Sparkle auto-update integration
- Signed + notarized DMG build pipeline

### Next — Phase 5: Advanced Prompts with Context
- [ ] Per-prompt keyboard shortcuts (assignable from UI)
- [ ] Active app detection to adapt prompt to context (e.g. in Cursor: project terminology)
- [ ] App context passed to MLXClient before rewriting

### Blocked — Phase 6: Public Distribution
Blocked on Apple Developer ID ($99/year).
- [ ] Enroll in Apple Developer Program
- [ ] Publish first signed DMG to GitHub Releases
- [ ] Create `appcast.xml` and update `SUFeedURL` in `Info.plist`
- [ ] Landing page

## Additional Docs

- [ARCHITECTURE.md](ARCHITECTURE.md) — full technical design with diagrams
- [README.md](README.md) — user guide and installation
