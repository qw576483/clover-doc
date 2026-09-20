
## 这篇文档讲什么？

`windows-env` 是一个 Windows 本地开发环境管理工具，一键启动/停止 MySQL、Redis、etcd、NATS 等依赖服务。

## 安装

```powershell
cd clover-server-tools/windows-env/core
go build -o env.exe ./main.go
```

## 命令

| 命令 | 说明 |
| --- | --- |
| `env.exe start all` | 启动所有服务 |
| `env.exe stop all` | 停止所有服务 |
| `env.exe status` | 查看所有服务状态 |
| `env.exe start mysql` | 启动指定服务 |
| `env.exe stop mysql` | 停止指定服务 |

## 使用示例

```powershell
# 启动所有依赖服务
core\env.exe start all

# 查看状态
core\env.exe status
# 输出：
# MySQL   : running (port 3306)
# Redis   : running (port 6379)
# etcd    : running (port 2379)
# NATS    : running (port 4222)

# 启动服务端
cd your-server
.\server.exe -config configs\all

# 关闭所有服务
core\env.exe stop all
```

## 配置说明

`windows-env` 内置默认配置，各服务端口：

| 服务 | 默认端口 | 配置文件 |
| --- | --- | --- |
| MySQL | 3306 | `core/my.ini`（首次启动自动按基准配置生成生效文件） |
| Redis | 6379 | `redis/redis.conf` |
| etcd | 2379 | 无外部配置文件（用命令行默认值启动） |
| NATS | 4222 | 无外部配置文件（用命令行默认值启动） |

> **注意：** 工具**不会自动下载**组件。缺组件时 `env.exe info` / `start` 会打印官方下载地址，
> 需要人工下载解压后放到 `windows-env/` 对应目录（见 `reference/server-env.md`）。


## 注意事项

- 仅支持 Windows 10/11
- 确保端口未被其他程序占用
- MySQL 数据目录位于 `data/`，不要手动删除

## 下一步


**相关链接：**

- [环境安装](../install.md) - 完整的环境安装指南

- [快速上手](../quickstart.md) - 运行完整 demo


