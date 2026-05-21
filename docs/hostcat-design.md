# HostCat 开发方案设计

日期：2026-05-19
最后更新：2026-05-21（同步多选模式、首次写入 hash 和草稿保留语义）
竞品调研：[iHosts 竞品调研](./ihosts-research.md)

## 概述

HostCat 是一个 Apple Silicon 原生的 macOS 菜单栏 hosts 管理应用。核心定位是菜单栏驱动的 hosts 配置切换器，支持分组、节点和跨组自由组合。

发布路线为直接分发（公证签名 DMG / GitHub Release），不做 App Store 版本。

## 权限方案：SMAppService + Privileged Helper

经评估，首版采用 **`SMAppService` + XPC Privileged Helper** 方案。`SMJobBless` 已在 macOS 13 废弃，`SMAppService` 是 Apple 当前推荐的特权辅助工具注册方式。

架构：

- **主应用**：以标准用户身份运行，通过 `NSXPCConnection` 向 Helper 发送写入请求。
- **Privileged Helper**：独立可执行文件，以 root Launch Daemon 身份运行。负责写入 `/etc/hosts` 和刷新 DNS 缓存。
- **注册流程**：首次注册时，macOS 会在「系统设置 > 登录项」中显示审批项，用户需手动启用。可通过 `SMAppService.openSystemSettingsLoginItems()` 引导用户。

实现要点：

- 主应用和 Helper 必须使用有效的 Developer ID 证书签名。
- XPC 连接需双向验证 code signing requirement，防止第三方进程冒用。主应用建立连接后调用 `NSXPCConnection.setCodeSigningRequirement(_:)` 限定 Helper 签名；Helper 端在 `listener(_:shouldAcceptNewConnection:)` 回调中对入站 `NSXPCConnection` 同样设置调用方 code signing requirement，限定 Team ID、bundle identifier 和签名状态。`processIdentifier` / `SecCode` / `auditToken` 只作为补充诊断信息，不作为唯一安全边界。
- Helper 的 launchd plist 放在 `Contents/Library/LaunchDaemons/` 目录下，Helper 可执行文件放在 `Contents/Library/HelperTools/` 目录下。`SMAppService` 模式下二者都必须在 app bundle 内，应用删除时自动清理。
- DNS 缓存刷新命令（`dscacheutil -flushcache` + `killall -HUP mDNSResponder`）由 Helper 在写入 hosts 后一并执行，因为这两个命令都需要 root 权限。

### XPC 接口边界

XPC 层只做一件事：把主应用已经合成并校验过的 hosts 文本交给 root Helper 写入固定路径。不要把 UI 状态、节点树、任意文件路径或任意命令参数传给 Helper，避免扩大特权进程的攻击面。

接口约束：

- XPC 协议使用 `@objc` protocol + `NSXPCInterface`。方法返回值统一通过 reply block 返回，因为 `NSXPCConnection` 的远程方法本质是异步调用。
- 参数只使用 XPC 稳定支持的桥接类型，例如 `String`、`Data`、`Bool`、`NSNumber`、`NSDictionary`、`NSError`。Swift `Codable struct` 只在主应用和 `HostCatCore` 内部使用，不直接暴露为 XPC 参数。
- 主应用侧提供 `HostHelperClient` 包装层，把 reply block 转成 `async throws`，UI 和服务层只依赖 Swift Concurrency 接口。
- Helper 不接受路径参数，只写启动时 `realpath` 解析得到的 `/private/etc/hosts`。DNS 刷新只调用固定命令和固定参数，不允许主应用透传 shell 命令。
- 写入请求携带 `expectedCurrentHostsHash`。Helper 写入前重新读取当前 hosts 并计算 hash；若与预期不一致，拒绝写入并返回「hosts 已被外部修改」。主应用再弹窗让用户选择导入、取消或明确覆盖。
- Helper 端重复做最小安全校验：内容非空、包含必要系统默认条目、HostCat 管理区块格式完整、文件 flags 可写。不能只信任主应用已经校验过。

推荐调用边界：

```text
SwiftUI UI (@MainActor)
    |
    v
HostWriteCoordinator actor
    |
    v
HostHelperClient async wrapper
    |
    v
NSXPCConnection + @objc protocol
    |
    v
Privileged Helper (root, fixed /private/etc/hosts only)
```

