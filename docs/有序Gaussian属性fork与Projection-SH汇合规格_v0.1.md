# 有序Gaussian属性fork与Projection-SH汇合规格 v0.1

- 日期：2026-08-09
- 主路径：深度分组、Gaussian有序发射、Gaussian内部8×8 block遍历
- 禁止路径：Gaussian–tile KV/bin、逐tile Gaussian list、逐tile排序

## 1. 完整属性事务

排序后每个Gaussian形成一个完整事务：

`{epoch, GID, sequence, world mean, quaternion, scale, opacity, 48个SH系数}`。

其中`{epoch,GID,sequence}`同时进入projection和SH支路，是两支路汇合的完整身份标签。epoch在Gaussian被源端接受时冻结，不能在后续block或pixel阶段读取当时的全局活动epoch替代。

## 2. 原子fork

`gaussian_projection_sh_fork`由两个等深ready/valid FIFO组成。只有projection FIFO和SH FIFO均有空间时，源Gaussian才显示ready；源端一次握手必定同时写入两个副本。

两支路之后独立背压：projection可以比SH快，SH也可以比projection快。任一支路暂时停顿不会造成另一支路重复接受，也不会丢失完整属性记录。当前深度为4，属于短期解耦缓冲，不是按tile建立的属性缓存。

## 3. Projection与SH汇合

- projection使用现有1/2/4 lane阵列，可以乱序完成；
- `ordered_gaussian_retire`先恢复Gaussian输入顺序，并保证同一Gaussian的block连续输出；
- SH颜色结果按输入顺序进入FIFO；
- `ordered_projection_sh_join`比较完整`{epoch,GID,sequence}`，匹配后才输出；
- SH FIFO头部颜色在当前Gaussian全部block期间保持不动，只在其last block或cull被下游接受时弹出；
- 因而每Gaussian只做一次SH，RGB复用于自身全部block，年轻Gaussian不得越序进入blend。

## 4. 动态模式与epoch安全

模式commit提出后立即停止接受新Gaussian。commit必须同时满足：

1. 外部声明epoch boundary；
2. 属性fork已排空；
3. projection lane与ordered-retire已排空；
4. SH结果FIFO和当前Gaussian block已排空；
5. pixel、alpha、blend和termination后端已排空。

只有全部条件成立才更新active mode和epoch。固定模式与动态模式使用完全相同的算术和事务顺序，动态模式只改变已实例化projection资源的启用数量；SH/R真实多lane启停仍是后续阶段工作。

## 5. 新增RTL

- `rtl/common/rv_fifo.sv`
- `rtl/projection/gaussian_projection_sh_fork.sv`
- `rtl/projection/ordered_projection_sh_join.sv`
- `rtl/projection/gaussian_projection_sh_array.sv`
- `rtl/projection/ordered_gaussian_block_decoder.sv`
- `rtl/gaussian_ordered_render_frontend.sv`

`gaussian_ordered_render_frontend`目前从排序后的完整Gaussian属性开始，已贯通projection、SH、block、pixel、alpha、blend和termination。深度分组/排序到完整属性读取、AXI4 DMA、整帧命令和图像写回仍不在该封装内。

## 6. 验证合同

- fork测试覆盖两支路分别停顿、FIFO满、顺序和完整排空；
- join测试覆盖一个颜色连续复用三个block、last弹出、cull、背压稳定；
- 双projection lane测试覆盖两个Gaussian、每个4个block、不同SH颜色以及Gaussian严格有序；
- 完整链测试覆盖一个Gaussian产生4个block和225个有效像素，所有提交保持GID/sequence/epoch，且处理中请求的模式切换直到最后一个pixel排空后才提交。

当前验证仍是有代表性的解析Gaussian，不是13场景整帧RTL渲染。完整图像PSNR、SSIM和LPIPS必须等待DMA/属性读取/帧写回闭环后执行。
