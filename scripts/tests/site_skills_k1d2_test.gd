extends SceneTree
## 技能系統 K1d part 2 (reports/skill-k1-implementation.md; spec reports/skill-system-plan.md V0.7 §5.3, §7). Checks:
## - 師徒同工: one step's credits on one target and line: a worker at 60 or more teaches up to 3 co-workers who are 10 or
##   more below him (lowest ids first, best master first) and their credited work counts 1.5 times; nobody else's
##   does, nor anyone on another target; one person's several credits in a step count once together;
## - 戶籍派工: without a proficiency Callable the household job plan keeps its old order; with one, the open farm place
##   goes to the household whose members farm best, the smithy to the other.
## Output: SITE_SKILLS_K1D2_PASS on success; quit(1) on failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const ResidentWork = preload("res://scripts/terrain_lab/site_resident_work.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K1D2 OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_K1D2_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _row(identity: int, craft: int) -> Dictionary:
	return {"person_id": identity, "skills": {"version": 1, "lines": {"craft": craft}}}

func _pending(row: Dictionary) -> int:
	return int(row.get("skills", {}).get("pending", {}).get("craft", 0))

func _run() -> void:
	var team := SiteWorkTeam.new()
	var rows := {1: _row(1, 70000), 2: _row(2, 50000), 3: _row(3, 55000), 4: _row(4, 58000), 5: _row(5, 60000), 6: _row(6, 62000), 7: _row(7, 40000)}
	for identity: int in [6, 5, 4, 3, 2, 1]: team._skill_credits.append([rows[identity], "craft", 100.0, "feature:9|operate", identity])
	team._skill_credits.append([rows[2], "craft", 20.0, "feature:9|operate", 2])
	team._skill_credits.append([rows[7], "craft", 100.0, "feature:8|operate", 7])
	team._flush_skill_credits()
	var got := {}
	for identity: int in rows: got[identity] = _pending(rows[identity])
	var expected := {1: 100000000, 2: 180000000, 3: 150000000, 4: 150000000, 5: 100000000, 6: 100000000, 7: 100000000}
	if not _ok(got == expected and team._skill_credits.is_empty(), "the master at 70 teaches the three lowest ids 10 below him; 60 and 62 teach nobody here", got): return
	team = null
	# Household dispatch by proficiency.
	var state := {"minute": 0, "zones": [], "features": {"10": {"kind": "house", "owner_faction": 1}, "11": {"kind": "house", "owner_faction": 1}},
		"housing": {"1": {"version": 1, "house_id": "10", "cell": 1}, "2": {"version": 1, "house_id": "11", "cell": 2}}}
	for pair: Array in [["40", "farm"], ["30", "smithy"]]:
		state.features[pair[0]] = {"kind": pair[1], "owner_faction": 1}
		state.zones.append({"cells": [], "kind": -1, "action": "operate", "feature": pair[0], "active": true})
	Households.normalize(state)
	var plain := ResidentWork.plan(state, 1)
	var levels := {1: {"farming": 20.0, "craft": 80.0}, 2: {"farming": 90.0, "craft": 30.0}}
	var skilled := ResidentWork.plan(state, 1, false, func(identity: int, line: String) -> float: return float(levels.get(identity, {}).get(line, 50.0)))
	if not _ok(plain == {"10": "40", "11": "30"}, "without proficiency the old order stands", plain): return
	if not _ok(skilled == {"11": "40", "10": "30"}, "with proficiency the better farmer's household gets the farm", skilled): return
	print("SITE_SKILLS_K1D2_PASS checks=", checks)
	quit(0)
