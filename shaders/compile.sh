#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Compiles rocinante's internal shaders (CLAUDE.md section 4.3) from HLSL to the
# formats the GPU backends take, into shaders/compiled/, which is committed so
# building rocinante needs none of these tools. Run it from anywhere after
# changing a .hlsl file, on a Mac or Linux computer:
#
#   needs glslang (glslang), SPIRV-Cross (spirv-cross); optionally the Metal
#   compiler (from Xcode) to check the MSL.
#
# This makes SPIR-V (Vulkan) and Metal shading language (macOS and iOS). The
# Direct3D 12 form, DXIL, needs Microsoft's DXC, which only runs on Windows and
# Linux; compile-dxil.sh makes it. SDL_shadercross does these same steps behind
# one command line (HLSL through DXC to SPIR-V, then SPIRV-Cross); it has no
# macOS build because DXC has none, so this script runs the steps by hand and
# can be replaced by shadercross where DXC exists (SHADERCROSS_COMMIT).
set -eu
cd "$(dirname "$0")"
mkdir -p compiled

# <file> <stage name for glslang> <HLSL entry point> <suffix>
compile_stage() {
  file=$1 stage=$2 entry=$3 suffix=$4
  name=${file%.hlsl}
  # glslang names the SPIR-V entry point "main"; SPIRV-Cross then calls it
  # "main0" in Metal, which is the name the renderer asks SDL for.
  glslang -D -V -S "$stage" -e main --source-entrypoint "$entry" --auto-sampled-textures -I. "$file" -o "compiled/$name.$suffix.spv"
  spirv-cross --msl --msl-version 20300 --output "compiled/$name.$suffix.msl" "compiled/$name.$suffix.spv"
}

for file in *.hlsl; do
  compile_stage "$file" vert vs_main vert
  compile_stage "$file" frag ps_main frag
done

# Check the Metal source compiles, when a working Metal compiler is there (Xcode
# can have it missing: xcodebuild -downloadComponent MetalToolchain). SDL builds
# the Metal source when the program creates the shader, so a run also checks it.
if command -v xcrun >/dev/null 2>&1 && xcrun metal -c -std=metal2.3 compiled/shapes.vert.msl -o /dev/null 2>/dev/null; then
  for msl in compiled/*.msl; do
    xcrun metal -c -std=metal2.3 "$msl" -o /dev/null
  done
  echo "metal: ok"
else
  echo "metal: compiler not available, MSL not checked"
fi
echo "compiled $(command ls compiled | wc -l | tr -d ' ') files"
