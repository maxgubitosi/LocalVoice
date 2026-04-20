---
name: LocalVoice roadmap — 3-phase plan
description: Agreed priority order for LocalVoice development: UX fixes → LLM testing → local database
type: project
---

Three phases agreed on 2026-04-20:

**Phase 1 — UX improvements (current)**
Small targeted fixes to what's already built. See CLAUDE.md ## Roadmap for the task list.

**Phase 2 — LLM post-processing**
Test the already-implemented `llmRewrite` mode with Ollama + Gemma4. The pipeline exists; it just needs testing and prompt tuning.

**Why phase 2 before 3:** Low effort, high payoff — feature is already coded.

**Phase 3 — Local database + history + metrics**
SwiftData persistence, history window, metrics (WPM, frequency by app/language, etc.). Biggest scope item; deferred until phases 1-2 are solid.

**How to apply:** When the user starts a new session, check which phase is current and pick up where we left off. Update CLAUDE.md ## Roadmap checkboxes as items complete.
