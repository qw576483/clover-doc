# 资源管理

## 这篇文档讲什么？

本指南介绍 Resource 模块的使用方法，包括资源加载、释放和热更新。

**目标读者**：需要管理游戏资源的 Unity 开发者。

## 前置条件

- 已完成 [快速开始](../quickstart.md)
- 了解 Unity 资源管理基础
- 了解 [Game 门面](./game-facade.md)

## 核心能力

> **注意：** 资源**一律走 Resource 模块异步加载**，禁止直调 Resources/AB/Addressables 原生 API。

| 能力 | 说明 |
|------|------|
| 异步加载/释放 | 引用计数管理 |
| 版本热更 | 资源+配置热更；下载器支持断点续传、边下边玩 |
| 预加载 | 场景切换前按清单预加载，配合 Scene 加载门控 |
| 内存水位 | 超水位按 LRU 释放未引用资源 |

## API 参考

| API | 参数 | 返回值 | 说明 |
|-----|------|--------|------|
| `Game.Res.LoadAsset<T>(path, callback)` | `string, Action<T>` | `void` | 异步加载资源（回调式） |
| `Game.Res.LoadAsset<T>(path, progress, callback)` | `string, Action<float>, Action<T>` | `void` | 异步加载资源（带进度） |
| `Game.Res.Release(path)` | `string` | `void` | 释放资源引用计数 |
| `Game.Res.Preload(paths, onDone, progress)` | `List<string>, Action, Action<float>` | `void` | 批量预加载 |
| `Game.Res.UnloadAll()` | - | `void` | 卸载所有未被引用的资源 |
| `Game.Res.TryGet<T>(path)` | `string` | `T` | **同步**取已驻留的资源；没装进来返回 `null`（不触发加载、不阻塞） |
| `Game.Res.CachedBytes` | - | `long` | 当前缓存占用（估算字节） |
| `Game.Res.CacheWatermark` | - | `long` | 缓存字节水位，可读写；0/负数=不限制 |
| `Game.Res.Version` | - | `string` | 当前生效的资源版本号（未热更时为 `"0"`） |
| `Game.Res.IsBundleMode` | - | `bool` | 是否运行在 AssetBundle 后端 |
| `Game.Res.UpdateState` | - | `ResourceUpdateState` | 热更阶段（Idle/Checking/Downloading/Ready/Failed） |
| `Game.Res.ContentDir` | - | `string` | 热更内容目录（裸文件/配表下载后落地处） |
| `Game.Res.CheckUpdate(onResult)` | `Action<ResourceUpdateInfo>` | `void` | 拉取清单并比对差异（**只比对不下载**） |
| `Game.Res.DownloadUpdate(info, onProgress, onDone)` | `ResourceUpdateInfo, Action<ResourceUpdateProgress>, Action<bool,string>` | `void` | 差异下载（断点续传 + 自动重试） |
| `Game.Res.ClearDownloaded()` | - | `void` | 清除热更内容与本地版本记录（硬修复） |

> **`Release` 的语义**：引用计数归零表示「业务不再用」，但资源**仍留在缓存**里，
> 是否真正释放由**字节水位 + LRU** 决定。这样「加载→释放→再加载」不会反复走磁盘/解包。
> 要立刻释放请用 `UnloadAll()`（只清未被引用的条目）。


## 使用示例

### 加载资源

```csharp
// 异步加载单个资源（回调式）
Game.Res.LoadAsset<GameObject>("prefabs/role", prefab =>
{
    if (prefab != null)
    {
        var go = Instantiate(prefab);
        // 使用资源...
    }
});
```

### 带进度加载

```csharp
// 加载资源（带进度回调）
Game.Res.LoadAsset<GameObject>(
    "prefabs/role",
    progress => Debug.Log($"加载进度: {progress:P0}"),
    prefab =>
    {
        if (prefab != null)
        {
            var go = Instantiate(prefab);
        }
    }
);
```

### 批量预加载

```csharp
// 场景切换前预加载
var preloadList = new List<string>
{
    "prefabs/role",
    "prefabs/monster",
    "textures/ground",
};
Game.Res.Preload(preloadList,
    onDone: () => Debug.Log("预加载完成"),
    progress: p => Debug.Log($"预加载进度: {p:P0}")
);
```

### 同步取已驻留资源（先 Preload，后 TryGet）

