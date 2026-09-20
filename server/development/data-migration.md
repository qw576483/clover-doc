# 数据迁移指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的数据迁移方法，包括迁移文件创建、执行迁移、备份和恢复。目标读者是想要管理数据库迁移的开发者。

## 前置条件

- 了解数据库基础概念
- 熟悉 Clover 引擎的项目结构
- 了解 SQL 基础

## 快速开始

### 1. 创建迁移文件

```bash
# 迁移文件手动创建（引擎没有配套的迁移 CLI 工具）
mkdir -p migrations
touch migrations/V001__add_player_level.sql
```

### 2. 编写迁移 SQL

```sql
-- migrations/V001__add_player_level.sql
ALTER TABLE player_info ADD COLUMN level INT DEFAULT 1;
ALTER TABLE player_info ADD COLUMN experience INT DEFAULT 0;
```

### 3. 执行迁移

```bash
# 手动执行迁移 SQL（引擎在 app 启动时按 data.sqls_dir 自动跑该目录下的迁移，
# 这里给出的是不经引擎、直接对库执行的方式）
mysql -u root -p your_database < migrations/V001__add_player_level.sql
```

## 迁移文件规范

### 1. 命名规范

```
migrations/
├── V001__add_player_level.sql      # 版本号__描述.sql
├── V002__add_item_system.sql
├── V003__add_chat_system.sql
└── V004__optimize_indexes.sql
```

### 2. SQL 规范

```sql
-- V001__add_player_level.sql
-- 版本：001
-- 描述：添加玩家等级字段
-- 作者：developer
-- 日期：2024-01-01

-- 开始迁移
BEGIN;

-- 添加字段
ALTER TABLE player_info ADD COLUMN level INT DEFAULT 1;
ALTER TABLE player_info ADD COLUMN experience INT DEFAULT 0;

-- 添加索引
CREATE INDEX idx_player_level ON player_info(level);
CREATE INDEX idx_player_experience ON player_info(experience);

-- 提交迁移
COMMIT;
```

### 3. Go 代码迁移

引擎的迁移以结构化 `Migration` 对象注册，`Up` / `Down` 为内嵌 SQL 字符串；在 **app 启动**（`internal/app/bootstrap.go` 的 `runSQLMigrations`，配置了 `data.sqls_dir` 时）扫描目录并执行待执行的迁移——**不是**在 `data.NewStore` 里。

> **注意：** 迁移 API（`migration.Register`）目前位于 `internal/domain/data/migration`，尚未暴露到 `pkg/` 公开面。
> 以下代码仅供参考引擎内部迁移机制。业务侧应通过 `data.NewStore` 的 `AutoCreateTable` 选项自动建表，
> 或联系引擎团队将迁移 API 提升到公开面。

```go
package datadef

import (
    "clover-server-engine/internal/domain/data/migration"
)

func init() {
    migration.Register(migration.Migration{
        Version: 1,
        Name:    "add player level",
        Up:      "ALTER TABLE player ADD COLUMN level INT DEFAULT 1",
        Down:    "ALTER TABLE player DROP COLUMN level",
    })
}
```

> **注意：** `Up` / `Down` 是纯 SQL 字符串（非 `*sql.Tx` 回调）。版本号必须单调递增，引擎在 app 启动扫描 `data.sqls_dir` 时自动调用 `Migrator.Up(ctx)`。

### 4. 验证迁移

```bash
# 查迁移记录表确认已执行的版本（版本表默认名 _schema_versions，见 migration.NewMigrator）
mysql -u clover -p clover_game -e "SELECT * FROM _schema_versions"
```

## 数据备份

### 1. 备份策略

```bash
# 完整备份
mysqldump -u clover -p clover_game > full_backup_$(date +%Y%m%d_%H%M%S).sql

# 增量备份
mysqldump -u clover -p clover_game --where="1=1" > incremental_backup.sql

# 表级备份
mysqldump -u clover -p clover_game player_info > player_backup.sql
```

### 2. 自动备份脚本

