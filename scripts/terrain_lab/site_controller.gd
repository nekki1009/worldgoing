class_name SiteController
extends Node

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const View = preload("res://scripts/terrain_lab/site_resource_view.gd")
const MODES := ["查看", "手動採集", "工人採集區", "清理區", "勘探區", "建設區", "原測試：放置角色"]
const PANEL_SCALE := 1.35
const PANEL_SPACE := 590.0
var lab: Node2D
var view: Node2D
var panel: PanelContainer
var clock_label: Label
var details: Label
var stock_label: Label
var worker_label: Label
var message: Label
var zones: VBoxContainer
var modes: OptionButton
var kinds: OptionButton
var buildings: OptionButton
var pause_button: Button
var saved_sites: OptionButton
var legend: Label
var selected := Vector2i(-1, -1)
var source_key := ""
var feature_key := ""
var drag_start := Vector2i(-1, -1)
var build_cells: Array[int] = []
var save_path := Store.DEFAULT_PATH
var _ui_elapsed := 0.0
var _work_elapsed := 0.0
var _save_elapsed := 0.0
var _navigation_revision := -1
var _zone_signature := ""
var _exit_pending := false
var _auto_save_blocked := false
var _summary_area := Rect2i()
var _summary_revision := -1
var _summary_text := ""

func setup(scene: Node2D) -> void:
	lab = scene
	view = View.new()
	view.name = "SiteResources"
	lab.add_child(view)
	# Same-row props are behind the existing actors; northern actors still sort behind roofs.
	lab.move_child(view, lab.character.get_index())
	_build_ui()
	lab.character.combat_event.connect(_combat_event)
	lab.npc.combat_event.connect(_combat_event)
	lab.character.cell_blocker = _actor_blocked
	lab.npc.cell_blocker = _actor_blocked
	get_tree().root.size_changed.connect(_layout)
	get_tree().root.close_requested.connect(_request_exit)
	get_tree().auto_accept_quit = false
	lab.get_node("TerrainLabUI").hide()
	_layout()

func bind() -> void:
	var data: TerrainData = lab.terrain
	if not data.site.has("worker_enabled"):
		data.site.worker_enabled = true
	data.site.worker.cell = data.index(lab.npc.terrain_cell)
	view.display(data)
	Runtime.rebuild_water(data)
	_navigation_revision = data.navigation_revision
	selected = data.spawn_cell
	source_key = ""
	feature_key = ""
	build_cells.clear()
	_zone_signature = ""
	_summary_revision = -1
	_work_elapsed = 1.0
	_save_elapsed = 0.0
	get_tree().paused = bool(data.site.paused)
	update_ui()

