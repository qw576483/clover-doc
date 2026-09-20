# 网络配置指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的网络配置，包括 WebSocket、TCP 和 UDP 协议的配置和优化。目标读者是想要配置和优化网络层的开发者。

## 前置条件

- 了解网络协议基础
- 熟悉 Clover 引擎的配置文件结构
- 了解部署环境（本地开发、生产环境）

## 快速开始

### 1. 基本网络配置

在 `configs/all/server.yaml` 中配置网络参数：

```yaml
# 网关配置
gateway:
  listen_ws: "127.0.0.1:8001"       # WebSocket 监听地址
  listen_tcp: "127.0.0.1:8002"      # TCP 监听地址
  listen_udp: "127.0.0.1:8003"      # UDP 监听地址
  ws_path: "/ws"                    # WebSocket 路径
  ws_allow_all_origins: true        # 允许跨域 WS
```

### 2. 启动服务

```bash
# 启动服务
go run . -config configs/all/server.yaml

# 验证端口监听
netstat -tlnp | grep -E '(8001|8002|8003)'
```

## 网络协议详解

### WebSocket (WS)

WebSocket 提供全双工通信，适合实时性要求高的游戏场景。

```yaml
gateway:
  listen_ws: "0.0.0.0:8001"         # 监听所有接口
  ws_path: "/ws"                    # WebSocket 路径
  ws_allow_all_origins: true        # 允许跨域（开发环境）
```

**客户端连接示例：**

```javascript
// 浏览器连接
const ws = new WebSocket('ws://localhost:8001/ws');
ws.binaryType = 'arraybuffer';

// 线协议：一条**二进制消息** = 一个客户端帧 [4B 大端 requestID][4B 大端 msgID][body(UTF-8 JSON)]
// ——不是 JSON 文本包；requestID==0 表示推送，回包 msgID 恒为 0（按 requestID 配对）
function sendFrame(msgID, bodyObj) {
    const body = new TextEncoder().encode(JSON.stringify(bodyObj));
    const buf = new ArrayBuffer(8 + body.length);
    const view = new DataView(buf);
    view.setUint32(0, 1);          // requestID（>0，请求-回包配对；大端）
    view.setUint32(4, msgID);      // 消息号（大端）
    new Uint8Array(buf, 8).set(body);
    ws.send(buf);
}

ws.onopen = function() {
    console.log('WebSocket connected');
    // 登录：msgID=2（EMsg.Login），body 为 ELoginRequest{token}
    // （token 由账号服 HTTP 换取，登录体只有 token；见 auth-server.md）
    sendFrame(2, { token: '<账号服换来的 JWT>' });
};

ws.onmessage = function(event) {
    const view = new DataView(event.data);
    const requestID = view.getUint32(0);
    const msgID = view.getUint32(4);
    const body = new TextDecoder().decode(new Uint8Array(event.data, 8));
    console.log('Received:', { requestID, msgID, body });
};

ws.onclose = function() {
    console.log('WebSocket disconnected');
};
```

### TCP 连接

TCP 提供可靠的连接，适合需要保证数据完整性的场景。

```yaml
gateway:
  listen_tcp: "0.0.0.0:8002"        # 监听所有接口
```

**客户端连接示例（Go）：**

```go
package main

import (
    "fmt"
    "net"
    "encoding/binary"
    "bytes"
)

func main() {
    conn, err := net.Dial("tcp", "localhost:8002")
    if err != nil {
        panic(err)
    }
    defer conn.Close()
    
    // 发送消息
    msg := []byte("hello")
    buf := new(bytes.Buffer)
    binary.Write(buf, binary.BigEndian, uint32(len(msg)))
    buf.Write(msg)
    conn.Write(buf.Bytes())
    
    // 读取响应
    response := make([]byte, 1024)
    n, err := conn.Read(response)
    if err != nil {
        panic(err)
    }
    fmt.Printf("Received: %s\n", response[:n])
}
```

