# hook_bark_ios

**一句话**：让 Claude Code 在等你回复或跑完任务时，自动通知你的 iPhone 和 Mac。

> **这个文件夹是什么**：`hook_bark/` 是文档目录，里面只放 README 和 SETUP。脚本（`notify.sh`、`stop-notify.sh`）在上一级目录——也就是 `~/.claude/hooks/`（仓库根目录）。整个 hook_bark 项目的所有内容都在 `hooks/` 文件夹下。

> 用 Windows + Android？看 [Windows 版文档](../windows/README.md)。

---

## 这个东西解决什么问题？

用 Claude Code 时，常见两种「干等」：

**情况一：Claude 在等你授权**

你让 Claude 帮你删个文件、跑个命令，它会弹个框问"我可以用 Bash 吗？"。如果你正在切窗口、看手机、倒水——半小时回来发现它还停在那等。任务没进展。

**情况二：Claude 在跑长任务，跑完了你不知道**

你让 Claude 帮你分析大文件、装一堆依赖、跑测试——几十秒到几分钟。你切去做别的事，回来发现早跑完了，白白等了 5 分钟。

**hook_bark_ios 干的就是这件事**：Claude 卡住或跑完时，主动给你手机（iPhone Bark 推送）和电脑（macOS 桌面通知）发消息，让你随时知道它的状态。

---

## 适合谁用？

本仓库支持两套平台：

| 版本 | 电脑 | 手机 | 文档 |
|---|---|---|---|
| macOS + iPhone | Mac | iPhone（Bark） | 本文档 + [SETUP.md](SETUP.md) |
| Windows + Android | Win10/11 | Android（ntfy） | [Windows 版文档](../windows/README.md) |

✅ 适合你，如果你：
- 经常用 Claude Code 跑任务，经常超过 30 秒
- 用 Mac + iPhone，**或** Windows + Android

❌ 不太适合：
- Linux 电脑（暂不支持）
- 偶尔才用 Claude Code 的人（短问答不会触发，装了也用不上）

---

## 你需要先准备什么

| 准备项 | 怎么搞 |
|---|---|
| 一台 Mac | — |
| 一部 iPhone | — |
| Claude Code 已装好能正常用 | — |
| Bark App（免费） | iPhone 上打开 App Store，搜 "Bark"，下载安装 |

---

## 怎么装？（macOS + iPhone）

> 用 Windows + Android？看 [Windows 版安装文档](../windows/README.md)。

有两种方法，**强烈推荐方法一**——让 Claude Code 自己引导你配置，什么都不用手动改。

### 方法一：Claude Code 引导配置（推荐）

只需 2 步：

**1. 把代码下载到本地**

打开 Mac 的「终端」（按 `Cmd + 空格`，输入"终端"或"Terminal"，回车），粘下面这行回车：

```bash
git clone git@github.com:HaiLei472/hook_bark.git ~/.claude/hooks
```

如果提示 "destination path already exists"（文件夹已存在），先备份再重试：
```bash
mv ~/.claude/hooks ~/.claude/hooks.bak
git clone git@github.com:HaiLei472/hook_bark.git ~/.claude/hooks
```

**2. 让 Claude Code 引导你完成剩下的配置**

打开 Claude Code（在任何目录都行），把下面这段话**完整复制粘贴**到对话框，回车：

```
请读取 ~/.claude/hooks/SETUP.md 并严格按照里面的步骤引导我完成 hook_bark_ios 的配置。每一步用 AskUserQuestion 工具一次问一个问题，等用户回答后再继续。不要批量问，不要替我做决定。
```

Claude Code 会：
- 一步步问你 Bark key 等信息
- 自动帮你写入 key、改 settings.json、加 alias
- 测试配置是否成功
- 中间任何步骤出问题会帮你排查

**完全不用手动改任何文件**。

---

### 方法二：手动配置（7 步走）

如果方法一不可用（比如 Claude Code 出问题），可以手动操作。下面所有命令都在 Mac 的「终端」里运行。

