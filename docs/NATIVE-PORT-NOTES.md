# BAR native macOS port — plan & log

Goal: run Beyond All Reason **natively** on the M4 MacBook Air (no VM).
Sister doc: `ATTEMPT-LOG.md` is the **VM track** (owned by a different agent —
do not touch the VM, UTM, or the guest). This file is the **native track**.

Decision (2026-06-13): the VM path renders the lobby but looks unlikely to be
playable; pursue a native port instead.

---

## STATUS (2026-06-13) — all hard unknowns retired; remaining work is plumbing

| Phase | State | Evidence |
|-------|-------|----------|
| M0 graphics (zink→MoltenVK→Metal, GL4.5 compat on M4) | ✅ DONE | `gltest`/`fbotest`, RENDER OK |
| M1 engine builds+runs native arm64 | ✅ DONE | `build/spring --version`→2026.01.01 |
| M2 present path (zink→CAMetalLayer via eglSwapBuffers) | ✅ PROVEN | `eglsurf2` → "M2 OK", GL4.5, swap=1 |
| M2 plumbing (wire engine SDL2 → that EGL context) | ⏳ TODO | mapped below, no unknowns |
| M3 content + run BAR | ⏳ TODO | pr-downloader built; plan below |

**Bottom line:** a native arm64 BAR engine binary exists and runs; the full
graphics stack (incl. windowed present to a Metal layer) is proven end-to-end on
this M4 with NO VM. What's left is connecting the two — mechanical, no research.

### HOW TO FINISH — ordered checklist (engine-side EGL approach, recommended)
All in `rts/Rendering/GlobalRendering.cpp` behind `#ifdef __APPLE__` (+ VerticalSync.cpp).
The exact working EGL calls are in `~/BAR-on-mac/native/eglsurf2.m` — copy them.
1. Create the SDL window with `SDL_WINDOW_METAL` (not `SDL_WINDOW_OPENGL`) on APPLE.
2. `SDL_Metal_CreateView(win)` → `SDL_Metal_GetLayer(view)` → the `CAMetalLayer*`.
3. EGL bring-up on that layer: `eglGetDisplay(EGL_DEFAULT_DISPLAY)`, `eglInitialize`,
   `eglBindAPI(EGL_OPENGL_API)`, choose a config looping for **exactly R=G=B=A=8**
   (SURFACE_TYPE=WINDOW_BIT, RENDERABLE_TYPE=OPENGL_BIT), `eglCreateWindowSurface(
   dpy,cfg,(EGLNativeWindowType)layer,NULL)`, `eglCreateContext(MAJOR4 MINOR5
   PROFILE=COMPAT)`, `eglMakeCurrent`. (8888 + CAMetalLayer are mandatory — see gotchas.)
4. Replace on APPLE: `SDL_GL_CreateContext`→the above; `SDL_GL_SwapWindow`→`eglSwapBuffers`;
   `SDL_GL_MakeCurrent`→`eglMakeCurrent`; `SDL_GL_SetSwapInterval`→`eglSwapInterval`;
   GLAD loader (`gladLoadGL`/`SDL_GL_GetProcAddress`)→`eglGetProcAddress`.
   Call sites: GlobalRendering.cpp, VerticalSync.cpp (RmlUi SDL_GL3 backend + headlessStubs
   likely not compiled in this build — verify). Link `-framework QuartzCore -framework Metal`,
   add `-I<mesa-native>/include`, `-L<mesa-native>/lib -lEGL` to the engine/legacy target on APPLE.
5. Run with the M0 runtime env (DYLD_LIBRARY_PATH/VK_ICD_FILENAMES/MESA_LOADER_DRIVER_OVERRIDE=
   zink/MESA_GL_VERSION_OVERRIDE=4.5COMPAT). Expect glGetString → "zink ... Apple M4 (MOLTENVK)".
   ALT approach (b): patch+rebuild SDL2 Cocoa backend to route SDL_GL_*→EGL (template:
   lucamignatti/glfw commit 95cd3b5); engine code stays stock but riskier (SDL build config).

### M3 — content + run
- Build/locate pr-downloader: `~/BAR-on-mac/native/RecoilEngine/build` (target `pr-downloader`),
  or reuse the VM track's already-downloaded BAR data if accessible.
