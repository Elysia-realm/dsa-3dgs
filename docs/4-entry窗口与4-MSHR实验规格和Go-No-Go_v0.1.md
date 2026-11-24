# 4-entry窗口与4-MSHR实验规格和Go/No-Go（v0.1）

## 1. 设计边界

本实验配置只扩展像素状态后端的可并发事务数，不改变主数据流。主路径仍为：

1. 深度分组；
2. 组内稳定排序与Gaussian有序发射；
3. 每个Gaussian只读取一次完整属性；
4. Gaussian内部8×8 block遍历；
5. alpha、前到后blend、termination与有序写回。

没有加入per-tile bin、per-tile list或per-tile sort。G/P/R/E模式及其epoch-safe lane mask、clock-enable也保持不变。

## 2. 综合配置

新增综合参数`STATE_WINDOW_ENTRIES`，允许的物理组合只有：

- `2-entry window + 1 MSHR`：Phase A回退配置；
- `2-entry window + 2 MSHR`：默认Phase B；
- `4-entry window + 4 MSHR`：本报告实验配置。

非法的2+4、4+1、4+2组合由RTL elaboration assertion拒绝。三个配置通过generate选择独立物理模块，4+4寄存器和CAM不会进入默认2+2综合网表。

## 3. 4+4微架构

- 4-entry环形有序transaction window；
- 每slot保存完整`{epoch,pixel}` key、metadata、颜色/alpha、旧state和blend结果；
- query选择最老且不存在older完整key RAW hazard的slot；
- 4路完整key CAM始终保留；
- state response和blend response携带2-bit slot tag，可乱序回填；
- 仍共享一个blend core，不复制乘法阵列；
- 只有ring head的DONE事务可以commit和更新architected state；
- 允许满窗口时commit与新alloc同周期替换；
- cache含4个物理MSHR，tag未释放前不得复用；
- AXI reader支持4个outstanding，`ARID[1:0]=tag`，按RID乱序返回；
- cache和window边界仍保留单response端口。此前13场景探针的response背压为0，没有证据支持复制端口。

## 4. 定向验证

### 4-entry窗口

`tb_blend_state_commit_4.sv`覆盖：

- 四个不同像素连续进入；
- state response按3、1、2、0乱序返回；
- younger先完成也不能越过head提交；
- 四笔相同像素严格RAW串行，结果为R=2048/3072/3584/3840、T=32768/16384/8192/4096；
- head/tail环形回绕；
- commit背压下payload稳定；
- 满窗commit+allocation同周期replacement。

### 4 MSHR cache

`tb_image_state_cache_backend_4.sv`覆盖四miss并存、3/1/2/0乱序fill、相同direct-map index冲突、epoch失配、错误响应、tag生命周期，以及fill/update同周期时较新的architected update获胜。

### 4-ID AXI reader

`tb_axi4_pixel_state_quad_read_random.sv`固定种子运行500笔事务，四个tag分别覆盖123/126/126/125笔（最终回归附近的确定性分布），覆盖随机AR/R/consumer背压、乱序RID、偶发错误、非法高位RID和最终排空。

同时收紧双/四reader：当下游阻塞已可见response时，不接收会以更低固定优先级tag抢占当前payload的R beat，从而严格保持ready/valid稳定。

## 5. 真实训练属性n32微负载

13场景、每场景ideal/limited共26项全部PASS。4+4与默认Phase B逐场景比较：

| Profile | Phase B总周期 | 4+4总周期 | 几何平均加速 | 单场景范围 |
|---|---:|---:|---:|---:|
| ideal | 43,240 | 25,029 | 1.726× | 1.684×–1.764× |
| limited | 72,885 | 41,843 | 1.741× | 1.680×–1.791× |

全部场景的commit、state miss、AXI state read和state write计数与Phase B一致。26项ideal/limited frame-state在场景内一致，且13场景SHA-256均与Phase B一致。

train n32代表项：

- Phase B：ideal 3707，limited 6095；
- 4+4：ideal 2160，limited 3525；
- 加速：1.716×、1.729×；
- commit=795、miss/read=537、write=795均不变；
- 四份frame-state SHA-256均为`F771C1FE4FEAE4858AD191C6F20CAFD2A8BD9C0C1EAA8FBE6BB4907E606E2634`。

详细原始结果：`experiments/rtl_workloads/all13_n32_4x4_2026-08-14.json`。

## 6. 决策

功能正确性和微负载性能结论为Research-Go，但暂不替换默认Phase B。

原因：

- 收益跨13场景稳定且数值显著，值得进入PPA比较；
- 4-entry metadata/state寄存器、4路CAM、4 MSHR及4-ID response寄存器必然增加面积和动态功耗；
- 当前缺少目标工艺标准单元库、SRAM macro、PVT/RC和活动文件，不能合理量化性能/功耗/面积综合收益；
- 4+4后部分场景出现52–97周期output stall，瓶颈开始下移到共享blend/有序写回附近，继续扩大window/MSHR不再合理。

因此默认仍为`STATE_WINDOW_ENTRIES=2, STATE_MSHR_COUNT=2`。待具体工艺PPA完成后，再用性能/面积、性能/功耗与时序裕量决定是否升级。

## 7. 适用边界

n32结果是真实训练属性驱动的RTL微负载，不是完整帧图像质量、最终FPS或ASIC PPA。它不能替代PSNR、SSIM、LPIPS，也不能用于虚构某工艺节点的面积和功耗。全部数据仅在`D:/3DGS`本地处理，未上传网络或公开平台。
