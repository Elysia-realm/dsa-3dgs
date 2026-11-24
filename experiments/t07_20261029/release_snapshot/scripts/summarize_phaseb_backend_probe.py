from __future__ import annotations

import argparse
import json
from pathlib import Path


def percent(value: int, total: int) -> str:
    return f"{100.0 * value / total:.1f}%" if total else "0.0%"


def main() -> None:
    parser = argparse.ArgumentParser(description="Summarize Phase-B backend opportunity probes")
    parser.add_argument("report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(args.report.read_text(encoding="utf-8"))
    lines = ["# Phase B 后端瓶颈与下一候选 Go/No-Go", "", f"源数据：`{args.report.as_posix()}`", ""]
    summary = {}
    for profile in ("ideal", "limited"):
        rows = [row for row in report["results"] if row["profile"] == profile]
        total = lambda key, group: sum(row[group][key] for row in rows)
        cycles = sum(row["cycles"] for row in rows)
        third = total("third_candidate", "window_opportunity")
        distinct = total("third_distinct", "window_opportunity")
        two = total("third_distinct_mshr_two", "window_opportunity")
        wait_response = total("head_wait_response", "window_opportunity")
        blend_service = total("head_need_blend", "window_opportunity") + total("head_wait_blend", "window_opportunity")
        ar_stall = total("axi_ar_stall", "backend_cycles")
        rsp_block = total("reader_response_block", "backend_cycles") + total("cache_response_block", "backend_cycles")
        summary[profile] = {"cycles": cycles, "third": third, "distinct": distinct, "two": two}
        lines.extend([
            f"## {profile}", "",
            f"- 聚合周期：{cycles}；第三笔候选等待：{third}（{percent(third, cycles)}）。",
            f"- 与两个在途 slot 都不同 key：{distinct}（候选的 {percent(distinct, third)}）；RAW 冲突：{third-distinct}。",
            f"- distinct 候选到达时双 MSHR 同时占满：{two}（{percent(two, distinct)}）。",
            f"- head 等 backing response：{wait_response}；head 等共享 blend 服务：{blend_service}。",
            f"- AXI AR 背压：{ar_stall}；reader/cache response-port 背压：{rsp_block}。", "",
        ])
    lines.extend([
        "## 工程结论", "",
        "- **单独 4 MSHR：No-Go。** 2-entry window 没有第三个 slot，实测 `mshr_full_query_block=0`；新增 MSHR 无事务可接收。",
        "- **单独 4-entry window：No-Go。** limited 下大量第三候选到达时两个 MSHR都已占满，窗口会把等待位置从 alpha retire 移到 cache query，不能独立提高 backing service rate。",
        "- **4-entry window + 4 MSHR：Research-Go，而非默认 RTL Go。** 机会在13场景中稳定存在，且当前 n32 RAW 冲突为0；但 head-only commit、共享单 blend core、直接映射 cache fill冲突和4路 tag/AXI ID会显著增加验证与PPA风险。必须先实现参数化实验分支并与Phase B逐位对照，不能直接替换默认设计。",
        "- AXI response-port 不是当前瓶颈：所有 profile 的 reader/cache response背压均为0；AR背压相对总周期很小。优先复制response端口没有证据。",
        "- `third_candidate/cycles` 不能直接当作可消除周期。第三事务提前进入只能隐藏部分 wait-response，最终仍受严格顺序退休、单 blend 吞吐和片外读延迟限制。",
        "- 当前数据是 n32 真实训练属性微负载，不是完整帧、PSNR/SSIM/LPIPS或ASIC PPA。", "",
        "## 路线边界", "",
        "下一研究分支只允许扩展有序像素状态窗口/MSHR，不改变深度分组、Gaussian有序发射和Gaussian内部8×8 block遍历，也不引入per-tile bin/list/sort。",
    ])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(args.output)


if __name__ == "__main__":
    main()
