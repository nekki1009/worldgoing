extends SceneTree
## Close-up visual evidence from the formal TerrainLab scene, its original player
## owner and the original Army owner with one live captain and two baked soldiers.
## The headless simultaneous-exchange test owns the complete result matrix; this
## fixture checks that a mixed 1v3 round leaves the surrounded actor visibly hit.

const OUT := "res://output/encirclement_simultaneous_20260925/visual_1v3"
const SOURCES := ["res://project.godot", "res://scripts/terrain_lab/terrain_lab.gd",
	"res://scripts/terrain_lab/terrain_test_character.gd",
	"res://scripts/terrain_lab/terrain_army.gd",
	"res://scripts/terrain_lab/site_combat_rules.gd", "res://scripts/tests/site_encirclement_1v3_visual_test.gd",
	"res://scenes/terrain_lab/TerrainLab.tscn", "res://scripts/terrain_lab/terrain_renderer.gd",
	"res://scripts/terrain_lab/terrain_army_equipment_atlas.gd", "res://scripts/terrain_lab/terrain_army_dye_atlas.gd"]
const CENTER := Vector2i(60, 60)
const CELLS: Array[Vector2i] = [CENTER, CENTER + Vector2i.RIGHT,
	CENTER + Vector2i.DOWN, CENTER + Vector2i.LEFT]
const PLAYER_1V3_ABILITY := 50.0
const GAP_OUT := "res://output/encirclement_gap_closure_20260925/visual"
const EXPECTED_PAIRS := {
	"1v4-all-win": [[2, 1, -1, -24.0], [3, 1, -1, -56.0], [4, 1, -1, -54.0], [5, 1, -1, -41.0]],
	"1v4-mixed": [[2, 1, 1, 26.0], [3, 1, -1, -6.0], [4, 1, 0, -4.0], [5, 1, 1, 9.0]],
	"1v4-draw": [[2, 1, 0, 4.0], [3, 1, -1, -28.0], [4, 1, -1, -26.0], [5, 1, -1, -13.0]],
	"1v4-blocked-push": [[2, 1, 1, 76.0], [3, 1, 1, 44.0], [4, 1, 1, 46.0], [5, 1, 1, 59.0]],
	"army-center-mixed": [[3, 4, -1, -8.0], [3, 5, 1, 8.0], [3, 6, 0, 5.0], [3, 7, 1, 7.0]],
	"army-center-draw": [[3, 4, 0, -3.0], [3, 5, 1, 13.0], [3, 6, 1, 10.0], [3, 7, 1, 12.0]],
}
const EXPECTED_TOTALS := {
	"1v4-all-win": [4, 0, 0, 0.0, 0.0, 2.0],
	"1v4-mixed": [1, 2, 1, 6.0, 46.0, 2.0],
	"1v4-draw": [3, 0, 1, 0.0, 12.0, 1.5],
	"1v4-blocked-push": [0, 4, 0, 16.0, 58.0, 4.0],
	"army-center-mixed": [2, 1, 1, 2.0, 34.0, 0.75],
	"army-center-draw": [3, 0, 1, 0.0, 12.0, 0.75],
}
var lab: TerrainLab
var events: Array[Dictionary] = []
var caption: Label
var deadline_ms := 0

func _initialize() -> void:
	deadline_ms = Time.get_ticks_msec() + 100000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() >= deadline_ms:
		push_error("ENCIRCLEMENT_1V3_VISUAL_TIMEOUT")
		quit(1)
	return false

