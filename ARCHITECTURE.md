# LocalVoice — Architecture

## Overview

```
┌─────────────────────────────────────────────────────────┐
│                    macOS Menu Bar                       │
│  [waveform icon]  →  NSStatusItem  →  NSMenu            │
└─────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────┐     ┌──────────────────────────┐
│   HotkeyManager     │────▶│      AppDelegate         │
│  (CGEventTap)       │     │  (orchestrates pipeline) │
│  Right Command key  │     └──────────┬───────────────┘
└─────────────────────┘                │
                           ┌───────────▼────────────┐
                           │     AudioCapture       │
                           │  AVAudioEngine         │
                           │  Float32 / 16kHz / mono│
                           └───────────┬────────────┘
                                       │  [Float]
                           ┌───────────▼────────────┐
                           │  TranscriptionEngine   │
                           │  WhisperKit v0.18      │
                           │  Apple Neural Engine   │
                           └───────────┬────────────┘
                                       │  String
                              ┌────────┴────────┐
                              │                 │
                    ┌─────────▼──────┐  ┌───────▼────────┐
                    │  Mode 1:       │  │  Mode 2:       │
                    │  Direct insert │  │  OllamaClient  │
                    │                │  │  gemma4        │
                    └─────────┬──────┘  └───────┬────────┘
                              │                 │  rewritten text
                              └────────┬────────┘
                                       │  String
                           ┌───────────▼────────────┐
                           │     TextInserter       │
                           │  Tier 1: AXUIElement   │
                           │  Tier 2: Pasteboard+V  │
                           └────────────────────────┘
```

## Module Breakdown

### `App/`
- **`LocalVoiceApp.swift`** — `@main`, launches `NSApplication` in `.accessory` mode (no Dock icon)
- **`AppDelegate.swift`** — wires all subsystems, handles the record→transcribe→insert pipeline
- **`AppSettings.swift`** — `ObservableObject` backed by `UserDefaults`, persists mode/model choices
- **`DeviceCapability.swift`** — detects chip generation and RAM, auto-selects the recommended Gemma4 variant

### `Audio/`
- **`AudioCapture.swift`** — `AVAudioEngine` tap on input node. Converts native format → 16 kHz Float32 mono (WhisperKit requirement) via `AVAudioConverter`. Accumulates samples in a `[Float]` array during recording.
- **`HotkeyManager.swift`** — `CGEvent.tapCreate` at `.cgSessionEventTap`. Monitors `.flagsChanged` events for Right Command (kVK_RightCommand = `0x36`). Supports two hotkey modes: **hold** (press/release) and **latch** (double-tap to start, single tap to stop). Returns `nil` (consumes event) when hotkey is active so it doesn't leak to other apps.

### `Transcription/`
- **`TranscriptionEngine.swift`** — Wraps `WhisperKit`. Loads model asynchronously on startup. `transcribe(buffer:)` takes raw `[Float]` PCM, returns cleaned `String`. Supports model swapping at runtime.

### `LLM/`
- **`OllamaClient.swift`** — HTTP client for `localhost:11434`.
  - `rewrite(transcript:)` — sends crafted system prompt to clean up dictation
  - `listModels()` — queries `/api/tags` for installed models
  - `isAvailable()` — health check before attempting LLM rewrite

### `Persistence/`
- **`TranscriptionRecord.swift`** — `@Model` (SwiftData). Stores per-transcription metadata: timestamp, audio duration, word count, detected language, destination app, mode, Whisper model, Ollama model, Ollama latency, and optionally the transcribed text (opt-in, default off).

### `TextInsertion/`
- **`TextInserter.swift`** — Two-tier insertion strategy:
  1. **AXUIElement** (`kAXSelectedTextAttribute` or `kAXValueAttribute + kAXSelectedTextRangeAttribute`): Direct, precise, no clipboard side-effects. Checks `kAXSecureTextFieldRole` and skips password fields.
  2. **NSPasteboard + CGEventPost** (Cmd+V): Universal fallback. Saves and restores clipboard contents after 500ms.

### `UI/`
- **`MenuBarManager.swift`** — `NSStatusItem` with `waveform.circle` SF Symbol. Builds `NSMenu` with mode picker, hotkey mode picker, and Whisper model submenu. Animates icon while recording.
- **`RecordingOverlayWindow.swift`** — Borderless `NSWindow` at `.floating` level, bottom-right corner. SwiftUI content with pulsing red dot + animated bar chart. Shows distinct states: recording → transcribing → improving (Mode 2).
- **`SettingsWindow.swift`** — Standard `NSWindow` + SwiftUI `Form` for persistent settings, including privacy opt-in for storing transcribed text.
- **`HistoryWindow.swift`** — Transcription history browser (⌘H). Displays aggregate stats (total recordings, total words, avg WPM), a list of past records, and CSV export.

## Data Flow

```
User activates hotkey (hold or latch)
    → HotkeyManager.onHotkeyDown
    → AudioCapture.startRecording()          ← AVAudioEngine tap starts
    → RecordingOverlayWindow.show(.recording)

User releases / taps to stop
    → HotkeyManager.onHotkeyUp
    → AudioCapture.stopRecording([Float])    ← tap removed, engine stopped
    → RecordingOverlayWindow.show(.transcribing)
    → TranscriptionEngine.transcribe([Float]) → String
    → [if Mode 2] RecordingOverlayWindow.show(.improving)
    → [if Mode 2] OllamaClient.rewrite(String) → String
    → TextInserter.insert(String)
    → TranscriptionRecord saved to SwiftData
    → RecordingOverlayWindow.hide()
```

## Permissions & Entitlements

Required `Info.plist` keys:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>LocalVoice captures audio only while you hold the hotkey.</string>

<key>NSAccessibilityUsageDescription</key>
<string>LocalVoice uses Accessibility to insert transcribed text into apps.</string>

<key>NSInputMonitoringUsageDescription</key>
<string>LocalVoice monitors the Right Command key to trigger recording.</string>
```

Required sandbox entitlements (or disable sandbox for SPM CLI):
- `com.apple.security.device.audio-input`
- `com.apple.security.automation.apple-events` (for simulated Cmd+V)

## Threading Model

- **Main thread**: UI updates, `NSApplication` events, menu interactions
- **`AudioCapture` tap callback**: AVAudioEngine thread — only appends to `[Float]`
- **`Task { ... }`** (async/await): Transcription + Ollama HTTP (structured concurrency)
- **`MainActor.run { }`**: Text insertion and UI updates marshaled back to main thread

## Known Limitations & Future Work

- [ ] Xcode project / `.xcodeproj` for full App Store / notarization support
- [ ] Streaming Ollama responses (currently waits for full completion)
- [ ] Custom hotkey configuration UI (currently hardcoded to Right Command)
- [ ] Voice Activity Detection to auto-trim silence at start/end
- [ ] Multiple language support (WhisperKit supports 99 languages)
- [ ] Whisper model download UI (currently must be pre-downloaded)
