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
	func rebuild() -> void:
		for child in get_children():
			remove_child(child)
			child.queue_free()
		animated_runs.clear()
		queue_redraw()
		if not view.retain_static_rows: return
		# Retain contiguous runs in the ORIGINAL painter order. Putting all
		# animated props above static props would break overlapping silhouettes.
		var run: ResourceRun
		var was_animated := false
		for key: String in view.resources_by_row.get(row, []):
			var animated: bool = int(view.data.resource_base[key].kind) in [Env.Kind.WILDLIFE, Env.Kind.FISH]
			if run == null or animated != was_animated:
				run = ResourceRun.new()
				run.view = view
				run.row = row
				run.use_parent_material = true
				add_child(run)
				if animated: animated_runs.append(run)
				was_animated = animated
			run.keys.append(key)
		var features := ResourceRun.new()
		features.view = view
		features.row = row
		features.decorations = true
		features.use_parent_material = true
		add_child(features)

func _ready() -> void:
	var prop_material := ShaderMaterial.new()
	prop_material.shader = PROP_SHADER
	material = prop_material
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func display(value: TerrainData) -> void:
	data = value
	for row: Node2D in rows:
		remove_child(row)
		row.queue_free()
	rows.clear()
	for y: int in range(data.size.y):
		var row := ResourceRow.new()
		row.name = "ResourceRow%d" % y
		row.view = self
		row.row = y
		row.z_index = 10 + y
		row.use_parent_material = true
		add_child(row)
		rows.append(row)
	_seen_revision = -1
	loot_cells_by_row.clear()
	for cell: int in data.ground_loot_at:
		data.ground_loot_dirty_rows[data.cell_from_index(cell).y] = true
	refresh()

func refresh() -> void:
	if data == null or data.site.is_empty():
		return
	resources_by_row.clear()
	features_by_row.clear()
	for key: String in data.resource_base:
		var resource_rows: Array[int] = [data.cell_from_index(int(data.resource_base[key].cell)).y]
		if int(data.resource_base[key].kind) == Env.Kind.WILDLIFE:
			for i: int in data.resource_base[key].cells:
				var row := data.cell_from_index(i).y
				if not resource_rows.has(row):
					resource_rows.append(row)
		for row: int in resource_rows:
			if not resources_by_row.has(row):
				resources_by_row[row] = []
			resources_by_row[row].append(key)
	for key: String in data.site.features:
		var row := 0
		var feature_rows: Array[int] = []
		for i: int in data.site.features[key].cells:
			row = maxi(row, data.cell_from_index(i).y)
			if str(data.site.features[key].kind) == "palisade" and str(data.site.features[key].stage) == "complete" and not feature_rows.has(data.cell_from_index(i).y):
				feature_rows.append(data.cell_from_index(i).y)
		if feature_rows.is_empty():
			feature_rows.append(row)
		for feature_row: int in feature_rows:
			if not features_by_row.has(feature_row):
				features_by_row[feature_row] = []
			features_by_row[feature_row].append(key)
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
	for row: Node2D in rows:
		row.rebuild()

func animate(delta: float) -> void:
	if data == null:
		return
	for row: int in data.ground_loot_dirty_rows:
		var cells: Array[int] = []
		for x in range(data.size.x):
			var cell := data.index(Vector2i(x, row))
			if data.ground_loot_at.has(cell):
				cells.append(cell)
		loot_cells_by_row[row] = cells
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
	if data == null:
		return
	# Walkable crop beds and low defensive positions stay below their occupants.
	for feature: Dictionary in data.site.features.values():
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

func draw_row(canvas: Node2D, row_index: int) -> void:
	if data == null:
		return
	_draw_row_loot(canvas, row_index)
	_draw_row_resources(canvas, row_index, resources_by_row.get(row_index, []))
	_draw_row_features(canvas, row_index)

