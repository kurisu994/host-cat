# Changelog

本项目遵循面向用户和贡献者的变更记录。当前还没有正式版本号，首个阶段记录在 `未发布` 下。

## 未发布

### Added

- **【阶段 2 完成】真实写入版已完成：使用 xcodegen 迁移为标准 Xcode 工程，实现真实 XPC 服务、安全写入和完整的 UI 交互。**
- 添加 `HostCatHelperClient` 真实 XPC 连接封装（`XPCHostHelperClient`），实现 SMAppService 注册与开机启动管理（`HelperRegistrationManager`）。
- 添加 Privileged Helper (`HostCatPrivilegedHelper`)，基于安全策略执行真实 `/etc/hosts` 写入、权限设置和 DNS 刷新。
- 添加 `HostsFileWriter` 安全文件写入器，实现 immutable flags 检查、mkstemp 临时文件、fsync、chmod/chown、rename 原子替换和目录 fsync。
- 添加 `DNSRefresher`（`SystemDNSRefresher` / `StubDNSRefresher`），执行固定 DNS 刷新命令。
- 添加 `ExternalModificationDetector` 外部修改检测及 UI 决策弹窗（`ExternalModificationAlert`）。
- 添加写入前自动备份（`HostWriteCoordinator` 在写入前调用 `BackupStore.createBackup`）。
- 增强 HostCatApp UI：Helper 注册引导 (`HelperSetupView`)、备份管理恢复 (`BackupRestoreView`)、外部修改弹窗。
- 新增 `scripts/build-release.sh` 支持归档、代码签名导出与 DMG 打包；无证书时自动跳过 exportArchive。
- 添加应用图标资源（Assets.xcassets，7 个尺寸）。
- 拆分 `EditorView.swift` 为 `EditorView`、`SidebarComponents`、`NameInputDialog`、`NodeReorderDropDelegate` 四个文件。
- 拆分 `HostCatApp.swift` 为 `HostCatApp`、`MenuBarContentView`、`WindowFocus` 三个文件。
- 添加 `MenuBarViewModelTests` 验证写入失败时保留配置草稿。
- 添加 `TestDoubles.swift`（`FakeHostHelperClient`、`StubDNSRefresher`）。
- 搭建 SwiftPM 基础开发框架，包含 `HostCatApp`、`HostCatCore`、`HostCatHelperClient`、`HostCatPrivilegedHelper` 和 `HostCatCoreTests`。
- 添加 `HostCatCore` 数据模型：`AppConfig`、`HostGroup`、`HostNode`、`AppSettings` 和 `AppStateMetadata`。
- 添加 hosts parser，支持 IPv4、IPv6、多 hostname、行尾注释和基础错误定位。
- 添加 hosts 合并逻辑，支持默认节点参与、激活节点合并、重复条目去重和同域名不同 IP 冲突检测。
- 添加 SHA256 hosts hash 工具，为后续外部修改检测和写入状态隔离打基础。
- 添加 JSON 配置存储，支持默认配置创建、版本校验、损坏恢复和原子写入。
- 添加最小 SwiftUI 菜单栏 app 骨架和 Privileged Helper 可执行 target 骨架。
- 添加核心单元测试，覆盖配置初始化、hash 稳定性、parser、合并去重和冲突检测。
- 添加 `HostsImporter`，支持解析 HostCat 管理区块（`# --- HostCat Begin (v1) ---` / `# --- HostCat End ---`）。
- 支持 hosts 导入场景：无 HostCat 区块、完整 v1 区块、缺 Begin、缺 End、未知版本。
- 支持首次启动时将管理区块外内容导入「默认」节点，避免重复导入。
- 支持 UTF-8 读取和 Latin-1 fallback，标记编码问题并提示用户。
- 添加 `HostsImporterTests`，覆盖全部解析场景和编码 fallback。
- 添加 `ConfigMutationService`，提供 group/node 增删改、排序、多选激活行为，默认节点不可删除/不可停用保护。
- 添加 `ConfigMutationServiceTests`，覆盖全部配置变更操作和边界行为。
- 添加 `MenuBarViewModel`，管理菜单栏内存配置状态、节点激活切换、debounce 写入调度和错误展示。
- 更新 `HostCatApp` 菜单栏 UI，支持分组标题展示、节点勾选切换、合成预览入口、冲突和错误提示。
- 添加 `EditorView`，实现左侧分组/节点树（增删改排序）和右侧 hosts 文本编辑。
- 菜单栏「打开编辑器」入口打开 EditorWindow。
- 添加 `MergedPreviewView`，展示合成 hosts 文本、重复条目合并数量、冲突详情。
- 菜单栏「查看合成 Hosts」入口打开预览窗口。
- 添加 `BackupStore`，支持自动命名备份、保留策略（默认3份）、读取恢复。
- 添加 `BackupStoreTests`，覆盖备份命名、列表排序、保留策略、读取内容。
- 编辑器侧边栏交互增强：分组折叠/展开、分组和节点拖拽排序、双击分组名称和节点名称重命名、hover 显示删除按钮。
- 统一为多选模式，移除单选/多选切换逻辑和 UI。
- 分组和节点删除操作增加确认弹窗。

