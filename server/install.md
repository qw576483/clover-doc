
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

使用 [clover-server-tools](https://github.com/qw576483/clover-server-tools) 的 `windows-env` 一键启动全部依赖：

```powershell
git clone https://github.com/qw576483/clover-server-tools.git
cd clover-server-tools/windows-env/core
go build -o env.exe .
./env.exe start
./env.exe status
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

引擎是标准 Go module，**直接依赖即可，不需要克隆引擎源码**：

```bash
mkdir your-server && cd your-server
go mod init your-server
go get github.com/qw576483/clover-server-engine@latest
```

`go.mod` 里只会多出一行 `require`：

```text
module your-server

go 1.25

require github.com/qw576483/clover-server-engine v0.1.0
```

> 只有**需要改引擎源码**时才克隆引擎，并用 `replace` 指过去：
> `replace github.com/qw576483/clover-server-engine => ../clover-server-engine`

按需额外获取：

| 仓库 | 用途 |
|---|---|
| [clover-server-tools](https://github.com/qw576483/clover-server-tools) | 本地依赖环境、网关调试客户端、压测机器人、集群编排、运营后台 |
| [clover-tools](https://github.com/qw576483/clover-tools) | 打表工具（Excel → Go / C# 强类型代码） |
| [clover-client-unity-engine](https://github.com/qw576483/clover-client-unity-engine) | Unity 客户端引擎（UPM 包） |

## 验证编译

```bash
cd your-server
go build -o server.exe .
./server.exe -config configs/all
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

- [快速上手](quickstart.md) - 构建并运行第一个 demo

- [环境搭建](development/environment.md) - 开发环境详细配置

- [部署指南](operations/deployment.md) - 生产环境部署