优点：

- 用户只需首次在系统设置里批准一次，后续写入完全透明。
- 主应用不以 root 身份运行，安全边界清晰。
- Helper 同时负责 hosts 写入和 DNS 刷新，不需要额外授权。

注意事项：

- 开发调试时 "Sign to Run Locally" 可能不够，需配置真实证书。
- 调试注册问题可用 `log stream --style compact --predicate 'subsystem == "com.apple.libxpc.SMAppService"'`。

## 技术方向

首版建议做 Apple Silicon 原生 macOS 菜单栏应用，优先直接分发，不先受 App Store 沙盒限制绑死。

建议技术方向：

- **Swift 6.x**，启用 strict concurrency checking（`StrictConcurrency = complete`）。所有跨并发域传递的类型必须满足 `Sendable`；UI 层统一标注 `@MainActor`；优先使用 Swift Concurrency（`async/await`、`actor`）替代 GCD。
- **SwiftUI 为主**。菜单栏使用 `MenuBarExtra`（macOS 13+）替代 `NSStatusItem`，窗口使用 SwiftUI `Window` / `Settings` scene，弹窗使用 `.alert()` 修饰符。仅在 SwiftUI 无法覆盖的场景（如 hosts 纯文本编辑器的语法高亮）通过 `NSViewRepresentable` 桥接 AppKit。
- 本地配置使用 JSON，存储在 `~/Library/Application Support/com.hostcat.app/config.json`。配置文件包含 `configVersion` 字段（首版为 `1`），便于后续格式变更时做迁移。数据量小够用，不考虑迁移 SQLite。
- 配置文件写入采用原子写入（先写临时文件再 rename），防止写入中断导致文件损坏。JSON 解析失败时使用默认配置并弹窗提示用户「配置文件已损坏，已恢复为默认设置」。
- hosts 写入逻辑独立成服务层，通过协议抽象与 UI 解耦。

推荐模块边界：

- `HostCatApp`：SwiftUI app target，负责菜单栏、编辑窗口、设置页、弹窗和用户交互。
- `HostCatCore`：纯 Swift 模块，包含数据模型、hosts parser、合并规则、冲突检测、配置读写、备份索引和状态快照逻辑。此模块不依赖 SwiftUI、AppKit 或 ServiceManagement，便于单元测试。
- `HostCatHelperClient`：主应用内的 XPC client 包装层，向上暴露 `async throws` API，向下封装 `NSXPCConnection`、code signing requirement 和错误映射。
- `HostCatPrivilegedHelper`：root Helper 可执行文件，只负责固定路径写入、文件安全校验、DNS 刷新和错误回传。
- `HostCatCoreTests`：覆盖 parser、merge、dedupe、conflict、encoding、配置迁移、状态批次隔离和 hosts 导入；Helper 的真实写入只放在签名后的集成或手动 smoke 测试中。

## 核心数据模型

所有数据模型为值类型 `struct`，天然满足 `Sendable`，可安全跨并发域传递。

```swift
struct AppConfig: Codable, Sendable {
    var configVersion: Int           // 首版为 1
    var defaultNode: HostNode        // 首次导入的系统 hosts，作为可编辑且不可删除的基础节点
    var groups: [HostGroup]
    var settings: AppSettings
    var state: AppStateMetadata
}

struct HostGroup: Codable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var isSingleSelect: Bool         // 历史兼容字段，加载后统一规范化为 false
    var nodes: [HostNode]            // 数组位置即排序顺序，首版不引入显式 sortOrder
}

struct HostNode: Codable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var content: String              // hosts 文本内容
    var isActive: Bool
}

struct AppSettings: Codable, Sendable {
    var launchAtLogin: Bool
}

struct AppStateMetadata: Codable, Sendable {
    var lastAppliedHostsHash: String?     // 上次成功写入后的 /private/etc/hosts 内容 hash
    var lastAppliedAt: Date?
    var lastExternalHostsHash: String?    // 上次导入或确认处理的外部 hosts hash；首次写入时作为 expected hash
}
```

