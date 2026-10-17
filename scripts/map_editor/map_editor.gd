extends Control
## P1B author host: a source-only candidate, never a normal TerrainLab session.
const Entry = preload("res://scripts/region_lab/region_entry.gd")
const Data = preload("res://scripts/region_lab/region_data.gd")
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Preview = preload("res://scripts/region_lab/region_site_preview.gd")
const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const DRAFT_ROOT := "user://map_editor/drafts"
const MAX_DRAFT_BYTES := 65536
const PLAYTEST_REASON := "情境發布／建立試玩世界尚未實作，仍可保存草稿。"
var source = Data.new()
var terrain: TerrainData
var draft: Dictionary = {}
var _saved_content := ""
var _samples: Array[Vector2i] = []
var _renderer: TerrainRenderer
var _resources: SiteResourceView
var _canvas: Control
var _name: LineEdit
var _file: LineEdit
var _open_file: LineEdit
var _saved_path := ""
var _sites: OptionButton
var _status: Label
var _unsaved: ConfirmationDialog
var _next_action: Callable
var _dragging := false
var _offset := Vector2.ZERO
var _scale := 0.1

func _ready() -> void:
	_build_ui()
	var request := Entry.take_author_request()
	var path := str(request.get("manifest", Data.DEFAULT_MANIFEST))
	if path != Data.DEFAULT_MANIFEST:
		_status.text = "P1B 只開放固定台灣標準來源；未開啟草稿。"
		return
	var loaded: Dictionary = source.load_manifest(path)
	if not bool(loaded.get("ok", false)):
		_status.text = "來源讀取失敗：" + str(loaded.get("message", loaded.get("code", "")))
		return
	for sample: Dictionary in source.manifest.get("preview_sites", []):
		var pair: Array = sample.get("site", [])
		if not Adapter.author_pair_valid(pair, 0, 1000000): continue
		var site := Vector2i(int(pair[0]), int(pair[1]))
		var info: Dictionary = source.get_site_summary(site.x, site.y)
		if not bool(info.get("ok", false)) or not bool(info.get("has_terrain", false)): continue
		_samples.append(site)
		_sites.add_item(str(sample.get("label", site)))
	if _samples.is_empty():
		_status.text = "沒有合法標準候選；保留來源錯誤，不建立替代地形。"
		return
	new_work(_samples[0])

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.name = "AuthorColumn"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var row := HBoxContainer.new()
	row.name = "AuthorToolbar"
	column.add_child(row)
	_name = LineEdit.new()
	_name.name = "WorkName"
	_name.max_length = 64
	_name.placeholder_text = "作品名稱"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name)
	_name.text_changed.connect(_rename_work)
	_file = LineEdit.new()
	var save_label := Label.new()
	save_label.text = "保存／另存："
	row.add_child(save_label)
	_file.name = "DraftFile"
	_file.text = "taiwan_draft"
	_file.max_length = 64
	_file.tooltip_text = "保存／另存檔名（user://map_editor/drafts/，不含副檔名）"
	row.add_child(_file)
	_open_file = LineEdit.new()
	var open_label := Label.new()
	open_label.text = "開啟："
	row.add_child(open_label)
	_open_file.name = "OpenDraftFile"
	_open_file.text = "taiwan_draft"
	_open_file.max_length = 64
	_open_file.tooltip_text = "待開啟草稿檔名；不作為目前作品保存位置"
	row.add_child(_open_file)
	_sites = OptionButton.new()
	_sites.name = "StandardSite"
	row.add_child(_sites)
	_button(row, "新建標準候選", "NewWork", func() -> void:
		if _sites.selected >= 0 and _sites.selected < _samples.size():
			var site := _samples[_sites.selected]
			request_action(func() -> void: new_work(site)))
	_button(row, "開啟草稿", "OpenWork", _request_open_work)
	_button(row, "保存草稿", "SaveWork", func() -> void: save_work())
	var play := _button(row, "試玩（不可用）", "Playtest", func() -> void: pass)
	play.disabled = true
	play.tooltip_text = PLAYTEST_REASON
	_button(row, "返回", "Back", func() -> void: request_action(_return_to_menu))
	_status = Label.new()
	_status.name = "AuthorStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var reason := Label.new()
	reason.text = PLAYTEST_REASON
	column.add_child(reason)
	var history_row: HBoxContainer = HBoxContainer.new()
	column.add_child(history_row)
	_button(history_row, "復原", "UndoWork", func() -> void: undo_work())
	_button(history_row, "重做", "RedoWork", func() -> void: redo_work())
	_build_terrain_form(column)
	_build_resource_form(column)
	_build_resource_state_form(column)
	_build_building_form(column)
	_build_family_form(column)
	_canvas = Control.new()
	_canvas.name = "AuthorCanvas"
	_canvas.clip_contents = true
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_map_input)
	_canvas.resized.connect(_fit_view)
	column.add_child(_canvas)
	_renderer = TerrainRenderer.new()
	_renderer.name = "TerrainRenderer"
	_canvas.add_child(_renderer)
	_resources = SiteResourceView.new()
	_resources.name = "SiteResources"
	_renderer.add_child(_resources)
	_unsaved = ConfirmationDialog.new()
	_unsaved.name = "UnsavedWork"
	_unsaved.title = "草稿尚未保存"
	_unsaved.dialog_text = "保存後繼續、放棄修改或取消本次操作。"
	_unsaved.get_ok_button().text = "保存"
	_unsaved.get_cancel_button().text = "取消"
	_unsaved.add_button("放棄", true, "discard")
	_unsaved.confirmed.connect(func() -> void:
		if save_current_work(): _continue_action()
		else: _next_action = Callable())
	_unsaved.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			_unsaved.hide()
			_continue_action())
	_unsaved.canceled.connect(func() -> void: _next_action = Callable())
	add_child(_unsaved)

