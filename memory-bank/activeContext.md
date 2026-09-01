# activeContext.md

> 每次会话结束前由 AI 主动更新此文件。

最后更新：2026-09-01

## 当前状态

- **分支**：main（工具链基线更新已提交）
- **版本**：1.0.0（pre-release，尚未打 tag）
- **阶段进度**：阶段 1 + 阶段 2 完成；阶段 3 进行中（任务 14 版本号管理 / 任务 18 全局快捷键 / 任务 19 搜索过滤 / 任务 22 结构化日志最小集 / 任务 25 隐私政策 / 任务 26 DMG + landing page 已完成）

## 最近一次重要变更

**2026-09-01 对齐 Xcode / XcodeGen 工具链基线**

1. `project.yml` 的 `xcodeVersion` 从 26.5 更新为 26.6，`minimumXcodeGenVersion` 从 2.40.0 更新为 2.46.0。
2. 使用 XcodeGen 2.46.0 重新生成 `HostCat.xcodeproj`；生成结果同步更新 Xcode upgrade 标记，并按 spec 声明顺序排列 targets。
3. 清理 workspace 中残留但已忽略的 `KeyboardShortcuts 2.4.0` `Package.resolved`；生产工程仍保持零第三方依赖。
4. 验证通过：165 个 Swift 测试、`swift build`、完整 HostCatApp Xcode 构建。

**2026-06-18 自实现 Carbon 全局快捷键，移除 KeyboardShortcuts 三方依赖**

1. 新增 `Shortcut.swift`：值类型（keyCode + carbonModifiers），支持 Codable / NSEvent 构造 / Cocoa→Carbon mask 转换 / UCKeyTranslate 当前键盘布局翻译 + 特殊键符号表兜底。
2. 新增 `CarbonHotKeyMonitor.swift`：`@MainActor` 单例，Carbon `RegisterEventHotKey` + `InstallEventHandler` 回调用 `MainActor.assumeIsolated` 安全进入 main 隔离域。
3. 新增 `ShortcutRecorderView.swift`：`NSViewRepresentable` 录制框，要求 modifier、Esc 取消、清除按钮解绑；通过 idle/recording placeholder 注入支持本地化。
4. 重写 `GlobalShortcuts.swift`：`ShortcutStore` `ObservableObject` 单例，`@Published toggleMenuBar` setter 自动 JSON 持久化到 `UserDefaults` 并重注册 Carbon；`MenuBarStatusItemOpener` 保留不动。
5. `HostCatApp.swift`：移除 `import KeyboardShortcuts`，`@StateObject(wrappedValue: ShortcutStore.shared)` 注入 SettingsView，`Recorder` 替换为 `ShortcutRecorderView`，`applicationDidFinishLaunching` 改调 `bootstrap()`。
6. `project.yml` 移除 `packages.KeyboardShortcuts` + dependency；`xcodegen generate` 重生成 pbxproj；新增 2 条 placeholder 本地化（中英）。
7. CHANGELOG「未发布」段直接改写原"接入 KeyboardShortcuts"条目为最终事实（自实现），不留中间状态痕迹。

构建状态：✅ `xcodebuild -scheme HostCatApp -configuration Debug build` BUILD SUCCEEDED，0 warning / 0 error / Xcode 自动清理旧 `KeyboardShortcuts_KeyboardShortcuts.bundle`；✅ `rg KeyboardShortcuts` 全工程 0 命中。landing page（gh-pages 分支）「零三方依赖」声明重新与事实一致，无需改动。

## 活跃文件

