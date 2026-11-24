#!/usr/bin/env python3
"""Collect measured T01 artifacts; never turn mapping/ABC timing into signoff."""
import json
from collections import defaultdict
from pathlib import Path
from run_t01_synthesis import sha256_file

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "asic/reports/t01"
summaries = [json.loads(p.read_text()) for p in sorted((OUT / "runs").glob("*/*/*/*/summary.json"))]
inventory = {
    "date": "2026-10-03",
    "synthesis": {"tool": "OSS CAD Suite Windows x64 20260706", "yosys": "0.66+183 b285b72e3", "abc": "1.01 (2026-07-03)", "source": "https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2026-07-06"},
    "unused_frontend": {"tool": "yowasp-yosys 0.69.0.0.post1233", "reason": "Native Yosys selected for working ABC target-library mapping"},
    "opensta": {"status": "NOT_INSTALLED_NOT_EXECUTED", "user_decision": "2026-10-03: defer Linux environment and deliver existing evidence", "script": "asic/scripts/run_t01_sta.tcl"},
    "memory": {"cacti": "NOT_INSTALLED_T11", "ramulator": "NOT_INSTALLED_T11", "cache_boundary_timing_model": "MISSING_T11", "cache_control_included": False},
    "libraries": [],
}
specs = [
    ("FreePDK45/Nangate45", "TT", "tmp/toolchains/freepdk45/NangateOpenCellLibrary_typical.lib", "ORFS master snapshot, Liberty revision 1.0 (2011-02-10); pinned by SHA-256", 1.1, 25, "https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/master/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib"),
    ("ICsprout55 RVT H7CR", "TT", "tmp/toolchains/icsprout55/rvt-v1.10.102/liberty/ics55_LLSC_H7CR_typ_tt_1p2_25_nldm.lib", "v1.10.102", 1.2, 25, "https://github.com/openecos-projects/icsprout55-pdk/releases/tag/v1.10.102"),
    ("ICsprout55 RVT H7CR", "SS", "tmp/toolchains/icsprout55/rvt-v1.10.102/liberty/ics55_LLSC_H7CR_ss_rcworst_1p08_125_nldm.lib", "v1.10.102", 1.08, 125, "https://github.com/openecos-projects/icsprout55-pdk/releases/tag/v1.10.102"),
    ("ICsprout55 RVT H7CR", "FF", "tmp/toolchains/icsprout55/rvt-v1.10.102/liberty/ics55_LLSC_H7CR_ff_rcbest_1p32_m40_nldm.lib", "v1.10.102", 1.32, -40, "https://github.com/openecos-projects/icsprout55-pdk/releases/tag/v1.10.102"),
]
for pdk, corner, rel, version, voltage, temp, url in specs:
    p = ROOT / rel
    inventory["libraries"].append(dict(pdk=pdk, corner=corner, path=rel, version=version, voltage=voltage, temperature_c=temp, source=url, bytes=p.stat().st_size, sha256=sha256_file(p)))
inventory["freepdk45_ss_ff"] = "MISSING: selected ORFS Nangate45 distribution supplies TT only; T00 SS/TT/FF requirement remains open"
inventory["license_notes"] = "ICsprout55 Liberty headers: Apache-2.0. Nangate Liberty copyright/license notices preserved; downloaded from official ORFS distribution. No commercial-license server used."
inventory["archives"] = []
for rel in ["tmp/toolchains/oss-cad-suite-windows-x64-20260706.exe", "tmp/toolchains/icsprout55/ics55_LLSC_H7CR_liberty.tar.bz2"]:
    p = ROOT / rel
    inventory["archives"].append(dict(path=rel, bytes=p.stat().st_size, sha256=sha256_file(p)))
(OUT / "toolchain_manifest.json").write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