func _button(parent: Node, text: String, node_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func new_work(site: Vector2i) -> bool:
	if site not in _samples: return false
	var candidate := {"format": 1, "kind": "fixed_tw_editor_draft", "name": "台灣作品",
		"manifest": Data.DEFAULT_MANIFEST, "source_sha256": source.manifest_hash,
		"site": [site.x, site.y], "revision": 1}
	return _accept_work(candidate, false)

func validate_work(value: Variant) -> bool:
	if not value is Dictionary or not Adapter.author_integer(value.get("format"), 1, 4): return false
	var version: int = int(value.format)
	if value.size() != (7 if version == 1 else (8 if version == 2 else (10 if version == 3 else 11))): return false
	for key: String in ["format", "kind", "name", "manifest", "source_sha256", "site", "revision"]:
		if not value.has(key): return false
	if version >= 2 and not source.author_static_valid(value.get("terrain_static")): return false
	if version >= 3:
		if not Env.resource_integer(value.get("resource_highwater"), 0, 2147483646) or not value.get("initial_state") is Dictionary: return false
		for key: String in value.terrain_static.resources:
			if key.begins_with("author_resource:") and int(key.get_slice(":", 1)) > int(value.resource_highwater): return false
	elif version == 2 and not value.terrain_static.resources.is_empty(): return false
	if version == 4:
		if not Env.resource_integer(value.get("feature_highwater"), 0, 999999): return false
		if not value.initial_state.get("features", {}) is Dictionary: return false
		for key: Variant in value.initial_state.get("features", {}):
			if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 1 or int(key) > int(value.feature_highwater): return false
	if not value.kind is String or value.kind != "fixed_tw_editor_draft": return false
	if not Data._author_text_valid(value.name, 64, true): return false
	if not value.manifest is String or not Adapter.author_digest_valid(value.source_sha256): return false
	if value.manifest != Data.DEFAULT_MANIFEST or value.source_sha256 != source.manifest_hash: return false
	if not Adapter.author_integer(value.revision, 1, 2147483647) or not Adapter.author_pair_valid(value.site, 0, 1000000): return false
	return Vector2i(int(value.site[0]), int(value.site[1])) in _samples


func _accept_work(value: Dictionary, saved: bool, keep_file: bool = false) -> bool:
	var prepared: Dictionary = _prepare_work(value)
	if not bool(prepared.get("ok", false)):
		_status.text = "草稿格式、來源或候選非法；作品、保存位置與歷史保持原狀。"
		return false
	_publish_work(prepared)
	if saved: _saved_content = _content()
	elif not keep_file: _saved_content = ""
	if not saved and not keep_file: _saved_path = ""
	_clear_work_history()
	_refresh_status()
	return true

func _rename_work(value: String) -> void:
	if draft.is_empty() or str(draft.name) == value: return
	var next: Dictionary = draft.duplicate(true)
	next.name = value
	if int(next.revision) < 2147483647:
		next.revision = int(next.revision) + 1
		if _commit_work(next, "作品名稱"): return
	_name.set_block_signals(true)
	_name.text = str(draft.name)
	_name.set_block_signals(false)
	_status.text = "名稱或修訂非法；未變更作品與歷史。"

func _content() -> String:
	return JSON.stringify(draft, "", true, true)

func is_dirty() -> bool:
	return not draft.is_empty() and _content() != _saved_content

func _draft_path() -> String:
	return _path_for_id(_file.text)

func _path_for_id(name: String) -> String:
	if not Adapter.author_id_valid(name): return ""
	return DRAFT_ROOT.path_join(name + ".json")

func save_work() -> bool:
	return _save_to_path(_draft_path())

func save_current_work() -> bool:
	if _saved_path.is_empty():
		_status.text = "新作品尚無保存位置；請取消本次操作，先用保存／另存檔名保存草稿。"
		return false
	return _save_to_path(_saved_path)

func _save_to_path(path: String) -> bool:
	if path.is_empty() or not validate_work(draft):
		_status.text = "名稱、檔名或草稿無效；沒有保存。"
		return false
	if not bool(_prepare_work(draft).get("ok", false)): return false
	var text := _content()
	if text.to_utf8_buffer().size() > MAX_DRAFT_BYTES: return false
	if DirAccess.make_dir_recursive_absolute(DRAFT_ROOT) != OK: return false
	# Commit-last replacement; a failed write never truncates the saved draft.
	var temporary := path + ".tmp"
	var backup := path + ".bak"
	if FileAccess.file_exists(temporary) or FileAccess.file_exists(backup):
		_status.text = "草稿有未完成保存檔；請保留並另選檔名。"
		return false
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(temporary) != text:
		_status.text = "草稿寫入失敗；原檔與現有內容保留。"
		return false
	var existed := FileAccess.file_exists(path)
	if existed and DirAccess.rename_absolute(path, backup) != OK: return false
	if DirAccess.rename_absolute(temporary, path) != OK:
		if existed:
			var restored := DirAccess.rename_absolute(backup, path)
			if restored != OK: _status.text = "保存失敗；原檔保留於 .bak，請勿刪除。"
		return false
	if existed:
		var removed := DirAccess.remove_absolute(backup)
		if removed != OK: _status.text = "草稿已保存；舊檔仍保留於 .bak。"
	_saved_content = text
	_saved_path = path
	_refresh_status()
	return true

func _request_open_work() -> void:
	var path := _path_for_id(_open_file.text)
	if path.is_empty():
		_status.text = "待開啟檔名無效；目前作品保持原狀。"
		return
	request_action(func() -> void: _open_work(path))

func _open_work(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ) if not path.is_empty() else null
	if file == null:
		_status.text = "草稿無法開啟；目前作品保持原狀。"
		return
	if file.get_length() > MAX_DRAFT_BYTES:
		file.close()
		_status.text = "草稿超出大小限制；未讀取。"
		return
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not validate_work(decoded):
		_status.text = "草稿格式或來源不符；原檔與目前作品保留。"
		return
	if _accept_work(decoded, true):
		_saved_path = path
		_file.text = path.get_file().get_basename()
		_refresh_status()

func request_action(action: Callable) -> void:
	if _unsaved.visible: return
	_dragging = false
	if is_dirty():
		_next_action = action
		_unsaved.popup_centered()
	else: action.call()

func _continue_action() -> void:
	var action := _next_action
	_next_action = Callable()
	if action.is_valid(): action.call()

func _return_to_menu() -> void:
	get_tree().change_scene_to_file(Entry.MAIN_MENU)

func _refresh_status() -> void:
	if draft.is_empty(): return
	var site := Vector2i(int(draft.site[0]), int(draft.site[1]))
	_status.text = "%s%s・%s・來源 %s・base（非作者 current）・修訂 %d\n原高程／scope／quality 不變；2m 資源配置為遊戲規則。拖曳平移・滾輪縮放・Ctrl+S 保存・Ctrl+O 開啟。" % [
		str(draft.name), " * 未保存" if is_dirty() else " 已保存", Grid.site_id(str(source.manifest.atlas_id), site),
		source.manifest_hash.left(12), int(draft.revision)]
	_status.text += "\n目前保存位置：" + (_saved_path if not _saved_path.is_empty() else "尚未保存；切換前請先明示保存／另存")

func _fit_view() -> void:
	if _canvas == null or terrain == null or _canvas.size.x <= 0: return
	_scale = clampf(minf(_canvas.size.x, _canvas.size.y) / (100.0 * TerrainRenderer.CELL_PIXELS), 0.02, 2.0)
	_offset = (_canvas.size - Vector2(terrain.size) * TerrainRenderer.CELL_PIXELS * _scale) * 0.5
	_transform_view()

func _transform_view() -> void:
	_renderer.position = _offset
	_renderer.scale = Vector2.ONE * _scale

func _text_focus() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit or focus is SpinBox

func _map_input(event: InputEvent) -> void:
	if _text_focus():
		if event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			get_viewport().gui_get_focus_owner().release_focus()
		_canvas.accept_event()
		_dragging = false
		return
	if _unsaved.visible or terrain == null:
		_dragging = false
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT: _dragging = button.pressed
		elif button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var next := clampf(_scale * (1.25 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 0.02, 2.0)
			_offset = button.position - (button.position - _offset) * next / _scale
			_scale = next
	elif event is InputEventMouseMotion and _dragging:
		_offset += (event as InputEventMouseMotion).relative
	_transform_view()
	_canvas.accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.is_pressed(): _dragging = false
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and not _unsaved.visible:
		var key := event as InputEventKey
		if key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
			if key.keycode == KEY_S:
				save_work()
				get_viewport().set_input_as_handled()
			elif key.keycode == KEY_Z and not _text_focus():
				if key.shift_pressed: redo_work()
				else: undo_work()
				get_viewport().set_input_as_handled()
			elif key.keycode == KEY_Y and not _text_focus():
				redo_work()
				get_viewport().set_input_as_handled()
			elif key.keycode == KEY_O and not _text_focus():
				_request_open_work()
				get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _dragging = false
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_history): _history.free()

var _terrain_fields: Dictionary = {}
var _cell_x: SpinBox
var _cell_y: SpinBox
var _water_permission: CheckBox

static func empty_terrain_static() -> Dictionary:
	return {"format": 2, "terrain": {}, "resources": {}, "water_bodies": {}, "water_permissions": {"cells": [], "bodies": []}}

func set_cell_patch(cell: Vector2i, row: Dictionary, bodies: Dictionary = {}, permitted: bool = false) -> bool:
	if draft.is_empty() or not terrain.contains(cell) or int(draft.revision) == 2147483647: return false
	var value: Dictionary = draft.duplicate(true)
	value.format = maxi(2, int(value.format))
	var raw: Dictionary = value.get("terrain_static", empty_terrain_static()).duplicate(true)
	raw.terrain[str(terrain.index(cell))] = row.duplicate(true)
	for key: String in bodies: raw.water_bodies[key] = bodies[key].duplicate(true)
	var permission: Array = raw.water_permissions.cells
	permission.erase(terrain.index(cell))
	if permitted: permission.append(terrain.index(cell))
	value.terrain_static = raw
	value.revision = int(value.revision) + 1
	return _commit_work(value, "單格地形／水／土地")

func _build_terrain_form(column: Node) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	_cell_x = _terrain_spin(row, "格X", 0, 99)
	_cell_y = _terrain_spin(row, "格Y", 0, 99)
	_cell_x.value_changed.connect(func(_value: float) -> void: _read_terrain_cell())
	_cell_y.value_changed.connect(func(_value: float) -> void: _read_terrain_cell())
	for field: String in ["height", "surface", "water_kind", "water_body", "fertility", "moisture", "drainage", "foundation", "groundwater"]:
		var maximum := 100
		if field == "height": maximum = 5
		elif field == "surface": maximum = 6
		elif field == "water_kind": maximum = 4
		elif field == "water_body": maximum = 2147483646
		_terrain_fields[field] = _terrain_spin(row, field, -1 if field == "water_body" else 0, maximum)
	_water_permission = CheckBox.new()
	_water_permission.text = "明示可航許可"
	_water_permission.tooltip_text = "只授予此真水格；不推定水深，橋占格仍禁止船通行。"
	row.add_child(_water_permission)
	_button(row, "套用單格", "ApplyTerrainCell", _apply_terrain_cell)
	var note: Label = Label.new()
	note.text = "高度0–5／地表0–6／水0–4／土地0–100；新水體ID>=1000000000。單Site，不跨界筆刷。"
	column.add_child(note)

func _terrain_spin(parent: Node, label: String, minimum: int, maximum: int) -> SpinBox:
	var column: VBoxContainer = VBoxContainer.new()
	parent.add_child(column)
	var title: Label = Label.new()
	title.text = label
	column.add_child(title)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	column.add_child(spin)
	return spin

func _read_terrain_cell() -> void:
	if terrain == null or _cell_x == null: return
	var cell: Vector2i = Vector2i(int(_cell_x.value), int(_cell_y.value))
	var index: int = terrain.index(cell)
	for field: String in _terrain_fields:
		var actual: String = "height_levels" if field == "height" else ("surface_types" if field == "surface" else field)
		var array: Variant = terrain.get(actual)
		_terrain_fields[field].value = int(array[index]) if array.size() > index else 0
	var raw: Dictionary = draft.get("terrain_static", {})
	_water_permission.button_pressed = index in raw.get("water_permissions", {}).get("cells", [])

func _apply_terrain_cell() -> void:
	if _unsaved.visible or terrain == null: return
	var row := {}
	for field: String in _terrain_fields: row[field] = int(_terrain_fields[field].value)
	var bodies := {}
	if int(row.water_kind) > 0 and int(row.water_body) >= Data.AUTHOR_BODY_MIN:
		bodies[str(int(row.water_body))] = {"id": "water_%d" % int(row.water_body), "kind": int(row.water_kind)}
	var accepted: bool = set_cell_patch(Vector2i(int(_cell_x.value), int(_cell_y.value)), row, bodies, _water_permission.button_pressed)
	if not accepted: _status.text = "地形／水／土地候選非法或衝突；原草稿及保存位置保持不變。"

const HISTORY_LIMIT := 100
const HISTORY_BYTES := 16777216
var _history: UndoRedo = UndoRedo.new()
var _history_records: Array[Dictionary] = []
var _history_cursor := 0
var _history_ready: Dictionary = {}
var _history_expected := ""


func _prepare_work(value: Dictionary) -> Dictionary:
	if not validate_work(value): return {"ok": false}
	var result: Dictionary
	if int(value.format) >= 2: result = source.make_author_draft(Vector2i(int(value.site[0]), int(value.site[1])), value.terrain_static, int(value.revision))
	else: result = source.make_terrain_data(int(value.site[0]), int(value.site[1]))
	if not bool(result.get("ok", false)) or not result.get("data") is TerrainData: return {"ok": false}
	var candidate: TerrainData = result.data
	if not candidate.site.is_empty(): return {"ok": false}
	var value_copy: Dictionary = value.duplicate(true)
	value_copy.format = int(value_copy.format)
	value_copy.revision = int(value_copy.revision)
	value_copy.site = [int(value_copy.site[0]), int(value_copy.site[1])]
	if int(value_copy.format) >= 2: value_copy.terrain_static = Data.author_static_normalized(value_copy.terrain_static)
	if int(value_copy.format) >= 3:
		value_copy.resource_highwater = int(value_copy.resource_highwater)
		var state: Dictionary = value_copy.initial_state
		if state.is_empty():
			Env.initialize(candidate, str(result.base.site_id))
			if candidate.site.is_empty(): return {"ok": false}
			# Capture-only supplies the original item/holder schemas without creating a world or file.
			candidate.site.world_pin = Data.author_projection_pin(result.base)
			var captured: Dictionary = SiteStore.save(candidate, "", null, false, {}, true)
			candidate.site.erase("world_pin")
			if not bool(captured.get("ok", false)): return {"ok": false}
			state = captured.state
			state.erase("world_pin")
		if state.get("id") != str(result.base.site_id): return {"ok": false}
		if int(value_copy.format) == 4:
			value_copy.feature_highwater = int(value_copy.feature_highwater)
			if not Env.resource_integer(state.get("next_feature"), 1, 1000000): return {"ok": false}
			state.next_feature = maxi(int(state.next_feature), int(value_copy.feature_highwater) + 1)
		var prepared: Dictionary = Env.prepare_author_resource_state(candidate, state)
		if not bool(prepared.get("ok", false)): return {"ok": false}
		candidate = prepared.data
		value_copy.initial_state = prepared.state
		if int(value_copy.format) == 4:
			var buildings: Dictionary = SiteRuntime.validate_author_buildings(candidate)
			if not buildings.ok: return {"ok": false}
	if JSON.stringify(value_copy, "", true, true).to_utf8_buffer().size() > MAX_DRAFT_BYTES: return {"ok": false}
	return {"ok": true, "draft": value_copy, "terrain": candidate}


func _publish_work(prepared: Dictionary) -> void:
	# All fallible source generation and validation happened before history moved.
	draft = prepared.draft
	terrain = prepared.terrain
	_name.set_block_signals(true)
	_name.text = str(draft.name)
	_name.set_block_signals(false)
	_renderer.display(terrain)
	if terrain.site.is_empty(): _resources.display_source(terrain)
	else: _resources.display(terrain)
	_refresh_resources()
	_refresh_buildings()
	_read_terrain_cell()
	_fit_view()
	_history_expected = _content()
	_refresh_status()


func _history_publish() -> void:
	_publish_work(_history_ready)
	_history_ready = {}


func _clear_work_history() -> void:
	_history.clear_history()
	_history_records.clear()
	_history_cursor = 0
	_history_ready = {}
	_history_expected = _content()


func _commit_work(value: Dictionary, label: String) -> bool:
	if draft.is_empty() or _unsaved.visible or _history_expected != _content(): return false
	if int(value.get("resource_highwater", 0)) < int(draft.get("resource_highwater", 0)): return false
	var prepared: Dictionary = _prepare_work(value)
	if not bool(prepared.get("ok", false)): return false
	var record: Dictionary = {"edits": _history_delta(draft, prepared.draft), "label": label}
	var records: Array[Dictionary] = []
	for i: int in range(_history_cursor): records.append(_history_records[i])
	records.append(record)
	if records.size() > HISTORY_LIMIT: records.pop_front()
	if JSON.stringify(records, "", true, true).to_utf8_buffer().size() > HISTORY_BYTES: return false
	_publish_work(prepared)
	_history.max_steps = HISTORY_LIMIT
	_history.create_action(label, UndoRedo.MERGE_DISABLE)
	_history.add_do_method(_history_publish)
	_history.add_undo_method(_history_publish)
	_history.commit_action(false)
	_history_records = records
	_history_cursor = records.size()
	return true


func undo_work() -> bool:
	if _unsaved.visible or _history_cursor <= 0 or not _history.has_undo() or _history_expected != _content(): return false
	var prepared: Dictionary = _prepare_work(_history_value(_history_records[_history_cursor - 1], false))
	if not bool(prepared.get("ok", false)): return false
	_history_ready = prepared
	if not _history.undo():
		_history_ready = {}
		return false
	_history_cursor -= 1
	return true


func redo_work() -> bool:
	if _unsaved.visible or _history_cursor >= _history_records.size() or not _history.has_redo() or _history_expected != _content(): return false
	var prepared: Dictionary = _prepare_work(_history_value(_history_records[_history_cursor], true))
	if not bool(prepared.get("ok", false)): return false
	_history_ready = prepared
	if not _history.redo():
		_history_ready = {}
		return false
	_history_cursor += 1
	return true


const Env = preload("res://scripts/terrain_lab/site_environment.gd")
var _resource_list: OptionButton
var _resource_kind: OptionButton
var _resource_fields: Dictionary = {}
var _resource_cells: LineEdit

func _resource_work() -> Dictionary:
	var value: Dictionary = draft.duplicate(true)
	value.format = maxi(3, int(value.get("format", 1)))
	value.terrain_static = value.get("terrain_static", empty_terrain_static()).duplicate(true)
	value.resource_highwater = int(value.get("resource_highwater", 0))
	value.initial_state = value.get("initial_state", {}).duplicate(true)
	value.revision = int(value.revision) + 1
	return value

func add_resource(row: Dictionary) -> String:
	if draft.is_empty() or int(draft.revision) >= 2147483647: return ""
	var value: Dictionary = _resource_work()
	if int(value.resource_highwater) >= 2147483646: return ""
	value.resource_highwater = int(value.resource_highwater) + 1
	var key: String = "author_resource:%d" % int(value.resource_highwater)
	if terrain.resource_base.has(key): return ""
	value.terrain_static.resources[key] = row.duplicate(true)
	return key if _commit_work(value, "新增資源") else ""

func set_resource(key: String, row: Dictionary) -> bool:
	if terrain == null or not terrain.resource_base.has(key) or int(draft.revision) >= 2147483647: return false
	var previous: Dictionary = terrain.resource_base[key]
	if not Env.resource_definition_shape(row, terrain.size.x * terrain.size.y, true) or int(row.kind) != int(previous.kind): return false
	var value: Dictionary = _resource_work()
	var definition: Dictionary = row.duplicate(true)
	if int(previous.kind) == Env.Kind.WILDLIFE:
		var identity: int = int(previous.get("identity_cell", previous.cell))
		if definition.has("identity_cell") and int(definition.identity_cell) != identity: return false
		definition.identity_cell = identity
	value.terrain_static.resources[key] = definition
	return _commit_work(value, "編輯／搬移資源")

func move_resource(key: String, cell: Vector2i) -> bool:
	if terrain == null or not terrain.contains(cell) or not terrain.resource_base.has(key): return false
	var row: Dictionary = terrain.resource_base[key].duplicate(true)
	var offset: Vector2i = cell - terrain.cell_from_index(int(row.cell))
	var cells: Array[int] = []
	for index: int in row.cells:
		var moved: Vector2i = terrain.cell_from_index(index) + offset
		if not terrain.contains(moved): return false
		cells.append(terrain.index(moved))
	row.cell = terrain.index(cell)
	row.cells = cells
	row.water = int(terrain.water_body[int(row.cell)])
	return set_resource(key, row)

func remove_resource(key: String) -> bool:
	if terrain == null or not terrain.resource_base.has(key) or int(draft.revision) >= 2147483647: return false
	var value: Dictionary = _resource_work()
	if key.begins_with("author_resource:"): value.terrain_static.resources.erase(key)
	else: value.terrain_static.resources[key] = null
	return _commit_work(value, "刪除資源（引用未收束則拒絕）")

func reset_resource(key: String) -> bool:
	if terrain == null or not terrain.resource_base.has(key) or int(draft.revision) >= 2147483647: return false
	var value: Dictionary = _resource_work()
	var target: TerrainData = terrain
	if target.site.is_empty():
		var prepared: Dictionary = _prepare_work(value)
		if not bool(prepared.get("ok", false)): return false
		target = prepared.terrain
	var reset: Dictionary = Env.prepare_author_resource_state(target, target.site, key)
	if not bool(reset.get("ok", false)): return false
	value.initial_state = reset.state
	return _commit_work(value, "重設存量（保留生態與分鐘配額）")

func _build_resource_form(column: Node) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	_resource_list = OptionButton.new()
	_resource_list.name = "ResourceSelection"
	row.add_child(_resource_list)
	_resource_list.item_selected.connect(func(_index: int) -> void: _read_resource())
	_resource_kind = OptionButton.new()
	_resource_kind.name = "ResourceKind"
	for kind: String in Env.NAMES: _resource_kind.add_item(kind)
	row.add_child(_resource_kind)
	for field: String in ["capacity", "variant", "recover", "identity_cell"]:
		_resource_fields[field] = _terrain_spin(row, field, 0 if field != "capacity" else 1, 2 if field == "variant" else (9999 if field == "identity_cell" else 1000000))
	_resource_fields.capacity.value = 20
	_resource_cells = LineEdit.new()
	_resource_cells.name = "ResourceFootprint"
	_resource_cells.placeholder_text = "足跡格號，以逗號分隔；留白使用格X/Y"
	_resource_cells.custom_minimum_size.x = 220
	row.add_child(_resource_cells)
	var actions: HBoxContainer = HBoxContainer.new()
	column.add_child(actions)
	_button(actions, "新增資源", "AddResource", func() -> void: _resource_ui("add"))
	_button(actions, "套用資源", "SetResource", func() -> void: _resource_ui("set"))
	_button(actions, "搬至格X/Y", "MoveResource", func() -> void: _resource_ui("move"))
	_button(actions, "刪除資源", "RemoveResource", func() -> void: _resource_ui("remove"))
	_button(actions, "補滿資源存量", "ResetResource", func() -> void: _resource_ui("reset"))
	_button(actions, "恢復自然來源", "RestoreNaturalResource", func() -> void: _resource_ui("natural"))
	_button(actions, "恢復作者定義", "RestoreResourceDefinition", func() -> void: _resource_ui("definition"))

func _refresh_resources() -> void:
	if _resource_list == null or terrain == null: return
	var selected: String = _selected_resource()
	_resource_list.clear()
	var keys: Array = terrain.resource_base.keys()
	for key: String in draft.get("terrain_static", {}).get("resources", {}):
		if not key.begins_with("author_resource:") and key not in keys: keys.append(key)
	keys.sort()
	for key: String in keys:
		var definition: Dictionary = terrain.resource_base.get(key, {})
		_resource_list.add_item("%s %s" % [key, "已刪除（可恢復自然來源）" if definition.is_empty() else Env.NAMES[int(definition.kind)]])
		var index: int = _resource_list.item_count - 1
		_resource_list.set_item_metadata(index, key)
		if key == selected: _resource_list.select(index)
	_read_resource()

func _selected_resource() -> String:
	if _resource_list == null or _resource_list.selected < 0: return ""
	return str(_resource_list.get_item_metadata(_resource_list.selected))

func _read_resource() -> void:
	var key: String = _selected_resource()
	if terrain == null or not terrain.resource_base.has(key): return
	var definition: Dictionary = terrain.resource_base[key]
	_resource_kind.select(int(definition.kind))
	for field: String in _resource_fields:
		_resource_fields[field].value = int(definition.get(field, definition.cell))
	var cells: PackedStringArray = []
	for index: int in definition.cells: cells.append(str(index))
	_resource_cells.text = ",".join(cells)
	_cell_x.value = terrain.cell_from_index(int(definition.cell)).x
	_cell_y.value = terrain.cell_from_index(int(definition.cell)).y
	_read_resource_initial_state(key)

func _resource_ui(action: String) -> void:
	if terrain == null or _unsaved.visible: return
	var key: String = _selected_resource()
	var accepted: bool = false
	var cell: Vector2i = Vector2i(int(_cell_x.value), int(_cell_y.value))
	if action == "remove": accepted = remove_resource(key)
	elif action == "reset": accepted = reset_resource(key)
	elif action == "move": accepted = move_resource(key, cell)
	elif action == "natural": accepted = restore_natural_resource(key)
	elif action == "definition": accepted = restore_resource_definition(key)
	else:
		var cells: Array[int] = []
		if _resource_cells.text.strip_edges().is_empty(): cells.append(terrain.index(cell))
		else:
			for token: String in _resource_cells.text.split(","):
				var value: String = token.strip_edges()
				if not value.is_valid_int() or str(int(value)) != value: return
				cells.append(int(value))
		var kind: int = _resource_kind.selected
		var row: Dictionary = {"kind": kind, "cell": terrain.index(cell), "cells": cells,
			"capacity": int(_resource_fields.capacity.value), "variant": int(_resource_fields.variant.value),
			"recover": int(_resource_fields.recover.value), "blocks": kind in [Env.Kind.TIMBER, Env.Kind.STONE],
			"water": int(terrain.water_body[terrain.index(cell)])}
		if kind == Env.Kind.WILDLIFE: row.identity_cell = int(_resource_fields.identity_cell.value)
		accepted = not add_resource(row).is_empty() if action == "add" else set_resource(key, row)
	if not accepted: _status.text = "資源候選非法或仍有引用；草稿、ID、歷史與原檔保持不變。"

func _history_delta(before: Dictionary, after: Dictionary, path: Array = []) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var keys: Array = before.keys()
	for key: Variant in after:
		if not before.has(key): keys.append(key)
	for key: Variant in keys:
		var at: Array = path.duplicate()
		at.append(key)
		# Keep dictionary key order and types when a structural edit is undone.
		if before.has(key) and after.has(key) and before[key] is Dictionary and after[key] is Dictionary and var_to_bytes(before[key].keys()) == var_to_bytes(after[key].keys()):
			changes.append_array(_history_delta(before[key], after[key], at))
		elif not before.has(key) or not after.has(key) or var_to_bytes(before[key]) != var_to_bytes(after[key]):
			changes.append({"path": at, "before_present": before.has(key), "after_present": after.has(key),
				"before": before.get(key), "after": after.get(key)})
	return changes


func _history_value(record: Dictionary, forward: bool) -> Dictionary:
	var value: Dictionary = draft.duplicate(true)
	var side: String = "after" if forward else "before"
	for change: Dictionary in record.edits:
		var target: Dictionary = value
		for depth: int in range(change.path.size() - 1): target = target[change.path[depth]]
		var key: Variant = change.path.back()
		if bool(change[side + "_present"]):
			var restored: Variant = change[side]
			target[key] = restored.duplicate(true) if restored is Dictionary or restored is Array else restored
		else: target.erase(key)
	# Allocation history survives undo and discarded redo branches, including a legacy first edit.
	if int(draft.get("resource_highwater", 0)) > int(value.get("resource_highwater", 0)):
		value.format = maxi(3, int(value.get("format", 1)))
		value.resource_highwater = int(draft.resource_highwater)
		value.terrain_static = value.get("terrain_static", empty_terrain_static())
		value.initial_state = value.get("initial_state", {})
	if draft.has("feature_highwater"):
		value.format = 4
		value["feature_highwater"] = maxi(int(draft.feature_highwater), int(value.get("feature_highwater", 0)))
		value["resource_highwater"] = maxi(int(draft.get("resource_highwater", 0)), int(value.get("resource_highwater", 0)))
		value["terrain_static"] = value.get("terrain_static", empty_terrain_static())
		value["initial_state"] = value.get("initial_state", {})
	return value


var _resource_state_fields: Dictionary = {}
var _resource_cleared: CheckBox
var _resource_discovered: CheckBox

func set_resource_initial_state(key: String, fields: Dictionary) -> bool:
	if terrain == null or not terrain.resource_base.has(key) or fields.is_empty() or int(draft.revision) >= 2147483647: return false
	var definition: Dictionary = terrain.resource_base[key]
	for field: Variant in fields:
		if field in ["cleared", "discovered"]:
			if not fields[field] is bool: return false
		elif field == "remaining":
			if not Env.resource_integer(fields[field], 0, int(definition.capacity)): return false
		elif field == "next_recovery":
			if not Env.resource_integer(fields[field], -1, 1100000000): return false
		elif field == "used":
			if int(definition.kind) != Env.Kind.SALT or not (fields[field] is int or fields[field] is float) or not is_finite(float(fields[field])) or float(fields[field]) < 0.0 or float(fields[field]) > float(definition.capacity): return false
		elif field == "used_minute":
			if int(definition.kind) != Env.Kind.SALT or not Env.resource_integer(fields[field], 0, 1000000000): return false
		else: return false
	var value: Dictionary = _resource_work()
	if value.initial_state.is_empty():
		var prepared: Dictionary = _prepare_work(value)
		if not bool(prepared.get("ok", false)): return false
		value.initial_state = prepared.draft.initial_state
	var candidate: TerrainData = Env.navigation_for_state(terrain, value.initial_state)
	# Typed input is admitted before the original change owner derives population latches.
	Env.change(candidate, key, fields)
	value.initial_state = candidate.site
	return _commit_work(value, "編輯資源初始狀態")

func restore_natural_resource(key: String) -> bool:
	if draft.is_empty() or not Env.resource_key_valid(key) or key.begins_with("author_resource:") or int(draft.revision) >= 2147483647: return false
	var raw: Dictionary = draft.get("terrain_static", {})
	if not raw.get("resources", {}).has(key): return false
	var value: Dictionary = _resource_work()
	value.terrain_static.resources.erase(key)
	# Keep every initial delta/reference; a mismatch with natural capacity/habitat must refuse.
	return _commit_work(value, "恢復自然來源（移除作者覆寫）")

func restore_resource_definition(key: String) -> bool:
	if terrain == null or not terrain.resource_base.has(key) or int(draft.revision) >= 2147483647: return false
	var value: Dictionary = _resource_work()
	var target: TerrainData = terrain
	if target.site.is_empty():
		var prepared: Dictionary = _prepare_work(value)
		if not bool(prepared.get("ok", false)): return false
		target = prepared.terrain
	var restored: Dictionary = Env.prepare_author_resource_state(target, target.site, key)
	if not bool(restored.get("ok", false)): return false
	var delta: Dictionary = restored.state.changes.get(key, {}).duplicate(true)
	# Clear only initial operational overrides; minute quota and ecology/management stay.
	for field: String in ["remaining", "cleared", "discovered", "next_recovery"]: delta.erase(field)
	if delta.is_empty(): restored.state.changes.erase(key)
	else: restored.state.changes[key] = delta
	value.initial_state = restored.state
	return _commit_work(value, "恢復作者定義（保留管理與配額）")

func _build_resource_state_form(column: Node) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	_resource_state_fields.remaining = _terrain_spin(row, "初始剩餘量", 0, 1000000)
	_resource_state_fields.next_recovery = _terrain_spin(row, "下次恢復分鐘（-1停排）", -1, 1100000000)
	_resource_state_fields.used = _terrain_spin(row, "鹽：本分鐘已用", 0, 1000000)
	_resource_state_fields.used.step = 0.0
	_resource_state_fields.used_minute = _terrain_spin(row, "鹽：使用分鐘", 0, 1000000000)
	_resource_cleared = CheckBox.new()
	_resource_cleared.text = "初始已清除"
	row.add_child(_resource_cleared)
	_resource_discovered = CheckBox.new()
	_resource_discovered.text = "初始已發現"
	row.add_child(_resource_discovered)
	_button(row, "套用初始狀態", "ApplyResourceInitialState", _apply_resource_initial_state)

func _read_resource_initial_state(key: String) -> void:
	if terrain == null or not terrain.resource_base.has(key) or _resource_state_fields.is_empty(): return
	var resource: Dictionary = Env.resource(terrain, key)
	_resource_state_fields.remaining.max_value = int(resource.capacity)
	_resource_state_fields.remaining.value = int(resource.remaining)
	_resource_state_fields.next_recovery.value = int(resource.next_recovery)
	_resource_state_fields.used.max_value = int(resource.capacity)
	_resource_state_fields.used.value = float(resource.get("used", 0.0))
	# SpinBox refreshes its text on draw; author reads must also work before drawing.
	_resource_state_fields.used.get_line_edit().text = String.num(_resource_state_fields.used.value, 16)
	_resource_state_fields.used_minute.value = maxi(0, int(resource.get("used_minute", terrain.site.get("minute", 0))))
	_resource_state_fields.used.editable = int(resource.kind) == Env.Kind.SALT
	_resource_state_fields.used_minute.editable = int(resource.kind) == Env.Kind.SALT
	_resource_cleared.button_pressed = bool(resource.cleared)
	_resource_discovered.button_pressed = bool(resource.discovered)

func _apply_resource_initial_state() -> void:
	if terrain == null or _unsaved.visible: return
	var key: String = _selected_resource()
	if not terrain.resource_base.has(key): return
	var fields: Dictionary = {"remaining": int(_resource_state_fields.remaining.value),
		"cleared": _resource_cleared.button_pressed, "discovered": _resource_discovered.button_pressed,
		"next_recovery": int(_resource_state_fields.next_recovery.value)}
	if int(terrain.resource_base[key].kind) == Env.Kind.SALT:
		# Initial-state field keys must stay String for the original Store schema.
		fields["used"] = float(_resource_state_fields.used.value)
		fields["used_minute"] = int(_resource_state_fields.used_minute.value)
	if not set_resource_initial_state(key, fields): _status.text = "初始狀態與容量／排程／分鐘配額／引用不符；作品與歷史保持原狀。"

var _building_list: OptionButton
var _building_kind: OptionButton
var _building_quarter: OptionButton
var _building_material: OptionButton
var _building_variant: OptionButton
var _building_camp: OptionButton
var _building_width: SpinBox
var _building_height: SpinBox
var _building_launch_x: SpinBox
var _building_launch_y: SpinBox
var _building_resource: OptionButton
var _building_stock: SpinBox
var _building_owner: SpinBox

## P4 S4B: the family panel. The family lives in the draft initial state where a Site keeps it.
## Each action builds a candidate from the committed draft, checks it (roster planner or name
## candidate, plus the original-person check), and commits through the same path as building
## edits. A refusal changes nothing.
var _family_name: LineEdit
var _family_person: SpinBox
var _family_summary: Label

func _family_work() -> Dictionary:
	var prepared: Dictionary = _prepare_work(_resource_work())
	if not bool(prepared.get("ok", false)): return {}
	var value: Dictionary = prepared.draft
	value.revision = int(value.revision) + 1
	return value

func _family_ui(action: String) -> void:
	if draft.is_empty() or _unsaved.visible or terrain == null: return
	var value: Dictionary = _family_work()
	if value.is_empty():
		_status.text = "家族未改變：草稿初始狀態無法準備"
		return
	var state: Dictionary = value.initial_state
	var site_id: String = str(state.get("id", ""))
	var family: Variant = state.get("family")
	var result: Dictionary = SiteRuntime.fail("INVALID", "未知家族動作")
	if action == "create":
		if family != null: result = SiteRuntime.fail("ALREADY_EXISTS", "此草稿已有家族；未改變")
		else: result = SiteRuntime.ok("", {"family": {"version": 1, "complete": true, "members": []}})
	elif family == null:
		result = SiteRuntime.fail("NO_TARGET", "請先建立家族；未改變")
	elif action == "name":
		result = FamilyContinuity.name_candidate(family, site_id, int(state.get("next_lineage", 1)), _family_name.text.strip_edges())
	else:
		var members: Array = family.members.duplicate(true)
		if action == "add":
			var added_person: int = int(_family_person.value)
			if not RegionTravel._body_records(state).has(added_person):
				result = SiteRuntime.fail("NO_TARGET", "原人物不在此草稿初始狀態中；未改變")
			else:
				members.append({"site_id": site_id, "person_id": added_person, "path": "", "label": "原人物 #%d" % added_person, "age_years": -1})
				result = FamilyContinuity.roster_plan(family, site_id, members)
		elif action == "remove":
			var removed_person: int = int(_family_person.value)
			var kept: Array = []
			for member: Dictionary in members:
				if int(member.person_id) != removed_person: kept.append(member)
			if kept.size() == members.size(): result = SiteRuntime.fail("NO_TARGET", "此人不在家族名冊中；未改變")
			else: result = FamilyContinuity.roster_plan(family, site_id, kept)
	if not bool(result.get("ok", false)):
		_status.text = "家族未改變：" + str(result.get("message", ""))
		return
	var candidate: Dictionary = result.family
	value.initial_state.family = candidate
	if action == "name" and int(candidate.version) == 4 and (family == null or int(family.version) != 4):
		value.initial_state.next_lineage = int(candidate.lineage_id) + 1
	if not _commit_work(value, "家族：" + action):
		_status.text = "家族未改變：候選或歷史預驗拒絕；作品與游標保持不變"
		return
	_read_family()
	_status.text = "家族名冊已更新"

func _read_family() -> void:
	if _family_summary == null or draft.is_empty(): return
	var family: Variant = draft.get("initial_state", {}).get("family")
	if family == null:
		_family_summary.text = "家族：尚未建立"
		return
	var label: String = "家族 v%d" % int(family.version)
	if int(family.version) == 4: label += "「%s」" % str(family.name)
	_family_summary.text = "%s：%d 人" % [label, family.members.size()]

## P4 S4B: the panel (toggle, name field, person field, create/add/remove/name buttons).
func _build_family_form(column: Node) -> void:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.name = "AuthorFamily"
	panel.visible = false
	_button(column, "家族與人物", "FamilyTools", func() -> void: panel.visible = not panel.visible)
	column.add_child(panel)
	_family_summary = Label.new()
	_family_summary.name = "FamilySummary"
	panel.add_child(_family_summary)
	var name_row: HBoxContainer = HBoxContainer.new()
	panel.add_child(name_row)
	_family_name = LineEdit.new()
	_family_name.name = "FamilyName"
	_family_name.max_length = 64
	_family_name.placeholder_text = "家族名稱（最多 32 字）"
	_family_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_family_name)
	_button(name_row, "設定家族名稱", "FamilySetName", _family_ui.bind("name"))
	var person_row: HBoxContainer = HBoxContainer.new()
	panel.add_child(person_row)
	_family_person = SpinBox.new()
	_family_person.name = "FamilyPerson"
	_family_person.min_value = 1
	_family_person.max_value = 2147483647
	_family_person.step = 1
	_family_person.value = 1
	person_row.add_child(_family_person)
	_button(person_row, "建立空家族", "FamilyCreate", _family_ui.bind("create"))
	_button(person_row, "加入原人物", "FamilyAddMember", _family_ui.bind("add"))
	_button(person_row, "移除成員", "FamilyRemoveMember", _family_ui.bind("remove"))
	_read_family()

