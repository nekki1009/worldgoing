extends Control
## Isolated geography viewer with an original Actor movement test; no formal save/session.

const RegionDataScript = preload("res://scripts/region_lab/region_data.gd")
const RegionGridScript = preload("res://scripts/region_lab/region_grid.gd")
const RendererScript = preload("res://scripts/terrain_lab/terrain_renderer.gd")
const ActorScript = preload("res://scripts/terrain_lab/terrain_test_character.gd")
const PreviewScript = preload("res://scripts/region_lab/region_site_preview.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const ResourceViewScript = preload("res://scripts/terrain_lab/site_resource_view.gd")
const SITE_SCENE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const MAX_PREVIEW_TILES := 32
const PREVIEW_MIN_SITE_PIXELS := 128.0
const CLASS_NAMES: Array[String] = ["缺資料", "海洋", "陸地", "內陸水域", "海陸／水岸混合"]
const PALETTE_SHADER := """
shader_type canvas_item;
void fragment() {
    vec2 encoded = texture(TEXTURE, UV).rg;
    float kind = floor(encoded.r * 255.0 + 0.5);
    float scope = floor(encoded.g * 255.0 + 0.5);
    vec3 color = vec3(0.28, 0.23, 0.32);
    if (kind == 1.0) { color = vec3(0.10, 0.27, 0.40); }
    else if (kind == 2.0) { color = vec3(0.39, 0.57, 0.34); }
    else if (kind == 3.0) { color = vec3(0.27, 0.63, 0.72); }
    else if (kind == 4.0) { color = vec3(0.73, 0.73, 0.48); }
    if (scope == 0.0) { color = mix(color, vec3(0.14, 0.16, 0.19), 0.72); }
    COLOR = vec4(color, 1.0);
}
"""

var source = RegionDataScript.new()
var selected_site := Vector2i(-1, -1)
var selection: Dictionary = {}
var terrain: TerrainData
var actor: TerrainTestCharacter
var site_visible := false
var render_pending := false
var _pending_display: Dictionary = {}
var _pending_display_site := Vector2i(-1, -1)
var _route: Array[Vector2i] = []
var _bounds: Array = []
var _map_size := Vector2.ONE
var _offset := Vector2.ZERO
var _scale := 1.0
var _dragging := false
var _press_position := Vector2.ZERO
var _drag_distance := 0.0
var _overview_texture: ImageTexture
var _canvas: Control
var _overlay: Control
var _overview: TextureRect
var _renderer: TerrainRenderer
var _resource_view: SiteResourceView
var _render_cover: ColorRect
var _details: Label
var _attribution: Label
var _status: Label
var _open_button: Button
var _new_world_button: Button
var _mode := "" # RegionEntry.region_mode captured at build: "pick_start", "view", "travel" or "" (lab).
var _travel: Node # Travelling-party controls ("travel" mode only).
var _back_button: Button
var _samples: OptionButton
var _sample_sites: Array = []
var _east_input: SpinBox
var _north_input: SpinBox
var _open_thread: Thread
var _open_request_site := Vector2i(-1, -1)
var _queued_open_site: Variant = null
var _open_cancelled := false
var _preview_tiles: Dictionary = {}
var _preview_lru: Array[Vector2i] = []
var _preview_queue: Array[Vector2i] = []
var _preview_visible_sites: Array[Vector2i] = []
var _preview_errors: Dictionary = {}
var _preview_thread: Thread
var _preview_requested_site := Vector2i(-1, -1)
var _preview_open_site: Variant = null
var _preview_image: TextureRect
var _preview_label: Label
var _preview_dirty := false
var _preview_after_usec := 0
var _preview_manifest_hash := ""
var _overview_view: Dictionary = {}

func _ready() -> void:
	_build_ui()
	var result: Dictionary = source.load_manifest()
	if not bool(result.get("ok", false)):
		_status.text = "地圖尚未就緒：%s" % str(result.get("message", result.get("code", "缺少固定資料")))
		_details.text = "沒有可用的固定底圖。\n缺資料不會轉成海洋或隨機地形。"
		return
	_attribution.text = str(source.manifest.get("attribution", _attribution.text))
	var overview: Dictionary = source.get_overview()
	if not bool(overview.get("ok", false)):
		_status.text = "概覽讀取失敗：%s" % str(overview.get("message", overview.get("code", "缺資料")))
		return
	_bounds = overview.get("bounds_m", [])
	var width: int = int(overview.get("width", 0))
	var height: int = int(overview.get("height", 0))
	var classes: PackedByteArray = overview.get("classes", PackedByteArray())
	var scopes: PackedByteArray = overview.get("content_scope", PackedByteArray())
	if _bounds.size() != 4 or width <= 0 or height <= 0 or classes.size() != width * height:
		_status.text = "概覽格式不完整，停止載入。"
		return
	_map_size = Vector2(float(_bounds[2]) - float(_bounds[0]), float(_bounds[3]) - float(_bounds[1]))
	if _map_size.x <= 0.0 or _map_size.y <= 0.0:
		_status.text = "概覽範圍無效，停止載入。"
		return
	# One native texture upload: no per-Site Node, Color array, or draw callback.
	var pixels := PackedByteArray()
	pixels.resize(classes.size() * 2)
	for i: int in range(classes.size()):
		pixels[i * 2] = classes[i]
		pixels[i * 2 + 1] = scopes[i] if scopes.size() == classes.size() else 1
	_overview_texture = ImageTexture.create_from_image(Image.create_from_data(width, height, false, Image.FORMAT_RG8, pixels))
	_overview.texture = _overview_texture
	_sample_sites = source.manifest.get("preview_sites", []).duplicate(true)
	if not source.resource_manifest_hash.is_empty():
		_sample_sites.append({"label": "森林資源樣本", "site": [1170, 13252]})
	for item: Variant in _sample_sites:
		if item is Dictionary:
			_samples.add_item(str(item.get("label", "代表地點")))
	_samples.disabled = _samples.item_count == 0
	_status.text = {"pick_start": "拖曳平移・滾輪縮放・點選地點。選一個有細節資料的陸地 Site 作為起點。",
		"view": "拖曳平移・滾輪縮放・點選地點。金框是目前所在地，白點是去過的地點。"}.get(_mode,
		"拖曳平移・滾輪縮放・點選地點。只有具備細節資料的 Site 可以開啟。")
	_fit_view.call_deferred()
	if _travel != null:
		var travel: Dictionary = _travel.call("start", RegionEntry.view)
		_status.text = "旅隊模式：點選目的地 → 規劃路線 → 出發。時間只在行進時流動。"
		if bool(travel.get("ok", false)):
			select_site(travel.site)
			focus_selected_area.call_deferred()
		return
	var active: Variant = RegionEntry.view.get("active") if _mode == "view" else null
	if active is Vector2i and active != Vector2i(-1, -1):
		select_site(active)
		focus_selected_area.call_deferred()
	elif _mode == "pick_start" and RegionEntry.draft.get("site") is Vector2i:
		select_site(RegionEntry.draft.site)
		focus_selected_area.call_deferred()
	elif not _sample_sites.is_empty():
		_select_sample(0)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("101b24")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_mode = RegionEntry.region_mode
	RegionEntry.region_mode = ""
	var title := Label.new()
	title.text = {"pick_start": "新遊戲：選擇起點", "view": "台灣", "travel": "台灣・旅途中"}.get(_mode, "台灣地理測試  /  Region Lab")
	title.add_theme_font_size_override("font_size", 23 if _mode.is_empty() else 40)
	if not _mode.is_empty():
		# Game screens use the main menu's text size for the 2560×1440 design.
		theme = Theme.new()
		theme.default_font_size = 26
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "固定地圖・Site 200 × 200 公尺・每格 2 公尺・Region 20 × 20 公里"
	column.add_child(subtitle)
	_attribution = Label.new()
	_attribution.text = "地形來源：內政部 20 公尺數值地形模型；海岸線：GSHHG 2.3.7"
	_attribution.add_theme_font_size_override("font_size", 13)
	_attribution.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_attribution)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(360, 320)
	_canvas.clip_contents = true
	_canvas.gui_input.connect(_on_map_input)
	_canvas.resized.connect(_fit_view)
	body.add_child(_canvas)
	_overview = TextureRect.new()
	_overview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shader := Shader.new()
	shader.code = PALETTE_SHADER
	var palette_material := ShaderMaterial.new()
	palette_material.shader = shader
	_overview.material = palette_material
	_canvas.add_child(_overview)
	_renderer = RendererScript.new()
	_renderer.brush_enabled = false
	_renderer.progressive_display = true
	_renderer.visible = false
	_canvas.add_child(_renderer)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	_canvas.add_child(_overlay)
	_render_cover = ColorRect.new()
	_render_cover.color = Color("101b24")
	_render_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_render_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_render_cover.visible = false
	_canvas.add_child(_render_cover)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 320
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 10)
	scroll.add_child(side)
	if _mode == "pick_start":
		_add_button(side, "返回主選單", func() -> void: get_tree().change_scene_to_file(RegionEntry.MAIN_MENU))
	elif _mode == "travel":
		_travel = load("res://scripts/region_lab/region_travel_panel.gd").new()
		_travel.call("setup", self)
		side.add_child(_travel)
	else:
		_add_button(side, "返回遊戲", return_to_game)
	_samples = OptionButton.new()
	_samples.disabled = true
	_samples.item_selected.connect(_select_sample)
	side.add_child(_samples)
	var buttons := HBoxContainer.new()
	side.add_child(buttons)
	_add_button(buttons, "＋", func() -> void: _zoom(1.5, _canvas.size * 0.5))
	_add_button(buttons, "−", func() -> void: _zoom(1.0 / 1.5, _canvas.size * 0.5))
	_add_button(buttons, "完整範圍", _fit_view)
	_add_button(side, "查看所選附近地形", focus_selected_area)
	var address_label := Label.new()
	address_label.text = "依 Site 位址選取（東向 x、北向 y）"
	side.add_child(address_label)
	var address := HBoxContainer.new()
	side.add_child(address)
	_east_input = _add_coordinate_input(address)
	_north_input = _add_coordinate_input(address)
	_add_button(address, "選取", func() -> void: select_site(Vector2i(int(_east_input.value), int(_north_input.value))))
	_new_world_button = _add_button(side, "以所選地點為起點", start_world_at_selected_site)
	_new_world_button.disabled = true
	_new_world_button.visible = _mode == "pick_start"
	_open_button = _add_button(side, "開啟所選 Site", request_open_selected_site)
	_open_button.disabled = true
	_back_button = _add_button(side, "返回地圖", show_overview)
	_back_button.disabled = true
	# The Site walk-through with a test Actor stays a lab tool, not a game screen.
	_open_button.visible = _mode.is_empty()
	_back_button.visible = _mode.is_empty()
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.text = "選取地點以查看固定身分與資料狀態。"
	_details.add_theme_font_size_override("font_size", 14 if _mode.is_empty() else 22)
	side.add_child(_details)
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.text = "選取 Site 後顯示地形預覽"
	side.add_child(_preview_label)
	_preview_image = TextureRect.new()
	_preview_image.custom_minimum_size = Vector2(0, 220)
	_preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(_preview_image)
	var legend := Label.new()
	legend.text = "細地形：淺色高台・棕色崖緣・米色坡口\n藍色水域・紫色缺資料・暗色未開放" + ("\nSite 人物：方向鍵 / WASD 或點選目的格" if _mode.is_empty() else "")
	legend.add_theme_font_size_override("font_size", 13 if _mode.is_empty() else 20)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(legend)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 42
	_status.text = "正在讀取固定地理資料…"
	column.add_child(_status)

