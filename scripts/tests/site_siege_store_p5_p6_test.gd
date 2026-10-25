extends "res://scripts/tests/site_siege_store_roundtrip_test.gd"
## Actual original Store/Controller file roundtrip and failed-load atomicity.
## Each named --crowd-test run executes one mode/case. No World save is touched.

const CASES := ["stable", "deployed", "disabled", "wreck", "legacy", "plain"]
const DT := 1.0 / 120.0
const OUTPUT := "res://output/site_siege_close_20261004/store_integration"
var store_mode := "gd"
var store_case := "stable"
var test_checks := 0
var test_roundtrips := 0
var test_rejections := 0
var native_crew_rejections := 0
var test_shared_steps := 0
var test_failed := false
var test_results: Array[Dictionary] = []
var keys_by_kind: Dictionary = {}
var original_ids: Array[int] = []
var roof_person := 0
var roof_cell := Vector2i(41, 41)
var rescue_person := 0
var recovery_evidence: Dictionary = {}
var wall_key := ""
var ladder_key := ""
var save_folder := ""
var current_path := ""
var report_run := "unconfigured_" + str(Time.get_ticks_usec())

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for pair: Array in [["--siege-store-mode", "store_mode"], ["--siege-store-case", "store_case"]]:
		var index := args.find(str(pair[0]))
		if index >= 0 and index + 1 < args.size(): set(str(pair[1]), args[index + 1])
	_run.call_deferred()

func _expect(value: bool, label: String, detail: Variant = null) -> bool:
	test_checks += 1
	test_results.append({"ok": value, "label": label, "detail": str(detail)})
	if value: return true
	test_failed = true
	_report()
	printerr("SIEGE STORE FAIL: ", label, " / ", detail)
	quit(2)
	return false

func _report() -> void:
	var folder := OUTPUT.path_join(report_run)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder.path_join(store_mode + "_" + store_case + ".json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"ok": not test_failed, "mode": store_mode, "case": store_case,
		"checks": test_checks, "roundtrips": test_roundtrips, "atomic_rejections": test_rejections, "native_crew_rejections": native_crew_rejections, "original_shared_steps": test_shared_steps,
		"run_save_root": save_folder, "results": test_results, "surface_recovery": recovery_evidence,
		"scope": "actual isolated SiteStore save/read plus Controller candidate commit/refusal; no GPU/FPS or general release claim"}, "\t"))
	file.close()

func _preflight() -> bool:
	if not _expect(store_mode in ["gd", "native"] and CASES.has(store_case), "known Store mode/case"): return false
	if not _expect(DisplayServer.get_name() == "headless", "Store contract requires bounded headless verification"): return false
	var args := OS.get_cmdline_user_args()
	var paths := SiteController.new()
	var configured := paths.configure_test_paths(args)
	var named: bool = configured.ok and not paths.crowd_test_run_id.is_empty()
	var fresh := not DirAccess.dir_exists_absolute(paths.save_root)
	var protected: bool = not paths._save_path_guard(SiteStore.DEFAULT_PATH).ok
	save_folder = paths.save_root
	if named: report_run = paths.crowd_test_run_id
	paths.free()
	if not _expect(named and fresh and protected, "fresh named isolated save root and forbidden formal current save", configured): return false
	if store_mode == "native":
		if not _expect(args.has("--crowd") and ClassDB.class_has_method(&"ArmyCrowd", &"siege_ground_cells") and ClassDB.class_has_method(&"ArmyCrowd", &"load_state_with_siege_navigation"), "paired native siege and same-mask candidate-load ABI required"): return false
	return true

func _new_lab() -> bool:
	roundtrip_lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	roundtrip_lab.pause_when_unfocused = false
	roundtrip_lab.movement_input_enabled = false
	root.add_child(roundtrip_lab)
	current_scene = roundtrip_lab
	roundtrip_lab.set_process(false)
	roundtrip_lab.set_process_unhandled_input(false)
	roundtrip_lab.site_controller.set_process(false)
	roundtrip_lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in roundtrip_lab.combat_actors: actor.set_process(false)
	# Original generated FOREST + recorded terrain_changes; no unsaved base-array
	# replacement that would disappear when Store reconstructs the seeded map.
	roundtrip_deadline = Time.get_ticks_msec() + 120000
	var data := _persistent_fixture()
	if not _expect(data != null and not roundtrip_failed, "existing persistent generated fixture"): return false
	# Explicit empty original optional supply collections. No cohort or food is
	# created; both sides retain the defaults that the original loader normalizes.
	data.site.team_supply = {}
	data.site.person_supply = {}
	roundtrip_lab.bind_terrain(data)
	if not _expect(roundtrip_lab.terrain == data, "original TerrainLab binds the persistent fixture"): return false
	var ui: SiteController = roundtrip_lab.site_controller
	ui._auto_save_blocked = true
	ui.release_worker()
	current_path = save_folder.path_join("store_" + store_case + "_current.json")
	ui.save_path = current_path
	return _expect(ui._save_path_guard(current_path).ok, "every test file stays below the named run root", current_path)

func _paid_vehicle(kind: String, anchor: Vector2i) -> String:
	var data := roundtrip_lab.terrain
	var created := SiteRuntime.begin_siege_build(data, kind, anchor, Vector2i.RIGHT, 1, 1)
	if not _expect(created.ok, "paid " + kind + " uses original vehicle construction", created): return ""
	var key := str(created.vehicle)
	var vehicle: Dictionary = data.site.vehicles[key]
	var station: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	var work := SiteRuntime.advance_siege_work(data, key, "construct", float(vehicle.build.total_work), data.cell_from_index(int(station.cell)), int(station.slot), 1)
	if not _expect(work.ok and vehicle.build.is_empty(), kind + " work completes on the original vehicle", work): return ""
	var definition: Dictionary = SiteRuntime.SIEGE_DEFINITIONS[kind]
	if not str(definition.ammo).is_empty():
		var loaded := SiteRuntime.transfer_items(data, data.site.depot_items, data.site.inventory, vehicle.holder, vehicle.cargo, {str(definition.ammo): 2}, [], int(data.site.depot_items.version), int(vehicle.holder.version), int(definition.capacity))
		if not _expect(loaded.ok, kind + " stores real original ammunition and holder versions", loaded): return ""
	keys_by_kind[kind] = key
	return key

func _paid_feature(kind: String, anchor: Vector2i, size: Vector2i = Vector2i.ONE) -> String:
	var data := roundtrip_lab.terrain
	var options := {"owner_faction": 1, "quarter": 0}
	var layout := SiteRuntime.building_cells(data, kind, anchor, size, options)
	if not _expect(layout.ok, "original " + kind + " layout", layout): return ""
	var cells: Array[int] = []; cells.assign(layout.cells)
	var built := SiteRuntime.request_build(data, kind, cells, Callable(), options)
	if not _expect(built.ok, "paid original " + kind + " feature", built): return ""
	var key := str(built.feature)
	var feature: Dictionary = data.site.features[key]
	var task := _task(key, "construct", int(feature.entrance))
	SiteRuntime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	if not _expect(str(feature.stage) == "complete" and SiteRuntime.validate_feature_layout(data, feature).ok, "original feature completed", key): return ""
	return key