func edit_building(action: String, key: String = "", kind: String = "", cells: Array[int] = [], options: Dictionary = {}, cargo: Dictionary = {}) -> Dictionary:
	if draft.is_empty() or _unsaved.visible or int(draft.revision) >= 2147483647: return SiteRuntime.fail("BUSY")
	var value: Dictionary = _resource_work()
	value.format = 4
	value["feature_highwater"] = maxi(int(value.get("feature_highwater", 0)), int(value.initial_state.get("next_feature", 1)) - 1)
	var prepared: Dictionary = _prepare_work(value)
	if not prepared.get("ok", false): return SiteRuntime.fail("INVALID", "作者來源或初始閉包不合法")
	var result: Dictionary = SiteRuntime.prepare_author_building(prepared.terrain, prepared.draft, action, key, kind, cells, options, cargo)
	if not result.ok: return result
	value.initial_state = result.state
	value.feature_highwater = maxi(int(value.feature_highwater), int(result.state.next_feature) - 1)
	var committed: bool = _commit_work(value, "建築／初始配置：" + action)
	if not committed: return SiteRuntime.fail("INVALID", "候選或歷史預驗拒絕；作品與游標保持不變")
	return result


func _building_choice(parent: Node, title: String, node_name: String) -> OptionButton:
	var column: VBoxContainer = VBoxContainer.new()
	parent.add_child(column)
	var label: Label = Label.new()
	label.text = title
	column.add_child(label)
	var choice: OptionButton = OptionButton.new()
	choice.name = node_name
	column.add_child(choice)
	return choice

