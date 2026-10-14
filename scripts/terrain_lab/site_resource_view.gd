class_name SiteResourceView
extends Node2D

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const PROPS = preload("res://assets/map/site/settlement/settlement_props_chroma_v1.png")
const PROP_SHADER = preload("res://assets/map/site/settlement/settlement_chroma.gdshader")
const PROP_REGIONS := {
	"house": Rect2(282, 18, 412, 590),
	"well": Rect2(915, 178, 312, 360),
	"farm": Rect2(264, 658, 460, 307),
	"chest": Rect2(991, 724, 203, 181),
}
const RESOURCE_ART_MANIFEST := "res://assets/map/site/natural_resources/manifest.json"
const BUILDING_ART_ROOT := "res://assets/map/site/settlement/building_v2/"
const TREE_ART := ["conifer", "broadleaf", "olive"]
static var _resource_art: Dictionary = _load_resource_art()
const CELL := 64.0
const VIEW_NAMES := ["自然地圖", "天然資源", "農耕適性", "放牧條件", "淡水服務", "建設適性"]
static var _oval_unit := _make_oval_unit()
static var _oval_triangles := Geometry2D.triangulate_polygon(_oval_unit)
var data: TerrainData
var view_mode := 0
var resource_filter := -1
var selection := Rect2i()
var selection_valid := true
var preview_entrance := Vector2i(-1, -1)
var combat_preview_platform_slots: Array[Vector2i] = []
var combat_preview_queue_slots: Array[Vector2i] = []
var combat_preview_anchor := Vector2i(-1, -1)
var combat_preview_facing := Vector2i.ZERO
var combat_preview_slot_facing: Dictionary = {}
var selected_resource := ""
var resources_by_row: Dictionary = {}
var features_by_row: Dictionary = {}
var loot_cells_by_row: Dictionary = {}
var rows: Array[Node2D] = []
var heat := PackedColorArray()
var animation_time := 0.0
var _animation_elapsed := 0.0
var _seen_revision := -1
var retain_static_rows := true # Same-owner reference switch; no resource state is cached.
var building_preview: Dictionary = {} # Derived presentation, never added to Site features.
var building_draws_by_row: Dictionary = {}
var _building_preview_draws: Array[Dictionary] = []
var _building_art_manifest: Dictionary = {}
var _building_art: Dictionary = {}
var _building_textures: Dictionary = {}
var _building_ground: Node2D
var _building_preview_signature := 0

class BuildingRun extends Node2D:
	var view: Node2D
	var row := -1
	var foreground := false
	func _draw() -> void:
		view._draw_buildings(self, row, foreground)

class TriangleBatcher extends RefCounted:
	var canvas_item: RID
	var indices := PackedInt32Array()
	var points := PackedVector2Array()
	var colors := PackedColorArray()

	func _init(p_canvas_item: RID) -> void:
		canvas_item = p_canvas_item

	func add_polygon(poly_points: PackedVector2Array, color: Color) -> void:
		if poly_points.size() < 3: return
		var base := points.size()
		for pt in poly_points:
			points.append(pt)
			colors.append(color)
		for i in range(1, poly_points.size() - 1):
			indices.append(base)
			indices.append(base + i)
			indices.append(base + i + 1)

	func add_quad(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, color: Color) -> void:
		var base := points.size()
		points.append(p1)
		points.append(p2)
		points.append(p3)
		points.append(p4)
		for _k in range(4): colors.append(color)
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base)
		indices.append(base + 2)
		indices.append(base + 3)

	func add_line(from: Vector2, to: Vector2, color: Color, width: float = 1.0) -> void:
		if (to - from).is_zero_approx(): return
		var dir := (to - from).normalized()
		var normal := Vector2(-dir.y, dir.x) * (maxf(0.5, width) * 0.5)
		add_quad(from - normal, from + normal, to + normal, to - normal, color)

	func add_polyline(poly_points: PackedVector2Array, color: Color, width: float = 1.0) -> void:
		for k in range(poly_points.size() - 1):
			add_line(poly_points[k], poly_points[k + 1], color, width)

	func add_rect(rect: Rect2, color: Color) -> void:
		add_quad(rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), color)

	func add_rect_outline(rect: Rect2, color: Color, width: float = 1.0) -> void:
		var p1 := rect.position
		var p2 := Vector2(rect.end.x, rect.position.y)
		var p3 := rect.end
		var p4 := Vector2(rect.position.x, rect.end.y)
		add_line(p1, p2, color, width)
		add_line(p2, p3, color, width)
		add_line(p3, p4, color, width)
		add_line(p4, p1, color, width)

	func add_oval(p: Vector2, radius: Vector2, color: Color, unit: PackedVector2Array, tri_indices: PackedInt32Array) -> void:
		var base := points.size()
		var xform := Transform2D(Vector2(radius.x, 0), Vector2(0, radius.y), p)
		var oval_points: PackedVector2Array = xform * unit
		for pt in oval_points:
			points.append(pt)
			colors.append(color)
		for idx in tri_indices:
			indices.append(base + idx)

	func flush() -> void:
		if indices.is_empty(): return
		RenderingServer.canvas_item_add_triangle_array(canvas_item, indices, points, colors)
		indices.clear()
		points.clear()
		colors.clear()

class ResourceRun extends Node2D:
	var view: Node2D
	var row := 0
	var keys: Array[String] = []
	var decorations := false
	func _draw() -> void:
		if decorations:
			view._draw_row_features(self, row)
		else:
			view._draw_row_resources(self, row, keys)

class ResourceRow extends Node2D:
	var view: Node2D
	var row := 0
	var animated_runs: Array[Node2D] = []
	func _draw() -> void:
		if view.retain_static_rows:
			view._draw_row_loot(self, row)
		else:
			view.draw_row(self, row)
	var _rebuild_job: Dictionary = {}
	func rebuild() -> void:
		begin_rebuild()
		while not step_rebuild(): pass
	func begin_rebuild() -> void:
		for child in get_children():
			remove_child(child)
			child.queue_free()
		animated_runs.clear()
		queue_redraw()
		var has_res: bool = view.resources_by_row.has(row)
		var has_feature: bool = view.features_by_row.has(row) or (view.data != null and not view.data.site.is_empty() and view.data.cell_from_index(int(view.data.site.depot_cell)).y == row)
		var has_loot: bool = view.loot_cells_by_row.has(row)
		visible = not view.retain_static_rows or has_res or has_feature or has_loot or view._building_on_row(row)
		if not visible:
			_rebuild_job = {}
			return
		if not view.retain_static_rows:
			_rebuild_job = {}
			view._install_building_runs(self, row)
			return
		_rebuild_job = {"cursor": 0, "run": null, "animated": false, "feature": has_feature, "visible": visible}
		visible = false
	func step_rebuild() -> bool:
		if _rebuild_job.is_empty(): return true
		var keys: Array = view.resources_by_row.get(row, [])
		var cursor := int(_rebuild_job.cursor)
		if cursor < keys.size():
			var key: String = keys[cursor]
			var animated: bool = int(view.data.resource_base[key].kind) in [Env.Kind.WILDLIFE, Env.Kind.FISH]
			var run: ResourceRun = _rebuild_job.run
			if run == null or animated != bool(_rebuild_job.animated):
				run = ResourceRun.new()
				run.view = view; run.row = row; run.use_parent_material = true
				add_child(run)
				if animated: animated_runs.append(run)
				_rebuild_job.run = run; _rebuild_job.animated = animated
			run.keys.append(key)
			_rebuild_job.cursor = cursor + 1
			return false
		if bool(_rebuild_job.feature):
			var features := ResourceRun.new()
			features.view = view
			features.row = row
			features.decorations = true
			features.use_parent_material = true
			add_child(features)
		view._install_building_runs(self, row)
		visible = bool(_rebuild_job.visible)
		_rebuild_job = {}
		return true

func _ready() -> void:
	var prop_material := ShaderMaterial.new()
	prop_material.shader = PROP_SHADER
	material = prop_material
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var ground := BuildingRun.new()
	ground.name = "BuildingGround"
	ground.view = self
	ground.use_parent_material = false
	add_child(ground)
	_building_ground = ground

var _display_job: Dictionary = {}
var _display_generation := 0

func display(value: TerrainData) -> void:
	begin_display(value)
	_display_job.atomic = true
	while not _display_job.is_empty(): step_display(0, 4096)

func begin_display(value: TerrainData) -> int:
	cancel_display()
	visible = true
	data = value
	building_preview.clear()
	_building_preview_draws.clear()
	_building_preview_signature = 0
	for row: Node2D in rows:
		remove_child(row)
		row.queue_free()
	rows.clear()
	_display_job = {"generation": _display_generation, "data": value, "stage": "rows", "row": 0}
	return _display_generation

func cancel_display() -> void:
	visible = false
	_display_generation += 1
	_display_job = {}

func display_pending() -> bool:
	return not _display_job.is_empty()

func _append_resource_row(y: int) -> void:
	var row := ResourceRow.new()
	row.name = "ResourceRow%d" % y; row.view = self; row.row = y
	row.z_index = 10 + y; row.use_parent_material = true
	add_child(row); rows.append(row)

func step_display(budget_usec: int = 2000, max_units: int = 256) -> bool:
	if _display_job.is_empty(): return true
	if _display_job.data != data or int(_display_job.generation) != _display_generation:
		cancel_display()
		return false
	var started := Time.get_ticks_usec()
	for unit in range(maxi(1, max_units)):
		var job: Dictionary = _display_job
		if job.stage == "rows":
			if int(job.row) < data.size.y:
				_append_resource_row(int(job.row)); job.row = int(job.row) + 1
			else:
				_seen_revision = -1
				loot_cells_by_row.clear()
				for cell: int in data.ground_loot_at:
					data.ground_loot_dirty_rows[data.cell_from_index(cell).y] = true
				if bool(job.get("atomic", false)) or data.site.is_empty() or not data.site.features.is_empty() or view_mode != 0:
					# Existing arbitrary-state display keeps its original refresh path.
					refresh(); _display_job = {}; return true
				resources_by_row.clear(); features_by_row.clear(); building_draws_by_row.clear(); heat.clear()
				job.index = _begin_resource_rows(); job.stage = "index"
		elif job.stage == "index":
			if _step_resource_rows(job.index): job.stage = "runs"; job.row = 0; job.started_row = false
		elif job.stage == "runs":
			if int(job.row) >= rows.size():
				_seen_revision = data.environment_revision
				queue_redraw()
				if is_instance_valid(_building_ground): _building_ground.queue_redraw()
				_display_job = {}; return true
			var row: ResourceRow = rows[int(job.row)]
			if not bool(job.started_row): row.begin_rebuild(); job.started_row = true
			elif row.step_rebuild(): job.row = int(job.row) + 1; job.started_row = false
		if budget_usec > 0 and Time.get_ticks_usec() - started >= budget_usec: break
	return false

func display_source(value: TerrainData) -> void:
	# Immutable Adapter candidate: no SiteEnvironment.initialize or gameplay state.
	display(value)
	resources_by_row.clear()
	features_by_row.clear()
	building_draws_by_row.clear()
	heat.clear()
	for key: String in data.resource_base:
		var resource: Dictionary = data.resource_base[key]
		var source_rows: Array[int] = []
		source_rows.append(data.cell_from_index(int(resource.cell)).y)
		if int(resource.kind) == Env.Kind.WILDLIFE:
			for cell: int in resource.cells:
				var row := data.cell_from_index(cell).y
				if not source_rows.has(row): source_rows.append(row)
		for row: int in source_rows:
			if not resources_by_row.has(row): resources_by_row[row] = []
			resources_by_row[row].append(key)
	for row: Node2D in rows: row.rebuild()

func _begin_resource_rows() -> Dictionary:
	return {"keys": data.resource_base.keys(), "key": 0, "cell": 0, "rows": [], "publish": 0, "phase": "begin"}

