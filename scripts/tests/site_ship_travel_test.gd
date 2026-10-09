extends "res://scripts/tests/region_lab_contract_test.gd"
## Original Slot transaction plus real people/jobs/shared Site steps. Synthetic
## fixed geography is explicitly packaged by the original Region fixture.
## Formal Controller journey UI/phase callers have a separate integration test.

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const FROM := Vector2i(99, 101)
const TO := Vector2i(100, 101)
var deadline := 0
var lab: TerrainLab
var team: TerrainArmy
var slot: RegionSaveSlot
var atlas: RegionData
var world_id := ""
var people: Array[int] = []
var boat_id := ""
var dock: Dictionary = {}

func _process(_delta: float) -> bool:
	if _started and not _finished and Time.get_ticks_msec() > deadline:
		push_error("Ship travel transaction bounded deadline")
		quit(1)
	return false

func _must(value: bool, message: String) -> bool:
	if value and Time.get_ticks_msec() <= deadline: return true
	push_error(message)
	_finished = true
	quit(1)
	return false

func _freeze() -> void:
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)

func _find_dock(data: TerrainData) -> Dictionary:
	for y in range(4, 96):
		for x in range(4, 96):
			var shore := Vector2i(x, y)
			if not data.is_walkable(shore): continue
			for facing: Vector2i in TerrainData.DIRECTIONS:
				var right := Vector2i(-facing.y, facing.x)
				# Original two stern-side contacts, searched from land. This avoids
				# scanning every licensed sea cell before reaching the actual coast.
				for anchor: Vector2i in [shore + right, shore - right * 2]:
					if not data.can_place_water_vehicle(Ship.footprint("ferry", anchor, facing)) or absi(data.effective_height(shore) - data.effective_height(anchor)) > 1: continue
					if not Ship.boarding_cells("ferry", anchor, facing).has(shore): continue
					var cells: Array[Vector2i] = []
					for at in range(data.size.x * data.size.y):
						var cell := data.cell_from_index(at)
						if data.is_walkable(cell) and cell != shore and not lab.character.occupies_cell(cell) and not lab.npc.occupies_cell(cell): cells.append(cell)
					cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(shore) < b.distance_squared_to(shore))
					if cells.size() >= 4: return {"anchor": anchor, "facing": facing, "shore": shore, "cells": cells.slice(0, 4)}
	return {}

func _walk(index: int, target: Vector2i) -> bool:
	var blocked := func(cell: Vector2i) -> bool:
		return team._cell_owners.has(cell) and int(team._cell_owners[cell]) != index or lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell)
	var path: Array[Vector2i] = lab.terrain.path_between(team.cells[index], target, blocked)
	if not _must(not path.is_empty(), "Original travel boarding shore path missing"): return false
	for cell: Vector2i in path:
		if cell == team.cells[index]: continue
		if not _must(team._reserve_combat_step(index, cell), "Original travel shore step rejected"): return false
		team.prepare_combat(float(team.move_duration[index]) + 0.01, 0.0)
		if not _must(team.cells[index] == cell and team.moving_to[index] == TerrainArmy.INVALID_CELL, "Original travel shore step did not commit"): return false
	return true

