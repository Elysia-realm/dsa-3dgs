# 真实场景 DMA 到 RTL 负载桥规格 v0.1

- 日期：2026-08-09
- 适用顶层：`gs_accel_system_top`
- 主数据流：深度分组 + Gaussian 有序发射 + Gaussian 内部 8×8 block 遍历
- 数据边界：仅使用 `D:\3DGS\data` 本地场景，不上传网络

## 1. 目的与结果口径

负载桥把训练完成的 3DGS PLY 和相机参数转换为 RTL 可直接读取的 AXI memory image，用于验证第一遍 mean DMA、第二遍完整属性 DMA、投影/SH/光栅链、image-state miss read 和有序 write-through 回写。

结果严格分为两类：

1. 小型真实属性微负载：使用真实训练属性，但只含少量 Gaussian 和缩小分辨率，用来发现字段布局、定点范围、握手、排序及排空错误。
2. 完整场景性能/画质验证：覆盖完整或有明确代表性的场景工作集，并生成完整图像；只有这一类结果才能用于 PSNR、SSIM、LPIPS 和实时性能结论。

当前完成的是第 1 类，不能表述为完整 bonsai 场景性能。

## 2. Memory image 合同

生成入口为 `scripts/build_rtl_real_workload.py`，核心打包逻辑位于 `model/io/dma_workload.py`。

- `mean.memh`：每 Gaussian 一个 128-bit 记录，供第一遍深度预处理使用。
- 微负载的 `attribute.memh`：每 Gaussian 九个 128-bit beat，共 144 Byte，早期样本可按 frame-local GID 读取。
- 完整批次的 `global_gid.memh` + `attribute_sparse.memh`：槽位 `i` 保存一个 global GID 及其九拍紧凑属性；验证侧 AXI 从设备把 RTL 发出的 `ATTRIBUTE_BASE + global_GID×144` 地址映射到槽位。该稀疏映射只属于仿真 memory model，不改变综合 RTL 的全局地址合同。
- `camera.memh`：28×64-bit camera descriptor v1；word27 高32位为 `0x47534301`，
  低32位为当前批 Gaussian 数。生产顶层通过 `CAMERA_BASE` AXI DMA 读取。
- `manifest.json`：场景、相机、原 Gaussian 索引、地址、定点格式及选择口径。
- `workload_params.svh`：供 testbench 使用的参数常量。

属性高层解包顺序为 `{world XYZ, quaternion WXYZ, scale XYZ, opacity, channel-major SH}`；memory image 按 RTL 低位优先合同放置 SH、opacity、scale Z/Y/X、quaternion Z/Y/X/W、mean Z/Y/X。

## 3. AXI testbench 合同

`verification/rtl/tb_real_dma_workload.sv` 提供四类单 outstanding memory model：mean AXI read、attribute AXI read、image-state AXI read，以及 image-state AXI write/B response。

testbench 检查帧必须完成且无 frame error，mean 拍数等于 Gaussian 数，属性拍数等于 Gaussian 数乘 9，cache miss 数等于实际状态读数，并要求产生非零像素提交和写回。

## 4. 性能计数定义

系统顶层在合法 start 时清零以下 64-bit 饱和计数器：

- `perf_cycle_count_o`：frame busy 的周期数；
- `perf_commit_count_o`：core commit 握手数；
- `perf_state_miss_count_o`：cache miss 请求握手数；
- `perf_state_read_stall_count_o`：miss 请求 valid 但状态读后端未 ready 的周期数；
- `perf_output_stall_count_o`：commit valid 但输出写 DMA 未 ready 的周期数。

这些计数器用于定位瓶颈，不等同于最终 ASIC 频率、帧率或带宽；后者还需要目标工艺时序和真实 AXI 延迟模型。

## 5. 首个本地真实属性微负载

目录：`experiments/rtl_workloads/bonsai_cammid_n4_d32`

- 场景/相机：bonsai / 146；
- 分辨率：32×21；Gaussian 数：4；
- mean/attribute AXI beat：4 / 36；
- busy：1049 cycles；pixel commit：68；
- state miss/read/write：68 / 68 / 68；
- state read stall：201 cycles；output commit stall：0 cycles；
- 自检结果：PASS。

