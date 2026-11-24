# RTL验证日志

## 2026-09-20：建立剩余任务执行清单（规划记录）

- 建立 [毕业设计剩余任务执行清单](毕业设计剩余任务执行清单_2026-09-20.md)，
  用 T00–T13 固定任务编号管理交付物、依赖、验收证据和停止优化条件。
- 后续以清单作为统一排程入口；历史“下一轮”安排保留为历史，不再自动延续。
  强调正式输入输出、共享资源、全场景执行、画质与真实 ASIC PPA，限制低收益候选反复迭代。
- 同步目标基线、审计规划、目录说明、RTL README 与实现状态中的入口信息。
  本次未修改 RTL、未运行硬件回归、未将任何实现验收项改为通过；审计日期仍为 2026-09-19。

## 2026-09-17：R 阶段共享 PE 混合候选

- 默认关闭的真实 R MAC 客户端已接到有序 blend `old_t×alpha`，四上下文流水和请求直通；
  固定深度分组、Gaussian 有序发射、内部 8×8 block 遍历及 G/P/R/E 模式不变。
- 定向 256 向量对拍、96 次当前源码完整 DMA A/B 和 Icarus 全回归通过；候选获得
  17,368 次 R 授权，所有场景 epoch 生效后的 RGB/T 图像一致。Python 153/153 通过。
- n32 24/24 候选配置相对原本地 blend 变慢，平均 +9.919%、最差 +17.426%；
  因此不切默认，Gate 1/2 仍 PARTIAL，PPA 未签核。旧报告标为历史证据。
- 详细记录：[R 阶段共享 PE 混合候选](D:/3DGS/docs/RTL验证日志_2026-09-17_R阶段共享PE混合候选.md)。

## 2026-09-17：形状候选资源隔离与扩展场景

- 默认关闭的形状判定器改为编译期生成：默认顶层展开实例 1→0，启用候选仍为 1；
  共享 PE 两种配置均为 1。原六场景 144 次跨轮周期/工作量/原始帧记录未变化。
- 13 场景共 312 次 DMA 通过，形状候选 104/104 快于共享基线，跳过 864 块、
  减少 3488 次提交；相对 bypass 仅 60/104 更快，44/104 退化，最差慢 7.032%。
- Train n128 的 8×4 样本跳过 0 块、8/8 与共享方案持平；64×36 样本跳过 328 块、
  8/8 快于共享方案、7/8 快于 bypass。两种样本 48 次 DMA 图像均一致。
- 当前源码额外重跑 96+72 正式 DMA 基线、排序 42 配置/147,343 输出/374 定向 case，
  Icarus 全回归、默认/候选 lint、五类展开和 Python 151/151 通过。无综合/STA/工艺库，
  所以只签结构和功能/周期，不签面积/频率/能耗；候选保持默认关闭，Gate 1/2 仍 PARTIAL。
- 详细记录：[形状候选资源隔离与扩展场景](D:/3DGS/docs/RTL验证日志_2026-09-17_形状候选资源隔离与扩展场景.md)，
  证据目录 `experiments/shared_pe/validation_20260917_shape_resource_guard`。

## 2026-09-16：保守形状感知 8×8 block 跳过

- 新增默认关闭的 `ENABLE_SHAPE_BLOCK_REJECT`，在原 Gaussian 内部 8×8 block
  握手处，用保守 `l11*dy` 下界证明整块 alpha 无贡献才跳过；固定主路径与 G/P/R/E 不变。
- 六场景 144 次 DMA 仿真通过：候选 48/48 个 epoch 生效后的 RGB/T 图像相同，
  相对共享基线全部提速，平均省 71.6875 周期；跳过 384 块、减少 1704 次提交/写。
- 相对完整 bypass 仅 22/48 提速，平均仍慢 0.147017%，最差慢 7.032181%；
  原始帧槽记录 48/48 不同于 shared，原因是省去了透明 epoch 写入。不能宣称 raw bit-exact
  或性能/PPA 通过，候选保持默认关闭。
- 20,000 随机 block 保守性检查、Icarus 全回归、默认/候选 lint、五类顶层展开，
  Python 150/150，以及当前源码 96+72 DMA 基线和排序 42 配置/147,343 输出/
  374 定向 case 已验证。
  详细记录：[保守形状感知 Block 跳过](D:/3DGS/docs/RTL验证日志_2026-09-16_保守形状感知Block跳过.md)，
  证据目录 `experiments/shared_pe/validation_20260916_shape_block_reject_n32`。
- 下一轮先量化目标工艺 PPA 和更大场景边界压力，再决定是否启用；R 客户端、最终 RGB DMA、
  GT 质量与自动配置性能仍未签核。

## 2026-09-15：流式Z预处理资源折中

- 新增默认关闭的`USE_STREAMING_DEPTH_PREPASS`综合候选；仅将collect相机Z改为三乘法器
  流式前端，G排序和主XYZ仍复用单共享PE，固定Gaussian主路径与G/P/R/E不变。
- 六场景×四模式×两AXI共48个候选运行逐bit一致且全部相对默认共享方案提速：ideal
  collect 99→66、整帧固定省33周期；limited 139→135、整帧固定省4周期。
- 每个n32共享P grant 384→288，恰移除96次预处理MAC；主XYZ仍288、G工作量不变。
  相对完整旁路仍平均/最大+1.983493%/+5.423123%，恢复3个乘法器，默认不启用、PPA未签核。
- 当前源码重新建立96+72 DMA正式基线；排序42配置147,343输出及374/374定向case也重跑。
  Python146、Icarus77+综合入口、默认/候选lint与四类展开通过，既有非致命告警保留。
- 详细日志：[流式Z预处理资源折中](D:/3DGS/docs/RTL验证日志_2026-09-15_流式Z预处理资源折中.md)；
  证据目录`experiments/shared_pe/validation_20260915_streaming_prepass_n32`。
- 下一轮优先保守shape/block reject及R共享接口；不继续加FIFO，也不在无PPA时推广流式候选。

## 2026-09-14：属性交接与投影首次发射旁路

- 两个生产模块消除输出交接空拍：XYZ首次MAC可在输入接受沿发射，失去仲裁锁存
  重试；attribute好响应直接提交、背压转寄存器保持，错误不旁路，单未完成请求不变。
  固定主路径/G/P/R/E/数值合同不变，不增加PE/乘法器；新增mux/ready路径PPA未签核。
- 12项same-stream/相同profile起始PRNG消融通过：XYZ ideal1536→1281（128输入、
  1152MAC），ATTR505→384（128请求、121输出、7错误拒绝）；不推广为整帧16.60%。
- 同口径96DMA功能通过，跨轮72配置工作量/图像全等且无周期退化；生产18提速/6持平，
  候选20提速/4持平，Garden E/ideal1357→1328，但旁路同时1278→1267。
- 生产相对旁路平均/最大+3.078960%/+6.305578%；候选+2.320832%/+4.814522%，仍
  NOT PASS，Gate 1/2仍PARTIAL、排序候选默认关闭；collect三MAC服务率未改变。
- 新增Truck/Room/Counter72DMA全等，候选24项对串行18提速/6持平0退化，统计独立。
  当前源码总168DMA通过，micro619/601/609/619；Python142、Icarus77+综合入口、顶层
  检查通过。继承sorter42配置/374定向case另有当前SHA，不冒称本轮重新执行全部。
- 详细日志：`docs/RTL验证日志_2026-09-14_属性交接与投影首次发射旁路.md`；目录
  `experiments/shared_pe/validation_20260914_xyz_turnover_n32`，最终`dma_matrix_release`/
  `dma_expanded_release`/`output_ablation_signed`/`round_audit.json`/`iverilog_signed.log`。
- 下一轮先评价collect三MAC单PE服务率/多slice折中与保守shape剪枝，不继续只消单周期
  空拍，不先重调旧自动oracle；R/全共享、camera/RGB、全场景边界、GT/PPA仍待实现。

## 2026-09-14：稳定段逆序与末项二分发射

- 固定Gaussian主路径/G/P/R/E不变；候选默认关闭。相等完整key段逆向遍历、段内
  正向；逆序前缀末项由共享G PE二分定位插入发射，非单调检测早退出。
- 42配置147,343条输出对拍通过；374/374无背压定向case不退化，上轮4反例全部修复。
  新增末项居中曾出现2退化，已修复并保留中间失败记录，不把集合PASS称普遍最优。
- 四路4类完整帧各1733commit、最终RGB/T与覆盖集合逐bit全等，APB确认路径与比较次数。
- 最终Bonsai/Train/Garden 96项DMA全等、72项旧配置周期/工作量不变；检测504→168
  （减少336，66.67%），fast仍0、24项周期与上轮相同，不能宣称真实整帧/能耗提升。
  Truck额外32项功能通过，独立报告，不混入同口径平均数。
- Python139、Icarus75自检+1综合入口、默认/候选顶层lint及展开通过。相对旁路仍
  平均/最大+2.414649%/+6.181534%，NOT PASS；Gate 1/2仍PARTIAL，PPA未签核。
- 详细记录：`docs/RTL验证日志_2026-09-14_稳定段逆序与末项二分发射.md`；证据目录
  `experiments/shared_pe/validation_20260914_stable_runs_n32`，最终基线`dma_matrix_final`，
  模块`sorter_ablation_checked`，源码哈希/跨轮核验`round_audit.json`。
- 下一步真实分布扩展、检测/网络/移动/服务等待消融与collect资源折中，随后R/全共享、
  形状、camera/RGB、自动策略与GT/PPA；不因定向改进而提前启用候选。

## 2026-09-14：单调排序快速路径与APB原子快照

- 复用lane1本地比较器检测接受流三级key：非递减正向、严格递减反向发射；全键相等
  不反转，其他输入继续网络，预算1回退保持，固定主路径/G/P/R/E不变，候选默认关闭。
- 36配置108,996项输出全等；16项预算2逆序97→32，32项预算4逆序193→64。
  原134定向case全不退化，但扩展至164后仍4失败（重复全键逆序/末项破坏单调性）。
- 12类工作计数含serial shift和collect，frame/system/APB快照已接通；验证逻辑帧累计、
  冻结快照、capture+rebase、soft reset及模回绕差值，不把计数次数当PPA收益。
- 四路升序/逆序整帧测试每帧1733commit、最终RGB/T全等，APB确认正反快速路径实际使用。
- 最终96项n32 DMA图像全等、72项旧配置周期/工作量未变；新候选fast=0、24项周期与
  上轮相同，增加504次collect本地工作；相对旁路仍+2.414649%/+6.181534%，NOT PASS。
- Python136、Icarus75自检+综合入口、双顶层lint/展开通过，完整日志留存。
  下一轮剩余4反例的稳定run/算法选择及检测开销评估；Gate 1/2和PPA不提前升级。
- 详细记录：`docs/RTL验证日志_2026-09-14_单调排序快速路径与APB原子快照.md`；证据：
  `experiments/shared_pe/validation_20260914_monotonic_sort_n32`，DMA最终引用`dma_matrix_checked`。

## 2026-09-13：交换后阶段旁路与扩容审计

- 新增独立阶段旁路参数：下一阶段操作数使用本拍交换后source-address视图，失败仲裁
  写回后保持重试；未直接读旧数组。固定Gaussian-wise主路径、G/P/R/E及默认候选关闭不变。
- 30配置（容量1/2/3/8/16/32×五算法开关）、89,520输出逐bit全等；16项预算4逆序
  80→65周期（串行78）。但预算2为97（串行78），32项预算4为193（串行158）。
  134无压力定向case中117不退化、17退化，扩大范围后性能仍NOT PASS，不以单项成功升级Gate。
- 八类模块工作计数监控核验通过，阶段旁路开/关比较/交换/阶段数量相同；frame留空未接
  APB、未计serial shift，仍不能称生产总工作计数闭环。新增mux成本无STA/PPA证据。
- 最终96项DMA输出hash一致，72项旧配置跨轮周期/工作量不变；相对上轮18项再省4–8
  周期、6项持平。候选相对串行18提速/6持平/0退化，相对完整旁路平均/最大
  +2.414649%/+6.181534%，仍NOT PASS；默认+3.166617%/+6.376110%不变。
- Python133项、Icarus73自检+综合入口、双顶层lint/展开通过；微负载621/602/610/621。
- 下一轮通用算法选择处理预算2/较大容量边界，补serial shift和APB生产计数，再分析collect
  吞吐资源折中，不先调自动建议器。详细记录：
  `docs/RTL验证日志_2026-09-13_排序阶段交换后旁路与扩容审计.md`；当前证据：
  `experiments/shared_pe/validation_20260913_phase_sort_n32`。以下为历史轮次。

## 2026-09-13：低预算排序回退与阶段内批间转发

- 候选在首项接受时锁存G预算；预算1走同组存储流式插入，高预算仅转发同阶段不相交batch。
  固定Gaussian-wise主路径及动态G/P/R/E保留，候选默认仍关闭，没有全共享阵列/PPA声明。
- 16配置消融、15,828项输出对拍通过；16项逆序预算1由272恢复到78周期，与串行一致；
  预算4由96降到80，但串行78，仍有2周期对抗输入退化。
- 三场景五配置120项DMA输出hash全等；新候选18/24提速、6/24持平、0/24退化，
  旧候选关闭新选项仍复现14/24提速、10/24退化。96项旧配置跨轮输出/工作量/周期未变。
- 新候选相对完整旁路平均/最大+2.637230%/+6.181534%，仍NOT PASS；默认主共享
  +3.166617%/+6.376110%不变。微负载默认/旁路/prepass-only/新候选621/602/610/621。
- Python131项、Icarus73项+综合入口、默认/候选lint及展开检查通过。Gate 1/2仍PARTIAL。
- 下一轮处理高预算对抗输入剩余退化、补总排序工作计数，并继续评估collect吞吐资源折中。
  详细记录：`docs/RTL验证日志_2026-09-13_低预算排序回退与批间转发.md`；证据目录：
  `experiments/shared_pe/validation_20260913_adaptive_sort_n32`。下面保留前轮历史结论。

## 2026-09-13：并行组内排序候选与资源折中

- 新增奇偶比较交换网络候选：每批1对走共享G、其余最多3对本地并行比较，批宽跟随G预算；
  两个完整奇偶阶段无交换时完成。固定Gaussian-wise主路径、G/P竞争及动态G/P/R/E保留。
- 容量1/3/8/16×串行/并行共8项消融，每项263组，同输入流共7,804项输出对拍通过；覆盖
  稳定三级键及全键tie、signed极值、收敛反例、溢出、P竞争、输出/请求保持及模式预算锁存。
- 最终三场景96项DMA输出与上一轮等价，默认72项周期不变；候选G模式6/6提速，合计
  14/24提速、10/24退化，E模式6/6退化。候选相对旁路平均/最大+3.184453%/+8.998435%，
  整体并未优于默认串行。`USE_PARALLEL_GROUP_SORT=0`继续默认，Gate 1/2均PARTIAL。
- 新增结构是混合候选，不是全共享PE池；现有APB G grant/utilization不含本地比较，PPA未签核。
- Python129项、Icarus73项+综合入口、默认及候选生产顶层lint通过；下一轮先解决低预算/逆序
  退化、补总排序工作计数和共享资源边界，不先拟合建议器或增加R客户端。
- 详细记录：`docs/RTL验证日志_2026-09-13_并行组内排序候选与资源折中.md`；最终证据：
  `experiments/shared_pe/validation_20260913_parallel_sort_final_n32/dma_matrix`及`sorter_ablation_v2`。

## 2026-09-13：四上下文深度预处理与异常排空

- 深度预处理默认四上下文环形缓冲，三MAC连续发射及有序退休；共享PE仍只有一个，固定
  Gaussian-wise主路径和动态G/P/R/E控制不变。1/3/4-context消融各324组对拍及972次P grant通过。
- 64-Gaussian连续流384→195 cycles（4相对1-context，模块吞吐1.969×，非整帧加速比）。
- 修复空帧/晚到DMA错误结束早于prepass排空的P所有权切换风险；帧级7周期、生产DMA9周期
  等待排空、有效前缀渲染及后续帧恢复通过。
- 最终72项真实DMA图像与上一轮逐项等价，24/24主共享周期改善；相对旁路平均退化
  7.324667%→3.166617%、最大13.882163%→6.376110%，仍NOT PASS，不升级Gate 1。
- 微负载主共享/旁路/prepass-only为621/602/610 cycles；Python122项、Icarus70项+综合入口、
  Verilator生产顶层lint通过。下一步并行排序服务候选及单PE collect资源折中，不先调建议器。
- 详细记录：`docs/RTL验证日志_2026-09-13_多上下文预处理与异常排空.md`；最终证据：
  `experiments/shared_pe/validation_20260913_queued_prepass_final_n32`。

## 2026-09-13：主投影XYZ共享PE与真实G/P竞争

- 主投影XYZ相机变换移到lane分发前，三轴交错通过同一P客户端发射9次MAC；lane使用已经
  变换的mean，协方差旋转、SH和Gaussian内部8×8遍历不变。共享适配器busy纳入安全epoch排空。
- prepass依赖MAC和sort连续比较新增响应转发，仲裁失败时以相同操作数重试；旧路径及上一轮
  prepass-only配置均保留为参数化golden。
- 258组XYZ差分向量在随机G竞争、请求/响应停顿、配置变化和溢出域下全等；三场景×四模式×
  两种AXI时序×三种配置，共72项真实DMA输出哈希全等。24项主共享配置均有实际G/P竞争。
- Verilator展开证据：默认四lane本地`world_to_camera_core`实例由4变0，共享XYZ适配器1个、
  共享PE1个；移除主mean链36个乘法操作，但不代表面积/功耗收益已经签核。
- 功能PASS，性能NOT PASS：微负载630/602 cycles（+4.651163%）；n32矩阵共享相对旁路
  平均+7.324667%、最大+13.882163%。主要瓶颈是串行prepass和compare，而不是新主XYZ本身。
- Gate 1仍PARTIAL，R未接入、PPA未完成；下一轮优先恢复G/P吞吐，不先调自动建议器。
- Python119/119、Icarus70项自检+综合入口、Verilator生产顶层lint全部PASS。
- 详细记录：`docs/RTL验证日志_2026-09-13_主投影共享PE与真实竞争.md`；产物位于
  `experiments/shared_pe/validation_20260913_projection_n32`。

## 2026-09-12：共享PE首次接入生产G/P数据流

- `gaussian_frame_render_pipeline`默认启用单一共享compare/MAC实例；稳定组内排序的三级键比较
  走G客户端，mean-only深度预处理的三项相机Z点积走P客户端，既定Gaussian-wise主路径不变。
- mode table的weight/owner/aggressive gate及epoch提交已接入；系统累计G/P/R grant、stall和
  utilization，并通过APB `0x064–0x07c`读回。
- 新增两项旧/新路径差分测试，覆盖稳定tie、随机反压、旋转/平移和溢出；生产帧级测试确认
  G grant非零、4个Gaussian产生12次P grant，系统APB测试确认1个Gaussian产生3次P grant。
- 真实DMA微负载共享路径627 cycles，旁路golden 602 cycles；68 commits及68次state读写完全
  一致。当前功能PASS，但25 cycles/4.152824%开销必须在后续流水化中消除。
- Gate 1仍为PARTIAL：主投影与光栅客户端尚未接入，G/P当前不重叠，weight仲裁尚未在生产
  竞争负载中体现吞吐差异；不能据此宣称统一PE池或PPA收益。
- 回归：Python 113/113、Icarus 68项自检+1项综合入口、Verilator生产顶层和新增排序适配器
  lint全部PASS。详细记录见`docs/RTL验证日志_2026-09-12_共享PE生产接入.md`。

## 2026-09-12：Gate 0事实基线与首个共享compare/MAC PE切片