func _finish(identity: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not _must(actions.is_busy(identity), "Travel setup requires the real timed job"): return false
	var job: Dictionary = actions._jobs[str(identity)]
	actions.advance_ship_jobs(float(job.duration) - float(job.elapsed) + 0.01)
	actions.settle_after_contacts()
	return _must(not actions.is_busy(identity), "Travel setup job failed to settle")

func _board(index: int) -> bool:
	if not _walk(index, dock.shore): return false
	var actions: SitePersonActions = lab.site_controller.person_actions
	var started: Dictionary = actions.begin_ship_board(people[index], boat_id, people[index], index, true)
	return _must(started.ok, "Original travel boarding rejected: " + str(started)) and _finish(people[index])

func _capture() -> void:
	team.prepare_combat(0.0, 0.0)
	team.settle_combat_command()
	lab.site_controller._capture_positions()

func _without_berth_pose(units: Array) -> Array:
	var copy: Array = units.duplicate(true)
	for row: Dictionary in copy:
		if row.has("embarked_vehicle_id") and float(row.get("hp", 0.0)) > 0.0 and bool(row.get("member", true)):
			row.erase("cell")
			row.erase("slot")
	return copy

func _berth_seated(units: Array) -> bool:
	for row: Dictionary in units:
		if row.has("embarked_vehicle_id") and float(row.get("hp", 0.0)) > 0.0 and bool(row.get("member", true)):
			if not row.get("cell") is Array or not _same_json(row.get("slot"), row.get("cell")): return false
	return true

func _same_json(left: Variant, right: Variant) -> bool:
	# JSON has a single number type. Preserve every key/value and full float
	# precision, while comparing captured ints/typed arrays with parsed numbers.
	return JSON.parse_string(JSON.stringify(left, "", true, true)) == JSON.parse_string(JSON.stringify(right, "", true, true))

func _family_slot_files(folder_path: String) -> Dictionary:
	var files: Dictionary = {}
	var pending: Array[String] = [folder_path]
	while not pending.is_empty():
		var directory_path: String = pending.pop_back()
		var directory: DirAccess = DirAccess.open(directory_path)
		if not _must(directory != null, "Original test Slot evidence directory unreadable"): return {}
		for child: String in directory.get_directories(): pending.append(directory_path.path_join(child))
		for name: String in directory.get_files():
			var file_path: String = directory_path.path_join(name)
			files[file_path] = FileAccess.get_sha256(file_path)
	return files

func _logical_family_path_contract(cold: RegionSaveSlot, reference: Dictionary, resident_data: TerrainData, selected_source: TerrainData, live_state: Dictionary, before_files: Dictionary, before_control: PackedByteArray, before_marker: PackedByteArray, before_live: PackedByteArray) -> bool:
	var logical: String = str(reference.path)
	var prefix: String = cold.folder.path_join("sites")
	if not _must(logical == prefix.path_join(str(FROM.x)).path_join(str(FROM.y) + ".json") and not FileAccess.file_exists(logical)
		and cold.site_path(FROM) != logical and FileAccess.file_exists(cold.site_path(FROM)), "Actual resident logical identity must have ONLY a selected existing generation"): return false
	if not _must(resident_data.fingerprint() == selected_source.fingerprint() and _same_json(resident_data.site, selected_source.site), "Logical family reference did not resolve the exact current source generation"): return false
	if not _must(_family_slot_files(cold.folder) == before_files and var_to_bytes(cold.control) == before_control and var_to_bytes(cold._marker) == before_marker and var_to_bytes(live_state) == before_live, "Legal logical family read mutated source/clock/marker/save files"): return false
	var invalid: Array[String] = [
		prefix.path_join("0" + str(FROM.x)).path_join(str(FROM.y) + ".json"),
		prefix.path_join(str(FROM.x)).path_join("+" + str(FROM.y) + ".json"),
		prefix.path_join(str(FROM.x) + ".5").path_join(str(FROM.y) + ".json"),
		prefix.path_join("10000001/101.json"),
		prefix.path_join("10000000/10000000.json"),
		prefix.path_join(str(FROM.x) + "/../" + str(FROM.x)).path_join(str(FROM.y) + ".json"),
		prefix + "/" + str(FROM.x) + "//" + str(FROM.y) + ".json",
		cold.folder.path_join("families").path_join(str(FROM.x)).path_join(str(FROM.y) + ".json"),
		cold.folder.get_base_dir().path_join("other_slot/sites").path_join(str(FROM.x)).path_join(str(FROM.y) + ".json")]
	for path: String in invalid:
		var rejected: Dictionary = cold.load_compatible_site(path)
		if not _must(not rejected.ok and str(rejected.code) in ["NO_SAVE", "INVALID_SLOT"] and not FileAccess.file_exists(path)
			and _family_slot_files(cold.folder) == before_files and var_to_bytes(cold.control) == before_control
			and var_to_bytes(cold._marker) == before_marker and var_to_bytes(live_state) == before_live,
			"Noncanonical/cross-slot/unvisited family path created a fresh Site or mutated original saves: " + path + " => " + str(rejected)): return false
	# A test-owned existing corrupt logical file MUST keep its original read
	# error; it cannot be hidden by a valid marker-selected generation.
	if not _must(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(logical.get_base_dir())) == OK, "Test-owned logical corrupt probe directory"): return false
	var probe: FileAccess = FileAccess.open(logical, FileAccess.WRITE)
	if not _must(probe != null, "Test-owned logical corrupt probe write"): return false
	probe.store_string("corrupt logical family alias")
	probe.close()
	var corrupt_bytes: String = FileAccess.get_sha256(logical)
	var corrupt_files: Dictionary = _family_slot_files(cold.folder)
	var corrupt: Dictionary = cold.load_compatible_site(logical)
	if not _must(not corrupt.ok and corrupt.code == "CORRUPT_SAVE" and FileAccess.get_sha256(logical) == corrupt_bytes
		and _family_slot_files(cold.folder) == corrupt_files and var_to_bytes(cold.control) == before_control
		and var_to_bytes(cold._marker) == before_marker and var_to_bytes(live_state) == before_live,
		"Existing corrupt logical file fell back or mutated original generation/source"): return false
	if not _must(DirAccess.remove_absolute(ProjectSettings.globalize_path(logical)) == OK and _family_slot_files(cold.folder) == before_files, "Test-owned corrupt alias cleanup changed original save files"): return false
	var reread: Dictionary = cold.load_compatible_site(logical)
	return _must(reread.ok and _same_json(reread.data.site, selected_source.site) and _family_slot_files(cold.folder) == before_files
		and var_to_bytes(cold.control) == before_control and var_to_bytes(cold._marker) == before_marker and var_to_bytes(live_state) == before_live,
		"Restored missing alias did not resume current generation without source/save replay")