func _build_building_form(column: Node) -> void:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.name = "AuthorBuildings"
	panel.visible = false
	_button(column, "建築與初始配置", "BuildingTools", func() -> void: panel.visible = not panel.visible)
	column.add_child(panel)
	var row: HBoxContainer = HBoxContainer.new()
	panel.add_child(row)
	_building_list = _building_choice(row, "已放置建築", "BuildingSelection")
	_building_kind = _building_choice(row, "原建築種類", "BuildingKind")
	var kinds: Array = SiteRuntime.FEATURES.keys()
	kinds.sort()
	for kind: String in kinds:
		_building_kind.add_item(str(SiteRuntime.FEATURES[kind].name))
		_building_kind.set_item_metadata(_building_kind.item_count - 1, kind)
	_building_owner = _terrain_spin(row, "建物管理方（不改居民國籍）", 0, 100000000)
	_building_quarter = _building_choice(row, "面向", "BuildingQuarter")
	for quarter: int in range(4): _building_quarter.add_item(str(quarter * 90) + "°")
	_building_width = _terrain_spin(row, "寬", 1, 50)
	_building_height = _terrain_spin(row, "深", 1, 50)
	var attributes: HBoxContainer = HBoxContainer.new()
	panel.add_child(attributes)
	_building_material = _building_choice(attributes, "原材質", "BuildingMaterial")
	_building_variant = _building_choice(attributes, "住宅版型", "BuildingVariant")
	_building_camp = _building_choice(attributes, "軍營型式", "BuildingCampType")
	for camp: String in SiteRuntime.BARRACKS_TYPES:
		_building_camp.add_item(str(SiteRuntime.BARRACKS_TYPES[camp].name))
		_building_camp.set_item_metadata(_building_camp.item_count - 1, camp)
	_building_launch_x = _terrain_spin(attributes, "原泊位 X", 0, 99)
	_building_launch_y = _terrain_spin(attributes, "原泊位 Y", 0, 99)
	var actions: HBoxContainer = HBoxContainer.new()
	panel.add_child(actions)
	for entry: Array in [["於格X/Y放置完工建築", "PlaceBuilding", "place"], ["空建物搬至格X/Y", "MoveBuilding", "move"], ["複製布局至格X/Y", "CopyBuilding", "copy"], ["刪除／回收承載資產", "DeleteBuilding", "delete"], ["變更管理方", "ManageBuilding", "owner"]]:
		_button(actions, str(entry[0]), str(entry[1]), _building_ui.bind(str(entry[2])))
	var stock: HBoxContainer = HBoxContainer.new()
	panel.add_child(stock)
	_building_resource = _building_choice(stock, "庫房原資源", "BuildingStockResource")
	var resources: Array = Env.ITEM_NAMES.keys()
	resources.sort()
	for item: String in resources:
		_building_resource.add_item(str(Env.ITEM_NAMES[item]))
		_building_resource.set_item_metadata(_building_resource.item_count - 1, item)
	_building_stock = _terrain_spin(stock, "此資源初始數量（0移除）", 0, 1000000)
	_building_stock.name = "BuildingInitialStock"
	_button(stock, "設定此項庫房初始資源", "SetBuildingStock", _building_ui.bind("stock"))
	_building_resource.item_selected.connect(_read_building_stock)
	_building_list.item_selected.connect(func(_index: int) -> void: _read_building())
	_building_kind.item_selected.connect(_building_kind_changed)
	_building_quarter.item_selected.connect(_building_dimensions_changed)
	_building_material.item_selected.connect(_building_dimensions_changed)
	_building_variant.item_selected.connect(_building_dimensions_changed)
	_building_camp.item_selected.connect(_building_dimensions_changed)
	var note: Label = Label.new()
	note.text = "位置沿上方格X/Y；尺寸和屬性沿原目錄。完工材料已耗用，複製不帶人／庫貨／實物。整地用地形工具；測量／渠道待原人物科技閉包。"
	panel.add_child(note)
	_building_kind_changed(0)