- 新增机器可读的 `verification/implementation_status.json` 和5项状态合同测试，锁定唯一
  生产顶层、camera DMA缺口、软件全局预排序、自动策略未过性能验收、GT/PPA未签核等事实。
- 新增一个真实物理 `shared_reconfigurable_pe_slice`：G/P/R共享单套稳定键compare/有符号
  MAC数据通路，weight控制credit，owner控制优先起点，并输出grant/stall/utilization。
- 补充安全重配置输入：只允许响应排空后清空旧模式credit；E模式以clock-enable边界表达
  aggressive gating，不直接门控测试时钟。
- 当前状态严格标为“共享PE切片已实现、生产主链集成未完成”，没有提前宣称跨阶段复用PASS。
- 回归：Python 113/113、Icarus 65项自检+1项综合入口、Verilator顶层和新增PE独立lint
  全部PASS；生产真实微负载仍为602 cycles、68 commits。
- 详细记录：`docs/RTL验证日志_2026-09-12_Gate0与共享PE切片.md`。

## 2026-09-11：当前实现全量审计与规划修订

- 新增 `docs/当前实现全量审计与修订开发规划_2026-09-11.md`，按 PASS、PARTIAL、
  NOT IMPLEMENTED、BLOCKED 重新核对开题目标、RTL 实际连线、验证覆盖、质量与 PPA 证据。
- 固定 Gaussian-wise 主路径、小分辨率完整帧、continuation/checkpoint 和功能回归成立；
  并行排序、跨阶段 PE 物理复用、硬件自主全局分批/排序、完整形状感知、参数压缩、GT 画质
  和 PPA 尚未完成。
- 13 场景自动矩阵只判为“正确性/安全切换 PASS、策略性能 NOT PASS”：exact 0/13，
  within 1% 为 12/13，不能作为自动调度通过。
- 当前源码复跑：Python 108/108、Icarus 64 个自检 + 1 次综合入口、Verilator 顶层 lint
  均 PASS；lint 仍有既有非致命告警，签核级验证只算 PARTIAL。
- 开发顺序修订为：事实基线 → 真实共享 PE → 并行排序/输入责任边界 → 形状剪枝消融 →
  自动策略重标定 → 完整 IO/GT 画质 → PPA。下一轮不继续拟合当前尚无物理收益的建议器。

## 2026-09-11：13 场景固定/自动模式真实标定矩阵（功能 PASS；策略性能 NOT PASS）

- 新增 `scripts/run_real_mode_calibration_matrix.py`，对每个场景运行固定 G/P/R/E 及自动
  双帧探针；固定模式按完整 framebuffer 哈希签核，自动模式由 RTL 内部逐像素比较 RGB/T。
- 自动探针现同时支持 global-GID 稀疏属性和帧内连续 dense 属性布局。
- 13 个真实场景、不同相机索引、每场景 32 Gaussian：固定 oracle 均为 G；自动模式 12 次
  推荐 R，garden 因只有 4 个完整窗口而没有推荐并保持 E。
- 自动所选模式精确命中 oracle 为 0/13，但 12/13 距最优小于 1%；平均 gap 0.573828%，
  最大 gap 3.147700%。四固定模式输出及全部自动双帧 RGB/T 等价性均 PASS。
- 结果证明按 busy-cycle 分类与现有 lane mask 的真实性能收益尚不匹配，因此不据此硬调分数；
  下一轮先把 weight/shared-math owner 接入真实共享算术服务路径，再重新标定策略。
- Python 108 项、Icarus 64 项加综合编译、Verilator lint 全部 PASS。
- 报告位于 `experiments/real_mode_calibration/validation_20260911_13scenes_n32`；详细过程见
  `docs/RTL验证日志_2026-09-09_开发恢复与完整帧续跑.md` 第 14 节。

## 2026-09-11：Bonsai 真实自动模式 observe→safe-select

- 真实 DMA 测试新增双帧自动探针：第一帧观察并保存推荐/RGB/T，第二帧只在新 epoch
  安全提交推荐，随后逐像素比较两帧输出；新增逐窗口结构化日志。
- 新增 `scripts/run_real_auto_mode_probe.py`，输出 JSON、CSV、Verilator 原始日志和帧状态，
  并自包含配置 MSYS2 UCRT64 动态库 PATH。
- Bonsai batch 0 从 E 观察帧 494,527 cycles 自动推荐 G；下一帧确实切为 G，492,827
  cycles，减少 1,700 cycles（0.343763%），RGB/T 差异为 0，PASS。
- 观察帧 1,931 个窗口中 G/P/R/E winner 为 116/2/1,769/44，但窗口 11 已锁存 G；这证明
  当前首未决队列安全语义，也暴露了早期阶段瞬态偏置，不能宣称策略已最优。
- Python 107 项、Icarus 64 项加综合编译、Verilator lint 全部 PASS；全帧 EXE SHA-256 为
  `3C0582C47ABD2660A4AA4BD0B989D3F64A7086689397458850DED9D737B31523`。
- 产物位于
  `experiments/full_frame_batches/bonsai_cam_mid_d64_c256/validation_20260911_real_auto_probe`；
  下一步建立多 batch/多视角固定 G/P/R/E 与自动模式标定矩阵，再调整决策聚合策略。
- 详细过程见 `docs/RTL验证日志_2026-09-09_开发恢复与完整帧续跑.md` 第 13 节。

## 2026-09-10：建议器原子遥测与五类长窗口矩阵

- `gaussian_mode_advisor` 在每个完整窗口原子保存窗口编号和六项事件计数；APB新增
  `0x048–0x060`，软件可用双读窗口编号获得一致快照。
- 新增G/P/R/E/均衡五类、每类三个64-cycle窗口的策略矩阵；四个瓶颈类分别稳定推荐
  G/P/R/E，均衡类保留G且不产生切换请求，PASS。
- 自动报告脚本输出JSON、CSV和原始Icarus日志，产物位于
  `experiments/mode_advisor_matrix/validation_20260910_round1`。
- Python 106项、Icarus 64项加1次综合编译、Verilator lint全部PASS。重建全帧模型后，
  Bonsai batch 0固定E仍为494,527 cycles、275,153 commits，frame SHA-256保持
  `7C999FFBCB9A06D190DE652913F726EA4FDB45BEEB78A8D3FC67F07B73260001`。
- 本轮证明事件分类和可解释性接口成立；下一轮才进入真实多批/多视角自动模式收益校准，
  不能用合成矩阵替代真实性能结论。
- 详细过程见 `docs/RTL验证日志_2026-09-09_开发恢复与完整帧续跑.md` 第12节。

## 2026-09-10：自动 G/P/R/E 建议器顶层闭环

- 新建 `docs/3DGS动态可重构硬件加速器_最终目标与验收基线.md`，固化最终目标、主路径、
  约束、分阶段验收条件和开发顺序。
- 建议器已接收真实 group/sort/projection/raster/block/termination 事件，并只在帧计算期
  采样；APB 新增 `0x044 AUTO_MODE`，支持自动使能和推荐、窗口胜者、未决状态读取。
- 顶层只保留一个未决推荐；推荐复用 runtime shadow/commit 路径，仅在下一新帧安全 epoch
  边界提交，continuation 不会中途改模式；关闭自动模式时恢复软件 shadow 配置。
- Python 105 项、Icarus 63 项加 1 次综合编译、Verilator lint 均 PASS。重建后的全帧
  EXE SHA-256 为 `B22C9FA16E24FCB3F036B84D0FCBCA706F02B2E9DF6CDC7A4A922A0B86F777F7`。
- 自动模式默认关闭的 bonsai batch 0 固定 E 复验得到 494,527 cycles、275,153 commits，
  帧 SHA-256 仍为 `7C999FFBCB9A06D190DE652913F726EA4FDB45BEEB78A8D3FC67F07B73260001`。
- 当前只完成控制闭环，尚不能称为物理 PE 复用；下一步是四类长负载策略校准，再接共享
  数学资源 owner、权重和时钟使能边界。
- 详细过程见 `docs/RTL验证日志_2026-09-09_开发恢复与完整帧续跑.md` 第 11 节。

## 2026-09-09：G/P/R/E 分组/排序服务率接入

- 新增 `group_sort_service_gate` 并接在 `depth_group_buffer` 与
  `stable_group_sorter` 之间；只改变服务节拍，不改变 depth/gid/seq/payload，主路径仍为
  深度分组、Gaussian 有序发射/退休、Gaussian 内部 8×8 block 遍历。
- 4-lane 下 G/P/R/E 的 group active 为 4/2/2/1；定向 8-cycle 测试分别接收
  8/4/4/2 个记录（P、R 同为 active=2），反压稳定性和 active=0 均 PASS。
- bonsai batch 0 四模式真实负载的 group stall 分别为 0/1,022/1,022/3,069；
  四者 275,153 commits、inactive-lane issue 全零，帧状态逐字节一致，SHA-256 均为
  `7C999FFBCB9A06D190DE652913F726EA4FDB45BEEB78A8D3FC67F07B73260001`。
- Python 104 项、Icarus 63 项加 1 次综合编译、Verilator lint 和四次真实负载均 PASS。
- 详细过程见 `docs/RTL验证日志_2026-09-09_开发恢复与完整帧续跑.md` 第 10 节。

## 2026-09-09：完整帧 checkpoint 续跑闭环

- 修复最终协方差测试平台的 Q20.20/Q27.8 格式漂移；Python 103 项、Icarus 62 项加
  1 次综合编译、Verilator lint 均通过。
- 最终 Verilator 模型已从当前源码真实重建，EXE SHA-256 为
  `55E8CBE2922D8593CE0D83D237A8C9A808B6627C90E62FA00B42FC2A6447536B`。
- 新增 checkpoint 终止 sidecar 重建及自动等价性脚本；batch 0–3 连续运行与在
  batch 1 后恢复运行字节级一致，最终状态 SHA-256 为
  `43773B8EB1EC0005870C2D428F2AEBE0466FA052A2603F03D9C06B32D26EC6BC`。
- 当前源码重新完成 1,030 批、1,051,092 Gaussian 单进程完整帧：30,067,089 cycles、
  868,247 commits、2,752 state misses，inactive-lane issue 全零，耗时约 34.24 分钟；
  frame SHA-256 为
  `E8193C162E8BFD9DC743E41FE1556A93AE3984685386EF7C06E85E5F2BFB1ED6`，PASS。
- 详细过程见 `docs/RTL验证日志_2026-09-09_开发恢复与完整帧续跑.md`。

## 2026-08-16：真实三批与可恢复执行

- Python/NumPy 规范生成器已改为 global-GID 稀疏 PLY 索引，单批从约 5 分钟降至约 0.205 秒，输出逐 bit 不变。
- 标准库 C++ 生成器因不同 `expf` 数学库在量化边界存在 LSB 差异，明确不得作为 RTL 签核输入。
- 真实 1024+1023 两批 continuation PASS：831,320 cycles、337,329 commits、epoch=1，frame SHA-256 `31EC81479A6A25869BAECB42CC2FDA8659C94F1E219944643B90BBC06E18C257`。
- 新增任意批数范围执行和 `STATE_IN` framebuffer checkpoint。真实 1024+1023+1022 三批 PASS：1,142,017 cycles、357,933 commits、epoch=1，frame SHA-256 `B01FD985DBB065F1D9BC323000A9619B95CA05A51816FE142D97DF491AC6DDEA`。
- Python 103项、Icarus 两批/三批/checkpoint、Verilator 默认和1024/4×4 build/真实执行均PASS。
- 详细记录：`docs/RTL验证日志_2026-08-16_真实三批与可恢复执行.md`。
- 后续已完成32批、128批和完整1,030批连续Verilator。完整1,051,092颗、30,239,614 cycles、922,605 commits、epoch=1、walltime约26.2分钟，frame SHA-256 `1632496F6AEB0AD472D200F78D0FF3868C7D3934EFCE9ED3B6D3142118D585F5`，协议与计数PASS。
- 当时的质量结论：完整PNG近似灰色且首批即T≈0；独立浮点模型在同一64×43/前1024颗也复现了全屏终止和低细节，说明低分辨率巨大footprint是主因之一。当时RTL对内部浮点参考为PSNR 18.222 dB、SSIM 0.884；该定点偏差后来已在投影格式收敛中修复为47.0279 dB/0.990241（见本日志后续条目）。两组数值都禁止冒充ground-truth质量。

## 2026-08-04：接入 Icarus Verilog 12

### 本地环境

- 操作系统：Windows。
- 工具位置：`D:\IcarusVerilog\iverilog`。
- 已验证可执行文件：`bin\iverilog.exe`、`bin\vvp.exe`。
- 版本：Icarus Verilog 12.0 (devel)，版本标识
  `s20150603-1539-g2693dd32b`。
- 项目文件和验证结果均在本机处理，未上传网络。

### 首次真实 RTL 编译

- 编译标准：SystemVerilog 2012（`-g2012`）。
- 编译顶层：`gs_accel_top`。
- 当前编译范围：16 个 `.sv` 模块，约 1501 行 RTL；这是目前的控制/光栅
  子集，并非最终完整加速器。
- 结果：定义 `SYNTHESIS`、排除仿真断言后，顶层解析和展开通过，退出码为 0。

### 已发现并修正的问题

1. `apb_regfile.sv` 使用 `inside` 地址集合判断，而 Icarus 12 尚不支持该
   表达式。改为逻辑等价的显式地址比较，保持 APB 行为不变，也更容易被不同
   仿真器和综合器接受。
2. `raster_pair_shell.sv` 的 `commit_epoch_id_o` 同时由元数据拆包和
   `blend_state_commit` 输出驱动。保留后者作为有效提交 epoch，元数据中的副本
   改接内部未使用信号，从而消除多驱动。
3. `pixel_termination_mask` 的禁用查询端口原先连接无尺寸 `'0`，Icarus 将其
   识别为 1 位并给出位宽扩展警告。改为按 `BLOCK_W` 和 `EPOCH_W` 显式构造
   全零向量。

### 仿真验证

- 新增 `tb_cfg_epoch_ctrl.sv`，覆盖复位、shadow 配置写入、安全点提交、挂起
  提交、同周期写入并提交、重复提交 overrun 六类行为。
- 新增 `run_iverilog.cmd`，一次执行完成顶层编译和控制模块冒烟仿真。
- 实际结果：`PASS: tb_cfg_epoch_ctrl`；总入口报告
  `PASS: Icarus Verilog compile and smoke simulation`。
- 公司 Windows 策略禁止直接执行 PowerShell 脚本，因此验证入口采用普通
  `.cmd` 文件，未修改也未绕过系统执行策略。

### 工具限制与后续事项

- Icarus 12 对项目现有完整 SVA 并发断言支持不全。因此 Icarus 回归暂用
  `SYNTHESIS` 宏排除 SVA；断言源码仍保留，待 Verilator 或商业验证工具继续
  检查。不能把本次通过解释为 SVA 已通过。
- `always_comb` 常量选择及 `unique case` 仍有 Icarus 能力提示，但不阻止当前
  编译和仿真；后续用 Verilator 交叉 lint。
- 当前系统没有可用的本地 Python 解释器，所以本轮未重跑原有 74 项 Python
  回归。此前的通过记录不变，但本次 RTL 修改仍需在 Python 环境恢复后复验。
- 下一步依次增加 APB、alpha、blend、图像状态、终止表和
  `raster_pair_shell` 的位精确、自检查 testbench 及随机背压验证。

### 可重复执行

在 Windows 命令提示符运行：

```text
D:\3DGS\verification\rtl\run_iverilog.cmd
```

## 2026-08-04：第一轮模块级与光栅端到端 RTL 验证

### 回归规模与结论

- 顶层 `gs_accel_top` 控制/光栅子集继续使用 SystemVerilog 2012 完整编译，
  解析和展开通过。
- 新增7个自检查 testbench；连同已有 `tb_cfg_epoch_ctrl`，当前共8个
  SystemVerilog 仿真用例。
- `run_iverilog.cmd` 已升级为9步回归：1步顶层编译、8步自检查仿真。
- 2026-08-04 本机实测结果：8个仿真全部输出 `PASS`，总入口退出码为0。

### 本轮覆盖范围

1. `cfg_epoch_ctrl`：shadow/active 分离、安全epoch边界、挂起提交、同周期
   写入提交和重复提交 overrun。
2. `apb_regfile`：64位基址拆分读写、图像尺寸、字节选通、单周期控制脉冲、
   mode提交、状态字段和未知地址 `PSLVERR`。
3. `alpha_block_float_core`：中心点alpha、0.99饱和、阈值上下界、一个非零
   二次型LUT点、元数据保序和输出背压稳定性。
4. `blend_fixed_core`：前向定点blend、RGB饱和、透射率舍入、首次终止检测、
   已终止像素不重复报告，以及输出背压。
5. `image_state_store`：初始透明状态、更新命中、epoch逻辑清空、同周期
   写穿透和响应背压。
6. `pixel_termination_mask`：64位mask按位OR、首次全1脉冲、脉冲不重复、
   epoch隔离、容量碰撞、写穿透和响应背压。
7. `raster_termination_filter`：live/skip分流、epoch失配保守放行、完整tag防止
   容量碰撞误跳过、同周期更新查询写穿透和下游背压。
8. `raster_pair_shell`：alpha剪枝到提交、图像读改写、确定性伪随机提交背压、
   64个像素各两次高alpha累积终止、粗粒度块表更新、后续任务提前跳过和
   新epoch恢复。该用例完成128次终止形成提交，并检查任务、block、Gaussian、
   epoch和pixel标签沿全链路保持一致。

### 本轮发现并修正的 RTL 问题

- `STATUS`寄存器原拼接宽度为31位：`epoch_id_i`会被隐式补零后整体错位一位。
  已把保留字段从11位修正为12位，并将布局明确为：bit[31:16] epoch、bit3
  overrun、bit2 pending、bit1 done、bit0 busy。APB testbench已锁定该合同。

### 对失败的判定

- `image_state_store`测试初版曾在背压检查处失败。逐周期检查确认数据和valid
  均正确，失败原因是testbench改变组合输入后在同一仿真时间片立即采样
  `query_ready_o`。加入一个时间步等待组合逻辑稳定后通过，因此没有为该失败
  修改RTL功能。

### 当前边界

- 这些结果证明当前控制/光栅子集已经从“Python结构模拟”进入真实
  SystemVerilog编译与自检查仿真阶段，但不代表最终完整3DGS加速器已经完成。
- Icarus仍提示忽略 `unique case` 的唯一性语义，并对部分 `always_comb` 常量
  选择给出能力提示；本轮无编译错误。完整SVA和更严格的宽度/latch检查仍需
  Verilator交叉lint。
- 现阶段未验证的主要RTL仍包括投影、SH颜色、Gaussian到tile/bin任务生成、
  深度分组/排序、AXI4 DMA、高并发scoreboard、完整命令调度和中断错误路径。
- Windows当前仍没有可用Python解释器，因此本轮没有重跑Python模型回归；
  本轮新增RTL均通过独立Icarus自检查仿真。

## 2026-08-04：前端投影与tile任务数据通路第一轮

### 设计目标对齐

- 新增前端专用于3DGS：输出depth、屏幕均值、二维协方差、bbox和8×8 tile任务，
  直接服务后续排序、SH、Cholesky alpha编码和光栅，不实现无关通用图形功能。
- `camera_projection_tile_lane`为可复制单元，后续动态模式可在epoch边界改变启用
  lane数；固定和动态模式共享同一算术路径与描述符格式。

### 新增RTL

- `fixed_div_pipe2.sv`
- `world_to_camera_core.sv`
- `perspective_project_core.sv`
- `screen_covariance_core.sv`
- `bbox_tile_bounds_core.sv`
- `gaussian_tile_task_gen.sv`
- `camera_projection_tile_lane.sv`

RTL模块总数由16个增加到23个。

### 真实负载范围审计

- 使用本地13场景、每场景20000个Gaussian、首/中/末3视角、最长边1920的离线
  样本冻结首版定点格式。