func _add_button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _add_coordinate_input(parent: Node) -> SpinBox:
	var input := SpinBox.new()
	input.min_value = -10000000
	input.max_value = 10000000
	input.custom_minimum_size.x = 80
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(input)
	return input

func select_site(site: Vector2i) -> Dictionary:
	if site_visible and site != selected_site:
		_status.text = "請先返回地圖，再選取其他 Site。"
		return {"ok": false, "code": "SITE_ACTIVE", "message": _status.text}
	if render_pending and site != _pending_display_site:
		_cancel_display()
	selected_site = site
	if _open_thread != null and site != _open_request_site:
		_open_cancelled = true
	if _preview_open_site != null and site != _preview_open_site:
		_preview_open_site = null
		_back_button.disabled = true
		_back_button.text = "返回地圖"
		_status.text = "已取消先前的開啟要求。"
	selection = source.get_site_summary(site.x, site.y)
	_east_input.value = site.x
	_north_input.value = site.y
	_samples.select(-1)
	_samples.text = "代表地點"
	for index: int in range(_sample_sites.size()):
		var sample_coordinates: Array = _sample_sites[index].get("site", [])
		if sample_coordinates.size() == 2 and Vector2i(int(sample_coordinates[0]), int(sample_coordinates[1])) == site:
			_samples.select(index)
			break
	var class_id: int = clampi(int(selection.get("class_id", 0)), 0, CLASS_NAMES.size() - 1)
	var state := str(selection.get("status", "outside_content"))
	var state_label: String = str({"outside_content": "尚未開放", "missing_data": "缺資料", "sea": "海洋", "land": "陸地", "inland_water": "內陸水域", "mixed": "混合岸線"}.get(state, "缺資料"))
	_details.text = "Site：%s\nRegion：%s\n地理：%s\n狀態：%s\n高程資料：%s\n品質：%s" % [
		str(selection.get("site_id", site)), str(selection.get("region", "—")), CLASS_NAMES[class_id],
		state_label, "海面" if class_id == 1 else ("有" if bool(selection.get("has_elevation", false)) else "尚缺"),
		_quality_description(int(selection.get("source_quality_code", -1)))]
	_open_button.disabled = site_visible or not bool(selection.get("ok", false)) or not bool(selection.get("has_terrain", false)) or class_id == 0
	_new_world_button.disabled = not bool(selection.get("ok", false)) or not bool(selection.get("has_terrain", false)) or class_id not in [2, 4]
	_update_selected_preview()
	_queue_preview_refresh()
	_overlay.queue_redraw()
	if _travel != null: _travel.call("_refresh")
	return selection

