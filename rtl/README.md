# 3DGS ASIC RTL 骨架

2026-10-13 T05重新验收：生产默认K16空间Bitonic（`BSU_PIPELINED=1`），双输入组缓冲与
10级弹性CAS流水允许收组、排序和发组重叠；首层首对使用共享G，其余79个CAS专用。
240次同版本选型和40次最终默认参数发布测试均通过，所有图像来自RGB DMA；支持8/16自然
容量的四子集命令，CPU暂时定义组间范围，硬件自主QSU仍由T06完成。满组理想稳态16拍/组，
不把该BSU吞吐提升冒充整帧加速。详见[T05 v2规格](../docs/T05_BSU接口与共享资源规格_v2.md)。
下方2026-10-10的K8折叠结论是已被本轮替代的历史记录。

2026-10-10 T05：生产默认使用 `USE_BITONIC_SORT=1`、K8 折叠 BSU，并启用共享 R
`old_T*alpha`。每批一个比较走 G/P/R PE、最多三个比较走专用 lane；完整 key 相等时按
到达次序稳定输出。共享 R 直接消费 PE 寄存响应，省去重复结果寄存级。五场景、五配置、
四模式、两种 AXI 共200次真实 RGB DMA 对拍通过；另五场景连续两帧验证安全epoch切换。
K8/K16 双工艺 TT 模块映射已取得，完整芯片 STA/功耗未签核。详细接口、算子边界与
资源代价见 [T05规格](../docs/T05_BSU接口与共享资源规格_v1.md)。下方2026-09等记录是历史，
其中“R默认关闭/仅插入排序”的描述已由本记录取代。

2026-09-20 起，开发排程以
[毕业设计剩余任务执行清单](../docs/毕业设计剩余任务执行清单_2026-09-20.md)为入口，
按编号关闭主要验收项；以下轮次记录保留为历史证据，不作为新的自动优化任务。

2026-09-19：保持 RTL 不变，新增 `shape_alpha_skip` 联合配置验证入口；五负载
200 次五路 DMA 图像一致，联合相对 alpha-only 16/40 更快、24/40 持平，
平均额外省 0.787% 周期，额外状态读写减少为 0。两个开关仍默认关闭。
结构展开、自动两帧、Python163与联合顶层 lint 通过；详细证据和下一轮共享
排序搜索优化计划见 `docs/RTL验证日志_2026-09-19_Alpha恢复与联合剪枝消融.md`。

2026-09-17 新增顶层参数 `ENABLE_ALPHA_ZERO_SKIP=0`（默认关闭）：四路 alpha
有序退休后，未通过阈值的像素直接完成，不进入 blend 或状态读改写；有效 alpha
仍走原唯一状态提交口。13 场景 n32 加两组 Train n128 的当前源码 360 次 DMA 中，
120 个候选配置 RGB/T 全等且均快于共享投影基线，n32 的 104/104 也快于未优化
完全旁路；总计少 45,496 次状态读、72,688 次状态写。稀疏 n128 d8 相对旁路
仍慢，ASIC 映射面积/时序/功耗未测，因此不启用默认。Icarus 80、Python 相关定向测试和
默认/候选顶层 lint 通过；完整记录见
`docs/RTL验证日志_2026-09-17_透明Alpha状态事务跳过.md`。以下旧轮次报告均为
当时源码证据，不应将其标为本轮当前源码。

2026-09-17 将默认关闭的形状判定器改为编译期资源隔离：默认顶层展开 0 个判定器，
启用候选才有 1 个；共享 PE 实例仍为 1。13 场景 104 次候选运行均快于共享基线，
但只有 60/104 快于 bypass，最差仍慢 7.032%；另有两组 Train n128 压力对拍。
当前源码正式 96+72 DMA、排序 42 配置、Icarus/Verilator 和 Python 151 回归通过。
无目标工艺库及综合/STA 工具，不能把结构展开或周期结果当作 PPA 签核；候选维持
默认关闭。证据与限制见 `docs/RTL验证日志_2026-09-17_形状候选资源隔离与扩展场景.md`。

2026-09-16新增默认关闭的 `ENABLE_SHAPE_BLOCK_REJECT`：在原 Gaussian 内部 8×8
block 握手处，以保守一轴 alpha 下界跳过无贡献块，不改变深度分组、Gaussian 有序发射、
block 遍历或动态 G/P/R/E。六场景 144 次 DMA 仿真中候选 48/48 个 epoch 生效后的 RGB/T
图像一致，全部快于共享基线（平均省 71.6875 周期），共跳过 384 块；但只在 22/48
个配置中快于完整 bypass，且原始帧槽记录不同。面积/时序/能耗未签核，维持默认关闭。
当前源码另外重跑 96+72 正式 DMA 基线、排序 42 配置/147,343 输出/374 定向 case，
证据见 `experiments/shared_pe/validation_20260916_shape_block_reject_n32` 和
`docs/RTL验证日志_2026-09-16_保守形状感知Block跳过.md`。

