## 更新日志

### 0.2.33
- 修复与 CommonAPI 共存时整段注入被跳过：CommonAPI 会给不存在的物品 ID 返回共享的 `Unknown Item` 占位原型，原判据 `LDB.items.Select(SuperMiner) != null` 在注入前就恒为 true。改用 `LDB.items.Exist(SuperMiner)`（只查 `dataIndices`，不受该补丁影响）。
  - 现象：装 CommonAPI（MoreMegaStructure 等整合包的前置）后，科技树没有「改版建筑」，建造栏/制造界面看不到 11 座建筑，旧档物品显示 `Unknown Item`。
- 要求 `DSPEasy Framework 0.2.32`；本版随该框架重新构建，建筑面板使用新的轮询式 `UiDrag`。
- 增加对[更多巨构建筑模组](https://thunderstore.io/c/dyson-sphere-program/p/jinxOAO/MoreMegaStructure/)的兼容。

### 0.2.32
- 随 `DSPEasy Framework 0.2.32` 重编译，建筑功能无变化；该版本未单独发布，内容并入 0.2.33。

### 0.2.31
- 仅文档与版本号更新（Thunderstore 无法只刷新文档，因此补丁版本重发），功能与 0.2.30 完全一致。
- 补充收集 Issue 的 URL。

### 0.2.30
- 首次发布到 Thunderstore。
- 本版起的存档旁车是格式 2（按命名空间分区），旧档读取时自动升级，无需手动处理。