func _quality_description(code: int) -> String:
	match code:
		0: return "未提供有效高程"
		1: return "20 公尺原始高程；非 2 公尺實測"
		2: return "部分高程由鄰近來源插值"
		3: return "部分高程由鄰近來源外推"
		4: return "含高程推估（精度未定）"
	return "20 公尺來源；非 2 公尺實測"

func focus_selected_area() -> void:
	if site_visible or _bounds.size() != 4 or not bool(selection.get("ok", false)):
		return
	# About three Sites high: enough context to compare neighbouring slopes.
	_scale = clampf(minf(_canvas.size.x, _canvas.size.y) / 600.0, 0.8, 4.0)
	var center := Vector2((selected_site.x + 0.5) * 200.0 - float(_bounds[0]),
		float(_bounds[3]) - (selected_site.y + 0.5) * 200.0)
	_offset = _canvas.size * 0.5 - center * _scale
	_update_transform()

func _site_rect(site: Vector2i) -> Rect2:
	var north_west := Vector2(site.x * 200.0 - float(_bounds[0]),
		float(_bounds[3]) - (site.y + 1.0) * 200.0)
	return Rect2(_offset + north_west * _scale, Vector2.ONE * 200.0 * _scale)

func _queue_preview_refresh() -> void:
	_preview_dirty = true
	_preview_after_usec = Time.get_ticks_usec() + 150_000

