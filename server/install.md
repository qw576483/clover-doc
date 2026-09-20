
## 这篇文档讲什么？

介绍运行 Clover Engine 及其业务工程所需的完整环境，包括 Go 编译器、数据库（MySQL/Redis）和中间件（NATS/etcd）。

## 系统要求

| 依赖 | 版本 | 用途 |
|---|---|---|
| Go | 1.25+ | 编译引擎与业务代码 |
| MySQL | 8.0+ | 玩家数据持久化 |
| Redis | 7.0+ | 缓存、分布式锁、排行榜 |
| etcd | 3.5+ | 服务发现、配置中心 |
| NATS | 2.10+ | 跨服消息、事件总线（`all` 模式可选） |

> **注意：** 内存至少 8GB，磁盘至少 10GB 可用空间。


## 安装 Go

### Windows

1. 访问 [Go 官方下载页](https://go.dev/dl/)
2. 下载 `go1.25.windows-amd64.msi` 并运行安装向导
3. 验证安装：

```powershell
go version
```

### Linux / macOS

```bash
wget https://go.dev/dl/go1.25.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.25.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
go version
```

## 安装数据库与中间件

### Windows 一键环境（推荐）

使用 `windows-env` 工具一键启动所有依赖：

```powershell
cd clover-server-tools/windows-env/core
go build -o core/env.exe ./main.go
core/env.exe start all
core/env.exe status
```

### Linux / macOS 手动安装

```bash
# MySQL
sudo apt install mysql-server-8.0

# Redis
sudo apt install redis-server

# etcd
wget https://github.com/etcd-io/etcd/releases/download/v3.5.0/etcd-v3.5.0-linux-amd64.tar.gz
tar -xzf etcd-v3.5.0-linux-amd64.tar.gz
sudo cp etcd-v3.5.0-linux-amd64/etcd* /usr/local/bin/

# NATS
wget https://github.com/nats-io/nats-server/releases/download/v2.10.0/nats-server-v2.10.0-linux-amd64.tar.gz
tar -xzf nats-server-v2.10.0-linux-amd64.tar.gz
sudo cp nats-server-v2.10.0-linux-amd64/nats-server /usr/local/bin/
```

## 获取代码

三个仓库平级放置：

```text
full-dev/
├── clover-server-engine/     # 引擎本体
├── your-server/              # 你的服务端工程（通过 replace 指令引用本地引擎）
└── clover-doc/               # 文档站
```

## 验证编译

```bash
cd clover-server-engine && go build ./...
cd ../clover-server-tools/table/core && go build ./...
cd ../msg-client && go build -o client ./cmd/client
```

> **注意：** `go build` 报 `connection refused` 是正常的——代码本身不依赖运行中的服务，只有启动并连接配置中心/数据库时才需要。


## 常见问题

| 问题 | 解决方案 |
|---|---|
| `go build` 报 `connection refused` | 正常现象，运行时才需要连接服务 |
| Windows 临时目录测试报 `Access is denied` | 设置 `$env:TMPDIR = "c:\\clover-tmp"` |
| staticcheck 版本不匹配 | 运行 `go install honnef.co/go/tools/cmd/staticcheck@latest` |

## 下一步


**相关链接：**

- [快速上手](/server/quickstart) - 构建并运行第一个 demo

- [环境搭建](/server/development/environment) - 开发环境详细配置

- [部署指南](/server/operations/deployment) - 生产环境部署