func _draw_row_loot(canvas: Node2D, row_index: int) -> void:
	for cell: int in loot_cells_by_row.get(row_index, []):
		var point := _center(cell) + Vector2(20, 12)
		canvas.draw_rect(Rect2(point - Vector2(8, 5), Vector2(16, 10)), Color("d2b36c"))
		canvas.draw_line(point + Vector2(-8, -1), point + Vector2(8, -1), Color("624e31"), 2)
		var count: int = data.ground_loot_at.get(cell, []).size()
		if count > 1:
			canvas.draw_string(ThemeDB.fallback_font, point + Vector2(8, 1), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("fff0bd"))
func _draw_row_resources(canvas: Node2D, row_index: int, keys: Array) -> void:
	for key: String in keys:
		var r := Env.resource(data, key)
		if bool(r.cleared):
			continue
		var feature_key := str(data.feature_at[int(r.cell)])
		if feature_key != "0" and str(data.site.features[feature_key].stage) == "complete":
			if int(r.kind) not in [Env.Kind.CLAY, Env.Kind.IRON] or view_mode != 1:
				continue
		if view_mode == 1 and resource_filter >= 0 and int(r.kind) != resource_filter:
			continue
		var p := _center(int(r.cell))
		if int(r.kind) == Env.Kind.WILDLIFE:
			for n: int in range(mini(int(r.remaining), r.cells.size())):
				var i: int = r.cells[n]
				if data.cell_from_index(i).y != row_index or not data.is_walkable(data.cell_from_index(i)) or data.feature_at[i] != 0:
					continue
				var phase := animation_time * 0.8 + float(n * 2 + int(r.cell) % 11)
				var animal_position := _center(i) + Vector2(sin(phase) * 9, cos(phase * 0.7) * 5)
				_draw_animal(canvas, animal_position, phase, int(r.variant))
			if row_index != data.cell_from_index(int(r.cell)).y:
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
					_oval(canvas, p, Vector2(27, 18), Color("855d44"))
					_oval(canvas, p + Vector2(-4, -4), Vector2(22, 13), Color("c88c63"))
					canvas.draw_polyline(PackedVector2Array([p + Vector2(-18, 2), p + Vector2(-2, 8), p + Vector2(17, -2)]), Color("e4b791"), 2.0)
				Env.Kind.IRON:
					_draw_rock(canvas, p, Color("676963"), true)
				Env.Kind.SALT:
					_oval(canvas, p, Vector2(26, 16), Color(0.84, 0.91, 0.86, 0.45))
					for offset: Vector2 in [Vector2(-10, -3), Vector2(7, 4), Vector2(14, -6)]:
						canvas.draw_polyline(PackedVector2Array([p + offset + Vector2(-5, 0), p + offset + Vector2(0, -5), p + offset + Vector2(7, 0)]), Color("ece6c9"), 2.0)
				Env.Kind.FOOD, Env.Kind.HERB:
					_draw_plant(canvas, p, int(r.kind) == Env.Kind.HERB)
				Env.Kind.FISH:
					for n: int in range(mini(3, int(r.remaining))):
						var offset := Vector2(sin(animation_time * 0.7 + n * 2.0) * 12.0, float(n - 1) * 10)
						_draw_fish(canvas, p + offset)
				Env.Kind.WILDLIFE:
					pass # Drawn at each animal's ground row above.
		if view_mode == 1 or key == selected_resource:
			var color: Color = Env.COLORS[int(r.kind)]
			canvas.draw_arc(p, 29, 0, TAU, 24, color.lightened(0.25), 2.5)
			var label := str(Env.NAMES[int(r.kind)])
			if key == selected_resource:
				label += " %s" % (str(int(r.remaining)) if bool(r.discovered) else "待勘探")
			canvas.draw_string(ThemeDB.fallback_font, p + Vector2(-28, 40), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff4d8"))
func _draw_row_features(canvas: Node2D, row_index: int) -> void:
	for key: String in features_by_row.get(row_index, []):
		_draw_feature(canvas, data.site.features[key], row_index)
	if data.cell_from_index(int(data.site.depot_cell)).y == row_index:
		var depot := _center(int(data.site.depot_cell))
		_draw_prop(canvas, "chest", depot + Vector2(0, 15), 40.0)
		canvas.draw_string(ThemeDB.fallback_font, depot + Vector2(-30, 38), "營地箱", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff0cc"))

func _draw_prop(canvas: Node2D, kind: String, foot: Vector2, width: float) -> void:
	var region: Rect2 = PROP_REGIONS[kind]
	var size := Vector2(width, width * region.size.y / region.size.x)
	canvas.draw_texture_rect_region(PROPS, Rect2(foot - Vector2(size.x * 0.5, size.y), size), region)

func _center(i: int) -> Vector2:
	return (Vector2(data.cell_from_index(i)) + Vector2.ONE * 0.5) * CELL

func _oval(canvas: Node2D, p: Vector2, radius: Vector2, color: Color) -> void:
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

func _draw_tree(canvas: Node2D, p: Vector2, variant: int) -> void:
	_oval(canvas, p + Vector2(7, 6), Vector2(32, 13), Color(0.06, 0.14, 0.09, 0.3))
	canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(-8, 5), p + Vector2(-5, -52), p + Vector2(5, -52), p + Vector2(9, 5)]), Color("654d37"))
	canvas.draw_line(p + Vector2(1, 1), p + Vector2(-1, -42), Color("b09561"), 3.0)
	if variant == 0:
		for tier: int in range(3):
			var top := p + Vector2(0, -102 + tier * 23)
			var width := 24.0 + tier * 7.0
			canvas.draw_colored_polygon(PackedVector2Array([top, top + Vector2(width, 43), top + Vector2(0, 36), top + Vector2(-width, 43)]), Color("386444").lightened(0.07 * (2 - tier)))
			canvas.draw_line(top + Vector2(-3, 10), top + Vector2(-width + 7, 36), Color("759569"), 2.0)
	else:
		var green := Color("49734b") if variant == 1 else Color("667c43")
		_oval(canvas, p + Vector2(2, -58), Vector2(40, 30), green.darkened(0.23))
		_oval(canvas, p + Vector2(-19, -72), Vector2(26, 26), green)
		_oval(canvas, p + Vector2(19, -75), Vector2(28, 27), green.darkened(0.08))
		_oval(canvas, p + Vector2(0, -92), Vector2(30, 25), green.lightened(0.08))
		_oval(canvas, p + Vector2(-10, -100), Vector2(15, 9), green.lightened(0.19))

