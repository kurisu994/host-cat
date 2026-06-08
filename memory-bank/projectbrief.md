# projectbrief.md

## 项目愿景

HostCat 是一款 **Apple Silicon 原生** 的 macOS 菜单栏 hosts 管理应用。核心定位是「菜单栏驱动的 hosts 配置切换器」，让开发者一次授权后即可在多套环境配置间无缝切换，不再频繁手动编辑 `/etc/hosts`。

## 范围

### 已完成
- **阶段 1（安全预览版）**：核心模型、编辑体验、合成规则、冲突检测、备份模块预研。
- **阶段 2（真实写入版）**：`SMAppService` + Privileged Helper、安全写入、备份恢复、DNS 刷新、外部修改检测、签名/公证/DMG 打包。
- **阶段 2 后续**：i18n（中英双语 + 运行时切换）、设置页整合 Helper 管理、hosts 编辑器（TextKit 2 语法高亮 + 多行错误收集）、hash 二次校验。

### 进行中
- **阶段 3（上线准备）**：版本管理、Sparkle 自动更新、GitHub Actions CI/CD、全局快捷键、搜索/过滤、配置导入导出、通知中心、可访问性、隐私政策。

### 已砍
- 跨分组拖拽排序（产品决策）。
- Mac App Store 版本（与 LaunchDaemon 方案不兼容）。
- Universal Binary（仅 arm64）。

## 交付物

- **签名 + 公证的 DMG**，通过 GitHub Release 直接分发；不上 App Store。
- **应用名称**：HostCat（"Host" 点题 + "Cat" 双关：Unix `cat` 命令 + 猫咪品牌形象）。
- **Bundle IDs**：
  - 主应用：`com.hostcat.app`
  - Helper：`com.hostcat.helper`
  - Core framework：`com.hostcat.core`
  - HelperClient framework：`com.hostcat.helper-client`

## 目标用户

- macOS 14+ Apple Silicon 开发者
- 需要在多个域名解析环境间切换（多环境测试、本地开发指向、绕过 CDN/DNS 缓存）
- 不希望每次都 `sudo vim /etc/hosts`，但又拒绝把 hosts 写入权放给"看似简单"但安全边界模糊的工具

## 关键非功能性约束

- **安全**：Helper 不接受任意路径或任意命令；XPC 双向 code signing 验证；hash 二次校验防止覆盖外部修改。
- **响应性**：菜单栏点击 0 延迟反馈（debounce 500ms 后落盘）。
- **可测试性**：核心业务全部下沉到 [[systemPatterns]] 中描述的 `HostCatCore` 纯 Swift 模块。
- **并发安全**：Swift 6 strict concurrency `complete`；UI `@MainActor`，写入 `actor` 隔离。
