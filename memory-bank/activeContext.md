# activeContext.md

> 每次会话结束前由 AI 主动更新此文件。

最后更新：2026-06-16

## 当前状态

- **分支**：main（commit `a68b586`）
- **版本**：1.0.0（pre-release，尚未打 tag）
- **阶段进度**：阶段 1 + 阶段 2 完成；阶段 3 进行中（任务 14 版本号管理 + 任务 19 搜索过滤 + 任务 22 结构化日志最小集已完成）

## 最近一次重要变更

**2026-06-16 任务 22 结构化日志最小集 + XPC timeout 假日志修复**

1. 新增 `DiagnosticLogExporter`，默认导出最近一小时 `com.hostcat.*` OSLog 到纯文本 `.log` 文件；失败时回退当前进程日志 store。
2. 设置页新增「导出诊断日志」按钮和导出状态提示，文案覆盖中英文。
3. 补强 `AppConfigStore` 配置加载/恢复/保存日志，以及 `XPCHostHelperClient` 写入请求、超时、reply 成功/失败日志；既有 `BackupStore`、`HostWriteCoordinator`、Helper 写入日志继续覆盖备份与 hosts 写入。
4. 修复 review 发现的 `XPCHostHelperClient` 成功 reply 后 timeout task 仍会记录假超时并断开连接的问题；新增 `XPCHostHelperPendingRepliesTests` 覆盖首次完成与批量失败清理。
5. 更新 `docs/roadmap-to-1.0.md`、`TODO.md`、`docs/hostcat-design.md`、README、CHANGELOG 和 Xcode 工程。

构建状态：✅ `swift test` 160 全通过（133 XCTest + 27 Swift Testing）/ ✅ `swift build` / ✅ `xcodegen generate` / ✅ `xcodebuild build -project HostCat.xcodeproj -scheme HostCatApp -destination 'platform=macOS,arch=arm64'` / ✅ `git diff --check`。

## 活跃文件

近期接触：
- `Sources/HostCatCore/DiagnosticLogExporter.swift` — 诊断日志读取、格式化和导出
- `Tests/HostCatCoreTests/DiagnosticLogExporterTests.swift` — 导出器格式、空状态、级别名测试
- `Sources/HostCatApp/HostCatApp.swift` — SettingsView 诊断日志导出入口
- `Sources/HostCatApp/Localization.swift` — 诊断日志设置文案 key
- `Sources/HostCatApp/Resources/{zh-Hans,en}.lproj/Localizable.strings` — 诊断日志中英文文案
- `Sources/HostCatCore/AppConfigStore.swift` — 配置加载/恢复/保存 OSLog
- `Sources/HostCatHelperClient/XPCHostHelperClient.swift` — XPC 写入请求/超时/reply OSLog
- `Tests/HostCatCoreTests/XPCHostHelperPendingRepliesTests.swift` — 重复完成 request 与批量清理的回归测试
- `Package.swift`、`project.yml` — `HostCatCoreTests` 测试 target 增加 `HostCatHelperClient` 依赖
- `HostCat.xcodeproj/project.pbxproj` — xcodegen 重新生成，纳入新增 Core 文件
- `docs/roadmap-to-1.0.md`、`TODO.md`、`docs/hostcat-design.md`、README、CHANGELOG — 任务 22 文档状态

## 已做决策（最近）

| 决策 | 时间 | 原因 |
|------|------|------|
| 版本号通过 project.yml 集中管理 | 2026-06-15 | 一处修改全局生效，避免 App/Helper Info.plist 版本不一致 |
| build-release.sh 注入 Git hash 后恢复默认值 | 2026-06-15 | 避免污染 Git 工作区 |
| 搜索使用 .searchable 修饰符 | 2026-06-15 | macOS 原生风格，简洁且自动处理搜索框位置和键盘交互 |
| 搜索三路匹配（分组名/节点名/域名内容） | 2026-06-15 | 覆盖用户最常见的搜索场景 |
| 搜索时自动展开折叠分组 | 2026-06-15 | 确保搜索结果全部可见 |
| 诊断日志导出默认查最近一小时 `com.hostcat.*` | 2026-06-16 | 输出足够覆盖常见写入失败上下文，避免无边界导出系统日志 |
| OSLog system store 不可用时回退当前进程 | 2026-06-16 | 直接分发环境权限不稳定，失败时仍能拿到主应用日志 |
| XPC reply 与 timeout 竞争时以首次完成为准 | 2026-06-16 | 避免成功写入后 timeout task 迟到造成假错误日志和无意义断连 |

## 下一步

按 `docs/roadmap-to-1.0.md` 路线图，剩余必做项：
1. **任务 17** GitHub Actions CI/CD 发布流水线
2. **任务 16** Sparkle 自动更新（依赖任务 17 的 appcast.xml）
3. **任务 26** DMG 安装体验（背景图 + landing page）
4. **任务 14 收尾** 首次打 `1.0.0` tag

## 阻塞

无。

## 备注

- 新建了 `docs/roadmap-to-1.0.md`，梳理距离实际使用的差距（必做 vs 可延后）
- 5/21 完整 autoplan 审查报告：`~/.gstack/projects/kurisu994-host-cat/kurisu-main-autoplan-review-20260521.md`
- 6/8 增量审查报告：`~/.gstack/projects/kurisu994-host-cat/kurisu-main-incremental-review-20260608-142535.md`
