# systemPatterns.md

## 架构总览

```text
┌──────────────────────────────────────────────────────────────┐
│                    HostCatApp (@main)                         │
│                    SwiftUI macOS app                          │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  MenuBarExtra(.menu) │ Settings │ Window(editor/...) │    │
│  └────────┬─────────────┴─────┬────┴───────┬────────────┘    │
│           │                   │            │                  │
│  ┌────────▼──────────┐  ┌─────▼──────────┐ │                  │
│  │ MenuBarViewModel  │  │ SettingsView   │ │                  │
│  │ (@MainActor)      │  │ (Helper 注册)  │ │                  │
│  └────────┬──────────┘  └────────────────┘ │                  │
│           │                                 │                  │
│           ▼                                 ▼                  │
│  ┌──────────────────────────────────────────────────────┐    │
│  │              HostCatCore (pure Swift)                 │    │
│  │  Models / Parser / Merger / Importer / Hash /         │    │
│  │  ConfigStore / ConfigMutationService /                │    │
│  │  HostWriteCoordinator (actor) / BackupStore /         │    │
│  │  HostsFileWriter / DNSRefresher / AppLanguage /       │    │
│  │  ExternalModificationDetector                         │    │
│  └──────────────────┬────────────────────────────────────┘    │
│                     │ HostHelperClient protocol               │
│                     ▼                                         │
│  ┌──────────────────────────────────────────────────────┐    │
│  │              HostCatHelperClient                     │    │
│  │  XPCHostHelperClient (NSXPCConnection wrap)          │    │
│  │  HelperRegistrationManager (SMAppService)            │    │
│  └──────────────────┬────────────────────────────────────┘    │
└────────────────────┼─────────────────────────────────────────┘
                     │ XPC (NSXPCConnection)
                     │ 双向 code signing requirement 验证
                     ▼
┌──────────────────────────────────────────────────────────────┐
│           HostCatPrivilegedHelper (root LaunchDaemon)         │
│  HelperDelegate ─ HelperService ─ HostsFileWriter            │
│  仅写固定 /private/etc/hosts                                  │
│  仅执行固定 DNS 刷新命令                                       │
└──────────────────────────────────────────────────────────────┘
```

## 目录约定

