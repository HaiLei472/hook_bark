# hook_bark_ios

**In one sentence**: Get pinged on your iPhone and Mac whenever Claude Code is waiting on you or has finished a long task — so you stop checking back to find it idle.

[中文文档](hook_bark/README.md) · [配置引导 (SETUP.md)](hook_bark/SETUP.md)

---

## What problem does this solve?

When using Claude Code, you hit two kinds of dead time:

**Case 1 — Claude is waiting on your permission**

You ask Claude to delete a file or run a command, and it pops up: "Can I use Bash?". You've tabbed away to check something, glanced at your phone, gone to refill water — half an hour later you come back and it's still sitting there. Nothing happened.

**Case 2 — Claude finished a long task and you didn't notice**

You ask Claude to analyze a big file, install a pile of dependencies, run a test suite — tens of seconds to several minutes. You switch to something else, come back, and find it finished ages ago. You burned 5 minutes waiting for nothing.

**hook_bark_ios fixes this**: when Claude is blocked or done, it pushes to your phone (iPhone via the Bark app) and your Mac (desktop notification), so you always know its state without babysitting it.

---

## Who is this for?

✅ A good fit if you:
- Run Claude Code tasks that regularly take more than 30 seconds
- Are on a Mac
- Have an iPhone

❌ Not a good fit if you're on:
- Windows / Linux (the scripts are macOS-only)
- Android (Bark is iPhone-only)
- Only occasional short chats with Claude (won't trigger, so it'd go unused)

---

## Prerequisites

| Need | How |
|---|---|
| A Mac | — |
| An iPhone | — |
| Claude Code installed and working | — |
| Bark app (free) | App Store on iPhone → search "Bark" → install |

---

## Repository layout

The repo is cloned into `~/.claude/hooks/`. Two layers:

- **Repo root (`~/.claude/hooks/`)** — the scripts that actually run: `notify.sh`, `stop-notify.sh`
- **`hook_bark/` subfolder** — docs only: the Chinese `README.md` and `SETUP.md` (the config guide Claude Code reads)

Everything in the project lives under the `hooks/` folder.

```
~/.claude/hooks/
├── README.md           ← English README (this file)
├── notify.sh           ← fires on permission needed
├── stop-notify.sh      ← fires when a task finishes
└── hook_bark/
    ├── README.md       ← Chinese README
    └── SETUP.md        ← config guide for Claude Code
```

---

## How to install

Two methods. **Method 1 is strongly recommended** — let Claude Code walk you through it, no manual file editing.

### Method 1 — Claude Code guided setup (recommended)

**Step 1. Download the code**

Open the macOS Terminal (`Cmd + Space`, type "Terminal", enter), paste this, hit enter:

```bash
git clone git@github.com:HaiLei472/hook_bark.git ~/.claude/hooks
```

If it says "destination path already exists", back it up first:
```bash
mv ~/.claude/hooks ~/.claude/hooks.bak
git clone git@github.com:HaiLei472/hook_bark.git ~/.claude/hooks
```

**Step 2. Let Claude Code do the rest**

Open Claude Code (any directory), paste this prompt, hit enter:

```
Read ~/.claude/hooks/hook_bark/SETUP.md and guide me step by step through configuring hook_bark_ios, strictly following the steps inside. Use the AskUserQuestion tool to ask one question at a time, and wait for my answer before continuing. Don't batch questions. Don't make decisions for me.
```

Claude Code will:
- Walk you through your Bark key and other inputs, one question at a time
- Write the key, modify `settings.json`, and add the aliases for you
- Test that the setup works
- Troubleshoot any step that breaks

**No manual file editing.**

---

### Method 2 — Manual setup (7 steps)

If Method 1 isn't working (Claude Code acting up), do it by hand. All commands run in the macOS Terminal.

#### Step 1 — Download the code

```bash
git clone git@github.com:HaiLei472/hook_bark.git ~/.claude/hooks
```

*What this does*: pulls the scripts into `~/.claude/hooks/`.

If "destination path already exists":
```bash
mv ~/.claude/hooks ~/.claude/hooks.bak
git clone git@github.com:HaiLei472/hook_bark.git ~/.claude/hooks
```

#### Step 2 — Get your Bark key

Open Bark on your iPhone. The first line on the home screen is your push URL, looking like:

```
https://api.day.app/AbCdEfGh1234567890
```

The trailing string `AbCdEfGh1234567890` is your **key**. Tap it to copy.

> Your key is your phone's unique "inbox address". Anyone who has it can push to your phone — **don't share it**.

#### Step 3 — Save the key on your Mac

Replace `YOUR_KEY` with what you copied:

```bash
echo "YOUR_KEY" > ~/.claude/.bark-key
chmod 600 ~/.claude/.bark-key
```

