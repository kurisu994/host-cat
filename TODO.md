# HostCat TODO

更新时间：2026-05-20

本文记录 HostCat 基于当前实现进度的实施任务。当前仓库仍处于 SwiftPM 基础框架阶段，真实 `SMAppService` 注册、XPC 写入、签名、公证和 DMG 分发尚未接入。

## 当前基线

- [x] 搭建 SwiftPM 分层骨架：`HostCatApp`、`HostCatCore`、`HostCatHelperClient`、`HostCatPrivilegedHelper`。
- [x] 实现核心模型：`AppConfig`、`HostGroup`、`HostNode`、`AppSettings`、`AppStateMetadata`。
- [x] 实现 hosts parser：IPv4、IPv6、多 hostname、行尾注释和基础错误定位。
- [x] 实现 hosts merge：默认节点参与、激活节点合并、重复条目去重、冲突检测和 HostCat 管理区块输出。
- [x] 实现 hosts 内容 SHA256 hash。
- [x] 提供 `PreviewHostHelperClient`，当前只计算 hash，不写真实 hosts。
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

- [ ] 解析 `# --- HostCat Begin (v1) ---` 和 `# --- HostCat End ---` 管理区块。
- [ ] 支持无 HostCat 区块、完整区块、缺 Begin、缺 End、未知版本。
- [ ] 首次启动把管理区块外内容导入「默认」节点。
- [ ] 如果 hosts 已包含 HostCat 管理区块，只把区块外内容导入「默认」节点，避免重复导入。
- [ ] 实现 UTF-8 读取和 Latin-1 fallback，并标记需要提示用户。
- [ ] 写出统一使用 UTF-8。
- [ ] 增加单元测试：导入、区块解析、异常区块、编码 fallback、区块外内容处理。

### 3. 封装配置变更服务

- [ ] 提供新增、删除、重命名、排序 group 的核心操作。
- [ ] 提供新增、删除、重命名、排序 node 的核心操作。
- [ ] 保证「默认」节点不可删除、不可停用、排序固定。
- [ ] 实现组内单选：激活一个节点时自动关闭同组其他节点。
- [ ] 支持多选组：允许组内多个节点同时激活。
- [ ] 增加单元测试：单选、多选、排序、默认节点保护。

### 4. 实现预览版 `HostWriteCoordinator` actor

- [ ] 合并配置并执行 parser 校验。
- [ ] 检测同 hostname 不同 IP 的冲突并阻止 apply。
- [ ] 使用 500ms debounce 合并菜单栏快速切换。
- [ ] 写入成功后更新 `lastAppliedHostsHash` 和 `lastAppliedAt`。
- [ ] 写入失败时只回滚当前失败批次。
- [ ] 写入期间产生的新操作保留到下一批 debounce。
- [ ] 先接入 `PreviewHostHelperClient`，不触碰真实 `/etc/hosts`。
- [ ] 增加单元测试：debounce、成功快照、失败回滚、新操作保留、hash 不匹配不自动覆盖。

### 5. 做可用的菜单栏预览体验

- [ ] 菜单按「分组标题 + 节点勾选项」展示。
- [ ] 点击节点后立即更新内存状态和菜单勾选状态。
- [ ] 节点状态变更交给 `HostWriteCoordinator` 延迟 apply。
- [ ] 增加「查看合成 Hosts」入口。
- [ ] 增加「打开编辑器」入口。
- [ ] 增加冲突和重复条目提示。
- [ ] 移除当前 `try?` 静默吞错，错误通过 `.alert()` 展示。

### 6. 实现编辑窗口 MVP

- [ ] 左侧展示分组和节点树。
- [ ] 支持新增、删除、重命名 group。
- [ ] 支持新增、删除、重命名 node。
- [ ] 支持 group 和 node 上移、下移排序。
- [ ] 右侧提供 hosts 文本编辑。
- [ ] Apply 前执行语法校验、合并和冲突检测。
- [ ] 首版先用 SwiftUI `TextEditor`，语法高亮和行号后置。

### 7. 实现合成预览与冲突 UX

- [ ] 显示最终合成 hosts 文本。
- [ ] 显示重复条目合并数量。
- [ ] 展示冲突 hostname、来源节点和冲突 IP。
- [ ] 发现冲突时阻止 apply。
- [ ] 引导用户修改节点内容或停用冲突节点后重新 apply。

### 8. 补齐备份模块预研实现