`Game.Res` **只有异步加载，没有阻塞式同步加载**（那会卡住主线程）。
需要"立刻拿到"时走两步：**启动期 `Preload` 装进来 → 之后 `TryGet` 同步取**。

```csharp
// ① 启动期预热（异步）
Game.Res.Preload(new List<string> { ResPaths.PixelFont, ResPaths.Level11 },
    onDone: () => { /* 预热完了，可以开面板了 */ });

// ② 之后同步取（不阻塞、不触发加载）
var font = Game.Res.TryGet<Font>(ResPaths.PixelFont);
var text = Game.Res.TryGet<TextAsset>(ResPaths.Level11);
```

> **`TryGet` 是纯读**：不影响引用计数、不改变 LRU 顺序 ⇒ 取到的对象**不归调用方持有**，
> **不要**对它 `Release`（引用计数由加载方负责）。
> 没装进来 / 已卸载 / 已销毁 / 类型不匹配 —— 一律返回 `null`，**不会**把 Unity 的「假 null」交出去。
>
> ⛔ **不要用 `Resources.Load` 绕开 `Game.Res`**：那会跳过资源根前缀、缓存、LRU、卸载策略与热更后端，
> 换资源后端时这些点会**静默地不跟着变**。需要同步拿就先 `Preload`。

### 释放资源

```csharp
// 释放资源引用计数
Game.Res.Release("prefabs/role");

// 卸载所有资源
Game.Res.UnloadAll();
```

## 版本热更与内存水位

### 接入热更

热更是**显式接入**的：不配 `ManifestUrl` 就走 Unity 内置 `Resources`（与改造前行为一致）；
配了才切到 AssetBundle 后端。

```csharp
// Game.Launch 之后
CloverRes.Init(new ResourceModuleConfig
{
    ManifestUrl = "https://cdn.example.com/rs/manifest.json",
    // ContentDir 留空 = Application.persistentDataPath/clover-res
    CacheWatermark = 256L * 1024 * 1024,   // 256MB
    MaxConcurrentDownloads = 4,
    MaxRetries = 3,
});
```

```csharp
// 检查差异（只比对，不下载）
Game.Res.CheckUpdate(info =>
{
    if (!info.Success) { Game.Logger?.Error("Res", info.Error); return; }
    if (!info.HasUpdate) return;          // 已是最新：info.LocalVersion

    // 下载（断点续传；进度回调会被高频调用）
    Game.Res.DownloadUpdate(info,
        p => Game.UI?.ShowLoading($"更新中 {p.Progress:P0}  {p.BytesPerSecond / 1024f:F0}KB/s"),
        (ok, error) =>
        {
            Game.UI?.HideLoading();
            if (!ok) { Game.UI?.Toast("更新失败：" + error); return; }
            Game.UI?.Toast("更新完成");
        });
});
```

**配表热更**走同一条链路：清单里把 TSV 标成裸文件（`raw: true`），下载后落在 `Game.Res.ContentDir`，
把它交给 `CloverData.InitDataTable(dir)` 即可。

### 资源后端的选择：自研更新（不接 Addressables）

引擎把"资源从哪来"抽成 `IResourceBackend`，现有 `Resources`（首包兜底）与 `AssetBundle`（热更内容）两个后端。
**已定：不接 Addressables，更新由我们自己负责**（避免与 `ResourceUpdater`/`ResourceDownloader` 两套更新打架、
避免引擎 LRU 与它的内部引用计数双重记账）。运行时能力**已齐**：

| 能力 | 位置 |
|---|---|
| 清单契约（`ResourceManifest`） | 两张表（`Files` / `Assets`）**私有 + `IReadOnlyList` 只读视图**，唯一追加入口 `AddFile` / `AddAsset`（就地让惰性索引失效，另有 `InvalidateIndex` 供绕过入口的自定义解析器显式置空）；索引失效判据只有「索引 == null」一条 |
| 路径 → 包 → 包内资源名（清单路由） | `AssetBundleBackend.BeginLoad` |
| **跨包依赖先加载**（依赖先于自身开包） | `AssetBundleBackend.EnsureBundle`（遍历 `deps` 递归） |
| 包引用计数 + 级联释放 | `AssetBundleBackend.ReleaseBundle` |
| 缓存 / LRU / 内存水位 | `ResourceManager` |
| 首包兜底（含 `builtinRoot`、`raw` 裸文件） | `ResourcesBackend` + 清单 `raw` 标记 |
| 漏打包**明确报错**（不静默回退） | `AssetBundleBackend.BeginLoad` 的 `manifest has no bundle for ...` |
| 断点续传 / hash 校验 / `.part` 原子落地 | `ResourceDownloader` |

