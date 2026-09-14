class_name SiteController
extends Node

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const View = preload("res://scripts/terrain_lab/site_resource_view.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const FoodDelivery = preload("res://scripts/terrain_lab/site_food_delivery.gd")
const PersonActions = preload("res://scripts/terrain_lab/site_person_actions.gd")
const CaptivitySupply = preload("res://scripts/terrain_lab/site_captivity_supply.gd")
const EquipmentOrders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const CaptiveEscort = preload("res://scripts/terrain_lab/site_captive_escort.gd")
const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const WorkTeam = preload("res://scripts/terrain_lab/site_work_team.gd")
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
var player_army_label: Label
var team_supply_label: Label
var supply_team_choice: OptionButton
var supply_quantity: SpinBox
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
var _supply_rout_review: Dictionary = {}
var person_actions := PersonActions.new()
var captivity_supply := CaptivitySupply.new()
var equipment_orders := EquipmentOrders.new()
var captive_escort := CaptiveEscort.new()
var family_continuity := FamilyContinuity.new()
var work_team := WorkTeam.new()
var food_delivery := FoodDelivery.new()
var _crew_handled: Dictionary = {}
var _family_dialog: AcceptDialog
var _family_wait := false
var _equipment_appearances: Dictionary = {} # Derived, event-updated; never saved as inventory.
var _pending_deaths: Dictionary = {} # Only newly dead original people; no corpse-wide tick.
var person_executor_id := 0

func setup(scene: Node2D) -> void:
	lab = scene
	food_delivery.init(self)
	view = View.new()
	view.name = "SiteResources"
	lab.add_child(view)
	# Same-row props are behind the existing actors; northern actors still sort behind roofs.
	lab.move_child(view, lab.character.get_index())
	_build_ui()
	lab.character.combat_event.connect(_combat_event)
	lab.npc.combat_event.connect(_combat_event)
	lab.character.died.connect(_person_died)
	lab.npc.died.connect(_person_died)
	for team: TerrainArmy in lab.combat_armies:
		team.combat_event.connect(_combat_event)
		team.died.connect(_person_died)
		team.equipment_initializer = initialize_team_items
		team.equipment_appearance_query = person_appearance
		team.person_busy_query = _person_has_duty
		team.controlled_person_query = lab.controlled_person_id
		team.membership_change_hook = captivity_supply.membership_change
		team.escort_step_guard = captive_escort.permits_step
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.escort_step_guard = captive_escort.permits_step
	person_actions.equipment_removal_guard = equipment_removal_guard
	person_actions.equipment_changed = equipment_changed
	person_actions.opened_food_pool = _personal_opened_food
	person_actions.opened_food_commit = _receive_opened_food
	captivity_supply.init(self)
	person_actions.captivity_change_guard = captivity_supply.change_guard
	person_actions.captivity_supply_commit = captivity_supply.commit_change
	person_actions.captivity_changed = _captivity_changed
	person_actions.ransom_exchange_query = captivity_supply.ransom_exchange_query
	person_actions.ransom_exchange_committed = captivity_supply.ransom_exchange_committed
	equipment_orders.init(lab, person_actions)
	equipment_orders.equipment_apply_guard = equipment_apply_guard
	family_continuity.load_site_query = _load_compatible_site
	family_continuity.archive_current = _archive_family_site
	family_continuity.control_selected = _control_family_person
	work_team.unavailable = _work_person_unavailable
	lab.character.cell_blocker = _actor_blocked
	lab.npc.cell_blocker = _actor_blocked
	get_tree().root.size_changed.connect(_layout)
	get_tree().root.close_requested.connect(_request_exit)
	get_tree().auto_accept_quit = false
	lab.get_node("TerrainLabUI").hide()
	_layout()

func bind() -> void:
	var data: TerrainData = lab.terrain
	lab.character.ammo_inventory = data.site.manual.cargo
	lab.npc.ammo_inventory = data.site.worker.cargo
	_equipment_appearances.clear()
	_pending_deaths.clear()
	person_actions.init(lab)
	captive_escort.init(lab, person_actions)
	family_continuity.init(lab)
	work_team.init(lab)
	_crew_handled.clear()
	_family_wait = false
	captivity_supply.init(self)
	person_executor_id = lab.controlled_person_id()
	for actor: TerrainTestCharacter in [lab.character, lab.npc]:
		var original: Dictionary = actor.editor.capture_appearance() if actor.editor != null else actor.capture_state().appearance
		var initialized := Runtime.seed_person_equipment(data, actor.item_state, actor.person_id, original)
		if not initialized.ok:
			show_result(initialized)
			continue
		equipment_changed(actor.person_id)
		if actor.editor != null:
			actor.editor.part_selection_request = _request_person_equipment.bind(actor.person_id)
			actor.editor.body_selection_request = func(_requested: int) -> int: return actor.visual_state.body_index
		if actor.hp <= 0.0 and not actor.loot_settled:
			_person_died(actor.person_id)
	for team: TerrainArmy in lab.combat_armies:
		initialize_team_items(team)
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
	if lab.exchange_enabled:
		_label(column, "Q 穩守／E 強攻：下次交鋒效果，消費後冷卻 8 秒", 15)
	message = _label(column, "先框選工人採集區，工人會自行採集並回營地交貨。", 16)
	message.modulate = Color("f0d7a0")
	details = _label(column, "")
	_button(column, "手動作業（需走到來源旁）", "ManualHarvest", manual_work)
	_button(column, "查看所選格人物／遺留物", "InspectLoot", _open_person_inventory)
	_button(column, "本人實物配裝／正式領裝", "EquipmentInventory", _open_equipment_inventory)
	if lab.exchange_enabled:
		_button(column, "營地旁：製作弓弩／彈藥", "RangedCrafting", _open_ranged_crafting)
		_button(column, "營地領取實物／彈藥", "TakeDepotItems", func() -> void: _open_person_inventory(true))
	_button(column, "軍事首長：設定未來領裝標準", "EquipmentStandards", _open_equipment_standards)
	_button(column, "被俘本人：嘗試逃脫", "BeginCaptiveEscape", func() -> void: show_result(person_actions.begin_escape(lab.controlled_person_id())))
	_button(column, "指定所選友方人物回收（須自行到相鄰格）", "ChooseRecoveryWorker", _choose_recovery_executor)
	_button(column, "改由玩家搜刮", "ChoosePlayerLooter", func() -> void:
		person_executor_id = lab.controlled_person_id()
		show_result(Runtime.ok("由原玩家執行搜刮")))
	_button(column, "取消人物作業", "CancelPersonAction", func() -> void: show_result(person_actions.cancel(person_executor_id)))
	_button(column, "看守押送原俘虜到所選格", "BeginCaptiveEscort", func() -> void: show_result(captive_escort.begin(lab.controlled_person_id(), person_executor_id, selected)))
	_button(column, "取消後續押送（不釋放俘虜）", "CancelCaptiveEscort", func() -> void: show_result(captive_escort.cancel(person_executor_id)))
	_button(column, "家族名單／死亡接續", "FamilyContinuity", _open_family)
	_button(column, "明確登錄既有家人", "RegisterFamily", _open_family_registry)
	_button(column, "派所選原隊員工作（須現任指揮權）", "AssignSelectedWorker", func() -> void:
		var person := person_actions._person(lab.selected_army_target)
		if not person.is_empty() and int(person.unit) >= 0:
			var ids: Array[int] = [int(person.person_id)]
			show_result(work_team.assign(person.owner, ids, lab.controlled_person_id())))
	_button(column, "停止所選原隊員工作（貨物保留）", "CancelSelectedWorker", func() -> void:
		var person := person_actions._person(lab.selected_army_target)
		if not person.is_empty() and int(person.unit) >= 0 and _can_command_person(person):
			show_result(work_team.cancel(int(person.person_id)))
		else:
			show_result(Runtime.fail("NO_AUTHORITY")))
	_button(column, "本人向營地交貨", "DepositCargo", deposit_controlled_cargo)
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
	_button(column, "部署兩隊近戰測試（各 100 人）", "StartMeleeTrial", func() -> void: show_result(lab.start_melee_trial()))
	_button(column, "結束測試並清除兩隊", "ClearMeleeTrial", lab.clear_army)
	_button(column, "查看兩隊傷亡", "MeleeTrialStatus", func() -> void:
		message.text = "我方：%s\n敵方：%s" % [lab.army.combat_summary(), lab.opposing_army.combat_summary()])
	player_army_label = _label(column, "尚未入隊；青色圓圈為建議站位，不會接管角色。", 15)
	_button(column, "查看／調整接任順位", "PlayerOfficerPriority", _open_officer_priority)
	_button(column, "加入我方隊伍（自主操作）", "JoinPlayerArmy", func() -> void: show_result(lab.join_player_army()))
	_button(column, "拆出選取隊員（需本隊指揮權）", "SplitSelectedSoldier", func() -> void: show_result(lab.split_selected_soldier()))
	_button(column, "本隊名冊：多人派工／補員／拆併", "ManagePlayerRoster", _open_roster)
	_button(column, "正式退出隊伍", "LeavePlayerArmy", func() -> void: show_result(lab.leave_player_army()))
	_label(column, "隊伍口糧／訓練（主動啟用）", 18)
	supply_team_choice = _options(column, ["玩家目前隊伍", "我方測試隊伍"], "SupplyTeam")
	supply_quantity = SpinBox.new()
	supply_quantity.name = "SupplyRations"
	supply_quantity.min_value = 1
	supply_quantity.max_value = 30
	supply_quantity.step = 1
	supply_quantity.value = 1
	column.add_child(supply_quantity)
	team_supply_label = _label(column, "先點選相鄰隊員，再從玩家行囊交糧；不會自取營地物資。", 15)
	_button(column, "向選取隊員交付口糧", "DeliverTeamFood", func() -> void:
		var team := _chosen_supply_team()
		var representative := -1
		if team != null:
			for index: int in team.combat_units.size():
				if team.cells[index] == selected:
					representative = team.combat_identity(index)
					break
		show_result(begin_team_food(team, int(supply_quantity.value), representative)))
	_button(column, "取消口糧交付", "CancelTeamFood", func() -> void: show_result(cancel_team_food()))
	_button(column, "後勤調度：營地／兩隊／地面口糧", "OpenLogistics", _open_logistics)
	_button(column, "玩家下令：平時訓練", "TrainPlayerTeam", func() -> void:
		show_result(order_team_training(_chosen_supply_team(), lab.controlled_member_index(_chosen_supply_team()), true)))
	_button(column, "玩家下令：停止訓練", "StopPlayerTeamTraining", func() -> void:
		show_result(order_team_training(_chosen_supply_team(), lab.controlled_member_index(_chosen_supply_team()), false)))
	for entry: Array in [["玩家下令：守位", TerrainArmy.CombatOrder.HOLD], ["玩家下令：接敵", TerrainArmy.CombatOrder.ATTACK], ["玩家下令：前進至所選格", TerrainArmy.CombatOrder.MOVE], ["玩家下令：撤退至所選格", TerrainArmy.CombatOrder.RETREAT], ["玩家下令：追擊所選敵兵", TerrainArmy.CombatOrder.PURSUE]]:
		var order_id := int(entry[1])
		_button(column, str(entry[0]), "PlayerArmyOrder%d" % order_id, func() -> void:
			var identity := -1
			if order_id == TerrainArmy.CombatOrder.PURSUE:
				for index in range(lab.opposing_army.combat_units.size()):
					if lab.opposing_army.cells[index] == selected:
						identity = lab.opposing_army.combat_identity(index)
						break
			show_result(lab.issue_player_army_order(order_id, selected, identity)))
	_label(column, "開發測試指揮（模擬 NPC 隊長下令，非玩家權限）", 15)
	_button(column, "我方守位", "ArmyCombatHold", func() -> void: _test_army_order(TerrainArmy.CombatOrder.HOLD))
	_button(column, "我方接敵／近戰包圍" if lab.exchange_enabled else "我方維持戰線接敵", "ArmyCombatAttack", func() -> void: _test_army_order(TerrainArmy.CombatOrder.ATTACK))
	_button(column, "我方前進至所選格", "ArmyCombatMove", func() -> void: _test_army_order(TerrainArmy.CombatOrder.MOVE, selected))
	_button(column, "我方撤退至所選格", "ArmyCombatRetreat", func() -> void: _test_army_order(TerrainArmy.CombatOrder.RETREAT, selected))
	_button(column, "我方追擊所選格敵兵", "ArmyCombatPursue", func() -> void:
		var identity := -1
		for index in range(lab.opposing_army.combat_units.size()):
			if lab.opposing_army.cells[index] == selected and lab.opposing_army.combat_can_act(index):
				identity = lab.opposing_army.combat_identity(index)
				break
		_test_army_order(TerrainArmy.CombatOrder.PURSUE, Vector2i(-1, -1), identity))
	var legacy := CheckButton.new()
	legacy.text = "展開原地形／人物／戰鬥測試"
	column.add_child(legacy)
	legacy.toggled.connect(func(enabled: bool) -> void:
		lab.get_node("TerrainLabUI").visible = enabled
		lab.fit_map())
	_label(column, "保存地圖、玩家／NPC 與兩隊傷亡、指揮、動作／移動。交戰中延後保存，離線期間不增加產量。", 15)
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

func deposit_controlled_cargo() -> void:
	var person := person_actions._person(lab.controlled_person_id())
	if get_tree().paused or bool(lab.terrain.site.paused) or person.is_empty() or not person_actions._ready(person) or person_actions.is_busy(int(person.person_id)):
		show_result(Runtime.fail("BUSY", "本人須清醒、自由並停止其他作業"))
		return
	var result := Runtime.deposit(lab.terrain, person.cargo, person.cell)
	if result.ok:
		person.holder.version = int(person.holder.version) + 1
	show_result(result)

func manual_work() -> void:
	var person := person_actions._person(lab.controlled_person_id())
	if get_tree().paused or person.is_empty() or not person_actions._ready(person) or person_actions.is_busy(int(person.person_id)):
		show_result(Runtime.fail("BUSY"))
		return
	if work_team.reserved_targets().has(source_key):
		show_result(Runtime.fail("BUSY", "此來源已有原人物作業"))
		return
	if int(person.unit) >= 0:
		show_result(work_team.begin_manual(int(person.person_id), source_key))
		return
	if person.owner == lab.npc:
		if not Env.work_cells(lab.terrain, source_key).has(person.cell):
			show_result(Runtime.fail("UNREACHABLE", "請原人物走到來源旁"))
			return
		var resource := Env.resource(lab.terrain, source_key)
		if resource.is_empty():
			show_result(Runtime.fail("NO_TARGET"))
			return
		Runtime.assign_task(lab.terrain, Runtime.ok("原人物手動作業", {"target": source_key, "action": "harvest" if bool(resource.discovered) else "survey", "cell": lab.terrain.index(person.cell)}))
		lab.terrain.site.worker_enabled = false
		lab.terrain.site.worker.manual_control = true
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
	lab.terrain.site.worker.manual_control = false
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)

