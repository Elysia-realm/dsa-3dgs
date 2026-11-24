#!/usr/bin/env bash
set -euo pipefail
base=/mnt/d/3DGS/experiments/environment_setup_20261024
logs="$base/logs"
archives=/mnt/d/3DGS/tmp/toolchains/linux_sources_20261024
sources="$HOME/eda/src-20261024"
mkdir -p "$sources" "$HOME/eda/opt" "$logs"
test "$(id -un)" = gs3d
trap 'printf "FAILED line=%s command=%s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
run() {
  local tag=$1; shift
  printf '%s %s\n' "$(date -Is)" "$tag"
  printf '%q ' "$@" > "$logs/$tag.command"
  printf '\n' >> "$logs/$tag.command"
  /usr/bin/time -v "$@" > "$logs/$tag.log" 2>&1
}
for name in cudd OpenSTA cacti; do
  test -s "$archives/$name.tar.gz"
  mkdir -p "$sources/$name"
  tar -xzf "$archives/$name.tar.gz" -C "$sources/$name" --strip-components=1
done
cd "$sources/cudd"
run cudd-configure ./configure --prefix="$HOME/eda/opt/cudd-3.0.0"
run cudd-build make -j4
run cudd-check make check
run cudd-install make install
test -s "$HOME/eda/opt/cudd-3.0.0/include/cudd.h"
test -s "$HOME/eda/opt/cudd-3.0.0/lib/libcudd.a"
cd "$sources"
run opensta-configure cmake -S OpenSTA -B OpenSTA/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCUDD_DIR="$HOME/eda/opt/cudd-3.0.0" -DCMAKE_INSTALL_PREFIX="$HOME/eda/opt/opensta"
run opensta-build cmake --build OpenSTA/build --parallel 4
run opensta-install cmake --install OpenSTA/build
run opensta-version "$HOME/eda/opt/opensta/bin/sta" -version
cd "$sources/cacti"
run cacti-build make -j4
run cacti-smoke ./cacti -infile cache.cfg
test -s "$archives/ramulator.tar.gz"
mkdir -p "$sources/ramulator"
tar -xzf "$archives/ramulator.tar.gz" -C "$sources/ramulator" --strip-components=1
cd "$sources/ramulator"
run ramulator-build make -j4
run ramulator-lpddr4-smoke ./ramulator configs/LPDDR4-config.cfg --mode=dram --stats "$logs/ramulator-lpddr4.stats" dram.trace
echo TOOL_BUILDS_AND_EXAMPLES_COMPLETED