func _label(parent: Node, value: String, size: int = 17) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 356
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _button(parent: Node, title: String, node_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = title
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _options(parent: Node, values: Array, node_name: String) -> OptionButton:
	var choice := OptionButton.new()
	choice.name = node_name
	choice.fit_to_longest_item = false
	choice.clip_text = true
	choice.add_theme_font_size_override("font_size", 17)
	for value: Variant in values:
		choice.add_item(str(value))
	parent.add_child(choice)
	return choice

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "SiteUI"
	lab.add_child(ui)
	panel = PanelContainer.new()
	panel.name = "SitePanel"
	panel.scale = Vector2.ONE * PANEL_SCALE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1d2c2b")
	style.border_color = Color("526b5d")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	_label(column, "聚落地圖  ·  資源與土地", 25)
	clock_label = _label(column, "", 18)
	var row := HBoxContainer.new()
	column.add_child(row)
	pause_button = _button(row, "暫停", "PauseSite", toggle_pause)
	_button(row, "保存", "SaveSite", save_current)
	_button(row, "載入", "LoadSite", load_current)
	var views := _options(column, View.VIEW_NAMES, "LandView")
	views.item_selected.connect(func(index: int) -> void:
		view.view_mode = index
		view.refresh()
		update_ui())
	legend = _label(column, "", 15)
	modes = _options(column, MODES, "WorkMode")
	modes.item_selected.connect(func(_index: int) -> void:
		build_cells.clear()
		view.selection = Rect2i()
		view.queue_redraw()
		update_ui())
	var names: Array = ["全部天然資源"]
	names.append_array(Env.NAMES)
	kinds = _options(column, names, "ResourceKind")
	kinds.item_selected.connect(func(index: int) -> void:
		view.resource_filter = index - 1
		view.refresh()
		select_cell(selected))
	var feature_names: Array = []
	for definition: Dictionary in Runtime.FEATURES.values():
		feature_names.append(definition.name)
	buildings = _options(column, feature_names, "BuildingKind")
	buildings.item_selected.connect(func(_index: int) -> void: update_ui())
	_label(column, "點選查看；採集／清理／勘探／建設可拖曳框選。\nWASD 移動玩家；滾輪縮放、右鍵拖圖。", 15)
	message = _label(column, "先框選工人採集區，工人會自行採集並回營地交貨。", 16)
	message.modulate = Color("f0d7a0")
	details = _label(column, "")
	_button(column, "手動作業（需走到來源旁）", "ManualHarvest", manual_work)
	_button(column, "玩家向營地交貨", "DepositCargo", func() -> void:
		show_result(Runtime.deposit(lab.terrain, lab.terrain.site.manual.cargo, lab.character.terrain_cell)))
	_button(column, "安排施工（按預覽扣材料）", "BuildFeature", build_selected)
	row = HBoxContainer.new()
	column.add_child(row)
	_button(row, "派工運作", "OperateFeature", func() -> void:
		enable_worker()
		show_result(Runtime.operate_feature(lab.terrain, feature_key)))
	_button(row, "拆除／取消", "CancelFeature", func() -> void:
		show_result(Runtime.cancel_feature(lab.terrain, feature_key)))
	stock_label = _label(column, "")
	worker_label = _label(column, "")
	row = HBoxContainer.new()
	column.add_child(row)
	_button(row, "工人開始", "EnableWorker", enable_worker)
	_button(row, "工人停止", "StopWorker", release_worker)
	_label(column, "工作區（由上而下優先）", 18)
	zones = VBoxContainer.new()
	column.add_child(zones)
	row = HBoxContainer.new()
	column.add_child(row)
	_button(row, "營地近景", "FocusCamp", focus_camp)
	_button(row, "全圖", "FitSite", lab.fit_map)
	var legacy := CheckButton.new()
	legacy.text = "展開原地形／人物／戰鬥測試"
	column.add_child(legacy)
	legacy.toggled.connect(func(enabled: bool) -> void:
		lab.get_node("TerrainLabUI").visible = enabled
		lab.fit_map())
	_label(column, "保存地圖資源、用地與工作；保存不含人物換裝、戰鬥與軍隊。離線期間不增加產量。", 15)
	saved_sites = _options(column, ["已保存地圖"], "SavedSites")
	_button(column, "開啟所選保存地圖", "OpenSavedSite", func() -> void:
		if saved_sites.selected >= 0 and saved_sites.get_item_metadata(saved_sites.selected) != null:
			_load_path(str(saved_sites.get_item_metadata(saved_sites.selected))))
	_refresh_saved_sites()

func _layout() -> void:
	var screen := lab.get_viewport_rect().size
	panel.position = Vector2(maxf(0, screen.x - 412 * PANEL_SCALE - 16), 16)
	panel.size = Vector2(412, maxf(100, (screen.y - 32) / PANEL_SCALE))

func focus_camp() -> void:
	if lab.terrain == null:
		return
	lab.camera.zoom = Vector2.ONE * 0.9
	lab.camera.position = (Vector2(lab.terrain.spawn_cell) + Vector2.ONE * 0.5) * 64 + Vector2(PANEL_SPACE * 0.5 / 0.9, 0)
	lab.camera.force_update_scroll()

func show_result(result: Dictionary) -> void:
	message.text = str(result.get("message", ""))
	update_ui()

func select_cell(cell: Vector2i) -> void:
	var data: TerrainData = lab.terrain
	if not data.contains(cell):
		return
	selected = cell
	source_key = ""
	feature_key = str(data.feature_at[data.index(cell)]) if data.feature_at[data.index(cell)] != 0 else ""
	for key: String in data.resources_at.get(data.index(cell), []):
		if kinds.selected == 0 or int(data.resource_base[key].kind) == kinds.selected - 1:
			source_key = key
			break
	view.selected_resource = source_key
	view.refresh()
	update_ui()

func handle_input(event: InputEvent) -> bool:
	if modes.selected == 6 or lab._npc_target_pending:
		return false
	var area_mode: bool = modes.selected in [2, 3, 4, 5] or (modes.selected == 0 and view.view_mode >= 2)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Vector2i = lab.renderer.pick_cell(event.position)
		if event.pressed:
			if not lab.terrain.contains(cell):
				drag_start = Vector2i(-1, -1)
				return true
			select_cell(cell)
			view.selection = Rect2i(cell, Vector2i.ONE)
			drag_start = cell
			if modes.selected == 1:
				manual_work()
		elif drag_start.x >= 0 and area_mode:
			var area := _rectangle(drag_start, cell)
			view.selection = area
			if modes.selected == 5:
				build_cells.clear()
				if area.get_area() <= 36:
					for y: int in range(area.position.y, area.end.y):
						for x: int in range(area.position.x, area.end.x):
							build_cells.append(lab.terrain.index(Vector2i(x, y)))
				update_ui()
			elif modes.selected in [2, 3, 4]:
				enable_worker()
				show_result(Runtime.add_zone(lab.terrain, area, kinds.selected - 1, ["harvest", "clear", "survey"][modes.selected - 2]))
			else:
				update_ui()
			drag_start = Vector2i(-1, -1)
		view.queue_redraw()
		return true
	if event is InputEventMouseMotion and drag_start.x >= 0 and area_mode:
		view.selection = _rectangle(drag_start, lab.renderer.pick_cell(event.position))
		view.queue_redraw()
		return true
	return false

func _rectangle(a: Vector2i, b: Vector2i) -> Rect2i:
	return Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), Vector2i(absi(a.x - b.x) + 1, absi(a.y - b.y) + 1)).intersection(Rect2i(Vector2i.ZERO, lab.terrain.size))

