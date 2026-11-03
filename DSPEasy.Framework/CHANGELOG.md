## 更新日志

### 0.2.35
- 新增 `PanelFrame` / `PanelHost` 面板基座：统一标题栏、贴边/居中锚点、拖动提示与关闭按钮，并提供 `KeepOnScreen` 把面板夹在根画布的可见区域内。Buildings、Exchange 与 Starport 的面板已迁移到这套基座。
- 新增 `ItemPickerFilter`：统一物品选择器的白名单与页签过滤；依赖方可以只显示指定物品，同时保留自己的专属页签（例如「改版建筑」）。
- 新增 `SaveLifecycle`：旁车存档的载入、写出、重置钩子只安装一份，多个模组各自注册命名空间；`ModSave.RegisterLegacyNamespace` 可把旧命名空间登记为别名，旧存档读取时自动迁移。
- `AbnormalityGuard.Install()` 与 `BlueprintChannel.Install()`：异常拦截与蓝图 `content` 通道补丁由依赖方显式安装一次，重复调用不会重复挂载。
- 新增 `ProfilerModule` 统一性能统计节点声明、`FrameworkLog` 统一框架诊断日志出口；`UiDrag` 增加 `KeepOnScreen`。
- 依赖本框架的面板模组需一起升级才能拿到新的面板夹取与选择器过滤。

### 0.2.34
- 新增 `DSPEasy.Framework.Diagnostics`：模组注册后，可在原版「分析面板 → 性能测试 → CPU」列表末尾按「模组 → 建筑/功能 → 主要逻辑」三级显示每帧平均耗时与占比。
- 统计只在分析面板打开、且勾选了「实时检测」时采样；面板关闭或取消勾选后不产生额外开销。

### 0.2.33
- 内部重构：拆分 `ModSave` 旁车读写源文件，**公开 API、旁车存档格式与运行时行为不变**。

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
