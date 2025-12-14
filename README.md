# The Riftbreaker Dedicated Server on Pterodactyl (Proton + Headless GUI Autostart)

The Riftbreaker dedicated server currently launches a **GUI window** and requires pressing **“Start game”**. That’s a problem on Pterodactyl, because the server runs inside a headless container with no interactive desktop.

This repo shows a working, repeatable approach:

- Run the Windows server using **Proton**
- Provide a virtual display using **Xvfb**
- Make window focus reliable using **openbox**
- Automatically press **Start game** using **xdotool**
- Fix common path/runtime issues encountered in containers

If you follow this README, you end up with a dedicated server that boots automatically on Pterodactyl without needing VNC/desktop access.

---

## What you get

- ✅ Fully headless start (no GUI interaction needed)
- ✅ “Start game” gets pressed automatically
- ✅ Steam init issues avoided (using the correct launch flag)
- ✅ Relative asset path issues solved (symlink fix)
- ✅ Works with an empty Pterodactyl STARTUP line if you want (entrypoint handles launch)

---

## Why the server fails in containers (and what we fix)

### 1) Steam initialization error
If you start the exe “raw”, it may complain it can’t initialize Steam services.

Fix: launch with the argument:

    disable_steam=1

### 2) No display available
The server opens a window. In a container there is no X server.

Fix: run a virtual X server:

    Xvfb :0 ...

### 3) Window cannot be focused/clicked reliably
Wine/Proton windows can be hard to focus under pure Xvfb without a window manager.

Fix: start a tiny WM:

    openbox &

### 4) “Missing file gui/locale.kvp” and similar
When you run from `/home/container/bin`, the process may look for assets relative to that directory (e.g. `bin/gui/...`) even though the real folders are one level up (`/home/container/gui/...`).

Fix: create symlinks in `bin/`:

    bin/gui   -> ../gui
    bin/packs -> ../packs
    bin/data  -> ../data

### 5) X socket directory errors
Some images/logs show errors like `_XSERVTransmkdir` or warnings about `/tmp/.X11-unix`.

Fix: ensure socket directories exist *before* Xvfb starts, and set correct perms.

---

## Pterodactyl overview

This approach is designed so you can keep the Pterodactyl STARTUP line empty (`''`) if you want.
The entrypoint script starts everything (Xvfb, autoclicker, Proton command).

If you prefer to use Pterodactyl’s STARTUP field, you can: just move the Proton command into STARTUP and keep the rest in entrypoint. Either way works.

---

## Environment variables (recommended)

Steam install/update:
- SRCDS_APPID=4114030
- WINDOWS_INSTALL=1
- AUTO_UPDATE=1          (set 0 to disable updates at boot)

Headless display:
- XVFB=1
- DISPLAY=:0
- DISPLAY_WIDTH=1024
- DISPLAY_HEIGHT=768
- DISPLAY_DEPTH=16

Autoclicker:
- AUTOCLICK=1
- AUTOCLICK_TIMEOUT=90
- AUTOCLICK_WINDOW_REGEX=The Riftbreaker: Dedicated Server|Dedicated Server
- AUTOCLICK_FALLBACK_CLICK=1

Optional runtime helpers (only if needed):
- WINETRICKS_RUN=vcrun2022

---

## Docker image

Below is an example Dockerfile that layers these tools onto a Pterodactyl-compatible base. Adjust the FROM line to match the base you already use (or your own working Proton base).

