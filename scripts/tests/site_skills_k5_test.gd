extends SceneTree
## 技能系統 K5 (reports/skill-system-plan.md V0.7 §5.5, §5.8): the player's start template. Checks:
## - the budget 武力 + 戰術 + 統御 + 教練 + 學業 + Σ(line − 50) + (根骨 − 50) + (悟性 − 50): the defaults are exactly 200, a line
##   pushed below 50 gives points back;
## - the created packet stores the chosen lines and aptitude, is marked started, and carries a title for every 100;
## - SiteController._created_skills refuses an over-budget template unless 自由分配, a malformed packet, a packet without
##   its aptitude and a bad 學業; data without `skills` (callers before K5) is left alone.
## Output: SITE_SKILLS_K5_PASS on success; quit(1) on failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K5 OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_K5_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var command := {"tactics": 50, "leadership": 50, "coach": 50}
	if not _ok(Skills.start_points(50, command, 0, {}, {}) == Skills.START_POINTS and Skills.START_POINTS == 200, "the defaults use exactly 200 points"): return
	var traded := Skills.start_points(80, command, 10, {"farming": 10, "riding": 40}, {"body": 50, "mind": 60})
	if not _ok(traded == 200, "lines pushed below 50 pay for a higher 武力, 學業 and 悟性", traded): return
	var plain := Skills.start_packet({}, {})
	if not _ok(plain == {"version": 1, "start": 1, "aptitude": {"body": 50, "mind": 50}}, "a default template stores only its aptitude and the start mark", plain): return
	var packet := Skills.start_packet({"farming": 10, "riding": 40}, {"body": 50, "mind": 60}, 80, command, 10)
	if not _ok(packet.lines == {"farming": 10000, "riding": 40000} and Skills.valid(packet) and Skills.titles_of(packet).is_empty(), "the chosen lines are stored in thousandths, no title below 100", packet): return
	if not _ok(Skills.packet_points(packet, 80, command, 10) == traded, "a stored packet counts the same points", Skills.packet_points(packet, 80, command, 10)): return
	var masters := Skills.start_packet({"craft": 100}, {"body": 100, "mind": 50}, 100, {"tactics": 50, "leadership": 50, "coach": 100}, 100)
	if not _ok(Skills.titles_of(masters) == ["craft", "ability", "learning", "coach"], "every 100 set at the start carries its title (匠神, 武神, 文曲, 兵神)", masters): return
	# K5b (§5.5, §5.7): people met at world creation.
	if not _ok(Skills.start_trades("officer", false, "archery", "") == {"trades": ["archery"], "rate": Skills.TRADE_RATE} and Skills.start_trades("soldier", true, "melee", "") == {"trades": ["melee"], "rate": Skills.TRADE_RATE}
		and Skills.start_trades("soldier", false, "melee", "") == {"trades": ["building", "gathering"], "rate": Skills.SOLDIER_RATE} and Skills.start_trades("civilian", true, "melee", "farming") == {"trades": ["farming"], "rate": Skills.TRADE_RATE},
		"an officer works his main weapon, a bandit fights, a soldier builds and gathers, a civilian his trade"): return
	var archer := Skills.initial({"version": 1, "aptitude": {"body": 50, "mind": 50}}, 30, ["archery"], Skills.TRADE_RATE, 1, 7)
	if not _ok(absf(Skills.level(archer, "archery") - 67.0) < 2.0 and Skills.level(archer, "farming") == 30.0 and Skills.level(archer, "melee") == 50.0, "an officer of 30 has about 67 on his main weapon, the work lines 30, the other martial lines 50", archer): return
	var taught := {}
	for age: int in [20, 30, 40]: taught[age] = int(Skills.start_learning({"version": 1, "aptitude": {"body": 50, "mind": 50}}, age, 1, 7).value)
	if not _ok(absi(int(taught[20]) - 63) <= 1 and absi(int(taught[30]) - 75) <= 1 and int(taught[40]) >= 80 and int(taught[40]) <= 86, "a 文吏 has about 63 at 20, 75 at 30, 82 at 40 (開局要有老師)", taught): return
	var controller := SiteController.new()
	var accepted: Dictionary = controller._created_skills({"skills": packet, "learning": 10}, 80.0, command)
	var over: Dictionary = controller._created_skills({"skills": packet, "learning": 10}, 81.0, command)
	var free: Dictionary = controller._created_skills({"skills": packet, "learning": 10, "free_points": true}, 81.0, command)
	var bare: Dictionary = controller._created_skills({"skills": {"version": 1, "start": 1}, "learning": 0}, 50.0, command)
	var broken: Dictionary = controller._created_skills({"skills": {"version": 1, "lines": {"farming": 100001}, "aptitude": {"body": 50, "mind": 50}}}, 50.0, command)
	var bad_learning: Dictionary = controller._created_skills({"skills": plain, "learning": 10.5}, 50.0, command)
	var before: Dictionary = controller._created_skills({"combat_ability": 100}, 100.0, {"tactics": 100, "leadership": 100, "coach": 100})
	controller.free()
	if not _ok(accepted.ok and accepted.apply and int(accepted.learning) == 10 and accepted.packet == packet, "a 200-point template is applied as chosen", accepted): return
	if not _ok(not over.ok and "201" in str(over.message) and free.ok and free.apply, "201 points are refused unless 自由分配", [over, free]): return
	if not _ok(not bare.ok and not broken.ok and not bad_learning.ok, "a packet without its aptitude, a malformed packet and a fractional 學業 are refused", [bare, broken, bad_learning]): return
	if not _ok(before.ok and not before.apply, "data without skills (callers before K5) is left alone", before): return
	print("SITE_SKILLS_K5_PASS checks=", checks)
	quit(0)
