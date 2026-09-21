## 这篇文档讲什么？

Clover 各组件的可扩展性、Gateway/Game 节点的扩容方案，以及缩容时的注意事项。本文档适用于运维人员进行扩缩容操作。

## 前置条件

- 了解 Clover 的架构和组件
- 熟悉负载均衡和集群管理
- 了解 Kubernetes HPA 配置

## 组件可扩展性

| 组件 | 扩展方式 | 说明 |
|------|----------|------|
| Gateway | 水平扩展 | 无状态，直接加节点 |
| Game（房间型） | 水平扩展 | 按房间分配到不同节点 |
| Game（MMO 分线） | 水平扩展 | 按地图分线，每线一个节点 |
| Auth（账号服） | 水平扩展 | 无状态，账号表在 MySQL；多实例经 etcd `auth` 前缀被 `Game.CallAuth` 发现 |
| Log（日志服） | 水平扩展 | 无状态，业务日志写同一张 MySQL 表；多实例经 etcd `log` 前缀被发现，两条通路都支持：`Game.CallLog`（同步 RPC，每次轮询）与业务日志管道 `Game.AddLog`（按片轮询分发到各实例，每实例一条长连接，写失败自动重连） |
| Master | 单点 | 无内置多节点 / 故障转移；多开互不共享状态 |
| MySQL | 主从复制 | 读写分离 |
| Redis | Cluster | 分片扩展 |
| NATS | Cluster | 集群扩展 |

## Gateway 扩容

Gateway 的连接级状态（加密会话、上游连接、owner 绑定）都随连接销毁而重建，**可靠通道**
（TCP / WS / QUIC / WT）重连可落到任意网关，所以横向扩容**不需要会话粘性**：

```text Gateway 扩容示意图
                    ┌─ Gateway-1 (ws://gateway1:8001)
Load Balancer ──────┤
                    └─ Gateway-2 (ws://gateway2:8001)
```

**扩容步骤：**

1. 部署新的 Gateway 节点
2. 修改 `server.yaml` 中的 `gateway.listen_ws`、`gateway.listen_tcp`、`gateway.listen_udp` 为新端口
3. 在负载均衡器中添加新节点
4. 验证连接和消息路由正常

> **注意：** Gateway 之间通过 NATS 通信，无需直接互联。

> **⚠️ 裸 UDP 例外（唯一的粘性要求）：** 若启用了**裸 UDP** 通道，绑定令牌与端点表是
> **网关进程本地**的，换网关即失效 ⇒ 必须让**同一玩家的 TCP 与其 UDP 包落到同一网关进程**
> （LB 按源 IP 亲和，或 UDP 地址静态指向固定网关）。详见[部署指南](./deployment.md)
> 的「网关多实例的负载均衡约束」。

## Game 扩容：房间型

帧同步、MOBA 等房间型游戏，按房间分配到不同 Game 节点：

```text 房间型扩容示意图
Room-1 → Game-1
Room-2 → Game-1
Room-3 → Game-2  ← 新增节点
Room-4 → Game-2
```

**扩容步骤：**

1. 部署新的 Game 节点
2. Master 通过节点心跳感知新节点（节点经 TCP 注册到 Master，不走 etcd）
3. 新创建的房间会自动分配到新节点
4. 已有房间不受影响

## Game 扩容：MMO 分线

MMO 大世界按地图分线，每线一个 Game 节点：

```text MMO 分线扩容示意图
Map-1 (新手村) → Game-1
Map-2 (主城)   → Game-2
Map-3 (副本)   → Game-3  ← 新增节点
```

**扩容步骤：**

1. 部署新的 Game 节点
2. 在配置中添加新地图到新节点的映射
3. 玩家进入新地图时，路由到新节点

## 缩容注意事项

> **警告：** 缩容前必须确保没有活跃玩家在目标节点上，否则会导致连接断开和数据丢失。

**缩容步骤：**

1. **停止分配**：从负载均衡器或 Master 中移除节点
2. **等待排空**：等待节点上的所有房间/玩家迁移或结束
3. **验证排空**：检查节点上无活跃连接
4. **关闭节点**：安全关闭进程
5. **清理注册**：从 etcd 中移除节点注册信息

## 容量规划

| 场景 | 单节点承载 | 10K 玩家所需 |
|------|------------|--------------|
| Gateway | 5000 连接 | 2 个节点 |
| Game（房间型） | 200 个房间 | 50 个节点 |
| Game（MMO） | 1000 玩家/线 | 10 个节点 |
| Master | - | 1 个节点（单点，无横向扩展） |

## 自动扩缩容

### Kubernetes HPA

```yaml HPA 配置
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: game-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: game
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### 自定义指标

```yaml 自定义指标配置
metrics:
- type: Pods
  pods:
    metric:
      name: active_rooms
    target:
      type: AverageValue
      averageValue: "200"
```

## 常见问题

### 扩容后负载不均

**症状**：新增节点负载低，旧节点负载高

**原因**：负载均衡策略不当、路由规则问题，或**裸 UDP 的源亲和没配**

**解决**：
1. 检查负载均衡算法（轮询、加权、最少连接）
2. 若启用了裸 UDP：确认 LB 按**源 IP 亲和**——令牌是网关进程本地的，换网关即失效
3. 检查路由规则是否均衡
4. 考虑使用一致性哈希

### 缩容导致数据丢失

**症状**：缩容后部分玩家数据丢失

**原因**：未正确排空节点、玩家未迁移完成

**解决**：
1. 确保所有玩家已迁移到其他节点
2. 确认节点已从 Master 节点表摘除（心跳超时自动摘除）
3. 验证数据同步状态
4. 制定回滚方案

## 下一步

1. [集群架构](../concepts/cluster.md) —— 理解 Clover 集群拓扑
2. [Kubernetes 部署](kubernetes.md) —— K8s 部署详解
3. [性能优化](performance.md) —— 性能调优策略

