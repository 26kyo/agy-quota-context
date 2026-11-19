# agy-quota-context

Windows 桌面悬浮小球，实时显示 Antigravity (AGY) 桌面端的：

- **三环配额**：5 小时 / 每周 / 额外额度剩余及重置时间
- **当前会话上下文占用**：已用 / 上限 / 百分比
- **当前会话名称**：确认上下文计算对象正确
- **全局热键 `Ctrl + Alt + Q`**：立即刷新并弹出详情气泡（4 秒自动收回，再按一次立即收回）
- **纯 Windows / Windows + WSL 自动识别**：同一套脚本开箱即用，无需手动切换模式

---

## Agent 接入指南（For AI Agents）

> 若你是替用户安装、验证或排查本工具的 Coding Agent，直接按本节顺序执行即可。

### 1. 自动识别规则

`ring.ps1` 每次抓取时自动判断 `language_server` 所在环境，**无需配置文件**：

| 检测条件（按顺序） | 命中模式 | 执行命令 | 依赖要求 |
| :--- | :--- | :--- | :--- |
| Windows 本机存在 `language_server*` 进程 | `windows`（纯 Windows） | 自动探测本机 `python3` → `python` → `py -3` 执行 `get_quota.py` | Windows 已装 Python 3（仅标准库，零第三方包） |
| 本机无 `language_server*` 且系统存在 `wsl.exe` | `wsl`（Windows + WSL） | `wsl.exe --cd "<repoDir>" -e python3 get_quota.py` | 默认 WSL 发行版内已装 `python3` 与 `ss` |
| 以上均不满足 | 无 | 界面提示 `AGY · AGY 未运行` | 启动 Antigravity 后自动恢复 |

> 切换纯 Windows 与 WSL 工作区时会自动切模式，无需重启悬浮球；当前命中的模式会记录在同目录 `ring.log`（`fetch mode=windows|wsl`）。

### 2. 仓库文件职责

| 文件 | 作用 |
| :--- | :--- |
| `start-ring.vbs` | 隐藏终端窗口启动 `ring.ps1` |
| `ring.ps1` | Windows WPF 悬浮球 UI、窗口置顶跟随、`Ctrl+Alt+Q` 热键、自动选路调用 `get_quota.py` |
| `get_quota.py` | 跨平台数据抓取器（Windows 用 CIM + `netstat`；Linux/WSL 用 `/proc` + `ss`），输出单行 JSON |
| `context_report.py` | 只读解析 `~/.gemini/antigravity/conversations/*.db` 计算上下文 token 占用 |
| `ring.ico` | 可选桌面快捷方式图标 |

### 3. 安装与验收步骤（PowerShell）

1. 将仓库拉取到目标目录（如 `D:\tools\agy-quota-context`）：
   ```powershell
   git clone https://github.com/26kyo/agy-quota-context.git D:\tools\agy-quota-context
   cd D:\tools\agy-quota-context
   ```
2. 确认 Antigravity 已打开，按环境验证数据抓取（**验收标准：stdout 返回 `{"ok": true, ...}`**）：
   - **纯 Windows**：
     ```powershell
     python3 get_quota.py
     # 若系统未提供 python3 别名，改用 python get_quota.py 或 py -3 get_quota.py
     ```
   - **Windows + WSL**：
     ```powershell
     wsl -l -v                     # 确认带 * 的默认发行版是运行 AGY 的发行版（必要时 wsl -s <Distro>）
     wsl -e python3 get_quota.py
     ```
3. 启动悬浮球：
   ```powershell
   wscript.exe start-ring.vbs
   ```

### 4. `get_quota.py` JSON 输出契约

成功：
```json
{
  "ok": true,
  "mode": "windows",
  "h": 85.0,
  "hReset": "21:30",
  "w": 92.5,
  "wReset": "11-24 08:00",
  "a": null,
  "aReset": "",
  "ctx": 34.2,
  "ctxUsed": "358k",
  "ctxLimit": "1.0M",
  "ctxTitle": "会话标题"
}
```

