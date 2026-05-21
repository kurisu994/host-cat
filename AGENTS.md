# HostCat Agent 协作说明

本文件记录后续 AI agent 或自动化工具在本仓库内工作的项目规则。

## 沟通与输出

- 默认使用中文说明计划、取舍、结果和错误。
- 变量名、类型名、函数名、target 名和命令保持英文。
- 涉及架构、安全边界、权限模型或发布流程时，先说明方案和风险，再修改。
- 事实优先：以当前代码、`docs/hostcat-design.md` 和测试结果为准。

## 当前项目状态

- 当前已通过 `xcodegen` 迁移为标准 Xcode 工程，支持构建带 Privileged Helper 的 macOS App。
- `HostCatApp` 已实现菜单栏预览体验、编辑窗口、合成预览窗口，以及 Helper 安装引导和备份恢复界面。
- `HostCatPrivilegedHelper` 已实现基于 `SMAppService` 注册的 XPC 服务，支持安全的 `/etc/hosts` 真实写入和 DNS 刷新。
- `HostCatCore` 已包含模型、parser、merge、conflict、hash、importer、config storage、mutation service、write coordinator 和 backup store。
- 节点激活统一使用多选模式，`isSingleSelect` 字段保留但 UI 不再暴露切换入口。
- 阶段 2（真实写入版）已完成，包含安全的外部修改检测和原子备份机制。
- 当前主要验证命令是 `xcodegen generate` 和 `xcodebuild`，同时保留 `swift test` 用于核心逻辑验证。

## 常用命令

```bash
# 生成工程
xcodegen generate

# 命令行构建
xcodebuild build -project HostCat.xcodeproj -scheme HostCatApp -destination 'platform=macOS,arch=arm64'

# 核心单测
swift test
```

如果沙盒限制导致无法写用户级 cache，需要请求用户批准后再运行构建或测试命令。

## 模块边界

- `Sources/HostCatCore`：纯 Swift 业务核心。不要依赖 SwiftUI、AppKit、ServiceManagement 或真实文件系统权限。
- `Sources/HostCatApp`：SwiftUI UI 层。业务规则不要直接写在 view 里。
- `Sources/HostCatHelperClient`：主应用到 Helper 的边界。未来封装 `NSXPCConnection` 和签名校验。
- `Sources/HostCatPrivilegedHelper`：未来 root helper。只允许固定 hosts 写入和固定 DNS 刷新命令。
- `Tests/HostCatCoreTests`：核心行为测试。新增 parser、merge、状态或配置行为时必须补测试。

## 安全边界

- 不要在普通开发测试中写真实 `/etc/hosts` 或 `/private/etc/hosts`。
- Helper 不接受任意路径、任意 shell 命令或 UI 状态对象。
- XPC 只传稳定桥接类型，例如 `String`、`Data`、`Bool`、`NSNumber`、`NSDictionary`、`NSError`。
- 真实写入前必须保留 `expectedCurrentHostsHash` 检查，避免覆盖外部修改。
- DNS 刷新只允许固定命令：`dscacheutil -flushcache` 和 `killall -HUP mDNSResponder`。

## 开发原则

- 新增行为优先 TDD：先写失败测试，再实现最小代码。
- 优先扩展 `HostCatCore`，让 parser、merge、storage、rollback 等逻辑可单测。
- Swift 代码遵守 strict concurrency；跨并发域传递的类型保持 `Sendable`。
- UI 状态更新保持主线程语义；写入协调放进 actor。
- 变更保持聚焦，不顺手重构无关模块。
- 不引入新依赖，除非设计文档或任务明确需要。

## 文档规则

- 设计决策更新到 `docs/hostcat-design.md`。
- 用户可见的运行、测试、模块说明更新到 `README.md`。
- 已完成的重要变更更新到 `CHANGELOG.md`。
- agent 协作规则更新到本文件。

## 代码提交规则

- 提交代码前至少运行：

```bash
git diff --check
swift test
swift build
```