完整机器可读报告见同目录 `rtl_report.json`。

## 6. 本轮发现并修复的错误

被裁剪 Gaussian 通过一个 `first=last=culled=1` 的 backpressured task beat 完成架构退休；`culled_pulse_o` 是同一事件的延迟通知。旧 `raw_gaussian_projection_lane` 把两者都计入 inflight 退休，导致计数器重复减一并下溢为 65535，最终使帧永久停在 DRAIN。

修复后 inflight 只由唯一的 `m_task_valid_o && m_task_ready_i && m_task_last_o` 握手退休。微负载由超时恢复为 1049 周期正常完成；单 lane cull 测试也增加了延迟通知后仍保持 idle 的检查。

## 7. 下一阶段

1. 在现有跨 PLY batch 的固定种子 priority sampling 之外，增加深度/屏幕覆盖分层采样模式。
2. 逐步扩大 Gaussian 数和图像尺寸，加入可配置 AXI 延迟/背压，形成 cache miss 与带宽敏感性曲线。
3. 建立定点渲染输出导出和逐像素参考比对，再扩展到 13 场景完整帧 PSNR、SSIM、LPIPS。
4. 由真实负载统计决定是否实现组相联 cache、多 outstanding 或 dirty/write-combining；优化前后必须保持逐像素等价。

## 8. 可配置 AXI 矩阵与完整帧状态导出

`tb_real_dma_workload.sv` 已取消场景、相机、Gaussian 数、分辨率和相机定点值的硬编码。仿真从 `camera.memh` 读取配置，并通过 plusargs 接收 mean/attribute/camera/frame 路径及以下时序参数：

- `READ_LATENCY`：读地址握手到首个返回拍的等待；
- `READ_GAP`：同一 burst 返回拍之间的空泡；
- `READY_PERIOD/READY_LOW`：读地址和写 AW/W 通道的周期性 ready 占空比；
- `WRITE_RESPONSE_LATENCY`：AW/W 完成到 B response 的等待。

仿真结束将所有 128-bit pixel state 写入 `frame_state_*.memh`。`scripts/decode_rtl_frame.py` 可把 Q1.12 RGB 解码为 PNG，并保留 transmittance 统计入口。`scripts/run_rtl_workload_matrix.py` 自动编译 testbench、运行多场景/多内存配置、解析性能计数，并要求不同 AXI 时序的最终 frame state SHA-256 完全一致。

首轮矩阵包含三个场景、每场景8个跨全PLY采样Gaussian：

| 场景 | 分辨率 | commits | ideal cycles | limited cycles | 周期倍率 | ideal/limited帧状态 |
|---|---:|---:|---:|---:|---:|---|
| bonsai | 32×21 | 108 | 1538 | 3097 | 2.01× | 逐位一致 |
| garden | 32×21 | 106 | 1514 | 3045 | 2.01× | 逐位一致 |
| train | 32×18 | 195 | 2582 | 5359 | 2.08× | 逐位一致 |

limited 配置为8周期首拍延迟、2周期拍间空泡、地址/写通道3/4 ready、8周期B响应。三场景在受限时序下仍逐位等价，但总周期约翻倍，表明当前 single-miss/write-through state path 对片外延迟非常敏感。该数据为后续增加 miss overlap、写合并或cache组织优化提供了依据。

## 9. 有序写缓冲与异 pixel 读写重叠

基于第8节瓶颈数据，系统在唯一AXI writer前增加深度可参数化、默认8项的有序commit FIFO。FIFO只解耦blend与B响应，不改变commit或AXI写回顺序。每项保存完整32-bit pixel tag，并与当前writer中的active pixel共同形成小型hazard CAM：

- miss pixel命中FIFO或active writer时等待，保证同pixel读取不会越过较新的write-through状态；
- miss pixel与所有待写pixel不同时，可与旧写事务重叠；
- frame done仍等待FIFO、writer B响应、state read和cache全部排空；
- AXI错误继续由原writer检测并进入统一ERROR_STATUS/IRQ。

