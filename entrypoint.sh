#!/usr/bin/env bash
set -euo pipefail

cd /home/container

stty columns 250 || true

echo "Running on Debian $(cat /etc/debian_version)"
echo "User: $(id)"
echo "DISPLAY=$DISPLAY"

# --- Steam login defaults ---
if [[ -z "${STEAM_USER:-}" ]]; then
  echo -e "steam user is not set.\nUsing anonymous user.\n"
  STEAM_USER=anonymous
  STEAM_PASS=""
else
  echo "user set to ${STEAM_USER}"
fi

# --- Ensure steamcmd exists (safe if already there) ---
if [[ ! -x "./steamcmd/steamcmd.sh" ]]; then
  echo "[boot] steamcmd missing, downloading..."
  mkdir -p ./steamcmd
  curl -sSL -o /tmp/steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
  tar -xzf /tmp/steamcmd.tar.gz -C ./steamcmd
fi

# --- Update server files if requested ---
AUTO_UPDATE="${AUTO_UPDATE:-1}"
WINDOWS_INSTALL="${WINDOWS_INSTALL:-1}"
VALIDATE="${VALIDATE:-}"

if [[ "$AUTO_UPDATE" == "1" && -n "${SRCDS_APPID:-}" ]]; then
  echo "[update] Updating app ${SRCDS_APPID}..."
  ./steamcmd/steamcmd.sh \
    +force_install_dir /home/container \
    +login "${STEAM_USER}" "${STEAM_PASS}" \
    $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) \
    +app_update "${SRCDS_APPID}" \
    +app_update 1007 \
    $( [[ -n "${VALIDATE}" ]] && printf %s "validate" ) \
    +quit || true
else
  echo "[update] Skipping update (AUTO_UPDATE=$AUTO_UPDATE, SRCDS_APPID=${SRCDS_APPID:-unset})"
fi

# --- Headless X ---
mkdir -p /tmp/.X11-unix /tmp/.ICE-unix
chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix

XVFB="${XVFB:-1}"
if [[ "$XVFB" == "1" ]]; then
  echo "[x] Starting Xvfb..."
  Xvfb "$DISPLAY" -screen 0 "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}x${DISPLAY_DEPTH}" -nolisten tcp -ac &
  sleep 1
fi

echo "[x] Starting openbox..."
openbox >/dev/null 2>&1 &
sleep 0.5

# --- Fix relative asset paths when working dir is /home/container/bin ---
# (prevents missing gui/locale.kvp if the game expects bin/gui, bin/packs, etc.)
for d in gui packs data; do
  if [[ -d "/home/container/$d" && ! -e "/home/container/bin/$d" ]]; then
    ln -s "../$d" "/home/container/bin/$d"
  fi
done

# Start web GUI (noVNC) so we can click inside the container
/usr/local/bin/start-novnc.sh || true

# --- Proton install options ---
# Option A: set PROTON_URL to a tar.gz you provide (Proton-GE etc)
# Option B: set PROTON_APPID to a Steam tool appid that contains proton (default is Proton Experimental)
PROTON_DIR="/home/container/proton"
PROTON_URL="${PROTON_URL:-}"
PROTON_APPID="${PROTON_APPID:-1493710}"   # default: Proton Experimental (commonly used)

if [[ -n "$PROTON_URL" ]]; then
  if [[ ! -x "$PROTON_DIR/proton" ]]; then
    echo "[proton] Downloading Proton from PROTON_URL..."
    rm -rf "$PROTON_DIR"
    mkdir -p "$PROTON_DIR"
    curl -L "$PROTON_URL" -o /tmp/proton.tgz
    tar -xzf /tmp/proton.tgz -C "$PROTON_DIR" --strip-components=1
  fi
else
  if [[ ! -x "$PROTON_DIR/proton" ]]; then
    echo "[proton] Installing Proton via SteamCMD appid=${PROTON_APPID} ..."
    mkdir -p "$PROTON_DIR"
    ./steamcmd/steamcmd.sh \
      +force_install_dir "$PROTON_DIR" \
      +login anonymous \
      +app_update "$PROTON_APPID" validate \
      +quit || true
  fi
fi

if [[ ! -x "$PROTON_DIR/proton" ]]; then
  echo "[proton] ERROR: Proton not found at $PROTON_DIR/proton"
  echo "[proton] Set PROTON_URL to a Proton-GE tarball, or set PROTON_APPID to a working proton tool."
  exit 1
fi

echo "[proton] Proton runner: $PROTON_DIR/proton"

# --- Proton compatibility prefix location (important!) ---
export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container"
export STEAM_COMPAT_DATA_PATH="/home/container/compatdata/riftbreaker-ds"
mkdir -p "$STEAM_COMPAT_DATA_PATH"

# Optional: force software rendering in headless containers
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-llvmpipe}"

# Optional: install dependencies into the proton prefix (HIGHLY recommended)
# In Pterodactyl: set PROTON_WINETRICKS="vcrun2022"
PROTON_WINETRICKS="${PROTON_WINETRICKS:-}"
if [[ -n "$PROTON_WINETRICKS" ]]; then
  echo "[proton] Preparing prefix + running winetricks: $PROTON_WINETRICKS"
  export WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"

  # initialize prefix
  "$PROTON_DIR/proton" run wineboot -u || true

  # use proton's wine for winetricks if available
  if [[ -x "$PROTON_DIR/dist/bin/wine" ]]; then
    export WINE="$PROTON_DIR/dist/bin/wine"
  fi

  winetricks -q $PROTON_WINETRICKS || true
fi

# --- Autoclick background ---
/usr/local/bin/autoclick.sh &

# --- Start dedicated server with the correct args ---
# IMPORTANT: use disable_steam=1
echo "[srv] Launching DedicatedServer.exe via Proton..."
cd /home/container/bin

# Helpful for debugging Proton issues (creates proton logs)
# export PROTON_LOG=1

exec "$PROTON_DIR/proton" run ./DedicatedServer.exe disable_steam=1