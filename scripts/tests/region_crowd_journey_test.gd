extends SceneTree
## CENTER_JOURNEY: one crowd travel journey through public entries on the formal TerrainLab scene and a pinned
## synthetic Region world.
## - Step 1 (bind): the live crowd Site is bound to a Region save slot (Controller.open_fixed_world, then a native deploy).
## - Step 2 (depart): the controlled captain's whole team leaves through RegionTravelSite.request_departure, the player entry.
## - Step 3 (map steps): the departed journey is checkpointed and reopened through the production RegionTravelPanel.start;
##   an original route is set and RegionSaveSlot.advance_region_travel takes several map steps: no UNSUPPORTED_BACKEND,
##   and the travelling position advances.
## - Step 4 (arrival): the party reaches the fresh neighbouring Site and the production world-open binds it. The arrived
##   team becomes a native crowd team controlled by the player on that crowd-less destination (RegionTravel.insert marks
##   it crowd_convert_pending and the bind converts it). The converted Site saves and reloads with the team still native.
## - The origin Site's crowd advances natively across the map steps (its watermark follows the world clock).
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_JOURNEY_PASS on success (steps 1-3); quit(1) on any failure.

const Grid = preload("res://scripts/region_lab/region_grid.gd")
const TravelPanelScript = preload("res://scripts/region_lab/region_travel_panel.gd")

const MAP_STEPS := 4
## Per-phase deadlines, each a fast fail with its own label (the 540 s in-file timer is the outer bound only).
const MAP_DEADLINE_MS := 60000
const ARRIVAL_DEADLINE_MS := 240000

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
	out = "res://.godot-temp/region_crowd_journey/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(540.0).timeout.connect(func() -> void: _fail("540-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_JOURNEY_FAIL: ", message, " ", str(detail))
	quit(1)

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

