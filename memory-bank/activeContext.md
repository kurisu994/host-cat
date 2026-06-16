# activeContext.md

> 每次会话结束前由 AI 主动更新此文件。

最后更新：2026-06-16

## 当前状态

- **分支**：main（commit `a68b586`）
- **版本**：1.0.0（pre-release，尚未打 tag）
- **阶段进度**：阶段 1 + 阶段 2 完成；阶段 3 进行中（任务 14 版本号管理 + 任务 19 搜索过滤 + 任务 22 结构化日志最小集 + 任务 26 DMG 拖拽安装背景已完成）

## 最近一次重要变更

**2026-06-16 DMG 拖拽安装体验与 Finder 布局定制**

1. 准备了精美的暗色科技感 DMG 安装背景图 `scripts/dmg-background.png`，对齐 Apple 官方设计指南，规范了 App 图标与 Applications 软链接的位置。
2. 编写了 `scripts/create-dmg.sh` 脚本，通过 AppleScript 自动配置 DMG 挂载后 Finder 窗口的尺寸（660x400）、隐藏状态栏与工具栏、应用背景图、定位 `HostCat.app` 和 `Applications` 快捷方式并启用自定义卷图标，确保极佳的首次安装体验。
3. 升级 `scripts/build-release.sh`，在打包阶段采用 `create-dmg.sh` 替代原有简单的 `hdiutil create`，并在本地挂载验证通过。

构建状态：✅ `swift test` 160 全通过（133 XCTest + 27 Swift Testing）/ ✅ `swift build` / ✅ `xcodegen generate` / ✅ `xcodebuild build -project HostCat.xcodeproj -scheme HostCatApp -destination 'platform=macOS,arch=arm64'` / ✅ `git diff --check`。

## 活跃文件

近期接触：
- `scripts/dmg-background.png` — DMG 拖拽安装背景设计图
- `scripts/create-dmg.sh` — 自动化 DMG 制作、Finder 布局和 AppleScript 设置脚本
- `scripts/build-release.sh` — 更新 release 脚本调用新打包方法
- `memory-bank/activeContext.md`、`memory-bank/progress.md` — 更新开发上下文和最新进度记录
- `TODO.md`、`CHANGELOG.md`、`docs/roadmap-to-1.0.md` — 打包相关状态勾选及变更归档

## 已做决策（最近）

| 决策 | 时间 | 原因 |
|------|------|------|
| 使用 AppleScript 动态构建 DMG 布局 | 2026-06-16 | macOS 官方首选方案，能在只读 DMG 中准确保持 Finder 窗口边界、背景与图标坐标 |
| 版本号通过 project.yml 集中管理 | 2026-06-15 | 一处修改全局生效，避免 App/Helper Info.plist 版本不一致 |
| build-release.sh 注入 Git hash 后恢复默认值 | 2026-06-15 | 避免污染 Git 工作区 |
| 搜索使用 .searchable 修饰符 | 2026-06-15 | macOS 原生风格，简洁且自动处理搜索框位置和键盘交互 |
| 搜索三路匹配（分组名/节点名/域名内容） | 2026-06-15 | 覆盖用户最常见的搜索场景 |
| 搜索时自动展开折叠分组 | 2026-06-15 | 确保搜索结果全部可见 |
| 诊断日志导出默认查最近一小时 `com.hostcat.*` | 2026-06-16 | 输出足够覆盖常见写入失败上下文，避免无边界导出系统日志 |
| OSLog system store 不可用时回退当前进程 | 2026-06-16 | 直接分发环境权限不稳定，失败时仍能拿到主应用日志 |
| XPC reply 与 timeout 竞争时以首次完成为准 | 2026-06-16 | 避免成功写入后 timeout task 迟到造成假错误日志和无意义断连 |

## 下一步

按 `docs/roadmap-to-1.0.md` 路线图，剩余必做项：
1. **任务 17** GitHub Actions CI/CD 发布流水线
2. **任务 16** Sparkle 自动更新（依赖任务 17 的 appcast.xml）
3. **任务 26 剩余** 准备 landing page 作为临时官网
4. **任务 14 收尾** 首次打 `1.0.0` tag

## 阻塞

无。

## 备注

- 新建了 `docs/roadmap-to-1.0.md`，梳理距离实际使用的差距（必做 vs 可延后）
- 5/21 完整 autoplan 审查报告：`~/.gstack/projects/kurisu994-host-cat/kurisu-main-autoplan-review-20260521.md`
- 6/8 增量审查报告：`~/.gstack/projects/kurisu994-host-cat/kurisu-main-incremental-review-20260608-142535.md`
