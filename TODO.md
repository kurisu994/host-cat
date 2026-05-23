# HostCat TODO

更新时间：2026-05-23

本文记录 HostCat 基于当前实现进度的实施任务。阶段 1（安全预览版）和阶段 2（真实写入版）已完成。

## 当前基线

- [x] 搭建 SwiftPM 分层骨架：`HostCatApp`、`HostCatCore`、`HostCatHelperClient`、`HostCatPrivilegedHelper`。
- [x] 实现核心模型：`AppConfig`、`HostGroup`、`HostNode`、`AppSettings`、`AppStateMetadata`。
- [x] 补充核心模型 Codable/Equatable 覆盖，以及备份恢复失败回归测试。
- [x] 实现 hosts parser：IPv4、IPv6、多 hostname、行尾注释和基础错误定位。
- [x] 实现 hosts merge：默认节点参与、激活节点合并、重复条目去重、冲突检测和 HostCat 管理区块输出。
- [x] 实现 hosts 内容 SHA256 hash。
- [x] 提供 `PreviewHostHelperClient`，开发调试时绕过 Helper 注册。
- [x] 提供最小 `MenuBarExtra` 菜单栏入口和 Settings 页面。
- [x] 提供 `HostCatPrivilegedHelper` 可执行 target 骨架。
- [x] 当前验证命令通过：`swift test`、`swift build`。

## 阶段 1：安全预览版

目标：先完成可持久化、可编辑、可预览的 hosts 管理体验，不写入真实 `/etc/hosts`。

### 1. 补齐配置存储

- [x] 新增 JSON 配置读写模块。
- [x] 使用 `~/Library/Application Support/com.hostcat.app/config.json` 作为默认配置路径。
- [x] 支持 `configVersion` 校验和未来迁移入口。
- [x] 配置不存在时创建 `AppConfig.initial(defaultHosts:)`。
- [x] JSON 损坏时恢复默认配置，并返回可展示的错误状态。
- [x] 写入采用原子写入：临时文件写入后 rename。
- [x] 增加单元测试：保存、读取、损坏恢复、版本入口、原子写入失败不破坏旧配置。

### 2. 实现 hosts 导入与管理区块解析

- [x] 解析 `# --- HostCat Begin (v1) ---` 和 `# --- HostCat End ---` 管理区块。
- [x] 支持无 HostCat 区块、完整区块、缺 Begin、缺 End、未知版本。
- [x] 首次启动把管理区块外内容导入「默认」节点。
- [x] 如果 hosts 已包含 HostCat 管理区块，只把区块外内容导入「默认」节点，避免重复导入。
- [x] 实现 UTF-8 读取和 Latin-1 fallback，并标记需要提示用户。
- [x] 写出统一使用 UTF-8。
- [x] 增加单元测试：导入、区块解析、异常区块、编码 fallback、区块外内容处理。

### 3. 封装配置变更服务

- [x] 提供新增、删除、重命名、排序 group 的核心操作。
- [x] 提供新增、删除、重命名、排序 node 的核心操作。
- [x] 保证「默认」节点不可删除、不可停用、排序固定。
- [x] 实现组内单选：激活一个节点时自动关闭同组其他节点。
- [x] 支持多选组：允许组内多个节点同时激活。
- [x] 增加单元测试：单选、多选、排序、默认节点保护。

### 4. 实现预览版 `HostWriteCoordinator` actor

- [x] 合并配置并执行 parser 校验。
- [x] 检测同 hostname 不同 IP 的冲突并阻止 apply。
- [x] 使用 500ms debounce 合并菜单栏快速切换。
- [x] 写入成功后更新 `lastAppliedHostsHash` 和 `lastAppliedAt`。
- [x] 写入失败时只回滚当前失败批次。
- [x] 写入期间产生的新操作保留到下一批 debounce。
- [x] 先接入 `PreviewHostHelperClient`，不触碰真实 `/etc/hosts`。
- [x] 增加单元测试：debounce、成功快照、失败回滚、新操作保留、hash 不匹配不自动覆盖。

### 5. 做可用的菜单栏预览体验

- [x] 菜单按「分组标题 + 节点勾选项」展示。
- [x] 点击节点后立即更新内存状态和菜单勾选状态。
- [x] 节点状态变更交给 `HostWriteCoordinator` 延迟 apply。
- [x] 增加「查看合成 Hosts」入口。
- [x] 增加「打开编辑器」入口。
- [x] 增加冲突和重复条目提示。
- [x] 移除当前 `try?` 静默吞错，错误通过状态展示。

### 6. 实现编辑窗口 MVP

- [x] 左侧展示分组和节点树。
- [x] 支持新增、删除、重命名 group。
- [x] 支持新增、删除、重命名 node。
- [x] 支持 group 和 node 上移、下移排序。
- [x] 右侧提供 hosts 文本编辑。
- [x] Apply 前执行语法校验、合并和冲突检测。
- [x] 首版先用 SwiftUI `TextEditor`，语法高亮和行号后置。

### 7. 实现合成预览与冲突 UX

- [x] 显示最终合成 hosts 文本。
- [x] 显示重复条目合并数量。
- [x] 展示冲突 hostname、来源节点和冲突 IP。
- [x] 发现冲突时阻止 apply。
- [x] 引导用户修改节点内容或停用冲突节点后重新 apply。

### 8. 补齐备份模块预研实现

