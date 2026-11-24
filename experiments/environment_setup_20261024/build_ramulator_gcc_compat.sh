#!/usr/bin/env bash
set -euo pipefail
logs=/mnt/d/3DGS/experiments/environment_setup_20261024/logs
cd "$HOME/eda/src-20261024/ramulator"
# GCC 13 no longer provides uint64_t via the old transitive includes.
# Explicitly preinclude the standard header without changing upstream source.
printf '%s\n' 'make CXX=g++ CXXFLAGS="-O3 -std=c++11 -g -Wall -include cstdint" -j4' > "$logs/ramulator-build-gcc-compat.command"
/usr/bin/time -v make CXX=g++ CXXFLAGS='-O3 -std=c++11 -g -Wall -include cstdint' -j4 > "$logs/ramulator-build-gcc-compat.log" 2>&1
/usr/bin/time -v ./ramulator configs/LPDDR4-config.cfg --mode=dram --stats "$logs/ramulator-lpddr4.stats" dram.trace > "$logs/ramulator-lpddr4-smoke.log" 2>&1
echo RAMULATOR_BUILD_AND_LPDDR4_COMPLETE
