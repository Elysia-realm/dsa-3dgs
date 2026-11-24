#!/usr/bin/env bash
set -euo pipefail
base=/mnt/d/3DGS/experiments/t01_resume_20261025
dest="$HOME/eda/opt/oss-cad-suite-20260706"
mkdir -p "$dest"
tar -xzf /mnt/d/3DGS/tmp/toolchains/oss-cad-suite-linux-x64-20260706.tgz -C "$dest"
"$dest/oss-cad-suite/bin/yosys" -V | tee "$base/yosys-version.txt"
"$dest/oss-cad-suite/bin/verilator" --version | tee "$base/verilator-version.txt"
"$dest/oss-cad-suite/bin/yosys-abc" -c version > "$base/abc-version.txt" 2>&1
