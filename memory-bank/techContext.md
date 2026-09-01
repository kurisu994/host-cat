# techContext.md

## 平台与语言

| 项 | 值 |
|---|---|
| 最低 macOS | 14.0 (Sonoma) |
| 架构 | arm64 only（无 x86_64） |
| Swift | 6.0 |
| Swift Strict Concurrency | `complete` |
| Xcode | 26.6（`xcodeVersion` in project.yml） |
| 包管理 | SwiftPM（核心 + 测试） + XcodeGen 2.46.0+（Xcode 工程） |

## 第三方依赖

**无**。所有依赖均为 Apple 系统框架：

| 框架 | 用途 |
|------|------|
| Foundation | 基础类型 |
| SwiftUI | UI 层 |
| AppKit | NSTextView / NSRulerView / ShortcutRecorderView 桥接 |
| Combine | `@Published` ObservableObject |
| Carbon.HIToolbox | `RegisterEventHotKey` 全局快捷键监听 + `UCKeyTranslate` 键码翻译 |
| os.log | 日志 |
| ServiceManagement | `SMAppService` Helper 注册 |
| Network | `IPv4Address` / `IPv6Address` 校验 |
| Security | code signing requirement |
| Darwin (POSIX) | `mkstemp` / `fsync` / `chmod` / `chown` / `rename` / `realpath` / `chflags` |

阶段 3 计划引入：
- **Sparkle**（自动更新）

## Bundle Identifiers

| 模块 | Bundle ID |
|------|-----------|
| 主应用 | `com.hostcat.app` |
| Helper | `com.hostcat.helper` |
| Core framework | `com.hostcat.core` |
| HelperClient framework | `com.hostcat.helper-client` |
| Core tests | `com.hostcat.core-tests` |

## 数据存储路径

| 路径 | 用途 |
|------|------|
| `~/Library/Application Support/com.hostcat.app/config.json` | 应用配置（JSON, configVersion=1） |
| `~/Library/Application Support/com.hostcat.app/backups/hosts_YYYY-MM-DD_HHMMSS.bak` | 自动 + 手动备份（默认保留 3 份） |
| `~/Library/Application Support/com.hostcat.app/config.json.<reason>.<ts>.<uuid>` | 配置损坏时的 preserved 副本 |
| `/private/etc/hosts` | 真实 hosts 文件（仅 Helper 写入，realpath 解析） |
| `UserDefaults["HostCat.appLanguage"]` | 界面语言偏好（`system` / `zh-Hans` / `en`） |
| `UserDefaults["HostCat.shortcut.toggleMenuBar"]` | 「打开菜单栏」全局快捷键（JSON: keyCode + carbonModifiers） |
| `UserDefaults["HostCat.privacyWelcomeShown"]` | 首启隐私摘要欢迎窗口是否已展示过 |
| `UserDefaults["HostCatTeamIdentifier"]` | Team ID（Info.plist 注入） |

## HostCat 管理区块格式

```text
# --- HostCat Begin (v1) ---
（合成后的 hosts 内容）
# --- HostCat End ---
```

- 标记包含版本号 `(v1)`，便于未来格式升级
- `HostsImporter` 负责识别、版本校验、区块外内容提取

## XPC 接口

```swift
@objc protocol HostCatHelperXPCProtocol {
    func writeHosts(
        _ contents: NSString,
        expectedCurrentHostsHash: NSString?,
        localizationIdentifier: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    )
}
```

**Reply dictionary keys**：
- 成功：`success: true`, `finalHash: String`, `didRefreshDNS: Bool`, `dnsRefreshError: String`
- 失败：`success: false`, `errorCode: String`（`fileImmutable` / `hashMismatch` / `writeFailed`）, `errorMessage: String`

**`localizationIdentifier` 取值**：
- `"zh-Hans"` 或 `"en"`：直接使用
- 其他（包括 `"system"` 或未知）：Helper 记录 warning 并回退到 `zh-Hans`
- 主应用必须先在客户端调用 `AppLanguage.effectiveLocalizationIdentifier()` 解析

## 构建命令

| 命令 | 用途 |
|------|------|
| `swift test` | 核心单元测试（推荐快速验证） |
| `swift build` | SwiftPM 编译（Core + HelperClient） |
| `xcodegen generate` | 从 project.yml 生成 HostCat.xcodeproj |
| `xcodebuild build -project HostCat.xcodeproj -scheme HostCatApp -destination 'platform=macOS,arch=arm64'` | 命令行构建完整 app |
| `xcodebuild test -project HostCat.xcodeproj -scheme HostCatApp -destination 'platform=macOS,arch=arm64'` | Xcode 工程测试 |
| `./scripts/build-release.sh` | 发布打包（archive + 公证 + DMG） |
| `git diff --check` | 提交前空白字符检查 |

## 发布构建要求

发布脚本 `scripts/build-release.sh` 必须提供以下环境变量：

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export DEVELOPMENT_TEAM="TEAMID"
./scripts/build-release.sh
```

缺失任一变量时脚本会直接失败，避免生成不可验证 Helper requirement 的发布包。

## 测试基础设施

- 测试目录：`Tests/HostCatCoreTests/`
- 测试替身集中：`TestDoubles.swift`
- 框架：XCTest + Swift Testing（混用）
- 当前测试数：133 XCTest + 27 Swift Testing
- CI：尚未配置（阶段 3 任务 17 — GitHub Actions）

## 关键配置文件

| 文件 | 关键设置 |
|------|---------|
| `project.yml` | Swift 6, deployment target macOS 14, arch arm64, App Sandbox 关闭, LSUIElement=true（菜单栏 app） |
| `Package.swift` | 仅保留 Core + HelperClient + Tests，app/helper 在 Xcode 工程 |
| `Sources/HostCatApp/Resources/HostCatApp.entitlements` | 沙盒关闭 |
| `Sources/HostCatPrivilegedHelper/com.hostcat.helper.plist` | launchd plist |
| `Sources/HostCatPrivilegedHelper/Info.plist` | Helper 端 code signing requirement |
| `scripts/ExportOptions.plist` | 导出配置 |

## 已知技术约束

- `HostsTextView` 的 `isUpdatingFromSwiftUI` 标记 **不可** 声明为 `private`，否则 Xcode 构建失败（SwiftUI propertyWrapper 限制）
- 编辑器行号栏与标题栏的视觉层级已统一，后续样式调整需保持两者一致
- `MenuBarExtra(.menu)` 的菜单项会被系统复用，文案改变需要 `.id()` 强制重建
- macOS 没有公开 Swift/C API 直接刷新 DNS，调用命令行工具是标准做法
- `/etc/hosts` 是 `/private/etc/hosts` 的符号链接；统一用 resolved path 避免 `rename` 跨挂载点失败（`EXDEV`）