func _step_resource_rows(job: Dictionary) -> bool:
	if int(job.key) >= job.keys.size(): return true
	var key: String = job.keys[int(job.key)]
	var resource: Dictionary = data.resource_base[key]
	if job.phase == "begin":
		job.rows = [data.cell_from_index(int(resource.cell)).y]
		job.phase = "cells" if int(resource.kind) == Env.Kind.WILDLIFE or (Env.ecology_active(data) and int(resource.kind) == Env.Kind.FISH) else "publish"
	elif job.phase == "cells":
		if int(job.cell) < resource.cells.size():
			var row := data.cell_from_index(int(resource.cells[int(job.cell)])).y
			if not job.rows.has(row): job.rows.append(row)
			job.cell = int(job.cell) + 1
		else: job.phase = "publish"
	else:
		if int(job.publish) < job.rows.size():
			var row := int(job.rows[int(job.publish)])
			if not resources_by_row.has(row): resources_by_row[row] = []
			resources_by_row[row].append(key)
			job.publish = int(job.publish) + 1
		else:
			job.key = int(job.key) + 1; job.cell = 0; job.publish = 0; job.phase = "begin"
	return int(job.key) >= job.keys.size()

func refresh() -> void:
	if data == null or data.site.is_empty():
		return
	resources_by_row.clear()
	features_by_row.clear()
	var row_index := _begin_resource_rows()
	while not _step_resource_rows(row_index): pass
	for key: String in data.site.features:
		var row := 0
		var feature_rows: Array[int] = []
		for i: int in data.site.features[key].cells:
			row = maxi(row, data.cell_from_index(i).y)
			if str(data.site.features[key].kind) in ["palisade", "warehouse"] and str(data.site.features[key].stage) == "complete" and not feature_rows.has(data.cell_from_index(i).y):
				feature_rows.append(data.cell_from_index(i).y)
		if feature_rows.is_empty():
			feature_rows.append(row)
		for feature_row: int in feature_rows:
			if not features_by_row.has(feature_row):
				features_by_row[feature_row] = []
			features_by_row[feature_row].append(key)
	_rebuild_building_draws()
	heat.clear()
	if view_mode >= 2:
		heat.resize(data.surface_types.size())
		for i: int in range(heat.size()):
			var condition := Env.land(data, data.cell_from_index(i))
			var score := int(condition[["farm", "pasture", "water", "build"][view_mode - 2]])
			var color := Color("c45c46").lerp(Color("e1b656"), minf(1.0, float(score) / 45.0))
			if score > 45:
				color = Color("e1b656").lerp(Color("57b580"), float(score - 45) / 55.0)
			if view_mode == 4:
				color = Color("64c7e6") if score > 0 else Color("a88565")
			color.a = 0.38
			heat[i] = color
	_seen_revision = data.environment_revision
	queue_redraw()
	if is_instance_valid(_building_ground): _building_ground.queue_redraw()
	for row: Node2D in rows:
		row.rebuild()

func show_combat_move_preview(preview: Dictionary) -> void:
	combat_preview_platform_slots.assign(preview.get("platform_slots", []))
	combat_preview_queue_slots.assign(preview.get("approach_queue_slots", []))
	combat_preview_anchor = preview.get("resolved_anchor", Vector2i(-1, -1))
	combat_preview_facing = preview.get("final_facing", Vector2i.ZERO)
	combat_preview_slot_facing = preview.get("slot_facing", {}).duplicate()
	queue_redraw()

func clear_combat_move_preview() -> void:
	if combat_preview_platform_slots.is_empty() and combat_preview_queue_slots.is_empty() and combat_preview_facing == Vector2i.ZERO:
		return
	combat_preview_platform_slots.clear()
	combat_preview_queue_slots.clear()
	combat_preview_anchor = Vector2i(-1, -1)
	combat_preview_facing = Vector2i.ZERO
	combat_preview_slot_facing.clear()
	queue_redraw()

func animate(delta: float) -> void:
	if display_pending(): return
	if data == null:
		return
	for row: int in data.ground_loot_dirty_rows:
		var cells: Array[int] = []
		for x in range(data.size.x):
			var cell := data.index(Vector2i(x, row))
			if data.ground_loot_at.has(cell):
				cells.append(cell)
		loot_cells_by_row[row] = cells
		if not cells.is_empty():
			rows[row].visible = true
		rows[row].queue_redraw()
	data.ground_loot_dirty_rows.clear()
	if data.environment_revision != _seen_revision:
		refresh()
	if bool(data.site.paused):
		return
	animation_time += delta
	if retain_static_rows and not rows.is_empty():
		# Same 0.12-second animation period, with row phases spread across it.
		# A late frame redraws each due row at most once; simulation never waits.
		var next_elapsed := _animation_elapsed + delta
		var first := floori(_animation_elapsed / 0.12 * rows.size())
		var stop := floori(next_elapsed / 0.12 * rows.size())
		_animation_elapsed = fmod(next_elapsed, 0.12)
		for cursor in range(first, mini(first + rows.size(), stop)):
			for run: Node2D in rows[cursor % rows.size()].animated_runs: run.queue_redraw()
		return
	_animation_elapsed += delta
	if _animation_elapsed < 0.12:
		return
	_animation_elapsed = 0.0
	for row_index: int in resources_by_row:
		for key: String in resources_by_row[row_index]:
			if int(data.resource_base[key].kind) in [Env.Kind.WILDLIFE, Env.Kind.FISH]:
				rows[row_index].queue_redraw()
				break

func _draw() -> void:
	if data == null or data.site.is_empty():
		return
	# Walkable crop beds and low defensive positions stay below their occupants.
	for feature: Dictionary in data.site.features.values():
		if _building_uses_art(feature): continue
		if str(feature.get("kind", "")) == "well" and int(feature.get("civil_version", 0)) == Runtime.CIVIL_VERSION and not Runtime.feature_usable(feature):
			for index: int in feature.cells:
				draw_texture_rect_region(PROPS, Rect2(Vector2(data.cell_from_index(index)) * CELL + Vector2(8, 40), Vector2(CELL - 16, 18)), PROP_REGIONS.well, _civil_building_tint(feature))
			continue
		if str(feature.stage) != "complete" or (not str(feature.kind).contains("farm") and str(feature.kind) != "fighting_position"):
			continue
		for i: int in feature.cells:
			if str(feature.kind).contains("farm"):
				var plot := Rect2(Vector2(data.cell_from_index(i)) * CELL, Vector2.ONE * CELL).grow(-2)
				draw_texture_rect_region(PROPS, plot, PROP_REGIONS.farm)
			elif str(feature.kind) == "fighting_position":
				_draw_defense_cell(self, _center(i), false)
	for i: int in range(heat.size()):
		draw_rect(Rect2(Vector2(data.cell_from_index(i)) * CELL, Vector2.ONE * CELL), heat[i])
	for zone: Dictionary in data.site.zones:
		if not bool(zone.active) or str(zone.action) in ["construct", "operate"]:
			continue
		for i: int in zone.cells:
			var rect := Rect2(Vector2(data.cell_from_index(i)) * CELL, Vector2.ONE * CELL)
			draw_rect(rect.grow(-2), Color(0.98, 0.81, 0.39, 0.045))
			draw_rect(rect.grow(-2), Color(0.98, 0.81, 0.39, 0.34), false, 1.5)
	if selection.has_area():
		var rect := Rect2(Vector2(selection.position) * CELL, Vector2(selection.size) * CELL)
		var color := Color("fff0b4") if selection_valid else Color("f56b60")
		draw_rect(rect, Color(color, 0.13))
		draw_rect(rect, color, false, 3.0)
	if data.contains(preview_entrance):
		var entrance := (Vector2(preview_entrance) + Vector2.ONE * 0.5) * CELL
		draw_arc(entrance, 22, 0, TAU, 20, Color("a2eacf"), 3)
		draw_string(ThemeDB.fallback_font, entrance + Vector2(-18, 5), "入口", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("eefff7"))
	for cell: Vector2i in combat_preview_platform_slots:
		draw_rect(Rect2(Vector2(cell) * CELL, Vector2.ONE * CELL).grow(-5), Color(0.22, 0.85, 0.55, 0.28))
		if combat_preview_slot_facing.has(cell) and combat_preview_slot_facing[cell] != combat_preview_facing:
			var direction := Vector2(combat_preview_slot_facing[cell])
			var center := (Vector2(cell) + Vector2.ONE * 0.5) * CELL
			var tip := center + direction * CELL * 0.24
			var side := Vector2(-direction.y, direction.x) * CELL * 0.08
			draw_line(center, tip, Color("fff3a6"), 2)
			draw_line(tip, tip - direction * CELL * 0.1 + side, Color("fff3a6"), 2)
			draw_line(tip, tip - direction * CELL * 0.1 - side, Color("fff3a6"), 2)
	for cell: Vector2i in combat_preview_queue_slots:
		draw_rect(Rect2(Vector2(cell) * CELL, Vector2.ONE * CELL).grow(-5), Color(0.26, 0.62, 0.96, 0.25))
	if data.contains(combat_preview_anchor) and combat_preview_facing in TerrainData.DIRECTIONS:
		var center := (Vector2(combat_preview_anchor) + Vector2.ONE * 0.5) * CELL
		var slot_count := combat_preview_platform_slots.size() + combat_preview_queue_slots.size()
		if slot_count > 0:
			center = Vector2.ZERO
			for slot: Vector2i in combat_preview_platform_slots:
				center += (Vector2(slot) + Vector2.ONE * 0.5) * CELL
			for slot: Vector2i in combat_preview_queue_slots:
				center += (Vector2(slot) + Vector2.ONE * 0.5) * CELL
			center /= slot_count
		var tip := center + Vector2(combat_preview_facing) * CELL * 0.7
		var side := Vector2(-combat_preview_facing.y, combat_preview_facing.x) * CELL * 0.16
		draw_line(center, tip, Color("fff3a6"), 5)
		draw_line(tip, tip - Vector2(combat_preview_facing) * CELL * 0.22 + side, Color("fff3a6"), 5)
		draw_line(tip, tip - Vector2(combat_preview_facing) * CELL * 0.22 - side, Color("fff3a6"), 5)

func draw_row(canvas: Node2D, row_index: int) -> void:
	if data == null:
		return
	_draw_row_loot(canvas, row_index)
	_draw_row_resources(canvas, row_index, resources_by_row.get(row_index, []))
	_draw_row_features(canvas, row_index)

func _draw_thick_line(canvas: Node2D, from: Vector2, to: Vector2, color: Color, width: float = 1.0) -> void:
	if canvas.has_meta(&"batcher"):
		(canvas.get_meta(&"batcher") as TriangleBatcher).add_line(from, to, color, width)
	else:
		var dir := (to - from).normalized()
		var normal := Vector2(-dir.y, dir.x) * (maxf(0.5, width) * 0.5)
		canvas.draw_colored_polygon(PackedVector2Array([from - normal, from + normal, to + normal, to - normal]), color)

func _draw_polygon(canvas: Node2D, poly_points: PackedVector2Array, color: Color) -> void:
	if canvas.has_meta(&"batcher"):
		(canvas.get_meta(&"batcher") as TriangleBatcher).add_polygon(poly_points, color)
	else:
		canvas.draw_colored_polygon(poly_points, color)

func _draw_circle(canvas: Node2D, p: Vector2, radius: float, color: Color) -> void:
	if canvas.has_meta(&"batcher"):
		(canvas.get_meta(&"batcher") as TriangleBatcher).flush()
	canvas.draw_circle(p, radius, color)

