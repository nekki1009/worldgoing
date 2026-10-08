extends SceneTree
## Formal generated Site: original player and Army bodies, one mixed surround
## round, natural withdrawal/death settlement, then the real save/load boundary.

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const OUT := "res://output/encirclement_gap_closure_20260925/save"
const SAVE := OUT + "/encirclement_roundtrip.json"
const LEGACY := OUT + "/legacy_exact_arrow.json"
var deadline_ms := 0

func _initialize() -> void:
	deadline_ms = Time.get_ticks_msec() + 110000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() >= deadline_ms:
		push_error("Encirclement save integration deadline")
		quit(1)
	return false

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _find_layout(data: TerrainData, player: TerrainTestCharacter) -> Dictionary:
	for y in range(4, data.size.y - 5):
		for x in range(4, data.size.x - 5):
			var center := Vector2i(x, y)
			var right := center + Vector2i.RIGHT
			var down := center + Vector2i.DOWN
			var cells: Array[Vector2i] = [center, center + Vector2i.LEFT,
				right, center + Vector2i.RIGHT * 2, center + Vector2i.RIGHT * 3, center + Vector2i.RIGHT * 4,
				down, center + Vector2i.DOWN * 2, center + Vector2i.DOWN * 3, center + Vector2i.DOWN * 4]
			var legal := player.can_enter_cell(center)
			for cell: Vector2i in cells:
				legal = legal and data.is_walkable(cell) and not player.occupies_cell(cell)
				legal = legal and is_zero_approx(Runtime.exchange_facility_bonus(data, cell))
			for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				for distance in range(4):
					legal = legal and data.can_step(center + direction * distance, center + direction * (distance + 1))
			if legal and data.can_step(center, center + Vector2i.LEFT):
				return {"center": center, "weak": [center + Vector2i.RIGHT * 2, right],
					"strong": [center + Vector2i.DOWN * 2, down],
					"weak_goal": center + Vector2i.RIGHT * 4, "strong_goal": center + Vector2i.DOWN * 4}
	return {}

func _contexts(lab: TerrainLab, identities: Array[int]) -> Dictionary:
	var people: Array[Dictionary] = lab._exchange_people(false)
	var occupied := {}
	for person: Dictionary in people:
		if not occupied.has(person.cell): occupied[person.cell] = []
		occupied[person.cell].append(person)
	var result := {}
	for person: Dictionary in people:
		if identities.has(int(person.id)):
			result[int(person.id)] = lab._exchange_context(person, occupied)
	return result

func _select(value: Dictionary, fields: Array) -> Dictionary:
	var selected := {}
	for field: String in fields:
		selected[field] = value.get(field)
	return selected

func _saved_projection(site: Dictionary) -> Dictionary:
	var actor: Dictionary = site.get("actors", {}).get("player", {})
	var teams: Array[Dictionary] = []
	for team: Dictionary in site.get("armies", []):
		var rows: Array[Dictionary] = []
		for row: Dictionary in team.units:
			rows.append(_select(row, ["person_id", "hp", "stun", "grace", "ko", "fatigue", "fatigue_rest",
				"cell", "destination", "member", "departed", "loot_settled", "remains_id",
				"cargo", "item_state", "visual_role"]))
		var selected := _select(team, ["team_id", "faction_id", "combat_order", "formal_commander",
			"current_commander", "training", "team_fatigue", "player_member", "goal"])
		selected["units"] = rows
		teams.append(selected)
	var projection := {"controlled_person_id": site.get("controlled_person_id"), "player_cell": site.get("player_cell"),
		"player": _select(actor, ["person_id", "faction_id", "hp", "stun", "stun_grace", "knockout_left",
			"fatigue", "fatigue_rest", "combat_ability", "cell", "attack_target", "item_state",
			"loot_settled", "remains_id"]), "manual_cargo": site.get("manual", {}).get("cargo", {}),
		"armies": teams, "item_records": site.get("item_records", {}),
		"item_definitions": site.get("item_definitions", {}), "ground_loot": site.get("ground_loot", {}),
		"next_item": site.get("next_item"), "next_person_id": site.get("next_person_id")}
	# SiteStore's JSON round trip loads integral JSON numbers as floats.
	var normalized: Dictionary = JSON.parse_string(JSON.stringify(projection))
	return normalized