func _update_selected_preview() -> void:
	if _preview_image == null:
		return
	_preview_image.texture = null
	if not bool(selection.get("ok", false)) or not bool(selection.get("has_terrain", false)):
		_preview_label.text = "此地點尚無可用地形預覽"
	elif _preview_errors.has(selected_site):
		_preview_label.text = "地形預覽失敗：" + str(_preview_errors[selected_site])
	elif _preview_tiles.has(selected_site):
		var tile: Dictionary = _preview_tiles[selected_site]
		_preview_image.texture = tile.texture
		var info: Dictionary = tile.metadata
		_preview_label.text = "所選 Site 地形・200 × 200 公尺\n台階 %d–%d・水域 %.1f%%\n%s" % [
			int(info.height_min), int(info.height_max), float(info.water_cells) / 100.0,
			_resource_info_text(info.get("resource_counts", []), str(info.get("resource_source_summary", "")))]
	else:
		_preview_label.text = "正在準備所選地形…"

func _refresh_preview_queue() -> void:
	_preview_dirty = false
	_preview_queue.clear()
	_preview_visible_sites.clear()
	if site_visible or render_pending or source.manifest.is_empty():
		return
	if _preview_manifest_hash != source.manifest_hash:
		_preview_tiles.clear()
		_preview_lru.clear()
		_preview_errors.clear()
		_preview_manifest_hash = source.manifest_hash
	# Selected Site has priority even at the whole-island scale.
	if bool(selection.get("has_terrain", false)):
		_preview_queue.append(selected_site)
	if _scale * 200.0 >= PREVIEW_MIN_SITE_PIXELS and _bounds.size() == 4:
		var left := maxf(0.0, -_offset.x / _scale)
		var right := minf(_map_size.x, (_canvas.size.x - _offset.x) / _scale)
		var top := maxf(0.0, -_offset.y / _scale)
		var bottom := minf(_map_size.y, (_canvas.size.y - _offset.y) / _scale)
		if left < right and top < bottom:
			var west := floori((float(_bounds[0]) + left) / 200.0)
			var east := ceili((float(_bounds[0]) + right) / 200.0) - 1
			var south := floori((float(_bounds[3]) - bottom) / 200.0)
			var north := ceili((float(_bounds[3]) - top) / 200.0) - 1
			# A wide window must zoom further instead of enqueueing an unbounded atlas.
			if (east - west + 1) * (north - south + 1) < MAX_PREVIEW_TILES:
				for y: int in range(south, north + 1):
					for x: int in range(west, east + 1):
						_preview_visible_sites.append(Vector2i(x, y))
				var center := Vector2((west + east) * 0.5, (south + north) * 0.5)
				_preview_visible_sites.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
					return Vector2(a).distance_squared_to(center) < Vector2(b).distance_squared_to(center))
				for site: Vector2i in _preview_visible_sites:
					var info: Dictionary = source.get_site_summary(site.x, site.y)
					if site != selected_site and bool(info.get("has_terrain", false)) and int(info.get("class_id", 0)) != 1:
						_preview_queue.append(site)
	var pending: Array[Vector2i] = []
	for site: Vector2i in _preview_queue:
		if _preview_tiles.has(site):
			_preview_lru.erase(site)
			_preview_lru.append(site)
		elif not _preview_errors.has(site):
			pending.append(site)
	_preview_queue = pending
	_update_selected_preview()
	_overlay.queue_redraw()

