#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
plugin_dir=$(dirname -- "$script_dir")
app_bundle="$plugin_dir/bin/Codex Quota Bar.app"
action=${1:-status}

running_pids() { pgrep -x CodexQuotaBar 2>/dev/null || true; }

case "$action" in
  start|Start)
    if [ -n "$(running_pids)" ]; then echo 'Codex 额度条已在运行。'; exit 0; fi
    if [ ! -x "$app_bundle/Contents/MacOS/CodexQuotaBar" ]; then
      echo '缺少已编译的 Mac 应用，请先运行项目的 scripts/build.sh。' >&2
      exit 1
    fi
    open "$app_bundle"
    attempts=0
    while [ "$attempts" -lt 40 ]; do
      if [ -n "$(running_pids)" ] && [ -f "$HOME/Library/Application Support/CodexQuotaBar/status.json" ]; then
        sleep 0.5
        if [ -n "$(running_pids)" ]; then echo 'Codex 额度条已启动。拖动调整位置，右键打开菜单。'; exit 0; fi
      fi
      attempts=$((attempts + 1))
      sleep 0.2
    done
    echo '应用未能保持运行，请检查本机 Mac 桌面环境。' >&2
    exit 1
    ;;
  stop|Stop)
    pids=$(running_pids)
    if [ -n "$pids" ]; then
      kill $pids
      attempts=0
      while [ -n "$(running_pids)" ] && [ "$attempts" -lt 25 ]; do
        attempts=$((attempts + 1)); sleep 0.2
      done
      if [ -n "$(running_pids)" ]; then echo '应用尚未退出。' >&2; exit 1; fi
    fi
    echo 'Codex 额度条已停止。'
    ;;
  status|Status)
    if [ -n "$(running_pids)" ]; then echo 'Codex 额度条正在运行。'; else echo 'Codex 额度条未运行。'; fi
    ;;
  *) echo '用法：quota-bar.sh start|stop|status' >&2; exit 2 ;;
esac
