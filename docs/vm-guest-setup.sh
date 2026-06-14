#!/bin/bash
# BAR guest setup — run inside the Debian 13 ARM64 VM (as user with sudo).
# Idempotent; safe to re-run.
set -euo pipefail

ENGINE_VERSION="2026.06.08"
ENGINE_URL="https://github.com/beyond-all-reason/RecoilEngine/releases/download/${ENGINE_VERSION}/recoil_${ENGINE_VERSION}_arm64-linux.7z"
BAR_DIR="$HOME/bar"
DATA_DIR="$HOME/bar/data"

echo "=== [1/5] Packages ==="
sudo apt-get update
sudo apt-get install -y \
  mesa-vulkan-drivers mesa-utils vulkan-tools libvulkan1 \
  libsdl2-2.0-0 libopenal1 libcurl4 p7zip-full wget \
  xorg openbox xinit x11-xserver-utils

echo "=== [2/5] Verify Venus Vulkan driver ==="
if vulkaninfo --summary 2>/dev/null | grep -q "venus"; then
  echo "OK: Venus driver active."
else
  echo "WARNING: Venus NOT detected. vulkaninfo summary:"
  vulkaninfo --summary 2>&1 | grep -E "driverName|deviceName" || true
  echo "Check UTM display settings (virtio-gpu-gl-pci, GPU Supported on, Vulkan=MoltenVK)."
fi

echo "=== [3/5] Recoil engine (native arm64) ==="
mkdir -p "$BAR_DIR/engine" "$DATA_DIR"
if [ ! -x "$BAR_DIR/engine/spring" ]; then
  wget -q --show-progress -O /tmp/recoil.7z "$ENGINE_URL"
  7z x -y -o"$BAR_DIR/engine" /tmp/recoil.7z
  rm /tmp/recoil.7z
fi
ls -la "$BAR_DIR/engine" | head

echo "=== [4/5] BAR game data via pr-downloader ==="
PRD="$BAR_DIR/engine/pr-downloader"
[ -x "$PRD" ] || PRD="$(find "$BAR_DIR/engine" -name 'pr-downloader' -type f | head -1)"
"$PRD" --filesystem-writepath "$DATA_DIR" --download-game "byar:test"
# Chobby lobby (menu) + a starter map
"$PRD" --filesystem-writepath "$DATA_DIR" --download-game "byar-chobby:test" || true
"$PRD" --filesystem-writepath "$DATA_DIR" --download-map "Supreme Isthmus v1.8" || true

echo "=== [5/5] Launchers ==="
cat > "$BAR_DIR/run-bar-gpu.sh" <<'EOF'
#!/bin/bash
# GPU path: Zink (GL-on-Vulkan) -> Venus -> MoltenVK -> Metal
cd "$HOME/bar/engine"
export MESA_LOADER_DRIVER_OVERRIDE=zink
export MESA_GL_VERSION_OVERRIDE=4.5
export MESA_GLSL_VERSION_OVERRIDE=450
exec ./spring --write-dir "$HOME/bar/data" --menu "rapid://byar-chobby:test" "$@"
EOF
cat > "$BAR_DIR/run-bar-cpu.sh" <<'EOF'
#!/bin/bash
# CPU fallback: native arm64 llvmpipe software rendering
cd "$HOME/bar/engine"
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
exec ./spring --write-dir "$HOME/bar/data" --menu "rapid://byar-chobby:test" "$@"
EOF
chmod +x "$BAR_DIR/run-bar-gpu.sh" "$BAR_DIR/run-bar-cpu.sh"

echo
echo "Done. Start X with: startx /usr/bin/openbox-session"
echo "Then in an X terminal: ~/bar/run-bar-gpu.sh   (or run-bar-cpu.sh)"
