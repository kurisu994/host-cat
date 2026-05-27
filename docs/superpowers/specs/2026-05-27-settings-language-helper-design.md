# 设置页语言切换与 Helper 整合设计

## 背景

HostCat 当前已有 `SettingsView`，其中已提供 Privileged Helper 的状态展示、安装、审批与刷新操作；菜单栏仍另有一个独立的 Helper 安装入口和窗口。应用也已具备中英文资源，但没有用户可配置的运行时语言偏好，本地化读取仍按启动时语言工作。

本设计目标是将语言切换与 Helper 管理统一收敛到设置页，并支持无需重启的界面语言切换。

## 已确认需求

- 设置页是 Helper 管理的唯一入口，不再保留独立的“安装助手”菜单项或窗口。
- 语言选择提供三项：`跟随系统`、`简体中文`、`English`。
- 切换语言后，已打开的应用窗口与菜单内容立即使用所选语言，不要求重启。
- 默认使用 `跟随系统`，避免改变未设置过偏好的现有用户行为。
- 语言偏好是应用 UI 偏好，不进入 hosts 配置、备份或恢复数据。

## 界面设计

继续使用现有 `SettingsView` 作为唯一设置窗口。

### 通用区域

在现有通用设置区域新增语言选择器：

| 选项 | 行为 |
| --- | --- |
| 跟随系统 | 依据 macOS 当前首选语言解析应用资源；不支持的语言按应用默认语言回退 |
| 简体中文 | 立即使用 `zh-Hans` 资源 |
| English | 立即使用 `en` 资源 |

选择发生后，设置窗口本身及应用中仍显示的其他界面一并刷新。

### Privileged Helper 区域

保留当前设置页已有能力：

- 展示 Helper 注册/审批状态。
- 注册或安装 Helper。
- 打开系统审批设置。
- 刷新状态。
- 展示操作失败信息。

删除重复入口：

- 删除菜单栏中打开 Helper 安装引导窗口的操作。
- 删除应用场景中的独立 `helper-setup` 窗口注册。
- 无其他页面负责 Helper 安装流程。

## 状态与数据流

### 语言偏好

新增应用层语言枚举，例如：

```swift
enum AppLanguage: String, CaseIterable {
    case system
    case simplifiedChinese
    case english
}
```

语言偏好使用 `UserDefaults` 持久化。原因如下：

- 其生命周期属于用户界面偏好，而不是 hosts 业务配置。
- 不需要更改 `AppConfig` 编码格式或引入配置迁移。
- 配置导入、备份与恢复不会意外改变界面语言。

根应用场景持有当前偏好并向 SwiftUI 环境注入有效 `Locale`。设置页绑定该状态；选择变化后，依赖语言状态的视图立即重新渲染。

### 本地化解析

App 层现有 `L` API 保持调用形式尽量稳定，但解析改为依据当前语言偏好的动态查找，而不是依赖启动期固定值。对于 `system`，选择与当前系统偏好匹配的资源 bundle；对于显式语言，直接使用对应 `.lproj` 资源。

Core 层不能依赖 SwiftUI。`LC` 在新生成错误和状态文本时从 Foundation 可读取的共享语言偏好解析相应资源。运行前已经实例化为普通 `String` 的历史错误消息不做反向重译；用户再次触发操作或状态刷新时，新的文本使用当前语言。

### Helper 管理

`HelperRegistrationManager` 保持为 UI 到 Helper 注册状态的唯一管理对象。设置页继续调用其现有注册、打开审批设置和刷新接口，不调整：

- XPC 协议。
- code signing requirement。
- `/private/etc/hosts` 写入边界。
- DNS 刷新命令白名单。

## 实现边界

计划修改范围：

- `Sources/HostCatApp/HostCatApp.swift`：根语言状态、设置页语言控件、移除独立 Helper 窗口。
- `Sources/HostCatApp/MenuBarContentView.swift`：移除独立 Helper 入口。
- `Sources/HostCatApp/Localization.swift`：应用层运行时语言解析。
- `Sources/HostCatApp/Resources/*.lproj/Localizable.strings`：设置页新增文案。
- `Sources/HostCatCore/LocalizationCore.swift` 及相应资源：Core 动态语言解析与需要的偏好类型/文案。
- 针对语言偏好、资源解析及回退规则的测试文件。
- 必要的用户文档与未发布变更记录。

不在本次范围：

- 重构 Helper 权限模型或安装协议。
- 将语言偏好写入 hosts 配置模型。
- 引入新第三方依赖。
- 为切换前已经产生的任意历史字符串维护可重译状态模型。

## 测试与验收

### 自动测试

- 语言偏好 raw value、默认值与持久化读取规则测试。
- `system`、`zh-Hans`、`en` 资源选择及未知语言回退测试。
- Core 新产生文本在偏好切换后使用对应资源的测试。

### 手动/构建验证

- 启动应用并打开设置页，确认语言选择器有三项。
- 在应用窗口保持打开的情况下依次选择中文、英文和跟随系统，确认内容立即更新。
- 确认菜单中不再出现独立 Helper 安装入口。
- 确认设置页仍能展示 Helper 状态并触发安装、审批入口与刷新。
- 运行 `git diff --check`、`swift test`、`swift build`。
- 如工程生成配置受变更影响，运行 `xcodegen generate` 和 `xcodebuild build -project HostCat.xcodeproj -scheme HostCatApp -destination 'platform=macOS,arch=arm64'`。

## 风险与取舍

- 即时语言切换要求现有静态本地化文本改为可随状态重新解析，比仅在重启后读取语言的方案改动更大，但符合已确认交互体验。
- 将语言偏好放在 `UserDefaults` 而非 `AppConfig`，保持 hosts 配置数据语义清晰，代价是 App 与 Core 需要约定同一个偏好键。
- Core 已形成的字符串不进行历史翻译，避免为错误展示引入额外状态和复杂映射；新产生的文本与刷新后的状态保持当前语言一致。
