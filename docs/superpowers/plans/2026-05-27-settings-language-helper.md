# Settings Language and Helper Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将语言即时切换与 Privileged Helper 管理集中到唯一可访问的设置页中。

**Architecture:** `HostCatCore` 新增不依赖 UI 的 `AppLanguage` 偏好及 bundle 解析逻辑，通过 `UserDefaults` 共享所选语言；Core 与 App 的字符串包装器在每次读取时按该偏好解析资源。`HostCatApp` 观察该偏好并注入 `Locale`，设置页写入选择值，菜单栏提供唯一的设置入口并移除独立 Helper 窗口。

**Tech Stack:** Swift 6、SwiftUI、Foundation `Bundle` / `UserDefaults`、XCTest、XcodeGen

---

## 执行说明

当前工作树已有通过验证但尚未提交的国际化与写入安全修复，且与本计划会修改的本地化文件重叠。执行期间仅维护本计划清单与验证证据，不在中途提交重叠文件，避免将已有修复以不完整的方式拆入功能提交。

代码核查补充了一项规格隐含要求：`HostCat` 是 `LSUIElement` 菜单栏应用，当前菜单中没有打开 `Settings` scene 的入口。移除 `helper-setup` 入口时必须新增 `SettingsLink`，否则设置页及新的语言功能将无法可靠访问。

## 文件映射

- Create: `Sources/HostCatCore/AppLanguage.swift` - 保存/读取 UI 语言偏好，计算有效本地化资源和 `Locale`。
- Create: `Tests/HostCatCoreTests/AppLanguageTests.swift` - 覆盖持久化、系统语言匹配、资源切换。
- Modify: `Sources/HostCatCore/LocalizationCore.swift` - 将 Core 字符串改为按当前偏好动态解析。
- Modify: `Sources/HostCatCore/HostsWriteError.swift` - 允许 Helper 按请求携带的语言标识格式化写入错误。
- Modify: `Sources/HostCatCore/HostHelperClient.swift` - XPC 写入接口携带只用于展示的资源语言标识。
- Modify: `Sources/HostCatHelperClient/XPCHostHelperClient.swift` - 从主应用偏好解析语言标识并随请求发送。
- Modify: `Sources/HostCatPrivilegedHelper/HelperService.swift` - 使用请求语言格式化 Helper 错误响应。
- Modify: `Sources/HostCatApp/Localization.swift` - 将 App 字符串改为按当前偏好动态解析，并新增设置页语言标签。
- Modify: `Sources/HostCatApp/HostCatApp.swift` - 根语言状态、环境 locale、设置页 Picker、移除 Helper 窗口。
- Modify: `Sources/HostCatApp/MenuBarContentView.swift` - 删除 Helper 入口，添加可访问的 `SettingsLink`。
- Delete: `Sources/HostCatApp/HelperSetupView.swift` - 删除不再可达的重复流程界面。
- Modify: `Sources/HostCatApp/Resources/en.lproj/Localizable.strings` - 英文语言设置文案。
- Modify: `Sources/HostCatApp/Resources/zh-Hans.lproj/Localizable.strings` - 中文语言设置文案。
- Modify: `README.md`, `CHANGELOG.md`, `TODO.md`, `docs/hostcat-design.md` - 用户能力、变更记录、进度与设计决策。
- Regenerate: `HostCat.xcodeproj/project.pbxproj` - 删除源文件后由 `xcodegen generate` 同步工程。

### Task 1: Core 语言偏好与资源解析

**Files:**
- Create: `Tests/HostCatCoreTests/AppLanguageTests.swift`
- Create: `Sources/HostCatCore/AppLanguage.swift`
- Modify: `Sources/HostCatCore/LocalizationCore.swift`

- [x] **Step 1: 写入失败测试**

新增以下测试，先规定偏好不进入 `AppConfig`、显式语言立即覆盖系统语言、`system` 遵循支持的系统语言并回退到默认中文，以及 Core 文案可在同一进程中切换资源：

