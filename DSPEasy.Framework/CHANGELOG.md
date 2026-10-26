## 更新日志

### 0.2.32
- 面板拖动改为轮询式：`UiDrag` 按鼠标左键逐帧推动窗口，命中判定用画布的 `eventCamera`，口径对齐原版 `UIWindowDrag`；修掉 Screen Space - Camera 画布下「点不中、拖不动」。
- 新增 `UiFactory.CanvasCamera`：按画布渲染模式返回正确的换算相机（Overlay 为 `null`，其它用画布相机），避免 `RectTransformUtility` 命中算偏。
- `UiFocus` 抽出 `TopmostIs`：只认射线命中的最上层控件，点在别的窗口上不会再误提本面板或误触拖动。
- 依赖本框架的面板模组需一起升级才能拿到拖动修复；`DSPEasy Buildings 0.2.33` 已按本版本重编译。

### 0.2.31
- 仅文档与版本号更新（Thunderstore 无法只刷新文档，因此补丁版本重发），功能与 0.2.30 完全一致。
- 补充收集 Issue 的 URL。

### 0.2.30
- 首次发布到 Thunderstore。
- 旁车存档为格式 2：块头带命名空间，一个命名空间的数据不会被其它模组的重写覆盖；写入有全局锁与 `.tmp` 原子替换。