2026-09-15新增默认关闭的`USE_STREAMING_DEPTH_PREPASS`资源折中候选：collect阶段可用
三乘法器流式Z前端，G排序和主XYZ仍使用原单共享PE。六场景48个候选配置全部逐bit一致并
相对默认共享方案提速；ideal collect 99→66、limited 139→135。相对完整旁路仍平均/最大
+1.983493%/+5.423123%，且恢复3个乘法器，故不是默认配置或PPA通过。当轮源码96+72 DMA、
排序42配置/147,343输出/374定向case、Python146和Icarus77均复验。证据目录
`experiments/shared_pe/validation_20260915_streaming_prepass_n32`。

2026-09-14最新生产交接：`world_to_camera_shared_mac`默认启用输出turnover及first-request
旁路，第一次仲裁失败锁存重试；`ordered_gaussian_attribute_issue`默认启用有序请求交接及
good-response旁路，背压capture保持、错误不旁路，最多一笔后端请求不变。各模块可关闭
开关消融，没有新增PE/乘法器，mux/ready路径STA/PPA未评价。12项消融、168当前源码DMA、
Python142、Icarus77+综合入口及顶层检查通过；同口径生产18/24、候选20/24跨轮提速。
默认/候选相对当前旁路平均最大仍+3.078960%/+6.305578%、+2.320832%/+4.814522%，
Gate 1/2仍PARTIAL、排序候选仍默认关闭。最终证据目录`validation_20260914_xyz_turnover_n32`，
DMA为`dma_matrix_release`/`dma_expanded_release`，下文前轮sort数字为历史锚点。

2026-09-14本轮：可选排序新增`PARALLEL_SORT_STABLE_RUN_FASTPATH`（默认1，但
`USE_PARALLEL_GROUP_SORT`仍默认0）。非递增输入按相等完整key段逆向遍历、段内正向；
逆序前缀的末项使用共享G比较二分定位并按稳定顺序插入发射；检测两方向失效后停止。
仅新增run-start地址元数据，不复制Gaussian payload数组。42配置147,343条模块输出
对拍通过，374/374无背压定向case不退化；四路4类完整帧最终RGB/T全等、APB命中计数核验。
证据目录`experiments/shared_pe/validation_20260914_stable_runs_n32`，默认架构及G/P/R/E不变。
该范围不是任意负载最优排序或PPA签核；Gate 1/2仍PARTIAL。最终 RGB DMA 已由 T04 独立闭环。

当前目录是工艺无关的 SystemVerilog 控制通路基线，目标是先固定可验证的事务协议，再逐步接入定点投影、排序、alpha 和 blend 算子。

## 已实现模块

- `common/rv_reg_slice.sv`：单项弹性寄存切片。
- `common/rv_skid_buffer.sv`：两项 skid buffer，切断长 ready 路径。
- `control/cfg_epoch_ctrl.sv`：shadow/active 原子提交、epoch 递增、重复提交告警。
- `control/shared_reconfigurable_pe_slice.sv`：共享compare/MAC物理切片；G/P/R按weight credit
  与owner优先级仲裁，带grant/stall/utilization、安全重配置和clock-enable边界。生产帧级路径
  已让G客户端执行稳定排序比较、P客户端执行相机Z深度三项MAC及主投影XYZ九项MAC。
- `projection/world_to_camera_shared_mac.sv`：lane分发前共享XYZ变换，三轴交错发射并按轴追踪
  乘加依赖；输出饱和/溢出和meta保持与旧九乘法器实现逐bit一致。
- `control/sat_counter_bank.sv`：可清零、可快照的 64 位饱和计数器组。
- `raster/raster_pair_shell.sv`：终止过滤、多 alpha lane、有序退休和唯一 blend/image-state 提交口的集成壳，维持任务标签与严格提交顺序。
- `raster/block_termination_bank.sv`：保存完整block tag和epoch的单bank终止状态存储。
- `raster/block_termination_table.sv`：bank化、一周期查询、同址写穿透的终止状态表。
- `raster/pixel_termination_mask.sv`：每8×8块64位单调终止mask，首次全终止写回粗粒度终止表。
- `raster/alpha_block_float_core.sv`：保半正定Cholesky双指数块浮点alpha流水。
- `raster/gaussian_shape_block_reject.sv`：默认关闭的一轴保守 alpha 下界，证明整块
  Gaussian 内部 8×8 像素均无贡献时跳过；单独局部乘法运算符，PPA 待测。
