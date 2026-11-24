# 动态Gaussian-wise联合架构 v0.1

- 日期：2026-08-04
- 定位：本课题区别于固定GCC复现的核心架构说明

## 1. 一句话定义

以Gaussian-wise前到后有序渲染消除tile-wise冗余，以终止和队列负载感知的
epoch级动态资源重构提高跨场景、跨深度组的硬件利用率和能效。

## 2. 为什么二者必须结合

Gaussian-wise改变了工作量分布：

- 每颗Gaussian只加载一次，但大小不同导致覆盖block数差异很大；
- 深度分组阶段集中使用比较/排序资源，后续阶段这些资源可能空闲；
- 投影工作按Gaussian近似固定，raster工作随Gaussian面积和遮挡显著变化；
- 强遮挡场景会跳过深层组，projection/SH需求随时间快速下降；
- 大场景或低遮挡场景则可能长期由projection、排序或raster任一阶段主导。

因此固定GCC式资源配比未必适合全部13个场景。动态重构应利用这些阶段性变化，
但不得破坏Gaussian-wise顺序和blend正确性。

## 3. 建议物理组织

```text
        shared MAC / comparator / divider resources
                   ↑ resource mode
depth grouper → stable sorter → ordered issue/retire
                                  ↓
                         projection lane array
                                  ↓
                              SH engine
                                  ↓
                    Gaussian-internal block walker
                                  ↓
                     alpha / blend / termination
```

物理资源总量在芯片制造后固定。运行时通过lane启停、共享算术多路选择、仲裁权重、
SRAM bank映射和时钟门控形成不同工作模式。

## 4. 初步模式

| 模式 | 触发特征 | group/sort | projection/SH | block raster | 功耗策略 |
|---|---|---:|---:|---:|---|
| G | group队列高、sort忙 | 高 | 低/中 | 低 | 闲置raster门控 |
| P | 投影队列持续高 | 低 | 高 | 中 | 启用更多projection lane |
| R | 平均block/Gaussian高 | 低 | 中/限流 | 高 | 更多alpha/walker份额 |
| E | 深组跳过率和终止率高 | 低 | 低 | 按需 | 关闭多余lane/bank |

模式表后续必须由真实场景周期模型与RTL计数器校准，不能只凭经验冻结。

## 5. 观测、决策与安全提交

```text
64位饱和计数器
  → epoch窗口归一化指标
  → 阈值/滞回模式建议器
  → shadow配置
  → 等待ordered retire、队列、scoreboard和lane排空
  → active配置原子提交
```

最低计数器集合：group占用/溢出、sort周期、projection队列水位、lane busy、
候选/有效/终止块、alpha发射/裁剪、blend提交、scoreboard等待、retire等待、
DRAM停顿、各阶段空闲周期和模式切换排空周期。

## 6. 公平实验合同

- 固定1-lane、固定G/P/R/E和动态模式均使用同一RTL参数上限。
- SRAM总容量、DRAM带宽、时钟、数值格式和图像质量阈值相同。
- 报告全局最佳固定模式、逐场景oracle固定模式和动态模式。
- 动态方案计入策略器面积/功耗、切换排空、低利用率和错误决策代价。
- 除FPS与能耗外，报告各单元利用率、Gaussian属性加载次数、排序次数、block跳过率。

## 7. 当前实现映射

- 已完成：1/2/4 projection lane启停、round-robin分发、Gaussian内部block连续仲裁、
  shadow/active epoch安全提交、控制与停顿计数器基础模块。
- 待实现：depth grouper、stable sorter、ordered retire、其他阶段的可重构资源接口、
  长窗口模式建议器和门控集成。