- Fetch BAR: `pr-downloader --download-game "byar:test"` (rapid tag), set `--write-dir`.
- Launch: `./spring --write-dir <dir> --menu "rapid://byar-chobby:test"` (matches VM track).
- Reuse VM-track Chobby findings VERBATIM (ATTEMPT-LOG.md): create `chobby_config.json`
  (game:byar) at `<dir>/` and `<dir>/LuaMenu/`, set `LuaSocketEnabled=1` in springsettings.cfg.
- For ONLINE play, rebuild the engine at BAR's REAL released tag (not the 2026.01.01
  placeholder) so the network sync version matches the server.

---

## Feasibility verdict: FEASIBLE. All three legs have working prior art.

The hard, existential risk (can macOS even give the engine a modern desktop-GL
context on the GPU?) is **retired** by prior art before writing any code.

### The proven native graphics stack (no VM, no venus, no virtio-gpu)
```
BAR (OpenGL 4.5 compat) → Zink (Mesa gallium) → Vulkan → KosmicKrisp → Metal → M4
```
- **KosmicKrisp** = LunarG's Vulkan-on-Metal driver, **merged into upstream Mesa**
  (gitlab.freedesktop.org/mesa/mesa). **Fully Vulkan 1.3 conformant** on Apple
  Silicon; targets macOS 15+ for VK 1.3. We're on macOS 26.3.1 / M4 → supported.
  Prebuilt in the Vulkan SDK alongside MoltenVK + loader.
