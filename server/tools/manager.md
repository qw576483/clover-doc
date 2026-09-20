## 这篇文档讲什么？

`manager` 是 clover 集群的**命令行编排工具**：查看所有节点、查看节点状态、对节点下发运维指令、
按顺序做滚动发布。它同时是**给 AI / 脚本用的自动化入口** —— 输出可解析、退出码可判定、非交互不阻塞。

位置：`clover-server-tools/manager/`。

## 它做什么 / 不做什么

| | 内容 |
|---|---|
| **做** | 读 etcd 拿集群拓扑；调各节点 admin 控制面做 drain（灰度下线）、切网关上游、优雅退出；编排「逐个节点滚动发布」 |
| **不做** | **起新进程**（k8s `Deployment` / systemd 的职责）；**死节点拉起**（master 判 `Dead` 后只摘除路由）。这两件事通过 `rollout --launch "<命令>"` 转交出去 |

> 一句话：**连接级迁移 k8s 做不了，进程拉起引擎不做**，`manager` 站在两者中间做编排。

## 前置条件

1. **etcd 可连** —— 节点目录与服务发现的唯一数据源。
2. **节点上报了 admin 地址，且该地址对 manager 可达。**
   引擎启动时会把 `admin.listen_addr` 登记进 `clover/nodes/<nodeID>` 的 `admin` 字段。
   admin **默认只绑回环**（`127.0.0.1:8041`）——**跨机管理必须把 `admin.listen_addr` 配成内网可达地址，
   并同时配置 `admin.token`**：`AdminConfig.Normalize` 把「非回环 + 无 token」判为不安全配置，
   构造期直接报错、**启动被拒**（`listen_addr` 留空也不行：它回落到回环，跨机依旧不可达）。
   不要绑公网：admin 挂着 `/admin/shutdown`、`/admin/gateway/upstream`。
   配了 token 后该端口上的 `/admin/*`、`/deadletter`、`/log/level`、`/debug/pprof` 一律要求带
    `X-Admin-Token`（或 `Authorization: Bearer`）。
   3. **manager 侧配同一令牌**：把节点的 `admin.token` 原样填进 manager 配置的 `admin.token`。
    manager 的 admin 客户端（`internal/adminclient`）会给**每个** admin 请求带 `X-Admin-Token` 头。
    两边不一致时 `drain` / `shutdown` / `upstream` 会被 **401 拒绝**，错误文案会提示「令牌不一致」；
    `doctor` / `status` 仍能判定节点存活（`GET /ping` 不设门禁），但 drain 状态
    （`/admin/drain/status`）读不到会**显式**报成 `drain_error` / 「drain 状态不可读」
    并计入 `summary.drain_unavailable`、退出码变 `3`，不再静默显示成「未进行」。

## 数据源（etcd 键）

| 键 | 值 | 说明 |
|---|---|---|
| `clover/nodes/<nodeID>` | `{"type":"game","tags":["room"],"admin":"127.0.0.1:8041"}` | 节点目录（引擎登记） |
| `clover/services/<role>/<role>-<host>-<pid>` | `"127.0.0.1:8011"` | 服务实例（logic / auth / log） |

## 编译与运行

```bash
cd clover-server-tools/manager

# 产物落在当前目录（Windows 下为 manager.exe）
go build -o manager ./cmd/manager

# 首次运行会自动生成默认 config.yaml
./manager nodes
./manager -config /etc/clover/manager.yaml nodes
```

配置（`config.yaml`）：

```yaml
etcd:
  endpoints: ["127.0.0.1:2379"]
  username: ""          # 未开鉴权留空
  password: ""
  dial_timeout: "3s"
admin:
  timeout: "5s"         # 单次 admin 请求超时
  default_port: 8041    # 仅老版本节点未上报 admin 时兜底
  token: ""             # 被管节点的 admin.token；留空 = 不发令牌头
```

`admin.token` 必须与被管节点配置里的 `admin.token` **逐字一致**（引擎侧逐字节比较，大小写与
首尾空白都算差异）。它是长期凭据，因此**只从配置文件读**：不做命令行参数（会进 shell 历史与
进程列表），也**不会**出现在任何输出里 —— `doctor` 只打印「已配置 / 未配置」。

