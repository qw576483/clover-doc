
## 这篇文档讲什么？

游戏后端反作弊的核心原则、常见作弊类型和防护策略。

## 常见作弊类型

| 类型 | 手段 | 防护策略 |
| --- | --- | --- |
| 修改客户端 | 篡改内存数值 | 服务器权威，不信任客户端计算 |
| 重放攻击 | 重发合法消息 | 请求去重 + 时间戳校验 |
| 速度作弊 | 加速移动/攻击 | 服务端校验频率和间隔 |
| 刷资源 | 重复执行获利操作 | 请求限流 + 幂等性保证 |
| 协议篡改 | 发送非法消息 | 协议校验 + 字段范围检查 |

## 服务器权威原则

> **注意：** **核心原则：客户端只是展示层，所有游戏逻辑由服务器权威计算。**


```go
// ❌ 错误：信任客户端计算的伤害
type AttackRequest struct {
    Damage int `json:"damage"`
}
func onAttack(c event.Ctx) error {
    var req AttackRequest
    c.BindMsg(&req)
    target.HP -= req.damage // 危险！客户端可以传任意值
}

// ✅ 正确：服务端计算伤害
type AttackRequest struct {
    TargetID uint32 `json:"target_id"`
}
func onAttack(c event.Ctx) error {
    var req AttackRequest
    c.BindMsg(&req)

    // 服务端计算实际伤害
    damage := calculateDamage(attacker, target)
    target.HP -= damage
}
```

## 关键校验点

### 移动校验

```go
func validateMovement(oldPos, newPos Position, deltaTime float64) error {
    // 计算移动距离
    distance := math.Sqrt(
        math.Pow(newPos.X-oldPos.X, 2) +
        math.Pow(newPos.Y-oldPos.Y, 2),
    )

    // 校验速度是否超过最大值
    speed := distance / deltaTime
    if speed > MaxMoveSpeed {
        return errors.New("speed hack detected")
    }

    return nil
}
```

### 物品校验

```go
import "clover-server-engine/pkg/domain/object"

func validateItemUse(c event.Ctx, playerID string, itemID uint32) error {
    // 通过 Record 查询背包是否拥有该物品
    // 注意：第二参须为 data.RecordSchema 变量，不能传字符串
    bag, err := g.LoadRecord(c, datadef.BagSchema, playerID)
    if err != nil {
        return err
    }
    colItemID := bag.ColIndex("item_id")
    if colItemID < 0 {
        return errors.New("bag schema invalid")
    }
    if bag.Find(colItemID, object.NewInt(int64(itemID))) < 0 {
        return errors.New("item not found")
    }

    // 检查物品冷却（业务层自行维护冷却时间戳字段）
    colCooldown := bag.ColIndex("cooldown_at")
    if colCooldown >= 0 {
        row := bag.Find(colItemID, object.NewInt(int64(itemID)))
        if row >= 0 {
            cooldownAt := bag.GetCell(row, colCooldown).Int()
            if cooldownAt > time.Now().Unix() {
                return errors.New("item on cooldown")
            }
        }
    }

    // 检查物品使用条件
    item := GetItem(itemID)
    var player PlayerData
    if err := g.LoadStruct(c, datadef.PlayerSchema, playerID, &player); err != nil {
        return err
    }
    if player.Level < item.RequiredLevel {
        return errors.New("level too low")
    }

    return nil
}
```

### 经济校验

```go
func validateTransaction(player *Player, amount int64) error {
    // 检查余额
    if player.Gold < amount {
        return errors.New("insufficient gold")
    }

    // 检查交易金额范围
    if amount <= 0 || amount > MaxTransaction {
        return errors.New("invalid amount")
    }

    return nil
}
```

## 请求去重

```go
// 使用消息ID + 时间戳去重
type RequestDeduplicator struct {
    seen map[string]time.Time
    mu   sync.RWMutex
}

func (d *RequestDeduplicator) IsDuplicate(msgID string, timestamp int64) bool {
    d.mu.Lock()
    defer d.mu.Unlock()

    key := fmt.Sprintf("%s:%d", msgID, timestamp)
    if _, exists := d.seen[key]; exists {
        return true
    }

    d.seen[key] = time.Now()
    return false
}
```

## 随机数安全

```go
// ❌ 危险：可预测的随机数
func roll() int {
    return rand.Intn(100) // 每次重启种子相同
}

// ✅ 安全：不可预测的随机数
func secureRoll() int {
    n, _ := rand.Int(rand.Reader, big.NewInt(100))
    return int(n.Int64())
}
```

## 日志与审计

```go
// 记录可疑行为（使用引擎 zap 门面 logger）
import "clover-server-engine/pkg/foundation/logger"

func logSuspiciousActivity(playerID string, activity string, details string) {
    logger.Warn("suspicious activity detected",
        logger.Field("player_id", playerID),
        logger.Field("activity", activity),
        logger.Field("details", details),
    )

    // 发送告警
    alertService.Send("anti-cheat", fmt.Sprintf(
        "Player %s: %s - %s", playerID, activity, details,
    ))
}
```

## 下一步


**相关链接：**

- [认证与权限](/server/security/auth) - 认证流程和权限控制

- [输入校验](/server/security/input-validation) - 详细的输入校验指南

- [安全指南](/server/security/security-guide) - 安全编码和扫描集成


