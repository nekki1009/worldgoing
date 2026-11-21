extends SceneTree
## SPLITUI v1 (G6.6): the player's cadre-split entry in the 功能 window, beside 整隊出發. The fixture is the one of
## region_crowd_cadre_split_test (a seven-person crowd team: formal captain, cadre B, the controlled cadre and four ordinary
## members) bound to a Region save slot through open_fixed_world, so depart_crowd_split can begin the sub-party's travel.
## Checks, through the formal UI nodes (DepartCrowdSplit button, CrowdSplitMembers selector, DepartRegionTravel):
## - the formal captain does not see the split entry and keeps 整隊出發;
## - an ordinary member sees the split entry disabled with CADRE_REQUIRED, and a press of it releases nobody;
## - the controlled cadre sees it enabled; the selector lists only the ordinary members; the chosen members (--case pair:
##   two; --case alone: none) are selected and the press departs the cadre with them (the cadre leads, as formal captain);
##   the remaining team keeps its captain, cadre B and the unchosen members.
## Run only with: --crowd --crowd-test <fresh_run_id> [--case alone|pair]   (default pair)
## Output: REGION_CROWD_SPLIT_UI_PASS on success; quit(1) on the first failure. In-file deadline 300 s.

const ShipCoastGenesis = preload("res://scripts/tests/region_ship_coast_legal_named_genesis.gd")

const DT := 1.0 / 30.0
const TEAM_SIZE := 7
const SHIP_SHORE := Vector2i(30, 20)
const DEADLINE_SECONDS := 300.0

var out := ""
var manifest_path := ""
var checks := 0
var lab: TerrainLab
var controller: SiteController
var slot: RegionSaveSlot
var crowd: Variant
var team_id := -1
var captain := -1
var leader := -1
var second := -1
var ordinary: Array[int] = []

