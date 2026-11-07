extends "res://scripts/tests/region_crowd_offscreen_step_test.gd"
## NPCDISPATCH v1 (2026-11-08): NPC Nation dispatch from a live crowd Site, by land, to the neighbouring Site.
## Rule (party-travel survey R11, command center): the whole team leaves, led by its roster captain, as the player's
## whole-team departure; a team holding the controlled person is refused. Steps:
## - bind a live crowd Site to a Region slot; the player's start team stays (faction 0); a three-person NPC team deploys;
## - the NPC captain heads a Nation with nation.dispatch and observes the neighbouring Site;
## - the team holding the controlled person is refused RELATION_OPEN with the live Site unchanged;
## - prepare_npc_region_dispatch admits the NPC team (land) with every refusal decided before the live Site changes;
## - commit publishes the party and rebinds the live Site from the published origin: the three people left the live crowd
##   natively, the player keeps control, and the origin saves and reloads;
## - shared steps carry the party to the neighbouring Site, where the same three people stand as one team.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_NPC_DISPATCH_PASS on success; quit(1) on any failure. Deadline 420 s (in-file).

const PhaseAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const TEAM_SIZE := 3
const GOAL := Vector2i(1, 0)
const STEP_LIMIT := 20000

func _initialize() -> void:
	out = "res://.godot-temp/region_crowd_npc_dispatch/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(420.0).timeout.connect(func() -> void: _fail("420-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_NPC_DISPATCH_FAIL: ", message, " ", str(detail))
	push_error("REGION_CROWD_NPC_DISPATCH_FAIL: " + message + " " + str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_NPC_DISPATCH OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

## The roster of `team_id` in the live crowd, or {}.
func _roster(team_id: int) -> Dictionary:
	for roster: Dictionary in lab.crowd_site.rosters:
		if int(roster.team_id) == team_id: return roster
	return {}

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	if not _write_manifest(): return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "formal TerrainLab instance exists"): return
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	controller = lab.site_controller
	_freeze(lab)
	var world_id := "r0_crowd_npc_dispatch_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds a pinned Region world", opened): return
	_freeze(lab)
	slot = controller.region_slot
	site_id = str(lab.terrain.site.id)
	var wired: Dictionary = lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok, "the Slot adapters wire the live owner", wired): return
	var player := lab.controlled_person_id()
	var centre: Vector2i = lab.terrain.spawn_cell
	var cells: Array[Vector2i] = []
	for offset: int in range(-1, 2): cells.append(centre + Vector2i(offset, 4))
	var cleared: Dictionary = lab.crowd_site.clear()
	if not _check(cleared.get("ok", false) == true and not lab.crowd_site.active, "the player's crowd team returns to its holder before the NPC team deploys", cleared): return
	for team: TerrainArmy in lab.combat_armies:
		if team.has_army() and team.combat_identity(0) == player: team.faction_id = 0
	var entered: Dictionary = lab.crowd_site.deploy([_side(TEAM_SIZE, 0)], [cells])
	if not _check(entered.get("ok", false) == true and lab.crowd_site.active, "the NPC crowd team deploys beside the player's team", entered): return
	var team_id := -1
	var player_team := -1
	for roster: Dictionary in lab.crowd_site.rosters:
		var ids: Array[int] = []
		for unit: Dictionary in roster.units: ids.append(int(unit.person_id))
		if ids.has(player): player_team = int(roster.team_id)
		elif ids.size() == TEAM_SIZE: team_id = int(roster.team_id)
	if not _check(team_id > 0 and player_team > 0, "the NPC team and the player's start team have crowd rosters", {"npc": team_id, "player": player_team}): return
	var roster: Dictionary = _roster(team_id)
	var members: Array[int] = []
	for unit: Dictionary in roster.units: members.append(int(unit.person_id))
	var captain := int(roster.units[int(roster.formal_commander)].person_id)
	var nation_id := "crowd_npc_nation_%d" % OS.get_process_id()
	if not lab.terrain.site.has("equipment_nations"): lab.terrain.site.equipment_nations = {}
	lab.terrain.site.equipment_nations[nation_id] = {"members": members.duplicate(), "standards": {}, "offices": SiteOffices.default_offices("nation", captain, true)}
	var target_id := Grid.site_id(str(slot.pin.atlas_id), GOAL)
	# The destination's cold owner exists and is published before the party arrives (as the original dispatch tests
	# bind their destination first).
	var destination_owner: Dictionary = lab._region_gameplay_owner_lab(target_id, "cold_exact")
	if not _check(destination_owner.ok and destination_owner.lab is TerrainLab, "the neighbouring Site has its cold owner", destination_owner.get("code")): return
	_freeze(destination_owner.lab)
	var checkpoint: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(checkpoint.ok, "the live crowd Site checkpoints with its Nation and the cold destination", checkpoint): return
	var at := float(slot.control.logical_game_seconds)
	var observed: Dictionary = PhaseAI.observe(slot.region_registry(), {"id": "crowd_npc_known_target", "source": "site_observation", "observer": captain, "receiver": captain,
		"observer_scope": site_id, "receiver_scope": site_id, "object_scope": target_id, "object": target_id,
		"value": {"power": 1.0}, "game_time": at, "expires_at": at + 86400.0})
	if not _check(observed.ok, "the NPC captain holds a scoped observation of the neighbouring Site", observed): return
	var body: Dictionary = lab.crowd_site.person_owner(captain).person(int(lab.crowd_site.person_owner(captain).index_for_identity(captain)), false)
	var component := RegionTravelSite.start_component(slot, Vector2i.ZERO, body.cell, lab.terrain)
	if not _check(component >= 0, "the captain's cell has a land route out of the Site", component): return

	# The team that holds the controlled person cannot be sent by an NPC Nation.
	var before := var_to_bytes([lab.terrain.site.get("crowd", {}), lab.crowd_site.crowd.state_hash()])
	var refused: Dictionary = slot.prepare_npc_region_dispatch(lab, nation_id, player_team, GOAL, component, [], "crowd_npc_refused_%d" % OS.get_process_id())
	if not _check(not refused.ok and str(refused.get("code", "")) in ["RELATION_OPEN", "NO_AUTHORITY", "NOT_MEMBER"], "dispatching the controlled person's team is refused", refused): return
	if not _check(lab.crowd_site.contains_person(player) and lab.controlled_person_id() == player, "the refusal leaves the player's team live"): return

	var token := "crowd_npc_dispatch_%d" % OS.get_process_id()
	var hash_before: int = int(lab.crowd_site.crowd.state_hash())
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, nation_id, team_id, GOAL, component, [], token)
	if not _check(prepared.get("ok", false) == true and str(prepared.party.get("mode", "land")) == "land", "the NPC Nation prepares a whole-team land dispatch from the crowd Site", prepared): return
	var party_people: Array = prepared.party.person_ids.duplicate()
	party_people.sort()
	var expected: Array = members.duplicate()
	expected.sort()
	if not _check(party_people == expected and prepared.party.content.actors.is_empty(), "the party is exactly the three NPC team people", prepared.party.person_ids): return
	for member: int in members:
		if not _check(lab.crowd_site.contains_person(member), "prepare leaves the live crowd unchanged", member): return
	if not _check(int(lab.crowd_site.crowd.state_hash()) == hash_before, "prepare does not touch the live native World"): return
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	if not _check(committed.get("ok", false) == true and str(slot.region_registry().parties[token].phase) == "travelling", "the commit publishes one travelling NPC party", committed): return
	if not _check(lab.crowd_site != null and lab.crowd_site.active and lab.controlled_person_id() == player and lab.crowd_site.contains_person(player), "the rebound live Site keeps the player's crowd team and control"): return
	for member: int in members:
		if not _check(not lab.crowd_site.contains_person(member) and lab.crowd_site.person_owner(member) == null, "a dispatched person left the live crowd", member): return
	var saved: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "the origin checkpoints after the dispatch", saved): return
	var effective: Dictionary = slot.effective_site_path(Vector2i.ZERO)
	var reread: Dictionary = slot._load_checked(str(effective.get("path", "")), Vector2i.ZERO)
	if not _check(effective.ok and reread.get("ok", false) == true, "the origin reloads through the slot read path", reread.get("code")): return

	# Shared steps carry the party to the neighbouring Site.
	var steps := 0
	while str(slot.region_registry().parties[token].phase) != "entered":
		steps += 1
		if not _check(steps < STEP_LIMIT, "the party reaches its destination within the step bound", slot.region_registry().parties[token]): return
		var stepped: Dictionary = lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP)
		if not _check(stepped.get("ok", false) == true, "a shared step advances the world", stepped): return
		if steps % 60 == 0: await process_frame
	var reference: Dictionary = slot.region_registry().parties[token]
	var mapping: Dictionary = reference.arrival_mapping.maps
	var destination: Dictionary = lab._region_gameplay_owner_lab(target_id, "cold_exact")
	if not _check(destination.ok and destination.lab is TerrainLab, "the destination has its owner Lab", destination.get("code")): return
	var arrived: TerrainLab = destination.lab
	for member: int in members:
		var local := int(mapping.person[str(member)])
		var target: Dictionary = arrived._original_person_target(local) if arrived.has_method("_original_person_target") else {}
		var held: bool = arrived.crowd_site != null and arrived.crowd_site.active and arrived.crowd_site.contains_person(local)
		if not _check(held or not target.is_empty(), "the dispatched person stands in the destination Site", {"source": member, "local": local}): return
	print("REGION_CROWD_NPC_DISPATCH_PASS: ", checks, " checks; ", steps, " shared steps")
	quit(0)
