extends SceneTree

var completed := 0
const LARGE_SAVE := "res://.godot-temp/site_resources_contract/building_large_farm.json"

class CrewFixture extends RefCounted:
	var terrain: TerrainData
	var army := TerrainArmy.new()
	var combat_armies: Array[TerrainArmy] = []
	var combat_actors: Array[TerrainTestCharacter] = []
	var crew := SiteWorkTeam.new()
	func setup(tree_root: Node, data: TerrainData, positions: Array[Vector2i], snapshot: Dictionary = {}) -> void:
		terrain = data
		tree_root.add_child(army)
		army.set_process(false)
		army.team_id = 1
		army.faction_id = 1
		army.roster_size = positions.size()
		if snapshot.is_empty():
			assert(army.deploy_at(terrain, null, null, positions))
			assert(army.enable_combat(false))
		else:
			army.restore_combat_state(snapshot, terrain, null, null)
		combat_armies.append(army)
		if snapshot.is_empty():
			for row: Dictionary in army.combat_units:
				row["cargo"] = {}
				row["item_state"] = SiteRuntime.new_item_state("person:" + str(row.person_id))
		crew.init(self)
	func _combat_target(identity: int) -> Dictionary:
		var index := army.index_for_identity(identity)
		return {"owner": army, "unit": index, "cell": army.cells[index], "hp": army.combat_units[index].hp} if index >= 0 else {}
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return false
	func controlled_person_id() -> int:
		return -1
	func close() -> void:
		crew.lab = null
		army.free()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(35.0).timeout.connect(func() -> void: quit(1))
	_check_layout_and_legacy()
	_check_walls_stairs_and_repair()
	_check_gate_operations()
	_check_resize_livestock_and_refunds()
	_check_expansion_clearing()
	_check_original_workers_shared_batch()
	_check_large_farm_store_resume()
	_check_prison_and_validation()
	TerrainArmy.release_contact_source()
	assert(completed == 8, "A building contract stopped before completion")
	print("SITE_BUILDING_RUNTIME_CONTRACT_PASS: formal footprints/rotation/legacy, effective walls and stairs, unique-exit guard, paid repair, gate operator and occupancy, same-ID expansion/shrink with preserved HP and no recycled materials, strict expansion cost/work, livestock conservation and overloaded shrink rejection, real worker slots/shared batch/fatigue, 2500-cell and shrunk-wall Store roundtrip with two original workers resume, prison geometry and malformed layouts; no visual or combat-performance claim")
	quit(0)

func _fixture() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(72, 72))
	data.spawn_cell = Vector2i(3, 3)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "building-runtime-contract")
	data.resource_base.clear()
	data.site.changes.clear()
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.ramp_edges.fill(0)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.foundation.fill(80)
	data.fertility.fill(60)
	data.moisture.fill(70)
	data.groundwater.fill(80)
	data.drainage.fill(70)
	data.site.depot_cell = data.index(Vector2i(3, 3))
	data.site.worker.cell = data.index(Vector2i(3, 4))
	for item: String in SiteEnvironment.ITEM_NAMES:
		data.site.inventory[item] = 1000
	data.site.capacity = 100000
	assert(SiteRuntime.initialize_item_storage(data.site).ok)
	SiteEnvironment.rebuild_indexes(data)
	return data

func _cells(data: TerrainData, kind: String, anchor: Vector2i, size: Vector2i = Vector2i.ONE, options: Dictionary = {}) -> Array[int]:
	var layout := SiteRuntime.building_cells(data, kind, anchor, size, options)
	assert(layout.ok, str(layout))
	var result: Array[int] = []
	result.assign(layout.cells)
	return result

func _task(key: String, action: String, cell: int, zone: int = -1, slot: int = -1) -> Dictionary:
	return {"version": 2, "zone": zone, "target": "feature:" + key, "action": action,
		"work_cell": cell, "cell": cell, "mode": "work", "progress": 0.0, "status": "", "work_slot": slot}

func _build(data: TerrainData, kind: String, anchor: Vector2i, size: Vector2i = Vector2i.ONE, options: Dictionary = {}) -> String:
	var chosen := options.duplicate()
	chosen["owner_faction"] = 1
	var result := SiteRuntime.request_build(data, kind, _cells(data, kind, anchor, size, chosen), Callable(), chosen)
	assert(result.ok, str(result))
	var key := str(result.feature)
	var feature: Dictionary = data.site.features[key]
	var task := _task(key, "construct", int(feature.entrance))
	SiteRuntime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	assert(str(feature.stage) == "complete", str(task))
	assert(SiteRuntime.validate_feature_layout(data, feature).ok)
	return key

