# Fase 4 — Prompts avanzados con contexto de app

**Fecha:** 2026-04-21  
**Estado:** Aprobado

## Resumen

Reemplazar el único prompt fijo de `OllamaClient.rewrite` por un sistema de prompts configurables. El usuario puede elegir entre 4 presets y definir prompts propios. Cada prompt puede tener un hotkey opcional (Right ⌘ + número). El modelo recibe el nombre de la app activa como contexto.

---

## 1. Modelo de datos

### `LLMPrompt` — nuevo struct en `Sources/LocalVoice/LLM/`

```swift
struct LLMPrompt: Codable, Identifiable {
    let id: UUID
    var name: String          // nombre visible al usuario
    var instruction: String   // system prompt completo
    let isPreset: Bool        // los presets no se pueden borrar
    var keyNumber: Int?       // 1–9 → Right ⌘ + N activa este prompt
}
```

### Presets incluidos por defecto

| Nombre | Comportamiento |
|---|---|
| **Mejorar** | Polish completo: gramática, puntuación, eliminación de fillers. Output = versión más limpia del dictado. |
| **Corregir** | Intervención mínima: solo errores evidentes de transcripción (palabras mal reconocidas). No reformula. |
| **Promptear** | Convierte el dictado en un prompt óptimo para un LLM. Estructura la instrucción claramente. |
| **Formalizar** | Ajusta el tono a formal sin cambiar el contenido. Útil para emails y documentos. |

Los presets tienen `isPreset = true` y no pueden borrarse. Su `instruction` sí puede editarse.

### `PromptStore` — nuevo en `Sources/LocalVoice/LLM/PromptStore.swift`

- Carga y guarda `~/Library/Application Support/LocalVoice/prompts.json`
- Si el archivo no existe al arrancar, lo crea con los 4 presets
- Métodos principales:
  - `prompt(withKeyNumber: Int) -> LLMPrompt?`
  - `activePrompt(id: UUID?) -> LLMPrompt` (fallback a "Mejorar")
  - `add(_ prompt: LLMPrompt)`
  - `update(_ prompt: LLMPrompt)`
  - `delete(id: UUID)` — solo para no-presets

### Cambios en `AppSettings`

Nuevo campo: `activePromptID: UUID?` — el prompt pre-seleccionado para modo `.llmRewrite`. `nil` → fallback a "Mejorar".

`AppMode` no cambia. El modo `.llmRewrite` ahora siempre resuelve un `LLMPrompt` activo.

---

## 2. Pipeline de ejecución

### `OllamaClient.rewrite` — firma extendida

```swift
func rewrite(transcript: String, prompt: LLMPrompt, appContext: String?) async throws -> String
```

El prompt que se envía a Ollama combina:

```
[prompt.instruction]

[Si appContext != nil]: The user is typing in [appContext]. Preserve terminology and conventions appropriate for that context.

User's dictation: "[transcript]"

Return ONLY the rewritten text, no explanations or quotation marks.
```

### `AppDelegate.stopAndProcess()`

Antes de llamar a `ollamaClient.rewrite`, se resuelve el prompt activo:

```swift
let activePrompt: LLMPrompt
if let keyNum = sessionPromptKeyNumber,
   let byKey = promptStore.prompt(withKeyNumber: keyNum) {
    activePrompt = byKey
} else {
    activePrompt = promptStore.activePrompt(id: appSettings.activePromptID)
}
let appContext = recordingTargetApp?.name
finalText = try await ollamaClient.rewrite(
    transcript: output.text,
    prompt: activePrompt,
    appContext: appContext
)
```

### `TranscriptionRecord` — campo nuevo

`promptName: String?` — nombre del prompt usado. Se setea cuando `mode == .llmRewrite`, nil en directTranscription.

---

## 3. Hotkeys por prompt

### Mecánica

- Right ⌘ ↓ → empieza a grabar con el prompt activo por defecto (`activePromptID`)
- Mientras graba, usuario presiona `1`–`9` → sobreescribe el prompt para esta sesión
- Right ⌘ ↑ → procesa con el prompt seleccionado

Funciona igual en modo hold y modo latch.

### `HotkeyManager`

Nuevo callback: `onPromptKeyPressed: ((Int) -> Void)?`  
Nueva propiedad interna: `private var isHotkeyHeld = false`

En el CGEventTap existente, cuando llega `keyDown` mientras `isHotkeyHeld == true`:
- Si keyCode corresponde a 1–9: llama `onPromptKeyPressed(n)` y **consume el evento** (no llega a la app activa)
- Keycodes: `0x12`→1, `0x13`→2, `0x14`→3, `0x15`→4, `0x17`→5, `0x16`→6, `0x1A`→7, `0x1C`→8, `0x19`→9

### `AppDelegate`

```swift
private var sessionPromptKeyNumber: Int? = nil

hotkeyManager.onHotkeyDown = { [weak self] in
    self?.sessionPromptKeyNumber = nil
    self?.startRecording()
}
hotkeyManager.onPromptKeyPressed = { [weak self] keyNumber in
    self?.sessionPromptKeyNumber = keyNumber
}
hotkeyManager.onHotkeyUp = { [weak self] in
    self?.stopAndProcess()
}
```

---

## 4. Arquitectura abierta para el futuro

- **Per-app context rules:** el campo `appContext` en `rewrite()` ya es un `String?`. En el futuro, `PromptStore` puede tener un `[String: String]` de `bundleID → extraInstruction` que se adjunta al contexto.
- **Full settings page:** `prompts.json` puede leerse/escribirse desde cualquier UI futura sin migración de datos.
- **Nuevas herramientas (vibe coding):** el campo `instruction` de "Promptear" puede incluir contexto sobre herramientas como Cursor, Claude Code, etc. que el modelo pueda no conocer.

---

## 5. Archivos a crear o modificar

| Archivo | Cambio |
|---|---|
| `LLM/LLMPrompt.swift` | Nuevo |
| `LLM/PromptStore.swift` | Nuevo |
| `LLM/OllamaClient.swift` | Extender `rewrite()` |
| `App/AppSettings.swift` | Agregar `activePromptID` |
| `App/AppDelegate.swift` | Integrar `PromptStore`, hotkey, resolución de prompt |
| `Audio/HotkeyManager.swift` | Agregar `onPromptKeyPressed` + tracking de held state |
| `Persistence/TranscriptionRecord.swift` | Agregar `promptName` |
