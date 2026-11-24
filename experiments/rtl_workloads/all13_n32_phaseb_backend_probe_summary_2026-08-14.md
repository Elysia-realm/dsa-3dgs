# Phase B 后端瓶颈与下一候选 Go/No-Go

源数据：`experiments/rtl_workloads/all13_n32_phaseb_backend_probe_v2_2026-08-14.json`

## ideal

- 聚合周期：43240；第三笔候选等待：30235（69.9%）。
- 与两个在途 slot 都不同 key：30235（候选的 100.0%）；RAW 冲突：0。
- distinct 候选到达时双 MSHR 同时占满：7517（24.9%）。
- head 等 backing response：16565；head 等共享 blend 服务：13670。
- AXI AR 背压：0；reader/cache response-port 背压：0。

## limited

- 聚合周期：72885；第三笔候选等待：58392（80.1%）。
- 与两个在途 slot 都不同 key：58392（候选的 100.0%）；RAW 冲突：0。
- distinct 候选到达时双 MSHR 同时占满：33502（57.4%）。
- head 等 backing response：45072；head 等共享 blend 服务：13320。
- AXI AR 背压：284；reader/cache response-port 背压：0。

## 工程结论

- **单独 4 MSHR：No-Go。** 2-entry window 没有第三个 slot，实测 `mshr_full_query_block=0`；新增 MSHR 无事务可接收。
- **单独 4-entry window：No-Go。** limited 下大量第三候选到达时两个 MSHR都已占满，窗口会把等待位置从 alpha retire 移到 cache query，不能独立提高 backing service rate。
- **4-entry window + 4 MSHR：Research-Go，而非默认 RTL Go。** 机会在13场景中稳定存在，且当前 n32 RAW 冲突为0；但 head-only commit、共享单 blend core、直接映射 cache fill冲突和4路 tag/AXI ID会显著增加验证与PPA风险。必须先实现参数化实验分支并与Phase B逐位对照，不能直接替换默认设计。
- AXI response-port 不是当前瓶颈：所有 profile 的 reader/cache response背压均为0；AR背压相对总周期很小。优先复制response端口没有证据。
- `third_candidate/cycles` 不能直接当作可消除周期。第三事务提前进入只能隐藏部分 wait-response，最终仍受严格顺序退休、单 blend 吞吐和片外读延迟限制。
- 当前数据是 n32 真实训练属性微负载，不是完整帧、PSNR/SSIM/LPIPS或ASIC PPA。

## 路线边界

下一研究分支只允许扩展有序像素状态窗口/MSHR，不改变深度分组、Gaussian有序发射和Gaussian内部8×8 block遍历，也不引入per-tile bin/list/sort。
