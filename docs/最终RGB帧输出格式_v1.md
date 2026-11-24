# 最终 RGB 帧输出格式 v1

本文件冻结 T04 的一种最小完整成品帧格式。生产默认启用
`gs_accel_system_top.USE_FINAL_RGB_DMA=1`。

## 地址与容量

- `OUTPUT_BASE` 必须 16 Byte 对齐，指向最终 RGB888 图像首字节。
- 行跨度 `stride = align16(width * 3)`；图像占用 `stride * height` Byte。
- RTL 内部 16 Byte/像素的 RGB/T/epoch 状态位于
  `OUTPUT_BASE + stride * height`，主机须在同一外存分配中继续预留
  `width * height * 16` Byte scratch；scratch 不是成品输出。
- RGB 行尾填充字节由 RTL 写为 0。像素按行优先，像素内字节顺序为 R、G、B。

## 颜色合同

- 内部累积颜色为无符号 Q12；最终先执行
  `C_final = saturate_q12(C + T * background)`，再以
  `round_half_up(C_final * 255 / 4096)` 饱和到 8 bit。
- v1 生产默认背景固定为黑色 `(0,0,0)`；RTL 参数保留静态背景色验证能力，
  不在本任务扩展运行时多格式/多背景寄存器。
- scratch 记录的 epoch 不等于当前帧 epoch 时，该像素视为未触及并直接输出背景；
  正常连续帧无需逐帧清空 scratch。首次分配 scratch 时须初始化 epoch 标签为 0（可全区清零）；
  复位或 epoch 回绕造成标签复用前亦须清除旧标签。任意未初始化内存可能恰好匹配当前 epoch，
  不能承诺对该内存自动识别未触及像素。真实场景验收采用首次全零 scratch。

## AXI 与完成语义

- scratch 读取为 128-bit 单拍；RGB 写按最多 15 个 128-bit beat 形成 INCR burst。
- 任一写 burst 都不会跨越 4 KiB 边界；地址、数据和响应均支持独立背压。
- 中间 continuation 批次只保留状态，不启动最终 RGB DMA。最终批次在渲染写回与
  状态请求完全排空后启动扫描。
- `DONE`、done IRQ 与外部 `frame_done_pulse_o` 必须等待最后一个 RGB 写响应 B 完成。
- `ERROR_STATUS[22]` 为最终 DMA 配置错误，bit23 为读响应/协议错误，bit24 为写响应错误。
  错误仍形成可轮询的完成事件。

## 主机读取示例

主机从 `OUTPUT_BASE` 读取 `stride * height` Byte 后，只做容器封装：

```powershell
python scripts/read_rgb888_frame.py frame.rgb frame.png --width 1920 --height 1080 --metadata frame.json
```

脚本不读取 scratch，也不重新执行背景合成、量化或渲染。
