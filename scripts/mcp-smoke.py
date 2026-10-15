#!/usr/bin/env python3

import json
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

APP = Path(sys.argv[1] if len(sys.argv) > 1 else ".build/debug/BetterWispr.app")
BINARY = APP / "Contents/MacOS/BetterWispr"
MEETING_ID = str(uuid.uuid4()).upper()
REFERENCE = datetime(2001, 1, 1, tzinfo=timezone.utc)


def seconds(year, month, day, hour):
    return (datetime(year, month, day, hour, tzinfo=timezone.utc) - REFERENCE).total_seconds()


def segment(speaker, start, text, participant=None):
    line = {"id": str(uuid.uuid4()).upper(), "speaker": speaker, "start": start, "duration": 3, "text": text, "rawText": text}
    return line | ({"participant": participant} if participant else {})


def request(id, method, params=None):
    return {"jsonrpc": "2.0", "id": id, "method": method} | ({"params": params} if params is not None else {})


def call(id, tool, arguments):
    return request(id, "tools/call", {"name": tool, "arguments": arguments})


def exchange(home, messages):
    started = time.monotonic()
    run = subprocess.run([BINARY, "--mcp"], input="".join(json.dumps(m) + "\n" for m in messages), capture_output=True, text=True,
                         timeout=30, env={"CFFIXED_USER_HOME": str(home), "PATH": "/usr/bin:/bin"})
    elapsed = time.monotonic() - started
    assert run.returncode == 0, run.stderr
    replies = [json.loads(line) for line in run.stdout.splitlines()]
    for message in messages:
        print(">", json.dumps(message))
        reply = next((r for r in replies if "id" in message and r.get("id") == message["id"]), None)
        print("<", json.dumps(reply) if reply else "(no reply)")
    print(f"{len(messages)} messages, {len(replies)} replies in {elapsed:.3f}s\n")
    return {r["id"]: r for r in replies}


def text(reply):
    return reply["result"]["content"][0]["text"], reply["result"]["isError"]


with tempfile.TemporaryDirectory() as root:
    home = Path(root)
    support = home / "Library/Application Support/BetterWispr"
    meetings = support / "Meetings"
    meetings.mkdir(parents=True)
    meeting = {
        "id": MEETING_ID, "title": "Synthetic launch sync", "createdAt": seconds(2026, 10, 14, 9), "duration": 1930,
        "notes": "Bring the launch deck", "modelName": "smoke", "language": "en", "attendees": ["Debra Lee"], "participantNames": {"1": "Debra"},
        "summary": {"overview": "Launch moves to May.", "keyPoints": ["Beta feedback is positive"], "decisions": ["Ship in May"],
                    "actionItems": [{"id": str(uuid.uuid4()).upper(), "text": "Send recap", "isDone": False}], "generatedAt": seconds(2026, 10, 14, 10)},
        "segments": [segment("me", 12, "Morning, where are we on launch?"), segment("them", 75, "The launch budget is final", 1)],
    }
    (meetings / f"{MEETING_ID}.json").write_text(json.dumps({"version": 1, "meeting": meeting}))
    (meetings / "broken.json").write_text("not json")
    before = {p.name: p.read_bytes() for p in meetings.iterdir()}
    handshake = [
        request(1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}}),
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        request(2, "tools/list"),
    ]

    print("Connected apps off (no workspace.json)")
    off = exchange(home, handshake + [call(3, "list_meetings", {})])
    assert off[1]["result"]["protocolVersion"] == "2025-06-18"
    assert {t["name"] for t in off[2]["result"]["tools"]} == {"list_meetings", "get_meeting", "search_meetings"}
    assert text(off[3]) == ("Connected apps is off. Turn it on in BetterWispr Settings > Connected apps, then try again.", True)

    settings = {"selectedModelID": "apple", "language": "auto", "autoPaste": True, "saveHistory": True, "showCapsule": True,
                "launchAtLogin": False, "silenceThreshold": 0.002, "mcpServer": True}
    (support / "workspace.json").write_text(json.dumps({"version": 1, "settings": settings, "history": [], "vocabulary": []}))
    print("Connected apps on")
    on = exchange(home, handshake + [
        call(3, "list_meetings", {}),
        call(4, "get_meeting", {"id": MEETING_ID}),
        call(5, "search_meetings", {"query": "LAUNCH BUDGET"}),
        request(6, "resources/list"),
    ])
    listed, failed = text(on[3])
    assert not failed and listed.startswith("Meetings 1-1 of 1") and "Skipped 1 meeting file" in listed, listed
    got, failed = text(on[4])
    assert not failed and "[01:15] Debra: The launch budget is final" in got and "- [ ] Send recap" in got, got
    found, failed = text(on[5])
    assert not failed and found.startswith("Matches 1-1 of 1"), found
    assert on[6]["error"]["code"] == -32601
    assert before == {p.name: p.read_bytes() for p in meetings.iterdir()}, "meeting files changed"
    print("PASS")