func _run() -> void:
	var case_name := _case_name()
	if case_name != "1v3":
		await _run_extended(case_name)
		return
	assert(DisplayServer.get_name() != "headless", "GPU window required")
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) == OK)
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	var hashes := _hashes()
	lab = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate() as TerrainLab
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	lab.site_controller.set_process(false)
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "encirclement-1v3-visual")
	data.resource_base.clear()
	data.resources_at.clear()
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	assert(lab.terrain == data and not lab.army.combat_enabled)
	lab.get_node("SiteUI").hide()
	assert(not lab.has_node("TerrainLabUI"), "Legacy debug panel must not be constructed")
	if is_instance_valid(lab.site_test_window): lab.site_test_window.hide()
	var player := lab.character
	player.reset_combat()
	player.exchange_enabled = true
	player.person_id = 1
	player.faction_id = 0
	player.combat_ability = PLAYER_1V3_ABILITY
	player.attack_target_id = 2
	assert(player.place(CELLS[0], true))
	assert(player.editor.select_part_by_id(&"weapon", &"longsword_01"))
	assert(player.editor.select_part_by_id(&"shield", &"none"))
	player.item_state.clear()
	var player_seed := SiteRuntime.seed_person_equipment(data, player.item_state, player.person_id,
		player.editor.capture_appearance())
	assert(player_seed.ok, str(player_seed))
	var team := lab.opposing_army
	team.roster_size = 3
	team.initialize_visual()
	var selected: Array[Vector2i] = [CELLS[1], CELLS[2], CELLS[3]]
	assert(team.deploy_at(data, null, null, selected))
	assert(team.enable_combat(true, 1))
	assert(team.visual_mode() == "baked_atlas" and team.active_3d_source_count() == 1)
	var enemy_ids: Array[int] = []
	for index in range(3):
		team.facing[index] = CENTER - CELLS[index + 1]
		enemy_ids.append(team.combat_identity(index))
	team.advance_frame(0.0)
	player.combatants = func() -> Array[TerrainTestCharacter]: return lab.combat_actors
	player.combat_target_query = lab._combat_target
	player.combat_mode_query = func() -> bool: return true
	player.face_cell(CELLS[1])
	lab.exchange_resolved.connect(func(a_id: int, b_id: int, result: Dictionary) -> void:
		events.append({"a": a_id, "b": b_id, "kind": result.kind, "winner": result.winner}))
	lab.camera.zoom = Vector2.ONE * 3.1
	lab.camera.position = (Vector2(CENTER) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	lab.camera.force_update_scroll()
	var overlay := CanvasLayer.new()
	lab.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(30, 20)
	caption.add_theme_font_size_override("font_size", 24)
	overlay.add_child(caption)
	caption.text = "一對三：三名包圍者同回合出手｜交鋒前"
	await _capture("01_before.png")
	lab._resolve_exchanges()
	assert(lab.exchange_count == 3 and events.size() == 3, "All three adjacent pairs must exchange once")
	var center := player
	print("ENCIRCLEMENT_1V3_VISUAL_DIAGNOSTIC ", JSON.stringify({"events": events,
		"hp": center.hp, "stun": center.stun, "status": center.combat_status,
		"animation": str(center.visual_state.animation_id)}))
	assert(center.hp < 100.0 and center.combat_status.begins_with("Exchange loss")
		and center.visual_state.animation_id in [&"hit", &"hit_back", &"knockback"],
		"One loss must make the surrounded person visibly react as hit or knockback")
	var winners := {}
	for event: Dictionary in events:
		var opponent_id: int = event.b if event.a == 1 else event.a
		winners[opponent_id] = event.a if int(event.winner) == 1 else event.b if int(event.winner) == -1 else 0
	var expected := {}
	expected[enemy_ids[0]] = enemy_ids[0]
	expected[enemy_ids[1]] = 1
	expected[enemy_ids[2]] = 0
	assert(winners == expected, "The 1v3 contains one independent win, loss and draw: " + str(winners))
	caption.text = "一對三：敗、勝、平各結算一次｜被包圍者受擊"
	await _capture("02_hit_start.png")
	for tick in range(6):
		player.advance_combat(1.0 / 60.0)
		team.advance_frame(1.0 / 60.0)
	caption.text = "一對三：一次敗北就維持受擊動作｜0.1 秒後"
	await _capture("03_hit_reaction.png")
	assert(hashes == _hashes(), "Sources changed during visual evidence")
	var report := {"passed": true, "main_scene": ProjectSettings.get_setting("application/run/main_scene"),
		"original_actor_owners": 1, "original_army_owners": 1, "army_rows": 3,
		"army_visual_mode": team.visual_mode(), "pair_events": events, "winners": winners,
		"center_hp": center.hp, "center_stun": center.stun, "center_status": center.combat_status,
		"center_animation": str(center.visual_state.animation_id),
		"captures": ["01_before.png", "02_hit_start.png", "03_hit_reaction.png"],
		"sources": hashes, "scope": "Formal main scene, original player and Army owner with three members, deterministic mixed 1v3 outcome; close-up presentation, not an FPS benchmark"}
	var file := FileAccess.open(OUT + "/result.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE_ENCIRCLEMENT_1V3_VISUAL_PASS ", JSON.stringify(report))
	lab.queue_free()
	await process_frame
	quit(0)

func _capture(filename: String, directory: String = OUT) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(directory + "/" + filename) == OK)