func _projection_changes(expected: Dictionary, actual: Dictionary) -> Array[String]:
	var changed: Array[String] = []
	for key: String in expected:
		if expected[key] != actual.get(key): changed.append(key)
	if changed.has("player"):
		for key: String in expected.player:
			if expected.player[key] != actual.player.get(key):
				changed.append("player.%s: %s -> %s" % [key, str(expected.player[key]).substr(0, 100), str(actual.player.get(key)).substr(0, 100)])
	if changed.has("armies"):
		for index in range(mini(expected.armies.size(), actual.armies.size())):
			for key: String in expected.armies[index]:
				if expected.armies[index][key] != actual.armies[index].get(key):
					if key == "units":
						for row in range(mini(expected.armies[index].units.size(), actual.armies[index].units.size())):
							for field: String in expected.armies[index].units[row]:
								if expected.armies[index].units[row][field] != actual.armies[index].units[row].get(field):
									changed.append("army%d.unit%d.%s" % [index, row, field])
					else:
						changed.append("army%d.%s: %s -> %s" % [index, key,
							str(expected.armies[index][key]).substr(0, 100), str(actual.armies[index].get(key)).substr(0, 100)])
	return changed

func _separated(lab: TerrainLab) -> bool:
	var center := lab.character.terrain_cell
	for team: TerrainArmy in lab.combat_armies:
		for index in range(team.combat_units.size()):
			if float(team.combat_units[index].hp) > 0.0 and center.distance_to(team.cells[index]) <= 1.0:
				return false
	return true

func _clear_for_save(lab: TerrainLab) -> bool:
	if not _separated(lab) or lab.character.is_moving() or lab.has_ranged_projectiles(): return false
	if float(lab.terrain.site.combat_left) > 0.0 or not lab.site_controller._pending_deaths.is_empty(): return false
	for team: TerrainArmy in lab.combat_armies:
		if team.moving_count() > 0: return false
	return lab.site_controller.supply_save_guard().ok

func _empty_shot_cell(lab: TerrainLab) -> Vector2i:
	var source := lab.character.terrain_cell
	var occupied := lab._ranged_occupants()
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
		for distance in range(3, 8):
			var goal := source + direction * distance
			if not lab.terrain.is_walkable(goal) or not SiteCombatRules.ranged_line_clear(lab.terrain, source, goal): continue
			var empty := true
			for cell: Vector2i in SiteCombatRules.ranged_cells(source, goal):
				if occupied.has(cell): empty = false
			if empty: return goal
	return Vector2i(-1, -1)

