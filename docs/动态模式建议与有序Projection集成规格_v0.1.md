# 动态模式建议与有序Projection集成规格 v0.1

日期：2026-08-04

## 1. 有序Projection集成

- 稳定排序后的Gaussian按sequence ID原子发射到动态projection lane。
- lane接收与ordered-retire issue FIFO写入必须是同一个握手事务，任一侧无法接收时都不得只推进一侧。
- 多lane可以乱序完成，但只有sequence等于FIFO队头的lane能向raster输出。
- 一颗可见Gaussian从first block到last block连续退休，中间不得插入其他Gaussian。
- 剔除Gaussian不再使用无标签旁路脉冲，而是保留完整描述符和sequence，形成first=last=culled=1的单拍、可背压事件。
- 阵列all_idle必须同时满足所有启用lane空闲和ordered-retire FIFO为空，作为epoch安全提交条件。

## 2. Sequence元数据合同

- projection输入metadata的低SEQ_W位承载sequence ID。
- block/cull输出描述符以metadata为最高字段，因此输出sequence位置由TASK_W-META_W确定。
- 首版raw projection array默认SEQ_W=16；系统顶层冻结最终描述符时可提升为32位。

## 3. 自动模式建议器

gaussian_mode_advisor只生成G/P/R/E推荐，不直接改变active配置。推荐经shadow/commit控制器，并在受影响状态完全排空的epoch边界提交。

保护机制：

- 长窗口：默认256周期统计一次负载。
- 分数裕量：候选模式必须显著优于当前模式。
- 滞回：候选模式必须连续多个窗口保持胜出。
- 最短驻留：一次实际模式提交后必须驻留若干窗口。
- 单未决请求：同一时间只保存一条推荐，直到下游接受或实际提交。
- 禁用清空：关闭自动控制时清空窗口状态和未决请求，回到软件强制模式。

初始分数映射：

- G：group pressure与sort busy之和。
- P：projection busy。
- R：raster busy与block candidate之和。
- E：block样本不少于8且终止跳过比例达到75%。

这些阈值目前是工艺无关RTL默认值，必须用13个真实场景的周期统计校准后才能作为论文最终配置。

## 4. 当前边界

- 深度分组/稳定排序到raw projection阵列的属性SRAM读取顶层仍待封装。
- SH颜色尚未加入projection描述符。
- ordered block输出尚未连接64像素对生成与raster_pair_shell。
- 模式建议器尚未连接APB的自动/手动选择和中断状态位。