func _army(positions: Array[Vector2i]) -> bool:
	var team: TerrainArmy = roundtrip_lab.army
	team.team_id = 1
	team.roster_size = positions.size()
	if not _expect(team.deploy_at(roundtrip_lab.terrain, roundtrip_lab.character, roundtrip_lab.npc, positions) and team.enable_combat(false, 1), "original Army owns every test person"): return false
	team.set_process(false)
	team.tactical_ai_enabled = false
	roundtrip_lab.site_controller.initialize_team_items(team)
	for index in range(positions.size()):
		var body: Dictionary = team.combat_units[index]
		var data := roundtrip_lab.terrain
		var loaded := SiteRuntime.transfer_items(data, data.site.depot_items, data.site.inventory, body.item_state, body.cargo, {"wood": 1}, [], int(data.site.depot_items.version), int(body.item_state.version))
		if not _expect(loaded.ok, "original person carries actual transferred resources", loaded): return false
	roundtrip_lab.terrain.site.army_next_team = 2
	for index in range(positions.size()): original_ids.append(team.combat_identity(index))
	return true

func _fixture_case() -> bool:
	if store_case == "stable":
		var kinds := ["ballista", "ram", "traction_trebuchet", "counterweight_trebuchet", "siege_tower"]
		var anchors: Array[Vector2i] = [Vector2i(20, 20), Vector2i(35, 20), Vector2i(20, 36), Vector2i(40, 36), Vector2i(54, 50)]
		for index in range(kinds.size()):
			if _paid_vehicle(str(kinds[index]), anchors[index]).is_empty(): return false
		if _paid_feature("palisade", Vector2i(20, 55)).is_empty(): return false
		ladder_key = _paid_feature("siege_ladder", Vector2i(20, 56))
		if ladder_key.is_empty(): return false
		if not _army([Vector2i(16, 20), Vector2i(19, 20), Vector2i(19, 21)]): return false
	elif store_case in ["deployed", "disabled", "wreck"]:
		var key := _paid_vehicle("siege_tower", Vector2i(40, 40))
		if key.is_empty(): return false
		wall_key = _paid_feature("palisade", Vector2i(45, 40), Vector2i(1, 3))
		if wall_key.is_empty(): return false
		var vehicle: Dictionary = roundtrip_lab.terrain.site.vehicles[key]
		# Explicit initial stable Store fixture, matching existing landing tests.
		# The movement suite separately proves the real 15-second deployment.
		vehicle.deployed_pose = SiteRuntime.siege_tower_pose(roundtrip_lab.terrain, vehicle)
		vehicle.phase = "deployed"
		SiteEnvironment.rebuild_indexes(roundtrip_lab.terrain)
		if not _expect(SiteRuntime.siege_tower_geometry(roundtrip_lab.terrain, vehicle).active and roundtrip_lab.terrain.effective_height(roof_cell) == 2, "legal original tower roof fixture"): return false
		if not _army([Vector2i(37, 38), roof_cell, Vector2i(37, 43)]): return false
		roof_person = original_ids[1]
	else:
		if not _army([Vector2i(16, 20), Vector2i(17, 20), Vector2i(18, 20)]): return false
		if store_case == "legacy":
			var transport: SiteVehicleTransport = roundtrip_lab.site_controller.vehicles
			var plan := transport.plan_team(1, 1, 1, roundtrip_lab.army.cells)
			if not _expect(plan.ok, "old cart/wagon use original planning", plan): return false
			var deployed := transport.deploy_plan(roundtrip_lab.army, plan.plan)
			if not _expect(deployed.ok, "old cart/wagon original owners deployed", deployed): return false
	if store_case == "stable":
		if not _expect(keys_by_kind.size() == 5 and str(roundtrip_lab.terrain.site.features[ladder_key].kind) == "siege_ladder", "all six agreed categories exist: five original vehicles and original ladder feature"): return false
	elif store_case == "legacy":
		var legacy := {}
		for vehicle: Dictionary in roundtrip_lab.terrain.site.vehicles.values(): legacy[str(vehicle.kind)] = true
		if not _expect(legacy == {"cart": true, "wagon": true} and not SiteStore.has_siege_vehicles(roundtrip_lab.terrain.site), "old cart/wagon retain their original schema with no siege quota fields"): return false
	elif store_case == "plain":
		if not _expect(roundtrip_lab.terrain.site.vehicles.is_empty() and not SiteStore.has_siege_vehicles(roundtrip_lab.terrain.site), "ordinary no-siege regression fixture"): return false
	if store_mode == "native" and not _enter_native(): return false
	if store_case == "stable":
		var key: String = keys_by_kind.ballista
		var transport: SiteVehicleTransport = roundtrip_lab.site_controller.vehicles
		for slot in range(2):
			var assigned := transport.assign_crew(key, original_ids[slot + 1], str(slot), original_ids[0], true)
			if not _expect(assigned.ok, "stable original crew assignment", assigned): return false
		transport.update_siege(0.001)
		if store_mode == "native":
			var inputs: Dictionary = roundtrip_lab.crowd_site.sync_siege_inputs()
			if not _expect(inputs.ok, "stable crew derived native handoff", inputs): return false
		if not _expect(transport.crew_ready(roundtrip_lab.terrain.site.vehicles[key]), "both original crew remain at their actual stations"): return false
	if store_case in ["disabled", "wreck"]:
		if store_mode == "native" and not _prepare_native_rescue(): return false
		if not _lose_surface(): return false
	return true

