# productContext.md

## 业务背景

开发者日常会频繁切换 hosts 配置：
- 本地开发指向某个 IP（测试环境/灰度环境）
- 绕过 CDN 或污染的 DNS
- 多套部署环境（dev / staging / preprod）的快速对比

现有方案的痛点：
- `sudo vim /etc/hosts` 流程长、易写错、无回滚
- 商业工具 iHosts 等需付费、UI 偏 Web 风格、对 macOS 原生体验融入不足
- 自写脚本需自管备份、DNS 刷新、权限提升

HostCat 提供：分组 + 节点 + 菜单栏一键切换 + 自动备份 + 安全 root 写入。

## 特殊约束

| 约束 | 原因 | 影响 |
|------|------|------|
| 仅 Apple Silicon | 项目核心定位是原生体验，且 2026 年起 Intel Mac 已退役多年 | 不做 Universal Binary，单 arm64 |
| 仅 macOS 14+ | macOS 13 的 `SMAppService` 有早期 bug | 注册流程更稳定，能用最新 SwiftUI API |
| 直接分发不上架 | LaunchDaemon Helper 与 Mac App Store 沙盒模型冲突 | 需自行处理签名/公证/Sparkle 自更新 |
| Helper 写入路径固定 | XPC 安全边界最小化 | 主应用不能把任意路径透传给 root 进程 |
| 不能 byte-for-byte 保留原 hosts | 统一 UTF-8 输出便于 parser/合成 | Latin-1 fallback 仅用于读取展示 |
| 不在测试中真实写 /etc/hosts | 防止污染开发机和 CI runner | 所有文件系统操作通过 `FileSystemOperations` 协议注入 |

## 核心用户流

```text
┌─────────────────────────────────────────────────────────────────┐
│  首次启动                                                        │
│   ↓                                                              │
│  导入当前 /etc/hosts（区块外内容 → 「默认」节点）                 │
│   ↓                                                              │
│  引导用户到「设置页」批准 Helper（SMAppService 系统设置 → 登录项）│
│   ↓                                                              │
│  菜单栏 ⌘点击 → 节点勾选切换                                     │
│   ↓                                                              │
│  内存状态立即更新 / UI 零延迟反馈                                │
│   ↓                                                              │
│  HostWriteCoordinator (debounce 500ms)                          │
│   ↓                                                              │
│  ① 备份当前 /etc/hosts → ~/Library/.../backups/                  │
│  ② XPC writeHosts(content, expectedHash, language)              │
│  ③ Helper: immutable flags 检查                                  │
│  ④ Helper: hash 一次校验（外部修改？）                            │
│  ⑤ Helper: 内容校验（HostCat 区块 + 必备系统条目）                 │
│  ⑥ Helper: mkstemp + write + fsync + chmod 644 + chown root:wheel│
│  ⑦ Helper: hash 二次校验（替换前再读一次）                        │
│  ⑧ Helper: rename(2) 原子替换 + 父目录 fsync                     │
│  ⑨ Helper: dscacheutil -flushcache + killall -HUP mDNSResponder │
│   ↓                                                              │
│  写入成功 → 持久化 config + 更新 lastAppliedHostsHash             │
│  写入失败 → 保留草稿 + UI 提示「hosts 未应用」（不回滚 UI）        │
└─────────────────────────────────────────────────────────────────┘
```

## 关键交互逻辑

### 两阶段写入模型
1. **即时更新 UI**：点击节点，`@MainActor` 上立即更新内存状态。
2. **延迟落盘**：500ms debounce 合并连续点击，只写最终状态。

### 失败语义（重要：2026-05-27 设计调整）
- 写入失败 **不回滚** UI 草稿，保持用户当前编辑状态。
- 草稿在 apply 调用前已被 `persistDraftConfig()` 持久化到磁盘。
- `HostWriteCoordinator.lastSuccessfulConfigSnapshot` 仅供服务层判定真实 hosts 状态，不返回给 UI（[[systemPatterns]] 中详述）。

### 多选模式
- 节点激活统一为多选模式。
- 旧 `isSingleSelect=true` 配置加载时被规范化为 `false`，UI 不再暴露单选切换。

### 外部修改决策
- Helper 检测到 `expectedCurrentHostsHash` 不匹配时拒绝写入，返回 `hashMismatch`。
- UI 弹窗给用户两个选择：**取消** 或 **确认覆盖**（force=true，跳过 hash 校验）。
- 注意：即使用户选了覆盖，Helper 在 rename 前仍会再次 hash 比对，拒绝覆盖操作期间发生的新修改。

### 撤销快捷键
- 编辑器「放弃」按钮（discard all unsaved edits）使用 **⇧⌘Z**，不占用 macOS 标准的 ⌘Z（避免长时间编辑后误触整体丢弃）。

## 数据安全约束

- hosts 写入前必备：备份成功 + immutable flags 通过 + 内容校验 + hash 一次校验 + hash 二次校验，五道关卡。
- 配置文件原子写入（临时文件 + rename），JSON 损坏时保留原配置 + 恢复默认。
- Helper code signing requirement 必须包含 `anchor apple generic` + bundle id + Team ID。
- XPC 仅传 String/Data/Bool/NSDictionary 等稳定桥接类型，不传 Swift Codable struct。

## 国际化决策

- **简体中文** 与 **English** 两套字符串资源。
- 偏好持久化在独立 `UserDefaults` key：`HostCat.appLanguage`（值：`system` / `zh-Hans` / `en`）。
- 运行时切换无需重启；`MenuBarExtra(.menu)` 通过 `.id(storedLanguage)` 强制重建避免文案延迟刷新。
- Helper 接受已解析后的具体语言标识（`zh-Hans` / `en`），仅用于错误文案；不参与权限/路径判定。
