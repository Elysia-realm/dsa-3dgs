# 动态 Raster Alpha 并行与同像素有序提交规格 v0.1

- 日期：2026-08-09
- 状态：工艺无关 SystemVerilog RTL 已实现并通过自检查
- 适用主链：深度分组、Gaussian 有序发射、Gaussian 内部 8×8 block 遍历

## 1. 目的与边界

本阶段把 R 模式从资源策略表落到真实可启停的 Raster alpha 算术阵列，同时优先保证 3DGS 前到后混合的数值顺序。实现复制的是无图像状态的 alpha 计算 lane，不复制有状态的 blend/image-state writer。

本阶段不是多状态写端口方案，也不建立 Gaussian–tile KV/bin、per-tile Gaussian list 或 per-tile 排序路径。

## 2. 安全数据流

```text
Gaussian 内部 8×8 block row-major 像素发射
→ termination filter
→ 分配全局单调 pixel issue sequence
→ 1/2/4 路 alpha lane 并行计算
→ 按 issue sequence 有序退休
→ 唯一 blend/image-state read-modify-write 提交口
→ pixel/block termination 状态更新
```

alpha 计算只依赖当前 Gaussian/像素描述符，不读取图像累积状态，因此可以跨 lane 并行和乱序完成。blend 依赖当前像素的 RGB 与透射率，必须按 Gaussian 前到后顺序更新；有序退休和唯一状态提交口共同构成保守的 hazard scoreboard。

## 3. 顺序与握手合同

- 只有 live pixel 在被 alpha 阵列接受时分配 sequence；被 coarse termination 直接跳过的任务不进入 alpha 顺序队列。
- sequence 与完整 metadata 一起写入 lane payload，不能在 lane 完成时引用输入端当前 sequence。
- lane issue 与 ordered-retire FIFO 写入是同周期原子事务。
- lane 可以乱序完成；只有等于 order FIFO head 的结果可以向 blend 提交。
- 输出背压期间 sequence、pixel ID、颜色、alpha 和标签保持稳定。
- 唯一 blend 状态口一次只提交一个有序事务，所以连续命中同一 pixel 的读改写严格串行。
- `idle` 同时要求外部在途任务为零、alpha outstanding 为零且退休队列为空。
- active lane 数只允许在 epoch 安全排空后改变；RTL 非综合断言会检查直接违规切换。

## 4. 动态资源映射

对于 4 个物理 Raster alpha lane：

| 模式 | Projection | SH | Raster alpha | 含义 |
|---|---:|---:|---:|---|
| G=0 | 2 | 2 | 2 | group/sort 优先 |
| P=1 | 4 | 4 | 2 | projection/SH 优先 |
| R=2 | 2 | 2 | 4 | raster alpha 优先 |
| E=3 | 1 | 1 | 1 | 低功耗/强门控 |

模式只改变已实例化 lane 的 active mask。当前工艺无关 RTL 不直接实例化专用 clock-gating cell；ASIC 综合阶段应根据 active mask/clock-enable 插入工艺门控单元。

## 5. 正确性证据

### 5.1 Alpha 阵列

`tb_raster_alpha_lane_array` 覆盖 4 路并行、8 个不同 opacity、输出背压、4→1 lane 切换、alpha 阈值/上限以及单 lane 数值等价。结果必须严格按 sequence 退休。

### 5.2 同像素 RAW hazard

`tb_raster_ordered_same_pixel` 连续发射 4 个 `alpha=0.5`、红色为 1.0 的任务到同一像素。Q 格式下提交后状态依次为：

| 提交序号 | R(Q1.12) | T(Q0.16) |
|---:|---:|---:|
| 1 | 2048 | 32768 |
| 2 | 3072 | 16384 |
| 3 | 3584 | 8192 |
| 4 | 3840 | 4096 |

随后对另一个像素的首次提交必须从清空状态开始，得到 `R=1024, T=32768`。测试同时施加 commit 背压并检查任务严格按 1→2→3→4→5 提交。

### 5.3 完整前端动态切换

`tb_gaussian_ordered_render_frontend` 使用 4 个物理 lane。在 G 模式下 projection/SH/Raster mask 均为 `0011`；Gaussian 尚在 projection、block、pixel、alpha 或 blend 中时请求 R 模式，commit 保持 pending。225 个有效像素全部提交、全链排空后才更新 epoch，Raster mask 原子变为 `1111`，projection/SH 保持 `0011`。

## 6. 已知限制与后续扩展条件

当前吞吐上限最终仍受唯一 blend/image-state 提交口约束；多 alpha lane 的收益取决于 alpha 算术延迟、termination 命中率与状态提交带宽。后续只有在真实负载证明该提交口为主要瓶颈时，才扩展 bank 化多状态端口，并必须同时实现：

1. 显式 pixel outstanding/scoreboard；
2. 同 pixel 前到后依赖检测；
3. image-state bank 映射与冲突仲裁；
4. 多端口提交后的全局可见顺序定义；
5. 与单提交口逐提交或整帧位精确等价验证。

在上述机制完成前，不把当前实现描述为“多 blend lane”或“多 image-state writer”。