func _draw_string(canvas: Node2D, font: Font, pos: Vector2, text: String, alignment := HORIZONTAL_ALIGNMENT_LEFT, width := -1, font_size := 16, text_modulate := Color.WHITE) -> void:
	if canvas.has_meta(&"batcher"):
		(canvas.get_meta(&"batcher") as TriangleBatcher).flush()
	canvas.draw_string(font, pos, text, alignment, width, font_size, text_modulate)

func _draw_row_loot(canvas: Node2D, row_index: int) -> void:
	var loot_cells: Array = loot_cells_by_row.get(row_index, [])
	if loot_cells.is_empty():
		return
	var batcher := TriangleBatcher.new(canvas.get_canvas_item())
	canvas.set_meta(&"batcher", batcher)
	for cell: int in loot_cells:
		var point := _center(cell) + Vector2(20, 12)
		batcher.add_rect(Rect2(point - Vector2(8, 5), Vector2(16, 10)), Color("d2b36c"))
		batcher.add_line(point + Vector2(-8, -1), point + Vector2(8, -1), Color("624e31"), 2.0)
	batcher.flush()
	canvas.remove_meta(&"batcher")
	for cell: int in loot_cells:
		var count: int = data.ground_loot_at.get(cell, []).size()
		if count > 1:
			var point := _center(cell) + Vector2(20, 12)
			canvas.draw_string(ThemeDB.fallback_font, point + Vector2(8, 1), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("fff0bd"))

func _draw_row_resources(canvas: Node2D, row_index: int, keys: Array) -> void:
	if keys.is_empty():
		return
	var batcher := TriangleBatcher.new(canvas.get_canvas_item())
	canvas.set_meta(&"batcher", batcher)
	for key: String in keys:
		var r := Env.resource(data, key)
		if bool(r.cleared):
			# Cleared originals get a label only; no plant or recovery sprite is drawn.
			var cleared_label := _resource_label(key, r)
			if not cleared_label.is_empty() and row_index == data.cell_from_index(int(r.cell)).y:
				batcher.flush()
				canvas.draw_string(ThemeDB.fallback_font, _center(int(r.cell)) + Vector2(-28, 40), cleared_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff4d8"))
			continue
		var display_cell := int(r.cell)
		var display_cells: Array[int] = []
		if Env.ecology_active(data) and int(r.kind) in Env.POPULATION_KINDS:
			for index: int in r.cells:
				if Env.ecology_cell_usable(data, r, index):
					display_cells.append(index)
			if display_cells.is_empty():
				continue
			display_cell = display_cells[0]
		var feature_key := str(data.feature_at[display_cell]) if not data.feature_at.is_empty() else "0"
		if feature_key != "0" and str(data.site.features[feature_key].stage) == "complete":
			if int(r.kind) not in [Env.Kind.CLAY, Env.Kind.IRON] or view_mode != 1:
				continue
		if view_mode == 1 and resource_filter >= 0 and int(r.kind) != resource_filter:
			continue
		var p := _center(display_cell)
		if int(r.kind) == Env.Kind.WILDLIFE:
			var art_index := wildlife_art_index(int(r.variant), int(r.cell))
			var animals: Array = r.cells if display_cells.is_empty() else display_cells
			for n: int in range(mini(int(r.remaining), animals.size())):
				var i: int = int(animals[n])
				if data.cell_from_index(i).y != row_index or not data.is_walkable(data.cell_from_index(i)) or (not data.feature_at.is_empty() and data.feature_at[i] != 0):
					continue
				var phase := animation_time * 0.8 + float(n * 2 + int(r.cell) % 11)
				var animal_position := _center(i) + Vector2(sin(phase) * 9, cos(phase * 0.7) * 5)
				_draw_wildlife(canvas, animal_position, phase, art_index)
		if row_index != data.cell_from_index(display_cell).y:
			continue
		if int(r.remaining) <= 0:
			_draw_exhausted(canvas, r, p)
		else:
			match int(r.kind):
				Env.Kind.TIMBER:
					_draw_tree(canvas, p, int(r.variant))
				Env.Kind.STONE:
					_draw_rock(canvas, p, Color("879087"), false)
				Env.Kind.CLAY:
					_draw_resource_sprite(canvas, p, "clay")
				Env.Kind.IRON:
					_draw_rock(canvas, p, Color("676963"), true)
				Env.Kind.SALT:
					_draw_resource_sprite(canvas, p, "salt")
				Env.Kind.FOOD, Env.Kind.HERB:
					_draw_plant(canvas, p, int(r.kind) == Env.Kind.HERB)
				Env.Kind.FISH:
					for n: int in range(mini(3, int(r.remaining))):
						var offset := Vector2(sin(animation_time * 0.7 + n * 2.0) * 12.0, float(n - 1) * 10)
						_draw_fish(canvas, p + offset)
				Env.Kind.WILDLIFE:
					pass # Drawn at each animal's ground row above.
		if view_mode == 1 or key == selected_resource:
			batcher.flush()
			var color: Color = Env.COLORS[int(r.kind)]
			canvas.draw_arc(p, 29, 0, TAU, 24, color.lightened(0.25), 2.5)
			var label := _resource_label(key, r)
			canvas.draw_string(ThemeDB.fallback_font, p + Vector2(-28, 40), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff4d8"))
	batcher.flush()
	canvas.remove_meta(&"batcher")

# Pure presentation only. Query ecology when this original label is visible.
func _resource_label(key: String, resource: Dictionary) -> String:
	if view_mode != 1 and key != selected_resource: return ""
	if view_mode == 1 and resource_filter >= 0 and int(resource.kind) != resource_filter: return ""
	var admitted := Env.ecology_active(data)
	if bool(resource.cleared) and (not admitted or int(resource.kind) not in Env.RESTORABLE_KINDS): return ""
	var label := str(Env.NAMES[int(resource.kind)])
	if key == selected_resource:
		label += " %s" % (str(int(resource.remaining)) if bool(resource.discovered) else "待勘探")
	if not admitted: return label
	var info := Env.ecology_info(data, key)
	if bool(info.cleared): label += " ·待復育"
	if str(info.mode) == "protected": label += " ·休養保護"
	elif str(info.mode) == "sustainable" and bool(info.population) and bool(info.resting): label += " ·休採"
	if int(info.remaining) <= 0 and bool(info.recoverable): label += " ·待恢復"
	return label

func _draw_row_features(canvas: Node2D, row_index: int) -> void:
	var feature_keys: Array = features_by_row.get(row_index, [])
	var is_depot: bool = data != null and not data.site.is_empty() and data.cell_from_index(int(data.site.depot_cell)).y == row_index
	if feature_keys.is_empty() and not is_depot:
		return
	var batcher := TriangleBatcher.new(canvas.get_canvas_item())
	canvas.set_meta(&"batcher", batcher)
	for key: String in feature_keys:
		_draw_feature(canvas, data.site.features[key], row_index)
	batcher.flush()
	canvas.remove_meta(&"batcher")
	if is_depot:
		var depot := _center(int(data.site.depot_cell))
		_draw_prop(canvas, "chest", depot + Vector2(0, 15), 40.0)
		canvas.draw_string(ThemeDB.fallback_font, depot + Vector2(-30, 38), "營地箱", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff0cc"))

func _draw_prop(canvas: Node2D, kind: String, foot: Vector2, width: float, color: Color = Color.WHITE) -> void:
	if canvas.has_meta(&"batcher"):
		(canvas.get_meta(&"batcher") as TriangleBatcher).flush()
	var region: Rect2 = PROP_REGIONS[kind]
	var size := Vector2(width, width * region.size.y / region.size.x)
	canvas.draw_texture_rect_region(PROPS, Rect2(foot - Vector2(size.x * 0.5, size.y), size), region, color)

func _center(i: int) -> Vector2:
	return (Vector2(data.cell_from_index(i)) + Vector2.ONE * 0.5) * CELL

func _oval(canvas: Node2D, p: Vector2, radius: Vector2, color: Color) -> void:
	if canvas.has_meta(&"batcher") and _oval_can_reuse_triangles(p, radius):
		(canvas.get_meta(&"batcher") as TriangleBatcher).add_oval(p, radius, color, _oval_unit, _oval_triangles)
		return
	# Same CPU float32 vertices, without repeating trigonometry for each prop.
	var oval_transform := Transform2D(Vector2(radius.x, 0), Vector2(0, radius.y), p)
	var points: PackedVector2Array = oval_transform * _oval_unit
	if _oval_can_reuse_triangles(p, radius):
		# Bound float32 conditioning: very thin/large/far ellipses keep the
		# original triangulation, which can choose different rounded ears.
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), _oval_triangles, points, PackedColorArray([color]))
	else:
		canvas.draw_colored_polygon(points, color)

static func _oval_can_reuse_triangles(p: Vector2, radius: Vector2) -> bool:
	return radius.x >= 3.0 and radius.y >= 3.0 and radius.x <= 256.0 and radius.y <= 256.0 and absf(p.x) <= 8192.0 and absf(p.y) <= 8192.0

static func _make_oval_unit() -> PackedVector2Array:
	var points := PackedVector2Array()
	for n: int in range(20):
		var angle := float(n) * TAU / 20.0
		points.append(Vector2(cos(angle), sin(angle)))
	return points

static func _load_resource_art() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RESOURCE_ART_MANIFEST))
	assert(parsed is Dictionary and parsed.get("schema_version") == 1, "Missing natural resource art manifest")
	var art: Dictionary = parsed
	art["_texture"] = load(str(art.texture)) as Texture2D
	assert(art._texture != null, "Missing natural resource atlas")
	art["_wildlife_indices"] = {}
	for index: int in range(art.wildlife.size()):
		var animal: Dictionary = art.wildlife[index]
		art._wildlife_indices[str(animal.name)] = index
		animal["_texture"] = load(str(animal.texture)) as Texture2D
		assert(animal._texture != null, "Missing wildlife walk atlas")
	return art

func _draw_resource_sprite(canvas: Node2D, p: Vector2, resource_name: String) -> void:
	var sprite: Dictionary = _resource_art.sprites[resource_name]
	var region_data: Array = sprite.region
	var region := Rect2(float(region_data[0]), float(region_data[1]), float(region_data[2]), float(region_data[3]))
	var size := Vector2(float(sprite["size"][0]), float(sprite["size"][1]))
	var anchor := Vector2(float(sprite.anchor[0]), float(sprite.anchor[1]))
	var texture: Texture2D = _resource_art._texture
	if canvas.has_meta(&"batcher"):
		(canvas.get_meta(&"batcher") as TriangleBatcher).flush()
	canvas.draw_texture_rect_region(texture, Rect2(p - size * anchor, size), region)

func _draw_tree(canvas: Node2D, p: Vector2, variant: int) -> void:
	_draw_resource_sprite(canvas, p, TREE_ART[posmod(variant, TREE_ART.size())])

func _draw_rock(canvas: Node2D, p: Vector2, _color: Color, iron: bool) -> void:
	_draw_resource_sprite(canvas, p, "iron" if iron else "stone")

func _draw_plant(canvas: Node2D, p: Vector2, herb: bool) -> void:
	_draw_resource_sprite(canvas, p, "herb" if herb else "food")

func _draw_fish(canvas: Node2D, p: Vector2) -> void:
	_draw_resource_sprite(canvas, p, "fish")

static func wildlife_art_index(variant: int, source_cell: int) -> int:
	return int(_resource_art._wildlife_indices[Env.wildlife_species(variant, source_cell)])

