# Beyond All Reason on Apple Silicon (no VM)

**[Beyond All Reason](https://www.beyondallreason.dev/) (BAR) running natively on an
Apple-Silicon Mac under Wine** — lobby, online multiplayer, and a fully-rendered,
**playable in-game battle** (terrain, units, UI), with native CoreAudio and native input.
**No virtual machine.**

Verified on an **M4 MacBook Air, 16 GB RAM, macOS 26.3.1**. Should work on any
Apple-Silicon Mac with Rosetta 2.

![status: playable](https://img.shields.io/badge/status-playable-brightgreen)

> **Disclaimer.** This documentation was written by **Claude (Opus and Fable)** based on a
> hands-on research effort, and edited by a human. It involves swapping system libraries,
> re-signing apps, and building/patching low-level graphics drivers. **Use it entirely at
> your own risk** — it is provided as-is, with no warranty, and is not affiliated with or
> endorsed by the Beyond All Reason team or the Recoil, Mesa, Wine, or MoltenVK projects.
> Back up anything you care about (Wine prefix, app bundles) before you start.

---

## Performance: turn graphics down for high FPS

The GL→Vulkan→Metal translation has overhead, and the engine runs as a Win64 binary under
Rosetta 2 — so you'll get a much smoother game by **lowering the graphics settings**, not
running max. Biggest wins:

- **Resolution** — drop to 1600×900 or 1280×720 (or run windowed at a smaller size). The
  single largest lever on a translation/Rosetta stack.
- **Shadows** — set to Low or Off.
- **Water** — use the cheap reflective/forward water, not the expensive shader water.
- **Particles / unit detail** — lower the particle and reflection quality; reduce max
  particles.
- **VSync off** + cap FPS to your display (e.g. 60) to avoid wasted frames and reduce input
  lag.
- Keep the **forward** render path (`AllowDeferred*Rendering = 0`, see `GUIDE.md` §6) —
  deferred buys nothing here and costs frames.

Tune these in-game under **Settings → Graphics**; set them low first, then raise individual
options until the frame rate dips. An RTS is very playable at 40–60 FPS.

---

## Why this is hard

BAR's engine (RecoilEngine / Spring) renders with **OpenGL 4.x in a compatibility
profile**. macOS's native OpenGL is frozen at **2.1 compat / 4.1 core** — there is no 4.x
compatibility profile on macOS at all. So you can't just run the Windows or a native build
against Apple's GL.

The fix is to route OpenGL through Vulkan and onto Metal, then patch the handful of places
where the translation layer's assumptions don't hold on Apple's Metal:

```
BAR (Win64 PE, runs under Rosetta 2)
  → Mesa opengl32.dll  (zink: GL-on-Vulkan, patched — see patches/)
  → Wine vulkan-1.dll  (winevulkan)
  → libMoltenVK        (private-API build)
  → Metal → Apple GPU
```

This gets a **GL 4.6 compatibility** context on Apple Silicon, which is enough to run the
whole game.

## How to reproduce it

**→ Follow [`GUIDE.md`](GUIDE.md).** It's the complete, step-by-step runbook: Wine prefix,
the MoltenVK swap, cross-building patched Mesa, getting BAR's content, config, and launch
scripts.

Rough shape of the work:

1. Install Wine (`wine-stable`) + a cross-compile toolchain (`mingw-w64`, `meson`, `ninja`).
2. Swap Wine's MoltenVK for a private-API build (enables `logicOp` / `wideLines`).
3. Cross-build **Mesa 25.1.9 (zink) for Windows** with the patches in [`patches/`](patches/).
4. Use the official BAR launcher (under Wine) to download content, then launch the engine
   directly with the zink env from [`scripts/`](scripts/).

## What's in this repo

| Path | What |
|---|---|
| [`GUIDE.md`](GUIDE.md) | **Start here.** Full reproduction runbook for the Wine path. |
| [`patches/mesa-bar-patches.diff`](patches/) | zink/Mesa 25.1.9 patches (varying-link, MoltenVK quirks, draw-skip). The two Session-5 in-game patches (depth-FBO + MSL reserved-name) are documented inline in `GUIDE.md` §4 "Set B". |
| [`patches/mingw-x64.cross`](patches/) | meson cross file for building Windows Mesa from macOS. |
| [`scripts/`](scripts/) | Launch scripts — `run-bar-online.sh` (normal play), `run-bar-debug.sh` / `run-bar-skirmish.sh` (reproducible offline diagnostics). |
| [`widget-ports/`](widget-ports/) | Optional: BAR widgets whose **geometry shaders** were rewritten as instanced quads so they render on Metal (minimap blips, health bars). See its README. |
| [`ATTEMPT-LOG.md`](ATTEMPT-LOG.md) | The full chronological story incl. every dead end (VM path, native-port spike, all the diagnosis). Read this for the "why". |
| [`docs/`](docs/) | Secondary tracks: the earlier **UTM/Linux VM** runbook and a **native-macOS-port** spike. Both partially work; the Wine path above is the recommended one. |

## What renders / what doesn't

**Works:** terrain, unit & feature models, selection rings, water (forward), the full HUD
(build menu, resource bars, minimap, commander panel), CoreAudio, native input. Smooth and
playable.

**Limitation — OpenGL geometry shaders.** Metal has no geometry-shader stage
(`GL_MAX_GEOMETRY_OUTPUT_VERTICES = 0`), and neither MoltenVK nor zink emulates one. Widgets
that use GS (unit icons, health bars, range rings, some particles, minimap icons) disable
themselves — they don't affect playability. [`widget-ports/`](widget-ports/) rewrites a
couple of them as hardware instancing to bring them back. (BAR upstream is also incrementally
removing GS use.)

## Caveats

- **Version-pinned.** The Mesa patches target **Mesa 25.1.9** specifically (newest branch
  where zink doesn't hard-require `nullDescriptor`). The widget ports are pinned to the BAR
  content version at the time and will be shadowed by a BAR content update.
- This is a **reproduction record from a research effort**, not a packaged installer. Expect
  to build things. `ATTEMPT-LOG.md` documents the dead ends so you don't repeat them.
- Not affiliated with the BAR team or the Recoil/Mesa/Wine projects.

## License / attribution

See [`NOTICE.md`](NOTICE.md). The Mesa patches are derived from
[Mesa](https://gitlab.freedesktop.org/mesa/mesa) (MIT); the widget ports are derived from
[Beyond All Reason](https://github.com/beyond-all-reason/Beyond-All-Reason) (GPL-2.0+).
This repo's original documentation and scripts are MIT.
