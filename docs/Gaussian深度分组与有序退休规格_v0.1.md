# Gaussian深度分组与有序退休规格 v0.1

日期：2026-08-04

## 1. 适用主路径

本规格服务于GCC式主路径：深度预处理、固定pivot粗分组、组内稳定排序、Gaussian有序发射、多projection lane并行完成、Gaussian有序退休，以及Gaussian内部8×8 block遍历。系统不建立Gaussian–tile KV/bin，也不执行逐tile深度排序。

## 2. 顺序合同

- 深度采用view-space Z，越小越靠近相机。
- 每帧输入Gaussian按接受顺序分配单调sequence ID，首条为0。
- frame_start允许与首条输入同周期，首条仍得到sequence 0。
- 确定性稳定排序键为 (depth, GID, sequence ID)。
- 固定pivot粗分组只建立组间近到远关系；每个组内必须恢复上述完整顺序。
- 多projection lane允许乱序完成，但进入blend前必须按照issue FIFO的Gaussian顺序退休。
- 一颗可见Gaussian的所有8×8 block必须从first到last连续退休，下一颗Gaussian不得穿插。
- 被剔除Gaussian用一条 first=1,last=1,culled=1 的空事件退休，以释放顺序队头。

## 3. 容量和错误合同

- 深度组bank、组内排序窗口和ordered-retire FIFO均为有限容量。
- 上游应服从ready/valid背压。
- bank或排序窗口无法接纳帧数据时，必须设置粘滞overflow；不得静默丢弃。
- overflow帧由系统软件或慢路径使用更大窗口/分批策略重放。
- ordered retire发现首尾块或cull格式错误时设置粘滞protocol_error，复位前保持。
- 任一lane在valid=1、ready=0时必须保持sequence、data、first、last和culled稳定。

## 4. 动态可重构约束

G/P/R/E模式不改变上述排序和退休合同。模式只能在受影响状态排空的epoch边界提交，且只改变：

- 已实例化lane的启用数量和时钟门控；
- group/projection/raster调度权重；
- 共享算术单元的时分服务优先级；
- 后续固定总容量SRAM内的bank或队列份额。

固定基线与动态方案必须共享相同物理资源上限、SRAM总容量、外存带宽、数值格式和Gaussian顺序，保证ASIC面积、功耗、性能和图像质量对比公平。

## 5. 首版RTL边界

- depth_group_buffer首版固定为4个组、3个可编程pivot；参数名保留但暂不承诺任意组数泛化。
- stable_group_sorter采用有限窗口插入排序，作为面积可控、综合友好的基线。
- gaussian_resource_mode_table当前为强制静态表，不包含运行时自动模式决策。
- gaussian_pipeline_event_counters提供自动策略所需观测量，但策略阈值、滞回和最短驻留时间留待下一阶段。
