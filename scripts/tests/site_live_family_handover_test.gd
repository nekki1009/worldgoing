extends "res://scripts/tests/site_family_offices_test.gd"
## Actual Family / Controller / Actor / Army / Housing / Store, without owner stubs.
const LiveHousing = preload("res://scripts/terrain_lab/site_housing.gd")
const LIVE_SAVE := "res://.godot-temp/live_family_handover/current.json"
var live_checks := 0

func _live_assert(condition: bool, message: String) -> void:
	live_checks += 1
	assert(condition, message)

func _live_facts(lab: TerrainLab) -> PackedByteArray:
	var teams: Array = []
	for team: TerrainArmy in lab.combat_armies:
		if team.combat_enabled: teams.append({"saved": team.capture_combat_state(true), "offices": team.offices.duplicate(true), "pool": team.team_fatigue.duplicate(true)})
	return var_to_bytes({"site": lab.terrain.site, "player": lab.character.capture_state(true), "npc": lab.npc.capture_state(true),
		"appearance": [lab.character._saved_appearance, lab.npc._saved_appearance], "teams": teams,
		"executor": lab.site_controller.person_executor_id, "paused": paused, "camera": lab.camera.position})

func _live_refused(lab: TerrainLab, request: Callable, code: String) -> void:
	var before: PackedByteArray = _live_facts(lab)
	var result: Dictionary = request.call()
	_live_assert(not result["ok"] and str(result.get("code", "")) == code, str(result))
	_live_assert(before == _live_facts(lab), "Rejected live handover changes no original gameplay/appearance/office/body/paused/camera state")

func _live_fixture() -> TerrainLab:
	var data: TerrainData = _building_fixture()
	var lab: TerrainLab = _building_lab(data)
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = lab.character.faction_id
	var deployed: bool = team.deploy_at(data, lab.character, lab.npc, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)])
	_live_assert(deployed, "Original Army deploys real family rows")
	var enabled: bool = team.enable_combat(false)
	_live_assert(enabled, "Original Army admits its real combat bodies")
	team.set_process(false)
	team.settle_combat_command()
	lab.site_controller.initialize_team_items(team)
	var family: FamilyContinuity = lab.site_controller.family_continuity
	var members: Array = [_ref(data, lab.character.person_id, "本人"), _ref(data, lab.npc.person_id, "家人"), _ref(data, team.combat_identity(1), "隊員家人")]
	var registered: Dictionary = family.register_members(members, true)
	_live_assert(registered["ok"], "Explicit original family registry")
	# Original legacy v1 remains saveable before founding offices.
	lab.site_controller._capture_positions()
	var legacy_save: Dictionary = Store.save(data, LIVE_SAVE)
	_live_assert(legacy_save["ok"], str(legacy_save))
	var legacy_load: Dictionary = Store.load_site(LIVE_SAVE)
	_live_assert(legacy_load["ok"] and int(legacy_load["data"].site["family"]["version"]) == 1, "Old family schema remains readable")
	var appointed: Dictionary = family.appoint_head(lab.character.person_id, lab.character.person_id)
	_live_assert(appointed["ok"], "Original controlled member founds the actual head office")
	return lab

