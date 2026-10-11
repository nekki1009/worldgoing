# CC-001 第 1–149 列重跑（D a3a4020）

- 執行：2026-10-11 18:45–23:32，1–22 正式目錄、23–149 隔離目錄，每列獨立行程，canonical verify_godot.ps1。
- 證據：output/project_command_center/evidence/CC-20261009-001/rerun_20261011_a3a4020/；run 目錄 CC_CC001R_<NNN>_<id>_*。完整資料：cc001_rerun_a3a4020.json。
- **PASS 44/149**（10/10 為 27）。新增通過 17 列：11, 13, 26, 27, 28, 30, 31, 32, 38, 58, 90, 93, 95, 98, 99, 100, 140。**回歸 0**（10/10 通過的列全部仍通過）。
- PASS 列：1, 2, 3, 8, 9, 10, 11, 12, 13, 17, 18, 19, 20, 21, 22, 23, 26, 27, 28, 29, 30, 31, 32, 37, 38, 47, 48, 49, 58, 79, 83, 87, 88, 90, 93, 95, 98, 99, 100, 105, 118, 136, 140, 143

## 失敗分群（首個錯誤）

| 列數 | 列 | 首個錯誤 |
|---|---|---|
| 10 | 25, 33, 34, 54, 55, 57, 132, 135, 146, 147 | SCRIPT ERROR: Assertion failed. |
| 7 | 109, 110, 111, 112, 113, 114, 115 | SCRIPT ERROR: Assertion failed: Actual original person consents and grants exactly the finite full phase budge |
| 6 | 62, 63, 66, 67, 71, 74 | 逾時 ERROR: REGION_INITIAL_WORLD_TRANSACTION_FAIL: Actual completed newworld transaction cannot overwrite/reissue |
| 6 | 70, 125, 127, 128, 129, 130 | 逾時 ERROR: REGION_INITIAL_WORLD_TRANSACTION_FAIL: No fixture assigns or manufactures an extra learned master |
| 5 | 56, 94, 101, 104, 133 | SCRIPT ERROR: Assertion failed: { "ok": false, "code": "BUSY", "message": "工作或戰鬥進行中：須保留原住戶住宅、門口通路與休息格" } |
| 5 | 59, 64, 65, 68, 69 | 逾時 ERROR: Cannot create uniform set because there's not enough room in the RESOURCES descriptor heap. |
| 4 | 4, 5, 6, 7 | (無錯誤訊息，見 run) |
| 2 | 14, 107 | SCRIPT ERROR: Assertion failed: [] |
| 2 | 15, 108 | ERROR: 1 RID allocations of type 'N26RendererEnvironmentStorage11EnvironmentE' were leaked at exit. |
| 2 | 39, 43 | SCRIPT ERROR: Assertion failed: Original death owner settles all original belongings and counters |
| 2 | 42, 145 | SCRIPT ERROR: Assertion failed: { "ok": false, "code": "INVALID", "message": "無效命令" } |
| 2 | 60, 61 | ERROR: REGION_INITIAL_WORLD_TRANSACTION_FAIL: Actual completed newworld transaction cannot overwrite/reissue |
| 2 | 72, 75 | 逾時 ERROR: REGION_INITIAL_WORLD_TRANSACTION_FAIL: Original caller consumed its exact whole fixed-step input; no di |
| 2 | 73, 124 | ERROR: REGION_INITIAL_WORLD_TRANSACTION_FAIL: No fixture assigns or manufactures an extra learned master |
| 2 | 80, 139 | ERROR: 1 resources still in use at exit (run with --verbose for details). |
| 2 | 84, 86 | 逾時 SCRIPT ERROR: Assertion failed: Original captain fixes each actual original NPC crew slot |
| 2 | 120, 122 | SCRIPT ERROR: Assertion failed: Actual team/head/person approve this purpose and exact finite cumulative budge |
| 2 | 137, 138 | SCRIPT ERROR: Cannot call method 'set_process' on a null value. |
| 1 | 16 | ERROR: Isolated accepted four-category catalog required; fixture never changes it |
| 1 | 24 | SCRIPT ERROR: Assertion failed: Only true Controller/WorkTeam sources create these same held demands and origi |
| 1 | 35 | SCRIPT ERROR: Assertion failed: Actual original work decider is the same joined controlled Actor |
| 1 | 36 | SCRIPT ERROR: Assertion failed: { "ok": false, "code": "NO_WATER", "message": "NO_WATER" } |
| 1 | 40 | ERROR: 3 resources still in use at exit (run with --verbose for details). |
| 1 | 41 | SCRIPT ERROR: Assertion failed: Actual living original captain delegates only the existing logistics office to |
| 1 | 44 | SCRIPT ERROR: Assertion failed: Original JSON loader preserves exactly the actual partial/earned knowledge and |
| 1 | 45 | SCRIPT ERROR: Assertion failed: Original effective-work completion or REST recovery is finitely bounded |
| 1 | 46 | SCRIPT ERROR: Assertion failed: Actual original controlled team decider names this original researcher |
| 1 | 50 | SCRIPT ERROR: Invalid access to property or key 'vehicles' on a base object of type 'RefCounted (Controller)'. |
| 1 | 51 | SCRIPT ERROR: Invalid access to property or key 'combat_armies' on a base object of type 'RefCounted (Fixture) |
| 1 | 52 | SCRIPT ERROR: Invalid call. Nonexistent function 'blocks' in base 'RefCounted (SiteVehicleTransport)'. |
| 1 | 53 | SCRIPT ERROR: Trying to assign an array of type "Array" to a variable of type "Array[Dictionary]". |
| 1 | 76 | ERROR: REGION_INITIAL_WORLD_TRANSACTION_FAIL: Precisely the original configured named row learned one category |
| 1 | 77 | SCRIPT ERROR: Assertion failed: Original Actor validator accepts same-person technology |
| 1 | 78 | SCRIPT ERROR: Assertion failed: Original final shared preflight admits exactly one held actor task |
| 1 | 81 | SCRIPT ERROR: Assertion failed: Original camp head grants full finite hull cost and actual team gives purpose- |
| 1 | 82 | SCRIPT ERROR: Assertion failed: Actual original bind reestablishes source refs without replaying prior goods o |
| 1 | 85 | SCRIPT ERROR: Assertion failed: Original 80 REST state pauses cold work and preserves unfinished progress with |
| 1 | 89 | SCRIPT ERROR: Assertion failed: The explicit saved F07 archive/skill uses the true strict Family and person sc |
| 1 | 91 | SCRIPT ERROR: Assertion failed: Original shared preflight admits this SAME PA task and its actual final water  |
| 1 | 92 | SCRIPT ERROR: Assertion failed: Actual UI start performs one original full batch payment |
| 1 | 96 | SCRIPT ERROR: Assertion failed: True original source/contact/head/carrier and finite cap preflight purely |
| 1 | 97 | SCRIPT ERROR: Assertion failed: Each adopted real batch debits the original holder exactly once |
| 1 | 102 | SCRIPT ERROR: Assertion failed: A second actual original Actor deliberately occupies the same fixture station |
| 1 | 103 | SCRIPT ERROR: Assertion failed: Two retained ballista attempts use the greatest true unfinished unit fraction, |
| 1 | 106 | SCRIPT ERROR: Assertion failed: Actual unlearned original NPC prepares its genuine research purpose |
| 1 | 116 | 逾時 ERROR: Maximum dictionary recursion reached! |
| 1 | 117 | ERROR: Maximum dictionary recursion reached! |
| 1 | 119 | SCRIPT ERROR: Assertion failed: Original F07 first research has finite source and genuine consent |
| 1 | 121 | SCRIPT ERROR: Assertion failed: Public original command prepares an unknown Settlement target |
| 1 | 123 | SCRIPT ERROR: Assertion failed: Original generated source must contain a legal full vehicle, crew and worksite |
| 1 | 126 | ERROR: Real controlled original Actor and exclusive GD mesh branch |
| 1 | 131 | SCRIPT ERROR: Invalid access to property or key 'faction' on a base object of type 'Dictionary'. |
| 1 | 134 | SCRIPT ERROR: Assertion failed: Original F07 selects genuine unknown NPC, real team consent and finite materia |
| 1 | 141 | SCRIPT ERROR: Assertion failed: Strict actual mesh fraction is inside the admitted original action interval |
| 1 | 142 | SCRIPT ERROR: Assertion failed: { "ok": false, "code": "OCCUPIED", "message": "占地或人員預約衝突：原裝備槽" } |
| 1 | 144 | SCRIPT ERROR: Invalid operands 'Dictionary' and 'String' in operator '=='. |
| 1 | 148 | SCRIPT ERROR: Assertion failed: Genuine mesh contact occurs during the actual, still-uncompleted ground-food t |
| 1 | 149 | SCRIPT ERROR: Assertion failed: { "kind": "stone_wall", "cells": [2020], "entrance": 2120, "source": "", "stag |
