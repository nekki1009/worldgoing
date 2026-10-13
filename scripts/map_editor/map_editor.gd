extends Control
## P1B author host: a source-only candidate, never a normal TerrainLab session.
const Entry = preload("res://scripts/region_lab/region_entry.gd")
const Data = preload("res://scripts/region_lab/region_data.gd")
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Preview = preload("res://scripts/region_lab/region_site_preview.gd")
const DRAFT_ROOT := "user://map_editor/drafts"
const MAX_DRAFT_BYTES := 65536
const PLAYTEST_REASON := "作者初始化尚未實作；目前只能保存草稿，不能建立試玩世界。"
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
	if not value is Dictionary or value.size() != 7: return false
	for key: String in ["format", "kind", "name", "manifest", "source_sha256", "site", "revision"]:
		if not value.has(key): return false
	if not Adapter.author_integer(value.format, 1, 1): return false
	if not value.kind is String or value.kind != "fixed_tw_editor_draft": return false
	if not Data._author_text_valid(value.name, 64, true): return false
	if not value.manifest is String or not Adapter.author_digest_valid(value.source_sha256): return false
	if value.manifest != Data.DEFAULT_MANIFEST or value.source_sha256 != source.manifest_hash: return false
	if not Adapter.author_integer(value.revision, 1, 2147483647) or not Adapter.author_pair_valid(value.site, 0, 1000000): return false
	return Vector2i(int(value.site[0]), int(value.site[1])) in _samples

func _accept_work(value: Dictionary, saved: bool) -> bool:
	if not validate_work(value):
		_status.text = "草稿格式、來源 SHA 或標準 Site 不符；目前作品保持原狀。"
		return false
	var result: Dictionary = source.make_terrain_data(int(value.site[0]), int(value.site[1]))
	if not bool(result.get("ok", false)) or not result.get("data") is TerrainData:
		_status.text = "標準候選讀取失敗；目前作品保持原狀。"
		return false
	var candidate: TerrainData = result.data
	if not candidate.site.is_empty():
		_status.text = "作者候選不可帶玩法 SiteState；未替換目前作品。"
		return false
	terrain = candidate
	draft = value.duplicate(true)
	_name.text = str(draft.name)
	_renderer.display(terrain)
	_resources.display_source(terrain)
	_saved_content = _content() if saved else ""
	if not saved: _saved_path = ""
	_fit_view()
	_refresh_status()
	return true

func _rename_work(value: String) -> void:
	if draft.is_empty(): return
	if str(draft.name) == value: return
	if int(draft.revision) == 2147483647:
		_name.text = str(draft.name)
		_status.text = "草稿修訂已達上限；未套用名稱。"
		return
	draft.name = value
	draft.revision = int(draft.revision) + 1
	_refresh_status()

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
			elif key.keycode == KEY_O and not _text_focus():
				_request_open_work()
				get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _dragging = false
