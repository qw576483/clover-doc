# Clover 文档

Clover 框架的官方文档站，用 [Mintlify](https://mintlify.com) 构建，覆盖**服务端（Go）**与**客户端（Unity）**两套完整文档。

## 内容结构

### 服务端 `server/`

| 路径 | 内容 |
|---|---|
| `index.md`、`quickstart.md`、`install.md`、`getting-started.md` | 环境安装与 5 分钟跑通 |
| `concepts/` | 核心概念（18 篇）：app-game、structure、data、data-flow、event、timer、proto、push、request-lifecycle、network-topology、cluster、heartbeat、lifecycle、entity-object、mmo-world、mmo-worldsync |
| `development/` | 开发指南（14 篇）：handler、network、persistence、logging、configuration、debugging、error-handling、state-machine、testing、performance、protocol-design、table-design、data-migration、environment |
| `examples/` | 示例（7 篇）：login、chat、room、data、inventory、timer、heartbeat |
| `operations/` | 部署运维（8 篇）：deployment、kubernetes、scaling、monitoring、logging、backup-recovery、performance、troubleshooting |
| `security/` | 安全（5 篇）：auth、auth-server、anti-cheat、input-validation、security-guide |
| `tools/` | 工具说明（6 篇）：windows-env、manager、msg-client、robot、table-tools、ai-skill |

### 客户端 `client/`

| 路径 | 内容 |
|---|---|
| `concepts/` | 架构、设计原则、模块依赖、概念命名 |
| `development/` | network、ui-system、resource、serialization、entity-view、worldsync、event-timer-fsm、object-pool、input、auth、game-facade、presentation-modules、quick-start |
| `examples/login-flow.md` | 注册 / 登录 / 会话建立 / 全量同步 / 断线恢复的完整接入示例 |
| `reference/` | constraints（硬约束）、emsg（消息号）、frame-format（帧格式）、api-cheatsheet（API 速查） |

### 站点文件

| 路径 | 内容 |
|---|---|
| `index.md` | 站点首页（框架定位、快速上手代码片段、选型理由） |
| `logo/`、`favicon.svg`、`styles.css` | 站点资源与样式 |
| `STANDARDS.md` | 文档编写规范（分层组织、导航结构、术语与示例口径）——**新增文档前先读** |
| `docs.json` / `mint.json` | Mintlify 站点配置（主题、颜色、导航树） |

## 本地预览

```bash
npm i -g mintlify
mintlify dev
```

默认地址 `http://localhost:3000`。

## 部署

由 Mintlify 关联本仓库自动部署，站点配置读取仓库根目录的 `docs.json`。

## 相关仓库

| 仓库 | 说明 |
|---|---|
| [clover-server-engine](https://github.com/qw576483/clover-server-engine) | Go 服务端引擎（`server/` 的描述对象） |
| [clover-client-unity-engine](https://github.com/qw576483/clover-client-unity-engine) | Unity 客户端引擎 UPM 包（`client/` 的描述对象） |
| [clover-official-website](https://github.com/qw576483/clover-official-website) | 官网落地页（与本站相互独立，各自部署） |
