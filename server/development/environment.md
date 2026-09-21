# 开发环境配置

## 这篇文档讲什么？

本文档指导您搭建 Clover 游戏服务器的开发环境，包括所有必要的组件安装和配置。目标读者是想要开始开发 Clover 游戏的开发者。

## 前置条件

- 了解基本的开发环境配置
- 熟悉命令行操作
- 了解数据库和消息队列基础

## 环境要求

| 组件 | 版本 | 说明 | 必需 |
|------|------|------|------|
| Go | 1.25+ | 服务端运行时 | 是 |
| NATS | 2.10+ | 事件总线 | 是 |
| MySQL | 8.0+ | 数据库 | 是 |
| Redis | 7.0+ | 缓存 | 推荐 |
| Docker | 24.0+ | 容器化部署 | 可选 |
| etcd | 3.5+ | 服务发现 | 可选 |

## 快速开始

### 1. 一键安装脚本

```bash
#!/bin/bash
# install.sh - 一键安装开发环境

echo "开始安装 Clover 开发环境..."

# 安装 Go
echo "安装 Go..."
wget -q https://go.dev/dl/go1.25.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.25.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# 安装 NATS
echo "安装 NATS..."
wget -q https://github.com/nats-io/nats-server/releases/download/v2.10.0/nats-server-v2.10.0-linux-amd64.tar.gz
tar -xzf nats-server-v2.10.0-linux-amd64.tar.gz
sudo mv nats-server-v2.10.0-linux-amd64/nats-server /usr/local/bin/

# 安装 MySQL
echo "安装 MySQL..."
sudo apt update
sudo apt install -y mysql-server

# 安装 Redis
echo "安装 Redis..."
sudo apt install -y redis-server

echo "安装完成！请运行以下命令启动服务："
echo "  sudo systemctl start mysql"
echo "  sudo systemctl start redis"
echo "  nats-server &"
```

### 2. Docker 开发环境

```bash
# 使用 docker-compose 启动所有依赖服务
docker-compose up -d

# 检查服务状态
docker-compose ps
```

**docker-compose.yml：**

```yaml
version: '3.8'

services:
  nats:
    image: nats:2.10
    ports:
      - "4222:4222"
      - "8222:8222"
    command: "-js"
    
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: clover_game
      MYSQL_USER: clover
      MYSQL_PASSWORD: clover123
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
      
  redis:
    image: redis:7.0
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
      
  etcd:
    image: quay.io/coreos/etcd:v3.5.0
    environment:
      ETCD_NAME: clover
      ETCD_DATA_DIR: /etcd-data
      ETCD_LISTEN_CLIENT_URLS: http://0.0.0.0:2379
      ETCD_ADVERTISE_CLIENT_URLS: http://localhost:2379
    ports:
      - "2379:2379"

volumes:
  mysql_data:
  redis_data:
```

## 组件安装

### 1. Go 安装

**Linux：**

```bash
# 下载 Go 1.25+
wget https://go.dev/dl/go1.25.linux-amd64.tar.gz

# 解压到 /usr/local
sudo tar -C /usr/local -xzf go1.25.linux-amd64.tar.gz

# 添加到 PATH
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# 验证安装
go version
```

**macOS：**

```bash
# 使用 Homebrew
brew install go

# 或者下载安装
wget https://go.dev/dl/go1.25.darwin-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.25.darwin-amd64.tar.gz
```

**Windows：**

```bash
# 下载安装包
# https://go.dev/dl/go1.25.windows-amd64.msi

# 或者使用 chocolatey
choco install golang
```

### 2. NATS 安装

```bash
# 下载 NATS Server
wget https://github.com/nats-io/nats-server/releases/download/v2.10.0/nats-server-v2.10.0-linux-amd64.tar.gz

# 解压
tar -xzf nats-server-v2.10.0-linux-amd64.tar.gz

# 移动到系统目录
sudo mv nats-server-v2.10.0-linux-amd64/nats-server /usr/local/bin/

# 验证安装
nats-server --version

# 启动 NATS
nats-server -js &
```

### 3. MySQL 安装

**Ubuntu/Debian：**

```bash
# 更新包列表
sudo apt update

# 安装 MySQL
sudo apt install mysql-server

# 启动 MySQL
sudo systemctl start mysql
sudo systemctl enable mysql

# 安全安装
sudo mysql_secure_installation
```

**CentOS/RHEL：**

```bash
# 安装 MySQL
sudo yum install mysql-server

# 启动 MySQL
sudo systemctl start mysqld
sudo systemctl enable mysqld

# 获取临时密码
sudo grep 'temporary password' /var/log/mysqld.log

# 安全安装
sudo mysql_secure_installation
```

### 4. Redis 安装

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install redis-server

# 启动 Redis
sudo systemctl start redis
sudo systemctl enable redis

# 验证安装
redis-cli ping
# 应该返回 PONG
```

### 5. etcd 安装（可选）

```bash
# 下载 etcd
ETCD_VER=v3.5.0
wget https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz

# 解压
tar -xzf etcd-${ETCD_VER}-linux-amd64.tar.gz