### Dockerfile (example)
```
  FROM ghcr.io/ptero-eggs/yolks:debian_trixie
  
  ENV DEBIAN_FRONTEND=noninteractive
  
  # Base deps: Xvfb + click tools + winetricks deps + 32-bit libs + common runtime libs
  RUN dpkg --add-architecture i386 \
   && apt update -y \
   && apt install -y --no-install-recommends \
      ca-certificates curl wget unzip tar xz-utils \
      python3 procps iproute2 \
      xvfb xauth x11-utils openbox xdotool wmctrl \
      winbind libntlm0 \
      cabextract \
      libgl1 libgl1:i386 libgl1-mesa-dri libgl1-mesa-dri:i386 \
      libvulkan1 libvulkan1:i386 \
      libstdc++6 libstdc++6:i386 \
      libgcc-s1 libgcc-s1:i386 \
   && rm -rf /var/lib/apt/lists/*
  
  RUN apt update -y && apt install -y --no-install-recommends imagemagick && rm -rf /var/lib/apt/lists/*
  RUN apt update -y && apt install -y --no-install-recommends \
      x11vnc novnc websockify \
   && rm -rf /var/lib/apt/lists/*
  
  
  # Winetricks helper
  RUN wget -q -O /usr/sbin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
   && chmod +x /usr/sbin/winetricks
  
  ENV HOME=/home/container
  ENV DISPLAY=:0
  ENV DISPLAY_WIDTH=1024
  ENV DISPLAY_HEIGHT=768
  ENV DISPLAY_DEPTH=16
  
  # Proton + launcher scripts
  COPY entrypoint.sh /entrypoint.sh
  COPY autoclick.sh /usr/local/bin/autoclick.sh
  COPY start-novnc.sh /usr/local/bin/start-novnc.sh
  
  RUN chmod +x /entrypoint.sh /usr/local/bin/autoclick.sh /usr/local/bin/start-novnc.sh
  CMD ["/bin/bash", "/entrypoint.sh"]
```
---

## Scripts

### entrypoint.sh (example)

This entrypoint:
1) runs SteamCMD update (if enabled)
2) starts Xvfb + openbox
3) applies the `bin/` symlink fix for assets
4) starts the autoclicker in the background
5) starts the server using Proton with `disable_steam=1`
```
    #!/bin/bash
    set -euo pipefail

    cd /home/container

    # Prevent Wine/Proton output wrapping badly
    stty columns 250 || true

    echo "Running on Debian $(cat /etc/debian_version)"
    command -v proton >/dev/null 2>&1 && proton --version || true
    command -v wine  >/dev/null 2>&1 && wine --version  || true

    # Make internal Docker IP address available to processes (useful for some games)
    INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
    export INTERNAL_IP

    # Steam credentials handling (optional)
    if [ "${STEAM_USER:-}" = "" ]; then
        echo -e "steam user is not set.\nUsing anonymous user.\n"
        STEAM_USER=anonymous
        STEAM_PASS=""
        STEAM_AUTH=""
    else
        echo "user set to ${STEAM_USER}"
    fi

    # Auto-update via SteamCMD (optional)
    if [ -z "${AUTO_UPDATE:-}" ] || [ "${AUTO_UPDATE}" = "1" ]; then
        if [ -n "${SRCDS_APPID:-}" ]; then
            ./steamcmd/steamcmd.sh \
              +force_install_dir /home/container \
              +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH}" \
              $( [[ "${WINDOWS_INSTALL:-0}" = "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) \
              +app_update "${SRCDS_APPID}" \
              +app_update 1007 \
              +quit
        else
            echo "No appid set. Skipping update."
        fi
    else
        echo "AUTO_UPDATE=0, skipping update."
    fi

    # Ensure X socket dirs exist BEFORE Xvfb starts
    mkdir -p /tmp/.X11-unix /tmp/.ICE-unix
    chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix

    # Start Xvfb if requested
    if [ "${XVFB:-0}" = "1" ]; then
        export DISPLAY="${DISPLAY:-:0}"
        Xvfb "${DISPLAY}" -screen 0 "${DISPLAY_WIDTH:-1024}x${DISPLAY_HEIGHT:-768}x${DISPLAY_DEPTH:-16}" -nolisten tcp -ac &
        sleep 1
    fi

    # Start a lightweight WM for reliable focus
    if command -v openbox >/dev/null 2>&1; then
        openbox >/dev/null 2>&1 &
        sleep 0.5
    fi

    # Ensure prefix exists (some Proton/Wine setups want it)
    mkdir -p "${WINEPREFIX:-/home/container/.wine}"

    # Optional: install winetricks components if your egg uses WINETRICKS_RUN
    # (Only needed if you hit runtime crashes; many setups work without.)
    if [ -n "${WINETRICKS_RUN:-}" ] && command -v winetricks >/dev/null 2>&1; then
        for trick in ${WINETRICKS_RUN}; do
            echo "Installing winetricks component: ${trick}"
            winetricks -q "${trick}" || true
        done
    fi

    # --- Critical fix: symlinks so assets resolve when running from /home/container/bin ---
    for d in gui packs data; do
        if [ -d "/home/container/${d}" ] && [ ! -e "/home/container/bin/${d}" ]; then
            ln -s "../${d}" "/home/container/bin/${d}"
        fi
    done

    # Start autoclicker in background (presses Start game)
    if command -v /usr/local/bin/autoclick.sh >/dev/null 2>&1; then
        /usr/local/bin/autoclick.sh &
    fi

    # Start the dedicated server (Proton) with the required flag
    cd /home/container/bin
    exec proton run DedicatedServer.exe disable_steam=1
```
### autoclick.sh (example)