func _building_kind_changed(_index: int) -> void:
	var kind: String = str(_building_kind.get_item_metadata(_building_kind.selected))
	var spec: Dictionary = SiteRuntime.building_spec(kind, {"quarter": _building_quarter.selected})
	if not spec.ok: return
	_building_material.clear()
	for material: String in spec.materials:
		_building_material.add_item("木" if material == "wood" else "石")
		_building_material.set_item_metadata(_building_material.item_count - 1, material)
	_building_variant.clear()
	for variant: String in spec.variants:
		_building_variant.add_item(variant)
		_building_variant.set_item_metadata(_building_variant.item_count - 1, variant)
	if not spec.variants.is_empty(): _building_variant.select(maxi(0, spec.variants.find(str(spec.options.get("variant", "standard")))))
	(_building_material.get_parent() as Control).visible = spec.materials.size() > 1
	(_building_variant.get_parent() as Control).visible = not spec.variants.is_empty()
	(_building_camp.get_parent() as Control).visible = kind == "barracks"
	(_building_launch_x.get_parent() as Control).visible = kind in SiteRuntime.WATERFRONT_KINDS
	(_building_launch_y.get_parent() as Control).visible = kind in SiteRuntime.WATERFRONT_KINDS
	_building_dimensions_changed(0)