func _check_layout_and_legacy() -> void:
	var data := _fixture()
	assert(SiteRuntime.building_spec("house", {"variant": "small"}).size == Vector2i(2, 2))
	assert(SiteRuntime.building_spec("house", {"variant": "long", "quarter": 1}).size == Vector2i(3, 4))
	assert(SiteRuntime.building_spec("house", {"variant": "large"}).size == Vector2i(5, 4))
	assert(SiteRuntime.building_spec("gate", {"quarter": 3}).size == Vector2i(3, 4))
	var before := JSON.stringify(data.site.inventory)
	assert(not SiteRuntime.request_build(data, "house", [data.index(Vector2i(8, 8))]).ok)
	assert(JSON.stringify(data.site.inventory) == before)
	var field := _cells(data, "farm", Vector2i(10, 10), Vector2i(50, 50))
	assert(field.size() == 2500)
	var key := _build(data, "farm", Vector2i(10, 10), Vector2i(50, 50))
	var slots := SiteRuntime.feature_work_slots(data, data.site.features[key])
	assert(slots.size() == 81)
	var covered := {}
	for slot: Dictionary in slots:
		assert(slot.service_cells.size() <= 36 and slot.service_cells.has(int(slot.cell)))
		for index: int in slot.service_cells:
			assert(not covered.has(index))
			covered[index] = true
	assert(covered.size() == 2500)
	SiteRuntime.set_operating_slots(data, [{"task": _task(key, "operate", int(slots[0].cell), -1, 0)}])
	assert(int(SiteRuntime.feature_production_info(data, key).served_cells) == 36)
	var old := {"kind": "house", "cells": [data.index(Vector2i(5, 5))], "entrance": data.index(Vector2i(5, 6)), "stage": "complete", "solid": true}
	assert(SiteRuntime.validate_feature_layout(data, old).ok)
	assert(SiteRuntime.feature_geometry(data, old).blocked == old.cells)
	assert(not old.has("layout_version"))
	for kind: String in ["stone_wall", "wall_stairs", "gate", "prison"]:
		var missing_version := old.duplicate(true)
		missing_version.kind = kind
		assert(not SiteRuntime.validate_feature_layout(data, missing_version).ok, "New building kind masqueraded as a legacy feature")
	completed += 1

func _check_walls_stairs_and_repair() -> void:
	var data := _fixture()
	var wall_cell := Vector2i(20, 10)
	var wall := _build(data, "palisade", wall_cell)
	var stairs := _build(data, "wall_stairs", Vector2i(20, 11))
	assert(data.height_levels[data.index(wall_cell)] == 0 and data.navigation_heights()[data.index(wall_cell)] == 2)
	var raised_base: Dictionary = data.site.features[wall].duplicate(true)
	raised_base.level = 5
	assert(not SiteRuntime.validate_feature_layout(data, raised_base, false).ok, "Saved wall invented a higher natural foundation")
	assert(data.can_step(Vector2i(20, 13), Vector2i(20, 12)))
	assert(data.can_step(Vector2i(20, 12), Vector2i(20, 11)))
	assert(data.can_step(Vector2i(20, 11), wall_cell))
	assert(not data.can_step(Vector2i(19, 12), Vector2i(20, 12)))
	var trapped := SiteRuntime.cancel_feature(data, stairs, func(cell: Vector2i) -> bool: return cell == wall_cell, 1)
	assert(not trapped.ok and trapped.code == "UNREACHABLE", str(trapped))
	var wall_part := "c:%d" % data.index(wall_cell)
	assert(SiteRuntime.damage_structure_part(data, wall, wall_part, 40.0).ok)
	var wood := int(data.site.inventory.wood)
	assert(not SiteRuntime.request_repair(data, wall, wall_part, 2).ok)
	assert(int(data.site.inventory.wood) == wood)
	assert(SiteRuntime.request_repair(data, wall, wall_part, 1).ok)
	var feature: Dictionary = data.site.features[wall]
	var repair: Dictionary = feature.repair
	assert(float(repair.amount) == 40.0 and int(data.site.inventory.wood) < wood)
	assert(SiteRuntime.damage_structure_part(data, wall, wall_part, 30.0).ok)
	var task := _task(wall, "repair", int(repair.work_cell))
	SiteRuntime._feature_work(data, wall, float(repair.work), Callable(), Callable(), task, {}, 20, 1)
	assert(float(feature.parts[wall_part].hp) == 70.0, "Repair healed additional damage for free")
	assert(not feature.has("repair"))
	assert(SiteRuntime.damage_structure_part(data, wall, wall_part, 1000.0).ok)
	assert(data.navigation_heights()[data.index(wall_cell)] == 0)
	assert(SiteRuntime.request_repair(data, wall, wall_part, 1).ok)
	repair = feature.repair
	task = _task(wall, "repair", int(repair.work_cell))
	SiteRuntime._feature_work(data, wall, float(repair.work), func(cell: Vector2i) -> bool: return cell == wall_cell, Callable(), task, {}, 20, 1)
	assert(feature.has("repair") and float(feature.parts[wall_part].hp) == 0.0)
	SiteRuntime._feature_work(data, wall, 0.1, Callable(), Callable(), task, {}, 20, 1)
	assert(float(feature.parts[wall_part].hp) == 100.0)
	var stair_part := "c:%d" % data.index(Vector2i(20, 11))
	var hit := SiteRuntime.damage_structure_part(data, stairs, stair_part, 1000.0)
	assert(hit.ok and not hit.lost_surfaces.is_empty())
	assert(not data.can_step(Vector2i(20, 12), Vector2i(20, 11)))
	assert(data.navigation_heights()[data.index(wall_cell)] == 2)
	completed += 1

