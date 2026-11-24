# 排序后完整 Gaussian 属性 AXI4 读取规格 v0.1

- 日期：2026-08-09
- 数据流：深度分组 + Gaussian有序发射 + Gaussian内部8×8 block遍历
- RTL：`rtl/dma/axi4_gaussian_attribute_read_engine.sv`

## 设计目的

首遍mean/GID DMA只为深度预处理供数。深度分组和组内稳定排序后，每个有序GID向属性后端发起一次request；返回的完整属性被原子锁存，随后由projection、每Gaussian一次SH及该Gaussian全部8×8 block复用。

该路径不预搬全部宽属性，不创建Gaussian–tile KV/bin、per-tile list或per-tile排序。

## Request/response合同

- request：`valid/ready + GID`，首版最多一个outstanding，保持严格Gaussian顺序。
- response：`valid/ready + error + 1118-bit完整属性`。
- issue单元在response握手时复制完整属性，此后后端可以立即改变输出；渲染背压不会反压到AXI R通道中的已完成事务。
- 模式commit冻结新的有序请求，并等待当前request/response、projection、SH、block、pixel、alpha/blend全部排空后在epoch边界应用。

## 片外记录布局

每个GID固定占144 Byte，即9个128-bit beat：

- bits[1117:0]：与片上属性SRAM相同的逻辑属性向量；
- bits[1151:1118]：保留，软件写0；
- 记录地址：`ATTRIBUTE_BASE + GID × 144`。

1118-bit属性向量从高到低依次为：world xyz、quaternion wxyz、scale xyz、opacity、3×16个SH系数；各字段位宽仍分别为27、22、24、13和18 bit。

## AXI合同和错误

- 128-bit AXI4 INCR读取，单outstanding固定ID。
- 每条记录通常为9拍；若记录跨4 KiB边界则拆成两个burst后再原子重组。
- 检查RRESP、RID与RLAST早/晚错误。
- `ATTRIBUTE_BASE`必须16 Byte对齐；不对齐不发AR并返回错误response。
- ERROR_STATUS bit12：完整属性AXI response/protocol错误。
- ERROR_STATUS bit13：完整属性DMA配置/对齐错误。
- 属性错误经issue后端错误、frame error、done/error pending和IRQ统一完成，错误帧不会挂起。

## APB扩展

- `0x03C ATTRIBUTE_BASE_LO`
- `0x040 ATTRIBUTE_BASE_HI`

首遍mean紧凑数组使用`GAUSSIAN_BASE`，第二遍完整属性数组使用`ATTRIBUTE_BASE`，二者地址语义独立。

## 当前边界

首版按一个GID发一个9拍记录，不含属性cache和多outstanding合并。该结构以正确性和明确顺序为优先，后续可在不改变request/response合同的情况下增加小型属性cache、预取或多outstanding调度。
