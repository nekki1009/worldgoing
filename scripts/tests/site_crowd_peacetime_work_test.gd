extends SceneTree
## PEACE2: peacetime settlement and work systems under the crowd model (owner decision 2026-10-31).
## Outside combat (combat_left == 0, no fighting identity) the settlement pages, founding, ecology commands,
## farm/construction dispatch, manual work and deposit run under crowd; during combat they stay refused.
## One case per run, picked with --peace-case:
##   settlement_page_editable   the founded settlement's office plan really changes in peace (a garrison appointment)
##   found_settlement_peace     the controlled crowd soldier founds a settlement in peace
##   ecology_command_peace      an ecology command authority is granted in peace (a discovered ecology source)
##   farm_dispatch_peace        a crowd worker is dispatched through the original work team by the team's commander
##   construction_dispatch_peace the same dispatch gate for construction work (same work-team path)
##   manual_work_peace          manual work is not refused by the crowd guard in peace
##   deposit_peace              depositing controlled cargo is not refused by the crowd guard in peace
##   each_refused_in_combat     every system above refuses with CROWD_ACTIVE during combat and changes nothing
##   saveload                   a peaceful settlement survives a native crowd save/load round trip
## Run: -- --crowd --crowd-test <fresh run_id> --peace-case <case> --crowd-atlas-root res://output/site_siege_close_20261004/equipment_atlas_runtime
## Fails fast on the first failed check.
const DT := 1.0 / 30.0
const CASES := ["settlement_page_editable", "found_settlement_peace", "ecology_command_peace", "farm_dispatch_peace",
	"construction_dispatch_peace", "manual_work_peace", "deposit_peace", "each_refused_in_combat", "saveload"]
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const ResidentLife = preload("res://scripts/terrain_lab/site_resident_life.gd")
const SiteOffices = preload("res://scripts/terrain_lab/site_offices.gd")
const SiteEnvironment = preload("res://scripts/terrain_lab/site_environment.gd")
var lab: TerrainLab
var controller: SiteController
var site: Node
var case_name := "settlement_page_editable"
var helper_id := -1

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	print("PEACE2 ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			printerr("PEACE2 latched frame fault: ", controller._original_step_fault)
			return false
	return true

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	var pick := args.find("--peace-case")
	if pick >= 0 and pick + 1 < args.size(): case_name = str(args[pick + 1])
	if not check(case_name in CASES, "a known peace case is selected", case_name): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	controller = lab.site_controller
	site = lab.crowd_site
	controller._auto_save_blocked = true
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 4, "troop_type": "melee_infantry", "female_percent": 0, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": 6, "female_percent": 0, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "east"}])
	if not check(deployed.ok and site.active and site.command_teams().size() == 2, "a crowd battle deploys two opposing teams", deployed): return
	var friend_team: Dictionary = site._team_by_id(int(site.command_teams()[0].team_id))
	var soldier_id := int(friend_team.person_ids[1])
	helper_id = int(friend_team.person_ids[2]) # A second living same-faction soldier, appointed to a real office seat.
	if not check(not site._actors.has(soldier_id), "the chosen soldier is an ordinary crowd person", soldier_id): return
	if not check(_tick(900), "the deployed team marches in with no latched fault"): return
	match case_name:
		"settlement_page_editable", "found_settlement_peace", "saveload":
			_settlement_case(soldier_id)
		"ecology_command_peace":
			_ecology_case(soldier_id)
		"farm_dispatch_peace", "construction_dispatch_peace":
			_dispatch_case(soldier_id)
		"manual_work_peace":
			_manual_case(soldier_id)
		"deposit_peace":
			_deposit_case(soldier_id)
		"each_refused_in_combat":
			_combat_case(soldier_id)

# Makes the soldier the controlled person for an authority-checked order, restoring it afterwards.
func _as_controlled(soldier_id: int, action: Callable) -> Variant:
	var previous := lab.controlled_person_id()
	lab.terrain.site["controlled_person_id"] = soldier_id
	var result: Variant = action.call()
	lab.terrain.site["controlled_person_id"] = previous
	return result

# Centre cells around the soldier's own cell (the founder must stand within reach of the centre).
func _center_cells(soldier_id: int) -> Array[int]:
	var person: Dictionary = controller.person_actions._person(soldier_id, false)
	var cells: Array[int] = []
	var placement := Runtime.building_cells(lab.terrain, "settlement_center", Vector2i(person.cell) + Vector2i(2, 2), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": int(person.faction)})
	if placement.ok: cells.assign(placement.cells)
	return cells

func _found(soldier_id: int) -> Dictionary:
	return _as_controlled(soldier_id, func() -> Dictionary:
		return Settlement.found(lab, soldier_id, _center_cells(soldier_id), {"layout_version": 1, "quarter": 0}, controller.reserves_cell, "和平測試聚落"))

func _settlement_case(soldier_id: int) -> void:
	var founded: Dictionary = _found(soldier_id)
	if not check(bool(founded.get("ok", false)), "the peaceful founding is accepted", founded): return
	var key := str(founded.get("feature", ""))
	if not check(not key.is_empty() and lab.terrain.site.has("settlement"), "the settlement record exists after founding", key): return
	# Nekki 2026-11-26: the player's own settlement is fed and farmed as the scenario settlements are.
	if not check(ResidentLife.meals_on(lab.terrain.site), "the founded settlement feeds its people (meals 1)", lab.terrain.site.settlement): return
	var rations: Dictionary = ResidentLife.ration_day(controller)
	if not check(rations.refused.is_empty(), "its first day's rations reach every team of its owner", rations): return
	var offices: Dictionary = Settlement.offices(lab)
	var garrison := str(offices.duties["settlement.garrison"])
	# A real change: the second soldier takes the 營務官 seat (the founder keeps the head).
	var plan: Variant = _as_controlled(soldier_id, func() -> Dictionary:
		return Settlement.apply_office_plan(lab, soldier_id, int(offices.get("revision", 0)), [{"op": "appoint", "position_id": garrison, "person_id": helper_id}]))
	if not check(bool((plan as Dictionary).get("ok", false)), "the settlement office page is editable in peace", plan): return
	if not check(int(SiteOffices.position(Settlement.offices(lab), garrison).get("holder", -1)) == helper_id, "the garrison seat is held by the appointed soldier"): return
	if case_name == "found_settlement_peace":
		print("PEACE2 GATE OK: found_settlement_peace")
		quit(0)
		return
	if case_name == "settlement_page_editable":
		print("PEACE2 GATE OK: settlement_page_editable")
		quit(0)
		return
	# saveload: the settlement and its appointment survive a native crowd save/load round trip.
	if not check(_tick(30), "live frames after founding have no latched fault"): return
	var captured: Dictionary = controller._capture_for_save()
	if not check(bool(captured.get("ok", false)), "the save capture is valid with the peaceful settlement", captured.get("code", "OK")): return
	var blob: PackedByteArray = site.crowd.save_state()
	if not check(site.crowd.load_state(blob), "the native state reloads"): return
	if not check(lab.terrain.site.has("settlement"), "the settlement record survives the save"): return
	print("PEACE2 GATE OK: saveload")
	quit(0)

func _ecology_case(soldier_id: int) -> void:
	var key := ""
	var keys: Array = lab.terrain.resource_base.keys()
	keys.sort()
	for candidate: String in keys:
		var resource := SiteEnvironment.resource(lab.terrain, candidate)
		if not resource.is_empty() and int(resource.kind) in SiteEnvironment.ECOLOGY_KINDS and bool(resource.discovered):
			key = candidate
			break
	if not check(not key.is_empty(), "the generated map has a discovered ecology source to command", keys.size()): return
	var authority: Dictionary = _as_controlled(soldier_id, func() -> Dictionary:
		return Settlement.ecology_authority(lab, key, soldier_id))
	if not check(bool(authority.get("ok", false)) or str(authority.get("code", "")) != "CROWD_ACTIVE", "the ecology command is not refused by the crowd in peace", authority): return
	print("PEACE2 GATE OK: ecology_command_peace")
	quit(0)

func _dispatch_case(soldier_id: int) -> void:
	# Dispatch authority: the crowd team's current commander (the team's work duty holder) is the controlled person.
	var owner: RefCounted = site.person_owner(soldier_id)
	var commander_id: int = owner.combat_identity(owner.current_commander)
	var worker_id := helper_id if commander_id == soldier_id else soldier_id
	lab.selected_army_target = worker_id
	var check_result: Dictionary = _as_controlled(commander_id, func() -> Dictionary: return controller._selected_worker_assignment())
	if not check(bool(check_result.get("ok", false)), "the selected crowd worker passes the dispatch check in peace", check_result): return
	var ids: Array[int] = [worker_id]
	var assigned: Dictionary = _as_controlled(commander_id, func() -> Dictionary:
		return controller.work_team.assign(check_result.person.owner, ids, commander_id))
	if not check(bool(assigned.get("ok", false)) and controller.work_team.is_assigned(worker_id), "the crowd worker is dispatched through the original work team", assigned): return
	print("PEACE2 GATE OK: ", case_name)
	quit(0)

func _manual_case(soldier_id: int) -> void:
	_as_controlled(soldier_id, func() -> void: controller.manual_work("harvest"))
	if not check(not controller.message.text.contains("群眾戰鬥"), "manual work is not refused by the crowd guard in peace", controller.message.text): return
	print("PEACE2 GATE OK: manual_work_peace")
	quit(0)

func _deposit_case(soldier_id: int) -> void:
	var person: Dictionary = controller.person_actions._person(soldier_id, false)
	if not check(not person.is_empty() and person.get("cargo") is Dictionary, "the soldier carries a goods record", person.get("cargo")): return
	_as_controlled(soldier_id, func() -> void: controller.deposit_controlled_cargo())
	if not check(not controller.message.text.contains("群眾戰鬥"), "deposit is not refused by the crowd guard in peace", controller.message.text): return
	print("PEACE2 GATE OK: deposit_peace")
	quit(0)

func _combat_case(soldier_id: int) -> void:
	lab.terrain.site["combat_left"] = 30.0
	var refused_found: Dictionary = _as_controlled(soldier_id, func() -> Dictionary:
		return Settlement.found(lab, soldier_id, _center_cells(soldier_id), {"layout_version": 1, "quarter": 0}, controller.reserves_cell, "戰時測試"))
	var refused_plan: Dictionary = _as_controlled(soldier_id, func() -> Dictionary:
		return Settlement.apply_office_plan(lab, soldier_id, 0, []))
	lab.selected_army_target = soldier_id
	var refused_dispatch: Dictionary = controller._selected_worker_assignment()
	var peace_guard: Dictionary = controller.person_actions.crowd_peace_guard([soldier_id])
	lab.terrain.site["combat_left"] = 0.0
	if not check(str(refused_found.get("code", "")) == "CROWD_ACTIVE", "founding is refused in combat with CROWD_ACTIVE", refused_found): return
	if not check(str(refused_plan.get("code", "")) == "CROWD_ACTIVE", "the office page is refused in combat", refused_plan): return
	if not check(str(refused_dispatch.get("code", "")) == "CROWD_ACTIVE" and not peace_guard.ok, "dispatch is refused in combat", refused_dispatch): return
	if not check(not controller.work_team.is_assigned(soldier_id), "no work is assigned in combat"): return
	print("PEACE2 GATE OK: each_refused_in_combat")
	quit(0)
