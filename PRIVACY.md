# HostCat 隐私政策 / Privacy Policy

> 最近更新 / Last updated: 2026-06-18

---

## 中文

HostCat 是一款本地运行的菜单栏 hosts 管理应用。我们尊重你的隐私，**不收集、不上传、不分享任何个人数据或使用数据**。本政策说明 HostCat 在你的 Mac 上读写哪些信息、在什么情况下会联网、以及你可以如何控制这些行为。

### 1. 我们不收集什么

HostCat 不内置遥测、不连接分析服务、不接入任何第三方崩溃报告 SDK，也不会在后台读取与 hosts 管理无关的内容。具体说明如下：

- 不收集设备标识符、序列号、MAC 地址、IP 地址或任何形式的设备指纹。
- 不收集账号、邮箱、姓名、地理位置等任何个人身份信息。
- 不收集使用行为：菜单点击、节点切换、编辑操作均仅在本机处理，不会上报。
- 不读取剪贴板、通讯录、日历、相册等系统隐私数据。
- 不在 hosts 文件之外读取其他用户文件。

### 2. 我们在本地处理哪些数据

HostCat 仅在你的 Mac 本地处理以下数据，所有文件都保存在你账户的标准目录下：

- **HostCat 配置**：`~/Library/Application Support/com.hostcat.app/config.json`，包含你创建的分组、节点和激活状态。
- **hosts 备份**：`~/Library/Application Support/com.hostcat.app/backups/`，默认保留最近 3 份；每次真实写入前自动生成。
- **系统 hosts 文件**：`/etc/hosts`（即 `/private/etc/hosts`）。HostCat 通过 Privileged Helper 以 root 权限读写该文件，仅写入你在 HostCat 中编辑的内容和你导入的原始内容。
- **诊断日志（OSLog）**：通过 macOS 系统日志框架记录 HostCat 关键路径（写入、备份、XPC、配置加载），日志只保留在本机系统日志中；只有你在「设置 → 诊断 → 导出诊断日志」主动导出后才会写入指定文件，**HostCat 不会自动上传**。

### 3. 联网行为

当前版本的 HostCat **不主动发起任何网络请求**。未来版本规划接入以下能力，届时会在本政策更新前明确告知：

- **Sparkle 自动更新**（规划中）：联网拉取 `appcast.xml`（HostCat 官方 GitHub Releases 上的更新源）和对应的安装包。请求中仅包含 Sparkle 框架的标准 User-Agent，不携带任何自定义遥测字段。可在设置中关闭自动更新检查。

### 4. Privileged Helper 权限说明

HostCat 通过 `SMAppService` 注册名为 `com.hostcat.helper` 的特权 Helper，用于安全地写入 `/etc/hosts`。Helper 的能力受到严格限制：

- 仅允许写入固定路径 `/private/etc/hosts`，不接受任何路径参数。
- 仅允许执行固定的 DNS 刷新命令 `dscacheutil -flushcache` 和 `killall -HUP mDNSResponder`。
- 写入前校验 immutable flags、HostCat 管理区块标识和最近一次确认的 hosts hash。
- Helper 不连接网络，不执行任意 shell 命令，不接收 UI 状态对象。

### 5. 你的控制项

- **配置数据**：通过编辑器删除节点 / 分组，或直接删除 `~/Library/Application Support/com.hostcat.app/` 目录可清除所有 HostCat 状态。
- **hosts 写入**：始终需要 Helper 注册和系统审批；未注册 Helper 时不会写入 `/etc/hosts`。
- **备份**：可在备份管理窗口手动删除；卸载时一并删除 `backups/` 目录即可彻底清理。
- **诊断日志**：仅在你主动「导出诊断日志」时落盘，导出文件由你完全控制；未导出前 HostCat 不会读取或转发任何日志内容。
- **卸载**：将 HostCat.app 拖入废纸篓，并在系统设置 → 通用 → 登录项中移除 `com.hostcat.helper`，可完整移除 HostCat。配套数据目录见上文。

### 6. 第三方组件