- 极端屏幕均值约17.3万像素、极端半径约29.3万像素，证明窄屏幕坐标会溢出。
- 采用Q18.8宽屏幕坐标及溢出保守全屏策略，禁止因数值溢出错误剔除Gaussian。

### 新增SystemVerilog仿真

1. `tb_fixed_div_pipe2`：正负商、除零、正负饱和和流水背压。
2. `tb_projection_primitives`：世界到相机变换、透视均值和标签保持。
3. `tb_screen_covariance_core`：identity covariance解析点，验证JΣJᵀ和0.3正则化。
4. `tb_camera_projection_tile_lane`：均值/协方差fork-rejoin、保守bbox、row-major
   tile枚举、伪随机背压和near剔除。

全量回归现为13步：1步当前顶层子集编译、12个自检查仿真。2026-08-04本机
实测全部通过，退出码0；原74项Python unittest也使用本地捆绑Python重新运行并
全部通过。

### 当前未闭环部分

- quaternion/scale到3D covariance及view covariance旋转。
- opacity感知半径、2D covariance逆矩阵和Cholesky块浮点编码。
- projection lane到排序器、SH和现有raster链路的顶层连接。
- Verilator lint、SVA、ASIC综合与PPA仍未执行。

## 2026-08-04：前端数据通路第二轮——协方差生成、alpha描述符闭环

### 目标对齐

- 继续服务“面向3DGS渲染的动态可重构ASIC”主线；projection lane仍是可复制的
  固定算术单元，后续仅在epoch边界改变启用lane数量，不改变数值路径。
- 本轮没有扩展通用图形功能，集中补齐真实3DGS Gaussian从quaternion/scale到
  光栅alpha描述符之间的缺口。

### 真实范围审计与冻结格式

- 本地13场景、每场景30000个Gaussian、3视角审计结果：scale最大约3.02017，
  quaternion绝对值最大约0.999998，3D covariance绝对值最大约8.72054。
- conic对角最大约3.33332，非对角绝对值最大约1.66493；Cholesky因子绝对值
  最大约1.82572，factor shift范围约-14至-1，coordinate shift约0至8。
- 据此采用quaternion signed Q1.20、scale unsigned Q4.20、中间Cholesky Q4.20，
  最终输出与`alpha_block_float_core`一致的Q3.12因子及6位有符号指数。

### 新增与修改RTL

1. `quaternion_scale_covariance_core`：由归一化四元数和三轴scale计算
   `Sigma=R*diag(scale^2)*R^T`，输出世界空间Q24.16对称协方差。
2. `covariance_view_rotate_core`：计算`V*Sigma*V^T`，得到相机空间3D协方差。
3. `fixed_sqrt_pipe`：吞吐1事务/周期、全局背压的恢复式无符号整数平方根流水线。
4. `covariance2d_cholesky_encoder`：Q24.8二维协方差求逆，在Q4.40精度下形成
   conic，再以两次sqrt和一次divider生成PSD保持的Cholesky因子；同时生成
   factor/coordinate shift，并传播退化和数值溢出标志。
5. `opacity_radius_bound`：以1/4 sigma向上分档的opacity支持域，最大仍为3 sigma。
   `bbox_tile_bounds_core`使用向上取整的协方差平方根与半径，误差只会扩大任务范围，
   不会因LUT或sqrt向下量化漏渲染。
6. `camera_projection_tile_lane`：opacity随ready/valid元数据对齐；bbox之后串接
   Cholesky编码器，tile描述符现已携带光栅alpha核可直接消费的因子、指数和错误标志。

当前SystemVerilog RTL为28个模块、约3063行；自检查testbench为16个、约1447行。

### 新增验证与结果

- `tb_covariance3d_chain`：identity quaternion、scale=(1,2,3)和绕z轴90度view，
  验证世界协方差diag(1,4,9)变为相机协方差diag(4,1,9)。
- `tb_fixed_sqrt_pipe`：完全平方数、非完全平方数、最大32位输入、标签保持及背压。
- `tb_covariance2d_cholesky_encoder`：diag(4,9)解析点，验证逆矩阵、Cholesky、
  块浮点编码、opacity透传、背压和奇异矩阵错误完成。
- `tb_camera_projection_tile_lane`扩展为投影、bbox、alpha编码、tile枚举的闭环测试，
  并继续覆盖下游背压和near剔除。
- 一键Icarus回归现为16步：1步顶层子集编译、15个自检查仿真；本机全部PASS。
- 74项Python unittest重新运行，全部PASS。
- Icarus仍仅有已知兼容性提示；SVA保留在RTL中，待Verilator交叉检查。

### 当前边界与下一步

- 世界均值变换与世界协方差生成目前是分别验证的模块，尚未封装成从原始Gaussian
  输入到完整tile描述符的单一顶层lane。
- 仍需实现SH颜色、tile/bin缓存、深度排序、projection lane阵列和epoch级启停调度、
  AXI4 DMA及最终前端到`raster_pair_shell`的系统顶层连接。
- 本轮证明的是工艺无关RTL功能正确性，不代表已经获得ASIC时序、面积或功耗；
  这些必须在用户准备具体工艺库和综合工具后给出。

## 2026-08-04：前端数据通路第三轮——原始Gaussian闭环与动态lane阵列

### 本轮设计目标

- 把此前分别验证的世界均值变换、quaternion/scale协方差、view旋转、屏幕投影、
  bbox、Cholesky编码和tile生成串成单一原始Gaussian lane。
- 建立1/2/4 lane动态启用的工艺无关阵列，使“动态可重构”从架构设想进入可编译RTL。
- 保持固定基线和动态模式使用完全相同的lane、数值格式、相机配置和输出描述符。

### 新增RTL

1. `raw_gaussian_projection_lane`：输入世界坐标、归一化quaternion、scale和opacity；
   均值与协方差原子fork/rejoin后输出完整tile/alpha描述符。用16位在途计数器生成
   `idle`，支持多个Gaussian同时处于不同流水级。
2. `projection_lane_scheduler`：只向启用lane前缀轮询分发Gaussian；输出仲裁从一个
   Gaussian的first锁定到last，禁止多lane的tile序列交叉。禁用lane不参与idle归约。
3. `projection_epoch_lane_ctrl`：模式0/1/2映射1/2/4 lane，超出物理数量时钳位；
   复用`cfg_epoch_ctrl`，仅在epoch边界且阵列排空时提交模式。
4. `raw_gaussian_projection_array`：实例化物理lane、模式控制和调度器，形成可独立综合的
   动态投影前端子系统。模式0即固定单lane基线，动态方案仅改变启用副本数量。

当前工艺无关SystemVerilog RTL共32个模块、约3505行；自检查testbench共20个、
约1627行。

### 新增自检查验证

- `tb_raw_gaussian_projection_lane`：identity view、identity quaternion、单位scale解析点；
  从原始Gaussian生成4个正确tile，在背压下保持meta/first/last，并检查near剔除和idle。
- `tb_projection_lane_scheduler`：2/3/1 lane轮询分发、多lane同时有效、跨多task仲裁锁定、
  cull归约及禁用lane的idle屏蔽。
- `tb_projection_epoch_lane_ctrl`：阵列忙时模式提交保持pending，排空且epoch边界到达后
  从1 lane原子切换到4 lane，非法高模式钳位到物理lane数。
- `tb_raw_gaussian_projection_array`：两条完整lane并行处理两个Gaussian；验证每个Gaussian
  的4个tile保持连续，并验证处理中请求2->1 lane直到阵列排空才提交。

### 回归结果

- 一键Icarus回归扩展为20步：1步当前顶层子集编译、19个SystemVerilog自检查仿真；
  2026-08-04本机全部PASS，退出码0。
- 74项Python unittest全部PASS。
- 现有Icarus提示仍限于时间单位、`always_comb`常量选择和`unique case`支持差异；
  未出现新的编译或功能错误。

### 当前边界

- 动态投影子系统已独立闭环，但尚未接入系统`gs_accel_top`的数据DMA和排序/光栅路径。
- 目前模式由软件shadow/commit指定，尚未实现根据运行时计数器自动选择lane数的策略器；
  自动策略必须保持epoch低频切换，不能逐Gaussian抖动。
- 后续仍需SH颜色、tile/bin缓存、深度排序和前端描述符到光栅像素对生成。
- 多lane吞吐提升仍受单一输出任务口限制；后续需通过真实负载统计决定扩大任务口、
  增设队列或保持单口以节省面积。

## 2026-08-04：路线冻结——Gaussian-wise与动态可重构联合架构

### 用户确认的正式路线

主路径调整为GCC式“深度分组 + Gaussian有序发射 + Gaussian内部8×8块遍历”，
不再建设传统Gaussian–tile KV/bin和逐tile排序主路径。同时保留并强化本课题的
动态可重构目标，形成联合研究路线，而不是简单复现GCC。

### 联合创新主线

- Gaussian-wise数据流负责消除重复Gaussian属性加载、tile KV搬运和逐tile重复排序。
- epoch级动态重构负责应对不同场景、深度组和Gaussian尺寸造成的阶段负载不均衡。
- 初步模式定义为G（group/sort优先）、P（projection优先）、R（raster优先）和
  E（低功耗/强终止）；模式改变资源服务能力，不改变Gaussian深度顺序和数值结果。
- 可重构对象包括lane启停、共享算术时分复用、调度权重、固定总容量下的SRAM bank/
  队列份额，以及空闲资源时钟门控。
- 模式策略使用长窗口计数器、滞回和最短驻留时间，只在所有受影响状态排空的
  epoch边界提交。

### 对现有RTL的解释与影响

- 动态1/2/4 projection lane阵列继续保留，是P模式的第一批实现。
- 现有`gaussian_tile_task_gen`功能继续有效，但语义冻结为当前Gaussian内部的8×8
  block walker；其坐标字段暂不机械改名，以避免无意义接口破坏。
- projection多lane允许并行/乱序完成，但后续必须以sequence ID通过ordered retire，
  严格恢复前到后Gaussian顺序后才能进入blend。
- 不实现Gaussian–tile bin SRAM和逐tile sort单元。

### 文档变更

- 新增`架构决策记录_ADR-007.md`。
- 新增`系统规格_v0.9.md`。
- 新增`完整RTL交付分解_v0.2.md`。
- 修订动态投影前端和RTL注释，明确block walker语义。

### 下一批RTL优先级

1. depth/group/sequence描述符。
2. depth grouper与稳定组内sorter。
3. ordered issue/retire buffer并连接动态projection阵列。
4. G/P/R/E强制模式资源表与运行计数器。
5. SH和Gaussian block光栅闭环，随后实现自动模式建议器。
## 2026-08-04：Gaussian-wise深度顺序链与动态资源控制第一轮

### 本轮目标与架构对齐

- 沿正式路线实现“深度分组 + Gaussian有序发射/退休 + Gaussian内部8×8 block遍历”的顺序基础。
- 不新增Gaussian–tile KV/bin和逐tile排序路径。
- 把动态可重构扩展到G/P/R/E四种全流水级资源模式；模式只启停固定物理资源，不增加面积上限。

### 新增与修订RTL

1. depth_group_buffer：4个固定pivot深度组，组间近到远排放，容量溢出粘滞报告。
2. stable_group_sorter：以(depth,GID,sequence)执行有限窗口稳定排序。
3. gaussian_depth_prepass_core：仅读取世界均值计算view-space Z，完成near/far判断并分配逐帧sequence；修复frame_start与首条输入同周期时序号必须为0的边界。
4. ordered_gaussian_retire：允许多lane乱序完成，但仅队头Gaussian可向blend退休；一颗Gaussian的block流保持连续；cull使用单条空事件；非法first/last/cull格式设置粘滞错误。
5. gaussian_resource_mode_table：实现G/P/R/E强制资源表，输出group/projection/SH/raster启用lane数、调度权重、共享算术优先归属和强门控指示。
6. gaussian_pipeline_event_counters：记录group接收/溢出、sort和projection忙周期、block候选/终止跳过、alpha、blend、有序退休等待和模式切换共10类事件。

### 新增自检查仿真

- tb_depth_group_sort_chain：乱序输入、4组粗分组、同深度GID确定性顺序及随机背压。
- tb_gaussian_depth_prepass_core：identity Z、平移、near/far剔除、sequence、同周期frame start、饱和溢出及背压稳定。
- tb_ordered_gaussian_retire：issue顺序10/11/12、11先完成不得越序、10的多block连续退休、12的cull退休、输出背压、occupancy和wait事件。
- tb_gaussian_resource_control：G/P/R/E表项、固定物理上限、事件映射、快照与清零。

### 验证结果

- 三个本轮新模块测试和此前新增的深度分组/排序链测试均独立通过。
- 一键Icarus入口扩展为24步：1步顶层综合子集编译、23个SystemVerilog自检查仿真。
- 2026-08-04本机执行完整一键回归，23个SystemVerilog自检查仿真全部PASS，入口退出码为0。
- 使用本地Python运行74项模型与工作负载unittest，全部PASS。
- Icarus对always_comb常量选择的提示仍属于已知兼容性提示；未因提示修改正确的组合逻辑。
- 详细接口合同冻结在Gaussian深度分组与有序退休规格_v0.1.md。

### 当前边界和下一步

- 当前模式表是软件/测试强制模式，尚未实现基于长窗口计数器、滞回和最短驻留的自动建议器。
- ordered-retire已作为独立模块验证，尚未与raw projection array和raster顶层数据端口完全封装。
- SH颜色计算、Gaussian block到64像素对生成，以及完整帧输出/图像质量闭环仍待实现。
- 具体工艺节点的PPA仍须等待标准单元库和ASIC综合环境。
## 2026-08-04：有序Projection集成与自动模式建议器

### 架构问题与修正

- 审查发现原projection阵列先按完成时间集中仲裁，再计划在单一输出后做ordered retire，这无法恢复丢失的lane身份；原cull又只有无标签脉冲，无法确认对应sequence。
- 将ordered retire移到lane输出汇合点，直接观察所有lane的带标签完成流。排序发射和issue FIFO写入成为原子事务。
- cull改为携带完整描述符和sequence的单拍ready/valid事件，格式为first=last=culled=1，不再越过顺序控制。
- all_idle现在同时要求启用projection lane和ordered-retire FIFO排空，模式提交不会遗漏已发射但未退休的Gaussian。

### 新增与修改RTL

1. ordered_projection_lane_scheduler：动态lane轮询发射、原子issue、分布式乱序完成和严格有序退休。
2. gaussian_mode_advisor：长窗口G/P/R/E评分、分数裕量、连续窗口滞回、最短驻留和单未决推荐。
3. gaussian_tile_task_gen：cull升级为可背压、带描述符的退休事件。
4. camera_projection_tile_lane、raw_gaussian_projection_lane和raw_gaussian_projection_array：全链传播culled标签，并将有序调度器接入动态阵列。

### 新增验证

- tb_ordered_projection_lane_scheduler：验证年轻Gaussian先完成不得越序、较老Gaussian多block连续退休、输出背压、cull有序退休、FIFO占用与全局idle。
- tb_gaussian_mode_advisor：验证短期波动不会切换、最短驻留、连续窗口确认、推荐保持、握手和实际提交后重新计时，以及强终止E模式。
- 原raw lane、camera lane与array测试同步更新为带标签cull合同。

### 完整回归结果

- 一键Icarus回归扩展为26步：1步顶层综合子集编译和25个SystemVerilog自检查仿真，全部PASS，退出码0。
- 74项Python参考模型与工作负载测试全部PASS。
- 当前工艺无关SystemVerilog RTL为40个文件、约3924行；testbench为26个、约1830行。
- Icarus输出仍只有已知的时间单位、always_comb常量选择和unique case兼容性提示。

### 下一阶段

- 加入SH颜色计算及描述符格式。
- 将有序8×8 block输出连接64像素对生成、alpha、blend和termination链。
- 用13个真实场景校准模式建议器阈值、窗口、滞回和驻留参数。
- ASIC工艺库准备后再执行综合、时序、面积和功耗分析。
## 2026-08-09：每Gaussian一次SH颜色与8×8 block逐像素光栅入口

### 路线对齐

- 本轮继续采用GCC式“深度分组 + Gaussian有序发射 + Gaussian内部8×8 block遍历”。
- 没有新增Gaussian–tile KV/bin、逐tile list或逐tile排序。
- SH只在每Gaussian计算一次，RGB随该Gaussian全部block/pixel复用；动态模式后续仅改变SH/raster lane启用数量，不改变算术和有序合同。

### 本地真实负载格式审计

- 新增`scripts/profile_sh_fixed_format.py`，只读取`D:/3DGS/data`中的13个场景，每场景最多抽样100000个Gaussian。
- 结果保存到本地`experiments/sh_fixed_format_profile.json`：SH系数绝对值最大约7.79183，degree-3基函数绝对值最大约0.74635，裁剪前颜色范围约-0.529至3.087。
- 据此冻结首版SH系数signed Q5.12、方向signed Q1.20、32位Q20基函数、64位Q32 MAC和RGB unsigned Q1.12。

### 新增与修正RTL

1. `view_direction_normalizer`：Q16世界视线归一化，零向量回退到(0,0,1)。修正了分子在扩宽前左移导致的潜在截断。
2. `sh_degree3_color_core`：与Python参考顺序一致的16项degree-3实SH、三通道宽MAC、0.5偏置与0..4096裁剪。
3. `gaussian_sh_color_core`：世界坐标差先扩宽一位；fallback标志随SH结果metadata对齐，不再错误地取归一化器当前拍状态。
4. `gaussian_block_pixel_expander`：row-major遍历当前Gaussian的8×8 block，执行bbox/整图边界mask，产生Q5.10像素差与32位线性pixel ID。
5. `ordered_block_raster_frontend`：把已有序的block与每Gaussian缓存RGB接入现有termination、alpha、blend链；保持无tile bin语义。

收口审查进一步修正了像素整数坐标扩宽前左移的潜在Q8截断，并增加30000×20000量级坐标用例锁定该合同。

### 新增自检查测试

- `tb_view_direction_normalizer`：覆盖(3,4,0)、负Z、零向量、metadata和背压稳定。
- `tb_sh_degree3_color_core`：覆盖DC、一次SH符号、上下裁剪和背压。
- `tb_gaussian_sh_color_core`：覆盖相机平移、零视线fallback及最终标志对齐。
- `tb_gaussian_block_pixel_expander`：覆盖bbox裁剪、图像裁剪、row-major地址、pixel-in-block、dx/dy、空block/cull和随机式背压。
- `tb_ordered_block_raster_frontend`：覆盖单个有序block从pixel展开贯通termination、alpha和blend提交，以及culled退休。

### 全量结果

- 一键Icarus入口扩展为31步：1步当前`gs_accel_top`子集编译，30个自检查SystemVerilog仿真全部PASS，退出码0。
- Python参考/定点模型74项unittest全部PASS，耗时约4.4秒。
- 当前共有45个SystemVerilog RTL文件、约4288行；31个testbench、约1985行。
- Icarus输出仍是已知的时间单位、`always_comb`常量选择和`unique case`兼容性提示，无新增编译或功能失败。

### 当前边界与下一步

- 本轮闭合了SH模块和“有序block到现有光栅后端”的子链，但系统级`gs_accel_top`仍未把完整属性存储、排序、projection、SH、block和DMA串成整帧主链。
- 下一步应实现排序后完整Gaussian属性缓存与projection/SH原子fork/join，使SH颜色按sequence与projection descriptor汇合，再接入本轮光栅前端。
- 随后把SH/raster实际lane启停接到G/P/R/E模式和epoch提交，完成动态模式与固定基线的位精确等价验证。
- 完整RTL、整图PSNR/SSIM/LPIPS和具体工艺节点PPA仍未完成，不得用本轮模块PASS替代最终验收。

## 2026-08-09：完整Gaussian属性原子fork、Projection-SH有序汇合与光栅贯通