func _draw_wildlife(canvas: Node2D, p: Vector2, phase: float, art_index: int, display_width: float = -1.0) -> void:
	var art: Dictionary = _resource_art.wildlife[art_index]
	var texture: Texture2D = art._texture
	var cell_size := texture.get_size() / Vector2(float(art.grid[0]), float(art.grid[1]))
	var direction := 0 if cos(phase) >= 0.0 else 1
	# Four authored poses share the existing roaming phase and fixed ground anchor.
	var frame := posmod(floori(phase * 2.0), int(art.grid[0]))
	var region := Rect2(Vector2(float(frame), float(direction)) * cell_size, cell_size)
	var width := display_width if display_width > 0.0 else float(art.width)
	var size := Vector2(width, width * cell_size.y / cell_size.x)
	var anchor := Vector2(float(art.anchors[direction][0]), float(art.anchors[direction][1]))
	_oval(canvas, p, Vector2(20, 7) * (width / float(art.width)), Color(0.08, 0.12, 0.08, 0.26))
	if canvas.has_meta(&"batcher"):
		(canvas.get_meta(&"batcher") as TriangleBatcher).flush()
	canvas.draw_texture_rect_region(texture, Rect2(p - size * anchor, size), region)

func _draw_animal(canvas: Node2D, p: Vector2, phase: float, variant: int) -> void:
	_oval(canvas, p + Vector2(0, 5), Vector2(20, 7), Color(0.08, 0.12, 0.08, 0.26))
	for n: int in range(4):
		var leg := p + Vector2(float(n % 2) * 20 - 11, -10)
		_draw_thick_line(canvas, leg, leg + Vector2(sin(phase * 3.0 + n * PI) * 3, 14 - n % 2 * 3), Color("604c38"), 3.0)
	var color := Color("b18a59") if variant != 1 else Color("78675b")
	_oval(canvas, p + Vector2(-1, -16), Vector2(19, 10), color)
	_oval(canvas, p + Vector2(18, -25), Vector2(9, 7), color.lightened(0.1))
	_draw_thick_line(canvas, p + Vector2(12, -13), p + Vector2(15, -29), color, 7.0)
	_draw_thick_line(canvas, p + Vector2(-18, -16), p + Vector2(-25, -23), color.darkened(0.1), 3.0)
	_draw_circle(canvas, p + Vector2(21, -27), 1.4, Color("262b22"))
	if variant == 0:
		var horn := [p + Vector2(15, -29), p + Vector2(11, -41), p + Vector2(7, -43)]
		for k in range(horn.size() - 1):
			_draw_thick_line(canvas, horn[k], horn[k + 1], Color("d4c9a5"), 2.0)
		_draw_thick_line(canvas, p + Vector2(12, -37), p + Vector2(18, -43), Color("d4c9a5"), 2.0)
	else:
		_draw_thick_line(canvas, p + Vector2(14, -29), p + Vector2(12, -37), color.darkened(0.15), 4.0)

func _draw_exhausted(canvas: Node2D, r: Dictionary, p: Vector2) -> void:
	if int(r.kind) == Env.Kind.TIMBER:
		_oval(canvas, p, Vector2(12, 8), Color("725139"))
		_oval(canvas, p + Vector2(0, -3), Vector2(10, 5), Color("c7a477"))
	elif int(r.kind) in [Env.Kind.STONE, Env.Kind.CLAY, Env.Kind.IRON]:
		_oval(canvas, p, Vector2(23, 11), Color(0.2, 0.22, 0.2, 0.38))
	elif int(r.kind) in [Env.Kind.FOOD, Env.Kind.HERB]:
		_draw_thick_line(canvas, p, p + Vector2(-3, -9), Color("749052"), 2.0)

func _draw_defense_cell(canvas: Node2D, p: Vector2, palisade: bool) -> void:
	if palisade:
		_oval(canvas, p + Vector2(0, 17), Vector2(28, 7), Color(0.12, 0.1, 0.07, 0.3))
		for x: int in [-24, -12, 0, 12, 24]:
			var base := p + Vector2(x, 16)
			_draw_polygon(canvas, PackedVector2Array([base + Vector2(-5, 0), base + Vector2(-5, -32), base + Vector2(0, -41), base + Vector2(5, -32), base + Vector2(5, 0)]), Color("856344"))
			_draw_thick_line(canvas, base + Vector2(-2, -28), base + Vector2(-2, -2), Color("c59b66"), 2.0)
		for y: int in [-5, 9]:
			_draw_thick_line(canvas, p + Vector2(-30, y), p + Vector2(30, y), Color("56442f"), 4.0)
	else:
		var batcher: TriangleBatcher = (canvas.get_meta(&"batcher") as TriangleBatcher) if canvas.has_meta(&"batcher") else null
		if batcher != null:
			batcher.add_rect(Rect2(p - Vector2(27, 25), Vector2(54, 50)), Color(0.37, 0.32, 0.23, 0.35))
			for x: int in [-21, -7, 7, 21]:
				var bag := Rect2(p + Vector2(x - 6, 17), Vector2(12, 8))
				batcher.add_rect(bag, Color("aaa18a"))
				batcher.add_rect_outline(bag, Color("5b594d"), 1.5)
			for x: int in [-27, 19]:
				for y: int in [-19, -5, 9]:
					var bag := Rect2(p + Vector2(x, y), Vector2(8, 12))
					batcher.add_rect(bag, Color("aaa18a"))
					batcher.add_rect_outline(bag, Color("5b594d"), 1.5)
		else:
			canvas.draw_rect(Rect2(p - Vector2(27, 25), Vector2(54, 50)), Color(0.37, 0.32, 0.23, 0.35))
			for x: int in [-21, -7, 7, 21]:
				var bag := Rect2(p + Vector2(x - 6, 17), Vector2(12, 8))
				canvas.draw_rect(bag, Color("aaa18a"))
				canvas.draw_rect(bag, Color("5b594d"), false, 1.5)
			for x: int in [-27, 19]:
				for y: int in [-19, -5, 9]:
					var bag := Rect2(p + Vector2(x, y), Vector2(8, 12))
					canvas.draw_rect(bag, Color("aaa18a"))
					canvas.draw_rect(bag, Color("5b594d"), false, 1.5)

func _building_uses_art(feature: Dictionary) -> bool:
	if int(feature.get("fire_layout_version", 0)) == Runtime.FIRE_LAYOUT_VERSION and str(feature.get("kind", "")) == "warehouse": return true
	return int(feature.get("layout_version", 0)) == 1 and str(feature.get("kind", "")) not in ["level", "warehouse", "irrigation_channel"] and not (str(feature.get("kind", "")) == "well" and int(feature.get("quarter", 0)) == 0)


func building_art_key(feature: Dictionary) -> String:
	var kind := str(feature.get("kind", ""))
	var quarter := int(feature.get("quarter", 0))
	var direction: String = ["south", "west", "north", "east"][quarter]
	if kind == "house": return "house_" + str(feature.get("variant", "standard")) + "_" + direction
	# Each settlement level only swaps the formal artwork; footprint stays fixed 5x5.
	if kind == "settlement_center": return "settlement_center_l%d_%s" % [clampi(int(data.site.get("settlement", {}).get("level", 1)) if data != null else 1, 1, Runtime.SETTLEMENT_MAX_LEVEL), direction]
	if kind == "barracks_dormitory": return kind + "_" + direction
	if kind in ["palisade", "stone_wall"]: return kind + "_orthogonal"
	if kind in ["gate", "wall_stairs"]: return ("stairs" if kind == "wall_stairs" else "gate") + "_" + str(feature.get("material", "wood")) + "_" + direction
	if kind == "level" or (kind == "well" and quarter == 0): return ""
	if kind == "road": return kind
	if kind in Runtime.MILITARY_KINDS: return "road" # Compound art borrows this approved ground tile.
	if kind in ["farm", "fiber_farm", "fodder_farm"]: return kind + ("_west" if quarter % 2 else "")
	return kind + ["", "_west", "_north", "_east"][quarter]

# Formal buildings never fall back to placeholder geometry; callers refuse
# placement explicitly while an approved asset is absent from the manifest.
func building_art_available(feature: Dictionary) -> bool:
	if feature.get("kind") == "irrigation_channel": return data != null and Runtime._irrigation_path(data, feature.get("cells")) and Runtime._irrigation_config(feature.get("irrigation"), data.site)
	if _building_art_manifest.is_empty():
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUILDING_ART_ROOT + "art_manifest.json"))
		if not manifest is Dictionary or not manifest.get("assets") is Dictionary: return false
		_building_art_manifest = manifest
	var key: String = building_art_key(feature)
	if feature.get("kind") == "survey_stakes": return Runtime._survey_stakes_asset_readable(_building_art_manifest.assets.get(key))
	return _building_art_manifest.assets.has(key)


func _building_asset(key: String, component: String = "") -> Dictionary:
	if _building_art_manifest.is_empty():
		_building_art_manifest = JSON.parse_string(FileAccess.get_file_as_string(BUILDING_ART_ROOT + "art_manifest.json"))
	var cache_key := key + ":" + component
	if _building_art.has(cache_key): return _building_art[cache_key]
	assert(_building_art_manifest.assets.has(key), "Missing formal building artwork: " + key)
	var asset: Dictionary = _building_art_manifest.assets[key]
	var result: Dictionary = asset.duplicate() if component.is_empty() else asset.sprites[component].duplicate()
	var file := str(result.get("file", asset.file))
	if not _building_textures.has(file):
		_building_textures[file] = load(BUILDING_ART_ROOT + file) as Texture2D
	assert(_building_textures[file] != null, "Cannot load formal building artwork: " + file)
	result["texture"] = _building_textures[file]
	result["file"] = file
	result["asset_key"] = key
	result["component"] = component
	var box: Array = result.bbox
	result["region"] = Rect2(float(box[0]), float(box[1]), float(box[2]), float(box[3]))
	_building_art[cache_key] = result
	return result

func _building_sprite_size(sprite: Dictionary) -> Vector2:
	if sprite.has("world_size"): return Vector2(float(sprite.world_size[0]), float(sprite.world_size[1]))
	var size: Array = sprite.get("art_size", [1, 1])
	var region: Rect2 = sprite.region
	var scale_value := float(size[0]) * CELL / maxf(1.0, region.size.x * float(sprite.get("ground_width_fraction", 1.0)))
	return region.size * scale_value

func _building_draw(sprite: Dictionary, rect: Rect2, row: int, part_id: String = "", foreground: bool = false) -> Dictionary:
	return {"texture": sprite.texture, "region": sprite.region, "rect": rect, "row": row, "part_id": part_id,
		"asset_key": sprite.asset_key, "component": sprite.component, "file": sprite.file, "foreground": foreground, "color": Color.WHITE}

func _building_crop(part: Dictionary, start: Vector2, end: Vector2) -> Dictionary:
	var result := part.duplicate()
	var rect: Rect2 = part.rect
	var region: Rect2 = part.region
	result.rect = Rect2(rect.position + rect.size * start, rect.size * (end - start))
	result.region = Rect2(region.position + region.size * start, region.size * (end - start))
	return result

func _building_local_point(feature: Dictionary, local: Vector2) -> Vector2:
	var bounds := Runtime._cell_bounds(data, feature.cells)
	var quarter := int(feature.get("quarter", 0))
	var base := Vector2(bounds.size.y, bounds.size.x) if quarter % 2 else Vector2(bounds.size)
	var point := local
	match quarter:
		1: point = Vector2(base.y - local.y, local.x)
		2: point = base - local
		3: point = Vector2(local.y, base.x - local.x)
	return (Vector2(bounds.position) + point) * CELL

