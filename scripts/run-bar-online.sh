#!/bin/bash
# BAR online/lobby under Wine using the official launcher's content (byar game +
# byar-chobby + engine recoil_2025.06.24), rendered via patched zink. Connects to
# BAR's server; log in with your account. (The launcher's Electron UI renders blank
# under this Wine, so we launch the engine directly — lobby/login/battle-list still work.)
export WINE="/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine"
export WINEPREFIX="$HOME/BAR-on-mac/wineprefix"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="opengl32=n"            # use OUR opengl32.dll (zink), not Wine's
export GALLIUM_DRIVER=zink
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLSL_VERSION_OVERRIDE=460
export MVK_CONFIG_USE_METAL_PRIVATE_API=1
export ALSOFT_CONF="C:\\users\\$USER\\AppData\\Local\\Programs\\Beyond-All-Reason\\data\\engine\\recoil_2025.06.24\\alsoft.ini"
# BAR's content CDN (springrts.com defaults fail for BAR maps/games):
export PRD_HTTP_SEARCH_URL="https://files-cdn.beyondallreason.dev/find"        # maps
export PRD_RAPID_REPO_MASTER="https://repos-cdn.beyondallreason.dev/repos.gz"  # games
export PRD_RAPID_USE_STREAMER=false                                            # static CDN
ENG='C:\users\'"$USER"'\AppData\Local\Programs\Beyond-All-Reason\data\engine\recoil_2025.06.24'
DATA='C:\users\'"$USER"'\AppData\Local\Programs\Beyond-All-Reason\data'
cd "$WINEPREFIX/drive_c/users/$USER/AppData/Local/Programs/Beyond-All-Reason/data/engine/recoil_2025.06.24" || exit 1
exec "$WINE" "$ENG\\spring.exe" --write-dir "$DATA" --menu "rapid://byar-chobby:test"
