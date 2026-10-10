extends "res://scripts/tests/site_building_ui_test.gd"
## Fixture-only source/geometry helper. No knowledge, permission, output or clock.
## Actual source is original PLAINS/12345 + original Env; never rewrite arrays.

func _cold_natural_template(specs: Array, site_id: String, extra: Array[Vector2i] = [], stride: int = 1, paths: Array = []) -> Dictionary:
	var data = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, site_id)
	# Bound/loaded/visited Sites carry item storage; Core building payment reads its depot.
	var fixture_item_storage = Runtime.initialize_item_storage(data.site)
	assert(fixture_item_storage.ok, "Fixture natural world carries original item storage")
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 10000
	data.site.capacity = 1000000
	# Only translate fixture infrastructure on the unchanged source. Every
	# candidate uses the original geometry/material/soil preview before adoption.
	for radius: int in range(101):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius or posmod(x, stride) != 0 or posmod(y, stride) != 0: continue
				var offset = Vector2i(x, y)
				var valid = true
				for original: Vector2i in extra:
					var cell = original + offset
					if not data.contains(cell) or not data.is_walkable(cell): valid = false; break
				if not valid: continue
				for path: Array in paths:
					var cells: Array[int] = []
					var level = -1
					for original: Vector2i in path:
						var cell = original + offset
						if not data.contains(cell): valid = false; break
						var index = data.index(cell)
						if level < 0: level = int(data.height_levels[index])
						if data.ramp_edges[index] != 0 or int(data.height_levels[index]) != level or data.foundation[index] < 35: valid = false; break
						cells.append(index)
					if not valid or not Runtime._irrigation_path(data, cells): valid = false; break
				if not valid: continue
				var plans: Array[Dictionary] = []
				var used = {}
				for spec: Dictionary in specs:
					var options = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
					options.merge(spec.get("options", {}), true)
					var geometry = Runtime.building_cells(data, str(spec.kind), Vector2i(spec.anchor) + offset, Vector2i(spec.extent), options)
					if not geometry.ok: valid = false; break
					for cell: int in geometry.cells:
						if used.has(cell): valid = false; break
						used[cell] = true
					if not valid: break
					var preview = Runtime.preview_build(data, str(spec.kind), geometry.cells, Callable(), options)
					if not preview.ok: valid = false; break
					plans.append({"kind": str(spec.kind), "anchor": Vector2i(spec.anchor) + offset, "extent": Vector2i(spec.extent), "options": options, "geometry": geometry, "preview": preview})
				if valid:
					return {"data": data, "offset": offset, "plans": plans}
	assert(false, "Original natural source must admit the finite fixture template without modifying terrain/soil")
	return {}

func _cold_natural_feature(data: TerrainData, kind: String, anchor: Vector2i, extent: Vector2i = Vector2i.ONE, options: Dictionary = {}) -> String:
	var settings = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	settings.merge(options, true)
	var geometry = Runtime.building_cells(data, kind, anchor, extent, settings)
	assert(geometry.ok, str(geometry))
	var preview = Runtime.preview_build(data, kind, geometry.cells, Callable(), settings)
	assert(preview.ok, str(preview))
	for key: String in preview.get("clearing", []): Env.change(data, key, {"cleared": true, "remaining": 0})
	return _formal_feature(data, kind, anchor, extent, settings)

func _cold_natural_conditions(data: TerrainData) -> PackedByteArray:
	return var_to_bytes([data.fertility, data.moisture, data.drainage, data.foundation, data.groundwater])

func _cold_natural_lab(data: TerrainData) -> TerrainLab:
	var lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(data)
	lab.character.faction_id = 1
	lab.npc.faction_id = 1
	var camp = data.cell_from_index(int(data.site.depot_cell))
	assert(lab.character.place(camp, true), "Actual Actor reaches the original generated camp")
	var npc_cell = Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell = camp + direction
		if data.contains(cell) and data.is_walkable(cell) and data.can_step(camp, cell):
			npc_cell = cell
			break
	assert(npc_cell.x >= 0 and lab.npc.place(npc_cell, true), "The second original Actor has a distinct legal camp contact")
	lab.site_controller.release_worker()
	return lab
