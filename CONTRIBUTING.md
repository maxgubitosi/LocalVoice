# Contributing to LocalVoice

## Build locally

**Prerequisites:**
- macOS 14 (Sonoma) or later
- Apple Silicon Mac (M1 or later recommended)
- Xcode installed (full Xcode, not just Command Line Tools — needed to compile Metal shaders)

```bash
make build   # compile + Metal shaders + ad-hoc codesign
make run     # build and launch
```

The binary lands at `.build/release/LocalVoice`.

## Report a bug

Open a [GitHub issue](https://github.com/maxgubitosi/LocalVoice/issues) and include:

- macOS version
- Chip model and RAM (e.g. M2 Pro, 16 GB)
- Steps to reproduce
- What you expected vs what happened

## Submit a change

1. Fork the repo and create a branch off `main`
2. Make your change — keep it focused on one thing
3. Open a PR against `main` describing what you changed and why
