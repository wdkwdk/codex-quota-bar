#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/plugin/bin/Codex Quota Bar.app/Contents/Info.plist")
name="CodexQuotaBar-v$version-macos-universal"
stage="$project_dir/.build/package/$name"
binary="$project_dir/plugin/bin/Codex Quota Bar.app/Contents/MacOS/CodexQuotaBar"
xcrun lipo "$binary" -verify_arch arm64 x86_64
codesign --verify --strict "$project_dir/plugin/bin/Codex Quota Bar.app"
if [ -d "$stage" ]; then rm -rf "$stage"; fi
mkdir -p "$stage/plugin" "$stage/scripts" "$project_dir/dist"
for entry in .codex-plugin assets skills scripts bin; do
  ditto "$project_dir/plugin/$entry" "$stage/plugin/$entry"
done
ditto "$project_dir/.agents" "$stage/.agents"
ditto "$project_dir/docs" "$stage/docs"
cp "$project_dir/scripts/install.sh" "$stage/scripts/install.sh"
cp "$project_dir/install.command" "$project_dir/README.md" "$project_dir/LICENSE" "$stage/"
chmod +x "$stage/install.command"
ditto -c -k --keepParent "$stage" "$project_dir/dist/$name.zip"
(cd "$project_dir/dist" && shasum -a 256 "$name.zip" > SHA256SUMS.txt)
echo "安装包：$project_dir/dist/$name.zip"
