# DSPEasy · 戴森球计划模组

给 **戴森球计划（Dyson Sphere Program）** 做的一组模组，发布在 Thunderstore：

| 包 | 做什么 | 当前版本 | 依赖 |
| --- | --- | --- | --- |
| [DSPEasy Framework](https://thunderstore.io/c/dyson-sphere-program/p/Suntion/DSPEasy_Framework/) | 其它 DSPEasy 模组共用的框架：按命名空间隔离的旁车存档、面板基座、配方求解等。本身不含玩法 | `0.2.32` | BepInEx 5.4.17 |
| [DSPEasy Buildings](https://thunderstore.io/c/dyson-sphere-program/p/Suntion/DSPEasy_Buildings/) | 11 座独立于原版的超级建筑：采矿机、制造机、充电桩、发电机、炮台、传送带、分拣器、研究站、黑箱超市、电磁-火箭发射器、太空防卫站 | `0.2.33` | BepInEx 5.4.17 + DSPEasy Framework |

> **这不是源码仓库。** 模组本体闭源，这里只放**发布用的包文件**（DLL、图标、manifest、包页 README）和**问题反馈入口**。

## 这个仓库做什么

1. **收 Issue** —— Bug、崩溃、兼容性问题、玩法建议，都提到本仓库的 **Issues** 标签页。
2. **打包发布** —— 每个子目录就是一个 Thunderstore 包的内容，改完版本号重新打包、上传。

不在这里处理：游戏本体的 Bug、其它作者模组的问题、模组源码。

## 安装

推荐用 **r2modman** 或 **Thunderstore Mod Manager**（[下载](https://get.thunderstore.io/)）：选 `Dyson Sphere Program` 社区，搜 `DSPEasy`，装 `DSPEasy Buildings` 时会把 Framework 和 BepInEx 一起装上。

手动安装：

1. 装 **BepInEx 5.4.17（x64，Mono）**——游戏是 Unity Mono 运行时，**不要**装 IL2CPP 版。
2. 两个包各解到一个自己的文件夹里，不要直接摊在 `plugins/` 根下：

   ```text
   BepInEx/plugins/DSPEasy_Framework/DSPEasy.Framework.dll
   BepInEx/plugins/DSPEasy_Buildings/DSPEasyBuildings.dll
   ```

3. 启动游戏，打开 `BepInEx/LogOutput.log`，能看到两个插件依次加载成功即可。

> ⚠️ **`BepInEx/plugins/` 下只能有一份 `DSPEasy.Framework.dll`。**
> BepInEx 会递归加载所有 DLL，每一份都会建立自己的静态注册表；有了两份，一份写进去的存档数据另一份读不到，表现就是「设置存了，重进游戏全没了」。升级时把旧副本删干净。

## 反馈问题（Issue）

开 issue 前先搜一下有没有重复的；一个 issue 只讲一个问题，标题写清模组名 + 现象。

请尽量带上这些信息：

```text
游戏版本：        主菜单右下角，如 0.10.35.29151
模组版本：        Thunderstore 页面 / manifest.json 里的 version_number
复现步骤：        1. … 2. … 3. …
期望结果 / 实际结果：
BepInEx 日志：    BepInEx/LogOutput.log（整份贴，别只贴最后一行）
截图 / 存档：     能复现的存档请把 .dsv 和同名 .mod.dat 一起打包
```

几个能少走弯路的点：

- 先说清楚**只装 DSPEasy 模组时能不能复现**，这能直接排除大半兼容性问题。
- 日志开头那几行有游戏版本、BepInEx 版本、插件列表，很关键，别裁掉。
- 建筑相关的问题，请说明是否已研究「改版建筑」科技、建筑是否通电网。
- 崩溃请贴完整调用栈，不用截图日志。

**关于 Pull Request**：模组功能改动没法合（闭源，源码不在这里）；README、manifest、发布文档的错别字与修正，欢迎直接 PR。

## 兼容性

| 项目 | 支持情况 |
| --- | --- |
| 游戏 | `0.10.35.29151`（Unity 2022.3.62f3c1，64 位） |
| BepInEx | `5.4.17`（x64 / Mono） |
| 旁车存档格式 | `2`（能读格式 `1`，旧档读取时自动升级） |

- 只支持 64 位 Windows + Mono 版 BepInEx。
- 存档设置写在存档旁边的 `<存档名>.mod.dat` 里，**不进 `.dsv`**。备份或迁移存档时请把 `.dsv` 与 `.mod.dat` 成对复制。
- 建筑设置会随原版蓝图一起保存；**对方没装本模组时粘贴蓝图会丢建筑或报错**，这是已知限制。
- Buildings 只用 `11500`–`11510` 物品段，配方 ID 自动找空位；与其它新增物品的模组冲突时请发日志。

## 发布流程（维护者）

### 包内文件

每个包目录就这四样，打包时全部放在 zip 的**根目录**（不能套一层文件夹）：

| 文件 | 说明 |
| --- | --- |
| `manifest.json` | Thunderstore 元数据：`name` / `version_number` / `website_url` / `description` / `dependencies` |
| `icon.png` | 256×256 PNG |
| `README.md` | Thunderstore 包页正文 |
| `*.dll` | 插件本体 |

两条硬规则：

- `name` 不要随便改——改名等于新包，订阅、依赖字符串、下载量都会断。
- `version_number` 是 `x.y.z` 语义化版本，**同一版本号不能重复上传**，改完必须升版本。

### 步骤

1. 改该包 `manifest.json` 的 `version_number`，同步更新包内 `CHANGELOG.md`（包页 README 不再单独放更新日志）。
2. 如果 Framework 升版：把 `DSPEasy.Buildings/manifest.json` 里的 `Suntion-DSPEasy_Framework-x.y.z` 改成新版本，两个包一起发（先 Framework，后 Buildings）。
3. 重新打包：

   ```powershell
   Compress-Archive -Path .\DSPEasy.Framework\DSPEasy.Framework.dll, .\DSPEasy.Framework\icon.png, .\DSPEasy.Framework\manifest.json, .\DSPEasy.Framework\README.md -DestinationPath .\DSPEasy.Framework\DSPEasy.Framework.zip -Force

   Compress-Archive -Path .\DSPEasy.Buildings\DSPEasyBuildings.dll, .\DSPEasy.Buildings\icon.png, .\DSPEasy.Buildings\manifest.json, .\DSPEasy.Buildings\README.md -DestinationPath .\DSPEasy.Buildings\DSPEasy.Buildings.zip -Force
   ```

   > 别图省事写 `.\DSPEasy.Framework\*`——目录里已经有上一版的 zip，会被一起打进包里。

4. 上传 zip 到 Thunderstore，确认依赖能正确解析。
5. 提交 git（zip 不入库），打 tag 示例：`Framework-0.2.32+Buildings-0.2.33`。

## Git 约定

- **`*.dll`、`*.png` 标为 binary**（`.gitattributes`）。这两个格式一旦被 Git 当文本处理，Windows 上的 CRLF 转换会直接改坏字节，diff 也没有意义。
- **`*.zip`、`*.7z` 不入库**（`.gitignore`）。包是 DLL + 图标 + manifest + README 现场打出来的，每次重打内容都会变，进 git 只会制造噪音；发布走 Thunderstore，不靠仓库分发。

## 许可

仓库内的文档、manifest、打包配置按 **MPL-2.0** 发布，见 [LICENSE](LICENSE)。模组本体为闭源分发，仅提供编译后的 DLL，源代码不在本仓库。