func _check_gate_operations() -> void:
	var data := _fixture()
	var key := _build(data, "gate", Vector2i(40, 30), Vector2i.ONE, {"material": "stone"})
	var feature: Dictionary = data.site.features[key]
	var left := Vector2i(41, 31)
	var right := Vector2i(42, 31)
	var operator := {"cell": Vector2i(41, 33), "hp": 100.0, "ko": 0.0, "faction": 1, "ready": true}
	var query := func(identity: int) -> Dictionary: return operator if identity == 17 else {}
	assert(not data.is_walkable(left) and not data.is_walkable(right))
	assert(not SiteRuntime.request_gate(data, key, true, 18, query).ok)
	assert(SiteRuntime.request_gate(data, key, true, 17, query).ok)
	SiteRuntime.advance_gate_operations(data, 1.0, query)
	assert(not bool(feature.gate.open) and str(feature.gate.pending) == "open")
	SiteRuntime.advance_gate_operations(data, 2.0, query)
	assert(bool(feature.gate.open) and data.is_walkable(left))
	var wait := SiteRuntime.request_gate(data, key, false, 17, query, func(cell: Vector2i) -> bool: return cell == left)
	assert(not wait.ok and wait.code == "WAIT_OCCUPANCY" and str(feature.gate.pending).is_empty())
	assert(SiteRuntime.request_gate(data, key, false, 17, query).ok)
	assert(data.is_walkable(left) and not data.can_step(Vector2i(41, 29), Vector2i(41, 30)))
	SiteRuntime.advance_gate_operations(data, 3.0, query, func(cell: Vector2i) -> bool: return cell == right)
	assert(bool(feature.gate.open) and str(feature.gate.pending).is_empty())
	assert(SiteRuntime.request_gate(data, key, false, 17, query).ok)
	SiteRuntime.advance_gate_operations(data, 3.0, query)
	assert(not bool(feature.gate.open) and not data.is_walkable(right))
	assert(SiteRuntime.damage_structure_part(data, key, "leaf:left", 1000.0).ok)
	assert(data.is_walkable(left) and not data.is_walkable(right), "One broken leaf opened the other leaf")
	assert(SiteRuntime.request_gate(data, key, true, 17, query).ok)
	SiteRuntime.advance_gate_operations(data, 3.0, query)
	assert(not SiteRuntime.request_gate(data, key, false, 17, query).ok)
	assert(SiteRuntime.damage_structure_part(data, key, "frame:right", 1000.0).ok)
	assert(float(feature.parts["leaf:right"].hp) == 0.0)
	assert(not SiteRuntime.request_repair(data, key, "leaf:right", 1).ok)
	assert(SiteRuntime.validate_feature_layout(data, feature).ok)
	completed += 1

