# HostCat 代码审查报告

日期：2026-05-21
审查范围：host-cat 仓库全量 Swift 源码（阶段 1 安全预览版）
审查依据：AGENTS.md 项目规则、docs/hostcat-design.md 设计文档

---

## 1. 总体评价

当前代码处于阶段 1（安全预览版）完成状态，整体架构清晰，模块边界遵守设计文档约定。核心逻辑（parser、merge、config storage、mutation、backup）已具备较完整的单元测试覆盖。但审查中发现若干需要修复的问题，按严重程度分为：阻塞问题、建议修复、设计债务三类。

---

## 2. 阻塞问题（必须修复）

### 2.1 HostsParser 对纯注释/空行内容抛出 emptyContent，与设计文档语义冲突

**位置**：`Sources/HostCatCore/HostsParser.swift` 第117-119行

**问题**：Parser 在内容只有注释或空行时抛出 `emptyContent` 错误。但设计文档明确说明「每行可为空行、整行注释」，且默认节点可能只包含系统注释（如 macOS 默认 hosts 的前导注释）。这会导致合法配置无法通过 parser 校验。

**影响**：
- 默认节点如果只有注释内容，merge 会失败
- 用户创建只含注释的节点，Apply 会报错

**修复建议**：
- 移除 `emptyContent` 错误，或将其降级为 warning
- 允许 parser 返回空记录数组
- 同步更新 `HostsParserTests.swift` 中对应断言

### 2.2 HostsMergerTests 存在重复测试方法名

**位置**：`Tests/HostCatCoreTests/HostsMergerTests.swift` 第5行和第34行

**问题**：两个测试方法同名 `testDefaultNodeAlwaysParticipatesAndDuplicateEntriesAreCollapsed()`。XCTest 不会报错，但只会执行其中一个，导致测试覆盖缺失。

**修复建议**：重命名其中一个，例如第二个改为 `testDefaultNodeAlwaysParticipatesAndDuplicateEntriesAreCollapsed_Second()` 或合并为一个更完整的测试。

### 2.3 HostWriteCoordinator 写入失败后未执行状态回滚

**位置**：`Sources/HostCatCore/HostWriteCoordinator.swift` 第153-162行

**问题**：设计文档明确规定「写入失败时只回滚当前失败批次的状态到上次成功写入的快照」。但当前 `performWrite` 在 catch 块中仅返回错误结果，没有将 `config` 回滚到 `lastSuccessfulConfigSnapshot`。

**影响**：MenuBarViewModel 中的 `config` 状态与实际 hosts 文件不一致，用户看到的勾选状态是"已应用"的，但实际上写入失败。

**修复建议**：
- 在 `HostWriteCoordinator` 中增加回滚方法
- 写入失败时将传入的 config 替换为 `lastSuccessfulConfigSnapshot`
- 或者通过返回回滚后的 config 让调用方同步状态

### 2.4 MenuBarViewModel 在写入成功后未更新 `lastExternalHostsHash`

**位置**：`Sources/HostCatCore/MenuBarViewModel.swift` 第128-148行

**问题**：设计文档中 `AppStateMetadata` 包含 `lastExternalHostsHash` 字段，用于记录"上次导入或确认处理的外部 hosts hash"。但当前代码在写入成功后只更新 `lastAppliedHostsHash` 和 `lastAppliedAt`，从未写入 `lastExternalHostsHash`。该字段目前属于死代码。

**修复建议**：
- 如果阶段 1 暂不实现外部修改检测，应在 `Models.swift` 中注释说明该字段预留用途
- 或在 `HostWriteCoordinator` 写入成功时同步设置该字段

---

## 3. 建议修复（推荐在阶段 2 前处理）

### 3.1 HostsParser 的 hostname 校验过于严格

**位置**：`Sources/HostCatCore/HostsParser.swift` 第128-147行

**问题**：`isValidHostname` 使用 `CharacterSet.alphanumerics` 校验 label 字符，这会拒绝包含下划线 `_` 的 hostname。虽然 RFC 1123 不推荐下划线，但 Windows 网络和某些内部系统广泛使用 `_`（如 `my_host.local`）。

**建议**：放宽校验，允许下划线，或提供明确的错误提示说明 HostCat 不支持含下划线的 hostname。

### 3.2 HostsParser 不支持制表符分隔

**位置**：`Sources/HostCatCore/HostsParser.swift` 第86-88行

**问题**：`split(whereSeparator: { $0 == " " || $0 == "\t" })` 确实支持制表符，但注释和测试中没有覆盖制表符场景。hosts 文件传统上使用制表符分隔 IP 和 hostname。

**建议**：在 `HostsParserTests` 中增加制表符分隔的测试用例。

### 3.3 HostsMerger 的 duplicateCount 计数逻辑有歧义