func _initialize() -> void:
	out = "res://.godot-temp/region_crowd_split_ui/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(DEADLINE_SECONDS).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_SPLIT_UI_FAIL: ", message, " ", str(detail))
	push_error("REGION_CROWD_SPLIT_UI_FAIL: " + message + " " + str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_SPLIT_UI OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

# region_crowd_ship_journey_ui_test.gd verbatim (the coast fixture calls these).
func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path := out.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

# region_crowd_ship_journey_ui_test.gd verbatim.
func _freeze(scene: TerrainLab) -> void:
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.site_controller.set_process(false)
	scene.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in scene.combat_actors: actor.set_process(false)
	for team: TerrainArmy in scene.combat_armies: team.set_process(false)

func _side(count: int, faction: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side["faction"] = faction
	return side

## TEAM_SIZE land cells two apart on one inland row, free of the original Actors and connected to the shore contact.
func _inland_cells(start: Vector2i) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	for row: int in range(0, 30):
		for column: int in range(0, 30):
			var cells: Array[Vector2i] = []
			var legal := true
			for k: int in range(TEAM_SIZE):
				var cell := start + Vector2i(column + k * 2, row)
				if not lab.terrain.contains(cell) or not lab.terrain.is_walkable(cell) or lab.character.occupies_cell(cell) \
						or lab.npc != null and lab.npc.occupies_cell(cell) or lab.terrain.path_between(cell, SHIP_SHORE).is_empty():
					legal = false
					break
				cells.append(cell)
			if legal: return cells
	return none

func _far_cells(start: Vector2i, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row: int in range(0, 20):
		for column: int in range(0, 20):
			var cell := start - Vector2i(column, row)
			if not lab.terrain.contains(cell) or not lab.terrain.is_walkable(cell) or lab.character.occupies_cell(cell) or lab.npc != null and lab.npc.occupies_cell(cell): continue
			cells.append(cell)
			if cells.size() == count: return cells
	return cells

## Makes `identity` a cadre: a native officer, an officer_service entry and, when the team has a free non-head seat, that seat.
func _make_cadre(roster: Dictionary, identity: int) -> bool:
	if not bool(crowd.native_set_military_role(identity, "officer").ok): return false
	for seat: Dictionary in roster.get("offices", {}).get("positions", []):
		if not bool(seat.get("head", false)) and int(seat.get("holder", 0)) <= 0:
			seat["holder"] = identity
			break
	var index := -1
	for at in range(roster.units.size()):
		if int(roster.units[at].person_id) == identity: index = at
	var service: Array = roster.get("officer_service", [])
	service.append(index)
	roster["officer_service"] = service
	return index >= 0

## Moves control to `identity` through the existing control-change owner (as region_crowd_cadre_split_test does).
func _switch_control(identity: int) -> bool:
	var switched: Dictionary = crowd.on_control_changed(lab.controlled_person_id(), identity)
	if not _check(switched.ok, "control change is accepted", switched): return false
	lab.terrain.site["controlled_person_id"] = identity
	return lab.controlled_person_id() == identity

## The live roster of the friendly team after any split (the departed sub-party leaves this roster).
func _team_roster() -> Dictionary:
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.team_id) == team_id and not bool(candidate.get("departed", false)): return candidate
	return {}

func _team_units() -> Array[int]:
	var ids: Array[int] = []
	for unit: Dictionary in _team_roster().get("units", []): ids.append(int(unit.person_id))
	ids.sort()
	return ids

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	var case_name := str(args[args.find("--case") + 1]) if args.has("--case") and args.find("--case") + 1 < args.size() else "pair"
	if not _check(case_name in ["alone", "pair"], "--case must be alone or pair", case_name): return
	if not ShipCoastGenesis.write(self): return
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
	controller = lab.site_controller
	_freeze(lab)

	# Bind the Site to a Region save slot on the pinned coast: a legal begin_region_travel needs the slot.
	var world_id := "r0_crowd_split_ui_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds the pinned coast World", opened): return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null, "a Region save slot is bound to the Site"): return

	var friendly_cells: Array[Vector2i] = _inland_cells(Vector2i(24, 40))
	if not _check(friendly_cells.size() == TEAM_SIZE, "an inland row of seven free cells connected to the shore exists", friendly_cells): return
	var enemy_cells: Array[Vector2i] = _far_cells(Vector2i(96, 96), 2)
	if not _check(enemy_cells.size() == 2, "two far enemy cells exist", enemy_cells): return
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

	crowd = lab.crowd_site
	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0 and candidate.units.size() == TEAM_SIZE:
			roster = candidate
			break
	if not _check(not roster.is_empty(), "the friendly crowd team has its seven-person roster"): return
	team_id = int(roster.team_id)
	captain = int(roster.units[int(roster.formal_commander)].person_id)
	for unit: Dictionary in roster.units:
		var identity := int(unit.person_id)
		if identity == captain: continue
		if leader < 0: leader = identity
		elif second < 0: second = identity
		else: ordinary.append(identity)
	if not _check(ordinary.size() == TEAM_SIZE - 3, "the team has a captain, a cadre leader, a second cadre and four ordinary members", ordinary): return
	if not _check(_make_cadre(roster, leader) and _make_cadre(roster, second), "both cadres are native officers"): return
	if not _check(_switch_control(leader), "control moves to the non-captain cadre"): return
	controller.update_ui()

	var split_button: Button = lab.find_child("DepartCrowdSplit", true, false)
	var split_members: ItemList = lab.find_child("CrowdSplitMembers", true, false)
	if not _check(split_button != null and split_members != null and controller.region_travel_button != null, "the cadre-split entry and the whole-team button exist in the 功能 window"): return

	# Captain: no split entry; 整隊出發 stays available.
	if not _check(_switch_control(captain), "control moves to the formal captain"): return
	controller.update_ui()
	if not _check(not split_button.visible and not split_members.visible, "the formal captain does not see the split entry"): return
	if not _check(not controller.region_travel_button.disabled, "the formal captain keeps the whole-team departure"): return

	# Ordinary member: the entry is shown disabled with CADRE_REQUIRED; a press releases nobody.
	if not _check(_switch_control(ordinary[0]), "control moves to an ordinary member"): return
	controller.update_ui()
	if not _check(split_button.visible and split_button.disabled, "an ordinary member sees the split entry disabled", controller.crowd_split_status.text): return
	if not _check(controller.crowd_split_status.text.begins_with("CADRE_REQUIRED"), "the ordinary member's entry names CADRE_REQUIRED", controller.crowd_split_status.text): return
	if not _check(controller.region_travel_button.disabled, "an ordinary member cannot use the whole-team departure either"): return
	var units_before := _team_units()
	split_button.pressed.emit()
	if not _check(_team_units() == units_before and units_before.size() == TEAM_SIZE, "a refused split releases nobody", _team_units()): return

	# Cadre: enabled; the selector lists the ordinary members only; the chosen members depart with him.
	if not _check(_switch_control(leader), "control moves back to the cadre"): return
	controller.update_ui()
	if not _check(split_button.visible and not split_button.disabled, "the cadre sees the split entry enabled", controller.crowd_split_status.text): return
	if not _check(split_members.item_count == ordinary.size(), "the selector lists the ordinary members only", split_members.item_count): return
	var chosen: Array[int] = []
	if case_name == "pair": chosen = [ordinary[0], ordinary[1]]
	for at in range(split_members.item_count):
		if chosen.has(int(split_members.get_item_metadata(at))):
			split_members.select(at, false)
			split_members.multi_selected.emit(at, true)
	controller.update_ui()
	if not _check(split_members.get_selected_items().size() == chosen.size(), "the chosen members are selected", split_members.get_selected_items()): return
	if not _check(not split_button.disabled and controller.crowd_split_status.text.begins_with("分隊：可帶"), "the split is allowed with the chosen members", controller.crowd_split_status.text): return

	split_button.pressed.emit()
	if not _check(controller.message.text.begins_with("已分隊出發"), "the press departs the sub-party", controller.message.text): return

	# The sub-party is the cadre and the chosen members; the remaining team keeps its captain, cadre B and the rest.
	var expected: Array[int] = [captain, second]
	for identity: int in ordinary:
		if not chosen.has(identity): expected.append(identity)
	expected.sort()
	var remaining := _team_roster()
	if not _check(not remaining.is_empty(), "the remaining team is still live"): return
	if not _check(_team_units() == expected, "the remaining team holds the captain, cadre B and the unchosen members", {"remaining": _team_units(), "expected": expected}): return
	if not _check(int(remaining.units[int(remaining.formal_commander)].person_id) == captain, "the remaining team keeps its formal captain"): return
	for identity: int in chosen:
		if not _check(not _team_units().has(identity), "chosen member %d left with the cadre" % identity): return
	if not _check(not _team_units().has(leader), "the cadre left the remaining team"): return

	print("REGION_CROWD_SPLIT_UI_PASS: ", checks, " checks; case ", case_name, ": the cadre-split entry is hidden for the captain, disabled with CADRE_REQUIRED for an ordinary member, and the cadre departed with the chosen members while the remaining team stayed whole")
	quit(0)