### 第 1 步：把代码下载到本地

复制下面这行，粘到终端，回车：

```bash
git clone git@github.com:HaiLei472/hook_bark.git ~/.claude/hooks
```

**这步在干嘛**：把这套通知脚本下载到 `~/.claude/hooks/` 这个文件夹。

**如果提示** "destination path already exists"（文件夹已存在），先备份再重试：
```bash
mv ~/.claude/hooks ~/.claude/hooks.bak
git clone git@github.com:HaiLei472/hook_bark.git ~/.claude/hooks
```

### 第 2 步：拿到你的 Bark key

iPhone 上打开 Bark App，首页第一行是你的专属推送地址，长这样：

```
https://api.day.app/AbCdEfGh1234567890
```

后面那串 `AbCdEfGh1234567890` 就是你的 **key**，点一下能复制。

> 这个 key 是你手机唯一的"收件地址"。别人知道就能给你手机发推送，**别外传**。

### 第 3 步：把 key 存到电脑里

回到终端，把下面这条命令里的 `你的key` 替换成你刚复制的 key，回车：

```bash
echo "你的key" > ~/.claude/.bark-key
chmod 600 ~/.claude/.bark-key
```

**这两步在干嘛**：
- 第一行：把 key 写进文件 `~/.claude/.bark-key`
- 第二行：限制只有你自己能读这个文件

测一下 key 对不对（手机应该会响）：

```bash
curl "https://api.day.app/$(cat ~/.claude/.bark-key)/测试/你好"
```

**手机收到推送 = key 正确**，可以下一步。

### 第 4 步：让脚本可以执行

```bash
chmod +x ~/.claude/hooks/notify.sh ~/.claude/hooks/stop-notify.sh
```

**这步在干嘛**：告诉 Mac「这两个文件是程序，可以运行」。

### 第 5 步：告诉 Claude Code 这两个 hook 的存在

打开 `~/.claude/settings.json` 这个文件。可以用任意文本编辑器（VS Code、Sublime、TextEdit 都行），或者在终端跑：

```bash
open -a "TextEdit" ~/.claude/settings.json
```

> 注意：如果用 TextEdit，确保是「纯文本模式」（菜单栏 → 格式 → 制作纯文本），不然它会加格式把 JSON 弄坏。

在文件最外层的 `{ }` 里，加一段 `hooks` 配置。改完整个文件大概长这样：

```json
{
  "你原有的配置": "保留不变",
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

**关键点**：
- 只加 `"hooks"` 这一段，其他原有内容别动
- 注意逗号——`"原配置": "..."` 这一行末尾要有逗号，才能接 `"hooks"`
- 改完用这条命令验证写对了没：

```bash
python3 -m json.tool ~/.claude/settings.json > /dev/null && echo "格式 OK"
```

看到 `格式 OK` = 写对了。报错就说明逗号或引号有问题，回去检查。

### 第 6 步：（可选）装开关

如果以后想临时关通知，加几个快捷命令到 `~/.zshrc`：

```bash
cat >> ~/.zshrc << 'EOF'

# Claude Code hooks 开关
alias hookoff='touch ~/.claude/.hooks-disabled && echo "hooks 已关"'
alias hookon='rm -f ~/.claude/.hooks-disabled && echo "hooks 已开"'
alias hookstatus='[ -f ~/.claude/.hooks-disabled ] && echo "off" || echo "on"'
EOF

