# Image-State 片外 Backing Cache 规格 v0.1

日期：2026-08-09

## 1. 目的与架构边界

本模块解除早期 `STATE_ENTRIES=4096` 必须容纳整帧像素状态的限制，使 32 位线性 pixel ID 可以访问真实分辨率图像。它只替换 blend 前后的图像状态存储后端，不改变既定主数据流：

`深度分组 → Gaussian 有序发射 → Gaussian 内部 8×8 block 遍历 → pixel/alpha → 单一有序 blend/state commit`

不增加 Gaussian–tile KV/bin、逐 tile Gaussian list 或逐 tile 排序路径；G/P/R/E 动态资源模式和 epoch 安全提交规则保持不变。

## 2. 数据通路

```text
blend 状态查询
  → 片上直接映射 image-state cache
  → miss：OUTPUT_BASE + pixel_id × 16 的 AXI4 单拍读
  → epoch 检查与 clear-state 选择
  → blend
  → cache 更新 + 既有 AXI4 write-through 写回
```

- cache 为直接映射、参数化 `ENTRIES`、完整 pixel ID tag 和 16 位 epoch tag。
- cache 命中返回 Q1.12 RGB 与 Q0.16 transmittance。
- miss 从 128-bit backing record 读取旧状态；记录 epoch 与查询 epoch 不相等时，逻辑上视为新帧，返回 `RGB=0, T=16'hffff`。
- 每次成功 blend commit 同时更新 cache，并通过已有写 DMA 写回 backing store；当前是 write-through，不是 write-back。
- miss response 出错时返回 clear state、置 sticky error，并使本帧最终报告错误，避免把未知片外数据送入 blend。

## 3. 一致性与顺序

当前实现采用保守的 single-miss、single-writer 合同：

1. 所有 alpha 结果先按全局 pixel issue sequence 有序退休，再进入唯一 blend/state writer。
2. cache 在 blend commit 握手时更新，因此紧随其后的同 pixel 查询可直接看到最新状态。
3. 当既有 AXI write-through 尚未收到 B response 时，新的 cache miss 不允许向状态读引擎握手；这保证冲突换出后的读回不会越过先前写回而读到旧状态。
4. 系统 done 必须同时等待计算核心、cache miss、cache response、状态读 AXI 和像素写 AXI 全部排空。
5. miss fill 与同 index 的 blend update 同周期发生时，blend update 具有最终写优先级。

## 4. AXI4 状态读接口

- 数据宽度：128 bit。
- 地址：`OUTPUT_BASE + pixel_id × 16`。
- burst：单拍 INCR，`ARLEN=0`、`ARSIZE=4`。
- outstanding：1。
- 检查：`RRESP`、`RID`、`RLAST` 和 16 Byte base 对齐。
- 错误位：`ERROR_STATUS[16]` 为响应/协议错误，`[17]` 为配置/对齐错误。

## 5. 128-bit backing record 中的状态字段

- `[12:0]`：R Q1.12
- `[25:13]`：G Q1.12
- `[38:26]`：B Q1.12
- `[54:39]`：T Q0.16
- `[70:55]`：epoch

其余字段与 `axi4_pixel_state_write_engine` 的有序写回记录保持一致。

## 6. 容量与性能边界

启用 `USE_STATE_CACHE_BACKEND=1` 后，`width × height` 不再受 `STATE_ENTRIES` 限制；该参数只表示片上 cache 工作集大小。禁用该参数时仍保留原有容量拒绝和 `ERROR_STATUS[9]`，防止本地 SRAM 地址别名。

本版本解决的是逻辑容量与正确性，不等于已经证明 1080p 性能达标。直接映射冲突会产生单拍片外读，且每次 commit 都 write-through；后续必须用 13 个真实场景测量 miss rate、读写带宽和 stall，再决定是否增加组相联、行合并、写合并或多 outstanding。任何性能优化都必须维持同 pixel 顺序和 epoch 语义。

## 7. 验证覆盖

- AXI 状态读：正常地址/数据、response 背压、RRESP、RID、RLAST、base 对齐。
- cache：miss、hit、update、直接映射冲突、换出后读回、epoch 失配 clear、错误响应、同周期 fill/update 优先级。
- 系统：片外状态读错误进入 bit16；启用 backing 后大于 4096 像素的帧不再触发容量错误。

