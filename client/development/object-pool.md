# 对象池

## 这篇文档讲什么？

本指南介绍 GameObject 池的使用方法，帮助开发者高效管理游戏对象复用。

**目标读者**：需要优化性能的 Unity 开发者。

## 前置条件

- 已完成 [快速开始](../quickstart.md)
- 了解 Unity 对象池概念
- 了解 [资源管理](./resource.md)

## GameObject 池

> **注意：** 战斗内 GameObject **一律走对象池**，禁止裸 `Instantiate`。

### 核心能力

| 能力 | 说明 |
|------|------|
| Spawn/Despawn | 按 prefab key 获取/归还 |
| 预热 | 支持启动时预热指定数量 |
| 容量上限 | 超出上限时裁剪不活跃实例（TrimPool） |
| 空闲过期回收 | `IdleExpirySeconds` > 0 时，闲置超时的非活跃实例在下次 `Spawn`/`Despawn` 被销毁（**默认 0 = 关闭**）；另有 `TrimIdle()` 可手动清理一次 |
| 按场景分组清理 | 场景卸载时自动批量回收 |
| 池化回调 | 对象实现 `IObjectPoolable`（`OnSpawn` / `OnDespawn`）时，取出 / 归还会**自动回调**复位——与引用池的 `IReferencePoolable` 对称（那个管纯 C# 对象，这个管 `GameObject`） |
| 代码工厂 | `Register(key, factory)` 注册"怎么造"（工厂优先，未注册的 key 才回落 Resources 预制体）；`IsRegistered(key)` 只回答该 key **注册过代码工厂**没有 |

### API 参考

| API | 参数 | 返回值 | 说明 |
|-----|------|--------|------|
| `Game.Pool.Spawn(key, parent, group)` | `string, Transform, string` | `GameObject` | 获取实例 |
| `Game.Pool.Despawn(go)` | `GameObject` | `void` | 归还实例 |
| `Game.Pool.Preload(key, count, group)` | `string, int, string` | `void` | 预热实例 |
| `Game.Pool.Clear(key)` | `string` | `void` | 清空指定池 |
| `Game.Pool.ClearAll()` | - | `void` | 清空所有实例 |
| `Game.Pool.ClearGroup(group)` | `string` | `void` | 清除指定场景组的所有池 |
| `Game.Pool.GetActiveCount(key)` / `GetInactiveCount(key)` | `string` | `int` | 活跃 / 非活跃实例数 |
| `Game.Pool.IdleExpirySeconds` | `float`（属性） | `float` | 空闲过期回收阈值（秒）：>0 时闲置超时的非活跃实例在下次 `Spawn`/`Despawn` 被销毁；**默认 0 = 关闭**（负数按 0 处理） |
| `Game.Pool.TrimIdle()` | - | `void` | 立即按 `IdleExpirySeconds` 清理一次全部池的空闲对象（阈值为 0 时无操作） |
| `Game.Pool.Register(key, factory)` | `string, Func<GameObject>` | `void` | 注册代码工厂（`Spawn` / `Preload` 时**工厂优先**，未注册的 key 才回落 `Resources.Load<GameObject>(key)`）；传 `null` = 注销该 key |
| `Game.Pool.IsRegistered(key)` | `string` | `bool` | 该 key 在本池上是否注册过**代码工厂**（⛔ 不回答 Resources 里的预制体） |

### 使用示例

```csharp
// 获取实例（可指定父对象和分组）
var bullet = Game.Pool.Spawn("bullet_prefab", firePoint, "bullets");

// 使用实例
bullet.transform.position = firePoint.position;
bullet.GetComponent<Rigidbody>().velocity = transform.forward * 10f;

// 归还实例
Game.Pool.Despawn(bullet);

// 预热实例（启动时调用）
Game.Pool.Preload("bullet_prefab", 50, "bullets");

// 清空指定池
Game.Pool.Clear("bullet_prefab");
```

### 池化回调（`IObjectPoolable`）

池化对象在**根节点**上实现 `IObjectPoolable`，取出 / 归还时引擎自动回调，把"忘记复位上一次的字段"固定在池的两个动作上：

```csharp
using CloverEngine;

// 挂在池化对象的根节点上（引擎只查根节点自身，不递归子节点）
class Bullet : MonoBehaviour, IObjectPoolable
{
    public void OnSpawn()   { /* 取出：复位速度 / 计时 / 拖尾 */ }
    public void OnDespawn() { /* 归还前：释放外部引用 / 解绑每实例数据 */ }
}

var bullet = Game.Pool.Spawn("Prefabs/Bullet");   // 新建与复用两条路径都会调 OnSpawn
Game.Pool.Despawn(bullet);                        // 禁用前调 OnDespawn
```

