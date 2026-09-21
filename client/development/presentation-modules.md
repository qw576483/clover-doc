# 表现域模块（场景 / 图集 / 动画 / 声音 / 相机 / 画质）

## 这篇文档讲什么？

本指南介绍表现域里除 UI 之外的 6 个模块：`Scene`（场景）、`Atlas`（图集）、`Anim`（动画）、
`Sound`（声音）、`Camera`（相机）、`Quality`（画质与性能）。

**目标读者**：需要驱动场景 / 表现效果的 Unity 开发者。

## 前置条件

- 已完成 [快速开始](../quickstart.md)
- 了解 [Game 门面](./game-facade.md) 与 [UI 系统](./ui-system.md)

## 共同约定

- 契约定义在 `Runtime/Core/PresentationContracts.cs`，实现在 `Runtime/Presentation/`（`internal`）。
- **随 `Game.Launch` 自动挂载**，业务直接 `Game.Scene` / `Game.Sound` / … 即可，无需手动初始化：

```csharp
Game.Launch(new GameConfig { ServerAddr = "127.0.0.1:8002" });
Game.Scene.Load("MainCity");     // 直接用
```

- 需要精细控制（只挂一部分 / 手动接管）时可关闭自动挂载：

```csharp
CloverPresentation.AutoMount = false;   // 必须在 Launch 之前设置
Game.Launch(config);
CloverPresentation.Init();              // 手动挂载（幂等）
```

> `Game.Tick` 统一驱动的是 `Net` / `Sync` / `Res` / `UI` / `Anim` / `Camera` / `Quality`
> （见 `Game.cs` 的 Tick 实现）；`Scene` / `Atlas` **没有**每帧驱动。业务无需自己写 `Update`。

## Scene（场景管理）

| API | 说明 |
|-----|------|
| `Game.Scene.Load(sceneName, onProgress, onDone)` | 异步加载场景；`onProgress` 参数为 0~1 |
| `Game.Scene.Unload(sceneName, onDone)` | 异步卸载场景 |
| `Game.Scene.CurrentScene` | 当前场景名 |
| `Game.Scene.OnSceneLoaded(handler)` / `OnSceneUnloaded(handler)` | 订阅场景加载 / 卸载完成 |

```csharp
Game.Scene.Load("MainCity",
    progress => _progressBar.value = progress,
    () => Game.Logger?.Info("Scene", "场景就绪"));
```

行为要点：
- 内置**加载门控**：进度到 0.9 才允许激活场景，避免"场景已切但资源没到"的白屏。
- 卸载时会**自动批量回收**该场景的 Entity、对象池实例，并停止 **scope = 场景名** 的定时器（`StopScope(sceneName)`）；业务注册场景级定时器时把 scope 传为场景名即可随场景回收。
- 业务**禁止**直调 Unity 的 `SceneManager.LoadScene`。

## Atlas（图集）

| API | 说明 |
|-----|------|
| `Game.Atlas.Load(atlasName, cb)` | 加载图集（已加载则仅增加引用计数） |
| `Game.Atlas.GetSprite(atlasName, spriteName, cb)` | 取某个 Sprite；图集未加载会自动先加载 |
| `Game.Atlas.Release(atlasName)` | 释放引用，计数归零时卸载 |
| `Game.Atlas.UnloadAll()` | 卸载全部已缓存图集 |

```csharp
Game.Atlas.GetSprite("ui_common", "btn_ok", sp =>
{
    if (sp != null) _icon.sprite = sp;
});
```

图集资源路径约定为 `Atlas/{atlasName}`（走 `Game.Res`）。

## Anim（动画）

基于 Unity Animator：

| API | 说明 |
|-----|------|
| `Game.Anim.CreateAnimator(go, controller)` | 为 GameObject 创建 Animator 播放器 |
| `Game.Anim.Destroy(player)` | 销毁播放器 |

播放器（`IAnimPlayer`）常用方法：
`Play(state, normalizedTime)`、`CrossFade(state, duration)`、`SetBool/SetFloat/SetInteger/SetTrigger`、
`OnComplete(cb)`。

> 骨骼动画（Spine / DragonBones）不在引擎封装范围内：业务自行接入 SDK。
> 动画事件同理，在业务侧挂 Unity `AnimationEvent` 接收脚本即可。

```csharp
var player = Game.Anim.CreateAnimator(enemyGo, controller);
player.CrossFade("run", 0.2f);
player.OnComplete(() => Game.Anim.Destroy(player));
```

> 播放完成与播放进度由 `Game.Anim.Tick` 每帧驱动，业务不需要自己调。

## Sound（声音）

| API | 说明 |
|-----|------|
| `Game.Sound.PlayBGM(clipName, fadeTime)` | 播放 BGM（双音源交替，带淡入淡出） |
| `Game.Sound.StopBGM(fadeTime)` | 停止 BGM |
| `Game.Sound.PlaySFX(clipName)` | 2D 音效 |
| `Game.Sound.PlaySFXAt(clipName, position)` | 3D 空间音效 |
| `Game.Sound.PlayVoice(clipName)` | 人声 |
| `Game.Sound.StopAll()` | 停止全部 |
| `Game.Sound.SetVolume(group, v)` / `GetVolume(group)` / `SetMute(group, mute)` | 分组音量与静音，`group ∈ SoundGroup.{BGM, SFX, Voice}` |