```bash
#!/bin/bash
# backup.sh - 自动备份脚本

# 配置
DB_HOST="localhost"
DB_USER="clover"
DB_PASS="password"
DB_NAME="clover_game"
BACKUP_DIR="/backup/mysql"
REDIS_DIR="/var/lib/redis"
DATE=$(date +%Y%m%d_%H%M%S)

# 创建备份目录
mkdir -p $BACKUP_DIR

# 备份 MySQL
echo "开始备份 MySQL..."
mysqldump -h$DB_HOST -u$DB_USER -p$DB_PASS $DB_NAME > $BACKUP_DIR/mysql_$DATE.sql
if [ $? -eq 0 ]; then
    echo "MySQL 备份成功: $BACKUP_DIR/mysql_$DATE.sql"
else
    echo "MySQL 备份失败"
    exit 1
fi

# 备份 Redis
echo "开始备份 Redis..."
redis-cli BGSAVE
sleep 5
cp $REDIS_DIR/dump.rdb $BACKUP_DIR/redis_$DATE.rdb
if [ $? -eq 0 ]; then
    echo "Redis 备份成功: $BACKUP_DIR/redis_$DATE.rdb"
else
    echo "Redis 备份失败"
    exit 1
fi

# 清理旧备份（保留7天）
echo "清理旧备份..."
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.rdb" -mtime +7 -delete

echo "备份完成"
```

### 3. 备份验证

```bash
# 验证备份文件完整性
mysql -u clover -p clover_game < /backup/mysql/full_backup.sql
if [ $? -eq 0 ]; then
    echo "备份验证成功"
else
    echo "备份验证失败"
    exit 1
fi
```

## 数据恢复

### 1. 恢复策略

```bash
# 完全恢复
mysql -u clover -p clover_game < full_backup.sql

# 部分恢复（单表）
mysql -u clover -p clover_game player_info < player_backup.sql

# 时间点恢复
mysqlbinlog --start-datetime="2024-01-01 10:00:00" \
            --stop-datetime="2024-01-01 12:00:00" \
            binlog.000001 | mysql -u clover -p clover_game
```

### 2. 自动恢复脚本

```bash
#!/bin/bash
# restore.sh - 自动恢复脚本

# 配置
DB_HOST="localhost"
DB_USER="clover"
DB_PASS="password"
DB_NAME="clover_game"
BACKUP_FILE=$1
REDIS_DIR="/var/lib/redis"

if [ -z "$BACKUP_FILE" ]; then
    echo "用法: $0 <backup_file>"
    exit 1
fi

# 恢复 MySQL
echo "开始恢复 MySQL..."
mysql -h$DB_HOST -u$DB_USER -p$DB_PASS $DB_NAME < $BACKUP_FILE
if [ $? -eq 0 ]; then
    echo "MySQL 恢复成功"
else
    echo "MySQL 恢复失败"
    exit 1
fi

# 恢复 Redis（如果备份文件存在）
REDIS_BACKUP=$(echo $BACKUP_FILE | sed 's/mysql/redis/g' | sed 's/.sql/.rdb/g')
if [ -f "$REDIS_BACKUP" ]; then
    echo "开始恢复 Redis..."
    redis-cli SHUTDOWN NOSAVE
    cp $REDIS_BACKUP $REDIS_DIR/dump.rdb
    redis-server --daemonize yes
    echo "Redis 恢复成功"
fi

echo "恢复完成"
```

## 高级迁移

### 1. 数据转换

```sql
-- V005__convert_player_data.sql
-- 转换玩家数据格式

BEGIN;

-- 添加新字段
ALTER TABLE player_info ADD COLUMN data_json TEXT;

-- 转换数据
UPDATE player_info 
SET data_json = JSON_OBJECT(
    'level', level,
    'experience', experience,
    'coins', coins,
    'items', items
);

-- 删除旧字段
ALTER TABLE player_info 
DROP COLUMN level,
DROP COLUMN experience,
DROP COLUMN coins,
DROP COLUMN items;

COMMIT;
```

### 2. 数据迁移脚本

迁移使用 SQL 字符串定义，按分号拆分执行：

```go
package migrations

import (
    "clover-server-engine/internal/domain/data/migration"
)

func init() {
    // 注册迁移（Version 单调递增，从 1 开始）
    migration.Register(migration.Migration{
        Version: 5,
        Name:    "convert player data to json",
        Up: `
            ALTER TABLE player ADD COLUMN data_json TEXT;
            UPDATE player SET data_json = JSON_OBJECT(
                'level', level,
                'experience', experience,
                'coins', coins,
                'items', items
            );
            ALTER TABLE player DROP COLUMN level,
                DROP COLUMN experience,
                DROP COLUMN coins,
                DROP COLUMN items;
        `,
        Down: `
            ALTER TABLE player ADD COLUMN level INT DEFAULT 1;
            ALTER TABLE player ADD COLUMN experience BIGINT DEFAULT 0;
            ALTER TABLE player ADD COLUMN coins BIGINT DEFAULT 0;
            ALTER TABLE player ADD COLUMN items TEXT;
            UPDATE player SET
                level = JSON_EXTRACT(data_json, '$.level'),
                experience = JSON_EXTRACT(data_json, '$.experience'),
                coins = JSON_EXTRACT(data_json, '$.coins'),
                items = JSON_EXTRACT(data_json, '$.items');
            ALTER TABLE player DROP COLUMN data_json;
        `,
    })
}
```

