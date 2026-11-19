extends SceneTree
## G6.5 (2026-11-01): 幹部分隊. The controlled person is a cadre of a live seven-person crowd team (formal captain,
## a second cadre B, four ordinary members). The controlled cadre leads his sub-party, as _depart_crowd does for a whole
## team: spec controller "player" with crowd_split. Checks:
## - an ordinary member as leader is refused CADRE_REQUIRED; the formal captain is refused CAPTAIN_REQUIRED (alone, or as a
##   member of the cadre's sub-party); a second cadre as a member is refused MEMBER_CADRE; refusals release nobody;
## - --case alone: the controlled cadre leaves alone; --case pair: he leaves with two ordinary members. Each case: the
##   party is led by the cadre as formal captain and carries its appearance; the remaining team keeps its captain and
##   consistent indices; control on the Site passes to the player actor body that stays (its fire command row keeps
##   its saved actor owner), and the Site validates through SiteStore after save and reload.
## Run only with: --crowd --crowd-test <fresh_run_id> --case alone|pair
## Output: REGION_CROWD_CADRE_SPLIT_PASS on success; quit(1) on any failure.

const Store = preload("res://scripts/terrain_lab/site_store.gd")

var checks := 0
var lab: TerrainLab

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_CADRE_SPLIT_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_CADRE_SPLIT OK ", checks, ": ", message)
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

## The travel spec of the cadre's sub-party: the controlled cadre leads it, as in _crowd_spec, with the crowd_split flag.
func _spec(identity: int, team_id: int, successor: Dictionary) -> Dictionary:
	return {"person_id": identity, "actor_key": "", "team_id": team_id, "controller": "player", "mode": "land",
		"crowd_departure": true, "crowd_split": true, "crowd_control_successor": successor, "game_seconds": 0.0}

func _index_of(roster: Dictionary, identity: int) -> int:
	for index in range(roster.units.size()):
		if int(roster.units[index].person_id) == identity: return index
	return -1

## Native soldier slots whose formation is `formation` (memberships: [formation, team, troop] per soldier).
func _formation_slots(world: Variant, formation: int) -> int:
	var rows: PackedInt32Array = world.memberships()
	var count := 0
	for index in range(rows.size() / 3):
		if rows[index * 3] == formation: count += 1
	return count

func _team_for(crowd: Variant, team_id: int) -> Dictionary:
	for team: Dictionary in crowd.teams:
		if int(team.team_id) == team_id: return team
	return {}

## Makes the person at `index` a cadre: a native officer (military role, as a cadre must be to command), an officer_service
## entry and, when the team has a free non-head seat, that seat.
func _make_cadre(crowd: Variant, roster: Dictionary, index: int) -> bool:
	var person := int(roster.units[index].person_id)
	if not bool(crowd.native_set_military_role(person, "officer").ok): return false
	for seat: Dictionary in roster.get("offices", {}).get("positions", []):
		if not bool(seat.get("head", false)) and int(seat.get("holder", 0)) <= 0:
			seat["holder"] = person
			break
	var service: Array = roster.get("officer_service", [])
	service.append(index)
	roster["officer_service"] = service
	return true

