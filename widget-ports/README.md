# Widget ports: geometry shaders → hardware instancing

Metal has no geometry-shader stage. On Apple Silicon, `GL_MAX_GEOMETRY_OUTPUT_VERTICES = 0`
and neither MoltenVK nor zink emulates one, so any BAR widget that uses an OpenGL geometry
shader fails to compile its shader and disables itself. This is **not** fatal — the core game
renders fine without these (see the main README) — but it costs some eye-candy: minimap unit
blips, health bars, selection-range rings.

These files rewrite the geometry shaders as **instanced vertex-shader quad expansion**, so the
widgets render on Metal.

## Files

| File | What |
|---|---|
| `gui_pip.lua` | Minimap widget. All 4 GS blocks (unit-blip icons, range/selection circles, quads, decals) ported to instancing. |
| `gui_healthbars_gl4.lua` | Health-bar widget. The GS (per unit: multiple bar primitives + a data-dependent number of glyph quads) reimplemented as a fixed-budget 58-vertex instanced strip. |
| `HealthbarsGL4_ported.vert.glsl` | New vertex shader for the health-bar port (referenced by `gui_healthbars_gl4.lua` via `vssrcpath`). |
| `*.diff` | Unified diffs vs the pristine BAR baselines, so you can see exactly what changed. |

## The port pattern (GS billboard → instancing)

For each geometry shader that expanded a point into a quad:

1. Fold the quad-emit into the **vertex shader** — read the corner from a small static
   per-vertex corner buffer.
2. Delete the `geometry` stage; remove `gssrcpath`.
3. Switch the per-item data buffer from `AttachVertexBuffer` → `AttachInstanceBuffer`.
4. Add a static 4-corner VBO as the vertex buffer.
5. Change `DrawArrays(GL.POINTS, n)` → instanced `DrawArrays(GL.TRIANGLE_STRIP, V, 0, n)`.

**Critical gotcha:** a `gl_VertexID`-only draw with **no vertex buffer bound hard-crashes
MoltenVK** (invalid Metal draw, no log). You MUST bind a real corner VBO.

Other gotcha: `active` is a GLSL reserved word — don't name a variable `active` (BAR's shader
cache can mask the resulting compile failure by serving an older successful compile).

## Deploy

Copy into BAR's write-dir, overriding the archive copies:

```
.../Beyond-All-Reason/data/LuaUI/Widgets/gui_pip.lua
.../Beyond-All-Reason/data/LuaUI/Widgets/gui_healthbars_gl4.lua
.../Beyond-All-Reason/data/LuaUI/Shaders/HealthbarsGL4_ported.vert.glsl
```

Confirm via the `[PIP-PORT]` / `[HB-PORT]` echo markers in `infolog.txt`.

## Caveats

- **Version-pinned** to the BAR content at the time of porting; a BAR content update will
  shadow these overrides. BAR upstream is independently removing GS use, which is the real
  long-term fix.
- One unrelated GS widget is **not** ported here: `DrawPrimitiveAtUnits GL4` /
  `DecalsGL4` (would need the same treatment).
- Derived from Beyond All Reason — **GPL-2.0-or-later** (see `../NOTICE.md`).
