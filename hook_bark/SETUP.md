# hook_bark_ios 配置引导（给 Claude Code 看的）

你的任务：用 AskUserQuestion 工具一步步引导用户完成 hook_bark_ios 的配置。**一次只问一个问题，等用户回答后再问下一个。不要批量问。**

## 项目背景

hook_bark_ios 是 Claude Code 的通知 hook 套件。装好后：
- Claude Code 要权限确认时 → 推送到用户 iPhone（Bark App）和 Mac 桌面通知
- Claude Code 跑完整轮任务（>30 秒且用了工具）→ 也推送

代码已克隆到 `~/.claude/hooks/`，包括：
- `notify.sh` —— Notification hook 脚本
- `stop-notify.sh` —— Stop hook 脚本

## 你要按顺序做的事

### 步骤 1：环境检查

读取 `~/.claude/hooks/` 目录，确认有 `notify.sh` 和 `stop-notify.sh`。

如果缺失，停止引导，告诉用户重新克隆：
```
git clone git@github.com:HaiLei472/hook_bark.git ~/.claude/hooks
```

### 步骤 2：用 AskUserQuestion 问 Bark App 是否装好

```
问题：你 iPhone 上装好 Bark App 了吗？
选项：
- 装好了（继续下一步）
- 还没装，等我一下
```

如果用户选"还没装"，告诉用户：
> iPhone 上打开 App Store，搜 "Bark"，下载安装。装好后再回来告诉我。

等用户回复"装好了"再继续。

### 步骤 3：用 AskUserQuestion 收集 Bark key

```
问题：请把你的 Bark key 粘贴过来。
说明：打开 Bark App，首页第一行是你的专属推送地址，形如 https://api.day.app/XXXXXX。点一下能复制。把整段地址粘贴到"其他"输入框里。
选项：
- 我已经复制好了，准备粘贴（让用户用"其他"输入框贴 key）
- 我找不到，给我详细说明
```

如果用户选"找不到"，详细说明：
> 1. 打开 iPhone 上的 Bark App
> 2. 首页第一段文字就是你的推送地址，类似：`https://api.day.app/AbCdEfGh1234567890`
> 3. 点击这段地址会弹出"复制"选项
> 4. 复制后回到这里粘贴给我

用户粘贴后，从粘贴内容里提取 key（如果用户贴的是完整 URL `https://api.day.app/XXX`，提取 `XXX` 部分；如果只贴了 key 字符串，直接用）。

### 步骤 4：验证 key

跑这条命令测试（用提取出的 key 替换 `<key>`）：

```bash
curl -sS "https://api.day.app/<key>/hook_bark_ios 配置测试"
```

- 返回 `{"code":200,...}` → key 有效，继续下一步
- 失败或手机没收到推送 → 用 AskUserQuestion：
  ```
  问题：刚才测试 key 时手机没收到推送，可能 key 不对。怎么办？
  选项：
  - 重新粘贴 key
  - 让我先去 Bark App 检查一下
  ```

### 步骤 5：写入 key 文件

跑（替换 `<key>`）：

```bash
echo "<key>" > ~/.claude/.bark-key
chmod 600 ~/.claude/.bark-key
```

### 步骤 6：让脚本可执行

```bash
chmod +x ~/.claude/hooks/notify.sh ~/.claude/hooks/stop-notify.sh
```

### 步骤 7：修改 ~/.claude/settings.json

读取当前 `~/.claude/settings.json` 全部内容。

**判断逻辑**：
- 如果顶层已有 `hooks` 字段，且其中已有 `Notification` 或 `Stop` 子键，用 AskUserQuestion 让用户决定怎么处理（覆盖 / 跳过 / 手动合并）。
- 如果没有，准备在顶层 JSON 对象里新增 `hooks` 字段，内容如下：

```json
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
```

**关键约束**：
- 必须保留所有原有字段（env、theme、enabledPlugins 等），只新增 `hooks`
- 注意 JSON 语法：原顶层最后一个键值对后面要加逗号才能接 `"hooks"`

写入前，用 AskUserQuestion 让用户确认：
```
问题：settings.json 即将修改，原有内容会保留，只在顶层加 hooks 字段。确认写入吗？
选项：
- 确认，写入
- 等等，我要先看看 diff
```

如果用户要看 diff，把"修改前"和"修改后"两份内容都展示给用户，再问一次确认。

写入后用这条验证 JSON 合法：
```bash
python3 -m json.tool ~/.claude/settings.json > /dev/null && echo "格式 OK"
```

如果报错，立即恢复原内容并告诉用户。

### 步骤 8：用 AskUserQuestion 问是否加 alias

```
问题：要不要加 hookoff / hookon / hookstatus 三个快捷命令到 ~/.zshrc？方便以后临时关闭/开启通知。
选项：
- 要，加上（推荐）
- 不用了
```

如果要，先检查 `~/.zshrc` 是否已有这些 alias（用 grep）。如果没有，追加：

```bash
cat >> ~/.zshrc << 'EOF'

# Claude Code hooks 开关
alias hookoff='touch ~/.claude/.hooks-disabled && echo "hooks 已关"'
alias hookon='rm -f ~/.claude/.hooks-disabled && echo "hooks 已开"'
alias hookstatus='[ -f ~/.claude/.hooks-disabled ] && echo "off" || echo "on"'
EOF
```

然后告诉用户需要在已开的终端里跑 `source ~/.zshrc` 或重开终端才能用。

### 步骤 9：实测

跑：

```bash
echo '{"message":"Claude needs your permission to use Bash"}' | bash ~/.claude/hooks/notify.sh
```

用 AskUserQuestion 问：
```
问题：刚触发了一次测试通知。你的手机（Bark）和 Mac 桌面通知，分别收到了吗？
选项：
- 都收到了
- 只有 Mac 桌面通知
- 只有手机推送
- 都没收到
```

**根据回答处理**：

- **都收到了** → 进步骤 10
- **只有 Mac 桌面通知** → 手机 Bark 配置问题：
  - 让用户检查 Bark App 内的通知权限（设置 → Bark → 通知）
  - 让用户检查 iPhone 是否开了专注模式
  - 重新测试 key：`curl "https://api.day.app/$(cat ~/.claude/.bark-key)/测试/重新测试"`
- **只有手机推送** → Mac 通知权限问题：
  - 让用户检查 系统设置 → 通知 → "脚本编辑器" 或 "Terminal" 是否允许通知
  - 让用户检查 Mac 是否开了勿扰模式
- **都没收到** → 全面排查：
  - 跑 `cat ~/.claude/.bark-key` 确认 key 文件内容
  - 跑 `python3 -m json.tool ~/.claude/settings.json > /dev/null` 确认 JSON 合法
  - 跑 `ls -la ~/.claude/hooks/*.sh` 确认脚本能执行
  - 根据检查结果修复

### 步骤 10：最后提醒

告诉用户：

> 配置完成！🎉
>
> **重要**：当前 Claude Code 会话不会触发新 hook——`settings.json` 是会话启动时加载的。**退出当前会话，开一个新会话才会生效**。
>
> 装好后正常用 Claude Code 就行：
> - 让 Claude 跑需要权限的命令 → 手机 + 桌面通知
> - 让 Claude 跑耗时任务（>30s 且用工具）→ 完成时通知
>
> 想临时关通知：在终端跑 `hookoff`；恢复：`hookon`。

完成。
