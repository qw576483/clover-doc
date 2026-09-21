## 这篇文档讲什么？

Clover 运行时依赖的所有数据源的备份策略，以及灾难恢复的 RTO/RPO 目标。本文档适用于运维人员制定备份计划和灾难恢复流程。

## 前置条件

- 了解 Clover 的数据存储架构（MySQL、etcd、Redis）
- 具备基本的 Linux/Windows 系统操作能力
- 熟悉所使用备份工具的基本命令

## 备份策略总览

| 数据源 | 备份工具 | 频率 | 保留期 | RPO |
|--------|----------|------|--------|-----|
| MySQL | mysqldump / xtrabackup | 每天全量 + 每小时增量 | 30 天 | 1 小时 |
| etcd | etcdctl snapshot | 每天 | 14 天 | 1 天 |
| Redis | RDB + AOF | RDB 每小时 / AOF 持续 | 7 天 | 几乎为零 |
| 策划表 | git | 每次变更 | 永久 | 0 |
| 配置文件 | git / rsync | 每次变更 | 永久 | 0 |

## MySQL 备份

### mysqldump（逻辑备份）

```bash 备份命令
# 全量备份
mysqldump -u root -p --all-databases --single-transaction \
  --routines --triggers --events \
  > backup_$(date +%Y%m%d_%H%M%S).sql

# 恢复
mysql -u root -p < backup_20260101_000000.sql
```

### xtrabackup（物理备份，推荐生产环境）

```bash 备份命令
# 全量备份
xtrabackup --backup --target-dir=/backup/full \
  --user=root --password=xxx

# 增量备份
xtrabackup --backup --target-dir=/backup/incr1 \
  --incremental-basedir=/backup/full \
  --user=root --password=xxx

# 恢复
xtrabackup --prepare --target-dir=/backup/full
xtrabackup --copy-back --target-dir=/backup/full
```

### 备份脚本

```bash 备份脚本
#!/bin/bash
BACKUP_DIR="/backup/mysql"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

mysqldump -u root -p"$DB_PASS" --all-databases \
  --single-transaction --routines --triggers \
  | gzip > $BACKUP_DIR/full_$DATE.sql.gz

# 保留 30 天
find $BACKUP_DIR -name "full_*.sql.gz" -mtime +30 -delete
```

## etcd 备份

```bash etcd 备份命令
# 备份
etcdctl snapshot save /backup/etcd/snapshot_$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/server.crt \
  --key=/etc/etcd/server.key

# 恢复
etcdctl snapshot restore /backup/etcd/snapshot_20260101.db \
  --data-dir=/var/lib/etcd-restored
```

## Redis 备份

### RDB 备份

```yaml Redis 配置
# redis.conf
save 3600 1      # 3600 秒内至少 1 次写入
save 300 100     # 300 秒内至少 100 次写入
dbfilename dump.rdb
dir /var/lib/redis
```

### AOF 备份

```yaml Redis AOF 配置
# redis.conf
appendonly yes
appendfsync everysec
```

```bash Redis 备份命令
# 手动触发备份
redis-cli BGSAVE

# 复制 RDB 文件
cp /var/lib/redis/dump.rdb /backup/redis/dump_$(date +%Y%m%d).rdb
```

## 策划表备份

```bash 策划表备份
# 使用 git 管理
cd game/table
git add .
git commit -m "update: $(date +%Y%m%d) 策划表更新"
git push origin main
```

## 灾难恢复

### RTO/RPO 目标

| 场景 | RTO | RPO | 恢复方式 |
|------|-----|-----|----------|
| MySQL 数据损坏 | <30 分钟 | <1 小时 | xtrabackup 恢复 |
| etcd 数据丢失 | <10 分钟 | <1 天 | snapshot 恢复 |
| Redis 数据丢失 | <5 分钟 | 几乎为零 | AOF 重放 |
| 配置文件丢失 | <5 分钟 | 0 | git 恢复 |

### 恢复演练

> **警告：** 备份不测试等于没有备份！每季度至少执行一次恢复演练。

**演练步骤：**

1. 在测试环境搭建空白集群
2. 恢复 MySQL → etcd → Redis
3. 启动 Clover 服务
4. 验证玩家数据完整性
5. 记录恢复耗时，对比 RTO 目标

## 常见问题

### 备份文件损坏

**症状**：恢复时提示文件损坏或校验失败

**原因**：备份过程中断、存储介质故障

**解决**：
1. 检查备份文件的完整性（如 md5sum）
2. 使用最近的完整备份
3. 如果使用增量备份，检查增量链是否完整

### 恢复后数据不一致

**症状**：恢复后部分数据丢失或重复

**原因**：备份频率不足、恢复步骤错误

**解决**：
1. 检查 RPO 目标是否满足业务需求
2. 确认恢复步骤的正确顺序
3. 考虑使用时间点恢复（PITR）

## 下一步

1. [部署指南](deployment.md) —— 生产环境部署
2. [监控告警](monitoring.md) —— 建立监控体系
3. [故障排查](troubleshooting.md) —— 常见问题排查

