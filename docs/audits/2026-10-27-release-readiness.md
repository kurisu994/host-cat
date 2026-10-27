# HostCat 正式使用前审查与测试报告

日期：2026-10-27

审查基线：`f476c036c0d63bb29268decf1339454ea34513a6`（`main`，开始时工作区干净）

## 结论

**暂不建议将当前构建作为日常使用或公开分发版本。开发者账号不是唯一阻塞。**

审查基线的 165 项测试通过，Debug 构建和未签名 Release archive 成功，但产物中的 Helper 启动入口、动态库路径、Team ID 嵌入及 Hardened Runtime 配置不完整。审查还发现写入并发、恢复意图丢失、CRLF 映射静默遗漏等实际缺陷；后续已修复 CRLF 等三项明确问题，但其他阻塞仍在。

本轮完成全仓分模块静态审查、双构建体系验证、产物检查和隔离回归实验；**未完成签名后的系统级端到端验收，不是“全面通过”或安全认证**。未发现有证据支持的 P0；P1 为正式使用／发布前阻塞，P2 为应修复的可靠性、兼容性或交付问题。

首次审查仅修复现有测试的目录隔离问题 T01；用户随后授权直接处理范围明确的逻辑问题，已修复 **R08、R12、R17**，其余问题仍待处理。架构、权限模型和写入状态机的修改应先确认方案。Sparkle、CI/CD 不是个人自用前的必要条件，不应优先于这些缺陷。

## 后续修复进展（2026-10-27）

| ID | 修复与验证 |
|---|---|
| R08 | parser／validate／import 统一识别 LF、CRLF 和混合换行；保留空行、错误行号、原始输入及原始 hash。新增解析、导入、合成到写入校验的数据保全测试，先失败后通过。 |
| R12 | 冲突、去重和系统条目校验统一按地址字节、地址族及 IPv6 接口作用域比较，输出保留原始 IP 写法。等价 IPv6 不再误报；真正不同的地址、IPv4／IPv4-mapped IPv6 和 scoped／unscoped IPv6 仍区分。回归测试先失败后通过。 |
| R17 | 错误提示移到预览条件之外，无预览时读取／创建失败也有展示路径。静态复核及 App 编译通过；尚未操作真实界面验收。 |

本批新增 **12 项测试**；`swift test` 为 **150 XCTest + 27 Swift Testing = 177 项通过**，`swift build` 和未签名 Xcode Debug App 构建通过。未改写入状态机、hash 覆盖策略或 Helper 权限／发布配置。

以下审查发现、行号、覆盖率和隔离失败用例结果保留原始基线证据；修复状态以上表为准，不将旧的失败计数或覆盖率当作修复后的测量值。

## 范围、方法和边界

- 四个独立审查分工：Core／文件与权限边界、写入状态与 XPC 并发、全部 App UI、构建与分发；主审复核调用链、合并重复问题，并运行验证。
- 覆盖 `Sources/HostCatCore`、`HostCatHelperClient`、`HostCatPrivilegedHelper`、`HostCatApp`，以及测试、XcodeGen／Xcode 工程、plist、entitlements、发布脚本和用户文档。
- 环境：Apple Silicon；macOS 27.0.1；Xcode 27.1（27A9275）；Apple Swift 6.4；XcodeGen 2.46.0。
- 不安装／注册／启动真实 Helper，不执行 DNS 刷新，不写真实 `/etc/hosts`，不访问签名私钥，不上传公证或发布产物。
- 未执行原生 UI 自动化或视觉／辅助功能验收；UI 发现均明确标为静态证据。
- 未使用第三方漏洞扫描器；项目当前无第三方代码依赖，不据此宣称不存在漏洞。
- 审查前后真实 hosts 的 SHA-256 一致。**现有测试曾影响用户备份目录，详见 T01，不能把本轮称为完全无副作用。**

## 实际验证结果

