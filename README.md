# hook_bark

Claude Code 通知 hook：当 Claude 需要权限确认或完成耗时任务时，通过 macOS 桌面通知 + iPhone Bark 推送提醒用户。

## 文件

- `notify.sh` — Notification hook，权限确认时触发，翻译 message 后双通道推送
- `stop-notify.sh` — Stop hook，整轮任务结束时触发，仅当耗时 >30s 且使用了工具时推送

## 使用

详见 spec 和 plan（在本机 `/Users/hailei/Documents/vscode/docs/superpowers/`）。

开关（在 `~/.zshrc` 里定义）：
- `hookoff` — 关闭通知
- `hookon` — 开启通知
- `hookstatus` — 查看当前状态