`AppStateMetadata` 持久化的是跨启动仍然有价值的事实，不保存正在进行的 Task、XPC connection 或 UI 临时状态。运行时另外由 `HostWriteCoordinator` actor 维护 `lastSuccessfulConfigSnapshot`、`pendingWriteID` 和当前 debounce task，用于失败状态隔离和批次隔离。

「默认」节点定义：应用内置一个不可删除的顶层节点「默认」，始终激活，不属于任何分组。首次启动时自动导入当前 `/etc/hosts` 中非 HostCat 管理区块的内容作为「默认」节点初始内容，同时记录当前 hosts hash，保证首次写入也能检测启动后的外部修改；导入完成后，HostCat 成为这部分内容的唯一编辑入口，后续写入时不再把同一段系统原始内容额外保留在标记区域外。这样可以避免原始 hosts 同时出现在「默认」节点和标记区外导致重复生效。

「默认」节点是可编辑节点，和普通节点一起参与语法校验、合并输出与冲突检测；区别仅在于它不可删除、不可停用、排序固定在菜单最顶部。若导入时发现 `/etc/hosts` 已包含 HostCat 管理区块，则优先解析管理区块恢复配置；只把管理区块外的内容导入「默认」节点，避免二次导入。如果配置文件缺失或损坏导致只能恢复默认配置，fallback 内容会去掉 HostCat 起止 marker 但保留区块内已有 hosts 记录，避免静默丢弃用户曾由 HostCat 管理的记录。

hosts 文件编码处理：首次导入和每次写入前读取 `/etc/hosts` 时按 UTF-8 解码；如果解码失败，回退到 Latin-1 读取并弹窗提示用户「hosts 文件编码异常，已按 Latin-1 读取。HostCat 写入时会转换为 UTF-8，建议先检查内容」。回退读取只用于最大程度展示和备份原内容，不承诺 byte-for-byte 保留；HostCat 写出时统一使用 UTF-8 编码。

## 首版交付路线

首版按风险拆成两个垂直切片，先验证产品手感和合成逻辑，再接入高风险的系统写入能力。

### 阶段 1：安全预览版

目标：不写入 `/etc/hosts`，先完成 HostCat 的核心模型、编辑体验和合成规则。

- 菜单栏采用平铺 + 标题分隔符风格：分组名作为不可点击的标题分隔符，组内节点平铺显示为可勾选菜单项，节点右侧显示快捷数字键。
- 支持分组、节点和多选激活；旧配置中的 `isSingleSelect` 字段仅保留兼容，加载后统一规范化为多选行为。
- 支持在编辑窗口中对节点和分组进行拖拽排序（上移/下移）。菜单栏 `NSMenu` 不支持原生拖拽，排序操作统一在编辑窗口的树形列表中完成。
- 支持编辑节点 hosts 文本（纯文本编辑器 + 语法高亮 + 行号 + 错误标记）。
- hosts 文本语法校验：每行可为空行、整行注释，或 `IP hostname [alias...] [# comment]`。首版支持 IPv4、IPv6、同一行多个 hostname / alias、连续空白和行尾注释；Apply 时高亮错误行。
- 支持查看当前合成后的 hosts 文本。
- 支持合并时跨组冲突检测，同一域名在多个激活节点中存在不同 IP 定义时阻止写入，要求用户解决冲突后再 Apply。
- 支持合并输出时静默去重：同一域名 + 同一 IP 在多个激活节点中重复出现时，只保留第一次出现的条目，在预览界面标注「N 条重复条目已合并」。
- 支持首次启动时导入当前 `/etc/hosts` 中非 HostCat 管理区块内容到「默认」节点（通过 `HostsImporter`）。
- 支持启用或关闭开机自启动。

### 阶段 2：真实写入版

目标：接入 `SMAppService` + Privileged Helper，完成安全写入、备份和 DNS 刷新。