## 命令

| 命令 | 说明 |
|---|---|
| `nodes [--json]` | 列出全部节点（节点目录 + 服务实例） |
| `status <node>\|--all [--json]` | 查看存活（admin `/ping`）、路由数、drain 进度 |
| `doctor [--tag t] [--json]` | **集群体检**：etcd 连通性 + 每个节点存活 + 汇总，AI 自检入口 |
| `drain <node> [--target addr] [--mode hybrid] [--grace 5m] [--hard-timeout 2m] [--stop-after] [--wait] [--timeout 30m]` | 发起灰度下线 |
| `drain-status <node> [--json]` | 查询灰度下线进度 |
| `drain-cancel <node> [--json]` | 取消灰度下线（回滚，节点恢复接客） |
| `wait <node> [--timeout 30m] [--interval 2s] [--json]` | 阻塞等待 drain 收敛（编排 / 脚本用） |
| `upstream <node> [--set host:port] [--json]` | 查看 / 切换网关默认上游 |
| `shutdown <node> [--json]` | 请求节点优雅退出 |
| `rollout [参数] [--json]` | 滚动发布：对一组旧节点逐个 drain |

通用参数：`-config <path>`、`--json`、`--addr <host:port>`（跳过节点目录直接指定 admin 地址）、
`--yes`（跳过确认）。带下划线的开关（`--stop_after` / `--hard_timeout` / `--dry_run`）同时接受连字符写法。

### drain 的三种模式（引擎侧语义）

| mode | 行为 | 何时用 |
|---|---|---|
| `grace` | 只等玩家自然退出，宽限期到后分批强踢；**不迁移、不需要 `--target`**，但必须先把网关上游切走 | 拿不到新进程地址时 |
| `migrate` | 逐连接切到新进程，客户端无感；宽限期到后不强踢 | 宁可留下也不打断玩家 |
| `hybrid` | 先迁移，宽限期到后对剩余连接分批强踢（**推荐**） | 常规滚动重启 |

## AI / 脚本自动化契约

`manager` 是按「无人值守调用」设计的，以下四条是**稳定契约**（改实现时要一起守住）：

1. **机器可读**：所有子命令支持 `--json`，把**结果**以**单个 JSON 对象**写到 stdout。
   任何返回路径（成功 / 失败 / `--dry-run`）都不会让 stdout 为空。
2. **错误也结构化**：`--json` 下失败同样输出 JSON（`{"ok":false,"error":"..."}`），
   不必去 stderr 上抓字符串。
3. **绝不阻塞等输入**：stdin 不是终端（AI / CI）时，破坏性命令（`drain` / `drain-cancel` / `shutdown` / `rollout`）
   必须显式带 `--yes`，否则**立即**返回 `ExitUsage(2)` —— 不会挂在确认提示上直到超时。
4. **退出码可判定**：

| 退出码 | 含义 |
|---|---|
| `0` | 成功 |
| `1` | 运行失败（连不上 etcd / admin 报错 / 操作被拒） |
| `2` | 用法错误（参数缺失、非交互环境下未带 `--yes`） |
| `3` | 部分成功：集群有节点不可达，或节点存活但 drain 状态读不到（`admin.token` 不匹配）；`doctor` / `status --all` 用 |

5. **流分离**：结果走 stdout；诊断与进度走 stderr，且 `--json` 下进度**完全静默**。

### AI 用法示例

```powershell
# ① 开工自检：一条命令看清集群（解析 stdout 的 JSON，判断退出码）
$doc = (.\manager.exe doctor --json 2>$null | Out-String | ConvertFrom-Json)
if (-not $doc.ok) { "有 $($doc.summary.down) 个节点不可达：$(($doc.nodes | Where-Object {-not $_.alive}).node.id -join ', ')" }

# ② 演练：只打印计划，不真正下发
.\manager.exe rollout --nodes 127.0.0.1:8011 --target 127.0.0.1:8012 --dry-run --yes --json

# ③ 执行并等待收敛（脚本拿退出码判断成败）
.\manager.exe drain 127.0.0.1:8011 --target 127.0.0.1:8012 --stop-after --yes --wait --json
if ($LASTEXITCODE -ne 0) { "drain 失败" }
```