```text
Sources/
├── HostCatApp/                    # SwiftUI UI 层（@MainActor）
│   ├── HostCatApp.swift           # @main 入口、Scene 定义、SettingsView
│   ├── MenuBarContentView.swift   # 菜单栏下拉
│   ├── EditorView.swift           # 编辑器主视图
│   ├── HostsTextView.swift        # NSTextView 桥接 (NSViewRepresentable)
│   ├── HostsSyntaxHighlighter.swift  # TextKit 2 高亮引擎
│   ├── LineNumberRulerView.swift  # 自定义行号栏 (NSRulerView)
│   ├── MergedPreviewView.swift    # 合成预览窗口
│   ├── BackupRestoreView.swift    # 备份恢复窗口
│   ├── ExternalModificationAlert.swift  # 外部修改弹窗
│   ├── GlobalShortcuts.swift      # `ShortcutStore` 持久化 + `MenuBarStatusItemOpener` 弹菜单
│   ├── Shortcut.swift             # 值类型：keyCode + Carbon modifier + UCKeyTranslate 翻译
│   ├── CarbonHotKeyMonitor.swift  # Carbon `RegisterEventHotKey` 全局监听
│   ├── ShortcutRecorderView.swift # NSViewRepresentable 快捷键录制框
│   ├── Localization.swift         # UI 本地化字符串入口
│   └── Resources/
│       ├── zh-Hans.lproj/Localizable.strings
│       ├── en.lproj/Localizable.strings
│       ├── Assets.xcassets/
│       ├── Info.plist
│       └── HostCatApp.entitlements
│
├── HostCatCore/                   # 纯 Swift 业务核心（无 SwiftUI/AppKit/SM 依赖）
│   ├── Models.swift               # AppConfig / HostGroup / HostNode / ...
│   ├── HostsParser.swift          # parse + validate (non-throwing)
│   ├── HostsMerger.swift          # 合并 + 去重 + 冲突检测
│   ├── HostsImporter.swift        # HostCat 区块解析 + Latin-1 fallback
│   ├── HostsHash.swift            # SHA256
│   ├── HostsFileWriter.swift      # 安全写入实现 + FileSystemOperations 协议
│   ├── HostsContentValidator      # 写入前内容校验（区块 + 必备条目）
│   ├── HostWriteCoordinator.swift # actor: debounce + 失败保留草稿
│   ├── BackupStore.swift          # 备份 + 保留策略
│   ├── ExternalModificationDetector.swift
│   ├── AppConfigStore.swift       # JSON 配置读写 + isSingleSelect 规范化
│   ├── ConfigMutationService.swift
│   ├── MenuBarViewModel.swift     # @MainActor ObservableObject
│   ├── AppLanguage.swift          # 三选偏好 + 资源 bundle 解析
│   ├── HostHelperClient.swift     # 协议定义（UI 只依赖此）
│   ├── HostCatCodeSigningRequirements.swift
│   └── Resources/                 # Core 本地化资源（Bundle.module）
│
├── HostCatHelperClient/           # XPC client + Helper 注册
│   ├── XPCHostHelperClient.swift  # NSXPCConnection wrap → async throws
│   └── HelperRegistrationManager.swift
│
└── HostCatPrivilegedHelper/       # root LaunchDaemon
    ├── HostCatPrivilegedHelperMain.swift  # @main
    ├── HelperDelegate.swift               # NSXPCListenerDelegate
    ├── HelperService.swift                # XPC 服务实现
    ├── Info.plist
    └── com.hostcat.helper.plist           # launchd plist
```

## 前端设计模式

- **SwiftUI 为主**：`MenuBarExtra(.menu)`、`Window`、`Settings` scene；弹窗用 `.alert()`。
- **AppKit 桥接最小化**：仅 hosts 编辑器（语法高亮、行号、错误标记）通过 `NSViewRepresentable` 接入 `NSTextView` + TextKit 2。
- **@MainActor 严格执行**：所有 UI 层类型标注 `@MainActor`；`HostsSyntaxHighlighter` 整体为 `@MainActor` 以兼容 Swift 6 strict concurrency。
- **菜单刷新机制**：`MenuBarExtra(.menu)` 通过 `.id(storedLanguage)` 强制重建菜单项，避免语言切换后等悬停才刷新。
- **撤销快捷键**：编辑器「放弃」按钮使用 ⇧⌘Z，避让 macOS 标准 ⌘Z 单步撤销。

## 后端设计模式

### 权限模型
- `SMAppService.daemon` 注册 Privileged Helper（macOS 13+ 推荐方案，替代废弃的 `SMJobBless`）。
- Helper plist 必须在 `Contents/Library/LaunchDaemons/`；Helper 可执行文件必须在 `Contents/Library/HelperTools/`（XcodeGen 通过 postBuildScripts 拷贝）。
- 首次注册引导用户到「系统设置 → 登录项」批准。

### XPC 安全边界
- 双向 `setCodeSigningRequirement(_:)`：主应用要求 Helper 签名，Helper 要求调用方签名。
- requirement 字符串必须包含 `anchor apple generic` + 固定 bundle id + Team ID。
- Team ID 通过 Info.plist `HostCatTeamIdentifier` 注入，发布脚本要求显式 `DEVELOPMENT_TEAM`。
- 只传稳定桥接类型：`String` / `Data` / `Bool` / `NSDictionary`；不传 Swift Codable struct。
- Helper 接受的参数仅：`contents`（写入文本）+ `expectedCurrentHostsHash`（hash 校验）+ `localizationIdentifier`（错误文案语言）。

