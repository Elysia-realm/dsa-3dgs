# 排序后 Gaussian 属性读取与渲染集成规格 v0.1

- 日期：2026-08-09
- 状态：工艺无关 RTL 已实现并通过自检查
- 主路径：深度分组与组内稳定排序 → GID/sequence → 完整属性读取 → projection/SH → Gaussian 内部 8×8 block → raster

## 1. 设计目的

深度预处理和排序只搬运 `depth/GID/sequence/group` 元数据，不复制约 1118 bit 的完整 Gaussian 属性。排序结果按 GID 对完整属性执行一次读取；属性进入 projection/SH 原子 fork 后，由该 Gaussian 的全部 block 和 pixel 复用。设计不生成 Gaussian–tile KV，不建立 per-tile Gaussian list，也不执行 per-tile 排序。

## 2. 属性格式与存储映射

默认完整属性宽度为：

```text
geometry = 3×27-bit world mean + 4×22-bit quaternion
         + 3×24-bit scale + 13-bit opacity = 254 bit
appearance = 3×16×18-bit SH = 864 bit
total = 1118 bit/Gaussian
```

`gaussian_attribute_store` 在逻辑上分成 geometry 和 appearance 两个 1R1W bank。当前使用工艺无关 `sram_1r1w_wrapper`，一周期同步读、同址读写 write-through；ASIC 综合时应继续把两个逻辑 bank 切分成目标工艺可用的窄 SRAM 宏，保持外部时序合同不变。

GID 采用 frame-local dense 编号，合法范围为 `[0, ATTR_DEPTH)`。不得只截取 GID 低位形成别名。帧加载开始时用 `clear_valid` 清空有效位，不复位 SRAM 数据本身；每个成功写入的 GID 被置为 loaded。

## 3. 有序读取合同

`ordered_gaussian_attribute_issue` 首版只允许一个 outstanding read，以最小控制逻辑保证：

- SRAM 请求与 `depth/GID/sequence/group/first/last` 一一对齐；
- 下游背压期间完整属性和 metadata 保持稳定；
- 后一个 GID 不越过前一个 GID；
- 每个被接受的排序项只产生一次属性读脉冲；
- 越界或未加载 GID 被消费但不发射未定义属性，并置 sticky error。

sticky error 必须由最终帧控制器转换为错误中断或 frame-failed 状态，禁止静默提交错误帧。当前集成层已暴露这些错误信号，完整命令 FSM 尚待实现。

## 4. 动态重构安全边界

模式切换请求到达的同周期，集成层立即停止接受新的 sorted item。若已有一个属性读取事务，则先让它送入旧 epoch 的渲染前端；只有属性 issue 为空后，才把 commit 请求转发给 projection/SH/raster 内部 epoch 控制器。后者继续等待 projection lane、SH FIFO、block walker、pixel、alpha/blend 和提交状态全部排空，然后原子更新 active mode 和 epoch。

因此一次 Gaussian 不会跨越动态配置 epoch，也不会因“前端先 pending、属性响应后到达”形成死锁。重复 commit 会置 `mode_overrun`。

## 5. 当前性能边界

该版本每周期最多启动一次读，但仅维持一个 outstanding transaction，优先建立正确性基线。后续若真实场景表明属性 SRAM 延迟或带宽成为瓶颈，可在不改变顺序合同的情况下加入 2–4 深度 metadata FIFO、多个顺序 outstanding read，或将 geometry/SH bank 并行预取。任何优化都必须继续维持“一 Gaussian 一次属性加载”和 epoch 排空语义。

## 6. 验证覆盖

- 多地址属性写后读与 geometry/SH bank 对齐；
- 同地址 read/write write-through；
- clear-valid、越界写、越界读、未加载读；
- 排序顺序 GID 3→1→7、sequence/group metadata、下游背压稳定；
- 越界与未加载项不发射；
- 完整链中一个 GID 只读一次属性，产生 4 个 8×8 block 和 225 个有效像素提交；
- 渲染中请求模式切换，确认属性 issue 与整个渲染后端排空后才进入下一 epoch。

