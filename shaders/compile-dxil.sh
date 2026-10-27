#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Makes the Direct3D 12 form of the internal shaders (DXIL) with Microsoft's
# DXC (https://github.com/microsoft/DirectXShaderCompiler/releases, the
# dxc_*.zip, whose bin/x64 folder must be on the PATH, with dxil.dll beside
# dxc.exe so the shaders are signed and D3D12 accepts them). The Windows SDK
# that the Visual Studio Build Tools install has both, so this is enough:
#     PATH="/c/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64:$PATH" shaders/compile-dxil.sh
# Run it in Git Bash
# on Windows after compile.sh changed anything, and commit the results.
set -eu
cd "$(dirname "$0")"
mkdir -p compiled
for file in *.hlsl; do
  name=${file%.hlsl}
  dxc -nologo -I . -T vs_6_0 -E vs_main "$file" -Fo "compiled/$name.vert.dxil"
  dxc -nologo -I . -T ps_6_0 -E ps_main "$file" -Fo "compiled/$name.frag.dxil"
done
echo "compiled $(command ls compiled/*.dxil | wc -l | tr -d ' ') DXIL files"
