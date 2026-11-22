# SPDX-License-Identifier: 0BSD
#
# Fedora with what `roci package linux` needs, for `tools/ci/package-linux-distros.sh`, as the Debian one: the compilers (with
# libstdc++-static, since SDL3_ttf has the C++ library linked into it), SDL's build dependencies, the pinned Odin, SDL 3.4.18
# and SDL_ttf 3.2.2, SPIRV-Cross at its pin, and Fedora's shaderc, whose library is already libshaderc_shared. Built from the
# repository root:
#
#   podman build --build-arg BASE=docker.io/library/fedora:43 -t roci-pkg-fedora -f tools/ci/package-fedora.Containerfile .
ARG BASE=docker.io/library/fedora:43
FROM ${BASE}
RUN dnf install -y --setopt=install_weak_deps=False \
    ca-certificates curl git-core rsync unzip xz tar zstd squashfs-tools binutils file \
    gcc gcc-c++ libstdc++-static make clang cmake ninja-build pkgconf-pkg-config \
    libX11-devel libXext-devel libXrandr-devel libXcursor-devel libXfixes-devel libXi-devel libXScrnSaver-devel libXtst-devel \
    libxkbcommon-devel wayland-devel wayland-protocols-devel libdecor-devel libdrm-devel mesa-libgbm-devel mesa-libEGL-devel mesa-libGLES-devel \
    vulkan-loader-devel alsa-lib-devel pulseaudio-libs-devel pipewire-devel systemd-devel dbus-devel ibus-devel libusb1-devel \
    freetype-devel harfbuzz-devel libshaderc-devel \
 && dnf clean all
COPY ODIN_VERSION /tmp/r/ODIN_VERSION
COPY tools/ci/install-odin.sh tools/ci/install-sdl3.sh tools/ci/install-spirv-cross.sh /tmp/r/tools/ci/
RUN sh /tmp/r/tools/ci/install-odin.sh /opt/odin \
 && sh /tmp/r/tools/ci/install-sdl3.sh /opt/sdl3 release-3.4.18+release-3.2.2 \
 && sh /tmp/r/tools/ci/install-spirv-cross.sh /opt/spirv-cross \
 && printf '/opt/sdl3/lib\n/opt/sdl3/lib64\n/opt/spirv-cross/lib\n/opt/spirv-cross/lib64\n' > /etc/ld.so.conf.d/rocinante.conf && ldconfig && rm -rf /tmp/r
ENV PATH=/opt/odin:$PATH \
    LIBRARY_PATH=/opt/spirv-cross/lib:/opt/spirv-cross/lib64:/opt/sdl3/lib:/opt/sdl3/lib64 \
    PKG_CONFIG_PATH=/opt/sdl3/lib/pkgconfig:/opt/sdl3/lib64/pkgconfig
