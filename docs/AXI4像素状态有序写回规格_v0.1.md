# AXI4 像素状态有序写回规格 v0.1

- 日期：2026-08-09
- RTL：`rtl/dma/axi4_pixel_state_write_engine.sv`
- 目标：保持唯一blend/image-state writer的提交顺序并形成片外最终图像状态

## 写回方式

每次blend提交产生一个128-bit完整像素状态，写到：

`OUTPUT_BASE + pixel_id × 16`

首版采用单outstanding AXI4写事务。AW与W可独立握手，但下一个像素提交必须等待前一事务B响应。因核心本身已按全局pixel issue sequence有序退休，同一pixel的多次更新会按前后顺序覆盖，最终一次写即为最终像素状态。

该方式不复制有状态blend/image-state writer，也不改变Gaussian顺序；属于正确性优先基线。后续若增加write combining，必须保持同pixel RAW顺序。

## 128-bit记录布局

| 位段 | 字段 |
|---:|---|
| 12:0 | R，Q1.12 |
| 25:13 | G，Q1.12 |
| 38:26 | B，Q1.12 |
| 54:39 | T，Q0.16 |
| 70:55 | epoch |
| 83:71 | 本次alpha，Q1.12 |
| 84 | pass alpha |
| 85 | newly terminated |
| 117:86 | GID |
| 127:118 | 保留0 |

软件进行最终图像质量评价时读取RGB字段；T和调试字段用于定点误差与提前终止分析。

## AXI4合同

- 128-bit、单拍INCR写，`AWLEN=0`、`AWSIZE=4`、全字节WSTRB、WLAST=1。
- OUTPUT_BASE必须16 Byte对齐。
- AW/W分别保持到握手，之后等待固定BID的OKAY响应。
- BRESP或BID错误置ERROR_STATUS bit14；配置/对齐错误置bit15。
- `frame_busy = core_busy || write_busy || completion_pending`。
- 核心frame done只记录为内部pending；最后一笔B响应排空后才产生软件可见done/IRQ。

## 当前边界

当前写回的是每次像素状态更新而不只是帧末最终像素，因此带宽大但语义明确。后续真实分辨率优化可加入小型dirty-pixel cache或帧末扫描写回，同时必须与片上image-state容量扩展共同设计。
