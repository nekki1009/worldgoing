extends "res://scripts/tests/site_cross_boundary_wall_test.gd"
## Candidate transaction + original PersonActions tests. Formal input/bind is a
## separate root integration check; this does not claim that caller exists.

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

func _run() -> void:
	deadline = Time.get_ticks_msec() + 150000
	_bridge_output("ground")
	for direction: Vector2i in TerrainData.DIRECTIONS:
		assert(_ground_roundtrip(direction))
	assert(_ground_refusals())
	assert(_ground_action_clock())
	assert(_ground_presence())
	TerrainArmy.release_contact_source()
	print("SITE_GROUND_CROSSING_CONTRACT_PASS: original Actor/item/cargo/meal identity, four boundary directions, source NPC retained, source/destination single generation, bind failure atomicity, recovery/replay rejection, relation/collision rejection, explicit presence subset and original ACTION pause/cancel/interruption; formal input/binder/GPU/performance remain separate")
	quit(0)

func _ground_fixture(name: String, direction: Vector2i = Vector2i.RIGHT) -> Dictionary:
	var number := TerrainData.DIRECTIONS.find(direction)
	var from_site := Vector2i(2, -3)
	var cell: Vector2i = [Vector2i(50, 0), Vector2i(99, 50), Vector2i(50, 99), Vector2i(0, 50)][number]
	var boundary := RegionSaveSlot.boundary_pair(from_site, cell, direction)
	var left := _flat_site(from_site)
	var right := _flat_site(boundary.site)
	var source := PinnedGeography.new()
	source.manifest_hash = "b".repeat(64)
	source.manifest = {"atlas_id": RegionGrid.ATLAS_ID, "grid_contract_version": 1, "base_revision": "bridge_contract_v1"}
	source.bases[from_site] = _bridge_base(left)
	source.bases[boundary.site] = _bridge_base(right)
	var slot := RegionSaveSlot.new()
	slot.source = source
	slot.folder = bridge_output.path_join(name)
	slot.pin = {"format": 1, "world_instance_id": "ground_world", "slot_id": name, "atlas_id": RegionGrid.ATLAS_ID,
		"grid_contract_version": 1, "base_revision": "bridge_contract_v1", "manifest_sha256": source.manifest_hash,
		"ramp_rule_revision": RegionTerrainAdapter.RAMP_RULE_REVISION}
	assert(slot._recover_control().ok)
	var lab := _building_lab(left)
	assert(lab.character.place(cell, true))
	left.site.controlled_person_id = int(lab.character.person_id)
	lab.character.hp = 73.0
	lab.character.fatigue = 37.0
	left.site.manual.cargo = {"grain": 4, "wood": 2}
	lab.character.ammo_inventory = left.site.manual.cargo
	var identity := int(lab.character.person_id)
	var pool := Store.Sustain.create(RegionSaveSlot._site_seconds(left))
	assert(Store.Sustain.add_members(pool, {identity: {"hp": lab.character.hp}}, [identity]).ok)
	if not left.site.has("person_supply"): left.site.person_supply = {}
	left.site.person_supply[str(identity)] = pool
	assert(lab.site_controller._capture_for_save().ok)
	assert(slot.attach_active_site(left).ok)
	return {"lab": lab, "slot": slot, "data": left, "id": identity, "from": from_site, "to": boundary.site, "cell": cell, "arrival": boundary.cell, "direction": direction}

func _ground_clock_step(fixture: Dictionary) -> void:
	# The transaction test drives the original Runtime + personal supply owners.
	# Full shared-step ordering/input/bind are deliberately tested by the caller.
	var seconds := TerrainTestCharacter.MOVE_DURATION
	var game_seconds := Runtime.game_seconds(seconds, float(fixture.data.site.combat_left))
	Runtime.advance(fixture.data, seconds)
	fixture.lab.site_controller.advance_person_supply(game_seconds)
	assert(fixture.lab.site_controller._capture_for_save().ok)
	assert(fixture.slot.record_active_step(fixture.data.site, game_seconds).ok)

func _ground_bind_ready(_data: TerrainData) -> Dictionary:
	return {"ok": true}

func _ground_bind_refused(_data: TerrainData) -> Dictionary:
	return Runtime.fail("BIND_GUARD", "Injected original presenter guard refusal")