func _process_preview() -> void:
	if _preview_thread != null and not _preview_thread.is_alive():
		var completed_site := _preview_requested_site
		var result: Dictionary = _preview_thread.wait_to_finish()
		_preview_thread = null
		_preview_queue.erase(completed_site)
		# A completed old position may be cached, but never relabelled as the selection.
		if bool(result.get("ok", false)):
			var built: Dictionary = result.terrain_result
			var data: TerrainData = built.data
			var pixels: PackedByteArray = result.pixels
			var dimensions: Vector2i = result.size
			var texture := ImageTexture.create_from_image(Image.create_from_data(
				dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8, pixels))
			_preview_tiles[completed_site] = {"texture": texture,
				"metadata": {"site_id": built.metadata.site_id, "fingerprint": built.base.terrain_fingerprint,
					"terrain_fingerprint": built.base.terrain_fingerprint, "water_body_sha256": result.water_body_sha256,
					"height_min": 5,
					"height_max": 0, "water_cells": built.metadata.water_cells,
					"land_cells": built.metadata.land_cells,
					"resource_counts": result.resource_counts,
					"resource_source_summary": str(built.metadata.get("resource_source_summary", ""))}}
			var info: Dictionary = _preview_tiles[completed_site].metadata
			info.height_min = 5
			for level: int in data.height_levels:
				info.height_min = mini(int(info.height_min), level)
				info.height_max = maxi(int(info.height_max), level)
			_preview_lru.erase(completed_site)
			_preview_lru.append(completed_site)
			while _preview_lru.size() > MAX_PREVIEW_TILES:
				var oldest: Vector2i = _preview_lru.pop_front()
				if oldest == selected_site:
					_preview_lru.append(oldest)
				else:
					_preview_tiles.erase(oldest)
		else:
			_preview_errors[completed_site] = str(result.get("message", result.get("code", "來源缺資料")))
			if _preview_errors.size() > MAX_PREVIEW_TILES:
				_preview_errors.erase(_preview_errors.keys()[0])
		_update_selected_preview()
		_overlay.queue_redraw()
		if _preview_open_site is Vector2i:
			var requested: Vector2i = _preview_open_site
			_preview_open_site = null
			if requested == selected_site:
				if requested == completed_site and bool(result.get("ok", false)):
					_show_site(result.terrain_result)
				else:
					_start_open(requested)
			else:
				_back_button.disabled = true
				_back_button.text = "返回地圖"
				_open_button.disabled = not bool(selection.get("has_terrain", false))
			return
	if _preview_dirty and Time.get_ticks_usec() >= _preview_after_usec:
		_refresh_preview_queue()
	if _preview_thread != null or _open_thread != null or site_visible or render_pending \
			or _preview_dirty or _preview_queue.is_empty():
		return
	_preview_requested_site = _preview_queue.pop_front()
	_preview_thread = Thread.new()
	var started := _preview_thread.start(PreviewScript.bake.bind(source, _preview_requested_site))
	if started != OK:
		_preview_thread = null
		_preview_errors[_preview_requested_site] = error_string(started)
		_update_selected_preview()

## New Game: keep the chosen start in the menu draft and continue there.
func start_world_at_selected_site() -> void:
	if _new_world_button.disabled: return
	RegionEntry.draft["site"] = selected_site
	RegionEntry.draft["step"] = "character"
	get_tree().change_scene_to_file(RegionEntry.MAIN_MENU)

## Back to the world the map was opened from; a lab run returns to the default Site.
func return_to_game() -> void:
	if _mode == "view" and not str(RegionEntry.view.get("world_id", "")).is_empty():
		RegionEntry.request_world(str(RegionEntry.view.world_id), str(RegionEntry.view.get("slot_id", RegionEntry.SLOT)))
	RegionEntry.view = {}
	get_tree().change_scene_to_file(SITE_SCENE)

func request_open_selected_site() -> void:
	if render_pending:
		return
	if not bool(selection.get("has_terrain", false)):
		return
	if _preview_thread != null:
		# The one RegionData cache is never touched by two workers at once.
		_preview_open_site = selected_site
		_preview_queue.clear()
		_open_button.disabled = true
		_back_button.disabled = false
		_back_button.text = "取消載入"
		_status.text = "正在準備所選 Site…"
		return
	if _open_thread != null:
		if selected_site != _open_request_site:
			_queued_open_site = selected_site
			_status.text = "正在準備新的地點；先完成前一份讀取。"
		else:
			_queued_open_site = null
			_open_cancelled = false
		return
	_start_open(selected_site)

func _start_open(site: Vector2i) -> void:
	_preview_queue.clear()
	_open_request_site = site
	_open_cancelled = false
	_queued_open_site = null
	_open_thread = Thread.new()
	var started: Error = _open_thread.start(source.make_terrain_data.bind(site.x, site.y))
	if started != OK:
		_open_thread = null
		_status.text = "無法開始讀取 Site：%s" % error_string(started)
		return
	_open_button.disabled = true
	_back_button.disabled = false
	_back_button.text = "取消載入"
	_status.text = "正在準備所選 Site…"

func open_selected_site() -> Dictionary:
	# Synchronous acceptance callers still respect the same cache ownership.
	if _preview_thread != null:
		_preview_thread.wait_to_finish()
		_preview_thread = null
	_preview_open_site = null
	return _show_site(source.make_terrain_data(selected_site.x, selected_site.y))

