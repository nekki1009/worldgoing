# Project Guidelines & Autonomous Rules

## Background Tasks and Monitoring (Updated 2026-09-13)
- The user approved native subagent status/wait monitoring when `schedule` is unavailable. Do not require, invent, or block work on a tool that is not enabled.
- Use the available task status/wait tools to actively monitor background commands and subagents until completion or an explicit handoff. Keep task/session IDs and bounded waits; do not leave work unmonitored.
- If an actual `schedule` tool is available, a task-bound watchdog timer may be used. Otherwise native wait/status tools are the approved mechanism; do not create recurring automations solely as substitute timers.
- Long-running external commands still need an explicit execution timeout. Godot verification continues to use the unchanged canonical bounded helper below.
- This available-tool rule supersedes the older mandatory `schedule` requirement in the repository's background-task-timer skill.

## Verification Failure Recovery (Updated 2026-09-14)
- The user explicitly removed the rule requiring a pause and a new user confirmation after every failed verification. In this project, this overrides the `godot-runtime-verify` skill's first-failure stop/ask rule.
- Diagnose failures, make a targeted in-scope code or test correction, then rerun the relevant bounded verification autonomously and continue the planned checks. Do not ask the user to approve routine fixes to errors introduced by the implementation or test.
- Preserve every failed result and report failures honestly. Never weaken acceptance, hide error output, change the canonical verifier, or repeatedly rerun unchanged failures.
- A crash, timeout, unexplained failure, permission boundary or out-of-scope change still requires investigation; do not blindly retry or infer broader authority. Request user input only when a genuine external blocker or material decision remains.

## Approved Temporary-File Retention (2026-09-12)
- The user approved automatic retention in this project: keep the newest 100 completed Godot verification runs under `.godot-temp/godot_verify`, identified by `result.json`, and preserve every unfinished run. The canonical `godot-runtime-verify/scripts/verify_godot.ps1` applies this after each run.
- Run that helper unchanged. Do not remove `Clear-CompletedVerificationHistory`, including through text replacement or an in-memory script block. If a task needs a particular older result for its handoff, copy that specific result into the task's named `output` folder before it expires instead of disabling retention for all runs.
- Successful Blender publication removes only its intermediate copy after the formal output has been copied successfully. Preserve formal assets, baselines, Git history and LFS objects.
- This checkout uses the repository-local LFS clean guard documented in `tools/lfs-clean-guard/README.md`. Preserve its `filter.lfs.clean` and `filter.lfs.process` overrides; a forced `git lfs install` can replace them and reintroduce orphan copies after cancelled reviews. Do not revert these settings as routine Git setup.
