# APB 帧命令、状态与中断规格 v0.1

- 日期：2026-08-09
- 系统控制顶层：`rtl/gs_accel_system_top.sv`
- 状态：工艺无关 RTL 与 APB 端到端自检查完成

## 1. 系统边界

`gs_accel_system_top` 将 APB 寄存器与 `gaussian_frame_render_pipeline` 相连，形成软件可启动、轮询、清错和中断通知的完整计算系统边界。相机参数已由 `CAMERA_BASE` 驱动的 AXI4 DMA 装载；当前以下端口仍显式暴露，作为兼容或后续替换缝隙：

- 完整 Gaussian 属性装载端口；
- mean/GID 深度预处理输入流；
- 最终像素提交输出流。

生产默认不再依赖测试平台直接注入相机矩阵；静态 `cfg_*` 端口只在
`USE_AXI_CAMERA_DMA=0` 兼容配置中使用。

## 2. 命令语义

`CONTROL`：

- bit0 `START`：单周期帧启动请求。空闲时快照全部命令字段，读取并校验相机描述符后启动新批次；busy 时拒绝新请求并记录 busy-start 错误。
- bit1 `SOFT_RESET`：单周期计算核心复位并清 sticky status/IRQ pending；APB 地址、尺寸、模式与 IRQ enable 配置保持。
- bit2 `STATUS_CLEAR`：清 done、error status 和 IRQ pending，不复位计算核心。

同时写多个命令位时，soft reset禁止同周期start进入计算核心；状态清除与帧完成同周期时，新的完成事件优先保留，避免丢中断。

## 3. STATUS

| 位 | 字段 | 说明 |
|---:|---|---|
| 31:16 | EPOCH | 当前active帧epoch |
| 5 | IRQ | 最终外部IRQ电平 |
| 4 | ERROR | error status非零 |
| 3 | MODE_OVERRUN | 帧错误位7的快捷镜像 |
| 2 | MODE_PENDING | 已有下一帧动态模式建议，或底层模式提交尚未完成 |
| 1 | DONE | 帧完成sticky |
| 0 | BUSY | 帧级数据通路非IDLE |

已有 `0x000–0x028` 地址保持兼容；扩展寄存器位于 `0x02C–0x07C`。`0x038 GAUSSIAN_COUNT`给出mean/GID记录数，`0x03C/0x040`给出属性数组基址。

## 4. 中断

```text
irq = (done_pending & done_enable) |
      (error_pending & error_enable)
```

- 正常帧完成：设置 done sticky 与 done pending。
- 错误帧完成：设置 done sticky、done pending、error status和error pending。
- IRQ enable只控制外部电平，不阻止pending记录。
- 软件写 `CONTROL.STATUS_CLEAR` 统一应答当前事件。
- 当前采用单加速器、单未决完成模型；下一帧开始前软件应清除上一帧状态。

## 5. 模式控制

手动模式下，写 `MODE[1:0]` 更新shadow模式，bit8产生运行时提交请求。为避免半帧
切换或冻结未排空sorter，该请求只在下一帧START时与新epoch原子生效。

`AUTO_MODE(0x044)`：

| 位 | 字段 | 说明 |
|---:|---|---|
| 0 | AUTO_ENABLE | 1启用自动建议器；0采用软件shadow模式 |
| 1 | RECOMMENDATION_VALID | 建议器请求或已接收队列有效 |
| 3:2 | RECOMMENDED_MODE | 当前请求或已排队的G/P/R/E模式 |
| 5:4 | WINDOW_WINNER | 最近完成统计窗口的winner |
| 6 | REQUEST_OUTSTANDING | 建议器内部请求等待顶层接收 |
| 7 | MODE_PENDING | 建议已排队或底层模式提交尚未完成 |

自动建议器只在计算核心busy时推进统计窗口，空闲间隔不会虚增驻留时间。建议被顶层接收
后保持为单未决队列；当前帧和逻辑continuation期间active模式保持不变，下一新帧才提交。
关闭自动模式会清空建议器状态，并用软件shadow模式覆盖尚未生效的自动推荐。

`0x048–0x060` 给出最近完整窗口的原子快照：窗口编号，以及 group pressure、sort busy、
projection busy、raster busy、block candidate 和 terminated skip 六个 32 位计数。所有字段
在窗口结束的同一时钟沿更新。软件读取时应执行 `index → 六项计数 → index`，两次 index
一致才接受该样本；编号按32位自然回绕。该接口用于解释推荐原因和离线校准权重，
不参与渲染数据通路。