func _show_site(result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		_status.text = "無法開啟 Site：%s" % str(result.get("message", result.get("code", "缺資料")))
		return result
	var candidate: TerrainData = result.get("data") as TerrainData
	if candidate == null:
		_status.text = "地形資料無效；保留目前畫面。"
		return {"ok": false, "code": "INVALID_TERRAIN"}
	if not site_visible and not render_pending:
		_overview_view = {"scale": _scale, "offset": _offset}
	_clear_resource_view()
	terrain = candidate
	_renderer.display(terrain)
	_clear_actor()
	render_pending = _renderer.display_pending
	if render_pending:
		_pending_display = result
		_pending_display_site = selected_site
		# Keep the renderer visible so actual draw callbacks prepare its retained
		# commands behind this cover; visibility alone is not completion evidence.
		_renderer.visible = true
		_render_cover.visible = true
		_open_button.disabled = true
		_back_button.disabled = false
		_back_button.text = "取消載入"
		_status.text = "正在準備地形畫面…"
		return result
	return _finish_display(result)

func _finish_display(result: Dictionary) -> Dictionary:
	# A whole-sea Site has no lawful spawn or mutable Site state.
	if terrain.spawn_cell != Vector2i(-1, -1):
		Env.initialize(terrain, str(result.get("metadata", {}).get("site_id", "")))
	if not terrain.site.is_empty() and not terrain.resource_base.is_empty():
		_resource_view = ResourceViewScript.new()
		_resource_view.name = "SiteResources"
		_renderer.add_child(_resource_view)
		_resource_view.display(terrain)
	var spawn := terrain.spawn_cell
	if not terrain.is_walkable(spawn):
		spawn = Vector2i(-1, -1)
		for index: int in range(terrain.size.x * terrain.size.y):
			var cell: Vector2i = terrain.cell_from_index(index)
			if terrain.is_walkable(cell):
				spawn = cell
				break
	if terrain.is_walkable(spawn):
		actor = ActorScript.new()
		actor.name = "RegionMovementTestActor"
		actor.data = terrain
		actor.visible = false # Only the marker presents this original Actor; no model viewport.
		_renderer.add_child(actor)
		if not actor.place(spawn, true):
			_clear_actor()
	_render_cover.visible = false
	site_visible = true
	_overview.visible = false
	_renderer.visible = true
	_back_button.disabled = false
	_back_button.text = "返回地圖"
	_open_button.disabled = true
	_details.text += "\n來源高程供地理檢視；人物通行沿用原 Site 台階規則。"
	var estimated := int(result.get("metadata", {}).get("estimated_elevation_cells", 0))
	if estimated > 0:
		_details.text += "\n本 Site 有 %d 格使用插值或推估高程。" % estimated
	_details.text += "\n" + _resource_info_text(PreviewScript.visible_resource_counts(terrain),
		str(result.get("metadata", {}).get("resource_source_summary", "")))
	_status.text = "Site 固定地理預覽；圓點跟隨原測試人物。方向鍵 / WASD 依原人物規則移動。" if actor != null else "Site 地形預覽：沒有合法陸地落點，不建立測試人物。"
	_fit_view()
	return result

func _cancel_display() -> void:
	render_pending = false
	_pending_display = {}
	_clear_resource_view()
	_renderer.data = null
	_renderer.redraw()
	_renderer.visible = false
	_render_cover.visible = false
	terrain = null
	site_visible = false
	_clear_actor()
	_overview.visible = true
	_back_button.disabled = true
	_back_button.text = "返回地圖"
	_status.text = "已取消；目前地圖保持原樣。"

func show_overview() -> void:
	if _preview_open_site != null:
		_preview_open_site = null
		_back_button.disabled = true
		_back_button.text = "返回地圖"
		_open_button.disabled = not bool(selection.get("has_terrain", false))
		_status.text = "已取消開啟；保留地圖預覽。"
		_queue_preview_refresh()
		return
	if _open_thread != null:
		_open_cancelled = true
		_queued_open_site = null
		_back_button.text = "返回地圖"
		_status.text = "已取消；目前地圖保持原樣。"
		return
	if render_pending:
		_cancel_display()
	site_visible = false
	_clear_resource_view()
	_renderer.visible = false
	_renderer.data = null
	_renderer.redraw()
	_clear_actor()
	terrain = null
	_overview.visible = true
	_back_button.disabled = true
	_status.text = "固定地理概覽；選地點後可查資料狀態。"
	if not selection.is_empty():
		select_site(selected_site)
	if _overview_view.is_empty():
		_fit_view()
	else:
		_scale = float(_overview_view.scale)
		_offset = _overview_view.offset
		_update_transform()

func _clear_resource_view() -> void:
	if _resource_view == null:
		return
	_resource_view.visible = false
	_renderer.remove_child(_resource_view)
	_resource_view.queue_free()
	_resource_view = null

func _resource_info_text(counts: Variant, source_summary: String) -> String:
	var entries: Array = []
	if counts is Array:
		entries = counts
	var names := PackedStringArray()
	for kind: int in range(mini(entries.size(), Env.NAMES.size())):
		if int(entries[kind]) > 0:
			names.append("%s %d 處" % [Env.NAMES[kind], int(entries[kind])])
	var listed := "此 Site 尚無具來源的可見資源" if names.is_empty() else "可見資源據點：" + "、".join(names)
	return listed if source_summary.is_empty() else listed + "\n來源：" + source_summary

func _select_sample(index: int) -> void:
	if index < 0 or index >= _sample_sites.size():
		return
	var sample: Dictionary = _sample_sites[index]
	var site: Array = sample.get("site", [])
	if site.size() == 2:
		if site_visible:
			show_overview()
		select_site(Vector2i(int(site[0]), int(site[1])))

func _fit_view() -> void:
	if _canvas == null or _overlay == null:
		return
	var dimensions := Vector2(terrain.size) * TerrainRenderer.CELL_PIXELS if site_visible and terrain != null else _map_size
	_scale = maxf(0.00001, minf((_canvas.size.x - 24.0) / dimensions.x, (_canvas.size.y - 24.0) / dimensions.y))
	_offset = (_canvas.size - dimensions * _scale) * 0.5
	_update_transform()

func _zoom(factor: float, anchor: Vector2) -> void:
	var minimum := 0.025 if site_visible else 0.0001
	var maximum := 2.0 if site_visible else 4.0
	var new_scale := clampf(_scale * factor, minimum, maximum)
	_offset = anchor - (anchor - _offset) * (new_scale / _scale)
	_scale = new_scale
	_update_transform()

func _update_transform() -> void:
	_overview.position = _offset
	_overview.size = _map_size * _scale
	_renderer.position = _offset
	_renderer.scale = Vector2.ONE * _scale
	_overlay.queue_redraw()
	_queue_preview_refresh()

func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.25, button.position)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(0.8, button.position)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_dragging = true
				_press_position = button.position
				_drag_distance = 0.0
			else:
				_dragging = false
				if _drag_distance < 5.0:
					_pick_position(button.position)
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_drag_distance = maxf(_drag_distance, motion.position.distance_to(_press_position))
		_offset += motion.relative
		_update_transform()
	_canvas.accept_event()

