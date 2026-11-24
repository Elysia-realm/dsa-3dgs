#!/usr/bin/env bash
set -euo pipefail
base=/mnt/d/3DGS/experiments/environment_setup_20261024
logs="$base/logs"
mkdir -p "$HOME/eda/src" "$HOME/eda/opt" "$HOME/eda/logs" "$logs"
test "$(id -un)" = gs3d
trap 'printf "FAILED line=%s command=%s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
run() {
  local tag=$1; shift
  printf '%s %s\n' "$(date -Is)" "$tag"
  printf '%q ' "$@" > "$logs/$tag.command"
  printf '\n' >> "$logs/$tag.command"
  /usr/bin/time -v "$@" > "$logs/$tag.log" 2>&1
}
cd "$HOME/eda/src"
run cudd-clone timeout 180 git -c http.version=HTTP/1.1 clone --branch 3.0.0 --depth 1 https://github.com/cuddorg/cudd.git cudd
git -C cudd rev-parse HEAD > "$logs/cudd.commit.txt"
cd cudd
run cudd-configure ./configure --prefix="$HOME/eda/opt/cudd-3.0.0"
run cudd-build make -j4
run cudd-check make check
run cudd-install make install
test -s "$HOME/eda/opt/cudd-3.0.0/include/cudd.h"
test -s "$HOME/eda/opt/cudd-3.0.0/lib/libcudd.a"
cd "$HOME/eda/src"
run opensta-clone timeout 180 git -c http.version=HTTP/1.1 clone --depth 1 https://github.com/parallaxsw/OpenSTA.git OpenSTA
git -C OpenSTA checkout --detach HEAD
git -C OpenSTA rev-parse HEAD > "$logs/opensta.commit.txt"
run opensta-configure cmake -S OpenSTA -B OpenSTA/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCUDD_DIR="$HOME/eda/opt/cudd-3.0.0" -DCMAKE_INSTALL_PREFIX="$HOME/eda/opt/opensta"
run opensta-build cmake --build OpenSTA/build --parallel 4
run opensta-install cmake --install OpenSTA/build
run opensta-version "$HOME/eda/opt/opensta/bin/sta" -version
cd "$HOME/eda/src"
run cacti-clone timeout 180 git -c http.version=HTTP/1.1 clone https://github.com/HewlettPackard/cacti.git cacti
git -C cacti checkout --detach 1ffd8dfb10303d306ecd8d215320aea07651e878
git -C cacti rev-parse HEAD > "$logs/cacti.commit.txt"
cd cacti
run cacti-build make -j4
run cacti-smoke ./cacti -infile cache.cfg
cd "$HOME/eda/src"
run ramulator-clone timeout 180 git -c http.version=HTTP/1.1 clone --depth 1 https://github.com/CMU-SAFARI/ramulator.git ramulator
git -C ramulator checkout --detach HEAD
git -C ramulator rev-parse HEAD > "$logs/ramulator.commit.txt"
cd ramulator
run ramulator-build make -j4
run ramulator-lpddr4-smoke ./ramulator configs/LPDDR4-config.cfg --mode=dram --stats "$logs/ramulator-lpddr4.stats" dram.trace
echo TOOL_BUILDS_AND_EXAMPLES_COMPLETED