func building_part_draws(feature: Dictionary, geometry: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if data == null or feature.get("cells", []).is_empty() or not _building_uses_art(feature): return result
	if str(feature.kind) == "survey_stakes" and not building_art_available(feature):
		push_error("MISSING_ART: survey_stakes requires readable formal directional PNG; no geometry fallback")
		return result
	if str(feature.kind) == "siege_ladder": return result # Generated sprite is shown by the original VehicleView.
	if geometry.is_empty(): geometry = Runtime.feature_geometry(data, feature)
	if _fire_component_presentation(feature, geometry): return _fire_component_draws(feature, geometry)
	var kind := str(feature.kind)
	var key := building_art_key(feature)
	var bounds := Runtime._cell_bounds(data, feature.cells)
	if kind == "survey_stakes":
		# Each real stake keeps its own contact cell and original row occlusion.
		for index: int in range(2):
			var art: Dictionary = _building_asset(key, "stake_%d" % index)
			var region: Rect2 = art.region
			var height := float(CELL) * 0.55
			var size := Vector2(height * region.size.x / region.size.y, height)
			var cell: Vector2i = bounds.position
			if index == 1:
				if int(feature.quarter) % 2 == 0: cell += Vector2i.RIGHT
				else: cell += Vector2i.DOWN
			var foot := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
			var anchor := Vector2(float(art.ground_anchor[0]), float(art.ground_anchor[1]))
			result.append(_building_draw(art, Rect2(foot - anchor * size, size), cell.y))
	elif kind == "bridge":
		result = _building_bridge_draws(feature)
	elif kind in Runtime.MILITARY_KINDS:
		result = _military_building_draws(feature)
	elif kind in ["palisade", "stone_wall"]:
		result = _building_wall_draws(feature, geometry, key)
	elif kind == "wall_stairs":
		result = _building_stair_draws(feature, geometry, key)
	elif kind == "gate":
		result = _building_gate_draws(feature, geometry, key)
	else:
		var art := _building_asset(key)
		var region: Rect2 = art.region
		var ground := kind in ["farm", "fiber_farm", "fodder_farm", "road", "fighting_position"]
		if ground or kind == "prison":
			for index: int in feature.cells:
				var cell := data.cell_from_index(index)
				var size := Vector2(CELL, CELL * region.size.y / region.size.x)
				var foot := (Vector2(cell) + Vector2(0.5, 1.0)) * CELL
				result.append(_building_draw(art, Rect2(foot - Vector2(size.x * 0.5, size.y), size), -1 if ground else cell.y))
		else:
			var core := bounds
			if kind in ["pasture", "horse_ranch"]:
				var base: Array = art.get("base_art_size", art.art_size)
				var a := _building_local_point(feature, Vector2.ZERO) / CELL
				var b := _building_local_point(feature, Vector2(float(base[0]), float(base[1]))) / CELL
				core = Rect2i(Vector2i(a.min(b)), Vector2i((a - b).abs()))
			result.append(_building_structure_draw(feature, art, core))
		if kind in ["pasture", "horse_ranch"]: result.append_array(_building_fence_draws(feature))
	if int(feature.get("civil_version", 0)) == Runtime.CIVIL_VERSION and geometry.parts.has("body"):
		var body: Dictionary = geometry.parts.body
		if float(body.hp) <= 0.0:
			# Crop the same approved PNG into low pieces inside real ground cells.
			# Ground row -1 precedes every original actor; no upright silhouette
			# or foreground floor remains after the original body collapses.
			result.clear()
			var art := _building_asset(key)
			var source: Rect2 = art.region
			for index: int in feature.cells:
				var cell := data.cell_from_index(index)
				var rubble := _building_draw(art, Rect2(Vector2(cell) * CELL + Vector2(8, 40), Vector2(CELL - 16, 18)), -1, "body")
				var uv := Vector2(cell - bounds.position) / Vector2(bounds.size)
				rubble.region = Rect2(source.position + source.size * uv, source.size / Vector2(bounds.size))
				rubble["state"] = "destroyed"
				rubble.color = _civil_building_tint(feature)
				result.append(rubble)
		else:
			for part: Dictionary in result:
				part.part_id = "body"
				part["state"] = "damaged" if float(body.hp) < float(body.max_hp) else "standing"
				part.color = _civil_building_tint(feature)
	var complete := str(feature.get("stage", "")) == "complete"
	for part: Dictionary in result:
		if not complete: part.color = Color(part.color, 0.38)
	return result

# Appearance is a pure projection of the original prospective civil body.
func _civil_building_tint(feature: Dictionary) -> Color:
	if int(feature.get("civil_version", 0)) != Runtime.CIVIL_VERSION: return Color.WHITE
	var fraction := clampf(float(feature.get("parts", {}).get("body", {}).get("hp", 0.0)) / Runtime.civil_max_hp(feature), 0.0, 1.0)
	return Color.WHITE.lerp(Color(0.53, 0.46, 0.36), 1.0 - fraction)


# The original row painter draws simple boards/masonry. No bitmap asset or
# separate render/navigation owner; the footprint and height are the feature's.
func _building_bridge_draws(feature: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in feature.cells:
		var cell := data.cell_from_index(index)
		var rise := float(int(feature.level) - int(data.height_levels[index])) * 48.0
		var rect := Rect2(Vector2(cell) * CELL - Vector2(0.0, rise), Vector2.ONE * CELL)
		for foreground: bool in [false, true]:
			result.append({"primitive": "bridge", "rect": rect, "row": cell.y, "foreground": foreground,
				"color": Color.WHITE, "part_id": "", "vertical": int(feature.quarter) % 2 == 0, "stone": str(feature.material) == "stone"})
	return result

func _draw_bridge_deck(canvas: Node2D, part: Dictionary) -> void:
	var rect: Rect2 = part.rect
	var alpha := float(part.color.a)
	var base := Color("909185") if bool(part.stone) else Color("967249")
	var edge := Color("51594f") if bool(part.stone) else Color("503b2a")
	base.a = alpha
	edge.a = alpha
	if not bool(part.foreground):
		canvas.draw_rect(rect, base)
		for step: int in range(1, 5):
			var offset := float(step) * CELL / 5.0
			var a := rect.position + (Vector2(0, offset) if bool(part.vertical) else Vector2(offset, 0))
			var b := a + (Vector2(CELL, 0) if bool(part.vertical) else Vector2(0, CELL))
			canvas.draw_line(a, b, edge, 1.5)
	else:
		for side: float in [3.0, CELL - 3.0]:
			var a := rect.position + (Vector2(side, 0) if bool(part.vertical) else Vector2(0, side))
			var b := a + (Vector2(0, CELL) if bool(part.vertical) else Vector2(CELL, 0))
			canvas.draw_line(a, b, edge, 5.0)

func _building_structure_draw(feature: Dictionary, art: Dictionary, core: Rect2i) -> Dictionary:
	var kind := str(feature.kind)
	var width := float(art.art_size[0]) * CELL - 6.0
	if kind == "well": width = 52.0
	width *= float(art.get("display_scale", 1.0))
	if kind in ["house", "barracks_dormitory"]: width /= float(art.get("foundation_width_fraction", 1.0))
	var region: Rect2 = art.region
	var size := Vector2(width, width * region.size.y / region.size.x)
	var foot := (Vector2(core.position) + Vector2(core.size.x * 0.5, core.size.y)) * CELL - Vector2(0, 6)
	var anchor := Vector2(0.5, 1.0)
	if kind in ["house", "tent", "barracks_dormitory"] and art.has("door_sill_anchor"):
		var base_size: Vector2i
		if kind == "barracks_dormitory": base_size = feature.base_size
		else: base_size = Runtime.building_spec(kind, Runtime._feature_options(feature)).base_size
		foot = _building_local_point(feature, Vector2(float(base_size.x) * 0.5, float(base_size.y)))
		anchor = Vector2(float(art.door_sill_anchor[0]), float(art.door_sill_anchor[1]))
	if kind == "well": foot.y -= 4.0
	return _building_draw(art, Rect2(foot - size * anchor, size), core.end.y - 1)

# Runtime owns both these module footprints and their blocked cells. The view
# only projects fixed-size modules through the original ground/row draw pipeline.
func _military_building_draws(feature: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var chinese_camp := str(feature.kind) == "barracks" and Runtime.barracks_type(feature) == "chinese"
	var ground := _building_asset("road")
	if str(feature.kind) == "barracks" and int(feature.get("barracks_layout_version", 1)) == 2:
		ground = ground.duplicate()
		# Use the original road's solid central gravel, excluding its grassy alpha border.
		ground.region = Rect2(440, 430, 360, 360)
	for index: int in feature.cells:
		var cell := data.cell_from_index(index)
		result.append(_building_draw(ground, Rect2(Vector2(cell) * CELL, Vector2.ONE * CELL), -1))
	for module: Dictionary in Runtime.military_modules(data, feature):
		var direction: String = ["south", "west", "north", "east"][int(module.quarter)]
		if str(module.kind) == "barracks_dormitory":
			var key := "barracks_chinese_dormitory_" + direction if chinese_camp else building_art_key(module)
			var art := _building_asset(key)
			result.append(_building_structure_draw(module, art, Runtime._cell_bounds(data, module.cells)))
		elif str(module.kind) == "house":
			var house: Dictionary = module.duplicate()
			house.merge({"layout_version": 1, "material": "wood", "level": int(feature.level), "stage": str(feature.stage),
				"owner_faction": int(feature.get("owner_faction", -1)), "solid": true, "entrance": -1})
			if chinese_camp and str(house.variant) == "small":
				var art := _building_asset("barracks_chinese_hq_" + direction)
				result.append(_building_structure_draw(house, art, Runtime._cell_bounds(data, house.cells)))
			else:
				result.append_array(building_part_draws(house))
		else:
			var art := _building_asset("training_station")
			var bounds := Runtime._cell_bounds(data, module.cells)
			var width := 2.0 * CELL - 6.0
			var size := Vector2(width, width * art.region.size.y / art.region.size.x)
			var foot := (Vector2(bounds.position) + Vector2(bounds.size.x * 0.5, bounds.size.y)) * CELL
			result.append(_building_draw(art, Rect2(foot - Vector2(size.x * 0.5, size.y), size), bounds.end.y - 1))
	if str(feature.kind) == "barracks" and int(feature.get("barracks_layout_version", 1)) == 2:
		result.append_array(_building_fence_draws(feature))
		result.append_array(_barracks_gate_frame_draws(feature))
		result.append_array(_barracks_flag_draws(feature))
	return result

func _barracks_entrance_posts(feature: Dictionary) -> Array[Vector2]:
	var bounds := Runtime._cell_bounds(data, feature.cells)
	var entry := data.cell_from_index(int(feature.entrance))
	var inward := Vector2.DOWN if entry.y < bounds.position.y else Vector2.UP
	if entry.x < bounds.position.x: inward = Vector2.RIGHT
	elif entry.x >= bounds.end.x: inward = Vector2.LEFT
	var gate := (Vector2(entry) + Vector2.ONE * 0.5 + inward * 0.5) * CELL
	var tangent := Vector2(-inward.y, inward.x)
	return [gate - tangent * CELL * 0.75, gate + tangent * CELL * 0.75]

# An open entrance marker only: no leaves, wall, navigation or gate state.
func _barracks_gate_frame_draws(feature: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var bounds := Runtime._cell_bounds(data, feature.cells)
	var posts := _barracks_entrance_posts(feature)
	for side: int in range(posts.size()):
		var base: Vector2 = posts[side]
		result.append({"primitive": "barracks_gate_post", "asset_key": "barracks_gate_frame",
			"part_id": "barracks:gate:post:%d" % side, "rect": Rect2(base - Vector2(7, 118), Vector2(14, 120)),
			"row": clampi(floori((base.y - 0.01) / CELL), bounds.position.y, bounds.end.y - 1),
			"foreground": false, "color": Color.WHITE, "base": base})
	var tangent := (posts[1] - posts[0]).normalized()
	var beam_a := posts[0] - Vector2(0, 112) - tangent * 8.0
	var beam_b := posts[1] - Vector2(0, 112) + tangent * 8.0
	result.append({"primitive": "barracks_gate_beam", "asset_key": "barracks_gate_frame", "part_id": "barracks:gate:beam",
		"rect": Rect2(beam_a.min(beam_b) - Vector2.ONE * 6.0, (beam_b - beam_a).abs() + Vector2.ONE * 12.0),
		"row": clampi(floori((maxf(posts[0].y, posts[1].y) - 0.01) / CELL), bounds.position.y, bounds.end.y - 1),
		"foreground": true, "color": Color.WHITE, "beam_a": beam_a, "beam_b": beam_b})
	return result

func _draw_barracks_gate_frame(canvas: Node2D, part: Dictionary) -> void:
	var alpha: float = part.color.a
	if str(part.primitive) == "barracks_gate_post":
		var base: Vector2 = part.base
		var post := Rect2(base - Vector2(5, 112), Vector2(10, 112))
		canvas.draw_rect(post.grow(1.0), Color(Color("413325"), alpha))
		canvas.draw_rect(post, Color(Color("92704a"), alpha))
		canvas.draw_line(post.position + Vector2(2, 1), base + Vector2(-3, -2), Color(Color("c2a276"), alpha), 2.0)
		for height: float in [14.0, 104.0]:
			canvas.draw_rect(Rect2(base - Vector2(6, height), Vector2(12, 3)), Color(Color("5e5446"), alpha))
	else:
		canvas.draw_line(part.beam_a, part.beam_b, Color(Color("413325"), alpha), 12.0, true)
		canvas.draw_line(part.beam_a, part.beam_b, Color(Color("92704a"), alpha), 8.0, true)
		canvas.draw_line(Vector2(part.beam_a) - Vector2(0, 2), Vector2(part.beam_b) - Vector2(0, 2), Color(Color("c2a276"), alpha), 1.5, true)

# These cloth colours are derived presentation, never a second nation record.
func _barracks_flag_draws(feature: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var bounds := Runtime._cell_bounds(data, feature.cells)
	var faction := int(feature.get("owner_faction", -1))
	var palette_id := SiteEquipmentOrders.npc_palette_id(faction) if faction >= 0 else ""
	var colors: Dictionary = Runtime.EquipmentDye.PRESETS[palette_id].colors if not palette_id.is_empty() else {}
	var face := Color(str(colors.get("armor", "8a897fff")))
	var accent := Color(str(colors.get("outfit", "dedbcfff")))
	var bases := {"center": Vector2(bounds.get_center()) * CELL}
	var posts := _barracks_entrance_posts(feature)
	bases["entrance:left"] = posts[0]
	bases["entrance:right"] = posts[1]
	for place: String in bases:
		var base: Vector2 = bases[place]
		var size := Vector2(68, 128) if place == "center" else Vector2(48, 92)
		result.append({"primitive": "barracks_flag", "asset_key": "barracks_flag", "part_id": "flag:" + place,
			"rect": Rect2(base - Vector2(6, size.y + 6), size + Vector2(12, 10)),
			"row": clampi(floori((base.y - 0.01) / CELL), bounds.position.y, bounds.end.y - 1),
			"foreground": false, "color": Color.WHITE, "flag_base": base, "flag_size": size,
			"owner_faction": faction, "palette_id": palette_id, "flag_color": face, "flag_accent": accent,
			"flag_pattern": posmod(floori(float(faction) / 16.0), 4) if faction >= 0 else -1})
	return result

func _draw_barracks_flag(canvas: Node2D, part: Dictionary) -> void:
	var base: Vector2 = part.flag_base
	var size: Vector2 = part.flag_size
	var alpha: float = part.color.a
	var top := base - Vector2(0, size.y)
	canvas.draw_line(base + Vector2(-4, 0), base + Vector2(5, 0), Color(Color("80715a"), alpha), 4.0, true)
	canvas.draw_line(base, top, Color(Color("5a4a36"), alpha), 4.0, true)
	canvas.draw_line(base + Vector2(1, -3), top + Vector2(1, 0), Color(Color("c7b68d"), alpha), 1.0, true)
	canvas.draw_circle(top - Vector2(0, 2), 3.0, Color(Color("c7b68d"), alpha))
	var cloth := Rect2(top + Vector2(3, 5), Vector2(size.x - 7, size.y * 0.31))
	var points := PackedVector2Array([cloth.position, cloth.position + Vector2(cloth.size.x * 0.65, 2),
		cloth.position + Vector2(cloth.size.x, -2), cloth.end - Vector2(cloth.size.x * 0.15, cloth.size.y * 0.45),
		cloth.end, cloth.position + Vector2(0, cloth.size.y)])
	canvas.draw_colored_polygon(points, Color(part.flag_color, alpha))
	canvas.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[4], points[5], points[0]]), Color(Color("342f28"), alpha), 1.0, true)
	var center := cloth.position + cloth.size * Vector2(0.42, 0.5)
	var accent := Color(part.flag_accent, alpha)
	var radius := cloth.size.y * 0.25
	match int(part.flag_pattern):
		0: canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center - Vector2(radius, 0)]), accent)
		1:
			canvas.draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), accent, 4.0, true)
			canvas.draw_line(center - Vector2(0, radius), center + Vector2(0, radius), accent, 4.0, true)
		2:
			for offset: float in [-0.5, 0.5]: canvas.draw_line(center + Vector2(offset * radius, -radius), center + Vector2(offset * radius, radius), accent, 3.0, true)
		3: canvas.draw_circle(center, radius * 0.8, accent)

