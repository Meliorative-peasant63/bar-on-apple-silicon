# BAR on M4 Air — attempt log

Goal: play Beyond All Reason on an M4 MacBook Air (16 GB, macOS 26.3.1)
via a Linux ARM64 VM with GPU-accelerated rendering.

---

# Session 6 (2026-06-13, night) — GEOMETRY-SHADER WIDGETS PORTED TO INSTANCING (minimap blips + healthbars work)

## Headline: the GS-using eye-candy widgets (minimap unit-blips, healthbars) now render
## under Wine on the M4, by porting their geometry shaders to instanced vertex-shader quads.
Session 5 left the GS widgets dead (Metal has no GS stage). This session **confirmed that's
a hard MoltenVK limit, then worked around it per-widget** by rewriting each geometry shader
as instanced quad expansion. Minimap blips + healthbars confirmed working by the user in live
online play (the write-dir overrides load into the real game, not just the test skirmish).

## Proof the GS gap is real, not self-inflicted (empirical, this session)
Built `/tmp/gsprobe.exe` (win64 Vulkan, uses `vulkan-1.dll`) and ran under Wine with our
private-API MoltenVK. Reports for **Apple M4**: `geometryShader = 0`, `maxGeometryOutputVertices
= 0`, **with AND without `MVK_CONFIG_USE_METAL_PRIVATE_API`**; `tessellationShader = 1` (MVK
emulates tessellation via compute, but never implemented compute-based GS emulation). zink
`zink_screen.c:511` just mirrors that bit (`if (!feats.features.geometryShader)` → GL max-output
0), which is the `GL_MAX_GEOMETRY_OUTPUT_VERTICES = 0` that Mesa's GLSL frontend rejects every
GS with (fails *before* SPIR-V/Metal). So there is no flag/private-API to enable GS — the only
fix is removing GS from the widgets. (This corrects the lingering "maybe it's off for no reason"
question — it is genuinely absent.)

## The port pattern (GS billboard → hardware instancing)
For each GS that expanded a point into a quad: fold the quad-emit into the **vertex shader**
(corner from a small static per-vertex corner buffer), delete the `geometry` stage, switch the
per-item data buffer from `AttachVertexBuffer`→`AttachInstanceBuffer`, add a static corner VBO
as the vertex buffer, and change `DrawArrays(GL.POINTS, n)` → `DrawArrays(GL.TRIANGLE_STRIP, V,
0, n)` (instanced). **CRUCIAL GOTCHA:** a `gl_VertexID`-only draw with *no* vertex buffer bound
**hard-crashes MoltenVK** (invalid Metal draw, no log) — you MUST bind a real corner vertex
buffer. (First icon attempt crashed at the first icon draw for exactly this reason.)

## What was ported (write-dir widget overrides; load over the archive copies)
- **`gui_pip.lua`** (minimap) — all 4 GS blocks ported, no GS left:
  - icon shader (unit blips) — `max_vertices=4` billboards → instanced; 3 VAOs (mobile/bldg/
    slow), 6 draw calls. Fixes the `gui_pip.lua:10730 vbo nil` cascade (was downstream of the
    icon GS compile-fail).
  - circle shader (range/selection rings), quad shader, decal shader — same pattern, share a
    4-corner VBO (`gl4Prim.cornerVBO`; decals use location 4 since their instance data is 0-3).
- **`gui_healthbars_gl4.lua`** + **`LuaUI/Shaders/HealthbarsGL4_ported.vert.glsl`** (new file,
  referenced via `vssrcpath`; `gssrcpath` removed). The healthbar GS is the hard one: per unit
  it emits *multiple* primitives (bg + colored backing + foreground bar) **plus a data-dependent
  number of glyph quads** (unit icon, %, stockpile digits, reload/EMP timers), `max_vertices=64`.
  Reimplemented as a **fixed-budget instanced strip of 58 verts**: 28 for the 3 bar sub-strips
  (8+bridge+8+bridge+8, degenerate-bridged) + 5 glyph slots × 6 verts (2-vert degenerate bridge
  + 4-vert quad). Inactive glyph slots collapse to the previous real vertex (`prevLast`) so they
  contribute zero-area triangles — no stray geometry. The VS faithfully recomputes the GS math
  (emitVertexBG / emitVertexBarBG / emitGlyph). `BAR_STRIP_VERTS = 58`.

## Gotchas that cost cycles (don't repeat)
- **MoltenVK no-vertex-buffer instanced draw = silent hard crash** (see above). Bind a corner VBO.
- **`active` is a GLSL reserved word** — `bool active` in the glyph code failed to compile
  (`illegal use of reserved word 'active'`). Renamed to `slotActive`. The failure was masked at
  first by BAR's **shader cache** serving the older bars-only compile (looked like success=true);
  a source change (or cache clear) forces a real recompile that exposed it. Always confirm the
  `recompiled in N ms ... success, true` line is a *fresh* compile of the current source.
- **The autonomous skirmish harness crashes at the first instanced icon draw** (~f=26) even
  though the **identical widget renders fine in the user's live game** — so it's a scripted-
  skirmish quirk, not a widget bug. To test a widget in isolation, deploy ONLY that override and
  leave the stock (GS-failing-but-stable) pip in place; the stock pip runs the skirmish to f≈900.
- **Bars hide at full health by design** — with a do-nothing AI (NullAI) nothing takes damage, so
  no bars show. Force `shaderConfig.DEBUGSHOW = 1` to make all bars visible for testing (REMOVE
  before final — default behavior is bars only when building / below full health).

## Test harness (this session)
- `~/BAR-on-mac/run-bar-skirmish.sh` (quiet, no `MESA_DEBUG`) launches `data/skirmish.txt`
  (set `StartPosType=0` for immediate fixed-position spawn — `=2` adds a ~30s start-box wait).
  `run-bar-debug.sh` is the noisy `MESA_DEBUG=1` variant (use to surface real per-call GL errors).
- Editable widget copies kept at `~/BAR-on-mac/pip-port/` (`gui_pip.lua`, `gui_healthbars_gl4.lua`,
  `HealthbarsGL4_ported.vert.glsl`, plus `.orig` pristine baselines). Deploy to write-dir
  `…/Beyond-All-Reason/data/LuaUI/{Widgets,Shaders}/`. Verify via `[PIP-PORT]`/`[HB-PORT]` Echo
  markers in infolog.

## Also this session
- Launched BAR online (lobby/server connect) and moved it to the **external Dell P2720D**: the
  Chobby lobby hardcodes `lobby_fullscreen=1` (borderless on the *primary* display) and re-applies
  its stored video settings ~3s after launch, overriding `springsettings.cfg` window pos. Clean
  fix = make the **Dell the macOS primary display** (CoreGraphics: set its origin to (0,0); built
  `/tmp/setprimary`), so BAR's borderless-fullscreen lands there for both lobby and in-game.

## Status / what remains (cosmetic, out of scope)
Minimap (blips/icons + range-circles + decals) and healthbars (bars + on-bar numbers) all render,
no GS left in either widget. **One unrelated widget still fails**: `DrawPrimitiveAtUnits GL4`
(`Failed to compile DecalsGL4 GL4`) is a *separate* GS-using widget not touched here (would need
the same instancing port if wanted). Overrides are version-pinned to the installed game content
and will be shadowed by a BAR content update (BAR upstream is removing GS use centrally).

---

# Session 5 (2026-06-13, evening) — IN-GAME RENDERS: black screen + magenta terrain FIXED (2 zink patches)

## Headline: BAR is now PLAYABLE in-game under Wine on the M4 — terrain, units, UI all render, smooth.
First time an actual battle (not just the lobby) renders. Fixed with **two small zink
patches**, rebuilt in `~/BAR-on-mac/wine-mesa` and deployed to the engine dir.

