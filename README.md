# LocalVoice

A free macOS app for local, private voice-to-text. 100% local, no cloud, no APIs, no subscription.

**Your voice never leaves your machine.**

## Features

- **Hold mode**: hold your recording hotkey → speak → release → text appears in any app
- **Latch mode**: double-tap your recording hotkey → speak → tap again → text appears
- **Mode 1 — Direct Transcription**: speech → Whisper → inserted instantly
- **Mode 2 — Refine**: speech → Whisper → local MLX text model → polished text inserted
- Powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Apple Neural Engine optimized)
- Local LLM via [mlx-swift](https://github.com/ml-explore/mlx-swift) — runs entirely on your Mac, no external server
- Smart text insertion: AXUIElement API first, Unicode keyboard events fallback, no clipboard pollution
- Skips password fields automatically (`AXSecureTextField`)
- Transcription history with stats and CSV export (⌘H)
- Optional active browser page context for Refine and local history, with sanitized URLs
- Animated floating overlay while recording

## Download

**[Download the public beta ZIP (`LocalVoice.zip`) →](https://github.com/maxgubitosi/LocalVoice/releases/latest/download/LocalVoice.zip)** (or browse all [releases](https://github.com/maxgubitosi/LocalVoice/releases))

### First launch (one-time setup)

The current public beta is signed ad-hoc, not with a paid Apple Developer ID. macOS quarantines downloaded ad-hoc apps, so clear that flag **before** opening LocalVoice. Otherwise macOS may run it from a randomized translocated path and your Input Monitoring / Accessibility grants may not stick.

1. Unzip `LocalVoice.zip`.
2. Drag `LocalVoice.app` into `/Applications`.
3. Open **Terminal** and run:
  ```bash
   xattr -dr com.apple.quarantine /Applications/LocalVoice.app
  ```
4. Open the app. In **System Settings → Privacy & Security**, enable **Microphone**, **Accessibility**, and **Input Monitoring** for LocalVoice.

> **Already opened it before step 3?** Remove the existing `LocalVoice` entries from *Input Monitoring* and *Accessibility* in System Settings, run the `xattr` command, then relaunch and grant the permissions again.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon Mac (M1 or later)

## Building from source

Requires full Xcode (not just Command Line Tools) — Metal shader compilation uses `xcrun metal`.

```bash
# 1. Clone
git clone https://github.com/maxgubitosi/LocalVoice.git
cd LocalVoice

# 2. Build and run
make run
```

To build a distributable zip:

```bash
make release-zip   # produces LocalVoice.zip, ready to upload to GitHub Releases
```

Beta ZIP builds are ad-hoc signed, so they still require the quarantine step above. A Developer ID notarized DMG is coming soon; until then, use the ZIP flow.

Mode 1 (Direct Transcription) works immediately. Mode 2 (Refine) will prompt you to download a local text model on first use — this happens inside the app, no manual steps needed.

## Permissions

On first launch, LocalVoice will request:


| Permission           | Why                                            |
| -------------------- | ---------------------------------------------- |
| **Microphone**       | To capture your voice                          |
| **Accessibility**    | To insert text into other apps via AXUIElement |
| **Input Monitoring** | To detect the global hotkey                    |


Go to **System Settings → Privacy & Security** to grant these. The app won't work without Accessibility and Input Monitoring.

## Language tip

If you dictate in Spanish, set **Language → Spanish** instead of Auto. Auto can misdetect short Spanish clips, and Refine may then respond in English.

## Privacy

LocalVoice does not use cloud transcription, API keys, or a remote LLM. Audio, transcripts, prompts, model inference, and history stay on your Mac.

When **Include active browser page context** is enabled in Settings, LocalVoice may read the active browser page title and URL to improve Refine mode and include that metadata in local history/CSV export. URLs are stored without query strings or fragments, and you can turn this off at any time.

## Hotkey

**Right Command (⌘)** is the default recording hotkey. You can switch it to Fn, Right Option, or Right Control in Settings. Two recording gestures are available:


| Mode      | Gesture                                 |
| --------- | --------------------------------------- |
| **Hold**  | Hold to record, release to transcribe   |
| **Latch** | Double-tap to start, single tap to stop |


## Whisper Models

Direct transcription usually completes in a few seconds. Refine mode adds local LLM processing time depending on your Mac and selected text model. Use History export or `scripts/benchmark-localvoice.sh` to base public numbers on measurements from a real machine.


| Model              | Accuracy profile                     |
| ------------------ | ------------------------------------ |
| tiny               | Fastest, lower accuracy              |
| base               | Very fast, decent accuracy           |
| small              | Fast, good accuracy                  |
| medium             | Balanced, great accuracy             |
| **large-v3-turbo** | Recommended: best quality-to-speed   |
| large-v3           | Highest accuracy, larger local model |


Default: `large-v3-turbo` — best quality-to-speed ratio. Switch models from Settings.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full technical design.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
