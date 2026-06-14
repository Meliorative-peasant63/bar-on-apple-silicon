#!/bin/bash
# Diagnostic launcher: same zink env as run-bar-online.sh + verbose driver logging,
# launching a reproducible OFFLINE skirmish (data/skirmish.txt) instead of the lobby.
# Set DebugGL=1 in springsettings.cfg first so zink's real per-call GL errors surface
# through the engine's GL_KHR_debug callback (this is how the in-game bugs were found).
export WINE="/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine"
export WINEPREFIX="$HOME/BAR-on-mac/wineprefix"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="opengl32=n"
export GALLIUM_DRIVER=zink
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLSL_VERSION_OVERRIDE=460
export MVK_CONFIG_USE_METAL_PRIVATE_API=1
# verbose driver logging
export MESA_DEBUG=1
export MVK_CONFIG_LOG_LEVEL=3
ENG='C:\users\'"$USER"'\AppData\Local\Programs\Beyond-All-Reason\data\engine\recoil_2025.06.24'
DATA='C:\users\'"$USER"'\AppData\Local\Programs\Beyond-All-Reason\data'
cd "$WINEPREFIX/drive_c/users/$USER/AppData/Local/Programs/Beyond-All-Reason/data/engine/recoil_2025.06.24" || exit 1
exec "$WINE" "$ENG\\spring.exe" --write-dir "$DATA" "$DATA\\skirmish.txt"
