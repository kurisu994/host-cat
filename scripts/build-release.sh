#!/bin/bash
set -e

# HostCat Release Build Script
# usage: ./scripts/build-release.sh

echo "🚀 开始构建 HostCat Release 版本..."

# 环境变量检查
if [ -z "$DEVELOPER_ID_APPLICATION" ]; then
    echo "❌ 未设置 DEVELOPER_ID_APPLICATION，Release 包必须使用 Developer ID 签名"
    exit 1
fi

if [ -z "$DEVELOPMENT_TEAM" ]; then
    echo "❌ 未设置 DEVELOPMENT_TEAM，Privileged Helper 的 XPC requirement 需要真实 Team ID"
    exit 1
fi

APP_NAME="HostCat"
PROJECT_DIR=$(pwd)
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
EXPORT_OPTIONS_PATH="${BUILD_DIR}/ExportOptions.plist"
APP_BUNDLE="${EXPORT_PATH}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

# 版本信息（从 project.yml 读取或使用环境变量覆盖）
VERSION="${HOSTCAT_VERSION:-$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')}"
BUILD_NUMBER="${HOSTCAT_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo "📋 版本: ${VERSION} (build ${BUILD_NUMBER} · ${GIT_HASH})"

# 1. 清理目录
echo "🧹 清理旧构建目录..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 2. 生成 Xcode 工程
echo "🛠 生成 Xcode 工程..."
xcodegen generate -q

# 3. 注入 Git commit hash 到 App Info.plist
APP_PLIST="Sources/HostCatApp/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Set :HostCatBuildCommit ${GIT_HASH}" "$APP_PLIST"
echo "📝 已注入 Git hash: ${GIT_HASH}"

# 4. 归档 (Archive)
echo "📦 归档 App..."
xcodebuild archive \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}App" \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
    CODE_SIGN_STYLE=Manual \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    -quiet

# 5. 恢复 Info.plist 中的 HostCatBuildCommit 为默认值（避免污染 Git 工作区）
/usr/libexec/PlistBuddy -c "Set :HostCatBuildCommit dev" "$APP_PLIST"

# 6. 导出 (Export)
echo "📤 导出 App..."
sed "s/YOUR_TEAM_ID/${DEVELOPMENT_TEAM}/g" scripts/ExportOptions.plist > "$EXPORT_OPTIONS_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
    -exportPath "$EXPORT_PATH" \
    -quiet

# 7. 打包 DMG (使用 hdiutil)
echo "💿 创建 DMG..."
hdiutil create -volname "${APP_NAME}" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

echo "✅ 构建完成！"
echo "   版本: ${VERSION} (build ${BUILD_NUMBER} · ${GIT_HASH})"
echo "   DMG: $DMG_PATH"
