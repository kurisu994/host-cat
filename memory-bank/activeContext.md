# activeContext.md

> 每次会话结束前由 AI 主动更新此文件。

最后更新：2026-06-08

## 当前状态

- **分支**：main（与 origin/main 比领先 1 个 commit `ee3c562`）
- **版本**：未发布（still pre-1.0，处于阶段 3 上线准备）
- **阶段进度**：阶段 1 + 阶段 2 完成；阶段 3 进行中（i18n 主体完成、Helper 整合完成、Cmd+Z UX 修复完成）

## 最近一次重要变更

**2026-06-08 增量审查修复（commit `ee3c562`）**

针对 2026-05-22 ~ 2026-05-27 增量内容的定向审查反馈：
1. **P2#1** 编辑器撤销按钮 `Cmd+Z` → `⇧⌘Z`，避免与 macOS 标准撤销冲突导致长时间编辑后误触整体丢弃
2. **P2#2** `HostWriteCoordinator` 移除 `rolledBackConfig` 元组返回值，简化 API；与 2026-05-27 设计调整后的「保留草稿」语义对齐
3. **P3#1** `HelperService` 显式 switch 校验 `localizationIdentifier`，未知值或 `"system"` 时记录 warning 并回退 `zh-Hans`
4. **测试补充** `HostWriteCoordinatorTests` +2（hash mismatch 不自动重试 / 失败不阻塞后续批次）
5. **测试新增** `ValidatorParityTests` 验证 `HostsParser.validate` 与 `HostsContentValidator.validate` 行为一致

构建状态：✅ swift build / swift test 128 + 27 全通过

## 活跃文件

近期接触：
- `Sources/HostCatCore/HostWriteCoordinator.swift` — API 重构（移除元组返回）
- `Sources/HostCatCore/MenuBarViewModel.swift` — 4 处调用点适配
- `Sources/HostCatApp/EditorView.swift` — 撤销快捷键
- `Sources/HostCatApp/Resources/{zh-Hans,en}.lproj/Localizable.strings` — tooltip 文案
- `Sources/HostCatPrivilegedHelper/HelperService.swift` — 语言标识校验
- `Tests/HostCatCoreTests/HostWriteCoordinatorTests.swift` — 调用点适配 + 2 个新测试
- `Tests/HostCatCoreTests/ValidatorParityTests.swift` — 新建（8 个用例）
- `docs/hostcat-design.md` — 增量审查报告中的对应修订
- `~/.gstack/projects/kurisu994-host-cat/kurisu-main-incremental-review-20260608-142535.md` — 增量审查报告

## 已做决策（最近）

| 决策 | 时间 | 原因 |
|------|------|------|
| 撤销快捷键改 ⇧⌘Z | 2026-06-08 | 避让 macOS 标准 ⌘Z 单步撤销，防止误触全量丢弃 |
| `HostWriteCoordinator` 不再返回 `rolledBackConfig` | 2026-06-08 | 2026-05-27 已转向"保留草稿"语义，旧 API 是无用 artifact |
| Helper `localizationIdentifier` 显式校验 | 2026-06-08 | 防止主应用错传 `"system"` 导致英文用户看到中文错误 |
| 写入失败保留草稿（不回滚 UI） | 2026-05-27 | 避免覆盖用户正在编辑的内容（参见 [[productContext]] 失败语义） |
| 设置页整合 Helper 注册 + 语言切换 | 2026-05-27 | 单一入口，移除独立 Helper 引导窗口 |

## 下一步

按 TODO.md 阶段 3 任务，优先级建议：
1. **任务 14** 版本号与发布管理（先打 `1.0.0` tag，进入正式版）
2. **任务 17** GitHub Actions CI/CD 发布流水线（无 CI 难以可持续维护）
3. **任务 19** 搜索/过滤节点和域名（高频用户需求）
4. **任务 16** Sparkle 自动更新（依赖任务 17 的 appcast.xml）
5. **任务 15** 中英文多语言收敛底层诊断文本

阶段 3 中已部分完成：
- ✅ 任务 15 中英文主体已完成；剩余「清理底层文件系统与命令执行诊断细节中残留的英文文本」
- ✅ 任务 26 分发渠道确定独立分发

## 阻塞

无。

## 备注

- 5/21 已有完整 autoplan 审查报告：`~/.gstack/projects/kurisu994-host-cat/kurisu-main-autoplan-review-20260521.md`
- 6/8 增量审查报告：`~/.gstack/projects/kurisu994-host-cat/kurisu-main-incremental-review-20260608-142535.md`
- 用户的语言/工具偏好：[[~/CLAUDE.md]] 全局规则适用（中文交流、fd/rg/bat/eza、提交 message 中文不署名）
