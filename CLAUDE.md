# CLAUDE.md — LocalVoice

Guía para agentes de IA que trabajen en este codebase.

## Qué es esto

App de menu bar para macOS que convierte voz a texto de forma completamente local.
Sin cloud, sin suscripción. Todo el procesamiento corre localmente en el Mac.

- **Hotkey modo hold:** mantener Right Command (⌘ derecho) → graba, soltar → transcribe
- **Hotkey modo latch:** doble-tap Right Command → empieza a grabar, tap → para y transcribe
- **Modo 1 (Direct):** audio → Whisper → texto insertado en la app activa
- **Modo 2 (Refine):** audio → Whisper → MLX (Qwen3.5 en proceso) → texto reescrito → insertado

## Cómo buildear

```bash
make build                     # swift build + Metal shaders + re-firma el binario
make run                       # build + ejecutar
.build/release/LocalVoice      # ejecutar sin re-buildear
make bundle                    # crea LocalVoice.app en el directorio raíz
```

`make build` hace tres cosas en orden:
1. `swift build -c release` — compila Swift
2. `scripts/build-metallib.sh` — compila shaders Metal de MLX → `.build/release/mlx.metallib`
3. `codesign --force --sign -` — firma ad-hoc (obligatorio para que macOS reconozca el bundle ID)

**Requiere Xcode instalado** (no solo CLT) porque la compilación de Metal shaders usa el toolchain
de Xcode (`xcrun metal`). macOS 14+ (Sonoma). Apple Silicon recomendado.

### Metal shaders

MLX necesita `mlx.metallib` colocado junto al binario. El script `scripts/build-metallib.sh`
compila los shaders pre-generados de mlx-swift desde:
```
.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal/*.metal
```
Tiene chequeo de staleness: si el metallib ya existe y es más nuevo que todos los `.metal`,
se saltea la compilación.

## Estructura de módulos

```
Sources/LocalVoice/
├── App/
│   ├── LocalVoiceApp.swift       # @main, NSApplication.accessory (sin Dock icon)
│   ├── AppDelegate.swift         # orquesta el pipeline completo
│   ├── AppSettings.swift         # UserDefaults-backed, ObservableObject
│   └── DeviceCapability.swift    # detecta chip/RAM, recomienda modelo MLX
├── Audio/
│   ├── AudioCapture.swift        # AVAudioEngine → Float32 16kHz mono
│   └── HotkeyManager.swift       # CGEventTap en Right Command key
├── Transcription/
│   └── TranscriptionEngine.swift # wrapper WhisperKit, retorna TranscriptionOutput {text, language}
├── LLM/
│   ├── MLXClient.swift           # inferencia en proceso vía MLXLLM + ChatSession
│   ├── MLXModelCatalog.swift     # lista curada de modelos Qwen3.5 con metadata
│   └── MLXModelManager.swift     # descarga, progreso, borrado de modelos MLX
├── Persistence/
│   └── TranscriptionRecord.swift # @Model SwiftData — historial local
├── TextInsertion/
│   └── TextInserter.swift        # AXUIElement (tier 1) + pasteboard (tier 2)
└── UI/
    ├── MenuBarManager.swift       # NSStatusItem + NSMenu + "Check for Updates…"
    ├── RecordingOverlayWindow.swift # overlay flotante SwiftUI animado
    ├── SettingsWindow.swift       # NSWindow + SwiftUI Form (con download UI de modelos)
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
  → TranscriptionEngine.transcribe([Float]) → TranscriptionOutput
  → [si Modo 2] MLXClient.rewrite(transcript:prompt:appContext:detectedLanguage:) → String
  → TextInserter.insert(String)
```

## Modelo MLX por defecto

`DeviceCapability.recommendedMLXModel` elige automáticamente según chip y RAM:

| Dispositivo | Modelo | RAM ~necesaria |
|---|---|---|
| M4, 32GB+ | `mlx-community/Qwen3.5-27B-4bit` | ~16 GB |
| M3/M4, 16GB+ | `mlx-community/Qwen3.5-9B-MLX-4bit` | ~5.5 GB |
| Cualquiera, 16GB+ | `mlx-community/Qwen3.5-4B-MLX-4bit` | ~3 GB |
| Default (M1/M2 8GB) | `mlx-community/Qwen3.5-2B-MLX-4bit` | ~1.5 GB |

Los modelos se descargan la primera vez que se usa el modo Refine. Se guardan en:
`~/Library/Application Support/LocalVoice/MLXModels/models/<org>/<model>/`

**Qwen3 no-think mode:** se agrega `/no_think` al prompt para desactivar chain-of-thought,
lo que reduce la latencia significativamente en tareas cortas de reescritura.

Para cambiar el modelo recomendado: modificar `DeviceCapability.recommendedMLXModel`.

## MLXClient — detalles de implementación

`MLXClient` usa un bridge manual (sin macros de `MLXHuggingFace`) porque el paquete
`HuggingFace` no es compatible con este setup:

- `HubDownloader`: implementa `MLXLMCommon.Downloader` via `Hub.HubApi.snapshot()`
- `TransformersTokenizerLoader`: implementa `MLXLMCommon.TokenizerLoader` via `AutoTokenizer.from(modelFolder:)`
- `TokenizerBridge`: adapta `Tokenizers.Tokenizer` → `MLXLMCommon.Tokenizer`
  - Importante: `decode(tokenIds:)` en MLXLMCommon vs `decode(tokens:)` en Tokenizers

La sesión de chat se crea nueva por cada request (o se llama `session.clear()`) para evitar
que el historial acumule contexto entre transcripciones distintas.

