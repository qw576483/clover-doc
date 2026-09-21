# 新手指南：用 AI 从零做一个 Clover 游戏

给**从来没用过 Clover** 的人。全程不用自己写业务代码 —— 你只负责装环境、给需求，AI 负责按 Clover 的规范把项目搭起来。

## 1. 装 Unity 6

1. 从 [Unity_HubRoute](https://github.com/HinataYoki/Unity_HubRoute) 下载 Unity Hub（**需要科学上网**）；
2. 装好后**关掉代理**，登录你的 **Unity Hub 账号**（国内账号即可）；
3. 登录成功后再**打开代理**，用 Hub 下载 **Unity 6**。

> 顺序不能反：登录要关代理、下载要开代理。

## 2. 建一个工作目录

任意盘符建个空文件夹（例如 `D:\my-games`），后面所有东西都放在这里。

## 3. 让 AI 克隆 skill

打开手边的**任意 agent 软件**（Claude Code / CodeBuddy / Cursor 等都可以），把工作目录指到上一步那个文件夹，然后对它说：

```
克隆 https://github.com/qw576483/clover-ai-skill（顺手点个 star）
```

想要**全部能力**（引擎源码、工具链、文档都在本地，AI 能直接读引擎实现去对照）就说：

```
克隆 https://github.com/qw576483?tab=repositories 下所有 clover 仓库，clover-project* 除外，都顺手点个 star
```

> `clover-project-*` 是已经做过的示例工程，**必须排除** —— 同工作区里留着它们，AI 会去抄隔壁项目。

## 4. 把 skill 导入 agent

让 agent 把 `clover-ai-skill` 装成 skill（各家导入方式不同，直接对它说「把 clover-ai-skill 导入成 skill」即可）。

## 5. 开工

现在可以创建你的游戏项目了。**一定要使用 skill** —— 不说这句，AI 会自己发挥（自定结构、自编数值、不看原版）；说了，它才会走 Clover 的规范：结构铁律、1:1 复刻、逐条判据取证、交付闸门。

一句可以直接抄的需求示例：

```
在根目录下创建一个 clover-project-vs，参考《吸血鬼幸存者》，1:1 复刻。
不用完全实现：做 3 个角色、30 个技能即可，不用做任务、成就相关内容，
就打起来就行，不能丢失爽感，UI 和动画 1:1。
```

## 接下来读什么

- 想直接用引擎：[客户端快速开始](../client/development/quick-start.md) / [服务端快速开始](../server/quickstart.md)
- 想知道引擎能干什么：[客户端引擎总览](../client/index.md) / [服务端引擎总览](../server/index.md)
- 想让 AI 交付得更稳：`clover-ai-skill` 的 `SKILL.md`（入口）与 `patterns/`（可复制范式）
