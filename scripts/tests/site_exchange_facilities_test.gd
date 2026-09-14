extends SceneTree

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "user://exchange_facilities/roundtrip.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, "exchange-facilities")
	assert(Runtime.exchange_facility_bonus(null, Vector2i.ZERO) == 0.0)
	assert(Runtime.exchange_facility_bonus(data, Vector2i(-1, -1)) == 0.0)
	var keys: Array[String] = []
	for kind: String in ["palisade", "fighting_position"]:
		var cells := _find_plot(data, kind)
		assert(cells.size() == 2, "A generated, flat, clear two-cell plot must exist")
		var original_inventory: Dictionary = data.site.inventory.duplicate()
		var refused := Runtime.request_build(data, kind, cells, func(_cell: Vector2i) -> bool: return true)
		assert(not refused.ok and refused.code == "OCCUPIED" and data.site.inventory == original_inventory)
		var preview := Runtime.preview_build(data, kind, cells)
		assert(preview.ok and preview.clearing.is_empty())
		assert(preview.cost == ({"wood": 8} if kind == "palisade" else {"wood": 6, "stone": 4}))
		var requested := Runtime.request_build(data, kind, cells)
		assert(requested.ok, str(requested))
		var key := str(requested.feature)
		keys.append(key)
		var feature: Dictionary = data.site.features[key]
		assert(feature.stage == "planned" and feature.progress == 0.0)
		assert(feature.work == (12.0 if kind == "palisade" else 16.0))
		assert(Runtime.water_demand(feature) == 0.0)
		for item: String in preview.cost:
			assert(int(data.site.inventory[item]) == int(original_inventory[item]) - int(preview.cost[item]), "Materials paid once at placement")
		for cell_index: int in cells:
			var cell := data.cell_from_index(cell_index)
			assert(data.is_walkable(cell) and Runtime.exchange_facility_bonus(data, cell) == 0.0, "An unfinished feature gives no defense or free wall")
		Runtime.advance(data, 2.0, false)
		assert(feature.progress == 0.0, "Passing time without work cannot construct defenses")
		Runtime.assign_task(data, {"ok": true, "target": "feature:" + key, "action": "construct", "cell": feature.entrance, "message": ""})
		data.site.worker.cell = feature.entrance
		data.site.worker.mode = "work"
		Runtime.advance(data, 1.0, true, false, func(_cell: Vector2i) -> bool: return true)
		assert(feature.progress == 0.0, "Construction still respects live occupancy/reservations")
		Runtime.advance(data, float(feature.work) - 0.5, true)
		assert(feature.stage == "building" and Runtime.exchange_facility_bonus(data, data.cell_from_index(cells[0])) == 0.0)
		Runtime.advance(data, 0.5, true)
		assert(feature.stage == "complete" and feature.progress == feature.work)
		for cell_index: int in cells:
			var cell := data.cell_from_index(cell_index)
			assert(data.is_walkable(cell) == (kind == "fighting_position"))
			assert(Runtime.exchange_facility_bonus(data, cell) == (10.0 if kind == "fighting_position" else 0.0))
		var entrance := data.cell_from_index(int(feature.entrance))
		var edge := _entrance_edge(data, entrance, cells)
		assert(edge != Vector2i(-1, -1))
		assert(data.can_step(entrance, edge) == (kind == "fighting_position"))
		assert(data.can_attack_across(entrance, edge) == (kind == "fighting_position"))
		assert(not Runtime.operate_feature(data, key).ok, "Passive defenses need no production worker or water cycle")
	# Save uses unchanged generated terrain, the original sparse features, and the
	# existing kind/solid validation. No new persistence owner or custom fields.
	var saved := Store.save(data, SAVE)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(SAVE)
	assert(loaded.ok, str(loaded))
	var restored: TerrainData = loaded.data
	for key: String in keys:
		var original: Dictionary = data.site.features[key]
		var feature: Dictionary = restored.site.features[key]
		assert(feature.kind == original.kind and feature.cells == original.cells and feature.progress == original.progress)
		for cell_index: int in feature.cells:
			var cell := restored.cell_from_index(cell_index)
			assert(Runtime.exchange_facility_bonus(restored, cell) == Runtime.exchange_facility_bonus(data, cell))
			assert(restored.is_walkable(cell) == data.is_walkable(cell))
	var corrupted: Dictionary = restored.site.duplicate(true)
	corrupted.features[keys[0]].solid = false
	assert(not Store._validate_state(restored, corrupted).ok, "A saved palisade cannot bypass the canonical solid definition")
	corrupted = restored.site.duplicate(true)
	corrupted.features[keys[1]].kind = "unapproved_fort"
	assert(not Store._validate_state(restored, corrupted).ok, "Only the existing FEATURES kinds are admitted")
	var rows := SiteResourceView.new()
	root.add_child(rows)
	rows.display(restored)
	for cell_index: int in restored.site.features[keys[0]].cells:
		assert(rows.features_by_row[restored.cell_from_index(cell_index).y].has(keys[0]), "Palisades are batched at each actual ground row")
	rows.queue_free()
	await process_frame
	print("SITE EXCHANGE FACILITIES PASS: per-cell paid construction, no instant defense, occupancy guards, completed position bonus, palisade movement/attack blocking, sparse save/load and kind validation")
	quit(0)

func _find_plot(data: TerrainData, kind: String) -> Array[int]:
	for i in range(data.surface_types.size()):
		var cell := data.cell_from_index(i)
		var next := cell + Vector2i.DOWN
		if not data.contains(next):
			continue
		var cells: Array[int] = [i, data.index(next)]
		if cells.has(int(data.site.worker.cell)) or cells.has(int(data.site.get("player_cell", data.site.depot_cell))):
			continue
		var preview := Runtime.preview_build(data, kind, cells)
		if preview.ok and preview.clearing.is_empty():
			return cells
	return []

func _entrance_edge(data: TerrainData, entrance: Vector2i, cells: Array[int]) -> Vector2i:
	for cell_index: int in cells:
		var cell := data.cell_from_index(cell_index)
		if absi(cell.x - entrance.x) + absi(cell.y - entrance.y) == 1:
			return cell
	return Vector2i(-1, -1)
