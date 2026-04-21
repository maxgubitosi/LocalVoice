#!/usr/bin/env python3
"""
Evalúa resultados de WhisperBench usando Ollama como juez.

Uso:
    python3 judge.py results.json --ground-truth transcript.txt
    swift run WhisperBench audio.m4a | python3 judge.py - --ground-truth transcript.txt

Opciones:
    --ground-truth FILE     Transcripción de referencia (escrita a mano)
    --ollama-host URL       URL base de Ollama (default: http://localhost:11434)
    --model MODEL           Modelo Ollama a usar como juez (default: gemma4:e2b)
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime
from pathlib import Path


MODEL_DISPLAY_NAMES = {
    "openai_whisper-large-v3_turbo": "large-v3-turbo",
}


def display_name(model: str) -> str:
    return MODEL_DISPLAY_NAMES.get(model, model)


JUDGE_PROMPT = """\
Eres un evaluador experto de sistemas de reconocimiento de voz (STT).
Tu tarea es evaluar la calidad de la transcripción producida por un modelo comparándola con la transcripción de referencia.

TRANSCRIPCIÓN DE REFERENCIA (ground truth):
{ground_truth}

TRANSCRIPCIÓN DEL MODELO "{model}":
{model_output}

Evalúa la transcripción del modelo en los siguientes criterios:

1. **word_accuracy** (0-100): Porcentaje estimado de palabras correctamente transcritas. Considera errores de ortografía, palabras faltantes o sobrantes.
2. **semantic_accuracy** (0-10): ¿Se preservó el significado y la intención del texto? 10 = perfecto, 0 = significado completamente diferente.
3. **hallucinations**: Lista de palabras o frases que el modelo inventó y NO están en el audio (texto que no existe en la referencia). Array vacío si no hay alucinaciones.
4. **missing_content**: Partes importantes del audio que el modelo omitió. Array vacío si no falta nada relevante.
5. **notable_errors**: Los 3 errores más impactantes (palabras mal transcritas, nombres propios incorrectos, etc.). Array vacío si no hay errores.
6. **overall_score** (0-10): Puntuación global considerando todos los factores.
7. **summary**: Una frase resumiendo la calidad de esta transcripción.

