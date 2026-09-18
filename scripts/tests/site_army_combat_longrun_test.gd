extends SceneTree
## Full-scene GPU pilot: helper 120 s, internal 100 s. Separate --endurance
## uses helper 620 s / internal 600 s without changing gameplay or success.
## --full-endurance is a separate 1800 s / helper 1820 s completion check;
## both earlier pilots and their output paths remain unchanged.
## All original bodies, shared precise query, AI, damage and 120 Hz steps stay
## enabled. Bounded manual stepping measures CPU throughput, NOT gameplay FPS.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUTPUT := "res://output/site_army_combat_longrun"
const STEP := 1.0 / 120.0
const TARGET_SECONDS := 60.0
const INTERNAL_SECONDS := 100.0
const ENDURANCE_SECONDS := 600.0
const FULL_ENDURANCE_SECONDS := 1800.0
const FINISH_RESERVE_SECONDS := 8.0
var started_us := 0
var deadline_us := 0
var measurements := {}
var mixed_equipment := false
var output_path := OUTPUT
var internal_seconds := INTERNAL_SECONDS

class ObservedLab extends TerrainLab:
	func _init() -> void:
		exchange_enabled = false # Historical exact-policy benchmark, never relabel new rules as equivalent.

	var action_seconds := 0.0
	var combat_seconds := 0.0
	var combat_streak := 0.0
	var longest_combat_streak := 0.0
	var shared_steps := 0
	var contact_queries := 0
	var contact_cpu_us := 0
	var resolved_packets := 0
	var returned_contact_kinds := {"friendly": 0, "enemy": 0, "body": 0, "shield": 0, "parry": 0}
	var queued_result_kinds := {"body": 0, "shield": 0, "parry": 0, "zero_damage": 0, "hp_only": 0, "stun_only": 0, "hp_and_stun": 0}
	var effective_hit_events := 0
	var injured := {}
	var knocked_out := {}
	var died_from_contact := {}
	func _advance_combat(delta: float, combat_clock: float = -1.0) -> void:
		# Observation only. This inherited entry receives the exact original
		# common-step clock; never pre-set combat_left or replay a surrogate timer.
		action_seconds += delta
		shared_steps += 1
		if combat_clock > 0.0:
			combat_seconds += minf(delta, combat_clock)
			combat_streak += minf(delta, combat_clock)
			longest_combat_streak = maxf(longest_combat_streak, combat_streak)
		else:
			combat_streak = 0.0
		super._advance_combat(delta, combat_clock)
	func _collect_unit_contacts(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], source_cell: Vector2i, source_position: Vector2, source: Variant, source_unit: int) -> Array[Dictionary]:
		var before := Time.get_ticks_usec()
		var result := super._collect_unit_contacts(previous, current, source_cell, source_position, source, source_unit)
		contact_cpu_us += Time.get_ticks_usec() - before
		contact_queries += 1
		for hit: Dictionary in result:
			var faction_kind := "friendly" if int(hit.faction) == int(source.faction_id) else "enemy"
			returned_contact_kinds[faction_kind] += 1
			returned_contact_kinds[str(hit.get("block_kind", "body"))] += 1
		return result
	func _resolve_combat_contacts() -> void:
		# Only actual packet victims are observed. No extra per-person update,
		# fabricated hit, reduced HP, grace reset or ignored casualty is used.
		var victims := {}
		for packet: Dictionary in _combat_contacts:
			# These are queued packet classifications, not a claim that every
			# queued packet survives the original simultaneous-death eligibility.
			queued_result_kinds[str(packet.get("block_kind", "body"))] += 1
			var hurts: bool = float(packet.result.hp) > 0.0
			var stuns: bool = float(packet.result.stun) > 0.0
			queued_result_kinds["hp_and_stun" if hurts and stuns else "hp_only" if hurts else "stun_only" if stuns else "zero_damage"] += 1
			if not packet.target is TerrainArmy:
				continue
			var team: TerrainArmy = packet.target
			var index := int(packet.target_unit)
			var identity := team.combat_identity(index)
			if not victims.has(identity):
				var body: Dictionary = team.combat_units[index]
				victims[identity] = {"body": body, "hp": body.hp, "ko": body.ko,
					"hit_revision": int(body.get("hit_revision", 0))}
		resolved_packets += _combat_contacts.size()
		super._resolve_combat_contacts()
		for identity: int in victims:
			var previous: Dictionary = victims[identity]
			var body: Dictionary = previous.body
			effective_hit_events += int(body.get("hit_revision", 0)) - int(previous.hit_revision)
			if float(body.hp) < float(previous.hp):
				injured[identity] = true
			if float(previous.ko) <= 0.0 and float(body.ko) > 0.0:
				knocked_out[identity] = true
			if float(previous.hp) > 0.0 and float(body.hp) <= 0.0:
				died_from_contact[identity] = true