- 支持应用配置到 `/etc/hosts`，写入后自动刷新 DNS 缓存。
- 支持写入前自动备份 `/etc/hosts` 到 `~/Library/Application Support/com.hostcat.app/backups/`，支持从备份恢复。默认保留最近 3 份备份，超出自动删除最早的。
- 支持写入前对比 `expectedCurrentHostsHash`，检测 `/etc/hosts` 是否在 HostCat 之外被修改；发现变化时先进入导入/取消/覆盖决策，不静默覆盖。
- 支持写入前检测 HostCat 管理区块外是否存在非空内容。如果有，弹窗告知用户「检测到 hosts 文件中有 HostCat 管理区块外的内容」，并提供三个选择：推荐的「导入到默认节点并继续」、保守的「取消写入」、显式风险选项「确认覆盖并不再保留」。默认按钮为导入，禁止用含糊的「忽略」表达可能丢失内容的操作。
- 支持 HostCat 管理区块输出，区块使用明确的起止标记（`# --- HostCat Begin (v1) ---` / `# --- HostCat End ---`），标记中包含版本号便于未来格式升级。
- 支持 HostCat 管理区块解析，由 `HostsImporter` 负责识别、版本校验和区块外内容提取。
- 支持 Helper 注册、审批状态检测、重新注册引导和写入失败状态隔离。

### 暂缓功能

- 鼠标悬停时预览 hosts 内容。
- 全局快捷键打开菜单栏。
- 中文/英文完整多语言覆盖。
- 搜索/过滤节点和域名。
- iCloud 或云同步。
- 应用自更新（引入 Sparkle 框架）。

### 合并输出格式

```text
# --- HostCat Begin (v1) ---

# ==============================
# 默认
# Host Database
127.0.0.1 localhost
255.255.255.255 broadcasthost
::1 localhost

# ==============================
# [分组名]

# ------------------------------
# [节点名]
127.0.0.1 example.com

# --- HostCat End ---
```

## DNS 缓存刷新策略

macOS 修改 `/etc/hosts` 后不会立即生效，需要刷新 DNS 缓存。标准命令（macOS 10.15+ 通用）：

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

两个命令都需要 root 权限。由于我们采用 Privileged Helper 方案，Helper 本身以 root 身份运行，因此可以在写入 `/etc/hosts` 成功后立即执行这两条命令，无需额外授权。整个流程对用户完全透明。

Apple 没有提供公开的 Swift/C API 直接刷新 DNS 缓存，调用命令行工具是标准做法。

## 备份与回滚机制

### 自动与手动备份

备份统一由主应用执行，Helper 只负责写入 `/etc/hosts` 和刷新 DNS 缓存。

- 每次真实写入 `/etc/hosts` 前，主应用先备份当前 `/etc/hosts` 内容（644 权限，普通用户可读）。备份成功后再通过 XPC 发送写入请求给 Helper，避免错误配置覆盖后无法回滚。
- 在设置界面或菜单中提供「备份当前 Hosts」手动操作。
- 备份写入 `~/Library/Application Support/com.hostcat.app/backups/` 目录。文件名包含时间戳，例如 `hosts_2026-05-20_114000.bak`。
- 默认保留最近 3 份备份，超出时自动删除最早的备份文件。
- 提供「从备份恢复」功能，用户可选择历史备份文件，主应用读取备份内容后通过 XPC 发送给 Helper 写入 `/etc/hosts`。
- 备份路径使用 `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` 获取，避免硬编码 `~` 展开歧义。

### 写入安全策略

写入 `/etc/hosts` 采用安全写入策略。注意 `/etc/hosts` 是指向 `/private/etc/hosts` 的符号链接，所有操作统一使用真实路径 `/private/etc/hosts`，避免跨挂载点导致 `rename` 失败（`EXDEV`）。Helper 启动时通过 `realpath` 解析一次真实路径并缓存，后续操作统一使用 resolved path。

1. Helper 检查 `/private/etc/hosts` 是否有 immutable flags（`schg` / `uchg`）。如有，默认拒绝写入，并通过 XPC 回传给主应用弹窗提示用户「hosts 文件当前被锁定保护，HostCat 不会自动移除保护标志」。弹窗提供手动处理说明；首版不执行 `chflags(path, 0)` 这类清空所有 flags 的操作，避免意外移除用户或安全工具设置的保护。
2. Helper 读取当前 `/private/etc/hosts` 并计算 hash；如果请求里的 `expectedCurrentHostsHash` 非空且不匹配，拒绝写入，避免覆盖外部程序或用户刚刚做的修改。
3. Helper 使用同目录 `mkstemp` 创建唯一临时文件，例如 `/private/etc/.hosts.hostcat.XXXXXX`。不使用固定临时文件名，避免上次崩溃残留、符号链接攻击或并发写入互相踩踏。
4. 将新内容写入临时文件后执行 `fsync`，再设置权限和属主：`chmod 644` + `chown root:wheel`，确保与原始 hosts 文件一致。
5. 校验临时文件内容完整性（文件大小 > 0、包含必要的系统默认条目、HostCat 管理区块起止标记完整）。
6. 使用 `rename(2)` 原子替换 `/private/etc/hosts`（同一文件系统上 rename 是原子操作），随后对父目录执行 `fsync`，降低断电或系统崩溃导致目录项未落盘的风险。
7. 替换成功后再执行 DNS 缓存刷新。
8. 无论成功或失败，都尝试清理未使用的临时文件；清理失败只记录日志，不覆盖主错误。

