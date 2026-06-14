#!/bin/bash
# Run the official BAR Windows launcher under Wine. zink env is inherited by the
# engine the launcher spawns; --disable-gpu keeps Electron's Chromium on software.
# Mainly useful as a content downloader (its UI renders blank under this Wine).
export WINE="/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine"
export WINEPREFIX="$HOME/BAR-on-mac/wineprefix"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="opengl32=n"
export GALLIUM_DRIVER=zink
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLSL_VERSION_OVERRIDE=460
export MVK_CONFIG_USE_METAL_PRIVATE_API=1
LAUNCHER='C:\users\'"$USER"'\AppData\Local\Programs\Beyond-All-Reason\Beyond-All-Reason.exe'
exec "$WINE" "$LAUNCHER" --disable-gpu