**位置**：`Sources/HostCatCore/HostsMerger.swift` 第142-151行

**问题**：`duplicateCount` 按 "被过滤掉的 hostname 次数" 计数。如果一个记录有 3 个 hostname，其中 2 个重复，会计数 2 次。但 UI 展示为 "N 条重复条目已合并"，用户可能理解为 "N 条记录" 而不是 "N 个 hostname"。

**建议**：明确语义——要么改为记录级去重计数（整条记录算 1 条），要么在 UI 文案中改为 "N 个重复域名已合并"。

### 3.4 ConfigMutationService 在 EditorView 中被重复实例化

**位置**：`Sources/HostCatApp/EditorView.swift` 多处

**问题**：EditorView 中每次操作都 `var service = ConfigMutationService()` 创建新实例。虽然 `ConfigMutationService` 是无状态 struct，但这样写冗余且容易遗漏统一行为（如未来需要在 mutation 中增加校验）。

**建议**：
- 将 `ConfigMutationService` 作为 `MenuBarViewModel` 的属性统一维护
- 或者让 EditorView 通过 viewModel 调用 mutation，不直接操作 service

### 3.5 EditorView 的 `saveCurrentNode` 中节点查找效率低

**位置**：`Sources/HostCatApp/EditorView.swift` 第254-269行

**问题**：`saveCurrentNode` 通过遍历所有 group 和 node 来定位目标节点，时间复杂度 O(G*N)。虽然数据量小，但代码风格不佳。

**建议**：利用 `selectedNodeID` 和已知的 `groupID` 直接定位，或在 EditorView 状态中缓存当前编辑的 `(groupID, nodeID)`。

### 3.6 BackupStore.createBackup 未返回错误时 cleanup 失败被静默忽略

**位置**：`Sources/HostCatCore/BackupStore.swift` 第75-80行

**问题**：cleanup 失败只记录 warning 日志，不抛出错误。这是设计意图（备份已创建成功），但如果 cleanup 持续失败，备份目录会无限增长。

**建议**：增加一个 `cleanupFailures` 计数或定期告警机制，或在测试中添加 cleanup 失败场景的覆盖。

### 3.7 AppConfigStore 的 atomicReplaceFailed 错误信息不够具体

**位置**：`Sources/HostCatCore/AppConfigStore.swift` 第106-108行

**问题**：`rename()` 失败时只返回 errno，没有包含源路径和目标路径信息，调试困难。

**建议**：在错误描述中包含路径信息，或增加 debug 日志记录 rename 操作详情。

---

## 4. 设计债务（阶段 2 需要关注）

### 4.1 HostWriteCoordinator 的 debounce 与写入串行化存在竞态条件

**位置**：`Sources/HostCatCore/HostWriteCoordinator.swift` 第60-88行

**问题**：`scheduleApply` 中 `pendingTask?.cancel()` 后创建新 Task，但旧 Task 可能已经在 `performWrite` 中执行（因为 cancel 不会立即终止运行中的代码）。`isWriting` 标志可以阻止并发写入，但 debounce 语义不够清晰：
- 如果旧 Task 正在 `Task.sleep` 中，cancel 会正确跳过写入
- 如果旧 Task 已经进入 `performWrite`，新 Task 会在 `isWriting` 处返回失败

**建议**：阶段 2 引入更清晰的批次 ID 机制，明确区分"取消待写入"和"写入进行中"两种状态。

### 4.2 HostHelperClient 协议未包含备份操作

**位置**：`Sources/HostCatHelperClient/HostHelperClient.swift`

**问题**：设计文档规定"备份统一由主应用执行，Helper 只负责写入"。但当前 `HostHelperClient` 协议只有 `writeHosts` 方法，没有体现主应用侧备份的接口。阶段 2 需要在 `HostWriteCoordinator` 中显式接入 `BackupStore`。

### 4.3 HostCatPrivilegedHelper 骨架未实现任何安全校验

**位置**：`Sources/HostCatPrivilegedHelper/HostCatPrivilegedHelperMain.swift`

**问题**：当前 Helper 只是打印骨架信息。阶段 2 需要实现：
- `realpath` 解析 `/private/etc/hosts`
- immutable flags 检测
- `expectedCurrentHostsHash` 校验
- `mkstemp` + `fsync` + `chmod 644` + `chown root:wheel` + `rename`
- 内容完整性校验（非空、包含系统默认条目、区块标记完整）
- DNS 刷新命令执行

### 4.4 XPC Protocol 使用 NSDictionary 返回值，类型不安全

**位置**：`Sources/HostCatHelperClient/HostHelperClient.swift` 第43-49行

**问题**：`HostCatHelperXPCProtocol` 的 reply block 使用 `NSDictionary`，需要运行时解包，容易出错。

