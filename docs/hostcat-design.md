# HostCat 开发方案设计

日期：2026-05-19
竞品调研：[iHosts 竞品调研](./ihosts-research.md)

## 概述

HostCat 是一个 Apple Silicon 原生的 macOS 菜单栏 hosts 管理应用。核心定位是菜单栏驱动的 hosts 配置切换器，支持分组、节点、组内单选和跨组自由组合。

发布路线为直接分发（公证签名 DMG / GitHub Release），不做 App Store 版本。

## 权限方案：SMAppService + Privileged Helper

经评估，首版采用 **`SMAppService` + XPC Privileged Helper** 方案。`SMJobBless` 已在 macOS 13 废弃，`SMAppService` 是 Apple 当前推荐的特权辅助工具注册方式。

架构：

- **主应用**：以标准用户身份运行，通过 `NSXPCConnection` 向 Helper 发送写入请求。
- **Privileged Helper**：独立可执行文件，以 root Launch Daemon 身份运行。负责写入 `/etc/hosts` 和刷新 DNS 缓存。
- **注册流程**：首次注册时，macOS 会在「系统设置 > 登录项」中显示审批项，用户需手动启用。可通过 `SMAppService.openSystemSettingsLoginItems()` 引导用户。

实现要点：

- 主应用和 Helper 必须使用有效的 Developer ID 证书签名。
- XPC 连接需验证调用方的 code signing requirement，防止第三方进程冒用。Helper 端在 `listener(_:shouldAcceptNewConnection:)` 回调中通过 `auditToken` 验证连接方的 Team ID、bundle identifier 和签名状态。
- Helper 的 launchd plist 放在 `Contents/Library/LaunchDaemons/` 目录下，Helper 可执行文件放在 `Contents/Library/HelperTools/` 目录下。`SMAppService` 模式下二者都必须在 app bundle 内，应用删除时自动清理。
- DNS 缓存刷新命令（`dscacheutil -flushcache` + `killall -HUP mDNSResponder`）由 Helper 在写入 hosts 后一并执行，因为这两个命令都需要 root 权限。

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

- Swift + AppKit / SwiftUI 混合。
- `NSStatusItem` 实现菜单栏常驻。
- AppKit 负责菜单、窗口和 macOS 原生交互。
- SwiftUI 可用于偏好设置和部分表单页面。
- 本地配置使用 JSON，存储在 `~/Library/Application Support/com.hostcat/config.json`。配置文件包含 `configVersion` 字段（首版为 `1`），便于后续格式变更时做迁移。数据量小够用，不考虑迁移 SQLite。
- 配置文件写入采用原子写入（先写临时文件再 rename），防止写入中断导致文件损坏。JSON 解析失败时使用默认配置并弹窗提示用户「配置文件已损坏，已恢复为默认设置」。
- hosts 写入逻辑独立成服务层，通过协议抽象与 UI 解耦。

## 核心数据模型

```swift
struct AppConfig {
    var configVersion: Int           // 首版为 1
    var groups: [HostGroup]
    var settings: AppSettings
}

struct HostGroup {
    var id: UUID
    var name: String
    var isSingleSelect: Bool         // 组内是否单选，默认 true
    var nodes: [HostNode]
    var sortOrder: Int
}

struct HostNode {
    var id: UUID
    var name: String
    var content: String              // hosts 文本内容
    var isActive: Bool
    var sortOrder: Int
}

struct AppSettings {
    var launchAtLogin: Bool
}
```

「默认」节点定义：应用内置一个不可删除的顶层节点「默认」，始终激活，不属于任何分组。首次启动时自动导入当前 `/etc/hosts` 的内容作为「默认」节点的初始内容。它不参与冲突检测（因为它的内容由用户自行控制，不与分组节点产生组合关系）。写入时，标记区域外的系统原始内容由写入逻辑自动保留。

## 首版功能范围

