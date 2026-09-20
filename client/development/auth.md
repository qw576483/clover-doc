# 账号服登录（CloverAuth）

游戏服只认 token、不碰账号表（见 [账号服](../../server/security/auth-server.md)）。
引擎只有这一种登录模式，所以客户端登录固定**两步**：

```text
① HTTPS  ──▶  账号服  /auth/login  ──▶  JWT
② 长连接 ──▶  游戏网关  EMsgLogin{token}  ──▶  owner
```

第二步走的是普通游戏长连接，只是请求体从 `account/password` 换成 `token`。

## 前置：初始化网络（HTTP 已包含在内）

`CloverAuth` 依赖 `Game.Http`，而 **`CloverNet.Init` 会一并把它挂上**——业务不需要单独调用
`CloverNet.InitHttp()`（该方法保留，仅用于「只想用 HTTP、暂不连网关」的场景，如纯登录页先换 token）。
服务器地址与账号服地址**一律从 `Assets/Configs/config.json` 读**（范式见客户端配置模板），
**不要在业务代码里写地址字面量**：

```csharp
// 全部取自 config.json：server.addr / server.udp_addr / server.auth_addr / server.tls / …
Game.Launch(new GameConfig
{
    ServerAddr = Cfg.Server.addr,
    CallTimeoutSeconds = Cfg.Server.call_timeout,
    MaxReconnectCount = Cfg.Server.max_reconnect_count,
    UseTls = Cfg.Server.tls,   // 与服务端 gateway.tcp_tls_disabled 相反；证书只走系统信任链
});
CloverNet.Init(Cfg.Server.addr,
    string.IsNullOrEmpty(Cfg.Server.udp_addr) ? null : Cfg.Server.udp_addr);
// HTTP 模块随上面这行一并挂接，无需再调 CloverNet.InitHttp()

CloverAuth.AuthAddr = Cfg.Server.auth_addr;   // ★ 必填：config.json 的 server.auth_addr
```

> `AuthAddr` 是**必填配置**：为空即配置错误。建议在启动时就校验并**明确失败**
> （`Debug.LogError` + 终止初始化），而不是等玩家点登录才报错。

`AuthAddr` 是**必填配置**：未配置时 `CloverAuth.Enabled == false`，
调用 `LoginAsync` / `SignupAsync` 会抛 `InvalidOperationException`。
不存在「不配账号服地址就走本地账号表」的老流程——账号服是登录链路的必经依赖。

## 登录

登录路径**唯一**：先 HTTP 换 token，再拿 token 登游戏服。

```csharp
async Task Login(string account, string password)
{
    // ① HTTP：账号服校验账号密码，返回 JWT
    var token = await CloverAuth.LoginAsync(account, password);   // 失败抛异常

    // ② 长连接：把 token 交给游戏服，游戏服调账号服 /auth/verify 换 owner
    var reply = await Game.Net.Call<ELoginReply>(
        EMsg.Login, new ELoginRequest { token = token });

    if (reply.success)
    {
        // ★ 登记会话是断线恢复的前提（让引擎进入「恢复会话态」，断线后自动提交 ResumeSession）。
        //
        // 第 2 个参数**传 null，不是登录回包的 session_key**（与官方样例 Samples~/LoginFlow/LoginFlow.cs 一致）：
        // session_key 是会话通道加密密钥（AES-256），当作恢复凭证上交会让恢复会话 token mismatch 被踢，
        // 引擎也会对非空恢复凭证打一条 Warn。真正的恢复凭证由紧随其后的
        // PushPlayerFullSync.session_token 非空覆盖（引擎的全量同步处理会自动把它写进会话），
        // 在此之前引擎不会提交恢复请求。
        Game.Net.SetupSession(account, null);
    }
}
```

`CloverAuth.LoginAsync` 返回的 token **原样回传给游戏服**：它仍是账号服签发的那一个，
客户端应自行保管，并在过期前重新向账号服换取（游戏服侧不续期——它没有账号表）。

## 注册

注册是账号服的职责，**游戏服不接收注册报文**（原 `EMsgSignup`=1 已作废保留）。客户端注册走 HTTP：

```csharp
await CloverAuth.SignupAsync(account, password);  // 注册成功即签发 token
// 随后正常走 LoginAsync（或直接用返回的 token 发 EMsgLogin）
```

向游戏服发注册消息没有意义：该号位已作废，会落到「没有 handler」或被登录门禁挡下，拿不到有意义的回包。

## API

| 成员 | 说明 |
| --- | --- |
| `CloverAuth.AuthAddr` | 账号服地址，如 `https://127.0.0.1:8051`（账号服默认要求 TLS）；**必填**（空 = 未配置） |
| `CloverAuth.Enabled` | 是否已配置账号服（`AuthAddr` 非空） |
| `LoginAsync(account, password)` | 返回 `Task<string>`（JWT）；失败抛异常，消息为服务端 `err` |
| `SignupAsync(account, password)` | 同上；注册成功即签发 token |

两个方法都是 `Task`，**必须 await**：拿到 token 才能继续登录游戏服，
且异常要能沿 await 链路抛出。

## 异常语义

| 异常 | 含义 | 处理 |
| --- | --- | --- |
| `InvalidOperationException("未配置账号服地址…")` | `AuthAddr` 为空却调了方法 | 检查配置（`auth_addr` 必填） |
| `InvalidOperationException("HTTP 模块未初始化…")` | 没调 `CloverNet.Init`（HTTP 随它挂接） | 先完成网络初始化 |
| `Exception("账号服无响应")` | 网络失败 / 账号服未启动 | 提示重试 |
| `Exception("账号服响应无法解析…")` | 返回体不是预期 JSON | 检查账号服版本 |
| `Exception(服务端 err 文案)` | **业务失败**（密码错、账号已存在、429 锁定等） | 直接展示给玩家 |

**链路失败与业务失败要分开提示**：前者是"网络问题，请重试"，后者是"密码不对"。
`CloverAuth` 内部通过「抛异常 vs 返回结果」区分，调用方按 `catch` 的类型判断。

## 与登录门禁的关系

网关的登录门禁**只看本连接有没有绑定 owner**，不关心你用哪种方式登录：

- 客户端拿 token 走 `EMsgLogin{token}` → 游戏服调账号服 `/auth/verify` 换 owner → 网关绑定 owner。

这条链路走完，**后续消息都正常放行**。只有「登录 / 注册 / 恢复会话」三个消息号
在未登录时可发（见 [认证与授权](../../server/security/auth.md)），其余会收到 `code=401`，
引擎同时发布 `Net.OnUnauthorized`：

```csharp
Game.Event.On<EErrorReply>("Net.OnUnauthorized", e =>
{
    Game.Logger?.Warn("Net", $"未认证（code={e.code}）: {e.err}");
    BackToLogin();
});
```

## 配置示例（`config.json`）

```json
{
  "server": {
    "addr": "127.0.0.1:8002",
    "udp_addr": "127.0.0.1:8003",
    "auth_addr": "https://127.0.0.1:8051",
    "call_timeout": 10,
    "max_reconnect_count": 5
  }
}
```

`auth_addr` **必填**：填账号服地址（如 `https://127.0.0.1:8051`）。
账号服**默认要求 TLS**（服务端没配证书又没显式 `auth.insecure_plaintext` 时启动即失败），
所以协议头通常是 `https://`；证书只走系统信任链（本地联调证书由
[`clover-server-tools/mkcert`](https://github.com/qw576483/clover-server-tools/blob/main/mkcert.md) 签、根 CA 已入信任库）。
留空即未配置，登录 / 注册会抛 `InvalidOperationException`。
