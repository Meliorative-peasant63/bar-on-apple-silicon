# Attribution & licensing

This repository is a reproduction record. It combines original documentation/scripts with
patches and ports derived from other projects. Different parts carry different licenses.

## Original work in this repo (MIT)

The documentation (`README.md`, `GUIDE.md`, `ATTEMPT-LOG.md`, `docs/*.md`) and the launch
scripts (`scripts/*.sh`, `patches/mingw-x64.cross`) are original to this effort and released
under the MIT License.

## `patches/mesa-bar-patches.diff` — derived from Mesa

These are source patches against **Mesa 25.1.9** (`src/gallium/drivers/zink/...`,
`src/virtio/vulkan/...`, `src/vulkan/wsi/...`). Mesa is licensed under the **MIT License**.
The patches are derivative works of Mesa and are offered under the same MIT terms. Mesa:
https://gitlab.freedesktop.org/mesa/mesa

## `widget-ports/` — derived from Beyond All Reason

`gui_pip.lua`, `gui_healthbars_gl4.lua`, and `HealthbarsGL4_ported.vert.glsl` are modified
versions of widgets/shaders from **Beyond All Reason**, which is licensed **GPL-2.0-or-later**.
These files remain under GPL-2.0+. Beyond All Reason:
https://github.com/beyond-all-reason/Beyond-All-Reason

## Not included / not redistributed

This repo does **not** redistribute: the BAR game content or engine, MoltenVK, Wine, the
Mesa source tree, or any compiled binaries. `GUIDE.md` tells you where to obtain each.

## No affiliation

This is an independent community effort, not affiliated with or endorsed by the Beyond All
Reason team or the Recoil, Mesa, Wine, or MoltenVK projects.
