# Changelog

本项目遵循面向用户和贡献者的变更记录。当前还没有正式版本号，首个阶段记录在 `未发布` 下。

## 未发布

### Added

- **【大文件编辑响应】** 新增 `LargeHostsPerformanceTests` 覆盖 6000 行解析、校验、合并、导入、哈希和配置读写。编辑器语法校验改为停止输入 200ms 后执行；`HostsTextView` 在文本和错误行未变化时跳过全量高亮，滚动时复用文档宽度缓存。
- **【可访问性】** 编辑器侧边栏改为列表选择，方向键可移动节点；节点启用、分组折叠改为按钮。菜单栏节点、侧边栏、备份工具栏和快捷键清除按钮补充 VoiceOver 标签与提示。

- **【写入诊断多语言收敛】** 新增 `WriteErrorDetail`：`HostsWriteError` 的底层细节不再硬编码英文，而是携带「key + 参数」，在 `description(in:)` 里按主应用经 XPC 传来的语言翻译（覆盖 chmod/chown/rename/fsync、内容校验、DNS 刷新等 15 条）；`strerror` 与命令名等系统原文保留以便排障。
- **【通知中心集成】** 新增 `NotificationService`（`UserNotifications`）与 Core 层 `ApplyNotificationEvent` / `NotificationPreferences`：`MenuBarViewModel.applyEventHandler` 在写入成功、失败（含冲突、Helper 不可用）和检测到外部修改时广播事件，App 层按偏好转成系统通知；写入成功通知默认关闭，失败与外部修改默认开启；授权在用户首次需要时懒请求，被系统拒绝时设置页提示并可跳转系统通知设置；点击通知弹出菜单栏菜单。设置页新增「通知」卡片，三个开关即时生效。
- **【配置导入导出】** 编辑器工具栏新增「更多」菜单，支持导出 / 导入 `config.json`：新增 `ConfigTransferService`（纯逻辑、可单测），导出时清除 `state`（hash 与应用时间）避免换机后误判外部修改；导入先校验格式与 `configVersion`（经 `migrate` 迁移入口），再由用户选择「合并」（按分组名 / 节点名匹配，同名节点仅更新内容并保留本机激活状态，新增节点默认不启用，默认节点不变）或「替换」（覆盖默认节点内容与全部分组）；设置与本机 state 始终保留。
- **【全局快捷键】** 新增「打开菜单栏」全局快捷键，零三方依赖：`CarbonHotKeyMonitor` 基于 Carbon `RegisterEventHotKey` 实现全局监听（Apple 官方稳定 API，10.3 起可用，不需要"输入监控"或"辅助功能"等系统授权）；`ShortcutRecorderView` 是原生 `NSViewRepresentable` 录制框，按下带 ⌘/⌥/⌃ 的组合键即写入并立即重注册、Esc 取消、清除按钮解绑；`ShortcutStore` 把绑定以 JSON 持久化到 `UserDefaults`，启动时自动恢复；触发回调时通过遍历 `NSStatusBarWindow` 找到 MenuBarExtra 状态项 button 并模拟点击弹出菜单。默认未绑定，在设置页 → 快捷键中录入。
- **【隐私政策与首启摘要】** 新增仓库根目录 `PRIVACY.md`（中英合并），覆盖不联网/不收集、本地存储范围、Privileged Helper 边界、Sparkle 联网预告与第三方组件；首次启动通过 `HostCatAppDelegate` 弹出 `WelcomeView` 隐私摘要窗口（四条要点 + 「查看完整隐私政策」按钮），关闭后写入 `UserDefaults` 键 `HostCat.privacyWelcomeShown` 不再弹出；PRIVACY.md 同步打包进 app bundle，按钮通过 `NSWorkspace.open` 调用系统默认编辑器查看完整文本。
- **【字符串目录迁移】** 将 App 与 Core 的本地化资源从 `*.lproj/*.strings` 迁移到 `Localizable.xcstrings` / `LocalizableCore.xcstrings` 字符串目录（Xcode 15+ 推荐格式），统一中英文翻译管理；构建期 Xcode 和 SwiftPM 都会自动生成 `*.lproj/*.strings`，运行时 `AppLanguage.localizedBundle(in:)` 取值路径不变。
- **【DMG 安装体验】** 准备了精美的 macOS 科技感暗色调拖拽安装背景图 `scripts/dmg-background.png`；编写了 `scripts/create-dmg.sh` 脚本，基于 AppleScript 精准配置 DMG 挂载后的 Finder 窗口尺寸、背景图布局、应用图标与 Applications 快捷方式位置；升级了 `scripts/build-release.sh` 以在构建发布版本时自动调用该脚本生成高品质的 DMG 镜像。
- **【版本号管理】** `project.yml` 集中定义 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`，App 和 Helper 的 Info.plist 统一引用变量；设置页展示完整版本号（含 build 号 and Git commit hash）。
- **【搜索过滤】** 编辑器侧边栏新增搜索框（`.searchable`），支持按分组名、节点名和 hosts 域名内容实时过滤，过滤后保持树状结构，搜索时自动展开折叠分组，空结果展示提示。
- **【诊断日志】** 新增 `DiagnosticLogExporter`，设置页支持导出最近一小时 `com.hostcat.*` OSLog 诊断日志；补强 XPC、hosts 写入、备份和配置加载关键路径日志。
- 构建脚本 `build-release.sh` 支持自动注入版本号、build 号和 Git commit hash，构建完成后恢复 Info.plist 默认值避免污染 Git 工作区。
- 新增 `ValidatorParityTests`，验证 `HostsParser.validate` 与 `HostsContentValidator.validate` 在语法错误上行为一致，避免编辑器校验通过但写入侧二次拒绝的边界差异。
- 补充 `HostWriteCoordinatorTests` 失败语义测试：hash mismatch 不自动重试、失败批次不阻塞后续批次。
- 在 `/memory-bank/` 下新建 6 份记忆银行文件（projectbrief / productContext / systemPatterns / techContext / activeContext / progress），供后续 AI 会话快速恢复项目上下文。
- 添加简体中文与英文字符串资源，覆盖菜单栏、编辑/预览、Helper 设置、备份恢复、设置页及 Core 用户可见错误。
- 添加设置页语言选择器，支持跟随系统、简体中文与 English 在运行期间即时切换。
- **【语法高亮与行号】hosts 编辑器语法高亮与多行错误定位标记：使用 TextKit 2 与 NSRulerView 实现极佳的等宽 hosts 编辑与校验体验。**
- 添加 `HostsSyntaxHighlighter` 语法高亮引擎，基于 TextKit 2 渲染 IP (蓝色)、hostname (绿色)、注释 (灰色)、HostCat 标记 (橙色粗体)，并对语法错误行进行红色半透明背景高亮。
- 添加 `LineNumberRulerView` 自定义行号组件（`NSRulerView` + TextKit 2 `NSTextLayoutManager`），支持精确的滚动同步、当前行粗体加亮、并在错误行显示红色数字和红点标识。
- 添加 `HostsTextView` 桥接组件（`NSViewRepresentable` 封装 `NSTextView` 和 `NSScrollView`），禁用自动纠错、智能引号等行为，提供完美的程序员 hosts 编辑环境。
- 升级 `HostsParser` 增加非抛出错误的 `validate(_:)` 方法，能够单次收集整个 hosts 文本中所有的语法错误行。
- 升级 `EditorView` 语法校验，使编辑器能同时在文本及行号栏中高亮所有错误行，并在底部状态栏展示语法错误数。
- 添加 `HostsParserTests.testValidateCollectsMultipleErrors` 测试，验证能够同时检测并提取多行错误。
- **【阶段 2 完成】真实写入版已完成：使用 xcodegen 迁移为标准 Xcode 工程，实现真实 XPC 服务、安全写入和完整的 UI 交互。**
- 添加 `HostCatHelperClient` 真实 XPC 连接封装（`XPCHostHelperClient`），实现 SMAppService 注册与开机启动管理（`HelperRegistrationManager`）。
- 添加 Privileged Helper (`HostCatPrivilegedHelper`)，基于安全策略执行真实 `/etc/hosts` 写入、权限设置和 DNS 刷新。
- 添加 `HostsFileWriter` 安全文件写入器，实现 immutable flags 检查、mkstemp 临时文件、fsync、chmod/chown、rename 原子替换和目录 fsync。
- 添加 `DNSRefresher`（`SystemDNSRefresher`），执行固定 DNS 刷新命令。
- 添加 `ExternalModificationDetector` 外部修改检测及 UI 决策弹窗（`ExternalModificationAlert`）。
- 添加写入前自动备份（`HostWriteCoordinator` 在写入前调用 `BackupStore.createBackup`）。
- 增强 HostCatApp UI：设置页集中管理 Helper 注册和系统审批、备份管理与事务式恢复 (`BackupRestoreView`)、外部修改弹窗。
- 新增 `scripts/build-release.sh` 支持归档、代码签名导出与 DMG 打包；发布构建要求显式提供 Developer ID 证书和 Team ID。
- 添加应用图标资源（Assets.xcassets，7 个尺寸）。
- 拆分 `EditorView.swift` 为 `EditorView`、`SidebarComponents`、`NameInputDialog`、`NodeReorderDropDelegate` 四个文件。
- 拆分 `HostCatApp.swift` 为 `HostCatApp`、`MenuBarContentView`、`WindowFocus` 三个文件。
- 添加 `MenuBarViewModelTests` 验证写入失败时保留配置草稿、备份恢复失败时不污染当前配置和持久化配置。
- 添加 `ModelsTests` 覆盖核心模型 Codable/Equatable 行为。
- 添加 `TestDoubles.swift`（`FakeHostHelperClient`、`FakeFileSystemOperations`、`StubDNSRefresher`）。
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

### Changed

- 主机名只接受 ASCII：`中文.test`、`café.local` 这类 hosts 解析器永远匹配不到的写法会被标为语法错误，国际化域名需写成 punycode（`xn--`）。
- 全局快捷键必须包含 ⌘/⌥/⌃ 之一；只带 ⇧ 的组合会拦截全系统的大写输入，录制时拒绝，旧版本存下的此类快捷键启动时丢弃。
- 将 Xcode 工程生成基线更新到 Xcode 26.6 与 XcodeGen 2.46.0，保持生成工具版本和当前开发环境一致。
- 放大菜单栏悬停时的合成 Hosts 预览窗口，便于浏览较长的预览内容。
- 将 Helper 安装入口收敛到设置页，并在菜单栏提供统一的“设置”入口。

### Fixed

- **【Helper 打包】** 修复 Release 包里 Helper 无法启动和通过签名校验的问题：launchd plist 补上 `BundleProgram` 与 `AssociatedBundleIdentifiers`；Helper 开启 `CREATE_INFOPLIST_SECTION_IN_BINARY`，签名标识变为 `com.hostcat.helper`，运行时也能读到 `HostCatTeamIdentifier`；rpath 增加 `@executable_path/../../Frameworks`，Helper 能从 `Contents/Frameworks` 加载 `HostCatCore`；App 与 Helper 的 Release 配置开启 Hardened Runtime 以满足公证要求。
- **【误报外部修改】** 第一次写入还在进行时再切换节点，第二次写入会拿快照里的旧 hash 去比对，被误判为「hosts 被外部修改」。现在 coordinator 优先使用本会话最近一次成功写入的 hash，被取代批次的成功结果也会记进配置。
- **【错误分类】** Helper 返回的写入失败（如缺少 `::1 localhost` 等系统条目、rename 失败）不再被当成「Helper 不可用」而弹出安装/重试引导，改为显示 Helper 给出的具体原因；未知错误码归为异常回复。
- **【XPC 连接】** 连接回调按连接代际区分：旧连接的中断/失效回调晚到时，不再让新连接上的请求失败，也不再把新连接一起关掉。
- **【备份清理】** 备份按文件名中的纪元纳秒排序，而不是本地时间串；跨时区或夏令时回拨后，清理不会再把刚建的备份当成最旧的删掉，备份列表的时间显示也随之准确。
- **【诊断日志】** 日志中的错误原因、hash 前缀、节点名等字符串插值标注为公开，Release 包导出的诊断日志不再全是 `<private>`。
- **【配置恢复提示】** 配置文件损坏被重置时在菜单和编辑器状态栏提示用户；配置读取失败时先把原文件挪到 `config.json.unreadable.*` 保留，避免后续保存覆盖。
- **【编辑器】** 有未应用修改时切换节点会先询问「先应用 / 放弃 / 取消」，不再静默丢弃编辑；重命名当前节点后标题同步更新；拖拽节点拖到列表外松手后不再一直半透明，拖动中的重排也会写入配置。
- 合成预览的冲突列表在同一域名出现多处冲突时不再出现重复 ID；语法高亮改用 UTF-16 偏移，行内含 emoji 时颜色不再错位；切换默认节点不再触发一次无意义的写入。
- 写入成功但 DNS 未确认刷新时，系统通知改为「hosts 已写入，但有警告」，不再显示成「hosts 应用失败」（仍受「写入失败时通知」开关控制）。
- 写入更保守：Helper 只接受 `/private/etc/hosts`，非强制写入必须带当前文件 hash，超过 1 MB 的内容会被拒绝。外部修改不再靠错误文案识别。启动时会标出「还没写入」或「外面改过」。XPC 超时但磁盘已经是本次内容时按成功记，并提示 DNS 可能没刷新。合并进系统文件时保留注释和空行。自动备份默认保留 20 份。
- 修复编辑器可用性：节点行里的按钮会抢走点击导致无法选中；删除当前节点或分组后编辑区仍显示已删除内容；切换节点时错误行号会短暂标在新内容上；搜索状态下拖动分组会按过滤后的下标打乱真实顺序。导入导出前若有未应用修改会先询问，替换结果不再误报成「新增分组」，导入确认和结果提示不再互相吃掉。macOS 列表行上的点击手势不会触发选中，名称区域改为按钮，打开编辑器时直接进入默认节点；节点重命名改到右键菜单。打开节点时调整文本滚动会重入布局并触发独占访问崩溃，同步布局期间忽略这次重入。
- 修复 `XPCHostHelperClient` 成功收到 XPC reply 后 timeout task 仍会继续记录假超时并断开连接的问题；重复完成同一 request 现在会被忽略。
- 修复编辑器「放弃」按钮使用 ⌘Z 与 macOS 标准撤销快捷键冲突的问题，长时间编辑后按 ⌘Z 可能整体丢弃草稿；改为 ⇧⌘Z，并在 tooltip 中提示快捷键。
- 修复 `HelperService` 未严格校验 `localizationIdentifier` 的问题：未知值或 `"system"` 时记录 warning 并显式回退到 `zh-Hans`，防止英语用户看到中文错误文案。
- 修复切换界面语言后菜单栏操作标题需等待鼠标悬停才更新的问题；菜单内容现在观察语言偏好并立即重建原生菜单项。
- 修复国际化资源未接入 SwiftPM 和生成的 Xcode 工程导致项目无法构建、本地化 key 无法加载的问题。
- 修复国际化迁移中错误复用文案导致的状态、字符数、冲突操作与分组删除风险提示失真问题。
- 修复 Helper/XPC 错误信息未走本地化资源，以及本地化日志直接传入 `Logger` 导致的编译错误。
- 修复 `HostsFileWriter` 仅在操作开始时校验 hash 的竞态窗口；在原子替换前再次比对目标文件，并补充并发修改回归测试。
- 修复 Xcode scheme 配置中测试 target 关联问题。
- 修复 `HostsTextView` 的 SwiftUI 更新标记访问权限问题，确保 `updateNSView` 能正确同步外部文本变化。
- 修复编辑器行号与标题栏样式不一致的问题，统一视觉层级。
- 修复 Xcode App target 构建失败问题，`HostsTextView` 的 SwiftUI 更新标记不再被错误声明为 `private`。
- 修复 Privileged Helper/App XPC 签名校验过宽的问题，改为包含 `anchor apple generic`、bundle identifier 和 Team ID 的完整 requirement。
- 修复 XPC reply 丢失、连接中断或超时时可能永久挂起的问题，现在 pending reply 会在错误、取消、超时或连接失效时收敛。
- 修复写入前备份失败仍继续覆盖 hosts 的问题，现在备份失败会阻止真实写入。
- 修复强制覆盖失败后会清空持久化 hash、削弱后续外部修改保护的问题，现在强制写入使用一次性参数。
- 修复 hosts 写入内容未强制包含系统默认条目的问题，Helper 写入前会校验 `localhost` 与 `broadcasthost` 默认条目。
- 修复备份读取和手动备份未复用 Latin-1 fallback 的问题。
- 修复配置损坏或未来版本恢复默认时未保留原始配置文件的问题。
- 修复外部修改确认弹窗只挂在编辑器窗口的问题，现在菜单栏、合成预览和备份窗口入口也能处理外部修改。
- 修复 `HostsParser` 对纯注释/空行内容误报 `emptyContent` 错误的问题，现在返回空记录数组。
- 修复 `HostsMergerTests` 中重复的测试方法名 `testDefaultNodeAlwaysParticipatesAndDuplicateEntriesAreCollapsed`。
- 修复 `HostWriteCoordinator` 写入失败后的状态隔离问题，写入失败时草稿保留在 UI 层，hosts 保持未应用状态。
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
- 修复从备份恢复失败时可能提前替换并持久化当前配置的问题，现在恢复写入成功前不会替换当前草稿。
- 修复 DEBUG 构建未使用 `PreviewHostHelperClient` 的问题，开发调试不再要求安装 Privileged Helper。
- 修复旧 `isSingleSelect` 配置继续影响节点激活的问题，加载后统一规范化为多选行为。
- 修复连续调度 apply 时旧任务可能覆盖最新 `isApplying` 状态的问题。

### Documentation

- 更新 `docs/hostcat-design.md`：撤销快捷键改为 ⇧⌘Z、`HostWriteCoordinator` 失败语义、Helper 语言标识严格校验，并将最后更新日期推进至 2026-06-08。
- 补充开发方案设计，明确 XPC 安全边界、状态快照、写入安全策略、测试策略和构建分发策略。
- 新增 README、CHANGELOG 和 AGENTS 协作文档。
- 更新 README，补充 `HostsImporter` 能力和阶段1当前进度。
- 更新 TODO.md，标记阶段 1 和阶段 2 全部完成。
- 更新 AGENTS.md，同步项目状态为阶段 2 完成。
- 删除已移除的 `docs/ihosts-research.md` 文件引用，清理文档中的死链接。

### Refactored

- 简化 `HostWriteCoordinator` 接口：`scheduleApply` / `applyImmediately` / `performWrite` 返回 `ApplyResult` 而非 `(ApplyResult, AppConfig?)` 元组；`lastSuccessfulConfigSnapshot` 保留为 actor 内部状态供服务层使用，不再作为 UI 回滚指令通过 API 返回，与 2026-05-27 设计调整后的"保留草稿"语义对齐。
- 将 `EditorView` 中原有的标准 `TextEditor` 替换为自定义的 `HostsTextView` 桥接组件，极大改善了 hosts 编辑体验。
- 重构 `HostsSyntaxHighlighter` 为 `@MainActor` 并使用主 Actor 级别的 static 属性，完美符合 Swift 6 Strict Concurrency 严格并发安全校验。
- 拆分 `EditorView.swift`（747→362 行）为 `EditorView`、`SidebarComponents`、`NameInputDialog`、`NodeReorderDropDelegate` 四个文件。
- 拆分 `HostCatApp.swift`（230→79 行）为 `HostCatApp`、`MenuBarContentView`、`WindowFocus` 三个文件。
- 从 SwiftPM 骨架迁移到 Xcode 工程（project.yml → HostCat.xcodeproj），保留 Package.swift 用于核心测试。
- 统一核心测试替身到 `TestDoubles.swift`，将 `FakeFileSystemOperations` 和 `StubDNSRefresher` 移出生产/单测局部定义。

### Not Yet Implemented

- 语法高亮和冲突解决 UI（冲突定位按钮当前仅显示提示）。
- GitHub Release CI/CD 发布流水线。
- 自动更新 (Sparkle)。
- iCloud 同步。
- 全局快捷键打开菜单栏。
- 搜索/过滤节点和域名。
- 完整多语言覆盖。
