extends SceneTree
## G6.4b: a crowd team departs Region travel. Activates a two-faction native crowd on the formal TerrainLab scene, then checks:
## - a refused departure (a member knocked out) releases nobody: every member is still a native member;
## - the captain team's plan passes, and the pre-validated Travel.extract probe accepts the team;
## - release takes every member out of native membership, neighbour and exchange checks, and out of the Site maps;
## - the travelling team keeps its appearance and item_state rows, and the travel party carries them;
## - a Site capture after the departure omits the released people from the crowd section and rosters.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_DEPARTURE_PASS on success; quit(1) on any failure.

const AI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")

var checks := 0
var lab: TerrainLab

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_DEPARTURE_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_DEPARTURE OK ", checks, ": ", message)
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

func _spec(identity: int, team_id: int) -> Dictionary:
	return {"person_id": identity, "actor_key": "", "team_id": team_id, "controller": "player", "mode": "land",
		"crowd_departure": true, "game_seconds": 0.0}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
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
	# The enemy sits far outside ENEMY_RADIUS so the combat check does not block the departure.
	var friendly_cells: Array[Vector2i] = [centre + Vector2i(-1, 3), centre + Vector2i(0, 3)]
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
	var captain: int = int(roster.units[int(roster.formal_commander)].person_id)
	var team_id: int = int(roster.team_id)
	var members: Array[int] = []
	var native_index := {}
	var before := {}
	for unit: Dictionary in roster.units:
		var identity := int(unit.person_id)
		members.append(identity)
		native_index[identity] = int(crowd._index_by_id[identity])
		before[identity] = {"appearance": unit.appearance.duplicate(true), "item_state": unit.item_state.duplicate(true)}
	if not _check(not before[captain].appearance.is_empty(), "the captain team row carries its appearance"): return

	# Refusal: a member knocked out is not ready, so the whole departure refuses and nobody is released.
	var knocked: int = members[members.size() - 1]
	if not _check(crowd.set_soldier_fields(native_index[knocked], {"ko": 5.0}), "a member can be knocked out for the refusal check"): return
	var refused: Dictionary = crowd.departure_plan(captain)
	if not _check(refused.get("ok", true) == false and refused.get("code", "") == "NOT_READY", "a knocked-out member refuses the team plan", refused): return
	var refused_release: Dictionary = crowd.departure_release(refused)
	if not _check(refused_release.get("ok", true) == false, "a refused plan releases nothing"): return
	for identity: int in members:
		var owner: Variant = crowd.person_owner(identity)
		if not _check(owner != null and owner.is_member(native_index[identity]), "refusal keeps every member native", identity): return
	if not _check(crowd.set_soldier_fields(native_index[knocked], {"ko": 0.0}), "the knocked member recovers before the departure"): return

	# Pre-validation: capture the Site, then prove the whole extraction on a copy before any release.
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(captured.get("ok", false), "the Site captures its crowd before departure", captured): return
	var plan: Dictionary = crowd.departure_plan(captain)
	if not _check(plan.get("ok", false) == true, "the ready captain team passes the departure plan", plan): return
	if not _check(plan.people.size() == members.size(), "the plan names every team member", plan.people): return
	var probe: Dictionary = RegionTravel.extract(lab.terrain.site.duplicate(true), _spec(captain, team_id), "crowd_departure_probe")
	if not _check(probe.get("ok", false) == true, "Travel.extract accepts the crowd team on a copy", probe): return

	# Remaining soldiers (everyone outside the team, including the controlled body) keep their ids and positions.
	var remaining_before := {}
	for key: Variant in crowd._index_by_id.keys():
		if members.has(int(key)): continue
		var before_state: Dictionary = crowd.soldier_state(int(crowd._index_by_id[key]))
		remaining_before[int(key)] = [float(before_state.px), float(before_state.py)]
	var soldiers_before: int = int(crowd.crowd.soldier_count())
	var ids_before: PackedInt64Array = crowd.crowd.person_ids()

	# Release: every member leaves native membership, neighbour and exchange checks, and the Site maps.
	var released: Dictionary = crowd.departure_release(plan)
	if not _check(released.get("ok", false) == true and int(released.released) == members.size(), "every planned member is released", released): return
	for identity: int in members:
		var index: int = native_index[identity]
		if not _check(not crowd.crowd.site_person_exit_ready(index), "a released member is not exit-ready natively", identity): return
		if not _check(not crowd.contains_person(identity) and crowd.person_owner(identity) == null, "a released member leaves the Site maps", identity): return
	var travelling: Dictionary = released.roster.duplicate(true)
	for unit: Dictionary in travelling.units:
		var identity := int(unit.person_id)
		if not _check(unit.appearance == before[identity].appearance, "the travelling row keeps its appearance", identity): return
		if not _check(unit.item_state == before[identity].item_state, "the travelling row keeps its item_state", identity): return
		if not _check(unit.crowd_position is Array and unit.crowd_position.size() == 2, "the released row carries its position receipt", identity): return

	# The Site save after the departure omits the released team.
	var saved: Dictionary = crowd.capture_save()
	if not _check(saved.get("ok", false) == true, "the Site still captures after the departure", saved): return
	for row: Dictionary in saved.rosters:
		if not _check(int(row.team_id) != team_id, "the saved crowd rosters omit the departed team"): return
	for entry: Dictionary in saved.section.teams:
		if int(entry.team_id) != team_id: continue
		if not _check(bool(entry.get("departed", false)) and entry.person_ids.size() == members.size(), "the saved crowd section keeps only a departed tombstone for the team"): return

	# The travel party carries the team's equipment and appearance intact (the probe ran on the pre-release copy).
	saved.rosters.append(travelling)
	lab.site_controller._apply_region_crowd_capture(saved)
	var extracted: Dictionary = RegionTravel.extract(lab.terrain.site.duplicate(true), _spec(captain, team_id), "crowd_departure_test")
	if not _check(extracted.get("ok", false) == true, "the departure extraction succeeds after release", extracted): return
	var party_armies: Array = extracted.party.content.armies
	if not _check(party_armies.size() == 1 and party_armies[0].units.size() == members.size(), "the travel party carries the whole team", party_armies.size()): return
	for index: int in range(members.size()):
		var party_unit: Dictionary = party_armies[0].units[index]
		var identity: int = members[index]
		if not _check(party_unit.appearance == before[identity].appearance, "the travel party keeps the appearance", identity): return
		if not _check(party_unit.item_state == before[identity].item_state, "the travel party keeps the item_state", identity): return
	for army: Dictionary in extracted.origin.get("armies", []):
		if not _check(int(army.get("team_id", -1)) != team_id, "the Site left behind has no departed team roster"): return
	# The enemy crowd team stays behind, so the Site keeps its crowd section without the departed team.
	var left_section: Dictionary = extracted.origin.get("crowd", {})
	if not _check(not left_section.is_empty(), "the Site left behind keeps the remaining crowd section"): return
	for entry: Dictionary in left_section.get("teams", []):
		if int(entry.team_id) != team_id: continue
		if not _check(bool(entry.get("departed", false)), "the remaining crowd section marks the departed team as a tombstone"): return

	# Full Site save -> load after the departure. The Site is the extracted origin: the state begin_region_travel saves.
	lab.terrain.site = extracted.origin
	DirAccess.make_dir_recursive_absolute("user://sites")
	var path := "user://sites/g64c_departure_test.json"
	var written: Dictionary = Store.save(lab.terrain, path, crowd.crowd)
	if not _check(written.get("ok", false) == true, "the Site saves after the crowd departure", written.get("code", written)): return
	var loaded: Dictionary = Store.load_site(path, Callable(), 1, false)
	if not _check(loaded.get("ok", false) == true, "the Site loads after the crowd departure", loaded.get("code", loaded)): return
	var restored: Variant = loaded.get("crowd_native")
	if not _check(restored is Object and restored.get_class() == &"ArmyCrowd", "the load returns the native crowd"): return
	if not _check(int(restored.soldier_count()) == soldiers_before, "the loaded soldier count matches", int(restored.soldier_count())): return
	if not _check(restored.person_ids() == ids_before, "the loaded person ids match the blob order"): return
	for key: int in remaining_before.keys():
		var index: int = ids_before.find(key)
		var values: PackedFloat64Array = restored.get_soldier_state(index)
		if not _check(values.size() > 15 and values[14] == remaining_before[key][0] and values[15] == remaining_before[key][1], "a remaining soldier keeps its position through the save", key): return
	for army: Variant in loaded.data.site.get("armies", []):
		if not army is Dictionary or not bool(army.get("crowd", false)): continue
		for row: Variant in army.get("units", []):
			for identity: int in members:
				if not _check(int(row.person_id) != identity, "a departed person is absent from the loaded rosters", identity): return
	for entry: Variant in loaded.data.site.crowd.get("teams", []):
		if bool(entry.get("departed", false)): continue
		for identity: int in members:
			if not _check(not entry.person_ids.has(identity), "a departed person is absent from the loaded live teams", identity): return

	print("REGION_CROWD_DEPARTURE_PASS: ", checks, " checks; refusal releases nobody, the preflight and Travel.extract accept the captain team, release clears native and Site maps, travel rows keep equipment and appearance, the saved and reloaded Site omits the team, remaining soldiers keep ids and positions")
	quit(0)
