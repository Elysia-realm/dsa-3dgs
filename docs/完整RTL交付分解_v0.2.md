# 3DGS动态可重构ASIC完整RTL交付分解 v0.2

- 日期：2026-08-04
- 状态：采用Gaussian-wise有序渲染路线，替代v0.1中的潜在tile/bin解释
- 目标：提交可综合的完整SystemVerilog加速器RTL

## 1. 完整RTL边界

闭环必须覆盖命令、DMA、深度分组与稳定排序、Gaussian有序发射、投影、SH、
Gaussian内部块遍历、alpha/blend、图像状态、提前终止、有序退休、动态模式、计数器、
中断和结果写回。

其中Gaussian-wise是数据流基础，动态可重构是硬件设计主线；最终交付不能只完成
Gaussian-wise固定流水，也不能只有孤立的lane开关而缺少运行时观测、策略和公平基线。

外部CPU和DRAM不在RTL内实现，但控制从接口和AXI4 DMA主接口必须交付。

## 2. 模块分解

| 层级 | 必需模块 | Gaussian-wise职责 | 当前状态 |
|---|---|---|---|
| 控制 | APB/AXI4-Lite、命令、epoch | 配置、启动、安全模式提交 | 子集完成 |
| DMA | AXI4读写、burst、错误处理 | 均值首遍读取、属性按需读取、图像写回 | 待实现 |
| 深度前端 | depth transform、frustum cull | 只处理均值，生成depth/GID | 算术可复用，封装待实现 |
| 深度分组 | grouper、group目录、overflow | Gaussian映射粗深度组 | 软件模型完成，RTL待实现 |
| 组内排序 | stable sorter | 组内depth/GID稳定排序 | 软件模型完成，RTL待实现 |
| 有序控制 | issue queue、ROB/retire | 多lane完成恢复Gaussian顺序 | 待实现 |
| 投影阵列 | raw Gaussian projection array | 生成屏幕Gaussian与alpha描述符 | RTL完成 |
| SH | SH basis/evaluation | 当前Gaussian颜色，只计算一次 | 待实现 |
| block walker | bbox/中心向外块遍历 | 枚举当前Gaussian的8×8块 | bbox/矩形枚举RTL完成 |
| 光栅入口 | termination filter | 跳过已终止块 | RTL完成 |
| 像素生成 | 8×8坐标与活跃mask | 形成Gaussian–pixel计算向量 | 待实现 |
| alpha/blend | Cholesky、exp、RGB/T更新 | 当前Gaussian对块内像素贡献 | RTL子集完成 |
| 状态依赖 | image state、block scoreboard | 保证同像素前到后提交 | 保守闭环完成，并发优化待实现 |
| 动态模式 | 计数器、策略、滞回、epoch切换、门控 | 在G/P/R/E模式间分配group/projection/SH/raster资源 | projection lane切换完成，联合策略待实现 |
| ASIC适配 | SRAM wrapper、门控、SDC/UPF | 工艺映射和PPA | 工艺环境待准备 |

## 3. 删除项与保留项

### 从主路径删除

- Gaussian–tile KV生成、存储和DMA流量；
- 固定屏幕tile的Gaussian bin/list；
- 每tile独立深度排序；
- tile扫描驱动的Gaussian重复属性加载。

### 保留但重定义

- 8×8 tile坐标改称Gaussian block坐标；
- `gaussian_tile_task_gen`作为当前Gaussian的block walker；
- 块任务队列保存短期Gaussian-block工作，不形成跨Gaussian tile bin；
- block termination与64位pixel mask继续使用。

## 4. 实现顺序

1. depth/group/sequence描述符和SRAM合同。
2. depth grouper、稳定组内sorter和溢出慢路径。
3. ordered issue/retire与动态投影阵列连接。
4. G/P/R/E强制模式、资源表和阶段计数器。
5. SH颜色和Gaussian描述符缓存。
6. block walker、像素向量、alpha/blend和Gaussian retire闭环。
7. 长窗口自动模式策略、滞回、门控与切换开销统计。
8. DMA、顶层命令/中断和系统集成。
7. 真实场景整图PSNR/SSIM/LPIPS、性能流量与具体工艺PPA。

## 5. 强制验收

- 全部必需模块均为SystemVerilog RTL，不用Python模型替代。
- 固定模式和动态模式共享相同顺序、算术、带宽、SRAM和约束。
- 不得重新引入Gaussian–tile KV/bin与逐tile排序作为默认主路径。
- 多lane投影允许乱序完成，但blend必须按Gaussian sequence有序。
- 提交完整图像质量与具体工艺节点面积、功耗报告。
