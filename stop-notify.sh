#!/usr/bin/env bash
# Claude Code Stop hook: notify on task completion if duration >30s AND tools were used.

# Master switch
[ -f ~/.claude/.hooks-disabled ] && exit 0

BARK_KEY=$(tr -d '[:space:]' < ~/.claude/.bark-key)

input=$(cat)

# Parse transcript, decide whether to notify, output notification text (or empty)
result=$(echo "$input" | /usr/bin/python3 -c '
import sys, json, os
from datetime import datetime

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

transcript_path = data.get("transcript_path")
if not transcript_path or not os.path.exists(transcript_path):
    sys.exit(0)

# Parse JSONL, keep only real user/assistant messages (skip meta)
messages = []
with open(transcript_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        if msg.get("type") not in ("user", "assistant"):
            continue
        if msg.get("isMeta"):
            continue
        messages.append(msg)

if len(messages) < 2:
    sys.exit(0)

# Find last user message index
last_user_idx = -1
for i in range(len(messages) - 1, -1, -1):
    if messages[i].get("type") == "user":
        last_user_idx = i
        break

if last_user_idx < 0:
    sys.exit(0)

def get_ts(msg):
    ts = msg.get("timestamp")
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except Exception:
        return None

user_ts = get_ts(messages[last_user_idx])
last_ts = get_ts(messages[-1])
if not user_ts or not last_ts:
    sys.exit(0)

duration = (last_ts - user_ts).total_seconds()
if duration <= 30:
    sys.exit(0)

# Check for tool_use in assistant messages of this turn
tools_used = False
for i in range(last_user_idx + 1, len(messages)):
    msg = messages[i]
    if msg.get("type") != "assistant":
        continue
    content = msg.get("message", {}).get("content", [])
    if not isinstance(content, list):
        continue
    for block in content:
        if isinstance(block, dict) and block.get("type") == "tool_use":
            tools_used = True
            break
    if tools_used:
        break

if not tools_used:
    sys.exit(0)

print(f"Claude 已完成本轮任务（耗时 {int(duration)}s）")
')

# Empty result = threshold not met, silent exit
[ -z "$result" ] && exit 0

# URL-encode for Bark
encoded=$(echo "$result" | /usr/bin/python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))')

# macOS notification (best effort)
osascript -e "display notification \"$result\" with title \"Claude Code\" sound name \"Glass\"" 2>/dev/null || true

# Bark push (async)
curl -sS "https://api.day.app/$BARK_KEY/Claude%20Code/$encoded" >/dev/null 2>&1 &

exit 0