func _run() -> void:
	if not _check(DisplayServer.get_name() == "headless"
		and ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn",
		"Formal headless TerrainLab entrypoint required"): return
	var scene := load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene
	if not _check(scene != null and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) == OK,
		"Formal scene or named output unavailable"): return
	var lab := scene.instantiate() as TerrainLab
	lab.pause_when_unfocused = false
	lab.set_process(false)
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.site_controller.save_path = SAVE
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	if not _check(lab.exchange_enabled and lab.npc == null and lab.combat_actors.size() == 1,
		"Current formal Site has one original player and no default worker"): return
	var player_appearance := HumanCharacter3DEditor.default_appearance()
	player_appearance.parts.cape = "none"
	player_appearance.parts.weapon = "bow_01"
	lab.character._saved_appearance = player_appearance
	var data := TerrainGenerator.generate(0, 94321)
	SiteEnvironment.initialize(data, "encirclement-save-94321")
	lab.bind_terrain(data)
	if not _check(lab.terrain == data and lab.character.item_state.has("equipped")
		and lab.character.exchange_stats().weapon == "bow_01"
		and not lab.character.item_state.equipped.has("cape"),
		"Bind must seed the player's real bow and no unauthorized cape"): return
	var controller: SiteController = lab.site_controller
	var player := lab.character
	data.site.manual.cargo["arrow"] = 1
	var layout := _find_layout(data, player)
	if not _check(not layout.is_empty() and player.place(layout.center, true),
		"Generated Site needs a legal unmodified two-sided surround and withdrawal route"): return
	var weak := lab.army
	var strong := lab.opposing_army
	weak.faction_id = 1
	weak.roster_size = 2
	strong.roster_size = 2
	strong.training = 100.0
	var weak_cells: Array[Vector2i] = [layout.weak[0], layout.weak[1]]
	var strong_cells: Array[Vector2i] = [layout.strong[0], layout.strong[1]]
	if not _check(weak.deploy_at(data, player, null, weak_cells) and strong.deploy_at(data, player, null, strong_cells)
		and weak.enable_combat(true, 0) and strong.enable_combat(true, 0),
		"Deploy two original, equipped, command-capable Army owners"): return
	if not _check(weak.combat_units.size() == 2 and strong.combat_units.size() == 2
		and not weak.combat_units[1].item_state.is_empty() and not strong.combat_units[1].item_state.is_empty()
		and controller.cape_policy_guard().ok, "All actual holders must be valid before the baseline save"): return
	weak.team_fatigue.fatigue = 100.0
	var local_damage := SiteCombatRules.exchange_hp(str(player.exchange_stats().weapon), str(weak.exchange_stats(1).armor))
	if not _check(local_damage > 0.0, "A real equipped bow must have a positive melee exchange effect"): return
	weak.combat_units[1].hp = local_damage * 0.5
	var weak_id := weak.combat_identity(1)
	var strong_id := strong.combat_identity(1)
	var dead_item_ids: Array = weak.combat_units[1].item_state.item_ids.duplicate()
	dead_item_ids.sort()
	var strong_fatigue_before := float(strong.team_fatigue.fatigue)
	if not _check(not dead_item_ids.is_empty() and strong_fatigue_before < 100.0,
		"The dying original soldier needs real items and the winning shared pool needs fatigue headroom"): return
	var ids: Array[int] = [player.person_id, weak_id, strong_id]
	var stats := _contexts(lab, ids)
	if not _check(stats.size() == 3 and weak.exchange_stats(1).fatigue == 100.0,
		"Both genuine ordinary soldiers and the player must expose pre-round stats"): return
	var player_without_ability := SiteCombatRules.exchange_score(stats[player.person_id]) - player.combat_ability
	var lower := SiteCombatRules.exchange_score(stats[weak_id]) + 16.0 - player_without_ability
	var upper := SiteCombatRules.exchange_score(stats[strong_id]) - 16.0 - player_without_ability
	if not _check(lower <= upper and lower >= 0.0 and upper <= 100.0,
		"Original training and shared fatigue must permit a roll-proof win and loss"): return
	player.combat_ability = (lower + upper) * 0.5
	stats = _contexts(lab, ids)
	if not _check(SiteCombatRules.exchange_score(stats[player.person_id]) - SiteCombatRules.exchange_score(stats[weak_id]) >= 16.0
		and SiteCombatRules.exchange_score(stats[strong_id]) - SiteCombatRules.exchange_score(stats[player.person_id]) >= 16.0,
		"Independent original scores must dominate the bounded per-pair roll"): return
	controller._capture_positions()
	var baseline := Store.save(data, SAVE)
	if not _check(baseline.ok and Store.load_site(SAVE).ok, "Write a valid precombat baseline: " + str(baseline)): return
	var baseline_hash := FileAccess.get_sha256(SAVE)
	var events: Array[Dictionary] = []
	lab.exchange_resolved.connect(func(a_id: int, b_id: int, result: Dictionary) -> void:
		events.append({"a": a_id, "b": b_id, "result": result.duplicate(true)}))
	var player_hp := player.hp
	lab._resolve_exchanges()
	var winners := {}
	for event: Dictionary in events:
		var other_id := int(event.b) if int(event.a) == player.person_id else int(event.a)
		var result: Dictionary = event.result
		winners[other_id] = 0 if int(result.winner) == 0 else int(event.a) if int(result.winner) == 1 else int(event.b)
	if not _check(events.size() == 2 and lab.exchange_count == 2 and winners.get(weak_id) == player.person_id
		and winners.get(strong_id) == strong_id and player.hp < player_hp and weak.combat_units[1].hp == 0.0
		and strong.combat_units[1].hp == 100.0 and controller._pending_deaths.has(weak_id),
		"One real round must give the surrounded player a loss and a local kill, each pair once"): return
	if not _check(float(strong.team_fatigue.fatigue) > strong_fatigue_before
		and is_equal_approx(float(strong.exchange_stats(1).fatigue), float(strong.team_fatigue.fatigue)),
		"The winning soldier must charge the original non-saturated shared fatigue pool"): return
	if not _check(float(data.site.combat_left) > 0.0 and Store.save(data, SAVE).code == "BUSY",
		"Store must reject an active multi-person combat clock"): return
	controller.save_current()
	if not _check(FileAccess.get_sha256(SAVE) == baseline_hash and controller.supply_save_guard().code == "BUSY",
		"Pending original death and combat refusal must keep the baseline bytes"): return
	if not _check(weak.issue_combat_order(weak.current_commander, TerrainArmy.CombatOrder.RETREAT, layout.weak_goal).ok
		and strong.issue_combat_order(strong.current_commander, TerrainArmy.CombatOrder.RETREAT, layout.strong_goal).ok,
		"Survivors must withdraw through original orders before a postbattle save"): return
	for tick in range(900):
		if not _separated(lab) and not player.is_moving() and player.exchange_stagger <= 0.0:
			player.step(Vector2i.LEFT)
		lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
		if _clear_for_save(lab): break
		if tick % 60 == 0: await process_frame
	if not _check(_clear_for_save(lab) and bool(weak.combat_units[1].loot_settled)
		and not str(weak.combat_units[1].remains_id).is_empty(),
		"Withdrawal, down pose, loot and combat clock must settle naturally"): return
	var remains: Dictionary = data.site.ground_loot.get(str(weak.combat_units[1].remains_id), {})
	var dropped_item_ids: Array = remains.get("item_ids", []).duplicate()
	dropped_item_ids.sort()
	var original_items_settled: bool = (not remains.is_empty() and str(remains.get("kind", "")) == "remains"
		and int(remains.get("original_owner", 0)) == weak_id and dropped_item_ids == dead_item_ids
		and weak.combat_units[1].item_state.item_ids.is_empty())
	for item_id: String in dead_item_ids:
		original_items_settled = (original_items_settled and data.site.item_records.has(item_id)
			and str(data.site.item_records[item_id].holder) == str(remains.get("holder", ""))
			and int(data.site.item_records[item_id].original_owner) == weak_id)
	if not _check(original_items_settled, "The dead soldier's original item IDs must transfer once to its own remains"): return
	controller._capture_positions()
	var saved_strong_fatigue := float(strong.team_fatigue.fatigue)
	var expected := _saved_projection(data.site)
	if not _check(expected.ground_loot.has(str(weak.combat_units[1].remains_id))
		and expected.player.hp < player_hp and expected.item_records.size() > 0,
		"Save-point projection must contain the original corpse, injury and item records"): return
	controller.save_current()
	if not _check(FileAccess.get_sha256(SAVE) != baseline_hash, "Controller must replace baseline with settled battle state"): return
	var restored := Store.load_site(SAVE)
	var restored_projection := _saved_projection(restored.data.site) if restored.ok else {}
	if not _check(restored.ok and restored_projection == expected,
		"Store round trip must preserve stable original owner, fatigue and item data: %s" %
		str(_projection_changes(expected, restored_projection))): return
	lab.bind_terrain(restored.data)
	controller._auto_save_blocked = true
	controller._capture_positions()
	if not _check(lab.terrain == restored.data and _saved_projection(lab.terrain.site) == expected
		and is_equal_approx(float(lab.opposing_army.team_fatigue.fatigue), saved_strong_fatigue)
		and lab.npc == null and lab.combat_actors.size() == 1,
		"First bind cannot heal, revive, refill or duplicate original people/items"): return
	var second := Store.load_site(SAVE)
	if not _check(second.ok, "Saved site must load repeatedly"): return
	lab.bind_terrain(second.data)
	controller._auto_save_blocked = true
	controller._capture_positions()
	if not _check(lab.terrain == second.data and _saved_projection(lab.terrain.site) == expected
		and is_equal_approx(float(lab.opposing_army.team_fatigue.fatigue), saved_strong_fatigue)
		and lab.npc == null and lab.combat_actors.size() == 1,
		"Second bind must be idempotent, including one death drop and all item IDs"): return
	var settled_hash := FileAccess.get_sha256(SAVE)
	if not _check(int(player.ammo_inventory.get("arrow", 0)) == 1 and player.exchange_stats().weapon == "bow_01",
		"The saved original player still has its real bow and one arrow"): return
	var target := _empty_shot_cell(lab)
	if not _check(target != Vector2i(-1, -1) and player.ranged_fire(target, 71001),
		"An original bow must launch one cell-target arrow on generated terrain"): return
	var flight_terrain := lab.terrain
	var flight_records := var_to_bytes(flight_terrain.site.item_records)
	var before_resolution := lab.ranged_resolutions
	var arrivals: Array[Dictionary] = []
	lab.ranged_resolved.connect(func(shooter_id: int, hit_id: int, result: Dictionary) -> void:
		arrivals.append({"shooter": shooter_id, "target": hit_id, "kind": str(result.kind)}))
	if not _check(player.projectiles.size() == 1 and lab.has_ranged_projectiles()
		and int(player.ammo_inventory.get("arrow", 0)) == 0 and controller.supply_save_guard().code == "BUSY",
		"Flight must debit the original cargo once and block saving"): return
	controller.save_current()
	if not _check(FileAccess.get_sha256(SAVE) == settled_hash and not controller.archive_before_replace(),
		"Save and archive refusal must leave the last completed file untouched"): return
	var loaded_during_flight := Store.load_site(SAVE)
	if not _check(loaded_during_flight.ok, "The completed file remains readable during a rejected live flight"): return
	lab.bind_terrain(loaded_during_flight.data)
	if not _check(lab.terrain == flight_terrain and player.projectiles.size() == 1
		and int(player.ammo_inventory.get("arrow", 0)) == 0 and var_to_bytes(flight_terrain.site.item_records) == flight_records
		and FileAccess.get_sha256(SAVE) == settled_hash,
		"Direct replacement cannot lose an in-flight original arrow or refund ammunition"): return
	player.apply_contact({"shield": false, "result": {"hp": 0.0, "stun": 100.0, "guard_break": false}})
	if not _check(player.knockout_left > 0.0 and player.projectiles.size() == 1,
		"The original shooter may become unconscious without deleting its launched arrow"): return
	for tick in range(1200):
		lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
		if not lab.has_ranged_projectiles() and player.can_act() and player.action_time <= 0.0 \
			and float(lab.terrain.site.combat_left) <= 0.0 and controller.supply_save_guard().ok: break
		if tick % 60 == 0: await process_frame
	if not _check(arrivals.size() == 1 and int(arrivals[0].shooter) == player.person_id
		and lab.ranged_resolutions == before_resolution + 1 and not lab.has_ranged_projectiles()
		and int(player.ammo_inventory.get("arrow", 0)) == 0 and controller.supply_save_guard().ok,
		"A KO shooter still resolves exactly once; the original arrow is never refunded"): return
	controller.save_current()
	var after_arrow := Store.load_site(SAVE)
	if not _check(after_arrow.ok and int(after_arrow.data.site.manual.cargo.get("arrow", 0)) == 0,
		"Post-flight successful save must retain spent original ammunition"): return
	var final_hash := FileAccess.get_sha256(SAVE)
	var old_site := Store.load_site(SAVE)
	if not _check(old_site.ok, "Legacy arrow fixture starts from a complete saved Site"): return
	var old_actor: Dictionary = old_site.data.site.actors.player
	var old_cell := Vector2i(int(old_actor.cell[0]), int(old_actor.cell[1]))
	var old_position := (Vector2(old_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	old_actor.projectiles = [{"remaining": 64.0, "faction": int(old_actor.faction_id), "visual": "arrow",
		"position": [old_position.x, old_position.y], "velocity": [420.0, 0.0],
		"ground": [old_position.x, old_position.y], "ground_velocity": [420.0, 0.0],
		"source_cell": [old_cell.x, old_cell.y]}]
	if not _check(Store.save(old_site.data, LEGACY).ok, "Old exact-arrow snapshot remains valid as historical data"): return
	var old_hash := FileAccess.get_sha256(LEGACY)
	var legacy_loaded := Store.load_site(LEGACY)
	if not _check(legacy_loaded.ok and lab.exchange_snapshot_guard(legacy_loaded.data).code == "UNSUPPORTED_ACTIVE_PROJECTILES"
		and controller._load_compatible_site(LEGACY).code == "UNSUPPORTED_ACTIVE_PROJECTILES",
		"Current exchange mode must reject a valid historical exact-arrow snapshot"): return
	var before_legacy := var_to_bytes(lab.terrain.site)
	var current_site := lab.terrain
	lab.bind_terrain(legacy_loaded.data)
	if not _check(lab.terrain == current_site and var_to_bytes(lab.terrain.site) == before_legacy
		and FileAccess.get_sha256(SAVE) == final_hash and FileAccess.get_sha256(LEGACY) == old_hash,
		"Rejected old arrows must preserve the active Site and both files"): return
	print("SITE_ENCIRCLEMENT_SAVE_PASS mixed original Army surround, local death and loot, natural retreat, settled repeat load, BUSY combat/death/cell flight, KO shooter, exact-arrow rejection")
	lab.queue_free()
	await process_frame
	quit(0)