comparison = {"task_status": "PARTIAL_EXTERNAL_BLOCKED", "ppa_signed_off": False, "runs": summaries, "within_library_comparisons": []}
costs = []
for s in summaries:
    stat = json.loads((ROOT / s["artifacts"]["mapped_stats"]).read_text())
    modules = {name.lstrip("\\"): value for name, value in stat["modules"].items()}
    buckets = defaultdict(float)
    def visit(name, copies):
        m = modules[name]
        # Local gate area only; hierarchical child area must not be counted twice.
        short = name.lstrip("\\")
        if "\\" in name.lstrip("\\"):
            short = name.lstrip("\\").split("\\")[1]
        buckets[short] += copies * float(m["num_cells"]["local_area"])
        for child, value in m.get("num_submodules_by_type", {}).items():
            child = child.lstrip("\\")
            if child in modules:
                visit(child, copies * int(value["count"]))
            elif float(value["area"]) != 0:
                raise ValueError(f"Missing nonzero-area child module: {child}")
    visit(next(n for n in modules if n.lstrip("\\") == "gs_accel_system_top"), 1)
    expected = s["mapped"]["standard_cell_area_um2"]
    if expected is not None and abs(sum(buckets.values()) - expected) > 0.1:
        raise ValueError("Hierarchical area accounting does not match design total")
    costs.append(dict(pdk=s["pdk"], variant=s["variant"], area_um2_by_module_family=dict(sorted(buckets.items(), key=lambda kv: -kv[1]))))
comparison["module_costs"] = costs
for pdk in sorted({s["pdk"] for s in summaries}):
    runs = {s["variant"]: s for s in summaries if s["pdk"] == pdk}
    if set(runs) != {"shared_baseline", "alpha_only"}: continue
    b, a = runs["shared_baseline"], runs["alpha_only"]
    ba, aa = b["mapped"]["standard_cell_area_um2"], a["mapped"]["standard_cell_area_um2"]
    if ba is None or aa is None: continue
    comparison["within_library_comparisons"].append(dict(pdk=pdk, area_delta_um2=aa-ba, area_delta_percent=100*(aa/ba-1), timing_kind="ABC module-local proxy only", signoff=False))