> ⚠️ **仍缺的一半在发布端**：仓库里**没有**产出 AssetBundle 与清单（尤其 `deps` 依赖表）的打包器
> （`BuildPipeline.BuildAssetBundles` / `AssetBundleManifest` 全仓零命中）。
> 手工维护依赖表不现实 ⇒ 必须补一个 Editor 打包脚本：`BuildPipeline.BuildAssetBundles` →
> 用 `AssetBundleManifest.GetAllDependencies()` 生成清单的 `deps` 与版本 → 再上传。
> 发布流程与目录约定（清单 URL 来源、`rs/<版本>` 规范、灰度与回滚）属客户端引擎未交付项，
> 待办由客户端引擎仓库维护。

### 生效时机（重要）

| 场景 | 生效时机 |
|------|----------|
| 首次安装（本地还没有任何热更内容） | 引擎先用首包 `Resources` 把游戏跑起来；下载完成后**自动**切到 AssetBundle，立即可用 |
| 版本升级（已经在 AssetBundle 后端） | **下次启动**生效。引擎**不做运行中热切换** —— 正在被使用的资源在脚下被替换会引出难查的空引用 |

### 内存水位

`CacheWatermark` 是缓存占用的字节上限（估算值）。超过后引擎从 LRU 尾部淘汰**引用计数为 0** 的资源。

> **不会**强制淘汰仍在被引用的资源（宁可持续超标并打一条告警）。
> 原实现「全被引用就强拆最旧的」会把业务正在用的对象从缓存摘掉并连带卸载，业务侧随后拿到
> Unity 的「假 null」。若看到这条告警，说明业务有漏调 `Game.Res.Release`。

## 与 ObjectPool 配合

战斗内特效/子弹/飘字/角色**一律走池**，禁止裸 `Instantiate`：

```csharp
// 1. 加载资源
Game.Res.LoadAsset<GameObject>("prefabs/bullet", prefab =>
{
    if (prefab == null) return;

    // ⛔ 池取预制体走的是 **Unity 原生 `Resources.Load<GameObject>(key)`**，**不经过 Game.Res**：
    //    不认 CloverRes 的 root、不走热更后端、不共享缓存/引用计数。
    //    ⇒ key 必须是 **Resources 下的相对路径**；与 Game.Res 的路径不同源时
    //      `Spawn` 会返回 **null**（只留一条 "Prefab not found"），紧接着用它的成员就是 NRE。
    Game.Pool.Preload("prefabs/bullet", 100);
});

// 2. 使用时从对象池获取（注意已经出了回调）
var bullet = Game.Pool.Spawn("prefabs/bullet");
if (bullet != null) bullet.transform.position = firePoint.position;

// 3. 归还到对象池
Game.Pool.Despawn(bullet);

// 4. 不再需要时释放资源
Game.Res.Release("prefabs/bullet");
```

## 最佳实践

> **警告：** 以下是资源管理的最佳实践：

1. **异步加载**：始终使用异步加载，避免卡顿
2. **及时释放**：不再使用时及时释放资源
3. **预加载**：场景切换前预加载常用资源
4. **对象池复用**：频繁创建/销毁的对象使用对象池

```csharp
// ✅ 正确：回调式异步加载
void ShowShopUI()
{
    Game.Res.LoadAsset<GameObject>("prefabs/shop_ui", prefab =>
    {
        if (prefab == null) return;
        var ui = Instantiate(prefab);
        // ... 使用 UI ...
    });
}

// ❌ 错误：同步加载
var prefab = Resources.Load<GameObject>("prefabs/shop_ui");  // 不要这样做
```

## 常见问题

### 资源加载失败

**症状**：`LoadAsset<T>()` 回调收到 null

**原因**：资源路径错误或资源不存在

**解决**：
1. 检查资源路径是否正确
2. 确认资源已打包到 AssetBundle

### 内存泄漏

**症状**：内存持续增长

**原因**：资源未及时释放

**解决**：
1. 检查 `Release()` 调用
2. 使用 `UnloadAll()` 释放所有缓存资源

## 下一步

1. 了解 [对象池](./object-pool.md) 和实例复用
2. 了解 [Entity 与 View](./entity-view.md) 和数据绑定

