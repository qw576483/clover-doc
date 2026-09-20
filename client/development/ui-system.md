# UI 系统

## 这篇文档讲什么？

本指南介绍 UIManager 的使用方法，包括窗口管理、数据绑定和通用组件。

**目标读者**：需要构建游戏 UI 的 Unity 开发者。

## 前置条件

- 已完成 [快速开始](./quick-start.md)
- 了解基本的 Unity UI 开发
- 了解 [Game 门面](./game-facade.md)

## UIManager 概览

> **注意：** UI **只订阅数据变更事件**刷新，不直连网络、不改数据。

> **说明：** `IUIManager` 契约在 `Runtime/Core/PresentationContracts.cs`，实现在 `Runtime/Presentation/UI.cs`（`internal`）。
> 模块**已挂载到 `Game.UI`**，并随 `Game.Launch` 自动完成——业务无需任何手动注入或实例化。

### 核心能力

| 能力 | 说明 |
|------|------|
| 窗口管理 | Open/Close/Get/IsOpen/CloseAll |
| 固定层级 | Background / Normal / Popup / Top / System 五级 |
| 面板生命周期 | IUIPanel 接口定义 OnOpen/OnClose/OnUpdate |
| 面板事件 | OnPanelOpened / OnPanelClosed 回调 |

### API 参考

| API | 参数 | 返回值 | 说明 |
|-----|------|--------|------|
| `Game.UI.Open<T>(param)` | `object` | `void` | 打开窗口（泛型约束 `IUIPanel`） |
| `Game.UI.Close<T>()` | - | `void` | 关闭指定类型窗口 |
| `Game.UI.Close(panelName)` | `string` | `void` | 按名称关闭窗口 |
| `Game.UI.CloseAll()` | - | `void` | 关闭所有窗口 |
| `Game.UI.Get<T>()` | - | `T` | 获取已打开的窗口 |
| `Game.UI.IsOpen<T>()` | - | `bool` | 检查窗口是否已打开 |
| `Game.UI.OnPanelOpened(handler)` | `Action<string>` | `void` | 注册面板打开回调 |
| `Game.UI.OnPanelClosed(handler)` | `Action<string>` | `void` | 注册面板关闭回调 |

### 写一个面板

面板继承 `UIPanel` 基类即可（基类已实现 `PanelName`（默认取类名）/ `Layer`（默认 `Normal`）/ `Root` /
`OnClose` / `OnUpdate`），业务通常只需 `OnOpen`。**预制体放 `Resources/UI/{类名}`**，`Game.UI.Open<T>()` 按类名加载。

```csharp
using CloverEngine;
using UnityEngine;

public class LoginPanel : UIPanel
{
    public override void OnOpen(object param)
    {
        // 刷新界面（param 为 Open<T>(param) 传进来的对象）
    }

    // 需要弹窗遮罩时覆盖 Layer：
    // public override UILayer Layer => UILayer.Popup;
}
```

```csharp
Game.UI.Open<LoginPanel>();              // 打开
Game.UI.Open<ItemInfoPanel>(itemData);   // 带参数打开
Game.UI.Close<LoginPanel>();             // 关闭
```

> 引擎已自动创建 `Canvas`（1920×1080 缩放适配）+ `GraphicRaycaster`；
> UI 点击还依赖 `EventSystem`，它归输入模块管理——请在 `Game.Launch` 后调用 `CloverInput.Init()`。

## 用代码搭 UI（`UIFactory`）

不少项目选择**用代码生成面板内容**（预制体只当挂载点）：像素风/纯色块/精确对齐的界面，
用编辑器手拖反而更难对齐，代码里写坐标还能用常量约束住版式。

引擎为此提供 **`CloverEngine.UIFactory`**（对业务公开），**不要自己再写一套锚点/铺满/文本的工具类**
——那类重复实现是踩坑高发区（实测：业务自建的同类工具因为「面板根节点没铺满」，
让左对齐文案整段飞出屏幕，而同屏居中的控件都正常，极容易被误判成"那几个控件没做"）。

| API | 参数 | 返回值 | 说明 |
|-----|------|--------|------|
| `UIFactory.CreateNode(name, parent)` | `string, Transform` | `RectTransform` | 新建节点，**已铺满父节点** |
| `UIFactory.Stretch(rt)` | `RectTransform` | `void` | 把已有节点设为铺满父节点 |
| `UIFactory.CreateCentered(name, parent, size, pos)` | `string, Transform, Vector2, Vector2` | `RectTransform` | 居中对齐 + 定尺 + 相对父层中心定位 |
| `UIFactory.CreatePanel(name, parent, color, raycastTarget)` | `string, Transform, Color, bool` | `Image` | 铺满的纯色面板（背景 / 遮罩 / 按钮底板） |
| `UIFactory.CreateText(name, parent, content, fontSize, alignment, color, raycastTarget)` | `string, Transform, string, int, TextAnchor, Color, bool` | `Text` | 文本节点（**用引擎内置字体**） |
| `UIFactory.CreateButton(name, parent, label, size, pos, bg, onClick)` | `string, Transform, string, Vector2, Vector2, Color, Action` | `Image` | 底板 + 居中标签（`Button` 已挂好） |
| `UIFactory.DefaultFont()` | - | `Font` | 引擎内置字体（取不到时回退系统字体） |
| `UIFactory.UICamera()` | - | `Camera` | 世界坐标 → 屏幕坐标换算用（主相机缺失时退到任一启用相机） |

