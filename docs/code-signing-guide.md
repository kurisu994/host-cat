# HostCat 代码签名指南

本文档说明 HostCat 项目所需的代码签名证书类型、生成流程和配置方法。

## 签名场景一览

| 场景 | 证书类型 | 费用 | 说明 |
|------|---------|------|------|
| 本地开发调试 | Apple Development（Xcode 自动管理） | 免费 | 仅限自己的设备运行 |
| 分发给其他用户 | Developer ID Application | ¥688/年（Apple Developer Program） | Mac App Store 以外分发 |
| 上架 Mac App Store | Mac App Distribution + Mac Installer Distribution | ¥688/年 | 通过 App Store 分发 |

HostCat 包含 Privileged Helper，发布构建**必须**使用 Developer ID Application 证书，
且 Team ID 会硬编码进 Helper 的 XPC code signing requirement。


---

## 一、本地开发（免费，Xcode 自动签名）

如果只是自己开发调试，不需要手动生成证书。

### 1. 登录 Apple ID

打开 Xcode → **Settings** (⌘,) → **Accounts** → 点击左下角 **"+"** → 登录 Apple ID。

### 2. 配置自动签名

在 Xcode 项目设置中：

- Target `HostCatApp` → **Signing & Capabilities** → 勾选 **Automatically manage signing** → 选择你的 Team
- Target `HostCatPrivilegedHelper` → 同上

或者在 `project.yml` 中临时设置（不要提交）：

```yaml
settings:
  CODE_SIGN_STYLE: Automatic
  DEVELOPMENT_TEAM: "你的 Team ID"
```

### 3. 查看 Team ID

```bash
# 列出钥匙串中的开发证书
security find-identity -v -p codesigning
```

输出中 `Apple Development: xxx (XXXXXXXX)` 括号里的就是 Team ID。

---

## 二、发布构建（需要 Apple Developer Program）

### 前置条件

