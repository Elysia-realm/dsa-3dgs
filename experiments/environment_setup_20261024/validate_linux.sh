#!/usr/bin/env bash
set -euo pipefail
base=/mnt/d/3DGS/experiments/environment_setup_20261024
export PATH="$HOME/eda/opt/opensta/bin:$PATH"
smoke="$HOME/work/3dgs-env-smoke-20261024-v2"
mkdir -p "$smoke" "$base/smoke-v2"
cp /mnt/d/3DGS/docs/environment_setup_20261023/{smoke_netlist.v,smoke_tb.sv,smoke_sta.tcl,run_smoke.sh} "$smoke/"
sed -i 's/\r$//' "$smoke/run_smoke.sh"
export ENV_SMOKE_LIB=/mnt/d/3DGS/tmp/toolchains/freepdk45/NangateOpenCellLibrary_typical.lib
cd "$smoke"
set +e
bash run_smoke.sh > "$base/logs/linux-smoke-driver-v2.log" 2>&1
result=$?
set -e
cp ./*.log ./*.txt ./*.v ./*.sv ./*.tcl ./*.sh "$base/smoke-v2/"
if test -f smoke.vcd; then cp ./*.vcd "$base/smoke-v2/"; fi
echo "LINUX_SMOKE_EXIT=$result"
exit "$result"
