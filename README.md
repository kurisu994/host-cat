# HostCat

HostCat 是一个 Apple Silicon 原生的 macOS 菜单栏 hosts 管理应用。目标是提供菜单栏驱动的 hosts 配置切换、分组、节点和跨组组合能力。

当前仓库已完成阶段 2（真实写入版）：通过 `xcodegen` 迁移为 Xcode 工程，实现了 `SMAppService` Helper 注册、Privileged Helper 真实安全写入、XPC 通信、备份恢复、外部修改检测、DNS 刷新、简体中文/英文界面、hosts 编辑器语法高亮与行号、多行错误实时收集和完整的菜单栏交互，支持签名导出和 DMG 打包。

## 当前能力

- SwiftPM 包结构保留核心库和测试，最低平台为 macOS 14。
- Swift 6 strict concurrency 配置。
- `HostCatCore`：
  - 应用配置、分组、节点和状态元数据模型。
  - hosts 文本解析，支持 IPv4、IPv6、多 hostname、行尾注释、制表符分隔、下划线 hostname 和基础错误定位。
  - hosts 合并输出，包含 HostCat 管理区块（`# --- HostCat Begin (v1) ---` / `# --- HostCat End ---`）。
  - 同域名不同 IP 冲突检测（按地址族区分，避免 IPv4/IPv6 localhost 误判）。
  - 同 IP + 同域名重复条目去重计数。
  - hosts 内容 SHA256 hash。
  - JSON 配置存储，支持默认路径、版本校验、损坏恢复、原配置保留和原子写入（rename）。
  - hosts 导入与管理区块解析（`HostsImporter`），支持无区块、完整 v1 区块、缺 Begin、缺 End、未知版本，区块外内容提取为默认节点内容，并在 fallback 场景保全已有 HostCat 区块记录。
  - UTF-8 读取和 Latin-1 fallback，标记编码问题。
  - 配置变更服务（`ConfigMutationService`），支持 group/node 增删改、排序、多选激活行为，默认节点保护。
  - 配置草稿保存与 hosts 应用分离，写入失败时保留用户编辑内容并提示 hosts 未应用；备份失败会阻止真实写入，备份恢复采用事务式写入，成功前不替换当前配置。
  - 写入协调器（`HostWriteCoordinator` actor），支持 debounce（500ms）、冲突检测、首次写入 expected hash、成功快照和失败状态隔离。
  - 备份存储（`BackupStore`），支持自动命名（含微秒级时间戳防冲突）、保留策略（默认 3 份）和读取恢复。
  - 外部修改检测（`ExternalModificationDetector`），通过 hash 比对检测 hosts 是否在 HostCat 之外被修改。
  - 安全文件写入器（`HostsFileWriter`），实现 immutable flags 检查、系统默认条目校验、临时文件准备期间的目标 hash 二次校验、mkstemp 临时文件、fsync、chmod 644 / chown root:wheel、rename 原子替换、目录 fsync。
  - DNS 刷新器（`SystemDNSRefresher`），执行固定命令 `dscacheutil -flushcache` 和 `killall -HUP mDNSResponder`。
- `HostCatHelperClient`：
  - Helper client 协议（`HostHelperClient`），UI 和服务层只依赖此协议。
  - 真实 XPC client（`XPCHostHelperClient`），通过 `NSXPCConnection` 与 Privileged Helper 通信，将 reply block 转为 `async throws`，并处理连接错误、取消和超时。
  - Helper 注册管理器（`HelperRegistrationManager`），封装 `SMAppService.daemon` 注册、状态检测、审批引导和主应用开机自启动管理。
  - XPC 协议定义（`HostCatHelperXPCProtocol`），使用 `@objc` protocol + `NSDictionary` 参数，以稳定桥接类型传递写入数据、hash 与仅用于错误展示的语言标识。
- `HostCatApp`：
  - 菜单栏预览体验：分组标题 + 节点勾选、即时状态更新、debounce 写入、合成预览和错误提示。
  - 编辑窗口：左侧分组/节点树，支持分组折叠、节点拖拽排序、分组上移/下移、双击重命名、增删操作、右侧 hosts 文本编辑。
  - 合成预览窗口：展示最终 hosts 文本、重复条目合并数量、冲突详情和定位引导。
  - 备份管理窗口（`BackupRestoreView`）：列出历史备份、预览内容、手动创建备份和事务式恢复。
  - 外部修改弹窗（`ExternalModificationAlert`）：检测到外部修改时提供「取消」或「确认覆盖」决策。
  - 设置页面：提供跟随系统、简体中文和 English 的即时语言切换，并集中承载开机自启动、Helper 状态、注册、审批与刷新操作。
  - 简体中文与英文字符串资源：覆盖菜单栏、编辑/预览、Helper、备份、设置及主要错误反馈，切换语言无需重启应用。
  - 程序员专享的 hosts 编辑体验：等宽字体、全量语法高亮渲染（IP、hostname、注释、管理标记）、当前行高亮、滚动同步行号栏、语法错误行整行红色背景及行号栏红点标识、多行错误实时收集与底部状态栏展示。