func _actor_blocked(cell: Vector2i, requester: Node) -> bool:
	return lab.army.blocks_cell(cell) or lab.opposing_army.blocks_cell(cell) or (requester != lab.character and lab.character.occupies_cell(cell)) or (requester != lab.npc and lab.npc.occupies_cell(cell))

func _worker_blocked(cell: Vector2i) -> bool:
	return _actor_blocked(cell, lab.npc)

func reserves_cell(cell: Vector2i) -> bool:
	return lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell) or lab.army.reserves_terrain_cell(cell) or lab.opposing_army.reserves_terrain_cell(cell)

func _combat_event(duration: float) -> void:
	if lab.terrain != null:
		Runtime.mark_combat(lab.terrain, duration)

func toggle_pause() -> void:
	lab.terrain.site.paused = not bool(lab.terrain.site.paused)
	get_tree().paused = bool(lab.terrain.site.paused)
	lab._clear_movement_input()
	update_ui()

func tick(delta: float) -> void:
	_crew_handled.clear()
	var data: TerrainData = lab.terrain
	if data == null or data.site.is_empty():
		return
	view.animate(delta)
	_ui_elapsed += delta
	if not bool(data.site.paused) and not get_tree().paused:
		_work_elapsed += delta
		_save_elapsed += delta
		var worker: Dictionary = data.site.worker
		worker.cell = data.index(lab.npc.terrain_cell)
		lab.npc.work_resting = PersonFatigue.needs_work_rest(lab.npc.fatigue, lab.npc.work_resting)
		var capable: bool = lab.npc.can_act() and lab.npc.action_time <= 0 and not lab.npc.guarding and lab.npc.guard_transition_left <= 0.0 and lab.npc.guard_break_left <= 0.0 and lab.npc._rescue_left <= 0.0 and lab.npc.visible and not _person_has_duty(lab.npc.person_id)
		var worker_ready := false
		if bool(data.site.worker_enabled) and lab.npc.work_resting:
			# STOP clears future navigation, not the committed step or original task/cargo.
			if lab.npc.command != TerrainTestNPC.Command.STOP:
				lab.npc.issue_command(TerrainTestNPC.Command.STOP)
			worker.status = "疲勞輪休；安全休息至 50 後續作"
		if bool(worker.get("manual_control", false)):
			if lab.controlled_person_id() == lab.npc.person_id and capable and not lab.npc.is_moving() and worker.cell == worker.work_cell and not str(worker.target).is_empty():
				worker.mode = "work"
				worker_ready = true
			else:
				worker.manual_control = false
				worker.target = ""
				worker.progress = 0.0
		elif bool(data.site.worker_enabled) and lab.controlled_person_id() != lab.npc.person_id and capable and not lab.npc.work_resting:
			if str(worker.target).is_empty() and lab.npc.command != TerrainTestNPC.Command.STOP:
				lab.npc.issue_command(TerrainTestNPC.Command.STOP)
			if str(worker.target).is_empty() and _work_elapsed >= 0.5:
				Runtime.assign_task(data, Runtime.choose_task(data, lab.npc.terrain_cell, _worker_blocked, null, null, work_team.reserved_targets()))
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
		var manual_ready: bool = not str(manual.target).is_empty() and lab.character.can_act() and lab.character.action_time <= 0 and not lab.character.guarding and lab.character.guard_transition_left <= 0.0 and lab.character.guard_break_left <= 0.0 and lab.character._rescue_left <= 0.0 and not lab.character.is_moving() and data.index(lab.character.terrain_cell) == int(manual.get("cell", -1))
		if not manual_ready:
			manual.target = ""
			manual.progress = 0.0
		var work_interval := Runtime.game_seconds(delta, float(data.site.combat_left))
		Runtime.advance(data, delta, worker_ready, manual_ready, reserves_cell, lab.fatigue_work_minutes, _advance_crew,
			floori(Runtime.CARRY_CAPACITY - Runtime.carried_load(lab.terrain.site, {}, lab.npc.item_state)), floori(Runtime.CARRY_CAPACITY - Runtime.carried_load(lab.terrain.site, {}, lab.character.item_state)))
		if worker_ready and not lab.npc.work_resting:
			# Waiting on tools/inputs/output space is assigned duty, not a rest break.
			lab._fatigue_work_seconds[lab.npc] = work_interval
			lab.npc.fatigue_rest = 0.0
	if data.navigation_revision != _navigation_revision:
		_navigation_revision = data.navigation_revision
		lab.renderer.redraw()
		lab.army.notify_terrain_changed()
	if not data.site.notices.is_empty():
		message.text = str(data.site.notices.back())
		data.site.notices.clear()
	if _ui_elapsed >= 0.25:
		_ui_elapsed = 0
		var team: TerrainArmy = lab.player_army()
		if player_army_label != null:
			var controlled_member: int = lab.controlled_member_index(team)
			player_army_label.text = "尚未加入隊伍" if team == null else ("本隊 %d 名原人物；%s\n正式 %s／當前 %s\n%s" % [team.command_members().size(), "你可下令" if team.current_commander == controlled_member and team.command_eligible(controlled_member) else "你是隊員，保持自主操作", str(team.combat_identity(team.formal_commander)) if team.formal_commander >= 0 else "空缺", str(team.combat_identity(team.current_commander)) if team.current_commander >= 0 else "空缺", team.command_notice])
		update_ui()

func finish_tick() -> void:
	# The caller has now advanced bodies/fatigue as well as the Site clock/work.
	var data: TerrainData = lab.terrain
	if data == null or data.site.is_empty() or bool(data.site.paused):
		return
	if _save_elapsed >= 30 and float(data.site.combat_left) <= 0 and not _auto_save_blocked:
		_save_elapsed = 0.0
		save_current()
	if _exit_pending and float(data.site.combat_left) <= 0:
		_exit_pending = false
		_request_exit()

func _test_army_order(order_id: int, goal: Vector2i = Vector2i(-1, -1), target_id: int = -1) -> void:
	show_result(lab.army.issue_combat_order(lab.army.current_commander, order_id, goal, target_id))

