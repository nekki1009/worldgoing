extends SceneTree

## Base of the GD replay helpers (_scene/_restore/_capture/...) kept for the tests that extend it; the crowd
## shared-step replay acceptance itself is site_shared_step_replay_test.gd (2026-11-14, CC-20261114-193).
# Copy to scripts/tests only after the ORIGINAL candidate APIs are installed.
# All expected state comes from another original TerrainLab running live steps.
const SAVE := "res://.godot-temp/site_shared_step_replay/original.json"
var checks := 0
var deadline := 0
var _started := false
var _finished := false

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if (_started and not _finished) or Time.get_ticks_msec() > deadline: quit(1)
	return false

func _scene() -> TerrainLab:
	var original := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	assert(original != null)
	var lab := original.instantiate() as TerrainLab
	lab.restore_only = true
	lab.pause_when_unfocused = false
	lab.exchange_enabled = true
	root.add_child(lab)
	assert(lab.terrain == null and not is_instance_valid(lab.npc), "Restore-only startup must not load a default save or add a worker")
	return lab

func _build(data: TerrainData, kind: String, anchor: Vector2i, extent := Vector2i.ONE) -> String:
	var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var layout := SiteRuntime.building_cells(data, kind, anchor, extent, options)
	assert(layout.ok, str(layout))
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var result := SiteRuntime.request_build(data, kind, cells, Callable(), options)
	assert(result.ok, str(result))
	var feature: Dictionary = data.site.features[result.feature]
	var task := {"version": 2, "zone": -1, "target": "feature:" + str(result.feature), "action": "construct",
		"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0,
		"status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, str(result.feature), float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	assert(str(feature.stage) == "complete")
	return str(result.feature)

func _initial_original() -> Dictionary:
	var lab := _scene()
	var data := TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(72, 72)})
	SiteEnvironment.initialize(data, "original-shared-step-replay")
	for y: int in range(5, 70):
		for x: int in range(5, 70):
			var index := data.index(Vector2i(x, y))
			data.site.terrain_changes[str(index)] = 0
			data.height_levels[index] = 0
	for key: String in data.resource_base:
		SiteEnvironment.change(data, key, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(6, 6))
	data.site.worker.cell = data.index(Vector2i(6, 7))
	data.site.worker_enabled = false
	data.site.capacity = 100000
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	assert(SiteRuntime.initialize_item_storage(data.site).ok)
	SiteRuntime.rebuild_terrain_edges(data)
	SiteEnvironment.rebuild_indexes(data)
	var farm := _build(data, "farm", Vector2i(10, 30), Vector2i(12, 6))
	_build(data, "well", Vector2i(8, 32))
	_build(data, "well", Vector2i(24, 32))
	data.site.minute = 0
	data.site.phase = 0.0
	data.site.worker.target = ""
	data.site.worker.mode = "idle"
	data.site.worker.progress = 0.0
	assert(SiteRuntime.operate_feature(data, farm).ok)
	# This is the explicitly authored initial test population. Every cold path
	# below restores its saved original body instead of creating test people.
	lab.bind_terrain(data)
	assert(lab.actor_present(lab.character))
	assert(lab.character.place(Vector2i(6, 6), true))
	lab.character.faction_id = 1
	var team := lab.army
	team.faction_id = 1
	team.roster_size = 3
	var slots := SiteRuntime.feature_work_slots(data, data.site.features[farm])
	var positions: Array[Vector2i] = [Vector2i(7, 30), data.cell_from_index(int(slots[0].cell)),
		data.cell_from_index(int(slots[1].cell))]
	assert(team.deploy_at(data, null, null, positions) and team.enable_combat(false))
	team.set_process(false)
	lab.site_controller.initialize_team_items(team)
	# Authored fixture deployment still consumes the original monotonic team ID.
	data.site["army_next_team"] = lab._next_army_identity()
	var worker_ids: Array[int] = [team.combat_identity(1), team.combat_identity(2)]
	assert(lab.site_controller.work_team.assign(team, worker_ids, team.combat_identity(0)).ok)
	var entry: Dictionary = lab.site_controller._enable_team_supply(team)
	assert(not entry.is_empty())
	entry.inventory.grain = 10
	lab.restore_only = false
	lab.movement_input_enabled = false
	lab.set_process(false)
	lab.character.set_process(false)
	lab._advance_action_time(0.5)
	var feature: Dictionary = data.site.features[farm]
	assert(bool(feature.batch_paid) and float(feature.production) > 0.0 and float(feature.production) < float(SiteRuntime.FEATURES.farm.cycle), "Fixture must leave an actually paid partial shared batch")
	assert(PersonFatigue.read(team.combat_units[1]) > 0.0 and PersonFatigue.read(team.combat_units[2]) > 0.0)
	assert(float(entry.sustain.at) > 0.0 and not entry.sustain.cohorts.is_empty())
	assert(lab.site_controller._capture_for_save().ok)
	data.site.actor_presence_version = 1
	var at := SiteRuntime.now(data) * 60.0
	assert(RegionSaveSlot.attach_settlement(data.site, at).ok)
	var validated: Dictionary = SiteStore._validate_state(data, data.site)
	assert(validated.ok, str(validated))
	var saved: Dictionary = SiteStore.save(data, SAVE)
	assert(saved.ok, str(saved))
	return {"lab": lab, "farm": farm, "at": at, "worker_ids": worker_ids}