HostCat 当前依赖以下第三方开源组件，均不进行任何远程通信或数据收集：

- [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts)：本机全局快捷键，基于 Carbon Hot Key API，仅在本地注册。

未来如引入其他依赖（如 Sparkle、Sentry 等），会在本政策中明确说明数据范围。

### 7. 联系方式

如对本政策有任何疑问，欢迎在 [HostCat 仓库](https://github.com/) 提交 issue 反馈。

---

## English

HostCat is a local-first menu bar app for managing the macOS hosts file. We respect your privacy and **do not collect, upload, or share any personal data or usage data**. This policy describes which information HostCat reads or writes on your Mac, when it makes network requests, and how you can control these behaviors.

### 1. What we do not collect

HostCat ships with no telemetry, no analytics, no third-party crash reporting SDK, and no background readers unrelated to hosts management. Specifically:

- No device identifiers, serial numbers, MAC or IP addresses, or any device fingerprints.
- No personal identifiable information such as accounts, email, name, or location.
- No usage tracking: menu clicks, node toggles, and edits stay on your machine.
- No reading of clipboard, contacts, calendar, photos, or any other system privacy domains.
- No reading of files outside the hosts file.

### 2. Data processed locally

HostCat only processes the following data on your Mac, in standard per-user directories:

- **HostCat configuration**: `~/Library/Application Support/com.hostcat.app/config.json`, containing groups, nodes, and active state.
- **Hosts backups**: `~/Library/Application Support/com.hostcat.app/backups/`, keeping the last 3 backups by default; created automatically before every real write.
- **System hosts file**: `/etc/hosts` (i.e. `/private/etc/hosts`). HostCat writes through a Privileged Helper running as root, and only writes the content you authored in HostCat or content imported from the existing file.
- **Diagnostic logs (OSLog)**: HostCat emits structured logs for key paths (writes, backups, XPC, config loading) into the macOS unified logging system. Logs only leave the system log when you actively choose **Settings → Diagnostics → Export Diagnostic Logs**; HostCat never uploads them.

### 3. Network activity

The current release of HostCat **does not initiate any network requests**. Future releases plan to add the following capability, which will be reflected here before shipping:

- **Sparkle auto-update (planned)**: fetches `appcast.xml` from HostCat's official GitHub Releases and the corresponding installer. Requests carry only the standard Sparkle User-Agent and no custom telemetry. You'll be able to disable automatic update checks in Settings.

### 4. Privileged Helper scope

HostCat installs a Privileged Helper `com.hostcat.helper` through `SMAppService` to write `/etc/hosts` safely. The Helper is intentionally narrow:

- Writes only to the fixed path `/private/etc/hosts`; it does not accept path arguments.
- Executes only the fixed DNS flush commands `dscacheutil -flushcache` and `killall -HUP mDNSResponder`.
- Verifies immutable flags, the HostCat management block marker, and the last acknowledged hosts hash before each write.
- Does not open network connections, run arbitrary shell commands, or accept UI state objects.

### 5. Your controls

- **Configuration**: Remove nodes / groups in the editor, or delete `~/Library/Application Support/com.hostcat.app/` to wipe HostCat state entirely.
- **Hosts writes**: Always require Helper registration and system approval; HostCat will not touch `/etc/hosts` until the Helper is enabled.
- **Backups**: Manage them in the backup window or delete the `backups/` directory to remove them.
- **Diagnostic logs**: They only land on disk if you export them yourself; HostCat never reads or forwards log contents otherwise.
- **Uninstall**: Move HostCat.app to the Trash and remove `com.hostcat.helper` from System Settings → General → Login Items. Then delete the data directories above if desired.

### 6. Third-party components

HostCat currently depends on the following open-source packages, none of which transmit data:

- [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts): local global shortcut registration via the Carbon Hot Key API.

If additional dependencies (e.g. Sparkle, Sentry) are introduced later, the data they touch will be documented here.

### 7. Contact

If you have any questions about this policy, please open an issue in the [HostCat repository](https://github.com/).