失败：
```json
{"ok": false, "mode": "windows", "err": "AGY 未运行"}
```

| 字段 | 说明 |
| :--- | :--- |
| `ok` | `true` / `false` |
| `mode` | 实际抓取环境：`windows` / `wsl` / `linux` |
| `h` / `hReset` | 5 小时配额剩余百分比与本地重置时间 |
| `w` / `wReset` | 每周配额剩余百分比与本地重置时间（为空时 UI 回退显示 `a` / `aReset`） |
| `ctx` / `ctxUsed` / `ctxLimit` / `ctxTitle` | 当前活跃会话上下文百分比、已用/上限 token、会话标题（可选，读取失败不影响配额显示） |

### 5. 排错对照表

| 现象 / 报错 | 根因与处理 |
| :--- | :--- |
| `AGY · 未找到 Python 3` | 纯 Windows 模式下未检测到可用的 Python 3（Windows Store 假占位符会被自动跳过）。安装 Python 3 并加入 `PATH`（或启用 `py` 启动器）。 |
| `AGY · AGY 未运行` | Antigravity 未启动；或 WSL 模式下 `wsl -l -v` 的默认发行版（带 `*`）不是运行 AGY 的发行版（执行 `wsl -s <Distro>`）。 |
| 纯 Windows 下 `language_server` 已运行但仍报 `AGY 未运行` | 权限不匹配：若 Antigravity 以管理员身份运行，非管理员进程读不到其命令行参数；需以同等权限启动 `start-ring.vbs` 或改用普通权限运行 Antigravity。 |
| 悬浮球不显示 | 仅在 Antigravity 主窗口可见且未最小化时显示；查看同目录 `ring.log` 获取实时状态。 |

---

## 快速开始（无 Git 方式）

在 **PowerShell**（不要用 `cmd.exe`）中执行：

```powershell
mkdir D:\tools -Force
cd D:\tools
Invoke-WebRequest https://github.com/26kyo/agy-quota-context/archive/refs/heads/main.zip -OutFile agy-quota-context.zip
Expand-Archive agy-quota-context.zip -DestinationPath . -Force
Rename-Item agy-quota-context-main agy-quota-context
Remove-Item agy-quota-context.zip
cd agy-quota-context
wscript.exe start-ring.vbs
```

---

## 日常使用与快捷键

- **移动位置**：右键悬浮球 → 取消勾选 **锁定位置** → 拖动到顺手的位置 → 再勾回 **锁定位置**（坐标保存在同目录 `pos.txt`）
- **查看详情 / 快捷键刷新**：鼠标移上悬浮球，或按全局快捷键 **`Ctrl + Alt + Q`**（立即刷新并弹出详情，4 秒自动收回）
- **立即刷新 / 退出**：右键悬浮球 → **立即刷新** / **退出**

### 创建桌面快捷方式（可选，方便固定到任务栏）

在 `agy-quota-context` 目录的 PowerShell 中执行：

```powershell
$s = (New-Object -ComObject WScript.Shell).CreateShortcut("$HOME\Desktop\AGY-Ring.lnk")
$s.TargetPath = "$env:WINDIR\System32\wscript.exe"
$s.Arguments = "`"$PWD\start-ring.vbs`""
$s.WorkingDirectory = "$PWD"
$s.IconLocation = "$PWD\ring.ico"
$s.Save()
```

---

## 原理与免责声明

`get_quota.py` 扫描本机 `language_server` 进程的 `--csrf_token` 与本地监听端口，显式绕过系统代理直连 `127.0.0.1`，调用 AGY 本地**非公开**接口；不上传任何数据。接口随 AGY 版本更新可能失效。非官方项目。

## 致谢

- 上下文数据库与 token 统计模块 `context_report.py` 来自 [antigravity-desktop-context](https://github.com/dimitr-io/antigravity-desktop-context)（MIT License, Copyright (c) 2026 Dimitrios Ioannidis）。

## License

MIT
