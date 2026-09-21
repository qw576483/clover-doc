## 这篇文档讲什么？

如何用 Kubernetes 部署 Clover Engine 的网关与逻辑服。本文档适用于需要在 Kubernetes 集群中部署 Clover 的运维人员。

## 前置条件

- 已安装 Kubernetes 集群
- 了解 Kubernetes 基本概念（Deployment、Service、ConfigMap）
- 已准备 Docker 镜像构建环境
- 了解 Clover 的架构和组件

## 镜像构建（多阶段）

```dockerfile Dockerfile 示例
FROM golang:1.25-alpine AS builder
WORKDIR /build
COPY . .
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /bin/game .

FROM alpine:3.19
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=builder /bin/game /app/game
COPY configs /app/configs
COPY tables /app/tables
ENTRYPOINT ["/app/game"]
CMD ["-config", "/app/configs"]
```

构建网关镜像：Clover 默认网关+逻辑服同进程（server_type: "all"），无需单独构建网关镜像。

> **注意：** `-ldflags="-w -s"` 去掉调试信息，可将二进制体积缩减约 30%。

## ConfigMap 配置分离

```yaml ConfigMap 配置
apiVersion: v1
kind: ConfigMap
metadata:
  name: clover-game-config
data:
  config.yaml: |
    server_type: "game"
    logic:
      listen_addr: "127.0.0.1:10001"
      http_listen: "127.0.0.1:10081"
    auth:                      # 必填：每次登录都调账号服 /auth/verify（缺失启动即 panic）
      verify_addr: "https://clover-auth:8051"   # 账号服 Service 名（按你的部署替换）；默认要求 TLS
      verify_timeout: 3s
    data:
      tier: "redis_mysql"
      mysql:
        host: "mysql"
        port: 3306
        user: "user"
        pass: "pass"
        db_name: "clover"        # ★ 键名是 db_name，不是 db
      redis:
        addr: "redis:6379"
    etcd:
      endpoints:
        - "etcd:2379"
    nats:
      addr: "nats:4222"
```

挂载到 Pod：

```yaml Pod 挂载配置
volumeMounts:
  - name: config
    mountPath: /app/configs/game
volumes:
  - name: config
    configMap:
      name: clover-game-config
```

## Deployment

### 逻辑服

```yaml 逻辑服 Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clover-game
spec:
  replicas: 3
  selector:
    matchLabels:
      app: clover-game
  template:
    metadata:
      labels:
        app: clover-game
    spec:
      containers:
        - name: game
          image: clover/game:latest
          args: ["-config", "/app/configs/game"]
          ports:
            - containerPort: 10001
            - containerPort: 10081
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 2000m
              memory: 4Gi
          livenessProbe:
            httpGet:
              path: /healthz
              port: 10081
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: 10081
            initialDelaySeconds: 5
            periodSeconds: 5
```

### 网关 Service

```yaml 网关 Service
apiVersion: v1
kind: Service
metadata:
  name: clover-gateway
spec:
  type: LoadBalancer
  selector:
    app: clover-gateway
  ports:
    - name: ws
      port: 8001
      targetPort: 8001
    - name: tcp
      port: 8002
      targetPort: 8002
```

## 服务发现

etcd 在集群内使用 Headless Service：

```yaml etcd Headless Service
apiVersion: v1
kind: Service
metadata:
  name: etcd
spec:
  clusterIP: None
  selector:
    app: etcd
  ports:
    - port: 2379
```

## 水平扩缩容（HPA）

```yaml HPA 配置
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: clover-gateway-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: clover-gateway
  minReplicas: 2
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

> **警告：** 逻辑服扩容需注意：新 Pod 只承载新房间/新地图，已有玩家不会自动迁移。缩容前需先排空旧 Pod。

## 存储

| 资源 | 方式 |
|------|------|
| 日志 | 输出到 stdout，由 Fluent Bit / Promtail 采集 |
| 策划表 | 随镜像打包，或挂载 ConfigMap / PVC |
| 持久数据 | MySQL / Redis 独立部署，不在 Pod 内存储 |

## 命名空间与 RBAC

```yaml 命名空间配置
apiVersion: v1
kind: Namespace
metadata:
  name: clover
```

为每个环境（dev / staging / prod）创建独立 namespace。

## 常见问题

### Pod 无法启动

**症状**：Pod 状态为 CrashLoopBackOff

**原因**：配置错误、依赖服务未就绪、资源不足

**解决**：
1. 检查 Pod 日志：`kubectl logs <pod-name>`
2. 确认 ConfigMap 已正确挂载
3. 检查资源限制是否足够
4. 确认依赖服务（etcd、NATS、MySQL）已就绪

### 服务无法访问

**症状**：外部无法访问 Gateway Service

**原因**：Service 配置错误、网络策略限制、负载均衡器问题

**解决**：
1. 检查 Service 配置：`kubectl get svc`
2. 确认 Endpoint 已就绪：`kubectl get endpoints`
3. 检查网络策略（NetworkPolicy）
4. 验证负载均衡器配置

## 下一步

1. [部署指南](deployment.md) —— 传统部署方式
2. [扩缩容](scaling.md) —— 扩缩容策略
3. [日志](logging.md) —— 日志采集与存储
4. [监控与告警](monitoring.md) —— 监控体系建设

