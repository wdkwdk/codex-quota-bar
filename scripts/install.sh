#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
install_dir=${CODEX_QUOTA_INSTALL_DIR:-"$HOME/Applications/CodexQuotaBar"}
if [ "$(uname -s)" != Darwin ]; then echo '仅支持 macOS 13 及以上版本。' >&2; exit 1; fi
codex_cli=$(command -v codex || true)
if [ -z "$codex_cli" ]; then
  for candidate in \
    '/Applications/Codex.app/Contents/Resources/codex' \
    '/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex' \
    '/Applications/ChatGPT.app/Contents/Resources/codex' \
    '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'; do
    if [ -x "$candidate" ]; then codex_cli=$candidate; break; fi
  done
fi
if [ -z "$codex_cli" ]; then echo '未找到 Codex CLI，请先安装并登录 Mac 版 Codex。' >&2; exit 1; fi
if ! "$codex_cli" plugin --help >/dev/null 2>&1; then
  echo '当前 Codex CLI 不支持插件，请先更新 Codex。' >&2; exit 1
fi
if [ ! -x "$project_dir/plugin/bin/Codex Quota Bar.app/Contents/MacOS/CodexQuotaBar" ]; then
  if [ ! -f "$project_dir/scripts/build.sh" ]; then echo '安装包不完整，请重新下载 Release ZIP。' >&2; exit 1; fi
  sh "$project_dir/scripts/build.sh"
fi
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-quota-install.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
"$codex_cli" plugin list --json > "$work_dir/plugins.json"
sh "$project_dir/plugin/scripts/quota-bar.sh" stop
mkdir -p "$install_dir"
if [ "$project_dir" != "$install_dir" ]; then
  ditto "$project_dir/plugin" "$install_dir/plugin"
  ditto "$project_dir/.agents" "$install_dir/.agents"
fi
if grep -Eq '"pluginId"[[:space:]]*:[[:space:]]*"codex-quota-bar@wdk-local-plugins"' "$work_dir/plugins.json"; then
  "$codex_cli" plugin remove codex-quota-bar@wdk-local-plugins
fi
"$codex_cli" plugin marketplace add "$install_dir"
"$codex_cli" plugin add codex-quota-bar@wdk-local-plugins
echo "已安装。新聊天可使用 @Codex 额度条 启动。"
printf '或执行：sh "%s/plugin/scripts/quota-bar.sh" start\n' "$install_dir"
