# 3DGS动态可重构ASIC完整RTL交付分解 v0.3

- 日期：2026-08-09
- 主数据流：深度分组 + Gaussian有序发射 + Gaussian内部8×8 block遍历
- 动态主线：epoch级G/P/R/E资源模式、长窗口建议、滞回和最短驻留

## 当前状态

| 子系统 | 状态 | 下一闭环 |
|---|---|---|
| APB配置、epoch提交 | 帧命令、sticky done/error、maskable IRQ完成 | 接入DMA状态与性能窗口 |
| 深度预处理、4组粗分组、组内稳定排序 | 已接入帧级完整计算链 | 扩展真实场景容量/DMA |
| 1/2/4 projection lane、有序退休 | RTL及测试完成，排序后属性AXI读取已接入 | 扩展属性cache/多outstanding性能版本 |
| degree-3 SH颜色 | 已与有序projection按完整身份标签汇合 | 真实场景RTL/定点逐Gaussian差分 |
| Gaussian内部block walker | RTL及测试完成 | 接入系统级有序主链 |
| 8×8到pixel展开 | RTL及测试完成 | 增加多block、多Gaussian系统测试 |
| termination、alpha、blend、图像状态 | 子链RTL及测试完成 | 扩展真实整图容量和写回 |
| G/P/R/E模式表、计数器、自动建议器 | projection/SH/Raster alpha真实启停；帧间安全应用 | 对group/sort和工艺时钟门控进一步落线 |
| AXI4 DMA、属性缓存、结果写回 | mean/GID读、完整属性读及有序像素状态写回已完成；cache待实现 | 下一阶段重点为真实分辨率state backing/cache |
| 排序后完整Gaussian至光栅提交 | request/response属性后端、AXI读取和提交写回完成 | 优化写合并并接真实负载 |
| 帧级完整计算数据通路 | `gaussian_frame_render_pipeline`闭环 | 接DMA和真实分辨率state backing store |
| 系统控制顶层 | `gs_accel_system_top`完成APB、双AXI读、AXI写回、状态/IRQ | 接state backing；旧`gs_accel_top`仅兼容保留 |
| PSNR/SSIM/LPIPS | Python参考基础已在 | 等完整定点/RTL帧输出后评测 |
| 具体工艺PPA | 等ASIC环境 | 需要节点、标准单元/SRAM库和综合功耗工具 |

## 强制架构约束

1. 不得引入Gaussian–tile KV/bin、逐tile Gaussian list和逐tile排序作为默认主路径。
2. 多projection lane可以乱序完成，但进入blend前必须恢复Gaussian sequence顺序。
3. SH颜色每Gaussian只计算一次，禁止放入逐block或逐pixel重复计算路径。
4. 固定模式与动态模式必须使用相同算术、存储格式和顺序合同；动态模式只改变物理资源启停、复用和调度权重。
5. 模式只能在受影响状态排空的epoch边界提交，并保留固定单lane公平基线。
6. 完整图像地址至少32位，不能把12位模块测试接口直接用于1080p等整图。

## 后续开发顺序

1. 实现AXI4读DMA、属性布局和结果写DMA，并增加支持真实分辨率的image-state backing store/tile cache。
2. 把DMA错误、完成和性能计数接入现有APB/IRQ合同。
3. 用13个场景生成定点/RTL整帧输出，完成PSNR、SSIM、LPIPS及性能计数分析。
4. 安装Verilator后补第二工具lint/SVA/仿真交叉验证。
5. ASIC环境就绪后，冻结具体工艺节点和频率约束，执行综合、SRAM映射、门级功耗和面积报告。
## 2026-08-09 状态更新

- 真实分辨率 image-state backing/cache 的 correctness baseline 已完成：直接映射片上 cache、AXI4 miss read、epoch lazy clear、write-through 和 B response 顺序门控。
- `STATE_ENTRIES` 不再限制 backing 模式整帧像素数；本地 SRAM 兼容模式仍保持容量保护。
- 当前回归为 50 项 SystemVerilog 自检 + 1 项综合入口编译、79 项 Python unittest，全部通过。
- 下一交付重点调整为真实场景 DMA memory image 与 RTL workload bridge、状态 cache/AXI 性能计数、13 场景逐帧定点输出和 PSNR/SSIM/LPIPS 闭环。
- PPA 仍需用户准备具体工艺节点、标准单元库、SRAM compiler/model 及综合/功耗工具后开展；当前不能给出可信工艺面积和功耗数字。

## 2026-08-09 真实场景 RTL workload bridge 更新