func _draw_rock(canvas: Node2D, p: Vector2, color: Color, iron: bool) -> void:
	_oval(canvas, p + Vector2(3, 4), Vector2(28, 13), Color(0.06, 0.1, 0.09, 0.25))
	var vertices := PackedVector2Array([p + Vector2(-28, 2), p + Vector2(-17, -26), p + Vector2(5, -35), p + Vector2(27, -15), p + Vector2(28, 7), p + Vector2(0, 13)])
	canvas.draw_colored_polygon(vertices, color)
	canvas.draw_colored_polygon(PackedVector2Array([vertices[0], vertices[1], vertices[2], p + Vector2(1, -4)]), color.lightened(0.2))
	canvas.draw_line(p + Vector2(1, -4), p + Vector2(0, 11), color.darkened(0.32), 2.5)
	if iron:
		canvas.draw_polyline(PackedVector2Array([p + Vector2(-14, -20), p + Vector2(-4, -13), p + Vector2(-10, -6), p + Vector2(12, 4)]), Color("bd8050"), 5.0)
		canvas.draw_line(p + Vector2(12, -24), p + Vector2(20, -14), Color("a76541"), 4.0)

func _draw_plant(canvas: Node2D, p: Vector2, herb: bool) -> void:
	_oval(canvas, p + Vector2(0, 5), Vector2(22, 9), Color(0.08, 0.14, 0.07, 0.25))
	for n: int in range(5):
		var base := p + Vector2(float(n - 2) * 8, 0)
		var top := base + Vector2(float(n % 2) * 4 - 2, -16 - float((n + 1) % 3) * 6)
		canvas.draw_line(base, top, Color("648849"), 3.0)
		_oval(canvas, top + Vector2(-4, 7), Vector2(7, 3), Color("6e984f"))
		_oval(canvas, top, Vector2(4, 4), Color("bd94d7") if herb else Color("d9b443"))

