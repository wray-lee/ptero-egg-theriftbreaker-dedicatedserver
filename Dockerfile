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