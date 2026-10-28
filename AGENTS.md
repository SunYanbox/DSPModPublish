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
   - GitHub 建 Release 必须给 tag（API 的 `tag_name` 是必填，网页不填就报「tag name can't be blank」）。草稿的 tag 只是占位：在 tag 输入框里敲 `draft`，选「Create new tag: draft on publish」即可。占位名每次换一个（`draft-1`、`draft-2`…），免得两个草稿撞名。草稿不会真的创建 git tag，工作流发布时才把 tag 改写成算出来的名字。
   - `projects` 填 `auto`（默认）就按 DLL 文件名自动对上包目录（`DSPEasy.Buildings.dll` → `DSPEasy.Buildings`）；也可以填 `all` 或直接写包目录名。名字对不上时用 `mapping` 逐行指定 `dll文件名=包目录名`。
   - Release 的 tag 由各包 `manifest.json` 的 `version_number` 自动算出（如 `Framework-0.2.33+Buildings-0.2.36`）。tag 已存在会直接报错，不会悄悄覆盖。
   - 第一次跑建议勾 `dry_run`，只打包不写 Release，看 Artifacts 和运行摘要；`publish` 取消勾选则上传后留作草稿。
   - zip 里只有 `manifest.json` / `icon.png` / `README.md` / `CHANGELOG.md` / `*.dll`，全部在根目录。

4. Thunderstore 上传：Release 正式发布后，工作流的「上传 Thunderstore」job 会把各 zip 挨个传上去（先 Framework 后玩法包）。

   - 仓库 Secrets 里要有 `THUNDERSTORE_TOKEN`：thunderstore.io → 右上角头像 → Settings → Teams → 团队 → Service accounts 创建的 `tss_...` token（明文只显示一次）。
   - 社区与各包分类写在仓库根的 `thunderstore.json`：`community` / `author_name` / `has_nsfw_content`，`packages` 下按包目录名给 `categories`（不选分类就写 `[]`）。分类 slug 写错会在准备阶段直接报错并列出可用分类。
   - `dry_run` 或 `publish` 取消勾选时**不会**上传（Thunderstore 上的版本发布后撤不回来）。没勾 `thunderstore` 就手动从 Release 取同名 `.zip` 上传，确认依赖能正确解析。
5. 提交 git（只提交版本号与 CHANGELOG，zip 不入库）。

> 打包、算 tag、发 Release、传 Thunderstore 全在工作流里，本地不压 zip、也不手工上传。
> 工作流见 `.github/workflows/publish-release.yml`，脚本在 `.github/scripts/`：`prepare.ps1`（取 DLL、校验、算 tag）→ `package.ps1`（打 zip）→ `publish.ps1`（传 Release）→ `thunderstore.ps1`（传 Thunderstore）。