### UDP 连接

UDP 提供低延迟通信，适合实时性要求极高的场景。

```yaml
gateway:
  listen_udp: "0.0.0.0:8003"        # 监听所有接口
```

**客户端连接示例（Go）：**

```go
package main

import (
    "fmt"
    "net"
)

func main() {
    conn, err := net.Dial("udp", "localhost:8003")
    if err != nil {
        panic(err)
    }
    defer conn.Close()
    
    // 发送数据
    msg := []byte("hello udp")
    conn.Write(msg)
    
    // 读取响应
    response := make([]byte, 1024)
    n, err := conn.Read(response)
    if err != nil {
        panic(err)
    }
    fmt.Printf("Received: %s\n", response[:n])
}
```

## 高级配置

### 1. TLS/SSL 配置

```yaml
gateway:
  tls_cert: "certs/server.pem"      # TLS 证书路径
  tls_key: "certs/server-key.pem"   # TLS 私钥路径
  tcp_tls_disabled: false           # false（默认）=TCP 口也走 TLS；true=显式保留明文 TCP
  wt_cert: ""                       # WebTransport 证书（留空=自动生成）
  wt_key: ""                        # WebTransport 私钥
  wt_pin: true                      # 是否对 WebTransport 启用证书固定
```

**覆盖哪些入口**：配了 `tls_cert` 后 WS / QUIC / WebTransport 全走 TLS；**TCP 口默认也走 TLS**
（`tcp_tls_disabled: false`），Unity 客户端用 `GameConfig.UseTls = true` 匹配（两者必须相反）。
TCP/WS 的 TLS 下限是 **1.2**（原生 `SslStream` 大多只到 1.2），QUIC/WT 仍是 1.3。
把 `tcp_tls_disabled` 设为 `true` 只影响 TCP——那属显式降级，启动日志会告警。

**生成自签名证书：**

```bash
# 使用 mkcert 生成本地证书
cd clover-server-tools/mkcert
go run main.go -install

# 生成证书
mkdir -p ../../certs
mkcert -cert-file ../../certs/server.pem -key-file ../../certs/server-key.pem localhost 127.0.0.1
```

### 1.1 会话通道加密（AES-256-GCM，TLS 之上再加一层）

登录成功后网关可对本连接做**整帧**加解密，业务与客户端均无需接线：

```text
客户端登录（ELoginRequest.encrypt=true，引擎按平台能力自动声明）
  → 服务端生成 32B 随机密钥，随 ELoginReply.session_key（base64，明文）下发
  → 此后双方所有帧 = [12B nonce][ciphertext||tag(16B)]（8B 帧头一起加密）
```

| 项 | 说明 |
|---|---|
| 协商 | **客户端声明制**：不声明（robot / msg-client / 网页工具）即保持明文，老客户端不会"收到密钥却解不开" |
| 密钥生成 | `auth.Handler` 在 `req.Encrypt` 为真时生成（`session.NewKey()`）；生成失败**明确报错**，不静默退化明文 |
| 网关启用 | `bootstrap` 的 `WithCryptoKeyExtractor(auth.ExtractSessionKey())`；按回包 `session_key` 字段解析，与 opcode 解耦 |
| 不加密的帧 | ① 携带密钥的登录回包自身（客户端要靠它取密钥）；② `EMsgBindUDP` 绑定帧（网关按明文读令牌） |
| 换绑 / 二次登录 | 服务端会轮换密钥（老密钥加密发出该回包后切换到新密钥），客户端覆盖并重开握手窗口 |
| 与 TLS 的关系 | **不是 TLS 的替代**：登录回包里的密钥本身仍是明文下发，只有链路已有 TLS 才安全 |

### 2. 连接管理配置

```yaml
gateway:
  max_frame_size: 10485760          # 单帧上限（10MB，引擎默认值；与客户端帧上限常量同值）
  reconnect_grace: 30s              # 重连宽限期
  disconnect_grace: 30s             # 断线宽限期
```

