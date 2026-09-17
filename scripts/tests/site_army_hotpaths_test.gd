extends "res://scripts/tests/site_army_scale_rules_test.gd"
## Fixed-step CPU parity on original owners, never alternative-scene FPS.
const Phase4 = preload("res://scripts/tests/fixtures/terrain_army_hotpaths_phase4.gd")
const Phase5 = preload("res://scripts/tests/fixtures/terrain_army_hotpaths_phase5.gd")
const Phase6 = preload("res://scripts/tests/fixtures/terrain_army_prepare_phase6.gd")
const LabPhase6 = preload("res://scripts/tests/fixtures/terrain_lab_fatigue_phase6.gd")

class Submission extends RefCounted:
	var payload: Array = []
	func submit(index: int, ground: Vector2, appearance: Dictionary, clip: String, direction: String, time: float) -> bool:
		payload = [index, ground, appearance.duplicate(true), clip, direction, time]
		return true

class Before extends Phase4:
	var eligibility_queries := 0
	func _exchange_maneuver_blocked(index: int) -> bool:
		eligibility_queries += 1
		return super._exchange_maneuver_blocked(index)

class After extends TerrainArmy:
	var eligibility_queries := 0
	func _exchange_maneuver_blocked(index: int) -> bool:
		eligibility_queries += 1
		return super._exchange_maneuver_blocked(index)

func _run() -> void:
	var script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	var guard := "selected.size() > MAX_ROSTER_SIZE"
	assert(script.source_code.count(guard) == 1)
	script.source_code = script.source_code.replace(guard, "selected.size() > 2500")
	assert(script.reload(true) == OK)
	for count in [100, 2500]:
		var original := _fixture(false, count, true, Before)
		var recent := _fixture(false, count, true, Phase5)
		var previous := _fixture(false, count, true, Phase6, LabPhase6)
		var candidate := _fixture(false, count, true, After)
		for lab: TerrainLab in [original, recent, previous, candidate]:
			for team: TerrainArmy in lab.combat_armies:
				for index in range(0, count, 11):
					var unit: Dictionary = team.combat_units[index]
					match index % 9:
						0:
							for field: String in ["exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown"]: unit.erase(field)
							unit.stun = 0
							unit.grace = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
						1: unit["exchange_cooldown"] = 0.07
						2: unit["exchange_stagger"] = 0.03
						3: unit["exchange_skill_cooldown"] = 0.1
						4: unit["ranged_cooldown"] = 0.2
						5:
							unit["exchange_visual"] = {}
							unit["exchange_cooldown"] = 0
							unit["exchange_stagger"] = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
						6: unit["exchange_pose_duration"] = 0.12
						7: unit.pose = "guard_raise"
						8: unit.ko = 0.1; unit.pose = "down"
		for step in range(120 if count == 100 else 36):
			for lab: TerrainLab in [original, recent, previous, candidate]:
				if step == 12: lab.combat_armies[0].combat_order = TerrainArmy.CombatOrder.HOLD
				if step == 24: lab.combat_armies[0].combat_order = TerrainArmy.CombatOrder.MOVE
				if step == 30: lab.combat_armies[0].combat_order = TerrainArmy.CombatOrder.ATTACK
				lab._advance_combat(1.0 / 30.0)
			assert(var_to_bytes(_state(original)) == var_to_bytes(_state(candidate)), "Owner state changed count=%d step=%d" % [count * 2, step])
			assert(var_to_bytes(_state(recent)) == var_to_bytes(_state(candidate)), "Phase-five owner state changed count=%d step=%d" % [count * 2, step])
			assert(var_to_bytes(_state(previous)) == var_to_bytes(_state(candidate)), "Phase-six owner state changed count=%d step=%d" % [count * 2, step])
			for side in range(2):
				for field: String in ["combat_slots", "_reserved_cells", "_cell_owners", "_vacancy_assignments", "_unit_rescues", "encirclement_reviews", "encirclement_steps", "combat_order", "_command_dirty", "_visual_dirty"]:
					assert(var_to_bytes(original.combat_armies[side].get(field)) == var_to_bytes(candidate.combat_armies[side].get(field)), "Changed " + field)
					assert(var_to_bytes(recent.combat_armies[side].get(field)) == var_to_bytes(candidate.combat_armies[side].get(field)), "Phase-five changed " + field)
					assert(var_to_bytes(previous.combat_armies[side].get(field)) == var_to_bytes(candidate.combat_armies[side].get(field)), "Phase-six changed " + field)
				assert(original.combat_armies[side].command_rng.state == candidate.combat_armies[side].command_rng.state)
				assert(recent.combat_armies[side].command_rng.state == candidate.combat_armies[side].command_rng.state)
				assert(previous.combat_armies[side].command_rng.state == candidate.combat_armies[side].command_rng.state)
		var before_queries := int(original.combat_armies[0].eligibility_queries) + int(original.combat_armies[1].eligibility_queries)
		var after_queries := int(candidate.combat_armies[0].eligibility_queries) + int(candidate.combat_armies[1].eligibility_queries)
		assert(after_queries <= before_queries, "Original-scan fallback must not add eligibility work")
		if count == 2500:
			assert(after_queries < before_queries, "Large-roster filter must actually exclude irrelevant eligibility work")
		print("ARMY_HOTPATHS_PASS people=", count * 2, " exact rows/keys/types/claims/RNG; eligibility=", before_queries, " -> ", after_queries)
		var native_rows := candidate.combat_armies[0].native_idle_rows + candidate.combat_armies[1].native_idle_rows
		assert(native_rows > 0, "Parity must exercise native updates")
		print("ARMY_NATIVE_OWNER_PASS phase6 exact state people=", count * 2, " native_rows=", native_rows)
		var fatigue_rows := candidate.combat_armies[0].native_fatigue_rows + candidate.combat_armies[1].native_fatigue_rows
		assert(fatigue_rows > 0, "Parity must exercise native fatigue")
		print("ARMY_NATIVE_FATIGUE_PASS phase6 exact state people=", count * 2, " native_rows=", fatigue_rows)
		if count == 100: _render_inputs(recent.combat_armies[0], candidate.combat_armies[0])
		_dispose(original)
		_dispose(recent)
		_dispose(previous)
		_dispose(candidate)
	quit(0)

