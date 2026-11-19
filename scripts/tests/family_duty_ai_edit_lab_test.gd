extends "res://scripts/tests/region_initial_world_transaction_test.gd"
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
## Original inherited inner180 unchanged; real owner/people/bind, no fake receipts.

func _ref(lab: TerrainLab, id: int) -> Dictionary:
	return {"site_id": str(lab.terrain.site.id), "person_id": id, "path": lab.site_controller.region_slot.site_path(START), "label": "Original person", "age_years": -1}

func _begin_edit(lab: TerrainLab) -> Dictionary:
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var stage: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	if not _check(stage.ok, "Original source-bound B2 stage", stage): return {}
	var edit: Dictionary = slot.begin_organization_edit(stage.ticket)
	if not _check(edit.ok, "Original B3 private transaction", edit): return {}
	var key: String = str(edit.registry.families.keys()[0])
	return {"slot": slot, "ticket": stage.ticket, "edit": edit, "key": key, "reference": edit.registry.families[key].reference.duplicate(true)}

func _run() -> void:
	var source: RegionData = _fixed_source()
	if source == null:
		_finish()
		return
	var lab: TerrainLab = _source_lab("family_duty_ai_edit")
	if lab == null:
		_finish()
		return
	var controller: SiteController = lab.site_controller
	var born: Dictionary = controller.open_fixed_world(manifest_path, _world("family_duty_ai_edit"), SLOT, START, true, Artisans.PRIMARY)
	if not _check(born.ok, "Original World birth supplies original actual people", born):
		_finish()
		return
	_freeze(lab)
	var slot: RegionSaveSlot = controller.region_slot
	var owner: Family = controller.family_continuity
	var player: int = lab.controlled_person_id()
	var npc: int = int(lab.terrain.site.armies[0].units[0].person_id)
	var outsider: int = int(lab.terrain.site.armies[0].units[1].person_id)
	var registered: Dictionary = owner.register_members([_ref(lab, player), _ref(lab, npc)], true, player)
	var saved: Dictionary = controller.save_to(controller.save_path) if registered.ok else registered
	if not _check(saved.ok, "Original legacy registration/save", saved):
		_finish()
		return
	var legacy: Dictionary = _begin_edit(lab)
	if not legacy.is_empty():
		var legacy_before: PackedByteArray = var_to_bytes(lab.terrain.site)
		var unestablished: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(legacy.ticket, 0, player, true)
		_check(not unestablished.ok and unestablished.code == "NO_AUTHORITY" and var_to_bytes(lab.terrain.site) == legacy_before, "Unestablished family cannot gain AI configuration authority", unestablished)
		var close_legacy: Dictionary = slot.release_organization_stage(legacy.ticket)
		_check(close_legacy.ok, "Close legacy scope")
	var founded: Dictionary = owner.appoint_head(player, player)
	var named: Dictionary = owner.establish_identity(player, "原職責家族") if founded.ok else founded
	saved = controller.save_to(controller.save_path) if named.ok else named
	if not _check(saved.ok, "Original live head/identity/save establish saved typed family", saved):
		_finish()
		return
	lab.terrain.site.family.offices.version = 1
	for row: Dictionary in lab.terrain.site.family.offices.positions: row.erase("office_class")
	var live_offices: Dictionary = lab.terrain.site.family.offices
	var session: Dictionary = _begin_edit(lab)
	if session.is_empty():
		_finish()
		return
	var office_revision: int = int(session.edit.registry.families[session.key].record.offices.revision)
	var before: PackedByteArray = var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()])
	var files_before: Dictionary = _files(slot.folder)
	var denied: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(session.ticket, 0, npc, true)
	var ko: float = lab.character.knockout_left
	lab.character.knockout_left = 1.0
	var unconscious: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(session.ticket, 0, player, true)
	lab.character.knockout_left = ko
	var captive: bool = lab.character.captive
	lab.character.captive = true
	var held: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(session.ticket, 0, player, true)
	lab.character.captive = captive
	var hp: float = lab.character.hp
	lab.character.hp = 0.0
	var dead: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(session.ticket, 0, player, true)
	var sentinel: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(session.ticket, 0, -1, true)
	lab.character.hp = hp
	_check(not denied.ok and denied.code == "NO_AUTHORITY" and not unconscious.ok and unconscious.code == "NO_AUTHORITY" and not held.ok and held.code == "NO_AUTHORITY" and not dead.ok and dead.code == "NO_AUTHORITY" and not sentinel.ok and sentinel.code == "NO_AUTHORITY", "Actual head/NPC authority and physical KO/captive/death/sentinel refusals")
	var rogue: Family = Family.new()
	rogue.init(lab)
	var impersonated: Dictionary = rogue.set_duty_ai_enabled_in_organization_edit(session.ticket, 0, player, true)
	_check(not impersonated.ok and impersonated.code == "NO_ORIGINAL_FAMILY_OWNER", "Second Family cannot impersonate actual Controller owner")
	for index: int in 3:
		var result: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(session.ticket, index, player, index < 2)
		if not _check(result.ok, "Original private flag command succeeds", result):
			_finish()
			return
		_check(result.revision == index + 1 and result.office_revision == office_revision and result.validation == "family_duty_ai_command_preflight_only" and bool(result.registry.families[session.key].record.offices.duty_ai) == (index < 2), "True, same true and false succeed without office revision bump", result)
	var stale: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(session.ticket, 0, player, true)
	_check(not stale.ok and stale.code == "ORGANIZATION_EDIT_CONFLICT", "Private transaction version is independently guarded", stale)
	_check(var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()]) == before and _files(slot.folder) == files_before and is_same(live_offices, lab.terrain.site.family.offices) and int(live_offices.version) == 1, "Private success/refusal never changes live legacy bytes/office alias or original owners/files")
	var readback: Dictionary = slot.read_organization_edit(session.ticket)
	var pretend: Dictionary = readback.registry.families[session.key].record.duplicate(true)
	pretend.members.append(_ref(lab, outsider))
	SiteOffices.head_position(pretend.offices).holder = outsider
	var spoof: Dictionary = slot.mutate_organization_edit(session.ticket, 3, "family", session.reference, pretend)
	var fake_head: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(session.ticket, 4, outsider, true) if spoof.ok else spoof
	var draft_refusal: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(session.ticket, 4, player, true) if spoof.ok else spoof
	_check(spoof.ok and not fake_head.ok and fake_head.code == "NO_AUTHORITY" and not draft_refusal.ok and draft_refusal.code == "NO_AUTHORITY", "Draft-only member/head cannot gain live power; live head cannot ignore draft head", fake_head)
	var barrier: Dictionary = slot.activate_organization_registry(session.ticket, lab.terrain, lab)
	_check(not barrier.ok and barrier.code == "ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "Configuration command leaves activation barrier")
	var close: Dictionary = slot.release_organization_stage(session.ticket)
	_check(close.ok, "Close private configuration scope")
	# Default live setter keeps the original Dictionary object and revision.
	var live_revision: int = int(live_offices.revision)
	var live_on: Dictionary = owner.set_duty_ai_enabled(player, true)
	var live_same: Dictionary = owner.set_duty_ai_enabled(player, true)
	var live_off: Dictionary = owner.set_duty_ai_enabled(player, false)
	_check(live_on.ok and live_same.ok and live_off.ok and not bool(live_offices.duty_ai) and is_same(live_offices, lab.terrain.site.family.offices) and int(live_offices.revision) == live_revision and int(live_offices.version) == SiteOffices.VERSION, "Original live setter upgrades in place, same flag succeeds, no office revision bump")
	var handover: Dictionary = owner.appoint_head(player, npc)
	var npc_flag: Dictionary = owner.set_duty_ai_enabled(npc, true) if handover.ok else handover
	saved = controller.save_to(controller.save_path) if npc_flag.ok else npc_flag
	if not _check(saved.ok, "Original NPC head and live configuration persist", saved):
		_finish()
		return
	var npc_session: Dictionary = _begin_edit(lab)
	if not npc_session.is_empty():
		var npc_revision: int = int(npc_session.edit.registry.families[npc_session.key].record.offices.revision)
		var npc_private: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(npc_session.ticket, 0, npc, false)
		_check(npc_private.ok and npc_private.office_revision == npc_revision and bool(lab.terrain.site.family.offices.duty_ai), "Actual fit NPC head can privately configure without controlled-player restriction or live change", npc_private)
		var actual: Dictionary = slot.read_organization_edit(npc_session.ticket)
		pretend = actual.registry.families[npc_session.key].record.duplicate(true)
		SiteOffices.head_position(pretend.offices).holder = player
		spoof = slot.mutate_organization_edit(npc_session.ticket, 1, "family", npc_session.reference, pretend)
		var self_crown: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(npc_session.ticket, 2, player, false) if spoof.ok else spoof
		_check(spoof.ok and not self_crown.ok and self_crown.code == "NO_AUTHORITY", "Draft self-crown cannot override actual live NPC head", self_crown)
		var close_npc: Dictionary = slot.release_organization_stage(npc_session.ticket)
		_check(close_npc.ok, "Close NPC scope")
	var had_identity: bool = lab.terrain.site.has("travel_identity")
	var old_identity: Dictionary = lab.terrain.site.get("travel_identity", {}).duplicate(true)
	var issued: Dictionary = RegionTravel.prepare_identity(lab.terrain.site)
	if _check(issued.ok, "Original issuer supplies detached typed binding", issued):
		lab.terrain.site.travel_identity = issued.state.travel_identity.duplicate(true)
		lab.terrain.site.travel_identity.refs.family.controlled.namespace += ":foreign"
		var foreign: Dictionary = _begin_edit(lab)
		if not foreign.is_empty():
			var foreign_before: PackedByteArray = var_to_bytes([lab.terrain.site, foreign.edit.registry])
			var wrong_family: Dictionary = owner.set_duty_ai_enabled_in_organization_edit(foreign.ticket, 0, npc, false)
			var foreign_after: Dictionary = slot.read_organization_edit(foreign.ticket)
			_check(not wrong_family.ok and wrong_family.code == "ORGANIZATION_FAMILY_IDENTITY_CHANGED" and var_to_bytes([lab.terrain.site, foreign_after.registry]) == foreign_before, "Saved/live typed mismatch refuses without mutating either side", wrong_family)
			var close_foreign: Dictionary = slot.release_organization_stage(foreign.ticket)
			_check(close_foreign.ok, "Close foreign family scope")
		if had_identity: lab.terrain.site.travel_identity = old_identity
		else: lab.terrain.site.erase("travel_identity")
	lab.free()
	var freed: Dictionary = owner.set_duty_ai_enabled_in_organization_edit({}, 0, player, true)
	_check(not freed.ok and freed.code == "NO_ORIGINAL_FAMILY_OWNER", "Freed Lab refused before controller access")
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
	print("FAMILY_DUTY_AI_EDIT_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)
