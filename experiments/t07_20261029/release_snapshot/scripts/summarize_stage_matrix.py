from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import mean


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Summarize ideal/limited stage occupancy from an RTL workload report"
    )
    parser.add_argument("report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    report = json.loads(args.report.read_text(encoding="utf-8"))
    by_scene: dict[str, dict[str, dict[str, object]]] = {}
    for row in report["results"]:
        by_scene.setdefault(row["scene"], {})[row["profile"]] = row

    rows: list[tuple[str, int, int, float, int, int, float]] = []
    for scene in sorted(by_scene):
        profiles = by_scene[scene]
        if "ideal" not in profiles or "limited" not in profiles:
            raise ValueError(f"{scene} is missing ideal or limited data")
        ideal = profiles["ideal"]
        limited = profiles["limited"]
        ideal_cycles = int(ideal["cycles"])
        limited_cycles = int(limited["cycles"])
        block_bp = int(ideal["stage_cycles"]["block_backpressure"])
        rows.append(
            (
                scene,
                ideal_cycles,
                limited_cycles,
                limited_cycles / ideal_cycles,
                int(ideal["commits"]),
                int(ideal["state_misses"]),
                block_bp / ideal_cycles,
            )
        )

    equivalence = report.get("equivalence", {})
    all_equivalent = all(
        bool(value.get("all_profiles_equal", False)) for value in equivalence.values()
    ) and len(equivalence) == len(rows)
    output_stalls = [int(row["output_stall"]) for row in report["results"]]
    ideal_peaks = [
        int(row["peak_outstanding"])
        for row in report["results"]
        if row["profile"] == "ideal"
    ]
    limited_peaks = [
        int(row["peak_outstanding"])
        for row in report["results"]
        if row["profile"] == "limited"
    ]

    lines = [
        "# 13 场景 n32 RTL 阶段占用汇总",
        "",
        f"源报告：`{args.report.as_posix()}`",
        "",
        "配置：每场景 32 个确定性全场景抽样 Gaussian，4 个物理 lane，"
        f"R 模式（mode {report['frame_mode']}），{report['state_entries']} 项 state cache，"
        f"{report['multiwrite_depth']} 项 AXI multiwrite。",
        "",
        "| 场景 | ideal cycles | limited cycles | limited/ideal | commits | misses | ideal block_bp/cycles |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for scene, ideal, limited, ratio, commits, misses, block_ratio in rows:
        lines.append(
            f"| {scene} | {ideal} | {limited} | {ratio:.3f}× | {commits} | {misses} | {block_ratio:.1%} |"
        )
    lines.extend(
        [
            "",
            "## 汇总结论",
            "",
            f"- limited/ideal 周期比均值：{mean(row[3] for row in rows):.3f}×。",
            f"- ideal block backpressure 占比均值：{mean(row[6] for row in rows):.1%}。",
            f"- ideal/limited 完整 frame-state 逐位一致：{'是' if all_equivalent else '否'}。",
            f"- 所有 output stall 为 0：{'是' if all(value == 0 for value in output_stalls) else '否'}。",
            f"- AXI multiwrite 峰值：ideal={max(ideal_peaks, default=0)}，limited={max(limited_peaks, default=0)}。",
            "- 现阶段复制更多投影或光栅 lane 不能缩短总周期；优先研究严格有序、同像素 RAW 安全的 state transaction overlap。",
            "",
            "## 适用边界",
            "",
            "- 这是读取真实训练属性的 n32 RTL 微负载，用于数据通路正确性、阶段占用和内存敏感性分析。",
            "- 它不是完整帧渲染，不能用于 PSNR、SSIM、LPIPS，也不能冒充最终帧率。",
            "- 报告不包含标准单元库、SRAM 宏、布线寄生或开关活动，不能用于 ASIC 面积和功耗宣称。",
            "- 测试保持“深度分组 + Gaussian 有序发射 + Gaussian 内部 8×8 block 遍历”，没有 per-tile bin/list/sort。",
            "- 数据仅在 `D:/3DGS` 本地处理，没有网络上传。",
            "",
        ]
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
