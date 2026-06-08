# HostCat TODO

更新时间：2026-06-08

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
- [x] ~~跨分组拖拽排序（当前已实现分组内节点拖拽）~~ — **已砍**，产品决策：跨组拖拽引入的交互复杂度和意外行为风险大于收益，保持分组内拖拽即可满足核心排序需求。
- [ ] 搜索和过滤节点、域名。
- [ ] 全局快捷键打开菜单栏。
- [x] 鼠标悬停预览 hosts 内容。
- [ ] 中文/英文完整多语言覆盖（主界面和主要错误流已完成，仍需收敛底层诊断细节并评估字符串目录迁移）。
- [ ] Sparkle 自动更新。
- [ ] GitHub Actions CI/CD 发布流水线。
- [ ] iCloud 同步。

## 阶段 3：上线准备（新增）

目标：完善发布链路、用户体验和运营基础设施，达到可公开分发的 1.0 标准。

### 14. 版本号与发布管理

- [ ] 确定版本号方案（semver）。
- [ ] Info.plist / `CFBundleShortVersionString` 与 Git tag 对齐。
- [ ] 构建脚本自动注入版本号和 commit hash。
- [ ] 首次打 `1.0.0` tag，完成从「未发布」到「正式版」的过渡。

### 15. 中英文多语言覆盖

- [ ] 将当前 `.strings` 资源迁移到 `Localizable.xcstrings`。
- [x] 接入中文（简体）和英文两套 App/Core 字符串资源及构建资源 bundle。
- [x] 菜单栏项、弹窗、主要错误提示和设置页面完成本地化。
- [x] 设置页提供跟随系统/简体中文/English 选择，并支持界面运行时即时切换。
- [x] 切换语言时立即刷新菜单栏本地化操作项，不依赖鼠标悬停触发更新。
- [x] Helper 注册与审批入口整合到设置页，移除独立引导窗口。
- [ ] 清理底层文件系统与命令执行诊断细节中残留的英文文本。

### 16. Sparkle 自动更新

- [ ] 引入 Sparkle 框架（Swift Package Manager）。
- [ ] 配置 `SUFeedURL` 指向 GitHub Releases appcast XML。
- [ ] 首次发版时生成 `appcast.xml` 并随 Release 附件上传。
- [ ] 设置更新检查间隔（默认 24 小时）。

### 17. GitHub Actions CI/CD 发布流水线

- [ ] 配置 GitHub Actions workflow：触发条件为 tag push。
- [ ] 步骤：安装证书和 provisioning profile（通过 secrets）。
- [ ] 步骤：`xcodebuild archive` + `xcodebuild -exportArchive`。
- [ ] 步骤：`xcrun notarytool` 公证。
- [ ] 步骤：生成 DMG（`build-release.sh` 或 `create-dmg`）。
- [ ] 步骤：生成 Sparkle `appcast.xml`。
- [ ] 步骤：自动创建 GitHub Release，上传 DMG + appcast.xml。

### 18. 全局快捷键

- [ ] 引入 `MASShortcut` 或 `KeyboardShortcuts`（推荐 SwiftUI 友好方案）。
- [ ] 支持「打开菜单栏」全局快捷键（默认未绑定，首次设置时引导）。
- [ ] 快捷键偏好持久化到 `AppSettings`。
- [ ] 注册/注销 `CGEventTap` 或 `NSEvent` 全局监听。

### 19. 搜索和过滤

- [ ] 编辑器侧边栏顶部添加搜索框。
- [ ] 实时过滤分组和节点名称（支持拼音模糊匹配）。
- [ ] 过滤结果保持树状结构展示。
- [ ] 支持搜索 hosts 域名（在节点内容中匹配）。
- [ ] 空结果时展示空状态提示。

### 20. 配置导入导出

- [ ] 编辑器菜单增加「导出配置」入口，输出 `config.json`。
- [ ] 编辑器菜单增加「导入配置」入口，校验版本后合并或替换。
- [ ] 导入时冲突处理：提示用户选择「替换」或「合并」。
- [ ] 支持从旧版本配置平滑迁移。

### 21. 通知中心集成

- [ ] 注册 `UNUserNotificationCenter` 权限。
- [ ] hosts 写入成功时发送通知（可选，可在设置中关闭）。
- [ ] hosts 写入失败时发送通知（重要，提醒用户查看）。
- [ ] 外部修改检测到时发送通知。
- [ ] 通知点击行为：打开编辑器或菜单栏。

### 22. 崩溃报告与诊断日志

- [ ] 集成崩溃报告（Sentry 或 Apple Crash Reports 符号化）。
- [ ] 增加结构化日志系统（`OSLog` 或 `swift-log`），覆盖关键路径：XPC、写入、备份、配置加载。
- [ ] 设置页面增加「导出诊断日志」按钮。
- [ ] 日志级别：error、warning、info、debug。

### 23. 大文件性能与稳定性验证

- [ ] 测试 5000+ 行 hosts 文件的解析和合并性能。
- [ ] 测试 TextKit 2 语法高亮在超大文件下的响应。
- [ ] 验证长时间运行（>7 天）内存占用是否稳定。
- [ ] 验证 XPC 连接断开后自动重连是否可靠。

### 24. 可访问性（Accessibility）

- [ ] 菜单栏项支持 VoiceOver 朗读。
- [ ] 编辑器侧边栏支持 VoiceOver 导航。
- [ ] 所有按钮和控件添加 `accessibilityLabel` 和 `accessibilityHint`。
- [ ] 支持键盘完全操作（Tab 导航、Enter/Space 触发）。

### 25. 隐私政策与合规

- [ ] 编写 `PRIVACY.md`：声明不收集用户数据、不联网（除 Sparkle 更新检查）。
- [ ] 首次启动展示隐私政策摘要（可跳过）。
- [ ] 如集成 Sentry，明确说明收集的崩溃信息范围。

### 26. 分发渠道决策

- [x] 确定走**独立官网分发**（LaunchDaemon 方案不支持 Mac App Store）。
- [ ] 准备官网 landing page（或 GitHub 页面作为临时官网）。
- [ ] 准备 DMG 背景图和拖拽安装指引。

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