func _check_resize_livestock_and_refunds() -> void:
	var data := _fixture()
	var key := _build(data, "palisade", Vector2i(20, 20))
	var part := "c:%d" % data.index(Vector2i(20, 20))
	assert(SiteRuntime.damage_structure_part(data, key, part, 40.0).ok)
	var feature: Dictionary = data.site.features[key]
	var larger := _cells(data, "palisade", Vector2i(20, 20), Vector2i(2, 1))
	var before_wood := int(data.site.inventory.wood)
	assert(SiteRuntime.request_resize(data, key, larger, Callable(), 1).ok)
	assert(feature.cells.size() == 1 and float(feature.parts[part].hp) == 60.0)
	var json_feature: Dictionary = JSON.parse_string(JSON.stringify(feature))
	assert(SiteRuntime.validate_feature_layout(data, json_feature, false).ok, "Checked JSON integer cells must retain the original footprint")
	json_feature.pending_build.cells[0] = float(json_feature.pending_build.cells[0]) + 0.25
	assert(not SiteRuntime.validate_feature_layout(data, json_feature, false).ok, "Fractional expansion cells were rounded before validation")
	var wrong_terms := feature.duplicate(true)
	wrong_terms.pending_build.cost["wood"] = 999999
	assert(not SiteRuntime.validate_feature_layout(data, wrong_terms, false).ok, "Saved expansion minted a cancellation refund")
	wrong_terms = feature.duplicate(true)
	wrong_terms.pending_build.work = 0.000001
	assert(not SiteRuntime.validate_feature_layout(data, wrong_terms, false).ok, "Saved expansion skipped its required construction work")
	data.height_levels[data.index(Vector2i(21, 20))] = 1
	assert(not SiteRuntime.validate_feature_layout(data, feature, false).ok, "Expansion accepted a different natural foundation")
	data.height_levels[data.index(Vector2i(21, 20))] = 0
	assert(data.navigation_heights()[data.index(Vector2i(21, 20))] == 0 and data.feature_at[data.index(Vector2i(21, 20))] == int(key))
	assert(SiteRuntime.cancel_feature(data, key, Callable(), 1).ok)
	assert(data.site.features.has(key) and feature.cells.size() == 1 and int(data.site.inventory.wood) == before_wood)
	assert(SiteRuntime.request_resize(data, key, larger, Callable(), 1).ok)
	var pending: Dictionary = feature.pending_build
	var task := _task(key, "construct", int(pending.entrance))
	SiteRuntime._feature_work(data, key, float(pending.work), Callable(), Callable(), task, {}, 20, 1)
	assert(feature.cells.size() == 2 and float(feature.parts[part].hp) == 60.0)
	var replaced_part := "c:%d" % data.index(Vector2i(21, 20))
	assert(float(feature.parts[replaced_part].hp) == 100.0)
	assert(SiteRuntime.damage_structure_part(data, key, replaced_part, 100.0).ok)
	assert(float(feature.parts[replaced_part].hp) == 0.0)
	var smaller := _cells(data, "palisade", Vector2i(20, 20))
	var shrink_preview := SiteRuntime.preview_resize(data, key, smaller)
	assert(shrink_preview.ok and shrink_preview.refund.is_empty(), str(shrink_preview))
	var before_shrink_wood := int(data.site.inventory.wood)
	var next_feature := int(data.site.next_feature)
	var shrunk := SiteRuntime.request_resize(data, key, smaller, Callable(), 1)
	assert(shrunk.ok and str(shrunk.feature) == key, str(shrunk))
	assert(is_same(feature, data.site.features[key]) and int(data.site.next_feature) == next_feature)
	assert(feature.cells == smaller and feature.parts.size() == 1 and float(feature.parts[part].hp) == 60.0, "Shrinking must preserve the retained damaged original part")
	assert(int(data.site.inventory.wood) == before_shrink_wood, "Removing a ruined completed part cannot refund its consumed materials")
	assert(data.feature_at[data.index(Vector2i(21, 20))] == 0 and data.navigation_heights()[data.index(Vector2i(21, 20))] == 0)
	assert(SiteRuntime.validate_feature_layout(data, feature).ok)
	var rebuild_preview := SiteRuntime.preview_resize(data, key, larger)
	assert(rebuild_preview.ok and int(rebuild_preview.cost.wood) == 4)
	data.site.inventory.wood = int(rebuild_preview.cost.wood) - 1
	var insufficient := JSON.stringify(data.site)
	var rejected_rebuild := SiteRuntime.request_resize(data, key, larger, Callable(), 1)
	assert(not rejected_rebuild.ok and str(rejected_rebuild.code) == "MATERIALS", str(rejected_rebuild))
	assert(JSON.stringify(data.site) == insufficient, "Insufficient rebuilding materials must not mutate the original feature, zones or inventory")
	data.site.inventory.wood = before_shrink_wood
	assert(SiteRuntime.request_resize(data, key, larger, Callable(), 1).ok)
	assert(int(data.site.inventory.wood) == before_shrink_wood - int(rebuild_preview.cost.wood))
	pending = feature.pending_build
	task = _task(key, "construct", int(pending.entrance))
	SiteRuntime._feature_work(data, key, float(pending.work), Callable(), Callable(), task, {}, 20, 1)
	assert(float(feature.parts[part].hp) == 60.0 and float(feature.parts[replaced_part].hp) == 100.0)
	assert(int(data.site.inventory.wood) == before_shrink_wood - 4, "Rebuilding restores only the new part after spending fresh materials and completing work")
	var sheep := _build(data, "pasture", Vector2i(40, 10), Vector2i(3, 3))
	var pen: Dictionary = data.site.features[sheep]
	var sheep_inventory := int(data.site.inventory.sheep)
	assert(SiteRuntime.request_resize(data, sheep, _cells(data, "pasture", Vector2i(40, 10), Vector2i(4, 3)), Callable(), 1).ok)
	assert(int(data.site.inventory.sheep) == sheep_inventory and int(pen.residents) == 1)
	assert(SiteRuntime.cancel_feature(data, sheep, Callable(), 1).ok)
	var cargo := {}
	assert(SiteRuntime.unstock_pasture(data, sheep, cargo, data.cell_from_index(int(pen.entrance)), 1).ok)
	assert(int(pen.residents) == 0 and int(cargo.sheep) == 1)
	assert(SiteRuntime.stock_pasture(data, sheep, cargo, data.cell_from_index(int(pen.entrance))).ok)
	assert(int(pen.residents) == 1 and cargo.is_empty())
	var large_pen_key := _build(data, "pasture", Vector2i(40, 40), Vector2i(7, 6))
	var large_pen: Dictionary = data.site.features[large_pen_key]
	var capacity := SiteRuntime.livestock_capacity(data, large_pen)
	assert(capacity == SiteRuntime.grazing_capacity(data, large_pen.cells) and capacity > 36)
	var brought := 1
	for _visit: int in range(5):
		var herd := {"sheep": 20}
		var transfer := SiteRuntime.stock_pasture(data, large_pen_key, herd, data.cell_from_index(int(large_pen.entrance)))
		assert(transfer.ok)
		brought += int(transfer.transferred)
		assert(int(transfer.transferred) + int(herd.get("sheep", 0)) == 20)
	assert(int(large_pen.residents) == capacity and int(large_pen.residents) == brought and brought > 36)
	var overflow_cargo := {"sheep": 1}
	var full_snapshot := JSON.stringify(data.site)
	assert(not SiteRuntime.stock_pasture(data, large_pen_key, overflow_cargo, data.cell_from_index(int(large_pen.entrance))).ok)
	assert(JSON.stringify(data.site) == full_snapshot and int(overflow_cargo.sheep) == 1)
	var undersized := _cells(data, "pasture", Vector2i(40, 40), Vector2i(3, 3))
	assert(SiteRuntime.grazing_capacity(data, undersized) < int(large_pen.residents))
	var rejected_shrink := SiteRuntime.request_resize(data, large_pen_key, undersized, Callable(), 1)
	assert(not rejected_shrink.ok and str(rejected_shrink.code) == "CAPACITY", str(rejected_shrink))
	assert(JSON.stringify(data.site) == full_snapshot and int(overflow_cargo.sheep) == 1, "Rejected pasture shrink must retain all residents, footprint, zones and resources")
	assert(SiteStore._validate_site_values(data, data.site).ok)
	var invalid_stock := data.site.duplicate(true)
	invalid_stock.features[large_pen_key].residents = capacity + 1
	assert(not SiteStore._validate_site_values(data, invalid_stock).ok, "Save accepted more animals than the original grass can carry")
	var legacy_pen := large_pen.duplicate(true)
	legacy_pen.erase("layout_version")
	assert(SiteRuntime.livestock_capacity(data, legacy_pen) == 36)
	pen.batch_paid = true
	var snapshot := JSON.stringify(data.site)
	assert(not SiteRuntime.cancel_feature(data, sheep, Callable(), 1).ok)
	assert(JSON.stringify(data.site) == snapshot)
	pen.batch_paid = false
	var planned := SiteRuntime.request_build(data, "house", _cells(data, "house", Vector2i(8, 8), Vector2i.ONE, {"variant": "small"}), Callable(), {"variant": "small", "owner_faction": 1})
	assert(planned.ok)
	var definition := {"slot": "weapon", "asset": "sword_01", "tint": [1.0, 1.0, 1.0, 1.0]}
	assert(SiteRuntime.create_equipment(data, data.site.depot_items, "contract_sword", definition, 1).ok)
	data.site.capacity = SiteRuntime.inventory_size(data.site.inventory) + 6
	snapshot = JSON.stringify(data.site)
	assert(not SiteRuntime.cancel_feature(data, str(planned.feature), Callable(), 1).ok, "Refund ignored physical depot item")
	assert(JSON.stringify(data.site) == snapshot)
	completed += 1

