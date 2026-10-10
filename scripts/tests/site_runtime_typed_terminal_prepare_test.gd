extends SceneTree
## Original Runtime transaction component. No person/Native/clock/admission claim.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")

var notifications := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(1))
	_drop_and_collect()
	_open_only_and_sealed()
	_tent_roundtrip()
	print("RUNTIME_TYPED_TERMINAL_PREPARE_COMPONENT_PASS: actual original factory/ground/cargo/tent transactions; pure candidates, current CAS/geometry, forged projection refusal, once publication/callback; no person admission, main clock, combat, Native or cold claim")
	quit(0)

func _data(tag: String) -> TerrainData:
	var data := TerrainGenerator.generate(0, 84241, {"size": Vector2i(48, 48), "max_height": 0, "micro_strength": 0.0})
	Env.initialize(data, tag)
	assert(Runtime.initialize_item_storage(data.site).ok)
	return data

func _goods(data: TerrainData, holders: Array, cargos: Array) -> PackedByteArray:
	return var_to_bytes([data.site, holders, cargos, data.ground_loot_at, data.ground_loot_dirty_rows])

func _item(data: TerrainData, holder: Dictionary, identity: int) -> String:
	var result := Runtime.create_equipment(data, holder, "terminal-component-sword", {"slot": "weapon", "asset": "longsword_01", "tint": [1.0, 1.0, 1.0, 1.0]}, identity, "weapon")
	assert(result.ok, str(result))
	return str(result.item_id)

func _drop_and_collect() -> void:
	var data := _data("typed-terminal-ground")
	var source := Runtime.new_item_state("person:21")
	var cargo := {"wood": 3, "grain": 2, "arrow": 0}
	var pool := {"open_rations": 0.25}
	var item := _item(data, source, 21)
	var version := int(source.version)
	var before := _goods(data, [source, pool], [cargo])
	var prepared := Runtime.prepare_leave_ground_loot(data, source, cargo, 21, data.spawn_cell, "remains", cargo, [item], version, pool, 0.25)
	assert(prepared.ok and Runtime.validate_prepared_leave_ground_loot(prepared).ok, str(prepared))
	assert(_goods(data, [source, pool], [cargo]) == before)
	assert(prepared.container.cargo.is_empty() and prepared.container.item_ids.is_empty() and prepared.container.version == 0)
	assert(prepared.identity == str(data.site.next_loot) and not data.site.ground_loot.has(prepared.identity))
	var forged: Dictionary = prepared.duplicate()
	forged.container = prepared.container.duplicate(true)
	forged.container["cargo"] = {"wood": 99}
	assert(not Runtime.validate_prepared_leave_ground_loot(forged).ok and _goods(data, [source, pool], [cargo]) == before)
	source.version += 1
	assert(not Runtime.validate_prepared_leave_ground_loot(prepared).ok)
	source.version = version
	assert(Runtime.validate_prepared_leave_ground_loot(prepared).ok)
	var result := Runtime.publish_prepared_leave_ground_loot(prepared)
	assert(result.ok and result.container_id == prepared.identity and not Runtime.validate_prepared_leave_ground_loot(prepared).ok)
	var ground: Dictionary = data.site.ground_loot[result.container_id]
	assert(is_same(ground, prepared.container) and ground.cargo == {"wood": 3, "grain": 2})
	assert(ground.open_rations == 0.25 and pool.open_rations == 0.0)
	assert(ground.equipped.weapon == item and data.site.item_records[item].holder == ground.holder)
	assert(data.site.item_records[item].original_owner == 21 and cargo.is_empty() and source.item_ids.is_empty())
	assert(source.version == version + 1 and ground.version == 1 and data.site.next_loot == int(result.container_id) + 1)
	assert(not Runtime.prepare_clear_empty_ground_loot(data, str(result.container_id)).ok)
	var destination := Runtime.new_item_state("person:22")
	var destination_cargo := {}
	before = _goods(data, [ground, destination], [ground.cargo, destination_cargo])
	var take := Runtime.prepare_loot_transfer(data, ground, ground.cargo, destination, destination_cargo, ground.cargo, [item], int(ground.version), int(destination.version), 0.25)
	assert(take.ok and Runtime.validate_prepared_loot_transfer(take).ok and not take.cleanup.is_empty())
	assert(_goods(data, [ground, destination], [ground.cargo, destination_cargo]) == before)
	assert(not Runtime.validate_prepared_clear_empty_ground_loot(take.cleanup).ok, "Projected empty container is validated by its SAME actual transfer, never standalone while still full")
	forged = take.duplicate()
	forged.cleanup = take.cleanup.duplicate()
	forged.cleanup.identity = "missing"
	assert(not Runtime.validate_prepared_loot_transfer(forged).ok and _goods(data, [ground, destination], [ground.cargo, destination_cargo]) == before)
	var original_cargo: Dictionary = ground.cargo
	ground.cargo = ground.cargo.duplicate()
	assert(not Runtime.validate_prepared_loot_transfer(take).ok, "Original ground cargo reference must survive")
	ground.cargo = original_cargo
	data.ground_loot_removed = func(identity: String) -> void:
		assert(identity == result.container_id and not data.site.ground_loot.has(identity))
		notifications += 1
	assert(Runtime.validate_prepared_loot_transfer(take).ok)
	assert(Runtime.publish_prepared_loot_transfer(take).ok)
	assert(not Runtime.validate_prepared_loot_transfer(take).ok and notifications == 0)
	assert(ground.open_rations == 0.0 and ground.cargo.is_empty() and ground.item_ids.is_empty())
	assert(destination_cargo == {"wood": 3, "grain": 2} and destination.item_ids == [item] and destination.equipped.is_empty())
	assert(ground.version == 2 and destination.version == 1 and data.site.item_records[item].holder == "person:22")
	assert(Runtime.validate_prepared_clear_empty_ground_loot(take.cleanup).ok)
	assert(Runtime.publish_prepared_clear_empty_ground_loot(take.cleanup).ok and notifications == 0)
	assert(not Runtime.validate_prepared_clear_empty_ground_loot(take.cleanup).ok)
	Runtime.notify_cleared_ground_loot(take.cleanup)
	assert(notifications == 1 and not data.site.ground_loot.has(result.container_id))
	assert(not data.ground_loot_at.has(data.index(data.spawn_cell)))