func manual_work() -> void:
	if get_tree().paused or lab.character.is_moving() or lab.character.action_time > 0 or lab.character.hp <= 0:
		show_result(Runtime.fail("BUSY"))
		return
	show_result(Runtime.begin_manual(lab.terrain, source_key, lab.character.terrain_cell))

func build_selected() -> void:
	enable_worker()
	show_result(Runtime.request_build(lab.terrain, str(Runtime.FEATURES.keys()[buildings.selected]), build_cells, reserves_cell))

func enable_worker() -> void:
	lab.terrain.site.worker_enabled = true
	_work_elapsed = 1.0

func release_worker() -> void:
	lab.terrain.site.worker_enabled = false
	lab.terrain.site.worker.mode = "idle"
	lab.terrain.site.worker.target = ""
	lab.terrain.site.worker.progress = 0.0
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)

func _actor_blocked(cell: Vector2i, requester: Node) -> bool:
	return lab.army.blocks_cell(cell) or (requester != lab.character and lab.character.occupies_cell(cell)) or (requester != lab.npc and lab.npc.occupies_cell(cell))

func _worker_blocked(cell: Vector2i) -> bool:
	return _actor_blocked(cell, lab.npc)

func reserves_cell(cell: Vector2i) -> bool:
	return lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell) or lab.army.reserves_terrain_cell(cell)

func _combat_event(duration: float) -> void:
	if lab.terrain != null:
		Runtime.mark_combat(lab.terrain, duration)

func toggle_pause() -> void:
	lab.terrain.site.paused = not bool(lab.terrain.site.paused)
	get_tree().paused = bool(lab.terrain.site.paused)
	lab._clear_movement_input()
	update_ui()