func _check_expansion_clearing() -> void:
	var data := _fixture()
	var key := _build(data, "farm", Vector2i(10, 10), Vector2i(2, 2))
	var feature: Dictionary = data.site.features[key]
	for source: Array in [["expansion_tree", SiteEnvironment.Kind.TIMBER, Vector2i(12, 10), 4], ["expansion_stone", SiteEnvironment.Kind.STONE, Vector2i(12, 11), 3]]:
		var index := data.index(source[2])
		data.resource_base[source[0]] = {"kind": source[1], "cell": index, "cells": [index], "capacity": source[3], "variant": 0, "water": -1, "blocks": true, "recover": 0}
	SiteEnvironment.rebuild_indexes(data)
	var wood := int(data.site.inventory.wood)
	var stone := int(data.site.inventory.stone)
	assert(SiteRuntime.request_resize(data, key, _cells(data, "farm", Vector2i(10, 10), Vector2i(3, 2)), Callable(), 1).ok)
	assert(feature.pending_build.clearing.size() == 2)
	var cleared_before_completion := false
	for _step: int in range(16):
		var selected := SiteRuntime.choose_task(data, data.cell_from_index(int(data.site.worker.cell)), Callable(), null, null, {}, 1)
		assert(selected.ok, str(selected))
		SiteRuntime.assign_task(data, selected)
		data.site.worker.cell = int(selected.cell)
		data.site.worker.mode = "work"
		SiteRuntime.advance(data, 20.0, true, false, Callable(), Callable(), Callable(), 20, 20, 1.0, 1)
		if bool(SiteEnvironment.resource(data, "expansion_tree").cleared) and bool(SiteEnvironment.resource(data, "expansion_stone").cleared):
			cleared_before_completion = true
		if not feature.has("pending_build"):
			break
	assert(cleared_before_completion and not feature.has("pending_build") and feature.cells.size() == 6, "Pending expansion never cleared its original resource sources")
	assert(int(data.site.inventory.wood) == wood + 4 and int(data.site.inventory.stone) == stone + 3)
	assert(data.site.worker.cargo.is_empty(), "Construction clearing discarded the original harvested cargo")
	# Reintroduce one source as a guard fixture: once this cell is completed
	# ground, the temporary construction exception must no longer apply.
	SiteEnvironment.change(data, "expansion_tree", {"cleared": false, "remaining": 4})
	SiteEnvironment.rebuild_indexes(data)
	var blocked := SiteRuntime.harvest(data, "expansion_tree", Vector2i(13, 10), {}, "clear", true)
	assert(not blocked.ok and str(blocked.code) == "OCCUPIED", "Expansion exception leaked into completed land")
	completed += 1

func _check_original_workers_shared_batch() -> void:
	var data := _fixture()
	var key := _build(data, "farm", Vector2i(10, 40), Vector2i(12, 6))
	_build(data, "well", Vector2i(8, 42))
	_build(data, "well", Vector2i(24, 42))
	assert(SiteRuntime.operate_feature(data, key).ok)
	var fixture := CrewFixture.new()
	fixture.setup(root, data, [Vector2i(7, 40), Vector2i(12, 42), Vector2i(18, 42)])
	var ids: Array[int] = [fixture.army.combat_identity(1), fixture.army.combat_identity(2)]
	assert(fixture.crew.assign(fixture.army, ids, fixture.army.combat_identity(0)).ok)
	var seeds := int(data.site.inventory.seeds)
	var step := fixture.crew.advance(60.0)
	var first: Dictionary = fixture.army.combat_units[1]
	var second: Dictionary = fixture.army.combat_units[2]
	assert(int(first.work_task.work_slot) == 0 and int(second.work_task.work_slot) == 1)
	assert(first.work_task.target == second.work_task.target)
	assert(SiteRuntime.work_claim_key(first.work_task) != SiteRuntime.work_claim_key(second.work_task))
	assert(SiteWorkTeam.valid_task(data, data.site, first.work_task) and SiteWorkTeam.valid_task(data, data.site, second.work_task))
	var feature: Dictionary = data.site.features[key]
	assert(is_equal_approx(float(feature.production), 72.0), str(feature))
	assert(int(data.site.inventory.seeds) == seeds - 1 and bool(feature.batch_paid))
	assert(step.handled_seconds.size() == 2 and float(first.fatigue) > 0.0 and float(second.fatigue) > 0.0)
	assert(int(SiteRuntime.feature_production_info(data, key).served_cells) == 72)
	feature.production = float(SiteRuntime.FEATURES.farm.cycle) - 20.0
	fixture.crew.advance(60.0)
	assert(int(first.cargo.get("grain", 0)) + int(second.cargo.get("grain", 0)) == 8, "Two workers collected the same batch twice")
	assert(int(data.site.inventory.seeds) == seeds - 2 and bool(feature.batch_paid))
	var invalid: Dictionary = second.work_task.duplicate(true)
	invalid.work_cell = data.index(Vector2i(60, 60))
	assert(not SiteWorkTeam.valid_task(data, data.site, invalid))
	assert(not SiteRuntime.cancel_feature(data, key, Callable(), 1).ok)
	fixture.close()
	completed += 1