## The Site a split would produce, proven by Travel.extract on a copy of the captured Site (as depart_crowd_split):
## nothing native or live changes. The party is the converted grid army (split_army_snapshot).
func _probe(crowd: Variant, plan: Dictionary, team_id: int, successor: Dictionary) -> Dictionary:
	var converted: Dictionary = crowd.split_army_snapshot(plan, team_id)
	if not converted.ok: return converted
	var site: Dictionary = lab.terrain.site.duplicate(true)
	var party: Dictionary = converted.snapshot.duplicate(true)
	party["crowd"] = true
	site.armies.append(party)
	return RegionTravel.extract(site, _spec(int(plan.people[0]), team_id, successor), "cadre_split_probe")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	var case_name := str(args[args.find("--case") + 1]) if args.has("--case") and args.find("--case") + 1 < args.size() else "alone"
	if not _check(case_name in ["alone", "pair"], "--case must be alone or pair", case_name): return
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
	# Seven friendly soldiers in one row; the enemy sits far outside ENEMY_RADIUS so the combat check does not block.
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
	# The deploy makes the captain the controlled person. Control moves to the first non-captain soldier through the
	# existing control-change owner (as crowd_c2_clear_handoff_test does), and that soldier leads the sub-party.
	var leader := -1
	for unit: Dictionary in roster.units:
		if int(unit.person_id) != captain and leader < 0: leader = int(unit.person_id)
	var switched: Dictionary = crowd.on_control_changed(lab.controlled_person_id(), leader)
	if not _check(switched.ok, "control moves to a chosen non-captain soldier", switched): return
	lab.terrain.site["controlled_person_id"] = leader
	if not _check(lab.controlled_person_id() == leader and leader != captain, "the controlled person is a non-captain soldier of the friendly team", leader): return
	var second := -1
	var ordinary: Array[int] = []
	for unit: Dictionary in roster.units:
		var identity := int(unit.person_id)
		if identity == captain or identity == leader: continue
		if second < 0: second = identity
		else: ordinary.append(identity)
	# The controlled person and the second person become cadres; the rest are ordinary members.
	if not _check(_make_cadre(crowd, roster, _index_of(roster, leader)) and _make_cadre(crowd, roster, _index_of(roster, second)), "both cadres are native officers"): return
	var before := {}
	var native_index := {}
	for unit: Dictionary in roster.units:
		var identity := int(unit.person_id)
		before[identity] = unit.appearance.duplicate(true)
		native_index[identity] = int(crowd._index_by_id[identity])
	var rosters_before: int = crowd.rosters.size()
	# The native World holds every soldier (this team, the player actor body's solo formation, the enemy side); a released
	# soldier keeps its slot. The team formation holds the seven, and its native roster counts the people not released.
	var world_slots := int(crowd.crowd.soldier_count())
	var team_formation := int(_team_for(crowd, team_id).formation)
	if not _check(_formation_slots(crowd.crowd, team_formation) == 7 and int(crowd.crowd.formation_info(team_formation)[4]) == 7, "the native team formation holds seven soldiers on its roster before the split"): return

	# Refusals: each one changes nothing.
	var refused: Dictionary = crowd.split_departure_plan(ordinary[0], [])
	if not _check(refused.get("code", "") == "CADRE_REQUIRED", "an ordinary member as leader is refused CADRE_REQUIRED", refused): return
	refused = crowd.split_departure_plan(captain, [])
	if not _check(refused.get("code", "") == "CAPTAIN_REQUIRED", "the formal captain alone is refused CAPTAIN_REQUIRED", refused): return
	refused = crowd.split_departure_plan(leader, [captain])
	if not _check(refused.get("code", "") == "CAPTAIN_REQUIRED", "a sub-party naming the formal captain is refused CAPTAIN_REQUIRED", refused): return
	refused = crowd.split_departure_plan(leader, [second])
	if not _check(refused.get("code", "") == "MEMBER_CADRE", "a second cadre cannot ride as a member", refused): return
	if not _check(crowd.rosters.size() == rosters_before and roster.units.size() == 7, "refusals leave the roster whole"): return
	# Unreleased means still on the Site maps with an owner (site_person_exit_ready is not a release flag: it also refuses
	# the host-controlled leader).
	for identity: int in native_index.keys():
		if not _check(crowd.contains_person(identity) and crowd.person_owner(identity) != null, "refusals release nobody", identity): return

	# The sub-party: alone, or with two ordinary members.
	var group: Array[int] = [leader]
	if case_name == "pair":
		group.append(ordinary[0])
		group.append(ordinary[1])
	var expected_remaining: Array[int] = []
	for unit: Dictionary in roster.units:
		if not group.has(int(unit.person_id)): expected_remaining.append(int(unit.person_id))
	expected_remaining.sort()
	var plan: Dictionary = crowd.split_departure_plan(leader, group.slice(1))
	if not _check(plan.get("ok", false) == true and plan.people.size() == group.size() and int(plan.people[0]) == leader, "the cadre's sub-party passes the split plan", plan): return
	# The full Site capture of depart_crowd_split (as _depart_crowd): it writes the player actor body, which stays.
	var site_captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(site_captured.get("ok", false) == true, "the Site captures its actors and crowd before the split", site_captured): return
	var body := int(lab.character.person_id)
	if not _check(int(lab.terrain.site.get("actors", {}).get("player", {}).get("person_id", -1)) == body and body != leader and not group.has(body), "the captured Site keeps the player actor body outside the sub-party", body): return
	var successor: Dictionary = RegionTravelSite.split_control_successor(lab, leader)
	if not _check(int(successor.get("person_id", -1)) == body and int(successor.get("soldier_index", -1)) == int(crowd._index_by_id[body]), "control passes to the player actor body with its native index", successor): return
	var probe: Dictionary = _probe(crowd, plan, team_id + 1000, successor)
	if not _check(probe.get("ok", false) == true, "Travel.extract accepts the cadre's sub-party on a copy", probe): return
	var released: Dictionary = crowd.split_departure_release(plan, team_id + 1000)
	if not _check(released.get("ok", false) == true and int(released.released) == group.size(), "the sub-party is released", released): return
	# The travelling party is a complete grid army (the same conversion as a whole team's): it restores as a TerrainArmy
	# through the owner lab's restore path, and its formal captain is the cadre.
	var party_army: Dictionary = released.army
	if not _check(party_army.units.size() == group.size() and int(party_army.formal_commander) == 0, "the party's formal captain is the cadre", party_army.get("formal_commander")): return
	if not _check(int(party_army.units[0].person_id) == leader and int(party_army.team_id) == team_id + 1000, "the party's first person is the cadre under the new team id"): return
	var restored_army := TerrainArmy.new()
	restored_army.restore_combat_state(party_army.duplicate(true), lab.terrain, null, null)
	if not _check(restored_army.combat_units.size() == group.size() and restored_army.team_id == team_id + 1000, "the travelling army restores as a TerrainArmy with every member", restored_army.combat_units.size()): return
	if not _check(restored_army.formal_commander == 0 and restored_army.combat_identity(restored_army.formal_commander) == leader, "the restored army's formal commander is the cadre", restored_army.formal_commander): return
	restored_army.free()
	var departing: Dictionary = party_army.duplicate(true)
	departing["crowd"] = true
	for identity: int in group:
		if not _check(not crowd.crowd.site_person_exit_ready(native_index[identity]) and not crowd.contains_person(identity), "a released person is native-released and off the Site maps", identity): return
	var remaining_now: Array[int] = []
	for unit: Dictionary in roster.units: remaining_now.append(int(unit.person_id))
	remaining_now.sort()
	if not _check(remaining_now == expected_remaining, "the team keeps the people outside the sub-party", remaining_now): return
	if not _check(roster.units[int(roster.formal_commander)].person_id == captain, "the team keeps its captain at a consistent index"): return
	var live: Dictionary = _team_for(crowd, team_id)
	if not _check(live.person_ids.size() == expected_remaining.size() and live.departed_person_ids.size() == group.size(), "the live entry names the departed people in departed_person_ids", live): return
	if not _check(not bool(live.get("departed", false)), "the team is not a tombstone after a split"): return

	# Travel: the Site is captured with the party, the party is extracted, and the Site it leaves has no controlled person.
	var captured: Dictionary = crowd.capture_save()
	if not _check(captured.get("ok", false) == true, "the Site captures after the split", captured): return
	captured.rosters.append(departing)
	lab.site_controller._apply_region_crowd_capture(captured)
	var extracted: Dictionary = RegionTravel.extract(lab.terrain.site.duplicate(true), _spec(leader, team_id + 1000, successor), "cadre_split")
	if not _check(extracted.get("ok", false) == true, "the cadre's party extracts from the Site", extracted): return
	var party: Array = extracted.party.content.armies
	if not _check(party.size() == 1 and party[0].units.size() == group.size() and int(party[0].units[0].person_id) == leader, "the party carries the cadre and its members"): return
	if not _check(int(extracted.party.content.controlled_person_id) == leader, "the travelling party carries the controlled cadre"): return
	for unit: Dictionary in party[0].units:
		if not _check(unit.appearance == before[int(unit.person_id)], "the party keeps each appearance", unit.person_id): return
	var left_player: Dictionary = extracted.origin.crowd.player
	if not _check(int(left_player.person_id) == body and int(left_player.soldier_index) == int(successor.soldier_index) and int(extracted.origin.get("controlled_person_id", -1)) == body, "the Site left behind is controlled by the player actor body, not the departed cadre", left_player): return
	if not _check(int(extracted.origin.get("actors", {}).get("player", {}).get("person_id", -1)) == body, "the Site left behind keeps the player actor record"): return
	lab.terrain.site = extracted.origin

	# Save -> load: the Site validates through SiteStore, and the remaining team keeps consistent indices.
	DirAccess.make_dir_recursive_absolute("user://sites")
	var path := "user://sites/cadre_split_%s.json" % case_name
	var written: Dictionary = Store.save(lab.terrain, path, crowd.crowd)
	if not _check(written.get("ok", false) == true, "the Site saves after the split", written): return
	var loaded: Dictionary = Store.load_site(path, Callable(), 1, false)
	if not _check(loaded.get("ok", false) == true, "the Site loads after the split", loaded): return
	var restored: Variant = loaded.get("crowd_native")
	if not _check(restored is Object and restored.get_class() == &"ArmyCrowd", "the load returns the native crowd"): return
	if not _check(int(restored.soldier_count()) == world_slots, "the loaded native crowd keeps every soldier slot of the World", [int(restored.soldier_count()), world_slots]): return
	if not _check(_formation_slots(restored, team_formation) == 7, "the loaded team formation keeps all seven soldier slots", _formation_slots(restored, team_formation)): return
	if not _check(int(restored.formation_info(team_formation)[4]) == 7 - group.size(), "the loaded team formation's native roster drops exactly the sub-party", restored.formation_info(team_formation)): return
	for identity: int in native_index.keys():
		var slot := int(native_index[identity])
		if not _check(int(restored.soldier_index(identity)) == slot, "the loaded soldier keeps its native slot", identity): return
		if group.has(identity) and not _check(not bool(restored.site_person_exit_ready(slot)), "a released soldier stays released after the load", identity): return
	var remaining: Dictionary = {}
	for army: Variant in loaded.data.site.get("armies", []):
		if army is Dictionary and bool(army.get("crowd", false)) and int(army.team_id) == team_id: remaining = army
	if not _check(not remaining.is_empty(), "the loaded remaining team exists"): return
	var loaded_ids: Array[int] = []
	for unit: Dictionary in remaining.units: loaded_ids.append(int(unit.person_id))
	loaded_ids.sort()
	if not _check(loaded_ids == expected_remaining, "the loaded remaining team keeps the people outside the sub-party", loaded_ids): return
	var formal := int(remaining.formal_commander)
	if not _check(formal >= 0 and formal < remaining.units.size() and int(remaining.units[formal].person_id) == captain, "the loaded formal captain index names the captain"): return
	for field: String in ["officers", "officer_service"]:
		for entry: Variant in remaining.get(field, []):
			if not _check(int(entry) >= 0 and int(entry) < remaining.units.size(), "every loaded officer index is in range", entry): return
			if not _check(int(remaining.units[int(entry)].person_id) != leader, "the departed cadre is no longer an officer of the remaining team"): return
	var loaded_live: Dictionary = {}
	for entry: Variant in loaded.data.site.crowd.get("teams", []):
		if int(entry.get("team_id", -1)) == team_id and not bool(entry.get("departed", false)): loaded_live = entry
	if not _check(loaded_live.get("departed_person_ids", []).size() == group.size(), "the loaded live entry keeps the departed people", loaded_live.get("departed_person_ids", [])): return
	if not _check(int(loaded.data.site.crowd.player.person_id) == body and int(loaded.data.site.get("controlled_person_id", -1)) == body, "the loaded Site is controlled by the player actor body", loaded.data.site.crowd.player): return

	print("REGION_CROWD_CADRE_SPLIT_PASS (", case_name, "): ", checks, " checks; ordinary and captain refusals release nobody, the controlled cadre leads his sub-party as formal captain, the remaining captain stays live, control passes to the player body, and the saved and reloaded Site validates with consistent indices")
	quit(0)