```swift
import Foundation
import XCTest
@testable import HostCatCore

final class AppLanguageTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppLanguageTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStoredPreferenceDefaultsToSystemAndRoundTrips() {
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
        AppLanguage.english.store(in: defaults)
        XCTAssertEqual(AppLanguage.stored(in: defaults), .english)
        defaults.set("unsupported", forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
    }

    func testEffectiveLocalizationUsesExplicitSelectionOrSupportedSystemLanguage() {
        XCTAssertEqual(AppLanguage.english.effectiveLocalizationIdentifier(preferredLanguages: ["zh-Hans"]), "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.effectiveLocalizationIdentifier(preferredLanguages: ["en-US"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.effectiveLocalizationIdentifier(preferredLanguages: ["en-US"]), "en")
        XCTAssertEqual(AppLanguage.system.effectiveLocalizationIdentifier(preferredLanguages: ["zh-Hans-CN"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.effectiveLocalizationIdentifier(preferredLanguages: ["fr-FR"]), "zh-Hans")
    }

    func testCoreLocalizationResolvesNewTextUsingStoredLanguageWithoutRestart() {
        AppLanguage.english.store(in: defaults)
        XCTAssertEqual(LC.localizedString("helper.status.enabled", userDefaults: defaults), "Enabled")

        AppLanguage.simplifiedChinese.store(in: defaults)
        XCTAssertEqual(LC.localizedString("helper.status.enabled", userDefaults: defaults), "已启用")
    }
}
```

- [x] **Step 2: 运行测试并确认 RED**

Run: `swift test --filter AppLanguageTests`

Expected: 编译失败，提示找不到 `AppLanguage` 或 `LC.localizedString`，证明测试正在要求尚未存在的能力。

- [x] **Step 3: 实现最小 Core API**

创建 `AppLanguage.swift`，核心接口如下；`localizedBundle` 供 Core 和 App 共享相同的资源选择规则：

```swift
import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public static let preferenceKey = "HostCat.appLanguage"
    private static let defaultLocalizationIdentifier = "zh-Hans"

    public static func stored(in userDefaults: UserDefaults = .standard) -> AppLanguage {
        guard let rawValue = userDefaults.string(forKey: preferenceKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }
        return language
    }

    public func store(in userDefaults: UserDefaults = .standard) {
        userDefaults.set(rawValue, forKey: Self.preferenceKey)
    }

    public func effectiveLocalizationIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        case .system:
            for identifier in preferredLanguages.map({ $0.replacingOccurrences(of: "_", with: "-").lowercased() }) {
                if identifier == "en" || identifier.hasPrefix("en-") { return "en" }
                if identifier == "zh" || identifier == "zh-hans" || identifier.hasPrefix("zh-hans-")
                    || identifier == "zh-cn" || identifier.hasPrefix("zh-cn-")
                    || identifier == "zh-sg" || identifier.hasPrefix("zh-sg-") {
                    return "zh-Hans"
                }
            }
            return Self.defaultLocalizationIdentifier
        }
    }

    public var locale: Locale {
        Locale(identifier: effectiveLocalizationIdentifier())
    }

    public func localizedBundle(in baseBundle: Bundle, preferredLanguages: [String] = Locale.preferredLanguages) -> Bundle {
        let identifier = effectiveLocalizationIdentifier(preferredLanguages: preferredLanguages)
        guard let url = baseBundle.url(forResource: identifier, withExtension: "lproj"),
              let bundle = Bundle(url: url) else {
            return baseBundle
        }
        return bundle
    }
}
```

在 `LocalizationCore.swift` 增加可测试解析入口，并将本地化的 `public static let` 改为 computed `public static var`：

```swift
static func localizedString(
    _ key: String,
    userDefaults: UserDefaults = .standard,
    preferredLanguages: [String] = Locale.preferredLanguages
) -> String {
    let language = AppLanguage.stored(in: userDefaults)
    let bundle = language.localizedBundle(in: resourceBundle, preferredLanguages: preferredLanguages)
    return bundle.localizedString(forKey: key, value: key, table: "LocalizableCore")
}

private static var resourceBundle: Bundle {
    #if SWIFT_PACKAGE
    Bundle.module
    #else
    Bundle(for: HostCatCoreBundleToken.self)
    #endif
}

private static func localize(_ key: String) -> String {
    localizedString(key)
}
```

- [x] **Step 4: 运行测试并确认 GREEN**

Run: `swift test --filter AppLanguageTests`

Expected: `AppLanguageTests` 全部通过。

### Task 2: App 运行时语言绑定与设置控件

**Files:**
- Modify: `Sources/HostCatApp/Localization.swift`
- Modify: `Sources/HostCatApp/HostCatApp.swift`
- Modify: `Sources/HostCatApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/HostCatApp/Resources/zh-Hans.lproj/Localizable.strings`

- [x] **Step 1: 添加设置文案**

在两份 App 字符串表新增下列键：

