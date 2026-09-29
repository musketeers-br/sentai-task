#!/usr/bin/env bash
# Spec 014 US1: records the showcase and writes the media into assets/media/.
#   bash scripts/media/make-media.sh
# Needs the dev stack with iris-target (docker compose up -d) and the frontend toolchain. ffmpeg
# runs in a throw-away container (FR-006). Nothing is written to assets/media unless every check
# passes (FR-004).
set -euo pipefail
export MSYS_NO_PATHCONV=1
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FFMPEG_IMAGE="jrottenberg/ffmpeg:7-alpine"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sentai-media.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

ff()      { docker run --rm -v "$WORK:/w" "$FFMPEG_IMAGE" -hide_banner -loglevel error -y "$@"; }
seconds() { docker run --rm -v "$WORK:/w" --entrypoint ffprobe "$FFMPEG_IMAGE" -v error -show_entries format=duration -of csv=p=0 "/w/$1"; }
bytes()   { wc -c < "$WORK/$1" | tr -d ' '; }

record() {
	local timelapse="$1"
	rm -rf "$WORK/rec"
	(cd "$REPO/frontend" && SENTAI_MEDIA_OUT="$WORK/rec" SENTAI_MEDIA_TIMELAPSE="$timelapse" \
		npx playwright test -c playwright.media.config.ts -g "the recording")
	local video
	video="$(find "$WORK/rec" -name '*.webm' | head -n 1)"
	[ -n "$video" ] || { echo "no video was recorded" >&2; exit 1; }
	cp "$video" "$WORK/run.webm"
}

echo "== recording (pass 1)"
record 1
dur="$(seconds run.webm)"
factor="$(awk -v d="$dur" 'BEGIN { f = d / 28; if (f < 1) f = 1; printf "%.2f", f }')"
echo "   video ${dur}s; speed factor ${factor}"
if awk -v f="$factor" 'BEGIN { exit !(f > 1.5) }'; then
	echo "== recording (pass 2, captions say time-lapse ×${factor})"
	record "$factor"
	dur="$(seconds run.webm)"
	factor="$(awk -v d="$dur" 'BEGIN { f = d / 28; if (f < 1) f = 1; printf "%.2f", f }')"
fi

echo "== converting"
ff -i /w/run.webm -vf "scale=1280:720:flags=lanczos,format=yuv420p" -c:v libx264 -preset slow -crf 22 -movflags +faststart /w/sentai-run.mp4
gif() { # $1 name, $2 width, $3 fps
	ff -i /w/run.webm -vf "setpts=PTS/${factor},fps=$3,scale=$2:-1:flags=lanczos,palettegen=stats_mode=diff" /w/palette.png
	ff -i /w/run.webm -i /w/palette.png -lavfi "setpts=PTS/${factor},fps=$3,scale=$2:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5" "/w/$1"
}
gif sentai-run.gif 960 12
if [ "$(bytes sentai-run.gif)" -gt 8000000 ]; then echo "   over 8 MB at 12 fps; trying 10 fps"; gif sentai-run.gif 960 10; fi
gif sentai-run-small.gif 640 8

echo "== checking (FR-002)"
ok=1
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; ok=0; fi; }
g="$(seconds sentai-run.gif)"; s="$(seconds sentai-run-small.gif)"; m="$(seconds sentai-run.mp4)"
check "animated capture ≤ 30 s (${g}s)" "awk -v x=$g 'BEGIN{exit !(x<=30.5)}'"
check "animated capture ≤ 8 MB ($(bytes sentai-run.gif) bytes)" "[ $(bytes sentai-run.gif) -le 8000000 ]"
check "small capture ≤ 3 MB ($(bytes sentai-run-small.gif) bytes)" "[ $(bytes sentai-run-small.gif) -le 3000000 ]"
check "video ≤ 90 s (${m}s)" "awk -v x=$m 'BEGIN{exit !(x<=90.5)}'"
[ "$ok" = 1 ] || { echo "media checks failed; assets/media left unchanged" >&2; exit 1; }

echo "== stills"
(cd "$REPO/frontend" && SENTAI_MEDIA_OUT="$WORK/stills-run" SENTAI_MEDIA_STILLS="$WORK/stills" \
	npx playwright test -c playwright.media.config.ts -g "stills")
[ "$(ls "$WORK/stills" | wc -l)" -ge 12 ] || { echo "expected 12 stills" >&2; exit 1; }

echo "== publishing into assets/media"
mkdir -p "$REPO/assets/media/stills"
cp "$WORK/sentai-run.gif" "$WORK/sentai-run-small.gif" "$WORK/sentai-run.mp4" "$REPO/assets/media/"
cp "$WORK/stills/"*.png "$REPO/assets/media/stills/"
commit="$(git -C "$REPO" rev-parse --short HEAD)"
version="$(grep -o '<Version>[^<]*' "$REPO/module.xml" | head -n 1 | cut -d'>' -f2)"
cat > "$REPO/assets/media/manifest.json" <<JSON
{ "recordedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "commit": "$commit", "moduleVersion": "$version", "timelapse": $factor,
  "files": { "gif": {"path": "sentai-run.gif", "bytes": $(bytes sentai-run.gif), "seconds": $g},
             "gifSmall": {"path": "sentai-run-small.gif", "bytes": $(bytes sentai-run-small.gif), "seconds": $s},
             "video": {"path": "sentai-run.mp4", "seconds": $m, "committed": false},
             "stills": [$(cd "$WORK/stills" && ls *.png | sed 's/.*/"stills\/&"/' | paste -sd, -)] } }
JSON
echo "done: assets/media ($(ls "$REPO/assets/media" | wc -l) entries)"
