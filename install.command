#!/bin/sh
set -eu
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sh "$package_dir/scripts/install.sh"
echo '安装完成。请按 README 中的启动步骤打开额度条。'
