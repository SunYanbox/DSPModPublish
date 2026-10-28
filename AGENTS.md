## 开发规范

提交：中文提交消息，遵循**约定式提交规范**，遵循"单一职责"原则（文档和相关代码视为同一主题，可以一起提交），**每个 commit 只包含一个逻辑变更/一个主题**。

## 发布流程

### 包内文件

每个包目录就这几样，打包时全部放在 zip 的**根目录**（不能套一层文件夹）：

| 文件 | 说明 |
| --- | --- |
| `manifest.json` | Thunderstore 元数据：`name` / `version_number` / `website_url` / `description` / `dependencies` |
| `icon.png` | 256×256 PNG |
| `README.md` | Thunderstore 包页正文 |
| `CHANGELOG.md` | 包页「更新日志」标签的内容；不要在 README 里再写一份 |
| `*.dll` | 插件本体 |

三条硬规则：

- `name` 禁止修改。
- `version_number` 是 `x.y.z` 语义化版本，**同一版本号不能重复上传**，改完必须升版本。
- 包内 `CHANGELOG.md` / `README.md` 是**给玩家的页面**：读者只有「上一版 + 这个页面」，我们的讨论、被否决的方案、代码内部结构他都看不到。所以 `CHANGELOG` 每条只能是「**相对上一个已发布版本**，玩家能观察到什么不同」，不得写入任何其他的上下文、判断、决策——备选方案与取舍理由、讨论中改过又推翻的配方/数值、代码里才有的名词（类名/字段名/克隆/注入这类实现细节）、还没做的计划。写进去就是**悬空引用**。`README` 只写当前状态（现在时），不写「本版/这次/后续会加」，历史变化一律只进 `CHANGELOG`。**写完逐条复查**：这句话离开我们的对话还成立吗？它引用的名词/编号/版本读者能找到吗？答不上就删。

### 步骤

1. 改该包 `manifest.json` 的 `version_number`，同步更新包内 `CHANGELOG.md`（包页 README 不再单独放更新日志）。
2. 如果 Framework 升版：把 `DSPEasy.Buildings` 与 `DSPEasy.Exchange` 的 `manifest.json` 里的 `Suntion-DSPEasy_Framework-x.y.z` 改成新版本，三个包一起发（先 Framework，后两个玩法包）。
3. 打包并上传到 GitHub Release：Actions →「打包并发布 Release」→ Run workflow。

   - 先在 Releases 页面新建一个**草稿** Release，把这次要发的 `*.dll` 全部拖进它的 assets。表单不能选文件，这个草稿 Release 就是 DLL 的上传区，工作流按 release id 走 API 取回。
   - `projects` 填 `auto`（默认）就按 DLL 文件名自动对上包目录（`DSPEasy.Buildings.dll` → `DSPEasy.Buildings`）；也可以填 `all` 或直接写包目录名。名字对不上时用 `mapping` 逐行指定 `dll文件名=包目录名`。
   - Release 的 tag 由各包 `manifest.json` 的 `version_number` 自动算出（如 `Framework-0.2.33+Buildings-0.2.36`）。tag 已存在会直接报错，不会悄悄覆盖。
   - 第一次跑建议勾 `dry_run`，只打包不写 Release，看 Artifacts 和运行摘要；`publish` 取消勾选则上传后留作草稿。
   - zip 里只有 `manifest.json` / `icon.png` / `README.md` / `CHANGELOG.md` / `*.dll`，全部在根目录。

4. 从 Release 取同名 `.zip` 上传到 Thunderstore，确认依赖能正确解析。
5. 提交 git（zip 不入库）。

> 工作流不可用时才本地手动打包，注意别写 `.\DSPEasy.Framework\*`——目录里已有上一版 zip，会被一起打进包里：

   ```powershell
   Compress-Archive -Path .\DSPEasy.Framework\DSPEasy.Framework.dll, .\DSPEasy.Framework\icon.png, .\DSPEasy.Framework\manifest.json, .\DSPEasy.Framework\README.md, .\DSPEasy.Framework\CHANGELOG.md -DestinationPath .\DSPEasy.Framework\DSPEasy.Framework.zip -Force

   Compress-Archive -Path .\DSPEasy.Buildings\DSPEasy.Buildings.dll, .\DSPEasy.Buildings\icon.png, .\DSPEasy.Buildings\manifest.json, .\DSPEasy.Buildings\README.md, .\DSPEasy.Buildings\CHANGELOG.md -DestinationPath .\DSPEasy.Buildings\DSPEasy.Buildings.zip -Force

   Compress-Archive -Path .\DSPEasy.Exchange\DSPEasy.Exchange.dll, .\DSPEasy.Exchange\icon.png, .\DSPEasy.Exchange\manifest.json, .\DSPEasy.Exchange\README.md, .\DSPEasy.Exchange\CHANGELOG.md -DestinationPath .\DSPEasy.Exchange\DSPEasy.Exchange.zip -Force
   ```