| 验证 | 结果与含义 |
|---|---|
| `swift test --enable-code-coverage` | 138 XCTest + 27 Swift Testing = **165 项通过** |
| 修复 T01 后 `swift test` | **165 项再次通过**，未弱化任何断言 |
| `swift build` | 通过，T01 修复后再次通过 |
| `xcodegen generate` | 通过，生成工程与 Git 基线无差异 |
| Xcode Debug `build`，`CODE_SIGNING_ALLOWED=NO` | 通过 |
| Xcode Debug `test`，`CODE_SIGNING_ALLOWED=NO` | **165 项通过**；T01 修复后再次通过 |
| Xcode Release `archive`，禁用签名 | 通过；使用 `DEVELOPMENT_TEAM=AUDIT12345` 作为展开验证占位值，**不是有效签名或账号验收** |
| Xcode `analyze` | 通过；不能替代 Swift 并发、原生 UI 或运行时安全验证 |
| `bash -n scripts/build-release.sh scripts/create-dmg.sh` | 通过；未实际执行 DMG 挂载／Finder 操作 |
| 5 个 plist／entitlements 的 `plutil -lint` | 通过；语法有效不代表启动语义有效 |
| 发布脚本缺身份／缺 Team 的提前失败分支 | 两种均 exit 1，均在清理 build 目录之前退出 |
| 隔离审查用例 | **10 项：8 项失败、2 项通过**；失败覆盖 5 类根因，而非 8 个独立漏洞 |
| 万条映射 merge → validate → import → parse | 10,003 条含系统条目完整保留，单次 Debug 核心处理约 **0.315 秒**；不代表编辑器输入／高亮／滚动性能 |
| T01 修复后的用户目录检查 | 最后一轮 Xcode 测试前后备份文件名、大小、修改时间完全一致 |
| `git diff --check` | 通过 |

构建警告：AppIntents 元数据提取被跳过；Release App 未配置 App Category。不是本轮主要阻塞，但不能声称零 warning。

### 覆盖率解释

本次 SwiftPM coverage 中，`Sources/` 下被计入的 **Core + HelperClient** 行覆盖合计约 **63.83%（1860/2914）**，不包括 App 与 PrivilegedHelper：

- `HostsParser`：96.53%；`HostsMerger`：98.84%；`HostsImporter`：94.04%。
- `HostWriteCoordinator`：90.61%，但 fake 不验证 hash，所以高覆盖仍漏过 R05。
- `MenuBarViewModel`：57.40%；`HostsFileWriter`：58.78%（真实 POSIX 实现大多未执行）。
- `XPCHostHelperClient`：4.53%；`HelperRegistrationManager`、真实 `DNSRefresher`：0%。

因此，现有绿灯主要说明纯逻辑与测试替身路径可运行，不能证明 Helper、签名、注册、公证和系统权限链可用。

## P1：正式使用／发布前阻塞

### R01 — LaunchDaemon 没有启动目标

**证据：产物静态检查 + Apple 官方文档。**

- `Sources/HostCatPrivilegedHelper/com.hostcat.helper.plist:4–12` 只有 `Label`、`MachServices`，无 `BundleProgram`，也没有其他程序入口。
- `project.yml:110–113` 原样复制；当前 Debug 和 Release archive 内同样缺失。
- 系统无法仅凭 Mach service 名称推断 Helper 二进制。复制可执行文件、取得证书都不能补上启动目标。

**修复方向：** 配置与当前布局一致的 `BundleProgram=Contents/Library/HelperTools/HostCatPrivilegedHelper`，保留按需启动。先做静态路径检查，再在签名包上实测注册、批准与连接。

### R02 — Helper 找不到 HostCatCore.framework

**证据：本轮新构建 Debug／Release 产物的 `otool` 检查。**

- `project.yml:105–107` 把 Helper 放在 `Contents/Library/HelperTools/`。
- 生成工程 Helper 的 `LD_RUNPATH_SEARCH_PATHS` 是 `@executable_path/../Frameworks`（`HostCat.xcodeproj/project.pbxproj:1003–1006,1086–1089`）。
- Helper 依赖 `@rpath/HostCatCore.framework/Versions/A/HostCatCore`；rpath 展开到不存在的 `Contents/Library/Frameworks`，实际框架在 `Contents/Frameworks`。

**影响：** 即使修复 R01，正常安装环境下仍会在进入 Helper 业务代码前加载失败。

**修复方向：** 在 `project.yml` 为 Helper 显式配置 `@executable_path/../../Frameworks` 并重新生成工程；验证最终导出产物而非只看 DerivedData。

### R03 — Helper tool 没有嵌入 Info.plist，Team ID 运行时缺失

**证据：构建设置、Mach-O 和运行时读取路径的静态闭环。**

