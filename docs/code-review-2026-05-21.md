# HostCat 代码全面审查报告

**审查日期**：2026-05-21  
**审查范围**：全仓库 Swift 源码、测试、配置、文档  
**审查工具**：静态代码扫描 + 协议实现检查 + 测试覆盖率分析  
**当前基线**：阶段 1（安全预览版）和阶段 2（真实写入版）均已完成

---

## 一、部署阻塞项（必须完成）

### 1.1 Team ID 替换（2 处）

| 位置 | 当前值 | 要求 |
|------|--------|------|
| `Sources/HostCatPrivilegedHelper/HelperDelegate.swift:8` | `identifier "com.hostcat.app"` | 替换为包含真实 Team ID 的完整 requirement 字符串 |
| `Sources/HostCatHelperClient/XPCHostHelperClient.swift:12` | `identifier "com.hostcat.helper"` | 同上 |

**风险说明**：当前仅使用 bundle identifier 校验，未校验证书 Team ID，存在被同 identifier 的恶意应用调用的风险。  
**部署前必须完成**：获取 Apple Developer Team ID 后，将 requirement 更新为：

```swift
"anchor apple generic and identifier \"com.hostcat.app\" and certificate leaf[subject.OU] = \"TEAM_ID\""
```

---

## 二、代码层面的未完成项

### 2.1 占位实现（1 项）

**位置**：`Sources/HostCatApp/BackupRestoreView.swift:166-185`

`restoreBackup()` 方法当前为占位实现。点击"恢复此备份"后，实际未解析备份文件内容并更新节点配置，仅调用了 `applyImmediately()`。代码注释明确说明：

```swift
// 注意：实际恢复是通过修改 config 然后写入来实现的
// 这里暂时用 applyImmediately 占位，
// 完整实现需要 parse 备份内容并更新节点配置
```

**建议实现路径**：
1. 读取备份文件内容
2. 调用 `HostsImporter` 解析管理区块
3. 将解析结果更新到 `viewModel.config` 的对应节点
4. 触发 `scheduleApply()` 写入

### 2.2 TODO 标记（1 项）

**位置**：`Sources/HostCatApp/MergedPreviewView.swift:41`

冲突定位按钮点击后仅通过 `viewModel.applyError` 显示提示文字，未实现导航到 EditorView 并选中对应冲突节点的功能。

```swift
// TODO: 导航到冲突节点需要 EditorView 集成，当前显示提示
viewModel.applyError = "冲突节点 \(conflict.hostname) 位于 \(conflict.incoming.nodeName)"
```

### 2.3 代码问题（2 项）

**位置**：`Sources/HostCatApp/HostCatApp.swift:14-23`

DEBUG 模式下注释说明可用 `PreviewHostHelperClient` 绕过 Helper 注册，但实际代码直接使用了 `XPCHostHelperClient`，`PreviewHostHelperClient` 未被实际调用。建议修复为：

```swift
#if DEBUG
let helperClient: any HostHelperClient = PreviewHostHelperClient()
#else
let helperClient: any HostHelperClient = XPCHostHelperClient()
#endif
```

**位置**：`Sources/HostCatCore/HostWriteCoordinator.swift:132-146`

`waitUntilCurrentWriteFinishes()` 使用 10ms 轮询等待当前写入完成。功能正确但效率较低，在高频操作场景下会累积不必要的延迟。建议后续改为基于 `Continuation` 或 `AsyncStream` 的通知机制。

---

## 三、测试缺口

### 3.1 测试缺失（1 项）

**位置**：`Sources/HostCatCore/Models.swift`

以下纯数据模型的行为无独立单元测试覆盖：

- `AppConfig.initial(defaultHosts:currentHostsHash:)` 的默认值正确性
- `HostGroup`/`HostNode` 的 `Codable` 编解码一致性
- `AppSettings`/`AppStateMetadata` 的 `Equatable` 行为
- 模型间的嵌套编解码（configVersion 迁移场景预留）