*What these do*: write the key into `~/.claude/.bark-key`, then lock the file to your user only.

Verify the key works (your phone should ring):

```bash
curl "https://api.day.app/$(cat ~/.claude/.bark-key)/test/hello"
```

**Phone got a push → key works.** Next step.

#### Step 4 — Make the scripts executable

```bash
chmod +x ~/.claude/hooks/notify.sh ~/.claude/hooks/stop-notify.sh
```

#### Step 5 — Register the hooks in Claude Code

Open `~/.claude/settings.json` with any text editor, or:

```bash
open -a "TextEdit" ~/.claude/settings.json
```

> If using TextEdit, switch to plain text mode (Format → Make Plain Text) so it doesn't corrupt the JSON with formatting.

Inside the outermost `{ }`, add a `hooks` block. The result should look roughly like:

```json
{
  "your_existing_config": "keep unchanged",
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/notify.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/stop-notify.sh" }
        ]
      }
    ]
  }
}
```

Key points:
- Only add the `"hooks"` block — leave existing content untouched
- Mind the commas: the line before `"hooks"` needs a trailing comma
- Validate after saving:

```bash
python3 -m json.tool ~/.claude/settings.json > /dev/null && echo "JSON OK"
```

`JSON OK` = good. An error means a comma/quote slipped — recheck.

#### Step 6 — (Optional) Add the on/off switch

Append these aliases to `~/.zshrc`:

```bash
cat >> ~/.zshrc << 'EOF'

# Claude Code hooks on/off switch
alias hookoff='touch ~/.claude/.hooks-disabled && echo "hooks off"'
alias hookon='rm -f ~/.claude/.hooks-disabled && echo "hooks on"'
alias hookstatus='[ -f ~/.claude/.hooks-disabled ] && echo "off" || echo "on"'
EOF

source ~/.zshrc
```

Test:

```bash
hookstatus    # → on
hookoff       # off
hookstatus    # → off
hookon        # back on
```

#### Step 7 — Restart Claude Code

**Required.** Exit the current Claude Code session and start a new one — `settings.json` is loaded at startup, so the current session won't pick up the new hooks.

---

## After install — how to use it

**Nothing.** Just use Claude Code normally:

- Ask Claude to run commands needing permission (rm, writing files, …) → **phone rings + desktop notification**
- Ask Claude to run a long task (>30 s and uses tools) → when done, **phone rings + desktop notification**
- Quick chat (short Q&A) → **silent** (no noise)

### Turn it off temporarily

```bash
hookoff     # off
hookon      # on
hookstatus  # current state
```

Good for meetings, late nights, or deep-work blocks.

---

## Troubleshooting

### Installed but no notifications

Check in order:

**1. JSON valid?**
```bash
python3 -m json.tool ~/.claude/settings.json > /dev/null && echo "OK"
```
Errors → `settings.json` is malformed. Back to Step 5.

**2. Scripts executable?**
```bash
ls -la ~/.claude/hooks/*.sh
```
Need `-rwxr-xr-x` (an `x` near the front). If missing:
```bash
chmod +x ~/.claude/hooks/notify.sh ~/.claude/hooks/stop-notify.sh
```

**3. Key file present?**
```bash
cat ~/.claude/.bark-key
```
Should print a string. Empty/error → redo Step 3.

**4. Restarted Claude Code?** `settings.json` changes need a fresh session.

**5. Switch off?**
```bash
hookstatus
```
If `off`, run `hookon`.

### Desktop notification silent

- Mac in Do Not Disturb / Focus? Turn it off in Control Center.
- System Settings → Notifications → "Script Editor" or "Terminal" → allow.

### Phone silent

Test the key:
```bash
curl "https://api.day.app/$(cat ~/.claude/.bark-key)/test/hello"
```
- Rings → key's fine, problem is in the scripts.
- No ring → key invalid. Recopy from the Bark app, redo Step 3.

Other things to check: iPhone Focus mode; Settings → Bark → notifications allowed?

### Phone won't stop ringing

```bash
hookoff
```

Then raise the trigger threshold — in `~/.claude/hooks/stop-notify.sh`, find `if duration <= 30:` and bump `30` to `60` or `120` (bigger = harder to trigger).

---

## Tweaks

| Want to change | Where |
|---|---|
| Desktop notification sound | `sound name "Glass"` in `notify.sh` and `stop-notify.sh` — try `Ping`, `Hero`, `Funk`, `Submarine` |
| Stop threshold (default 30 s) | `if duration <= 30:` in `stop-notify.sh` |
| Bark push title (default "Claude Code") | `Claude%20Code` in the curl command inside the scripts |

---

## License

MIT — use freely, issues welcome.
