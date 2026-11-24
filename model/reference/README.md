# FP32黄金参考模型

该目录保存不依赖CUDA的3DGS推理参考实现，用于冻结算法语义并为周期模型、定点模型和RTL提供对照。

当前支持：

- 3D协方差构造与透视投影；
- 常量RGB或0至3阶实球谐颜色；
- 深度稳定排序与分组；
- pixel-wise独立参考渲染；
- Gaussian-wise块级遍历；
- alpha剪枝、逐像素透射率和提前终止；
- 执行统计计数器。

运行本地测试：

```powershell
python -m unittest verification.test_reference_model -v
```

当前版本用于功能正确性，不代表最终硬件周期。粗分组、scoreboard并行和存储流量将在周期模型中继续细化。