func tick(delta: float) -> void:
	var data: TerrainData = lab.terrain
	if data == null or data.site.is_empty():
		return
	view.animate(delta)
	_ui_elapsed += delta
	if not bool(data.site.paused):
		_work_elapsed += delta
		_save_elapsed += delta
		var worker: Dictionary = data.site.worker
		worker.cell = data.index(lab.npc.terrain_cell)
		var capable: bool = lab.npc.hp > 0 and lab.npc.action_time <= 0 and not lab.npc.guarding and lab.npc.visible
		var worker_ready := false
		if bool(data.site.worker_enabled) and capable:
			if str(worker.target).is_empty() and lab.npc.command != TerrainTestNPC.Command.STOP:
				lab.npc.issue_command(TerrainTestNPC.Command.STOP)
			if str(worker.target).is_empty() and _work_elapsed >= 0.5:
				Runtime.assign_task(data, Runtime.choose_task(data, lab.npc.terrain_cell, _worker_blocked))
				_work_elapsed = 0.0
			if not str(worker.target).is_empty():
				var goal := data.cell_from_index(int(worker.work_cell))
				if lab.npc.terrain_cell == goal and not lab.npc.is_moving():
					worker.mode = "work"
					worker_ready = true
				elif not lab.npc.is_moving() and _work_elapsed >= 0.5:
					worker.mode = "travel"
					if not lab.npc.issue_command(TerrainTestNPC.Command.MOVE_TO_CELL, goal):
						worker.target = ""
						worker.mode = "idle"
						worker.status = "路線受阻；等待重試"
					_work_elapsed = 0.0
		var manual: Dictionary = data.site.manual
		var manual_ready: bool = not str(manual.target).is_empty() and lab.character.hp > 0 and lab.character.action_time <= 0 and not lab.character.is_moving() and data.index(lab.character.terrain_cell) == int(manual.get("cell", -1))
		if not manual_ready:
			manual.target = ""
			manual.progress = 0.0
		Runtime.advance(data, delta, worker_ready, manual_ready, reserves_cell)
		if _save_elapsed >= 30 and float(data.site.combat_left) <= 0 and not _auto_save_blocked:
			_save_elapsed = 0.0
			save_current()
	if data.navigation_revision != _navigation_revision:
		_navigation_revision = data.navigation_revision
		lab.renderer.redraw()
		lab.army.notify_terrain_changed()
	if not data.site.notices.is_empty():
		message.text = str(data.site.notices.back())
		data.site.notices.clear()
	if _ui_elapsed >= 0.25:
		_ui_elapsed = 0
		update_ui()
	if _exit_pending and float(data.site.combat_left) <= 0:
		_exit_pending = false
		_request_exit()

func _capture_positions() -> void:
	lab.terrain.site.player_cell = lab.terrain.index(lab.character.terrain_cell)
	lab.terrain.site.worker.cell = lab.terrain.index(lab.npc.terrain_cell)

func save_current() -> void:
	_capture_positions()
	var result := Store.save(lab.terrain, save_path)
	if result.ok:
		_auto_save_blocked = false
	show_result(result)

func archive_before_replace() -> bool:
	if lab.terrain == null or lab.terrain.site.is_empty():
		return true
	_capture_positions()
	var result := Store.save(lab.terrain, "user://sites/" + str(lab.terrain.site.id).validate_filename() + ".json")
	show_result(result)
	if result.ok:
		_auto_save_blocked = false
		_refresh_saved_sites()
	return bool(result.ok)

func load_current() -> void:
	_load_path(save_path)

func _load_path(path: String) -> void:
	if lab.terrain != null and float(lab.terrain.site.combat_left) > 0:
		show_result(Runtime.fail("BUSY", "脫戰後才能載入"))
		return
	var result := Store.load_site(path)
	if result.ok:
		if path != save_path and not archive_before_replace():
			return
		lab.bind_terrain(result.data)
		_auto_save_blocked = false
	else:
		_auto_save_blocked = true
		result.message += "；自動保存已暫停，原檔保留"
	show_result(result)