### 路线对齐

- 完整属性事务从排序后的Gaussian开始，同时携带`epoch/GID/sequence`、世界均值、quaternion、scale、opacity和48个SH系数。
- projection与SH支路通过等深FIFO原子fork；两支路可以独立背压，但一次源握手不会只写入一个支路。
- 多projection lane继续允许乱序完成，先由既有ordered-retire恢复Gaussian顺序，再与按输入顺序完成的SH颜色汇合。
- 一个SH结果保持到该Gaussian的last block被下游接受，继续满足“每Gaussian一次SH、内部8×8 block遍历”，未建立tile bin或逐tile排序。

### 新增RTL

1. `rv_fifo`：小容量可综合ready/valid FIFO，数据阵列无复位赋值。
2. `gaussian_projection_sh_fork`：完整Gaussian属性到projection/SH的原子双FIFO fork。
3. `ordered_projection_sh_join`：比较完整`epoch/GID/sequence`，颜色跨当前Gaussian全部block复用，last/cull才弹出。
4. `gaussian_projection_sh_array`：封装动态projection阵列、一次SH和有序汇合；mode pending期间停止接收新Gaussian。
5. `ordered_gaussian_block_decoder`：集中冻结projection描述符到raster字段的位布局。
6. `gaussian_ordered_render_frontend`：从排序后完整Gaussian贯通projection、SH、block、pixel、alpha、blend和termination。
7. `raster_pair_shell`增加精确的在途事务计数与`idle_o`，使epoch提交不会把alpha/blend流水中的旧任务误判为空。

### 新增验证

- `tb_gaussian_projection_sh_fork`：projection快/SH慢和反向背压、FIFO满、顺序与排空。
- `tb_ordered_projection_sh_join`：一个颜色跨三个block复用、last弹出、下一Gaussian cull和输出背压。
- `tb_gaussian_projection_sh_array`：双projection lane处理两个Gaussian；每个四个block，分别使用DC与+Z一次SH颜色，输出仍严格保持Gaussian顺序。
- `tb_gaussian_ordered_render_frontend`：一个解析Gaussian生成4个内部block和225个bbox有效像素，贯通alpha/blend提交；全部GID/sequence/epoch保持，SH颜色比例不丢失。
- 完整链测试同时在Gaussian处理中请求模式切换，确认commit保持pending，直到最后一个pixel提交、所有前后端状态排空后才更新epoch。

### 回归结果

- 一键Icarus入口增加4项测试；目前34个SystemVerilog自检查仿真全部PASS，退出码0。
- Python参考/定点模型74项unittest全部PASS。
- 当前共有51个SystemVerilog RTL文件、约4660行；35个testbench、约2127行。
- Icarus仍只有已知时间单位、`always_comb`常量选择和`unique case`兼容提示，无新增功能失败。

### 当前边界

- 当前系统前端从“排序后的完整Gaussian属性流”开始，尚未实现从深度排序结果读取完整属性的SRAM/DMA接口。
- G/P/R/E模式目前真实控制projection lane数量；SH和raster仍各为单个物理算术路径，模式表中的SH/R lane数量尚未落到实际阵列启停。
- `gs_accel_top`仍是早期控制/光栅接口子集，尚未替换为包含DMA、命令、中断、属性读取和整帧写回的最终顶层。
- 整图PSNR/SSIM/LPIPS与具体工艺PPA仍待后续闭环。
## 2026-08-09：排序后完整 Gaussian 属性 SRAM 读取与渲染主链闭环

### 路线对齐

- 排序输出仍只携带 `depth/GID/sequence/group`，不复制完整 Gaussian 属性。
- 每个有序 Gaussian 按 GID 读取一次完整属性，随后由 projection、每 Gaussian 一次 SH 和 Gaussian 内部全部 8×8 block/pixel 复用。
- 没有引入 Gaussian–tile KV/bin、per-tile Gaussian list 或 per-tile 排序。
- 动态重构仍是主设计目标：模式请求立即冻结新的排序发射，排空已接受的属性读取，再排空 projection/SH/block/pixel/alpha/blend 后原子提交 epoch。

### 新增 RTL

1. `gaussian_attribute_store`：完整属性逻辑存储，分为 254-bit geometry bank 和 864-bit SH appearance bank；采用 frame-local dense GID，有效位独立管理，一周期读延迟。
2. `ordered_gaussian_attribute_issue`：把排序后的元数据与 SRAM 响应严格对齐；单 outstanding 正确性基线支持 ready/valid 背压。
3. `gaussian_sorted_render_pipeline`：从排序结果、属性读取贯通到既有 ordered projection/SH/block/pixel/raster 前端；补齐属性 issue 与动态模式 commit 的安全排空层。

### 异常处理

- GID 超过属性深度时不截断为低位地址，设置越界 sticky error。
- 属性未加载时设置 unloaded sticky error。
- 两类错误项均被消费但不发射 SRAM 中的未定义属性；最终命令 FSM 应据此拒绝帧完成并产生错误状态/中断。
- 帧切换只清 valid 位，不复位宽 SRAM 数据阵列；ASIC 映射时可替换为目标工艺 SRAM 宏。

### 新增验证

- `tb_gaussian_attribute_store`：多地址写读、两个 bank 对齐、同址 write-through、valid 清空及三类非法访问。
- `tb_ordered_gaussian_attribute_issue`：GID 3→1→7 顺序、metadata 对齐、背压稳定、未加载和越界项抑制。
- `tb_gaussian_sorted_render_pipeline`：一个已排序 GID 只触发一次完整属性读取，产生 4 个内部 block 和 225 个有效 pixel commit；全部 GID/sequence/epoch 正确；渲染中模式请求直到全链排空才提交。

### 全量回归结果

- 一键 Icarus 回归共 37 个 SystemVerilog 自检查仿真，全部 PASS，退出码 0。
- Python 参考/定点模型 74 项 unittest 全部 PASS。
- 当前共有 54 个 SystemVerilog RTL 文件、约 5107 行；38 个 testbench、约 2401 行。
- Icarus 输出仍只有已知的 time unit、`always_comb` constant-select 和 `unique case` 兼容性提示，无新增编译或功能失败。

### 当前边界与下一步

- 当前完成的是“stable sorter 输出 → 按 GID 读一次属性 → 完整有序渲染前端”的闭环；深度分组/sorter 与该集成层尚未封成最终顶层命令链。
- 属性存储已有测试加载端口，AXI4 burst DMA、命令 FSM、中断、frame error 和整帧写回尚未实现。
- SH 与 raster 当前各为单物理算术路径；projection 已支持 1/2/4 lane。下一阶段优先设计 SH 多 lane 有序汇合，raster 多 lane 必须先冻结同像素 blend hazard/commit 机制，不能仅复制 lane 而破坏顺序。
- 13 场景整帧 RTL 输出、PSNR/SSIM/LPIPS 与具体工艺节点 PPA 仍待后续闭环。

## 2026-08-09：动态多 SH Lane、有序退休与 G/P/R/E 联合配置

### 路线对齐

- SH 仍然每 Gaussian 只计算一次，结果跨该 Gaussian 全部 8×8 block/pixel 复用。
- 多 SH lane 只提高 Gaussian 前端并行度；完成结果按 sequence 恢复有序后才与 projection 汇合，不改变 blend 次序。
- 没有引入 Gaussian–tile KV/bin、per-tile list 或 per-tile 排序。
- 动态重构从“主要控制 projection”推进到同时真实控制 projection 与 SH 两类物理 lane。

### 新增与修改 RTL

1. `ordered_sh_lane_scheduler`：round-robin 发射到启用 lane，issue order FIFO 与分布式 ordered retire 恢复 sequence 顺序，维护准确 outstanding/idle。
2. `gaussian_sh_color_array`：复制完整方向归一化与 degree-3 SH 定点路径，支持 1/2/4 lane active mask。
3. `gaussian_projection_sh_array`：用动态 SH array 替换单 SH core；SH idle、retire wait 和 protocol error 纳入全前端排空与错误合同。
4. `projection_epoch_lane_ctrl`：旧的 `1<<mode` 临时编码正式替换为共享 G/P/R/E 语义。G/P/R/E 下 projection 与 SH 均采用 half/all/half/1 lane，和中央资源表一致。
5. 完整渲染与排序集成层增加 `sh_active_mask` 状态观测端口。

### 新增验证

- `tb_ordered_sh_lane_scheduler`：四个人工不同延迟的 lane 强制乱序完成，仍按 sequence 1→2→3→4 输出；覆盖随机式背压、4→1 lane gating与排空。
- `tb_gaussian_sh_color_array`：真实4 lane定点SH计算多组DC/一次项系数，验证顺序、颜色和1/4 lane位精确等价。
- 扩展 `tb_gaussian_projection_sh_array`：P模式同时启用全部projection/SH lane，排空后原子切换到E模式的单projection/单SH lane；E模式继续产生正确epoch、颜色和四个block。
- 更新 projection epoch/array 测试以锁定共享G/P/R/E模式含义。

### 全量回归结果

- 一键 Icarus 回归共 39 个 SystemVerilog 自检查仿真，全部 PASS，退出码 0。
- Python 参考/定点模型 74 项 unittest 全部 PASS。
- 当前共有 56 个 SystemVerilog RTL 文件、约 5241 行；40 个 testbench、约 2493 行。
- Icarus 仍只有已知 time-unit、`always_comb` constant-select 和 `unique case` 兼容性提示，无新增功能失败。

### 当前边界与下一步

- Projection 和 SH 已成为实际可按 epoch 启停的物理阵列；G 与 sorter 并行度、R 与 alpha/blend 并行度仍未全部落地。
- 下一阶段不应直接复制 raster writer。先设计 pixel hazard scoreboard、同 pixel 前到后顺序保证、image-state bank 仲裁和有序 commit，再实现真实 R lane。
- AXI4 DMA、完整命令 FSM/中断/错误、最终顶层、13场景整帧画质与具体工艺PPA仍未完成。

## 2026-08-09：安全 Raster 多 Alpha Lane 与同像素有序状态提交

### 路线与正确性原则

- 主路径继续保持 GCC 式“深度分组 + Gaussian 有序发射 + Gaussian 内部 8×8 block 遍历”，未引入 Gaussian–tile KV/bin、per-tile list 或 per-tile 排序。
- R 模式真实控制 1/2/4 路 alpha 算术 lane；alpha 不读取图像状态，允许并行和乱序完成。
- 所有 alpha 结果按全局 pixel issue sequence 恢复顺序后，才进入唯一 blend/image-state 读改写口。
- 没有复制有状态 writer；有序退休加单提交口是当前正确性优先的保守 pixel hazard scoreboard。

### 新增与修改 RTL

1. 新增 `raster_alpha_lane_array`：运行时 active lane 数、round-robin 发射、sequence 携带、乱序完成和有序退休；输出 active mask、idle、retire wait 与 protocol error。
2. `raster_pair_shell`：在 live pixel 被 alpha 阵列接受时分配 32 位单调 sequence；多 alpha 阵列替换单 core；唯一 `blend_state_commit` 保持不变；在途计数和 alpha 排空共同定义 idle。
3. `ordered_block_raster_frontend`：透传 Raster lane 配置、active mask、排空和错误状态。
4. `gaussian_ordered_render_frontend`：由中央 G/P/R/E 资源表解出 Raster active lane 数，并把 Raster idle 纳入 epoch 安全提交条件。
5. `gaussian_sorted_render_pipeline`：向系统集成边界透传 Raster active mask。

### 新增与增强验证

- `tb_raster_alpha_lane_array`：4 路 alpha、8 个 opacity、输出背压、严格 sequence 顺序、4→1 lane gating 和单 lane 数值等价。
- `tb_raster_ordered_same_pixel`：四个 alpha=0.5 的任务连续命中同一像素，提交状态严格为 `(R,T)=(2048,32768)→(3072,16384)→(3584,8192)→(3840,4096)`；随后另一像素从 clear state 开始，验证同 pixel RAW 串行化与不同 pixel 状态隔离。
- 增强 `tb_gaussian_ordered_render_frontend` 为 4 个物理 lane：G 模式 projection/SH/Raster mask 均为 `0011`；繁忙时请求 R 模式保持 pending；225 个 pixel 全部提交并全链排空后，epoch 才递增且 Raster mask 原子切为 `1111`。

### 全量回归结果

- 一键 Icarus 回归：1 项当前 `gs_accel_top` 综合子集编译 + 41 个 SystemVerilog 自检查仿真，全部 PASS，退出码 0。
- Python 参考/定点模型：74 项 unittest 全部 PASS，约 4.7 秒。
- 当前共有 57 个 SystemVerilog RTL 文件、约 5162 行；42 个 testbench、约 2456 行（PowerShell `Measure-Object -Line` 口径）。
- Icarus 输出仍只有已知 time-unit、`always_comb` constant-select 和 `unique case` 支持提示；未出现新增编译或功能失败。

### 当前边界与下一步

- 当前已实现“真实多 alpha 算术 lane + 单一有序 blend/state 提交”，不能表述为多 blend lane 或多 image-state writer。
- G/P/R/E 已真实控制 projection、SH 与 Raster alpha 三类物理阵列；group/sorter 并行资源仍需后续进一步落地。
- 下一阶段优先补最终系统控制边界：深度分组/sorter 到完整渲染链的最终顶层、命令 FSM、frame/error/interrupt 合同；随后再接 AXI4 burst DMA 与整帧写回。
- 只有真实负载表明单状态提交口成为主要瓶颈后，才考虑 bank 化多状态端口；届时必须新增显式 pixel scoreboard、bank 冲突仲裁和位精确等价验证。
- 13 场景整帧 PSNR/SSIM/LPIPS 与具体工艺节点 PPA 尚未完成。

## 2026-08-09：帧级深度分组/排序到完整渲染数据通路闭环

### 本轮目标

- 把此前独立验证的 mean-only depth prepass、4组粗分组、组内稳定排序、按GID一次属性读取和完整Gaussian-wise渲染链封为帧级可综合顶层。
- 增加帧启动、epoch准备、输入关闭、全链排空、完成脉冲和sticky error合同。
- 保持动态可重构主线，不建立Gaussian–tile bin/list或逐tile排序路径。

### 新增RTL

新增 `gaussian_frame_render_pipeline.sv`，状态机为 `IDLE→PREP→COLLECT→DRAIN→IDLE`：

1. 每个合法帧启动先原子应用G/P/R/E模式并递增epoch；即使模式不变也递增，保证图像和终止状态跨帧逻辑清空。
2. 接收GID与世界均值，执行view-space Z、near/far可见性和逐帧sequence分配。
3. 可见Gaussian进入4组粗深度buffer，再按 `(depth,GID,sequence)` 做确定性组内稳定排序。
4. 排序结果按GID读取一次完整属性，进入已验证的projection/SH/block/pixel/alpha/blend链。
5. runtime模式建议在本帧只锁存，下一帧启动时与新epoch原子应用，避免冻结未排空sorter导致死锁或半帧切换。
6. frame done只在grouper、sorter、属性issue和完整渲染链全部排空后产生。

### 容量安全修正

- 系统pixel ID保持32位完整线性地址，image-state SRAM仍是参数化片上工作集。
- `STATE_ENTRIES`贯穿blend、raster、完整渲染和帧级顶层，默认4096项。
- 尚无外部backing store时，帧启动检查 `image_width×image_height<=STATE_ENTRIES`；超容量立即以错误位9完成，禁止低位地址别名后静默生成错误图像。
- 更新Python结构合同：要求image-state保留full pixel tag、`PIXEL_W>=INDEX_W`，同时要求帧控制器存在容量拒绝逻辑。

### 帧错误合同

错误位覆盖：depth数值溢出、group/sort容量溢出、属性读越界/未加载/写越界、ordered协议错误、模式overrun、busy重复start及image-state容量不足。下一次合法帧启动清零上一帧错误。

### 新增验证

- `tb_gaussian_frame_render_pipeline`：反序输入同深度GID 2→1，验证最终整帧提交严格为GID 1→2；两颗Gaussian各只读一次完整属性；覆盖提交背压。
- 同一测试连续运行两帧：第一帧内锁存E模式但不半帧切换；第二帧启动时E模式与epoch 2原子生效；逐像素结果与第一帧对应Gaussian的首次贡献一致，证明图像状态未跨epoch继承。
- `tb_gaussian_frame_error_control`：覆盖busy重复start、未加载属性被安全抑制且帧完成，以及65×64超过4096项时立即容量错误。

### 全量结果

- 一键Icarus入口：1项旧 `gs_accel_top` 综合子集编译 + 43个SystemVerilog自检查仿真，全部PASS，退出码0。
- Python参考/结构合同：74项unittest全部PASS，约4.6秒。
- Icarus仍只有已知time-unit、`always_comb` constant-select及`unique case`兼容提示，无新增功能失败。

### 当前边界与下一步

- `gaussian_frame_render_pipeline` 已闭合计算数据通路；旧 `gs_accel_top` 尚未替换，APB命令/中断和AXI4 DMA仍未闭合。
- 当前4096项image-state只适合小图/片上工作集验证；真实1080p必须加入tile cache与外部帧缓冲回写/回填，或映射足够容量SRAM。
- 下一阶段先用帧级计算顶层重构系统顶层命令/错误/中断合同，再实现AXI4 DMA和整帧写回。
- Verilator安装后补lint、非SYNTHESIS SVA与第二仿真器交叉验证；本轮不把Icarus PASS当作ASIC签核。

## 2026-08-09：APB帧命令、Sticky状态与IRQ系统控制顶层

### 目标与边界

- 用帧级完整计算链建立软件可见的START、busy、done、error和中断合同。
- 保留属性装载、mean/GID输入和像素提交为显式DMA缝隙；本轮不虚构AXI4事务或DRAM自主访问。
- 保持既定Gaussian-wise数据流和帧间epoch级动态重构。

### 新增与修改RTL

1. 新增 `gs_accel_system_top`：集成扩展APB寄存器、`gaussian_frame_render_pipeline`、sticky done/error、IRQ pending/enable和soft reset。
2. 扩展 `apb_regfile`：保留0x000–0x028地址，新增IRQ enable、10位error status与IRQ pending寄存器；CONTROL bit2清状态。
3. 正常帧设置done pending；错误帧同时设置done/error pending。IRQ enable只屏蔽外部电平，不丢失事件记录。
4. soft reset清计算核心及sticky状态，保留软件配置寄存器；同周期soft reset抑制START。
5. 更新旧 `gs_accel_top` 对扩展APB端口的兼容连接，旧顶层继续作为早期子集保留。

### 新增验证

- `tb_gs_accel_system_top` 通过真实APB写读启动一颗Gaussian的完整帧渲染，验证epoch、E模式、done sticky、done IRQ、IRQ_STATUS和CONTROL clear。
- 同一测试随后配置65×64超出4096项state容量，验证ERROR状态、容量错误位9、done/error双pending、外部IRQ及清除。
- 扩展 `tb_apb_regfile` 覆盖新地址、状态拼接、IRQ enable和status clear单周期脉冲。
- Python结构合同新增系统顶层、固定扩展地址、maskable IRQ与sticky错误锁存检查。

### 全量结果

- 一键Icarus入口：1项旧兼容 `gs_accel_top` 综合子集编译 + 44个SystemVerilog自检查仿真，全部PASS，退出码0。
- Python参考/结构合同共75项全部PASS，约4.5秒。
- Icarus仍只有已知time-unit、constant-select与unique-case兼容提示，无新增功能失败。

### 下一步

- 系统命令/状态/IRQ已闭环，下一阶段应冻结片外Gaussian属性布局和AXI4读写通道合同。
- 实现AXI4读DMA向属性装载与mean流供数，写DMA接收像素/帧结果；DMA response error必须进入现有frame error和error IRQ。
- 真实分辨率仍需image-state tile cache/backing store，不能用4096项小图验证替代1080p整帧支持。
## 2026-08-09：AXI4 mean/GID顺序读取DMA与系统级错误闭环