- 菜单栏显示当前 hosts 分组和节点，节点右侧显示快捷数字键。
- 支持分组、节点、组内单选。
- 支持节点和分组的拖拽排序（上移/下移）。
- 支持编辑节点 hosts 文本（纯文本编辑器 + 语法高亮 + 行号 + 错误标记）。
- 支持 hosts 基础语法校验（每行为注释、空行或 `<IP> <域名>` 格式），Apply 时高亮错误行。
- 支持应用配置到 `/etc/hosts`，写入后自动刷新 DNS 缓存。
- 支持查看当前合成后的 hosts 文本。
- 支持合并时跨组冲突检测，同一域名在多个激活节点中存在不同 IP 定义时阻止写入，要求用户解决冲突后再 Apply。
- 支持保留系统原始 hosts 中非本应用管理区域的内容。应用管理区块使用明确的起止标记（`# --- HostCat Begin (v1) ---` / `# --- HostCat End ---`），标记中包含版本号便于未来格式升级。
- 支持手动备份 `/etc/hosts` 到 `~/Library/Application Support/com.hostcat/backups/`，支持从备份恢复。默认保留最近 3 份备份，超出自动删除最早的。
- 支持首次启动时导入当前 `/etc/hosts` 内容到「默认」节点。
- 支持启用或关闭开机自启动。
- 支持多语言（中文/英文完整覆盖）。
- 支持菜单栏鼠标悬停时预览 hosts 内容。
- 支持全局快捷键打开菜单栏。

### 合并输出格式

```text
# --- HostCat Begin (v1) ---

# ==============================
# [分组名]

# ------------------------------
# [节点名]
127.0.0.1 example.com

# --- HostCat End ---
```

### 暂缓功能

- 搜索/过滤节点和域名。
- iCloud 或云同步。

## DNS 缓存刷新策略

macOS 修改 `/etc/hosts` 后不会立即生效，需要刷新 DNS 缓存。标准命令（macOS 10.15+ 通用）：

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

两个命令都需要 root 权限。由于我们采用 Privileged Helper 方案，Helper 本身以 root 身份运行，因此可以在写入 `/etc/hosts` 成功后立即执行这两条命令，无需额外授权。整个流程对用户完全透明。

Apple 没有提供公开的 Swift/C API 直接刷新 DNS 缓存，调用命令行工具是标准做法。

## 备份与回滚机制

### 手动备份

- 在设置界面或菜单中提供「备份当前 Hosts」操作。
- 备份由主应用执行：读取当前 `/etc/hosts` 内容（644 权限，普通用户可读），写入 `~/Library/Application Support/com.hostcat/backups/` 目录。文件名包含时间戳，例如 `hosts_2026-05-20_114000.bak`。
- 默认保留最近 3 份备份，超出时自动删除最早的备份文件。
- 提供「从备份恢复」功能，用户可选择历史备份文件，主应用读取备份内容后通过 XPC 发送给 Helper 写入 `/etc/hosts`。
- 备份路径使用 `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` 获取，避免硬编码 `~` 展开歧义（Helper 以 root 身份运行时 `~` 会展开为 `/var/root/`）。

### 写入安全策略

写入 `/etc/hosts` 采用安全写入策略。注意 `/etc/hosts` 是指向 `/private/etc/hosts` 的符号链接，所有操作统一使用真实路径 `/private/etc/hosts`，避免跨挂载点导致 `rename` 失败（`EXDEV`）。Helper 启动时通过 `realpath` 解析一次真实路径并缓存，后续操作统一使用 resolved path。

1. Helper 检查 `/private/etc/hosts` 是否有 immutable flags（`schg` / `uchg`）。如有，通过 XPC 回传给主应用弹窗提示用户「hosts 文件当前被锁定保护，需要移除保护标志才能写入」，用户确认后再执行 `chflags(path, 0)` 移除。
2. Helper 将新内容写入临时文件 `/private/etc/hosts.hostcat.tmp`。
3. 设置临时文件权限和属主：`chmod 644` + `chown root:wheel`，确保与原始 hosts 文件一致。
4. 校验临时文件内容完整性（文件大小 > 0、包含必要的系统默认条目）。
5. 使用 `rename(2)` 原子替换 `/private/etc/hosts`（同一文件系统上 rename 是原子操作）。
6. 替换成功后再执行 DNS 缓存刷新。

如果任何一步失败，原始 `/private/etc/hosts` 保持不变，主应用通过 XPC 收到错误信息后向用户展示具体原因。

## 冲突检测

多个节点跨组同时激活时，可能对同一域名定义不同 IP。macOS 的 hosts 解析取文件中第一条匹配，后续重复行被忽略。隐式的合并顺序会让用户难以预测生效结果。

首版实现（冲突 = 错误，阻止写入）：

- 在 Apply 合并阶段扫描所有激活节点的 hosts 条目，按域名分组统计。
- 如果同一域名出现多个不同 IP，弹窗显示冲突详情：「域名 X 在节点 A（IP1）和节点 B（IP2）中都有定义」。
- **阻止写入**，要求用户先解决冲突（修改其中一个节点或停用冲突节点）后再重新 Apply。
- 不自动选择优先级，避免用户无法预测哪个 IP 生效。

## 错误处理 UX

