# hook_bark Windows + Android 配置引导（给 Claude Code 看的）

你的任务：用 AskUserQuestion 工具一步步引导用户完成 Windows + Android 配置。**一次只问一个问题，等用户回答后再问下一个。不要批量问。不要替我做决定。**

## 项目背景

hook_bark 的 Windows + Android 版。装好后：
- Claude Code 要权限确认时 -> 推送到用户 Android 手机（ntfy app）和 Windows 桌面 toast 通知
- Claude Code 跑完整轮任务（>30 秒且用了工具）-> 也推送

代码已克隆到 `~/.claude/hooks/windows/`（仓库的 windows 子目录），包括：
- `notify.ps1` -- Notification hook 脚本（PowerShell）
- `stop-notify.ps1` -- Stop hook 脚本（PowerShell，纯 PS 解析，不依赖 Python）

> 路径说明：Windows 上 `~` 等于 `$env:USERPROFILE`（通常是 `C:\Users\你的用户名`）。所有 `~/.claude/...` 路径在 Windows 上就是 `C:\Users\你的用户名\.claude\...`。

## 你要按顺序做的事

### 步骤 1：环境检查

读取 `$env:USERPROFILE\.claude\hooks\windows\` 目录，确认有 `notify.ps1` 和 `stop-notify.ps1`。
- 如果脚本缺失：停止引导，告诉用户重新 clone：
  ```powershell
  git clone git@github.com:HaiLei472/hook_bark.git "$env:USERPROFILE\.claude\hooks"
  ```
- 确认在 Windows 上：`$env:OS` 应该是 `Windows_NT`。如果不是，停止引导并提示用户用 macOS 版（`hook_bark/SETUP.md`）。

### 步骤 2：确认 ntfy Android App

用 AskUserQuestion 问：你 Android 手机上装好 ntfy App 了吗？
- 装好了 -> 下一步
- 还没装 -> 告诉用户：Google Play 搜 "ntfy" 安装（或 F-Droid）。等用户装好再继续。

### 步骤 3：生成 ntfy topic

给用户说明（重要）：
> ntfy 的 topic 名就像你的"频道地址"。**跟 Bark 不同：谁知道了你的 topic 名，谁就能给你手机推送。** 所以 topic 名要当密码用--够长、够随机。

生成一个随机 topic（PowerShell 命令）：
```powershell
"claude-code-$([guid]::NewGuid().ToString('N').Substring(0,8))"
```
把生成的 topic（形如 `claude-code-7a3f9b2e`）展示给用户。

用 AskUserQuestion 问：用这个随机 topic 吗？
- 用这个（推荐）
- 我自己起名

如果用户自己起名：检查只含字母/数字/下划线/连字符，长度 ≤ 64。不合法就提示重新起。

记住最终选定的 topic（后续步骤要用，替换所有 `<topic>` 占位符）。

### 步骤 4：在手机上订阅 topic

引导用户：
1. 打开 Android 上的 ntfy App
2. 点右下角 + 号
3. 输入刚才选定的 topic 名（不带任何前缀，就 `claude-code-xxxx` 这种纯名字）
4. 点订阅

用 AskUserQuestion 确认：订阅成功了吗？
- 成功 -> 下一步
- 失败 -> 排查（topic 名拼写、ntfy App 是否登录等）

### 步骤 5：测试 topic（发一条测试推送）

跑这条命令（把 `<topic>` 换成实际 topic）：
```powershell
Invoke-RestMethod -Uri "https://ntfy.sh/<topic>" -Method Post -Body "hook_bark 配置测试" -Headers @{ "Title" = "Claude Code" }
```

用 AskUserQuestion 问：手机收到推送了吗？
- 收到了 -> topic 配置正确，下一步
- 没收到 -> 排查：
  - topic 名拼写对不对
  - ntfy App 的通知权限开了没（Android 设置 -> 应用 -> ntfy -> 通知）
  - 手机是不是开了勿扰/专注模式
  - 网络能不能访问 ntfy.sh（浏览器打开 https://ntfy.sh/<topic> 看看有没有返回 JSON）

### 步骤 6：写入 .ntfy-topic 文件

跑（把 `<topic>` 换成实际 topic）：
```powershell
Set-Content -Path "$env:USERPROFILE\.claude\.ntfy-topic" -Value "<topic>" -NoNewline
```

验证：
```powershell
Get-Content "$env:USERPROFILE\.claude\.ntfy-topic"
```
应该输出 topic 名。

**这步在干嘛**：把 topic 名存到一个文件里，脚本运行时读这个文件拿 topic。文件在 `~/.claude/`，不会进 git。

### 步骤 7：（可选）安装 BurntToast 做 Windows 桌面通知

说明：桌面通知需要 BurntToast 模块（不装的话手机推送照常工作，只是桌面可能没通知）。

用 AskUserQuestion 问：要不要装 BurntToast 来获得 Windows 桌面通知？
- 装（推荐）-> 继续下面的安装步骤
- 不装 -> 跳到步骤 8，告诉用户桌面通知可能不显示，但手机推送不受影响

如果装：
1. 先看执行策略：
   ```powershell
   Get-ExecutionPolicy
   ```
   - 如果是 `Restricted`，用 AskUserQuestion 确认用户同意改执行策略，同意后跑：
     ```powershell
     Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
     ```
2. 装模块：
   ```powershell
   Install-Module BurntToast -Scope CurrentUser -Force
   ```
   如果提示要装 NuGet provider，按 Y 同意。
3. 验证：
   ```powershell
   Get-Module -ListAvailable BurntToast
   ```
   应该列出 BurntToast。
4. 测试 toast：
   ```powershell
   New-BurntToastNotification -Text "测试", "BurntToast 装好了"
   ```
   Windows 桌面应该弹个通知。用 AskUserQuestion 确认用户看到了。

### 步骤 8：修改 settings.json

读取 `$env:USERPROFILE\.claude\settings.json`。
- 如果文件不存在，创建一个 `{}`。
- 读取现有内容，**保留所有现有字段**（如 `env`、`model`、`permissions` 等原样不动）。

新增/替换 `hooks` 字段为 Windows 版（exec form，绕过执行策略）：
```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe",
            "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "& \"$env:USERPROFILE/.claude/hooks/windows/notify.ps1\""]
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe",
            "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "& \"$env:USERPROFILE/.claude/hooks/windows/stop-notify.ps1\""]
          }
        ]
      }
    ]
  }
}
```

**关键点**：
- 只动 `hooks` 字段，其他现有字段原样保留
- 如果已有 `hooks` 字段，先用 AskUserQuestion 告诉用户要替换旧值，确认后再写
- 注意 JSON 转义：`\"` 是必须的（PowerShell 命令里的双引号要在 JSON 里转义）