func _open_only_and_sealed() -> void:
	var data := _data("typed-terminal-open")
	var source := Runtime.new_item_state("person:31")
	var cargo := {}
	var pool := {"open_rations": 0.5}
	var before := _goods(data, [source, pool], [cargo])
	var preview := Runtime.leave_ground_loot(data, source, cargo, 31, data.spawn_cell, "cargo", {}, [], 0, pool, 0.5, true)
	assert(preview.ok and _goods(data, [source, pool], [cargo]) == before)
	var prepared := Runtime.prepare_leave_ground_loot(data, source, cargo, 31, data.spawn_cell, "cargo", {}, [], 0, pool, 0.5)
	assert(prepared.ok and prepared.transfer.is_empty())
	pool.open_rations = 0.25
	assert(not Runtime.validate_prepared_leave_ground_loot(prepared).ok and data.site.ground_loot.is_empty())
	pool.open_rations = 0.5
	assert(Runtime.validate_prepared_leave_ground_loot(prepared).ok)
	assert(Runtime.publish_prepared_leave_ground_loot(prepared).ok and source.version == 1 and pool.open_rations == 0.0)
	var ground: Dictionary = data.site.ground_loot[prepared.identity]
	var destination := Runtime.new_item_state("person:32")
	var destination_cargo := {"wood": Runtime.CARRY_CAPACITY}
	before = _goods(data, [ground, destination], [ground.cargo, destination_cargo])
	assert(not Runtime.prepare_loot_transfer(data, ground, ground.cargo, destination, destination_cargo, {}, [], 1, 0, 0.5).ok)
	assert(_goods(data, [ground, destination], [ground.cargo, destination_cargo]) == before)
	destination_cargo.clear()
	var take := Runtime.prepare_loot_transfer(data, ground, ground.cargo, destination, destination_cargo, {}, [], 1, 0, 0.5)
	assert(take.ok and take.transfer.is_empty() and not take.cleanup.is_empty())
	assert(Runtime.publish_prepared_loot_transfer(take).ok and ground.version == 2 and destination.version == 1 and ground.open_rations == 0.0)
	assert(destination_cargo.is_empty(), "Fractional opened food is not manufactured as grain; PA owns destination original food pool")
	assert(Runtime.publish_prepared_clear_empty_ground_loot(take.cleanup).ok)
	Runtime.notify_cleared_ground_loot(take.cleanup)
	var prisoner_holder := Runtime.new_item_state("person:33")
	var prisoner_cargo := {"wood": 1}
	var item := _item(data, prisoner_holder, 33)
	var sealed := Runtime.prepare_leave_ground_loot(data, prisoner_holder, prisoner_cargo, 33, data.spawn_cell, "sealed", {"wood": 1}, [item], int(prisoner_holder.version))
	assert(sealed.ok and not sealed.transfer.preserve_slots)
	assert(Runtime.publish_prepared_leave_ground_loot(sealed).ok)
	assert(data.site.ground_loot[sealed.identity].equipped.is_empty() and data.site.item_records[item].original_owner == 33)
	assert(prisoner_holder.item_ids.is_empty() and prisoner_cargo.is_empty(), "Only real goods move; Runtime creates no captive/person/research state")

