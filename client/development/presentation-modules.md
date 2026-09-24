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

### 第一人称 rig（`CloverFirstPersonCamera`）

**纯逻辑类**（不是 `MonoBehaviour`）：帧步长由调用方经 `Tick(dt)` 注入（不读 `Time.deltaTime`），
可离线断言、可被任意持有者驱动；**不经 `Game.Camera` 门面**，业务自持实例 + 自己填手感参数。

| API | 参数 | 返回值 | 说明 |
|-----|------|--------|------|
| `rig.Bind()` | - | `bool` | 用引擎相机管理器（`Game.Camera.Main`）绑定当前主相机 —— **推荐入口** |
| `rig.Bind(camera)` | `Camera` | `bool` | 显式绑定指定相机（传 `null` ⇒ `false` + 限频留痕） |
| `rig.Unbind()` | - | `void` | 解绑；解绑后 `Tick` 不再写任何 Transform |
| `rig.Tick(dt)` | `float` | `void` | 推进一帧：读鼠标 → 累加视角 → 跟随后坐力 → 衰减摇晃 → 算眼位与朝向 → 写相机位姿与 FOV。`dt <= 0` ⇒ 本帧不推进任何状态 |
| `rig.ApplyLookDelta(dx, dy)` | `float, float` | `void` | 把一次**原始鼠标位移**按灵敏度 / 反转 / 限位累加进视角（设备无关的公开缝：回放 / 演示 / 观战接管 / 离线段言都走它） |
| `rig.SetRecoil(pitch, yaw)` | `float, float` | `void` | 喂入**权威**后坐力（度），本类只做表现跟随，⛔ 不累加第二份 |
| `rig.AddShake(amplitude, duration)` | `float, float` | `bool` | 注入一次摇晃（受击 / 爆炸 / 落地），期间幅度**线性**衰减；参数非正或未注入随机器 ⇒ `false` + 留痕 |
| `rig.SetView(yaw, pitch)` | `float, float` | `void` | 直接对齐视角（出生 / 接管 / 观战切换，不做平滑），yaw 走 360° 规范化、pitch 按 `PitchLimit` 夹紧 |
| `rig.Look` | - | `LookAccumulator` | 引擎件；读它的 `Yaw` / `Pitch` 得到**不含**后坐力 / 摇晃的「输入视角」（例如喂给移动方向解算） |
| `rig.Yaw` / `rig.Pitch` | - | `float` | 当前朝向**合量** = `Look` + 后坐力 + 摇晃（`Pitch` 已夹在 `±PitchLimit`） |
| `rig.AimDirection` | - | `Vector3` | 本帧视线方向（含后坐力 / 摇晃，与相机朝向一致）—— 射线 / 命中判定用它 |
| `rig.EyePosition` | - | `Vector3` | 本帧射线起点（眼位，**不含** `ViewOffset` 与摇晃） |
| `rig.ViewOffset` / `rig.ViewRoll` | `Vector3` / `float` | - | 业务每帧塞进来的视点晃动（典型 = `ViewBob` 的输出缝） |
| `rig.FovX` / `rig.VerticalFieldOfView` | `float` | - | 水平 FOV（开镜改它）/ 本帧实际下发的**垂直** FOV（未绑定时为 0） |
| `rig.SensitivityX` / `rig.SensitivityY` / `rig.SeparateAxes` / `rig.InvertY` / `rig.PitchLimit` | `float` / `bool` | - | 灵敏度（**度/count**，不是倍率）、分轴开关、Y 轴反转、俯仰限位（默认 `89`，引擎只保证不翻面） |
| `rig.EyeAnchor` / `rig.EyeOffset` / `rig.EyeSmoothTau` | `Transform` / `Vector3` / `float` | - | 眼位来源 / 相对锚点的局部偏移 / 眼位一阶平滑时间常数（`<= 0` = 吸附） |
| `rig.RecoilRiseTau` / `rig.RecoilFallTau` / `rig.ShakeRng` / `rig.ShakeRollScale` | `float` / `Rng` / `float` | - | 后坐力上跳 / 回正常数、摇晃随机器（⛔ 用注入的 `Rng`，不用全局随机）、摇晃横滚比例 |
| `rig.SetControlEnabled(on)` / `rig.LockInput()` / `rig.UnlockInput()` | `bool` | `void` / `bool` | 开关本 rig 的鼠标读取 / 加锁 / 解锁（只解**自己加的**那把锁） |

```csharp
var rig = new CloverFirstPersonCamera { EyeAnchor = playerRoot, EyeOffset = new Vector3(0f, 1.62f, 0f) };
rig.SensitivityX = settings.MouseSensitivity * DegPerCount;   // 每 count 多少度（业务换算）
rig.PitchLimit = tuning.PitchLimit;                           // 玩法口径（引擎不替业务定手感值）
rig.ShakeRng = new Rng(matchSeed);                            // 注入随机器
rig.Bind();                                                   // 用 Game.Camera.Main

void Update()
{
    rig.Tick(Time.deltaTime);                                 // 帧步长注入
    rig.SetRecoil(sim.RecoilPitch, sim.RecoilYaw);            // 只喂权威值，表现由本类跟随
    rig.ViewOffset = bob.Offset; rig.ViewRoll = bob.Roll;     // ViewBob 的输出缝
}
```

