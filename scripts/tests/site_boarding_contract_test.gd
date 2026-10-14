extends "res://scripts/tests/site_ship_naval_lifecycle_test.gd"
const LinkContract = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd")
const TravelCensus = preload("res://scripts/region_lab/region_travel.gd")
var b0_failed: bool = false

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline: _must(false, "BOARDING_B0_DEADLINE")
	return false

func _must(condition: bool, message: String) -> bool:
	if condition: return true
	if not b0_failed:
		b0_failed = true
		push_error(message)
		_cleanup.call_deferred(1)
	return false

func _cleanup(code: int) -> void:
	if is_instance_valid(lab): lab.queue_free()
	await process_frame
	quit(code)

func _fixture() -> bool:
	if not _generate(true): return false
	team = lab.army
	enemy = lab.opposing_army
	team.team_id = lab._next_army_identity()
	enemy.team_id = team.team_id + 1
	lab.terrain.site.army_next_team = enemy.team_id + 1
	team.role = "logistics"
	enemy.role = "logistics"
	team.roster_size = 5
	enemy.roster_size = 1
	var selected: Array[Vector2i] = []
	for index in range(5): selected.append(native_dock.cells[index])
	var hostile_cells: Array[Vector2i] = [native_dock.cells[5]]
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, selected) and team.enable_combat(false, 0), "B0_ORIGINAL_FIVE"): return false
	if not _must(enemy.deploy_at(lab.terrain, lab.character, lab.npc, hostile_cells) and enemy.enable_combat(false, 0), "B0_ORIGINAL_ENEMY"): return false
	people.clear()
	for index in range(5):
		people.append(team.combat_identity(index))
		team.combat_units[index].logistics = true
	team.combat_units[2].cargo.grain = 2
	lab.terrain.site.controlled_person_id = people[0]
	lab.terrain.site.army_trial_active = true
	var enabled: Dictionary = lab.site_controller.captivity_supply.enable_team(team)
	if not _must(enabled.ok, "B0_ORIGINAL_SUPPLY"): return false
	enabled.entry.inventory.grain = 12
	enabled.entry.sustain.open_rations = 0.5
	var made: Dictionary = lab.site_controller.vehicles.deploy_ship(team, "ferry", native_dock.anchor, native_dock.facing, true)
	var hostile: Dictionary = lab.site_controller.vehicles.deploy_ship(enemy, "ferry", native_dock.second, native_dock.facing, true)
	if not _must(made.ok and hostile.ok, "B0_REAL_TWO_HULLS"): return false
	boat_id = str(made.vehicle_id)
	enemy_boat = str(hostile.vehicle_id)
	if not _board(0, 0): return false
	if not _must(lab.site_controller.vehicles.boarding_save_guard().ok, "B0_REAL_LEGACY_NO_NAVAL"): return false
	# Keep original deployed rows/holders; naval positives use the original genesis.
	for identity: String in [boat_id, enemy_boat]:
		var vehicle: Dictionary = lab.site_controller.vehicles.records()[identity]
		if not vehicle.has("naval"):
			var original_holder: Dictionary = vehicle.holder
			var original_record: PackedByteArray = var_to_bytes(vehicle)
			var genesis: Dictionary = Ship.make_record(identity, int(vehicle.team_id), str(vehicle.ship_type), int(vehicle.cell),
				Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])))
			var naval: Variant = genesis.get("naval")
			if not _must(naval is Dictionary and naval.get("version") == 1, "B0_ORIGINAL_NAVAL_GENESIS"): return false
			vehicle["naval"] = naval
			var preserved: Dictionary = vehicle.duplicate(true)
			preserved.erase("naval")
			if not _must(is_same(vehicle, lab.site_controller.vehicles.records()[identity]) and is_same(vehicle.holder, original_holder)
				and var_to_bytes(preserved) == original_record, "B0_GENESIS_PRESERVES_ORIGINAL_RECORD_HOLDER_IDS_CARGO"): return false
	return _must(lab.site_controller._capture_for_save().ok, "B0_ORIGINAL_CAPTURE")

func _link_end(vehicle: Dictionary, peer: Dictionary) -> Dictionary:
	var anchor: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
	var other: Vector2i = lab.terrain.cell_from_index(int(peer.cell))
	return {"version": 1, "id": "fixture-link", "epoch": 7,
		"self": {"site_id": str(lab.terrain.site.id), "vehicle_id": str(vehicle.id)},
		"peer": {"site_id": str(lab.terrain.site.id), "vehicle_id": str(peer.id)},
		"frame": {"site_id": str(lab.terrain.site.id), "anchor": [anchor.x, anchor.y], "facing": vehicle.facing.duplicate()},
		"peer_frame": {"site_id": str(lab.terrain.site.id), "anchor": [other.x, other.y], "facing": peer.facing.duplicate()},
		"local": [0.0, 0.0], "world_point": [float(anchor.x), float(anchor.y)], "state": "linked", "crosser_id": 0}