func _draw_fish(canvas: Node2D, p: Vector2) -> void:
	_oval(canvas, p, Vector2(10, 4), Color(0.66, 0.86, 0.85, 0.75))
	canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(8, 0), p + Vector2(16, -5), p + Vector2(16, 5)]), Color("4b8f9f"))
	canvas.draw_circle(p + Vector2(-5, -1), 1.0, Color("315b64"))

func _draw_animal(canvas: Node2D, p: Vector2, phase: float, variant: int) -> void:
	_oval(canvas, p + Vector2(0, 5), Vector2(20, 7), Color(0.08, 0.12, 0.08, 0.26))
	for n: int in range(4):
		var leg := p + Vector2(float(n % 2) * 20 - 11, -10)
		canvas.draw_line(leg, leg + Vector2(sin(phase * 3.0 + n * PI) * 3, 14 - n % 2 * 3), Color("604c38"), 3.0)
	var color := Color("b18a59") if variant != 1 else Color("78675b")
	_oval(canvas, p + Vector2(-1, -16), Vector2(19, 10), color)
	_oval(canvas, p + Vector2(18, -25), Vector2(9, 7), color.lightened(0.1))
	canvas.draw_line(p + Vector2(12, -13), p + Vector2(15, -29), color, 7.0)
	canvas.draw_line(p + Vector2(-18, -16), p + Vector2(-25, -23), color.darkened(0.1), 3.0)
	canvas.draw_circle(p + Vector2(21, -27), 1.4, Color("262b22"))
	if variant == 0:
		canvas.draw_polyline(PackedVector2Array([p + Vector2(15, -29), p + Vector2(11, -41), p + Vector2(7, -43)]), Color("d4c9a5"), 2.0)
		canvas.draw_line(p + Vector2(12, -37), p + Vector2(18, -43), Color("d4c9a5"), 2.0)
	else:
		canvas.draw_line(p + Vector2(14, -29), p + Vector2(12, -37), color.darkened(0.15), 4.0)

func _draw_exhausted(canvas: Node2D, r: Dictionary, p: Vector2) -> void:
	if int(r.kind) == Env.Kind.TIMBER:
		_oval(canvas, p, Vector2(12, 8), Color("725139"))
		_oval(canvas, p + Vector2(0, -3), Vector2(10, 5), Color("c7a477"))
	elif int(r.kind) in [Env.Kind.STONE, Env.Kind.CLAY, Env.Kind.IRON]:
		_oval(canvas, p, Vector2(23, 11), Color(0.2, 0.22, 0.2, 0.38))
	elif int(r.kind) in [Env.Kind.FOOD, Env.Kind.HERB]:
		canvas.draw_line(p, p + Vector2(-3, -9), Color("749052"), 2.0)

func _draw_defense_cell(canvas: Node2D, p: Vector2, palisade: bool) -> void:
	if palisade:
		_oval(canvas, p + Vector2(0, 17), Vector2(28, 7), Color(0.12, 0.1, 0.07, 0.3))
		for x: int in [-24, -12, 0, 12, 24]:
			var base := p + Vector2(x, 16)
			canvas.draw_colored_polygon(PackedVector2Array([base + Vector2(-5, 0), base + Vector2(-5, -32), base + Vector2(0, -41), base + Vector2(5, -32), base + Vector2(5, 0)]), Color("856344"))
			canvas.draw_line(base + Vector2(-2, -28), base + Vector2(-2, -2), Color("c59b66"), 2.0)
		for y: int in [-5, 9]:
			canvas.draw_line(p + Vector2(-30, y), p + Vector2(30, y), Color("56442f"), 4.0)
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