- [ ] 设计 `BackupStore`，负责保存、列出、读取备份。
- [ ] 备份目录使用 `~/Library/Application Support/com.hostcat.app/backups/`。
- [ ] 备份文件名包含时间戳，例如 `hosts_2026-05-20_114000.bak`。
- [ ] 默认保留最近 3 份备份，超出删除最早备份。
- [ ] 在预览阶段只对传入内容或测试临时文件操作，不写真实 `/etc/hosts`。
- [ ] 增加单元测试：备份命名、保留策略、读取恢复内容。

## 阶段 2：真实写入版

目标：接入 `SMAppService` + Privileged Helper，完成安全写入、备份、DNS 刷新和发布链路。

### 9. 建立真实 app/helper 打包基础

- [ ] 从 SwiftPM 骨架过渡到 Xcode app/helper target。
- [ ] 固定主应用 bundle id：`com.hostcat.app`。
- [ ] 固定 Helper bundle id：`com.hostcat.helper`。
- [ ] 配置 Helper 可执行文件位置：`Contents/Library/HelperTools/`。
- [ ] 配置 launchd plist 位置：`Contents/Library/LaunchDaemons/`。
- [ ] 准备本机真实签名环境，进入真实 Helper 注册前不依赖 `Sign to Run Locally`。

### 10. 实现真实 `HostHelperClient` XPC 包装

- [ ] 使用 `NSXPCConnection` 封装 async API。
- [ ] 设置 Helper code signing requirement。
- [ ] 把 XPC reply block 转成 `async throws`。
- [ ] 映射连接失败、签名失败、连接中断、reply 超时和 Helper 业务错误。
- [ ] UI 和服务层只依赖 `HostHelperClient` 协议，不直接接触 XPC。
- [ ] 增加 fake XPC/helper 测试覆盖成功和错误路径。

### 11. 实现 Privileged Helper 安全写入

- [ ] Helper 只写固定 `/private/etc/hosts`，不接受路径参数。
- [ ] 启动时通过 `realpath` 解析并缓存真实 hosts 路径。
- [ ] 写入前检查 immutable flags，发现 `schg` 或 `uchg` 时拒绝写入。
- [ ] 写入前读取当前 hosts 并校验 `expectedCurrentHostsHash`。
- [ ] 使用同目录 `mkstemp` 创建唯一临时文件。
- [ ] 写入后执行 `fsync`，设置 `chmod 644` 和 `chown root:wheel`。
- [ ] 校验临时文件非空、包含必要系统默认条目和 HostCat 管理区块。
- [ ] 使用 `rename(2)` 原子替换 `/private/etc/hosts`。
- [ ] 对父目录执行 `fsync`。
- [ ] 写入成功后执行固定 DNS 刷新命令：`dscacheutil -flushcache` 和 `killall -HUP mDNSResponder`。
- [ ] 失败时清理临时文件，并保留原始 hosts 不变。
- [ ] 默认测试只使用临时目录和协议注入，不污染真实 hosts。

### 12. 接入真实写入流程

- [ ] apply 前自动备份当前 hosts。
- [ ] 检测 `/etc/hosts` 是否被外部修改。
- [ ] 外部修改时提供「导入」「取消」「明确覆盖」决策。
- [ ] 检测 HostCat 管理区块外是否有非空内容。
- [ ] 区块外有内容时默认推荐「导入到默认节点并继续」。
- [ ] 写入失败时回滚 UI/config 到当前失败批次前的成功快照。
- [ ] 写入期间产生的新操作保留到下一次 debounce。
- [ ] 真实 `/private/etc/hosts` 写入只做签名后的本机 smoke test。

### 13. 构建、签名、公证和发布

- [ ] 配置 `xcodebuild test -scheme HostCat -destination 'platform=macOS,arch=arm64'`。
- [ ] 配置 `xcodebuild archive -scheme HostCat -archivePath build/HostCat.xcarchive`。
- [ ] 使用 Developer ID Application 证书导出 app。
- [ ] 使用 `notarytool submit --wait` 公证。
- [ ] 公证成功后执行 `stapler staple`。
- [ ] 打包 DMG。
- [ ] 上传 GitHub Release。
- [ ] 更新 README：系统要求、首次授权步骤、常见故障排查。
- [ ] 更新 CHANGELOG：记录真实写入版能力和限制。

## 后置功能

- [ ] hosts 编辑器语法高亮、行号和错误行标记。
- [ ] 拖拽排序替代上移/下移按钮。
- [ ] 搜索和过滤节点、域名。
- [ ] 全局快捷键打开菜单栏。
- [ ] 鼠标悬停预览 hosts 内容。
- [ ] 中文/英文完整多语言覆盖。
- [ ] Sparkle 自动更新。

## 常用验证命令

```bash
swift test
swift build
git diff --check
```
