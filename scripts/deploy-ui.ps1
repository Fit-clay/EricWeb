# Windows-only local publishing window. Credentials stay in the interactive SSH terminal.
[CmdletBinding()]
param([string]$PreviewPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$script:projectRoot = Split-Path $PSScriptRoot -Parent
$script:activeProcess = $null
$script:activeMode = ''
$script:configFile = Join-Path $script:projectRoot '.deploy.env'

function New-Label($Parent, $Text, $X, $Y, $Width, $Height, $Size = 10) {
    $control = New-Object Windows.Forms.Label
    $control.Text = $Text
    $control.SetBounds($X, $Y, $Width, $Height)
    $control.Font = New-Object Drawing.Font('Microsoft YaHei UI', $Size)
    $control.ForeColor = [Drawing.ColorTranslator]::FromHtml('#29364b')
    $Parent.Controls.Add($control)
    return $control
}
function New-Input($Parent, $X, $Y, $Width) {
    $control = New-Object Windows.Forms.TextBox
    $control.SetBounds($X, $Y, $Width, 30)
    $control.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
    $Parent.Controls.Add($control)
    return $control
}
function New-Button($Parent, $Text, $X, $Y, $Width, $Color = '#245be6') {
    $control = New-Object Windows.Forms.Button
    $control.Text = $Text
    $control.SetBounds($X, $Y, $Width, 42)
    $control.FlatStyle = 'Flat'
    $control.FlatAppearance.BorderSize = 0
    $control.BackColor = [Drawing.ColorTranslator]::FromHtml($Color)
    $control.ForeColor = [Drawing.Color]::White
    $control.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
    $Parent.Controls.Add($control)
    return $control
}
function Add-Event($Text) {
    $events.AppendText(('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $Text + [Environment]::NewLine))
}
function Quote-Argument([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }

$form = New-Object Windows.Forms.Form
$form.Text = '貔貅小库 · 发布管理'
$form.ClientSize = New-Object Drawing.Size(960, 730)
$form.MinimumSize = New-Object Drawing.Size(976, 769)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.ColorTranslator]::FromHtml('#f2f5fb')
$form.AutoScaleMode = 'Dpi'
$null = New-Label $form '发布管理' 30 22 600 42 23
$null = New-Label $form '本地构建，轻量上线。服务器只负责运行网站。' 33 70 850 27 10

$configPanel = New-Object Windows.Forms.Panel
$configPanel.SetBounds(30, 115, 900, 206)
$configPanel.BackColor = [Drawing.Color]::White
$form.Controls.Add($configPanel)
$null = New-Label $configPanel '服务器连接' 20 14 300 28 12
$null = New-Label $configPanel '服务器地址' 20 55 200 23
$hostBox = New-Input $configPanel 20 81 340
$null = New-Label $configPanel 'SSH 用户' 380 55 160 23
$userBox = New-Input $configPanel 380 81 165
$null = New-Label $configPanel '端口' 565 55 110 23
$portBox = New-Input $configPanel 565 81 100
$null = New-Label $configPanel '服务器架构' 685 55 180 23
$architecture = New-Object Windows.Forms.ComboBox
$architecture.SetBounds(685, 81, 190, 30)
$architecture.DropDownStyle = 'DropDownList'
$architecture.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
[void]$architecture.Items.AddRange(@('amd64 (常见 Intel / AMD)', 'arm64 (ARM 服务器)'))
$architecture.SelectedIndex = 0
$configPanel.Controls.Add($architecture)
$null = New-Label $configPanel 'SSH 私钥（可选；留空时在终端输入密码）' 20 125 600 23
$identityBox = New-Input $configPanel 20 151 720
$browse = New-Button $configPanel '选择文件' 755 146 120 '#60718c'

$fullPanel = New-Object Windows.Forms.Panel
$fullPanel.SetBounds(30, 341, 440, 167)
$fullPanel.BackColor = [Drawing.Color]::White
$form.Controls.Add($fullPanel)
$null = New-Label $fullPanel '全量更新' 20 15 380 28 14
$null = New-Label $fullPanel "在本机完成 Linux 构建与测试，上传网站和全部 HTML。`n需要本机 Docker Desktop，切换后自动检查运行状态。" 20 52 400 48 9
$fullButton = New-Button $fullPanel '构建并发布全部内容' 20 111 400
$htmlPanel = New-Object Windows.Forms.Panel
$htmlPanel.SetBounds(490, 341, 440, 167)
$htmlPanel.BackColor = [Drawing.Color]::White
$form.Controls.Add($htmlPanel)
$null = New-Label $htmlPanel '仅更新 HTML' 20 15 380 28 14
$null = New-Label $htmlPanel "上传 html-pages 中的所有页面、图片及其他资源。`n无需 Docker、无需编译，不重启网站；保留服务器额外页面。" 20 52 400 48 9
$htmlButton = New-Button $htmlPanel '上传 HTML 页面与资源' 20 111 400 '#16806a'

$status = New-Label $form '准备就绪' 32 526 830 27 11
$progress = New-Object Windows.Forms.ProgressBar
$progress.SetBounds(32, 558, 896, 5)
$form.Controls.Add($progress)
$events = New-Object Windows.Forms.TextBox
$events.SetBounds(32, 576, 896, 108)
$events.Multiline = $true
$events.ReadOnly = $true
$events.ScrollBars = 'Vertical'
$events.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)
$events.BackColor = [Drawing.Color]::White
$form.Controls.Add($events)
$null = New-Label $form '执行日志、SSH 密码和首次管理员设置会在独立终端中显示；密码不保存在本窗口。' 32 694 900 25 9

$defaults = @{ VPS_HOST = ''; VPS_SSH_USER = 'root'; VPS_SSH_PORT = '22' }
if (Test-Path -LiteralPath $script:configFile) {
    foreach ($line in Get-Content -LiteralPath $script:configFile -Encoding UTF8) {
        if ($line -match '^\s*(VPS_HOST|VPS_SSH_USER|VPS_SSH_PORT)\s*=\s*([^#]+)') {
            $defaults[$Matches[1]] = $Matches[2].Trim().Trim("'", '"')
        }
    }
}
$hostBox.Text = $defaults.VPS_HOST
$userBox.Text = $defaults.VPS_SSH_USER
$portBox.Text = $defaults.VPS_SSH_PORT
Add-Event '配置已读取。请确认服务器架构后选择更新方式。'

$browse.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = '选择 SSH 私钥'
    if ($dialog.ShowDialog() -eq 'OK') { $identityBox.Text = $dialog.FileName }
    $dialog.Dispose()
})
function Start-Publish([string]$Mode) {
    try {
        if ($hostBox.Text -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            $userBox.Text -cnotmatch '^[A-Za-z_][A-Za-z0-9_-]*$' -or
            $portBox.Text -notmatch '^\d{1,5}$' -or [int]$portBox.Text -lt 1 -or [int]$portBox.Text -gt 65535) {
            throw '请填写有效的服务器地址、SSH 用户和端口。'
        }
        if ($identityBox.Text -and -not (Test-Path -LiteralPath $identityBox.Text -PathType Leaf)) { throw '所选 SSH 私钥不存在。' }
        if ($Mode -eq 'Full' -and -not (Get-Command docker.exe -ErrorAction SilentlyContinue)) { throw '请先安装并启动 Docker Desktop（Linux 容器模式）。HTML 更新无需 Docker。' }
        if (-not (Test-Path -LiteralPath $script:configFile)) {
            Copy-Item -LiteralPath (Join-Path $script:projectRoot '.deploy.env.example') -Destination $script:configFile
        }
        $text = [IO.File]::ReadAllText($script:configFile)
        $updates = @{ VPS_HOST = $hostBox.Text; VPS_SSH_USER = $userBox.Text; VPS_SSH_PORT = $portBox.Text }
        foreach ($key in $updates.Keys) {
            $pattern = '(?m)^\s*' + $key + '\s*=.*$'
            if ([regex]::IsMatch($text, $pattern)) { $text = [regex]::Replace($text, $pattern, ($key + '=' + $updates[$key])) }
            else { $text += "`n$key=$($updates[$key])`n" }
        }
        [IO.File]::WriteAllText($script:configFile, ($text -replace "`r`n?", "`n"), (New-Object Text.UTF8Encoding($false)))
        $deployScript = Join-Path $script:projectRoot 'scripts\deploy-vps.ps1'
        $arch = if ($architecture.SelectedIndex -eq 0) { 'amd64' } else { 'arm64' }
        $command = '& ' + (Quote-Argument $deployScript) + ' -Mode ' + $Mode + ' -Architecture ' + $arch +
            ' -ConfigFile ' + (Quote-Argument $script:configFile)
        if ($identityBox.Text) { $command += ' -IdentityFile ' + (Quote-Argument $identityBox.Text) }
        $command = '$ErrorActionPreference = ''Stop''; try { ' + $command +
            '; exit 0 } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Read-Host ''发布失败。按回车关闭终端后，在发布窗口查看状态''; exit 1 }'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $script:activeProcess = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -WindowStyle Normal -PassThru
        $script:activeMode = if ($Mode -eq 'Full') { '全量更新' } else { 'HTML 更新' }
        foreach ($control in @($fullButton, $htmlButton, $hostBox, $userBox, $portBox, $architecture, $identityBox, $browse)) { $control.Enabled = $false }
        $status.Text = $script:activeMode + '进行中 · 请查看终端并按提示输入登录信息'
        $progress.Style = 'Marquee'
        Add-Event ($script:activeMode + '已启动。详细日志在终端中显示。')
    } catch {
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, '无法开始发布', 'OK', 'Information')
    }
}
$fullButton.Add_Click({ Start-Publish 'Full' })
$htmlButton.Add_Click({ Start-Publish 'Html' })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 800
$timer.Add_Tick({
    if ($script:activeProcess -and $script:activeProcess.HasExited) {
        $exitCode = $script:activeProcess.ExitCode
        $status.Text = if ($exitCode -eq 0) { $script:activeMode + '已完成' } else { $script:activeMode + '未完成，请检查终端中的错误信息' }
        Add-Event ($status.Text + '（退出码 ' + $exitCode + '）')
        $progress.Style = 'Blocks'
        $progress.Value = if ($exitCode -eq 0) { 100 } else { 0 }
        foreach ($control in @($fullButton, $htmlButton, $hostBox, $userBox, $portBox, $architecture, $identityBox, $browse)) { $control.Enabled = $true }
        $script:activeProcess.Dispose()
        $script:activeProcess = $null
    }
})
$timer.Start()
if ($PreviewPath) {
    # Render this application's own controls for offline layout checks; no publishing action runs.
    $bitmap = New-Object Drawing.Bitmap($form.Width, $form.Height)
    try {
        $form.Show()
        [Windows.Forms.Application]::DoEvents()
        $form.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bitmap.Save([IO.Path]::GetFullPath($PreviewPath), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose(); $timer.Dispose(); $form.Dispose() }
    return
}
try { [void]$form.ShowDialog() } finally { $timer.Stop(); $timer.Dispose(); $form.Dispose() }
