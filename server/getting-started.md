
## 这篇文档讲什么？

如何获取代码、构建服务端、运行测试、以及构建文档站。

## 环境要求

| 依赖 | 版本 | 用途 |
| --- | --- | --- |
| Go | 1.25+ | 编译引擎与业务代码 |
| Node.js | 18+ | 文档构建（Mintlify，仅文档站需要） |
| NATS（可选） | 任意 | 跨节点推送/事件总线（`all` 模式可省略） |
| MySQL（可选） | 任意 | `simple` 数据模式的持久化后端 |

## 获取代码

引擎是标准 Go module，**直接依赖即可，不需要克隆引擎源码**：

```bash
mkdir your-server && cd your-server
go mod init your-server
go get github.com/qw576483/clover-server-engine@latest
```

`go.mod`：

```text
module your-server

go 1.25

require github.com/qw576483/clover-server-engine v0.1.0
```

> 只有需要**改引擎源码**时才克隆引擎，并在 `go.mod` 里加一行指过去：
> `replace github.com/qw576483/clover-server-engine => ../clover-server-engine`

文档站（[clover-doc](https://github.com/qw576483/clover-doc)）与本地依赖环境（[clover-server-tools](https://github.com/qw576483/clover-server-tools)）是独立仓库，按需单独 clone。

## 构建服务端

```powershell
cd your-server
go build -o server.exe .

# 运行（all 模式，无需外部服务）
./server.exe -config configs/all
```

## 运行测试

```powershell
# 业务工程测试
cd your-server
go test ./...
go vet ./...

# 引擎自身的测试（克隆引擎后）
cd ../clover-server-engine
go test ./...
go vet ./...
```

> **注意：** 引擎包约定：**每个包必须配套单测与 `README.md`**，新包落地前请遵循。


## 构建文档

文档站使用 Mintlify 构建（配置文件为 `docs.json`）：

```powershell
git clone https://github.com/qw576483/clover-doc.git
cd clover-doc
npx mintlify dev
```

## 常见问题

| 问题 | 解决方案 |
|---|---|
| 启动报错找不到配置 | 确认 `-config` 指向 `configs/all` 目录或文件路径 |
| NATS 连接告警 | `all` 模式下 NATS 是可选依赖，未启动时自动降级为内存总线 |
| 端口占用 | 修改 `configs/all/server.yaml` 中 `gateway.listen_ws`、`gateway.listen_tcp`、`gateway.listen_udp` |

## 下一步


**相关链接：**

- [快速上手](quickstart.md) - 5 分钟跑通完整流程

- [Handler 开发](development/handler.md) - 开始编写你的第一个 Handler

- [部署指南](operations/deployment.md) - 生产环境部署


