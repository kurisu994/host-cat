# iHosts 竞品调研

日期：2026-05-19

## 背景

目标是制作一个 Apple Silicon 原生的 macOS hosts 管理应用，参考产品是 Toolinbox 的 iHosts。发布路线为直接分发（公证签名 DMG / GitHub Release），不做 App Store 版本，避免沙盒限制对权限模型的约束。

## 已核对资料

- GitHub 仓库：<https://github.com/toolinbox/iHosts>
- 官方产品页：<https://en.toolinbox.net/iHosts/>
- App Store 页面：<https://apps.apple.com/gb/app/ihosts-etc-hosts-editor/id1102004240>
- App Store 美国区评论：<https://apps.apple.com/us/app/ihosts-etc-hosts-editor/id1102004240?mt=12&see-all=reviews&platform=mac>

GitHub 仓库不是可直接改造的源码仓库，主要包含 `README.md` 和 `images/` 截图素材。它适合作为产品参考，不能作为 ARM 版本的直接 fork 基础。

## ARM / Apple Silicon 现状

App Store 页面显示 iHosts 当前版本为 `1.4.0`，发布时间是 2018-11-15。美国区评论里有用户在 2024-05-26 和 2025-04-19 提到希望支持 ARM / Apple Silicon，原因是不想安装 Rosetta 或希望 Universal App。开发者在 2025-04-21 的回复里表示自己仍在使用 Intel MBP，会尝试找办法。

这说明当前痛点真实存在：iHosts 仍能作为老工具使用，但不是 Apple Silicon 原生体验。

## iHosts 核心产品形态

iHosts 的本质不是单纯的 hosts 文本编辑器，而是一个菜单栏驱动的 hosts 配置切换器。

核心能力：

- 菜单栏常驻：点击菜单栏 `H` 图标后，可以直接勾选或取消勾选 hosts 节点。
- 分组管理：用组表达项目、域名集合或业务场景，例如 `Product A`、`Product B`。
- 节点管理：组下面有具体 hosts 节点，例如 `Development`、`Test`、`Production`。
- 组内单选：默认一个 hosts 分组里只能激活一个节点，避免同一批域名同时指向多个 IP。
- 自由组合：不同分组之间可以同时激活，用来组合多个项目或多个用途。
- 编辑窗口：左侧树形结构展示组和节点，右侧是当前节点的 hosts 文本内容。
- 应用与撤销：编辑后通过 `Apply` 写入，通过 `Revert` 放弃当前改动。
- 实时查看：只读显示当前最终写入 `/etc/hosts` 的内容。
- 快捷键：菜单项通过单字母标识触发（`E` = 编辑 Hosts，`V` = 查看 Hosts），通用设置中可配置全局快捷键（如 `⇧⌘E`）打开菜单栏。
- 开机启动：偏好设置里可以启用 start at login。

## 截图观察

### 菜单栏

菜单内容大致分为三段：

- hosts 节点区：顶层有 `Default`，分组显示为文件夹样式，组下展示节点。
- 常用操作区：`View Hosts`、`Edit Hosts`。
- 更多区：`More` 子菜单，包含偏好设置、教程、反馈、评分、退出。

本地中文截图中还能看到右侧数字，例如 `默认 0`、`feewee 1`、`onw 2`，这是菜单项的快捷数字键——用户按对应数字键可直接切换节点。首版保留此交互。

### 编辑窗口

编辑窗口采用 macOS 原生偏好设置式工具栏：

- `General`
- `Account`（我们的版本不保留此标签）
- `Edit Hosts`
- `View Hosts`

`Edit Hosts` 页面左侧是 hosts 树形列表，右侧是代码编辑器。底部有添加、删除、更多操作，右下角是 `Revert` 和 `Apply`。

本地中文截图显示编辑器已有语法着色：

- 注释为灰绿色。
- IP 地址为蓝色。
- 域名为黑色。

### 查看窗口

`View Hosts` 是只读预览，不仅显示当前节点内容，还会把分组和节点名写成注释分隔块。示例结构：

```text
# 默认
##
# Host Database
...

# ==============================
# 示例域名

# ------------------------------
# feewee
127.0.0.1 local.feewee.cn
```

这个预览能力很重要，因为用户切换完节点后需要明确知道当前真实生效的 hosts 状态。

### 通用设置

截图中的设置项：

- 开机自启动。
- 鼠标悬停时预览 Hosts。
- 一个 Hosts 分组中仅能激活一项。
- 打开菜单快捷键。
- 版本号。

## iHosts 权限模型（参考）

iHosts 为了上架 Mac App Store 使用沙盒模式，因此它不能默认访问 `/etc/hosts`。README 和截图展示了两步授权：

1. 应用弹窗提示用户允许访问 `/etc/hosts`，然后打开系统文件选择器，让用户手动选择 `/etc/hosts`。
2. 如果当前用户没有写权限，提示用户在 Terminal 执行一次类似 `sudo chmod +a 'user:<username>:allow write' /etc/hosts` 的命令。

这种方式虽然兼容沙盒，但用户体验较差，且权限可能在系统更新后丢失。我们采用 `SMAppService` + Privileged Helper 方案避免这些问题，详见 [开发方案设计](./hostcat-design.md)。
