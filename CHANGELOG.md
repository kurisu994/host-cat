# Changelog

本项目遵循面向用户和贡献者的变更记录。当前还没有正式版本号，首个阶段记录在 `未发布` 下。

## 未发布

### Added

- 搭建 SwiftPM 基础开发框架，包含 `HostCatApp`、`HostCatCore`、`HostCatHelperClient`、`HostCatPrivilegedHelper` 和 `HostCatCoreTests`。
- 添加 `HostCatCore` 数据模型：`AppConfig`、`HostGroup`、`HostNode`、`AppSettings` 和 `AppStateMetadata`。
- 添加 hosts parser，支持 IPv4、IPv6、多 hostname、行尾注释和基础错误定位。
- 添加 hosts 合并逻辑，支持默认节点参与、激活节点合并、重复条目去重和同域名不同 IP 冲突检测。
- 添加 SHA256 hosts hash 工具，为后续外部修改检测和写入回滚打基础。
- 添加最小 SwiftUI 菜单栏 app 骨架和 Privileged Helper 可执行 target 骨架。
- 添加核心单元测试，覆盖配置初始化、hash 稳定性、parser、合并去重和冲突检测。

### Documentation

- 补充开发方案设计，明确 XPC 安全边界、状态快照、写入安全策略、测试策略和构建分发策略。
- 新增 README、CHANGELOG 和 AGENTS 协作文档。

### Not Yet Implemented

- 真实 `SMAppService` 注册和审批流程。
- 真实 XPC 连接与 code signing requirement 验证。
- 真实 `/private/etc/hosts` 写入、备份、回滚和 DNS 缓存刷新。
- 完整编辑窗口、语法高亮、拖拽排序和冲突解决 UI。
- 签名、公证、DMG 和 GitHub Release 发布流水线。