source ~/.zshrc
```

装完试一下：

```bash
hookstatus    # 应该输出: on
hookoff       # 关闭通知
hookstatus    # 应该输出: off
hookon        # 重新开启
```

### 第 7 步：重启 Claude Code

**最后一步，必须做**：退出当前 Claude Code 会话，开一个新的。

因为 `settings.json` 是 Claude Code 启动时读的，**当前会话不会自动加载新配置**。

---

## 装完怎么用？

**什么都不用做**。正常用 Claude Code 就行：

- 让 Claude 跑需要权限的命令（rm、写文件等） → **手机响 + 桌面弹通知**
- 让 Claude 跑耗时任务（>30 秒且用了工具） → 跑完时 **手机响 + 桌面弹通知**
- 跟 Claude 简单聊天（短问答） → **不响**（避免噪音）

### 想临时关掉

```bash
hookoff     # 关
hookon      # 开
hookstatus  # 看当前状态
```

适合：开会、深夜、专注深度工作不想被打断。

---

## 出问题了怎么办？

### 装完 Claude Code 还是没通知

按顺序检查：

**1. JSON 格式对吗？**
```bash
python3 -m json.tool ~/.claude/settings.json > /dev/null && echo "OK"
```
报错就说明 `settings.json` 写错了，回第 5 步看逗号和引号。

**2. 脚本文件能执行吗？**
```bash
ls -la ~/.claude/hooks/*.sh
```
应该看到 `-rwxr-xr-x`，前面有 `x`。如果没有，跑：
```bash
chmod +x ~/.claude/hooks/notify.sh ~/.claude/hooks/stop-notify.sh
```

**3. key 文件还在吗？**
```bash
cat ~/.claude/.bark-key
```
应该输出一串字符。如果空或报错，回第 3 步重做。

**4. Claude Code 重启了吗？**

`settings.json` 改完必须开新会话。

**5. 开关是不是关着？**
```bash
hookstatus
```
如果是 `off`，跑 `hookon`。

### 桌面通知不响

- Mac 是不是开了「勿扰模式」/「专注模式」？右上角控制中心关掉
- 系统设置 → 通知 → 找 "脚本编辑器" 或 "Terminal" → 允许通知

### 手机不响

**测一下 key 还有效不**：
```bash
curl "https://api.day.app/$(cat ~/.claude/.bark-key)/测试/你好"
```
- 手机响 → key 没问题，问题在脚本
- 不响 → key 失效了，回 Bark App 重新复制 key，重做第 3 步

**其他可能**：
- iPhone 是不是开了专注模式？
- 设置 → Bark → 通知权限开了吗？

### 手机一直响个不停

```bash
hookoff
```

临时关掉。然后调高触发阈值——找 `~/.claude/hooks/stop-notify.sh` 里的 `if duration <= 30:`，把 `30` 改成 `60` 或 `120`（数字越大，越不容易触发）。

---

## 想改设置？

| 想改什么 | 改哪里 |
|---|---|
| 桌面通知声音 | `notify.sh` 和 `stop-notify.sh` 里的 `sound name "Glass"`，换成 `Ping`、`Hero`、`Funk`、`Submarine` 等 |
| Stop 触发阈值（默认 30 秒） | `stop-notify.sh` 里 `if duration <= 30:` 改数字 |
| Bark 推送标题（默认 "Claude Code"） | 脚本里 curl 命令中的 `Claude%20Code` |

---

## 文件都在哪？

```
~/.claude/
├── hooks/              ← 这个仓库（脚本在这）
│   ├── README.md       ← 英文 README（仓库根，macOS 版）
│   ├── notify.sh       ← macOS：权限确认时触发
│   ├── stop-notify.sh  ← macOS：任务完成时触发
│   ├── hook_bark/      ← macOS 文档目录（你正在看的就是这）
│   │   ├── README.md
│   │   └── SETUP.md
│   └── windows/        ← Windows + Android 版
│       ├── notify.ps1
│       ├── stop-notify.ps1
│       ├── README.md
│       └── SETUP.md
├── .bark-key           ← 你的 Bark key（私密，不会进 git）
├── .ntfy-topic         ← 你的 ntfy topic（Windows 版用，私密，不进 git）
└── settings.json       ← Claude Code 配置，加了 hooks 字段

~/.zshrc                ← macOS：hookoff / hookon / hookstatus 三个快捷命令
$PROFILE                ← Windows：同上三个命令（PowerShell profile）
```

---

## License

MIT — 随便用，有问题欢迎提 issue。
