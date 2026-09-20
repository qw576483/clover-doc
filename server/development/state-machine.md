# 状态机指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的状态机系统，包括 FSM（有限状态机）的基本用法、状态转换和实际应用示例。目标读者是想要管理游戏流程和房间状态的开发者。

## 前置条件

- 了解状态机基本概念
- 熟悉 Clover 引擎的项目结构
- 了解游戏流程管理需求

## FSM 有限状态机

Clover 内置 FSM（Finite State Machine）有限状态机，用于管理游戏流程和房间状态。

## 基本用法

```go
import (
    "time"
    "github.com/qw576483/clover-server-engine/pkg/runtime/fsm"
)

// 创建状态机（初始态 "Idle"，不要求预先 RegisterState）
m := fsm.New(fsm.State("Idle"))

// 注册状态（StateDef 结构体包含 OnEnter/OnTick/OnExit 钩子，均可省略）
m.RegisterState(fsm.State("Idle"), fsm.StateDef{
    OnTick: func(m *fsm.Machine, dt time.Duration) { /* 每帧调用 */ },
})
m.RegisterState(fsm.State("Fighting"), fsm.StateDef{
    OnEnter: func(m *fsm.Machine, from fsm.State, payload any) { /* 进入 */ },
    OnTick:  func(m *fsm.Machine, dt time.Duration) { /* 每帧调用 */ },
    OnExit:  func(m *fsm.Machine, to fsm.State, payload any) { /* 离开 */ },
})

// 注册转移（from → to，事件名 "start_battle"，可带守卫/动作）
m.Transition(fsm.State("Idle"), fsm.State("Fighting"), "start_battle",
    fsm.WithGuard(func(m *fsm.Machine, from fsm.State, payload any) bool {
        return ready // 守卫返回 false 则 Trigger 报 ErrGuard
    }),
)

// 触发转移
if err := m.Trigger("start_battle", nil); err != nil {
    // err 可能是 ErrUnknownEvent / ErrGuard / ErrRace / ErrUnknownState
}
```

## 游戏流程

```go
// 游戏流程状态机
m := fsm.New(fsm.State("Login"))

// 注册状态
m.RegisterState(fsm.State("Login"), fsm.StateDef{...})
m.RegisterState(fsm.State("Lobby"), fsm.StateDef{...})
m.RegisterState(fsm.State("Battle"), fsm.StateDef{...})

// 注册转移
m.Transition(fsm.State("Login"), fsm.State("Lobby"), "login_success")
m.Transition(fsm.State("Lobby"), fsm.State("Battle"), "enter_battle")
m.Transition(fsm.State("Battle"), fsm.State("Lobby"), "battle_end")
```

## 房间状态

```go
// 房间状态机
m := fsm.New(fsm.State("Waiting"))

// 注册状态
m.RegisterState(fsm.State("Waiting"), fsm.StateDef{...})
m.RegisterState(fsm.State("Playing"), fsm.StateDef{...})
m.RegisterState(fsm.State("Finished"), fsm.StateDef{...})

// 注册转移
m.Transition(fsm.State("Waiting"), fsm.State("Playing"), "all_ready")
m.Transition(fsm.State("Playing"), fsm.State("Finished"), "game_over")
m.Transition(fsm.State("Finished"), fsm.State("Waiting"), "restart")
```

## 状态回调

| 回调 | 说明 |
|------|------|
| `OnEnter` | 进入状态时触发 |
| `OnTick` | 状态每帧更新 |
| `OnExit` | 退出状态时触发 |

> 字段名见 `fsm.StateDef`（`OnEnter` / `OnTick` / `OnExit`），不是小写 `onEnter`。

## 状态查询

```go
// 获取当前状态（方法是 Current()，不是 CurrentState()）
current := m.Current()   // 返回 fsm.State

// 检查是否在某个状态
if current == fsm.State("Fighting") {
    // 处理战斗逻辑
}
```

## 状态转换

```go
// 触发转移（event 为 Transition 声明的事件名）
if err := m.Trigger("start_battle", nil); err != nil {
    // ErrUnknownEvent / ErrGuard / ErrRace / ErrUnknownState
}

// 强制转移（绕过守卫，用于 GM/运维强制改态）
if err := m.Force(fsm.State("Battle"), nil); err != nil {
    // ErrUnknownState：目标态未 RegisterState
}
```