**建议**：使用 `NSError` 参数 + 明确的 success/failure 结构，或定义专门的 XPC 结果类型。

### 4.5 MenuBarViewModel 同时承担 UI 状态管理和业务协调，职责过重

**位置**：`Sources/HostCatCore/MenuBarViewModel.swift`

**问题**：`MenuBarViewModel` 既维护 `@Published` UI 状态，又直接调用 `configStore.save()` 和 `HostsMerger().merge()`。按照模块边界，持久化和合并逻辑应该由 `HostWriteCoordinator` 或专门的服务层处理，ViewModel 只负责状态绑定。

**建议**：阶段 2 将配置持久化逻辑下沉到 `HostWriteCoordinator` 或新建 `ConfigPersistenceService`。

### 4.6 缺少对 `lastAppliedHostsHash` 不匹配时的用户决策流程

**位置**：整体设计

**问题**：设计文档规定了 hash 不匹配时的三种选择（导入/取消/覆盖），但当前代码中没有实现该决策流程。`HostWriteCoordinator` 在写入失败时只是返回错误，没有区分"hash 不匹配"和其他错误类型。

**建议**：阶段 2 在 `ApplyStatus` 中增加 `.hashMismatch` case，并在 UI 层实现决策弹窗。

---

## 5. 测试覆盖评估

### 5.1 已覆盖（良好）

- Parser：IPv4、IPv6、多 alias、注释、空行、错误 IP、错误 hostname、行号追踪
- Merger：默认节点参与、跨组合并、单选/多选、冲突检测、重复去重
- ConfigMutationService：group/node CRUD、排序、单选行为、默认节点保护
- ConfigStore：加载、保存、损坏恢复、版本不匹配、原子写入保护
- Importer：无区块、完整区块、缺 Begin/End、未知版本、区块外内容提取、编码 fallback
- BackupStore：命名、排序、保留策略、读取
- HostWriteCoordinator：debounce、成功状态更新、失败不回滚（当前实现如此）、冲突阻止写入

### 5.2 未覆盖（需要补充）

- `HostsHash`：只有工具函数，无独立测试（虽然被间接测试覆盖）
- `MenuBarViewModel`：无单元测试，所有行为依赖 UI 集成测试
- `EditorView` / `MergedPreviewView` / `HostCatApp`：无 UI 测试
- `HostCatPrivilegedHelper`：无测试（骨架代码）
- HostsParser：缺少制表符分隔测试、下划线 hostname 测试、纯注释内容测试
- HostsMerger：缺少空默认节点 + 空 groups 的边界测试
- 并发测试：`HostWriteCoordinator` 的并发场景依赖 sleep 模拟，不够稳定

---

## 6. 代码风格与规范

### 6.1 符合规范

- Swift 6 strict concurrency 已启用
- 数据模型使用 `struct` + `Sendable`
- UI 层使用 `@MainActor`
- 写入协调使用 `actor`
- 中文注释和错误信息
- Git 提交信息使用中文

### 6.2 不符合规范

- `HostsParserTests.swift` 第26行：`return XCTFail(...)` 在 `guard else` 中，虽然语法正确但风格不佳，应直接使用 `XCTAssertEqual` 或 `XCTAssertTrue`
- `EditorView.swift` 中多处 `var service = ConfigMutationService()` 冗余
- `HostWriteCoordinator` 第124行：`catch let HostMergeError.conflicts(conflicts)` 可以简化为 `catch HostMergeError.conflicts(let conflicts)`

---

## 7. 修复优先级建议

| 优先级 | 问题 | 文件 |
|--------|------|------|
| P0 | Parser emptyContent 误报 | HostsParser.swift |
| P0 | 重复测试方法名 | HostsMergerTests.swift |
| P0 | 写入失败未回滚状态 | HostWriteCoordinator.swift |
| P1 | hostname 下划线支持 | HostsParser.swift |
| P1 | ConfigMutationService 重复实例化 | EditorView.swift |
| P1 | 补充制表符测试 | HostsParserTests.swift |
| P2 | duplicateCount 语义澄清 | HostsMerger.swift + UI |
| P2 | lastExternalHostsHash 死代码 | Models.swift |
| P2 | 竞态条件优化 | HostWriteCoordinator.swift |
| P3 | ViewModel 职责拆分 | MenuBarViewModel.swift |
| P3 | XPC 类型安全 | HostHelperClient.swift |

---

## 8. 结论

HostCat 阶段 1 代码整体质量良好，架构分层清晰，核心逻辑测试覆盖充分。存在 3 个阻塞问题需要在进入阶段 2 前修复，其余问题可在阶段 2 开发过程中逐步处理。建议先修复 P0 问题，再启动 `SMAppService` + Privileged Helper 的接入工作。