func _render_inputs(reference: TerrainArmy, candidate: TerrainArmy) -> void:
	# Original Army -> batch arguments, not a substitute renderer or FPS scene.
	var before := Submission.new()
	var after := Submission.new()
	reference._batch_view = before
	candidate._batch_view = after
	var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	for team: TerrainArmy in [reference, candidate]:
		team._soldier_baked_ready = true
		team._sprites.resize(team.combat_units.size())
		team.equipment_appearance_query = func(_identity: int) -> Dictionary: return appearance
	var checked := 0
	for weapon: String in ["longsword_01", "bow_01", "crossbow_01"]:
		appearance.parts.weapon = weapon
		appearance.parts.shield = "none"
		for pose: String in ["idle", "walk", "guard", "guard_raise", "guard_lower", "hit", "down", "get_up", "unconscious", str(HumanCharacter3DEditor.WEAPON_ATTACK_MAP[&"longsword_01"]), "attack_bow", "attack_crossbow"]:
			for direction: Vector2i in TerrainData.DIRECTIONS:
				for time: float in [0.0, 0.371, 1.0, 1000.371]:
					for visual_mode in range(4):
						for moving: bool in [false, true]:
							before.payload.clear()
							after.payload.clear()
							for team: TerrainArmy in [reference, candidate]:
								var unit: Dictionary = team.combat_units[1]
								unit.pose = pose
								unit.age = time
								unit.hp = 0.0 if pose == "down" else 100.0
								unit.ko = 1.0 if pose == "unconscious" else 0.0
								unit.attack = TerrainArmy.CombatTimings.ATTACKS.has(StringName(pose))
								unit.exchange_pose_duration = 0.1 if visual_mode == 3 else 0.0
								unit.erase("exchange_visual")
								if visual_mode == 1: unit.exchange_visual = {}
								if visual_mode == 2: unit.exchange_visual = {"pose": "hit", "age": 0.07, "left": 0.1, "facing": Vector2i.UP}
								team.facing[1] = direction
								team.moving_to[1] = team.cells[1] + direction if moving else TerrainArmy.INVALID_CELL
								team.move_progress[1] = 0.371
								team.move_duration[1] = TerrainArmy.RUN_DURATION
								team._set_soldier_frame(1)
							assert(not before.payload.is_empty())
							assert(var_to_bytes(before.payload) == var_to_bytes(after.payload), "Army render input changed %s %s %s %.9f visual=%d moving=%s" % [weapon, pose, direction, time, visual_mode, moving])
							checked += 1
	for team: TerrainArmy in [reference, candidate]:
		team._batch_view = null
		team.equipment_appearance_query = Callable()
	print("ARMY_RENDER_INPUTS_PASS exact original batch arguments cases=", checked)
