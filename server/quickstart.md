## 这篇文档讲什么？

通过一个完整的服务端工程，5 分钟内体验 Clover Engine 的核心功能：登录、建号、进游戏、数据读写、全服广播。无需任何外部服务即可跑通完整流程。

## 前置条件

- [已安装 Go 1.25+](./install.md)
- 克隆了 `clover-server-engine` 与你的服务端工程（[详见安装文档](./install.md)）

> **提示：** 如果尚未安装 Go 或克隆仓库，请先完成[环境安装](./install.md)。

## 5 分钟上手

### 第一步：构建并启动服务端

```bash
# 进入你的服务端工程目录
cd your-server

# 构建可执行文件
go build -o server.exe .

# 启动 all 模式（master → game → gateway 单进程）
./server.exe -config configs/all
```

**预期输出：**

```
[master] listening on 127.0.0.1:8021
[game]   connected to master
[gateway] listening on 127.0.0.1:8001 (WebSocket)
[gateway] listening on 127.0.0.1:8002 (TCP)
[gateway] listening on 127.0.0.1:8003 (UDP)
```

> **注意：** 启动日志中可能出现 NATS 相关警告（若未安装 NATS），这是正常的。`all` 模式会自动降级，不影响核心功能。

### 第二步：连接测试工具

打开**新的终端窗口**，使用 `msg-client` 工具连接：

```bash
# 进入测试工具目录
cd clover-server-tools/msg-client

# 编译并运行
go build -o client.exe ./cmd/client
./client.exe
```

连接网关：

```
clover> connect 127.0.0.1:8002
已连接到 127.0.0.1:8002
```

### 第三步：体验完整流程

#### 1. 登录

```
clover> login test_user 123123
>>> 已发送 EMsgLogin (id=2): {"token":"eyJhbGciOi..."}

<<< [ELoginReply]
{
  "owner": "test_user",
  "token": "tok-xxx",
  "success": true
}
```

#### 2. 建号

```
clover> send MsgCreatePlayer name=Player1 server_id=1
>>> 已发送 MsgCreatePlayer (id=1000102): {"name":"Player1","server_id":1}

<<< [ReplyMsgCreatePlayer]
{
  "summary": "ok",
  "player_id": "p_1234567890"
}
```

#### 3. 进游戏

```
clover> send MsgEnterGame player_id=p_1234567890
>>> 已发送 MsgEnterGame (id=1000103): {"player_id":"p_1234567890"}

<<< [MsgPlayerFullSync]
{
  "player_id": "p_1234567890",
  "name": "Player1",
  "level": 1
}
```

#### 4. 数据读写（Load-Modify-Return）

```
clover> send MsgSetAnnounce server_id=1 content="Welcome to Clover!"
>>> 已发送 MsgSetAnnounce (id=1000501): {"server_id":"1","content":"Welcome to Clover!"}

<<< [MsgSetAnnounceReply]
{
  "summary": "ok",
  "success": true
}
```

#### 5. 全服广播

设置公告后，所有连接的客户端都会收到全服广播推送：

```
<<< [PushDemoBroadcast]
{
  "content": "Welcome to Clover!"
}
```

## 目录结构

```text
your-server/
└── server/                      # 服务器工程（Go module: your-server）
    ├── main.go                  # 入口：app.Run(*cfgPath)
    ├── configs/
    │   └── all/
    │       └── server.yaml      # 唯一配置文件（server_type/端口/数据/日志/NATS 等段）
    ├── game/
    │   ├── def/                 # 消息号与消息结构定义
    │   │   ├── msg.go           # C2S 消息号（1000101 起）
    │   │   ├── reply.go         # 回复体定义（回包不占消息号，msgID 恒为 0）
    │   │   ├── push.go          # 推送消息号（3002001 起）
    │   │   └── ...             # 其他消息结构
    │   ├── datadef/             # 数据 schema 定义（经 data.RegisterTypeBySchema）
    │   │   ├── player.go        # 玩家结构体/记录集
    │   │   ├── item.go          # 背包记录集
    │   │   ├── kv.go            # KV 存储
    │   │   └── server.go        # 服务器公告
    │   ├── logic/               # game 侧业务逻辑（app.Mount(app.RoleGame, ...)）
    │   │   ├── logic.go         # 表加载
    │   │   ├── player.go        # 建号/进游戏/升级
    │   │   ├── item.go          # 物品
    │   │   ├── server.go        # 公告（Load-Modify-Return 示例）
    │   │   └── ...             # 其他业务逻辑
    │   ├── master_logic/        # master 侧业务逻辑
    │   └── table/               # TSV 配置表（go:embed + table.LoadAll）
```

## 核心概念速览

### 消息号约定

引擎与业务共用消息号空间，引擎占 `[1, 10000]`，业务从独立起点起步：

| 段 | 起点 | 示例 |
| --- | --- | --- |
| C2S | `1000101` | `MsgGetPlayerList`、`MsgCreatePlayer`、`MsgEnterGame` |
| 回包 | 无（不占消息号） | `<请求名>Reply` 结构体，如 `GetPlayerListReply`（按 requestID 配对） |
| 推送 | `3002001` | `PushFrameRoomSync`、`PushDemoBroadcast` |

### Load-Modify-Return 模型

```go
// 读取数据
var player Player
g.LoadStruct(c, datadef.PlayerSchema, playerID, &player)

// 直接修改（无需显式 Save）
player.Level += 1

// handler 返回后引擎自动提交（dirty → 写库 → 字段级增量广播）
return nil
```

## 常见问题

### 启动失败：端口被占用

**症状：** `listen tcp 127.0.0.1:8001: bind: address already in use`

**解决：**

1. 检查是否已有服务端运行：`netstat -ano | findstr :8001`
2. 终止占用进程或修改配置文件端口

### 登录失败：数据库连接错误

**症状：** `dial tcp 127.0.0.1:3306: connect: connection refused`

**解决：**

1. 确保 MySQL 已启动：`mysql -u root -p`
2. 检查配置文件 `configs/all/server.yaml` 中的数据库配置
3. 使用 Windows 一键环境：`cd clover-server-tools/windows-env/core && go build -o env.exe ./main.go && ./env.exe start all`

### NATS 警告日志

**症状：** 启动时出现 `nats: connection failed` 相关日志

**说明：** 这是正常的。`all` 模式下 NATS 是可选依赖，未安装时会自动降级，不影响核心功能。

### 客户端无法连接

**症状：** `connect` 命令后无响应或超时

**解决：**

1. 确认服务端已启动并监听正确端口
2. 检查防火墙设置
3. 尝试使用 `127.0.0.1:8001`（WebSocket）或 `127.0.0.1:8002`（TCP）

## 下一步

**相关链接：**

- [消息号与协议](concepts/proto.md) - 理解消息号三段分配规则

- [进程与挂载](concepts/app-game.md) - 理解角色架构与 `app.Mount` 挂载

- [Handler 开发](development/handler.md) - 深入学习 Context API 和业务编写

- [配置说明](development/configuration.md) - 详细配置项解析

- [部署指南](operations/deployment.md) - 生产环境部署
