#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bundle="$project_dir/plugin/bin/Codex Quota Bar.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$project_dir/.build"
case "${1:-native}" in
  native) architectures=$(uname -m) ;;
  universal) architectures='arm64 x86_64' ;;
  *) echo '用法：build.sh [native|universal]' >&2; exit 2 ;;
esac
for architecture in $architectures; do
  xcrun swiftc -swift-version 5 -O -target "$architecture-apple-macosx13.0" \
    -module-cache-path "$project_dir/.build/module-cache" \
    "$project_dir/plugin/Sources/Quota.swift" \
    "$project_dir/plugin/Sources/CodexClient.swift" \
    "$project_dir/plugin/Sources/Overlay.swift" \
    "$project_dir/plugin/Sources/main.swift" \
    -o "$project_dir/.build/CodexQuotaBar-$architecture"
done
if [ "$architectures" = 'arm64 x86_64' ]; then
  xcrun lipo -create "$project_dir/.build/CodexQuotaBar-arm64" "$project_dir/.build/CodexQuotaBar-x86_64" \
    -output "$bundle/Contents/MacOS/CodexQuotaBar"
else
  cp "$project_dir/.build/CodexQuotaBar-$architectures" "$bundle/Contents/MacOS/CodexQuotaBar"
fi
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.wdk.codex-quota-bar</string>
<key>CFBundleName</key><string>Codex Quota Bar</string>
<key>CFBundleDisplayName</key><string>Codex 额度条</string>
<key>CFBundleExecutable</key><string>CodexQuotaBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$bundle"
echo "已构建：$bundle"
