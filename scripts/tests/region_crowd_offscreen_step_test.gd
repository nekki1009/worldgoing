extends SceneTree
## OFFSCREEN_v1: a cached origin crowd keeps advancing through native crowd stepping while the party travels.
## Steps: bind a live crowd Site to a Region slot; the remaining (enemy) crowd team gets a MOVE order before departure;
## the controlled captain's whole team departs; the journey reopens through the production travel panel; several map
## steps run. Then, on the cached origin crowd:
## (a) the GD watermark (fire_action_cursor, the region clock mode) and the region owner clock equal the world clock,
##     and no region point is left pending;
## (b) crowd.state_hash() changed;
## (c) the moving remaining soldier moved: positive distance, bounded by RUN speed x elapsed action seconds.
## The origin is saved and reloaded afterwards.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_OFFSCREEN_STEP_PASS on success; quit(1) on any failure. Deadline 300 s (in-file).

const MAP_STEPS := 4
const MAP_DEADLINE_MS := 60000

var out := ""
var manifest_path := ""
var checks := 0
var lab: TerrainLab
var controller: SiteController
var slot: RegionSaveSlot
var site_id := ""
var journey_slot: RegionSaveSlot
var journey_host: TerrainLab

func _initialize() -> void:
	out = "res://.godot-temp/region_crowd_offscreen_step/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_OFFSCREEN_STEP_FAIL: ", message, " ", str(detail))
	quit(1)

