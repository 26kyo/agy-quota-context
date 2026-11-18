Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$posFile = Join-Path $scriptDir "pos.txt"
$logFile = Join-Path $scriptDir "ring.log"

try {
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'ring\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
"$(Get-Date -Format 'HH:mm:ss') start PID=$PID" | Set-Content -Path $logFile -Encoding UTF8

[xml]$mainXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="44" Height="44"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="False" ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize">
    <Grid Width="44" Height="44">
        <Border x:Name="RootBorder" Width="36" Height="36" CornerRadius="9"
                Background="#E622211F" BorderBrush="#52514D" BorderThickness="1.2"
                Cursor="Arrow" RenderTransformOrigin="0.5,0.5">
            <Border.RenderTransform>
                <ScaleTransform x:Name="IconScale" ScaleX="1" ScaleY="1"/>
            </Border.RenderTransform>
            <Canvas Width="34" Height="34">
                <Path x:Name="TrackTop" Stroke="#3E3D3A" StrokeThickness="2.3" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                <Path x:Name="FillTop"  Stroke="#D8D7D4" StrokeThickness="2.3" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                <Path x:Name="TrackBot" Stroke="#3E3D3A" StrokeThickness="2.3" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                <Path x:Name="FillBot"  Stroke="#9E9D99" StrokeThickness="2.3" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                <Ellipse Width="10" Height="10" Canvas.Left="12" Canvas.Top="12" Stroke="#3E3D3A" StrokeThickness="2.0"/>
                <Path x:Name="FillCtx" Stroke="#6CB6FF" StrokeThickness="2.0" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
            </Canvas>
        </Border>
    </Grid>
</Window>
"@

[xml]$tipXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        SizeToContent="WidthAndHeight"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="False" ShowInTaskbar="False" ShowActivated="False" IsHitTestVisible="False">
    <Border x:Name="TipBorder" CornerRadius="11" Background="#F522211F" BorderBrush="#454440" BorderThickness="1"
            Padding="11,7" Margin="4" Opacity="0">
        <Border.RenderTransform>
            <TranslateTransform x:Name="TipSlide" X="-6"/>
        </Border.RenderTransform>
        <StackPanel>
            <TextBlock x:Name="RowTop" Text="5 小时 · 读取中..." Foreground="#E8E6E1" FontFamily="Microsoft YaHei UI, Segoe UI" FontSize="11.5"/>
            <TextBlock x:Name="RowBot" Text="每周 · 读取中..." Foreground="#B8B6B0" FontFamily="Microsoft YaHei UI, Segoe UI" FontSize="11.5" Margin="0,2,0,0"/>
            <TextBlock x:Name="RowCtx" Text="上下文 · 读取中..." Foreground="#B8B6B0" FontFamily="Microsoft YaHei UI, Segoe UI" FontSize="11.5" Margin="0,2,0,0"/>
            <TextBlock x:Name="RowTitle" Text="" Foreground="#8E8D88" FontFamily="Microsoft YaHei UI, Segoe UI" FontSize="10.5" Margin="0,3,0,0" MaxWidth="240" TextTrimming="CharacterEllipsis" Visibility="Collapsed"/>
        </StackPanel>
    </Border>
</Window>
"@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $mainXaml))
$tip = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $tipXaml))

$rootBorder = $win.FindName("RootBorder")
$iconScale  = $win.FindName("IconScale")
$trackTop   = $win.FindName("TrackTop")
$fillTop    = $win.FindName("FillTop")
$trackBot   = $win.FindName("TrackBot")
$fillBot    = $win.FindName("FillBot")
$fillCtx    = $win.FindName("FillCtx")
$tipBorder  = $tip.FindName("TipBorder")
$tipSlide   = $tip.FindName("TipSlide")
$rowTop     = $tip.FindName("RowTop")
$rowBot     = $tip.FindName("RowBot")
$rowCtx     = $tip.FindName("RowCtx")
$rowTitle   = $tip.FindName("RowTitle")

$script:lastData = $null
$script:hoverZone = "top"
$script:isHovered = $false

