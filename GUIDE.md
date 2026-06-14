# Beyond All Reason on an Apple-Silicon Mac (no VM) — Reproduction Report

**Result:** BAR (RecoilEngine) runs **natively under Wine** on an M4 MacBook Air —
lobby, online multiplayer, **and a fully-rendered, playable in-game battle** (terrain,
units, UI), with native CoreAudio and native input. No virtual machine.

**Machine this was done on:** M4 MacBook Air, 16 GB RAM, macOS 26.3.1, Rosetta 2 present.

**The rendering chain:**
```
BAR (Win64 PE, runs under Rosetta) → Mesa opengl32.dll (zink, patched)
   → Wine vulkan-1.dll (winevulkan) → libMoltenVK (private-API) → Metal → Apple M4
```

The whole trick: macOS only gives OpenGL 2.1-compat / 4.1-core natively, but BAR needs
**GL 4.x compatibility**. We get it by routing GL→Vulkan→Metal via **zink**, then fix the
handful of places where zink's Vulkan assumptions don't hold on MoltenVK/Metal.

---

## 0. Prerequisites (host tools, via Homebrew)

```bash
brew install --cask wine-stable          # Wine 11.0; bundles MoltenVK 1.4.1 (needs interactive sudo)
brew install mingw-w64 meson ninja flex bison
pip3 install mako    # or: brew install python-mako
# vulkan-headers only needed if you want to rebuild the probe tools
```