### 安全写入策略（HostsFileWriter）
1. immutable flags 检查（`schg` / `uchg`），拒绝写入但不自动清除
2. **hash 一次校验**：读取当前 hosts，与 `expectedCurrentHostsHash` 比对
3. 内容校验：非空 + HostCat 区块标记完整 + 必备系统条目（127.0.0.1 localhost 等）
4. mkstemp 创建唯一临时文件（不固定文件名，防符号链接攻击）
5. write + fsync + chmod 644 + chown root:wheel
6. **hash 二次校验**：rename 前再读一次目标文件，与第 2 步对比；即使 force=true 也不覆盖期间发生的新修改
7. `rename(2)` 原子替换 + 父目录 fsync
8. DNS 刷新（失败不回滚 hosts）
9. defer 清理未使用的临时文件

### 并发模型
- `HostWriteCoordinator` actor 串行处理写入。
- 写入开始后，后续用户操作只更新待写入快照，不修改正在进行的批次。
- debounce 500ms：连续点击合并为一次最终写入；中间状态全部丢弃。
- 失败保留草稿：UI 在 apply 前已经持久化草稿（`persistDraftConfig`），失败仅记录日志 + 提示 hosts 未应用，不回滚 UI。

## 数据模式

- **配置存储**：JSON，路径 `~/Library/Application Support/com.hostcat.app/config.json`。
- **`configVersion`**：首版为 `1`；变更需走迁移入口。
- **原子写入**：临时文件 + rename；JSON 损坏时保留原配置（preserved 副本）+ 恢复默认。
- **协议注入**：所有文件系统操作通过 `FileSystemOperations` 协议；`RealFileSystemOperations` + `FakeFileSystemOperations` 双实现，让 [[techContext]] 中的测试不依赖真实 root 权限。
- **`isSingleSelect` 规范化**：旧配置加载时 `AppConfigStore.normalizedForCurrentRules` 强制 `isSingleSelect=false`，统一多选。

## 测试模式

- 测试替身集中放在 `Tests/HostCatCoreTests/TestDoubles.swift`：
  - `FakeHostHelperClient`（actor + delay/shouldSucceed/simulatedError 三段可控）
  - `FakeFileSystemOperations`（支持 `setReadSequence` 模拟多次读不同内容）
  - `StubDNSRefresher`
- **测试金字塔三层**：
  1. 纯函数单元测试（parser/merger/hash/importer）
  2. actor/状态单元测试（coordinator/mutation/menu vm）
  3. 协议注入测试（FileSystemOperations 注入到 HostsFileWriter）
- 真实 `/private/etc/hosts` 写入：仅签名后的本机 smoke test，不入 CI。

## 负向约束（❌ 不要做）

- ❌ Helper 接受任意路径或任意 shell 命令
- ❌ XPC 传 Swift Codable struct
- ❌ 真实测试写 `/etc/hosts`
- ❌ 在 UI view 里写业务规则（必须通过 ViewModel/Service 委托）
- ❌ 在 `HostCatCore` 里引入 SwiftUI / AppKit / ServiceManagement
- ❌ 启用 App Sandbox（与 LaunchDaemon 方案冲突，发布版关闭）
- ❌ Universal Binary（仅 arm64）
- ❌ 引入新第三方依赖（除非设计文档明确）
- ❌ `git add -A`（避免误提交 .env / 临时文件）
- ❌ 跨分组拖拽排序（产品决策已砍）
- ❌ 写入失败时回滚 UI 草稿（2026-05-27 设计调整，参见 [[productContext]] 失败语义）
- ❌ 编辑器撤销按钮用 ⌘Z 单键（与 macOS 标准撤销冲突，已改 ⇧⌘Z）
- ❌ 从 `HostWriteCoordinator` API 返回 `rolledBackConfig`（2026-06-08 移除，仅保留 actor 内部 `lastSuccessfulConfigSnapshot`）
- ❌ 在 commit message 加 `Generated with` 或 `Co-Authored-By`
- ❌ 跳过 pre-commit hook（`--no-verify`）
