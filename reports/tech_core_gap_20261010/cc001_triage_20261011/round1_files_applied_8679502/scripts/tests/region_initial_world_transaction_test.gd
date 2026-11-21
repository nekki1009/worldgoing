extends SceneTree
## Original formal SceneTree + accepted RegionData fixed geographic source +
## original Controller/Slot/Store first generation. IO faults subclass ONLY the
## original Slot IO methods. No fake bind receipts, clocks, people or proof flags.
## The geographic source is a checksummed synthetic fixture, not Taiwan/GPU/G06.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Artisans = preload("res://scripts/terrain_lab/site_technology_artisans.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Policy = preload("res://scripts/terrain_lab/site_technology_policy.gd")
const SCENE := "res://scenes/terrain_lab/TerrainLab.tscn"
const SLOT := "main"
const START := Vector2i.ZERO
var checks := 0
var failures: Array[String] = []
var report: Dictionary = {}
var root_path := ""
var manifest_path := ""
var case_sequence := 0
var deadline := 0
var finished := false
var labs: Array[TerrainLab] = []
var birth_counts: Dictionary = {}

class FaultSlot:
	extends RegionSaveSlot
	var fault := ""
	var remaining := 1
	var fault_count := 0
	var save_body_ids: Array[int] = []
	var write_paths: Array[String] = []
	func _write_new_document(path: String, payload: Dictionary) -> Dictionary:
		write_paths.append(path)
		var selected := fault in ["pending", "pending_tmp"] and path.ends_with("/manifest.pending.json") or fault == "commit" and path.contains("/commits/") or fault == "receipt" and path.ends_with("/manifest.initialized.json")
		if selected and remaining > 0:
			remaining -= 1
			fault_count += 1
			if fault == "pending_tmp":
				# A genuine interrupted write, retained on disk as failure evidence.
				var temporary := ProjectSettings.globalize_path(path + ".tmp")
				var made := DirAccess.make_dir_recursive_absolute(temporary.get_base_dir())
				if made != OK: return fail("SAVE_IO", "Injected pending temporary mkdir")
				var output := FileAccess.open(temporary, FileAccess.WRITE)
				if output == null: return fail("SAVE_IO", "Injected pending temporary open")
				output.store_string("{\"payload\":\"interrupted")
				output.flush()
				output.close()
			return fail("SAVE_IO", "Injected original " + fault + " IO failure")
		return super._write_new_document(path, payload)
	func _save_checked(data: TerrainData, site: Vector2i, path: String) -> Dictionary:
		save_body_ids.append(data.get_instance_id())
		if fault == "site" and remaining > 0:
			remaining -= 1
			fault_count += 1
			return fail("SAVE_IO", "Injected original SiteStore candidate IO failure")
		return super._save_checked(data, site, path)
	func _finish_initial_manifest() -> Dictionary:
		if fault == "manifest" and remaining > 0:
			remaining -= 1
			fault_count += 1
			return fail("SAVE_IO", "Injected original first manifest IO failure")
		return super._finish_initial_manifest()

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish("deadline")
	return false

func _check(value: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if not value:
		failures.append(message)
		push_error("REGION_INITIAL_WORLD_TRANSACTION_FAIL: " + message + " " + str(detail))
	return value

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path := root_path.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "Fixture asset can be written", name): return {}
	file.store_buffer(bytes)
	file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

