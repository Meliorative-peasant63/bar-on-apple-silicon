#!/bin/bash
# Quiet skirmish launcher (no MESA_DEBUG spam) for iterating on widget ports.
# Runs the reproducible offline skirmish in data/skirmish.txt.
export WINE="/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine"
export WINEPREFIX="$HOME/BAR-on-mac/wineprefix"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="opengl32=n"
export GALLIUM_DRIVER=zink
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLSL_VERSION_OVERRIDE=460
export MVK_CONFIG_USE_METAL_PRIVATE_API=1
export ALSOFT_CONF="C:\\users\\$USER\\AppData\\Local\\Programs\\Beyond-All-Reason\\data\\engine\\recoil_2025.06.24\\alsoft.ini"
ENG='C:\users\'"$USER"'\AppData\Local\Programs\Beyond-All-Reason\data\engine\recoil_2025.06.24'
DATA='C:\users\'"$USER"'\AppData\Local\Programs\Beyond-All-Reason\data'
cd "$WINEPREFIX/drive_c/users/$USER/AppData/Local/Programs/Beyond-All-Reason/data/engine/recoil_2025.06.24" || exit 1
exec "$WINE" "$ENG\\spring.exe" --write-dir "$DATA" "$DATA\\skirmish.txt"
