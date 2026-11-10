extends SceneTree
## R5-R7 (2026-11-01): an ordinary party arriving at a live crowd Site. Setup as region_crowd_cadre_split_test (pair case):
## a seven-person friendly crowd team; a cadre leads three of its people off the Site as a sub-party. The Site it leaves
## (two sides, saved and reloaded) is the destination. The party is inserted with RegionTravel.insert. Checks:
## - the arrival adds one native formation and three soldiers; its roster is crowd=true with the party leader as formal
##   captain; the saved Site validates through SiteStore and reloads with the new formation;
## - a duplicate team id is refused ID_CONFLICT, a garrisoned team INVALID_GARRISON, an arriving actor
##   UNSUPPORTED_CROWD_ACTOR_ARRIVAL; every refusal leaves the destination file and blob hash unchanged.
## --case player (default npc): the controlled cadre stays in the party and arrives as the crowd's controlled soldier. The
## destination's own controlled soldier first refuses the arrival ID_CONFLICT (nothing changes); its host control is then
## released on its native and record, so the arrival takes control. The arrived Site keeps controlled_person_id, the crowd
## player section (person id and native index) and the native host control through save, SiteStore load and reload.
## Run only with: --crowd --crowd-test <fresh_run_id> [--case player]
## Output: REGION_CROWD_ARRIVAL_PASS on success; quit(1) on any failure.

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")