func _pick_position(position_in_canvas: Vector2) -> void:
	var local := (position_in_canvas - _offset) / _scale
	if site_visible and terrain != null:
		var goal := Vector2i(floori(local.x / TerrainRenderer.CELL_PIXELS), floori(local.y / TerrainRenderer.CELL_PIXELS))
		if not terrain.contains(goal) or actor == null:
			return
		if goal == actor.terrain_cell:
			_status.text = "原測試人物：%s" % goal
			return
		_route = terrain.path_between(actor.terrain_cell, goal)
		if _route.is_empty():
			_status.text = "原 Site 規則判定無法抵達 %s。" % goal
		else:
			_status.text = "原測試人物將逐步前往 %s，共 %d 步。" % [goal, _route.size()]
		return
	if _bounds.size() == 4 and Rect2(Vector2.ZERO, _map_size).has_point(local):
		var east: float = float(_bounds[0]) + float(local.x)
		var north: float = float(_bounds[3]) - float(local.y)
		select_site(RegionGridScript.site_from_meters(east, north))

func _unhandled_key_input(event: InputEvent) -> void:
	if not site_visible or not event is InputEventKey or not event.is_pressed():
		return
	var key: int = (event as InputEventKey).physical_keycode
	var direction := Vector2i.ZERO
	match key:
		KEY_UP, KEY_W: direction = Vector2i.UP
		KEY_RIGHT, KEY_D: direction = Vector2i.RIGHT
		KEY_DOWN, KEY_S: direction = Vector2i.DOWN
		KEY_LEFT, KEY_A: direction = Vector2i.LEFT
	if direction != Vector2i.ZERO:
		_route.clear()
		try_probe_step(direction)
		get_viewport().set_input_as_handled()

func try_probe_step(direction: Vector2i) -> bool:
	if actor == null or not actor.step(direction):
		_status.text = "原人物尚在移動，或 Site 通行規則阻擋此步。"
		return false
	_status.text = "原測試人物：%s；Actor.step 允許此步。" % actor.terrain_cell
	_overlay.queue_redraw()
	return true