### 路线对齐

- 本轮只实现GCC式两遍访问的第一遍：按片外记录顺序读取GID和三维均值，直接进入深度预处理、4组粗分组和组内稳定排序。
- 排序后完整Gaussian仍按GID读取一次，随后执行Gaussian有序发射和Gaussian内部8×8 block遍历；没有引入Gaussian–tile bin/KV、per-tile list或per-tile排序。
- G/P/R/E动态可重构资源模式仍在帧/epoch边界原子生效；DMA不改变projection、SH、Raster lane的有序退休合同。

### 新增和修改RTL

1. 新增 `rtl/dma/axi4_gaussian_mean_read_dma.sv`：128-bit AXI4 INCR读、单outstanding、最大16拍、4 KiB边界拆分、下游背压holding register、RRESP/RID/RLAST检查。
2. mean记录固定16 Byte：32-bit GID + 3个27-bit有符号Q10.16世界坐标；整帧last由Gaussian count产生，不把burst RLAST误作frame last。
3. `apb_regfile`新增 `0x038 GAUSSIAN_COUNT`，ERROR_STATUS扩为16位。
4. `gs_accel_system_top`默认启用AXI mean DMA；保留参数化外部mean流仅作兼容验证。bit10记录AXI response/protocol错误，bit11记录配置/对齐错误。
5. `gaussian_frame_render_pipeline`和`depth_group_buffer`新增独立无数据结束事件。空帧、未对齐或AXI失败可以确定性排空并结束，不伪造特殊GID或Gaussian记录。

### 验证覆盖

- `tb_axi4_gaussian_mean_read_dma`覆盖基址0xFF0时4 KiB拆分、16拍主burst、3拍尾burst、输出背压稳定、空帧、16 Byte未对齐、SLVERR、错误RID、RLAST提前和延迟。
- `tb_gs_accel_system_axi_mean`覆盖APB配置基址/count、AXI读取到完整Gaussian-wise渲染链、AXI错误到frame done/error IRQ，以及count=0空帧。
- 一键Icarus回归：1项兼容顶层综合编译 + 46项SystemVerilog自检仿真全部PASS，退出码0。
- Python参考/结构合同：76项unittest全部PASS，约4.6秒。
- Icarus仅保留已知time-unit、constant-select和unique-case兼容提示，无新增功能失败。

### 当前边界和下一步

- 本轮准确完成的是“第一遍mean/GID顺序读DMA”，不是完整DMA子系统。
- 完整1118-bit逻辑属性仍需预加载片上属性SRAM；下一阶段应把排序后GID属性读取抽象成request/response接口，再接属性cache和AXI随机/合并读引擎。
- 像素AXI写回、真实分辨率image-state backing store、13场景整帧PSNR/SSIM/LPIPS和具体工艺PPA仍待后续闭环。
## 2026-08-09：排序后完整Gaussian属性request/response与AXI4读取

### 路线对齐

- 第一遍仍由紧凑mean/GID顺序DMA服务深度预处理；第二遍只在排序后按GID读取一次完整属性。
- 完整属性随后供projection、一次SH和Gaussian内部全部8×8 block复用，不预搬全部宽属性。
- 未引入Gaussian–tile bin/KV、per-tile list或per-tile排序；动态G/P/R/E仍以epoch安全排空为前提。

### RTL实现

1. 重构 `ordered_gaussian_attribute_issue` 为标准request/response后端，首版单outstanding；响应握手时原子锁存1118-bit属性，修复旧版依赖SRAM输出在渲染背压期间保持的接口限制。
2. 新增 `gaussian_attribute_sram_backend`，把原片上属性SRAM包装为同一ready/valid合同，原有验证路径保持兼容。
3. `gaussian_sorted_render_pipeline`支持SRAM与外部属性后端参数化替换，渲染主链不感知存储实现。
4. 新增 `axi4_gaussian_attribute_read_engine`：按 `ATTRIBUTE_BASE + GID×144` 读取9个128-bit beat；跨4 KiB自动拆burst；检查RRESP/RID/RLAST并原子重组。
5. APB新增 `0x03C/0x040 ATTRIBUTE_BASE`；系统错误bit12/13分别记录属性DMA协议和配置错误。

### 验证

- 新增属性AXI单元测试：GID地址计算、9拍重组、response背压、4 KiB拆分、未对齐和协议错误。
- 扩展系统AXI测试：mean DMA完成第一遍后，排序结果触发第二遍9拍属性读取；属性AXI错误使帧确定性结束并通过ERROR_STATUS bit12和IRQ报告。
- 全量Icarus回归：1项兼容顶层综合编译 + 47项SystemVerilog自检全部PASS，退出码0。
- Python参考/结构合同：77项unittest全部PASS。

### 当前边界

- 当前完整属性DMA是单outstanding、每GID固定9拍的正确性基线，尚无属性cache、合并读或预取。
- 下一阶段可在不改变渲染链顺序合同的情况下加入小型属性cache/多outstanding性能版本，或优先推进像素结果AXI写回和真实分辨率image-state backing store。
## 2026-08-09：有序像素状态AXI4写回与完成排空

### 路线对齐

- 写回只消费唯一blend/image-state writer的有序提交，不复制有状态writer，不改变Gaussian顺序。
- 主数据流继续是深度分组、Gaussian有序发射、Gaussian内部8×8遍历；未增加per-tile bin/list/sort。
- 动态R模式仍只复制无状态alpha lane；写回保持单有序端口，维持同pixel RAW正确性。

### RTL实现

1. 新增 `axi4_pixel_state_write_engine`：每commit打包128-bit完整像素状态，写到 `OUTPUT_BASE + pixel_id×16`。
2. 单outstanding，AW/W独立握手，必须等待B响应才接受下一提交；同pixel后续状态严格覆盖前态。
3. `gs_accel_system_top`默认启用 `USE_AXI_PIXEL_WRITE=1`，commit观察输出保留，但核心ready由写DMA控制。
4. 软件可见busy覆盖core、write DMA及completion pending；核心done后继续等待最后B响应，再产生系统done/IRQ。
5. ERROR_STATUS bit14/15分别记录写回响应/协议错误与配置/对齐错误。

### 验证

- 写回单元测试覆盖记录打包、pixel地址、AW/W不同步背压、数据稳定、正常B响应、SLVERR和未对齐。
- 系统双读+写回测试确认真实commit产生AXI写事务，且整个Gaussian-wise链正常结束。
- 全量Icarus回归：1项兼容顶层综合编译 + 48项SystemVerilog自检全部PASS，退出码0。
- Python参考/结构合同：78项unittest全部PASS。

### 当前边界

- 当前每次像素更新均写片外，正确但带宽较高；尚未实现dirty-pixel合并或帧末扫描写回。
- 真实分辨率仍受片上image-state容量4096项限制。下一阶段需设计image-state backing store/cache，不能仅以写回DMA宣称1080p支持完成。
## 2026-08-09：真实分辨率 Image-State 片外 Backing Cache

### 本轮目标与路线约束

- 解除片上 `STATE_ENTRIES=4096` 必须保存整帧状态的限制，同时保持 GCC 式“深度分组 + Gaussian 有序发射 + Gaussian 内部 8×8 block 遍历”。
- cache 只替换唯一 blend/state commit 的存储后端，不引入 per-tile bin/list/sort，也不复制有状态 writer。
- G/P/R/E 动态资源模式仍在 epoch 安全边界生效；cache 使用 epoch tag 实现跨帧逻辑清零。

### RTL 实现

1. 新增 `image_state_cache_backend.sv`：直接映射、完整 pixel tag、epoch tag、ready/valid 查询、单 miss、命中返回、片外填充和 commit 更新。
2. 新增 `axi4_pixel_state_read_engine.sv`：128-bit 单拍 AXI4 状态读，地址为 `OUTPUT_BASE + pixel_id×16`，检查 RRESP/RID/RLAST 和 16 Byte 对齐。
3. 将状态 miss 接口从 `raster_pair_shell` 贯穿至 `gs_accel_system_top`；raster idle 与系统 done 均等待 cache 和状态读排空。
4. blend commit 同时更新 cache 和既有 write-through DMA。状态 miss 在旧写 B response 未完成时禁止发射，避免冲突换出读回旧数据。
5. backing 模式下 `STATE_ENTRIES` 只表示片上 cache 容量，整帧像素数不再因此被拒绝；本地 state SRAM 模式继续保留 bit9 容量保护。
6. `ERROR_STATUS` 扩展为 32 位；原 bit0–15 保持不变，bit16/17 分别记录状态 backing 读协议/响应错误与配置/对齐错误。

### 验证

- 新增 `tb_axi4_pixel_state_read_engine`，覆盖正常读、背压、RRESP、RID、RLAST 和对齐错误。
- 新增 `tb_image_state_cache_backend`，使用 2-entry cache 覆盖冲突替换、写回后读回、epoch 失配、错误返回及 fill/update 同周期优先级。
- 扩展系统测试：状态读错误通过 APB `ERROR_STATUS[16]` 可见；backing 启用时 65×64 帧不再因 4096-entry cache 触发容量错误。
- 一键 Icarus 回归：1 项综合入口编译 + 50 项 SystemVerilog 自检全部 PASS，退出码 0。
- Python 参考模型/RTL 结构合同：79 项 unittest 全部 PASS，耗时约 6.2 秒。
- 当前共有 65 个 SystemVerilog RTL 文件、约 6501 行；51 个 RTL testbench、约 3047 行。
- Icarus 仍只有已知 time-unit、`always_comb` constant-select 和 `unique case` 兼容提示，无新增功能失败。

### 当前边界与下一步

- 本轮闭环的是逻辑容量和严格顺序正确性，尚未证明真实场景下片外状态带宽满足实时渲染。
- 下一阶段应建立真实场景 RTL workload bridge：把 13 场景的 Gaussian/相机数据转换为 DMA memory image，采集 cache hit/miss、AXI 读写、stall、commit 与周期数。
- 在真实负载数据支持前，不应直接增加复杂组相联、多 outstanding 或写合并；这些优化必须由 miss/带宽瓶颈驱动并做逐像素等价验证。

## 2026-08-09：真实训练场景 DMA 微负载贯通与 Drain 下溢修复

### 本轮目标

- 将本地训练完成的 PLY/相机数据转换为可被完整系统 RTL 读取的 DMA memory image。
- 用通用 AXI memory model 覆盖 mean、完整属性、image-state read 和有序 write-through write。
- 输出 cycle、commit、state miss、状态读等待和输出等待计数；结果明确标注为微负载而非完整场景性能。

### 新增与修复

- 新增 `model/io/dma_workload.py`、`scripts/build_rtl_real_workload.py` 和 `verification/rtl/tb_real_dma_workload.sv`。
- `gs_accel_system_top` 新增 5 个 64-bit 饱和性能计数输出；场景 IO 测试新增 mean 与 1118-bit 属性布局检查。
- 初始现象是 70 次 commit 后所有 DMA、cache、blend 和 raster 事务均排空，但 frame 停在 DRAIN。
- 根因是被裁剪 Gaussian 已通过 `valid && ready && last` 退休，延迟的 `culled_pulse_o` 又重复减一次 inflight，使计数下溢为 65535。
- 修复后 inflight 只由唯一的 backpressured last-beat 握手退休，并增强 raw projection lane cull 回归。

### 真实微负载结果

- bonsai / camera 146 / 4 Gaussian / 32×21；
- frame 正常完成，无 frame error；
- 1049 busy cycles，68 pixel commits；
- 68 state cache misses / 68 AXI reads / 68 AXI writes；
- 201 state-read stall cycles，0 output-commit stall cycles；
- 4 mean beats，36 attribute beats。

### 全量验证与口径

- Icarus Verilog 12：1 项综合入口编译 + 51 项 SystemVerilog 自检全部 PASS。
- Python：81 项 unittest 全部 PASS，约 7.0 秒。
- 当前样本是真实训练属性；选择器已改为扫描全部 PLY batch 的固定种子 priority sampling，不再集中于文件首批记录，但仍不是深度/屏幕分层代表样本。
- 下一阶段增加分层采样并扩大负载/AXI 延迟覆盖，然后建立完整帧导出、逐像素参考比对和 13 场景画质闭环。

## 2026-08-09：多场景可配置 AXI 性能矩阵与 Frame-State 导出

### 为什么开展本轮

- 固定4-Gaussian testbench只能验证单一数据集，无法测量内存系统对周期的影响，也无法为cache/写合并优化提供证据。
- 本轮验收要求不是增加测试数量，而是让同一完整RTL在不同场景和AXI时序下产生可比较周期数据，并证明背压不改变最终像素状态。

### 实现

- `tb_real_dma_workload.sv` 改为从 `camera.memh` 加载相机、尺寸和Gaussian数量；memory image和输出路径均由plusargs选择。
- 增加首拍读延迟、burst拍间空泡、ready占空比和B响应延迟参数。
- 仿真结束导出整幅 `frame_state.memh`，每像素保留完整128-bit写回记录。
- 新增 `scripts/decode_rtl_frame.py`，将Q1.12 RGB解码为PNG并输出非零像素、RGB和透射率统计。
- 新增 `scripts/run_rtl_workload_matrix.py`，自动运行矩阵、解析性能、计算frame SHA-256并强制理想/受限AXI逐位等价。

### 多场景结果

- bonsai：1538→3097 cycles，108 commits，倍率2.01×；
- garden：1514→3045 cycles，106 commits，倍率2.01×；
- train：2582→5359 cycles，195 commits，倍率2.08×。
- 三个场景的受限AXI输出与理想AXI输出逐位完全一致。
- limited配置下read-stall分别为963、945、1746 cycles；output-commit stall均为0。后者不代表写回免费，而是唯一state事务链已在commit之前串行化，写延迟体现于state miss发射和总周期。

### 工程结论与边界

- 背压时序正确性已由三场景逐位等价验证。
- 当前微负载在片外延迟增加后周期约翻倍，说明下一轮优先研究state miss overlap/cache命中提升或安全写合并是有数据依据的，不应先盲目复制算术lane。
- 8-Gaussian输出仍是稀疏微负载PNG，不能用于PSNR/SSIM/LPIPS；完整画质评价必须使用足够覆盖的完整帧和统一参考图。
- 机器可读报告位于 `experiments/rtl_workloads/real_dma_matrix_2026-08-09.json`。

### 本轮全量回归

- Icarus Verilog 12：1项综合入口编译 + 51项SystemVerilog自检全部PASS。
- Python：82项unittest全部PASS，约6.6秒；新增frame-state字段解码检查。
- 保留既有Icarus兼容性提示，无新增功能失败。

## 2026-08-09：有序 Pixel-State 写缓冲性能优化

### 数据驱动的优化目标

- 上一轮limited AXI使三场景周期约翻倍，且state-read stall占比明显。
- 原互锁要求任意miss等待整个旧写事务收到B响应，即使读写pixel完全不同，形成不必要的全局串行化。
- 本轮不增加per-tile结构、不复制有状态blend writer，只优化唯一writer之前的事务排队和精确同址保护。

### RTL实现

- 新增 `axi4_pixel_state_write_buffer.sv`：默认8项有序commit FIFO，内部继续复用单outstanding AXI writer。
- 使用完整32-bit pixel tag CAM检查FIFO和active writer；只有同pixel miss被阻塞，无关pixel读写可重叠。
- core commit由FIFO ready驱动，B响应延迟不再直接反压blend；frame done仍等待写缓冲彻底排空。
- 新增单元测试覆盖FIFO满背压、严格写顺序、排队/active同址hazard以及异址不误阻塞。
- 修复矩阵testbench的AW/W memory model：事务形成必须使用真实 `valid&&ready` 握手，不能把仅valid周期重复计为写事务。

### 性能与等价结果

- bonsai：ideal 1538→1219（1.26×），limited 3097→2171（1.43×）。
- garden：ideal 1514→1201（1.26×），limited 3045→2138（1.42×）。
- train：ideal 2582→2002（1.29×），limited 5359→3679（1.46×）。
- 六个配置的state-read stall均降为0；commit、state read、state write数量保持一致。
- 三场景优化后帧状态与优化前逐位相同，且优化后ideal/limited仍逐位相同。

### 边界

- 当前仍是唯一有序AXI writer和single-miss cache；优化消除了异pixel伪依赖，但没有提高AXI写事务本身的峰值吞吐。
- 微负载中write FIFO未表现出output stall；更大负载与更慢B响应下需要继续测深度敏感性。
- 下一性能候选应比较FIFO深度、写合并和state cache命中，不应破坏同pixel严格顺序或Gaussian-wise主路径。

### 全量回归

- Icarus Verilog 12：52项SystemVerilog自检 + 1项综合入口编译全部PASS。
- Python：82项unittest全部PASS，约5.9秒。
- Icarus仅保留既有兼容性提示，无新增编译或功能失败。

## 2026-08-09：写缓冲深度收敛与 State Cache 容量扫描

### 写缓冲深度

- 扫描深度2/4/8/16：三场景n8在ideal/limited AXI下周期、stall和最终输出均一致。
- train n8加64周期B响应压力时，四种深度均为13510周期；深队列没有缩短总时间。
- 默认深度从8改为2，payload存储由1216 bit降至304 bit，同时减少完整pixel-tag比较器；保持参数化以便后续工艺扫描。

### 写合并决策

- testbench新增连续同pixel commit统计；bonsai、garden、train n8的六个配置均为0。
- 因此相邻写合并当前收益为0；未实现任意队列CAM搜索/重排，避免为微负载不存在的机会增加面积和验证风险。

### Cache容量扫描

- n8负载像素复用低，容量从2增至128总体收益很小。
- 新增train n32、64×36负载：32/128/512项cache在limited AXI下周期为14155/13906/12415，miss为793/768/583。
- 512项相对32项获得1.14×加速并减少26.5%状态读；三种容量frame-state逐位一致。
- 默认4096项不因本轮微负载下调；最终容量待完整场景trace与SRAM宏面积/功耗共同决定。

### 下一瓶颈

- cache hit增加后，train n32的output stall上升到ideal 184、limited 1074周期，说明写侧吞吐将成为下一性能目标。
- 深FIFO已证明无助于总周期；下一轮应研究不改变有序语义的写事务减少或安全重叠，并用更大负载验证。

### 全量回归

- Icarus Verilog 12：52项SystemVerilog自检 + 1项综合入口编译全部PASS。
- Python：82项unittest全部PASS。
- 新增参数扫描均保持frame-state逐位等价；无新增功能失败。

## 2026-08-09：Dirty Pixel Write-Back 实验与默认路径决策

### RTL与验证补充

- 新增 `axi4_pixel_state_writeback_buffer.sv`：全相联完整pixel tag、128-bit最新状态覆盖、满缓冲最老项驱逐、frame末尾flush，以及queued/active writer状态前递。
- 系统顶层保留 `USE_PIXEL_WRITEBACK_BUFFER` 和 `PIXEL_WRITEBACK_DEPTH` 参数；状态cache miss优先查询dirty buffer，命中时不发AXI读。
- 真实负载testbench和矩阵脚本支持write-through/write-back切换；分别输出coalesced和forwarded-read计数。
- 修复矩阵脚本的并行运行冲突：不同路径/深度使用独立 `.vvp`，避免多个编译进程覆盖同一仿真镜像。
- 新增write-back单元回归，覆盖同pixel覆盖、完整128-bit前递、active writer前递、满缓冲驱逐、frame flush及严格最终记录。

### train n32 / cache512 对照

- write-through depth2：ideal 6582、limited 12415周期，795 commits / 795 writes。
- write-back depth8：ideal 6694、limited 12668周期，794 writes，1次合并。
- write-back depth32：ideal 6753、limited 12632周期，751 writes，44次合并。
- write-back depth128：ideal 7218、limited 13224周期，658 writes，137次合并、3次系统级前递。
- 8份完整128-bit frame-state的SHA-256均为 `F771C1FE...606E2634`，write-through/write-back及ideal/limited逐位一致。