### Fixed

- 修复 `HostsParser` 对纯注释/空行内容误报 `emptyContent` 错误的问题，现在返回空记录数组。
- 修复 `HostsMergerTests` 中重复的测试方法名 `testDefaultNodeAlwaysParticipatesAndDuplicateEntriesAreCollapsed`。
- 修复 `HostWriteCoordinator` 写入失败后的状态隔离问题，现在返回 `rolledBackConfig` 供调用方判断真实 hosts 状态。
- 放宽 `HostsParser` 的 hostname 校验，支持下划线 `_`。
- 修复 `EditorView` 中 `ConfigMutationService` 被重复实例化的问题，改为统一使用 `@State` 属性。
- 为 `HostsParser` 补充制表符分隔、下划线 hostname、纯注释/空内容等边界测试用例。
- 为 `AppStateMetadata.lastExternalHostsHash` 添加预留注释，说明阶段2外部修改检测用途。
- 修复 `HostWriteCoordinator` 与 `HostHelperClient` 的 target 边界错误，恢复 `swift build` 和 `swift test` 编译。
- 修复写入进行中新操作被跳过的问题，现在会等待当前写入结束后继续应用最新批次。
- 修复 HostCat 管理区块导入的版本解析、反序 marker 和区块外内容保留问题。
- 修复合并输出中 group/node 名称换行可能注入 hosts 记录的问题。
- 修复标准 `localhost` IPv4/IPv6 双栈条目被误判为冲突的问题。
- 修复快速连续备份可能同名覆盖和保留顺序不稳定的问题。
- 修复 macOS SwiftUI List 内 Section 嵌套 ForEach 无法拖拽排序的问题，改用 `onDrag` + `onDrop(delegate:)` 实现。
- 修复菜单栏应用中分组重命名 TextField 无法获取键盘焦点的问题，通过 `setActivationPolicy(.regular)` 和 `@FocusState` 解决。
- 修复首次 hosts 写入缺少 expected hash 的问题，避免覆盖启动后外部修改。
- 修复已有 HostCat 管理区块在配置缺失或恢复默认配置时可能被静默丢弃的问题。
- 修复写入失败时菜单栏 ViewModel 可能丢弃用户配置草稿的问题，现在保留草稿并提示 hosts 未应用。
- 修复旧 `isSingleSelect` 配置继续影响节点激活的问题，加载后统一规范化为多选行为。
- 修复连续调度 apply 时旧任务可能覆盖最新 `isApplying` 状态的问题。

### Documentation

- 补充开发方案设计，明确 XPC 安全边界、状态快照、写入安全策略、测试策略和构建分发策略。
- 新增 README、CHANGELOG 和 AGENTS 协作文档。
- 更新 README，补充 `HostsImporter` 能力和阶段1当前进度。
- 更新 TODO.md，标记阶段 1 和阶段 2 全部完成。
- 更新 AGENTS.md，同步项目状态为阶段 2 完成。

### Refactored

- 拆分 `EditorView.swift`（747→362 行）为 `EditorView`、`SidebarComponents`、`NameInputDialog`、`NodeReorderDropDelegate` 四个文件。
- 拆分 `HostCatApp.swift`（230→79 行）为 `HostCatApp`、`MenuBarContentView`、`WindowFocus` 三个文件。
- 从 SwiftPM 骨架迁移到 Xcode 工程（project.yml → HostCat.xcodeproj），保留 Package.swift 用于核心测试。

### Not Yet Implemented

- 语法高亮和冲突解决 UI（冲突定位按钮当前仅显示提示）。
- GitHub Release CI/CD 发布流水线。
- 自动更新 (Sparkle)。
- iCloud 同步。
- 全局快捷键打开菜单栏。
- 搜索/过滤节点和域名。
- 完整多语言覆盖。