`wine-stable`'s gstreamer `.pkg` dependency needs an **interactive** sudo password — run
the cask install yourself in a terminal. (Whisky is deprecated; don't use it.)

Disk: budget ~10 GB (Wine prefix + Mesa build + BAR content ~2.2 GB).

---

## 1. Wine prefix

```bash
export WINE="/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine"
export WINEPREFIX="$HOME/BAR-on-mac/wineprefix"
"$WINE" wineboot --init        # builds a win64 drive_c
```
Wine Stable 11.0 is x86_64 (runs under Rosetta) and **bundles MoltenVK 1.4.1** at
`/Applications/Wine Stable.app/Contents/Resources/wine/lib/libMoltenVK.dylib`.

**Run Wine commands with the Bash sandbox DISABLED** — Wine spawns wineserver/child
processes that get SIGKILL (137) under a sandbox.

---

## 2. Swap in the private-API MoltenVK (fixes logicOp / wideLines)

Stock MoltenVK reports `logicOp=0, wideLines=0`, which blocks zink at startup. UTM ships a
MoltenVK built with `MVK_CONFIG_USE_METAL_PRIVATE_API` that reports them as 1. Borrow its
x86_64 slice:

```bash
WINE_MVK="/Applications/Wine Stable.app/Contents/Resources/wine/lib/libMoltenVK.dylib"
cp "$WINE_MVK" "$HOME/BAR-on-mac/wine-libMoltenVK-stock.backup"     # backup first
UTM_MVK="/Applications/UTM.app/Contents/Frameworks/MoltenVK.framework/Versions/A/MoltenVK"
lipo "$UTM_MVK" -thin x86_64 -output /tmp/mvk-x64.dylib
cp /tmp/mvk-x64.dylib "$WINE_MVK"
codesign --force --sign - "$WINE_MVK"        # ad-hoc re-sign after editing
```
(Requires UTM.app installed for its MoltenVK framework. With the private-API build,
`logicOp`/`wideLines` default ON — no env var needed.)

---

## 3. Cross-build patched Mesa (zink) for Windows

### 3a. Get Mesa 25.1.9 source
`~/BAR-on-mac/wine-mesa/mesa-25.1.9` (git tag `mesa-25.1.9`).
**Why 25.1.9:** newest branch where zink does *not* hard-require the `nullDescriptor`
robustness2 feature (which MoltenVK reports false). 26.x fails with
`Zink requires the nullDescriptor feature`.

### 3b. Apply ALL the patches (see section 4 for the full list)

### 3c. Cross file — `~/BAR-on-mac/mingw-x64.cross`
```ini
[binaries]
c = 'x86_64-w64-mingw32-gcc'
cpp = 'x86_64-w64-mingw32-g++'
ar = 'x86_64-w64-mingw32-ar'
strip = 'x86_64-w64-mingw32-strip'
windres = 'x86_64-w64-mingw32-windres'
exe_wrapper = ''

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
```

### 3d. Configure + build
```bash
cd ~/BAR-on-mac/wine-mesa/mesa-25.1.9
meson setup build-win --cross-file ~/BAR-on-mac/mingw-x64.cross \
  -Dbuildtype=release \
  -Dgallium-drivers=zink -Dvulkan-drivers= -Dplatforms=windows -Dopengl=true \
  -Dgles1=disabled -Dgles2=disabled -Degl=disabled -Dglx=disabled -Dglvnd=false \
  -Dshared-glapi=enabled -Dllvm=disabled -Dshader-cache=disabled \
  -Dvalgrind=disabled -Dlibunwind=disabled \
  -Dgallium-va=disabled -Dgallium-vdpau=disabled -Dgallium-xa=disabled \
  -Dgallium-nine=false -Dzstd=disabled
ninja -C build-win
```
**CRUCIAL:** leave `gallium-wgl-dll-name` at its default `libgallium_wgl` — do **not** set
it to `opengl32` (that builds the wrong-facing DLL → SDL "Could not retrieve OpenGL
functions"). No Rust/LLVM needed for zink. zlib comes from a meson subproject.

### 3e. Outputs + runtime dep — copy into the engine dir (see §5 for path)
```
build-win/src/gallium/targets/libgl-gdi/opengl32.dll      (~538 KB, app-facing)
build-win/src/gallium/targets/wgl/libgallium_wgl.dll      (~40 MB, the zink driver)
build-win/subprojects/zlib-1.3.1/libz-1.dll               (libgallium_wgl imports it!)
```
All three must land next to BAR's `spring.exe`. (The engine ships `zlib1.dll`, a *different*
name — `libz-1.dll` is still required.)

Incremental rebuilds after editing a patch:
```bash
ninja -C build-win src/gallium/targets/wgl/libgallium_wgl.dll \
                   src/gallium/targets/libgl-gdi/opengl32.dll
```

---

## 4. The patches (all in zink) — THIS is the miracle

Two patch sets. Set A makes the **lobby** render (Session 2/4). Set B makes the **in-game
battle** render (Session 5 — the breakthrough this report is named for).

### Set A — `~/BAR-on-mac/mesa-bar-patches.diff` (zink hunks only)
Apply the **zink-only** subset (the 4 zink files; the venus/x11 hunks are for the VM and
aren't built for Windows). These fix:
- **MoltenVK quirks** (`zink_screen.c`): `have_triangle_fans=false`; drop
  `EXT_shader_demote_to_helper_invocation` (host SPIRV-Cross targets MSL < 2.3). Detected
  via `zink_driverid(screen) == VK_DRIVER_ID_MOLTENVK`.
- **Varying link by location+component** (`zink_compiler.c`): Metal links varyings by
  location+component; zink split FS inputs into per-component groups → MSL "input not
  written by vertex shader" → pipeline INITIALIZATION_FAILED. Fix merges groups and expands
  user varyings to vec4 @ component 0.
- **Skip draw on failed pipeline** (`zink_draw.cpp`): otherwise falls into the unsupported
  shader-object bind path and segfaults (PC=0).
- **Pipeline debug dump** (`zink_pipeline.c`): diagnostic, keep.

```bash
cd ~/BAR-on-mac/wine-mesa/mesa-25.1.9
# extract the 4 zink-file hunks (lines 1-152 of the diff in this repo) to /tmp/zink-only.diff
patch -p1 < /tmp/zink-only.diff
```

### Set B — Session-5 patches (the two that fixed the black screen + magenta terrain)

These are **already applied** in `~/BAR-on-mac/wine-mesa/mesa-25.1.9`. If reproducing from
clean source, add both:

**B1 — depth-buffer allocation (`src/gallium/drivers/zink/zink_screen.c`).** Fixes the
**fully-black in-game screen.** MoltenVK can't allocate depth/stencil images with
`VK_IMAGE_USAGE_HOST_TRANSFER_BIT_EXT` (from `EXT_host_image_copy`); every
`glTexImage(GL_DEPTH_COMPONENT*)` then fails `GL_OUT_OF_MEMORY`, leaving all
depth-attachment FBOs incomplete → all clears/draws/blits rejected → black. zink's own
guard for this is behind `#if defined(MVK_VERSION)`, which is **compiled out** in a
winevulkan build (zink links `vulkan-1.dll`, not MoltenVK headers). So disable the
extension outright for MoltenVK, detected at runtime by driver ID.

Find, near the end of the function that ends with the `resizable_bar` check (~line 3034):
```c
   if (!screen->resizable_bar)
      screen->info.have_EXT_host_image_copy = false;
```
…and add immediately after it:
```c
   /* MoltenVK cannot allocate depth/stencil images with VK_IMAGE_USAGE_HOST_TRANSFER_BIT_EXT:
    * every glTexImage on a depth format fails with OUT_OF_MEMORY, leaving all depth-attachment
    * FBOs incomplete (black screen in-game). The MVK_VERSION-gated workaround in zink_resource.c
    * is compiled out under winevulkan, so disable the extension outright for MoltenVK. It is only
    * a staging-upload optimization; the normal staging path works. (BAR-on-mac patch) */
   if (zink_driverid(screen) == VK_DRIVER_ID_MOLTENVK)
      screen->info.have_EXT_host_image_copy = false;
```

**B2 — MSL reserved-name collision (`src/gallium/drivers/zink/zink_compiler.c`).** Fixes the
**magenta terrain.** A shader resource named `sampler` makes SPIRV-Cross emit
`texture2d<float> sampler`, which shadows Metal's built-in `sampler` type → the ground
shader's pipeline won't compile → terrain falls back to magenta. The name arrives as an
`OpName` SPIRV-Cross reuses, so rename any colliding variable before SPIR-V emission.

In `compile_module()`, immediately before `struct spirv_shader *spirv = nir_to_spirv(...)`:
```c
   /* BAR-on-mac: MoltenVK/SPIRV-Cross emits invalid MSL when a shader resource is
    * named after an MSL reserved type (e.g. a sampler literally named "sampler" ->
    * "texture2d<float> sampler" shadows the MSL 'sampler' type). Rename colliding vars. */
   {
      static const char *const msl_reserved[] = {
         "sampler", "texture", "device", "constant", "thread", "threadgroup",
         "vertex", "fragment", "kernel", "access", "half", "ushort", "uchar",
      };
      nir_foreach_variable_in_shader(var, nir) {
         if (!var->name)
            continue;
         for (unsigned i = 0; i < ARRAY_SIZE(msl_reserved); i++) {
            if (!strcmp(var->name, msl_reserved[i])) {
               var->name = ralloc_asprintf(nir, "%s_znk", var->name);
               break;
            }
         }
      }
   }
```

Rebuild (§3d incremental) and redeploy the two DLLs (§3e) after each patch.

---

## 5. Get BAR (use the official Windows launcher as a downloader)

```bash
# Install the official BAR launcher under Wine (silent), then let it download content:
"$WINE" /path/to/Beyond-All-Reason-1.2988.0.exe /S
```
- Installs to
  `wineprefix/drive_c/users/$USER/AppData/Local/Programs/Beyond-All-Reason/`.
- It **downloads** engine `recoil_2025.06.24` + `byar` game (~2.2 GB) + `byar-chobby`.
- Its Electron/Chromium UI renders **blank** under this Wine (only the titlebar draws), so
  it's usable as a *downloader* but not as the live UI — we launch the engine directly.
- Then copy the three Mesa DLLs (§3e) into:
  `.../Beyond-All-Reason/data/engine/recoil_2025.06.24/`

---

## 6. Engine config + Chobby fixes

In `.../Beyond-All-Reason/data/`:

- **`springsettings.cfg`** — the only setting that actually matters here is the audio one:
  ```
  UseSDLAudio = 0
  DebugGL = 0
  ```
  **Note:** the *actual working setup this guide is based on* leaves **deferred rendering at
  its default (ON)** — `AllowDeferredMapRendering`/`AllowDeferredModelRendering` are `1`, and
  it renders fine and smooth. During diagnosis we tried forcing the forward path
  (`AllowDeferred*Rendering = 0`) to fix the black screen; it **didn't** help — the real fix
  was the two Session-5 zink patches (§4 Set B). So you do **not** need to disable deferred
  rendering. (`DebugGL = 0` is just the default; set it to `1` only when debugging, see §7.)
- **Smooth audio:** with `UseSDLAudio = 0` (above) OpenAL Soft drives Wine's audio directly
  instead of through an SDL loopback buffer, so its buffer settings apply. Create
  `.../engine/recoil_2025.06.24/alsoft.ini` to give it a deep, multi-period buffer (kills
  the Rosetta-load crackle; ~85 ms latency, fine for an RTS):
  ```ini
  [general]
  frequency = 48000
  period_size = 1024
  periods = 4
  ```
  Point OpenAL Soft at it via `ALSOFT_CONF` in the launcher (§7). Bump `period_size` to 2048
  if any crackle remains.
- **Chobby (only needed for the raw-engine lobby, not the launcher's content):**
  `LuaSocketEnabled = 1`, and a `chobby_config.json` with `"game":"byar"` at both
  `data/` and `data/LuaMenu/`. The launcher's content already includes this.

---

## 7. Launch scripts

### `~/BAR-on-mac/run-bar-online.sh` (normal play — online + skirmish)
```bash
#!/bin/bash
export WINE="/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine"
export WINEPREFIX="$HOME/BAR-on-mac/wineprefix"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="opengl32=n"        # use OUR opengl32.dll (zink), not Wine's
export GALLIUM_DRIVER=zink
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLSL_VERSION_OVERRIDE=460
export MVK_CONFIG_USE_METAL_PRIVATE_API=1
export ALSOFT_CONF='C:\users\'"$USER"'\AppData\Local\Programs\Beyond-All-Reason\data\engine\recoil_2025.06.24\alsoft.ini'  # smooth audio (§6)
# BAR's content CDN (springrts.com defaults fail for BAR maps/games):
export PRD_HTTP_SEARCH_URL="https://files-cdn.beyondallreason.dev/find"        # maps
export PRD_RAPID_REPO_MASTER="https://repos-cdn.beyondallreason.dev/repos.gz"  # games
export PRD_RAPID_USE_STREAMER=false                                            # static CDN
ENG='C:\users\'"$USER"'\AppData\Local\Programs\Beyond-All-Reason\data\engine\recoil_2025.06.24'
DATA='C:\users\'"$USER"'\AppData\Local\Programs\Beyond-All-Reason\data'
cd "$WINEPREFIX/drive_c/users/$USER/AppData/Local/Programs/Beyond-All-Reason/data/engine/recoil_2025.06.24" || exit 1
exec "$WINE" "$ENG\\spring.exe" --write-dir "$DATA" --menu "rapid://byar-chobby:test"
```

### `~/BAR-on-mac/run-bar-debug.sh` (diagnostics only)
Same env + `MESA_DEBUG=1 MVK_CONFIG_LOG_LEVEL=3`, and launches a reproducible offline
skirmish via a start script instead of the lobby:
```bash
exec "$WINE" "$ENG\\spring.exe" --write-dir "$DATA" "$DATA\\skirmish.txt"
```
The start script `data/skirmish.txt` (GameType=`Beyond All Reason test-30368-d10579c`,
MapName=`Ravaged Remake v1.2`, AI=`NullAI` 0.1, with
`IsHost=1; HostIP=127.0.0.1; HostPort=8452;`) lets you reproduce in-game rendering with no
clicking — invaluable for debugging. Set `DebugGL=1` in springsettings.cfg first so zink's
real per-call GL errors surface through the engine's `GL_KHR_debug` callback (this is how
the two Session-5 bugs were found).

---

## 8. Play

```bash
~/BAR-on-mac/run-bar-online.sh        # lobby loads → log in → join an 8v8 → it renders
```
Online connects directly to `server4.beyondallreason.info:8200` (liblobby); battle list,
chat, login, and in-lobby map/game auto-download all work with the CDN env above.

---

## What renders / what doesn't

**Works:** terrain, unit & feature models, selection rings, water (forward), the full HUD
(build menu, resource bars, minimap, commander panel), CoreAudio, native input. Smooth.

**Still missing (cosmetic, expected):** anything that uses an **OpenGL geometry shader** —
Metal has no geometry-shader stage (`GL_MAX_GEOMETRY_OUTPUT_VERTICES = 0`), and neither
MoltenVK nor zink emulates one. Casualties: unit icons, health bars, selection-range rings,
some particle effects, PIP minimap-icons. These widgets detect no-GS and disable themselves;
they don't affect playability. (BAR upstream is incrementally removing GS use.)

---

## File manifest (what persists on disk)

| Path | What |
|---|---|
| `~/BAR-on-mac/wineprefix/` | the win64 Wine prefix |
| `~/BAR-on-mac/wine-mesa/mesa-25.1.9/` | patched Mesa source + `build-win/` |
| `~/BAR-on-mac/mesa-bar-patches.diff` | Set-A patches (zink + venus/x11; use zink hunks) |
| `~/BAR-on-mac/mingw-x64.cross` | meson cross file |
| `~/BAR-on-mac/wine-libMoltenVK-stock.backup` | original Wine MoltenVK (to revert §2) |
| `~/BAR-on-mac/run-bar-online.sh` | normal-play launcher |
| `~/BAR-on-mac/run-bar-debug.sh` + `data/skirmish.txt` | diagnostic skirmish launcher |
| `.../Beyond-All-Reason/data/engine/recoil_2025.06.24/{opengl32,libgallium_wgl,libz-1}.dll` | deployed patched zink |
| `~/BAR-on-mac/ATTEMPT-LOG.md` | full chronological log incl. dead ends |

**To revert the MoltenVK swap:** restore `wine-libMoltenVK-stock.backup` and re-sign.
**To rebuild zink after a patch:** edit source → `ninja -C build-win …` → recopy DLLs.