Responde ÚNICAMENTE con un objeto JSON válido, sin texto adicional, sin markdown, sin explicaciones fuera del JSON.
Formato exacto:
{{"word_accuracy": 95, "semantic_accuracy": 9, "hallucinations": [], "missing_content": [], "notable_errors": ["error1"], "overall_score": 9, "summary": "..."}}
"""


def call_ollama(prompt: str, host: str, model: str) -> str:
    url = f"{host.rstrip('/')}/api/generate"
    payload = json.dumps({"model": model, "prompt": prompt, "stream": False}).encode()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.loads(resp.read())
            return data["response"].strip()
    except urllib.error.URLError as e:
        print(f"Error conectando a Ollama en {host}: {e}", file=sys.stderr)
        print("Asegurate de que Ollama esté corriendo: ollama serve", file=sys.stderr)
        sys.exit(1)


def parse_json_response(raw: str) -> dict:
    # Intentar extraer JSON aunque el modelo agregue texto alrededor
    raw = raw.strip()
    start = raw.find("{")
    end = raw.rfind("}") + 1
    if start != -1 and end > start:
        try:
            return json.loads(raw[start:end])
        except json.JSONDecodeError:
            pass
    return {"raw_response": raw, "parse_error": True}


def render_table(results: list[dict], bench_results: list[dict], judge_model: str = "gemma4:e2b") -> str:
    lines = []

    lines.append("# Resultados del Benchmark de Transcripción\n")

    # Info general
    if bench_results:
        lines.append(f"**Audio:** {bench_results[0].get('_audio_file', 'N/A')}  ")
        lines.append(f"**Duración:** {bench_results[0].get('_duration', 'N/A')}s  ")
        lines.append(f"**Idioma configurado:** {bench_results[0].get('_language', 'auto')}  ")
        lines.append(f"**Juez:** {judge_model}  ")
        lines.append(f"**Fecha:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")

    # Tabla de métricas
    lines.append("## Métricas por modelo\n")
    lines.append("| Modelo | Score | Word Acc | Semántica | Carga (ms) | Transcripción (ms) | Alucinaciones |")
    lines.append("|--------|-------|----------|-----------|------------|-------------------|---------------|")

    sorted_results = sorted(results, key=lambda r: r.get("eval", {}).get("overall_score", 0), reverse=True)

    for r in sorted_results:
        model = display_name(r["model"])
        load_ms = r.get("load_ms", "—")
        transcribe_ms = r.get("transcribe_ms", "—")
        eval_data = r.get("eval", {})

        if eval_data.get("parse_error"):
            lines.append(f"| {model} | ERROR | — | — | {load_ms} | {transcribe_ms} | — |")
            continue

        score = eval_data.get("overall_score", "—")
        word_acc = f"{eval_data.get('word_accuracy', '—')}%"
        semantic = eval_data.get("semantic_accuracy", "—")
        hallucinations = len(eval_data.get("hallucinations", []))
        hall_str = str(hallucinations) if hallucinations == 0 else f"**{hallucinations}**"
        lines.append(f"| {model} | {score}/10 | {word_acc} | {semantic}/10 | {load_ms} | {transcribe_ms} | {hall_str} |")

    lines.append("")

    # Detalle por modelo
    lines.append("## Detalle por modelo\n")
    for r in sorted_results:
        model = display_name(r["model"])
        eval_data = r.get("eval", {})
        lines.append(f"### {model}")

        if eval_data.get("parse_error"):
            lines.append(f"*Error al parsear la respuesta del juez:*\n```\n{eval_data.get('raw_response', '')}\n```\n")
            continue

        lines.append(f"**Resumen:** {eval_data.get('summary', '—')}")
        lines.append(f"**Score global:** {eval_data.get('overall_score', '—')}/10")

        errors = eval_data.get("notable_errors", [])
        if errors:
            lines.append(f"\n**Errores notables:**")
            for e in errors:
                lines.append(f"- {e}")

        hallucinations = eval_data.get("hallucinations", [])
        if hallucinations:
            lines.append(f"\n**Alucinaciones:**")
            for h in hallucinations:
                lines.append(f"- {h}")

        missing = eval_data.get("missing_content", [])
        if missing:
            lines.append(f"\n**Contenido omitido:**")
            for m in missing:
                lines.append(f"- {m}")

        lines.append(f"\n**Transcripción completa:**")
        lines.append(f"> {r.get('text', '—')}\n")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Evalúa resultados de WhisperBench con Ollama como juez.")
    parser.add_argument("input", help="Archivo JSON de resultados o '-' para stdin")
    parser.add_argument("--ground-truth", required=True, help="Archivo de texto con la transcripción de referencia")
    parser.add_argument("--ollama-host", default="http://localhost:11434", help="URL base de Ollama")
    parser.add_argument("--model", default="gemma4:e2b", help="Modelo Ollama a usar como juez")
    args = parser.parse_args()

    # Cargar ground truth
    with open(args.ground_truth, "r", encoding="utf-8") as f:
        ground_truth = f.read().strip()

    # Cargar resultados del benchmark
    if args.input == "-":
        bench_data = json.load(sys.stdin)
    else:
        with open(args.input, "r", encoding="utf-8") as f:
            bench_data = json.load(f)

    audio_file = bench_data.get("audio_file", "?")
    audio_duration = bench_data.get("audio_duration_seconds", "?")
    language = bench_data.get("language", "auto")
    bench_results = bench_data.get("results", [])

    if not bench_results:
        print("No hay resultados en el JSON.", file=sys.stderr)
        sys.exit(1)

    print(f"Evaluando {len(bench_results)} modelos con {args.model} en {args.ollama_host}...", file=sys.stderr)

    evaluated = []
    for result in bench_results:
        model = result["model"]
        text = result.get("text", "")
        error = result.get("error")

        if error:
            print(f"  Saltando {model} (error al transcribir): {error}", file=sys.stderr)
            evaluated.append({**result, "eval": {"error": error}, "_audio_file": audio_file, "_duration": audio_duration, "_language": language})
            continue

        if not text.strip():
            print(f"  Saltando {model} (transcripción vacía)", file=sys.stderr)
            evaluated.append({**result, "eval": {"overall_score": 0, "word_accuracy": 0, "semantic_accuracy": 0,
                               "hallucinations": [], "missing_content": ["todo el contenido"],
                               "notable_errors": ["transcripción vacía"], "summary": "Sin salida"},
                              "_audio_file": audio_file, "_duration": audio_duration, "_language": language})
            continue

        print(f"  Evaluando {display_name(model)}...", file=sys.stderr)
        prompt = JUDGE_PROMPT.format(ground_truth=ground_truth, model=display_name(model), model_output=text)
        raw_response = call_ollama(prompt, args.ollama_host, args.model)
        eval_result = parse_json_response(raw_response)

        evaluated.append({
            **result,
            "eval": eval_result,
            "_audio_file": audio_file,
            "_duration": audio_duration,
            "_language": language,
        })

    report = render_table(evaluated, evaluated, judge_model=args.model)
    print(report)

    # Write report to outputs/
    script_dir = Path(__file__).parent
    outputs_dir = script_dir / "outputs"
    outputs_dir.mkdir(exist_ok=True)

    audio_stem = Path(audio_file).stem
    timestamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    output_path = outputs_dir / f"{timestamp}_{audio_stem}.md"
    output_path.write_text(report, encoding="utf-8")
    print(f"\nReporte guardado en: {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