func _building_dimensions_changed(_index: int) -> void:
	var kind: String = str(_building_kind.get_item_metadata(_building_kind.selected))
	var options: Dictionary = {"quarter": _building_quarter.selected}
	if kind == "house" and _building_variant.selected >= 0: options["variant"] = str(_building_variant.get_item_metadata(_building_variant.selected))
	var spec: Dictionary = SiteRuntime.building_spec(kind, options)
	if not spec.ok: return
	var fixed: bool = str(spec.placement) == "fixed"
	var minimum: Vector2i = spec.size if fixed else spec.min_size
	var maximum: Vector2i = spec.size if fixed else spec.max_size
	_building_width.min_value = minimum.x
	_building_width.max_value = maximum.x
	_building_height.min_value = minimum.y
	_building_height.max_value = maximum.y
	_building_width.value = minimum.x
	_building_height.value = minimum.y
	_building_width.editable = not fixed
	_building_height.editable = not fixed

func _selected_building() -> String:
	return "" if _building_list == null or _building_list.selected < 0 else str(_building_list.get_item_metadata(_building_list.selected))

func _refresh_buildings() -> void:
	if _building_list == null or terrain == null: return
	var selected: String = _selected_building()
	_building_list.clear()
	var keys: Array = terrain.site.get("features", {}).keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		_building_list.add_item("%s %s" % [key, str(SiteRuntime.FEATURES[str(terrain.site.features[key].kind)].name)])
		_building_list.set_item_metadata(_building_list.item_count - 1, key)
		if key == selected: _building_list.select(_building_list.item_count - 1)
	_read_building()

