
# 构建下一代游戏

Clover 是一套面向中重度游戏的全栈框架。服务端 Go 分布式架构 + 客户端 Unity 引擎，从立项到上线一站覆盖。

```go Go 服务端
package main

import (
    "clover-server-engine/pkg/app"
    "clover-server-engine/pkg/foundation/logger"
    _ "your-game/server/logic"
)

func main() {
    if err := app.Run("configs/all"); err != nil {
        logger.Fatal("启动失败", logger.Field("err", err))
    }
}
```
```csharp Unity 客户端
var config = new GameConfig
{
    ServerAddr = "127.0.0.1:8002",   // 网关 TCP 口（gateway.listen_tcp）
    MaxReconnectCount = 5,
    UseTls = true,                   // 与服务端 gateway.tcp_tls_disabled 相反（默认 false 时这里 true）
};
Game.Launch(config);
// 第 1 参 = 网关 TCP 口；第 2 参 = 网关 UDP 口（gateway.listen_udp），留空=不启用不可靠通道
CloverNet.Init("127.0.0.1:8002", "127.0.0.1:8003");
```

> **注意：**   需要 Go 1.25+ 和 **Unity 6（6000.x）**。详见 [环境安装](/server/install)。


  ### 安装 Go 并克隆项目

    ```bash
    git clone https://github.com/qw576483/clover-full.git
    ```
  
  ### 构建并启动服务端

    ```bash
    cd clover/your-server
    go build -o server.exe .
    ./server.exe -config configs/all
    ```
  
  ### Unity 导入客户端包

    Package Manager → Add package from git URL → 输入仓库地址
  
  ### 连接并运行

    网页端连接 `ws://localhost:8001`；原生客户端连 `127.0.0.1:8002`（TCP）。登录进游戏。
  

## 为什么选择 Clover？

      NATS 事件总线 + 多进程协作，Gateway / Game / Master 三角色分离，水平扩展支撑万人同服。
        读取 → 修改 → 返回，handler 返回即自动提交，无需手动 Save，消除遗忘持久化的 bug。
        客户端 UPM 包内置状态同步，AOI 视野管理 + 帧同步房间，开箱即用。
        打表工具、调试客户端、可视化测试、Windows 一键环境，开发体验拉满。
  

## 浏览文档

<Columns cols={2}>
  <Card title="快速上手" icon="rocket" href="/server/quickstart">
    5 分钟跑通 Demo，体验完整的消息收发流程
  </Card>
  <Card title="客户端" icon="gamepad" href="/client">
    Unity UPM 包集成、网络接入、WorldSync 世界同步
  </Card>
  <Card title="核心概念" icon="lightbulb" href="/server/concepts">
    进程模型、数据流、事件系统、协议设计
  </Card>
  <Card title="部署运维" icon="server" href="/server/operations">
    Kubernetes 部署、监控告警、性能调优
  </Card>
</Columns>
  