(OUT / "comparison.json").write_text(json.dumps(comparison, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

lines = ["# T01 首次 ASIC 映射报告（2026-10-03）", "", "状态：**部分完成 / STA 外部阻塞；T01 未签核，PPA 未通过。**", "",
"用户已明确选择暂不配置 Linux/OpenSTA 环境，保留 STA 阻塞并交付已有结果。现有工具链与首轮映射工作在此停止，不进行低收益调参。", "",
"## 1. 实际结果", "", "| 工艺 / TT 角 | 配置 | 标准单元面积 mm² | 单元数（含已声明黑盒） | ABC 最长模块内延迟 ns | 未知单元 |", "| --- | --- | ---: | ---: | ---: | --- |"]
for s in summaries:
    m, t = s["mapped"], s["timing"]
    area, delay = m["standard_cell_area_mm2"], t["worst_module_delay_ps"]
    lines.append(f'| {s["pdk"]} / {s["corner"]} | {s["variant"]} | {area:.6f} | {int(m["cell_count"]):,} | {delay/1000:.3f} | {m["unknown_cell_types"] or "无"} |' if area is not None and delay is not None else f'| {s["pdk"]} | {s["variant"]} | 待解析 | — | — | {m["unknown_cell_types"]} |')
lines += ["", "面积来自 Yosys 实际读取目标 Liberty 后的实例累计；ABC 延迟只覆盖各模块内组合逻辑，不能替代跨层级 STA、WNS/TNS 或最高工作频率。未生成实际功耗、FPS 或最终核心面积结论。", ""]
for c in comparison["within_library_comparisons"]:
    lines.append(f'- {c["pdk"]}：alpha-only 相对共享基线面积增加 {c["area_delta_um2"]:.3f} µm²（{c["area_delta_percent"]:+.4f}%）。这是控制逻辑成本，不是功耗或吞吐收益证明。')
lines += ["", "## 2. 比较条件与结果边界", "",
"- 顶层 `gs_accel_system_top`；正式源清单 `verification/rtl/system_top_sources.f`。共享 G/P 开启、共享 R 关闭，其余生产参数维持默认；两组仅修改 `ENABLE_ALPHA_ZERO_SKIP=0/1`。",
"- 映射约束为 200 MHz（5 ns）。每个库内使用相同驱动单元、输出负载、脚本和缓存边界。跨工艺电压与单元结构不同，原始面积/延迟不视为严格归一化 GCC 对标。",
"- 采用分层综合和快速 ABC 映射；未进行跨模块常量传播/全局优化。面积是这套具体网表的成本，不代表优化后的最小实现。",
"- 唯一源替换为 `image_state_cache_backend` 显式黑盒；**整个缓存边界及其控制逻辑均未计入面积和时序**。内部数组按默认参数估算为 425,984 bit（52 KiB），不是整个芯片存储总量，也不是 SRAM 面积估计。最终恢复控制逻辑、CACTI 存储面积/能耗和延迟合同归 T11。",
"- 其他保留的存储/流水线寄存器按映射后的标准单元计入面积；指数 LUT ROM 已要求显式映射，不能以通用 `$mem_v2` 零成本漏算。",
"- 现有映射面积已明显高于 4 mm² 限制，模块内延迟估计超过 5 ns；后续优先检查宽除法/开方流水线、协方差/SH 运算和寄存器式状态存储。这里只定位风险，不在 T01 展开架构优化。", "",
"## 3. 已修复与验证", "",
"1. 将 `covariance2d_cholesky_encoder.sv` 中两个数据相关 while 循环改为等价的固定次数扫描，消除 Yosys 动态循环展开失败。",
"2. ABC `map` 后增加 `cleanup`，清除无 fanout 节点，修复 `buffer` 报错；失败日志保留。",
"3. 显式映射 LUT ROM；兼容当前 Yosys 分层统计 JSON 的 count/area 格式；任何未声明的非库单元均报告并返回失败。",
"4. Icarus Cholesky encoder 定向测试 PASS；正式生产顶层编译退出码 0，详见 `validation/`。这不是门级等价或整个系统发布回归。", "",
"原生 Windows ABC 会报告 merged-SCL 缓存转换的路径引用警告，然后回退直接读取 Liberty。成功日志保留实际读库、映射单元和结束标记；这不代表跳过了目标库。", "",
"## 4. 工具与库", "",
"详见 `toolchain_manifest.json`：Native Yosys 0.66+183 / ABC 1.01；ICsprout55 RVT v1.10.102 的 TT/SS/FF 已保存并哈希；FreePDK45 使用 Nangate45 TT。所选 ORFS 分发中未取得 FreePDK45 SS/FF Liberty，T00 的三角目标保留。ICsprout55 本轮只跑 TT，三角 STA/活动功耗归后续验收。",
"", "来源：[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2026-07-06)、[ICsprout55](https://github.com/openecos-projects/icsprout55-pdk/releases/tag/v1.10.102)、[ORFS Nangate45](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/tree/master/flow/platforms/nangate45)。", "",
"## 5. 重放与断点", "", "```powershell", "# 从 D:\\3DGS 执行；支持覆盖工具和库路径", ".\\asic\\scripts\\run_t01_matrix.ps1", "# 只汇总已完成证据", ".\\asic\\scripts\\run_t01_matrix.ps1 -ReportOnly", ".\\tmp\\toolchains\\yowasp\\Scripts\\python.exe asic\\scripts\\summarize_t01.py", "```", "",
"通用综合/技术无关映射位于 `runs/generic/<variant>/`；目标库映射、网表、日志、统计、源码与网表哈希位于 `runs/<pdk>/<corner>/<variant>/200MHz/`。恢复旧断点的 ROM 补映射脚本/日志单独保存；从头重跑会在目标库映射前处理 ROM，无须恢复脚本。", "",
"## 6. 尚未关闭的验收项", "",
"- OpenSTA 未安装、顶层 STA 未执行，WNS/TNS、恢复/移除检查和时序通过均未知。`asic/scripts/run_t01_sta.tcl` 仅已准备，未做工具执行验证。",
"- 缓存边界还需要匹配实际接口的时序模型；仅安装 OpenSTA 也不等于完整设计即可签核。脚本要求提供该模型，禁止自动豁免未知单元。",
"- CACTI/Ramulator 未安装、存储控制边界未恢复；FreePDK45 SS/FF 库未取得；无活动功耗证据。",
"- T01 方框保持未勾选；本轮可开发部分基本完成。按主清单可先推进 T02，环境/模型齐备后返回 T01 补 STA，不把本次部分成功写成最终 PPA 通过。", ""]
for cost in costs:
    if cost["variant"] == "shared_baseline":
        lines += [f'## 附：{cost["pdk"]} 共享基线主要面积来源', "", "按模块自身标准单元面积乘实际层级实例数累计，避免重复计算子模块；合计已与顶层统计核对。", "", "| 模块族 | 全芯片该类标准单元面积 mm² |", "| --- | ---: |"]
        for name, area in list(cost["area_um2_by_module_family"].items())[:8]:
            lines.append(f"| {name} | {area / 1e6:.6f} |")
        lines.append("")
(OUT / "首次映射报告_2026-10-03.md").write_text("\n".join(lines), encoding="utf-8")
print(f"Wrote manifest, comparison, report: {len(summaries)} runs")
