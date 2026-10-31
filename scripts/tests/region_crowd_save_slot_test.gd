extends SceneTree
## G6 remainder: the Region save slot follows a live native crowd.
## Binds the pinned synthetic Region world (same fixture as region_crowd_bind_test), founds a real settlement
## center through the original paid owner, then checks:
## - mode_registry_follows_crowd: the live mode turns native on deploy, back to gd on clear, native again on redeploy;
##   the hot checkpoint context is stamped from that same mode;
## - officer_observation_crowd: the evaluation officer observation pass no longer refuses MISSING_ORIGINAL_OBSERVER,
##   and a crowd person resolves as a present delivery person;
## - region_siege_attack_move_crowd: crowd attackers in MOVE (goal in the capture zone) and ATTACK get original route
##   proofs and the siege enters "assault" instead of CROWD_SIEGE_ROUTE_UNADMITTED;
##   the save-slot siege refresh admits that ATTACK siege (REGION_BACKEND_UNADMITTED gate on native);
## - owner_lab_backend_crowd: the live owner-lab resolves with the native receipt backend.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_SAVE_SLOT_PASS on success; quit(1) on any failure.

const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Battle = preload("res://scripts/region_lab/region_gameplay_battle.gd")
const RegionAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")

var out := ""
var manifest_path := ""
var checks := 0
var lab: TerrainLab
var controller: SiteController
var slot: RegionSaveSlot
var site_id := ""

func _initialize() -> void:
	out = "res://.godot-temp/region_crowd_save_slot/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_SAVE_SLOT_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_SAVE_SLOT OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _freeze(scene: TerrainLab) -> void:
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.site_controller.set_process(false)
	scene.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in scene.combat_actors: actor.set_process(false)
	for team: TerrainArmy in scene.combat_armies: team.set_process(false)

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path := out.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