> 边界：非线程安全（主线程使用）；`Tick` **每帧只许调用一次**（鼠标位移是"读时结算"的增量，一帧调两次会把同一帧的位移按两次算）；
> 未绑定相机 / 相机被销毁 / 相机被禁用时**只跳过"下发位姿"这一步**（视角 / 后坐力 / 摇晃状态照常推进，复绑后立刻可用）+ 限频留痕。

## Separation2D（角色间水平推开）

与 `Game.Camera` 无关：它是 `Runtime/Core/Separation2D.cs` 的**纯函数静态工具**，防"两个角色站进同一格"。
**不是物理引擎**：不做路径规划（那是 `AStar`）/ 不做碰撞检测（墙体与视线由位图与射线各管一层）/ 不做时间积分 / 不处理竖直分层（同层筛选由调用方先做完再传进来）。
只保证一条几何约束：任意两圆**圆心距 ≥ 两半径之和**（外加 `Skin = 0.001f` 缝隙）。

| API | 参数 | 返回值 | 说明 |
|-----|------|--------|------|
| `Separation2D.TryResolve(circles, count, result)` | `Circle[], int, Vector2[]` | `bool` | 一次解开**一整组**（所有人一起挪，各退一半），结果**写进** `result`（不改输入、热路径零分配）。`true` = 已推出；`false` = 迭代上限内仍有重叠（挤成一堆）或缓冲长度不够，**不抛** |
| `Separation2D.TryResolveOne(position, radius, others, count, out result)` | `Vector2, float, Circle[], int, out Vector2` | `bool` | 只推**一个**申请位置（`others` 视作不动的障碍，退全部）—— 每帧角色推进的形态 |
| `Separation2D.Circle` | `Vector2 Position` / `float Radius` | - | 参与推开的水平圆（`Radius <= 0` 按 0 处理） |
| `Separation2D.MaxIterations` / `Separation2D.Skin` | - | `int` / `float` | 迭代轮数上限（`8`）/ 推开后额外缝隙（`0.001f`，与 cs16 侧同值） |

**确定性契约**：同输入 ⇒ 逐位相同的输出 —— 不调 `UnityEngine.Random`、不读时钟 / 帧号，遍历顺序 = 调用方给的数组下标顺序；
"完全重合"（无几何方向可言）时按**下标**取确定方向（黄金角 × (下标+1)）。

> ⚠️ 推开结果**不许直接采用**：调用方要再喂回自己的墙体判定钳一次（⛔ 别把人推进墙里）。
> 边界：`count <= 0` / 空数组 ⇒ 成功返回且什么都不写；半径全 0 ⇒ 位置原样返回；坐标非有限（NaN / ±Inf）⇒ 该圆不动也不推别人；统统**不抛异常**（失败留降频日志）。
> 性能口径：`O(n² × MaxIterations)`、热路径零分配，`n` = 同屏参与推开的角色数（个位数 ~ 几十）；⛔ 不要每帧对上千个单位调用。

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

### 第一人称视角不动 / 鼠标没反应

**症状**：`rig.Tick(dt)` 调了，但画面朝向不动，或一动就飘。

**原因 / 解决**：
1. **没绑定相机**（`rig.IsBound == false`）：`Bind()` 要等场景里有 `tag=MainCamera` 且启用的相机；进关卡前的空窗期取不到，稍后重试或 `Bind(camera)` 显式绑定。
2. **没设置眼位来源**：`EyeAnchor == null` ⇒ 只更新朝向、机位不动。
3. **灵敏度为 0**：`SensitivityX <= 0` ⇒ 该轴位移被忽略（限频 Warn）。
4. **一帧调了两次 `Tick`**：鼠标位移是"读时结算"的增量，一帧两次会把同一帧位移按两次算（表现为灵敏度翻倍 / 飘）。
5. **`timeScale = 0`**：业务传进来的 `dt` 为 0 ⇒ 本帧不推进任何状态（这是刻意的，不是 bug）。

### 两个角色站进同一格 / 重叠

**症状**：角色之间可以互相穿过去、站在同一处。

**原因**：位移解算里**没做角色间推开** —— 只判墙体不判"另一个角色挡不挡"。

**解决**：位移解算末尾调 `Separation2D.TryResolveOne(申请位置, 半径, 周围角色圆, count, out var fixedPos)`（或整组用 `TryResolve`），
再把 `fixedPos` **喂回墙体判定钳一次**（⛔ 别直接采用，否则会把人推进墙里）；
返回 `false` 表示迭代上限内仍有重叠（挤成一堆），按"挤住"处理（原地不动 / 交给寻路绕开）。

## 下一步

- 了解 [资源管理](./resource.md)——上述模块的资源加载都走 `Game.Res`
- 了解 [对象池](./object-pool.md)——图集/音效之外的实例复用
- 了解 [Game 门面](./game-facade.md)——完整模块清单
