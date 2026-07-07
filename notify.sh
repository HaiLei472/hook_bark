#!/usr/bin/env bash
# Claude Code Notification hook: macOS notification + Bark push when CC needs permission/input.

# Master switch
[ -f ~/.claude/.hooks-disabled ] && exit 0

BARK_KEY=$(tr -d '[:space:]' < ~/.claude/.bark-key)

# Read stdin JSON
input=$(cat)

# Extract message, translate, output two lines: translated | urlencoded
# (Note: original brief used `MAPFILE` which is bash 4+; macOS system bash is 3.2.
#  Using read into two vars is the portable equivalent, no behavior change.)
output=$(echo "$input" | /usr/bin/python3 -c '
import sys, json, re, urllib.parse
try:
    data = json.load(sys.stdin)
    text = data.get("message") or "Claude 需要你的输入"
except Exception:
    text = "Claude 需要你的输入"
patterns = [
    (r"^Claude needs your permission to use (\w+) to (.+)$", r"Claude 需要你授权使用 \1 来 \2"),
    (r"^Claude needs your permission to use (\w+)$", r"Claude 需要你授权使用 \1"),
    (r"^Claude is waiting for your input$", r"Claude 正在等待你的输入"),
]
translated = text
for pat, repl in patterns:
    if re.match(pat, text):
        translated = re.sub(pat, repl, text)
        break
print(translated)
print(urllib.parse.quote(translated))
')
translated="${output%$'\n'*}"
encoded="${output##*$'\n'}"

# macOS notification (best effort, do not fail script)
osascript -e "display notification \"$translated\" with title \"Claude Code\" sound name \"Glass\"" 2>/dev/null || true

# Bark push (async, fire-and-forget)
curl -sS "https://api.day.app/$BARK_KEY/Claude%20Code/$encoded" >/dev/null 2>&1 &

exit 0
