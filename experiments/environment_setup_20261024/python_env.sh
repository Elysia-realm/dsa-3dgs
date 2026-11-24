#!/usr/bin/env bash
set -euo pipefail
base=/mnt/d/3DGS/experiments/environment_setup_20261024
exec > >(tee "$base/logs/python-install.log") 2>&1
python3 -m venv "$HOME/eda/venvs/gsverify"
source "$HOME/eda/venvs/gsverify/bin/activate"
python -m pip install --timeout 30 --retries 2 numpy==2.3.5 Pillow==12.3.0
python -m pip freeze > "$base/logs/python-requirements.txt"
python -c 'import sys,numpy,PIL; print(sys.executable); print(sys.version); print(numpy.__version__,PIL.__version__)'
python -m pip check
echo PYTHON_ENV_COMPLETE