- [x] 设计 `BackupStore`，负责保存、列出、读取备份。
- [x] 备份目录使用 `~/Library/Application Support/com.hostcat.app/backups/`。
- [x] 备份文件名包含时间戳，例如 `hosts_2026-05-20_114000.bak`。
- [x] 默认保留最近 3 份备份，超出删除最早备份。
- [x] 在预览阶段只对传入内容或测试临时文件操作，不写真实 `/etc/hosts`。
- [x] 增加单元测试：备份命名、保留策略、读取恢复内容。

## 阶段 2：真实写入版

目标：接入 `SMAppService` + Privileged Helper，完成安全写入、备份、DNS 刷新和发布链路。

### 9. 建立真实 app/helper 打包基础

- [x] 从 SwiftPM 骨架过渡到 Xcode app/helper target（使用 xcodegen）。
- [x] 固定主应用 bundle id：`com.hostcat.app`。
- [x] 固定 Helper bundle id：`com.hostcat.helper`。
- [x] 配置 Helper 可执行文件位置：`Contents/Library/HelperTools/`。
- [x] 配置 launchd plist 位置：`Contents/Library/LaunchDaemons/`。
- [x] 准备发布构建脚本 `scripts/build-release.sh`，要求 Developer ID 证书与 Team ID 后执行签名导出。

### 10. 实现真实 `HostHelperClient` XPC 包装

- [x] 使用 `NSXPCConnection` 封装 async API（`XPCHostHelperClient`）。
- [x] 设置 Helper code signing requirement，使用 `anchor apple generic`、固定 bundle identifier 和真实 Team ID。
- [x] 把 XPC reply block 转成 `async throws`。
- [x] 映射连接失败、签名失败、连接中断、reply 超时和 Helper 业务错误。
- [x] UI 和服务层只依赖 `HostHelperClient` 协议，不直接接触 XPC。
- [x] 增加 `FakeHostHelperClient` 测试替身，覆盖成功和错误路径。

### 11. 实现 Privileged Helper 安全写入

- [x] Helper 只写固定 `/private/etc/hosts`，不接受路径参数。
- [x] 启动时通过 `realpath` 解析并缓存真实 hosts 路径。
- [x] 写入前检查 immutable flags，发现 `schg` 或 `uchg` 时拒绝写入。
- [x] 写入前读取当前 hosts 并校验 `expectedCurrentHostsHash`。
- [x] 使用同目录 `mkstemp` 创建唯一临时文件。
- [x] 写入后执行 `fsync`，设置 `chmod 644` 和 `chown root:wheel`。
- [x] 校验临时文件非空、包含 HostCat 管理区块标记。
- [x] 使用 `rename(2)` 原子替换 `/private/etc/hosts`。
- [x] 对父目录执行 `fsync`。
- [x] 写入成功后执行固定 DNS 刷新命令：`dscacheutil -flushcache` 和 `killall -HUP mDNSResponder`。
- [x] 失败时清理临时文件，并保留原始 hosts 不变。
- [x] 默认测试只使用临时目录和协议注入（`FakeFileSystemOperations`），不污染真实 hosts。

### 12. 接入真实写入流程

- [x] apply 前自动备份当前 hosts。
- [x] 检测 `/etc/hosts` 是否被外部修改（`ExternalModificationDetector`）。
- [x] 外部修改时提供「取消」「确认覆盖」决策弹窗。
- [x] 写入失败时保留配置草稿并提示 hosts 未应用（不自动回滚 UI）。
- [x] 写入期间产生的新操作保留到下一次 debounce。
- [x] 从备份恢复采用事务式写入，写入成功前不替换当前配置，失败时保留当前配置和持久化配置。
- [x] 真实 `/private/etc/hosts` 写入只做签名后的本机 smoke test。

### 13. 构建、签名、公证和发布

- [x] 配置 `xcodebuild archive` 和 `xcodebuild -exportArchive`。
- [x] 使用 `scripts/build-release.sh` 支持归档、代码签名导出与 DMG 打包。
- [x] 缺少 Developer ID 证书或 `DEVELOPMENT_TEAM` 时发布脚本直接失败，避免生成不可验证的 release 包。
- [x] 更新 README：系统要求、首次授权步骤、常见故障排查。
- [x] 更新 CHANGELOG：记录真实写入版能力和限制。

## 后置功能

- [x] hosts 编辑器语法高亮、行号和错误行标记。
- [x] 编辑器工具栏（节点名称展示、撤销/应用按钮、未保存状态提示）。
- [x] 修复编辑器行号与标题栏样式问题。
- [ ] 跨分组拖拽排序（当前已实现分组内节点拖拽）。
- [ ] 搜索和过滤节点、域名。
- [ ] 全局快捷键打开菜单栏。
- [ ] 鼠标悬停预览 hosts 内容。
- [ ] 中文/英文完整多语言覆盖。
- [ ] Sparkle 自动更新。
- [ ] GitHub Actions CI/CD 发布流水线。
- [ ] iCloud 同步。

## 常用验证命令

```bash
# 生成 Xcode 工程
xcodegen generate

# 命令行构建
xcodebuild build -project HostCat.xcodeproj -scheme HostCatApp -destination 'platform=macOS,arch=arm64'

# 核心单测
swift test

# 发布打包
./scripts/build-release.sh

# 代码格式检查
git diff --check
```
