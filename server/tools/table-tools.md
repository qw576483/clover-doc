
## 这篇文档讲什么？

`table-tools` 是策划表工具链，负责将策划提交的 Excel/CSV 文件转换为引擎可加载的 TSV 格式，同时生成 Go 类型化代码。

## 安装

```bash
cd clover-tools/table/core
go build -o table .
```

## 使用

打表**由配置文件驱动**（输入 Excel 目录、输出 tsv / 代码路径、包名等都在 YAML 里），
不像早期版本那样逐个传路径参数：

```bash
# 扫描当前目录的 .yaml/.yml，交互式选择要执行的配置（可循环重选）
./table

# 直接指定配置（跳过选择）
./table -config config.yaml

# 反向：把「源表 txt」打包成 xlsx，交给策划用 Excel 编辑
./table -pack ./tables
```

参数说明：

| 参数 | 说明 |
| --- | --- |
| `-config` | 配置文件路径；留空则扫描当前目录所有 `.yaml` / `.yml` 让你选择 |
| `-force` | 强制覆盖已存在的产物（打表的非 base 层 tsv / `-pack` 的 xlsx） |
| `-pack` | 把指定目录下的「源表 txt」打包成 xlsx（打表的反向操作，见下） |

## 反向模式：源表 txt → xlsx（`-pack`）

打表原本是**单向**的（xlsx → tsv + 强类型代码）。但 AI 只能产出文本、无法直接生成
xlsx，于是约定一种「**源表 txt**」——**与 xlsx 的表头布局完全一致**，只是用 tab 分隔：

```text
name	hp	atk        ← 第 1 行：字段名（空 = 整列无效）
int	int	float32    ← 第 2 行：类型
cs	cs	c          ← 第 3 行：cs 标记（c=仅客户端 / s=仅服务器 / cs=两端 / 空=按配置默认）
名字	生命	攻击       ← 第 4 行：注释
1	100	10.5       ← 第 5 行起：数据（第一列为主键，为空的行跳过）
```

由此形成闭环：

```text
AI 写 txt ──[table -pack]──▶ xlsx（策划用 Excel 编辑）
                                │
            [table -config] ◀───┘ ──▶ tsv + 强类型代码（程序用）
```

- **文件名（去掉 `.txt`）即工作表名**，因此同样受 `_c` / `_s` / `_cs` 后缀规则约束——
  不带后缀的表会被打表流程跳过，不会生成任何东西。
- 已存在的 xlsx **默认不覆盖**：那多半是策划已经编辑过的成品。确需重打包加 `-force`。

## 命名规则

| 后缀 | 去向 | 说明 |
| --- | --- | --- |
| `.tsv` | 运行时加载 | `go:embed` + `table.LoadAll()` |
| `.go` | 编译时使用 | 类型化结构体，供业务代码引用 |
| `.json` | 配置 | 元数据配置文件 |

## 生成代码示例

输入 Excel `items.xlsx`：

| id | name | type | price |
| --- | --- | --- | --- |
| 1001 | 铁剑 | weapon | 100 |
| 1002 | 木盾 | armor | 80 |

生成 Go 代码 `gen/items.go`：

```go
package table

type Item struct {
    ID    int32  `json:"id" tsv:"id"`
    Name  string `json:"name" tsv:"name"`
    Type  string `json:"type" tsv:"type"`
    Price int32  `json:"price" tsv:"price"`
}

var Items = map[int32]*Item{
    1001: {ID: 1001, Name: "铁剑", Type: "weapon", Price: 100},
    1002: {ID: 1002, Name: "木盾", Type: "armor", Price: 80},
}
```

## 运行时加载

```go
// 在 game logic 初始化时加载
func init() {
    table.LoadAll()
}

// 使用
item := table.Items[1001]
fmt.Println(item.Name) // "铁剑"
```

## 常见问题

| 问题 | 原因 | 解决方案 |
| --- | --- | --- |
| 中文乱码 | Excel 编码问题 | 确保 UTF-8 编码 |
| 列名不匹配 | Excel 列名与代码不一致 | 检查第一行表头 |
| 类型转换失败 | Excel 中数值列有文本 | 统一格式 |

## 下一步


**相关链接：**

- [配置管理](/server/development/configuration) - 配置文件管理

- [msg-client](/server/tools/msg-client) - 交互式命令行工具（网关调试客户端）