func _check_large_farm_store_resume() -> void:
	# Regenerate the same real base on load. Only the original saved clearing
	# and terrain deltas prepare this plot; soil/water arrays are never replaced.
	var data := TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(72, 72)})
	SiteEnvironment.initialize(data, "building-large-farm-store")
	for y: int in range(5, 70):
		for x: int in range(5, 70):
			var index := data.index(Vector2i(x, y))
			data.site.terrain_changes[str(index)] = 0
			data.height_levels[index] = 0
	for source: String in data.resource_base:
		SiteEnvironment.change(data, source, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(3, 3))
	data.site.worker.cell = data.index(Vector2i(3, 4))
	data.site["worker_enabled"] = false
	for item: String in SiteEnvironment.ITEM_NAMES:
		data.site.inventory[item] = 1000
	data.site.capacity = 100000
	assert(SiteRuntime.initialize_item_storage(data.site).ok)
	SiteRuntime.rebuild_terrain_edges(data)
	SiteEnvironment.rebuild_indexes(data)
	var built_at := Time.get_ticks_usec()
	var key := _build(data, "farm", Vector2i(10, 10), Vector2i(50, 50))
	var build_ms := float(Time.get_ticks_usec() - built_at) / 1000.0
	_build(data, "well", Vector2i(8, 12))
	_build(data, "well", Vector2i(24, 8))
	var expanding := _build(data, "fiber_farm", Vector2i(64, 20), Vector2i(2, 2))
	assert(SiteRuntime.request_resize(data, expanding, _cells(data, "fiber_farm", Vector2i(64, 20), Vector2i(3, 2)), Callable(), 1).ok)
	var expanding_pasture := _build(data, "pasture", Vector2i(64, 28), Vector2i(3, 3))
	assert(SiteRuntime.request_resize(data, expanding_pasture, _cells(data, "pasture", Vector2i(64, 28), Vector2i(4, 3)), Callable(), 1).ok)
	var paid_expanding := _build(data, "palisade", Vector2i(64, 40))
	assert(SiteRuntime.request_resize(data, paid_expanding, _cells(data, "palisade", Vector2i(64, 40), Vector2i(2, 1)), Callable(), 1).ok)
	var repairing := _build(data, "palisade", Vector2i(64, 50))
	var damaged_part := "c:%d" % data.index(Vector2i(64, 50))
	assert(SiteRuntime.damage_structure_part(data, repairing, damaged_part, 40.0).ok)
	assert(SiteRuntime.request_repair(data, repairing, damaged_part, 1).ok)
	assert(not data.site.features[paid_expanding].pending_build.cost.is_empty() and not data.site.features[repairing].repair.cost.is_empty())
	var shrunk_wall := _build(data, "palisade", Vector2i(64, 60), Vector2i(2, 1))
	var retained_part := "c:%d" % data.index(Vector2i(64, 60))
	assert(SiteRuntime.damage_structure_part(data, shrunk_wall, retained_part, 40.0).ok)
	var shrink_result := SiteRuntime.request_resize(data, shrunk_wall, _cells(data, "palisade", Vector2i(64, 60)), Callable(), 1)
	assert(shrink_result.ok and str(shrink_result.feature) == shrunk_wall, str(shrink_result))
	assert(data.site.features[shrunk_wall].cells.size() == 1 and float(data.site.features[shrunk_wall].parts[retained_part].hp) == 60.0)
	assert(SiteRuntime.operate_feature(data, key).ok)
	var feature: Dictionary = data.site.features[key]
	var slots := SiteRuntime.feature_work_slots(data, feature)
	var positions: Array[Vector2i] = [Vector2i(7, 10), data.cell_from_index(int(slots[0].cell)), data.cell_from_index(int(slots[1].cell))]
	var fixture := CrewFixture.new()
	fixture.setup(root, data, positions)
	var identities: Array[int] = [fixture.army.combat_identity(1), fixture.army.combat_identity(2)]
	assert(fixture.crew.assign(fixture.army, identities, fixture.army.combat_identity(0)).ok)
	# Independent extensions and repair are stored but have no active builder.
	for zone: Dictionary in data.site.zones:
		if str(zone.get("feature", "")) != key:
			zone.active = false
	var seeds := int(data.site.inventory.seeds)
	SiteRuntime.advance(data, 1.0, false, false, Callable(), Callable(), func(seconds: float) -> void: fixture.crew.advance(seconds))
	assert(bool(feature.batch_paid) and float(feature.production) > 0.0 and float(feature.production) <= 108.0)
	assert(int(data.site.inventory.seeds) == seeds - 1)
	assert(int(SiteRuntime.feature_production_info(data, key).served_cells) == 72)
	assert(fixture.army.combat_units[1].work_task.work_slot == 0 and fixture.army.combat_units[2].work_task.work_slot == 1)
	data.site["actors"] = {}
	data.site["army_trial_active"] = true
	data.site["army_next_team"] = fixture.army.team_id + 1
	data.site["armies"] = [fixture.army.capture_combat_state()]
	var saved_at := Time.get_ticks_usec()
	var saved := SiteStore.save(data, LARGE_SAVE)
	assert(saved.ok, str(saved))
	var save_ms := float(Time.get_ticks_usec() - saved_at) / 1000.0
	var valid_save := FileAccess.get_file_as_string(LARGE_SAVE)
	for job: Array in [[paid_expanding, "pending_build"], [repairing, "repair"]]:
		var wrapper: Dictionary = JSON.parse_string(valid_save)
		var payload: Dictionary = JSON.parse_string(wrapper.payload)
		var bad_cost: Dictionary = payload.state.features[job[0]][job[1]].cost
		bad_cost.wood = float(bad_cost.wood) + 0.25
		var body := JSON.stringify(payload, "", true, true)
		var bad_file := FileAccess.open(LARGE_SAVE + ".fraction", FileAccess.WRITE)
		assert(bad_file != null)
		bad_file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
		bad_file.close()
		assert(not SiteStore.load_site(LARGE_SAVE + ".fraction").ok, "JSON fraction silently became paid whole materials")
	assert(FileAccess.get_file_as_string(LARGE_SAVE) == valid_save)
	var loaded_at := Time.get_ticks_usec()
	var loaded := SiteStore.load_site(LARGE_SAVE)
	assert(loaded.ok, str(loaded))
	var load_ms := float(Time.get_ticks_usec() - loaded_at) / 1000.0
	var resumed_data: TerrainData = loaded.data
	assert(resumed_data.fingerprint() == data.fingerprint())
	assert(resumed_data.fertility == data.fertility and resumed_data.groundwater == data.groundwater)
	assert(resumed_data.site.features[key].cells.size() == 2500)
	assert(resumed_data.site.features[expanding].pending_build == data.site.features[expanding].pending_build)
	assert(resumed_data.site.features[paid_expanding].pending_build.cost.wood is int)
	assert(resumed_data.site.features[repairing].repair.cost.wood is int)
	assert(resumed_data.site.features[repairing].repair.work_cell is int)
	var loaded_wall: Dictionary = resumed_data.site.features[shrunk_wall]
	# Compare every saved value at the same JSON boundary. Optional numeric
	# metadata and clearing-array typing need not share in-memory Variant types.
	var saved_wall_values: Dictionary = JSON.parse_string(JSON.stringify(data.site.features[shrunk_wall]))
	var loaded_wall_values: Dictionary = JSON.parse_string(JSON.stringify(loaded_wall))
	assert(loaded_wall_values == saved_wall_values, str({"message": "Actual Store roundtrip changed the shrunk original feature or retained damage", "before": saved_wall_values, "after": loaded_wall_values}))
	assert(loaded_wall.cells.get_typed_builtin() == TYPE_INT and loaded_wall.cells == _cells(resumed_data, "palisade", Vector2i(64, 60)))
	assert(loaded_wall.parts.size() == 1 and float(loaded_wall.parts[retained_part].hp) == 60.0)
	assert(resumed_data.feature_at[resumed_data.index(Vector2i(64, 60))] == int(shrunk_wall) and resumed_data.feature_at[resumed_data.index(Vector2i(65, 60))] == 0)
	assert(resumed_data.navigation_heights()[resumed_data.index(Vector2i(64, 60))] == 2 and resumed_data.navigation_heights()[resumed_data.index(Vector2i(65, 60))] == 0)
	for zone: Dictionary in resumed_data.site.zones:
		if str(zone.get("feature", "")) == shrunk_wall: assert(zone.cells == loaded_wall.cells and not bool(zone.active))
	for expanded_key: String in [expanding, expanding_pasture, paid_expanding]:
		var saved_job: Dictionary = resumed_data.site.features[expanded_key].pending_build
		assert(saved_job.cells.get_typed_builtin() == TYPE_INT and saved_job.added_cells.get_typed_builtin() == TYPE_INT and saved_job.entrance is int)
	assert(resumed_data.site.inventory == data.site.inventory and resumed_data.site.features[key].batch_paid)
	assert(is_equal_approx(float(resumed_data.site.features[key].production), float(feature.production)))
	var large_zones := 0
	for zone: Dictionary in resumed_data.site.zones:
		if str(zone.get("feature", "")) == key:
			assert(zone.cells.size() == 2500)
			large_zones += 1
	assert(large_zones == 2, "Both original 2500-cell construction/operation zones must survive")
	var resumed := CrewFixture.new()
	resumed.setup(root, resumed_data, positions, resumed_data.site.armies[0])
	for identity: int in identities:
		assert(resumed.crew.is_assigned(identity))
		var original_row: Dictionary = fixture.army.combat_units[fixture.army.index_for_identity(identity)]
		var restored_row: Dictionary = resumed.army.combat_units[resumed.army.index_for_identity(identity)]
		assert(SiteWorkTeam.normalize_task(restored_row.work_task) == SiteWorkTeam.normalize_task(original_row.work_task) and restored_row.cargo == original_row.cargo)
	var work_at := Time.get_ticks_usec()
	SiteRuntime.advance(data, 1.0, false, false, Callable(), Callable(), func(seconds: float) -> void: fixture.crew.advance(seconds))
	var work_ms := float(Time.get_ticks_usec() - work_at) / 1000.0
	SiteRuntime.advance(resumed_data, 1.0, false, false, Callable(), Callable(), func(seconds: float) -> void: resumed.crew.advance(seconds))
	assert(is_equal_approx(float(resumed_data.site.features[key].production), float(feature.production)), "Load changed original shared-batch work")
	assert(int(resumed_data.site.inventory.seeds) == seeds - 1 and resumed_data.site.inventory == data.site.inventory, "Resume charged the paid batch twice")
	assert(is_equal_approx(SiteRuntime.now(resumed_data), SiteRuntime.now(data)))
	for identity: int in identities:
		var original_row: Dictionary = fixture.army.combat_units[fixture.army.index_for_identity(identity)]
		var restored_row: Dictionary = resumed.army.combat_units[resumed.army.index_for_identity(identity)]
		assert(restored_row.cargo == original_row.cargo)
		assert(is_equal_approx(PersonFatigue.read(restored_row), PersonFatigue.read(original_row)))
	var pending_feature: Dictionary = resumed_data.site.features[expanding]
	var pending: Dictionary = pending_feature.pending_build
	var construction := _task(expanding, "construct", int(pending.entrance))
	SiteRuntime._feature_work(resumed_data, expanding, float(pending.work), Callable(), Callable(), construction, {}, 20, 1)
	assert(not pending_feature.has("pending_build") and pending_feature.cells.size() == 6, "Original expansion did not resume after JSON normalization")
	assert(pending_feature.cells.get_typed_builtin() == TYPE_INT)
	var pen: Dictionary = resumed_data.site.features[expanding_pasture]
	var pen_job: Dictionary = pen.pending_build
	var pen_task := _task(expanding_pasture, "construct", int(pen_job.entrance))
	SiteRuntime._feature_work(resumed_data, expanding_pasture, float(pen_job.work), Callable(), Callable(), pen_task, {}, 20, 1)
	assert(not pen.has("pending_build") and pen.cells.size() == 12 and pen.cells.get_typed_builtin() == TYPE_INT)
	assert(SiteRuntime.livestock_capacity(resumed_data, pen) > 1 and int(pen.residents) == 1)
	var herd := {}
	var pen_entry := resumed_data.cell_from_index(int(pen.entrance))
	assert(SiteRuntime.unstock_pasture(resumed_data, expanding_pasture, herd, pen_entry, 1).ok)
	assert(int(pen.residents) == 0 and int(herd.sheep) == 1)
	assert(SiteRuntime.stock_pasture(resumed_data, expanding_pasture, herd, pen_entry).ok)
	assert(int(pen.residents) == 1 and herd.is_empty(), "Loaded expanded pasture lost its original livestock transfer")
	var before_refund := int(resumed_data.site.inventory.wood)
	var refund := int(resumed_data.site.features[paid_expanding].pending_build.cost.wood) + int(resumed_data.site.features[repairing].repair.cost.wood)
	assert(SiteRuntime.cancel_feature(resumed_data, paid_expanding, Callable(), 1).ok)
	assert(SiteRuntime.cancel_feature(resumed_data, repairing, Callable(), 1).ok)
	assert(resumed_data.site.inventory.wood is int and int(resumed_data.site.inventory.wood) == before_refund + refund)
	assert(resumed_data.site.features[paid_expanding].cells.size() == 1 and not resumed_data.site.features[paid_expanding].has("pending_build"))
	assert(not resumed_data.site.features[repairing].has("repair") and float(resumed_data.site.features[repairing].parts[damaged_part].hp) == 60.0)
	print("BUILDING_LARGE_FARM_TIMING ", JSON.stringify({"build_ms": build_ms, "save_ms": save_ms, "load_ms": load_ms, "two_worker_game_minute_ms": work_ms, "cells": 2500, "served_cells": 72, "scope": "headless contract, no rendering or battle load"}))
	fixture.close()
	resumed.close()
	completed += 1

func _check_prison_and_validation() -> void:
	var data := _fixture()
	for entry: Array in [[Vector2i(8, 8), Vector2i.ONE, 1, 0], [Vector2i(20, 8), Vector2i(3, 3), 4, 1], [Vector2i(35, 8), Vector2i(6, 6), 10, 2]]:
		var key := _build(data, "prison", entry[0], entry[1], {"quarter": entry[3]})
		var layout := SiteRuntime.prison_layout(data, key)
		assert(layout.ok and layout.slots.size() == int(entry[2]), str(layout))
		for slot: Dictionary in layout.slots:
			assert(data.can_step(slot.contact_cell, slot.cell))
		var feature: Dictionary = data.site.features[key]
		var bad := feature.duplicate(true)
		bad.entrance = feature.cells[0]
		assert(not SiteRuntime.validate_feature_layout(data, bad).ok)
		data.site["captivity"] = {"42": {"prison_id": key}}
		assert(not SiteRuntime.cancel_feature(data, key, Callable(), 1).ok)
		data.site.captivity.clear()
	completed += 1