```text
/* en */
"settings.language" = "Language";
"settings.language.system" = "Follow System";
"settings.language.simplified_chinese" = "简体中文";
"settings.language.english" = "English";

/* zh-Hans */
"settings.language" = "语言";
"settings.language.system" = "跟随系统";
"settings.language.simplified_chinese" = "简体中文";
"settings.language.english" = "English";
```

- [x] **Step 2: 将 App 字符串解析改为动态读取**

`Localization.swift` 引入 `HostCatCore`，将所有 `static let ... = localize(...)` 改为 computed `static var ...: String { localize(...) }`，并添加：

```swift
static var settingsLanguage: String { localize("settings.language") }
static var languageSystem: String { localize("settings.language.system") }
static var languageSimplifiedChinese: String { localize("settings.language.simplified_chinese") }
static var languageEnglish: String { localize("settings.language.english") }

private static func localize(_ key: String) -> String {
    let bundle = AppLanguage.stored().localizedBundle(in: .main)
    return bundle.localizedString(forKey: key, value: key, table: "Localizable")
}
```

- [x] **Step 3: 在设置页接入 Picker 和根环境刷新**

在 `HostCatApplication` 中使用 `@AppStorage(AppLanguage.preferenceKey)` 持有偏好，并把有效 locale 注入各场景内容：

```swift
@AppStorage(AppLanguage.preferenceKey) private var storedLanguage = AppLanguage.system.rawValue

private var appLanguage: AppLanguage {
    AppLanguage(rawValue: storedLanguage) ?? .system
}

private var appLanguageBinding: Binding<AppLanguage> {
    Binding(
        get: { appLanguage },
        set: { storedLanguage = $0.rawValue }
    )
}
```

向 `SettingsView` 传入 `preferredLanguage: appLanguageBinding`，并在 General section 中增加：

```swift
Picker(L.settingsLanguage, selection: $preferredLanguage) {
    Text(L.languageSystem).tag(AppLanguage.system)
    Text(L.languageSimplifiedChinese).tag(AppLanguage.simplifiedChinese)
    Text(L.languageEnglish).tag(AppLanguage.english)
}
```

所有窗口根 view 与菜单内容应用 `.environment(\.locale, appLanguage.locale)`；语言偏好改变会重算 `L` computed properties 并刷新界面。

- [x] **Step 4: 检查 App 接线差异**

Run: `rg -n 'AppLanguage|settingsLanguage|languageSystem|environment\\(\\\\.locale' Sources/HostCatApp`

Expected: `Localization.swift` 中存在动态语言标签和解析，`HostCatApp.swift` 中存在持久化绑定、Picker 及 locale 注入；编译验证在工程同步后的 Task 4 统一进行。

### Task 3: 收敛 Helper 到唯一可达设置入口

**Files:**
- Modify: `Sources/HostCatApp/MenuBarContentView.swift`
- Modify: `Sources/HostCatApp/HostCatApp.swift`
- Delete: `Sources/HostCatApp/HelperSetupView.swift`

- [x] **Step 1: 将菜单入口改为设置入口**

在备份操作后删除 `openAppWindow(id: "helper-setup", ...)`，改用 SwiftUI 设置入口：

```swift
SettingsLink {
    Text(L.settingsTitle)
}
```

- [x] **Step 2: 移除重复窗口与页面**

从 `HostCatApp.swift` 删除：

```swift
Window(L.helperTitle, id: "helper-setup") {
    HelperSetupView(registrationManager: registrationManager)
}
.defaultSize(width: 400, height: 350)
```

删除 `Sources/HostCatApp/HelperSetupView.swift`，避免维护无入口的重复 Helper 交互实现。

- [x] **Step 3: 静态验证不存在旧入口**

Run: `rg -n 'HelperSetupView|helper-setup|openAppWindow\\(id: "helper-setup"' Sources/HostCatApp`

Expected: 无匹配结果。

### Task 3B: 跨进程 Helper 错误语言传递

**Files:**
- Modify: `Tests/HostCatCoreTests/AppLanguageTests.swift`
- Modify: `Sources/HostCatCore/LocalizationCore.swift`
- Modify: `Sources/HostCatCore/HostsWriteError.swift`
- Modify: `Sources/HostCatCore/HostHelperClient.swift`
- Modify: `Sources/HostCatHelperClient/XPCHostHelperClient.swift`
- Modify: `Sources/HostCatPrivilegedHelper/HelperService.swift`

主应用和 Privileged Helper 的 `UserDefaults.standard` 属于不同进程/domain，Helper 不能直接读到设置页偏好。XPC 仅追加已经解析出的 `en`/`zh-Hans` 展示参数，不改变写入内容、目标路径、hash 校验或权限判定。

