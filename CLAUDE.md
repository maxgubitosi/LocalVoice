# CLAUDE.md — LocalVoice

Guía para agentes de IA que trabajen en este codebase.

## Qué es esto

App de menu bar para macOS que convierte voz a texto de forma completamente local.
Sin cloud, sin suscripción. Todo el procesamiento corre localmente en el Mac.

- **Hotkey modo hold:** mantener Right Command (⌘ derecho) → graba, soltar → transcribe
- **Hotkey modo latch:** doble-tap Right Command → empieza a grabar, tap → para y transcribe
- **Modo 1:** audio → Whisper → texto insertado en la app activa
- **Modo 2:** audio → Whisper → Ollama (gemma4) → texto reescrito → insertado

## Cómo buildear

```bash
swift build                    # debug
swift build -c release         # release
.build/release/LocalVoice      # correr
```

Requiere CLT o Xcode instalado. macOS 14+ (Sonoma). Apple Silicon recomendado.

## Estructura de módulos

```
Sources/LocalVoice/
├── App/
│   ├── LocalVoiceApp.swift       # @main, NSApplication.accessory (sin Dock icon)
│   ├── AppDelegate.swift         # orquesta el pipeline completo
│   ├── AppSettings.swift         # UserDefaults-backed, ObservableObject
│   └── DeviceCapability.swift    # detecta chip/RAM, recomienda modelo Ollama
├── Audio/
│   ├── AudioCapture.swift        # AVAudioEngine → Float32 16kHz mono
│   └── HotkeyManager.swift       # CGEventTap en Right Option key
├── Transcription/
│   └── TranscriptionEngine.swift # wrapper WhisperKit, retorna TranscriptionOutput {text, language}
├── LLM/
│   └── OllamaClient.swift        # HTTP client localhost:11434
├── Persistence/
│   └── TranscriptionRecord.swift # @Model SwiftData — historial local
├── TextInsertion/
│   └── TextInserter.swift        # AXUIElement (tier 1) + pasteboard (tier 2)
└── UI/
    ├── MenuBarManager.swift       # NSStatusItem + NSMenu
    ├── RecordingOverlayWindow.swift # overlay flotante SwiftUI animado
    ├── SettingsWindow.swift       # NSWindow + SwiftUI Form
    └── HistoryWindow.swift        # ventana historial con stats y export CSV
```

## Pipeline de datos

```
HotkeyManager.onHotkeyDown
  → AudioCapture.startRecording()
  → RecordingOverlayWindow.show()

HotkeyManager.onHotkeyUp
  → AudioCapture.stopRecording() → [Float] (PCM 16kHz)
  → RecordingOverlayWindow.hide()
  → TranscriptionEngine.transcribe([Float]) → String
  → [si Modo 2] OllamaClient.rewrite(String) → String
  → TextInserter.insert(String)
```

## Modelo Ollama por defecto

`DeviceCapability.recommendedGemmaModel` elige automáticamente:

| Dispositivo | Modelo | Por qué |
|---|---|---|
| M1/M2 o <16GB RAM | `gemma4:e2b` | Más rápido, menor consumo |
| M3/M4 o ≥16GB RAM | `gemma4:e4b` | Mejor calidad, el hardware lo aguanta |

Para instalar: `ollama pull gemma4:e2b` o `ollama pull gemma4:e4b`

## Inserción de texto — reglas importantes

`TextInserter` tiene dos tiers:

1. **AXUIElement** — directo, sin tocar el clipboard. Verifica `kAXSecureTextFieldRole` y **no inserta en campos de contraseña**.
2. **NSPasteboard + Cmd+V** — fallback universal. Guarda y restaura el clipboard después de 500ms.

**Nunca saltear la verificación de secure text field.** Es un invariante de seguridad.

## Threading

- **Main thread:** UI, NSApplication, menú
- **AVAudioEngine callback:** solo acumula samples en `[Float]`, nada más
- **Task { }:** transcripción + HTTP Ollama (structured concurrency)
- **MainActor.run { }:** toda actualización de UI o inserción de texto

