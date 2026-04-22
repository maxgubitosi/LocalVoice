# Latch Mode Fix — Descartar audio en tap solitario

**Fecha:** 2026-04-22  
**Estado:** Aprobado

## Problema

El modo latch usa doble-tap: primer tap arranca la grabación, segundo tap entra en modo latch, un tercer tap para y transcribe. Cuando el segundo tap no llega dentro de la ventana de 0.5s, el timer dispara `onHotkeyUp?()`, que intenta transcribir el audio del primer tap — generalmente vacío o ruido de fondo. El usuario termina con muchos registros vacíos en el historial.

## Solución

Cuando el timer de `waitingDoubleTap` vence sin segundo tap, descartar el audio en vez de transcribirlo.

Comportamiento nuevo:

| Gesto | Resultado |
|---|---|
| Tap rápido + nada (< 0.5s) | Audio descartado, overlay desaparece silenciosamente |
| Tap rápido + tap rápido | Latch mode (sin cambios) |
| Press & hold + soltar | Hold mode (sin cambios) |

El overlay sigue apareciendo en el primer tap. Si el segundo tap no llega, el overlay desaparece cuando vence el timer (~0.5s).

## Cambio en la máquina de estados

`HotkeyManager` tiene un estado `waitingDoubleTap` al que llega tras un tap rápido. Hoy el timer que lo controla llama `onHotkeyUp?()`. El único cambio es que llame `onHotkeyCancel?()` en su lugar.

```
// Antes — timer en waitingDoubleTap:
state = .idle
onHotkeyUp?()      // transcribe → audio vacío

// Después:
state = .idle
onHotkeyCancel?()  // descarta → sin registro
```

Timing: se mantiene `holdThreshold = 0.25s` y `doubleTapWindow = 0.5s`.

## Archivos a modificar

### `Sources/LocalVoice/Audio/HotkeyManager.swift`

1. Agregar propiedad: `var onHotkeyCancel: (() -> Void)?`
2. En el timer de `waitingDoubleTap` (método `handleKeyUp`), reemplazar:
   ```swift
   self.onHotkeyUp?()
   ```
   por:
   ```swift
   self.onHotkeyCancel?()
   ```

### `Sources/LocalVoice/App/AppDelegate.swift`

En `applicationDidFinishLaunching`, agregar junto a los otros callbacks de `hotkeyManager`:

```swift
hotkeyManager.onHotkeyCancel = { [weak self] in
    self?.cancelRecording()
}
```

Agregar método privado:

```swift
private func cancelRecording() {
    audioCapture.stopRecording { _ in }
    DispatchQueue.main.async { self.recordingOverlay.hide() }
}
```

## Archivos que NO cambian

- `AudioCapture.swift` — `stopRecording { _ in }` ya descarta el buffer correctamente.
- `RecordingOverlayWindow.swift` — `hide()` ya existe.
- Todo el pipeline de transcripción — no se toca.
