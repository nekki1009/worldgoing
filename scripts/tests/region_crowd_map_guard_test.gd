extends SceneTree
## R9: party map motion under an active crowd. Activates two friendly crowd teams and one far enemy on the formal
## TerrainLab scene, whole-team departs one friendly team, then checks the crowd-only map guard with the remaining crowd:
## - the remaining crowd still keeps the origin active and the controlled body resolves as a target;
## - the crowd-only guard passes with no open action;
## - the remaining friendly crowd cells are ours, and an enemy inside RegionTravelSite.ENEMY_RADIUS counts as hostile;
## - a pending captivity event refuses with PENDING_EVENT.
## The full party proof (region_original_party_runtime_proof) and prepare_region_party_map_motion need a travelling
## party fixture and are not run here.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_MAP_GUARD_PASS on success; quit(1) on any failure.

const CROWD_TEST_TIMEOUT := 300.0

var checks := 0
var lab: TerrainLab

func _initialize() -> void:
	create_timer(CROWD_TEST_TIMEOUT).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_MAP_GUARD_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_MAP_GUARD OK ", checks, ": ", message)
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

func _code(result: Dictionary) -> String:
	return str(result.get("code", "")) if not result.ok else "OK"

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
	# Two friendly teams and one enemy team far outside ENEMY_RADIUS, so the start is not in combat.
	var first_cells: Array[Vector2i] = [centre + Vector2i(-1, 3), centre + Vector2i(0, 3)]
	var second_cells: Array[Vector2i] = [centre + Vector2i(2, 3), centre + Vector2i(3, 3)]
	var enemy_cells: Array[Vector2i] = [centre + Vector2i(-1, -40), centre + Vector2i(0, -40)]
	var sides: Array[Dictionary] = [_side(first_cells.size(), 0), _side(second_cells.size(), 0), _side(enemy_cells.size(), 1)]
	if not _check(sides[0].size() > 0 and sides[1].size() > 0 and sides[2].size() > 0, "all three original sides exist"): return
	var formations: Array = [first_cells, second_cells, enemy_cells]
	var entered: Dictionary = lab.crowd_site.deploy(sides, formations)
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "two friendly teams and an enemy activate the native crowd", entered): return

	var crowd: Variant = lab.crowd_site
	var departing: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0 and candidate.units.size() == first_cells.size():
			departing = candidate
			break
	if not _check(not departing.is_empty(), "the first friendly crowd team has its roster"): return
	var captain: int = int(departing.units[int(departing.formal_commander)].person_id)
	var departing_ids: Array[int] = []
	for unit: Dictionary in departing.units: departing_ids.append(int(unit.person_id))
	var controlled: int = lab.controlled_person_id()
	if not _check(not departing_ids.has(controlled), "fixture: the controlled body is not in the departing team", controlled): return

	# Whole-team departure of the first friendly team.
	var plan: Dictionary = crowd.departure_plan(captain)
	if not _check(plan.get("ok", false) == true, "the ready first friendly team passes the departure plan", plan): return
	var released: Dictionary = crowd.departure_release(plan)
	if not _check(released.get("ok", false) == true, "the first friendly team is released", released): return
	if not _check(lab.crowd_site.active, "the remaining crowd keeps the origin Site active after the departure"): return

	# The controlled body remains a resolvable target while the crowd is active.
	var target: Dictionary = lab.controlled_target()
	if not _check(not target.is_empty(), "the controlled body resolves as a combat target under the remaining crowd", controlled): return
	var faction: int = int(target.owner.faction_id)
	if not _check(faction == 0, "the controlled body belongs to the friendly faction", faction): return

	# Crowd-only guard: no open action, so it passes.
	print("REGION_CROWD_MAP_GUARD raw: projectiles=", crowd.has_projectiles(), " fire_host=", crowd.fire_host_active(),
		" siege_busy=", (crowd.crowd != null and bool(crowd.crowd.siege_busy())), " work_point=", crowd.work_fatigue_point_active(),
		" pending=", crowd.pending_captivity.size())
	var guard: Dictionary = lab.region_party_map_crowd_guard()
	if not _check(guard.get("ok", false) == true, "the crowd-only map guard passes with the remaining crowd and no open action",
			_code(guard) + ": " + str(guard.get("message", ""))): return

	# Our cells come from the remaining friendly crowd members, and the enemy crowd counts as hostile within ENEMY_RADIUS.
	# Expected living friendly crowd persons: the remaining team's roster members plus the controlled body when it is a
	# crowd solo actor outside that roster. The departed team is excluded by identity.
	var expected_ids: Array[int] = []
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) != 0 or int(candidate.team_id) == int(departing.team_id): continue
		for unit: Dictionary in candidate.units:
			if not expected_ids.has(int(unit.person_id)): expected_ids.append(int(unit.person_id))
	if crowd.contains_person(controlled) and not expected_ids.has(controlled): expected_ids.append(controlled)
	var ours: Array[Vector2i] = lab.region_party_map_crowd_cells(0)
	print("REGION_CROWD_MAP_GUARD cells: expected=", expected_ids.size(), " actual=", ours.size(), " expected_ids=", expected_ids)
	if not _check(ours.size() == expected_ids.size(), "the living remaining friendly crowd persons supply the party cells (expected %d, actual %d)" % [expected_ids.size(), ours.size()], expected_ids.size()): return
	if not _check(not RegionTravelSite._hostile_near(lab, 0, ours), "the remaining friendly crowd is not hostile to itself at the far enemy distance"): return
	var near_enemy: Array[Vector2i] = [enemy_cells[0] + Vector2i(0, RegionTravelSite.ENEMY_RADIUS - 2)]
	if not _check(RegionTravelSite._hostile_near(lab, 0, near_enemy), "a crowd enemy within ENEMY_RADIUS is hostile to the party cells (IN_COMBAT path)"): return

	# A pending captivity event refuses the map motion with PENDING_EVENT.
	var pending_before: int = lab.crowd_site.pending_captivity.size()
	lab.crowd_site.pending_captivity.append({"kind": "crowd_map_guard_test", "person": controlled, "other": -1, "ammo_synced": false})
	var pending: Dictionary = lab.region_party_map_crowd_guard()
	if not _check(not pending.ok and _code(pending) == "PENDING_EVENT", "a pending captivity refuses with PENDING_EVENT", _code(pending)): return
	lab.crowd_site.pending_captivity.resize(pending_before)

	print("REGION_CROWD_MAP_GUARD_PASS: ", checks, " checks; crowd-only guard passes with the remaining crowd, controlled target resolves, friendly cells and hostility check, pending captivity refuses; full party proof and prepare_region_party_map_motion not exercised")
	quit(0)