function New-ArcGeometry([double]$cx, [double]$cy, [double]$r, [double]$startDeg, [double]$sweepDeg) {
    if ([Math]::Abs($sweepDeg) -lt 0.5) { return $null }
    $capped = [Math]::Min(359.5, [Math]::Max(-359.5, $sweepDeg))
    $rad1 = $startDeg * [Math]::PI / 180.0
    $rad2 = ($startDeg + $capped) * [Math]::PI / 180.0
    $x1 = $cx + $r * [Math]::Cos($rad1)
    $y1 = $cy + $r * [Math]::Sin($rad1)
    $x2 = $cx + $r * [Math]::Cos($rad2)
    $y2 = $cy + $r * [Math]::Sin($rad2)

    $seg = New-Object System.Windows.Media.ArcSegment
    $seg.Point = New-Object System.Windows.Point($x2, $y2)
    $seg.Size = New-Object System.Windows.Size($r, $r)
    $seg.IsLargeArc = ([Math]::Abs($capped) -gt 180)
    $seg.SweepDirection = [System.Windows.Media.SweepDirection]::Clockwise

    $fig = New-Object System.Windows.Media.PathFigure
    $fig.StartPoint = New-Object System.Windows.Point($x1, $y1)
    $fig.Segments.Add($seg)

    $geo = New-Object System.Windows.Media.PathGeometry
    $geo.Figures.Add($fig)
    return $geo
}

function Start-Anim($target, $prop, [double]$to, [int]$ms) {
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.To = $to
    $anim.Duration = [TimeSpan]::FromMilliseconds($ms)
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $anim.EasingFunction = $ease
    $target.BeginAnimation($prop, $anim)
}

$trackTop.Data = New-ArcGeometry 17 17 11.5 -160 140
$trackBot.Data = New-ArcGeometry 17 17 11.5 20 140

function Update-TipText {
    $d = $script:lastData
    if (-not $d -or -not $d.ok) {
        $err = if ($d -and $d.err) { $d.err } else { "读取中..." }
        $rowTop.Text = "AGY · $err"
        $rowBot.Visibility = "Collapsed"
        $rowCtx.Visibility = "Collapsed"
        $rowTitle.Visibility = "Collapsed"
        return
    }

    $rowBot.Visibility = "Visible"
    $rowCtx.Visibility = "Visible"
    $hText = if ($null -ne $d.h) { "5 小时 · 剩余 $($d.h)%  ($($d.hReset))" } else { "5 小时 · --" }
    $wVal = if ($null -ne $d.w) { $d.w } else { $d.a }
    $wRes = if ($d.wReset) { $d.wReset } else { $d.aReset }
    $wText = if ($null -ne $wVal) { "每周   · 剩余 $wVal%  ($wRes)" } else { "每周   · --" }
    $cText = if ($null -ne $d.ctx) { "上下文 · 已用 $($d.ctx)%  ($($d.ctxUsed)/$($d.ctxLimit))" } else { "上下文 · --" }

    $rowTop.Text = $hText
    $rowBot.Text = $wText
    $rowCtx.Text = $cText
    if ($d.ctxTitle) {
        $rowTitle.Text = "会话   · $($d.ctxTitle)"
        $rowTitle.Visibility = "Visible"
    } else {
        $rowTitle.Text = ""
        $rowTitle.Visibility = "Collapsed"
    }

    $rowTop.Foreground = "#B8B6B0"; $rowTop.FontWeight = "Normal"
    $rowBot.Foreground = "#B8B6B0"; $rowBot.FontWeight = "Normal"
    $rowCtx.Foreground = "#B8B6B0"; $rowCtx.FontWeight = "Normal"

    if ($script:isHovered) {
        $fillBot.Stroke = "#9E9D99"
        $fillTop.StrokeThickness = 2.1
        $fillBot.StrokeThickness = 2.1
        $fillCtx.StrokeThickness = 1.9
        if ($script:hoverZone -eq "bot") {
            $fillBot.Stroke = "#F2F1EE"
            $fillBot.StrokeThickness = 2.7
            $rowBot.Foreground = "#FFFFFF"; $rowBot.FontWeight = "SemiBold"
        } elseif ($script:hoverZone -eq "center") {
            $fillCtx.StrokeThickness = 2.6
            $rowCtx.Foreground = "#FFFFFF"; $rowCtx.FontWeight = "SemiBold"
        } else {
            $fillTop.StrokeThickness = 2.7
            $rowTop.Foreground = "#FFFFFF"; $rowTop.FontWeight = "SemiBold"
        }
    } else {
        $fillTop.StrokeThickness = 2.3
        $fillBot.StrokeThickness = 2.3
        $fillCtx.StrokeThickness = 2.0
        $fillBot.Stroke = "#9E9D99"
    }
}

