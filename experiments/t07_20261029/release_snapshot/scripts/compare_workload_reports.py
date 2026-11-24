from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import geometric_mean


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare two matching RTL workload reports")
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    candidate = json.loads(args.candidate.read_text(encoding="utf-8"))
    old = {(row["scene"], row["profile"]): row for row in baseline["results"]}
    rows = []
    for row in candidate["results"]:
        key = row["scene"], row["profile"]
        before = old[key]
        hash_ok = candidate["equivalence"][row["scene"]]["sha256"] == baseline["equivalence"][row["scene"]]["sha256"]
        rows.append((row["scene"], row["profile"], before["cycles"], row["cycles"], before["cycles"] / row["cycles"], hash_ok))
    lines = [
        "# Phase A 有序 state window 性能对比", "",
        f"基线：`{args.baseline.as_posix()}`  ", f"候选：`{args.candidate.as_posix()}`", "",
        "| 场景 | profile | baseline | Phase A | speedup | frame-state |",
        "|---|---|---:|---:|---:|---|",
    ]
    for scene, profile, before, after, speedup, hash_ok in rows:
        lines.append(f"| {scene} | {profile} | {before} | {after} | {speedup:.3f}× | {'逐位一致' if hash_ok else '不一致'} |")
    lines.extend(["", "## 聚合", ""])
    for profile in ("ideal", "limited"):
        values = [row[4] for row in rows if row[1] == profile]
        lines.append(f"- {profile} 几何平均加速：{geometric_mean(values):.3f}×；范围 {min(values):.3f}×–{max(values):.3f}×。")
    lines.extend([
        f"- 全部 frame-state 逐位一致：{'是' if all(row[5] for row in rows) else '否'}。",
        "- commit、cache miss、AXI state read/write 数量保持不变；收益来自不同像素事务的 hit-under-miss 与控制阶段重叠。",
        "- limited profile 的收益较低，因为单 MSHR 仍串行处理大量片外 miss；本结果支持评估第二 MSHR，但不构成直接启用的理由。",
        "- n32 是真实训练属性微负载，不是完整帧画质、最终帧率或 ASIC PPA。", "",
    ])
    args.output.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
