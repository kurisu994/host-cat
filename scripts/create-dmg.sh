#!/bin/bash
set -e

# HostCat DMG 打包脚本（带背景图和拖拽安装引导）
# 用法: ./scripts/create-dmg.sh <app_bundle_path> <output_dmg_path>
#
# 此脚本创建一个带有自定义背景、图标布局和 Applications 快捷方式的 DMG。
# 背景图中央有拖拽安装箭头，App 图标在左侧，Applications 文件夹在右侧。

APP_BUNDLE="${1:?用法: create-dmg.sh <HostCat.app 路径> <输出 DMG 路径>}"
DMG_OUTPUT="${2:?用法: create-dmg.sh <HostCat.app 路径> <输出 DMG 路径>}"

APP_NAME="HostCat"
VOL_NAME="${APP_NAME}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BG_IMAGE="${SCRIPT_DIR}/dmg-background.png"

# DMG 窗口尺寸（与背景图匹配，背景图 @2x 为 1320×800，窗口为 660×400）
WINDOW_W=660
WINDOW_H=400

# 图标位置（与背景图两侧虚线圆圈对准）
APP_ICON_X=180
APP_ICON_Y=210
APPS_ICON_X=480
APPS_ICON_Y=210
ICON_SIZE=100

# 验证输入
if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ App bundle 不存在: $APP_BUNDLE"
    exit 1
fi

if [ ! -f "$BG_IMAGE" ]; then
    echo "❌ DMG 背景图不存在: $BG_IMAGE"
    exit 1
fi

echo "💿 创建 DMG（带安装引导背景）..."

# 临时 DMG 路径
TMP_DMG="${DMG_OUTPUT}.tmp.dmg"
rm -f "$TMP_DMG" "$DMG_OUTPUT"

# 计算需要的 DMG 大小（App 大小 + 20MB 余量）
APP_SIZE_KB=$(du -sk "$APP_BUNDLE" | cut -f1)
DMG_SIZE_KB=$((APP_SIZE_KB + 20480))

# 1. 创建可读写的临时 DMG
echo "  📦 创建可写 DMG (${DMG_SIZE_KB} KB)..."
hdiutil create -size "${DMG_SIZE_KB}k" -fs HFS+ -volname "$VOL_NAME" "$TMP_DMG" -quiet

# 2. 挂载临时 DMG
echo "  📂 挂载 DMG..."
MOUNT_DIR=$(hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
MOUNT_POINT="/Volumes/${VOL_NAME}"

if [ ! -d "$MOUNT_POINT" ]; then
    echo "❌ DMG 挂载失败"
    exit 1
fi

# 3. 复制 App 和创建 Applications 快捷方式
echo "  📋 复制 ${APP_NAME}.app..."
cp -R "$APP_BUNDLE" "${MOUNT_POINT}/${APP_NAME}.app"
ln -s /Applications "${MOUNT_POINT}/Applications"

# 4. 设置背景图
echo "  🎨 设置背景图..."
mkdir -p "${MOUNT_POINT}/.background"
cp "$BG_IMAGE" "${MOUNT_POINT}/.background/dmg-background.png"

# 5. 使用 AppleScript 设置 Finder 窗口布局
echo "  🖼 配置 Finder 窗口布局..."
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, $((100 + WINDOW_W)), $((100 + WINDOW_H))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to ${ICON_SIZE}
        set background picture of viewOptions to file ".background:dmg-background.png"
        set position of item "${APP_NAME}.app" of container window to {${APP_ICON_X}, ${APP_ICON_Y}}
        set position of item "Applications" of container window to {${APPS_ICON_X}, ${APPS_ICON_Y}}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# 6. 设置自定义卷图标（使用 App 图标）
if [ -f "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" ]; then
    cp "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" "${MOUNT_POINT}/.VolumeIcon.icns"
    SetFile -c icnC "${MOUNT_POINT}/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "${MOUNT_POINT}" 2>/dev/null || true
fi

# 7. 确保 .DS_Store 被写入
sync

# 8. 卸载
echo "  💾 卸载 DMG..."
hdiutil detach "$MOUNT_POINT" -quiet || hdiutil detach "$MOUNT_POINT" -force -quiet

# 9. 转换为只读压缩格式
echo "  🗜 压缩 DMG..."
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUTPUT" -quiet

# 10. 清理临时文件
rm -f "$TMP_DMG"

echo "  ✅ DMG 创建完成: $DMG_OUTPUT"