function Update-UI($data) {
    $script:lastData = $data
    if (-not $data -or -not $data.ok) {
        $fillTop.Data = $null
        $fillBot.Data = $null
        $fillCtx.Data = $null
        Update-TipText
        return
    }
    $h = if ($null -ne $data.h) { [Math]::Max(0, [Math]::Min(100, [double]$data.h)) } else { 0 }
    $wSrc = if ($null -ne $data.w) { $data.w } else { $data.a }
    $w = if ($null -ne $wSrc) { [Math]::Max(0, [Math]::Min(100, [double]$wSrc)) } else { 0 }
    $c = if ($null -ne $data.ctx) { [Math]::Max(0, [Math]::Min(100, [double]$data.ctx)) } else { 0 }

    $fillTop.Data = New-ArcGeometry 17 17 11.5 -160 (140.0 * $h / 100.0)
    $fillBot.Data = New-ArcGeometry 17 17 11.5 20 (140.0 * $w / 100.0)
    $fillCtx.Data = New-ArcGeometry 17 17 5.0 -90 (360.0 * $c / 100.0)

    if ($h -le 10) { $fillTop.Stroke = "#E05252" }
    elseif ($h -le 25) { $fillTop.Stroke = "#E5A93C" }
    else { $fillTop.Stroke = "#D8D7D4" }

    if ($c -ge 90) { $fillCtx.Stroke = "#E05252" }
    elseif ($c -ge 75) { $fillCtx.Stroke = "#E5A93C" }
    else { $fillCtx.Stroke = "#6CB6FF" }

    Update-TipText
}

$script:proc = $null
$pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$pollTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$pollTimer.add_Tick({
    if ($null -eq $script:proc) { $pollTimer.Stop(); return }
    if ($script:proc.HasExited) {
        $pollTimer.Stop()
        $out = $script:proc.StandardOutput.ReadToEnd().Trim()
        $script:proc.Dispose()
        $script:proc = $null
        try {
            if ($out) { Update-UI ($out | ConvertFrom-Json) }
        } catch {
            Update-UI $null
        }
    }
})