| 场景 | 用户体验 |
|------|--------|
| Helper 未注册 / 未在系统设置中批准 | 弹窗引导用户打开「系统设置 > 登录项」，提供跳转按钮 |
| 权限不够无法写入 `/etc/hosts` | 弹窗提示具体错误，建议重新注册 Helper |
| `/etc/hosts` 被其他程序锁定 | 弹窗提示「文件被占用，请稍后重试」 |
| 写入中途失败 | 原子写入保证原始文件不受影响，弹窗提示写入失败原因 |
| DNS 缓存刷新失败 | hosts 已写入但提示「DNS 缓存刷新失败，可能需要手动刷新」 |
| hosts 文本语法错误 | Apply 前在编辑器中高亮错误行，阻止写入并提示修正 |
| 冲突检测发现重复域名 | 弹窗列出冲突详情，阻止写入，要求用户解决冲突后重新 Apply |

所有错误通过 macOS 原生 `NSAlert` 弹窗展示，不使用通知中心（避免被忽略）。

## 写入并发安全

hosts 写入服务层引入串行队列（`DispatchQueue` 或 `OperationQueue` maxConcurrent=1），保证同一时刻只有一个写入操作。菜单栏切换和编辑窗口 Apply 共用同一队列，后到的请求排队等待。

菜单栏快速切换采用两阶段状态模型：

1. **即时更新 UI**：用户每次点击菜单栏节点，立即更新内存配置和菜单勾选状态，体验上零延迟。
2. **延迟写入 `/etc/hosts`（debounce 500ms）**：每次状态变更重置 500ms 计时器，最后一次变更后 500ms 无新操作才执行写入。只写入最终累积状态，中间状态全部丢弃。实现上一个 `DispatchWorkItem` + `asyncAfter` 即可。
3. **写入中视觉反馈**：菜单栏图标短暂显示小圆点或微动画表示「正在应用」，写入完成后恢复正常图标。不在菜单内加 spinner，避免过重。
4. **写入失败回滚**：写入失败时将内存状态回滚到上次成功写入的状态，菜单勾选同步回滚，弹窗提示错误原因。

## 已确认设计决策

- **hosts 写入策略**：只管理应用标记区域（`# --- HostCat Begin (v1) ---` / `# --- HostCat End ---`），保留用户手写内容。
- **编辑体验**：首版使用纯文本编辑器，配合语法高亮、行号和错误标记。结构化表格编辑复杂度高，放到后续版本。
- **架构目标**：只做 ARM64，不做 Universal Binary。项目核心定位是 Apple Silicon 原生体验。
- **首版最低 macOS 版本**：macOS 14 (Sonoma)。macOS 13 的 `SMAppService` 存在早期 bug，14+ 更稳定，且截至 2026 年 macOS 13 市场份额已很低。
- **Helper bundle identifier**：主应用 `com.hostcat.app`，Helper `com.hostcat.helper`。
- **hosts 区块标记格式**：`# --- HostCat Begin (v1) ---` / `# --- HostCat End ---`，标记中包含版本号。
- **Helper 更新策略**：`SMAppService` 的 Helper 在 app bundle 内，更新 app 即更新 Helper 二进制，注册状态和用户审批保持不变。启动时检查 `service.status`，如果变为 `notRegistered` 则重新 `register()`。
- **导入已有 hosts**：首次启动时自动导入当前 `/etc/hosts` 内容到「默认」节点。
- **应用名称**：`HostCat`。"Host" 直接点题，"Cat" 一语双关（Unix `cat` 命令 + 猫咪品牌形象），与 bundle ID（`com.hostcat.*`）和标记格式一致。
- **菜单栏节流策略**：两阶段模型——点击后立即更新内存状态和菜单 UI，实际写入 debounce 500ms。写入期间菜单栏图标微动画提示，失败时回滚 UI 状态并弹窗。

## 初步取舍

- 只做直接分发版本（公证签名 DMG），不做 App Store 版本。避免沙盒限制对权限架构的约束。
- 权限方案采用 `SMAppService` + Privileged Helper，一次授权后透明运行。
- 写入逻辑通过协议抽象与 UI 解耦，便于测试和未来扩展。
- 本地配置使用 JSON（含 `configVersion` 字段），存储在 `~/Library/Application Support/com.hostcat/`，不考虑迁移 SQLite。
- 应用只管理自己标记的 hosts 区块（使用起止注释标记），避免覆盖用户手工维护的系统 hosts 内容。
- 首版去掉反馈、评分等非核心模块。
- UI 不照搬旧版 iHosts 的灰色偏好设置风格，但保留 macOS 原生感和菜单栏优先的工作流。
