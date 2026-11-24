# 帧级 Gaussian-wise 完整数据通路与控制合同 v0.1

- 日期：2026-08-09
- 状态：工艺无关 SystemVerilog RTL 已实现并通过本地自检查
- 顶层：`rtl/gaussian_frame_render_pipeline.sv`

## 1. 实现范围

本阶段把此前独立验证的计算阶段封装为一个帧级数据通路：

```text
frame start / epoch prepare
→ mean-only depth prepass
→ 4组粗深度分组
→ 组内稳定排序(depth, GID, sequence)
→ 按排序后GID读取一次完整Gaussian属性
→ 动态projection + 每Gaussian一次SH
→ Gaussian内部8×8 block/pixel遍历
→ 动态多alpha + 有序blend/image-state提交
→ 全链排空 / frame done
```

主路径没有 Gaussian–tile KV/bin、per-tile Gaussian list 或 per-tile 排序。本模块是完整计算数据通路顶层，不包含 AXI4 burst DMA、APB SoC 外壳、中断控制器或外部帧缓冲写回。

## 2. 帧控制状态

| 状态 | 含义 | 可接收源Gaussian |
|---|---|---|
| `FRAME_IDLE` | 等待合法帧启动 | 否 |
| `FRAME_PREP` | 原子提交本帧模式并递增epoch | 否 |
| `FRAME_COLLECT` | 接收mean/GID，执行深度预处理并收集分组 | 是 |
| `FRAME_DRAIN` | 分组、排序、属性读取和渲染全链排空 | 否 |

`frame_done_pulse` 只有在 grouper、sorter 和完整渲染链均排空后产生。`source_last` 随最后一个输入 Gaussian 握手进入深度预处理；即使最后一项被 near/far 剔除，也会可靠触发分组结束。

## 3. 帧epoch与图像状态

每个合法 `frame_start` 都会执行一次 epoch 提交，即使资源模式与上一帧相同。这样 image state 和 termination state 的 epoch tag 在帧间必然改变，旧帧 RGB、透射率和终止状态不会被新帧继承。

第一颗 Gaussian 只能在 `mode_commit_pulse` 之后被接受，所以本帧所有 projection、block、pixel 和 blend 标签使用同一个新 epoch。

## 4. 动态重构合同

- `frame_mode` 指定本帧启动模式。
- 帧内 `runtime_mode_valid/runtime_mode` 只锁存推荐模式，不立即冻结 sorter 或切换资源。
- 锁存的推荐模式在下一帧启动时，与新 epoch 原子应用。
- 多次帧内推荐采用最后一次写入值。
- 该策略避免 sorter 尚有待发记录时渲染入口冻结造成死锁，也避免半帧改变资源配置。
- Projection、SH 与 Raster alpha active mask 继续遵循统一 G/P/R/E 表。

## 5. 图像状态容量合同

当前 `STATE_ENTRIES=4096` 是片上 image-state 工作集容量，pixel ID 仍保留 32 位完整线性地址和完整 tag。由于尚未实现外部帧缓冲回写/回填，必须满足：

```text
image_width × image_height <= STATE_ENTRIES
```

超容量帧在启动周期立即产生完成脉冲和错误位 9，不接收 Gaussian、不允许低位地址别名后静默输出错误图像。后续支持 1080p/真实整图必须实现片上 tile cache 与外部 backing store，或实例化足够容量的 SRAM 宏。

## 6. 帧错误位

| 位 | 错误 |
|---:|---|
| 0 | depth prepass 数值溢出 |
| 1 | coarse depth group 容量溢出 |
| 2 | stable sorter 容量溢出 |
| 3 | 属性读取 GID 越界 |
| 4 | 属性未加载 |
| 5 | 属性写入 GID 越界 |
| 6 | ordered-retire / sequence 协议错误 |
| 7 | 底层模式重复提交/overrun |
| 8 | busy 期间重复 frame start |
| 9 | 图像像素数超过片上 state 容量 |

错误状态在下一次合法帧启动时清零。发生属性未加载或越界时，相应 Gaussian 被消费但不会把未定义属性发往渲染链；帧仍安全排空并以 error 状态完成。

## 7. 验证证据

### 7.1 完整数据流

`tb_gaussian_frame_render_pipeline` 反序输入同深度 GID 2→1，验证组内稳定键使整帧提交严格变为 GID 1→2；每颗 Gaussian 只触发一次属性读取，并覆盖输出背压。

测试在第一帧中请求 E 模式，确认当前 R 模式不发生半帧切换；第二帧启动时 E 模式与 epoch 2 原子生效。第二帧逐像素结果与第一帧同一 Gaussian 的首次贡献一致，证明图像状态按 epoch 逻辑清空。

### 7.2 错误与安全终止

`tb_gaussian_frame_error_control` 覆盖 busy 时重复启动、未加载属性不进入 raster、错误帧安全完成，以及 65×64 大于 4096 项状态容量时立即拒绝。

## 8. 后续工作

1. 用该计算顶层替换旧 `gs_accel_top` 的早期 raster 子集，建立 APB 命令、done/error/interrupt 寄存器合同。
2. 实现 Gaussian 属性 AXI4 burst 读 DMA 和帧结果写 DMA。
3. 增加 tile cache/backing-store 机制，使 image state 支持 1080p 等真实分辨率。
4. 接入 13 个真实场景的整帧输入/输出，完成 PSNR、SSIM、LPIPS。
5. Verilator 可用后补 lint、非 `SYNTHESIS` SVA 和第二仿真器交叉验证。
