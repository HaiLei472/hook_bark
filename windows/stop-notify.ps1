# Claude Code Stop hook (Windows): 任务完成（>30s 且用了工具）时通知
# 纯 PowerShell，不依赖 Python。对应 macOS 的 stop-notify.sh。

$ErrorActionPreference = 'SilentlyContinue'

# --- 总开关 ---
if (Test-Path "$env:USERPROFILE\.claude\.hooks-disabled") { exit 0 }

# --- 读 ntfy topic ---
$ntfyTopic = $null
$topicFile = "$env:USERPROFILE\.claude\.ntfy-topic"
if (Test-Path $topicFile) {
    $ntfyTopic = (Get-Content $topicFile -Raw).Trim()
}

# --- 强制 TLS 1.2 ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- 读 stdin JSON ---
$rawInput = [Console]::In.ReadToEnd()
try {
    $data = $rawInput | ConvertFrom-Json
    $transcriptPath = $data.transcript_path
} catch { exit 0 }

if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

# --- 解析 JSONL transcript（纯 PowerShell，不依赖 Python）---
$messages = @(Get-Content $transcriptPath |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } |
    Where-Object { $_ -and $_.type -in @('user', 'assistant') -and -not $_.isMeta })

if ($messages.Count -lt 2) { exit 0 }

# --- 找最后一条 user 消息（定义"本轮"的起点）---
$lastUserIdx = -1
for ($i = $messages.Count - 1; $i -ge 0; $i--) {
    if ($messages[$i].type -eq 'user') { $lastUserIdx = $i; break }
}
if ($lastUserIdx -lt 0) { exit 0 }

# --- 解析 timestamp（ISO 8601，含 Z 后缀）---
function Get-Ts($ts) {
    if (-not $ts) { return $null }
    try { return [datetimeoffset]::Parse($ts) } catch { return $null }
}

$userTs = Get-Ts $messages[$lastUserIdx].timestamp
$lastTs = Get-Ts $messages[$messages.Count - 1].timestamp
if (-not $userTs -or -not $lastTs) { exit 0 }

$duration = ($lastTs - $userTs).TotalSeconds
if ($duration -le 30) { exit 0 }

# --- 检测本轮 assistant 是否用了 tool（任意一个 tool_use 就算）---
$toolsUsed = $false
for ($i = $lastUserIdx + 1; $i -lt $messages.Count; $i++) {
    if ($messages[$i].type -ne 'assistant') { continue }
    $content = @($messages[$i].message.content)  # @() 强制数组（单元素也变数组，PS 5.1 需要）
    foreach ($block in $content) {
        if ($block.type -eq 'tool_use') { $toolsUsed = $true; break }
    }
    if ($toolsUsed) { break }
}
if (-not $toolsUsed) { exit 0 }

# --- 构造通知正文 ---
$notificationText = "Claude 已完成本轮任务（耗时 $([int]$duration)s）"

# --- 桌面通知（同 notify.ps1 的三级降级）---
function Send-DesktopNotification {
    param([string]$Title, [string]$Body)
    if (Get-Module -ListAvailable -Name BurntToast) {
        try {
            Import-Module BurntToast -ErrorAction SilentlyContinue
            New-BurntToastNotification -Text $Title, $Body -ErrorAction SilentlyContinue
            return
        } catch {}
    }
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $textNodes = $template.GetElementsByTagName('text')
        $textNodes.Item(0).AppendChild($template.CreateTextNode($Title)) | Out-Null
        $textNodes.Item(1).AppendChild($template.CreateTextNode($Body)) | Out-Null
        $toast = New-Object Windows.UI.Notifications.ToastNotification $template
        $aumid = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid).Show($toast)
    } catch {}
}

Send-DesktopNotification -Title 'Claude Code' -Body $notificationText

# --- ntfy 推送 ---
if ($ntfyTopic) {
    try {
        Invoke-RestMethod -Uri "https://ntfy.sh/$ntfyTopic" `
            -Method Post `
            -Body $notificationText `
            -Headers @{ 'Title' = 'Claude Code' } `
            -ContentType 'text/plain; charset=utf-8' `
            -TimeoutSec 5 | Out-Null
    } catch {}
}

exit 0
