# SPDX-License-Identifier: 0BSD
#
# The image `tools/package-linux-docker.sh` makes Linux apps in, for people on a Mac or a Windows computer, and the one
# `tools/ci/package-linux-distros.sh arch` makes the Arch package in: Arch (what the
# pipeline uses too) with the compiler, SDL3, the shader libraries and the tools `roci package linux` makes its formats with
# (tar, ar, zstd, mksquashfs). It is x86-64, so a package made in it runs on the computers most people have; on an Apple silicon
# Mac that runs under emulation, which is slow but works. Build it from the repository root:
#
#   docker build --platform linux/amd64 -t rocinante-linux -f tools/ci/package-linux.Dockerfile .
ARG BASE=docker.io/library/archlinux:latest
FROM ${BASE}

# DisableSandbox: pacman's download sandbox needs a system call that emulation does not have, and the image is thrown away anyway.
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf \
 && pacman -Syu --noconfirm clang gcc make cmake ninja curl tar unzip git pkgconf rsync binutils zstd squashfs-tools sdl3 sdl3_ttf shaderc spirv-cross diffutils \
 && yes | pacman -Scc

# The pinned Odin, in /opt/odin.
COPY ODIN_VERSION /tmp/rocinante/ODIN_VERSION
COPY tools/ci/install-odin.sh /tmp/rocinante/tools/ci/install-odin.sh
RUN /tmp/rocinante/tools/ci/install-odin.sh /opt/odin && rm -rf /tmp/rocinante
ENV PATH=/opt/odin:$PATH
