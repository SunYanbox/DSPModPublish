# DSPEasy Framework

Dyson Sphere Program（戴森球计划）**DSPEasy 系列模组**共用的框架库。

> **这个包本身不提供任何玩法功能。** 只有当你安装的其它模组（例如 `DSPEasy Buildings`、`DSPEasy Exchange`）
> 依赖它时，或者你要基于它做开发时，才需要安装。
> 
> 汇报问题(Bug/Issue)：[github](https://github.com/SunYanbox/DSPModPublish/issues)

---

## 包含什么

| 模块 | 能力 |
| --- | --- |
| `DSPEasy.Framework.Save` | **命名空间旁车存档**：在存档旁边写一个 `.mod.dat`，数据块按 `命名空间/块ID` 分区，一个模组的数据不会踩到另一个模组；原子写入（先写 `.tmp` 再替换），文件格式 2，可读旧格式 1 并自动升级。 |
| `DSPEasy.Framework.UI` | **面板基座**：`UiFactory` 提供文本 / 按钮 / 滑条的工厂方法与配色；`UiDrag` 处理窗口拖动；`UiFocus` 处理层级——只在打开时提层一次，不会像每帧抢置顶那样把游戏的物品提示条压掉。 |
| `DSPEasy.Framework.Recipes` | `RecipeSolver`：配方树递归展开，带环检测与深度上限，用于「需要哪些材料」这类计算。 |
| `DSPEasy.Framework.Items` | 物品栈辅助。 |
| `DSPEasy.Framework.Blueprint` | 模组之间的蓝图数据通道。 |
| `DSPEasy.Framework.Abnormal` | 异常状态守卫：动工厂之前先确认游戏状态正常。 |

## 安装

1. 先装 **BepInEx 5.4.17（x64，Mono）**（已写在依赖里，模组管理器会自动处理）。
2. 把 `DSPEasy.Framework.dll` 放进 `BepInEx/plugins/`（Thunderstore Mod Manager / r2modman 会自动放好）。
3. 启动一次游戏，日志里能看到依赖它的模组正常加载。

> ⚠️ **`BepInEx/plugins/` 下只能有一份 `DSPEasy.Framework.dll`。**
> BepInEx 会递归加载 `plugins/` 下所有 DLL，每一份都会建立自己的静态注册表——有了两份，
> 一份写进去的数据另一份看不到，表现就是「设置存了，重进游戏却全没了」。
> 升级时请把旧副本删干净。

## 兼容性

- 游戏：戴森球计划 `0.10.35.29151`（Unity 2022.3.62f3c1，64 位）。
- BepInEx：`5.4.17.0`（Mono）。
- 旁车存档格式：2（能读格式 1，旧档会自动升级，不需要手动迁移）。

## 开发者参考

```csharp
// 注册一个带命名空间的存档块（块 ID 必须是 4 个可打印 ASCII 字符）
ModSave.Register("MyMod", new MyStateChunk(MyState.Table));

// 显式指定命名空间读写（不传参数则读写「本程序集注册的全部块」）
ModSave.WriteForSaveName(saveName, "MyMod");

// 面板：自己拼控件 + 处理层级
var root = UiFactory.NewRect(transform, "MyPanel");
UiFactory.Place(root, ...).Pos(...);
UiFocus.BringToFront(root);   // 打开时提层一次即可，不要每帧抢置顶
```

- 命名空间：`DSPEasy.Framework.Save` / `.UI` / `.Recipes` / `.Items` / `.Blueprint` / `.Abnormal`。
- 依赖方向是单向的：框架只引用游戏的 `Assembly-CSharp` 与 BepInEx / 0Harmony，**不引用任何使用它的模组**。
