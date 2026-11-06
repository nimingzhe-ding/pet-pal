#!/usr/bin/env python3
"""Claude Code hook -> 桌面宠物状态

从 stdin 读取 hook 的 JSON，根据事件类型更新 pet-state.json。
由 ~/.claude/settings.json 的 hooks 配置调用。
"""
import json
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib.machinery import SourceFileLoader

_bridge_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pet-bridge")
_bridge = SourceFileLoader("pet_bridge", _bridge_path).load_module()


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return 0

    event = payload.get("hook_event_name", "")
    data = _bridge.load()

    if event == "UserPromptSubmit":
        data["phase"] = "thinking"
        data["turnStartedAt"] = _bridge.time.time() * 1000
        data["runningTool"] = None

    elif event == "PreToolUse":
        tool = payload.get("tool_name", "")
        data["phase"] = "working"
        data["runningTool"] = tool
        data["tools"] += 1

    elif event == "PostToolUse":
        data["phase"] = "thinking"
        data["runningTool"] = None

    elif event == "Stop":
        data["phase"] = "happy"
        data["turns"] += 1
        data["bond"] = min(100, data["bond"] + 1)
        data["xp"] += 6
        while data["xp"] >= _bridge.xp_for_level(data["level"]):
            data["xp"] -= _bridge.xp_for_level(data["level"])
            data["level"] += 1
        if data["turnStartedAt"]:
            data["lastTurnMs"] = _bridge.time.time() * 1000 - data["turnStartedAt"]
        data["turnStartedAt"] = 0
        data["runningTool"] = None

    elif event == "SessionEnd":
        data["phase"] = "idle"
        data["runningTool"] = None
        data["turnStartedAt"] = 0

    else:
        return 0

    data["xpNeed"] = _bridge.xp_for_level(data["level"])
    _bridge.save(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
