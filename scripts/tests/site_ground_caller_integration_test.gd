extends "res://scripts/tests/site_cross_boundary_wall_test.gd"
## Install the caller patch after ShipC's original save_to wrapper, then copy
## this test to scripts/tests. Only Root runs the canonical bounded verifier.
var caller_checks: int = 0

func _ground_json(value: Variant) -> Variant:
	# Compare complete persisted values through the same JSON projection as Store.
	return JSON.parse_string(JSON.stringify(value, "", true, true))

func _ground_expected_arrival(original: Dictionary, cell: Vector2i) -> Dictionary:
	var expected: Dictionary = original.duplicate(true)
	var arrival: Vector2 = (Vector2(cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	expected.cell = [cell.x, cell.y]
	expected.position = [arrival.x, arrival.y]
	expected.movement_from = expected.cell.duplicate()
	expected.movement_left = 0.0
	if expected.has("movement"):
		expected.movement.start = expected.position.duplicate()
		expected.movement.duration = 0.0
		expected.movement.elapsed = 0.0
	return expected

class RefusingClockSlot:
	extends RegionSaveSlot
	func record_active_step(_state: Dictionary, _game_seconds: Variant, _permit: Dictionary = {}, _fire_step: Dictionary = {}) -> Dictionary:
		return fail("INJECTED_PUBLISHER_FAILURE", "Original completed-step publisher refused")

func _caller_scene(with_npc: bool = false) -> TerrainLab:
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	assert(scene != null)
	var lab: TerrainLab = scene.instantiate() as TerrainLab
	lab.restore_only = true
	lab.pause_when_unfocused = false
	if with_npc: lab.npc = TerrainTestNPC.new() # Explicit test presenter; never an arriving replacement person.
	root.add_child(lab)
	assert(lab.terrain == null)
	assert(is_instance_valid(lab.npc) == with_npc)
	lab.set_process(false)
	return lab

func _caller_fixture(name: String, direction: Vector2i = Vector2i.RIGHT, with_npc: bool = true, at: float = 0.0) -> Dictionary:
	var edge: int = TerrainData.DIRECTIONS.find(direction)
	var coordinate: Vector2i = Vector2i(12, -8)
	var cell: Vector2i = [Vector2i(50, 0), Vector2i(99, 50), Vector2i(50, 99), Vector2i(0, 50)][edge]
	var boundary: Dictionary = RegionSaveSlot.boundary_pair(coordinate, cell, direction)
	var data: TerrainData = _flat_site(coordinate)
	var neighbour: TerrainData = _flat_site(Vector2i(boundary.site))
	var geography: PinnedGeography = PinnedGeography.new()
	geography.manifest_hash = "b".repeat(64)
	geography.manifest = {"atlas_id": RegionGrid.ATLAS_ID, "grid_contract_version": 1, "base_revision": "bridge_contract_v1"}
	geography.bases[coordinate] = _bridge_base(data)
	geography.bases[boundary.site] = _bridge_base(neighbour)
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	slot.source = geography
	slot.folder = bridge_output.path_join(name)
	slot.pin = {"format": 1, "world_instance_id": "ground_caller_world", "slot_id": name,
		"atlas_id": RegionGrid.ATLAS_ID, "grid_contract_version": 1, "base_revision": "bridge_contract_v1",
		"manifest_sha256": geography.manifest_hash, "ramp_rule_revision": RegionTerrainAdapter.RAMP_RULE_REVISION}
	assert(slot._recover_control().ok)
	var lab: TerrainLab = _caller_scene(with_npc)
	data.site.worker_enabled = false
	data.site.minute = floori(at / 60.0)
	data.site.phase = at / 60.0 - float(data.site.minute)
	# A Site born through RegionSaveSlot.open_site carries the Slot's fire_settlement stamp
	# (region_save_slot.gd open_site); the original shared step's owner guard requires it
	# (terrain_lab.gd _region_original_interval_guard, REGION_OWNER_FIRE_SOURCE). attach_active_site
	# only re-stamps when it resets the fire clock (the at > 0 fixtures), so stamp the at = 0 birth here.
	if at == float(slot.control.logical_game_seconds) and not data.site.has("fire_settlement"):
		var birth_clock: Dictionary = slot.control.fire_clock
		data.site["fire_settlement"] = {"version": 1, "epoch": str(birth_clock.epoch), "sequence": int(birth_clock.sequence),
			"action_seconds": float(birth_clock.action_seconds), "game_seconds": float(slot.control.logical_game_seconds)}
	# The fixture Site is the live active Site: bind it live (receipt live/original_site), not as a
	# restore-only cold owner, so the Slot can admit it below exactly as bind_terrain does in the game.
	lab.site_controller._auto_save_blocked = true # No formal/current save from the live bind.
	lab.restore_only = false
	lab.bind_terrain(data)
	assert(lab.terrain == data and lab.actor_present(lab.character))
	assert(lab.character.place(cell, true))
	lab.character.hp = 73.0
	lab.character.fatigue = 37.0
	lab.character.faction_id = 1
	data.site.manual.cargo = {"grain": 4, "wood": 2}
	lab.character.ammo_inventory = data.site.manual.cargo
	if with_npc:
		assert(lab.npc.place(Vector2i(10, 9), true))
		lab.npc.faction_id = 1
		lab.npc.issue_command(TerrainTestNPC.Command.STOP)
		lab.npc.set_process(false)
	var identity: int = lab.character.person_id
	data.site.controlled_person_id = identity
	var pool: Dictionary = Store.Sustain.create(at)
	assert(Store.Sustain.add_members(pool, {identity: {"hp": lab.character.hp}}, [identity]).ok)
	if not data.site.has("person_supply"): data.site.person_supply = {}
	data.site.person_supply[str(identity)] = pool
	assert(lab.site_controller._capture_for_save().ok)
	data.site.actor_presence_version = 1
	assert(slot.attach_active_site(data).ok)
	lab.site_controller.region_slot = slot
	# attach_active_site leaves the owner committed-unbound; the original shared step's region permit
	# (GameplayClock.begin_permit) requires the live/original_site mode that the complete bind admits.
	# Same formal activation as bind_terrain with a slot present (and site_ship_travel_test).
	var activated: Dictionary = slot.acknowledge_region_bind(data, lab.region_bind_receipt(data))
	assert(activated.ok, "Original active Site was not admitted by its complete live bind: " + str(activated))
	lab.site_controller.save_path = slot.site_path(coordinate)
	lab.site_controller._auto_save_blocked = true
	lab.restore_only = false
	lab.movement_input_enabled = true
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	assert(Store._validate_state(data, data.site).ok)
	return {"lab": lab, "data": data, "slot": slot, "id": identity, "from": coordinate,
		"to": boundary.site, "cell": cell, "arrival": boundary.cell, "direction": direction, "geography": geography}

func _caller_deadline() -> void:
	assert(Time.get_ticks_msec() <= deadline, "Ground caller integration exceeded its internal 90 s deadline")

func _finish_action(fixture: Dictionary) -> void:
	var lab: TerrainLab = fixture.lab
	var slot: RegionSaveSlot = fixture.slot
	# Actual held input is sampled between original Site.tick and body/contact
	# phases. Its queued crossing waits for that WHOLE step's clock publication.
	var input_at: float = float(slot.control.logical_game_seconds)
	lab._held_directions[KEY_D] = Vector2i(fixture.direction)
	lab._last_direction_key = KEY_D
	lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(str(lab.site_controller._ground_crossing.stage) == "queued")
	assert(float(slot.control.logical_game_seconds) > input_at and slot._marker.is_empty())
	assert(RegionSaveSlot.validate_settlement(fixture.data.site, float(slot.control.logical_game_seconds)).pending == 0.0)
	lab.site_controller.finish_tick()
	assert(str(lab.site_controller._ground_crossing.stage) == "action")
	assert(lab.site_controller.person_actions.is_busy(int(fixture.id)))
	assert(lab.terrain == fixture.data and slot._marker.is_empty())
	var started: float = float(slot.control.logical_game_seconds)
	lab._advance_action_time(TerrainTestCharacter.MOVE_DURATION * 0.5)
	assert(lab.terrain == fixture.data and slot._marker.is_empty(), "Boundary input teleported before ACTION finished")
	assert(str(lab.site_controller._ground_crossing.stage) == "action")
	assert(float(slot.control.logical_game_seconds) > started, "Original shared-step clock did not run")
	assert(lab.character.terrain_cell == fixture.cell)
	lab._advance_action_time(TerrainTestCharacter.MOVE_DURATION + 0.25)
	assert(str(lab.site_controller._ground_crossing.stage) == "commit")
	assert(not lab.site_controller.person_actions.is_busy(int(fixture.id)))
	assert(slot._marker.is_empty() and lab.terrain == fixture.data, "Published inside post-contact settlement")
	assert(RegionSaveSlot.validate_settlement(fixture.data.site, float(slot.control.logical_game_seconds)).pending == 0.0)

func _caller_roundtrip(direction: Vector2i) -> void:
	var fixture: Dictionary = _caller_fixture("caller_" + str(TerrainData.DIRECTIONS.find(direction)), direction)
	var lab: TerrainLab = fixture.lab
	var slot: RegionSaveSlot = fixture.slot
	_finish_action(fixture)
	assert(lab.site_controller._capture_for_save().ok)
	var latest: Dictionary = fixture.data.site.duplicate(true)
	var at: float = float(slot.control.logical_game_seconds)
	var remainder: float = lab._action_time_remainder
	assert(remainder > 0.0)
	lab.site_controller.finish_tick()
	assert(lab.terrain != fixture.data and lab.character.terrain_cell == fixture.arrival)
	assert(lab.character.person_id == int(fixture.id) and lab.site_controller._ground_crossing.is_empty())
	assert(float(slot.control.logical_game_seconds) == at and str(slot.control.active_site_id) == str(lab.terrain.site.id))
	assert(lab._action_time_remainder == remainder, "Bind discarded already-earned elapsed time")
	assert(int(slot._marker.generation) == 1 and slot._marker.sites.size() == 2)
	assert(fixture.data.site == latest, "Bind mutated departing live owner rather than a detached pair")
	var loaded_from: Dictionary = slot._load_checked(slot.site_path(Vector2i(fixture.from)), Vector2i(fixture.from))
	var loaded_to: Dictionary = slot._load_checked(slot.site_path(Vector2i(fixture.to)), Vector2i(fixture.to))
	assert(loaded_from.ok and loaded_to.ok)
	assert(loaded_from.data.site.fire_transport.orders.keys() == [-int(latest.actors.npc.person_id)])
	assert(loaded_to.data.site.fire_transport.orders.keys() == [-int(fixture.id)])
	assert(not loaded_from.data.site.actors.has("player") and _ground_json(loaded_from.data.site.actors.npc) == _ground_json(latest.actors.npc))
	assert(loaded_to.data.site.actors.keys() == ["player"] and not lab.actor_present(lab.npc))
	assert(_ground_json(loaded_to.data.site.actors.player.item_state) == _ground_json(latest.actors.player.item_state))
	assert(loaded_to.data.site.actors.player.hp == latest.actors.player.hp and loaded_to.data.site.actors.player.fatigue == latest.actors.player.fatigue)
	var expected_player: Dictionary = _ground_expected_arrival(latest.actors.player, Vector2i(fixture.arrival))
	assert(_ground_json(loaded_to.data.site.actors.player) == _ground_json(expected_player), "Complete original player snapshot changed during caller transfer")
	assert(_ground_json(loaded_to.data.site.manual.cargo) == _ground_json(latest.manual.cargo) and loaded_from.data.site.manual.cargo.is_empty())
	assert(_ground_json(loaded_to.data.site.person_supply[str(fixture.id)]) == _ground_json(latest.person_supply[str(fixture.id)]))
	assert(not loaded_from.data.site.person_supply.has(str(fixture.id)))
	for key: String in loaded_to.data.site.item_records:
		assert(_ground_json(loaded_to.data.site.item_records[key]) == _ground_json(latest.item_records[key]) and not loaded_from.data.site.item_records.has(key))
	# Dependency: ShipC routes save_to through the SAME RegionSaveSlot publisher.
	var generation_one: String = slot.site_path(Vector2i(fixture.to))
	var checksum: String = FileAccess.get_sha256(generation_one)
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	assert(saved.ok, str(saved))
	assert(int(slot._marker.generation) == 2 and FileAccess.get_sha256(generation_one) == checksum)
	assert(lab.site_controller.save_path == slot.site_path(Vector2i(fixture.to)))
	assert(slot._recover_control().ok)
	lab.free()
	caller_checks += 1

func _caller_action_cancel() -> void:
	var fixture: Dictionary = _caller_fixture("action_cancel")
	var lab: TerrainLab = fixture.lab
	lab._try_move(Vector2i(fixture.direction))
	lab.site_controller.finish_tick()
	lab._advance_action_time(TerrainTestCharacter.MOVE_DURATION * 0.5)
	assert(lab.site_controller.person_actions.cancel(int(fixture.id)).ok, "Existing Actions.cancel ceased to work")
	lab.site_controller.finish_tick()
	assert(lab.site_controller._ground_crossing.is_empty() and not lab.site_controller.ground_crossing_blocks_clock())
	assert(fixture.slot._marker.is_empty() and lab.terrain == fixture.data and lab.character.terrain_cell == fixture.cell)
	lab._try_move(Vector2i(fixture.direction))
	lab.site_controller.finish_tick()
	var button: Button = lab.find_child("CancelPersonAction", true, false) as Button
	assert(button != null)
	button.pressed.emit()
	assert(lab.site_controller._ground_crossing.is_empty() and not lab.site_controller.person_actions.is_busy(int(fixture.id)))
	lab.free()
	caller_checks += 1

func _caller_destination_npc() -> void:
	var fixture: Dictionary = _caller_fixture("missing_presenter", Vector2i.RIGHT, false)
	var destination: TerrainData = _flat_site(Vector2i(fixture.to))
	var author: TerrainLab = _caller_scene(true)
	author.npc.person_id = 2027
	author.bind_terrain(destination)
	assert(author.actor_present(author.npc))
	assert(author.site_controller._capture_for_save().ok)
	destination.site.actor_presence_version = 1
	destination.site.actors.erase("player")
	# The authored fixture contains ONLY this NPC. Remove the author's unused
	# initial player equipment before saving that explicitly authored population.
	for key: String in destination.site.item_records.keys():
		if str(destination.site.item_records[key].holder) == "person:1": destination.site.item_records.erase(key)
	destination.site.manual.cargo = {}
	destination.site.controlled_person_id = 2027
	destination.site.next_person_id = maxi(2028, int(destination.site.get("next_person_id", 2)))
	assert(RegionSaveSlot.attach_settlement(destination.site, 0.0).ok)
	var path: String = fixture.slot.site_path(Vector2i(fixture.to))
	var stale_capture := Store.save(destination, path)
	assert(not stale_capture.ok and stale_capture.code == "CORRUPT_FIRE_OWNER", str(stale_capture))
	author.bind_terrain(destination)
	assert(author.actor_present(author.npc) and not author.actor_present(author.character))
	assert(Store.save(destination, path).ok)
	var original: String = FileAccess.get_file_as_string(path)
	var lab: TerrainLab = fixture.lab
	var before: PackedByteArray = var_to_bytes(fixture.data.site)
	var begun: Dictionary = lab.site_controller.begin_ground_crossing(int(fixture.id), Vector2i(fixture.direction))
	assert(begun.ok and str(lab.site_controller._ground_crossing.stage) == "queued")
	var preflight: Dictionary = lab.site_controller._ground_presenter_preflight()
	assert(not preflight.ok and preflight.code == "BIND_GUARD", str(preflight))
	lab.site_controller.finish_tick()
	assert(lab.site_controller._ground_crossing.is_empty(), "Missing presenter did not atomically reject the queued request")
	assert(lab.terrain == fixture.data and var_to_bytes(fixture.data.site) == before)
	assert(FileAccess.get_file_as_string(path) == original and fixture.slot._marker.is_empty())
	assert(not is_instance_valid(lab._cold_replay_lab) and lab.site_controller._ground_crossing.is_empty())
	assert(destination.site.actors.has("npc") and int(destination.site.actors.npc.person_id) == 2027)
	author.free()
	lab.free()
	caller_checks += 1

func _caller_cold_pending() -> void:
	# An actually visited original empty destination retains its saved epoch.
	# Large real game-time debt guarantees bounded original replay spans frames;
	# this invokes TerrainLab.advance_cold_site, never a fake clock or result.
	var fixture: Dictionary = _caller_fixture("cold_pending", Vector2i.RIGHT, false, 18000.0)
	var lab: TerrainLab = fixture.lab
	var slot: RegionSaveSlot = fixture.slot
	# Center decision (2026-10-27): a cold replay source must be a committed snapshot (b85549b), so the
	# visited empty destination is born and committed through the original Slot, together with the active
	# Site in one marker, and its debt is real elapsed world time on the active Site afterwards.
	var saved_active: Dictionary = slot.save_site(fixture.data)
	assert(saved_active.ok, "Initial active Site commit: " + str(saved_active))
	var opened_destination: Dictionary = slot.open_site(Vector2i(fixture.to))
	assert(opened_destination.ok, "Original birth of the visited destination: " + str(opened_destination))
	var destination: TerrainData = opened_destination.data
	destination.site["actor_presence_version"] = 1
	destination.site["actors"] = {}
	assert(Runtime.initialize_item_storage(destination.site).ok)
	assert(RegionSaveSlot.attach_settlement(destination.site, float(slot.control.logical_game_seconds)).ok)
	destination.site["fire_settlement"] = fixture.data.site.fire_settlement.duplicate(true)
	var saved_destination: Dictionary = slot.save_site(destination)
	assert(saved_destination.ok, "Committed visited destination: " + str(saved_destination))
	var path: String = str(saved_destination.path)
	var original: String = FileAccess.get_file_as_string(path)
	# Real world time passes on the active Site only; the committed destination keeps its saved epoch.
	# The debt must exceed one bounded call (advance_region_cold_actual_fixed: at most 128 original
	# steps per call), so the actual replay spans frames and stays PENDING in PREPARE. 10 action
	# seconds are 300 original 30 Hz steps (600 game seconds at speed 1), each replayed exactly.
	var debt_from: float = float(slot.control.logical_game_seconds)
	var debt_action: float = 10.0
	lab._advance_action_time(debt_action)
	assert(lab.site_controller._original_step_fault.is_empty())
	assert(float(slot.control.logical_game_seconds) - debt_from > 128.0 * TerrainLab.EXCHANGE_ACTION_STEP * 60.0 * lab.simulation_speed,
		"Cold destination debt does not span one bounded replay call: " + str(float(slot.control.logical_game_seconds) - debt_from))
	var committed_generation: int = int(slot._marker.generation)
	var committed_sites: int = slot._marker.sites.size()
	lab._action_time_remainder = 0.19
	lab._try_move(Vector2i(fixture.direction))
	var diag_after_input: String = str(lab.site_controller._ground_crossing.get("stage", ""))
	lab.site_controller.finish_tick()
	if str(lab.site_controller._ground_crossing.get("stage", "")) != "prepare":
		# DIAG_ONLY (HEADFIX15): why the committed-destination crossing is not PENDING in PREPARE.
		print("DIAG_ONLY GROUND_COLD_QUEUE ", JSON.stringify({"after_input": diag_after_input,
			"after_tick": str(lab.site_controller._ground_crossing.get("stage", "")), "message": lab.site_controller.message.text,
			"fault": str(lab.site_controller._original_step_fault), "marker_generation": slot._marker.get("generation"),
			"clock": float(slot.control.logical_game_seconds), "debt_from": debt_from}))
	assert(str(lab.site_controller._ground_crossing.get("stage", "")) == "prepare")
	assert(is_instance_valid(lab._cold_replay_lab))
	var retained_hash: String = str(lab.site_controller._ground_crossing.pending_sha256)
	assert(retained_hash.length() == 64 and retained_hash == lab._cold_replay_signature)
	var at: float = float(slot.control.logical_game_seconds)
	var before: PackedByteArray = var_to_bytes(fixture.data.site)
	assert(lab._action_elapsed_input(10.0) == 0.0 and not lab._process_sample_active)
	lab._advance_action_time(10.0)
	lab._try_move(Vector2i.LEFT)
	assert(lab._action_time_remainder == 0.19 and float(slot.control.logical_game_seconds) == at)
	assert(var_to_bytes(fixture.data.site) == before and int(slot._marker.generation) == committed_generation)
	assert(not lab.site_controller.save_to(lab.site_controller.save_path).ok)
	assert(not lab.site_controller.load_from(path).ok)
	assert(lab.site_controller.cancel_ground_crossing(int(fixture.id)).ok)
	assert(not is_instance_valid(lab._cold_replay_lab) and lab.site_controller._ground_crossing.is_empty())
	assert(FileAccess.get_file_as_string(path) == original and int(slot._marker.generation) == committed_generation)

	lab._try_move(Vector2i(fixture.direction))
	lab.site_controller.finish_tick()
	while str(lab.site_controller._ground_crossing.get("stage", "")) == "prepare":
		_caller_deadline()
		assert(float(slot.control.logical_game_seconds) == at and lab._action_time_remainder == 0.19)
		lab._process(10.0) # The ORIGINAL frame retries finish_tick while input elapsed is zero.
	if str(lab.site_controller._ground_crossing.get("stage", "")) != "action":
		# DIAG_ONLY (HEADFIX15): the completed cold replay's refusal (see REPLAY_SOURCE_MISMATCH).
		print("DIAG_ONLY GROUND_COLD_PREPARE_END ", JSON.stringify({"attempt": 1, "stage": str(lab.site_controller._ground_crossing.get("stage", "")),
			"message": lab.site_controller.message.text, "fault": str(lab.site_controller._original_step_fault)}))
	assert(str(lab.site_controller._ground_crossing.get("stage", "")) == "action")
	lab._advance_action_time(TerrainTestCharacter.MOVE_DURATION + 0.25)
	assert(str(lab.site_controller._ground_crossing.stage) == "commit")
	var completed_at: float = float(slot.control.logical_game_seconds)
	var earned: float = lab._action_time_remainder
	lab.site_controller.finish_tick()
	assert(str(lab.site_controller._ground_crossing.stage) == "commit" and is_instance_valid(lab._cold_replay_lab))
	var commit_hash: String = str(lab.site_controller._ground_crossing.pending_sha256)
	assert(commit_hash == lab._cold_replay_signature and float(lab._cold_replay_target) == completed_at)
	assert(float(slot.control.logical_game_seconds) == completed_at and int(slot._marker.generation) == committed_generation)
	var completed_source: PackedByteArray = var_to_bytes(fixture.data.site)
	assert(lab.site_controller.cancel_ground_crossing(int(fixture.id)).ok)
	assert(not is_instance_valid(lab._cold_replay_lab) and int(slot._marker.generation) == committed_generation)
	assert(float(slot.control.logical_game_seconds) == completed_at and var_to_bytes(fixture.data.site) == completed_source)
	assert(lab._action_time_remainder == earned and FileAccess.get_file_as_string(path) == original)
	# A fresh attempt resumes the original actor at its earned source time.
	lab._try_move(Vector2i(fixture.direction))
	lab.site_controller.finish_tick()
	while str(lab.site_controller._ground_crossing.get("stage", "")) == "prepare":
		_caller_deadline()
		assert(float(slot.control.logical_game_seconds) == completed_at and lab._action_time_remainder == earned)
		lab._process(10.0)
	if str(lab.site_controller._ground_crossing.get("stage", "")) != "action":
		# DIAG_ONLY (HEADFIX15): the completed cold replay's refusal (see REPLAY_SOURCE_MISMATCH).
		print("DIAG_ONLY GROUND_COLD_PREPARE_END ", JSON.stringify({"attempt": 2, "stage": str(lab.site_controller._ground_crossing.get("stage", "")),
			"message": lab.site_controller.message.text, "fault": str(lab.site_controller._original_step_fault)}))
	assert(str(lab.site_controller._ground_crossing.get("stage", "")) == "action")
	lab._advance_action_time(TerrainTestCharacter.MOVE_DURATION + 0.25)
	assert(str(lab.site_controller._ground_crossing.stage) == "commit")
	completed_at = float(slot.control.logical_game_seconds)
	earned = lab._action_time_remainder
	lab.site_controller.finish_tick()
	assert(str(lab.site_controller._ground_crossing.stage) == "commit" and is_instance_valid(lab._cold_replay_lab))
	while not lab.site_controller._ground_crossing.is_empty():
		_caller_deadline()
		assert(float(slot.control.logical_game_seconds) == completed_at and lab._action_time_remainder == earned)
		assert(lab.terrain == fixture.data and FileAccess.get_file_as_string(path) == original)
		lab._process(10.0)
	assert(lab.terrain != fixture.data and lab.character.terrain_cell == fixture.arrival,
		"ground=" + str(lab.site_controller._ground_crossing) + " message=" + lab.site_controller.message.text
		+ " fault=" + str(lab.site_controller._original_step_fault) + " marker=" + str(slot._marker))
	assert(float(slot.control.logical_game_seconds) == completed_at and lab._action_time_remainder == earned)
	assert(int(slot._marker.generation) == committed_generation + 1 and slot._marker.sites.size() == committed_sites)
	assert(not is_instance_valid(lab._cold_replay_lab))
	lab.free()
	caller_checks += 1

func _caller_pruned_clock_commit() -> void:
	var fixture: Dictionary = _caller_fixture("pruned_fire_clock_commit", Vector2i.RIGHT, false, 18000.0)
	var lab: TerrainLab = fixture.lab
	var slot: RegionSaveSlot = fixture.slot
	var data: TerrainData = fixture.data
	var cold_coordinate: Vector2i = fixture.to
	var saved_active := slot.save_site(data)
	if not saved_active.ok: _fire_prefix_fail("Initial active Site checkpoint", saved_active); return
	var cold_opened := slot.open_site(cold_coordinate)
	if not cold_opened.ok: _fire_prefix_fail("Open original cold Site", cold_opened); return
	var cold_data: TerrainData = cold_opened.data
	cold_data.site["actor_presence_version"] = 1
	cold_data.site["actors"] = {}
	var item_storage := Runtime.initialize_item_storage(cold_data.site)
	if not item_storage.ok: _fire_prefix_fail("Initialize original cold Site item owner", item_storage); return
	var attached := RegionSaveSlot.attach_settlement(cold_data.site, float(slot.control.logical_game_seconds))
	if not attached.ok: _fire_prefix_fail("Attach cold Site shared-step watermark", attached); return
	cold_data.site["fire_settlement"] = data.site.fire_settlement.duplicate(true)
	var saved_cold := slot.save_site(cold_data)
	if not saved_cold.ok: _fire_prefix_fail("Cold Site checkpoint and index", saved_cold); return
	# The original cold replay accepts only the selected committed snapshot (terrain_lab.gd
	# _region_selected_bind_source): continue from the Slot's own readback, not the pre-save draft,
	# which lacks the fields the Store writes (armies, vehicles, supply, housing, lineage counters).
	cold_data = saved_cold.data
	var action_step := 1.0 / 30.0
	lab.simulation_speed = 0.5
	var first_step: Dictionary = lab._advance_original_shared_step(action_step)
	if not first_step.ok or not first_step.completed: _fire_prefix_fail("Original shared step 1", first_step); return
	lab.simulation_speed = 2.0
	var second_step: Dictionary = lab._advance_original_shared_step(action_step)
	if not second_step.ok or not second_step.completed: _fire_prefix_fail("Original shared step 2", second_step); return
	var mixed_clock: Dictionary = slot.control.fire_clock
	if not (int(mixed_clock.base_sequence) == 0 and mixed_clock.journal.size() == 2
		and float(mixed_clock.journal[0].scale) == 0.5 and int(mixed_clock.journal[0].first_sequence) == 1
		and float(mixed_clock.journal[1].scale) == 2.0 and int(mixed_clock.journal[1].first_sequence) == 2):
		_fire_prefix_fail("Published journal retains both historical scales", mixed_clock); return
	var mixed_target := float(slot.control.logical_game_seconds)
	var cold_result := lab.advance_cold_site(cold_data, mixed_target)
	while not cold_result.ok and cold_result.get("code", "") == "PENDING":
		if Time.get_ticks_msec() > deadline: _fire_prefix_fail("Mixed-scale cold Site replay deadline", cold_result); return
		lab._process(10.0)
		cold_result = lab.advance_cold_site(cold_data, mixed_target)
	if not cold_result.ok or int(cold_result.data.site.fire_settlement.sequence) != 2:
		_fire_prefix_fail("Cold replay across historical scales 0.5 and 2", cold_result); return
	var saved_replay := slot.save_site(cold_result.data)
	if not saved_replay.ok: _fire_prefix_fail("Mixed-scale cold replay checkpoint", saved_replay); return
	lab.simulation_speed = 4.0
	var third_step: Dictionary = lab._advance_original_shared_step(action_step)
	if not third_step.ok or not third_step.completed: _fire_prefix_fail("Original shared step 3", third_step); return
	var clock: Dictionary = slot.control.fire_clock
	if not (int(clock.base_sequence) == 2 and clock.journal.size() == 1
		and int(clock.journal[0].first_sequence) == 3 and int(clock.journal[0].steps) == 1
		and float(clock.journal[0].scale) == 4.0):
		_fire_prefix_fail("Pruned suffix after mixed-scale cold Site", clock); return
	var saved_trimmed := slot.save_site(data)
	if not saved_trimmed.ok: _fire_prefix_fail("Atomic trimmed-clock and active Site checkpoint", saved_trimmed); return
	var reopened := RegionSaveSlot.new()
	reopened.source = slot.source
	reopened.folder = slot.folder
	reopened.pin = slot.pin.duplicate(true)
	reopened.cold_site_advance = Callable(lab, "advance_cold_site")
	var recovered := reopened._recover_control()
	if not (recovered.ok and int(reopened.control.fire_clock.base_sequence) == 2
		and int(reopened.control.fire_clock.journal[0].first_sequence) == 3):
		_fire_prefix_fail("Reopen pruned control journal", recovered); return
	lab.site_controller.region_slot = reopened
	var loaded_cold := reopened.open_site(cold_coordinate)
	if not (loaded_cold.ok and int(loaded_cold.data.site.fire_settlement.sequence) == 3
		and absf(float(loaded_cold.data.site.get("fire_transport", {}).get("action_cursor", -1.0))
			- float(clock.action_seconds)) < 0.00000001):
		_fire_prefix_fail("Reopen and replay cold Site from retained suffix", loaded_cold); return
	var loaded_active := reopened.open_site(Vector2i(fixture.from))
	if not loaded_active.ok or int(loaded_active.data.site.fire_settlement.sequence) != 3:
		_fire_prefix_fail("Reopen active Site checkpoint", loaded_active); return
	lab.free()
	caller_checks += 1

func _fire_prefix_fail(label: String, detail: Variant) -> void:
	printerr("FIRE_PREFIX_CASE_FAIL: ", label, " / ", detail)
	quit(2)

func _caller_fault_halt() -> void:
	var fixture: Dictionary = _caller_fixture("publisher_fault", Vector2i.RIGHT, false)
	var lab: TerrainLab = fixture.lab
	var original: RegionSaveSlot = fixture.slot
	var refusing: RefusingClockSlot = RefusingClockSlot.new()
	refusing.pin = original.pin.duplicate(true)
	refusing.control = original.control.duplicate(true)
	lab.site_controller.region_slot = refusing
	var result: Dictionary = lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(not result.ok and bool(result.completed) and str(result.code) == "INJECTED_PUBLISHER_FAILURE")
	assert(lab.site_controller._auto_save_blocked and not lab.site_controller._original_step_fault.is_empty())
	var stopped: PackedByteArray = var_to_bytes([lab.terrain.site, lab.character.capture_state()])
	lab._advance_action_time(10.0)
	var second: Dictionary = lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(not second.ok and second.code == "STEP_FAULT")
	lab.site_controller._save_elapsed = 31.0
	lab.site_controller.finish_tick()
	assert(var_to_bytes([lab.terrain.site, lab.character.capture_state()]) == stopped)
	assert(not lab.site_controller.save_to(lab.site_controller.save_path).ok)
	assert(float(refusing.control.logical_game_seconds) == float(original.control.logical_game_seconds))
	lab.free()
	caller_checks += 1

func _caller_pause_resume() -> void:
	var fixture: Dictionary = _caller_fixture("pause_resume", Vector2i.RIGHT, false)
	var lab: TerrainLab = fixture.lab
	fixture.data.site.paused = true
	var before: PackedByteArray = var_to_bytes([fixture.data.site, lab.character.capture_state()])
	var paused_site: Dictionary = lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(not paused_site.ok and paused_site.code == "PAUSED_SITE" and lab.site_controller._original_step_fault.is_empty())
	assert(var_to_bytes([fixture.data.site, lab.character.capture_state()]) == before)
	fixture.data.site.paused = false
	self.paused = true
	var paused_world: Dictionary = lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(not paused_world.ok and paused_world.code == "PAUSED_WORLD" and lab.site_controller._original_step_fault.is_empty())
	self.paused = false
	lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(float(fixture.slot.control.logical_game_seconds) > 0.0 and lab.site_controller._original_step_fault.is_empty())
	lab.free()
	caller_checks += 1

func _caller_nonfixed_remainder() -> void:
	var fixture: Dictionary = _caller_fixture("nonfixed", Vector2i.RIGHT, false)
	var lab: TerrainLab = fixture.lab
	lab.exchange_enabled = false
	lab.fixed_action_steps_enabled = false
	for actor: TerrainTestCharacter in lab.combat_actors: actor.exchange_enabled = false
	lab._try_move(Vector2i(fixture.direction))
	lab.site_controller.finish_tick()
	assert(str(lab.site_controller._ground_crossing.stage) == "action")
	lab._advance_action_time(TerrainTestCharacter.MOVE_DURATION + 0.5)
	assert(str(lab.site_controller._ground_crossing.stage) == "commit")
	var earned: float = lab._action_time_remainder
	var at: float = float(fixture.slot.control.logical_game_seconds)
	assert(earned > 0.0)
	lab.site_controller.finish_tick()
	assert(lab.terrain != fixture.data and lab._action_time_remainder == earned)
	var diag_action_before: float = float(fixture.slot.control.fire_clock.action_seconds)
	lab._advance_action_time(0.01)
	# DIAG_ONLY (HEADFIX12/15): values behind the nonfixed GAME-time expectation, printed only on failure.
	if absf(float(fixture.slot.control.logical_game_seconds) - at - (earned + 0.01) * 60.0) >= 0.00001:
		print("DIAG_ONLY GROUND_NONFIXED ", JSON.stringify({"fire_settlement": str(lab.terrain.site.get("fire_settlement", "<missing>")), "at": at, "clock": float(fixture.slot.control.logical_game_seconds),
			"delta_game": float(fixture.slot.control.logical_game_seconds) - at, "expected": (earned + 0.01) * 60.0, "earned": earned,
			"delta_action": float(fixture.slot.control.fire_clock.action_seconds) - diag_action_before, "remainder_after": lab._action_time_remainder,
			"step_remaining": lab._action_step_remaining, "speed": lab.simulation_speed, "combat_left": float(lab.terrain.site.get("combat_left", 0.0)),
			"exchange": lab.exchange_enabled, "fixed_steps": lab.fixed_action_steps_enabled, "fault": str(lab.site_controller._original_step_fault),
			"message": lab.site_controller.message.text}))
	assert(absf(float(fixture.slot.control.logical_game_seconds) - at - (earned + 0.01) * 60.0) < 0.00001)
	assert(lab._action_time_remainder == 0.0, "Retained nonfixed remainder was never consumed")
	lab.free()
	caller_checks += 1

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	root.gui_embed_subwindows = true
	if OS.get_cmdline_user_args().has("--fire-prefix-only"):
		_bridge_output("ground_caller_fire_prefix")
		_caller_pruned_clock_commit()
		if caller_checks != 1: quit(2); return
		TerrainArmy.release_contact_source()
		print("SITE_GROUND_CALLER_FIRE_PREFIX_PASS: actual RegionSaveSlot/SiteStore commit and reopen with cold-Site shared-step replay from the retained suffix")
		quit(0)
		return
	_bridge_output("ground_caller")
	for direction: Vector2i in TerrainData.DIRECTIONS:
		_caller_deadline()
		_caller_roundtrip(direction)
	_caller_action_cancel()
	_caller_destination_npc()
	_caller_cold_pending()
	_caller_pruned_clock_commit()
	_caller_fault_halt()
	_caller_pause_resume()
	_caller_nonfixed_remainder()
	TerrainArmy.release_contact_source()
	assert(caller_checks == 11)
	print("SITE_GROUND_CALLER_INTEGRATION_PASS: actual original PackedScene and held-input _try_move; original ACTION/shared-step/postcontact/clock ordering; four-direction original Actor/item/cargo/private-meal transfer, source NPC retained, dual-Site single marker, subsequent immutable-generation save, existing action/UI and prepare/commit PENDING cancellation, actual cold PENDING with original source SHA and fixed-target retries, no elapsed added during wait and earned remainder retained in 30 Hz and nonfixed 120 Hz modes, missing NPC presenter atomic refusal, completed publisher fault halts replay/autosave, pure pre-step pause refusal resumes; no GPU/performance/release claim")
	quit(0)