func _live_negatives(lab: TerrainLab) -> void:
	var controller: SiteController = lab.site_controller
	var family: FamilyContinuity = controller.family_continuity
	var site: String = str(lab.terrain.site.id)
	var head: int = lab.character.person_id
	var recipient: int = lab.npc.person_id
	_live_refused(lab, func() -> Dictionary: return family.handover(-1, site, recipient), "NO_AUTHORITY")
	_live_refused(lab, func() -> Dictionary: return family.handover(recipient, site, head), "NO_AUTHORITY")
	_live_refused(lab, func() -> Dictionary: return family.handover(head, "remote:site", recipient), "LOCAL_REQUIRED")
	_live_refused(lab, func() -> Dictionary: return family.handover(head, site, head), "SAME_PERSON")
	_live_refused(lab, func() -> Dictionary: return family.handover(head, site, lab.army.combat_identity(2)), "NO_MEMBER")
	var original_family: Dictionary = lab.terrain.site["family"]
	lab.terrain.site["family"] = {}
	_live_refused(lab, func() -> Dictionary: return family.handover(head, site, recipient), "INVALID_FAMILY")
	lab.terrain.site["family"] = original_family
	for field: String in ["hp", "knockout_left", "captive"]:
		var before: Variant = lab.npc.get(field)
		lab.npc.set(field, true if field == "captive" else (0.0 if field == "hp" else 3.0))
		_live_refused(lab, func() -> Dictionary: return family.handover(head, site, recipient), "NO_TARGET" if field == "hp" else "UNAVAILABLE")
		lab.npc.set(field, before)
	for field: String in ["hp", "knockout_left", "captive"]:
		var before: Variant = lab.character.get(field)
		lab.character.set(field, true if field == "captive" else (0.0 if field == "hp" else 3.0))
		_live_refused(lab, func() -> Dictionary: return family.handover(head, site, recipient), "NO_AUTHORITY")
		lab.character.set(field, before)
	lab.npc.surrender_pending = true
	_live_refused(lab, func() -> Dictionary: return family.handover(head, site, recipient), "UNAVAILABLE")
	lab.npc.surrender_pending = false
	controller._original_step_fault = {"fixture": "explicit original failed interval"}
	_live_refused(lab, func() -> Dictionary: return family.handover(head, site, recipient), "STEP_FAULT")
	controller._original_step_fault = {}
	var missing: Dictionary = lab.terrain.site["family"].duplicate(true)
	for member: Dictionary in missing["members"]:
		if int(member["person_id"]) == recipient: member["person_id"] = 999999
	lab.terrain.site["family"] = missing
	_live_refused(lab, func() -> Dictionary: return family.handover(head, site, 999999), "NO_TARGET")
	lab.terrain.site["family"] = original_family
	var callback: Callable = family.commit_live_handover
	family.commit_live_handover = Callable()
	_live_refused(lab, func() -> Dictionary: return family.handover(head, site, recipient), "UNAVAILABLE")
	family.commit_live_handover = callback
	lab.restore_only = true
	_live_refused(lab, func() -> Dictionary: return family.handover(head, site, recipient), "UNSUPPORTED")
	lab.restore_only = false
	var admitted: bool = lab.npc.place(lab.npc.terrain_cell + Vector2i.RIGHT, false, 0.5)
	_live_assert(admitted and lab.npc.is_moving(), "Original NPC admits a real committed edge")
	_live_refused(lab, func() -> Dictionary: return family.handover(head, site, recipient), "BUSY")
	lab.npc._advance_movement(0.5)
	_live_assert(not lab.npc.is_moving(), "Original movement owner completes the same edge")
	var context: Dictionary = controller._live_family_ui_context()
	lab.terrain.site["family"]["complete"] = not bool(lab.terrain.site["family"]["complete"])
	_live_refused(lab, func() -> Dictionary: return controller._submit_live_family_handover(context, site, recipient), "STALE_CONTEXT")
	lab.terrain.site["family"]["complete"] = not bool(lab.terrain.site["family"]["complete"])
	var death_choice: Dictionary = family.choose(site, recipient)
	_live_assert(not death_choice["ok"] and str(death_choice["code"]) == "NOT_DEAD", "Death-only choose remains NOT_DEAD for a living person")

