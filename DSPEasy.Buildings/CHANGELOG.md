## 更新日志

### 0.2.34
- 新增配置文件 `BepInEx/config/DSPEasy.Buildings.cfg`：**物品 ID（默认 `11500`–`11510`）与科技 ID（默认 `1999`）改成可覆盖**，和别的模组撞号时不用再等模组更新。
  - 首次启动自动按默认值生成，键名就是建筑中文名；改完重启游戏生效。
  - 注入前会检查越界、内部重复、与原版或其它模组已占用的 ID 冲突；有问题只报错并放弃注入（不做自动避让）——悄悄换 ID 会让存档里的建筑变成 `Unknown Item`。
  - **改 ID 的代价**：旧存档里已建好的本模组建筑会变成 `Unknown Item`、科技要重新研究。请先定好 ID 再开档。
- 修复多模组环境下「以为已注入、实际没注入」的误判：幂等判据改成按对象引用查当前物品表，别的模组占用同一 ID、或 CommonAPI 给未知 ID 返回的 `Unknown Item` 占位，都不会再被当成「本模组已注入」。
- 插件 GUID 与显示名改为 `DSPEasy.Buildings`（原 `DSPMod.easybuildings`）：日志来源前缀变成 `[Info   :DSPEasy.Buildings]`，启动横幅是 `Loading [DSPEasy.Buildings 0.2.34]`，Harmony 实例 id 同步改名。本模组此前没有自己的配置文件，这次改名不影响任何已有设置。
- 要求的框架版本仍是 `DSPEasy Framework 0.2.32`，本版随该框架构建。

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
