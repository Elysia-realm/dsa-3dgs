#!/usr/bin/env bash
set -euo pipefail
base=/mnt/d/3DGS/experiments/environment_setup_20261024
python3 "$base/patch_cacti_io.py"
cd "$HOME/eda/src-20261024/cacti"
/usr/bin/time -v make -j4 > "$base/logs/cacti-build-patched.log" 2>&1
python3 "$base/cacti_diagnostic.py"
# Negative test: original sample omits the required tflight numeric value.
set +e
./cacti -infile cache.cfg > "$base/logs/cacti-invalid-config.log" 2>&1
result=$?
set -e
test "$result" -ne 0
grep -q 'Invalid -tflight_value' "$base/logs/cacti-invalid-config.log"
echo CACTI_PATCH_POSITIVE_AND_NEGATIVE_CHECKS_COMPLETE