func _linked_state() -> Dictionary:
	var state: Dictionary = lab.terrain.site.duplicate(true)
	var a: Dictionary = state.vehicles[boat_id]
	var b: Dictionary = state.vehicles[enemy_boat]
	var a_naval: Variant = a.get("naval")
	var b_naval: Variant = b.get("naval")
	if not _must(a_naval is Dictionary and b_naval is Dictionary, "B0_LINK_FIXTURE_REQUIRES_ORIGINAL_GENESIS"): return {}
	a_naval.version = 2
	a_naval.boarding_link = _link_end(a, b)
	b_naval.version = 2
	b_naval.boarding_link = _link_end(b, a)
	return state

func _position(state: Dictionary) -> Dictionary:
	var link: Dictionary = state.vehicles[boat_id].naval.boarding_link
	return {"version": 1, "kind": "channel", "link_id": link.id, "epoch": link.epoch,
		"frame": link.frame.duplicate(true), "world_point": [link.world_point[0] + 0.7, link.world_point[1] + 0.8]}

func _nq(state: Dictionary) -> Dictionary:
	# Census uses the actual original row/item IDs. Q reads their original stocks.
	var census: Dictionary = TravelCensus.census({"content": state})
	var grain: int = int(state.get("inventory", {}).get("grain", 0)) + int(state.get("manual", {}).get("cargo", {}).get("grain", 0)) + int(state.get("worker", {}).get("cargo", {}).get("grain", 0))
	for supply: Dictionary in state.get("team_supply", {}).values(): grain += int(supply.get("inventory", {}).get("grain", 0))
	for army: Dictionary in state.get("armies", []):
		for row: Dictionary in army.units: grain += int(row.get("cargo", {}).get("grain", 0))
	for vehicle: Dictionary in state.get("vehicles", {}).values(): grain += int(vehicle.get("cargo", {}).get("grain", 0))
	for holder: Dictionary in state.get("ground_loot", {}).values(): grain += int(holder.get("cargo", {}).get("grain", 0))
	return {"N": census.people, "Q_items": census.items, "Q_grain": grain}

func _reject_unchanged(state: Dictionary, code: String) -> bool:
	var before: PackedByteArray = var_to_bytes(state)
	var nq: Dictionary = _nq(state)
	var result: Dictionary = LinkContract.save_guard(state, lab.terrain)
	return _must(not result.ok and result.code == code and before == var_to_bytes(state) and nq == _nq(state), "B0_REFUSAL_PURITY: " + str(result))