func _enter_native() -> bool:
	var crowd: Node = roundtrip_lab.crowd_site
	if not _expect(crowd != null and not crowd.active, "actual inactive CrowdSite entry"): return false
	var parsed: Dictionary = roundtrip_lab._trial_side_settings({"friendly_count": 1, "friendly_training": 0, "friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _expect(parsed.ok, "original native deployment side settings", parsed): return false
	var side: Dictionary = parsed.side
	side.faction = 2
	var result: Dictionary = crowd.deploy([side], [[Vector2i(65, 65)]])
	if not _expect(result.ok and crowd.active, "native deploy imports original existing Army rows", result): return false
	# Original native genesis allows this optional empty registration, and the
	# original Store loader adds it. Declare it in the initial fixture so the
	# exact persisted comparison remains strict without hiding any saved value.
	for roster: Dictionary in crowd.rosters:
		if not roster.has("garrison_feature_id"): roster.garrison_feature_id = ""
	for identity: int in original_ids:
		if not _expect(crowd.contains_person(identity), "native still owns the same original person ID", identity): return false
	return true

func _person(identity: int) -> Dictionary:
	return roundtrip_lab.site_controller.person_actions._person(identity)

func _shared_step() -> bool:
	if Time.get_ticks_msec() >= roundtrip_deadline: return _expect(false, "bounded original shared-step deadline")
	var result := roundtrip_lab._advance_original_shared_step(DT)
	if not result.ok or not bool(result.get("completed", false)): return _expect(false, "one original shared step completes", result)
	if store_mode == "native" and not roundtrip_lab.crowd_site.last_event_error.is_empty(): return _expect(false, "native step has no deferred owner error", roundtrip_lab.crowd_site.last_event_error)
	test_shared_steps += 1
	return true

func _lose_surface() -> bool:
	var data := roundtrip_lab.terrain
	var key: String = keys_by_kind.siege_tower
	var person := _person(roof_person)
	var hp := float(person.hp)
	var hit := int(person.hit)
	# Original GD environmental contact keeps effective-hit revision; native
	# sync_surface has its own one-fall revision increment. Preserve both owners.
	var expected_hit: int = hit + (1 if store_mode == "native" else 0)
	var holder: Dictionary = person.holder
	var cargo: Dictionary = person.cargo
	var result: Dictionary
	if store_case == "wreck": result = roundtrip_lab.siege_apply_damage_batch({}, {key: 9999.0})
	else:
		var part := "c:" + str(data.index(Vector2i(45, 41)))
		result = roundtrip_lab.siege_apply_damage_batch({wall_key + "|" + part: {"feature": wall_key, "part": part, "damage": 100.0}}, {})
	if not _expect(result.ok, "original structure batch loses the original tower surface", result): return false
	person = _person(roof_person)
	if not _expect(person.cell == roof_cell and is_equal_approx(float(person.hp), hp - 30.0) and float(person.ko) > 0.0 and int(person.hit) == expected_hit, "one original fall at the central source cell/revision", person): return false
	if not _expect(is_same(holder, person.holder) and is_same(cargo, person.cargo), "fall preserves original item/cargo owners"): return false
	if not _expect(data.effective_height(roof_cell) == 0 and str(data.site.vehicles[key].phase) == ("wrecked" if store_case == "wreck" else "disabled"), "lost surface stays removed with retained original pose"): return false
	var settled_hp := float(person.hp)
	if store_mode == "native":
		recovery_evidence.merge({"patient": roof_person, "rescuer": rescue_person, "source_cell": [roof_cell.x, roof_cell.y], "fall_hp_loss": 30.0, "fall_hit_revision": expected_hit, "after_fall_hp": settled_hp}, true)
		if not _bandage_native_fall(expected_hit, holder, cargo): return false
		settled_hp = float(_person(roof_person).hp)
	# Let the original combat timer drain. Do not zero or edit the save guard.
	for _slice in range(1320):
		if float(data.site.combat_left) <= 0.0: break
		if not _shared_step(): return false
	person = _person(roof_person)
	return _expect(float(data.site.combat_left) <= 0.0 and person.cell == roof_cell and is_equal_approx(float(person.hp), settled_hp) and int(person.hit) == expected_hit
		and is_same(holder, person.holder) and is_same(cargo, person.cargo), "original timer drains without relocating, bleeding after real bandage, or falling twice")

func _prepare_native_rescue() -> bool:
	# Preserve the original central cell. The original control/key path only
	# moves the patient within that cell before the actual fall transaction.
	var switched: Dictionary = roundtrip_lab.site_controller._control_family_person(null, roof_person)
	if not _expect(switched.ok and roundtrip_lab.controlled_person_id() == roof_person, "original control selects the same central saved patient", switched): return false
	root.gui_release_focus()
	roundtrip_lab.movement_input_enabled = true
	var pressed := InputEventKey.new()
	pressed.keycode = KEY_UP; pressed.physical_keycode = KEY_UP; pressed.pressed = true
	roundtrip_lab._unhandled_input(pressed)
	var advanced := true
	for _tick in range(64):
		var person := _person(roof_person)
		var values: PackedFloat64Array = person.owner._soldier_values(int(person.unit))
		if values[15] <= float(roof_cell.y) + 0.10: break
		if not _shared_step(): advanced = false; break
	var released := InputEventKey.new()
	released.keycode = KEY_UP; released.physical_keycode = KEY_UP; released.pressed = false
	roundtrip_lab._unhandled_input(released)
	roundtrip_lab.movement_input_enabled = false
	if not advanced or not _settle_released_native_input(roof_person): return false
	var patient := _person(roof_person)
	var original_position: Vector2 = patient.position / 64.0
	if not _expect(patient.cell == roof_cell and not bool(patient.moving) and original_position.y > float(roof_cell.y) and original_position.y <= float(roof_cell.y) + 0.10,
		"original held-key patient stays inside its saved central roof cell", {"position": original_position, "moving": patient.moving, "cell": patient.cell}): return false
	rescue_person = original_ids[2]
	var goal := roof_cell + Vector2i.UP * 2
	for _tick in range(3600):
		var rescuer := _person(rescue_person)
		if rescuer.cell == goal and not bool(rescuer.moving):
			var vehicle: Dictionary = roundtrip_lab.terrain.site.vehicles[keys_by_kind.siege_tower]
			return _expect(not SiteRuntime.siege_tower_physical_cells(roundtrip_lab.terrain, vehicle).has(rescuer.cell) and rescuer.owner.combat_can_act(int(rescuer.unit)), "actual original rescuer arrives and holds outside the intact tower", rescuer.cell)
		if not bool(rescuer.moving) and not _expect(roundtrip_lab.crowd_site.siege_approach_step(rescue_person, goal), "original rescuer reserves the next real edge to outside aid position", rescuer.cell): return false
		if not _shared_step(): return false
	return _expect(false, "real rescuer reaches its legal exterior source before the bounded deadline")

func _settle_released_native_input(identity: int) -> bool:
	# Original World retains 60% velocity each ordinary idle slice. Twelve
	# slices can still exceed the original 0.001 moving threshold; observe up
	# to24 actual slices, without clearing velocity or commitment.
	for _release_slice in range(24):
		if not _shared_step(): return false
		if not bool(_person(identity).moving): return true
	return _expect(false, "original released native input actually settles", _person(identity))

func _position_native_rescuer(revision: int, original_holder: Dictionary, original_cargo: Dictionary) -> bool:
	# Original key movement stops at the original 0.30-cell body margin. The
	# patient is already KO at its same central source; neither body is placed.
	var exterior := roof_cell + Vector2i.UP * 2
	var rescuer := _person(rescue_person)
	if not _expect(rescuer.cell == exterior and not bool(rescuer.moving), "original rescuer starts at its settled exterior source"): return false
	roundtrip_lab.crowd_site.crowd.cancel_siege_step(int(rescuer.unit))
	var switched: Dictionary = roundtrip_lab.site_controller._control_family_person(null, rescue_person)
	if not _expect(switched.ok and roundtrip_lab.controlled_person_id() == rescue_person, "original control selects the existing rescuer", switched): return false
	root.gui_release_focus()
	roundtrip_lab.movement_input_enabled = true
	var pressed := InputEventKey.new()
	pressed.keycode = KEY_DOWN; pressed.physical_keycode = KEY_DOWN; pressed.pressed = true
	roundtrip_lab._unhandled_input(pressed)
	var advanced := true
	for _tick in range(64):
		rescuer = _person(rescue_person)
		var values: PackedFloat64Array = rescuer.owner._soldier_values(int(rescuer.unit))
		if values[15] >= float(exterior.y) + 0.699: break
		if not _shared_step(): advanced = false; break
	var released := InputEventKey.new()
	released.keycode = KEY_DOWN; released.physical_keycode = KEY_DOWN; released.pressed = false
	roundtrip_lab._unhandled_input(released)
	roundtrip_lab.movement_input_enabled = false
	if not advanced or not _settle_released_native_input(rescue_person): return false
	rescuer = _person(rescue_person)
	var patient := _person(roof_person)
	var vehicle: Dictionary = roundtrip_lab.terrain.site.vehicles[keys_by_kind.siege_tower]
	var distance: float = (Vector2(patient.position) - Vector2(rescuer.position)).length() / 64.0
	var source_y := float(rescuer.position.y) / 64.0
	if not _expect(rescuer.cell == exterior and not bool(rescuer.moving) and source_y >= float(exterior.y) + 0.699 and source_y <= float(exterior.y) + 0.701
		and not SiteRuntime.siege_tower_physical_cells(roundtrip_lab.terrain, vehicle).has(rescuer.cell) and distance > 1.3 and distance <= 1.5
		and patient.cell == roof_cell and int(patient.hit) == revision and float(patient.hp) > 0.0 and float(patient.ko) > 0.0
		and is_same(original_holder, patient.holder) and is_same(original_cargo, patient.cargo), "real original key movement reaches the legal exterior margin without moving the central patient", {"distance": distance, "rescuer_cell": rescuer.cell, "rescuer_y": source_y, "patient_cell": patient.cell}): return false
	# The original control switch releases host movement; the original HOLD
	# formation alone selects and performs the real rescue on later slices.
	switched = roundtrip_lab.site_controller._control_family_person(null, roof_person)
	if not _expect(switched.ok and roundtrip_lab.controlled_person_id() == roof_person, "original control returns to the same living KO patient", switched): return false
	recovery_evidence.merge({"rescue_admission_distance": distance, "rescuer_key_source": [exterior.x, exterior.y],
		"rescuer_margin_position": [float(rescuer.position.x) / 64.0, source_y], "rescue_admission": "original same-height fallen occupant within existing 1.5 reach; own wreck domain only"}, true)
	return true

func _bandage_native_fall(revision: int, original_holder: Dictionary, original_cargo: Dictionary) -> bool:
	if not _position_native_rescuer(revision, original_holder, original_cargo): return false
	var rescuer := _person(rescue_person)
	var began := test_shared_steps
	for _tick in range(3600):
		var patient := _person(roof_person)
		if float(patient.hp) <= 0.0: return _expect(false, "original central patient survives until actual rescue", patient)
		if bool(patient.owner.combat_hot_get(int(patient.unit), &"bandaged", false)):
			rescuer = _person(rescue_person)
			var key: String = keys_by_kind.siege_tower
			var vehicle: Dictionary = roundtrip_lab.terrain.site.vehicles[key]
			var distance: float = (Vector2(patient.position) - Vector2(rescuer.position)).length() / 64.0
			if not _expect(patient.cell == roof_cell and int(patient.hit) == revision and float(patient.ko) > 0.0 and float(patient.ko) <= 3600.0
				and float(test_shared_steps - began) * DT >= 4.0 - DT and distance <= 1.5 + 0.0002 and not SiteRuntime.siege_tower_physical_cells(roundtrip_lab.terrain, vehicle).has(rescuer.cell)
				and is_same(original_holder, patient.holder) and is_same(original_cargo, patient.cargo), "real original rescue bandages within actual reach, outside footprint, preserving patient source/revision/items", {"patient_cell": patient.cell, "rescuer_cell": rescuer.cell, "distance": distance, "hp": patient.hp, "ko": patient.ko}): return false
			recovery_evidence.merge({"rescue_action_seconds": float(test_shared_steps - began) * DT, "rescuer_actual_distance": distance,
				"rescuer_actual_cell": [rescuer.cell.x, rescuer.cell.y], "after_rescue_hp": float(patient.hp), "after_rescue_ko_game_seconds": float(patient.ko),
				"bandage_source": "original World HOLD rescue; no hot HP/KO/bandaged setter"}, true)
			return true
		if not _shared_step(): return false
	return _expect(false, "actual original HOLD rescue finishes before the bounded deadline")

func _native_signature() -> Dictionary:
	if store_mode != "native": return {}
	var native: Variant = roundtrip_lab.crowd_site.crowd
	return {"hash": str(native.state_hash()), "blob": native.save_state(), "ids": native.person_ids(), "physical_mask": native.siege_occupancy_mask(PackedInt64Array()), "ground_cells": native.siege_ground_cells()}

func _canonical(state: Dictionary) -> Dictionary:
	var result := {}
	for key: String in ["actors", "armies", "features", "vehicles", "next_vehicle", "next_feature", "next_person_id", "army_next_team", "item_records", "item_definitions", "depot_items", "next_item", "inventory", "ground_loot", "controlled_person_id", "team_supply", "person_supply"]:
		if state.has(key): result[key] = state[key]
	# Compare both sides through the same original JSON number boundary.
	return JSON.parse_string(JSON.stringify(result, "", true, true))

func _roundtrip() -> bool:
	var ui: SiteController = roundtrip_lab.site_controller
	var recovery_before := {}
	if store_mode == "native" and store_case in ["disabled", "wreck"]:
		var patient := _person(roof_person)
		recovery_before = {"hp": float(patient.hp), "ko": float(patient.ko), "hit": int(patient.hit), "bandaged": bool(patient.owner.combat_hot_get(int(patient.unit), &"bandaged", false)), "cell": patient.cell}
		if not _expect(recovery_before.bandaged and float(recovery_before.ko) > 0.0 and patient.cell == roof_cell,
			"saved native fixture retains the actually bandaged original KO patient", recovery_before): return false
	var saved := ui.save_to(current_path)
	if not _expect(saved.ok, "actual Controller capture and Store file write", saved): return false
	var raw := FileAccess.get_file_as_string(current_path)
	var decoded := SiteStore._read(current_path)
	if not _expect(decoded.ok, "actual stored envelope/checksum/decompression read", decoded): return false
	var original: Dictionary = _canonical(decoded.payload.state)
	var native_before := _native_signature()
	var original_data: TerrainData = roundtrip_lab.terrain
	var candidate := SiteStore.load_site(current_path)
	if not _expect(candidate.ok and candidate.data != original_data and roundtrip_lab.terrain == original_data, "actual Store prepares a detached candidate without replacing live owners", candidate): return false
	if not _expect(FileAccess.get_file_as_string(current_path) == raw and _native_signature() == native_before, "candidate read leaves original bytes and native state unchanged"): return false
	if store_mode == "native":
		if not _expect(candidate.has("crowd_native") and candidate.crowd_native.save_state() == native_before.blob and str(candidate.crowd_native.state_hash()) == str(native_before.hash), "same-mask candidate load preserves every original native byte and gameplay hash"): return false
	var committed := ui.load_from(current_path)
	if not _expect(committed.ok and roundtrip_lab.terrain == committed.get("data") and roundtrip_lab.terrain != original_data, "original Controller atomically commits its valid candidate", committed): return false
	var difference := _first_difference(original, _canonical(roundtrip_lab.terrain.site), "saved")
	if not _expect(difference.is_empty(), "all persisted original people/holders/cargo/vehicles/parts/allocators survive", difference): return false
	if not _expect(_native_signature() == native_before, "native blob, identity order and gameplay hash are equal after actual Controller load"): return false
	if not recovery_before.is_empty():
		var patient := _person(roof_person)
		var restored := {"hp": float(patient.hp), "ko": float(patient.ko), "hit": int(patient.hit), "bandaged": bool(patient.owner.combat_hot_get(int(patient.unit), &"bandaged", false)), "cell": patient.cell}
		if not _expect(restored == recovery_before, "actual load preserves the same rescued native HP/KO/bandaged/revision/source", restored): return false
		recovery_evidence["saved_and_loaded_hot"] = {"hp": restored.hp, "ko": restored.ko, "hit": restored.hit, "bandaged": restored.bandaged, "cell": [patient.cell.x, patient.cell.y]}
	for identity: int in original_ids:
		if not _expect(not _person(identity).is_empty(), "same original person is queryable after load", identity): return false
	if store_case == "stable":
		var vehicle: Dictionary = roundtrip_lab.terrain.site.vehicles[keys_by_kind.ballista]
		if not _expect(vehicle.crew_slots == {"0": original_ids[1], "1": original_ids[2]} and int(vehicle.operator_id) == original_ids[1] and roundtrip_lab.site_controller.vehicles.crew_ready(vehicle), "crew remains original authority with stable actual stations"): return false
		if store_mode == "native":
			for identity: int in vehicle.crew_slots.values():
				var person := _person(identity)
				var marks: PackedInt64Array = person.owner.native_siege_state(int(person.unit))
				if not _expect(marks.size() == 8 and int(marks[0]) == 1 and int(marks[2]) < 0 and int(marks[3]) == 0, "stable native crew mark rebuilt from original Site reference", marks): return false
	test_roundtrips += 1
	return true

func _native_crew_snapshot(native: Object) -> Dictionary:
	var ids: PackedInt64Array = native.call("person_ids")
	var marks: Array[PackedInt64Array] = []
	for index in range(ids.size()): marks.append(native.call("siege_person_state", index))
	# Exact blob and gameplay hash include original native clocks; no stats()
	# call here, because that diagnostic changes serialized reporting counters.
	return {"hash": str(native.call("state_hash")), "blob": native.call("save_state"), "ids": ids,
		"terrain": native.call("terrain_state"), "physical_mask": native.call("siege_occupancy_mask", PackedInt64Array()),
		"ground_cells": native.call("siege_ground_cells"), "crew_marks": marks}

func _crew_source_unchanged(source: Dictionary, expected_native: Dictionary, label: String) -> bool:
	var data: TerrainData = roundtrip_lab.terrain
	var clocks := [data.site.minute, data.site.phase, roundtrip_lab._action_time_remainder, roundtrip_lab._exchange_phase, roundtrip_lab._exchange_round]
	if not _expect(data == source.data and roundtrip_lab.army == source.army and roundtrip_lab.crowd_site == source.crowd
		and roundtrip_lab.crowd_site.crowd == source.native and JSON.stringify(data.site, "", true, true) == source.site
		and clocks == source.clocks and _native_crew_snapshot(source.native) == expected_native
		and FileAccess.get_file_as_string(current_path) == source.file, "crew refusal preserves actual scene/native clocks/navigation/crew and source file: " + label): return false
	for saved: Dictionary in source.handles:
		var person: Dictionary = _person(int(saved.id))
		if not _expect(person.owner == saved.owner and is_same(person.holder, saved.holder) and is_same(person.cargo, saved.cargo), "crew refusal preserves original person holder/cargo objects: " + label): return false
	return true

func _native_crew_refusal_contract() -> bool:
	if store_mode != "native" or store_case != "stable": return true
	if not _expect(test_roundtrips == 1, "native crew fault checks follow the first actual good Store/Controller roundtrip"): return false
	var data: TerrainData = roundtrip_lab.terrain
	var native: Object = roundtrip_lab.crowd_site.crowd
	var baseline: Dictionary = _native_crew_snapshot(native)
	var source := {"data": data, "army": roundtrip_lab.army, "crowd": roundtrip_lab.crowd_site, "native": native,
		"site": JSON.stringify(data.site, "", true, true), "file": FileAccess.get_file_as_string(current_path),
		"clocks": [data.site.minute, data.site.phase, roundtrip_lab._action_time_remainder, roundtrip_lab._exchange_phase, roundtrip_lab._exchange_round],
		"handles": _live_identity_handles()}
	var ids: PackedInt64Array = baseline.ids
	var expected_indices := PackedInt32Array()
	for vehicle: Dictionary in data.site.vehicles.values():
		for identity: int in vehicle.get("crew_slots", {}).values():
			var index: int = ids.find(identity)
			if not _expect(index >= 0 and not expected_indices.has(index), "fault fixture uses the exact existing original crew ID set", identity): return false
			expected_indices.append(index)
	var extra_index: int = ids.find(original_ids[0])
	if not _expect(expected_indices.size() == 2 and extra_index >= 0 and not expected_indices.has(extra_index)
		and not baseline.blob.is_empty() and bool(native.call("validate")), "real stable native crew and a real noncrew member are available"): return false
	var missing: PackedInt32Array = expected_indices.duplicate()
	missing.remove_at(0)
	var extra: PackedInt32Array = expected_indices.duplicate()
	extra.append(extra_index)
	var specimens: Array[Dictionary] = [{"label": "missing_crew_flag", "indices": missing}, {"label": "extra_noncrew_flag", "indices": extra}]
	for specimen: Dictionary in specimens:
		var label: String = str(specimen.label)
		# Fault injection uses only the existing native owner interface. Snapshot
		# AFTER injection, so validation is forbidden from repairing this state.
		if not _expect(bool(native.call("set_siege_crew_members", specimen.indices)), "original owner applies live flag fault: " + label): return false
		var fault: Dictionary = _native_crew_snapshot(native)
		if not _expect(fault.hash != baseline.hash and fault.crew_marks != baseline.crew_marks and fault.blob == baseline.blob
			and bool(native.call("validate")), "live fault changes derived flags while preserving a valid original blob: " + label): return false
		var rejected: Dictionary = SiteStore.save(data, current_path, native)
		if not _expect(rejected == SiteRuntime.fail("INVALID_CROWD", "原生操作班旗標與原 Site 操作人集合不符"),
			"full Store.save rejects the exact live crew mismatch: " + label, rejected): return false
		if not _crew_source_unchanged(source, fault, "live " + label): return false
		if not _expect(bool(native.call("set_siege_crew_members", expected_indices)) and _native_crew_snapshot(native) == baseline,
			"only the test's original owner interface restores live flags: " + label): return false
		if not _crew_source_unchanged(source, baseline, "restored live " + label): return false
		native_crew_rejections += 1
		var candidate: Dictionary = SiteStore.load_site(current_path, Callable(), clampi(OS.get_processor_count(), 1, 8))
		if not _expect(candidate.ok and candidate.has("crowd_native") and candidate.data != data and candidate.crowd_native != native,
			"full original loader prepares a real detached positive candidate: " + label, candidate): return false
		var detached: Object = candidate.crowd_native
		var detached_baseline: Dictionary = _native_crew_snapshot(detached)
		var candidate_state: String = JSON.stringify(candidate.data.site, "", true, true)
		if not _expect(detached_baseline == baseline and bool(detached.call("set_siege_crew_members", specimen.indices)),
			"original owner injects the same fault into the actual detached result: " + label): return false
		var detached_fault: Dictionary = _native_crew_snapshot(detached)
		if not _expect(detached_fault.hash != detached_baseline.hash and detached_fault.crew_marks != detached_baseline.crew_marks
			and detached_fault.blob == detached_baseline.blob and bool(detached.call("validate")), "detached snapshot is taken after a valid flag-only fault: " + label): return false
		var candidate_rejected: Dictionary = SiteStore._validate_state(candidate.data, candidate.data.site, clampi(OS.get_processor_count(), 1, 8), detached)
		if not _expect(candidate_rejected == SiteRuntime.fail("INVALID_CROWD", "原生操作班旗標與原 Site 操作人集合不符"),
			"full supplied-candidate Store boundary rejects before navigation restoration: " + label, candidate_rejected): return false
		if not _expect(_native_crew_snapshot(detached) == detached_fault and JSON.stringify(candidate.data.site, "", true, true) == candidate_state,
			"supplied candidate refusal does not repair flags or change hash/blob/navigation/crew: " + label): return false
		if not _crew_source_unchanged(source, baseline, "detached " + label): return false
		if not _expect(bool(detached.call("set_siege_crew_members", expected_indices)), "test original owner alone restores detached flags: " + label): return false
		var restored: Dictionary = SiteStore._validate_state(candidate.data, candidate.data.site, clampi(OS.get_processor_count(), 1, 8), detached)
		if not _expect(restored.ok and _native_crew_snapshot(detached) == detached_baseline
			and JSON.stringify(candidate.data.site, "", true, true) == candidate_state, "restored actual supplied candidate passes full original boundary: " + label, restored): return false
		if not _crew_source_unchanged(source, baseline, "restored detached " + label): return false
		native_crew_rejections += 1
	return _expect(native_crew_rejections == 4, "both live and detached crew faults completed all four exact refusal/restoration checks")

func _live_identity_handles() -> Array[Dictionary]:
	var handles: Array[Dictionary] = []
	for identity: int in original_ids:
		var person := _person(identity)
		handles.append({"id": identity, "owner": person.owner, "holder": person.holder, "cargo": person.cargo})
	return handles

func _write_bad(path: String, mutate: Callable) -> bool:
	var decoded := SiteStore._read(current_path)
	if not _expect(decoded.ok, "valid baseline decoded for independent corrupt-file fixture"): return false
	var payload: Dictionary = decoded.payload
	mutate.call(payload.state)
	var body := SiteStore._stringify_crowd_payload(payload) if payload.state.has("crowd") else JSON.stringify(payload, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _expect(file != null, "isolated corrupt candidate file can be written", path): return false
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()
	return true

func _reject_bad(label: String, mutate: Callable, code: String = "CORRUPT_SAVE") -> bool:
	var path := save_folder.path_join("bad_" + label + ".json")
	if not _write_bad(path, mutate): return false
	var data: TerrainData = roundtrip_lab.terrain
	var army: TerrainArmy = roundtrip_lab.army
	var crowd: Variant = roundtrip_lab.crowd_site
	var site_before := JSON.stringify(data.site, "", true, true)
	var native_before := _native_signature()
	var handles := _live_identity_handles()
	var raw := FileAccess.get_file_as_string(current_path)
	# Exercise the full original candidate loader before Controller preflight.
	var store_rejected: Dictionary = SiteStore.load_site(path, Callable(), clampi(OS.get_processor_count(), 1, 8))
	if not _expect(not code.is_empty() and not store_rejected.ok and str(store_rejected.get("code", "")) == code, "full original Store rejects the semantic candidate: " + label, store_rejected): return false
	var semantic_message: String = str(store_rejected.get("message", ""))
	if not _expect(not semantic_message.is_empty(), "full Store supplies a semantic rejection reason: " + label, store_rejected): return false
	if not _expect(roundtrip_lab.terrain == data and roundtrip_lab.army == army and roundtrip_lab.crowd_site == crowd and JSON.stringify(data.site, "", true, true) == site_before and _native_signature() == native_before and FileAccess.get_file_as_string(current_path) == raw, "detached semantic rejection preserves every original owner/native byte/valid file: " + label): return false
	var rejected: Dictionary = roundtrip_lab.site_controller.load_from(path)
	if not _expect(not rejected.ok and str(rejected.get("code", "")) == code and str(rejected.get("message", "")) == semantic_message + "；自動保存已暫停，原檔保留", "Controller rejects the same original semantic code/reason: " + label, rejected): return false
	if not _expect(roundtrip_lab.terrain == data and roundtrip_lab.army == army and roundtrip_lab.crowd_site == crowd and JSON.stringify(data.site, "", true, true) == site_before and _native_signature() == native_before and FileAccess.get_file_as_string(current_path) == raw, "failed load preserves every original owner/native byte/valid file: " + label): return false
	for saved: Dictionary in handles:
		var person := _person(int(saved.id))
		if not _expect(person.owner == saved.owner and is_same(person.holder, saved.holder) and is_same(person.cargo, saved.cargo), "failed load preserves actual person holder/cargo objects: " + label): return false
	test_rejections += 1
	return true

func _reject_bad_save(tower: String) -> bool:
	var data: TerrainData = roundtrip_lab.terrain
	var original := JSON.stringify(data.site, "", true, true)
	var native_before := _native_signature()
	# Build only a valid detached baseline, then make its source record malformed.
	# Store must reject before any invalid pose is passed to navigation rebuild.
	var candidate := SiteEnvironment.navigation_for_state(data, data.site.duplicate(true))
	candidate.site.vehicles[tower].deployed_pose = []
	var before := FileAccess.get_file_as_string(current_path)
	var rejected := SiteStore.save(candidate, current_path)
	if not _expect(not rejected.ok and str(rejected.code) == "CORRUPT_SAVE", "Store rejects malformed source pose before projecting candidate terrain", rejected): return false
	if not _expect(FileAccess.get_file_as_string(current_path) == before and JSON.stringify(data.site, "", true, true) == original and _native_signature() == native_before, "failed Store write preserves valid file and all live original owners"): return false
	test_rejections += 1
	return true

func _reject_invalid_source_hp(vehicle_key: String, value: float, label: String) -> bool:
	var data: TerrainData = roundtrip_lab.terrain
	var original := JSON.stringify(data.site, "", true, true)
	var native_before := _native_signature()
	var handles := _live_identity_handles()
	var candidate := SiteEnvironment.navigation_for_state(data, data.site.duplicate(true))
	candidate.site.vehicles[vehicle_key].hp = value
	var raw := FileAccess.get_file_as_string(current_path)
	var rejected: Dictionary = SiteStore.save(candidate, current_path)
	if not _expect(not rejected.ok and str(rejected.code) == "CORRUPT_SAVE", "direct non-finite source HP rejected before JSON projection: " + label, rejected): return false
	if not _expect(FileAccess.get_file_as_string(current_path) == raw and JSON.stringify(data.site, "", true, true) == original and _native_signature() == native_before, "invalid source HP preserves original scene/native bytes/valid file: " + label): return false
	for saved: Dictionary in handles:
		var person := _person(int(saved.id))
		if not _expect(person.owner == saved.owner and is_same(person.holder, saved.holder) and is_same(person.cargo, saved.cargo), "invalid source HP preserves actual original holder objects: " + label): return false
	test_rejections += 1
	return true

func _bad_cases() -> bool:
	if keys_by_kind.has("siege_tower"):
		var tower: String = keys_by_kind.siege_tower
		if not _reject_bad_save(tower): return false
		for specimen: Dictionary in [
			{"label": "pose_array", "mutate": func(state: Dictionary) -> void: state.vehicles[tower].deployed_pose = []},
			{"label": "pose_missing", "mutate": func(state: Dictionary) -> void: state.vehicles[tower].erase("deployed_pose")},
			{"label": "pose_fraction", "mutate": func(state: Dictionary) -> void: state.vehicles[tower].deployed_pose = {"version": 1, "cell": state.vehicles[tower].cell, "facing": [1, 0], "level": 0.5}},
			{"label": "pose_mismatch", "mutate": func(state: Dictionary) -> void: state.vehicles[tower].deployed_pose = {"version": 1, "cell": int(state.vehicles[tower].cell) + 1, "facing": [1, 0], "level": 0}},
			{"label": "pose_bad_axis", "mutate": func(state: Dictionary) -> void: state.vehicles[tower].deployed_pose = {"version": 1, "cell": state.vehicles[tower].cell, "facing": [1, 1], "level": 0}},
			{"label": "pose_extra_authority", "mutate": func(state: Dictionary) -> void: state.vehicles[tower].deployed_pose = {"version": 1, "cell": state.vehicles[tower].cell, "facing": [1, 0], "level": 0, "heights": {"1": 2}}}]:
			if not _reject_bad(str(specimen.label), specimen.mutate, "CORRUPT_SAVE"): return false
	if store_case == "stable":
		var ballista: String = keys_by_kind.ballista
		for specimen: Dictionary in [
			{"label": "damage_flag_missing", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].erase("ever_hp_damaged")},
			{"label": "damage_flag_non_bool", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].ever_hp_damaged = 0},
			{"label": "damage_flag_hp_conflict", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].hp = 139.0},
			{"label": "hp_negative", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].hp = -1.0},
			{"label": "hp_above_definition", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].hp = 141.0},
			{"label": "unknown_kind", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].kind = "unregistered_siege_engine"},
			{"label": "unknown_vehicle_version", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].vehicle_version = 4},
			{"label": "unknown_definition_version", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].definition_version = 2},
			{"label": "illegal_facing", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].facing = [1, 1]},
			{"label": "illegal_footprint_edge", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].cell = roundtrip_lab.terrain.size.x * roundtrip_lab.terrain.size.y - 1},
			{"label": "footprint_overlap_vehicle", "mutate": func(state: Dictionary) -> void: state.vehicles[keys_by_kind.ram].cell = state.vehicles[ballista].cell},
			{"label": "unknown_cargo_resource", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].cargo["unregistered_resource"] = 1},
			{"label": "wrong_ammunition", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].cargo["siege_stone"] = 1},
			{"label": "ammunition_capacity", "mutate": func(state: Dictionary) -> void: state.vehicles[ballista].cargo["siege_bolt"] = 21},
			{"label": "duplicate_original_holder", "mutate": func(state: Dictionary) -> void: state.vehicles[keys_by_kind.ram].holder.holder = state.vehicles[ballista].holder.holder},
			{"label": "duplicate_role_two_vehicles", "mutate": func(state: Dictionary) -> void: state.vehicles[keys_by_kind.ram].crew_slots["0"] = original_ids[1]; state.vehicles[keys_by_kind.ram].operator_id = original_ids[1]}]:
			if not _reject_bad(str(specimen.label), specimen.mutate): return false
		if not _reject_invalid_source_hp(ballista, NAN, "NaN"): return false
		if not _reject_invalid_source_hp(ballista, INF, "positive infinity"): return false
		if not _reject_invalid_source_hp(ballista, -INF, "negative infinity"): return false
		if store_mode == "gd":
			# Derive a real ordinary deployment through original APIs. No actor is
			# moved or cloned; a detached candidate later restores one saved claim.
			var ui: SiteController = roundtrip_lab.site_controller
			var team: TerrainArmy = roundtrip_lab.army
			var requester := team.combat_identity(team.current_commander)
			var vehicle: Dictionary = roundtrip_lab.terrain.site.vehicles[ballista]
			var released := ui.vehicles.unassign_crew(ballista, 0, requester, true)
			if not _expect(released.ok and vehicle.crew_slots.is_empty(), "slot-conflict fixture releases original stopped crew through original owner", released): return false
			var ordered := team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(30, 25), -1, Vector2i.RIGHT, "square")
			if not _expect(ordered.ok and team._combat_deployment_plan != null, "original public MOVE creates valid ordinary deployment", ordered): return false
			var ordinary: Dictionary = TerrainArmy._serialize_deployment_plan(team._combat_deployment_plan)
			var crew_id := original_ids[1]
			var crew_key := str(crew_id)
			if not _expect(int(ordinary.requested_count) == 3 and ordinary.member_slot_map.has(crew_key) and ordinary.member_role_map.has(crew_key), "actual original MOVE gave the future crew a real ordinary slot", ordinary): return false
			for slot in range(2):
				var assigned := ui.vehicles.assign_crew(ballista, original_ids[slot + 1], str(slot), requester, true)
				if not _expect(assigned.ok, "original owner reassigns the same stopped people to crew", assigned): return false
			ui.vehicles.update_siege(0.001)
			if not _expect(ui.vehicles.crew_ready(vehicle) and team._combat_deployment_plan.requested_count == 3 and not team._combat_deployment_plan.member_slot_map.has(crew_id), "valid baseline retains real geometry and excludes the original crew claim"): return false
			var prior_path := current_path
			var prior_bytes := FileAccess.get_file_as_string(prior_path)
			var baseline_path := save_folder.path_join("valid_ordinary_slot_baseline.json")
			var saved := ui.save_to(baseline_path)
			if not _expect(saved.ok, "independent valid ordinary-slot baseline saves without adding a roundtrip", saved): return false
			var prepared := SiteStore.load_site(baseline_path)
			var decoded := SiteStore._read(baseline_path)
			if not _expect(prepared.ok and decoded.ok, "full original Store accepts the untouched independent baseline", prepared): return false
			var restore_claim := func(state: Dictionary) -> void:
				for saved_team: Dictionary in state.armies:
					if int(saved_team.team_id) != team.team_id: continue
					var plan: Dictionary = saved_team.combat_deployment_plan
					plan.member_slot_map[crew_key] = ordinary.member_slot_map[crew_key].duplicate()
					plan.member_role_map[crew_key] = ordinary.member_role_map[crew_key]
					if ordinary.member_slot_locked.has(crew_key): plan.member_slot_locked[crew_key] = ordinary.member_slot_locked[crew_key]
					for field: String in ["queue_member_ids", "pending_platform_member_ids", "admitted_platform_member_ids", "settled_platform_member_ids", "settled_queue_member_ids", "ever_admitted_platform_member_ids"]:
						if ordinary[field].has(crew_id) and not plan[field].has(crew_id): plan[field].append(crew_id)
			var bad_state: Dictionary = decoded.payload.state.duplicate(true)
			restore_claim.call(bad_state)
			var bad_team: Dictionary = {}
			for saved_team: Dictionary in bad_state.armies:
				if int(saved_team.team_id) == team.team_id: bad_team = saved_team
			var excluded := {original_ids[1]: true, original_ids[2]: true}
			if not _expect(not bad_team.is_empty() and SiteStore._valid_combat_movement_snapshot(prepared.data, bad_team, {}, excluded) and SiteStore._validate_armies(prepared.data, bad_state, true).ok, "bad candidate retains valid original movement shape, geometry and people; only crew role conflicts"): return false
			var role_guard := SiteStore._validate_vehicles(prepared.data, bad_state, true)
			if not _expect(role_guard == SiteRuntime.fail("CORRUPT_SAVE", "攻城操作人仍占一般隊形槽位／租約"), "existing siege validator identifies the specific ordinary-slot role conflict", role_guard): return false
			current_path = baseline_path
			var rejected := _reject_bad("crew_ordinary_slot_semantic", restore_claim, "CORRUPT_SAVE")
			current_path = prior_path
			if not rejected: return false
			if not _expect(FileAccess.get_file_as_string(prior_path) == prior_bytes and test_roundtrips == 1, "extra positive save preserves earlier valid file and original two-roundtrip accounting"): return false
		if not _reject_bad("crew_missing_original", func(state: Dictionary) -> void: state.vehicles[ballista].crew_slots["1"] = 2147483647): return false
		if not _reject_bad("crew_duplicate", func(state: Dictionary) -> void: state.vehicles[ballista].crew_slots["1"] = state.vehicles[ballista].crew_slots["0"]): return false
		if not _reject_bad("crew_owner_team", func(state: Dictionary) -> void: state.vehicles[ballista].team_id = 999999): return false
		if not _reject_bad("ladder_pending_without_workers", func(state: Dictionary) -> void: state.features[ladder_key].ladder.pending = "deploy", "CORRUPT_SAVE"): return false
	return true

