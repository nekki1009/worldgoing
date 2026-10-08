extends "res://scripts/tests/site_siege_runtime_contract_test.gd"
## Real JSON save/load and the original Controller candidate/commit boundary.
const OUT := "res://.godot-temp/site_siege_store_roundtrip"
var roundtrip_lab: TerrainLab
var roundtrip_deadline := 0
var roundtrip_completed := 0
var json_roundtrips := 0
var candidate_rejections := 0
var roundtrip_failed := false

func _initialize() -> void:
	roundtrip_deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()

func _roundtrip_require(condition: bool, message: String) -> bool:
	if condition: return true
	roundtrip_failed = true
	push_error(message)
	quit(1)
	return false

func _check_deadline() -> bool:
	return _roundtrip_require(Time.get_ticks_msec() < roundtrip_deadline, "Siege roundtrip deadline")

func _first_difference(left: Variant, right: Variant, path: String) -> String:
	if left == right: return ""
	if left is Dictionary and right is Dictionary:
		for key: Variant in left:
			if not right.has(key): return path + "." + str(key) + " missing after load"
			var difference: String = _first_difference(left[key], right[key], path + "." + str(key))
			if not difference.is_empty(): return difference
		for key: Variant in right:
			if not left.has(key): return path + "." + str(key) + " added after load"
	elif left is Array and right is Array:
		if left.size() != right.size(): return "%s size: %d vs %d" % [path, left.size(), right.size()]
		for index in range(left.size()):
			var difference: String = _first_difference(left[index], right[index], "%s[%d]" % [path, index])
			if not difference.is_empty(): return difference
	return "%s: %s vs %s" % [path, JSON.stringify(left), JSON.stringify(right)]

func _persistent_fixture() -> TerrainData:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(72, 72)})
	SiteEnvironment.initialize(data, "siege-store-roundtrip")
	for y in range(5, 70):
		for x in range(5, 70):
			var index := data.index(Vector2i(x, y))
			data.site.terrain_changes[str(index)] = 0
			data.height_levels[index] = 0
	for source: String in data.resource_base:
		SiteEnvironment.change(data, source, {"cleared": true, "remaining": 0})
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	data.site.capacity = 100000
	data.site.depot_cell = data.index(Vector2i(3, 3))
	data.site.player_cell = data.index(Vector2i(8, 8))
	data.site.manual.cell = data.site.player_cell
	data.site.worker.cell = data.index(Vector2i(3, 4))
	data.site.worker_enabled = false
	if not _roundtrip_require(SiteRuntime.initialize_item_storage(data.site).ok, "Fixture item storage initialization failed"): return null
	SiteRuntime.rebuild_terrain_edges(data)
	SiteEnvironment.rebuild_indexes(data)
	return data

func _save_and_restore(path: String, key: String) -> Dictionary:
	if not _check_deadline(): return {}
	var ui: SiteController = roundtrip_lab.site_controller
	ui.save_path = path
	var saved: Dictionary = ui.save_to(path)
	if not _roundtrip_require(saved.ok, "Actual Controller save failed: " + str(saved)): return {}
	var original: Dictionary = roundtrip_lab.terrain.site.vehicles[key].duplicate(true)
	var roster: Array = roundtrip_lab.terrain.site.armies[0].units.duplicate(true)
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not _roundtrip_require(envelope.payload is String and str(envelope.checksum) == str(envelope.payload).sha256_text(), "Stored JSON envelope checksum mismatch"): return {}
	var loaded: Dictionary = ui.load_from(path)
	if not _roundtrip_require(loaded.ok and roundtrip_lab.terrain == loaded.get("data"), "Actual candidate was not committed: " + str(loaded)): return {}
	if not _roundtrip_require(roundtrip_lab.terrain.site.vehicles[key] == original, "Vehicle JSON roundtrip changed stored values"): return {}
	# Both sides pass through the same JSON numeric boundary; every field remains compared.
	var original_rows: Variant = JSON.parse_string(JSON.stringify(roster, "", true, true))
	var loaded_rows: Variant = JSON.parse_string(JSON.stringify(roundtrip_lab.terrain.site.armies[0].units, "", true, true))
	var difference: String = _first_difference(original_rows, loaded_rows, "roster")
	if not _roundtrip_require(difference.is_empty(), "Roundtrip changed original people or holders: " + difference): return {}
	json_roundtrips += 1
	return original