func _restore(data: TerrainData) -> TerrainLab:
	var before := var_to_bytes([data.site, data.height_levels, data.flags, data.ramp_edges, data.resource_base])
	var lab := _scene()
	var restored := lab.restore_original_site(data)
	assert(restored.ok, str(restored))
	assert(lab.terrain != data and var_to_bytes([data.site, data.height_levels, data.flags, data.ramp_edges, data.resource_base]) == before,
		"Restore must leave the caller's original people/goods/base arrays untouched")
	assert(not is_instance_valid(lab.npc) and lab.combat_actors.size() == data.site.actors.size())
	assert(lab.site_controller.work_team.active_ids().size() == 2)
	return lab

func _near(actual: float, expected: float) -> void:
	assert(absf(actual - expected) < 0.000001, "%s != %s" % [actual, expected])

func _same_original(actual: Variant, expected: Variant, path: String = "state") -> void:
	if (actual is int or actual is float) and (expected is int or expected is float):
		assert(absf(float(actual) - float(expected)) < 0.000001,
			"%s actual=%s expected=%s" % [path, str(actual), str(expected)])
	elif actual is Dictionary and expected is Dictionary:
		assert(actual.size() == expected.size(), path)
		for key: Variant in actual:
			assert(expected.has(key), path + "." + str(key))
			_same_original(actual[key], expected[key], path + "." + str(key))
	elif actual is Array and expected is Array:
		assert(actual.size() == expected.size(), path)
		for index: int in range(actual.size()): _same_original(actual[index], expected[index], path + "[%d]" % index)
	else:
		assert(actual == expected, "%s actual=%s expected=%s" % [path, str(actual), str(expected)])

func _capture(lab: TerrainLab) -> Dictionary:
	assert(lab.site_controller._capture_for_save().ok)
	var state: Dictionary = lab.terrain.site.duplicate(true)
	var transport := lab.capture_fire_transport()
	assert(transport.ok, str(transport))
	if transport.state.is_empty(): state.erase("fire_transport")
	else: state.fire_transport = transport.state
	var owners := lab.capture_fire_owner_state()
	assert(owners.ok, str(owners))
	if owners.state.is_empty(): state.erase("fire_owners")
	else: state.fire_owners = owners.state
	var validated := SiteStore._validate_state(lab.terrain, state)
	assert(validated.ok, str(validated))
	return state