### 决策

- depth128可减少17.2%片外写，但当前单未决writer的帧尾串行flush使总周期反而增加；带宽收益尚未转化为性能收益。
- 默认 `USE_PIXEL_WRITEBACK_BUFFER=0`，继续使用经验证更快、面积更小的2-entry write-through FIFO。
- write-back作为可配置研究路径保留，不宣称为正式性能优化；未来只有在多未决/突发writer或完整场景证明端到端收益后才重新评估默认值。
- 主数据流和动态可重构目标未改变，也未引入任何per-tile bin/list/sort。

### 全量回归

- Icarus Verilog 12：53项SystemVerilog自检 + 1项综合入口编译全部PASS。
- Python：82项unittest全部PASS。
- 详细数据见 `experiments/rtl_workloads/writeback_sensitivity_2026-08-09.md`。

## 2026-08-09：AXI4 Pixel-State 多未决写

### RTL设计

- 新增 `axi4_pixel_state_multiwrite_buffer.sv`，使用单一AXI ID支持参数化多未决写；同ID B响应按issue顺序回收。
- AW/W独立握手，但必须成对完成后才推进issue指针，防止无WID的AXI4写数据与地址错配。
- 环形队列项目在B响应前一直保留完整pixel tag，hazard覆盖queued、部分发射和response-pending全部阶段。
- 满队列支持B回收与新commit同周期替换，并修复同物理槽位下valid清除覆盖新入队的边界。
- 无未决BVALID、错误BID/BRESP和地址未对齐均进入既有write error sticky状态；frame completion继续等待全部响应排空。

### 性能

- train n32/cache512：ideal由6582降至6396周期（1.03×），limited由12415降至11353周期（1.09×），output stall均降为0。
- limited下峰值3笔未决，depth4/8/16周期相同；depth2仍有322周期output stall。
- 64周期B延迟压力下，旧路径54366周期；depth2/4/8/16分别为26971/13656/7303/6467周期。
- depth8在压力下相对旧路径加速7.44×；depth16仅比depth8再快约1.13×，但存储和tag CAM翻倍。
- 所有15份完整128-bit frame-state哈希完全相同，保持逐位正确性。

### 决策与回归

- 默认切换为 `USE_PIXEL_MULTIWRITE_BUFFER=1`、`PIXEL_MULTIWRITE_DEPTH=8`；旧单未决write-through和dirty write-back路径继续参数化保留。
- 新增确定性和96事务随机AXI测试，覆盖独立AW/W背压、随机B间隔、满环替换、协议错误和逐笔scoreboard。
- Icarus Verilog 12：55项SystemVerilog自检 + 1项综合入口编译全部PASS。
- Python：82项unittest全部PASS。
- 详细结果见 `experiments/rtl_workloads/multiwrite_sensitivity_2026-08-09.md`。

## 2026-08-13：Windows 原生 Verilator 安装与工具链验证

### 安装与安全边界

- 安装器：`D:\download\msys2-x86_64-20260611.exe`，大小 94,016,640 bytes，SHA-256 为 `3150d7d9aa5dedd900a7f52300d4d918271e3a8fc47de94848818fd5a430e6b0`；哈希与 winget 清单一致，Authenticode 状态为 Valid，签名者为 Christoph Reiter。
- MSYS2 安装在 `D:\Tools\msys64`，未加入用户或系统 PATH，未启用 WSL/虚拟化；卸载入口为 `D:\Tools\msys64\uninstall.exe`。
- 软件包仅来自 MSYS2 签名仓库。安装和验证过程未上传或读取外部平台上的项目数据，未关闭安全软件，未绕过公司策略，也未替换 DLL、降级包或采用非官方补丁。

### 已安装版本

- UCRT64：Verilator 5.050、GCC/G++ 16.2.0、Python 3.14.7；GNU Make 4.4.1。
- CLANG64：Verilator 5.050、Clang/LLD 22.1.8、Python 3.14.7。
- CLANG64 Verilator 包完整性检查为 154 个文件、0 个缺失；此前下载阶段末尾的 `llvm-tools` 镜像 404 不代表缺包，`pacman -Q` 和文件校验均确认该包已经安装。

### 验证结论

- UCRT64 `verilator --lint-only` 已通过本地 SystemVerilog smoke test，可立即作为项目 lint 工具使用。
- 普通 UCRT64 C++ 程序可编译运行，但 Verilator `--binary` 在链接生成模型时出现 `std::__cxx11::basic_string` 未定义引用，判断为当前 MSYS2 UCRT64 GCC 与 Verilator 运行库的打包/链接兼容问题。
- CLANG64 的包和版本均完整，但当前 Windows/MSYS2 组合下 lint 启动返回异常状态；底层程序同时表现出内建 include 路径混合分隔符和 Windows 栈溢出退出码。因此 CLANG64 暂不能作为正式仿真后端。
- 按安全约束停止继续扩展第三套工具链。当前状态为“Verilator 安装完成、静态 lint 可用、`--binary` 仿真暂不可用”；功能仿真继续以已经验证的 Icarus Verilog 12 为主。

### 推荐调用方式

```powershell
$env:MSYSTEM='UCRT64'
$env:CHERE_INVOKING='1'
& 'D:\Tools\msys64\usr\bin\bash.exe' -lc `
  'cd /d/3DGS && verilator --lint-only --sv <其他选项与源文件>'
