#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
UPSCALER_DIR="$ROOT_DIR/Anime4K-Upscaler"
BENCH_SWIFT="$UPSCALER_DIR/Tools/phase4_aahq_benchmark.swift"
BIN_OUT="/tmp/phase4_aahq_benchmark"
VIDEO="${1:-$ROOT_DIR/../TestVideos/test_pattern_1080p.mp4}"
MAX_FRAMES="${2:-120}"

BASELINE_FRAMES="${A4K_BENCH_BASELINE_FRAMES:-$MAX_FRAMES}"
OPT_WORKERS="${A4K_BENCH_OPT_WORKERS:-3}"
SCALE="${A4K_BENCH_OUTPUT_SCALE:-2}"
OPT_TG_THREADS="${A4K_BENCH_OPT_TG_THREADS:-512}"
SSIM_THRESHOLD="${A4K_BENCH_SSIM_THRESHOLD:-0.999}"
BASELINE_BACKEND="${A4K_BENCH_BASELINE_BACKEND:-metal}"
OPT_BACKEND="${A4K_BENCH_OPT_BACKEND:-mps}"

BASELINE_BACKEND_TAG="${BASELINE_BACKEND//[^A-Za-z0-9]/_}"
OPT_BACKEND_TAG="${OPT_BACKEND//[^A-Za-z0-9]/_}"

if [[ "$BASELINE_BACKEND" == "mps" ]]; then
  BASELINE_USE_MPS=1
else
  BASELINE_USE_MPS=0
fi

if [[ "$OPT_BACKEND" == "mps" ]]; then
  OPT_USE_MPS=1
else
  OPT_USE_MPS=0
fi

REF_RAW="/tmp/a4k_phase4_baseline_${BASELINE_BACKEND_TAG}.raw"
OPT_RAW="/tmp/a4k_phase4_trial_${OPT_BACKEND_TAG}.raw"
SUMMARY_MD="/tmp/a4k_phase4_aahq_summary.md"
METRICS_CSV="${A4K_BENCH_METRICS_CSV:-/tmp/a4k_phase4_metrics.csv}"

BASELINE_LOG="$(mktemp -t a4k_phase4_baseline).log"
OPT_LOG="$(mktemp -t a4k_phase4_opt).log"
SSIM_LOG="$(mktemp -t a4k_phase4_ssim).log"
PSNR_LOG="$(mktemp -t a4k_phase4_psnr).log"

if [[ ! -f "$VIDEO" ]]; then
  echo "ERROR: input video not found: $VIDEO"
  exit 1
fi

cd "$ROOT_DIR"

swiftc -O \
  -o "$BIN_OUT" \
  "$BENCH_SWIFT" \
  "$UPSCALER_DIR/ViewModels/Anime4KOfflineProcessor.swift" \
  "$UPSCALER_DIR/ViewModels/Anime4KRuntimePipeline.swift" \
  "$UPSCALER_DIR/ViewModels/Anime4KMPSConvolution.swift"

IN_DIMS="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$VIDEO")"
IN_W="${IN_DIMS%x*}"
IN_H="${IN_DIMS#*x}"
OUT_W=$((IN_W * SCALE))
OUT_H=$((IN_H * SCALE))

echo "[phase4] Running A+A HQ baseline (backend=$BASELINE_BACKEND, frames=$BASELINE_FRAMES)"
A4K_BENCH_BACKEND="$BASELINE_BACKEND" A4K_BENCH_USE_MPS="$BASELINE_USE_MPS" A4K_BENCH_USE_NEURAL_ASSIST=0 A4K_BENCH_OUTPUT_SCALE="$SCALE" A4K_BENCH_METRICS_CSV="$METRICS_CSV" "$BIN_OUT" "$VIDEO" "$BASELINE_FRAMES" | tee "$BASELINE_LOG"
cp -f /tmp/a4k_phase4_bench_last_frame.raw "$REF_RAW"

echo "[phase4] Running A+A HQ trial (backend=$OPT_BACKEND + Neural Assist, workers=$OPT_WORKERS, frames=$MAX_FRAMES)"
A4K_BENCH_BACKEND="$OPT_BACKEND" A4K_BENCH_USE_MPS="$OPT_USE_MPS" A4K_BENCH_USE_NEURAL_ASSIST=1 A4K_BENCH_WORKERS="$OPT_WORKERS" A4K_TARGET_THREADGROUP_THREADS="$OPT_TG_THREADS" A4K_BENCH_OUTPUT_SCALE="$SCALE" A4K_BENCH_METRICS_CSV="$METRICS_CSV" "$BIN_OUT" "$VIDEO" "$MAX_FRAMES" | tee "$OPT_LOG"
cp -f /tmp/a4k_phase4_bench_last_frame.raw "$OPT_RAW"

BASELINE_FPS="$(sed -nE 's/.*fps=([0-9]+\.[0-9]+).*/\1/p' "$BASELINE_LOG" | tail -n1)"
OPT_FPS="$(sed -nE 's/.*fps=([0-9]+\.[0-9]+).*/\1/p' "$OPT_LOG" | tail -n1)"
BASELINE_ELAPSED="$(sed -nE 's/.*elapsed=([0-9]+\.[0-9]+)s.*/\1/p' "$BASELINE_LOG" | tail -n1)"
OPT_ELAPSED="$(sed -nE 's/.*elapsed=([0-9]+\.[0-9]+)s.*/\1/p' "$OPT_LOG" | tail -n1)"
BASELINE_RESULT_LINE="$(grep 'RESULT:' "$BASELINE_LOG" | tail -n1)"
OPT_RESULT_LINE="$(grep 'RESULT:' "$OPT_LOG" | tail -n1)"
BASELINE_PROCESSED="$(echo "$BASELINE_RESULT_LINE" | sed -nE 's/.*frames=([0-9]+).*/\1/p')"
OPT_PROCESSED="$(echo "$OPT_RESULT_LINE" | sed -nE 's/.*frames=([0-9]+).*/\1/p')"