- [x] **Step 1: 写入显式 Helper 错误语言测试并确认 RED**

```swift
func testWriteErrorCanBeFormattedUsingRequestLanguage() {
    XCTAssertEqual(
        HostsWriteError.hashMismatch.description(in: .english),
        "The hosts file has been modified outside of HostCat."
    )
    XCTAssertEqual(
        HostsWriteError.hashMismatch.description(in: .simplifiedChinese),
        "hosts 文件已在 HostCat 之外被修改。"
    )
}
```

Run: `swift test --filter AppLanguageTests/testWriteErrorCanBeFormattedUsingRequestLanguage`

Expected: 编译失败，提示 `HostsWriteError` 尚无 `description(in:)`。

- [x] **Step 2: 实现显式资源解析和错误格式化**

`LC` 增加基于 `AppLanguage` 的解析重载，`HostsWriteError.errorDescription` 继续供主应用使用当前偏好，新增方法供 Helper 使用请求语言：

```swift
public func description(in language: AppLanguage) -> String {
    switch self {
    case .hashMismatch:
        return LC.localizedString("write.error.hash_mismatch", language: language)
    // 其他 case 按现有 key 和 detail 使用同一语言格式化。
    }
}
```

- [x] **Step 3: 将有效语言标识随 XPC 请求传递**

将 Objective-C XPC 方法追加稳定桥接参数 `localizationIdentifier: NSString`。`XPCHostHelperClient` 传递：

```swift
let localizationIdentifier = AppLanguage.stored().effectiveLocalizationIdentifier() as NSString
proxy.writeHosts(
    contentsNS,
    expectedCurrentHostsHash: hashNS,
    localizationIdentifier: localizationIdentifier
) { resultDict in
    // 现有 reply 解析保持不变。
}
```

`HelperService` 仅将参数用于格式化错误：

```swift
let language = AppLanguage(rawValue: localizationIdentifier as String) ?? .simplifiedChinese
let message = (error as? HostsWriteError)?.description(in: language) ?? error.localizedDescription
```

- [x] **Step 4: 确认 GREEN 与安全边界**

Run: `swift test --filter AppLanguageTests`

Expected: 语言偏好和显式 Helper 错误格式测试均通过。

Run: `rg -n 'localizationIdentifier|writeHosts\\(' Sources/HostCatCore Sources/HostCatHelperClient Sources/HostCatPrivilegedHelper`

Expected: 新参数仅在 XPC 声明、client 发送和 Helper 错误格式化路径中出现，不参与写入校验或目标路径。

### Task 4: 文档、工程生成与完整验证

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `TODO.md`
- Modify: `docs/hostcat-design.md`
- Regenerate: `HostCat.xcodeproj/project.pbxproj`

- [x] **Step 1: 更新用户与设计文档**

记录以下事实：

```text
README: 设置页支持即时语言切换，并作为 Helper 管理唯一入口；移除 HelperSetupView 文件树说明。
CHANGELOG/未发布: 新增三态语言选择与即时切换，设置页统一承载 Helper 管理。
TODO: 标记运行时语言选择与设置页整合完成。
docs/hostcat-design.md: 记录语言偏好保存在 UserDefaults、App/Core 动态解析资源、SettingsLink 为菜单栏唯一入口。
```

- [x] **Step 2: 同步 Xcode 工程**

Run: `xcodegen generate`

Expected: 工程重新生成，包含 `AppLanguage.swift` 和 `AppLanguageTests.swift`，不再引用 `HelperSetupView.swift`。

- [x] **Step 3: 检查 strings 与差异格式**

Run: `plutil -lint Sources/HostCatApp/Resources/en.lproj/Localizable.strings Sources/HostCatApp/Resources/zh-Hans.lproj/Localizable.strings Sources/HostCatCore/Resources/en.lproj/LocalizableCore.strings Sources/HostCatCore/Resources/zh-Hans.lproj/LocalizableCore.strings`

Expected: 四个资源文件均报告 `OK`。

Run: `git diff --check`

Expected: 退出码为 `0`，没有空白错误。

- [x] **Step 4: 完整测试与构建**

Run: `swift test`

Expected: 所有 `HostCatCoreTests` 通过，包括新增 `AppLanguageTests`。

Run: `swift build`

Expected: SwiftPM 构建成功。

Run: `xcodebuild build -project HostCat.xcodeproj -scheme HostCatApp -destination 'platform=macOS,arch=arm64' -quiet`

Expected: App、Core、HelperClient 与 Privileged Helper 目标构建成功。