- `project.yml:121–136` 仅设置 `INFOPLIST_FILE`，本轮 `-showBuildSettings` 确认 `CREATE_INFOPLIST_SECTION_IN_BINARY=NO`。
- 当前 Helper Mach-O 无 `__TEXT,__info_plist`；复制步骤只复制裸工具文件。
- 额外编译了只打印元数据的无副作用探针，放入相同 `App/Contents/Library/HelperTools/` 布局，外层 App Info.plist 已有占位 Team。实测 `Bundle.main` 指向 HelperTools、`TEAM=<missing>`、`INFO=[:]`，不会自动使用外层 App 的 Team；没有启动真实 Helper。
- `HelperDelegate.swift:6–15` 经 `HostCatCodeSigningRequirements.swift:19–32` 从 `Bundle.main` 读取 Team；缺失时生成 `HOSTCAT_TEAM_ID_NOT_CONFIGURED` requirement。

**影响：** 修好启动和加载后，服务端仍可能以不可满足的 Team requirement 拒绝合法主应用。这里不是签名验证绕过，而是发布产物不满足自己的验证要求。

**修复方向：** 为 tool 嵌入已展开的 Info.plist，核验 Team 和 bundle identifier。不能通过删除 Team 校验“修复”连接。

### R04 — Release 未启用 Hardened Runtime

**证据：本轮 App／Helper Release 构建设置均为 `ENABLE_HARDENED_RUNTIME=NO`。**

- `project.yml:12–20,86–98,131–136` 和 `scripts/build-release.sh:52–63` 均未启用。
- Developer ID 证书不会自动补齐该配置；当前流程缺少满足公证要求的必要条件。

**修复方向：** 为 Release App／Helper 启用，正式签名后确认 `runtime` flag、安全时间戳及无调试 entitlement。未实际提交公证，不声称已观察到服务端拒绝。

### R05 — 连续写入使用过期 hash，把自己的写入误报为外部修改

**证据：确定性内存 Helper 回归已失败。**

- `HostWriteCoordinator.swift:169–171` 只从捕获的 config 取得 expected hash。
- `MenuBarViewModel.swift:153–155,178–181` 在新 generation 出现后完全丢弃旧成功 completion。
- 时序：A 持 H0 等待 Helper → B 持 H0 入队 → A 写出 H1 → B 仍以 H0 写入，被拒绝；UI／磁盘也未保存 H1，后续普通应用不能自行恢复。
- 现有 `FakeHostHelperClient` 仅记录 expected hash、不验证，原并发测试因此通过。

**修复方向：** coordinator 以已确认提交的快照串联后续写入；区分“成功事实的记录”和“是否还能更新当前 UI”。不能把所有 mismatch 改成自动 force，否则会丢外部修改保护。

### R06 — debounce 到期后提前丢失取消句柄，旧等待者仍可落盘

**证据：代码级调度分析；未做确定性调度实测。**

- `HostWriteCoordinator.swift:104–105` 在进入 `performWrite` 前清空 `pendingTask`。
- `:125–127,138–150` 后续调用只能取消现有句柄，无法取消已经等待 `isWriting` 的旧任务；多个等待者的 10ms 轮询没有先后保证。
- A 正在写、B 已过 debounce 等待、C 后到的场景，B 不再能被 C 取消。若 B 是 force，它可以在 C 之后覆盖 C 的结果，而旧 UI completion 又被忽略。

**修复方向：** 明确单一活动批次与“最新待写快照”的队列语义，取消／代际检查贯穿等待阶段；补三批次、force 与恢复交错的可控调度测试。

### R07 — 恢复失败后的覆盖／审批重试，写成当前草稿

**证据：两个独立回归分支均失败。**

- `MenuBarViewModel.swift:190–216` 只在函数局部保留 `restoredConfig`。
- `:221–233` 的 force 和 `:297–299` 的 Helper 恢复重试都重新使用当前 `config`。
- `ExternalModificationAlert.swift:14–15` 和 Helper 引导入口没有保留恢复操作目标。
- 用户恢复 R，首次失败后确认覆盖或批准 Helper，实际写出的却是原草稿 D。

**修复方向：** 将待重试操作及其快照显式建模；失败仍保留草稿，但重试必须继续用户选中的恢复任务，取消时清除该意图。

### R08 — CRLF 注释开头节点的映射静默消失（已修复，见后续进展）

**证据：parser 与 merge→validator 两个回归均失败；LF 对照通过。**

- `HostsParser.swift:71–83,122–131` 使用按 `Character` 的 `split(separator: "\n")`。
- Swift 将 CRLF 作为一个 Character，`# imported\r\n10.0.0.1 api.test\r\n` 未被正确分行，整段被视为注释。
- `HostsMerger.swift:64–68` 得到空记录；若 LF 默认节点仍含系统条目，最终 Helper 校验照样通过，写入成功却遗漏映射。

