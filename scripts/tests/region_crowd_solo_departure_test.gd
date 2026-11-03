extends SceneTree
## G6.4c: the controlled player, a crowd SOLO ACTOR (its own solo team, no roster), leaves Region travel by land while a
## crowd roster team stays behind. Activates a two-faction native crowd on the formal TerrainLab scene with a pinned synthetic
## Region world, then checks:
## - a roster member who is not the formal captain is still refused by departure_plan (UNSUPPORTED), the cadre rule unchanged;
## - a hostile crowd soldier near the player refuses RegionTravelSite.depart (IN_COMBAT), and the refusal releases nobody;
## - with the hostile made inactive for the rest of the test, RegionTravelSite.depart succeeds for the solo actor by land;
## - the travelling party census holds exactly the player, and its team_ids are empty;
## - the origin Site keeps the stay-behind roster team and its people, keeps a crowd section, and no longer holds the player.
## The sea refusal (CROWD_SOLO_SEA_UNSUPPORTED) is not covered: no fixture helper embarks a solo crowd actor.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_SOLO_DEPARTURE_PASS on success; quit(1) on any failure or the 240-second deadline.

const Grid = preload("res://scripts/region_lab/region_grid.gd")

var out := ""
var manifest_path := ""
var checks := 0
var lab: TerrainLab
var controller: SiteController
var slot: RegionSaveSlot
var site_id := ""

func _initialize() -> void:
	out = "res://.godot-temp/region_crowd_solo_departure/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(240.0).timeout.connect(func() -> void: _fail("240-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_SOLO_DEPARTURE_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_SOLO_DEPARTURE OK ", checks, ": ", message)
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