`0x064–0x07C`给出当前逻辑帧共享PE的G/P/R grant、G/P/R stall和总utilization七个32位
饱和计数。新帧启动时清零，continuation不清零；它们是实时帧计数，不采用advisor窗口的
双读快照协议。当前G连接稳定排序比较、P连接相机Z深度预处理及主投影XYZ MAC，R未接入时应保持0。
可选并行排序候选新增的本地比较器不进入上述共享计数：G grant减少不能解释为总排序工作
减少，utilization也不能解释为整个混合阵列利用率。2026-09-14候选增加独立原子排序快照：

| 地址 | 字段 |
|---|---|
| 0x080 | 读快照序号；低byte写bit0 capture、bit1 rebase；其余写位忽略 |
| 0x084 | 只读capabilities：bit0候选存在，bit1单调检测可用，bit2计数可用；默认/legacy为0 |
| 0x088 / 0x08c | shared比较 / local比较（包含collect检测） |
| 0x090 / 0x094 | 网络交换 / 奇偶阶段（不计serial搜索） |
| 0x098 / 0x09c | 退休group / serial fallback group |
| 0x0a0 / 0x0a4 | 阶段旁路授权 / 阶段旁路失败 |
| 0x0a8 / 0x0ac | serial移动记录数 / collect检测比较 |
| 0x0b0 / 0x0b4 | fast group / reverse group |

12项均为32-bit模计数的区间差值。新逻辑帧接受start时更新base并清快照/序号，continuation
保持，STATUS clear不清测量状态，soft reset清零。capture在APB控制pulse被system消费的
时钟沿锁存全部字段，取该沿前raw-base值，之后读数冻结直到再次capture。rebase只改变
后续测量基线，不改变旧快照/序号；capture+rebase同次写先锁旧区间，再更新base。
新帧start或soft reset与capture重合时，清测量状态优先。计数不饱和、不提供溢出告警，
测量区间必须短于单字段2^32事件才能解释绝对总量。

软件写0x080后需等待pulse消费（APB写完成后至少一个核心沿），然后读seq→12字段→seq；
两次序号一致才接受，防止其他控制者重新capture或新帧start。只读寄存器写入忽略；
计数窗口只接受4-byte对齐地址，未对齐/越界仍PSLVERR。bit1代表编译可用，不代表当前
E模式启用检测；local/collect含工作次数，不能直接换算面积/功耗。

2026-09-14稳定run候选补充：shared比较包含逆序前缀末项的最大键验证及二分定位，
不再仅表示网络/serial比较。reverse group包含稳定相等键段的反向遍历，以及逆序
前缀配合末项插入；并不意味着逐记录反转。fast group仍在组最后一项实际退休时计数。
非单调两方向均已失效时停止collect检测，因此collect不必等于每组保留项数减一。

## 6. 验证

`tb_gs_accel_system_top` 完整通过 APB 事务验证：

1. 配置64×48小图、E模式和done/error IRQ enable；
2. APB START后完成真实一颗Gaussian的完整渲染；
3. 检查STATUS epoch/done/IRQ、IRQ_STATUS和外部IRQ；
4. CONTROL clear后检查sticky状态及IRQ下降；
5. 配置65×64超出4096项image-state容量；
6. 检查容量错误位、ERROR状态以及done/error两个pending；
7. 再次clear并确认错误与IRQ消失；
8. 启用自动模式，以真实投影/光栅/块事件形成推荐；
9. 验证当前帧active模式不变、推荐保持未决，并在下一新帧epoch边界精确提交。
10. 通过APB读取真实流水线产生的非零窗口编号与六项原子事件快照；
11. 以三个64-cycle窗口分别验证G/P/R/E及均衡事件负载的分类、滞回和无效切换抑制。
12. 读取共享PE计数，确认一颗实际渲染Gaussian产生12次P grant（预处理3次、主投影9次）、
    0次R grant且utilization一致。

## 7. 后续

主投影MAC已接入共享P客户端，三场景矩阵确认与后续组G比较形成真实竞争。下一阶段先恢复
串行prepass/compare造成的吞吐损失，再接入R客户端；继续使用`0x064–0x07C`观测服务分配。
之后才重新运行固定G/P/R/E与自动
模式矩阵并校准评分。任何资源复用都必须保持有序退休与framebuffer逐bit一致。
