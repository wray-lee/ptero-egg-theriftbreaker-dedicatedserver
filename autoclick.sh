#!/usr/bin/env bash
set -euo pipefail

: "${AUTOCLICK:=1}"
: "${AUTOCLICK_TIMEOUT:=120}"
: "${AUTOCLICK_TRIES:=15}"
: "${AUTOCLICK_SLEEP:=2}"
: "${AUTOCLICK_WINDOW_REGEX:=The Riftbreaker: Dedicated Server|Dedicated Server}"

# Screenshot controls
: "${AUTOCLICK_SCREENSHOT:=0}"          # 1=on, 0=off
: "${AUTOCLICK_SCREENSHOT_EVERY:=0}"    # 1=each attempt, 0=only before/after/fail
: "${AUTOCLICK_SCREENSHOT_DIR:=/home/container/autoclick}"

[[ "$AUTOCLICK" == "1" ]] || exit 0

command -v xdotool >/dev/null 2>&1 || { echo "[autoclick] ERROR: xdotool missing"; exit 1; }

export DISPLAY="${DISPLAY:-:0}"

mkdir -p "$AUTOCLICK_SCREENSHOT_DIR"

ts() { date +"%Y%m%d-%H%M%S"; }

shot() {
  [[ "$AUTOCLICK_SCREENSHOT" == "1" ]] || return 0
  command -v import >/dev/null 2>&1 || { echo "[autoclick] NOTE: 'import' not found (install imagemagick)"; return 0; }

  local label="$1"
  local file="${AUTOCLICK_SCREENSHOT_DIR}/$(ts)-${label}.png"
  # root screenshot of Xvfb
  import -display "$DISPLAY" -window root "$file" 2>/dev/null || true
  echo "[autoclick] Screenshot: $file"
}

echo "[autoclick] Waiting for window regex: $AUTOCLICK_WINDOW_REGEX (timeout ${AUTOCLICK_TIMEOUT}s)"

WIN_ID=""
for i in $(seq 1 "$AUTOCLICK_TIMEOUT"); do
  WIN_ID="$(xdotool search --onlyvisible --name "$AUTOCLICK_WINDOW_REGEX" 2>/dev/null | head -n1 || true)"
  [[ -n "$WIN_ID" ]] && break
  sleep 1
done

if [[ -z "$WIN_ID" ]]; then
  echo "[autoclick] ERROR: window not found."
  echo "[autoclick] Visible windows:"
  xdotool search --onlyvisible --name "." getwindowname %@ 2>/dev/null || true
  shot "window-not-found"
  exit 1
fi

echo "[autoclick] Found window id: $WIN_ID"
shot "found-window"

# Focus it
xdotool windowactivate --sync "$WIN_ID" || true
sleep 0.3

# Try multiple strategies, keep snapping if desired
for n in $(seq 1 "$AUTOCLICK_TRIES"); do
  echo "[autoclick] Attempt $n/$AUTOCLICK_TRIES"

  xdotool windowactivate --sync "$WIN_ID" || true
  sleep 0.2

  # Strategy A: TAB a bunch then ENTER/SPACE
  xdotool key --window "$WIN_ID" Tab Tab Tab Tab Tab || true
  xdotool key --window "$WIN_ID" Return || true
  xdotool key --window "$WIN_ID" space  || true
  sleep 0.2

  # Strategy B: click bottom-center (Start bar)
  eval "$(xdotool getwindowgeometry --shell "$WIN_ID" 2>/dev/null || true)"
  if [[ -n "${WIDTH:-}" && -n "${HEIGHT:-}" ]]; then
    xdotool mousemove --window "$WIN_ID" $((WIDTH/2)) $((HEIGHT-20)) click 1 || true
    xdotool mousemove --window "$WIN_ID" $((WIDTH/2)) $((HEIGHT-45)) click 1 || true
  fi

  [[ "$AUTOCLICK_SCREENSHOT_EVERY" == "1" ]] && shot "attempt-${n}"

  sleep "$AUTOCLICK_SLEEP"

  # If the config window disappears, assume it progressed
  if ! xdotool getwindowname "$WIN_ID" >/dev/null 2>&1; then
    echo "[autoclick] Window closed -> likely started."
    shot "window-closed"
    exit 0
  fi
done

# echo "[autoclick] ERROR: window still present after retries."
# echo "[autoclick] Visible windows:"
xdotool search --onlyvisible --name "." getwindowname %@ 2>/dev/null || true
shot "failed-after-retries"

exit 1