```csharp
Game.Sound.PlayBGM("bgm_main", 0.5f);
Game.Sound.SetVolume(SoundGroup.SFX, 0.8f);
Game.Sound.PlaySFXAt("boom", transform.position);
```

音频资源路径约定：`Sound/BGM/{name}`、`Sound/SFX/{name}`、`Sound/Voice/{name}`（走 `Game.Res`）。

## Camera（相机）

| API | 说明 |
|-----|------|
| `Game.Camera.Follow(target, smoothTime)` | 平滑跟随目标 |
| `Game.Camera.Unfollow()` | 停止跟随 |
| `Game.Camera.Shake(duration, intensity)` | 震屏（强度线性衰减） |
| `Game.Camera.SetBounds(bounds)` | 限制相机移动范围 |

```csharp
Game.Camera.Follow(player.transform, 0.15f);
Game.Camera.Shake(0.3f, 0.5f);
Game.Camera.SetBounds(new Bounds(Vector3.zero, new Vector3(100, 100, 0)));
```

> 相机跟随作用于 `Camera.main`。

## Quality（画质与性能）

> **命名说明**：本模块历史上叫 `Device`（`Game.Device` / `DeviceLevel` / `IDeviceManager`），
> 容易与「设备唯一标识」（`Game.DeviceId`，见下节）混淆——两者毫无关系：
> 本模块管「这台机器**跑得动多好的画质**」（随时可改，不涉及身份），
> `DeviceId` 管「这台机器**是谁**」（稳定标识，用于账号 / 房间寻址）。故统一更名为 `Quality*`。

| API | 说明 |
|-----|------|
| `Game.Quality.AutoDetect()` | 按内存 / 显存自动分级（有存档则用存档） |
| `Game.Quality.SetLevel(level)` | 手动设置等级（`QualityTier.{Low, Medium, High}`） |
| `Game.Quality.Level` / `Config` | 当前等级 / 生效的质量配置（`QualityConfig`） |
| `Game.Quality.IsThrottling` / `CurrentFPS` | 节流状态 / 实测帧率 |
| `Game.Quality.OnLevelChanged(handler)` / `OnThrottling(handler)` | 订阅等级变更 / 节流变更 |

```csharp
Game.Quality.AutoDetect();
Game.Quality.OnLevelChanged(lv => Game.Logger?.Info("Quality", $"画质档 -> {lv}"));
```

行为要点：
- 三档预设会设置 `Application.targetFrameRate` 与阴影级联。
- 持续低帧会自动降档（有冷却），节流状态会通过 `OnThrottling` 通知。
- `AutoDetect()` 是**显式调用**的，引擎不会在启动时自动改你的画质，避免覆盖项目设置。

## DeviceId（设备唯一标识）

| 成员 | 说明 |
|------|------|
| `Game.DeviceId.Value` | 设备唯一标识（**保证非空**，跨会话稳定） |
| `Game.DeviceId.Source` | 取值来源：`Native` / `Persisted` / `Ephemeral`（诊断用） |

```csharp
// 匿名登录：玩家无感，但服务端始终拿得到一个稳定身份
var deviceId = Game.DeviceId.Value;
var token = await CloverAuth.SignupAsync("guest_" + deviceId, deviceId);
await Game.Net.Call<ELoginReply>(EMsg.Login, new ELoginRequest { token = token });
```

行为要点：

- **三层兜底**（业务无需自己写）：平台原生 ID → 本地持久化随机码 → 本次会话临时码。
- **原生 ID 会被校验**：编辑器里的开发机 ID（全组共用）、WebGL 返回的固定值（平台
  `unsupportedIdentifier`）、等于设备型号 / 设备名的占位值都会被识别并丢弃。这类坏值"看起来完全正常"，不报错，却会让大量设备**撞成同一个人**——
  是本模块要解决的核心问题。
- `Source == Ephemeral` 表示持久化失败（隐私模式 / 无写权限 / 磁盘满），
  此时**重启会换标识**，引擎会打一条 warn 日志；业务可据此提示玩家。
- **清空数据 / 重装会换标识**（持久化码丢失后重新生成）。对匿名身份而言可接受；
  需要跨设备 / 跨重装保持同一身份时，应升级到正式账号（注册或渠道登录）。

## 常见问题

### 场景已切但内容没出现 / 白屏

场景加载带门控，进度到 0.9 才激活。若长时间卡住，检查该场景的前置资源是否在加载；
场景资源本身走 `Game.Res`，请确认路径正确。

### 音效没声音

1. 资源路径要落在 `Sound/SFX/`（或 `BGM/`、`Voice/`）下；
2. 检查该分组的音量与静音：`Game.Sound.GetVolume(...)`；
3. `Game.Res` 未挂载（`CloverRes.Init(root)` 未调用）时音频加载会拿不到资源。

### 相机跟随抖动

`Follow` 的 `smoothTime` 越小跟随越紧、越容易抖；震屏期间不要同时改边界。

## 下一步

- 了解 [资源管理](./resource.md)——上述模块的资源加载都走 `Game.Res`
- 了解 [对象池](./object-pool.md)——图集/音效之外的实例复用
- 了解 [Game 门面](./game-facade.md)——完整模块清单
