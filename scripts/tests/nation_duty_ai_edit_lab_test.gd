extends "res://scripts/tests/region_initial_world_transaction_test.gd"
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")

func _begin_nation_edit(lab: TerrainLab) -> Dictionary:
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var stage: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	if not _check(stage.ok, "Original source-bound nation stage", stage): return {}
	var edit: Dictionary = slot.begin_organization_edit(stage.ticket)
	if not _check(edit.ok, "Original private transaction", edit): return {}
	var key: String = str(edit.registry.nations.keys()[0])
	return {"ticket": stage.ticket, "edit": edit, "key": key, "reference": edit.registry.nations[key].reference.duplicate(true)}

func _old(offices: Dictionary) -> void:
	offices["version"] = 1
	var removed: String = str(offices.duties["nation.ransom"])
	offices.duties.erase("nation.ransom")
	for row: Dictionary in offices.positions.duplicate():
		if row.id == removed: offices.positions.erase(row)
		else: row.erase("office_class")

func _run() -> void:
	var source: RegionData = _fixed_source()
	if source == null:
		_finish()
		return
	var lab: TerrainLab = _source_lab("nation_duty_ai_edit")
	if lab == null:
		_finish()
		return
	var controller: SiteController = lab.site_controller
	var born: Dictionary = controller.open_fixed_world(manifest_path, _world("nation_duty_ai_edit"), SLOT, START, true, Artisans.PRIMARY)
	if not _check(born.ok, "Original World birth supplies real finite people", born):
		_finish()
		return
	_freeze(lab)
	var slot: RegionSaveSlot = controller.region_slot
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var player: int = lab.controlled_person_id()
	var npc: int = int(lab.terrain.site.armies[0].units[0].person_id)
	var keeper: int = int(lab.terrain.site.armies[0].units[1].person_id)
	# Original tests use explicit scenario nations; no person/office facts are mocked.
	lab.terrain.site["equipment_nations"] = {"n1": {"military_head": keeper, "members": [player, npc, keeper], "standards": {}}}
	var legacy_before: PackedByteArray = var_to_bytes(lab.terrain.site.equipment_nations)
	var legacy_flag: Dictionary = orders.set_nation_duty_ai(player, "n1", true)
	_check(not legacy_flag.ok and legacy_flag.code == "NO_AUTHORITY" and var_to_bytes(lab.terrain.site.equipment_nations) == legacy_before, "Original legacy nation has no installed head authority")
	var appointed: Dictionary = orders.appoint_nation_head("n1", player)
	var saved: Dictionary = controller.save_to(controller.save_path) if appointed.ok else appointed
	if not _check(saved.ok, "Original scenario head appointment and actual World save", saved):
		_finish()
		return
	_old(lab.terrain.site.equipment_nations.n1.offices)
	var alias: Dictionary = lab.terrain.site.equipment_nations.n1.offices
	var revision: int = int(alias.revision)
	var session: Dictionary = _begin_nation_edit(lab)
	if session.is_empty():
		_finish()
		return
	var candidate: Dictionary = session.edit.registry.nations[session.key].record.duplicate(true)
	_old(candidate.offices)
	var injected: Dictionary = slot.mutate_organization_edit(session.ticket, 0, "nation", session.reference, candidate)
	if not _check(injected.ok, "Original B3 admits valid old office/catalog draft fixture", injected):
		_finish()
		return
	var before: PackedByteArray = var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()])
	var files_before: Dictionary = _files(slot.folder)
	var denied: Dictionary = orders.set_nation_duty_ai_in_organization_edit(session.ticket, 1, npc, "n1", true)
	var missing: Dictionary = orders.set_nation_duty_ai_in_organization_edit(session.ticket, 1, player, "unsaved", true)
	_check(not denied.ok and denied.code == "NO_AUTHORITY" and not missing.ok and missing.code == "ORGANIZATION_SAVED_NATION_REQUIRED", "Original head and saved local nation binding required")
	var hp: float = lab.character.hp
	var ko: float = lab.character.knockout_left
	var captive: bool = lab.character.captive
	lab.character.knockout_left = 1.0
	var unconscious: Dictionary = orders.set_nation_duty_ai_in_organization_edit(session.ticket, 1, player, "n1", true)
	lab.character.knockout_left = ko
	lab.character.captive = true
	var held: Dictionary = orders.set_nation_duty_ai_in_organization_edit(session.ticket, 1, player, "n1", true)
	lab.character.captive = captive
	lab.character.hp = 0.0
	var dead: Dictionary = orders.set_nation_duty_ai_in_organization_edit(session.ticket, 1, player, "n1", true)
	var sentinel: Dictionary = orders.set_nation_duty_ai_in_organization_edit(session.ticket, 1, -1, "n1", true)
	lab.character.hp = hp
	_check(not unconscious.ok and unconscious.code == "NO_AUTHORITY" and not held.ok and held.code == "NO_AUTHORITY" and not dead.ok and dead.code == "NO_AUTHORITY" and not sentinel.ok and sentinel.code == "NO_AUTHORITY", "Actual original head HP/KO/captive and sentinel refusals")
	var rogue: SiteEquipmentOrders = Orders.new()
	rogue.lab = lab
	var impersonated: Dictionary = rogue.set_nation_duty_ai_in_organization_edit(session.ticket, 1, player, "n1", true)
	_check(not impersonated.ok and impersonated.code == "NO_ORIGINAL_NATION_OWNER", "Actual Controller EquipmentOrders required")
	for i: int in 3:
		var result: Dictionary = orders.set_nation_duty_ai_in_organization_edit(session.ticket, i + 1, player, "n1", i < 2)
		if not _check(result.ok, "Complete original flag writer succeeds privately", result):
			_finish()
			return
		var record: Dictionary = result.registry.nations[session.key].record
		_check(result.revision == i + 2 and result.office_revision == revision + 1 and int(record.offices.version) == SiteOffices.VERSION and record.offices.duties.has("nation.ransom") and bool(record.offices.duty_ai) == (i < 2), "True/same true/false: catalog adds one office revision, flag adds none", result)
	var stale: Dictionary = orders.set_nation_duty_ai_in_organization_edit(session.ticket, 1, player, "n1", true)
	_check(not stale.ok and stale.code == "ORGANIZATION_EDIT_CONFLICT", "Independent transaction revision guard")
	_check(var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()]) == before and _files(slot.folder) == files_before and is_same(alias, lab.terrain.site.equipment_nations.n1.offices) and int(alias.version) == 1, "Private success/refusal never upgrades live old offices or changes source owners/files")
	var readback: Dictionary = slot.read_organization_edit(session.ticket)
	candidate = readback.registry.nations[session.key].record.duplicate(true)
	SiteOffices.head_position(candidate.offices)["holder"] = npc
	var spoof: Dictionary = slot.mutate_organization_edit(session.ticket, 4, "nation", session.reference, candidate)
	var wrong_draft: Dictionary = orders.set_nation_duty_ai_in_organization_edit(session.ticket, 5, player, "n1", true) if spoof.ok else spoof
	var wrong_live: Dictionary = orders.set_nation_duty_ai_in_organization_edit(session.ticket, 5, npc, "n1", true) if spoof.ok else spoof
	_check(spoof.ok and not wrong_draft.ok and wrong_draft.code == "NO_AUTHORITY" and not wrong_live.ok and wrong_live.code == "NO_AUTHORITY", "Live and draft national authority are independent")
	var barrier: Dictionary = slot.activate_organization_registry(session.ticket, lab.terrain, lab)
	_check(not barrier.ok and barrier.code == "ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "Activation barrier unchanged")
	var closed: Dictionary = slot.release_organization_stage(session.ticket)
	_check(closed.ok, "Close private nation scope")
	var live_on: Dictionary = orders.set_nation_duty_ai(player, "n1", true)
	var live_same: Dictionary = orders.set_nation_duty_ai(player, "n1", true)
	_check(live_on.ok and live_same.ok and is_same(alias, lab.terrain.site.equipment_nations.n1.offices) and int(alias.revision) == revision + 1 and int(alias.version) == SiteOffices.VERSION and alias.duties.has("nation.ransom"), "Original live setter retains object and complete once-only catalog side effects", live_on)
	appointed = orders.appoint_nation_head("n1", npc)
	saved = controller.save_to(controller.save_path) if appointed.ok else appointed
	if not _check(saved.ok, "Original scenario NPC head and save", saved):
		_finish()
		return
	var npc_session: Dictionary = _begin_nation_edit(lab)
	if not npc_session.is_empty():
		var npc_result: Dictionary = orders.set_nation_duty_ai_in_organization_edit(npc_session.ticket, 0, npc, "n1", false)
		_check(npc_result.ok and bool(lab.terrain.site.equipment_nations.n1.offices.duty_ai), "Actual fit NPC head accepted without changing live flag", npc_result)
		var close_npc: Dictionary = slot.release_organization_stage(npc_session.ticket)
		_check(close_npc.ok, "Close NPC scope")
	var had_identity: bool = lab.terrain.site.has("travel_identity")
	var old_identity: Dictionary = lab.terrain.site.get("travel_identity", {}).duplicate(true)
	var issued: Dictionary = RegionTravel.prepare_identity(lab.terrain.site)
	if _check(issued.ok, "Original typed nation issuer", issued):
		lab.terrain.site["travel_identity"] = issued.state.travel_identity.duplicate(true)
		lab.terrain.site.travel_identity.refs.nation.n1["namespace"] += ":foreign"
		var foreign: Dictionary = _begin_nation_edit(lab)
		if not foreign.is_empty():
			var foreign_before: PackedByteArray = var_to_bytes([lab.terrain.site, foreign.edit.registry])
			var mismatch: Dictionary = orders.set_nation_duty_ai_in_organization_edit(foreign.ticket, 0, npc, "n1", false)
			var after: Dictionary = slot.read_organization_edit(foreign.ticket)
			_check(not mismatch.ok and mismatch.code == "ORGANIZATION_NATION_IDENTITY_CHANGED" and var_to_bytes([lab.terrain.site, after.registry]) == foreign_before, "Saved/live typed national mismatch refuses without mutation", mismatch)
			var close_foreign: Dictionary = slot.release_organization_stage(foreign.ticket)
			_check(close_foreign.ok, "Close foreign nation scope")
		if had_identity: lab.terrain.site["travel_identity"] = old_identity
		else: lab.terrain.site.erase("travel_identity")
	lab.free()
	var freed: Dictionary = orders.set_nation_duty_ai_in_organization_edit({}, 0, npc, "n1", false)
	_check(not freed.ok and freed.code == "NO_ORIGINAL_NATION_OWNER", "Freed Lab rejected before Controller access")
	_finish()

func _files(folder: String) -> Dictionary:
	var result: Dictionary = {}
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null: return result
	for name: String in directory.get_files(): result[folder.path_join(name)] = FileAccess.get_sha256(folder.path_join(name))
	for name: String in directory.get_directories(): result.merge(_files(folder.path_join(name)))
	return result

func _finish(reason: String = "") -> void:
	if finished: return
	print("NATION_DUTY_AI_EDIT_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)
