# 配置材料核验记录（2026-10-23）

本记录只评价新提供的安装材料，不评价生产加速器。

- 已核对指南中的 Nangate45 TT SHA-256 与本机文件一致，确认 DFF_X1 / BUF_X1 单元及 Liberty 的 ns / fF 单位。
- 指南内全部 Bash 代码块通过现有 MSYS2 Bash 的 `bash -n` 语法检查；这不验证 Ubuntu 包、网络或 Linux 二进制兼容性。
- `run_smoke.sh` 通过 `bash -n`。
- 两级 DFF 功能小测试在 Windows Icarus 12.0 devel 上重新编译运行，`ENV_SIM_PASS`。
- Windows Verilator 5.050 首次编译失败：当前 UCRT64 没有 `python3` 命令。原失败日志保留；指南第 11 节已补充手动安装构建依赖的步骤。
- 为验证小测试本身，本次仅在独立测试命令用 `-MAKEFLAGS PYTHON3=C:/Users/12104/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe` 指定现有解释器，并采用项目原有 `-CFLAGS -D_GLIBCXX_USE_CXX11_ABI=0`。使用独立 `obj_windows_retry` 编译通过，运行得到 `ENV_SIM_PASS`。没有安装 Python 或修改 Verilator Makefile；原 Windows 构建环境的 python3 缺项仍待手动处理。
- 测试路径：`D:\3DGS\tmp\environment_setup_20261023_smoke`。包含 Icarus 构建/运行日志、`verilator-build.log` 首次失败日志、`verilator-build-retry.log` 与 `verilator-run-retry.log` 成功日志，以及小测试 VCD。
- 未执行：WSL 安装、Ubuntu apt 安装、CUDD/OpenSTA/CACTI/Ramulator Linux 编译和样例；OpenSTA Tcl 只经官方命令与本地库接口核对，未在 STA 引擎执行。Linux 完整 `run_smoke.sh` 未运行。
- 未执行：当前生产顶层综合/STA、真实场景回归、功耗与 DDR 联动；T01/T11/T12 不因此签核。

上述 Windows 补丁式调用仅为本次材料核验；Ubuntu 指南已经显式安装 python3，不应把 Windows 路径或 UCRT64 的 ABI 选项照搬到 Linux。