- `HostCatPrivilegedHelper`：
  - 基于 `SMAppService` 注册的 LaunchDaemon，以 root 身份运行。
  - 通过 XPC 接收主应用写入请求，调用 `HostsFileWriter` 执行安全写入。
  - 写入成功后刷新 DNS 缓存。
  - Helper 端验证调用方 code signing requirement，要求 `anchor apple generic`、固定 bundle identifier 和真实 Team ID。
- `HostCatCoreTests`：
  - 数据模型（`ModelsTests`）Codable/Equatable 单元测试。
  - parser、merge、conflict、config/hash、importer 单元测试。
  - 配置变更服务（`ConfigMutationService`）单元测试。
  - 写入协调器（`HostWriteCoordinator`）单元测试。
  - 备份存储（`BackupStore`）单元测试。
  - 外部修改检测（`ExternalModificationDetector`）单元测试。
  - 文件写入器（`HostsFileWriter`）单元测试（使用协议注入临时目录，覆盖替换前发生外部修改时拒绝覆盖）。
  - 菜单栏视图模型（`MenuBarViewModel`）单元测试（验证写入失败保留草稿配置、备份恢复失败不污染当前配置和持久化配置）。
  - 界面语言偏好（`AppLanguageTests`）单元测试（验证偏好存取、系统语言回退和运行时资源切换）。
  - 测试替身（`FakeHostHelperClient`、`FakeFileSystemOperations`、`StubDNSRefresher`）。

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

使用 xcodegen 生成 Xcode 工程：

```bash
xcodegen generate
```

用 Xcode 打开生成的 `HostCat.xcodeproj`，或者使用命令行构建：

```bash
xcodebuild build -project HostCat.xcodeproj -scheme HostCatApp -destination 'platform=macOS,arch=arm64'
```

运行单元测试（也可以直接用 SwiftPM）：

```bash
swift test
```