- 注册 [Apple Developer Program](https://developer.apple.com/programs/)（¥688/年）
- macOS 设备，已安装 Xcode

### 步骤 1：生成证书签名请求 (CSR)

#### 方法 A：通过钥匙串访问（推荐）

1. 打开 **钥匙串访问** (Keychain Access.app)
2. 菜单栏 → **钥匙串访问** → **证书助理** → **从证书颁发机构请求证书…**
3. 填写：
   - **用户电子邮件地址**：你的 Apple Developer 账号邮箱
   - **常用名称**：你的名字（会显示在证书中）
   - **CA 电子邮件地址**：留空
4. 选择 **存储到磁盘**
5. 点击 **继续**，将 `.certSigningRequest` 文件保存到桌面

#### 方法 B：通过命令行

```bash
# 生成私钥和 CSR（私钥会自动保存在钥匙串中）
openssl req -new -newkey rsa:2048 -nodes \
  -keyout ~/Desktop/HostCat_DevID.key \
  -out ~/Desktop/HostCat_DevID.csr \
  -subj "/emailAddress=你的邮箱/CN=你的名字/C=CN"
```

> 命令行方式生成的私钥需要手动导入钥匙串，推荐用方法 A。

### 步骤 2：在 Apple Developer Portal 创建证书

1. 登录 [Apple Developer - Certificates](https://developer.apple.com/account/resources/certificates/list)
2. 点击 **"+"** 创建新证书
3. 在 **Software** 区域选择 **「Developer ID Application」**
   - 这是用于 Mac App Store 以外分发的证书
4. 点击 **Continue**
5. 上传步骤 1 生成的 `.certSigningRequest` 文件
6. 点击 **Continue**，等待证书生成
7. 点击 **Download** 下载 `.cer` 文件
8. **双击** `.cer` 文件将其导入钥匙串

### 步骤 3：验证证书安装

```bash
# 列出所有 codesigning 身份
security find-identity -v -p codesigning

# 仅筛选 Developer ID Application
security find-identity -v -p codesigning | grep "Developer ID Application"
```

应输出类似：

```
1) ABCDEF1234567890... "Developer ID Application: 你的名字 (TEAMID)"
    1 valid identities found
```

记下完整的证书名称和括号中的 **Team ID**。

### 步骤 4：配置环境变量

将以下内容添加到 `~/.zshrc` 或 `~/.zprofile`（替换为你的真实值）：

```bash
# HostCat Release 签名配置
export DEVELOPER_ID_APPLICATION="Developer ID Application: 你的名字 (TEAMID)"
export DEVELOPMENT_TEAM="TEAMID"
```

执行 `source ~/.zshrc` 使其生效。

### 步骤 5：运行发布构建

```bash
cd /path/to/host-cat
./scripts/build-release.sh
```

脚本会自动完成以下流程：

1. 检查 `DEVELOPER_ID_APPLICATION` 和 `DEVELOPMENT_TEAM` 环境变量
2. 生成 Xcode 工程 (`xcodegen generate`)
3. 注入 Git commit hash
4. 归档 (`xcodebuild archive`)，使用 Developer ID 签名
5. 导出 App（Team ID 注入 `ExportOptions.plist`）
6. 打包 DMG

产物位于 `build/HostCat.dmg`。

---

## 三、验证签名

构建完成后，验证签名和 Notarization 状态：

```bash
# 验证 App 签名
codesign --verify --deep --strict build/export/HostCat.app

# 查看签名详情
codesign -dvvv build/export/HostCat.app

# 验证 Helper 签名
codesign -dvvv build/export/HostCat.app/Contents/Library/LaunchServices/com.hostcat.privileged-helper

# 检查 Gatekeeper 评估（需要先 Notarize）
spctl --assess --verbose=4 build/export/HostCat.app
```

---

## 四、Notarization（公证，推荐）

macOS 10.15+ 要求分发的 App 经过 Apple 公证，否则用户打开时会被 Gatekeeper 拦截。

### 1. 创建 App 专用密码

1. 前往 [appleid.apple.com](https://appleid.apple.com/) → **登录安全** → **App 专用密码**
2. 生成一个专用密码并保存

### 2. 存储凭据到钥匙串

```bash
xcrun notarytool store-credentials "HostCat-Notary" \
  --apple-id "你的Apple ID邮箱" \
  --team-id "TEAMID" \
  --password "App专用密码"
```

### 3. 提交公证

```bash
xcrun notarytool submit build/HostCat.dmg \
  --keychain-profile "HostCat-Notary" \
  --wait
```

### 4. Staple 公证票据

```bash
xcrun stapler staple build/HostCat.dmg
```

---

## 五、Team ID 与 XPC 安全要求

HostCat 的 Privileged Helper 使用 XPC 通信，签名验证中硬编码了 Team ID：

- **Helper 端** (`Sources/HostCatPrivilegedHelper/Info.plist`)：验证主应用的签名包含正确的 bundle identifier 和 Team ID
- **主应用端** (`Sources/HostCatHelperClient/`)：验证 Helper 的签名

这意味着：

- **Team ID 一旦确定后不应更换**，否则已安装的 Helper 会拒绝新版本 App 的 XPC 连接
- 发布脚本 `build-release.sh` 会在构建时通过 `DEVELOPMENT_TEAM` 环境变量注入 Team ID
- 开发调试时 Xcode 自动签名使用的 Team ID 与发布时可以不同（因为 Helper 只在本地运行）

---

## 常见问题

### Q: `errSecInternalComponent` 或签名失败

钥匙串被锁定，解锁后重试：

```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db
```

### Q: 证书过期了怎么办？

Developer ID Application 证书有效期 5 年。过期后需要：

1. 在 Developer Portal 用新 CSR 重新申请
2. 下载并导入新证书
3. 重新构建并签名

已安装用户不受影响（签名时间戳在有效期内即可）。

### Q: 能否用自签名证书？

可以用于开发调试，但 Gatekeeper 会拦截，用户需要手动在「系统设置 → 隐私与安全」中允许。
Privileged Helper 的安装也可能受阻。**不建议用于分发**。

### Q: 如何查看已安装证书的 Team ID？

```bash
security find-identity -v -p codesigning | grep "Developer ID"
# 输出中括号里的就是 Team ID，例如 (ABC123XYZ)
```
