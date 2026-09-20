# Clover 文档编写规范

> 参考 [NEAR Docs](https://docs.near.org/) 的清晰结构，制定本规范。

## 核心原则

### 1. 分层渐进式组织

文档内容按学习路径组织，从基础到高级：

```
Concepts → Build → Tutorials → Tools → API → Examples
```

### 2. 清晰的导航结构

使用 Mintlify 的 `tabs` + `navigation` + `group` 三级导航：

```json
{
  "tabs": ["服务端", "客户端"],
  "navigation": [
    {
      "group": "核心概念",
      "pages": ["concepts/architecture", "concepts/data-flow"]
    },
    {
      "group": "开发指南", 
      "pages": ["development/handler", "development/configuration"]
    }
  ]
}
```

### 3. 卡片式首页

首页使用卡片式布局，直接链接到核心部分：

```markdown
## 浏览文档

<卡片标题="快速上手" description="5 分钟跑通 Demo" link="/server/quickstart" />
<卡片标题="核心概念" description="架构、数据流、事件系统" link="/server/concepts" />
<卡片标题="开发指南" description="Handler、配置、调试" link="/server/development" />
<卡片标题="部署运维" description="Kubernetes、监控、性能" link="/server/operations" />
```

## 文档结构规范

### 目录组织

```
clover-doc/
├── index.md              # 首页（概览 + 卡片导航）
├── mint.json             # 配置（导航、主题、颜色）
├── server/
│   ├── index.md          # 服务端概览
│   ├── quickstart.md     # 快速开始（5分钟上手）
│   ├── install.md        # 环境安装
│   ├── concepts/         # 核心概念（理论）
│   ├── development/      # 开发指南（实践）
│   ├── examples/         # 示例代码
│   ├── operations/       # 运维部署
│   ├── security/         # 安全相关
│   └── tools/            # 工具文档
└── client/
    ├── index.md          # 客户端概览
    ├── concepts/         # 核心概念
    ├── development/      # 开发指南
    ├── examples/         # 示例
    └── reference/        # 参考手册
```

### 文件命名规范

- 使用小写英文 + 连字符：`network-topology.md`
- 避免中文文件名
- 目录名使用复数形式：`concepts/`、`examples/`、`tools/`

## 页面格式规范

### 1. 标题层级

```markdown
## 本页内容               # 一级标题（页面主题）
## 概念说明               # 二级标题（主要内容）
## 配置示例               # 二级标题
### Master 配置           # 三级标题（子内容）
### Game 配置             # 三级标题
```

### 2. 代码块格式

````markdown
```go 标题
package main
// 代码内容
```

```yaml 配置文件
# 配置内容
```

```bash 命令
# 命令内容
```
````

**要求**：
- 每个代码块必须标注语言类型
- 复杂代码块添加标题说明
- 保持代码简洁，必要时省略无关部分

### 3. 表格格式

```markdown
| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `server_type` | string | `"all"` | 进程角色 |
| `listen_ws` | string | `"127.0.0.1:8001"` | WebSocket 地址 |
```

> 上表仅为**格式示例**，值非引擎默认值（引擎配置默认见 `server/development/configuration.md`）。

**要求**：
- 表头清晰
- 对齐格式
- 适当使用代码格式

### 4. 提示框格式

```markdown
> **注意：**   需要 Go 1.25+ 和 Unity 6（6000.x）。

> **提示：**   开发时建议使用 all 模式。

> **警告：**   生产环境请勿暴露 admin 端口。
```

### 5. 列表格式

```markdown
## 功能特性

- **分布式架构**：Gateway / Game / Master 三角色分离
- **状态同步**：Load-Modify-Return 模型
- **消息路由**：Handler 模式处理请求
```

## 内容编写规范

### 1. 页面开头

每个页面开头应包含：

```markdown
## 这篇文档讲什么？

简要说明本页面的内容和目标读者。

## 前置条件

- 需要了解的概念
- 需要安装的工具
```

### 2. 代码示例

- 提供完整可运行的示例
- 包含必要的 import 语句
- 添加注释说明关键点

```go
// handler/login.go
func Login(ctx *Ctx, req *LoginReq) (*LoginResp, error) {
    // 1. 验证用户
    user := ctx.LoadUser(req.UserId)
    
    // 2. 更新状态
    user.LastLogin = time.Now()
    
    // 3. 返回响应（引擎自动提交）
    return &LoginResp{Token: user.Token}, nil
}
```

### 3. 配置说明

配置文档应包含：

```markdown
## 配置文件

`configs/all/server.yaml`：

```yaml
# 配置内容
```

## 配置项说明

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| ... | ... | ... | ... |

## 环境变量

支持环境变量覆盖：

```bash
export CLOVER_MASTER_ADDR="192.168.1.100:8021"
```
```

### 4. 错误处理

文档应包含常见错误和解决方案：

```markdown
## 常见问题

### 连接失败

**症状**：`connection refused`

**原因**：服务未启动或端口配置错误

**解决**：
1. 检查服务是否启动
2. 确认端口配置一致
```

## Mintlify 配置规范

### 1. 颜色主题

```json
{
  "colors": {
    "primary": "#1FB858",    // Clover 绿
    "light": "#1FB858",
    "dark": "#1FB858"
  }
}
```

### 2. 导航配置

```json
{
  "tabs": [
    { "name": "服务端", "url": "/server" },
    { "name": "客户端", "url": "/client" }
  ],
  "topbarCtaButton": {
    "name": "快速上手",
    "url": "/server/quickstart"
  }
}
```

### 3. 搜索配置

```json
{
  "search": {
    "prompt": "搜索文档..."
  }
}
```

## 质量检查清单

### 发布前检查

- [ ] 所有代码示例可运行
- [ ] 链接有效
- [ ] 配置项与实际代码一致
- [ ] 无拼写错误
- [ ] 格式统一

### 定期维护

- [ ] 每月检查链接有效性
- [ ] 代码示例与最新版本同步
- [ ] 根据用户反馈更新内容
- [ ] 清理过时文档

## 参考资源

- [NEAR Docs](https://docs.near.org/) - 文档结构参考
- [Mintlify 文档](https://mintlify.com/docs) - 框架使用指南
- [技术写作指南](https://developers.google.com/style) - Google 技术写作规范