- `raster/raster_alpha_lane_array.sv`：1/2/4 路可启停 alpha 阵列；允许无状态计算乱序完成，但按像素 issue sequence 有序退休。
- `raster/blend_fixed_core.sv`：Q1.12 RGB/alpha与Q0.16透射率前向混合。
- `raster/image_state_store.sv`、`blend_state_commit.sv`：64×64 tile状态和保守读改写提交闭环。
- `control/apb_regfile.sv`：APB控制/状态寄存器表，含帧启动、模式、地址/尺寸、sticky done/error和maskable IRQ。
- `memory/sram_1r1w_wrapper.sv`：具体工艺宏可替换的一读一写SRAM合同。
- `memory/gaussian_attribute_store.sv`：按frame-local GID寻址的完整Gaussian属性存储，逻辑上拆分geometry与SH appearance bank。
- `sort/ordered_gaussian_attribute_issue.sv`：将排序后的GID/sequence与一周期属性响应对齐，支持背压和非法/未加载检测。
- `gaussian_ordered_render_frontend.sv`：完整Gaussian属性到projection、一次SH、8×8 block、pixel、alpha/blend的有序前端。
- `sh/ordered_sh_lane_scheduler.sv`、`sh/gaussian_sh_color_array.sv`：动态多SH lane及乱序完成后的sequence有序退休。
- `gaussian_sorted_render_pipeline.sv`：排序元数据、一次属性读取和完整有序渲染前端的集成边界，并覆盖动态模式切换排空。
- `gaussian_frame_render_pipeline.sv`：帧级完整计算顶层，贯通mean-only深度预处理、粗分组、稳定排序、属性读取和完整Gaussian-wise渲染，并提供启动、排空、完成及sticky error合同。
- `dma/axi4_final_rgb_frame_dma.sv`：帧末扫描 RGB/T/epoch scratch，处理背景与 Q12→RGB888 量化，以 4 KiB 安全 burst 写最终成品帧。
- `gs_accel_top.sv`：保留的早期APB/光栅兼容子集。
- `gs_accel_system_top.sv`：唯一生产/系统验证顶层，集成APB命令、帧级完整计算链、AXI mean/attribute/state DMA、sticky状态和IRQ。
- `raster/raster_termination_filter.sv`：在属性读取和alpha发射前过滤已经终止的块任务。

## 接口约定

内部数据流采用 ready/valid 语义。仅当 `valid && ready` 时发生传输；发送端在停顿期间必须保持 payload 不变。配置只在 `epoch_boundary && affected_empty` 时从 shadow 原子切换到 active。

## 当前边界

系统主顶层当前默认启用 `USE_AXI_MEAN_DMA=1`，由 `dma/axi4_gaussian_mean_read_dma.sv` 完成第一遍mean/GID的128-bit AXI4顺序读取。该DMA采用单outstanding、最多16拍、不跨4 KiB边界，并把RRESP/RID/RLAST错误纳入统一帧错误和IRQ。参数置0只用于既有外部mean流回归。

排序后完整属性默认由 `USE_AXI_ATTR_DMA=1` 的 `dma/axi4_gaussian_attribute_read_engine.sv` 按GID读取。每条属性为144 Byte/9个128-bit拍，跨4 KiB时拆burst并原子重组；`ordered_gaussian_attribute_issue`会锁存完整响应，使SRAM和AXI后端共享同一request/response合同。

`USE_AXI_PIXEL_WRITE=1`默认把唯一blend提交按pixel ID写到 scratch。生产默认同时启用 `USE_FINAL_RGB_DMA=1`：RGB 图像位于 `OUTPUT_BASE`，行跨度为 `align16(width×3)`；scratch 位于图像之后，地址为 `OUTPUT_BASE + stride×height + pixel_id×16`。`dma/axi4_pixel_state_write_engine.sv`保持同pixel提交顺序。

完整Gaussian属性默认在排序后按GID通过AXI attribute engine读取；参数化片上SRAM后端仅用于兼容回归。像素结果先通过AXI state backing和write-through路径保持正确性，最终批次排空后由 T04 DMA 形成 RGB888 成品帧；系统 done 等待最后 RGB B 响应。1080p 带宽和完整画质仍归 T10/T12 验收。

终止表使用低位bank映射、后续位行映射，并保存完整block tag与epoch。容量映射碰撞只会替换旧项，不会产生错误的“已终止”命中；epoch标签提供逻辑清空。同址查询与更新采用写穿透语义。