- **Why KosmicKrisp over MoltenVK:** it's *conformant*, so the VM track's
  MoltenVK quirk-patches (triangle fans, demote-to-helper, varying location/
  component merge — mesa-bar-patches.diff #5–7) may be **unneeded** natively.
  MoltenVK 1.4.1 (we have a backup) stays as fallback.
- **No GLX/EGL/X11 from Apple.** Mesa brings its own GL via a 2025 Kopper
  "Metal display vtbl" + EGL `surfaceless`. Apple's own GL is frozen at 4.1
  core (dead end) — confirmed by maintainers (RecoilEngine#936) and springrts.

### Context-routing mechanism (the make-or-break detail — SOLVED)
macOS apps normally get GL from Apple NSGL/CGL (capped 4.1). To force Mesa zink:
- a **`libgl_interpose.dylib`** uses `DYLD_INTERPOSE` / `DYLD_INSERT_LIBRARIES`
  to redirect GL symbol lookups to `eglGetProcAddress` → Mesa EGL → zink;
- the windowing toolkit is patched to create the context via **EGL surfaceless**
  instead of NSGL. Minecraft did this with GLFW; **we must do it with SDL2.**

Working reference recipe (Minecraft on macOS via zink+KosmicKrisp):
```
meson setup build -Dplatforms=macos -Degl-native-platform=surfaceless \
  -Degl=enabled -Dgallium-drivers=zink -Dvulkan-drivers=kosmickrisp \
  -Dmoltenvk-dir=$(brew --prefix molten-vk) -Dprefix=$HOME/mesa-native
# runtime env:
DYLD_INSERT_LIBRARIES=…/libgl_interpose.dylib  DYLD_LIBRARY_PATH=…/lib
LIBGL_DRIVERS_PATH=…/lib/dri  EGL_PLATFORM=surfaceless
VK_DRIVER_FILES=…/kosmickrisp_mesa_icd.aarch64.json
MESA_LOADER_DRIVER_OVERRIDE=zink  MESA_GL_VERSION_OVERRIDE=4.6  MESA_GLSL_VERSION_OVERRIDE=460
```
Sources: Khronos forum "OpenGL on Zink/Mesa/MoltenVK/macOS"; gist
lucamignatti/5312f5e937de2ba44256ecba6de54cc2; docs.mesa3d.org/drivers/zink.html;
lunarg.com KosmicKrisp pages; RecoilEngine#936; BAR#2258.

### Leg 2: ARM64 C++ — low risk
Engine is C++23 and already ships **native arm64-linux** builds; `rts/lib/sse2neon`
submodule present (NEON path). Compiling C++ for arm64 is a solved concern.

### Leg 3: Darwin build target — mechanical but bitrotted
Engine still has Apple scaffolding: `MACOSX_BUNDLE` option (default TRUE on APPLE,
top CMakeLists L95-103), `rts/System/Platform/Mac/` (SDLMain.m/.h, CrashHandler,
Signal, MessageBox, WindowManagerHelper), `__APPLE__` branches in Threading/Misc/
SharedLib, CoreFoundation/Foundation `find_library` (rts/System/CMakeLists L205+).
But official Spring only built on macOS through ~103.1; Darwin unmaintained since.
`SDLMain.m` predates SDL2's built-in macOS support → likely replace/trim.

---

## Environment (this Mac)
- macOS 26.3.1 (build 25D771280a), Apple M4, 16 GB RAM. **Disk: ~32 GB free** (tight).
- Toolchain: Apple clang 21, cmake 4.1.1, ninja 1.13.1, git 2.50.1, Homebrew 6.0.1
  (arm64 /opt/homebrew). **CLT only** (no full Xcode) — fine for a CLI/meson/cmake
  build; macOS SDK ships the Cocoa headers SDLMain needs. NO Xcode IDE required.

## Engine source
- `~/BAR-on-mac/native/RecoilEngine` — shallow clone (130 MB, no submodules yet).
  Build: `mkdir build && cd build && cmake .. && cmake --build .` (default
  RELWITHDEBINFO). Targets: engine-legacy (main), engine-headless, engine-dedicated.
- Submodules needed for a real build (rts/lib/*): tracy, gflags, entt, cereal,
  RmlUi, lunasvg, fastgltf, simdjson, nowide, fmt, mimalloc, sse2neon, streflop.
  (AI/CircuitAI + tools/pr-downloader + unitsync/python NOT needed to compile the
  engine itself.)
- External deps (brew shopping list, from find_package across CMake):
  sdl2, freetype, fontconfig, expat, openal-soft, libvorbis/libogg, devil, zlib.
  Frameworks (system): OpenGL (build-time headers only), CoreFoundation/Foundation.
  X11 find_package is guarded to non-APPLE. NOTE: engine prefers `find_package_static`
  → brew ships dylibs; expect to relax static-lib requirement on APPLE.

## Patch reuse from the VM track (mesa-bar-patches.diff, 10 files)
- #1–4 `vn_*.c` (Venus): **DROP** — no venus natively.
- #5–7 `zink_screen/zink_compiler/zink_draw` (MoltenVK quirks): **maybe needed** —
  re-test on KosmicKrisp first; conformant driver may not need them.
- #9 `wsi_common_x11`: **REPLACE** with the macOS Kopper-Metal / EGL-surfaceless path.
- #8,#10 diagnostics: optional, keep if useful.

---

## Build order (de-risk graphics first; engine is parallelizable)

**M0 — prove the graphics stack natively. ✅ DONE (2026-06-13).**
Native desktop **GL 4.5 (Compatibility Profile) Mesa 26.1.0-devel** on the M4,
`GL_RENDERER = zink Vulkan 1.4 (Apple M4 (MOLTENVK))`, FBO render + glReadPixels
returned the exact clear color (51,153,229,255 = RENDER OK). **No VM.** Existential
risk retired. Built zink-only against MoltenVK (KosmicKrisp deferred — needs LLVM).

### Exact working M0 recipe (reproduce)
- Mesa fork: `~/BAR-on-mac/native/mesa-macos` (github.com/lucamignatti/mesa, main).
  Configured + built (973 ninja steps, ~no LLVM):
  ```
  PKG_CONFIG_PATH=vulkan-loader+vulkan-headers+molten-vk pkgconfig dirs
  PATH prepend /opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin
  meson setup build --native-file native.ini -Dprefix=~/BAR-on-mac/native/mesa-native \
    -Dbuildtype=release -Dplatforms=macos -Degl-native-platform=surfaceless -Degl=enabled \
    -Dgallium-drivers=zink -Dvulkan-drivers= -Dgles1=enabled -Dgles2=enabled \
    -Dglx=disabled -Dgbm=disabled -Dmoltenvk-dir=/opt/homebrew/opt/molten-vk
  ninja -C build && ninja -C build install
  ```
  Build-dep gotchas: brew `meson bison flex pkgconf`; python3.14 modules via
  `pip install --break-system-packages mako packaging pyyaml ply setuptools`;
  dropped `-Dvulkan-drivers=kosmickrisp` because KosmicKrisp pulls mesa-clc→libclc→LLVM.
- Installed prefix `~/BAR-on-mac/native/mesa-native/lib`: libEGL, libGL (wrapper),
  libgl_interpose.dylib, libGLES*, libgallium-26.1.0-devel.dylib (contains zink).
- **Runtime env (the magic incantation):**
  ```
  DYLD_LIBRARY_PATH=<prefix>/lib:/opt/homebrew/opt/vulkan-loader/lib:/opt/homebrew/opt/molten-vk/lib
  VK_ICD_FILENAMES=/opt/homebrew/opt/molten-vk/etc/vulkan/icd.d/MoltenVK_icd.json
  EGL_PLATFORM=surfaceless  MESA_LOADER_DRIVER_OVERRIDE=zink
  MESA_GL_VERSION_OVERRIDE=4.5COMPAT  MESA_GLSL_VERSION_OVERRIDE=450
  ```
- Test programs: `~/BAR-on-mac/native/gltest.c` (context+version) and `fbotest.c`
  (FBO render proof). Both compile with `-I<prefix>/include -L<prefix>/lib -lEGL`.
- Same non-fatal warning as VM: zink misses logicOp/custom_border_color on MoltenVK
  (Mesa ≥25.1 = warning, not fatal). KosmicKrisp may remove it (conformant) — revisit.

**M1 — engine configures+builds on arm64-macOS. ✅ DONE (2026-06-13).**
`build/spring` = Mach-O 64-bit arm64, 28 MB; `./spring --version` → "spring version
2026.01.01". Native engine binary builds, links, and runs. Build dir
`~/BAR-on-mac/native/RecoilEngine/build`.
Configure cmd: `cmake .. -G Ninja -DCMAKE_BUILD_TYPE=RELWITHDEBINFO
-DCMAKE_PREFIX_PATH=/opt/homebrew -DCMAKE_OSX_ARCHITECTURES=arm64 -Wno-dev
-DOPENAL_INCLUDE_DIR=/opt/homebrew/opt/openal-soft/include/AL
-DOPENAL_LIBRARY=/opt/homebrew/opt/openal-soft/lib/libopenal.dylib`
then `PATH=brew bison+flex; ninja -j6 engine-legacy` (output binary is named `spring`).

### Darwin-port fixes applied so far (candidates for a real PR upstream)
1. `rts/builds/legacy/CMakeLists.txt`: `if(UNIX)` → `if(UNIX AND NOT APPLE)` around
   the X11/Xcursor link — macOS uses Cocoa via SDL2, not X11. (generate-step fail)
2. `rts/build/cmake/FindLibunwind.cmake`: replaced OS X 10.10 hack
   `set(LIBUNWIND_LIBRARY "-framework Cocoa")` (a space-containing string Ninja
   mis-parses as a missing input file → "needed by 'spring'") with
   `find_library(LIBUNWIND_LIBRARY System)` (unwind API lives in libSystem).
3. OpenAL: CMake's FindOpenAL grabbed Apple's `OpenAL.framework` which has NO EFX
   (AL_EAXREVERB_* undefined; `<efx.h>` mis-resolved to engine's own header on the
   case-insensitive FS). Fix = the two `-DOPENAL_*` overrides above → brew openal-soft
   (keg-only; has al.h/alc.h/efx.h w/ EFX). NOT a source patch, just cache vars.
4. `rts/lib/glad/CMakeLists.txt`: `if(UNIX AND NOT MINGW)` →
   `... AND NOT APPLE` so `glad_glx.c` (pulls `<X11/X.h>`) isn't built on macOS.
5. libc++ doesn't transitively include headers libstdc++ does — added missing includes:
   `rts/lib/smmalloc/smmalloc.h` (`<type_traits>`), `smmalloc_generic.cpp` (`<cstdlib>`
   for std::malloc/free), `rts/lib/assimp/include/assimp/types.h` (`<cmath>` for std::abs
   in vector2/3.inl).
6. `rts/Sim/Units/Unit.cpp`: `std::views::enumerate` (C++23, absent in this libc++,
   even with -fexperimental-library) → manual index loop. (only 1 use in tree)
7. `rts/Rml/SolLua/bind/{bind,Context,Element}.cpp`: `sol::nil`→`sol::lua_nil`,
   `sol::type::nil`→`sol::type::lua_nil` — `nil` is taken on macOS (ObjC), so sol2
   only defines the lua_nil aliases there.
8. `rts/System/Platform/ThreadAffinityGuard.{h,cpp}`: the non-Windows `#else` assumed
   Linux (cpu_set_t/sched_*/syscall.h) → `#elif defined(__linux__)`, leaving macOS a
   no-op (Apple has no equivalent pinning API).
9. `MemPoolTypes.h:434`: `static_cast<uint32_t>(GetCurrentThreadId())` illegal (NativeThreadId
   = pthread_t* on mac) → `(uint32_t)(uintptr_t)(...)`.
10. NEW FILE `rts/System/Platform/Mac/CpuTopology.cpp` (+ added to
    `sources_engine_System_Threading_Mac` in `rts/System/CMakeLists.txt`): macOS had no
    cpu_topology impl (only Linux/Win) → 3 undefined symbols at link. Stub returns
    THREAD_PIN_POLICY_NONE + empty masks/caches (XNU schedules P/E cores itself).
### Build-env prep (not source changes)
- brew: meson bison flex pkgconf sdl2 freetype fontconfig libvorbis libogg
  openal-soft devil sevenzip; `ln -sf 7zz /opt/homebrew/bin/7z` (FindSevenZip wants 7z/7za).
- submodules: `git submodule update --init --recursive --depth 1` for rts/lib/* +
  tools/pr-downloader + nested lunasvg/plutovg.
- shallow clone has no tags → version gen fails ("Invalid version format"); fixed with
  `git tag 2026.01.01` (placeholder; for ONLINE play must match BAR's real engine tag).
- python3.14 modules for meson(mesa): mako packaging pyyaml ply setuptools.

**M2 — wire engine SDL2 → zink context.** IN PROGRESS. **Present path PROVEN**
(2026-06-13): `~/BAR-on-mac/native/eglsurf2.m` — Mesa zink does
`eglCreateWindowSurface` on a **CAMetalLayer**, `eglMakeCurrent` → GL 4.5 Compat,
`eglSwapBuffers` presents via MoltenVK. **No VM, no KosmicKrisp needed.** Two gotchas:
  - native window MUST be a **CAMetalLayer** (plain CALayer → MoltenVK crash
    `-[CALayer naturalDrawableSizeMVK]: unrecognized selector`).
  - EGL config MUST be **exactly 8-bit RGBA** (loop configs, require R=G=B=A=8);
    a wide config makes zink pick RGBA16Unorm = Metal pixelFormat 110 →
    `CAMetalLayerInvalid: invalid pixel format 110`.
  - Working EGL recipe: `eglBindAPI(EGL_OPENGL_API)`, config with
    `EGL_SURFACE_TYPE=EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE=EGL_OPENGL_BIT`,
    context `MAJOR=4 MINOR=5 PROFILE=COMPAT`. Same MoltenVK runtime env as M0.

  Also established: **Apple NSGL can't run the engine** — `SDL_GL_CreateContext`
  with the engine's request (4.5 compat) FAILS on the Cocoa backend ("Failed
  creating OpenGL context at version requested"); Apple maxes at 2.1 compat / 4.1
  core. And the blunt `libgl_interpose` (DYLD_INTERPOSE) alone does NOT carry
  SDL2's context creation — SDL must actually create the context via EGL.

  REMAINING (plumbing, no unknowns): make the engine's SDL2 window present via the
  above. Two options: (a) patch+rebuild SDL2's Cocoa backend to route
  `SDL_GL_CreateContext`→EGL on a CAMetalLayer (mirrors lucamignatti/glfw fork:
  force NATIVE_CONTEXT_API→EGL, expose NSView.layer); engine code unchanged. Or
  (b) APPLE-only path in `rts/Rendering/GlobalRendering.cpp` that creates the EGL
  ctx/surface on the SDL window's CAMetalLayer (via SDL_GetWindowWMInfo → NSView)
  and replaces SDL_GL_CreateContext/SwapWindow/MakeCurrent. (a) is cleaner/reusable.
  Template diff: lucamignatti/glfw commit 95cd3b5 (cocoa_window.m 2-line force-EGL).

**M3 — run BAR** (engine + game data + Chobby). Game content is platform-agnostic
Lua/data; reuse the VM track's chobby_config.json / LuaSocket findings.

## Open questions to resolve as we go
- Does upstream Mesa main build cleanly on macOS 26 with both zink + kosmickrisp,
  or do we need a specific tag / the LunarG branch? (KosmicKrisp merged upstream.)
- Can we skip building the Vulkan driver and use the Vulkan SDK's prebuilt
  KosmicKrisp ICD, building only Mesa gallium-zink against it? (saves disk/time)
- Where does `libgl_interpose.dylib` come from — the gist's repo, or hand-roll the
  DYLD_INTERPOSE shim? Need the source.
- Does SDL2 (brew) support an EGL path on macOS, or must we patch/rebuild SDL2?
- Disk: Vulkan SDK + Mesa + engine + deps vs 32 GB free — watch closely.