**建议补充测试**：`Tests/HostCatCoreTests/ModelsTests.swift`

### 3.2 测试替身管理（1 项）

**位置**：`Tests/HostCatCoreTests/TestDoubles.swift`

当前 `TestDoubles.swift` 仅包含 `FakeHostHelperClient`。以下协议的测试替身分散或缺失：

| 协议 | 当前状态 | 建议 |
|------|----------|------|
| `FileSystemOperations` | 定义在 `HostsFileWriterTests.swift` 中 | 提取到 `TestDoubles.swift` |
| `HostsMerging` | 无独立替身 | 添加 `FakeHostsMerger` |
| `DNSRefreshing` | `StubDNSRefresher` 定义在 `DNSRefresher.swift` 中 | 提取到 `TestDoubles.swift` |
| `HostCatHelperXPCProtocol` | 无替身 | 添加 `FakeHelperXPCService` |

---

## 四、后置功能（9 项，低优先级）

以下功能在 `TODO.md`、`CHANGELOG.md` 和 `docs/hostcat-design.md` 中均标记为暂缓/后置：

| 序号 | 功能 | 当前状态 |
|------|------|----------|
| 1 | hosts 编辑器语法高亮、行号和错误行标记 | 未开始 |
| 2 | 跨分组拖拽排序 | 当前仅支持分组内节点拖拽 |
| 3 | 搜索和过滤节点、域名 | 未开始 |
| 4 | 全局快捷键打开菜单栏 | 未开始 |
| 5 | 鼠标悬停预览 hosts 内容 | 未开始 |
| 6 | 中文/英文完整多语言覆盖 | 未开始 |
| 7 | Sparkle 自动更新 | 未开始 |
| 8 | GitHub Actions CI/CD 发布流水线 | 未开始 |
| 9 | iCloud 同步 | 未开始 |

---

## 五、文档

### 5.1 README.md 补充建议

当前 README 已包含项目结构、快速开始、设计文档链接。建议补充：

1. **首次安装后的 Helper 授权步骤图解**：引导用户完成"系统设置 > 通用 > 登录项"中的 Helper 启用
2. **常见故障排查**：
   - Helper 注册失败的处理步骤
   - hash 不匹配（外部修改检测触发）的处理指引
   - DNS 刷新失败的排查方法
3. **卸载说明**：如何手动移除 Helper 和配置文件

---

## 六、审查统计

| 类别 | 数量 | 说明 |
|------|------|------|
| 部署阻塞 | 2 | Team ID + code signing requirement |
| 代码问题 | 3 | 占位实现、TODO、DEBUG 回退逻辑 |
| 测试缺口 | 2 | Models 测试缺失、测试替身分散 |
| 后置功能 | 9 | 语法高亮、搜索、快捷键、Sparkle 等 |
| 文档 | 1 | README 故障排查补充 |
| **合计** | **17** | — |

---

## 七、修复优先级建议

### P0（部署前必须完成）
- [ ] 替换 HelperDelegate 和 XPCHostHelperClient 中的 Team ID
- [ ] 更新 code signing requirement 为完整校验字符串

### P1（近期完成）
- [ ] 补全 `BackupRestoreView.restoreBackup()` 占位实现
- [ ] 修复 DEBUG 模式下 `PreviewHostHelperClient` 未使用的问题
- [ ] 补充 `Models.swift` 单元测试
- [ ] 统一测试替身到 `TestDoubles.swift`

### P2（后续迭代）
- [ ] 实现 `MergedPreviewView` 冲突定位导航
- [ ] 优化 `HostWriteCoordinator` 轮询为通知机制
- [ ] README 补充故障排查章节

### P3（后置功能，按需排期）
- [ ] 语法高亮、行号、错误标记
- [ ] 搜索过滤、全局快捷键
- [ ] Sparkle 自动更新
- [ ] GitHub Actions CI/CD
- [ ] iCloud 同步

---

*本报告由自动化代码审查生成，基于 2026-05-21 的代码快照。*
