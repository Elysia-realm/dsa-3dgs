# 动态多 SH Lane 与联合资源模式规格 v0.1

- 日期：2026-08-09
- 状态：工艺无关 RTL 已实现并通过自检查
- 适用主链：Gaussian-wise 有序发射、每 Gaussian 一次 SH、Gaussian 内部 8×8 block 遍历

## 1. 设计目的

把原先单个 SH 物理算术路径替换为可复制的 1/2/4 lane 阵列，并使其与 projection lane 一起接受同一个 epoch 级 G/P/R/E 模式。增加 SH 并行度只改变吞吐量和可门控资源数量，不改变定点格式、SH 数学公式、Gaussian 顺序或 block/pixel 混合顺序。

## 2. 数据流与顺序

```text
完整 Gaussian 原子 fork 的 SH 分支
→ round-robin 发射到 active SH lanes
→ 每 lane：方向归一化 + degree-3 SH RGB
→ 基于 sequence 的 ordered retire
→ 与已恢复顺序的 projection block stream 按 epoch/GID/sequence 汇合
```

每个 Gaussian 仍只执行一次 SH。SH 结果在 projection-SH join 内保持到该 Gaussian 的最后一个 block 被接受，不因 block 数量增加而重复计算。

## 3. 动态资源映射

共享模式编码保持为：

| 模式 | 含义 | Projection lane | SH lane | Raster alpha lane |
|---|---|---:|---:|---:|
| G=0 | group 优先 | half | half | half |
| P=1 | projection/前端优先 | all | all | half |
| R=2 | raster 优先 | half | half | all |
| E=3 | 能效/强门控 | 1 | 1 | 1 |

`half=(physical_lanes+1)/2`。本轮修正了旧 projection 控制器把 mode 误解释为指数 lane 数的临时语义，现在 projection 与中央 `gaussian_resource_mode_table` 一致。

模式只能在以下状态全部排空后提交：属性 issue、projection lanes及其有序退休队列、SH lanes及其有序退休队列、projection-SH join、block/pixel/alpha/blend 和下游提交状态。未启用 lane 保持无新事务，可在 ASIC 实现中插入 clock-gating cell；本 RTL 只生成 active mask，不直接实例化工艺专用门控单元。

## 4. SH 有序退休合同

- sorted sequence 在 lane 接受输入的同周期原子写入 order FIFO；
- lane 完成可以乱序，但只有 sequence 等于 FIFO head 的结果能够退休；
- 输出背压期间 metadata、RGB、fallback 和 overflow 保持稳定；
- outstanding 计数与 order FIFO empty 共同定义 SH array idle；
- lane 配置只能在 array idle 时改变；
- duplicate/missing/wrong sequence 会形成等待或协议错误，不允许静默越序。

## 5. 验证覆盖

- 使用合成可变延迟 lane 强制完成顺序不同于发射顺序，验证严格按 sequence 退休；
- active lane 从 4 切换到 1，验证 dispatch mask；
- 真实4路定点 SH 阵列计算四个不同 sequence/系数组合，验证 metadata、RGB 与单 lane 数值结果一致；
- 完整 projection-SH 阵列在 P 模式使用全部 lane，排空后切至 E 模式，projection 与 SH 同时变为单 lane；
- E 模式继续渲染一个 Gaussian，验证颜色、epoch、GID、sequence 和四个 block 全部正确；
- 完整 Icarus 和 Python 回归无退化。

## 6. 当前边界

后续阶段已把 Raster lane 数落到真实 1/2/4 路 alpha 算术阵列，并在进入唯一 blend/image-state writer 前按 pixel issue sequence 恢复全局顺序。该安全首版不复制有状态 writer；详细合同见 `动态Raster_Alpha并行与同像素有序提交规格_v0.1.md`。