func _loaded_surface() -> bool:
	if store_case not in ["deployed", "disabled", "wreck"]: return true
	var person := _person(roof_person)
	var hp := float(person.hp)
	var hit := int(person.hit)
	var key: String = keys_by_kind.siege_tower
	if not _expect(person.cell == roof_cell and roundtrip_lab.terrain.effective_height(roof_cell) == (2 if store_case == "deployed" else 0), "loaded original person uses the saved tower surface purpose"): return false
	if not _shared_step(): return false
	person = _person(roof_person)
	if not _expect(person.cell == roof_cell and is_equal_approx(float(person.hp), hp) and int(person.hit) == hit, "first real post-load slice does not replay a fall/revision"): return false
	if store_case == "deployed": return true
	# Original four-hour KO/get-up timer advances through the formal shared
	# clock at the existing UI's maximum 4x speed; no hot timer is rewritten.
	while roundtrip_lab.simulation_speed < 4.0: roundtrip_lab.change_simulation_speed(1)
	var wake_began := test_shared_steps
	for _slice in range(9600):
		person = _person(roof_person)
		if person.owner.combat_can_act(int(person.unit)): break
		if not _shared_step(): return false
	while roundtrip_lab.simulation_speed > 1.0: roundtrip_lab.change_simulation_speed(-1)
	person = _person(roof_person)
	if not _expect(float(person.hp) > 0.0 and person.owner.combat_can_act(int(person.unit)) and person.cell == roof_cell and int(person.hit) == hit,
		"original saved fallen person naturally wakes alive at its saved central source/revision"): return false
	if store_mode == "native": recovery_evidence.merge({"wake_action_seconds": float(test_shared_steps - wake_began) * DT, "awake_hp": float(person.hp), "awake_hit": int(person.hit), "maximum_original_game_speed": 4.0}, true)
	hp = float(person.hp)
	var goal := Vector2i(37, 41)
	for _edge in range(12):
		person = _person(roof_person)
		if person.cell == goal: break
		var source: Vector2i = person.cell
		if store_mode == "native":
			if not _expect(roundtrip_lab.crowd_site.siege_approach_step(roof_person, goal), "native original person reserves next legal wreck-exit edge"): return false
		else:
			var team: TerrainArmy = person.owner
			var next := team._common_order_route_step(int(person.unit), goal, 0)
			if not _expect(next != TerrainArmy.INVALID_CELL and team._reserve_combat_step(int(person.unit), next, 0, false, false, false, goal), "ordinary original person reserves next legal wreck-exit edge"): return false
		for _slice in range(480):
			if not _shared_step(): return false
			person = _person(roof_person)
			if not bool(person.moving): break
		if not _expect(not bool(person.moving) and absi(person.cell.x - source.x) + absi(person.cell.y - source.y) == 1 and is_equal_approx(float(person.hp), hp), "exit is one actual original step with no repeated damage"): return false
	person = _person(roof_person)
	if not _expect(person.cell == goal, "central original occupant reaches outside by multiple original edges"): return false
	if store_mode == "native": recovery_evidence["actual_exit_cell"] = [person.cell.x, person.cell.y]
	return _expect(roundtrip_lab.site_controller.vehicles.blocks_person_step(roof_person, goal, goal, Vector2i(38, 41), roof_cell), "exited original cannot reenter a retained disabled/wreck tower")

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: test_failed = true; _report(); printerr("SIEGE STORE FAIL: deadline"); quit(3))
	if not _preflight() or not _new_lab() or not _fixture_case(): return
	if not _roundtrip(): return
	if not _native_crew_refusal_contract() or not _bad_cases() or not _loaded_surface(): return
	if store_case == "stable":
		var feature: Dictionary = roundtrip_lab.terrain.site.features[ladder_key]
		# A second explicit stable fixture covers the deployed saved projection;
		# the WorkTeam 12/8-second action contract is independently exercised.
		feature.ladder.phase = "deployed"
		SiteEnvironment.rebuild_indexes(roundtrip_lab.terrain)
		if not _expect(SiteRuntime.validate_feature_layout(roundtrip_lab.terrain, feature).ok and not SiteRuntime.feature_geometry(roundtrip_lab.terrain, feature).heights.is_empty(), "deployed original ladder saved-state fixture is valid"): return
		if not _roundtrip(): return
	if not _expect(test_roundtrips == (2 if store_case == "stable" else 1), "every requested actual roundtrip completed"): return
	if not _expect(native_crew_rejections == (4 if store_mode == "native" and store_case == "stable" else 0), "all requested native crew fault cases completed without skipping"): return
	_report()
	roundtrip_lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_STORE_P5_P6_PASS: ", store_mode, " / ", store_case, " / ", test_roundtrips, " actual roundtrips / ", test_rejections, " atomic rejections / ", native_crew_rejections, " native crew refusals / ", test_checks, " checks")
	quit(0)