func _open_officer_priority() -> void:
	var team: TerrainArmy = lab.player_army()
	if team == null:
		show_result(Runtime.fail("NO_AUTHORITY", "先加入隊伍才能查看本隊順位"))
		return
	var proposed := team.officer_order.duplicate()
	var dialog := AcceptDialog.new()
	dialog.title = "接任順位（任免不在此處變更）"
	dialog.size = Vector2i(480, 420)
	dialog.get_ok_button().text = "一次套用"
	var content := VBoxContainer.new()
	dialog.add_child(content)
	_label(content, "只限在場正式隊長於停止、脫戰時套用。\n代理可查看；開啟此視窗不會暫停戰鬥。", 15)
	var items := ItemList.new()
	items.custom_minimum_size = Vector2(440, 250)
	content.add_child(items)
	var refresh := func() -> void:
		items.clear()
		for index: int in proposed:
			items.add_item("人物 %d" % team.combat_identity(index))
	refresh.call()
	var row := HBoxContainer.new()
	content.add_child(row)
	for offset: int in [-1, 1]:
		_button(row, "上移" if offset < 0 else "下移", "PriorityUp" if offset < 0 else "PriorityDown", func() -> void:
			if items.get_selected_items().is_empty():
				return
			var selected_index := int(items.get_selected_items()[0])
			var destination := selected_index + offset
			if destination < 0 or destination >= proposed.size():
				return
			var value: int = proposed[selected_index]
			proposed[selected_index] = proposed[destination]
			proposed[destination] = value
			refresh.call()
			items.select(destination))
	dialog.confirmed.connect(func() -> void:
		if lab.player_army() != team:
			show_result(Runtime.fail("NO_AUTHORITY", "隊伍已變更；未套用順位"))
		else:
			show_result(team.reorder_officers(lab.controlled_member_index(team), proposed))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	lab.get_node("SiteUI").add_child(dialog)
	dialog.popup_centered()

func _capture_positions() -> void:
	lab.terrain.site.player_cell = lab.terrain.index(lab.character.terrain_cell)
	lab.terrain.site.worker.cell = lab.terrain.index(lab.npc.terrain_cell)
	lab.terrain.site["actors"] = {"player": lab.character.capture_state(), "npc": lab.npc.capture_state()}
	var armies: Array = []
	for team: TerrainArmy in lab.combat_armies:
		if team.combat_enabled:
			armies.append(team.capture_combat_state())
	lab.terrain.site["armies"] = armies

func supply_save_guard() -> Dictionary:
	if lab.has_ranged_projectiles():
		return Runtime.fail("BUSY", "箭矢仍在飛行；結算前不保存、換場或清除射手")
	if not _pending_deaths.is_empty():
		return Runtime.fail("BUSY", "倒地／在途移動及遺物轉存尚未結束")
	var action_guard := person_actions.save_guard()
	if not action_guard.ok:
		return action_guard
	for entry: Dictionary in lab.terrain.site.get("team_supply", {}).values():
		if not entry.get("delivery", {}).is_empty():
			return Runtime.fail("BUSY", "口糧交付尚未完成；請完成或取消後保存，來源未扣物")
	return Runtime.ok()

func save_current() -> void:
	var guard := supply_save_guard()
	if not guard.ok:
		show_result(guard)
		return
	_capture_positions()
	var result := Store.save(lab.terrain, save_path)
	if result.ok:
		_auto_save_blocked = false
	show_result(result)

func archive_before_replace() -> bool:
	if lab.terrain == null or lab.terrain.site.is_empty():
		return true
	var guard := supply_save_guard()
	if not guard.ok:
		show_result(guard)
		return false
	_capture_positions()
	var result := Store.save(lab.terrain, "user://sites/" + str(lab.terrain.site.id).validate_filename() + ".json")
	show_result(result)
	if result.ok:
		_auto_save_blocked = false
		_refresh_saved_sites()
	return bool(result.ok)

func load_current() -> void:
	_load_path(save_path)

func _load_compatible_site(path: String) -> Dictionary:
	var result := Store.load_site(path)
	if result.ok:
		var guard: Dictionary = lab.exchange_snapshot_guard(result.data)
		if not guard.ok:
			return guard
	return result

func _load_path(path: String) -> void:
	if lab.terrain != null and float(lab.terrain.site.combat_left) > 0:
		show_result(Runtime.fail("BUSY", "脫戰後才能載入"))
		return
	var result := _load_compatible_site(path)
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
	var supply_guard := supply_save_guard()
	if not supply_guard.ok:
		show_result(supply_guard)
		return
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
	var containers: Array = data.ground_loot_at.get(data.index(selected), [])
	if not containers.is_empty():
		details.text += "\n現場有 %d 個實物容器；可查看並選擇取物。" % containers.size()
	var job := person_actions.job_for(person_executor_id)
	if not job.is_empty():
		details.text += "\n人物 #%d 作業：%s %.1f／%.1f 秒 %s" % [person_executor_id, job.kind, float(job.elapsed), float(job.duration), str(job.paused)]
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
	var controlled := person_actions._person(lab.controlled_person_id())
	var controlled_cargo: Dictionary = controlled.get("cargo", {})
	var controlled_fatigue := float(person_actions._body_get(controlled, "fatigue")) if not controlled.is_empty() else 0.0
	stock_label.text = "營地 %d / %d\n%s\n本人 #%d 攜帶：%s" % [Runtime.inventory_size(data.site.inventory), data.site.capacity, Runtime.items_text(data.site.inventory), lab.controlled_person_id(), Runtime.items_text(controlled_cargo)]
	stock_label.text += "\n本人疲勞 %.1f／100 · 耗時 +%.1f%%" % [controlled_fatigue, PersonFatigue.slowdown(controlled_fatigue) * 100.0]
	if not str(data.site.manual.target).is_empty():
		stock_label.text += "\n手動作業 %.1f 分" % float(data.site.manual.progress)
	var camp_water: Dictionary = data.site.water_status.get("camp", {})
	stock_label.text += "\n營地供水 %.2f / %.2f 單位／分" % [float(camp_water.get("supplied", 0)), float(camp_water.get("demand", 0.02))]
	stock_label.text += "\n施工／作坊投入由營地統一供應；採集與成品須運回。"
	worker_label.text = "工人：%s\n攜帶：%s" % [str(data.site.worker.status) if bool(data.site.worker_enabled) else "已停止", Runtime.items_text(data.site.worker.cargo)]
	worker_label.text += "\n疲勞 %.1f／100 · 耗時 +%.1f%%\n停止工作並安全停留 30 遊戲秒後恢復" % [lab.npc.fatigue, PersonFatigue.slowdown(lab.npc.fatigue) * 100.0]
	worker_label.text += "\n" + ("輪休中：降至 50 後續作，保留原進度與貨物" if lab.npc.work_resting else "疲勞達 80 自動輪休；玩家不強制停工")
	_update_team_supply_ui()
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

func _selected_people() -> Array[int]:
	var identities: Array[int] = []
	for actor: TerrainTestCharacter in [lab.character, lab.npc]:
		if actor.terrain_cell == selected:
			identities.append(actor.person_id)
	for team: TerrainArmy in lab.combat_armies:
		for index in range(team.combat_units.size()):
			if team.cells[index] == selected:
				identities.append(team.combat_identity(index))
	return identities

func _item_label(definition: Dictionary) -> String:
	for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
		if str(slot.id) == str(definition.get("slot", "")):
			for option: Dictionary in slot.options:
				if str(option.id) == str(definition.get("asset", "")):
					return str(option.label)
	return str(definition.get("asset", "未知物品"))

func _open_logistics() -> void:
	var original_control_id: int = lab.controlled_person_id()
	var original_data: TerrainData = lab.terrain
	var dialog := AcceptDialog.new()
	dialog.name = "LogisticsDialog"
	dialog.title = "原隊伍後勤 · 實際代表與原庫存"
	dialog.min_size = Vector2i(740, 760)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 660)
	dialog.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_label(column, "普通搬運者 3 日份，明確指派後勤者 6 日份；這是原隊伍共有載量，\n不是本人 20 件行囊以外的第二背包。開窗／選取不扣糧、不授指揮權。", 15)
	var targets := _options(column, ["選取實際接收隊伍"], "LogisticsTargetTeam")
	targets.set_item_metadata(0, -1)
	for team: TerrainArmy in lab.combat_armies:
		if team.combat_enabled and team.has_army():
			targets.add_item("隊伍 #%d · 陣營 %d" % [team.team_id, team.faction_id])
			targets.set_item_metadata(targets.item_count - 1, team.team_id)
	var receiver := _options(column, ["選取實際收糧／取糧代表"], "LogisticsReceiver")
	var roster := ItemList.new()
	roster.name = "LogisticsMembers"
	roster.select_mode = ItemList.SELECT_MULTI
	roster.custom_minimum_size = Vector2(650, 130)
	column.add_child(roster)
	var role_buttons := HBoxContainer.new()
	column.add_child(role_buttons)
	var capacity_label := _label(column, "", 15)
	capacity_label.name = "LogisticsCapacity"
	_label(column, "Ctrl／Shift 多選原隊員。只有該隊現任合格指揮者能指派／解除後勤。", 14)
	var sources := _options(column, ["本人原行囊與私人已開封餘糧", "營地原庫存（未開封）"], "LogisticsSource")
	sources.set_item_metadata(0, {})
	sources.set_item_metadata(1, {"kind": "depot"})
	for team: TerrainArmy in lab.combat_armies:
		if team.combat_enabled and team.has_army():
			sources.add_item("隊伍 #%d 的原共有糧" % team.team_id)
			sources.set_item_metadata(sources.item_count - 1, {"kind": "team", "team_id": team.team_id})
	for key: String in original_data.site.get("ground_loot", {}):
		var container: Dictionary = original_data.site.ground_loot[key]
		var food := float(container.get("open_rations", 0.0))
		for kind: String in Sustain.FOODS:
			food += int(container.cargo.get(kind, 0))
		if food > 0.0:
			sources.add_item("地面包 #%s · 原物主 #%d · 格 %s" % [key, int(container.original_owner), str(original_data.cell_from_index(int(container.cell)))])
			sources.set_item_metadata(sources.item_count - 1, {"kind": "ground", "container_id": key})
	var source_rep := _options(column, ["兩隊交糧：來源隊的實際代表"], "LogisticsSourceRepresentative")
	var source_stock_label := _label(column, "", 15)
	source_stock_label.name = "LogisticsSourceStock"
	var quantity := LineEdit.new()
	quantity.name = "LogisticsQuantity"
	quantity.placeholder_text = "完整日份 1–30（整數）；不足一份請勾選下項"
	quantity.text = "1"
	column.add_child(quantity)
	var all_opened := CheckBox.new()
	all_opened.name = "LogisticsAllOpened"
	all_opened.text = "來源未滿 1 日份：搬全部已開封餐份（保留原始小數）"
	column.add_child(all_opened)
	_label(column, "私人／兩隊交糧：兩位原代表須相鄰停止。營地／地面取糧：接收代表\n本人須靠近原庫存格；兩隊來源須來源隊指揮權，地面包不按陣營隱藏。\n此頁只送原隊伍共有糧；獨立人物取回自己的食物請用原搜刮面板。", 14)
	var report := _label(column, "開始時及完成時都會重查原人、權限、距離、載量及來源；途中不扣糧。", 15)
	report.name = "LogisticsResult"
	var show := func(result: Dictionary) -> void:
		show_result(result)
		report.text = str(result.message)
	var current_scope := func() -> bool:
		if lab.controlled_person_id() != original_control_id or lab.terrain != original_data:
			show.call(Runtime.fail("STALE", "控制人物／原 Site 已變更，請重新開啟後勤面板"))
			return false
		return true
	var find_team := func(identity: int) -> TerrainArmy:
		for team: TerrainArmy in lab.combat_armies:
			if team.combat_enabled and team.has_army() and team.team_id == identity:
				return team
		return null
	var selected_ids := func() -> Array[int]:
		var ids: Array[int] = []
		for index: int in roster.get_selected_items():
			ids.append(int(roster.get_item_metadata(index)))
		return ids
	var fill_representatives := func(choice: OptionButton, team: TerrainArmy) -> void:
		var previous: int = int(choice.get_item_metadata(choice.selected)) if choice.selected >= 0 and choice.get_item_metadata(choice.selected) != null else -1
		choice.clear()
		choice.add_item("選取原隊伍的實際代表")
		choice.set_item_metadata(0, -1)
		if team == null:
			return
		for index: int in team.command_members():
			var identity := team.combat_identity(index)
			choice.add_item("原人物 #%d%s" % [identity, "（目前不可行動）" if not team.combat_can_act(index) else ""])
			choice.set_item_metadata(choice.item_count - 1, identity)
			if identity == previous:
				choice.select(choice.item_count - 1)
		if choice.selected == 0 and choice.item_count > 1:
			choice.select(1)
	var source_spec := func() -> Dictionary:
		var spec: Dictionary = sources.get_item_metadata(sources.selected).duplicate()
		if str(spec.get("kind", "person")) == "team":
			spec["representative_id"] = int(source_rep.get_item_metadata(source_rep.selected)) if source_rep.selected >= 0 else -1
		return spec
	var source_stock := func() -> Dictionary:
		var spec: Dictionary = source_spec.call()
		var inventory: Dictionary = {}
		var opened := 0.0
		var title := sources.get_item_text(sources.selected)
		match str(spec.get("kind", "person")):
			"person":
				var person := person_actions._person(original_control_id)
				if not person.is_empty():
					inventory = person.cargo
					opened = float(original_data.site.get("person_supply", {}).get(str(original_control_id), {}).get("open_rations", 0.0))
			"depot": inventory = original_data.site.inventory
			"team":
				var entry := _supply_entry(find_team.call(int(spec.team_id)))
				if not entry.is_empty():
					inventory = entry.inventory
					opened = float(entry.sustain.open_rations)
			"ground":
				var container: Dictionary = original_data.site.ground_loot.get(str(spec.container_id), {})
				if not container.is_empty():
					inventory = container.cargo
					opened = float(container.get("open_rations", 0.0))
		return {"inventory": inventory, "opened": opened, "title": title} # Read-only original inventory reference.
	var refresh_stock := func() -> void:
		var stock: Dictionary = source_stock.call()
		var foods := {}
		for kind: String in Sustain.FOODS:
			foods[kind] = int(stock.inventory.get(kind, 0))
		source_stock_label.text = "%s\n原糧：%s\n已開封約 %s 日份（顯示值；全份提交讀原精確數量）" % [stock.title, Runtime.items_text(foods), String.num(float(stock.opened), 9)]
		source_stock_label.set_meta("opened_rations", float(stock.opened))
	var refresh_roster := func() -> void:
		var kept: Array[int] = selected_ids.call()
		var team: TerrainArmy = find_team.call(int(targets.get_item_metadata(targets.selected)))
		fill_representatives.call(receiver, team)
		roster.clear()
		if team == null:
			capacity_label.text = "尚未選取現場原隊伍"
			return
		for index: int in range(team.combat_units.size()):
			if not team.is_member(index):
				continue
			var identity := team.combat_identity(index)
			var row: Dictionary = team.combat_units[index]
			var item := roster.add_item("#%d · %s · HP %.0f · 疲勞 %.1f · 原行囊 %d 件" % [identity, "專職後勤（6）" if bool(row.get("logistics", false)) else "普通搬運（3）", row.hp, row.fatigue, Runtime.inventory_size(row.cargo)])
			roster.set_item_metadata(item, identity)
			if kept.has(identity):
				roster.select(item, false)
		var entry := _supply_entry(team)
		var held := 0.0 if entry.is_empty() else Sustain.rations(entry.sustain, entry.inventory)
		capacity_label.text = "接收隊原餘糧約 %s／%s 日份；個人行囊仍各自最多 20 件。" % [String.num(held, 9), String.num(team_food_capacity(team), 0)]
	for enabled: bool in [true, false]:
		_button(role_buttons, "指派所選原隊員後勤" if enabled else "解除所選後勤職務", "AssignLogisticsMembers" if enabled else "ReleaseLogisticsMembers", func() -> void:
			if current_scope.call():
				var ids: Array[int] = selected_ids.call()
				show.call(order_team_logistics(find_team.call(int(targets.get_item_metadata(targets.selected))), ids, original_control_id, enabled))
				refresh_roster.call())
	var refresh_source := func() -> void:
		var spec: Dictionary = sources.get_item_metadata(sources.selected)
		var is_team := str(spec.get("kind", "person")) == "team"
		fill_representatives.call(source_rep, find_team.call(int(spec.team_id)) if is_team else null)
		source_rep.visible = is_team
		refresh_stock.call()
	targets.item_selected.connect(func(_index: int) -> void: refresh_roster.call())
	sources.item_selected.connect(func(_index: int) -> void: refresh_source.call())
	_button(column, "重新核對原庫存／名冊", "RefreshLogisticsStock", func() -> void:
		if current_scope.call():
			refresh_roster.call()
			refresh_stock.call())
	_button(column, "開始由實際代表交付口糧", "BeginLogisticsFood", func() -> void:
		if not current_scope.call():
			return
		var amount := 0.0
		if all_opened.button_pressed:
			amount = float(source_stock.call().opened)
			if amount <= 0.0 or amount >= 1.0:
				show.call(Runtime.fail("INVALID", "來源須有未滿1日份的原已開封餐份"))
				return
		elif not quantity.text.strip_edges().is_valid_float():
			show.call(Runtime.fail("INVALID", "請輸入1–30完整日份；零頭請勾選整批已開封餐份"))
			return
		else:
			amount = quantity.text.strip_edges().to_float()
		show.call(begin_team_food(find_team.call(int(targets.get_item_metadata(targets.selected))), amount,
			int(receiver.get_item_metadata(receiver.selected)), source_spec.call()))
		refresh_stock.call())
	_button(column, "取消本人發起的口糧交付", "CancelLogisticsFood", func() -> void:
		if current_scope.call():
			show.call(cancel_team_food())
			refresh_stock.call())
	if targets.item_count > 1:
		targets.select(1)
		var own: TerrainArmy = lab.player_army()
		for index: int in range(1, targets.item_count):
			if own != null and int(targets.get_item_metadata(index)) == own.team_id:
				targets.select(index)
	refresh_roster.call()
	refresh_source.call()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	lab.get_node("SiteUI").add_child(dialog)
	dialog.popup_centered()

func deposit_owned_equipment(identity: int, item_ids: Array, expected_version: int) -> Dictionary:
	if identity != lab.controlled_person_id():
		return Runtime.fail("NO_AUTHORITY", "只能交付受控本人原行囊的實物")
	var person := person_actions._person(identity)
	if get_tree().paused or bool(lab.terrain.site.paused) or not person_actions._ready(person) or person_actions.is_busy(identity):
		return Runtime.fail("BUSY", "本人須清醒自由、停止其他作業")
	var depot: Dictionary = lab.terrain.site.depot_items
	if int(person.holder.version) != expected_version:
		return Runtime.fail("STALE_SOURCE", "本人持物已改變，請重新選擇")
	if not person_actions._adjacent(person.cell, lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))):
		return Runtime.fail("UNREACHABLE", "本人須在營地相鄰合法格交付")
	if int(person.holder.version) >= 2147483646 or int(depot.version) >= 2147483646:
		return Runtime.fail("INVALID", "物品提交版本已達上限")
	for item_id: Variant in item_ids:
		if person.holder.equipped.values().has(item_id):
			return Runtime.fail("INVALID", "穿戴物品須先完成本人卸裝，不會交貨時自動卸下")
	return Runtime.transfer_items(lab.terrain, person.holder, person.cargo, depot,
		lab.terrain.site.inventory, {}, item_ids, expected_version, int(depot.version), int(lab.terrain.site.capacity))

func _open_equipment_inventory() -> void:
	var person := person_actions._person(person_executor_id)
	if person.is_empty():
		show_result(Runtime.fail("NO_TARGET"))
		return
	var original_executor := person_executor_id
	var original_control: int = lab.controlled_person_id()
	var original_data: TerrainData = lab.terrain
	var original_depot: Dictionary = original_data.site.depot_items
	var original_stock: Dictionary = original_data.site.inventory
	var original_holder: Dictionary = person.holder
	var original_cargo: Dictionary = person.cargo
	var holder_version := int(original_holder.version)
	var depot_version := int(original_depot.version)
	var current_scope := func() -> bool:
		var current := person_actions._person(original_executor)
		if person_executor_id != original_executor or lab.controlled_person_id() != original_control or lab.terrain != original_data or current.is_empty() or not is_same(current.holder, original_holder) or not is_same(current.cargo, original_cargo) or not is_same(lab.terrain.site.depot_items, original_depot) or not is_same(lab.terrain.site.inventory, original_stock) or int(original_holder.version) != holder_version or int(original_depot.version) != depot_version:
			show_result(Runtime.fail("STALE", "原人物／持物／營地已變更，請重新開啟裝備面板"))
			return false
		return true
	var dialog := AcceptDialog.new()
	dialog.name = "EquipmentInventoryDialog"
	dialog.title = "人物 #%d 實際持物與領裝" % person_executor_id
	dialog.min_size = Vector2i(580, 480)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	_label(column, "換裝 5 遊戲秒，完成才交換實物。非交戰、停止且可行動；\n改標準不會直接換裝，缺料不生成替代品。", 16)
	var items := ItemList.new()
	items.name = "OwnedEquipmentItems"
	items.select_mode = ItemList.SELECT_MULTI
	items.custom_minimum_size = Vector2(500, 200)
	column.add_child(items)
	for identity: String in person.holder.item_ids:
		var definition: Dictionary = lab.terrain.site.item_definitions[lab.terrain.site.item_records[identity].definition]
		var row := items.add_item(_item_label(definition) + ("（穿戴）" if person.holder.equipped.values().has(identity) else "（行囊）"))
		items.set_item_metadata(row, {"slot": str(definition.slot), "id": identity})
	_button(column, "玩家穿戴選取的自有物品", "WearOwnedItem", func() -> void:
		if not current_scope.call() or items.get_selected_items().is_empty():
			return
		var choice: Dictionary = items.get_item_metadata(items.get_selected_items()[0])
		show_result(equipment_orders.begin_personal(original_executor, str(choice.slot), str(choice.id))))
	_button(column, "玩家卸下選取裝備至原行囊", "RemoveOwnedItem", func() -> void:
		if not current_scope.call() or items.get_selected_items().is_empty():
			return
		var choice: Dictionary = items.get_item_metadata(items.get_selected_items()[0])
		if person.holder.equipped.get(str(choice.slot), "") != str(choice.id):
			show_result(Runtime.fail("INVALID", "所選物品目前在行囊，沒有穿戴"))
			return
		show_result(equipment_orders.begin_personal(original_executor, str(choice.slot), "")))
	_button(column, "所選行囊實物入庫（不自動卸装）", "DepositOwnedEquipment", func() -> void:
		if not current_scope.call():
			return
		var selected_items: Array = []
		for row: int in items.get_selected_items():
			selected_items.append(str(items.get_item_metadata(row).id))
		show_result(deposit_owned_equipment(original_executor, selected_items, holder_version)))
	var standards := _options(column, ["選擇本人國家的領裝標準"], "IssueStandard")
	for nation_id: String in lab.terrain.site.get("equipment_nations", {}):
		var nation: Dictionary = lab.terrain.site.equipment_nations[nation_id]
		if not EquipmentOrders._member(nation, person_executor_id):
			continue
		for standard_id: String in nation.standards:
			standards.add_item(str(nation.standards[standard_id].name))
			standards.set_item_metadata(standards.item_count - 1, [nation_id, standard_id])
	if standards.item_count == 1:
		_label(column, "目前沒有此人的真實國別／標準資料；不自動授予國籍或首長職位。", 15)
	_button(column, "本人向相鄰營地領裝", "IssueEquipment", func() -> void:
		if not current_scope.call():
			return
		if standards.selected <= 0:
			show_result(Runtime.fail("NO_AUTHORITY", "沒有選取已授權的正式標準"))
			return
		var choice: Array = standards.get_item_metadata(standards.selected)
		show_result(equipment_orders.begin_issue(original_executor, str(choice[0]), str(choice[1]))))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	lab.get_node("SiteUI").add_child(dialog)
	dialog.popup_centered()

