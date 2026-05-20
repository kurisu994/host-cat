# HostCat

HostCat 是一个 Apple Silicon 原生的 macOS 菜单栏 hosts 管理应用。目标是提供菜单栏驱动的 hosts 配置切换、分组、节点、组内单选和跨组组合能力。

当前仓库处于基础开发框架阶段：已经有 SwiftPM 分层骨架、核心 hosts 解析/合并逻辑和单元测试；还没有接入真实 `SMAppService` Helper 注册、签名、公证、DMG 分发和真实 `/etc/hosts` 写入。

## 当前能力

- SwiftPM 包结构，最低平台为 macOS 14。
- Swift 6 strict concurrency 配置。
- `HostCatCore`：
  - 应用配置、分组、节点和状态元数据模型。
  - hosts 文本解析，支持 IPv4、IPv6、多 hostname、行尾注释和基础错误定位。
  - hosts 合并输出，包含 HostCat 管理区块。
  - 同域名不同 IP 冲突检测。
  - 同 IP + 同域名重复条目去重计数。
  - hosts 内容 SHA256 hash。
- `HostCatHelperClient`：
  - Helper client 协议。
  - 预览模式 client。
  - XPC protocol 边界草案。
- `HostCatApp`：
  - 最小 SwiftUI `MenuBarExtra` 菜单栏入口。
  - 最小 Settings 页面。
- `HostCatPrivilegedHelper`：
  - 可执行 target 骨架。
- `HostCatCoreTests`：
  - parser、merge、conflict、config/hash 单元测试。

## 环境要求

- macOS 14+
- Apple Silicon
- Xcode 26 或兼容 Swift 6 toolchain
- Swift 6+

检查本机工具链：

```bash
swift --version
xcodebuild -version
```

## 快速开始

构建：

```bash
swift build
```

测试：

```bash
swift test
```

运行当前菜单栏骨架：

```bash
swift run HostCatApp
```

运行当前 Helper 骨架：

```bash
swift run HostCatPrivilegedHelper
```

当前 Helper 只打印骨架信息，不会写入 `/etc/hosts`。

## 项目结构

```text
.
├── Package.swift
├── Sources
│   ├── HostCatApp
│   ├── HostCatCore
│   ├── HostCatHelperClient
│   └── HostCatPrivilegedHelper
├── Tests
│   └── HostCatCoreTests
└── docs
    ├── hostcat-design.md
    └── ihosts-research.md
```

模块职责：

- `HostCatApp`：SwiftUI app target，负责菜单栏、窗口和用户交互。
- `HostCatCore`：纯 Swift 业务核心，负责模型、parser、merge、冲突检测和 hash。
- `HostCatHelperClient`：主应用内的 Helper client 边界，后续封装 `NSXPCConnection`。
- `HostCatPrivilegedHelper`：未来以 root Launch Daemon 运行的写入 helper。
- `HostCatCoreTests`：核心逻辑单元测试。

## 设计文档

- [开发方案设计](docs/hostcat-design.md)
- [iHosts 竞品调研](docs/ihosts-research.md)
- [变更日志](CHANGELOG.md)
- [Agent 协作说明](AGENTS.md)

## 开发原则

- 优先把业务规则放进 `HostCatCore`，保证可以用单元测试覆盖。
- UI 层统一保持 `@MainActor` 语义，避免把业务逻辑塞进 SwiftUI view。
- Helper 不接受任意路径或任意命令；真实写入只允许固定 `/private/etc/hosts`。
- 默认不在测试里写真实 `/etc/hosts`。
- 新增行为先写测试，再实现最小代码。

## 下一步

- 增加 JSON 配置存储和迁移入口。
- 增加 `HostWriteCoordinator` actor，实现 debounce、状态快照和失败回滚。
- 将 `HostCatHelperClient` 接入真实 `NSXPCConnection`。
- 建立 Xcode app/helper target、签名、公证和 DMG 发布流程。
- 完成编辑窗口、语法高亮、冲突 UX 和备份恢复。