const Store := preload("res://scripts/terrain_lab/site_store.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const TravelPanelScript = preload("res://scripts/region_lab/region_travel_panel.gd")
func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_JOURNEY OK ", checks, ": ", message)
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

## Same pinned synthetic manifest as region_crowd_save_slot_test.gd.
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
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "region-crowd-journey-mapped-land-v1", "land_condition_rule": "terrain_mapped_potential_v1", "crs": "EPSG:3826",
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

func _mode() -> Dictionary:
	return slot.region_registry().modes.get(site_id, {})


## Diagnostic (test only): the origin stamps a failed map step is checked against, read at the world endpoint.
func _origin_probe(origin: TerrainLab) -> Dictionary:
	var site: Dictionary = origin.terrain.site
	var clock: Dictionary = journey_slot.control.fire_clock
	return {"settlement": RegionSaveSlot.validate_settlement(site, float(journey_slot.control.logical_game_seconds)),
		"fire_settlement": site.get("fire_settlement", {}), "fire_action_cursor": origin.fire_action_cursor,
		"fire_boundary_meta": origin.terrain.get_meta(&"fire_boundary", {}), "pending_point": origin._region_point_pending,
		"mode": journey_slot.region_registry().modes.get(site_id, {}), "generation": int(journey_slot._marker.get("generation", 0)),
		"world_action": float(clock.action_seconds), "world_game": float(journey_slot.control.logical_game_seconds),
		"world_epoch": str(clock.epoch), "world_sequence": int(clock.sequence)}

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

	# Step 1: bind the Site to a Region save slot, then deploy the native crowd on that live owner.
	var world_id := "r0_crowd_offscreen_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds a pinned Region world", opened): return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null, "a Region save slot is bound to the Site"): return
	site_id = str(lab.terrain.site.id)
	var centre: Vector2i = lab.terrain.spawn_cell
	if not _check(centre != Vector2i(-1, -1), "the Site has a legal spawn cell"): return
	var friendly_cells: Array[Vector2i] = []
	for offset: int in range(-1, 2): friendly_cells.append(centre + Vector2i(offset, 3))
	var enemy_cells: Array[Vector2i] = [centre + Vector2i(-1, -40), centre + Vector2i(0, -40)]
	var sides: Array[Dictionary] = [_side(friendly_cells.size(), 0), _side(enemy_cells.size(), 1)]
	if not _check(sides[0].size() > 0 and sides[1].size() > 0, "both original sides exist"): return
	var formations: Array = [friendly_cells, enemy_cells]
	# Neutral part 2: the bind opened the Site as the player's live native crowd; clear it to GD before this deploy.
	var cleared: Dictionary = lab.crowd_site.clear()
	if not _check(cleared.get("ok", false) == true and not lab.crowd_site.active, "the player's crowd team returns to GD before the test sides deploy", cleared): return
	# Stand-in for the pending join relabel: the player's start team joins the friendly faction 0, as the old actor
	# player was. Neutral is hostile to everyone, so a neutral player beside the test team would block its departure.
	for team: TerrainArmy in lab.combat_armies:
		if team.has_army() and team.combat_identity(0) == lab.controlled_person_id(): team.faction_id = 0
	var entered: Dictionary = lab.crowd_site.deploy(sides, formations)
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "the native crowd deploys on the bound Site", entered): return
	if not _check(str(_mode().get("backend", "")) == "native", "the bound slot's live mode follows the crowd to native", _mode()): return

	var crowd: Variant = lab.crowd_site
	var roster: Dictionary = {}
	var remaining: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0 and candidate.units.size() == friendly_cells.size(): roster = candidate # Not the player's start team.
		elif int(candidate.faction_id) == 1: remaining = candidate
	if not _check(not roster.is_empty() and roster.units.size() == friendly_cells.size(), "the friendly crowd team has its roster"): return
	if not _check(not remaining.is_empty() and not remaining.units.is_empty(), "the remaining (enemy) crowd team has its roster"): return
	var team_id: int = int(roster.team_id)
	var members: Array[int] = []
	for unit: Dictionary in roster.units: members.append(int(unit.person_id))
	var captain: int = int(roster.units[int(roster.formal_commander)].person_id)
	var switched: Dictionary = crowd.on_control_changed(lab.controlled_person_id(), captain)
	if not _check(switched.ok, "control moves to the friendly team's captain", switched): return
	lab.terrain.site["controlled_person_id"] = captain
	if not _check(lab.controlled_person_id() == captain and members.has(captain), "the controlled captain is a member of the friendly crowd team"): return

	# The remaining (enemy) crowd team gets a MOVE order before the departure; its first soldier is the moving body.
	var mover: int = int(remaining.units[0].person_id)
	var goal := centre + Vector2i(-1, -36)
	var ordered: Dictionary = crowd.issue_order(int(remaining.team_id), TerrainArmy.CombatOrder.MOVE, goal, -1, "test")
	if not _check(ordered.get("ok", false) == true, "the remaining crowd team accepts a MOVE order before departure", ordered): return

	# Step 2: whole-team departure through the player entry.
	var departed: Dictionary = RegionTravelSite.request_departure(controller)
	if not _check(departed.get("ok", false) == true, "the controlled team departs through RegionTravelSite.request_departure", departed): return
	var status: Dictionary = slot.region_travel_status()
	if not _check(status.ok and status.pending and not str(status.get("token", "")).is_empty(), "the departure opens one pending travel journey", status): return
	for identity: int in members:
		if not _check(not crowd.contains_person(identity) and crowd.person_owner(identity) == null, "a departed member leaves the Site crowd", identity): return

	# Step 3: durable checkpoint, production travel panel reopens the journey, the origin host is the cached crowd owner.
	var checkpoint: Dictionary = slot.checkpoint_region_travel()
	if not _check(checkpoint.ok, "the departed journey is durably checkpointed before the map reopens", checkpoint): return
	var panel = TravelPanelScript.new()
	root.add_child(panel)
	panel.setup(panel)
	panel.set_process(false)
	var started: Dictionary = panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(started.get("ok", false) == true, "the production travel panel reopens the departed journey", started): return
	journey_slot = panel.slot
	journey_host = panel._original_adapter_host
	if not _check(journey_slot != null and journey_host != null, "the reopened journey has its slot and origin host"): return
	_freeze(journey_host)
	if not _check(journey_host.crowd_site != null and journey_host.crowd_site.active, "the cached origin keeps its native crowd after reopen"): return

	# Baselines on the cached origin crowd, read before any map step.
	var origin_crowd: Variant = journey_host.crowd_site.crowd
	var base_hash: int = int(origin_crowd.state_hash())
	var base_index: int = int(origin_crowd.soldier_index(mover))
	if not _check(base_index >= 0, "the moving soldier is a native member of the origin crowd", mover): return
	var base_state: Dictionary = journey_host.crowd_site.soldier_state(base_index)
	var base_px: float = float(base_state.px)
	var base_py: float = float(base_state.py)
	var action_before: float = float(journey_slot.control.fire_clock.action_seconds)

	var before: Dictionary = journey_slot.region_travel_status()
	var party: Dictionary = journey_slot.region_travel_party()
	var context: Dictionary = journey_slot.prepare_region_route_context(null, party.get("party", {}))
	if not _check(before.ok and party.ok and context.ok, "the journey has its party and navigation context", [before.get("code"), party.get("code"), context.get("code")]): return
	var search := RegionRoute.Search.new()
	search.source = journey_slot.source
	search.start_site = before.site
	search.start_component = int(before.component)
	search.goal_site = Vector2i(1, 0)
	search.context = context.context
	var route: Dictionary = search.run()
	if not _check(route.ok, "the original route producer finds a land leg to the neighbouring Site", route): return
	var planned: Dictionary = journey_slot.set_region_travel_plan(route.steps)
	if not _check(planned.ok, "the original slot admits the route", planned): return

	print("REGION_CROWD_OFFSCREEN_STEP probe before steps: ", _origin_probe(journey_host))
	var moved := 0
	var attempts := 0
	var loop_deadline := Time.get_ticks_msec() + MAP_DEADLINE_MS
	while moved < MAP_STEPS and attempts < 5000:
		if not _check(Time.get_ticks_msec() <= loop_deadline, "map steps finish within the phase deadline", {"moved": moved, "attempts": attempts}): return
		attempts += 1
		var advanced: Dictionary = journey_slot.advance_region_travel(1)
		if not _check(advanced.get("ok", false) == true, "a map step advances without refusal", {"advance": advanced, "origin": _origin_probe(journey_host)}): return
		if bool(advanced.get("arrived", false)): break
		if float(advanced.get("advanced", 0.0)) > 0.0: moved += 1
	if not _check(moved >= MAP_STEPS, "several map steps are taken", {"moved": moved, "attempts": attempts}): return

	# (a) GD watermark and region owner clock equal the world clock; no region point is left pending.
	var world_action: float = float(journey_slot.control.fire_clock.action_seconds)
	var world_game: float = float(journey_slot.control.logical_game_seconds)
	var elapsed_action: float = world_action - action_before
	if not _check(elapsed_action > 0.0, "the world clock advanced across the map steps", [action_before, world_action]): return
	var mode: Dictionary = journey_slot.region_registry().modes.get(site_id, {})
	if not _check(absf(journey_host.fire_action_cursor - world_action) <= 0.000001, "the origin GD watermark equals the world action clock", [journey_host.fire_action_cursor, world_action]): return
	if not _check(absf(float(mode.get("action_seconds", -1.0)) - world_action) <= 0.000001, "the origin region owner action clock equals the world", mode): return
	if not _check(absf(float(mode.get("game_seconds", -1.0)) - world_game) <= 0.000001, "the origin region owner game clock equals the world", mode): return
	if not _check(journey_host._region_point_pending.is_empty(), "no origin region point is left pending"): return

	# (b) the native world changed.
	var after_hash: int = int(journey_host.crowd_site.crowd.state_hash())
	if not _check(after_hash != base_hash, "the origin crowd state hash changed across the map steps", [base_hash, after_hash]): return

	# (c) the moving soldier moved: positive distance, bounded by RUN speed (4.0 cells/s, CELL 64) x elapsed action seconds.
	var after_index: int = int(journey_host.crowd_site.crowd.soldier_index(mover))
	var after_state: Dictionary = journey_host.crowd_site.soldier_state(after_index)
	var distance: float = Vector2(float(after_state.px) - base_px, float(after_state.py) - base_py).length()
	if not _check(distance > 0.0, "the moving soldier has positive distance", distance): return
	if not _check(distance <= 4.0 * 64.0 * elapsed_action + 1.0, "the moving soldier stays within the RUN speed bound", [distance, elapsed_action]): return

	# Save and reload the cached origin after the steps.
	# The slot's own checkpoint is the product save path the next map step uses; a failure prints the whole result.
	var checkpointed: Dictionary = journey_slot.checkpoint_region_travel()
	if not _check(checkpointed.get("ok", false) == true, "the origin and journey checkpoint through the slot after the map steps", checkpointed): return
	# Reload through the slot's own read path (the reopen path): the checkpointed origin file must be crowd-active,
	# with the live cold origin's crowd section blob and its soldier count.
	var origin_site: Vector2i = journey_slot._coordinate(journey_host.terrain).site
	var effective: Dictionary = journey_slot.effective_site_path(origin_site)
	if not _check(effective.ok and not str(effective.path).is_empty(), "the checkpointed origin file is on the slot path", effective): return
	var reread: Dictionary = journey_slot._load_checked(str(effective.path), origin_site)
	if not _check(reread.get("ok", false) == true, "the origin reloads through the slot read path", reread): return
	var reloaded_native: Variant = reread.get("crowd_native")
	if not _check(reloaded_native is Object and reloaded_native.get_class() == &"ArmyCrowd", "the reloaded origin is crowd-active native"): return
	var live_blob := str(journey_host.terrain.site.get("crowd", {}).get("blob_sha256", ""))
	var reread_blob := str(reread.data.site.get("crowd", {}).get("blob_sha256", ""))
	if not _check(not live_blob.is_empty() and live_blob == reread_blob, "the reloaded crowd blob sha equals the live cold origin's", [live_blob, reread_blob]): return
	if not _check(int(reloaded_native.soldier_count()) == int(journey_host.crowd_site.crowd.soldier_count()), "the reloaded soldier count matches the live origin", int(reloaded_native.soldier_count())): return

	print("REGION_CROWD_OFFSCREEN_STEP_PASS: ", checks, " checks; ", moved, " map steps, action ", elapsed_action,
		" s; origin watermark and owner clock match the world, state hash changed, moving soldier moved ", distance, " px, origin saves and reloads")
	quit(0)
