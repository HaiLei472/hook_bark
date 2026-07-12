# hook_bark_ios (Windows + Android edition)

**In one sentence**: Get pinged on your Android phone and Windows desktop whenever Claude Code is waiting on you or has finished a long task.

This is the Windows + Android edition of hook_bark_ios. For macOS + iPhone, see the [root README](../README.md).

---

## What problem does this solve?

Same as the macOS version: you stop checking back on Claude Code only to find it idle or already done. When Claude is blocked on a permission prompt or has finished a task, this pushes to your Android phone (via ntfy) and your Windows desktop (Toast notification).

---

## Who is this for?

✅ A good fit if you:
- Run Claude Code on a Windows 10/11 PC
- Have an Android phone
- Regularly run tasks that take more than 30 seconds

❌ Not a good fit if you're on:
- macOS + iPhone (use the [macOS edition](../README.md) instead)
- Linux (not yet supported)
- iPhone (Bark has no Android version)

---

## Prerequisites

| Need | How |
|---|---|
| Windows 10 or 11 | - |
| PowerShell 5.1 (preinstalled on Win10/11) | - |
| Claude Code installed and working | - |
| ntfy Android app (free) | Play Store -> search "ntfy" -> install |

Optional (for desktop toast notifications):
- BurntToast PowerShell module - the setup will offer to install it for you. Without it, the script falls back to native WinRT toast (may show with a PowerShell icon or not at all); phone push is unaffected.

---

## Repository layout (Windows-relevant)

```
~/.claude/hooks/
└── windows/
    ├── README.md           ← this file
    ├── SETUP.md            ← config guide for Claude Code
    ├── notify.ps1          ← fires on permission needed
    └── stop-notify.ps1     ← fires when a task finishes
```

Scripts live under `~/.claude/hooks/windows/`. Config files (`.ntfy-topic`, `.hooks-disabled`) go in `~/.claude/` (your user profile). On Windows, `~` = `%USERPROFILE%` = `C:\Users\<you>`.

---

## How to install

**Recommended: let Claude Code guide you.**

After cloning the repo, open Claude Code on your Windows PC and paste:

```
Read ~/.claude/hooks/windows/SETUP.md and guide me step by step through configuring hook_bark for Windows + Android, strictly following the steps inside. Use the AskUserQuestion tool to ask one question at a time, and wait for my answer before continuing. Don't batch questions. Don't make decisions for me.
```

Claude Code will walk you through: installing the ntfy app, picking a topic, subscribing on your phone, testing the push, writing the config, and (optionally) installing BurntToast for desktop notifications.

**Manual install**: follow the steps in [SETUP.md](SETUP.md) yourself.

---

## ntfy topic security (read this)

ntfy works differently from Bark:

- **Bark** (iOS): your **key** is private. Only you can push to your phone.
- **ntfy** (Android): your **topic** is a channel address. **Anyone who knows the topic name can push to your phone.**

So treat your topic name like a password:
- Use a long, random topic (the setup generates `claude-code-<random hex>` for you)
- Don't screenshot or share the topic name
- The topic is stored in `~/.claude/.ntfy-topic` (gitignored)

---

## Troubleshooting

### No notifications at all

1. **Topic file present?**
   ```powershell
   Get-Content "$env:USERPROFILE\.claude\.ntfy-topic"
   ```
   Should print a topic string. Empty/error -> redo the setup step.

2. **Switch off?**
   ```powershell
   hookstatus
   ```
   If `off`, run `hookon`.

3. **Restarted Claude Code?** `settings.json` is loaded at startup; the current session won't pick up new hooks.

### Phone silent

Test the topic directly:
```powershell
Invoke-RestMethod -Uri "https://ntfy.sh/<your-topic>" -Method Post -Body "test" -Headers @{ "Title" = "test" }
```
- Phone rings -> topic works; problem is in the scripts.
- No ring -> topic name wrong, or ntfy app notifications disabled, or phone in Focus mode.

### Desktop toast silent

1. **BurntToast installed?**
   ```powershell
   Get-Module -ListAvailable BurntToast
   ```
   If empty, install it:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser   # if not already
   Install-Module BurntToast -Scope CurrentUser -Force
   ```

2. **Windows Focus Assist / Do Not Disturb on?** Turn it off in Settings.

3. Without BurntToast, the script falls back to native WinRT toast using PowerShell's system AUMID. It may show with a PowerShell icon or not appear at all. Installing BurntToast fixes both.

### PowerShell "running scripts is disabled"

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```
(The hook command uses `-ExecutionPolicy Bypass` so it doesn't actually need this, but installing BurntToast does.)

### Phone won't stop ringing

```powershell
hookoff
```
Then raise the trigger threshold - in `~/.claude/hooks/windows/stop-notify.ps1`, find `if ($duration -le 30)` and bump `30` to `60` or `120`.

---

## Tweaks

| Want to change | Where |
|---|---|
| ntfy topic | `~/.claude/.ntfy-topic` file |
| Stop threshold (default 30 s) | `if ($duration -le 30)` in `stop-notify.ps1` |
| ntfy title (default "Claude Code") | `'Title' = 'Claude Code'` in the scripts |
| Desktop toast title | `Send-DesktopNotification -Title 'Claude Code'` in the scripts |

---

## License

MIT - use freely, issues welcome.