# 移动到系统目录
sudo mv etcd-${ETCD_VER}-linux-amd64/etcd /usr/local/bin/
sudo mv etcd-${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/

# 启动 etcd
etcd --name clover --data-dir /tmp/etcd &
```

## 数据库配置

### 1. 创建数据库和用户

```sql
-- 登录 MySQL
mysql -u root -p

-- 创建数据库
CREATE DATABASE clover_game CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 创建用户
CREATE USER 'clover'@'localhost' IDENTIFIED BY 'clover123';

-- 授权
GRANT ALL PRIVILEGES ON clover_game.* TO 'clover'@'localhost';

-- 刷新权限
FLUSH PRIVILEGES;

-- 验证
SHOW DATABASES;
SELECT user, host FROM mysql.user;
```

### 2. 配置数据库连接

```yaml
# configs/all/server.yaml
data:
  tier: "TierRedisMySQL"
  mysql:
    host: "127.0.0.1"
    port: 3306
    user: "clover"
    pass: "clover123"
    db_name: "clover_game"
    charset: "utf8mb4"
    auto_create: true
    parse_time: true
  redis:
    addr: "127.0.0.1:6379"
    pass: ""
    db: 0
```

## 项目设置

### 1. 获取引擎

引擎是标准 Go module，**直接依赖即可，不需要克隆源码**：

```bash
cd your-server
go mod init your-server
go get github.com/qw576483/clover-server-engine@latest

# 安装依赖
go mod tidy

# 构建项目
go build -o server.exe .
```

### 2. 配置开发环境

```bash
# 创建配置目录
mkdir -p configs/all

# 按「配置管理」文档中的示例编写 server.yaml
vim configs/all/server.yaml

# 修改配置
vim configs/all/server.yaml
```

### 3. 启动开发环境

```bash
# 启动依赖服务
nats-server -js &
sudo systemctl start mysql
sudo systemctl start redis

# 启动服务端
go run main.go -config configs/all/server.yaml

# 或者使用热重载
go install github.com/air-verse/air@latest
air
```

## 验证环境

### 1. 检查服务状态

```bash
# 检查 Go
go version

# 检查 NATS
nats server info

# 检查 MySQL
mysql -u clover -pclover123 -e "SHOW DATABASES;"

# 检查 Redis
redis-cli ping

# 检查 etcd（如果安装了）
etcdctl endpoint health
```

### 2. 运行测试

```bash
# 运行单元测试
go test ./...

# 运行集成测试
go test -tags=integration ./...

# 运行性能测试
go test -bench=. ./...
```

### 3. 访问服务

```bash
# 检查端口监听
netstat -tlnp | grep -E '(8001|8002|8003|8011|8021)'

# 测试 WebSocket 连接
wscat -c ws://localhost:8001/ws

# 测试 HTTP 接口
# 注意：admin 端口（8041）只有 /ping、/routes、/log/level（外加可选 /metrics、/debug/pprof），
# **没有 /health**；健康探针在逻辑服 HTTP 控制面：http://127.0.0.1:8012/healthz
curl http://localhost:8041/ping
```

## IDE 配置

### 1. VS Code

```json
// .vscode/settings.json
{
    "go.useLanguageServer": true,
    "go.lintTool": "golangci-lint",
    "go.lintFlags": ["--fast"],
    "editor.formatOnSave": true,
    "[go]": {
        "editor.defaultFormatter": "golang.go"
    }
}
```

**推荐扩展：**
- Go
- Go Outliner
- Go Test Explorer
- Error Lens

### 2. GoLand

```bash
# 安装 GoLand 插件
# 1. 打开 Settings -> Plugins
# 2. 搜索并安装以下插件：
#    - Go Template
#    - YAML/JSON
#    - Docker
#    - Database Navigator
```

## 常见问题

### 1. Go 版本过低

**错误信息：**
```
Error: go: go.mod requires go >= 1.25
```

**解决方案：**
```bash
# 检查当前版本
go version

# 升级 Go
# Linux
wget https://go.dev/dl/go1.25.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.25.linux-amd64.tar.gz

# macOS
brew upgrade go

# Windows
choco upgrade golang
```

### 2. NATS 连接失败

**错误信息：**
```
Error: connection refused
```

**解决方案：**
```bash
# 检查 NATS 是否启动
ps aux | grep nats-server

# 启动 NATS
nats-server -js &

# 检查端口
netstat -tlnp | grep :4222
```

### 3. MySQL 连接失败

**错误信息：**
```
Error: Access denied for user 'clover'@'localhost'
```

**解决方案：**
```bash
# 检查用户权限
mysql -u root -p -e "SELECT user, host FROM mysql.user;"

# 重新授权
mysql -u root -p -e "GRANT ALL PRIVILEGES ON clover_game.* TO 'clover'@'localhost'; FLUSH PRIVILEGES;"

# 检查密码
mysql -u clover -pclover123 -e "SELECT 1;"
```

### 4. Redis 连接失败

**错误信息：**
```
Error: connection refused
```

**解决方案：**
```bash
# 检查 Redis 是否启动
sudo systemctl status redis

# 启动 Redis
sudo systemctl start redis

# 检查端口
netstat -tlnp | grep :6379
```

### 5. 端口冲突

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
vim configs/all/server.yaml
```

## 开发工具

### 1. 数据库管理工具

```bash
# 安装 MySQL Workbench
sudo snap install mysql-workbench-community

# 或者使用命令行工具
sudo apt install mycli

# 连接数据库
mycli -u clover -pclover123 clover_game
```

### 2. Redis 管理工具

```bash
# 安装 Redis Commander
npm install -g redis-commander

# 启动 Redis Commander
redis-commander

# 访问 http://localhost:8081
```

### 3. API 测试工具

```bash
# 安装 Postman
# https://www.postman.com/downloads/

# 或者使用 httpie
sudo apt install httpie

# 测试 API
http GET http://localhost:8041/ping
```

## 下一步

1. [快速开始](../quickstart.md)
2. [配置管理](configuration.md)
3. [故障排除](../operations/troubleshooting.md)

