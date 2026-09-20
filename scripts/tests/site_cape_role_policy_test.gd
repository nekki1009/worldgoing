extends SceneTree
## Original identities/holders and real controller guards, without a GPU window.
const PersonTest = preload("res://scripts/tests/site_person_actions_test.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUT := "res://output/equipment_limits_20260919/cape_role"
var _completed_groups := 0

class Controller extends SiteController:
	var last_result := {}
	func show_result(result: Dictionary) -> void:
		last_result = result

class Fixture extends Node2D:
	var source := PersonTest.Fixture.new()
	var terrain: TerrainData = source.terrain
	var character: TerrainTestCharacter = source.character
	var npc: TerrainTestNPC = source.npc
	var army: TerrainArmy = source.army
	var combat_armies: Array[TerrainArmy] = [army]
	var exchange_enabled := true
	var controller := Controller.new()
	func _init() -> void:
		terrain.site.inventory = {}
		terrain.site.capacity = 100
		terrain.site.depot_cell = terrain.index(Vector2i(5, 4))
		npc.terrain_cell = Vector2i(6, 4)
		controller.lab = self
		controller.person_actions.init(self)
		controller.equipment_orders.init(self, controller.person_actions)
		controller.equipment_orders.equipment_apply_guard = controller.equipment_apply_guard
		controller.equipment_orders.equipment_dye_guard = controller.equipment_dye_guard
		controller.person_actions.equipment_changed = controller.equipment_changed
		controller.vehicles.init(controller)
		army.native_presence_enabled = false
		army.cape_retirement = controller.retire_officer_capes
		army.cape_departure_guard = controller.cape_departure_guard
		for actor: TerrainTestCharacter in [character, npc]:
			actor._saved_appearance = HumanCharacter3DEditor.default_appearance(0)
			for slot: String in SiteRuntime.EQUIPMENT_SLOTS: actor._saved_appearance.parts[slot] = "none"
			controller.equipment_changed(actor.person_id)
		var row: Dictionary = army.combat_units[0]
		row.merge({"appearance": character._saved_appearance.duplicate(true), "visual_role": "male_live", "present": true, "member": true})
		var second: Dictionary = row.duplicate(true)
		second.person_id = 4
		second.item_state = SiteRuntime.new_item_state("person:4")
		army.combat_units.append(second)
		army.cells.append(Vector2i(6, 5))
		army.moving_to.append(TerrainArmy.INVALID_CELL)
		army._initialize_combat_command()
		army.settle_combat_command()
	func _combat_target(identity: int) -> Dictionary:
		if identity == 4: return {"owner": army, "unit": 1, "cell": army.cells[1], "hp": army.combat_units[1].hp}
		return source._combat_target(identity)
	func controlled_person_id() -> int:
		return source.controlled_id
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return false
	func has_ranged_projectiles() -> bool:
		return false
	func item(identity: int, slot: String = "cape", asset: String = "cape_travel_01", worn: bool = false) -> String:
		var holder: Dictionary = terrain.site.depot_items if identity == 0 else controller.person_actions._person(identity).holder
		var result := SiteRuntime.create_equipment(terrain, holder, slot + ":" + asset,
			{"slot": slot, "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, maxi(identity, 1), slot if worn else "")
		assert(result.ok)
		return str(result.item_id)
	func stock() -> String:
		return JSON.stringify([terrain.site.item_records, terrain.site.depot_items, character.item_state, npc.item_state,
			army.combat_units[0].item_state, army.combat_units[1].item_state, army.officer_order, army.officer_service])
	func close() -> void:
		controller.equipment_orders.lab = null
		controller.person_actions.lab = null
		controller.lab = null
		controller.free()
		source.close()
		queue_free()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(1))
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	_roles()
	_orders_and_editor()
	_retirement_and_demotion()
	_command_recovery_keeps_office()
	_acting_is_not_appointment()
	if not OS.get_cmdline_user_args().has("--policy-only"):
		_strict_atlas()
	_saved_roles()
	_save_boundary()
	await _live_spawn()
	await process_frame
	var expected_groups := 8 if OS.get_cmdline_user_args().has("--policy-only") else 9
	if _completed_groups != expected_groups:
		push_error("SITE CAPE ROLE POLICY incomplete assertion groups: %d/%d" % [_completed_groups, expected_groups])
		quit(1)
		return
	print("SITE CAPE ROLE POLICY PASS: continuing formal/officer/national offices, no temporary-command entitlement or automatic cape retirement, KO/recovery preserves office/items even with full backpack, existing death succession and explicit personnel removal, prepare+commit/editor/save guards, legacy/capacity/atlas preservation; atlas_positive_checks=%s; no GPU or material proof" % str(not OS.get_cmdline_user_args().has("--policy-only")))
	quit(0)

func _roles() -> void:
	var f := Fixture.new()
	var policy := f.controller.equipment_orders
	assert(policy.cape_role_allowed(3) and not policy.cape_role_allowed(4))
	assert(not policy.cape_role_allowed(1) and not policy.cape_role_allowed(2))
	f.army.command_abilities[1] = {"tactics": 100, "leadership": 100, "coach": 100}
	f.source.controlled_id = 4
	assert(not policy.cape_role_allowed(4), "Control and remembered command abilities cannot mint an office")
	assert(f.army.record_officer_service([1], true).ok and policy.cape_role_allowed(4))
	f.army.combat_units[1].ko = 10.0
	assert(policy.cape_role_allowed(4), "Temporary inability does not revoke an existing office")
	f.army.combat_units[1].ko = 0.0
	assert(f.army.record_officer_service([1], false).ok and not policy.cape_role_allowed(4))
	f.army.current_commander = 1
	assert(not policy.cape_role_allowed(4), "Temporary command without a continuing office cannot authorize a cape")
	f.army.combat_units[1].member = false
	assert(not policy.cape_role_allowed(4), "Stale indexes cannot authorize former members")
	f.army.player_member = f.character
	f.army.formal_commander = TerrainArmy.PLAYER_MEMBER
	assert(f.controller.person_can_wear_cape(1), "Resolve the original actor through PLAYER_MEMBER")
	f.army.player_member = null
	f.terrain.site.equipment_nations = {"real": {"military_head": 2, "members": [1, 2], "standards": {}}}
	assert(policy.cape_role_allowed(2) and not policy.cape_role_allowed(1))
	f.terrain.site.equipment_nations.real.members = [1]
	assert(not policy.cape_role_allowed(2), "A head ID without real membership does not authorize wear")
	f.close()
	_completed_groups += 1

func _live_spawn() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.set_process(false)
		assert(HumanCharacter3DEditor.valid_appearance(actor._saved_appearance), "Actor-owned initial snapshot must precede item/cape preflight, including GPU editor startup")
		assert(not lab.site_controller.person_can_wear_cape(actor.person_id))
		assert(not actor.item_state.equipped.has("cape"), "Formal new-site ordinary actors cannot keep a default worn cape")
		assert(lab.site_controller.person_appearance(actor.person_id).parts.cape == "none")
		var owned_capes := 0
		for item_id: String in actor.item_state.item_ids:
			var record: Dictionary = lab.terrain.site.item_records[item_id]
			assert(record.holder == actor.item_state.holder)
			if lab.terrain.site.item_definitions[record.definition].slot == "cape":
				owned_capes += 1
				assert(int(record.original_owner) == actor.person_id and not actor.item_state.equipped.values().has(item_id), "Original preview cape stays owned in the same person's backpack")
		assert(owned_capes == 1, "Initial authored cape becomes one real retained item, not deleted or replaced by a capeless seed")
	var before: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var holders := [lab.character.item_state.duplicate(true), lab.npc.item_state.duplicate(true)]
	lab.site_controller.bind()
	assert(lab.terrain.site.item_records == before, "Rebinding neither refills items nor resurrects the preview's default cape")
	assert([lab.character.item_state, lab.npc.item_state] == holders, "Rebinding preserves holder versions, backpack and equipped slots")
	assert(lab.site_controller.cape_policy_guard().ok)
	lab.site_controller._capture_positions()
	var saved := Store.save(lab.terrain, OUT + "/new_site.json")
	assert(saved.ok, str(saved))
	assert(Store.load_site(OUT + "/new_site.json").ok)
	lab.free()
	await process_frame
	_completed_groups += 1

func _orders_and_editor() -> void:
	var f := Fixture.new()
	var orders := f.controller.equipment_orders
	var cape := f.item(1)
	var before := f.stock()
	assert(orders.begin_personal(1, "cape", cape).code == "CAPE_ROLE_RESTRICTED")
	assert(f.controller.equipment_apply_guard(1, {"cape": cape}).code == "CAPE_ROLE_RESTRICTED")
	assert(f.controller._request_person_equipment("cape", "cape_travel_01", 1) == "none")
	assert(f.controller.last_result.code == "CAPE_ROLE_RESTRICTED" and f.stock() == before)
	f.terrain.site.equipment_nations = {"real": {"military_head": 1, "members": [1, 2], "standards": {}}}
	var prepared := orders.prepare(1, {"mode": "personal", "slot": "cape", "item_id": cape})
	assert(prepared.ok)
	f.terrain.site.equipment_nations.real.military_head = 2
	assert(orders.commit(prepared.order).code == "CAPE_ROLE_RESTRICTED" and f.stock() == before)
	f.terrain.site.equipment_nations.real.military_head = 1
	assert(orders.begin_personal(1, "cape", cape).ok)
	f.controller.person_actions.advance(5.0)
	assert(f.controller.person_actions.settle_after_contacts()[0].ok and f.character.item_state.equipped.cape == cape)
	assert(f.controller.person_appearance(1).parts.cape == "cape_travel_01")
	var depot_cape := f.item(0, "cape", "cape_chinese_01")
	assert(orders.set_standard(1, "real", "cape", "軍官披風", {"cape": {"definition": "cape:cape_chinese_01"}}).ok)
	assert(orders.set_nation_culture(1, "real", "chinese").ok)
	assert(orders.begin_issue(2, "real", "cape").code == "CAPE_ROLE_RESTRICTED")
	f.terrain.site.equipment_nations.real.military_head = 2
	prepared = orders.prepare(2, {"mode": "issue", "nation_id": "real", "standard_id": "cape"})
	assert(prepared.ok)
	before = f.stock()
	f.terrain.site.equipment_nations.real.military_head = 1
	assert(orders.commit(prepared.order).code == "CAPE_ROLE_RESTRICTED" and f.stock() == before)
	assert(f.terrain.site.depot_items.item_ids.has(depot_cape))
	f.close()
	_completed_groups += 1

func _retirement_and_demotion() -> void:
	var f := Fixture.new()
	var cape := f.item(4, "cape", "cape_travel_01", true)
	f.terrain.site.item_records[cape].dye_color = "123456ff"
	var record: Dictionary = f.terrain.site.item_records[cape].duplicate(true)
	f.army.combat_units[1].cargo.wood = 20
	var before := f.stock()
	assert(f.controller.reconcile_cape_roles([4]).code == "STORAGE_FULL" and f.stock() == before)
	assert(f.controller.cape_policy_guard().code == "CAPE_ROLE_RESTRICTED")
	f.army.combat_units[1].cargo.clear()
	var row: Dictionary = f.army.combat_units[1]
	var original_face := str(row.appearance.parts.face)
	row.appearance.parts.face = "face_standard_04"
	row.visual_role = "male_atlas"
	before = f.stock()
	var missing := f.controller.reconcile_cape_roles([4])
	assert(missing.code == "ATLAS_REQUIRED" and f.stock() == before,
		"A missing strict atlas must preserve the original cape, not hide or drop it: " + str(missing))
	row.appearance.parts.face = original_face
	row.visual_role = "male_live"
	assert(f.controller.reconcile_cape_roles([4]).ok)
	assert(not f.army.combat_units[1].item_state.equipped.has("cape"))
	assert(f.army.combat_units[1].item_state.item_ids.has(cape) and f.terrain.site.item_records[cape] == record)
	assert(f.controller.person_appearance(4).parts.cape == "none")
	assert(f.army.record_officer_service([1], true).ok)
	f.source.controlled_id = 4
	var prepared := f.controller.equipment_orders.prepare(4, {"mode": "personal", "slot": "cape", "item_id": cape})
	assert(prepared.ok and f.controller.equipment_orders.commit(prepared.order).ok)
	f.army.combat_units[1].cargo.wood = 20
	before = f.stock()
	assert(f.army.record_officer_service([1], false).code == "STORAGE_FULL" and f.stock() == before)
	f.army.combat_units[1].cargo.clear()
	assert(f.controller.cape_departure_guard(4).code == "CAPE_REMOVE_FIRST")
	assert(f.army.record_officer_service([1], false).ok)
	assert(not f.army.officer_order.has(1) and not f.army.combat_units[1].item_state.equipped.has("cape"))
	# Batch retirement is all-or-none even when a later original holder is full.
	f.item(1, "cape", "cape_travel_01", true)
	f.item(2, "cape", "cape_chinese_01", true)
	f.terrain.site.worker.cargo.wood = 20
	before = f.stock()
	assert(f.controller.equipment_orders.retire_capes([1, 2]).code == "STORAGE_FULL" and f.stock() == before)
	f.terrain.site.worker.cargo.clear()
	assert(f.controller.equipment_orders.retire_capes([1, 2], true).ok and f.stock() == before)
	assert(f.controller.equipment_orders.retire_capes([1, 2]).ok)
	f.close()
	_completed_groups += 1

func _command_recovery_keeps_office() -> void:
	var f := Fixture.new()
	assert(f.army.record_officer_service([1], true).ok)
	var commander_cape := f.item(3, "cape", "cape_travel_01", true)
	var officer_cape := f.item(4, "cape", "cape_chinese_01", true)
	f.terrain.site.item_records[officer_cape].dye_color = "123456ff"
	for identity: int in [3, 4]: f.controller.equipment_changed(identity)
	# A full backpack must not matter to a command handback: no office is lost
	# and there is no cape removal transaction to require free storage.
	f.army.combat_units[1].cargo.wood = 20
	var before := f.stock()
	var officer_look := f.controller.person_appearance(4).duplicate(true)
	f.army.combat_units[0].ko = 10.0
	f.army._command_dirty = true
	f.army.settle_combat_command()
	assert(f.army.formal_commander == 0 and f.army.current_commander == 1 and f.army.acting_commander == 1)
	assert(f.controller.person_can_wear_cape(3) and f.controller.person_can_wear_cape(4))
	assert(f.stock() == before, "KO/acting handover preserves continuing offices and all real cape records")
	f.army.combat_units[1].ko = 10.0
	f.army._command_dirty = true
	f.army.settle_combat_command()
	assert(f.army.current_commander == -1 and f.army.formal_commander == 0)
	assert(f.controller.person_can_wear_cape(3) and f.controller.person_can_wear_cape(4) and f.stock() == before)
	f.army.combat_units[1].ko = 0.0
	f.army._command_dirty = true
	f.army.settle_combat_command()
	assert(f.army.current_commander == 1 and f.stock() == before)
	f.army.combat_units[0].ko = 0.0
	f.army._command_dirty = true
	f.army.settle_combat_command()
	assert(f.army.formal_commander == 0 and f.army.current_commander == 0 and f.army.acting_commander == -1)
	assert(f.army.officer_service == [1] and f.army.officer_order == [1] and f.stock() == before)
	assert(f.army.combat_units[0].item_state.equipped.cape == commander_cape and f.army.combat_units[1].item_state.equipped.cape == officer_cape)
	assert(f.controller.person_appearance(4) == officer_look and f.controller.cape_policy_guard().ok and not f.controller._auto_save_blocked)
	# Existing explicit personnel removal is different from handback. A current
	# acting commander cannot use transient authority to retain a removed office.
	f.army.combat_units[0].ko = 10.0
	f.army._command_dirty = true
	f.army.settle_combat_command()
	assert(f.army.record_officer_service([1], false).code == "STORAGE_FULL" and f.stock() == before)
	f.army.combat_units[1].cargo.clear()
	var record: Dictionary = f.terrain.site.item_records[officer_cape].duplicate(true)
	assert(f.army.record_officer_service([1], false).ok)
	assert(f.army.current_commander == 1 and not f.controller.person_can_wear_cape(4))
	assert(f.army.officer_service.is_empty() and f.army.officer_order.is_empty())
	assert(not f.army.combat_units[1].item_state.equipped.has("cape") and f.army.combat_units[1].item_state.item_ids.has(officer_cape))
	assert(f.terrain.site.item_records[officer_cape] == record)
	f.close()
	_completed_groups += 1

func _acting_is_not_appointment() -> void:
	var f := Fixture.new()
	var cape := f.item(4)
	f.source.controlled_id = 4
	var before := f.stock()
	f.army.combat_units[0].ko = 10.0
	f.army._command_dirty = true
	f.army.settle_combat_command()
	assert(f.army.formal_commander == 0 and f.army.current_commander == 1)
	assert(not f.controller.person_can_wear_cape(4) and f.army.officer_service.is_empty())
	assert(f.controller.equipment_orders.begin_personal(4, "cape", cape).code == "CAPE_ROLE_RESTRICTED")
	assert(f.stock() == before, "Random temporary command never appoints an officer or moves items")
	f.army.combat_units[0].ko = 0.0
	f.army._command_dirty = true
	f.army.settle_combat_command()
	assert(f.army.current_commander == 0 and not f.army.officer_order.has(1))
	assert(f.stock() == before and not f.controller.person_can_wear_cape(4))
	# The original permanent-vacancy branch is untouched: a deceased formal
	# commander is succeeded by a real new formal commander, not an invented rank.
	f.army.combat_units[0].hp = 0.0
	f.army._command_dirty = true
	f.army.settle_combat_command()
	assert(f.army.formal_commander == 1 and f.army.current_commander == 1 and f.army.acting_commander == -1)
	assert(f.controller.person_can_wear_cape(4) and f.stock() == before)
	var prepared := f.controller.equipment_orders.prepare(4, {"mode": "personal", "slot": "cape", "item_id": cape})
	assert(prepared.ok and f.controller.equipment_orders.commit(prepared.order).ok)
	f.close()
	_completed_groups += 1

func _strict_atlas() -> void:
	var f := Fixture.new()
	var row: Dictionary = f.army.combat_units[1]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"))
	assert(manifest.appearance.parts.cape == "none")
	row.appearance = manifest.appearance.duplicate(true)
	row.item_state = {}
	assert(SiteRuntime.seed_person_equipment(f.terrain, row.item_state, 4, row.appearance).ok)
	row.visual_role = "male_atlas"
	f.item(4, "cape", "cape_travel_01", true)
	var result := f.controller.reconcile_cape_roles([4])
	assert(result.ok, "Current admitted male standard is actually capeless: " + str(result))
	row.appearance.parts.face = "face_standard_04"
	f.item(4, "cape", "cape_chinese_01", true)
	var before := f.stock()
	result = f.controller.reconcile_cape_roles([4])
	assert(result.code == "ATLAS_REQUIRED" and f.stock() == before, "No source/recipe bypass or silent hiding: " + str(result))
	row.appearance = TerrainArmy.EquipmentAtlas.female_appearance()
	assert(row.appearance.parts.cape == "none")
	row.visual_role = "female_atlas"
	assert(f.controller.reconcile_cape_roles([4]).ok, "Current admitted female standard also permits legacy retirement")
	f.close()
	_completed_groups += 1

func _saved_roles() -> void:
	var row := {"person_id": 12, "hp": 100.0, "member": true, "departed": false, "item_state": {"equipped": {"cape": "original"}}}
	var team := {"roster_version": 1, "units": [row], "formal_commander": -1, "current_commander": -1, "officers": [], "officer_service": [], "player_member": {}}
	var state := {"actors": {}, "armies": [team], "equipment_nations": {}}
	var before := JSON.stringify(state)
	assert(Store._validate_cape_roles(state).code == "CAPE_ROLE_RESTRICTED" and JSON.stringify(state) == before)
	team.officer_service = [0]
	assert(Store._validate_cape_roles(state).ok)
	team.officer_service = []
	team.current_commander = 0
	assert(Store._validate_cape_roles(state).code == "CAPE_ROLE_RESTRICTED", "Saved temporary command alone does not establish an office")
	team.officers = [0]
	row.ko = 10.0
	team.current_commander = -1
	assert(Store._validate_cape_roles(state).ok, "A KO officer keeps the same continuing office in a saved state")
	team.officers = []
	team.formal_commander = 0
	assert(Store._validate_cape_roles(state).ok)
	row.member = false
	assert(Store._validate_cape_roles(state).code == "CAPE_ROLE_RESTRICTED")
	row.item_state.equipped.clear()
	row.appearance = {"parts": {"cape": "cape_travel_01"}}
	assert(Store._validate_cape_roles(state).ok, "Real holder beats stale saved costume")
	row.erase("item_state")
	assert(Store._validate_cape_roles(state).code == "CAPE_ROLE_RESTRICTED", "Legacy appearance-only cape cannot bypass pre-restore policy")
	state.equipment_nations.real = {"military_head": 12, "members": [12], "standards": {}}
	assert(Store._validate_cape_roles(state).ok)
	state.equipment_nations.real.members.clear()
	assert(Store._validate_cape_roles(state).code == "CAPE_ROLE_RESTRICTED")
	row.hp = 0.0
	assert(Store._validate_cape_roles(state).ok, "A corpse is preserved as original property, not a wearer")
	_completed_groups += 1

func _save_boundary() -> void:
	var f := Fixture.new()
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "cape-role-save-fixture")
	assert(SiteRuntime.initialize_item_storage(data.site).ok)
	for actor: TerrainTestCharacter in [f.character, f.npc]:
		actor.data = data
		actor.terrain_cell = data.spawn_cell
		actor.movement_from_cell = data.spawn_cell
		actor.position = (Vector2(data.spawn_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		actor._movement_start = actor.position
		actor.item_state = SiteRuntime.new_item_state("person:%d" % actor.person_id)
	data.site.player_cell = data.index(data.spawn_cell)
	data.site.worker.cell = data.index(data.spawn_cell)
	var created := SiteRuntime.create_equipment(data, f.character.item_state, "cape:cape_travel_01",
		{"slot": "cape", "asset": "cape_travel_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 1, "cape")
	assert(created.ok)
	data.site.actors = {"player": f.character.capture_state(), "npc": f.npc.capture_state()}
	data.site.equipment_nations = {"real": {"military_head": 1, "members": [1, 2], "standards": {}}}
	var path := OUT + "/authorized_save.json"
	var result := Store.save(data, path)
	assert(result.ok, str(result))
	assert(Store.load_site(path).ok)
	var digest := FileAccess.get_sha256(path)
	data.site.equipment_nations.real.military_head = 2
	assert(Store.save(data, path).code == "CAPE_ROLE_RESTRICTED" and FileAccess.get_sha256(path) == digest)
	# Valid envelope and valid prior schemas, but an unauthorized real wearer.
	var payload: Dictionary = Store._read(path).payload
	payload.state.equipment_nations.real.military_head = 2
	var body := JSON.stringify(payload, "", true, true)
	var incoming := OUT + "/rejected_save.json"
	var file := FileAccess.open(incoming, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()
	var incoming_hash := FileAccess.get_sha256(incoming)
	var before := JSON.stringify(data.site)
	result = Store.load_site(incoming)
	assert(result.code == "CAPE_ROLE_RESTRICTED", str(result))
	assert(FileAccess.get_sha256(incoming) == incoming_hash and JSON.stringify(data.site) == before)
	assert(f.character.item_state.equipped.cape == created.item_id, "Rejection preserves both scene and file instead of deleting/drop-migrating property")
	f.close()
	_completed_groups += 1
