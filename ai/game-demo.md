# 游戏 Demo

用 **Clover 引擎 + AI skill** 复刻出来的完整游戏 —— 每款都是独立仓库，从启动菜单到首个关卡整条链路可玩。

> 状态以各项目自己的 `策划/验收表.md` 为准：**零空行 = 可交付**。照实写，虚报"已完成"比写"进行中"难看。

| 仓库 | 实现的游戏 | 范围 | 规模 | 类型 | 状态 | 作者 |
|---|---|---|---|---|---|---|
| [clover-project-super-mario](https://github.com/qw576483/clover-project-super-mario) | 《Super Mario Bros.》(Nintendo, 1985) | World 1-1 / 1-2 | 小 | 2D横版平台跳跃（单机） | **已完成** | [qw576483](https://github.com/qw576483) |
| [clover-project-diablo2](https://github.com/qw576483/clover-project-diablo2) | 《暗黑破坏神 II》(Blizzard, 2000) | Act I 起始两张地图 + 主线任务 | 小 | 2D横版ARPG（单机） | 进行中 | [qw576483](https://github.com/qw576483) |
| `clover-project-cr`（尚未发布） | 《皇室战争》(Supercell, 2016) | 1v1 联机对战 | 小 | 2D竖版即时对战（联机） | 进行中 | [qw576483](https://github.com/qw576483) |
| [clover-project-cs16](https://github.com/qw576483/clover-project-cs16) | 《Counter-Strike 1.6》(Valve, 2003) | 本地开图 + 机器人 / 局域网寻服加入 | 小 | 3D横版FPS（单机-内网联机） | 进行中 | [qw576483](https://github.com/qw576483) |

## 想把自己的 demo 列到这里？

外部作者的开源仓库同样欢迎：

1. 用 Clover 引擎复刻一款游戏（从 [新手指南](ai-quick-start.md) 开始）
2. 交付口径照 [AI 交付 skill](skill.md)：`策划/验收表.md` 零空行、`tools/verify.ps1` 无 FAIL；
3. 到 [clover-doc](https://github.com/qw576483/clover-doc) 提 PR/ISSUE/直接联系作者，照上表加一行。

## 下一步

1. [新手指南](ai-quick-start.md) —— 从装 Unity 6 到让 AI 开出第一个工程
2. [AI 交付 skill](skill.md) —— 两层 skill、交付清单与硬约束
3. [客户端快速开始](../client/quickstart.md) —— 引擎侧的接入手册