This script waits for the server GUI to appear and then presses “Start game”.
```
    #!/usr/bin/env bash
    set -euo pipefail

    : "${AUTOCLICK:=1}"
    : "${AUTOCLICK_TIMEOUT:=90}"
    : "${AUTOCLICK_WINDOW_REGEX:=The Riftbreaker: Dedicated Server|Dedicated Server}"
    : "${AUTOCLICK_FALLBACK_CLICK:=1}"

    [ "${AUTOCLICK}" = "1" ] || exit 0

    command -v xdotool >/dev/null 2>&1 || { echo "[autoclick] ERROR: xdotool missing"; exit 1; }

    export DISPLAY="${DISPLAY:-:0}"

    echo "[autoclick] Waiting for window regex: ${AUTOCLICK_WINDOW_REGEX} (timeout ${AUTOCLICK_TIMEOUT}s)"
    WIN_ID=""

    for i in $(seq 1 "${AUTOCLICK_TIMEOUT}"); do
        WIN_ID="$(xdotool search --onlyvisible --name "${AUTOCLICK_WINDOW_REGEX}" 2>/dev/null | head -n1 || true)"
        [ -n "${WIN_ID}" ] && break
        sleep 1
    done

    if [ -z "${WIN_ID}" ]; then
        echo "[autoclick] ERROR: window not found."
        echo "[autoclick] Visible windows:"
        xdotool search --onlyvisible --name "." getwindowname %@ 2>/dev/null || true
        exit 1
    fi

    echo "[autoclick] Found window id: ${WIN_ID}"
    xdotool windowactivate --sync "${WIN_ID}" || true
    sleep 0.3

    # Enter often triggers the default focused button (Start game)
    xdotool key --window "${WIN_ID}" Return || true
    sleep 0.3

    # Optional fallback: click bottom-center (covers many UI layouts)
    if [ "${AUTOCLICK_FALLBACK_CLICK}" = "1" ]; then
        eval "$(xdotool getwindowgeometry --shell "${WIN_ID}" 2>/dev/null || true)"
        if [ -n "${WIDTH:-}" ] && [ -n "${HEIGHT:-}" ]; then
            xdotool mousemove --window "${WIN_ID}" $((WIDTH/2)) $((HEIGHT-30)) click 1 || true
        fi
    fi

    echo "[autoclick] Start action sent."
```
---

## Debugging

### See the real window title
If clicking stops working after an update, the window title likely changed.
Run:

    xdotool search --onlyvisible --name "." getwindowname %@

Update `AUTOCLICK_WINDOW_REGEX` to match.

### Confirm X is running
    pgrep -a Xvfb
    echo "$DISPLAY"

### Confirm autoclicker ran
You should see log lines like:
- [autoclick] Waiting for window regex: ...
- [autoclick] Found window id: ...
- [autoclick] Start action sent.

---

## Summary

This is essentially “GUI automation as infrastructure”:

- Proton runs the Windows dedicated server
- Xvfb provides a display so the GUI can exist in a headless container
- openbox makes focus/activation reliable
- xdotool presses Start game automatically
- `disable_steam=1` prevents Steam service initialization from blocking startup
- symlinks fix missing asset paths when launching from `bin/`

It’s simple, stable, and works well in Pterodactyl where you cannot interact with a GUI window manually.
