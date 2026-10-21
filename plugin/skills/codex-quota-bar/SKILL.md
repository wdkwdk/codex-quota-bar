---
name: codex-quota-bar
description: 启动、停止或检查本机 Mac 上的 Codex 额度条。用于这个插件的悬浮条管理，不用于修改账户额度或其他插件。
---

使用相对此技能目录的 `../../scripts/quota-bar.sh` 管理已打包的原生应用：

```sh
sh ../../scripts/quota-bar.sh start
sh ../../scripts/quota-bar.sh stop
sh ../../scripts/quota-bar.sh status
```

根据用户请求选择操作。仅在本机 Mac 桌面环境启动。启动成功后无需重复查询状态；失败时读取脚本返回的原因再诊断。

横条可直接拖动并记住相对位置，右键可选左上、右上、左下、底部居中或右下。单击打开额度详情与刷新按钮。

额度来自本机 Codex CLI 的 `account/rateLimits/read`，每分钟刷新并监听更新。无需额外 API Key；不读取或显示认证文件。缺失的窗口显示未知，读取失败或过期时不要把旧数字称为当前额度。