如果任何一步失败，原始 `/private/etc/hosts` 保持不变，主应用通过 XPC 收到错误信息后向用户展示具体原因。

## 冲突检测

多个节点跨组同时激活时，可能对同一域名定义不同 IP。macOS 的 hosts 解析取文件中第一条匹配，后续重复行被忽略。隐式的合并顺序会让用户难以预测生效结果。

首版实现（冲突 = 错误，阻止写入）：

- 在 Apply 合并阶段扫描「默认」节点和所有激活节点的 hosts 条目，按域名分组统计。
- 如果同一域名出现多个不同 IP，弹窗显示冲突详情：「域名 X 在节点 A（IP1）和节点 B（IP2）中都有定义」。
- **阻止写入**，要求用户先解决冲突（修改其中一个节点或停用冲突节点）后再重新 Apply。
- 不自动选择优先级，避免用户无法预测哪个 IP 生效。

## 错误处理 UX

| 场景 | 用户体验 |
|------|--------|
| Helper 未注册 / 未在系统设置中批准 | 弹窗引导用户打开「系统设置 > 登录项」，提供跳转按钮 |
| 权限不够无法写入 `/etc/hosts` | 弹窗提示具体错误，建议重新注册 Helper |
| `/etc/hosts` 被其他程序锁定 | 弹窗提示「文件被占用，请稍后重试」 |
| `/etc/hosts` 设置了 immutable flags | 弹窗提示文件被保护，提供手动解除说明，不自动清除 flags |
| 写入中途失败 | 原子写入保证原始文件不受影响，弹窗提示写入失败原因 |
| DNS 缓存刷新失败 | hosts 已写入但提示「DNS 缓存刷新失败，可能需要手动刷新」 |
| hosts 文本语法错误 | Apply 前在编辑器中高亮错误行，阻止写入并提示修正 |
| 冲突检测发现重复域名 | 弹窗列出冲突详情，阻止写入，要求用户解决冲突后重新 Apply |

所有错误通过 SwiftUI `.alert()` 修饰符弹窗展示，不使用通知中心（避免被忽略）。

## 写入并发安全

hosts 写入服务层使用 Swift `actor` 隔离，保证同一时刻只有一个写入操作。菜单栏切换和编辑窗口 Apply 共用同一 actor 实例，后到的请求自动排队等待。UI 层统一标注 `@MainActor`，状态更新在主线程完成；写入操作在 actor 内部 `await` XPC 调用，不阻塞 UI。

菜单栏快速切换采用两阶段状态模型：

1. **即时更新 UI**：用户每次点击菜单栏节点，`@MainActor` 上立即更新内存配置和菜单勾选状态，体验上零延迟。
2. **延迟写入 `/etc/hosts`（debounce 500ms）**：每次状态变更重置 500ms 计时器，最后一次变更后 500ms 无新操作才执行写入。只写入最终累积状态，中间状态全部丢弃。实现上使用 `Task` + `Task.sleep(for:)` 配合取消前序 Task 即可。
3. **写入中视觉反馈**：菜单栏图标短暂显示小圆点或微动画表示「正在应用」，写入完成后恢复正常图标。不在菜单内加 spinner，避免过重。
4. **写入失败处理**：写入期间新的用户操作排入下一批 debounce，不与当前写入批次混合。写入失败时不丢弃用户配置草稿；配置先作为草稿持久化，hosts 保持未应用状态，并向用户提示错误原因。`HostWriteCoordinator` 仍维护上次成功快照供服务层判定真实 hosts 状态，但 UI 不用旧快照覆盖用户正在编辑的草稿。

