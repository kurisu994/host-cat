# activeContext.md

> 每次会话结束前由 AI 主动更新此文件。

最后更新：2026-06-15

## 当前状态

- **分支**：main（commit `a68b586`）
- **版本**：1.0.0（pre-release，尚未打 tag）
- **阶段进度**：阶段 1 + 阶段 2 完成；阶段 3 进行中（任务 14 版本号管理 + 任务 19 搜索过滤已完成）

## 最近一次重要变更

**2026-06-15 版本号管理 + 搜索过滤（commit `a68b586`）**

1. **任务 14** `project.yml` 集中定义 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`，App/Helper Info.plist 引用变量；`build-release.sh` 自动注入版本号、build 号和 Git commit hash；设置页展示完整版本信息
2. **任务 19** 编辑器侧边栏新增 `.searchable` 搜索框，支持分组名/节点名/hosts 域名内容三路匹配；搜索时自动展开折叠分组；空结果展示 `ContentUnavailableView`
3. **文档** 新建 `docs/roadmap-to-1.0.md` 1.0 发版路线图；更新 README、TODO、CHANGELOG

构建状态：✅ swift build / swift test 155 全通过 / xcodebuild BUILD SUCCEEDED

## 活跃文件

近期接触：
- `project.yml` — 新增 MARKETING_VERSION / CURRENT_PROJECT_VERSION
- `Sources/HostCatApp/Resources/Info.plist` — 改用变量引用 + 新增 HostCatBuildCommit
- `Sources/HostCatPrivilegedHelper/Info.plist` — 同步变量引用
- `scripts/build-release.sh` — 版本号 + Git hash 注入
- `Sources/HostCatApp/HostCatApp.swift` — SettingsView 版本号展示
- `Sources/HostCatApp/EditorView.swift` — 搜索过滤（searchText / filteredGroups / .searchable）
- `Sources/HostCatApp/Localization.swift` — 搜索相关 key
- `Sources/HostCatApp/Resources/{zh-Hans,en}.lproj/Localizable.strings` — 搜索文案
- `docs/roadmap-to-1.0.md` — 新建，1.0 发版路线图

## 已做决策（最近）

| 决策 | 时间 | 原因 |
|------|------|------|
| 版本号通过 project.yml 集中管理 | 2026-06-15 | 一处修改全局生效，避免 App/Helper Info.plist 版本不一致 |
| build-release.sh 注入 Git hash 后恢复默认值 | 2026-06-15 | 避免污染 Git 工作区 |
| 搜索使用 .searchable 修饰符 | 2026-06-15 | macOS 原生风格，简洁且自动处理搜索框位置和键盘交互 |
| 搜索三路匹配（分组名/节点名/域名内容） | 2026-06-15 | 覆盖用户最常见的搜索场景 |
| 搜索时自动展开折叠分组 | 2026-06-15 | 确保搜索结果全部可见 |

## 下一步

按 `docs/roadmap-to-1.0.md` 路线图，剩余必做项：
1. **任务 22** 结构化日志（OSLog 关键路径覆盖）
2. **任务 17** GitHub Actions CI/CD 发布流水线
3. **任务 16** Sparkle 自动更新（依赖任务 17 的 appcast.xml）
4. **任务 26** DMG 安装体验（背景图 + landing page）
5. **任务 14 收尾** 首次打 `1.0.0` tag

## 阻塞

无。

## 备注

- 新建了 `docs/roadmap-to-1.0.md`，梳理距离实际使用的差距（必做 vs 可延后）
- 5/21 完整 autoplan 审查报告：`~/.gstack/projects/kurisu994-host-cat/kurisu-main-autoplan-review-20260521.md`
- 6/8 增量审查报告：`~/.gstack/projects/kurisu994-host-cat/kurisu-main-incremental-review-20260608-142535.md`