func _cases() -> bool:
	var original: Dictionary = lab.terrain.site.duplicate(true)
	if not _must(team.combat_units.size() == 5 and enemy.combat_units.size() == 1 and int(team.combat_units[2].cargo.grain) == 2, "B0_TRUE_N_Q_PREMISE"): return false
	if not _must(LinkContract.save_guard(original, lab.terrain).ok, "B0_NAVAL_V1"): return false
	var json_v1: Dictionary = JSON.parse_string(JSON.stringify(original, "", true, true))
	if not _must(LinkContract.save_guard(json_v1, lab.terrain).ok, "B0_NAVAL_V1_JSON_NUMBERS"): return false
	var legacy: Dictionary = original.duplicate(true)
	for vehicle: Dictionary in legacy.vehicles.values(): vehicle.erase("naval")
	if not _must(LinkContract.save_guard(legacy, lab.terrain).ok, "B0_NO_NAVAL"): return false
	var legacy_query: Dictionary = LinkContract.query(legacy, boat_id, lab.terrain)
	if not _must(legacy_query.ok and not legacy_query.linked, "B0_NO_NAVAL_QUERY_IS_UNLINKED"): return false
	var invalid_v1: Dictionary = original.duplicate(true)
	invalid_v1.vehicles[boat_id].get("naval").hp = 0.0 # Afloat v1 must still have positive hull HP.
	if not _reject_unchanged(invalid_v1, "CORRUPT_SAVE"): return false
	legacy = original.duplicate(true)
	legacy.vehicles[boat_id].naval.boarding_link = {}
	legacy.vehicles[enemy_boat].naval.boarding_link = null
	if not _must(LinkContract.save_guard(legacy, lab.terrain).ok, "B0_LEGACY_EMPTY"): return false
	var linked: Dictionary = _linked_state()
	var before: PackedByteArray = var_to_bytes(linked)
	var result: Dictionary = LinkContract.query(linked, boat_id, lab.terrain)
	if not _must(result.ok and result.linked and result.entrants_open and not result.can_execute and before == var_to_bytes(linked), "B0_BOTH_ENDS_PURE"): return false
	result.link.epoch = 999
	if not _must(linked.vehicles[boat_id].naval.boarding_link.epoch == 7, "B0_QUERY_RETURN_ALIAS"): return false
	linked.vehicles[boat_id].revision += 1
	if not _must(LinkContract.query(linked, boat_id, lab.terrain).ok, "B0_EPOCH_NOT_DECK_REVISION"): return false
	if not _reject_unchanged(linked, "BUSY"): return false
	for kind: String in ["version", "half", "peer", "epoch", "frame", "endpoint", "site_type", "move_type", "command_type", "facing_type", "naval_type", "naval_version", "hull_id_type", "naval_state_type", "naval_version_type"]:
		var bad: Dictionary = _linked_state()
		match kind:
			"version": bad.vehicles[boat_id].naval.boarding_link.version = 99
			"half": bad.vehicles[enemy_boat].naval.erase("boarding_link")
			"peer": bad.vehicles[boat_id].naval.boarding_link.peer.vehicle_id = boat_id
			"epoch": bad.vehicles[enemy_boat].naval.boarding_link.epoch += 1
			"frame": bad.vehicles[boat_id].naval.boarding_link.peer_frame.anchor[0] += 1
			"endpoint": bad.vehicles[boat_id].naval.boarding_link.world_point[0] += 0.01
			"site_type": bad.id = 42
			"move_type": bad.vehicles[boat_id].move = "bad"
			"command_type": bad.vehicles[boat_id].command = 7
			"facing_type": bad.vehicles[boat_id].facing = "bad"
			"naval_type": bad.vehicles[boat_id].naval = "bad"
			"naval_version": bad.vehicles[boat_id].naval.version = 99
			"hull_id_type": bad.vehicles[boat_id].id = 42
			"naval_state_type": bad.vehicles[boat_id].naval.state = 42
			"naval_version_type": bad.vehicles[boat_id].naval.version = "1"
		if not _reject_unchanged(bad, "CORRUPT_SAVE"): return false
	for state_name: String in ["establishing", "closing", "invalid"]:
		var closing: Dictionary = _linked_state()
		for vehicle: Dictionary in closing.vehicles.values(): vehicle.naval.boarding_link.state = state_name
		var closed: Dictionary = LinkContract.query(closing, boat_id, lab.terrain)
		if not _must(closed.ok and not closed.entrants_open, "B0_CLOSING_NO_NEW_ENTRY"): return false
		if not _reject_unchanged(closing, "BUSY"): return false
	var occupied: Dictionary = _linked_state()
	for vehicle: Dictionary in occupied.vehicles.values(): vehicle.naval.boarding_link.crosser_id = people[0]
	var occupied_query: Dictionary = LinkContract.query(occupied, boat_id, lab.terrain)
	if not _must(occupied_query.ok and not occupied_query.entrants_open and not occupied_query.can_execute, "B0_SINGLE_REAL_CROSSER"): return false
	for vehicle: Dictionary in occupied.vehicles.values(): vehicle.naval.boarding_link.crosser_id = 2147483647
	if not _reject_unchanged(occupied, "CORRUPT_SAVE"): return false
	var channel: Dictionary = original.duplicate(true)
	channel.armies[0].units[0].boarding_position = _position(_linked_state())
	if not _reject_unchanged(channel, "BUSY"): return false
	channel.armies[0].units[0].boarding_position.kind = 42
	if not _reject_unchanged(channel, "CORRUPT_SAVE"): return false
	channel.armies[0].units[0].boarding_position.kind = "channel"
	channel.armies[0].units[0].boarding_position.version = 99
	if not _reject_unchanged(channel, "CORRUPT_SAVE"): return false
	# Real existing ground_loot holder from original Runtime transaction.
	var row: Dictionary = team.combat_units[2]
	var left: Dictionary = Runtime.leave_ground_loot(lab.terrain, row.item_state, row.cargo, people[2], team.cells[2], "cargo", {"grain": 1}, [], int(row.item_state.version))
	if not _must(left.ok and not lab.terrain.site.ground_loot.is_empty(), "B0_ORIGINAL_GROUND_LOOT"): return false
	if not _must(lab.site_controller._capture_for_save().ok, "B0_LOOT_ORIGINAL_RECAPTURE"): return false
	var loot_state: Dictionary = lab.terrain.site.duplicate(true)
	var holder: Dictionary = loot_state.ground_loot.values()[0]
	holder.boarding_position = _position(_linked_state())
	if not _must(_nq(loot_state).Q_grain == _nq(original).Q_grain, "B0_ORIGINAL_LOOT_Q_CONSERVED"): return false
	if not _reject_unchanged(loot_state, "BUSY"): return false
	return true

func _run() -> void:
	if not _must(DisplayServer.get_name() == "headless", "B0_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases(): return
	print("SITE_BOARDING_B0_PASS: " + get_script().resource_path)
	await _cleanup(0)