func _refresh_saved_sites() -> void:
	if saved_sites == null:
		return
	saved_sites.clear()
	saved_sites.add_item("已保存地圖")
	var folder := DirAccess.open("user://sites")
	if folder == null:
		return
	for file: String in folder.get_files():
		if not file.ends_with(".json") or file == "current.json":
			continue
		var path := "user://sites/" + file
		var decoded := Store._read(path)
		if decoded.ok:
			saved_sites.add_item("%s · seed %d · 第%d日" % [TerrainPreset.NAMES[int(decoded.payload.preset)], int(decoded.payload.seed), floori(float(decoded.payload.state.get("minute", 0)) / 1440) + 1])
			saved_sites.set_item_metadata(saved_sites.item_count - 1, path)

func _request_exit() -> void:
	if float(lab.terrain.site.combat_left) > 0:
		_exit_pending = true
		lab.npc_retaliates = false
		lab._clear_movement_input()
		lab.npc.issue_command(TerrainTestNPC.Command.STOP)
		lab.terrain.site.paused = false
		get_tree().paused = false
		message.text = "等候脫戰後保存並離開。"
		return
	_capture_positions()
	var destination := "user://sites/" + str(lab.terrain.site.id).validate_filename() + ".json" if _auto_save_blocked else save_path
	var result := Store.save(lab.terrain, destination)
	if result.ok:
		get_tree().quit()
	else:
		show_result(result)