近期接触：
- `project.yml` / `HostCat.xcodeproj` — Xcode 26.6、XcodeGen 2.46.0 基线与生成工程
- `CHANGELOG.md` / `memory-bank/techContext.md` — 同步工具链版本事实
- `Sources/HostCatApp/Shortcut.swift` / `CarbonHotKeyMonitor.swift` / `ShortcutRecorderView.swift` — 自实现快捷键三件套（新增）
- `Sources/HostCatApp/GlobalShortcuts.swift` — `ShortcutStore` + `MenuBarStatusItemOpener`（重写）
- `Sources/HostCatApp/HostCatApp.swift` — 移除依赖、注入 shortcutStore、替换 Recorder
- `Sources/HostCatApp/Localization.swift` + `Localizable.xcstrings` — 录制框 placeholder 文案
- `project.yml` + `HostCat.xcodeproj/project.pbxproj` — 移除 KeyboardShortcuts 包
- `CHANGELOG.md` — 改写未发布段全局快捷键条目
- `memory-bank/{techContext,progress,systemPatterns,activeContext}.md` — 同步本次变更

## 已做决策（最近）

| 决策 | 时间 | 原因 |
|------|------|------|
| XcodeGen 最低版本对齐到 2.46.0 | 2026-09-01 | 与官方最新稳定版及当前开发环境一致，避免不同版本生成工程产生漂移 |
| 自实现快捷键替代 KeyboardShortcuts 三方包 | 2026-06-18 | 维持「零三方依赖」承诺；KeyboardShortcuts 内部也是包 Carbon，自实现成本可控（~250 行） |
| 用 Carbon `RegisterEventHotKey` 而非 `NSEvent.addGlobalMonitor` | 2026-06-18 | 前者是 Apple 官方稳定 API（10.3 起），不需要"输入监控/辅助功能"授权；后者要授权弹窗，体验差 |
| 录制框用 `NSViewRepresentable` 而非纯 SwiftUI | 2026-06-18 | SwiftUI 没有捕获原始 `keyDown` 事件的标准 API；NSView first responder + keyDown 是标准做法 |
| Shortcut.displayString 用 `UCKeyTranslate` | 2026-06-18 | 兼容不同键盘布局；特殊键（F1-F20 / 方向键 / Esc / Space / Return 等）走硬编码符号表兜底，翻译失败退化为 `#<keyCode>` 避免崩溃 |
| Carbon callback 用 `MainActor.assumeIsolated` 进入隔离域 | 2026-06-18 | Carbon EventHandler 实际就在主线程派发；Swift 6 严格并发下用 `assumeIsolated` 是标准桥接做法 |
| `ShortcutStore` 用 `_toggleMenuBar = Published(initialValue:)` 绕过 didSet | 2026-06-18 | 从 UserDefaults 恢复时不希望触发"再次写盘 + 重注册"副作用 |
| CHANGELOG 未发布段改写而非加 Removed 行 | 2026-06-18 | 还没发版，没必要保留"先加依赖又移除"的脏历史；读者看到的应是最终事实 |
| 使用 AppleScript 动态构建 DMG 布局 | 2026-06-16 | macOS 官方首选方案，能在只读 DMG 中准确保持 Finder 窗口边界、背景与图标坐标 |
| 诊断日志导出默认查最近一小时 `com.hostcat.*` | 2026-06-16 | 输出足够覆盖常见写入失败上下文，避免无边界导出系统日志 |
| XPC reply 与 timeout 竞争时以首次完成为准 | 2026-06-16 | 避免成功写入后 timeout task 迟到造成假错误日志和无意义断连 |

## 下一步

按 `docs/roadmap-to-1.0.md` 路线图，剩余必做项：
1. **任务 17** GitHub Actions CI/CD 发布流水线
2. **任务 16** Sparkle 自动更新（依赖任务 17 的 appcast.xml）
3. **任务 14 收尾** 首次打 `1.0.0` tag

## 阻塞

无。

## 备注

- gh-pages 分支当前 commit `4cd8466`，已包含「全局快捷键」「隐私优先」卡片更新；本次依赖移除让其「零三方依赖」声明无需任何修改即重新成立。
- 5/21 完整 autoplan 审查报告：`~/.gstack/projects/kurisu994-host-cat/kurisu-main-autoplan-review-20260521.md`
- 6/8 增量审查报告：`~/.gstack/projects/kurisu994-host-cat/kurisu-main-incremental-review-20260608-142535.md`
