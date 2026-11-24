#!/usr/bin/env bash
set -euo pipefail
logs=/mnt/d/3DGS/experiments/environment_setup_20261024/logs
cd "$HOME/eda/src-20261024/ramulator"
printf '%s\n' 'make CXX=g++ -j4' > "$logs/ramulator-build-gcc.command"
/usr/bin/time -v make CXX=g++ -j4 > "$logs/ramulator-build-gcc.log" 2>&1
printf '%s\n' './ramulator configs/LPDDR4-config.cfg --mode=dram --stats <logs>/ramulator-lpddr4.stats dram.trace' > "$logs/ramulator-lpddr4-smoke.command"
/usr/bin/time -v ./ramulator configs/LPDDR4-config.cfg --mode=dram --stats "$logs/ramulator-lpddr4.stats" dram.trace > "$logs/ramulator-lpddr4-smoke.log" 2>&1
echo RAMULATOR_BUILD_AND_LPDDR4_COMPLETE