这些文件尚未使用目标 ASIC 标准单元库和 SRAM 宏进行综合、STA 或功耗分析。当前已使用 Windows 版 Icarus Verilog 12 执行 SystemVerilog 自检查回归；Icarus 回归以 `SYNTHESIS` 宏绕开其不完整的 SVA 支持，因此仍需用 Verilator 或商业工具补做 lint/SVA/形式验证，并在工艺环境就绪后完成 PPA。

当前 Raster 并行采用正确性优先的安全结构：只复制无图像状态的 alpha 算术 lane，全部结果恢复全局像素发射顺序后，进入唯一的 blend/image-state 读改写提交口。该结构已经支持 G/P/R/E epoch 级 1/2/4 lane 启停并保证同像素前到后 RAW 顺序，但尚未复制有状态写端口；后续若扩展 bank 化多提交口，必须增加显式 pixel scoreboard 与 bank 仲裁。

共享compare/MAC PE默认实例化到`gaussian_frame_render_pipeline`：v2的G客户端服务每子集首层首对比较（折叠/旧插入保留为对照），
P客户端完成mean-only深度预处理和主投影XYZ变换。主XYZ变换在lane分发前统一执行，lane中
仅寄存已变换mean，协方差旋转及SH仍保持原数据路径。mode table的weight/owner/gate和epoch
提交已接通，APB `0x064–0x07c`可读活动计数。`USE_SHARED_PE=0`是完整旧路径golden；
`USE_SHARED_PROJECTION_PE=0`仅旁路主XYZ共享变换，保留上一轮G/P预处理配置。
深度预处理现默认四上下文有序缓冲，单PE三MAC连续发射；异常DMA end等待已接受mean排空，
避免在未完成MAC时切换P所有权。1/3/4上下文各324组差分通过，64-Gaussian连续流384→195周期。
三场景默认三配置72项DMA图像哈希全等，24项主共享配置均出现真实G/P竞争；周期平均退化已由7.324667%
降至3.166617%（最大6.376110%），微负载621对旁路602 cycles，仍未达到性能验收。
以下为2026-09-17历史比较，已由T05正式G/P/R功能集成取代；最终PPA仍未完成。
旧 `USE_SHARED_RASTER_PE=1` 曾是默认关闭的真实R混合MAC候选：在唯一有序blend口将
`old_t_q16*alpha_q12`送入同一共享PE，四上下文缓存并保持提交顺序。当轮源码96次DMA
图像对拍通过，但n32的24/24个候选配置相对本地blend变慢（平均+9.919%、最差
+17.426%）；没有工艺PPA证据，不能据此切换生产默认或称R阶段全部共享。

`USE_PARALLEL_GROUP_SORT=1`提供奇偶比较交换候选（默认0，仅共享master启用时生效）：
每批一对走共享G，其余最多`LANES-1`对使用本地比较器，首项接受时锁存G模式预算，两个完整
异奇偶阶段无交换可提前完成。新增`PARALLEL_SORT_SERIAL_FALLBACK=1`：预算1使用同组数组
上的流式插入，避免旧候选低预算退化；`PARALLEL_SORT_BATCH_FORWARDING=1`仅转发同阶段
不相交batch。新增`PARALLEL_SORT_PHASE_FORWARDING=1`只在合法未收敛阶段边界使用
交换后source-address旁路，不能直接读取未写回的旧数组；失败仲裁写回后保持请求重试。
`PARALLEL_SORT_MONOTONIC_FASTPATH=1`复用lane1比较器在COLLECT判定完整三级key的
非递减/严格递减，分别正向/反向发射；相等全键不得反向，其余输入继续网络，预算1保持回退。
容量1/2/3/8/16/32的36配置、108,996项输出对拍通过。16项预算2逆序32周期（串行78），
32项预算4逆序64（串行158）；原134case均不退化，但扩展164case仍4失败，不换默认。
12类32-bit工作计数含serial shift/collect，frame/system/APB已接通原子模差快照；
0x080 capture/rebase、0x084 capabilities、0x088–0x0b4冻结12字段。新帧rebase、continuation
保持、soft reset清零，默认/legacy无候选读0能力及0快照；仍无面积/时序/能耗签核。
本轮四配置96项真实DMA证据位于
`experiments/shared_pe/validation_20260914_monotonic_sort_n32/dma_matrix_checked`；上一轮phase关闭
单调检测独立复测。此矩阵fast=0、24项周期与上轮相同，增加504次collect比较；
不把候选相对串行收益视为相对完整旁路的加速或PPA签核。
共享APB计数不包含本地比较工作，面积/时序/能耗均待签核；详见本轮排序候选开发日志。

