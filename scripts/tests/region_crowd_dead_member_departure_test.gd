extends SceneTree
## Decision A2 on crowd (2026-11-10): a crowd team departs with a fallen member. A three-person native crowd team loses one
## member through the original environment damage owner, then checks:
## - while the fallen member's remains are unsettled, the team plan refuses (NOT_READY) and nobody is released;
## - after the original death owner settles the remains (loot_settled), the plan passes with the living as `people` and the
##   fallen as `inert`, and the controlled captain is never inert;
## - release takes every living and fallen member out of native membership and the Site maps (the fallen through
##   site_person_release_dead), the travelling roster keeps the fallen row (hp 0, loot_settled), and Travel.extract carries
##   it as an inert row while the living travel;
## - a Site capture after the departure omits the team.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_DEAD_MEMBER_DEPARTURE_PASS on success; quit(1) on any failure.

const Store = preload("res://scripts/terrain_lab/site_store.gd")

var checks := 0
var lab: TerrainLab

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_DEAD_MEMBER_DEPARTURE_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_DEAD_MEMBER_DEPARTURE OK ", checks, ": ", message)
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
	var centre: Vector2i = lab.terrain.spawn_cell
	var friendly_cells: Array[Vector2i] = [centre + Vector2i(-1, 3), centre + Vector2i(0, 3), centre + Vector2i(1, 3)]
	var enemy_cells: Array[Vector2i] = [centre + Vector2i(-1, -40), centre + Vector2i(0, -40)]
	var sides: Array[Dictionary] = [_side(friendly_cells.size(), 0), _side(enemy_cells.size(), 1)]
	if not _check(sides[0].size() > 0 and sides[1].size() > 0, "both original sides exist"): return
	var entered: Dictionary = lab.crowd_site.deploy(sides, [friendly_cells, enemy_cells])
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "two-faction native crowd activates", entered): return
	var crowd: Variant = lab.crowd_site
	if not _check(crowd.crowd.has_method("site_person_release_dead"), "the native build has the dead-member release"): return

	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0: roster = candidate
	if not _check(not roster.is_empty() and roster.units.size() == 3, "the friendly crowd team has three roster rows"): return
	var captain: int = int(roster.units[int(roster.formal_commander)].person_id)
	var team_id: int = int(roster.team_id)
	var members: Array[int] = []
	for unit: Dictionary in roster.units: members.append(int(unit.person_id))
	var fallen: int = -1
	for identity: int in members:
		if identity != captain: fallen = identity
	var living: Array[int] = members.duplicate()
	living.erase(fallen)
	var native_index := {}
	for identity: int in members: native_index[identity] = int(crowd._index_by_id[identity])

	# The member falls through the original environment damage owner; its death is queued for the original remains owner.
	crowd.apply_environment_damage(fallen, 1000.0)
	crowd.settle_events()
	var fallen_person: Dictionary = lab.site_controller.person_actions._person(fallen, false)
	if not _check(not fallen_person.is_empty() and float(fallen_person.hp) <= 0.0, "the member has fallen", fallen_person.get("hp")): return
	if not _check(lab.site_controller._pending_deaths.has(fallen), "the original death owner queued the fallen member's remains", lab.site_controller._pending_deaths.keys()): return

	# Unsettled remains: the plan refuses and nobody is released.
	var refused: Dictionary = crowd.departure_plan(captain)
	if not _check(not refused.get("ok", true) and str(refused.get("code", "")) == "NOT_READY", "unsettled remains refuse the team plan", refused): return
	for identity: int in members:
		if not _check(crowd.contains_person(identity), "refusal keeps every member native", identity): return

	# The original owner settles the remains once the down pose has run.
	lab.site_controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 1.0)
	fallen_person = lab.site_controller.person_actions._person(fallen, false)
	if not _check(not lab.site_controller._pending_deaths.has(fallen) and bool(lab.site_controller.person_actions._body_get(fallen_person, "loot_settled")),
		"the original death owner settles the fallen member's remains"): return

	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(captured.get("ok", false), "the Site captures its crowd before departure", captured): return
	var plan: Dictionary = crowd.departure_plan(captain)
	var planned_people: Array = plan.get("people", []).duplicate()
	planned_people.sort()
	var expected_living: Array = living.duplicate()
	expected_living.sort()
	if not _check(plan.get("ok", false) and planned_people == expected_living and plan.get("inert", []) == [fallen], "settled remains pass the plan: the living depart, the fallen is inert", plan): return
	var probe: Dictionary = RegionTravel.extract(lab.terrain.site.duplicate(true), _spec(captain, team_id), "crowd_dead_member_probe")
	if not _check(probe.get("ok", false), "Travel.extract accepts the team with its fallen member on a copy", probe): return

	var released: Dictionary = crowd.departure_release(plan)
	if not _check(released.get("ok", false) and int(released.released) == members.size(), "the living and the fallen are released", released): return
	for identity: int in members:
		if not _check(not crowd.contains_person(identity) and crowd.person_owner(identity) == null, "a released member leaves the Site maps", identity): return
		if not _check(not crowd.crowd.site_person_exit_ready(int(native_index[identity])) and not crowd.crowd.site_person_release_dead(int(native_index[identity])).size() > 0,
			"a released member cannot be released again natively", identity): return
	var fallen_row: Dictionary = {}
	for unit: Dictionary in released.army.units:
		if int(unit.person_id) == fallen: fallen_row = unit
	if not _check(not fallen_row.is_empty() and float(fallen_row.get("hp", 1.0)) <= 0.0 and bool(fallen_row.get("loot_settled", false)), "the travelling army keeps the fallen row, dead and settled", fallen_row.keys()): return

	var saved: Dictionary = crowd.capture_save()
	if not _check(saved.get("ok", false), "the Site still captures after the departure", saved): return
	for row: Dictionary in saved.rosters:
		if not _check(int(row.team_id) != team_id, "the saved crowd rosters omit the departed team"): return
	var departing: Dictionary = RegionTravelSite._grid_party_army(lab, released.army)
	departing["crowd"] = true
	saved.rosters.append(departing)
	lab.site_controller._apply_region_crowd_capture(saved)
	var extracted: Dictionary = RegionTravel.extract(lab.terrain.site.duplicate(true), _spec(captain, team_id), "crowd_dead_member_departure")
	if not _check(extracted.get("ok", false), "the departure extraction succeeds after release", extracted): return
	var party_ids: Array[int] = []
	for army: Dictionary in extracted.party.content.armies:
		for unit: Dictionary in army.units: party_ids.append(int(unit.person_id))
	party_ids.sort()
	var expected_all: Array[int] = members.duplicate()
	expected_all.sort()
	if not _check(party_ids == expected_all, "the travel party carries the living and the fallen row", party_ids): return
	var inert: Dictionary = RegionTravel._inert_people(extracted.party.content, captain)
	if not _check(inert.has(fallen) and inert.size() == 1, "the fallen row travels inert (Decision A2)", inert.keys()): return

	print("REGION_CROWD_DEAD_MEMBER_DEPARTURE_PASS: ", checks, " checks; unsettled remains refuse, settled remains travel inert with the living, native dead release, Site capture omits the team")
	quit(0)