## Same pinned synthetic manifest as region_crowd_bind_test.gd.
func _write_manifest() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var summary := PackedByteArray()
	summary.resize(9 * 6)
	summary.fill(2)
	var summary_record := _asset("summary.u8", summary)
	summary_record.merge({"size": [9, 6], "site_origin": [-2, -2], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var width := 90
	var height := 60
	var elevation := PackedByteArray()
	var levels := PackedByteArray()
	var water := PackedByteArray()
	elevation.resize(width * height * 2)
	levels.resize(width * height)
	water.resize(width * height)
	for y in range(height):
		var north := -400 + (height - 1 - y) * 20 + 10
		for x in range(width):
			var east := -400 + x * 20 + 10
			var index := y * width + x
			var sea := east >= 400 and east < 440 and north < 400
			elevation.encode_s16(index * 2, -32767 if sea else 40)
			levels[index] = 0 if sea else 2
			water[index] = 2 if sea else 0
	var height_record := _asset("travel.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record := _asset("travel.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record := _asset("travel.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	height_record.merge({"id": "travel_plain", "origin": [-400, -400], "size": [width, height], "spacing_m": 20,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256,
			"water_path": water_record.path, "water_sha256": water_record.sha256}})
	# Without the declared mapped land rule a fixed Region world has foundation 0 everywhere,
	# so the original founding command refuses TERRAIN "地基不足". Declare it before birth.
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "region-crowd-save-slot-mapped-land-v1", "land_condition_rule": "terrain_mapped_potential_v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Synthetic Region travel fixture only"}]}
	manifest_path = out.path_join("manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	var source := RegionData.new()
	return _check(source.load_manifest(manifest_path).ok, "pinned checksummed manifest loads")

func _side(count: int, faction: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side["faction"] = faction
	return side

func _deploy(defender_cells: Array[Vector2i], attacker_cells: Array[Vector2i], label: String) -> bool:
	var sides: Array[Dictionary] = [_side(defender_cells.size(), 0), _side(attacker_cells.size(), 1)]
	if not _check(not sides[0].is_empty() and not sides[1].is_empty(), "both original sides exist (%s)" % label): return false
	var formations: Array = [defender_cells, attacker_cells]
	var entered: Dictionary = lab.crowd_site.deploy(sides, formations)
	return _check(entered.get("ok", false) and lab.crowd_site.active, "two-faction native crowd deploys (%s)" % label, entered)

func _mode() -> Dictionary:
	return slot.region_registry().modes.get(site_id, {})

func _found_settlement() -> bool:
	var data := lab.terrain
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.capacity = 100000
	for resource: String in Env.ITEM_NAMES: data.site.inventory[resource] = 1000
	if not _check(SiteRuntime.initialize_item_storage(data.site).ok, "original Depot owns explicit fixture stock"): return false
	lab.character.faction_id = 0
	if not _check(lab.character.place(Vector2i(20, 15), true), "founder stands in the founding jurisdiction"): return false
	var layout: Dictionary = SiteRuntime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i.ONE)
	if not _check(layout.ok, "settlement center layout is legal", layout): return false
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var founded: Dictionary = SiteSettlement.found(lab, lab.controlled_person_id(), cells, {}, Callable(), "原據點")
	if not _check(founded.ok, "original founding command reserves center materials", founded): return false
	var key := str(founded.feature)
	var feature: Dictionary = data.site.features[key]
	var task := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	# The work command must come from the center's management faction (the founder's faction, 0);
	# _feature_work refuses any other worker_faction before making progress.
	var management_faction := int(feature.get("owner_faction", -1))
	if not _check(management_faction == lab.character.faction_id and management_faction == 0, "center management faction is the founder's faction",
		{"owner_faction": feature.get("owner_faction"), "founder_faction": lab.character.faction_id}): return false
	SiteRuntime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, SiteRuntime.CARRY_CAPACITY, management_faction, lab.character.person_id)
	feature = data.site.features.get(key, feature)
	if not _check(str(feature.stage) == "complete", "center completes through the original paid feature owner", {
		"stage": feature.get("stage"), "progress": feature.get("progress"), "work": feature.get("work"),
		"has_pending_build": feature.has("pending_build"), "owner_faction": feature.get("owner_faction"),
		"worker_status": task.get("status", ""), "worker_mode": task.get("mode", ""), "worker_action": task.get("action", ""),
		"worker_cell": task.get("cell", -1), "expected_entrance": int(feature.entrance),
		"worker_faction_arg": management_faction, "original_identity": lab.character.person_id}): return false
	return _check(int(SiteSettlement.record(data).get("level", 0)) > 0, "completed center is a level 1 settlement", SiteSettlement.record(data))

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	if not _write_manifest(): return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "formal TerrainLab scene exists"): return
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "formal TerrainLab instance exists"): return
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	if not _check(lab.character != null, "formal scene has its player body"): return
	lab.character.set_process(false)
	controller = lab.site_controller
	if not _check(controller != null and lab.crowd_site != null and not lab.crowd_site.active and not controller.crowd_test_run_id.is_empty(),
		"formal scene has its inactive CrowdSite and isolated Controller"): return
	_freeze(lab)
	var world_id := "r0_crowd_save_slot_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds a pinned Region world", opened): return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null, "Region slot exists after the fixed world binds"): return
	site_id = str(lab.terrain.site.id)
	var mode_gd := _mode()
	if not _check(str(mode_gd.get("mode", "")) == "live" and str(mode_gd.get("backend", "")) == "gd", "live GD mode before any crowd", mode_gd): return
	if not _found_settlement(): return

	# --- mode_registry_follows_crowd -------------------------------------------------------------
	var first_defenders: Array[Vector2i] = [Vector2i(40, 40), Vector2i(41, 40)]
	var first_attackers: Array[Vector2i] = [Vector2i(70, 70), Vector2i(71, 70)]
	if not _deploy(first_defenders, first_attackers, "first"): return
	var mode_native := _mode()
	if not _check(str(mode_native.get("mode", "")) == "live" and str(mode_native.get("backend", "")) == "native"
		and str(mode_native.get("consumer", "")) == "original_site" and int(mode_native.get("revision", -1)) == int(mode_gd.get("revision", -2)) + 1
		and str(mode_native.get("activation", {}).get("backend", "")) == "native" and mode_native.get("activation", {}).get("complete") == true,
		"crowd deploy re-activates the same live owner with backend native", mode_native): return
	if not _check(controller.original_step_fault_guard().ok, "mode follow latched no step fault"): return
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true, {}, "", false)
	if not _check(captured.get("ok", false) and captured.get("snapshot") is Dictionary, "hot checkpoint captures under the native mode", captured.get("code", "")): return
	var context: Dictionary = captured.snapshot.get("context", {})
	if not _check(str(context.get("backend", "")) == "native" and int(context.get("mode_revision", -1)) == int(mode_native.revision),
		"checkpoint context is stamped from the native mode itself", context): return
	var cleared: Dictionary = lab.crowd_site.clear()
	if not _check(cleared.get("ok", false) and not lab.crowd_site.active, "crowd clears back to the original GD owners", cleared): return
	var mode_back := _mode()
	if not _check(str(mode_back.get("backend", "")) == "gd" and str(mode_back.get("mode", "")) == "live" and int(mode_back.get("revision", -1)) == int(mode_native.revision) + 1,
		"crowd clear re-activates the live owner with backend gd", mode_back): return
	# The clear seats its own cadre on the returning holder (no manual release): nothing is pending before the redeploy.
	var pending_after_clear: Array = []
	for team: TerrainArmy in lab.combat_armies:
		if team.combat_enabled and team.has_army(): pending_after_clear.append_array(team.pending_cadre())
	if not _check(pending_after_clear.is_empty(), "the clear seats its returning cadre; none is pending before the redeploy", pending_after_clear): return
	var defenders: Array[Vector2i] = [Vector2i(40, 44), Vector2i(41, 44)]
	var attackers: Array[Vector2i] = [Vector2i(70, 74), Vector2i(71, 74)]
	if not _deploy(defenders, attackers, "second"): return
	if not _check(str(_mode().get("backend", "")) == "native", "redeploy turns the live mode native again", _mode()): return

	# --- officer_observation_crowd ---------------------------------------------------------------
	var observed: Dictionary = slot.record_region_officer_feature_observations(lab)
	if not _check(observed.get("ok", false), "officer observation pass runs under the crowd (no MISSING_ORIGINAL_OBSERVER)", observed): return
	var controlled := lab.controlled_person_id()
	var reference := RegionAI.person_ref(lab.terrain.site, controlled)
	if reference.is_empty():
		print("REGION_CROWD_SAVE_SLOT note: controlled person has no travel ref; delivery-person probe skipped")
	else:
		var person: Dictionary = slot._region_delivery_person(lab, reference)
		if not _check(not person.is_empty() and person.owner is CrowdPersonOwner and int(person.person_id) == controlled,
			"a crowd person resolves as a present delivery person", person.keys()): return

	# --- owner_lab_backend_crowd -----------------------------------------------------------------
	# The live owner-lab resolves under the crowd: its receipt reports the live backend (native), not the bind-time gd.
	var owner_lab: Dictionary = lab._region_gameplay_owner_lab(site_id, "live")
	if not _check(owner_lab.get("ok", false) and owner_lab.get("lab") == lab and str(owner_lab.get("activation", {}).get("backend", "")) == "native",
		"live owner-lab resolves under the crowd with the native receipt backend", owner_lab): return

	# --- region_siege_attack_move_crowd ----------------------------------------------------------
	var attacker_team := {}
	var defender_id := -1
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)) or team.person_ids.is_empty(): continue
		if int(team.faction) == 1 and not bool(team.solo) and attacker_team.is_empty(): attacker_team = team
		if int(team.faction) == 0 and int(team.person_ids[0]) != controlled and defender_id < 0: defender_id = int(team.person_ids[0])
	if not _check(not attacker_team.is_empty() and defender_id > 0, "crowd has an attacker team and a defender person", lab.crowd_site.teams): return
	var zone: Dictionary = SiteSettlement.capture_zone(lab.terrain)
	var goals: Array = zone.keys()
	goals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return lab.terrain.index(a) < lab.terrain.index(b))
	var goal := Vector2i(-1, -1)
	for cell: Vector2i in goals:
		if lab.terrain.is_walkable(cell): goal = cell; break
	if not _check(goal != Vector2i(-1, -1), "capture zone has a walkable goal", goals.size()): return
	var moved: Dictionary = lab.crowd_site.issue_order(int(attacker_team.team_id), TerrainArmy.CombatOrder.MOVE, goal, -1, "test")
	if not _check(moved.get("ok", false), "crowd attacker team takes a MOVE order into the capture zone", moved): return
	var owner_ref: Variant = lab.crowd_site.person_owner(int(attacker_team.person_ids[0]))
	if not _check(owner_ref != null and owner_ref.combat_order == TerrainArmy.CombatOrder.MOVE and Battle._siege_order_goal(owner_ref) == goal,
		"native formation reports MOVE and the same goal cell", [owner_ref.combat_order if owner_ref != null else -1, goal]): return
	var moving: Dictionary = Battle.prepare_original_siege(lab, {})
	if not _check(moving.get("ok", false) and moving.get("present", false), "crowd MOVE siege snapshot is admitted (no CROWD_SIEGE_ROUTE_UNADMITTED)", moving): return
	var routes: Dictionary = moving.siege.get("routes", {})
	if not _check(str(moving.siege.get("phase", "")) == "assault" and routes.has(str(int(attacker_team.person_ids[0]))),
		"crowd MOVE attackers carry original route proofs and the siege is in assault", [moving.siege.get("phase"), routes.keys()]): return
	var attacked: Dictionary = lab.crowd_site.issue_order(int(attacker_team.team_id), TerrainArmy.CombatOrder.ATTACK, Vector2i(-1, -1), defender_id, "test")
	if not _check(attacked.get("ok", false) and owner_ref.combat_order == TerrainArmy.CombatOrder.ATTACK, "crowd attacker team takes an ATTACK order", attacked): return
	var attacking: Dictionary = Battle.prepare_original_siege(lab, {})
	if not _check(attacking.get("ok", false) and attacking.get("present", false) and str(attacking.siege.get("phase", "")) == "assault"
		and attacking.siege.get("routes", {}).has(str(int(attacker_team.person_ids[0]))),
		"crowd ATTACK attackers carry original route proofs and the siege is in assault", attacking): return
	# The save-slot refresh admits the siege under the native mode (backend gate = region_backend_expected).
	var refreshed: Dictionary = slot.refresh_original_region_siege_battle(lab)
	if not _check(refreshed.get("ok", false), "crowd ATTACK siege refreshes the original region battle under the native mode", refreshed): return
	var hold: Dictionary = lab.crowd_site.issue_order(int(attacker_team.team_id), TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "test")
	if not _check(hold.get("ok", false), "crowd attacker team returns to HOLD", hold): return
	var holding: Dictionary = Battle.prepare_original_siege(lab, {})
	var hold_routes: Dictionary = holding.get("siege", {}).get("routes", {})
	if not _check(holding.get("ok", false) and hold_routes.is_empty(), "HOLD crowd attackers carry no route proof (same rule as a GD team)", holding): return

	print("REGION_CROWD_SAVE_SLOT_PASS: ", checks, " checks; mode follows deploy/clear/redeploy, officer observation and crowd siege ATTACK/MOVE admitted")
	quit(0)
