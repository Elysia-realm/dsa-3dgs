# 13 场景 n32 有序 state window 机会探针

源报告：`experiments/rtl_workloads/all13_n32_state_window_probe_2026-08-13.json`

`window_wait` 表示严格有序的下一像素已经到达，但当前单事务 state path 尚未接收它。`window_same`/`window_diff` 按完整 `{epoch,pixel}` key 区分必须串行的 RAW 与潜在可重叠候选。

| 场景 | profile | cycles | misses/commits | window_wait/cycles | same | different |
|---|---|---:|---:|---:|---:|---:|
| bicycle | ideal | 4337 | 92.8% | 80.4% | 0 | 3489 |
| bicycle | limited | 8347 | 92.8% | 88.6% | 0 | 7393 |
| bonsai | ideal | 5271 | 68.8% | 79.3% | 0 | 4181 |
| bonsai | limited | 9613 | 68.8% | 87.6% | 0 | 8424 |
| counter | ideal | 5347 | 67.9% | 79.3% | 0 | 4240 |
| counter | limited | 9729 | 67.9% | 87.6% | 0 | 8523 |
| drjohnson | ideal | 5304 | 90.2% | 81.0% | 0 | 4295 |
| drjohnson | limited | 10213 | 90.2% | 88.8% | 0 | 9073 |
| flowers | ideal | 4868 | 81.5% | 80.1% | 0 | 3899 |
| flowers | limited | 9175 | 81.5% | 88.3% | 0 | 8099 |
| garden | ideal | 3631 | 86.2% | 78.0% | 0 | 2833 |
| garden | limited | 6865 | 86.2% | 86.5% | 0 | 5936 |
| kitchen | ideal | 5520 | 73.0% | 79.9% | 0 | 4412 |
| kitchen | limited | 10195 | 73.0% | 88.1% | 0 | 8980 |
| playroom | ideal | 4932 | 85.5% | 79.8% | 0 | 3934 |
| playroom | limited | 9401 | 85.5% | 87.7% | 0 | 8247 |
| room | ideal | 5121 | 86.9% | 81.0% | 0 | 4146 |
| room | limited | 9777 | 86.9% | 89.0% | 0 | 8703 |
| stump | ideal | 3945 | 93.6% | 79.8% | 0 | 3147 |
| stump | limited | 7585 | 93.6% | 88.1% | 0 | 6680 |
| train | ideal | 5389 | 67.5% | 79.3% | 0 | 4273 |
| train | limited | 9807 | 67.5% | 87.6% | 0 | 8592 |
| treehill | ideal | 5031 | 68.4% | 78.9% | 0 | 3971 |
| treehill | limited | 9163 | 68.4% | 87.3% | 0 | 7996 |
| truck | ideal | 5162 | 69.0% | 79.1% | 0 | 4085 |
| truck | limited | 9417 | 69.0% | 87.4% | 0 | 8233 |

## 聚合与边界

- ideal: wait/cycles=79.7%，miss/commit=77.8%，same=0，different=50905；若所有等待可完美二路重叠，Amdahl 乐观上限约 1.663×。按总体 hit 比例粗略折算的单 MSHR hit-under-miss 参考上限约 1.097×，但它不是周期预测。
- limited: wait/cycles=87.9%，miss/commit=77.8%，same=0，different=104879；若所有等待可完美二路重叠，Amdahl 乐观上限约 1.784×。按总体 hit 比例粗略折算的单 MSHR hit-under-miss 参考上限约 1.108×，但它不是周期预测。
- `same=0` 只说明这些 n32 微负载的相邻已排序像素没有出现精确 key 冲突，不能取消硬件 RAW CAM。
- 仅增加 2-entry FIFO 不改变 cache/AXI 单未决服务率，不能直接获得上述上限。
- 约 77.8% 的 commit 为 cache miss；要接近完整二路上限需要第二 MSHR、AXI read ID 和有序响应/退休，面积与验证成本显著增加。
- 第一阶段应采用 2-entry ordered window + 完整 key hazard + 单 MSHR hit-under-miss；只有实测收益/PPA 合理时才启用第二 MSHR。
- 这是微负载架构取舍数据，不是完整帧画质、最终帧率或 ASIC PPA。
