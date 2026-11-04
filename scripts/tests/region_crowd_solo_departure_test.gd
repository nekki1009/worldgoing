extends SceneTree
## Neutral part 2 (v2 rewrite of G6.4c): a new game now births the controlled player as roster unit 0 and formal captain of
## a one-person neutral crowd team (host control), never as a solo actor, so the old solo-actor fixture cannot be built from a
## new world any more. The legacy solo-actor departure code is kept (not removed yet) but has no new-game fixture.
## This test now checks the plain one-person-team departure by land on the formal TerrainLab scene with a pinned Region world:
## - the bind-time conversion makes the Site crowd at once, with the player as the host-controlled captain and no actor body;
## - departure_plan accepts the captain with exactly one person;
## - RegionTravelSite.depart succeeds by land with a travel token; the travelling party holds exactly the player and its team;
## - the live crowd forgets the player; the origin Site keeps no actor and no roster row for the player.
## Sea is not covered here (region_crowd_ship_sea_departure_test owns whole-team-aboard departures).
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
	var crowd: Variant = lab.crowd_site
	if not _check(crowd != null and crowd.active and str(lab.region_bind_receipt(lab.terrain).get("backend", "")) == "native", "the new world binds straight into a live crowd", lab.region_bind_receipt(lab.terrain)): return
	var player: int = lab.controlled_person_id()
	if not _check(player > 0 and not lab.actor_present(lab.character) and lab.terrain.site.get("actors", {}).is_empty(), "the controlled player has no actor body", player): return
	if not _check(crowd._records.has(player) and not crowd._actors.has(player), "the controlled player is a crowd roster person, not a crowd actor", player): return
	if not _check(int(crowd._index_by_id.get(player, -1)) == int(crowd.player_index), "host control is on the player", [crowd._index_by_id.get(player, -1), crowd.player_index]): return
	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if crowd._roster_index_for_person(candidate, player) >= 0: roster = candidate
	if not _check(not roster.is_empty() and roster.units.size() == 1 + TerrainLab.INITIAL_CADRES and int(roster.formal_commander) == 0 and int(roster.faction_id) == RegionFactionQuery.NEUTRAL_FACTION_ID,
		"the player is the formal captain of the neutral start team with its cadres", roster.get("units", []).size()): return
	var team_size: int = roster.units.size()
	var team_id: int = int(roster.team_id)
	var team_entry: Dictionary = {}
	for entry: Dictionary in crowd.teams:
		if int(entry.team_id) == team_id: team_entry = entry
	if not _check(not team_entry.is_empty() and not bool(team_entry.get("solo", true)), "the player team is a roster team, not a solo team", team_entry): return

	var plan: Dictionary = crowd.departure_plan(player)
	if not _check(plan.get("ok", false) == true and plan.people.size() == team_size and plan.people.has(player) and int(plan.team_id) == team_id, "departure_plan accepts the captain and the whole start team", plan): return

	var departed: Dictionary = RegionTravelSite.depart(controller)
	if not _check(departed.get("ok", false) == true and not str(departed.get("token", "")).is_empty(),
		"the one-person team departs by land and the result carries a travel token", departed): return
	var token := str(departed.token)
	var status: Dictionary = slot.region_travel_status()
	if not _check(status.ok and status.pending and str(status.get("token", "")) == token, "the departure opens one pending travel journey", status): return
	var travelling: Dictionary = slot.region_travel_party()
	if not _check(travelling.ok, "the travelling party is readable from the slot", travelling): return
	var census: Dictionary = RegionTravel.census(travelling.party)
	if not _check(census.people.size() == team_size and census.people.has(player), "the travelling party census holds the player and the cadres", census.people): return
	if not _check(travelling.party.get("team_ids", []).size() == 1 and int(travelling.party.team_ids[0]) == team_id, "the travelling party names the player's team", travelling.party.get("team_ids")): return
	if not _check(not crowd.contains_person(player) and crowd.person_owner(player) == null, "the crowd forgets the departed captain"): return
	for key: Variant in lab.terrain.site.get("actors", {}).keys():
		if not _check(int(lab.terrain.site.actors[key].person_id) != player, "the origin Site does not list the player as an actor", key): return
	# As region_crowd_departure_test: the live Site save after the departure omits the released team's roster rows.
	var saved: Dictionary = crowd.capture_save() if crowd.active else {"ok": true, "rosters": []}
	if not _check(saved.get("ok", false) == true, "the origin Site still captures after the departure", saved): return
	for army: Variant in saved.rosters:
		for row: Variant in army.get("units", []):
			if not _check(int(row.person_id) != player, "the origin crowd roster rows do not list the player", army.get("team_id")): return

	print("REGION_CROWD_SOLO_DEPARTURE_PASS: ", checks, " checks; the new-game player is the host-controlled captain of a one-person neutral crowd team, departure_plan accepts it, it departs by land with a token, the party holds exactly the player and its team, and the origin keeps no copy; site ", site_id)
	quit(0)
