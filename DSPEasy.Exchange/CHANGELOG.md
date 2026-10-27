## 更新日志

### 0.5.3
- 插件 GUID 与显示名改为 `DSPEasy.Exchange`（原 `DSPMod.easyexchange`）：日志来源前缀变成 `[Info   :DSPEasy.Exchange]`，启动横幅是 `Loading [DSPEasy.Exchange 0.5.3]`，Harmony 实例 id 同步改名。
- **配置文件改名**：现在是 `BepInEx/config/DSPEasy.Exchange.cfg`（按插件 GUID 命名）。旧的 `DSPMod.easyexchange.cfg` 不再读取，热键 / 基价倍率 / 交易日志会回到默认值；想保留原来的设置，把旧文件重命名为 `DSPEasy.Exchange.cfg` 即可（配置键名没变）。
- 要求的框架版本仍是 `DSPEasy Framework 0.2.32`。

### 0.5.2
- 首次发布到 Thunderstore。
- 买入 / 卖出写入原版累计统计（分析面板 `P` 的「累计」列）：买入记「生产 + 整条中间产物链」，卖出记「消耗」；分钟/小时曲线不受影响。
- 购买行新增「买×1 / 买×一组 / 买×MAX」快捷按钮。
- EMC 余额与已解锁物品随存档保存（存档旁车 `<存档名>.mod.dat` 的 `EMC1` 块），读档自动恢复。
- 按资源分布整体重定基价（1 EMC ≈ 10 个常见矿）。
- `pricing.csv` 只把「基价」列当输入，其余列改为导出；旧格式表整列作废。
- EMC 兑换面板：热键 `K`；行点击买 1、`Shift` 点买一组；选择物品器（物品 / 建筑两页）与数量输入。
- 首个发布版本：EMC 定价引擎（资源基价 + 配方推导）与交易面板骨架。
