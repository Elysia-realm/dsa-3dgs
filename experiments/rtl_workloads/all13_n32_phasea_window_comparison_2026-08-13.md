# Phase A 有序 state window 性能对比

基线：`experiments/rtl_workloads/all13_n32_commit_replace_stage_2026-08-13.json`  
候选：`experiments/rtl_workloads/all13_n32_phasea_window_2026-08-13.json`

| 场景 | profile | baseline | Phase A | speedup | frame-state |
|---|---|---:|---:|---:|---|
| bicycle | ideal | 4337 | 3373 | 1.286× | 逐位一致 |
| bicycle | limited | 8347 | 7386 | 1.130× | 逐位一致 |
| bonsai | ideal | 5271 | 4125 | 1.278× | 逐位一致 |
| bonsai | limited | 9613 | 8467 | 1.135× | 逐位一致 |
| counter | ideal | 5347 | 4184 | 1.278× | 逐位一致 |
| counter | limited | 9729 | 8581 | 1.134× | 逐位一致 |
| drjohnson | ideal | 5304 | 4115 | 1.289× | 逐位一致 |
| drjohnson | limited | 10213 | 9019 | 1.132× | 逐位一致 |
| flowers | ideal | 4868 | 3796 | 1.282× | 逐位一致 |
| flowers | limited | 9175 | 8101 | 1.133× | 逐位一致 |
| garden | ideal | 3631 | 2837 | 1.280× | 逐位一致 |
| garden | limited | 6865 | 6073 | 1.130× | 逐位一致 |
| kitchen | ideal | 5520 | 4293 | 1.286× | 逐位一致 |
| kitchen | limited | 10195 | 8979 | 1.135× | 逐位一致 |
| playroom | ideal | 4932 | 3860 | 1.278× | 逐位一致 |
| playroom | limited | 9401 | 8309 | 1.131× | 逐位一致 |
| room | ideal | 5121 | 3973 | 1.289× | 逐位一致 |
| room | limited | 9777 | 8626 | 1.133× | 逐位一致 |
| stump | ideal | 3945 | 3059 | 1.290× | 逐位一致 |
| stump | limited | 7585 | 6697 | 1.133× | 逐位一致 |
| train | ideal | 5389 | 4250 | 1.268× | 逐位一致 |
| train | limited | 9807 | 8665 | 1.132× | 逐位一致 |
| treehill | ideal | 5031 | 3948 | 1.274× | 逐位一致 |
| treehill | limited | 9163 | 8077 | 1.134× | 逐位一致 |
| truck | ideal | 5162 | 4051 | 1.274× | 逐位一致 |
| truck | limited | 9417 | 8321 | 1.132× | 逐位一致 |

## 聚合

- ideal 几何平均加速：1.281×；范围 1.268×–1.290×。
- limited 几何平均加速：1.133×；范围 1.130×–1.135×。
- 全部 frame-state 逐位一致：是。
- commit、cache miss、AXI state read/write 数量保持不变；收益来自不同像素事务的 hit-under-miss 与控制阶段重叠。
- limited profile 的收益较低，因为单 MSHR 仍串行处理大量片外 miss；本结果支持评估第二 MSHR，但不构成直接启用的理由。
- n32 是真实训练属性微负载，不是完整帧画质、最终帧率或 ASIC PPA。
