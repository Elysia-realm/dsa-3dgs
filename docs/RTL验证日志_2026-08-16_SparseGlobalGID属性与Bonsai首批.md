# RTL验证日志：Sparse Global-GID属性与Bonsai首批

日期：2026-08-16

## 1. 目标与边界

本轮把完整帧深度/GID索引接到真实属性DMA和RTL验证，继续保持既定主路径：

`深度分组 → Gaussian有序发射 → Gaussian内部8×8 block遍历`

没有增加per-tile bin、per-tile list或per-tile sort。G/P/R/E仍在安全epoch边界改变真实projection、SH和raster lane启用；4-lane、4-entry window、4-MSHR、双旁路和operand isolation仅作为研究配置。

全部输入、日志和结果只在`D:/3DGS`本地处理，没有上传网络或公开平台。

## 2. Sparse global-GID属性后端

- 新增`scripts/build_full_frame_rtl_batch.py`，从完整深度/GID索引提取指定批次，并从原始训练PLY按global GID提取Mean、Scale、Quaternion、Opacity和degree-3 SH。
- 每颗Gaussian生成9个128-bit属性beat；输出`mean.memh`、`global_gid.memh`、`attribute_sparse.memh`、`camera.memh`和manifest。
- RTL地址合同保持`ATTRIBUTE_BASE + global_GID × 144`。紧凑slot映射只存在于验证侧AXI memory model，不把global GID重映射成局部GID，不改变综合RTL语义。
- Mean和attribute DMA已修正为支持global GID和跨4 KiB边界的属性记录。
- testbench AXI B response从累计数组索引改为有界环形outstanding队列，消除长负载验证环境假溢出；不修改硬件写回协议。

Bonsai batch 0包含1024颗Gaussian，global GID范围7257–1241353，全部唯一；pivots为14112/14891/15502，四组均为256颗，32条属性记录跨4 KiB边界。

## 3. 回归结果

- Python全量回归：102项PASS（修改continuation合同测试后为103项，需可用Python/NumPy环境复跑确认）。
- 默认n4真实DMA：596 cycles、68 commits、68 state reads/writes，PASS；证明sparse模式没有破坏旧局部GID路径。
- Verilator 5.050默认和4+4参数化顶层lint均PASS；只有既有warning，无Error、LATCH、UNOPTFLAT或MULTIDRIVEN新增失败。

主要日志：

- `tmp/python_sparse_batch_full_2026-08-16.log`
- `tmp/sparse_tb_default_compile_2026-08-16.log`
- `tmp/sparse_tb_default_run_2026-08-16.log`
- `tmp/sparse_global_gid_verilator_default_2026-08-16.log`
- `tmp/sparse_global_gid_verilator_4x4_2026-08-16.log`

## 4. 真实跨批continuation验证

`tb_real_dma_workload.sv`新增可选第二批输入：`MEAN2/ATTR2/GLOBAL_GIDS2/CAMERA2`。默认单批行为不变。两批模式检查：

- fresh首批带`more_batches`，中间批不得产生done；
- 中间批结束后logical frame保持打开；
- 第二批用continue启动并保持相同epoch；
- 最后一批才关闭logical frame并产生done；
- pixel state与termination状态跨批保持；
- 两批Mean/attribute beat总数严格匹配。

定向结果：

1. n4+n4：epoch保持1，136 commits，状态继续累积，PASS。
2. Bonsai真实有序流前16颗、原始32-bit global GID、目标4+4研究配置：8+8 continuation为19180 cycles、15609 commits、2752 state reads、15609 state writes，PASS。
3. 同16颗一次性单批（容量16）为18916 cycles、相同15609 commits；两种执行的2752行`frame_state.memh`逐bit一致，different pixels=0。
4. continuation多264 cycles，属于额外批次collect/drain和APB控制开销；没有数值或顺序变化。
5. 误用group/sort容量8执行16颗单批时正确置`ERROR_STATUS=0x2`，证明容量保护生效；提高黄金单批容量到16后通过。

相关日志：

- `tmp/continuation_two_batch_smoke_2026-08-16.log`
- `tmp/global_cont_4x4_run_2026-08-16.log`
- `tmp/global_single16_4x4_run_2026-08-16.log`

## 5. 1024颗长仿真、根因修复与最终结果

Icarus专用1024颗batch 0仿真运行约42分钟，持续消耗CPU且没有RTL错误输出，但随后进程在无stdout/stderr、无frame文件、无Windows应用崩溃记录的情况下消失。因此该次执行不能记为PASS，也没有证据记为RTL `$fatal`。

该结果说明Icarus不适合作为1030批完整帧主执行器：单批需要几十分钟且当前没有checkpoint/restart。

把同一SystemVerilog testbench构建为Verilator本地二进制时发现并解决：

- 将验证侧B队列从默认16384编译为64后，Verilator可生成C++；
- UCRT64 GCC 16默认C++11 ABI链接当前libstdc++时缺少`std::__cxx11::basic_string`的C4 ABI符号；
- 通过仅对工程内Verilator模型统一加入`_GLIBCXX_USE_CXX11_ABI=0`成功链接，不安装或更新软件；
- n4 Verilator得到596 cycles/68 commits，672行frame-state SHA-256与Icarus逐bit相同，执行walltime约0.008秒；
- 1024/4+4专用模型构建成功。第一次持久执行达到1亿RTL周期timeout：全部1024 Mean、9216属性beat、315506 commits、2752 state reads和315506 writes均完成，但`raster inflight_count=888`，其余front/alpha/blend/cache/AXI全部排空；
- 根因是`raster_pair_shell`将独立的正常commit和termination-filter skip用逻辑OR合成一个`task_complete`。两者同拍时实际完成2项但只减1个credit；首批恰好漏记888次；
- 修复为0/1/2 completion计数，并增加commit+skip同拍定向用例和credit不下溢断言。n4和真实16颗continuation周期、计数、frame-state均不变；
- 修复后1024颗首批PASS：504984 cycles、315506 commits、2752 state misses/reads、315506 writes，Mean=1024、attribute=9216；无disabled-lane issue；
- 最终frame为2752行，SHA-256为`86A8CFD53AA878DE915A8FA1FFFB9E406C0BF8D4398AB8AA614D4F1F25C20B61`；Verilator脚本walltime 23.930秒（Verilator自报22.815秒）；
- 新增`scripts/build_verilator_real_workload.ps1`固化参数化生成、旧ABI兼容编译和链接步骤；`scripts/run_bonsai_batch0_verilator.ps1`固化首批输入、日志、status与walltime记录；
- lint和二进制运行均正常，最初问题局限于本机C++链接ABI，不是RTL elaboration错误。

没有擅自联网更新MSYS2。当前旧ABI兼容构建足以继续本地验证；后续可再把工具链包版本同步作为环境维护项，而不是当前RTL正确性的前置阻塞。

## 6. 当前结论与下一步

已经证明：sparse global-GID真实属性读取、真实两批continuation控制、epoch保持、像素状态累积、最终逐bit等价和首批1024颗完整RTL均正确；真实长负载还发现并修复了短回归未覆盖的双完成credit泄漏。主数据流和动态可重构目标没有变化。

尚未完成：

- 真实batch 1属性生成与1024+1023连续执行；
- 全1030批完整帧、PNG解码和PSNR/SSIM/LPIPS；
- 具体工艺节点面积与功耗。

优先级应为：生成真实batch 1并完成1024+1023两批长验证；之后实现可恢复批次执行器，最后推进完整帧和图像质量。不得以减少Gaussian、局部GID重映射或改变GCC式数据流伪造完整帧闭环。