func _persistent_original_projection(data: TerrainData) -> Dictionary:
	# The original loader rebuilds these derived fields. Actual operating slots
	# are last-slice TerrainData metadata, never persistent work authorities.
	# Rebuild both detached candidates through that SAME original water owner;
	# compare every field, including all unchanged people, goods and paid work.
	var projected: TerrainData = SiteEnvironment.navigation_for_state(data, data.site.duplicate(true))
	projected.site.water_links = {}
	projected.site.water_status = {}
	projected.site.notices = []
	SiteRuntime.rebuild_water(projected)
	var capture_transport: Variant = data.get_meta(&"fire_transport_snapshot", Callable())
	if capture_transport is Callable and capture_transport.is_valid():
		var transport: Variant = capture_transport.call()
		assert(transport.ok, str(transport))
		if transport.state.is_empty(): projected.site.erase("fire_transport")
		else: projected.site.fire_transport = transport.state
	var capture_owners: Variant = data.get_meta(&"fire_owner_snapshot", Callable())
	if capture_owners is Callable and capture_owners.is_valid():
		var owners: Variant = capture_owners.call()
		assert(owners.ok, str(owners))
		if owners.state.is_empty(): projected.site.erase("fire_owners")
		else: projected.site.fire_owners = owners.state
	return projected.site