func _live_success(lab: TerrainLab, use_army: bool) -> void:
	var controller: SiteController = lab.site_controller
	var old: TerrainTestCharacter = lab.character
	var target: int = lab.army.combat_identity(1) if use_army else lab.npc.person_id
	var house: String = _formal_feature(lab.terrain, "house", Vector2i(15, 16), Vector2i(4, 4))
	var housed: Dictionary = LiveHousing.assign(lab, old.person_id, house, old.person_id)
	_live_assert(housed["ok"], str(housed))
	var family: Dictionary = lab.terrain.site["family"]
	var family_before: PackedByteArray = var_to_bytes(family)
	var housing: PackedByteArray = var_to_bytes(lab.terrain.site["housing"])
	var items: PackedByteArray = var_to_bytes(lab.terrain.site["item_records"])
	var old_body: PackedByteArray = var_to_bytes(old.capture_state(true))
	var npc_body: PackedByteArray = var_to_bytes(lab.npc.capture_state(true))
	var army: PackedByteArray = var_to_bytes(lab.army.capture_combat_state(true))
	var pool: Dictionary = lab.army.team_fatigue
	var holder: Dictionary = old.item_state
	lab.terrain.site["paused"] = true
	paused = true
	if use_army:
		var result: Dictionary = controller.family_continuity.handover(old.person_id, str(lab.terrain.site.id), target)
		_live_assert(result["ok"], str(result))
	else:
		controller._open_family()
		var dialog: AcceptDialog = controller._family_dialog
		var listing: ItemList = dialog.find_child("FamilyMembers", true, false) as ItemList
		for index: int in listing.item_count:
			if int(listing.get_item_metadata(index)["person_id"]) == target: listing.select(index)
		var button: Button = dialog.find_child("LiveFamilyHandover", true, false) as Button
		_live_assert(button != null, "Formal family UI contains the distinct live transaction button")
		button.pressed.emit()
	_live_assert(lab.controlled_person_id() == target and controller.person_executor_id == target, "UI/API selects the actual original recipient")
	_live_assert(lab.character == old and is_same(old.item_state, holder) and is_same(lab.army.team_fatigue, pool), "No replacement person, item holder or fatigue authority")
	_live_assert(old_body == var_to_bytes(old.capture_state(true)) and npc_body == var_to_bytes(lab.npc.capture_state(true)), "Both original Actor bodies and positions remain exact")
	_live_assert(army == var_to_bytes(lab.army.capture_combat_state(true)), "Original Army roster, orders, offices, fatigue and team relationship remain exact")
	_live_assert(is_same(lab.terrain.site["family"], family) and family_before == var_to_bytes(family), "Head and all family office/reference objects remain unchanged")
	_live_assert(housing == var_to_bytes(lab.terrain.site["housing"]) and items == var_to_bytes(lab.terrain.site["item_records"]), "Real paid residence and item records stay with their original people")
	_live_assert(paused and bool(lab.terrain.site["paused"]), "Living control preserves the user's paused state")
	_live_refused(lab, func() -> Dictionary: return controller.family_continuity.handover(target, str(lab.terrain.site.id), old.person_id), "NO_AUTHORITY")
	paused = false
	lab.terrain.site["paused"] = false
	var saved: Dictionary = controller.save_to(LIVE_SAVE)
	_live_assert(saved["ok"], str(saved))
	var loaded: Dictionary = Store.load_site(LIVE_SAVE)
	_live_assert(loaded["ok"] and int(loaded["data"].site["controlled_person_id"]) == target, "Original Store roundtrip retains the new control")
	# Store's JSON writer sorts keys; raw Variant dictionary insertion order is not saved.
	var family_wire: String = JSON.stringify(family, "", true, true)
	var loaded_family_wire: String = JSON.stringify(loaded["data"].site["family"], "", true, true)
	_live_assert(loaded_family_wire == family_wire, "No family save-schema migration was introduced")
	lab.bind_terrain(loaded["data"])
	_live_assert(lab.controlled_person_id() == target and lab.controlled_target()["owner"] != lab.character, "Original bind restores actual NPC/Army control")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var first: TerrainLab = _live_fixture()
	_live_negatives(first)
	_live_success(first, false)
	first.free()
	var second: TerrainLab = _live_fixture()
	_live_success(second, true)
	second.free()
	var completed: bool = _finish_workflow_body()
	_live_assert(completed, "Focused live handover completed within its own deadline")
	print("SITE_LIVE_FAMILY_HANDOVER_PASS checks=", live_checks)
	quit(0)