func _read_building() -> void:
	var key: String = _selected_building()
	if terrain == null or not terrain.site.get("features", {}).has(key): return
	var feature: Dictionary = terrain.site.features[key]
	for index: int in range(_building_kind.item_count):
		if str(_building_kind.get_item_metadata(index)) == str(feature.kind): _building_kind.select(index)
	_building_quarter.select(int(feature.get("quarter", 0)))
	_building_kind_changed(0)
	for pair: Array in [[_building_material, str(feature.get("material", ""))], [_building_variant, str(feature.get("variant", ""))], [_building_camp, str(feature.get("camp_type", ""))]]:
		var choice: OptionButton = pair[0]
		for index: int in range(choice.item_count):
			if str(choice.get_item_metadata(index)) == str(pair[1]): choice.select(index)
	_building_owner.value = maxi(0, int(feature.get("owner_faction", -1)))
	var bounds: Rect2i = SiteRuntime._cell_bounds(terrain, feature.cells)
	_building_width.value = bounds.size.x
	_building_height.value = bounds.size.y
	if feature.has("launch_cell"):
		var launch: Vector2i = terrain.cell_from_index(int(feature.launch_cell))
		_building_launch_x.value = launch.x
		_building_launch_y.value = launch.y
	_read_building_stock(0)

