# agy-quota-context

Windows 桌面悬浮小球，实时显示 Antigravity (AGY) 桌面端的：

- 三环配额：5 小时 / 每周 / 额外额度剩余及重置时间
- 当前会话上下文占用（已用 / 上限 / 百分比）
- 当前会话名称（用于确认上下文计算对象正确）
- 全局热键 `Ctrl+Alt+Q`：等效鼠标悬停，弹出信息气泡，4 秒后自动收回

## 环境

- Windows + WSL（AGY 桌面端的 language server 运行在 WSL 内）
- WSL 内有 `python3` 与 `ss`
- Windows PowerShell 5+

## 使用

1. 克隆到 Windows 可访问目录（如 `D:\tools\agy-quota-context`）。
2. 双击 `start-ring.vbs` 启动；可自行创建指向 `wscript.exe "<路径>\start-ring.vbs"` 的快捷方式，图标选 `ring.ico`。
3. `python3 get_quota.py` 可在 WSL 中单独运行，输出 JSON。

## 原理与免责

`get_quota.py` 扫描本机 `language_server` 进程的 `--csrf_token` 与本地端口，调用 AGY 本地**非公开**接口。
仅访问 127.0.0.1，不上传任何数据；接口随 AGY 版本变化可能失效。非官方项目。

## License

MIT
