#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$project_dir/.build"
xcrun swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  "$project_dir/plugin/Sources/Quota.swift" "$project_dir/tests/ModelTests.swift" \
  -o "$project_dir/.build/model-tests"
"$project_dir/.build/model-tests"
for script in "$project_dir"/scripts/*.sh "$project_dir"/plugin/scripts/*.sh; do sh -n "$script"; done
echo '通过：Shell 语法检查。'
binary="$project_dir/plugin/bin/Codex Quota Bar.app/Contents/MacOS/CodexQuotaBar"
chmod +x "$project_dir/tests/mock-codex.py"
CODEX_QUOTA_CODEX_PATH="$project_dir/tests/mock-codex.py" "$binary" --probe > "$project_dir/.build/mock-quota.json"
/usr/bin/python3 - "$project_dir/.build/mock-quota.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data['fiveHour']['usedPercent'] == 27
assert data.get('weekly') is None
print('通过：真实客户端握手、分段 JSON、额度读取、子进程关闭。')
PY
if CODEX_QUOTA_CODEX_PATH="$project_dir/tests/mock-codex.py" QUOTA_TEST_ERROR=1 "$binary" --probe > "$project_dir/.build/mock-error.log" 2>&1; then
  echo '错误响应不应返回成功。' >&2; exit 1
fi
if /usr/bin/grep -q PRIVATE_ERROR_MARKER "$project_dir/.build/mock-error.log"; then
  echo '不应直接显示服务端原始错误。' >&2; exit 1
fi
echo '通过：错误状态与原始错误信息隔离。'