## Inserción de texto — reglas importantes

`TextInserter` tiene dos tiers:

1. **AXUIElement** — directo, sin tocar el clipboard. Verifica `kAXSecureTextFieldRole` y **no inserta en campos de contraseña**.
2. **NSPasteboard + Cmd+V** — fallback universal. Guarda y restaura el clipboard después de 500ms.

**Nunca saltear la verificación de secure text field.** Es un invariante de seguridad.

## Threading

- **Main thread:** UI, NSApplication, menú
- **AVAudioEngine callback:** solo acumula samples en `[Float]`, nada más
- **Task { }:** transcripción + inferencia MLX (structured concurrency)
- **MainActor.run { }:** toda actualización de UI o inserción de texto
- **MLXModelManager:** `@MainActor` — actualiza `@Published` desde async download tasks

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
- No bloquear el main thread con transcripción o inferencia LLM
- No agregar dependencias sin revisar si Apple Silicon las soporta nativamente
- No cambiar el modelo de Whisper en caliente sin llamar `loadModel()` de nuevo
- No usar `UserDefaults` fuera de `AppSettings`
- No usar el paquete `MLXHuggingFace` (requiere `HuggingFace` package incompatible); usar el bridge manual en `MLXClient.swift`

## Tareas comunes

**Cambiar el modelo Whisper por defecto:**
Modificar `AppSettings.init()` → campo `whisperModel`.

**Agregar un nuevo modelo MLX al catálogo:**
Modificar `MLXModelCatalog.swift` → array `models`. Verificar tamaño real en HuggingFace antes de agregar.

**Cambiar el modelo MLX recomendado por tier:**
Modificar `DeviceCapability.recommendedMLXModel` en `DeviceCapability.swift`.

**Cambiar el hotkey:**
`HotkeyManager.monitoredKeyCode` — el keycode actual es `0x36` (Right Command).

**Agregar un modo nuevo (ej. resumen):**
1. Agregar case a `AppMode` en `AppSettings.swift`
2. Agregar case en `AppDelegate.stopAndProcess()`
3. Agregar item al menú en `MenuBarManager.buildMenu()`

**Crear un DMG firmado para distribución:**
```bash
./scripts/build-release.sh 1.0.0
# Requiere: Developer ID cert en keychain, notarytool profile, create-dmg
```

## Distribución

La app se distribuye como DMG firmado + notarizado via GitHub Releases.
No requiere App Store. La URL del appcast de Sparkle está en `Info.plist` → `SUFeedURL`.
`SUEnableAutomaticChecks` está en `false` hasta que haya un appcast real publicado.

Para firmar con Developer ID real:
1. Exportar `DEVELOPER_ID_IDENTITY` con el nombre del certificado
2. Configurar `xcrun notarytool store-credentials notarytool`
3. Correr `./scripts/build-release.sh <version>`

## Roadmap

### Fases anteriores ✓ completadas
- [x] **Fase 1 UX:** overlay de estado, cancelación con hotkey, errores visibles
- [x] **Fase 2 LLM:** pipeline llmRewrite end-to-end (originalmente con Ollama/Gemma4)
- [x] **Fase 3 DB:** SwiftData + historial + métricas + export CSV

### Fase 4 — MLX + Distribución ✓ completada (branch: feature/mlx-distribution)
- [x] Reemplazar Ollama con MLX en proceso (MLXLLM + ChatSession)
- [x] `MLXModelCatalog` — catálogo de modelos Qwen3.5 con metadata de RAM/tamaño
- [x] `MLXModelManager` — descarga con progreso, borrado, chequeo de descarga
- [x] Settings: lista de modelos MLX con botón de descarga, barra de progreso, badge "Recommended"
- [x] Settings: lista de modelos Whisper con indicador de estado de descarga
- [x] Sparkle auto-update integrado (`SPUStandardUpdaterController`, "Check for Updates…" en menú)
- [x] `make bundle` → crea `LocalVoice.app` listo para Finder
- [x] `scripts/build-release.sh` → firma + notariza + DMG + instrucciones appcast
- [x] `scripts/build-metallib.sh` → compila shaders Metal de MLX al hacer `make build`
- [x] Entitlements para JIT de Metal (`LocalVoice.entitlements`)

### Fase 5 — Prompts avanzados con contexto
> Requiere que la rama feature/mlx-distribution esté mergeada a main.
- [ ] Múltiples prompts configurables por el usuario (ej. "corregir", "resumir", "formalizar")
- [ ] Shortcuts por prompt
- [ ] Detección de la app activa para adaptar el prompt al contexto (ej. en Cursor: terminología del proyecto)
- [ ] El modelo recibe contexto de la app de destino antes de reescribir

### Fase 6 — Distribución pública
> Bloqueada en Apple Developer ID ($99/año, enrollment en developer.apple.com)
- [ ] Enroll en Apple Developer Program
- [ ] Configurar notarytool credentials
- [ ] Publicar primer DMG firmado en GitHub Releases
- [ ] Crear appcast.xml y actualizar `SUFeedURL` en Info.plist
- [ ] Landing page con instrucciones de instalación

## Docs adicionales

- [ARCHITECTURE.md](ARCHITECTURE.md) — diseño técnico completo con diagramas
- [README.md](README.md) — guía de usuario e instalación
- [docs/superpowers/specs/2026-04-23-distribution-llm-redesign-design.md](docs/superpowers/specs/2026-04-23-distribution-llm-redesign-design.md) — spec original del rediseño
