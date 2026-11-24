# Phase A / Phase B 可综合回退与质量评价规格 v0.1

## 1. 目标与不变量

`STATE_MSHR_COUNT` 是编译/综合参数，只允许 1 或 2，默认值为 2：

- 1：Phase A，生成一个物理 MSHR 和单 outstanding AXI reader；
- 2：Phase B，生成两个 tagged MSHR 和双 outstanding、支持乱序 RID 的 AXI reader。

两种配置均保留 2-entry ordered pixel-state window、完整 `{epoch,pixel}` RAW CAM、head-only commit 和共享 blend core。参数不改变深度分组、Gaussian 有序发射或 Gaussian 内部 8×8 block 遍历，也不引入 per-tile bin/list/sort。

该参数不是帧内动态寄存器。G/P/R/E 仍在安全 epoch 边界动态切换 lane mask 和 clock-enable；MSHR 数量只在综合时选定，避免帧内改变状态容量产生无法排空的协议风险。

## 2. 物理生成路径

- Phase A cache：`rtl/raster/image_state_cache_backend_single.sv`，仅一份 pixel/epoch/slot-tag miss metadata。
- Phase B cache：`rtl/raster/image_state_cache_backend.sv`，两份按 slot tag 索引的 metadata。
- Phase A reader：`rtl/dma/axi4_pixel_state_read_engine.sv`。
- Phase B reader：`rtl/dma/axi4_pixel_state_dual_read_engine.sv`。
- system top 和 raster pair 均用 generate 选择对应物理模块，确保后续同工艺 PPA 对比不是逻辑屏蔽后的伪对比。

真实负载矩阵参数为 `--state-mshr-count {1,2}`，JSON 明确记录 `state_mshr_count`。bonsai n4 验证结果：Phase A ideal/limited 为 666/1257，Phase B 为 596/915，最终 frame-state 一致。

## 3. 协议验证

新增随机双 reader 压力测试，固定种子执行 200 个事务，覆盖：

- AR 和下游 response 的随机背压；
- 两 ID 同时 outstanding；
- ID1 先于 ID0 返回；
- RVALID/RID/RDATA 在背压期间保持；
- tag 未退休不得复用；
- unknown RID 错误捕获；
- 全部事务最终排空且请求/响应一一对应。

RTL SVA 继续检查 AR/RSP 稳定性、tag 空闲后才能接收请求、合法响应必须命中已发出 MSHR、未知 RID 必须置错。

## 4. 完整图像质量评价入口

现有 `decode_rtl_frame.py` 将 128-bit state 中的 Q1.12 RGB 解码为 PNG。新增 `prepare_rtl_quality_pairs.py`：

1. 接收 `(名称, frame_state.memh, manifest.json, reference.png)`；
2. 要求参考图尺寸与 RTL manifest 严格一致，不做隐式缩放或裁剪；
3. 生成同名 reference/candidate PNG 和 `pairs.json`；
4. 使用 `evaluate_image_quality.py` 输出逐图与平均 PSNR、SSIM、LPIPS JSON/CSV。

示例：

```powershell
python scripts/prepare_rtl_quality_pairs.py `
  --entry train150 frame_state.memh manifest.json reference.png `
  --output-root experiments/full_frame_quality
python scripts/evaluate_image_quality.py `
  experiments/full_frame_quality/reference `
  experiments/full_frame_quality/candidate `
  --lpips --output experiments/full_frame_quality/metrics.json
```

当前 bundled Python 可计算 PSNR/SSIM，但缺少本地 `torch`、`lpips` 和模型权重；`D:/3DGS/data` 也没有原始参考照片。因此接口与自检已完成，真实完整帧数值必须等本地参考图或浮点参考输出以及 LPIPS 环境就绪后运行。禁止下载、上传或虚构结果。
