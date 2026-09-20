# 输入（Input）

## 这篇文档讲什么？

介绍如何用 `Game.Input` 读取键鼠 / 手柄输入，以及引擎的输入后端机制。

**目标读者**：需要处理玩家操作的 Unity 开发者。

## 硬规则

业务代码里**不许出现** `Input.GetKeyDown(...)` / `Input.mousePosition` / `Input.GetAxis(...)`
（即 `UnityEngine.Input`）。一律走 `Game.Input`，按键用引擎的 `GameKey` 枚举。

原因见下方「为什么必须走 Game.Input」。

## 初始化（必须早于构建 UI）

```csharp
void Start()
{
    // 1. 启动引擎
    Game.Launch(new GameConfig { ServerAddr = "127.0.0.1:8002" });

    // 2. 挂载输入模块 + 建立 EventSystem
    //    只要工程里有 UI（按钮/输入框）或任何键鼠操作，这一句必须排在「构建 UI」之前
    CloverInput.Init();

    // 3. 之后再 CloverNet.Init / 构建 UI / 登录……
    BuildUi();
}
```

顺序反了（先建 UI、后 `CloverInput.Init()`）→ 按钮点不了。

## 基本用法

| 需求 | 写法 |
|------|------|
| 某键本帧按下 | `Game.Input.GetKeyDown(GameKey.Space)` |
| 某键按住 | `Game.Input.GetKey(GameKey.LeftShift)` |
| 某键本帧抬起 | `Game.Input.GetKeyUp(GameKey.Space)` |
| 鼠标键 | `Game.Input.GetMouseButtonDown(0)`（0=左 1=右 2=中） |
| 鼠标坐标 | `Game.Input.MousePosition`（左下角为原点） |
| 轴 | `Game.Input.GetAxis("Horizontal")` / `Game.Input.GetAxis("Vertical", raw: true)` |
| 锁定/解锁输入 | `Game.Input.Lock()` / `Game.Input.Unlock()`（过场、结算弹窗） |
| 运行状态 | `Game.Input.Available` / `Game.Input.BackendName` |

```csharp
void Update()
{
    if (Game.Input.GetKeyDown(GameKey.Num1)) StartSolo();
    if (Game.Input.GetKeyDown(GameKey.Space)) Jump();

    var dir = new Vector2(Game.Input.GetAxis("Horizontal"), Game.Input.GetAxis("Vertical"));
    Move(dir);

    if (Game.Input.GetMouseButtonDown(0)) Fire();
}
```

### 高层动作（动作游戏）

```csharp
Game.Input.OnJump(() => Jump());
Game.Input.OnSkill(1, () => CastSkill(1));
Game.Input.OnMove(dir => Move(dir));

// 取消：OffJump / OffSkill / OffMove
```

每帧的按键快照也可直接读：`Game.Input.State.JumpDown` 等。

## GameKey 与后端无关

`GameKey` 是引擎定义的按键枚举，**与具体后端无关** —— 引擎负责把它翻译成当前生效后端的实际按键。
所以同一份业务代码，在旧输入 / 新输入系统下都能跑。

常用按键：`A`-`Z`、`Num0`-`Num9`、`LeftArrow` / `RightArrow` / `UpArrow` / `DownArrow`、
`Space`、`Enter`、`Escape`、`LeftShift`、`LeftCtrl`、`F1`-`F12`、`MouseLeft` / `MouseRight` / `MouseMiddle`。

## 输入后端机制

引擎运行时自动挑一个「后端」（真正去读键鼠的那层实现）：

| 优先级 | 后端 | 何时使用 |
|--------|------|----------|
| 1 | **InputSystem**（新） | 默认首选。需 `activeInputHandler` 含 New（`1` 或 `2`）、装了 `com.unity.inputsystem`、`Keyboard.current != null` |
| 2 | **Legacy**（旧） | 新后端不可用时的兜底 |
| 3 | **None** | 都不可用 → 不抛异常，只报一条修复日志 |

UI 的输入模块**同步跟随**所选后端：新后端 → `InputSystemUIInputModule`，旧后端 → `StandaloneInputModule`。
**两者绝不并存**（并存会互相抢事件，导致点击失效）。

### Active Input Handling 的取值

位置：Edit → Project Settings → Player → Other Settings → Active Input Handling

| 值 | 含义 | 旧输入 | 新输入 |
|----|------|--------|--------|
| `0` | Input Manager (Old) | ✅ | ❌ |
| `1` | Input System Package (New) | ❌ | ✅ |
| `2` | Both | ✅ | ✅ |

⚠️ 这个设置**只在编辑器启动时读取一次**：改完必须完全重启 Unity 才生效。
另外 Unity 运行中手改 `ProjectSettings.asset` 会被回写覆盖 —— 必须先关掉编辑器再改。

## 为什么必须走 Game.Input

`UnityEngine.Input`（旧输入）只有在 Active Input Handling 含 Old（`0` 或 `2`）时才可用。
若设为「只新」（`1`），每次 `Input.*` 调用都会抛：

```
InvalidOperationException: You are trying to read Input using the UnityEngine.Input class,
but you have switched active Input handling to Input System package in Player Settings.
```

后果比「读不到按键」严重得多：

- 异常在 `Update()` 里抛出会**中断整帧后续逻辑** → 键盘也跟着失效；
- uGUI 的 `StandaloneInputModule` 内部同样读旧输入 → **按钮全部点不动**。

现象就是「键鼠一点效果也没有」。

`Game.Input` 把这些都封在引擎里：自动选后端；后端不可用时只报日志、**绝不把异常抛进帧循环**。

## 排查：键鼠没反应

| 序号 | 检查项 |
|------|--------|
| 1 | Console 里 `[Clover.Input] 输入后端=?`：期望 `InputSystem`；若是 `Legacy` 看括号里的回退原因；若是 `None` 按日志提示改设置 |
| 2 | `activeInputHandler` 至少要含 New（即 `1` 或 `2`） |
| 3 | 改完设置有没有**完全重启** Unity |
| 4 | 日志里 `InputModule=` 期望 `InputSystemUIInputModule`；若是 `StandaloneInputModule` 说明回退了旧模块 |
| 5 | 有没有 `[Clover.Input] EventSystem ...`：没有 → `CloverInput.Init()` 没排在构建 UI 之前 |
| 6 | 有没有两个 InputModule 并存（引擎会打印「移除不匹配的输入模块」） |

> **键鼠无响应先查输入后端**，不必排查 UI 布局、RectTransform、射线、DPI 缩放 —— 与它们无关。

### 后端选择与排障

后端**自动选择**：`InputSystem` 探测可用就用它，否则退回 `Legacy`（Input Manager），两者绝不并存；
没有手动切换开关。若日志显示 `后端=InputSystem` 但按键仍无反应，那是输入模块 / EventSystem 配置问题：
按日志提示把 `Active Input Handling` 设为 `Both` 或 `Input System Package (New)`，并**完全重启 Unity 编辑器**。

## 下一步

- [UI 系统](./ui-system.md)：EventSystem / InputModule 由引擎输入模块统一维护
- [Game 门面](./game-facade.md)：模块入口一览
- [常见约束](../reference/constraints.md)