func building_art_bounds(feature: Dictionary) -> Rect2:
	var result := Rect2()
	for part: Dictionary in building_part_draws(feature):
		result = result.merge(part.rect) if result.has_area() else part.rect
	return result

func _rebuild_building_draws() -> void:
	building_draws_by_row.clear()
	for key: String in data.site.features:
		var feature: Dictionary = data.site.features[key]
		for part: Dictionary in building_part_draws(feature):
			part["feature_key"] = key
			if not building_draws_by_row.has(int(part.row)): building_draws_by_row[int(part.row)] = []
			building_draws_by_row[int(part.row)].append(part)

func _building_on_row(row: int) -> bool:
	if building_draws_by_row.has(row): return true
	for part: Dictionary in _building_preview_draws:
		if int(part.row) == row: return true
	for key: String in features_by_row.get(row, []):
		if _building_uses_art(data.site.features[key]): return true
	return false

func _install_building_runs(parent: Node2D, row: int) -> void:
	if not _building_on_row(row): return
	for foreground: bool in [false, true]:
		var run := BuildingRun.new()
		run.name = "BuildingForeground" if foreground else "BuildingArt"
		run.view = self
		run.row = row
		run.foreground = foreground
		run.use_parent_material = false
		run.z_index = 1 if foreground else 0 # Exterior rails cover the feet of actors on this row.
		parent.add_child(run)

func set_building_preview(value: Dictionary) -> void:
	var signature := value.hash()
	if signature == _building_preview_signature and value == building_preview: return
	var changed := {}
	for part: Dictionary in _building_preview_draws: changed[int(part.row)] = true
	building_preview = value.duplicate(true)
	_building_preview_signature = signature
	_building_preview_draws.clear()
	if not value.is_empty():
		_building_preview_draws = building_part_draws(value.feature, value.get("geometry", {}))
		for part: Dictionary in _building_preview_draws: changed[int(part.row)] = true
	if is_instance_valid(_building_ground): _building_ground.queue_redraw()
	for row: int in changed:
		if row >= 0 and row < rows.size(): rows[row].rebuild()
	queue_redraw()

