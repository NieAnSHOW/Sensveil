# 激活与离线许可协议草案

版本：0.1 · 日期：2026-10-11 · 状态：架构建议，未实现服务或签名程序

产品规则依据 [PRD](../product/PRD.md)。客户端保护引擎在激活后不依赖网络；新设备首次激活必须联网。

## 1. 信任边界

服务端决定激活码对应的设备名额，并持有许可签名私钥。客户端只内置可信验签公钥，不能发行许可。应用界面的“成功”状态来自本地验签成功，而不是仅来自 HTTP 200。

使用 Ed25519，macOS 侧候选为 CryptoKit `Curve25519.Signing`；服务端候选为 Workers Web Crypto。所有网络连接使用 HTTPS。生产密钥与测试密钥隔离，不在仓库、安装包、日志或 CI 产物中保存发行私钥。

## 2. 设备身份

候选方案：首次运行生成设备密钥对，私钥保存本机 Keychain；以产品命名空间与平台设备标识做 SHA-256 摘要，并同时绑定设备公钥指纹。原始平台标识不离开本机。

签名凭证绑定设备摘要和公钥指纹，客户端每次读取凭证时检查本机身份一致。Keychain 可迁移性、macOS 平台标识来源、主板维修及系统重装行为必须 PoC，不能只用可能同步/迁移的随机安装 UUID 声称硬件绑定。凭证复制到另一设备即使能验签，也不能通过绑定检查。

设备摘要是可关联标识而非匿名数据。客户端本身不属于不可攻破的可信硬件边界，客户端篡改及虚拟机克隆风险不能用密码学消除。永久买断不做强制周期性在线设备证明。

## 3. 数据模型与套餐

| 对象 | 必需字段 | 约束 |
| --- | --- | --- |
| License | licenseId、activationCodeHash、seatLimit、status、createdAt | seatLimit 只能为 1 或 2，码摘要唯一 |
| DeviceBinding | licenseId、deviceDigest、publicKeyFingerprint、issuedAt、credentialId、status | 同许可同设备唯一；同时检查密钥指纹 |
| ActivationAttempt | requestId、请求摘要、结果标识、时间 | 同 requestId 不接受不同请求内容，敏感码不写日志 |
| SigningKey | keyId、算法、启用状态 | 私钥只在服务端秘密存储；客户端保存可信公钥集合 |

激活码使用安全随机源产生，不使用可猜的流水号或订单号。服务器仅保存带服务端秘密的 HMAC 摘要及脱敏显示信息，避免数据库泄露直接暴露可激活的码。购买套餐权益由服务器记录决定，不能信任客户端传来的设备数。

## 4. 激活过程

1. 用户录入激活码，客户端准备设备摘要、公钥和随机 requestId。
2. 服务端发放短时、一次性挑战 nonce；客户端用设备私钥签署挑战及请求摘要证明持有私钥。
3. 服务端验证请求、激活码、套餐与现有绑定；限流和 nonce 防重放不能依赖单进程内存。
4. 如果同设备/同公钥已绑定，返回同一权益，不增加名额。如果同设备摘要携带另一公钥，进入身份恢复流程，不静默新增名额或替换旧绑定。
5. 新绑定以数据库级唯一约束和**单次原子条件写入**分配名额：条件包含许可启用、未达名额与设备未绑定。禁止先查询 COUNT 再无约束 INSERT。记录名额的写入只在权威主库完成，不用副本读结果授权。
6. 记录绑定成功后签发凭证。若签名或返回失败，重试基于已有绑定重新签发，不重复占位。可先预生成签名，但只有原子绑定成功才返回给客户端。
7. 客户端验签、检查产品/协议/设备匹配后，原子替换本地有效凭证；任何失败保留旧的有效许可。

建议接口：`POST /v1/activation/challenge`、`POST /v1/activations`。这只是接口边界，OpenAPI 与完整请求体在实现阶段按已确认设备方案定义。试用登记和自助解绑不默认添加到一期接口。

成功响应包括签名凭证；业务错误应有稳定错误码：`CODE_INVALID`、`CODE_DISABLED`、`SEATS_EXHAUSTED`、`DEVICE_IDENTITY_CHANGED`、`NONCE_EXPIRED`、`RATE_LIMITED`、`SERVICE_UNAVAILABLE`。客户端区分网络超时与业务拒绝，不在任何失败路径显示已激活。

## 5. 凭证封装与验签

签名直接覆盖精确 payload 字节，不对解析后再序列化的 JSON 验签，以避免字段顺序或数字格式差异。建议 envelope 为 `keyId`、`payloadBase64`、`signatureBase64`；payload 包含签名覆盖的 `keyId`、`schemaVersion=1`、`product=sensveil`、`licenseId`、`credentialId`、`deviceDigest`、`publicKeyFingerprint`、`entitlement=unlimited_apps`、`seatLimit`、`issuedAt`。

永久授权没有 `expiresAt` 或“最近必须联网”字段。`issuedAt` 是审计元数据，不是使用到期时间。服务端时间回退或客户端回拨不能使已签永久许可过期。

客户端按顺序限制数据大小、选择可信 keyId、验签原始 payload、严格解析 schema、比对签名内外 keyId、检查产品/权益/设备匹配。拒绝未知密钥、签名错误、非法字段、版本不支持和超长输入；未知新字段只能按协议的显式兼容策略处理。

旧公钥随旧凭证长期保留以便永久离线验证。签名密钥轮换可阻止之后用旧密钥发行，但离线客户端无法收到实时撤销列表；密钥泄露的影响不能用“强制更新”暗中改写买断承诺。

## 6. 解绑、退款与永久离线

服务端解绑会释放未来签发名额，但旧设备上的永久签名凭证仍可离线验签。不能保证两个名额永远等于“两台实际使用中的设备”，只能可靠限制未迁移情况下的服务端分配数量。

一期建议不提供无限自助解绑，换机走人工审核并声明旧机停用义务。退款可停用后续签发，但不能声称已退款离线客户端立即失效。是否允许转移、次数、冷却时间和所需购买证据由产品在收费前明确。

服务停机不影响已有有效永久授权，但影响新激活、换机和码恢复。运营要保存绑定与签名密钥的受控备份，并确定停止运营时的处理承诺。

## 7. 验证与运营要求

- 单设备第 2 台拒绝，双设备第 3 台拒绝；20 个并发请求争用最后名额最多 1 个新设备成功。
- 同设备重试、请求超时后重试、签名失败后重试不重复占名额；requestId 内容变更被拒绝。
- 空库、已满名额、停用许可、重复设备、设备密钥变化、数据库失败均有明确行为。
- Apple CryptoKit 与服务端实际实现使用固定测试向量交叉验签，验证篡改、未知 keyId 和复制设备失败。
- 激活成功后断网、服务端停机、试用到期、客户端升级仍正常使用。
- 限流不得泄露某激活码是否存在；日志只含 requestId、脱敏许可标识、结果和耗时。
- 错误信息不得包含完整激活码、原始设备标识、私钥或屏幕信息。
- 私钥隔离、授权数据库备份恢复、审计保留期与删除请求流程在收费前完成。

## 官方参考

- [CryptoKit Curve25519.Signing](https://developer.apple.com/documentation/cryptokit/curve25519/signing)
- [Workers Web Crypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/)
- [Workers Secrets](https://developers.cloudflare.com/workers/configuration/secrets/)
- [D1 Database API](https://developers.cloudflare.com/d1/worker-api/d1-database/)
- [D1 Read Replication](https://developers.cloudflare.com/d1/best-practices/read-replication/)

上述文档支持候选能力；本仓库没有已部署许可服务或生产密钥。
