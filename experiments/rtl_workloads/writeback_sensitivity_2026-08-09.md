# Dirty Pixel Write-Back Buffer 参数实验（2026-08-09）

## 目的

评估在唯一有序 AXI pixel-state writer 前加入全相联脏像素缓冲，能否在不改变以下主数据流的前提下降低片外写流量并提高性能：

- 深度分组；
- Gaussian 有序发射；
- Gaussian 内部 8×8 block 遍历；
- epoch 级 G/P/R/E 动态资源重构。

该结构不包含 Gaussian–tile KV/bin、逐 tile Gaussian list 或逐 tile 排序。

## 实验配置

- 真实训练属性负载：`train_cam150_n32_d64`；
- 32 个 Gaussian，64×36 像素，795 次 pixel-state commit；
- `STATE_ENTRIES=512`；
- 基线：2-entry write-through FIFO；
- 候选：8/32/128-entry 全相联 write-back buffer；
- ideal AXI：无读延迟/空泡，B response latency=2；
- limited AXI：读延迟8、拍间空泡2、通道 ready=3/4、B response latency=8。

## 结果

| 路径 | profile | cycles | state reads | state writes | coalesced | forwarded reads | output stall |
|---|---|---:|---:|---:|---:|---:|---:|
| write-through depth2 | ideal | 6582 | 583 | 795 | 0 | 0 | 184 |
| write-back depth8 | ideal | 6694 | 583 | 794 | 1 | 0 | 253 |
| write-back depth32 | ideal | 6753 | 583 | 751 | 44 | 0 | 168 |
| write-back depth128 | ideal | 7218 | 580 | 658 | 137 | 3 | 66 |
| write-through depth2 | limited | 12415 | 583 | 795 | 0 | 0 | 1074 |
| write-back depth8 | limited | 12668 | 583 | 794 | 1 | 0 | 1244 |
| write-back depth32 | limited | 12632 | 583 | 751 | 44 | 0 | 919 |
| write-back depth128 | limited | 13224 | 580 | 658 | 137 | 3 | 387 |

全部8个输出的完整128-bit frame-state SHA-256均为：

`F771C1FE4FEAE4858AD191C6F20CAFD2A8BD9C0C1EAA8FBE6BB4907E606E2634`

因此 write-through/write-back、不同深度和不同 AXI 时序下结果逐位一致。depth128 还在完整系统中实际触发3次 dirty-buffer miss forwarding，且未发出对应 AXI state read，验证了 cache 冲突换出后读取最新脏状态的集成路径。

## 结论与架构决策

- write-back 合并在功能上正确；depth128 将片外状态写从795次降至658次，下降17.2%。
- 当前 writer 仅允许单个未决事务，脏项在 frame 尾部串行 flush。节省的写流量没有转化为本负载端到端加速：depth128 的 ideal/limited 周期分别比 write-through 增加9.7%/6.5%。
- `PIXEL_WRITEBACK_DEPTH` 越大，CAM、tag和128-bit数据阵列成本越高；在当前性能结果下不适合设为默认。
- 系统默认恢复为2-entry write-through FIFO；write-back RTL保留为参数化实验路径，供未来多未决/突发 writer 或更完整场景带宽评估复用。
- 下一写侧性能研究应优先评估“多个未决 AXI 写或连续地址突发排空”，并继续要求完整 frame-state 逐位等价；不应仅继续增大 dirty buffer。

## 可复现文件

- `writeback_train_n32_wt2.json`
- `writeback_train_n32_wb8.json`
- `writeback_train_n32_wb32.json`
- `writeback_train_n32_wb128.json`
- `train_cam150_n32_d64/frame_state_wt2_{ideal,limited}.memh`
- `train_cam150_n32_d64/frame_state_wb{8,32,128}_{ideal,limited}.memh`

全部数据仅在 `D:/3DGS` 本地生成和保存，未上传网络。