func _process(_delta: float) -> void:
	_process_preview()
	if _open_thread != null and not _open_thread.is_alive():
		var completed_site := _open_request_site
		var result: Dictionary = _open_thread.wait_to_finish()
		_open_thread = null
		_back_button.text = "返回地圖"
		if _queued_open_site is Vector2i:
			_start_open(_queued_open_site)
		elif _open_cancelled or selected_site != completed_site:
			_back_button.disabled = true
			select_site(selected_site)
			_status.text = "已取消；目前地圖保持原樣。"
		else:
			var shown := _show_site(result)
			if not shown.ok:
				_back_button.disabled = true
				_open_button.disabled = not bool(selection.get("has_terrain", false))
	if render_pending and not _renderer.display_pending:
		if selected_site != _pending_display_site:
			_cancel_display()
		else:
			var prepared := _pending_display
			_pending_display = {}
			render_pending = false
			_finish_display(prepared)
	if not site_visible or actor == null:
		return
	if not actor.is_moving() and not _route.is_empty():
		var next: Vector2i = _route[0]
		if try_probe_step(next - actor.terrain_cell):
			_route.pop_front()
		else:
			_route.clear()
	_overlay.queue_redraw()

func _exit_tree() -> void:
	if _preview_thread != null:
		_preview_thread.wait_to_finish()
		_preview_thread = null
	if _open_thread != null:
		_open_thread.wait_to_finish()
		_open_thread = null

func _clear_actor() -> void:
	_route.clear()
	if is_instance_valid(actor):
		actor.free()
	actor = null

func _draw_overlay() -> void:
	if _overlay == null:
		return
	if site_visible and terrain != null:
		if actor != null:
			var center := _offset + actor.position * _scale
			_overlay.draw_circle(center, maxf(4.0, 20.0 * _scale), Color("f6d77b"))
			_overlay.draw_arc(center, maxf(5.5, 25.0 * _scale), 0.0, TAU, 24, Color("142c36"), 2.0)
		return
	if _bounds.size() != 4:
		return
	for site: Vector2i in _preview_visible_sites:
		if _preview_tiles.has(site):
			_overlay.draw_texture_rect(_preview_tiles[site].texture, _site_rect(site), false)
		elif int(source.get_site_summary(site.x, site.y).get("class_id", 0)) == 1:
			_overlay.draw_rect(_site_rect(site), PreviewScript.SEA_COLOR)
		_overlay.draw_rect(_site_rect(site), Color(0.95, 0.98, 0.9, 0.22), false, 1.0)
	var map_rect := Rect2(_offset, _map_size * _scale)
	_overlay.draw_rect(map_rect, Color("799097"), false, 1.0)
	var region_pixels := 20000.0 * _scale
	if region_pixels >= 16.0:
		for x: int in range(0, ceili(_map_size.x / 20000.0) + 1):
			var at := _offset.x + float(x) * region_pixels
			_overlay.draw_line(Vector2(at, map_rect.position.y), Vector2(at, map_rect.end.y), Color(0.9, 0.95, 1.0, 0.13))
		for y: int in range(0, ceili(_map_size.y / 20000.0) + 1):
			var at := _offset.y + float(y) * region_pixels
			_overlay.draw_line(Vector2(map_rect.position.x, at), Vector2(map_rect.end.x, at), Color(0.9, 0.95, 1.0, 0.13))
	if not selection.is_empty():
		var top_left := Vector2(float(selected_site.x) * 200.0 - float(_bounds[0]), float(_bounds[3]) - (float(selected_site.y) + 1.0) * 200.0)
		var at := _offset + top_left * _scale
		var span := Vector2.ONE * 200.0 * _scale
		_overlay.draw_rect(Rect2(at, span), Color("ffe49b"), false, 2.0)
		if span.x < 8.0:
			_overlay.draw_circle(at + span * 0.5, 4.0, Color("ffe49b"))
	if _mode == "view":
		for visited: Variant in RegionEntry.view.get("visited", []):
			var rect := _site_rect(visited)
			_overlay.draw_circle(rect.get_center(), maxf(2.5, rect.size.x * 0.2), Color(1, 1, 1, 0.85))
		var active: Variant = RegionEntry.view.get("active")
		if active is Vector2i and active != Vector2i(-1, -1):
			var here := _site_rect(active)
			_overlay.draw_rect(here.grow(maxf(2.0, here.size.x * 0.1)), Color("ffb347"), false, 3.0)
			_overlay.draw_circle(here.get_center(), maxf(5.0, here.size.x * 0.25), Color("ffb347"))
	if _travel != null: _travel.call("draw_on", _overlay)
	var map_note := "N ↑   Region 網格：20 km・查看附近地形可辨識 Site"
	if not _preview_visible_sites.is_empty():
		var ready_tiles := 0
		for site: Vector2i in _preview_visible_sites:
			if _preview_tiles.has(site) or int(source.get_site_summary(site.x, site.y).get("class_id", 0)) == 1:
				ready_tiles += 1
		map_note = "N ↑   Site 網格：200 m・地形 %d / %d" % [ready_tiles, _preview_visible_sites.size()]
	_overlay.draw_string(ThemeDB.fallback_font, Vector2(12, 23), map_note, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e6eef2"))