**配置说明：**
- `max_frame_size`：单帧最大大小，防止恶意大包攻击
- `reconnect_grace`：断开后保留 owner 记录，宽限期内重连标记为 reconnect=true（**引擎默认 0=关闭**，需显式配置；示例 30s 为业务取值）
- `disconnect_grace`：断开后延迟触发硬掉线，宽限期内重连取消硬掉线（**引擎默认 0=立即触发**；示例 30s 为业务取值）

### 3. WebTransport 配置

```yaml
gateway:
  enable_wt: true                   # 在 WS 端口号上启用 WebTransport
  wt_cert: ""                       # WebTransport 专用证书
  wt_key: ""                        # WebTransport 专用私钥
  wt_pin: true                      # 是否对 WebTransport 启用证书固定
```

**WebTransport 优势：**
- 基于 QUIC 协议，提供更好的性能
- 支持多路复用，减少连接建立时间
- 提供更好的拥塞控制

## 性能优化

### 1. 连接数限制

```yaml
# 在网关配置中限制连接数
gateway:
  max_conns: 10000            # 最大连接数（yaml key: max_conns）
```

**监控连接数：**

```bash
# 使用 netstat 监控
netstat -an | grep :8001 | wc -l

# 使用 ss 监控
ss -s
```

### 2. 心跳检测

```yaml
logic:
  heartbeat: 30s                    # 心跳间隔
  frame_timeout: 30s                # 单帧处理上限
```

**心跳机制说明：**
- 客户端定期发送心跳包
- 服务端检测心跳超时
- 超时断开连接，释放资源

### 3. 缓冲区优化

```go
// 在代码中优化缓冲区
func optimizeBuffer() {
    // 使用连接池
    pool := &sync.Pool{
        New: func() interface{} {
            return make([]byte, 4096)
        },
    }
    
    // 获取缓冲区
    buf := pool.Get().([]byte)
    defer pool.Put(buf)
    
    // 使用缓冲区
    // ...
}
```

## 安全配置

### 1. 防火墙配置

```bash
# Linux 防火墙配置
sudo ufw allow 8001/tcp    # WebSocket
sudo ufw allow 8002/tcp    # TCP
sudo ufw allow 8003/udp    # UDP

# 或者使用 iptables
sudo iptables -A INPUT -p tcp --dport 8001 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8002 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 8003 -j ACCEPT
```

### 2. DDoS 防护

网关**内置**三层限流（都在 `gateway` 配置段，见 `gwcore.Config`）：

| 层 | 键 | 行为 |
|---|---|---|
| 连接建立速率 | `max_conns_per_sec` | 每秒新建连接数上限（滑动窗口），超限按下一行处理 |
| 等候队列 | `queue_cap` / `queue_release_per_sec` / `queue_timeout` | 不排队（默认）时超限**直接关连接**；启用后先排队、按速率放行、超时关闭，并下发 `EMsgQueuePosition`（前面还有 N 人） |
| 单连接消息速率 | 默认 `GCRA(64, 128)`（`internal/app/bootstrap.go`） | 单连接 64 帧/秒、突发 128，超限丢帧并记 `rejected_total{reason="rate_limit"}` |

> 仍可叠加反向代理层（Nginx / Cloudflare）的 IP 级防护；业务级限流用 `pkg/runtime/ratelimit`。

### 3. 连接限制

> **注意：** 引擎**不内置**每 IP 连接数限制（`max_connections_per_ip`）。只有全连接数上限（`gateway.max_conns`，按活跃会话数）与上表的连接建立速率。
> 需要 IP 级限制时在反向代理层配置，或通过 `g.OnAdminHTTP` 注册自定义运维接口监控连接数。

## 监控与调试

### 1. 连接监控