func _read_building_stock(_index: int) -> void:
	if terrain == null or _building_resource.selected < 0: return
	var item: String = str(_building_resource.get_item_metadata(_building_resource.selected))
	_building_stock.value = int(terrain.site.get("stockpiles", {}).get(_selected_building(), {}).get("cargo", {}).get(item, 0))

func _building_ui(action: String) -> void:
	if terrain == null or _unsaved.visible: return
	var key: String = _selected_building()
	var kind: String = str(_building_kind.get_item_metadata(_building_kind.selected))
	var options: Dictionary = {"owner_faction": int(_building_owner.value), "quarter": _building_quarter.selected}
	if _building_material.selected >= 0: options["material"] = str(_building_material.get_item_metadata(_building_material.selected))
	if kind == "house" and _building_variant.selected >= 0: options["variant"] = str(_building_variant.get_item_metadata(_building_variant.selected))
	if kind == "barracks": options["camp_type"] = str(_building_camp.get_item_metadata(_building_camp.selected))
	if kind in SiteRuntime.WATERFRONT_KINDS: options["launch_cell"] = terrain.index(Vector2i(int(_building_launch_x.value), int(_building_launch_y.value)))
	var anchor: Vector2i = Vector2i(int(_cell_x.value), int(_cell_y.value))
	var cells: Array[int] = []
	var cargo: Dictionary = terrain.site.get("stockpiles", {}).get(key, {}).get("cargo", {}).duplicate(true)
	if action == "stock":
		var item: String = str(_building_resource.get_item_metadata(_building_resource.selected))
		if int(_building_stock.value) == 0: cargo.erase(item)
		else: cargo[item] = int(_building_stock.value)
	if action in ["move", "copy"]:
		if not terrain.site.get("features", {}).has(key): return
		var original: Dictionary = terrain.site.features[key]
		var offset: Vector2i = anchor - SiteRuntime._cell_bounds(terrain, original.cells).position
		for index: int in original.cells:
			var cell: Vector2i = terrain.cell_from_index(index) + offset
			if not terrain.contains(cell):
				_status.text = "搬移／複製足跡越界。"
				return
			cells.append(terrain.index(cell))
	elif action == "place":
		var footprint: Dictionary = SiteRuntime.building_cells(terrain, kind, anchor, Vector2i(int(_building_width.value), int(_building_height.value)), options)
		if not footprint.ok:
			_status.text = str(footprint.message)
			return
		cells.assign(footprint.cells)
	var result: Dictionary = edit_building(action, key, kind, cells, options, cargo)
	if result.ok:
		for index: int in range(_building_list.item_count):
			if str(_building_list.get_item_metadata(index)) == str(result.feature): _building_list.select(index)
		_read_building()
	_status.text = str(result.message)
	if result.ok: _status.text += "\n初始總資產：" + SiteRuntime.items_text(result.asset_report.after.resources) + "；實物 " + str(result.asset_report.after.item_ids.size()) + " 件"
