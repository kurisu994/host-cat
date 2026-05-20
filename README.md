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
  - JSON 配置存储，支持默认路径、版本校验、损坏恢复和原子写入。
  - hosts 导入与管理区块解析（`HostsImporter`），支持无区块、完整 v1 区块、缺 Begin、缺 End、未知版本，区块外内容提取为默认节点内容。
  - UTF-8 读取和 Latin-1 fallback，标记编码问题。
  - 配置变更服务（`ConfigMutationService`），支持 group/node 增删改、排序、单选/多选激活行为，默认节点保护。
  - 预览版写入协调器（`HostWriteCoordinator` actor），支持 debounce、冲突检测、成功快照和失败回滚。
  - 备份存储（`BackupStore`），支持自动命名、保留策略和读取恢复。
- `HostCatHelperClient`：
  - Helper client 协议（`HostHelperClient`）。
  - 预览模式 client（`PreviewHostHelperClient`）。
  - XPC protocol 边界草案（`HostCatHelperXPCProtocol`）。
- `HostCatApp`：
  - 菜单栏预览体验：分组标题 + 节点勾选、即时状态更新、debounce 写入、合成预览和错误提示。
  - 编辑窗口 MVP：左侧分组/节点树、增删改排序、右侧 hosts 文本编辑。
  - 合成预览窗口：展示最终 hosts 文本、重复条目合并数量、冲突详情和定位引导。
- `HostCatPrivilegedHelper`：
  - 可执行 target 骨架。
- `HostCatCoreTests`：
  - parser、merge、conflict、config/hash、importer 单元测试。
  - 配置变更服务（`ConfigMutationService`）单元测试。
  - 写入协调器（`HostWriteCoordinator`）单元测试。
  - 备份存储（`BackupStore`）单元测试。

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

阶段 1（安全预览版）已完成。接下来进入阶段 2（真实写入版）：

- 从 SwiftPM 骨架过渡到 Xcode app/helper target。
- 接入 `SMAppService` 注册和 Privileged Helper 真实写入。
- 实现 `NSXPCConnection` 封装和 code signing requirement 验证。
- 完成安全写入策略：flags 检查、hash 校验、`mkstemp`、原子替换、DNS 刷新。
- 接入自动备份、外部修改检测和导入/覆盖决策。
- 配置签名、公证、DMG 打包和 GitHub Release 发布流水线。