## Same pinned synthetic manifest as region_crowd_journey_test.gd.
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
		"base_revision": "region-crowd-solo-departure-mapped-land-v1", "land_condition_rule": "terrain_mapped_potential_v1", "crs": "EPSG:3826",
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

	# Bind the Site to a pinned Region save slot, so RegionTravelSite.depart reaches the real travel start.
	var world_id := "r0_crowd_solo_departure_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds a pinned Region world", opened): return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null and controller.region_slot == slot, "a Region save slot is bound to the Site"): return
	site_id = str(lab.terrain.site.id)
	if not _check(str(_mode().get("backend", "")) == "gd", "live GD mode before any crowd", _mode()): return

	# Deploy: a four-person friendly roster team (captain plus three soldiers), and an enemy two cells north of the spawn,
	# close enough to block departure. The controlled player is not in any roster: deploy appends it as a solo crowd actor.
	var centre: Vector2i = lab.terrain.spawn_cell
	if not _check(centre != Vector2i(-1, -1), "the Site has a legal spawn cell"): return
	var player: int = lab.character.person_id
	if not _check(lab.controlled_person_id() == player, "the controlled body is the player before the crowd deploys", [lab.controlled_person_id(), player]): return
	var friendly_cells: Array[Vector2i] = []
	for offset: int in range(-2, 2): friendly_cells.append(centre + Vector2i(offset, 3))
	var enemy_cells: Array[Vector2i] = [centre + Vector2i(-1, -3), centre + Vector2i(0, -3)]
	var sides: Array[Dictionary] = [_side(friendly_cells.size(), 0), _side(enemy_cells.size(), 1)]
	if not _check(sides[0].size() > 0 and sides[1].size() > 0, "both original sides exist"): return
	var formations: Array = [friendly_cells, enemy_cells]
	var entered: Dictionary = lab.crowd_site.deploy(sides, formations)
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "the native crowd deploys with the player as a solo actor", entered): return
	var crowd: Variant = lab.crowd_site
	if not _check(crowd._actors.has(player), "the controlled player is a solo crowd actor"): return
	var solo_owner: Variant = crowd.person_owner(player)
	if not _check(solo_owner != null and crowd.team_record(solo_owner.formation_index).is_empty(), "the solo actor has no roster team", player): return

	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0:
			roster = candidate
			break
	if not _check(not roster.is_empty() and roster.units.size() == friendly_cells.size(), "the friendly crowd team has its roster"): return
	var team_id: int = int(roster.team_id)
	var captain: int = int(roster.units[int(roster.formal_commander)].person_id)
	var members: Array[int] = []
	for unit: Dictionary in roster.units: members.append(int(unit.person_id))
	if not _check(not members.has(player), "the player is not a roster member"): return
	# A plain soldier: neither the formal captain nor an officer of the roster.
	var non_cadre_index := 3
	var non_cadre: int = members[non_cadre_index]
	if not _check(int(roster.formal_commander) != non_cadre_index and not roster.officer_service.has(non_cadre_index), "the chosen roster member is not a cadre", non_cadre): return

	# Cadre rule unchanged: an ordinary roster member cannot leave alone; departure_plan refuses before any release.
	var member_plan: Dictionary = crowd.departure_plan(non_cadre)
	if not _check(member_plan.get("ok", true) == false and member_plan.get("code", "") == "UNSUPPORTED",
		"a non-cadre roster member is refused by departure_plan", member_plan): return
	if not _check(crowd.contains_person(non_cadre), "the refused roster member stays in the crowd"): return

	# Hostile refusal: the enemy two cells from the spawn is near the player, so depart refuses by name and releases nobody.
	var refused: Dictionary = RegionTravelSite.depart(controller)
	if not _check(refused.get("ok", true) == false and refused.get("code", "") == "IN_COMBAT",
		"a hostile crowd soldier near the solo actor refuses the land departure", refused): return
	if not _check(crowd._actors.has(player) and crowd.contains_person(player) and crowd.person_owner(player) != null,
		"after the IN_COMBAT refusal the crowd still contains the player"): return
	if not _check(crowd.contains_person(captain), "after the IN_COMBAT refusal the roster team is still native"): return

	# The enemy is made inactive for the rest of the test, so the next departure is not blocked by the hostile check.
	for owner_ref: Variant in crowd.person_owners():
		if int(owner_ref.faction_id) == 1: owner_ref.combat_enabled = false

	# Departure: the solo actor leaves by land; the roster team and its people stay.
	var departed: Dictionary = RegionTravelSite.depart(controller)
	if not _check(departed.get("ok", false) == true and not str(departed.get("token", "")).is_empty(),
		"the solo actor departs by land and the result carries a travel token", departed): return
	var token := str(departed.token)
	var status: Dictionary = slot.region_travel_status()
	if not _check(status.ok and status.pending and str(status.get("token", "")) == token, "the departure opens one pending travel journey", status): return

	# The travelling party holds exactly the player, and no team.
	var travelling: Dictionary = slot.region_travel_party()
	if not _check(travelling.ok, "the travelling party is readable from the slot", travelling): return
	var census: Dictionary = RegionTravel.census(travelling.party)
	if not _check(census.people == [player], "the travelling party census holds exactly the player", census.people): return
	if not _check(travelling.party.get("team_ids", [0]).is_empty(), "the travelling party names no team", travelling.party.get("team_ids")): return

	# The live crowd: the player is gone; the roster team and every member stay native.
	if not _check(not crowd._actors.has(player) and not crowd.contains_person(player) and crowd.person_owner(player) == null,
		"the crowd forgets the departed solo actor"): return
	for identity: int in members:
		if not _check(crowd.contains_person(identity), "a stay-behind roster member is still native", identity): return
	if not _check(crowd.active, "the crowd stays active for the stay-behind team"): return

	# The origin Site: read as the extraction of the post-departure live Site, with the solo spec the departure used.
	var spec: Dictionary = RegionTravelSite._crowd_spec(slot, player, 0)
	spec["actor_key"] = "player"
	spec["crowd_solo"] = true
	spec["crowd_control_successor"] = RegionTravelSite.split_control_successor(lab, player)
	var origin_probe: Dictionary = RegionTravel.extract(lab.terrain.site.duplicate(true), spec, "crowd_solo_origin_probe")
	if not _check(origin_probe.get("ok", false) == true, "the origin Site extracts after the solo departure", origin_probe): return
	var origin: Dictionary = origin_probe.origin
	for key: Variant in origin.get("actors", {}).keys():
		if not _check(int(origin.actors[key].person_id) != player, "the origin Site no longer lists the player as an actor", key): return
	var section: Dictionary = origin.get("crowd", {})
	if not _check(not section.is_empty(), "the origin Site keeps its crowd section for the stay-behind team"): return
	if not _check(int(section.get("player", {}).get("person_id", -1)) != player, "the origin crowd section no longer names the player as controlled"): return
	var stay_entry := {}
	var solo_entry := {}
	for entry: Variant in section.get("teams", []):
		if int(entry.team_id) == team_id: stay_entry = entry
		if entry.person_ids.has(player): solo_entry = entry
	if not _check(not stay_entry.is_empty() and not bool(stay_entry.get("departed", false)), "the origin crowd section keeps the roster team live", stay_entry): return
	for identity: int in members:
		if not _check(stay_entry.person_ids.has(identity), "the origin crowd section keeps every roster member", identity): return
	if not _check(not solo_entry.is_empty() and bool(solo_entry.get("departed", false)), "the origin crowd section tombstones the solo team", solo_entry): return
	var kept_row := false
	for army: Variant in origin.get("armies", []):
		if not army is Dictionary or not bool(army.get("crowd", false)): continue
		var row_ids: Array[int] = []
		for row: Variant in army.get("units", []): row_ids.append(int(row.person_id))
		var all_kept := true
		for identity: int in members:
			if not row_ids.has(identity): all_kept = false
		if all_kept: kept_row = true
		if not _check(not row_ids.has(player), "the origin crowd roster rows do not list the player"): return
	if not _check(kept_row, "the origin crowd roster rows keep the stay-behind team"): return

	print("REGION_CROWD_SOLO_DEPARTURE_PASS: ", checks, " checks; a non-cadre roster member is refused by departure_plan, a hostile near the solo actor refuses IN_COMBAT without release, the solo actor departs by land with a token, the travel party holds exactly the player with no team, the crowd and origin keep the stay-behind team and tombstone the solo team; site ", site_id)
	quit(0)