```csharp
using CloverEngine;

var root = UIFactory.CreateNode("Panel", transform);                 // 已铺满
UIFactory.CreatePanel("BG", root, new Color(0.36f, 0.58f, 0.99f), false);
UIFactory.CreateCentered("Title", root, new Vector2(600f, 80f), new Vector2(0f, 200f));
UIFactory.CreateButton("Start", root, "开始", new Vector2(240f, 64f), new Vector2(0f, -100f),
    Color.gray, () => Game.Event.Emit("Menu.Start"));
```

> **锚点约定（避免上面那个坑）**：位置一律表达成**相对父层中心的偏移**。
> 对齐方式交给 `Text.alignment` / 子物体自身处理，**不要**去改锚点来"实现对齐"
> （改了锚点，同一个坐标的含义就变了）。真正要贴父层边角（HUD）时才自己设锚点。
>
> ⚠️ **`UIFactory` 不负责**：`DefaultFont()` 给的是引擎内置字体；
> **像素风项目需要自己的像素字体（字号往往还要按字体规格取整）**，这层包装归业务自己写。
> 通用件（Toast / 飘字 / Loading / 确认框 / 引导）**走 `Game.UI`**，不要直接碰底层的 Layer 实现。

## 数据绑定

UI 只订阅数据变更事件刷新，**不直连网络、不改数据**。

### 推荐模式

```csharp
// UI 组件订阅数据事件
public class ShopUI : MonoBehaviour
{
    void OnEnable()
    {
        // 订阅数据变更事件（带泛型参数需用 On<T>）
        Game.Event.On<object>("Shop.OnInfoChanged", OnShopInfoChanged);
        Game.Event.On<object>("Shop.OnBuySuccess", OnBuySuccess);
    }
    
    void OnDisable()
    {
        // 取消订阅（泛型版本需匹配）
        Game.Event.Off<object>("Shop.OnInfoChanged", OnShopInfoChanged);
        Game.Event.Off<object>("Shop.OnBuySuccess", OnBuySuccess);
    }
    
    void OnShopInfoChanged(object data)
    {
        // 刷新 UI 显示
        var info = (ShopInfo)data;
        UpdateItemList(info.Items);
    }
    
    void OnBuySuccess(object data)
    {
        // 显示购买成功提示
        Game.UI.Toast("购买成功");
    }
}
```

### 禁止模式

```csharp
// ❌ 错误：UI 直连网络
public class ShopUI : MonoBehaviour
{
    void Start()
    {
        // 不要在 UI 中直接监听网络消息
        Game.OnMsg(EMsg.Xxx, ctx => { /* 刷新 UI */ });
    }
}

// ❌ 错误：UI 直接修改数据
public class ShopUI : MonoBehaviour
{
    void OnBuyClick()
    {
        // 不要在 UI 中直接修改数据模型
        ShopManager.Instance.BuyItem(itemId);
    }
}
```

### 正确的数据流

```csharp
// ✅ 正确：UI 触发事件，由其他模块处理
public class ShopUI : MonoBehaviour
{
    void OnBuyClick()
    {
        // 发射事件，由 ShopManager 处理
        Game.Event.Emit("Shop.OnBuyRequest", new { ItemID = itemId });
    }
}

// ShopManager 监听事件并处理
public class ShopManager
{
    void Start()
    {
        Game.Event.On<object>("Shop.OnBuyRequest", OnBuyRequest);
    }
    
    async void OnBuyRequest(object data)
    {
        var request = (dynamic)data;
        var reply = await Game.Net.Call<ShopBuyReply>(MsgDef.ShopBuy, new ShopBuyRequest
        {
            ItemID = request.ItemID,
        });
        
        // 购买成功后发射事件
        Game.Event.Emit("Shop.OnBuySuccess", reply.OrderID);
    }
}
```

## 通用件

引擎**已内置**，且**零美术依赖**（用代码搭 uGUI 节点），`Game.Launch` 之后即可直接调用：
不会因为「预制体还没做」而静默无反馈。需要美术版时替换表现域实现即可，接口不变。