**修复方向：** parser／validate／import／高亮一致处理 LF、CRLF、混合换行；必须有数据保全断言，不能只断言“不抛错”。

### R09 — 编辑器切换节点无提示丢失未应用内容

**证据：静态 UI 状态与调用链；未操作真实 UI。**

- `EditorView.swift:9,171–173,340–359` 只有一个 `editingContent`，切换 ID 直接覆盖。
- 输入 A → 不应用 → 选 B → 返回 A：A 的新文本不在 config、没有分节点草稿或确认提示。
- `hasUnsavedEdits` 仅控制按钮；Core 的草稿持久化无法保存尚未进入 config 的本地文本。

**修复方向：** 节点切换和关闭前明确保存／保留草稿／放弃语义；新增 UI 测试，不能用自动应用真实 hosts 作为无提示的替代方案。

### R10 — 退出丢失待应用状态，重启后勾选与真实 hosts 无提示分歧

**证据：静态退出、持久化和启动路径。**

- `MenuBarContentView.swift:98–99` 直接 `terminate`。
- `MenuBarViewModel.swift:141–153` 在 500ms debounce 前保存草稿；`HostCatApp.swift:99–107` 启动重新加载草稿，但不恢复 pending 标记或进行已应用状态对账。
- 切换后、写入前退出，重启可显示新勾选，实际 hosts 仍旧；失败后退出也会丢失仅内存中的错误状态。

**修复方向：** 区分“草稿选择”和“已应用状态”；退出提示／等待需有界，启动应呈现待应用／未知状态，不应未经授权直接覆盖外部 hosts。

## P2：其他确认问题与修复方向

| ID | 问题、证据及位置 | 影响与建议 |
|---|---|---|
| R11 | **强制覆盖未绑定本次备份快照**。`HostWriteCoordinator.swift:169–172,191–214`；隔离临时文件用例失败。备份 A 后外部改成 B，force 传 nil，Helper 两次都读取 B 后覆盖 C。 | 被覆盖的 B 没在本次备份中；第二次 hash 只保护 Helper 首读之后的变化。force 可忽略旧 config hash，但应改为本次备份快照 hash，仍拒绝更新的外部变化。建议自用前一并修复。 |
| R12（已修复） | **IPv6 等价文本被误判为不同地址**。`HostsMerger.swift:106–108,143`、`HostsFileWriter.swift:189–195`；两个回归失败。 | 压缩／展开地址误报冲突；展开的 loopback 被拒绝。按地址值规范化比较，同时保留真正不同 IP 的冲突检测。 |
| R13 | **旧 XPC 回调可污染新连接**。`XPCHostHelperClient.swift:143–166`；静态异步调度分析。 | C1 失效迟到，`failAllPendingReplies` 和 `invalidateConnection` 会清理 C2；回调应绑定连接代际，请求也归属其连接。需 fake connection 注入复现。 |
| R14 | **超时被断言为“未应用”，但远端可能已提交**。`XPCHostHelperClient.swift:68–81`、`HostWriteCoordinator.swift:234–247`、`MenuBarViewModel.swift:282`；静态跨进程分析。 | rename 后 DNS／reply 延迟可造成 10 秒客户端超时，hash 不更新且误导用户。引入“结果未知／需核实”语义，不能把本地取消视为远端回滚；增加已提交但丢 reply 的测试。 |
| R15 | **DNS 刷新失败被 UI 吞掉**。`HostWriteCoordinator.swift:211–232`；XPC 已保留 `didRefreshDNS=false`，coordinator 没有使用。 | hosts 成功但解析可能仍旧；传播非阻断警告，保留成功 hash，不回滚文件。 |
| R16 | **恢复成功后编辑器文本不同步**。`EditorView.swift:171–173,362–369,399–404`；静态 UI。 | 默认节点 ID 不变，独立 `editingContent` 仍是恢复前文本，点击应用可覆盖恢复结果。无本地编辑时同步外部版本，有编辑时提示冲突。 |
| R17（已修复，待 UI 验收） | **备份读取失败提示被隐藏**。`BackupRestoreView.swift:84–100,137–163`；静态 UI。 | 错误设定时 preview=nil，而错误标签在非 nil 分支；未选择备份时创建失败同样不可见。将错误展示移到独立区域。 |
| R18 | **快捷键注册失败仅写日志**。`CarbonHotKeyMonitor.swift:30–53`、`GlobalShortcuts.swift:16–38`；静态 UI。 | 快捷键被占用时设置仍显示成功绑定；返回注册结果并提示，替换失败考虑保留旧绑定。需多应用占用实测。 |
| R19 | **DMG 使用硬编码挂载点**。`scripts/create-dmg.sh:56–57,66,78,111`；静态脚本。 | 已有同名卷时实际挂载到另一位置，脚本仍操作 `/Volumes/HostCat`，可能失败或写错卷。解析 `hdiutil attach -plist` 并仅操作／卸载本次卷，用 trap 清理；本轮未挂载复现。 |
| R20 | **archive 失败后源 plist 不恢复**。`scripts/build-release.sh:2,47,52–66`；静态脚本。 | `set -e` 跳过成功路径中的恢复；成功时也固定写回 dev，而非原值。优先用构建变量，或保存原值并用 EXIT trap 恢复。 |
| R21 | **交付文档与实现不一致**。`docs/code-signing-guide.md:76–83,160,168`、`docs/roadmap-to-1.0.md:17`、`PRIVACY.md:47–57,107–117`。 | 签名指南验 Helper 路径错误；公证标“推荐”但路线图称已完成；脚本没有 notary／staple。CSR 注释称私钥自动存钥匙串，实际 `openssl -nodes -keyout` 写未加密桌面文件。隐私政策仍写已移除的 KeyboardShortcuts、备份删除入口和“删除目录清除全部状态”，遗漏 UserDefaults。需按真实行为修订；未读取私钥。 |

