# progress.md

## 版本发布历史

| 版本 | 日期 | 状态 | 备注 |
|------|------|------|------|
| 未发布 | — | 进行中 | 阶段 1 + 阶段 2 完成；阶段 3 上线准备（任务 14、19、22 最小集已完成） |

尚未打第一个 tag（`1.0.0`），CHANGELOG 全部归入「## 未发布」。

## 开发阶段完成度

### 阶段 1：安全预览版 ✅

| 子任务 | 状态 |
|--------|------|
| JSON 配置存储 + 原子写入 + 损坏恢复 | ✅ |
| HostCat 管理区块解析（v1）+ Latin-1 fallback | ✅ |
| 配置变更服务（增删改 + 排序 + 多选） | ✅ |
| `HostWriteCoordinator` actor（debounce + 冲突检测） | ✅ |
| 菜单栏预览体验（节点勾选 + 合成预览） | ✅ |
| 编辑窗口 MVP（左侧树 + 右侧文本编辑） | ✅ |
| 合成预览与冲突 UX | ✅ |
| `BackupStore` 预研实现 | ✅ |

### 阶段 2：真实写入版 ✅

| 子任务 | 状态 |
|--------|------|
| Xcode 工程迁移（xcodegen） | ✅ |
| 发布构建脚本（build-release.sh） | ✅ |
| `XPCHostHelperClient` + `HelperRegistrationManager` | ✅ |
| `HostCatPrivilegedHelper`（root 安全写入） | ✅ |
| `HostsFileWriter`（mkstemp + fsync + chmod/chown + rename + DNS） | ✅ |
| 写入前自动备份 + 外部修改检测 | ✅ |
| 写入失败保留草稿（UI 不回滚） | ✅ |
| 备份事务式恢复 | ✅ |
| DMG 打包 + Developer ID 签名 + 公证 | ✅ |

### 阶段 2 后续增强 ✅

| 子任务 | 状态 |
|--------|------|
| hosts 编辑器语法高亮（TextKit 2） | ✅ |
| 多行错误收集（`validate(_:)` 非抛出） | ✅ |
| 行号栏（`LineNumberRulerView`） | ✅ |
| 编辑器工具栏（节点名 + 撤销 + 应用） | ✅ |
| i18n 中英文资源 + 运行时切换 | ✅ |
| Helper 注册整合到设置页 | ✅ |
| hash 二次校验（替换前重检） | ✅ |
| 撤销快捷键改 ⇧⌘Z 避让 macOS 标准 | ✅ |
| `HostWriteCoordinator` API 清理（移除 rolledBackConfig） | ✅ |

### 阶段 3：上线准备 🚧 进行中

| 子任务 | 状态 |
|--------|------|
| 任务 14 版本号与发布管理（tag 1.0.0） | 🟡 主体完成（待打 tag） |
| 任务 15 中英文多语言（主体已完成，残留底层诊断文本待清理） | 🟡 部分 |
| 任务 16 Sparkle 自动更新 | ⏳ 未开始 |
| 任务 17 GitHub Actions CI/CD | ⏳ 未开始 |
| 任务 18 全局快捷键 | ⏳ 未开始 |
| 任务 19 搜索和过滤 | ✅ |
| 任务 20 配置导入导出 | ⏳ 未开始 |
| 任务 21 通知中心集成 | ⏳ 未开始 |
| 任务 22 崩溃报告与诊断日志 | 🟡 诊断日志最小集完成（崩溃报告后置） |
| 任务 23 大文件性能与稳定性验证 | ⏳ 未开始 |
| 任务 24 可访问性 | ⏳ 未开始 |
| 任务 25 隐私政策 | ⏳ 未开始 |
| 任务 26 分发渠道决策（独立分发） | ✅ 已决策 |