func _tent_place(data: TerrainData) -> Dictionary:
	for key: String in data.resource_base:
		Env.change(data, key, {"remaining": 0, "cleared": true})
	Env.rebuild_indexes(data)
	for y: int in range(2, data.size.y - 5):
		for x: int in range(2, data.size.x - 5):
			var layout := Runtime.building_cells(data, "tent", Vector2i(x, y), Vector2i(3, 3))
			if not layout.ok: continue
			var cells: Array[int] = []
			cells.assign(layout.cells)
			for index: int in cells:
				for direction: Vector2i in TerrainData.DIRECTIONS:
					var contact := data.cell_from_index(index) + direction
					if not data.contains(contact) or cells.has(data.index(contact)): continue
					var preview := Runtime.preview_deploy_tent(data, cells, contact, 0)
					if preview.ok: return {"cells": cells, "contact": contact}
	assert(false, "Original natural source must expose one legal tent/contact geometry")
	return {}

func _tent_roundtrip() -> void:
	var data := _data("typed-terminal-tent")
	var place := _tent_place(data)
	var holder := Runtime.new_item_state("person:41")
	var cargo := {"camp_tent": 1}
	var before := _goods(data, [holder], [cargo])
	var prepared := Runtime.prepare_deploy_tent(data, place.cells, cargo, holder, 0, place.contact, 0)
	assert(prepared.ok and Runtime.validate_prepared_deploy_tent(prepared).ok, str(prepared))
	assert(_goods(data, [holder], [cargo]) == before and data.site.features.is_empty())
	var forged: Dictionary = prepared.duplicate()
	forged.feature = prepared.feature.duplicate(true)
	forged.feature.cost = {}
	assert(not Runtime.validate_prepared_deploy_tent(forged).ok and _goods(data, [holder], [cargo]) == before)
	var footprint: int = place.cells[0]
	var occupied := func(cell: Vector2i) -> bool: return data.index(cell) == footprint
	forged = prepared.duplicate()
	forged.occupied = occupied
	assert(not Runtime.validate_prepared_deploy_tent(forged).ok and _goods(data, [holder], [cargo]) == before)
	holder.version = 1
	assert(not Runtime.validate_prepared_deploy_tent(prepared).ok and data.site.features.is_empty())
	holder.version = 0
	assert(Runtime.validate_prepared_deploy_tent(prepared).ok)
	var result := Runtime.publish_prepared_deploy_tent(prepared)
	assert(result.ok and result.feature == prepared.feature_id and is_same(data.site.features[result.feature], prepared.feature))
	assert(cargo.is_empty() and holder.version == 1 and data.site.next_feature == int(result.feature) + 1)
	assert(not Runtime.validate_prepared_deploy_tent(prepared).ok)
	before = _goods(data, [holder], [cargo])
	var pack := Runtime.prepare_pack_tent(data, result.feature, cargo, holder, 1, place.contact, 0)
	assert(pack.ok and Runtime.validate_prepared_pack_tent(pack).ok and _goods(data, [holder], [cargo]) == before)
	forged = pack.duplicate()
	forged.occupied = occupied
	assert(not Runtime.validate_prepared_pack_tent(forged).ok and _goods(data, [holder], [cargo]) == before)
	cargo.wood = Runtime.CARRY_CAPACITY
	assert(not Runtime.validate_prepared_pack_tent(pack).ok and data.site.features.has(result.feature))
	cargo.erase("wood")
	assert(Runtime.validate_prepared_pack_tent(pack).ok)
	assert(Runtime.publish_prepared_pack_tent(pack).ok and cargo == {"camp_tent": 1} and holder.version == 2 and data.site.features.is_empty())
	assert(not Runtime.validate_prepared_pack_tent(pack).ok)
	var sync_deploy := Runtime.deploy_tent(data, place.cells, cargo, holder, 2, place.contact, 0)
	assert(sync_deploy.ok and Runtime.pack_tent(data, sync_deploy.feature, cargo, holder, 3, place.contact, 0).ok)
	assert(cargo == {"camp_tent": 1} and holder.version == 4 and data.site.features.is_empty())