func _ground_roundtrip(direction: Vector2i) -> bool:
	var fixture := _ground_fixture("round_" + str(TerrainData.DIRECTIONS.find(direction)), direction)
	var slot: RegionSaveSlot = fixture.slot
	var original := JSON.stringify(fixture.data.site)
	var prepared := slot.prepare_ground_crossing(fixture.data, fixture.id, direction)
	assert(prepared.ok, str(prepared))
	assert(JSON.stringify(fixture.data.site) == original)
	assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(slot.folder)), "Prepare published mutable state")
	assert(not slot.commit_ground_crossing(prepared.request, fixture.data, 0.0, _ground_bind_ready).ok)
	_ground_clock_step(fixture)
	var latest: Dictionary = fixture.data.site.duplicate(true)
	var latest_holder: Dictionary = latest.actors.player.item_state.duplicate(true)
	var source_record_count: int = latest.item_records.size()
	var ready_time := float(slot.control.logical_game_seconds)
	var refused := slot.commit_ground_crossing(prepared.request, fixture.data, TerrainTestCharacter.MOVE_DURATION, _ground_bind_refused)
	assert(not refused.ok and str(refused.code) == "BIND_GUARD")
	assert(slot._marker.is_empty() and float(slot.control.logical_game_seconds) == ready_time)
	assert(fixture.data.site == latest and not FileAccess.file_exists(slot.site_path(fixture.to)))
	var committed := slot.commit_ground_crossing(prepared.request, fixture.data, TerrainTestCharacter.MOVE_DURATION, _ground_bind_ready)
	assert(committed.ok, str(committed))
	assert(fixture.data.site == latest, "Transaction mutated still-live old scene before bind")
	var from: Dictionary = committed.source_data.site
	var to: Dictionary = committed.destination_data.site
	var npc_delta: Dictionary = {}
	for field: String in latest.actors.npc:
		var original_value: Variant = latest.actors.npc[field]
		var returned_value: Variant = from.actors.get("npc", {}).get(field)
		if typeof(original_value) != typeof(returned_value) or original_value != returned_value:
			npc_delta[field] = {"original_type": typeof(original_value), "returned_type": typeof(returned_value),
				"original": original_value, "returned": returned_value}
	if from.actors.has("player") or _ground_json(from.actors.npc) != _ground_json(latest.actors.npc): quit(1)
	assert(not from.actors.has("player") and _ground_json(from.actors.npc) == _ground_json(latest.actors.npc),
		str({"direction": direction, "source_actor_keys": from.actors.keys(), "destination_actor_keys": to.actors.keys(),
			"original_npc_keys": latest.actors.npc.keys(), "returned_npc_keys": from.actors.get("npc", {}).keys(),
			"npc_field_delta": npc_delta}))
	assert(to.actors.keys() == ["player"] and int(to.actors.player.person_id) == int(fixture.id))
	assert(_ground_json(to.actors.player.item_state) == _ground_json(latest_holder) and float(to.actors.player.hp) == 73.0 and float(to.actors.player.fatigue) == 37.0)
	assert(_ground_json(to.actors.player.cell) == _ground_json([fixture.arrival.x, fixture.arrival.y]) and float(to.actors.player.movement_left) == 0.0)
	var expected_player: Dictionary = _ground_expected_arrival(latest.actors.player, Vector2i(fixture.arrival))
	assert(_ground_json(to.actors.player) == _ground_json(expected_player), "Complete original player snapshot changed during transfer")
	assert(_ground_json(to.manual.cargo) == _ground_json(latest.manual.cargo) and from.manual.cargo.is_empty())
	assert(_ground_json(to.person_supply[str(fixture.id)]) == _ground_json(latest.person_supply[str(fixture.id)]) and not from.person_supply.has(str(fixture.id)))
	assert(_ground_json(from.inventory) == _ground_json(latest.inventory) and to.inventory.is_empty())
	assert(from.item_records.size() + to.item_records.size() == source_record_count)
	for identity: String in to.item_records:
		assert(_ground_json(to.item_records[identity]) == _ground_json(latest.item_records[identity]) and not from.item_records.has(identity))
	assert(float(slot.control.logical_game_seconds) == ready_time and str(slot.control.active_site_id) == str(to.id))
	assert(int(committed.generation) == 1 and int(slot._marker.generation) == 1 and slot._marker.sites.size() == 2)
	assert(Store._validate_actors(committed.source_data, from).ok and Store._validate_actors(committed.destination_data, to).ok)
	var repeated := slot.commit_ground_crossing(prepared.request, fixture.data, TerrainTestCharacter.MOVE_DURATION, _ground_bind_ready)
	assert(not repeated.ok and str(repeated.code) == "ALREADY_COMMITTED")
	var recovered := RegionSaveSlot.new()
	recovered.source = slot.source
	recovered.pin = slot.pin.duplicate(true)
	recovered.folder = slot.folder
	assert(recovered._recover_control().ok and recovered._was_committed(str(prepared.request.token)))
	assert(_ground_json(recovered.control) == _ground_json(slot.control))
	var loaded_source := recovered._load_checked(recovered.site_path(fixture.from), fixture.from)
	var loaded_destination := recovered._load_checked(recovered.site_path(fixture.to), fixture.to)
	assert(loaded_source.ok and loaded_destination.ok)
	assert(not loaded_source.data.site.actors.has("player") and int(loaded_destination.data.site.actors.player.person_id) == int(fixture.id))
	assert(_ground_json(loaded_source.data.site.actors.npc) == _ground_json(latest.actors.npc))
	fixture.lab.free()
	return true