R13、R14 的实际 XPC 时序尚未用系统连接或可注入连接测试验证；不应将代码级风险叙述为真实攻击／故障已在系统重现。

## T01 — 已修复：现有测试会创建并轮转真实用户备份

**优先级 P1，证据为本轮实际副作用。**

以下测试构造 coordinator 时未传 `backupStore`，默认读真实 hosts 并写真实用户备份目录：

- `HostWriteCoordinatorTests`：`testNewOperationsPreservedDuringWrite`、`testHashMismatchPreventsOverwrite`；`testConflictDetectionPreventsApply` 也使用默认值，但当前在备份前已被冲突拦截。
- `MenuBarViewModelTests`：`testFailedApplyWithRollbackSnapshotStillKeepsEditedDraftConfig`、`testScheduledFailedApplyPersistsDraftConfig`。

**本轮影响：** 第一轮现有测试已执行默认备份与保留逻辑；确认用户目录最后只剩本轮 16:20:19 生成的三份备份。审查前没有该目录清单，无法确认原有文件数量或名称；若存在旧备份，可能已被轮转删除。未擅自清除这些新备份或声称恢复了旧备份，已及时告知用户。真实 hosts 始终未变。

**修复：** 以上五处显式传 `backupStore: nil`；需要覆盖备份行为的现有测试仍使用临时 hosts／备份目录，没有关闭备份专项测试或删断言。未改生产默认行为。

**复验：** SwiftPM 和 Xcode 各 165 项通过；扫描当前 `Tests/` 的 coordinator 构造均显式指定备份策略；修复后的最终 Xcode 测试前后真实用户备份文件名、大小、mtime 一致。

## 隔离回归证据和复跑方法

本轮为基线创建了临时 Git archive 副本，只加入以下审查用例，**不把已知失败测试放入默认测试 target**：

- [AuditConcurrencyRegressionTests.swift](2026-10-27/AuditConcurrencyRegressionTests.swift)：3 项均失败，对应 R05、R07 两个重试分支。
- [AuditContentRegressionTests.swift](2026-10-27/AuditContentRegressionTests.swift)：7 项，5 项失败（R08 两项、R11 一项、R12 两项）；LF 对照和万条记录测试通过。

用例断言期望的正确行为，失败是审查证据，不是用“期望 bug”伪装通过。只使用内存 Helper、临时 config／hosts fixture／备份；不注册 XPC 或调用 DNS。并发测试闸门等待应由外层测试进程设置超时。

从仓库根目录复跑基线（即使审查文件尚未提交也可运行）：

```bash
AUDIT_DIR="$(pwd)/docs/audits/2026-10-27"
WORK_DIR="$(mktemp -d /tmp/hostcat-audit-repro.XXXXXX)"
git archive f476c036c0d63bb29268decf1339454ea34513a6 | tar -x -C "$WORK_DIR"
cp "$AUDIT_DIR"/Audit*RegressionTests.swift "$WORK_DIR/Tests/HostCatCoreTests/"
cd "$WORK_DIR"
swift test --filter AuditConcurrencyRegressionTests
swift test --filter AuditContentRegressionTests
```

