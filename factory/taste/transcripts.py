"""Read the final SubagentHandback reply from a Claude Code .output transcript."""
import json
from pathlib import Path


def final_reply(path):
    for line in reversed(Path(path).read_text().splitlines()):
        if not line.strip():
            continue
        message = json.loads(line).get("message")
        if not isinstance(message, dict) or message.get("role") != "assistant":
            continue
        content = message.get("content", [])
        if not isinstance(content, list):
            continue
        for block in reversed(content):
            if block.get("type") == "tool_use" and block.get("name") == "SubagentHandback":
                return block["input"].get("message", "")
    return ""


def extract(path):
    raw = final_reply(path)
    body = raw[raw.find("{"):raw.rfind("}") + 1]
    try:
        data = json.loads(body)
        if not isinstance(data, dict):
            raise ValueError("expected a JSON object")
        return data
    except (ValueError, TypeError) as error:
        return {"error": f"unparsable reply: {error}", "raw": raw}
