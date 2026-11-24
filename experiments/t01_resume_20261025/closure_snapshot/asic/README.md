# ASIC 综合与验证入口

## 2026-10-28 当前执行入口

T01已按WSL接入与首次物理反馈范围签核，最终时序/电气/PPA未通过。以`verification/t06_release_profile.json`冻结的当前生产参数为准；
原2026-10-03整缓存黑盒流程和报告保留作历史，不作为当前顶层STA输入。
当前入口为`asic/scripts/run_t01_wsl_synthesis.py`及`run_t01_wsl_sta.py`，实际约束由
`run_t01_wsl_sta.tcl`生成并归档为每次运行的`applied.sdc`。旧`constraints/gs_accel_system_top.sdc`
是历史占位文件，本轮不采用其中的整复位false path。

本轮已保留原RTL全部控制和阵列并映射为标准单元，四组双工艺TT顶层STA完成；最终SRAM宏仍归T11。
验收与严重物理风险见`docs/T01恢复轮验收与物理风险交接_2026-10-28.md`，处理计划见`docs/T01问题闭环与后续开发计划_2026-10-28.md`。
进度/失败与范围见`docs/开发日志_2026-10-25_T01恢复执行.md`，证据目录为
`experiments/t01_resume_20261025`。保留Windows系统保护，不等待解除MSYS2拦截。

## 2026-10-03 T01 断点恢复交付

本轮已建立 Native Yosys/ABC 真实目标库映射流程，本轮证据统一保存于
`asic/reports/t01/首次映射报告_2026-10-03.md` 与 `comparison.json`；工具/库版本和文件哈希见
`toolchain_manifest.json`。重放入口为 `asic/scripts/run_t01_matrix.ps1`，单次运行可用
`run_t01_synthesis.py --help` 配置工具、库和输出目录。

**T01 仍为部分完成，未签核。** 用户已选择暂不配置 Linux/OpenSTA，交付当前结果。
STA 脚本仅准备未执行；缓存控制和存储边界显式排除，最终时序/面积/功耗还需 T11/T12。
ABC 的模块内时序估计不能代替顶层 STA。ICsprout55 TT/SS/FF 库已取得；当前选用的
ORFS Nangate45 分发只有 TT，FreePDK45 SS/FF 仍缺。后续可先推进 T02。

T02 修改源码后的恢复版本与保存路径见 `asic/reports/t01/T02后断点说明_2026-10-04.md`。
原 T01 数据属于 2026-10-03 源码快照，不能作为新源码的 PPA 证据。

本目录用于把当前完整 SystemVerilog RTL 接入 ASIC 标准单元逻辑综合、STA、面积和活动功耗分析流程。T00 已于 2026-09-29 冻结为综合级验收，不要求布局布线、寄生提取、DRC/LVS 或 DFT；当前结果仍未达到 PPA 签核。

## 当前入口

- 综合顶层：`gs_accel_system_top`
- RTL 文件清单：`verification/rtl/system_top_sources.f`
- 时钟：`clk_i`
- 低有效异步复位：`rst_ni`
- 基础约束：`asic/constraints/gs_accel_system_top.sdc`

约束中的 5.0 ns 对应 T00 的最低通过频率 200 MHz；目标为 300 MHz，1 GHz 为 GCC 对标冲刺值。T01 须按 PDK/corner 生成约束并验证，不能因 SDC 中写有 5 ns 就判定通过。无真实封装/SoC 预算时，时钟不确定度为周期 5%，输入/输出延迟各为周期 10%。

## 获得可信 PPA 前必须补齐