`gs_accel_system_top` 已用 `gaussian_frame_render_pipeline` 建立APB控制的完整计算系统边界；旧 `gs_accel_top` 只作为兼容测试子集保留，不代表当前系统能力。生产默认通过 `camera_base` 读取并校验 v1 相机描述符；启用默认state cache backing时不受片上4096项整帧容量限制，禁用backing时帧控制器才会拒绝 `width×height` 超容量配置。两种配置均未完成1080p性能与带宽签核。
## Image-State Backing Cache（2026-08-09）

系统顶层默认启用 `USE_STATE_CACHE_BACKEND=1`、`STATE_WINDOW_ENTRIES=2` 和 `STATE_MSHR_COUNT=2`。综合允许三种物理组合：2-entry+1-MSHR生成Phase A单reader，2-entry+2-MSHR生成默认Phase B双tagged reader，4-entry+4-MSHR生成研究用四ID乱序reader；其他组合由elaboration assertion拒绝。生产配置从 `OUTPUT_BASE + align16(width×3)×height + pixel_id×16` 读回；关闭最终 RGB DMA 的兼容测试仍使用旧 `OUTPUT_BASE + pixel_id×16` 布局。epoch不匹配返回逻辑clear state，blend commit同时更新cache并由原写DMA write-through。4+4使用独立generate分支，不进入默认2+2综合网表。

为保持同 pixel RAW 顺序，状态 miss 在先前写事务收到 B response 前不会发射。系统 done 同时等待 cache、状态读和写 DMA 排空。启用 backing 后 `STATE_ENTRIES` 是 cache 工作集容量而非整帧容量；禁用时仍保留整帧容量检查。`ERROR_STATUS[16:17]` 用于状态读协议/响应和配置/对齐错误。

当前实现是 correctness-first 的 single-miss/single-writer 基线。真实 1080p 是否满足性能与带宽目标，必须以 13 场景的 cache miss、stall 和 AXI 流量统计为依据，不能仅由 32 位地址和 backing 接口推断。

## 真实训练属性 RTL 微负载（2026-08-09）

`scripts/build_rtl_real_workload.py` 可从本地训练场景生成 mean、完整属性、相机 memory image 与 manifest。首个 `bonsai/camera 146/4 Gaussian/32×21` 微负载已贯通完整系统并加入一键 Icarus 回归：1049 busy cycles、68 commits、68 state miss/read/write、201 state-read stall cycles，自检 PASS。

该结果只证明真实字段打包与完整事务链可工作，不代表完整 bonsai 场景性能，也不能用于 PSNR/SSIM/LPIPS。详细合同与限制见 `docs/真实场景DMA到RTL负载桥规格_v0.1.md`。

真实负载testbench现支持从memory image加载任意已生成场景，配置AXI首拍延迟、拍间空泡、ready占空比和B响应延迟，并导出完整128-bit frame-state。bonsai、garden、train三场景8-Gaussian矩阵在受限AXI下分别产生约2.01×、2.01×、2.08×周期开销，但最终frame-state与理想AXI逐位一致。该结果指向state backing延迟瓶颈，而不是Gaussian-wise算术吞吐瓶颈。

`dma/axi4_pixel_state_write_buffer.sv` 在唯一有序writer前增加默认2项commit FIFO和完整pixel-tag hazard CAM。不同pixel的state miss可以与旧写回重叠，同pixel仍等待最新写穿透完成。三场景矩阵相对旧全局写互锁获得1.26×–1.46×加速，read-stall降为0，最终frame-state逐位不变。深度2/4/8/16扫描无额外周期收益，因此默认收敛到面积更小的2项。

`dma/axi4_pixel_state_writeback_buffer.sv` 提供可选的全相联dirty pixel合并、完整128-bit前递、最老项驱逐和frame flush。train n32/cache512实验中，depth128把写次数从795降到658，但受当前单未决writer帧尾串行排空影响，总周期反而增加。因此 `USE_PIXEL_WRITEBACK_BUFFER` 默认值为0，正式主配置继续使用2-entry write-through FIFO；write-back只作为未来多未决/突发AXI写研究路径保留。

`dma/axi4_pixel_state_multiwrite_buffer.sv` 是当前默认pixel-state写路径。它以同一AXI ID维持B响应顺序，允许多笔事务等待B响应；AW/W可独立背压但按事务成对推进。完整pixel tag从入队保持到B回收，状态读不会越过尚未落地的同pixel写。默认深度8在train n32 limited负载下把周期从12415降至11353，在64周期B压力下从54366降至7303；所有frame-state逐位一致。深度最终仍需目标工艺PPA冻结。