func _draw_buildings(canvas: Node2D, row: int, foreground: bool) -> void:
	if data == null: return
	var draws: Array = building_draws_by_row.get(row, []).duplicate()
	for part: Dictionary in _building_preview_draws:
		if int(part.row) == row: draws.append(part)
	for part: Dictionary in draws:
		if bool(part.foreground) == foreground:
			if str(part.get("primitive", "")) == "fire_component": _draw_fire_component(canvas, part)
			elif str(part.get("primitive", "")) == "bridge": _draw_bridge_deck(canvas, part)
			elif str(part.get("primitive", "")) == "barracks_flag": _draw_barracks_flag(canvas, part)
			elif str(part.get("primitive", "")).begins_with("barracks_gate_"): _draw_barracks_gate_frame(canvas, part)
			else: canvas.draw_texture_rect_region(part.texture, part.rect, part.region, part.color)
	if foreground or row < 0: return
	for key: String in features_by_row.get(row, []):
		var feature: Dictionary = data.site.features[key]
		if not _building_uses_art(feature): continue
		var bounds := Runtime._cell_bounds(data, feature.cells)
		if row != bounds.end.y - 1: continue
		var p := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, bounds.end.y) * CELL
		var label := str(Runtime.FEATURES[str(feature.kind)].name)
		if feature.has("technology_siege_yard"):
			var yard_work := Runtime.technology_siege_yard_context(data, key)
			label += "·器械場·六施工位" + ("·停效：" + str(yard_work.get("message", "")) if not yard_work.ok else "")
		if str(feature.get("kind", "")) == "settlement_center": label += "·%s%s" % [("%d級%s" % [int(data.site.get("settlement", {}).get("level", 0)), str(Runtime.SETTLEMENT_LEVEL_NAMES.get(int(data.site.get("settlement", {}).get("level", 0)), ""))]) if int(data.site.get("settlement", {}).get("level", 0)) > 0 else "籌建", "·毀損停效" if not Runtime.feature_usable(feature) else ""]
		elif int(feature.get("civil_version", 0)) == Runtime.CIVIL_VERSION: label += "·%d級%s" % [Runtime.building_grade(feature), "·毀損" if not Runtime.feature_usable(feature) else ""]
		if str(feature.stage) != "complete": label += "·施工"
		canvas.draw_string(ThemeDB.fallback_font, p + Vector2(-30, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("fff0c8"))
		if feature.has("pending_build"):
			for index: int in feature.pending_build.added_cells:
				canvas.draw_rect(Rect2(Vector2(data.cell_from_index(index)) * CELL, Vector2.ONE * CELL).grow(-3), Color(1.0, 0.83, 0.45, 0.4), false, 3.0)
		if str(feature.kind) in ["pasture", "horse_ranch"] and str(feature.stage) == "complete":
			for n: int in range(int(feature.get("residents", 0))):
				var animal := p + Vector2(float(n % 6) * 20.0 - 50.0, -16.0 - floorf(float(n) / 6.0) * 18.0)
				_draw_wildlife(canvas, animal, 0.0, int(_resource_art._wildlife_indices[str(feature.species)]), 38.0 if str(feature.kind) == "pasture" else 46.0)


func _building_fence_draws(feature: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var bounds := Runtime._cell_bounds(data, feature.cells)
	var entrance := data.cell_from_index(int(feature.entrance))
	# Barracks rails are low, separated boundary markers: the original runtime
	# keeps these edges walkable, so the artwork must not suggest a solid wall.
	var low_rails := str(feature.kind) == "barracks"
	for x: int in range(bounds.position.x, bounds.end.x):
		for y: int in [bounds.position.y, bounds.end.y]:
			if entrance == Vector2i(x, y - 1 if y == bounds.position.y else y): continue
			var art := _building_asset("pasture_fence_h")
			var size := Vector2(CELL, CELL * art.region.size.y / art.region.size.x)
			if low_rails: size = Vector2(CELL * 0.5, 18.0)
			var offset := Vector2((CELL - size.x) * 0.5, -size.y)
			result.append(_building_draw(art, Rect2(Vector2(x, y) * CELL + offset, size), y if y == bounds.position.y else y - 1,
				"barracks:fence:%d:%d:h" % [x, y] if low_rails else ""))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in [bounds.position.x, bounds.end.x]:
			if entrance == Vector2i(x - 1 if x == bounds.position.x else x, y): continue
			var art := _building_asset("pasture_fence_v")
			var size := Vector2(CELL * art.region.size.x / art.region.size.y, CELL)
			if low_rails: size = Vector2(8.0, CELL * 0.5)
			var offset := Vector2(-size.x * 0.5, (CELL - size.y) * 0.5)
			result.append(_building_draw(art, Rect2(Vector2(x, y) * CELL + offset, size), y,
				"barracks:fence:%d:%d:v" % [x, y] if low_rails else ""))
	return result

func _building_wall_draws(_feature: Dictionary, geometry: Dictionary, key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in geometry.parts:
		var state: Dictionary = geometry.parts[id]
		var index := int(state.cells[0])
		var cell := data.cell_from_index(index)
		var rise := float(int(state.height) - int(data.height_levels[index])) * 48.0
		var origin := Vector2(cell) * CELL - Vector2(0, rise)
		if float(state.hp) <= 0.0:
			var rubble := _building_draw(_building_asset(key, "body"), Rect2(Vector2(cell) * CELL + Vector2(0, 40), Vector2(CELL, 24)), cell.y, id)
			rubble["state"] = "destroyed"
			rubble.color = Color(0.58, 0.55, 0.51)
			result.append(rubble)
			continue
		var connected := {}
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not data.contains(next): continue
			var next_index := data.index(next)
			var own: Dictionary = geometry.parts.get("c:%d" % next_index, {})
			if not own.is_empty():
				connected[direction] = float(own.hp) > 0.0 and int(own.height) == int(state.height)
			elif int(data.feature_at[next_index]) != 0:
				var adjacent: Dictionary = data.site.features[str(data.feature_at[next_index])]
				if str(adjacent.stage) == "complete" and str(adjacent.kind) in ["palisade", "stone_wall", "wall_stairs"]:
					connected[direction] = data.effective_height(next) == int(state.height)
		for component: String in ["floor", "body", "rear", "left", "right", "front"]:
			var edge: Vector2i = {"body": Vector2i.DOWN, "rear": Vector2i.UP, "front": Vector2i.DOWN, "left": Vector2i.LEFT, "right": Vector2i.RIGHT}.get(component, Vector2i.ZERO)
			if component != "floor" and bool(connected.get(edge, false)): continue
			var art := _building_asset(key, component)
			var size := _building_sprite_size(art)
			var part_position := origin
			match component:
				"body": part_position.y += CELL
				"rear": part_position.y -= size.y * 0.5
				"front": part_position.y += CELL - size.y * 0.5
				"left": part_position.x -= size.x * 0.5
				"right": part_position.x += CELL - size.x * 0.5
			var part := _building_draw(art, Rect2(part_position, size), cell.y, id, component in ["front", "left", "right"])
			part["cell"] = cell
			part["elevation"] = rise
			part["state"] = str(state.state)
			if str(state.state) == "damaged": part.color = Color(0.77, 0.70, 0.61)
			result.append(part)
	return result

func _building_anchor(sprite: Dictionary, field: String = "ground_anchor") -> Vector2:
	var value: Array = sprite.get(field, sprite.get("ground_anchor", [0.5, 1.0]))
	return Vector2(float(value[0]), float(value[1]))

func _building_stair_draws(feature: Dictionary, geometry: Dictionary, key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lower: Vector2i = geometry.stair_lower.cell
	var upper: Vector2i = geometry.stair_upper.cell
	var lower_id := "c:%d" % data.index(lower)
	var upper_id := "c:%d" % data.index(upper)
	var lower_state: Dictionary = geometry.parts[lower_id]
	var upper_state: Dictionary = geometry.parts[upper_id]
	var lower_alive := float(lower_state.hp) > 0.0
	var upper_alive := float(upper_state.hp) > 0.0
	var low_point := (Vector2(geometry.external_lower.cell) + Vector2.ONE * 0.5) * CELL
	var rise := float(int(geometry.stair_upper.height) - int(feature.level)) * 48.0
	var high_point := (Vector2(upper) + Vector2.ONE * 0.5) * CELL - Vector2(0, rise)
	var floor_row := mini(lower.y, upper.y)
	if not lower_alive or not upper_alive:
		var destroyed := _building_asset(key, "destroyed_flight")
		var size := _building_sprite_size(destroyed)
		for cell: Vector2i in [lower, upper]:
			if cell == lower and lower_alive or cell == upper and upper_alive: continue
			var foot := (Vector2(cell) + Vector2.ONE * 0.5) * CELL
			var draw_entry := _building_draw(destroyed, Rect2(foot - size * _building_anchor(destroyed), size), cell.y, "c:%d" % data.index(cell))
			draw_entry["state"] = "destroyed"
			result.append(draw_entry)
		if not lower_alive and not upper_alive: return result
	var landing := _building_asset(key, "damaged_landing" if str(upper_state.state) == "damaged" else "landing")
	var landing_base := _building_asset(key, "landing")
	var landing_size := _building_sprite_size(landing)
	var walk_anchor := _building_anchor(landing, "walk_anchor") if landing.has("walk_anchor") else _building_anchor(landing_base, "walk_anchor")
	var landing_rect := Rect2(high_point - landing_size * walk_anchor, landing_size)
	var support := _building_asset(key, "support")
	var support_size := _building_sprite_size(support)
	var support_ground := _building_anchor(support)
	var support_upper := _building_anchor(support, "floor_upper_anchor")
	support_size.y = rise / (support_ground.y - support_upper.y)
	var support_point := landing_rect.position + landing_size * _building_anchor(landing)
	if upper_alive: result.append(_building_draw(support, Rect2(support_point - support_size * support_upper, support_size), floor_row, upper_id))
	var flight := _building_asset(key, "damaged_flight" if str(lower_state.state) == "damaged" else "flight")
	var flight_base := _building_asset(key, "flight")
	var toe := _building_anchor(flight_base, "toe_ground_anchor")
	var high := _building_anchor(flight_base, "high_exit_anchor")
	var delta := high_point - low_point
	var source_delta := high - toe
	var flight_size := _building_sprite_size(flight)
	if absf(source_delta.x) > 0.01: flight_size.x = delta.x / source_delta.x
	if absf(source_delta.y) > 0.01: flight_size.y = delta.y / source_delta.y
	assert(flight_size.x > 0.0 and flight_size.y > 0.0, "Stair artwork must face its real navigable upper cell")
	var flight_draw := _building_draw(flight, Rect2(low_point - flight_size * toe, flight_size), floor_row, lower_id)
	flight_draw["toe"] = low_point
	flight_draw["high_exit"] = high_point
	flight_draw["state"] = str(lower_state.state)
	if lower_alive and upper_alive:
		result.append(flight_draw)
	else:
		# A broken lower flight cannot erase a surviving upper landing (and vice versa).
		var middle := (toe + high) * 0.5
		var start := Vector2.ZERO
		var end := Vector2.ONE
		if int(feature.quarter) % 2:
			if (high.x > toe.x) == upper_alive: start.x = middle.x
			else: end.x = middle.x
		else:
			if (high.y > toe.y) == upper_alive: start.y = middle.y
			else: end.y = middle.y
		var surviving := _building_crop(flight_draw, start, end)
		surviving.part_id = upper_id if upper_alive else lower_id
		result.append(surviving)
	var landing_draw := _building_draw(landing, landing_rect, floor_row, upper_id)
	landing_draw["walk_foot"] = high_point
	landing_draw["state"] = str(upper_state.state)
	if upper_alive: result.append(landing_draw)
	var foreground := _building_crop(landing_draw, Vector2(0, float(landing_base.get("foreground_fraction", 0.7))), Vector2.ONE)
	foreground.foreground = true
	foreground.row = upper.y
	if upper_alive: result.append(foreground)
	return result

func _building_gate_draws(feature: Dictionary, geometry: Dictionary, key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var bounds := Runtime._cell_bounds(data, feature.cells)
	var quarter := int(feature.get("quarter", 0))
	var near := _building_local_point(feature, Vector2.ZERO)
	var far := near
	for corner: Vector2 in [Vector2(4, 0), Vector2(0, 2), Vector2(4, 2)]:
		var point := _building_local_point(feature, corner)
		near = near.min(point)
		far = far.max(point)
	# The frame front-post anchor meets the last artwork row's cell centre.
	# The far tile edge is half a cell beyond that ground contact.
	var foot := Vector2((near.x + far.x) * 0.5, far.y - CELL * 0.5)
	var row := clampi(floori(far.y / CELL - 0.01), bounds.position.y, bounds.end.y - 1)
	var closed := _building_asset(key, "closed")
	var closed_size := _building_sprite_size(closed)
	var closed_rect := Rect2(foot - closed_size * _building_anchor(closed), closed_size)
	var seam: float = [0.5, 0.30, 0.5, 0.70][quarter]
	var split_x := closed_rect.position.x + closed_size.x * seam
	for side: int in range(2):
		var suffix := "left" if side == 0 else "right"
		var frame: Dictionary = geometry.parts["frame:" + suffix]
		var leaf: Dictionary = geometry.parts["leaf:" + suffix]
		var component := "open" if bool(feature.get("gate", {}).get("open", false)) else "closed"
		if float(leaf.hp) < float(leaf.max_hp) and component == "closed": component = "damaged_leaf"
		if float(leaf.hp) <= 0.0: component = "broken_leaf"
		if float(frame.hp) <= 0.0: component = "ruined_frame"
		var art := _building_asset(key, component)
		var size := _building_sprite_size(art)
		var draw_entry := _building_draw(art, Rect2(foot - size * _building_anchor(art), size), row, "leaf:" + suffix)
		if component == "ruined_frame":
			# Rubble's centre anchor differs from the standing frame's front-post anchor.
			draw_entry.rect.position.x = closed_rect.get_center().x - size.x * 0.5
		var screen_side := 1 - side if quarter == 2 else side
		var fraction := clampf((split_x - float(draw_entry.rect.position.x)) / size.x, 0.0, 1.0)
		draw_entry = _building_crop(draw_entry, Vector2(0.0 if screen_side == 0 else fraction, 0), Vector2(fraction if screen_side == 0 else 1.0, 1))
		draw_entry["frame_part_id"] = "frame:" + suffix
		draw_entry["state"] = str(leaf.state)
		draw_entry["frame_state"] = str(frame.state)
		if str(frame.state) == "damaged": draw_entry.color = Color(0.70, 0.65, 0.58)
		result.append(draw_entry)
		if float(frame.hp) <= 0.0: continue
		var top := _building_asset(key, "top")
		var top_size := _building_sprite_size(top)
		# The measured art cap joins its own frame; it does not create a walkable level.
		var cap_rise := _building_sprite_size(closed).y * (_building_anchor(closed).y - _building_anchor(closed, "floor_upper_anchor").y)
		var cap := _building_draw(top, Rect2(foot - Vector2(0, cap_rise) - top_size * _building_anchor(top), top_size), row, "frame:" + suffix, true)
		fraction = clampf((split_x - float(cap.rect.position.x)) / top_size.x, 0.0, 1.0)
		cap = _building_crop(cap, Vector2(0.0 if screen_side == 0 else fraction, 0), Vector2(fraction if screen_side == 0 else 1.0, 1))
		cap["state"] = str(frame.state)
		if str(frame.state) == "damaged": cap.color = Color(0.70, 0.65, 0.58)
		result.append(cap)
	return result

func _draw_feature(canvas: Node2D, feature: Dictionary, row_index: int = -1) -> void:
	if str(feature.kind) == "siege_ladder": return # Original VehicleView shows the generated ladder sprite.
	if _building_uses_art(feature): return
	if feature.get("kind") == "irrigation_channel": _draw_irrigation_channel(canvas, feature, row_index); return
	var kind := str(feature.kind)
	var complete := str(feature.stage) == "complete"
	var min_cell := data.cell_from_index(int(feature.cells[0]))
	var max_cell := min_cell
	for i: int in feature.cells:
		var cell := data.cell_from_index(i)
		min_cell = min_cell.min(cell)
		max_cell = max_cell.max(cell)
		if complete and kind == "palisade":
			if row_index < 0 or cell.y == row_index:
				_draw_defense_cell(canvas, _center(i), true)
			continue
		if complete and kind == "fighting_position":
			continue # Drawn on the ground in _draw, below the occupying actor.
		if complete and (kind in ["house", "well"] or kind.contains("farm")):
			continue
		if complete and kind == "warehouse" and row_index >= 0 and cell.y != row_index: continue
		var rect := Rect2(Vector2(cell) * CELL, Vector2.ONE * CELL)
		var color := Color("856542") if kind.contains("farm") else Color("789158")
		if kind == "warehouse": color = Color("8b7355")
		if kind == "road":
			color = Color("bb9d6c")
		color.a = 0.72 if complete else 0.2
		var batcher: TriangleBatcher = (canvas.get_meta(&"batcher") as TriangleBatcher) if canvas.has_meta(&"batcher") else null
		if batcher != null:
			batcher.add_rect(rect.grow(-3), color)
			batcher.add_rect_outline(rect.grow(-3), Color("d9bd80"), 2.0)
		else:
			canvas.draw_rect(rect.grow(-3), color)
			canvas.draw_rect(rect.grow(-3), Color("d9bd80"), false, 2.0)
	if complete and kind == "warehouse":
		var ruined := float(feature.get("parts", {}).get("body", {}).get("hp", 1.0)) <= 0.0
		for index: int in feature.cells:
			if row_index >= 0 and data.cell_from_index(index).y != row_index: continue
			var foot := _center(index) + Vector2(0, 22)
			if not ruined: _draw_prop(canvas, "chest", foot, 40.0, _civil_building_tint(feature))
			else: _draw_thick_line(canvas, foot + Vector2(-18, -8), foot + Vector2(18, 0), Color("756353"), 6.0)
	if kind in ["palisade", "warehouse"] and row_index >= 0 and row_index != max_cell.y:
		return # One label/scaffold per feature; stakes use their actual ground row.
	var p := Vector2(float(min_cell.x + max_cell.x + 1) * CELL * 0.5, float(max_cell.y + 1) * CELL - 12)
	if not complete:
		for offset: Vector2 in [Vector2(-20, 0), Vector2(20, 0)]:
			_draw_thick_line(canvas, p + offset, p + offset + Vector2(0, -45), Color("c59c65"), 4.0)
		_draw_thick_line(canvas, p + Vector2(-24, -32), p + Vector2(24, -32), Color("ccad7b"), 4.0)
	elif kind == "warehouse":
		pass # Original camp crates were drawn on each actual cell row above.
	elif kind == "house":
		_draw_prop(canvas, "house", p + Vector2(0, 4), float(max_cell.x - min_cell.x + 1) * CELL - 6)
	elif kind == "well":
		if Runtime.feature_usable(feature): _draw_prop(canvas, "well", p + Vector2(0, 2), 52.0, _civil_building_tint(feature))
	elif kind == "intake":
		_oval(canvas, p, Vector2(22, 14), Color("a5a58f"))
		_oval(canvas, p + Vector2(0, -5), Vector2(15, 8), Color("3a5656"))
		_draw_thick_line(canvas, p + Vector2(-22, 0), p + Vector2(-22, -47), Color("896945"), 5.0)
		_draw_thick_line(canvas, p + Vector2(22, 0), p + Vector2(22, -47), Color("896945"), 5.0)
		_draw_thick_line(canvas, p + Vector2(-24, -46), p + Vector2(24, -46), Color("c0a675"), 5.0)
		_draw_thick_line(canvas, p + Vector2(0, -46), p + Vector2(0, -12), Color("cfbc87"), 2.0)
	elif kind in ["palisade", "fighting_position"]:
		pass # Per-cell defensive art above; never use the generic workshop house.
	elif bool(feature.solid):
		var width := minf(96.0, float(max_cell.x - min_cell.x + 1) * CELL - 8)
		var batcher: TriangleBatcher = (canvas.get_meta(&"batcher") as TriangleBatcher) if canvas.has_meta(&"batcher") else null
		if batcher != null:
			batcher.add_rect(Rect2(p + Vector2(-width * 0.5, -49), Vector2(width, 49)), Color("af966f"))
			batcher.add_rect(Rect2(p + Vector2(-9, -27), Vector2(18, 27)), Color("574737"))
		else:
			canvas.draw_rect(Rect2(p + Vector2(-width * 0.5, -49), Vector2(width, 49)), Color("af966f"))
			canvas.draw_rect(Rect2(p + Vector2(-9, -27), Vector2(18, 27)), Color("574737"))
		_draw_polygon(canvas, PackedVector2Array([p + Vector2(-width * 0.5 - 7, -46), p + Vector2(0, -80), p + Vector2(width * 0.5 + 7, -46)]), Color("745a42") if kind == "house" else Color("80685a"))
		_draw_thick_line(canvas, p + Vector2(-width * 0.5 - 7, -46), p + Vector2(0, -80), Color("c8ab77"), 3.0)
		if kind in ["kiln", "smelter", "smithy", "charcoal"]:
			if batcher != null:
				batcher.add_rect(Rect2(p + Vector2(15, -82), Vector2(13, 31)), Color("8e8b79"))
			else:
				canvas.draw_rect(Rect2(p + Vector2(15, -82), Vector2(13, 31)), Color("8e8b79"))
			_oval(canvas, p + Vector2(21, -95), Vector2(10, 8), Color(0.8, 0.8, 0.74, 0.35))
	elif kind in ["pasture", "horse_ranch"]:
		for n: int in range(int(feature.get("residents", 1))):
			var animal := p + Vector2(n * 22 - 8, -10)
			_draw_wildlife(canvas, animal, 0.0, int(_resource_art._wildlife_indices[str(feature.species)]), 38.0 if kind == "pasture" else 46.0)
	var label := str(Runtime.FEATURES[kind].name) + ("" if complete else "·施工")
	_draw_string(canvas, ThemeDB.fallback_font, p + Vector2(-30, 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("fff0c8"))

func _draw_irrigation_channel(canvas: Node2D, feature: Dictionary, row_index: int) -> void:
	var live := false
	for key: String in data.site.features:
		if is_same(data.site.features[key], feature): live = Runtime.irrigation_channel_flow(data, key).ok; break
	var broken := float(feature.get("parts", {}).get("body", {}).get("hp", 100.0)) <= 0.0
	var complete: bool = feature.get("stage") == "complete"
	var color := Color("467f9a") if live else Color("756653")
	if not complete: color.a = 0.4
	# Half-edges belong to the original cell's actual painter row. This renders
	# bends and each row once; no bounding-rectangle water/placeholder house.
	for index: int in feature.cells.size():
		var cell := int(feature.cells[index])
		if row_index >= 0 and data.cell_from_index(cell).y != row_index: continue
		var center := _center(cell)
		var ends: Array[Vector2] = []
		if index > 0: ends.append((_center(int(feature.cells[index - 1])) + center) * 0.5)
		if index + 1 < feature.cells.size(): ends.append((_center(int(feature.cells[index + 1])) + center) * 0.5)
		if ends.is_empty(): ends = [center + Vector2(-CELL * 0.25, 0), center + Vector2(CELL * 0.25, 0)]
		for endpoint: Vector2 in ends:
			_draw_thick_line(canvas, center, endpoint, Color("b2a28b"), 15.0)
			_draw_thick_line(canvas, center, endpoint, color, 8.0)
		if broken: _draw_thick_line(canvas, center + Vector2(-10, -10), center + Vector2(10, 10), Color("a46e50"), 4.0)

# Engineering component presentation through the original row draw records.
# The approved intact artwork remains the source for existing whole sprites;
# these bounded primitives make destroyed/supporting parts legible without
# claiming a pixel-aligned roof mask for artwork that has no component mask.
func _fire_component_presentation(feature: Dictionary, geometry: Dictionary) -> bool:
	if int(feature.get("fire_layout_version", 0)) != Runtime.FIRE_LAYOUT_VERSION: return false
	if str(feature.kind) == "warehouse": return true
	for part: Dictionary in geometry.parts.values():
		if float(part.hp) < float(part.max_hp): return true
	return false

func _fire_component_draws(_feature: Dictionary, geometry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var names: Array = geometry.parts.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return float(geometry.parts[a].lower) < float(geometry.parts[b].lower) if float(geometry.parts[a].lower) != float(geometry.parts[b].lower) else a < b)
	for identity: String in names:
		var part: Dictionary = geometry.parts[identity]
		var fraction := clampf(float(part.hp) / maxf(1.0, float(part.max_hp)), 0.0, 1.0)
		var mat := str(part.material)
		var color := Color("8c9295") if mat == "stone" else Color("886444")
		color = color.lerp(Color("3b302a"), (1.0 - fraction) * 0.75)
		for index: int in part.cells:
			var cell := data.cell_from_index(index)
			var origin := Vector2(cell) * CELL
			var lower := (float(part.lower) - float(data.height_levels[index])) * 48.0
			var upper := (float(part.upper) - float(data.height_levels[index])) * 48.0
			var rect := Rect2(origin + Vector2(3, -upper + 3), Vector2(CELL - 6, CELL + upper - lower - 6))
			if fraction <= 0.0: rect = Rect2(origin + Vector2(6, 40), Vector2(CELL - 12, 18))
			result.append({"primitive": "fire_component", "rect": rect, "row": -1 if fraction <= 0.0 else cell.y,
				"part_id": identity, "foreground": false, "color": color, "role": str(part.role), "material": mat,
				"state": "destroyed" if fraction <= 0.0 else "damaged" if fraction < 1.0 else "intact", "fraction": fraction,
				"top": Rect2(origin + Vector2(3, -upper + 3), Vector2(CELL - 6, CELL - 6)), "height": upper - lower})
	return result

func _draw_fire_component(canvas: Node2D, part: Dictionary) -> void:
	var rect: Rect2 = part.rect
	var color: Color = part.color
	if str(part.state) == "destroyed":
		for i: int in range(3):
			var rubble := Rect2(rect.position + Vector2(i * rect.size.x / 3.0, (i % 2) * 4.0), Vector2(rect.size.x / 3.0 - 2.0, 10.0))
			canvas.draw_rect(rubble, color)
			canvas.draw_rect(rubble, Color("2a2522"), false, 1.0)
		return
	var top: Rect2 = part.top
	var front := Rect2(top.position + Vector2(0, top.size.y), Vector2(top.size.x, float(part.height)))
	canvas.draw_rect(front, color.darkened(0.3))
	canvas.draw_rect(front, Color("30291f"), false, 1.5)
	if str(part.role) == "roof":
		var ridge := top.position + Vector2(top.size.x * 0.5, 0)
		canvas.draw_colored_polygon(PackedVector2Array([top.position, ridge, ridge + Vector2(0, top.size.y), top.position + Vector2(0, top.size.y)]), color.lightened(0.12))
		canvas.draw_colored_polygon(PackedVector2Array([ridge, top.position + Vector2(top.size.x, 0), top.end, ridge + Vector2(0, top.size.y)]), color.darkened(0.1))
		canvas.draw_line(ridge, ridge + Vector2(0, top.size.y), Color("3e2b20"), 2.0)
	else:
		canvas.draw_rect(top, color.lightened(0.12))
		if str(part.material) == "stone":
			canvas.draw_line(front.position + Vector2(0, front.size.y * 0.5), front.position + Vector2(front.size.x, front.size.y * 0.5), Color("565b60"), 1.0)
	canvas.draw_rect(top, Color("30291f"), false, 1.5)
	if float(part.fraction) < 1.0:
		var crack := front.position + Vector2(front.size.x * 0.4, 0)
		canvas.draw_polyline(PackedVector2Array([crack, crack + Vector2(7, front.size.y * 0.45), crack + Vector2(2, front.size.y)]), Color("201a16"), 2.0)
