extends SceneTree
## Atomic batch contract on original Orders/Actions/Army/holders; no GPU claim.

const PersonTest = preload("res://scripts/tests/site_person_actions_test.gd")

class Fixture extends RefCounted:
	var source := PersonTest.Fixture.new()
	var terrain: TerrainData = source.terrain
	var character: TerrainTestCharacter = source.character
	var npc: TerrainTestNPC = source.npc
	var army: TerrainArmy = source.army
	var combat_armies: Array[TerrainArmy] = [army]
	var actions: SitePersonActions = source.actions
	var orders := SiteEquipmentOrders.new()
	var old_ids: Array[String] = []
	var new_ids: Array[String] = []
	var external_busy := 0
	func _init(stock_count: int = 3, member_count: int = 3) -> void:
		terrain.site.inventory = {}
		terrain.site.capacity = maxi(20, maxi(stock_count, member_count))
		terrain.site.depot_cell = terrain.index(Vector2i(5, 4))
		source.controlled_id = 3
		var template: Dictionary = army.combat_units[0].duplicate(true)
		army.combat_units.clear()
		army.cells.clear()
		army.moving_to.clear()
		army.roster_size = member_count
		army.current_commander = 0
		army.formal_commander = 0
		army.combat_order = TerrainArmy.CombatOrder.HOLD
		army.command_reference_valid = true
		army.command_reference = Vector2(4, 4)
		army.command_radius = 20.0
		# Keep the original three-person fixture cells, then fill distinct legal
		# cells within its existing 12x12 terrain for the larger contract case.
		var positions: Array[Vector2i] = [Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6)]
		for y: int in 12:
			for x: int in 12:
				var cell := Vector2i(x, y)
				if not positions.has(cell) and cell != Vector2i(5, 4): positions.append(cell)
		var members: Array[int] = []
		for index: int in member_count:
			var identity := index + 3
			members.append(identity)
			var row := template.duplicate(true)
			row.person_id = identity
			row.item_state = SiteRuntime.new_item_state("person:%d" % identity)
			row["member"] = true
			# Same rank convention as TerrainArmy.enable_combat: the first captain is the officer.
			row["military_role"] = "officer" if index == 0 else "soldier"
			row["present"] = true
			row["appearance"] = HumanCharacter3DEditor.default_appearance(0)
			row.appearance.parts.cape = "none"
			army.combat_units.append(row)
			army.cells.append(positions[index])
			army.moving_to.append(TerrainArmy.INVALID_CELL)
			old_ids.append(item(row.item_state, "longsword_01", identity, true))
		for index: int in stock_count: new_ids.append(item(terrain.site.depot_items, "spear_01", 1))
		actions.init(self)
		orders.init(self, actions)
		orders.equipment_apply_guard = _appearance
		orders.equipment_team_apply_guard = _appearance
		orders.equipment_team_external_duty_guard = func(identity: int) -> bool: return identity == external_busy
		terrain.site.equipment_nations = {"batch": {"military_head": 3, "members": members, "standards": {}}}
		var standard := orders.set_standard(3, "batch", "line", "Original spear issue", {"weapon": {"definition": "weapon:spear_01"}})
		assert(standard.ok, str(standard))
	func _combat_target(identity: int) -> Dictionary:
		var index := army.index_for_identity(identity)
		if index >= 0:
			return {"owner": army, "unit": index, "cell": army.cells[index], "hp": army.combat_units[index].hp}
		return source._combat_target(identity)
	# Core SitePersonActions._person reads lab.site_controller and TerrainLab._original_person_target.
	var site_controller: Variant = null
	func _original_person_target(identity: int, with_bodies: bool = false) -> Dictionary:
		var person: Dictionary = _combat_target(identity)
		if not person.is_empty() and with_bodies: person.bodies = []
		return person
	func controlled_person_id() -> int:
		return source.controlled_id
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return source.threatened
	func _appearance(identity: int, planned: Dictionary) -> Dictionary:
		var appearance := HumanCharacter3DEditor.default_appearance(0)
		for slot: String in SiteRuntime.EQUIPMENT_SLOTS: appearance.parts[slot] = "none"
		for slot: String in planned:
			appearance.parts[slot] = terrain.site.item_definitions[terrain.site.item_records[planned[slot]].definition].asset
		assert(not actions._person(identity).is_empty())
		return SiteRuntime.ok("Fixture asset query only", {"appearance": appearance})
	func item(holder: Dictionary, asset: String, owner_id: int, worn: bool = false) -> String:
		var made := SiteRuntime.create_equipment(terrain, holder, "weapon:" + asset,
			{"slot": "weapon", "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, owner_id, "weapon" if worn else "")
		assert(made.ok)
		return str(made.item_id)
	func stock() -> Array:
		var holders := []
		for row: Dictionary in army.combat_units: holders.append([row.item_state.duplicate(true), row.cargo.duplicate(true)])
		return [holders, terrain.site.item_records.duplicate(true), terrain.site.item_definitions.duplicate(true),
			terrain.site.depot_items.duplicate(true), terrain.site.inventory.duplicate(true), terrain.site.next_item]
	func prepare(include_player: bool = true, selected_ids: Array[int] = []) -> Dictionary:
		return orders.prepare_team_issue(army, 3, 3, "batch", "line", include_player, selected_ids)
	func begin() -> Dictionary:
		return orders.begin_team_issue(army, 3, 3, "batch", "line", true)
	func close() -> void:
		if actions.is_busy(3): actions.cancel(3)
		actions.equipment_orders = null
		orders.equipment_apply_guard = Callable()
		orders.equipment_team_apply_guard = Callable()
		orders.equipment_team_external_duty_guard = Callable()
		orders.actions = null
		orders.lab = null
		source.close()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(1))
	_shortage_and_player_scope()
	_timed_atomic_success()
	_hundred_member_contract()
	for reason: String in ["holder", "version", "depot", "depot_version", "cargo", "member", "control", "hit", "move", "duty", "standard"]:
		_commit_refusal(reason)
	_selected_final_troop()
	_last_contact_refuses_all()
	_cancel_all()
	print("SITE TEAM EQUIPMENT ORDERS PASS: pure unique allocation including 100 members, 99/100 shortage all-or-none, actual controlled-person opt-in, one five-second job, one depot version, unchanged item identities, commit invalidation, selected-subset full-team troop guard and group cancel; fixture asset query, no GPU/UI proof")
	quit(0)

func _shortage_and_player_scope() -> void:
	var f := Fixture.new(2)
	var before := f.stock()
	assert(f.prepare().code == "MATERIALS" and f.stock() == before)
	assert(f.begin().code == "MATERIALS" and f.actions.save_guard().ok and f.stock() == before)
	var selected := f.prepare(false)
	assert(selected.ok and selected.target_ids == [4, 5] and selected.changed_ids == [4, 5], str(selected))
	assert(selected.take_count == 2 and selected.return_count == 2 and f.stock() == before)
	assert(not f.prepare(false, [3, 4]).ok and f.stock() == before, "The original controlled captain also requires explicit player inclusion")
	assert(not f.prepare(true, [4, 4]).ok and f.stock() == before)
	f.close()

func _timed_atomic_success() -> void:
	var f := Fixture.new()
	var before := f.stock()
	var query := f.prepare()
	assert(query.ok and query.target_ids == [3, 4, 5] and query.changed_ids == [3, 4, 5], str(query))
	assert(query.take_count == 3 and query.return_count == 3 and query.recipe_count == 1, "Three original people share one geometry recipe; the fixture query does not prove GPU capture")
	assert(f.orders.check_team_issue(query.order).ok and f.stock() == before)
	var begun := f.begin()
	assert(begun.ok, str(begun))
	for identity: int in [3, 4, 5]: assert(f.actions.is_busy(identity))
	assert(f.actions.save_guard().code == "BUSY")
	f.actions.advance(4.999)
	assert(f.actions.settle_after_contacts().is_empty() and f.stock() == before)
	f.actions.advance(0.001)
	assert(f.stock() == before, "The clock cannot commit before contact settlement")
	var results := f.actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok, str(results))
	var seen := {}
	for index: int in 3:
		var holder: Dictionary = f.army.combat_units[index].item_state
		var issued := str(holder.equipped.weapon)
		assert(f.new_ids.has(issued) and not seen.has(issued))
		seen[issued] = true
		assert(holder.version == before[0][index][0].version + 1)
		assert(f.terrain.site.item_records[issued].holder == "person:%d" % (index + 3))
		assert(f.terrain.site.depot_items.item_ids.has(f.old_ids[index]))
		assert(f.terrain.site.item_records[f.old_ids[index]].holder == "depot")
	assert(f.terrain.site.depot_items.version == before[3].version + 1, "One atomic depot transaction, not three conflicting individual issues")
	assert(f.terrain.site.item_records.size() == before[1].size() and f.terrain.site.next_item == before[5])
	for item_id: String in before[1]:
		var expected: Dictionary = before[1][item_id].duplicate(true)
		expected.holder = f.terrain.site.item_records[item_id].holder
		assert(expected == f.terrain.site.item_records[item_id], "Only planned holder changes; original owner/dye/definition persist")
	assert(f.source.changed.size() == 3 and f.actions.save_guard().ok)
	assert(f.actions.settle_after_contacts().is_empty())
	assert(f.prepare().code == "NO_CHANGE", "Already matching gear is retained without consuming duplicate stock")
	f.close()

