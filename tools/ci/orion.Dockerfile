# SPDX-License-Identifier: 0BSD
#
# The image ORION's GitLab jobs run in: Arch with everything the pipeline needs
# already installed, so a job starts compiling at once instead of downloading and
# installing about a gigabyte first. The runner pulls images only when they are
# missing, so the image built on ORION itself is the one the jobs use.
#
# Build it on ORION, from the repository root, and again now and then to bring Arch
# up to date (a new Odin in ODIN_VERSION needs no rebuild: the pipeline fetches it
# when the image's is another):
#
#   docker build --pull -t rocinante-ci -f tools/ci/orion.Dockerfile .
FROM archlinux:latest

# clang links Odin's programs; unzip opens accesskit-c's release archive (tools/ui-libs.sh accesskit); gcc (with its binutils) compiles Dear ImGui, which is C++, with tools/ui-libs.sh; sdl3 is linked by the engine's tests; diffutils for
# the format checks; shaderc and spirv-cross translate a sketch's own shaders (the tests link
# them); vulkan-swrast is Mesa's software Vulkan (lavapipe), which draws
# the golden images. The package cache is emptied so the image stays small.
RUN pacman -Syu --noconfirm clang gcc curl tar unzip git sdl3 sdl3_ttf shaderc spirv-cross diffutils vulkan-swrast \
 && yes | pacman -Scc

# The pinned Odin, in /opt/odin.
COPY ODIN_VERSION /tmp/rocinante/ODIN_VERSION
COPY tools/ci/install-odin.sh /tmp/rocinante/tools/ci/install-odin.sh
RUN /tmp/rocinante/tools/ci/install-odin.sh /opt/odin && rm -rf /tmp/rocinante