func _ground_refusals() -> bool:
	var fixture := _ground_fixture("refusals")
	var slot: RegionSaveSlot = fixture.slot
	var before := JSON.stringify(fixture.data.site)
	var prepared := slot.prepare_ground_crossing(fixture.data, fixture.id, fixture.direction)
	assert(prepared.ok, str(prepared))
	fixture.data.site.housing = {str(fixture.id): {"version": 1, "house_id": "1", "cell": fixture.data.index(fixture.cell)}}
	var housing := slot.prepare_ground_crossing(fixture.data, fixture.id, fixture.direction)
	assert(not housing.ok and str(housing.code) == "RELATION_OPEN")
	fixture.data.site.erase("housing")
	var fresh := slot.source.make_terrain_data(fixture.to.x, fixture.to.y)
	var destination := slot._ground_destination(fresh.data, slot.control.logical_game_seconds)
	assert(destination.ok)
	var target: TerrainData = destination.data
	target.site.actors = {"player": fixture.data.site.actors.player.duplicate(true)}
	var occupied := slot._ground_transfer_pair(fixture.data, target, prepared.request, slot.site_path(fixture.to))
	assert(not occupied.ok and str(occupied.code) == "ACTOR_SLOT_OCCUPIED")
	target.site.actors = {}
	var item_id := str(fixture.data.site.actors.player.item_state.item_ids[0])
	target.site.item_records[item_id] = {"holder": "depot", "original_owner": 999, "definition": "test"}
	var collision := slot._ground_transfer_pair(fixture.data, target, prepared.request, slot.site_path(fixture.to))
	assert(not collision.ok and str(collision.code) == "ID_CONFLICT")
	target.site.item_records = {"999": {"holder": "depot", "original_owner": fixture.id, "definition": "test"}}
	var history := slot._ground_transfer_pair(fixture.data, target, prepared.request, slot.site_path(fixture.to))
	assert(not history.ok and str(history.code) == "ID_CONFLICT")
	assert(JSON.stringify(fixture.data.site) == before and slot._marker.is_empty())
	fixture.lab.free()
	return true

func _ground_action_clock() -> bool:
	var fixture := _ground_fixture("action")
	var actions: SitePersonActions = fixture.lab.site_controller.person_actions
	var prepared: Dictionary = fixture.slot.prepare_ground_crossing(fixture.data, fixture.id, fixture.direction)
	assert(prepared.ok and actions.begin_ground_boundary(fixture.id, prepared).ok)
	assert(not actions.save_guard().ok)
	actions.advance(100.0)
	assert(float(actions.job_for(fixture.id).elapsed) == 0.0, "WORK clock advanced boundary ACTION")
	fixture.data.site.paused = true
	actions.advance_ship_jobs(10.0)
	assert(float(actions.job_for(fixture.id).elapsed) == 0.0)
	fixture.data.site.paused = false
	actions.advance_ship_jobs(TerrainTestCharacter.MOVE_DURATION * 0.5)
	assert(actions.settle_after_contacts().is_empty())
	assert(actions.cancel(fixture.id).ok and actions.save_guard().ok and fixture.slot._marker.is_empty())
	assert(actions.begin_ground_boundary(fixture.id, prepared).ok)
	fixture.lab.character._received_effective_hit += 1
	actions.advance_ship_jobs(TerrainTestCharacter.MOVE_DURATION)
	var interrupted := actions.settle_after_contacts()
	assert(interrupted.size() == 1 and not interrupted[0].ok and not actions.is_busy(fixture.id))
	assert(fixture.lab.site_controller._capture_for_save().ok)
	prepared = fixture.slot.prepare_ground_crossing(fixture.data, fixture.id, fixture.direction)
	assert(prepared.ok and actions.begin_ground_boundary(fixture.id, prepared).ok)
	actions.advance_ship_jobs(TerrainTestCharacter.MOVE_DURATION)
	var completed := actions.settle_after_contacts()
	assert(completed.size() == 1 and completed[0].ok and completed[0].ground_boundary_ready)
	assert(actions.save_guard().ok and fixture.slot._marker.is_empty() and fixture.data.site.actors.has("player"))
	assert(float(fixture.slot.control.logical_game_seconds) == 0.0, "PersonActions invented a second clock")
	fixture.lab.free()
	return true

func _ground_presence() -> bool:
	var fixture := _ground_fixture("presence")
	var state: Dictionary = fixture.data.site.duplicate(true)
	state.actor_presence_version = 1
	state.actors.erase("player")
	assert(Store._validate_actors(fixture.data, state).ok, "Explicit NPC-only container rejected")
	state.erase("actor_presence_version")
	assert(not Store._validate_actors(fixture.data, state).ok, "Legacy player requirement weakened")
	state.actor_presence_version = 1
	state.actors = {}
	assert(Store._validate_actors(fixture.data, state).ok)
	state.actor_presence_version = true
	assert(not Store._validate_actors(fixture.data, state).ok)
	state.actor_presence_version = 1
	state.actors = {"visitor": fixture.data.site.actors.player}
	assert(not Store._validate_actors(fixture.data, state).ok)
	fixture.lab.free()
	return true