| 通用件 | API | 说明 |
|--------|-----|------|
| Toast | `Game.UI.Toast(text, duration)` | 顶部堆叠提示，到期自动淡出；同屏最多 5 条，超出丢弃最旧的 |
| 飘字 | `Game.UI.FloatText(worldPos, text, color, duration)` | 世界坐标冒出、上飘淡出（伤害数字 / 获得物品）；目标在相机背面不显示 |
| Loading | `Game.UI.ShowLoading(text)` / `Game.UI.HideLoading()` / `Game.UI.IsLoading` | 全屏半透明遮罩 + 旋转指示；**引用计数**，可嵌套 |
| 确认框 | `Game.UI.Confirm(title, message, onConfirm, onCancel, confirmText, cancelText)` | 同时只显示一个，后到的请求**排队** |
| 红点 | `Game.UI.SetRedDot(key, on)` / `Game.UI.GetRedDot(key)` / `Game.UI.OnRedDotChanged(handler)` | key 用 `/` 分层，父节点自动聚合后代 |
| 引导遮罩 | `Game.UI.ShowGuide(target, tip, onClick, blockTarget)` / `Game.UI.HideGuide()` | 挖空并高亮目标控件，其余压暗 |

```csharp
// Toast：默认 2 秒
Game.UI.Toast("购买成功");
Game.UI.Toast("网络不稳定，正在重连", 3f);

// 飘字：传世界坐标，引擎负责投影到屏幕
Game.UI.FloatText(monster.transform.position, "-120", Color.red);

// Loading：引用计数，两个异步流程各自 Show/Hide 互不干扰
Game.UI.ShowLoading("正在购买...");
try { await Game.Net.Call<ShopBuyReply>(MsgDef.ShopBuy, req); }
finally { Game.UI.HideLoading(); }

// 确认框：回调式（不阻塞主线程）
Game.UI.Confirm("购买确认", "确定要花费 100 钻石吗？",
    onConfirm: () => Game.Event.Emit("Shop.OnBuyRequest", new { ItemID = itemId }),
    onCancel: () => { },
    confirmText: "购买", cancelText: "再想想");

// 红点：key 分层，点亮叶子即自动点亮父节点，父项不需要手工维护
Game.UI.SetRedDot("shop/item/weapon", true);        // 此时 Game.UI.GetRedDot("shop") 也为 true
Game.UI.OnRedDotChanged((key, on) => RefreshDot(key, on));

// 引导：blockTarget=false 时被高亮的控件能正常点，业务在它的回调里 HideGuide
Game.UI.ShowGuide(buyButton.GetComponent<RectTransform>(), "点击这里购买", blockTarget: false);
```

> **不进入窗口栈**：这些件**不参与 Popup 互斥**——弹一条 Toast 不会把正在看的弹窗顶掉。
> **红点不变量**：父节点恒为「自身显式亮起 或 任一后代亮起」，因此不会出现「子项有红点、父项没有」
> 的困惑状态；要熄灭整棵子树请逐个熄灭叶子（或退出登录时统一清空），**不能**靠把父节点设成 false 压制子节点。
> **按钮类通用件**（确认框 / 引导）需要场景里有 EventSystem，由 `CloverInput.Init()` 负责创建；
> 缺失时引擎会打一条明确的错误日志（否则表现为「面板能开但点不动」）。


## 适配

| 适配项 | 说明 |
|--------|------|
| 安全区适配 | 通用件（Toast / Loading / 确认框）已内置 `SafeAreaFitter`（`Runtime/Presentation/UI.cs`，internal，不挂在全屏遮罩上）；**业务面板需自行**用 `Screen.safeArea` 处理，见下 |
| 分辨率适配 | 策略集中管理，支持多种适配模式 |

```csharp
// 获取安全区
var safeArea = Screen.safeArea;

// 引擎内置的 SafeAreaFitter 是 internal、只在通用件内部使用；
// 业务面板的安全区适配需自行实现
//（`UIHelper` / `AdaptStrategy` 这类公开适配 API 在引擎里不存在，此前文档出现过是笔误，不要照抄）
// 直接用 Unity 原生能力：
// var canvasScaler = GetComponent<CanvasScaler>();
// canvasScaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
```

## 最佳实践

> **警告：** 以下是 UI 开发的最佳实践：

1. **数据驱动**：UI 只负责显示，不处理业务逻辑
2. **事件通信**：通过事件总线与其他模块通信
3. **及时清理**：关闭 UI 时及时取消事件订阅
4. **对象池复用**：频繁创建/销毁的 UI 使用对象池

## 常见问题

### 窗口无法打开

**症状**：`Game.UI.Open<T>()` 无响应，日志出现 `Panel prefab not found: Resources/UI/XxxPanel`

**原因**：预制体没放对位置，或类名与文件名不一致

**解决**：
1. 确认预制体在 `Resources/UI/{面板类名}.prefab`（路径与类名逐字一致）
2. 确认预制体根节点上挂着该面板组件（实现 `IUIPanel`，一般继承 `UIPanel`）
3. 面板能打开但**按钮点不动**时，检查是否漏了 `CloverInput.Init()`（缺 `EventSystem` 时引擎会告警一次）

### 数据绑定失效

**症状**：UI 不更新

**原因**：事件订阅未正确注册或已取消

**解决**：
1. 检查 `OnEnable`/`OnDisable` 中的事件订阅
2. 确认事件名称正确

## 下一步

- 了解 [资源管理](./resource.md) 和异步加载
- 了解 [对象池](./object-pool.md) 和实例复用