func _draw_feature(canvas: Node2D, feature: Dictionary, row_index: int = -1) -> void:
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
		var rect := Rect2(Vector2(cell) * CELL, Vector2.ONE * CELL)
		var color := Color("856542") if kind.contains("farm") else Color("789158")
		if kind == "road":
			color = Color("bb9d6c")
		color.a = 0.72 if complete else 0.2
		canvas.draw_rect(rect.grow(-3), color)
		canvas.draw_rect(rect.grow(-3), Color("d9bd80"), false, 2.0)
	if kind == "palisade" and row_index >= 0 and row_index != max_cell.y:
		return # One label/scaffold per feature; stakes use their actual ground row.
	var p := Vector2(float(min_cell.x + max_cell.x + 1) * CELL * 0.5, float(max_cell.y + 1) * CELL - 12)
	if not complete:
		for offset: Vector2 in [Vector2(-20, 0), Vector2(20, 0)]:
			canvas.draw_line(p + offset, p + offset + Vector2(0, -45), Color("c59c65"), 4.0)
		canvas.draw_line(p + Vector2(-24, -32), p + Vector2(24, -32), Color("ccad7b"), 4.0)
	elif kind == "house":
		_draw_prop(canvas, "house", p + Vector2(0, 4), float(max_cell.x - min_cell.x + 1) * CELL - 6)
	elif kind == "well":
		_draw_prop(canvas, "well", p + Vector2(0, 2), 52.0)
	elif kind == "intake":
		_oval(canvas, p, Vector2(22, 14), Color("a5a58f"))
		_oval(canvas, p + Vector2(0, -5), Vector2(15, 8), Color("3a5656"))
		canvas.draw_line(p + Vector2(-22, 0), p + Vector2(-22, -47), Color("896945"), 5.0)
		canvas.draw_line(p + Vector2(22, 0), p + Vector2(22, -47), Color("896945"), 5.0)
		canvas.draw_line(p + Vector2(-24, -46), p + Vector2(24, -46), Color("c0a675"), 5.0)
		canvas.draw_line(p + Vector2(0, -46), p + Vector2(0, -12), Color("cfbc87"), 2.0)
	elif kind in ["palisade", "fighting_position"]:
		pass # Per-cell defensive art above; never use the generic workshop house.
	elif bool(feature.solid):
		var width := minf(96.0, float(max_cell.x - min_cell.x + 1) * CELL - 8)
		canvas.draw_rect(Rect2(p + Vector2(-width * 0.5, -49), Vector2(width, 49)), Color("af966f"))
		canvas.draw_rect(Rect2(p + Vector2(-9, -27), Vector2(18, 27)), Color("574737"))
		canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(-width * 0.5 - 7, -46), p + Vector2(0, -80), p + Vector2(width * 0.5 + 7, -46)]), Color("745a42") if kind == "house" else Color("80685a"))
		canvas.draw_line(p + Vector2(-width * 0.5 - 7, -46), p + Vector2(0, -80), Color("c8ab77"), 3.0)
		if kind in ["kiln", "smelter", "smithy", "charcoal"]:
			canvas.draw_rect(Rect2(p + Vector2(15, -82), Vector2(13, 31)), Color("8e8b79"))
			_oval(canvas, p + Vector2(21, -95), Vector2(10, 8), Color(0.8, 0.8, 0.74, 0.35))
	elif kind in ["pasture", "horse_ranch"]:
		for n: int in range(int(feature.get("residents", 1))):
			var animal := p + Vector2(n * 22 - 8, -10)
			if kind == "pasture":
				for leg_x: int in [-9, 9]:
					canvas.draw_line(animal + Vector2(leg_x, -6), animal + Vector2(leg_x, 3), Color("70634e"), 3)
				_oval(canvas, animal + Vector2(-1, -14), Vector2(17, 12), Color("ddd9bd"))
				_oval(canvas, animal + Vector2(16, -16), Vector2(7, 6), Color("8e7b5e"))
			else:
				_draw_animal(canvas, animal, 0.0, 2)
				canvas.draw_line(animal + Vector2(8, -19), animal + Vector2(11, -31), Color("4a3a2b"), 4)
	var label := str(Runtime.FEATURES[kind].name) + ("" if complete else "·施工")
	canvas.draw_string(ThemeDB.fallback_font, p + Vector2(-30, 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("fff0c8"))
