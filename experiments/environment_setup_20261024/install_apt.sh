#!/usr/bin/env bash
set -euo pipefail
base=/mnt/d/3DGS/experiments/environment_setup_20261024
mkdir -p "$base/logs"
exec > >(tee "$base/logs/apt-install.log") 2>&1
test "$(id -u)" = 0
dpkg-query -W > "$base/logs/apt-packages-before.txt"
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 update
apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 install -y \
  build-essential git ca-certificates curl wget cmake ninja-build pkg-config \
  autoconf automake libtool bison flex swig tcl8.6 tcl-dev zlib1g-dev \
  libeigen3-dev libfmt-dev python3 python3-venv python3-pip \
  iverilog verilator gtkwave rsync unzip ripgrep time
dpkg-query -W > "$base/logs/apt-packages-after.txt"
echo APT_INSTALL_COMPLETE