func _hundred_member_contract() -> void:
	var short := Fixture.new(99, 100)
	var short_before := short.stock()
	assert(short.prepare().code == "MATERIALS" and short.stock() == short_before, "One missing item must refuse all 100 original people")
	assert(short.begin().code == "MATERIALS" and short.stock() == short_before and short.actions.save_guard().ok and short.source.changed.is_empty())
	short.close()
	var f := Fixture.new(100, 100)
	var before := f.stock()
	var query := f.prepare()
	assert(query.ok and query.target_ids.size() == 100 and query.changed_ids.size() == 100, str(query))
	assert(query.take_count == 100 and query.return_count == 100 and query.recipe_count == 1)
	var positions := {}
	var assigned := {}
	for index: int in 100:
		var cell: Vector2i = f.army.cells[index]
		assert(cell.x >= 0 and cell.y >= 0 and cell.x < 12 and cell.y < 12 and not positions.has(cell))
		positions[cell] = true
		var entry: Dictionary = query.order.entries[index]
		var item_id := str(entry.planned.weapon)
		assert(entry.person_id == index + 3 and entry.take == [item_id] and entry["return"] == [f.old_ids[index]])
		assert(f.new_ids.has(item_id) and not assigned.has(item_id), "Preview must allocate 100 distinct real depot IDs")
		assigned[item_id] = true
	assert(assigned.size() == 100 and f.orders.check_team_issue(query.order).ok and f.stock() == before, "100-person preflight is pure")
	assert(f.begin().ok and f.actions.save_guard().code == "BUSY")
	for identity: int in query.target_ids: assert(f.actions.is_busy(identity))
	f.actions.advance(4.999)
	assert(f.actions.settle_after_contacts().is_empty() and f.stock() == before)
	f.actions.advance(0.001)
	assert(f.stock() == before, "All 100 original holders remain unchanged until contact settlement")
	var results := f.actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok and results[0].changed_ids.size() == 100, str(results))
	for index: int in 100:
		var holder: Dictionary = f.army.combat_units[index].item_state
		var item_id := str(holder.equipped.weapon)
		assert(item_id == str(query.order.entries[index].planned.weapon) and holder.item_ids == [item_id])
		assert(holder.version == before[0][index][0].version + 1 and f.terrain.site.item_records[item_id].holder == "person:%d" % (index + 3))
		assert(f.terrain.site.depot_items.item_ids.has(f.old_ids[index]) and f.terrain.site.item_records[f.old_ids[index]].holder == "depot")
		assert(not f.terrain.site.depot_items.item_ids.has(item_id) and not f.actions.is_busy(index + 3))
	assert(f.terrain.site.depot_items.item_ids.size() == 100 and f.terrain.site.depot_items.version == before[3].version + 1, "100 people publish one depot transaction")
	assert(f.terrain.site.item_records.size() == before[1].size() and f.terrain.site.next_item == before[5])
	for item_id: String in before[1]:
		assert(f.terrain.site.item_records.has(item_id), "Original IDs are conserved")
		var expected: Dictionary = before[1][item_id].duplicate(true)
		expected.holder = f.terrain.site.item_records[item_id].holder
		assert(expected == f.terrain.site.item_records[item_id], "Only holder changes in the 100-person transaction")
	assert(f.source.changed.size() == 100 and f.actions.save_guard().ok and f.actions.settle_after_contacts().is_empty())
	f.close()