func _travel_closure(expected: Dictionary, origin: Dictionary, arrived: Dictionary) -> bool:
	# Only the selected original team/people/boat closure migrates. Residents
	# remain at the source. Compare all original values without a tolerance.
	var travelling_team := int(expected.vehicles[boat_id].team_id)
	var moved_supply := {}
	var remaining_supply: Dictionary = expected.team_supply.duplicate(true)
	for key: String in expected.team_supply:
		if int(key) != travelling_team: continue
		var supply: Dictionary = expected.team_supply[key].duplicate(true)
		for location: String in supply.locations.keys():
			if location == "vehicle:" + boat_id: continue
			var stock: Dictionary = supply.locations[location]
			if not _must(Runtime.inventory_size(stock.inventory) == 0 and float(stock.open_rations) == 0.0, "Expected travel closure contains actual shore/nonselected-boat stock: " + location): return false
			# The original Slot drops only empty historical locations; sustain,
			# every actual stock and all non-location fields stay byte-value exact.
			supply.locations.erase(location)
		moved_supply[key] = supply
		remaining_supply.erase(key)
	if not _must(_same_json(arrived.team_supply, moved_supply) and _same_json(origin.team_supply, remaining_supply), "Travel team supply split changed actual stock/meal/morale history or resident ownership"): return false
	var moved_private := {}
	var remaining_private := {}
	for key: String in expected.person_supply:
		if people.has(int(key)): moved_private[key] = expected.person_supply[key]
		else: remaining_private[key] = expected.person_supply[key]
	if not _must(_same_json(arrived.person_supply, moved_private) and _same_json(origin.person_supply, remaining_private), "Travel private supply split changed a traveller/resident original meal source"): return false
	var moved_loot := {}
	var remaining_loot := {}
	for key: String in expected.ground_loot:
		var loot: Dictionary = expected.ground_loot[key]
		if str(loot.get("vehicle_id", "")) == boat_id: moved_loot[key] = loot
		else: remaining_loot[key] = loot
	if not _must(_same_json(arrived.ground_loot, moved_loot) and _same_json(origin.ground_loot, remaining_loot), "Travel loot split changed an original boat/land remains container"): return false
	var moved_nations := {}
	var remaining_nations := {}
	for key: String in expected.equipment_nations:
		var nation: Dictionary = expected.equipment_nations[key]
		var touched := false
		for identity: Variant in nation.members: touched = touched or people.has(int(identity))
		if touched:
			for identity: Variant in nation.members:
				if not _must(people.has(int(identity)), "Travel equipment nation closure still references a resident"): return false
			moved_nations[key] = nation
		else: remaining_nations[key] = nation
	return _must(_same_json(arrived.equipment_nations, moved_nations) and _same_json(origin.equipment_nations, remaining_nations), "Travel military equipment split changed an original traveller/resident relation")