状态批次规则：

- 每次计划写入生成一个 `writeID`，同时捕获本批次的 `configSnapshot`、`expectedCurrentHostsHash` 和合成后的 hosts 文本。
- `HostWriteCoordinator` actor 串行处理写入。写入开始后，后续用户操作只更新新的待写入快照，不修改正在写入的批次。
- 写入成功后，更新 `lastSuccessfulConfigSnapshot`、`lastAppliedHostsHash` 和 `lastAppliedAt`，再持久化配置。
- 写入失败时，保留当前配置草稿并提示 hosts 未应用。如果失败期间已经产生更新的待写入批次，不丢弃这些新操作；下一次 debounce 继续尝试写入最新快照。
- 如果失败原因是 `expectedCurrentHostsHash` 不匹配，不自动重试。必须先让用户选择导入、取消或明确覆盖。

## 测试策略

首版测试重点放在 `HostCatCore`，把高风险逻辑从 UI 和 Helper 中剥离出来测到足够细。

单元测试必须覆盖：

- hosts parser：空行、整行注释、行尾注释、IPv4、IPv6、多 hostname、连续空白、非法 IP、非法 hostname。
- 合并规则：默认节点固定参与、多选激活、跨组组合、重复条目静默去重、同域名不同 IP 冲突阻止。
- 管理区块解析：无 HostCat 区块、完整 v1 区块、缺 Begin、缺 End、版本号未知、区块外内容导入。
- 编码处理：UTF-8 正常读取、Latin-1 回退提示、写出统一 UTF-8。
- 配置存储：`configVersion`、JSON 损坏恢复、原子写入失败不破坏旧配置、未来迁移入口。
- 状态批次：debounce 合并、写入成功更新快照、写入失败保留配置草稿、失败期间新操作保留、hash 不匹配不自动覆盖。

Helper 测试分层处理：

- 大部分 Helper 逻辑通过 `HostsFileWriter` 协议注入临时目录，测试 flags 检测、`mkstemp`、权限设置、rename 失败、DNS 刷新失败映射。
- 真正写 `/private/etc/hosts` 的路径只做签名后的本机集成 smoke test，不放进默认 CI，避免污染开发机和 CI runner。
- XPC client 使用 fake helper 覆盖成功、签名失败、连接中断、reply 超时和 helper 返回业务错误。

## 构建与分发策略

首版直接分发必须把构建、签名、公证和安装体验纳入计划，否则 Helper 路线无法验证。

推荐 target 结构：

```text
HostCat.xcodeproj
├── HostCatApp                 # macOS app，arm64 only
├── HostCatCore                # Swift framework / local package
├── HostCatPrivilegedHelper    # LaunchDaemon helper executable
├── HostCatHelperClient        # XPC client wrapper
└── HostCatCoreTests
```

本地开发命令以 Xcode scheme 为准，CI 至少包含：

- `xcodebuild test -scheme HostCat -destination 'platform=macOS,arch=arm64'`
- `xcodebuild archive -scheme HostCat -archivePath build/HostCat.xcarchive`
- 使用 Developer ID Application 证书导出 app。
- 使用 `notarytool submit --wait` 公证，成功后执行 `stapler staple`。
- 打包 DMG，上传 GitHub Release，并在 release notes 中明确 `macOS 14+`、`Apple Silicon only` 和 Helper 首次授权步骤。

签名注意事项：

- App、Helper、launchd plist、bundle identifier 和 code signing requirement 必须在 CI 与本机开发中保持一致。
- `Sign to Run Locally` 只适合早期 UI 和 Core 调试；进入阶段 2 前必须使用真实 Developer ID 跑通 Helper 注册、审批、写入和更新流程。
- 发布产物不引入 Sparkle。自动更新作为第二版能力，首版只提供 GitHub Release 下载和手动替换安装。

## 已确认设计决策

