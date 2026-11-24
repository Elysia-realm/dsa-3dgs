from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Summarize validation-only ordered state-window probes")
    parser.add_argument("report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(args.report.read_text(encoding="utf-8"))

    lines = [
        "# 13 场景 n32 有序 state window 机会探针",
        "",
        f"源报告：`{args.report.as_posix()}`",
        "",
        "`window_wait` 表示严格有序的下一像素已经到达，但当前单事务 state path 尚未接收它。"
        "`window_same`/`window_diff` 按完整 `{epoch,pixel}` key 区分必须串行的 RAW 与潜在可重叠候选。",
        "",
        "| 场景 | profile | cycles | misses/commits | window_wait/cycles | same | different |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    totals: dict[str, dict[str, int]] = {}
    for row in report["results"]:
        stage = row["stage_cycles"]
        profile = row["profile"]
        accumulator = totals.setdefault(
            profile, {"cycles": 0, "commits": 0, "misses": 0, "wait": 0, "same": 0, "diff": 0}
        )
        values = {
            "cycles": int(row["cycles"]),
            "commits": int(row["commits"]),
            "misses": int(row["state_misses"]),
            "wait": int(stage["state_window_wait"]),
            "same": int(stage["state_window_same_key"]),
            "diff": int(stage["state_window_different_key"]),
        }
        for key, value in values.items():
            accumulator[key] += value
        lines.append(
            f"| {row['scene']} | {profile} | {values['cycles']} | "
            f"{values['misses']/values['commits']:.1%} | {values['wait']/values['cycles']:.1%} | "
            f"{values['same']} | {values['diff']} |"
        )

    lines.extend(["", "## 聚合与边界", ""])
    for profile in ("ideal", "limited"):
        value = totals[profile]
        wait_fraction = value["wait"] / value["cycles"]
        miss_fraction = value["misses"] / value["commits"]
        optimistic_two_way = 1.0 / (1.0 - wait_fraction + wait_fraction / 2.0)
        hit_only_fraction = wait_fraction * (1.0 - miss_fraction)
        rough_hit_only = 1.0 / (1.0 - hit_only_fraction / 2.0)
        lines.append(
            f"- {profile}: wait/cycles={wait_fraction:.1%}，miss/commit={miss_fraction:.1%}，"
            f"same={value['same']}，different={value['diff']}；若所有等待可完美二路重叠，Amdahl 乐观上限约 "
            f"{optimistic_two_way:.3f}×。按总体 hit 比例粗略折算的单 MSHR hit-under-miss 参考上限约 "
            f"{rough_hit_only:.3f}×，但它不是周期预测。"
        )
    lines.extend(
        [
            "- `same=0` 只说明这些 n32 微负载的相邻已排序像素没有出现精确 key 冲突，不能取消硬件 RAW CAM。",
            "- 仅增加 2-entry FIFO 不改变 cache/AXI 单未决服务率，不能直接获得上述上限。",
            "- 约 77.8% 的 commit 为 cache miss；要接近完整二路上限需要第二 MSHR、AXI read ID 和有序响应/退休，面积与验证成本显著增加。",
            "- 第一阶段应采用 2-entry ordered window + 完整 key hazard + 单 MSHR hit-under-miss；只有实测收益/PPA 合理时才启用第二 MSHR。",
            "- 这是微负载架构取舍数据，不是完整帧画质、最终帧率或 ASIC PPA。",
            "",
        ]
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