> `Spawn`（含**新建与复用**两条路径）取出时调 `OnSpawn`、`Despawn` **禁用前**调 `OnDespawn`；`Preload` 只预造、**不**回调。
> 回调异常由引擎接住并留痕（**不打断** `Spawn` / `Despawn` 链）；⛔ 回调里别做重活。

## 引用池（纯 C# 对象）

`Game.Pool` 管 `GameObject`（`Instantiate`/`Destroy` 昂贵、必须复用）；**普通托管对象**
（每帧产生的输入帧、事件参数、临时 List 等）用 `ReferencePool` —— 它们的问题不是"实例化贵"，
而是"每帧 `new` 一堆短命对象把 GC 顶起来"。两者是**互补**而不是替代关系。

### API 参考

| API | 参数 | 返回值 | 说明 |
|-----|------|--------|------|
| `ReferencePool.Acquire<T>()` | - | `T` | 取一个实例（池空则 `new`）；`T` 须有**无参构造函数** |
| `ReferencePool.Release<T>(item)` | `T` | `void` | 归还实例（传 `null` 静默忽略；同一实例重复归还被忽略并告警） |
| `ReferencePool.Count<T>()` | - | `int` | 当前池中的空闲实例数 |
| `ReferencePool.Clear<T>()` | - | `void` | 清空该类型的池 |
| `ReferencePool.ClearAll()` | - | `void` | 清空全部类型的池（切场景 / 引擎拆卸时调用） |

### 使用示例

```csharp
// 池化对象：必须有公开无参构造函数；实现 IReferencePoolable 可让池自动回调复位
class DamagePopup : IReferencePoolable
{
    public int Value;

    public void OnAcquire() { Value = 0; }   // 取出时复位为可用初态
    public void OnRelease() { Value = 0; }   // 归还前清理（清空集合 / 释放外部引用）
}

var popup = ReferencePool.Acquire<DamagePopup>();   // 池空则 new
popup.Value = 42;
// ... 使用 ...
ReferencePool.Release(popup);                       // 归还，供下次 Acquire 复用
```

> 对象实现 `IReferencePoolable`（`OnAcquire` / `OnRelease`）时，取出 / 归还会**自动回调**复位——
> 把"忘记清干净上一次的字段"这类坑固定在池的两个动作上。
> 线程模型：**主线程专用**（内部加锁只为"误从后台线程归还"时不破坏栈结构，不要当跨线程池用）。

## 与 Resource 模块配合

资源加载后使用对象池管理实例：

```csharp
// 加载资源（回调式）
Game.Res.LoadAsset<GameObject>("prefabs/bullet", prefab =>
{
    if (prefab == null) return;

    // ⛔ 池取预制体走 **Resources.Load<GameObject>(key)**，不经 Game.Res ⇒
    //    key 必须是 Resources 下的相对路径（不是 Game.Res 的自定义 root 路径）。
    //    不同源时 Spawn 返回 **null**（只留 "Prefab not found"），下一行就是 NRE。
    Game.Pool.Preload("prefabs/bullet", 100);
});

// 使用时（已出回调）
var bullet = Game.Pool.Spawn("prefabs/bullet");
if (bullet != null) bullet.transform.position = firePoint.position;

// 归还时
Game.Pool.Despawn(bullet);

// 不再需要时释放资源
Game.Res.Release("prefabs/bullet");
```

## 最佳实践

> **警告：** 以下是对象池使用的最佳实践：

1. **预热**：在场景加载前预热常用对象
2. **及时归还**：使用完毕后立即归还，避免内存泄漏
3. **不要存储引用**：不要长期持有对象池实例的引用
4. **场景切换清理**：场景切换时自动清理，无需手动处理

```csharp
// ✅ 正确：及时归还
void Fire()
{
    var bullet = Game.Pool.Spawn("bullet_prefab");
    bullet.transform.position = firePoint.position;
    // 使用完毕后归还
    Game.Timer.After(2f, () => Game.Pool.Despawn(bullet));
}

// ❌ 错误：长期持有引用
GameObject cachedBullet;  // 不要这样做
void Fire()
{
    cachedBullet = Game.Pool.Spawn("bullet_prefab");
    // 忘记归还
}
```

## 常见问题

### 对象池实例未归还

**症状**：内存持续增长

**原因**：使用后未调用 `Despawn()`

**解决**：
1. 检查所有 `Spawn()` 调用是否有对应的 `Despawn()`
2. 使用 `GetActiveCount(key)` / `GetInactiveCount(key)` 检查实例数量

### 对象池预热失败

**症状**：启动时卡顿

**原因**：预热数量过大或资源未加载

**解决**：
1. 分批次预热
2. 确保资源已加载

## 下一步

1. 了解 [资源管理](./resource.md) 和异步加载
2. 了解 [Entity 与 View](./entity-view.md) 和数据绑定