func _initialize() -> void:
	started_us = Time.get_ticks_usec()
	mixed_equipment = "--mixed-equipment" in OS.get_cmdline_user_args()
	if mixed_equipment:
		output_path += "/mixed"
	# A separate bounded endurance run preserves the original 100-second pilot
	# files and its unmet result. No gameplay or success threshold is relaxed.
	if "--full-endurance" in OS.get_cmdline_user_args():
		internal_seconds = FULL_ENDURANCE_SECONDS
		output_path += "/full_endurance"
	elif "--endurance" in OS.get_cmdline_user_args():
		internal_seconds = ENDURANCE_SECONDS
		output_path += "/endurance"
	deadline_us = started_us + int(internal_seconds * 1000000.0)
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_usec() >= deadline_us:
		push_error("SITE ARMY COMBAT LONGRUN exceeded its dedicated %s-second internal deadline" % internal_seconds)
		quit(1)
	return false

func _write() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
	var file := FileAccess.open(output_path + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(measurements, "\t"))
	file.close()

static func finalize_report(report: Dictionary) -> void:
	# The live report starts false. Dictionary.merge defaults to NOT overwriting
	# existing keys, so explicitly replace this flag only after the final metrics.
	report.goal_met = (float(report.longest_combat_streak_seconds) >= TARGET_SECONDS - 0.000001 or bool(report.natural_terminal)) and int(report.effective_hit_events) > 0
	report.reason = ("Original casualties left one whole side unable to act; actual elapsed duration reported, no revival" if bool(report.natural_terminal) else "60 continuous original combat seconds and effective original contacts; unobserved KO/death are explicit coverage limits") if report.goal_met else "Bounded pilot did not satisfy both (60 continuous combat seconds or a natural terminal) and effective original contact; no weakened PASS"

func _inventory(lab: TerrainLab) -> Dictionary:
	var data: TerrainData = lab.terrain
	var ids := {}
	var food := {}
	var holders: Array[Dictionary] = [data.site.depot_items, lab.character.item_state, lab.npc.item_state]
	var cargoes: Array[Dictionary] = [data.site.inventory, data.site.manual.cargo, data.site.worker.cargo]
	for team: TerrainArmy in lab.combat_armies:
		for body: Dictionary in team.combat_units:
			holders.append(body.item_state)
			cargoes.append(body.cargo)
	for container: Dictionary in data.site.ground_loot.values():
		holders.append(container)
		cargoes.append(container.cargo)
	for holder: Dictionary in holders:
		for identity: String in holder.item_ids:
			assert(not ids.has(identity) and data.site.item_records.has(identity), "Actual equipment must have exactly one actual holder")
			assert(str(data.site.item_records[identity].holder) == str(holder.holder))
			ids[identity] = data.site.item_records[identity].original_owner
		for identity: String in holder.equipped.values():
			assert(identity in holder.item_ids, "Equipped slots reference actual held items, not new copies")
	for cargo: Dictionary in cargoes:
		for resource: String in cargo:
			food[resource] = int(food.get(resource, 0)) + int(cargo[resource])
	assert(ids.size() == data.site.item_records.size(), "No original item may be orphaned")
	return {"items": ids, "cargo": food}