- **hosts 写入策略**：HostCat 成为 hosts 内容的统一编辑入口。首次启动把现有非 HostCat 管理区块导入「默认」节点；之后写入完整 hosts 文件，其中 HostCat 合成内容放在管理区块内，不再重复保留已导入的原始内容。
- **UI 框架**：SwiftUI 为主，菜单栏用 `MenuBarExtra`，窗口用 SwiftUI `Window` / `Settings` scene，弹窗用 `.alert()`。仅 hosts 纯文本编辑器的语法高亮通过 `NSViewRepresentable` 桥接 AppKit。
- **Swift 版本**：Swift 6.x，启用 strict concurrency（`StrictConcurrency = complete`）。数据模型为 `Sendable` 值类型，UI 层 `@MainActor`，写入服务层用 `actor` 隔离，优先 `async/await` 替代 GCD。
- **模块边界**：UI、Core、XPC client、Privileged Helper 分层实现；parser、merge、storage、state rollback 等业务逻辑放在 `HostCatCore`，避免被 SwiftUI 或 root Helper 绑定。
- **架构目标**：只做 ARM64，不做 Universal Binary。项目核心定位是 Apple Silicon 原生体验。
- **首版最低 macOS 版本**：macOS 14 (Sonoma)。macOS 13 的 `SMAppService` 存在早期 bug，14+ 更稳定，且截至 2026 年 macOS 13 市场份额已很低。
- **Helper bundle identifier**：主应用 `com.hostcat.app`，Helper `com.hostcat.helper`。
- **hosts 区块标记格式**：`# --- HostCat Begin (v1) ---` / `# --- HostCat End ---`，标记中包含版本号。
- **XPC 安全边界**：XPC 只传合成后的 hosts 文本和 `expectedCurrentHostsHash`，Helper 不接受任意路径或任意命令，且重复执行最小安全校验。
- **Helper 更新策略**：`SMAppService` 的 Helper 在 app bundle 内，更新 app 即更新 Helper 二进制，注册状态和用户审批保持不变。启动时检查 `service.status`，如果变为 `notRegistered` 则重新 `register()`。
- **导入已有 hosts**：首次启动时自动导入当前 `/etc/hosts` 中非 HostCat 管理区块内容到「默认」节点；「默认」节点可编辑、不可删除、不可停用，并参与冲突检测。
- **应用名称**：`HostCat`。"Host" 直接点题，"Cat" 一语双关（Unix `cat` 命令 + 猫咪品牌形象），与 bundle ID（`com.hostcat.*`）和标记格式一致。
- **菜单栏节流策略**：两阶段模型——点击后立即更新内存状态和菜单 UI，实际写入 debounce 500ms。写入期间菜单栏图标微动画提示，失败时保留配置草稿并提示 hosts 未应用，写入期间新产生的用户操作保留待下次 debounce 重试。
- **菜单栏展示风格**：平铺 + 标题分隔符。分组名作为不可点击的标题分隔符，组内节点平铺为可勾选菜单项。
- **排序操作归属**：拖拽排序在编辑窗口的树形列表中完成，菜单栏不支持拖拽。
- **合并去重策略**：合并输出时静默去重，同域名 + 同 IP 只保留第一次出现；预览界面标注合并数量。
- **hosts 文件编码**：读取按 UTF-8，解码失败回退 Latin-1 并提示用户写入时会转换为 UTF-8；回退读取用于展示和备份，不承诺 byte-for-byte 保留；写出统一 UTF-8。
- **应用自更新**：计划第二版引入 Sparkle 框架实现自动更新，首版暂不包含。

## 初步取舍

- 只做直接分发版本（公证签名 DMG），不做 App Store 版本。避免沙盒限制对权限架构的约束。
- 权限方案采用 `SMAppService` + Privileged Helper，一次授权后透明运行。
- 写入逻辑通过协议抽象与 UI 解耦，便于测试和未来扩展。
- 本地配置使用 JSON（含 `configVersion` 字段），存储在 `~/Library/Application Support/com.hostcat.app/`（与主应用 bundle ID 一致），不考虑迁移 SQLite。
- 构建路线采用 Xcode app target + helper executable target + 可测试 Core 模块；首版 release 包含签名、公证、DMG 和 GitHub Release，不包含自动更新。
- 应用导入并管理现有 hosts 内容，避免「标记区外保留」和「默认节点导入」同时存在造成重复条目。
- 首版去掉反馈、评分、悬停预览、全局快捷键、完整多语言等非核心模块。
- UI 不照搬旧版 iHosts 的灰色偏好设置风格，但保留 macOS 原生感和菜单栏优先的工作流。
