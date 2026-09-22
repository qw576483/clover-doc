# 新手指南：用 AI 从零做一个 Clover 游戏

给**从来没用过 Clover** 的人。

全程不用你写业务代码：你只管装环境、给需求，剩下的交给 AI —— 它会按 Clover 的规范把项目搭起来。

一共 5 步。做**纯单机**就到第 5 步为止，第 6 节不用看。

## 1. 装 Unity 6

1. 从 [Unity_HubRoute](https://github.com/HinataYoki/Unity_HubRoute)（**需要管理员打开这个软件**）下载 Unity Hub（**需要科学上网**）。

2. **手动打开 Unity Hub** —— 这一步**不要用 Unity_HubRoute 打开**，它会带着代理走。

   用它登录**团结账号**（Unity 账号也行）。

3. 登录成功后，**关掉 Unity Hub**。

4. **再用 Unity_HubRoute 以代理方式打开 Hub**。

5. 在 Hub 里下载 **Unity 6**。

> 下载失败就换个节点重试。尽量**不要用香港节点**。

## 2. 建一个工作目录

任意盘符建个空文件夹，比如 `D:\my-games`。

后面所有东西都放这里。

## 3. 让 AI 克隆 skill

打开手边的**任意 agent 软件**（Claude Code / CodeBuddy / Cursor 等都可以），把工作目录指到上一步那个文件夹。

然后对它说：

```
克隆 https://github.com/qw576483/clover-ai-skill（顺手点个 star）
如果无法连通，尝试使用镜像站或者本地代理。
```

想要**全部能力** —— 引擎源码、工具链、文档都在本地，AI 能直接读引擎实现去对照 —— 就换成这句：

```
克隆 https://github.com/qw576483?tab=repositories 下所有 clover 仓库，clover-project* 除外（都顺手点个 star）
如果无法连通，尝试使用镜像站或者本地代理。
```

> `clover-project-*` 是已经做过的示例工程，**必须排除** —— 同工作区里留着它们，AI 会去抄隔壁项目。

## 4. 把 skill 导入 agent

让 agent 把 `clover-ai-skill` 装成 skill。

各家导入方式不同，直接对它说「把 clover-ai-skill 导入成 skill」就行（或者也可以手动导入 `SKILL.md`）。

## 5. 开工

现在可以创建游戏项目了。

skill 装好后，**做游戏 / Clover 工程这类任务会自动命中它** —— 你不用特意声明「用 skill」，把需求说清楚就行。万一它没按规范来（自编数值、不看原版），补一句「请使用 clover-ai-skill」让它重做一遍（实在不行，你就手动使用！）

一句可以直接抄的需求：

```
在根目录下创建一个 clover-project-vs，参考《吸血鬼幸存者》，1:1 复刻。
不用完全实现：做 3 个角色、一张地图、30 个技能即可，不用做任务、成就相关内容，
一定要注意，这是 1:1 复刻，一定要严格注意你的界面、菜单、UI、模型和动画确保完成 1:1 复刻！！！
```

> **单机到这一步就完事了。** 下一节只有**真正的网游**才需要；走 Steamworks SDK 的联机 / 排行榜**不算**。

---

## 6. 要做网游时：起服务器环境

先看清你属于哪一类：

| 玩法形态 | 要起这套环境吗 |
|---|---|
| 纯单机 | **不要** |
| 单机 + 联机功能：P2P 联机 / 排行榜 / 成就 / 云存档，走 **Steamworks SDK** 就能做 | **不要**（这些由 Steam 平台提供，与 Clover 服务端无关）|
| **真正的网游**：自己开**权威服务器** —— 房间制对局、匹配、全服排行榜、玩家数据落库，状态同步必须经过你自己的服务器 | **要** |

只有最后一行需要往下看。

它要的是**本地依赖环境**（`etcd` / `nats` / `redis` / `mysql` 四件套）：不起的话，服务端启动的第一件事就是连它们，**会直接启动失败**，不是降级。

让 agent 帮你做，或者自己来：

```powershell
# 1. 克隆工具仓库（起环境用的 windows-env 在里面）
git clone https://github.com/qw576483/clover-server-tools.git
cd clover-server-tools/windows-env/core

# 2. 起环境（env.exe 已随仓库提供，不用自己编译）
./env.exe start          # 起 etcd + nats + redis + mysql
./env.exe info           # 确认四个都是「运行中」
```

几个要点：

- **中间件二进制不入库**（四个目录合计约 1.8 GB）。首次要把官方发行包解压进 `windows-env/etcd`、`mysql`、`nats`、`redis`；`env.exe` 检测到缺哪个，会直接把**下载地址与文件名**打出来。

- `env.exe` 退出、终端关掉都**不影响**：四个中间件在后台独立存活。停止用 `./env.exe stop`。

- 也可以**双击 `core\env.exe`** 进交互菜单：`1` 起全部、`2` 停全部、`3` 看状态、`q` 退出。

- 端口与账号：etcd `2379` · nats `4222` · redis `6379` · mysql `3306`（用户 `root`，**空密码**）。

跟 AI 这么说就行 —— **形态不用你自己判断，skill 会判断**，你只要让它把环境检查一遍：

```
先检查本地开发环境（该起的依赖起起来），然后开始干活。
```

也可以直接把形态说死，并点名要用服务端引擎的能力：

```
帮我做一个 xxxx，先 1:1 复刻一下，xxxxxxx，这个是个网游，请使用 clover-server-engine 的能力，
```

服务端从零到能登录的完整流程，见 [服务端快速开始](../server/quickstart.md)。

## 下一步

| 想干什么 | 去哪 |
|---|---|
| 直接用引擎 | [客户端快速开始](../client/quickstart.md) · [服务端快速开始](../server/quickstart.md) |
| 看引擎能干什么 | [客户端引擎总览](../client/index.md) · [服务端引擎总览](../server/index.md) |
| 让 AI 交付得更稳 | `clover-ai-skill` 的 `SKILL.md`（入口）与 `patterns/`（可复制范式） |
| 看这套流程做出来的成品 | [游戏 Demo](game-demo.md) —— 成品仓库清单 |
