#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  debootstrap qemu-user qemu-user-binfmt binfmt-support \
  dosfstools e2fsprogs parted rsync xz-utils ca-certificates \
  git make bc bison flex libssl-dev libelf-dev dwarves \
  gcc-arm-linux-gnueabihf device-tree-compiler u-boot-tools \
  curl wget file cpio
apt-get clean