func _hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCES:
		result[path] = FileAccess.get_sha256(path)
	return result

func _case_name() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			return argument.substr(7)
	return "1v3"

func _person_state(person: Dictionary) -> Dictionary:
	var row: int = person.row
	if row < 0:
		var actor: TerrainTestCharacter = person.owner
		return {"id": actor.person_id, "owner": "Actor", "row": -1, "hp": actor.hp,
			"stun": actor.stun, "fatigue": actor.fatigue, "fatigue_rest": actor.fatigue_rest,
			"cell": [actor.terrain_cell.x, actor.terrain_cell.y],
			"source": [actor.movement_from_cell.x, actor.movement_from_cell.y],
			"destination": [actor.terrain_cell.x, actor.terrain_cell.y],
			"progress": actor._movement_elapsed, "moving": actor.is_moving(),
			"cooldown": actor.exchange_cooldown, "stagger": actor.exchange_stagger,
			"skill_cooldown": actor.exchange_skill_cooldown, "pending_skill": actor._exchange_pending_skill,
			"hit_revision": actor._received_effective_hit, "status": actor.combat_status,
			"animation": str(actor.visual_state.animation_id), "ko": actor.knockout_left}
	var team: TerrainArmy = person.owner
	var unit: Dictionary = team.combat_units[row]
	var destination: Vector2i = team.moving_to[row]
	return {"id": team.combat_identity(row), "owner": "Army:%d" % team.team_id, "row": row,
		"visual_role": str(unit.visual_role), "hp": float(unit.hp), "stun": float(unit.stun),
		"fatigue": PersonFatigue.read(unit), "fatigue_rest": PersonFatigue.read(unit, "fatigue_rest"),
		"cell": [team.cells[row].x, team.cells[row].y],
		"source": [team.cells[row].x, team.cells[row].y],
		"destination": [destination.x, destination.y], "progress": float(team.move_progress[row]),
		"moving": destination != TerrainArmy.INVALID_CELL,
		"cooldown": float(unit.get("exchange_cooldown", 0.0)),
		"stagger": float(unit.get("exchange_stagger", 0.0)),
		"skill_cooldown": float(unit.get("exchange_skill_cooldown", 0.0)),
		"pending_skill": str(unit.get("exchange_skill", "")),
		"hit_revision": int(unit.get("hit_revision", 0)), "status": str(unit.status),
		"animation": str(unit.pose), "ko": float(unit.ko)}

func _person_states(people: Array[Dictionary]) -> Dictionary:
	var states := {}
	for person: Dictionary in people:
		states[int(person.id)] = _person_state(person)
	return states

func _appearances(people: Array[Dictionary]) -> Dictionary:
	var appearances := {}
	for person: Dictionary in people:
		var row: int = person.row
		if row < 0:
			var actor: TerrainTestCharacter = person.owner
			appearances[int(person.id)] = actor.editor.capture_appearance()
		else:
			var team: TerrainArmy = person.owner
			appearances[int(person.id)] = team.equipment_appearance(row)
	return appearances

func _effective_contexts(people: Array[Dictionary]) -> Dictionary:
	# Query the same Lab context as the real resolver, including legal auto skill
	# activation. This pre-read happens before the before snapshot and immediate
	# resolution at the same simulated time; it is disclosed in result.json.
	var occupied := {}
	for entry: Dictionary in lab._exchange_people(false):
		if not occupied.has(entry.cell):
			occupied[entry.cell] = []
		occupied[entry.cell].append(entry)
	var wanted := {}
	for person: Dictionary in people:
		wanted[int(person.id)] = true
	var contexts := {}
	for entries: Array in occupied.values():
		for entry: Dictionary in entries:
			if wanted.has(int(entry.id)):
				contexts[int(entry.id)] = lab._exchange_context(entry, occupied).duplicate(true)
	return contexts