func _open_equipment_standards() -> void:
	var nation_id := ""
	for key: String in lab.terrain.site.get("equipment_nations", {}):
		if int(lab.terrain.site.equipment_nations[key].military_head) == lab.controlled_person_id():
			nation_id = key
			break
	if nation_id.is_empty():
		show_result(Runtime.fail("NO_AUTHORITY", "原玩家沒有本國軍事首長職位；隊長不等於國家軍事首長"))
		return
	var dialog := AcceptDialog.new()
	dialog.name = "EquipmentStandardsDialog"
	dialog.title = "正式兵種配裝需求 · 只影響未來領裝"
	dialog.min_size = Vector2i(560, 480)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	var standard_choice := _options(column, ["新增標準"], "EditStandard")
	var nation: Dictionary = lab.terrain.site.equipment_nations[nation_id]
	for key: String in nation.standards:
		standard_choice.add_item(str(nation.standards[key].name))
		standard_choice.set_item_metadata(standard_choice.item_count - 1, key)
	var title_input := LineEdit.new()
	title_input.name = "StandardName"
	title_input.placeholder_text = "兵種／標準名稱"
	column.add_child(title_input)
	var choices := {}
	var alternatives_by_slot := {}
	_label(column, "配色與外觀來自選取的真實物品定義；未列出的替代品不會自動發放。", 14)
	for slot: String in Runtime.EQUIPMENT_SLOTS:
		var row := HBoxContainer.new()
		column.add_child(row)
		var choice := _options(row, [slot + "：不變更現役此槽"], "StandardSlot_" + slot)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for definition_id: String in lab.terrain.site.item_definitions:
			var definition: Dictionary = lab.terrain.site.item_definitions[definition_id]
			if str(definition.slot) == slot and EquipmentOrders.valid_definition(definition_id, definition):
				choice.add_item(_item_label(definition))
				choice.set_item_metadata(choice.item_count - 1, definition_id)
		choices[slot] = choice
		alternatives_by_slot[slot] = []
		_button(row, "替代清單…", "StandardAlternatives_" + slot, func() -> void: _open_standard_alternatives(slot, choice, alternatives_by_slot))
	standard_choice.item_selected.connect(func(index: int) -> void:
		if index == 0:
			title_input.text = ""
			for slot: String in choices:
				choices[slot].select(0)
				alternatives_by_slot[slot] = []
			return
		var standard: Dictionary = nation.standards[str(standard_choice.get_item_metadata(index))]
		title_input.text = str(standard.name)
		for slot: String in choices:
			var choice: OptionButton = choices[slot]
			alternatives_by_slot[slot] = standard.slots.get(slot, {}).get("alternatives", []).duplicate()
			choice.select(0)
			for row in range(1, choice.item_count):
				if str(choice.get_item_metadata(row)) == str(standard.slots.get(slot, {}).get("definition", "")):
					choice.select(row))
	_button(column, "提交正式標準（不搬動實物）", "CommitStandard", func() -> void:
		var key := str(standard_choice.get_item_metadata(standard_choice.selected)) if standard_choice.selected > 0 else "unit_%d" % (nation.standards.size() + 1)
		while standard_choice.selected == 0 and nation.standards.has(key):
			key += "_"
		var slots := {}
		for slot: String in choices:
			var choice: OptionButton = choices[slot]
			if choice.selected > 0:
				var definition_id := str(choice.get_item_metadata(choice.selected))
				var alternatives: Array = alternatives_by_slot[slot].duplicate()
				alternatives.erase(definition_id)
				slots[slot] = {"definition": definition_id, "alternatives": alternatives}
		show_result(equipment_orders.set_standard(lab.controlled_person_id(), nation_id, key, title_input.text.strip_edges(), slots)))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	lab.get_node("SiteUI").add_child(dialog)
	dialog.popup_centered()