## Permisos requeridos

- `NSMicrophoneUsageDescription` — grabar audio
- `NSAccessibilityUsageDescription` — insertar texto vía AX
- `NSInputMonitoringUsageDescription` — detectar hotkey global

## Convenciones

- Sin comentarios salvo que el WHY sea no obvio
- No agregar manejo de errores para casos que no pueden ocurrir
- No introducir abstracciones sin necesidad concreta
- `async/await` para todo lo asíncrono, no callbacks salvo AVAudioEngine
- Archivos por módulo funcional, no por tipo (no carpeta `Models/`, `Protocols/`, etc.)

## Lo que NO hacer

- No insertar texto en `kAXSecureTextFieldRole` (campos de contraseña)
- No bloquear el main thread con transcripción o HTTP
- No agregar dependencias sin revisar si Apple Silicon las soporta nativamente
- No cambiar el modelo de Whisper en caliente sin llamar `loadModel()` de nuevo
- No usar `UserDefaults` fuera de `AppSettings`

## Tareas comunes

**Cambiar el modelo Whisper por defecto:**
Modificar `AppSettings.init()` → campo `whisperModel`.

**Agregar un nuevo modelo Ollama recomendado:**
Modificar `DeviceCapability.swift` → `recommendedGemmaModel` y la tabla de `shouldUseHeavierModel`.

**Cambiar el hotkey:**
`HotkeyManager.monitoredKeyCode` — el keycode actual es `0x36` (Right Command).

**Agregar un modo nuevo (ej. resumen):**
1. Agregar case a `AppMode` en `AppSettings.swift`
2. Agregar case en `AppDelegate.stopAndProcess()`
3. Agregar item al menú en `MenuBarManager.buildMenu()`

## Roadmap

### Fase 1 — Mejoras UX ✓ completada
- [x] Overlay muestra estado "transcribiendo" tras soltar el hotkey
- [x] Cancelar transcripción en curso si el usuario vuelve a presionar el hotkey
- [x] Errores de Ollama visibles en la UI (overlay auto-dismiss 3s, sin modal bloqueante)
- [x] Hotkey: docs corregidos (Right Command `0x36`, no Right Option)

### Fase 2 — Post-procesado LLM ✓ completada
- [x] Pipeline llmRewrite funcionando end-to-end con Ollama + Gemma4
- [x] Overlay diferenciado: "Transcribiendo…" → "Mejorando…" con preview del transcript
- [x] Nombres de modelos corregidos (`gemma4:e2b` / `gemma4:e4b`)
- [x] Timeout Ollama extendido (120s request / 300s resource)

### Fase 3 — Base de datos local + historial + métricas ✓ completada
- [x] SwiftData para persistencia local (`~/Library/Application Support/LocalVoice/`)
- [x] `TranscriptionRecord` guarda: timestamp, duración de audio, palabras, idioma detectado, app destino, modo, modelo Whisper, modelo Ollama, latencia Ollama
- [x] Texto transcrito opt-in (default off) — configurable en Settings → Privacy
- [x] Ventana History accesible desde el menú (⌘H): stats, lista de registros, export CSV
- [x] Métricas en UI: total grabaciones, total palabras, WPM promedio (calculado sobre duración real del audio)

### Fase 4 — Prompts avanzados con contexto (requiere Fase 3)
> Implementar recién cuando la base de datos esté lista y se esté almacenando contexto.
- [ ] Múltiples prompts configurables por el usuario (ej. "corregir", "resumir", "formalizar")
- [ ] Shortcuts por prompt
- [ ] Detección de la app activa para adaptar el prompt al contexto (ej. en Cursor: corregir nombres de variables del proyecto, entender terminología del codebase)
- [ ] El modelo recibe contexto de la app de destino antes de reescribir

## Docs adicionales

- [ARCHITECTURE.md](ARCHITECTURE.md) — diseño técnico completo con diagramas
- [README.md](README.md) — guía de usuario e instalación