> **注意：** `Migration.Up` / `Down` 为 SQL 字符串（多条用分号分隔），引擎在事务内按分号拆分执行，不支持 Go 回调函数。

## 监控与告警

### 1. 迁移监控

```go
package main

import (
    "clover-server-engine/pkg/foundation/logger"
    "time"
)

func monitorMigration() {
    // 监控迁移进度
    ticker := time.NewTicker(10 * time.Second)
    defer ticker.Stop()
    
    for range ticker.C {
        // 检查迁移状态
        status, err := getMigrationStatus()
        if err != nil {
            logger.Errorf("获取迁移状态失败: %v", err)
            continue
        }
        
        // 记录迁移进度
        logger.Infof("迁移状态: %s, 进度: %d%%", status.Status, status.Progress)
        
        // 检查是否需要告警
        if status.Progress < 50 && status.Duration > 30*time.Minute {
            sendAlert("迁移进度缓慢", "当前进度: "+string(status.Progress)+"%")
        }
    }
}
```

### 2. 告警配置

```yaml
# alerting.yaml
alerts:
  - name: migration_slow
    condition: "migration_progress < 50 AND migration_duration > 30m"
    severity: warning
    message: "迁移进度缓慢，当前进度: {{ .Progress }}%"
    
  - name: migration_failed
    condition: "migration_status == 'failed'"
    severity: critical
    message: "迁移失败，请检查日志"
    
  - name: migration_completed
    condition: "migration_status == 'completed'"
    severity: info
    message: "迁移已完成，耗时: {{ .Duration }}"
```

## 最佳实践

### 1. 迁移前准备

```bash
# 1. 备份数据库
./backup.sh

# 2. 检查磁盘空间
df -h

# 3. 检查数据库连接
mysql -u clover -p clover_game -e "SELECT 1"

# 4. 校验迁移脚本语法：先在测试库上执行一遍，确认无误再上生产
```

### 2. 迁移执行

```bash
# 1. 进入维护模式
./maintenance.sh on

# 2. 执行迁移（手动执行 SQL）
mysql -u clover -p clover_game < migrations/V001__add_player_level.sql

# 3. 验证迁移结果（查迁移记录表 / 检查表结构）

# 4. 退出维护模式
./maintenance.sh off
```

### 3. 迁移后验证

```bash
# 1. 检查数据完整性
./verify_data.sh

# 2. 运行测试
go test ./...

# 3. 监控系统状态
./monitor.sh

# 4. 通知相关人员
./notify.sh "迁移完成"
```

## 故障排除

### 1. 迁移失败

**错误信息：**
```
Error 1062: Duplicate entry '123' for key 'PRIMARY'
```

**解决方案：**
```bash
# 检查重复数据
mysql -u clover -p clover_game -e "SELECT id, COUNT(*) FROM player_info GROUP BY id HAVING COUNT(*) > 1"

# 修复重复数据
mysql -u clover -p clover_game -e "DELETE FROM player_info WHERE id = 123 AND created_at < '2024-01-01'"
```

### 2. 迁移超时

**错误信息：**
```
Error 2013: Lost connection to MySQL server during query
```

**解决方案：**
```bash
# 增加超时时间
mysql -u clover -p clover_game --connect-timeout=600 -e "source migration.sql"

# 或者分批执行
split -l 1000 migration.sql migration_part_
for file in migration_part_*; do
    mysql -u clover -p clover_game < $file
done
```

### 3. 数据不一致

**错误信息：**
```
数据验证失败: player_info 行数不匹配
```

**解决方案：**
```bash
# 比较迁移前后数据
mysql -u clover -p clover_game -e "SELECT COUNT(*) FROM player_info" > before.txt
# 执行迁移
# ...
mysql -u clover -p clover_game -e "SELECT COUNT(*) FROM player_info" > after.txt

# 比较结果
diff before.txt after.txt
```

## 相关文档

- [配置管理](configuration.md)
- [性能优化](performance.md)
- [测试指南](testing.md)
- [监控配置](../operations/scaling.md)