func _life(lab: TerrainLab) -> Dictionary:
	var result := {"actual_rows": 0, "living": 0, "ko": 0, "dead": 0, "settled": 0, "attacking": 0, "fatigue_total": 0.0}
	for team: TerrainArmy in lab.combat_armies:
		for body: Dictionary in team.combat_units:
			result.actual_rows += 1
			result.dead += int(float(body.hp) <= 0.0)
			result.living += int(float(body.hp) > 0.0)
			result.ko += int(float(body.ko) > 0.0)
			result.settled += int(bool(body.get("loot_settled", false)))
			result.attacking += int(bool(body.attack))
			result.fatigue_total += PersonFatigue.read(body)
	return result

func _natural_terminal(lab: TerrainLab) -> bool:
	for team: TerrainArmy in lab.combat_armies:
		var capable := false
		for index: int in team.combat_units.size():
			if team.combat_can_act(index):
				capable = true
				break
		if not capable:
			return true # Original casualties, not a fabricated order or revival.
	return false

func _prepare_mixed_equipment(lab: TerrainLab) -> Array[Dictionary]:
	# Explicit initial-loadout fixture, NOT timed looting or a combat stat change.
	# Select the actual adjacent front rank created by the original trial, not a
	# replacement body or assumptions about an unrelated formation's row indices.
	var before := _inventory(lab)
	var selected: Array[Dictionary] = []
	var untouched := {}
	var depot_before: int = lab.terrain.site.depot_items.item_ids.size()
	for team: TerrainArmy in lab.combat_armies:
		var front: Array[int] = []
		for index: int in team.combat_units.size():
			var adjacent := false
			for other: TerrainArmy in lab.combat_armies:
				if other.faction_id == team.faction_id:
					continue
				for cell: Vector2i in other.cells:
					var offset := cell - team.cells[index]
					if absi(offset.x) + absi(offset.y) == 1:
						adjacent = true
						break
			if adjacent:
				front.append(index)
			else:
				untouched[team.combat_identity(index)] = team.combat_units[index].item_state.duplicate(true)
		assert(front.size() == 10, "Original trial must provide ten actual adjacent front-rank people per team")
		for index: int in front:
			var body: Dictionary = team.combat_units[index]
			var identity := team.combat_identity(index)
			var appearance: Dictionary = team.equipment_appearance(index).duplicate(true)
			var items: Array = []
			for slot: String in ["shield", "armor"]:
				assert(body.item_state.equipped.has(slot))
				items.append(body.item_state.equipped[slot])
				appearance.parts[slot] = "none"
			var person: Dictionary = lab.site_controller.person_actions._person(identity)
			var admitted: Dictionary = lab.site_controller._equipment_recipe_guard(person, appearance)
			assert(admitted.ok, str(admitted))
			var transfer := Runtime.transfer_items(lab.terrain, body.item_state, body.cargo,
				lab.terrain.site.depot_items, lab.terrain.site.inventory, {}, items,
				int(body.item_state.version), int(lab.terrain.site.depot_items.version), int(lab.terrain.site.capacity))
			assert(transfer.ok, str(transfer))
			lab.site_controller.equipment_changed(identity)
			assert(team.equipment_appearance(index) == appearance)
			assert(float(body.hp) == 100.0 and float(body.fatigue) == 0.0 and not body.attack)
			selected.append({"person_id": identity, "team_id": team.team_id,
				"cell": [team.cells[index].x, team.cells[index].y], "moved_item_ids": items})
	for team: TerrainArmy in lab.combat_armies:
		for index: int in team.combat_units.size():
			var identity := team.combat_identity(index)
			if untouched.has(identity):
				assert(team.combat_units[index].item_state == untouched[identity], "The other 180 people retain their actual original equipment")
	assert(selected.size() == 20 and lab.terrain.site.depot_items.item_ids.size() == depot_before + 40)
	assert(_inventory(lab) == before, "Initial real shield/armor transfer conserves all actual item IDs and original owners")
	return selected

