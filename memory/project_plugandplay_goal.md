---
name: Objetivo plug and play
description: LocalVoice debe ser fácil de correr en distintas máquinas, primero para developers, eventualmente para usuarios normales
type: project
---

El objetivo a largo plazo es que LocalVoice sea lo más accesible posible para cualquier persona.

**Fases:**
1. **Ahora:** developers que clonan el repo. Que `swift build` funcione limpio en distintas máquinas sin sorpresas.
2. **Futuro:** usuarios normales sin conocimientos técnicos. Distribución como `.app` firmado y notarizado, sin tener que abrir Terminal.

**Por qué:** el usuario quiere que la app llegue a más gente, no solo a devs.

**Cuellos de botella identificados:**
- Ollama es el principal: es una instalación separada del sistema. El Modo 2 (reescritura LLM) depende de él. Opciones: bundlearlo, hacer onboarding in-app, o hacer el Modo 2 completamente opcional con fallback gracioso.
- WhisperKit descarga el modelo Whisper automáticamente — no es fricción.
- Firma y notarización de Apple necesaria para evitar Gatekeeper en distribución fuera del App Store.

**Cómo aplicar:** cuando se diseñe onboarding, settings, o se agregue el Modo 2, priorizar degradación graceable si Ollama no está instalado. No asumir que el usuario tiene todo configurado.
