# AXI4 Pixel-State 多未决写参数实验（2026-08-09）

## 架构

新增 `axi4_pixel_state_multiwrite_buffer`，用于把B响应等待从每次pixel commit的关键路径移除：

- 所有写事务使用同一个AXI ID，利用AXI4同ID响应有序规则；
- AW和W允许独立握手，两个通道均完成后才选择下一笔事务，避免AXI4 W通道无ID造成地址/数据错配；
- 每个事务从renderer接收到B响应回收期间始终保留完整32-bit pixel tag；
- 状态读命中任意queued、部分发射或response-pending项时保持hazard；
- B响应按issue顺序释放环形队列；满队列支持B回收与新commit同周期替换；
- `busy`直到所有B响应回收才解除，因此系统frame done不会早于最终写响应。

该模块只优化pixel-state存储后端，不改变深度分组、Gaussian有序发射、Gaussian内部8×8遍历或epoch级G/P/R/E动态重构。

## train n32 / cache512

| 路径 | profile | cycles | output stall | peak outstanding | 相对旧路径加速 |
|---|---|---:|---:|---:|---:|
| single-outstanding + FIFO2 | ideal | 6582 | 184 | 1 | 1.00× |
| multiwrite depth2 | ideal | 6396 | 0 | 1 | 1.03× |
| multiwrite depth4/8/16 | ideal | 6396 | 0 | 1 | 1.03× |
| single-outstanding + FIFO2 | limited | 12415 | 1074 | 1 | 1.00× |
| multiwrite depth2 | limited | 11673 | 322 | 2 | 1.06× |
| multiwrite depth4/8/16 | limited | 11353 | 0 | 3 | 1.09× |

## 64周期B响应压力

| 路径 | cycles | output stall | peak outstanding | 相对旧路径加速 |
|---|---:|---:|---:|---:|
| single-outstanding + FIFO2 | 54366 | 47772 | 1 | 1.00× |
| multiwrite depth2 | 26971 | 20513 | 2 | 2.02× |
| multiwrite depth4 | 13656 | 7198 | 4 | 3.98× |
| multiwrite depth8 | 7303 | 845 | 8 | 7.44× |
| multiwrite depth16 | 6467 | 9 | 16 | 8.41× |

所有15份write-through/multiwrite、ideal/limited/write-stress完整128-bit frame-state文件均具有相同SHA-256：

`F771C1FE4FEAE4858AD191C6F20CAFD2A8BD9C0C1EAA8FBE6BB4907E606E2634`

## 默认参数决策

- 正常limited profile在depth4已达到本负载饱和性能。
- 长B延迟下depth8相对depth4仍有1.87×提升，而depth16相对depth8只再提升1.13×，且需要双倍payload/tag/CAM容量。
- 默认采用 `USE_PIXEL_MULTIWRITE_BUFFER=1`、`PIXEL_MULTIWRITE_DEPTH=8`，作为延迟容忍和面积的阶段性折中。
- depth4/8/16仍保留参数化，最终必须结合目标工艺时序、SRAM/寄存器实现和完整场景PPA冻结。

## 验证

- 确定性单测覆盖AW/W独立背压、4笔未决、同pixel重复hazard、满环同槽回收/补入、BRESP错误和地址未对齐。
- 96笔随机测试覆盖独立AW/W ready、随机B间隔、地址/数据逐笔scoreboard和8笔峰值未决。
- 无未决事务收到BVALID会锁存协议错误且不拉高BREADY。
- 数据仅在 `D:/3DGS` 本地生成和保存，未上传网络。