- 新增本地 PLY/camera 到 `mean.memh`、`attribute.memh`、`camera.memh`、manifest 和参数头文件的生成链。
- bonsai camera 146 的 4-Gaussian、32×21 真实属性微负载已贯通完整系统：1049 busy cycles、68 commits、68 state miss/read/write、201 state-read stall、0 output-commit stall，PASS。
- 修复投影 lane 对被裁剪 Gaussian 重复退休导致 inflight 计数下溢和 frame DRAIN 不结束的问题；退休现统一使用唯一的 backpressured last-beat 握手。
- 一键回归更新为 51 项 SystemVerilog 自检 + 1 项综合入口编译，全部 PASS；Python 为 81 项 unittest，全部 PASS。
- 当前结果属于“小型真实属性微负载”，不是完整场景性能或画质结果；采样器已改为跨 PLY batch 的固定种子 priority sampling，后续仍需深度/屏幕分层模式。
- 下一步先扩大真实负载和 AXI 延迟覆盖，再建立完整帧输出与 PSNR/SSIM/LPIPS 闭环；优化 state cache/写回结构必须由测得瓶颈驱动。

## 2026-08-09 多场景 AXI 敏感性更新

- 通用真实负载testbench已支持场景/相机/数量/尺寸加载、AXI延迟/空泡/ready占空比配置以及完整128-bit frame-state导出。
- bonsai、garden、train的8-Gaussian微负载在受限AXI下总周期约为理想AXI的2.01×、2.01×和2.08×，最终帧状态均逐位一致。
- 当前数据表明state backing延迟是明确的优化目标；下一轮优先评估cache命中提升、miss overlap和安全写合并，不应无依据地继续复制算术lane。
- 当前回归为51项SystemVerilog自检 + 1项综合入口编译、82项Python unittest，全部PASS。

## 2026-08-09 Pixel-State 写缓冲性能更新

- 唯一有序AXI writer前已增加默认8项commit FIFO和完整32-bit pixel hazard比较，不复制blend/state writer。
- 不同pixel的state miss可越过旧写响应等待，同pixel仍严格等待，保持前到后图像状态正确性。
- 三场景微负载获得1.26×–1.46×加速，周期下降20.7%–31.3%，state-read stall降为0。
- 优化前后frame-state逐位一致；主路径仍是深度分组、Gaussian有序发射和Gaussian内部8×8遍历。
- 当前全量回归为52项SystemVerilog自检 + 1项综合入口编译、82项Python unittest，全部PASS。

## 2026-08-09 Buffer/Cache 参数收敛

- 写缓冲深度2/4/8/16在正常和64周期B响应压力下总周期相同；默认深度从8降为2，payload位数下降75%，不损失性能。
- 三场景连续同pixel commit机会为0，暂不实现无收益的相邻写合并。
- train n32中512项cache相对32项在limited AXI下获得1.14×加速、状态读减少26.5%；说明cache容量有效，但最终4096项默认值仍需完整场景和SRAM宏PPA确认。

## 2026-08-09 Dirty Pixel Write-Back 决策

- 已完成可参数化全相联dirty pixel write-back RTL、queued/active状态前递、满缓冲驱逐与frame flush，且保留write-through兼容路径。
- train n32/cache512下，depth128将片外写次数从795降到658（17.2%），并由系统级路径前递3次cache miss；完整frame-state与write-through逐位一致。
- 单未决AXI writer导致frame尾部flush串行化，depth128的ideal/limited总周期反而增加9.7%/6.5%。因此默认保持2-entry write-through，不把无端到端性能收益的结构设为主配置。
- write-back模块作为未来多未决/突发写研究基础保留。该选择不改变深度分组、Gaussian有序发射、Gaussian内部8×8遍历及epoch级动态重构主线。
- 当前回归为53项SystemVerilog自检 + 1项综合入口编译、82项Python unittest，全部PASS。

## 2026-08-09 AXI4 多未决写性能版

- 完成同ID有序B回收、AW/W独立握手、完整pixel hazard CAM和满环同周期回收/补入的可综合多未决写模块。
- train n32/cache512在ideal/limited下相对单未决路径获得1.03×/1.09×加速，output stall降为0；64周期B压力下8项版本获得7.44×加速。
- 15份write-through/multiwrite输出完整frame-state逐位一致；确定性测试和96事务随机scoreboard均PASS。
- 默认切换为8项多未决writer；深度参数等待完整场景和目标工艺PPA最终冻结。
- 当前回归为55项SystemVerilog自检 + 1项综合入口编译、82项Python unittest，全部PASS。
