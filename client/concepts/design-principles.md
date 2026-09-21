## 本页内容

本文档介绍 Clover Unity 客户端引擎的设计理念和必须遵守的硬约束。

## 前置条件

- 已了解 [架构总览](architecture.md)
- 已了解 Unity C# 开发基础

## 这篇文档讲什么？

Clover 客户端引擎遵循一系列设计原则和硬约束，确保代码质量、性能和可维护性。这些原则和约束是强制性的，所有业务代码必须遵守。

## 核心原则

| # | 原则 | 说明 | 示例 |
|---|------|------|------|
| 1 | **能力域划分** | 按客户端真实需要的能力划分模块，不按服务器分层 | 网络域、表现域、数据域、基础域 |
| 2 | **门面收口** | 业务只从 `Game` 门面拿各模块入口 | `Game.Net`, `Game.Entity`, `Game.Res` |
| 3 | **主线程唯一出口** | 网络/资源 IO 在后台，所有业务回调经 Dispatcher 回 Unity 主线程 | `Game.Dispatcher.Post()` |
| 4 | **Entity 与 View 解耦** | Entity 纯数据（不继承 MonoBehaviour），View 是 GameObject，异步绑定 | Entity 组件 + View 组件分离 |
| 5 | **客户端不跑权威逻辑** | 数值/战斗/掉落权威在服务端，客户端只做表现、插值、缓存 | 插值平滑 + 服务端快照校正 |
| 6 | **资源全部池化异步化** | 战斗内禁止裸 `Instantiate`、禁止同步加载资源 | `Game.Pool.Spawn()` + 异步加载 |
| 7 | **能力内置、项目选用** | 资源双后端（Resources + AssetBundle）、版本热更、对象池、UI 通用件等为引擎内置基础能力 | 引擎提供，项目选用 |

## 通用硬约束

> **警告：**   这些约束是**强制性**的，所有业务代码必须遵守。

### G1: 模块封装

**规则**：对外只暴露接口/纯数据/枚举/工厂；实现类 `internal`；工厂返回接口。

```csharp 错误示例
// ❌ 错误：暴露实现类
public class NetworkManager
{
    public void Send(byte[] data) { /* ... */ }
}

// ✅ 正确：暴露接口
public interface INetworkManager
{
    void Send(byte[] data);
}

internal class NetworkManagerImpl : INetworkManager
{
    public void Send(byte[] data) { /* ... */ }
}
```

### G2: 主线程约束

**规则**：所有业务回调（OnMsg/Timer/Event/动画事件）必须在主线程；公开 API 仅主线程可调（**引擎未内置主线程断言**，靠约定与评审保障）。

```csharp 错误示例
// ❌ 错误：在非主线程调用 UI
void OnNetworkMessage(byte[] data)
{
    // 这里可能在后台线程
    uiText.text = "收到消息"; // 可能崩溃
}

// ✅ 正确：通过 Dispatcher 回到主线程
void OnNetworkMessage(byte[] data)
{
    Game.Dispatcher.Post(() => {
        uiText.text = "收到消息";
    });
}
```

### G3: Entity 与 View

**规则**：Entity 不继承 MonoBehaviour；View 异步绑定。

```csharp 错误示例
// ❌ 错误：Entity 继承 MonoBehaviour
public class PlayerEntity : MonoBehaviour
{
    public int Hp;
    public void TakeDamage(int damage) { /* ... */ }
}

// ✅ 正确：Entity 是纯数据
public class PlayerEntity
{
    public int Hp;
    public void TakeDamage(int damage) { /* ... */ }
}

// View 是独立的 MonoBehaviour
public class PlayerView : MonoBehaviour
{
    public PlayerEntity Entity;
    public void UpdateHp(int hp) { /* ... */ }
}
```

### G4: 客户端不权威

**规则**：不跑权威数值逻辑；重连后以服务器快照覆盖本地。

```csharp 错误示例
// ❌ 错误：客户端计算伤害
void Attack(PlayerEntity target)
{
    int damage = CalculateDamage(); // 权威逻辑不应该在客户端
    target.Hp -= damage;
    target.IsDead = target.Hp <= 0;
}

// ✅ 正确：客户端只做表现
void Attack(PlayerEntity target)
{
    Game.Net.Call<AttackReply>(EMsg.Attack, new AttackRequest
    {
        TargetId = target.Id,
    });
    // 等待服务端返回结果
}
```

### G5: 资源池化

**规则**：战斗内 GameObject 一律走对象池；资源一律走 Resource 模块异步加载。

