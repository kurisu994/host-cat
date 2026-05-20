# Changelog

本项目遵循面向用户和贡献者的变更记录。当前还没有正式版本号，首个阶段记录在 `未发布` 下。

## 未发布

### Added

- 搭建 SwiftPM 基础开发框架，包含 `HostCatApp`、`HostCatCore`、`HostCatHelperClient`、`HostCatPrivilegedHelper` 和 `HostCatCoreTests`。
- 添加 `HostCatCore` 数据模型：`AppConfig`、`HostGroup`、`HostNode`、`AppSettings` 和 `AppStateMetadata`。
- 添加 hosts parser，支持 IPv4、IPv6、多 hostname、行尾注释和基础错误定位。
- 添加 hosts 合并逻辑，支持默认节点参与、激活节点合并、重复条目去重和同域名不同 IP 冲突检测。
- 添加 SHA256 hosts hash 工具，为后续外部修改检测和写入回滚打基础。
- 添加 JSON 配置存储，支持默认配置创建、版本校验、损坏恢复和原子写入。
- 添加最小 SwiftUI 菜单栏 app 骨架和 Privileged Helper 可执行 target 骨架。
- 添加核心单元测试，覆盖配置初始化、hash 稳定性、parser、合并去重和冲突检测。
- 添加 `HostsImporter`，支持解析 HostCat 管理区块（`# --- HostCat Begin (v1) ---` / `# --- HostCat End ---`）。
- 支持 hosts 导入场景：无 HostCat 区块、完整 v1 区块、缺 Begin、缺 End、未知版本。
- 支持首次启动时将管理区块外内容导入「默认」节点，避免重复导入。
- 支持 UTF-8 读取和 Latin-1 fallback，标记编码问题并提示用户。
- 添加 `HostsImporterTests`，覆盖全部解析场景和编码 fallback。
- 添加 `ConfigMutationService`，提供 group/node 增删改、排序、单选/多选激活行为，默认节点不可删除/不可停用保护。
- 添加 `ConfigMutationServiceTests`，覆盖全部配置变更操作和边界行为。
- 添加 `MenuBarViewModel`，管理菜单栏内存配置状态、节点激活切换、debounce 写入调度和错误展示。
- 更新 `HostCatApp` 菜单栏 UI，支持分组标题展示、节点勾选切换、合成预览入口、冲突和错误提示。
- 添加 `EditorView`，实现左侧分组/节点树（增删改排序）和右侧 hosts 文本编辑。
- 菜单栏「打开编辑器」入口打开 EditorWindow。
- 添加 `MergedPreviewView`，展示合成 hosts 文本、重复条目合并数量、冲突详情。
- 菜单栏「查看合成 Hosts」入口打开预览窗口。

### Documentation

- 补充开发方案设计，明确 XPC 安全边界、状态快照、写入安全策略、测试策略和构建分发策略。
- 新增 README、CHANGELOG 和 AGENTS 协作文档。
- 更新 README，补充 `HostsImporter` 能力和阶段1当前进度。

### Not Yet Implemented

- 真实 `SMAppService` 注册和审批流程。
- 真实 XPC 连接与 code signing requirement 验证。
- 真实 `/private/etc/hosts` 写入、备份、回滚和 DNS 缓存刷新。
- 完整编辑窗口、语法高亮、拖拽排序和冲突解决 UI。
- 签名、公证、DMG 和 GitHub Release 发布流水线。
