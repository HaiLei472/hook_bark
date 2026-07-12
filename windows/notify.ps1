# Claude Code Notification hook (Windows): desktop toast + ntfy push
# 对应 macOS 的 notify.sh。Windows 10/11 + PowerShell 5.1。

$ErrorActionPreference = 'SilentlyContinue'

# --- 总开关（hookoff 时跳过）---
if (Test-Path "$env:USERPROFILE\.claude\.hooks-disabled") { exit 0 }

# --- 读 ntfy topic（没有就只发桌面通知，不推手机）---
$ntfyTopic = $null
$topicFile = "$env:USERPROFILE\.claude\.ntfy-topic"
if (Test-Path $topicFile) {
    $ntfyTopic = (Get-Content $topicFile -Raw).Trim()
}

# --- 强制 TLS 1.2（PowerShell 5.1 默认 TLS 1.0，连不上 ntfy.sh）---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- 读 stdin JSON ---
$rawInput = [Console]::In.ReadToEnd()
try {
    $data = $rawInput | ConvertFrom-Json
    $text = $data.message
} catch {
    $text = $null
}
if (-not $text) { $text = "Claude 需要你的输入" }

# --- 中英翻译（PowerShell -replace 用 $1 不是 \1）---
$translated = $text
$patterns = @(
    @{ Pattern = '^Claude needs your permission to use (\w+) to (.+)$'; Replace = 'Claude 需要你授权使用 $1 来 $2' },
    @{ Pattern = '^Claude needs your permission to use (\w+)$'; Replace = 'Claude 需要你授权使用 $1' },
    @{ Pattern = '^Claude is waiting for your input$'; Replace = 'Claude 正在等待你的输入' }
)
foreach ($p in $patterns) {
    if ($translated -match $p.Pattern) {
        $translated = $translated -replace $p.Pattern, $p.Replace
        break
    }
}

# --- Windows 桌面通知（best effort，三级降级）---
function Send-DesktopNotification {
    param([string]$Title, [string]$Body)
    # 1. BurntToast 模块（首选，自动处理 AUMID/快捷方式）
    if (Get-Module -ListAvailable -Name BurntToast) {
        try {
            Import-Module BurntToast -ErrorAction SilentlyContinue
            New-BurntToastNotification -Text $Title, $Body -ErrorAction SilentlyContinue
            return
        } catch {}
    }
    # 2. 原生 WinRT Toast（降级，可能图标是 PowerShell）
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $textNodes = $template.GetElementsByTagName('text')
        $textNodes.Item(0).AppendChild($template.CreateTextNode($Title)) | Out-Null
        $textNodes.Item(1).AppendChild($template.CreateTextNode($Body)) | Out-Null
        $toast = New-Object Windows.UI.Notifications.ToastNotification $template
        # PowerShell 的系统 AUMID（Win10/11 都注册了）
        $aumid = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid).Show($toast)
    } catch {}
    # 3. 都失败就静默（手机推送是主渠道，不影响）
}

Send-DesktopNotification -Title 'Claude Code' -Body $translated

# --- ntfy 推送（有 topic 才推，同步 + 5s 超时；ntfy.sh 很快）---
if ($ntfyTopic) {
    try {
        Invoke-RestMethod -Uri "https://ntfy.sh/$ntfyTopic" `
            -Method Post `
            -Body $translated `
            -Headers @{ 'Title' = 'Claude Code' } `
            -ContentType 'text/plain; charset=utf-8' `
            -TimeoutSec 5 | Out-Null
    } catch {}
}

exit 0