仅运行这两个 filter；上述基线仍含 T01，不要在该旧副本运行未隔离的全套测试。修复生产问题后将对应测试移入正常 `Tests/`，再做红→绿验证。

本轮原始日志和产物位于 **`/tmp/hostcat-audit-20261027/`**（临时文件可能被系统清理）：

- `swift-test.log`、`swift-test-after-isolation.log`、`swift-build-final.log`
- `xcode-debug.log`、`xcode-release-archive.log`、`xcode-test.log`、`xcode-test-after-isolation.log`、`xcode-analyze.log`
- `regression-tests.log`、`content-regression-tests.log`
- `helper-build-settings.txt`、`app-build-settings.txt`、`bundle-info-probe.log`
- `CoreTests.xcresult`、`HostCat.xcarchive`、`DerivedData/`

报告和两份用例保留在仓库；原始日志未复制入仓库，避免包含本机路径或测试读取到的用户数据。

## 修复顺序与拿到账号后的验收门槛

### 账号之前即可完成

1. **先修产物链 R01–R04**：启动 plist、rpath、嵌入 Team、Release runtime；增加不需要 root／账号的 bundle 静态验收。
2. **再修写入状态 R05–R07、R11、R13–R15**：明确成功事实、最新待写快照、恢复意图、连接代际、未知提交结果；保留外部修改保护。设计确认后实施。
3. **修文本／编辑安全 R08–R10、R12、R16–R18**：CRLF、IPv6、未保存编辑和待应用状态；补 Native UI 测试及手工验收。
4. 修脚本与文档 R19–R21；检查上述所有失败审查用例变绿，现有正常测试无回归（本批已增至 177 项）。

### 拿到 Developer ID 后，在专用测试机或 VM 验证

- [ ] 使用有效 Developer ID Application 和真实 Team 完整 archive／export；不能用本轮无签名 archive 替代。
- [ ] App、Helper、两个 framework 的 identifier、Team、时间戳和签名有效；App／Helper 有 runtime，无 `get-task-allow` 等调试权限。
- [ ] 检查 Helper 内嵌 plist 的 Team 已展开；rpath、BundleProgram 在**最终安装目录**能解析。
- [ ] `codesign --verify --deep --strict --verbose=4` 验最终 App；不要用 `--deep` 重签来掩盖嵌套签名错误。
- [ ] 把 App 安装到 `/Applications`，测试首次注册、拒绝／待审批、批准后按需启动、断连恢复、重新登录／重启。
- [ ] 在明确授权的隔离系统中验证真实写入、系统条目保全、备份恢复、外部修改拒绝、确认覆盖、immutable flags、DNS 成功和失败。不要在普通开发测试里操作宿主真实 hosts。
- [ ] 验证写入中连续切换、恢复与切换交错、写入／DNS 中途断开、退出重启后的草稿／已应用状态。
- [ ] 验证同 Team 升级、Helper 更新、注销／卸载、重新安装；不只测试首次安装。
- [ ] 最低 macOS 14 Apple Silicon 与当前支持系统均测试；本轮仅在 macOS 27.0.1 编译和跑核心测试。
- [ ] 公证最终分发对象，结果为 `Accepted`；staple 后 `stapler validate` 成功；保留 submission ID 和产物校验和，不存凭据。
- [ ] 从真实下载获得 quarantine 的最终 DMG 验 Gatekeeper，补离线首次打开测试；不通过删除 quarantine 绕过验收。
- [ ] 原生 UI：中文输入法、Unicode／CRLF、撤销重做、节点切换草稿、恢复同步、快捷键占用、语言切换、VoiceOver、键盘焦点、深浅色和大文件滚动。

**个人自用门槛：** 关键数据／Helper 问题修复后，通过签名安装和隔离真实写入验收。

**公开分发门槛：** 再通过完整公证、Gatekeeper、最低系统、升级／卸载和文档验收。自动更新及自动发布可作为后续迭代，不掩盖当前的安全与正确性阻塞。

## 官方依据

- [Apple：Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)（本轮通过 Context7 核对 `BundleProgram` 与 bundle-relative 路径要求）
- [Apple：SMAppService.daemon(plistName:)](https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:))（本轮直接读取官方文档 JSON，核对 LaunchDaemons 目录）
- [Apple：Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

以上公开资料仅作为 API／交付要求依据；产物与测试结论来自本轮本地验证。署名证书、公证服务及真实系统授权尚待账号后验证。
