# AXI4 Gaussian 均值顺序读取 DMA 规格 v0.1

- 日期：2026-08-09
- 主系统顶层：`rtl/gs_accel_system_top.sv`
- DMA RTL：`rtl/dma/axi4_gaussian_mean_read_dma.sv`
- 状态：工艺无关 SystemVerilog RTL；Icarus 自检通过

## 1. 与总设计目标的关系

该 DMA 只负责 GCC 式 Gaussian-wise 数据流的第一遍访问：按帧内记录顺序读取 GID 和三维均值，直接供给深度预处理、四组粗深度分组和组内稳定排序。排序后仍按 GID 获取一次完整 Gaussian 属性，并在一个 Gaussian 内遍历其全部 8×8 block。

本实现没有创建 Gaussian–tile KV/bin、逐 tile Gaussian list 或逐 tile 排序。G/P/R/E 动态资源模式仍在帧/epoch 边界原子生效，DMA 不改变渲染顺序合同。

## 2. 片外均值记录格式

AXI 数据宽度固定为 128 bit，每个 Gaussian 一拍、16 Byte，地址必须 16 Byte 对齐：

| 位段 | 含义 |
|---:|---|
| 31:0 | frame-local GID |
| 58:32 | world X，27 位有符号 Q10.16 |
| 85:59 | world Y，27 位有符号 Q10.16 |
| 112:86 | world Z，27 位有符号 Q10.16 |
| 127:113 | 保留，软件写 0 |

`GAUSSIAN_BASE` 指向第一条均值记录，`GAUSSIAN_COUNT` 给出记录数。GID 不是片外字节地址，也不在 DMA 中截断；它保持为后续完整属性读取的帧内标识。

## 3. AXI4 读合同

- 只使用 AR/R 通道和 INCR burst；`ARSIZE=4`，每拍 16 Byte。
- 首版单 outstanding，固定 AXI ID；返回 RID 必须匹配。
- 每个 burst 最多 16 拍，并同时受剩余 Gaussian 数量限制。
- burst 不跨 4 KiB 边界；例如基址 `0xFF0` 时首 burst 只能为一拍。
- R 通道检查 `RRESP`、`RID` 和 `RLAST` 的提前/延迟错误。
- 下游背压时通过一项 holding register 拉低 `RREADY`，并保持 GID、均值和 last 稳定。
- 整帧 `source_last` 由 `GAUSSIAN_COUNT` 生成，不能用某个 burst 的 `RLAST` 代替。

## 4. 空帧和错误终止

`GAUSSIAN_COUNT=0` 时不发 AR 请求，经独立 `source_end_valid/source_end_ready` 控制事件结束空帧。地址未对齐或 AXI 读/协议错误也使用该控制事件关闭当前输入流，不伪造一条 Gaussian 或特殊 GID。

系统错误状态扩为 16 位：bit[9:0] 为原计算帧错误，bit10 为 mean DMA AXI response/protocol 错误，bit11 为 mean DMA 配置/16 Byte 对齐错误，bit[15:12] 保留。

错误帧仍走统一 frame done、done pending、error pending 和 maskable IRQ 路径。`CONTROL.STATUS_CLEAR` 清系统 sticky 状态以及空闲 DMA 的错误锁存。

## 5. 当前边界

这不是完整的片外存储子系统。完整 Gaussian 属性当前仍由片上逻辑属性 SRAM 预加载；后续需把排序后 GID 请求抽象为 request/response 接口，接入属性 cache 和 AXI 合并/随机读取。像素结果 AXI 写回及真实分辨率 image-state backing store 也尚未实现。

因此本阶段准确表述为“第一遍 mean/GID 顺序读 DMA 已闭环”，不能表述为完整属性 DMA 或完整帧缓冲 DMA 已完成。

## 6. 验证覆盖

- `tb_axi4_gaussian_mean_read_dma`：4 KiB 拆分、16 拍上限、尾 burst、下游背压、空帧、未对齐、SLVERR、错误 RID、RLAST 提前和延迟。
- `tb_gs_accel_system_axi_mean`：APB 配置至 AXI 读取、深度预处理和完整渲染链；AXI 错误至 frame error/IRQ；零 Gaussian 空帧。
