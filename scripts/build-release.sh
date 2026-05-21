#!/bin/bash
set -e

# HostCat Release Build Script
# usage: ./scripts/build-release.sh

echo "🚀 开始构建 HostCat Release 版本..."

# 环境变量检查
if [ -z "$DEVELOPER_ID_APPLICATION" ]; then
    echo "⚠️ 未设置 DEVELOPER_ID_APPLICATION，将使用默认本地签名"
fi

APP_NAME="HostCat"
PROJECT_DIR=$(pwd)
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
APP_BUNDLE="${EXPORT_PATH}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

# 1. 清理目录
echo "🧹 清理旧构建目录..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 2. 生成 Xcode 工程
echo "🛠 生成 Xcode 工程..."
xcodegen generate -q

# 3. 归档 (Archive)
echo "📦 归档 App..."
xcodebuild archive \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}App" \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -archivePath "$ARCHIVE_PATH" \
    -quiet

# 4. 导出 (Export)
echo "📤 导出 App..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$EXPORT_PATH" \
    -quiet

# 5. 打包 DMG (使用 hdiutil)
echo "💿 创建 DMG..."
hdiutil create -volname "${APP_NAME}" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

echo "✅ 构建完成！DMG 路径: $DMG_PATH"
