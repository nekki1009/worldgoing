extends "res://scripts/tests/site_fire_building_parts_test.gd"
## Named original stock mutation and original component row projection.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_INVENTORY_COMPONENTS_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _loss_request(f: Fixture, key: String, resources: Dictionary, items: Array) -> Dictionary:
	var state: Dictionary = f.data.site.fire
	var unit_key := SiteRuntime._fire_unit_key("feature", key, "roof")
	var unit: Dictionary = state.units[unit_key]
	var holder: Dictionary = f.data.site.stockpiles[key].holder
	return {"version": 1, "event_id": "contents:%d:%s@%d" % [int(state.step_index), unit_key, int(unit.generation)],
		"site_id": str(f.data.site.id), "feature_id": key, "source_unit_key": unit_key, "source_generation": int(unit.generation),
		"step": int(state.step_index), "holder_id": str(holder.holder), "expected_version": int(holder.version), "resources": resources, "item_ids": items}

func _inventory_once() -> bool:
	var f := _fixture()
	var key := _paid_feature(f, "warehouse", Vector2i(20, 20), Vector2i.ONE, {"material": "stone"})
	if key.is_empty(): return false
	var storage := SiteStockpiles.ensure_storage(f.data, key, 1)
	if not _check(storage.ok, "Original warehouse has one stock owner"): return false
	var stock: Dictionary = storage.stock
	stock.cargo.merge({"wood": 5, "stone": 3}, true)
	var holder: Dictionary = stock.holder
	var cargo: Dictionary = stock.cargo
	f.lab.siege_apply_damage_batch({key + "|roof": {"feature": key, "part": "roof", "damage": 50.0}}, {})
	_hot_feature(f, key, "roof")
	if not _check(int(cargo.wood) == 5, "First roof collapse does not retrospectively charge contents"): return false
	if not _check(SiteRuntime.fire_advance(f.data, 1.0, 0, f.lab.siege_queue_damage).ok, "Original finite 5Hz owner advances exposed cargo"): return false
	var state: Dictionary = f.data.site.fire
	if not _check(int(cargo.wood) == 4 and int(cargo.stone) == 3 and state.inventory_receipts.size() == 1 and is_same(stock.holder, holder) and is_same(stock.cargo, cargo), "One full-intensity action second debits one real wood and preserves original objects"): return false
	var event: String = state.inventory_receipts.keys()[0]
	var receipt: Dictionary = state.inventory_receipts[event]
	var replay := _loss_request(f, key, {"wood": 1}, [])
	replay.event_id = event
	replay.step = int(receipt.step)
	replay.source_generation = int(receipt.source_generation)
	var unchanged := var_to_bytes(f.data.site)
	var repeated := SiteRuntime.apply_inventory_loss(f.data, replay)
	if not _check(repeated.ok and repeated.duplicate and var_to_bytes(f.data.site) == unchanged, "Duplicate original event returns receipt without another debit"): return false
	# Explicit fixture stock genesis removes only stacks, so the next real loss
	# demonstrates original item IDs and records rather than a copied quantity.
	cargo.erase("wood")
	var definition := {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}
	var created := SiteRuntime.create_equipment(f.data, holder, "weapon:bow_01", definition, 1)
	if not _check(created.ok, "Original item allocation creates combustible equipment", created): return false
	var definitions := var_to_bytes(f.data.site.item_definitions)
	var next_item := int(f.data.site.next_item)
	if not _check(SiteRuntime.fire_advance(f.data, 2.0, 0, f.lab.siege_queue_damage).ok, "Original owner advances second cargo interval"): return false
	if not _check(not f.data.site.item_records.has(str(created.item_id)) and not holder.item_ids.has(str(created.item_id)) and var_to_bytes(f.data.site.item_definitions) == definitions and int(f.data.site.next_item) == next_item and int(cargo.stone) == 3, "Real burned item disappears once; definitions, next ID and stone remain"): return false
	_close(f)
	return true

func _moved_item() -> bool:
	var f := _fixture()
	var key := _paid_feature(f, "warehouse", Vector2i(20, 20), Vector2i.ONE, {"material": "stone"})
	if key.is_empty(): return false
	var storage := SiteStockpiles.ensure_storage(f.data, key, 1)
	if not _check(storage.ok, "Original stock ready for movement race"): return false
	f.lab.siege_apply_damage_batch({key + "|roof": {"feature": key, "part": "roof", "damage": 50.0}}, {})
	var stock: Dictionary = storage.stock
	var made := SiteRuntime.create_equipment(f.data, stock.holder, "weapon:bow_01", {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 1)
	if not _check(made.ok, "Original equipment genesis for movement race"): return false
	var request := _loss_request(f, key, {}, [str(made.item_id)])
	var depot: Dictionary = f.data.site.depot_items
	var moved := SiteRuntime.transfer_items(f.data, stock.holder, stock.cargo, depot, f.data.site.inventory, {}, [str(made.item_id)], int(stock.holder.version), int(depot.version), 100000)
	if not _check(moved.ok, "Original inventory transfer moves the selected item", moved): return false
	var rejected := SiteRuntime.apply_inventory_loss(f.data, request)
	if not _check(not rejected.ok and rejected.code == "STALE_SOURCE", "Original holder version prevents stale loss"): return false
	request.expected_version = int(stock.holder.version)
	var applied := SiteRuntime.apply_inventory_loss(f.data, request)
	if not _check(applied.ok and applied.receipt.item_ids.is_empty() and f.data.site.item_records.has(str(made.item_id)) and depot.item_ids.has(str(made.item_id)), "Revalidated loss never follows an item to its new owner"): return false
	_close(f)
	return true

func _component_rows() -> bool:
	var f := _fixture()
	var key := _paid_feature(f, "warehouse", Vector2i(20, 20), Vector2i.ONE, {"material": "stone"})
	if key.is_empty(): return false
	var feature: Dictionary = f.data.site.features[key]
	var view := SiteResourceView.new()
	view.data = f.data
	var before := view.building_part_draws(feature)
	if not _check(before.size() == feature.cells.size() * 2 and before.all(func(part: Dictionary) -> bool: return str(part.primitive) == "fire_component" and str(part.state) == "intact"), "Original rows project intact stone body and timber roof separately"): view.free(); return false
	f.lab.siege_apply_damage_batch({key + "|roof": {"feature": key, "part": "roof", "damage": 50.0}}, {})
	var after := view.building_part_draws(feature)
	for part: Dictionary in after:
		if not _check((part.part_id == "body" and part.state == "intact" and part.row >= 0) or (part.part_id == "roof" and part.state == "destroyed" and part.row == -1), "Original row ordering removes roof silhouette while retaining standing body", part.part_id): view.free(); return false
	view.free()
	_close(f)
	return true

func _run() -> void:
	if not _inventory_once(): _finish(false, "original cargo and equipment once-only loss"); return
	if not _moved_item(): _finish(false, "original holder race"); return
	if not _component_rows(): _finish(false, "original component row projection"); return
	_finish(not failed, "P4 inventory and engineering component records only; no visual capture or performance acceptance")