优化前后多场景结果：

| 场景 | profile | 优化前cycles | 优化后cycles | 加速比 | 周期下降 | read stall |
|---|---|---:|---:|---:|---:|---:|
| bonsai | ideal | 1538 | 1219 | 1.26× | 20.7% | 321→0 |
| bonsai | limited | 3097 | 2171 | 1.43× | 29.9% | 963→0 |
| garden | ideal | 1514 | 1201 | 1.26× | 20.7% | 315→0 |
| garden | limited | 3045 | 2138 | 1.42× | 29.8% | 945→0 |
| train | ideal | 2582 | 2002 | 1.29× | 22.5% | 582→0 |
| train | limited | 5359 | 3679 | 1.46× | 31.3% | 1746→0 |

所有优化后ideal/limited帧状态与优化前SHA-256相同，state reads、writes和commits逐项相等。机器可读报告为 `real_dma_matrix_write_buffer_2026-08-09.json`。

## 10. 写缓冲深度和 Cache 容量敏感性

写缓冲深度2/4/8/16在三个n8场景的全部配置下周期完全相同。train n8配合64周期B响应的极端压力下，四种深度也均为13510周期。深度增加只移动output stall和同pixel hazard等待，并不缩短frame completion；因此默认深度由8收敛为2，payload存储从1216 bit降至304 bit，tag比较器数量同步下降。参数仍保留供工艺PPA扫描。

三个n8场景的连续同pixel commit均为0，安全的相邻写合并不会减少AXI事务，因此本轮不加入无收益的合并复杂度。

train n32、64×36负载显示cache容量开始有意义：

| State entries | limited cycles | misses / 795 | 相对32项加速 | 状态读下降 |
|---:|---:|---:|---:|---:|
| 32 | 14155 | 793 | 1.00× | 0% |
| 128 | 13906 | 768 | 1.02× | 3.2% |
| 512 | 12415 | 583 | 1.14× | 26.5% |

三种容量的最终frame-state逐位一致。默认系统cache仍保持4096项；最终ASIC容量必须结合完整场景trace和SRAM宏PPA决定，不能仅凭微负载冻结。

## 11. Dirty Pixel Write-Back 对照

真实负载testbench新增 `TB_USE_WRITEBACK` 和 `TB_WRITEBACK_DEPTH`，矩阵脚本新增 `--use-writeback` 与 `--writeback-depth`。由于write-back可在cache miss时直接前递dirty状态，`state_misses`表示cache miss请求数，`state_reads`表示实际AXI读数，两者不再强制相等；差值单独报告为`forwarded_reads`。

train n32、cache512的write-through与write-back depth8/32/128均导出完整128-bit frame-state。8个ideal/limited输出SHA-256完全一致。depth128把writes从795降至658，并实际触发3次系统级dirty状态前递；但总周期由6582/12415增加到7218/13224。原因是当前唯一单未决writer必须在帧末串行排空dirty项。

因此默认仍使用2-entry write-through FIFO，write-back仅作为参数化带宽研究路径。详细数据和决策见 `experiments/rtl_workloads/writeback_sensitivity_2026-08-09.md`。

## 12. 多未决AXI写与B响应队列

真实负载AXI memory model已从单一 `b_delay` 改为有序B响应队列，可以在前一B响应返回前继续接受AW/W事务。每笔写只有在真实AW和W握手均完成后才更新backing state并登记B到期周期，避免仅凭VALID重复计数。

新增 `REAL_MULTIWRITE` 输出和 `--use-multiwrite`、`--multiwrite-depth`、`--write-stress-latency` 参数。train n32/cache512的8项多未决默认路径在ideal/limited下为6396/11353周期，相对旧路径6582/12415分别提升约1.03×/1.09×；64周期B响应压力下由54366降至7303周期，提升7.44×。全部输出frame-state逐位一致。

默认采用8项多未决写；详细协议、深度扫描与验证见 `experiments/rtl_workloads/multiwrite_sensitivity_2026-08-09.md`。
