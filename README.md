# agy-quota-context

Windows 桌面悬浮小球，实时显示 Antigravity (AGY) 桌面端的：

- **三环配额**：5 小时 / 每周 / 额外额度剩余及重置时间
- **当前会话上下文占用**：已用 / 上限 / 百分比
- **当前会话名称**：确认上下文计算对象正确
- **全局热键 `Ctrl + Alt + Q`**：等效鼠标悬停，弹出详情气泡（4 秒自动收回）

---

## 适用环境与前提

- **Windows + WSL**：AGY 桌面端运行在 Windows，其 `language_server` 运行在 WSL 内
- WSL 内已安装 `python3` 与 `ss`（Ubuntu 等常见发行版默认自带）
- Windows PowerShell 5.1+（Windows 10/11 自带）
- **如需显示内环上下文与会话名**：需安装 [antigravity-desktop-context](https://github.com/dimitr-io/antigravity-desktop-context) 插件（未安装时仅显示外环配额）

---

## 快速开始（直接复制命令）

在你想存放工具的文件夹里 **Shift + 右键 → 在终端中打开（或在此处打开 PowerShell 窗口）**，也可以直接按 `Win + R` 输入 `powershell` 回车后按下面任一方式执行。

### 1. 下载项目

**方式 A：已装 Git**

```powershell
mkdir D:\tools -Force
cd D:\tools
git clone https://github.com/26kyo/agy-quota-context.git
cd agy-quota-context
```

**方式 B：不会用 / 没装 Git（直接下载 ZIP）**

```powershell
mkdir D:\tools -Force
cd D:\tools
Invoke-WebRequest https://github.com/26kyo/agy-quota-context/archive/refs/heads/main.zip -OutFile agy-quota-context.zip
Expand-Archive agy-quota-context.zip -DestinationPath . -Force
Rename-Item agy-quota-context-main agy-quota-context
Remove-Item agy-quota-context.zip
cd agy-quota-context
```

### 2. 检查默认 WSL 与数据抓取（推荐先测一下）

```powershell
wsl -l -v
```

确认带 `*` 号的默认 WSL 是你运行 AGY 的发行版（例如 `Ubuntu`，不要是 `docker-desktop`）。如不是，切换一下：

```powershell
wsl -s Ubuntu
```

保持 Antigravity 打开，测试数据是否能正常抓到：

```powershell
wsl --cd "$PWD" -e python3 get_quota.py
```

看到 `{"ok": true, ...}` 即表示环境正常。

### 3. 启动悬浮球

在当前 PowerShell 窗口运行（或直接双击文件夹里的 `start-ring.vbs`）：

```powershell
wscript.exe "$PWD\start-ring.vbs"
```

> 仅当 **Antigravity 主窗口可见且未最小化** 时悬浮球才会显示；最小化或关闭 AGY 时会自动隐藏。

---

## 日常使用与快捷键

- **移动位置**：右键悬浮球 → 取消勾选 **锁定位置** → 拖动到顺手的位置 → 再勾回 **锁定位置**（坐标保存在同目录 `pos.txt`）
- **查看详情**：鼠标移上悬浮球，或按全局快捷键 **`Ctrl + Alt + Q`**
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

生成的桌面快捷方式目标为 `wscript.exe`，可直接右键 **固定到任务栏**。

---

## 原理与免责声明

`get_quota.py` 扫描本机 `language_server` 进程的 `--csrf_token` 与本地端口，调用 AGY 本地**非公开**接口；仅访问 `127.0.0.1`，不上传任何数据。接口随 AGY 版本更新可能失效。非官方项目。

## License

MIT