func _run() -> void:
	measurements = {"goal_met": false, "scope": "original full TerrainLab/200 actual army people, common120Hz, continuous exact contacts and natural casualties; bounded manually stepped CPU throughput, not GPU FPS",
		"shared_source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"target_combat_seconds": TARGET_SECONDS, "internal_deadline_seconds": internal_seconds,
		"fixture_mode": "mixed-equipment" if mixed_equipment else "original-equipment",
		"display": DisplayServer.get_name(), "checkpoints": []}
	if DisplayServer.get_name() == "headless":
		measurements.reason = "Headless skips both original female live geometry owners; cannot claim full 200-person combat"
		_write()
		print("SITE_ARMY_COMBAT_LONGRUN_UNAVAILABLE ", JSON.stringify(measurements))
		quit(0)
		return
	root.size = Vector2i(1400, 900)
	root.content_scale_size = root.size
	var lab := ObservedLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(0, 581)
	Env.initialize(data, "army-combat-longrun-fixture")
	# Fixture terrain only. Preserve original sparse resource owners so the real
	# Site clock's minute boundary cannot silently resurrect flattened obstacles.
	for key: String in data.resource_base:
		Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	for index: int in data.surface_types.size():
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
		data.surface_types[index] = TerrainData.Surface.GRASS
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	assert(lab.character.place(Vector2i(50, 50), true) and lab.npc.place(Vector2i(52, 50), true))
	var deployed := lab.start_melee_trial()
	assert(deployed.ok, str(deployed))
	var original_rows := {}
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
		assert(team.visual_mode() == "baked_atlas" and team.active_3d_source_count() == 1)
		team.advance_frame(0.0)
		for index: int in team.combat_units.size():
			var body: Dictionary = team.combat_units[index]
			assert(float(body.hp) == 100.0 and float(body.stun) == 0.0 and float(body.ko) == 0.0)
			assert(not original_rows.has(int(body.person_id)))
			original_rows[int(body.person_id)] = body
		assert(team._unit_editor(0) != null and team._unit_editor(0)._body_index == 1)
		assert(not team.combat_shapes(0, "body").is_empty() and not team.combat_shapes(1, "body").is_empty())
	assert(original_rows.size() == 200)
	assert(TerrainArmy._contact_source.editor.preview_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	measurements.initial_loadout_transfers = _prepare_mixed_equipment(lab) if mixed_equipment else []
	var original_inventory := _inventory(lab)
	var original_game_time := Runtime.now(data) * 60.0
	lab.site_controller._capture_positions()
	var baseline_path := output_path + "/before_battle.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
	var initial_save := Store.save(data, baseline_path)
	assert(initial_save.ok, str(initial_save))
	var initial_hash := FileAccess.get_sha256(baseline_path)
	lab.get_node("SiteUI").hide()
	lab.get_node("TerrainLabUI").hide()
	lab.camera.zoom = Vector2.ONE * 0.85
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output_path + "/01_before.png") == OK)
	measurements.setup_ms = (Time.get_ticks_usec() - started_us) / 1000.0
	measurements.nodes_before = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	measurements.memory_before_bytes = OS.get_static_memory_usage()
	var cpu_us := 0
	var maximum_chunk_us := 0
	var next_report_us := Time.get_ticks_usec() + 5000000
	var finish_at := deadline_us - int(FINISH_RESERVE_SECONDS * 1000000.0)
	var terminal := false
	while lab.longest_combat_streak < TARGET_SECONDS - 0.000001 and Time.get_ticks_usec() < finish_at:
		# Twelve original steps per bounded chunk; no time dropped/accelerated to
		# conceal expensive collision or fatigue/AI work. Yield only between chunks.
		var before := Time.get_ticks_usec()
		for tick: int in 12:
			lab._process(STEP)
			if Time.get_ticks_usec() >= finish_at:
				break
		var elapsed := Time.get_ticks_usec() - before
		cpu_us += elapsed
		maximum_chunk_us = maxi(maximum_chunk_us, elapsed)
		if Time.get_ticks_usec() >= next_report_us:
			var checkpoint := _life(lab)
			checkpoint.merge({"game_seconds": Runtime.now(data) * 60.0 - original_game_time,
				"action_seconds": lab.action_seconds, "combat_streak_seconds": lab.combat_streak,
				"cpu_ms": cpu_us / 1000.0, "wall_ms": (Time.get_ticks_usec() - started_us) / 1000.0})
			measurements.checkpoints.append(checkpoint)
			_write()
			print("SITE_ARMY_COMBAT_LONGRUN_PROGRESS ", JSON.stringify(checkpoint))
			next_report_us = Time.get_ticks_usec() + 5000000
		for team: TerrainArmy in lab.combat_armies:
			team.advance_frame(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		terminal = _natural_terminal(lab)
		if terminal:
			break
	# A final in-flight death retains its original cargo until the actual down
	# timer completes. Never call a synthetic death settler or erase combat to save.
	var final_life := _life(lab)
	assert(int(final_life.actual_rows) == original_rows.size(), "All original dead/KO/live rows remain accounted for")
	var final_inventory := _inventory(lab)
	assert(final_inventory == original_inventory, "Real combat/KO/death conserves every original equipment ID and cargo quantity")
	for team: TerrainArmy in lab.combat_armies:
		for body: Dictionary in team.combat_units:
			assert(is_same(body, original_rows[int(body.person_id)]), "No person replacement during endurance attempt")
	lab.site_controller._capture_positions()
	var item_validation := Store._validate_items(data, data.site)
	assert(item_validation.ok, str(item_validation))
	var save_guard: Dictionary = lab.site_controller.supply_save_guard()
	var save_result := Store.save(data, baseline_path) if save_guard.ok else save_guard
	if not save_result.ok:
		assert(save_result.code == "BUSY" and FileAccess.get_sha256(baseline_path) == initial_hash,
			"An active battle cannot overwrite the last safe original save")
	measurements.merge({"natural_terminal": terminal, "natural_ko_observed": not lab.knocked_out.is_empty(), "natural_death_observed": not lab.died_from_contact.is_empty(),
		"action_seconds": lab.action_seconds, "game_seconds": Runtime.now(data) * 60.0 - original_game_time,
		"combat_seconds": lab.combat_seconds, "longest_combat_streak_seconds": lab.longest_combat_streak,
		"shared_steps": lab.shared_steps, "full_clock_cpu_ms": cpu_us / 1000.0, "max_chunk_cpu_ms": maximum_chunk_us / 1000.0,
		"contact_cpu_ms": lab.contact_cpu_us / 1000.0, "contact_queries": lab.contact_queries,
		"returned_contact_kinds": lab.returned_contact_kinds, "queued_result_kinds": lab.queued_result_kinds,
		"shared_source_profile_usec": TerrainArmy._contact_source.profile_usec.duplicate(),
		"shared_component_lookup_keys": (TerrainArmy._contact_source.editor.get("_component_nodes") as Dictionary).size(),
		"resolved_packets": lab.resolved_packets, "effective_hit_events": lab.effective_hit_events,
		"unique_injured": lab.injured.size(), "unique_ko": lab.knocked_out.size(), "unique_deaths_from_contact": lab.died_from_contact.size(),
		"final_life": final_life, "items": data.site.item_records.size(), "containers": data.site.ground_loot.size(),
		"pending_original_deaths": lab.site_controller._pending_deaths.size(), "item_conservation": true,
		"save_result": save_result.code, "nodes_after": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"memory_after_bytes": OS.get_static_memory_usage(), "wall_ms": (Time.get_ticks_usec() - started_us) / 1000.0})
	finalize_report(measurements)
	_write()
	for team: TerrainArmy in lab.combat_armies:
		team.advance_frame(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output_path + "/02_final.png") == OK)
	print("SITE_ARMY_COMBAT_LONGRUN_PASS " if measurements.goal_met else "SITE_ARMY_COMBAT_LONGRUN_PILOT_INCOMPLETE ", JSON.stringify(measurements))
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
