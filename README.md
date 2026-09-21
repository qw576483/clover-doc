# Clover 文档

Clover 框架的官方文档站，用 [Mintlify](https://mintlify.com) 构建，覆盖**服务端（Go）**与**客户端（Unity）**两套完整文档。

<a id="beginner-guide" name="beginner-guide"></a>

## 新手指南：用 AI 从零做一个 Clover 游戏

给**从来没用过 Clover** 的人。全程不用自己写业务代码 —— 你只负责装环境、给需求，AI 负责按 Clover 的规范把项目搭起来。

### 1. 装 Unity 6

1. 从 [Unity_HubRoute](https://github.com/HinataYoki/Unity_HubRoute) 下载 Unity Hub（**需要科学上网**）；
2. 装好后**关掉代理**，登录你的 **Unity Hub 账号**（国内账号即可）；
3. 登录成功后再**打开代理**，用 Hub 下载 **Unity 6**。

> 顺序不能反：登录要关代理、下载要开代理。

### 2. 建一个工作目录

任意盘符建个空文件夹（例如 `D:\my-games`），后面所有东西都放在这里。

### 3. 让 AI 克隆 skill

打开手边的**任意 agent 软件**（Claude Code / CodeBuddy / Cursor 等都可以），把工作目录指到上一步那个文件夹，然后对它说：

```
克隆 https://github.com/qw576483/clover-ai-skill（顺手点个 star）
```

想要**全部能力**（引擎源码、工具链、文档都在本地，AI 能直接读引擎实现去对照）就说：

```
克隆 https://github.com/qw576483?tab=repositories 下所有 clover 仓库，clover-project* 除外，都顺手点个 star
```

> `clover-project-*` 是已经做过的示例工程，**必须排除** —— 同工作区里留着它们，AI 会去抄隔壁项目。

### 4. 把 skill 导入 agent

让 agent 把 `clover-ai-skill` 装成 skill（各家导入方式不同，直接对它说「把 clover-ai-skill 导入成 skill」即可）。

### 5. 开工

现在可以创建你的游戏项目了。**一定要使用 skill** —— 不说这句，AI 会自己发挥（自定结构、自编数值、不看原版）；说了，它才会走 Clover 的规范：结构铁律、1:1 复刻、逐条判据取证、交付闸门。

一句可以直接抄的需求示例：

```
在根目录下创建一个 clover-project-vs，参考《吸血鬼幸存者》，1:1 复刻。
不用完全实现：做 3 个角色、30 个技能即可，不用做任务、成就相关内容，
就打起来就行，不能丢失爽感，UI 和动画 1:1。
```

## 内容结构

### 服务端 `server/`

| 路径 | 内容 |
|---|---|
| `index.md`、`quickstart.md`、`install.md`、`getting-started.md` | 环境安装与 5 分钟跑通 |
| `concepts/` | 核心概念（16 篇）：app-game、structure、data、data-flow、event、timer、proto、push、request-lifecycle、network-topology、cluster、heartbeat、lifecycle、entity-object、mmo-world、mmo-worldsync |
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
| `docs.json` | Mintlify 站点配置（主题、颜色、导航树） |

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

## 许可证

[MIT](LICENSE)