```go
import "github.com/qw576483/clover-server-engine/pkg/foundation/metrics"

// 通过 metrics.ForModule 创建模块级指标
m := metrics.ForModule("gateway")

// 监控连接数
m.Gauge("connections.total").Set(float64(connectionCount))

// 监控连接类型
m.Gauge("connections.ws").Set(float64(wsConnections))
m.Gauge("connections.tcp").Set(float64(tcpConnections))
m.Gauge("connections.udp").Set(float64(udpConnections))
```

### 2. 网络延迟监控

```go
m := metrics.ForModule("gateway")

// 测量并记录延迟（Duration 内置常用 bucket）
m.Duration("latency.ws").Observe(wsLatency.Seconds())
m.Duration("latency.tcp").Observe(tcpLatency.Seconds())
m.Duration("latency.udp").Observe(udpLatency.Seconds())
```

### 3. 带宽监控

```go
m := metrics.ForModule("gateway")

// 记录流量计数
m.Counter("bandwidth.in").Add(float64(inboundBytes))
m.Counter("bandwidth.out").Add(float64(outboundBytes))
```

## 故障排除

### 1. 端口冲突

**错误信息：**
```
bind: address already in use
```

**解决方案：**
```bash
# 检查端口占用
netstat -tlnp | grep :8001

# 杀死占用进程
kill -9 <PID>

# 或者修改配置文件中的端口号
gateway:
  listen_ws: "127.0.0.1:8004"      # 使用其他端口
```

### 2. 连接超时

**错误信息：**
```
dial tcp: connect: connection timed out
```

**解决方案：**
```bash
# 检查网络连通性
ping localhost

# 检查防火墙设置
sudo ufw status

# 检查服务是否启动
netstat -tlnp | grep :8001
```

### 3. TLS 证书错误

**错误信息：**
```
tls: bad certificate
```

**解决方案：**
```bash
# 重新生成证书
cd clover-server-tools/mkcert
go run main.go -install

# 清除旧证书
rm -rf ../../certs

# 重新生成
mkdir -p ../../certs
mkcert -cert-file ../../certs/server.pem -key-file ../../certs/server-key.pem localhost 127.0.0.1
```

## 最佳实践

### 1. 开发环境配置

```yaml
# 开发环境配置
gateway:
  listen_ws: "127.0.0.1:8001"      # 仅本地访问
  listen_tcp: "127.0.0.1:8002"
  listen_udp: "127.0.0.1:8003"
  ws_allow_all_origins: true        # 允许跨域
  tls_cert: ""                      # 不使用 TLS
  tls_key: ""
```

### 2. 生产环境配置

```yaml
# 生产环境配置
gateway:
  listen_ws: "0.0.0.0:8001"        # 监听所有接口
  listen_tcp: "0.0.0.0:8002"
  listen_udp: "0.0.0.0:8003"
  tls_cert: "certs/server.pem"     # 使用 TLS
  tls_key: "certs/server-key.pem"
  max_conns: 10000                 # 限制连接数（yaml key: max_conns）
```

### 3. 网络架构设计

```yaml
# 分离部署配置
# 网关服配置
gateway:
  listen_ws: "0.0.0.0:8001"
  listen_tcp: "0.0.0.0:8002"
  listen_udp: "0.0.0.0:8003"

# 逻辑服配置
logic:
  listen_addr: "0.0.0.0:8011"      # 内部 TCP 监听
  http_listen: "0.0.0.0:8012"      # 内部 HTTP 控制面

# Master 配置
master_listen_addr: "0.0.0.0:8021"   # 非回环 ⇒ 必须配 master_token（否则启动被拒）
master_http_listen_addr: "0.0.0.0:8022"
master_token: "<强随机串>"            # 内部 RPC 共享密钥；各 game 节点填同一个值
```

## 相关文档

- [配置管理](configuration.md)
- [性能优化](performance.md)
- [安全配置](../operations/kubernetes.md)
- [监控配置](../operations/scaling.md)