#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive=${1:-"$project_dir/dist/CodexQuotaBar-v0.1.0-macos-universal.zip"}
work_dir=$(mktemp -d "$project_dir/.build/install-test.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
mkdir -p "$work_dir/package with spaces" "$work_dir/mock-bin" "$work_dir/user home"
ditto -x -k "$archive" "$work_dir/package with spaces"
package_dir="$work_dir/package with spaces/CodexQuotaBar-v0.1.0-macos-universal"
binary="$package_dir/plugin/bin/Codex Quota Bar.app/Contents/MacOS/CodexQuotaBar"
codesign --verify --strict "$package_dir/plugin/bin/Codex Quota Bar.app"
xcrun lipo "$binary" -verify_arch arm64 x86_64
CODEX_QUOTA_CODEX_PATH="$project_dir/tests/mock-codex.py" "$binary" --probe > "$work_dir/probe.json"
export QUOTA_INSTALL_TEST_LOG="$work_dir/commands.log"
cat > "$work_dir/mock-bin/codex" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$QUOTA_INSTALL_TEST_LOG"
case "$*" in
  'plugin --help') echo 'plugin help' ;;
  'plugin list --json')
    if [ "${QUOTA_INSTALL_TEST_UPGRADE:-0}" = 1 ]; then
      printf '%s\n' '{"installed":[{"pluginId":"codex-quota-bar@wdk-local-plugins"},{"pluginId":"another-plugin@another-marketplace"}]}'
    else printf '%s\n' '{"installed":[]}'; fi ;;
  'plugin remove codex-quota-bar@wdk-local-plugins') ;;
  'plugin marketplace add '*) ;;
  'plugin add codex-quota-bar@wdk-local-plugins') ;;
  *) echo 'Unexpected command' >&2; exit 99 ;;
esac
MOCK
cat > "$work_dir/mock-bin/xcrun" <<'MOCK'
#!/bin/sh
echo '安装预编译包不应调用 Xcode。' >&2
exit 99
MOCK
# 只替换隔离副本的控制脚本，避免安装测试停止用户正在运行的额度条。
cat > "$package_dir/plugin/scripts/quota-bar.sh" <<'MOCK'
#!/bin/sh
test "$1" = stop
MOCK
chmod +x "$work_dir/mock-bin/codex" "$work_dir/mock-bin/xcrun"
CODEX_QUOTA_INSTALL_DIR="$work_dir/user home/Applications/CodexQuotaBar" PATH="$work_dir/mock-bin:/usr/bin:/bin:/usr/sbin:/sbin" sh "$package_dir/scripts/install.sh"
CODEX_QUOTA_INSTALL_DIR="$work_dir/user home/Applications/CodexQuotaBar" PATH="$work_dir/mock-bin:/usr/bin:/bin:/usr/sbin:/sbin" QUOTA_INSTALL_TEST_UPGRADE=1 sh "$package_dir/scripts/install.sh"
python3 - "$work_dir" <<'PY'
import json, sys
from pathlib import Path
root=Path(sys.argv[1])
installed=root/'user home/Applications/CodexQuotaBar'
assert (installed/'plugin/bin/Codex Quota Bar.app/Contents/MacOS/CodexQuotaBar').is_file()
assert (installed/'.agents/plugins/marketplace.json').is_file()
commands=(root/'commands.log').read_text().splitlines()
assert commands.count('plugin remove codex-quota-bar@wdk-local-plugins') == 1
assert not any('another-plugin' in command for command in commands)
assert json.loads((root/'probe.json').read_text())['fiveHour']['usedPercent'] == 27
print('通过：ZIP 解压、双架构与签名、打包后接口客户端、空格路径、首次安装、更新安装；无需 Xcode，不触碰其他插件。')
PY
