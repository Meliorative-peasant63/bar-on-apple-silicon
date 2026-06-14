# BAR on Apple Silicon (M4 Air) — Setup Runbook

Goal: play Beyond All Reason on macOS via a lightweight Linux ARM64 VM with
GPU-accelerated Vulkan (Venus → MoltenVK → Metal). Based on the Dec-2025
Reddit recipe, updated for what changed since:

- **UTM 5.0.3** (installed): Vulkan 1.3 in Linux guests via Venus is now official.
  UTM's MoltenVK fork gained geometry-shader support (Feb 2026, issue #7575) —
  the `logicOp`-class gaps that blocked the GPU path in December have been
  actively fixed (DXVK games confirmed booting by the UTM maintainer).
- **Recoil engine now ships native `arm64-linux` builds** (since release
  2026.06.07). **FEX-Emu is no longer needed** — the whole stack runs native
  ARM64. This was the biggest perf bottleneck in the original post.
- Fallback: native arm64 llvmpipe (software GL) — far faster than the
  emulated-x86 llvmpipe the Reddit poster used, though still not great.

## Stack

```
BAR (arm64 Recoil engine, OpenGL 4.3+)
  → Mesa Zink (GL-on-Vulkan) in guest
  → Venus (paravirtualized Vulkan, virtio-gpu)
  → UTM/QEMU → MoltenVK → Metal → M4 GPU
```

## Step 1 — VM creation (DONE, fully automated)

What was actually done (no GUI needed):
- VM "BAR" created via UTM AppleScript: aarch64 virtualize, 8 GB RAM,
  6 cores, display hardware `virtio-gpu-gl-pci`, shared network.
- Disk: Debian 13 **genericcloud** arm64 qcow2 (no installer!), resized to
  32 GB with `qemu-img resize` (note: a raw header patch is NOT enough —
  "L1 table is too small").
- cloud-init seed.iso (volume label `cidata`, built with `hdiutil
  makehybrid`) creates user `youruser` (password `<your-vm-password>`, host ssh key
  authorized), installs openssh/avahi/qemu-guest-agent.
- Gotchas hit: removable drives reference external paths via sandbox
  bookmarks → make seed.iso an internal drive (`ImageName` in
  config.plist + copy into `BAR.utm/Data/`); UTM prefs (`Registry:…:
  ExternalDrives`) can resurrect via cfprefsd — edit only while UTM is
  fully quit.
- UTM app settings: Renderer Backend = Default, Vulkan Driver = Default
  (resolves to MoltenVK; KosmicKrisp still WIP in 5.0.3).

## Step 2 — Guest reachable at `youruser@bar-vm.local` (avahi/mDNS)

Claude drives everything else over SSH.

## Step 4 — Guest setup (scripted: `guest-setup.sh`)

What it does:
1. Installs Mesa (Vulkan + Zink), vulkan-tools, SDL2, OpenAL, 7zip, a minimal
   Openbox/X11 session.
2. Verifies `vulkaninfo` shows `driverName = venus` (if llvmpipe shows
   instead, the UTM display settings are wrong — recheck Step 1).
3. Downloads Recoil `arm64-linux` engine release.
4. Uses bundled `pr-downloader` to fetch BAR game data + a couple of maps.
5. Creates `run-bar-gpu.sh` (Zink→Venus path) and `run-bar-cpu.sh`
   (llvmpipe fallback) launchers.

## Launch env vars

GPU path:
```
MESA_LOADER_DRIVER_OVERRIDE=zink MESA_GL_VERSION_OVERRIDE=4.5 \
MESA_GLSL_VERSION_OVERRIDE=450 ./spring [...]
```
CPU fallback:
```
LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe ./spring [...]
```

## Known risks (verified June 2026)

- `VK_EXT_custom_border_color`: Metal can't expose it; MoltenVK closed the
  request as not-planned. Mesa has a draft fallback (MR !22578). If Zink
  refuses GL 4.3+ because of it, options: GL version override + hope BAR
  doesn't hit border-color sampling, or pull a Mesa build with the fallback.
- Don't resize the VM window mid-game (Mesa dispatch thread-safety crash) —
  though UTM 5.0.2 fixed *its* resize bugs, the Mesa-side one may persist.
- Multiplayer note: engine sim is deterministic per-arch; cross-arch
  (arm64 vs amd64) multiplayer sync is unproven. Skirmish vs AI is the
  first target; online play needs testing.

## Space budget (host)

UTM ~1 GB · ISO 0.7 GB · VM real usage ~12–15 GB (Debian ~4 + BAR ~6–8 + maps)
→ need ~20 GB free to be comfortable.
