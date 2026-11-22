# SPDX-License-Identifier: 0BSD
#
# Debian or Ubuntu with what `roci package linux` needs, for `tools/ci/package-linux-distros.sh`: the compilers, SDL's build
# dependencies (SDL loads the video and sound libraries at run time, but a backend is built only when its headers are here),
# the pinned Odin, SDL 3.4.18 and SDL_ttf 3.2.2, SPIRV-Cross at its pin, and shaderc: the distribution's (`SHADERC=system`,
# linked through a `libshaderc_shared.so` link to its `libshaderc.so.1`) or one built from source (`SHADERC=source`, for
# Debian 12, whose own cannot be linked alone). Built from the repository root:
#
#   podman build --build-arg BASE=docker.io/library/debian:12 --build-arg SHADERC=source -t roci-pkg-debian -f tools/ci/package-debian.Containerfile .
ARG BASE=docker.io/library/debian:12
FROM ${BASE}
ARG SHADERC=system
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git rsync unzip xz-utils tar zstd squashfs-tools binutils file \
    build-essential clang cmake ninja-build pkg-config \
    libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev libxss-dev libxtst-dev \
    libxkbcommon-dev libwayland-dev wayland-protocols libdecor-0-dev libdrm-dev libgbm-dev libegl1-mesa-dev libgles2-mesa-dev \
    libvulkan-dev libasound2-dev libpulse-dev libpipewire-0.3-dev libudev-dev libdbus-1-dev libibus-1.0-dev libusb-1.0-0-dev \
    libfreetype-dev libharfbuzz-dev \
 && if [ "$SHADERC" = system ]; then apt-get install -y --no-install-recommends libshaderc-dev; fi \
 && rm -rf /var/lib/apt/lists/*
COPY ODIN_VERSION /tmp/r/ODIN_VERSION
COPY tools/ci/install-odin.sh tools/ci/install-sdl3.sh tools/ci/install-spirv-cross.sh tools/ci/install-shaderc.sh /tmp/r/tools/ci/
RUN sh /tmp/r/tools/ci/install-odin.sh /opt/odin \
 && sh /tmp/r/tools/ci/install-sdl3.sh /opt/sdl3 release-3.4.18+release-3.2.2 \
 && sh /tmp/r/tools/ci/install-spirv-cross.sh /opt/spirv-cross \
 && if [ "$SHADERC" = source ]; then sh /tmp/r/tools/ci/install-shaderc.sh /opt/shaderc; \
    else mkdir -p /opt/shaderc/lib && ln -s "$(ls /usr/lib/*-linux-gnu/libshaderc.so.1)" /opt/shaderc/lib/libshaderc_shared.so; fi \
 && printf '/opt/sdl3/lib\n/opt/spirv-cross/lib\n/opt/shaderc/lib\n' > /etc/ld.so.conf.d/rocinante.conf && ldconfig && rm -rf /tmp/r
ENV PATH=/opt/odin:$PATH \
    LIBRARY_PATH=/opt/shaderc/lib:/opt/spirv-cross/lib:/opt/sdl3/lib \
    PKG_CONFIG_PATH=/opt/sdl3/lib/pkgconfig