## Symptom chain (what the user hit)
- Online 8v8 AND offline skirmish: game **loads + sim runs** (frames advance, chat/AI
  work) but the screen is **fully black** (world AND BAR's own UI). Lobby renders fine.
- Ruled out by config (all disproven, NOT the cause): deferred rendering (forced forward
  via `AllowDeferred{Map,Model}Rendering=0` + disabling the "Deferred rendering GL4"/
  "Bloom Shader Deferred"/"Distortion GL4" widgets in `LuaUI/Config/BYAR.lua` order=0),
  shadows, MSAA (`AllowMultiSampledFrameBuffers`/`MSAALevel` default 0 already), water.
  Still black ⇒ not a config problem.

## How it was diagnosed (the key move)
Set engine **`DebugGL = 1`** (springsettings.cfg) → engine registers a GL_KHR_debug
callback that surfaces zink/Mesa's REAL per-call errors (invisible otherwise), and ran a
**reproducible autonomous skirmish** via a start script (no clicking): `data/skirmish.txt`
(GameType=`Beyond All Reason test-30368-d10579c`, map=Ravaged Remake v1.2, AI=NullAI 0.1,
`IsHost=1; HostIP=127.0.0.1; HostPort=8452`), launched by `~/BAR-on-mac/run-bar-debug.sh`
(= online env + `MESA_DEBUG=1 MVK_CONFIG_LOG_LEVEL=3`, captures stderr). Verbose log showed:
- **27,382× `GL_OUT_OF_MEMORY in glTexImage(GL_DEPTH_COMPONENT16/24/32/32F)`** → every
  depth-attachment FBO incomplete → 8,500+/frame `glClear/glDraw*/glBlitFramebuffer
  incomplete` → world renders into dead FBOs → **black**. (Engine warns `FBO-SHADOW-*`,
  `FBO-*-GBUFFER`, `FBO--MULTISAMPLED`: `GL_FRAMEBUFFER_UNSUPPORTED_EXT`; the color-only
  IconsAtlas FBO worked → it's specifically DEPTH/MRT/MSAA attachments.)
- After depth fix, **magenta terrain** = 2× `vkCreateGraphicsPipelines failed
  VK_ERROR_INITIALIZATION_FAILED` on the SMF ground fragment shader (GL_CLAMP variant),
  MSL error: `must use 'struct' tag to refer to type 'sampler'` — SPIRV-Cross emitted
  `texture2d<float> sampler` (a resource literally named `sampler`) shadowing Metal's
  built-in `sampler` type.

## The two patches (in `~/BAR-on-mac/wine-mesa/mesa-25.1.9`, both zink, rebuilt for win64)
1. **`zink_screen.c`** (after the `resizable_bar` host_image_copy disable): also
   `if (zink_driverid(screen) == VK_DRIVER_ID_MOLTENVK) screen->info.have_EXT_host_image_copy = false;`
   — MoltenVK can't allocate depth images with `VK_IMAGE_USAGE_HOST_TRANSFER_BIT_EXT`;
   zink's own workaround is gated on `#if defined(MVK_VERSION)` which is **compiled out**
   under winevulkan (zink talks to vulkan-1.dll, not MoltenVK headers). Disabling the ext
   (it's just a staging-upload optimization) fixes ALL depth-texture creation. → no more
   black; UI + minimap + units render.
2. **`zink_compiler.c`** (`compile_module`, right before `nir_to_spirv`): rename any
   `nir_foreach_variable_in_shader` var whose name is an MSL reserved word
   (`sampler`,`texture`,`device`,`constant`,`thread`,`threadgroup`,`vertex`,`fragment`,
   `kernel`,`access`,`half`,`ushort`,`uchar`) to `name_znk`. The name rides through as an
   OpName SPIRV-Cross reuses; renaming kills the MSL type collision. → terrain renders.

Rebuild: `ninja -C build-win src/gallium/targets/wgl/libgallium_wgl.dll
src/gallium/targets/libgl-gdi/opengl32.dll`; copy both DLLs to
`.../engine/recoil_2025.06.24/`. `run-bar-online.sh` automatically uses them now.

## Result & what remains (cosmetic only)
Terrain + unit models + selection rings + full UI render; **smooth, playable** (user
confirmed). Remaining (NON-fatal, expected): the **geometry-shader widgets** still bail
(`GL_MAX_GEOMETRY_OUTPUT_VERTICES=0`, Metal has no GS stage) — unit icons, health bars,
selection-range rings, some particles, PIP minimap-icons (~54 GS errors). Also harmless
`glUniform2("sunDirY"/"gameFrames") has 1 components, not 2` spam from an icon widget.
The earlier "geometry shaders are an unfixable wall for the whole game" verdict was WRONG:
GS only powers optional eye-candy; the core renderer needed depth-FBO + MSL-name fixes.

## Audio smoothing (session 5 cont.) — crackle FIXED
Default `UseSDLAudio=1` routes OpenAL Soft → SDL loopback buffer → CoreAudio; under Rosetta
load this underran ("klanky"). Fix: `UseSDLAudio = 0` (OpenAL Soft drives Wine audio
directly) + `alsoft.ini` in the engine dir (`[general] frequency=48000 period_size=1024
periods=4`) pointed to by `ALSOFT_CONF` env in run-bar-online.sh. Device opens fine, audio
smooth (user-confirmed). Bump period_size→2048 if crackle returns.

## Known cosmetic gap: minimap unit blips
BAR's minimap (`gui_pip_minimap.lua`) draws unit icons/circles with geometry shaders
(`[PIP] GL4 icons`/`GL4 circle shader`) → Metal has no GS → minimap shows terrain but no
unit dots. Same GS wall as unit icons/health bars; no config fix (would need rewriting the
minimap-icon widget to instanced quads).

## Strategic update
The in-game blockers were zink↔MoltenVK bugs (fixable, as above), NOT VM-architectural and
NOT requiring a native port. A native macOS port would still hit the same GS gap for the
eye-candy widgets. NEXT: try online 8v8 again (DLLs already deployed); set `DebugGL=0` for
normal play (perf); optionally chase the GS widgets (BAR upstream is removing GS use).

---

# Session 4 (2026-06-13) — Wine native path: crux measured, NATIVE GL is a dead end

Question (see `~/BAR-on-mac/WINE-TASK.md`): can BAR run natively via Wine (no VM)
to get native input + audio? Crux: Wine routes Windows GL somewhere — does that
"somewhere" give BAR a GL 4.x **compatibility** context?

## Empirically measured the macOS GL ceiling (the limit Wine's native path can't beat)

Wrote `/tmp/glprobe.c` (CGL: create contexts, print GL_VERSION/GLSL/RENDERER).
On this M4 / macOS 26.3.1, Apple's OpenGL.framework (now GL-over-Metal,
RENDERER="Apple M4", "Metal - 90.5") gives:
- **legacy/compatibility profile → GL 2.1, GLSL 1.20**
- 3.2-core profile → GL 4.1, GLSL 4.10
- GL4-core profile → **GL 4.1, GLSL 4.10** (no higher)
- i.e. **NO 4.x compatibility profile exists on macOS; best compat ctx is 2.1.**

## BREAKTHROUGH: zink-in-Wine WORKS — GL 4.6 compat on the M4, no VM

Pushed past the verdict and the zink route came up **far more easily than feared
(no Mesa cross-build needed yet)**. Confirmed chain, all native (no VM/venus/SPICE):

  Win64 app → Mesa `opengl32.dll` (zink) → Wine `vulkan-1.dll` (winevulkan)
            → libMoltenVK (private-API) → Metal → Apple M4

Final probe output (`/tmp/wglinfo.exe`, a WGL GL-info tool, run under Wine):
```
GL_VERSION  = 4.6 (Compatibility Profile) Mesa 25.1.9
GLSL        = 4.60
GL_RENDERER = zink Vulkan 1.4 (Apple M4 (MOLTENVK))
```
The three gates, all PASS:
1. **win64 Wine prefix** — `wine-11.0` (x86_64, Rosetta) at `~/BAR-on-mac/wineprefix`,
   `drive_c` built, runs win64 PE exes. Wine Stable 11.0 **bundles MoltenVK 1.4.1**.
2. **Vulkan/MoltenVK in-prefix** — a win64 probe (`/tmp/vkprobe.exe`, built w/
   mingw + `brew vulkan-headers`, uses `vulkan-1.dll`) enumerates **Apple M4**,
   VK 1.4.334. STOCK MoltenVK reports `logicOp=0, wideLines=0` (the session-1
   wall). FIX: swapped Wine's `.../wine/lib/libMoltenVK.dylib` for the **x86_64
   slice of UTM's private-API MoltenVK** (`/Applications/UTM.app/Contents/
   Frameworks/MoltenVK.framework/.../MoltenVK`, universal x86_64+arm64, has
   `MVK_CONFIG_USE_METAL_PRIVATE_API`; `lipo -thin x86_64`, ad-hoc codesign).
   After swap: **`logicOp=1, wideLines=1`** (private API defaults ON, no env needed).
   Wine's stock dylib backed up: `~/BAR-on-mac/wine-libMoltenVK-stock.backup`.
3. **zink GL over MoltenVK** — dropped a **stock Windows Mesa build** (pal1000
   mesa-dist-win) next to the probe, `WINEDLLOVERRIDES=opengl32=n`,
   `GALLIUM_DRIVER=zink`. Mesa **26.1.1 FAILS** (`Zink requires the nullDescriptor
   feature of KHR/EXT robustness2` — the exact session-2 reason). Mesa **25.1.9
   WORKS** → `zink Vulkan 1.4 (Apple M4 (MOLTENVK))`; with
   `MESA_GL_VERSION_OVERRIDE=4.6COMPAT MESA_GLSL_VERSION_OVERRIDE=460` →
   **GL 4.6 Compatibility / GLSL 4.60**. Same non-fatal `EXT_custom_border_color`
   warning as the VM. Mesa win build at `/tmp/mesa2519/x64/` (opengl32.dll +
   libgallium_wgl.dll); test dir `~/BAR-on-mac/wineprefix/drive_c/gltest`.

### What this means
The native-GL path is dead (below) BUT the zink path — same as the VM — runs
**natively under Wine with PREBUILT parts** (stock mesa-dist-win 25.1.9 + reused
UTM private-API MoltenVK). No Mesa cross-build was needed to get a 4.6 compat
context. The "better than VM" bet (native input + CoreAudio, no nested present
lag) is now genuinely in reach.

### BAR ACTUALLY LAUNCHED under Wine — full lobby loads, audio works, ONE crash
Downloaded the Windows x64 engine (RecoilEngine 2025.06.21 release, 22MB:
`spring.exe`+`pr-downloader.exe`+`SDL2.dll`+`OpenAL32.dll`) → `drive_c/bar/engine`,
overlaid Mesa 25.1.9 `opengl32.dll`+`libgallium_wgl.dll`. Fetched BYAR Chobby
content (338MB) via `pr-downloader.exe` — gotchas: BAR's rapid is on its own CDN
**`PRD_RAPID_REPO_MASTER=https://repos-cdn.beyondallreason.dev/repos.gz`** (NOT
springrts.com), and the CDN is **static-only** (no streamer.cgi → 404), so need
**`PRD_RAPID_USE_STREAMER=false`** (direct pool download). Applied the same two
raw-engine Chobby fixes as the VM (`LuaSocketEnabled=1`; `chobby_config.json`
w/ `game:byar` at data/ and data/LuaMenu/). Launch script: `~/BAR-on-mac/run-bar-wine.sh`.

What happened (infolog `drive_c/bar/data/infolog.txt`): engine got
**GL 4.6 (Compat) / zink Vulkan 1.4 (Apple M4 MOLTENVK)**, compiled font shaders,
brought up **native CoreAudio** (`[Sound] OpenAL Soft 1.21.0`, opened "MacBook Air
Speakers", **lobby music played**), loaded the BYAR Chobby archive, ran ALL the
LuaMenu/Chobby widgets (liblobby→BAR server, Battle List, Settings, Login, …),
**showed the SDL window** (`SDL_WINDOWEVENT_SHOWN`), reached `GR::InitGLState` /
first frame — then crashed at t≈2-5s with an Access Violation at **PC=0x0**
(call through a NULL fn pointer; engine's own stacktrace useless: FramePtr=0).
Bisected: crash is NOT audio (persists with `Sound=0 UseEFX=0`).

### ROOT CAUSE = the session-2 MSL varying bug (already patched in the VM)
`winedbg` (breaks first-chance, before the engine handler) surfaced the real error:
```
[mvk-error] VK_ERROR_INITIALIZATION_FAILED: Render pipeline compile failed (Error code 3):
Fragment input(s) `user(locn0_3)` mismatching vertex shader output type(s) or not written by vertex shader.
```
This is **identical** to session-2 patch #6 (`zink_compiler.c`: Metal links varyings
by location+component; zink splits FS inputs into per-component groups the VS
writes as one vec4 → MSL link fail → `vkCreateGraphicsPipelines` INITIALIZATION_FAILED).
The PC=0 crash is what session-2 patch #7 (`zink_draw.cpp`) prevents: on failed
pipeline, stock Mesa falls into the unsupported shader-object bind path → segfault.
**Stock mesa-dist-win 25.1.9 has neither patch.** So Wine hits the EXACT same wall
as the VM, and `~/BAR-on-mac/mesa-bar-patches.diff` (10 files, same Mesa 25.1.9) is
the known fix. No new blocker.

### VERDICT: native Wine path is VIABLE and likely better than the VM
Confirmed working under Wine, no VM: GL 4.6-compat-on-M4 (zink→MoltenVK→Metal),
native audio (CoreAudio), native SDL window/input, full content pipeline + Chobby
lobby logic. The only thing between here and a rendering lobby is **cross-building
Mesa 25.1.9 for Windows with the existing patch diff**. Expected wins over the VM:
no nested software-present (the VM's ~100ms lag source), real audio.

### DONE — patched Mesa 25.1.9 cross-built for Windows → LOBBY RENDERS NATIVELY
Cross-compiled Mesa 25.1.9 + zink patches for win64 from macOS, dropped it in,
and **the BAR Chobby lobby now renders natively under Wine on the M4 — no VM**
(screenshot `/tmp/bar-lobby-wine.png`: BAR logo, left menu, Welcome panel, Vittra
map, Login/Register window; title bar "Wine"; lobby music playing). No crash, no
pipeline failures. THE WINE-TASK GOAL IS MET.

How (reproducible):
- Source: `~/BAR-on-mac/wine-mesa/mesa-25.1.9`, zink-only patch `/tmp/zink-only.diff`
  (= lines 1-152 of mesa-bar-patches.diff: the 4 zink files; venus/x11 hunks
  dropped — not built for Windows). `patch -p1 < /tmp/zink-only.diff` (clean).
- Toolchain: brew `mingw-w64` (`x86_64-w64-mingw32-gcc/g++`), `meson`, `ninja`,
  flex/bison, python-mako. Cross file `/tmp/mingw-x64.cross`.
- Configure (build dir `build-win`): `meson setup ... --cross-file mingw-x64.cross
  -Dgallium-drivers=zink -Dvulkan-drivers= -Dplatforms=windows -Dopengl=true
  -Dgles1/2=disabled -Degl/glx/glvnd=disabled -Dshared-glapi=enabled -Dllvm=disabled
  -Dshader-cache=disabled -Dvalgrind/libunwind=disabled -Dgallium-va/vdpau/xa=disabled
  -Dgallium-nine=false -Dzstd=disabled`. **CRUCIAL: leave gallium-wgl-dll-name at
  default `libgallium_wgl`** — do NOT set it to opengl32 (that builds the wrong-facing
  DLL → SDL "Could not retrieve OpenGL functions"). zlib comes from a meson subproject.
  No Rust/LLVM needed for zink. `ninja -C build-win` (~938 targets, few min).
- Outputs: `build-win/src/gallium/targets/libgl-gdi/opengl32.dll` (538KB, app-facing
  ABI, imports libgallium_wgl.dll) + `build-win/src/gallium/targets/wgl/libgallium_wgl.dll`
  (39.8MB, the patched zink driver). Both → `drive_c/bar/engine/`.
- RUNTIME DEP: libgallium_wgl.dll imports `libz-1.dll` (from the zlib subproject:
  `build-win/subprojects/zlib-1.3.1/libz-1.dll`) — must also be in the engine dir
  (engine ships `zlib1.dll`, different name). Other imports (api-ms-win-crt-*,
  ucrtbase, libwinpthread-1) are satisfied by Wine / the engine's bundled dlls.
- Verified in infolog: `GL 4.6 (Compatibility Profile) Mesa 25.1.9`,
  `zink Vulkan 1.4 (Apple M4 (MOLTENVK))`, pipeline-fail count 0, no crash,
  LuaMenu activated, login window up.

### ONLINE WORKS (session 4 cont.) — login, live battle list, chat, map downloads
Got multiplayer online working under Wine. Path that worked:
- Installed the **official BAR Windows launcher** (`Beyond-All-Reason-1.2988.0.exe`,
  NSIS, from BYAR-Chobby releases) under Wine — `/S` silent install →
  `drive_c/users/youruser/AppData/Local/Programs/Beyond-All-Reason/`. It RUNS and
  downloads content (engine `recoil_2025.06.24` + `byar` game ~2.2GB + `byar-chobby`).
  BUT its **Electron/Chromium UI renders BLANK under this Wine** (only the titlebar
  draws) → can't click "Start Game", and it doesn't auto-launch the engine. So the
  launcher is usable as a *downloader* but not as the live UI.
- WORKAROUND = launch the launcher's engine DIRECTLY with our zink env, pointed at
  the launcher's full-content data dir → `~/BAR-on-mac/run-bar-online.sh`. This
  renders the lobby (patched zink) AND connects to BAR's server: `OnConnected` in
  ~16s, **live battle list** (`[chobby] Showing battle with ID, 4482`), **live #main
  chat**, login works (user logged in, joined an 8v8 room). Online does NOT need the
  spring-launcher loopback — liblobby connects to server4.beyondallreason.info:8200
  directly. (The raw byar-chobby-only engine also connected but took ~4min and lacked
  game content; the launcher's full content + engine 2025.06.24 connects fast.)
- **Map/game downloads when joining a battle**: the engine's in-Chobby pr-downloader
  defaults to springrts.com and FAILS for BAR content (`Download Failed errorID 2`;
  springfiles returns `[]` for BAR maps). FIX = set BAR's CDN env on the engine
  (now baked into run-bar-online.sh): `PRD_HTTP_SEARCH_URL=https://files-cdn.beyondallreason.dev/find`
  (maps), `PRD_RAPID_REPO_MASTER=https://repos-cdn.beyondallreason.dev/repos.gz` +
  `PRD_RAPID_USE_STREAMER=false` (games). Verified: downloaded `supreme_isthmus_v2.1.sd7`
  (144MB) via `pr-downloader.exe --download-map "Supreme Isthmus v2.1"` with that env.
  With these vars set, Chobby's in-lobby "join battle → auto-download map" now works.

### What's NEXT (chase the actual playability win vs the VM)
1. Interactively click around the lobby (login/create account, browse battles) —
   confirm native input latency feels better than the VM's ~100ms.
2. Start a SKIRMISH vs AI (offline, no server) — exercises real gameplay rendering;
   watch for any further missing-feature crashes under battle load (more shaders,
   units, terrain). May surface new zink/MoltenVK gaps to patch.
3. Online: the Windows spring-launcher could own the server connection (the raw
   engine's in-Lua socket is limited, same as VM) — or try manual login first.
4. Polish: VSync/idle-fps for latency; window mode/resolution.
Patched Mesa build tree kept at `~/BAR-on-mac/wine-mesa` (rebuild: `ninja -C build-win`).

## Verdict on the native (winemac.drv) path: DEAD

Wine's `winemac.drv` forwards WGL/GL to this same OpenGL.framework, so a Windows
app gets at most GL 2.1 compat / 4.1 core. BAR/Recoil needs **GL 4.x COMPAT**
(we forced 4.5COMPAT in the VM; Spring's Lua/widgets use compat-profile features).
Fails on BOTH axes (version too low AND no compat profile >3.2). **GPTK/CrossOver
do NOT help** — D3DMetal accelerates D3D11/12 only; a native-GL app falls back to
the same Apple GL 4.1. GPTK's headline feature is irrelevant to BAR (as suspected).

## The only viable Wine route = the SAME chain we built in the VM

GL must go GL→Vulkan→MoltenVK→Metal via **zink**, but now as a **Windows** Mesa
build: drop a patched `opengl32.dll` (Mesa/zink, `MESA_LOADER_DRIVER_OVERRIDE=zink`)
next to BAR's exe, pointed at Wine's `vulkan-1.dll` (winevulkan→MoltenVK). This
means re-fighting the SAME MoltenVK gaps already patched in the VM (logicOp,
wideLines, nullDescriptor, the SPIRV-Cross/MSL varying-link bug, the sync-fd
segfault) — but in a **cross-compiled-for-Windows** Mesa, against whatever MoltenVK
CrossOver/GPTK ships, AND with the engine running as **Win-x64 under Rosetta**
(extra CPU translation the native arm64-linux VM engine doesn't pay).
Trade: gains native input (kills the VM's ~100ms present-loop lag) + audio;
costs a Windows Mesa-zink cross-build (~= the VM Mesa effort) + Rosetta overhead.

## State / setup this session
- Rosetta2 present (`arch -x86_64` works). 31 GB disk free.
- Installed `mingw-w64` (host cross-compiler, kept). 
- `brew install --cask wine-stable` BLOCKED: its gstreamer-runtime `.pkg`
  dependency needs an interactive sudo password (can't supply non-interactively).
  To proceed: run `brew install --cask wine-stable` yourself (interactive sudo),
  or use CrossOver trial (drag-install, no sudo) / Apple GPTK.
- Whisky cask is deprecated/disabled (2026-04-09) — don't use.

## Next steps (gates 1-3 DONE — see BREAKTHROUGH above)
1. ✓ Wine installed (wine-stable 11.0). Prefix `~/BAR-on-mac/wineprefix`.
2. ✓ Vulkan/MoltenVK confirmed in-prefix; private-API MoltenVK swapped in
   (logicOp/wideLines now 1).
3. ✓ zink GL 4.6 compat over MoltenVK confirmed (stock mesa-dist-win 25.1.9).
4. **NEXT: get BAR for Windows and launch it under Wine** with the zink+override
   env. Windows distribution = spring-launcher (Chobby) from beyondallreason.info,
   OR fetch Windows x64 engine via `pr-downloader.exe`. Proven launch env:
   `WINEDLLOVERRIDES=opengl32=n GALLIUM_DRIVER=zink
   MESA_GL_VERSION_OVERRIDE=4.6COMPAT MESA_GLSL_VERSION_OVERRIDE=460`, with Mesa
   25.1.9 `opengl32.dll`+`libgallium_wgl.dll` in the BAR exe's dir. Watch for
   `vkCreateGraphicsPipelines`/MSL link failures on real shaders.
5. IF shaders fail like the VM did: cross-build Mesa 25.1.9 for Windows w/ the
   `~/BAR-on-mac/mesa-bar-patches.diff` patches (mingw). Same version → clean apply.

## How to reproduce the working GL probe (this session's artifacts)
- `export WINE="/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine"`
- `export WINEPREFIX="$HOME/BAR-on-mac/wineprefix"`; test dir
  `$WINEPREFIX/drive_c/gltest` has Mesa 25.1.9 DLLs + `wglinfo.exe`.
- `cd $WINEPREFIX/drive_c/gltest && WINEDEBUG=-all WINEDLLOVERRIDES=opengl32=n
  GALLIUM_DRIVER=zink MESA_GL_VERSION_OVERRIDE=4.6COMPAT
  MESA_GLSL_VERSION_OVERRIDE=460 "$WINE" C:\\gltest\\wglinfo.exe`
- Probes: `/tmp/glprobe.c` (native CGL), `/tmp/vkprobe.c` (win64 Vulkan),
  `/tmp/wglinfo.c` (win64 WGL). **Bash tool must run sandbox-DISABLED for Wine**
  (Wine spawns wineserver/children → SIGKILL 137 under sandbox).
- mingw: `x86_64-w64-mingw32-gcc`; VK headers `$(brew --prefix vulkan-headers)/include`.

---

# Session 3 (2026-06-13, morning) — hostmem cap DEFEATED; BAR no longer crashes

## Headline: the `hostmem=256M` blocker is **solved**. BAR now runs stably.

We did **not** build UTM from source (next-step #1) — full Xcode is required
(CLT only on this Mac; ~40 GB install won't fit in 34 GB free; a from-source
build also re-bundles stock MoltenVK, undoing session 1's 1.4.1 swap). Instead
we took next-step #3: **binary-patch the UTM arm64 slice** — clean, no toolchain,
keeps our patched MoltenVK.

## The patch (what changed on host)

`UTMQemuConfiguration+Arguments.swift` builds the literal Swift String
`"hostmem=256M"` inline as a small string. In `/Applications/UTM.app/Contents/
MacOS/UTM` arm64 slice at **VM addr 0x1001517a4** (= file offset 0x1517a4):

```
0x1517a4  mov  x8, #0x3532        ; "25"   (word1 low16)
0x1517a8  movk x8, #0x4d36, lsl16 ; "6M"
0x1517ac  movk x8, #0xec00, lsl48 ; flag 0xE0 | count 0x0C(=12)
```
`0x4d36` is **unique** in the whole slice → unambiguous target. Patched to
`"hostmem=2G"` (10 chars):
```
0x1517a4  movz x8, #0x4732        ; "2G"
0x1517a8  movk x8, #0x0,    lsl16 ; (cleared)
0x1517ac  movk x8, #0xea00, lsl48 ; flag 0xE0 | count 0x0A(=10)
```
2G = 0x80000000, a valid power-of-two PCI BAR.

**GOTCHA that cost a cycle:** first tried `"2.0G"` (4 chars, keeps count=12,
only 2 immediates change — tempting). QEMU's `hostmem` size parser **rejects
the decimal point** → VM never launches, `utmctl start` returns
**OSStatus -2700 "Operation not available"**, QEMU never spawns, debug.log
not written. Use the integer form `2G`. (Confirmed by A/B: restoring the
original 256M binary booted fine; the 2.0G binary failed identically every time;
2G binary boots.)

## Re-signing (REQUIRED, and a trap)

Editing the Mach-O invalidates the signature → app won't launch until
re-signed ad-hoc. **Trap:** `codesign --force --sign - UTM.app` *strips all
entitlements*. UTM lost `app-sandbox` + `application-groups`
(`WDNLXAD4W8.com.utmapp.UTM`) → `utmctl`/AppleScript bridge hung (-1712),
QEMUHelper XPC couldn't launch. Fix: re-sign **with** the original entitlements:
```
codesign -d --entitlements - --xml ~/BAR-on-mac/UTM-binary-256M.backup > /tmp/ent.xml
codesign --force --sign - --entitlements /tmp/ent.xml /Applications/UTM.app
```
(no `--deep` — nested QEMUHelper/QEMULauncher keep their good sigs).
Original unpatched binary backed up: **`~/BAR-on-mac/UTM-binary-256M.backup`**.
To revert entirely: `brew reinstall --cask utm@beta` (also undoes MoltenVK swap).

## Verified results

- QEMU cmdline now `hostmem=2G` (in BAR.utm/Data/debug.log).
- Guest `lspci -v`: virtio-gpu prefetchable BAR is **`size=2G`** (was 256M).
- **The `tc_buffer_map` SIGSEGV at menu load is GONE** — no coredump, no
  dmesg segfault. BAR ran **15s+ stably** (killed it; earlier "exits" were just
  SIGHUP from nohup/SSH detachment, not crashes).
- Patch persists across VM restarts; re-confirmed 2G after a stop/start.
- GPU present path still healthy this boot: **glxgears renders** (accelerated,
  scrot-captured) — see screenshots in /tmp on host.

## Chobby lobby now LOADS and RENDERS (was: black screen)

**Fixed.** The black screen + every-widget `attempt to index field 'Chobby'
(a nil value)` was NOT a load-order/noise problem. Failure chain (from infolog):
`Error loading socket.lua` (tolerated) → **missing `chobby_config.json`** →
`[Settings] Mandatory field is missing: settingsNames` →
`_defaultGameRapidTag not present` → **`[Chobby] Chobby Shutdown`** at t≈1.1s →
`Chobby` global goes nil → all widgets error → empty (black) frame.

Two fixes, both in the guest:

1. **Enable LuaSocket** (Chobby's `main.lua` loads `socket.lua` early; off by
   default). `~/bar/data/springsettings.cfg`: add `LuaSocketEnabled = 1`.
   (`socket.lua` still logs a load error but it's non-fatal; this got Chobby
   to run further — liblobby/[Chobby]/[Settings] now execute.)
2. **Provide `chobby_config.json`** — normally written by spring-launcher,
   which we don't use (we run the engine directly via pr-downloader). Without
   it Chobby falls back to the `generic` gameConfig (no BYAR fields) and bails.
   Source of truth: `BYAR-Chobby/dist_cfg/config.json`. Create at BOTH
   `~/bar/data/chobby_config.json` and `~/bar/data/LuaMenu/chobby_config.json`:
   ```json
   { "server": { "address": "server4.beyondallreason.info", "port": 8200,
                 "protocol": "spring", "serverName": "BAR" }, "game": "byar" }
   ```
   `"game":"byar"` makes Chobby load `LuaMenu/configs/gameConfig/byar/mainConfig.lua`,
   which defines `settingsNames` + `_defaultGameRapidTag`. After this:
   `settingsNames missing=0, deploy-fail=0, Chobby Shutdown=0, Chobby-nil=0`,
   and liblobby targets BAR's real server (server4.beyondallreason.info, not
   springrts.com).

## Host QEMU crash on lobby render — FIXED (DebugLog=false)

Once Chobby actually rendered the lobby, the **host QEMU (QEMULauncher) aborted**
→ VM "stopped" (twice). Crash = **Metal API Validation assertion**:
`MTLDebugDevice notifyExternalReferencesNonZeroOnDealloc` → `abort`, from
`MVKBuffer::destroy()` ← `vkDestroyBuffer` ← venus. The lobby destroys a Metal
buffer Metal's debug layer still thinks is referenced; release Metal tolerates
this, the validation layer aborts. UTM enables the validation layer
(`MTL_DEBUG_LAYER=1`, also `MESA_DEBUG=1`, `MVK_DEBUG=1`, `MVK_CONFIG_LOG_LEVEL=4`,
`VK_LOADER_DEBUG=all`) **whenever the VM config has `DebugLog=true`** — confirmed
in the QEMU launch header + "Metal API Validation Enabled" line in debug.log.

Fix: set **`:QEMU:DebugLog` → false** in
`~/Library/Containers/com.utmapp.UTM/Data/Documents/BAR.utm/config.plist`
(`PlistBuddy -c "Set :QEMU:DebugLog false"`; quit UTM first so it doesn't
clobber; backup at `config.plist.bak.s3`). Trade-off: no more host debug.log.
Re-enable temporarily if you need host venus/MoltenVK logs again.

## RESULT: the BAR lobby works, GPU-accelerated

After both fixes: spring runs **stably 30s+**, **VM stays up** (no host crash),
and the **Chobby lobby renders fully** — BAR logo, left menu (Multiplayer /
Singleplayer / Replays / Chat / Settings…), "Welcome to Beyond All Reason"
panel, and the **Login/Register window**. liblobby calls `TryLogin` against
server4.beyondallreason.info. Screenshot saved host-side `/tmp/bar-lobby25.png`.
First time the lobby has been visible. **The session goal is met.**

## Keeping BAR running so you can SEE it (persistent launch)

Don't launch over a foreground SSH session you then close — and watch two traps
that wasted time here:
- **`pkill -f spring` kills your own SSH shell** (your command line contains the
  word "spring", so `-f` full-cmdline matching nukes the launcher mid-run →
  silent "no output" hangs, scripts that never start). Use **`pkill -x spring`**.
- **`pgrep -x spring` / `pgrep -c spring` return 0 even when it's alive** (the
  process `comm` isn't exactly "spring"). To check liveness use
  `pgrep -fa "engine/spring"` or just watch `/tmp/bar.log`'s `t=` timestamp climb.

Working method — run it in a **detached `screen`** (gives a persistent pty so
stdin never EOFs, and survives SSH logout):
```
ssh -p 2222 youruser@localhost   # then on guest:
pkill -x spring; screen -dmS bar bash ~/bar/run-live2.sh
```
`~/bar/run-live2.sh` = the run-bar-gpu2 env (DISPLAY=:0, XAUTHORITY from newest
/tmp/serverauth.*, LD_LIBRARY_PATH/VK_DRIVER_FILES→~/mesa-bar, zink, KOPPER_DRI2,
GL 4.5COMPAT, GLSL 450) then `./spring --write-dir ~/bar/data --menu
"rapid://byar-chobby:test"`, logging to /tmp/bar.log, `sleep 3600` after.
Verified alive 2.5min+ across reconnects. **To view it: open the BAR VM's
display window in the UTM app** — the lobby renders to X :0 → virtio-gpu scanout
→ UTM's SPICE display. (scrot of :0 confirms correct pixels: /tmp/live-now.png.)
Note: lobby music spams "Starting Track" ~6×/s in the log — harmless side effect
of the failed audio device (no ALSA in guest), each track ends instantly.

## Session 3 follow-up — online/lag/audio investigation (NOT yet solved)

User played with the lobby; three problems surfaced. Findings:

**1. Online lobby unstable — can't see/join battles.** The VM DOES reach BAR's
server (TCP server4.beyondallreason.info:8200 reachable; `OnConnected` fires,
~40s to connect), but it **drops every ~1 min** (`Disconnected, reason: nil`)
and never logs in (`TryLoginMultiplayer, nil, nil` loop — no credentials). Root
cause is deeper than first thought:
- `Error: Error loading socket.lua` at every LuaMenu start. `socket.lua` is NOT
  missing — it IS in `springcontent.sdz` at `LuaSocket/socket.lua` (verified via
  python zipfile; the earlier "missing" read was bogus — `unzip` isn't installed
  on the guest, so the grep found nothing). The file *executes and fails*: it
  does `function socket.connect(...)` assuming a global `socket` C-table exists,
  but the engine **doesn't expose the socket C-binding to the LuaMenu state**.
  `LuaSocketEnabled` defaults to 1 (confirmed via --list-config-vars), so that's
  not the gate. Likely recent Recoil **restricted/removed LuaSocket in the menu
  Lua for security** (see RecoilEngine issue #1786 "unsafe lua socket api").
- Consequence: BYAR-Chobby's lobby networking normally runs THROUGH
  **spring-launcher** (the BAR Electron launcher), which we don't use ("[Chobby]
  spring-launcher doesn't exist", "[spring-launcher] Disabling ... missing
  connection details"). Running the engine raw, the in-Lua socket path is what's
  broken. **The clean fix is probably to run spring-launcher** (need a Linux
  arm64 build) rather than patch engine internals. Did NOT crack this.
- Harmless leftovers added this session (keep or revert, no effect): springsettings
  `LuaSocketEnabled = 1`, `TCPAllowConnect = *`; a write-dir copy of socket.lua at
  `~/bar/data/LuaSocket/socket.lua` (VFS doesn't load it from there anyway).

**2. Mouse lag ~100ms.** NOT compute — guest CPU ~9% / 98% idle during the lobby.
It's the architecture: frame = GPU render → guest CPU copy (software WSI) → X →
virtio-gpu scanout → SPICE → UTM window, and input the reverse. Inherent to this
nested/software-present stack. Mitigations untested: VSync off (springsettings
VSync was 4/2), lower resolution (1280x800). Won't reach native feel.

**3. No audio.** Guest OpenAL "failed to open device" — there's no working sound
device in the guest (UTM/QEMU audiodev=spice but no usable guest driver/card).
Separate fix (add sound card + guest audio), low priority.

### Strategic note
User is weighing a **native macOS (arm64-darwin) Recoil/BAR port** vs. continuing
the VM. Reality: lag + audio are VM-architectural (a native port would fix both),
online is fixable-but-fiddly (spring-launcher). No official native macOS BAR build
exists; a port is a large, uncertain effort (engine not regularly built/tested on
macOS; needs Metal/MoltenVK for the GL path). Offline **skirmish vs AI works today**
in the VM (local render, no server) for immediate play.

### Promising next steps (session 4)

0. Decide VM-vs-native-port direction (see strategic note).
1. For online in the VM: get **spring-launcher** (Linux arm64) running — it owns
   the server connection/updates that the raw engine can't do. Or test whether a
   manual login even works despite the socket.lua error.
1b. **Log in / create an account** and try to **join or host a battle** —
   exercises the full online path (the login window is up and waiting).
2. **Start an actual game** (skirmish vs AI or a multiplayer battle) and watch
   stability + the 2G mappable ceiling under real load — the menu is light;
   gameplay loads far more textures/buffers. If it crashes in-game on mappable
   memory again, 2G may need to go higher (binary patch supports up to ~4-char
   values; `4G`/`3G` are 2-char, same patch technique).
3. The `socket.lua` load error is still logged (non-fatal). If online features
   misbehave, revisit LuaSocket (may need `LuaSocketRestrictions`/host allow-list).
4. Optional: re-create the `vkmaplimit` test (guest /tmp, lost on reboot) to
   quantify the new mappable ceiling at 2G.

## How to run (unchanged from session 2, recap)

- `utmctl` now works (entitlements restored): `utmctl list/start/status BAR`.
  Path: `/Applications/UTM.app/Contents/MacOS/utmctl`. SSH `ssh -p 2222 youruser@localhost`.
- Launch BAR on the guest X display (DISPLAY=:0): run env from
  `~/bar/run-bar-gpu2.sh`. **Run it inside a single foreground SSH session**
  (don't nohup+detach — the SIGHUP kills it and looks like a crash). Screenshot
  with `scrot -o /tmp/x.png`, scp back.

---

# Session 2 (2026-06-12, evening) — GPU rendering WORKS; one blocker left

## Where we got: **BAR launches, renders on the M4 GPU, and draws on screen.**
The menu comes up (fullscreen magenta + UI loading), then crashes ~3s in.
The single remaining blocker is a **256 MB cap on GPU-mappable memory**,
hardcoded in UTM. Everything graphics-related above that is solved.

The working chain: `BAR (GL 4.5 compat) → zink → Venus → virglrenderer →
MoltenVK → Metal → M4`, presented via Mesa's *software WSI* path
(GPU renders, guest CPU copies the frame, X11 displays it).
glxgears: **~950 FPS offscreen / ~400 FPS presented**. vkcube: works.
Red-clear test: pixel-perfect on the VM display.

## Session 1's conclusion was wrong in a useful way

- `VK_EXT_custom_border_color` is **not** fatal in Mesa ≥ 25.1 — it's a
  "some incorrect rendering might occur" *warning*. No patch needed.
- The session-1 segfault in `driBindContext` was actually the **missing
  `VK_KHR_swapchain`** crashing kopper when creating a GL drawable.
- Venus hides `VK_KHR_swapchain` only because MoltenVK can't import
  sync-fd semaphores — but Mesa's **software WSI** path needs no sync fds
  at all. Exposing it + forcing sw WSI is a ~20-line Mesa patch.

## The patched Mesa (THE key artifact)

Guest has **Mesa 25.1.9** built from source with our patches:
- source + build tree: guest `~/mesa` (git tag mesa-25.1.9, patches uncommitted)
- installed to: guest `~/mesa-bar` (prefix; activated via env vars, see launcher)
- full diff saved on host: **`~/BAR-on-mac/mesa-bar-patches.diff`** (352 lines, 10 files)

Why 25.1.9: newest branch where zink does NOT hard-require `nullDescriptor`
(robustness2), which Venus/MoltenVK reports as false. 25.2+ would need
another workaround.

The patches, in dependency order:

1. **vn_physical_device.c** — expose `VK_KHR_swapchain` (+ maintenance1,
   mutable_format, etc.) when `can_external_mem`, dropping the
   `semaphore_importable` requirement (sw WSI doesn't need it).
2. **vn_wsi.c** — force `wsi_device_options.sw_device = true` when
   `!renderer_sync_fd.semaphore_importable` (i.e., on macOS hosts).
3. **vn_device.c** — when `wsi_device.sw`, do NOT add host-side device
   extensions MoltenVK lacks (`VK_EXT_image_drm_format_modifier`,
   `VK_EXT_queue_family_foreign`, `VK_KHR_external_semaphore_fd`,
   dma-buf externals). Without this, host `vkCreateDevice` fails
   EXTENSION_NOT_PRESENT.
4. **vn_queue.c** — `vn_semaphore_signal_wsi` / `vn_fence_signal_wsi`:
   replace the sync-fd payload trick with a real **empty `vkQueueSubmit`**
   that signals the semaphore/fence. The payload trick routes to host
   `vkImportSemaphoreFdKHR` which is a NULL pointer on MoltenVK —
   **it segfaults the host QEMU process** (verified via crash report:
   `vn_dispatch_vkImportSemaphoreResourceMESA` → SIGSEGV).
5. **zink_screen.c** — MoltenVK quirks, detected via
   `zink_driverid(screen) == VK_DRIVER_ID_MOLTENVK` (venus passes the host
   driverID through; note `deviceName` does NOT contain "MOLTENVK" at this
   layer — that suffix is added later by zink itself):
   - `have_triangle_fans = false` (Metal has no fans; gallium lowers them)
   - clear `EXT_shader_demote_to_helper_invocation` (host SPIRV-Cross
     targets MSL < 2.3 and rejects `OpDemoteToHelperInvocation`;
     error verified via host log + `spirv-cross --msl` on dumped shaders)
6. **zink_compiler.c** — the big one: **Metal links varyings by
   location+component**. zink splits FS inputs into per-component-group
   variables (e.g. `slot_4` vec2 @ comp0 + `slot_4_c3` float @ comp3) while
   the VS writes one vec4 → MSL link error *"Fragment input user(locn0_3)
   ... not written by vertex shader"* → `vkCreateGraphicsPipelines` fails
   INITIALIZATION_FAILED. Fix (gated on a `zink_io_quirk_moltenvk` global
   set in `zink_screen_init_compiler`): merge disjoint FS-input component
   groups into one variable and expand user varyings to **vec4 @ component
   0 on both VS-out and FS-in** sides.
7. **zink_draw.cpp** — if pipeline compile failed, skip the draw instead of
   falling into the shader-object bind path (which is unsupported here and
   segfaults).
8. **zink_pipeline.c** — `ZINK_PIPE_DEBUG=1` env: on pipeline failure dump
   topology/blend/multisample/attr formats (diagnostic, keep).
9. **wsi_common_x11.c** — `WSI_SW_DEBUG=1` env: fence-wait + first-pixel
   log + checked PutImage in the sw present path (diagnostic, keep).
10. **vn_renderer_virtgpu.c** — `VN_RENDER_NODE=/dev/dri/renderD129` env to
    pin venus to a specific virtgpu device (added for the two-GPU
    experiment; harmless, keep).

**Rebuild loop** (guest): `cd ~/mesa && ninja -C build && ninja -C build
install && sync`. ALWAYS `sync` — a host QEMU crash rolls back unsynced
guest writes (this silently reverted one patch and cost an hour).
Clear `~/.cache/mesa_shader_cache*` after compiler-affecting changes —
cached NIR keeps old lowering (demote kept reappearing until cleared).

## The X server was a hidden second bug

Xorg's glamor runs on **virgl** (UTM's host-GL path) and silently corrupts
*all* PutImage/texture uploads — windows render black with working title
bars. Pure-X11 `XPutImage` test proved it (server accepts the request,
pixels never appear). This also masked our working present path for hours.

Fix (already applied in guest): `/etc/X11/xorg.conf.d/20-no-glamor.conf`
with `Option "AccelMethod" "none"`. X 2D becomes CPU — fine.
Side effect: no DRI3 → GLX needs **`LIBGL_KOPPER_DRI2=1`** (kopper presents
via Vulkan WSI directly; without this env, libGL hard-fails
"DRI3 not available" when zink is explicitly requested).

## The current blocker: hostmem=256M

- BAR crashes at menu load: SIGSEGV in `tc_buffer_map` ←
  `glBufferSubData` (glthread) — a buffer map returns NULL and mesa's
  threaded context doesn't check. Verified by core dump (`coredumpctl`).
- Root cause measured: guest can map only **~80–96 MB** of host-visible
  GPU memory before `vkMapMemory` fails (test prog: guest `/tmp/vkmaplimit.c`).
  All venus-mappable memory lives in the virtio-gpu **hostmem PCI BAR**,
  which UTM hardcodes at **256 MB**.
- `UTM/Configuration/UTMQemuConfiguration+Arguments.swift` (~line 279):
  emits `hostmem=256M`, `blob=true`, `venus=true` whenever the display is
  GL+Vulkan capable. No config knob.

Dead ends tried (don't repeat):
- `-global virtio-gpu-gl-pci.hostmem=2G` via `QEMU.AdditionalArguments` in
  config.plist → parsed, but per-device option wins. No effect.
- Second `-device virtio-gpu-gl-pci,hostmem=2G,...` → QEMU: *"at most one
  virtio-gpu-gl-device device is permitted"*. VM won't boot (config since
  reverted; `QEMU.AdditionalArguments` is `[]` again).
- Binary-patching UTM: the string is NOT in the binary as bytes —
  Swift small-string inline immediates (x86 slice shows it split across
  `movabs`; arm64 slice has zero hits for "hostmem"/"256M" as raw bytes;
  would require patching movk immediate pairs).
- apple/container (user asked): no — Virtualization.framework gives Linux
  guests no Vulkan/venus GPU path at all.

## Promising next steps (in order)

1. **Build UTM from source** with `hostmem=2G` (one-line change in
   Arguments.swift). UTM.app is already ad-hoc signed (vmnet already
   sacrificed in session 1), so a self-built unsigned UTM loses nothing.
   Repo: github.com/utmapp/UTM, needs Xcode; see Documentation/Build.md.
   Use the same UTM-bundled QEMU/virglrenderer (the fork matters — venus
   on macOS is their work) — building the app shell only should be enough
   if their prebuilt frameworks are fetched by the build.
2. **krunkit / libkrun** (brew install krunkit): purpose-built for GPU
   (venus) Linux VMs on macOS, used by podman/RamaLama. Check its hostmem
   default/configurability; if good, migrate the guest qcow2.
3. **Patch arm64 movk immediates** in UTM binary ("25"=0x3532, "6M"=0x4D36
   movk pair → "2G\0\0"; also fix the Swift small-string length nibble).
   Fiddly but no toolchain needed.
4. **Reduce BAR's mappable footprint** (likely insufficient alone): disable
   glthread (`mesa_glthread=false`), lower texture quality in BAR settings,
   shrink Spring's buffer pools. The 80 MB ceiling is probably too tight
   for the menu, let alone a game.

## How to run / verify (current state)

- VM "BAR" in UTM (leave config as-is; boots fine). SSH:
  `ssh -p 2222 youruser@localhost` (key auth works from this Mac).
- X runs automatically on the VM console (xinit/openbox via tty1 autologin,
  `DISPLAY=:0`, auth file `ls -t /tmp/serverauth.*`).
- Launch BAR: guest `~/bar/run-bar-gpu2.sh` (has all env baked in:
  LD_LIBRARY_PATH/VK_DRIVER_FILES → ~/mesa-bar, MESA_LOADER_DRIVER_OVERRIDE=zink,
  LIBGL_KOPPER_DRI2=1, MESA_GL_VERSION_OVERRIDE=4.5COMPAT, GLSL 450).
- Quick GPU sanity: `glxinfo -B` (expect "zink Vulkan 1.2 (Virtio-GPU Venus
  (Apple M4) (MOLTENVK))", Accelerated: yes), `vkcube`, `glxgears`.
- Screenshots: guest `scrot -o /tmp/x.png` then scp.
- **Host-side venus/MoltenVK log** (gold for debugging):
  `~/Library/Containers/com.utmapp.UTM/Data/Documents/BAR.utm/Data/debug.log`
  (DebugLog=true is set in the VM config). mvk-error lines show the real
  pipeline failures.
- Shader debugging: `ZINK_DEBUG=spirv` (dumps dumpNN.spv to CWD =
  `~/bar/data`), then `spirv-cross --msl [--msl-version 20300] f.spv`.
- Engine log: `~/bar/last-run-gpu2.log` / `~/bar/data/infolog.txt`.

## Misc state

- Guest tools installed: gdb, systemd-coredump, vulkan-tools, spirv-cross,
  spirv-dis, scrot, python3-pil, mesa-utils, build deps for mesa.
- Test programs in guest /tmp (rebuildable from this log's history):
  vkread.c (buffer readback), vkimg.c (image clear+copy), vkmaplimit.c
  (mappable ceiling), clearred.c (GL red clear), xput.c (raw X11 PutImage).
- `MESA: warning: ... VK_EXT_depth_clip_enable` at BAR launch is expected
  and harmless-ish (minor depth artifacts possible).
- Chobby Lua errors ("attempt to index field 'Chobby'") appear in every
  run incl. pre-crash; lobby-side noise, not the crash cause.
- Host disk: UTM.app ad-hoc signed with upstream MoltenVK 1.4.1
  private-API build (from session 1); vmnet broken → VM uses NAT+port 2222.
- mesa sparse checkout for reference on host: /tmp/mesa-src (26.1.2; may
  be gone after reboot — unimportant).

---

# Session 1 (2026-06-12, earlier) — original notes

Goal: play Beyond All Reason on an M4 MacBook Air (16 GB, macOS 26.3.1)
via a Linux ARM64 VM with GPU-accelerated rendering. One evening's attempt.

## Where we got: **almost, but blocked on one Metal gap.**

*(Superseded by session 2: the "Metal gap" diagnosis below was wrong —
custom border color is a warning, the crash was the missing swapchain.)*

## What works (verified)

- **VM stack stands up cleanly.** UTM 5.0.3 beta, Debian 13 ARM64 *cloud*
  image (no installer needed), 8 GB / 6 cores / 32 GB disk. Created and
  driven entirely by script + SSH.
- **No emulation needed.** Recoil engine now ships native `arm64-linux`
  builds (since 2026.06.07), so FEX-Emu — the big bottleneck in the Dec-2025
  Reddit writeup — is gone. Everything runs native ARM64.
- **Venus Vulkan passthrough is live.** Guest sees `Virtio-GPU Venus
  (Apple M4)`, driver `venus`, going through host MoltenVK → Metal → M4 GPU.
  QEMU launched with `virtio-gpu-gl-pci,hostmem=256M,blob=true,venus=true`.
- **Game is fully downloaded.** BAR game data (3.3 GB), Chobby lobby, and a
  map (Supreme Isthmus), via native arm64 `pr-downloader`.
- **Engine boots, X11 runs, input works.** Spring 2026.06.08 starts, reads
  config, enumerates all display modes at 1280×800, registers threads.

## What we had to fix along the way

- **MoltenVK feature gap (partially solved).** UTM's bundled MoltenVK fork
  reported `logicOp=false`, `wideLines=false` — which blocked Zink at
  startup. Swapped in the upstream **MoltenVK 1.4.1 private-API build**
  (`MVK_USE_METAL_PRIVATE_API`). After that, `logicOp=true`, `wideLines=true`.
  Backup of the original at `~/BAR-on-mac/MoltenVK-utm-fork.backup`.
- **Re-signing broke vmnet.** Swapping the binary forced an ad-hoc re-sign
  of UTM.app, which invalidated its sandboxed `vmnet` networking entitlement
  (Apple-issued, can't self-sign). Worked around by switching the VM to
  emulated NAT networking with an SSH port-forward on host `localhost:2222`.
- **KosmicKrisp driver: dead end.** UTM's alternative Vulkan driver crashed
  with a Metal validation assertion (`Linear texture: must be
  MTLTextureType2D, got 2DArray`). MoltenVK is the only viable host driver.

## State left on disk

- VM "BAR" in UTM. SSH: `ssh -p 2222 youruser@localhost` (pw `<your-vm-password>`,
  host key authorized). Launchers in guest `~/bar/run-bar-gpu.sh` (old) /
  `run-bar-cpu.sh` / **`run-bar-gpu2.sh` (current)**.
- UTM.app is ad-hoc re-signed with upstream MoltenVK 1.4.1. To restore
  stock UTM + working vmnet networking: reinstall via
  `brew reinstall --cask utm@beta` (would also undo the MoltenVK swap —
  don't, unless abandoning GPU).
- Host disk was cleared to make room (deleted Claude Desktop `vm_bundles`,
  12 GB — re-downloads on demand).