func _reject_candidate(path: String, base: String, mutate: Callable) -> bool:
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base))
	var payload: Dictionary = JSON.parse_string(str(envelope.payload))
	mutate.call(payload.state)
	var body := JSON.stringify(payload, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _roundtrip_require(file != null, "Could not write corrupt candidate fixture"): return false
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()
	var old_data: TerrainData = roundtrip_lab.terrain
	var old_army: TerrainArmy = roundtrip_lab.army
	var old_state := JSON.stringify(old_data.site, "", true, true)
	var old_file := FileAccess.get_file_as_string(base)
	var rejected: Dictionary = roundtrip_lab.site_controller.load_from(path)
	if not _roundtrip_require(not rejected.ok and str(rejected.code) == "CORRUPT_SAVE", "Corrupt semantic candidate unexpectedly passed: " + str(rejected)): return false
	if not _roundtrip_require(roundtrip_lab.terrain == old_data and roundtrip_lab.army == old_army, "Rejected candidate replaced the original scene owners"): return false
	if not _roundtrip_require(JSON.stringify(old_data.site, "", true, true) == old_state and FileAccess.get_file_as_string(base) == old_file,
		"Rejected candidate changed the original scene or valid JSON save"): return false
	if not _check_deadline(): return false
	candidate_rejections += 1
	return true

func _check_legacy_quota(data: TerrainData, key: String) -> bool:
	# Focused quota validation; full legacy JSON regressions have their own tests.
	var state := data.site.duplicate(true)
	var vehicle: Dictionary = state.vehicles[key]
	vehicle.crew_slots = {}
	vehicle.operator_id = 0
	vehicle.phase = "idle"
	vehicle.hp = 140.0
	vehicle.command = {}
	var rows: Array[Dictionary] = []
	for index in range(100):
		var row: Dictionary = state.armies[0].units[0].duplicate(true)
		row.person_id = 10000 + index
		row.cell = [8 + index % 10, 40 + floori(float(index) / 10.0)]
		row.destination = [-1, -1]
		rows.append(row)
	state.armies[0].units = rows
	if not _roundtrip_require(SiteStore._validate_vehicles(data, state, true).ok, "100 original people plus a ballista must retain independent quotas"): return false
	for kind: String in ["cart", "wagon"]:
		var old_id := str(int(state.next_vehicle))
		state.next_vehicle = int(state.next_vehicle) + 1
		state.vehicles[old_id] = {"id": old_id, "kind": kind, "team_id": 1, "cell": data.index(Vector2i(45, 45)),
			"facing": [1, 0], "operator_id": 0, "holder": SiteRuntime.new_item_state("vehicle:" + old_id),
			"cargo": {}, "move": {}, "stop_pending": false}
		if not _roundtrip_require(not SiteStore._validate_vehicles(data, state, true).ok, "Legacy " + kind + " must still count toward the 100-slot quota"): return false
		state.armies[0].units = rows.slice(0, 99)
		if not _roundtrip_require(SiteStore._validate_vehicles(data, state, true).ok, "99 people plus one legacy vehicle must remain legal"): return false
		state.vehicles.erase(old_id)
		state.armies[0].units = rows
	roundtrip_completed += 1
	return true

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(1))
	if not _roundtrip_require(DisplayServer.get_name() == "headless", "Roundtrip requires headless mode"): return
	if not _roundtrip_require(DirAccess.make_dir_recursive_absolute(OUT) == OK, "Cannot create isolated roundtrip output"): return
	roundtrip_lab = TerrainLab.new()
	roundtrip_lab.npc = TerrainTestNPC.new()
	roundtrip_lab.pause_when_unfocused = false
	root.add_child(roundtrip_lab)
	roundtrip_lab.set_process(false)
	roundtrip_lab.set_process_unhandled_input(false)
	roundtrip_lab.site_controller.set_process(false)
	roundtrip_lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in roundtrip_lab.combat_actors: actor.set_process(false)
	var data := _persistent_fixture()
	if roundtrip_failed or data == null: return
	roundtrip_lab.bind_terrain(data)
	if not _roundtrip_require(roundtrip_lab.terrain == data, "Persistent fixture did not bind"): return
	var ui: SiteController = roundtrip_lab.site_controller
	ui.save_root = OUT
	ui._auto_save_blocked = true
	ui.release_worker()
	var key := _new_ballista(data)
	if not _roundtrip_require(not key.is_empty(), "Fixture ballista construction did not complete"): return
	_finish_siege(data, key)
	var team: TerrainArmy = roundtrip_lab.army
	team.team_id = 1
	team.roster_size = 3
	var positions: Array[Vector2i] = [Vector2i(16, 20), Vector2i(19, 20), Vector2i(19, 21)]
	if not _roundtrip_require(team.deploy_at(data, roundtrip_lab.character, roundtrip_lab.npc, positions) and team.enable_combat(false, 0), "Original Army fixture deployment failed"): return
	team.set_process(false)
	data.site.army_next_team = 2
	if not _roundtrip_require(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(35, 25), -1, Vector2i.RIGHT, "square").ok, "Original Army MOVE fixture order failed"): return
	var ids: Array[int] = [team.combat_identity(1), team.combat_identity(2)]
	for slot in range(2):
		if not _roundtrip_require(ui.vehicles.assign_crew(key, ids[slot], str(slot), team.combat_identity(0), true).ok, "Original crew assignment failed"): return
	ui.vehicles.update_siege(0.01)
	data.site.combat_left = 0.0
	if not _roundtrip_require(ui.vehicles.crew_ready(data.site.vehicles[key]), "Fixture crew did not reach ready"): return
	var ready: Dictionary = _save_and_restore(OUT + "/ready.json", key)
	if roundtrip_failed: return
	if not _roundtrip_require(ready.phase == "ready" and ready.crew_slots == {"0": ids[0], "1": ids[1]}, "Ready roundtrip lost original crew slots"): return
	var snapshot: Dictionary = roundtrip_lab.terrain.site.armies[0]
	for person_id: int in ids:
		if not _roundtrip_require(not snapshot.combat_deployment_plan.member_slot_map.has(str(person_id)), "Crew still owns a general formation slot"): return
		if not _roundtrip_require(not snapshot.combat_deployment_plan.slot_lease_owner_map.values().has(person_id), "Crew still owns a general formation lease"): return
	if not _roundtrip_require(snapshot.units.size() == 3, "Roundtrip changed the original roster count"): return
	roundtrip_completed += 1
	if not _reject_candidate(OUT + "/bad_crew.json", OUT + "/ready.json", func(state: Dictionary) -> void: state.vehicles[key].crew_slots["1"] = 2147483647): return
	if not _reject_candidate(OUT + "/missing_flag.json", OUT + "/ready.json", func(state: Dictionary) -> void: state.vehicles[key].erase("ever_hp_damaged")): return
	roundtrip_completed += 1
	data = roundtrip_lab.terrain
	var vehicle: Dictionary = data.site.vehicles[key]
	if not _roundtrip_require(ui.vehicles.unassign_crew(key, 0, roundtrip_lab.army.combat_identity(0), true).ok and vehicle.crew_slots.is_empty(), "Crew release did not finish"): return
	if not _roundtrip_require(SiteRuntime.damage_siege_vehicle(data, key, 70.0).ok and SiteRuntime.request_siege_repair(data, key, 1).ok, "Original damage/repair fixture failed"): return
	var slot: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	if not _roundtrip_require(SiteRuntime.advance_siege_work(data, key, "repair", float(vehicle.repair.total_work), data.cell_from_index(int(slot.cell)), int(slot.slot), 1).ok, "Original repair work failed"): return
	if not _roundtrip_require(float(vehicle.hp) == 140.0 and bool(vehicle.ever_hp_damaged), "Repair reset original damage history"): return
	var repaired: Dictionary = _save_and_restore(OUT + "/repaired.json", key)
	if roundtrip_failed: return
	if not _roundtrip_require(float(repaired.hp) == 140.0 and bool(repaired.ever_hp_damaged), "Repaired roundtrip reset damage history"): return
	if not _reject_candidate(OUT + "/bad_flag.json", OUT + "/repaired.json", func(state: Dictionary) -> void: state.vehicles[key].ever_hp_damaged = "true"): return
	roundtrip_completed += 1
	data = roundtrip_lab.terrain
	vehicle = data.site.vehicles[key]
	vehicle.cargo = {"siege_bolt": 3}
	vehicle.holder.version = int(vehicle.holder.version) + 1
	if not _roundtrip_require(SiteRuntime.damage_siege_vehicle(data, key, 999.0).ok, "Wreck fixture damage failed"): return
	var wreck: Dictionary = _save_and_restore(OUT + "/wreck.json", key)
	if roundtrip_failed: return
	if not _roundtrip_require(wreck.phase == "wrecked" and float(wreck.hp) == 0.0 and bool(wreck.ever_hp_damaged) and wreck.cargo == {"siege_bolt": 3}, "Wreck roundtrip lost original HP/history/cargo"): return
	if not _reject_candidate(OUT + "/contradictory_flag.json", OUT + "/wreck.json", func(state: Dictionary) -> void: state.vehicles[key].ever_hp_damaged = false): return
	roundtrip_completed += 1
	if not _check_legacy_quota(roundtrip_lab.terrain, key): return
	if not _roundtrip_require(not roundtrip_failed and roundtrip_completed == 5 and json_roundtrips == 3 and candidate_rejections == 4,
		"A roundtrip or atomic-rejection case stopped before completion"): return
	roundtrip_lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_STORE_ROUNDTRIP_PASS: 3 actual Controller JSON roundtrips, crew roster/lease preservation, repaired damage history, cargo wreck, 4 semantic candidate atomic rejections, and unchanged legacy cart/wagon quota")
	quit(0)