## Diagnostic probe (test only): every cached original lab, every party owner lab, and the live modes, with the fields
## region_bind_receipt reads (terrain_lab.gd:875-877: terrain == data, _region_bound_data == data, receipt complete).
func _probe_labs(probe_slot: RegionSaveSlot) -> Dictionary:
	var report := {"original": [], "party": [], "modes": {}}
	for owner: Variant in probe_slot._region_original_labs.keys():
		var item: Variant = probe_slot._region_original_labs[owner]
		if not is_instance_valid(item) or item.terrain == null:
			report["original"].append({"owner": str(owner), "valid": is_instance_valid(item)})
			continue
		report["original"].append({"owner": str(owner), "restore_only": item.restore_only, "bound": item._region_bound_data == item.terrain,
			"complete": item._region_bind_receipt_value.get("complete", null), "crowd": item.crowd_site != null and item.crowd_site.active,
			"site": str(item.terrain.site.get("id", ""))})
	var party_labs: Dictionary = probe_slot.get_meta(&"region_party_owner_labs", {})
	for token: Variant in party_labs.keys():
		var lab_item: Variant = party_labs[token]
		if not is_instance_valid(lab_item) or lab_item.terrain == null:
			report["party"].append({"token": str(token), "valid": is_instance_valid(lab_item)})
			continue
		report["party"].append({"token": str(token), "bound": lab_item._region_bound_data == lab_item.terrain,
			"complete": lab_item._region_bind_receipt_value.get("complete", null), "site": str(lab_item.terrain.site.get("id", ""))})
	var modes: Dictionary = probe_slot.region_registry().modes
	for key: Variant in modes.keys():
		var mode: Dictionary = modes[key]
		report["modes"][str(key)] = {"mode": mode.get("mode", ""), "backend": mode.get("backend", ""), "consumer": mode.get("consumer", "")}
	return report

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
	var world_id := "r0_crowd_journey_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds a pinned Region world", opened): return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null and controller.region_slot == slot, "a Region save slot is bound to the Site"): return
	site_id = str(lab.terrain.site.id)
	var mode_gd := _mode()
	# Neutral part 2: the bind opens the Site as a live native crowd (the player's start team), so the mode is native.
	var bind_live: Dictionary = lab.region_bind_receipt(lab.terrain)
	if not _check(bind_live.get("complete") == true and str(bind_live.get("backend", "")) == "native" and lab.crowd_site.active, "a new world binds straight into a live native crowd", bind_live): return
	if not _check(str(mode_gd.get("mode", "")) == "live" and str(mode_gd.get("backend", "")) == "native", "live native mode from the bind", mode_gd): return
	var cleared: Dictionary = lab.crowd_site.clear()
	if not _check(cleared.get("ok", false) == true and not lab.crowd_site.active, "the player's crowd team returns to GD before the test sides deploy", cleared): return
	# Stand-in for the pending join relabel: the player's start team joins the friendly faction 0, as the old actor
	# player was. Neutral is hostile to everyone, so a neutral player beside the test team would block its departure.
	for team: TerrainArmy in lab.combat_armies:
		if team.has_army() and team.combat_identity(0) == lab.controlled_person_id(): team.faction_id = 0
	var centre: Vector2i = lab.terrain.spawn_cell
	if not _check(centre != Vector2i(-1, -1), "the Site has a legal spawn cell"): return
	var friendly_cells: Array[Vector2i] = []
	for offset: int in range(-1, 2): friendly_cells.append(centre + Vector2i(offset, 3))
	var enemy_cells: Array[Vector2i] = [centre + Vector2i(-1, -40), centre + Vector2i(0, -40)]
	var sides: Array[Dictionary] = [_side(friendly_cells.size(), 0), _side(enemy_cells.size(), 1)]
	if not _check(sides[0].size() > 0 and sides[1].size() > 0, "both original sides exist"): return
	var formations: Array = [friendly_cells, enemy_cells]
	var entered: Dictionary = lab.crowd_site.deploy(sides, formations)
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "the native crowd deploys on the bound Site", entered): return
	var native_mode := _mode()
	if not _check(str(native_mode.get("backend", "")) == "native", "the bound slot's live mode follows the crowd to native", native_mode): return

	var crowd: Variant = lab.crowd_site
	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0:
			roster = candidate
			break
	if not _check(not roster.is_empty() and roster.units.size() == friendly_cells.size(), "the friendly crowd team has its roster"): return
	var team_id: int = int(roster.team_id)
	var members: Array[int] = []
	for unit: Dictionary in roster.units: members.append(int(unit.person_id))
	# The deployed controlled body is a solo crowd actor (crowd_site.gd departure_plan refuses actors), so control moves to the
	# friendly team's formal captain first, as region_crowd_cadre_split_test does for its leader.
	var captain: int = int(roster.units[int(roster.formal_commander)].person_id)
	var switched: Dictionary = crowd.on_control_changed(lab.controlled_person_id(), captain)
	if not _check(switched.ok, "control moves to the friendly team's captain", switched): return
	lab.terrain.site["controlled_person_id"] = captain
	var controlled: int = lab.controlled_person_id()
	if not _check(controlled == captain and members.has(controlled), "the controlled captain is a member of the friendly crowd team", [controlled, captain]): return

	# B (Nekki 2026-11-09): the player's crowd departure has no deferred intent. While a row of the team is still walking under
	# the captain's public MOVE, the request refuses at once and changes nothing; after the public HOLD has settled every row,
	# the same request departs (step 2 below).
	var captain_owner: CrowdPersonOwner = crowd.person_owner(captain) as CrowdPersonOwner
	if not _check(captain_owner != null and captain_owner.moving_member_count() == 0, "the friendly crowd team stands before its captain's order"): return
	var marching: Dictionary = {}
	for distance: int in [9, 7, 5]:
		marching = crowd.issue_order(team_id, TerrainArmy.CombatOrder.MOVE, centre + Vector2i(0, distance), -1, "ui")
		if marching.get("ok", false): break
	if not _check(marching.get("ok", false) == true, "the crowd captain's public formation MOVE is accepted", marching): return
	var walking_row: int = -1
	for count: int in range(600):
		if not crowd.step(1.0 / 60.0, 1.0 / 60.0, 0.0): break
		for member: int in members:
			if member != captain and captain_owner.is_walking(int(captain_owner.index_for_identity(member))): walking_row = member
		if walking_row >= 0: break
	if not _check(walking_row >= 0, "a noncontrolled row of the team walks under the formation order", crowd.last_event_error): return
	var walking_refused: Dictionary = RegionTravelSite.request_departure(controller)
	if not _check(not walking_refused.get("ok", false) and str(walking_refused.get("code", "")) == "NOT_READY" and controller._region_departure_intent.is_empty()
		and slot.region_travel_journey().is_empty() and captain_owner.is_walking(int(captain_owner.index_for_identity(walking_row))),
		"B: a walking row refuses the player's request at once, with no intent and no journey", walking_refused): return
	var halted: Dictionary = crowd.issue_order(team_id, TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "ui")
	if not _check(halted.get("ok", false) == true, "the crowd captain's public HOLD is accepted", halted): return
	for count: int in range(1800):
		if captain_owner.moving_member_count() == 0: break
		if not crowd.step(1.0 / 60.0, 1.0 / 60.0, 0.0): break
	if not _check(captain_owner.moving_member_count() == 0, "the held crowd formation settles every row", crowd.last_event_error): return

	# Nekki 2026-11-04: the team's morale state travels; it leaves shaken, with a rally rest running.
	var origin_formation := int(crowd.person_owner(captain).formation_index)
	if not _check(crowd.set_formation_fields(origin_formation, {"morale": 42.0, "rally_rest": 6.0}), "the departing team is shaken"): return
	# Step 2: whole-team departure through the player entry. Every refusal is decided before any release.
	var departed: Dictionary = RegionTravelSite.request_departure(controller)
	if not _check(departed.get("ok", false) == true, "the controlled team departs through RegionTravelSite.request_departure", departed): return
	var status: Dictionary = slot.region_travel_status()
	if not _check(status.ok and status.pending and not str(status.get("token", "")).is_empty(), "the departure opens one pending travel journey", status): return
	var travelling: Dictionary = slot.region_travel_party()
	if not _check(travelling.ok, "the travelling party is readable from the slot", travelling): return
	var census: Dictionary = RegionTravel.census(travelling.party)
	if not _check(census.people.size() == members.size(), "the travel party carries the whole departing team", census.people): return
	for identity: int in members:
		if not _check(not crowd.contains_person(identity) and crowd.person_owner(identity) == null, "a departed member leaves the Site crowd", identity): return
	if not _check(lab.crowd_site.active, "the remaining crowd keeps the origin Site active after the departure"): return

	# Step 3: map steps of the travelling party through the slot's own entries.
	# Durable checkpoint, then the production travel panel reopens the journey from disk and binds its origin host.
	var checkpoint: Dictionary = slot.checkpoint_region_travel()
	if not _check(checkpoint.ok, "the departed journey is durably checkpointed before the map reopens", checkpoint): return
	# The panel builds its UI in setup(owner_map) (region_travel_panel.gd:36); start() writes its status label, so setup runs first
	# exactly as region_siege_cancellable_departure_test does.
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
	# The origin Site's crowd advances natively while the party travels (e4ecfeb): its GD watermark follows the world clock.
	var origin_watermark_before: float = float(journey_host.fire_action_cursor)
	var world_action_before: float = float(journey_slot.control.fire_clock.action_seconds)

	# Diagnostic (no product change): the three conditions of TerrainLab.region_bind_receipt (terrain_lab.gd:875-877) on the
	# origin host, printed before the map steps so a REGION_BIND_INCOMPLETE failure names the one that fires.
	var receipt_probe := {"restore_only": journey_host.restore_only, "terrain_is_bound": journey_host._region_bound_data == journey_host.terrain,
		"receipt_complete": journey_host._region_bind_receipt_value.get("complete", null),
		"receipt_keys": journey_host._region_bind_receipt_value.keys(), "crowd_active": journey_host.crowd_site != null and journey_host.crowd_site.active}
	print("REGION_CROWD_JOURNEY bind probe: ", receipt_probe)
	print("REGION_CROWD_JOURNEY lab probe before steps: ", _probe_labs(journey_slot))
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

	var moved := 0
	var attempts := 0
	var last_status: Dictionary = before
	var loop_deadline := Time.get_ticks_msec() + MAP_DEADLINE_MS
	while moved < MAP_STEPS and attempts < 5000:
		if not _check(Time.get_ticks_msec() <= loop_deadline, "map steps finish within the %d s phase deadline" % (MAP_DEADLINE_MS / 1000), {"moved": moved, "attempts": attempts}): return
		attempts += 1
		var advanced: Dictionary = journey_slot.advance_region_travel(1)
		if not _check(advanced.get("ok", false) == true, "a map step advances without refusal (no UNSUPPORTED_BACKEND)", {"advance": advanced, "probe": _probe_labs(journey_slot)}): return
		if bool(advanced.get("arrived", false)): break
		if float(advanced.get("advanced", 0.0)) > 0.0: moved += 1
	var after: Dictionary = journey_slot.region_travel_status()
	if not _check(moved >= MAP_STEPS, "several map steps are taken by the travelling party", {"moved": moved, "attempts": attempts}): return
	var position_moved: bool = float(after.get("elapsed_game_seconds", 0.0)) > float(before.get("elapsed_game_seconds", 0.0)) \
		and (float(after.get("fraction", 0.0)) != float(before.get("fraction", 0.0)) or int(after.get("step_index", 0)) != int(before.get("step_index", 0)) \
		or after.get("site") != before.get("site") or int(after.get("component", -1)) != int(before.get("component", -1)))
	var origin_watermark_after: float = float(journey_host.fire_action_cursor)
	var world_action_after: float = float(journey_slot.control.fire_clock.action_seconds)
	var origin_advanced: bool = journey_host.crowd_site != null and journey_host.crowd_site.active \
		and origin_watermark_after > origin_watermark_before and world_action_after > world_action_before \
		and absf(origin_watermark_after - world_action_after) <= 0.000001
	if not _check(origin_advanced, "the origin crowd advances natively across the map steps (watermark follows the world clock)",
		[origin_watermark_before, origin_watermark_after, world_action_after]): return
	if not _check(position_moved, "the travelling position advances across the map steps", [before.get("step_index"), after.get("step_index"), before.get("fraction"), after.get("fraction")]): return
	last_status = after

	# Step 4: the party travels to arrival, then the production world-open binds the destination (as region_travel_test).
	var arrive_deadline := Time.get_ticks_msec() + ARRIVAL_DEADLINE_MS
	var arrived_flag := false
	while not arrived_flag:
		if not _check(Time.get_ticks_msec() <= arrive_deadline, "the journey reaches arrival within the %d s phase deadline" % (ARRIVAL_DEADLINE_MS / 1000)): return
		var progress: Dictionary = journey_slot.advance_region_travel(1000)
		if progress.get("ok", false) != true and str(progress.get("code", "")) == "PENDING": continue
		if not _check(progress.get("ok", false) == true, "the journey advances to arrival without refusal", progress): return
		arrived_flag = bool(progress.get("arrived", false))
	if not _check(arrived_flag, "the travelling party reaches the destination Site"): return
	var at_arrival: Dictionary = journey_slot.region_travel_status()
	if not _check(at_arrival.ok and bool(at_arrival.get("arrived", false)), "the arrived journey is reported as arrived", at_arrival): return
	var destination: Vector2i = at_arrival.destination
	var arrival_saved: Dictionary = journey_slot.checkpoint_region_travel()
	if not _check(arrival_saved.ok, "the arrived journey is durably checkpointed before the world-open", arrival_saved): return
	var arrived_open: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i(-1, -1), false)
	if not _check(arrived_open.ok and bool(arrived_open.get("arrived", false)), "the production world-open admits the arrival at the destination", arrived_open): return
	_freeze(controller.lab)
	if not _check(controller._current_region_site() == destination and controller.region_slot.region_travel_journey().is_empty(),
		"the arrival binds the destination Site and clears the journey", destination): return
	var dest_state: Dictionary = controller.lab.terrain.site
	var arrived_army: Dictionary = {}
	for army: Variant in dest_state.get("armies", []):
		if army is Dictionary and int(army.get("team_id", -1)) == team_id: arrived_army = army
	if not _check(not arrived_army.is_empty() and arrived_army.units.size() == members.size(), "the arrived team is in the destination armies with every member", team_id): return
	var arrived_native: bool = bool(arrived_army.get("crowd", false))
	var destination_crowd: bool = controller.lab.crowd_site != null and controller.lab.crowd_site.active
	if not _check(arrived_native and destination_crowd, "the arrived team converts to a native crowd team on the crowd-less destination", [arrived_native, destination_crowd]): return
	if not _check(not controller.lab.terrain.site.has("crowd_convert_pending"), "the arrival conversion clears the crowd_convert_pending mark"): return
	# The arriving controlled person is a member of the arrived native team and holds host control of the destination crowd.
	var dest_crowd: Variant = controller.lab.crowd_site
	var arrived_controlled: int = controller.lab.controlled_person_id()
	var arrived_ids: Array[int] = []
	for unit: Dictionary in arrived_army.units: arrived_ids.append(int(unit.person_id))
	if not _check(arrived_ids.has(arrived_controlled) and dest_crowd.contains_person(arrived_controlled) and int(dest_crowd.player_index) >= 0,
		"the arriving controlled person is the native crowd's host-controlled soldier", [arrived_controlled, int(dest_crowd.player_index)]): return
	var arrived_owner: Variant = dest_crowd.person_owner(arrived_controlled)
	var arrived_state: Dictionary = dest_crowd.formation_state(int(arrived_owner.formation_index)) if arrived_owner != null else {}
	if not _check(not arrived_state.is_empty() and float(arrived_state.morale) <= 42.0 + 0.001 and float(arrived_state.morale) < 100.0,
		"the arrived native team continues its carried morale (no fresh 100)", [arrived_state.get("morale"), arrived_army.get("team_morale")]): return
	# The converted destination saves and reloads with the team still native and the player still in control.
	var arrival_path: String = controller.save_root.path_join("arrival_crowd.json")
	var site_saved: Dictionary = controller.save_to(arrival_path)
	if not _check(site_saved.ok, "the converted destination saves", site_saved): return
	# A region-bound Site saves into its slot, not the given path: read back the slot's own file, as a reopen does.
	var slot_path: Dictionary = controller.region_slot.effective_site_path(destination)
	if not _check(slot_path.ok, "the destination has a slot Site file", slot_path): return
	var arrival_reloaded: Dictionary = controller.region_slot._load_checked(str(slot_path.path), destination)
	if not _check(arrival_reloaded.ok, "the converted destination reloads from the slot", arrival_reloaded): return
	var reloaded_site: Dictionary = arrival_reloaded.data.site
	var reloaded_army: Dictionary = {}
	for army: Variant in reloaded_site.get("armies", []):
		if army is Dictionary and int(army.get("team_id", -1)) == team_id: reloaded_army = army
	var reloaded_player: Dictionary = reloaded_site.get("crowd", {}).get("player", {})
	var reloaded_native: bool = reloaded_site.has("crowd") and not reloaded_army.is_empty() and bool(reloaded_army.get("crowd", false)) \
		and int(reloaded_player.get("person_id", -1)) == arrived_controlled and int(reloaded_player.get("soldier_index", -1)) >= 0 \
		and not bool(reloaded_site.get("crowd_convert_pending", false))
	if not _check(reloaded_native, "the reloaded destination keeps a native crowd team with the controlled person as its player", [arrived_controlled, reloaded_player]): return
	print("REGION_CROWD_JOURNEY_PASS: ", checks, " checks; steps 1-4 run: bind, whole-team departure via request_departure, map steps via the production travel panel and advance_region_travel, arrival via the production world-open; arrived team converted to a native crowd controlled by the player, Site saved and read back from the slot, origin crowd advanced natively")
	quit(0)