func _commit_refusal(reason: String) -> void:
	var f := Fixture.new()
	var query := f.prepare()
	assert(query.ok, str(query))
	match reason:
		"holder": f.army.combat_units[2].item_state = f.army.combat_units[2].item_state.duplicate(true)
		"version": f.army.combat_units[2].item_state.version += 1
		"depot": f.terrain.site.depot_items = f.terrain.site.depot_items.duplicate(true)
		"depot_version": f.terrain.site.depot_items.version += 1
		"cargo": f.army.combat_units[2].cargo = f.army.combat_units[2].cargo.duplicate(true)
		"member": f.army.combat_units[2].member = false
		"control": f.source.controlled_id = 1
		"hit": f.army.combat_units[2].hit_revision += 1
		"move": f.army.cells[2] += Vector2i.RIGHT
		"duty": f.external_busy = 5
		"standard": f.terrain.site.equipment_nations.batch.standards.line.revision += 1
	var before := f.stock()
	var original_holders := []
	for entry: Dictionary in query.order.entries: original_holders.append(entry.holder.duplicate(true))
	assert(not f.orders.commit_team_issue(query.order).ok, reason)
	assert(f.stock() == before and f.source.changed.is_empty(), "No earlier target may commit before a later refusal: " + reason)
	for index: int in original_holders.size(): assert(query.order.entries[index].holder == original_holders[index], "Detached original holders must also remain unchanged: " + reason)
	f.close()