func _run() -> void:
	_started = true
	root.gui_embed_subwindows = true # Isolated headless test uses original embedded family UI.
	var initial := _initial_original()
	var saved := SiteStore.load_site(SAVE, Callable(), 1, true)
	assert(saved.ok, str(saved))
	var source: TerrainData = saved.data
	var original_source := var_to_bytes([source.site, source.height_levels, source.flags, source.ramp_edges, source.resource_base])
	# A remote Fire Site can keep the world on tactical time while this Site has
	# no local combat. Cold replay must restore that original per-step clock mode.
	var fire_source: TerrainData = SiteEnvironment.navigation_for_state(source, source.site.duplicate(true))
	var fire_action_step := 1.0 / 30.0
	var fire_epoch := "synthetic-cross-site-fire"
	var fire_start_game := float(fire_source.site.simulation_settlement.last_settled_game_seconds)
	var fire_start_action := float(fire_source.site.get("fire_transport", {}).get("action_cursor", 0.0))
	var fire_start_sequence := roundi(fire_start_action * 30.0)
	fire_source.site.fire_settlement = {"version": 1, "epoch": fire_epoch, "sequence": fire_start_sequence,
		"action_seconds": fire_start_action, "game_seconds": fire_start_game}
	var fire_live := _restore(fire_source)
	var fire_cold := _restore(fire_source)
	fire_live.restore_only = false
	fire_live.simulation_speed = 4.0
	fire_live.terrain.site.combat_left = fire_action_step
	var fire_live_step := fire_live._advance_original_shared_step(fire_action_step)
	assert(fire_live_step.ok and fire_live_step.completed, str(fire_live_step))
	var fire_target := fire_start_game + fire_action_step * 4.0
	var fire_segment := {"first_sequence": fire_start_sequence + 1, "last_sequence": fire_start_sequence + 1,
		"action_begin": fire_start_action, "action_end": fire_start_action + fire_action_step,
		"game_begin": fire_start_game, "game_end": fire_target,
		"scale": 4.0, "tactical_seconds": fire_action_step, "steps": 1}
	fire_cold._fire_replay_tracking = true
	fire_cold._fire_replay_epoch = fire_epoch
	fire_cold._fire_replay_segments = [fire_segment]
	fire_cold._fire_replay_end_sequence = fire_start_sequence + 1
	fire_cold._fire_replay_end_action = fire_start_action + fire_action_step
	fire_cold._fire_replay_end_game = fire_target
	var fire_cold_result := fire_cold.replay_site_to(fire_target)
	var fire_cold_transport := fire_cold.capture_fire_transport()
	var fire_cold_owners := fire_cold.capture_fire_owner_state()
	var fire_meta_capture: Variant = fire_cold.terrain.get_meta(&"fire_transport_snapshot", Callable())
	var fire_meta_transport: Variant = fire_meta_capture.call() if fire_meta_capture is Callable else {}
	assert(fire_cold_result.ok and fire_cold_result.status == "COMPLETE",
		"%s action=%s settlement=%s transport=%s owners=%s" % [str(fire_cold_result),
		str(fire_cold.fire_action_cursor), str(fire_cold.terrain.site.get("fire_settlement", {})),
		str(fire_cold_transport.get("state", {}).get("action_cursor", -1.0)),
		str(fire_cold_owners.get("state", {}).get("action_cursor", -1.0)) + " meta=" +
		str(fire_meta_transport.get("state", {}).get("action_cursor", -1.0))])
	assert(RegionSaveSlot.record_completed_replay_step(fire_live.terrain.site, fire_target,
		fire_target - fire_start_game).ok)
	RegionSaveSlot.record_completed_fire_replay(fire_live.terrain.site, {"epoch": fire_epoch,
		"sequence": fire_start_sequence + 1, "action_end": fire_start_action + fire_action_step, "game_end": fire_target})
	_same_original(_capture(fire_cold), _capture(fire_live))
	checks += 1
	var live := _restore(source)
	var slot := RegionSaveSlot.new()
	slot.pin = {"world_instance_id": "original-shared-step-replay", "slot_id": "synthetic-live-clock"}
	slot.control = {"logical_game_seconds": initial.at, "active_site_id": source.site.id}
	live.site_controller.region_slot = slot
	live.restore_only = false
	live.movement_input_enabled = false
	live._advance_action_time(20.0)
	# This synthetic slot has no fixed geography or formal Fire journal.
	live.terrain.site.erase("fire_settlement")
	var target := float(slot.control.logical_game_seconds)
	# Core clips fixed steps at work boundaries; the unconsumed fixed remainder
	# is carried to the next frame, so the 20 s are conserved, not all published.
	_near(target + live._action_time_remainder * 60.0 * live.simulation_speed, float(initial.at) + 1200.0)
	var expected := _capture(live)
	assert(float(expected.features[initial.farm].production) != float(source.site.features[initial.farm].production))
	assert(expected.inventory != source.site.inventory or expected.armies[0].units[1].cargo != source.site.armies[0].units[1].cargo)
	assert(float(expected.armies[0].units[1].fatigue) != float(source.site.armies[0].units[1].fatigue))
	assert(float(expected.team_supply["1"].sustain.at) > float(source.site.team_supply["1"].sustain.at))
	checks += 1

	var cold := _restore(source)
	var step := cold.replay_site_to(target, 0, 1)
	assert(step.ok and step.status == "PENDING" and float(step.pending) > 0.0)
	var retained := float(cold.terrain.site.simulation_settlement.last_settled_game_seconds)
	var wrong_target := cold.replay_site_to(target + 1.0, 0, 1)
	assert(not wrong_target.ok and wrong_target.code == "BUSY")
	_near(float(cold.terrain.site.simulation_settlement.last_settled_game_seconds), retained)
	while step.ok and step.status == "PENDING":
		assert(Time.get_ticks_msec() <= deadline)
		step = cold.replay_site_to(target, 0, 17)
	assert(step.ok and step.status == "COMPLETE" and float(step.pending) == 0.0, str(step))
	_same_original(_capture(cold), expected)
	_near(float(slot.control.logical_game_seconds), target)
	assert(var_to_bytes([source.site, source.height_levels, source.flags, source.ramp_edges, source.resource_base]) == original_source)
	checks += 1

	var settled := _capture(cold)
	var zero := cold.replay_site_to(target, 0, 1)
	assert(zero.ok and zero.steps == 0 and zero.pending == 0.0)
	_same_original(_capture(cold), settled)
	checks += 1

	# Reopening later on the computer without world game-time does zero work.
	# Store preserves the real partial paid batch and original bodies/supply.
	assert(SiteStore.save(cold.terrain, SAVE + ".settled").ok)
	var reopened := SiteStore.load_site(SAVE + ".settled", Callable(), 1, true)
	assert(reopened.ok)
	var revisit := _restore(reopened.data)
	var reopen_before: Dictionary = _capture(revisit)
	var offline := revisit.replay_site_to(target, 0, 1)
	assert(offline.ok and offline.steps == 0 and offline.pending == 0.0)
	_same_original(_capture(revisit), reopen_before)
	_same_original(_capture(revisit).water_status, _persistent_original_projection(revisit.terrain).water_status)
	_same_original(_persistent_original_projection(revisit.terrain), _persistent_original_projection(cold.terrain))
	checks += 1

	var blocked := _restore(source)
	blocked.terrain.site.paused = true
	var paused_before := var_to_bytes(blocked.terrain.site)
	var paused_result := blocked.replay_site_to(target, 0, 1)
	assert(not paused_result.ok and paused_result.code == "PAUSED_SITE")
	assert(var_to_bytes(blocked.terrain.site) == paused_before)
	assert(var_to_bytes([source.site, source.height_levels, source.flags, source.ramp_edges, source.resource_base]) == original_source)
	checks += 1

	# One original retained cold owner accepts retries of the SAME untouched
	# input and fixed target, keeping arrivals unmerged until complete.
	var host := _scene()
	var adapter := host.advance_cold_site(source, target)
	while not adapter.ok and adapter.code == "PENDING":
		assert(Time.get_ticks_msec() <= deadline)
		_near(float(slot.control.logical_game_seconds), target)
		assert(var_to_bytes([source.site, source.height_levels, source.flags, source.ramp_edges, source.resource_base]) == original_source)
		adapter = host.advance_cold_site(source, target)
	assert(adapter.ok and adapter.data != source, str(adapter))
	_same_original(adapter.data.site, expected)
	checks += 1

	# The same original phase also handles the combat->peace boundary in both
	# existing 30 Hz and retained 120 Hz modes, using real bodies/work/supply.
	for exchange: bool in [true, false]:
		var mixed_source := SiteEnvironment.navigation_for_state(source, source.site.duplicate(true))
		mixed_source.site.combat_left = 0.04
		var mixed_live := _restore(mixed_source)
		var mixed_cold := _restore(mixed_source)
		for lab: TerrainLab in [mixed_live, mixed_cold]:
			lab.exchange_enabled = exchange
			lab.fixed_action_steps_enabled = true
			for actor: TerrainTestCharacter in lab.combat_actors: actor.exchange_enabled = exchange
			for team: TerrainArmy in lab.combat_armies: team.exchange_enabled = exchange
		var mixed_slot := RegionSaveSlot.new()
		mixed_slot.pin = {"world_instance_id": "original-shared-step-replay", "slot_id": "synthetic-mixed-clock"}
		mixed_slot.control = {"logical_game_seconds": initial.at, "active_site_id": source.site.id}
		mixed_live.site_controller.region_slot = mixed_slot
		mixed_live.restore_only = false
		mixed_live.movement_input_enabled = false
		mixed_live._advance_action_time(0.2)
		var mixed_target := float(mixed_slot.control.logical_game_seconds)
		_near(mixed_target + mixed_live._action_time_remainder * 60.0 * mixed_live.simulation_speed, float(initial.at) + 0.2 * 60.0) # TCM: one Site rate
		var mixed_result := mixed_cold.replay_site_to(mixed_target)
		assert(mixed_result.ok and mixed_result.status == "COMPLETE", str(mixed_result))
		mixed_live.terrain.site.erase("fire_settlement")
		_same_original(_capture(mixed_cold), _capture(mixed_live))
		var retained_geometry: Dictionary = mixed_cold.army.incoming_geometry(1)
		assert(not retained_geometry.body.is_empty(), "Original retained person has admitted contact geometry")
		mixed_live.free()
		assert(mixed_cold.army.incoming_geometry(1) == retained_geometry, "Closing another Lab preserves the retained original person contact geometry")
		mixed_cold.free()
	checks += 1

	# Real original environmental damage, death animation/remains settlement,
	# then family UI pauses the live world AFTER a fully completed shared step.
	var death_live := _restore(source)
	var death_slot := RegionSaveSlot.new()
	death_slot.pin = {"world_instance_id": "original-shared-step-replay", "slot_id": "synthetic-death-clock"}
	death_slot.control = {"logical_game_seconds": initial.at, "active_site_id": source.site.id}
	death_live.site_controller.region_slot = death_slot
	death_live.restore_only = false
	death_live.movement_input_enabled = false
	death_live.site_controller._apply_supply_damage(death_live.character.person_id, 1000.0)
	death_live._advance_action_time(8.0)
	assert(death_live.character.hp == 0.0 and death_live.character.loot_settled)
	assert(death_live.terrain.site.paused and self.paused)
	assert(float(death_slot.control.logical_game_seconds) > float(initial.at))
	_near(float(death_slot.control.logical_game_seconds), SiteRuntime.now(death_live.terrain) * 60.0)
	assert(not death_live.character.remains_id.is_empty() and death_live.terrain.site.ground_loot.has(death_live.character.remains_id))
	death_live.free()
	self.paused = false # Isolated test SceneTree cleanup after the paused live Lab is freed.
	checks += 1

	# Quiet cold death keeps the SAME remains owner and continues original
	# workers; it does not open a global family selection dialog or pause Tree.
	var death_cold := _restore(source)
	death_cold.site_controller._apply_supply_damage(death_cold.character.person_id, 1000.0)
	var death_result := death_cold.replay_site_to(float(initial.at) + 600.0)
	assert(death_result.ok and death_result.status == "COMPLETE", str(death_result))
	assert(death_cold.character.hp == 0.0 and death_cold.character.loot_settled and not self.paused)
	assert(not death_cold.terrain.site.paused and not is_instance_valid(death_cold.site_controller._family_dialog))
	assert(death_cold.terrain.site.ground_loot.has(death_cold.character.remains_id))
	assert(float(death_cold.terrain.site.features[initial.farm].production) != float(source.site.features[initial.farm].production))
	death_cold.free()
	checks += 1

	var final_contact_source: RefCounted = TerrainArmy.contact_source_for(initial.lab.army.equipment_appearance(1))
	assert(final_contact_source != null and is_instance_valid(final_contact_source.editor))
	for lab: TerrainLab in [initial.lab, live, cold, revisit, blocked, host, fire_live, fire_cold]: lab.free()
	assert(not is_instance_valid(final_contact_source.editor), "Last original Lab exit disposes the original root query resource")
	TerrainArmy.release_contact_source()
	assert(checks == 10)
	assert(Time.get_ticks_msec() <= deadline, "Complete original checks and cleanup stay inside the unchanged 90s deadline")
	print("SITE_SHARED_STEP_CONTACT_RESOURCE_LIFETIME_PASS: retained original geometry survives another Lab exit in both 30/120Hz modes; final Lab exit disposes original resource; same 90s deadline")
	_finished = true
	print("SITE_SHARED_STEP_REPLAY_PASS: real original Actor + two original Army workers, actually paid partial farm batch, physical food/supply/fatigue, stay-vs-cold equality, bounded fixed-target pending, zero-game-time offline/revisit, paused refusal, untouched source and retained scene retries, both 30/120 Hz mixed combat clock, real death/remains/poststep live pause permit and quiet cold continuity; no FPS/GPU/release claim")
	quit(0)
