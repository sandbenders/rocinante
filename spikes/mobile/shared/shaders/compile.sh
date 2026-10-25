#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Compiles the spike's shaders: GLSL to SPIR-V (Android, Vulkan) with glslc, and
# SPIR-V to Metal shading language (iOS and macOS) with spirv-cross. The outputs
# are committed, so building the spike needs neither tool. Phase 1 replaces this
# with the real pipeline (HLSL through SDL_shadercross, CLAUDE.md section 4.3).
set -eu
cd "$(dirname "$0")"
for stage in vert frag; do
  name="circle.$stage"
  case "$stage" in vert) kind=vertex ;; frag) kind=fragment ;; esac
  glslc -fshader-stage=$kind -O --target-env=vulkan1.0 "$name" -o "$name.spv"
  spirv-cross --msl --msl-version 20300 --output "$name.msl" "$name.spv"
done