func update_ui() -> void:
	if lab.terrain == null or details == null:
		return
	var data: TerrainData = lab.terrain
	legend.text = "條件 0–100：紅色低、黃色中、綠色高" if view.view_mode in [2, 3, 5] else ("藍色：取水服務可達；褐色：尚未服務" if view.view_mode == 4 else "")
	legend.visible = not legend.text.is_empty()
	clock_label.text = Runtime.date_text(data) + ("\n戰鬥：1 秒 = 遊戲 1 秒 · 脫戰 %.0f 秒" % float(data.site.combat_left) if float(data.site.combat_left) > 0 else "\n和平：1 秒 = 遊戲 1 分鐘")
	pause_button.text = "繼續" if bool(data.site.paused) else "暫停"
	var condition := Env.land(data, selected)
	details.text = "選取 %s\n農耕 %d  ·  牧地 %d  ·  淡水 %d  ·  建設 %d\n%s" % [selected, condition.farm, condition.pasture, condition.water, condition.build, "；".join(condition.reasons)]
	if view.selection.get_area() > 1:
		if _summary_revision != data.environment_revision or _summary_area != view.selection:
			_summary_revision = data.environment_revision
			_summary_area = view.selection
			var summary := Env.land_summary(data, _summary_area)
			_summary_text = "\n框選 %d 格 · 可耕 %d 格\n草地承載 %d 頭 · 有水 %d 格 · 地基適建 %d 格" % [summary.cells, summary.farm_cells, summary.pasture_capacity, summary.water_cells, summary.build_cells]
		details.text += _summary_text
	if int(condition.potential_farm) > int(condition.farm):
		details.text += "\n未占用時農耕潛力：%d" % int(condition.potential_farm)
	if not source_key.is_empty():
		var resource := Env.resource(data, source_key)
		details.text += "\n%s · %s" % [Env.NAMES[int(resource.kind)], "已勘探" if bool(resource.discovered) else "待勘探，儲量未知"]
		if bool(resource.discovered):
			details.text += "\n%s %d / %d · 一批 %.0f 遊戲分" % ["本分可取" if int(resource.kind) == Env.Kind.SALT else "存量", int(resource.remaining) - (int(resource.get("used", 0)) if int(resource.get("used_minute", -1)) == int(data.site.minute) else 0), resource.capacity, Env.WORK_MINUTES[int(resource.kind)]]
	if not feature_key.is_empty() and data.site.features.has(feature_key):
		var feature: Dictionary = data.site.features[feature_key]
		details.text += "\n%s：%s" % [Runtime.FEATURES[str(feature.kind)].name, feature.status]
		if feature.has("species"):
			details.text += "\n%s %d 頭 · 草地承載 %d 頭" % [Env.ITEM_NAMES[str(feature.species)], int(feature.residents), Runtime.grazing_capacity(data, feature.cells)]
		var water: Dictionary = data.site.water_status.get(feature_key, {})
		if float(water.get("demand", 0)) > 0:
			details.text += "\n供水 %.2f / %.2f 單位／分" % [water.supplied, water.demand]
		if str(feature.kind) in ["well", "intake"]:
			details.text += "\n%s · 共用來源上限 %d／分\n沿可行路線服務 14 格" % ["地下水" if str(feature.kind) == "well" else "淡水水體", 2 if str(feature.kind) == "well" else 6]
		if str(feature.stage) == "complete" and Runtime.FEATURES[str(feature.kind)].has("cycle"):
			var definition: Dictionary = Runtime.FEATURES[str(feature.kind)]
			details.text += "\n%s → %s\n批次 %.1f / %.0f 分" % [Runtime.items_text(definition.input), Runtime.items_text(definition.output), feature.production, definition.cycle]
	view.preview_entrance = Vector2i(-1, -1)
	view.selection_valid = true
	if modes.selected == 5:
		var preview := Runtime.preview_build(data, str(Runtime.FEATURES.keys()[buildings.selected]), build_cells, reserves_cell)
		view.selection_valid = bool(preview.ok)
		details.text += "\n建設預覽：" + ("材料 " + Runtime.items_text(preview.cost) if preview.ok else str(preview.message))
		if preview.ok:
			view.preview_entrance = data.cell_from_index(int(preview.entrance))
			details.text += "\n入口 %s · 清理 %d 處\n施工 %.0f 遊戲分" % [data.cell_from_index(int(preview.entrance)), preview.clearing.size(), Runtime.build_work(str(Runtime.FEATURES.keys()[buildings.selected]), build_cells.size())]
	view.queue_redraw()
	stock_label.text = "營地 %d / %d\n%s\n玩家攜帶：%s" % [Runtime.inventory_size(data.site.inventory), data.site.capacity, Runtime.items_text(data.site.inventory), Runtime.items_text(data.site.manual.cargo)]
	if not str(data.site.manual.target).is_empty():
		stock_label.text += "\n手動作業 %.1f 分" % float(data.site.manual.progress)
	var camp_water: Dictionary = data.site.water_status.get("camp", {})
	stock_label.text += "\n營地供水 %.2f / %.2f 單位／分" % [float(camp_water.get("supplied", 0)), float(camp_water.get("demand", 0.02))]
	stock_label.text += "\n施工／作坊投入由營地統一供應；採集與成品須運回。"
	worker_label.text = "工人：%s\n攜帶：%s" % [str(data.site.worker.status) if bool(data.site.worker_enabled) else "已停止", Runtime.items_text(data.site.worker.cargo)]
	var signature := JSON.stringify(data.site.zones)
	if signature != _zone_signature:
		_zone_signature = signature
		for child: Node in zones.get_children():
			zones.remove_child(child)
			child.queue_free()
		for index: int in range(data.site.zones.size()):
			var zone: Dictionary = data.site.zones[index]
			var toggle := CheckButton.new()
			toggle.text = "%d · %s · %d 格" % [index + 1, {"harvest": "採集", "clear": "清理", "survey": "勘探", "construct": "施工", "operate": "生產"}.get(str(zone.action), "工作"), zone.cells.size()]
			toggle.button_pressed = bool(zone.active)
			toggle.toggled.connect(func(enabled: bool) -> void:
				zone.active = enabled
				if not enabled and int(data.site.worker.zone) == index:
					data.site.worker.target = ""
					data.site.worker.mode = "idle"
					lab.npc.issue_command(TerrainTestNPC.Command.STOP)
				data.environment_revision += 1)
			zones.add_child(toggle)
