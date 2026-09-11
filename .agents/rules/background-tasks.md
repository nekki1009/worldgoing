# Project Guidelines & Autonomous Rules

## Background Tasks and Timers (Mandatory)
- Whenever a command or process is sent to the background (e.g. `run_command` returning a task ID like `task-xxxx` or `invoke_subagent`), you **MUST ALWAYS** immediately call the `schedule` tool to set an explicit timer (e.g. 5–15 seconds) with `TimerCondition` set to the task ID or `any`.
- Never let an async background command run without an active watchdog schedule timer.
- Always monitor background tasks actively until completion.
