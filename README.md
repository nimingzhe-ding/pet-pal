# pet-pal 🐋

一个 macOS 桌面宠物，养着一只鲸鱼娘。它会停在你的桌面上，跟着 Claude Code 的实际状态换表情，还会帮你盯着所有会话的进度。

原生的 Swift 实现，无第三方依赖。

## 能做什么

**桌面摆件**
- 透明无边框窗口，浮在所有窗口之上
- 会眨眼、上下浮动、自己在桌面溜达
- 可以拖动到任意位置，双击展开

**跟随工作状态**
| 我在做什么 | 它的反应 |
|---|---|
| 空闲 | 常态，缓慢呼吸 |
| 思考中 | 微微放大，轻微倾斜 |
| 调用工具 | 放大更明显，轻微旋转 |
| 回合完成 | 向上跳一下 |
| 超过 2 分钟 | 缩小、压暗、降低饱和度 |
| 工具报错 | 歪向一边 |

**会话面板**

点一下鲸鱼娘展开，列出所有 Claude Code 会话：

- 会话名、最后一句提示词、多久之前活动过
- 进行中：橙色脉冲圆点
- 已完成：绿色 ✅，归到「最近完成」区
- **点击任意会话，切换到对应的窗口**

**进度徽章**

收起状态下右上角有个小徽章，不用展开就知道状态：
- 橙色数字 = 有几个会话正在跑
- 绿色 ✓ = 有会话已完成
- 都没有 = 隐藏

**完成提示**

某个会话从「进行中」变成「空闲」时，头顶弹出绿色气泡「✅「会话名」完成了」，同时播放系统音效。

## 安装

需要 macOS 13+ 和 Xcode Command Line Tools（`xcode-select --install`）。

```bash
git clone git@github.com:nimingzhe-ding/pet-pal.git
cd pet-pal

# 1. 获取形象素材（见下方「素材来源」）
./scripts/fetch-asset.sh

# 2. 编译并安装
./scripts/build.sh --install
```

## 使用

```bash
petpal on         # 打开（并设为登录自启）
petpal off        # 关闭（并取消自启）
petpal status     # 查看状态
petpal restart    # 重启
```

`petpal` 安装在 `~/.claude/pet-desktop/petpal`，建议链到 PATH：

```bash
ln -sf ~/.claude/pet-desktop/petpal ~/.local/bin/petpal
```

右键鲸鱼娘也有菜单：展开面板 / 停止走动 / 回到右下角 / 退出。

## 会话数据从哪来

宠物不侵入 Claude Code，只读以下文件：

| 路径 | 内容 |
|---|---|
| `~/.claude/sessions/*.json` | 会话列表、pid、状态（busy/idle） |
| `~/.claude/projects/*/<sessionId>.jsonl` | 会话标题、最后一条提示 |
| `~/.claude/pet-state.json` | 宠物自己的状态（由 hook 写入） |

### 状态同步（可选）

想让表情跟着 Claude Code 实时变化，在 `~/.claude/settings.json` 里加 hooks：

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "python3 ~/.claude/pet-desktop/pet-hook.py" }] }],
    "PreToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "python3 ~/.claude/pet-desktop/pet-hook.py" }] }],
    "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "python3 ~/.claude/pet-desktop/pet-hook.py" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "python3 ~/.claude/pet-desktop/pet-hook.py" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "python3 ~/.claude/pet-desktop/pet-hook.py" }] }]
  }
}
```

不加也能用，只是表情不会联动，会话面板和完成提示照常工作。

## 素材来源

**仓库不包含角色图片。**

形象是 DeepSeek娘（蓝色大肥鱼 / 鲸鱼娘），来自开源表情包合集：

- 素材库：https://github.com/the-beating-light-of-the-nail/deepseek-chan-meme-pack
- 在线图库：https://aigengtu.com

角色形象与原始画作版权归原作者及社区创作者所有。该项目为非营利粉丝向整理，README 明确说明「非营利粉丝向玩梗可以随意使用」。

本项目只提供获取脚本（`scripts/fetch-asset.sh`），下载后本地抠图使用，不随仓库分发。**请勿用于商业用途。**

## 项目结构

```
src/
  main.swift          应用主体：窗口、菜单、拖动、状态轮询
  WhaleGirl.swift     角色渲染（图片 + 状态变换）
  SessionPanel.swift  会话面板 UI
  SessionReader.swift 读取 ~/.claude 下的会话数据
  SessionJump.swift   点击跳转到对应窗口
  preview.swift       离屏渲染预览（开发用）
tools/
  cutout.swift        白底转透明抠图工具
scripts/
  build.sh            编译 / 安装
  fetch-asset.sh      获取并处理素材
petpal                开关控制脚本
pet-hook.py           Claude Code hook：写宠物状态
```

## 已知限制

- **跳转只能到应用层**。同一终端开多个会话时，切过去还得自己点对应的 tab，各家终端没有暴露切 tab 的接口。
- **点击需要窗口聚焦**。焦点在别的 app 上时，第一次点击可能只是激活宠物窗口。
- 目前只支持 macOS。

## License

代码 MIT。

角色素材不属于本项目，版权归原作者所有。