```

- 上述设置只作用于当前 PowerShell 进程，不修改系统环境。
- 下一步可以对 `verification/rtl/system_top_sources.f` 和顶层 `gs_accel_system_top` 运行项目级 lint，先分类既有告警，不直接修改架构或 RTL 行为。

## 2026-08-13：Verilator 顶层基线与有序退休组合环修复

### 项目级 lint 基线

- 使用 Verilator 5.050 对 `system_top_sources.f` 中完整 RTL 展开，顶层为 `gs_accel_system_top`；源文件 include 路径显式设置为 `rtl/raster`。
- 首次完整 lint 可展开 64 个模块并退出 0，但报告 344 条告警：127 条 WIDTHEXPAND、91 条 UNUSEDSIGNAL、76 条 WIDTHTRUNC、34 条 PINCONNECTEMPTY、10 条 MULTIDRIVEN、2 条 SYNCASYNCNET、2 条 BLKSEQ、1 条 UNOPTFLAT 和 1 条 UNUSEDPARAM。
- 其中未使用端口多为参数化研究路径的观测输出；位宽告警需要结合定点数值等价测试逐模块处理，未采用批量屏蔽或机械强制类型转换。

### 确定问题与修复

- `ordered_gaussian_retire` 原先在同一 `always_comb` 中完成 lane 选择、输出 mux 和 downstream-ready 回传。虽然设计意图中输出数据不依赖 ready，但工具将整个过程视为互相依赖，报告从投影结果、SH join 到退休 ready 的组合环。
- 将结果选择、输出 mux 和 ready demux 分离；不增加寄存器或周期延迟，不改变近到远 Gaussian 退休顺序，也不改变 Gaussian 内部 block 流。
- `depth_group_buffer` 和 `stable_group_sorter` 原先分别在组合与时序过程复用同一个整数循环变量；改为过程独立循环变量，消除工具报告的多驱动伪对象。
- 修复后 UNOPTFLAT 从 1 降为 0、MULTIDRIVEN 从 10 降为 0，总告警由 344 降至 333，Verilator 顶层 lint 退出码为 0。

### 可重复验证入口

- 新增 `verification/rtl/run_verilator_lint.cmd`，从脚本位置解析工程根目录，使用本机 `D:\Tools\msys64` UCRT64 环境，不修改用户或系统 PATH。
- lint 输出基线保存于 `tmp/verilator_top_lint_2026-08-13.log`。

### 回归结果

- Icarus Verilog 12：55 项 SystemVerilog 自检 + 1 项综合入口编译全部 PASS。
- 真实 bonsai DMA 微负载保持 848 busy cycles、68 commits、68 state reads、68 state writes，multiwrite 峰值未决为 1，与修复前基线一致。
- Python：82 项 unittest 全部 PASS，耗时约 5.1 秒。
- Verilator：完整 `gs_accel_system_top` lint PASS；组合环与多驱动告警均为 0。

### 路线约束与下一步

- 本轮没有改变深度分组、Gaussian 有序发射、Gaussian 内部 8×8 block 遍历，也没有引入 per-tile bin/list/sort。
- epoch 级 G/P/R/E 动态重构和默认 8 项 AXI 多未决写保持不变。
- 下一轮从公共 `fixed_sqrt_pipe` 开始治理定点位宽告警；每项调整必须通过整数平方根单元测试、投影/协方差链测试、全量回归和 Verilator 告警差分，不以“消警”代替数值正确性。

## 2026-08-13：定点平方根精确定宽与随机背压验证

### 修改原因

- `fixed_sqrt_pipe` 的恢复平方根算法原先使用移位和按位或表达式拼接余数、被开方数位和试除数。SystemVerilog 的表达式自定宽规则使中间结果先扩展到较宽操作数、再截断回目标寄存器。
- 算法结果在当前参数下正确，但 Verilator 报告 15 条 WIDTHEXPAND/WIDTHTRUNC；两个共享阻塞临时变量位于 `always_ff` 内，又产生 2 条 BLKSEQ。这种隐式宽度不利于不同 ASIC 综合工具间的一致性审查。

### RTL实现

- 每个流水级显式拼接 `{partial_remainder, radicand_pair}`，严格保持 `REM_W` 位。
- 试除数显式拼接 `{partial_root, 2'b01}`，同样严格保持 `REM_W` 位。
- 每级的比较、余数减法和下一位根改为独立组合网络，时序过程只负责寄存结果；未增加流水级、延迟或全局背压路径。
- 算法仍为每级处理两个被开方数位的全流水恢复平方根，空闲时保持一拍一输入，输出阻塞时冻结完整管线。

### 验证增强

- `tb_fixed_sqrt_pipe` 从 5 笔定向向量扩展为 256 笔逐笔自检。
- 覆盖 0、1、完全平方数相邻边界、`65535^2`、32-bit 最大值及确定性伪随机输入。
- testbench 内使用独立的逐位整数平方根参考函数，并随机改变输出 ready；根值和 metadata 均逐笔比较，可同时发现数值错误、丢数和乱序。
- 256 笔测试全部 PASS；Cholesky 编码、完整投影 lane 和 SH 视角归一化等实际调用链测试全部 PASS。

### 告警差分与全量回归

- `fixed_sqrt_pipe` 的 15 条位宽告警和 2 条 BLKSEQ 全部归零。
- 完整顶层告警由 333 降至 316：115 WIDTHEXPAND、73 WIDTHTRUNC、91 UNUSEDSIGNAL、34 PINCONNECTEMPTY、2 SYNCASYNCNET、1 UNUSEDPARAM。
- UNOPTFLAT 与 MULTIDRIVEN 继续保持为 0；Verilator 顶层 lint 退出码为 0。
- Icarus Verilog 12：55 项 SystemVerilog 自检 + 1 项综合入口编译全部 PASS。
- Python：82 项 unittest 全部 PASS。

### 路线与下一步

- 本轮只治理公共定点算术单元的可移植性，没有改变 Gaussian-wise 主数据流、8×8 block 遍历、深度分组顺序或动态重构策略。
- 下一轮优先分析 `gaussian_resource_mode_table` 的 20 条位宽提示。该模块直接决定 G/P/R/E 动态资源分配，需先验证各模式的面积信用预算和 lane 数映射，再决定哪些是参数比较告警、哪些需要显式定宽。

## 2026-08-13：G/P/R/E 动态资源模式表精确定宽

### 设计目标复核

- 模式表只对已经实例化的物理 group/projection/SH/raster lanes 进行启用和时钟门控，不在运行时改变算术单元或 SRAM 的物理容量。
- G/P/R/E 分别保持分组优先、投影与 SH 优先、光栅优先和节能模式；模式只在 epoch 安全边界提交。
- Python R1 周期模型继续负责验证不同动态模式遵守相同面积信用预算；RTL 模式表负责具体 lane-count 和仲裁权重映射，两者职责不混用。

### RTL改进

- 原模式表将 32-bit elaboration 参数 `*_LANES` 和 `*_HALF` 直接赋给 1～3 bit active-lane 输出，顶层产生 20 条 WIDTHTRUNC。
- 新增 `*_ALL_COUNT` 和 `*_HALF_COUNT` 精确定宽 localparam，在 elaboration 时一次性转换到对应 count width；四种模式的输出数值和权重不变。
- half 策略继续使用 `(LANES+1)/2`，即奇数物理 lane 数向上取整；节能模式继续保证每个阶段至少启用 1 lane。
- count-width 默认表达式对非法零 lane 保持至少 1 bit 语法宽度；仿真/形式环境加入参数 assertion，拒绝零物理 lane 和无法表示完整 lane 数的过窄 count width。assertion 不进入综合数据通路。

### 验证增强

- 原有 4/4/4/4 对称配置的四模式映射保持：G=`4/2/2/2`、P=`2/4/4/2`、R=`2/2/2/4`、E=`1/1/1/1`。
- 新增 3/5/2/7 非二次幂非对称实例，验证：G=`3/3/1/4`、P=`2/5/2/4`、R=`2/3/1/7`、E=`1/1/1/1`。
- 两组配置均验证 G/P/R 权重分别为 `4/2/1`、`1/4/2`、`1/2/4`；E 为 `1/1/1` 并启用 aggressive clock gate。
- Python 结构契约新增精确定宽常量、非法参数 assertion 和禁止 tile-bin 路径检查。

### 告警差分与回归

- `gaussian_resource_mode_table` 的 20 条位宽告警全部归零。
- 完整顶层告警由 316 降至 296：115 WIDTHEXPAND、53 WIDTHTRUNC、91 UNUSEDSIGNAL、34 PINCONNECTEMPTY、2 SYNCASYNCNET、1 UNUSEDPARAM。
- UNOPTFLAT 与 MULTIDRIVEN 继续为 0；Verilator 顶层 lint PASS。
- Icarus Verilog 12：55 项 SystemVerilog 自检 + 1 项综合入口编译全部 PASS。
- Python：83 项 unittest 全部 PASS。
- bonsai 真实 DMA 微负载保持 848 cycles、68 commits、68 state reads 和 68 state writes，证明默认模式数据通路未改变。

### 路线约束与下一步

- 未改变“深度分组 + Gaussian 有序发射 + Gaussian 内部 8×8 block 遍历”主路径，未引入 per-tile bin/list/sort。
- epoch 级动态重构、模式提交安全边界和默认 8 项 AXI 多未决写保持不变。
- 下一轮应优先检查投影协方差算术链中集中的位宽告警；建议从 `quaternion_scale_covariance_core` 开始，先明确每个 Q 格式和饱和/舍入边界，再逐项定宽并使用现有 3D covariance、projection lane 和真实负载回归。

## 2026-08-13：四元数-尺度协方差定宽与舍入溢出闭环

### 与既定主线的关系

- 本轮继续安装 Verilator 前的 ASIC RTL 与真实负载验证主线；Verilator 仅用于发现跨综合工具的隐式定宽风险，不以告警数量替代渲染正确性。
- 修改对象是 Gaussian 投影前端中的 `quaternion_scale_covariance_core`，负责将训练所得归一化四元数和三轴尺度转换为世界空间协方差，是后续屏幕协方差、椭圆覆盖和 8×8 block 遍历的数值基础。
- 未改变深度分组、Gaussian 有序发射、SH 计算、8×8 遍历或 epoch 级动态重构。

### 定点位宽修复

- 输入格式保持 quaternion signed Q1.20、scale unsigned Q4.20；旋转与 scaled-rotation 保持 Q*.20，协方差输出保持 signed Q24.16。
- 原旋转矩阵表达式将 44-bit Q40 乘积与 64-bit `1<<40` 常量混合，产生 21 条隐式扩展/截断告警。
- 新增 `ROT_ACC_W` 同宽 `ONE_Q40` 常量和 `twice_qprod` 显式符号扩展函数，所有旋转矩阵加减均在 47-bit accumulator 内完成；乘法器数量、Q 格式和流水级不变。
- 三处定点转换使用显式尺寸转换表达输出截断意图，模块自身的宽度与未使用高位告警全部归零。

### 舍入与 overflow 一致性修复

- 发现原 overflow 判断使用算术截断后的整数部分，而输出采用 round-to-nearest；在有符号最大/最小值附近，半 LSB 舍入可能越界但错误位仍为 0。
- 新增 rotation、scaled-rotation 和 covariance 共用的舍入函数；数值输出和 overflow 检查现在使用同一个舍入结果。
- 增加正负有符号极限前一 raw code 与恰好半 LSB 越界检查，确认边界内不误报、舍入越界不漏报。

### 验证增强

- 3D 协方差链测试由 1 笔扩展为 4 笔：单位四元数各向异性尺度、精确轴置换四元数 `(0.5,0.5,0.5,0.5)`、15 倍各向同性尺度、非法非归一化四元数。
- 正常样例对六个协方差分量逐位比较；异常样例必须完成事务并置 overflow，不对溢出后的截断数据作错误数值承诺。
- 加入输出背压，metadata 和各协方差事务保持有序、无丢失。

### 完整回归与真实负载

- `quaternion_scale_covariance_core` 的 24 条顶层告警全部归零。
- 完整顶层告警由 296 降至 272：97 WIDTHEXPAND、50 WIDTHTRUNC、88 UNUSEDSIGNAL、34 PINCONNECTEMPTY、2 SYNCASYNCNET、1 UNUSEDPARAM。
- UNOPTFLAT 与 MULTIDRIVEN 保持为 0；Verilator 顶层 lint PASS。
- Icarus Verilog 12：55 项 SystemVerilog 自检 + 1 项综合入口编译全部 PASS；Python 83 项 unittest 全部 PASS。
- bonsai/garden/train 三个训练场景的 n8 微负载在 ideal/limited AXI 下共 6 个配置全部 PASS，且各场景两种 AXI 时序的 128-bit frame-state 逐位一致。
- 当前输出与 2026-08-09 修改前保存的 frame-state 哈希逐位一致：bonsai `2BA5189A...C005A6E`、garden `14431103...3D87CAB`、train `38054720...A53AD7`。
- 新报告为 `experiments/rtl_workloads/covariance_width_matrix_2026-08-13.json`。当前周期低于早期报告是默认 8 项 multiwrite 已启用的结果，不能归因于本轮协方差定宽；本轮可证明的是像素状态不变。

### 下一步

- 下一轮建议继续同一投影协方差链，处理 `covariance_view_rotate_core` 的显式乘加宽度和舍入溢出一致性。
- 完成世界协方差与视图协方差后，再进入 screen covariance；每步均要求模块数值测试、完整 projection lane、三场景 frame-state 哈希和全量 RTL/Python 回归。

## 2026-08-13：视图协方差乘加定宽与舍入边界闭环

### RTL改进

- `covariance_view_rotate_core` 的两级矩阵乘加明确为 63-bit 乘积、65-bit 第一级三项和、87-bit 第二级乘积和 89-bit 最终三项和，不再依赖表达式隐式扩展。
- 增加固定宽度 `sum3_p`、`mul_t_rot` 和 `sum3_final`，保证不同 SystemVerilog 综合工具采用相同的中间精度。
- 输出 Q24.16 转换与 numeric-overflow 判断共用同一个 round-to-nearest 结果，避免最大/最小值附近出现“输出已舍入越界但错误位未置位”。

### 验证与结果

- 增加正、负 Q24.16 舍入极限检查；完整 covariance 链、projection lane、背压和 metadata 对齐测试全部通过。
- 模块 19 条 Verilator 位宽告警全部归零，顶层告警由 272 降至 253；UNOPTFLAT、MULTIDRIVEN 保持为 0。
- 55 项 SystemVerilog 自检 + 1 项综合入口、83 项 Python unittest 全部 PASS；真实微负载数值输出与既有基线逐位一致。

## 2026-08-13：屏幕协方差结构与 metadata PPA 收敛

### RTL改进

- `screen_covariance_core` 第一层两项乘积累加器由 `PRODUCT_W+2` 收敛到所需的 `PRODUCT_W+1`；第二层最终累加器只保留 1 个必要保护位。
- 删除后续计算未使用的 `row1_x` 数据路径以及两个 32×41 乘法器。
- 第二级 divider metadata 删除已经消费完的 camera x/y/z，每个 divider stage 减少 81 bit；当前 33-stage divider 每实例结构上减少约 2673 个 metadata 流水触发器，默认 4 projection lanes 时约减少 10692 个触发器。
- regularizer 改为显式零扩展，消除符号和宽度歧义。

### 验证与结果

- 模块测试扩展到 4 笔，覆盖非零 x/y、交叉协方差、z=0 错误、输出背压和饱和边界。
- 模块 25 条告警全部归零，顶层告警由 253 降至 228；55+1 项 RTL 与 83 项 Python 回归全部 PASS。
- bonsai、garden、train 的 ideal/limited 六个配置逐位等价，哈希分别为 `2BA5189A...C005A6E`、`14431103...3D87CAB`、`38054720...A53AD7`。
- 机器可读报告：`experiments/rtl_workloads/screen_covariance_ppa_matrix_2026-08-13.json`。

## 2026-08-13：BBox 整数平方根全流水化

### 修改原因与结构

- 原 `bbox_tile_bounds_core` 使用 32 次展开的 `trial*trial` 组合循环求整数平方根，综合后可能形成很深的乘法—比较链，不利于 ASIC 时序、面积和切换功耗。
- 改为复用 16 级全流水 `fixed_sqrt_pipe`，保持每周期 1 个 Gaussian 的吞吐；保守 `ceil(sqrt)`、opacity-aware radius 与 8×8 block/tile 语义不变。
- `fixed_sqrt_pipe` 增加 `m_exact_o`，用最终余数判断完全平方，避免把 eigen bound 额外复制穿过 16 级流水；bbox metadata 与 sqrt 结果原子传递。

### 性能代价与验收

- 三个场景 ideal 配置均固定增加 17 周期，limited 配置均增加 18 周期；commit、state read/write 数不变。固定启动/排空代价没有按 Gaussian 数串行放大。
- 新旧完整 frame-state SHA-256 逐位相同，ideal/limited 也逐位相同；因此接受该结构，以极小整帧固定延迟换取关键路径风险的显著降低。
- bbox 的 13 条位宽告警归零；256 笔 sqrt root/exact/meta 随机背压测试以及 bbox、完整投影 lane、55+1 项 RTL、83 项 Python 回归全部 PASS。
- 机器可读报告：`experiments/rtl_workloads/bbox_sqrt_pipeline_matrix_2026-08-13.json`。

## 2026-08-13：Blend 共享乘积优化

### 结构优化

- 原前向混合同时计算 `old_t*alpha` 和 `old_t*(1-alpha)`，每个 blend lane 使用两个 16×13 乘法器。
- 利用 `old_t*(4096-alpha) = (old_t<<12) - old_t*alpha`，透射率更新复用颜色权重已经计算的乘积；每个 lane 删除一个 16×13 乘法器，仅增加移位布线和 29-bit 减法器。
- 保持原定点舍入、RGB 饱和、termination 判定、一拍一笔吞吐和 ready/valid 接口，不增加流水延迟，也不改变同像素严格顺序。
- 所有中间结果显式定宽，`blend_fixed_core` 原 12 条位宽告警全部归零；顶层总告警由 218 降至 206。

### 验证与结论

- blend 单元测试新增 256 笔合法定点域随机向量，由独立参考公式逐笔检查 RGB、transmittance、饱和、termination 和 metadata；全部 PASS。
- Icarus Verilog 12：55 项 SystemVerilog 自检 + 1 项综合入口编译全部 PASS；Python：83 项 unittest 全部 PASS；Verilator 完整顶层 lint PASS，UNOPTFLAT 与 MULTIDRIVEN 仍为 0。
- 三场景六配置的周期、commit 和 AXI 流量与 bbox 流水化基线完全一致，完整 frame-state 哈希逐位相同。
- 机器可读报告：`experiments/rtl_workloads/blend_shared_product_matrix_2026-08-13.json`。

### 路线约束

- 上述修改均未改变“深度分组 + Gaussian 有序发射 + Gaussian 内部 8×8 block 遍历”主路径，未引入 per-tile bin/list/sort。
- epoch 级 G/P/R/E 动态重构、默认 8 项 AXI 多未决写和严格前向 alpha 混合顺序保持不变。
- 在具体 ASIC 工艺库到位前，当前只报告可综合结构变化与周期/逐位等价证据，不把 RTL 运算单元数直接冒充工艺面积或功耗结果。

## 2026-08-13：World-to-Camera 公共变换定宽

### RTL与验证改进

- 明确 3×3 旋转乘积为 49 bit，三项乘积加平移采用 51-bit accumulator；新增 `sum_products_translation` 对每个乘积先做显式符号扩展，再完成四项求和。
- 每轴 round-to-nearest 结果只形成一次，并同时供输出饱和和 overflow 判断使用，避免综合器重复展开等价舍入网络。
- 新增独立 `tb_world_to_camera_core`，覆盖精确 identity+translation、正负半 LSB 舍入、正负饱和/overflow 和输出背压。全量 RTL 回归由 55 项增加到 56 项。

### 结果

- 模块 9 条位宽告警全部归零；顶层总告警由 206 降至 197，UNOPTFLAT、MULTIDRIVEN 仍为 0。
- 56 项 SystemVerilog 自检 + 1 项综合入口、83 项 Python unittest 和 Verilator 顶层 lint 全部 PASS。
- 三场景六配置的周期、commit 和完整 frame-state 与上一轮逐位相同；报告为 `experiments/rtl_workloads/world_transform_width_matrix_2026-08-13.json`。
- 本轮不改变乘法器数、流水级或 Gaussian-wise 调度，只提高公共投影算术的可移植性和逻辑共享确定性。

## 2026-08-13：2D Cholesky 编码器定宽与并行路径一致性

### 修改与验证

- `choose_factor_shift` 和 `choose_coordinate_shift` 的整数搜索结果显式转换为 signed 6 bit；动态编码移位显式转为软件整数控制量，消除 SystemVerilog 隐式宽度差异。
- 像素边界转 Q8 时先显式零扩展到 signed 28 bit，屏幕均值显式符号扩展到同宽后再作差，保证负均值、大坐标和右下开区间边界的 extent 计算一致。
- 新增大范围坐标测试：相对均值的 256 像素跨度正确选择 coordinate shift=4，同时 factor shift 与 Cholesky 因子保持不变。
- 新增并行 conic divider metadata 相等断言；两条求逆路径只在同一事务对齐时进入 sqrt，未来若延迟或背压修改造成错配会立即失败。

### 结果

- 编码器 9 条宽度/未使用告警归零；保留 2 条明确空接 `m_exact_o` 的 PINCONNECTEMPTY 提示。顶层总告警由 197 降至 188。
- 56 项 SystemVerilog 自检 + 1 项综合入口、83 项 Python unittest、Verilator 顶层 lint 全部 PASS。
- 三场景六配置的周期、commit、AXI 流量和完整 frame-state 均与上一轮逐位一致；报告为 `experiments/rtl_workloads/cholesky_width_matrix_2026-08-13.json`。
- Cholesky 求逆、PSD 因子化、保守 block 覆盖和 Gaussian 内部 8×8 遍历语义均未改变。

## 2026-08-13：透视投影双轴独立饱和修复

### 发现的问题

- 原 `perspective_project_core` 将 X/Y 的越界条件合并为单个 `screen_overflow` 后再控制两轴饱和；如果只有 X 越界，正常的 Y 也会被错误饱和，反之亦然。
- principal point 从 Q16 转 Q8 后仍以 33-bit 表达式参加求和，再隐式截到 28 bit；极端主点或大投影 offset 下可能漏掉真实范围信息。

### 修复

- 主点和 divider offset 均显式符号扩展到 34-bit，再完成屏幕坐标求和；上下界定义为同宽 signed 常量。
- X/Y 分别判断范围并独立饱和，最终 visible/error 仍由任一轴越界合并产生。
- 新增独立 `tb_perspective_project_core`，覆盖正常 Q16→Q8 主点、仅 X 正向越界且 Y 保持、仅 Y 负向越界且 X 保持。全量 RTL 回归由 56 项增加到 57 项。

### 结果

- 模块 4 条位宽告警归零，顶层总告警由 188 降至 184。
- 57 项 SystemVerilog 自检 + 1 项综合入口、83 项 Python unittest 和 Verilator 顶层 lint 全部 PASS。
- 三场景六配置的周期、commit 与完整 frame-state 均与修复前逐位一致，说明当前微负载未触发该极端边界；定向测试证明问题已被实际覆盖，而非仅靠 lint 推断。
- 报告为 `experiments/rtl_workloads/perspective_axis_saturation_matrix_2026-08-13.json`。
- 本修复不改变 divider 吞吐、投影 lane 数、深度分组或 Gaussian 内部 8×8 block 遍历。

## 2026-08-13：真实负载阶段探针、模式修复与有序 commit 气泡优化

### 阶段探针与模式编程修复

- `tb_real_dma_workload.sv` 新增仅验证侧的 collect/drain、group/sort、attribute wait、projection/SH/raster、projection-raster overlap、sorted/block backpressure、retire wait 和 state-cache busy 周期计数；这些计数器不进入综合硬件。
- `run_rtl_workload_matrix.py` 新增 `--lanes`、`--frame-mode` 参数并把 `REAL_STAGE` 字段写入 JSON 的 `stage_cycles`。
- 发现真实负载 testbench 原来把模式写到 APB `0x02C`，但 `0x008` 才是 mode shadow，`0x02C` 是 IRQ enable。此前矩阵实际使用默认模式，不能作为四模式比较证据。
- 已改为向 `0x008` 写模式并检查 `active_mode_o`；AXI/IRQ testbench 同时保留 `0x02C=3` 和 `0x008=3`，分别验证 IRQ enable 与模式编程。

### 4 lane G/P/R/E 行为与瓶颈

- 修复地址后，train n32 的 G/P/R/E active-lane mask 和阶段占用确实随模式变化，证明 epoch 级动态资源配置生效。
- 优化前四模式总周期仍相同：ideal 6413、limited 11371。projection 与 raster 长时间重叠，而 block backpressure 约占帧周期 90%；多条上游 lane 最终受单一有状态 read-blend-commit 服务路径限制。
- 因此没有继续盲目复制算术 lane，也没有引入 per-tile bin/list/sort，而是优先消除严格有序状态提交中的固定控制气泡。

### Commit 同周期替换

- `blend_state_commit.sv` 原来每笔事务执行 `IDLE → QUERY → BLEND → COMMIT → IDLE`。现在 commit 被接受的同一周期可原子接收下一笔 ordered pixel，下一状态直接进入 `QUERY`。
- 该改动仍保持单未决事务、严格输入顺序和同像素 RAW：当前更新在 commit 时钟沿写回，替换事务下一周期 query 可见更新值。硬件代价仅为少量控制 mux，没有新增 CAM、scoreboard 或 MSHR。
- 新增 SVA 检查 commit replacement，并由同像素连续四次 blend 定向测试验证。
- train n32：ideal 从 6413 降至 5619（约 12.4%），limited 从 11371 降至 10405（约 8.5%）；bonsai n4 从 865 降至 798。commit、miss、AXI 读写和 frame-state 均保持不变。

### 回归暴露的测试问题

- 优化改变周期相位后，`tb_gaussian_frame_render_pipeline` 暴露帧间 `commit_ready_i` 随机残留为 0 的 testbench 问题；已在第二帧前显式恢复为 1。
- `tb_gs_accel_system_axi_mean` 曾因模式地址修复时遗漏 IRQ enable 写入而失败；现已分别写 `0x02C` 和 `0x008`。
- 最终 57 项 SystemVerilog 自检 + 1 项综合入口、83 项 Python unittest、Verilator 顶层 lint 全部 PASS；跨帧 epoch、同像素 RAW、AXI 和 IRQ 均通过。

## 2026-08-13：13 场景 n32 阶段占用矩阵

### 配置与结果

- 为 bicycle、bonsai、counter、drjohnson、flowers、garden、kitchen、playroom、room、stump、train、treehill、truck 生成 13 份确定性 n32 负载；每份读取真实训练属性，最大边 64，像素数不超过 4096 项 state cache 容量。
- 使用 4 个物理 lane、R 模式、4096 项 state cache、8 项 AXI multiwrite，分别运行 ideal/limited AXI，共 26 项全部 PASS。
- 所有场景的 ideal/limited 完整 frame-state 逐位一致；output stall 均为 0；multiwrite 峰值 ideal=2、limited=4。
- limited/ideal 周期比均值约 1.871×；ideal 下 block backpressure 占帧周期均值约 87.5%。优化后四模式 train n32 总周期仍均为 ideal 5619、limited 10405。
- 详细逐场景数据见 `experiments/rtl_workloads/all13_n32_commit_replace_stage_2026-08-13.json` 和对应 Markdown 汇总。

### 工程结论与适用边界

- Commit 气泡优化跨 13 场景稳定有效；当前下一瓶颈是 state-cache miss 与单未决读改写路径。动态 G/P/R/E 的功能和 lane mask 正常生效，但上游并行度暂时不能越过 state path 的服务率上限。
- 下一项候选是保持 Gaussian 顺序和同像素 RAW 的不同 pixel state transaction overlap。它需要 hazard CAM/scoreboard、hit-under-miss 或 MSHR 以及 AXI read order 管理，面积和验证风险显著增加，必须先做收益上界和微架构规格，不能直接堆叠硬件。
- n32 是真实训练属性 RTL 微负载，不是完整帧画质评估，不能用于 PSNR、SSIM、LPIPS，也不能冒充最终帧率或 ASIC PPA。
- 本轮没有改变“深度分组 + Gaussian 有序发射 + Gaussian 内部 8×8 block 遍历”主路径，没有增加任何 per-tile bin/list/sort。
- 所有数据仅在 `D:/3DGS` 本地读取和写入，没有上传网络或公开平台。

## 2026-08-13：工艺无关 ASIC 约束入口

- 新增 `asic/constraints/gs_accel_system_top.sdc`，以 `gs_accel_system_top`、`clk_i` 和 `rst_ni` 为边界，提供参数化时钟、时钟不确定度、I/O delay 和异步复位 false path。
- 默认 5.0 ns（200 MHz）只是前综合设计目标假设，用于尽早发现长路径，不是签核频率；0.25 ns uncertainty 和 0.5 ns I/O delay 也必须在 SoC 集成时替换。
- 新增 `asic/README.md`，明确最终 PPA 需要标准单元和 SRAM macro 库、PVT/RC corner、目标频率、真实 I/O budget、综合/STA/功耗工具以及代表性 VCD/SAIF。
- 在工艺库和活动文件未准备好前，不报告虚构的面积、功耗或 ASIC FPS。

## 2026-08-13：2-entry 有序 state window 机会探针与规格冻结

### 验证侧探针

- 在真实负载 testbench 中新增 `window_wait/window_same/window_diff`，只观察 alpha ordered-retire 队首因当前单事务 state path 反压而等待的周期，并用完整 `{epoch,pixel}` key 区分必须串行的 RAW 与潜在不同像素并行候选；该探针不进入综合硬件。
- 13 场景 ideal 聚合：63858 cycles，window wait 50905（79.7%）；limited 聚合：119287 cycles，window wait 104879（87.9%）。两种 profile 的 same-key 等待均为 0，different-key 分别为 50905 和 104879。
- 8651 commits 中有 6734 misses，miss/commit=77.8%。因此 2-entry FIFO 本身不能提高服务率；它必须和 hit-under-miss 或多 MSHR 配合。
- 若所有等待可完美二路重叠，Amdahl 乐观上限约 ideal 1.663×、limited 1.784×；这只是上界。按总体 hit 比例粗略折算，单 MSHR hit-under-miss 参考上限约 1.10×，不能当作周期预测。

### 架构决策

- 新增 `docs/有序像素状态窗口规格_v0.1.md`。Phase A 采用 2-entry ordered window、完整 key hazard CAM、共享 blend core 和单 MSHR hit-under-miss；head-only commit 保持严格顺序。
- Phase B 的第二 MSHR 暂不直接实现。只有 Phase A 实测收益不足且 ASIC PPA 允许时，才增加 AXI read ID、响应 slot tag、同 key 合并/阻塞和双 miss 管理。
- E 模式可关闭第二窗口项以降低 metadata/CAM 活动；G/P/R 是否启用窗口由 epoch 边界和阶段瓶颈决定，从而把 state path 也纳入动态可重构，而不是只改变上游 lane mask。
- `same=0` 只代表当前 n32 微负载，不允许删除 RAW 比较器。完整帧 trace、PSNR/SSIM/LPIPS 和具体工艺 PPA 仍未由该实验覆盖。

### 本轮回归

- 13 场景 state-window 探针共 26 项 ideal/limited 仿真全部 PASS，完整 frame-state 在每个场景内逐位一致；报告为 `experiments/rtl_workloads/all13_n32_state_window_probe_2026-08-13.json`。
- 57 项 SystemVerilog 自检 + 1 项综合入口全部 PASS；新增探针下 bonsai n4 仍为 798 cycles、68 commits、68 state reads/writes。
- Python unittest 由 83 项增加至 86 项并全部 PASS，新增合同覆盖 mode APB 地址、stage/window 字段、commit replacement 和 ASIC 约束的非签核边界。
- Verilator 5.050 完整顶层 lint PASS；本轮没有修改综合 RTL，UNOPTFLAT 和 MULTIDRIVEN 仍保持 0。

## 2026-08-13：Phase A 两项有序 state window 与单 MSHR hit-under-miss

### RTL 实现

- `blend_state_commit.sv` 从单事务 FSM 改为 2-entry ordered transaction window。每项保存完整 metadata、`{epoch,pixel}` key、颜色/alpha、state response 和 blend result。
- 窗口只允许 head 对外 commit 和更新 architected pixel state；younger 即使先完成也必须等待。完整 key hazard CAM 阻止相同像素在 older 退休前发起独立 query，保持严格同像素 RAW。
- state query/response 和共享 `blend_fixed_core` 均加入 1-bit slot tag，响应和 blend 结果写回原 slot，不依赖完成先后来推断事务归属。
- `image_state_cache_backend.sv` 加入一个 MSHR：miss 等待 AXI 时允许不同 key 的 cache hit 返回，第二个 miss 仍阻塞。对外 AXI reader 保持单 ID、单未决，不引入多响应乱序风险。
- cache fill 与有序 commit update 同周期时仍由 update 获胜；帧 idle 同时要求窗口、response register 和 MSHR 排空。
- 记录最近一次已接受 commit 数据，保持 `valid=0` 时调试可见输出确定；有效协议仍只以 ready/valid 为准。

### 动态可重构取舍

- 曾实验用 raster active lane 数控制窗口深度，使 E 模式只启用 1 项。train n32 在 E 模式退化为 ideal 6979、limited 11409，而 2 项窗口为 4250/8665，性能损失过大。
- 在没有目标工艺库动态功耗证据前，G/P/R/E 四模式均保留 2 项窗口；动态可重构继续由投影、SH、raster lane mask 与 clock-enable 实现。未来若引入 state-window 深度寄存器，必须在 epoch-safe idle 边界提交并以 PPA 证明价值。

### 正确性与性能

- 新增 cache hit-under-miss 定向测试：older miss 占用 MSHR 时，带不同 slot tag 的 resident pixel hit 先返回，随后 older miss response 回到正确 slot。
- 原有四笔连续同像素测试通过，前到后结果依次保持 R=2048/3072/3584/3840、T=32768/16384/8192/4096；pruned alpha、commit 背压和 last-packet 边界也通过。
- train n32：ideal `5389 → 4250`（1.268×），limited `9807 → 8665`（1.132×）；commit=795、miss/read=537、write=795 和完整 frame-state 哈希均不变。
- 13 场景：ideal 加速范围 1.268×–1.290×，几何平均约 1.281×；limited 为 1.130×–1.135×，几何平均约 1.133×。全部 26 项 frame-state 与优化前逐位一致。
- limited 收益受单 MSHR 串行 miss 限制。该结果允许下一轮评估第二 MSHR 的收益/面积，但不能据此直接启用高风险多 miss 架构。

### 路线边界

- 本轮仍保持“深度分组 + Gaussian 有序发射 + Gaussian 内部 8×8 block 遍历”，没有 per-tile bin/list/sort。
- n32 是真实训练属性微负载，不是 PSNR/SSIM/LPIPS、最终完整帧率或 ASIC PPA。
- 所有负载和结果仅在 `D:/3DGS` 本地处理，没有上传网络。

### 最终回归与报告

- E 模式恢复为 2-entry 后，train n32 与 G/P/R 一致为 ideal 4250、limited 8665，active mode 仍正确提交；说明窗口深度不再人为抵消 E 模式的 lane/clock-enable 策略。
- 57 项 SystemVerilog 自检 + 1 项综合入口全部 PASS；bonsai n4 从上一轮 798 cycles 进一步降至 666 cycles，68 commits/reads/writes 与 frame-state 不变。
- Python unittest 增至 87 项并全部 PASS；新增 Phase A 结构合同覆盖 tagged response、单 MSHR、head/tail、有序 commit 与完整 key RAW CAM。
- Verilator 5.050 顶层 lint PASS，UNOPTFLAT=0、MULTIDRIVEN=0。当前剩余告警分类为 UNUSEDSIGNAL 84、WIDTHTRUNC 36、PINCONNECTEMPTY 36、WIDTHEXPAND 33、SYNCASYNCNET 2、UNUSEDPARAM 1；后续仍需逐项结合数值合同治理，不能批量屏蔽。
- 逐场景对比见 `experiments/rtl_workloads/all13_n32_phasea_window_comparison_2026-08-13.md`。

## 2026-08-13：Phase B 双 tagged MSHR 与 AXI 乱序读响应

### RTL 与协议实现

- image-state cache 从单 MSHR 扩展为两个按 1-bit slot tag 索引的 MSHR；不同像素 miss 可同时未决，response 按 tag 填回。完整 `{epoch,pixel}` RAW CAM 和 head-only ordered commit 保持不变。
- 新增 `axi4_pixel_state_dual_read_engine.sv`：最多两个单拍 AXI read outstanding，tag 映射到 `ARID[0]`，按 `RID` 接收乱序响应；每个 ID 有独立 response register。
- tag 贯穿 raster、ordered frontend、sorted/frame pipeline 和 system top。主路径仍为“深度分组 + Gaussian 有序发射 + Gaussian 内部 8×8 block 遍历”，没有 per-tile bin/list/sort。

### 调试与定向验证

- train n32 最初停在第 69 个 miss。追踪发现 testbench 的 1-bit 反向 tag 直接赋给 2-bit RID 时产生非法 `2'b10`；现显式构造 `{1'b0, tag}`，并将 AXI slave 改为 pending + 稳定 active R channel，仅在真实 R 握手后释放 pending。
- cache 定向测试覆盖双 miss、ID1 先返回、同 direct-map index 不同 tag、tag 未释放不得复用、hit-under-miss、错误响应，以及 fill/update 同周期时 architected update 获胜。

### 正确性、性能与 Go/No-Go

- train n32：ideal `4250 → 3707`（1.146×），limited `8665 → 6095`（1.422×）；commit=795、miss/read=537、write=795 和完整 frame-state SHA-256 与 Phase A 相同。
- 13 场景：ideal 几何平均 1.154×（1.138×～1.172×），limited 1.446×（1.411×～1.491×）。26 组输出全部与 Phase A 哈希一致，commit/miss/read/write 计数不变。
- 功能与真实微负载性能判定为 Go，Phase B 成为新的工艺无关 RTL 默认候选。最终 ASIC 保留仍需目标标准单元、SRAM 宏、PVT/RC 和活动文件下的 Phase A/Phase B PPA 比较。
- 详细报告：`experiments/rtl_workloads/all13_n32_phaseb_dual_mshr_2026-08-13.json` 和 `all13_n32_phaseb_dual_mshr_comparison_2026-08-13.md`。

### 回归状态与边界

- Icarus Verilog 12：58 项 SystemVerilog 自检 + 1 项综合入口 PASS；Python：87 项 unittest PASS。
- Verilator 5.050 顶层 lint PASS，UNOPTFLAT=0、MULTIDRIVEN=0；剩余分类为 UNUSEDSIGNAL 84、WIDTHTRUNC 36、PINCONNECTEMPTY 36、WIDTHEXPAND 33、SYNCASYNCNET 2、UNUSEDPARAM 1。
- n32 是真实训练属性 RTL 微负载，不是完整帧图像质量、最终帧率或 ASIC PPA。PSNR/SSIM/LPIPS 与具体工艺面积/功耗仍待后续环境。
- 全部文件仅在 `D:/3DGS` 本地读写，未上传网络或公开平台。

## 2026-08-14：Phase A/B 物理可综合回退、随机协议压力与质量评价入口

- 新增综合参数 `STATE_MSHR_COUNT=1/2` 并从 system top 贯穿到 raster cache；默认 2。单项配置生成独立 `image_state_cache_backend_single.sv` 和单 outstanding AXI reader，双项配置生成双 tagged cache 和乱序双 reader，因此后续 PPA 可比较实际物理结构。
- bonsai n4 回归：Phase A ideal/limited=666/1257，Phase B=596/915；commit/miss/read/write 与完整 frame-state 一致。G/P/R/E 动态配置仍保持 epoch-safe，MSHR 数量本身是综合常量，不在帧内切换。
- 新增 `tb_axi4_pixel_state_dual_read_random.sv`，固定种子覆盖 200 个随机背压/乱序事务、两 tag 公平使用、R 通道稳定、tag 生命周期、未知 RID 错误和最终排空；PASS，tag0/tag1 分别 99/101。
- 双 reader/cache 增加请求 tag、合法响应和未知 RID SVA。Icarus 回归增至 59 项自检 + 1 综合入口并全部 PASS；Python 增至 89 项 PASS；Verilator 顶层 lint PASS，UNOPTFLAT=0、MULTIDRIVEN=0。
- 新增 `prepare_rtl_quality_pairs.py`，与已有 decode/evaluate 脚本组成 state→PNG→PSNR/SSIM/LPIPS JSON/CSV 流程，并增加端到端自检。当前本机缺 torch/lpips/权重，且 `D:/3DGS/data` 不含参考照片；真实 LPIPS 和完整帧质量结果仍待本地输入与环境，不虚构数值。
- 规格见 `docs/PhaseA_PhaseB可综合回退与质量评价规格_v0.1.md`。全部工作仅在 `D:/3DGS` 本地完成，未上传网络或公开平台。

## 2026-08-14：Phase B 后端瓶颈探针与下一候选收敛

- 在真实负载 testbench 增加仅验证侧 `REAL_BACKEND` 和 `REAL_WINDOW_OPP`，统计2-entry blend window满载、0/1/2 MSHR占用、第三候选到达、完整key RAW、head阶段、AXI AR/R背压和reader/cache response背压；不修改综合RTL。
- 13场景26组 ideal/limited 全部PASS，完整frame-state在每个场景内一致。ideal聚合43240周期，第三候选等待30235周期（69.9%）；limited聚合72885周期，等待58392周期（80.1%）。
- n32中第三候选与两个在途slot的完整 `{epoch,pixel}` key均不同，RAW计数为0；这只是当前微负载现象，不允许删除RAW CAM。第三候选到达时双MSHR占满比例为ideal 24.9%、limited 57.4%。
- 单独4 MSHR判定No-Go：2-entry window没有第三事务，实测cache侧 `mshr_full_query_block=0`。单独4-entry window也判定No-Go：limited下会频繁把阻塞从alpha retire转移到已满MSHR，不能提高backing service rate。
- “4-entry window + 4 MSHR”判为Research-Go，不升级默认RTL。机会稳定存在，但必须同时扩展slot tag、完整key CAM、cache MSHR、AXI ID/response寄存器，并继续共享单blend core和head-only commit；先做实验分支和逐位验证，再依据收益/PPA决定。
- 所有reader/cache response背压为0，AXI AR背压仅limited聚合284周期；没有证据优先复制response端口。详细报告为 `experiments/rtl_workloads/all13_n32_phaseb_backend_probe_summary_2026-08-14.md`。
- 回归：Icarus 59项自检+1综合入口PASS，Python 89项PASS。主路径仍为深度分组、Gaussian有序发射和Gaussian内部8×8 block遍历，无per-tile bin/list/sort。
## 2026-08-14：4-entry有序窗口、4 MSHR与4-ID AXI实验配置

- 新增独立可综合`blend_state_commit_4.sv`：4-entry环形窗口、4路完整`{epoch,pixel}` RAW CAM、带2-bit tag的乱序state/blend回填、共享单blend core和head-only commit；没有复制alpha/blend算术阵列。
- 新增`image_state_cache_backend_4.sv`和`axi4_pixel_state_quad_read_engine.sv`：4个物理MSHR、4个AXI outstanding、RID乱序解复用和每tag响应寄存器。双/四reader同时收紧阻塞响应的payload稳定合同。
- 新增综合参数`STATE_WINDOW_ENTRIES=2/4`并贯穿system/frame/sorted/ordered/raster。合法物理组合限定为2+1、2+2和4+4；默认继续为2-entry+2-MSHR，4+4逻辑不进入默认generate分支。
- 三项定向自检PASS：4-entry窗口覆盖乱序返回、同像素四级RAW、wrap和满窗替换；4-MSHR cache覆盖3/1/2/0 fill、index冲突、错误和update优先；4-ID AXI随机覆盖500笔、随机背压、乱序RID和非法RID。
- 真实bonsai n4：默认2+2为ideal 596，4+4为ideal 430、limited 613；68次commit/read/write不变，672行frame-state逐位相同。
- 真实train n32：默认Phase B为3707/6095，4+4为2160/3525，分别1.716×/1.729×；commit=795、miss/read=537、write=795和frame-state SHA-256全部不变。
- 13场景n32共26项全部PASS：ideal几何平均1.726×、范围1.684×–1.764×；limited几何平均1.741×、范围1.680×–1.791×。13场景hash和全部architectural计数均与Phase B一致。
- Icarus完整回归为62项SystemVerilog自检+1综合入口PASS。Verilator默认和4+4顶层lint均PASS；4+4的UNOPTFLAT=0、MULTIDRIVEN=0、LATCH=0。
- 结论为性能Research-Go、默认暂不升级。必须等待目标工艺PPA验证4-entry寄存器/CAM与4-MSHR/4-ID成本；4+4后已出现0–97周期output stall，暂不继续盲目扩大状态并发度。
- 详细规格和决策见`docs/4-entry窗口与4-MSHR实验规格和Go-No-Go_v0.1.md`，原始矩阵见`experiments/rtl_workloads/all13_n32_4x4_2026-08-14.json`。主路径仍是深度分组、Gaussian有序发射和Gaussian内部8×8遍历，无per-tile bin/list/sort；全部数据只在D:/3DGS本地处理。

## 2026-08-14：Blend结果提交旁路与写回深度收敛

- 4+4研究配置新增可关闭的blend结果直达ring-head提交旁路；不复制算术核，
  下游背压时仍写slot并保持原有稳定输出合同。
- 在response旁路基线上，13场景ideal总周期22863降至21088（1.084x），
  limited从40466降至38052（1.063x）；全部计数和frame-state哈希一致。
- multiwrite深度8/12/16在常规limited下为6685/6683/6683周期，默认保持8；
  深度扩容仅对64周期B响应压力有显著作用。
- Icarus完整回归、Python 89项和Verilator 4+4双旁路lint通过；详细记录见
  `docs/RTL验证日志_2026-08-14_Blend提交旁路与写回深度.md`。

## 2026-08-14：动态Lane操作数隔离

- projection、SH、alpha三个真实调度器不再向全部物理lane广播变化packet，
  只向dispatch选中lane传递，其余输入保持0；GCC主路径与ordered retire不变。
- 4-lane train n128/8x4代理统计由6708次lane packet暴露降为1677次，避免
  75%；这不是SAIF/门级功耗结论。
- 完整Icarus、89项Python和Verilator参数化lint通过；周期和最终状态不变。
- 详细记录：`docs/RTL验证日志_2026-08-14_动态Lane操作数隔离.md`。

## 2026-08-14：完整帧Continuation与13场景容量规划

- 新增fresh/continuation/more-batches逻辑帧命令；中间批保持同一epoch和像素/
  termination状态，不产生外部done/IRQ，末批才完成。非法批次序列置错误bit18。
- 定向RTL证明第二批在第一批像素状态上继续blend；system/APB覆盖中间批、末批
  和孤立continuation。旧单批命令保持兼容。
- 13场景本地PLY扫描得到28,845,709个深度有效且定点可表示的规划Gaussian；
  group容量8/64/256的保守总批数分别为3,605,720/450,721/112,684，证明完整帧
  必须同时依靠continuation和容量安全的depth-pivot构造，不能只扩大buffer。
- 回归为62项SystemVerilog自检+1综合入口、93项Python和两组Verilator lint
  全部PASS；UNOPTFLAT/MULTIDRIVEN/LATCH/Error均为0。
- 当前仍不是完整帧画质结果，不报告PSNR/SSIM/LPIPS、完整帧FPS或ASIC PPA。
- 详细记录：`docs/RTL验证日志_2026-08-14_完整帧Continuation与容量规划.md`；
  原始容量报告：`experiments/full_frame_all13_execution_plan_2026-08-14.json`。

## 2026-08-14：完整帧有序批次索引与Mean DMA流

- 新增位精确批次生成器，按RTL Q16 camera depth与global GID排序，并构造
  4x256容量安全pivots；不使用per-tile数据结构。
- bonsai完整1,051,092项生成1030批，最大batch 1024、最大group 256，四组平均
  利用率99.656%；全部pivot重放和全局顺序检查通过。
- 生成8,408,736-byte depth/GID索引和16,817,472-byte 128-bit mean DMA流，
  manifest包含每批控制、offset、count、pivots和哈希；mean流重算RTL depth逐项一致。
- Python增至100项PASS；本子阶段没有修改RTL，上一阶段62项RTL+1综合入口及
  默认/4+4 Verilator lint仍有效。
- 详细记录：`docs/RTL验证日志_2026-08-14_完整帧有序批次索引与Mean流.md`。

## 2026-08-16：Sparse global-GID属性与真实continuation闭环

- 新增完整批次属性生成器，按真实global GID从PLY提取Mean、Scale、Quaternion、Opacity和degree-3 SH；每颗9个128-bit beat。RTL继续使用`ATTRIBUTE_BASE + global_GID×144`，紧凑slot只存在于testbench memory model。
- Bonsai首批1024颗global GID为7257–1241353、全部唯一，四个深度组均256颗；32条属性记录跨4 KiB边界。Python 102项、默认n4回归及Verilator默认/4+4 lint通过。
- 真实负载testbench支持可选第二批输入。Bonsai有序流前16颗的8+8 continuation保持epoch 1，中间批无done，最终15609 commits；与16颗单批的2752行frame state逐bit一致。continuation为19180 cycles，单批为18916 cycles，多264 cycles为批间控制开销。
- Icarus 1024颗长仿真约42分钟后无状态退出；Verilator旧ABI兼容构建后首次得到明确1亿周期timeout，定位`raster_pair_shell`把同拍commit和skip两项完成压成1 bit，泄漏888个inflight credit。现改为0/1/2 completion计数并增加同拍定向测试，n4和16颗continuation结果不变。
- 修复后Bonsai首批1024颗PASS：504984 cycles、315506 commits、2752 state reads、315506 writes；2752行frame SHA-256为`86A8CFD53AA878DE915A8FA1FFFB9E406C0BF8D4398AB8AA614D4F1F25C20B61`，Verilator walltime 23.930秒。
- 当前已收敛sparse global-GID、真实两批continuation和首批1024颗完整RTL正确性；batch 1、1030批完整帧、画质及具体工艺PPA仍待后续。详细记录：`docs/RTL验证日志_2026-08-16_SparseGlobalGID属性与Bonsai首批.md`。
## 2026-08-16：真实负载投影定点格式收敛

真实 Bonsai batch0 暴露的 projection/conic 主误差已完成闭环修复，详见：

```text
docs/RTL验证日志_2026-08-16_投影定点格式收敛.md
```

最终格式为：三维协方差 41-bit Q20.20、透视 Jacobian 34-bit Q*.16、屏幕协方差 35-bit Q27.8。batch0 内部软件浮点参考指标从 PSNR 18.2222 dB / SSIM 0.883964 提升至 47.0279 dB / 0.990241；Verilator 系统仿真、n4 ideal/limited、定向 RTL 和 Python 103 项回归均 PASS。数值无效项采用 ordered cull，不再伪装成全屏 Gaussian。
# 2026-09-09 开发环境恢复与验证基线重建

- 修复 `tb_screen_covariance_core.sv` 的 35-bit Q27.8 接口/饱和边界和 Q20.20
  单位协方差测试数据；修复 `tb_covariance3d_chain.sv` 的 Q20.20 期望值。
- 主数据通路 RTL 未修改；深度分组、Gaussian 有序发射、Gaussian 内部 8×8 block
  遍历及 G/P/R/E 架构合同不变。
- Python：103 tests PASS。
- Icarus：62 项自检 + 1 项综合入口编译 PASS。
- Verilator 5.050：`gs_accel_system_top` lint PASS（保留既有非致命警告）。
- 详细记录：`docs/RTL验证日志_2026-09-09_开发恢复与完整帧续跑.md`。

## 2026-09-17：ASIC 导向透明 Alpha 状态事务跳过

- 在有序 alpha 退休边界跳过未通过阈值的零权重 blend 与像素状态读写；主路径、
  G/P/R/E 及默认配置不变，候选由顶层编译参数控制。
- 当前源码 15 负载、360 次 DMA：候选 RGB/T 120/120 等价并均快于共享投影基线，
  n32 的 104/104 也快于未优化完全旁路；全矩阵平均少 28.100% 周期，少
  45,496 次状态读、72,688 次写。n128 d8 相对旁路仍不快。
- 两帧自动续跑图像等价，Python 158、Icarus 79 项与综合入口、默认/候选顶层
  lint 通过。无目标工艺 PDK/SRAM 与映射 PPA，候选仍默认关闭；详见
  `docs/RTL验证日志_2026-09-17_透明Alpha状态事务跳过.md`。

## 2026-09-19：恢复验收与联合剪枝消融

- 补齐 alpha 候选结构检查；新增五负载 200 次五路 DMA 对照，联合方案相对
  alpha-only 为 16/40 提速、24/40 持平、0 退化，平均额外省 0.787% 周期。
- 少做 2504 次 alpha 任务，额外状态读写减少为 0；alpha-only 不新增乘法 AST
  节点，联合方案增加一个，工艺 PPA 仍未签核。
- 自动两帧、Python163、联合顶层 lint 通过；RTL/testbench 未变，继承上一轮
  同源码 Icarus 证据。下一项 RTL 性能候选优先共享 G 稳定二分插入定位。
- 完整记录：`docs/RTL验证日志_2026-09-19_Alpha恢复与联合剪枝消融.md`。