用 AskUserQuestion 让用户确认要写入。

写入后验证 JSON：
```powershell
try { Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json | Out-Null; "JSON OK" } catch { "JSON ERROR: $_" }
```
看到 `JSON OK` 才继续。如果是 `JSON ERROR`，检查逗号和引号。

### 步骤 9：配置 PowerShell profile（hookoff/on/status）

用 AskUserQuestion 问：要不要加 hookoff/hookon/hookstatus 三个快捷命令？
- 要 -> 继续下面的步骤
- 不要 -> 跳到步骤 10

如果要：
1. 看 `$PROFILE` 路径：
   ```powershell
   $PROFILE
   ```
2. 如果文件不存在，创建：
   ```powershell
   if (-not (Test-Path $PROFILE)) { New-Item -Path $PROFILE -ItemType File -Force }
   ```
3. 检查是否已有 hookoff function：
   ```powershell
   Select-String -Path $PROFILE -Pattern "function hookoff"
   ```
   - 如果有匹配：告诉用户已经配过，跳过
   - 如果没匹配：追加这段：
     ```powershell
     Add-Content -Path $PROFILE -Value @'

     # Claude Code hooks on/off switch
     function hookoff {
         New-Item -Path "$env:USERPROFILE\.claude\.hooks-disabled" -ItemType File -Force | Out-Null
         Write-Host "hooks off"
     }
     function hookon {
         Remove-Item -Path "$env:USERPROFILE\.claude\.hooks-disabled" -Force -ErrorAction SilentlyContinue
         Write-Host "hooks on"
     }
     function hookstatus {
         if (Test-Path "$env:USERPROFILE\.claude\.hooks-disabled") { Write-Host "off" } else { Write-Host "on" }
     }
     '@
     ```
4. 告诉用户：重开 PowerShell 窗口，或者跑 `. $PROFILE` 重新加载。然后测试：
   ```powershell
   hookstatus    # 应该输出: on
   hookoff       # 关
   hookstatus    # 应该输出: off
   hookon        # 开
   ```

### 步骤 10：实测

跑这条命令模拟一个 Notification 事件：
```powershell
'{"message":"Claude needs your permission to use Bash"}' | powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& \"$env:USERPROFILE/.claude/hooks/windows/notify.ps1\""
```

用 AskUserQuestion 问：手机和桌面分别收到通知了吗？
- 两个都收到 -> 配置成功，下一步
- 只收到手机 -> 桌面通知问题：检查 BurntToast 是否装了（步骤 7）、Windows 通知权限
- 只收到桌面 -> 手机推送问题：检查 topic 名、ntfy App 订阅、网络
- 都没收到 -> 排查：
  - `.ntfy-topic` 文件存在且内容正确：`Get-Content "$env:USERPROFILE\.claude\.ntfy-topic"`
  - settings.json 的 JSON OK（步骤 8 的验证命令）
  - 脚本路径对不对
  - 直接跑脚本看报错：`'{"message":"test"}' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\hooks\windows\notify.ps1"`

### 步骤 11：完成提醒

告诉用户：
- 配置完成！
- **必须重启 Claude Code 会话**，新 hook 才会生效（settings.json 只在启动时读）
- 正常用法：Claude 要权限时手机响 + 桌面弹；长任务（>30s 且用了工具）跑完也响
- 开关命令：`hookoff` / `hookon` / `hookstatus`
- 调阈值：`stop-notify.ps1` 里 `if ($duration -le 30)` 改大