func _fixed_source() -> RegionData:
	root_path = "res://.godot-temp/t7_initial_world_transaction/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_path)) == OK, "Isolated fixed-source directory exists"): return null
	var summary := PackedByteArray()
	summary.resize(4)
	summary.fill(2)
	var summary_record := _asset("summary.u8", summary)
	if summary_record.is_empty(): return null
	summary_record.merge({"size": [2, 2], "site_origin": [0, 0], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var elevation := PackedByteArray()
	var levels := PackedByteArray()
	var water := PackedByteArray()
	# 22x22 posts at 20 m from -20 m: a margin past every site edge so the adapter's
	# 2 m edge halo samples real fixture terrain instead of missing neighbourhood data.
	elevation.resize(22 * 22 * 2)
	levels.resize(22 * 22)
	water.resize(22 * 22)
	for index: int in range(22 * 22):
		elevation.encode_s16(index * 2, 40)
		levels[index] = 2
	var height_record := _asset("birth.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record := _asset("birth.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record := _asset("birth.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	if height_record.is_empty() or level_record.is_empty() or water_record.is_empty(): return null
	height_record.merge({"id": "birth_plain", "origin": [-20, -20], "size": [22, 22], "spacing_m": 20,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256,
			"water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "t7-original-first-generation-v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Original T7 first-generation fixed-source fixture"}]}
	manifest_path = root_path.path_join("manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if not _check(file != null, "Original geographic manifest is written"): return null
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	var source := RegionData.new()
	if not _check(source.load_manifest(manifest_path).ok, "Real RegionData loader admits the complete checksummed fixed source"): return null
	return source

func _world(label: String) -> String:
	case_sequence += 1
	return "t7_%s_%d_%d_%d" % [label, OS.get_process_id(), Time.get_ticks_usec(), case_sequence]

func _freeze(lab: TerrainLab) -> void:
	lab.set_process(false)
	lab.set_process_input(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)

func _source_lab(label: String) -> TerrainLab:
	var packed := load(SCENE) as PackedScene
	if not _check(packed != null, "Original formal TerrainLab scene exists"): return null
	var lab := packed.instantiate() as TerrainLab
	if not _check(lab != null, "Original scene instantiates its real Lab"): return null
	lab.restore_only = true # Build the original shells without implicit startup IO.
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	labs.append(lab)
	birth_counts[lab.get_instance_id()] = 0
	lab.child_entered_tree.connect(_record_birth.bind(lab.get_instance_id()))
	var old := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 18373, {"size": Vector2i(32, 32)})
	Env.initialize(old, "t7_old_" + label)
	lab.bind_terrain(old)
	if not _check(lab._region_bound_data == old, "Original source owners bind before replacement"): return null
	lab.character.hp = 73.0
	lab.character.faction_id = 5
	lab.character.combat_ability = 84.0
	lab.character.technology = Technology.learned_candidate({}, "F07")
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(captured.ok, "Old original source captures its actual pre-existing body", captured): return null
	lab.restore_only = false # The real first-world consumer must issue a live receipt.
	lab.site_controller.save_root = root_path.path_join("archives_" + label)
	_freeze(lab)
	return lab

func _record_birth(child: Node, owner_id: int) -> void:
	if str(child.name) in ["InitialArtisanBirthCandidate", "InitialWorldStarterCandidate"]:
		birth_counts[owner_id] = int(birth_counts[owner_id]) + 1

func _facts(state: Dictionary) -> String:
	var facts := {"actors": state.get("actors", {}), "armies": state.get("armies", []),
		"item_records": state.get("item_records", {}), "next_item": state.get("next_item"),
		"next_person_id": state.get("next_person_id"), "army_next_team": state.get("army_next_team"),
		"initial_scenario": state.get("initial_scenario", {}), "technology_artisans": state.get("technology_artisans", {})}
	# JSON has one numeric domain; compare whole-number saved normalization
	# consistently while retaining every actual original body/item field.
	return JSON.stringify(JSON.parse_string(JSON.stringify(facts, "", true, true)), "", true, true)

func _verify_born(data: TerrainData, scenario: String, world_id: String) -> bool:
	var state: Dictionary = data.site
	var count := 0 if scenario.is_empty() else (1 if scenario == Artisans.PRIMARY else 3)
	if not _check(state.get("actors", {}).size() == 1 and int(state.get("controlled_person_id", -1)) == 1, "One true fresh original starter controls the new namespace"): return false
	var actor: Dictionary = state.actors.player
	_check(int(actor.person_id) == 1 and float(actor.hp) == 100.0 and int(actor.faction_id) == 0 and float(actor.combat_ability) == 50.0 and actor.get("technology", {}).is_empty(), "Old hp/faction/ability/F07 do not leak into the genuinely fresh original starter")
	_check(state.get("armies", []).size() == count and not state.has("family") and not state.has("technology_artisans"), "Exactly the original finite empty-policy population; no family or skill receipt")
	var identities := {1: true}
	for team: Dictionary in state.get("armies", []):
		_check(team.units.size() == 5 and int(team.combat_order) == TerrainArmy.CombatOrder.HOLD, "Each selected original team has five idle real born people")
		for row: Dictionary in team.units:
			_check(not identities.has(int(row.person_id)) and int(row.person_id) >= 2 and row.get("technology", {}).is_empty(), "Every bounded NPC retains one distinct unlearned original body")
			identities[int(row.person_id)] = true
			_check(row.get("item_state", {}).get("holder") == "person:" + str(row.person_id), "Born NPC item holder is the original actual person")
	_check(int(state.next_person_id) == count * 5 + 2 and int(state.army_next_team) == count + 1, "True birth advances original person/team allocation exactly once")
	var policy: Dictionary = Policy.candidate(state.world_pin)
	_check(policy.ok and policy.policy.categories.is_empty() and str(state.world_pin.world_instance_id) == world_id, "Original World/Site geographic pin freezes the empty release policy")
	_check(not state.has("initial_scenario") if scenario.is_empty() else state.get("initial_scenario") == {"version": 1, "scenario_id": scenario, "world_id": world_id}, "Only the explicit original scenario has its matching one-time persisted selection")
	_check(Store._validate_actors(data, state).ok and Store._validate_armies(data, state, true).ok and Store._validate_items(data, state).ok and Store._validate_person_allocator(state).ok, "Original body/item/allocator validators admit the full first-generation cold population")
	return true

func _cold_reopen(source: RegionData, world_id: String, scenario: String, expected_facts: String) -> Dictionary:
	var reopened := RegionSaveSlot.new()
	var opened: Dictionary = reopened.open_map(source, world_id, SLOT)
	if not _check(opened.ok, "Original Slot reopens its real first-generation manifest", opened): return {}
	_check(int(reopened._marker.get("generation", -1)) == 1 and not reopened.initialization_pending(), "Completed creation cold reopen selects exactly generation one with no birth authority")
	var path := reopened.site_path(START)
	var digest := FileAccess.get_sha256(path)
	var loaded: Dictionary = reopened.open_site(START)
	if not _check(loaded.ok, "Original Store reconstructs the saved fixed terrain and full cold body", loaded): return {}
	_verify_born(loaded.data, scenario, world_id)
	_check(_facts(loaded.data.site) == expected_facts and FileAccess.get_sha256(path) == digest and int(reopened._marker.generation) == 1, "Cold re-entry preserves exact people/items/sequences without rewriting or another generation")
	return {"slot": reopened, "data": loaded.data, "path": path, "sha256": digest}

func _verify_original_archive(result: Dictionary, old_facts: String) -> void:
	var path := str(result.get("archive", ""))
	if not _check(not path.is_empty() and FileAccess.file_exists(path), "Previous real source is preserved in its original archive", result): return
	var loaded: Dictionary = Store.load_site(path)
	if not _check(loaded.ok, "Original previous-world archive cold-loads through SiteStore", loaded): return
	_check(_facts(loaded.data.site) == old_facts and float(loaded.data.site.actors.player.hp) == 73.0 and Technology.learned(loaded.data.site.actors.player.get("technology", {}), "F07"), "Old original person, items and learned state remain with the original archive")

func _successful_birth(source: RegionData, scenario: String, label: String) -> void:
	var lab := _source_lab(label)
	if lab == null: return
	var controller: SiteController = lab.site_controller
	var old: TerrainData = lab.terrain
	var old_facts := _facts(old.site)
	var world_id := _world(label)
	var result: Dictionary = controller.open_fixed_world(manifest_path, world_id, SLOT, START, true, scenario)
	if not _check(result.ok, "Real original Controller completes the first-world transaction: " + label, result): return
	_freeze(lab)
	_check(int(birth_counts[lab.get_instance_id()]) == 1, "Actual original disposable birth owners enter the formal tree exactly once")
	var slot: RegionSaveSlot = controller.region_slot
	_check(slot != null and int(slot._marker.generation) == 1 and int(result.initial_generation) == 1, "Only the original Slot publishes one first generation")
	_check(lab.region_bind_receipt(lab.terrain).get("complete", false) and lab.region_bind_receipt(lab.terrain).get("mode") == "live", "The actual original main SceneTree emits the complete live bind receipt")
	_check(FileAccess.file_exists(slot.folder.path_join("manifest.json")) and FileAccess.file_exists(slot.folder.path_join("manifest.initialized.json")), "Manifest and initialization receipt exist only after the real first-generation/bind")
	_check(not slot.initialization_pending() and not controller.region_operation_pending() and controller._initial_world_birth_data == null, "Successful original creation releases its pending transient candidates")
	_check(_facts(old.site) == old_facts and lab.terrain != old, "Replacement does not mutate the archived original source bodies")
	_verify_original_archive(result, old_facts)
	var cold: Dictionary = slot._load_checked(slot.site_path(START), START)
	if not _check(cold.ok, "Published first-generation SiteStore file validates against its full geographic pin", cold): return
	_verify_born(cold.data, scenario, world_id)
	var saved_facts := _facts(cold.data.site)
	var reopened := _cold_reopen(source, world_id, scenario, saved_facts)
	if reopened.is_empty(): return
	var manifest_sha := FileAccess.get_sha256(slot.folder.path_join("manifest.json"))
	var committed_sha := FileAccess.get_sha256(slot.folder.path_join("commits/%020d.json" % 1))
	var repeated: Dictionary = controller.open_fixed_world(manifest_path, world_id, SLOT, START, true, scenario)
	_check(not repeated.ok and repeated.code == "CONFLICT" and FileAccess.get_sha256(slot.folder.path_join("manifest.json")) == manifest_sha and FileAccess.get_sha256(slot.folder.path_join("commits/%020d.json" % 1)) == committed_sha, "Completed world creation cannot reissue births, change policy or overwrite its first generation")
	report[label] = {"world_id": world_id, "generation": 1, "site_path": ProjectSettings.globalize_path(str(reopened.path)), "site_sha256": reopened.sha256,
		"people": cold.data.site.get("armies", []).size() * 5 + 1, "archive": result.archive}
	if scenario == Artisans.PRIMARY: _ordinary_scene_resume(lab, world_id)
	lab.free()

func _ordinary_scene_resume(source_lab: TerrainLab, world_id: String) -> void:
	# Authored existing-player state is saved by the actual original live owner.
	# A restore must retain this damage; a mistaken fresh birth would reset it.
	source_lab.character.hp = 91.0
	var source_controller: SiteController = source_lab.site_controller
	var saved: Dictionary = source_controller.save_to(source_controller.save_path)
	if not _check(saved.ok, "Real original live owner saves the already-born world with its full graph", saved): return
	var source_slot: RegionSaveSlot = source_controller.region_slot
	var generation := int(source_slot._marker.generation)
	var path := source_slot.site_path(START)
	var loaded: Dictionary = source_slot._load_checked(path, START)
	if not _check(loaded.ok and loaded.data.site.has("region_snapshot"), "Saved existing first-world population has the real original fullgraph snapshot", loaded): return
	var expected := _facts(loaded.data.site)
	var marker_path := source_slot.folder.path_join("commits/%020d.json" % generation)
	var marker_sha := FileAccess.get_sha256(marker_path)
	var site_sha := FileAccess.get_sha256(path)
	var lab := _source_lab("ordinary_resume")
	if lab == null: return
	var restored: Dictionary = lab.site_controller.open_fixed_world(manifest_path, world_id, SLOT, Vector2i(-1, -1), false)
	if not _check(restored.ok and restored.get("region_recovery", false), "Actual new formal main scene resumes the selected original hot body through its private fullgraph restore", restored): return
	_freeze(lab)
	_check(int(birth_counts[lab.get_instance_id()]) == 0 and _facts(lab.terrain.site) == expected and float(lab.character.hp) == 91.0, "Ordinary world entry restores exact original bodies/items/damage and never births again")
	_check(lab.region_bind_receipt(lab.terrain).get("complete", false) and int(lab.site_controller.region_slot._marker.generation) == generation and FileAccess.get_sha256(marker_path) == marker_sha and FileAccess.get_sha256(path) == site_sha, "Selected fullgraph ordinary restore binds the complete same generation without new save or marker")
	report.ordinary_scene_resume = {"world_id": world_id, "selected_generation": generation, "site_sha256": site_sha, "marker_sha256": marker_sha, "births": 0}
	lab.free()

func _legacy_empty_slot(source: RegionData) -> void:
	var world_id := _world("legacy")
	var slot := RegionSaveSlot.new()
	var opened: Dictionary = slot.open_map(source, world_id, SLOT)
	if not _check(opened.ok, "Original default 3-argument open_map still creates an empty legacy-compatible Slot", opened): return
	_check(FileAccess.file_exists(slot.folder.path_join("manifest.json")) and not FileAccess.file_exists(slot.folder.path_join("manifest.pending.json")) and not FileAccess.file_exists(slot.folder.path_join("manifest.initialized.json")), "Legacy empty Slot retains its original manifest path without new birth/pending metadata")
	_check(slot._marker.is_empty() and not slot.initialization_pending() and str(slot.control.active_site_id).is_empty(), "Default API grants neither a first-generation commit nor initialization birth authority")
	var site: Dictionary = slot.open_site(START)
	if not _check(site.ok, "Default empty Slot can still open its original newly generated Site", site): return
	_check(site.get("created", false) and site.data.site.get("actors", {}).is_empty() and site.data.site.get("armies", []).is_empty(), "Ordinary unvisited Site generation never calls either real birth helper")
	var reopened := RegionSaveSlot.new()
	_check(reopened.open_map(source, world_id, SLOT).ok and reopened._marker.is_empty() and not reopened.initialization_pending(), "Existing empty manifest reopens through the unchanged original API")
	report.legacy = {"world_id": world_id, "manifest": ProjectSettings.globalize_path(slot.folder.path_join("manifest.json"))}

func _failure_resume(source: RegionData, fault: String) -> void:
	var lab := _source_lab("fault_" + fault)
	if lab == null: return
	var controller: SiteController = lab.site_controller
	var old: TerrainData = lab.terrain
	var old_facts := _facts(old.site)
	var world_id := _world(fault)
	var slot := FaultSlot.new()
	slot.fault = fault
	# Substitute only an original Slot IO subtype. Its retained path is a
	# Controller injection seam, never a pin/body/marker/bind proof. open_map
	# must still admit the complete source and every ordinary owner validator.
	slot.folder = "user://region_lab/worlds/%s/slots/%s" % [world_id, SLOT]
	controller._initial_world_candidate = slot
	var result: Dictionary = controller.open_fixed_world(manifest_path, world_id, SLOT, START, true, Artisans.PRIMARY)
	if not _check(not result.ok and result.code == "PENDING" and result.get("cause_code") == "SAVE_IO" and slot.fault_count == 1, "Actual original IO failure becomes a resumable original pending operation: " + fault, result): return
	_check(controller.region_operation_pending() and controller._initial_world_candidate == slot and slot.initialization_pending(), "Pending retry retains the exact original Slot/context")
	var born: TerrainData = controller._initial_world_birth_data
	_check(born == null if fault in ["pending", "pending_tmp"] else born != null, "Birth runs only after its pending metadata is admitted")
	_check(int(birth_counts[lab.get_instance_id()]) == (0 if fault in ["pending", "pending_tmp"] else 1), "Observed original SceneTree birth count matches the real IO boundary")
	if fault == "site":
		_check(str(slot.control.active_site_id).is_empty() and slot.control.fire_clock.index.is_empty() and slot.control.get("region_gameplay", {}).is_empty(), "Failed original candidate save rolls back unpublished control/fire/mode attachment")
	if fault in ["pending", "pending_tmp", "site", "commit"]:
		_check(slot._marker.is_empty() and not FileAccess.file_exists(slot.folder.path_join("manifest.json")), "A precommit IO fault publishes neither first marker nor final manifest")
	else:
		_check(int(slot._marker.get("generation", -1)) == 1, "Postcommit IO fault retains the one true first generation")
		_check(not FileAccess.file_exists(slot.folder.path_join("manifest.initialized.json")), "Failed completion never manufactures a successful initialized receipt")
		if fault == "manifest": _check(not FileAccess.file_exists(slot.folder.path_join("manifest.json")), "Manifest IO fault leaves the sole original first marker recoverable")
	if fault == "receipt":
		_check(lab.terrain != old and lab.region_bind_receipt(lab.terrain).get("complete", false), "Receipt-write failure occurs after the genuine original full main bind")
	else:
		_check(lab.terrain == old and _facts(old.site) == old_facts, "Pre-bind failure keeps the actual old original graph intact")
	var at_before := JSON.stringify([lab.terrain.site.get("minute"), lab.terrain.site.get("phase"), lab.fire_action_cursor, lab._action_time_remainder,
		slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds], "", true, true)
	var facts_before := _facts(lab.terrain.site)
	lab._advance_action_time(0.5)
	_check(at_before == JSON.stringify([lab.terrain.site.get("minute"), lab.terrain.site.get("phase"), lab.fire_action_cursor, lab._action_time_remainder,
		slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds], "", true, true) and _facts(lab.terrain.site) == facts_before,
		"The actual original positive frame consumer stays frozen while birth IO is pending")
	var born_facts := _facts(born.site) if born != null else ""
	var marker_path := slot.folder.path_join("commits/%020d.json" % 1)
	var marker_sha := FileAccess.get_sha256(marker_path) if FileAccess.file_exists(marker_path) else ""
	var changed: Dictionary = slot.open_map(source, world_id, SLOT, true, {"starting_site": [0, 0], "initial_scenario_id": Artisans.THREE_FACTIONS})
	if not _check(not changed.ok and changed.code == "INITIAL_SCENARIO_CONFLICT" and slot._initialization.initial_scenario_id == Artisans.PRIMARY, "The exact pending scenario cannot be reselected, even after IO failed before mkdir", changed): return
	var probe := RegionSaveSlot.new()
	if fault == "pending_tmp":
		var refused: Dictionary = probe.open_map(source, world_id, SLOT)
		_check(not refused.ok and refused.code == "INVALID_SLOT" and FileAccess.file_exists(slot.folder.path_join("manifest.pending.json.tmp")), "A different reader refuses the genuine incomplete pending temporary file without rewriting it")
	elif fault in ["site", "commit"]:
		var refused: Dictionary = probe.open_map(source, world_id, SLOT)
		_check(not refused.ok and refused.code == "INITIALIZATION_PENDING" and slot._marker.is_empty(), "Ordinary resume never births an unfinished original precommit world")
	elif fault in ["manifest", "receipt"]:
		var restored: Dictionary = probe.open_map(source, world_id, SLOT)
		_check(restored.ok and int(probe._marker.get("generation", -1)) == 1 and probe.initialization_pending() and FileAccess.get_sha256(marker_path) == marker_sha, "Fresh original Slot recovers the selected first marker and pending metadata without a new generation")
	var resumed: Dictionary = controller.resume_region_operation()
	if not _check(resumed.ok, "Original Controller resumes the exact pending birth transaction: " + fault, resumed): return
	_freeze(lab)
	_check(controller.region_slot == slot and not controller.region_operation_pending() and not slot.initialization_pending(), "Original same-Slot resume reaches a genuine complete operation")
	_check(int(birth_counts[lab.get_instance_id()]) == 1, "Retry never reissues real original Actor/Army births in the formal SceneTree")
	_check(int(slot._marker.generation) == 1 and float(slot.control.logical_game_seconds) == 0.0 and int(slot.control.fire_clock.sequence) == 0, "Retry neither republishes another first generation nor advances World/Fire time")
	_check(lab.region_bind_receipt(lab.terrain).get("complete", false) and lab.region_bind_receipt(lab.terrain).get("generation") == 1, "Retry binds through the original complete generation-one main receipt")
	if not marker_sha.is_empty(): _check(FileAccess.get_sha256(marker_path) == marker_sha, "Postcommit retry does not rewrite the selected original first marker")
	if fault == "site":
		_check(slot.save_body_ids.size() == 2 and slot.save_body_ids[0] == slot.save_body_ids[1] and born != null and slot.save_body_ids[0] == born.get_instance_id(), "Failed SiteStore retry saves the identical already-born original TerrainData, without birth reissue")
	else:
		_check(slot.save_body_ids.size() == 1, "Once a true born body was saved, later IO retries do not save or birth another candidate")
	var loaded: Dictionary = slot._load_checked(slot.site_path(START), START)
	if not _check(loaded.ok, "Retried first-generation cold body passes the original geographic Store reader", loaded): return
	_verify_born(loaded.data, Artisans.PRIMARY, world_id)
	if not born_facts.is_empty(): _check(_facts(loaded.data.site) == born_facts, "Pending retries preserve exact original people/items/allocators from the already-born candidate")
	_verify_original_archive(resumed, old_facts)
	_cold_reopen(source, world_id, Artisans.PRIMARY, _facts(loaded.data.site))
	report["fault_" + fault] = {"world_id": world_id, "injected": slot.fault_count, "original_save_calls": slot.save_body_ids.size(),
		"generation": int(slot._marker.generation), "marker_sha256": FileAccess.get_sha256(marker_path), "site_sha256": FileAccess.get_sha256(slot.site_path(START))}
	lab.free()

func _configuration_refusal() -> void:
	var lab := _source_lab("config")
	if lab == null: return
	var controller: SiteController = lab.site_controller
	var old: TerrainData = lab.terrain
	var before := _facts(old.site)
	var world_id := _world("invalid")
	var folder := "user://region_lab/worlds/%s/slots/%s" % [world_id, SLOT]
	var refused: Dictionary = controller.open_fixed_world("res://missing_t7_manifest", world_id, SLOT, START, false, Artisans.PRIMARY)
	_check(not refused.ok and refused.code == "INVALID_INITIAL_SCENARIO" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)), "Explicit scenario on ordinary resume rejects before any world IO")
	refused = controller.open_fixed_world("res://missing_t7_manifest", world_id, SLOT, START, true, "unknown_scenario")
	_check(not refused.ok and refused.code == "INVALID_INITIAL_SCENARIO" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)) and lab.terrain == old and _facts(old.site) == before, "Unknown creation scenario cannot write a name or mutate previous original bodies")
	lab.free()

func _run() -> void:
	var source := _fixed_source()
	if source == null: _finish(); return
	_configuration_refusal()
	_legacy_empty_slot(source)
	_successful_birth(source, "", "empty")
	_successful_birth(source, Artisans.PRIMARY, "primary")
	_successful_birth(source, Artisans.THREE_FACTIONS, "three")
	for fault: String in ["pending", "pending_tmp", "site", "commit", "manifest", "receipt"]:
		_failure_resume(source, fault)
	_finish()

func _finish(reason: String = "") -> void:
	if finished: return
	finished = true
	if not reason.is_empty(): failures.append(reason)
	for lab: TerrainLab in labs:
		if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	print("REGION_INITIAL_WORLD_TRANSACTION_REPORT: " + JSON.stringify({"checks": checks, "failures": failures, "cases": report,
		"source_epochs": {"lab": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_lab.gd"),
			"slot": FileAccess.get_sha256("res://scripts/region_lab/region_save_slot.gd"),
			"controller": FileAccess.get_sha256("res://scripts/terrain_lab/site_controller.gd")}, "fixture": root_path}, "", true, true))
	print("REGION_INITIAL_WORLD_TRANSACTION_", "PASS" if failures.is_empty() else "FAILED", " scope=real_formal_scene_pinned_fixed_source_original_first_generation_store_pending_io_sameborn_resume_legacy_api")
	quit(0 if failures.is_empty() else 1)