var checks := 0
var lab: TerrainLab

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_ARRIVAL_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_ARRIVAL OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _side(count: int, faction: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side.faction = faction
	return side

func _spec(identity: int, team_id: int, successor: Dictionary) -> Dictionary:
	return {"person_id": identity, "actor_key": "", "team_id": team_id, "controller": "player", "mode": "land",
		"crowd_departure": true, "crowd_split": true, "crowd_control_successor": successor, "game_seconds": 0.0}

func _make_cadre(roster: Dictionary, index: int) -> void:
	var person := int(roster.units[index].person_id)
	for seat: Dictionary in roster.get("offices", {}).get("positions", []):
		if not bool(seat.get("head", false)) and int(seat.get("holder", 0)) <= 0:
			seat["holder"] = person
			break
	var service: Array = roster.get("officer_service", [])
	service.append(index)
	roster["officer_service"] = service

func _index_of(roster: Dictionary, identity: int) -> int:
	for index in range(roster.units.size()):
		if int(roster.units[index].person_id) == identity: return index
	return -1

func _team_entry(site_crowd: Dictionary, team_id: int) -> Dictionary:
	for team: Dictionary in site_crowd.get("teams", []):
		if int(team.get("team_id", -1)) == team_id: return team
	return {}

## The travel namespace RegionTravel derives for a Site: its own travel_identity, or the one from its id when absent.
func _namespace(state: Dictionary) -> String:
	return str(state.get("travel_identity", {}).get("namespace", "site:" + str(state.get("id", ""))))

func _army(state: Dictionary, team_id: int) -> Dictionary:
	for army: Variant in state.get("armies", []):
		if army is Dictionary and int(army.get("team_id", -1)) == team_id: return army
	return {}

func _sha(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()

## Player case, state record: the Site's controlled person and its crowd player section name the leader's destination id.
func _player_state_checks(state: Dictionary, leader: int) -> bool:
	var section: Dictionary = state.crowd.get("player", {})
	if not _check(int(state.get("controlled_person_id", -1)) == leader, "the destination's controlled_person_id is the leader's destination id", [int(state.get("controlled_person_id", -1)), leader]): return false
	return _check(int(section.get("person_id", -1)) == leader, "the crowd player section names the leader's destination id", section)

## Player case, native: the section's soldier index is the leader's native index, which alone has host control. The native has no
## getter for host control, so host_input with zero wishes is the query: it returns true only for the host-controlled soldier and
## writes nothing for the others.
func _player_native_checks(state: Dictionary, native: Object, leader: int) -> bool:
	var index := int(native.call("soldier_index", leader))
	var section: Dictionary = state.crowd.get("player", {})
	if not _check(index >= 0 and int(section.get("soldier_index", -1)) == index, "the crowd player section names the leader's native index", [section, index]): return false
	if not _check(bool(native.call("host_input", index, 0.0, 0.0, false, false)), "the leader's native soldier has host control"): return false
	var other := 0 if index != 0 else 1
	return _check(not bool(native.call("host_input", other, 0.0, 0.0, false, false)), "no other native soldier has host control")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	var case_name := "npc"
	var case_flag := args.find("--case")
	if case_flag >= 0 and case_flag + 1 < args.size(): case_name = str(args[case_flag + 1])
	if not _check(case_name in ["npc", "player"], "--case is npc (default) or player", case_name): return
	var player_case := case_name == "player"
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "formal TerrainLab scene exists"): return
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "formal TerrainLab instance exists"): return
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	if not _check(lab.character != null and lab.site_controller != null, "formal scene has its player body and Controller"): return
	lab.character.set_process(false)
	if not _check(lab.crowd_site != null and not lab.crowd_site.active, "formal scene has an inactive CrowdSite"): return
	if not _check(lab.terrain != null and lab.terrain.spawn_cell != Vector2i(-1, -1), "scene has a legal spawn cell"): return
	var centre: Vector2i = lab.terrain.spawn_cell
	var friendly_cells: Array[Vector2i] = []
	for offset: int in range(-3, 4): friendly_cells.append(centre + Vector2i(offset, 3))
	var enemy_cells: Array[Vector2i] = [centre + Vector2i(-1, -40), centre + Vector2i(0, -40)]
	var sides: Array[Dictionary] = [_side(friendly_cells.size(), 0), _side(enemy_cells.size(), 1)]
	if not _check(sides[0].size() > 0 and sides[1].size() > 0, "both original sides exist"): return
	var formations: Array = [friendly_cells, enemy_cells]
	var entered: Dictionary = lab.crowd_site.deploy(sides, formations)
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "two-faction native crowd activates", entered): return

	var crowd: Variant = lab.crowd_site
	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0:
			roster = candidate
			break
	if not _check(not roster.is_empty() and roster.units.size() == friendly_cells.size(), "the friendly crowd team has its roster"): return
	var captain := int(roster.units[int(roster.formal_commander)].person_id)
	var team_id := int(roster.team_id)
	var leader := -1
	for unit: Dictionary in roster.units:
		if int(unit.person_id) != captain and leader < 0: leader = int(unit.person_id)
	var switched: Dictionary = crowd.on_control_changed(lab.controlled_person_id(), leader)
	if not _check(switched.ok, "control moves to a chosen non-captain soldier", switched): return
	lab.terrain.site["controlled_person_id"] = leader
	var second := -1
	var ordinary: Array[int] = []
	for unit: Dictionary in roster.units:
		var identity := int(unit.person_id)
		if identity == captain or identity == leader: continue
		if second < 0: second = identity
		else: ordinary.append(identity)
	_make_cadre(roster, _index_of(roster, leader))
	_make_cadre(roster, _index_of(roster, second))

	# The three-person party: the cadre and two ordinary members leave by a split (the cadre-split path).
	var group: Array[int] = [leader, ordinary[0], ordinary[1]]
	var plan: Dictionary = crowd.split_departure_plan(leader, group.slice(1))
	if not _check(plan.get("ok", false) == true and plan.people.size() == 3, "the sub-party passes the split plan", plan): return
	var site_captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(site_captured.get("ok", false) == true, "the Site captures before the split", site_captured): return
	var successor: Dictionary = RegionTravelSite.split_control_successor(lab, leader)
	if not _check(int(successor.get("person_id", -1)) > 0, "control passes to the player actor body", successor): return
	var released: Dictionary = crowd.split_departure_release(plan, team_id + 1000)
	if not _check(released.get("ok", false) == true, "the sub-party is released", released): return
	var departing: Dictionary = released.army.duplicate(true)
	departing["crowd"] = true
	var captured: Dictionary = crowd.capture_save()
	if not _check(captured.get("ok", false) == true, "the Site captures after the split", captured): return
	captured.rosters.append(departing)
	lab.site_controller._apply_region_crowd_capture(captured)
	var extracted: Dictionary = RegionTravel.extract(lab.terrain.site.duplicate(true), _spec(leader, team_id + 1000, successor), "crowd_arrival")
	if not _check(extracted.get("ok", false) == true, "the sub-party extracts from the Site", extracted): return
	var party: Dictionary = extracted.party
	if not player_case:
		# An ordinary party: the cadre's control stays with the Site's player body (see report).
		party.content.erase("controlled_person_id")
	elif not _check(int(party.content.get("controlled_person_id", -1)) == leader and str(party.controller) == "player", "the player party carries the controlled cadre", party.content.get("controlled_person_id")):
		return
	var party_team := int(party.content.armies[0].team_id)
	if not _check(party.content.armies.size() == 1 and party.content.armies[0].units.size() == 3, "the party carries three people in one team"): return

	# The origin: the Site the split leaves, saved and loaded. The party left it, so arriving back there is refused.
	lab.terrain.site = extracted.origin
	DirAccess.make_dir_recursive_absolute("user://sites")
	var origin_path := "user://sites/crowd_arrival_origin.json"
	var origin_written: Dictionary = Store.save(lab.terrain, origin_path, crowd.crowd)
	if not _check(origin_written.get("ok", false) == true, "the origin Site saves", origin_written): return
	var origin_loaded: Dictionary = Store.load_site(origin_path, Callable(), 1, false)
	if not _check(origin_loaded.get("ok", false) == true, "the origin Site loads", origin_loaded): return

	# The destination: a second live crowd Site with its own people (a separate scene and deploy), saved and loaded.
	var packed2 := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	var lab2 := packed2.instantiate() as TerrainLab
	if not _check(lab2 != null, "a second formal TerrainLab instance exists for the destination"): return
	lab2.pause_when_unfocused = false
	lab2.movement_input_enabled = false
	root.add_child(lab2)
	lab2.set_process(false)
	lab2.character.set_process(false)
	# A genuinely different Site: its own id and no inherited travel identity, so its namespace and refs are its own.
	lab2.terrain.site["id"] = "crowd_arrival_destination"
	lab2.terrain.site.erase("travel_identity")
	var centre2: Vector2i = lab2.terrain.spawn_cell
	var dest_friendly: Array[Vector2i] = []
	for offset: int in range(-3, 4): dest_friendly.append(centre2 + Vector2i(offset, 3))
	var dest_enemy: Array[Vector2i] = [centre2 + Vector2i(-1, -40), centre2 + Vector2i(0, -40)]
	var dest_side_a: Dictionary = lab2._trial_side_settings({"friendly_count": dest_friendly.size(), "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly").side
	dest_side_a.faction = 0
	var dest_side_b: Dictionary = lab2._trial_side_settings({"friendly_count": dest_enemy.size(), "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly").side
	dest_side_b.faction = 1
	var dest_entered: Dictionary = lab2.crowd_site.deploy([dest_side_a, dest_side_b], [dest_friendly, dest_enemy])
	if not _check(dest_entered.get("ok", false) and lab2.crowd_site.active, "the destination's own two-side crowd activates", dest_entered): return
	var dest_captured: Dictionary = lab2.site_controller._capture_for_save()
	if not _check(dest_captured.get("ok", false) == true, "the destination Site captures", dest_captured): return
	var dest_path := "user://sites/crowd_arrival_dest.json"
	var written: Dictionary = Store.save(lab2.terrain, dest_path, lab2.crowd_site.crowd)
	if not _check(written.get("ok", false) == true, "the destination Site saves", written): return
	var loaded: Dictionary = Store.load_site(dest_path, Callable(), 1, false)
	if not _check(loaded.get("ok", false) == true, "the destination Site loads", loaded): return
	var dest_native: Variant = loaded.get("crowd_native")
	if not _check(dest_native is Object and dest_native.get_class() == &"ArmyCrowd", "the destination loads its native crowd"): return
	var dest_state: Dictionary = loaded.data.site
	if not _check(_namespace(dest_state) != _namespace(origin_loaded.data.site) and str(dest_state.id) != str(origin_loaded.data.site.id), "the destination is a different Site: its own id and travel namespace", [_namespace(dest_state), _namespace(origin_loaded.data.site)]): return
	var formations_before := int(dest_native.formation_count())
	var soldiers_before := int(dest_native.soldier_count())
	var teams_before := int(dest_state.crowd.teams.size())
	var file_before := FileAccess.get_sha256(dest_path)
	var blob_before := str(dest_state.crowd.blob_sha256)
	var entry: Vector2i = loaded.data.spawn_cell
	var nav: TerrainData = Env.navigation_for_state(loaded.data, dest_state)
	if player_case:
		# The destination's own controlled soldier (from its deploy) would clash with the arriving one: refused ID_CONFLICT,
		# nothing changes. Its control is then released on the native and in the record, so the arrival can take control.
		var own_identity := int(dest_state.crowd.player.get("person_id", -1))
		# The crowd player section is the record of control (JSON gives floats: every id and index is read with int()).
		var own_section: Dictionary = dest_state.crowd.get("player", {})
		if not _check(own_identity > 0 and int(own_section.get("soldier_index", -1)) >= 0, "the destination starts with its own controlled soldier", own_section): return
		var clash: Dictionary = RegionTravel.insert(dest_state, party.duplicate(true), nav, entry, dest_path, 0.0, 0.0, {})
		if not _check(clash.get("ok", true) == false and clash.get("code", "") == "ID_CONFLICT", "a controlled arrival at a destination with a controlled soldier is refused ID_CONFLICT", clash): return
		if not _check(FileAccess.get_sha256(dest_path) == file_before and str(dest_state.crowd.blob_sha256) == blob_before, "the ID_CONFLICT refusal leaves the destination file and blob hash unchanged"): return
		var own_index := int(dest_native.call("soldier_index", own_identity))
		if not _check(own_index >= 0 and bool(dest_native.call("set_host_control", own_index, false)), "the destination's own host control is released"): return
		var cleared: PackedByteArray = dest_native.call("save_state")
		dest_state.crowd["blob"] = Marshalls.raw_to_base64(cleared)
		dest_state.crowd["blob_sha256"] = _sha(cleared)
		dest_state.crowd["player"] = {"person_id": -1, "soldier_index": -1}
		dest_state.erase("controlled_person_id")
		blob_before = str(dest_state.crowd.blob_sha256)

	# Refusals: each changes nothing.
	var duplicate_party: Dictionary = party.duplicate(true)
	var remaining_team := -1
	for army: Variant in dest_state.get("armies", []):
		if army is Dictionary and bool(army.get("crowd", false)): remaining_team = int(army.team_id)
	duplicate_party.content.armies[0].team_id = remaining_team
	var refused: Dictionary = RegionTravel.insert(dest_state, duplicate_party, nav, entry, dest_path, 0.0, 0.0, {})
	if not _check(refused.get("ok", true) == false and refused.get("code", "") == "ID_CONFLICT", "a duplicate team id is refused ID_CONFLICT", refused): return
	var garrisoned_party: Dictionary = party.duplicate(true)
	garrisoned_party.content.armies[0]["garrison_feature_id"] = "arrival_test_garrison"
	refused = RegionTravel.insert(dest_state, garrisoned_party, nav, entry, dest_path, 0.0, 0.0, {})
	if not _check(refused.get("ok", true) == false and refused.get("code", "") == "INVALID_GARRISON", "a garrisoned team is refused INVALID_GARRISON", refused): return
	var actor_party: Dictionary = party.duplicate(true)
	actor_party.content["actors"] = {"npc": {"person_id": 999999}}
	refused = RegionTravel.insert(dest_state, actor_party, nav, entry, dest_path, 0.0, 0.0, {})
	if not _check(refused.get("ok", true) == false and refused.get("code", "") == "UNSUPPORTED_CROWD_ACTOR_ARRIVAL", "an arriving actor is refused UNSUPPORTED_CROWD_ACTOR_ARRIVAL", refused): return
	# Returning to the origin Site. The party split off its team, so the origin still holds the three people as released
	# native slots listed in that team's departed_person_ids. They rejoin through their own slots (no new soldiers) as the
	# party's own team in one new formation, and the team they split from no longer lists them as away.
	var origin_state: Dictionary = origin_loaded.data.site
	var origin_blob_before := str(origin_state.crowd.blob_sha256)
	var origin_file_before := FileAccess.get_sha256(origin_path)
	var origin_native: Variant = origin_loaded.get("crowd_native")
	if not _check(origin_native is Object, "the origin loads its native crowd"): return
	var origin_soldiers := int(origin_native.soldier_count())
	var origin_formations := int(origin_native.formation_count())
	var split_from: Dictionary = _team_entry(origin_state.crowd, team_id)
	if not _check(not bool(split_from.get("departed", false)) and split_from.get("departed_person_ids", []).size() == 3 and _team_entry(origin_state.crowd, party_team).is_empty(), "the origin's team lists the three people who split off as away", split_from): return
	var away_ids: Array = split_from.departed_person_ids.duplicate()
	var return_nav: TerrainData = Env.navigation_for_state(origin_loaded.data, origin_state)
	var came_back: Dictionary = RegionTravel.insert(origin_state, party.duplicate(true), return_nav, origin_loaded.data.spawn_cell, origin_path, 0.0, 0.0, {})
	if not _check(came_back.get("ok", false) == true, "the party returns to the origin Site it left", came_back): return
	if not _check(FileAccess.get_sha256(origin_path) == origin_file_before and str(origin_state.crowd.blob_sha256) == origin_blob_before, "the return leaves the caller's origin state and the origin file untouched"): return
	var back_state: Dictionary = came_back.state
	var back_entries := 0
	var still_held := 0
	for team: Variant in back_state.crowd.teams:
		if int(team.get("team_id", -1)) == party_team: back_entries += 1
		if bool(team.get("departed", false)):
			for identity: Variant in team.get("person_ids", []):
				if away_ids.has(identity): still_held += 1
		for identity: Variant in team.get("departed_person_ids", []):
			if away_ids.has(identity): still_held += 1
	var back_entry: Dictionary = _team_entry(back_state.crowd, party_team)
	if not _check(back_entries == 1 and not bool(back_entry.get("departed", false)) and back_entry.get("person_ids", []).size() == 3 and still_held == 0, "the returned team has one entry of three people and nobody is still listed as away", [back_entries, back_entry, still_held]): return
	var back_ids: Array = []
	for identity: Variant in back_entry.person_ids: back_ids.append(int(identity))
	back_ids.sort()
	var left_ids: Array = []
	for identity: Variant in away_ids: left_ids.append(int(identity))
	left_ids.sort()
	if not _check(back_ids == left_ids, "the returned people keep the person ids they left with", [back_ids, left_ids]): return
	var back_army: Dictionary = _army(back_state, party_team)
	if not _check(not back_army.is_empty() and bool(back_army.get("crowd", false)) and back_army.units.size() == 3, "the returned roster is crowd=true with three people"): return
	var back_path := "user://sites/crowd_arrival_returned.json"
	origin_loaded.data.site = back_state
	var back_saved: Dictionary = Store.save(origin_loaded.data, back_path)
	if not _check(back_saved.get("ok", false) == true, "the origin Site saves after the return", back_saved): return
	var back_loaded: Dictionary = Store.load_site(back_path, Callable(), 1, false)
	if not _check(back_loaded.get("ok", false) == true, "the origin Site validates and reloads after the return", back_loaded): return
	var back_native: Variant = back_loaded.get("crowd_native")
	if not _check(int(back_native.soldier_count()) == origin_soldiers, "the returners took their own native slots back: no new soldier", [int(back_native.soldier_count()), origin_soldiers]): return
	if not _check(int(back_native.formation_count()) == origin_formations + 1, "the returned team stands in one new formation beside the team it split from", [int(back_native.formation_count()), origin_formations]): return
	for identity: int in back_ids:
		var back_index := int(back_native.call("soldier_index", identity))
		if not _check(back_index >= 0 and float(back_native.call("get_soldier_state", back_index)[0]) > 0.0, "a returned person is a living native soldier under their own id", [identity, back_index]): return
	if not _check(FileAccess.get_sha256(dest_path) == file_before and str(dest_state.crowd.blob_sha256) == blob_before, "refusals leave the destination file and blob hash unchanged"): return

	# The arrival.
	var inserted: Dictionary = RegionTravel.insert(dest_state, party, nav, entry, dest_path, 0.0, 0.0, {})
	if not _check(inserted.get("ok", false) == true, "the ordinary party arrives at the crowd Site", inserted): return
	var after_state: Dictionary = inserted.state
	if not _check(after_state.crowd.teams.size() == teams_before + 1, "the destination gains one crowd team", after_state.crowd.teams.size()): return
	if not _check(str(dest_state.crowd.blob_sha256) == blob_before, "the caller's destination blob hash is not touched by the arrival"): return
	var arrived: Dictionary = _army(after_state, party_team)
	if not _check(not arrived.is_empty() and bool(arrived.get("crowd", false)), "the arriving roster is crowd=true"): return
	# Arrival remaps person ids into the destination namespace; the returned leader id is the destination's id for the leader.
	var arrival_leader := int(inserted.leader_person_id)
	var captain_now := int(arrived.units[int(arrived.formal_commander)].person_id)
	if not _check(captain_now == arrival_leader, "the arriving roster's formal captain is the party leader", {"expected": arrival_leader, "actual": captain_now, "origin_leader": leader}): return
	if not _check(_team_entry(after_state.crowd, party_team).get("person_ids", []).size() == 3, "the arriving team entry names three people"): return

	if player_case and not _player_state_checks(after_state, arrival_leader): return

	# Save -> load: the Site validates and reloads with the new formation and three soldiers.
	var arrival_path := "user://sites/crowd_arrival_after.json"
	loaded.data.site = after_state
	var saved: Dictionary = Store.save(loaded.data, arrival_path)
	if not _check(saved.get("ok", false) == true, "the arrived Site saves", saved): return
	var reloaded: Dictionary = Store.load_site(arrival_path, Callable(), 1, false)
	if not _check(reloaded.get("ok", false) == true, "the arrived Site validates and reloads", reloaded): return
	var restored: Variant = reloaded.get("crowd_native")
	if not _check(int(restored.formation_count()) == formations_before + 1, "the reloaded native crowd has the new formation", [int(restored.formation_count()), formations_before]): return
	if not _check(int(restored.soldier_count()) == soldiers_before + 3, "the reloaded native crowd has three more soldiers", [int(restored.soldier_count()), soldiers_before]): return
	var reloaded_arrived: Dictionary = _army(reloaded.data.site, party_team)
	var reloaded_captain := int(reloaded_arrived.units[int(reloaded_arrived.formal_commander)].person_id)
	if not _check(bool(reloaded_arrived.get("crowd", false)) and reloaded_captain == arrival_leader, "the reloaded roster is crowd=true with the leader as captain", {"expected": arrival_leader, "actual": reloaded_captain}): return
	if player_case:
		if not _player_state_checks(reloaded.data.site, arrival_leader): return
		if not _player_native_checks(reloaded.data.site, restored, arrival_leader): return

	print("REGION_CROWD_ARRIVAL_PASS: ", checks, " checks (case ", case_name, "); an ordinary three-person party joins the live crowd Site as a native team with its leader as captain, the Site validates and reloads, duplicate, garrisoned and actor arrivals are refused with unchanged files, and the party can return to the Site it left through its own native slots")
	quit(0)
