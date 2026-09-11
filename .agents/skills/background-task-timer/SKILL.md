---
name: background-task-timer
description: >-
  Enforces setting an explicit timer using the `schedule` tool whenever running background tasks,
  subagents, or long-running async commands to prevent execution hangs or deadlocks.
  Use whenever executing background commands (e.g. Blender exports, Godot reimports, test suites, builds),
  or when managing running tasks.
---

# Background Task Timer Standard Operating Procedure

## Core Rule
**Whenever an operation runs in the background (as a task or subagent), NEVER leave it unmonitored without an explicit schedule timer.**
Always call the `schedule` tool immediately to establish a wakeup timeout.

---

## 1. When Launching Commands (`run_command`)

When launching commands that may run in the background (e.g. Blender scripts, Godot imports/tests, compiler builds):

1. If the tool returns that the command was sent to the background with a `task id` (e.g. `task-xxxx`):
2. **IMMEDIATELY** call the `schedule` tool in the very next step to set a one-shot timer:
   ```json
   {
     "DurationSeconds": 10,
     "Prompt": "Check status of task <task_id>",
     "TimerCondition": "<task_id>",
     "toolSummary": "Schedule task timer",
     "toolAction": "Scheduling timer for background task"
   }
   ```
3. Set `TimerCondition` to the specific task ID so that if the task completes early, the timer cancels automatically and wakes up the agent.

---

## 2. When Spawning Subagents (`invoke_subagent`)

1. After invoking one or more subagents, if waiting for their results:
2. Schedule a watchdog timer:
   ```json
   {
     "DurationSeconds": 60,
     "Prompt": "Check in on subagents progress",
     "TimerCondition": "any",
     "toolSummary": "Schedule subagent timer",
     "toolAction": "Scheduling timer for subagents"
   }
   ```

---

## 3. Monitoring Long-Running Tasks

1. When checking task status via `manage_task(Action="status", TaskId="...")`:
   - If the task is still `RUNNING`, schedule another timer (e.g., 5 to 15 seconds) using `schedule`.
   - Never enter an idle turn without an active timer or early termination condition.
2. If a timer fires or task completes:
   - Check the final logs and exit code with `manage_task(Action="status")`.
   - Proceed with the workflow or handle failures.
