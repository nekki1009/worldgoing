extends SceneTree
## Jobs/real Orders/real holders; availability is a pure fixture query, not GPU evidence.
const PersonTest = preload("res://scripts/tests/site_person_actions_test.gd")
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")

class Fixture extends Node:
	var source := PersonTest.Fixture.new()
	var terrain: TerrainData = source.terrain
	var character: TerrainTestCharacter = source.character
	var npc: TerrainTestNPC = source.npc
	var army: TerrainArmy = source.army
	var combat_armies: Array[TerrainArmy] = [army]
	var actions: SitePersonActions = source.actions
	var orders := Orders.new()
	var available := false
	var query_code := "ATLAS_REQUIRED"
	var queries := 0
	var old_item := ""
	var new_item := ""
	var appearance := HumanCharacter3DEditor.default_appearance(0)
	func _init() -> void:
		terrain.site.inventory = {}
		terrain.site.capacity = 100
		terrain.site.depot_cell = terrain.index(Vector2i(5, 4))
		actions.init(self)
		orders.init(self, actions)
		orders.equipment_apply_guard = _recipe_query
		old_item = item(character.item_state, "weapon", "longsword_01", true)
		new_item = item(terrain.site.depot_items, "weapon", "spear_01")
		terrain.site.equipment_nations = {"n1": {"military_head": 2, "members": [1, 2, 3], "standards": {}}}
		assert(orders.set_standard(2, "n1", "line", "槍兵", {"weapon": {"definition": "weapon:spear_01"}}).ok)
		appearance.parts.weapon = "spear_01"
	func _combat_target(identity: int) -> Dictionary:
		return source._combat_target(identity)
	func controlled_person_id() -> int:
		return source.controlled_id
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return false
	func _recipe_query(_identity: int, _equipped: Dictionary) -> Dictionary:
		queries += 1
		if available: return SiteRuntime.ok()
		var missing := SiteRuntime.fail(query_code, "fixture availability query")
		if query_code == "ATLAS_REQUIRED": missing.appearance = appearance.duplicate(true)
		return missing
	func item(holder: Dictionary, slot: String, asset: String, worn: bool = false) -> String:
		var made := SiteRuntime.create_equipment(terrain, holder, slot + ":" + asset,
			{"slot": slot, "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, 1, slot if worn else "")
		assert(made.ok)
		return str(made.item_id)
	func stock() -> String:
		return JSON.stringify([terrain.site.item_records, terrain.site.depot_items, terrain.site.inventory,
			character.item_state, terrain.site.manual.cargo, npc.item_state, army.combat_units[0].item_state])
	func begin() -> Dictionary:
		var started := orders.begin_issue(1, "n1", "line")
		assert(started.ok and started.preparing)
		return actions._jobs["1"]
	func close() -> void:
		actions._jobs.clear()
		actions.equipment_orders = null
		orders.equipment_apply_guard = Callable()
		orders.actions = null
		orders.lab = null
		source.close()
		queue_free()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(1))
	_pure_prepare()
	_pending_and_success()
	_cancel_and_replacement()
	for phase: String in ["advance", "settle", "complete"]:
		for reason: String in ["move", "hit", "ko", "death", "site", "terrain", "holder", "cargo", "depot", "stock", "person_version", "depot_version", "standard", "member", "owner", "capacity", "guard"]:
			_invalidated(phase, reason)
	_office_and_body()
	_failure_and_lost_admission()
	await _real_deferred_failure()
	await process_frame
	print("SITE EQUIPMENT PREPARATION JOBS PASS: pure prepare/check, same order/holders/versions, pending savebusy/no work/no items, canceled and same-ID replacement isolation, 51 invalidation boundaries, office/body loss, original 5s post-contact commit, real static headless preparation failure; no GPU/capture/admission proof")
	quit(0)

func _pure_prepare() -> void:
	var f := Fixture.new()
	var before := f.stock()
	var prepared := f.orders.prepare(1, {"mode": "issue", "nation_id": "n1", "standard_id": "line"})
	assert(prepared.code == "ATLAS_REQUIRED" and prepared.has("order") and prepared.appearance == f.appearance)
	assert(prepared.order.take == [f.new_item] and prepared.order["return"] == [f.old_item])
	for i: int in 3: assert(f.orders.check(prepared.order).code == "ATLAS_REQUIRED")
	assert(f.stock() == before and f.actions.save_guard().ok and f.actions._jobs.is_empty())
	f.query_code = "UNSUPPORTED"
	assert(f.orders.begin_issue(1, "n1", "line").code == "UNSUPPORTED")
	assert(f.actions._jobs.is_empty() and f.stock() == before)
	f.close()

func _pending_and_success() -> void:
	var f := Fixture.new()
	var job := f.begin()
	var order: Dictionary = job.order
	var holder: Dictionary = f.character.item_state
	var depot: Dictionary = f.terrain.site.depot_items
	var version := int(holder.version)
	var depot_version := int(depot.version)
	var before := f.stock()
	var fatigue := f.character.fatigue
	assert(f.actions.save_guard().code == "BUSY" and not f.actions.is_working(1))
	assert(f.actions.advance(100.0).handled_seconds.is_empty())
	assert(f.actions.settle_after_contacts().is_empty() and float(job.elapsed) == 0.0)
	assert(f.stock() == before and f.character.fatigue == fatigue and f.source.changed.is_empty())
	f.available = true
	assert(f.actions.advance(100.0).handled_seconds.is_empty(), "A pure successful query cannot bypass pending completion")
	f.actions._equipment_prepared(job, true)
	assert(is_same(f.actions._jobs["1"].order, order) and not job.preparing and job.elapsed == 0.0)
	assert(f.actions.is_working(1) and f.actions.save_guard().code == "BUSY")
	f.actions.advance(4.999)
	assert(f.actions.settle_after_contacts().is_empty() and f.stock() == before)
	f.actions.advance(0.001)
	assert(f.stock() == before, "advance never commits before contact settlement")
	assert(f.actions.settle_after_contacts()[0].ok)
	assert(holder.equipped.weapon == f.new_item and depot.item_ids == [f.old_item])
	assert(holder.version == version + 1 and depot.version == depot_version + 1)
	assert(f.terrain.site.item_records[f.new_item].holder == "person:1")
	assert(f.terrain.site.item_records[f.old_item].holder == "depot")
	assert(f.actions.save_guard().ok and f.source.changed == [1])
	f.actions._equipment_prepared(job, true)
	assert(f.actions.settle_after_contacts().is_empty() and holder.version == version + 1)
	f.close()

func _cancel_and_replacement() -> void:
	var f := Fixture.new()
	var first := f.begin()
	var before := f.stock()
	assert(f.actions.cancel(1).ok and f.actions.save_guard().ok)
	f.actions._equipment_prepared(first, true)
	assert(not f.actions.is_busy(1) and f.actions.settle_after_contacts().is_empty())
	var second := f.begin()
	assert(not is_same(first, second))
	f.available = true
	f.actions._equipment_prepared(first, false)
	f.actions._equipment_prepared(first, true)
	assert(is_same(f.actions._jobs["1"], second) and second.preparing)
	assert(f.stock() == before and f.source.changed.is_empty())
	f.actions.cancel(1)
	f.close()

func _invalidated(phase: String, reason: String) -> void:
	var f := Fixture.new()
	var job := f.begin()
	match reason:
		"move": f.character.terrain_cell = Vector2i(4, 5)
		"hit": f.character._received_effective_hit += 1
		"ko": f.character.knockout_left = 10.0
		"death": f.character.hp = 0.0
		"site": f.terrain.site = f.terrain.site.duplicate(true)
		"terrain":
			var replacement := TerrainData.new()
			replacement.allocate(Vector2i(12, 12))
			replacement.site = f.terrain.site.duplicate(true)
			f.terrain = replacement
		"holder": f.character.item_state = f.character.item_state.duplicate(true)
		"cargo": f.terrain.site.manual.cargo = f.terrain.site.manual.cargo.duplicate()
		"depot": f.terrain.site.depot_items = f.terrain.site.depot_items.duplicate(true)
		"stock": f.terrain.site.inventory = f.terrain.site.inventory.duplicate()
		"person_version": f.character.item_state.version += 1
		"depot_version": f.terrain.site.depot_items.version += 1
		"standard": f.terrain.site.equipment_nations.n1.standards.line.revision += 1
		"member": f.terrain.site.equipment_nations.n1.members.erase(1)
		"owner": f.terrain.site.item_records[f.new_item].holder = "person:2"
		"capacity": f.terrain.site.capacity = -1
		"guard": f.query_code = "UNSUPPORTED"
	var before := f.stock()
	var old_holder: Dictionary = job.executor_holder
	var original_before := JSON.stringify([old_holder, job.depot_holder, job.site_state.item_records])
	if phase == "advance": f.actions.advance(100.0)
	elif phase == "complete": f.actions._equipment_prepared(job, true)
	var results := f.actions.settle_after_contacts()
	assert(results.size() == 1 and not results[0].ok, phase + "/" + reason)
	assert(not f.actions.is_busy(1) and f.stock() == before and f.source.changed.is_empty(), reason)
	assert(JSON.stringify([old_holder, job.depot_holder, job.site_state.item_records]) == original_before, reason)
	f.available = true
	f.actions._equipment_prepared(job, true)
	assert(not f.actions.is_busy(1) and f.actions.settle_after_contacts().is_empty(), "No auto-resubmit: " + reason)
	f.close()

func _office_and_body() -> void:
	var f := Fixture.new()
	var cape := f.item(f.character.item_state, "cape", "cape_travel_01")
	f.terrain.site.equipment_nations.n1.military_head = 1
	assert(f.orders.begin_personal(1, "cape", cape).preparing)
	var job: Dictionary = f.actions._jobs["1"]
	f.terrain.site.equipment_nations.n1.military_head = 2 # Actual authority changes while preparing.
	var before := f.stock()
	f.available = true
	f.actions._equipment_prepared(job, true)
	assert(f.actions.settle_after_contacts()[0].code == "CAPE_ROLE_RESTRICTED")
	assert(f.stock() == before and f.character.item_state.item_ids.has(cape))
	f.source.controlled_id = 3
	var spare := f.item(f.army.combat_units[0].item_state, "weapon", "spear_01")
	f.available = false
	assert(f.orders.begin_personal(3, "weapon", spare).preparing)
	job = f.actions._jobs["3"]
	f.army.combat_units[0] = f.army.combat_units[0].duplicate() # Same holder/version, different original body.
	f.available = true
	f.actions._equipment_prepared(job, true)
	assert(f.actions.settle_after_contacts()[0].code == "STALE_SOURCE")
	assert(f.army.combat_units[0].item_state.equipped.is_empty())
	f.close()

func _failure_and_lost_admission() -> void:
	for complete: bool in [false, true]:
		var f := Fixture.new()
		var job := f.begin()
		var before := f.stock()
		f.actions._equipment_prepared(job, complete) # Still missing even if capture claims success.
		var result: Dictionary = f.actions.settle_after_contacts()[0]
		assert(result.code == "ATLAS_PREPARATION_FAILED" and "保留" in str(result.message))
		assert(f.stock() == before and f.actions.save_guard().ok and f.source.changed.is_empty())
		f.close()
	var f := Fixture.new()
	var job := f.begin()
	f.available = true
	f.actions._equipment_prepared(job, true)
	f.actions.advance(5.0)
	f.available = false # Strict admission disappearing at commit never triggers another preparation.
	var before := f.stock()
	assert(f.actions.settle_after_contacts()[0].code == "ATLAS_REQUIRED")
	assert(f.stock() == before and not f.actions.is_busy(1))
	f.close()

func _real_deferred_failure() -> void:
	var f := Fixture.new()
	root.add_child(f)
	f.appearance.parts.face = "face_standard_08"
	f.appearance.parts.armor = "armor_japanese_steel_01"
	f.appearance.parts.helmet = "helmet_cloth_japanese_01"
	assert(HumanCharacter3DEditor.valid_appearance(f.appearance))
	assert(not TerrainArmy.EquipmentAtlas.supports(f.appearance), "The real helper must need preparation, not hit an admitted fixture recipe")
	var job := f.begin()
	var before := f.stock()
	# Actual static helper cannot capture on headless; no production callback injection.
	for frame: int in 3: await process_frame
	var result: Dictionary = f.actions.settle_after_contacts()[0]
	assert(result.code == "ATLAS_PREPARATION_FAILED" and "保留" in str(result.message))
	assert(not f.actions.is_busy(1) and f.stock() == before and job.elapsed == 0.0)
	f.close()