ffmpeg -hide_banner -nostats \
  -f rawvideo -pix_fmt bgra -s "${OUT_W}x${OUT_H}" -i "$REF_RAW" \
  -f rawvideo -pix_fmt bgra -s "${OUT_W}x${OUT_H}" -i "$OPT_RAW" \
  -lavfi ssim -f null - 2>&1 | tee "$SSIM_LOG" >/dev/null

ffmpeg -hide_banner -nostats \
  -f rawvideo -pix_fmt bgra -s "${OUT_W}x${OUT_H}" -i "$REF_RAW" \
  -f rawvideo -pix_fmt bgra -s "${OUT_W}x${OUT_H}" -i "$OPT_RAW" \
  -lavfi psnr -f null - 2>&1 | tee "$PSNR_LOG" >/dev/null

SSIM_ALL="$(sed -nE 's/.*All:([0-9]+\.[0-9]+).*/\1/p' "$SSIM_LOG" | tail -n1)"
PSNR_AVG="$(sed -nE 's/.*average:([[:alnum:]+.-]+).*/\1/p' "$PSNR_LOG" | tail -n1)"

QUALITY_STATUS="FAIL"
if [[ -n "${SSIM_ALL:-}" ]] && awk -v ssim="$SSIM_ALL" -v threshold="$SSIM_THRESHOLD" 'BEGIN { exit (ssim >= threshold ? 0 : 1) }'; then
  QUALITY_STATUS="PASS"
fi

if [[ ! -f "$METRICS_CSV" ]]; then
  echo "timestamp_utc,baseline_backend,trial_backend,run_role,backend,neural_assist,workers,frames_requested,frames_processed,elapsed_s,fps,input_w,input_h,output_w,output_h,ssim_all,psnr_avg_db,quality_status,video" > "$METRICS_CSV"
fi

RUN_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
VIDEO_CSV="${VIDEO//\"/\"\"}"

printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
  "$RUN_TS" "$BASELINE_BACKEND" "$OPT_BACKEND" "baseline" "$BASELINE_BACKEND" "0" "1" "$BASELINE_FRAMES" "${BASELINE_PROCESSED:-}" "${BASELINE_ELAPSED:-}" "${BASELINE_FPS:-}" "$IN_W" "$IN_H" "$OUT_W" "$OUT_H" "${SSIM_ALL:-}" "${PSNR_AVG:-}" "$QUALITY_STATUS" "$VIDEO_CSV" >> "$METRICS_CSV"

printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
  "$RUN_TS" "$BASELINE_BACKEND" "$OPT_BACKEND" "trial" "$OPT_BACKEND" "1" "$OPT_WORKERS" "$MAX_FRAMES" "${OPT_PROCESSED:-}" "${OPT_ELAPSED:-}" "${OPT_FPS:-}" "$IN_W" "$IN_H" "$OUT_W" "$OUT_H" "${SSIM_ALL:-}" "${PSNR_AVG:-}" "$QUALITY_STATUS" "$VIDEO_CSV" >> "$METRICS_CSV"

cat > "$SUMMARY_MD" <<EOF
# Phase 4 A+A HQ Benchmark Summary

- Input: $VIDEO
- Input resolution: ${IN_W}x${IN_H}
- Output resolution: ${OUT_W}x${OUT_H}
- Baseline run: backend=$BASELINE_BACKEND, frames=$BASELINE_FRAMES
- Trial run: backend=$OPT_BACKEND + Neural Assist probe, workers=$OPT_WORKERS, frames=$MAX_FRAMES
- Optimized threadgroup target: $OPT_TG_THREADS

| Metric | Value |
|---|---:|
| Baseline FPS (${BASELINE_BACKEND}) | ${BASELINE_FPS:-n/a} |
| Trial FPS (${OPT_BACKEND}) | ${OPT_FPS:-n/a} |
| SSIM (baseline vs trial) | ${SSIM_ALL:-n/a} |
| PSNR average (dB) | ${PSNR_AVG:-n/a} |
| Quality gate (SSIM >= ${SSIM_THRESHOLD}) | ${QUALITY_STATUS} |

Artifacts:
- $REF_RAW
- $OPT_RAW
- $METRICS_CSV
- $BASELINE_LOG
- $OPT_LOG
- $SSIM_LOG
- $PSNR_LOG
EOF

echo "[phase4] Summary: $SUMMARY_MD"
echo "[phase4] Baseline FPS (${BASELINE_BACKEND}): ${BASELINE_FPS:-n/a}"
echo "[phase4] Trial FPS (${OPT_BACKEND}): ${OPT_FPS:-n/a}"
echo "[phase4] SSIM: ${SSIM_ALL:-n/a}"
echo "[phase4] PSNR avg: ${PSNR_AVG:-n/a} dB"
echo "[phase4] Metrics CSV: $METRICS_CSV"
echo "[phase4] Quality gate (SSIM >= ${SSIM_THRESHOLD}): ${QUALITY_STATUS}"

if [[ "$QUALITY_STATUS" != "PASS" ]]; then
  echo "[phase4] ERROR: Quality gate failed. Optimized path does not match baseline closely enough."
  exit 3
fi