1. ICsprout55 和 FreePDK45 的发布版本、配套标准单元库变体及文件哈希。
2. CACTI SRAM 配置与读写时序；当前 RTL memory wrapper 必须与其端口、容量和延迟一致。
3. 两套库实际提供的 SS/TT/FF Liberty 文件及电压、温度。
4. 200/300 MHz 约束，以及 APB、AXI 和外部 source/commit 接口的 I/O 时序预算。
5. 综合、STA、功耗、CACTI 和 Ramulator/LPDDR4 工具版本及脚本。
6. 由代表性完整场景 RTL/gate 仿真导出的 VCD 或 SAIF；无活动文件时只能得到粗略向量无关估计。

## 推荐签核顺序

1. 用当前 SDC 做 elaboration、lint 和 pre-synthesis timing sanity check。
2. 映射标准单元，并以 CACTI 模型核算 SRAM；检查 unconstrained endpoints、latch、组合环和多驱动。
3. 在多 PVT corner 下综合和 STA，修复 setup/hold，不以屏蔽路径代替修复。
4. 用完整场景活动文件计算动态功耗，并分别报告内部、开关、漏电和 SRAM 功耗。
5. 报告面积时区分综合标准单元面积、CACTI SRAM 面积与合计值；同时报告频率、corner 和约束版本。
6. 用 Ramulator 的 LPDDR4 配置或等效 LPDDR4 模型报告片外延迟、流量和能耗；片外功耗与 1 W 芯片核上限分列。

动态 G/P/R/E 模式主要通过 lane enable/clock-enable 改变活动率。综合阶段应保留 clock-enable 语义；是否插入集成时钟门控单元，必须由目标工艺的 clock-gating flow 决定并做门控检查。

## 结果边界

正式硬线为：每个正式视角 30 FPS、200 MHz、标准单元加 SRAM 面积不超过 4 mm²、片上存储不超过 300 KB、芯片核功耗不超过 1 W；目标线为 300 MHz、2.7 mm²、0.8 W。上述输入未准备完成前，只报告工艺无关的 RTL 正确性、周期数、结构趋势和内存事务，不给出虚构的面积、功耗或 ASIC FPS。

2026-09-17 的形状候选资源隔离轮次已用 Verilator 顶层展开确认：默认配置 0 个
`gaussian_shape_block_reject` 实例，启用候选为 1 个，两者仍各有 1 个共享 PE；
这是结构证据，不是映射后单元面积、关键路径或功耗数字。2026-09-17 时本机尚无 Yosys/OpenSTA、
目标标准单元 `.lib` 与 CACTI 配置，PPA 仍未执行；该历史事实由 T01 重新核实。

2026-09-17 新增默认关闭的 `ENABLE_ALPHA_ZERO_SKIP` 顶层参数。当前源码 15 负载的
120/120 个候选配置 RGB/T 等价且比共享投影基线快，减少 45,496 次像素状态读、
72,688 次写；这是映射前的周期/事务证据，不是 ASIC 面积或能耗证明。目标工艺
准备好后，应以同一 PDK、PVT、SRAM 宏、时钟和负载活动分别综合参数 `0`/`1`：
对照标准单元与宏面积、WNS/TNS、关键 ready/valid 路径、频率、动态/漏电及
状态存储访问能耗；候选新增的控制选择与诊断计数也应计入面积。稀疏 n128 d8
只省 1–6 周期，应作为低收益边界用例保留。与 `ENABLE_SHAPE_BLOCK_REJECT`
联合启用的增量效益见下文 2026-09-19 更新，不得把两候选的单独节省相加。

2026-09-19 更新：联合消融已完成，五负载 40 个联合配置相对 alpha-only 为
16 提速/24 持平/0 退化，平均额外节省 0.787% 周期，额外状态读写减少为 0。
展开 AST 确认 alpha-only 不增加乘法节点，联合方案多一个有符号乘法节点；
这是源码结构比较，节点数不能当作映射后硬件数量。首轮 ASIC 消融优先比较
共享基线与 alpha-only，再用联合方案评估该额外判定器的面积/时序/活动代价。
证据：`experiments/shape_alpha_20260919_audit.json` 与
`experiments/shape_alpha_20260919_structure.json`。