func _selected_final_troop() -> void:
	var f := Fixture.new()
	for index: int in 2: f.item(f.terrain.site.depot_items, "bow_01", 1)
	assert(f.orders.set_standard(3, "batch", "line", "Original bows", {"weapon": {"definition": "weapon:bow_01"}}).ok)
	var before := f.stock()
	assert(f.prepare(false, [4]).code == "MIXED_TROOP" and f.stock() == before)
	var all_ordinary := f.prepare(false, [4, 5])
	assert(all_ordinary.ok and all_ordinary.target_ids == [4, 5], str(all_ordinary))
	assert(f.orders.commit_team_issue(all_ordinary.order).ok)
	assert(f.army.combat_units[0].item_state.equipped.weapon == f.old_ids[0], "Captain exemption preserves the original sword")
	f.close()

func _cancel_all() -> void:
	var f := Fixture.new()
	var before := f.stock()
	assert(f.begin().ok)
	assert(f.actions.cancel(4).ok, "Any participant cancels the same original group job")
	for identity: int in [3, 4, 5]: assert(not f.actions.is_busy(identity))
	f.actions.advance(100.0)
	assert(f.actions.settle_after_contacts().is_empty() and f.actions.save_guard().ok and f.stock() == before)
	f.close()

func _last_contact_refuses_all() -> void:
	var f := Fixture.new()
	var before := f.stock()
	assert(f.begin().ok)
	f.actions.advance(5.0)
	f.army.combat_units[2].hit_revision += 1
	var result := f.actions.settle_after_contacts()
	assert(result.size() == 1 and not result[0].ok, "The final target's last contact invalidates the entire original batch")
	assert(f.stock() == before and f.source.changed.is_empty() and f.actions.save_guard().ok)
	for identity: int in [3, 4, 5]: assert(not f.actions.is_busy(identity))
	f.close()
