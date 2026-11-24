#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${ENV_SMOKE_LIB:?Set ENV_SMOKE_LIB to Nangate45 TT Liberty}"
test -s "$ENV_SMOKE_LIB"
iverilog -g2012 -s tb -o smoke.vvp smoke_netlist.v smoke_tb.sv 2>&1 | tee iverilog-build.log
vvp smoke.vvp 2>&1 | tee iverilog-run.log
grep -q '^ENV_SIM_PASS' iverilog-run.log
test -s smoke.vcd
# Separate build directory; do not reuse a Windows Verilator executable in WSL.
verilator --binary --timing --trace --top-module tb -Wno-fatal -j 2 \
  --Mdir obj_linux smoke_netlist.v smoke_tb.sv -o env_smoke 2>&1 | tee verilator-build.log
./obj_linux/env_smoke 2>&1 | tee verilator-run.log
grep -q '^ENV_SIM_PASS' verilator-run.log
sta -no_init -exit smoke_sta.tcl 2>&1 | tee sta-smoke.log
grep -q '^ENV_STA_COMMANDS_COMPLETED_NOT_PROJECT_SIGNOFF' sta-smoke.log
if grep -Ein '(^|[[:space:]])(error|critical)([[:space:]:]|$)' sta-smoke.log; then
  echo 'Review STA errors; environment smoke is not accepted.' >&2
  exit 1
fi
sha256sum smoke_netlist.v smoke_tb.sv smoke_sta.tcl "$ENV_SMOKE_LIB" > smoke-input-sha256.txt
echo 'ENV_COMMAND_SMOKE_COMPLETE: inspect timing paths, warnings and VCD annotation before acceptance.'