func _reopen() -> RegionSaveSlot:
	var restored := Slot.new()
	if not _must(restored.open_map(atlas, world_id, "slot").ok, "Original slot could not reopen the committed generation"): return null
	return restored

func _run() -> void:
	_started = true
	deadline = Time.get_ticks_msec() + 180000
	_output = "res://output/site_ship_close_20261004/travel/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _must(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output)) == OK, "Travel evidence directory failed"): return
	# Inherited Region fixture writes original elevation/level/ocean-mask assets.
	var manifest: Dictionary = _fixture()
	_write(_output.path_join("manifest.json"), JSON.stringify(manifest).to_utf8_buffer())
	atlas = Atlas.new()
	if not _must(atlas.load_manifest(_output.path_join("manifest.json")).ok, "Travel source manifest failed"): return
	world_id = "ship_travel_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	slot = Slot.new()
	if not _must(slot.open_map(atlas, world_id, "slot").ok, "Travel slot pin failed"): return
	var opened: Dictionary = slot.open_site(FROM)
	if not _must(opened.ok and opened.interactive, "Synthetic pinned source has no real land"): return
	var data: TerrainData = opened.data
	# Original saved grading deltas establish an explicit level shore; no water
	# mask, surface, body ID, source pin or real-person row is replaced.
	for at in range(data.height_levels.size()):
		if data.height_levels[at] != 0:
			data.site.terrain_changes[str(at)] = 0
			data.height_levels[at] = 0
	Runtime.rebuild_terrain_edges(data)
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.bind_terrain(data)
	_freeze()
	dock = _find_dock(data)
	if not _must(not dock.is_empty(), "Original fixed ocean source cannot admit a real ferry"): return
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 4
	var cells: Array[Vector2i] = []
	cells.assign(dock.cells)
	if not _must(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false, 0), "Original travel roster deployment failed"): return
	data.site.army_next_team = team.team_id + 1
	data.site.army_trial_active = true
	for index in range(4):
		team.combat_units[index].logistics = true
		people.append(team.combat_identity(index))
	var controller: SiteController = lab.site_controller
	var supply: Dictionary = controller._enable_team_supply(team)
	if not _must(not supply.is_empty(), "Original travel supply enable failed"): return
	supply.inventory.grain = 4 # Explicit original starting common stock, not a second ledger.
	var deployed: Dictionary = controller.vehicles.deploy_ship(team, "ferry", dock.anchor, dock.facing, true)
	if not _must(deployed.ok, "Original travel ferry deployment failed: " + str(deployed)): return
	boat_id = str(deployed.vehicle_id)
	for index in range(3):
		if not _board(index): return
	# Region R1: the three people aboard form a sailable crew (helm + minimum
	# crew) and the controlled body is aboard, so the only reason left to refuse
	# is the fourth member still ashore. The commander loads the food before
	# taking the helm (helm duty is busy).
	var loaded_food: Dictionary = controller.transfer_ship_supply(team, "shore:%d" % data.index(dock.shore), "vehicle:" + boat_id, {"grain": 4}, 0.0, people[0], true)
	if not _must(loaded_food.ok, "Original physical common food loading failed: " + str(loaded_food)): return
	var helm: Dictionary = controller.person_actions.begin_ship_helm(people[0], boat_id, people[0], true)
	if not _must(helm.ok, "Original travel helm job failed") or not _finish(people[0]): return
	var had_control: bool = data.site.has("controlled_person_id")
	var ashore_control: int = int(data.site.get("controlled_person_id", -1))
	data.site["controlled_person_id"] = people[0]
	_capture()
	var boats: Array[String] = [boat_id]
	var before := var_to_bytes(data.site)
	var partial: Dictionary = slot.prepare_ship_transfer(data, TO, boats, dock.anchor, dock.facing)
	if not _must(not partial.ok and partial.code == "NOT_EMBARKED" and var_to_bytes(data.site) == before, "Half-team travel was not rejected atomically: " + str(partial)): return
	if not _must(slot._prepared.is_empty() and slot._marker.get("journey", {}).is_empty(), "Half-team refusal left a prepared journey"): return
	if had_control: data.site["controlled_person_id"] = ashore_control
	else: data.site.erase("controlled_person_id")
	if not _board(3): return
	var nation: Dictionary = controller.register_trial_equipment_nation(team, "trial_team_travel", people[0], people.duplicate(), "chinese")
	if not _must(nation.ok, "Original closed military nation registration failed: " + str(nation)): return
	data.site.controlled_person_id = people[3] # Explicit selection of an existing original row.
	if not _must(team.leave_row(people[3]).ok, "Original travel retirement failed"): return
	data.site.controlled_person_id = people[0]
	var references: Array = []
	for identity: int in people:
		references.append({"site_id": str(data.site.id), "path": slot.site_path(FROM), "label": "original_%d" % identity, "person_id": identity, "age_years": -1})
	references.append({"site_id": str(data.site.id), "path": slot.site_path(FROM), "label": "resident_actor", "person_id": lab.character.person_id, "age_years": -1})
	if not _must(controller.family_continuity.register_members(references, true).ok, "Original family reference registration failed"): return
	team.apply_unit_contact(1, {"result": {"hp": 0.0, "stun": 1000.0, "guard_break": false}, "shield": false})
	team.apply_unit_contact(2, {"result": {"hp": 10000.0, "stun": 0.0, "guard_break": false}, "shield": false})
	controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.5)
	data.site.combat_left = 0.0 # Same explicit settled/out-of-combat fixture contract as the real JSON tests.
	_capture()
	if not _must(bool(team.combat_units[2].ship_death_settled) and not data.site.ground_loot.is_empty() and float(team.combat_hot_get(1, &"ko", 0.0)) > 0.0, "Travel fixture omitted the real KO/dead/boat-loot closure"): return
	if not _must(slot.attach_active_site(data).ok and controller.supply_save_guard().ok, "Original source clock/save preflight failed"): return
	# Region R1: a downed but alive member blocks departure (rescue or bandage
	# first). The refusal is atomic: no live-source change, no prepared journey.
	var downed_before := var_to_bytes(data.site)
	var downed: Dictionary = slot.prepare_ship_transfer(data, TO, boats, dock.anchor, dock.facing)
	if not _must(not downed.ok and downed.code == "NOT_READY" and str(downed.message).contains("倒地") and var_to_bytes(data.site) == downed_before \
		and slot._prepared.is_empty() and slot._marker.get("journey", {}).is_empty(), "Downed-member departure was not refused atomically: " + str(downed)): return
	team.combat_hot_set(1, &"ko", 0.0)
	team.combat_hot_set(1, &"stun", 0.0)
	team.combat_hot_set(1, &"pose", "idle")
	team.combat_hot_set(1, &"age", 0.0)
	_capture()
	# Decision A2 (Nekki, 2026-10-10): the settled dead member (unit 2) and the
	# discharged member (people[3]) do not block departure; they travel inert
	# with the container and stay in it, unchanged, at the destination.
	var inert_before: Array = [data.site.armies[0].units[2].duplicate(true), data.site.armies[0].units[3].duplicate(true)]
	var dead_id := int(inert_before[0].person_id)
	var dead_supply_before: Dictionary = data.site.get("person_supply", {}).get(str(dead_id), {}).duplicate(true)
	if not _must(float(inert_before[0].hp) <= 0.0 and bool(inert_before[0].get("loot_settled", false)) and not bool(inert_before[1].get("member", true)),
		"Fixture lacks the settled dead and discharged rows"): return
	# S1: on a sea leg an inert row rides no ship. A stale embarked_vehicle_id
	# (with an impossible berth) must not put it aboard on arrival: the same
	# original sea placement runs on a detached copy of this real content.
	var probe_site: Dictionary = data.site.duplicate(true)
	var probe := {"armies": probe_site.armies, "actors": {}, "vehicles": {boat_id: probe_site.vehicles[boat_id]}, "ground_loot": {}}
	probe.armies[0].units[3]["embarked_vehicle_id"] = boat_id
	probe.armies[0].units[3]["berth_id"] = 999
	var stale_before := var_to_bytes(probe.armies[0].units[3])
	var dead_before := var_to_bytes(probe.armies[0].units[2])
	var placed: Dictionary = RegionTravel._sea_arrival(probe, {}, data, {}, people[0])
	if not _must(placed.ok and var_to_bytes(probe.armies[0].units[3]) == stale_before and var_to_bytes(probe.armies[0].units[2]) == dead_before 		and placed.leader_cell != Vector2i(-1, -1), "Inert row with a stale embarked_vehicle_id leaked onto the arrival ship: " + str(placed)): return
	if not _must(slot.save_site(data).ok, "Original travel departure baseline failed"): return
	var source_path := slot.site_path(FROM)
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	before = var_to_bytes(data.site)
	var blocked: Dictionary = slot.prepare_ship_transfer(data, TO, boats, Vector2i(-2, -2), dock.facing)
	if not _must(not blocked.ok and var_to_bytes(data.site) == before and FileAccess.get_file_as_bytes(source_path) == source_bytes, "Blocked destination modified source or published a generation"): return
	var prepared: Dictionary = slot.prepare_ship_transfer(data, TO, boats, dock.anchor, dock.facing)
	if not _must(prepared.ok and var_to_bytes(data.site) == before, "Prepared transfer mutated live source or failed: " + str(prepared)): return
	var token := str(prepared.token)
	var cold := _reopen()
	if not _must(cold != null and cold.open_site(FROM).data.site.armies.size() == 1 and cold.effective_site_path(TO).path == "", "Uncommitted prepared files replaced original effective ownership"): return
	if not _must(slot.checkpoint_ship_transfer(token, data, 0.0).ok, "Original departure checkpoint failed"): return
	cold = _reopen()
	var status: Dictionary = cold.ship_transfer_status()
	if not _must(status.ok and status.token == token and status.elapsed_action_seconds == 0.0 and status.elapsed_game_seconds == 0.0, "Original journey did not recover its independent ACTION progress"): return
	var incomplete: Dictionary = slot.commit_ship_transfer(token, data)
	if not _must(not incomplete.ok and incomplete.code == "INCOMPLETE_JOURNEY" and var_to_bytes(data.site) == before, "Zero-action transfer committed"): return
	if not _must(slot.cancel_ship_transfer(token).ok, "Original prepared journey cancellation failed"): return
	cold = _reopen()
	if not _must(cold != null and cold.ship_transfer_status().pending == false, "Cancelled checkpoint retained an active journey"): return
	var cancelled_source: Dictionary = cold.open_site(FROM)
	if not _must(cancelled_source.ok and _same_json(cancelled_source.data.site.armies[0].units, data.site.armies[0].units) \
		and FileAccess.get_file_as_bytes(cold.site_path(FROM)) == source_bytes, "Cancelled checkpoint changed complete original travelers/source bytes"): return
	if not _must(slot.commit_ship_transfer(token, data).code == "CANCELLED", "Cancelled checkpoint remained replayable"): return
	print("SITE_SHIP_TRAVEL_PROGRESS:departure_cancel_preserved:wall_ms=%d" % (Time.get_ticks_msec() - (deadline - 180000)))
	prepared = slot.prepare_ship_transfer(data, TO, boats, dock.anchor, dock.facing)
	if not _must(prepared.ok and var_to_bytes(data.site) == before, "Restarted original journey after cancel failed"): return
	token = str(prepared.token)
	if not _must(slot.checkpoint_ship_transfer(token, data, 0.0).ok, "Restarted journey departure checkpoint failed"): return
	# Region R1 single clock: the original shared step publishes each completed
	# step itself (GAME and fire watermark) through the controller's slot. The
	# test never records a second time; it only checks the one clock.
	controller.region_slot = slot
	# Same formal activation bind_terrain performs when the slot is present: the
	# active original owner acknowledges its complete bind, admitting its mode.
	var activated: Dictionary = slot.acknowledge_region_bind(data, lab.region_bind_receipt(data))
	if not _must(activated.ok, "Original active Site was not admitted by its complete bind: " + str(activated)): return
	var clock_start := float(slot.control.logical_game_seconds)
	var completed_game_total := 0.0
	var elapsed := 0.0
	var completed_action_total := 0.0
	while elapsed + 0.000001 < float(prepared.seconds):
		var previous_seconds := Slot._site_seconds(data)
		var remainder := lab._action_time_remainder
		# The shared step carries a sub-step remainder; request only what, with that
		# remainder, completes the leg within one more original fixed step.
		var request := minf(0.25, float(prepared.seconds) - elapsed + TerrainLab.EXCHANGE_ACTION_STEP - remainder)
		lab._advance_action_time(request)
		var completed_game := Slot._site_seconds(data) - previous_seconds
		var completed_action := request + remainder - lab._action_time_remainder
		if not _must(completed_action > 0.0 and completed_game > 0.0, "Original shared travel fixture step made no progress"): return
		completed_game_total += completed_game
		completed_action_total += completed_action
		# The original fixed step completes in full. Only its journey distance is
		# capped at the leg end; body/food/GAME time retain the whole actual step.
		elapsed = minf(float(prepared.seconds), elapsed + completed_action)
	if not _must(completed_action_total + 0.000001 >= elapsed and completed_action_total - elapsed <= TerrainLab.EXCHANGE_ACTION_STEP + 0.000001, "Original completed ACTION and capped leg distance diverged"): return
	if not _must(is_equal_approx(float(slot.control.logical_game_seconds) - clock_start, completed_game_total), "The shared step did not publish exactly one GAME clock"): return
	print("SITE_SHIP_TRAVEL_PROGRESS:completed_action=%.8f:journey_action=%.8f:whole_step_delta=%.8f" % [completed_action_total, elapsed, completed_action_total - elapsed])
	_capture()
	if not _must(controller.supply_save_guard().ok and slot.checkpoint_ship_transfer(token, data, elapsed).ok, "Original completed travel checkpoint failed"): return
	var expected: Dictionary = data.site.duplicate(true)
	var original_ids: Array = expected.item_records.keys()
	var source_people: Dictionary = Slot._saved_people(expected)
	var load_before: Dictionary = Store._ship_saved_load(expected, expected.vehicles[boat_id], source_people)
	if not _must(load_before.ok, "Original travel Q could not be measured"): return
	var actors: Dictionary = expected.actors.duplicate(true)
	cold = _reopen()
	status = cold.ship_transfer_status()
	if not _must(status.ok and is_equal_approx(float(status.elapsed_action_seconds), elapsed) and is_equal_approx(float(status.elapsed_game_seconds), float(slot.control.logical_game_seconds)), "Checkpoint recovery conflated ACTION with GAME time"): return
	var committed: Dictionary = slot.commit_ship_transfer(token, data)
	if not _must(committed.ok and var_to_bytes(data.site) == var_to_bytes(expected), "Atomic original transfer failed or mutated live source before bind: " + str(committed)): return
	cold = _reopen()
	var from: Dictionary = cold.open_site(FROM)
	var to: Dictionary = cold.open_site(TO)
	if not _must(from.ok and to.ok and from.data.site.armies.is_empty() and _same_json(from.data.site.actors, actors) and not from.data.site.vehicles.has(boat_id), "Source generation retained travelers or lost original resident Actors: " + str({"from": from.get("code", "OK"), "to": to.get("code", "OK"), "actors_equal": _same_json(from.data.site.actors, actors) if from.ok else false})): return
	var arrived: Dictionary = to.data.site
	# Region R1 sea arrival seats each aboard member at its berth: cell and slot
	# become that berth cell. Every other field, and every inert row in full,
	# must be unchanged.
	if not _must(arrived.armies.size() == 1 and _same_json(_without_berth_pose(arrived.armies[0].units), _without_berth_pose(expected.armies[0].units)) and _berth_seated(arrived.armies[0].units) and _same_json(arrived.armies[0].team_fatigue, expected.armies[0].team_fatigue), "Travel changed original roster, retirement/life or shared fatigue history"): return
	if not _travel_closure(expected, from.data.site, arrived): return
	if not _must(_same_json(arrived.armies[0].units[2], expected.armies[0].units[2]) and _same_json(arrived.armies[0].units[3], expected.armies[0].units[3])
		and float(arrived.armies[0].units[2].hp) <= 0.0 and not bool(arrived.armies[0].units[3].get("member", true)), "Inert dead/discharged rows changed on arrival"): return
	# A settled dead member consumes nothing in transit (team pools and Sustain
	# count only living members); its own ration record, if any, is unchanged.
	if not _must(_same_json(arrived.get("person_supply", {}).get(str(dead_id), {}), dead_supply_before), "Settled dead member consumed rations in transit"): return
	for identity: Variant in original_ids:
		var moving: bool = expected.item_records[identity].holder != "person:" + str(lab.character.person_id) and expected.item_records[identity].holder != "person:" + str(lab.npc.person_id) and expected.item_records[identity].holder != "depot"
		var record: Dictionary = arrived.item_records.get(identity, {}) if moving else from.data.site.item_records.get(identity, {})
		if not _must(_same_json(record, expected.item_records[identity]), "Travel lost or rewrote original item record #" + str(identity)): return
	var load_after: Dictionary = Store._ship_saved_load(arrived, arrived.vehicles[boat_id], Slot._saved_people(arrived))
	if not _must(load_after.ok and is_equal_approx(float(load_after.load), float(load_before.load)) and arrived.actors.is_empty() and int(arrived.controlled_person_id) == people[0], "Travel changed N/Q/control or created destination Actors"): return
	if not _must(cold.commit_ship_transfer(token, data).code == "ALREADY_COMMITTED", "Committed journal replayed original travelers"): return
	# The resident Actor's own registry entry (by its label, not list order:
	# travelling members' entries now follow them to the destination).
	var resident_reference: Dictionary = {}
	for family_member: Dictionary in arrived.family.members:
		if str(family_member.get("label", "")) == "resident_actor": resident_reference = family_member
	if not _must(not resident_reference.is_empty(), "Resident Actor family entry missing after travel"): return
	var family_files: Dictionary = _family_slot_files(cold.folder)
	var family_control: PackedByteArray = var_to_bytes(cold.control)
	var family_marker: PackedByteArray = var_to_bytes(cold._marker)
	var family_live: PackedByteArray = var_to_bytes(data.site)
	var resident: Dictionary = cold.load_compatible_site(str(resident_reference.path))
	if not _must(resident.ok and resident.data.site.armies.is_empty() and _same_json(resident.data.site.actors, actors), "Original family loader reopened the old traveler generation: " + str(resident_reference) + " load=" + str(resident.get("code", "OK")) + " message=" + str(resident.get("message", "")) + " actors_equal=" + str(_same_json(resident.data.site.actors, actors) if resident.ok else false) + " armies=" + str(resident.data.site.armies.size() if resident.ok else -1)): return
	if not _logical_family_path_contract(cold, resident_reference, resident.data, from.data, data.site, family_files, family_control, family_marker, family_live): return
	lab.bind_terrain(to.data)
	team = lab.army
	_freeze()
	if not _must(lab.combat_actors.is_empty() and team.combat_units.size() == 4 and team.combat_identity(3) == people[3] and not team.is_member(3), "Original destination bind respawned residents or retired traveler"): return
	_finished = true
	print("SITE_SHIP_TRAVEL_PASS:scope=raw_original_slot_transaction_and_shared_steps:real_board=4:one_action_progress:one_game_clock:prepared_crash_old:checkpoint_resume:full_closed_roster_food_items_family_military_downed_refused_dead_discharged_inert:pair_commit_no_replay:actors_stay_source;formal_Controller_phase_caller_separate")
	quit(0)
