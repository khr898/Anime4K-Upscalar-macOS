#!/bin/zsh
# check_outputs.sh — post-hoc validator for GUI-upscaled videos.
#
# Workflow: you upscale a source clip through every pipeline in the GUI app,
# drop the output .mp4/.mov/.mkv files into one folder, then run this script
# against that folder. It probes each output and reports resolution, frame
# count, duration, codec, bitrate, and file size. If you also pass the
# original source clip, it checks each output kept the source's frame count
# and duration (within 2%) and is actually upscaled (out dims > source dims).
#
# Usage:
#   zsh check_outputs.sh <outputs_folder>                      # report only
#   zsh check_outputs.sh <outputs_folder> <source_clip>        # + integrity vs source
#
# Requires: ffprobe (brew install ffmpeg). No app, no probe binaries.

set -u
FOLDER="${1:-}"
SRC="${2:-}"
PASS=0; FAIL=0; FAILED=()

[ -d "$FOLDER" ] || { echo "usage: zsh check_outputs.sh <outputs_folder> [source_clip]"; echo "  '\$FOLDER' is not a directory"; exit 2; }
command -v ffprobe >/dev/null || { echo "FAIL: ffprobe not found (brew install ffmpeg)"; exit 2; }

# Probe a file: echo "WxH|frames|duration|codec|bitrate|size_bytes"
probe(){
  local f="$1"
  local W H FR DUR CODEC BR SZ
  W=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nk=1:nw=1 "$f")
  H=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nk=1:nw=1 "$f")
  FR=$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of default=nk=1:nw=1 "$f")
  DUR=$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$f")
  CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nk=1:nw=1 "$f")
  BR=$(ffprobe -v error -show_entries format=bit_rate -of default=nk=1:nw=1 "$f")
  SZ=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)
  echo "${W}x${H}|${FR}|${DUR}|${CODEC}|${BR}|${SZ}"
}

hr(){ printf '\n======================== %s ========================\n' "$1"; }
ok(){ PASS=$((PASS+1)); printf '  [PASS] %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); printf '  [FAIL] %s\n' "$1"; }
humansize(){ awk -v b="$1" 'BEGIN{split("B KB MB GB TB",u); i=1; while(b>=1024&&i<5){b/=1024;i++} printf "%.1f%s",b,u[i]}'; }

# Source metadata (if provided).
SRC_W=""; SRC_H=""; SRC_FR=""; SRC_DUR=""
if [ -n "$SRC" ]; then
  [ -f "$SRC" ] || { echo "source clip not found: $SRC"; exit 2; }
  IFS='|' read -r dims SRC_FR SRC_DUR _rest _ _ <<<"$(probe "$SRC")"
  SRC_W="${dims%x*}"; SRC_H="${dims#*x}"
  hr "SOURCE"
  printf '  %s  %sx%s  %s frames  %.2fs\n' "$(basename "$SRC")" "$SRC_W" "$SRC_H" "$SRC_FR" "$SRC_DUR"
fi

hr "OUTPUTS in: $FOLDER"
# Collect video files (mp4/mov/mkv/avi/webm/m4v), sorted.
files=()
for f in "$FOLDER"/*.{mp4,MP4,mov,MOV,mkv,MKV,avi,AVI,webm,m4v}; do
  [ -f "$f" ] && files+=("$f")
done
[ ${#files[@]} -gt 0 ] || { echo "  no video files found in $FOLDER"; exit 1; }

printf '\n  %-32s %-12s %-8s %-8s %-8s %-10s %s\n' "file" "resolution" "frames" "dur(s)" "codec" "size" "status"
printf '  %-32s %-12s %-8s %-8s %-8s %-10s %s\n' "----" "----------" "------" "------" "-----" "----" "------"

for f in "${files[@]}"; do
  IFS='|' read -r dims FR DUR CODEC BR SZ <<<"$(probe "$f")"
  W="${dims%x*}"; H="${dims#*x}"
  base=$(basename "$f")
  [ ${#base} -gt 30 ] && base="${base:0:27}..."
  szh=$(humansize "$SZ")
  status="--"
  # Validity gate: must have dims + frames + nonzero size.
  if [ -z "$W" ] || [ -z "$H" ] || [ "$W" = "N/A" ] || [ -z "$FR" ] || [ "$FR" = "N/A" ] || [ "${SZ:-0}" -eq 0 ]; then
    status="BROKEN"; bad "$base: unreadable/empty"
    printf '  %-32s %-12s %-8s %-8s %-8s %-10s %s\n' "$base" "${dims:-?}" "${FR:-?}" "${DUR:-?}" "${CODEC:-?}" "$szh" "$status"
    continue
  fi
  # Integrity vs source (if provided).
  if [ -n "$SRC" ]; then
    rc=0
    [ "$FR" = "$SRC_FR" ] && ok "$base: frames match ($FR)" || { bad "$base: frame mismatch src=$SRC_FR out=$FR"; rc=1; }
    awk -v s="$SRC_DUR" -v o="$DUR" 'BEGIN{d=(o-s)/s; if(d<0)d=-d; exit (d>0.02)}' && ok "$base: duration within 2%" || { bad "$base: duration drift src=$SRC_DUR out=$DUR"; rc=1; }
    [ "$W" -gt "$SRC_W" ] && [ "$H" -gt "$SRC_H" ] && ok "$base: upscaled ${SRC_W}x${SRC_H} -> ${W}x${H}" || { bad "$base: not upscaled (${W}x${H} vs src ${SRC_W}x${SRC_H})"; rc=1; }
    [ $rc -eq 0 ] && status="OK" || status="FAIL"
  else
    # No source: just confirm it's a real, non-trivial video.
    if [ "$FR" -ge 1 ] && [ "$SZ" -gt 1000 ]; then status="OK"; ok "$base: valid (${W}x${H}, $FR frames)"; else status="BROKEN"; bad "$base: trivial output"; fi
  fi
  printf '  %-32s %-12s %-8s %-8s %-8s %-10s %s\n' "$base" "${W}x${H}" "$FR" "$DUR" "$CODEC" "$szh" "$status"
done

hr "SUMMARY"
printf 'PASS=%d  FAIL=%d  (videos=%d)\n' "$PASS" "$FAIL" "${#files[@]}"
if [ $FAIL -gt 0 ]; then
  printf 'Failed:\n'
  for s in "${FAILED[@]}"; do printf '  - %s\n' "$s"; done
  exit 1
fi
printf 'All outputs valid.\n'