```csharp 错误示例
// ❌ 错误：裸 Instantiate
var go = Instantiate(prefab);

// ✅ 正确：使用对象池
var go = Game.Pool.Spawn("prefab_key");

// ❌ 错误：同步加载资源
var texture = Resources.Load<Texture2D>("textures/hero");

// ✅ 正确：回调式加载
Game.Res.LoadAsset<Texture2D>("textures/hero", texture => {
    // 使用 texture
});
```

### G6: 场景管理

**规则**：场景切换一律走 Scene 模块；业务禁止直调 Unity `SceneManager`。

```csharp 错误示例
// ❌ 错误：直调 SceneManager
UnityEngine.SceneManagement.SceneManager.LoadScene("GameScene");

// ✅ 正确：使用 Game.Scene（随 Launch 自动挂载）
Game.Scene.Load("GameScene");
```

### G7: 代码生成

**规则**：**配表**由打表工具生成（源表 → tsv + 强类型代码），禁止手改产物。
消息号、动画参数常量、多语言 key 手工维护，但两端 / 多处必须保持一致。

```csharp 示例
// 用具名常量（禁止裸字面量）；业务常量与服务端 game/def/ 同名同值
public const uint MsgLogin = MsgDef.Login;
```

### G8: 跨边界传递

**规则**：引用类型**跨程序集**传递不得让渡可变状态：或返回**拷贝快照**，或返回**只读契约 / 不可变对象**（判据见 [`clover-client-unity-engine/结构规则.md`](https://github.com/qw576483/clover-client-unity-engine/blob/main/结构规则.md) §5.3）。

```csharp 错误示例
// ❌ 错误：直接传递引用
void ProcessData(DataContainer data)
{
    // data 可能在多个地方被修改
    data.Value = 100;
}

// ✅ 正确：传递副本
void ProcessData(DataContainer original)
{
    var copy = original.Copy();
    copy.Value = 100;
}
```

### G9: 空值处理

**规则**：返回接口的方法判 `null` 后再返回，避免 typed-null 等价问题。

```csharp 错误示例
// ❌ 错误：可能返回 typed-null
public IPlayer GetPlayer(int id)
{
    return playerMap[id]; // 如果 id 不存在，返回 typed-null
}

// ✅ 正确：显式判空
public IPlayer GetPlayer(int id)
{
    if (playerMap.TryGetValue(id, out var player))
        return player;
    return null;
}
```

### G10: 注释规范

**规则**：函数注释不写冗余函数名。

```csharp 错误示例
// ❌ 冗余注释
/// <summary>
/// 发送消息
/// </summary>
/// <param name="msgId">消息ID</param>
public void Send(int msgId) { }

// ✅ 有价值的注释
/// <summary>
/// 发送网络消息，自动处理重连和消息队列
/// </summary>
/// <param name="msgId">消息ID，业务消息必须 >= InternalMsgMax + 1（即 >= 10001）</param>
public void Send(int msgId) { }
```

### G11: UI 数据流

**规则**：UI 只订阅数据事件，不直连网络、不改数据。

```csharp 错误示例
// ❌ 错误：UI 直连网络
public class ShopUI : MonoBehaviour
{
    void Start()
    {
        Game.OnMsg(EMsg.Xxx, ctx => { /* 刷新 UI */ });
    }
}

// ✅ 正确：UI 订阅数据事件
public class ShopUI : MonoBehaviour
{
    void Start()
    {
        Game.Event.On<object>("Shop.OnInfoChanged", data => { /* 刷新 UI */ });
    }
}
```

## 原则背后的设计理念

### 为什么客户端不跑权威逻辑？

1. **安全性**：数值计算在服务端，客户端无法作弊
2. **一致性**：重连后以服务器快照覆盖本地，保证状态一致
3. **简化**：客户端只做表现、预测、插值，逻辑更简单

### 为什么资源全部池化异步化？

1. **性能**：避免频繁创建/销毁，减少 GC
2. **内存**：对象池管理内存，避免内存泄漏
3. **流畅**：异步加载避免卡顿

### 为什么 UI 只订阅数据事件？

1. **解耦**：UI 与网络/业务逻辑解耦
2. **可测试**：UI 可独立测试
3. **可复用**：相同的 UI 可复用于不同场景

## 下一步

1. **了解架构** → [架构总览](architecture.md)
2. **了解依赖** → [模块依赖规则](module-dependencies.md)
3. **开始开发** → [Game 门面](../development/game-facade.md) → [网络与会话](../development/network.md)

