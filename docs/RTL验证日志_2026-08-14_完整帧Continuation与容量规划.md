# RTL验证日志：完整帧Continuation与容量规划

日期：2026-08-14

## 1. 本轮目标

结束缺少工艺证据的局部性能优化，转入13个真实训练场景的完整帧执行基础设施。
主路径保持GCC式“深度分组 + Gaussian有序发射 + Gaussian内部8x8 block遍历”，
不引入per-tile bin/list/sort。

## 2. 真实规模扫描

新增`scripts/plan_full_frame_execution.py`，只读取`D:/3DGS/data`本地PLY和相机，
不上传数据。报告为`experiments/full_frame_all13_execution_plan_2026-08-14.json`：

- 13场景源Gaussian总数39,781,233；
- 中间相机下，深度有效且定点可表示的规划数量合计28,845,709；
- 单场景约926,606--4,672,750；
- 全局GID需要20--23 bit，现有顶层默认32 bit足够；
- 规划mean stream合计约461.5 MB；原始GID dense attribute地址空间约5.73 GB；
- 64最大边长下13帧128-bit pixel state合计550,912 byte；
- 当前Q5.12/18-bit SH范围扫描没有发现需要饱和的值。

保守批次保证一个批次即使全部落入同一coarse group也不会溢出：

| group容量 | 13场景总批数 | 单场景范围 |
|---:|---:|---:|
| 8 | 3,605,720 | 115,826--584,094 |
| 64 | 450,721 | 14,479--73,012 |
| 256 | 112,684 | 3,620--18,253 |

因此不能把8-entry微负载结构直接称为完整帧架构，也不能仅靠盲目增大buffer。
后续需要continuation流和容量安全的depth-pivot/group构造共同工作。

屏幕中心候选只作诊断，绝不用于完整帧剔除；中心在屏幕外的大Gaussian仍可能
覆盖图像，真正screen/bbox cull继续由RTL projection路径完成。

## 3. RTL continuation命令

`apb_regfile`新增`CONTROL[3] continue`、`CONTROL[4] more_batches`和
`STATUS[6] frame_open`。

`gs_accel_system_top`新增逻辑帧状态：

- fresh首批创建render epoch；
- continuation保持epoch、pixel state和termination状态；
- 中间批全部内部/AXI状态排空，但不产生外部done/IRQ；
- 末批才关闭逻辑帧并产生done/IRQ；
- continuation性能计数接续累积，fresh首批清零；
- 孤立continuation或逻辑帧打开时错误fresh start置`ERROR_STATUS[18]`；
- 首批锁存输出基地址和图像宽高，continuation配置不一致时拒绝并置bit18；
- 任一中间批发生错误都会强制关闭逻辑帧并报告，不允许带错继续。

`gaussian_frame_render_pipeline`的continuation直接进入collect，不触发mode commit，
因此不会递增epoch或逻辑清除像素状态。当前同一逻辑帧内冻结G/P/R/E模式；动态
模式仍在逻辑帧安全边界切换。帧内批间动态模式若要实现，必须另行解耦配置版本
与render epoch，不能为了“动态”破坏画面状态。

## 4. 正确性验证

- frame pipeline定向TB：两批渲染同一Gaussian，第二批epoch不变，并观察到参与
  blend的未饱和像素颜色严格大于第一批，证明不是新帧重置；
- system/APB TB：中间批无done/IRQ、`frame_open=1`；末批epoch不变并正常done；
  逻辑帧关闭后的孤立continuation置bit18；
- Icarus Verilog 12：62项SystemVerilog自检 + 1项综合入口PASS；
- Python：新增容量规划边界测试后93项PASS；
- Verilator 5.050：默认2+2和4+4+双旁路+operand isolation参数化lint均PASS；
  两组`UNOPTFLAT/MULTIDRIVEN/LATCH/Error`均为0。

关键日志：

- `tmp/continuation_system_iverilog_2026-08-14.log`；
- `tmp/continuation_python_2026-08-14.log`；
- `tmp/continuation_verilator_default_2026-08-14.log`；
- `tmp/continuation_verilator_4x4_2026-08-14.log`。

## 5. 当前边界与下一步

本轮完成的是完整帧所需的控制语义和真实规模容量证据，不是完整帧渲染结果。
尚不能报告PSNR、SSIM、LPIPS、完整帧FPS或具体工艺PPA。

下一步按顺序实现：

1. 容量安全的全局深度有序批次生成器，保留原始global GID；
2. 批次DMA memory image与manifest，记录首/续/末批标志和哈希；
3. 小分辨率完整Gaussian集合的跨批RTL执行及位精确定点frame-state对拍；
4. 在可信FP32参考输出到位后运行PSNR/SSIM，并在本地LPIPS依赖/权重准备后补LPIPS；
5. ASIC工艺库和综合环境到位后再进行ICG、STA、面积和功耗裁决。
