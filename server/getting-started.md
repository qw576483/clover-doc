
## 这篇文档讲什么？

如何获取代码、构建服务端、运行测试、以及构建文档站。

## 环境要求

| 依赖 | 版本 | 用途 |
| --- | --- | --- |
| Go | 1.25+ | 编译引擎与业务代码 |
| Node.js | 18+ | 文档构建（Mintlify） |
| NATS（可选） | 任意 | 跨节点推送/事件总线（`all` 模式可省略） |
| MySQL（可选） | 任意 | `simple` 数据模式的持久化后端 |

## 获取代码

三个仓库平级放置：

```text
full-dev/
├── clover-server-engine/     # 引擎本体（go.mod: clover-server-engine）
├── your-server/              # 你的服务端工程（依赖引擎）
└── clover-doc/               # 文档站
```

服务端工程通过 `replace` 指令引用本地引擎：

```text
// your-server/go.mod
require clover-server-engine v0.0.0
replace clover-server-engine => ../../clover-server-engine
```

## 构建服务端

```powershell
cd your-server
go build -o server.exe .

# 运行（all 模式，无需外部服务）
./server.exe -config configs/all
```

## 运行测试

```powershell
# 引擎全量单测
cd clover-server-engine
go test ./...
go vet ./...

# 业务工程测试
cd ../your-server
go test ./...
```

> **注意：** 引擎包约定：**每个包必须配套单测与 `README.md`**，新包落地前请遵循。


## 构建文档

文档站使用 Mintlify 构建（配置文件为 `clover-doc/docs.json`）：

```powershell
cd clover-doc
# 本地预览（Mintlify CLI）
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

- [快速上手](/server/quickstart) - 5 分钟跑通完整流程

- [Handler 开发](/server/development/handler) - 开始编写你的第一个 Handler

- [部署指南](/server/operations/deployment) - 生产环境部署