func _open_standard_alternatives(slot: String, primary: OptionButton, selections: Dictionary) -> void:
	if primary.selected <= 0:
		show_result(Runtime.fail("NO_TARGET", "請先指定此槽的主要裝備"))
		return
	var definition_id := str(primary.get_item_metadata(primary.selected))
	var dialog := AcceptDialog.new()
	dialog.name = "StandardAlternativesDialog"
	dialog.title = slot + " · 明列可接受的同槽替代物"
	dialog.min_size = Vector2i(500, 320)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	_label(column, "Ctrl／Shift 多選；完全不選代表不接受替代。\n順序沿物品清單；主要裝備優先，仍須有真庫存及可呈現的實裝。", 14)
	var list := ItemList.new()
	list.name = "StandardAlternativeItems"
	list.select_mode = ItemList.SELECT_MULTI
	list.custom_minimum_size = Vector2(460, 230)
	column.add_child(list)
	for index: int in range(1, primary.item_count):
		var candidate := str(primary.get_item_metadata(index))
		if candidate == definition_id:
			continue
		var item := list.add_item(primary.get_item_text(index))
		list.set_item_metadata(item, candidate)
		if selections[slot].has(candidate):
			list.select(item, false)
	dialog.confirmed.connect(func() -> void:
		if is_instance_valid(primary) and primary.selected > 0 and str(primary.get_item_metadata(primary.selected)) == definition_id:
			var allowed: Array = []
			for item: int in list.get_selected_items():
				allowed.append(str(list.get_item_metadata(item)))
			selections[slot] = allowed
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	primary.get_window().add_child(dialog)
	dialog.popup_centered()

func _choose_recovery_executor() -> void:
	var controlled := person_actions._person(lab.controlled_person_id())
	for identity: int in _selected_people():
		var person := person_actions._person(identity)
		if not person.is_empty() and not controlled.is_empty() and int(person.faction) == int(controlled.faction) and float(person.hp) > 0.0:
			person_executor_id = identity
			show_result(Runtime.ok("已選原人物 #%d；停止其他工作並到来源相鄰合法格，再指定搜刮" % identity))
			return
	show_result(Runtime.fail("NO_TARGET", "請點選原友方人物所在格"))

func _open_ranged_crafting() -> void:
	var original_executor := person_executor_id
	var original_control: int = lab.controlled_person_id()
	var original_data: TerrainData = lab.terrain
	var dialog := AcceptDialog.new()
	dialog.name = "RangedCraftingDialog"
	dialog.title = "營地手作 · 原人物 #%d" % original_executor
	dialog.min_size = Vector2i(560, 380)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	_label(column, "本人須站在營地相鄰格、停止其他工作並脫戰。\n營地須有工具 1 件（不消耗）；完工才扣材料、製品入營地。\n取消、移動或受擊中斷不扣材料；疲勞沿原工作規則。", 15)
	var names := {"bow": "弓 1 把", "crossbow": "弩 1 把", "arrow": "箭 10 支", "bolt": "弩矢 10 支"}
	for key: String in Runtime.RANGED_RECIPES:
		var recipe: Dictionary = Runtime.RANGED_RECIPES[key]
		var title := "%s：%s · %.0f 遊戲分鐘" % [str(names.get(key, key)), Runtime.items_text(recipe.cost), float(recipe.duration) / 60.0]
		_button(column, title, "Craft_" + key, func() -> void:
			if person_executor_id != original_executor or lab.controlled_person_id() != original_control or lab.terrain != original_data:
				show_result(Runtime.fail("STALE_SOURCE", "原執行者或地圖已變更，請重開製作面板"))
				return
			show_result(person_actions.begin_ranged_craft(original_executor, key)))
	_label(column, "完成後用「營地領取實物／彈藥」取到本人行囊，\n再用「本人實物配裝／正式領裝」換裝；Space 攻擊所選敵人。\n工作隊伍可先指定原友方人物作為執行者。", 15)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	lab.get_node("SiteUI").add_child(dialog)
	dialog.popup_centered()

func _open_person_inventory(depot_only: bool = false) -> void:
	var original_executor := person_executor_id
	var original_control: int = lab.controlled_person_id()
	var original_data: TerrainData = lab.terrain
	var current_scope := func() -> bool:
		if person_executor_id != original_executor or lab.controlled_person_id() != original_control or lab.terrain != original_data:
			show_result(Runtime.fail("STALE", "原執行者／控制人物／Site已變更，請重新開啟搜刮面板"))
			return false
		return true
	var sources: Array[Dictionary] = []
	if depot_only:
		sources.append({"kind": "depot", "id": "depot", "label": "原營地庫存（本人须到相鄰格）"})
	for identity: int in _selected_people():
		if depot_only:
			break
		var person := person_actions._person(identity)
		if not person.is_empty():
			sources.append({"kind": "person", "id": str(identity), "label": "人物 #%d · HP %.1f · %s" % [identity, float(person.hp), "昏迷" if float(person.ko) > 0.0 else ("死亡" if float(person.hp) <= 0.0 else "清醒")]})
	for identity: String in lab.terrain.ground_loot_at.get(lab.terrain.index(selected), []):
		if depot_only:
			break
		var holder: Dictionary = lab.terrain.site.ground_loot[identity]
		sources.append({"kind": "ground", "id": identity, "label": "%s #%s · 原物主 #%d" % [{"remains": "遺物", "sealed": "封存包", "cargo": "物資包"}[str(holder.kind)], identity, int(holder.original_owner)]})
	if sources.is_empty():
		show_result(Runtime.fail("NO_TARGET", "此格沒有原人物或遺留物"))
		return
	var dialog := AcceptDialog.new()
	dialog.name = "PersonInventoryDialog"
	dialog.title = ("營地領取" if depot_only else "實物搜刮") + " · 執行者 #%d" % person_executor_id
	dialog.min_size = Vector2i(560, 510)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	var labels: Array = []
	for source: Dictionary in sources:
		labels.append(source.label)
	var choice := _options(column, labels, "LootSource")
	for index: int in range(sources.size()):
		choice.set_item_metadata(index, {"kind": sources[index].kind, "id": sources[index].id})
	var description := _label(column, "穿戴裝備每件 5 秒；散物 2 + 0.2 × 數量秒。\n拿入原行囊，不自動穿戴；醒來、受擊或移動中止。", 15)
	var items := ItemList.new()
	items.name = "LootItems"
	items.select_mode = ItemList.SELECT_MULTI
	items.custom_minimum_size = Vector2(480, 170)
	column.add_child(items)
	var resources := _options(column, ["不取散裝資源"], "LootResource")
	var opened := CheckButton.new()
	opened.name = "LootOpenedFood"
	opened.text = "取此包全部開封口糧（原私人餐份，不捨去小數）"
	column.add_child(opened)
	var quantity := SpinBox.new()
	quantity.name = "LootQuantity"
	quantity.min_value = 1
	quantity.max_value = Runtime.CARRY_CAPACITY
	quantity.step = 1
	column.add_child(quantity)
	var refresh := func(_index: int = 0) -> void:
		items.clear()
		opened.button_pressed = false
		resources.clear()
		resources.add_item("不取散裝資源")
		var source: Dictionary = sources[choice.selected]
		var current := person_actions._source(str(source.kind), str(source.id))
		if current.is_empty():
			description.text = "來源已不存在，請重新查看。"
			opened.disabled = true
			return
		var available := float(current.holder.get("open_rations", 0.0))
		opened.disabled = source.kind != "ground" or available <= 0.0
		opened.text = "取此包全部開封口糧 %.6f 日份（本人原餐份池）" % available
		for identity: String in current.holder.item_ids:
			var definition: Dictionary = lab.terrain.site.item_definitions[lab.terrain.site.item_records[identity].definition]
			var row := items.add_item("%s #%s%s" % [_item_label(definition), identity, "（穿戴）" if current.holder.equipped.values().has(identity) else ""])
			items.set_item_metadata(row, identity)
		for resource: String in current.cargo:
			if int(current.cargo[resource]) > 0:
				resources.add_item("%s ×%d" % [str(Env.ITEM_NAMES.get(resource, resource)), int(current.cargo[resource])])
				resources.set_item_metadata(resources.item_count - 1, resource)
	choice.item_selected.connect(refresh)
	refresh.call()
	_button(column, "開始取走所選實物", "BeginLoot", func() -> void:
		if not current_scope.call():
			return
		var source: Dictionary = sources[choice.selected]
		var selected_items: Array = []
		for row: int in items.get_selected_items():
			selected_items.append(items.get_item_metadata(row))
		var selected_resources := {}
		if resources.selected > 0:
			selected_resources[str(resources.get_item_metadata(resources.selected))] = int(quantity.value)
		var current := person_actions._source(str(source.kind), str(source.id))
		var open_amount := float(current.get("holder", {}).get("open_rations", 0.0)) if opened.button_pressed else 0.0
		show_result(person_actions.begin_loot(person_executor_id, str(source.kind), str(source.id), selected_resources, selected_items, open_amount)))
	_button(column, "拘束所選昏迷人物（本人看守）", "BeginCapture", func() -> void:
		if not current_scope.call():
			return
		var source: Dictionary = sources[choice.selected]
		show_result(person_actions.begin_capture(person_executor_id, int(source.id), person_executor_id) if source.kind == "person" else Runtime.fail("NO_TARGET")))
	_button(column, "替所選友方俘虜解綁", "BeginUnbind", func() -> void:
		if not current_scope.call():
			return
		var source: Dictionary = sources[choice.selected]
		show_result(person_actions.begin_unbind(person_executor_id, int(source.id)) if source.kind == "person" else Runtime.fail("NO_TARGET")))
	_button(column, "由原隊伍付 100 日份贖回", "BeginRansomDialog", func() -> void:
		if not current_scope.call():
			return
		var source: Dictionary = sources[choice.selected]
		if source.kind == "person":
			_open_ransom(int(source.id), dialog))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	lab.get_node("SiteUI").add_child(dialog)
	dialog.popup_centered()

func _open_ransom(target_id: int, source_window: Window = null) -> void:
	var relation: Dictionary = lab.terrain.site.captivity.get(str(target_id), {})
	if relation.is_empty():
		show_result(Runtime.fail("NO_TARGET", "原人物不在拘押關係中"))
		return
	var original_payer := person_executor_id
	var original_control: int = lab.controlled_person_id()
	var original_data: TerrainData = lab.terrain
	var dialog := AcceptDialog.new()
	dialog.name = "RansomDialog"
	dialog.title = "原物資贖回 #%d" % target_id
	var column := VBoxContainer.new()
	dialog.add_child(column)
	_label(column, "原付款代表須與拘押方有權代表相鄰停止。\n10 遊戲秒完成才轉交 100 日份，不從私人行囊或家人遠端取糧。", 16)
	var choice := _options(column, ["選擇實際拘押代表"], "RansomRepresentative")
	for identity: int in captivity_supply._all_members():
		var person := person_actions._person(identity)
		if not person.is_empty() and int(person.faction) == int(relation.captor_faction):
			choice.add_item("原人物 #%d" % identity)
			choice.set_item_metadata(choice.item_count - 1, identity)
	_button(column, "開始原物資交付", "BeginRansom", func() -> void:
		if person_executor_id != original_payer or lab.controlled_person_id() != original_control or lab.terrain != original_data:
			show_result(Runtime.fail("STALE", "原付款代表／控制人物／Site已變更，請重新開啟贖回面板"))
			return
		if choice.selected > 0:
			show_result(person_actions.begin_ransom(original_payer, target_id, int(choice.get_item_metadata(choice.selected)))))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	(source_window if is_instance_valid(source_window) else lab.get_node("SiteUI")).add_child(dialog)
	dialog.popup_centered()

func initialize_team_items(team: TerrainArmy) -> void:
	if not team.combat_enabled:
		return
	for index in range(team.combat_units.size()):
		var unit: Dictionary = team.combat_units[index]
		if not unit.has("appearance"):
			var presenter: Variant = team._unit_editor(index)
			unit.appearance = presenter.capture_appearance() if team._uses_live_presenter(index) and presenter != null else TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		if not unit.has("item_state"):
			unit.item_state = {}
		if not unit.has("cargo"):
			unit.cargo = {}
		var initialized := Runtime.seed_person_equipment(lab.terrain, unit.item_state, team.combat_identity(index), unit.appearance)
		if not initialized.ok:
			show_result(initialized)
			continue
		equipment_changed(team.combat_identity(index))
		if float(unit.hp) <= 0.0 and not bool(unit.get("loot_settled", false)):
			_person_died(team.combat_identity(index))

func before_clear_team_items() -> Dictionary:
	var guard := supply_save_guard()
	if not guard.ok:
		return guard
	var holders: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		if team.moving_count() > 0:
			return Runtime.fail("BUSY", "先完成原在途移動；不刪除行進中人物的物資")
		for index in range(team.combat_units.size()):
			var person := person_actions._person(team.combat_identity(index))
			if person.is_empty():
				return Runtime.fail("STALE_SOURCE", "原人物持物資料無效；未清除或略過其物資")
			if int(person.person_id) == lab.controlled_person_id():
				return Runtime.fail("BUSY", "不能清除目前受控原人物")
			for relative: Dictionary in lab.terrain.site.get("family", {}).get("members", []):
				if str(relative.site_id) == str(lab.terrain.site.id) and int(relative.person_id) == int(person.person_id):
					return Runtime.fail("BUSY", "此原人物已列家族名單；不能用清除測試消滅家人")
			for nation: Dictionary in lab.terrain.site.get("equipment_nations", {}).values():
				if nation.members.has(int(person.person_id)):
					return Runtime.fail("BUSY", "此原人物仍有原國別／職務引用；未清除")
			if bool(person.captive) or person_actions.is_guarding(int(person.person_id)):
				return Runtime.fail("BUSY", "先處理原俘虜／看守，不能藉清除測試消滅人物關係")
			if not lab.terrain.is_walkable(person.cell):
				return Runtime.fail("UNREACHABLE", "退場物資須留在合法原格")
			for identity: String in person.holder.item_ids:
				if lab.terrain.site.item_records.get(identity, {}).get("holder") != person.holder.holder:
					return Runtime.fail("STALE_SOURCE")
			holders.append(person)
	var removed := {}
	for person: Dictionary in holders:
		removed[int(person.person_id)] = true
	var all_members := captivity_supply._all_members()
	for key: String in lab.terrain.site.get("person_supply", {}):
		var pool: Dictionary = lab.terrain.site.person_supply[key]
		if not Sustain.validate(pool, all_members):
			return Runtime.fail("INVALID_SUSTAIN", "原私人供養歷史無效；未清隊或轉存物資")
		for identity: int in Sustain._ids(pool):
			if removed.has(int(key)) and identity != int(key) or not removed.has(int(key)) and removed.has(identity):
				return Runtime.fail("BUSY", "退場人物仍與其他原人物共用餐份歷史；未清除私人庫存或他人歷史")
	var required_containers := 0
	for person: Dictionary in holders:
		var pool := _personal_opened_food(int(person.person_id))
		var checked := Runtime.leave_ground_loot(lab.terrain, person.holder, person.cargo, int(person.person_id), person.cell, "cargo", person.cargo, person.holder.item_ids.duplicate(), int(person.holder.version), pool, float(pool.get("open_rations", 0.0)), true)
		if not checked.ok and str(checked.code) != "EMPTY":
			return checked
		required_containers += int(checked.ok)
	if int(lab.terrain.site.next_loot) + required_containers > 2147483647:
		return Runtime.fail("INVALID", "物資包序號已用盡")
	for offset in range(required_containers):
		if lab.terrain.site.ground_loot.has(str(int(lab.terrain.site.next_loot) + offset)):
			return Runtime.fail("INVALID", "物資包序號衝突")
	for person: Dictionary in holders:
		var pool := _personal_opened_food(int(person.person_id))
		var result := Runtime.leave_ground_loot(lab.terrain, person.holder, person.cargo, int(person.person_id), person.cell, "cargo", person.cargo, person.holder.item_ids.duplicate(), int(person.holder.version), pool, float(pool.get("open_rations", 0.0)))
		assert(result.ok or str(result.code) == "EMPTY")
	# Only explicitly removed experimental rows lose their private owner entry.
	# Existing Actors, other people's meal history and all ground stock survive.
	for identity: int in removed:
		lab.terrain.site.get("person_supply", {}).erase(str(identity))
	return Runtime.ok("測試人物退場；全部實物仍留在原格，既有遺物不變")

func person_appearance(identity: int) -> Dictionary:
	return _equipment_appearances.get(identity, {})

func _person_has_duty(identity: int) -> bool:
	return person_actions.is_busy(identity) or person_actions.is_guarding(identity) or work_team.is_assigned(identity) or _is_delivering_person(identity)

func _open_roster() -> void:
	var team: TerrainArmy = lab.player_army()
	var original_control_id: int = lab.controlled_person_id()
	if team == null:
		show_result(Runtime.fail("NO_TARGET", "本人目前沒有原隊伍"))
		return
	var dialog := AcceptDialog.new()
	dialog.title = "原人物名冊與調度"
	dialog.name = "RosterDialog"
	dialog.min_size = Vector2i(660, 500)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	_label(column, "可按 Ctrl／Shift 多選既有隊員；不生成新兵、貨物或家人。\n拆分保留原訓練與供養歷史；補員／合併由原制度按存活人數加權。", 15)
	var members := ItemList.new()
	members.name = "RosterMembers"
	members.select_mode = ItemList.SELECT_MULTI
	members.custom_minimum_size = Vector2(620, 270)
	column.add_child(members)
	for index: int in range(team.combat_units.size()):
		if not team.is_member(index):
			continue
		var identity := team.combat_identity(index)
		var row: Dictionary = team.combat_units[index]
		var item := members.add_item("#%d  HP %.0f  疲勞 %.1f  貨物 %d  %s" % [identity, row.hp, row.fatigue, Runtime.inventory_size(row.cargo), "工作中" if work_team.is_assigned(identity) else "未派工"])
		members.set_item_metadata(item, identity)
	var selected_ids := func() -> Array[int]:
		var identities: Array[int] = []
		for item: int in members.get_selected_items():
			identities.append(int(members.get_item_metadata(item)))
		return identities
	var report := _label(column, "所有提交會重新核對原人物、停止狀態與當前指揮權。", 15)
	var apply_result := func(result: Dictionary) -> void:
		show_result(result)
		report.text = str(result.message) if result.ok else "%s：%s" % [result.code, result.message]
	var current_scope := func() -> bool:
		if lab.controlled_person_id() != original_control_id or lab.player_army() != team:
			apply_result.call(Runtime.fail("STALE", "原控制人物／所屬隊伍已變更，請重新開啟名冊"))
			return false
		return true
	_button(column, "派所選原隊員工作", "AssignRosterWorkers", func() -> void:
		if current_scope.call():
			apply_result.call(work_team.assign(team, selected_ids.call(), lab.controlled_person_id())))
	_button(column, "停止所選原隊員後續工作", "CancelRosterWorkers", func() -> void:
		if not current_scope.call():
			return
		var identities: Array[int] = selected_ids.call()
		if identities.is_empty() or team.current_commander != lab.controlled_member_index(team) or not team.command_eligible(team.current_commander):
			apply_result.call(Runtime.fail("NO_AUTHORITY"))
			return
		for identity: int in identities:
			var person := person_actions._person(identity)
			if person.is_empty() or person.owner != team:
				apply_result.call(Runtime.fail("STALE", "名冊已變更，請重開面板"))
				return
		for identity: int in identities:
			work_team.cancel(identity)
		apply_result.call(Runtime.ok("已停止後續工作；原貨物與已預約步進保留")))
	var confirmation := CheckButton.new()
	confirmation.name = "ReceiverCommanderConfirmation"
	confirmation.text = "開發調度確認：接收隊現任合格指揮者同意此次編入"
	column.add_child(confirmation)
	var approval := {}
	confirmation.toggled.connect(func(enabled: bool) -> void:
		approval.clear()
		if not enabled or not current_scope.call():
			return
		for receiver: TerrainArmy in lab.combat_armies:
			if receiver == team or not receiver.has_army():
				continue
			var member_ids: Array[int] = []
			for index: int in team.command_members():
				member_ids.append(team.combat_identity(index))
			approval.merge({"team_id": receiver.team_id, "commander_id": receiver.combat_identity(receiver.current_commander),
				"source_team_id": team.team_id, "source_commander_id": original_control_id,
				"selected_ids": selected_ids.call(), "member_ids": member_ids}))
	_label(column, "已有接收隊須同地圖、同陣營、雙方停止及雙方指揮者確認。\n勾選是明示模擬 NPC 指揮者確認，不是授予玩家對方職位。空槽拆分不需對方。", 14)
	_button(column, "所選原隊員拆分／補入另一隊", "TransferRosterMembers", func() -> void:
		if current_scope.call():
			apply_result.call(lab.transfer_player_roster(selected_ids.call(), false, approval))
			confirmation.button_pressed = false)
	_button(column, "全隊合入另一既有隊伍", "MergeRosterTeam", func() -> void:
		if current_scope.call():
			var all_members: Array[int] = []
			apply_result.call(lab.transfer_player_roster(all_members, true, approval))
			confirmation.button_pressed = false)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	lab.get_node("SiteUI").add_child(dialog)
	dialog.popup_centered()

func _can_command_person(person: Dictionary) -> bool:
	if int(person.person_id) == lab.controlled_person_id():
		return true
	return int(person.unit) >= 0 and person.owner.command_eligible(person.owner.current_commander) and person.owner.combat_identity(person.owner.current_commander) == lab.controlled_person_id()

func _work_person_unavailable(identity: int) -> bool:
	if person_actions.is_busy(identity) or person_actions.is_guarding(identity) or _is_delivering_person(identity):
		return true
	var person := person_actions._person(identity)
	if person.is_empty() or int(person.unit) < 0:
		return true
	if not person.owner.is_member(int(person.unit)):
		return false # The old simulation container is not this person's membership.
	if bool(person.body.get("logistics", false)):
		return true # Dedicated hauling is not simultaneous harvesting.
	var entry := _supply_entry(person.owner)
	return not entry.is_empty() and (bool(entry.training_order) or not entry.delivery.is_empty())

func _advance_crew(seconds: float) -> void:
	var result: Dictionary = work_team.advance(seconds).handled_seconds
	for identity: int in result:
		_crew_handled[identity] = float(_crew_handled.get(identity, 0.0)) + float(result[identity])

func consume_crew_work() -> Dictionary:
	var result := _crew_handled.duplicate()
	_crew_handled.clear()
	return result

func advance_guard_work(seconds: float) -> Dictionary:
	var handled := {}
	var guards := {}
	var threats := {}
	for relation: Dictionary in lab.terrain.site.captivity.values():
		guards[int(relation.guard_id)] = true
	for identity: int in guards:
		var person := person_actions._person(identity)
		if not person_actions._ready(person, true) or person_actions.is_busy(identity) or person_actions._threat(person, threats):
			continue
		var fatigue := float(person_actions._body_get(person, "fatigue"))
		var autonomous: bool = identity != lab.controlled_person_id()
		var resting: bool = autonomous and PersonFatigue.needs_work_rest(fatigue, bool(person_actions._body_get(person, "work_resting")))
		person_actions._body_set(person, "work_resting", resting)
		if resting:
			continue # Original safe-rest update handles recovery; no duplicate time.
		var effort := minf(seconds, maxf(0.0, (PersonFatigue.WORK_REST_AT - fatigue) / PersonFatigue.WORK_RATE)) if autonomous else seconds
		var state := PersonFatigue.advance(fatigue, float(person_actions._body_get(person, "fatigue_rest")), effort, PersonFatigue.WORK_RATE, false)
		person_actions._body_set(person, "fatigue", minf(PersonFatigue.WORK_REST_AT, state[0]) if autonomous else state[0])
		person_actions._body_set(person, "fatigue_rest", state[1])
		if autonomous:
			person_actions._body_set(person, "work_resting", PersonFatigue.needs_work_rest(float(person_actions._body_get(person, "fatigue")), false))
		handled[identity] = effort
	return handled

func _archive_family_site() -> Dictionary:
	var check := supply_save_guard()
	if not check.ok:
		return check
	_capture_positions()
	return Store.save(lab.terrain, "user://sites/" + str(lab.terrain.site.id).validate_filename() + ".json")

func _control_family_person(data: Variant, identity: int) -> Dictionary:
	if data != null:
		if not data is TerrainData or float(FamilyContinuity._saved_person(data, identity).get("hp", 0.0)) <= 0.0:
			return Runtime.fail("NO_TARGET", "原快照人物不存在；保留目前場景")
		var guard: Dictionary = lab.exchange_snapshot_guard(data)
		if not guard.ok:
			return guard
		data.site.controlled_person_id = identity
		lab.bind_terrain(data) # Original validated actor/row restore, never a substitute body.
	var target: Dictionary = lab._combat_target(identity)
	if target.is_empty() or float(target.hp) <= 0.0:
		return Runtime.fail("NO_TARGET", "原接續人物不存在或已死亡")
	lab.terrain.site.controlled_person_id = identity
	person_executor_id = identity
	if int(target.unit) < 0 and target.owner == lab.npc:
		lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	lab._clear_movement_input()
	lab.camera.position = target.position
	_family_wait = false
	if is_instance_valid(_family_dialog):
		_family_dialog.queue_free()
	_family_dialog = null
	lab.terrain.site.paused = false
	get_tree().paused = false
	return Runtime.ok("已接續原人物 #%d；保留生命、年齡、拘押、實物與原職位" % identity)

func check_family_death() -> void:
	if is_instance_valid(_family_dialog) or not _pending_deaths.is_empty():
		return
	var death := family_continuity.death_tick()
	if not death.ok or str(death.status) != "DEAD":
		return
	if _family_wait and float(lab.terrain.site.combat_left) > 0.0:
		return
	_family_wait = false
	_open_family()

func _open_family() -> void:
	if is_instance_valid(_family_dialog):
		_family_dialog.popup_centered()
		return
	var observation := family_continuity.inspect()
	if not observation.ok:
		show_result(observation)
		return
	var death := family_continuity.death_tick()
	var dead: bool = death.ok and str(death.status) == "DEAD"
	if dead:
		lab.terrain.site.paused = true
		get_tree().paused = true
		lab._clear_movement_input()
	var dialog := AcceptDialog.new()
	dialog.name = "FamilyDialog"
	_family_dialog = dialog
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.title = "原家人接續" if dead else "已登錄家族（在世時不能换人）"
	dialog.min_size = Vector2i(620, 430)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	var messages := {"UNREGISTERED": "家族尚未明確登錄；不是 Game Over。沒有自動建立親屬。",
		"DATA_MISSING": "部分家族資料缺失／名單未確認完整，不能判定 Game Over。",
		"GAME_OVER": "Game Over：已確認的完整家族名單沒有其他在世成員。",
		"CHOOSE": "請選在世原家人。未成年不成年、被俘不解綁、死者遺物不轉送。",
		"ALIVE": "只有真正死亡才允許接續；昏迷與被俘不能換人。"}
	_label(column, str(messages.get(str(observation.status), observation.status)), 17)
	var list := ItemList.new()
	list.name = "FamilyMembers"
	list.custom_minimum_size = Vector2(580, 220)
	column.add_child(list)
	for member: Dictionary in observation.members:
		var age := "年齡未登錄" if int(member.age_years) < 0 else "%d 歲%s" % [int(member.age_years), "（未成年）" if int(member.age_years) < 18 else ""]
		var row := list.add_item("%s #%d · %s · %s · %s%s" % [str(member.label), int(member.person_id), str(member.site_id), age, {"ALIVE": "在世", "DEAD": "死亡", "UNKNOWN": "資料不足"}[str(member.status)], " · 被俘" if bool(member.get("captive", false)) else ""])
		list.set_item_metadata(row, member)
		list.set_item_tooltip(row, str(member.message))
	_button(column, "接續選取的在世原家人", "ChooseFamilySuccessor", func() -> void:
		if list.get_selected_items().is_empty():
			return
		var member: Dictionary = list.get_item_metadata(list.get_selected_items()[0])
		show_result(family_continuity.choose(str(member.site_id), int(member.person_id))))
	if dead:
		_button(column, "繼續原場景，等待脫戰安全歸檔後再選", "WaitForFamilyArchive", func() -> void:
			_family_wait = true
			dialog.queue_free()
			_family_dialog = null
			lab.terrain.site.paused = false
			get_tree().paused = false)
	_button(column, "登錄／核對既有家人", "ReviewFamilyRegistry", _open_family_registry)
	dialog.confirmed.connect(func() -> void:
		if not dead:
			dialog.queue_free()
			_family_dialog = null)
	dialog.canceled.connect(func() -> void:
		if not dead:
			dialog.queue_free()
			_family_dialog = null)
	lab.get_node("SiteUI").add_child(dialog)
	dialog.popup_centered()

func _open_family_registry() -> void:
	var dialog := AcceptDialog.new()
	dialog.name = "FamilyRegistryDialog"
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.title = "明確登錄家人 · 只引用既有人物，不建立身體"
	dialog.min_size = Vector2i(620, 540)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	_label(column, "只有你明確登錄的人才是家人，不按同陣營或外貌推定。\n異地須填既有 Site 快照；年齡未知填 -1，不依模型推測成年。", 16)
	var members: Array = lab.terrain.site.get("family", {}).get("members", []).duplicate(true)
	var listing := ItemList.new()
	listing.name = "FamilyRegistryMembers"
	listing.custom_minimum_size = Vector2(560, 130)
	column.add_child(listing)
	var refresh := func() -> void:
		listing.clear()
		for member: Dictionary in members:
			listing.add_item("%s / #%d / %s" % [member.site_id, int(member.person_id), member.label])
	refresh.call()
	var site_input := LineEdit.new()
	site_input.name = "FamilySite"
	site_input.text = str(lab.terrain.site.id)
	site_input.placeholder_text = "原 Site 識別"
	column.add_child(site_input)
	var path_input := LineEdit.new()
	path_input.name = "FamilySnapshotPath"
	path_input.text = "user://sites/" + str(lab.terrain.site.id).validate_filename() + ".json"
	path_input.placeholder_text = "異地原 Site 快照路徑"
	column.add_child(path_input)
	var person_input := SpinBox.new()
	person_input.name = "FamilyPersonId"
	person_input.min_value = 1
	person_input.max_value = 2147483647
	person_input.value = person_executor_id
	person_input.prefix = "原人物 ID "
	column.add_child(person_input)
	var label_input := LineEdit.new()
	label_input.name = "FamilyMemberLabel"
	label_input.placeholder_text = "家人稱呼（自行登錄）"
	column.add_child(label_input)
	var age_input := SpinBox.new()
	age_input.name = "FamilyMemberAge"
	age_input.min_value = -1
	age_input.max_value = 200
	age_input.value = -1
	age_input.prefix = "年齡 "
	column.add_child(age_input)
	_button(column, "加入此既有人物到待確認名單", "AddFamilyReference", func() -> void:
		members.append({"site_id": site_input.text.strip_edges(), "person_id": int(person_input.value), "path": path_input.text.strip_edges(), "label": label_input.text.strip_edges(), "age_years": int(age_input.value)})
		refresh.call())
	_button(column, "移除選取引用（不刪除人物）", "RemoveFamilyReference", func() -> void:
		if not listing.get_selected_items().is_empty():
			members.remove_at(listing.get_selected_items()[0])
			refresh.call())
	var complete := CheckBox.new()
	complete.name = "FamilyRegistryComplete"
	complete.text = "我確認這是完整家族名單（否則不得據此判定 Game Over）"
	complete.button_pressed = bool(lab.terrain.site.get("family", {}).get("complete", false))
	column.add_child(complete)
	_button(column, "查證原人物並提交登錄", "CommitFamilyRegistry", func() -> void:
		var result := family_continuity.register_members(members, complete.button_pressed)
		show_result(result)
		if result.ok:
			# Release the exclusive child synchronously before opening its successor.
			dialog.hide()
			dialog.get_parent().remove_child(dialog)
			dialog.queue_free()
			if is_instance_valid(_family_dialog):
				_family_dialog.hide()
				_family_dialog.get_parent().remove_child(_family_dialog)
				_family_dialog.queue_free()
				_family_dialog = null
			_open_family())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	(_family_dialog if is_instance_valid(_family_dialog) else lab.get_node("SiteUI")).add_child(dialog)
	dialog.popup_centered()

func _person_died(identity: int) -> void:
	_pending_deaths[identity] = float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"])

func settle_person_deaths(real_seconds: float) -> void:
	for identity: int in _pending_deaths.keys():
		_pending_deaths[identity] = maxf(0.0, float(_pending_deaths[identity]) - real_seconds)
		if float(_pending_deaths[identity]) > 0.0:
			continue # Resolve original owners only when the down animation can settle.
		var person := person_actions._person(identity)
		if person.is_empty():
			continue # Never silently lose a pending person's actual belongings.
		if float(person.hp) > 0.0:
			_pending_deaths.erase(identity) # Only explicit development reset can revive.
			continue
		if bool(person_actions._body_get(person, "loot_settled")):
			_pending_deaths.erase(identity)
			continue
		if bool(person.moving):
			continue
		var opened := _personal_opened_food(identity)
		var result := Runtime.leave_ground_loot(lab.terrain, person.holder, person.cargo, identity, person.cell, "remains", person.cargo, person.holder.item_ids.duplicate(), int(person.holder.version), opened, float(opened.get("open_rations", 0.0)))
		if not result.ok and str(result.code) != "EMPTY":
			continue # Preflight failure retains original items and blocks replacement/save.
		person_actions._body_set(person, "loot_settled", true)
		person_actions._body_set(person, "remains_id", str(result.get("container_id", "")))
		lab.terrain.site.get("captivity", {}).erase(str(identity))
		_pending_deaths.erase(identity)
		equipment_changed(identity)

func _presentation_holder(person: Dictionary) -> Dictionary:
	if float(person.hp) <= 0.0 and bool(person_actions._body_get(person, "loot_settled")):
		return lab.terrain.site.ground_loot.get(str(person.body.get("remains_id")), Runtime.new_item_state("empty-remains"))
	return person.holder

func equipment_removal_guard(identity: int, item_ids: Array) -> Dictionary:
	var person := person_actions._person(identity)
	if person.is_empty():
		return Runtime.ok() # Historical owner no longer has a scene body; ground items remain real.
	var proposed: Dictionary = _presentation_holder(person).duplicate(true)
	for slot: String in proposed.equipped.keys():
		if item_ids.has(proposed.equipped[slot]):
			proposed.equipped.erase(slot)
	return _equipment_holder_guard(person, proposed)

func equipment_apply_guard(identity: int, equipped: Dictionary) -> Dictionary:
	var person := person_actions._person(identity)
	if person.is_empty():
		return Runtime.fail("NO_TARGET")
	# Preflight may include real depot pieces not transferred yet. Derive only
	# the proposed appearance; no production holder or item record moves.
	var original: Dictionary = person.body.appearance if int(person.unit) >= 0 else person.owner._saved_appearance
	var appearance := original.duplicate(true)
	for slot: String in Runtime.EQUIPMENT_SLOTS:
		appearance.parts[slot] = "none"
	for slot: String in equipped:
		var record: Dictionary = lab.terrain.site.item_records.get(equipped[slot], {})
		var definition: Dictionary = lab.terrain.site.item_definitions.get(str(record.get("definition", "")), {})
		if definition.get("slot") != slot or definition.get("tint") != [1.0, 1.0, 1.0, 1.0]:
			return Runtime.fail("UNSUPPORTED", "此實物色彩／裝備槽尚未有原呈現支援")
		appearance.parts[slot] = str(definition.asset)
	return _equipment_recipe_guard(person, appearance)

func _equipment_holder_guard(person: Dictionary, proposed: Dictionary) -> Dictionary:
	var original: Dictionary = person.body.appearance if int(person.unit) >= 0 else person.owner._saved_appearance
	var appearance := Runtime.equipment_appearance(lab.terrain, proposed, original)
	return _equipment_recipe_guard(person, appearance)

func _equipment_recipe_guard(person: Dictionary, appearance: Dictionary) -> Dictionary:
	if appearance.is_empty():
		return Runtime.fail("INVALID", "實物配裝不能對應原人物")
	if int(person.unit) >= 0 and not person.owner._uses_live_presenter(int(person.unit)):
		if not lab.exchange_enabled and (not TerrainArmy.load_contact_source() or not TerrainArmy._contact_source.supports_appearance(appearance)):
			return Runtime.fail("UNSUPPORTED", "此配裝的原碰撞來源未就緒")
		if not person.owner.supports_equipment_recipe(appearance):
			return Runtime.fail("UNSUPPORTED", "此缺裝組合的完整原動畫圖集未就緒；未扣物")
	return Runtime.ok()

func _request_person_equipment(slot: String, asset: String, identity: int) -> String:
	if slot not in Runtime.EQUIPMENT_SLOTS:
		return asset # Body/face/hair are not loot or manufactured equipment.
	var current := str(person_appearance(identity).get("parts", {}).get(slot, "none"))
	if current == asset:
		return current
	var person := person_actions._person(identity)
	var item_id := ""
	if asset != "none" and not person.is_empty():
		for held: String in person.holder.item_ids:
			var definition: Dictionary = lab.terrain.site.item_definitions[lab.terrain.site.item_records[held].definition]
			if str(definition.slot) == slot and str(definition.asset) == asset and not person.holder.equipped.values().has(held):
				item_id = held
				break
	if asset != "none" and item_id.is_empty():
		show_result(Runtime.fail("NO_TARGET", "沒有本人實際持有的該件裝備；不能從外觀清單補物"))
	else:
		show_result(equipment_orders.begin_personal(identity, slot, item_id))
	return current # Actual appearance changes only after the timed atomic commit.

func equipment_changed(identity: int) -> void:
	var person := person_actions._person(identity)
	if person.is_empty():
		return
	var original: Dictionary = person.body.appearance if int(person.unit) >= 0 else (person.owner.editor.capture_appearance() if person.owner.editor != null else person.owner._saved_appearance)
	var appearance := Runtime.equipment_appearance(lab.terrain, _presentation_holder(person), original)
	if appearance.is_empty():
		return
	_equipment_appearances[identity] = appearance
	if int(person.unit) >= 0:
		var team: TerrainArmy = person.owner
		var presenter: Variant = team._unit_editor(int(person.unit))
		if team._uses_live_presenter(int(person.unit)) and presenter != null:
			presenter.restore_appearance(appearance)
		team._combat_pose_cache.erase(identity)
		team._visual_dirty = true
	else:
		var actor: TerrainTestCharacter = person.owner
		actor._saved_appearance = appearance.duplicate(true)
		if actor.editor != null:
			actor.editor.restore_appearance(appearance)
		actor._collision_shapes.clear()
	TerrainArmy.clear_contact_samples()

func _captivity_changed(identity: int, _captor_id: int, capturing: bool) -> void:
	var person := person_actions._person(identity)
	if person.is_empty():
		return
	if int(person.unit) >= 0:
		var team: TerrainArmy = person.owner
		team._cancel_unit_rescue(int(person.unit))
		person.body.attack = false
		person.body.previous = []
		person.body.hits = {}
		person.body.target = -1
		person.body.think = 0.5
		person.body.status = "被俘" if capturing else "已解除拘押"
		team._command_dirty = true
		team._visual_dirty = true
	else:
		var actor: TerrainTestCharacter = person.owner
		actor._cancel_rescue()
		actor._reload_left = 0.0
		actor.attack_target_id = 0
		actor.combat_status = "被俘" if capturing else "已解除拘押"
		if actor is TerrainTestNPC:
			(actor as TerrainTestNPC).issue_command(TerrainTestNPC.Command.STOP)
	equipment_changed(identity)

func _personal_opened_food(identity: int) -> Dictionary:
	return lab.terrain.site.get("person_supply", {}).get(str(identity), {})

func _receive_opened_food(identity: int, amount: float, original: Dictionary) -> void:
	# Called synchronously after the original loot preflight/transfer. No food
	# is converted to grain, and existing team/captive meal ownership stays put.
	var pool := _personal_opened_food(identity)
	assert((pool.is_empty() and original.is_empty()) or is_same(pool, original))
	if pool.is_empty():
		pool = Sustain.create(Runtime.now(lab.terrain) * 60.0)
		if not lab.terrain.site.has("person_supply"):
			lab.terrain.site.person_supply = {}
		lab.terrain.site.person_supply[str(identity)] = pool
	var states: Dictionary = captivity_supply._states()
	if pool.cohorts.is_empty() and captivity_supply._feeding_owner(identity, states).is_empty():
		# An old empty private store can lag safely; no living history is skipped.
		# Once the original person is independent again, eating must resume here.
		assert(_align_supply_clock(pool, Runtime.now(lab.terrain) * 60.0))
		assert(Sustain.add_members(pool, captivity_supply._all_members(), [identity]).ok)
	pool.open_rations = float(pool.open_rations) + amount

func _chosen_supply_team() -> TerrainArmy:
	return lab.player_army() if supply_team_choice == null or supply_team_choice.selected == 0 else lab.army

func _supply_entry(team: TerrainArmy) -> Dictionary:
	return lab.terrain.site.get("team_supply", {}).get(str(team.team_id), {}) if team != null else {}

func _team_members(team: TerrainArmy) -> Dictionary:
	var members := {}
	for index: int in team.combat_units.size():
		if team.is_member(index):
			members[team.combat_identity(index)] = team.combat_units[index]
	if is_instance_valid(team.player_member):
		members[team.player_member.person_id] = _actor_supply_adapter(team.player_member, team.player_present)
	return captivity_supply.team_members(team, members)

func _actor_supply_adapter(actor: TerrainTestCharacter, present: bool = false) -> Dictionary:
	var legacy_weapon := str(actor._saved_appearance.get("parts", {}).get("weapon", "none"))
	if actor.editor != null:
		var choice := actor.editor.part_options.get(&"weapon") as OptionButton
		if choice != null and choice.selected >= 0:
			legacy_weapon = str(choice.get_item_metadata(choice.selected))
	# Ephemeral field adapter; it is never stored in terrain.site.
	return {"person_id": actor.person_id, "hp": actor.hp, "ko": actor.knockout_left, "fatigue": actor.fatigue,
		"fatigue_rest": actor.fatigue_rest, "work_resting": actor.work_resting,
		"present": present, "captive": actor.captive, "is_player": actor.person_id == lab.controlled_person_id(),
		"item_state": actor.get("item_state"), "legacy_weapon": legacy_weapon}

func _all_supply_members() -> Dictionary:
	return captivity_supply._all_members()

func _life(body: Dictionary) -> int:
	return 2 if float(body.hp) <= 0 else (1 if float(body.get("ko", 0)) > 0 else 0)

func _enable_team_supply(team: TerrainArmy) -> Dictionary:
	var result: Dictionary = captivity_supply.enable_team(team)
	if not result.ok:
		show_result(result)
		return {}
	return result.entry

func _team_stopped(team: TerrainArmy) -> bool:
	if not team.combat_enabled or team.combat_order != TerrainArmy.CombatOrder.HOLD:
		return false
	for index: int in range(team.combat_units.size()):
		if not team.is_member(index):
			continue
		var unit: Dictionary = team.combat_units[index]
		if team.moving_to[index] != TerrainArmy.INVALID_CELL or bool(unit.attack) or str(unit.pose) in ["guard", "guard_raise", "guard_lower", "guard_break", "rescue", "get_up"]:
			return false
	if not is_instance_valid(team.player_member):
		return true
	var actor: TerrainTestCharacter = team.player_member
	# Stopped is a physical group condition, not this particular member's
	# capacity to receive food/train. An immobile casualty does not freeze peers.
	return not actor.is_moving() and actor.action_time <= 0.0 and not actor.guarding and actor.guard_transition_left <= 0.0 and actor.guard_break_left <= 0.0 and actor._rescue_left <= 0.0 and not actor._getting_up

func _supply_actor_ready(actor: TerrainTestCharacter) -> bool:
	return actor.can_act() and not actor.is_moving() and actor.action_time <= 0.0 and not actor.guarding and actor.guard_transition_left <= 0.0 and actor.guard_break_left <= 0.0 and actor._rescue_left <= 0.0

func team_food_capacity(team: TerrainArmy) -> float:
	var capacity := 0.0
	for index: int in team.combat_units.size():
		if team.is_member(index) and team.combat_can_act(index):
			capacity += 6.0 if bool(team.combat_units[index].get("logistics", false)) else 3.0
	if is_instance_valid(team.player_member) and team.player_member.can_act():
		capacity += 3.0
	return capacity

func order_team_logistics(team: TerrainArmy, identities: Array[int], requester_id: int, enabled: bool) -> Dictionary:
	if team == null or not team.combat_enabled or get_tree().paused or bool(lab.terrain.site.paused):
		return Runtime.fail("BUSY")
	team.settle_combat_command()
	var requester := team.index_for_identity(requester_id)
	if requester_id != lab.controlled_person_id() or requester != team.current_commander or not team.command_eligible(requester):
		return Runtime.fail("NO_AUTHORITY", "只有目前受控的原隊合格指揮者可明確指派專職後勤")
	if identities.is_empty() or not _team_stopped(team):
		return Runtime.fail("BUSY", "先停止原隊伍並選取既有自由隊員")
	var seen := {}
	for identity: int in identities:
		var index := team.index_for_identity(identity)
		if index < 0 or index == TerrainArmy.PLAYER_MEMBER or not team.is_member(index) or seen.has(identity):
			return Runtime.fail("INVALID_MEMBER")
		var person := person_actions._person(identity)
		if not _delivery_person_ready(person) or _is_delivering_person(identity):
			return Runtime.fail("BUSY", "原人物尚有作業；不替換其工作或身體")
		seen[identity] = true
	if not enabled:
		var reduced_capacity := team_food_capacity(team)
		for identity: int in identities:
			if bool(team.combat_units[team.index_for_identity(identity)].get("logistics", false)):
				reduced_capacity -= 3.0
		var entry := _supply_entry(team)
		if not entry.is_empty() and Sustain.rations(entry.sustain, entry.inventory) > reduced_capacity + 0.000000001:
			return Runtime.fail("STORAGE_FULL", "解除後勤會超載；請先實際交付共有口糧，不靜默丟物或帶超額出發")
	for identity: int in identities:
		team.combat_units[team.index_for_identity(identity)].logistics = enabled
	return Runtime.ok("已指定原人物專職後勤，每名可搬運者6日份；不另生貨物" if enabled else "已解除原人物專職後勤，恢復3日份載量")

func _delivery_person_ready(person: Dictionary) -> bool:
	if person.is_empty() or person_actions.is_busy(int(person.person_id)) or person_actions.is_guarding(int(person.person_id)) or work_team.is_assigned(int(person.person_id)):
		return false
	if int(person.unit) >= 0:
		return person.owner.combat_can_act(int(person.unit)) and not bool(person.moving) and not bool(person.body.attack) and str(person.body.pose) == "idle" and person.body.get("work_task", {}).is_empty()
	if not _supply_actor_ready(person.owner):
		return false
	if person.owner == lab.npc and (int(lab.npc.command) != TerrainTestNPC.Command.STOP or not lab.npc._path.is_empty()):
		return false
	var activity: Dictionary = lab.terrain.site.manual if person.owner == lab.character else lab.terrain.site.worker
	return str(activity.get("target", "")).is_empty()

func _is_delivering_person(identity: int) -> bool:
	for entry: Dictionary in lab.terrain.site.get("team_supply", {}).values():
		var job: Dictionary = entry.get("delivery", {})
		if not job.is_empty() and identity in [int(job.player_id), int(job.representative_id)]:
			return true
	return false

func begin_team_food(team: TerrainArmy, quantity: float, representative_id: int, source: Dictionary = {}) -> Dictionary:
	if get_tree().paused or bool(lab.terrain.site.paused):
		return Runtime.fail("BUSY")
	for existing: Dictionary in lab.terrain.site.get("team_supply", {}).values():
		if not existing.delivery.is_empty():
			return Runtime.fail("BUSY", "已有原口糧交付；可先取消")
	var prepared := food_delivery.prepare(team, quantity, representative_id, source)
	if not prepared.ok:
		return prepared
	var entry := _supply_entry(team)
	if entry.is_empty():
		entry = _enable_team_supply(team)
	if entry.is_empty():
		return Runtime.fail("BUSY", "原供養時段尚未收束；未重建餐份或扣物")
	entry.delivery = prepared.job
	return Runtime.ok("原口糧交付中；%.1f有效遊戲秒，完成並重查才轉移" % float(entry.delivery.left))

func cancel_team_food() -> Dictionary:
	for entry: Dictionary in lab.terrain.site.get("team_supply", {}).values():
		if not entry.delivery.is_empty():
			if int(entry.delivery.get("requester_id", -1)) != lab.controlled_person_id():
				return Runtime.fail("NO_AUTHORITY", "只能取消本人原先發起的口糧交付")
			entry.delivery = {}
			return Runtime.ok("已取消交糧；來源未扣物")
	return Runtime.fail("NO_TARGET", "沒有進行中的交付")

func _delivery_valid(team: TerrainArmy, entry: Dictionary) -> bool:
	return food_delivery.valid(team, entry)

func _delivery_people(entry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if entry.delivery.is_empty():
		return result
	for identity: int in [int(entry.delivery.player_id), int(entry.delivery.representative_id)]:
		if not result.is_empty() and int(result[0].person_id) == identity:
			continue # Camp/ground pickup has one original worker, not two copies.
		var person := person_actions._person(identity)
		if not person.is_empty():
			result.append(person)
	return result

func _delivery_active(entry: Dictionary) -> bool:
	if entry.delivery.is_empty() or bool(entry.delivery.get("pending", false)):
		return false
	var threats := {}
	for person: Dictionary in _delivery_people(entry):
		if int(person.person_id) == lab.controlled_person_id():
			continue
		var fatigue := float(person_actions._body_get(person, "fatigue"))
		var resting := PersonFatigue.needs_work_rest(fatigue, bool(person_actions._body_get(person, "work_resting")))
		person_actions._body_set(person, "work_resting", resting)
		if resting or person_actions._threat(person, threats):
			return false
	return true

func _delivery_seconds(entry: Dictionary, maximum: float) -> float:
	if not _delivery_active(entry):
		return maximum
	var people := _delivery_people(entry)
	var bound := maximum
	for person: Dictionary in people:
		if int(person.person_id) != lab.controlled_person_id():
			bound = minf(bound, maxf(0.0, PersonFatigue.WORK_REST_AT - float(person_actions._body_get(person, "fatigue"))) / PersonFatigue.WORK_RATE)
	var wanted := float(entry.delivery.left)
	var productive := INF
	for person: Dictionary in people:
		productive = minf(productive, PersonFatigue.work_seconds(float(person_actions._body_get(person, "fatigue")), bound))
	if productive <= wanted:
		return maxf(0.000000001, bound)
	var lower := 0.0
	var upper := bound
	for iteration: int in 40:
		var middle := (lower + upper) * 0.5
		var effort := INF
		for person: Dictionary in people:
			effort = minf(effort, PersonFatigue.work_seconds(float(person_actions._body_get(person, "fatigue")), middle))
		if effort < wanted:
			lower = middle
		else:
			upper = middle
	return upper

func _finish_delivery_step(team: TerrainArmy, entry: Dictionary, seconds: float) -> void:
	if entry.delivery.is_empty() or bool(entry.delivery.get("pending", false)):
		return
	if not _delivery_valid(team, entry):
		entry.delivery = {}
		message.text = "交糧條件已變更，當批取消；來源未扣物"
		return
	if not _delivery_active(entry):
		return # Original safe-rest loop recovers 80->50; original job stays queued.
	var productive := INF
	for person: Dictionary in _delivery_people(entry):
		var fatigue := float(person_actions._body_get(person, "fatigue"))
		productive = minf(productive, PersonFatigue.work_seconds(fatigue, seconds))
		var updated := PersonFatigue.advance(fatigue, float(person_actions._body_get(person, "fatigue_rest")), seconds, PersonFatigue.WORK_RATE, false)
		var autonomous: bool = int(person.person_id) != lab.controlled_person_id()
		if autonomous and updated[0] >= PersonFatigue.WORK_REST_AT - 0.000000001:
			updated[0] = PersonFatigue.WORK_REST_AT
			person_actions._body_set(person, "work_resting", true)
		person_actions._body_set(person, "fatigue", updated[0])
		person_actions._body_set(person, "fatigue_rest", updated[1])
		if int(person.unit) < 0:
			lab._fatigue_work_seconds[person.owner] = float(lab._fatigue_work_seconds.get(person.owner, 0.0)) + seconds
	entry.delivery.left = maxf(0.0, float(entry.delivery.left) - productive)
	if float(entry.delivery.left) <= 0.00000001:
		entry.delivery.left = 0.0
		entry.delivery.pending = true

func settle_supply_deliveries() -> void:
	if get_tree().paused or bool(lab.terrain.site.paused):
		return
	for team: TerrainArmy in lab.combat_armies:
		var entry := _supply_entry(team)
		if entry.is_empty():
			continue
		if not entry.delivery.is_empty() and bool(entry.delivery.get("pending", false)):
			var result := food_delivery.commit(team, entry)
			if not result.ok:
				entry.delivery = {}
			message.text = str(result.message)
		# Post-contact/death landing. Later losses, an actual retreat, or total
		# incapacitation may require another excess drop without a morale rout.
		var dropped := food_delivery.drop_excess(team)
		if dropped.ok and dropped.has("container_id"):
			message.text = "超額共有口糧已一次留在原人物現場；敵我均須實際接近搬取"

func order_team_training(team: TerrainArmy, requester: int, enabled: bool) -> Dictionary:
	if team == null or not team.combat_enabled:
		return Runtime.fail("NO_TARGET")
	team.settle_combat_command()
	if get_tree().paused or requester != team.current_commander or not team.command_eligible(requester):
		return Runtime.fail("NO_AUTHORITY", "只有當前在場合格指揮者可下訓練令")
	if enabled and (not _team_stopped(team) or float(lab.terrain.site.combat_left) > 0):
		return Runtime.fail("BUSY", "須先守位停止並脫戰")
	var entry := _enable_team_supply(team)
	if entry.is_empty():
		return Runtime.fail("BUSY", "原供養時段尚未收束，未重建餐份")
	entry.training_order = enabled
	entry.training_requester = team.combat_identity(requester) if enabled else -1
	return Runtime.ok("訓練令已保留；足額供餐、安全且實際持武器者才參訓" if enabled else "已停止訓練；保留既有訓練與疲勞")

func _armed(body: Dictionary) -> bool:
	var holder: Variant = body.get("item_state")
	if not holder is Dictionary or holder.is_empty():
		# Existing non-ledger combat still uses actual fixed manifest/player slots.
		# This reads that weapon only; it never creates owned items or loot.
		var actual := str(body.get("legacy_weapon", "none"))
		if body.has("visual_role"):
			actual = str(TerrainArmy._combat_bake.get("manifest", {}).get("appearance", {}).get("parts", {}).get("weapon", "none"))
		return actual not in ["", "none"]
	var item := str(holder.get("equipped", {}).get("weapon", ""))
	if item not in holder.get("item_ids", []) or str(holder.get("holder", "")) != "person:%d" % int(body.get("person_id", 0)):
		return false
	var record: Dictionary = lab.terrain.site.get("item_records", {}).get(item, {})
	var definition: Dictionary = lab.terrain.site.get("item_definitions", {}).get(str(record.get("definition", "")), {})
	return not item.is_empty() and str(record.get("holder", "")) == str(holder.get("holder", "")) and str(definition.get("slot", "")) == "weapon" and str(definition.get("asset", "none")) not in ["", "none"]

func _team_safe(team: TerrainArmy, members: Dictionary) -> bool:
	var candidates := {}
	for index: int in team.combat_units.size():
		if team.is_member(index) and not bool(team.combat_units[index].captive) and float(team.combat_units[index].hp) > 0 and lab._fatigue_threat(team.cells[index], team.faction_id, team, index, candidates):
			return false
	if is_instance_valid(team.player_member) and members.has(team.player_member.person_id) and team.player_member.hp > 0 and lab._fatigue_threat(team.player_member.terrain_cell, team.faction_id, team.player_member, -1, candidates):
		return false
	return true

func _observe_team_life(team: TerrainArmy, entry: Dictionary, members: Dictionary) -> void:
	var deaths := 0
	var knockouts := 0
	var living_before := 0
	for key: String in entry.life_checkpoint:
		if team.index_for_identity(int(key)) < 0:
			continue # Feeding a foreign captive is not enrolling a combatant.
		var old := int(entry.life_checkpoint[key])
		living_before += int(old != 2)
		if members.has(int(key)):
			var current := _life(members[int(key)])
			deaths += int(current == 2 and old != 2)
			knockouts += int(current == 1 and old == 0)
	var qualified := team.current_commander >= 0 and team.command_eligible(team.current_commander)
	if living_before > 0 and (deaths > 0 or knockouts > 0 or bool(entry.sustain.commander_present) != qualified):
		var leadership := _team_ability(team, "leadership")
		Sustain.combat_event(entry.sustain, int(entry.sustain.last_combat_event) + 1, living_before, deaths, knockouts, qualified, leadership)
	for id: Variant in members:
		entry.life_checkpoint[str(id)] = _life(members[id])

func _team_ability(team: TerrainArmy, kind: String) -> float:
	var value := 0.0
	for index: int in team.command_abilities:
		if team.command_eligible(index):
			value += float(team.command_abilities[index].get(kind, 0))
	if is_instance_valid(team.player_member) and team.command_eligible(TerrainArmy.PLAYER_MEMBER):
		value += float(team.player_member.command_abilities.get(kind, 0))
	return value

func advance_team_sustain(team: TerrainArmy, elapsed_game_seconds: float) -> Dictionary:
	# Root calls this ONLY from the existing common Site action step, not tick().
	var handled := {}
	var entry := _supply_entry(team)
	if entry.is_empty() or elapsed_game_seconds <= 0 or get_tree().paused or bool(lab.terrain.site.paused):
		return {"handled_ids": [], "handled_seconds": handled}
	var left := elapsed_game_seconds
	while left > 0.000000001:
		if not entry.delivery.is_empty() and not _delivery_valid(team, entry):
			entry.delivery = {}
			message.text = "交糧中止；來源未扣物"
		var seconds := _delivery_seconds(entry, left)
		var members := _team_members(team)
		var was_routed := bool(entry.sustain.routed)
		_observe_team_life(team, entry, members)
		var safe := _team_safe(team, members)
		var stopped := _team_stopped(team)
		var hp_before := {}
		for id: Variant in members:
			hp_before[id] = float(members[id].hp)
		var outcome := Sustain.advance_to(entry.sustain, members, entry.inventory, float(entry.sustain.at) + seconds, {"safe": safe, "stopped": stopped})
		if not outcome.ok:
			message.text = "隊伍供養資料無效，未推進：" + str(outcome.message)
			return {"handled_ids": handled.keys(), "handled_seconds": handled}
		if float(outcome.consumed_rations) > 0:
			entry.revision = int(entry.revision) + 1
		for id: Variant in outcome.damage:
			# Sustain has already settled an exact zero endpoint. Forward that
			# result through the original death entrypoint, not a subtractive tail.
			var loss := float(hp_before[id]) if float(members[id].hp) == 0.0 else float(outcome.damage[id])
			members[id].hp = float(hp_before[id])
			members[id].hp = _apply_supply_damage(int(id), loss)
		for id: Variant in members:
			entry.life_checkpoint[str(id)] = _life(members[id]) # Hunger isn't a combat casualty event.
		if bool(entry.sustain.routed) and not was_routed:
			_start_supply_rout(team)
		elif bool(entry.sustain.routed) and team.combat_order == TerrainArmy.CombatOrder.HOLD and stopped and not safe:
			# A HOLD order cannot permanently cancel an available forced escape.
			# Bounded game-time review, not a path search on every combat sample.
			_supply_rout_review[team.team_id] = float(_supply_rout_review.get(team.team_id, 0.0)) + seconds
			if float(_supply_rout_review[team.team_id]) >= 2.0:
				_supply_rout_review[team.team_id] = 0.0
				_start_supply_rout(team)
		if bool(outcome.regrouped):
			team.combat_order = TerrainArmy.CombatOrder.HOLD
			team.combat_attacking = false
			team.needs_attack_order = true
			team.combat_goal = TerrainArmy.INVALID_CELL
			team.command_status = "整補完成；守位自衛，等待新進攻令"
		var fed: bool = not entry.sustain.cohorts.is_empty()
		for cohort: Dictionary in entry.sustain.cohorts:
			if float(cohort.coverage) < 1.0:
				fed = false
		var eligible: Array[int] = []
		for id: Variant in members:
			var delivering := _is_delivering_person(int(id))
			if _armed(members[id]) and not bool(members[id].get("logistics", false)) and not delivering and not _person_has_duty(int(id)):
				eligible.append(int(id))
		var commander := team.index_for_identity(int(entry.training_requester))
		var training := Sustain.train(team.training, members, eligible, seconds,
			{"ordered": bool(entry.training_order), "commander": commander >= 0 and commander == team.current_commander and team.command_eligible(commander),
			"safe": safe, "stopped": stopped, "fed": fed, "routed": bool(entry.sustain.routed), "coach": _team_ability(team, "coach"),
			"controlled_person_id": lab.controlled_person_id()})
		if training.ok:
			team.training = float(training.training)
			for id: Variant in training.handled_ids:
				handled[id] = float(handled.get(id, 0.0)) + seconds
		for original: TerrainTestCharacter in [lab.character, lab.npc]:
			if members.has(original.person_id):
				var adapter: Dictionary = members[original.person_id]
				original.fatigue = float(adapter.fatigue)
				original.fatigue_rest = float(adapter.fatigue_rest)
				original.work_resting = bool(adapter.work_resting)
		if not entry.delivery.is_empty() and _delivery_active(entry) and _delivery_valid(team, entry):
			for person: Dictionary in _delivery_people(entry):
				if int(person.unit) >= 0:
					var identity := int(person.person_id)
					handled[identity] = float(handled.get(identity, 0.0)) + seconds
		_finish_delivery_step(team, entry, seconds)
		left -= seconds
	return {"handled_ids": handled.keys(), "handled_seconds": handled}

func team_is_routed(team: TerrainArmy) -> bool:
	var entry := _supply_entry(team)
	return not entry.is_empty() and bool(entry.sustain.routed)

func _start_supply_rout(team: TerrainArmy) -> void:
	# Reuse original movement/commit machinery; player movement stays autonomous.
	team.combat_attacking = false
	team.needs_attack_order = true
	team.pursuit_left = 0.0
	team.combat_order = TerrainArmy.CombatOrder.HOLD
	team.combat_goal = TerrainArmy.INVALID_CELL
	var origin := Vector2i(team.command_reference.floor())
	var candidates := {}
	var pending: Array[Vector2i] = [origin]
	var distances := {origin: 0}
	var cursor := 0
	while cursor < pending.size() and cursor < 512:
		var cell := pending[cursor]
		cursor += 1
		if int(distances[cell]) > 0 and not team._is_external_cell(cell) and not lab._fatigue_threat(cell, team.faction_id, team, 0, candidates):
			team.combat_goal = cell
			team.combat_order = TerrainArmy.CombatOrder.RETREAT
			team._translate_combat_slots(cell)
			team.command_status = "士氣潰退；收束原動作後沿合法通路撤退"
			return
		if int(distances[cell]) >= 16:
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not distances.has(next) and lab.terrain.can_step(cell, next):
				distances[next] = int(distances[cell]) + 1
				pending.append(next)
	team.combat_slots.assign(team.cells)
	team.command_status = "士氣潰退但無安全合法退路；就地自衛"

func move_team_supply_members(source: TerrainArmy, target: TerrainArmy, ids: Array[int]) -> Dictionary:
	# Military registration is not always feeding ownership (captives/personal
	# meals). Resolve and preflight all original cohort moves before row mutation.
	return captivity_supply.move_roster(source, target, ids)

func before_clear_team_supply(team: TerrainArmy) -> void:
	# Explicit test-roster removal does not erase stock still at its supply owner.
	var entry := _supply_entry(team)
	if entry.is_empty():
		return
	entry.delivery = {}
	if is_instance_valid(team.player_member):
		player_supply_change(team, team.player_member, false)
	entry.training_order = false
	entry.training_requester = -1
	entry.sustain.cohorts = []
	entry.life_checkpoint = {}

func _align_supply_clock(state: Dictionary, at_seconds: float) -> bool:
	if state.cohorts.is_empty() and float(state.at) < at_seconds:
		# An empty former owner may legitimately lag in a saved Site. Advancing
		# no members consumes no food and preserves opened stock; never skip a
		# populated owner's hunger interval or wind a future state backwards.
		var advanced := Sustain.advance_to(state, {}, {}, at_seconds)
		if not advanced.ok:
			return false
	if absf(float(state.at) - at_seconds) > 0.00001:
		return false
	state.at = at_seconds
	for cohort: Dictionary in state.cohorts:
		if absf(float(cohort.meal_until) - at_seconds) <= 0.00001:
			cohort.meal_until = at_seconds
	return true

func player_supply_change(team: TerrainArmy, actor: TerrainTestCharacter, joining: bool) -> Dictionary:
	# Same original membership transaction for Actors and Army rows, including
	# the captor's dependent meal histories; never move shared/private stock.
	return captivity_supply.membership_change(team, actor.person_id, joining)

func _apply_supply_damage(identity: int, loss: float) -> float:
	var person: Dictionary = lab._combat_target(identity)
	if person.is_empty():
		return 0.0
	var packet := {"result": {"hp": loss, "stun": 0.0, "guard_break": false}, "shield": false, "environmental": true}
	if int(person.unit) >= 0:
		person.owner.apply_unit_contact(int(person.unit), packet)
		return float(person.owner.combat_units[int(person.unit)].hp)
	person.owner.apply_contact(packet)
	return float(person.owner.hp)

func advance_person_supply(elapsed_game_seconds: float) -> void:
	if elapsed_game_seconds <= 0 or get_tree().paused or bool(lab.terrain.site.paused):
		return
	for owner_id: String in lab.terrain.site.get("person_supply", {}):
		var personal: Dictionary = lab.terrain.site.person_supply[owner_id]
		if personal.is_empty():
			continue
		var person := person_actions._person(int(owner_id))
		if person.is_empty():
			message.text = "個人供養原人物不存在，保留其原物资與餐份資料"
			continue
		var members := captivity_supply.personal_members_id(int(owner_id))
		var prior := {}
		for id: int in members:
			prior[id] = float(members[id].hp)
		var result := Sustain.advance_to(personal, members, person.cargo, float(personal.at) + elapsed_game_seconds)
		if not result.ok:
			message.text = "個人供養資料無效：" + str(result.message)
			continue
		if float(result.consumed_rations) > 0.0:
			person.holder.version = int(person.holder.version) + 1
		for id: Variant in result.damage:
			var loss := float(prior[id]) if float(members[id].hp) == 0.0 else float(result.damage[id])
			members[id].hp = float(prior[id])
			_apply_supply_damage(int(id), loss)

func _update_team_supply_ui() -> void:
	if team_supply_label == null:
		return
	var team := _chosen_supply_team()
	var entry := _supply_entry(team)
	if entry.is_empty():
		team_supply_label.text = "尚未啟用供養。點選相鄰隊員交糧，或由合格隊長下訓練令。\n只取玩家指定交出的實際口糧；不動營地物資。"
		return
	var maximum_hunger := 0.0
	for cohort: Dictionary in entry.sustain.cohorts:
		maximum_hunger = maxf(maximum_hunger, float(cohort.hunger))
	team_supply_label.text = "本隊餘糧 %.2f／%.0f 日份 · 士氣 %.1f\n最高等效缺糧 %.1f 小時 · 訓練 %.2f\n%s%s" % [Sustain.rations(entry.sustain, entry.inventory), team_food_capacity(team), float(entry.sustain.morale), maximum_hunger, team.training, "潰退；須安全足額整補 30 分且士氣≥50" if bool(entry.sustain.routed) else ("訓練令保留：缺糧／受威脅／缺實裝即停止增長" if bool(entry.training_order) else "未下訓練令"), "\n交糧剩餘 %.1f 有效秒；可取消，完成前不扣物" % float(entry.delivery.left) if not entry.delivery.is_empty() else ""]