## 重大架构变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-05-19 | 项目初始化，SwiftPM 骨架 | 起步 |
| 2026-05-21 | 完成阶段 1，完成首次 autoplan 审查 | 验收阶段 1 + 决策阶段 2 方案 |
| 2026-05-21 | SwiftPM → Xcode 工程（xcodegen） | `SMAppService` 要求标准 app bundle 结构 |
| 2026-05-22 | hosts 加固：hash 二次校验 + 安全写入 5 道关卡 | 5/21 审查报告 P2 风险修复 |
| 2026-05-22 | 编辑器语法高亮（TextKit 2 + NSRulerView） | 用户体验完整性 |
| 2026-05-22 | 节点激活统一为多选，废弃 `isSingleSelect` UI | 简化交互模型，旧配置加载时规范化 |
| 2026-05-22 | XPC 双向 code signing requirement（含 Team ID） | 5/21 审查报告 P1 安全风险 |
| 2026-05-23 | 修复 hover preview / 完善 i18n 资源 | 体验打磨 |
| 2026-05-27 | i18n 中英文资源完整覆盖 + 运行时切换 | 阶段 3 任务 15 |
| 2026-05-27 | Helper 注册整合到设置页，移除独立引导窗口 | 单一入口 |
| 2026-05-27 | 写入失败语义从「回滚」转为「保留草稿」 | 避免覆盖用户正在编辑的内容 |
| 2026-05-27 | 菜单 `.id(storedLanguage)` 强制重建 | 修复语言切换后菜单文案需悬停才刷新 |
| 2026-06-08 | 撤销快捷键 ⌘Z → ⇧⌘Z | 避让 macOS 标准撤销 |
| 2026-06-08 | `HostWriteCoordinator` 移除 `rolledBackConfig` 返回值 | 与 5/27 设计调整对齐，清理 API artifact |
| 2026-06-08 | `HelperService` 显式校验 `localizationIdentifier` | 防止 `"system"` 被错传导致语种不一致 |
| 2026-06-15 | 版本号通过 project.yml 集中管理 | 一处修改全局生效，避免 App/Helper 版本不一致 |
| 2026-06-15 | 编辑器侧边栏搜索过滤 | 高频用户需求，分组名/节点名/域名三路匹配 |
| 2026-06-16 | 结构化日志与诊断日志导出 | 1.0 前排查 XPC 断连、写入失败、备份和配置加载问题 |

## 已解阻碍

| 阻碍 | 解决方案 | 时间 |
|------|---------|------|
| SwiftPM 无法构建带 Privileged Helper 的 app bundle | 引入 xcodegen 双轨：SwiftPM 跑核心测试，Xcode 工程构建 app | 2026-05-21 |
| Helper code signing requirement 过宽，第三方可冒用 | 改为 `anchor apple generic` + bundle id + Team ID 完整 requirement | 2026-05-22 |
| `HostsFileWriter` 仅在操作开始时校验 hash，存在竞态窗口 | 替换前再读一次目标文件做 hash 二次校验，并补回归测试 | 2026-05-22 |
| `MenuBarExtra(.menu)` 切换语言后菜单文案不刷新 | 通过 `.id(storedLanguage)` 强制重建菜单项 | 2026-05-27 |
| `HostsParser` 对纯注释/空行内容误报 `emptyContent` | 返回空记录数组而非抛错 | 2026-05-22 |
| 跨分组拖拽排序复杂度大于收益 | 产品决策已砍，保留分组内拖拽 | 2026-05-23 |
| Cmd+Z 与 macOS 标准撤销冲突可能导致草稿丢失 | 改为 ⇧⌘Z + tooltip 提示快捷键 | 2026-06-08 |
| `rolledBackConfig` API 是无用 artifact，注释误导性 | 移除元组返回值，更新注释为「保留草稿」语义 | 2026-06-08 |
| `HelperService` 收到 `"system"` 时回退到中文，可能让英文用户看到中文错误 | 显式 switch 校验，未知值记录 warning | 2026-06-08 |
| XPC reply 丢失/连接中断时可能永久挂起 | pending reply 在错误/取消/超时/连接失效时收敛 | 2026-05-22 |
| 写入前备份失败仍继续覆盖 hosts | 备份失败阻止真实写入 | 2026-05-22 |

## 审查记录

| 日期 | 审查类型 | 报告 |
|------|---------|------|
| 2026-05-21 | 完整 4 阶段 autoplan | `~/.gstack/projects/kurisu994-host-cat/kurisu-main-autoplan-review-20260521.md` |
| 2026-06-08 | 定向增量审查（5/22-5/27 变更） | `~/.gstack/projects/kurisu994-host-cat/kurisu-main-incremental-review-20260608-142535.md` |

## 测试演进

| 日期 | 变化 |
|------|------|
| 阶段 1 完成时 | 核心模型 + parser + merge + storage + hash 单测，约 60+ |
| 阶段 2 完成时 | 增加 coordinator + backup + file writer + viewmodel + importer 测试 |
| 2026-05-27 | 增加 `AppLanguageTests`、`ModelsTests`、`TestDoubles.swift` 统一替身 |
| 2026-06-08 | 增加 `ValidatorParityTests`（8）+ HostWriteCoordinatorTests `hashMismatchDoesNotAutoRetry` 和 `failedBatchDoesNotBlockSubsequentBatch` |
| 2026-06-15 | 未新增测试（任务 14 和 19 为 UI 层变更，现有 155 个测试全通过） |
| 2026-06-16 | 增加 `DiagnosticLogExporterTests`（3），覆盖导出格式、空结果文案和诊断级别名 |
| 2026-06-16 | 增加 `XPCHostHelperPendingRepliesTests`（2），覆盖 XPC request 重复完成只接受首次结果，以及批量失败时清空 pending replies |

当前测试总数：**133 XCTest + 27 Swift Testing**，全部通过。
