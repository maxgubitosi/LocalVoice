#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage:
  scripts/benchmark-localvoice.sh path/to/localvoice-history.csv [output-directory]

Export History from LocalVoice after recording the same short phrases on one Mac,
then run this script to produce landing-page friendly timing summaries.
USAGE
  exit 0
fi

INPUT_CSV="$1"
OUT_DIR="${2:-Benchmarks}"
STAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
OUT_JSON="$OUT_DIR/localvoice-benchmark-$STAMP.json"
OUT_CSV="$OUT_DIR/localvoice-benchmark-$STAMP.csv"

mkdir -p "$OUT_DIR"

python3 - "$INPUT_CSV" "$OUT_JSON" "$OUT_CSV" <<'PY'
import csv
import datetime
import json
import math
import platform
import statistics
import subprocess
import sys

input_csv, out_json, out_csv = sys.argv[1:4]

def sysctl(name):
    try:
        return subprocess.check_output(["sysctl", "-n", name], text=True).strip()
    except Exception:
        return ""

def as_float(value):
    try:
        return float(value) if value not in (None, "") else None
    except ValueError:
        return None

def percentile(values, pct):
    values = sorted(v for v in values if v is not None)
    if not values:
        return None
    if len(values) == 1:
        return values[0]
    rank = (len(values) - 1) * pct
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return values[int(rank)]
    return values[lower] + (values[upper] - values[lower]) * (rank - lower)

with open(input_csv, newline="", encoding="utf-8") as handle:
    records = list(csv.DictReader(handle))

groups = {}
for record in records:
    key = (
        record.get("mode", ""),
        record.get("whisperModel", ""),
        record.get("llmModel", "") or "none",
    )
    groups.setdefault(key, []).append(record)

rows = []
for (mode, whisper_model, llm_model), items in sorted(groups.items()):
    whisper = [as_float(r.get("transcriptionSeconds")) for r in items]
    refine = [as_float(r.get("refineSeconds")) for r in items]
    total = [as_float(r.get("processingSeconds")) for r in items]
    audio = [as_float(r.get("durationSeconds")) for r in items]

    rows.append({
        "mode": mode,
        "whisperModel": whisper_model,
        "llmModel": "" if llm_model == "none" else llm_model,
        "sampleCount": len(items),
        "medianAudioSeconds": percentile(audio, 0.5),
        "medianWhisperSeconds": percentile(whisper, 0.5),
        "p90WhisperSeconds": percentile(whisper, 0.9),
        "medianRefineSeconds": percentile(refine, 0.5),
        "p90RefineSeconds": percentile(refine, 0.9),
        "medianTotalSeconds": percentile(total, 0.5),
        "p90TotalSeconds": percentile(total, 0.9),
    })

hardware = {
    "machine": platform.machine(),
    "processor": sysctl("machdep.cpu.brand_string"),
    "memoryGB": round(int(sysctl("hw.memsize") or 0) / (1024 ** 3), 1),
    "macOS": platform.mac_ver()[0],
}

payload = {
    "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "sourceCSV": input_csv,
    "hardware": hardware,
    "summary": rows,
}

with open(out_json, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")

fieldnames = [
    "mode", "whisperModel", "llmModel", "sampleCount",
    "medianAudioSeconds", "medianWhisperSeconds", "p90WhisperSeconds",
    "medianRefineSeconds", "p90RefineSeconds", "medianTotalSeconds", "p90TotalSeconds",
]
with open(out_csv, "w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

print(out_json)
print(out_csv)
PY
