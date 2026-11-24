# 13 场景 n32 RTL 阶段占用汇总

源报告：`experiments/rtl_workloads/all13_n32_commit_replace_stage_2026-08-13.json`

配置：每场景 32 个确定性全场景抽样 Gaussian，4 个物理 lane，R 模式（mode 2），4096 项 state cache，8 项 AXI multiwrite。

| 场景 | ideal cycles | limited cycles | limited/ideal | commits | misses | ideal block_bp/cycles |
|---|---:|---:|---:|---:|---:|---:|
| bicycle | 4337 | 8347 | 1.925× | 526 | 488 | 86.6% |
| bonsai | 5271 | 9613 | 1.824× | 769 | 529 | 91.2% |
| counter | 5347 | 9729 | 1.820× | 786 | 534 | 91.6% |
| drjohnson | 5304 | 10213 | 1.926× | 661 | 596 | 88.8% |
| flowers | 4868 | 9175 | 1.885× | 643 | 524 | 87.6% |
| garden | 3631 | 6865 | 1.891× | 450 | 388 | 82.6% |
| kitchen | 5520 | 10195 | 1.847× | 782 | 571 | 89.9% |
| playroom | 4932 | 9401 | 1.906× | 628 | 537 | 85.3% |
| room | 5121 | 9777 | 1.909× | 654 | 568 | 89.2% |
| stump | 3945 | 7585 | 1.923× | 472 | 442 | 81.5% |
| train | 5389 | 9807 | 1.820× | 795 | 537 | 87.4% |
| treehill | 5031 | 9163 | 1.821× | 734 | 502 | 87.8% |
| truck | 5162 | 9417 | 1.824× | 751 | 518 | 88.5% |

## 汇总结论

- limited/ideal 周期比均值：1.871×。
- ideal block backpressure 占比均值：87.5%。
- ideal/limited 完整 frame-state 逐位一致：是。
- 所有 output stall 为 0：是。
- AXI multiwrite 峰值：ideal=2，limited=4。
- 现阶段复制更多投影或光栅 lane 不能缩短总周期；优先研究严格有序、同像素 RAW 安全的 state transaction overlap。

## 适用边界

- 这是读取真实训练属性的 n32 RTL 微负载，用于数据通路正确性、阶段占用和内存敏感性分析。
- 它不是完整帧渲染，不能用于 PSNR、SSIM、LPIPS，也不能冒充最终帧率。
- 报告不包含标准单元库、SRAM 宏、布线寄生或开关活动，不能用于 ASIC 面积和功耗宣称。
- 测试保持“深度分组 + Gaussian 有序发射 + Gaussian 内部 8×8 block 遍历”，没有 per-tile bin/list/sort。
- 数据仅在 `D:/3DGS` 本地处理，没有网络上传。