func _hit_reaction(state: Dictionary) -> bool:
	if float(state.hp) <= 0.0 or float(state.ko) > 0.0:
		return str(state.animation) in ["down", "unconscious"]
	if str(state.owner) == "Actor":
		return (str(state.status).begins_with("Exchange hit") or str(state.status).begins_with("Exchange loss")) \
			and str(state.animation) in ["hit", "hit_back", "knockback"]
	return str(state.status) == "受擊硬直" and str(state.animation) in ["hit", "knockback"]

func _run_extended(case_name: String) -> void:
	assert(case_name in ["1v4-all-win", "1v4-mixed", "1v4-draw", "1v4-blocked-push",
		"army-center-mixed", "army-center-draw"], "Unknown encirclement visual case: " + case_name)
	assert(DisplayServer.get_name() != "headless", "GPU window required")
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn")
	var directory := GAP_OUT + "/" + case_name
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	deadline_ms = Time.get_ticks_msec() + 140000
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	var hashes := _hashes()
	lab = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate() as TerrainLab
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	lab.site_controller.set_process(false)
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "encirclement-" + case_name)
	data.resource_base.clear()
	data.resources_at.clear()
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	lab.get_node("SiteUI").hide()
	assert(not lab.has_node("TerrainLabUI"), "Legacy debug panel must not be constructed")
	if is_instance_valid(lab.site_test_window): lab.site_test_window.hide()
	var player := lab.character
	player.reset_combat()
	player.exchange_enabled = true
	player.person_id = 1
	player.faction_id = 0
	assert(player.editor.select_part_by_id(&"weapon", &"longsword_01"))
	assert(player.editor.select_part_by_id(&"shield", &"none"))
	player.item_state.clear()
	var player_seed := SiteRuntime.seed_person_equipment(data, player.item_state, player.person_id,
		player.editor.capture_appearance())
	assert(player_seed.ok, str(player_seed))
	var army_center := case_name.begins_with("army-center-")
	var center: Dictionary
	var enemies: Array[Dictionary] = []
	var teams: Array[TerrainArmy] = []
	var ring: Array[Vector2i] = [CENTER + Vector2i.RIGHT, CENTER + Vector2i.DOWN,
		CENTER + Vector2i.LEFT, CENTER + Vector2i.UP]
	if army_center:
		assert(player.place(CENTER + Vector2i(-12, -12), true))
		player.attack_target_id = 0
		var defenders := lab.opposing_army
		defenders.roster_size = 2
		defenders.training = 50.0 if case_name == "army-center-mixed" else 75.0
		defenders.initialize_visual()
		var defender_cells: Array[Vector2i] = [CENTER + Vector2i(-6, -6), CENTER]
		assert(defenders.deploy_at(data, null, null, defender_cells) and defenders.enable_combat(false, 1))
		assert(defenders.visual_mode() == "baked_atlas" and defenders.active_3d_source_count() == 1
			and not defenders._uses_live_presenter(1), "The surrounded person must be an ordinary atlas soldier")
		assert(str(defenders.combat_units[1].visual_role) == "male_atlas")
		center = {"owner": defenders, "row": 1, "id": defenders.combat_identity(1)}
		teams.append(defenders)
		var attackers := lab.third_army
		attackers.roster_size = 4
		attackers.initialize_visual()
		assert(attackers.deploy_at(data, null, null, ring) and attackers.enable_combat(true, 1))
		assert(attackers.visual_mode() == "baked_atlas" and attackers.active_3d_source_count() == 1)
		assert(defenders.faction_id != attackers.faction_id,
			"The two original armies must remain opposing factions; enable_combat's second argument counts women")
		teams.append(attackers)
		for index in range(4):
			attackers.facing[index] = CENTER - ring[index]
			enemies.append({"owner": attackers, "row": index, "id": attackers.combat_identity(index)})
	else:
		assert(player.place(CENTER, true))
		player.combat_ability = 100.0 if case_name == "1v4-all-win" else 0.0 if case_name == "1v4-blocked-push" else 72.0 if case_name == "1v4-draw" else 50.0
		center = {"owner": player, "row": -1, "id": player.person_id}
		var attackers := lab.opposing_army
		attackers.roster_size = 4
		attackers.initialize_visual()
		assert(attackers.deploy_at(data, null, null, ring) and attackers.enable_combat(true, 1))
		assert(attackers.visual_mode() == "baked_atlas" and attackers.active_3d_source_count() == 1)
		teams.append(attackers)
		for index in range(4):
			attackers.facing[index] = CENTER - ring[index]
			enemies.append({"owner": attackers, "row": index, "id": attackers.combat_identity(index)})
		player.attack_target_id = int(enemies[0].id)
		player.face_cell(ring[0])
	player.combatants = func() -> Array[TerrainTestCharacter]: return lab.combat_actors
	player.combat_target_query = lab._combat_target
	player.combat_mode_query = func() -> bool: return true
	for team: TerrainArmy in teams:
		team.advance_frame(0.0)
	var people: Array[Dictionary] = [center]
	people.append_array(enemies)
	var contexts := _effective_contexts(people)
	var appearances := _appearances(people)
	var before := _person_states(people)
	events.clear()
	lab.exchange_resolved.connect(func(a_id: int, b_id: int, result: Dictionary) -> void:
		events.append({"round": lab._exchange_round, "a": a_id, "b": b_id,
			"a_stats": contexts.get(a_id, {}), "b_stats": contexts.get(b_id, {}),
			"result": result.duplicate(true)}))
	lab.camera.zoom = Vector2.ONE * 2.2
	lab.camera.position = (Vector2(CENTER) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	lab.camera.force_update_scroll()
	var overlay := CanvasLayer.new()
	lab.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(30, 20)
	caption.add_theme_font_size_override("font_size", 24)
	overlay.add_child(caption)
	caption.text = case_name + "｜四面包圍，交鋒前"
	await _capture("01_before.png", directory)
	lab._resolve_exchanges()
	for team: TerrainArmy in teams:
		team.advance_frame(0.0)
	var immediate := _person_states(people)
	caption.text = case_name + "｜同輪四對完成"
	await _capture("02_exchange.png", directory)
	for tick in range(3):
		lab._advance_action_time(1.0 / 30.0)
	for team: TerrainArmy in teams:
		team.advance_frame(0.0)
	var after_tenth := _person_states(people)
	caption.text = case_name + "｜0.1 秒反應"
	await _capture("03_reaction.png", directory)
	for tick in range(24):
		lab._advance_action_time(1.0 / 30.0)
	for team: TerrainArmy in teams:
		team.advance_frame(0.0)
	var reaction_end := _person_states(people)
	caption.text = case_name + "｜同輪 0.9 秒反應結束後"
	await _capture("04_reaction_end.png", directory)
	assert(hashes == _hashes(), "Sources changed during visual evidence")
	var center_id: int = center.id
	var wins := 0
	var losses := 0
	var draws := 0
	var hp_cost := 0.0
	var stun_cost := 0.0
	var draw_hp_cost := 0.0
	var stagger_budget := 0.0
	var opponent_ids := {}
	var opponent_hp_cost := {}
	var effective_hits := {}
	for event: Dictionary in events:
		var pair_result: Dictionary = event.result
		if float(pair_result.hp_a) > 0.0 or float(pair_result.stun_a) > 0.0:
			effective_hits[int(event.a)] = true
		if float(pair_result.hp_b) > 0.0 or float(pair_result.stun_b) > 0.0:
			effective_hits[int(event.b)] = true
		if event.a != center_id and event.b != center_id:
			continue
		var opponent_id: int = event.b if event.a == center_id else event.a
		opponent_ids[opponent_id] = true
		var result: Dictionary = event.result
		var side: int = int(result.winner) if event.a == center_id else -int(result.winner)
		var hp: float = float(result.hp_a) if event.a == center_id else float(result.hp_b)
		var opponent_hp: float = float(result.hp_b) if event.a == center_id else float(result.hp_a)
		var stun: float = float(result.stun_a) if event.a == center_id else float(result.stun_b)
		hp_cost += hp
		stun_cost += stun
		opponent_hp_cost[opponent_id] = opponent_hp
		if side > 0:
			wins += 1
		elif side < 0:
			losses += 1
			stagger_budget = maxf(stagger_budget, float(result.stagger))
		else:
			draws += 1
			draw_hp_cost += hp + opponent_hp
			stagger_budget = maxf(stagger_budget, float(result.hold))
	var first: Dictionary = before[center_id]
	var settled: Dictionary = immediate[center_id]
	var tenth: Dictionary = after_tenth[center_id]
	var ended: Dictionary = reaction_end[center_id]
	var effective_hit := hp_cost > 0.0 or stun_cost > 0.0
	var machine_ok := events.size() == 4 and opponent_ids.size() == 4 and lab.exchange_count == 4
	var expected_pairs: Array = EXPECTED_PAIRS[case_name]
	var expected_totals: Array = EXPECTED_TOTALS[case_name]
	for index in range(mini(events.size(), expected_pairs.size())):
		var actual_pair: Dictionary = events[index]
		var expected_pair: Array = expected_pairs[index]
		machine_ok = machine_ok and int(actual_pair.a) == int(expected_pair[0]) \
			and int(actual_pair.b) == int(expected_pair[1]) \
			and int(actual_pair.result.winner) == int(expected_pair[2]) \
			and absf(float(actual_pair.result.margin) - float(expected_pair[3])) < 0.000001
	machine_ok = machine_ok and wins == int(expected_totals[0]) and losses == int(expected_totals[1]) \
		and draws == int(expected_totals[2]) and absf(hp_cost - float(expected_totals[3])) < 0.000001 \
		and absf(stun_cost - float(expected_totals[4])) < 0.000001 \
		and absf(float(settled.fatigue) - float(first.fatigue) - float(expected_totals[5])) < 0.000001
	machine_ok = machine_ok and absf(float(settled.hp) - maxf(0.0, float(first.hp) - hp_cost)) < 0.000001
	machine_ok = machine_ok and absf(float(settled.stun) - float(first.stun) - stun_cost) < 0.000001
	machine_ok = machine_ok and int(settled.hit_revision) - int(first.hit_revision) == (1 if effective_hit else 0)
	machine_ok = machine_ok and float(settled.cooldown) == SiteCombatRules.EXCHANGE_ROUND_SECONDS
	machine_ok = machine_ok and absf(float(tenth.cooldown) - 0.9) < 0.000001
	machine_ok = machine_ok and absf(float(ended.cooldown) - 0.1) < 0.000001
	if effective_hit:
		machine_ok = machine_ok and _hit_reaction(settled) and _hit_reaction(tenth)
		machine_ok = machine_ok and (_hit_reaction(ended) if float(ended.hp) <= 0.0 or float(ended.ko) > 0.0 else not _hit_reaction(ended))
	if army_center:
		machine_ok = machine_ok and int(first.row) == 1 and str(first.visual_role) == "male_atlas"
		machine_ok = machine_ok and not (center.owner as TerrainArmy)._uses_live_presenter(1)
	var animation_transitions := {}
	for person: Dictionary in people:
		var identity: int = person.id
		var prior: Dictionary = before[identity]
		var current: Dictionary = immediate[identity]
		var at_tenth: Dictionary = after_tenth[identity]
		# The snapshots show one final state transition and no visible restart
		# through 0.1 seconds. They do not count unseen animation starts.
		animation_transitions[identity] = int(str(prior.animation) != str(current.animation))
		machine_ok = machine_ok and int(animation_transitions[identity]) == 1 \
			and str(current.animation) == str(at_tenth.animation) \
			and int(current.hit_revision) - int(prior.hit_revision) == (1 if effective_hits.has(identity) else 0) \
			and int(at_tenth.hit_revision) == int(current.hit_revision)
		var look: Dictionary = appearances.get(identity, {})
		var parts: Dictionary = look.get("parts", {})
		var stats: Dictionary = contexts.get(identity, {})
		machine_ok = machine_ok and stats.has("weapon") and stats.has("armor") and parts.has("weapon") and parts.has("armor")
		machine_ok = machine_ok and str(stats.get("weapon", "none")) == str(parts.get("weapon", "none"))
		machine_ok = machine_ok and str(stats.get("armor", "none")) == str(parts.get("armor", "none"))
	for enemy: Dictionary in enemies:
		var identity: int = enemy.id
		machine_ok = machine_ok and opponent_hp_cost.has(identity)
		if opponent_hp_cost.has(identity):
			machine_ok = machine_ok and absf(float(immediate[identity].hp)
				- maxf(0.0, float(before[identity].hp) - float(opponent_hp_cost[identity]))) < 0.000001
	match case_name:
		"1v4-all-win":
			machine_ok = machine_ok and wins == 4 and losses == 0 and draws == 0 and hp_cost == 0.0
			for enemy: Dictionary in enemies:
				machine_ok = machine_ok and float(immediate[int(enemy.id)].hp) < float(before[int(enemy.id)].hp)
		"1v4-mixed", "army-center-mixed":
			machine_ok = machine_ok and wins >= 1 and losses >= 1 and effective_hit
		"1v4-draw", "army-center-draw":
			machine_ok = machine_ok and draws >= 1 and losses == 0 and draw_hp_cost == 0.0 and effective_hit \
				and _hit_reaction(settled)
		"1v4-blocked-push":
			machine_ok = machine_ok and losses >= 1 and float(settled.hp) < float(first.hp) \
				and settled.cell == first.cell and settled.destination == first.cell \
				and not bool(settled.moving) and _hit_reaction(settled)
			machine_ok = machine_ok and absf(float(settled.stagger) - stagger_budget) < 0.000001
			var occupied_cells := {}
			for person: Dictionary in people:
				var identity: int = person.id
				var cell_key := str(immediate[identity].cell)
				machine_ok = machine_ok and not occupied_cells.has(cell_key)
				occupied_cells[cell_key] = true
			for index in range(4):
				var enemy_before: Dictionary = before[int(enemies[index].id)]
				machine_ok = machine_ok and enemy_before.cell == [ring[index].x, ring[index].y]
	var report := {"machine_checks_passed": machine_ok, "acceptance": "pending_visual_review" if machine_ok else "failed_or_needs_calibration",
		"calibration_pending": false, "case": case_name,
		"main_scene": ProjectSettings.get_setting("application/run/main_scene"),
		"expected_pairs": expected_pairs, "expected_totals": expected_totals,
		"animation_transitions_observed": animation_transitions,
		"animation_observation_scope": "Before/immediate/0.1-second state transition and coalesced hit revision; unseen restarts are not directly counted.",
		"center_id": center_id, "center_owner": first.owner, "center_row": first.row,
		"pair_events": events, "effective_contexts": contexts, "visual_appearances": appearances,
		"aggregate": {"wins": wins, "losses": losses, "draws": draws, "all_won": wins == 4,
			"hp_cost": hp_cost, "stun_cost": stun_cost, "draw_hp_cost": draw_hp_cost,
			"opponent_hp_cost": opponent_hp_cost,
			"stagger_budget": stagger_budget, "hit_revision_delta": int(settled.hit_revision) - int(first.hit_revision),
			"fatigue_delta": float(settled.fatigue) - float(first.fatigue),
			"fatigue_rest_delta": float(settled.fatigue_rest) - float(first.fatigue_rest)},
		"before": before, "immediate": immediate, "after_0_1_seconds": after_tenth,
		"reaction_end": reaction_end,
		"captures": ["01_before.png", "02_exchange.png", "03_reaction.png", "04_reaction_end.png"],
		"sources": hashes,
		"context_pre_read": "Called Lab._exchange_context before the before snapshot at the same simulated time; legal captain skill activation is included in the recorded pre-state.",
		"scope": "Formal main scene with controlled flat terrain and editor-selected player appearance. Original Actor/Army owners and atlas rows; visual evidence only, not save/load or FPS."}
	var file := FileAccess.open(directory + "/result.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE_ENCIRCLEMENT_EXTENDED_VISUAL_DIAGNOSTIC ", JSON.stringify(report))
	lab.queue_free()
	await process_frame
	quit(0 if machine_ok else 1)
