# QA explore: agent, debug build, on iPhone_17_Pro 27.0 C6ADE5F0-4D7A-469A-9283-CAC656EEC388

- commit: 8b6d49f394cd22672200b7f421d38b61c1d84728
- run: https://github.com/pbordjadze/paint-by-number/actions/runs/42108932979
- steps: build=success prepare=success probe=success relay=skipped explore=success
- Maestro 2.11.0, Claude Code 2.1.301, claude-opus-5-5, 30 min, 160 turns, $5

- attempt 1: server maestro 1.0.0, protocol 2025-06-18; tools: list_devices, take_screenshot, run, inspect_screen, cheat_sheet, open_maestro_viewer, list_cloud_devices, run_on_cloud, get_cloud_run_status, describe_cloud_run
- list_devices: ok in 12.0 s; no image; {"devices":[{"device_id":"C6ADE5F0-4D7A-469A-9283-CAC656EEC388","name":"PBN-iphone - iOS 27.0 - C6ADE5F0-4D7A-469A-9283-CAC656EEC388","platform":"ios","type":"s
- take_screenshot: ok in 43.5 s; 1-2-take_screenshot-1.jpg 919x2000 152 KiB; 
- inspect_screen: ok in 3.2 s; no image; {"ui_schema":{"platform":"ios","abbreviations":{"b":"bounds","txt":"text","rid":"resource-id","a11y":"accessibilityText","hint":"hintText","val":"value","c":"ch
- PASS: the simulator is listed
- PASS: a screenshot came back as an image
- PASS: the screen's elements came back
- passed in 77 s

- end: success, 118 turns, 18.6 min, estimated $3.0034292
- tool calls: {"Read": 5, "mcp__maestro__take_screenshot": 44, "mcp__maestro__run": 50, "mcp__maestro__inspect_screen": 14, "Write": 4}
- images the agent received: 44

The agent's report: session/report.md