打包 Release DMG（将输出到 `build/HostCat.dmg`，需要真实 Developer ID 证书和 Team ID）：

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export DEVELOPMENT_TEAM="TEAMID"
./scripts/build-release.sh
```

## 项目结构

```text
.
├── Package.swift              # SwiftPM：保留 HostCatCore、HostCatHelperClient 和测试
├── project.yml                # XcodeGen 配置，生成完整 Xcode 工程
├── HostCat.xcodeproj          # 生成的 Xcode 工程（Git 追踪）
├── scripts/
│   ├── build-release.sh       # 发布构建脚本（archive + export + DMG）
│   └── ExportOptions.plist    # 导出配置
├── Sources/
│   ├── HostCatApp/            # SwiftUI 菜单栏应用
│   │   ├── HostCatApp.swift              # @main 入口、场景定义、设置视图
│   │   ├── MenuBarContentView.swift      # 菜单栏下拉内容
│   │   ├── EditorView.swift              # 编辑器主视图
│   │   ├── SidebarComponents.swift       # 侧边栏子组件（NodeRow、GroupHeader 等）
│   │   ├── NameInputDialog.swift         # 名称输入弹窗和 NSTextField 封装
│   │   ├── NodeReorderDropDelegate.swift # 节点拖拽排序代理
│   │   ├── HostsTextView.swift           # NSTextView 桥接的 SwiftUI 视图
│   │   ├── LineNumberRulerView.swift     # 基于 TextKit 2 的自定义行号标尺栏
│   │   ├── HostsSyntaxHighlighter.swift  # 基于 TextKit 2 的 hosts 语法高亮引擎
│   │   ├── MergedPreviewView.swift       # 合成预览窗口
│   │   ├── BackupRestoreView.swift       # 备份管理和事务式恢复
│   │   ├── ExternalModificationAlert.swift # 外部修改决策弹窗
│   │   ├── WindowFocus.swift             # 窗口焦点管理工具
│   │   └── Resources/
│   │       ├── Assets.xcassets/          # 应用图标
│   │       ├── HostCatApp.entitlements   # 应用权限配置（沙盒关闭）
│   │       └── Info.plist                # 应用 Info.plist
│   ├── HostCatCore/             # 纯 Swift 业务核心
│   │   ├── Models.swift
│   │   ├── HostsParser.swift
│   │   ├── HostsMerger.swift
│   │   ├── HostsHash.swift
│   │   ├── HostsImporter.swift
│   │   ├── AppConfigStore.swift
│   │   ├── ConfigMutationService.swift
│   │   ├── HostWriteCoordinator.swift
│   │   ├── BackupStore.swift
│   │   ├── ExternalModificationDetector.swift
│   │   ├── HostsFileWriter.swift
│   │   ├── HostsWriteError.swift
│   │   ├── DNSRefresher.swift
│   │   ├── AppLanguage.swift             # 应用语言偏好与资源选择
│   │   ├── HostHelperClient.swift        # 协议和 XPC 接口定义
│   │   └── MenuBarViewModel.swift
│   ├── HostCatHelperClient/     # XPC client 包装层
│   │   ├── XPCHostHelperClient.swift     # 真实 NSXPCConnection 实现
│   │   ├── HelperRegistrationManager.swift # SMAppService 注册管理
│   │   └── HostHelperClient.swift        # （已迁移到 HostCatCore）
│   └── HostCatPrivilegedHelper/ # root Helper 可执行文件
│       ├── HostCatPrivilegedHelperMain.swift  # @main 入口，启动 XPC Listener
│       ├── HelperDelegate.swift             # NSXPCListenerDelegate，验证调用方签名
│       ├── HelperService.swift              # XPC 服务实现，调用 HostsFileWriter
│       ├── Info.plist                       # Helper Info.plist
│       └── com.hostcat.helper.plist         # launchd plist
├── Tests/
│   └── HostCatCoreTests/
│       ├── AppConfigStoreTests.swift
│       ├── AppConfigTests.swift
│       ├── BackupStoreTests.swift
│       ├── ConfigMutationServiceTests.swift
│       ├── ExternalModificationDetectorTests.swift
│       ├── HostsFileWriterTests.swift
│       ├── HostsImporterTests.swift
│       ├── HostsMergerTests.swift
│       ├── HostsParserTests.swift
│       ├── HostWriteCoordinatorTests.swift
│       ├── MenuBarViewModelTests.swift
│       ├── AppLanguageTests.swift
│       ├── ModelsTests.swift
│       └── TestDoubles.swift
└── docs/
    └── hostcat-design.md
```

模块职责：

- `HostCatApp`：SwiftUI app target，负责菜单栏、编辑器窗口、合成预览、集中式设置页（含 Helper 管理和语言切换）、备份管理和用户交互。
- `HostCatCore`：纯 Swift 业务核心，负责模型、parser、merge、冲突检测、hash、配置存储、备份、外部修改检测、文件写入器和 DNS 刷新。不依赖 SwiftUI、AppKit 或 ServiceManagement。
- `HostCatHelperClient`：主应用内的 XPC client 边界，封装 `NSXPCConnection`、code signing requirement、错误映射和 `SMAppService` 注册管理。向上暴露 `async throws` API。
- `HostCatPrivilegedHelper`：以 root Launch Daemon 运行的写入 helper，只负责固定路径 `/private/etc/hosts` 的安全写入和 DNS 刷新。
- `HostCatCoreTests`：核心逻辑单元测试，覆盖 models、parser、merge、storage、write coordinator、backup、import、mutation、file writer 和 view model。

## 设计文档

- [开发方案设计](docs/hostcat-design.md)
- [变更日志](CHANGELOG.md)
- [Agent 协作说明](AGENTS.md)
- [待办任务](TODO.md)

## 开发原则

- 优先把业务规则放进 `HostCatCore`，保证可以用单元测试覆盖。
- UI 层统一保持 `@MainActor` 语义，避免把业务逻辑塞进 SwiftUI view。
- Helper 不接受任意路径或任意命令；真实写入只允许固定 `/private/etc/hosts`。
- 默认不在测试里写真实 `/etc/hosts`。
- 新增行为先写测试，再实现最小代码。

## 下一步

阶段 2（真实写入版）与 hosts 编辑器高亮等功能已完成。接下来可以考虑：
1.~~跨分组拖拽排序~~（已砍：产品决策不实现）
2.搜索/过滤节点和域名
3.自动化 CI/CD 流水线（GitHub Actions）
4.UI 动画细节打磨与自动更新 (Sparkle)
5.iCloud 同步支持