function Start-QuotaFetch {
    if ($null -ne $script:proc) { return }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = "--cd `"$scriptDir`" -e python3 get_quota.py"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8

    $script:proc = [System.Diagnostics.Process]::Start($psi)
    $pollTimer.Start()
}

$wa = [System.Windows.SystemParameters]::WorkArea
$win.Left = [Math]::Round(($wa.Left + $wa.Right - 44) / 2.0)
$win.Top = [Math]::Round(($wa.Top + $wa.Bottom - 44) / 2.0)
if (Test-Path $posFile) {
    $parts = (Get-Content $posFile -ErrorAction SilentlyContinue | Select-Object -First 1) -split ","
    if ($parts.Count -eq 2) {
        $lx = 0.0; $ly = 0.0
        if ([double]::TryParse($parts[0], [ref]$lx) -and [double]::TryParse($parts[1], [ref]$ly)) {
            $win.Left = [Math]::Max($wa.Left, [Math]::Min($wa.Right - 44, $lx))
            $win.Top  = [Math]::Max($wa.Top,  [Math]::Min($wa.Bottom - 44, $ly))
        }
    }
}

$positionTip = {
    $tip.UpdateLayout()
    $tip.Left = $win.Left + 44
    if ($tip.Left + $tip.ActualWidth -gt $wa.Right) {
        $tip.Left = $win.Left - $tip.ActualWidth
    }
    $tip.Top = $win.Top + ($win.Height - $tip.ActualHeight) / 2.0
}

$script:hotkeyActive = $false
$hotkeyHideTimer = New-Object System.Windows.Threading.DispatcherTimer
$hotkeyHideTimer.Interval = [TimeSpan]::FromSeconds(4)

function Enter-HoverUI {
    $wasHovered = $script:isHovered
    $script:isHovered = $true
    $rootBorder.Background = "#F52E2D2A"
    $rootBorder.BorderBrush = "#6E6D68"
    Start-Anim $iconScale ([System.Windows.Media.ScaleTransform]::ScaleXProperty) 1.14 140
    Start-Anim $iconScale ([System.Windows.Media.ScaleTransform]::ScaleYProperty) 1.14 140
    Update-TipText
    & $positionTip
    if (-not $wasHovered -or -not $tip.IsVisible) {
        $tipBorder.Opacity = 0
        $tipSlide.X = -6
        $tip.Show()
        Start-Anim $tipBorder ([System.Windows.UIElement]::OpacityProperty) 1.0 150
        Start-Anim $tipSlide ([System.Windows.Media.TranslateTransform]::XProperty) 0.0 150
    }
}

function Leave-HoverUI {
    $script:hotkeyActive = $false
    $hotkeyHideTimer.Stop()
    $script:isHovered = $false
    $rootBorder.Background = "#E622211F"
    $rootBorder.BorderBrush = "#52514D"
    Update-TipText
    Start-Anim $iconScale ([System.Windows.Media.ScaleTransform]::ScaleXProperty) 1.0 140
    Start-Anim $iconScale ([System.Windows.Media.ScaleTransform]::ScaleYProperty) 1.0 140
    $tip.Hide()
}

$hotkeyHideTimer.add_Tick({
    $hotkeyHideTimer.Stop()
    if ($script:hotkeyActive -and -not $rootBorder.IsMouseOver) {
        Leave-HoverUI
    }
})

$rootBorder.add_MouseEnter({
    $script:hotkeyActive = $false
    $hotkeyHideTimer.Stop()
    Enter-HoverUI
})

$rootBorder.add_MouseMove({
    param($s, $e)
    $pos = $e.GetPosition($rootBorder)
    $dx = $pos.X - 18.0
    $dy = $pos.Y - 18.0
    $zone = if (($dx * $dx + $dy * $dy) -le 56.25) { "center" } elseif ($pos.Y -lt 18) { "top" } else { "bot" }
    if ($zone -ne $script:hoverZone) {
        $script:hoverZone = $zone
        Update-TipText
        & $positionTip
    }
})

$rootBorder.add_MouseLeave({
    Leave-HoverUI
})

$script:locked = $true

$winRefs = @(
    [System.Windows.Interop.HwndSource].Assembly.Location,
    [System.Windows.Threading.Dispatcher].Assembly.Location
)
Add-Type -ReferencedAssemblies $winRefs -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;
public static class WinZ {
    public const uint GW_HWNDNEXT = 2;
    public const uint GW_HWNDPREV = 3;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_NOMOVE = 0x0002;
    public const uint SWP_NOSIZE = 0x0001;
    public const uint MOD_ALT = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_NOREPEAT = 0x4000;
    public const int WM_HOTKEY = 0x0312;
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public static event Action HotkeyPressed;
    public static void AttachHotkey(IntPtr hwnd) {
        var src = HwndSource.FromHwnd(hwnd);
        if (src != null) src.AddHook(WndProc);
    }
    private static IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) {
        if (msg == WM_HOTKEY && wParam.ToInt32() == 1) {
            handled = true;
            var cb = HotkeyPressed;
            if (cb != null) cb();
        }
        return IntPtr.Zero;
    }
}
"@

$rootBorder.add_MouseLeftButtonDown({
    if ($script:locked) { return }
    $tip.Hide()
    $win.DragMove()
    "$($win.Left),$($win.Top)" | Set-Content -Path $posFile -Encoding ASCII
})

$menu = New-Object System.Windows.Controls.ContextMenu
$miRefresh = New-Object System.Windows.Controls.MenuItem; $miRefresh.Header = "立即刷新"
$miRefresh.add_Click({ Start-QuotaFetch })
$miLock = New-Object System.Windows.Controls.MenuItem; $miLock.Header = "锁定位置"; $miLock.IsCheckable = $true; $miLock.IsChecked = $true
$miLock.add_Click({
    $script:locked = $miLock.IsChecked
    $rootBorder.Cursor = if ($script:locked) { "Arrow" } else { "Hand" }
})
$miExit = New-Object System.Windows.Controls.MenuItem; $miExit.Header = "退出"
$miExit.add_Click({ $ownerTimer.Stop(); $timer.Stop(); $pollTimer.Stop(); $hotkeyHideTimer.Stop(); if ($script:hkHwnd) { [WinZ]::UnregisterHotKey($script:hkHwnd, 1) | Out-Null }; $tip.Close(); $win.Close(); [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() })
[void]$menu.Items.Add($miRefresh)
[void]$menu.Items.Add($miLock)
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$menu.Items.Add($miExit)
$rootBorder.ContextMenu = $menu

function Sync-AgyZOrder {
    $agy = Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue |
           Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and [WinZ]::IsWindowVisible($_.MainWindowHandle) } |
           Select-Object -First 1
    if (-not $agy -or [WinZ]::IsIconic($agy.MainWindowHandle)) {
        $script:loggedShown = $false
        if (-not $script:loggedMissing) {
            $script:loggedMissing = $true
            $cnt = @(Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue).Count
            "$(Get-Date -Format 'HH:mm:ss') hidden: agyCount=$cnt" | Add-Content -Path $logFile -Encoding UTF8
        }
        if ($win.IsVisible) { Leave-HoverUI; $win.Hide() }
        return
    }
    $script:loggedMissing = $false
    if (-not $script:loggedShown) {
        $script:loggedShown = $true
        "$(Get-Date -Format 'HH:mm:ss') showing above hwnd=$($agy.MainWindowHandle)" | Add-Content -Path $logFile -Encoding UTF8
    }
    if (-not $win.IsVisible) { $win.Show() }

    $myHwnd = (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle
    $tipHwnd = (New-Object System.Windows.Interop.WindowInteropHelper $tip).Handle
    if ($myHwnd -eq [IntPtr]::Zero) { return }

    $next = [WinZ]::GetWindow($myHwnd, [WinZ]::GW_HWNDNEXT)
    if ($next -eq $tipHwnd) { $next = [WinZ]::GetWindow($next, [WinZ]::GW_HWNDNEXT) }
    if ($next -eq $agy.MainWindowHandle) { return }

    $prev = [WinZ]::GetWindow($agy.MainWindowHandle, [WinZ]::GW_HWNDPREV)
    while ($prev -eq $myHwnd -or $prev -eq $tipHwnd) {
        $prev = [WinZ]::GetWindow($prev, [WinZ]::GW_HWNDPREV)
    }
    [WinZ]::SetWindowPos($myHwnd, $prev, 0, 0, 0, 0, ([WinZ]::SWP_NOMOVE -bor [WinZ]::SWP_NOSIZE -bor [WinZ]::SWP_NOACTIVATE)) | Out-Null
}

$ownerTimer = New-Object System.Windows.Threading.DispatcherTimer
$ownerTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$ownerTimer.add_Tick({ Sync-AgyZOrder })
$ownerTimer.Start()

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(15)
$timer.add_Tick({ Start-QuotaFetch })
$timer.Start()

$script:tipOwnerBound = $false
$win.add_Loaded({
    if (-not $script:tipOwnerBound) {
        $tip.Owner = $win
        $script:tipOwnerBound = $true
    }
})
$script:hkHwnd = (New-Object System.Windows.Interop.WindowInteropHelper $win).EnsureHandle()
[WinZ]::AttachHotkey($script:hkHwnd)
[WinZ]::add_HotkeyPressed({
    if (-not $win.IsVisible) { return }
    if ($script:hotkeyActive) {
        Leave-HoverUI
    } else {
        $script:hotkeyActive = $true
        Enter-HoverUI
        $hotkeyHideTimer.Stop()
        $hotkeyHideTimer.Start()
    }
})
$hkOk = [WinZ]::RegisterHotKey($script:hkHwnd, 1, ([WinZ]::MOD_CONTROL -bor [WinZ]::MOD_ALT -bor [WinZ]::MOD_NOREPEAT), 0x51)
if (-not $hkOk) {
    "$(Get-Date -Format 'HH:mm:ss') hotkey Ctrl+Alt+Q register failed" | Add-Content -Path $logFile -Encoding UTF8
}

Sync-AgyZOrder
Start-QuotaFetch
[System.Windows.Threading.Dispatcher]::Run()
"$(Get-Date -Format 'HH:mm:ss') exit" | Add-Content -Path $logFile -Encoding UTF8
} catch {
    "$(Get-Date -Format 'HH:mm:ss') ERROR: $($_.Exception.ToString())" | Add-Content -Path $logFile -Encoding UTF8
}
