extends "res://scripts/tests/region_initial_world_transaction_test.gd"
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const OrganizationRegistry = preload("res://scripts/region_lab/region_organization_registry.gd")

func _begin_nation_edit(lab: TerrainLab) -> Dictionary:
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var stage: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	if not _check(stage.ok, "Original source-bound nation stage", stage): return {}
	var edit: Dictionary = slot.begin_organization_edit(stage.ticket)
	if not _check(edit.ok, "Original private transaction", edit): return {}
	var key: String = str(edit.registry.nations.keys()[0])
	return {"ticket": stage.ticket, "edit": edit, "key": key, "reference": edit.registry.nations[key].reference.duplicate(true)}

func _run() -> void:
	var source: RegionData = _fixed_source()
	if source == null:
		_finish()
		return
	var lab: TerrainLab = _source_lab("nation_culture_edit")
	if lab == null:
		_finish()
		return
	var controller: SiteController = lab.site_controller
	var born: Dictionary = controller.open_fixed_world(manifest_path, _world("nation_culture_edit"), SLOT, START, true, Artisans.PRIMARY)
	if not _check(born.ok, "Original World birth supplies real finite people", born):
		_finish()
		return
	_freeze(lab)
	var slot: RegionSaveSlot = controller.region_slot
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var player: int = lab.controlled_person_id()
	var npc: int = int(lab.terrain.site.armies[0].units[0].person_id)
	var keeper: int = int(lab.terrain.site.armies[0].units[1].person_id)
	# Original tests use explicit scenario nations; no person/office facts are mocked. The legacy
	# military head (keeper) keeps the equipment duties, culture included, through the head migration;
	# the player becomes the nation head, who is not the culture decider.
	lab.terrain.site["equipment_nations"] = {"n1": {"military_head": keeper, "members": [player, npc, keeper], "standards": {}}}
	var appointed: Dictionary = orders.appoint_nation_head("n1", player)
	var saved: Dictionary = controller.save_to(controller.save_path) if appointed.ok else appointed
	if not _check(saved.ok, "Original scenario head appointment and actual World save", saved):
		_finish()
		return
	var nation: Dictionary = lab.terrain.site.equipment_nations.n1
	var session: Dictionary = _begin_nation_edit(lab)
	if session.is_empty():
		_finish()
		return
	var before: PackedByteArray = var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()])
	var files_before: Dictionary = _files(slot.folder)
	var denied: Dictionary = orders.set_nation_culture_in_organization_edit(session.ticket, 0, npc, "n1", "japanese")
	var missing: Dictionary = orders.set_nation_culture_in_organization_edit(session.ticket, 0, keeper, "unsaved", "japanese")
	var invalid: Dictionary = orders.set_nation_culture_in_organization_edit(session.ticket, 0, keeper, "n1", "martian")
	_check(not denied.ok and denied.code == "NO_AUTHORITY" and not missing.ok and missing.code == "ORGANIZATION_SAVED_NATION_REQUIRED" and not invalid.ok and invalid.code == "INVALID",
		"Original culture decider, saved local nation binding and culture list required", {"denied": denied, "missing": missing, "invalid": invalid})
	var head_only: Dictionary = orders.set_nation_culture_in_organization_edit(session.ticket, 0, player, "n1", "japanese")
	var sentinel: Dictionary = orders.set_nation_culture_in_organization_edit(session.ticket, 0, -1, "n1", "japanese")
	_check(not head_only.ok and head_only.code == "NO_AUTHORITY" and not sentinel.ok and sentinel.code == "NO_AUTHORITY",
		"The nation head is not the culture decider, and a -1 requester never matches a sentinel", {"head": head_only, "sentinel": sentinel})
	var rogue: SiteEquipmentOrders = Orders.new()
	rogue.lab = lab
	var impersonated: Dictionary = rogue.set_nation_culture_in_organization_edit(session.ticket, 0, keeper, "n1", "japanese")
	_check(not impersonated.ok and impersonated.code == "NO_ORIGINAL_NATION_OWNER", "Actual Controller EquipmentOrders required")
	var fixed: Dictionary = orders.set_nation_culture_in_organization_edit(session.ticket, 0, keeper, "n1", "japanese")
	if not _check(fixed.ok, "Original domain command fixes the culture only in the private draft", fixed):
		_finish()
		return
	var record: Dictionary = fixed.registry.nations[session.key].record
	var record_canonical: Dictionary = OrganizationRegistry.canonical(record)
	_check(fixed.revision == 1 and fixed.validation == "nation_culture_command_preflight_only" and str(record.get("culture", "")) == "japanese" and record_canonical.ok,
		"Private revision, fixed culture and canonical record returned", fixed)
	var stale: Dictionary = orders.set_nation_culture_in_organization_edit(session.ticket, 0, keeper, "n1", "japanese")
	var changed: Dictionary = orders.set_nation_culture_in_organization_edit(session.ticket, 1, keeper, "n1", "western")
	var same: Dictionary = orders.set_nation_culture_in_organization_edit(session.ticket, 1, keeper, "n1", "japanese")
	_check(not stale.ok and stale.code == "ORGANIZATION_EDIT_CONFLICT" and not changed.ok and changed.code == "CULTURE_FIXED" and not same.ok and same.code == "NO_CHANGE",
		"Transaction revision guard and original fixed-culture rules on the draft", {"stale": stale, "changed": changed, "same": same})
	_check(var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()]) == before and _files(slot.folder) == files_before and not nation.has("culture"),
		"Private success/refusal never fixes the live culture or changes source owners/files")
	var barrier: Dictionary = slot.activate_organization_registry(session.ticket, lab.terrain, lab)
	_check(not barrier.ok and barrier.code == "ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "Activation barrier unchanged")
	var closed: Dictionary = slot.release_organization_stage(session.ticket)
	_check(closed.ok, "Close private nation scope")
	# The original live first setting writes a JSON-canonical String key.
	var live_fixed: Dictionary = orders.set_nation_culture(keeper, "n1", "chinese")
	var live_canonical: Dictionary = OrganizationRegistry.canonical(nation)
	_check(live_fixed.ok and str(nation.get("culture", "")) == "chinese" and live_canonical.ok, "Original live first setting still fixes the culture with a String key", live_canonical)
	lab.free()
	var freed: Dictionary = orders.set_nation_culture_in_organization_edit({}, 0, keeper, "n1", "chinese")
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
	print("NATION_CULTURE_EDIT_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)
