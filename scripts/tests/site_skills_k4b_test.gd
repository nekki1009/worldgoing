extends SceneTree
## 技能系統 K4b (reports/skill-system-plan.md V0.7 §5.3, §6): training-ground drill. Checks (SiteTrainingGround.credit_drill):
## - each officer drilling counts his drill seconds hour for hour on his martial line (弓弩 with a bow) and toward 武力;
## - the controlled person counts even when not an officer; an ordinary soldier gains nothing;
## - the commander who ordered the drill gains the longest drill toward 教練 when he holds it, nothing when he does not.
## Output: SITE_SKILLS_K4B_PASS on success; quit(1) on failure.

const Ground = preload("res://scripts/terrain_lab/site_training_ground.gd")

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K4B OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_K4B_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _pending(body: Dictionary, key: String) -> int:
	return int(body.get("skills", {}).get("pending", {}).get(key, 0))

func _run() -> void:
	var commander := {"person_id": 1, "military_role": "officer", "command_abilities": {"coach": 50}}
	var archer := {"person_id": 2, "military_role": "officer", "appearance": {"parts": {"weapon": "bow_01"}, "mounted": false}}
	var soldier := {"person_id": 3, "military_role": "soldier"}
	var player := {"person_id": 4, "military_role": "civilian"}
	var bodies := {1: commander, 2: archer, 3: soldier, 4: player}
	Ground.credit_drill(bodies, {2: 3600.0, 3: 3600.0, 4: 1800.0}, 4, 1)
	if not _ok(_pending(archer, "archery") == 3600000000 and _pending(archer, "ability") == 3600000000, "an officer's hour of drill is an hour on his martial line and toward 武力", archer.get("skills")): return
	if not _ok(_pending(player, "melee") == 1800000000 and not soldier.has("skills"), "the controlled person counts; an ordinary soldier gains nothing", [player.get("skills"), soldier.get("skills")]): return
	if not _ok(_pending(commander, "coach") == 3600000000, "the commander's supervision of the longest drill counts toward 教練", commander.get("skills")): return
	var no_coach := {"person_id": 5, "military_role": "officer", "command_abilities": {}}
	Ground.credit_drill({5: no_coach, 2: archer}, {2: 600.0}, -1, 5)
	if not _ok(not no_coach.has("skills"), "a commander without 教練 gains nothing", no_coach.get("skills")): return
	print("SITE_SKILLS_K4B_PASS checks=", checks)
	quit(0)