> 典型 AI 验证流程：`doctor` 确认环境 → `rollout --dry-run` 核对计划 → `rollout --yes --json`
> 执行并逐步核对 `steps[]` → 再跑一次 `doctor` 确认结论。

## 滚动发布 SOP

`rollout` 的循环：**起新进程（`--launch`）→ 对旧节点 drain → 等它归零 → 间隔后处理下一个**。

### 场景 A：k8s

k8s 负责起 Pod，`manager` 负责把存量连接迁走。两条典型接法：

1. **preStop hook 调 drain**（不依赖 manager 常驻）：
   ```yaml
   lifecycle:
     preStop:
       exec:
         command: ["curl", "-sf", "-XPOST",
                   "http://127.0.0.1:8041/admin/drain?mode=grace"]
   terminationGracePeriodSeconds: 420   # 必须 >= drain 的 grace + hard_timeout
   ```
   `grace` 模式不需要 `target`：SIGTERM 前先摘流，新 Pod 就绪后流量自然切过去。
  若该 Pod 配了 `admin.token`（admin 不在回环时**必须**配，见「前置条件」），
  preStop 的 curl 必须带令牌头：`-H "X-Admin-Token: $ADMIN_TOKEN"`，否则被 401 拒绝。
2. **manager 编排**：`kubectl rollout` 起新 Pod，就绪后由 `manager` 对旧 Pod 执行 drain。

### 场景 B：systemd / 裸机

```bash
manager rollout --nodes 10.0.0.11:8011 --target 10.0.0.11:8012 \
  --launch "systemctl start clover-game-new@8012" --stop-after --yes --json
```

## 常见问题

**`nodes` 是空的**：节点未接入 etcd 或未注册。检查节点的 `etcd.endpoints` 配置。

**`doctor` 显示全部 DOWN**：节点上报的 admin 地址不可达。默认 `127.0.0.1` 只对本机有效；
跨机管理需在节点配置里**同时**把 `admin.listen_addr` 改成内网地址**并配 `admin.token`**
（只改地址、不配 token 会被 `AdminConfig.Normalize` 拒绝启动；manager 会把回环 / 通配主机
换成节点 ID 里的主机名再尝试）。

**`doctor` / `status` 显示节点存活、但 `drain` / `shutdown` / `upstream` 报 401（或 drain 状态列为空）**：
被管节点启用了 `admin.token`，而 manager 配置的 `admin.token` 没填或与节点不一致 ——
错误文案会分别提示「节点启用了 admin.token：请填同一令牌」/「manager 配置的 admin.token 与节点不一致」。
存活判定走 `GET /ping`（不设门禁）所以体检照旧通过，但 drain 状态读不到会单独计入
`summary.drain_unavailable`（人类模式打印明细），退出码为 `3`。

**drain 报 `target must not be self`**：`--target` 写成了旧节点自己的地址。

**drain 后节点不再被调度到**：这是预期行为——drain 第一步就是停心跳 + 从 master 摘除节点。
回滚用 `drain-cancel`，然后由运维把网关上游切回来（已迁出的连接不会自动搬回）。

**AI 调用卡在确认提示上**：不该发生（见自动化契约第 3 条）。若遇到，说明命令没带 `--yes`
且 stdin 被误判为终端——优先检查调用方式，别改成"自动填空输入"绕过。

**相关链接：**

- [部署指南](/server/operations/deployment) - 组件部署与高可用
- [Kubernetes 部署](/server/operations/kubernetes) - K8s 部署详解
- [扩缩容](/server/operations/scaling) - 扩容 / 缩容步骤
- [本地环境](/server/tools/windows-env) - etcd / nats / redis / mysql 一键起停
- [AI Skill](/server/tools/ai-skill) - 开发范式与模板
