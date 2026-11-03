class_name SiteController
extends Node

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const CrowdOwner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const View = preload("res://scripts/terrain_lab/site_resource_view.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const TrainingGround = preload("res://scripts/terrain_lab/site_training_ground.gd")
const Garrison = preload("res://scripts/terrain_lab/site_garrison.gd")
const FoodDelivery = preload("res://scripts/terrain_lab/site_food_delivery.gd")
const PersonActions = preload("res://scripts/terrain_lab/site_person_actions.gd")
const CaptivitySupply = preload("res://scripts/terrain_lab/site_captivity_supply.gd")
const PoliticalAdoption = preload("res://scripts/terrain_lab/site_political_adoption.gd")
const EquipmentOrders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const CaptiveEscort = preload("res://scripts/terrain_lab/site_captive_escort.gd")
const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const TechWindow = preload("res://scripts/terrain_lab/site_tech_window.gd")
var _tech_window := TechWindow.new()
const WorkTeam = preload("res://scripts/terrain_lab/site_work_team.gd")
const Vehicles = preload("res://scripts/terrain_lab/site_vehicle_transport.gd")
const SiegeWorkAppend = preload("res://scripts/terrain_lab/site_siege_work_append.gd")
const VehicleView = preload("res://scripts/terrain_lab/site_vehicle_view.gd")
const MODES := ["查看", "手動採集", "隊員採集區", "清理區", "勘探區", "建設區", "馬羊捕捉區", "復育原生植被區"]
const FORMATION_DESCRIPTIONS := {
	"auto": "依地形站位，可使用進路待命",
	"square": "密集近方形",
	"circle": "實心圓形，外緣朝外",
	"wedge": "前窄後寬的楔形",
	"goose": "逐列側移的斜列",
	"hook": "前線與兩翼回折",
	"loose": "每人相隔一格",
}
const PANEL_SCALE := 1.35
const REGION_MAP_SCENE := "res://scenes/region_lab/RegionLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const COMBAT_ORDER_NAMES := ["守位", "接敵", "移動", "撤退", "追擊", "返隊", "衝鋒", "重整"]
var lab: Node2D
var view: Node2D
var panel: PanelContainer
var top_banner: PanelContainer
var status_panel: PanelContainer
var combat_window: Window
var launcher_window: Window
var formal_windows: Dictionary = {}
var _formal_columns: Dictionary = {}
var formal_team_choice: OptionButton
var _formal_team_signature := ""
var _formation_views: Dictionary = {}
var _active_formation_view := "formal"
var _vehicle_forms: Dictionary = {}
var _siege_construction_form: Dictionary = {}
var _tent_form: Dictionary = {}
var _ui_dialogs: Dictionary = {}
var _test_pages: Dictionary = {}
var _trial_fire_ui: Dictionary = {}
var _ui_control_id := -1
var clock_label: Label
var fps_label: Label
var speed_label: Label
var player_status_label: Label
var tool_status_label: Label
var details: Label
var stock_label: Label
var worker_label: Label
var assign_worker_button: Button
var message: Label
var zones: VBoxContainer
var modes: OptionButton
var kinds: OptionButton
var buildings: OptionButton
var building_variant: OptionButton
var building_direction: OptionButton
var building_material: OptionButton
var building_width: SpinBox
var building_depth: SpinBox
var building_size_row: HBoxContainer
var building_policy: Label
var building_selection: Label
var building_parts: OptionButton
var building_recipe: OptionButton
var building_actions: Dictionary = {}
var building_resize := false # Draft UI mode; feature_key remains the sole selected building.
var _building_controls_sync := false
var _building_quarter := 0
var pause_button: Button
var manual_capture_button: Button
var ecology_status: Label
var ecology_modes: OptionButton
var ecology_apply_button: Button
var manual_restore_button: Button
var _ecology_revisions := {}
var _ecology_selection_signature := ""
var _ecology_ui_cache_key: Array = []
var _ecology_ui_cache_text := ""
var _ecology_ui_cache_description := ""
var stock_pasture_button: Button
var saved_sites: OptionButton
var legend: Label
var player_army_label: Label
var team_info_label: Label
var _team_info_report := ""
var _team_info_overview: Label
var _team_info_list: VBoxContainer
var _team_info_report_button: Button
var _team_info_cards := {}
var team_supply_label: Label
var supply_team_choice: OptionButton
var supply_quantity: SpinBox
var combat_summary_label: Label
var trial_friendly_count: SpinBox
var trial_enemy_count: SpinBox
var trial_friendly_female_percent: SpinBox
var trial_enemy_female_percent: SpinBox
var trial_friendly_gender_label: Label
var trial_enemy_gender_label: Label
var trial_friendly_training: SpinBox
var trial_enemy_training: SpinBox
var trial_friendly_tactics: SpinBox
var trial_enemy_tactics: SpinBox
var trial_friendly_leadership: SpinBox
var trial_enemy_leadership: SpinBox
var trial_friendly_coach: SpinBox
var trial_enemy_coach: SpinBox
var trial_friendly_order: OptionButton
var trial_enemy_order: OptionButton
var trial_entry_direction: OptionButton
var trial_friendly_entry: OptionButton
var trial_enemy_entry: OptionButton
var trial_third_entry: OptionButton
var trial_friendly_spawn_label: Label
var trial_enemy_spawn_label: Label
var trial_friendly_spawn := Vector2i(-1, -1)
var trial_enemy_spawn := Vector2i(-1, -1)
var trial_third_enabled: CheckBox
var trial_third_faction: OptionButton
var trial_third_count: SpinBox
var trial_third_female_percent: SpinBox
var trial_third_gender_label: Label
var trial_third_training: SpinBox
var trial_third_tactics: SpinBox
var trial_third_leadership: SpinBox
var trial_third_coach: SpinBox
var trial_third_order: OptionButton
var trial_third_spawn_label: Label
var trial_third_spawn := Vector2i(-1, -1)
var trial_roles: Dictionary = {}
var trial_ai_enabled: Dictionary = {}
var trial_troop_types: Dictionary = {}
var trial_carts: Dictionary = {}
var trial_wagons: Dictionary = {}
var trial_command_team: OptionButton
var trial_friendly_teams: SpinBox
var trial_enemy_teams: SpinBox
var trial_third_teams: SpinBox
var trial_batch_status: Label
var _trial_team_choice_signature := ""
var _trial_team_choices_initialized := false
var _combat_ui_elapsed := 0.0
var trial_ai_status_label: Label
var trial_retreat_button: Button
var player_retreat_button: Button
# CAV-4b: crowd cavalry orders, enabled only for a cavalry team (site_controller _update_combat_window).
var trial_charge_button: Button
var trial_rally_button: Button
var player_charge_button: Button
var player_rally_button: Button
var test_retreat_button: Button
var formation_command_source: OptionButton
var formation_preset_choice: OptionButton
var formation_status_label: Label
var formation_apply_button: Button
var selected := Vector2i(-1, -1)
var source_key := ""
var feature_key := ""
var drag_start := Vector2i(-1, -1)
var _facing_order_source := ""
var _crowd_facing := false
var _facing_order_anchor := Vector2i(-1, -1)
var _facing_preview_direction := Vector2i.ZERO
var _facing_preview_pending := false
var _facing_team: TerrainArmy
var _facing_team_id := -1
var _facing_requester_identity := -1
var _facing_terrain: TerrainData
var _facing_preset_id := ""
var _facing_order_serial := -1
var _facing_roster_hash := 0
var _facing_navigation_revision := -1
var _formation_candidate_id := ""
var _formation_candidate_source := ""
var _formation_candidate_team: TerrainArmy
var _formation_candidate_team_id := -1
var _formation_candidate_requester_identity := -1
var _formation_candidate_terrain: TerrainData
var _formation_preview_signature := ""
var _formation_preview_note := ""
var build_cells: Array[int] = []
var save_path := Store.DEFAULT_PATH
var save_root := "user://sites"
var crowd_test_run_id := ""
var _test_path_error := ""
var refresh_hidden_combat_summary_on_tick := false
var _ui_elapsed := 0.0
var _work_elapsed := 0.0
var _settlement_elapsed := 0.0 # Real-time throttle; the capture timer itself is in Site game seconds.
var _settlement_game_seconds := 0.0
var _save_elapsed := 0.0
var _navigation_revision := -1
var _zone_signature := ""
var _exit_pending := false
var _exit_dialog: ConfirmationDialog
var _auto_save_blocked := false
var _boot_request: Dictionary = {} # Main-menu/Region request; the placeholder Site is never saved.
var _region_manifest_path := RegionData.DEFAULT_MANIFEST
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
var vehicles := Vehicles.new()
var vehicle_view: Node2D
var vehicle_choice: OptionButton
var vehicle_operator_choice: OptionButton
var vehicle_resource_choice: OptionButton
var vehicle_resource_quantity: SpinBox
var vehicle_status: Label
var vehicle_depot_item: OptionButton
var vehicle_loaded_item: OptionButton
var _crew_handled: Dictionary = {}
var _shared_worker_inputs: Dictionary = {} # One original selection, held only for this shared step.
var _shared_work_plan: Dictionary = {}
var _family_dialog: AcceptDialog
var _family_wait := false
var _equipment_appearances: Dictionary = {} # Derived, event-updated; never saved as inventory.
var _equipment_dialog: AcceptDialog
var _equipment_sync: Callable
var _equipment_result: Callable
var _team_equipment_dialog: AcceptDialog
var _team_equipment_sync: Callable
var _team_equipment_result: Callable
var _pending_deaths: Dictionary = {} # Only newly dead original people; no corpse-wide tick.
var person_executor_id := 0
var region_slot: RegionSaveSlot
var _ship_journey: Dictionary = {} # Original Slot job projection, never a second persisted clock/roster.
var _region_pending: Dictionary = {} # Uncommitted fixed-target original cold replay request only.
var _region_form: Dictionary = {}

var _audio_volume_slider: HSlider
var _audio_mute_toggle: CheckButton

func get_region_slot() -> RegionSaveSlot:
	return region_slot

func record_completed_region_step(action_seconds: float, game_seconds: float, permit: Dictionary = {}, fire_step: Dictionary = {}) -> Dictionary:
	if not is_finite(action_seconds) or action_seconds < 0.0 or not is_finite(game_seconds) or game_seconds < 0.0: return Runtime.fail("INVALID_TIME", "完成原步進秒數非法")
	if region_slot == null: return Runtime.ok()
	var recorded: Dictionary = region_slot.record_active_step(lab.terrain.site, game_seconds, permit, fire_step)
	if not recorded.ok:
		latch_original_step_fault(recorded)
		show_result(recorded)
		return recorded
	_release_disabled_journey_operators()
	if not _ship_journey.is_empty() and not bool(lab.terrain.site.get("paused", false)) and _journey_can_advance():
		if str(_ship_journey.phase) == "return":
			_ship_journey.return_elapsed_action_seconds = minf(float(_ship_journey.return_required_action_seconds), float(_ship_journey.return_elapsed_action_seconds) + action_seconds)
		else:
			_ship_journey.elapsed_action_seconds = minf(float(_ship_journey.seconds), float(_ship_journey.elapsed_action_seconds) + action_seconds)
		_ship_journey["checkpoint_due"] = float(_ship_journey.get("checkpoint_due", 0.0)) + action_seconds
	# This is AFTER the original complete body/food/death phase and sole global
	# publication. Bind only here; Controller.tick must not replace a half-step.
	if not bool(lab.terrain.site.get("paused", false)) and not lab._region_deferring_endpoint(): _finish_ship_journey_tick()
	return recorded



func setup(scene: Node2D) -> void:
	lab = scene
	configure_test_paths(OS.get_cmdline_user_args())
	if not lab.restore_only: get_tree().root.focus_exited.connect(_cancel_facing_move)
	food_delivery.init(self)
	vehicles.init(self)
	if lab.terrain != null and lab.has_method("siege_save_guard"): lab.terrain.set_meta(&"siege_event_guard", lab.siege_save_guard)
	if lab.terrain != null and lab.has_method("fire_save_guard"): lab.terrain.set_meta(&"fire_event_guard", lab.fire_save_guard)
	if lab.terrain != null and lab.has_method("fire_pending_projectile_query"): lab.terrain.set_meta(&"fire_pending_projectile_query", lab.fire_pending_projectile_query)
	view = View.new()
	view.faction_query = func(faction: int) -> Dictionary: return region_slot.faction_display(faction) if region_slot != null else RegionFactionQuery.display({}, faction)
	view.name = "SiteResources"
	lab.add_child(view)
	# Same-row props are behind the existing actors; northern actors still sort behind roofs.
	lab.move_child(view, lab.character.get_index())
	_build_ui()
	vehicle_view = VehicleView.new()
	vehicle_view.name = "SiteVehicles"
	lab.add_child(vehicle_view)
	vehicle_view.setup(lab)
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.combat_event.connect(_combat_event)
		actor.died.connect(_person_died)
	for team: TerrainArmy in lab.combat_armies:
		wire_combat_team(team)
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.escort_step_guard = captive_escort.permits_step
	person_actions.equipment_removal_guard = equipment_removal_guard
	person_actions.custody_removal_guard = custody_removal_guard
	person_actions.equipment_changed = equipment_changed
	person_actions.opened_food_pool = _personal_opened_food
	person_actions.opened_food_commit = _receive_opened_food
	captivity_supply.init(self)
	person_actions.captivity_change_guard = captivity_supply.change_guard
	person_actions.captivity_supply_commit = captivity_supply.commit_change
	person_actions.captivity_changed = _captivity_changed
	person_actions.ransom_exchange_query = captivity_supply.ransom_exchange_query
	person_actions.ransom_exchange_committed = captivity_supply.ransom_exchange_committed
	person_actions.coin_ransom_query = captivity_supply.coin_ransom_query
	person_actions.coin_ransom_committed = captivity_supply.coin_ransom_committed
	person_actions.coin_ransom_carried_query = captivity_supply.coin_ransom_carried_query
	equipment_orders.init(lab, person_actions)
	equipment_orders.nation_build_request = _nation_build_request
	equipment_orders.nation_arsenal_request = _nation_arsenal_request
	equipment_orders.nation_course_request = person_actions.begin_nation_funded_course
	equipment_orders.nation_route_query = nation_route_query
	equipment_orders.nation_route_request = nation_route_request
	equipment_orders.nation_owner_receipt_query = person_actions.nation_original_receipt_query
	equipment_orders.equipment_apply_guard = equipment_apply_guard
	equipment_orders.equipment_dye_guard = equipment_dye_guard
	equipment_orders.equipment_team_apply_guard = _equipment_team_holder_guard
	equipment_orders.equipment_team_external_duty_guard = _equipment_team_external_duty_guard
	family_continuity.load_site_query = _load_compatible_site
	family_continuity.archive_current = _archive_family_site
	family_continuity.control_selected = _control_family_person
	family_continuity.commit_live_handover = _handover_family_person
	work_team.unavailable = _work_person_unavailable
	work_team.vehicle_blocked = vehicles.blocks_cell
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.cell_blocker = _actor_blocked
		actor.step_blocker = _actor_step_blocked
	if not lab.restore_only:
		get_tree().root.size_changed.connect(_layout)
		get_tree().root.close_requested.connect(_request_exit)
		get_tree().auto_accept_quit = false
		_layout()

func wire_combat_team(team: TerrainArmy) -> void:
	team.vehicle_transport = vehicles
	team.combat_event.connect(_combat_event)
	team.died.connect(_person_died)
	team.equipment_initializer = initialize_team_items
	team.equipment_appearance_query = person_appearance
	team.equipment_appearance_batch_query = person_appearance_batch
	team.cape_retirement = retire_officer_capes
	team.cape_departure_guard = cape_departure_guard
	team.person_busy_query = _person_has_duty
	team.controlled_person_query = lab.controlled_person_id
	team.membership_change_hook = _ship_membership_change
	team.escort_step_guard = captive_escort.permits_step
	team.roster_transfer_hook = move_team_supply_members
	team.sustain_routed_query = team_is_routed
	team.player_supply_hook = player_supply_change

func bind() -> void:
	_region_departure_intent.clear() # Source replacement invalidates only the volatile command.
	invalidate_ui_context()
	var data: TerrainData = lab.terrain
	_restore_ship_journey()
	data.set_meta(&"ship_journey_active", Callable(self, "ship_journey_active"))
	data.set_meta(&"region_operation_pending", Callable(self, "region_operation_pending"))
	data.set_meta(&"ship_vehicle_in_journey", Callable(self, "ship_vehicle_in_journey"))
	data.set_meta(&"settlement_grade_cap", Callable(self, "settlement_grade_cap"))
	_settlement_elapsed = 0.0
	_settlement_game_seconds = 0.0
	if lab.actor_present(lab.character):
		lab.character.ammo_inventory = data.site.manual.cargo
	if lab.actor_present(lab.npc):
		lab.npc.ammo_inventory = data.site.worker.cargo
	_equipment_appearances.clear()
	_pending_deaths.clear()
	person_actions.init(lab)
	captive_escort.init(lab, person_actions)
	family_continuity.init(lab)
	work_team.init(lab)
	vehicles.init(self)
	_crew_handled.clear()
	if lab.has_method("siege_save_guard"): data.set_meta(&"siege_event_guard", lab.siege_save_guard)
	if lab.has_method("fire_save_guard"): data.set_meta(&"fire_event_guard", lab.fire_save_guard)
	if lab.has_method("fire_pending_projectile_query"): data.set_meta(&"fire_pending_projectile_query", lab.fire_pending_projectile_query)
	_family_wait = false
	captivity_supply.init(self)
	person_executor_id = lab.controlled_person_id()
	for actor: TerrainTestCharacter in lab.combat_actors:
		# Capture through the actor owner before item/legacy-cape preflight reads
		# _saved_appearance; a live editor alone has not published that snapshot.
		var original: Dictionary = actor.capture_state().appearance
		if actor.person_id != lab.controlled_person_id() and actor.item_state.is_empty() and not original.has("equipment_dyes"):
			original = _initial_uniform(original, actor.faction_id)
		var initialized := Runtime.seed_person_equipment(data, actor.item_state, actor.person_id, original)
		if not initialized.ok:
			show_result(initialized)
			continue
		reconcile_cape_roles([actor.person_id])
		equipment_changed(actor.person_id)
		if actor.editor != null:
			actor.editor.part_selection_request = _request_person_equipment.bind(actor.person_id)
			actor.editor.equipment_dye_request = _request_person_dye.bind(actor.person_id)
			actor.editor.body_selection_request = func(_requested: int) -> int: return actor.visual_state.body_index
		if actor.hp <= 0.0 and not actor.loot_settled:
			_person_died(actor.person_id)
	for team: TerrainArmy in lab.combat_armies:
		initialize_team_items(team)
	if _crowd_active():
		for crowd_owner: RefCounted in lab.crowd_site.person_owners(): initialize_team_items(crowd_owner)
	if not lab.actor_present(lab.npc):
		release_worker()
	else:
		if not data.site.has("worker_enabled"):
			data.site["worker_enabled"] = false
		data.site.worker.cell = data.index(lab.npc.terrain_cell)
	view.display(data)
	Runtime.rebuild_water(data)
	_navigation_revision = data.navigation_revision
	selected = data.spawn_cell
	source_key = ""
	feature_key = ""
	build_cells.clear()
	building_resize = false
	_sync_building_controls(true)
	# The install-time refresh ran before any Site was bound; apply the S02 gate
	# now instead of waiting for the construction window to become visible.
	_refresh_irrigation_controls()
	_zone_signature = ""
	_summary_revision = -1
	_work_elapsed = 1.0
	_save_elapsed = 0.0
	if not lab.restore_only: get_tree().paused = bool(data.site.paused)
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

func _compact_label(parent: Node, value: String, size: int = 16) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _number_input(parent: Node, node_name: String, minimum: float, maximum: float, value: float) -> SpinBox:
	var input := SpinBox.new()
	input.name = node_name
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1
	input.value = value
	input.custom_minimum_size.x = 120
	parent.add_child(input)
	return input

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "SiteUI"
	ui.visible = not lab.restore_only
	lab.add_child(ui)
	if not lab.restore_only: get_tree().root.gui_embed_subwindows = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1d2c2b")
	style.border_color = Color("526b5d")
	style.set_border_width_all(1)
	top_banner = PanelContainer.new()
	top_banner.name = "TopBanner"
	top_banner.add_theme_stylebox_override("panel", style)
	ui.add_child(top_banner)
	var banner_margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		banner_margin.add_theme_constant_override("margin_" + side, 10)
	top_banner.add_child(banner_margin)
	var banner_row := HBoxContainer.new()
	banner_row.add_theme_constant_override("separation", 10)
	banner_margin.add_child(banner_row)
	clock_label = _compact_label(banner_row, "", 16)
	clock_label.name = "ClockStatus"
	clock_label.custom_minimum_size.x = 190
	banner_row.add_child(VSeparator.new())
	_button(banner_row, "−", "SlowerSite", func() -> void:
		lab.change_simulation_speed(-1))
	speed_label = _compact_label(banner_row, "1×", 16)
	speed_label.name = "SimulationSpeed"
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.custom_minimum_size.x = 42
	_button(banner_row, "+", "FasterSite", func() -> void:
		lab.change_simulation_speed(1))
	pause_button = _button(banner_row, "暫停", "PauseSite", toggle_pause)
	banner_row.add_child(VSeparator.new())
	player_status_label = _compact_label(banner_row, "", 15)
	player_status_label.name = "PlayerStatus"
	player_status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	player_status_label.clip_text = true
	player_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_panel = PanelContainer.new()
	status_panel.name = "StatusPanel"
	status_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status_panel.add_theme_stylebox_override("panel", style)
	ui.add_child(status_panel)
	var status_margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		status_margin.add_theme_constant_override("margin_" + side, 14)
	status_panel.add_child(status_margin)
	var status_column := VBoxContainer.new()
	status_column.add_theme_constant_override("separation", 5)
	status_margin.add_child(status_column)
	_label(status_column, "現在狀態", 18)
	tool_status_label = _label(status_column, "工具：查看", 15)
	message = _label(status_column, "可手動採集，或框選工作區後指派既有隊員作業。", 16)
	message.modulate = Color("f0d7a0")
	message.max_lines_visible = 3
	message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_column.add_child(HSeparator.new())
	_label(status_column, "所選格資訊", 17)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.name = "SelectedCellScroll"
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.custom_minimum_size.y = 140
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status_column.add_child(detail_scroll)
	details = _label(detail_scroll, "")
	_button(banner_row, "功能", "OpenSiteFunctions", func() -> void: open_window("launcher"))
	fps_label = _compact_label(banner_row, "FPS --", 18)
	fps_label.name = "FramesPerSecond"
	fps_label.custom_minimum_size.x = 88
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var titles := {"map": "地圖與土地", "work": "採集與工作區", "construction": "建設與製作", "equipment": "倉儲與配裝", "people": "人物與俘虜", "family": "家族與接續", "team_info": "隊伍資訊", "team": "隊伍與軍令", "supply": "後勤與訓練", "transport": "車輛與運輸", "system": "存讀與介面"}
	var launcher := _create_tool_window(ui, "launcher", "功能", Vector2i(260, 460), style)
	launcher_window = launcher.window
	panel = launcher.panel
	panel.name = "SitePanel"
	for id: String in titles:
		var built := _create_tool_window(ui, id, str(titles[id]), Vector2i(640, 520) if id == "team_info" else Vector2i(480, 650), style)
		formal_windows[id] = built.window
		_formal_columns[id] = built.column
		_button(launcher.column, str(titles[id]), "OpenSite_" + id, func() -> void: open_window(id))
	_button(launcher.column, "台灣地圖", "OpenRegionMap", _open_region_map)
	region_travel_button = _button(launcher.column, "整隊出發", "DepartRegionTravel", func() -> void: show_result(RegionTravelSite.request_departure(self)))
	_build_crowd_split_entry(launcher.column)
	_resume_region_party_map_button = _button(launcher.column, "原旅隊繼續地圖旅行", "ResumeOriginalPartyMap", _resume_region_party_map)
	_button(launcher.column, "回主選單", "ReturnMainMenu", func() -> void: _request_exit(RegionEntry.MAIN_MENU))
	var column: VBoxContainer = _formal_columns.map
	_button(column, "地點／區域／世界的已保存建設", "OpenRegionBuildingSummary", _open_region_building_summary)
	var row: HBoxContainer
	var views := _options(column, View.VIEW_NAMES, "LandView")
	views.item_selected.connect(func(index: int) -> void:
		view.view_mode = index
		view.refresh()
		update_ui())
	legend = _label(column, "", 15)
	var names: Array = ["全部天然資源"]
	names.append_array(Env.NAMES)
	kinds = _options(column, names, "ResourceKind")
	kinds.item_selected.connect(func(index: int) -> void:
		view.resource_filter = index - 1
		view.refresh()
		select_cell(selected))
	_button(column, "營地近景", "FocusCamp", focus_camp)
	_button(column, "全圖", "FitSite", lab.fit_map)
	column = _formal_columns.work
	modes = _options(column, MODES, "WorkMode")
	modes.item_selected.connect(func(_index: int) -> void:
		lab.test_placement_enabled = false
		build_cells.clear()
		building_resize = false
		view.set_building_preview({})
		view.selection = Rect2i()
		view.queue_redraw()
		update_ui())
	_label(column, "目前資源篩選由地圖與土地共用。點選來源或拖曳工作區；WASD 移動、滾輪縮放、右鍵拖圖。", 15)
	_button(column, "資源篩選…", "WorkResourceFilter", func() -> void: open_window("map"))
	_button(column, "手動作業（需走到來源旁）", "ManualHarvest", manual_work)
	manual_capture_button = _button(column, "活捉馬／羊（需走到來源旁）", "ManualCapture", func() -> void: manual_work("capture"))
	manual_capture_button.tooltip_text = "每批活捉一隻，需工具及攜帶空間。帶到同種類牧場入口可入欄，也可向營地交貨供建場使用。"
	assign_worker_button = _button(column, "派所選原隊員工作（須現任指揮權）", "AssignSelectedWorker", func() -> void:
		var check := _selected_worker_assignment()
		if not check.ok:
			show_result(check)
			return
		var ids: Array[int] = [int(check.person.person_id)]
		show_result(work_team.assign(check.person.owner, ids, lab.controlled_person_id())))
	_button(column, "停止所選原隊員工作（貨物保留）", "CancelSelectedWorker", func() -> void:
		var person := person_actions._person(lab.selected_army_target)
		if not person.is_empty() and int(person.unit) >= 0 and _can_command_person(person):
			show_result(work_team.cancel(int(person.person_id)))
		else:
			show_result(Runtime.fail("NO_AUTHORITY")))
	if lab.npc != null:
		worker_label = _label(column, "")
		row = HBoxContainer.new()
		column.add_child(row)
		_button(row, "工人開始", "EnableWorker", enable_worker)
		_button(row, "工人停止", "StopWorker", release_worker)
	_label(column, "原來源生態管理", 18)
	ecology_status = _label(column, "選取原來源，或框選範圍批次管理。", 15)
	ecology_status.name = "EcologyStatus"
	ecology_modes = _options(column, ["永續採取", "休養保護", "一般採取"], "EcologyMode")
	ecology_apply_button = _button(column, "套用至所選原來源（須生態管理權）", "ApplyEcologyMode", _apply_ecology_mode)
	manual_restore_button = _button(column, "本人復育所選原生植被（60 遊戲分）", "ManualRestore", func() -> void: manual_work("restore"))
	_button(column, "框選復育原生植被區", "ChooseRestorationArea", func() -> void:
		modes.select(7)
		modes.item_selected.emit(7)
		formal_windows.work.hide())
	_label(column, "工作區（由上而下優先）", 18)
	zones = VBoxContainer.new()
	column.add_child(zones)
	column = _formal_columns.construction
	buildings = _options(column, [], "BuildingKind")
	for kind: String in Runtime.FEATURES:
		if kind == "survey_stakes": continue # Requires the original F09 plan and operator caller.
		var choice := {"kind": kind, "camp_type": "standard" if kind == "barracks" else ""}
		buildings.add_item(Runtime.barracks_type_name(choice) if kind == "barracks" else str(Runtime.FEATURES[kind].name))
		buildings.set_item_metadata(buildings.item_count - 1, choice)
	buildings.add_item(Runtime.barracks_type_name({"kind": "barracks", "camp_type": "chinese"}))
	buildings.set_item_metadata(buildings.item_count - 1, {"kind": "barracks", "camp_type": "chinese"})
	buildings.item_selected.connect(func(_index: int) -> void: _building_kind_changed())
	_build_building_controls(column)
	_button(column, "選址／框選建設區", "ChooseConstructionArea", func() -> void:
		modes.select(5)
		modes.item_selected.emit(5)
		formal_windows.construction.hide())
	_button(column, "安排施工（按預覽扣材料）", "BuildFeature", build_selected)
	_button(column, "聚落頁（等級／人口／升級）", "SettlementPage", _open_settlement)
	row = HBoxContainer.new()
	column.add_child(row)
	_button(row, "派工運作", "OperateFeature", func() -> void:
		enable_worker()
		show_result(Runtime.operate_feature(lab.terrain, feature_key)))
	_button(row, "拆除／取消", "CancelFeature", func() -> void:
		show_result(Runtime.cancel_feature(lab.terrain, feature_key, reserves_cell, int(_building_options().get("owner_faction", -1)))))
	stock_pasture_button = _button(column, "把攜帶馬／羊送入所選牧場", "StockPasture", stock_controlled_livestock)
	stock_pasture_button.tooltip_text = "走到已完成的牧場入口旁，將攜帶的同種牲畜送入剩餘草地承載空位。"
	_build_building_actions(column)
	_build_ladder_actions(column)
	_siege_construction_form = {"trial": false}
	_build_siege_construction_controls(column, _siege_construction_form)
	_install_settlement_engineering_controls(column)
	_install_irrigation_controls(column)
	if lab.exchange_enabled:
		_button(column, "營地旁：製作弓弩／彈藥", "RangedCrafting", _open_ranged_crafting)
	column = _formal_columns.equipment
	stock_label = _label(column, "")
	_button(column, "本人向營地交貨", "DepositCargo", deposit_controlled_cargo)
	_button(column, "玩家本人實物配裝／正式領裝", "EquipmentInventory", _open_equipment_inventory)
	_button(column, "指定搜刮執行者正式領裝", "SelectedEquipmentInventory", func() -> void: _open_equipment_inventory(person_executor_id))
	if lab.exchange_enabled:
		_button(column, "營地領取實物／彈藥", "TakeDepotItems", func() -> void: _open_person_inventory(true))
	_button(column, "軍事首長：設定未來領裝標準", "EquipmentStandards", _open_equipment_standards)
	_button(column, "國家制度／具名公務", "NationOperations", _open_nation_operations)
	column = _formal_columns.people
	_button(column, "查看所選格人物／遺留物", "InspectLoot", _open_person_inventory)
	_button(column, "攻擊所選目標", "AttackSelectedPerson", lab.attack_selected_soldier)
	_button(column, "救助所選友方", "RescueSelectedPerson", lab.rescue_selected_soldier)
	_button(column, "被俘本人：嘗試逃脫", "BeginCaptiveEscape", func() -> void: show_result(person_actions.begin_escape(lab.controlled_person_id())))
	_button(column, "俘虜歸降／接收同意", "CaptiveAdoption", _open_captive_adoption)
	_button(column, "指定所選友方人物回收（須自行到相鄰格）", "ChooseRecoveryWorker", _choose_recovery_executor)
	_button(column, "改由玩家搜刮", "ChoosePlayerLooter", func() -> void:
		person_executor_id = lab.controlled_person_id()
		show_result(Runtime.ok("由原玩家執行搜刮")))
	_button(column, "取消人物作業", "CancelPersonAction", func() -> void: show_result(cancel_ground_crossing(person_executor_id)))
	_button(column, "看守押送原俘虜到所選格", "BeginCaptiveEscort", func() -> void: show_result(captive_escort.begin(lab.controlled_person_id(), person_executor_id, selected)))
	_button(column, "取消後續押送（不釋放俘虜）", "CancelCaptiveEscort", func() -> void: show_result(captive_escort.cancel(person_executor_id)))
	column = _formal_columns.family
	_label(column, "檢視已登錄原家人；未知資料不推定死亡。只有真正死亡後才可接續。", 15)
	_button(column, "家族名單／死亡接續", "FamilyContinuity", _open_family)
	_tech_window.install(self, column)
	column = _formal_columns.team_info
	_team_info_overview = _label(column, "尚未部署隊伍。", 16)
	_team_info_overview.custom_minimum_size.x = 0
	_team_info_list = VBoxContainer.new()
	_team_info_list.name = "TeamCards"
	_team_info_list.add_theme_constant_override("separation", 16)
	column.add_child(_team_info_list)
	_team_info_report_button = _button(column, "展開完整文字紀錄", "ToggleTeamInformationText", func() -> void:
		team_info_label.visible = not team_info_label.visible
		_team_info_report_button.text = "收起完整文字紀錄" if team_info_label.visible else "展開完整文字紀錄")
	team_info_label = _label(column, "尚未部署隊伍。", 15)
	team_info_label.name = "TeamInformation"
	team_info_label.custom_minimum_size.x = 0
	team_info_label.hide()
	column = _formal_columns.team
	_label(column, "玩家與隊伍", 20)
	_button(column, "查看隊伍資訊", "OpenTeamInformation", func() -> void: open_window("team_info"))
	player_army_label = _label(column, "尚未入隊；青色圓圈為建議站位，不會接管角色。", 15)
	_button(column, "查看／調整接任順位", "PlayerOfficerPriority", _open_officer_priority)
	_button(column, "職位頁：本隊／國家／聚落職位與職責", "OfficesPage", _open_offices)
	_button(column, "拆出選取隊員（需本隊指揮權）", "SplitSelectedSoldier", func() -> void: show_result(lab.split_selected_soldier()))
	_button(column, "本隊名冊：多人派工／補員／拆併", "ManagePlayerRoster", _open_roster)
	_button(column, "本隊正式領裝／換裝", "TeamEquipment", _open_team_equipment)
	_button(column, "正式退出隊伍", "LeavePlayerArmy", func() -> void: show_result(lab.leave_player_army()))

	formal_team_choice = _options(column, ["選取軍團轉進目標"], "FormalCommandTeam")
	formal_team_choice.set_item_metadata(0, -1)
	formal_team_choice.item_selected.connect(func(_index: int) -> void: _sync_formal_captain_selection())
	_build_formation_controls(column, "formal")
	for entry: Array in [["玩家下令：守位", TerrainArmy.CombatOrder.HOLD], ["玩家下令：接敵", TerrainArmy.CombatOrder.ATTACK], ["玩家下令：前進至所選格", TerrainArmy.CombatOrder.MOVE], ["玩家下令：撤至地圖邊緣（士氣崩潰後）", TerrainArmy.CombatOrder.RETREAT], ["玩家下令：追擊所選敵兵", TerrainArmy.CombatOrder.PURSUE], ["玩家下令：衝鋒（騎兵隊，所選敵隊或所選格）", TerrainArmy.CombatOrder.CHARGE], ["玩家下令：重整（騎兵隊）", TerrainArmy.CombatOrder.RALLY]]:
		var order_id := int(entry[1])
		var order_button := _button(column, str(entry[0]), "PlayerArmyOrder%d" % order_id, func() -> void:
			var identity := -1
			if order_id == TerrainArmy.CombatOrder.PURSUE:
				identity = _selected_enemy_identity(lab.player_army())
			_player_army_order(order_id, identity))
		if order_id == TerrainArmy.CombatOrder.RETREAT:
			player_retreat_button = order_button
		elif order_id == TerrainArmy.CombatOrder.CHARGE:
			player_charge_button = order_button
		elif order_id == TerrainArmy.CombatOrder.RALLY:
			player_rally_button = order_button
	_button(column, "玩家下令：拖曳指定終點面向", "PlayerArmyFacingMove", func() -> void: _begin_facing_move("player"))
	_button(column, "軍團長要求：所選隊伍轉進至所選格", "CorpsReposition", func() -> void: _player_corps_reposition())
	column = _formal_columns.supply
	_label(column, "隊伍口糧／訓練（主動啟用）", 18)
	supply_team_choice = _options(column, ["玩家目前隊伍"], "SupplyTeam")
	supply_quantity = _number_input(column, "SupplyRations", 1, 30, 1)
	team_supply_label = _label(column, "先點選相鄰隊員，再從玩家行囊交糧；不會自取營地物資。", 15)
	_button(column, "向選取隊員交付口糧", "DeliverTeamFood", func() -> void:
		# P1e: food delivery under crowd runs in peace only; begin_team_food refuses in combat (CROWD_ACTIVE).
		var team: Variant = _chosen_supply_team()
		var representative := -1
		if team != null:
			representative = _representative_at(team, selected)
		show_result(begin_team_food(team, int(supply_quantity.value), representative)))
	_button(column, "取消口糧交付", "CancelTeamFood", func() -> void: show_result(cancel_team_food()))
	_button(column, "後勤調度：營地／隊伍／地面口糧", "OpenLogistics", _open_logistics)
	_button(column, "玩家下令：平時訓練", "TrainPlayerTeam", func() -> void:
		show_result(order_controlled_training(true)))
	_button(column, "玩家下令：停止訓練", "StopPlayerTeamTraining", func() -> void:
		show_result(order_controlled_training(false)))
	_build_vehicle_controls(_formal_columns.transport)
	_build_tent_controls(_formal_columns.transport)
	column = _formal_columns.system
	_audio_build_controls(column)
	_button(column, "保存", "SaveSite", save_current)
	_button(column, "載入", "LoadSite", load_current)
	_label(column, "保存地圖、玩家與各隊傷亡、指揮、動作／移動。交戰中延後保存，離線期間不增加產量。", 15)
	saved_sites = _options(column, ["已保存地圖"], "SavedSites")
	_button(column, "開啟所選保存地圖", "OpenSavedSite", func() -> void:
		if saved_sites.selected >= 0 and saved_sites.get_item_metadata(saved_sites.selected) != null:
			_load_path(str(saved_sites.get_item_metadata(saved_sites.selected))))
	_refresh_saved_sites()
	_button(column, "收起一般工具窗", "HideSiteToolWindows", hide_tool_windows)
	_button(column, "重設視窗位置", "ResetSiteWindowPositions", reset_window_positions)
	_use_formation_controls("formal")
	reset_window_positions()
	launcher_window.show()

func _create_tool_window(ui: CanvasLayer, id: String, title: String, initial_size: Vector2i, style: StyleBoxFlat) -> Dictionary:
	var window := Window.new()
	window.name = "SiteFunctions" if id == "launcher" else "Site_" + id
	window.title = title
	window.force_native = false
	window.exclusive = false
	window.transient = false
	window.size = initial_size
	window.min_size = Vector2i(250, 220)
	window.process_mode = Node.PROCESS_MODE_ALWAYS
	window.close_requested.connect(window.hide)
	window.focus_entered.connect(func() -> void:
		lab._clear_movement_input()
		lab._dragging = false
		drag_start = Vector2i(-1, -1)
		_cancel_facing_move()
		if id == "team": _use_formation_controls("formal"))
	window.window_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			lab._clear_movement_input()
			lab._dragging = false
			drag_start = Vector2i(-1, -1)
			_cancel_facing_move()
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and window.get_exclusive_child() == null:
			window.hide()
			window.set_input_as_handled())
	ui.add_child(window)
	var surface := PanelContainer.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.add_theme_stylebox_override("panel", style)
	window.add_child(surface)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	surface.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	window.hide()
	return {"window": window, "panel": surface, "column": column}

func open_window(id: String) -> void:
	var window: Window = launcher_window if id == "launcher" else formal_windows.get(id)
	if not is_instance_valid(window): return
	if id == "team":
		_refresh_formal_team_choices()
		_sync_formal_captain_selection()
		_use_formation_controls("formal")
	if id == "transport": _refresh_vehicle_controls()
	_clamp_tool_window(window)
	window.show()
	window.grab_focus()
	update_ui(false)

func hide_tool_windows() -> void:
	for window: Window in formal_windows.values(): window.hide()
	launcher_window.hide()
	_cancel_facing_move()

func reset_window_positions() -> void:
	var screen := Vector2i(lab.get_viewport_rect().size)
	launcher_window.position = Vector2i(maxi(8, screen.x - launcher_window.size.x - 18), 112)
	_clamp_tool_window(launcher_window)
	var index := 0
	for window: Window in formal_windows.values():
		window.position = Vector2i(40 + (index % 5) * 42, 116 + (index % 4) * 32)
		_clamp_tool_window(window)
		index += 1
	if is_instance_valid(lab.site_test_window): lab.site_test_window.reset_position()

func _clamp_tool_window(window: Window) -> void:
	var screen := Vector2i(lab.get_viewport_rect().size)
	window.size = Vector2i(mini(window.size.x, maxi(250, screen.x - 16)), mini(window.size.y, maxi(220, screen.y - 120)))
	window.position = Vector2i(clampi(window.position.x, 0, maxi(0, screen.x - window.size.x)), clampi(window.position.y, 104, maxi(104, screen.y - window.size.y)))

func camera_usable_rect() -> Rect2:
	var screen := lab.get_viewport_rect().size
	var top := top_banner.position.y + top_banner.size.y + 12.0
	var bottom := status_panel.size.y * status_panel.scale.y + 28.0 if status_panel.visible else 16.0
	return Rect2(Vector2(16, top), Vector2(maxf(1, screen.x - 32.0), maxf(1, screen.y - top - bottom)))

func _refresh_formal_team_choices() -> void:
	if formal_team_choice == null: return
	var rows: Array = []
	if _crowd_active():
		for row: Dictionary in lab.crowd_site.command_teams(): rows.append([int(row.team_id), "隊伍 #%d" % int(row.team_id)])
	else:
		for team: TerrainArmy in lab.combat_armies:
			if team.has_army(): rows.append([team.team_id, "隊伍 #%d · 陣營 %s" % [team.team_id, _faction_label(team.faction_id)]])
	var signature := str(rows)
	if signature == _formal_team_signature: return
	_formal_team_signature = signature
	var previous := int(formal_team_choice.get_item_metadata(formal_team_choice.selected)) if formal_team_choice.selected >= 0 else -1
	formal_team_choice.clear()
	formal_team_choice.add_item("選取軍團轉進目標")
	formal_team_choice.set_item_metadata(0, -1)
	for row: Array in rows:
		formal_team_choice.add_item(str(row[1]))
		var index := formal_team_choice.item_count - 1
		formal_team_choice.set_item_metadata(index, int(row[0]))
		if int(row[0]) == previous: formal_team_choice.select(index)
	_sync_formal_captain_selection()

func _build_formation_controls(column: Node, context_id: String) -> void:
	var controls := {}
	if context_id == "test":
		controls["source"] = _options(column, ["所選測試隊", "我方測試指揮"], "FormationCommandSource")
		controls.source.item_selected.connect(func(_index: int) -> void:
			_use_formation_controls(context_id)
			_formation_context_changed())
	controls["preset"] = _options(column, ["自適應", "方陣", "圓陣", "錐行陣", "雁行陣", "鉤行陣", "疏陣"], "TrialFormationPreset" if context_id == "test" else "FormationPreset")
	for index in range(controls.preset.item_count):
		controls.preset.set_item_metadata(index, ["auto", "square", "circle", "wedge", "goose", "hook", "loose"][index])
	controls.preset.item_selected.connect(func(index: int) -> void:
		_use_formation_controls(context_id)
		_select_formation_candidate(index))
	controls["status"] = _label(column, "先選擇可下令的原隊伍。", 15)
	controls["apply"] = _button(column, "套用陣型", "ApplyTrialFormation" if context_id == "test" else "ApplyFormation", func() -> void:
		_use_formation_controls(context_id)
		_apply_formation_change())
	_formation_views[context_id] = controls

func _use_formation_controls(context_id: String) -> void:
	if not _formation_views.has(context_id): return
	if _active_formation_view != context_id:
		_cancel_facing_move()
		_clear_formation_candidate()
	_active_formation_view = context_id
	var controls: Dictionary = _formation_views[context_id]
	formation_command_source = controls.get("source")
	formation_preset_choice = controls.preset
	formation_status_label = controls.status
	formation_apply_button = controls.apply

func install_test_window(host: Window, pages: Dictionary) -> void:
	combat_window = host
	_test_pages = pages.duplicate()
	host.tree_exiting.connect(func() -> void:
		_cancel_facing_move()
		_use_formation_controls("formal")
		_formation_views.erase("test")
		_vehicle_forms.erase("test")
		_trial_fire_ui.clear()
		_test_pages.clear()
		combat_window = null
		trial_command_team = null
		_trial_team_choices_initialized = false)
	var column: VBoxContainer = pages.deployment
	_label(column, "隊伍戰鬥、工作與後勤測試", 23)
	_label(column, "每隊選擇近戰／弓／弩單一兵種（基礎武力 %.0f）。普通兵共用兵種基礎值、各自使用實裝；隊長與幹部才保有個別指揮能力。" % TerrainArmy.TROOP_COMBAT_ABILITY, 15)
	_label(column, "可調整人數、訓練、隊長指揮能力與初始命令。隊伍 ID 仍由 Site 自動分配；現役隊伍不會被原地改寫。", 15)
	trial_third_enabled = CheckBox.new()
	trial_third_enabled.name = "EnableThirdTeam"
	trial_third_enabled.text = "增加第三隊（一起部署時啟用）"
	column.add_child(trial_third_enabled)
	_label(column, "第三隊可加入我方／敵方勢力，或選第三勢力；同勢力友軍、不同勢力互相敵對。", 15)
	var config := GridContainer.new()
	config.columns = 4
	config.add_theme_constant_override("h_separation", 10)
	config.add_theme_constant_override("v_separation", 7)
	column.add_child(config)
	_compact_label(config, "設定")
	_compact_label(config, "我方")
	_compact_label(config, "敵方")
	_compact_label(config, "第三隊")
	_compact_label(config, "勢力")
	_compact_label(config, "我方勢力")
	_compact_label(config, "敵方勢力")
	trial_third_faction = _options(config, ["我方勢力", "敵方勢力", "第三勢力"], "ThirdFaction")
	trial_third_faction.select(2)
	_compact_label(config, "隊伍用途")
	for prefix: String in ["friendly", "enemy", "third"]:
		trial_roles[prefix] = _options(config, ["戰鬥隊", "工作隊", "後勤隊"], prefix.capitalize() + "TeamRole")
	_compact_label(config, "戰鬥兵種")
	for prefix: String in ["friendly", "enemy", "third"]:
		trial_troop_types[prefix] = _options(config, ["近戰步兵", "弓兵", "弩兵"], prefix.capitalize() + "TroopType")
	_compact_label(config, "總名額（人＋車）")
	trial_friendly_count = _number_input(config, "FriendlyCount", 1, 100, 100)
	trial_enemy_count = _number_input(config, "EnemyCount", 1, 100, 100)
	trial_third_count = _number_input(config, "ThirdCount", 1, 100, 100)
	_compact_label(config, "物資車（後勤限定）")
	for prefix: String in ["friendly", "enemy", "third"]:
		trial_carts[prefix] = _number_input(config, prefix.capitalize() + "CartCount", 0, 99, 0)
	_compact_label(config, "馬車（後勤限定）")
	for prefix: String in ["friendly", "enemy", "third"]:
		trial_wagons[prefix] = _number_input(config, prefix.capitalize() + "WagonCount", 0, 99, 0)
	_compact_label(config, "女性比例（0–100%）")
	trial_friendly_female_percent = _number_input(config, "FriendlyFemalePercent", 0, 100, 50)
	trial_enemy_female_percent = _number_input(config, "EnemyFemalePercent", 0, 100, 50)
	trial_third_female_percent = _number_input(config, "ThirdFemalePercent", 0, 100, 50)
	_compact_label(config, "男／女人數（含隊長）")
	trial_friendly_gender_label = _compact_label(config, "")
	trial_enemy_gender_label = _compact_label(config, "")
	trial_third_gender_label = _compact_label(config, "")
	for input: SpinBox in [trial_friendly_count, trial_enemy_count, trial_third_count, trial_friendly_female_percent, trial_enemy_female_percent, trial_third_female_percent]:
		input.value_changed.connect(func(_value: float) -> void: _update_trial_gender_counts())
	for prefix: String in trial_roles:
		trial_roles[prefix].item_selected.connect(func(_index: int) -> void: _trial_role_changed(prefix))
		trial_carts[prefix].value_changed.connect(func(_value: float) -> void: _update_trial_gender_counts())
		trial_wagons[prefix].value_changed.connect(func(_value: float) -> void: _update_trial_gender_counts())
	_compact_label(config, "訓練（0–1000）")
	trial_friendly_training = _number_input(config, "FriendlyTraining", 0, 1000, 0)
	trial_enemy_training = _number_input(config, "EnemyTraining", 0, 1000, 0)
	trial_third_training = _number_input(config, "ThirdTraining", 0, 1000, 0)
	_compact_label(config, "隊長戰術（0–100）")
	trial_friendly_tactics = _number_input(config, "FriendlyCaptainTactics", 0, 100, 50)
	trial_enemy_tactics = _number_input(config, "EnemyCaptainTactics", 0, 100, 50)
	trial_third_tactics = _number_input(config, "ThirdCaptainTactics", 0, 100, 50)
	_compact_label(config, "隊長領導（0–100）")
	trial_friendly_leadership = _number_input(config, "FriendlyCaptainLeadership", 0, 100, 50)
	trial_enemy_leadership = _number_input(config, "EnemyCaptainLeadership", 0, 100, 50)
	trial_third_leadership = _number_input(config, "ThirdCaptainLeadership", 0, 100, 50)
	_compact_label(config, "隊長教練（0–100）")
	trial_friendly_coach = _number_input(config, "FriendlyCaptainCoach", 0, 100, 50)
	trial_enemy_coach = _number_input(config, "EnemyCaptainCoach", 0, 100, 50)
	trial_third_coach = _number_input(config, "ThirdCaptainCoach", 0, 100, 50)
	_compact_label(config, "初始命令")
	trial_friendly_order = _options(config, ["守位", "接敵"], "FriendlyInitialOrder")
	trial_enemy_order = _options(config, ["守位", "接敵"], "EnemyInitialOrder")
	trial_third_order = _options(config, ["守位", "接敵"], "ThirdInitialOrder")
	trial_friendly_order.select(1)
	trial_enemy_order.select(1)
	trial_third_order.select(1)
	_compact_label(config, "自主戰術 AI")
	for prefix: String in ["friendly", "enemy", "third"]:
		var ai_toggle := CheckBox.new()
		ai_toggle.name = prefix.capitalize() + "TacticalAI"
		ai_toggle.text = "自主進攻／撤退"
		ai_toggle.button_pressed = true
		config.add_child(ai_toggle)
		trial_ai_enabled[prefix] = ai_toggle
	_compact_label(config, "進場方位")
	trial_friendly_entry = _options(config, ["東", "南", "西", "北"], "FriendlyEntryDirection")
	trial_enemy_entry = _options(config, ["東", "南", "西", "北"], "EnemyEntryDirection")
	trial_third_entry = _options(config, ["東", "南", "西", "北"], "ThirdEntryDirection")
	trial_friendly_entry.select(2) # 西
	trial_enemy_entry.select(0)    # 東
	trial_third_entry.select(3)    # 北
	trial_friendly_entry.item_selected.connect(func(_index: int) -> void: _update_combat_window())
	trial_enemy_entry.item_selected.connect(func(_index: int) -> void: _update_combat_window())
	trial_third_entry.item_selected.connect(func(_index: int) -> void: _update_combat_window())
	trial_entry_direction = trial_enemy_entry
	for prefix: String in trial_roles:
		_trial_role_changed(prefix)
	column.add_child(HSeparator.new())
	_label(column, "進場點與部署方位", 18)
	_label(column, "我方、敵方與第三方隊伍可各自獨立選擇進場方位（東、南、西、北），系統自動從該方位的合法空位部署隊伍。", 15)
	_label(column, "總名額包含每一名人員與每一輛車，至少保留一人；男女比例只計真正人員。車多於可用操作者時停泊等待，不額外生成駕駛。工作隊留下隊長，其餘人沿原工作區派工；後勤隊不自動取物。", 15)
	_label(column, "弓／弩測試隊部署時每人持有對應武器及 20 發彈藥，無盾；只在本次建立時配置。射完須沿原營地製作、領取補給。", 15)
	trial_friendly_spawn_label = _label(column, "我方：從【西】方空位自動部署", 15)
	trial_enemy_spawn_label = _label(column, "敵方：從【東】方空位自動部署", 15)
	trial_third_spawn_label = _label(column, "第三隊：從【北】方空位自動部署", 15)
	var deploy_row := HBoxContainer.new()
	column.add_child(deploy_row)
	_button(deploy_row, "依設定部署", "StartMeleeTrial", _deploy_melee_trial)
	_button(deploy_row, "清除測試隊伍", "ClearMeleeTrial", _clear_melee_trial)
	_button(column, "只追加第三隊（保留已部署兩隊）", "AddThirdMeleeTrial", _add_third_melee_trial)
	_label(column, "多隊部署（每隊 100 人；友／敵／第三方隊數合計不得超過 Site 容量）", 18)
	var batch_row := HBoxContainer.new()
	column.add_child(batch_row)
	_compact_label(batch_row, "我方")
	trial_friendly_teams = _number_input(batch_row, "FriendlyArmyCount", 0, Store.MAX_ARMIES, 25)
	_compact_label(batch_row, "敵方")
	trial_enemy_teams = _number_input(batch_row, "EnemyArmyCount", 0, Store.MAX_ARMIES, 25)
	_compact_label(batch_row, "第三方")
	trial_third_teams = _number_input(batch_row, "ThirdArmyCount", 0, Store.MAX_ARMIES, 0)
	trial_batch_status = _label(column, "", 15)
	for input: SpinBox in [trial_friendly_teams, trial_enemy_teams, trial_third_teams]:
		input.value_changed.connect(func(_value: float) -> void: _update_trial_batch_status())
	_update_trial_batch_status()
	_button(column, "空場部署多支百人隊", "DeployTrialArmies", _deploy_trial_armies)
	_button(column, "更新所有隊伍傷亡", "MeleeTrialStatus", _show_melee_trial_status)
	_button(column, "加入我方測試隊伍（自主操作）", "JoinPlayerArmy", func() -> void: show_result(lab.join_player_army()))
	column = pages.command
	_label(column, "開發調度：原 NPC 隊長下令", 18)
	trial_command_team = _options(column, [], "TrialCommandTeam")
	trial_command_team.item_selected.connect(func(_index: int) -> void: _formation_context_changed())
	trial_command_team.item_selected.connect(func(_index: int) -> void: _update_combat_window())
	trial_command_team.item_selected.connect(func(_index: int) -> void: _sync_trial_captain_selection())
	_sync_trial_team_choices()
	trial_ai_status_label = _label(column, "尚未部署所選隊伍。", 15)
	trial_ai_status_label.name = "TrialTeamAIStatus"
	_label(column, "啟用 AI 後由原隊長判斷敵我兵力、疲勞與士氣；成功下達人工軍令後改由手動指揮。初始命令只決定部署時狀態。", 15)
	_button(column, "所選隊伍：啟用自主 AI", "TrialTeamAIEnable", func() -> void: _trial_team_ai(true))
	_button(column, "所選隊伍：停用自主 AI", "TrialTeamAIDisable", func() -> void: _trial_team_ai(false))
	_build_formation_controls(column, "test")
	_button(column, "所選隊伍移動至地圖所選格", "TrialTeamMove", func() -> void: _trial_team_order(TerrainArmy.CombatOrder.MOVE))
	_button(column, "所選隊伍：拖曳指定終點面向", "TrialTeamFacingMove", func() -> void: _begin_facing_move("trial"))
	_button(column, "所選隊伍守位／恢復原派工", "TrialTeamHold", func() -> void: _trial_team_order(TerrainArmy.CombatOrder.HOLD))
	_build_trial_fire_controls(column)
	_button(column, "所選隊伍接敵", "TrialTeamAttack", func() -> void: _trial_team_order(TerrainArmy.CombatOrder.ATTACK))
	trial_retreat_button = _button(column, "所選隊伍撤至地圖邊緣（士氣崩潰後）", "TrialTeamRetreat", func() -> void: _trial_team_order(TerrainArmy.CombatOrder.RETREAT))
	_button(column, "所選隊伍追擊所選敵兵", "TrialTeamPursue", func() -> void: _trial_team_order(TerrainArmy.CombatOrder.PURSUE))
	trial_charge_button = _button(column, "所選騎兵隊衝鋒（所選敵隊或所選格）", "TrialTeamCharge", func() -> void: _trial_team_order(TerrainArmy.CombatOrder.CHARGE))
	trial_rally_button = _button(column, "所選騎兵隊重整", "TrialTeamRally", func() -> void: _trial_team_order(TerrainArmy.CombatOrder.RALLY))
	_label(column, "開發測試指揮（模擬 NPC 隊長下令，非玩家權限）", 15)
	_button(column, "測試任命：本人為所選隊軍團長", "TrialCorpsAppointment", func() -> void: show_result(_appoint_trial_corps()))
	_button(column, "我方守位", "ArmyCombatHold", func() -> void: _test_army_order(TerrainArmy.CombatOrder.HOLD))
	_button(column, "我方接敵／近戰包圍" if lab.exchange_enabled else "我方維持戰線接敵", "ArmyCombatAttack", func() -> void: _test_army_order(TerrainArmy.CombatOrder.ATTACK))
	_button(column, "我方前進至所選格", "ArmyCombatMove", func() -> void: _test_army_order(TerrainArmy.CombatOrder.MOVE, selected))
	_button(column, "我方測試指揮：拖曳指定終點面向", "ArmyCombatFacingMove", func() -> void: _begin_facing_move("test"))
	test_retreat_button = _button(column, "我方撤至地圖邊緣（士氣崩潰後）", "ArmyCombatRetreat", func() -> void: _test_army_order(TerrainArmy.CombatOrder.RETREAT))
	_button(column, "我方追擊所選格敵兵", "ArmyCombatPursue", func() -> void:
		var identity := _selected_enemy_identity(lab.army)
		_test_army_order(TerrainArmy.CombatOrder.PURSUE, Vector2i(-1, -1), identity))
	column = pages.stock
	_button(column, "測試情境：設定國別與裝備實物", "TrialEquipmentSetup", func() -> void: _open_trial_equipment_setup(host))
	_button(column, "測試指揮：所選隊伍整批領裝", "TrialTeamEquipment", func() -> void:
		var team := _selected_trial_team()
		if team == null:
			show_result(Runtime.fail("NO_TARGET", "所選隊伍已不在場"))
		else:
			_open_team_equipment(team, true, host))
	_button(column, "本人配裝／指定領裝", "TrialPersonalEquipment", func() -> void: _open_equipment_inventory(-1, host))
	_build_vehicle_controls(pages.logistics, true)
	_button(pages.logistics, "原後勤交付與訓練", "TrialOpenLogistics", func() -> void: _open_logistics(host))
	_button(pages.relationships, "測試接收隊同意／名冊調度", "TrialRosterConsent", func() -> void: _open_roster(true, host))
	_button(pages.relationships, "明確登錄既有家人", "RegisterFamily", func() -> void: _open_family_registry(host))
	combat_summary_label = _label(pages.diagnostics, "尚未部署測試隊伍。", 15)
	_use_formation_controls("formal")
	host.visibility_changed.connect(func() -> void:
		if host.visible: _refresh_vehicle_controls(_vehicle_forms.test)
		elif _facing_order_source.is_empty() and _active_formation_view == "test": _clear_formation_candidate())

func _selected_enemy_identity(source: Variant) -> int:
	if _crowd_active():
		return _crowd_selected_enemy_identity(source)
	if source == null:
		return -1
	for actor: TerrainTestCharacter in lab.combat_actors:
		if is_instance_valid(actor) and actor != source and not RegionFactionQuery.same_side(actor.faction_id, source.faction_id) and actor.terrain_cell == selected and actor.can_act():
			return actor.person_id
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled or team == source or RegionFactionQuery.same_side(team.faction_id, source.faction_id):
			continue
		for index in range(team.combat_units.size()):
			if team.cells[index] == selected and team.combat_can_act(index):
				return team.combat_identity(index)
	return -1

# G8a: crowd mirror of the grid rule above (exact selected cell, hostile to the source team's faction,
# able to act). Under crowd the player's grid army is null, so the controlled person's native owner
# supplies the faction when no source team is given.
func _crowd_selected_enemy_identity(source: Variant) -> int:
	var crowd: Variant = lab.crowd_site
	var faction_owner: Variant = source if source != null else crowd.person_owner(lab.controlled_person_id())
	if faction_owner == null: return -1
	var faction: int = int(faction_owner.faction_id)
	var own_team: int = int(faction_owner.team_id) if "team_id" in faction_owner else -1
	for actor: TerrainTestCharacter in lab.combat_actors:
		if not is_instance_valid(actor) or crowd.contains_person(actor.person_id): continue
		if not RegionFactionQuery.same_side(actor.faction_id, faction) and actor.terrain_cell == selected and actor.can_act(): return actor.person_id
	for owner_ref: CrowdPersonOwner in crowd.person_owners():
		if not owner_ref.combat_enabled or owner_ref.team_id == own_team or RegionFactionQuery.same_side(owner_ref.faction_id, faction): continue
		for index: int in owner_ref.combat_units.keys():
			var ground: Vector2 = owner_ref.combat_ground(index) / TerrainRenderer.CELL_PIXELS
			if Vector2i(floori(ground.x), floori(ground.y)) == selected and owner_ref.combat_can_act(index):
				return owner_ref.combat_identity(index)
	return -1

func _open_combat_window() -> void:
	if not is_instance_valid(combat_window): return
	_update_combat_window()
	combat_window.show()
	combat_window.grab_focus()

func _set_trial_spawn(friendly: bool) -> void:
	if lab.terrain == null or not lab.terrain.contains(selected):
		show_result(Runtime.fail("NO_TARGET", "請先在地圖選一格"))
		return
	if friendly:
		trial_friendly_spawn = selected
	else:
		trial_enemy_spawn = selected
	_update_combat_window()

func _reset_trial_spawns() -> void:
	trial_friendly_spawn = Vector2i(-1, -1)
	trial_enemy_spawn = Vector2i(-1, -1)
	trial_third_spawn = Vector2i(-1, -1)
	_update_combat_window()

func _set_third_trial_spawn() -> void:
	if lab.terrain == null or not lab.terrain.contains(selected):
		show_result(Runtime.fail("NO_TARGET", "請先在地圖選一格"))
		return
	trial_third_spawn = selected
	_update_combat_window()

func _crowd_command_team(source: String = "trial") -> Dictionary:
	if not _crowd_active(): return {}
	var selected_id := -1
	if source == "trial" and trial_command_team != null and trial_command_team.selected >= 0:
		selected_id = int(trial_command_team.get_item_metadata(trial_command_team.selected))
	elif source == "player":
		var controlled_owner: RefCounted = lab.crowd_site.person_owner(lab.controlled_person_id())
		if controlled_owner != null: selected_id = controlled_owner.team_id
	for team: Dictionary in lab.crowd_site.command_teams():
		if int(team.team_id) == selected_id or source == "test" and int(team.faction) == 0: return team
	return {}

func _crowd_selected_enemy(team: Dictionary) -> int:
	if team.is_empty(): return -1
	for candidate_owner: RefCounted in lab.crowd_site.person_owners():
		if candidate_owner.team_id == int(team.team_id) or RegionFactionQuery.same_side(candidate_owner.faction_id, int(team.faction)): continue
		for index: int in candidate_owner.combat_units:
			var person: Dictionary = candidate_owner.person(index)
			if person.cell == selected and float(person.hp) > 0.0 and not bool(person.captive): return int(person.person_id)
	return -1

func _crowd_order(source: String, order_id: int, goal: Vector2i = Vector2i(-1, -1), target_id: int = -1, facing: Vector2i = Vector2i.ZERO) -> Dictionary:
	var team := _crowd_command_team(source)
	if team.is_empty(): return Runtime.fail("NO_TARGET", "尚未部署可下令的群眾隊伍")
	if order_id == TerrainArmy.CombatOrder.MOVE:
		# A grid candidate armed before crowd activation has no crowd owner; drop it instead of refusing the crowd MOVE as STALE.
		_clear_formation_candidate()
	if target_id < 0 and order_id == TerrainArmy.CombatOrder.PURSUE: target_id = _crowd_selected_enemy(team)
	# CAV-4b: a picked enemy person charges that enemy team (native kind 7); otherwise the selected cell is a point (kind 5).
	if target_id < 0 and order_id == TerrainArmy.CombatOrder.CHARGE: target_id = _crowd_selected_enemy(team)
	return lab.crowd_site.issue_order(int(team.team_id), order_id, selected if goal == Vector2i(-1, -1) else goal, target_id, source, facing)

func _sync_crowd_choices() -> void:
	var selected_id := -1
	if trial_command_team.selected >= 0: selected_id = int(trial_command_team.get_item_metadata(trial_command_team.selected))
	var teams: Array = lab.crowd_site.command_teams()
	var ids: Array = []
	for team: Dictionary in teams: ids.append(int(team.team_id))
	var signature := "crowd:" + str(ids)
	if signature != _trial_team_choice_signature:
		_trial_team_choice_signature = signature
		trial_command_team.clear()
		for team: Dictionary in teams:
			trial_command_team.add_item(lab.crowd_site.team_summary(int(team.team_id)))
			trial_command_team.set_item_metadata(trial_command_team.item_count - 1, int(team.team_id))
		trial_command_team.select(ids.find(selected_id) if ids.has(selected_id) else (0 if not ids.is_empty() else -1))
	for index in range(teams.size()):
		trial_command_team.set_item_text(index, lab.crowd_site.team_summary(int(teams[index].team_id)))

func _selected_trial_team() -> TerrainArmy:
	if trial_command_team == null or trial_command_team.selected < 0:
		return null
	var selected_id := int(trial_command_team.get_item_metadata(trial_command_team.selected))
	for team: TerrainArmy in lab.combat_armies:
		if is_instance_valid(team) and team.team_id == selected_id:
			return team
	return null

func _sync_formal_captain_selection() -> void:
	if _crowd_active() or formal_team_choice == null: return
	var team_id := int(formal_team_choice.get_item_metadata(formal_team_choice.selected)) if formal_team_choice.selected >= 0 else -1
	for team: TerrainArmy in lab.combat_armies:
		if is_instance_valid(team): team.set_captain_presenter_selected(team.team_id == team_id)

func _sync_trial_captain_selection() -> void:
	if _crowd_active(): return
	var selected_team := _selected_trial_team()
	for team: TerrainArmy in lab.combat_armies:
		if is_instance_valid(team): team.set_captain_presenter_selected(team == selected_team)

func _trial_team_choice_text(team: TerrainArmy) -> String:
	var purpose: String = {"combat": "戰鬥", "work": "工作", "logistics": "後勤"}.get(team.role, team.role)
	var status: String = "未部署" if not team.has_army() else COMBAT_ORDER_NAMES[clampi(team.combat_order, 0, COMBAT_ORDER_NAMES.size() - 1)]
	return "隊伍 #%d · 陣營 %s · %s · %d 人 · %s" % [team.team_id, _faction_label(team.faction_id), purpose, team.combat_units.size(), status]

func _sync_trial_team_choices() -> void:
	if trial_command_team == null:
		return
	if _crowd_active():
		_sync_crowd_choices()
		return
	var signature_parts := PackedStringArray()
	for team: TerrainArmy in lab.combat_armies:
		if is_instance_valid(team):
			signature_parts.append("%d:%d:%s:%d:%d" % [team.team_id, team.faction_id, team.role, team.combat_units.size(), int(team.has_army())])
	var signature := "|".join(signature_parts)
	if signature == _trial_team_choice_signature:
		return
	var selected_id := -1
	if trial_command_team.selected >= 0:
		selected_id = int(trial_command_team.get_item_metadata(trial_command_team.selected))
	_trial_team_choice_signature = signature
	trial_command_team.clear()
	var selected_index := -1
	for team: TerrainArmy in lab.combat_armies:
		if not is_instance_valid(team):
			continue
		trial_command_team.add_item(_trial_team_choice_text(team))
		var index := trial_command_team.item_count - 1
		trial_command_team.set_item_metadata(index, team.team_id)
		if team.team_id == selected_id:
			selected_index = index
	if not _trial_team_choices_initialized and trial_command_team.item_count > 0:
		selected_index = 0
	_trial_team_choices_initialized = true
	trial_command_team.select(selected_index)
	_sync_trial_captain_selection()

func _refresh_trial_team_choice_statuses() -> void:
	if _crowd_active():
		_sync_trial_team_choices()
		return
	_sync_trial_team_choices()
	var index := 0
	for team: TerrainArmy in lab.combat_armies:
		if not is_instance_valid(team):
			continue
		var title := _trial_team_choice_text(team)
		if trial_command_team.get_item_text(index) != title:
			trial_command_team.set_item_text(index, title)
		index += 1

func _update_trial_batch_status() -> void:
	if trial_batch_status == null:
		return
	var count := int(trial_friendly_teams.value) + int(trial_enemy_teams.value) + int(trial_third_teams.value)
	var people := count * 100
	var eligible := count > 0 and count <= Store.MAX_ARMIES and people <= Store.MAX_ARMY_ROWS
	trial_batch_status.text = "%d 隊 · %d 人（全陣營合計）；%s" % [count, people, "可提交部署預檢" if eligible else "超出 Site 額度或未選隊伍"]

func _deploy_trial_armies() -> void:
	var counts := {"friendly": int(trial_friendly_teams.value), "enemy": int(trial_enemy_teams.value), "third": int(trial_third_teams.value)}
	var total := int(counts.friendly) + int(counts.enemy) + int(counts.third)
	if total <= 0 or total > Store.MAX_ARMIES or total * 100 > Store.MAX_ARMY_ROWS:
		show_result(Runtime.fail("NO_SPACE", "隊伍數或總人數超出 Site 額度"))
		return
	var config := _trial_setup()
	var setups: Array[Dictionary] = []
	for prefix: String in ["friendly", "enemy", "third"]:
		var faction := int(config.third_faction) if prefix == "third" else (0 if prefix == "friendly" else 1)
		for _index in range(int(counts[prefix])):
			setups.append({
				"count": 100, "faction": faction, "entry": str(config[prefix + "_entry"]),
				"role": str(config[prefix + "_role"]), "troop_type": str(config[prefix + "_troop_type"]),
				"female_percent": int(config[prefix + "_female_percent"]),
				"training": float(config[prefix + "_training"]),
				"tactics": float(config[prefix + "_tactics"]),
				"leadership": float(config[prefix + "_leadership"]),
				"coach": float(config[prefix + "_coach"]),
				"attack": bool(config[prefix + "_attack"]),
				"ai_enabled": bool(config[prefix + "_ai_enabled"]),
				"cart_count": int(config[prefix + "_cart_count"]),
				"wagon_count": int(config[prefix + "_wagon_count"]),
			})
	var result: Dictionary = lab.deploy_trial_armies(setups)
	_show_team_deployment_result(result)
	_update_combat_window()
	_refresh_vehicle_controls()

func _trial_setup() -> Dictionary:
	var trial_config := {
		"friendly_count": int(trial_friendly_count.value),
		"enemy_count": int(trial_enemy_count.value),
		"friendly_female_percent": int(trial_friendly_female_percent.value),
		"enemy_female_percent": int(trial_enemy_female_percent.value),
		"friendly_training": float(trial_friendly_training.value),
		"enemy_training": float(trial_enemy_training.value),
		"friendly_tactics": float(trial_friendly_tactics.value),
		"enemy_tactics": float(trial_enemy_tactics.value),
		"friendly_leadership": float(trial_friendly_leadership.value),
		"enemy_leadership": float(trial_enemy_leadership.value),
		"friendly_coach": float(trial_friendly_coach.value),
		"enemy_coach": float(trial_enemy_coach.value),
		"friendly_attack": trial_friendly_order.selected == 1,
		"enemy_attack": trial_enemy_order.selected == 1,
		"friendly_spawn": trial_friendly_spawn,
		"enemy_spawn": trial_enemy_spawn,
		"friendly_entry": ["east", "south", "west", "north"][trial_friendly_entry.selected] if trial_friendly_entry != null and trial_friendly_entry.selected >= 0 else "west",
		"enemy_entry": ["east", "south", "west", "north"][trial_enemy_entry.selected] if trial_enemy_entry != null and trial_enemy_entry.selected >= 0 else "east",
		"third_entry": ["east", "south", "west", "north"][trial_third_entry.selected] if trial_third_entry != null and trial_third_entry.selected >= 0 else "north",
		"entry_direction": ["east", "south", "west", "north"][trial_enemy_entry.selected] if trial_enemy_entry != null and trial_enemy_entry.selected >= 0 else "east",
		"third_enabled": trial_third_enabled.button_pressed,
		"third_faction": trial_third_faction.selected,
		"third_count": int(trial_third_count.value),
		"third_female_percent": int(trial_third_female_percent.value),
		"third_training": float(trial_third_training.value),
		"third_tactics": float(trial_third_tactics.value),
		"third_leadership": float(trial_third_leadership.value),
		"third_coach": float(trial_third_coach.value),
		"third_attack": trial_third_order.selected == 1,
		"third_spawn": trial_third_spawn,
	}
	for prefix: String in trial_roles:
		trial_config[prefix + "_role"] = ["combat", "work", "logistics"][trial_roles[prefix].selected]
		trial_config[prefix + "_ai_enabled"] = trial_roles[prefix].selected == 0 and trial_ai_enabled[prefix].button_pressed
		trial_config[prefix + "_troop_type"] = ["melee_infantry", "bow", "crossbow"][trial_troop_types[prefix].selected]
		trial_config[prefix + "_cart_count"] = int(trial_carts[prefix].value)
		trial_config[prefix + "_wagon_count"] = int(trial_wagons[prefix].value)
	return trial_config

func _deploy_melee_trial() -> void:
	var result: Dictionary = lab.start_melee_trial(_trial_setup())
	_show_team_deployment_result(result)
	_update_combat_window()
	_refresh_vehicle_controls()

func _add_third_melee_trial() -> void:
	var result: Dictionary = lab.add_melee_trial_team(_trial_setup())
	if result.ok:
		trial_third_enabled.button_pressed = true
	_show_team_deployment_result(result)
	_update_combat_window()
	_refresh_vehicle_controls()

func _trial_role_changed(prefix: String) -> void:
	var logistics: bool = trial_roles[prefix].selected == 2
	if trial_ai_enabled.has(prefix):
		trial_ai_enabled[prefix].disabled = trial_roles[prefix].selected != 0
		if trial_ai_enabled[prefix].disabled:
			trial_ai_enabled[prefix].button_pressed = false
	trial_troop_types[prefix].disabled = trial_roles[prefix].selected != 0
	if trial_troop_types[prefix].disabled:
		trial_troop_types[prefix].select(0)
	for input: SpinBox in [trial_carts[prefix], trial_wagons[prefix]]:
		input.editable = logistics
		if not logistics:
			input.set_value_no_signal(0)
	var orders := {"friendly": trial_friendly_order, "enemy": trial_enemy_order, "third": trial_third_order}
	if orders[prefix] != null:
		orders[prefix].select(1 if trial_roles[prefix].selected == 0 else 0)
	_update_trial_gender_counts()

func _update_trial_gender_counts() -> void:
	var counts := {"friendly": trial_friendly_count, "enemy": trial_enemy_count, "third": trial_third_count}
	var percentages := {"friendly": trial_friendly_female_percent, "enemy": trial_enemy_female_percent, "third": trial_third_female_percent}
	var labels := {"friendly": trial_friendly_gender_label, "enemy": trial_enemy_gender_label, "third": trial_third_gender_label}
	for prefix: String in counts:
		var people := int(counts[prefix].value) - int(trial_carts[prefix].value) - int(trial_wagons[prefix].value)
		var women := roundi(maxi(0, people) * float(percentages[prefix].value) / 100.0)
		labels[prefix].text = "至少保留一人" if people < 1 else "男 %d／女 %d" % [people - women, women]
		if people > 0 and people < int(counts[prefix].value):
			labels[prefix].text += " · 車 %d" % [int(counts[prefix].value) - people]

func _trial_team_ai(enabled: bool) -> void:
	if _crowd_active():
		var crowd_team := _crowd_command_team()
		show_result(lab.crowd_site.set_team_ai(int(crowd_team.team_id), enabled) if not crowd_team.is_empty() else Runtime.fail("NO_TARGET"))
		_update_combat_window()
		return
	var team := _selected_trial_team()
	if team == null or not team.combat_enabled or not team.has_army():
		show_result(Runtime.fail("NO_TARGET", "尚未部署此隊伍"))
		return
	show_result(team.set_tactical_ai_enabled(team.current_commander, enabled))
	_update_combat_window()

func _trial_team_order(order_id: int) -> void:
	if _crowd_active():
		show_result(_crowd_order("trial", order_id))
		_update_combat_window()
		return
	var team := _selected_trial_team()
	if team == null or not team.combat_enabled or not team.has_army():
		show_result(Runtime.fail("NO_TARGET", "尚未部署此隊伍"))
		return
	var candidate := _formation_move_candidate("trial", team) if order_id == TerrainArmy.CombatOrder.MOVE else {"ok": true, "preset": ""}
	if not bool(candidate.ok):
		show_result(candidate)
		return
	var preset: String = candidate.preset
	var target_id := _selected_enemy_identity(team) if order_id == TerrainArmy.CombatOrder.PURSUE else -1
	var result := team.issue_combat_order(team.current_commander, order_id, selected, target_id, Vector2i.ZERO, preset)
	if bool(result.get("ok", false)) and not preset.is_empty():
		_clear_formation_candidate()
	if result.ok and order_id == TerrainArmy.CombatOrder.HOLD and team.role == "work":
		var workers: Array[int] = []
		for index in range(team.combat_units.size()):
			if index != team.formal_commander and index != team.current_commander and team.is_member(index) and team.combat_can_act(index) and not work_team.is_assigned(team.combat_identity(index)):
				workers.append(team.combat_identity(index))
		if not workers.is_empty():
			result = work_team.assign(team, workers, team.duty_decider("team.work"))
	show_result(result)
	_update_combat_window()

func _player_corps_reposition() -> void:
	# PEACE3b: under crowd the lab routes the reposition (peace only; combat refused by crowd_peace_guard).
	var team_id := int(formal_team_choice.get_item_metadata(formal_team_choice.selected)) if formal_team_choice != null and formal_team_choice.selected >= 0 else -1
	if team_id < 0:
		show_result(Runtime.fail("NO_TARGET", "先在正式隊伍窗選取原隊伍"))
		return
	show_result(lab.issue_player_corps_reposition(team_id, selected))

func _appoint_trial_corps() -> Dictionary:
	var team := _selected_trial_team()
	if team == null or not team.combat_enabled or not team.has_army():
		return Runtime.fail("NO_TARGET", "所選隊伍已不在場")
	var person: Dictionary = lab._combat_target_in_site(lab.controlled_person_id())
	if person.is_empty() or not team.combat_enabled or int(person.owner.faction_id) != team.faction_id:
		return Runtime.fail("NO_AUTHORITY", "本人須在場並與受令隊伍同陣營")
	var corps: Dictionary = lab.terrain.site.get("corps", {}).duplicate(true)
	for relation: Dictionary in corps.values():
		if team.team_id in relation.team_ids:
			return Runtime.fail("BUSY", "所選隊伍已有軍團隸屬")
	var identity: int = lab.controlled_person_id()
	var key := "trial_%d" % identity
	var relation: Dictionary = corps.get(key, {"version": 1, "commander_person_id": identity, "team_ids": []})
	if int(relation.commander_person_id) != identity:
		return Runtime.fail("NO_AUTHORITY")
	relation.team_ids.append(team.team_id)
	corps[key] = relation
	var people := {}
	var teams := {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		people[actor.person_id] = actor.faction_id
	for original: TerrainArmy in lab.combat_armies:
		if not original.combat_enabled:
			continue
		teams[original.team_id] = original.faction_id
		for index in range(original.combat_units.size()):
			people[original.combat_identity(index)] = original.faction_id
	if not Runtime.valid_corps(corps, people, teams):
		return Runtime.fail("INVALID", "軍團長或所屬隊伍關係非法")
	lab.terrain.site["corps"] = corps
	var authority := Runtime.authorize_corps_reposition(lab.terrain, identity, team, lab._combat_target_in_site)
	if not bool(authority.get("ok", false)):
		corps[key].team_ids.erase(team.team_id)
		if corps[key].team_ids.is_empty(): corps.erase(key)
		lab.terrain.site["corps"] = corps
		return authority
	return Runtime.ok("已明示任命；軍團長可要求此隊轉進")

func _player_army_order(order_id: int, target_id: int = -1) -> void:
	if _crowd_active():
		show_result(_crowd_order("player", order_id, selected, target_id))
		return
	var team: TerrainArmy = lab.player_army()
	var candidate := _formation_move_candidate("player", team) if order_id == TerrainArmy.CombatOrder.MOVE else {"ok": true, "preset": ""}
	if not bool(candidate.ok):
		show_result(candidate)
		return
	var preset: String = candidate.preset
	var result: Dictionary = lab.issue_player_army_order(order_id, selected, target_id, Vector2i.ZERO, preset)
	if bool(result.get("ok", false)) and not preset.is_empty():
		_clear_formation_candidate()
	show_result(result)

func register_trial_equipment_nation(team: TerrainArmy, nation_id: String, head_id: int, member_ids: Array[int], culture: String) -> Dictionary:
	if team == null or not lab.combat_armies.has(team) or not team.combat_enabled or not team.has_army():
		return Runtime.fail("NO_TARGET", "請先部署原測試隊伍")
	if not nation_id.begins_with("trial_team_") or not EquipmentOrders._valid_key(nation_id) or lab.terrain.site.get("equipment_nations", {}).has(nation_id):
		return Runtime.fail("INVALID", "測試國別須用新的 trial_team_ 英數代號；既有國別不在此覆寫")
	if not EquipmentOrders.CULTURES.has(culture) or member_ids.is_empty() or not member_ids.has(head_id):
		return Runtime.fail("INVALID", "請明確指定文化、原成員與其中一位真實軍事首長")
	var known_people: Dictionary = {}
	for identity: int in member_ids:
		var index: int = team.index_for_identity(identity)
		var person: Dictionary = person_actions._person(identity)
		if known_people.has(identity) or index < 0 or not team.is_member(index) or person.is_empty() or int(person.faction) != team.faction_id or float(person.hp) <= 0.0:
			return Runtime.fail("INVALID", "名單含重複、非本隊或已失效的原人物")
		for nation: Dictionary in lab.terrain.site.get("equipment_nations", {}).values():
			if EquipmentOrders._member(nation, identity):
				return Runtime.fail("NO_AUTHORITY", "人物 #%d 已有原國別；不能由測試設定改籍" % identity)
		known_people[identity] = true
	var nation: Dictionary = {"military_head": head_id, "members": member_ids.duplicate(), "standards": {}, "culture": culture}
	if not EquipmentOrders.valid_nations({nation_id: nation}, lab.terrain.site.item_definitions, known_people):
		return Runtime.fail("INVALID", "國別、文化或原人物資料未通過保存規則")
	if not lab.terrain.site.has("equipment_nations"):
		lab.terrain.site["equipment_nations"] = {}
	lab.terrain.site.equipment_nations[nation_id] = nation
	return Runtime.ok("已建立測試國別 %s：原成員 %d 人、軍事首長 #%d；未換裝或新增物品" % [nation_id, member_ids.size(), head_id])

func revoke_trial_equipment_nation(team: TerrainArmy, nation_id: String) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if team == null or not lab.combat_armies.has(team) or not team.combat_enabled or not nation_id.begins_with("trial_team_") or nation.is_empty():
		return Runtime.fail("NO_TARGET", "只可明確解除此原測試隊伍的 trial_team_ 國別")
	if not person_actions.save_guard().ok:
		return Runtime.fail("BUSY", "先完成或取消人物作業再解除測試國別")
	var retiring: Array[int] = []
	for identity: int in nation.members:
		var index: int = team.index_for_identity(identity)
		var person: Dictionary = person_actions._person(identity)
		if index < 0 or not team.is_member(index) or person.is_empty():
			return Runtime.fail("STALE_SOURCE", "國別名單或原持物已不再是此原隊伍；未解除")
		if person.holder.equipped.has("cape"):
			var appointed := false
			for other_team: TerrainArmy in lab.combat_armies:
				if EquipmentOrders._team_grants_cape(other_team, other_team.index_for_identity(identity)):
					appointed = true
			if not appointed: retiring.append(identity)
	var checked: Dictionary = equipment_orders.retire_capes(retiring, true)
	if not checked.ok: return checked
	lab.terrain.site.equipment_nations.erase(nation_id)
	var retired: Dictionary = equipment_orders.retire_capes(retiring)
	if not retired.ok:
		lab.terrain.site.equipment_nations[nation_id] = nation
		return retired
	return Runtime.ok("已解除測試國別 %s；失去職務資格的原披風仍在本人行囊，其他實物未刪除" % nation_id)

func _trial_equipment_definition(slot: String, asset: String) -> Dictionary:
	var definition_id := slot + ":" + asset
	var definition: Dictionary = lab.terrain.site.item_definitions.get(definition_id,
		{"slot": slot, "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]})
	return definition if EquipmentOrders.valid_definition(definition_id, definition) and str(definition.slot) == slot and str(definition.asset) == asset else {}

func register_trial_equipment_definition(slot: String, asset: String) -> Dictionary:
	var definition: Dictionary = _trial_equipment_definition(slot, asset)
	if definition.is_empty(): return Runtime.fail("INVALID", "僅能登記原編輯器七槽中的真實裝備選項")
	var definition_id := slot + ":" + asset
	if lab.terrain.site.item_definitions.has(definition_id):
		return Runtime.fail("NO_CHANGE", "原裝備規格已登記；這不代表營地已有實物")
	lab.terrain.site.item_definitions[definition_id] = definition.duplicate(true)
	return Runtime.ok("已登記原裝備規格 %s；尚未建立實物 ID，重開標準視窗即可選用" % definition_id)

func stock_trial_equipment(team: TerrainArmy, slot: String, asset: String, quantity: int, original_owner: int) -> Dictionary:
	if team == null or not lab.combat_armies.has(team) or not team.combat_enabled or original_owner <= 0 or not team.is_member(team.index_for_identity(original_owner)) or person_actions._person(original_owner).is_empty():
		return Runtime.fail("NO_TARGET", "先選原測試隊伍內的真實物品來源人物")
	var definition: Dictionary = _trial_equipment_definition(slot, asset)
	if definition.is_empty() or quantity < 1 or quantity > 200:
		return Runtime.fail("INVALID", "實物品項或數量不合法")
	var data: TerrainData = lab.terrain
	var depot: Dictionary = data.site.depot_items
	if int(data.site.get("item_storage_version", -1)) != Runtime.ITEM_STORAGE_VERSION or not Runtime._item_holder_shape(depot) or str(depot.holder) != "depot":
		return Runtime.fail("INVALID", "原營地物品資料未就緒")
	if Runtime.carried_load(data.site, data.site.inventory, depot) + quantity > float(data.site.capacity):
		return Runtime.fail("STORAGE_FULL", "營地容量不足；本次未建立實物")
	if int(data.site.next_item) < 1 or int(data.site.next_item) + quantity >= 2147483647 or int(depot.version) + quantity >= 2147483647:
		return Runtime.fail("INVALID", "實物或持物版本序號已達上限")
	for offset: int in range(quantity):
		if data.site.item_records.has(str(int(data.site.next_item) + offset)):
			return Runtime.fail("INVALID", "原物品 ID 衝突；本次未建立實物")
	var definition_id := slot + ":" + asset
	for _index: int in range(quantity):
		var created: Dictionary = Runtime.create_equipment(data, depot, definition_id, definition, original_owner)
		assert(created.ok) # Fully checked above; one synchronous explicit test stock action.
	return Runtime.ok("已明確補入 %d 件真實 %s 實物；未給任何人物換裝" % [quantity, definition_id])

func _open_trial_equipment_setup(host: Window = null) -> void:
	var ui_context := "測試裝備設定"
	if _existing_dialog("trial_equipment", ui_context, host): return
	var original_control: int = lab.controlled_person_id()
	var original_data: TerrainData = lab.terrain
	var dialog := AcceptDialog.new()
	dialog.name = "TrialEquipmentSetupDialog"
	dialog.title = "測試情境：國別、標準規格與營地真實實物"
	dialog.min_size = Vector2i(680, 650)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(620, 570)
	dialog.add_child(scroll)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 600
	scroll.add_child(column)
	_label(column, "以下都是明確的測試情境操作。軍事首長是所選原人物；建立國別或規格不會換裝。", 14)
	var teams := _options(column, ["選擇已部署原隊伍"], "TrialEquipmentTeam")
	var selected_team := _selected_trial_team()
	for team: TerrainArmy in lab.combat_armies:
		if team.combat_enabled and team.has_army():
			teams.add_item("原隊伍 #%d · %d 人" % [team.team_id, team.command_members().size()])
			teams.set_item_metadata(teams.item_count - 1, team)
			if team == selected_team: teams.select(teams.item_count - 1)
	var nation_key := LineEdit.new()
	nation_key.name = "TrialEquipmentNationId"
	nation_key.placeholder_text = "trial_team_ 原隊伍代號"
	_label(column, "測試國別代號（新建後須明確解除才能清除原測試隊伍）", 14)
	column.add_child(nation_key)
	var heads := _options(column, ["選擇真實軍事首長"], "TrialEquipmentHead")
	var members := ItemList.new()
	members.name = "TrialEquipmentMembers"
	members.select_mode = ItemList.SELECT_MULTI
	members.custom_minimum_size = Vector2(580, 140)
	column.add_child(members)
	var cultures := _options(column, ["明確選擇中／日／西文化"], "TrialEquipmentCulture")
	cultures.set_item_metadata(0, "")
	for culture: String in EquipmentOrders.CULTURES:
		cultures.add_item(str(EquipmentOrders.CULTURES[culture]))
		cultures.set_item_metadata(cultures.item_count - 1, culture)
	var status := _label(column, "先選隊伍、首長、成員與文化；不自動授權。", 14)
	status.name = "TrialEquipmentStatus"
	var current_team := func() -> TerrainArmy:
		var team: TerrainArmy = teams.get_item_metadata(teams.selected) if teams.selected > 0 else null
		return team if is_instance_valid(team) and lab.combat_armies.has(team) and team.combat_enabled and team.has_army() else null
	var in_scope := func() -> bool:
		return lab.terrain == original_data and lab.controlled_person_id() == original_control
	var refresh_team := func(_index: int = 0) -> void:
		heads.clear()
		heads.add_item("選擇真實軍事首長")
		members.clear()
		var team: TerrainArmy = current_team.call()
		if team == null: return
		nation_key.text = "trial_team_%d" % team.team_id
		for index: int in team.command_members():
			var identity: int = team.combat_identity(index)
			if person_actions._person(identity).is_empty(): continue
			heads.add_item("人物 #%d%s" % [identity, " · 現任指揮" if index == team.current_commander else ""])
			heads.set_item_metadata(heads.item_count - 1, identity)
			var row := members.add_item("人物 #%d%s" % [identity, " · 玩家" if identity == lab.controlled_person_id() else ""])
			members.set_item_metadata(row, identity)
			members.select(row, false)
	var catalog := _options(column, ["選擇原七槽裝備規格"], "TrialEquipmentCatalog")
	for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
		if str(slot.id) not in Runtime.EQUIPMENT_SLOTS: continue
		for option: Dictionary in slot.options:
			if str(option.id) == "none": continue
			catalog.add_item("%s · %s" % [str(slot.id), str(option.label)])
			catalog.set_item_metadata(catalog.item_count - 1, {"slot": str(slot.id), "asset": str(option.id)})
	_label(column, "本次補入營地的實物件數", 14)
	var quantity := _number_input(column, "TrialEquipmentQuantity", 1, 200, 1)
	var stock_status := _label(column, "登記規格不產生實物；補給會占用原營地容量。", 14)
	stock_status.name = "TrialEquipmentStockStatus"
	var refresh_stock := func(_index: int = 0) -> void:
		if catalog.selected <= 0 or lab.terrain != original_data: return
		var choice: Dictionary = catalog.get_item_metadata(catalog.selected)
		var definition_id := str(choice.slot) + ":" + str(choice.asset)
		var count := 0
		for item_id: String in original_data.site.depot_items.item_ids:
			if str(original_data.site.item_records.get(item_id, {}).get("definition", "")) == definition_id: count += 1
		stock_status.text = "%s · 規格%s · 營地真實可領 %d 件" % [definition_id, "已登記" if original_data.site.item_definitions.has(definition_id) else "未登記", count]
	var show := func(result: Dictionary) -> void:
		status.text = str(result.get("message", "")) if bool(result.get("ok", false)) else "%s：%s" % [str(result.get("code", "FAILED")), str(result.get("message", ""))]
		show_result(result)
		refresh_stock.call()
	_button(column, "建立所選原人物的測試國別", "RegisterTrialEquipmentNation", func() -> void:
		if not in_scope.call():
			show.call(Runtime.fail("STALE", "控制人物或 Site 已變更，請重開"))
			return
		var selected_ids: Array[int] = []
		for row: int in members.get_selected_items(): selected_ids.append(int(members.get_item_metadata(row)))
		show.call(register_trial_equipment_nation(current_team.call(), nation_key.text.strip_edges(), int(heads.get_item_metadata(heads.selected)) if heads.selected > 0 else -1, selected_ids, str(cultures.get_item_metadata(cultures.selected)))))
	_button(column, "由所選原軍事首長編輯正式標準", "TrialEquipmentStandards", func() -> void:
		if not in_scope.call() or heads.selected <= 0:
			show.call(Runtime.fail("STALE", "請重新選擇原隊伍與軍事首長"))
			return
		var nation: Dictionary = original_data.site.get("equipment_nations", {}).get(nation_key.text.strip_edges(), {})
		if nation.is_empty() or EquipmentOrders.military_head(nation) != int(heads.get_item_metadata(heads.selected)):
			show.call(Runtime.fail("NO_AUTHORITY", "先建立此首長的原測試國別"))
			return
		dialog.hide()
		_open_equipment_standards(EquipmentOrders.military_head(nation), host))
	_button(column, "僅登記所選合法裝備規格（零實物）", "RegisterTrialEquipmentDefinition", func() -> void:
		if not in_scope.call() or catalog.selected <= 0:
			show.call(Runtime.fail("STALE", "請重新選擇原裝備規格"))
			return
		var choice: Dictionary = catalog.get_item_metadata(catalog.selected)
		show.call(register_trial_equipment_definition(str(choice.slot), str(choice.asset))))
	_button(column, "明確補入營地真實裝備實物", "StockTrialEquipment", func() -> void:
		if not in_scope.call() or catalog.selected <= 0 or heads.selected <= 0:
			show.call(Runtime.fail("STALE", "請重新選擇原隊伍、來源人物與裝備規格"))
			return
		var choice: Dictionary = catalog.get_item_metadata(catalog.selected)
		show.call(stock_trial_equipment(current_team.call(), str(choice.slot), str(choice.asset), int(quantity.value), int(heads.get_item_metadata(heads.selected)))))
	_button(column, "明確解除此測試國別（不刪實物）", "RevokeTrialEquipmentNation", func() -> void:
		if not in_scope.call():
			show.call(Runtime.fail("STALE", "控制人物或 Site 已變更，請重開"))
			return
		show.call(revoke_trial_equipment_nation(current_team.call(), nation_key.text.strip_edges())))
	teams.item_selected.connect(refresh_team)
	catalog.item_selected.connect(refresh_stock)
	refresh_team.call()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_show_dialog(dialog, "trial_equipment", ui_context, host)

func _formation_source() -> String:
	if _active_formation_view != "test" or formation_command_source == null: return "player"
	return "trial" if formation_command_source.selected == 0 else "test"

func _formation_name(preset_id: String) -> String:
	for index in range(formation_preset_choice.item_count):
		if str(formation_preset_choice.get_item_metadata(index)) == preset_id:
			return formation_preset_choice.get_item_text(index)
	return preset_id

func _formation_team(source: String) -> TerrainArmy:
	match source:
		"player": return lab.player_army()
		"test": return lab.army
		"trial": return _selected_trial_team()
	return null

func _formation_requester(team: TerrainArmy, source: String) -> int:
	if team == null:
		return -1
	return lab.controlled_member_index(team) if source == "player" else team.current_commander

func _formation_requester_identity(team: TerrainArmy, source: String) -> int:
	var requester := _formation_requester(team, source)
	return team.combat_identity(requester) if requester >= 0 and team.is_member(requester) else -1

func _formation_context_current(source: String, team: TerrainArmy, team_id: int, requester_identity: int, terrain: TerrainData) -> bool:
	return team != null and team == _formation_team(source) and team.combat_enabled and team.has_army() \
		and team.team_id == team_id and lab.terrain == terrain \
		and _formation_requester_identity(team, source) == requester_identity

func _facing_context_current() -> bool:
	return _formation_context_current(_facing_order_source, _facing_team, _facing_team_id, _facing_requester_identity, _facing_terrain) \
		and _facing_team.get_order_serial() == _facing_order_serial \
		and _facing_team._get_active_member_ids().hash() == _facing_roster_hash \
		and lab.terrain.navigation_revision == _facing_navigation_revision

func _clear_formation_candidate() -> void:
	_formation_candidate_id = ""
	_formation_candidate_source = ""
	_formation_candidate_team = null
	_formation_candidate_team_id = -1
	_formation_candidate_requester_identity = -1
	_formation_candidate_terrain = null
	_formation_preview_signature = ""
	_formation_preview_note = ""
	if _facing_order_source.is_empty() and view != null:
		view.clear_combat_move_preview()

func _formation_context_changed() -> void:
	_clear_formation_candidate()
	_update_formation_controls()

func _formation_candidate_for(source: String, team: TerrainArmy) -> String:
	if _formation_candidate_id.is_empty() or source != _formation_candidate_source or team != _formation_candidate_team:
		return ""
	if not _formation_context_current(source, team, _formation_candidate_team_id, _formation_candidate_requester_identity, _formation_candidate_terrain):
		_clear_formation_candidate()
		return ""
	return _formation_candidate_id

func _formation_move_candidate(source: String, team: TerrainArmy) -> Dictionary:
	if _formation_candidate_id.is_empty() or source != _formation_candidate_source:
		return {"ok": true, "preset": ""}
	var preset := _formation_candidate_for(source, team)
	if preset.is_empty():
		return Runtime.fail("STALE", "隊伍或指揮者已變更，請重新選陣")
	return {"ok": true, "preset": preset}

func _select_formation_candidate(index: int) -> void:
	_clear_formation_candidate()
	var source := _formation_source()
	var team := _formation_team(source)
	if team == null or not team.combat_enabled or not team.has_army():
		_update_formation_controls()
		return
	_formation_candidate_id = str(formation_preset_choice.get_item_metadata(index))
	_formation_candidate_source = source
	_formation_candidate_team = team
	_formation_candidate_team_id = team.team_id
	_formation_candidate_requester_identity = _formation_requester_identity(team, source)
	_formation_candidate_terrain = lab.terrain
	_update_formation_controls()

func _formation_external_signature(team: TerrainArmy) -> int:
	# Compare cheap authoritative occupancy inputs; the full planner only runs
	# when one of them changes, and Army still rechecks on commit.
	var blockers: Array = []
	for other: TerrainArmy in lab.combat_armies:
		if other == team or not other.has_army():
			continue
		blockers.append([other.team_id, other.get_active_members_occupancy(), other.get_active_movement_claims()])
	for actor: TerrainTestCharacter in lab.combat_actors:
		if is_instance_valid(actor):
			blockers.append([actor.person_id, actor.terrain_cell, actor.movement_from_cell,
				actor.is_moving(), actor.hp > 0.0 and actor.knockout_left <= 0.0])
	for vehicle: Dictionary in vehicles.records().values():
		blockers.append(vehicles._claims(vehicle))
	if lab.combat_movement_coordinator != null:
		blockers.append(lab.combat_movement_coordinator.get_retained_occupancy())
		var leases: Array = []
		for cell: Vector2i in lab.combat_movement_coordinator.deployment_registry.slot_owners:
			var lease = lab.combat_movement_coordinator.deployment_registry.slot_owners[cell]
			if lease != null and lease.formation_id != team.team_id:
				leases.append([cell, lease.formation_id, lease.order_serial])
		blockers.append(leases)
	return hash(blockers)

func _update_formation_controls() -> void:
	if _crowd_active():
		if formation_apply_button != null: formation_apply_button.disabled = true
		if formation_status_label != null: formation_status_label.text = "群眾隊形由戰場維持；可直接移動、守位、接敵、撤退或追擊。"
		return
	if formation_preset_choice == null or formation_status_label == null:
		return
	var source := _formation_source()
	var team := _formation_team(source)
	if team == null or not team.combat_enabled or not team.has_army():
		_clear_formation_candidate()
		formation_apply_button.disabled = true
		formation_status_label.text = "先選擇可下令的戰鬥隊伍。"
		return
	if not _formation_candidate_id.is_empty() and _formation_candidate_for(source, team).is_empty():
		_clear_formation_candidate()
	var preset := _formation_candidate_id if not _formation_candidate_id.is_empty() else team.formation_preset_id
	for index in range(formation_preset_choice.item_count):
		if str(formation_preset_choice.get_item_metadata(index)) == preset:
			if formation_preset_choice.selected != index:
				formation_preset_choice.select(index)
			break
	var requester := _formation_requester(team, source)
	var can_command := requester == team.current_commander and team.command_eligible(requester)
	formation_apply_button.disabled = not can_command or team.role != "combat"
	var plan: CombatDeploymentPlan = team.get_active_deployment_plan()
	var state := "待整隊" if team.formation_preset_id == "auto" else "已中斷"
	var counts := ""
	if plan != null:
		var active_count := team._get_active_member_ids().size()
		var automatic_total := 0
		var automatic_arrived := 0
		var controlled_count := 0
		for mid: int in plan.member_slot_map.keys():
			var member_index := team.index_for_identity(mid)
			if member_index < 0 or not team.is_member(member_index) or not team.combat_can_act(member_index):
				continue
			if team.is_controlled_person(member_index):
				controlled_count += 1
			else:
				automatic_total += 1
				if team.cells[member_index] == plan.get_slot_for_member(mid) and team.moving_to[member_index] == TerrainArmy.INVALID_CELL:
					automatic_arrived += 1
		var missing_count := maxi(0, plan.requested_count - automatic_total - controlled_count)
		counts = "\n自動隊員到位 %d/%d · 受控者自主 %d · 缺員 %d" % [automatic_arrived, automatic_total, controlled_count, missing_count]
		var settled := team.combat_order == TerrainArmy.CombatOrder.HOLD and team.get_active_move_plan() == null \
			and active_count == plan.member_slot_map.size() and plan.formation_preset_id == team.formation_preset_id \
			and team._combat_batch_members.is_empty() and team.get_active_movement_claims().is_empty() \
			and team._automatic_deployment_settled() and team._settled_deployment_leases_valid() \
			and automatic_arrived == automatic_total
		if active_count < plan.requested_count or plan.member_slot_map.size() < plan.requested_count:
			state = ("可動隊員已整隊；缺員" if controlled_count == 0 else "自動隊員已到位；缺員") if settled else "缺員"
		elif team.combat_order == TerrainArmy.CombatOrder.MOVE:
			state = "正在整隊"
		elif settled:
			state = "已整隊" if controlled_count == 0 else "自動隊員已到位"
		else:
			state = "已中斷"
	var title := formation_preset_choice.get_item_text(formation_preset_choice.selected)
	formation_status_label.text = "%s · 目前 %s%s\n%s" % [state, _formation_name(team.formation_preset_id), counts, FORMATION_DESCRIPTIONS.get(preset, "")]
	if not can_command:
		formation_status_label.text += " · 無指揮權"
	elif team.role != "combat":
		formation_status_label.text += " · 只有戰鬥隊可換陣"
	elif team._formation_change_pending:
		formation_status_label.text += "\n已接受新陣型；等待可用格位逐步展開"
	if _formation_candidate_id.is_empty():
		return
	if not _facing_order_source.is_empty():
		return
	var signature := str([team.team_id, requester, can_command, team.role, team.is_sustain_routed(),
		team.get_order_serial(), team.combat_order, team.combat_goal,
		team._get_active_member_ids().hash(), team.get_active_members_occupancy().hash(),
		team.get_active_movement_claims().hash(), lab.terrain.navigation_revision,
		_formation_candidate_id, _formation_external_signature(team)])
	if signature == _formation_preview_signature:
		formation_status_label.text += _formation_preview_note
		return
	_formation_preview_signature = signature
	if not can_command or team.role != "combat":
		view.clear_combat_move_preview()
		_formation_preview_note = "\n候選 %s（尚未下令）" % title
		formation_status_label.text += _formation_preview_note
		return
	var preview: Dictionary = team.preview_formation_change(_formation_candidate_id)
	if bool(preview.get("ok", false)):
		if bool(preview.get("pending", false)):
			view.clear_combat_move_preview()
			_formation_preview_note = "\n候選 %s：現在可接受；待空間或隊伍狀態允許時展開" % title
		else:
			view.show_combat_move_preview(preview)
			_formation_preview_note = "\n候選 %s · 占地 %d×%d · 現可部署 %d 人、跟隨 %d 人；按「套用陣型」下令" % [title,
				int(preview.get("final_width", 0)), int(preview.get("final_depth", 0)),
				preview.platform_slots.size() + preview.approach_queue_slots.size(), preview.get("following_member_ids", []).size()]
	else:
		view.clear_combat_move_preview()
		_formation_preview_note = "\n候選 %s：%s" % [title, str(preview.get("message", preview.get("code", "不能部署")))]
	formation_status_label.text += _formation_preview_note

func _apply_formation_change() -> void:
	if _crowd_active():
		show_result(Runtime.fail("CROWD_UNSUPPORTED", "群眾隊形由戰場維持；未改陣"))
		return
	var source := _formation_source()
	var team := _formation_team(source)
	if team == null or not team.combat_enabled or not team.has_army():
		show_result(Runtime.fail("NO_TARGET", "尚未部署可下令的隊伍"))
		return
	var had_candidate := not _formation_candidate_id.is_empty()
	var preset := _formation_candidate_for(source, team)
	if had_candidate and preset.is_empty():
		show_result(Runtime.fail("STALE", "隊伍或指揮者已變更，請重新選陣"))
		return
	if preset.is_empty():
		preset = str(formation_preset_choice.get_item_metadata(formation_preset_choice.selected))
	var requester := _formation_requester(team, source)
	var result: Dictionary = lab.issue_player_formation_change(preset) if source == "player" else team.issue_formation_change(requester, preset)
	if bool(result.get("ok", false)):
		_clear_formation_candidate()
	show_result(result)

func _begin_facing_move(source: String) -> void:
	if _crowd_active():
		var crowd_team := _crowd_command_team(source)
		if crowd_team.is_empty():
			show_result(Runtime.fail("NO_TARGET"))
			return
		_crowd_facing = true
		_facing_order_source = source
		_facing_order_anchor = Vector2i(-1, -1)
		_facing_team_id = int(crowd_team.team_id)
		_facing_terrain = lab.terrain
		_yield_command_window(source)
		message.text = "點選目的地，或按住左鍵拖曳指定群眾隊形面向；Esc 取消"
		return
	if get_tree().paused or lab.terrain == null or bool(lab.terrain.site.get("paused", false)) or lab._npc_target_pending:
		show_result(Runtime.fail("BUSY", "先結束暫停或目前的選擇操作"))
		return
	var team := _formation_team(source)
	if team == null or not team.combat_enabled or not team.has_army():
		show_result(Runtime.fail("NO_TARGET", "尚未部署可下令的隊伍"))
		return
	var candidate := _formation_move_candidate(source, team)
	if not bool(candidate.ok):
		show_result(candidate)
		return
	_facing_order_source = source
	_facing_order_anchor = Vector2i(-1, -1)
	_facing_preview_direction = Vector2i.ZERO
	_facing_preview_pending = true
	_facing_team = team
	_facing_team_id = team.team_id
	_facing_requester_identity = _formation_requester_identity(team, source)
	_facing_terrain = lab.terrain
	_facing_preset_id = candidate.preset
	_facing_order_serial = team.get_order_serial()
	_facing_roster_hash = team._get_active_member_ids().hash()
	_facing_navigation_revision = lab.terrain.navigation_revision
	view.clear_combat_move_preview()
	_yield_command_window(source)
	message.text = "在地圖點選目的地，或按住左鍵拖曳指定面向；Esc 取消"

func _cancel_facing_move() -> void:
	_crowd_facing = false
	if _facing_order_source.is_empty():
		return
	_facing_order_source = ""
	_facing_order_anchor = Vector2i(-1, -1)
	_facing_preview_direction = Vector2i.ZERO
	_facing_preview_pending = false
	_facing_team = null
	_facing_team_id = -1
	_facing_requester_identity = -1
	_facing_terrain = null
	_facing_preset_id = ""
	_facing_order_serial = -1
	_facing_roster_hash = 0
	_facing_navigation_revision = -1
	view.clear_combat_move_preview()
	_clear_formation_candidate()

func cancel_facing_move_on_gui_input(event: InputEvent) -> void:
	if _facing_order_source.is_empty() or not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	var over_gui := false
	for control: Control in [top_banner, panel, status_panel]:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(mouse.position):
			over_gui = true
			break
	var hovered := lab.get_viewport().gui_get_hovered_control()
	if not over_gui and (hovered == null or not hovered.is_visible_in_tree() or not hovered.get_global_rect().has_point(mouse.position)):
		return
	_cancel_facing_move()
	message.text = "已取消指定隊形方向"

func _update_facing_move_preview(direction: Vector2i) -> void:
	if direction == _facing_preview_direction and not _facing_preview_pending:
		return
	_facing_preview_direction = direction
	_facing_preview_pending = false
	if not _facing_context_current():
		_cancel_facing_move()
		message.text = "隊伍或指揮者已變更，請重新下令"
		return
	var preview: Dictionary = _facing_team.preview_combat_move(_facing_order_anchor, direction, _facing_preset_id)
	if bool(preview.get("ok", false)):
		view.show_combat_move_preview(preview)
		message.text = "終點預覽：平台 %d／進路 %d；放開左鍵下令" % [preview.platform_slots.size(), preview.approach_queue_slots.size()]
	else:
		view.clear_combat_move_preview()
		message.text = "此方向無合法部署：" + str(preview.get("message", preview.get("code", "請換位置")))

func _complete_facing_move(source: String, team: TerrainArmy, requester: int, anchor: Vector2i, direction: Vector2i, preset_id: String) -> void:
	if team == null or not team.combat_enabled:
		show_result(Runtime.fail("NO_TARGET", "隊伍已不在場"))
		return
	var result: Dictionary
	if source == "player":
		result = lab.issue_player_army_order(TerrainArmy.CombatOrder.MOVE, anchor, -1, direction, preset_id)
	else:
		result = team.issue_combat_order(requester, TerrainArmy.CombatOrder.MOVE, anchor, -1, direction, preset_id)
	show_result(result)

func _clear_melee_trial() -> void:
	_cancel_facing_move()
	_clear_formation_candidate()
	lab.clear_army()
	if _crowd_active():
		_update_combat_window()
		return
	var cleared := true
	for team: TerrainArmy in lab.combat_armies:
		cleared = cleared and not team.has_army()
	if cleared:
		message.text = "測試隊伍已清除；裝備與物資留在原格，既有遺物保留。"
	_update_combat_window()

func _show_melee_trial_status() -> void:
	_update_combat_window()
	open_window("team_info")
	message.text = "各隊資訊已更新於「隊伍資訊」視窗。"

func _update_retreat_button(button: Button, team: TerrainArmy, requester: int) -> void:
	if button == null:
		return
	var reason := ""
	if team == null or not team.combat_enabled or not team.has_army():
		reason = "尚未加入或部署隊伍"
	elif not team.is_sustain_routed():
		reason = "士氣尚未崩潰；隊長不能主動下達撤退"
	elif team.morale_retreat_terminal():
		reason = "隊伍已避難、撤出或進入投降處置"
	elif requester != team.current_commander or not team.command_eligible(requester):
		reason = "只有當前在場指揮者可下令"
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason if button.disabled else "沿原士氣潰退命令前往合法地圖邊緣，不使用所選格作為集結點"

func _update_combat_window() -> void:
	_update_formal_team_ui()
	if not is_instance_valid(combat_window) or combat_summary_label == null or not combat_window.visible:
		return
	if not (_test_page_visible("command") or _test_page_visible("deployment") or _test_page_visible("diagnostics")): return
	if _test_page_visible("command"):
		_refresh_trial_fire_status()
		_refresh_trial_suppress_status()
	if _crowd_active():
		_sync_trial_team_choices()
		var teams: Array = lab.crowd_site.command_teams()
		var crowd_people := 0
		for crowd_team: Dictionary in teams: crowd_people += int(crowd_team.count)
		combat_summary_label.text = "現場群眾 %d 隊 · %d 人。" % [teams.size(), crowd_people]
		var selected_team := _crowd_command_team()
		if trial_ai_status_label != null:
			trial_ai_status_label.text = "尚未選擇隊伍" if selected_team.is_empty() else lab.crowd_site.team_summary(int(selected_team.team_id))
		for pair: Array in [[trial_retreat_button, "trial"], [player_retreat_button, "player"], [test_retreat_button, "test"]]:
			var team := _crowd_command_team(str(pair[1]))
			if pair[0] != null:
				pair[0].disabled = team.is_empty() or not bool(team.get("routed", false))
		# CAV-4b: cavalry orders only for a team that is mostly mounted (native cavalry_formation).
		for pair: Array in [[trial_charge_button, "trial"], [player_charge_button, "player"], [trial_rally_button, "trial"], [player_rally_button, "player"]]:
			var cavalry_team := _crowd_command_team(str(pair[1]))
			if pair[0] != null:
				pair[0].disabled = cavalry_team.is_empty() or not bool(cavalry_team.get("cavalry", false))
		_update_formation_controls()
		return
	for cavalry_button: Button in [trial_charge_button, trial_rally_button, player_charge_button, player_rally_button]:
		if cavalry_button != null: cavalry_button.disabled = true
	_sync_trial_team_choices()
	var retreat_team := _selected_trial_team()
	if retreat_team != null and trial_command_team.selected >= 0:
		var title := _trial_team_choice_text(retreat_team)
		if trial_command_team.get_item_text(trial_command_team.selected) != title:
			trial_command_team.set_item_text(trial_command_team.selected, title)
	var player_team: TerrainArmy = lab.player_army()
	_update_retreat_button(trial_retreat_button, retreat_team, retreat_team.current_commander if retreat_team != null else -1)
	_update_retreat_button(player_retreat_button, player_team, lab.controlled_member_index(player_team))
	_update_retreat_button(test_retreat_button, lab.army, lab.army.current_commander)
	var dir_names: Array[String] = ["東", "南", "西", "北"]
	var f_name: String = dir_names[trial_friendly_entry.selected] if trial_friendly_entry != null and trial_friendly_entry.selected >= 0 else "西"
	var e_name: String = dir_names[trial_enemy_entry.selected] if trial_enemy_entry != null and trial_enemy_entry.selected >= 0 else "東"
	var t_name: String = dir_names[trial_third_entry.selected] if trial_third_entry != null and trial_third_entry.selected >= 0 else "北"
	trial_friendly_spawn_label.text = "我方：%s" % (("從【%s】方空位自動部署" % f_name) if trial_friendly_spawn.x < 0 else str(trial_friendly_spawn))
	trial_enemy_spawn_label.text = "敵方：%s" % (("從【%s】方空位自動部署" % e_name) if trial_enemy_spawn.x < 0 else str(trial_enemy_spawn))
	trial_third_spawn_label.text = "第三隊：%s" % (("從【%s】方空位自動部署" % t_name) if trial_third_spawn.x < 0 else str(trial_third_spawn))
	var deployed := 0
	var people := 0
	for team: TerrainArmy in lab.combat_armies:
		if team.has_army():
			deployed += 1
			people += team.combat_units.size()
	combat_summary_label.text = "現場 %d 隊 · %d 人。" % [deployed, people]
	if retreat_team != null and retreat_team.has_army():
		var carts := 0
		var wagons := 0
		var parked := 0
		for vehicle: Dictionary in vehicles.records().values():
			if int(vehicle.team_id) == retreat_team.team_id:
				carts += int(vehicle.kind == "cart")
				wagons += int(vehicle.kind == "wagon")
				parked += int(int(vehicle.operator_id) == 0)
		var purpose: String = {"combat": "戰鬥隊", "work": "工作隊", "logistics": "後勤隊"}.get(retreat_team.role, retreat_team.role)
		combat_summary_label.text += "\n所選隊伍 #%d：陣營 %s · %s\n人員 %d · 物資車 %d／馬車 %d（停泊 %d）· 共 %d 名額\n%s\nAI：%s · %s" % [
			retreat_team.team_id, _faction_label(retreat_team.faction_id), purpose,
			retreat_team.combat_units.size(), carts, wagons, parked, retreat_team.combat_units.size() + carts + wagons,
			retreat_team.combat_summary(), retreat_team.tactical_ai_status if retreat_team.tactical_ai_enabled else "手動指揮", retreat_team.tactical_ai_reason]
	elif deployed > 0:
		combat_summary_label.text += "\n請選擇一支仍在場的隊伍。"
	if trial_ai_status_label != null:
		trial_ai_status_label.text = "尚未部署所選隊伍。"
		if retreat_team != null and retreat_team.has_army():
			trial_ai_status_label.text = "所選隊伍：%s\n%s" % [retreat_team.tactical_ai_status if retreat_team.tactical_ai_enabled else "手動指揮", retreat_team.tactical_ai_reason]
			if retreat_team.tactical_ai_enabled and retreat_team.tactical_ai_target_id > 0:
				trial_ai_status_label.text += "\n判斷目標 #%d" % retreat_team.tactical_ai_target_id
	_update_formation_controls()

func _layout() -> void:
	var screen := lab.get_viewport_rect().size
	top_banner.position = Vector2(16, 16)
	top_banner.size = Vector2(maxf(1, screen.x - 32), 78)
	status_panel.scale = Vector2.ONE
	status_panel.size = Vector2(minf(460, screen.x - 32), 200)
	status_panel.position = Vector2(16, maxf(110, screen.y - status_panel.size.y - 16))
	if is_instance_valid(launcher_window): _clamp_tool_window(launcher_window)
	for window: Window in formal_windows.values(): _clamp_tool_window(window)

func focus_camp() -> void:
	if lab.terrain == null:
		return
	lab.camera.zoom = Vector2.ONE * 0.9
	lab.camera.position = (Vector2(lab.terrain.spawn_cell) + Vector2.ONE * 0.5) * 64 + (lab.get_viewport_rect().size * 0.5 - camera_usable_rect().get_center()) / 0.9
	lab.camera.force_update_scroll()

func show_result(result: Dictionary) -> void:
	if lab.restore_only: return
	message.text = str(result.get("message", ""))
	if _equipment_result.is_valid() and is_instance_valid(_equipment_dialog):
		_equipment_result.call(result)
	if _team_equipment_result.is_valid() and is_instance_valid(_team_equipment_dialog) and _team_equipment_dialog.visible:
		_team_equipment_result.call(result)
	update_ui()

func _show_team_deployment_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		show_result(result)
		return
	_team_info_report = str(result.get("message", ""))
	var brief := result.duplicate()
	brief["message"] = "隊伍已部署；詳細資訊見「隊伍資訊」視窗。"
	show_result(brief)
	open_window("team_info")

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
	_refresh_trial_fire_targets()

func handle_input(event: InputEvent) -> bool:
	if modes.selected == 5 and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			building_direction.select((building_direction.selected + 1) % 4)
			_building_direction_changed()
			return true
		if event.keycode == KEY_ESCAPE:
			_cancel_building_draft()
			return true
	if _crowd_facing:
		if not _crowd_active() or lab.terrain != _facing_terrain:
			_cancel_facing_move()
			return true
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_facing_move()
			return true
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var cell: Vector2i = lab.renderer.pick_cell(event.position)
			if event.pressed:
				_facing_order_anchor = cell
			elif _facing_order_anchor != Vector2i(-1, -1):
				var source := _facing_order_source
				var team := _crowd_command_team(source)
				var result := Runtime.fail("STALE", "隊伍已變更；請重新下令")
				if not team.is_empty() and int(team.team_id) == _facing_team_id:
					result = _crowd_order(source, TerrainArmy.CombatOrder.MOVE, _facing_order_anchor, -1, cell - _facing_order_anchor)
				_cancel_facing_move()
				show_result(result)
			return true
		return event is InputEventMouseMotion
	if not _facing_order_source.is_empty():
		if get_tree().paused or bool(lab.terrain.site.get("paused", false)):
			_cancel_facing_move()
			return false
		if not _facing_context_current():
			_cancel_facing_move()
			message.text = "隊伍或指揮者已變更，請重新下令"
			return true
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_facing_move()
			message.text = "已取消指定隊形方向"
			return true
		if event is InputEventMouseMotion and _facing_order_anchor.x >= 0:
			if event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
				return false
			var hover: Vector2i = lab.renderer.pick_cell(event.position)
			if lab.terrain.contains(hover) and hover != _facing_order_anchor:
				var drag := hover - _facing_order_anchor
				var direction := Vector2i(1 if drag.x > 0 else -1, 0) if absi(drag.x) >= absi(drag.y) else Vector2i(0, 1 if drag.y > 0 else -1)
				_update_facing_move_preview(direction)
			else:
				_update_facing_move_preview(Vector2i.ZERO)
			return true
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var cell: Vector2i = lab.renderer.pick_cell(event.position)
			if event.pressed:
				_facing_order_anchor = cell if lab.terrain.contains(cell) else Vector2i(-1, -1)
				_facing_preview_direction = Vector2i.ZERO
				_facing_preview_pending = true
				view.clear_combat_move_preview()
				if _facing_order_anchor.x >= 0:
					select_cell(cell)
					_update_facing_move_preview(Vector2i.ZERO)
				else:
					message.text = "請從地圖內選擇目的地"
			elif _facing_order_anchor.x >= 0:
				var delta := cell - _facing_order_anchor
				if not lab.terrain.contains(cell):
					message.text = "請在地圖內放開左鍵，或按 Esc 取消"
					view.clear_combat_move_preview()
				else:
					var direction := Vector2i.ZERO
					if delta != Vector2i.ZERO:
						direction = Vector2i(1 if delta.x > 0 else -1, 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, 1 if delta.y > 0 else -1)
					var source := _facing_order_source
					var team := _facing_team
					var requester := _formation_requester(team, source)
					var preset_id := _facing_preset_id
					var anchor := _facing_order_anchor
					_cancel_facing_move()
					_complete_facing_move(source, team, requester, anchor, direction, preset_id)
				_facing_order_anchor = Vector2i(-1, -1)
			return true
	if lab.test_placement_enabled or lab._npc_target_pending:
		return false
	var area_mode: bool = modes.selected in [2, 3, 4, 5, 6, 7] or (modes.selected == 0 and view.view_mode >= 2)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Vector2i = lab.renderer.pick_cell(event.position)
		if event.pressed:
			if not lab.terrain.contains(cell):
				drag_start = Vector2i(-1, -1)
				return true
			if building_resize and modes.selected == 5:
				selected = cell
			else:
				select_cell(cell)
			view.selection = Rect2i(cell, Vector2i.ONE)
			drag_start = cell
			if modes.selected == 5:
				_set_building_footprint(cell, Vector2i(int(building_width.value), int(building_depth.value)))
			if modes.selected == 1:
				manual_work()
		elif drag_start.x >= 0 and area_mode:
			var area := _rectangle(drag_start, cell)
			view.selection = area
			if modes.selected == 5:
				_set_building_footprint(area.position, Vector2i(int(building_width.value), int(building_depth.value)) if cell == drag_start else area.size)
			elif modes.selected == 7:
				var restored := Settlement.restore_ecology_zone(lab, lab.controlled_person_id(), area, kinds.selected - 1)
				if restored.ok: enable_worker()
				show_result(restored)
			elif modes.selected in [2, 3, 4, 6]:
				enable_worker()
				var capture: bool = modes.selected == 6
				show_result(Runtime.add_zone(lab.terrain, area, Env.Kind.WILDLIFE if capture else kinds.selected - 1, "capture" if capture else ["harvest", "clear", "survey"][modes.selected - 2]))
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

func _ecology_keys() -> Array[String]:
	var result: Array[String] = []
	var candidates: Array[String] = []
	if view.selection.get_area() > 1: candidates = Env.resources_in(lab.terrain, view.selection, kinds.selected - 1)
	else: candidates.append(source_key)
	for key: String in candidates:
		var resource := Env.resource(lab.terrain, key)
		if not resource.is_empty() and int(resource.kind) in Env.ECOLOGY_KINDS and not result.has(key): result.append(key)
	result.sort()
	return result

func _apply_ecology_mode() -> void:
	show_result(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), _ecology_keys(), str(Env.ECOLOGY_MODES[ecology_modes.selected]), -1, _ecology_revisions))
	view.refresh()

func _ecology_description(key: String) -> String:
	var resource := Env.resource(lab.terrain, key)
	var info := Env.ecology_info(lab.terrain, key)
	if info.is_empty(): return ""
	if not bool(resource.discovered): return "待勘探；存量與恢復條件未知。"
	if not bool(info.renewable): return "每遊戲分鐘重新供給；不屬族群繁殖。" if int(info.kind) == Env.Kind.SALT else "有限來源；耗盡後不自然回補。"
	var mode_name: String = ["永續採取", "休養保護", "一般採取"][Env.ECOLOGY_MODES.find(str(info.mode))]
	var text := "%s · 現量 %d / 有效容量 %d（原容量 %d）\n可採 %d · 每批最多 %d" % [mode_name, int(info.remaining), int(info.capacity), int(info.base_capacity), int(info.takeable), int(info.batch_takeable)]
	if bool(info.population):
		var policy_status := "休養保護" if str(info.mode) == "protected" else "一般採取（可採至零）" if str(info.mode) == "general" else "保育休採" if bool(info.resting) else "可採"
		text += "\n留底 %d · 復採 %d · %s" % [int(info.reserve), int(info.resume), policy_status]
	if int(info.remaining) > int(info.capacity): text += "\n現量超出當前承載；不增加產物。"
	var blocked := str(info.recovery_blocked)
	if int(info.kind) == Env.Kind.TIMBER and int(info.remaining) == 0 and blocked.is_empty() and reserves_cell(lab.terrain.cell_from_index(int(resource.cell))): blocked = "MOVING"
	if bool(info.cleared): return text + "\n已清地，普通等待不會恢復；復育後容量潛力 %d。" % int(info.potential_capacity)
	if not blocked.is_empty():
		var reasons := {"NO_HABITAT": "棲地被占用或不合格", "OCCUPIED": "原來源被人工用地占用", "NO_WORK_CELL": "沒有合法作業／展示格", "FIRE_HOT": "火場或待解決接觸事件", "MOVING": "人物、車輛或移動預約正在使用此格"}
		return text + "\n恢復受阻：%s；到期只會重查。" % str(reasons.get(blocked, blocked))
	if int(info.next_recovery) >= 0: text += "\n下次%s：%.1f 遊戲分後。" % ["增加 1" if bool(info.population) else "成熟", float(info.wait_minutes)]
	elif int(info.remaining) >= int(info.capacity): text += "\n目前滿量。"
	else: text += "\n等待原恢復排程。"
	return text

func _ecology_person_signature() -> String:
	# Authority depends on the controller being alive, awake and free; restore
	# progress depends on its current task.
	var person := person_actions._person(lab.controlled_person_id(), false)
	if person.is_empty(): return ""
	var task: Variant = lab.terrain.site.worker if person.owner == lab.npc else lab.terrain.site.manual
	if int(person.unit) >= 0:
		# Crowd actors are Nodes: Object.get takes one argument and returns null when unset.
		task = person.body.get("work_task", {}) if person.body is Dictionary else person.body.get("work_task")
		if task == null: task = {}
	return JSON.stringify([float(person.get("hp", 0.0)), person.get("cell", Vector2i(-1, -1)), person_actions._ready(person), person_actions.is_busy(int(person.person_id)), task])

func _update_ecology_ui() -> void:
	if ecology_status == null: return
	# Box selections can hold hundreds of sources; authority/habitat reads are
	# only redone when the selection, map, offices, minute or controller change.
	# Commands still re-resolve everything at commit.
	var settlement_offices: Variant = Settlement.record(lab.terrain).get("offices", {})
	var cache_key := [view.selection, source_key, kinds.selected, lab.terrain.environment_revision, int(lab.terrain.site.minute),
		lab.controlled_person_id(), int(settlement_offices.get("revision", -1)) if settlement_offices is Dictionary else -1,
		Runtime._ship_runtime_pending(lab.terrain), _crowd_active(), _ecology_person_signature()]
	if cache_key == _ecology_ui_cache_key:
		ecology_status.text = _ecology_ui_cache_text
		if not source_key.is_empty(): details.text += "\n" + _ecology_ui_cache_description
		return
	var keys := _ecology_keys()
	var signature := JSON.stringify(keys)
	var checked := Runtime.fail("NO_TARGET", "請選取原可更新來源。")
	_ecology_revisions.clear()
	if not keys.is_empty():
		for key: String in keys:
			checked = Settlement.ecology_authority(lab, key, lab.controlled_person_id())
			if not checked.ok: break
			_ecology_revisions[key] = int(checked.revision)
		if signature != _ecology_selection_signature:
			ecology_modes.select(maxi(0, Env.ECOLOGY_MODES.find(str(Env.ecology_info(lab.terrain, keys[0]).mode))))
	_ecology_selection_signature = signature
	ecology_apply_button.disabled = not checked.ok
	ecology_apply_button.tooltip_text = str(checked.get("message", ""))
	ecology_modes.disabled = not checked.ok
	ecology_status.text = "所選 %d 個原來源（已去重）\n%s" % [keys.size(), "管理：" + str(checked.position_name) if checked.ok else str(checked.get("message", ""))]
	if view.selection.get_area() > 1:
		var totals := {}
		var unknown := 0
		for key: String in keys:
			if not bool(Env.resource(lab.terrain, key).discovered):
				unknown += 1
				continue
			var info := Env.ecology_info(lab.terrain, key)
			var kind := int(info.kind)
			if not totals.has(kind): totals[kind] = {"remaining": 0, "capacity": 0, "takeable": 0}
			for field: String in ["remaining", "capacity", "takeable"]: totals[kind][field] += int(info[field])
		for kind: int in totals:
			ecology_status.text += "\n%s：%d / %d，可採 %d" % [str(Env.NAMES[kind]), int(totals[kind].remaining), int(totals[kind].capacity), int(totals[kind].takeable)]
		if unknown > 0: ecology_status.text += "\n另有 %d 個來源待勘探，未推定數量。" % unknown
	manual_restore_button.disabled = source_key.is_empty() or not bool(Env.ecology_info(lab.terrain, source_key).get("restorable", false)) or not Settlement.ecology_authority(lab, source_key, lab.controlled_person_id()).ok
	if not source_key.is_empty(): details.text += "\n" + _ecology_description(source_key)
	var person := person_actions._person(lab.controlled_person_id(), false)
	var task: Dictionary = {}
	if not person.is_empty():
		var held: Variant = lab.terrain.site.worker if person.owner == lab.npc else lab.terrain.site.manual
		if int(person.unit) >= 0:
			held = person.body.get("work_task", {}) if person.body is Dictionary else person.body.get("work_task")
		if held is Dictionary: task = held
	if str(task.get("action", "")) == "restore": ecology_status.text += "\n本人復育進度 %.1f / %.0f 遊戲分" % [float(task.get("progress", 0.0)), Runtime.resource_work_minutes(Env.Kind.TIMBER, "restore")]
	_ecology_ui_cache_key = cache_key
	_ecology_ui_cache_text = ecology_status.text
	_ecology_ui_cache_description = _ecology_description(source_key) if not source_key.is_empty() else ""

func _rectangle(a: Vector2i, b: Vector2i) -> Rect2i:
	return Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), Vector2i(absi(a.x - b.x) + 1, absi(a.y - b.y) + 1)).intersection(Rect2i(Vector2i.ZERO, lab.terrain.size))

func deposit_controlled_cargo() -> void:
	var peace := person_actions.crowd_peace_guard([lab.controlled_person_id()])
	if not peace.ok:
		show_result(peace)
		return
	var person := person_actions._person(lab.controlled_person_id())
	if get_tree().paused or bool(lab.terrain.site.paused) or person.is_empty() or not person_actions._ready(person) or person_actions.is_busy(int(person.person_id)):
		show_result(Runtime.fail("BUSY", "本人須清醒、自由並停止其他作業"))
		return
	var result := Runtime.deposit(lab.terrain, person.cargo, person.cell)
	if result.ok:
		person.holder.version = int(person.holder.version) + 1
	show_result(result)

func stock_controlled_livestock() -> void:
	var peace := person_actions.crowd_peace_guard([lab.controlled_person_id()])
	if not peace.ok:
		show_result(peace)
		return
	var person := person_actions._person(lab.controlled_person_id())
	if get_tree().paused or bool(lab.terrain.site.paused) or person.is_empty() or not person_actions._ready(person) or person_actions.is_busy(int(person.person_id)):
		show_result(Runtime.fail("BUSY", "本人須清醒、自由並停止其他作業"))
		return
	var result := Runtime.stock_pasture(lab.terrain, feature_key, person.cargo, person.cell)
	if result.ok:
		person.holder.version = int(person.holder.version) + 1
	show_result(result)

func manual_work(action: String = "harvest") -> void:
	var peace := person_actions.crowd_peace_guard([lab.controlled_person_id()])
	if not peace.ok:
		show_result(peace)
		return
	var person := person_actions._person(lab.controlled_person_id())
	if get_tree().paused or bool(lab.terrain.site.paused) or person.is_empty() or not person_actions._ready(person) or person_actions.is_busy(int(person.person_id)):
		show_result(Runtime.fail("BUSY"))
		return
	if action == "restore":
		var authority := Settlement.ecology_authority(lab, source_key, lab.controlled_person_id())
		if not authority.ok:
			show_result(authority)
			return
		var preflight := Runtime.harvest(lab.terrain, source_key, person.cell, person.cargo, action, true)
		if not preflight.ok:
			show_result(preflight)
			return
	if action == "capture" and Runtime.capturable_species(Env.resource(lab.terrain, source_key)).is_empty():
		show_result(Runtime.fail("INVALID", "只有野馬與羊可以活捉"))
		return
	if work_team.reserved_targets().has(source_key):
		show_result(Runtime.fail("BUSY", "此來源已有原人物作業"))
		return
	if int(person.unit) >= 0:
		show_result(work_team.begin_manual(int(person.person_id), source_key, action))
		return
	if person.owner == lab.npc:
		if not Env.work_cells(lab.terrain, source_key).has(person.cell):
			show_result(Runtime.fail("UNREACHABLE", "請原人物走到來源旁"))
			return
		var resource := Env.resource(lab.terrain, source_key)
		if resource.is_empty():
			show_result(Runtime.fail("NO_TARGET"))
			return
		Runtime.assign_task(lab.terrain, Runtime.ok("原人物手動作業", {"target": source_key, "action": action if bool(resource.discovered) else "survey", "cell": lab.terrain.index(person.cell)}))
		lab.terrain.site["worker_enabled"] = false
		lab.terrain.site.worker.manual_control = true
		return
	show_result(Runtime.begin_manual(lab.terrain, source_key, lab.character.terrain_cell, action))

func build_selected() -> void:
	if _building_kind() == "irrigation_channel": _irrigation_build_selected(false); return
	if not building_resize and _building_kind() == "settlement_center":
		found_settlement_selected()
		return
	var result := Runtime.request_resize(lab.terrain, feature_key, build_cells, reserves_cell, int(_building_options().get("owner_faction", -1))) if building_resize else Runtime.request_build(lab.terrain, _building_kind(), build_cells, reserves_cell, _building_options())
	if result.ok:
		enable_worker()
		feature_key = str(result.get("feature", feature_key))
		_cancel_building_draft()
		view.refresh()
	show_result(result)

func enable_worker() -> void:
	if region_operation_pending():
		show_result(Runtime.fail("BUSY", "正在更新目的地；完成前暫停新派工"))
		return
	lab.terrain.site["worker_enabled"] = lab.npc != null
	_work_elapsed = 1.0

func release_worker() -> void:
	if region_operation_pending():
		show_result(Runtime.fail("BUSY", "正在更新目的地；完成前暫停新派工"))
		return
	lab.terrain.site["worker_enabled"] = false
	lab.terrain.site.worker.mode = "idle"
	lab.terrain.site.worker.target = ""
	lab.terrain.site.worker.progress = 0.0
	lab.terrain.site.worker.manual_control = false
	if lab.npc != null:
		lab.npc.issue_command(TerrainTestNPC.Command.STOP)

func _actor_people_blocked(cell: Vector2i, requester: Node, endpoint_actor: Node = null) -> bool:
	var ignored: Array[int] = []
	if requester is TerrainTestCharacter: ignored.append(requester.person_id)
	if endpoint_actor is TerrainTestCharacter: ignored.append(endpoint_actor.person_id)
	if _crowd_active() and lab.crowd_site.siege_people_block(cell, ignored): return true
	for team: TerrainArmy in lab.combat_armies:
		if _crowd_active() and lab.crowd_site.owns_original_team(team): continue
		if team._cell_owners.has(cell) or team._reserved_cells.has(cell): return true
		for index in range(team.combat_units.size()):
			if ignored.has(team.combat_identity(index)) or team._ship_embarked(index): continue
			if bool(team.combat_hot_get(index, &"departed", false)) or bool(team.combat_hot_get(index, &"site_exited", false)): continue
			if team.cells[index] == cell or team.moving_to[index] == cell: return true
	for actor: TerrainTestCharacter in lab.combat_actors:
		if actor == requester or actor == endpoint_actor or actor.site_exited: continue
		if _crowd_active() and lab.crowd_site.contains_person(actor.person_id): continue
		if actor.terrain_cell == cell or actor.is_moving() and actor.movement_from_cell == cell: return true
	return false

func _actor_blocked(cell: Vector2i, requester: Node) -> bool:
	var identity: int = requester.person_id if requester is TerrainTestCharacter else 0
	if vehicles.blocks_person_cell(cell, identity) and not vehicles.person_origin_exception(identity, cell): return true
	return _actor_people_blocked(cell, requester)

func _actor_exit_goal(origin: Vector2i, from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	var direction := to_cell - from_cell
	if absi(direction.x) + absi(direction.y) != 1: return to_cell
	for vehicle: Dictionary in vehicles.records().values():
		if str(vehicle.kind) != "siege_tower" or vehicle.get("deployed_pose", {}).is_empty(): continue
		var geometry: Dictionary = Runtime.siege_tower_geometry(lab.terrain, vehicle)
		if bool(geometry.active) or not geometry.physical.has(origin) or not geometry.physical.has(from_cell): continue
		var cursor := from_cell
		for index: int in range(maxi(lab.terrain.size.x, lab.terrain.size.y)):
			var next := cursor + direction
			if not lab.terrain.can_step(cursor, next): return TerrainArmy.INVALID_CELL
			if not geometry.physical.has(next): return next
			cursor = next
		return TerrainArmy.INVALID_CELL
	return to_cell

func _actor_step_blocked(origin: Vector2i, from_cell: Vector2i, to_cell: Vector2i, goal: Vector2i, requester: Node, endpoint_actor: Node = null) -> bool:
	if goal == TerrainArmy.INVALID_CELL: goal = _actor_exit_goal(origin, from_cell, to_cell)
	if goal == TerrainArmy.INVALID_CELL or not lab.terrain.can_step(from_cell, to_cell): return true
	var identity: int = requester.person_id if requester is TerrainTestCharacter else 0
	if vehicles.blocks_person_step(identity, origin, from_cell, to_cell, goal): return true
	return _actor_people_blocked(to_cell, requester, endpoint_actor)

func _worker_blocked(cell: Vector2i) -> bool:
	return _actor_blocked(cell, lab.npc)

func reserves_cell(cell: Vector2i) -> bool:
	if vehicles.blocks_cell(cell):
		return true
	if is_instance_valid(lab.crowd_site) and lab.crowd_site.reserves_cell(cell):
		return true
	var native_active: bool = is_instance_valid(lab.crowd_site) and lab.crowd_site.active
	for team: TerrainArmy in lab.combat_armies:
		if native_active and lab.crowd_site.owns_original_team(team): continue
		if team.reserves_terrain_cell(cell):
			return true
	for actor: TerrainTestCharacter in lab.combat_actors:
		if native_active and lab.crowd_site.contains_person(actor.person_id): continue
		if actor.occupies_cell(cell):
			return true
	return false

func _combat_event(duration: float) -> void:
	if lab.terrain != null:
		Runtime.mark_combat(lab.terrain, duration)

func toggle_pause() -> void:
	_cancel_facing_move()
	lab.terrain.site["paused"] = not bool(lab.terrain.site.paused)
	get_tree().paused = bool(lab.terrain.site.paused)
	lab._clear_movement_input()
	update_ui()

func tick(delta: float, accepted_game_seconds: float = -1.0) -> void:
	_crew_handled.clear()
	var data: TerrainData = lab.terrain
	if data == null or data.site.is_empty():
		return
	if not lab.restore_only: view.animate(delta)
	_ui_elapsed += delta
	if is_instance_valid(combat_window) and combat_window.visible:
		_combat_ui_elapsed += delta
		if _combat_ui_elapsed >= 0.1:
			_combat_ui_elapsed = fmod(_combat_ui_elapsed, 0.1)
			_update_combat_window()
	else:
		_combat_ui_elapsed = 0.0
	if not bool(data.site.paused) and not get_tree().paused:
		vehicles.settle_operators()
		_work_elapsed += delta
		_save_elapsed += delta
		var inputs: Dictionary = _shared_worker_inputs if not _shared_worker_inputs.is_empty() else _prepare_original_work_inputs()
		var worker_ready: bool = bool(inputs.get("worker_ready", false))
		var manual_ready: bool = bool(inputs.get("manual_ready", false))
		var worker_limit: int = int(inputs.get("worker_limit", 0))
		var time_multiplier := float(lab.simulation_speed)
		var work_interval := accepted_game_seconds if accepted_game_seconds >= 0.0 else Runtime.game_seconds(delta, float(data.site.combat_left)) * time_multiplier
		var manual_limit: int = int(inputs.get("manual_limit", 0))
		Runtime.advance(data, delta, worker_ready, manual_ready, reserves_cell, lab.fatigue_work_minutes, _advance_crew,
			worker_limit, manual_limit, time_multiplier, int(inputs.get("worker_faction", -1)), work_interval,
			not _shared_work_plan.is_empty() and is_same(_shared_work_plan, lab._shared_work_plan), checked_runtime_clock_interval())
		_advance_settlement(delta, work_interval)
		if checked_runtime_clock_interval().is_empty() and worker_ready and not lab.npc.work_resting:
			# Waiting on tools/inputs/output space is assigned duty, not a rest break.
			lab._fatigue_work_seconds[lab.npc] = work_interval
			lab.npc.fatigue_rest = 0.0
	if data.navigation_revision != _navigation_revision:
		_navigation_revision = data.navigation_revision
		lab.renderer.redraw()
		for team: TerrainArmy in lab.combat_armies:
			team.notify_terrain_changed()
		if is_instance_valid(lab.crowd_site):
			# A refused native sync means GD navigation and native walls disagree; never drop it silently.
			var native_synced: bool = lab.crowd_site.sync_terrain()
			if not native_synced and lab.crowd_site.active: push_error("STRUCTURE_NATIVE_TERRAIN_REJECTED")
	if not data.site.notices.is_empty():
		if not lab.restore_only: message.text = str(data.site.notices.back())
		data.site.notices.clear() # Same original consumption; no quiet UI update.
	if _ui_elapsed >= 0.25:
		_ui_elapsed = 0
		var team: TerrainArmy = lab.player_army()
		if player_army_label != null:
			var controlled_member: int = lab.controlled_member_index(team)
			player_army_label.text = "尚未加入隊伍" if team == null else ("本隊 %d 名原人物；%s\n正式 %s／當前 %s\n%s" % [team.command_members().size(), "你可下令" if team.current_commander == controlled_member and team.command_eligible(controlled_member) else "你是隊員，保持自主操作", str(team.combat_identity(team.formal_commander)) if team.formal_commander >= 0 else "空缺", str(team.combat_identity(team.current_commander)) if team.current_commander >= 0 else "空缺", team.command_notice])
		update_ui(refresh_hidden_combat_summary_on_tick)

func finish_tick() -> void:
	if lab.restore_only: return
	var fault: Dictionary = original_step_fault_guard()
	if not fault.ok: return
	if region_operation_pending():
		if not get_tree().paused and lab.terrain != null and not bool(lab.terrain.site.get("paused", false)):
			resume_region_operation() # Exactly one retry; elapsed input is already zero.
		return
	if finish_ground_crossing(): return
	# The caller has now advanced bodies/fatigue as well as the Site clock/work.
	var data: TerrainData = lab.terrain
	if data == null or data.site.is_empty() or bool(data.site.paused):
		return
	if _finish_region_departure(): return
	if _save_elapsed >= 30 and float(data.site.combat_left) <= 0 and not _auto_save_blocked:
		var result := save_to(save_path)
		# A due save waits for the original pending death/capture handoff. It must
		# not lose its deadline and wait another 30 seconds after a BUSY response.
		if result.ok or str(result.get("code", "")) != "BUSY": _save_elapsed = 0.0
		show_result(result)


func _test_army_order(order_id: int, goal: Vector2i = Vector2i(-1, -1), target_id: int = -1) -> void:
	if _crowd_active():
		show_result(_crowd_order("test", order_id, goal, target_id))
		return
	var candidate := _formation_move_candidate("test", lab.army) if order_id == TerrainArmy.CombatOrder.MOVE else {"ok": true, "preset": ""}
	if not bool(candidate.ok):
		show_result(candidate)
		return
	var preset: String = candidate.preset
	var result: Dictionary = lab.army.issue_combat_order(lab.army.current_commander, order_id, goal, target_id, Vector2i.ZERO, preset)
	if bool(result.get("ok", false)) and not preset.is_empty():
		_clear_formation_candidate()
	show_result(result)

func _open_officer_priority(host: Window = null) -> void:
	var ui_context := str(lab.controlled_person_id())
	if _existing_dialog("officer", ui_context, host): return
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
	_show_dialog(dialog, "officer", ui_context, host)

func _capture_positions(state: Dictionary = {}, read_only: bool = false) -> void:
	if state.is_empty(): state = lab.terrain.site
	state["actors"] = {}
	if lab.actor_present(lab.character):
		state["player_cell"] = lab.terrain.index(lab.character.terrain_cell)
		state["actors"]["player"] = lab.character.capture_state(read_only)
	if lab.actor_present(lab.npc):
		state["worker"]["cell"] = lab.terrain.index(lab.npc.terrain_cell)
		state["actors"]["npc"] = lab.npc.capture_state(read_only)
	for actor: TerrainTestCharacter in lab.combat_actors:
		if not actor.has_meta(&"crowd_handoff"): continue
		var key := "player" if actor == lab.character else "npc"
		if state["actors"].has(key):
			var extra: Dictionary = actor.get_meta(&"crowd_handoff").duplicate(true)
			extra["stagger"] = actor.exchange_stagger
			extra["exch_cd"] = actor.exchange_cooldown
			extra["ranged_cd"] = actor.ranged_cooldown
			extra["skill_cd"] = actor.exchange_skill_cooldown
			state["actors"][key]["crowd_handoff"] = extra
	var armies: Array = []
	for team: TerrainArmy in lab.combat_armies:
		if team.combat_enabled:
			armies.append(team.capture_combat_state(read_only))
	state["armies"] = armies

func supply_save_guard(ignore_ground_crossing: bool = false, allow_dirty_fire_save: bool = false,
		allow_checkpointed_fire_jobs: bool = false) -> Dictionary:
	var fault: Dictionary = original_step_fault_guard()
	if not fault.ok: return fault
	if region_operation_pending(): return Runtime.fail("BUSY", "原船隊或固定世界補算等待中，不能保存或換場")
	if not ignore_ground_crossing and not _ground_crossing.is_empty():
		return Runtime.fail("BUSY", "原跨界 ACTION 或冷地點補算尚未提交，不能保存或換場")
	var siege_guard := Store.siege_save_guard(lab.terrain, allow_dirty_fire_save)
	if not siege_guard.ok: return siege_guard
	if _crowd_active():
		var crowd_guard: Dictionary = lab.crowd_site.save_guard()
		if not crowd_guard.ok: return crowd_guard
	var cape_guard := cape_policy_guard()
	if not cape_guard.ok: return cape_guard
	if lab.has_unpersisted_ranged_projectiles():
		return Runtime.fail("BUSY", "箭矢仍在飛行；結算前不保存、換場或清除射手")
	if not _pending_deaths.is_empty():
		return Runtime.fail("BUSY", "倒地／在途移動及遺物轉存尚未結束")
	var checkpointed_fire_jobs: bool = allow_checkpointed_fire_jobs and lab.fire_owner_snapshot_matches_checkpoint()
	var action_guard := person_actions.fire_jobs_save_guard(lab.fire_action_cursor) \
		if allow_dirty_fire_save or checkpointed_fire_jobs else person_actions.save_guard()
	if not action_guard.ok:
		return action_guard
	for entry: Dictionary in lab.terrain.site.get("team_supply", {}).values():
		if not entry.get("delivery", {}).is_empty():
			return Runtime.fail("BUSY", "口糧交付尚未完成；請完成或取消後保存，來源未扣物")
	return Runtime.ok()


func configure_test_paths(arguments: PackedStringArray) -> Dictionary:
	var index := arguments.find("--crowd-test")
	var atlas_index := arguments.find("--crowd-atlas-root")
	if index < 0:
		if atlas_index >= 0:
			_test_path_error = "--crowd-atlas-root 只能與 --crowd-test 一起使用"
			return Runtime.fail("INVALID_TEST_PATH", _test_path_error)
		return Runtime.ok()
	if index + 1 >= arguments.size():
		_test_path_error = "--crowd-test 缺少 run_id"
		return Runtime.fail("INVALID_TEST_PATH", _test_path_error)
	var run_id := arguments[index + 1]
	if run_id.is_empty() or run_id != run_id.validate_filename() or run_id in [".", ".."] or run_id.contains(":") or run_id.contains("/") or run_id.contains("\\"):
		_test_path_error = "--crowd-test run_id 必須是單一路徑片段"
		return Runtime.fail("INVALID_TEST_PATH", _test_path_error)
	crowd_test_run_id = run_id
	save_root = "user://sites/crowd_test/" + run_id
	save_path = save_root.path_join("current.json")
	if atlas_index >= 0:
		if atlas_index + 1 >= arguments.size():
			_test_path_error = "--crowd-atlas-root 缺少測試圖集路徑"
			return Runtime.fail("INVALID_TEST_PATH", _test_path_error)
		var atlas_root := arguments[atlas_index + 1].replace("\\", "/").simplify_path().trim_suffix("/")
		if not (atlas_root.begins_with("res://output/") or atlas_root.begins_with("res://native/crowd10k/out_c2/") or atlas_root.begins_with("res://native/crowd10k/out_c3/")):
			_test_path_error = "測試圖集只能位於 output 或 crowd10k/out_c2、out_c3 的子目錄"
			return Runtime.fail("INVALID_TEST_PATH", _test_path_error)
		TerrainArmy.EquipmentAtlas._mixed_root = atlas_root
		TerrainArmy.EquipmentAtlas.refresh_female_sources()
	return Runtime.ok()

func _save_path_guard(path: String) -> Dictionary:
	if lab != null and lab.has_meta(&"fire_lab_fixture"): return Runtime.fail("FIRE_LAB_FIXTURE", "隔離火場不覆寫正式保存；使用本頁 seed 重建")
	if not _test_path_error.is_empty():
		return Runtime.fail("INVALID_TEST_PATH", _test_path_error)
	if not crowd_test_run_id.is_empty():
		var root_path := ProjectSettings.globalize_path(save_root).simplify_path().replace("\\", "/").to_lower() + "/"
		var absolute := ProjectSettings.globalize_path(path).simplify_path().replace("\\", "/").to_lower()
		if not absolute.begins_with(root_path):
			return Runtime.fail("INVALID_TEST_PATH", "測試存讀只能使用本輪 crowd_test 目錄")
	return Runtime.ok()

func _archive_path() -> String:
	return save_root.path_join(str(lab.terrain.site.id).validate_filename() + ".json")

func _archive_live_site() -> Dictionary:
	# A controller with no bound terrain (a fresh visible window before its first
	# bind) has no live Site to publish, so there is nothing to archive. Calling
	# _archive_path() there would dereference the null terrain.
	if lab == null or lab.terrain == null: return Runtime.ok()
	return save_to(_archive_path())

func _crowd_active() -> bool:
	return lab != null and lab.get("crowd_site") != null and lab.crowd_site.active

func _capture_for_save() -> Dictionary:
	var boarding: Dictionary = vehicles.boarding_save_guard()
	if not boarding.ok: return boarding
	var captured := {}
	if _crowd_active():
		# One synchronous native sync supplies both the original actor snapshot
		# and the crowd blob. Store.save retains the full public validation.
		captured = lab.crowd_site.capture_save()
		if not captured.ok: return captured
	_capture_positions()
	if _crowd_active():
		for actor: Dictionary in lab.terrain.site.actors.values():
			if not lab.crowd_site.contains_person(int(actor.person_id)): continue
			# Continuous native coordinates are preserved; grid reservations belong only to TerrainArmy.
			actor.movement_left = 0.0
			actor.movement_from = actor.cell.duplicate()
			actor.movement = {"duration": 0.0, "elapsed": 0.0, "start": actor.position.duplicate(),
				"linear": false, "ride": false, "ride_running": false, "start_speed": 0.0, "end_speed": 0.0}
			actor.ride_speed = 0.0
		lab.terrain.site.armies.append_array(captured.rosters)
		lab.terrain.site["crowd"] = captured.section
	return Runtime.ok()

## Region checkpoint twin of the crowd tail of _capture_for_save(). It replaces,
## never appends, the crowd rosters already on the live Site, so repeated
## checkpoints keep exactly one roster per team. The cold writer is unchanged.
func _apply_region_crowd_capture(captured: Dictionary) -> void:
	for actor: Dictionary in lab.terrain.site.actors.values():
		if not lab.crowd_site.contains_person(int(actor.person_id)): continue
		actor.movement_left = 0.0
		actor.movement_from = actor.cell.duplicate()
		actor.movement = {"duration": 0.0, "elapsed": 0.0, "start": actor.position.duplicate(),
			"linear": false, "ride": false, "ride_running": false, "start_speed": 0.0, "end_speed": 0.0}
		actor.ride_speed = 0.0
	var kept: Array = []
	for roster: Variant in lab.terrain.site.armies:
		if roster is Dictionary and not bool(roster.get("crowd", false)): kept.append(roster)
	kept.append_array(captured.rosters)
	lab.terrain.site["armies"] = kept
	lab.terrain.site["crowd"] = captured.section

func save_to(path: String) -> Dictionary:
	var path_guard := _save_path_guard(path)
	if not path_guard.ok: return path_guard
	var guard := supply_save_guard(false, true)
	if not guard.ok: return guard
	var captured := _capture_for_save()
	if not captured.ok: return captured
	# The synchronous capture and Store validation share the same original native
	# state. Store still proves the full blob and checks every public save guard.
	var native_candidate: Variant = lab.crowd_site.crowd if _crowd_active() else null
	var result: Dictionary
	if region_slot != null and lab.terrain.parameters.get("fixed_base") is Dictionary:
		result = _checkpoint_ship_journey() if not _ship_journey.is_empty() else region_slot.save_site(lab.terrain)
		if result.ok: save_path = str(result.get("path", region_slot.site_path(_current_region_site())))
	else:
		result = Store.save(lab.terrain, path, native_candidate, true)
	if result.ok:
		lab._fire_unsaved = false
		_auto_save_blocked = false
	return result

func save_current() -> void:
	show_result(save_to(save_path))

func archive_before_replace() -> bool:
	if lab.terrain == null or lab.terrain.site.is_empty(): return true
	var result := save_to(_archive_path())
	show_result(result)
	if result.ok: _refresh_saved_sites()
	return bool(result.ok)

func load_current() -> void:
	await _load_path(save_path)

func _load_compatible_site(path: String) -> Dictionary:
	var slot_path := region_slot.folder.replace("\\", "/").trim_suffix("/") + "/" if region_slot != null else ""
	var selected_slot_path := not slot_path.is_empty() and path.replace("\\", "/").begins_with(slot_path)
	var result: Dictionary = region_slot.load_compatible_site(path) if selected_slot_path else Store.load_site(path, Callable(), clampi(OS.get_processor_count(), 1, 8))
	if result.ok:
		var selected_restore: bool = result.data.site.has("region_snapshot")
		if selected_restore and not selected_slot_path: return Runtime.fail("INVALID_SELECTED_REGION_RESTORE", "原完整快照只由目前存檔槽選定檔恢復")
		var guard: Dictionary = Store.validate_region_snapshot(result.data, {}) if selected_restore else lab.exchange_snapshot_guard(result.data)
		if not guard.ok: return guard
	return result

func _load_failure(result: Dictionary) -> Dictionary:
	_auto_save_blocked = true
	result["message"] = str(result.get("message", result.get("code", "載入失敗"))) + "；自動保存已暫停，原檔保留"
	return result

func load_from(path: String) -> Dictionary:
	if not _ground_crossing.is_empty(): return _load_failure(Runtime.fail("BUSY", "先完成或取消原跨界候選"))
	var replacement := region_replacement_guard()
	if not replacement.ok: return _load_failure(replacement)
	var fire_guard := Store.fire_event_guard(lab.terrain)
	if not fire_guard.ok: return _load_failure(fire_guard)
	var path_guard := _save_path_guard(path)
	if not path_guard.ok: return _load_failure(path_guard)
	if lab.terrain != null and float(lab.terrain.site.combat_left) > 0:
		return _load_failure(Runtime.fail("BUSY", "脫戰後才能載入"))
	var result := _load_compatible_site(path)
	var selected_restore: bool = result.ok and result.data.site.has("region_snapshot")
	if result.ok and not selected_restore and not is_instance_valid(lab.npc):
		var retired := Store.retire_default_worker(result.data)
		if not retired.ok: result = retired
	if not result.ok: return _load_failure(result)
	var work_guard := _siege_work_saved_guard(result.data)
	if not work_guard.ok: return _load_failure(work_guard)
	var prepared: Dictionary = lab.prepare_selected_region_owner_restore(result.data, region_slot) if selected_restore else lab.prepare_crowd_load(result.data, result.get("crowd_native"))
	# Only the staged CrowdSite keeps the accepted candidate. Do not expose a
	# second native owner through the public load result after this transaction.
	result.erase("crowd_native")
	if not prepared.ok: return _load_failure(prepared)
	var selected_generation := int(region_slot._marker.generation) if selected_restore else -1
	if selected_restore: result["data"] = prepared.data # Canonical readback and its private ticket stay together.
	var transport_guard: Dictionary = lab.fire_transport_bind_guard(result.data,
		is_instance_valid(prepared.get("crowd_site")) or lab.crowd_startup_requested)
	if not transport_guard.ok:
		if is_instance_valid(prepared.get("crowd_site")): prepared.crowd_site.free()
		if selected_restore: lab._region_owner_bind_tickets.erase(str(prepared.region_bind_token))
		return _load_failure(transport_guard)
	# A selected reload keeps this exact published generation; ordinary replacement still archives.
	if not selected_restore and path != save_path and lab.terrain != null and not lab.terrain.site.is_empty():
		var archive := save_to(_archive_path())
		if not archive.ok:
			if is_instance_valid(prepared.get("crowd_site")): prepared.crowd_site.free()
			return _load_failure(archive)
	if selected_restore:
		var admission: Dictionary = lab._region_bind_ticket_admission(result.data, prepared)
		if not admission.ok:
			lab._region_owner_bind_tickets.erase(str(prepared.region_bind_token))
			return _load_failure(admission)
	_cancel_facing_move()
	_clear_formation_candidate()
	lab.bind_terrain(result.data, prepared)
	vehicles.bind_loaded_convoys() # S5: the record check ran in prepare_load; this resets the previous Site's convoy latches
	var bound: Dictionary = lab.region_bind_receipt(result.data)
	if not bound.get("complete", false) or selected_restore and (int(bound.get("generation", -1)) != selected_generation
			or str(bound.get("owner", "")) != str(region_slot.control.active_site_id) or str(bound.get("mode", "")) != "live"):
		if is_instance_valid(prepared.get("crowd_site")): prepared.crowd_site.free()
		if selected_restore: lab._region_owner_bind_tickets.erase(str(prepared.region_bind_token))
		return _load_failure(Runtime.fail("INVALID_CROWD", "載入未提交；保留目前場景"))
	_auto_save_blocked = false
	return result

func _load_path(path: String) -> void:
	var fire_guard := Store.fire_event_guard(lab.terrain)
	if not fire_guard.ok:
		show_result(_load_failure(fire_guard))
		return
	if DisplayServer.get_name() != "headless":
		var path_guard := _save_path_guard(path)
		if not path_guard.ok: show_result(_load_failure(path_guard)); return
		if lab.terrain != null and float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: show_result(_load_failure(Runtime.fail("BUSY", "脫戰後才可載入"))); return
		var candidate := _load_compatible_site(path)
		if not candidate.ok: show_result(_load_failure(candidate)); return
		var original_data: TerrainData = lab.terrain
		# This read has no active owner. Drop its temporary native validation object
		# before capture; load_from rereads/validates the actual file before commit.
		candidate.erase("crowd_native")
		if not await prepare_existing_siege_work_assets(candidate.data):
			show_result(_load_failure(Runtime.fail("MISSING_ASSET", "已存原操作班工作動作準備未完成；未替換現場")))
			return
		if not is_same(lab.terrain, original_data): show_result(_load_failure(Runtime.fail("STALE_SOURCE"))); return
	show_result(load_from(path))

func _refresh_saved_sites() -> void:
	if saved_sites == null:
		return
	saved_sites.clear()
	saved_sites.add_item("已保存地圖")
	var folder := DirAccess.open(save_root)
	if folder == null:
		return
	for file: String in folder.get_files():
		if not file.ends_with(".json") or file == "current.json":
			continue
		var path := save_root.path_join(file)
		var decoded := Store._read(path)
		if decoded.ok:
			saved_sites.add_item("%s · seed %d · 第%d日" % [TerrainPreset.NAMES[int(decoded.payload.preset)], int(decoded.payload.seed), floori(float(decoded.payload.state.get("minute", 0)) / 1440) + 1])
			saved_sites.set_item_metadata(saved_sites.item_count - 1, path)

func _request_exit(next_scene: String = "") -> void:
	if is_instance_valid(_exit_dialog):
		_exit_dialog.popup_centered()
		_exit_dialog.get_cancel_button().grab_focus()
		return
	var supply_guard := supply_save_guard(false, false, true)
	if not supply_guard.ok:
		show_result(supply_guard)
		_confirm_unsaved_exit(str(supply_guard.message), next_scene)
		return
	if float(lab.terrain.site.combat_left) > 0:
		_confirm_unsaved_exit("戰鬥尚未結束，目前不能安全保存。", next_scene)
		return
	var destination := _archive_path() if _auto_save_blocked else save_path
	var result := save_to(destination)
	if result.ok:
		_leave_site(next_scene)
	else:
		show_result(result)
		_confirm_unsaved_exit(str(result.message), next_scene)

# Quit, or hand the window to another scene with the tree unpaused and the
# ordinary close-to-quit behaviour that this controller disabled restored.
func _leave_site(next_scene: String) -> void:
	if lab.audio_view != null:
		lab._audio_live_requested = false
		lab.audio_view.set_active(false)
	if _boot_request.is_empty(): _record_world()
	if next_scene.is_empty():
		get_tree().quit()
		return
	get_tree().paused = false
	get_tree().auto_accept_quit = true
	# Deferred: the request usually comes from a click inside an embedded tool
	# Window; removing the scene mid-dispatch leaves that Window's viewport
	# handling input outside the tree ("!is_inside_tree()").
	get_tree().change_scene_to_file.call_deferred(next_scene)

func _confirm_unsaved_exit(reason: String, next_scene: String = "") -> void:
	# Never wait forever for two autonomous armies to disengage, or silently
	# discard their unsaved state. Use the native modal and an explicit choice.
	var data: TerrainData = lab.terrain
	var site_was_paused := bool(data.site.paused)
	var tree_was_paused := get_tree().paused
	_exit_pending = true
	lab._clear_movement_input()
	data.site["paused"] = true
	get_tree().paused = true
	var dialog := ConfirmationDialog.new()
	_exit_dialog = dialog
	dialog.name = "ConfirmUnsavedExit"
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.title = "尚未保存，確定離開？"
	dialog.dialog_text = reason + "\n\n不保存離開會遺失上次保存後的進度，不會覆寫存檔。"
	dialog.ok_button_text = "不保存離開"
	dialog.cancel_button_text = "取消，返回場景"
	lab.get_node("SiteUI").add_child(dialog)
	dialog.confirmed.connect(func() -> void: _leave_site(next_scene))
	dialog.canceled.connect(func() -> void:
		dialog.hide()
		_exit_dialog = null
		_exit_pending = false
		data.site["paused"] = site_was_paused
		get_tree().paused = tree_was_paused
		dialog.queue_free())
	dialog.popup_centered()
	dialog.get_cancel_button().grab_focus()

func update_ui(refresh_combat_window: bool = true) -> void:
	if lab.restore_only: return
	_update_region_travel_status()
	_update_region_party_map_resume_button()
	if _ui_control_id != lab.controlled_person_id(): invalidate_ui_context()
	if lab.terrain == null or details == null:
		return
	_refresh_crowd_split_ui()
	if formal_windows.has("family") and formal_windows.family.visible: _tech_window.refresh()
	if formal_windows.has("construction") and formal_windows.construction.visible:
		_refresh_settlement_engineering_controls()
		_refresh_irrigation_controls()
	fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	message.tooltip_text = message.text
	if _equipment_sync.is_valid() and is_instance_valid(_equipment_dialog) and _equipment_dialog.visible:
		_equipment_sync.call()
	if _team_equipment_sync.is_valid() and is_instance_valid(_team_equipment_dialog) and _team_equipment_dialog.visible:
		_team_equipment_sync.call()
	if _test_page_visible("logistics") and _vehicle_forms.has("test"):
		_update_vehicle_status(_vehicle_forms.test)
	var data: TerrainData = lab.terrain
	var worker_assignment := _selected_worker_assignment()
	assign_worker_button.disabled = not worker_assignment.ok
	assign_worker_button.tooltip_text = str(worker_assignment.message)
	tool_status_label.text = "工具：測試放置" if lab.test_placement_enabled else "工具：" + MODES[modes.selected]
	legend.text = "條件 0–100：紅色低、黃色中、綠色高" if view.view_mode in [2, 3, 5] else ("藍色：取水服務可達；褐色：尚未服務" if view.view_mode == 4 else "")
	legend.visible = not legend.text.is_empty()
	var simulation_speed := float(lab.simulation_speed)
	var speed_text := String.num(simulation_speed, 1)
	clock_label.text = Runtime.date_text(data) + ("\n戰鬥：1 秒 = 遊戲 %s 秒 · 脫戰 %.0f 秒" % [speed_text, float(data.site.combat_left)] if float(data.site.combat_left) > 0 else "\n和平：1 秒 = 遊戲 %s 分鐘" % speed_text)
	speed_label.text = "%s×" % speed_text
	pause_button.text = "繼續" if bool(data.site.paused) else "暫停"
	var condition := Env.land(data, selected)
	details.text = "選取 %s\n農耕 %d  ·  牧地 %d  ·  淡水 %d  ·  建設 %d\n%s" % [selected, condition.farm, condition.pasture, condition.water, condition.build, "；".join(condition.reasons)]
	var containers: Array = data.ground_loot_at.get(data.index(selected), [])
	if not containers.is_empty():
		details.text += "\n現場有 %d 個實物容器；可查看並選擇取物。" % containers.size()
	var job := person_actions.job_for(person_executor_id)
	if not job.is_empty():
		if job.kind == "equipment" and job.paused == "PREPARING_ATLAS":
			details.text += "\n人物 #%d 作業：正在準備共用裝備外觀；完成後開始五秒換裝，可取消" % person_executor_id
		elif job.kind == "capture" and job.paused == "PREPARING_ATLAS":
			details.text += "\n人物 #%d 作業：正在準備被拘押者卸裝後的共用外觀；完成後開始拘束，可取消" % person_executor_id
		else:
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
		var resource_name: String = str(Env.WILDLIFE_NAMES[Env.resource_species(resource)]) if int(resource.kind) == Env.Kind.WILDLIFE else str(Env.NAMES[int(resource.kind)])
		details.text += "\n%s · %s" % [resource_name, "已勘探" if bool(resource.discovered) else "待勘探，儲量未知"]
		if bool(resource.discovered):
			details.text += "\n%s %d / %d · 一批 %.0f 遊戲分" % ["本分可取" if int(resource.kind) == Env.Kind.SALT else "存量", int(resource.remaining) - (int(resource.get("used", 0)) if int(resource.get("used_minute", -1)) == int(data.site.minute) else 0), resource.capacity, Env.WORK_MINUTES[int(resource.kind)]]
	_update_ecology_ui()
	manual_capture_button.disabled = Runtime.capturable_species(Env.resource(data, source_key)).is_empty()
	var selected_pasture: Dictionary = data.site.features.get(feature_key, {})
	stock_pasture_button.disabled = str(selected_pasture.get("kind", "")) not in ["pasture", "horse_ranch"] or str(selected_pasture.get("stage", "")) != "complete"
	if not feature_key.is_empty() and data.site.features.has(feature_key):
		var feature: Dictionary = data.site.features[feature_key]
		details.text += "\n%s：%s" % [_building_name(feature), feature.status]
		if str(feature.kind) == "barracks": details.text += "\n" + Runtime.barracks_type_description(feature)
		if feature.has("species"):
			details.text += "\n%s %d 頭 · 牧場容量 %d 頭 · 草地承載 %d 頭" % [Env.ITEM_NAMES[str(feature.species)], int(feature.residents), Runtime.livestock_capacity(data, feature), Runtime.grazing_capacity(data, feature.cells)]
		var water: Dictionary = data.site.water_status.get(feature_key, {})
		if float(water.get("demand", 0)) > 0:
			details.text += "\n供水 %.2f / %.2f 單位／分" % [water.supplied, water.demand]
		if str(feature.kind) in ["well", "intake"]:
			details.text += "\n%s · 共用來源上限 %d／分\n沿可行路線服務 14 格" % ["地下水" if str(feature.kind) == "well" else "淡水水體", 2 if str(feature.kind) == "well" else 6]
		var definition := Runtime.feature_recipe(feature)
		if str(feature.stage) == "complete" and definition.has("cycle"):
			details.text += "\n%s → %s\n批次 %.1f / %.0f 分" % [Runtime.items_text(definition.input), Runtime.items_text(definition.output), feature.production, definition.cycle]
			if int(feature.get("layout_version", 0)) == 1 and str(feature.kind) in Runtime.FARM_KINDS + Runtime.PASTURE_KINDS:
				var production := Runtime.feature_production_info(data, feature_key)
				details.text += "\n工作人數 %d · 作業覆蓋 %d／%d 格" % [int(production.workers), int(production.served_cells), int(production.land_cells)]
	view.preview_entrance = Vector2i(-1, -1)
	view.selection_valid = true
	_sync_building_actions()
	if modes.selected == 5:
		var preview := Runtime.preview_resize(data, feature_key, build_cells, reserves_cell) if building_resize else Runtime.preview_build(data, _building_kind(), build_cells, reserves_cell, _building_options())
		view.selection_valid = bool(preview.ok)
		details.text += "\n建設預覽：" + ("材料 " + Runtime.items_text(preview.cost) if preview.ok else str(preview.message))
		var center_probe := {"kind": "settlement_center", "layout_version": 1, "quarter": building_direction.selected}
		if preview.ok and not building_resize and _building_kind() == "settlement_center" and not view.building_art_available(center_probe):
			view.selection_valid = false
			details.text += "\n缺正式美術資產 %s；不以占位圖替代，暫不能建立聚落" % view.building_art_key(center_probe)
			view.set_building_preview({})
		elif preview.ok:
			view.preview_entrance = data.cell_from_index(int(preview.entrance))
			details.text += "\n入口 %s · 清理 %d 處\n施工 %.0f 遊戲分" % [data.cell_from_index(int(preview.entrance)), preview.get("clearing", []).size(), float(preview.work)]
			var draft: Dictionary = data.site.features[feature_key].duplicate(true) if building_resize else preview.options.duplicate(true)
			draft.merge({"kind": _building_kind(), "cells": build_cells.duplicate(), "entrance": int(preview.entrance), "stage": "planned", "solid": bool(Runtime.FEATURES[_building_kind()].solid), "level": int(preview.get("level", 0))}, true)
			view.set_building_preview({"feature": draft, "geometry": preview.get("geometry", {}), "valid": true})
		else:
			view.set_building_preview({})
	else:
		view.set_building_preview({})
	view.queue_redraw()
	var controlled := person_actions._person(lab.controlled_person_id())
	var controlled_cargo: Dictionary = controlled.get("cargo", {})
	var controlled_fatigue := float(person_actions._body_get(controlled, "fatigue")) if not controlled.is_empty() else 0.0
	var controlled_health := "HP -- · 暈眩 --" if controlled.is_empty() else "HP %.1f · 暈眩 %.1f" % [float(controlled.hp), float(person_actions._body_get(controlled, "stun"))]
	var manual_status := "無" if str(data.site.manual.target).is_empty() else "%.1f 分" % float(data.site.manual.progress)
	var fatigue_label := "隊伍疲勞" if not controlled.is_empty() and not PersonFatigue.pool(controlled.body).is_empty() else "疲勞"
	var time_label := "騎乘耗時" if not controlled.is_empty() and int(controlled.unit) < 0 and controlled.owner.is_mounted() else "耗時"
	var controlled_label: String = lab.character.display_name if lab.controlled_person_id() == lab.character.person_id and not lab.character.display_name.is_empty() else "#%d" % lab.controlled_person_id()
	player_status_label.text = "目前控制 %s · %s\n攜帶：%s · %s %.1f／100（%s +%.1f%%） · 手動作業：%s" % [controlled_label, controlled_health, Runtime.items_text(controlled_cargo), fatigue_label, controlled_fatigue, time_label, PersonFatigue.slowdown(controlled_fatigue) * 100.0, manual_status]
	player_status_label.tooltip_text = player_status_label.text
	stock_label.text = "營地 %d / %d\n%s" % [Runtime.inventory_size(data.site.inventory), data.site.capacity, Runtime.items_text(data.site.inventory)]
	var camp_water: Dictionary = data.site.water_status.get("camp", {})
	stock_label.text += "\n營地供水 %.2f / %.2f 單位／分" % [float(camp_water.get("supplied", 0)), float(camp_water.get("demand", 0.02))]
	stock_label.text += "\n施工／作坊投入由營地統一供應；採集與成品須運回。"
	if worker_label != null and lab.npc != null:
		worker_label.text = "工人：%s\n攜帶：%s" % [str(data.site.worker.status) if bool(data.site.worker_enabled) else "已停止", Runtime.items_text(data.site.worker.cargo)]
		worker_label.text += "\n疲勞 %.1f／100 · 耗時 +%.1f%%\n停止工作並安全停留 30 遊戲秒後恢復" % [lab.npc.fatigue, PersonFatigue.slowdown(lab.npc.fatigue) * 100.0]
		worker_label.text += "\n" + ("輪休中：降至 50 後續作，保留原進度與貨物" if lab.npc.work_resting else "疲勞達 80 自動輪休；玩家不強制停工")
	_update_team_supply_ui()
	_update_formal_team_ui()
	_update_team_info()
	if formal_windows.transport.visible: _update_vehicle_status()
	if is_instance_valid(lab.site_test_window) and lab.site_test_window.visible: lab.site_test_window.refresh()
	if _test_page_visible("command"):
		_refresh_trial_team_choice_statuses()
	if refresh_combat_window or (is_instance_valid(combat_window) and combat_window.visible):
		_update_combat_window()
	var signature := JSON.stringify(data.site.zones)
	if signature != _zone_signature:
		_zone_signature = signature
		for child: Node in zones.get_children():
			zones.remove_child(child)
			child.queue_free()
		for index: int in range(data.site.zones.size()):
			var zone: Dictionary = data.site.zones[index]
			var toggle := CheckButton.new()
			toggle.text = "%d · %s · %d 格" % [index + 1, {"harvest": "採集", "capture": "活捉馬羊", "clear": "清理", "survey": "勘探", "construct": "施工", "operate": "生產"}.get(str(zone.action), "工作"), zone.cells.size()]
			toggle.button_pressed = bool(zone.active)
			toggle.toggled.connect(func(enabled: bool) -> void:
				zone["active"] = enabled
				if not enabled and int(data.site.worker.zone) == index:
					data.site.worker.target = ""
					data.site.worker.mode = "idle"
					if lab.npc != null:
						lab.npc.issue_command(TerrainTestNPC.Command.STOP)
				data.environment_revision += 1)
			zones.add_child(toggle)

func _selected_people() -> Array[int]:
	var identities: Array[int] = []
	var native_active := _crowd_active()
	if native_active:
		for crowd_owner in lab.crowd_site.person_owners():
			for index: int in crowd_owner.combat_units:
				var values: PackedFloat64Array = lab.crowd_site.crowd.get_soldier_state(index)
				if values.size() > 15 and Vector2i(floori(values[14]), floori(values[15])) == selected:
					identities.append(crowd_owner.combat_identity(index))
	for actor: TerrainTestCharacter in lab.combat_actors:
		if native_active and lab.crowd_site.contains_person(actor.person_id):
			continue
		if actor.terrain_cell == selected:
			identities.append(actor.person_id)
	for team: TerrainArmy in lab.combat_armies:
		for index in range(team.combat_units.size()):
			if native_active and lab.crowd_site.contains_person(team.combat_identity(index)):
				continue
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

func _open_logistics(host: Window = null) -> void:
	var ui_context := str(lab.controlled_person_id())
	if _existing_dialog("logistics", ui_context, host): return
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
			targets.add_item("隊伍 #%d · 陣營 %s" % [team.team_id, _faction_label(team.faction_id)])
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
	for vehicle: Dictionary in original_data.site.get("vehicles", {}).values():
		if SiteVehicleTransport.is_ship(vehicle):
			sources.add_item("船 #%s 原貨艙食品（尚非共有糧）" % str(vehicle.id))
			sources.set_item_metadata(sources.item_count - 1, {"kind": "vehicle", "vehicle_id": str(vehicle.id)})
	for key: String in original_data.site.get("ground_loot", {}):
		var container: Dictionary = original_data.site.ground_loot[key]
		var food := float(container.get("open_rations", 0.0))
		for kind: String in Sustain.FOODS:
			food += int(container.cargo.get(kind, 0))
		if food > 0.0:
			var place := "船 #%s" % str(container.vehicle_id) if container.has("vehicle_id") else "格 %s" % str(original_data.cell_from_index(int(container.cell)))
			sources.add_item("物資包 #%s · 原物主 #%d · %s" % [key, int(container.original_owner), place])
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
	_label(column, "岸上交糧：兩位原代表须在原可達接觸點停止。船岸裝卸須停船、無船內作業，\n並靠合法岸格；船員只取本船糧，船船交糧須先卸岸。來源隊共有糧須其指揮權。\n船貨艙食品須實際交付才成為共有糧；獨立人物用原搜刮面板取回自己的食物。", 14)
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
			var person := _supply_person(identity)
			var place := ""
			if not person.is_empty():
				var ship := vehicles.ship_for_person(identity)
				place = " · 船 #%s" % str(ship.id) if not ship.is_empty() else " · 岸格 %s" % str(person.cell)
			choice.add_item("原人物 #%d%s%s" % [identity, place, "（目前不可行動）" if not team.combat_can_act(index) else ""])
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
				var person := _supply_person(original_control_id)
				if not person.is_empty():
					inventory = person.cargo
					opened = float(original_data.site.get("person_supply", {}).get(str(original_control_id), {}).get("open_rations", 0.0))
			"depot": inventory = original_data.site.inventory
			"team":
				var team: TerrainArmy = find_team.call(int(spec.team_id))
				var endpoint := _team_food_endpoint(team, int(spec.get("representative_id", -1)))
				if not endpoint.is_empty():
					inventory = endpoint.inventory
					opened = float(endpoint.opened.open_rations)
					if not str(endpoint.key).is_empty():
						title += " · 船 #%s 共有糧" % str(endpoint.key).trim_prefix("vehicle:") if str(endpoint.key).begins_with("vehicle:") else " · 岸格 %s 共有糧" % str(original_data.cell_from_index(int(str(endpoint.key).trim_prefix("shore:"))))
			"vehicle":
				var vehicle: Dictionary = original_data.site.vehicles.get(str(spec.vehicle_id), {})
				if not vehicle.is_empty(): inventory = vehicle.cargo
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
			var item := roster.add_item("#%d · %s · HP %.0f · 疲勞 %.1f · 原行囊 %d 件" % [identity, "專職後勤（6）" if bool(row.get("logistics", false)) else "普通搬運（3）", team.combat_hot_get(index, &"hp"), PersonFatigue.read(row), Runtime.inventory_size(row.cargo)])
			roster.set_item_metadata(item, identity)
			if kept.has(identity):
				roster.select(item, false)
		var entry := _supply_entry(team)
		var held := 0.0 if entry.is_empty() else Sustain.rations(entry.sustain, _supply_stock(entry))
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
	source_rep.item_selected.connect(func(_index: int) -> void: refresh_stock.call())
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
	_show_dialog(dialog, "logistics", ui_context, host)

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
	var audio_data: TerrainData = lab.terrain
	var audio_ground: Vector2 = vehicles.ship_person_ground(identity) if vehicles.is_embarked(identity) else person.get("position", Vector2(-1, -1))
	var original_transfer := func() -> Dictionary:
		return Runtime.transfer_items(audio_data, person.holder, person.cargo, depot,
			audio_data.site.inventory, {}, item_ids, expected_version, int(depot.version), int(audio_data.site.capacity))
	if lab.has_method("_audio_p3_transfer"):
		return lab.call("_audio_p3_transfer", original_transfer, identity, audio_ground, {}, item_ids)
	return original_transfer.call()

func _open_equipment_inventory(identity: int = -1, host: Window = null) -> void:
	var ui_context := str(identity if identity >= 0 else lab.controlled_person_id())
	if _existing_dialog("equipment", ui_context, host): return
	var linked_executor: bool = identity >= 0
	var target_id: int = identity if linked_executor else lab.controlled_person_id()
	var person: Dictionary = person_actions._person(target_id)
	if person.is_empty():
		show_result(Runtime.fail("NO_TARGET"))
		return
	var context: Dictionary = {"person_id": target_id, "control_id": lab.controlled_person_id(), "terrain": lab.terrain,
		"holder": person.holder, "cargo": person.cargo, "depot": lab.terrain.site.depot_items,
		"stock": lab.terrain.site.inventory, "holder_version": int(person.holder.version),
		"depot_version": int(lab.terrain.site.depot_items.version), "pending": false,
		"pending_mode": "", "stale": false}
	var dialog := AcceptDialog.new()
	_equipment_dialog = dialog
	dialog.name = "EquipmentInventoryDialog"
	dialog.title = "%s #%d · 實際持物與領裝" % ["指定人物" if linked_executor else "玩家本人", target_id]
	dialog.min_size = Vector2i(580, 520)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	_label(column, "換裝 5 遊戲秒，完成才交換實物。非交戰、停止且可行動；\n改標準不會直接換裝，缺料不生成替代品。", 16)
	var slots := _label(column, "", 15)
	var status := _label(column, "", 15)
	status.name = "EquipmentStatus"
	_label(column, "沒有行囊替換品時，可由主面板的營地領取、現場搜刮或弓弩手作取得原實物。", 14)
	var items := ItemList.new()
	items.name = "OwnedEquipmentItems"
	items.select_mode = ItemList.SELECT_MULTI
	items.custom_minimum_size = Vector2(500, 180)
	column.add_child(items)
	var panel_callbacks: Dictionary = {}
	var current_scope := func() -> bool:
		if bool(context.stale) or lab.controlled_person_id() != int(context.control_id) or lab.terrain != context.terrain or linked_executor and person_executor_id != target_id:
			return false
		var current: Dictionary = person_actions._person(target_id)
		return not current.is_empty() and is_same(current.holder, context.holder) and is_same(current.cargo, context.cargo) and is_same(lab.terrain.site.depot_items, context.depot) and is_same(lab.terrain.site.inventory, context.stock) and int(context.holder.version) == int(context.holder_version) and int(context.depot.version) == int(context.depot_version)
	var show := func(result: Dictionary) -> void:
		status.text = str(result.get("message", "")) if bool(result.get("ok", false)) else "%s：%s" % [str(result.get("code", "FAILED")), str(result.get("message", ""))]
		show_result(result)
	var wear := _button(column, "玩家穿戴選取的自有物品", "WearOwnedItem", func() -> void:
		if not current_scope.call():
			show.call(Runtime.fail("STALE", "原人物／持物／營地已變更，請重新開啟裝備面板"))
			return
		if items.get_selected_items().is_empty(): return
		var choice: Dictionary = items.get_item_metadata(items.get_selected_items()[0])
		var result: Dictionary = equipment_orders.begin_personal(target_id, str(choice.slot), str(choice.id))
		if result.ok:
			context["pending"] = true
			context["pending_mode"] = "personal"
		show.call(result))
	var remove := _button(column, "玩家卸下選取裝備至原行囊", "RemoveOwnedItem", func() -> void:
		if not current_scope.call():
			show.call(Runtime.fail("STALE", "原人物／持物／營地已變更，請重新開啟裝備面板"))
			return
		if items.get_selected_items().is_empty(): return
		var choice: Dictionary = items.get_item_metadata(items.get_selected_items()[0])
		if context.holder.equipped.get(str(choice.slot), "") != str(choice.id):
			show.call(Runtime.fail("INVALID", "所選物品目前在行囊，沒有穿戴"))
			return
		var result: Dictionary = equipment_orders.begin_personal(target_id, str(choice.slot), "")
		if result.ok:
			context["pending"] = true
			context["pending_mode"] = "personal"
		show.call(result))
	var deposit := _button(column, "所選行囊實物入庫（不自動卸裝）", "DepositOwnedEquipment", func() -> void:
		if not current_scope.call():
			show.call(Runtime.fail("STALE", "原人物／持物／營地已變更，請重新開啟裝備面板"))
			return
		var selected_items: Array = []
		for row: int in items.get_selected_items():
			selected_items.append(str(items.get_item_metadata(row).id))
		var result: Dictionary = deposit_owned_equipment(target_id, selected_items, int(context.holder_version))
		if result.ok:
			context["holder_version"] = int(context.holder.version)
			context["depot_version"] = int(context.depot.version)
			panel_callbacks.refresh_items.call()
		show.call(result))
	var standards := _options(column, ["選擇此人國家的領裝標準"], "IssueStandard")
	for nation_id: String in lab.terrain.site.get("equipment_nations", {}):
		var nation: Dictionary = lab.terrain.site.equipment_nations[nation_id]
		if not EquipmentOrders._member(nation, target_id): continue
		for standard_id: String in nation.standards:
			standards.add_item(str(nation.standards[standard_id].name))
			standards.set_item_metadata(standards.item_count - 1, [nation_id, standard_id])
	if standards.item_count == 1:
		_label(column, "目前沒有此人的真實國別／標準資料；不自動授予國籍或首長職位。", 15)
	var issue := _button(column, "此人向相鄰營地領裝", "IssueEquipment", func() -> void:
		if not current_scope.call():
			show.call(Runtime.fail("STALE", "原人物／持物／營地已變更，請重新開啟裝備面板"))
			return
		if standards.selected <= 0:
			show.call(Runtime.fail("NO_AUTHORITY", "沒有選取已授權的正式標準"))
			return
		var choice: Array = standards.get_item_metadata(standards.selected)
		var result: Dictionary = equipment_orders.begin_issue(target_id, str(choice[0]), str(choice[1]))
		if result.ok:
			context["pending"] = true
			context["pending_mode"] = "issue"
		show.call(result))
	var dye := _button(column, "套用所選國別配色到現有裝備", "ApplyStandardDyes", func() -> void:
		if not current_scope.call():
			show.call(Runtime.fail("STALE", "原人物／持物／營地已變更，請重新開啟裝備面板"))
			return
		if standards.selected <= 0: return
		var choice: Array = standards.get_item_metadata(standards.selected)
		var result: Dictionary = equipment_orders.apply_standard_dyes(lab.controlled_person_id(), target_id, str(choice[0]), str(choice[1]))
		if result.ok:
			context["holder_version"] = int(context.holder.version)
			panel_callbacks.refresh_items.call()
		show.call(result))
	var cancel := _button(column, "取消此人物換裝作業", "CancelEquipmentAction", func() -> void:
		if lab.controlled_person_id() != int(context.control_id) or lab.terrain != context.terrain or linked_executor and person_executor_id != target_id:
			show.call(Runtime.fail("STALE", "原控制人物、執行者或 Site 已變更"))
			return
		var job: Dictionary = person_actions.job_for(target_id)
		if job.is_empty() or str(job.kind) != "equipment": return
		if str(job.get("order", {}).get("mode", "")) == "team_issue": # F08: same authority as the team window.
			show.call(equipment_orders.cancel_team_issue(lab.controlled_person_id(), target_id))
			return
		context["pending"] = false
		show.call(person_actions.cancel(target_id)))
	var refresh_buttons := func() -> void:
		var selected_rows: PackedInt32Array = items.get_selected_items()
		var chosen: Dictionary = items.get_item_metadata(selected_rows[0]) if not selected_rows.is_empty() else {}
		var worn: bool = not chosen.is_empty() and context.holder.equipped.get(str(chosen.slot), "") == str(chosen.id)
		var available: bool = bool(current_scope.call()) and not person_actions.is_busy(target_id)
		wear.disabled = not available or not bool(person.player) or chosen.is_empty() or worn
		remove.disabled = not available or not bool(person.player) or chosen.is_empty() or not worn
		deposit.disabled = not available or target_id != lab.controlled_person_id() or selected_rows.is_empty()
		if not deposit.disabled:
			for row: int in selected_rows:
				var row_id := str(items.get_item_metadata(row).id)
				if context.holder.equipped.values().has(row_id) or row_id == Runtime.MOUNT_GOODS:
					deposit.disabled = true
					break
		issue.disabled = not available or standards.selected <= 0
		dye.disabled = not available or standards.selected <= 0
		cancel.disabled = str(person_actions.job_for(target_id).get("kind", "")) != "equipment"
	var refresh_items := func() -> void:
		var selected_ids: Array[String] = []
		for row: int in items.get_selected_items(): selected_ids.append(str(items.get_item_metadata(row).id))
		items.clear()
		var slot_lines: Array[String] = []
		for slot: String in Runtime.EQUIPMENT_SLOTS:
			var equipped_id: String = str(context.holder.equipped.get(slot, ""))
			var record: Dictionary = context.terrain.site.item_records.get(equipped_id, {})
			var definition: Dictionary = context.terrain.site.item_definitions.get(str(record.get("definition", "")), {})
			slot_lines.append("%s：%s" % [slot, _item_label(definition) if not definition.is_empty() else "未穿戴"])
		slots.text = "\n".join(slot_lines)
		for item_id: String in context.holder.item_ids:
			var record: Dictionary = context.terrain.site.item_records.get(item_id, {})
			var definition: Dictionary = context.terrain.site.item_definitions.get(str(record.get("definition", "")), {})
			if definition.is_empty(): continue
			var row := items.add_item("%s #%s（%s）" % [_item_label(definition), item_id, "穿戴" if context.holder.equipped.values().has(item_id) else "行囊"])
			items.set_item_metadata(row, {"slot": str(definition.slot), "id": item_id})
			if selected_ids.has(item_id): items.select(row, false)
		# CAV-3: the mount slot is filled from the person's own horse goods (one generic slot row, worn with the same button).
		var horses := int(context.cargo.get("horse", 0))
		if horses > 0 and not context.holder.equipped.has(Runtime.MOUNT_SLOT):
			var horse_row := items.add_item("馬匹貨物 ×%d（坐騎槽，穿戴時取一匹）" % horses)
			items.set_item_metadata(horse_row, {"slot": Runtime.MOUNT_SLOT, "id": Runtime.MOUNT_GOODS})
			if selected_ids.has(Runtime.MOUNT_GOODS): items.select(horse_row, false)
		refresh_buttons.call()
	panel_callbacks["refresh_items"] = refresh_items
	items.multi_selected.connect(func(_row: int, _selected: bool) -> void: refresh_buttons.call())
	standards.item_selected.connect(func(_index: int) -> void: refresh_buttons.call())
	_equipment_sync = func() -> void:
		if not current_scope.call():
			context["stale"] = true
			status.text = "STALE：原人物／持物／營地已變更，請重新開啟裝備面板"
			refresh_buttons.call()
			return
		var job: Dictionary = person_actions.job_for(target_id)
		if not job.is_empty():
			if str(job.kind) != "equipment": context["pending"] = false
			elif not bool(context.pending):
				context["pending"] = true
				context["pending_mode"] = str(job.order.mode)
			status.text = "準備共用裝備外觀；原裝保留" if str(job.get("paused", "")) == "PREPARING_ATLAS" else "作業進度：%.1f／%.1f 秒 %s" % [float(job.elapsed), float(job.duration), str(job.paused)]
		elif bool(context.pending):
			status.text = "作業已停止，等待原結算結果"
		refresh_buttons.call()
	_equipment_result = func(result: Dictionary) -> void:
		if not bool(context.pending) or int(result.get("executor_id", -1)) != target_id: return
		context["pending"] = false
		if bool(result.get("ok", false)):
			var expected_depot: int = int(context.depot_version) + (1 if str(context.pending_mode) == "issue" else 0)
			if int(context.holder.version) != int(context.holder_version) + 1 or int(context.depot.version) != expected_depot:
				context["stale"] = true
				status.text = "STALE：作業完成後持物版本異常，請重新開啟核對"
			else:
				context["holder_version"] = int(context.holder.version)
				context["depot_version"] = int(context.depot.version)
				refresh_items.call()
				status.text = str(result.get("message", "換裝完成"))
		else:
			status.text = "%s：%s" % [str(result.get("code", "FAILED")), str(result.get("message", "換裝失敗"))]
		refresh_buttons.call()
	dialog.tree_exiting.connect(func() -> void:
		if _equipment_dialog == dialog:
			_equipment_dialog = null
			_equipment_sync = Callable()
			_equipment_result = Callable())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	refresh_items.call()
	_equipment_sync.call()
	_show_dialog(dialog, "equipment", ui_context, host)

func _open_equipment_standards(authority_identity: int = 0, host: Window = null) -> void:
	var ui_context := str(authority_identity if authority_identity > 0 else lab.controlled_person_id())
	if _existing_dialog("standards", ui_context, host): return
	var original_control: int = lab.controlled_person_id()
	var original_data: TerrainData = lab.terrain
	var requester_id: int = authority_identity if authority_identity > 0 else original_control
	var nation_id := ""
	for key: String in lab.terrain.site.get("equipment_nations", {}):
		if equipment_orders._can_set_standard(requester_id, lab.terrain.site.equipment_nations[key]) or EquipmentOrders.military_head(lab.terrain.site.equipment_nations[key]) == requester_id:
			nation_id = key
			break
	if nation_id.is_empty() or requester_id != original_control and not nation_id.begins_with("trial_team_"):
		show_result(Runtime.fail("NO_AUTHORITY", "選定原人物沒有可編輯的本國軍事首長職位；隊長不等於國家軍事首長"))
		return
	var npc_head := not bool(person_actions._person(requester_id, false).get("player", false))
	var dialog := AcceptDialog.new()
	dialog.name = "EquipmentStandardsDialog"
	dialog.title = "原軍事首長 #%d · 正式兵種配裝需求" % requester_id
	dialog.min_size = Vector2i(760, 480)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	var nation: Dictionary = lab.terrain.site.equipment_nations[nation_id]
	_button(column, "本國制度／具名公務…", "StandardNationOperations", func() -> void: _open_nation_operations(nation_id, dialog))
	var culture_label := _label(column, "本國文化只約束未來制式領裝；材質可混搭，外國戰利品保留。\n舊國別不猜文化；先修訂跨文化舊標準，再由真實軍事首長首次固定。", 14)
	culture_label.name = "NationCultureStatus"
	var culture_choice := _options(column, ["尚未固定：請明確選擇本國文化"], "NationCulture")
	culture_choice.set_item_metadata(0, "")
	for culture: String in EquipmentOrders.CULTURES:
		culture_choice.add_item(str(EquipmentOrders.CULTURES[culture]))
		culture_choice.set_item_metadata(culture_choice.item_count - 1, culture)
		if str(nation.get("culture", "")) == culture: culture_choice.select(culture_choice.item_count - 1)
	culture_choice.disabled = nation.has("culture")
	var standard_choice := _options(column, ["新增標準"], "EditStandard")
	for key: String in nation.standards:
		standard_choice.add_item(str(nation.standards[key].name))
		standard_choice.set_item_metadata(standard_choice.item_count - 1, key)
	var title_input := LineEdit.new()
	title_input.name = "StandardName"
	title_input.placeholder_text = "兵種／標準名稱"
	column.add_child(title_input)
	var choices := {}
	var alternatives_by_slot := {}
	var fix_culture := _button(column, "首次固定本國文化（之後不可改）", "CommitNationCulture", func() -> void:
		if lab.controlled_person_id() != original_control or lab.terrain != original_data or not is_same(lab.terrain.site.get("equipment_nations", {}).get(nation_id, {}), nation):
			show_result(Runtime.fail("STALE_SOURCE", "原人物／地圖／國別已變更，請重開標準面板"))
			return
		var result: Dictionary = equipment_orders.set_nation_culture(requester_id, nation_id, str(culture_choice.get_item_metadata(culture_choice.selected)))
		show_result(result)
		culture_label.text = str(result.message)
		if not result.ok: return
		culture_choice.disabled = true
		(dialog.find_child("CommitNationCulture", true, false) as Button).disabled = true
		for slot: String in choices:
			var choice: OptionButton = choices[slot]
			for index: int in range(choice.item_count - 1, 0, -1):
				var definition: Dictionary = original_data.site.item_definitions[str(choice.get_item_metadata(index))]
				var culture := EquipmentOrders.definition_culture(definition)
				if not culture.is_empty() and culture != str(nation.culture): choice.remove_item(index)
		standard_choice.item_selected.emit(standard_choice.selected))
	fix_culture.disabled = nation.has("culture")
	var dye_choices := {}
	var dye_enabled := {}
	_label(column, "指定原實物與五部位配色；改標準不立即染現役裝備，須另按套用。", 14)
	_label(column, "NPC 首長須選原 16 組配色；玩家首長可自由配色。", 14)
	var palette_row := HBoxContainer.new()
	column.add_child(palette_row)
	var palette_choice := _options(palette_row, [], "StandardPalette")
	palette_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for palette_id: String in Runtime.EquipmentDye.PRESETS:
		palette_choice.add_item(str(Runtime.EquipmentDye.PRESETS[palette_id].name))
		palette_choice.set_item_metadata(palette_choice.item_count - 1, palette_id)
	_button(palette_row, "NPC 選用預設" if npc_head else "載入預設（仍可自由改色）", "LoadStandardPalette", func() -> void:
		if palette_choice.selected < 0:
			show_result(Runtime.fail("NO_TARGET", "先選配色預設"))
			return
		var colors: Dictionary = Runtime.EquipmentDye.PRESETS[str(palette_choice.get_item_metadata(palette_choice.selected))].colors
		for slot: String in dye_choices:
			dye_enabled[slot].button_pressed = true
			dye_choices[slot].color = Color.from_string(colors[slot], Color.WHITE))
	for slot: String in Runtime.EQUIPMENT_SLOTS:
		var row := HBoxContainer.new()
		column.add_child(row)
		var choice := _options(row, [slot + "：不變更現役此槽"], "StandardSlot_" + slot)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for definition_id: String in lab.terrain.site.item_definitions:
			var definition: Dictionary = lab.terrain.site.item_definitions[definition_id]
			var culture := EquipmentOrders.definition_culture(definition)
			if str(definition.slot) == slot and EquipmentOrders.valid_definition(definition_id, definition) and (not nation.has("culture") or culture.is_empty() or culture == str(nation.culture)):
				choice.add_item(_item_label(definition))
				choice.set_item_metadata(choice.item_count - 1, definition_id)
		choices[slot] = choice
		alternatives_by_slot[slot] = []
		_button(row, "替代清單…", "StandardAlternatives_" + slot, func() -> void: _open_standard_alternatives(slot, choice, alternatives_by_slot))
		if slot in Runtime.EquipmentDye.SLOTS:
			var enabled := CheckBox.new()
			enabled.name = "StandardDyeEnabled_" + slot
			enabled.text = "染色"
			row.add_child(enabled)
			var picker := ColorPickerButton.new()
			picker.name = "StandardDye_" + slot
			picker.edit_alpha = false
			picker.custom_minimum_size = Vector2(48, 32)
			row.add_child(picker)
			dye_choices[slot] = picker
			dye_enabled[slot] = enabled
			enabled.disabled = npc_head
			picker.disabled = npc_head
	standard_choice.item_selected.connect(func(index: int) -> void:
		var colors: Dictionary = nation.standards[str(standard_choice.get_item_metadata(index))].get("equipment_dyes", {}) if index > 0 else {}
		for palette_index: int in range(palette_choice.item_count):
			if colors == Runtime.EquipmentDye.PRESETS[str(palette_choice.get_item_metadata(palette_index))].colors:
				palette_choice.select(palette_index)
				break
		for slot: String in dye_choices:
			dye_enabled[slot].button_pressed = colors.has(slot)
			dye_choices[slot].color = Color.from_string(colors.get(slot, "ffffffff"), Color.WHITE)
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
		if lab.controlled_person_id() != original_control or lab.terrain != original_data or not is_same(lab.terrain.site.get("equipment_nations", {}).get(nation_id, {}), nation):
			show_result(Runtime.fail("STALE_SOURCE", "原人物／地圖／國別已變更，請重開標準面板"))
			return
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
		var colors := {}
		for slot: String in dye_choices:
			if dye_enabled[slot].button_pressed: colors[slot] = (dye_choices[slot].color as Color).to_html()
		if npc_head and palette_choice.selected < 0:
			show_result(Runtime.fail("INVALID", "NPC 原軍事首長須選一組預設配色"))
			return
		var dyes: Variant = colors
		if npc_head:
			dyes = str(palette_choice.get_item_metadata(palette_choice.selected))
		show_result(equipment_orders.set_standard(requester_id, nation_id, key, title_input.text.strip_edges(), slots, dyes)))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_show_dialog(dialog, "standards", ui_context, host)

func _open_standard_alternatives(slot: String, primary: OptionButton, selections: Dictionary) -> void:
	var ui_context := slot
	if _existing_dialog("alternatives", ui_context, primary.get_window()): return
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
	_show_dialog(dialog, "alternatives", ui_context, primary.get_window())

func _choose_recovery_executor() -> void:
	var controlled := person_actions._person(lab.controlled_person_id())
	for identity: int in _selected_people():
		var person := person_actions._person(identity)
		if not person.is_empty() and not controlled.is_empty() and int(person.faction) == int(controlled.faction) and float(person.hp) > 0.0:
			person_executor_id = identity
			show_result(Runtime.ok("已選原人物 #%d；停止其他工作並到来源相鄰合法格，再指定搜刮" % identity))
			return
	show_result(Runtime.fail("NO_TARGET", "請點選原友方人物所在格"))

func _open_ranged_crafting(host: Window = null) -> void:
	var ui_context := str(person_executor_id)
	if _existing_dialog("crafting", ui_context, host): return
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
	var names := {"fire_pot": "火罐 1 件", "ballista_spares": "弩砲備件 1 件", "fire_arrow": "火箭 5 支", "bow": "弓 1 把", "crossbow": "弩 1 把", "arrow": "箭 10 支", "bolt": "弩矢 10 支", "siege_bolt": "重弩矢 1 支"}
	for key: String in Runtime.RANGED_RECIPES:
		var recipe: Dictionary = Runtime.RANGED_RECIPES[key]
		var duration := float(person_actions.ranged_craft_seconds(original_executor, key))
		var title := "%s：%s · %.1f 遊戲分鐘" % [str(names.get(key, key)), Runtime.items_text(recipe.cost), duration / 60.0]
		_button(column, title, "Craft_" + key, func() -> void:
			if person_executor_id != original_executor or lab.controlled_person_id() != original_control or lab.terrain != original_data:
				show_result(Runtime.fail("STALE_SOURCE", "原執行者或地圖已變更，請重開製作面板"))
				return
			show_result(person_actions.begin_ranged_craft(original_executor, key)))
	_label(column, "完成後用「營地領取實物／彈藥」取到本人行囊，\n再用「本人實物配裝／正式領裝」換裝；Space 攻擊所選敵人。\n工作隊伍可先指定原友方人物作為執行者。", 15)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_show_dialog(dialog, "crafting", ui_context, host)

func _open_person_inventory(depot_only: bool = false, host: Window = null) -> void:
	var ui_context := str([selected, person_executor_id, depot_only])
	if _existing_dialog("inventory", ui_context, host): return
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
	if not depot_only:
		var original_ship: Dictionary = vehicles.ship_for_person(original_executor)
		for identity: String in lab.terrain.site.get("ground_loot", {}):
			var holder: Dictionary = lab.terrain.site.ground_loot[identity]
			if not holder.has("vehicle_id"): continue
			var ground: Vector2 = vehicles.ship_loot_ground(holder)
			if str(original_ship.get("id", "")) != str(holder.vehicle_id) and Vector2i(floori(ground.x / TerrainRenderer.CELL_PIXELS), floori(ground.y / TerrainRenderer.CELL_PIXELS)) != selected: continue
			sources.append({"kind": "ground", "id": identity, "label": "船上遺物 #%s · 船 #%s · 原物主 #%d" % [identity, str(holder.vehicle_id), int(holder.original_owner)]})
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
	_show_dialog(dialog, "inventory", ui_context, host)

func _open_ransom(target_id: int, source_window: Window = null) -> void:
	var ui_context := str([target_id, person_executor_id])
	if _existing_dialog("ransom", ui_context, source_window): return
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
	_show_dialog(dialog, "ransom", ui_context, source_window)

## R4b-2 UI: nation treasury, ceilings and payer-side authorization (no payment, no release).
func _nation_ransom_status_text(nation: Dictionary) -> String:
	var record: Dictionary = nation.get("ransom_data", EquipmentOrders.RansomData.empty_record())
	var treasury := "未綁定國庫" if record.treasury.is_empty() else "國庫：倉庫 %s（硬幣仍在原倉）" % str(record.treasury.feature_id)
	var authority := ("已授權付款（授權人 #%d）" % int(record.policy.authorized_by)) if bool(record.policy.authorized) else "未授權付款"
	return "%s\n%s\n每人上限 %d · 每日上限 %d · 準備金 %d" % [treasury, authority,
		int(record.policy.per_person), int(record.policy.daily), int(record.policy.reserve)]

func _open_nation_ransom(nation_id: String, source_window: Window = null) -> void:
	var controlled_id: int = lab.controlled_person_id()
	var ui_context := str([nation_id, controlled_id])
	if _existing_dialog("nation_ransom", ui_context, source_window): return
	var nations: Dictionary = lab.terrain.site.get("equipment_nations", {})
	if not nations.has(nation_id) or not nations[nation_id] is Dictionary or not nations[nation_id].has("offices"):
		show_result(Runtime.fail("NO_TARGET", "須為已建制的國家"))
		return
	var nation: Dictionary = nations[nation_id]
	var record: Dictionary = nation.get("ransom_data", EquipmentOrders.RansomData.empty_record())
	var dialog := AcceptDialog.new()
	dialog.name = "NationRansomDialog"
	dialog.title = "國家贖金：%s" % nation_id
	var column := VBoxContainer.new()
	dialog.add_child(column)
	var status := _label(column, _nation_ransom_status_text(nation), 16)
	status.name = "NationRansomStatus"
	_label(column, "付款方：本國贖務官授權。拘押方同意與實物付款於後續階段才生效；本步不移動硬幣，也不解除拘押。", 15)
	var faction := int(nation.get("faction_id", -1))
	var features: Dictionary = lab.terrain.site.get("features", {})
	var stocks: Dictionary = lab.terrain.site.get("stockpiles", {})
	var warehouses: Array[String] = []
	var keys: Array = features.keys()
	keys.sort()
	for key: Variant in keys:
		var feature: Dictionary = features[key]
		if str(feature.get("kind", "")) == "warehouse" and str(feature.get("stage", "")) == "complete" \
			and int(feature.get("owner_faction", -1)) == faction and stocks.has(key): warehouses.append(str(key))
	var choice := _options(column, warehouses, "NationRansomWarehouse")
	_button(column, "綁定所選倉庫為國庫", "NationRansomBind", func() -> void:
		if choice.selected < 0 or choice.selected >= warehouses.size():
			show_result(Runtime.fail("NO_TARGET", "沒有可綁定的完整本國倉庫"))
			return
		show_result(equipment_orders.bind_nation_treasury(lab.controlled_person_id(), nation_id, warehouses[choice.selected]))
		dialog.queue_free())
	var per := SpinBox.new()
	per.name = "NationRansomPerPerson"
	per.min_value = 1
	per.max_value = 35
	per.value = int(record.policy.per_person)
	column.add_child(per)
	var daily := SpinBox.new()
	daily.name = "NationRansomDaily"
	daily.min_value = 1
	daily.max_value = 1000000
	daily.value = int(record.policy.daily)
	column.add_child(daily)
	var reserve := SpinBox.new()
	reserve.name = "NationRansomReserve"
	reserve.min_value = 0
	reserve.max_value = 1000000
	reserve.value = int(record.policy.reserve)
	column.add_child(reserve)
	_button(column, "設定贖金上限", "NationRansomSetPolicy", func() -> void:
		show_result(equipment_orders.set_nation_ransom_policy(lab.controlled_person_id(), nation_id, int(per.value), int(daily.value), int(reserve.value)))
		dialog.queue_free())
	var authorized := bool(record.policy.authorized)
	_button(column, "撤銷本國付款授權" if authorized else "授權本國付款（僅授權，不付款）", "NationRansomAuthorize", func() -> void:
		show_result(equipment_orders.authorize_nation_ransom(lab.controlled_person_id(), nation_id, not authorized))
		dialog.queue_free())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_show_dialog(dialog, "nation_ransom", ui_context, source_window)

static func _initial_uniform(appearance: Dictionary, faction_id: int) -> Dictionary:
	var uniform := appearance.duplicate(true)
	# An explicitly authored finish, including an empty one, is not a missing default.
	if uniform.has("equipment_dyes"): return uniform
	var palette: Dictionary = Runtime.EquipmentDye.PRESETS[EquipmentOrders.npc_palette_id(faction_id)].colors
	var dyes := {}
	for slot: String in palette:
		if uniform.parts.get(slot, "none") != "none": dyes[slot] = palette[slot]
	uniform["equipment_dyes"] = dyes
	return uniform

func initialize_team_items(team: Variant) -> void:
	if not team is TerrainArmy:
		assert(_crowd_active() and lab.crowd_site.person_owners().has(team))
		for index: int in team.combat_units:
			var person: Dictionary = team.person(index, false)
			var identity: int = team.combat_identity(index)
			var appearance: Dictionary = team.combat_hot_get(index, &"appearance", {})
			if not team.actors.has(index) and person.holder.is_empty():
				appearance = _initial_uniform(appearance, team.faction_id)
				team.combat_hot_set(index, &"appearance", appearance)
			var seeded := Runtime.seed_person_equipment(lab.terrain, person.holder, identity, appearance)
			if not seeded.ok:
				show_result(seeded)
				continue
			reconcile_cape_roles([identity])
			equipment_changed(identity)
			if float(person.hp) <= 0.0 and not bool(team.combat_hot_get(index, &"loot_settled", false)):
				_person_died(identity)
		return
	if not team.combat_enabled:
		return
	for index in range(team.combat_units.size()):
		var unit: Dictionary = team.combat_units[index]
		if not unit.has("appearance"):
			var presenter: Variant = team._unit_editor(index)
			unit["appearance"] = presenter.capture_appearance() if team._uses_live_presenter(index) and presenter != null else (TerrainArmy.EquipmentAtlas.female_appearance() if str(unit.get("visual_role", "")).begins_with("female") else TerrainArmy._combat_bake.manifest.appearance.duplicate(true))
		if not unit.has("item_state"):
			unit["item_state"] = {}
			# A newly created soldier receives an explicit initial uniform finish.
			# Existing item records and faction changes never silently repaint gear.
			var uniform := _initial_uniform(unit.appearance, team.faction_id)
			if team._uses_live_presenter(index) or team.supports_equipment_recipe(uniform):
				unit["appearance"] = uniform
		if not unit.has("cargo"):
			unit["cargo"] = {}
		var initialized := Runtime.seed_person_equipment(lab.terrain, unit.item_state, team.combat_identity(index), unit.appearance)
		if not initialized.ok:
			show_result(initialized)
			continue
		reconcile_cape_roles([team.combat_identity(index)])
		equipment_changed(team.combat_identity(index))
		if team._uses_live_presenter(index):
			var live: Variant = team._unit_editor(index)
			if live != null:
				live.equipment_dye_request = _request_person_dye.bind(team.combat_identity(index))
				live.part_selection_request = _request_person_equipment.bind(team.combat_identity(index))
				var original_body := int(unit.appearance.body)
				live.body_selection_request = func(_requested: int) -> int: return original_body
		if float(team.combat_hot_get(index, &"hp")) <= 0.0 and not bool(unit.get("loot_settled", false)):
			_person_died(team.combat_identity(index))

func before_clear_team_items() -> Dictionary:
	var guard := supply_save_guard()
	if not guard.ok:
		return guard
	var holders: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		var vehicle_guard: Dictionary = vehicles.can_park_team(team)
		if Runtime.ship_build_uses_team(lab.terrain, team.team_id) or Runtime.ship_repair_uses_team(lab.terrain, team.team_id):
			return Runtime.fail("BUSY", "原隊仍有已付造船批次；先完成或明示取消，不能留下失去所屬的船")
		if not vehicle_guard.ok:
			return vehicle_guard
		var supply := _supply_entry(team)
		if int(supply.get("version", 0)) == 3:
			for key: String in supply.locations:
				var stock: Dictionary = supply.locations[key]
				if key.begins_with("vehicle:") and Sustain.rations(stock, stock.inventory) > Sustain.EPS:
					return Runtime.fail("BUSY", "清隊前先將船上共有糧實際卸到合法岸格，不能隨船改所屬而遺失物資")
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
	for team: TerrainArmy in lab.combat_armies:
		vehicles.park_team(team)
	return Runtime.ok("測試人物退場；全部實物仍留在原格，既有遺物不變")

func person_appearance(identity: int) -> Dictionary:
	if _crowd_active() and lab.crowd_site.contains_person(identity):
		return lab.crowd_site._appearance(identity)
	return _equipment_appearances.get(identity, {})

func person_appearance_batch(query: Callable) -> Dictionary:
	# Borrow the same owner publication only for the exact pure query. Replaced
	# callbacks must still run individually, including any observable effects.
	return _equipment_appearances if query == person_appearance else {}

static func _freeze_appearance(value: Variant) -> void:
	# Published presentation snapshots are replaced on equipment_changed, never
	# mutated. Freeze nested containers too; Godot's read-only flag is shallow.
	if value is Dictionary:
		for child: Variant in value.values(): _freeze_appearance(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: _freeze_appearance(child)
		value.make_read_only()

func _person_has_duty(identity: int) -> bool:
	return person_actions.is_busy(identity) or person_actions.is_guarding(identity) or work_team.is_assigned(identity) or _is_delivering_person(identity) or vehicles.is_operator(identity)

func _open_team_equipment(team: TerrainArmy = null, trial: bool = false, host: Window = null) -> void:
	if team == null:
		team = lab.player_army()
	var ui_context := str([team.team_id if team != null else -1, trial])
	if _existing_dialog("team_equipment", ui_context, host): return
	if team == null or not team.has_army():
		show_result(Runtime.fail("NO_TARGET", "請先選擇已部署的原隊伍"))
		return
	var original_data: TerrainData = lab.terrain
	var original_team_id: int = team.team_id
	var original_control: int = lab.controlled_person_id()
	var dialog := AcceptDialog.new()
	dialog.name = "TeamEquipmentDialog"
	dialog.title = "原隊伍正式領裝 · 同批實物換裝"
	dialog.min_size = Vector2i(720, 580)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	_label(column, "隊伍 #%d；先由原隊指揮者下令，再由相鄰營地的真實代表集中領裝。\n須 HOLD、停止、脫戰；預覽不扣物。玩家預設不納入。" % original_team_id, 15)
	var nation_choice := _options(column, ["選擇已登錄國別"], "TeamEquipmentNation")
	nation_choice.set_item_metadata(0, "")
	var standard_choice := _options(column, ["選擇正式標準"], "TeamEquipmentStandard")
	standard_choice.set_item_metadata(0, "")
	var nations: Dictionary = original_data.site.get("equipment_nations", {})
	for nation_id: String in nations:
		for index: int in team.command_members():
			if nations[nation_id].get("members", []).has(team.combat_identity(index)):
				nation_choice.add_item("%s · 文化 %s · 首長 #%d" % [nation_id, str(nations[nation_id].get("culture", "未定")), EquipmentOrders.military_head(nations[nation_id])])
				nation_choice.set_item_metadata(nation_choice.item_count - 1, nation_id)
				break
	var fill_standards := func() -> void:
		standard_choice.clear()
		standard_choice.add_item("選擇正式標準")
		standard_choice.set_item_metadata(0, "")
		var nation_id := str(nation_choice.get_item_metadata(nation_choice.selected))
		for standard_id: String in original_data.site.get("equipment_nations", {}).get(nation_id, {}).get("standards", {}):
			var standard: Dictionary = original_data.site.equipment_nations[nation_id].standards[standard_id]
			standard_choice.add_item("%s · %s" % [standard_id, str(standard.name)])
			standard_choice.set_item_metadata(standard_choice.item_count - 1, standard_id)
		if standard_choice.item_count == 2: standard_choice.select(1)
	nation_choice.item_selected.connect(func(_index: int) -> void: fill_standards.call())
	if nation_choice.item_count == 2: nation_choice.select(1)
	fill_standards.call()
	if not trial:
		_button(column, "所選本國制度／具名公務…", "TeamNationOperations", func() -> void:
			_open_nation_operations(str(nation_choice.get_item_metadata(nation_choice.selected)), dialog))
	var representative_choice := _options(column, ["選擇營地旁原隊代表"], "TeamEquipmentRepresentative")
	representative_choice.set_item_metadata(0, -1)
	var roster := ItemList.new()
	roster.name = "TeamEquipmentMembers"
	roster.select_mode = ItemList.SELECT_MULTI
	roster.custom_minimum_size = Vector2(620, 190)
	column.add_child(roster)
	for index: int in team.command_members():
		var identity := team.combat_identity(index)
		representative_choice.add_item("原隊員 #%d%s" % [identity, " · 無法行動" if not team.combat_can_act(index) else ""])
		representative_choice.set_item_metadata(representative_choice.item_count - 1, identity)
		var row := roster.add_item("#%d · %s%s" % [identity, "隊長" if index == team.formal_commander else "隊員", " · 目前受控" if identity == original_control else ""])
		roster.set_item_metadata(row, identity)
	var all_members := CheckBox.new()
	all_members.name = "TeamEquipmentAllMembers"
	all_members.text = "全隊成員（玩家除外；指定成員時取消勾選）"
	all_members.button_pressed = true
	column.add_child(all_members)
	var include_player := CheckBox.new()
	include_player.name = "TeamEquipmentIncludePlayer"
	include_player.text = "明確納入目前受控玩家"
	column.add_child(include_player)
	var simulate_npc := CheckBox.new()
	if trial:
		simulate_npc.name = "TeamEquipmentSimulateNpcCommander"
		simulate_npc.text = "開發測試：明確模擬原 NPC 現任指揮者下令"
		column.add_child(simulate_npc)
	var report := _label(column, "先選國別、標準與營地旁代表；庫存缺件時不會換任何人。", 15)
	report.name = "TeamEquipmentResult"
	var state := {"waiting": false, "representative_id": -1}
	for index: int in team.command_members():
		var existing: Dictionary = person_actions.job_for(team.combat_identity(index))
		var existing_order: Dictionary = existing.get("order", {})
		if str(existing.get("kind", "")) == "equipment" and str(existing_order.get("mode", "")) == "team_issue" and is_same(existing_order.get("team"), team):
			state["waiting"] = true
			state["representative_id"] = int(existing_order.representative_id)
			break
	var scope := func() -> bool:
		if lab.terrain != original_data or lab.controlled_person_id() != original_control or not is_instance_valid(team) or not team.has_army() or team.team_id != original_team_id:
			report.text = "STALE_SOURCE：原人物、隊伍或 Site 已變更；請重開面板"
			return false
		return true
	var selection := func() -> Array[int]:
		var ids: Array[int] = []
		if not all_members.button_pressed:
			for row: int in roster.get_selected_items(): ids.append(int(roster.get_item_metadata(row)))
		return ids
	var request := func(begin: bool) -> void:
		if not scope.call(): return
		var nation_id := str(nation_choice.get_item_metadata(nation_choice.selected))
		var standard_id := str(standard_choice.get_item_metadata(standard_choice.selected))
		var representative_id := int(representative_choice.get_item_metadata(representative_choice.selected))
		if nation_id.is_empty() or standard_id.is_empty() or representative_id <= 0 or not all_members.button_pressed and roster.get_selected_items().is_empty():
			report.text = "請選正式國別、標準、營地旁代表與至少一名成員"
			return
		var npc_mode: bool = trial and simulate_npc.button_pressed
		var requester_id: int = team.duty_decider("team.equip") if npc_mode else original_control
		var ids: Array[int] = selection.call()
		var result: Dictionary = equipment_orders.begin_team_issue(team, requester_id, representative_id, nation_id, standard_id, include_player.button_pressed, ids, npc_mode) if begin else equipment_orders.prepare_team_issue(team, requester_id, representative_id, nation_id, standard_id, include_player.button_pressed, ids, npc_mode)
		if result.ok or str(result.get("code", "")) == "ATLAS_REQUIRED":
			var targets: Array = result.get("target_ids", [])
			report.text = "%s｜目標 %d 人、需換 %d 人、領 %d 件、退 %d 件、待準備配方 %d 組" % [str(result.message), targets.size(), result.get("changed_ids", []).size(), int(result.get("take_count", 0)), int(result.get("return_count", 0)), int(result.get("recipe_count", 0))]
		else:
			report.text = "%s：%s" % [str(result.get("code", "INVALID")), str(result.get("message", ""))]
		if begin and result.ok:
			state["waiting"] = true
			state["representative_id"] = representative_id
		show_result(result)
	_button(column, "預覽全批實物與限制", "PreviewTeamEquipment", func() -> void: request.call(false))
	_button(column, "開始整隊正式領裝", "BeginTeamEquipment", func() -> void: request.call(true))
	_button(column, "取消本批換裝", "CancelTeamEquipment", func() -> void:
		if not bool(state.waiting):
			report.text = "沒有此面板正在進行的整隊換裝"
			return
		var result := equipment_orders.cancel_team_issue(lab.controlled_person_id(), int(state.representative_id)) # F08: re-check now.
		show_result(result)
		if result.ok:
			state["waiting"] = false
			report.text = str(result.message))
	_team_equipment_dialog = dialog
	_team_equipment_sync = func() -> void:
		if not bool(state.waiting): return
		var job: Dictionary = person_actions.job_for(int(state.representative_id))
		if job.is_empty() or str(job.get("order", {}).get("mode", "")) != "team_issue": return
		report.text = "共用圖集準備中；原裝與實物保留" if bool(job.get("preparing", false)) else "整隊換裝 %.1f／5.0 秒%s" % [float(job.get("elapsed", 0.0)), " · " + str(job.paused) if not str(job.get("paused", "")).is_empty() else ""]
	_team_equipment_result = func(result: Dictionary) -> void:
		if bool(state.waiting) and int(result.get("executor_id", -1)) == int(state.representative_id) and person_actions.job_for(int(state.representative_id)).is_empty():
			state["waiting"] = false
			report.text = "%s：%s" % [str(result.get("code", "OK")), str(result.get("message", ""))]
	dialog.tree_exiting.connect(func() -> void:
		if _team_equipment_dialog == dialog:
			_team_equipment_dialog = null
			_team_equipment_sync = Callable()
			_team_equipment_result = Callable())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_show_dialog(dialog, "team_equipment", ui_context, host)
	_team_equipment_sync.call()

func _open_roster(trial: bool = false, host: Window = null) -> void:
	var ui_context := str([lab.controlled_person_id(), trial])
	if _existing_dialog("roster", ui_context, host): return
	var team: TerrainArmy = lab.player_army()
	var original_control_id: int = lab.controlled_person_id()
	var original_data: TerrainData = lab.terrain
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
		var item := members.add_item("#%d  HP %.0f  疲勞 %.1f  貨物 %d  %s" % [identity, team.combat_hot_get(index, &"hp"), PersonFatigue.read(row), Runtime.inventory_size(row.cargo), "工作中" if work_team.is_assigned(identity) else "未派工"])
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
		if lab.terrain != original_data or lab.controlled_person_id() != original_control_id or lab.player_army() != team:
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
	var receiver_choice := _options(column, ["空槽拆分（自動）"], "RosterReceiverTeam")
	receiver_choice.set_item_metadata(0, -1)
	for receiver: TerrainArmy in lab.combat_armies:
		if receiver != team and receiver.has_army() and RegionFactionQuery.same_side(receiver.faction_id, team.faction_id):
			receiver_choice.add_item("編入隊伍 #%d（同勢力）" % receiver.team_id)
			receiver_choice.set_item_metadata(receiver_choice.item_count - 1, receiver.team_id)
	if trial and receiver_choice.item_count == 2:
		receiver_choice.select(1)
	var confirmation: CheckButton
	if trial:
		confirmation = CheckButton.new()
		confirmation.name = "ReceiverCommanderConfirmation"
		confirmation.text = "開發調度確認：接收隊現任合格指揮者同意此次編入"
		column.add_child(confirmation)
	var approval := {}
	var update_approval := func(enabled: bool) -> void:
		approval.clear()
		var receiver_id: int = int(receiver_choice.get_item_metadata(receiver_choice.selected))
		if receiver_id >= 0:
			approval["team_id"] = receiver_id
		if not trial or not enabled or not current_scope.call():
			return
		for receiver: TerrainArmy in lab.combat_armies:
			if receiver.team_id != receiver_id or receiver == team or not receiver.has_army() or not RegionFactionQuery.same_side(receiver.faction_id, team.faction_id):
				continue
			if receiver.duty_decider("team.roster") <= 0:
				break
			var member_ids: Array[int] = []
			for index: int in team.command_members():
				member_ids.append(team.combat_identity(index))
			approval.merge({"team_id": receiver.team_id, "commander_id": receiver.duty_decider("team.roster"),
				"source_team_id": team.team_id, "source_commander_id": original_control_id,
				"selected_ids": selected_ids.call(), "member_ids": member_ids})
			return
		confirmation.set_pressed_no_signal(false)
		apply_result.call(Runtime.fail("NO_AUTHORITY", "請先選擇仍有合格指揮者的同勢力接收隊"))
	if trial: confirmation.toggled.connect(update_approval)
	receiver_choice.item_selected.connect(func(_index: int) -> void:
		if trial: confirmation.set_pressed_no_signal(false)
		update_approval.call(false))
	update_approval.call(false)
	_label(column, "既有接收隊須雙方指揮者確認；正式流程目前僅開放空槽拆分。" if not trial else "開發勾選明示模擬 NPC 指揮者確認；空槽拆分不需對方。", 14)
	_button(column, "所選原隊員拆分／補入另一隊", "TransferRosterMembers", func() -> void:
		if current_scope.call():
			if not trial and int(receiver_choice.get_item_metadata(receiver_choice.selected)) >= 0:
				apply_result.call(Runtime.fail("NO_AUTHORITY", "尚無原接收隊指揮者的正式同意"))
				return
			apply_result.call(lab.transfer_player_roster(selected_ids.call(), false, approval))
			if trial: confirmation.button_pressed = false)
	_button(column, "全隊合入另一既有隊伍", "MergeRosterTeam", func() -> void:
		if current_scope.call():
			if not trial:
				apply_result.call(Runtime.fail("NO_AUTHORITY", "尚無原接收隊指揮者的正式同意"))
				return
			var all_members: Array[int] = []
			apply_result.call(lab.transfer_player_roster(all_members, true, approval))
			if trial: confirmation.button_pressed = false)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_show_dialog(dialog, "roster", ui_context, host)

func _selected_worker_assignment() -> Dictionary:
	var person := person_actions._person(lab.selected_army_target)
	if person.is_empty() or int(person.unit) < 0:
		return Runtime.fail("NO_TARGET", "請先選取原隊伍成員")
	if not person.owner is TerrainArmy:
		# Crowd workers take the same original work-team path (G2/G10) in peace only.
		var peace := person_actions.crowd_peace_guard([int(person.person_id)])
		if not peace.ok: return peace
	if not _can_command_person(person):
		return Runtime.fail("NO_AUTHORITY", "須由原隊伍派工職責負責者派工")
	if _work_person_unavailable(int(person.person_id)):
		return Runtime.fail("BUSY", "原人物正在執行其他工作或行動")
	return Runtime.ok("由原隊伍工作者執行", {"person": person})

func _can_command_person(person: Dictionary) -> bool:
	if region_operation_pending() or _region_player_input_blocks(): return false
	if _crowd_active() and lab.crowd_site.contains_person(int(person.get("person_id", -1))):
		# Crowd teams: only the team's current commander (the controlled person) orders work.
		var crowd_owner: Variant = person.owner
		return crowd_owner.current_commander >= 0 and crowd_owner.command_eligible(crowd_owner.current_commander) \
			and crowd_owner.combat_identity(crowd_owner.current_commander) == lab.controlled_person_id()
	if int(person.person_id) == lab.controlled_person_id():
		return true
	return int(person.unit) >= 0 and person.owner is TerrainArmy and person.owner.duty_decider("team.work") == lab.controlled_person_id()

func _work_person_unavailable(identity: int) -> bool:
	if region_operation_pending(): return true
	if _crowd_active() and lab.crowd_site.contains_person(identity): return _native_siege_work_person_unavailable(identity)
	if person_actions.is_busy(identity) or person_actions.is_guarding(identity) or _is_delivering_person(identity) or vehicles.is_operator(identity):
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

func _native_siege_work_person_unavailable(identity: int) -> bool:
	# WorkTeam is the only caller admitted here. Other native UI permissions keep
	# their existing owner guards; metadata rows never substitute for hot state.
	var site: Variant = lab.crowd_site
	if not site.siege_native_supported() or not site.crowd.has_method("charge_siege_work") or not site.crowd.has_method("controlled_step_state"): return true
	if person_actions.is_busy(identity) or person_actions.is_guarding(identity) or _is_delivering_person(identity) or vehicles.is_operator(identity) or vehicles.is_embarked(identity): return true
	var person: Dictionary = site.siege_original_person(identity)
	if person.is_empty() or person.get("row", {}).is_empty() or not person.owner.has_army(): return true
	var index := int(person.unit)
	if not person.owner.combat_can_act(index) or bool(person.row.get("site_exited", false)) or bool(person.row.get("departed", false)) or bool(person.row.get("logistics", false)): return true
	if not lab.terrain.site.get("housing", {}).get(str(identity), {}).is_empty() or not lab.terrain.site.get("captivity", {}).get(str(identity), {}).is_empty(): return true
	var formation: Dictionary = site.formation_state(int(person.owner.formation_index))
	if int(formation.get("order", -1)) != 0 or bool(formation.get("routed", false)) or bool(formation.get("garrisoned", false)): return true
	var hot: Dictionary = site.soldier_state(index)
	if hot.is_empty() or int(hot.get("prison_id", 0)) != 0 or bool(hot.get("captive", false)) or float(hot.get("stagger", 0.0)) > 0.0 or float(hot.get("knock_t", 0.0)) > 0.0 or float(hot.get("act_t", 0.0)) > 0.0 or float(hot.get("exch_cd", 0.0)) > 0.0 or float(hot.get("ranged_cd", 0.0)) > 0.0 or float(hot.get("skill_cd", 0.0)) > 0.0: return true
	var step: PackedInt64Array = site.crowd.siege_person_state(index)
	if step.size() != 8 or int(step[0]) != 0 or int(step[3]) > 0: return true
	var controlled: PackedInt64Array = site.crowd.controlled_step_state(index)
	# Mode 5 is this original WorkTeam approach, including its committed edge.
	# Do not cancel it merely because the worker is still walking to the station.
	if controlled.size() != 2 or int(controlled[0]) not in [0, 5]: return true
	var supply := _supply_entry(person.owner)
	return not supply.is_empty() and (bool(supply.get("training_order", false)) or not supply.get("delivery", {}).is_empty())

func _advance_crew(seconds: float) -> void:
	var result: Dictionary = work_team.advance(seconds, _shared_work_plan).handled_seconds
	for identity: int in result:
		_crew_handled[identity] = float(_crew_handled.get(identity, 0.0)) + float(result[identity])

func consume_crew_work() -> Dictionary:
	var result := _crew_handled.duplicate()
	_crew_handled.clear()
	return result

func advance_guard_work(seconds: float) -> Dictionary:
	if not _shared_work_plan.is_empty(): return _consume_shared_guard_work()
	var handled := {}
	var guards := {}
	var threats := {}
	for relation: Dictionary in lab.terrain.site.captivity.values():
		if str(relation.get("prison_id", "")).is_empty():
			guards[int(relation.guard_id)] = true
	for identity: int in guards:
		if _crowd_active() and lab.crowd_site.contains_person(identity): continue
		var person := person_actions._person(identity)
		if not person_actions._ready(person, true) or person_actions.is_busy(identity) or person_actions._threat(person, threats):
			continue
		var fatigue := float(person_actions._body_get(person, "fatigue"))
		var autonomous: bool = identity != lab.controlled_person_id()
		var resting: bool = autonomous and PersonFatigue.needs_work_rest(fatigue, bool(person_actions._body_get(person, "work_resting")))
		person_actions._body_set(person, "work_resting", resting)
		if resting:
			continue # Original safe-rest update handles recovery; no duplicate time.
		var effort := minf(seconds, maxf(0.0, (PersonFatigue.WORK_REST_AT - fatigue) / PersonFatigue.effort_rate(person.body))) if autonomous else seconds
		var state := PersonFatigue.advance(fatigue, float(person_actions._body_get(person, "fatigue_rest")), effort, PersonFatigue.effort_rate(person.body), false)
		person_actions._body_set(person, "fatigue", minf(PersonFatigue.WORK_REST_AT, state[0]) if autonomous else state[0])
		person_actions._body_set(person, "fatigue_rest", state[1])
		if autonomous:
			person_actions._body_set(person, "work_resting", PersonFatigue.needs_work_rest(float(person_actions._body_get(person, "fatigue")), false))
		handled[identity] = effort
	return handled

func _archive_family_site() -> Dictionary:
	if region_slot != null and (not lab._region_point_pending.is_empty() or not region_slot.pending_region_events().is_empty()):
		return checkpoint_region_internal("region_family", false, {"original_point": lab._region_point_pending.duplicate(true)})
	return save_to(_archive_path())

func _control_family_person(data: Variant, identity: int) -> Dictionary:
	if data != null and ship_journey_active(): return Runtime.fail("BUSY", "原船隊旅程只能接續同船隊原人物，不能跨 Site 換場")
	var old_identity: int = lab.controlled_person_id()
	if data != null and _crowd_active():
		return Runtime.fail("UNSUPPORTED", "群眾戰鬥中不支援跨 Site 接續")
	if data != null:
		if not data is TerrainData or float(FamilyContinuity._saved_person(data, identity).get("hp", 0.0)) <= 0.0:
			return Runtime.fail("NO_TARGET", "原快照人物不存在；保留目前場景")
		var guard: Dictionary = lab.exchange_snapshot_guard(data)
		if not guard.ok:
			return guard
		data.site["controlled_person_id"] = identity
		lab.bind_terrain(data) # Original validated actor/row restore, never a substitute body.
	var target: Dictionary = lab._combat_target(identity)
	if data == null and ship_person_in_journey(identity):
		for original: TerrainArmy in lab.combat_armies:
			var index := original.index_for_identity(identity)
			if index >= 0 and index < original.combat_units.size():
				target = {"owner": original, "unit": index, "hp": float(original.combat_hot_get(index, &"hp", 0.0)), "position": lab.camera.position}
				break
	if target.is_empty() or float(target.hp) <= 0.0:
		return Runtime.fail("NO_TARGET", "原接續人物不存在或已死亡")
	if _crowd_active():
		var switched: Dictionary = lab.crowd_site.on_control_changed(old_identity, identity)
		if not switched.ok: return switched
	lab.terrain.site["controlled_person_id"] = identity
	invalidate_ui_context()
	for team: TerrainArmy in lab.combat_armies: team.sync_shared_fatigue(true)
	person_executor_id = identity
	if int(target.unit) < 0 and target.owner == lab.npc:
		lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	lab._clear_movement_input()
	lab.camera.position = target.position
	_family_wait = false
	if is_instance_valid(_family_dialog):
		_family_dialog.queue_free()
	_family_dialog = null
	lab.terrain.site["paused"] = false
	get_tree().paused = false
	return Runtime.ok("已接續原人物 #%d；保留生命、年齡、拘押、實物與原職位" % identity)

## Same-Site control is not a departure, appointment or death settlement.
func _live_family_handover_guard(person_id: int) -> Dictionary:
	var prepared: Dictionary = family_continuity.prepare_live_handover(lab.controlled_person_id(), str(lab.terrain.site["id"]), person_id)
	if not prepared["ok"]: return prepared
	if lab.restore_only or _crowd_active() or lab.terrain.has_meta(&"region_party_owner"):
		return Runtime.fail("UNSUPPORTED", "請在原活動 Site 到站後交接")
	if ship_journey_active() or not _ground_crossing.is_empty() or _family_wait or lab._region_point_consuming or not lab._region_point_pending.is_empty():
		return Runtime.fail("BUSY", "先收束原旅行或共同步進")
	if is_instance_valid(lab._movement_input_actor) and absf(lab._movement_input_actor.ride_speed) > TerrainLab.ACTION_TIME_EPSILON:
		return Runtime.fail("BUSY", "先釋放原騎乘移動輸入")
	var guard: Dictionary = supply_save_guard()
	if not guard["ok"]: return guard
	guard = vehicles.boarding_save_guard()
	if not guard["ok"]: return guard
	for identity: int in [lab.controlled_person_id(), person_id]:
		var target: Dictionary = lab._combat_target(identity)
		if target.is_empty(): return Runtime.fail("NO_TARGET")
		if int(target["unit"]) < 0:
			var actor: TerrainTestCharacter = target["owner"]
			if not lab.actor_present(actor) or actor.data != lab.terrain: return Runtime.fail("NO_TARGET")
			if actor.is_moving() or actor.action_time > 0.0 or actor.guarding or actor.guard_transition_left > 0.0:
				return Runtime.fail("BUSY", "先完成原人物動作")
		else:
			var team: TerrainArmy = target["owner"]
			var index: int = int(target["unit"])
			if team.member_gone(index): return Runtime.fail("NO_TARGET")
			if team.moving_to[index] != TerrainArmy.INVALID_CELL or bool(team.combat_hot_get(index, &"attack")) or str(team.combat_hot_get(index, &"pose")) in ["guard", "guard_raise", "guard_lower"]:
				return Runtime.fail("BUSY", "先完成原隊員動作")
		var person: Dictionary = person_actions._person(identity, false)
		if person.is_empty(): return Runtime.fail("NO_TARGET")
		if bool(person.get("surrender_pending", false)): return Runtime.fail("UNAVAILABLE", "原人物投降尚未結束")
		if person["body"].get("departed") == true or person["body"].get("site_exited") == true:
			return Runtime.fail("NO_TARGET")
		if _person_has_duty(identity): return Runtime.fail("BUSY", "先完成或解除原人物作業")
	return prepared

## Store calls this actual owner again; a caller cannot supply an arbitrary body.
func live_family_handover_state(person_id: int) -> Dictionary:
	var guard: Dictionary = _live_family_handover_guard(person_id)
	if not guard["ok"]: return guard
	var state: Dictionary = lab.terrain.site.duplicate(true)
	_capture_positions(state, true)
	state["controlled_person_id"] = person_id
	return Runtime.ok("", {"state": state})

func _handover_family_person(requester_id: int, site_id: String, person_id: int) -> Dictionary:
	var prepared: Dictionary = family_continuity.prepare_live_handover(requester_id, site_id, person_id)
	if not prepared["ok"]: return prepared
	var guard: Dictionary = _live_family_handover_guard(person_id)
	if not guard["ok"]: return guard
	var selected: Dictionary
	if region_slot != null:
		selected = region_slot.commit_live_family_handover(lab, requester_id, person_id)
	else:
		selected = Store.save(lab.terrain, "", null, false, {}, true, person_id)
	if not selected["ok"]: return selected
	# No yield, callback or fallible operation after the Slot's single publication.
	var state: Dictionary = selected["state"]
	lab.terrain.site["actors"] = state["actors"]
	lab.terrain.site["armies"] = state["armies"]
	lab.terrain.site["player_cell"] = state["player_cell"]
	lab.terrain.site["worker"]["cell"] = state["worker"]["cell"]
	if state.has("region_snapshot"): lab.terrain.site["region_snapshot"] = state["region_snapshot"]
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled or not team.offices.is_empty(): continue
		for saved: Dictionary in state["armies"]:
			if int(saved["team_id"]) == team.team_id: team.offices = saved["offices"].duplicate(true)
	lab.terrain.site["controlled_person_id"] = person_id
	person_executor_id = person_id
	lab._clear_movement_input()
	lab.camera.position = lab._combat_target(person_id)["position"]
	invalidate_ui_context()
	if is_instance_valid(_family_dialog): _family_dialog.queue_free()
	_family_dialog = null
	return Runtime.ok("已交接控制給原家人 #%d；原人物、住宅、職位與隊伍保留" % person_id, {"person_id": person_id, "generation": selected.get("generation", -1)})

func _live_family_ui_context() -> Dictionary:
	return {"data": lab.terrain, "requester": lab.controlled_person_id(), "family": lab.terrain.site.get("family", {}).duplicate(true),
		"slot": region_slot, "generation": int(region_slot._marker.get("generation", 0)) if region_slot != null else -1,
		"revision": int(region_slot.region_registry()["revision"]) if region_slot != null else -1}

func _submit_live_family_handover(context: Dictionary, site_id: String, person_id: int) -> Dictionary:
	if context != _live_family_ui_context(): return Runtime.fail("STALE_CONTEXT", "原場景、家族、控制者或保存世代已改變；請重開家族窗")
	return family_continuity.handover(int(context["requester"]), site_id, person_id)

func check_family_death() -> void:
	if is_instance_valid(_family_dialog) or (_pending_deaths.has(lab.controlled_person_id()) if _crowd_active() else not _pending_deaths.is_empty()):
		return
	var death := family_continuity.death_tick()
	if not death.ok or str(death.status) != "DEAD":
		return
	if _family_wait and float(lab.terrain.site.combat_left) > 0.0:
		return
	_family_wait = false
	if lab.restore_only: return # death_tick/remains already settled; no global UI pause.
	_open_family()

func _open_family(host: Window = null) -> void:
	if is_instance_valid(_family_dialog):
		_focus_dialog(_family_dialog)
		return
	var observation := family_continuity.inspect()
	if not observation.ok:
		show_result(observation)
		return
	var death := family_continuity.death_tick()
	var dead: bool = death.ok and str(death.status) == "DEAD"
	if dead:
		lab.terrain.site["paused"] = true
		get_tree().paused = true
		lab._clear_movement_input()
	var dialog := AcceptDialog.new()
	dialog.name = "FamilyDialog"
	_family_dialog = dialog
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.title = "原家人接續" if dead else "家族與控制交接"
	dialog.min_size = Vector2i(620, 430)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	var messages := {"UNREGISTERED": "家族尚未明確登錄；不是 Game Over。沒有自動建立親屬。",
		"DATA_MISSING": "部分家族資料缺失／名單未確認完整，不能判定 Game Over。",
		"GAME_OVER": "Game Over：已確認的完整家族名單沒有其他在世成員。",
		"CHOOSE": "請選在世原家人。未成年不成年、被俘不解綁、死者遺物不轉送。",
		"ALIVE": "能履職的家主可把控制交給同站清醒自由的家人。原家主保留住宅與職位；受方非家主則不能再次交接。死亡接續仍只限真正死亡。"}
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
	if not dead:
		var context: Dictionary = _live_family_ui_context()
		_button(column, "交接控制給選取的家人（原人物留站）", "LiveFamilyHandover", func() -> void:
			if list.get_selected_items().is_empty(): return
			var member: Dictionary = list.get_item_metadata(list.get_selected_items()[0])
			show_result(_submit_live_family_handover(context, str(member["site_id"]), int(member["person_id"]))))
	if dead:
		_button(column, "繼續原場景，等待脫戰安全歸檔後再選", "WaitForFamilyArchive", func() -> void:
			_family_wait = true
			dialog.queue_free()
			_family_dialog = null
			lab.terrain.site["paused"] = false
			get_tree().paused = false)
	dialog.confirmed.connect(func() -> void:
		if not dead:
			dialog.queue_free()
			_family_dialog = null)
	dialog.canceled.connect(func() -> void:
		if not dead:
			dialog.queue_free()
			_family_dialog = null)
	_dialog_host(host).add_child(dialog)
	dialog.popup_centered()

func _open_family_registry(host: Window = null) -> void:
	var ui_context := str(lab.controlled_person_id())
	if _existing_dialog("family_registry", ui_context, host): return
	var original_data: TerrainData = lab.terrain
	var original_control: int = lab.controlled_person_id()
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
	path_input.text = _archive_path()
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
		if lab.terrain != original_data or lab.controlled_person_id() != original_control:
			show_result(Runtime.fail("STALE", "原 Site 或控制人物已變更，請重開家族登錄"))
			return
		var result := family_continuity.register_members(members, complete.button_pressed, lab.controlled_person_id())
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
			_open_family(host))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_show_dialog(dialog, "family_registry", ui_context, host)

func _person_died(identity: int) -> void:
	_pending_deaths[identity] = float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"])

func settle_person_deaths(real_seconds: float) -> void:
	advance_person_death_timers(real_seconds)
	for identity: int in _pending_deaths.keys():
		if _crowd_active() and lab.crowd_site.has_pending_capture(identity): continue
		if float(_pending_deaths[identity]) > 0.0:
			continue # Resolve original owners only when the down animation can settle.
		var person := person_actions._person(identity)
		if person.is_empty():
			continue # Never silently lose a pending person's actual belongings.
		if float(person.hp) > 0.0:
			_pending_deaths.erase(identity) # Only explicit development reset can revive.
			continue
		if bool(person_actions._body_get(person, "loot_settled")):
			lab.terrain.site.get("housing", {}).erase(str(identity))
			_pending_deaths.erase(identity)
			continue
		var aboard: bool = person.body is Dictionary and person.body.has("embarked_vehicle_id")
		var ship_location: Dictionary = vehicles.ship_death_location(identity) if aboard else {}
		if aboard and ship_location.is_empty():
			continue # Retain a damaged boat reference, never drop at historical shore.
		if bool(person.moving) and not aboard:
			continue # Finish an original land step; a moving hull keeps local loot.
		var opened := _personal_opened_food(identity)
		var result := Runtime.leave_ground_loot(lab.terrain, person.holder, person.cargo, identity, person.cell, "remains", person.cargo, person.holder.item_ids.duplicate(), int(person.holder.version), opened, float(opened.get("open_rations", 0.0)), false, ship_location)
		if not result.ok and str(result.code) != "EMPTY":
			continue # Preflight failure retains original items and blocks replacement/save.
		person_actions._body_set(person, "loot_settled", true)
		person_actions._body_set(person, "remains_id", str(result.get("container_id", "")))
		if not ship_location.is_empty(): vehicles.ship_death_settled(identity)
		lab.terrain.site.get("captivity", {}).erase(str(identity))
		lab.terrain.site.get("housing", {}).erase(str(identity))
		_pending_deaths.erase(identity)
		equipment_changed(identity)

func _presentation_holder(person: Dictionary) -> Dictionary:
	if float(person.hp) <= 0.0 and bool(person_actions._body_get(person, "loot_settled")):
		return lab.terrain.site.ground_loot.get(str(person.body.get("remains_id")), Runtime.new_item_state("empty-remains"))
	return person.holder

func person_can_wear_cape(identity: int) -> bool:
	return equipment_orders.cape_role_allowed(identity)

func retire_officer_capes(identities: Array[int]) -> Dictionary:
	var retiring: Array[int] = []
	for identity: int in identities:
		var person := person_actions._person(identity, false)
		var qualified: bool = not person.is_empty() and str(person.body.get("military_role")) == "officer"
		if not qualified and not equipment_orders.nation_grants_cape(identity): retiring.append(identity)
	return equipment_orders.retire_capes(retiring)

func cape_departure_guard(identity: int) -> Dictionary:
	var person := person_actions._person(identity)
	var qualified: bool = not person.is_empty() and str(person.body.get("military_role")) == "officer"
	if not person.is_empty() and person.holder.equipped.has("cape") and not qualified and not equipment_orders.nation_grants_cape(identity):
		return Runtime.fail("CAPE_REMOVE_FIRST", "離任／退隊前請先將披風卸回本人行囊；名冊、職務、物品與供養未改")
	return Runtime.ok()

func reconcile_cape_roles(identities: Array[int]) -> Dictionary:
	var retiring: Array[int] = []
	for identity: int in identities:
		var person := person_actions._person(identity)
		if person.is_empty() or float(person.hp) <= 0.0 or not person.holder.equipped.has("cape"): continue
		if not equipment_orders.cape_role_allowed(identity): retiring.append(identity)
	var result := equipment_orders.retire_capes(retiring)
	if not result.ok:
		_auto_save_blocked = true
		show_result(result)
	return result

func cape_policy_guard() -> Dictionary:
	var identities: Array[int] = []
	if _crowd_active():
		for crowd_owner: RefCounted in lab.crowd_site.person_owners():
			for index: int in crowd_owner.combat_units:
				identities.append(crowd_owner.combat_identity(index))
	for actor: TerrainTestCharacter in lab.combat_actors:
		identities.append(actor.person_id)
	for team: TerrainArmy in lab.combat_armies:
		for index in range(team.combat_units.size()): identities.append(team.combat_identity(index))
	for identity: int in identities:
		var person := person_actions._person(identity)
		if person.is_empty() or float(person.hp) <= 0.0: continue
		var guard := equipment_orders.cape_wear_guard(identity, person.holder.equipped)
		if not guard.ok: return Runtime.fail(guard.code, "原人物 %d 的披風須先完成卸裝；請檢查行囊容量及無披風圖集准入" % identity)
	return Runtime.ok()

func equipment_removal_guard(identity: int, item_ids: Array) -> Dictionary:
	return _removal_holder_guard(identity, item_ids, false)

## Capture/custody sealing of a captive's worn items (Nekki 2026-10-27). Same holder/recipe guard as an
## ordinary removal; only its shared-atlas requirement is mechanics-only in headless (see _equipment_recipe_guard).
func custody_removal_guard(identity: int, item_ids: Array) -> Dictionary:
	return _removal_holder_guard(identity, item_ids, true)

func _removal_holder_guard(identity: int, item_ids: Array, custody: bool) -> Dictionary:
	var person := person_actions._person(identity)
	if person.is_empty():
		return Runtime.ok() # Historical owner no longer has a scene body; ground items remain real.
	var proposed: Dictionary = _presentation_holder(person).duplicate(true)
	for slot: String in proposed.equipped.keys():
		if item_ids.has(proposed.equipped[slot]):
			proposed.equipped.erase(slot)
	return _equipment_holder_guard(person, proposed, custody)

func equipment_apply_guard(identity: int, equipped: Dictionary) -> Dictionary:
	return _equipment_apply_guard(identity, equipped, false)

func _equipment_apply_guard(identity: int, equipped: Dictionary, team_batch: bool) -> Dictionary:
	var person := person_actions._person(identity)
	if person.is_empty():
		return Runtime.fail("NO_TARGET")
	var cape_guard := equipment_orders.cape_wear_guard(identity, equipped)
	if not cape_guard.ok: return cape_guard
	# Preflight may include real depot pieces not transferred yet. Derive only
	# the proposed appearance; no production holder or item record moves.
	var original: Dictionary
	if _crowd_active() and lab.crowd_site.contains_person(int(person.person_id)):
		original = person.owner.combat_hot_get(int(person.unit), &"appearance", {})
	else:
		original = person.body.appearance if int(person.unit) >= 0 else person.owner._saved_appearance
	var appearance := original.duplicate(true)
	appearance.erase("equipment_dyes")
	for slot: String in Runtime.APPEARANCE_EQUIPMENT_SLOTS:
		appearance.parts[slot] = "none"
	appearance["mounted"] = equipped.has(Runtime.MOUNT_SLOT) # CAV-3a: derived from the mount slot only.
	for slot: String in equipped:
		# CAV-3: the mount slot only sets mounted (above). Its horse is a worn horse item or Runtime.MOUNT_GOODS
		# (drawn from goods at commit); SiteEquipmentOrders.check validates both before this guard.
		if slot == Runtime.MOUNT_SLOT: continue
		var record: Dictionary = lab.terrain.site.item_records.get(equipped[slot], {})
		var definition: Dictionary = lab.terrain.site.item_definitions.get(str(record.get("definition", "")), {})
		if definition.get("slot") != slot:
			return Runtime.fail("UNSUPPORTED", "此實物色彩／裝備槽尚未有原呈現支援")
		appearance.parts[slot] = str(definition.asset)
		var dye := Runtime.item_dye(record, definition)
		if not dye.is_empty():
			if not appearance.has("equipment_dyes"): appearance["equipment_dyes"] = {}
			appearance.equipment_dyes[slot] = dye
	var result := _equipment_recipe_guard(person, appearance, team_batch)
	if team_batch and (result.ok or str(result.get("code", "")) == "ATLAS_REQUIRED"):
		result.appearance = appearance
	return result

func equipment_dye_guard(identity: int, changes: Dictionary) -> Dictionary:
	var person := person_actions._person(identity)
	if person.is_empty():
		return Runtime.fail("NO_TARGET")
	var appearance := person_appearance(identity).duplicate(true)
	var dyes: Dictionary = appearance.get("equipment_dyes", {}).duplicate()
	for slot: String in changes:
		if changes[slot] == "":
			var record: Dictionary = lab.terrain.site.item_records[person.holder.equipped[slot]]
			var default_dye := Runtime.item_dye({}, lab.terrain.site.item_definitions[record.definition])
			if default_dye.is_empty(): dyes.erase(slot)
			else: dyes[slot] = default_dye
		else: dyes[slot] = changes[slot]
	if dyes.is_empty(): appearance.erase("equipment_dyes")
	else: appearance["equipment_dyes"] = dyes
	return _equipment_recipe_guard(person, appearance)

func _request_person_dye(changes: Dictionary, identity: int) -> Dictionary:
	var result := equipment_orders.dye_person(lab.controlled_person_id(), identity, changes)
	show_result(result)
	return result

func _equipment_holder_guard(person: Dictionary, proposed: Dictionary, custody: bool = false) -> Dictionary:
	var original: Dictionary
	if _crowd_active() and lab.crowd_site.contains_person(int(person.person_id)):
		original = person.owner.combat_hot_get(int(person.unit), &"appearance", {})
	else:
		original = person.body.appearance if int(person.unit) >= 0 else person.owner._saved_appearance
	var appearance := Runtime.equipment_appearance(lab.terrain, proposed, original)
	return _equipment_recipe_guard(person, appearance, false, custody)

func _equipment_team_external_duty_guard(identity: int) -> bool:
	return work_team.is_assigned(identity) or _is_delivering_person(identity) or vehicles.is_operator(identity)

func _equipment_team_holder_guard(identity: int, proposed: Dictionary) -> Dictionary:
	return _equipment_apply_guard(identity, proposed, true)

func _equipment_recipe_guard(person: Dictionary, appearance: Dictionary, team_batch: bool = false, custody: bool = false) -> Dictionary:
	if _crowd_active() and lab.crowd_site.contains_person(int(person.person_id)):
		return lab.crowd_site.equipment_recipe_guard(int(person.person_id), appearance)
	if appearance.is_empty() or not HumanCharacter3DEditor.valid_appearance(appearance):
		return Runtime.fail("INVALID", "實物配裝不能對應原人物")
	# Settled ship deaths have no corpse presenter or collision source. Looting
	# their original worn items still uses the normal item/version transaction.
	if int(person.unit) >= 0 and float(person.hp) <= 0.0 and person.body.get("loot_settled", false) == true and person.body.get("ship_death_settled", false) == true:
		return Runtime.ok()
	if float(person.hp) > 0.0 and str(appearance.parts.get("cape", "none")) != "none" and not equipment_orders.cape_role_allowed(int(person.person_id)):
		return Runtime.fail("CAPE_ROLE_RESTRICTED", "披風僅限現任軍官以上；先完成原披風卸裝")
	var vehicle: Dictionary = vehicles._operated(int(person.person_id))
	if vehicle.get("kind", "") == "wagon" and not preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd").supports(appearance):
		return Runtime.fail("UNSUPPORTED", "此人物的固定布裝騎姿素材未就緒；原物品與染色未改")
	if not team_batch:
		for team: TerrainArmy in lab.combat_armies:
			var member_index := team.index_for_identity(int(person.person_id))
			if member_index >= 0:
				var troop_guard := team.single_troop_equipment_guard(member_index, appearance)
				if not troop_guard.ok: return troop_guard
	if int(person.unit) >= 0 and (not person.owner._uses_live_presenter(int(person.unit)) or (DisplayServer.get_name() == "headless" and not bool(appearance.get("mounted", false)))):
		if not TerrainArmy.prepare_contact_source_for(appearance):
			return Runtime.fail("UNSUPPORTED", "此配裝的原碰撞來源未就緒")
	if int(person.unit) >= 0 and not person.owner._uses_live_presenter(int(person.unit)):
		if not person.owner.supports_equipment_recipe(appearance):
			if not TerrainArmy.EquipmentAtlas.mixed_plan(appearance).is_empty():
				# Custody sealing: headless verifies mechanics only, exactly as the siege-work asset gate
				# below (DisplayServer headless) and SiteVehicleTransport._siege_work_assets_guard do. A shared
				# atlas can only be built with a GPU; visual runs keep the gate and prepare it first.
				if custody and DisplayServer.get_name() == "headless": return Runtime.ok()
				var missing := Runtime.fail("ATLAS_REQUIRED", "此配裝須先準備完整共用圖集；原裝與物品保留")
				missing.appearance = appearance.duplicate(true)
				return missing
			return Runtime.fail("UNSUPPORTED", "此配裝尚無完整原動畫圖集；未扣物")
	if DisplayServer.get_name() != "headless" and int(person.unit) >= 0 and not bool(appearance.get("mounted", false)) and _siege_team_has_vehicle(int(person.owner.team_id)) and not SiegeWorkAppend.ready(appearance):
		var missing := Runtime.fail("ATLAS_REQUIRED", "此原隊攻城工作動作須先備妥；原裝與物品保留")
		missing.appearance = appearance.duplicate(true)
		return missing
	return Runtime.ok()

func _request_person_equipment(slot: String, asset: String, identity: int) -> String:
	if slot not in Runtime.EQUIPMENT_SLOTS:
		return asset # Body/face/hair are not loot or manufactured equipment.
	var current := str(person_appearance(identity).get("parts", {}).get(slot, "none"))
	var crowd_guard := person_actions.crowd_equipment_guard([identity])
	if not crowd_guard.ok:
		show_result(crowd_guard)
		return current
	if slot == "cape" and asset != "none" and not equipment_orders.cape_role_allowed(identity):
		show_result(Runtime.fail("CAPE_ROLE_RESTRICTED", "披風僅限現任軍官以上；預覽選單不授予職位或實物"))
		return current
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
	if _crowd_active() and lab.crowd_site.contains_person(identity):
		lab.crowd_site.equipment_changed(identity)
		return
	var person := person_actions._person(identity)
	if person.is_empty():
		return
	var original: Dictionary = person.body.appearance if int(person.unit) >= 0 else (person.owner.editor.capture_appearance() if person.owner.editor != null else person.owner._saved_appearance)
	var appearance := Runtime.equipment_appearance(lab.terrain, _presentation_holder(person), original)
	if appearance.is_empty():
		return
	_freeze_appearance(appearance)
	_equipment_appearances[identity] = appearance
	if int(person.unit) >= 0:
		var team: TerrainArmy = person.owner
		var presenter: Variant = team._unit_editor(int(person.unit))
		if team._uses_live_presenter(int(person.unit)) and presenter != null:
			presenter.restore_appearance(appearance)
		if int(person.unit) == 0: team.refresh_captain_presentation()
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
	if _crowd_active() and lab.crowd_site.contains_person(identity):
		lab.crowd_site.captivity_changed(identity, _captor_id, capturing)
		return
	var person := person_actions._person(identity)
	if person.is_empty():
		return
	if int(person.unit) >= 0:
		var team: TerrainArmy = person.owner
		team._cancel_unit_rescue(int(person.unit))
		person_actions._body_set(person, "attack", false)
		person.body.previous = []
		person.body.hits = {}
		person.body.target = -1
		person_actions._body_set(person, "think", 0.5)
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
	var prepared: Dictionary = prepare_received_opened_food(identity, amount, original)
	assert(prepared.ok)
	var checked: Dictionary = validate_received_opened_food(prepared)
	assert(checked.ok)
	publish_received_opened_food(prepared)

func _chosen_supply_team() -> Variant:
	# P1e: under crowd the player's team is the owner of the controlled person (a native crowd owner).
	if _crowd_active() and lab.crowd_site.contains_person(lab.controlled_person_id()):
		return lab.crowd_site.person_owner(lab.controlled_person_id())
	return lab.player_army()

# P1e: the representative standing on the selected cell, read from a crowd owner (cell and identity) or a grid army (cells).
func _representative_at(team: Variant, cell: Vector2i) -> int:
	if team is CrowdPersonOwner:
		for key: Variant in team.combat_units.keys():
			var person: Dictionary = team.person(int(key), false)
			if not person.is_empty() and Vector2i(person.cell) == cell: return team.combat_identity(int(key))
		return -1
	for index: int in team.combat_units.size():
		if team.cells[index] == cell: return team.combat_identity(index)
	return -1

func _supply_entry(team: Variant) -> Dictionary:
	return lab.terrain.site.get("team_supply", {}).get(str(team.team_id), {}) if team != null else {}

func _supply_stock(entry: Dictionary) -> Dictionary:
	return entry.get("locations", {}) if int(entry.get("version", 0)) == 3 else entry.get("inventory", {})

func _supply_person(identity: int) -> Dictionary:
	if vehicles != null and vehicles.has_method("is_embarked") and vehicles.is_embarked(identity):
		var person: Dictionary = vehicles.ship_person(identity)
		if not person.is_empty():
			return person
	return person_actions._person(identity)

func _supply_shore_contact(first: Vector2i, second: Vector2i) -> bool:
	if not lab.terrain.is_walkable(first) or not lab.terrain.is_walkable(second):
		return false
	return first == second or absi(first.x - second.x) + absi(first.y - second.y) == 1 and lab.terrain.can_step(first, second)

func _supply_location_valid(team: Variant, key: String) -> bool:
	if not Sustain._valid_location_key(key):
		return false
	if key.begins_with("shore:"):
		var index := int(key.trim_prefix("shore:"))
		return index >= 0 and index < lab.terrain.size.x * lab.terrain.size.y and lab.terrain.is_walkable(lab.terrain.cell_from_index(index))
	var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(key.trim_prefix("vehicle:"), {})
	return SiteVehicleTransport.is_ship(vehicle) and int(vehicle.get("team_id", -1)) == team.team_id

func _supply_locations_valid(team: Variant, locations: Dictionary) -> bool:
	if not Sustain._valid_locations(locations):
		return false
	for key: String in locations:
		if not _supply_location_valid(team, key):
			return false
		for resource: String in locations[key].inventory:
			if resource not in Sustain.FOODS: return false
	return true

func ship_food_locations(team: Variant, members: Dictionary, candidate_locations: Dictionary = {}) -> Dictionary:
	var result := {}
	var entry := _supply_entry(team)
	var locations: Dictionary = entry.get("locations", {}) if candidate_locations.is_empty() else candidate_locations
	var keys := locations.keys()
	keys.sort()
	for id: int in members:
		result[id] = ""
		var person := _supply_person(id)
		if person.is_empty():
			continue
		if vehicles.is_embarked(id):
			var key := "vehicle:" + str(vehicles.ship_for_person(id).id)
			if locations.has(key): result[id] = key
			continue
		for key: String in keys:
			if not key.begins_with("shore:") or not _supply_shore_contact(person.cell, lab.terrain.cell_from_index(int(key.trim_prefix("shore:")))):
				continue
			if str(result[id]).is_empty(): result[id] = key
			var stock: Dictionary = locations[key]
			if Sustain.rations(stock, stock.inventory) > Sustain.EPS:
				result[id] = key
				break
	return result

func _team_food_endpoint(team: Variant, identity: int, create_location: bool = false) -> Dictionary:
	var entry := _supply_entry(team)
	if entry.is_empty(): return {}
	if int(entry.version) != 3:
		return {"inventory": entry.inventory, "opened": entry.sustain, "key": "", "exists": true}
	var person := _supply_person(identity)
	if person.is_empty(): return {}
	var key := str(ship_food_locations(team, {identity: person.body}).get(identity, ""))
	if key.is_empty() and create_location:
		key = "vehicle:" + str(vehicles.ship_for_person(identity).id) if vehicles.is_embarked(identity) else "shore:%d" % lab.terrain.index(person.cell)
	if key.is_empty() or not _supply_location_valid(team, key): return {}
	var stock: Dictionary = entry.locations.get(key, {"inventory": {}, "open_rations": 0.0})
	return {"inventory": stock.inventory, "opened": stock, "key": key, "exists": entry.locations.has(key)}

func _supply_boarding_job_valid(team: Variant, shore: Vector2i, job: Dictionary) -> bool:
	if job.is_empty(): return true
	if str(job.get("kind", "")) != "ship_board" or not is_same(person_actions._jobs.get(str(job.get("executor_id", 0)), {}), job): return false
	if not is_same(job.get("terrain"), lab.terrain) or not is_same(job.get("site_state"), lab.terrain.site) or job.get("shore") != shore or int(job.get("executor_cell", -1)) != lab.terrain.index(shore): return false
	var person := vehicles.ship_person(int(job.executor_id))
	var vehicle: Dictionary = vehicles.records().get(str(job.get("vehicle_id", "")), {})
	return not person.is_empty() and is_same(person.owner, team) and team.is_member(int(person.unit)) and person.cell == shore and not vehicles.is_embarked(int(person.person_id)) and int(person.hit) == int(job.get("executor_hit", -1)) and SiteVehicleTransport.is_ship(vehicle) and int(vehicle.team_id) == team.team_id and int(vehicle.revision) == int(job.get("ship_revision", -1))

func prepare_ship_supply(team: Variant, shore: Vector2i, preview: bool = false, boarding_job: Dictionary = {}) -> Dictionary:
	if region_operation_pending(): return Runtime.fail("BUSY", "原固定目標冷交換尚未完成，先等待再裝卸供養")
	if team == null or not team.combat_enabled or not _supply_boarding_job_valid(team, shore, boarding_job) or get_tree().paused or bool(lab.terrain.site.paused):
		return Runtime.fail("BUSY", "首次登船前須全隊停止並收束原動作")
	if not lab.terrain.contains(shore) or not lab.terrain.is_walkable(shore):
		return Runtime.fail("UNREACHABLE", "共有口糧須落在本人已到達的合法岸格")
	var present := false
	for id: int in team.command_members():
		var person := _supply_person(team.combat_identity(id))
		if not person.is_empty() and not vehicles.is_embarked(int(person.person_id)) and person.cell == shore and _delivery_person_ready(person, boarding_job):
			present = true
			break
	if not present: return Runtime.fail("UNREACHABLE", "未有原隊員在指定岸格，不能遠端搬移舊共有糧")
	var existing := _supply_entry(team)
	if not existing.is_empty() and int(existing.version) == 3:
		var checked: Dictionary = existing.sustain.duplicate(true)
		if not existing.delivery.is_empty() or not _align_supply_clock(checked, Runtime.now(lab.terrain) * 60.0) or not _supply_locations_valid(team, existing.locations) or not Sustain.validate(checked, captivity_supply._all_members()): return Runtime.fail("INVALID_SUSTAIN")
		return Runtime.ok()
	# Only the first conversion relocates the old abstract stock. Once locations
	# are authoritative, each boat keeps its own original job and stop guards.
	if not _team_stopped(team, false, boarding_job):
		return Runtime.fail("BUSY", "首次登船前須全隊停止並收束原動作")
	var supplied: Dictionary = captivity_supply.enable_team(team, true)
	if not supplied.ok: return supplied
	var entry: Dictionary = supplied.entry
	if not entry.delivery.is_empty() or int(entry.revision) >= 2147483646:
		return Runtime.fail("BUSY", "先完成或取消原交糧，再將舊共有糧落定岸格")
	var state: Dictionary = entry.sustain.duplicate(true)
	var at := Runtime.now(lab.terrain) * 60.0
	if not _align_supply_clock(state, at) or not Sustain.validate(state, captivity_supply._all_members()) or not Runtime._resource_stack(entry.inventory):
		return Runtime.fail("INVALID_SUSTAIN", "原供養時段／口糧未同步，未改餐份或物資")
	var location := {"inventory": entry.inventory.duplicate(true), "open_rations": float(state.open_rations)}
	var locations := {"shore:%d" % lab.terrain.index(shore): location}
	state["version"] = 2
	state.erase("open_rations")
	if not _supply_locations_valid(team, locations) or not Sustain.validate(state, captivity_supply._all_members()):
		return Runtime.fail("INVALID_SUSTAIN")
	if preview: return Runtime.ok("首次登船會將全部舊共有糧一次落在本人此岸格", {"locations": locations})
	if existing.is_empty():
		var enabled: Dictionary = captivity_supply.enable_team(team)
		if not enabled.ok: return enabled
		entry = enabled.entry
	entry.sustain.clear()
	entry.sustain.merge(state)
	entry.erase("inventory")
	entry["locations"] = locations
	entry["version"] = 3
	entry["revision"] = int(entry.revision) + 1
	return Runtime.ok("舊共有糧已一次落在本人此岸格；船上仍須實際裝糧")

func ship_retreat_shore_safe(team: Variant, shores: Array[Vector2i]) -> bool:
	var threats := {}
	for shore: Vector2i in shores:
		if lab.terrain.is_walkable(shore) and not lab._fatigue_threat(shore, team.faction_id, team, -1, threats):
			return true
	return false

func transfer_ship_supply(team: Variant, source_location: String, target_location: String, resources: Dictionary, open_amount: float, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	if region_operation_pending(): return Runtime.fail("BUSY", "原固定目標冷交換尚未完成，先等待再裝卸供養")
	var entry := _supply_entry(team)
	if entry.is_empty() or int(entry.version) != 3 or not entry.delivery.is_empty() or not _team_stopped(team): return Runtime.fail("BUSY")
	var arrived_unload: bool = not test_dispatch and not (team is CrowdOwner) and source_location.begins_with("vehicle:") and target_location.begins_with("shore:") and region_slot != null and region_slot._region_entered_npc_ship_unload_authorized(lab, team, requester_id, vehicles.records().get(source_location.trim_prefix("vehicle:"), {}))
	if not vehicles._authorized(team, requester_id, 0, test_dispatch) and not arrived_unload: return Runtime.fail("NO_AUTHORITY")
	if source_location == target_location or not _supply_locations_valid(team, entry.locations) or not entry.locations.has(source_location) or not _supply_location_valid(team, target_location): return Runtime.fail("INVALID_SUSTAIN")
	if not Runtime._resource_stack(resources) or not Sustain._number(open_amount, 0, 1000000.0) or resources.is_empty() and open_amount == 0.0: return Runtime.fail("INVALID")
	for resource: String in resources:
		if resource not in Sustain.FOODS: return Runtime.fail("INVALID")
	var source_ship := source_location.trim_prefix("vehicle:") if source_location.begins_with("vehicle:") else ""
	var target_ship := target_location.trim_prefix("vehicle:") if target_location.begins_with("vehicle:") else ""
	if not source_ship.is_empty() and not target_ship.is_empty(): return Runtime.fail("UNSUPPORTED", "首版船船轉糧須先卸到合法岸格")
	var person := _supply_person(requester_id)
	if person.is_empty() or not _delivery_person_ready(person): return Runtime.fail("BUSY")
	var ship_id := source_ship if not source_ship.is_empty() else target_ship
	if not ship_id.is_empty():
		var shore_key := target_location if target_ship.is_empty() else source_location
		var shore: Vector2i = lab.terrain.cell_from_index(int(shore_key.trim_prefix("shore:")))
		var vehicle: Dictionary = lab.terrain.site.vehicles[ship_id]
		if not vehicles.ship_supply_contact(vehicle, shore): return Runtime.fail("UNREACHABLE")
		if vehicles.is_embarked(requester_id):
			if str(vehicles.ship_for_person(requester_id).id) != ship_id: return Runtime.fail("UNREACHABLE")
		elif not _supply_shore_contact(person.cell, shore): return Runtime.fail("UNREACHABLE")
	else:
		var from: Vector2i = lab.terrain.cell_from_index(int(source_location.trim_prefix("shore:")))
		var to: Vector2i = lab.terrain.cell_from_index(int(target_location.trim_prefix("shore:")))
		if not _supply_shore_contact(person.cell, from) or not _supply_shore_contact(person.cell, to): return Runtime.fail("UNREACHABLE")
	var source: Dictionary = entry.locations[source_location]
	var destination: Dictionary = entry.locations.get(target_location, {"inventory": {}, "open_rations": 0.0})
	if not Runtime.can_pay(source.inventory, resources) or float(source.open_rations) + Sustain.EPS < open_amount: return Runtime.fail("MATERIALS")
	if int(entry.revision) >= 2147483646 or not Sustain._number(float(destination.open_rations) + open_amount, 0, 1000000.0): return Runtime.fail("STALE_SOURCE")
	for resource: String in resources:
		if int(destination.inventory.get(resource, 0)) + int(resources[resource]) > 1000000: return Runtime.fail("STORAGE_FULL")
	if not target_ship.is_empty() and vehicles.ship_load(target_ship) + float(Runtime.inventory_size(resources)) + open_amount > float(SiteVehicleTransport.capacity_of(lab.terrain.site.vehicles[target_ship])) + Sustain.EPS: return Runtime.fail("CAPACITY")
	var stock: Dictionary = entry.locations.duplicate(true)
	var state: Dictionary = entry.sustain.duplicate(true)
	if not stock.has(target_location): stock[target_location] = {"inventory": {}, "open_rations": 0.0}
	Runtime.add_items(stock[source_location].inventory, resources, -1)
	stock[source_location].open_rations = maxf(0.0, float(stock[source_location].open_rations) - open_amount)
	Runtime.add_items(stock[target_location].inventory, resources)
	stock[target_location].open_rations = float(stock[target_location].open_rations) + open_amount
	var members := _team_members(team)
	var context := {"food_locations": ship_food_locations(team, members, stock)}
	if not _align_supply_clock(state, Runtime.now(lab.terrain) * 60.0) or not _supply_locations_valid(team, stock): return Runtime.fail("INVALID_SUSTAIN")
	var supplied := Sustain.resupply(state, members, stock, false, _supply_team_hot_reader(team, members), {}, context)
	if not supplied.ok: return supplied
	for key: String in stock:
		if entry.locations.has(key):
			entry.locations[key].inventory.clear()
			entry.locations[key].inventory.merge(stock[key].inventory)
			entry.locations[key].open_rations = stock[key].open_rations
		else: entry.locations[key] = stock[key]
	entry.sustain.clear()
	entry.sustain.merge(state)
	entry.revision = int(entry.revision) + 1
	_observe_original_food_result("team", str(team.team_id), float(entry.sustain.at), supplied)
	return Runtime.ok("共有糧已由原接觸點實際搬移，原餐份只補當期未吃部分", {"consumed_rations": supplied.consumed_rations})

func _team_members(team: Variant) -> Dictionary:
	# G3: a crowd team's members are its native rows; a crowd team has no grid player_member.
	if team is CrowdOwner:
		return captivity_supply.team_members(team, team.original_members())
	var members := {}
	for index: int in team.combat_units.size():
		if team.is_member(index):
			members[team.combat_identity(index)] = team.combat_units[index]
	if is_instance_valid(team.player_member):
		members[team.player_member.person_id] = _actor_supply_adapter(team.player_member, team.player_present)
	return captivity_supply.team_members(team, members)

func _supply_team_hot_reader(team: Variant, members: Dictionary) -> Callable:
	# G3: crowd members read native hp, ko, captive and fatigue; other fields stay on the member snapshot.
	if team is CrowdOwner:
		return func(identity: int, field: StringName) -> Variant:
			if lab.crowd_site.contains_person(identity) and field in [&"hp", &"ko", &"captive", &"fatigue", &"fatigue_rest"]:
				var person_owner: Variant = lab.crowd_site.person_owner(identity)
				return person_owner.combat_hot_get(person_owner.index_for_identity(identity), field, 0.0)
			return members[identity].get(String(field))
	return _supply_hot_reader(team, members, {})

func _supply_hot_reader(team: TerrainArmy, members: Dictionary, changed_ids: Dictionary) -> Callable:
	var own_hot := team.combat_hot_active()
	var hp := team.combat_hot_column(&"hp") if own_hot else PackedFloat64Array()
	var ko := team.combat_hot_column(&"ko") if own_hot else PackedFloat64Array()
	var foreign: Array[TerrainArmy] = []
	for other: TerrainArmy in lab.combat_armies:
		if other != team and other.combat_hot_active():
			foreign.append(other)
	if not own_hot and foreign.is_empty() and not lab._region_deferring_endpoint():
		return Callable()
	return func(identity: int, field: StringName) -> Variant:
		if own_hot:
			var index := team.combat_hot_index_for_identity(identity)
			if index >= 0 and index < team.combat_units.size():
				if not changed_ids.has(identity):
					if field == &"hp": return hp[index]
					if field == &"ko": return ko[index]
				return team.combat_hot_get(index, field)
		for foreign_owner: TerrainArmy in foreign:
			var index := foreign_owner.combat_hot_index_for_identity(identity)
			if index >= 0 and index < foreign_owner.combat_units.size():
				return foreign_owner.combat_hot_get(index, field)
		return members[identity].get(String(field))

func _actor_supply_adapter(actor: TerrainTestCharacter, present: bool = false) -> Dictionary:
	var legacy_weapon := str(actor._saved_appearance.get("parts", {}).get("weapon", "none"))
	if actor.editor != null:
		var choice := actor.editor.part_options.get(&"weapon") as OptionButton
		if choice != null and choice.selected >= 0:
			legacy_weapon = str(choice.get_item_metadata(choice.selected))
	# Ephemeral field adapter; it is never stored in terrain.site.
	return {"person_id": actor.person_id, "hp": actor.hp, "ko": actor.knockout_left, "fatigue": actor.fatigue,
		"fatigue_rest": actor.fatigue_rest, "work_resting": actor.work_resting, "_fatigue_pool": actor._fatigue_pool,
		"present": present, "captive": actor.captive, "is_player": actor.person_id == lab.controlled_person_id(),
		"item_state": actor.get("item_state"), "legacy_weapon": legacy_weapon}

func _all_supply_members() -> Dictionary:
	return captivity_supply._all_members()

func _life(body: Dictionary, hot_read: Callable = Callable(), pending_hp: Dictionary = {}) -> int:
	var identity := int(body.person_id)
	var hp: Variant
	var ko: Variant
	if hot_read.is_valid():
		hp = hot_read.call(identity, &"hp")
		ko = hot_read.call(identity, &"ko")
	else:
		hp = body.get("hp")
		ko = body.get("ko", 0)
	if pending_hp.has(identity):
		hp = pending_hp[identity]
	return 2 if float(hp) <= 0 else (1 if float(ko) > 0 else 0)

func _enable_team_supply(team: Variant) -> Dictionary:
	var result: Dictionary = captivity_supply.enable_team(team)
	if not result.ok:
		show_result(result)
		return {}
	return result.entry

## P1k diagnostic: the first clause of _team_stopped that fails, with the member index and its values. Same reads, same order,
## writes nothing. Returns "ok" when _team_stopped would be true (for the crowd branch the same loop as _team_stopped).
func team_stopped_breakdown(team: Variant) -> String:
	if not team.combat_enabled: return "combat_enabled=false"
	if team.combat_order != TerrainArmy.CombatOrder.HOLD: return "combat_order=%s" % str(team.combat_order)
	if not vehicles.ships_stopped_for_team(team.team_id): return "ships_not_stopped"
	if team is CrowdPersonOwner:
		for index: int in team.combat_units.keys():
			if not team.is_member(index) or bool(team.combat_hot_get(index, &"site_exited", false)) \
				or bool(team.combat_hot_get(index, &"surrender_pending", false)) or bool(team.combat_hot_get(index, &"captive")):
				continue
			var state: Dictionary = team.person(index, false)
			var speed: float = team.drift_speed(index)
			if team.has_move_goal(index) or speed >= CrowdPersonOwner.SETTLE_SPEED:
				var here: Vector2 = Vector2(state.get("position", Vector2.ZERO)) / 64.0
				var last: Variant = crowd_probe_last.get(index)
				crowd_probe_last[index] = here
				var delta: float = (here - last).length() if last is Vector2 else -1.0
				return "walking:%d:id=%d:controlled=%s:speed=%.4f:delta_since_last_probe=%.4f:goal=%s:native_moving=%s:cell=%s:moving_to=%s:movement=%s" % [index, team.combat_identity(index), str(team.combat_identity(index) == lab.controlled_person_id()), speed, delta, str(team.has_move_goal(index)), str(state.get("moving", "")), str(state.get("cell", "")), str(team.moving_to[index]), str(team.native_siege_state(index))]
			if bool(team.combat_hot_get(index, &"attack")): return "attack:%d" % index
			var pose := str(team.combat_hot_get(index, &"pose"))
			if pose in ["guard", "guard_raise", "guard_lower", "guard_break", "rescue", "get_up"]: return "pose:%d:%s" % [index, pose]
		return "ok"
	return "grid_branch_not_diagnosed"

func _team_stopped(team: Variant, allow_sheltered: bool = false, ignored_ship_job: Dictionary = {}) -> bool:
	if not team.combat_enabled or (team.combat_order != TerrainArmy.CombatOrder.HOLD and not (allow_sheltered and team.morale_retreat_sheltered())):
		return false
	if ignored_ship_job.is_empty():
		if not vehicles.ships_stopped_for_team(team.team_id): return false
	else:
		for vehicle: Dictionary in vehicles.records().values():
			if SiteVehicleTransport.is_ship(vehicle) and int(vehicle.team_id) == team.team_id and not vehicle.move.is_empty(): return false
		for job: Dictionary in person_actions._jobs.values():
			if not str(job.get("kind", "")).begins_with("ship_") or is_same(job, ignored_ship_job): continue
			var person := vehicles.ship_person(int(job.get("executor_id", 0)))
			if not person.is_empty() and is_same(person.owner, team): return false
	# G8a: a crowd roster is checked natively before the grid member loop, which reads TerrainArmy-only
	# moving_to/combat_units. person(index) supplies the hot moving state for each member.
	if team is CrowdPersonOwner:
		for index: int in team.combat_units.keys():
			if not team.is_member(index) or bool(team.combat_hot_get(index, &"site_exited", false)) \
				or bool(team.combat_hot_get(index, &"surrender_pending", false)) or bool(team.combat_hot_get(index, &"captive")):
				continue
			var state: Dictionary = team.person(index, false)
			if team.is_walking(index) or bool(team.combat_hot_get(index, &"attack")) \
				or str(team.combat_hot_get(index, &"pose")) in ["guard", "guard_raise", "guard_lower", "guard_break", "rescue", "get_up"]:
				return false
		return true
	for index: int in range(team.combat_units.size()):
		if not team.is_member(index) or bool(team.combat_hot_get(index, &"site_exited", false)) \
			or bool(team.combat_hot_get(index, &"surrender_pending", false)) or bool(team.combat_hot_get(index, &"captive")):
			continue
		if team.moving_to[index] != TerrainArmy.INVALID_CELL or bool(team.combat_hot_get(index, &"attack")) or str(team.combat_hot_get(index, &"pose")) in ["guard", "guard_raise", "guard_lower", "guard_break", "rescue", "get_up"]:
			return false
	if not is_instance_valid(team.player_member):
		return true
	var actor: TerrainTestCharacter = team.player_member
	if actor.site_exited or actor.surrender_pending or actor.captive:
		return true
	# Stopped is a physical group condition, not this particular member's
	# capacity to receive food/train. An immobile casualty does not freeze peers.
	return not actor.is_moving() and actor.action_time <= 0.0 and not actor.guarding and actor.guard_transition_left <= 0.0 and actor.guard_break_left <= 0.0 and actor._rescue_left <= 0.0 and not actor._getting_up

func _supply_actor_ready(actor: TerrainTestCharacter) -> bool:
	return actor.can_act() and not actor.is_moving() and actor.action_time <= 0.0 and not actor.guarding and actor.guard_transition_left <= 0.0 and actor.guard_break_left <= 0.0 and actor._rescue_left <= 0.0

func team_food_capacity(team: Variant) -> float:
	var capacity := 0.0
	# P1e: a crowd owner keys its rows by index and keeps logistics in its cold row; it has no player_member.
	var indices: Array = team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())
	for index: Variant in indices:
		if team_carrier_contributes(team, int(index)):
			var logistic: bool = bool(team._cold_get(int(index), "logistics", false)) if team is CrowdPersonOwner else bool(team.combat_units[int(index)].get("logistics", false))
			capacity += 6.0 if logistic else 3.0
	var player_member: Variant = null if team is CrowdPersonOwner else team.player_member
	if is_instance_valid(player_member):
		var actor: TerrainTestCharacter = player_member
		if actor.can_act() or actor.site_exited and actor.hp > 0.0 and actor.knockout_left <= 0.0 \
			and not actor.captive and not actor.surrender_pending and not actor._getting_up:
			capacity += 3.0
	return capacity

## Does this member carry food now (the one rule team_food_capacity and the
## logistics AI share, F03)? Leaving this Site removes spatial actions, not the
## original carrier or its share of this same Army's food. Death/KO/captivity
## still lose capacity.
func team_carrier_contributes(team: Variant, index: int) -> bool:
	var exited_carrier := bool(team.combat_hot_get(index, &"site_exited", false)) \
		and float(team.combat_hot_get(index, &"hp")) > 0.0 and float(team.combat_hot_get(index, &"ko")) <= 0.0 \
		and str(team.combat_hot_get(index, &"pose")) != "get_up" and not bool(team.combat_hot_get(index, &"captive")) \
		and not bool(team.combat_hot_get(index, &"departed")) and not bool(team.combat_hot_get(index, &"surrender_pending", false))
	return team.is_member(index) and (team.combat_can_act(index) or exited_carrier)

func order_team_logistics(team: TerrainArmy, identities: Array[int], requester_id: int, enabled: bool) -> Dictionary:
	if team == null or not team.combat_enabled or get_tree().paused or bool(lab.terrain.site.paused):
		return Runtime.fail("BUSY")
	team.settle_combat_command()
	var refused := team.duty_authority("team.logistics", requester_id)
	if not refused.is_empty():
		return refused
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
		if not entry.is_empty() and Sustain.rations(entry.sustain, _supply_stock(entry)) > reduced_capacity + 0.000000001:
			return Runtime.fail("STORAGE_FULL", "解除後勤會超載；請先實際交付共有口糧，不靜默丟物或帶超額出發")
	for identity: int in identities:
		team.combat_units[team.index_for_identity(identity)].logistics = enabled
	return Runtime.ok("已指定原人物專職後勤，每名可搬運者6日份；不另生貨物" if enabled else "已解除原人物專職後勤，恢復3日份載量")

## P1o: a member counts as walking for supply readiness. A crowd member uses the crowd settle rule (CrowdPersonOwner.is_walking);
## a grid member keeps its strict moving flag, unchanged.
func _supply_walking(person: Dictionary) -> bool:
	if person.owner is CrowdPersonOwner and int(person.unit) >= 0: return bool(person.owner.is_walking(int(person.unit)))
	return bool(person.moving)

## P1o diagnostic: every clause of _delivery_person_ready for one person, with values. Writes nothing.
func delivery_person_breakdown(person: Dictionary) -> String:
	if person.is_empty(): return "empty"
	var identity := int(person.person_id)
	var text := "id=%d busy=%s guarding=%s assigned=%s operator=%s" % [identity, str(person_actions.is_busy(identity)), str(person_actions.is_guarding(identity)), str(work_team.is_assigned(identity)), str(vehicles.is_operator(identity))]
	if int(person.unit) >= 0:
		var unit := int(person.unit)
		text += " cell=%s can_act=%s" % [str(person.cell), str(person.owner.combat_can_act(unit))]
		if person.owner is CrowdPersonOwner: text += " speed=%.4f goal=%s walking=%s" % [float(person.owner.drift_speed(unit)), str(person.owner.has_move_goal(unit)), str(_supply_walking(person))]
		else: text += " moving=%s" % str(person.moving)
		text += " attack=%s pose=%s work_task_empty=%s" % [str(person_actions._body_get(person, "attack")), str(person_actions._body_get(person, "pose")), str(person.body.get("work_task", {}).is_empty())]
	return text

func _delivery_person_ready(person: Dictionary, ignored_job: Dictionary = {}) -> bool:
	if person.is_empty(): return false
	var own_job := not ignored_job.is_empty() and int(ignored_job.get("executor_id", 0)) == int(person.person_id) and is_same(person_actions._jobs.get(str(person.person_id), {}), ignored_job)
	if person_actions.is_busy(int(person.person_id)) and not own_job or person_actions.is_guarding(int(person.person_id)) or work_team.is_assigned(int(person.person_id)) or vehicles.is_operator(int(person.person_id)):
		return false
	if int(person.unit) >= 0:
		if vehicles.is_embarked(int(person.person_id)) and not person.owner.is_member(int(person.unit)):
			return int(person.person_id) == lab.controlled_person_id() and float(person.hp) > 0.0 and float(person.ko) <= 0.0 and not bool(person.captive) and not _supply_walking(person) and not bool(person_actions._body_get(person, "attack")) and str(person_actions._body_get(person, "pose")) == "idle" and person.body.get("work_task", {}).is_empty()
		return person.owner.combat_can_act(int(person.unit)) and not _supply_walking(person) and not bool(person_actions._body_get(person, "attack")) and str(person_actions._body_get(person, "pose")) == "idle" and person.body.get("work_task", {}).is_empty()
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

func begin_team_food(team: Variant, quantity: float, representative_id: int, source: Dictionary = {}) -> Dictionary:
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

func _delivery_valid(team: Variant, entry: Dictionary) -> bool:
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
			bound = minf(bound, maxf(0.0, PersonFatigue.WORK_REST_AT - float(person_actions._body_get(person, "fatigue"))) / PersonFatigue.effort_rate(person.body))
	var wanted := float(entry.delivery.left)
	var productive := INF
	for person: Dictionary in people:
		productive = minf(productive, PersonFatigue.work_seconds(float(person_actions._body_get(person, "fatigue")), bound, PersonFatigue.effort_rate(person.body)))
	if productive <= wanted:
		return maxf(0.000000001, bound)
	var lower := 0.0
	var upper := bound
	for iteration: int in 40:
		var middle := (lower + upper) * 0.5
		var effort := INF
		for person: Dictionary in people:
			effort = minf(effort, PersonFatigue.work_seconds(float(person_actions._body_get(person, "fatigue")), middle, PersonFatigue.effort_rate(person.body)))
		if effort < wanted:
			lower = middle
		else:
			upper = middle
	return upper

func _finish_delivery_step(team: Variant, entry: Dictionary, seconds: float) -> void:
	if entry.delivery.is_empty() or bool(entry.delivery.get("pending", false)):
		return
	if not _delivery_valid(team, entry):
		entry["delivery"] = {}
		message.text = "交糧條件已變更，當批取消；來源未扣物"
		return
	if not _shared_work_plan.is_empty():
		var allocation: Dictionary = _shared_work_plan.get("jobs", {}).get("delivery", {}).get(str(team.team_id), {})
		if allocation.is_empty(): return
		for person: Dictionary in _delivery_people(entry):
			var actual := float(allocation.get("participant_seconds", {}).get(int(person.person_id), 0.0))
			if int(person.person_id) != lab.controlled_person_id(): person_actions._body_set(person, "work_resting", str(allocation.get("paused", "")) == "REST")
			if int(person.unit) < 0: lab._fatigue_work_seconds[person.owner] = float(lab._fatigue_work_seconds.get(person.owner, 0.0)) + actual
		entry.delivery.left = maxf(0.0, float(entry.delivery.left) - float(allocation.get("effective_seconds", 0.0)))
		if float(entry.delivery.left) <= 0.00000001:
			entry.delivery.left = 0.0
			entry.delivery.pending = true
		return
	if not _delivery_active(entry):
		return # Original safe-rest loop recovers 80->50; original job stays queued.
	var productive := INF
	for person: Dictionary in _delivery_people(entry):
		var fatigue := float(person_actions._body_get(person, "fatigue"))
		productive = minf(productive, PersonFatigue.work_seconds(fatigue, seconds, PersonFatigue.effort_rate(person.body)))
		var updated := PersonFatigue.advance(fatigue, float(person_actions._body_get(person, "fatigue_rest")), seconds, PersonFatigue.effort_rate(person.body), false)
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
	supply_settle_runs += 1
	# P1e: grid armies, or the native crowd owners while the crowd is active (team_owners). Completion is not peace-gated: it only
	# commits a delivery that was started in peace, and moves no one.
	for team: Variant in lab.team_owners():
		var entry := _supply_entry(team)
		if entry.is_empty():
			continue
		if not entry.delivery.is_empty() and bool(entry.delivery.get("pending", false)):
			supply_settle_pending += 1
			# P1i diagnostic: why the completion commit refuses (the entry is cleared on refusal). Read before commit, no writes.
			var pre_valid: bool = food_delivery.valid(team, entry)
			var pre_stopped: bool = _team_stopped(team)
			var pre_code := "" if pre_valid else ("STOPPED" if not pre_stopped else "VALID_FALSE")
			var pre_why: String = food_delivery.valid_breakdown(team, entry)
			var result := food_delivery.commit(team, entry)
			supply_settle_result = result.duplicate(true) # P1r diagnostic: the last completion result (consumed_rations on success)
			supply_settle_last = "owner=%d pre_valid=%s pre_stopped=%s pre_code=%s why=%s commit=%s msg=%s" % [int(team.team_id), str(pre_valid), str(pre_stopped), pre_code, pre_why, str(result.get("code", "")), str(result.get("message", ""))]
			if result.ok: _observe_original_food_result("team", str(team.team_id), float(entry.sustain.at), result)
			if not result.ok:
				entry.delivery = {}
			message.text = str(result.message)
		# Post-contact/death landing. Later losses, an actual retreat, or total
		# incapacitation may require another excess drop without a morale rout.
		var dropped := food_delivery.drop_excess(team)
		if dropped.ok and dropped.has("container_id"):
			message.text = "超額共有口糧已一次留在原人物現場；敵我均須實際接近搬取"

func order_controlled_training(enabled: bool, training_feature: String = "") -> Dictionary:
	if _crowd_active() and lab.crowd_site.contains_person(lab.controlled_person_id()):
		var owner_ref: RefCounted = lab.crowd_site.person_owner(lab.controlled_person_id())
		return order_team_training(owner_ref, owner_ref.index_for_identity(lab.controlled_person_id()), enabled, training_feature)
	var team: Variant = _chosen_supply_team()
	return order_team_training(team, lab.controlled_member_index(team), enabled, training_feature)

func order_team_training(team: Variant, requester: int, enabled: bool, training_feature: String = "") -> Dictionary:
	if team == null or not team.combat_enabled:
		return Runtime.fail("NO_TARGET")
	if get_tree().paused or bool(lab.terrain.site.paused): return Runtime.fail("BUSY", "暫停時不下訓練令")
	var identity: int = team.combat_identity(requester)
	if not enabled:
		var current := _supply_entry(team)
		if current.is_empty(): return Runtime.ok("目前没有訓練命令")
		if bool(current.get("training_order", false)) and team is TerrainArmy:
			# Stop belongs to whoever exercises team.training now (incl. acting head), 3.6.
			var refused: Dictionary = team.duty_authority("team.training", identity)
			if not refused.is_empty(): return refused
		elif identity != int(current.training_requester): return Runtime.fail("NO_AUTHORITY", "須由原下令軍官停止訓練")
		TrainingGround.stop(current)
		return Runtime.ok("已停止訓練；保留既有訓練與疲勞")
	var checked := TrainingGround.inspect(self, int(team.team_id), training_feature)
	if not checked.ok: return checked
	if checked.owner is TerrainArmy:
		var refused: Dictionary = checked.owner.duty_authority("team.training", identity)
		if not refused.is_empty(): return refused
	elif identity != int(checked.commander_id):
		return Runtime.fail("NO_AUTHORITY", "只有當前在場合格指揮者可下訓練令")
	if not bool(checked.safe):
		return Runtime.fail("BUSY", "須先守位停止並脫戰")
	var prepared: Dictionary = captivity_supply.enable_team(checked.owner)
	if not prepared.ok: return prepared
	var entry: Dictionary = prepared.entry
	if int(entry.get("version", 1)) < 2: entry["version"] = 2
	entry["training_order"] = true
	entry["training_requester"] = identity
	entry["training_feature_id"] = str(checked.feature_id)
	var facility: Dictionary = lab.terrain.site.features.get(str(checked.feature_id), {})
	return Runtime.ok("在%s #%s 訓練；離場、移動或原軍官離任即停止，缺糧／威脅／疲勞依原規則暫停" % [_building_name(facility), checked.feature_id])

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
		if team.is_member(index) and not bool(team.combat_hot_get(index, &"captive")) \
			and not bool(team.combat_hot_get(index, &"site_exited", false)) and not bool(team.combat_hot_get(index, &"surrender_pending", false)) \
			and float(team.combat_hot_get(index, &"hp")) > 0 and lab._fatigue_threat(vehicles.ship_person_cell(team.combat_identity(index)) if vehicles.is_embarked(team.combat_identity(index)) else team.cells[index], team.faction_id, team, index, candidates):
			return false
	if is_instance_valid(team.player_member) and members.has(team.player_member.person_id) and team.player_member.hp > 0 \
		and not team.player_member.site_exited and not team.player_member.surrender_pending and not team.player_member.captive \
		and lab._fatigue_threat(team.player_member.terrain_cell, team.faction_id, team.player_member, -1, candidates):
		return false
	return true

func _observe_team_life(team: TerrainArmy, entry: Dictionary, members: Dictionary, hot_read: Callable = Callable()) -> void:
	var deaths := 0
	var knockouts := 0
	var living_before := 0
	for key: String in entry.life_checkpoint:
		if team.index_for_identity(int(key)) < 0:
			continue # Feeding a foreign captive is not enrolling a combatant.
		var old := int(entry.life_checkpoint[key])
		living_before += int(old != 2)
		if members.has(int(key)):
			var current := _life(members[int(key)], hot_read)
			deaths += int(current == 2 and old != 2)
			knockouts += int(current == 1 and old == 0)
	var qualified := team.current_commander >= 0 and team.command_eligible(team.current_commander)
	if living_before > 0 and (deaths > 0 or knockouts > 0 or bool(entry.sustain.commander_present) != qualified):
		var leadership := _team_ability(team, "leadership")
		Sustain.combat_event(entry.sustain, int(entry.sustain.last_combat_event) + 1, living_before, deaths, knockouts, qualified, leadership)
	for id: Variant in members:
		entry.life_checkpoint[str(id)] = _life(members[id], hot_read)

func _team_ability(team: TerrainArmy, kind: String) -> float:
	var value := 0.0
	for index: int in team.command_abilities:
		if team.command_eligible(index):
			value += float(team.command_abilities[index].get(kind, 0))
	if is_instance_valid(team.player_member) and team.command_eligible(TerrainArmy.PLAYER_MEMBER):
		value += float(team.player_member.command_abilities.get(kind, 0))
	return value

## R6 S6C (plan 10.1 退隊 with 供養歸屬, the R6S6B decisions): a team member leaves the team and the team's sustain supply in one
## call. The team's cohorts release the leaver (dependents stay with the team; an emptied cohort is removed; the leaver gets a free
## person state under its person key carrying its current values). Everything is computed and validated first; the roster and seats
## leave through the team's depart_member; the supply is written only after that succeeds. Any refusal changes nothing.
func depart_team_member(team: TerrainArmy, person_id: int, authority: Dictionary = {}) -> Dictionary:
	# R7 C1: membership_change (the roster hook every membership flip uses) is the single supply writer for a team departure.
	# The seats vacate and the roster leave run through team.depart_member; no separate team-sustain release is written here.
	return team.depart_member(person_id, authority)

func advance_team_sustain(team: TerrainArmy, elapsed_game_seconds: float) -> Dictionary:
	# Root calls this ONLY from the existing common Site action step, not tick().
	var handled := {}
	if not lab._gd_mesh_work_point.is_empty(): return {"handled_ids": [], "handled_seconds": handled}
	var entry := _supply_entry(team)
	if entry.is_empty() or elapsed_game_seconds <= 0 or get_tree().paused or bool(lab.terrain.site.paused):
		return {"handled_ids": [], "handled_seconds": handled}
	if int(entry.version) == 3 and not _supply_locations_valid(team, entry.locations):
		message.text = "隊伍位置供養資料無效，未推進"
		return {"handled_ids": handled.keys(), "handled_seconds": handled}
	var left := elapsed_game_seconds
	while left > 0.000000001:
		if not entry.delivery.is_empty() and not _delivery_valid(team, entry):
			entry.delivery = {}
			message.text = "交糧中止；來源未扣物"
		var seconds := left if not _shared_work_plan.is_empty() else _delivery_seconds(entry, left)
		var members := _team_members(team)
		var changed_ids := {}
		var hot_read := _supply_hot_reader(team, members, changed_ids)
		var pending_hp := {}
		if int(entry.version) == 3 and not Sustain.validate(entry.sustain, members, hot_read):
			message.text = "原隊伍餐份／人物資料無效，未推進"
			return {"handled_ids": handled.keys(), "handled_seconds": handled}
		var was_routed := bool(entry.sustain.routed)
		_observe_team_life(team, entry, members, hot_read)
		var safe := _team_safe(team, members)
		var stopped := _team_stopped(team, true)
		var hp_before := {}
		for id: Variant in members:
			hp_before[id] = float(Sustain._member_value(members, int(id), &"hp", hot_read))
		var context := {"safe": safe, "stopped": stopped, "hot_read": hot_read, "pending_hp": pending_hp}
		if int(entry.version) == 3: context["food_locations"] = ship_food_locations(team, members)
		var outcome := Sustain.advance_to(entry.sustain, members, _supply_stock(entry), float(entry.sustain.at) + seconds, context)
		if not outcome.ok:
			message.text = "隊伍供養資料無效，未推進：" + str(outcome.message)
			return {"handled_ids": handled.keys(), "handled_seconds": handled}
		if float(outcome.consumed_rations) > 0:
			entry.revision = int(entry.revision) + 1
		for id: Variant in outcome.damage:
			# Sustain has already settled an exact zero endpoint. Forward that
			# result through the original death entrypoint, not a subtractive tail.
			var ending_hp := float(pending_hp[id]) if hot_read.is_valid() else float(members[id].hp)
			var loss := float(hp_before[id]) if ending_hp == 0.0 else float(outcome.damage[id])
			if hot_read.is_valid():
				pending_hp[int(id)] = _apply_supply_damage(int(id), loss)
				changed_ids[int(id)] = true
			else:
				members[id].hp = float(hp_before[id])
				members[id].hp = _apply_supply_damage(int(id), loss)
		for id: Variant in members:
			entry.life_checkpoint[str(id)] = _life(members[id], hot_read, pending_hp) # Hunger isn't a combat casualty event.
		_publish_sustain_team_commands(team, entry, was_routed, outcome, seconds, safe, stopped)
		var fed: bool = not entry.sustain.cohorts.is_empty()
		for cohort: Dictionary in entry.sustain.cohorts:
			if float(cohort.coverage) < 1.0:
				fed = false
		if bool(entry.training_order):
			var field := TrainingGround.inspect(self, team.team_id, str(entry.get("training_feature_id", "")))
			# Handing team.training to another seat is a handover, not a cancel
			# (OFFICE plan 3.6): only the physical field check or the issuer
			# actually leaving (death, departure, transfer) ends the order.
			var issuer_index := team.index_for_identity(int(entry.training_requester))
			var issuer_gone := issuer_index < 0 or team.member_gone(issuer_index)
			if not field.ok or issuer_gone:
				TrainingGround.stop(entry)
				message.text = "校場訓練已停止：" + str(field.get("message", "原下令者已離任"))
			var eligible: Array = field.get("eligible_ids", []) if bool(entry.training_order) else []
			var training_context := {"ordered": bool(entry.training_order), "commander": team.command_eligible(team.current_commander),
				"safe": safe and bool(field.get("safe", false)), "stopped": stopped, "fed": fed, "routed": bool(entry.sustain.routed), "coach": _team_ability(team, "coach"),
				"controlled_person_id": lab.controlled_person_id(), "hot_read": hot_read, "pending_hp": pending_hp,
				"training_multiplier": field.get("training_multiplier", 1.0)}
			if not _shared_work_plan.is_empty(): training_context["work_plan"] = _shared_work_plan
			var training := Sustain.train(team.training, members, eligible, seconds, training_context)
			if training.ok:
				team.training = float(training.training)
				for id: Variant in training.handled_ids:
					handled[id] = float(handled.get(id, 0.0)) + float(training.effort_seconds.get(id, seconds))
					if not _shared_work_plan.is_empty() and int(id) != lab.controlled_person_id():
						var allocation: Dictionary = _shared_work_plan.jobs.get("training", {}).get(str(int(id)), {})
						members[id].work_resting = str(allocation.get("paused", "")) == "REST"
		for original: TerrainTestCharacter in lab.combat_actors:
			if members.has(original.person_id):
				var adapter: Dictionary = members[original.person_id]
				if original._fatigue_pool.is_empty():
					original.fatigue = PersonFatigue.read(adapter)
					original.fatigue_rest = PersonFatigue.read(adapter, "fatigue_rest")
				original.work_resting = bool(adapter.work_resting)
		if not entry.delivery.is_empty() and _delivery_valid(team, entry):
			var allocation: Dictionary = _shared_work_plan.get("jobs", {}).get("delivery", {}).get(str(team.team_id), {})
			if not _shared_work_plan.is_empty() or _delivery_active(entry):
				for person: Dictionary in _delivery_people(entry):
					if int(person.unit) >= 0:
						var identity := int(person.person_id)
						var actual := float(allocation.get("participant_seconds", {}).get(identity, 0.0)) if not _shared_work_plan.is_empty() else seconds
						handled[identity] = float(handled.get(identity, 0.0)) + actual
		_finish_delivery_step(team, entry, seconds)
		_observe_original_food_result("team", str(team.team_id), float(entry.sustain.at), outcome)
		left -= seconds
	return {"handled_ids": handled.keys(), "handled_seconds": handled}

# P1g diagnostics (read by the crowd food test): how often the crowd sustain runs, why it skipped, and the last delivery slice.
var crowd_sustain_runs := 0
var crowd_sustain_skip := ""
var crowd_delivery_steps := 0
var crowd_delivery_last := ""
var supply_settle_runs := 0
var supply_settle_pending := 0
var supply_settle_last := ""
var supply_settle_result: Dictionary = {}
var crowd_probe_last: Dictionary = {} # P1m diagnostic: last member position (cells) per index, for the walking breakdown

# P1p: the crowd food-delivery timer is not advanced per crowd step (that wrote the delivery state inside the prepared native
# work point and latched STALE_NATIVE_WORK_POINT). It advances in the shared point tail: finish_shared_native_delivery_prefix.


func advance_crowd_sustain(elapsed_game_seconds: float) -> void:
	if not _crowd_active() or elapsed_game_seconds <= 0.0 or get_tree().paused or bool(lab.terrain.site.paused):
		crowd_sustain_skip = "active=%s elapsed=%.4f paused=%s site_paused=%s" % [str(_crowd_active()), elapsed_game_seconds, str(get_tree().paused), str(bool(lab.terrain.site.paused))]
		return
	crowd_sustain_runs += 1
	# Same-call projection only. With observers, retain each first-read sample
	# across damage callbacks; people not read yet must then sample current native state.
	var deferred_native: bool = lab._region_deferring_endpoint()
	var life := PackedFloat64Array()
	if not deferred_native and lab.crowd_site.crowd.has_method("get_life_states"):
		life = lab.crowd_site.crowd.get_life_states()
		if life.size() != int(lab.crowd_site.crowd.soldier_count()) * 3: life = PackedFloat64Array()
	# Closures share this box; an unobserved call keeps its existing allocation-free reads.
	var bulk_window: Variant = null
	if not lab.crowd_site.get_signal_connection_list("events_received").is_empty(): bulk_window = {"open": true}
	var samples := {}
	var original_checkpoint: bool = get_script() == SiteController and bulk_window != null
	# The native query is only a borrowed life projection. Observer/custom-owner
	# paths keep the existing lazy reads and callback ordering in full.
	var native_sample: bool = get_script() == SiteController and bulk_window == null and not life.is_empty() \
		and lab.crowd_site.get_script() != null and lab.crowd_site.get_script().resource_path == "res://scripts/terrain_lab/crowd_site.gd" \
		and lab.crowd_site.crowd.get_script() == null and lab.crowd_site.crowd.get_class() == "ArmyCrowd" \
		and captivity_supply.get_script() == CaptivitySupply
	var feeding: Dictionary = captivity_supply.feeding_index()
	for team_owner: RefCounted in lab.crowd_site.person_owners():
		var entry := _supply_entry(team_owner)
		if entry.is_empty(): continue
		var originals := {}
		for index: int in team_owner.records:
			originals[team_owner.combat_identity(index)] = team_owner.records[index]
		for index: int in team_owner.actors:
			originals[team_owner.combat_identity(index)] = _actor_supply_adapter(team_owner.actors[index])
		var members: Dictionary = captivity_supply.team_members(team_owner, originals, feeding, lab.crowd_site._records)
		# G3: split-shore and ship supply read each member's native cell; the grid path sets the same key.
		var food_locations: Variant = ship_food_locations(team_owner, members) if int(entry.get("version", 1)) == 3 else null
		var native_life: Dictionary = {"life": life, "indices": lab.crowd_site._index_by_id} if native_sample and team_owner.get_script() == CrowdPersonOwner \
			and entry.get("life_checkpoint") is Dictionary and not entry.life_checkpoint.is_typed() and not entry.life_checkpoint.is_read_only() else {}
		var hot_read := func(identity: int, field: StringName) -> Variant:
			if field == &"hp" and deferred_native: return lab.crowd_site.work_fatigue_forecast_hp(identity)
			if field == &"hp" or field == &"ko" or field == &"captive":
				# Same-call samples survive mapping edits; use their original index/value.
				var cached: Variant = samples.get(identity)
				if cached is int:
					if field == &"hp": return life[cached * 3]
					if field == &"ko": return life[cached * 3 + 1]
					return bool(life[cached * 3 + 2])
				if cached is PackedFloat64Array and not cached.is_empty():
					if field == &"hp": return cached[0]
					if field == &"ko": return cached[3]
					return bool(cached[6])
				var index := int(lab.crowd_site._index_by_id.get(identity, -1))
				if not life.is_empty():
					var bulk_index := index
					if samples.has(identity):
						bulk_index = int(samples[identity]) if samples[identity] is int else -1
					elif bulk_window != null:
						if index >= 0 and bool(bulk_window.open): samples[identity] = index
						else: bulk_index = -1
					if bulk_index >= 0:
						if field == &"hp": return life[bulk_index * 3]
						if field == &"ko": return life[bulk_index * 3 + 1]
						return bool(life[bulk_index * 3 + 2])
				if index >= 0:
					if not samples.has(identity) or samples[identity].is_empty():
						samples[identity] = lab.crowd_site.crowd.get_soldier_state(index)
				if samples.has(identity):
					var values: PackedFloat64Array = samples[identity]
					if field == &"hp": return values[0]
					if field == &"ko": return values[3]
					return bool(values[6])
			elif lab.crowd_site.contains_person(identity):
				var person_owner: RefCounted = lab.crowd_site.person_owner(identity)
				return person_owner.combat_hot_get(person_owner.index_for_identity(identity), field, 0.0)
			return members.get(identity, {}).get(field, 0.0)
		var pending_hp := {}
		var old_morale := float(entry.sustain.morale)
		var old_routed := bool(entry.sustain.routed)
		var old_regroup := float(entry.sustain.regroup_seconds)
		var morale_delta := 0.0
		var fully_fed := true
		var left := elapsed_game_seconds
		while left > 0.000000001:
			# Sustain owns meals/hunger. Its bounded neutral score extracts only
			# meal/shortage delta; native alone owns actual morale/rout/regroup.
			entry.sustain.morale = 50.0
			entry.sustain.routed = false
			entry.sustain.regroup_seconds = 0.0
			var seconds := minf(left, 600.0)
			var at := float(entry.sustain.at)
			# Bound the neutral morale slice without resupplying or reading people
			# twice. advance_to still validates the complete original state first.
			if entry.sustain.get("cohorts") is Array:
				for cohort: Variant in entry.sustain.cohorts:
					if cohort is Dictionary and Sustain._number(cohort.get("meal_until"), 0):
						var until := float(cohort.meal_until)
						if until <= at: until = Sustain._next_meal(at)
						seconds = minf(seconds, until - at)
			var context := {"safe": false, "stopped": false, "hot_read": hot_read, "pending_hp": pending_hp}
			if food_locations is Dictionary: context["food_locations"] = food_locations
			var outcome := Sustain._advance_with_life_sample(entry.sustain, members, _supply_stock(entry), float(entry.sustain.at) + seconds, context, native_life) \
				if not native_life.is_empty() else Sustain.advance_to(entry.sustain, members, _supply_stock(entry), float(entry.sustain.at) + seconds, context)
			if not outcome.ok:
				_auto_save_blocked = true
				show_result(outcome)
				break
			fully_fed = fully_fed and bool(outcome.fully_fed)
			morale_delta += float(entry.sustain.morale) - 50.0
			if float(outcome.consumed_rations) > 0.0: entry.revision = int(entry.revision) + 1
			for identity: Variant in outcome.damage:
				native_life.clear()
				native_sample = false
				var before := float(hot_read.call(int(identity), &"hp"))
				var loss := before if float(pending_hp[identity]) == 0.0 else float(outcome.damage[identity])
				pending_hp[int(identity)] = _apply_supply_damage(int(identity), loss)
				if bulk_window != null: bulk_window.open = false
				samples[int(identity)] = PackedFloat64Array() # Damage invalidates this person's bulk sample too.
			left -= seconds
		entry.sustain.morale = old_morale
		entry.sustain.routed = old_routed
		entry.sustain.regroup_seconds = old_regroup
		if native_life.has("checkpoints"):
			entry.life_checkpoint.merge(native_life.checkpoints, true)
		else:
			for identity: int in members:
				if original_checkpoint:
					var body_identity := int(members[identity].person_id)
					var cached: Variant = samples.get(body_identity)
					if cached is int:
						var hp: Variant = life[cached * 3]
						var ko: Variant = life[cached * 3 + 1]
						if pending_hp.has(body_identity):
							hp = pending_hp[body_identity]
						entry.life_checkpoint[str(identity)] = 2 if float(hp) <= 0 else (1 if float(ko) > 0 else 0)
						continue
				entry.life_checkpoint[str(identity)] = _life(members[identity], hot_read, pending_hp)
		lab.crowd_site.set_sustain_input(team_owner.formation_index, fully_fed, morale_delta)
		if not deferred_native and lab._shared_work_plan.is_empty():
			TrainingGround.advance_native(self, team_owner, entry, elapsed_game_seconds, fully_fed)

func team_is_routed(team: TerrainArmy) -> bool:
	var entry := _supply_entry(team)
	return not entry.is_empty() and bool(entry.sustain.routed)

func _start_supply_rout(team: TerrainArmy) -> void:
	# Sustain owns collapse; the original Army owns withdrawal and physical steps.
	if team_is_routed(team) and not team.morale_retreat_terminal():
		team.begin_morale_retreat()

func move_team_supply_members(source: TerrainArmy, target: TerrainArmy, ids: Array[int]) -> Dictionary:
	# Military registration is not always feeding ownership (captives/personal
	# meals). Resolve and preflight all original cohort moves before row mutation.
	if Runtime.ship_build_uses_team(lab.terrain, source.team_id) or Runtime.ship_build_uses_team(lab.terrain, target.team_id) or Runtime.ship_repair_uses_team(lab.terrain, source.team_id) or Runtime.ship_repair_uses_team(lab.terrain, target.team_id):
		return Runtime.fail("BUSY", "先完成或取消原隊造船批次，再拆併原名冊")
	return captivity_supply.move_roster(source, target, ids)

func before_clear_team_supply(team: TerrainArmy) -> void:
	# Explicit test-roster removal does not erase stock still at its supply owner.
	var entry := _supply_entry(team)
	if entry.is_empty():
		return
	entry.delivery = {}
	if is_instance_valid(team.player_member):
		player_supply_change(team, team.player_member, false)
	TrainingGround.stop(entry)
	entry.sustain.cohorts = []
	entry.life_checkpoint = {}
	if int(entry.version) == 3:
		for key: String in entry.locations.keys():
			var stock: Dictionary = entry.locations[key]
			if key.begins_with("vehicle:") and Sustain.rations(stock, stock.inventory) <= Sustain.EPS: entry.locations.erase(key)

func _align_supply_clock(state: Dictionary, at_seconds: float) -> bool:
	if state.cohorts.is_empty() and float(state.at) < at_seconds:
		# An empty former owner may legitimately lag in a saved Site. Advancing
		# no members consumes no food and preserves opened stock; never skip a
		# populated owner's hunger interval or wind a future state backwards.
		var advanced := Sustain.advance_to(state, {}, {}, at_seconds, {"food_locations": {}} if int(state.version) == 2 else {})
		if not advanced.ok:
			return false
	if absf(float(state.at) - at_seconds) > 0.00001:
		return false
	state["at"] = at_seconds
	for cohort: Dictionary in state.cohorts:
		if absf(float(cohort.meal_until) - at_seconds) <= 0.00001:
			cohort.meal_until = at_seconds
	return true

func player_supply_change(team: TerrainArmy, actor: TerrainTestCharacter, joining: bool) -> Dictionary:
	# Same original membership transaction for Actors and Army rows, including
	# the captor's dependent meal histories; never move shared/private stock.
	return _ship_membership_change(team, actor.person_id, joining)

func _apply_supply_damage(identity: int, loss: float) -> float:
	if _crowd_active() and lab.crowd_site.contains_person(identity):
		return lab.crowd_site.apply_environment_damage(identity, loss)
	var person: Dictionary = lab._original_person_target(identity)
	if person.is_empty():
		return 0.0
	var before_hp: float = float(person.owner.combat_hot_get(int(person.unit), &"hp")) if int(person.unit) >= 0 else float(person.owner.hp)
	var deferred: bool = lab._region_deferring_endpoint()
	var packet := {"result": {"hp": loss, "stun": 0.0, "guard_break": false}, "shield": false, "environmental": true}
	if int(person.unit) >= 0:
		person.owner.apply_unit_contact(int(person.unit), packet)
		return maxf(0.0, before_hp - loss) if deferred else float(person.owner.combat_hot_get(int(person.unit), &"hp"))
	person.owner.apply_contact(packet)
	return maxf(0.0, before_hp - loss) if deferred else float(person.owner.hp)

func advance_person_supply(elapsed_game_seconds: float) -> void:
	if not lab._gd_mesh_work_point.is_empty(): return # Same window was published chronologically by its original point.
	if elapsed_game_seconds <= 0 or get_tree().paused or bool(lab.terrain.site.paused):
		return
	for owner_id: String in lab.terrain.site.get("person_supply", {}):
		var personal: Dictionary = lab.terrain.site.person_supply[owner_id]
		if personal.is_empty():
			continue
		var person := _supply_person(int(owner_id))
		if person.is_empty():
			message.text = "個人供養原人物不存在，保留其原物资與餐份資料"
			continue
		var joint_supply: Dictionary = lab._native_begin_shared_window_prepared.get("sustain", {})
		if native_sustain_point_covers_person(joint_supply, int(owner_id)): continue
		var members := captivity_supply.personal_members_id(int(owner_id))
		var prior := {}
		for id: int in members:
			prior[id] = float(members[id].hp)
		var pending_hp := {}
		var context := {}
		if lab._region_deferring_endpoint():
			context = {"pending_hp": pending_hp, "hot_read": func(identity: int, field: StringName) -> Variant: return members[identity].get(String(field))}
		var result := Sustain.advance_to(personal, members, person.cargo, float(personal.at) + elapsed_game_seconds, context)
		if not result.ok:
			message.text = "個人供養資料無效：" + str(result.message)
			continue
		if float(result.consumed_rations) > 0.0:
			person.holder.version = int(person.holder.version) + 1
		for id: Variant in result.damage:
			var ending_hp := float(pending_hp.get(id, members[id].hp))
			var loss := float(prior[id]) if ending_hp == 0.0 else float(result.damage[id])
			if context.is_empty(): members[id].hp = float(prior[id])
			_apply_supply_damage(int(id), loss)
		_observe_original_food_result("person", owner_id, float(personal.at), result)

func _update_team_supply_ui() -> void:
	if team_supply_label == null:
		return
	var team: Variant = _chosen_supply_team()
	var entry := _supply_entry(team)
	if entry.is_empty():
		team_supply_label.text = "尚未啟用供養。點選相鄰隊員交糧，或由合格隊長下訓練令。\n只取玩家指定交出的實際口糧；不動營地物資。"
		return
	var maximum_hunger := 0.0
	for cohort: Dictionary in entry.sustain.cohorts:
		maximum_hunger = maxf(maximum_hunger, float(cohort.hunger))
	# P1e: a crowd owner keeps its training on the native clock; the grid field is not projected, so it is not shown.
	var training_text := "—" if team is CrowdPersonOwner else "%.2f" % float(team.training)
	team_supply_label.text = "本隊總餘糧 %.2f／%.0f 日份 · 士氣 %.1f\n最高等效缺糧 %.1f 小時 · 訓練 %s\n%s%s" % [Sustain.rations(entry.sustain, _supply_stock(entry)), team_food_capacity(team), float(entry.sustain.morale), maximum_hunger, training_text, "潰退；須安全足額整補 30 分且士氣≥50" if bool(entry.sustain.routed) else ("訓練令保留：缺糧／受威脅／缺實裝即停止增長" if bool(entry.training_order) else "未下訓練令"), "\n交糧剩餘 %.1f 有效秒；可取消，完成前不扣物" % float(entry.delivery.left) if not entry.delivery.is_empty() else ""]
	if int(entry.version) == 3:
		team_supply_label.text += "\n乘員只吃本船共有糧；岸上代表只取現場可達的指定岸糧。"

func _build_vehicle_controls(parent: Node, trial: bool = false) -> void:
	var form := {"trial": trial, "depot_version": -1, "holder_version": -1}
	_vehicle_forms["test" if trial else "formal"] = form
	parent.add_child(HSeparator.new())
	_label(parent, "車輛操作／真實裝卸", 20)
	_label(parent, ("測試調度由原隊長下令、原隊員操作。" if trial else "以目前受控原人物身份下令；無指揮權或距離不足時不能操作。") + "物資車容量100件、馬車300件；無人操作的車保持停泊。裝卸者須實際鄰接車輛與營地。", 15)
	form["choice"] = _options(parent, ["尚無車輛"], ("TrialVehicle" if trial else "Vehicle"))
	form.choice.item_selected.connect(func(_index: int) -> void: _refresh_vehicle_details(form))
	form["status"] = _label(parent, "尚無車輛", 15)
	form.status.name = ("TrialVehicleStatus" if trial else "VehicleStatus")
	_button(parent, "更新車輛／原人員名單", ("RefreshTrialVehicles" if trial else "RefreshVehicles"), func() -> void: _refresh_vehicle_controls(form))
	_button(parent, "定位所選車輛", ("FocusTrialVehicle" if trial else "FocusVehicle"), func() -> void:
		var vehicle := _selected_vehicle(form)
		if vehicle.is_empty(): return
		selected = lab.terrain.cell_from_index(int(vehicle.cell))
		lab.camera.position = (Vector2(selected) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		lab.camera.force_update_scroll()
		update_ui())
	_label(parent, "操作人：物資車站車後；馬車先走到馬旁再指派上馬。停泊友車可由另一後勤隊接手。", 15)
	_label(parent, "馬車騎姿目前支援標準男女步兵裝備與原染色；其他配裝須先下馬。騎手與馬車分別占名額。", 15)
	form["operator"] = _options(parent, ["尚無可選原隊員"], ("TrialVehicleOperator" if trial else "VehicleOperator"))
	var row := HBoxContainer.new()
	parent.add_child(row)
	_button(row, "指派操作／上馬", ("AssignTrialVehicleOperator" if trial else "AssignVehicleOperator"), func() -> void: _assign_trial_vehicle(form))
	_button(row, "停止操作／下馬", ("ParkTrialVehicle" if trial else "ParkVehicle"), func() -> void:
		var vehicle := _selected_vehicle(form)
		if vehicle.is_empty(): return
		show_result(vehicles.unassign_crew(str(vehicle.id), 0, _vehicle_requester(vehicle, false, form), trial) if SiteVehicleTransport.is_siege(vehicle) else vehicles.unassign_operator(str(vehicle.id), _vehicle_requester(vehicle, false, form), trial))
		_refresh_vehicle_controls(form))
	form["siege_slot"] = _options(parent, ["器具操作位 1", "器具操作位 2"], "SiegeSlot")
	form["siege_ammo"] = _options(parent, ["原器具彈種"], "SiegeAmmoKind")
	form.siege_ammo.set_item_metadata(0, "")
	_label(parent, "明示彈種後用原人物装卸；火罐須在位本人已學 F15。", 15)
	form["siege_target"] = _options(parent, ["所選原人物", "所選格牆／門部件", "所選格器具", "所選格地點"], "SiegeTarget")
	form["siege_part"] = _options(parent, ["請更新所選格部件"], "SiegePart")
	_button(parent, "更新所選格牆／門部件", "SiegeRefreshParts", func() -> void: _refresh_siege_parts(form))
	row = HBoxContainer.new()
	parent.add_child(row)
	_button(row, "器具左轉", "SiegeTurnLeft", func() -> void: _siege_order_ui(form, "left"))
	_button(row, "器具右轉", "SiegeTurnRight", func() -> void: _siege_order_ui(form, "right"))
	_button(parent, "射擊／衝撞所選目標（含友傷）", "SiegeAttack", func() -> void: _siege_order_ui(form, "attack"))
	_button(parent, "停止器具作業", "SiegeStop", func() -> void: _siege_order_ui(form, "stop"))
	_button(parent, "推運衝車／攻城塔至所選格", "SiegeMove", func() -> void: _siege_order_ui(form, "move"))
	_button(parent, "部署攻城塔／放橋", "SiegeDeploy", func() -> void: _siege_order_ui(form, "deploy"))
	_button(parent, "收橋後停泊攻城塔", "SiegeRetract", func() -> void: _siege_order_ui(form, "retract"))
	_button(parent, "所選原人物奪取無操作班敵具（10秒）", "SiegeTakeover", func() -> void:
		var vehicle := _selected_vehicle(form)
		if not SiteVehicleTransport.is_siege(vehicle): show_result(Runtime.fail("NO_TARGET")); return
		var identity := _siege_executor(form)
		var person := person_actions._person(identity)
		if person.is_empty() or not person.owner is TerrainArmy or not vehicles._authorized(person.owner, _siege_executor_requester(form, identity), identity, trial): show_result(Runtime.fail("NO_AUTHORITY")); return
		show_result(person_actions.begin_siege_takeover(identity, str(vehicle.id), _siege_executor_requester(form, identity), trial)))
	_button(parent, "預覽取消施工退款", "SiegeRefundPreview", func() -> void:
		var vehicle := _selected_vehicle(form)
		if not SiteVehicleTransport.is_siege(vehicle): return
		var job: Dictionary = vehicle.build if not vehicle.build.is_empty() else vehicle.repair
		var refund := {}
		for material: String in job.get("paid_cost", {}): refund[material] = 0 if bool(vehicle.ever_hp_damaged) else floori(float(job.paid_cost[material]) * (1.0 - float(job.progress) / float(job.total_work)))
		show_result(Runtime.ok("曾受損，取消不退料" if bool(vehicle.ever_hp_damaged) else "取消退款：" + Runtime.items_text(refund))))
	_button(parent, "取消施工／修理", "SiegeCancelWork", func() -> void: _siege_lifecycle_ui(form, "cancel"))
	_button(parent, "備料修理器具（須先解除操作班）", "SiegeRepair", func() -> void: _siege_lifecycle_ui(form, "repair"))
	_button(parent, "拆除空機具／清空殘骸", "SiegeClear", func() -> void: _siege_lifecycle_ui(form, "clear"))
	_button(parent, "殘骸 → 所選原人物行囊（耗時搜刮）", "SiegeLootWreck", func() -> void: _siege_wreck_ui(form, false))
	_button(parent, "本人接觸攻擊所選敵具", "SiegeMeleeAttack", func() -> void:
		var vehicle := _selected_vehicle(form)
		if SiteVehicleTransport.is_siege(vehicle): show_result(person_actions.begin_vehicle_attack(lab.controlled_person_id(), str(vehicle.id))))
	if trial: _build_siege_construction_controls(parent, form)
	_build_ship_controls(parent, form)
	if not trial:
		_build_shipyard_controls(parent, form)
		_build_region_travel_controls(parent)
	_label(parent, "原營地物資（不自動補物）", 16)
	form["resource"] = _options(parent, [], ("TrialVehicleResource" if trial else "VehicleResource"))
	for key: String in Env.ITEM_NAMES:
		form.resource.add_item(str(Env.ITEM_NAMES[key]))
		form.resource.set_item_metadata(form.resource.item_count - 1, key)
	form["quantity"] = _number_input(parent, ("TrialVehicleQuantity" if trial else "VehicleQuantity"), 1, 300, 10)
	row = HBoxContainer.new()
	parent.add_child(row)
	_button(row, "營地 → 車輛", ("LoadTrialVehicleResources" if trial else "LoadVehicleResources"), func() -> void: _transfer_trial_vehicle(true, false, form))
	_button(row, "車輛 → 營地", ("UnloadTrialVehicleResources" if trial else "UnloadVehicleResources"), func() -> void: _transfer_trial_vehicle(false, false, form))
	_button(parent, "所選原人物行囊 → 器具彈艙", "SupplySiegeAmmo", func() -> void: _siege_person_ammo_ui(form, true))
	_button(parent, "器具彈艙 → 所選原人物行囊", "TakeSiegeAmmo", func() -> void: _siege_person_ammo_ui(form, false))
	_label(parent, "原實物裝備（依實際物品ID搬運）", 16)
	form["depot"] = _options(parent, ["營地尚無實物"], ("TrialVehicleDepotItem" if trial else "VehicleDepotItem"))
	_button(parent, "將所選營地實物裝車", ("LoadTrialVehicleItem" if trial else "LoadVehicleItem"), func() -> void: _transfer_trial_vehicle(true, true, form))
	form["loaded"] = _options(parent, ["車內尚無實物"], ("TrialVehicleLoadedItem" if trial else "VehicleLoadedItem"))
	_button(parent, "將所選車內實物卸回營地", ("UnloadTrialVehicleItem" if trial else "UnloadVehicleItem"), func() -> void: _transfer_trial_vehicle(false, true, form))
	_label(parent, "工作隊沿原工作區尋工、採集與交庫；後勤隊由上方移動命令推車／駕車到目的地，再明確裝卸。車輛不自動往返，車上袋箱是固定外觀，實際庫存以上方載量為準。", 15)

	if not trial:
		vehicle_choice = form.choice
		vehicle_operator_choice = form.operator
		vehicle_resource_choice = form.resource
		vehicle_resource_quantity = form.quantity
		vehicle_status = form.status
		vehicle_depot_item = form.depot
		vehicle_loaded_item = form.loaded

func _build_tent_controls(parent: Node) -> void:
	parent.add_child(HSeparator.new())
	_label(parent, "軍隊野外駐紮／臨時營帳", 20)
	_label(parent, "帳篷包由後勤人員或車輛攜帶。先選後勤人員，再點地圖上的搭設位置；每頂占地 3×3 格。搭設與收納各需 30 有效工作秒。", 15)
	_tent_form.person = _options(parent, [], "TentLogisticPerson")
	_tent_form.status = _label(parent, "更新名單後選擇原後勤人員。", 15)
	_tent_form.status.name = "TentLogisticStatus"
	_tent_form.direction = _options(parent, ["入口朝南", "入口朝西", "入口朝北", "入口朝東"], "TentDirection")
	_tent_form.quantity = _number_input(parent, "TentTransferCount", 1, 20, 1)
	_tent_form.person.item_selected.connect(func(_index: int) -> void: _refresh_tent_status())
	_button(parent, "更新後勤人員與攜帶物", "RefreshTentLogistics", _refresh_tent_people)
	_button(parent, "在營地製作帳篷包（布4、木2、纖維2）", "CraftCampTent", func() -> void:
		var ready_now := _prepare_tent_person()
		if ready_now.ok: show_result(person_actions.begin_ranged_craft(int(ready_now.person_id), "camp_tent")))
	var row := HBoxContainer.new()
	parent.add_child(row)
	_button(row, "營地 → 後勤行囊", "TakeCampTent", func() -> void: _transfer_camp_tent("depot", true))
	_button(row, "後勤行囊 → 營地", "ReturnCampTent", func() -> void: _transfer_camp_tent("depot", false))
	row = HBoxContainer.new()
	parent.add_child(row)
	_button(row, "所選車輛 → 後勤行囊", "UnloadCampTent", func() -> void: _transfer_camp_tent("vehicle", true))
	_button(row, "後勤行囊 → 所選車輛", "LoadCampTent", func() -> void: _transfer_camp_tent("vehicle", false))
	_button(parent, "在地圖所選格搭設營帳", "DeployCampTent", func() -> void:
		var ready_now := _prepare_tent_person()
		if not ready_now.ok: return
		var quarter := int(_tent_form.direction.selected)
		var footprint := Runtime.building_cells(lab.terrain, "tent", selected, Vector2i(3, 3), {"quarter": quarter})
		if not footprint.ok:
			show_result(footprint)
			return
		var cells: Array[int] = []
		cells.assign(footprint.cells)
		view.selection = footprint.bounds
		show_result(person_actions.begin_tent_deploy(int(ready_now.person_id), cells, quarter)))
	_button(parent, "收納地圖所選營帳（須清空人員）", "PackCampTent", func() -> void:
		var ready_now := _prepare_tent_person()
		if ready_now.ok: show_result(person_actions.begin_tent_pack(int(ready_now.person_id), feature_key)))
	_button(parent, "取消所選人員搭收工作", "CancelCampTentWork", func() -> void:
		var identity := _tent_person_id()
		if identity > 0: show_result(person_actions.cancel(identity)))
	_label(parent, "搭帳前須停泊下車並走到占地旁。施工中物資留在行囊，完成才轉成營帳；收回前須清空營帳。群眾模式會先切回一般人物模擬。", 15)
	_refresh_tent_people()

func _build_siege_construction_controls(parent: Node, form: Dictionary) -> void:
	parent.add_child(HSeparator.new())
	_label(parent, "攻城器具施工", 18)
	form["siege_kind"] = _options(parent, [], "SiegeBuildKind")
	for kind: String in Runtime.SIEGE_DEFINITIONS:
		var definition: Dictionary = Runtime.SIEGE_DEFINITIONS[kind]
		form.siege_kind.add_item("%s · %d×%d格 · 最低%d／標準%d人 · %s · %.0f人工分鐘" % [definition.name, definition.size.x, definition.size.y, definition.min_crew, definition.standard_crew, Runtime.items_text(definition.cost), float(definition.work_seconds) / 60.0])
		form.siege_kind.set_item_metadata(form.siege_kind.item_count - 1, kind)
	_label(parent, "工具1件須保留；開工後派原工作隊施工，最多4人各站一個施工位。", 15)
	form["siege_facing"] = _options(parent, ["朝東", "朝南", "朝西", "朝北"], "SiegeBuildFacing")
	if bool(form.trial):
		form["siege_team"] = _options(parent, ["請更新原隊伍"], "SiegeBuildTeam")
		_button(parent, "更新原隊伍", "SiegeRefreshTeams", func() -> void: _refresh_siege_teams(form))
	form["siege_builder"] = _options(parent, ["請具名選擇原施工人員"], "SiegeBuildOperator")
	form.siege_builder.set_item_metadata(0, 0)
	_button(parent, "重新查詢原施工人員", "SiegeRefreshOperators", func() -> void: _refresh_siege_build_people(form))
	form.siege_kind.item_selected.connect(func(_index: int) -> void: _refresh_siege_build_people(form))
	if form.has("siege_team"):
		form.siege_team.item_selected.connect(func(_index: int) -> void: _refresh_siege_build_people(form))
	_label(parent, "本次備料只委派明示的原人；師傅須實際到位，助手沿原工作隊另行具名派工。", 15)
	form["siege_method"] = _options(parent, ["原基本工法", "F11木接（本人新工時九折）"], "SiegeJoinery")
	form.siege_method.set_item_metadata(0, "basic")
	form.siege_method.set_item_metadata(1, "joinery")
	_button(parent, "預覽所選格器具施工", "SiegeBuildPreview", func() -> void: _build_siege_ui(form, true))
	_button(parent, "在所選格備料建造器具", "SiegeBuild", func() -> void: _build_siege_ui(form, false))

func _refresh_siege_teams(form: Dictionary) -> void:
	if not form.has("siege_team"): return
	var selected_id := int(form.siege_team.get_item_metadata(form.siege_team.selected)) if form.siege_team.selected >= 0 and form.siege_team.get_item_metadata(form.siege_team.selected) != null else 0
	form.siege_team.clear()
	for team: Variant in _siege_ui_teams():
		if not team.has_army() or not team.command_eligible(team.current_commander): continue
		var count := 0
		for member: int in _siege_ui_indices(team): count += int(team.is_member(member))
		form.siege_team.add_item("隊伍 #%d · 原人員 %d" % [team.team_id, count])
		var index: int = form.siege_team.item_count - 1
		form.siege_team.set_item_metadata(index, team.team_id)
		if team.team_id == selected_id: form.siege_team.select(index)

func _prepare_siege_work_people(identities: Array) -> bool:
	# Existing explicit command preparation, before any original crew/job commit.
	if _crowd_active():
		for identity: int in identities:
			if not lab.crowd_site._live_contact_actor_ids.has(identity): continue
			var actor: TerrainTestCharacter = lab.crowd_site._actors.get(identity)
			if actor == null or actor.editor == null or not TerrainArmy.SiegeWorkClips.install(actor.editor): return false
	# Explicit UI/load/equipment boundary only; no AI/frame capture path.
	if DisplayServer.get_name() == "headless": return true
	var original_data: TerrainData = lab.terrain
	for identity: int in identities:
		if not await SiegeWorkAppend.ensure(self, person_appearance(identity)): return false
		if not is_same(lab.terrain, original_data): return false
	return true

func _siege_team_has_vehicle(team_id: int) -> bool:
	for vehicle: Dictionary in vehicles.records().values():
		if SiteVehicleTransport.is_siege(vehicle) and int(vehicle.team_id) == team_id: return true
	return false

func prepare_siege_equipment_work(appearance: Dictionary, team_id: int) -> bool:
	# Called by the original explicit equipment-atlas job before its timed commit.
	if DisplayServer.get_name() == "headless" or not _siege_team_has_vehicle(team_id) or bool(appearance.get("mounted", false)): return true
	return await SiegeWorkAppend.ensure(self, appearance)

func _siege_work_saved_appearances(data: TerrainData) -> Dictionary:
	var needed := {}
	for vehicle: Dictionary in data.site.get("vehicles", {}).values():
		if not SiteVehicleTransport.is_siege(vehicle): continue
		for identity: int in vehicle.get("crew_slots", {}).values(): needed[identity] = {}
	if needed.is_empty(): return needed
	for actor: Dictionary in data.site.get("actors", {}).values():
		var identity := int(actor.get("person_id", -1))
		if needed.has(identity): needed[identity] = Runtime.equipment_appearance(data, actor.get("item_state", {}), actor.get("appearance", {}))
	for team: Dictionary in data.site.get("armies", []):
		for row: Dictionary in team.get("units", []):
			var identity := int(row.get("person_id", -1))
			if needed.has(identity): needed[identity] = Runtime.equipment_appearance(data, row.get("item_state", {}), row.get("appearance", {}))
	return needed

func _siege_work_saved_guard(data: TerrainData) -> Dictionary:
	if DisplayServer.get_name() == "headless": return Runtime.ok()
	for appearance: Dictionary in _siege_work_saved_appearances(data).values():
		if not SiegeWorkAppend.ready(appearance): return Runtime.fail("MISSING_ASSET", "先準備已存原操作班的工作動作；原存檔與現場保留")
	return Runtime.ok()

func prepare_existing_siege_work_assets(data: TerrainData = null) -> bool:
	if DisplayServer.get_name() == "headless": return true
	if data == null: return await _prepare_siege_work_people(_siege_work_saved_appearances(lab.terrain).keys())
	for appearance: Dictionary in _siege_work_saved_appearances(data).values():
		if not await SiegeWorkAppend.ensure(self, appearance): return false
	return true

func _build_siege_ui(form: Dictionary, preview: bool) -> void:
	if _crowd_active() and not lab.crowd_site.siege_native_supported():
		show_result(Runtime.fail("CROWD_UNSUPPORTED", "原生群眾模組不支援攻城器；請更新原生模組")); return # No clear to GD.
	var context: Dictionary = _siege_build_person_context(form)
	if not context.ok: show_result(context); return
	var team: Variant = context.team
	var requester: int = int(context.requester_id)
	var actual_operator: int = int(context.person_id)
	var direction: Vector2i = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP][form.siege_facing.selected]
	var kind := str(form.siege_kind.get_item_metadata(form.siege_kind.selected)) if form.has("siege_kind") and form.siege_kind.selected >= 0 else "ballista"
	var anchor: Vector2i = selected
	var method: String = str(form.siege_method.get_item_metadata(form.siege_method.selected)) if form.has("siege_method") and form.siege_method.selected >= 0 else "basic"
	var original_data: TerrainData = lab.terrain
	var trial := bool(form.trial)
	if not preview:
		if not await _prepare_siege_work_people([actual_operator]):
			show_result(Runtime.fail("MISSING_ASSET", "所選原人工作動作準備未完成；未扣施工材料"))
			return
		if not is_same(lab.terrain, original_data) or not is_instance_valid(team) or not _siege_ui_teams().has(team): show_result(Runtime.fail("STALE_SOURCE")); return
	var current: Dictionary = _siege_build_person_context(form)
	if not current.ok: show_result(current); return
	if not is_same(current.team, team) or int(current.person_id) != actual_operator or int(current.requester_id) != requester or not is_same(lab.terrain, original_data): show_result(Runtime.fail("STALE_SOURCE")); return
	var result := Runtime.begin_siege_build(lab.terrain, kind, anchor, direction, int(team.team_id), requester, reserves_cell, preview, {}, {}, actual_operator, method)
	if result.ok and preview:
		var bounds := Rect2i(result.cells[0], Vector2i.ONE)
		for cell: Vector2i in result.cells: bounds = bounds.expand(cell)
		view.selection = bounds
		view.refresh()
	show_result(result)
	if not preview:
		if vehicle_view != null: vehicle_view.refresh()
		_refresh_vehicle_controls()
		if _vehicle_forms.has("test"): _refresh_vehicle_controls(_vehicle_forms.test)

func _siege_order_ui(form: Dictionary, operation: String) -> void:
	var vehicle := _selected_vehicle(form)
	if not SiteVehicleTransport.is_siege(vehicle): show_result(Runtime.fail("NO_TARGET", "請先選擇攻城器具")); return
	var target := {}
	var command := operation
	var warning := ""
	if operation in ["left", "right"]:
		var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
		var direction := Vector2i(facing.y, -facing.x) if operation == "left" else Vector2i(-facing.y, facing.x)
		target = {"facing": [direction.x, direction.y]}
		command = "turn"
	elif operation == "move": target = {"type": "ground", "cell": [selected.x, selected.y]}
	elif operation == "attack":
		match form.siege_target.selected:
			0: target = {"type": "person", "person_id": lab.selected_army_target}
			1:
				var key := str(lab.terrain.feature_at[lab.terrain.index(selected)])
				var feature: Dictionary = lab.terrain.site.features.get(key, {})
				var geometry := Runtime.feature_geometry(lab.terrain, feature)
				var choice: Variant = form.siege_part.get_item_metadata(form.siege_part.selected) if form.has("siege_part") and form.siege_part.selected >= 0 else null
				if choice is Dictionary and choice.get("feature_id") == key and geometry.parts.has(str(choice.get("part_id", ""))) and geometry.parts[str(choice.part_id)].cells.has(lab.terrain.index(selected)):
					target = {"type": "structure", "feature_id": key, "part_id": str(choice.part_id)}
				else: show_result(Runtime.fail("NO_TARGET", "請更新並選擇原牆／門扇／門框部件")); return
			2:
				for identity: String in vehicles.records():
					if identity != str(vehicle.id) and Vehicles.footprint(lab.terrain, vehicles.records()[identity]).has(selected):
						target = {"type": "vehicle", "vehicle_id": identity}
						break
			3: target = {"type": "ground", "cell": [selected.x, selected.y]}
	var ammo_choice := _siege_ammo_choice(form, vehicle) if command == "attack" else Runtime.ok("", {"ammo": ""})
	if not ammo_choice.ok: show_result(ammo_choice); return
	var ammunition: String = ammo_choice.ammo
	var operator_id := _siege_executor(form) if ammunition == "fire_pot" else 0
	if ammunition == "fire_pot":
		var original_guard: Dictionary = person_actions.fire_pot_ammo_guard(vehicle, operator_id)
		if not original_guard.ok: show_result(original_guard); return
	var original_data: TerrainData = lab.terrain
	var original_control: int = lab.controlled_person_id()
	var requester := _vehicle_requester(vehicle, false, form)
	var trial := bool(form.trial)
	if command != "stop" and not await _prepare_siege_work_people(vehicle.get("crew_slots", {}).values()):
		show_result(Runtime.fail("MISSING_ASSET", "原人員工作動作準備未完成；未下達器具操作"))
		return
	if lab.terrain != original_data or lab.controlled_person_id() != original_control or not is_same(vehicles.records().get(str(vehicle.id)), vehicle): show_result(Runtime.fail("STALE_SOURCE")); return
	if command == "attack":
		var check: Dictionary = lab.siege_fire_preview(vehicle, target)
		if not check.ok: show_result(check); return
		warning = str(check.message)
	var result := vehicles.order_siege(str(vehicle.id), command, target, requester, trial, ammunition, operator_id)
	if result.ok and not warning.is_empty(): result.message += "；" + warning
	show_result(result)
	if is_instance_valid(form.get("status")): _refresh_vehicle_details(form)

func _refresh_siege_parts(form: Dictionary) -> void:
	if not form.has("siege_part"): return
	form.siege_part.clear()
	if lab.terrain.contains(selected):
		var key := str(lab.terrain.feature_at[lab.terrain.index(selected)])
		var feature: Dictionary = lab.terrain.site.features.get(key, {})
		var geometry := Runtime.feature_geometry(lab.terrain, feature)
		for part: String in geometry.get("parts", {}):
			if not geometry.parts[part].cells.has(lab.terrain.index(selected)): continue
			var state: Dictionary = feature.get("parts", {}).get(part, {})
			form.siege_part.add_item("%s · %s · HP %.0f" % [key, part, float(state.get("hp", 0.0))])
			form.siege_part.set_item_metadata(form.siege_part.item_count - 1, {"feature_id": key, "part_id": part})
	if form.siege_part.item_count == 0:
		form.siege_part.add_item("所選格沒有可攻擊部件")
		form.siege_part.set_item_metadata(0, null)

func _siege_lifecycle_ui(form: Dictionary, operation: String) -> void:
	var vehicle := _selected_vehicle(form)
	if operation == "clear" and SiteVehicleTransport.is_siege(vehicle) and str(vehicle.phase) == "wrecked": _siege_wreck_ui(form, true); return
	var team: Variant = vehicles._siege_team(vehicle) if SiteVehicleTransport.is_siege(vehicle) else null
	var requester := _vehicle_requester(vehicle, false, form) if team != null else 0
	if team == null or not vehicles._authorized(team, requester, 0, bool(form.trial)): show_result(Runtime.fail("NO_AUTHORITY")); return
	var result: Dictionary
	if operation == "repair": result = Runtime.request_siege_repair(lab.terrain, str(vehicle.id), team.team_id)
	elif operation == "cancel": result = Runtime.cancel_siege_job(lab.terrain, str(vehicle.id), team.team_id, _siege_people_occupied)
	else: result = Runtime.remove_siege_vehicle(lab.terrain, str(vehicle.id), team.team_id, _siege_people_occupied)
	show_result(result)
	_refresh_vehicle_controls(form)
	if vehicle_view != null: vehicle_view.refresh()

func _siege_people_occupied(cell: Vector2i) -> bool:
	if _actor_people_blocked(cell, null): return true
	for team: TerrainArmy in lab.combat_armies:
		if _crowd_active() and lab.crowd_site.owns_original_team(team): continue
		# Real people and committed destinations were checked above. Generic
		# terrain reservations also include vehicles, which cannot block themselves.
		if team.has_army() and team._passage_cell_is_protected(cell): return true
	return false

func _siege_executor(form: Dictionary) -> int:
	var identity := int(form.operator.get_item_metadata(form.operator.selected)) if form.operator.selected >= 0 else 0
	return identity if identity > 0 else lab.controlled_person_id()

func _siege_executor_requester(form: Dictionary, identity: int) -> int:
	if bool(form.trial):
		var person := person_actions._person(identity)
		if not person.is_empty() and (person.owner is TerrainArmy or person.owner is CrowdPersonOwner) and person.owner.command_eligible(person.owner.current_commander): return person.owner.combat_identity(person.owner.current_commander)
	return lab.controlled_person_id()

func _siege_wreck_ui(form: Dictionary, clear: bool) -> void:
	var vehicle := _selected_vehicle(form)
	if not SiteVehicleTransport.is_siege(vehicle) or str(vehicle.phase) != "wrecked": show_result(Runtime.fail("NO_TARGET")); return
	var identity := _siege_executor(form)
	if clear:
		show_result(vehicles.clear_siege_wreck(str(vehicle.id), identity, _siege_executor_requester(form, identity), bool(form.trial)))
	else:
		var person := person_actions._person(identity, false)
		var requester := _siege_executor_requester(form, identity)
		if person.is_empty() or (person.owner is TerrainArmy and (not person.owner.is_member(int(person.unit)) or not vehicles._authorized(person.owner, requester, identity, bool(form.trial)))) or (not person.owner is TerrainArmy and identity != requester):
			show_result(Runtime.fail("NO_AUTHORITY", "只能調度本人或自己指揮的原隊員搜刮"))
			return
		var resource := str(form.resource.get_item_metadata(form.resource.selected))
		var resources := {resource: int(form.quantity.value)}
		show_result(person_actions.begin_loot(identity, "wreck", str(vehicle.id), resources, []))
	_refresh_vehicle_controls(form)

func _siege_person_ammo_ui(form: Dictionary, loading: bool) -> void:
	var vehicle := _selected_vehicle(form)
	if not SiteVehicleTransport.is_siege(vehicle): show_result(Runtime.fail("NO_TARGET")); return
	var identity := _siege_executor(form)
	var personal := "person:%d" % identity
	var source_id := personal if loading else str(vehicle.id)
	var destination_id := str(vehicle.id) if loading else personal
	var source := vehicles._stock(source_id)
	var destination := vehicles._stock(destination_id)
	if source.is_empty() or destination.is_empty(): show_result(Runtime.fail("NO_TARGET", "須選擇原後勤或本人操作班")); return
	var choice := _siege_ammo_choice(form, vehicle)
	if not choice.ok: show_result(choice); return
	var ammo: String = choice.ammo
	if ammo.is_empty(): show_result(Runtime.fail("NO_TARGET", "此器具不使用彈藥")); return
	show_result(vehicles.transfer(source_id, destination_id, {ammo: int(form.quantity.value)}, [], int(source.holder.version), int(destination.holder.version), _siege_executor_requester(form, identity), bool(form.trial)))
	_refresh_vehicle_details(form)

func _tent_person_id() -> int:
	if _tent_form.is_empty() or _tent_form.person.selected < 0: return -1
	return int(_tent_form.person.get_item_metadata(_tent_form.person.selected))

func _refresh_tent_people() -> void:
	if _tent_form.is_empty(): return
	var prior := _tent_person_id()
	_tent_form.person.clear()
	var owners: Array = lab.crowd_site.person_owners() if _crowd_active() else lab.combat_armies
	for owner_ref: Variant in owners:
		var indices: Array = owner_ref.combat_units.keys() if owner_ref.combat_units is Dictionary else range(owner_ref.combat_units.size())
		for index: int in indices:
			if not owner_ref.is_member(index) or not bool(owner_ref.combat_hot_get(index, &"logistics", false)): continue
			var identity: int = owner_ref.combat_identity(index)
			_tent_form.person.add_item("後勤 #%d · 隊伍 #%d" % [identity, int(owner_ref.team_id)])
			_tent_form.person.set_item_metadata(_tent_form.person.item_count - 1, identity)
			if identity == prior: _tent_form.person.select(_tent_form.person.item_count - 1)
	_refresh_tent_status()

func _refresh_tent_status() -> void:
	if person_actions.lab == null: return # Controls are built before the original action owner is initialized.
	if _tent_form.is_empty(): return
	var person := person_actions._person(_tent_person_id())
	if person.is_empty():
		_tent_form.status.text = "尚無後勤人員；請先在原隊伍名冊指定後勤身分。"
		return
	var job := person_actions.job_for(int(person.person_id))
	_tent_form.status.text = "後勤 #%d · 帳篷包 %d · 負重 %.0f／20\n%s" % [int(person.person_id), int(person.cargo.get("camp_tent", 0)), Runtime.carried_load(lab.terrain.site, person.cargo, person.holder), str(job.get("kind", "待命"))]

func _prepare_tent_person() -> Dictionary:
	var identity := _tent_person_id()
	if identity <= 0:
		var missing := Runtime.fail("NO_TARGET", "請先選擇原後勤人員")
		show_result(missing)
		return missing
	return Runtime.ok("", {"person_id": identity}) # Crowd people transfer through their CrowdPersonOwner stock; no clear to GD.

func _transfer_camp_tent(endpoint: String, take: bool) -> void:
	var ready_now := _prepare_tent_person()
	if not ready_now.ok: return
	var external := "depot"
	if endpoint == "vehicle":
		var vehicle := _selected_vehicle()
		if vehicle.is_empty():
			show_result(Runtime.fail("NO_TARGET", "請先選擇停泊車輛"))
			return
		external = str(vehicle.id)
	var personal := "person:%d" % int(ready_now.person_id)
	var source_id := external if take else personal
	var destination_id := personal if take else external
	var source := vehicles._stock(source_id)
	var destination := vehicles._stock(destination_id)
	if source.is_empty() or destination.is_empty():
		show_result(Runtime.fail("NO_TARGET"))
		return
	show_result(vehicles.transfer(source_id, destination_id, {"camp_tent": int(_tent_form.quantity.value)}, [],
		int(source.holder.version), int(destination.holder.version), lab.controlled_person_id()))
	_refresh_tent_status()

func _selected_vehicle(form: Dictionary = {}) -> Dictionary:
	if form.is_empty(): form = _vehicle_forms.get("formal", {})
	if form.is_empty(): return {}
	if form.choice == null or form.choice.selected < 0: return {}
	return vehicles.records().get(str(form.choice.get_item_metadata(form.choice.selected)), {})

func _refresh_vehicle_controls(form: Dictionary = {}) -> void:
	if form.is_empty(): form = _vehicle_forms.get("formal", {})
	if form.is_empty(): return
	if form.choice == null or lab.terrain == null: return
	var selected_id := str(form.choice.get_item_metadata(form.choice.selected)) if form.choice.selected >= 0 else ""
	form.choice.clear()
	for identity: String in vehicles.records():
		var vehicle: Dictionary = vehicles.records()[identity]
		form.choice.add_item("#%s %s · %s" % [identity, _ship_type_name(str(vehicle.ship_type)) if SiteVehicleTransport.is_ship(vehicle) else (str(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].name) if SiteVehicleTransport.is_siege(vehicle) else ("物資車" if vehicle.kind == "cart" else "馬車")), "停泊無所屬隊伍" if int(vehicle.team_id) == 0 else "隊伍 #%d" % int(vehicle.team_id)])
		var index: int = form.choice.item_count - 1
		form.choice.set_item_metadata(index, identity)
		if identity == selected_id: form.choice.select(index)
	if form.choice.item_count == 0:
		form.choice.add_item("尚無車輛")
		form.choice.set_item_metadata(0, "")
	_refresh_vehicle_details(form)
	if form.has("siege_team"): _refresh_siege_teams(form)
	if form.has("siege_builder"): _refresh_siege_build_people(form)
	_refresh_shipyards(form)

func _refresh_vehicle_details(form: Dictionary = {}) -> void:
	if form.is_empty(): form = _vehicle_forms.get("formal", {})
	if form.is_empty(): return
	if form.operator == null: return
	var vehicle := _selected_vehicle(form)
	_refresh_siege_ammo_choices(form, vehicle)
	if form.has("siege_slot"):
		var old_slot: int = maxi(0, form.siege_slot.selected)
		form.siege_slot.clear()
		var slots := int(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].standard_crew) if SiteVehicleTransport.is_siege(vehicle) else 2
		for slot in slots: form.siege_slot.add_item("器具操作位 %d" % (slot + 1))
		form.siege_slot.select(mini(old_slot, slots - 1))
	var prior_operator := int(form.operator.get_item_metadata(form.operator.selected)) if form.operator.selected >= 0 and form.operator.get_item_metadata(form.operator.selected) != null else 0
	form.operator.clear()
	form.depot.clear()
	form.loaded.clear()
	form["depot_version"] = int(lab.terrain.site.depot_items.version)
	form["holder_version"] = -1
	if not vehicle.is_empty():
		form["holder_version"] = int(vehicle.holder.version)
		for team: Variant in (_siege_ui_teams() if SiteVehicleTransport.is_siege(vehicle) else lab.combat_armies):
			if not team.has_army(): continue
			if SiteVehicleTransport.is_siege(vehicle):
				if str(vehicle.phase) != "wrecked" and team.team_id != int(vehicle.team_id) and _siege_ui_role(team) != "logistics": continue
			elif SiteVehicleTransport.is_ship(vehicle):
				if team.team_id != int(vehicle.team_id): continue
			elif team.team_id != int(vehicle.team_id) and not vehicles.can_offer_operator_team(vehicle, team): continue
			for index: int in _siege_ui_indices(team):
				if not team.combat_can_act(index) or not team.is_member(index) and not (SiteVehicleTransport.is_ship(vehicle) and vehicles.is_embarked(team.combat_identity(index))): continue
				var identity: int = team.combat_identity(index)
				form.operator.add_item("人物 #%d · 隊伍 #%d · 格%s%s" % [identity, team.team_id, vehicles.ship_person_cell(identity) if vehicles.is_embarked(identity) else _siege_ui_cell(team, index), " · 正操作車輛" if vehicles.is_operator(identity) else ""])
				var item: int = form.operator.item_count - 1
				form.operator.set_item_metadata(item, identity)
				if identity == prior_operator or prior_operator == 0 and identity == int(vehicle.operator_id): form.operator.select(item)
		_vehicle_item_choices(form.loaded, vehicle.holder)
	_vehicle_item_choices(form.depot, lab.terrain.site.depot_items)
	if form.operator.item_count == 0:
		form.operator.add_item("尚無可選原隊員")
		form.operator.set_item_metadata(0, 0)
	if form.loaded.item_count == 0:
		form.loaded.add_item("車內尚無實物")
		form.loaded.set_item_metadata(0, "")
	_update_vehicle_status(form)
	_refresh_ship_deck_targets(form)
	_refresh_ship_repair_facilities(form)

func _vehicle_item_choices(choice: OptionButton, holder: Dictionary) -> void:
	for identity: String in holder.item_ids:
		var record: Dictionary = lab.terrain.site.item_records.get(identity, {})
		choice.add_item("%s · %s" % [identity, str(record.get("definition", "未知"))])
		choice.set_item_metadata(choice.item_count - 1, identity)
	if choice.item_count == 0:
		choice.add_item("尚無實物裝備")
		choice.set_item_metadata(0, "")

func _update_vehicle_status(form: Dictionary = {}) -> void:
	if form.is_empty(): form = _vehicle_forms.get("formal", {})
	if form.is_empty(): return
	_refresh_shipyard_status(form)
	if form.status == null: return
	var vehicle := _selected_vehicle(form)
	if vehicle.is_empty():
		form.status.text = "尚無車輛。"
		return
	if SiteVehicleTransport.is_ship(vehicle):
		var spec: Dictionary = vehicles.Ship.definition(str(vehicle.ship_type))
		var supply: Dictionary = lab.terrain.site.get("team_supply", {}).get(str(vehicle.team_id), {}).get("locations", {}).get("vehicle:%s" % str(vehicle.id), {})
		var job: Dictionary = vehicles.ship_job(str(vehicle.id))
		form.status.text = "%s #%s · 隊伍 #%d\n乘員 %d／%d · 船員 %d／最低%d／標準%d\n全船物品 %.1f／%d · 舵手 #%d · %s\n船上共用糧：%s，開封 %.2f\n%s" % [_ship_type_name(str(vehicle.ship_type)), vehicle.id, int(vehicle.team_id), vehicles.ship_people(vehicle).size(), int(spec.max_people), vehicles.ship_crew_count(vehicle), int(spec.min_crew), int(spec.standard_crew), vehicles.ship_load(str(vehicle.id)), int(spec.capacity), int(vehicle.operator_id), "旅途中" if ship_vehicle_in_journey(str(vehicle.id)) else "行進中" if not vehicle.move.is_empty() else "已停穩", Runtime.items_text(supply.get("inventory", {})), float(supply.get("open_rations", 0.0)), str({"ship_board": "登船中", "ship_disembark": "離船中", "ship_helm": "前往舵位", "ship_walk": "甲板移動", "ship_cross": "換船中", "ship_evac": "撤離沉船"}.get(str(job.get("kind", "")), "待命"))]
		var naval: Dictionary = vehicle.get("naval", {})
		form.status.text += "\n船體 HP %.0f／%.0f · %s" % [float(naval.get("hp", vehicles.Ship.hull_hp(str(vehicle.ship_type)))), vehicles.Ship.hull_hp(str(vehicle.ship_type)), str({"afloat": "漂浮中", "sinking": "下沉中", "wrecked": "殘骸"}.get(str(naval.get("state", "afloat")), "未知狀態"))]
		var repair: Dictionary = naval.get("repair", {})
		if not repair.is_empty():
			form.status.text += "\n修理工時 %.1f／%.1f 秒 · 已恢復耐久 %.1f／%.1f\n本船艙預留：%s" % [float(repair.progress), float(repair.total_work), float(repair.applied), float(repair.amount), Runtime.items_text(Runtime.reserved_ship_repair_resources(vehicle))]
		return
	if SiteVehicleTransport.is_siege(vehicle):
		var definition: Dictionary = Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)]
		var action: Dictionary = vehicle.get("action", {})
		form.status.text = "%s #%s · HP %.0f／%.0f · 隊伍 #%d\n在位 %d／最低%d／標準%d（仍在原人員編制）\n%s · %s · 輪次%d · %s %.1fs\n%s\n%s" % [definition.name, vehicle.id, float(vehicle.hp), float(definition.max_hp), int(vehicle.team_id), vehicles.crew_count(vehicle), definition.min_crew, definition.standard_crew, "無彈藥需求" if str(definition.ammo).is_empty() else "%s %d／%d" % [Env.ITEM_NAMES.get(str(definition.ammo), str(definition.ammo)), int(vehicle.cargo.get(str(definition.ammo), 0)), definition.capacity], vehicle.phase, int(vehicle.next_attack_seq), action.get("stage", "待命"), float(action.get("elapsed", 0.0)), vehicle.command.get("reason", ""), "曾受損，取消施工不退料" if bool(vehicle.ever_hp_damaged) else "操作人留在原隊名冊；一般軍令作用於非操作班"]
		return
	var cell: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
	var operator_cell: Vector2i = vehicles.operator_cell(vehicle)
	form.status.text = "%s · 格%s · %s%s\n%s · 載量%d／%d件\n%s" % ["物資車" if vehicle.kind == "cart" else "馬車", cell, "車後操作格" if vehicle.kind == "cart" else "馬匹格（在相鄰格上馬）", operator_cell,
		"無人操作，停泊" if int(vehicle.operator_id) == 0 else "原人物 #%d 操作%s" % [int(vehicle.operator_id), "（行進中）" if not vehicle.move.is_empty() else "（停止）"],
		Runtime.carried_load(lab.terrain.site, vehicle.cargo, vehicle.holder), int(Vehicles.CAPACITY[vehicle.kind]), Runtime.items_text(vehicle.cargo)]

func _vehicle_requester(vehicle: Dictionary, loading: bool = false, form: Dictionary = {}) -> int:
	if form.is_empty(): form = _vehicle_forms.get("formal", {})
	if form.is_empty(): return lab.controlled_person_id()
	if not bool(form.trial): return lab.controlled_person_id()
	if loading and int(vehicle.operator_id) > 0: return int(vehicle.operator_id)
	var operator_id := 0
	if form.operator.selected >= 0: operator_id = int(form.operator.get_item_metadata(form.operator.selected))
	if loading and SiteVehicleTransport.is_siege(vehicle) and vehicle.crew_slots.values().has(operator_id): return operator_id
	for team: Variant in (_siege_ui_teams() if SiteVehicleTransport.is_siege(vehicle) else lab.combat_armies):
		if team.has_army() and (team.team_id == int(vehicle.team_id) or int(vehicle.team_id) == 0 and team.index_for_identity(operator_id) >= 0) and team.command_eligible(team.current_commander):
			return team.combat_identity(team.current_commander)
	return lab.controlled_person_id()

func _assign_trial_vehicle(form: Dictionary = {}) -> void:
	if form.is_empty(): form = _vehicle_forms.get("formal", {})
	if form.is_empty(): return
	var vehicle := _selected_vehicle(form)
	if vehicle.is_empty() or form.operator.selected < 0: return
	var identity := int(form.operator.get_item_metadata(form.operator.selected))
	var requester: int = lab.controlled_person_id()
	for team: Variant in (_siege_ui_teams() if SiteVehicleTransport.is_siege(vehicle) else lab.combat_armies):
		if bool(form.trial) and team.index_for_identity(identity) >= 0 and team.command_eligible(team.current_commander):
			requester = team.combat_identity(team.current_commander)
			break
	var slot := str(form.siege_slot.selected) if SiteVehicleTransport.is_siege(vehicle) else ""
	var trial := bool(form.trial)
	if SiteVehicleTransport.is_siege(vehicle) and not await _prepare_siege_work_people([identity]):
		show_result(Runtime.fail("MISSING_ASSET", "原人員工作動作準備未完成；未指派操作班"))
		return
	if not is_same(vehicles.records().get(str(vehicle.id)), vehicle): show_result(Runtime.fail("STALE_SOURCE")); return
	show_result(vehicles.assign_crew(str(vehicle.id), identity, slot, requester, trial) if SiteVehicleTransport.is_siege(vehicle) else vehicles.assign_operator(str(vehicle.id), identity, requester, trial))
	if is_instance_valid(form.get("status")): _refresh_vehicle_controls(form)

func _transfer_trial_vehicle(loading: bool, equipment: bool = false, form: Dictionary = {}) -> void:
	if form.is_empty(): form = _vehicle_forms.get("formal", {})
	if form.is_empty(): return
	var vehicle := _selected_vehicle(form)
	if vehicle.is_empty():
		show_result(Runtime.fail("NO_TARGET"))
		return
	var resources := {}
	var items: Array = []
	if equipment:
		var choice: OptionButton = form.depot if loading else form.loaded
		var identity := str(choice.get_item_metadata(choice.selected)) if choice.selected >= 0 else ""
		if identity.is_empty():
			show_result(Runtime.fail("EMPTY"))
			return
		items.append(identity)
	else:
		resources[str(form.resource.get_item_metadata(form.resource.selected))] = int(form.quantity.value)
	show_result(vehicles.transfer("depot" if loading else str(vehicle.id), str(vehicle.id) if loading else "depot", resources, items,
		form.depot_version if loading else form.holder_version, form.holder_version if loading else form.depot_version, _vehicle_requester(vehicle, true, form), bool(form.trial)))
	_refresh_vehicle_controls(form)

func _update_formal_team_ui() -> void:
	if not formal_windows.has("team") or not formal_windows.team.visible: return
	_refresh_formal_team_choices()
	if _crowd_active():
		var team := _crowd_command_team("player")
		player_retreat_button.disabled = team.is_empty() or not bool(team.get("routed", false))
		player_army_label.text = "尚未加入隊伍" if team.is_empty() else lab.crowd_site.team_summary(int(team.team_id))
	else:
		var team: TerrainArmy = lab.player_army()
		_update_retreat_button(player_retreat_button, team, lab.controlled_member_index(team))
	if _active_formation_view == "formal": _update_formation_controls()

func _update_team_info() -> void:
	if not formal_windows.team_info.visible: return
	var summaries: PackedStringArray = []
	if _crowd_active():
		summaries = lab.crowd_site.team_summaries()
	else:
		var batch_texts := PackedStringArray()
		if get_script() == SiteController:
			var can_batch := true
			for team: TerrainArmy in lab.combat_armies:
				if team.get_script() != TerrainArmy or not team.has_army() or not team.combat_enabled:
					can_batch = false
					break
			if can_batch: batch_texts = TerrainArmy.combat_summaries(lab.combat_armies)
		var summary_index := 0
		for team: TerrainArmy in lab.combat_armies:
			if not team.has_army(): continue
			if team.combat_enabled:
				summaries.append(_trial_team_choice_text(team) + "\n" + (batch_texts[summary_index] if not batch_texts.is_empty() else team.combat_summary()))
				summary_index += 1
			else:
				summaries.append("隊伍 #%d · 陣營 %s · %d 人\n%s\n陣型：%s · 站位 %d · 移動 %d" % [team.team_id, _faction_label(team.faction_id), team.roster_size, team.command_status, team.formation_mode_name(), team.occupied_count(), team.moving_count()])
	team_info_label.text = "尚未部署隊伍。" if summaries.is_empty() else ((_team_info_report + "\n\n") if not _team_info_report.is_empty() else "") + "\n\n".join(summaries)
	if _team_info_list == null: return # Summary-only callers retain the original serial/batch read order.
	var rows: Array[Dictionary] = []
	if _crowd_active():
		for team: Dictionary in lab.crowd_site.command_teams():
			rows.append({"id": int(team.team_id), "meta": "陣營 %s · %d 人" % [_faction_label(int(team.faction)), int(team.count)], "prefix": "隊伍 #%d｜" % int(team.team_id)})
	else:
		for team: TerrainArmy in lab.combat_armies:
			if not team.has_army(): continue
			var caption: String = _trial_team_choice_text(team) if team.combat_enabled else "隊伍 #%d · 陣營 %s · %d 人" % [team.team_id, _faction_label(team.faction_id), team.roster_size]
			rows.append({"id": team.team_id, "meta": caption.trim_prefix("隊伍 #%d · " % team.team_id), "prefix": caption + "\n"})
	var ids: Array[int] = []
	for row: Dictionary in rows: ids.append(int(row.id))
	for id: int in _team_info_cards.keys():
		if ids.has(id): continue
		var card_panel: PanelContainer = _team_info_cards[id].panel
		_team_info_list.remove_child(card_panel)
		card_panel.queue_free()
		_team_info_cards.erase(id)
	for index in range(rows.size()):
		var id := int(rows[index].id)
		if not _team_info_cards.has(id): _add_team_info_card(id)
		var card: Dictionary = _team_info_cards[id]
		_team_info_list.move_child(card.panel, index)
		card.meta.text = str(rows[index].meta)
		card.summary.text = summaries[index].trim_prefix(str(rows[index].prefix)).replace("｜", "\n")
		var leader := _team_info_leader(id)
		card.button.disabled = leader.is_empty()
		card.button.text = "隊伍 #%d · 定位%s" % [id, "代理隊長" if bool(leader.get("acting", false)) else "隊長"]
		card.leader.text = "隊長不在場，無法定位" if leader.is_empty() else "%s%s · 地圖 (%d, %d)" % ["代理隊長" if bool(leader.acting) else "隊長", " #%d" % int(leader.identity) if int(leader.identity) > 0 else "", floori(leader.position.x / TerrainRenderer.CELL_PIXELS), floori(leader.position.y / TerrainRenderer.CELL_PIXELS)]
	_team_info_overview.text = "尚未部署隊伍。" if rows.is_empty() else "共 %d 隊 · 點選隊伍標題，地圖將定位到隊長。" % rows.size()
	_team_info_report_button.visible = not rows.is_empty()
	if rows.is_empty():
		team_info_label.hide()
		_team_info_report_button.text = "展開完整文字紀錄"

func _add_team_info_card(id: int) -> void:
	var card_panel := PanelContainer.new()
	card_panel.name = "TeamCard_%d" % id
	card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("243835")
	style.border_color = Color("526b5d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	for side: int in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side, 12)
	card_panel.add_theme_stylebox_override("panel", style)
	_team_info_list.add_child(card_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card_panel.add_child(column)
	var button := _button(column, "", "FocusTeamLeader_%d" % id, focus_team_leader.bind(id))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.custom_minimum_size.y = 40
	button.tooltip_text = "移動地圖鏡頭到此隊隊長；正式隊長離場時定位目前代理隊長。"
	var card := {"panel": card_panel, "button": button}
	for field: String in ["meta", "leader", "summary"]:
		var label := _label(column, "", 15)
		label.custom_minimum_size.x = 0
		label.add_theme_constant_override("line_spacing", 5)
		card[field] = label
	card.meta.modulate = Color("c9dfce")
	card.leader.modulate = Color("edd5a2")
	_team_info_cards[id] = card

func _team_info_leader(team_id: int) -> Dictionary:
	if _crowd_active():
		var team: Dictionary = lab.crowd_site._team_by_id(team_id)
		if team.is_empty() or bool(team.solo): return {}
		var state: Dictionary = lab.crowd_site.formation_state(int(team.formation))
		for identity: int in [int(state.formal_person), int(state.current_person)]:
			var person_owner: Variant = lab.crowd_site.person_owner(identity)
			if person_owner == null: continue
			var unit: int = person_owner.index_for_identity(identity)
			if unit < 0 or person_owner.team_id != team_id or float(person_owner.combat_hot_get(unit, &"hp")) <= 0.0 or bool(person_owner.combat_hot_get(unit, &"departed", false)) or bool(person_owner.combat_hot_get(unit, &"site_exited", false)): continue
			var acting := identity != int(state.formal_person)
			if acting and (not bool(state.commander_present) or not person_owner.combat_can_act(unit)): continue
			var target: Dictionary = lab.crowd_site.combat_target(identity)
			if not target.is_empty(): return {"position": target.position, "identity": identity, "acting": acting}
		return {}
	for team: TerrainArmy in lab.combat_armies:
		if team.team_id != team_id or not team.has_army() or team.has_ship_journey(): continue
		if not team.combat_enabled: return {"position": team.combat_ground(0), "identity": -1, "acting": false}
		for unit: int in [team.formal_commander, team.current_commander]:
			if not team.is_member(unit) or team.member_gone(unit): continue
			if unit == TerrainArmy.PLAYER_MEMBER:
				if team.player_member.site_exited: continue
			elif bool(team.combat_hot_get(unit, &"site_exited", false)): continue
			var acting := unit != team.formal_commander
			if acting and not team.command_eligible(unit): continue
			return {"position": team.combat_ground(unit), "identity": team.combat_identity(unit), "acting": acting}
	return {}

func _team_leader_focus_rect() -> Rect2:
	var area := camera_usable_rect()
	var window: Window = formal_windows.team_info
	if not window.visible: return area
	var covered := area.intersection(Rect2(Vector2(window.position) - Vector2(4, 28), Vector2(window.size) + Vector2(8, 32)))
	if not covered.has_area(): return area
	var candidates := [Rect2(area.position, Vector2(covered.position.x - area.position.x, area.size.y)),
		Rect2(Vector2(covered.end.x, area.position.y), Vector2(area.end.x - covered.end.x, area.size.y)),
		Rect2(area.position, Vector2(area.size.x, covered.position.y - area.position.y)),
		Rect2(Vector2(area.position.x, covered.end.y), Vector2(area.size.x, area.end.y - covered.end.y))]
	var best := Rect2()
	for candidate: Rect2 in candidates:
		if candidate.size.x < 96 or candidate.size.y < 96: continue
		if candidate.get_area() > best.get_area(): best = candidate
	return best

func focus_team_leader(team_id: int) -> void:
	var leader := _team_info_leader(team_id)
	if leader.is_empty():
		show_result(Runtime.fail("UNAVAILABLE", "隊伍 #%d 的隊長不在場，無法定位。" % team_id))
		return
	lab._clear_movement_input()
	lab._dragging = false
	_cancel_facing_move()
	var area := _team_leader_focus_rect()
	if not area.has_area():
		formal_windows.team_info.hide()
		area = camera_usable_rect()
	var target := Vector2(leader.position)
	target += lab.terrain.surface_visual_offset_at(target)
	lab.camera.position = target + (lab.get_viewport_rect().size * 0.5 - area.get_center()) / lab.camera.zoom
	lab.camera.force_update_scroll()
	get_tree().root.grab_focus()

func clear_team_info_report() -> void:
	_team_info_report = ""
	_update_team_info()

func _yield_command_window(source: String) -> void:
	if source == "player":
		formal_windows.team.hide()
	elif is_instance_valid(combat_window):
		combat_window.hide()
	get_tree().root.grab_focus()

func invalidate_ui_context() -> void:
	_tech_window.context_changed()
	_cancel_facing_move()
	_clear_formation_candidate()
	drag_start = Vector2i(-1, -1)
	_ui_control_id = lab.controlled_person_id()
	for entry: Dictionary in _ui_dialogs.values().duplicate():
		if is_instance_valid(entry.dialog):
			entry.dialog.hide()
			if entry.dialog.is_inside_tree(): entry.dialog.get_parent().remove_child(entry.dialog)
			entry.dialog.queue_free()
	_ui_dialogs.clear()
	_equipment_sync = Callable()
	_equipment_result = Callable()
	_team_equipment_sync = Callable()
	_team_equipment_result = Callable()
	if is_instance_valid(_family_dialog):
		_family_dialog.hide()
		_family_dialog.get_parent().remove_child(_family_dialog)
		_family_dialog.queue_free()
	_family_dialog = null
	person_executor_id = lab.controlled_person_id()
	_formal_team_signature = ""
	_team_info_report = ""
	if is_instance_valid(lab.site_test_window): lab.site_test_window.context_changed()

func _dialog_host(host: Window) -> Node:
	return host if is_instance_valid(host) else lab.get_node("SiteUI")

func _focus_dialog(dialog: Window) -> void:
	var ancestors: Array[Window] = []
	var node := dialog.get_parent()
	while node != null:
		if node is Window: ancestors.push_front(node)
		node = node.get_parent()
	for window: Window in ancestors: window.show()
	dialog.show()
	dialog.grab_focus()

func _existing_dialog(key: String, context: String, host: Window = null) -> bool:
	if _ui_control_id != lab.controlled_person_id(): invalidate_ui_context()
	if not _ui_dialogs.has(key): return false
	var entry: Dictionary = _ui_dialogs[key]
	if not is_instance_valid(entry.dialog):
		_ui_dialogs.erase(key)
		return false
	_focus_dialog(entry.dialog)
	if entry.context != context or entry.host != _dialog_host(host):
		message.text = "此類表單已開啟：%s。請先關閉原表單，再切換目標或入口。" % entry.dialog.title
	return true

func _show_dialog(dialog: Window, key: String, context: String, host: Window = null) -> void:
	var parent := _dialog_host(host)
	dialog.force_native = false
	dialog.exclusive = false
	dialog.focus_entered.connect(func() -> void:
		lab._clear_movement_input()
		lab._dragging = false
		_cancel_facing_move())
	_ui_dialogs[key] = {"dialog": dialog, "context": context, "host": parent}
	dialog.tree_exiting.connect(func() -> void:
		if _ui_dialogs.has(key) and _ui_dialogs[key].dialog == dialog: _ui_dialogs.erase(key))
	parent.add_child(dialog)
	if parent is Window: parent.show()
	dialog.popup_centered()

func _build_building_controls(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	column.add_child(row)
	building_variant = _options(row, ["標準住宅", "小屋", "長屋", "大屋"], "BuildingVariant")
	for index: int in range(4): building_variant.set_item_metadata(index, ["standard", "small", "long", "large"][index])
	building_material = _options(row, ["木製", "石製"], "BuildingMaterial")
	building_material.set_item_metadata(0, "wood")
	building_material.set_item_metadata(1, "stone")
	building_direction = _options(row, ["朝南", "朝西", "朝北", "朝東"], "BuildingDirection")
	for choice: OptionButton in [building_variant, building_material, building_direction]:
		choice.custom_minimum_size.x = 110.0
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_variant.item_selected.connect(func(_index: int) -> void: _building_options_changed(true))
	building_material.item_selected.connect(func(_index: int) -> void: _building_options_changed(false))
	building_direction.item_selected.connect(func(_index: int) -> void: _building_direction_changed())
	building_size_row = HBoxContainer.new()
	column.add_child(building_size_row)
	_compact_label(building_size_row, "寬", 15)
	building_width = _number_input(building_size_row, "BuildingWidth", 1, 50, 3)
	_compact_label(building_size_row, "深", 15)
	building_depth = _number_input(building_size_row, "BuildingDepth", 1, 50, 3)
	building_width.value_changed.connect(func(_value: float) -> void: _building_options_changed(false))
	building_depth.value_changed.connect(func(_value: float) -> void: _building_options_changed(false))
	building_policy = _label(column, "", 15)
	building_policy.name = "BuildingSizePolicy"
	_button(column, "在所選格預覽尺寸／旋轉可按 R", "PreviewBuildingSize", func() -> void:
		modes.select(5)
		_set_building_footprint(selected, Vector2i(int(building_width.value), int(building_depth.value))))

func _build_building_actions(column: VBoxContainer) -> void:
	column.add_child(HSeparator.new())
	building_selection = _label(column, "點選已建設的格子以查看設施", 16)
	building_selection.name = "SelectedBuilding"
	building_recipe = _options(column, [], "BuildingRecipe")
	building_recipe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_actions.recipe = _button(column, "套用加工配方", "ChangeFeatureRecipe", _request_building_recipe)
	building_actions.upgrade = _button(column, "普通建物升級", "UpgradeFeatureGrade", _request_building_upgrade)
	building_actions.resize = _button(column, "調整所選設施占地（保留原設施）", "ResizeFeature", _begin_building_resize)
	building_actions.cancel_resize = _button(column, "取消建設預覽／擴縮", "CancelBuildingDraft", _cancel_building_draft)
	var row := HBoxContainer.new()
	column.add_child(row)
	building_actions.open_gate = _button(row, "開門", "OpenGate", func() -> void: _request_building_gate(true))
	building_actions.close_gate = _button(row, "關門", "CloseGate", func() -> void: _request_building_gate(false))
	building_parts = _options(column, ["未選取結構部件"], "BuildingPart")
	row = HBoxContainer.new()
	column.add_child(row)
	building_actions.repair = _button(row, "派工修復部件", "RepairFeaturePart", _request_building_repair)
	building_actions.attack = _button(row, "本人攻擊部件", "AttackStructurePart", func() -> void:
		show_result(person_actions.begin_structure_attack(lab.controlled_person_id(), feature_key, _building_part_id())))
	row = HBoxContainer.new()
	column.add_child(row)
	var quantity := _number_input(row, "UnstockLivestockCount", 1, Runtime.CARRY_CAPACITY, 1)
	building_actions.unstock = _button(row, "從所選牧場帶出牲畜", "UnstockPasture", func() -> void: unstock_controlled_livestock(int(quantity.value)))
	building_actions.storage = _button(column, "設施庫存／原人物及車輛裝卸", "ManageFeatureStock", _open_feature_storage)
	building_actions.prison = _button(column, "戰俘營名單／押送入監／解放", "ManagePrison", _open_prison)
	building_actions.garrison = _button(column, "軍營名冊／入營解編／編成出營", "ManageGarrison", _open_garrison)
	building_actions.housing = _button(column, "住宅名單／分配／返家／離住", "ManageHousing", _open_housing)
	building_actions.training = _button(column, "在校場開始本隊訓練", "TrainAtGround", func() -> void: show_result(order_controlled_training(true, feature_key)))
	building_actions.shipyard = _button(column, "在車輛與運輸視窗造船…", "OpenSelectedShipyard", _open_selected_shipyard)

func _feature_stock_choices(choice: OptionButton, preferred: String = "") -> void:
	choice.clear()
	var entries: Array[Dictionary] = [{"id": "depot", "label": "原營地"},
		{"id": "person:%d" % lab.controlled_person_id(), "label": "本人原行囊"}]
	var keys: Array = lab.terrain.site.get("stockpiles", {}).keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var feature: Dictionary = lab.terrain.site.features.get(key, {})
		if not feature.is_empty(): entries.append({"id": Stockpiles.identity(key), "label": "#%s %s" % [key, _building_name(feature)]})
	for key: String in vehicles.records():
		var vehicle: Dictionary = vehicles.records()[key]
		if str(vehicle.kind) in ["cart", "wagon"]: entries.append({"id": key, "label": "原%s #%s" % ["物資車" if str(vehicle.kind) == "cart" else "馬車", key]})
	for entry: Dictionary in entries:
		choice.add_item(str(entry.label))
		choice.set_item_metadata(choice.item_count - 1, str(entry.id))
		if str(entry.id) == preferred: choice.select(choice.item_count - 1)

func _open_feature_storage() -> void:
	var key := feature_key
	var feature: Dictionary = lab.terrain.site.features.get(key, {})
	if not Stockpiles.eligible(feature): return
	if _existing_dialog("feature_stock", key): return
	var person := person_actions._person(lab.controlled_person_id())
	if person.is_empty(): return
	var opened := Stockpiles.ensure_storage(lab.terrain, key, int(person.faction))
	if not opened.ok:
		show_result(opened)
		return
	var dialog := Window.new()
	dialog.title = "原設施庫存 #%s · %s" % [key, _building_name(feature)]
	dialog.size = Vector2i(740, 640)
	dialog.min_size = Vector2i(640, 540)
	dialog.close_requested.connect(dialog.queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_label(column, "材料與裝備保留原物權；本人須到入口或同時鄰接兩個庫存。\n遠處倉庫的物資須由本人或原車輛實際載運。原裝卸不自動往返。\n群眾人物須先沿原手動收回入口轉回一般人物，再現場裝卸。", 17)
	if str(feature.kind) != "warehouse":
		var local := CheckBox.new()
		local.name = "LocalFeatureSupply"
		local.text = "以本人卸入這座設施的現場材料加工"
		local.button_pressed = str(feature.get("supply_mode", "")) == "local"
		column.add_child(local)
		local.toggled.connect(func(enabled: bool) -> void:
			var current := person_actions._person(lab.controlled_person_id())
			var changed := Stockpiles.set_local_supply(lab.terrain, key, enabled, int(current.get("faction", -1)))
			show_result(changed)
			local.set_pressed_no_signal(str(lab.terrain.site.features.get(key, {}).get("supply_mode", "")) == "local"))
	var row := HBoxContainer.new()
	column.add_child(row)
	var source := _options(row, [], "FeatureStockSource")
	var destination := _options(row, [], "FeatureStockDestination")
	for choice: OptionButton in [source, destination]: choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feature_stock_choices(source, Stockpiles.identity(key))
	_feature_stock_choices(destination, "person:%d" % lab.controlled_person_id())
	var status := _label(column, "", 16)
	status.name = "FeatureStockStatus"
	row = HBoxContainer.new()
	column.add_child(row)
	var resource := _options(row, [], "FeatureStockResource")
	resource.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: String in Env.ITEM_NAMES:
		resource.add_item(str(Env.ITEM_NAMES[item]))
		resource.set_item_metadata(resource.item_count - 1, item)
	var quantity := _number_input(row, "FeatureStockQuantity", 1, 1000000, 1)
	var items := _options(column, [], "FeatureStockItem")
	var snapshot := {"source_version": -1, "destination_version": -1}
	var refresh := func() -> void:
		var left: Dictionary = vehicles._stock(str(source.get_item_metadata(source.selected)), true)
		var right: Dictionary = vehicles._stock(str(destination.get_item_metadata(destination.selected)), true)
		items.clear()
		if left.is_empty() or right.is_empty():
			status.text = "原庫存不存在或車輛尚未停妥；停止後重新整理。"
			snapshot["source_version"] = -1
			snapshot["destination_version"] = -1
			return
		snapshot["source_version"] = int(left.holder.version)
		snapshot["destination_version"] = int(right.holder.version)
		_vehicle_item_choices(items, left.holder)
		status.text = "來源 格%s · 載量 %.0f／%d · %s\n目的 格%s · 載量 %.0f／%d · %s" % [
			left.cell, Runtime.carried_load(lab.terrain.site, left.cargo, left.holder), int(left.capacity), Runtime.items_text(left.cargo),
			right.cell, Runtime.carried_load(lab.terrain.site, right.cargo, right.holder), int(right.capacity), Runtime.items_text(right.cargo)]
	row = HBoxContainer.new()
	column.add_child(row)
	_button(row, "實際裝卸所選資源", "TransferFeatureStockResource", func() -> void:
		var resources := {str(resource.get_item_metadata(resource.selected)): int(quantity.value)}
		show_result(vehicles.transfer(str(source.get_item_metadata(source.selected)), str(destination.get_item_metadata(destination.selected)),
			resources, [], int(snapshot.source_version), int(snapshot.destination_version), lab.controlled_person_id()))
		refresh.call())
	_button(row, "實際装卸所選原物品", "TransferFeatureStockItem", func() -> void:
		var id := str(items.get_item_metadata(items.selected)) if items.selected >= 0 else ""
		if id.is_empty():
			show_result(Runtime.fail("EMPTY"))
			return
		show_result(vehicles.transfer(str(source.get_item_metadata(source.selected)), str(destination.get_item_metadata(destination.selected)),
			{}, [id], int(snapshot.source_version), int(snapshot.destination_version), lab.controlled_person_id()))
		refresh.call())
	_button(column, "重新整理原庫存與版本", "RefreshFeatureStock", refresh)
	source.item_selected.connect(func(_index: int) -> void: refresh.call())
	destination.item_selected.connect(func(_index: int) -> void: refresh.call())
	_show_dialog(dialog, "feature_stock", key)
	refresh.call()

# These controls hold only a stale-input context. Runtime remains the only
# recipe, paid-batch, construction, authority and durability owner.
func _building_economy_context_matches(control: Control) -> bool:
	var context: Dictionary = control.get_meta(&"building_context", {})
	return not context.is_empty() and is_same(context.data, lab.terrain) and str(context.key) == feature_key \
		and int(context.person_id) == lab.controlled_person_id() \
		and is_same(context.feature, lab.terrain.site.features.get(feature_key, {}))

func _sync_building_economy(feature: Dictionary) -> void:
	var requester := person_actions._person(lab.controlled_person_id())
	var faction := int(requester.get("faction", -1))
	var context := {"data": lab.terrain, "key": feature_key, "person_id": lab.controlled_person_id(), "feature": feature,
		"recipe_id": str(feature.get("recipe_id", "")), "grade": Runtime.building_grade(feature)}
	var kind := str(feature.get("kind", ""))
	var owned := not requester.is_empty() and faction >= 0 and faction == int(feature.get("owner_faction", -1))
	var has_recipes := Runtime.FEATURE_RECIPES.has(kind)
	var selected_recipe := str(feature.get("recipe_id", ""))
	# Routine update_ui must preserve an uncommitted dropdown selection while
	# its original feature/person/current recipe remain the same.
	if _building_economy_context_matches(building_recipe) and building_recipe.selected >= 0:
		var previous: Dictionary = building_recipe.get_meta(&"building_context")
		if str(previous.recipe_id) == selected_recipe:
			var draft: Variant = building_recipe.get_item_metadata(building_recipe.selected)
			if draft is String: selected_recipe = draft
	building_recipe.set_meta(&"building_context", context)
	building_actions.upgrade.set_meta(&"building_context", context)
	building_recipe.set_block_signals(true)
	building_recipe.clear()
	if has_recipes:
		var choices: Array = [""] + Runtime.FEATURE_RECIPES[kind].keys()
		for recipe: String in choices:
			var projection := feature.duplicate()
			if recipe.is_empty(): projection.erase("recipe_id")
			else: projection["recipe_id"] = recipe
			var definition := Runtime.feature_recipe(projection)
			building_recipe.add_item("原配方 · " + Runtime.items_text(definition.output) if recipe.is_empty() else str(definition.recipe_name))
			building_recipe.set_item_metadata(building_recipe.item_count - 1, recipe)
			if recipe == selected_recipe: building_recipe.select(building_recipe.item_count - 1)
	else:
		building_recipe.add_item("此設施沒有可切換的加工配方")
	building_recipe.set_block_signals(false)
	var busy := feature.has("pending_build") or feature.has("repair") or bool(feature.get("batch_paid", false)) \
		or float(feature.get("production", 0.0)) > 0.0 or Runtime._feature_has_work(lab.terrain, feature_key) \
		or Runtime._feature_operation_active(lab.terrain, feature_key)
	building_recipe.disabled = not has_recipes or not owned or str(feature.get("stage", "")) != "complete" or busy
	building_actions.recipe.disabled = building_recipe.disabled
	if int(feature.get("owner_faction", -1)) >= 0 and not owned: building_actions.repair.disabled = true
	building_recipe.tooltip_text = "先停止工作區並領出原已付批次，再選配方、按套用。配方由原設施保存，現場材料由本人或原車輛實際送入。"
	var upgrade := Runtime.request_upgrade(lab.terrain, feature_key, faction, reserves_cell, true) if owned else Runtime.fail("NO_AUTHORITY", "請由設施管理方人物安排升級")
	building_actions.upgrade.disabled = not upgrade.ok
	building_actions.upgrade.text = "升級至 %d 級（占地與入口保持）" % int(upgrade.target_grade) if upgrade.ok else "普通建物升級"
	building_actions.upgrade.tooltip_text = "投入 %s · 有效工時 %.1f 分；完工保留當下受損比例。" % [Runtime.items_text(upgrade.cost), float(upgrade.work)] if upgrade.ok else str(upgrade.message)
	if kind == "settlement_center" and feature.get("parts", {}).has("body"):
		building_selection.text += "\n聚落中心 · 本體耐久 %.0f／%.0f%s；等級與人口見聚落頁" % [float(feature.parts.body.hp), Runtime.civil_max_hp(feature), " · 受損停效，先修復" if not Runtime.feature_usable(feature) else ""]
	elif int(feature.get("civil_version", 0)) == Runtime.CIVIL_VERSION:
		building_selection.text += "\n等級 %d／3 · 本體耐久 %.0f／%.0f%s" % [Runtime.building_grade(feature), float(feature.parts.body.hp), Runtime.civil_max_hp(feature), " · 已毀損，先修復" if not Runtime.feature_usable(feature) else ""]
	elif kind in Runtime.CIVIL_KINDS and not feature.is_empty():
		building_selection.text += "\n原建物；明確升級後採用新的等級與本體耐久。"
	if has_recipes and str(feature.get("stage", "")) == "complete":
		var definition := Runtime.feature_recipe(feature)
		building_selection.text += "\n配方：%s · 供料：%s" % [str(definition.get("recipe_name", "原配方")), "本人卸入此設施的現場庫存" if str(feature.get("supply_mode", "")) == "local" else "原營地"]

func _request_building_recipe() -> void:
	if not _building_economy_context_matches(building_recipe):
		show_result(Runtime.fail("STALE_SOURCE", "原設施或控制人物已變更，請重新選擇配方"))
		return
	var context: Dictionary = building_recipe.get_meta(&"building_context")
	var feature: Dictionary = context.feature
	if str(feature.get("recipe_id", "")) != str(context.recipe_id) or building_recipe.selected < 0:
		show_result(Runtime.fail("STALE_SOURCE", "原配方已變更，請重新選擇"))
		return
	var requester := person_actions._person(lab.controlled_person_id())
	var result := Runtime.request_feature_recipe(lab.terrain, feature_key, str(building_recipe.get_item_metadata(building_recipe.selected)), int(requester.get("faction", -1)))
	if result.ok: view.refresh()
	show_result(result)

func _request_building_upgrade() -> void:
	if not _building_economy_context_matches(building_actions.upgrade):
		show_result(Runtime.fail("STALE_SOURCE", "原設施或控制人物已變更，請重新選擇升級"))
		return
	var context: Dictionary = building_actions.upgrade.get_meta(&"building_context")
	if Runtime.building_grade(context.feature) != int(context.grade):
		show_result(Runtime.fail("STALE_SOURCE", "原建物等級已變更，請重新選擇升級"))
		return
	var requester := person_actions._person(lab.controlled_person_id())
	var result := Runtime.request_upgrade(lab.terrain, feature_key, int(requester.get("faction", -1)), reserves_cell)
	if result.ok:
		enable_worker()
		view.refresh()
	show_result(result)


func _building_summary_counts(counts: Dictionary) -> String:
	var rows: PackedStringArray = []
	var keys := counts.keys()
	keys.sort()
	for kind: String in keys:
		var entry: Dictionary = counts[kind]
		rows.append("%s：已完成 %d／施工 %d／規劃 %d" % [str(Runtime.FEATURES.get(kind, {}).get("name", kind)),
			int(entry.get("complete", 0)), int(entry.get("building", 0)), int(entry.get("planned", 0))])
	return "\n".join(rows) if not rows.is_empty() else "沒有已保存的建設。"

func _query_saved_building_overview(dialog: Window, output: Label, whole_world: bool, region: Vector2i) -> void:
	var slot: RegionSaveSlot = region_slot
	if slot == null:
		output.text = "先沿原旅行入口開啟固定地圖存檔。"
		return
	var index := slot.known_saved_sites()
	if not index.ok:
		output.text = str(index.get("message", "無法讀取原存檔"))
		return
	var ticket := int(dialog.get_meta("query_ticket", 0)) + 1
	dialog.set_meta("query_ticket", ticket)
	var summaries: Array[Dictionary] = []
	var selected_entry: Array[Vector2i] = []
	for coordinate: Vector2i in index.sites:
		if whole_world or RegionGrid.region_of(coordinate) == region: selected_entry.append(coordinate)
	for coordinate: Vector2i in selected_entry:
		if not is_instance_valid(dialog) or dialog.is_queued_for_deletion() or int(dialog.get_meta("query_ticket", 0)) != ticket: return
		if region_slot != slot:
			output.text = "原地圖存檔已切換，請重新查詢。"
			return
		if int(slot._marker.get("generation", 0)) != int(index.generation):
			output.text = "保存版本已變更，請重新查詢。"
			return
		# The original resolver was checked once above. Reading all marker files
		# for every single row would turn this read-only page into quadratic work.
		var summary := RegionSaveSlot.read_site_building_summary(slot, coordinate, slot.site_path(coordinate))
		if not summary.ok:
			output.text = "地點 %s：%s" % [coordinate, str(summary.get("message", "原快照無法讀取"))]
			return
		summaries.append(summary)
		output.text = "正在查閱已保存建設：%d／%d" % [summaries.size(), selected_entry.size()]
		await get_tree().process_frame
	if not is_instance_valid(dialog) or dialog.is_queued_for_deletion() or int(dialog.get_meta("query_ticket", 0)) != ticket: return
	var latest := slot.known_saved_sites()
	if not latest.ok or int(latest.generation) != int(index.generation) or str(latest.scope) != str(index.scope):
		output.text = "保存版本已變更，請重新查詢。"
		return
	var combined := RegionSaveSlot.aggregate_building_summaries(summaries)
	if not combined.ok:
		output.text = str(combined.get("message", "建設摘要無法合併"))
		return
	var rows: PackedStringArray = ["%s · 已保存地點 %d" % ["本世界" if whole_world else "本區域", int(combined.visited_sites)]]
	var regions: Array = combined.regions.keys()
	regions.sort()
	for identity: String in regions:
		var entry: Dictionary = combined.regions[identity]
		rows.append("\n%s · %d 個地點\n%s" % [identity, int(entry.sites), _building_summary_counts(entry.counts)])
	rows.append("\n以原保存內容查閱。未造訪地點不建立人物或物資；此頁不推進生產。")
	output.text = "\n".join(rows)

func _open_region_building_summary() -> void:
	if region_slot == null:
		show_result(Runtime.fail("NO_SLOT", "先沿原旅行入口開啟固定地圖存檔"))
		return
	if _existing_dialog("region_buildings", "saved"): return
	var coordinate := region_slot._coordinate(lab.terrain)
	if not coordinate.ok:
		show_result(coordinate)
		return
	var dialog := Window.new()
	dialog.title = "地圖與建設 · 原保存摘要"
	dialog.size = Vector2i(820, 660)
	dialog.min_size = Vector2i(640, 500)
	dialog.close_requested.connect(dialog.queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_label(column, "查閱這個世界存檔的建設。地圖查詢不新建地點，也不進行生產或補算。", 17)
	var row := HBoxContainer.new()
	column.add_child(row)
	var x := _number_input(row, "BuildingSummarySiteX", -10000000, 10000000, coordinate.site.x)
	var y := _number_input(row, "BuildingSummarySiteY", -10000000, 10000000, coordinate.site.y)
	var scroll := ScrollContainer.new()
	scroll.name = "BuildingSummaryScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var output := _label(scroll, "選擇地點，或查閱本區域／本世界已保存的建設。", 16)
	output.name = "BuildingSummaryResult"
	output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_button(buttons, "查閱所選地點", "ReadSiteBuildingSummary", func() -> void:
		dialog.set_meta("query_ticket", int(dialog.get_meta("query_ticket", 0)) + 1)
		if region_slot == null: return
		var summary := region_slot.building_summary(Vector2i(int(x.value), int(y.value)))
		if not summary.ok:
			output.text = str(summary.get("message", "原保存內容無法讀取"))
			return
		output.text = "%s\n%s\n%s" % [str(summary.site_id), "已造訪／已保存" if bool(summary.visited) else "尚未造訪", _building_summary_counts(summary.counts)])
	_button(buttons, "本區域已保存建設", "ReadRegionBuildingSummary", func() -> void:
		_query_saved_building_overview(dialog, output, false, RegionGrid.region_of(coordinate.site)))
	_button(buttons, "本世界已保存建設", "ReadWorldBuildingSummary", func() -> void:
		_query_saved_building_overview(dialog, output, true, Vector2i.ZERO))
	_show_dialog(dialog, "region_buildings", "saved")


func _building_kind() -> String:
	return str(buildings.get_item_metadata(buildings.selected).kind) if buildings.selected >= 0 else ""

func _building_choice(kind: String, camp_type: String = "standard") -> int:
	for index: int in buildings.item_count:
		var choice: Dictionary = buildings.get_item_metadata(index)
		if str(choice.kind) == kind and (kind != "barracks" or str(choice.camp_type) == camp_type): return index
	return -1

func _building_name(feature: Dictionary) -> String:
	return Runtime.barracks_type_name(feature) if str(feature.get("kind", "")) == "barracks" else str(Runtime.FEATURES.get(str(feature.get("kind", "")), {}).get("name", "設施"))

func _building_options() -> Dictionary:
	var options := {"layout_version": 1, "quarter": building_direction.selected}
	if _building_kind() == "house": options["variant"] = str(building_variant.get_item_metadata(building_variant.selected))
	if _building_kind() in ["wall_stairs", "gate"]: options["material"] = str(building_material.get_item_metadata(building_material.selected))
	if _building_kind() == "barracks": options["camp_type"] = str(buildings.get_item_metadata(buildings.selected).camp_type)
	if _building_kind() in Runtime.WATERFRONT_KINDS:
		var bounds: Rect2i = Runtime._cell_bounds(lab.terrain, build_cells) if not build_cells.is_empty() else Rect2i(selected, Vector2i(int(building_width.value), int(building_depth.value)))
		options["waterfront_version"] = 1
		options["launch_cell"] = _waterfront_launch_cell(bounds, building_direction.selected)
	var person := person_actions._person(lab.controlled_person_id())
	if not person.is_empty(): options["owner_faction"] = int(person.faction)
	if _building_kind() == "irrigation_channel": options["irrigation"] = _irrigation_options()
	return options

func _building_kind_changed() -> void:
	building_resize = false
	_building_options_changed(true)

func _building_direction_changed() -> void:
	if _building_controls_sync: return
	if building_resize:
		building_direction.select(_building_quarter)
		show_result(Runtime.fail("INVALID", "擴縮保持原方向與材質"))
		return
	if absi(building_direction.selected - _building_quarter) % 2 == 1:
		_building_controls_sync = true
		var width := building_width.value
		building_width.value = building_depth.value
		building_depth.value = width
		_building_controls_sync = false
	_building_quarter = building_direction.selected
	_building_options_changed(false)

func _sync_building_controls(reset_size: bool = false) -> void:
	if not is_instance_valid(building_width) or lab.terrain == null: return
	var spec := Runtime.building_spec(_building_kind(), _building_options())
	if not spec.ok: return
	_building_controls_sync = true
	var fixed := str(spec.placement) == "fixed"
	var minimum: Vector2i = spec.size if fixed else spec.min_size
	var maximum: Vector2i = spec.size if fixed else spec.max_size
	building_width.min_value = minimum.x
	building_width.max_value = maximum.x
	building_depth.min_value = minimum.y
	building_depth.max_value = maximum.y
	if fixed or reset_size:
		building_width.value = minimum.x
		building_depth.value = minimum.y
	building_width.editable = not fixed
	building_depth.editable = not fixed
	building_variant.visible = not spec.variants.is_empty()
	building_variant.disabled = building_resize
	building_material.visible = spec.materials.size() > 1
	building_material.disabled = building_resize
	building_direction.disabled = building_resize or not bool(spec.rotatable)
	building_policy.text = ("固定版型 %d×%d 格；旋轉同步改變占地" % [minimum.x, minimum.y]) if fixed else ("寬深 %d–%d／%d–%d 格，單次最多 %d 格" % [minimum.x, maximum.x, minimum.y, maximum.y, int(spec.max_cells)])
	building_policy.text += "\n每格 2×2 公尺；框選後按安排施工。"
	if _building_kind() in Runtime.WATERFRONT_KINDS:
		building_policy.text += "\n占地全部在岸上；水面在入口反側，船尾泊位接鄰岸格。轉向選址須能容下整船與出水道。"
	if _building_kind() == "barracks": building_policy.text += "\n" + Runtime.barracks_type_description(buildings.get_item_metadata(buildings.selected))
	if _building_kind() == "tent":
		building_policy.text = "營帳固定 3×3 格；由後勤攜帶帳篷包，在後勤視窗部署及收納。"
	var arrange := lab.find_child("BuildFeature", true, false) as Button
	if arrange != null: arrange.disabled = _building_kind() == "tent"
	_building_quarter = building_direction.selected
	_building_controls_sync = false

func _building_options_changed(reset_size: bool) -> void:
	if _building_controls_sync or lab.terrain == null: return
	_sync_building_controls(reset_size)
	if modes.selected == 5:
		var anchor := selected
		if not build_cells.is_empty(): anchor = Runtime._cell_bounds(lab.terrain, build_cells).position
		_set_building_footprint(anchor, Vector2i(int(building_width.value), int(building_depth.value)))
	else:
		update_ui()

func _set_building_footprint(anchor: Vector2i, extent: Vector2i) -> void:
	var proposal := Runtime.building_cells(lab.terrain, _building_kind(), anchor, extent, _building_options())
	build_cells.clear()
	if proposal.ok:
		build_cells.assign(proposal.cells)
		view.selection = proposal.bounds
		_building_controls_sync = true
		building_width.value = proposal.bounds.size.x
		building_depth.value = proposal.bounds.size.y
		_building_controls_sync = false
	else:
		view.selection = Rect2i(anchor, extent).intersection(Rect2i(Vector2i.ZERO, lab.terrain.size))
		message.text = str(proposal.message)
	update_ui()

func _begin_building_resize() -> void:
	var feature: Dictionary = lab.terrain.site.features.get(feature_key, {})
	if feature.is_empty() or str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) != 1:
		show_result(Runtime.fail("INVALID", "需已完成的新布局設施"))
		return
	var spec := Runtime.building_spec(str(feature.kind), Runtime._feature_options(feature))
	if not spec.ok or str(spec.placement) == "fixed":
		show_result(Runtime.fail("INVALID", "固定版型不能任意擴縮"))
		return
	modes.select(5)
	building_resize = true
	buildings.select(_building_choice(str(feature.kind), Runtime.barracks_type(feature)))
	building_direction.select(int(feature.quarter))
	building_material.select(1 if str(feature.material) == "stone" else 0)
	build_cells.assign(feature.cells)
	_sync_building_controls(false)
	var bounds := Runtime._cell_bounds(lab.terrain, build_cells)
	_building_controls_sync = true
	building_width.value = bounds.size.x
	building_depth.value = bounds.size.y
	_building_controls_sync = false
	view.selection = bounds
	message.text = "擴縮 #%s：框選新的完整占地，再按安排施工。原方向、物品與人物保持。" % feature_key
	update_ui()

func _cancel_building_draft() -> void:
	building_resize = false
	build_cells.clear()
	drag_start = Vector2i(-1, -1)
	view.selection = Rect2i()
	view.set_building_preview({})
	if modes.selected == 5: modes.select(0)
	_sync_building_controls(false)
	update_ui()

func _building_part_id() -> String:
	return str(building_parts.get_item_metadata(building_parts.selected)) if building_parts.selected >= 0 and building_parts.get_item_metadata(building_parts.selected) != null else ""

func _building_part_label(part_id: String, part: Dictionary) -> String:
	if part_id == "body": return "建物本體"
	if part_id.begins_with("leaf:"): return "左門葉" if part_id.ends_with("left") else "右門葉"
	if part_id.begins_with("frame:"): return "左門框" if part_id.ends_with("left") else "右門框"
	var cell: Vector2i = lab.terrain.cell_from_index(int(part.cells[0]))
	return "%s（%d，%d）" % ["階梯" if str(part.role) == "stairs" else "牆段", cell.x, cell.y]

func _sync_building_actions() -> void:
	if not is_instance_valid(building_selection): return
	var feature: Dictionary = lab.terrain.site.features.get(feature_key, {})
	var kind := str(feature.get("kind", ""))
	var complete := str(feature.get("stage", "")) == "complete"
	var current_part := _building_part_id()
	building_parts.clear()
	var geometry := Runtime.feature_geometry(lab.terrain, feature)
	for part_id: String in geometry.parts:
		var part: Dictionary = geometry.parts[part_id]
		building_parts.add_item("%s · 耐久 %.0f／%.0f" % [_building_part_label(part_id, part), float(part.hp), float(part.max_hp)])
		building_parts.set_item_metadata(building_parts.item_count - 1, part_id)
		if part_id == current_part: building_parts.select(building_parts.item_count - 1)
	if building_parts.item_count == 0: building_parts.add_item("此設施沒有可修復的結構部件")
	building_parts.disabled = geometry.parts.is_empty()
	var selected_part: Dictionary = geometry.parts.get(_building_part_id(), {})
	building_actions.repair.disabled = not complete or selected_part.is_empty() or float(selected_part.get("hp", 0.0)) >= float(selected_part.get("max_hp", 0.0)) or feature.has("pending_build") or feature.has("repair")
	building_actions.attack.disabled = not complete or geometry.parts.is_empty()
	building_actions.open_gate.disabled = not complete or kind != "gate"
	building_actions.close_gate.disabled = not complete or kind != "gate"
	building_actions.unstock.disabled = not complete or kind not in ["pasture", "horse_ranch"]
	building_actions.storage.disabled = not complete or not Stockpiles.eligible(feature)
	building_actions.prison.disabled = not complete or kind != "prison"
	building_actions.garrison.disabled = not complete or kind != "barracks"
	building_actions.housing.disabled = not complete or kind != "house"
	var training_facility := kind == "training_ground" or (kind == "barracks" and Runtime.barracks_type(feature) == "standard")
	building_actions.training.disabled = not complete or not training_facility
	building_actions.shipyard.disabled = not complete or kind != "shipyard"
	building_actions.training.text = "在西式軍營開始本隊訓練" if kind == "barracks" and training_facility else "在校場開始本隊訓練"
	building_actions.resize.disabled = not complete or kind == "bridge" or int(feature.get("layout_version", 0)) != 1 or str(Runtime.FEATURES.get(kind, {}).get("placement", "fixed")) == "fixed"
	building_actions.cancel_resize.disabled = modes.selected != 5
	building_selection.text = "點選已建設的格子以查看設施" if feature.is_empty() else "所選 #%s · %s\n%s" % [feature_key, _building_name(feature), str(feature.status)]
	_sync_building_economy(feature)
	if kind == "gate":
		var gate: Dictionary = feature.get("gate", {})
		var pending := str(gate.get("pending", ""))
		var broken := 0
		for part_id: String in geometry.parts:
			if str(geometry.parts[part_id].role) == "leaf" and float(geometry.parts[part_id].hp) <= 0.0: broken += 1
		building_selection.text += "\n%s%s" % [("開門中" if pending == "open" else "關門中") if not pending.is_empty() else ("門已開" if bool(gate.get("open", false)) else "門已關"), " · %d 片門葉已毀" % broken if broken > 0 else ""]
	elif kind in ["barracks", "training_ground"]:
		var military := Runtime.military_layout(lab.terrain, feature_key)
		if military.ok: building_selection.text += "\n可用站位 %d（已扣除營舍／靶架）" % int(military.capacity)
		if kind == "barracks": building_selection.text += "\n" + Runtime.barracks_type_description(feature)
	elif kind == "house":
		var housing: Dictionary = Housing.query(lab, feature_key)
		if housing.ok: building_selection.text += "\n門前休息格 %d · 已登記 %d · 在家 %d" % [int(housing.capacity), int(housing.registered), int(housing.at_home)]
	elif kind == "bridge":
		building_selection.text += "\n一格寬單層橋面，橋下不通船；首版不支援部件攻擊、修理或擴建。"
	elif kind == "tent":
		building_selection.text += "\n後勤攜行營帳；請從後勤視窗收納，不能拆除換材料。"
	elif kind in Runtime.WATERFRONT_KINDS:
		building_selection.text += "\n船尾泊位 %s；岸上工位 %s。" % [lab.terrain.cell_from_index(int(feature.launch_cell)), lab.terrain.cell_from_index(int(feature.entrance))]
		if feature.has("ship_build"):
			building_selection.text += "\n原隊伍 #%d · 造船 %.1f／%.1f 分；已付材料保留。" % [int(feature.ship_build.team_id), float(feature.production), float(feature.ship_build.total_work) / 60.0]

func _request_building_gate(want_open: bool) -> void:
	show_result(Runtime.request_gate(lab.terrain, feature_key, want_open, lab.controlled_person_id(), _building_person_query, reserves_cell))

func _building_person_query(identity: int) -> Dictionary:
	var person := person_actions._person(identity)
	if person.is_empty(): return {}
	var result: Dictionary = person.duplicate()
	result["ready"] = not get_tree().paused and not bool(lab.terrain.site.paused) and person_actions._ready(person) and not person_actions.is_busy(identity)
	return result

func _request_building_repair() -> void:
	var requester := person_actions._person(lab.controlled_person_id())
	if requester.is_empty():
		show_result(Runtime.fail("NO_AUTHORITY"))
		return
	var result := Runtime.request_repair(lab.terrain, feature_key, _building_part_id(), int(requester.faction), reserves_cell)
	if result.ok:
		enable_worker()
		view.refresh()
	show_result(result)

func unstock_controlled_livestock(count: int) -> void:
	var person := person_actions._person(lab.controlled_person_id())
	if get_tree().paused or bool(lab.terrain.site.paused) or person.is_empty() or not person_actions._ready(person) or person_actions.is_busy(int(person.person_id)):
		show_result(Runtime.fail("BUSY", "本人須清醒、自由並停止其他作業"))
		return
	var limit := floori(Runtime.CARRY_CAPACITY - Runtime.carried_load(lab.terrain.site, {}, person.holder))
	var result := Runtime.unstock_pasture(lab.terrain, feature_key, person.cargo, person.cell, count, limit)
	if result.ok: person.holder.version = int(person.holder.version) + 1
	show_result(result)

func _prison_officer_description(officer: Dictionary) -> String:
	var abilities: Dictionary = officer.get("command_abilities", {})
	var appearance: Dictionary = officer.get("appearance", {})
	var parts: Dictionary = appearance.get("parts", {})
	var labels: Array[String] = []
	for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
		var key := str(slot.id)
		var asset := str(parts.get(key, "none"))
		if asset == "none": continue
		if key == "hair":
			for hair: Dictionary in HumanCharacter3DEditor.HAIR_OPTIONS[int(appearance.get("body", 0))]:
				if str(hair.id) == asset: labels.append(str(hair.label))
		else:
			labels.append(_item_label({"slot": key, "asset": asset}))
	return "原人物 #%d · 戰術 %s／領導 %s／教練 %s\n原外觀：%s" % [int(officer.person_id),
		str(abilities.get("tactics", "未登錄")), str(abilities.get("leadership", "未登錄")), str(abilities.get("coach", "未登錄")),
		"、".join(labels) if not labels.is_empty() else "未登錄"]

func _prison_regular_release_target(executor: int, query: Dictionary) -> Dictionary:
	if not query.ok: return query
	var officers := {}
	for officer: Dictionary in query.officers: officers[int(officer.person_id)] = true
	var failure := Runtime.fail("NO_TARGET", "營內沒有一般俘虜")
	for person: Dictionary in query.inmates:
		var identity := int(person.person_id)
		if officers.has(identity): continue
		var check := person_actions._prison_release_context(executor, identity)
		if check.ok: return Runtime.ok("", {"person_id": identity})
		failure = check
	return failure

func order_captive_adoption(target_id: int, offer: Dictionary) -> Dictionary:
	return PoliticalAdoption.command(lab, target_id, offer, int(lab.controlled_person_id()))

func _open_captive_adoption() -> void:
	var requester := int(lab.controlled_person_id())
	var original: TerrainData = lab.terrain
	var context := str([str(original.site.id), requester])
	if _existing_dialog("adoption", context): return
	var person: Dictionary = person_actions._person(requester, false)
	if person.is_empty(): show_result(Runtime.fail("NO_TARGET")); return
	var dialog := AcceptDialog.new()
	dialog.name = "CaptiveAdoptionDialog"
	dialog.title = "俘虜歸降／接收同意"
	dialog.min_size = Vector2i(580, 440)
	var column := VBoxContainer.new()
	dialog.add_child(column)
	_label(column, "本人願意、拘押方及戶籍官同意後，才依原出口與移交規則完成。\n他方職責 AI 關閉時，須由其本人明示操作；不會自動入隊或授官。", 15)
	var targets := _options(column, [], "AdoptionCaptives")
	var keys: Array = original.site.get("captivity", {}).keys()
	keys.sort()
	for key: String in keys:
		var relation: Dictionary = original.site.captivity[key]
		if int(relation.captor_faction) != int(person.faction) and int(key) != requester: continue
		targets.add_item("原俘虜 #%s" % key)
		targets.set_item_metadata(targets.item_count - 1, int(key))
	var nations := _options(column, [], "AdoptionNations")
	var nation_ids: Array = original.site.get("equipment_nations", {}).keys()
	nation_ids.sort()
	for nation_id: String in nation_ids:
		var nation: Dictionary = original.site.equipment_nations[nation_id]
		if not nation.has("offices") or equipment_orders.nation_head_executor(nation, true) <= 0: continue
		nations.add_item("目標國：%s" % nation_id)
		nations.set_item_metadata(nations.item_count - 1, nation_id)
	var teams := _options(column, [], "AdoptionTeams")
	for team: TerrainArmy in lab.combat_armies:
		if not is_instance_valid(team) or not team.combat_enabled or not team.garrison_feature_id.is_empty(): continue
		teams.add_item("接收隊伍 #%d · 陣營 %s" % [team.team_id, _faction_label(team.faction_id)])
		teams.set_item_metadata(teams.item_count - 1, team.team_id)
	var consent := CheckBox.new()
	consent.name = "AdoptionSelfConsent"
	consent.text = "若所選俘虜是本人，我明示願意歸降"
	column.add_child(consent)
	var result_label := _label(column, "期滿只進入處置評估；未完成合法交易仍在監。", 15)
	result_label.name = "AdoptionResult"
	var submit := _button(column, "以目前本人權責提出／接收歸降", "SubmitCaptiveAdoption", func() -> void:
		if lab.terrain != original or int(lab.controlled_person_id()) != requester:
			show_result(Runtime.fail("STALE", "Site 或控制人物已變更，請重新開啟")); return
		if targets.selected < 0 or nations.selected < 0 or teams.selected < 0: return
		var offer := {"nation_id": str(nations.get_item_metadata(nations.selected)), "destination_team_id": int(teams.get_item_metadata(teams.selected)), "consent": consent.button_pressed}
		var result := order_captive_adoption(int(targets.get_item_metadata(targets.selected)), offer)
		result_label.text = str(result.message) if result.ok else "%s：%s" % [str(result.code), str(result.message)]
		show_result(result)
		if result.ok: dialog.queue_free())
	submit.disabled = targets.item_count == 0 or nations.item_count == 0 or teams.item_count == 0
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_show_dialog(dialog, "adoption", context)

func _open_prison() -> void:
	var prison_id := feature_key
	var requester: int = lab.controlled_person_id()
	var executor := person_executor_id
	var context := str([prison_id, requester, executor])
	if _existing_dialog("prison", context): return
	var query := person_actions.prison_query(requester, prison_id)
	if not query.ok:
		show_result(query)
		return
	var original_data: TerrainData = lab.terrain
	var current_scope := func() -> bool:
		if lab.terrain != original_data or lab.controlled_person_id() != requester or person_executor_id != executor or feature_key != prison_id:
			show_result(Runtime.fail("STALE", "戰俘營／執行者／控制人物／Site 已變更，請重新開啟"))
			return false
		return true
	var dialog := AcceptDialog.new()
	dialog.name = "PrisonDialog"
	dialog.title = "戰俘營 #%s · 執行者 #%d" % [prison_id, executor]
	dialog.min_size = Vector2i(630, 610)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(590, 530)
	dialog.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var status := _label(column, "", 16)
	status.name = "PrisonStatus"
	_label(column, "軍官個別名冊", 16)
	var inmates := _options(column, [], "PrisonInmates")
	var officer_details := _label(column, "", 15)
	officer_details.name = "PrisonOfficerDetails"
	var regular := _label(column, "", 16)
	regular.name = "PrisonRegularCount"
	var activity := _label(column, "到原接觸格後解綁四秒；每次只執行 1 人。", 15)
	activity.name = "PrisonActionStatus"
	var show_action := func(result: Dictionary) -> void:
		activity.text = str(result.message) if result.ok else "%s：%s" % [str(result.code), str(result.message)]
		show_result(result)
	var current_officer := func() -> Dictionary:
		if not current_scope.call() or inmates.selected < 0: return {}
		var latest := person_actions.prison_query(requester, prison_id)
		if latest.ok:
			for officer: Dictionary in latest.officers:
				if int(officer.person_id) == int(inmates.get_item_metadata(inmates.selected)): return officer
		return {}
	var show_officer := func(_index: int = 0) -> void:
		var officer: Dictionary = current_officer.call()
		officer_details.text = _prison_officer_description(officer) if not officer.is_empty() else "沒有可查看的在監軍官"
	inmates.item_selected.connect(show_officer)
	var focus := _button(column, "在原地圖查看所選軍官外觀", "FocusPrisonOfficer", func() -> void:
		var officer: Dictionary = current_officer.call()
		if officer.is_empty():
			show_action.call(Runtime.fail("NO_TARGET", "原在監軍官已變更，請重新查詢"))
			return
		var target: Dictionary = lab._combat_target(int(officer.person_id))
		if target.is_empty(): return
		dialog.hide()
		lab._clear_movement_input()
		lab._dragging = false
		_cancel_facing_move()
		var point := Vector2(target.position)
		point += lab.terrain.surface_visual_offset_at(point)
		lab.camera.position = point + (lab.get_viewport_rect().size * 0.5 - camera_usable_rect().get_center()) / lab.camera.zoom
		lab.camera.force_update_scroll()
		get_tree().root.grab_focus())
	var release_officer := _button(column, "解放所選軍官（須到接觸格，解綁四秒）", "ReleasePrisoner", func() -> void:
		var officer: Dictionary = current_officer.call()
		if officer.is_empty():
			show_action.call(Runtime.fail("NO_TARGET", "原在監軍官已變更，請重新查詢"))
			return
		show_action.call(person_actions.begin_prison_release(executor, int(officer.person_id), requester)))
	var release_regular := _button(column, "解放接觸格旁的一般俘虜 1 人（四秒）", "ReleaseRegularPrisoner", func() -> void:
		if not current_scope.call(): return
		var candidate := _prison_regular_release_target(executor, person_actions.prison_query(requester, prison_id))
		show_action.call(person_actions.begin_prison_release(executor, int(candidate.person_id), requester) if candidate.ok else candidate))
	var refresh := func() -> void:
		if not current_scope.call(): return
		var old_id := int(inmates.get_item_metadata(inmates.selected)) if inmates.selected >= 0 else -1
		var result := person_actions.prison_query(requester, prison_id)
		inmates.clear()
		focus.disabled = true
		release_officer.disabled = true
		release_regular.disabled = true
		if not result.ok:
			status.text = str(result.message)
			regular.text = "一般俘虜數量暫不可查"
			officer_details.text = ""
			return
		status.text = "軍官 %d · 一般俘虜 %d · 已用 %d／共用容量 %d\n押送預留：軍官 %d · 一般 %d；可用 %d\n入口 %s" % [int(result.officer_count), int(result.regular_count), int(result.used), int(result.capacity), int(result.reserved_officers), int(result.reserved_regular), result.free_slots.size(), str(result.entry)]
		regular.text = "一般俘虜：%d 人；每次解放 1 人，完成後重新查詢。" % int(result.regular_count)
		for person: Dictionary in result.officers:
			inmates.add_item("軍官 #%d · HP %.0f · %s" % [int(person.person_id), float(person.get("hp", 0)), "昏迷" if float(person.get("ko", 0)) > 0.0 else "清醒"])
			inmates.set_item_metadata(inmates.item_count - 1, int(person.person_id))
			if int(person.person_id) == old_id: inmates.select(inmates.item_count - 1)
		inmates.disabled = result.officers.is_empty()
		focus.disabled = result.officers.is_empty()
		release_officer.disabled = result.officers.is_empty()
		release_regular.disabled = int(result.regular_count) == 0
		var job := person_actions.job_for(executor)
		activity.text = "出監解綁 %.1f／4.0 秒；完成前保留拘押。" % float(job.elapsed) if str(job.get("kind", "")) == "prison_release" else "目前沒有解綁作業；每次只執行 1 人。"
		show_officer.call()
	refresh.call()
	_button(column, "重新查詢名冊、數量與可用位置", "RefreshPrison", refresh)
	_button(column, "由指定看守押送原俘虜入監", "BeginPrisonEscort", func() -> void:
		if current_scope.call(): show_action.call(captive_escort.begin_prison(requester, executor, prison_id)))
	_button(column, "取消後續押送（拘押保留）", "CancelPrisonEscort", func() -> void:
		if current_scope.call(): show_action.call(captive_escort.cancel(executor)))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_show_dialog(dialog, "prison", context)

func _open_garrison() -> void:
	var barracks_id := feature_key
	var requester: int = lab.controlled_person_id()
	var original_data: TerrainData = lab.terrain
	var context := str([barracks_id, requester])
	if _existing_dialog("garrison", context): return
	var initial := Garrison.query(lab, barracks_id)
	if not initial.ok:
		show_result(initial)
		return
	var current := func() -> bool:
		if lab.terrain == original_data and lab.controlled_person_id() == requester and feature_key == barracks_id: return true
		show_result(Runtime.fail("STALE", "軍營或控制人物已變更，請重新開啟"))
		return false
	var dialog := AcceptDialog.new()
	dialog.name = "GarrisonDialog"
	dialog.title = "%s #%s · 未編成兵員" % [_building_name(lab.terrain.site.features[barracks_id]), barracks_id]
	dialog.min_size = Vector2i(680, 640)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(630, 550)
	dialog.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var status := _label(column, "", 17)
	status.name = "GarrisonStatus"
	_label(column, "軍官個別列出；士兵保留原人物，以人數選入新隊。入營及編成都須本人已在軍營內。", 15)
	var officers := ItemList.new()
	officers.name = "GarrisonOfficers"
	officers.select_mode = ItemList.SELECT_MULTI
	officers.custom_minimum_size = Vector2(580, 130)
	column.add_child(officers)
	_label(column, "新隊長（從軍官中指定）", 16)
	var commander := _options(column, [], "GarrisonCommander")
	var soldiers := _number_input(column, "GarrisonSoldierCount", 0, 200, 0)
	var soldier_label := _label(column, "", 16)
	soldier_label.name = "GarrisonSoldierSummary"
	var target := _options(column, [], "GarrisonTargetTeam")
	var source := _options(column, [], "GarrisonSourceTeam")
	var promotion := _options(column, [], "GarrisonPromotionCandidate")
	var action := _label(column, "選取軍官、士兵人數與空隊伍後編成。", 15)
	action.name = "GarrisonActionStatus"
	var refresh := func() -> void:
		if not current.call(): return
		var result := Garrison.query(lab, barracks_id)
		if not result.ok:
			status.text = str(result.message)
			return
		status.text = "軍官 %d · 士兵 %d · 在營 %d\n登記 %d／容量 %d · 被俘 %d · 營外 %d · 死亡 %d" % [result.officers.size(), int(result.soldier_count), int(result.people_count), int(result.registered_count), int(result.capacity), int(result.captive_count), int(result.away_count), int(result.dead_count)]
		status.text += "\n" + Runtime.barracks_type_description(lab.terrain.site.features[barracks_id])
		officers.clear()
		commander.clear()
		promotion.clear()
		var ready_soldiers := 0
		for person: Dictionary in result.people:
			if person.military_role == "officer":
				var row := officers.add_item("%s · HP %.0f · %s" % [person.name, float(person.hp), "昏迷" if float(person.ko) > 0.0 else "清醒"])
				officers.set_item_metadata(row, int(person.person_id))
				if float(person.hp) > 0.0 and float(person.ko) <= 0.0:
					commander.add_item(str(person.name))
					commander.set_item_metadata(commander.item_count - 1, int(person.person_id))
			elif person.military_role == "soldier" and float(person.hp) > 0.0 and float(person.ko) <= 0.0:
				ready_soldiers += 1
				promotion.add_item("候補士兵 #%d" % int(person.person_id))
				promotion.set_item_metadata(promotion.item_count - 1, int(person.person_id))
		soldiers.max_value = mini(199, ready_soldiers)
		soldier_label.text = "可選清醒士兵 %d 人；上方數字為本次編入人數。" % ready_soldiers
		target.clear()
		for id: int in result.empty_team_ids:
			target.add_item("空隊伍槽 #%d" % id)
			target.set_item_metadata(target.item_count - 1, id)
		source.clear()
		for team: Dictionary in Garrison._armies(lab):
			if str(team.garrison_feature_id).is_empty() and int(team.faction_id) == int(result.layout.owner_faction):
				source.add_item("入營隊伍 #%d · %d 人" % [int(team.team_id), team.rows.size()])
				source.set_item_metadata(source.item_count - 1, int(team.team_id))
	var finish := func(result: Dictionary) -> void:
		action.text = str(result.message)
		show_result(result)
		refresh.call()
	_button(column, "將指定原隊伍入營並解除現職", "AdmitGarrison", func() -> void:
		if current.call() and source.selected >= 0: finish.call(Garrison.admit(lab, barracks_id, int(source.get_item_metadata(source.selected)))))
	_button(column, "以所選軍官與士兵編成新隊伍", "FormGarrisonTeam", func() -> void:
		if not current.call(): return
		if commander.selected < 0 or target.selected < 0:
			finish.call(Runtime.fail("NO_TARGET", "須有清醒軍官及空隊伍槽"))
			return
		var identities: Array[int] = [int(commander.get_item_metadata(commander.selected))]
		for row: int in officers.get_selected_items():
			var identity := int(officers.get_item_metadata(row))
			if identity not in identities: identities.append(identity)
		var latest := Garrison.query(lab, barracks_id)
		if not latest.ok:
			finish.call(latest)
			return
		var count := int(soldiers.value)
		for person: Dictionary in latest.people:
			if count <= 0: break
			if person.military_role == "soldier" and float(person.hp) > 0.0 and float(person.ko) <= 0.0:
				identities.append(int(person.person_id))
				count -= 1
		finish.call(Garrison.form(lab, barracks_id, identities, identities[0], int(target.get_item_metadata(target.selected)))))
	_button(column, "晉任所選候補士兵為軍官", "PromoteGarrisonOfficer", func() -> void:
		if current.call() and promotion.selected >= 0: finish.call(Garrison.set_military_role(lab, int(promotion.get_item_metadata(promotion.selected)), "officer")))
	_button(column, "重新查詢軍營名冊", "RefreshGarrison", refresh)
	refresh.call()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_show_dialog(dialog, "garrison", context)

func _test_page_visible(key: String) -> bool:
	return is_instance_valid(combat_window) and combat_window.visible and _test_pages.has(key) and is_instance_valid(_test_pages[key]) and _test_pages[key].is_visible_in_tree()


func _ship_type_name(ship_type: String) -> String:
	return str({"ferry": "渡船", "river": "河船", "coastal": "沿海貨船", "troop": "運兵船", "patrol": "巡邏船", "tower": "樓船"}.get(ship_type, ship_type))

func _build_ship_controls(parent: Node, form: Dictionary) -> void:
	parent.add_child(HSeparator.new())
	_label(parent, "單 Site 船艦運輸", 20)
	_label(parent, "原人物登船、載物與供糧；船員包含在乘員人數內。先停隊並關閉 AI，再由岸邊登船。", 15)
	form["ship_berth"] = _number_input(parent, "ShipBerth", -1, 99, -1)
	form.ship_berth.prefix = "船席（-1 自動） "
	var row := HBoxContainer.new()
	parent.add_child(row)
	_button(row, "登上所選船", "ShipBoard", func() -> void: _ship_person_ui(form, "board"))
	_button(row, "離船到所選岸格", "ShipDisembark", func() -> void: _ship_person_ui(form, "disembark"))
	_button(parent, "原人物走到空駕駛席接替", "ShipTakeHelm", func() -> void: _ship_person_ui(form, "helm"))
	_button(parent, "取消此人的船上作業", "ShipCancelPerson", func() -> void:
		var person_id := _ship_ui_person(form)
		if person_id > 0: show_result(person_actions.cancel(person_id)))
	_button(parent, "查看本船遺物／本人搜刮", "ShipLootInventory", func() -> void:
		var person_id := _ship_ui_person(form)
		if person_id > 0:
			person_executor_id = person_id
			_open_person_inventory())
	row = HBoxContainer.new()
	parent.add_child(row)
	_button(row, "前進一格", "ShipForward", func() -> void: _ship_order_ui(form, "forward"))
	_button(row, "倒船一格", "ShipReverse", func() -> void: _ship_order_ui(form, "reverse"))
	row = HBoxContainer.new()
	parent.add_child(row)
	_button(row, "左轉", "ShipLeft", func() -> void: _ship_order_ui(form, "turn_left"))
	_button(row, "右轉", "ShipRight", func() -> void: _ship_order_ui(form, "turn_right"))
	_button(parent, "航行至所選水格", "ShipSail", func() -> void: _ship_order_ui(form, "sail"))
	_button(parent, "靠岸至所選船尾水格", "ShipDock", func() -> void: _ship_order_ui(form, "dock"))
	_button(parent, "完成目前船步後停止", "ShipStop", func() -> void: _ship_order_ui(form, "stop"))
	_button(parent, "潰退靠岸／離船", "ShipRetreat", func() -> void: _ship_order_ui(form, "dock", true))
	row = HBoxContainer.new()
	parent.add_child(row)
	_button(row, "所選人行囊 → 船艙", "ShipLoadPerson", func() -> void: _ship_cargo_ui(form, true))
	_button(row, "船艙 → 所選人行囊", "ShipUnloadPerson", func() -> void: _ship_cargo_ui(form, false))
	row = HBoxContainer.new()
	parent.add_child(row)
	_button(row, "所選岸點共用糧 → 船", "ShipSupplyLoad", func() -> void: _ship_supply_ui(form, true))
	_button(row, "船上共用糧 → 所選岸點", "ShipSupplyUnload", func() -> void: _ship_supply_ui(form, false))
	if not bool(form.trial):
		_build_ship_deck_controls(parent, form)
		_build_ship_repair_controls(parent, form)
	if bool(form.trial):
		_label(parent, "測試灰模船：正式造船與美術待後续接入。僅標記已存在的水面通行權，不修改地形。", 15)
		form["ship_type"] = _options(parent, ["渡船", "河船", "沿海貨船", "運兵船", "巡邏船", "樓船"], "ShipType")
		form["ship_facing"] = _options(parent, ["朝東", "朝南", "朝西", "朝北"], "ShipFacing")
		_button(parent, "開啟所選既有水體的測試通行", "ShipPermitWater", func() -> void: _ship_permit_water_ui())
		_button(parent, "在所選水格部署測試船", "ShipDeploy", func() -> void: _ship_deploy_ui(form))

func begin_ship_build(key: String, ship_type: String, team_id: int, requester_id: int, preview: bool = false) -> Dictionary:
	if get_tree().paused or bool(lab.terrain.site.paused): return Runtime.fail("BUSY", "造船須解除暫停")
	# G2: under crowd the team is the native owner; its duty authority is the original TerrainArmy that commands the requester.
	var owners: Array = lab.crowd_site.person_owners() if _crowd_active() else lab.combat_armies
	var team: Variant = null
	for original: Variant in owners:
		if int(original.team_id) == team_id: team = original; break
	var feature: Dictionary = lab.terrain.site.features.get(key, {})
	if team == null or not team.has_army() or feature.is_empty(): return Runtime.fail("NO_TARGET")
	if requester_id != lab.controlled_person_id() or not team.command_eligible(team.current_commander): return Runtime.fail("NO_AUTHORITY")
	var duty_owner: Variant = team
	if team is CrowdPersonOwner: duty_owner = team._command_owner(team.index_for_identity(requester_id))
	if not duty_owner is TerrainArmy: return Runtime.fail("NO_AUTHORITY")
	var ship_refused: Dictionary = duty_owner.duty_authority("team.ship", requester_id)
	if not ship_refused.is_empty(): return ship_refused
	var person: Dictionary = person_actions._person(requester_id)
	if person.is_empty() or int(person.faction) != team.faction_id or int(feature.get("owner_faction", -1)) != team.faction_id: return Runtime.fail("NO_AUTHORITY")
	if not person_actions._ready(person) or _person_has_duty(requester_id) or vehicles.is_embarked(requester_id) or team.is_sustain_routed() or not _team_stopped(team): return Runtime.fail("BUSY", "原指揮须可行動、無其他作業，全隊守位且停穩")
	return Runtime.begin_ship_build(lab.terrain, key, ship_type, team_id, int(person.faction), reserves_cell, preview)

func cancel_ship_build(key: String, requester_id: int, preview: bool = false) -> Dictionary:
	if get_tree().paused or bool(lab.terrain.site.paused): return Runtime.fail("BUSY")
	var person: Dictionary = person_actions._person(requester_id)
	var feature: Dictionary = lab.terrain.site.features.get(key, {})
	if requester_id != lab.controlled_person_id() or person.is_empty() or feature.is_empty() or int(person.faction) != int(feature.get("owner_faction", -1)): return Runtime.fail("NO_AUTHORITY")
	if not person_actions._ready(person) or _person_has_duty(requester_id) or vehicles.is_embarked(requester_id): return Runtime.fail("BUSY")
	return Runtime.cancel_ship_build(lab.terrain, key, int(person.faction), preview)

# CANDIDATE ONLY. Formal original transport window; no trial dispatch.
# Insert methods beside original begin_ship_build/cancel_ship_build.
func _ship_membership_change(team: TerrainArmy, identity: int, joining: bool) -> Dictionary:
	# The same original membership transaction remains authoritative. Reject the
	# last voluntary departure before its original supply/history mutates.
	var last_member: Dictionary = Runtime.team_last_member_refusal(lab.terrain, team, joining)
	if not bool(last_member.get("ok", false)): return last_member
	return captivity_supply.membership_change(team, identity, joining)

func _ship_repair_q_query(identity: String) -> Dictionary:
	var vehicle: Dictionary = vehicles.records().get(identity, {})
	if not SiteVehicleTransport.is_ship(vehicle): return Runtime.fail("NO_TARGET")
	return Runtime.ok("原乘載物品已查詢", {"load": vehicles.ship_load(identity), "capacity": float(SiteVehicleTransport.capacity_of(vehicle))})

func _ship_repair_authority(identity: String, requester_id: int, starting: bool) -> Dictionary:
	if _crowd_active() or get_tree().paused or bool(lab.terrain.site.paused): return Runtime.fail("BUSY")
	var vehicle: Dictionary = vehicles.records().get(identity, {})
	var person: Dictionary = person_actions._person(requester_id)
	if requester_id != lab.controlled_person_id() or not SiteVehicleTransport.is_ship(vehicle) or person.is_empty(): return Runtime.fail("NO_AUTHORITY")
	var team: TerrainArmy = null
	for original: TerrainArmy in lab.combat_armies:
		if original.team_id == int(vehicle.team_id): team = original; break
	if team == null or not team.has_army() or int(person.faction) != team.faction_id: return Runtime.fail("NO_AUTHORITY")
	var ship_refused := team.duty_authority("team.ship", requester_id)
	if not ship_refused.is_empty(): return ship_refused
	if not person_actions._ready(person) or _person_has_duty(requester_id) or team.is_sustain_routed() or not _team_stopped(team) or not vehicle.move.is_empty() or not vehicle.command.is_empty() or not vehicles.ship_job(identity).is_empty(): return Runtime.fail("BUSY", "先由原指揮停隊停船，結束船上作業")
	if starting and vehicles.is_embarked(requester_id): return Runtime.fail("BUSY", "原指揮須在原岸上設施安排施工")
	return Runtime.ok("原隊伍修理權限已確認", {"team_id": team.team_id, "faction": team.faction_id, "person": person})

func begin_ship_repair(identity: String, feature_id: String, requester_id: int, preview: bool = false) -> Dictionary:
	var authority: Dictionary = _ship_repair_authority(identity, requester_id, true)
	if not authority.ok: return authority
	var fixed_vehicle: Dictionary = vehicles.records().get(identity, {})
	if fixed_vehicle.get("naval", {}).has("boarding_link"): return Runtime.fail("BUSY", "接舷連結中船隻固定；先解除連結")
	var feature: Dictionary = lab.terrain.site.features.get(feature_id, {})
	var vehicle: Dictionary = vehicles.records().get(identity, {})
	if str(feature.get("kind", "")) not in Runtime.WATERFRONT_KINDS or int(feature.get("owner_faction", -1)) != int(authority.faction): return Runtime.fail("NO_AUTHORITY")
	var candidate: Dictionary = vehicle.duplicate(true)
	var naval: Dictionary = candidate.get("naval", {"version": 1, "hp": vehicles.Ship.hull_hp(str(vehicle.ship_type)), "state": "afloat", "repair": {}})
	candidate["naval"] = naval
	candidate.naval.repair = {"feature_id": feature_id}
	var contact: bool = false
	for station: Dictionary in Runtime.ship_repair_work_slots(lab.terrain, candidate):
		if vehicles.ship_supply_contact(vehicle, lab.terrain.cell_from_index(int(station.cell))): contact = true; break
	if not contact: return Runtime.fail("UNREACHABLE", "本船須與這座原碼頭或船塢合法接觸")
	return Runtime.request_ship_repair(lab.terrain, identity, feature_id, int(authority.team_id), preview, _ship_repair_q_query)

func cancel_ship_repair(identity: String, requester_id: int, preview: bool = false) -> Dictionary:
	var authority: Dictionary = _ship_repair_authority(identity, requester_id, false)
	if not authority.ok: return authority
	return Runtime.cancel_ship_repair(lab.terrain, identity, int(authority.team_id), preview)

func _build_ship_repair_controls(parent: Node, form: Dictionary) -> void:
	parent.add_child(HSeparator.new())
	_label(parent, "碼頭／船塢修理", 18)
	_label(parent, "備料會放入本船船艙，由本隊工人到岸上施工。取消時仍會結算已用材料；餘料留在船艙，靠岸後可卸下。修理期間不能航行，沉船不能修復。", 15)
	form["repair_facility"] = _options(parent, ["尚無水岸設施"], "ShipRepairFacility")
	_button(parent, "檢查修理條件與材料", "ShipRepairPreview", func() -> void: _ship_repair_ui(form, true, false))
	_button(parent, "投入原料，開始修理", "ShipRepairStart", func() -> void: _ship_repair_ui(form, false, false))
	_button(parent, "派遣本隊工人…", "ShipRepairWorkers", func() -> void: _open_roster())
	_button(parent, "檢查取消修理", "ShipRepairCancelPreview", func() -> void: _ship_repair_ui(form, true, true))
	_button(parent, "取消修理，未用原料留船艙", "ShipRepairCancel", func() -> void: _ship_repair_ui(form, false, true))
	_refresh_ship_repair_facilities(form)

func _refresh_ship_repair_facilities(form: Dictionary) -> void:
	if not form.has("repair_facility"): return
	var previous: String = str(form.repair_facility.get_item_metadata(form.repair_facility.selected)) if form.repair_facility.selected >= 0 else ""
	form.repair_facility.clear()
	if lab == null or lab.terrain == null or lab.terrain.site.is_empty():
		form.repair_facility.add_item("尚無已完成碼頭／船塢")
		form.repair_facility.set_item_metadata(0, "")
		return
	var keys: Array = lab.terrain.site.features.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var feature: Dictionary = lab.terrain.site.features[key]
		if str(feature.kind) not in Runtime.WATERFRONT_KINDS or str(feature.stage) != "complete": continue
		form.repair_facility.add_item("%s #%s · 管理方 %d" % [str(Runtime.FEATURES[str(feature.kind)].name), key, int(feature.owner_faction)])
		form.repair_facility.set_item_metadata(form.repair_facility.item_count - 1, key)
		if key == previous: form.repair_facility.select(form.repair_facility.item_count - 1)
	if form.repair_facility.item_count == 0:
		form.repair_facility.add_item("尚無已完成碼頭／船塢")
		form.repair_facility.set_item_metadata(0, "")

func _ship_repair_ui(form: Dictionary, preview: bool, cancelling: bool) -> void:
	if bool(form.trial): show_result(Runtime.fail("NO_AUTHORITY")); return
	var vehicle: Dictionary = _selected_vehicle(form)
	if not SiteVehicleTransport.is_ship(vehicle): show_result(Runtime.fail("NO_TARGET")); return
	if cancelling:
		show_result(cancel_ship_repair(str(vehicle.id), lab.controlled_person_id(), preview))
	else:
		var feature_id: String = str(form.repair_facility.get_item_metadata(form.repair_facility.selected)) if form.repair_facility.selected >= 0 else ""
		show_result(begin_ship_repair(str(vehicle.id), feature_id, lab.controlled_person_id(), preview))
	_refresh_vehicle_details(form)

# Hook only in formal _build_ship_controls after deck controls:
# if not bool(form.trial): _build_ship_repair_controls(parent, form)
# Refresh facilities from _refresh_vehicle_details alongside deck targets.
# Append status naval.repair progress/total, paidcost and reserved resources.
# Existing clear-team + roster-member move guards add ship_repair_uses_team.
# Original wire_combat_team membership_change_hook points to
# _ship_membership_change; player_supply_change delegates to the same wrapper.

func _build_shipyard_controls(parent: Node, form: Dictionary) -> void:
	parent.add_child(HSeparator.new())
	_label(parent, "原船塢正式造船", 20)
	_label(parent, "先在「建設與製作」建好岸上船塢。可用水道須已有來源許可；不會由造船開放水域。原工人施工，下水堵泊時保留已付材料與進度。", 15)
	form["shipyard"] = _options(parent, ["尚無船塢"], "ShipyardFeature")
	form.shipyard.item_selected.connect(func(_index: int) -> void: _refresh_shipyard_status(form))
	form["build_ship_type"] = _options(parent, ["渡船", "河船", "沿海貨船", "運兵船", "巡邏船", "樓船"], "BuildShipType")
	form.build_ship_type.item_selected.connect(func(_index: int) -> void: _refresh_shipyard_status(form))
	form["shipyard_status"] = _label(parent, "請選擇已完成船塢", 15)
	form.shipyard_status.name = "ShipyardStatus"
	_button(parent, "查看船塢位置", "FocusShipyard", func() -> void:
		var key: String = _selected_shipyard(form)
		var feature: Dictionary = lab.terrain.site.features.get(key, {})
		if feature.is_empty(): return
		feature_key = key
		selected = lab.terrain.cell_from_index(int(feature.entrance))
		lab.camera.position = (Vector2(selected) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		lab.camera.force_update_scroll()
		view.selection = Runtime._cell_bounds(lab.terrain, feature.cells)
		view.refresh()
		update_ui())
	_button(parent, "預驗造船原料／泊位", "ShipBuildPreview", func() -> void: _ship_build_ui(form, true))
	_button(parent, "投入原料，開始造船", "ShipBuildStart", func() -> void: _ship_build_ui(form, false))
	_button(parent, "派遣原隊員工作…", "ShipBuildWorkers", func() -> void: _open_roster())
	_button(parent, "預驗取消退款", "ShipBuildCancelPreview", func() -> void:
		show_result(cancel_ship_build(_selected_shipyard(form), lab.controlled_person_id(), true)))
	_button(parent, "取消造船，退回未用原料", "ShipBuildCancel", func() -> void:
		show_result(cancel_ship_build(_selected_shipyard(form), lab.controlled_person_id()))
		_refresh_shipyards(form))
	_refresh_shipyards(form)

func _selected_shipyard(form: Dictionary) -> String:
	if not form.has("shipyard") or form.shipyard.selected < 0: return ""
	var value: Variant = form.shipyard.get_item_metadata(form.shipyard.selected)
	return str(value) if value != null else ""

func _refresh_shipyards(form: Dictionary) -> void:
	if not form.has("shipyard") or lab.terrain == null: return
	var previous: String = _selected_shipyard(form)
	form.shipyard.clear()
	var keys: Array = lab.terrain.site.features.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var feature: Dictionary = lab.terrain.site.features[key]
		if str(feature.kind) != "shipyard": continue
		form.shipyard.add_item("船塢 #%s · %s · 管理方 %d" % [key, "已完成" if str(feature.stage) == "complete" else "施工中", int(feature.owner_faction)])
		form.shipyard.set_item_metadata(form.shipyard.item_count - 1, key)
		if key == previous or previous.is_empty() and key == feature_key: form.shipyard.select(form.shipyard.item_count - 1)
	if form.shipyard.item_count == 0:
		form.shipyard.add_item("尚無船塢；先於建設視窗安排岸上施工")
		form.shipyard.set_item_metadata(0, "")
	_refresh_shipyard_status(form)

func _refresh_shipyard_status(form: Dictionary) -> void:
	if not form.has("shipyard_status"): return
	var feature: Dictionary = lab.terrain.site.features.get(_selected_shipyard(form), {})
	var kind: String = vehicles.Ship.KINDS[maxi(0, int(form.build_ship_type.selected))]
	var cost: Dictionary = vehicles.Ship.build_cost(kind)
	var job: Dictionary = feature.get("ship_build", {})
	form.shipyard_status.text = "%s：%s · %.1f 人工遊戲分鐘\n工具1件须保留；由目前受控原指揮下令，造船結果保留原隊伍。" % [_ship_type_name(kind), Runtime.items_text(cost), vehicles.Ship.build_work_seconds(kind) / 60.0]
	if feature.is_empty(): return
	form.shipyard_status.text += "\n岸上入口 %s／船尾泊位 %s\n%s" % [lab.terrain.cell_from_index(int(feature.entrance)), lab.terrain.cell_from_index(int(feature.launch_cell)), str(feature.status)]
	if not job.is_empty():
		form.shipyard_status.text += "\n%s · 原隊伍 #%d · %.1f／%.1f 有效分鐘\n已付 %s；取消按未使用比例向下取整退款。" % [_ship_type_name(str(job.ship_type)), int(job.team_id), float(feature.production), float(job.total_work) / 60.0, Runtime.items_text(job.paid_cost)]

func _ship_build_ui(form: Dictionary, preview: bool) -> void:
	var team: TerrainArmy = lab.player_army()
	if team == null: show_result(Runtime.fail("NO_AUTHORITY", "目前受控原人物須有本隊指揮權")); return
	var kind: String = vehicles.Ship.KINDS[maxi(0, int(form.build_ship_type.selected))]
	show_result(begin_ship_build(_selected_shipyard(form), kind, team.team_id, lab.controlled_person_id(), preview))
	_refresh_shipyards(form)

func _open_selected_shipyard() -> void:
	var form: Dictionary = _vehicle_forms.get("formal", {})
	if form.is_empty() or not form.has("shipyard"): return
	_refresh_shipyards(form)
	for index: int in form.shipyard.item_count:
		if str(form.shipyard.get_item_metadata(index)) == feature_key: form.shipyard.select(index); break
	_refresh_shipyard_status(form)
	open_window("transport")

func _waterfront_launch_cell(bounds: Rect2i, quarter: int) -> int:
	var cell: Vector2i
	match quarter:
		1: cell = Vector2i(bounds.end.x, bounds.position.y)
		2: cell = Vector2i(bounds.end.x - 1, bounds.end.y)
		3: cell = Vector2i(bounds.position.x - 1, bounds.end.y - 1)
		_: cell = bounds.position + Vector2i.UP
	return lab.terrain.index(cell) if lab.terrain.contains(cell) else -1

func _build_ship_deck_controls(parent: Node, form: Dictionary) -> void:
	parent.add_child(HSeparator.new())
	_label(parent, "原人物甲板作業／近接船體", 18)
	_label(parent, "只由目前受控原人物執行。船须停穩；行走與跨船仍沿原作業、通路與席位預約，不會切換人物或瞬移。", 15)
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	form["deck_x"] = _number_input(row, "ShipDeckAcross", 0, 5.25, 0.5)
	form.deck_x.prefix = "甲板橫向 "
	form.deck_x.step = 0.25
	form["deck_y"] = _number_input(row, "ShipDeckForward", 0, 15.25, 1.0)
	form.deck_y.prefix = "往船首 "
	form.deck_y.step = 0.25
	_button(parent, "走到指定甲板位置", "ShipDeckWalk", func() -> void: _ship_deck_ui(form, "walk"))
	form["deck_target_ship"] = _options(parent, ["尚無目的船"], "ShipDeckTarget")
	_button(parent, "跨上目的船（使用船席選擇）", "ShipCross", func() -> void: _ship_deck_ui(form, "cross"))
	_button(parent, "近接攻擊所選敵船體", "ShipAttackHull", func() -> void: _ship_deck_ui(form, "attack"))
	_refresh_ship_deck_targets(form)

func _refresh_ship_deck_targets(form: Dictionary) -> void:
	if not form.has("deck_target_ship"): return
	var previous: String = str(form.deck_target_ship.get_item_metadata(form.deck_target_ship.selected)) if form.deck_target_ship.selected >= 0 and form.deck_target_ship.get_item_metadata(form.deck_target_ship.selected) != null else ""
	var source: Dictionary = _selected_vehicle(form)
	form.deck_target_ship.clear()
	for identity: String in vehicles.records():
		var boat: Dictionary = vehicles.records()[identity]
		if not SiteVehicleTransport.is_ship(boat) or str(source.get("id", "")) == identity: continue
		form.deck_target_ship.add_item("#%s %s · 原隊伍 #%d" % [identity, _ship_type_name(str(boat.ship_type)), int(boat.team_id)])
		form.deck_target_ship.set_item_metadata(form.deck_target_ship.item_count - 1, identity)
		if identity == previous: form.deck_target_ship.select(form.deck_target_ship.item_count - 1)
	if form.deck_target_ship.item_count == 0:
		form.deck_target_ship.add_item("尚無其他目的船")
		form.deck_target_ship.set_item_metadata(0, "")
	if SiteVehicleTransport.is_ship(source):
		var spec: Dictionary = vehicles.Ship.definition(str(source.ship_type))
		form.deck_x.max_value = float(spec.width) - 0.75
		form.deck_y.max_value = float(spec.length) - 0.75

func _ship_deck_ui(form: Dictionary, operation: String) -> void:
	var identity: int = lab.controlled_person_id()
	if bool(form.trial): show_result(Runtime.fail("NO_AUTHORITY", "此處只使用正式受控原人物")); return
	var source: Dictionary = _selected_vehicle(form)
	if not SiteVehicleTransport.is_ship(source): show_result(Runtime.fail("NO_TARGET", "先選擇原人物目前所在船")); return
	var result: Dictionary
	if operation == "attack":
		result = person_actions.begin_vehicle_attack(identity, str(source.id))
	else:
		var own_ship: Dictionary = vehicles.ship_for_person(identity)
		if own_ship.is_empty() or str(own_ship.id) != str(source.id): show_result(Runtime.fail("NO_AUTHORITY", "操作來源須是目前受控原人物所在的這艘船")); return
		if operation == "walk":
			result = person_actions.begin_ship_walk(identity, Vector2(float(form.deck_x.value), float(form.deck_y.value)), identity)
		else:
			var target_id: String = str(form.deck_target_ship.get_item_metadata(form.deck_target_ship.selected)) if form.deck_target_ship.selected >= 0 else ""
			if not SiteVehicleTransport.is_ship(vehicles.records().get(target_id, {})): show_result(Runtime.fail("NO_TARGET")); return
			result = person_actions.begin_ship_cross(identity, target_id, identity, int(form.ship_berth.value))
	show_result(result)
	_refresh_vehicle_details(form)

func _ship_ui_person(form: Dictionary) -> int:
	if not bool(form.trial): return lab.controlled_person_id()
	if form.operator.selected < 0 or form.operator.get_item_metadata(form.operator.selected) == null: return 0
	return int(form.operator.get_item_metadata(form.operator.selected))

func _ship_person_ui(form: Dictionary, action: String) -> void:
	var vehicle := _selected_vehicle(form)
	if not SiteVehicleTransport.is_ship(vehicle): show_result(Runtime.fail("NO_TARGET", "請選擇船艦")); return
	var person_id := _ship_ui_person(form)
	var requester := _vehicle_requester(vehicle, false, form)
	var result: Dictionary
	if action == "board":
		result = person_actions.begin_ship_board(person_id, str(vehicle.id), requester, int(form.ship_berth.value), bool(form.trial))
	elif action == "helm":
		var original := vehicles.ship_person(person_id)
		result = person_actions.begin_ship_helm(person_id, str(vehicle.id), requester, bool(form.trial), not original.is_empty() and original.owner.is_sustain_routed())
	else:
		var original := vehicles.ship_person(person_id)
		result = person_actions.begin_ship_disembark(person_id, str(vehicle.id), requester, selected, bool(form.trial), not original.is_empty() and original.owner.is_sustain_routed())
	show_result(result)
	_refresh_vehicle_details(form)

func _ship_order_ui(form: Dictionary, action: String, retreat: bool = false) -> void:
	var vehicle := _selected_vehicle(form)
	if not SiteVehicleTransport.is_ship(vehicle): show_result(Runtime.fail("NO_TARGET", "請選擇船艦")); return
	show_result(vehicles.ship_order(str(vehicle.id), action, selected, _vehicle_requester(vehicle, false, form), bool(form.trial), retreat))
	_refresh_vehicle_details(form)

func _ship_cargo_ui(form: Dictionary, loading: bool) -> void:
	var vehicle := _selected_vehicle(form)
	if not SiteVehicleTransport.is_ship(vehicle): show_result(Runtime.fail("NO_TARGET", "請選擇船艦")); return
	var person_id := _ship_ui_person(form)
	var person_key := "person:%d" % person_id
	var source_key_value := person_key if loading else str(vehicle.id)
	var target_key := str(vehicle.id) if loading else person_key
	var source: Dictionary = vehicles._ship_stock(source_key_value)
	var destination: Dictionary = vehicles._ship_stock(target_key)
	if source.is_empty() or destination.is_empty(): show_result(Runtime.fail("NO_TARGET")); return
	var resources := {str(form.resource.get_item_metadata(form.resource.selected)): int(form.quantity.value)}
	show_result(vehicles.transfer(source_key_value, target_key, resources, [], int(source.holder.version), int(destination.holder.version), _vehicle_requester(vehicle, true, form), bool(form.trial)))
	_refresh_vehicle_details(form)

func _ship_supply_ui(form: Dictionary, loading: bool) -> void:
	var vehicle := _selected_vehicle(form)
	if not SiteVehicleTransport.is_ship(vehicle): show_result(Runtime.fail("NO_TARGET", "請選擇船艦")); return
	var team: TerrainArmy = vehicles._siege_team(vehicle)
	if team == null or not lab.terrain.contains(selected): show_result(Runtime.fail("NO_TARGET")); return
	var resources := {str(form.resource.get_item_metadata(form.resource.selected)): int(form.quantity.value)}
	var shore_key := "shore:%d" % lab.terrain.index(selected)
	var boat_key := "vehicle:%s" % str(vehicle.id)
	show_result(transfer_ship_supply(team, shore_key if loading else boat_key, boat_key if loading else shore_key, resources, 0.0, _vehicle_requester(vehicle, false, form), bool(form.trial)))
	_refresh_vehicle_details(form)

func _ship_permit_water_ui() -> void:
	if ship_journey_active():
		show_result(Runtime.fail("BUSY", "原旅程期間來源水域通行資料凍結"))
		return
	if lab.terrain == null or not lab.terrain.contains(selected): return
	var cell_index: int = lab.terrain.index(selected)
	if lab.terrain.surface_types[cell_index] != TerrainData.Surface.WATER or lab.terrain.water_body.size() != lab.terrain.size.x * lab.terrain.size.y or lab.terrain.water_body[cell_index] < 0:
		show_result(Runtime.fail("INVALID", "僅能明示已有識別的水體，未知水域不開啟")); return
	var permitted: Array = lab.terrain.parameters.get("navigable_water_bodies", []).duplicate()
	if not permitted.has(int(lab.terrain.water_body[cell_index])): permitted.append(int(lab.terrain.water_body[cell_index]))
	lab.terrain.parameters.navigable_water_version = 1
	lab.terrain.parameters.navigable_water_bodies = permitted
	show_result(Runtime.ok("已開啟此既有水體的測試通行；整船仍逐步檢查地形與占位"))

func _ship_deploy_ui(form: Dictionary) -> void:
	if _crowd_active(): show_result(Runtime.fail("BUSY", "先切回原一般人物模式")); return
	var team: TerrainArmy = null
	if form.has("siege_team") and form.siege_team.selected >= 0:
		var team_id := int(form.siege_team.get_item_metadata(form.siege_team.selected))
		for original: TerrainArmy in lab.combat_armies:
			if original.team_id == team_id: team = original; break
	if team == null: show_result(Runtime.fail("NO_TARGET", "請在原隊伍選单選擇此船所屬隊伍")); return
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	show_result(vehicles.deploy_ship(team, vehicles.Ship.KINDS[int(form.ship_type.selected)], selected, directions[int(form.ship_facing.selected)], true))
	_refresh_vehicle_controls(form)

# Append to the existing SiteController; add Housing preload alongside Runtime.
func _open_housing(host: Window = null) -> void:
	var house_id := feature_key
	var requester_id := int(lab.controlled_person_id())
	var terrain_owner: TerrainData = lab.terrain
	var site_owner: Dictionary = lab.terrain.site
	if _existing_dialog("housing", house_id, host): return
	var layout: Dictionary = Runtime.house_layout(lab.terrain, house_id)
	if not layout.ok: show_result(layout); return
	var requester := person_actions._person(requester_id, false)
	if requester.is_empty(): show_result(Runtime.fail("NO_AUTHORITY")); return
	var dialog := Window.new()
	dialog.title = "住宅 #%s · 原人物入住／返家" % house_id
	dialog.size = Vector2i(560, 430)
	dialog.min_size = Vector2i(440, 360)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var summary := _label(column, "", 16)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var choice := _options(column, [], "HousingPerson")
	var candidates: Array[int] = []
	var known := {}
	if _crowd_active():
		for owner_ref: RefCounted in lab.crowd_site.person_owners():
			for unit: int in owner_ref.combat_units: known[owner_ref.combat_identity(unit)] = true
	else:
		for actor: TerrainTestCharacter in lab.combat_actors:
			if is_instance_valid(actor): known[int(actor.person_id)] = true
		for team: TerrainArmy in lab.combat_armies:
			for unit in range(team.combat_units.size()): known[team.combat_identity(unit)] = true
	var identities: Array = known.keys()
	identities.sort()
	for identity: int in identities:
		var person := person_actions._person(identity, false)
		if person.is_empty() or not Housing._same_team_authority(lab, requester, person): continue
		var home: Dictionary = Housing.relation(lab, identity)
		if not home.is_empty() and str(home.house_id) != house_id: continue
		var selected_index := choice.item_count
		choice.add_item("原人物 #%d%s" % [identity, " · 目前受控" if identity == requester_id else ""])
		choice.set_item_metadata(selected_index, identity)
		candidates.append(identity)
		if identity == requester_id: choice.select(selected_index)
	if candidates.is_empty(): choice.add_item("沒有可指派的原人物"); choice.disabled = true
	var listing := ItemList.new()
	listing.custom_minimum_size.y = 160
	listing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(listing)
	var status := _label(column, "", 15)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var update := func() -> void:
		var report: Dictionary = Housing.query(lab, house_id)
		listing.clear()
		if not report.ok: summary.text = str(report.message); return
		summary.text = "門前休息格 %d · 已登記 %d · 在家 %d · 被俘 %d\n保留房門通路；實際到家且安全時疲勞恢復提高 25%%。\n供養仍用本人／原隊伍的食物；不恢復生命或昏迷。" % [int(report.capacity), int(report.registered), int(report.at_home), int(report.captive)]
		for resident: Dictionary in report.occupants:
			listing.add_item("原人物 #%d · %s · 休息格 %s" % [int(resident.person_id), str(resident.status), lab.terrain.cell_from_index(int(resident.cell))])
	var invoke := func(action: String) -> void:
		if candidates.is_empty() or not is_instance_valid(choice): return
		if not is_same(terrain_owner, lab.terrain) or not is_same(site_owner, lab.terrain.site) or requester_id != int(lab.controlled_person_id()):
			show_result(Runtime.fail("STALE_SITE", "原住宅表單來源已變更"))
			return
		var identity := int(choice.get_item_metadata(choice.selected))
		var home: Dictionary = Housing.relation(lab, identity)
		if not home.is_empty() and str(home.house_id) != house_id:
			show_result(Runtime.fail("STALE_SOURCE", "原人物已改住其他住宅"))
			return
		var result: Dictionary
		match action:
			"assign": result = Housing.assign(lab, identity, house_id, requester_id)
			"return": result = person_actions.begin_housing_return(identity, requester_id)
			"leave": result = Housing.leave(lab, identity, requester_id)
			_: result = person_actions.cancel(identity)
		status.text = str(result.message)
		show_result(result)
		update.call()
	var row := HBoxContainer.new()
	column.add_child(row)
	_button(row, "分配住宅", "AssignHousing", func() -> void: invoke.call("assign"))
	_button(row, "逐格返家", "ReturnHousing", func() -> void: invoke.call("return"))
	_button(row, "離住", "LeaveHousing", func() -> void: invoke.call("leave"))
	_button(column, "取消返家（收束原步進）", "CancelHousingReturn", func() -> void: invoke.call("cancel"))
	dialog.close_requested.connect(dialog.queue_free)
	update.call()
	_show_dialog(dialog, "housing", house_id, host)

# Settlement center P0 (SETTLEMENT_CENTER_LEVELS_PLAN). SiteSettlement owns the
# record; this controller only adds the build entry, page and clock hook.
func settlement_grade_cap(feature: Dictionary) -> int:
	return Settlement.grade_cap(lab, feature)

var _settlement_capture_sample: Dictionary = {}

func prepare_settlement_interval() -> void:
	_settlement_capture_sample = Settlement.capture_sample(lab)

func settle_settlement_endpoint() -> Dictionary:
	var fallen := Settlement.settle_capture(lab)
	if not fallen.is_empty():
		if not bool(fallen.get("ok", false)): return fallen
		view.refresh()
		show_result(fallen)
	return Runtime.ok()

func _advance_settlement(real_seconds: float, game_seconds: float) -> void:
	if Settlement.record(lab.terrain).is_empty(): return
	var sample := _settlement_capture_sample
	if sample.is_empty(): sample = Settlement.capture_sample(lab)
	var advanced := Settlement.advance_capture_sample(lab.terrain, sample, game_seconds)
	_settlement_capture_sample = {}
	if not advanced.ok: latch_original_step_fault(advanced); return
	# The existing quarter-second cadence serves offices/UI only. Capture
	# progress has already consumed this exact interval and is never buffered.
	_settlement_elapsed += real_seconds
	_settlement_game_seconds = 0.0
	if _settlement_elapsed < 0.25: return
	_settlement_elapsed = fmod(_settlement_elapsed, 0.25)
	Settlement.settle_offices(lab)

func found_settlement_selected() -> void:
	var probe := {"kind": "settlement_center", "layout_version": 1, "quarter": building_direction.selected}
	if not view.building_art_available(probe):
		show_result(Runtime.fail("MISSING_ART", "聚落中心缺正式美術資產 %s；不以占位圖替代" % view.building_art_key(probe)))
		return
	var result := Settlement.found(lab, int(lab.controlled_person_id()), build_cells, _building_options(), reserves_cell)
	if result.ok:
		enable_worker()
		feature_key = str(result.feature)
		_cancel_building_draft()
		view.refresh()
	show_result(result)

func _settlement_page_text() -> String:
	var state := Settlement.status(lab)
	if not bool(state.founded): return "此 Site 尚未建制聚落：所有建造、升級與生產維持原規則。\n在建設窗選「聚落中心」選址，首長本人須在中心周圍 %d 格內。" % Settlement.radius(1)
	var lines: PackedStringArray = []
	var level := int(state.level)
	lines.append("%s · %s" % [str(state.name), ("%d 級%s" % [level, str(Runtime.SETTLEMENT_LEVEL_NAMES[level])]) if level > 0 else "中心施工中"])
	lines.append("陣營 %d · 管轄半徑 %d 格 · %s：%s" % [int(state.owner_faction), int(state.radius), str(state.head_title), ("原人物 #%d" % int(state.head)) if int(state.head) > 0 else "空缺"])
	lines.append("登記居民 %d 人（管轄內、同陣營、存活、已登記住宅）" % int(state.get("population", 0)))
	lines.append("狀態：生效" if bool(state.effective) else "狀態：停效（%s）" % "、".join(state.reasons))
	lines.append("普通建物新升級上限：%d 級" % (clampi(level, 1, Runtime.CIVIL_MAX_GRADE) if bool(state.effective) else 1))
	var next := Settlement.next_level(lab)
	if int(next.target) >= 2 and int(next.target) <= Runtime.SETTLEMENT_MAX_LEVEL:
		lines.append("升 %d 級：%s · 工時 %.0f 分" % [int(next.target), "條件已齊" if bool(next.ok) else "尚缺 " + "、".join(next.missing), float(next.get("work", 0.0))])
	elif level > 0:
		lines.append("已達 P0 最高等級")
	var fall: Dictionary = Settlement.record(lab.terrain).fall_record
	if int(fall.contest_faction) >= 0: lines.append("攻陷計時：陣營 %d · %.0f／%.0f 遊戲秒" % [int(fall.contest_faction), float(fall.contest_seconds), Settlement.CAPTURE_SECONDS])
	if _crowd_active(): lines.append("群眾戰鬥中：聚落頁唯讀，不接受命令。")
	return "\n".join(lines)

func _open_settlement(host: Window = null) -> void:
	if _existing_dialog("settlement", "site", host): return
	var terrain_owner: TerrainData = lab.terrain
	var dialog := Window.new()
	dialog.title = "聚落頁"
	dialog.size = Vector2i(560, 400)
	dialog.min_size = Vector2i(440, 320)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var summary := _label(column, "", 16)
	summary.name = "SettlementSummary"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	column.add_child(row)
	var buttons: Array[Button] = []
	var update := func() -> void:
		summary.text = _settlement_page_text()
		for button: Button in buttons: button.disabled = _crowd_active() or Settlement.record(lab.terrain).is_empty()
	var invoke := func(action: String) -> void:
		if not is_same(terrain_owner, lab.terrain):
			show_result(Runtime.fail("STALE_SITE", "原聚落頁來源已變更"))
			return
		var result: Dictionary = Settlement.claim_head(lab, int(lab.controlled_person_id())) if action == "claim" \
			else Settlement.request_upgrade(lab, int(lab.controlled_person_id()), reserves_cell)
		if result.ok and action == "upgrade":
			enable_worker()
			view.refresh()
		show_result(result)
		update.call()
	buttons.append(_button(row, "升級聚落（原地施工）", "SettlementUpgrade", func() -> void: invoke.call("upgrade")))
	buttons.append(_button(row, "就任空缺首長", "SettlementClaimHead", func() -> void: invoke.call("claim")))
	dialog.close_requested.connect(dialog.queue_free)
	update.call()
	_show_dialog(dialog, "settlement", "site", host)

## Position page (OFFICE_POSITIONS_AND_DUTIES_PLAN 8). Every org the controlled
## v2 plan 3.4 募兵 sources with a real transfer path: this team's retired rows
## and free same-faction original Actors (join_player). Others are not offered.
func _recruit_candidates(team: TerrainArmy) -> Array[int]:
	if not is_instance_valid(team): return [] as Array[int]
	var result := team.recruit_candidates()
	for other: TerrainArmy in lab.combat_armies:
		if is_instance_valid(other) and other != team and other.combat_enabled and RegionFactionQuery.same_side(other.faction_id, team.faction_id):
			if other.garrison_feature_id.is_empty(): result.append_array(other.recruit_candidates())
			else: # Garrisoned soldiers (fourth source; SiteGarrison.recruit checks the barracks authority).
				for index: int in other.combat_units.size():
					if other.is_member(index) and other.combat_can_act(index) and other.combat_identity(index) != lab.controlled_person_id():
						result.append(other.combat_identity(index))
	if not is_instance_valid(team.player_member):
		for actor: TerrainTestCharacter in lab.combat_actors:
			if is_instance_valid(actor) and actor in [team.player, team.npc] and RegionFactionQuery.same_side(actor.faction_id, team.faction_id) and actor.person_id != lab.controlled_person_id() 				and actor.can_act() and not lab.combat_armies.any(func(other: TerrainArmy) -> bool: return is_instance_valid(other) and other.player_member == actor):
				result.append(actor.person_id)
	return result

## R2 §8.4: members whose grievance shows (不滿／可能離開／已提出離開意向), plus
## the controlled person's own line. Game-visible state only; nothing acts on it in R2.
func _social_summary(team: TerrainArmy) -> String:
	if not is_instance_valid(team) or lab.terrain == null: return ""
	var ref := SiteSocial.team_ref(str(lab.terrain.site.get("id", "")), team.team_id)
	var lines: Array[String] = []
	for index: int in team.combat_units.size():
		if not team.is_member(index) or team.member_gone(index): continue
		var status := SiteSocial.status(team.combat_units[index], ref)
		var own: bool = team.combat_identity(index) == lab.controlled_person_id()
		if status.is_empty() or str(status.label).is_empty() and not own: continue
		var remaining := "（尚餘觀察 %d 日）" % int(status.days_left) if int(status.days_left) >= 0 else ""
		lines.append("#%d 不滿 %d／門檻 %d · 忠誠 %.1f%s%s" % [team.combat_identity(index), int(status.G), int(status.threshold), float(status.L) / 100.0,
			" · " + str(status.label) if not str(status.label).is_empty() else "", remaining])
	return "" if lines.is_empty() else "社會狀態（每日結算）：
" + "
".join(lines)

func _recruit(team: TerrainArmy, person_id: int) -> Dictionary:
	if not is_instance_valid(team): return Runtime.fail("NO_TARGET", "無合格原人物")
	for actor: TerrainTestCharacter in lab.combat_actors:
		if is_instance_valid(actor) and actor.person_id == person_id: return team.recruit_actor(lab.controlled_person_id(), actor)
	for other: TerrainArmy in lab.combat_armies:
		if is_instance_valid(other) and other != team and other.index_for_identity(person_id) >= 0:
			if not other.garrison_feature_id.is_empty(): return Garrison.recruit(lab, other.garrison_feature_id, [person_id], team.team_id)
			return team.recruit_from_team(other, lab.controlled_person_id(), person_id)
	return team.recruit_row(lab.controlled_person_id(), person_id)

## person belongs to can be viewed; only its present head may edit, and edits
## build one pending plan that the original owner validates and commits whole.
func _office_orgs() -> Array[Dictionary]:
	var orgs: Array[Dictionary] = []
	var controlled: int = lab.controlled_person_id()
	var team: TerrainArmy = lab.player_army()
	if team != null and team.combat_enabled:
		team.settle_combat_command()
		var team_id := team.team_id
		# Officers first (武官 posts need rank), then every other member (文官 posts, R1a).
		var candidates: Array[int] = []
		var others: Array[int] = []
		for index: int in team.combat_units.size():
			if index == team.formal_commander or not team.is_member(index) or team.member_gone(index): continue
			if team.military_role(index) == "officer": candidates.append(team.combat_identity(index))
			else: others.append(team.combat_identity(index))
		candidates.append_array(others)
		orgs.append({"kind": "team", "id": str(team_id), "label": "本隊 #%d" % team_id, "candidates": candidates,
			"pending": func() -> Array[int]: return team.pending_cadre() if is_instance_valid(team) else [] as Array[int],
			# v2 §3.3: offered only while the captaincy is permanently vacant.
			"claim_label": "以所選軍官就任空缺隊長",
			"claim_visible": func() -> bool: return is_instance_valid(team) and team.formal_commander < 0,
			"claim": func(person_id: int) -> Dictionary: return team.claim_vacant_captaincy(lab.controlled_person_id(), person_id),
			# v2 plan 3.4 募兵 (first source: this team's own retired rows).
			"recruit_candidates": func() -> Array[int]: return _recruit_candidates(team),
			"social": func() -> String: return _social_summary(team), # R2 §8.4 visible state
			"recruit_ok": func() -> bool: return is_instance_valid(team) and team.duty_decider("team.recruit") == lab.controlled_person_id(),
			"recruit": func(person_id: int) -> Dictionary: return _recruit(team, person_id),
			"release": func(person_id: int) -> Dictionary: return team.record_officer_service([team.index_for_identity(person_id)], false),
			"offices": func() -> Dictionary: return team.team_offices() if is_instance_valid(team) and team == lab.player_army() else {},
			"head": func() -> int: return team.combat_identity(team.formal_commander) if team.formal_commander >= 0 else -1,
			"resolve": func(duty_id: String) -> Dictionary: return team.duty_resolve(duty_id),
			"apply": func(revision: int, ops: Array) -> Dictionary: return team.apply_office_plan(controlled, revision, ops),
			"ai": func(enabled: bool) -> Dictionary: return team.set_duty_ai_enabled(controlled, enabled),
			"note": "武官職位與負責訓練的職位須由具軍官資格者擔任；其他文官職位任何隊員皆可。擔任任一職位（文官或武官）且具軍官資格者都能帶兵：隊長昏迷或陣亡時可代理、接任，並計入指揮能力。隊長由原接任規則產生，此處只能改「隊長」名稱。需停止、脫戰。"})
	var nations: Dictionary = lab.terrain.site.get("equipment_nations", {})
	var keys := nations.keys()
	keys.sort()
	for nation_id: String in keys:
		var nation: Dictionary = nations[nation_id]
		if not EquipmentOrders._member(nation, controlled): continue
		var members: Array[int] = []
		for member: Variant in nation.members: members.append(int(member))
		var versioned := nation.has("offices")
		orgs.append({"kind": "nation", "id": nation_id, "label": "國家 %s%s" % [nation_id, "" if versioned else "（未建制）"], "candidates": members,
			"offices": func() -> Dictionary: return EquipmentOrders.nation_offices(nations.get(nation_id, {})) if nations.has(nation_id) else {},
			"head": func() -> int: return int(SiteOffices.head_position(EquipmentOrders.nation_offices(nations.get(nation_id, {}))).get("holder", -1)),
			"resolve": func(duty_id: String) -> Dictionary: return equipment_orders.nation_duty_resolve(nations.get(nation_id, {}), duty_id),
			"apply": func(revision: int, ops: Array) -> Dictionary: return equipment_orders.apply_nation_office_plan(controlled, nation_id, revision, ops),
			"ai": func(enabled: bool) -> Dictionary: return equipment_orders.set_nation_duty_ai(controlled, nation_id, enabled),
			"note": "任職者須為本國國民。" if versioned else "舊國別紀錄：原軍事首長同時負責三項配裝職責，元首空缺；須由正式情境設定元首後才可調整。"})
	var family: Variant = lab.terrain.site.get("family", {})
	if family is Dictionary and FamilyContinuity.member_ids(family, str(lab.terrain.site.id)).has(controlled):
		var established: bool = family.get("offices") is Dictionary
		orgs.append({"kind": "family", "id": "family", "label": "家族" + ("" if established else "（未建制）"),
			"candidates": FamilyContinuity.member_ids(family, str(lab.terrain.site.id)),
			"offices": func() -> Dictionary: return FamilyContinuity.family_offices(lab.terrain.site.get("family", {})),
			"head": func() -> int: return int(SiteOffices.head_position(FamilyContinuity.family_offices(lab.terrain.site.get("family", {}))).get("holder", -1)),
			"resolve": func(duty_id: String) -> Dictionary: return family_continuity.duty_resolve(duty_id),
			"apply": func(revision: int, ops: Array) -> Dictionary: return family_continuity.apply_office_plan(controlled, revision, ops),
			"ai": func(enabled: bool) -> Dictionary: return family_continuity.set_duty_ai_enabled(controlled, enabled),
			"claim": func(person_id: int) -> Dictionary: return family_continuity.appoint_head(controlled, person_id),
			"note": "任職者須為登錄族人。「家族名冊」只由玩家操作，AI 不執行。家主空缺或失格時，受控族人可指定家主。" if established \
				else "家族尚未建制：維持原登錄方式。由受控族人指定家主後，才開始以職位管理。"})
	var settlement: Dictionary = Settlement.record(lab.terrain)
	if not settlement.is_empty() and settlement.get("offices") is Dictionary:
		var faction := int(settlement.owner_faction)
		var townsfolk: Array[int] = []
		for faction_team: TerrainArmy in lab.combat_armies:
			if not is_instance_valid(faction_team) or not faction_team.combat_enabled or faction_team.faction_id != faction: continue
			for index: int in faction_team.combat_units.size():
				if faction_team.is_member(index) and float(faction_team.combat_hot_get(index, &"hp")) > 0.0: townsfolk.append(faction_team.combat_identity(index))
		for faction_actor: TerrainTestCharacter in lab.combat_actors:
			if is_instance_valid(faction_actor) and faction_actor.faction_id == faction and faction_actor.hp > 0.0 and not townsfolk.has(faction_actor.person_id): townsfolk.append(faction_actor.person_id)
		townsfolk.sort()
		orgs.append({"kind": "settlement", "id": "settlement", "label": "聚落", "candidates": townsfolk,
			"offices": func() -> Dictionary: return Settlement.offices(lab),
			"head": func() -> int: return int(SiteOffices.head_position(Settlement.offices(lab)).get("holder", -1)),
			"resolve": func(duty_id: String) -> Dictionary: return Settlement.duty_resolve(lab, duty_id),
			"apply": func(revision: int, ops: Array) -> Dictionary: return Settlement.apply_office_plan(lab, controlled, revision, ops),
			"ai": func(enabled: bool) -> Dictionary: return Settlement.set_duty_ai_enabled(lab, controlled, enabled),
			"note": "首長由聚落頁就任與交接；其他職位由首長在此任免。「俘虜看管」（典獄）決定本聚落管轄內戰俘營的押送入監與釋放；空缺時由首長代行。任職者須為同陣營原人物。"})
	return orgs

func _office_seat_text(offices: Dictionary, seat: Dictionary) -> String:
	var duties := SiteOffices.duties_of_position(offices, str(seat.id))
	var holder := "#%d" % int(seat.holder) if int(seat.holder) > 0 else "空缺"
	return "%s%s · %s · %s · %d 項職責" % [str(seat.name), " ★" if bool(seat.head) else "", SiteOffices.class_label(str(seat.get("office_class", "military"))), holder, duties.size()]

func _office_plan_text(offices: Dictionary, ops: Array) -> String:
	var lines: Array[String] = []
	for op: Dictionary in ops:
		var seat := SiteOffices.position(offices, str(op.get("position_id", "")))
		var seat_name := str(seat.get("name", op.get("position_id", "")))
		match str(op.op):
			"rename": lines.append("改名「%s」→「%s」" % [seat_name, str(op.name)])
			"add": lines.append("新增%s職位「%s」" % [SiteOffices.class_label(str(op.get("office_class", "civil"))), str(op.name)])
			"classify": lines.append("「%s」改為%s" % [seat_name, SiteOffices.class_label(str(op.office_class))])
			"abolish": lines.append("裁撤「%s」" % seat_name)
			"appoint": lines.append("任命 #%d 為「%s」" % [int(op.person_id), seat_name])
			"dismiss": lines.append("免除「%s」任職者" % seat_name)
			"assign": lines.append("「%s」改由「%s」負責" % [SiteOffices.duty_label(str(op.duty_id)), seat_name])
	return "待套用方案：無" if lines.is_empty() else "待套用方案：\n" + "\n".join(lines)

func _open_offices(host: Window = null) -> void:
	var ui_context := str(lab.controlled_person_id())
	if _existing_dialog("offices", ui_context, host): return
	var terrain_owner: TerrainData = lab.terrain
	var original_control: int = lab.controlled_person_id()
	var orgs := _office_orgs()
	if orgs.is_empty():
		show_result(Runtime.fail("NO_TARGET", "目前受控人物不屬於任何隊伍、國家或聚落"))
		return
	var dialog := Window.new()
	dialog.name = "OfficesDialog"
	dialog.title = "職位頁"
	dialog.size = Vector2i(860, 640)
	dialog.min_size = Vector2i(680, 520)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var labels: Array = []
	for org: Dictionary in orgs: labels.append(org.label)
	var org_choice := _options(column, labels, "OfficeOrg")
	_button(column, "國家贖金與國庫", "OfficesNationRansom", func() -> void:
		var picked: Dictionary = orgs[org_choice.selected]
		if str(picked.kind) != "nation":
			show_result(Runtime.fail("NO_TARGET", "請先在上方選擇國家"))
			return
		_open_nation_ransom(str(picked.id), dialog))
	var note := _label(column, "", 15)
	note.name = "OfficeNote"
	note.custom_minimum_size.x = 0
	var lists := HBoxContainer.new()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(lists)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(right)
	_label(left, "職位（名稱 · 任職者 · 職責數）", 16).custom_minimum_size.x = 0
	var seats := ItemList.new()
	seats.name = "OfficePositions"
	seats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	seats.custom_minimum_size = Vector2(320, 220)
	left.add_child(seats)
	var filter := _options(left, ["全部職位", "只看有任職者", "只看空缺"], "OfficeFilter")
	_label(right, "職責（負責職位 · 實際執行）", 16).custom_minimum_size.x = 0
	var duties := ItemList.new()
	duties.name = "OfficeDuties"
	duties.size_flags_vertical = Control.SIZE_EXPAND_FILL
	duties.custom_minimum_size = Vector2(320, 220)
	right.add_child(duties)
	var edit := HBoxContainer.new()
	column.add_child(edit)
	var name_input := LineEdit.new()
	name_input.name = "OfficeName"
	name_input.placeholder_text = "職位名稱（1–%d 字）" % SiteOffices.NAME_MAX
	name_input.max_length = SiteOffices.NAME_MAX
	name_input.custom_minimum_size.x = 200
	edit.add_child(name_input)
	var people := _options(edit, ["選擇任職人選"], "OfficeCandidate")
	var plan_row := HBoxContainer.new()
	column.add_child(plan_row)
	var duty_row := HBoxContainer.new()
	column.add_child(duty_row)
	var plan_label := _label(column, "", 15)
	plan_label.name = "OfficePlan"
	plan_label.custom_minimum_size.x = 0
	var check_label := _label(column, "", 15)
	check_label.name = "OfficeCheck"
	check_label.custom_minimum_size.x = 0
	var apply_row := HBoxContainer.new()
	column.add_child(apply_row)
	var claim_button := Button.new()
	claim_button.name = "OfficeClaimHead"
	claim_button.text = "以所選人選為首長（家主空缺／失格時）"
	claim_button.add_theme_font_size_override("font_size", 17)
	apply_row.add_child(claim_button)
	var release_button := Button.new()
	release_button.name = "OfficeReleasePending"
	release_button.text = "解除待分職幹部"
	release_button.add_theme_font_size_override("font_size", 17)
	release_button.visible = false
	apply_row.add_child(release_button)
	var recruit_row := HBoxContainer.new()
	recruit_row.name = "OfficeRecruitRow"
	recruit_row.visible = false
	column.add_child(recruit_row)
	var recruit_pick := OptionButton.new()
	recruit_pick.name = "OfficeRecruitPick"
	recruit_row.add_child(recruit_pick)
	var recruit_button := Button.new()
	recruit_button.name = "OfficeRecruit"
	recruit_button.text = "募兵：編入所選原人物（退隊者或自由人物）"
	recruit_button.add_theme_font_size_override("font_size", 17)
	recruit_row.add_child(recruit_button)
	var ai_toggle := CheckButton.new()
	ai_toggle.name = "OfficeDutyAI"
	ai_toggle.text = "職責 AI（NPC 任職者自行執行）"
	apply_row.add_child(ai_toggle)
	var state := {"org": orgs[0], "ops": [], "revision": -1, "seat_ids": [], "duty_ids": [], "syncing": false}
	var edit_buttons: Array[Button] = []
	var context_ok := func() -> bool:
		if not is_same(terrain_owner, lab.terrain) or lab.controlled_person_id() != original_control:
			show_result(Runtime.fail("STALE_SITE", "受控人物或 Site 已變更；請重新開啟職位頁"))
			return false
		return true
	var can_edit := func() -> bool:
		var org: Dictionary = state.org
		return org.apply.is_valid() and not _crowd_active() and int(org.head.call()) == original_control
	var selected_seat := func() -> String:
		var picked := seats.get_selected_items()
		return str(state.seat_ids[int(picked[0])]) if not picked.is_empty() else ""
	var refresh := func() -> void:
		var org: Dictionary = state.org
		var current: Dictionary = org.offices.call()
		claim_button.visible = org.has("claim") and (not org.has("claim_visible") or bool(org.claim_visible.call()))
		claim_button.text = str(org.get("claim_label", "以所選人選為首長（家主空缺／失格時）"))
		claim_button.disabled = _crowd_active()
		if current.is_empty():
			seats.clear()
			duties.clear()
			for button: Button in edit_buttons: button.disabled = true
			ai_toggle.disabled = true
			note.text = str(org.note) if org.has("claim") else "此組織已不存在或已非本隊。"
			people.clear()
			people.add_item("選擇任職人選")
			people.set_item_metadata(0, -1)
			for identity: int in org.candidates:
				people.add_item("#%d" % identity)
				people.set_item_metadata(people.item_count - 1, identity)
			return
		if int(state.revision) != int(current.revision):
			if not state.ops.is_empty(): check_label.text = "人事已由他處變更；待套用方案已清除，請重新編排。"
			state.ops.clear()
			state["revision"] = int(current.revision)
		var preview := SiteOffices.preview_plan(current, state.ops)
		var shown: Dictionary = preview.offices
		var keep: String = selected_seat.call()
		seats.clear()
		state.seat_ids.clear()
		for seat: Dictionary in shown.positions:
			if filter.selected == 1 and int(seat.holder) <= 0 and not bool(seat.head): continue
			if filter.selected == 2 and (int(seat.holder) > 0 or bool(seat.head)): continue
			seats.add_item(_office_seat_text(shown, seat))
			state.seat_ids.append(str(seat.id))
			if str(seat.id) == keep: seats.select(seats.item_count - 1)
		duties.clear()
		state.duty_ids.clear()
		for duty_id: String in SiteOffices.duty_ids(str(org.kind)):
			var seat := SiteOffices.position(shown, str(shown.duties.get(duty_id, "")))
			var executor := "套用後重算"
			if state.ops.is_empty() and org.resolve.is_valid():
				var resolved: Dictionary = org.resolve.call(duty_id)
				executor = ("暫停：" + str(resolved.get("message", ""))) if not bool(resolved.ok) else ("代行：#%d" % int(resolved.decider) if bool(resolved.acting) else "#%d" % int(resolved.decider))
			elif not org.resolve.is_valid():
				executor = "#%d" % int(seat.holder) if int(seat.holder) > 0 else "空缺"
			duties.add_item("%s → %s · %s" % [SiteOffices.duty_label(duty_id), str(seat.get("name", "？")), executor])
			state.duty_ids.append(duty_id)
		people.clear()
		people.add_item("選擇任職人選")
		people.set_item_metadata(0, -1)
		for identity: int in org.candidates:
			var seated := SiteOffices.position_of(shown, identity)
			people.add_item("#%d%s" % [identity, "（現任「%s」）" % seated.name if not seated.is_empty() else ""])
			people.set_item_metadata(people.item_count - 1, identity)
		var editable: bool = can_edit.call()
		note.text = str(org.note) + ("" if editable else ("\n群眾戰鬥中：職位頁唯讀。" if _crowd_active() else "\n只有本組織首長可調整；目前僅能查看。"))
		var social_text: String = org.social.call() if org.has("social") else ""
		if not social_text.is_empty(): note.text += "
" + social_text
		var recruitable: Array = org.recruit_candidates.call() if org.has("recruit_candidates") else []
		recruit_row.visible = not recruitable.is_empty()
		recruit_pick.clear()
		for identity: int in recruitable:
			recruit_pick.add_item("#%d" % identity)
			recruit_pick.set_item_metadata(recruit_pick.item_count - 1, identity)
		recruit_button.disabled = _crowd_active() or not (org.has("recruit_ok") and bool(org.recruit_ok.call()))
		var pending: Array = org.pending.call() if org.has("pending") else []
		release_button.visible = not pending.is_empty()
		release_button.disabled = not editable
		if not pending.is_empty():
			var listed: Array[String] = []
			for identity: int in pending: listed.append("#%d" % identity)
			note.text += "\n⚠ 待分職幹部（MIGRATION_REQUIRED，舊存檔遷移）：%s。他們沒有指揮權；請任命到武官職位，或選取後按「解除待分職幹部」。" % "、".join(listed)
		for button: Button in edit_buttons: button.disabled = not editable
		name_input.editable = editable
		state["syncing"] = true
		ai_toggle.button_pressed = bool(current.get("duty_ai", false))
		ai_toggle.disabled = not editable or not org.ai.is_valid()
		state["syncing"] = false
		plan_label.text = _office_plan_text(shown, state.ops)
		if state.ops.is_empty():
			if not check_label.text.begins_with("人事已由他處"): check_label.text = ""
		elif not bool(preview.ok):
			check_label.text = "⚠ " + str(preview.message)
		else:
			var checked := SiteOffices.apply_plan(current, str(org.kind), int(current.revision), state.ops,
				func(_person: int, _office_class: String) -> bool: return true, str(org.kind) != "team")
			check_label.text = "✓ 方案可套用（任職資格於套用時由原 owner 核對）" if bool(checked.ok) else "⚠ " + str(checked.message)
	var queue := func(op: Dictionary) -> void:
		if not context_ok.call() or not can_edit.call(): return
		state.ops.append(op)
		refresh.call()
	var need_seat := func() -> String:
		var seat: String = selected_seat.call()
		if seat.is_empty(): check_label.text = "⚠ 請先在左側選取職位"
		return seat
	edit_buttons.append(_button(plan_row, "改名", "OfficeRename", func() -> void:
		var seat: String = need_seat.call()
		if not seat.is_empty(): queue.call({"op": "rename", "position_id": seat, "name": name_input.text.strip_edges()})))
	edit_buttons.append(_button(plan_row, "新增文官", "OfficeAdd", func() -> void:
		queue.call({"op": "add", "name": name_input.text.strip_edges(), "ref": "new_%d" % state.ops.size(), "office_class": "civil"})))
	edit_buttons.append(_button(plan_row, "新增武官", "OfficeAddMilitary", func() -> void:
		queue.call({"op": "add", "name": name_input.text.strip_edges(), "ref": "new_%d" % state.ops.size(), "office_class": "military"})))
	edit_buttons.append(_button(plan_row, "切換文官／武官", "OfficeClassify", func() -> void:
		var seat_id: String = need_seat.call()
		if seat_id.is_empty(): return
		var current_seat := SiteOffices.position(SiteOffices.preview_plan(state.org.offices.call(), state.ops).offices, seat_id)
		queue.call({"op": "classify", "position_id": seat_id, "office_class": "civil" if str(current_seat.get("office_class", "military")) == "military" else "military"})))
	edit_buttons.append(_button(plan_row, "裁撤", "OfficeAbolish", func() -> void:
		var seat: String = need_seat.call()
		if not seat.is_empty(): queue.call({"op": "abolish", "position_id": seat})))
	edit_buttons.append(_button(plan_row, "任命", "OfficeAppoint", func() -> void:
		var seat: String = need_seat.call()
		var person := int(people.get_item_metadata(people.selected)) if people.selected >= 0 else -1
		if person <= 0: check_label.text = "⚠ 請先選擇任職人選"
		elif not seat.is_empty(): queue.call({"op": "appoint", "position_id": seat, "person_id": person})))
	edit_buttons.append(_button(plan_row, "免職", "OfficeDismiss", func() -> void:
		var seat: String = need_seat.call()
		if not seat.is_empty(): queue.call({"op": "dismiss", "position_id": seat})))
	edit_buttons.append(_button(duty_row, "所選職責改由所選職位負責", "OfficeAssignDuty", func() -> void:
		var seat: String = need_seat.call()
		var picked := duties.get_selected_items()
		if picked.is_empty(): check_label.text = "⚠ 請先在右側選取職責"
		elif not seat.is_empty(): queue.call({"op": "assign", "duty_id": str(state.duty_ids[int(picked[0])]), "position_id": seat})))
	edit_buttons.append(_button(duty_row, "撤回上一步", "OfficeUndo", func() -> void:
		if not state.ops.is_empty(): state.ops.pop_back()
		refresh.call()))
	edit_buttons.append(_button(apply_row, "套用方案", "OfficeApply", func() -> void:
		if not context_ok.call(): return
		var org: Dictionary = state.org
		var result: Dictionary = org.apply.call(int(state.revision), state.ops)
		show_result(result)
		check_label.text = ("✓ " if bool(result.ok) else "⚠ ") + str(result.get("message", ""))
		if bool(result.ok):
			state.ops.clear()
			state["revision"] = -1
		refresh.call()))
	edit_buttons.append(_button(apply_row, "清除方案", "OfficeClear", func() -> void:
		state.ops.clear()
		check_label.text = ""
		refresh.call()))
	recruit_button.pressed.connect(func() -> void:
		if not context_ok.call(): return
		var org: Dictionary = state.org
		if not org.has("recruit") or recruit_pick.selected < 0: return
		var result: Dictionary = org.recruit.call(int(recruit_pick.get_item_metadata(recruit_pick.selected)))
		show_result(result)
		check_label.text = ("✓ " if bool(result.ok) else "⚠ ") + str(result.get("message", ""))
		state["revision"] = -1
		refresh.call())
	release_button.pressed.connect(func() -> void:
		if not context_ok.call(): return
		var org: Dictionary = state.org
		var person := int(people.get_item_metadata(people.selected)) if people.selected >= 0 else -1
		if person <= 0 or not org.has("release") or not org.pending.call().has(person):
			check_label.text = "⚠ 請先在人選中選取一名待分職幹部"
			return
		var result: Dictionary = org.release.call(person)
		show_result(result)
		check_label.text = ("✓ " if bool(result.ok) else "⚠ ") + str(result.get("message", ""))
		state["revision"] = -1
		refresh.call())
	claim_button.pressed.connect(func() -> void:
		if not context_ok.call(): return
		var org: Dictionary = state.org
		var person := int(people.get_item_metadata(people.selected)) if people.selected >= 0 else -1
		if person <= 0:
			check_label.text = "⚠ 請先選擇首長人選"
			return
		var result: Dictionary = org.claim.call(person)
		show_result(result)
		check_label.text = ("✓ " if bool(result.ok) else "⚠ ") + str(result.get("message", ""))
		state.ops.clear()
		state["revision"] = -1
		refresh.call())
	ai_toggle.toggled.connect(func(enabled: bool) -> void:
		if bool(state.syncing) or not context_ok.call(): return
		var org: Dictionary = state.org
		show_result(org.ai.call(enabled))
		refresh.call())
	org_choice.item_selected.connect(func(index: int) -> void:
		state["org"] = orgs[index]
		state.ops.clear()
		state["revision"] = -1
		check_label.text = ""
		refresh.call())
	filter.item_selected.connect(func(_index: int) -> void: refresh.call())
	seats.item_selected.connect(func(index: int) -> void:
		var seat := SiteOffices.position(SiteOffices.preview_plan(state.org.offices.call(), state.ops).offices, str(state.seat_ids[index]))
		if not seat.is_empty(): name_input.text = str(seat.name))
	dialog.close_requested.connect(dialog.queue_free)
	refresh.call()
	_show_dialog(dialog, "offices", ui_context, host)


# Transient caller state only. Original Actor, PersonActions, RegionSaveSlot,
# SiteStore and the original shared-step remain their existing owners.
var _ground_crossing: Dictionary = {}
var _original_step_fault: Dictionary = {}

func latch_original_step_fault(result: Dictionary) -> Dictionary:
	if _original_step_fault.is_empty():
		_original_step_fault = result.duplicate(true)
		_auto_save_blocked = true
	return _original_step_fault.duplicate(true)

func original_step_fault_guard() -> Dictionary:
	if _original_step_fault.is_empty(): return Runtime.ok()
	return Runtime.fail("STEP_FAULT", "原共同步進已部分執行或未完成時鐘記錄；停止新步進與保存，請重新載入場景")

func ground_crossing_blocks_clock() -> bool:
	return not _original_step_fault.is_empty() or str(_ground_crossing.get("stage", "")) in ["queued", "prepare", "commit"]

func ground_crossing_blocks_input() -> bool:
	return not _original_step_fault.is_empty() or not _ground_crossing.is_empty() or _region_player_input_blocks()

func _region_player_input_blocks() -> bool:
	return region_slot != null and not region_slot.region_player_barrier().is_empty()

func begin_ground_crossing(identity: int, direction: Vector2i) -> Dictionary:
	var fault: Dictionary = original_step_fault_guard()
	if not fault.ok: return fault
	if region_operation_pending() or ship_journey_active(): return Runtime.fail("BUSY", "原船隊旅程或目的地補算尚未結束")
	if ground_crossing_blocks_input(): return Runtime.fail("BUSY", "原跨界步進或補算尚未結束")
	if is_instance_valid(lab._cold_replay_lab): return Runtime.fail("BUSY", "另一原冷地點候選尚未結束")
	if lab.restore_only or region_slot == null: return Runtime.fail("NO_REGION_SLOT", "此原場景尚未接入固定地圖存檔槽")
	if get_tree().paused or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("PAUSED", "暫停時不開始跨界")
	var person: Dictionary = lab.controlled_target()
	if person.is_empty() or int(person.unit) >= 0 or identity != lab.controlled_person_id():
		return Runtime.fail("NO_AUTHORITY", "只限原受控 GD 獨立人物跨界")
	var guard: Dictionary = supply_save_guard()
	if not guard.ok: return guard
	if not region_slot.cold_site_advance.is_valid(): region_slot.cold_site_advance = lab.advance_cold_site
	_ground_crossing = {"stage": "queued", "source": lab.terrain, "slot": region_slot,
		"identity": identity, "direction": direction, "target": -1.0,
		"request": {}, "pending_sha256": "", "source_captured": false, "completed_action_seconds": 0.0}
	lab._clear_movement_input()
	# Held input reaches here AFTER Site.tick and BEFORE its whole-step clock
	# publication. No preparation/capture/cold work may observe that half-step.
	return Runtime.ok("原跨界輸入已排入；等待本共同步進完成")


func _ground_crossing_context() -> Dictionary:
	if _ground_crossing.is_empty(): return Runtime.fail("NO_TARGET", "沒有原跨界候選")
	if lab.terrain != _ground_crossing.source or region_slot != _ground_crossing.slot \
			or lab.controlled_person_id() != int(_ground_crossing.identity):
		return Runtime.fail("STALE", "原跨界人物、Site 或存檔槽已更換")
	if str(_ground_crossing.stage) in ["prepare", "commit"] and float(_ground_crossing.target) >= 0.0 \
			and float(region_slot.control.logical_game_seconds) != float(_ground_crossing.target):
		return Runtime.fail("TIME_MISMATCH", "等待中的原跨界固定遊戲時鐘已變")
	return Runtime.ok()

func _retain_ground_pending(result: Dictionary) -> Dictionary:
	var signature: String = str(result.get("source_sha256", ""))
	var retained: String = str(_ground_crossing.pending_sha256)
	if signature.is_empty() or not retained.is_empty() and signature != retained \
			or float(result.get("target", _ground_crossing.target)) != float(_ground_crossing.target):
		return _abort_ground_crossing(Runtime.fail("STALE_SOURCE", "原補算來源或固定目標不一致"))
	_ground_crossing.pending_sha256 = signature
	lab._reset_action_elapsed_input()
	return result

func _prepare_ground_crossing() -> Dictionary:
	var context: Dictionary = _ground_crossing_context()
	if not context.ok: return _abort_ground_crossing(context)
	if get_tree().paused or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("PAUSED", "暫停時保留原跨界候選")
	var preview: Dictionary = _ground_presenter_preflight()
	if not preview.ok: return _abort_ground_crossing(preview)
	var prepared: Dictionary = region_slot.prepare_ground_crossing(lab.terrain, int(_ground_crossing.identity), Vector2i(_ground_crossing.direction))
	if not prepared.ok:
		if str(prepared.get("code", "")) == "PENDING": return _retain_ground_pending(prepared)
		return _abort_ground_crossing(prepared)
	var begun: Dictionary = person_actions.begin_ground_boundary(int(_ground_crossing.identity), prepared)
	if not begun.ok: return _abort_ground_crossing(begun)
	_ground_crossing.request = prepared.request.duplicate(true)
	_ground_crossing.stage = "action"
	_ground_crossing.pending_sha256 = ""
	lab._reset_action_elapsed_input()
	return begun

func _ground_presenter_preflight() -> Dictionary:
	# Read the actual saved neighbour BEFORE its cold replay can run. Reject a
	# missing presenter while all original source/destination ownership is intact.
	var person: Dictionary = lab.controlled_target()
	if person.is_empty(): return Runtime.fail("NO_TARGET", "原跨界人物已不在場")
	var preview: Dictionary = region_slot.query_boundary_crossing(lab.terrain, Vector2i(person.cell), Vector2i(_ground_crossing.direction))
	if not preview.ok: return preview
	var destination: TerrainData = preview.destination_data
	if not is_instance_valid(lab.npc) and (destination.site.get("actors", {}).has("npc") \
			or Runtime.inventory_size(destination.site.get("worker", {}).get("cargo", {})) != 0):
		return Runtime.fail("BIND_GUARD", "目的地已有真實 NPC，原場景缺少該呈現者；原人與檔案保留")
	var source_identity: Dictionary = lab.cold_source_identity(destination, float(_ground_crossing.target))
	if not source_identity.ok: return source_identity
	_ground_crossing.expected_cold_source_sha256 = str(source_identity.source_sha256)
	_ground_crossing.expected_cold_site_id = str(source_identity.site_id)
	return Runtime.ok()

func collect_ground_boundary_result(result: Dictionary) -> void:
	if not bool(result.get("ground_boundary_ready", false)) or _ground_crossing.is_empty(): return
	var request: Dictionary = result.get("request", {})
	if str(_ground_crossing.stage) != "action" or str(request.get("token", "")) != str(_ground_crossing.request.get("token", "")):
		show_result(_abort_ground_crossing(Runtime.fail("STALE", "原 ACTION 完成結果不是此跨界候選")))
		return
	# Collect after contacts. Commit runs in finish_tick, after the original
	# whole shared step has recorded its own game time exactly once.
	_ground_crossing.stage = "commit"
	_ground_crossing.completed_action_seconds = float(result.completed_action_seconds)
	_ground_crossing.target = -1.0 # Set only after record_completed_region_step.
	_ground_crossing.source_captured = false
	lab._clear_movement_input()
	lab._reset_action_elapsed_input()

func _ground_destination_bind_guard(destination: TerrainData) -> Dictionary:
	# Pure preflight: no archive, Actor retirement, capture, initialization or bind.
	if destination == null or destination.site.has("crowd") or lab.restore_only:
		return Runtime.fail("BIND_GUARD", "原 GD 場景不能綁定此目的容器")
	if not is_instance_valid(lab.npc) and (destination.site.get("actors", {}).has("npc") \
			or Runtime.inventory_size(destination.site.get("worker", {}).get("cargo", {})) != 0):
		return Runtime.fail("BIND_GUARD", "目的地已有真實 NPC，原場景缺少該呈現者；原人與檔案保留")
	if not is_instance_valid(lab.character) or not is_instance_valid(lab.renderer):
		return Runtime.fail("BIND_GUARD", "原人物或地形呈現者不可用")
	var compatible: Dictionary = lab.exchange_snapshot_guard(destination)
	if not compatible.ok: return compatible
	return supply_save_guard(true)

func finish_ground_crossing() -> bool:
	if not _original_step_fault.is_empty(): return true
	if _ground_crossing.is_empty(): return false
	var live_context: Dictionary = _ground_crossing_context()
	if not live_context.ok:
		show_result(_abort_ground_crossing(live_context))
		return true
	if str(_ground_crossing.stage) == "action":
		if not person_actions.is_busy(int(_ground_crossing.identity)):
			show_result(_abort_ground_crossing(Runtime.fail("CANCELLED", "原跨界動作已取消或受擊中止")))
		return false
	if get_tree().paused or bool(lab.terrain.site.get("paused", false)): return true
	if str(_ground_crossing.stage) == "queued":
		var queued_guard: Dictionary = supply_save_guard(true)
		if not queued_guard.ok:
			show_result(_abort_ground_crossing(queued_guard))
			return true
		var captured: Dictionary = _capture_for_save()
		if not captured.ok:
			show_result(_abort_ground_crossing(captured))
			return true
		_ground_crossing.target = float(region_slot.control.logical_game_seconds)
		_ground_crossing.stage = "prepare"
	if str(_ground_crossing.stage) == "prepare":
		var prepared: Dictionary = _prepare_ground_crossing()
		if str(prepared.get("code", "")) != "PENDING": show_result(prepared)
		return true
	# The first finish_tick follows the complete original shared-step publisher.
	if not bool(_ground_crossing.source_captured):
		_ground_crossing.target = float(region_slot.control.logical_game_seconds)
		var captured: Dictionary = _capture_for_save()
		if not captured.ok:
			show_result(_abort_ground_crossing(captured))
			return true
		_ground_crossing.source_captured = true
	var context: Dictionary = _ground_crossing_context()
	if not context.ok:
		show_result(_abort_ground_crossing(context))
		return true
	var preview: Dictionary = _ground_presenter_preflight()
	if not preview.ok:
		show_result(_abort_ground_crossing(preview))
		return true
	var committed: Dictionary = region_slot.commit_ground_crossing(_ground_crossing.request, lab.terrain,
		float(_ground_crossing.completed_action_seconds), _ground_destination_bind_guard)
	if not committed.ok:
		if str(committed.get("code", "")) == "PENDING":
			var retained: Dictionary = _retain_ground_pending(committed)
			if str(retained.get("code", "")) != "PENDING": show_result(retained)
		else: show_result(_abort_ground_crossing(committed))
		return true
	# One marker already owns BOTH snapshots. Bind its exact returned candidate;
	# ordinary load/archive_before_replace would save the departing actor twice.
	var destination: TerrainData = committed.destination_data
	var retained_action_seconds: float = lab._action_time_remainder
	lab.bind_terrain(destination, {"ok": true, "crowd_site": null})
	if lab.terrain != destination:
		show_result(latch_original_step_fault(Runtime.fail("BIND_FAILED_AFTER_COMMIT", "原跨界已提交，但原場景未接受目的快照；停止步進")))
		return true
	# These seconds were already earned BEFORE PENDING. Waiting adds none.
	lab._action_time_remainder = retained_action_seconds
	save_path = region_slot.site_path(committed.active_site)
	_ground_crossing.clear()
	lab._reset_action_elapsed_input()
	show_result(Runtime.ok("原人物已跨入相鄰地點", {"generation": committed.generation}))
	return true

func _abort_ground_crossing(result: Dictionary) -> Dictionary:
	if _ground_crossing.is_empty(): return result
	var signature: String = str(_ground_crossing.get("pending_sha256", ""))
	# A cold failure may occur before its first PENDING result. Retire only the
	# candidate whose saved source/target this original caller already proved.
	if signature.is_empty() and is_instance_valid(lab._cold_replay_lab) \
			and lab._cold_replay_signature == str(_ground_crossing.get("expected_cold_source_sha256", "")) \
			and lab._cold_replay_id == str(_ground_crossing.get("expected_cold_site_id", "")) \
			and lab._cold_replay_target == float(_ground_crossing.target):
		signature = lab._cold_replay_signature
	if not signature.is_empty():
		var cancelled: Dictionary = lab.cancel_cold_site_replay(signature)
		if not cancelled.ok:
			_auto_save_blocked = true
			return cancelled # Keep the exact original retained scene identifiable.
	var identity: int = int(_ground_crossing.identity)
	if str(person_actions.job_for(identity).get("kind", "")) == "ground_boundary": person_actions.cancel(identity)
	_ground_crossing.clear()
	lab._clear_movement_input()
	lab._reset_action_elapsed_input()
	return result

func cancel_ground_crossing(identity: int) -> Dictionary:
	if _ground_crossing.is_empty(): return person_actions.cancel(identity)
	if identity != int(_ground_crossing.identity): return Runtime.fail("NO_AUTHORITY", "不是原跨界人物")
	if not _original_step_fault.is_empty(): return original_step_fault_guard()
	return _abort_ground_crossing(Runtime.ok("已取消未提交的原跨界候選"))

func _build_ladder_actions(column: VBoxContainer) -> void:
	_label(column, "攻城梯：兩名同隊原人搬設", 16)
	var choices: Array[OptionButton] = [_options(column, [], "LadderFirstCrew"), _options(column, [], "LadderSecondCrew")]
	var refresh := func() -> void:
		for choice: OptionButton in choices: choice.clear()
		for team: Variant in _siege_ui_teams():
			for index: int in _siege_ui_indices(team):
				var identity: int = team.combat_identity(index)
				var person := person_actions._person(identity)
				if person.is_empty() or not _can_command_siege_person(person): continue
				for choice: OptionButton in choices:
					choice.add_item("原人物 #%d · 原隊 #%d" % [identity, team.team_id])
					choice.set_item_metadata(choice.item_count - 1, identity)
		if choices[1].item_count > 1: choices[1].select(1)
	_button(column, "更新搬梯人選", "RefreshLadderCrew", refresh)
	for action: String in ["deploy", "retract"]:
		_button(column, "架梯（12 秒）" if action == "deploy" else "收梯（8 秒）", "Ladder" + action.capitalize(), func() -> void:
			if choices[0].selected < 0 or choices[1].selected < 0:
				show_result(Runtime.fail("CREW", "先選兩名同隊原隊員")); return
			var identities: Array[int] = [int(choices[0].get_item_metadata(choices[0].selected)), int(choices[1].get_item_metadata(choices[1].selected))]
			show_result(work_team.request_ladder_action(feature_key, identities, lab.controlled_person_id(), action)))
	_button(column, "停止梯具搬設", "StopLadderAction", func() -> void:
		var feature: Dictionary = lab.terrain.site.features.get(feature_key, {})
		var workers: Array = feature.get("ladder", {}).get("workers", [])
		if workers.is_empty(): show_result(Runtime.fail("NO_ACTION", "梯具目前沒有搬設作業")); return
		for identity: int in workers:
			var person := person_actions._person(identity)
			if person.is_empty() or not _can_command_siege_person(person): show_result(Runtime.fail("NO_AUTHORITY")); return
		var check := Runtime.cancel_siege_ladder_action(lab.terrain, feature_key)
		if check.ok: work_team._clear_ladder_tasks(feature_key)
		show_result(check))
	refresh.call()

func _siege_ui_teams() -> Array:
	if _crowd_active():
		var result: Array = []
		for owner_ref: Variant in lab.crowd_site.person_owners():
			if owner_ref.has_army(): result.append(owner_ref)
		return result
	return lab.combat_armies

func _siege_ui_indices(team: Variant) -> Array:
	return team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())

func _siege_ui_cell(team: Variant, index: int) -> Vector2i:
	if team is CrowdPersonOwner: return team.person(index, false).get("cell", TerrainArmy.INVALID_CELL)
	return team.cells[index]

func _siege_ui_role(team: Variant) -> String:
	if team is CrowdPersonOwner: return str(lab.crowd_site.team_record(team.formation_index).get("role", "combat"))
	return str(team.role)

func _can_command_siege_person(person: Dictionary) -> bool:
	if person.is_empty(): return false
	if not person.owner is CrowdPersonOwner: return _can_command_person(person)
	if not person.owner.has_army() or int(person.unit) < 0: return false
	return int(person.person_id) == lab.controlled_person_id() or person.owner.command_eligible(person.owner.current_commander) and person.owner.combat_identity(person.owner.current_commander) == lab.controlled_person_id()

# Append to the original SiteController. This is the original Slot's one job
# projection; Site bodies/items/supply/fatigue stay with their existing owners.
func region_replacement_guard() -> Dictionary:
	var fault: Dictionary = original_step_fault_guard()
	if not fault.ok: return fault
	if not _ground_crossing.is_empty(): return Runtime.fail("BUSY", "先完成或取消原地面跨界候選")
	return Runtime.ok() if not ship_journey_active() else Runtime.fail("BUSY", "船隊旅程或目的地更新尚未完成，暫不能切換或重建地圖。")


func ship_journey_active() -> bool:
	return not _ship_journey.is_empty() or region_operation_pending() or vehicles != null and lab != null and lab.terrain != null and not vehicles._region_original_ship_drive(lab.terrain) and not vehicles._region_ship_frames(lab.terrain).is_empty()

func region_operation_pending() -> bool:
	return not _region_pending.is_empty()

func _remember_region_pending(result: Dictionary, request: Dictionary) -> Dictionary:
	if str(result.get("code", "")) == "PENDING":
		request["source"] = lab.terrain
		request["source_slot"] = region_slot
		request["source_game_seconds"] = float(region_slot.control.logical_game_seconds) if region_slot != null else -1.0
		request["pending"] = result.duplicate(true)
		_region_pending = request
	return result

func resume_region_operation() -> Dictionary:
	if _region_pending.is_empty(): return Runtime.ok()
	var fault: Dictionary = original_step_fault_guard()
	if not fault.ok: return fault
	var request: Dictionary = _region_pending
	if lab.terrain != request.source or region_slot != request.source_slot or region_slot != null and float(region_slot.control.logical_game_seconds) != float(request.source_game_seconds): return Runtime.fail("STALE_SOURCE", "目前場景已變更，無法接續這次出航。")
	_region_pending = {}
	var result: Dictionary
	match str(request.kind):
		"depart": result = begin_ship_journey(request.boat_ids, request.destination, request.anchor, request.facing, int(request.requester_id))
		"world":
			result = open_fixed_world(str(request.manifest), str(request.world_id), str(request.slot_id), request.site, bool(request.create_new), str(request.get("initial_scenario_id", "")))
			_settle_boot_request(result)
		"arrival":
			_finish_ship_journey_tick()
			result = _region_pending.get("pending", Runtime.ok())
		_: result = Runtime.fail("INVALID", "原補算續作類型非法")
	if not result.ok and str(result.get("code", "")) != "PENDING": show_result(result)
	_update_region_travel_status()
	return result


func ship_vehicle_in_journey(identity: String) -> bool:
	return vehicles != null and vehicles.has_region_ship_projection(identity) or not _ship_journey.is_empty() and _ship_journey.get("boat_ids", []).has(identity)

func ship_person_in_journey(identity: int) -> bool:
	# No journey and no Region ship projection to read (including a controller
	# whose lab is not bound yet) means nobody is aboard a travelling ship.
	if _ship_journey.is_empty() and (lab == null or lab.terrain == null or SiteVehicleTransport._region_ship_frames(lab.terrain).is_empty()): return false
	# Crowd passengers keep their embarked row in the CrowdPersonOwner records, not in a grid army.
	var crowd_owner: Variant = vehicles._crowd_owner_of(identity) if vehicles != null else null
	if crowd_owner != null:
		var crowd_record: Dictionary = crowd_owner.records.get(int(crowd_owner.index_for_identity(identity)), {})
		return ship_vehicle_in_journey(str(crowd_record.get("embarked_vehicle_id", "")))
	for original: TerrainArmy in lab.combat_armies:
		var index := original.index_for_identity(identity)
		if index >= 0 and index < original.combat_units.size():
			return ship_vehicle_in_journey(str(original.combat_units[index].get("embarked_vehicle_id", "")))
	return false

func _current_region_site() -> Vector2i:
	var base: Dictionary = lab.terrain.parameters.get("fixed_base", {})
	var cell: Array = base.get("site", [])
	return Vector2i(int(cell[0]), int(cell[1])) if cell.size() == 2 else TerrainArmy.INVALID_CELL

func _restore_ship_journey() -> void:
	_ship_journey.clear()
	if region_slot == null: return
	var status: Dictionary = region_slot.ship_transfer_status()
	if not status.ok:
		_auto_save_blocked = true
		show_result(status)
		return
	var committed_job: Dictionary = region_slot._marker.get("journey", {})
	if status.get("pending", false) and str(committed_job.get("token", "")) == str(status.get("token", "")) and not committed_job.is_empty() and lab.terrain.site.get("id") == region_slot.control.active_site_id:
		_ship_journey = status
	_invalidate_ship_journey_projection()

func _invalidate_ship_journey_projection() -> void:
	for original: TerrainArmy in lab.combat_armies: original._invalidate_ship_projection()
	if is_instance_valid(vehicle_view): vehicle_view.queue_redraw()

func _journey_can_advance() -> bool:
	for identity: String in _ship_journey.get("boat_ids", []):
		var boat: Dictionary = vehicles.records().get(identity, {})
		if not SiteVehicleTransport.ship_afloat(boat) or not vehicles.ship_job(identity).is_empty() or not vehicles.ship_driver_ready(boat) or vehicles.ship_crew_count(boat) < int(Vehicles.Ship.definition(str(boat.ship_type)).min_crew): return false
	return true

func _release_disabled_journey_operators() -> void:
	# Same original idle-driver release as Transport.update_ships. The journey
	# branch skips fine navigation, so it must still release an incapacitated helm.
	for identity: String in _ship_journey.get("boat_ids", []):
		var boat: Dictionary = vehicles.records().get(identity, {})
		if SiteVehicleTransport.is_ship(boat) and boat.move.is_empty() and not vehicles.ship_driver_ready(boat): boat["operator_id"] = 0

func ship_journey_waiting_for_crew(identity: String) -> bool:
	if vehicles.has_region_ship_projection(identity):
		var boat: Dictionary = vehicles.records().get(identity, {})
		var pose: Dictionary = vehicles.region_ship_projection(boat)
		return not bool(pose.moving) or not vehicles.ship_driver_ready(boat) or vehicles.ship_crew_count(boat) < int(Vehicles.Ship.definition(str(boat.ship_type)).min_crew)
	return ship_vehicle_in_journey(identity) and not _journey_can_advance()

func _journey_stranded() -> bool:
	for identity: String in _ship_journey.get("boat_ids", []):
		var boat: Dictionary = vehicles.records().get(identity, {})
		if not SiteVehicleTransport.ship_afloat(boat) or vehicles.ship_people(boat).is_empty(): return true
	return false

func ship_journey_claims(vehicle: Dictionary) -> Dictionary:
	if vehicles.has_region_ship_projection(str(vehicle.get("id", ""))): return vehicles.region_ship_claims(vehicle)
	var claims := {}
	if not ship_vehicle_in_journey(str(vehicle.get("id", ""))): return claims
	var first: Dictionary = vehicles.records().get(str(_ship_journey.boat_ids[0]), {})
	if first.is_empty() or not _ship_journey.get("anchor") is Array or _ship_journey.anchor.size() != 2: return claims
	var original_anchor: Vector2i = lab.terrain.cell_from_index(int(first.cell))
	var current_anchor: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
	var from := Vector2i(int(_ship_journey.from[0]), int(_ship_journey.from[1]))
	var to := Vector2i(int(_ship_journey.to[0]), int(_ship_journey.to[1]))
	var arrival := Vector2i(int(_ship_journey.anchor[0]), int(_ship_journey.anchor[1]))
	var displacement := Vector2((to.x - from.x) * 100 + arrival.x - original_anchor.x, (from.y - to.y) * 100 + arrival.y - original_anchor.y)
	var elapsed := float(_ship_journey.elapsed_action_seconds) - float(_ship_journey.return_elapsed_action_seconds)
	var progress := clampf(elapsed / maxf(0.000001, float(_ship_journey.seconds)), 0.0, 1.0)
	var point := Vector2(current_anchor) + displacement * progress
	var beginning := Vector2i(floori(point.x), floori(point.y))
	var ending := Vector2i(ceili(point.x), ceili(point.y))
	var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	for cell: Vector2i in Vehicles.Ship.swept_footprint(str(vehicle.ship_type), beginning, facing, ending, facing):
		if lab.terrain.contains(cell): claims[cell] = true
	return claims

# Under crowd a journey starts in peace only (NEKKI_DECISION_20261031_crowd_peacetime_systems): combat refuses with CROWD_ACTIVE
# through crowd_peace_guard. Requester and every passenger aboard the boats must not be fighting. The grid keeps its refusal.
func _ship_journey_peace_guard(boat_ids: Array[String], requester_id: int) -> Dictionary:
	if not _crowd_active():
		return Runtime.ok() if float(lab.terrain.site.combat_left) <= 0.0 else Runtime.fail("BUSY", "船隊旅程須在活動、脫戰、一般人物場景開始")
	var identities: Array = [requester_id if requester_id > 0 else lab.controlled_person_id()]
	for identity: String in boat_ids:
		var boat: Dictionary = vehicles.records().get(identity, {})
		if boat.is_empty(): continue
		for passenger: Dictionary in vehicles.ship_people(boat, false): identities.append(int(passenger.id))
	return person_actions.crowd_peace_guard(identities)

func begin_ship_journey(boat_ids: Array[String], destination: Vector2i, anchor: Vector2i, facing: Vector2i, requester_id: int = 0) -> Dictionary:
	for linked_id: String in boat_ids:
		if vehicles.records().get(linked_id, {}).get("naval", {}).has("boarding_link"): return Runtime.fail("BUSY", "接舷連結中船隻固定；先解除連結")
	if ground_crossing_blocks_input(): return Runtime.fail("BUSY", "原地面跨界候選或共同步進故障尚未結束")
	if region_slot == null: return Runtime.fail("NO_TARGET", "先在固定地圖世界開啟原存檔槽")
	if region_operation_pending(): return Runtime.fail("BUSY", "原固定目標補算尚未完成")
	if not _ship_journey.is_empty() or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("BUSY", "船隊旅程須在活動、脫戰、一般人物場景開始")
	var peace := _ship_journey_peace_guard(boat_ids, requester_id)
	if not peace.ok: return peace
	var guard := supply_save_guard()
	if not guard.ok: return guard
	# Source geometry is frozen for the whole original Slot job. This keeps the
	# original strict Store snapshot/claims admissible without saved ghost poses.
	for original: Dictionary in vehicles.records().values():
		if SiteVehicleTransport.is_ship(original) and (not original.move.is_empty() or not original.command.is_empty() or not vehicles.ship_job(str(original.id)).is_empty() or not original.get("naval", {}).get("repair", {}).is_empty()): return Runtime.fail("BUSY", "出航前來源所有船須停穩且無未完成作業；旅程期間來源水域幾何凍結")
	for feature: Dictionary in lab.terrain.site.features.values():
		if str(feature.get("stage", "")) == "complete": continue
		for cell: Variant in feature.get("cells", []):
			if lab.terrain.surface_types[int(cell)] == TerrainData.Surface.WATER: return Runtime.fail("BUSY", "先完成原水域／橋梁整地作業再出航")
	if boat_ids.is_empty(): return Runtime.fail("NO_TARGET")
	if requester_id <= 0: requester_id = lab.controlled_person_id()
	var checked := {}
	for identity: String in boat_ids:
		var boat: Dictionary = vehicles.records().get(identity, {})
		if not SiteVehicleTransport.is_ship(boat) or not SiteVehicleTransport.ship_afloat(boat) or not boat.move.is_empty() or not boat.command.is_empty() or bool(boat.stop_pending) or not boat.get("naval", {}).get("repair", {}).is_empty() or not vehicles.ship_job(identity).is_empty(): return Runtime.fail("BUSY", "原船須停穩、無修理與未來命令")
		if not vehicles.ship_driver_ready(boat) or vehicles.ship_crew_count(boat) < int(Vehicles.Ship.definition(str(boat.ship_type)).min_crew): return Runtime.fail("NO_CREW", "每艘原船須有實際在原舵位的可行動舵手及在原船員位置的最低船員；先完成回席")
		if checked.has(int(boat.team_id)): continue
		# The team that holds the boat's cargo: the crowd owner under crowd, the grid army otherwise.
		var original: Variant = vehicles._team_owner(int(boat.team_id))
		if original == null or not vehicles._authorized(original, requester_id, 0, false): return Runtime.fail("NO_AUTHORITY", "須有選定每一原隊伍的船隊調度權")
		checked[int(boat.team_id)] = true
	var captured := _capture_for_save()
	if not captured.ok: return captured
	_wire_ship_transfer_crowd_adapter()
	var prepared: Dictionary = region_slot.prepare_ship_transfer(lab.terrain, destination, boat_ids, anchor, facing, true)
	if not prepared.ok: return _remember_region_pending(prepared, {"kind": "depart", "boat_ids": boat_ids.duplicate(), "destination": destination, "anchor": anchor, "facing": facing, "requester_id": requester_id})
	var token := str(prepared.token)
	var saved: Dictionary = region_slot.checkpoint_ship_transfer(token, lab.terrain, 0.0)
	if not saved.ok:
		region_slot.cancel_ship_transfer(token) # Only zero-distance prepared cancellation.
		return saved
	_restore_ship_journey()
	return Runtime.ok("船隊已出航；糧食消耗與疲勞持續。", {"token": token, "seconds": float(prepared.seconds)})


func _checkpoint_ship_journey() -> Dictionary:
	if region_slot == null or _ship_journey.is_empty(): return Runtime.fail("NO_TARGET")
	var guard := supply_save_guard()
	if not guard.ok: return guard
	var captured := _capture_for_save()
	if not captured.ok: return captured
	var had_checkpoint_due: bool = _ship_journey.has("checkpoint_due")
	var previous_due: Variant = _ship_journey.get("checkpoint_due")
	_ship_journey.checkpoint_due = 0.0
	var result: Dictionary = region_slot.checkpoint_ship_transfer(str(_ship_journey.token), lab.terrain, float(_ship_journey.elapsed_action_seconds), str(_ship_journey.phase), float(_ship_journey.return_elapsed_action_seconds))
	if not result.ok:
		if had_checkpoint_due: _ship_journey.checkpoint_due = previous_due
		else: _ship_journey.erase("checkpoint_due")
	return result

func cancel_ship_journey() -> Dictionary:
	if region_slot == null or _ship_journey.is_empty(): return Runtime.fail("NO_TARGET")
	if region_operation_pending(): return Runtime.fail("BUSY", "先完成固定目的地補算；原時鐘與來源已凍結")
	var saved := _checkpoint_ship_journey()
	if not saved.ok: return saved
	var result: Dictionary = region_slot.begin_return_ship_transfer(str(_ship_journey.token), lab.terrain)
	if not result.ok: return result
	_ship_journey = result
	_invalidate_ship_journey_projection()
	return Runtime.ok("船隊開始返航；仍須航回已走距離，糧食消耗與疲勞持續。")

func _journey_arrival_preflight(candidate: TerrainData) -> Dictionary:
	if not is_instance_valid(lab.npc) and (candidate.site.get("actors", {}).has("npc") or Runtime.inventory_size(candidate.site.get("worker", {}).get("cargo", {})) != 0):
		return Runtime.fail("BIND_GUARD", "目的地原 NPC 或工人貨物缺少原呈現者；不發布或退休真實人物")
	var guard: Dictionary = lab.exchange_snapshot_guard(candidate)
	if not guard.ok: return guard
	if lab.has_unpersisted_ranged_projectiles(): return Runtime.fail("BUSY")
	return lab.prepare_crowd_load(candidate)


func _return_source_clear() -> bool:
	for identity: String in _ship_journey.boat_ids:
		var boat: Dictionary = vehicles.records().get(identity, {})
		if boat.is_empty(): return false
		var anchor: Vector2i = lab.terrain.cell_from_index(int(boat.cell))
		var facing := Vector2i(int(boat.facing[0]), int(boat.facing[1]))
		if not vehicles._ship_fits(boat, Vehicles.Ship.footprint(str(boat.ship_type), anchor, facing)): return false
	return true

func _finish_ship_journey_tick() -> void:
	if region_slot == null or _ship_journey.is_empty(): return
	if str(_ship_journey.phase) != "return":
		for identity: String in _ship_journey.boat_ids:
			var original: Dictionary = vehicles.records().get(identity, {})
			var supply: Dictionary = lab.terrain.site.team_supply.get(str(original.get("team_id", 0)), {})
			if bool(supply.get("sustain", {}).get("routed", false)):
				var returning_result := cancel_ship_journey()
				if not returning_result.ok: show_result(returning_result)
				return
	var returning := str(_ship_journey.phase) == "return"
	var reached := float(_ship_journey.return_elapsed_action_seconds) + 0.000001 >= float(_ship_journey.return_required_action_seconds) if returning else float(_ship_journey.elapsed_action_seconds) + 0.000001 >= float(_ship_journey.seconds)
	if not reached and float(_ship_journey.get("checkpoint_due", 0.0)) < 5.0: return
	var saved := _checkpoint_ship_journey()
	if not saved.ok:
		if str(saved.get("code", "")) != "BUSY": _auto_save_blocked = true; show_result(saved)
		return
	if not reached: return
	if returning:
		if not _return_source_clear(): return # Completed original return waits for a legal source footprint.
		var cleared: Dictionary = region_slot.cancel_ship_transfer(str(_ship_journey.token))
		if not cleared.ok: show_result(cleared); return
		_ship_journey.clear()
		_invalidate_ship_journey_projection()
		show_result(Runtime.ok("原船隊已完成等距返航；原人貨與來源位置恢復"))
		return
	# SHIPCROWD: a crowd fleet's passengers leave the native crowd now, at arrival (they sail aboard until here). The
	# commit's own checks run first on copies, so a refusal releases nobody.
	var crowd_released := _release_crowd_ship_passengers()
	if not crowd_released.ok:
		if str(crowd_released.get("code", "")) == "PENDING":
			_remember_region_pending(crowd_released, {"kind": "arrival"})
			show_result(crowd_released)
			return
		if str(crowd_released.get("code", "")) != "BUSY": _auto_save_blocked = true
		show_result(crowd_released)
		return
	_wire_ship_transfer_crowd_adapter()
	var committed: Dictionary = region_slot.commit_ship_transfer(str(_ship_journey.token), lab.terrain, _journey_arrival_preflight)
	if not committed.ok:
		if str(committed.get("code", "")) == "PENDING":
			_remember_region_pending(committed, {"kind": "arrival"})
			show_result(committed)
			return
		if str(committed.get("code", "")) != "BUSY": _auto_save_blocked = true; show_result(committed)
		return
	# The marker is now the sole committed destination. Clear the transient query
	# BEFORE original Army.clear()/bind. A failed bind must retry this destination.
	_ship_journey.clear()
	_invalidate_ship_journey_projection()
	_cancel_facing_move()
	_clear_formation_candidate()
	lab.bind_terrain(committed.destination_data, committed.prepared)
	if not lab.region_bind_receipt(committed.destination_data).get("complete", false):
		show_result(latch_original_step_fault(Runtime.fail("BIND_FAILED_AFTER_COMMIT", "原移交已提交目的地但綁定失敗；停止來源步進與保存，須回復活動場景")))
		return
	save_path = region_slot.site_path(_current_region_site())
	show_result(Runtime.ok("船隊與全隊人貨已抵達目的地。"))


# Keep C save_to as the SINGLE wrapper. This body is reproduced for review only.


## SHIPCROWD: the crowd adapter of the Slot's ship transfer is this live Site's owner (Callable() off crowd).
func _wire_ship_transfer_crowd_adapter() -> void:
	if region_slot == null: return
	region_slot.ship_transfer_crowd_adapter = _crowd_ship_transfer_origin if lab != null and lab.get("crowd_site") != null else Callable()

## SHIPCROWD: converts the controlled captain's crowd team aboard the selected ships inside a transfer origin copy, as
## _depart_crowd's sea probe does: the team's army stub is replaced by its complete grid army snapshot (crowd marked, passenger
## rows with embarked_vehicle_id / berth / deck fields from the crowd records). Read-only on the live Site. After the arrival
## release (_release_crowd_ship_passengers) the Site armies already carry that converted team, so nothing is converted again.
## Returns {ok, successor}: the actor body that takes control of the origin Site (RegionTravelSite.split_control_successor).
func _crowd_ship_transfer_origin(origin: Dictionary, boat_ids: Array) -> Dictionary:
	var crowd: Variant = lab.crowd_site
	if crowd == null: return Runtime.fail("UNSUPPORTED", "群眾船隊旅程缺少原群眾 owner")
	var identity: int = lab.controlled_person_id()
	var successor: Dictionary = RegionTravelSite.split_control_successor(lab, identity)
	if not crowd.active or not crowd.contains_person(identity): return Runtime.ok("", {"successor": successor})
	var plan: Dictionary = crowd.departure_plan(identity)
	if not plan.ok: return plan
	for boat_id: Variant in boat_ids:
		if int(vehicles.records().get(str(boat_id), {}).get("team_id", 0)) != int(plan.team_id):
			return Runtime.fail("PARTIAL_FLEET", "群眾船隊旅程只帶受控隊長本隊的船")
	for member: int in plan.people:
		if not vehicles.is_embarked(member): return Runtime.fail("CROWD_SEA_PARTIAL", "群眾隊伍部分隊員未上船；海路須全隊上船")
	var converted: Dictionary = crowd.departure_army_snapshot(plan)
	if not converted.ok: return converted
	var team_id: int = int(plan.team_id)
	origin["armies"] = origin.get("armies", []).filter(func(army: Variant) -> bool: return not (army is Dictionary and int(army.get("team_id", -1)) == team_id))
	var departing: Dictionary = converted.snapshot.duplicate(true)
	departing["crowd"] = true
	origin.armies.append(departing)
	return Runtime.ok("", {"successor": successor})

## SHIPCROWD: at arrival, the crowd fleet's passengers are released from the native crowd with their vessel (the aboard
## release of departure_release), then the Site is captured again with the travelling team as its converted grid army, as
## RegionTravelSite._depart_crowd does before begin_region_travel. A grid fleet, or a team already released, is unchanged.
func _release_crowd_ship_passengers() -> Dictionary:
	if not _crowd_active(): return Runtime.ok()
	var crowd: Variant = lab.crowd_site
	var identity: int = lab.controlled_person_id()
	if not crowd.contains_person(identity): return Runtime.ok()
	var plan: Dictionary = crowd.departure_plan(identity)
	if not plan.ok: return plan
	var boat_ids: Array = _ship_journey.get("boat_ids", [])
	for boat_id: Variant in boat_ids:
		if int(vehicles.records().get(str(boat_id), {}).get("team_id", 0)) != int(plan.team_id):
			return Runtime.fail("PARTIAL_FLEET", "群眾船隊旅程只帶受控隊長本隊的船")
	# The same conversion the transfer reads, checked on a copy before the irreversible release, then the commit's own
	# checks and transfer pair on copies (ship_transfer_commit_preflight): a refusal there releases nobody.
	var probe: Dictionary = _crowd_ship_transfer_origin(lab.terrain.site.duplicate(true), boat_ids)
	if not probe.ok: return probe
	_wire_ship_transfer_crowd_adapter()
	var commit_probe: Dictionary = region_slot.ship_transfer_commit_preflight(str(_ship_journey.token), lab.terrain)
	if not commit_probe.ok: return commit_probe
	var released: Dictionary = crowd.departure_release(plan)
	if not released.ok: return released
	var departing: Dictionary = released.army.duplicate(true)
	departing["crowd"] = true
	var recaptured: Dictionary = crowd.capture_save()
	if not recaptured.ok: return recaptured
	recaptured.rosters.append(departing)
	_apply_region_crowd_capture(recaptured)
	return Runtime.ok()

func ship_journey_status() -> Dictionary:
	if _ship_journey.is_empty(): return Runtime.ok("沒有在途船隊", {"pending": false})
	var status: Dictionary = _ship_journey.duplicate(true)
	status["stranded"] = _journey_stranded() # Derived life/HP status; never persisted as a second ledger.
	return status

func _initialize_ship_destination(data: TerrainData) -> Dictionary:
	if not data.is_walkable(data.spawn_cell):
		var marine: Dictionary = Env.initialize_marine(data, str(data.parameters.fixed_base.site_id))
		if not marine.ok: return marine
	else:
		Env.initialize(data, str(data.parameters.fixed_base.site_id))
		data.site["actor_presence_version"] = 1
		data.site["actors"] = {}
	# Same fresh-Site contract as RegionSaveSlot.open_site: item storage exists
	# before any first save, and the Site carries this slot's world policy pin.
	var storage := Runtime.initialize_item_storage(data.site)
	if not storage.ok: return storage
	if region_slot != null and not region_slot.pin.is_empty() and not data.site.has("world_pin"):
		data.site["world_pin"] = region_slot.pin.duplicate(true)
	return Runtime.ok("", {"data": data})

func open_fixed_world(manifest_path: String, world_id: String, slot_id: String, starting_site: Vector2i, create_new: bool = false, initial_scenario_id: String = "") -> Dictionary:
	# Reject scenario-on-resume and unknown configuration BEFORE any file IO.
	if not create_new and not initial_scenario_id.is_empty(): return Runtime.fail("INVALID_INITIAL_SCENARIO")
	if initial_scenario_id not in ["", InitialArtisans.PRIMARY, InitialArtisans.THREE_FACTIONS]: return Runtime.fail("INVALID_INITIAL_SCENARIO")
	if ground_crossing_blocks_input(): return Runtime.fail("BUSY", "原地面跨界候選或共同步進故障尚未結束")
	if region_operation_pending(): return Runtime.fail("BUSY", "先完成原固定目標補算")
	if not _ship_journey.is_empty():
		if create_new or region_slot == null or world_id != str(region_slot.pin.world_instance_id) or slot_id != str(region_slot.pin.slot_id) or FileAccess.get_file_as_string(manifest_path).sha256_text() != str(region_slot.pin.manifest_sha256): return region_replacement_guard()
		var checkpoint := _checkpoint_ship_journey()
		if not checkpoint.ok: return checkpoint
	var source := RegionData.new()
	var loaded: Dictionary = source.load_manifest(manifest_path)
	if not loaded.ok: return loaded
	var request := _initial_world_request(manifest_path, world_id, slot_id, starting_site, create_new, initial_scenario_id)
	var location := "user://region_lab/worlds/%s/slots/%s" % [world_id, slot_id]
	var candidate: RegionSaveSlot
	if create_new and _initial_world_candidate != null and _initial_world_candidate.folder == location:
		candidate = _initial_world_candidate
	else:
		candidate = RegionSaveSlot.new()
		if create_new:
			_initial_world_candidate = candidate # Retain before the first IO attempt.
			_initial_world_birth_data = null
			_initial_companion_births = {}
			_initial_world_archive = {}
	var context := {"starting_site": [starting_site.x, starting_site.y], "initial_scenario_id": initial_scenario_id} if create_new else {}
	if not source.author_identity().is_empty():
		if not initial_scenario_id.is_empty(): return Runtime.fail("INITIAL_SCENARIO_CONFLICT")
		var authored: Dictionary = source.author_initial_context()
		if create_new and not RegionSaveSlot._initial_site_same([starting_site.x, starting_site.y], authored.starting_site): return Runtime.fail("INITIAL_SCENARIO_CONFLICT")
		if create_new: context = authored
	# P5C-S2B test seam: forwards the default-invalid Callable to the slot before birth.
	if create_new: candidate.initial_write_fault = initial_write_fault
	var opened: Dictionary = candidate.open_map(source, world_id, slot_id, create_new, context)
	if not opened.ok: return _remember_initial_world_pending(opened, request, candidate)
	candidate.ship_site_initialize = _initialize_ship_destination
	if lab.has_method("advance_cold_site"): candidate.cold_site_advance = Callable(lab, "advance_cold_site")
	if create_new:
		if not candidate.initialization_pending(): return Runtime.fail("CONFLICT", "此世界已完成建立")
		var prepared: Dictionary = _prepare_initial_world(candidate, starting_site, initial_scenario_id)
		if not prepared.ok: return _remember_initial_world_pending(prepared, request, candidate)
		# All original born bodies/items/allocator/placement and actual bind guards
		# have passed BEFORE archiving the old graph or publishing the first marker.
		var preflight: Dictionary = _journey_arrival_preflight(prepared.data)
		if not preflight.ok: return preflight
		if _initial_world_archive.is_empty():
			var archived := Runtime.ok() if not _boot_request.is_empty() else _archive_live_site()
			if not archived.ok: return archived
			_initial_world_archive = archived
		var committed: Dictionary = candidate.commit_initial_site()
		if not committed.ok: return _remember_initial_world_pending(committed, request, candidate)
		# The exact checked original first-generation body may have been reloaded.
		# Produce a bind ticket for that exact object; population is already born.
		if committed.data != prepared.data:
			preflight = _journey_arrival_preflight(committed.data)
			if not preflight.ok: return _remember_initial_world_pending(Runtime.fail("COMMITTED_UNBOUND", str(preflight.get("message", "原首代待綁定"))), request, candidate)
		region_slot = candidate
		_ship_journey.clear()
		lab.bind_terrain(committed.data, preflight)
		var bound: Dictionary = lab.region_bind_receipt(committed.data)
		if not bound.get("complete", false): return _remember_initial_world_pending(Runtime.fail("COMMITTED_UNBOUND", "原首代已提交，原人物／物品／租約待同槽綁定"), request, candidate)
		var finished: Dictionary = candidate.finish_initial_birth(bound)
		if not finished.ok: return _remember_initial_world_pending(finished, request, candidate)
		_region_manifest_path = manifest_path
		save_path = candidate.site_path(starting_site)
		_auto_save_blocked = false
		var archive_path := str(_initial_world_archive.get("path", ""))
		_initial_world_birth_data = null
		_initial_companion_births = {}
		_initial_world_archive = {}
		_initial_world_candidate = null
		return Runtime.ok("新世界原開局首代已提交並完整綁定", {"archive": archive_path, "site": [starting_site.x, starting_site.y], "initial_generation": 1})
	# Ordinary existing/visited/world restore retains the original path.
	# A committed pending first marker is restore-only; this branch never births.
	var travel := RegionTravelSite.world_opened(self, candidate, manifest_path, request)
	if not travel.is_empty(): return travel
	var active := str(candidate.control.active_site_id)
	var parts := active.split(":")
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int(): return Runtime.fail("NO_TARGET", "尚無活動地點；明示建立新固定地圖世界")
	var coordinate := Vector2i(int(parts[1]), int(parts[2]))
	var site: Dictionary = candidate.open_site(coordinate)
	if not site.ok: return _remember_initial_world_pending(site, request, candidate)
	if not site.get("interactive", true) or site.data.site.is_empty(): return Runtime.fail("NO_TARGET", "原活動地點沒有合法落腳点")
	var selected_restore: bool = site.data.site.has("region_snapshot")
	var preflight: Dictionary = lab.prepare_selected_region_owner_restore(site.data, candidate) if selected_restore else _journey_arrival_preflight(site.data)
	if not preflight.ok: return preflight
	if selected_restore: site["data"] = preflight.data # Exact selected readback/private nonce pair.
	# Reopening the slot that is already active resumes its last commit (the
	# commit is the truth). Archiving the live Site there would publish a newer
	# generation into the same slot and stale the selected ticket prepared above.
	var same_slot := region_slot != null and region_slot.folder.simplify_path() == candidate.folder.simplify_path()
	var archived := Runtime.ok() if not _boot_request.is_empty() or same_slot else _archive_live_site()
	if not archived.ok: return archived
	if not selected_restore:
		var attached: Dictionary = candidate.attach_active_site(site.data)
		if not attached.ok: return attached
	# Selected hot body already has its published active owner and clock. Keep
	# its registry revision unchanged until the original bind acknowledgement.
	region_slot = candidate
	_ship_journey.clear()
	lab.bind_terrain(site.data, preflight)
	var bound: Dictionary = lab.region_bind_receipt(site.data)
	if not bound.get("complete", false): return _remember_initial_world_pending(Runtime.fail("LOAD_RETRY", "固定地點待原完整綁定；原存檔保留"), request, candidate)
	_region_manifest_path = manifest_path
	if candidate.initialization_pending():
		var finished: Dictionary = candidate.finish_initial_birth(bound)
		if not finished.ok: return _remember_initial_world_pending(finished, request, candidate)
		save_path = candidate.site_path(coordinate)
		_auto_save_blocked = false
		return Runtime.ok("原已提交開局首代已恢復並完整綁定", {"archive": str(archived.get("path", "")), "site": [coordinate.x, coordinate.y], "initial_generation": 1})
	# A selected hot body may still hold its accepted original P0 endpoint. As on
	# the arrival path (RegionTravelSite.world_opened), the bound main lab wires the
	# Slot's endpoint consumers before any dispatch; no new owner is created.
	if selected_restore and not candidate.region_original_party_zero.is_valid():
		var wired: Dictionary = lab._wire_region_gameplay_adapters(candidate)
		if not wired.get("ok", false): return wired
	if not _boot_request.is_empty(): _auto_save_blocked = false
	if site.data.site.has("region_snapshot"):
		return Runtime.ok("原已提交世界已綁定；待原端點處理完成才保存新世代", {"site": [coordinate.x, coordinate.y], "region_recovery": true})
	var saved := save_to(candidate.site_path(coordinate))
	return Runtime.ok("固定地圖世界已開啟；上一場景完整存檔保留", {"archive": str(archived.get("path", "")), "site": [coordinate.x, coordinate.y]}) if saved.ok else saved

func enter_requested_world(request: Dictionary) -> Dictionary:
	_boot_request = request.duplicate(true)
	_auto_save_blocked = true
	var result := open_fixed_world(str(request.manifest), str(request.world_id), str(request.slot_id), Vector2i(request.site), bool(request.create_new), str(request.get("initial_scenario_id", "")))
	_settle_boot_request(result)
	_update_region_travel_status()
	return result

# Finish a menu request once its world opened (possibly after a PENDING retry):
# apply the created character and record the world, or return to the menu.
func _settle_boot_request(result: Dictionary) -> void:
	if _boot_request.is_empty() or str(result.get("code", "")) == "PENDING": return
	var request: Dictionary = _boot_request
	_boot_request = {}
	if result.ok and not request.get("character", {}).is_empty():
		var appearance: Dictionary = _initial_creation_appearance(request.character)
		var applied := apply_created_character(appearance) if bool(request.get("create_new", false)) else Runtime.fail("INVALID_INITIAL_SCENARIO")
		if not applied.ok: result = applied
	if result.ok:
		lab._audio_boot_complete()
		_record_world(str(request.get("world_name", "")))
		show_result(result)
		return
	RegionEntry.menu_message = str(result.get("message", result.get("code", "無法開啟世界")))
	_leave_site.call_deferred(RegionEntry.MAIN_MENU)

## Applies main-menu character creation to the new world's player and saves.
func apply_created_character(data: Dictionary) -> Dictionary:
	var actor: TerrainTestCharacter = lab.character
	if not lab.actor_present(actor): return Runtime.fail("NO_TARGET", "新世界沒有玩家人物")
	var state := actor.capture_state()
	var appearance: Dictionary = state.appearance.duplicate(true)
	appearance["body"] = int(data.get("body", appearance.body))
	appearance.parts.face = str(data.get("face", appearance.parts.face))
	appearance.parts.hair = str(data.get("hair", appearance.parts.hair))
	appearance["hair_dye"] = str(data.get("hair_dye", appearance.hair_dye))
	appearance["hair_dyed"] = bool(data.get("hair_dyed", appearance.hair_dyed))
	state.appearance = appearance
	var person_name := str(data.get("name", "")).strip_edges()
	if person_name.is_empty(): state.erase("name")
	else: state.name = person_name
	state.combat_ability = float(data.get("combat_ability", state.combat_ability))
	if data.get("command_abilities") is Dictionary: state.command_abilities = data.command_abilities.duplicate()
	var personality: Variant = data.get("personality", {})
	if personality is Dictionary and not personality.is_empty():
		if not TerrainTestCharacter.PersonPersonality.valid(personality): return Runtime.fail("INVALID", "人物性格資料不完整")
		var packet := TerrainTestCharacter.PersonPersonality.saved(personality)
		if packet.is_empty(): state.erase("personality")
		else: state.personality = packet
	if not TerrainTestCharacter.valid_state(state, lab.terrain): return Runtime.fail("INVALID", "建立的人物資料不合法")
	actor.restore_state(state)
	# A crowd start Site already admitted this Actor; native owns its abilities and syncs them back each step.
	if lab.crowd_site != null and lab.crowd_site.active and not actor.command_abilities.is_empty():
		var index := int(lab.crowd_site.crowd.soldier_index(actor.person_id))
		var abilities := {"tactics": int(actor.command_abilities.get("tactics", 0)), "leadership": int(actor.command_abilities.get("leadership", 0)), "coach": int(actor.command_abilities.get("coach", 0))}
		if index >= 0 and not lab.crowd_site.set_soldier_fields(index, abilities): return Runtime.fail("INVALID", "建立的人物能力無法寫入群眾模擬")
	return save_to(save_path)

func _record_world(world_name: String = "") -> void:
	if region_slot == null or lab.terrain == null: return
	var day := floori(float(lab.terrain.site.get("minute", 0)) / 1440) + 1
	RegionEntry.record_world(str(region_slot.pin.world_instance_id), str(region_slot.pin.slot_id), _region_manifest_path,
		_current_region_site(), day, world_name)

func _open_region_map() -> void:
	RegionEntry.region_mode = "view"
	RegionEntry.view = {}
	if region_slot != null:
		var world_id := str(region_slot.pin.world_instance_id)
		var slot_id := str(region_slot.pin.slot_id)
		RegionEntry.view = {"world_id": world_id, "slot_id": slot_id, "active": _current_region_site(),
			"visited": RegionEntry.visited_sites(world_id, slot_id)}
	_request_exit(REGION_MAP_SCENE)


func _build_region_travel_controls(parent: Node) -> void:
	parent.add_child(HSeparator.new())
	_label(parent, "世界地圖與船隊旅行", 20)
	_label(parent, "建立新世界前完整保存目前場景；新世界沿既有角色初始化開始。回復活動地點保留原人貨與在途進度。", 15)
	_region_form.manifest = LineEdit.new()
	_region_form.manifest.name = "RegionManifest"
	_region_form.manifest.text = RegionData.DEFAULT_MANIFEST
	parent.add_child(_region_form.manifest)
	_region_form.world = LineEdit.new()
	_region_form.world.name = "RegionWorld"
	_region_form.world.text = "world_%d" % Time.get_unix_time_from_system()
	parent.add_child(_region_form.world)
	_region_form.slot = LineEdit.new()
	_region_form.slot.name = "RegionSlot"
	_region_form.slot.text = "main"
	parent.add_child(_region_form.slot)
	_label(parent, "地點格座標（東向／北向）；建立時為起點，旅程時為相鄰目的地。", 15)
	_region_form.site_x = _number_input(parent, "RegionSiteX", -10000000, 10000000, 1170)
	_region_form.site_y = _number_input(parent, "RegionSiteY", -10000000, 10000000, 13252)
	_button(parent, "建立固定地圖世界（目前場景先完整保存）", "CreateFixedWorld", func() -> void: _region_world_ui(true))
	_button(parent, "回復此世界的活動地點／原旅程", "ResumeFixedWorld", func() -> void: _region_world_ui(false))
	_button(parent, "查看本世界固定地理縮圖", "PreviewFixedRegionSite", _preview_region_site)
	_region_form.preview = TextureRect.new()
	_region_form.preview.name = "FixedRegionSitePreview"
	_region_form.preview.custom_minimum_size = Vector2(300, 300)
	_region_form.preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_region_form.preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(_region_form.preview)
	_label(parent, "出航前，本隊所有活人（含仍乘船的退隊者）與共用糧都須上船。此地所有船須停妥、取消航令，完成登離船、船內作業與修理；每艘船須有清醒且就位的舵手及足額船員。只能直航到東、西、南、北相鄰地點：先航到出發邊界，所有船保持相同朝向，目的地船體接對側入口，船隊相對位置不變。旅途中，此地水域整地與其他船操作暫停；岸上生產、糧食消耗與疲勞持續。群眾模式（Crowd）下僅限無人戰鬥時出航；整隊群眾人物須上船，操控中的人物（Actor）不得乘船。", 15)
	_region_form.anchor_x = _number_input(parent, "RegionArrivalAnchorX", 0, 99, 0)
	_region_form.anchor_y = _number_input(parent, "RegionArrivalAnchorY", 0, 99, 99)
	_region_form.facing = _options(parent, ["朝東", "朝南", "朝西", "朝北"], "RegionArrivalFacing")
	_button(parent, "所選船所屬整隊船隊出航", "DepartShipJourney", _ship_journey_ui)
	_button(parent, "返航（須航回已走距離）", "ReturnShipJourney", func() -> void: show_result(cancel_ship_journey()))
	_region_form.status = _label(parent, "尚未開啟固定地圖存檔槽", 15)
	_region_form.status.name = "ShipJourneyStatus"

func _region_world_ui(create_new: bool) -> void:
	var coordinate := Vector2i(int(_region_form.site_x.value), int(_region_form.site_y.value))
	show_result(open_fixed_world(str(_region_form.manifest.text), str(_region_form.world.text), str(_region_form.slot.text), coordinate, create_new))
	_update_region_travel_status()

func _preview_region_site() -> void:
	var source: RegionData = region_slot.source if region_slot != null else RegionData.new()
	if region_slot == null:
		var loaded: Dictionary = source.load_manifest(str(_region_form.manifest.text))
		if not loaded.ok: show_result(loaded); return
	var coordinate := Vector2i(int(_region_form.site_x.value), int(_region_form.site_y.value))
	var preview: Dictionary = preload("res://scripts/region_lab/region_site_preview.gd").bake(source, coordinate)
	if not preview.ok: show_result(preview); return
	_region_form.preview.texture = ImageTexture.create_from_image(Image.create_from_data(int(preview.size.x), int(preview.size.y), false, Image.FORMAT_RGBA8, preview.pixels))
	show_result(Runtime.ok("已顯示本世界固定地理；未推進地點時間"))

func _ship_journey_ui() -> void:
	var boat: Dictionary = _selected_vehicle()
	if not SiteVehicleTransport.is_ship(boat): show_result(Runtime.fail("NO_TARGET", "請選擇原船隊中的船")); return
	var fleet: Array[String] = []
	for original: Dictionary in vehicles.records().values():
		if SiteVehicleTransport.is_ship(original) and int(original.team_id) == int(boat.team_id): fleet.append(str(original.id))
	var coordinate := Vector2i(int(_region_form.site_x.value), int(_region_form.site_y.value))
	var anchor := Vector2i(int(_region_form.anchor_x.value), int(_region_form.anchor_y.value))
	var direction: Vector2i = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP][int(_region_form.facing.selected)]
	show_result(begin_ship_journey(fleet, coordinate, anchor, direction))
	_update_region_travel_status()

func _update_region_travel_status() -> void:
	if _region_form.is_empty() or not is_instance_valid(_region_form.get("status")): return
	if region_slot == null: _region_form.status.text = "尚未開啟固定地圖存檔槽"; return
	var text := "本世界 %s／%s · 活動地點 %s\n共同遊戲時間 %.2f 秒" % [str(region_slot.pin.world_instance_id), str(region_slot.pin.slot_id), str(region_slot.control.active_site_id), float(region_slot.control.logical_game_seconds)]
	if not _ship_journey.is_empty():
		var returning := str(_ship_journey.phase) == "return"
		var elapsed := float(_ship_journey.return_elapsed_action_seconds) if returning else float(_ship_journey.elapsed_action_seconds)
		var required := float(_ship_journey.return_required_action_seconds) if returning else float(_ship_journey.seconds)
		var condition := "船體無法繼續漂浮，或沒有生還乘員；船貨仍保留，旅程無法繼續。" if _journey_stranded() else "船員不足或舵手未就位，航行暫停；糧食消耗與疲勞持續。昏迷者須甦醒後重新接舵。" if not _journey_can_advance() else "原船隊航行中"
		text += "\n%s %.2f／%.2f 航行秒 · %s" % ["返航" if returning else "出航", elapsed, required, condition]
	if region_operation_pending(): text += "\n正在更新目的地；完成前暫停旅程與遊戲時間。"
	_region_form.status.text = text

# Revalidate the original completed worker/cargo references after physical contacts.
# This query creates no job, person, resource or inventory owner.
func fire_resource_owner_guard(worker: Dictionary, cargo: Dictionary, cell: Vector2i, manual: bool) -> bool:
	var data: TerrainData = lab.terrain
	if data == null or not data.contains(cell) or bool(data.site.get("paused", false)): return false
	if manual:
		var actor: TerrainTestCharacter = lab.character
		return is_same(worker, data.site.manual) and is_same(cargo, data.site.manual.cargo) \
			and lab.actor_present(actor) and is_same(actor.ammo_inventory, cargo) and actor.terrain_cell == cell \
			and actor.can_act() and not actor.is_moving() and actor.action_time <= 0.0 and not actor.guarding \
			and actor.guard_transition_left <= 0.0 and actor.guard_break_left <= 0.0 and actor._rescue_left <= 0.0
	if is_same(worker, data.site.worker):
		var actor: TerrainTestCharacter = lab.npc
		return is_same(cargo, data.site.worker.cargo) and lab.actor_present(actor) \
			and is_same(actor.ammo_inventory, cargo) and actor.terrain_cell == cell and actor.can_act() \
			and not actor.is_moving() and actor.action_time <= 0.0 and not actor.guarding \
			and actor.guard_transition_left <= 0.0 and actor.guard_break_left <= 0.0 and actor._rescue_left <= 0.0 \
			and str(worker.get("mode", "")) == "work"
	for identity: int in work_team.active_ids():
		var person: Dictionary = work_team._person(identity)
		if person.is_empty() or not (person.owner is TerrainArmy or person.owner is CrowdPersonOwner): continue
		# G8a: a crowd person keeps its task and cargo in native-backed cold fields (combat_hot_get reads the
		# same stored references as the original row), so the same identity and state checks apply to it.
		var is_native: bool = person.owner is CrowdPersonOwner
		var row: Dictionary = person.row
		var task: Variant = person.owner.combat_hot_get(int(person.unit), &"work_task", {}) if is_native else row.get("work_task", {})
		var held: Variant = person.owner.combat_hot_get(int(person.unit), &"cargo", {}) if is_native else row.get("cargo", {})
		if not is_same(task, worker) or not is_same(held, cargo): continue
		var team: Variant = person.owner
		var unit := int(person.unit)
		return team.combat_can_act(unit) and not team.member_gone(unit) and person.cell == cell \
			and team.moving_to[unit] == TerrainArmy.INVALID_CELL and int(worker.cell) == data.index(cell) \
			and int(worker.get("work_cell", -1)) == data.index(cell) and str(worker.get("mode", "")) == "work" \
			and (bool(worker.get("manual", false)) or team.combat_order == TerrainArmy.CombatOrder.HOLD) \
			and float(team.combat_hot_get(unit, &"exchange_stagger", 0.0)) <= 0.0 \
			and not bool(team.combat_hot_get(unit, &"attack", false)) and str(team.combat_hot_get(unit, &"pose", "")) == "idle" \
			and not _work_person_unavailable(identity)
	return false


func _build_trial_fire_controls(column: VBoxContainer) -> void:
	_label(column, "實體箭矢／火攻（原隊長測試調度）", 18)
	_label(column, "先以原地圖操作選格，再更新目標。射擊使用原隊長權限及每名射手本人的彈藥；移動／守位沿本頁既有軍令。", 15)
	_trial_fire_ui.ammo = _options(column, ["NORMAL · 普通箭／弩矢", "FIRE_ARROW · 火箭（限弓）"], "TrialFireAmmo")
	_trial_fire_ui.policy = _options(column, ["持續射擊", "點燃後停射", "使目標功能失效"], "TrialFirePolicy")
	_trial_fire_ui.service = _options(column, ["整體功能", "住宿", "收貨", "加工", "供水", "駐軍", "休養", "訓練"], "TrialFireService")
	_trial_fire_ui.target = _options(column, ["人物（所選格）", "建築部件（所選格）", "地面（所選格）", "區域（所選格為左上角）"], "TrialFireTargetType")
	_trial_fire_ui.person = _options(column, [], "TrialFireTargetPerson")
	_trial_fire_ui.part = _options(column, [], "TrialFireTargetPart")
	_trial_fire_ui.area_label = _label(column, "區域寬／高（各 1–16 格，最多 256 格；超出地圖則拒絕）", 15)
	_trial_fire_ui.width = _number_input(column, "TrialFireAreaWidth", 1, 16, 2)
	_trial_fire_ui.height = _number_input(column, "TrialFireAreaHeight", 1, 16, 2)
	_button(column, "由原地圖所選格更新目標", "TrialFireRefreshTarget", _refresh_trial_fire_targets)
	_trial_fire_ui.issue = _button(column, "所選隊伍持續射擊", "TrialFireIssue", func() -> void: _trial_fire_order(false))
	_trial_fire_ui.stop = _button(column, "所選隊伍停止射擊", "TrialFireStop", func() -> void: _trial_fire_order(true))
	_button(column, "切換原 Site 暫停／繼續", "TrialFirePause", func() -> void:
		toggle_pause()
		_refresh_trial_fire_status())
	_label(column, "檢視原隊員本人彈藥／準備狀態", 15)
	_trial_fire_ui.shooter = _options(column, [], "TrialFireInspectShooter")
	_trial_fire_ui.debug = CheckButton.new()
	_trial_fire_ui.debug.name = "TrialFireFullObservation"
	_trial_fire_ui.debug.text = "測試完整觀察：顯示所選格原火勢／heat（含未觀測資訊）"
	column.add_child(_trial_fire_ui.debug)
	_trial_fire_ui.status = _label(column, "", 15)
	_trial_fire_ui.status.name = "TrialFireStatus"
	_build_trial_suppress_controls(column)
	_build_trial_fire_fixture_controls(column)
	_label(column, "此頁沿原人物與火攻操作；P4 建築功能、P5 保存及完整火攻驗收依各自具名結果判定。", 15)
	_trial_fire_ui.target.item_selected.connect(func(_index: int) -> void: _refresh_trial_fire_targets())
	_trial_fire_ui.shooter.item_selected.connect(func(_index: int) -> void: _refresh_trial_fire_status())
	_trial_fire_ui.debug.toggled.connect(func(_enabled: bool) -> void: _refresh_trial_fire_status())
	_refresh_trial_fire_targets()

func _refresh_trial_fire_targets() -> void:
	if _trial_fire_ui.is_empty() or lab.terrain == null: return
	var old_person: Variant = _trial_fire_ui.person.get_item_metadata(_trial_fire_ui.person.selected) if _trial_fire_ui.person.selected >= 0 else null
	var old_part: Variant = _trial_fire_ui.part.get_item_metadata(_trial_fire_ui.part.selected) if _trial_fire_ui.part.selected >= 0 else null
	_trial_fire_ui.person.clear()
	_trial_fire_ui.part.clear()
	_trial_fire_ui.terrain = lab.terrain
	_trial_fire_ui.cell = selected
	if lab.terrain.contains(selected) and not _crowd_active():
		for person: Dictionary in lab._siege_people():
			if person.cell != selected: continue
			_trial_fire_ui.person.add_item("人物 #%d" % int(person.id))
			var index: int = _trial_fire_ui.person.item_count - 1
			_trial_fire_ui.person.set_item_metadata(index, int(person.id))
			if old_person == int(person.id): _trial_fire_ui.person.select(index)
		var feature_id := str(lab.terrain.feature_at[lab.terrain.index(selected)])
		var feature: Dictionary = lab.terrain.site.features.get(feature_id, {})
		var geometry := Runtime.feature_geometry(lab.terrain, feature)
		for part_id: String in geometry.get("parts", {}):
			if not geometry.parts[part_id].cells.has(lab.terrain.index(selected)): continue
			var metadata := {"type": "structure", "feature_id": feature_id, "part_id": part_id}
			var part: Dictionary = geometry.parts[part_id]
			_trial_fire_ui.part.add_item("%s · %s · HP %.1f" % [feature_id, _building_part_label(part_id, part), float(part.get("hp", 0.0))])
			var index: int = _trial_fire_ui.part.item_count - 1
			_trial_fire_ui.part.set_item_metadata(index, metadata)
			if old_part == metadata: _trial_fire_ui.part.select(index)
	_trial_fire_ui.person.visible = _trial_fire_ui.target.selected == 0
	_trial_fire_ui.part.visible = _trial_fire_ui.target.selected == 1
	for node: Control in [_trial_fire_ui.area_label, _trial_fire_ui.width, _trial_fire_ui.height]:
		node.visible = _trial_fire_ui.target.selected == 3
	_refresh_trial_fire_status()

func _trial_fire_target() -> Dictionary:
	if _trial_fire_ui.get("terrain") != lab.terrain or _trial_fire_ui.get("cell") != selected or not lab.terrain.contains(selected):
		return Runtime.fail("STALE_SOURCE", "請由目前地圖所選格更新目標")
	var target := {}
	match _trial_fire_ui.target.selected:
		0:
			if _trial_fire_ui.person.selected < 0: return Runtime.fail("NO_TARGET", "所選格沒有可選人物")
			target = {"type": "person", "person_id": int(_trial_fire_ui.person.get_item_metadata(_trial_fire_ui.person.selected))}
		1:
			if _trial_fire_ui.part.selected < 0: return Runtime.fail("NO_TARGET", "所選格沒有可選原部件")
			target = _trial_fire_ui.part.get_item_metadata(_trial_fire_ui.part.selected).duplicate(true)
		2: target = {"type": "ground", "cell": [selected.x, selected.y]}
		3:
			var cells: Array = []
			for y in range(int(_trial_fire_ui.height.value)):
				for x in range(int(_trial_fire_ui.width.value)):
					var cell := selected + Vector2i(x, y)
					if not lab.terrain.contains(cell): return Runtime.fail("NO_TARGET", "指定區域超出地圖；未改動射擊命令")
					cells.append([cell.x, cell.y])
			target = {"type": "area", "cells": cells}
	return Runtime.ok("", {"target": target})

func _trial_fire_order(stopping: bool) -> void:
	if _crowd_active() and not lab.crowd_site.fire_host_active(): show_result(Runtime.fail("UNSUPPORTED_AMMO", "原生火箭尚未准入")); return
	var team := _selected_trial_team()
	if team == null: show_result(Runtime.fail("NO_TARGET", "所選原隊伍已不在場")); return
	var fire_owner: Variant = lab.fire_owner_view(team)
	var requester: int = int(fire_owner.current_commander)
	if fire_owner is CrowdPersonOwner: requester = fire_owner._command_index(requester)
	if stopping:
		show_result(lab.stop_fire_order(requester, team))
	else:
		var selected_target := _trial_fire_target()
		if not selected_target.ok: show_result(selected_target); return
		var ammo_mode := "FIRE_ARROW" if _trial_fire_ui.ammo.selected == 1 else "NORMAL"
		var policy: String = ["CONTINUOUS", "IGNITE_ONLY", "DESTROY_FUNCTION"][_trial_fire_ui.policy.selected]
		var service: String = ["", "lodging", "intake", "production", "water", "garrison", "recovery", "training"][_trial_fire_ui.service.selected]
		show_result(lab.issue_fire_order(requester, team, selected_target.target, ammo_mode, policy, service))
	_refresh_trial_fire_status()

func _refresh_trial_fire_status() -> void:
	if _trial_fire_ui.is_empty() or not is_instance_valid(_trial_fire_ui.get("status")): return
	var team := _selected_trial_team()
	var fire_owner: Variant = lab.fire_owner_view(team) if team != null else null
	var host_blocked: bool = _crowd_active() and not lab.crowd_site.fire_host_active()
	_trial_fire_ui.issue.disabled = team == null or host_blocked or not lab.physical_ranged_enabled or not lab.exchange_enabled
	_trial_fire_ui.stop.disabled = team == null or host_blocked
	if host_blocked:
		_trial_fire_ui.status.text = "原生火箭尚未准入；仍保留原 Save／Handoff 守衛。"
		return
	if team == null:
		_trial_fire_ui.status.text = "請先選擇仍在場的原隊伍。"
		return
	var signature: Array = [team.get_instance_id(), team.team_id]
	var indices: Array[int] = []
	if fire_owner is CrowdPersonOwner:
		for index: int in fire_owner.combat_units: indices.append(index)
	else:
		for index in range(team.combat_units.size()): indices.append(index)
	for index: int in indices:
		if fire_owner.is_member(index): signature.append(fire_owner.combat_identity(index))
	if _trial_fire_ui.get("roster", []) != signature:
		var old_identity: int = int(_trial_fire_ui.shooter.get_item_metadata(_trial_fire_ui.shooter.selected)) if _trial_fire_ui.shooter.selected >= 0 else 0
		_trial_fire_ui.shooter.clear()
		for index: int in indices:
			if not fire_owner.is_member(index): continue
			var identity: int = fire_owner.combat_identity(index)
			_trial_fire_ui.shooter.add_item("原隊員 #%d" % identity)
			var choice: int = _trial_fire_ui.shooter.item_count - 1
			_trial_fire_ui.shooter.set_item_metadata(choice, identity)
			if identity == old_identity or old_identity == 0 and index == fire_owner.current_commander: _trial_fire_ui.shooter.select(choice)
		_trial_fire_ui.roster = signature
	var summary := "原隊 #%d · 隊長索引 %d · %s · %s · %s\n所選格 %s；原命令目標 %s" % [team.team_id, fire_owner.current_commander,
		"暫停" if bool(lab.terrain.site.get("paused", false)) else "進行中", "持續射擊" if fire_owner.ranged_enabled else "已停射", fire_owner.ranged_ammo_mode, selected, fire_owner.ranged_target]
	if _trial_fire_ui.shooter.selected >= 0:
		var identity: int = int(_trial_fire_ui.shooter.get_item_metadata(_trial_fire_ui.shooter.selected))
		for index: int in indices:
			if not fire_owner.is_member(index) or fire_owner.combat_identity(index) != identity: continue
			var cargo: Dictionary = fire_owner.combat_hot_get(index, &"cargo", {}) if fire_owner is CrowdPersonOwner else team.combat_units[index].get("cargo", {})
			var reservation: Dictionary = lab.fire_reservations.get(identity, {})
			var preparation := "尚無準備預約"
			if not reservation.is_empty() and is_same(reservation.person.owner, fire_owner) and int(reservation.person.unit) == index:
				preparation = "%s 準備剩餘 %.2f 行動秒（尚未扣彈）" % [str(reservation.mode), maxf(0.0, float(reservation.ready_at) - float(lab.fire_action_cursor))]
			summary += "\n本人 #%d：普通箭 %d／弩矢 %d／火箭 %d；%s" % [identity, int(cargo.get("arrow", 0)), int(cargo.get("bolt", 0)), int(cargo.get("fire_arrow", 0)), preparation]
			break
	if _trial_fire_ui.debug.button_pressed:
		summary += "\n測試完整觀察（非正式可見資訊）：" + _trial_fire_debug_status()
	_trial_fire_ui.status.text = summary

func _trial_fire_debug_status() -> String:
	if lab.terrain == null or not lab.terrain.contains(selected): return "目前所選格無效"
	var units: Dictionary = lab.terrain.site.get("fire", {}).get("units", {})
	var cell_index: int = lab.terrain.index(selected)
	var feature_id := str(lab.terrain.feature_at[cell_index])
	var resources: Array = lab.terrain.resources_at.get(cell_index, [])
	var rows: Array[String] = []
	for key: String in units:
		var unit: Dictionary = units[key]
		var selected_unit: bool = str(unit.get("kind", "")) == "feature" and str(unit.get("feature", "")) == feature_id
		selected_unit = selected_unit or str(unit.get("kind", "")) == "resource" and resources.has(str(unit.get("resource", "")))
		if not selected_unit: continue
		rows.append("%s %s · heat %.2f · intensity %.2f" % [key, str(unit.get("state", "DORMANT")), float(unit.get("heat", 0.0)), float(unit.get("intensity", 0.0))])
	if rows.is_empty(): return "所選格尚無已登錄火勢資料"
	rows.sort()
	return "\n" + "\n".join(rows)


# P3-only addition. Requires the reviewed PersonActions begin_fire_suppress API.
# Do not append this to a P1/P2 controller before that original owner exists.
func _build_trial_suppress_controls(column: VBoxContainer) -> void:
	_label(column, "接近放火／滅火（原人物工作／有限測試供給）", 18)
	_label(column, "先在原目標格選部件或木材並記錄目標，再選候選接近格；執行者使用上方檢視的原隊員。是否安全、可達、有供給及實際工作狀態由原 owner 判定。", 15)
	_button(column, "記錄所選原作業目標", "TrialSuppressCaptureTarget", _trial_suppress_capture_target)
	_button(column, "原隊長命令所選隊員接近放火", "TrialIgniteBegin", func() -> void: _trial_suppress_order(false, "IGNITE"))
	_button(column, "原隊長命令所選隊員於所選格滅火", "TrialSuppressBegin", func() -> void: _trial_suppress_order(false))
	_button(column, "取消所選隊員的滅火工作", "TrialSuppressCancel", func() -> void: _trial_suppress_order(true))
	_trial_fire_ui.suppress_status = _label(column, "尚未記錄原目標。", 15)
	_trial_fire_ui.suppress_status.name = "TrialSuppressStatus"
	_label(column, "火場天氣（解除暫停後套用）", 18)
	var wind := OptionButton.new()
	wind.name = "TrialFireWind"
	for text: String in ["無風", "向東", "向西", "向北", "向南"]: wind.add_item(text)
	column.add_child(wind)
	_trial_fire_ui.wind = wind
	var rain := OptionButton.new()
	rain.name = "TrialFireRain"
	for text: String in ["無雨", "小雨", "大雨"]: rain.add_item(text)
	column.add_child(rain)
	_trial_fire_ui.rain = rain
	_button(column, "套用風雨", "TrialFireWeather", _trial_fire_weather)

func _trial_suppress_capture_target() -> void:
	if _crowd_active() or lab.terrain == null: show_result(Runtime.fail("UNSUPPORTED_AMMO")); return
	var key := ""
	if _trial_fire_ui.target.selected == 1:
		var target_value := _trial_fire_target()
		if not target_value.ok: show_result(target_value); return
		key = "feature:%s:%s" % [str(target_value.target.feature_id), str(target_value.target.part_id)]
	elif not source_key.is_empty():
		key = "resource:" + source_key
	var target: Dictionary = Runtime.fire_work_target(lab.terrain, key, "IGNITE")
	if not target.ok: show_result(target); return
	_trial_fire_ui.suppress_binding = {"terrain": lab.terrain, "key": key, "generation": int(target.generation)}
	_refresh_trial_suppress_status()

func _trial_suppress_order(cancelling: bool, mode: String = "SUPPRESS") -> void:
	if _crowd_active(): show_result(Runtime.fail("UNSUPPORTED_AMMO", "原生滅火尚未准入")); return
	var team := _selected_trial_team()
	if team == null or not team.command_eligible(team.current_commander): show_result(Runtime.fail("NO_AUTHORITY")); return
	if _trial_fire_ui.shooter.selected < 0: show_result(Runtime.fail("NO_TARGET", "請先選定原隊員")); return
	var executor: int = int(_trial_fire_ui.shooter.get_item_metadata(_trial_fire_ui.shooter.selected))
	var member := false
	for index in range(team.combat_units.size()):
		if team.is_member(index) and team.combat_identity(index) == executor: member = true; break
	if not member: show_result(Runtime.fail("STALE_SOURCE", "原隊員已不在所選队伍")); return
	if cancelling:
		if str(person_actions.job_for(executor).get("kind", "")) != "fire_suppress": show_result(Runtime.fail("NO_TARGET", "本人目前沒有滅火工作")); return
		show_result(person_actions.cancel(executor))
	else:
		var binding: Dictionary = _trial_fire_ui.get("suppress_binding", {})
		if binding.is_empty() or binding.terrain != lab.terrain: show_result(Runtime.fail("STALE_SOURCE", "請重新記錄目前 Site 的原燃燒目標")); return
		var target: Dictionary = Runtime.fire_work_target(lab.terrain, str(binding.key), mode, int(binding.generation))
		if not target.ok: show_result(target); return
		var result: Dictionary = person_actions.begin_fire_ignite(team.combat_identity(team.current_commander), executor, str(binding.key), selected, true) if mode == "IGNITE" else person_actions.begin_fire_suppress(team.combat_identity(team.current_commander), executor, str(binding.key), selected, true)
		show_result(result)
	_refresh_trial_suppress_status()

func _refresh_trial_suppress_status() -> void:
	if not is_instance_valid(_trial_fire_ui.get("suppress_status")): return
	if _crowd_active():
		_trial_fire_ui.suppress_status.text = "原生滅火尚未准入。"
		return
	var binding: Dictionary = _trial_fire_ui.get("suppress_binding", {})
	var text := "原目標 %s；候選接近格 %s" % [str(binding.get("key", "尚未記錄")), selected]
	if not binding.is_empty() and binding.terrain != lab.terrain: text += "（舊 Site 目標，須重新記錄）"
	if _trial_fire_ui.shooter.selected >= 0:
		var executor: int = int(_trial_fire_ui.shooter.get_item_metadata(_trial_fire_ui.shooter.selected))
		var job: Dictionary = person_actions.job_for(executor)
		if str(job.get("kind", "")) == "fire_suppress":
			text += " · 接近放火" if str(job.get("fire_work_mode", "SUPPRESS")) == "IGNITE" else " · 滅火"
			text += "\n原人物 #%d · %s · %s · %s" % [executor, str(job.get("phase", "")), str(job.get("paused", "")), str(job.get("target_key", ""))]
			if job.has("supply_q"): text += " · 原有限供給 %d q" % int(job.supply_q)
			else: text += " · 原供給投影尚未接入"
		else: text += "\n原人物 #%d 目前沒有滅火工作" % executor
	_trial_fire_ui.suppress_status.text = text


func _build_trial_fire_fixture_controls(column: VBoxContainer) -> void:
	var isolated := bool(lab._fire_lab_fixture_guard().ok)
	_label(column, "隔離火場控制" if isolated else "完整單步／seed 重置僅開放於 --site-fire-lab 隔離火場", 18)
	_trial_fire_ui.fixture_seed = _number_input(column, "TrialFireFixtureSeed", 0, 2147483646, int(lab.get_meta(&"fire_lab_fixture", {}).get("seed", 12345)))
	_trial_fire_ui.fixture_seed.editable = isolated
	var single := _button(column, "完整單步（維持暫停）", "TrialFireSingleStep", func() -> void:
		show_result(lab.step_fire_lab_fixture())
		_refresh_trial_fire_status()
		_refresh_trial_suppress_status())
	single.disabled = not isolated
	var reset := _button(column, "以 seed 重建隔離火場", "TrialFireResetFixture", func() -> void:
		show_result(lab.reset_fire_lab_fixture(int(_trial_fire_ui.fixture_seed.value))))
	reset.disabled = not isolated
	if isolated:
		_label(column, "固定平坦火場：原弓手與弩手、原工作隊、各自有限彈藥／滅火補給、原木材與付費木屋。點火須真實發射火箭；重建僅丟棄本隔離場景。", 15)

func _trial_fire_weather() -> void:
	if _crowd_active() or lab.terrain == null: show_result(Runtime.fail("UNSUPPORTED_BACKEND")); return
	var wind: Vector2 = [Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN][_trial_fire_ui.wind.selected]
	var rain: float = [0.0, 0.25, 1.0][_trial_fire_ui.rain.selected]
	show_result(Runtime.fire_set_weather(lab.terrain, lab.fire_action_cursor, wind, rain))


func capture_region_checkpoint(purpose: String, effects_complete: bool = true,
		endpoint_payload: Dictionary = {}, token: String = "", read_only: bool = false) -> Dictionary:
	if region_slot == null or lab.terrain == null: return Runtime.fail("NO_REGION_SLOT")
	var boarding: Dictionary = vehicles.boarding_save_guard()
	if not boarding.ok: return boarding
	# A live CrowdSite joins the checkpoint only as a non-read-only capture. The same
	# synchronous native capture as the cold save supplies state.crowd; a detached
	# read-only copy would need its own section and stays refused.
	var crowd_admitted := _crowd_active()
	if crowd_admitted and read_only: return Runtime.fail("REGION_BACKEND_UNADMITTED")
	if token.is_empty(): token = "region_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var request: Dictionary = region_slot.region_checkpoint_context(lab.terrain, purpose, token, effects_complete, endpoint_payload)
	if not request.ok: return request
	# G6.2: an admitted live crowd stamps its checkpoint "native". G6: the live mode and bind receipt follow the crowd too.
	if crowd_admitted: request.context["backend"] = "native"
	var crowd_captured := {}
	if crowd_admitted:
		# capture_save keeps the existing BUSY guards (arrows in flight, pending captivity, siege commit).
		crowd_captured = lab.crowd_site.capture_save()
		if not crowd_captured.ok: return crowd_captured
	if not read_only: _capture_positions() # Original presenters; ordinary-save guards remain.
	if crowd_admitted: _apply_region_crowd_capture(crowd_captured)
	var captured: Dictionary = lab.capture_region_owner_state(request.context, crowd_admitted)
	if not captured.ok: return captured
	var states: Dictionary = captured.get("owner_states", {"scene": captured.state})
	return Store.capture_region_snapshot(lab.terrain, request.context, states, read_only, crowd_admitted)

func checkpoint_region_internal(purpose: String, effects_complete: bool = true,
		endpoint_payload: Dictionary = {}, token: String = "") -> Dictionary:
	var captured := capture_region_checkpoint(purpose, effects_complete, endpoint_payload, token)
	if not captured.ok: return captured
	return region_slot.checkpoint_region_site(lab.terrain, captured.context, captured.owners, {}, false, captured)


func _prepare_original_work_inputs() -> Dictionary:
	var data: TerrainData = lab.terrain
	if data == null or data.site.is_empty(): return {}
	var worker_ready := false
	var worker_limit := 0
	if lab.actor_present(lab.npc):
		var worker: Dictionary = data.site.worker
		worker["cell"] = data.index(lab.npc.terrain_cell)
		worker_limit = floori(Runtime.CARRY_CAPACITY - Runtime.carried_load(data.site, {}, lab.npc.item_state))
		lab.npc.work_resting = PersonFatigue.needs_work_rest(lab.npc.fatigue, lab.npc.work_resting)
		var capable: bool = lab.npc.can_act() and lab.npc.action_time <= 0 and not lab.npc.guarding and lab.npc.guard_transition_left <= 0.0 and lab.npc.guard_break_left <= 0.0 and lab.npc._rescue_left <= 0.0 and lab.npc.visible and not _person_has_duty(lab.npc.person_id)
		if bool(data.site.worker_enabled) and lab.npc.work_resting:
			# STOP clears future navigation, not the committed step or original task/cargo.
			if lab.npc.command != TerrainTestNPC.Command.STOP:
				lab.npc.issue_command(TerrainTestNPC.Command.STOP)
			worker["status"] = "疲勞輪休；安全休息至 50 後續作"
		if bool(worker.get("manual_control", false)):
			if lab.controlled_person_id() == lab.npc.person_id and capable and not lab.npc.is_moving() and worker.cell == worker.work_cell and not str(worker.target).is_empty():
				worker["mode"] = "work"
				worker_ready = true
			else:
				worker["manual_control"] = false
				worker["target"] = ""
				worker["progress"] = 0.0
		elif bool(data.site.worker_enabled) and lab.controlled_person_id() != lab.npc.person_id and capable and not lab.npc.work_resting:
			if str(worker.target).is_empty() and lab.npc.command != TerrainTestNPC.Command.STOP:
				lab.npc.issue_command(TerrainTestNPC.Command.STOP)
			if str(worker.target).is_empty() and 0.5 - _work_elapsed <= lab.ACTION_TIME_EPSILON:
				Runtime.assign_task(data, Runtime.choose_task(data, lab.npc.terrain_cell, _worker_blocked, null, null, work_team.reserved_targets(), lab.npc.faction_id))
				_work_elapsed = 0.0
			if not str(worker.target).is_empty():
				var goal := data.cell_from_index(int(worker.work_cell))
				if lab.npc.terrain_cell == goal and not lab.npc.is_moving():
					# Autonomous work owns this arrived body; user orders first release_worker().
					if lab.npc.command != TerrainTestNPC.Command.STOP:
						lab.npc.issue_command(TerrainTestNPC.Command.STOP)
					worker["mode"] = "work"
					worker_ready = true
				elif not lab.npc.is_moving() and 0.5 - _work_elapsed <= lab.ACTION_TIME_EPSILON:
					worker["mode"] = "travel"
					if not lab.npc.issue_command(TerrainTestNPC.Command.MOVE_TO_CELL, goal):
						worker["target"] = ""
						worker["mode"] = "idle"
						worker["status"] = "路線受阻；等待重試"
					_work_elapsed = 0.0
	var manual: Dictionary = data.site.manual
	var manual_ready: bool = lab.actor_present(lab.character) and not str(manual.target).is_empty() and lab.character.can_act() and lab.character.action_time <= 0 and not lab.character.guarding and lab.character.guard_transition_left <= 0.0 and lab.character.guard_break_left <= 0.0 and lab.character._rescue_left <= 0.0 and not _person_has_duty(lab.character.person_id) and not lab.character.is_moving() and data.index(lab.character.terrain_cell) == int(manual.get("cell", -1))
	if not manual_ready:
		manual["target"] = ""
		manual["progress"] = 0.0
	var manual_limit := floori(Runtime.CARRY_CAPACITY - Runtime.carried_load(data.site, {}, lab.character.item_state)) if lab.actor_present(lab.character) else 0
	return {"worker_ready": worker_ready, "manual_ready": manual_ready, "worker_limit": worker_limit, "manual_limit": manual_limit, "worker_faction": lab.npc.faction_id if lab.actor_present(lab.npc) else -1}


## Call-local demands. The existing owners still decide qualification and commit.
func _shared_person_request(provider: String, key: String, people: Array, remaining: float,
		seconds: float, productive_kind: String = "single") -> Dictionary:
	var participants: Array = []
	var paused := ""
	for person: Dictionary in people:
		if person.is_empty(): return {}
		var identity := int(person.person_id)
		var participant: Dictionary
		if person.owner is CrowdPersonOwner:
			participant = lab.crowd_site.work_fatigue_participant(identity, identity != lab.controlled_person_id())
			if participant.is_empty(): return {}
		else:
			participant = {"person_id": identity, "body": person.body, "effort_rate": PersonFatigue.effort_rate(person.body), "rest_limited": identity != lab.controlled_person_id()}
		participants.append(participant)
		if identity != lab.controlled_person_id() and person_actions._threat(person, {}): paused = "THREAT"
	if participants.is_empty(): return {}
	return {"provider": provider, "key": key, "participants": participants, "remaining": remaining,
		"productive_kind": productive_kind, "progress_multiplier": 1.0, "max_game_seconds": seconds, "paused": paused}

func _prepare_camp_operating_projection(seconds: float) -> void:
	var data: TerrainData = lab.terrain
	var camp: Dictionary = {}
	if is_finite(seconds) and seconds > 0.0 and bool(_shared_worker_inputs.get("worker_ready", false)) and lab.actor_present(lab.npc):
		var actor: TerrainTestCharacter = lab.npc
		var task: Dictionary = data.site.worker
		var person: Dictionary = person_actions._person(int(actor.person_id))
		var source: Dictionary = {"actor": actor, "person": person, "task": task}
		if not person.is_empty() and is_same(person.body, actor) and is_same(person.cargo, task.get("cargo")) and is_same(person.holder, actor.item_state) \
			and Runtime._item_holder_shape(person.holder) and str(person.holder.holder) == "person:" + str(int(person.person_id)) \
			and Runtime._resource_stack(person.cargo) and _shared_runtime_source_ready(source) \
			and _native_held_runtime_ready(int(actor.person_id), task) and not person_actions._threat(person, {}):
			var checked: Dictionary = Runtime.camp_operating_slot_preflight(data, task, person.cargo,
				int(_shared_worker_inputs.get("worker_limit", 0)), int(person.faction), int(person.person_id), reserves_cell)
			if checked.ok: camp = task
	Runtime.set_camp_operating_task(data, camp)

func _retain_admitted_camp_projection(requests: Array) -> void:
	var data: TerrainData = lab.terrain
	var admitted: bool = false
	for request: Dictionary in requests:
		if str(request.provider) == "runtime" and str(request.key) == "worker" and is_same(request.get("task"), data.site.worker) and str(request.get("paused", "")).is_empty():
			admitted = true
	if not admitted:
		Runtime.set_camp_operating_task(data, {})

func prepare_shared_owner_work_requests(seconds: float) -> Array[Dictionary]:
	_prepare_camp_operating_projection(seconds)
	var requests: Array[Dictionary] = []
	for manual: bool in [false, true]:
		var name := "manual" if manual else "worker"
		if not bool(_shared_worker_inputs.get(name + "_ready", false)): continue
		var actor: TerrainTestCharacter = lab.character if manual else lab.npc
		var task: Dictionary = lab.terrain.site[name]
		if not _native_held_runtime_ready(int(actor.person_id), task):
			_shared_worker_inputs[name + "_ready"] = false
			continue
		var checked := Runtime.work_preflight(lab.terrain, task, task.cargo,
			int(_shared_worker_inputs.get(name + "_limit", 0)), int(actor.faction_id), int(actor.person_id), reserves_cell)
		if not checked.ok:
			_shared_worker_inputs[name + "_ready"] = false
			continue
		var request := _shared_person_request("runtime", name, [person_actions._person(actor.person_id)],
			float(checked.remaining), seconds)
		if request.is_empty():
			_shared_worker_inputs[name + "_ready"] = false
			continue
		# Original pickup/deposit has zero effort. The original Runtime callback
		# can still complete it with a zero effective allocation.
		request.payment = checked.get("payment", {})
		request.payment_source = checked.get("payment_source", {})
		request.payment_key = str(checked.get("payment_key", name))
		request.payment_order = -2 if not manual else -1
		request.task = task
		request = _shared_runtime_physical_request(request, checked)
		if request.is_empty():
			_shared_worker_inputs[name + "_ready"] = false
			continue
		requests.append(request)
	_retain_admitted_camp_projection(requests)
	var native_training: Dictionary = prepare_shared_native_training_requests(seconds, float(lab.terrain.site.combat_left))
	if not native_training.ok:
		latch_original_step_fault(native_training)
		_retain_admitted_camp_projection([])
		return []
	requests.append_array(native_training.requests)
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled or _crowd_active() and lab.crowd_site.owns_original_team(team): continue
		var entry := _supply_entry(team)
		if entry.is_empty(): continue
		var members := _team_members(team)
		if bool(entry.get("training_order", false)):
			var field := TrainingGround.inspect(self, team.team_id, str(entry.get("training_feature_id", "")))
			var fed: bool = not entry.sustain.cohorts.is_empty()
			for cohort: Dictionary in entry.sustain.cohorts: fed = fed and float(cohort.coverage) >= 1.0
			if field.ok and _team_safe(team, members) and bool(field.get("safe", false)) and _team_stopped(team, true) \
				and fed and not bool(entry.sustain.routed) and team.command_eligible(team.current_commander):
				for identity: Variant in field.get("eligible_ids", []):
					var person := person_actions._person(int(identity))
					if person.is_empty() or _person_has_duty(int(identity)): continue
					var request := _shared_person_request("training", str(int(identity)), [person], seconds, seconds)
					if not request.is_empty(): requests.append(request)
		if not entry.delivery.is_empty() and not bool(entry.delivery.get("pending", false)) and _delivery_valid(team, entry):
			var request := _shared_delivery_request(team, entry, seconds)
			if not request.is_empty(): requests.append(request)
	# P1p: a crowd team's delivery joins the SAME shared work point as the grid's. Its carriers are native participants
	# (_shared_person_request -> CrowdSite.work_fatigue_participant), so their effort is charged once, to the formation's native
	# fatigue pool, by the native point publisher. The job's own timer advances only in the point tail
	# (finish_shared_native_delivery_prefix), from the point's final allocation, after the native publication.
	_shared_native_delivery_prefixes = {}
	if _crowd_active():
		for team_owner: RefCounted in lab.crowd_site.person_owners():
			var entry := _supply_entry(team_owner)
			if entry.is_empty() or entry.get("delivery", {}).is_empty() or bool(entry.delivery.get("pending", false)) or not _delivery_valid(team_owner, entry): continue
			var request := _shared_delivery_request(team_owner, entry, seconds)
			if request.is_empty(): continue
			var people: Array[Dictionary] = []
			for person: Dictionary in _delivery_people(entry): people.append({"person_id": int(person.person_id), "unit": int(person.unit)})
			_shared_native_delivery_prefixes[str(team_owner.team_id)] = {"owner": team_owner, "entry": entry, "job": entry.delivery,
				"left": float(entry.delivery.left), "participants": request.participants, "people": people}
			requests.append(request)
	var guards := {}
	for relation: Dictionary in lab.terrain.site.captivity.values():
		if str(relation.get("prison_id", "")).is_empty(): guards[int(relation.guard_id)] = true
	for identity: int in guards:
		var person := person_actions._person(identity)
		if not person_actions._ready(person, true) or person_actions.is_busy(identity): continue
		var request := _shared_person_request("guard", str(identity), [person], seconds, seconds, "raw")
		if not request.is_empty(): requests.append(request)
	return requests

## The shared-work request of one team's food delivery (grid army or crowd owner): its carriers, the effective seconds left and,
## for a possible positive terminal, the source reservation.
func _shared_delivery_request(team: Variant, entry: Dictionary, seconds: float) -> Dictionary:
	var people := _delivery_people(entry)
	var request := _shared_person_request("delivery", str(team.team_id), people, float(entry.delivery.left), seconds,
		"joint" if people.size() == 2 else "single")
	if not request.is_empty():
		# Original finite source reservation only for a possible positive
		# terminal. Opened food and internal moves remain FoodDelivery's
		# original scalar/locations transaction, not an integer recipe.
		if str(request.paused).is_empty() and float(request.remaining) <= seconds + PersonFatigue.WORK_PLAN_EPS:
			request.payment_source = entry.delivery.source_cargo
			request.payment = entry.delivery.items.duplicate(true)
			request.payment_key = "delivery:" + str(team.team_id)
	return request

func shared_supply_event_limit(maximum: float) -> Dictionary:
	var limit := maximum
	if _crowd_active():
		var native_due: Dictionary = settle_native_supply_begin_endpoint(maximum)
		if not native_due.ok: return native_due
		limit = minf(limit, float(native_due.game_seconds))
	# A due meal is an original zero-time resupply. It changes no body/time;
	# its real inventory debit precedes this interval's work-material admission.
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled or _crowd_active() and lab.crowd_site.owns_original_team(team): continue
		var entry := _supply_entry(team)
		if entry.is_empty(): continue
		var members := _team_members(team)
		var hot_read := _supply_hot_reader(team, members, {})
		var context := {}
		if int(entry.version) == 3: context["food_locations"] = ship_food_locations(team, members)
		var supplied := Sustain.resupply(entry.sustain, members, _supply_stock(entry), true, hot_read, {}, context)
		if not supplied.ok: return Runtime.fail("SUPPLY_PREFLIGHT", str(supplied.get("message", "")))
		if float(supplied.get("consumed_rations", 0.0)) > 0.0: entry.revision = int(entry.revision) + 1
		_observe_original_food_result("team", str(team.team_id), float(entry.sustain.at), supplied)
		limit = minf(limit, _shared_supply_state_limit(entry.sustain, members, maximum))
	for key: String in lab.terrain.site.get("person_supply", {}):
		if _native_sustain_original_person(int(key)): continue
		var state: Dictionary = lab.terrain.site.person_supply[key]
		var person := _supply_person(int(key))
		if person.is_empty(): return Runtime.fail("STALE_SUPPLY_OWNER")
		var members := captivity_supply.personal_members_id(int(key))
		var supplied := Sustain.resupply(state, members, person.cargo, true)
		if not supplied.ok: return Runtime.fail("SUPPLY_PREFLIGHT", str(supplied.get("message", "")))
		if float(supplied.get("consumed_rations", 0.0)) > 0.0: person.holder.version = int(person.holder.version) + 1
		_observe_original_food_result("person", key, float(state.at), supplied)
		limit = minf(limit, _shared_supply_state_limit(state, members, maximum))
	return Runtime.ok("", {"game_seconds": limit})

func _shared_supply_state_limit(state: Dictionary, members: Dictionary, maximum: float) -> float:
	var limit := maximum
	for cohort: Dictionary in state.get("cohorts", []):
		var meal := float(cohort.meal_until) - float(state.at)
		if meal > 0.000000001: limit = minf(limit, meal)
		var deficit := 1.0 - float(cohort.coverage)
		if deficit <= 0.0: continue
		var hunger := float(cohort.hunger)
		if hunger < 48.0: limit = minf(limit, (48.0 - hunger) / deficit * Sustain.HOUR)
		for identity: Variant in cohort.ids:
			var person := person_actions._person(int(identity))
			if person.is_empty() or float(person.hp) <= 0.0: continue
			limit = minf(limit, (maxf(0.0, 48.0 - hunger) + float(person.hp)) / deficit * Sustain.HOUR)
	if bool(state.get("routed", false)):
		var regroup := 1800.0 - float(state.regroup_seconds)
		if regroup > 0.000000001: limit = minf(limit, regroup)
		var morale := float(state.morale)
		if morale < 50.0: limit = minf(limit, (50.0 - morale) / 5.0 * Sustain.HOUR)
	return maxf(0.000000001, limit)

func _consume_shared_guard_work() -> Dictionary:
	var handled := {}
	for key: String in _shared_work_plan.get("jobs", {}).get("guard", {}):
		var entry: Dictionary = _shared_work_plan.jobs.guard[key]
		var identity := int(key)
		var person := person_actions._person(identity)
		if person.is_empty(): continue
		var actual := float(entry.get("participant_seconds", {}).get(identity, 0.0))
		handled[identity] = actual
		if identity != lab.controlled_person_id():
			person_actions._body_set(person, "work_resting", str(entry.get("paused", "")) == "REST")
	return handled

func advance_person_death_timers(real_seconds: float) -> void:
	if not is_finite(real_seconds) or real_seconds < 0.0: return
	for identity: int in _pending_deaths:
		if _crowd_active() and lab.crowd_site.has_pending_capture(identity): continue
		_pending_deaths[identity] = maxf(0.0, float(_pending_deaths[identity]) - real_seconds)

# In ORIGINAL settle_person_deaths, call advance_person_death_timers(real_seconds)
# once before its existing identity loop; remove only the old per-row decrement.
# Keep all original ship_death_location, remains, holder, Cape, captivity, and
# loot_settled callbacks in that existing zero-time owner.
# Original Lab._advance_combat's old settle_person_deaths(elapsed) becomes:
# if _region_deferring_endpoint(): site_controller.advance_person_death_timers(elapsed)
# else: site_controller.settle_person_deaths(elapsed)


const InitialArtisans = preload("res://scripts/terrain_lab/site_technology_artisans.gd")

# P5C-S2B test seam (default invalid = off). Forwarded to the slot on creation only.
var initial_write_fault: Callable
var _initial_world_candidate: RegionSaveSlot

var _initial_world_birth_data: TerrainData
# P5C-S3: populated companion bodies from the same birth; reset with the birth data.
var _initial_companion_births: Dictionary = {}

var _initial_world_archive: Dictionary = {}

func _initial_world_request(manifest_path: String, world_id: String, slot_id: String, starting_site: Vector2i, create_new: bool, initial_scenario_id: String) -> Dictionary:
	return {"kind": "world", "manifest": manifest_path, "world_id": world_id, "slot_id": slot_id,
		"site": starting_site, "create_new": create_new, "initial_scenario_id": initial_scenario_id}


func _remember_initial_world_pending(result: Dictionary, request: Dictionary, candidate: RegionSaveSlot) -> Dictionary:
	var code := str(result.get("code", ""))
	if code in ["SAVE_IO", "COMMITTED_UNBOUND", "LOAD_RETRY", "REGION_BIND_INCOMPLETE"] and candidate != null and candidate.initialization_pending():
		var pending := result.duplicate(true)
		pending["ok"] = false
		pending["code"] = "PENDING"
		pending["cause_code"] = code
		pending["message"] = "原開局候選或首代已保留；停止步進，接續同一建立請求。"
		_auto_save_blocked = true
		return _remember_region_pending(pending, request)
	return _remember_region_pending(result, request)


func _prepare_initial_world(candidate: RegionSaveSlot, starting_site: Vector2i, initial_scenario_id: String) -> Dictionary:
	var checkpoint: Dictionary = candidate.person_allocation_checkpoint()
	var result: Dictionary = _prepare_initial_world_candidate(candidate, starting_site, initial_scenario_id)
	if not result.ok and _initial_world_birth_data == null and not candidate.rollback_person_allocation(checkpoint): return Runtime.fail("PERSON_ALLOCATION_CONFLICT")
	return result

func _prepare_initial_world_candidate(candidate: RegionSaveSlot, starting_site: Vector2i, initial_scenario_id: String) -> Dictionary:
	var retained: Dictionary = candidate.initial_site_candidate()
	if not retained.ok: return retained
	if retained.has("data"):
		return retained # Checked original prepared/committed body; never birth again.
	if not candidate._marker.is_empty() or not str(candidate.control.active_site_id).is_empty() or float(candidate.control.logical_game_seconds) != 0.0 or not candidate.control.fire_clock.get("index", {}).is_empty() or int(candidate.control.fire_clock.sequence) != 0 or float(candidate.control.fire_clock.action_seconds) != 0.0:
		return Runtime.fail("INVALID_INITIAL_GENERATION")
	if _initial_world_birth_data == null:
		var opened: Dictionary = candidate.open_site(starting_site)
		if not opened.ok: return opened
		if not opened.get("created", false) or not opened.get("interactive", true) or opened.data.site.is_empty():
			return Runtime.fail("NO_BIRTH_GROUND", "新世界須從真正全新的合法陸地落腳")
		var birth: Dictionary
		var author: Dictionary = candidate.source.author_initial_context()
		if not author.is_empty():
			var start: Vector2i = Vector2i(int(author.start.cell[0]), int(author.start.cell[1]))
			opened.data.site["player_cell"] = opened.data.index(start)
		if not author.is_empty() and author.start.mode == "existing_person":
			var people: Dictionary = RegionTravel._body_records(opened.data.site)
			if not people.has(int(author.start.person_id)): return Runtime.fail("NO_TARGET")
			var person: Dictionary = people[int(author.start.person_id)]
			if not RegionTravel._able(person) or not RegionSaveSlot._initial_site_same(person.get("cell"), author.start.cell): return Runtime.fail("NO_BIRTH_GROUND")
			opened.data.site["controlled_person_id"] = int(author.start.person_id)
			birth = Runtime.ok("", {"data": opened.data})
		elif initial_scenario_id.is_empty():
			birth = lab.prepare_fresh_initial_population(opened.data)
			# P4 S5c: author resident rows, fresh branch only (never restore, never the scenario branch).
			if birth.ok: birth = lab.prepare_initial_resident_roster(birth.data)
		else:
			# Same original Slot has already frozen/validated this policy.
			var policy: Dictionary = preload("res://scripts/terrain_lab/site_technology_policy.gd").candidate(candidate.pin)
			if not policy.ok: return policy
			birth = lab.prepare_initial_artisan_birth(opened.data, initial_scenario_id, policy.policy.categories)
		if not birth.ok: return birth
		# Keep this exact unpublished original candidate through SAVE_IO retries.
		# It is never a second saved body and never captures the previous world.
		# P5C-S3: populate authored companions with the original roster rule, ids continuing from the start.
		var companions: Dictionary = _author_companion_population(candidate, birth.data)
		if not companions.ok: return companions
		_initial_companion_births = companions.births
		_initial_world_birth_data = birth.data
	for companion_site: Vector2i in _initial_companion_births:
		var supplied: Dictionary = candidate.set_companion_birth(companion_site, _initial_companion_births[companion_site])
		if not supplied.ok: return supplied
	return candidate.prepare_initial_site(_initial_world_birth_data)


# Original resident births use the pending World allocator; Site counters are mirrors only.
func _author_companion_population(candidate: RegionSaveSlot, start_data: TerrainData) -> Dictionary:
	var births: Dictionary = {}
	for companion: Vector2i in candidate.initial_companion_sites():
		var projected: Dictionary = candidate.source.project_terrain(companion, "author_initial")
		if not projected.ok: return projected
		var data: TerrainData = projected.data
		var rows: Array = data.site.get("residents", [])
		if data.site.is_empty() or rows.is_empty(): continue
		candidate.attach_person_allocator(data)
		var populated: Dictionary = lab.prepare_initial_resident_roster(data)
		if not populated.ok: return populated
		births[companion] = populated.data
	var next_id: int = int(candidate.person_allocator_view().get("next_person_id", start_data.site.get("next_person_id", 1)))
	start_data.site["next_person_id"] = next_id
	for companion: Vector2i in births: births[companion].site["next_person_id"] = next_id
	return {"ok": true, "births": births}

func _initial_creation_appearance(source: Dictionary) -> Dictionary:
	var result := {}
	for key: String in ["body", "face", "hair", "hair_dye", "hair_dyed", "name", "combat_ability", "command_abilities", "personality"]:
		if source.has(key): result[key] = source[key]
	return result

# Original resume_region_operation(), "world" match anchor replacement:
# result = open_fixed_world(str(request.manifest), str(request.world_id),
#     str(request.slot_id), request.site, bool(request.create_new),
#     str(request.get("initial_scenario_id", "")))
# Keep its existing _settle_boot_request(result) and other operation kinds.

# Original enter_requested_world(request), single call anchor replacement:
# var result := open_fixed_world(str(request.manifest), str(request.world_id),
#     str(request.slot_id), Vector2i(request.site), bool(request.create_new),
#     str(request.get("initial_scenario_id", "")))
# Keep the original _boot_request copy, settle, UI status and return.

# Original _settle_boot_request(result), apply-created-character anchor:
# var appearance: Dictionary = _initial_creation_appearance(request.character)
# var applied := apply_created_character(appearance) if bool(request.get("create_new", false)) else Runtime.fail("INVALID_INITIAL_SCENARIO")
# Keep its existing failure/menu and successful _record_world behavior.
# Existing apply_created_character() remains the original validator/appearance
# restore/save owner; only MAIN_MENU_PLAN creation fields enter, never old hp/faction/technology/items.


func begin_nation_administration(nation_id: String, order_id: String, binding: String) -> Dictionary:
	return person_actions.begin_nation_administration(int(lab.controlled_person_id()), nation_id, order_id, binding)


func begin_nation_funded_course(nation_id: String, order_id: String, student_id: int) -> Dictionary:
	return equipment_orders.begin_funded_course(int(lab.controlled_person_id()), nation_id, order_id, student_id)

# Authoritative geometry source projection for Runtime's original paid request.
# Calling this never pays, creates a feature or assigns an automatic worker.


func nation_technology_phase_source(token: Dictionary, order_id: String) -> Dictionary:
	return person_actions.nation_research_source_candidate(token, order_id)

# Original Runtime completion preflight calls this while its SAME true paid
# target/ledger and prospective products remain available; publish after ALL
# original product/Scope/Native candidates pass, in the original no-yield tail.


func prepare_nation_technology_output(token: Dictionary, event: Dictionary) -> Dictionary:
	if token.get("scope") != "nation": return Runtime.ok("", {"operation": {}})
	if token.get("tech_id") not in ["N02", "N06", "N10", "N11"]: return Runtime.ok("", {"operation": {}})
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(str(token.get("scope_id", "")), {})
	if not equipment_orders.valid_nation_operation_record(nation.get("technology_operations"), lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var matching := ""
	for order_id: String in nation.technology_operations.get("public_orders", {}):
		var order: Dictionary = nation.technology_operations.public_orders[order_id]
		if int(order.project_id) == int(token.get("project_id", -1)) and order.tech_id == token.get("tech_id"):
			if not matching.is_empty(): return Runtime.fail("REPLAY")
			matching = order_id
	if matching.is_empty(): return Runtime.fail("NO_TARGET")
	if str(token.get("binding", "")) not in ["road_build", "house_build", "ballista_build", "iron_armor"]: return Runtime.ok("", {"operation": {}})
	var prepared := equipment_orders.prepare_public_owner_receipt(str(token.scope_id), matching, str(token.binding), str(token.target_id), str(event.get("id", "")))
	if not prepared.ok: return prepared
	return Runtime.ok("", {"operation": prepared})


func publish_nation_technology_output(prepared: Dictionary) -> void:
	if not prepared.operation.is_empty(): equipment_orders.publish_public_owner_receipt(prepared.operation)


func _open_farm_trial_protocol() -> void:
	if _existing_dialog("farm_trial_protocol", "current"): return
	var data_owner: TerrainData = lab.terrain
	var site_owner: Dictionary = data_owner.site
	var requester: int = int(lab.controlled_person_id())
	var selected_key: String = feature_key
	var selected_feature: Dictionary = site_owner.get("features", {}).get(selected_key, {})
	var dialog := Window.new()
	dialog.title = "原農事 · 兩田各一個真作物批次"
	dialog.size = Vector2i(620, 440)
	dialog.close_requested.connect(dialog.queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_label(column,"明選兩田、原作物和服務格；原人原工序各完成一次付料收穫就停該田工作區。需另沿原派工入口安排這位真人。",16)
	var operator := _options(column,[],"FarmTrialOriginalPerson")
	for person: Dictionary in lab._siege_people():
		operator.add_item("原人 #%d" % int(person.id))
		operator.set_item_metadata(operator.item_count-1,int(person.id))
		if int(person.id)==requester: operator.select(operator.item_count-1)
	var choices: Array[OptionButton] = [_options(column,[],"FarmTrialControlPlot"),_options(column,[],"FarmTrialComparisonPlot")]
	var refs := {}
	for key: String in site_owner.get("features",{}):
		var feature: Dictionary = site_owner.features[key]
		if str(feature.get("kind","")) not in Runtime.FARM_KINDS or feature.get("stage")!="complete" or int(feature.get("layout_version",0))!=1: continue
		refs[key]=feature
		for slot: Dictionary in Runtime.feature_work_slots(data_owner,feature):
			for choice: OptionButton in choices:
				choice.add_item("#%s · %s · 原服務格 %s" % [key,_building_name(feature),data_owner.cell_from_index(int(slot.cell))])
				choice.set_item_metadata(choice.item_count-1,{"feature_id":key,"work_slot":int(slot.slot),"recipe_id":str(feature.get("recipe_id",""))})
	if choices[1].item_count>1: choices[1].select(1)
	var active: bool = bool(preload("res://scripts/terrain_lab/site_technology_catalog.gd").get_node("F01").get("enabled",false))
	var status := _label(column,str(selected_feature.get("farm_trial_protocol",{}))+("" if active else "\nF01 尚未具名驗收啟用；登記入口唯讀。"),16)
	var current := func() -> bool:
		return is_same(lab.terrain,data_owner) and is_same(data_owner.site,site_owner) and int(lab.controlled_person_id())==requester
	var invoke := func(preview: bool) -> void:
		if not current.call(): show_result(Runtime.fail("STALE_SOURCE")); return
		if not bool(preload("res://scripts/terrain_lab/site_technology_catalog.gd").get_node("F01").get("enabled",false)): show_result(Runtime.fail("UNSUPPORTED")); return
		if operator.selected<0 or choices[0].selected<0 or choices[1].selected<0: show_result(Runtime.fail("NO_TARGET")); return
		var selections: Array = []
		for choice: OptionButton in choices:
			var selection: Dictionary = choice.get_item_metadata(choice.selected)
			if not is_same(site_owner.get("features",{}).get(selection.feature_id),refs.get(selection.feature_id)): show_result(Runtime.fail("STALE_SOURCE")); return
			selections.append(selection.duplicate())
		var result: Dictionary = Runtime.request_farm_trial_protocol(data_owner,requester,int(operator.get_item_metadata(operator.selected)),selections,preview)
		show_result(result)
		status.text=str(result.message)
		if result.ok and not preview: view.refresh(); _sync_building_actions()
	var row := HBoxContainer.new()
	column.add_child(row)
	var preview := _button(row,"原兩田預檢","FarmTrialPreview",func() -> void: invoke.call(true))
	var register := _button(row,"明示登記兩田單批","FarmTrialRegister",func() -> void: invoke.call(false))
	preview.disabled=not active
	register.disabled=not active
	_button(column,"解除目前所選田的試驗（先停止原派工）","FarmTrialCancel",func() -> void:
		if not current.call() or not is_same(site_owner.get("features",{}).get(selected_key),selected_feature): show_result(Runtime.fail("STALE_SOURCE")); return
		var result: Dictionary = Runtime.cancel_farm_trial_protocol(data_owner,selected_key,requester)
		show_result(result)
		status.text=str(result.message)
		if result.ok: view.refresh(); _sync_building_actions())
	_show_dialog(dialog,"farm_trial_protocol","current")

func _open_saved_survey_plan() -> void:
	var data_owner: TerrainData = lab.terrain
	var site_owner: Dictionary = data_owner.site
	var key: String = feature_key
	var feature_owner: Dictionary = site_owner.get("features", {}).get(key, {})
	var requester: int = int(lab.controlled_person_id())
	if feature_owner.get("kind") != "survey_stakes": show_result(Runtime.fail("NO_TARGET")); return
	if _existing_dialog("saved_survey", key): return
	var dialog := Window.new()
	dialog.title = "原真放樣方案 #%s" % key
	dialog.size = Vector2i(620, 330)
	dialog.close_requested.connect(dialog.queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var status := _label(column, str(feature_owner.get("survey_plan", {})), 16)
	var invoke := func(preview: bool) -> void:
		if not is_same(lab.terrain, data_owner) or not is_same(data_owner.site, site_owner) or not is_same(site_owner.get("features", {}).get(key), feature_owner) or int(lab.controlled_person_id()) != requester:
			show_result(Runtime.fail("STALE_SOURCE")); return
		var result: Dictionary = Runtime.request_build_from_survey(data_owner, key, requester, reserves_cell, preview)
		show_result(result)
		status.text = str(result.message)
		if result.ok and not preview: view.refresh()
	_button(column, "重驗當前完整原建設預覽／材料", "SavedSurveyPreview", func() -> void: invoke.call(true))
	_button(column, "沿原建造入口實際備料施工", "SavedSurveyBuild", func() -> void: invoke.call(false))
	_show_dialog(dialog, "saved_survey", key)

func _open_survey_plan() -> void:
	if _existing_dialog("survey_plan", "draft"): return
	var data_owner: TerrainData = lab.terrain
	var site_owner: Dictionary = data_owner.site
	var requester: int = int(lab.controlled_person_id())
	var plan := {"kind": _building_kind(), "cells": build_cells.duplicate(), "options": _building_options()}
	if building_resize or not Runtime.valid_survey_plan(data_owner, plan): show_result(Runtime.fail("INVALID", "先在原建設窗完成新的真占地預覽")); return
	var dialog := Window.new()
	dialog.title = "原建設方案 · 真双樁放樣"
	dialog.size = Vector2i(660, 430)
	dialog.close_requested.connect(dialog.queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_label(column, "沿目前完整原建設預覽，在邊界外明選兩個相鄰真樁；木材2、原120秒施工。日後使用方案仍重驗原地形、占用及完整建造材料。", 16)
	var operator := _options(column, [], "SurveyOriginalPerson")
	for person: Dictionary in lab._siege_people():
		operator.add_item("原人 #%d" % int(person.id))
		operator.set_item_metadata(operator.item_count - 1, int(person.id))
		if int(person.id) == requester: operator.select(operator.item_count - 1)
	var marks := _options(column, [], "SurveyActualBoundaryMarks")
	var outside := {}
	for index: int in plan.cells:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var cell: Vector2i = data_owner.cell_from_index(index) + direction
			if data_owner.contains(cell) and not plan.cells.has(data_owner.index(cell)): outside[data_owner.index(cell)] = true
	for first: int in outside:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var next: Vector2i = data_owner.cell_from_index(first) + direction
			if not data_owner.contains(next) or not outside.has(data_owner.index(next)): continue
			var pair: Array[int] = [first, data_owner.index(next)]
			marks.add_item("真格 %s、%s" % [data_owner.cell_from_index(first), next])
			marks.set_item_metadata(marks.item_count - 1, pair)
	var active: bool = bool(preload("res://scripts/terrain_lab/site_technology_catalog.gd").get_node("F09").get("enabled", false))
	_label(column, "原方案 %s · %d格%s" % [str(plan.kind), plan.cells.size(), "" if active else "\nF09 尚未具名驗收啟用；放樣入口唯讀。"], 16)
	var invoke := func(preview: bool) -> void:
		if not is_same(lab.terrain, data_owner) or not is_same(data_owner.site, site_owner) or int(lab.controlled_person_id()) != requester \
			or build_cells != plan.cells or _building_kind() != plan.kind or _building_options() != plan.options: show_result(Runtime.fail("STALE_SOURCE")); return
		if not bool(preload("res://scripts/terrain_lab/site_technology_catalog.gd").get_node("F09").get("enabled", false)): show_result(Runtime.fail("UNSUPPORTED")); return
		if operator.selected < 0 or marks.selected < 0: show_result(Runtime.fail("NO_TARGET")); return
		var cells: Array[int] = []
		cells.assign(marks.get_item_metadata(marks.selected))
		var result: Dictionary = Runtime.request_survey_plan(data_owner, requester, int(operator.get_item_metadata(operator.selected)), cells, plan, reserves_cell, preview)
		show_result(result)
		if result.ok and not preview: view.refresh()
	var row := HBoxContainer.new()
	column.add_child(row)
	var preview := _button(row, "真双樁預檢", "SurveyPreview", func() -> void: invoke.call(true))
	var build := _button(row, "真放樣施工（木材2）", "SurveyBuild", func() -> void: invoke.call(false))
	preview.disabled = not active
	build.disabled = not active
	_show_dialog(dialog, "survey_plan", "draft")

func _open_family_construction_method() -> void:
	var data_owner: TerrainData = lab.terrain
	var site_owner: Dictionary = data_owner.site
	var key: String = feature_key
	var feature_owner: Dictionary = site_owner.get("features", {}).get(key, {})
	var requester: int = int(lab.controlled_person_id())
	if feature_owner.is_empty(): show_result(Runtime.fail("NO_TARGET")); return
	if _existing_dialog("construction_method", key): return
	var dialog := Window.new()
	dialog.title = "原施工 · 丈量接榫工法"
	dialog.size = Vector2i(540, 340)
	dialog.close_requested.connect(dialog.queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_label(column, "只改所選學會者的新施工工作段為原90%時間；原材料、占地、工時基準和修理不變。仍須沿原派工入口安排真人。", 16)
	var operator := _options(column, [], "ConstructionMethodOriginalPerson")
	for person: Dictionary in lab._siege_people():
		operator.add_item("原人 #%d" % int(person.id))
		operator.set_item_metadata(operator.item_count - 1, int(person.id))
		if int(person.id) == requester: operator.select(operator.item_count - 1)
	var status := _label(column, "", 16)
	var active := bool(preload("res://scripts/terrain_lab/site_technology_catalog.gd").get_node("F10").get("enabled", false))
	status.text = str(feature_owner.get("pending_build", feature_owner).get("construction_method", {})) + ("" if active else "\nF10 尚未具名驗收啟用；此處唯讀。")
	var invoke := func(improved: bool, preview: bool) -> void:
		if not is_same(lab.terrain, data_owner) or not is_same(lab.terrain.site, site_owner) or not is_same(site_owner.get("features", {}).get(key), feature_owner) or int(lab.controlled_person_id()) != requester:
			show_result(Runtime.fail("STALE_SOURCE")); return
		if operator.selected < 0: show_result(Runtime.fail("NO_TARGET")); return
		if improved and not bool(preload("res://scripts/terrain_lab/site_technology_catalog.gd").get_node("F10").get("enabled", false)):
			show_result(Runtime.fail("UNSUPPORTED", "F10 尚未具名驗收啟用")); return
		var result: Dictionary = Runtime.request_family_construction_method(data_owner, key, requester, int(operator.get_item_metadata(operator.selected)), improved, preview)
		show_result(result)
		status.text = str(feature_owner.get("pending_build", feature_owner).get("construction_method", {}))
		if result.ok and not preview: view.refresh(); _sync_building_actions()
	var row := HBoxContainer.new()
	column.add_child(row)
	var preview := _button(row, "預檢所選工法", "PreviewConstructionMethod", func() -> void: invoke.call(true, true))
	var apply := _button(row, "明選丈量接榫", "SelectConstructionMethod", func() -> void: invoke.call(true, false))
	preview.disabled = not active
	apply.disabled = not active
	_button(column, "恢復原普通施工（未開工才可）", "ResetConstructionMethod", func() -> void: invoke.call(false, false))
	_show_dialog(dialog, "construction_method", key)

func _refresh_siege_ammo_choices(form: Dictionary, vehicle: Dictionary) -> void:
	if not form.has("siege_ammo"): return
	var choice: OptionButton = form.siege_ammo
	var previous: String = str(choice.get_item_metadata(choice.selected)) if choice.selected >= 0 else ""
	if not is_same(form.get("siege_ammo_vehicle"), vehicle): previous = ""
	choice.clear()
	form["siege_ammo_vehicle"] = vehicle
	var ordinary: String = str(Runtime.SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {}).get("ammo", ""))
	choice.add_item("原器具彈種 " + ordinary if not ordinary.is_empty() else "此器具不使用彈藥")
	choice.set_item_metadata(0, ordinary)
	if Runtime.siege_ammo_valid(str(vehicle.get("kind", "")), "fire_pot"):
		choice.add_item("火罐（原實物；在位本人須已學 F15）")
		choice.set_item_metadata(1, "fire_pot")
		if previous == "fire_pot": choice.select(1)
	choice.disabled = ordinary.is_empty()

func _siege_ammo_choice(form: Dictionary, vehicle: Dictionary) -> Dictionary:
	var ordinary: String = str(Runtime.SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {}).get("ammo", ""))
	if not form.has("siege_ammo"): return Runtime.ok("", {"ammo": ordinary})
	if not is_same(form.get("siege_ammo_vehicle"), vehicle): return Runtime.fail("STALE_SOURCE", "原器具已變更，請重查彈種")
	var choice: OptionButton = form.siege_ammo
	if choice.selected < 0: return Runtime.fail("NO_TARGET", "請明示原器具彈種")
	var value: Variant = choice.get_item_metadata(choice.selected)
	if not value is String or not ordinary.is_empty() and not Runtime.siege_ammo_valid(str(vehicle.kind), value): return Runtime.fail("INVALID")
	return Runtime.ok("", {"ammo": value})

func _install_irrigation_controls(column: VBoxContainer) -> void:
	column.add_child(HSeparator.new())
	_label(column, "灌排渠道 · 原格路徑／同源有限延伸", 18)
	var form := {"signature": ""}
	column.set_meta(&"irrigation_form", form)
	form["status"] = _label(column, "", 14)
	form["source"] = _options(column, [], "IrrigationSource")
	form["upstream"] = _options(column, [], "IrrigationUpstream")
	form.source.item_selected.connect(func(_index: int) -> void: form["signature"] = ""; _refresh_irrigation_controls())
	var row := HBoxContainer.new()
	column.add_child(row)
	form["add"] = _button(row, "加入目前真格", "IrrigationAppendCell", func() -> void: show_result(_irrigation_add_selected()); _refresh_irrigation_controls())
	_button(row, "清空渠道草稿", "IrrigationClearCells", func() -> void: build_cells.clear(); _refresh_irrigation_controls())
	row = HBoxContainer.new()
	column.add_child(row)
	form["preview"] = _button(row, "预檢渠道", "IrrigationPreview", func() -> void: _irrigation_build_selected(true))
	form["begin"] = _button(row, "本人於原工位開始", "IrrigationBegin", func() -> void: _irrigation_build_selected(false))
	form["resume"] = _button(row, "接續所選已付渠道", "IrrigationResume", func() -> void:
		show_result(Runtime.resume_irrigation_channel(lab.terrain, int(lab.controlled_person_id()), feature_key)); view.refresh())
	form["stop"] = _button(row, "本人停工（保留物資／進度）", "IrrigationStop", func() -> void:
		var identity := int(lab.controlled_person_id())
		var job: Dictionary = person_actions._jobs.get(person_actions._job_key_for(identity), {})
		if job.get("kind") == "technology_feature" and job.get("operation_selector", {}).has("irrigation"):
			show_result(person_actions.cancel(identity))
		else: show_result(Runtime.fail("NO_TARGET", "目前本人沒有普通渠道作業；科技試作沿原研習停止入口")))
	_refresh_irrigation_controls()

func _irrigation_build_selected(preview: bool) -> void:
	if _building_kind() != "irrigation_channel" or build_cells.is_empty(): show_result(Runtime.fail("NO_TARGET", "先選原渠道種類及完整真格路徑")); return
	var config := _irrigation_options()
	var result := Runtime.irrigation_channel_draft(lab.terrain, build_cells, _building_options(), reserves_cell) if preview else Runtime.begin_irrigation_channel(lab.terrain, int(lab.controlled_person_id()), str(config.get("source_feature_id", "")), str(config.get("upstream_feature_id", "")), build_cells, _building_options(), false, reserves_cell)
	if result.ok and not preview:
		feature_key = str(result.feature)
		_cancel_building_draft()
		view.refresh()
	show_result(result)

func reuse_selected_settlement_blueprint(plan_id: String) -> Dictionary:
	# The original selected map cell is a real anchor; Runtime reconstructs the
	# full saved geometry and applies all current original paid-build guards.
	return SiteRuntime.reuse_settlement_blueprint(lab.terrain, int(person_actions._technology_controlled()), plan_id, selected)

func save_selected_settlement_blueprint(name: String, preview: bool = false) -> Dictionary:
	return SiteRuntime.save_settlement_blueprint(lab.terrain, int(person_actions._technology_controlled()), feature_key, name, preview)

func begin_settlement_defense_work(order_id: String, preview: bool = false) -> Dictionary:
	return SiteRuntime.begin_settlement_defense_step(lab.terrain, int(person_actions._technology_controlled()), order_id, preview)

func request_settlement_defense_work(steps: Array, person_ids: Array, cap: Dictionary, preview: bool = false) -> Dictionary:
	# IDs identify real selected original people. They grant nothing; the manual
	# owner verifies its current head plus actual team.work decision for all IDs.
	return SiteRuntime.request_settlement_defense_order(lab.terrain, int(person_actions._technology_controlled()), steps, person_ids, cap, preview)

func _nation_ui_command(nation_id: String, action: String, selected_values: Dictionary) -> Dictionary:
	var requester := int(lab.controlled_person_id())
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty(): return Runtime.fail("NO_TARGET")
	var ops: Dictionary = nation.get("technology_operations", {})
	if not ops.is_empty() and not EquipmentOrders.valid_nation_operation_record(ops, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var s: Dictionary = selected_values
	var order_id := str(s.get("order", ""))
	var order: Dictionary = ops.get("public_orders", {}).get(order_id, {})
	var military: Dictionary = ops.get("orders", {}).get(order_id, {})
	var resources: Dictionary = s.get("resources", {})
	var people: Array[int] = []
	for identity: Variant in s.get("people", []): people.append(int(identity))
	match action:
		"publish_spec":
			var key := str(s.get("key", "")) if not str(s.get("key", "")).is_empty() else str(s.get("spec", ""))
			var standard: Dictionary = nation.get("standards", {}).get(str(s.get("standard", "")), {})
			var requirements := {}
			if int(s.get("item_batch", 0)) > 0:
				if standard.is_empty(): return Runtime.fail("NO_TARGET", "實物規格須選原標準與真替代定義")
				for slot: String in standard.slots:
					var entry: Dictionary = standard.slots[slot]
					requirements[slot] = {"definition": str(entry.definition), "alternatives": entry.get("alternatives", []).duplicate(), "batch": int(s.item_batch), "total": int(s.item_total)}
			return equipment_orders.publish_procurement_spec(requester, nation_id, key, str(s.get("name", "")), str(s.get("reserve", "")), s.resource_limits, requirements, int(ops.get("specs", {}).get(key, {}).get("revision", 0)))
		"deliver_spec":
			var key := str(s.get("spec", ""))
			var spec: Dictionary = ops.get("specs", {}).get(key, {})
			if spec.is_empty(): return Runtime.fail("NO_TARGET")
			return equipment_orders.accept_procurement_delivery(requester, nation_id, key, resources, s.get("items", []), _nation_ui_version("person:" + str(requester)), _nation_ui_version("feature:" + str(spec.destination_feature_id)), "manual_delivery_" + str(spec.receipts.size() + 1))
		"certify":
			var key := str(s.get("key", "")) if not str(s.get("key", "")).is_empty() else str(s.get("certificate", ""))
			if not EquipmentOrders.Technology.integer(s.get("receipt"), 1): return Runtime.fail("NO_RECEIPT")
			return equipment_orders.certify_workshop(requester, nation_id, key, str(s.get("host", "")), str(s.get("industry", "")), int(s.receipt), int(ops.get("certificates", {}).get(key, {}).get("revision", 0)))
		"administration_spec": return person_actions.begin_nation_administration(requester, nation_id, "procurement:" + str(s.get("spec", "")), "procurement")
		"administration_certificate": return person_actions.begin_nation_administration(requester, nation_id, "certificate:" + str(s.get("certificate", "")), "workshop_certificate")
		"request_military": return equipment_orders.request_military_production_order(requester, nation_id, str(s.get("certificate", "")), int(s.get("operator", 0)), int(s.get("recipient", 0)), str(s.get("standard", "")))
		"grant_military": return equipment_orders.authorize_military_materials(requester, nation_id, order_id, resources)
		"revoke_military_source": return equipment_orders.revoke_military_materials(requester, nation_id, order_id)
		"supply_military":
			if military.is_empty(): return Runtime.fail("NO_TARGET")
			return equipment_orders.supply_military_production(requester, nation_id, order_id, resources, _nation_ui_version("person:" + str(requester)), _nation_ui_version("feature:" + str(military.feature_id)))
		"begin_military":
			return Runtime.begin_nation_military_operation(lab.terrain, nation_id, order_id)
		"issue_military": return equipment_orders.begin_military_issue(requester, nation_id, order_id)
		"renew_military": return equipment_orders.renew_military_production_order(requester, nation_id, order_id, int(military.get("revision", -1)))
		"labor": return equipment_orders.register_nation_labor(requester, nation_id, people)
		"aid": return equipment_orders.request_aid_order(requester, nation_id, str(s.get("reserve", "")), people)
		"public_work": return equipment_orders.request_public_work_order(requester, nation_id, "house", str(s.get("labor", "")), people, str(s.get("reserve", "")))
		"course": return equipment_orders.request_funded_course(requester, nation_id, str(s.get("reserve", "")), int(s.get("teacher", 0)), people, str(s.get("skill", "")))
		"lesson": return equipment_orders.begin_funded_course(requester, nation_id, order_id, int(s.get("student", 0)))
		"tax": return equipment_orders.declare_tax_source(requester, nation_id, str(s.get("reserve", "")), int(s.get("recipient", 0)))
		"grant_source": return equipment_orders.authorize_public_source(requester, nation_id, order_id, resources)
		"revoke_source": return equipment_orders.revoke_public_source(requester, nation_id, order_id)
		"fund":
			if order.is_empty() or not order.payload.has("reserve_feature_id"): return Runtime.fail("NO_TARGET")
			return equipment_orders.fund_public_order(requester, nation_id, order_id, resources, _nation_ui_version("person:" + str(requester)), _nation_ui_version("feature:" + str(order.payload.reserve_feature_id)))
		"share":
			if order.is_empty() or not order.payload.has("reserve_feature_id"): return Runtime.fail("NO_TARGET")
			var recipient := int(s.get("recipient", 0))
			return equipment_orders.deliver_public_share(requester, nation_id, order_id, recipient, _nation_ui_version("feature:" + str(order.payload.reserve_feature_id)), _nation_ui_version("person:" + str(recipient)))
		"administration":
			if order.is_empty(): return Runtime.fail("NO_TARGET")
			var binding: String = {"N02": "labor_register", "N03": "aid_order", "N09": "tax", "N10": "mandate", "N11": "arsenal", "N12": "fleet"}.get(str(order.tech_id), "")
			return person_actions.begin_nation_administration(requester, nation_id, order_id, str(binding))
		"mandate", "renew_mandate":
			var now := equipment_orders._original_world_seconds()
			if now < 0.0: return Runtime.fail("NO_WORLD_CLOCK")
			var expiry := now + float(s.get("minutes", 0)) * 60.0
			return equipment_orders.grant_settlement_mandate(requester, nation_id, int(s.get("local", 0)), expiry) if action == "mandate" else equipment_orders.renew_settlement_mandate(requester, nation_id, order_id, int(order.get("revision", -1)), int(s.get("local", 0)), expiry)
		"arsenal": return equipment_orders.request_arsenal_order(requester, nation_id, str(s.get("arsenal_route", "")), str(s.get("host", "")), int(s.get("operator", 0)), str(s.get("reserve", "")))
		"begin_arsenal":
			if order.is_empty(): return Runtime.fail("NO_TARGET")
			var geometry := {}
			if order.payload.route == "siege":
				var person: Dictionary = person_actions._person(int(order.payload.operator_id), false)
				var team: Variant = person_actions._technology_team(person)
				if team == null or not s.get("facing") is Vector2i: return Runtime.fail("NO_TEAM")
				geometry = {"anchor": Vector2i(int(s.x), int(s.y)), "facing": s.facing, "team_id": int(team.team_id)}
			return begin_nation_arsenal(nation_id, order_id, geometry)
		"construction":
			if order.is_empty(): return Runtime.fail("NO_TARGET")
			var cells: Array[int] = []
			for y: int in range(int(s.get("depth", 1))):
				for x: int in range(int(s.get("width", 1))):
					var cell := Vector2i(int(s.x) + x, int(s.y) + y)
					if not lab.terrain.contains(cell): return Runtime.fail("TERRAIN")
					cells.append(lab.terrain.index(cell))
			return equipment_orders.begin_nation_construction(requester, nation_id, order_id, cells)
		"route":
			var route: Variant = s.get("route")
			if not route is Dictionary: return Runtime.fail("NO_ROUTE", "請選原 Region 已驗路線")
			return equipment_orders.authorize_public_transport_route(requester, nation_id, str(s.get("reserve", "")), str(route.get("route_id", "")), str(route.get("destination_site_id", "")), str(route.get("destination_holder", "")), str(route.get("vehicle_id", "")), int(route.get("driver_id", 0)))
		"load_route":
			if order.is_empty(): return Runtime.fail("NO_TARGET")
			return equipment_orders.load_public_route(requester, nation_id, order_id, _nation_ui_version("feature:" + str(order.payload.reserve_feature_id)), _nation_ui_version(str(order.payload.vehicle_id)))
		"begin_route": return equipment_orders.begin_public_route(requester, nation_id, order_id)
		"fleet":
			var ship_ids: Array[String] = []
			for identity: Variant in s.get("ships", []): ship_ids.append(str(identity))
			return equipment_orders.request_fleet_order(requester, nation_id, str(s.get("corps", "")), ship_ids)
		"command_ship": return equipment_orders.command_fleet_ship(requester, nation_id, order_id, str(s.get("ship", "")))
		"accept_ship": return equipment_orders.accept_fleet_ship_stop(requester, nation_id, order_id, str(s.get("ship", "")))
		"renew": return equipment_orders.renew_public_operation(requester, nation_id, order_id, int(order.get("revision", -1)))
		"revoke":
			if not military.is_empty(): return equipment_orders.cancel_military_production_order(requester, nation_id, order_id, int(military.revision), str(s.get("reason", "")))
			if s.has("certificate"): return equipment_orders.revoke_workshop_certificate(requester, nation_id, str(s.certificate), int(ops.get("certificates", {}).get(str(s.certificate), {}).get("revision", -1)), str(s.get("reason", "")))
			return equipment_orders.revoke_public_operation(requester, nation_id, order_id, int(order.get("revision", -1)), str(s.get("reason", "")))
	return Runtime.fail("INVALID")

func _nation_ui_submit(form: Dictionary, action: String) -> void:
	if lab.terrain != form.data or not is_same(lab.terrain.site, form.site) or lab.controlled_person_id() != int(form.requester):
		form.status.text = "原 Site 或受控人物已變更，請重開；未提交。"
		return
	var nation_id := str(form.nation_choice.get_item_metadata(form.nation_choice.selected))
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not is_same(nation, form.nation):
		form.status.text = "原國家已變更，請重查。"
		return
	var selection := _nation_ui_selection(form)
	var result := _nation_ui_command(nation_id, action, selection)
	show_result(result)
	form.status.text = "%s：%s" % [str(result.get("code", "OK")), str(result.get("message", ""))]
	if result.ok: form.status.text += "（重查原工單以查看新狀態）"

func _open_nation_operations(nation_id: String = "", host: Window = null, tech_id: String = "") -> void:
	if _existing_dialog("nation_operations", nation_id, host): return
	var original_data: TerrainData = lab.terrain
	var original_control: int = lab.controlled_person_id()
	var dialog := AcceptDialog.new()
	dialog.name = "NationOperationsDialog"
	dialog.title = "國家制度與具名公務"
	dialog.min_size = Vector2i(820, 640)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(790, 560)
	dialog.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_label(column, "選擇原國家與本次操作。供料取自目前受控人物；同意、工位、期限與實物均由原入口重新核對。", 15)
	var nations := _options(column, ["選擇原國家"], "NationOperationNation")
	nations.set_item_metadata(0, "")
	for key: String in original_data.site.get("equipment_nations", {}):
		nations.add_item(key)
		nations.set_item_metadata(nations.item_count - 1, key)
		if key == nation_id: nations.select(nations.item_count - 1)
	var technology := _options(column, [], "NationOperationTechnology")
	for index: int in range(1, 13):
		var key := "N%02d" % index
		technology.add_item("%s · %s" % [key, str(SiteTechnologyCatalog.get_node(key).get("name", key))])
		technology.set_item_metadata(technology.item_count - 1, key)
		if key == tech_id: technology.select(technology.item_count - 1)
	var body := VBoxContainer.new()
	column.add_child(body)
	var status := _label(column, "", 15)
	var form := {"data": original_data, "site": original_data.site, "requester": original_control,
		"nation_choice": nations, "technology": technology, "body": body, "status": status, "dialog": dialog,
		"controls": {}, "resources": {}, "nation": {}}
	nations.item_selected.connect(func(_index: int) -> void: _nation_ui_render(form))
	technology.item_selected.connect(func(_index: int) -> void: _nation_ui_render(form))
	_button(column, "重查原工單與現場", "RefreshNationOperations", func() -> void: _nation_ui_render(form))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_nation_ui_render(form)
	_show_dialog(dialog, "nation_operations", nation_id, host)

func prepare_gd_mesh_supply_window(seconds: float) -> Dictionary:
	if _crowd_active() or not is_finite(seconds) or seconds <= 0.0: return Runtime.fail("CLOCK_NOT_READY")
	var rows: Array[Dictionary] = []
	for owner_id: String in lab.terrain.site.get("person_supply", {}):
		var state: Dictionary = lab.terrain.site.person_supply[owner_id]
		if state.is_empty(): continue
		var person: Dictionary = _supply_person(int(owner_id))
		if person.is_empty(): return Runtime.fail("STALE_SUPPLY_OWNER")
		var members: Dictionary = captivity_supply.personal_members_id(int(owner_id))
		rows.append({"kind": "personal", "owner_id": owner_id, "state": state, "members": members,
			"stock": person.cargo, "holder": person.holder, "context": {}, "reader": _gd_mesh_supply_reader(members), "seconds": seconds})
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		var entry: Dictionary = _supply_entry(team)
		if entry.is_empty(): continue
		var members: Dictionary = _team_members(team)
		var reader: Callable = _gd_mesh_supply_reader(members)
		var context := {"hot_read": reader, "safe": _team_safe(team, members), "stopped": _team_stopped(team, true)}
		if int(entry.version) == 3: context["food_locations"] = ship_food_locations(team, members)
		rows.append({"kind": "team", "owner": team, "entry": entry, "state": entry.sustain, "members": members,
			"stock": _supply_stock(entry), "context": context, "reader": reader, "seconds": seconds})
	for row: Dictionary in rows:
		# Source membership is original. Snapshot only Supply's own finite
		# scalar state/stock, as its existing Native candidate already does.
		var state: Dictionary = row.state.duplicate(true)
		var stock: Dictionary = row.stock.duplicate(true)
		var sampled: Dictionary = _gd_mesh_supply_life(row.members, row.reader)
		if not sampled.ok: return sampled
		var life: Dictionary = sampled.life
		var context: Dictionary = row.context.duplicate(false)
		context["hot_read"] = func(identity: int, field: StringName) -> Variant:
			return life[identity][String(field)] if life[identity].has(String(field)) else row.members[identity].get(String(field))
		context["pending_hp"] = {}
		var forecast: Dictionary = Sustain.advance_to(state, row.members, stock, float(state.at) + seconds, context)
		if not forecast.ok: return Runtime.fail("SUPPLY_PREFLIGHT", str(forecast.get("message", "")))
		if float(forecast.consumed_rations) > 0.0 or not forecast.damage.is_empty(): return Runtime.fail("CONTACT_SUPPLY_COST_NOT_PREPARED")
		# Source is fixed; real contact may only reduce the living population.
		# No old-snapshot ration debit is made on the post-contact membership.
		row["state_values"] = row.state.duplicate(true)
		row["stock_values"] = row.stock.duplicate(true)
	return Runtime.ok("原供养本窗无餐费/饥饿伤害；同源已核", {"owner": self, "rows": rows, "seconds": seconds, "elapsed": 0.0})

func prepare_gd_contact_training_window(supply: Dictionary, requests: Array, planned: Dictionary) -> Dictionary:
	if supply.get("owner") != self or not planned.get("ok", false) or not is_same(requests, lab._shared_work_requests) \
		or not is_same(planned, lab._shared_work_plan) or float(planned.get("seconds", -1.0)) != float(supply.get("seconds", 0.0)): return Runtime.fail("CLOCK_NOT_READY")
	var rows: Array[Dictionary] = []
	var people := {}
	for row: Dictionary in supply.rows:
		if row.kind != "team" or not bool(row.entry.get("training_order", false)): continue
		var field: Dictionary = TrainingGround.inspect(self, int(row.owner.team_id), str(row.entry.get("training_feature_id", "")))
		var feature_id: String = str(row.entry.get("training_feature_id", ""))
		var entry := {"supply_row": row, "field": field, "feature_id": feature_id,
			"feature": lab.terrain.site.features.get(feature_id, {}), "requester": int(row.entry.training_requester), "eligible": field.get("eligible_ids", [])}
		rows.append(entry)
		for request: Dictionary in requests:
			if request.get("provider") != "training": continue
			if not request.get("participants") is Array or request.participants.size() != 1: return Runtime.fail("INVALID_OWNER")
			var participant: Dictionary = request.participants[0]
			var identity: int = int(participant.get("person_id", 0))
			if not row.members.has(identity): continue
			var person: Dictionary = person_actions._person(identity)
			if people.has(identity) or not field.ok or not entry.eligible.has(identity) or person.is_empty() \
				or not is_same(person.body, participant.get("body")) or _person_has_duty(identity): return Runtime.fail("STALE_TRAINING_SOURCE")
			people[identity] = {"row": entry, "request": request, "participant": participant, "owner": person.owner,
				"unit": int(person.unit), "body": person.body, "cell": person.cell, "hit": int(person.hit)}
		# Original Sustain checks the real roster/numbers before any work/body cost.
		# work_plan branch is pure: it does not charge or recover a native/GD pool.
		var checked: Dictionary = Sustain.train(float(row.owner.training), row.members, entry.eligible,
			float(supply.seconds), _gd_contact_training_context(entry, planned))
		if not checked.ok: return Runtime.fail("TRAINING_PREFLIGHT", str(checked.get("message", "")))
	for request: Dictionary in requests:
		if request.get("provider") == "training" and (request.get("participants", []).size() != 1 \
			or not people.has(int(request.participants[0].get("person_id", 0)))): return Runtime.fail("STALE_TRAINING_SOURCE")
	supply["training"] = {"rows": rows, "people": people}
	return Runtime.ok("原校場與同人物訓練分配已核；不扣疲勞")

func _gd_contact_training_context(entry: Dictionary, planned: Dictionary) -> Dictionary:
	var row: Dictionary = entry.supply_row
	var fed: bool = not row.state.cohorts.is_empty()
	for cohort: Dictionary in row.state.cohorts: fed = fed and float(cohort.coverage) >= 1.0
	return {"ordered": bool(row.entry.get("training_order", false)), "commander": row.owner.command_eligible(row.owner.current_commander),
		"safe": bool(entry.field.get("safe", false)) and float(lab.terrain.site.get("combat_left", 0.0)) <= 0.0 and _team_safe(row.owner, row.members),
		"stopped": _team_stopped(row.owner, true), "fed": fed, "routed": bool(row.state.routed), "coach": _team_ability(row.owner, "coach"),
		"controlled_person_id": lab.controlled_person_id(), "hot_read": row.reader, "pending_hp": {},
		"training_multiplier": entry.field.get("training_multiplier", 1.0), "work_plan": planned}

func gd_contact_training_person_ready(identity: int) -> bool:
	var supply: Dictionary = lab._gd_mesh_work_point.get("supply", {})
	var held: Dictionary = supply.get("training", {}).get("people", {}).get(identity, {})
	if held.is_empty(): return false
	var entry: Dictionary = held.row
	var row: Dictionary = entry.supply_row
	var person: Dictionary = person_actions._person(identity)
	if person.is_empty() or not is_same(_supply_entry(row.owner), row.entry) or not bool(row.entry.get("training_order", false)) \
		or int(row.entry.training_requester) != int(entry.requester) or str(row.entry.training_feature_id) != entry.feature_id \
		or not is_same(lab.terrain.site.features.get(entry.feature_id), entry.feature) \
		or not Runtime.feature_usable(entry.feature, "training") or _person_has_duty(identity) \
		or person.owner != held.owner or int(person.unit) != int(held.unit) or not is_same(person.body, held.body) \
		or person.cell != held.cell or int(person.hit) != int(held.hit) or bool(person.moving) or bool(person.captive) \
		or not (person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act()): return false
	var context: Dictionary = _gd_contact_training_context(entry, lab._gd_mesh_work_point.nominal_plan)
	for condition: String in ["ordered", "commander", "safe", "stopped", "fed"]:
		if not bool(context[condition]): return false
	return not bool(context.routed)

func prepare_gd_contact_training_segment(planned: Dictionary, seconds: float) -> Dictionary:
	var point: Dictionary = lab._gd_mesh_work_point
	if point.is_empty() or not is_same(point.get("segment_plan"), planned) or not is_finite(seconds) or seconds <= 0.0 \
		or float(planned.get("seconds", -1.0)) != seconds or float(point.elapsed) + seconds > float(point.seconds) + PersonFatigue.WORK_PLAN_EPS: return Runtime.fail("CLOCK_NOT_READY")
	var supply: Dictionary = point.supply
	var entries: Array[Dictionary] = []
	for entry: Dictionary in supply.training.rows:
		var row: Dictionary = entry.supply_row
		var checked: Dictionary = Sustain.train(float(row.owner.training), row.members, entry.eligible, seconds,
			_gd_contact_training_context(entry, planned))
		if not checked.ok: return Runtime.fail("TRAINING_PREFLIGHT", str(checked.get("message", "")))
		entries.append({"entry": entry, "before": float(row.owner.training), "result": checked})
	var segment := {"owner": self, "supply": supply, "plan": planned, "seconds": seconds, "entries": entries, "published": false}
	supply["training_segment"] = segment # SAME existing point's call-local registry only.
	return Runtime.ok("", {"segment": segment})

func publish_gd_contact_training_segment(segment: Dictionary) -> void:
	assert(segment.owner == self and not segment.published and is_same(lab._gd_mesh_work_point.supply, segment.supply) \
		and is_same(segment.supply.get("training_segment"), segment) and is_same(lab._gd_mesh_work_point.get("segment_plan"), segment.plan))
	for item: Dictionary in segment.entries:
		var row: Dictionary = item.entry.supply_row
		assert(float(row.owner.training) == float(item.before))
		row.owner.training = float(item.result.training)
		for identity: int in item.result.handled_ids:
			if identity == lab.controlled_person_id(): continue
			var allocation: Dictionary = segment.plan.jobs.get("training", {}).get(str(identity), {})
			var person: Dictionary = person_actions._person(identity)
			if not person.is_empty() and (str(allocation.get("paused", "")) == "REST" or float(allocation.get("actual_seconds", 0.0)) > 0.0):
				person_actions._body_set(person, "work_resting", str(allocation.get("paused", "")) == "REST")
	segment["published"] = true
	segment.supply.erase("training_segment")

func finish_gd_contact_training_window(supply: Dictionary) -> void:
	for entry: Dictionary in supply.get("training", {}).get("rows", []):
		var row: Dictionary = entry.supply_row
		if not bool(row.entry.get("training_order", false)): continue
		var field: Dictionary = TrainingGround.inspect(self, int(row.owner.team_id), str(row.entry.get("training_feature_id", "")))
		var issuer_index: int = row.owner.index_for_identity(int(row.entry.training_requester))
		if not field.ok or issuer_index < 0 or row.owner.member_gone(issuer_index):
			TrainingGround.stop(row.entry)

func checked_work_prefix_for_task(task: Dictionary, identity: int) -> Dictionary:
	for prefix: Dictionary in owned_checked_work_prefixes():
		if int(prefix.person_id) == identity and is_same(prefix.task, task): return prefix
	return lab.checked_shared_vehicle_prefix_for_task(task, identity) if lab.has_method("checked_shared_vehicle_prefix_for_task") else {}

func prepare_shared_runtime_work_prefix(requests: Array, seconds: float) -> Dictionary:
	if not is_finite(seconds) or seconds <= 0.0 or not _checked_runtime_work_capture.is_empty(): return Runtime.fail("CLOCK_NOT_READY")
	if seconds > (1.0 - float(lab.terrain.site.phase)) * 60.0 + PersonFatigue.WORK_PLAN_EPS: return Runtime.fail("INVALID_INTERVAL", "原共同point必须截至下一原分钟端点")
	bind_checked_runtime_work_prefix()
	var clock := {"owner": self, "site": lab.terrain.site, "seconds": seconds, "minute": int(lab.terrain.site.minute),
		"phase": float(lab.terrain.site.phase), "combat_left": float(lab.terrain.site.combat_left),
		"advanced": false, "ship_build_due": false, "minute_due": false, "consumed": false}
	var held: Array[Dictionary] = []
	# Preserve original camp-worker before manual order, regardless of Array order.
	for key: String in ["worker", "manual"]:
		for request: Dictionary in requests:
			if request.get("provider") != "runtime" or request.get("key") != key or not str(request.get("paused", "")).is_empty(): continue
			var source: Dictionary = _shared_runtime_request_source(request)
			if not _shared_runtime_source_ready(source): return Runtime.fail("STALE_SOURCE")
			var person: Dictionary = source.person
			var task: Dictionary = source.task
			if person.cell != lab.terrain.cell_from_index(int(task.get("cell", -1))): return Runtime.fail("UNREACHABLE")
			var checked: Dictionary = Runtime.work_preflight(lab.terrain, task, person.cargo, int(source.carry_limit), int(person.faction), int(person.person_id), reserves_cell)
			if not checked.ok: return checked
			var skills: Dictionary = work_team._work_skill_facts(checked)
			if skills.is_empty(): return Runtime.fail("INVALID_WORK_SKILLS")
			var target_ref: Dictionary = _checked_runtime_target(task)
			if target_ref.is_empty(): return Runtime.fail("NO_TARGET")
			var trial: Dictionary = Runtime.technology_trial_work_facts(lab.terrain, target_ref, task, int(person.person_id)) if target_ref.has("tech_trial") else Runtime.ok("", {"policy_exception": ""})
			if not trial.ok: return trial
			var start := {"owner": person.owner, "unit": int(person.unit), "body": person.body, "row": person.body,
				"cargo": person.cargo, "item_state": person.holder, "cargo_values": person.cargo.duplicate(true), "item_values": person.holder.duplicate(true),
				"cell": person.cell, "faction": int(person.faction), "occupied": reserves_cell, "carry_limit": int(source.carry_limit),
				"task_values": task.duplicate(true), "work_unit": _checked_runtime_unit(task, target_ref),
				"productivity": float(checked.get("productivity", 1.0)), "progress_multiplier": float(checked.get("progress_multiplier", 1.0)),
				"required_skill": str(checked.get("required_skill", "")), "eligible_master": bool(checked.get("eligible_master", false)), "required_skills": skills.required, "eligible_skills": skills.eligible,
				"policy_exception": str(trial.get("policy_exception", ""))}
			held.append({"key": key, "actor": source.actor, "person_id": int(person.person_id), "task": task, "request": request,
				"target_ref": target_ref, "start": start, "remaining": float(checked.remaining)})
	_checked_runtime_work_capture = Runtime.ok("原Camp/manual同held起点已捕捉", {"owner": self, "terrain": lab.terrain, "site": lab.terrain.site, "seconds": seconds, "held": held, "clock": clock})
	return _checked_runtime_work_capture

func refresh_shared_runtime_work_request(request: Dictionary) -> Dictionary:
	# Called after original operating-slot projection, before pure pool planning.
	# Nothing selects work, advances timers or debits finite materials here.
	var source: Dictionary = _shared_runtime_request_source(request)
	if not _shared_runtime_source_ready(source): return {}
	if not str(request.get("paused", "")).is_empty(): return request
	var person: Dictionary = source.person
	var checked: Dictionary = Runtime.work_preflight(lab.terrain, source.task, person.cargo, int(source.carry_limit), int(person.faction), int(person.person_id), reserves_cell)
	if not checked.ok: return {}
	var updated: Dictionary = request.duplicate(false)
	updated["participants"] = request.participants.duplicate(false)
	updated.participants[0] = request.participants[0].duplicate(false)
	updated.participants[0].progress_multiplier = float(checked.get("productivity", 1.0))
	updated["productive_kind"] = "sum"
	updated["progress_multiplier"] = float(checked.get("progress_multiplier", 1.0))
	updated["remaining"] = float(checked.remaining)
	updated["payment"] = checked.get("payment", {})
	updated["payment_source"] = checked.get("payment_source", {})
	updated["payment_key"] = str(checked.get("payment_key", source.key))
	return _shared_runtime_physical_request(updated, checked)

func valid_checked_work_prefix(task: Dictionary, identity: int, prefix_ref: Dictionary) -> bool:
	var actual: Dictionary = checked_work_prefix_for_task(task, identity)
	if not _gd_contact_runtime_segment.is_empty():
		if actual.is_empty() or not is_same(actual, prefix_ref): return false
		for envelope: Dictionary in _gd_contact_runtime_capture.envelopes:
			if is_same(actual.held, envelope.prepared.prefix_ref.held): return valid_gd_contact_work_prefix(envelope, actual, actual.runtime_priors)
		return false
	return not actual.is_empty() and is_same(actual, prefix_ref) and actual.owner == self \
		and is_same(actual.plan, _checked_runtime_work_preparing.plan) and is_same(actual.runtime_priors, _checked_runtime_work_preparing.runtime_priors) \
		and _checked_runtime_refs_valid(actual.held)

func validate_shared_runtime_work_prefix(prepared: Dictionary, planned: Dictionary, runtime_priors: Array = [], pre_registered: Dictionary = {}) -> Dictionary:
	var registered: Dictionary = pre_registered
	if registered.is_empty(): registered = prepare_shared_runtime_prefix_allocations(prepared, planned, runtime_priors)
	elif registered.get("owner") != self or not is_same(registered.get("registered"), _checked_runtime_work_preparing) or not is_same(_checked_runtime_work_preparing.get("prepared"), prepared) or not is_same(_checked_runtime_work_preparing.get("plan"), planned) or not is_same(_checked_runtime_work_preparing.get("runtime_priors"), runtime_priors): return Runtime.fail("STALE_WORK_PREFIX")
	if not registered.ok: return registered
	for prefix: Dictionary in _checked_runtime_work_preparing.prefixes:
		var candidate: Dictionary = Runtime.prepare_checked_work_prefix(lab.terrain, prefix.task, float(prefix.applied_productive_seconds), float(prefix.actual_seconds), prefix)
		if not candidate.ok: return candidate
		_checked_runtime_work_preparing.runtime.append(candidate)
		runtime_priors.append(candidate) # Sole preparer; Runtime only reads SAME Array.
	_checked_runtime_work_admission = Runtime.ok("原Camp/manual所有候选已纯预验", _checked_runtime_work_preparing)
	return _checked_runtime_work_admission

func prepare_gd_contact_runtime_prefix(prepared: Dictionary, planned: Dictionary, runtime_priors: Array, pre_registered: Dictionary = {}) -> Dictionary:
	if not _gd_contact_runtime_capture.is_empty() or not _gd_contact_runtime_segment.is_empty(): return Runtime.fail("CLOCK_NOT_READY")
	var upper: Dictionary = planned.duplicate(false)
	upper["jobs"] = {}
	for provider: String in planned.jobs:
		upper.jobs[provider] = {}
		for key: String in planned.jobs[provider]:
			var allocation: Dictionary = planned.jobs[provider][key].duplicate(false)
			allocation["participant_effective_seconds"] = allocation.participant_seconds.duplicate()
			upper.jobs[provider][key] = allocation
	var admitted: Dictionary = validate_shared_runtime_work_prefix(prepared, upper if pre_registered.is_empty() else _checked_runtime_work_preparing.plan, runtime_priors, pre_registered)
	if not admitted.ok: return admitted
	var envelopes: Array[Dictionary] = []
	var people := {}
	for candidate: Dictionary in admitted.runtime:
		var envelope: Dictionary = Runtime.prepare_gd_contact_work_envelope(candidate)
		if not envelope.ok: return envelope
		envelopes.append(envelope)
		var prefix: Dictionary = candidate.prefix_ref
		var person: Dictionary = person_actions._person(int(prefix.person_id))
		var intent: Dictionary = prefix.task.duplicate(false)
		for field: String in ["progress", "status", "cargo"]: intent.erase(field)
		people[int(prefix.person_id)] = {"prefix": prefix, "hit": int(person.hit), "intent": intent}
	_gd_contact_runtime_capture = Runtime.ok("原camp/manual來源與有限材料上界已純核", {"owner": self, "prepared": prepared,
		"admitted": admitted, "seconds": float(prepared.seconds), "elapsed": 0.0, "envelopes": envelopes,
		"people": people, "priors": [], "published": [], "finished": false})
	return _gd_contact_runtime_capture

func prepare_gd_contact_runtime_segment(planned: Dictionary, seconds: float, defer_runtime: bool = false) -> Dictionary:
	if _gd_contact_runtime_capture.is_empty() or not _gd_contact_runtime_segment.is_empty() or planned.get("ok") != true \
		or not is_same(planned, lab.gd_mesh_work_segment_plan()) or not is_finite(seconds) or seconds <= 0.0 \
		or not is_equal_approx(float(planned.get("seconds", -1.0)), seconds) \
		or float(_gd_contact_runtime_capture.elapsed) + seconds > float(_gd_contact_runtime_capture.seconds) + PersonFatigue.WORK_PLAN_EPS:
		return Runtime.fail("STALE_WORK_PREFIX")
	var segment := {"owner": self, "plan": planned, "seconds": seconds, "prefixes": [], "runtime": [],
		"priors": lab.gd_mesh_work_segment_priors(), "published": false}
	for envelope: Dictionary in _gd_contact_runtime_capture.envelopes:
		var original: Dictionary = envelope.prepared.prefix_ref
		var allocation: Dictionary = planned.jobs.get("runtime", {}).get(str(original.held.key), {})
		var identity: int = int(original.person_id)
		var actual: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
		var productive: float = float(allocation.get("participant_effective_seconds", {}).get(identity, 0.0))
		if actual <= 0.0 or productive <= 0.0:
			if float(original.held.remaining) > PersonFatigue.WORK_PLAN_EPS: continue
			# Original mark_combat clears manual target AND progress. A zero
			# retry cannot resurrect its captured pre-contact work/intent.
			if is_same(original.task, lab.terrain.site.manual) and not gd_contact_runtime_person_ready(identity): continue
			var already := false
			for prior: Dictionary in _gd_contact_runtime_capture.priors: already = already or is_same(prior.task, original.task)
			if already: continue
		var prefix: Dictionary = original.duplicate(false)
		prefix["plan"] = planned
		prefix["allocation"] = allocation
		prefix["actual_seconds"] = actual
		prefix["productive_seconds"] = productive
		prefix["applied_productive_seconds"] = productive * float(original.start.productivity) * float(original.start.progress_multiplier)
		prefix["group_actual_seconds"] = float(allocation.get("actual_seconds", 0.0))
		prefix["runtime_priors"] = segment.priors
		segment.prefixes.append(prefix)
	_gd_contact_runtime_segment = segment
	if defer_runtime: return Runtime.ok("同段真本人分配已登記", {"segment": segment})
	return validate_gd_contact_runtime_segment(segment)

func _shared_runtime_physical_request(request: Dictionary, checked: Dictionary) -> Dictionary:
	var physical: Dictionary = Runtime.shared_physical_work_unit(lab.terrain, request.get("task", {}))
	if physical.is_empty(): return request
	if request.get("participants", []).size() != 1: return {}
	var weight: float = float(checked.get("productivity", NAN)) * float(checked.get("progress_multiplier", 1.0))
	if not is_finite(weight) or weight <= 0.0: return {}
	request["productive_kind"] = "sum"
	request["progress_multiplier"] = 1.0
	request["remaining"] = float(physical.physical_remaining)
	request.participants[0].progress_multiplier = weight
	return request

func shared_vehicle_work_request_facts(request: Dictionary) -> Dictionary:
	if request.get("productive_kind") != "sum" or str(request.get("paused", "")) not in ["", "REST"]: return {}
	var source: Dictionary = _shared_runtime_request_source(request)
	if not _shared_runtime_source_ready(source): return {}
	var physical: Dictionary = Runtime.shared_physical_work_unit(lab.terrain, source.task)
	if physical.is_empty(): return {}
	var checked: Dictionary = Runtime.work_preflight(lab.terrain, source.task, source.person.cargo, int(source.carry_limit), int(source.person.faction), int(source.person.person_id), reserves_cell)
	if not checked.ok: return {}
	var skills: Dictionary = work_team._work_skill_facts(checked)
	var participant: Dictionary = request.participants[0]
	var identity: int = int(source.person.person_id)
	if skills.is_empty() or not is_same(participant.get("original_body", participant.get("body")), source.person.body) or not is_equal_approx(float(participant.get("progress_multiplier", 1.0)), float(checked.get("productivity", 1.0)) * float(checked.get("progress_multiplier", 1.0))) or not is_equal_approx(float(request.progress_multiplier), 1.0): return {}
	var facts: Dictionary = physical.duplicate(false)
	facts.merge({"owner": self, "request": request, "site": lab.terrain.site, "source": source, "task": source.task,
		"person_ids": [identity], "required_skills": skills.required, "eligible_by_id": {identity: skills.eligible},
		"remaining": float(physical.physical_remaining), "participants": request.participants, "values": request.duplicate(false),
		"participant_values": work_team._shared_vehicle_participant_values(request)})
	if not _shared_worker_inputs.has("shared_work_facts"): _shared_worker_inputs["shared_work_facts"] = {}
	_shared_worker_inputs.shared_work_facts[str(request.key)] = facts
	return facts

func valid_shared_vehicle_work_request_facts(request: Dictionary, facts: Dictionary) -> bool:
	if facts.get("owner") != self or not is_same(facts.get("request"), request) or not is_same(facts.get("site"), lab.terrain.site) or not is_same(facts.get("participants"), request.get("participants")) or request != facts.get("values") or work_team._shared_vehicle_participant_values(request) != facts.get("participant_values") or not is_same(_shared_worker_inputs.get("shared_work_facts", {}).get(str(request.key)), facts): return false
	var source: Dictionary = _shared_runtime_request_source(request)
	var physical: Dictionary = Runtime.shared_physical_work_unit(lab.terrain, facts.task)
	return not source.is_empty() and is_same(source.task, facts.task) and not physical.is_empty() and is_same(physical.target_ref, facts.target_ref) and is_same(physical.work_unit, facts.work_unit) and physical.action == facts.action and physical.field == facts.field

func owned_checked_work_prefixes() -> Array:
	return _gd_contact_runtime_segment.prefixes if not _gd_contact_runtime_segment.is_empty() else _checked_runtime_work_preparing.get("prefixes", [])

func prepare_shared_runtime_prefix_allocations(prepared: Dictionary, planned: Dictionary, runtime_priors: Array = []) -> Dictionary:
	if prepared.get("owner") != self or not is_same(prepared, _checked_runtime_work_capture) or not is_same(prepared.get("terrain"), lab.terrain) or not is_same(prepared.get("site"), lab.terrain.site) or planned.get("ok") != true or absf(float(planned.get("seconds", -1.0)) - float(prepared.seconds)) > PersonFatigue.WORK_PLAN_EPS: return Runtime.fail("STALE_SOURCE")
	_checked_runtime_work_preparing = {"owner": self, "prepared": prepared, "plan": planned, "runtime_priors": runtime_priors, "prefixes": [], "runtime": []}
	for held: Dictionary in prepared.held:
		if not _checked_runtime_refs_valid(held): return Runtime.fail("STALE_SOURCE")
		var allocation: Dictionary = planned.jobs.get("runtime", {}).get(str(held.key), {})
		var identity: int = int(held.person_id)
		var actual: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
		var productive: float = float(allocation.get("participant_effective_seconds", {}).get(identity, 0.0))
		if not is_finite(actual) or not is_finite(productive) or actual < 0.0 or actual > float(prepared.seconds) + PersonFatigue.WORK_PLAN_EPS or productive < 0.0 or productive > actual + PersonFatigue.WORK_PLAN_EPS: return Runtime.fail("INVALID_WORK")
		if actual <= 0.0 and float(held.remaining) > PersonFatigue.WORK_PLAN_EPS: continue
		var applied: float = productive * float(held.start.productivity) * float(held.start.progress_multiplier)
		if not is_finite(applied) or applied < 0.0: return Runtime.fail("INVALID_WORK")
		var prefix := {"owner": self, "plan": planned, "entry": held, "person_id": identity, "task": held.task, "start": held.start,
			"target_ref": held.target_ref, "target": str(held.task.target), "plan_key": str(allocation.get("shared_vehicle_group", {}).get("key", "runtime:" + str(held.key))), "shared_vehicle_group": allocation.get("shared_vehicle_group", {}),
			"actual_seconds": actual, "productive_seconds": productive, "applied_productive_seconds": applied,
			"group_actual_seconds": float(allocation.get("actual_seconds", actual)), "allocation": allocation, "required_skill": str(held.start.required_skill),
			"eligible_master": bool(held.start.eligible_master), "required_skills": held.start.required_skills, "eligible_skills": held.start.eligible_skills, "held": held, "runtime_priors": runtime_priors,
			"work_unit": held.start.work_unit, "policy_exception": str(held.start.policy_exception)}
		_checked_runtime_work_preparing.prefixes.append(prefix)
	return Runtime.ok("原camp/manual本人分配已登記，尚未來源候選", {"owner": self, "registered": _checked_runtime_work_preparing})

func validate_gd_contact_runtime_segment(segment: Dictionary) -> Dictionary:
	if not is_same(segment, _gd_contact_runtime_segment) or bool(segment.get("published", true)) or not segment.get("runtime", []).is_empty() or not is_same(segment.get("plan"), lab.gd_mesh_work_segment_plan()) or not is_same(segment.get("priors"), lab.gd_mesh_work_segment_priors()): return Runtime.fail("STALE_WORK_PREFIX")
	for envelope: Dictionary in _gd_contact_runtime_capture.envelopes:
		for prefix: Dictionary in segment.prefixes:
			if not is_same(prefix.held, envelope.prepared.prefix_ref.held): continue
			var candidate: Dictionary = Runtime.restrict_gd_contact_work_prefix(envelope, prefix, segment.priors)
			if not candidate.ok: return candidate
			segment.runtime.append(candidate)
			segment.priors.append(candidate)
	return Runtime.ok("原camp/manual實際段已派生；未施工／付款", {"segment": segment})

func _gd_contact_delivery_intent(job: Dictionary) -> Dictionary:
	var value: Dictionary = job.duplicate(false)
	for key: String in ["left", "pending", "source_cargo", "source_holder", "source_body", "source_owner", "receiver_body", "receiver_owner", "source_open"]: value.erase(key)
	return value.duplicate(true)

func prepare_gd_contact_delivery_window(supply: Dictionary, requests: Array, planned: Dictionary) -> Dictionary:
	if supply.get("owner") != self or not planned.get("ok", false) or not is_same(requests, lab._shared_work_requests) \
		or not is_same(planned, lab._shared_work_plan) or float(planned.get("seconds", -1.0)) != float(supply.get("seconds", 0.0)): return Runtime.fail("CLOCK_NOT_READY")
	var rows: Array[Dictionary] = []
	var people := {}
	var accepted := {}
	for row: Dictionary in supply.rows:
		if row.kind != "team" or row.entry.get("delivery", {}).is_empty(): continue
		var job: Dictionary = row.entry.delivery
		var held := {"supply_row": row, "job": job, "intent": _gd_contact_delivery_intent(job), "refs": job.duplicate(false), "request": {}, "people": {},
			"valid": _delivery_valid(row.owner, row.entry)}
		rows.append(held)
		if not bool(held.valid): continue # Original current endpoint cancels this source without blocking unrelated work.
		for request: Dictionary in requests:
			if request.get("provider") != "delivery" or str(request.get("key", "")) != str(row.owner.team_id): continue
			if bool(job.get("pending", false)) or not held.request.is_empty(): return Runtime.fail("STALE_DELIVERY_SOURCE")
			var originals: Array[Dictionary] = _delivery_people(row.entry)
			if originals.is_empty() or request.get("participants", []).size() != originals.size() \
				or str(request.get("productive_kind")) != ("joint" if originals.size() == 2 else "single") \
				or float(request.get("remaining", -1.0)) != float(job.left): return Runtime.fail("STALE_DELIVERY_SOURCE")
			for person: Dictionary in originals:
				var identity: int = int(person.person_id)
				var participant: Dictionary = {}
				for candidate: Dictionary in request.participants:
					if int(candidate.person_id) == identity: participant = candidate
				if participant.is_empty() or people.has(identity) or not is_same(person.body, participant.get("body")): return Runtime.fail("STALE_DELIVERY_SOURCE")
				var source := {"held": held, "person_id": identity, "owner": person.owner, "unit": int(person.unit), "body": person.body,
					"cell": person.cell, "hit": int(person.hit), "participant": participant}
				held.people[identity] = source
				people[identity] = source
			held["request"] = request
			accepted[str(row.owner.team_id)] = request
	for request: Dictionary in requests:
		if request.get("provider") == "delivery" and not is_same(accepted.get(str(request.get("key", ""))), request): return Runtime.fail("STALE_DELIVERY_SOURCE")
	supply["delivery"] = {"rows": rows, "people": people}
	return Runtime.ok("原交糧具名來源與雙人工作已核；尚無工時／餐費")

func gd_contact_delivery_person_ready(identity: int) -> bool:
	var supply: Dictionary = lab._gd_mesh_work_point.get("supply", {})
	var held: Dictionary = supply.get("delivery", {}).get("people", {}).get(identity, {}).get("held", {})
	if held.is_empty() or not bool(held.valid): return false
	var row: Dictionary = held.supply_row
	if not is_same(_supply_entry(row.owner), row.entry) or not is_same(row.entry.get("delivery"), held.job) \
		or bool(held.job.get("pending", false)) or _gd_contact_delivery_intent(held.job) != held.intent \
		or not _delivery_valid(row.owner, row.entry): return false
	for key: String in ["source_cargo", "source_holder", "source_body", "receiver_body"]:
		if not is_same(held.job.get(key), held.refs.get(key)): return false
	for key: String in ["source_owner", "receiver_owner"]:
		if held.job.get(key) != held.refs.get(key): return false
	if not held.refs.get("source_open", {}).is_empty() and not is_same(held.job.get("source_open"), held.refs.source_open): return false
	# Joint carrying requires BOTH true original people through every prefix.
	# REST remains the common planner's authority, not this physical predicate.
	for source: Dictionary in held.people.values():
		var person: Dictionary = person_actions._person(int(source.person_id))
		if person.is_empty() or person.owner != source.owner or int(person.unit) != int(source.unit) or not is_same(person.body, source.body) \
			or person.cell != source.cell or int(person.hit) != int(source.hit): return false
		if int(person.person_id) != lab.controlled_person_id() and person_actions._threat(person, {}): return false
	return true

func _project_gd_contact_delivery_segment(planned: Dictionary, seconds: float) -> Dictionary:
	var point: Dictionary = lab._gd_mesh_work_point
	if point.is_empty() or not is_same(point.get("segment_plan"), planned) or not is_finite(seconds) or seconds <= 0.0 \
		or float(planned.get("seconds", -1.0)) != seconds or float(point.elapsed) + seconds > float(point.seconds) + PersonFatigue.WORK_PLAN_EPS: return Runtime.fail("CLOCK_NOT_READY")
	var entries: Array[Dictionary] = []
	for held: Dictionary in point.supply.delivery.rows:
		if held.request.is_empty(): continue
		var row: Dictionary = held.supply_row
		var allocation: Dictionary = planned.jobs.get("delivery", {}).get(str(row.owner.team_id), {})
		if allocation.is_empty(): return Runtime.fail("STALE_DELIVERY_SOURCE")
		var actual: float = float(allocation.actual_seconds)
		var effective: float = float(allocation.effective_seconds)
		if not is_finite(actual) or not is_finite(effective) or actual < 0.0 or effective < 0.0 \
			or actual > seconds + PersonFatigue.WORK_PLAN_EPS or effective > actual + PersonFatigue.WORK_PLAN_EPS: return Runtime.fail("INVALID_WORK_PLAN")
		if not is_same(row.entry.get("delivery"), held.job):
			if actual > 0.0 or effective > 0.0: return Runtime.fail("STALE_DELIVERY_SOURCE")
			continue
		var smallest := INF
		for identity: int in held.people:
			var participant_actual: float = float(allocation.participant_seconds.get(identity, -1.0))
			var participant_effective: float = float(allocation.participant_effective_seconds.get(identity, -1.0))
			if participant_actual != actual or participant_effective < 0.0 or participant_effective > participant_actual + PersonFatigue.WORK_PLAN_EPS: return Runtime.fail("INVALID_WORK_PLAN")
			smallest = minf(smallest, participant_effective)
		if effective > smallest + PersonFatigue.WORK_PLAN_EPS or effective > float(held.job.left) + PersonFatigue.WORK_PLAN_EPS: return Runtime.fail("INVALID_WORK_PLAN")
		entries.append({"held": held, "allocation": allocation, "left_before": float(held.job.left), "pending_before": bool(held.job.pending),
			"left_after": maxf(0.0, float(held.job.left) - effective)})
	return Runtime.ok("", {"segment": {"owner": self, "supply": point.supply, "plan": planned, "seconds": seconds, "entries": entries, "published": false}})

func prepare_gd_contact_delivery_segment(planned: Dictionary, seconds: float) -> Dictionary:
	var prepared: Dictionary = _project_gd_contact_delivery_segment(planned, seconds)
	if not prepared.ok: return prepared
	prepared.segment.supply["delivery_segment"] = prepared.segment
	return prepared

func validate_gd_contact_delivery_segment(segment: Dictionary) -> Dictionary:
	var point: Dictionary = lab._gd_mesh_work_point
	if point.is_empty() or segment.get("owner") != self or bool(segment.get("published", true)) \
		or not is_same(segment.get("supply"), point.supply) or not is_same(point.supply.get("delivery_segment"), segment): return Runtime.fail("STALE_DELIVERY_SOURCE")
	var expected: Dictionary = _project_gd_contact_delivery_segment(segment.plan, float(segment.seconds))
	if not expected.ok or segment.entries.size() != expected.segment.entries.size(): return Runtime.fail("STALE_DELIVERY_SOURCE")
	for index: int in segment.entries.size():
		var value: Dictionary = segment.entries[index]
		var original: Dictionary = expected.segment.entries[index]
		if not is_same(value.get("held"), original.held) or not is_same(value.get("allocation"), original.allocation) \
			or value.get("left_before") != original.left_before or value.get("pending_before") != original.pending_before or value.get("left_after") != original.left_after: return Runtime.fail("STALE_DELIVERY_SOURCE")
	return Runtime.ok()

func publish_gd_contact_delivery_segment(segment: Dictionary) -> void:
	assert(segment.owner == self and not segment.published and is_same(lab._gd_mesh_work_point.supply.get("delivery_segment"), segment))
	for value: Dictionary in segment.entries:
		var held: Dictionary = value.held
		var allocation: Dictionary = value.allocation
		for identity: int in held.people:
			var source: Dictionary = held.people[identity]
			var actual: float = float(allocation.participant_seconds[identity])
			if identity != lab.controlled_person_id() and (str(allocation.paused) == "REST" or actual > 0.0):
				person_actions._body_set({"body": source.body, "owner": source.owner, "unit": source.unit}, "work_resting", str(allocation.paused) == "REST")
			if int(source.unit) < 0: lab._fatigue_work_seconds[source.owner] = float(lab._fatigue_work_seconds.get(source.owner, 0.0)) + actual
		# Only the original job's effective game seconds change. Food/source and
		# pools have their separate original publishers, each once.
		held.job.left = float(value.left_after)
		if float(held.job.left) <= 0.00000001:
			held.job.left = 0.0
			held.job.pending = true
	segment["published"] = true
	segment.supply.erase("delivery_segment")

func finish_gd_contact_delivery_window(supply: Dictionary) -> void:
	for held: Dictionary in supply.get("delivery", {}).get("rows", []):
		var row: Dictionary = held.supply_row
		if not is_same(row.entry.get("delivery"), held.job): continue
		if not _delivery_valid(row.owner, row.entry):
			row.entry.delivery = {}
			message.text = "交糧條件已變更，當批取消；來源未扣物"

func prepare_received_opened_food(identity: int, amount: float, original: Dictionary, source_only: bool = false) -> Dictionary:
	# The original private Supply owner prepares its OWN finite scalar state.
	# No food debit, person, cohort or clock is published by this reader.
	if not is_instance_valid(lab) or lab.terrain == null or captivity_supply == null or not is_finite(amount) or amount <= 0.0 or amount > Runtime.CARRY_CAPACITY:
		return Runtime.fail("INVALID", "原開封口糧數量或供養來源失效")
	var site: Dictionary = lab.terrain.site
	var person: Dictionary = _supply_person(identity)
	if person.is_empty() or person.owner is CrowdOwner: return Runtime.fail("UNSUPPORTED", "原GD私人餐份尚無同點Native提交")
	var pool: Dictionary = _personal_opened_food(identity)
	if (not pool.is_empty() or not original.is_empty()) and not is_same(pool, original): return Runtime.fail("STALE_SOURCE")
	var at_seconds: float = Runtime.now(lab.terrain) * 60.0
	var state: Dictionary = Sustain.create(at_seconds) if pool.is_empty() else pool.duplicate(true)
	var members: Dictionary = captivity_supply._all_members()
	if state.get("version") != 1 or not Sustain.validate(state, members): return Runtime.fail("INVALID_SUSTAIN", "原私人餐份狀態非法")
	var feeding: String = captivity_supply._feeding_owner(identity, captivity_supply._states())
	if state.cohorts.is_empty() and feeding.is_empty():
		if not _align_supply_clock(state, at_seconds): return Runtime.fail("STALE_SUPPLY_CLOCK")
		var joined: Dictionary = Sustain.add_members(state, members, [identity])
		if not joined.ok: return joined
	if not Sustain._number(float(state.open_rations) + amount, 0.0, 1000000.0): return Runtime.fail("STORAGE_FULL")
	state["open_rations"] = float(state.open_rations) + amount
	return Runtime.ok("原私人開封餐份候選；尚未收物", {"owner": self, "terrain": lab.terrain, "site": site,
		"identity": identity, "amount": amount, "original": original, "pool": pool, "pool_before": pool.duplicate(true),
		"had_map": site.has("person_supply"), "map": site.get("person_supply", {}), "at_seconds": at_seconds,
		"person": person, "feeding": feeding, "state": state, "source_only": source_only, "published": false})

func validate_received_opened_food(prepared: Dictionary, require_completion: bool = true) -> Dictionary:
	if prepared.get("ok") != true or prepared.get("owner") != self or prepared.get("published") != false \
		or require_completion and bool(prepared.get("source_only", true)) or not is_instance_valid(lab) \
		or not is_same(lab.terrain, prepared.get("terrain")) or not is_same(lab.terrain.site, prepared.get("site")):
		return Runtime.fail("STALE_SOURCE")
	var expected: Dictionary = prepare_received_opened_food(int(prepared.get("identity", -1)), float(prepared.get("amount", -1.0)), prepared.get("original", {}), bool(prepared.source_only))
	if not expected.ok: return expected
	if bool(expected.had_map) != bool(prepared.get("had_map", false)) or expected.had_map and not is_same(expected.map, prepared.get("map")) \
		or (not expected.pool.is_empty() or not prepared.get("pool", {}).is_empty()) and not is_same(expected.pool, prepared.get("pool")) \
		or expected.pool_before != prepared.get("pool_before") or expected.at_seconds != prepared.get("at_seconds") \
		or expected.feeding != prepared.get("feeding") or expected.state != prepared.get("state"):
		return Runtime.fail("STALE_SUPPLY_SOURCE")
	var person: Dictionary = expected.person
	var original_person: Dictionary = prepared.get("person", {})
	if original_person.is_empty() or not is_same(person.owner, original_person.get("owner")) or not is_same(person.body, original_person.get("body")) \
		or not is_same(person.holder, original_person.get("holder")) or not is_same(person.cargo, original_person.get("cargo")):
		return Runtime.fail("STALE_SUPPLY_OWNER")
	return Runtime.ok()

func publish_received_opened_food(prepared: Dictionary) -> void:
	# Caller checked every original loot/current-person endpoint immediately
	# before its first debit. This original Supply publication has no callback.
	assert(prepared.ok and prepared.owner == self and not prepared.source_only and not prepared.published)
	var site: Dictionary = prepared.site
	if not bool(prepared.had_map): site["person_supply"] = {}
	if prepared.pool.is_empty():
		site.person_supply[str(int(prepared.identity))] = prepared.state
	else:
		prepared.pool.clear()
		prepared.pool.merge(prepared.state)
	prepared["published"] = true

func _refresh_siege_build_people(form: Dictionary) -> void:
	if not form.has("siege_builder"): return
	var choice: OptionButton = form.siege_builder
	var prior: int = int(choice.get_item_metadata(choice.selected)) if choice.selected >= 0 else 0
	var previous: Dictionary = choice.get_meta(&"siege_build_context", {})
	choice.clear()
	choice.add_item("請具名選擇原施工人員")
	choice.set_item_metadata(0, 0)
	choice.set_meta(&"siege_build_context", {})
	if person_actions.lab == null or not person_actions.has_method("technology_vehicle_work_admission"): return
	var team: Variant = _siege_build_ui_team(form)
	if team == null or not team.has_army(): return
	var requester: int = team.combat_identity(team.current_commander) if bool(form.get("trial", false)) else lab.controlled_person_id()
	if not is_same(previous.get("data"), lab.terrain) or not is_same(previous.get("team"), team) or int(previous.get("requester_id", -1)) != requester or int(previous.get("controlled_id", -1)) != lab.controlled_person_id(): prior = 0
	choice.set_meta(&"siege_build_context", {"data": lab.terrain, "team": team, "requester_id": requester, "controlled_id": lab.controlled_person_id()})
	var kind: String = str(form.siege_kind.get_item_metadata(form.siege_kind.selected)) if form.siege_kind.selected >= 0 else ""
	var category: String = preload("res://scripts/terrain_lab/site_technology_policy.gd").siege_category(kind)
	for index: int in _siege_ui_indices(team):
		if not team.is_member(index): continue
		var identity: int = team.combat_identity(index)
		var person: Dictionary = person_actions._person(identity)
		if person.is_empty(): continue
		var ready: Dictionary = person_actions.technology_vehicle_work_admission(identity, int(team.team_id))
		var learned: bool = category.is_empty() or preload("res://scripts/terrain_lab/site_technology.gd").learned(person_actions._body_get(person, "technology"), category)
		choice.add_item("原人 #%d · 格%s · %s%s" % [identity, person.cell, "已學本工法" if learned else "未學本工法", "" if ready.ok else " · " + str(ready.get("code", "不可開工"))])
		choice.set_item_metadata(choice.item_count - 1, identity)
		# Preserve only a HUMAN's earlier explicit ID. Never auto-select a master.
		if identity == prior and prior > 0: choice.select(choice.item_count - 1)

func _siege_build_person_context(form: Dictionary) -> Dictionary:
	if not form.has("siege_builder") or form.siege_builder.selected < 0: return Runtime.fail("NO_OPERATOR", "請明示本次原施工人員")
	var identity: int = int(form.siege_builder.get_item_metadata(form.siege_builder.selected))
	if identity <= 0: return Runtime.fail("NO_OPERATOR", "請明示本次原施工人員")
	var held: Dictionary = form.siege_builder.get_meta(&"siege_build_context", {})
	var team: Variant = _siege_build_ui_team(form)
	if team == null or held.is_empty() or not is_same(held.get("data"), lab.terrain) or not is_same(held.get("team"), team) or int(held.get("controlled_id", -1)) != lab.controlled_person_id(): return Runtime.fail("STALE_SOURCE", "原人／隊伍／Site 已變更，請重新查詢")
	var requester: int = team.combat_identity(team.current_commander) if bool(form.get("trial", false)) else lab.controlled_person_id()
	if int(held.get("requester_id", -1)) != requester: return Runtime.fail("NO_AUTHORITY")
	if not person_actions.has_method("technology_vehicle_work_admission"): return Runtime.fail("UNSUPPORTED")
	var ready: Dictionary = person_actions.technology_vehicle_work_admission(identity, int(team.team_id))
	if not ready.ok: return ready
	if not is_same(ready.get("team"), team) or ready.get("person_ids", []) != [identity] or int(ready.get("requester_id", -1)) != requester: return Runtime.fail("STALE_SOURCE")
	return Runtime.ok("明示原人，施工准入仍由原 Runtime 重查", {"team": team, "requester_id": requester, "person_id": identity})

func _irrigation_add_selected() -> Dictionary:
	if not lab.terrain.contains(selected): return Runtime.fail("NO_TARGET")
	var index: int = lab.terrain.index(selected)
	if build_cells.size() >= Runtime.IRRIGATION_MAX_CELLS or build_cells.has(index): return Runtime.fail("INVALID")
	if not build_cells.is_empty() and not Runtime._irrigation_adjacent(lab.terrain, int(build_cells[-1]), index): return Runtime.fail("INVALID", "下一格須與草稿尾端真相鄰")
	var choice := _building_choice("irrigation_channel")
	if choice < 0: return Runtime.fail("NO_OWNER_HOOK")
	buildings.select(choice)
	building_resize = false
	build_cells.append(index)
	modes.select(5)
	return Runtime.ok("已加入原地圖真格；只保存在建設草稿，未扣料")

func _refresh_irrigation_controls() -> void:
	var form := _irrigation_controls()
	if form.is_empty() or lab.terrain == null: return
	var sources: Array[String] = []
	var upstreams: Array[String] = []
	var source := _irrigation_choice(form.source)
	var upstream := _irrigation_choice(form.upstream)
	for key: String in lab.terrain.site.features:
		var feature: Dictionary = lab.terrain.site.features[key]
		if feature.get("kind") in ["well", "intake"] and feature.get("stage") == "complete" and Runtime.feature_usable(feature): sources.append(key)
		if feature.get("kind") == "irrigation_channel" and feature.get("stage") == "complete" and Runtime.feature_usable(feature) \
			and feature.get("irrigation", {}).get("source_feature_id") == source: upstreams.append(key)
	var signature := JSON.stringify([sources, upstreams, source])
	if signature != str(form.signature):
		form.source.clear()
		for key: String in sources:
			form.source.add_item("原水站 #" + key)
			form.source.set_item_metadata(form.source.item_count - 1, key)
			if key == source: form.source.select(form.source.item_count - 1)
		form.upstream.clear()
		form.upstream.add_item("直接接原水站")
		form.upstream.set_item_metadata(0, "")
		for key: String in upstreams:
			form.upstream.add_item("原同源渠道尾端 #" + key)
			form.upstream.set_item_metadata(form.upstream.item_count - 1, key)
			if key == upstream: form.upstream.select(form.upstream.item_count - 1)
		form.signature = signature
	var activated: bool = SiteTechnologyCatalog.get_node("S02").get("enabled") == true
	form.status.text = "本草稿 %d／36 格；每格木1＋石2／原工作300秒，沿原共享取水预算；上游毀壞即停效。%s" % [build_cells.size(), "可提交原owner預檢" if activated else "尚未命名驗收，唯讀／禁止付款"]
	form.begin.disabled = not activated
	form.resume.disabled = not activated
	# Geometry selection/preview never creates knowledge or a paid request.
	form.preview.disabled = false

func _irrigation_options() -> Dictionary:
	var form := _irrigation_controls()
	if form.is_empty(): return {}
	return {"version": 1, "settlement_id": str(lab.terrain.site.get("settlement", {}).get("settlement_id", "")),
		"source_feature_id": _irrigation_choice(form.source), "upstream_feature_id": _irrigation_choice(form.upstream)}

func _nation_ui_version(key: String) -> int:
	var stock: Dictionary = {}
	if key.begins_with("person:"):
		var person: Dictionary = person_actions._person(int(key.trim_prefix("person:")), false)
		return int(person.get("holder", {}).get("version", -1))
	if key.begins_with("feature:"): stock = Stockpiles.stock_endpoint(lab.terrain, key.trim_prefix("feature:"))
	else:
		var vehicle: Dictionary = vehicles.records().get(key, {})
		if not vehicle.is_empty(): stock = {"holder": vehicle.holder}
	return int(stock.get("holder", {}).get("version", -1))

func begin_nation_arsenal(nation_id: String, order_id: String, work_target: Dictionary = {}) -> Dictionary:
	return equipment_orders.begin_arsenal_order(int(lab.controlled_person_id()), nation_id, order_id, work_target)

func _nation_ui_selection(form: Dictionary) -> Dictionary:
	var chosen := {"resources": {}, "resource_limits": {}}
	for key: String in form.controls:
		var node: Node = form.controls[key]
		if node is OptionButton: chosen[key] = node.get_item_metadata(node.selected) if node.selected >= 0 else ""
		elif node is ItemList:
			chosen[key] = []
			for index: int in node.get_selected_items(): chosen[key].append(node.get_item_metadata(index))
		elif node is SpinBox: chosen[key] = int(node.value)
		elif node is LineEdit: chosen[key] = node.text.strip_edges()
	for resource: String in form.resources:
		var fields: Dictionary = form.resources[resource]
		if int(fields.quantity.value) > 0: chosen.resources[resource] = int(fields.quantity.value)
		if fields.has("batch") and int(fields.batch.value) > 0:
			chosen.resource_limits[resource] = {"batch": int(fields.batch.value), "total": int(fields.total.value)}
	return chosen

func _nation_ui_render(form: Dictionary) -> void:
	if lab.terrain != form.data or not is_same(lab.terrain.site, form.site) or lab.controlled_person_id() != int(form.requester):
		form.status.text = "原 Site 或受控人物已變更，請重新開啟。"
		return
	for child: Node in form.body.get_children():
		form.body.remove_child(child)
		child.queue_free()
	form["controls"] = {}
	form["resources"] = {}
	var nation_id := str(form.nation_choice.get_item_metadata(form.nation_choice.selected))
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	form["nation"] = nation
	if nation.is_empty(): return
	var tech_id := str(form.technology.get_item_metadata(form.technology.selected))
	var ops: Dictionary = nation.get("technology_operations", {})
	if not ops.is_empty() and not EquipmentOrders.valid_nation_operation_record(ops, lab.terrain.site.item_definitions, {}):
		form.status.text = "原制度紀錄損壞；停止提交。"
		return
	var public_orders := {}
	for key: String in ops.get("public_orders", {}):
		if ops.public_orders[key].tech_id == tech_id: public_orders[key] = ops.public_orders[key]
	var people := _nation_ui_people()
	var order_records: Dictionary = ops.get("orders", {}) if tech_id == "N05" else public_orders
	if tech_id not in ["N01", "N04"]:
		var order_choice := _nation_ui_choice(form, "order", "原具名工單", _nation_ui_entries(order_records))
		var order_summary := _label(form.body, "選單可查看本單成本、來源與已接受實績。", 14)
		order_choice.item_selected.connect(func(_index: int) -> void: _nation_ui_order_summary(form, order_summary))
	if tech_id in ["N01", "N03", "N06", "N07", "N08", "N09", "N11"]: _nation_ui_choice(form, "reserve", "原倉庫", _nation_ui_features(["warehouse"]))
	if tech_id in ["N01", "N05"]: _nation_ui_choice(form, "standard", "原兵種標準（採購時沿此真定義與替代清單）", _nation_ui_entries(nation.get("standards", {})))
	if tech_id == "N01":
		_nation_ui_choice(form, "spec", "原採購規格", _nation_ui_entries(ops.get("specs", {})))
		_nation_ui_text(form, "key", "新增採購規格代號；選既有規格時留空")
		_nation_ui_text(form, "name", "規格名稱")
		_nation_ui_number(form, "item_batch", "實物單批數量", 0, 128)
		_nation_ui_number(form, "item_total", "實物總數量", 0, 128)
		_nation_ui_resource_fields(form, Env.ITEM_NAMES.keys(), true)
		var held_items: Array = []
		var person: Dictionary = person_actions._person(int(form.requester), false)
		for key: String in person.get("holder", {}).get("item_ids", []):
			var item: Dictionary = lab.terrain.site.get("item_records", {}).get(key, {})
			if not item.is_empty(): held_items.append({"id": key, "label": "#%s · %s" % [key, str(item.get("definition", ""))]})
		_nation_ui_list(form, "items", "本次交付本人原實物", held_items)
		_nation_ui_button(form, "發布／重新核准採購規格", "publish_spec")
		_nation_ui_button(form, "交出本次選定真材料與實物", "deliver_spec")
		_nation_ui_button(form, "重做所選原規格已付行政工作", "administration_spec")
	elif tech_id == "N04":
		_nation_ui_choice(form, "certificate", "原作坊證書", _nation_ui_entries(ops.get("certificates", {})))
		_nation_ui_text(form, "key", "新增作坊證書代號；選既有證書時留空")
		var host_choice := _nation_ui_choice(form, "host", "本地原作坊", _nation_ui_features(["smithy", "weaver"]))
		_nation_ui_choice(form, "industry", "本次驗收產業", [{"id": "S04", "label": "鍛造作坊"}, {"id": "S05", "label": "紡織作坊"}, {"id": "S07", "label": "弓作作坊"}])
		var receipts := _nation_ui_choice(form, "receipt", "所選作坊本次真出貨", [])
		host_choice.item_selected.connect(func(_index: int) -> void:
			receipts.clear()
			receipts.add_item("請選真出貨")
			receipts.set_item_metadata(0, "")
			var feature: Dictionary = lab.terrain.site.features.get(str(host_choice.get_item_metadata(host_choice.selected)), {})
			for receipt: Dictionary in feature.get("technology_output", {}).get("receipts", []):
				receipts.add_item("批次 %d · 操作者 #%d" % [int(receipt.id), int(receipt.operator_id)])
				receipts.set_item_metadata(receipts.item_count - 1, int(receipt.id)))
		_nation_ui_button(form, "驗收所選真出貨並核准作坊", "certify")
		_nation_ui_button(form, "重做所選原證書檢驗工作", "administration_certificate")
	elif tech_id == "N05":
		_nation_ui_choice(form, "certificate", "有效原弓作證書", _nation_ui_entries(ops.get("certificates", {})))
		_nation_ui_choice(form, "operator", "具名原操作者", people)
		_nation_ui_choice(form, "recipient", "原領裝人", people)
		_nation_ui_resource_fields(form, ["wood", "fiber"])
		_nation_ui_button(form, "建立一批弓的原生產與領裝單，請求原隊同意", "request_military")
		_nation_ui_button(form, "明示核准本人本單有限材料", "grant_military")
		_nation_ui_button(form, "交出本人材料至本單原作坊", "supply_military")
		_nation_ui_button(form, "開始本單真一批生產", "begin_military")
		_nation_ui_button(form, "沿原領裝入口領取本單成品", "issue_military")
	elif tech_id == "N02":
		_nation_ui_list(form, "people", "本次原居民與勞役人", people)
		_nation_ui_button(form, "登記具名勞役並請求原隊同意", "labor")
		_nation_ui_button(form, "開始本單名冊行政工作", "administration")
		_nation_ui_geometry(form, false)
		_nation_ui_button(form, "開始本單一格道路施工", "construction")
	elif tech_id == "N03":
		_nation_ui_list(form, "people", "本次兩名真接收者", people)
		_nation_ui_choice(form, "recipient", "本次送糧接收者", people)
		_nation_ui_button(form, "建立兩名接收者的有限賑濟單", "aid")
	elif tech_id == "N06":
		var labor := {}
		for key: String in ops.get("public_orders", {}):
			if ops.public_orders[key].tech_id == "N02": labor[key] = ops.public_orders[key]
		_nation_ui_choice(form, "labor", "真原勞役名冊", _nation_ui_entries(labor))
		_nation_ui_list(form, "people", "本次名冊內原工人", people)
		_nation_ui_button(form, "依原住宅藍圖開單並請求原隊同意", "public_work")
		_nation_ui_geometry(form, true)
		_nation_ui_button(form, "以本單真有限材料開始住宅施工", "construction")
	elif tech_id == "N07":
		_nation_ui_choice(form, "teacher", "真原師傅", people)
		_nation_ui_list(form, "people", "本次最多兩個學生席位", people)
		_nation_ui_choice(form, "student", "本次上課原學生", people)
		var skills: Array = []
		for key: String in EquipmentOrders.Technology.FAMILY_IDS: skills.append({"id": key, "label": "%s · %s" % [key, str(SiteTechnologyCatalog.get_node(key).name)]})
		_nation_ui_choice(form, "skill", "師傅本次傳授技藝", skills)
		_nation_ui_button(form, "開設最多兩席的真授課津貼單", "course")
		_nation_ui_button(form, "開始所選學生的一對一真授課", "lesson")
	elif tech_id == "N08":
		var routes: Array = []
		if has_method("nation_route_options"):
			var queried: Variant = call("nation_route_options")
			if queried is Dictionary and queried.get("ok", false) and queried.get("routes") is Array:
				for route: Variant in queried.routes:
					if route is Dictionary and route.get("label") is String: routes.append({"id": route, "label": route.label})
		_nation_ui_choice(form, "route", "原 Region 可用路線與真車船／目的倉", routes)
		if routes.is_empty(): _label(form.body, "目前沒有原 Region 可批准的具名公共運輸路線。", 14)
		_nation_ui_button(form, "批准所選原路線的四糧運輸單", "route")
		_nation_ui_button(form, "真裝四糧至本單原車船", "load_route")
		_nation_ui_button(form, "沿原 Region 行程開始運輸", "begin_route")
	elif tech_id == "N09":
		_nation_ui_choice(form, "recipient", "真原支付接收者", people)
		_nation_ui_button(form, "登記一糧有限收支單", "tax")
	elif tech_id == "N10":
		_nation_ui_choice(form, "local", "真正現任地方首長", people)
		_nation_ui_number(form, "minutes", "自目前原世界時間起有效分鐘", 60, 1440, 1)
		_nation_ui_button(form, "向所選現任首長明示有限委任並請求原隊同意", "mandate")
		_nation_ui_button(form, "以當前首長及新期限續任原單", "renew_mandate")
		_nation_ui_button(form, "開始本單真行政委任工作", "administration")
		_nation_ui_geometry(form, false)
		_nation_ui_button(form, "由本單真現任地方首長開始一格道路", "construction")
	elif tech_id == "N11":
		_nation_ui_choice(form, "arsenal_route", "軍械原工序", [{"id": "armor", "label": "真鐵甲"}, {"id": "siege", "label": "真弩砲"}])
		_nation_ui_choice(form, "host", "原甲冑作坊／器械場", _nation_ui_features(["smithy", "training_ground"]))
		_nation_ui_choice(form, "operator", "本次具名真工人", people)
		_nation_ui_button(form, "開立軍械單並請求原隊同意", "arsenal")
		_nation_ui_geometry(form, false, true)
		_nation_ui_button(form, "開始所選原單真軍械製造", "begin_arsenal")
		_nation_ui_button(form, "真製造收據後開始本單驗收行政工作", "administration")
	elif tech_id == "N12":
		_nation_ui_choice(form, "corps", "真正原軍團", _nation_ui_entries(lab.terrain.site.get("corps", {})))
		var ships: Array = []
		for key: String in vehicles.records():
			var ship: Dictionary = vehicles.records()[key]
			if SiteVehicleTransport.is_ship(ship): ships.append({"id": key, "label": "船 #%s · 原舵手 #%d" % [key, int(ship.operator_id)]})
		_nation_ui_list(form, "ships", "本次兩條原船", ships)
		_nation_ui_choice(form, "ship", "本次下令／驗收原船", ships)
		_nation_ui_button(form, "登記兩船的原軍團編制單", "fleet")
		_nation_ui_button(form, "向本單所選船真舵手下令前進一步", "command_ship")
		_nation_ui_button(form, "真到本步終點且停止後驗收此船", "accept_ship")
	if tech_id in ["N03", "N06", "N07", "N08", "N09", "N11"]:
		_nation_ui_resource_fields(form, ["grain"] if tech_id in ["N03", "N07", "N08", "N09"] else (["wood", "stone"] if tech_id == "N06" else ["wood", "iron", "fiber", "leather", "charcoal"]))
		_nation_ui_button(form, "明示核准本人本單有限用途額度", "grant_source")
		_nation_ui_button(form, "將本次数量真交入本單原倉庫", "fund")
		_nation_ui_button(form, "撤銷本人後續來源授權", "revoke_source")
	if tech_id in ["N03", "N09"]: _nation_ui_button(form, "從本單真倉庫交糧給所選接收者", "share")
	if tech_id in ["N03", "N09", "N12"]: _nation_ui_button(form, "本次真操作完成後開始制度試行行政工作", "administration")
	if tech_id == "N04" or tech_id == "N05" or tech_id in EquipmentOrders.PUBLIC_TECHNOLOGIES:
		_nation_ui_text(form, "reason", "撤銷／取消原因")
		_nation_ui_button(form, "撤銷證書" if tech_id == "N04" else "取消軍工單" if tech_id == "N05" else "撤銷本原公務单", "revoke")
		if tech_id == "N05":
			_nation_ui_button(form, "撤銷本人軍工材料授權", "revoke_military_source")
			_nation_ui_button(form, "由真現任職責人重新核准本軍工單", "renew_military")
		elif tech_id != "N04" and tech_id != "N10": _nation_ui_button(form, "由真現任職責人重新核准本原單", "renew")
	form.status.text = "%s · 請選定原對象；每次提交都重新核對現任權限與實際狀態。" % tech_id

func valid_gd_contact_work_prefix(envelope: Dictionary, prefix: Dictionary, priors: Array) -> bool:
	if _gd_contact_runtime_capture.is_empty() or _gd_contact_runtime_segment.is_empty() \
		or not is_same(priors, _gd_contact_runtime_segment.priors) or bool(_gd_contact_runtime_capture.finished): return false
	for prior: Dictionary in priors:
		if not lab.gd_mesh_work_prior_candidate(prior, priors): return false
	var found := false
	for original: Dictionary in _gd_contact_runtime_capture.envelopes: found = found or is_same(original, envelope)
	if not found or envelope.owner != self or prefix.get("owner") != self: return false
	for actual: Dictionary in _gd_contact_runtime_segment.prefixes:
		if not is_same(actual, prefix): continue
		var allocation: Dictionary = _gd_contact_runtime_segment.plan.jobs.get("runtime", {}).get(str(prefix.held.key), {})
		var identity: int = int(prefix.person_id)
		var seconds: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
		var productive: float = float(allocation.get("participant_effective_seconds", {}).get(identity, 0.0))
		return seconds >= 0.0 and seconds <= float(_gd_contact_runtime_segment.seconds) + PersonFatigue.WORK_PLAN_EPS \
			and productive >= 0.0 and productive <= seconds + PersonFatigue.WORK_PLAN_EPS \
			and is_equal_approx(float(prefix.actual_seconds), seconds) and is_equal_approx(float(prefix.productive_seconds), productive) \
			and is_equal_approx(float(prefix.applied_productive_seconds), productive * float(prefix.start.productivity) * float(prefix.start.progress_multiplier)) \
			and is_same(prefix.held, envelope.prepared.prefix_ref.held) and is_same(prefix.plan, _gd_contact_runtime_segment.plan) \
			and is_same(prefix.task, envelope.prepared.task) and is_same(prefix.target_ref, envelope.target) \
			and is_same(prefix.work_unit, envelope.unit) and identity == int(envelope.prepared.identity)
	return false

func _gd_mesh_supply_life(members: Dictionary, reader: Callable) -> Dictionary:
	var life: Dictionary = {}
	for identity: int in members:
		if not members[identity] is Dictionary: return Runtime.fail("INVALID_SUSTAIN", "Supply member must be a Dictionary")
		var hp: Variant = Sustain._member_value(members, identity, &"hp", reader)
		var ko: Variant = Sustain._member_value(members, identity, &"ko", reader)
		var captive: Variant = Sustain._member_value(members, identity, &"captive", reader)
		if not Sustain._number(hp, 0.0) or not Sustain._number(ko, 0.0) or not captive is bool:
			return Runtime.fail("INVALID_SUSTAIN", "Supply HP/KO must be finite nonnegative numbers and captive must be bool")
		life[identity] = {"hp": float(hp), "ko": float(ko), "captive": captive}
	return Runtime.ok("", {"life": life})

func _gd_mesh_supply_reader(members: Dictionary) -> Callable:
	# No captured hot column: packed arrays can detach on the real contact write.
	return func(identity: int, field: StringName) -> Variant:
		var person: Dictionary = _supply_person(identity)
		if person.is_empty(): return members.get(identity, {}).get(String(field))
		if int(person.unit) < 0:
			if field == &"ko": return person.get("ko") # Actor exposes knockout_left through the original person adapter.
			if field == &"present": return members.get(identity, {}).get("present")
		return person_actions._body_get(person, String(field))

func gd_contact_runtime_person_ready(identity: int) -> bool:
	if _gd_contact_runtime_capture.is_empty() or not _gd_contact_runtime_capture.people.has(identity): return false
	var held: Dictionary = _gd_contact_runtime_capture.people[identity]
	var prefix: Dictionary = held.prefix
	var start: Dictionary = prefix.start
	var person: Dictionary = person_actions._person(identity)
	if person.is_empty() or person.owner != start.owner or int(person.unit) != int(start.unit) \
		or not is_same(person.body, start.body) or not is_same(person.holder, start.item_state) or not is_same(person.cargo, start.cargo) \
		or not is_same(lab.terrain.site.get(str(prefix.held.key)), prefix.task) or int(person.hit) != int(held.hit) \
		or person.cell != start.cell or bool(person.captive) or bool(person.moving): return false
	var intent: Dictionary = prefix.task.duplicate(false)
	for field: String in ["progress", "status", "cargo"]: intent.erase(field)
	return intent == held.intent and (person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act())

func publish_gd_contact_runtime_segment(segment: Dictionary) -> void:
	assert(is_same(segment, _gd_contact_runtime_segment) and not bool(segment.published))
	for candidate: Dictionary in segment.runtime:
		Runtime.publish_checked_work_prefix(candidate)
		_gd_contact_runtime_capture.priors.append(candidate)
	for prefix: Dictionary in segment.prefixes:
		lab._shared_runtime_consumed[str(prefix.held.key)] = true
		var person: Dictionary = person_actions._person(int(prefix.person_id))
		if person.is_empty() or bool(person.player): continue
		if float(prefix.actual_seconds) > 0.0: person_actions._body_set(person, "work_resting", false)
		if str(prefix.allocation.get("participant_paused", {}).get(int(prefix.person_id), prefix.allocation.get("paused", ""))) == "REST":
			person_actions._body_set(person, "work_resting", true)
	_gd_contact_runtime_capture.elapsed = float(_gd_contact_runtime_capture.elapsed) + float(segment.seconds)
	_gd_contact_runtime_capture["published"].append(segment)
	segment["published"] = true
	_gd_contact_runtime_segment = {}

func publish_gd_mesh_supply_segment(prepared: Dictionary, seconds: float) -> void:
	assert(prepared.owner == self and seconds > 0.0 and float(prepared.elapsed) + seconds <= float(prepared.seconds) + PersonFatigue.WORK_PLAN_EPS)
	for row: Dictionary in prepared.rows:
		var was_routed: bool = bool(row.state.routed)
		if row.kind == "team":
			# Actual original ordered contacts are now reflected in this life
			# checkpoint BEFORE the next positive hunger/morale segment.
			_observe_team_life(row.owner, row.entry, row.members, row.reader)
		var state: Dictionary = row.state.duplicate(true)
		var stock: Dictionary = row.stock.duplicate(true)
		var context: Dictionary = row.context.duplicate(false)
		context["hot_read"] = row.reader
		if row.kind == "team":
			# Actual endpoint geometry/life, not optimistic BEGIN safe/stopped.
			context["safe"] = _team_safe(row.owner, row.members)
			context["stopped"] = _team_stopped(row.owner, true)
		context["pending_hp"] = {}
		var outcome: Dictionary = Sustain.advance_to(state, row.members, stock, float(state.at) + seconds, context)
		assert(outcome.ok and float(outcome.consumed_rations) == 0.0 and outcome.damage.is_empty())
		row.state.clear()
		row.state.merge(state)
		if row.kind == "team":
			_publish_sustain_team_commands(row.owner, row.entry, was_routed, outcome, seconds, bool(context.safe), bool(context.stopped))
	prepared["elapsed"] = float(prepared.elapsed) + seconds

func finish_gd_contact_runtime_prefix() -> void:
	if _gd_contact_runtime_capture.is_empty() or bool(_gd_contact_runtime_capture.finished): return
	_gd_contact_runtime_capture.finished = true
	var last: Array[Dictionary] = []
	for candidate: Dictionary in _gd_contact_runtime_capture.priors:
		for index: int in range(last.size() - 1, -1, -1):
			if is_same(last[index].unit, candidate.unit): last.remove_at(index)
		last.append(candidate)
	for candidate: Dictionary in last: Runtime.settle_checked_work_prefix(candidate)
	Runtime.release_checked_segment_links(_gd_contact_runtime_capture.get("published"))
	_gd_contact_runtime_capture = {}
	_gd_contact_runtime_segment = {}

func finish_shared_runtime_clock() -> void:
	# AFTER Native pub AND all true current work endpoints. Runtime uses the
	# existing exact minute/ship helpers once; it never advances elapsed again.
	var clock: Dictionary = checked_runtime_clock_interval()
	if clock.is_empty() or bool(clock.get("consumed", false)): return
	Runtime.finish_checked_work_clock(lab.terrain, clock, reserves_cell)
	discard_checked_runtime_work_prefix()

func _native_held_runtime_ready(identity: int, task: Dictionary) -> bool:
	if not _crowd_active() or not lab.crowd_site.contains_person(identity): return true
	if not lab.crowd_site.work_fatigue_work_start_ready(identity): return false
	var person: Dictionary = person_actions._person(identity, false)
	if person.is_empty() or not person.owner is CrowdPersonOwner or not person_actions._ready(person) or _person_has_duty(identity): return false
	if str(task.get("target", "")).is_empty() or not lab.terrain.contains(person.cell): return false
	var actual: int = lab.terrain.index(person.cell)
	return actual == int(task.get("work_cell", task.get("cell", -1))) and actual == int(task.get("cell", -1))

func prepare_shared_native_training_requests(seconds: float, combat_left: float) -> Dictionary:
	_shared_native_training_prefixes = {}
	if not _crowd_active(): return Runtime.ok("", {"requests": []})
	var requests: Array[Dictionary] = []
	for owner: RefCounted in lab.crowd_site.person_owners():
		var entry: Dictionary = lab.terrain.site.get("team_supply", {}).get(str(owner.team_id), {})
		if entry.is_empty() or not bool(entry.get("training_order", false)): continue
		# Existing Sustain zero-time resupply is already settled and its true
		# coverage interval clipped. Refresh ORIGINAL World input before start
		# qualification; old previous-tick fully_fed is not today's authority.
		var fed: bool = not entry.sustain.cohorts.is_empty()
		for cohort: Dictionary in entry.sustain.cohorts: fed = fed and float(cohort.coverage) >= 1.0
		lab.crowd_site.set_sustain_input(int(owner.formation_index), fed, 0.0)
		var prepared: Dictionary = TrainingGround.prepare_native_work_prefix(self, owner, entry, seconds, combat_left)
		if not prepared.ok: return prepared
		if prepared.held.is_empty(): continue
		_shared_native_training_prefixes[int(owner.formation_index)] = prepared.held
		requests.append_array(prepared.requests)
	return Runtime.ok("原Native训练参与者已纳入共同pool", {"requests": requests})

func _checked_runtime_target(task: Dictionary) -> Dictionary:
	var target: String = str(task.get("target", ""))
	if target.begins_with("feature:"): return lab.terrain.site.features.get(target.trim_prefix("feature:"), {})
	if target == "depot": return lab.terrain.site
	return lab.terrain.resource_base.get(target, {})

func _checked_runtime_unit(task: Dictionary, target: Dictionary) -> Dictionary:
	if not str(task.get("target", "")).begins_with("feature:"): return task
	var action: String = str(task.get("action", ""))
	return target.get("repair", {}) if action == "repair" else target.get("pending_build", target) if action == "construct" else target

func _shared_runtime_request_source(request: Dictionary) -> Dictionary:
	if request.get("provider") != "runtime" or request.get("key") not in ["worker", "manual"] or not request.get("participants") is Array or request.participants.size() != 1: return {}
	var key: String = str(request.key)
	var actor: TerrainTestCharacter = lab.character if key == "manual" else lab.npc
	var task: Dictionary = lab.terrain.site.get(key, {})
	if actor == null or not bool(_shared_worker_inputs.get(key + "_ready", false)) or not is_same(request.get("task"), task) or int(request.participants[0].get("person_id", 0)) != int(actor.person_id): return {}
	var person: Dictionary = person_actions._person(int(actor.person_id))
	if person.is_empty() or not is_same(person.body, actor) or not is_same(person.cargo, task.get("cargo")) or not is_same(person.holder, actor.item_state): return {}
	return {"key": key, "actor": actor, "task": task, "person": person,
		"carry_limit": int(_shared_worker_inputs.get(key + "_limit", 0))}

func _shared_runtime_source_ready(source: Dictionary) -> bool:
	# Original camp/manual work is already accepted by its owner. PA._ready
	# checks idle admission of a NEW job and deliberately rejects this task.
	# Preserve original ongoing-work qualification; never clear/clone activity.
	if source.is_empty(): return false
	var actor: TerrainTestCharacter = source.actor
	var person: Dictionary = source.person
	var task: Dictionary = source.task
	if actor == null or not lab.actor_present(actor) or not is_same(person.body, actor) or person.cell != lab.terrain.cell_from_index(int(task.get("cell", -1))) or _person_has_duty(int(person.person_id)): return false
	if person.owner is CrowdPersonOwner:
		return _native_held_runtime_ready(int(person.person_id), task)
	if person.owner != actor or not actor.can_act() or actor.is_moving() or actor.action_time > 0.0 or actor.guarding or actor.guard_transition_left > 0.0 or actor.guard_break_left > 0.0 or actor._rescue_left > 0.0: return false
	return actor != lab.npc or actor.visible

func bind_checked_runtime_work_prefix() -> void:
	if lab != null and lab.terrain != null: lab.terrain.set_meta(&"site_controller", weakref(self))

func _checked_runtime_refs_valid(held: Dictionary) -> bool:
	var person: Dictionary = person_actions._person(int(held.person_id))
	var start: Dictionary = held.start
	# Current HP/hit/position may reject the later endpoint, never erase real
	# positive work accepted at this same original start. No fabricated life.
	return not person.is_empty() and person.owner == start.owner and int(person.unit) == int(start.unit) \
		and is_same(person.body, start.body) and is_same(person.cargo, start.cargo) and is_same(person.holder, start.item_state) \
		and is_same(lab.terrain.site.get(str(held.key)), held.task) and held.task == start.task_values \
		and start.cargo == start.cargo_values and start.item_state == start.item_values \
		and is_same(_checked_runtime_target(held.task), held.target_ref) and is_same(_checked_runtime_unit(held.task, held.target_ref), start.work_unit)

func _siege_build_ui_team(form: Dictionary) -> Variant:
	if lab == null or lab.terrain == null: return null
	if bool(form.get("trial", false)):
		if not form.has("siege_team") or form.siege_team.selected < 0: return null
		var selected_team: int = int(form.siege_team.get_item_metadata(form.siege_team.selected))
		for team: Variant in _siege_ui_teams():
			if int(team.team_id) == selected_team: return team
		return null
	if _crowd_active():
		var controlled: Dictionary = person_actions._person(lab.controlled_person_id())
		return controlled.owner if not controlled.is_empty() and controlled.owner is CrowdPersonOwner and controlled.owner.has_army() else null
	return lab.player_army()

func _irrigation_choice(choice: OptionButton) -> String:
	return str(choice.get_item_metadata(choice.selected)) if choice.selected >= 0 else ""

func _irrigation_controls() -> Dictionary:
	return _formal_columns.construction.get_meta(&"irrigation_form", {}) if _formal_columns.has("construction") else {}

func _nation_ui_button(form: Dictionary, label: String, action: String) -> void:
	_button(form.body, label, "NationOperation_" + action, func() -> void: _nation_ui_submit(form, action))

func _nation_ui_choice(form: Dictionary, key: String, title: String, rows: Array) -> OptionButton:
	_label(form.body, title, 14)
	var choice := _options(form.body, ["請選擇"], "NationOperation_" + key)
	choice.set_item_metadata(0, "")
	for row: Dictionary in rows:
		choice.add_item(str(row.label))
		choice.set_item_metadata(choice.item_count - 1, row.id)
	form.controls[key] = choice
	return choice

func _nation_ui_entries(records: Dictionary) -> Array:
	var rows: Array = []
	for key: String in records:
		var record: Dictionary = records[key]
		rows.append({"id": key, "label": "%s · %s%s" % [key, str(record.get("name", record.get("status", ""))),
			" · 已接受 %d 次" % record.get("receipts", record.get("receipt_ids", [])).size()]})
	return rows

func _nation_ui_features(kinds_filter: Array) -> Array:
	var rows: Array = []
	for key: String in lab.terrain.site.get("features", {}):
		var feature: Dictionary = lab.terrain.site.features[key]
		if str(feature.get("kind", "")) in kinds_filter and str(feature.get("stage", "")) == "complete":
			rows.append({"id": key, "label": "#%s · %s" % [key, str(Runtime.FEATURES.get(str(feature.kind), {}).get("name", feature.kind))]})
	return rows

func _nation_ui_geometry(form: Dictionary, house: bool, siege: bool = false) -> void:
	_label(form.body, "本次施工位置；不移動人物或隊伍。操作者須已在原工位。", 14)
	_nation_ui_number(form, "x", "地圖 X", selected.x, lab.terrain.size.x - 1)
	_nation_ui_number(form, "y", "地圖 Y", selected.y, lab.terrain.size.y - 1)
	if siege:
		_nation_ui_choice(form, "facing", "器械朝向", [{"id": Vector2i.RIGHT, "label": "東"}, {"id": Vector2i.DOWN, "label": "南"}, {"id": Vector2i.LEFT, "label": "西"}, {"id": Vector2i.UP, "label": "北"}])
	else:
		_nation_ui_number(form, "width", "占地寬", 3 if house else 1, 3 if house else 1, 3 if house else 1)
		_nation_ui_number(form, "depth", "占地深", 3 if house else 1, 3 if house else 1, 3 if house else 1)

func _nation_ui_list(form: Dictionary, key: String, title: String, rows: Array) -> ItemList:
	_label(form.body, title + "（Ctrl／Shift 多選）", 14)
	var list := ItemList.new()
	list.name = "NationOperation_" + key
	list.select_mode = ItemList.SELECT_MULTI
	list.custom_minimum_size = Vector2(700, 115)
	form.body.add_child(list)
	for row: Dictionary in rows:
		var index := list.add_item(str(row.label))
		list.set_item_metadata(index, row.id)
	form.controls[key] = list
	return list

func _nation_ui_number(form: Dictionary, key: String, title: String, value: float, maximum: float = 1000000.0, minimum: float = 0.0) -> SpinBox:
	var row := HBoxContainer.new()
	form.body.add_child(row)
	_label(row, title, 14)
	var input := SpinBox.new()
	input.name = "NationOperation_" + key
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1.0
	input.value = value
	row.add_child(input)
	form.controls[key] = input
	return input

func _nation_ui_order_summary(form: Dictionary, summary: Label) -> void:
	if lab.terrain != form.data or lab.controlled_person_id() != int(form.requester):
		summary.text = "原人物或 Site 已變更；請重開。"
		return
	var nation_id := str(form.nation_choice.get_item_metadata(form.nation_choice.selected))
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	var order_id := str(form.controls.order.get_item_metadata(form.controls.order.selected))
	var records: Dictionary = nation.get("technology_operations", {}).get("orders" if str(form.technology.get_item_metadata(form.technology.selected)) == "N05" else "public_orders", {})
	var order: Dictionary = records.get(order_id, {})
	if order.is_empty(): summary.text = "請選原工單"; return
	var source: Dictionary = order.get("source", order.get("payload", {}).get("source", {}))
	var cost: Dictionary = Runtime.RANGED_RECIPES.bow.cost if records == nation.get("technology_operations", {}).get("orders", {}) else equipment_orders._public_cost(str(order.tech_id), order.payload)
	summary.text = "狀態 %s · 已接受 %d 次\n本單成本：%s\n本人授權：%s · 已交：%s" % [str(order.status), order.get("receipt_ids", order.get("receipts", [])).size(),
		_nation_ui_stack_text(cost), _nation_ui_stack_text(source.get("cap", {})), _nation_ui_stack_text(source.get("spent", {}))]

func _nation_ui_people() -> Array:
	var identities := {int(lab.controlled_person_id()): true}
	for actor: TerrainTestCharacter in lab.combat_actors:
		if is_instance_valid(actor): identities[int(actor.person_id)] = true
	if _crowd_active():
		for owner: RefCounted in lab.crowd_site.person_owners():
			for unit: int in owner.combat_units: identities[int(owner.combat_identity(unit))] = true
	else:
		for team: TerrainArmy in lab.combat_armies:
			for unit: int in team.command_members(): identities[int(team.combat_identity(unit))] = true
	var keys: Array = identities.keys()
	keys.sort()
	var rows: Array = []
	for identity: int in keys:
		var person: Dictionary = person_actions._person(identity, false)
		if person.is_empty() or float(person.hp) <= 0.0: continue
		rows.append({"id": identity, "label": "#%d%s" % [identity, " · 目前受控" if identity == lab.controlled_person_id() else ""]})
	return rows

func _nation_ui_resource_fields(form: Dictionary, resources: Array, procurement: bool = false) -> void:
	_label(form.body, "每項數量（0 表示本次不交）；核額與交物為兩個明示操作。" if not procurement else "每項交付／單批上限／總上限；0 不列入規格。", 14)
	for resource: String in resources:
		var row := HBoxContainer.new()
		form.body.add_child(row)
		_label(row, str(Env.ITEM_NAMES.get(resource, resource)), 14)
		var fields := {}
		for field: String in (["quantity", "batch", "total"] if procurement else ["quantity"]):
			var input := SpinBox.new()
			input.min_value = 0
			input.max_value = 1000000
			input.step = 1
			input.tooltip_text = {"quantity": "本次交付／核額數量", "batch": "單批上限", "total": "總上限"}[field]
			row.add_child(input)
			fields[field] = input
		form.resources[resource] = fields

func _nation_ui_text(form: Dictionary, key: String, hint: String) -> LineEdit:
	var input := LineEdit.new()
	input.name = "NationOperation_" + key
	input.placeholder_text = hint
	form.body.add_child(input)
	form.controls[key] = input
	return input

func gd_contact_runtime_candidate(candidate: Dictionary) -> bool:
	for actual: Dictionary in _gd_contact_runtime_capture.get("priors", []):
		if is_same(actual, candidate): return true
	for actual: Dictionary in _gd_contact_runtime_segment.get("runtime", []):
		if is_same(actual, candidate): return true
	return false

func _publish_sustain_team_commands(team: TerrainArmy, entry: Dictionary, was_routed: bool, outcome: Dictionary, seconds: float, safe: bool, stopped: bool) -> void:
	if bool(entry.sustain.routed) and not was_routed:
		_start_supply_rout(team)
	elif bool(entry.sustain.routed) and not team.morale_retreat_terminal() and team.combat_order == TerrainArmy.CombatOrder.HOLD and stopped and not safe:
		# A HOLD order cannot permanently cancel an available forced escape.
		# Bounded game-time review, not a path search on every combat sample.
		_supply_rout_review[team.team_id] = float(_supply_rout_review.get(team.team_id, 0.0)) + seconds
		if float(_supply_rout_review[team.team_id]) >= 2.0:
			_supply_rout_review[team.team_id] = 0.0
			_start_supply_rout(team)
	if bool(outcome.regrouped):
		team.finish_morale_retreat()

func checked_runtime_clock_interval() -> Dictionary:
	return _checked_runtime_work_capture.get("clock", {})

func discard_checked_runtime_work_prefix() -> void:
	Runtime.release_checked_prefix_links(_checked_runtime_work_preparing.get("prefixes"))
	Runtime.release_checked_prefix_links(_gd_contact_runtime_segment.get("prefixes"))
	Runtime.release_checked_segment_links(_gd_contact_runtime_capture.get("published"))
	_checked_runtime_work_capture = {}
	_gd_contact_runtime_capture = {}
	_gd_contact_runtime_segment = {}
	_checked_runtime_work_preparing = {}
	_checked_runtime_work_admission = {}

func _nation_ui_stack_text(stack: Dictionary) -> String:
	var entries: PackedStringArray = []
	for resource: String in stack:
		entries.append("%s × %d" % [str(Env.ITEM_NAMES.get(resource, resource)), int(stack[resource])])
	return "、".join(entries) if not entries.is_empty() else "無"

func valid_checked_runtime_clock(clock: Dictionary, seconds: float) -> bool:
	if clock.get("owner") != self or not is_same(clock, checked_runtime_clock_interval()) or not is_same(clock.get("site"), lab.terrain.site) or not is_finite(seconds) or absf(seconds - float(clock.seconds)) > PersonFatigue.WORK_PLAN_EPS or bool(clock.get("consumed", false)): return false
	if not bool(clock.get("advanced", false)):
		return int(lab.terrain.site.minute) == int(clock.minute) and float(lab.terrain.site.phase) == float(clock.phase) and float(lab.terrain.site.combat_left) == float(clock.combat_left)
	# Native contacts may legitimately refresh combat_left after this clock
	# advanced. The same source owner, interval, phase and once guard still apply.
	return int(lab.terrain.site.minute) == int(clock.minute_after) and float(lab.terrain.site.phase) == float(clock.phase_after)

var _gd_contact_runtime_capture: Dictionary = {}

var _gd_contact_runtime_segment: Dictionary = {}

var _shared_native_training_prefixes: Dictionary = {} # Same point only; never saved.
var _shared_native_delivery_prefixes: Dictionary = {} # P1p: crowd deliveries of the same point only; never saved.

var _checked_runtime_work_capture: Dictionary = {}

var _checked_runtime_work_preparing: Dictionary = {}

var _checked_runtime_work_admission: Dictionary = {}

func _refresh_settlement_engineering_controls() -> void:
	if not _formal_columns.has("construction") or not _formal_columns.construction.has_meta(&"settlement_engineering_form"): return
	var form: Dictionary = _formal_columns.construction.get_meta(&"settlement_engineering_form")
	var view := settlement_engineering_view()
	if not view.ok:
		form.status.text = str(view.message)
		for key: String in ["save", "delete", "preview", "reuse", "add_build", "add_repair", "request", "begin", "resume", "cancel", "remove"]: form[key].disabled = true
		return
	var signature := JSON.stringify([view.plans, view.orders])
	if signature != str(form.signature):
		var selected_plan := _settlement_engineering_choice(form.plans)
		var selected_order := _settlement_engineering_choice(form.orders)
		form.plans.clear()
		for key: String in view.plans:
			form.plans.add_item(str(view.plans[key].name) + " · " + str(view.plans[key].kind))
			form.plans.set_item_metadata(form.plans.item_count - 1, key)
			if key == selected_plan: form.plans.select(form.plans.item_count - 1)
		form.orders.clear()
		for key: String in view.orders:
			var order: Dictionary = view.orders[key]
			if order.kind != "defense": continue
			form.orders.add_item(key + " · " + str(order.status) + " · " + str(int(order.next_step)) + "/" + str(order.steps.size()))
			form.orders.set_item_metadata(form.orders.item_count - 1, key)
			if key == selected_order: form.orders.select(form.orders.item_count - 1)
		form["signature"] = signature
	form.status.text = str(view.read_only_reason) if not str(view.read_only_reason).is_empty() else "所選格 %s；所選建物 %s。方案每次重新核占地／人員／權限／完整材料。" % [str(selected), feature_key]
	var lines: Array[String] = []
	for step: Dictionary in form.steps:
		var target: String = str(view.plans.get(str(step.plan_id), {}).get("name", "方案已移除")) if step.action == "construct" else "建物 #" + str(step.feature_id) + "／" + str(step.part)
		lines.append("%d. %s · %s · 原人 #%d" % [lines.size() + 1, "施工" if step.action == "construct" else "維護", target, int(step.operator_id)])
	form.steps_label.text = "尚未加入清單步驟。每步使用目前選中的原人。" if lines.is_empty() else "\n".join(lines)
	var can_plan: bool = bool(view.can_command) and bool(view.effective) and bool(view.blueprints_available)
	var can_work: bool = bool(view.can_command) and bool(view.effective) and bool(view.defense_available)
	for key: String in ["save", "delete", "preview", "reuse"]: form[key].disabled = not can_plan
	for key: String in ["add_build", "add_repair", "request", "begin", "resume"]: form[key].disabled = not can_work
	# Effect suspension still permits the current original head to stop/release.
	form.cancel.disabled = not bool(view.can_command)
	form.remove.disabled = not bool(view.can_command)

func prepare_native_sustain_point(seconds: float, requests: Array, planned: Dictionary = {}) -> Dictionary:
	if not _crowd_active() or not is_finite(seconds) or seconds <= 0.0 or lab._region_deferring_endpoint(): return Runtime.fail("CLOCK_NOT_READY")
	var rows: Array[Dictionary] = []
	var payments: Array[Dictionary] = []
	var seen: Dictionary = {}
	for request: Dictionary in requests:
		if not str(request.get("paused", "")).is_empty(): continue
		if not planned.is_empty() and float(planned.jobs.get(str(request.provider), {}).get(str(request.key), {}).get("actual_seconds", 0.0)) <= 0.0: continue
		if not request.get("payment_source") is Dictionary or not request.get("payment") is Dictionary: continue
		var key: String = str(request.get("payment_key", str(request.provider) + ":" + str(request.key)))
		if seen.has(key): continue
		seen[key] = true
		payments.append({"cargo": request.payment_source, "cost": request.payment})
	var original_rows: Dictionary = _native_sustain_original_rows(seconds)
	if not original_rows.ok: return original_rows
	rows = original_rows.rows
	# Preserve original personal-then-team order even when two original meal
	# sources borrow the same physical inventory/location.
	var ordered_rows: Array[Dictionary] = []
	for row: Dictionary in rows:
		if row.held.kind == "personal": ordered_rows.append(row)
	for row: Dictionary in rows:
		if row.held.kind == "team": ordered_rows.append(row)
	rows = ordered_rows
	var prior_lower: Array = []
	var prior_upper: Array = payments.duplicate(false)
	for row: Dictionary in rows:
		for cohort: Dictionary in row.held.state_values.cohorts:
			var until: float = float(cohort.meal_until) - float(row.held.state_values.at)
			if until <= 0.0 or seconds > until: return Runtime.fail("SUPPLY_ENDPOINT_NOT_SETTLED")
		var lower: Dictionary = _native_sustain_point_projection(row.held, prior_lower)
		if not lower.ok: return lower
		var upper: Dictionary = _native_sustain_point_projection(row.held, prior_upper)
		if not upper.ok: return upper
		if row.held.kind == "team" and (lower.fully_fed != upper.fully_fed or float(lower.morale_delta) != float(upper.morale_delta)):
			return Runtime.fail("SUPPLY_WORK_ENDPOINT_COLLISION")
		if lower.damage != upper.damage: return Runtime.fail("SUPPLY_WORK_ENDPOINT_COLLISION")
		row.input = lower
		prior_lower.append_array(_native_sustain_projection_debits(lower))
		prior_upper.append_array(_native_sustain_projection_debits(upper))
	return Runtime.ok("原共同供養input在首cost前固定", {"owner": self, "site": lab.terrain.site, "seconds": seconds, "rows": rows, "published": false})

func retime_shared_native_training_begin(seconds: float, requests: Array, begin: Dictionary) -> Dictionary:
	# Only the SAME original Lab's registered pure BEGIN may shorten its held
	# training interval. No new inspect/selector, body setter, growth or charge.
	if not lab.valid_native_begin_shared_window(begin) or not is_finite(seconds) or seconds <= 0.0 \
		or seconds != float(begin.game_seconds) or not is_same(requests, begin.requests): return Runtime.fail("STALE_INTERVAL")
	for held: Dictionary in _shared_native_training_prefixes.values():
		if seconds > float(held.seconds) + PersonFatigue.WORK_PLAN_EPS: return Runtime.fail("INVALID_INTERVAL")
		for identity: int in held.people:
			var found: bool = false
			for request: Dictionary in requests:
				if str(request.provider) == "training" and str(request.key) == str(identity) \
					and request.participants.size() == 1 and is_same(request.participants[0], held.people[identity].participant): found = true; break
			if not found: return Runtime.fail("STALE_SOURCE")
	for held: Dictionary in _shared_native_training_prefixes.values(): held.seconds = seconds
	return Runtime.ok("Original held training interval retimed without growth/effort")

func validate_native_sustain_point(prepared: Dictionary, runtime_priors: Array = []) -> Dictionary:
	if prepared.get("owner") != self or not is_same(prepared.get("site"), lab.terrain.site) or prepared.get("published") != false:
		return Runtime.fail("STALE_SOURCE")
	var payments: Array[Dictionary] = []
	for prior: Dictionary in runtime_priors:
		if not prior.get("payment", {}).is_empty(): payments.append(prior.payment)
	var candidates: Array[Dictionary] = []
	for row: Dictionary in prepared.rows:
		var held: Dictionary = row.held
		if held.kind == "team":
			if not is_same(_supply_entry(held.owner), held.entry) or not is_same(held.entry.get("sustain"), held.state) \
				or not is_same(_supply_stock(held.entry), held.stock) or int(held.entry.revision) != int(held.revision): return Runtime.fail("STALE_SOURCE")
		else:
			var current: Dictionary = _supply_person(int(held.owner_id))
			if current.is_empty() or not is_same(lab.terrain.site.get("person_supply", {}).get(held.owner_id), held.state) \
				or not is_same(current.holder, held.entry) or not is_same(current.cargo, held.stock) or held.entry != held.holder_values:
				return Runtime.fail("STALE_SOURCE")
		if held.state != held.state_values or held.stock != held.stock_values: return Runtime.fail("STALE_SOURCE")
		for source: Dictionary in held.stock_sources:
			if not source.key.is_empty() and (not is_same(held.stock.get(source.key), source.location) \
				or not is_same(source.location.get("inventory"), source.inventory)): return Runtime.fail("STALE_SOURCE")
		var candidate: Dictionary = _native_sustain_point_projection(held, payments)
		if not candidate.ok: return candidate
		if held.kind == "team" and (candidate.fully_fed != row.input.fully_fed or float(candidate.morale_delta) != float(row.input.morale_delta) or candidate.damage != row.input.damage):
			return Runtime.fail("SUPPLY_WORK_ENDPOINT_COLLISION")
		candidates.append(candidate)
		payments.append_array(_native_sustain_projection_debits(candidate))
	return Runtime.ok("原Sustain來源與前序真支付已純核", {"prepared": prepared, "candidates": candidates})

func publish_native_sustain_inputs(prepared: Dictionary) -> void:
	# Original input setters only: no meal cost, hunger state, HP or clock writes.
	for row: Dictionary in prepared.rows:
		if row.held.kind != "team": continue
		lab.crowd_site.set_sustain_input(int(row.held.owner.formation_index), bool(row.input.fully_fed), float(row.input.morale_delta))

func _settlement_engineering_choice(choice: OptionButton) -> String:
	return str(choice.get_item_metadata(choice.selected)) if choice.selected >= 0 and choice.selected < choice.item_count else ""

func settlement_engineering_view() -> Dictionary:
	if lab == null or lab.terrain == null: return SiteRuntime.fail("NO_SITE")
	var owner: Variant = load("res://scripts/terrain_lab/site_settlement.gd")
	var settlement: Dictionary = owner.call("record", lab.terrain)
	if settlement.is_empty(): return SiteRuntime.fail("UNREGISTERED")
	var operations: Variant = settlement.get("technology_operations")
	if operations != null and not owner.call("valid_technology_operations", lab.terrain, operations): return SiteRuntime.fail("CORRUPT_STATE")
	var status: Dictionary = owner.call("status", lab)
	var duty: Dictionary = person_actions._technology_scope_duty("settlement", settlement, true)
	var enabled9: bool = SiteTechnologyCatalog.get_node("S09").get("enabled") == true
	var enabled10: bool = SiteTechnologyCatalog.get_node("S10").get("enabled") == true
	return SiteRuntime.ok("", {"settlement_id": str(settlement.settlement_id), "effective": bool(status.get("effective", false)),
		"can_command": bool(duty.get("ok", false)) and int(duty.get("decider", -1)) == int(person_actions._technology_controlled()),
		"blueprints_available": enabled9 and SiteTechnology.scope_known(settlement.get("technology", {}), "S09"),
		"defense_available": enabled10 and SiteTechnology.scope_known(settlement.get("technology", {}), "S10"),
		"plans": operations.get("plans", {}).duplicate(true) if operations is Dictionary else {},
		"orders": operations.get("orders", {}).duplicate(true) if operations is Dictionary else {},
		"source_feature_id": feature_key, "anchor": selected, "read_only_reason": "真实操作和命名验收未发布" if not enabled9 or not enabled10 else ""})

func _nation_arsenal_request(nation_id: String, order_id: String, order: Dictionary, preview: bool, work_target: Dictionary = {}) -> Dictionary:
	if order.get("tech_id") != "N11" or order.get("scope_site_id") != str(lab.terrain.site.id) \
		or order.get("scope_nation_id") != nation_id or not EquipmentOrders._valid_public_order(order, {}, {}, order_id): return Runtime.fail("INVALID")
	if preview:
		# The original request owner has checked this not-yet-stored candidate,
		# current command authority and explicit original team consent. Only
		# original host/person/industry/definition availability is projected here.
		var host: Dictionary = equipment_orders._arsenal_workshop_context(order)
		if not host.ok: return host
		if order.payload.route == "armor":
			if Runtime.FEATURE_RECIPES.get("smithy", {}).get("iron_armor", {}).is_empty(): return Runtime.fail("NO_RECIPE")
		elif Runtime.SIEGE_DEFINITIONS.get("ballista", {}).is_empty(): return Runtime.fail("NO_RECIPE")
		return Runtime.ok("原作坊、原操作者與實際配方可登記具名軍械單；尚未付款或派工")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	var actual: Dictionary = nation.get("technology_operations", {}).get("public_orders", {}).get(order_id, {})
	if actual.is_empty() or actual != order or int(actual.authorizer_id) != int(lab.controlled_person_id()): return Runtime.fail("STALE_ORDER")
	if int(actual.project_id) == 0:
		return Runtime.begin_nation_technology_operation(lab.terrain, nation_id, order_id, false, work_target)
	var binding := "ballista_build" if actual.payload.route == "siege" else "iron_armor"
	var target := "vehicle:" + str(int(lab.terrain.site.next_vehicle)) if actual.payload.route == "siege" else "feature:" + str(actual.payload.host_id)
	return person_actions.begin_scope_technology_phase(int(lab.controlled_person_id()), "nation", nation_id, binding, target, work_target)

func _nation_build_request(nation_id: String, order_id: String, request: Dictionary, preview: bool) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	var order: Dictionary = nation.get("technology_operations", {}).get("public_orders", {}).get(order_id, {})
	if order.is_empty() or order.tech_id not in ["N02", "N06", "N10"] or not request.get("cells") is Array: return Runtime.fail("NO_TARGET")
	var requester := int(lab.controlled_person_id())
	var expected := int(order.payload.local_person_id) if order.tech_id == "N10" else int(order.authorizer_id)
	if requester != expected or int(request.get("requester_id", -1)) != requester: return Runtime.fail("NO_AUTHORITY")
	var cells: Array[int] = []
	for index: Variant in request.cells:
		if not EquipmentOrders.Technology.integer(index, 0, lab.terrain.size.x * lab.terrain.size.y - 1): return Runtime.fail("INVALID")
		cells.append(int(index))
	var binding := "house_build" if order.tech_id == "N06" else "road_build"
	var work_target := {"cells": cells, "options": {}}
	if int(order.project_id) == 0: return Runtime.begin_nation_technology_operation(lab.terrain, nation_id, order_id, preview, work_target)
	var target := "feature:" + str(int(lab.terrain.site.next_feature))
	var selected_phase: Dictionary = person_actions._nation_phase_token(nation_id, order_id, binding, target)
	if not selected_phase.ok: return selected_phase
	if selected_phase.token.is_empty(): return Runtime.fail("STALE_PROJECT")
	return Runtime.begin_technology_operation(lab.terrain, selected_phase.token, preview, work_target)

func publish_native_sustain_point(checked: Dictionary) -> void:
	# Called after common host work/payment and native publishers. Write only
	# Sustain's own meal debit delta, preserving other accepted cargo costs.
	for candidate: Dictionary in checked.candidates:
		var held: Dictionary = candidate.held
		for source: Dictionary in held.stock_sources:
			var before: Dictionary = candidate.before_food if source.key.is_empty() else candidate.before_food[source.key].inventory
			var after: Dictionary = candidate.stock if source.key.is_empty() else candidate.stock[source.key].inventory
			for food: String in Sustain.FOODS:
				var amount: int = int(before.get(food, 0)) - int(after.get(food, 0))
				if amount > 0: source.inventory[food] = int(source.inventory.get(food, 0)) - amount
			if not source.key.is_empty():
				var opened: float = float(candidate.before_food[source.key].open_rations) - float(candidate.stock[source.key].open_rations)
				source.location.open_rations = float(source.location.open_rations) - opened
		held.state.clear()
		held.state.merge(candidate.state)
		if held.kind == "team": held.entry.revision = int(held.entry.revision) + int(candidate.revision_delta)
		elif int(candidate.revision_delta) > 0: held.entry.version = int(held.entry.version) + 1
		for identity: int in candidate.damage:
			# The SAME original pendingpoint queue preserves native count and HP
			# until common publication; no proxy/body snapshot is charged.
			_apply_supply_damage(identity, float(candidate.damage[identity]))
		for identity: int in held.members:
			if held.kind != "team": break
			var hp: float = lab.crowd_site.work_fatigue_forecast_hp(identity) if lab.crowd_site.contains_person(identity) else float(held.members[identity].hp)
			var ko: float = float(held.owner.combat_hot_get(held.owner.index_for_identity(identity), &"ko", 0.0)) if lab.crowd_site.contains_person(identity) else float(held.members[identity].ko)
			held.entry.life_checkpoint[str(identity)] = 2 if hp <= 0.0 else 1 if ko > 0.0 else 0
	checked.prepared.published = true

func settle_gd_mesh_supply_contact(prepared: Dictionary) -> void:
	# Same original contact group just applied real HP/KO. No elapsed advance,
	# ration debit, body step, synthetic casualty or second supply timer.
	assert(prepared.get("owner") == self)
	for row: Dictionary in prepared.rows:
		if row.kind != "team": continue
		assert(is_same(row.state, row.entry.sustain))
		var was_routed: bool = bool(row.state.routed)
		_observe_team_life(row.owner, row.entry, row.members, row.reader)
		_publish_sustain_team_commands(row.owner, row.entry, was_routed, {"regrouped": false}, 0.0,
			_team_safe(row.owner, row.members), _team_stopped(row.owner, true))

func native_checked_supply_interval_limit(maximum: float) -> Dictionary:
	# Counterfactual BEGIN bounds call this READ-ONLY method. The original zero
	# meal publisher runs once in shared_supply_event_limit before snapshot.
	if not is_finite(maximum) or maximum <= 0.0: return Runtime.fail("INVALID_TIME")
	var rows: Dictionary = _native_sustain_original_rows(0.0)
	if not rows.ok: return rows
	var limit: float = maximum
	for row: Dictionary in rows.rows:
		for cohort: Dictionary in row.held.state_values.cohorts:
			var until: float = float(cohort.meal_until) - float(row.held.state_values.at)
			if not is_finite(until) or until <= 0.0: return Runtime.fail("SUPPLY_ENDPOINT_NOT_SETTLED")
			limit = minf(limit, until)
			var deficit: float = 1.0 - float(cohort.coverage)
			if deficit <= 0.0: continue
			var hunger: float = float(cohort.hunger)
			if hunger < 48.0: limit = minf(limit, (48.0 - hunger) / deficit * Sustain.HOUR)
			for identity: int in cohort.ids:
				var hp: float = float(row.held.life.get(identity, {}).get("hp", 0.0))
				if hp > 0.0: limit = minf(limit, (maxf(0.0, 48.0 - hunger) + hp) / deficit * Sustain.HOUR)
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled or _native_sustain_original_team(team): continue
		var entry: Dictionary = _supply_entry(team)
		if not entry.is_empty(): limit = minf(limit, _shared_supply_state_limit(entry.sustain, _team_members(team), maximum))
	for key: String in lab.terrain.site.get("person_supply", {}):
		if _native_sustain_original_person(int(key)): continue
		limit = minf(limit, _shared_supply_state_limit(lab.terrain.site.person_supply[key], captivity_supply.personal_members_id(int(key)), maximum))
	if not is_finite(limit) or limit <= 0.0: return Runtime.fail("INVALID_TIME")
	return Runtime.ok("Original current supply boundary; no state/cost/time writes", {"game_seconds": limit})

func _native_sustain_original_rows(seconds: float) -> Dictionary:
	if not _crowd_active() or not is_finite(seconds) or seconds < 0.0: return Runtime.fail("CLOCK_NOT_READY")
	var rows: Array[Dictionary] = []
	var feeding: Dictionary = captivity_supply.feeding_index()
	for owner: RefCounted in lab.crowd_site.person_owners():
		var entry: Dictionary = _supply_entry(owner)
		if entry.is_empty(): continue
		var originals: Dictionary = {}
		for index: int in owner.records: originals[owner.combat_identity(index)] = owner.records[index]
		for index: int in owner.actors: originals[owner.combat_identity(index)] = _actor_supply_adapter(owner.actors[index])
		var members: Dictionary = captivity_supply.team_members(owner, originals, feeding, lab.crowd_site._records)
		var life: Dictionary = {}
		for identity: int in members:
			if lab.crowd_site.contains_person(identity):
				var physical: Dictionary = lab.crowd_site.soldier_state(int(lab.crowd_site._index_by_id[identity]))
				life[identity] = {"hp": float(physical.hp), "ko": float(physical.ko), "captive": bool(physical.captive)}
			else:
				life[identity] = {"hp": float(members[identity].hp), "ko": float(members[identity].ko), "captive": bool(members[identity].captive)}
		var stock: Dictionary = _supply_stock(entry)
		var sources: Array[Dictionary] = []
		if int(entry.get("version", 0)) == 3:
			for key: String in stock: sources.append({"key": key, "location": stock[key], "inventory": stock[key].inventory})
		else: sources.append({"key": "", "location": {}, "inventory": stock})
		var held: Dictionary = {"kind": "team", "owner": owner, "entry": entry, "state": entry.sustain, "state_values": entry.sustain.duplicate(true),
			"stock": stock, "stock_values": stock.duplicate(true), "stock_sources": sources, "revision": int(entry.revision),
			"members": members, "life": life, "seconds": seconds}
		if int(entry.get("version", 0)) == 3:
			# The original grid team of a converted crowd team owns the ship food locations. SHIPUI: a natively deployed crowd
			# team (CrowdSite.deploy) has no original grid plan; its locations are read through the crowd owner itself, which
			# ship_food_locations accepts (team_id entry, crowd-aware _supply_person and is_embarked).
			var original: Variant = null
			for plan: Dictionary in lab.crowd_site._original_team_plans:
				if int(plan.crowd_formation) == int(owner.formation_index) and int(plan.source.team_id) == int(owner.team_id): original = plan.source; break
			if original == null and owner is CrowdPersonOwner and owner.has_army(): original = owner
			if original == null: return Runtime.fail("STALE_SUPPLY_OWNER")
			held["food_locations"] = ship_food_locations(original, members)
		rows.append({"held": held})
	# Personal meals use the SAME original personal state/cargo. Native people
	# must not also receive the legacy positive advance_person_supply call.
	for owner_id: String in lab.terrain.site.get("person_supply", {}):
		var state: Dictionary = lab.terrain.site.person_supply[owner_id]
		if state.is_empty(): continue
		var person: Dictionary = _supply_person(int(owner_id))
		if person.is_empty(): continue
		var members: Dictionary = captivity_supply.personal_members_id(int(owner_id))
		var includes_native: bool = lab.crowd_site.contains_person(int(person.person_id))
		for identity: int in members: includes_native = includes_native or lab.crowd_site.contains_person(identity)
		if not includes_native: continue
		var life: Dictionary = {}
		for identity: int in members:
			if lab.crowd_site.contains_person(identity):
				var physical: Dictionary = lab.crowd_site.soldier_state(int(lab.crowd_site._index_by_id[identity]))
				life[identity] = {"hp": float(physical.hp), "ko": float(physical.ko), "captive": bool(physical.captive)}
			else: life[identity] = {"hp": float(members[identity].hp), "ko": float(members[identity].ko), "captive": bool(members[identity].captive)}
		var held: Dictionary = {"kind": "personal", "owner_id": owner_id, "person": person,
			"entry": person.holder, "holder_values": person.holder.duplicate(true), "state": state, "state_values": state.duplicate(true),
			"stock": person.cargo, "stock_values": person.cargo.duplicate(true),
			"stock_sources": [{"key": "", "location": {}, "inventory": person.cargo}], "revision": int(person.holder.version),
			"members": members, "life": life, "seconds": seconds}
		rows.append({"held": held})
	return Runtime.ok("Actual original Native Sustain sources captured", {"rows": rows})

func _native_sustain_point_projection(held: Dictionary, payments: Array) -> Dictionary:
	# The borrowed original life sample and stock/state candidates are local to
	# this accepted interval. Sustain remains the only meal/hunger authority.
	var state: Dictionary = held.state_values.duplicate(true)
	var stock: Dictionary = held.stock_values.duplicate(true)
	for debit: Dictionary in payments:
		for source: Dictionary in held.stock_sources:
			if not is_same(debit.get("cargo"), source.inventory): continue
			var candidate: Dictionary = stock if source.key.is_empty() else stock[source.key].inventory
			for food: String in Sustain.FOODS:
				var amount: int = int(debit.get("cost", {}).get(food, 0))
				if amount < 0 or int(candidate.get(food, 0)) < amount: return Runtime.fail("MATERIALS")
				if amount > 0: candidate[food] = int(candidate.get(food, 0)) - amount
			if not source.key.is_empty() and is_same(debit.get("location"), source.location):
				var opened: float = float(debit.get("open_rations", 0.0))
				if opened < 0.0 or float(stock[source.key].open_rations) < opened: return Runtime.fail("MATERIALS")
				stock[source.key].open_rations = float(stock[source.key].open_rations) - opened
	var before_food: Dictionary = stock.duplicate(true)
	var pending_hp: Dictionary = {}
	var reader: Callable = func(identity: int, field: StringName) -> Variant:
		if held.life.has(identity) and held.life[identity].has(String(field)): return held.life[identity][String(field)]
		return held.members.get(identity, {}).get(String(field))
	var left: float = float(held.seconds)
	var fully_fed: bool = true
	var morale_delta: float = 0.0
	var revision_delta: int = 0
	var damage: Dictionary = {}
	while left > 0.0:
		state["morale"] = 50.0
		state["routed"] = false
		state["regroup_seconds"] = 0.0
		var seconds: float = minf(left, 600.0)
		var at: float = float(state.at)
		for cohort: Dictionary in state.cohorts:
			var until: float = float(cohort.meal_until)
			if until <= at: until = Sustain._next_meal(at)
			seconds = minf(seconds, until - at)
		if not is_finite(seconds) or seconds <= 0.0 or at + seconds <= at: return Runtime.fail("INVALID_TIME")
		var context: Dictionary = {"safe": false, "stopped": false, "hot_read": reader, "pending_hp": pending_hp}
		if held.has("food_locations"): context["food_locations"] = held.food_locations
		var outcome: Dictionary = Sustain.advance_to(state, held.members, stock, at + seconds, context)
		if not outcome.ok: return outcome
		fully_fed = fully_fed and bool(outcome.fully_fed)
		morale_delta += float(state.morale) - 50.0
		if float(outcome.consumed_rations) > 0.0: revision_delta += 1
		for identity: int in outcome.damage:
			damage[identity] = float(damage.get(identity, 0.0)) + float(outcome.damage[identity])
		left = maxf(0.0, left - seconds)
	state["morale"] = float(held.state_values.morale)
	state["routed"] = bool(held.state_values.routed)
	state["regroup_seconds"] = float(held.state_values.regroup_seconds)
	if int(held.revision) + revision_delta > 2147483647: return Runtime.fail("STALE_SOURCE")
	return Runtime.ok("原Sustain純正時間候選；未扣物／HP", {"held": held, "state": state, "stock": stock,
		"before_food": before_food, "fully_fed": fully_fed, "morale_delta": morale_delta,
		"revision_delta": revision_delta, "damage": damage})

func _native_sustain_projection_debits(candidate: Dictionary) -> Array[Dictionary]:
	var debits: Array[Dictionary] = []
	for source: Dictionary in candidate.held.stock_sources:
		var before: Dictionary = candidate.before_food if source.key.is_empty() else candidate.before_food[source.key].inventory
		var after: Dictionary = candidate.stock if source.key.is_empty() else candidate.stock[source.key].inventory
		var cost: Dictionary = {}
		for food: String in Sustain.FOODS:
			var amount: int = int(before.get(food, 0)) - int(after.get(food, 0))
			if amount > 0: cost[food] = amount
		var opened: float = 0.0 if source.key.is_empty() else float(candidate.before_food[source.key].open_rations) - float(candidate.stock[source.key].open_rations)
		debits.append({"cargo": source.inventory, "cost": cost, "location": source.location, "open_rations": opened})
	return debits

func validate_shared_native_training_prefix(planned: Dictionary, requests: Array) -> Dictionary:
	var checked: Array[Dictionary] = []
	var formations: Array = _shared_native_training_prefixes.keys()
	formations.sort()
	for formation: int in formations:
		var item: Dictionary = TrainingGround.checked_native_work_prefix(self, _shared_native_training_prefixes[formation], planned, requests)
		if not item.ok: return item
		checked.append(item)
	return Runtime.ok("原Native训练所有同held前缀已预验", {"checked": checked})

func native_held_actual_work_person(identity: int) -> bool:
	# Admission to the ORIGINAL fire reader only, never a new work selector or
	# person permission. Existing _person_has_duty remains unchanged so ongoing
	# Runtime work does not reject its own source recheck as "busy".
	if not _crowd_active() or not lab.crowd_site.contains_person(identity) \
		or lab.crowd_site.work_fatigue_point_active() or int(lab.crowd_site._work_fatigue_tick) < 0: return false
	var native_owner: Variant = lab.crowd_site.person_owner(identity)
	var snapshot: Dictionary = lab.crowd_site.work_fatigue_snapshot_for_owner(native_owner)
	if snapshot.is_empty() or int(snapshot.get("tick", -1)) != int(lab.crowd_site._work_fatigue_tick): return false
	var hot: PackedFloat64Array = lab.crowd_site.crowd.work_fatigue_state(int(native_owner.formation_index))
	if hot.size() < 5 or int(hot[0]) != int(snapshot.tick) or float(hot[2]) != float(snapshot.pool.fatigue) \
		or float(hot[3]) != float(snapshot.pool.fatigue_rest) or int(hot[4]) != int(snapshot.pool.count): return false
	for request: Dictionary in lab._shared_work_requests:
		if request.get("provider") not in ["runtime", "training"] or not str(request.get("paused", "")).is_empty() \
			or not is_finite(float(request.get("remaining", -1.0))) or float(request.get("remaining", 0.0)) <= 0.0 \
			or float(request.get("max_game_seconds", 0.0)) <= 0.0 or request.get("participants", []).size() != 1: continue
		var participant: Dictionary = request.participants[0]
		if int(participant.get("person_id", 0)) != identity or str(participant.get("native_effort_kind", "")) != "work" \
			or participant.get("native_owner") != native_owner or not is_same(participant.get("native_snapshot"), snapshot) \
			or not is_finite(float(participant.get("effort_rate", 0.0))) or float(participant.get("effort_rate", 0.0)) <= 0.0: continue
		var unit: int = int(participant.get("unit", -1))
		if native_owner.index_for_identity(identity) != unit or not native_owner.combat_units.has(unit) \
			or not is_same(native_owner.combat_units[unit], participant.get("original_body")): continue
		var body: Dictionary = participant.get("body", {})
		if not is_same(body.get("_fatigue_pool"), snapshot.pool) \
			or bool(participant.get("rest_limited", true)) and PersonFatigue.needs_work_rest(PersonFatigue.read(body), bool(body.get("work_resting", false))): continue
		if not lab.crowd_site.work_fatigue_work_start_ready(identity): continue
		if request.provider == "runtime":
			var source: Dictionary = _shared_runtime_request_source(request)
			if source.is_empty() or not _shared_runtime_source_ready(source): continue
		else:
			var held: Dictionary = _shared_native_training_prefixes.get(int(native_owner.formation_index), {})
			if held.is_empty() or not is_same(held.snapshot, snapshot) or held.owner != native_owner \
				or not held.people.has(identity) or not is_same(held.people[identity].participant, participant) \
				or not is_same(lab.terrain.site.get("team_supply", {}).get(str(native_owner.team_id)), held.entry) \
				or not bool(held.entry.get("training_order", false)) \
				or int(held.entry.get("training_requester", -1)) != int(held.commander_id) \
				or str(held.entry.get("training_feature_id", "")) != str(held.feature_id) \
				or not is_same(lab.terrain.site.features.get(str(held.feature_id)), held.feature): continue
			var current: Dictionary = TrainingGround.inspect(self, int(native_owner.team_id), str(held.feature_id))
			if not current.ok or int(current.get("commander_id", -1)) != int(held.commander_id) \
				or not bool(current.get("safe", false)) or not current.get("eligible_ids", []).has(identity) \
				or not lab.crowd_site.crowd.work_training_start_ready(int(native_owner.formation_index), float(lab.terrain.site.combat_left)): continue
		return true
	return false

func _install_settlement_engineering_controls(column: VBoxContainer) -> void:
	column.add_child(HSeparator.new())
	_label(column, "施工方案與有限防禦清單", 18)
	var form := {"steps": [], "signature": "", "caps": {}}
	column.set_meta(&"settlement_engineering_form", form)
	form["status"] = _label(column, "", 14)
	form["name"] = LineEdit.new()
	form.name.placeholder_text = "方案名稱（目前選中已完工建物）"
	form.name.max_length = 48
	column.add_child(form.name)
	form["plans"] = _options(column, [], "SettlementEngineeringPlans")
	var row := HBoxContainer.new()
	column.add_child(row)
	form["save"] = _button(row, "保存幾何", "SaveSettlementBlueprint", func() -> void: show_result(save_selected_settlement_blueprint(str(form.name.text))); _refresh_settlement_engineering_controls())
	form["delete"] = _button(row, "移除方案", "DeleteSettlementBlueprint", func() -> void: show_result(delete_selected_settlement_blueprint(_settlement_engineering_choice(form.plans))); _refresh_settlement_engineering_controls())
	row = HBoxContainer.new()
	column.add_child(row)
	form["preview"] = _button(row, "預檢重用", "PreviewSettlementBlueprint", func() -> void: show_result(preview_settlement_blueprint(_settlement_engineering_choice(form.plans))))
	form["reuse"] = _button(row, "在所選格重用", "ReuseSettlementBlueprint", func() -> void: show_result(reuse_selected_settlement_blueprint(_settlement_engineering_choice(form.plans))); _refresh_settlement_engineering_controls())
	form["steps_label"] = _label(column, "尚未加入清單步驟。每步使用目前選中的原人。", 14)
	row = HBoxContainer.new()
	column.add_child(row)
	form["add_build"] = _button(row, "加入防禦施工", "AddSettlementDefenseBuild", func() -> void: _settlement_engineering_add_step(form, "construct"))
	form["add_repair"] = _button(row, "加入所選部件維護", "AddSettlementDefenseRepair", func() -> void: _settlement_engineering_add_step(form, "repair"))
	_button(row, "清空草稿", "ClearSettlementDefenseDraft", func() -> void: form.steps.clear(); _refresh_settlement_engineering_controls())
	_label(column, "本單材料上限（每步先預檢，開始才按完整原成本付款）", 14)
	row = HBoxContainer.new()
	column.add_child(row)
	for resource: String in ["wood", "stone", "iron", "rope"]:
		_label(row, str(Env.ITEM_NAMES.get(resource, resource)), 14)
		var amount := SpinBox.new()
		amount.min_value = 0
		amount.max_value = 10000
		amount.step = 1
		amount.custom_minimum_size.x = 90
		row.add_child(amount)
		form.caps[resource] = amount
	form["request"] = _button(column, "登記有限清單並明示本隊同意", "RequestSettlementDefense", func() -> void:
		var cap := {}
		for resource: String in form.caps:
			var amount: int = int(form.caps[resource].value)
			if amount > 0: cap[resource] = amount
		var people: Array = []
		for step: Dictionary in form.steps:
			if not people.has(int(step.operator_id)): people.append(int(step.operator_id))
		var result := request_settlement_defense_work(form.steps, people, cap)
		show_result(result)
		if result.ok: form.steps.clear()
		_refresh_settlement_engineering_controls())
	form["orders"] = _options(column, [], "SettlementDefenseOrders")
	row = HBoxContainer.new()
	column.add_child(row)
	form["begin"] = _button(row, "開始下一步", "BeginSettlementDefense", func() -> void: show_result(begin_settlement_defense_work(_settlement_engineering_choice(form.orders))); _refresh_settlement_engineering_controls())
	form["resume"] = _button(row, "接續已付步驟", "ResumeSettlementDefense", func() -> void: show_result(resume_settlement_defense_work(_settlement_engineering_choice(form.orders))); _refresh_settlement_engineering_controls())
	form["cancel"] = _button(row, "停止並解除本單", "CancelSettlementDefense", func() -> void: show_result(cancel_settlement_defense_work(_settlement_engineering_choice(form.orders))); _refresh_settlement_engineering_controls())
	form["remove"] = _button(column, "移除完成／取消清單", "RemoveSettlementDefense", func() -> void: show_result(remove_settlement_defense_work(_settlement_engineering_choice(form.orders))); _refresh_settlement_engineering_controls())
	_refresh_settlement_engineering_controls()

func native_sustain_point_covers_person(prepared: Dictionary, identity: int) -> bool:
	if prepared.get("owner") != self or not is_same(prepared.get("site"), lab.terrain.site): return false
	for row: Dictionary in prepared.get("rows", []):
		if row.held.kind == "personal" and int(row.held.owner_id) == identity: return true
	return false

func publish_shared_runtime_work_prefix(admitted: Dictionary) -> Dictionary:
	assert(admitted.ok and is_same(admitted, _checked_runtime_work_admission))
	if bool(admitted.get("published", false)): return {"handled_seconds": {}}
	assert(is_same(admitted.plan, lab._shared_work_plan) and is_same(admitted.plan, _shared_work_plan))
	var handled := {}
	for candidate: Dictionary in admitted.runtime: Runtime.publish_checked_work_prefix(candidate)
	for prefix: Dictionary in admitted.prefixes:
		lab._shared_runtime_consumed[str(prefix.held.key)] = true # No legacy work-time fallback.
		if float(prefix.actual_seconds) > 0.0:
			handled[int(prefix.person_id)] = float(prefix.actual_seconds)
			if not prefix.start.owner is CrowdPersonOwner:
				lab._fatigue_work_seconds[prefix.held.actor] = float(lab._fatigue_work_seconds.get(prefix.held.actor, 0.0)) + float(prefix.actual_seconds)
	admitted["published"] = true
	return {"handled_seconds": handled}

func _native_sustain_original_person(identity: int) -> bool:
	if not _crowd_active(): return false
	if lab.crowd_site.contains_person(identity): return true
	for member: int in captivity_supply.personal_members_id(identity):
		if lab.crowd_site.contains_person(member): return true
	return false

func settle_native_supply_begin_endpoint(maximum: float) -> Dictionary:
	if not is_finite(maximum) or maximum <= 0.0 or lab._region_deferring_endpoint(): return Runtime.fail("CLOCK_NOT_READY")
	var original: Dictionary = _native_sustain_original_rows(0.0)
	if not original.ok: return original
	# Same original zero-resupply order: teams first, then personal owners.
	var candidates: Array[Dictionary] = []
	var prior: Array = []
	var limit: float = maximum
	for row: Dictionary in original.rows:
		var candidate: Dictionary = _native_sustain_due_candidate(row.held, prior)
		if not candidate.ok: return candidate
		candidates.append(candidate)
		prior.append_array(_native_sustain_projection_debits(candidate))
		for cohort: Dictionary in candidate.state.cohorts:
			var meal: float = float(cohort.meal_until) - float(candidate.state.at)
			if not is_finite(meal) or meal <= 0.0: return Runtime.fail("INVALID_TIME")
			limit = minf(limit, meal)
			var deficit: float = 1.0 - float(cohort.coverage)
			if deficit <= 0.0: continue
			var hunger: float = float(cohort.hunger)
			if hunger < 48.0: limit = minf(limit, (48.0 - hunger) / deficit * Sustain.HOUR)
			for identity: int in cohort.ids:
				var hp: float = float(row.held.life.get(identity, {}).get("hp", 0.0))
				if hp <= 0.0: continue
				limit = minf(limit, (maxf(0.0, 48.0 - hunger) + hp) / deficit * Sustain.HOUR)
	if not is_finite(limit) or limit <= 0.0: return Runtime.fail("INVALID_TIME")
	# ALL original states/stocks have been checked, with shared inventory debits.
	# No callback/yield can alter them before this original zero-time tail.
	for candidate: Dictionary in candidates:
		var held: Dictionary = candidate.held
		for source: Dictionary in held.stock_sources:
			var before: Dictionary = candidate.before_food if source.key.is_empty() else candidate.before_food[source.key].inventory
			var after: Dictionary = candidate.stock if source.key.is_empty() else candidate.stock[source.key].inventory
			for food: String in Sustain.FOODS:
				var amount: int = int(before.get(food, 0)) - int(after.get(food, 0))
				if amount > 0: source.inventory[food] = int(source.inventory.get(food, 0)) - amount
			if not source.key.is_empty():
				source.location.open_rations = float(source.location.open_rations) - (float(candidate.before_food[source.key].open_rations) - float(candidate.stock[source.key].open_rations))
		held.state.clear()
		held.state.merge(candidate.state)
		if held.kind == "team": held.entry.revision = int(held.entry.revision) + int(candidate.revision_delta)
		elif int(candidate.revision_delta) > 0: held.entry.version = int(held.entry.version) + 1
	return Runtime.ok("Original zero meal settled before Native snapshot, no elapsed/HP/fatigue", {"game_seconds": limit})

func _native_sustain_original_team(team: TerrainArmy) -> bool:
	if not _crowd_active(): return false
	for plan: Dictionary in lab.crowd_site._original_team_plans:
		if is_same(plan.source, team): return true
	return false

## P1p: pure check of every crowd delivery held for this point, against the point's final plan and requests. Called with the
## training check, BEFORE the native final READY; no write. A job changed or cancelled since collection refuses the point
## (STALE_DELIVERY_SOURCE), as the grid's gd-contact delivery window does.
func validate_shared_native_delivery_prefix(planned: Dictionary, requests: Array) -> Dictionary:
	var checked: Array[Dictionary] = []
	var keys: Array = _shared_native_delivery_prefixes.keys()
	keys.sort()
	var seconds: float = float(planned.get("seconds", -1.0))
	for key: Variant in keys:
		var held: Dictionary = _shared_native_delivery_prefixes[key]
		var found: Dictionary = {}
		for request: Dictionary in requests:
			if str(request.get("provider", "")) != "delivery" or str(request.get("key", "")) != str(key): continue
			if not found.is_empty(): return Runtime.fail("STALE_DELIVERY_SOURCE")
			found = request
		if found.is_empty() or not is_same(found.get("participants"), held.participants): return Runtime.fail("STALE_DELIVERY_SOURCE")
		if not is_same(_supply_entry(held.owner), held.entry) or not is_same(held.entry.get("delivery"), held.job) \
			or bool(held.job.get("pending", false)) or float(held.job.left) != float(held.left): return Runtime.fail("STALE_DELIVERY_SOURCE")
		var allocation: Dictionary = planned.get("jobs", {}).get("delivery", {}).get(str(key), {})
		var actual: float = float(allocation.get("actual_seconds", 0.0))
		var effective: float = float(allocation.get("effective_seconds", 0.0))
		if not is_finite(actual) or not is_finite(effective) or actual < 0.0 or effective < 0.0 \
			or actual > seconds + PersonFatigue.WORK_PLAN_EPS or effective > actual + PersonFatigue.WORK_PLAN_EPS \
			or effective > float(held.left) + PersonFatigue.WORK_PLAN_EPS: return Runtime.fail("INVALID_WORK_PLAN")
		checked.append({"held": held, "allocation": allocation, "actual": actual, "effective": effective, "left_after": maxf(0.0, float(held.left) - effective)})
	return Runtime.ok("crowd delivery same-point prefix checked", {"checked": checked})

## P1p: the crowd delivery's own state after the native point published (fatigue is already charged there, once, to the native
## pool): work_resting as the grid's delivery publisher sets it, the left timer from the final allocation, pending at zero. Then the
## endpoint validity, as the grid's finish_gd_contact_delivery_window. Never writes fatigue.
func finish_shared_native_delivery_prefix(prepared: Dictionary) -> void:
	for item: Dictionary in prepared.get("checked", []):
		var held: Dictionary = item.held
		if not is_same(_supply_entry(held.owner), held.entry) or not is_same(held.entry.get("delivery"), held.job): continue
		var allocation: Dictionary = item.allocation
		var paused: String = str(allocation.get("paused", ""))
		for person: Dictionary in held.people:
			var identity: int = int(person.person_id)
			var actual: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
			if identity != lab.controlled_person_id() and int(person.unit) >= 0 and (paused == "REST" or actual > 0.0):
				held.owner.combat_hot_set(int(person.unit), &"work_resting", paused == "REST")
		var left_before: float = float(held.job.left)
		held.job.left = float(item.left_after)
		if float(held.job.left) <= 0.00000001:
			held.job.left = 0.0
			held.job.pending = true
		crowd_delivery_steps += 1
		crowd_delivery_last = "owner=%d point actual=%.4f effective=%.4f paused=%s left=%.4f->%.4f pending=%s" % [int(held.owner.team_id), float(item.actual), float(item.effective), paused, left_before, float(held.job.left), str(held.job.get("pending", false))]
		if not _delivery_valid(held.owner, held.entry):
			held.entry.delivery = {}
			message.text = "交糧條件已變更，當批取消；來源未扣物"
	_shared_native_delivery_prefixes.clear()

func finish_shared_native_training_prefix(prepared: Dictionary) -> void:
	# AFTER actual World common publisher, then current authority/cancellation.
	for item: Dictionary in prepared.get("checked", []): TrainingGround.finish_native_work_prefix(self, item)
	_shared_native_training_prefixes.clear()

# ORIGINAL collector insert in prepare_shared_owner_work_requests():
# after original worker/manual inputs, BEFORE Army training/delivery loop:
#   if _crowd_active():
#       var native_training: Dictionary = prepare_shared_native_training_requests(seconds, float(lab.terrain.site.combat_left))
#       if not native_training.ok: latch_original_step_fault(native_training); return []
#       requests.append_array(native_training.requests)
# The caller must stop the original point on error, not treat [] as success.
# Existing _shared_person_request uses original CrowdSite.work_fatigue_participant
# for native bodies, never PersonFatigue.bind onto a real record or Actor.
#
# ORIGINAL advance_crowd_sustain(): replace ONLY final legacy call:
#   if not lab._region_deferring_endpoint() and lab._shared_work_plan.is_empty():
#       TrainingGround.advance_native(self, team_owner, entry, elapsed_game_seconds, fully_fed)
# Native common collector preserves original Sustain.set_sustain_input/HP work;
# training growth/effort is solely the true captured shared-prefix path.
# This existing method must never call legacy train with missing allocations
# during a common interval, before or after World. Preserve original food time.
# Teardown/failed preflight clears _shared_native_training_prefixes explicitly.

# APPEND to ORIGINAL SiteController, then merge callsites into original Lab.
# Original worker/manual dictionaries, persons and finite same-point priors only.

func finish_shared_runtime_work_prefix(admitted: Dictionary) -> void:
	if admitted.get("owner") != self or not bool(admitted.get("published", false)) or bool(admitted.get("finished", false)): return
	admitted["finished"] = true
	for held: Dictionary in admitted.prepared.held:
		var person: Dictionary = person_actions._person(int(held.person_id))
		if person.is_empty() or bool(person.player): continue
		var allocation: Dictionary = admitted.plan.jobs.get("runtime", {}).get(str(held.key), {})
		if float(allocation.get("participant_seconds", {}).get(int(held.person_id), 0.0)) > 0.0: person_actions._body_set(person, "work_resting", false)
		if str(allocation.get("participant_paused", {}).get(int(held.person_id), allocation.get("paused", ""))) == "REST":
			person_actions._body_set(person, "work_resting", true)
			if person.owner is CrowdPersonOwner: person.owner.work_fatigue_rest(int(held.person_id))
	for candidate: Dictionary in admitted.runtime: Runtime.settle_checked_work_prefix(candidate)
	# Retain true capture/clock until all original provider endpoints settle.

# Original setup/rebind: bind_checked_runtime_work_prefix(). Failed preflight
# and original teardown: discard_checked_runtime_work_prefix(). No saved fields.
# Runtime supplement admits ONLY original data meta SAME self + SAME registry.
# Manual stays its original shape; Runtime preflight must allow SAME site.manual
# without adding mode/work_cell. Other task shapes/guards are unchanged.

func _settlement_engineering_add_step(form: Dictionary, action: String) -> void:
	if form.steps.size() >= 4: show_result(Runtime.fail("LIMIT", "本清單至多四步")); return
	var identity: int = int(lab.selected_army_target) if int(lab.selected_army_target) > 0 else int(person_executor_id)
	var person: Dictionary = person_actions._person(identity)
	if person.is_empty(): show_result(Runtime.fail("NO_WORKER", "先在原人物／隊伍介面選中真原人")); return
	var part := ""
	if action == "repair" and building_parts.selected >= 0 and building_parts.selected < building_parts.item_count:
		part = str(building_parts.get_item_metadata(building_parts.selected))
	var chosen := selected_settlement_defense_step(_settlement_engineering_choice(form.plans), identity, action, part)
	if not chosen.ok: show_result(chosen); return
	form.steps.append(chosen.step)
	_refresh_settlement_engineering_controls()

func cancel_settlement_defense_work(order_id: String) -> Dictionary:
	return SiteRuntime.cancel_settlement_defense_order(lab.terrain, int(person_actions._technology_controlled()), order_id)

func delete_selected_settlement_blueprint(plan_id: String) -> Dictionary:
	return SiteRuntime.delete_settlement_blueprint(lab.terrain, int(person_actions._technology_controlled()), plan_id)

func preview_settlement_blueprint(plan_id: String) -> Dictionary:
	return SiteRuntime.reuse_settlement_blueprint(lab.terrain, int(person_actions._technology_controlled()), plan_id, selected, true)

func remove_settlement_defense_work(order_id: String) -> Dictionary:
	return SiteRuntime.remove_finished_settlement_defense_order(lab.terrain, int(person_actions._technology_controlled()), order_id)

func resume_settlement_defense_work(order_id: String, preview: bool = false) -> Dictionary:
	return SiteRuntime.resume_settlement_defense_step(lab.terrain, int(person_actions._technology_controlled()), order_id, preview)

func _native_sustain_due_candidate(held: Dictionary, payments: Array) -> Dictionary:
	# Zero time: original Sustain meal only, before any new point snapshot.
	var state: Dictionary = held.state_values.duplicate(true)
	var stock: Dictionary = held.stock_values.duplicate(true)
	for debit: Dictionary in payments:
		for source: Dictionary in held.stock_sources:
			if not is_same(debit.get("cargo"), source.inventory): continue
			var inventory: Dictionary = stock if source.key.is_empty() else stock[source.key].inventory
			for food: String in Sustain.FOODS:
				var amount: int = int(debit.get("cost", {}).get(food, 0))
				if amount < 0 or int(inventory.get(food, 0)) < amount: return Runtime.fail("MATERIALS")
				if amount > 0: inventory[food] = int(inventory.get(food, 0)) - amount
			if not source.key.is_empty() and is_same(debit.get("location"), source.location):
				var opened: float = float(debit.get("open_rations", 0.0))
				if opened < 0.0 or float(stock[source.key].open_rations) < opened: return Runtime.fail("MATERIALS")
				stock[source.key].open_rations = float(stock[source.key].open_rations) - opened
	var before: Dictionary = stock.duplicate(true)
	var reader: Callable = func(identity: int, field: StringName) -> Variant:
		return held.life[identity][String(field)] if held.life.has(identity) and held.life[identity].has(String(field)) else held.members.get(identity, {}).get(String(field))
	var context: Dictionary = {}
	if held.has("food_locations"): context["food_locations"] = held.food_locations
	var result: Dictionary = Sustain.resupply(state, held.members, stock, true, reader, {}, context)
	if not result.ok: return result
	var revision: int = 1 if float(result.consumed_rations) > 0.0 else 0
	if int(held.revision) + revision > 2147483647: return Runtime.fail("STALE_SOURCE")
	return Runtime.ok("Original zero meal candidate", {"held": held, "state": state, "stock": stock,
		"before_food": before, "revision_delta": revision, "damage": {}})

func selected_settlement_defense_step(plan_id: String, operator_id: int, action: String = "construct", part: String = "") -> Dictionary:
	if action == "construct":
		var target := SiteRuntime.settlement_blueprint_target(lab.terrain, plan_id, selected)
		if not target.ok: return target
		return SiteRuntime.ok("", {"step": {"action": action, "plan_id": plan_id, "anchor": [selected.x, selected.y], "feature_id": "", "part": "", "operator_id": operator_id}})
	if action != "repair" or feature_key.is_empty(): return SiteRuntime.fail("INVALID")
	var feature: Dictionary = lab.terrain.site.features.get(feature_key, {})
	if not feature.get("parts", {}).has(part): return SiteRuntime.fail("NO_TARGET")
	return SiteRuntime.ok("", {"step": {"action": action, "plan_id": "", "anchor": [], "feature_id": feature_key, "part": part, "operator_id": operator_id}})

func nation_route_options() -> Dictionary:
	if region_slot == null: return Runtime.fail("NO_REGION_SLOT", "先開啟原固定世界存檔槽")
	return region_slot.nation_route_options(lab)

func nation_route_query(route_id: String, destination_site_id: String, vehicle_id: String,
		driver_id: int, destination_holder: String) -> Dictionary:
	if region_slot == null: return Runtime.fail("NO_REGION_SLOT")
	return region_slot.nation_route_query(lab, route_id, destination_site_id, vehicle_id, driver_id, destination_holder)

func nation_route_request(nation_id: String, order_id: String, original_order: Dictionary) -> Dictionary:
	if region_slot == null: return Runtime.fail("NO_REGION_SLOT")
	return region_slot.begin_nation_transport_route(lab, nation_id, order_id, original_order)

func prepare_nation_route_load(nation_id: String, order_id: String, original_order: Dictionary) -> Dictionary:
	if region_slot == null: return Runtime.fail("NO_REGION_SLOT")
	return region_slot.prepare_nation_route_load(lab, nation_id, order_id, original_order)

var _region_departure_intent: Dictionary = {}

## G6.6: the cadre-split entry in the 功能 window, beside 整隊出發. Built once; refreshed by update_ui.
var region_travel_button: Button
var crowd_split_members: ItemList
var crowd_split_button: Button
var crowd_split_status: Label
var crowd_split_context: Array = []

func _build_crowd_split_entry(parent: Node) -> void:
	crowd_split_status = _label(parent, "", 15)
	crowd_split_status.name = "CrowdSplitStatus"
	crowd_split_members = ItemList.new()
	crowd_split_members.name = "CrowdSplitMembers"
	crowd_split_members.select_mode = ItemList.SELECT_MULTI
	crowd_split_members.custom_minimum_size = Vector2(230, 120)
	crowd_split_members.visible = false
	parent.add_child(crowd_split_members)
	crowd_split_members.multi_selected.connect(func(_index: int, _selected: bool) -> void: _refresh_crowd_split_ui())
	crowd_split_button = _button(parent, "分隊出發", "DepartCrowdSplit", func() -> void:
		show_result(RegionTravelSite.depart_crowd_split(self, _selected_crowd_split_members())))
	crowd_split_button.visible = false
	crowd_split_status.visible = false

func _selected_crowd_split_members() -> Array:
	var identities: Array = []
	for item: int in crowd_split_members.get_selected_items():
		identities.append(int(crowd_split_members.get_item_metadata(item)))
	return identities

## G6.6: shows the cadre-split entry only for a non-captain of a live crowd team. The whole-team button is for the captain only.
func _refresh_crowd_split_ui() -> void:
	if crowd_split_button == null or lab == null or lab.restore_only: return
	var entry: Dictionary = RegionTravelSite.crowd_split_entry(self)
	if region_travel_button != null:
		var ordinary_crowd_member: bool = bool(entry.get("in_team", false)) and not bool(entry.get("captain", false))
		region_travel_button.disabled = ordinary_crowd_member
		region_travel_button.tooltip_text = "整隊出發僅限隊長；幹部請用分隊出發" if ordinary_crowd_member else ""
	var shown: bool = bool(entry.get("show", false))
	crowd_split_members.visible = shown
	crowd_split_button.visible = shown
	crowd_split_status.visible = shown
	if not shown:
		crowd_split_context = []
		return
	var context: Array = [entry.leader, entry.team_id]
	if context != crowd_split_context:
		crowd_split_context = context
		crowd_split_members.clear()
		for identity: int in entry.candidates:
			var item := crowd_split_members.add_item("#%d 隊員（非幹部）" % identity)
			crowd_split_members.set_item_metadata(item, identity)
	var gate: Dictionary = RegionTravelSite.crowd_split_gate(self, _selected_crowd_split_members())
	crowd_split_button.disabled = not gate.ok
	crowd_split_status.text = "分隊：可帶 %d 名所選隊員" % _selected_crowd_split_members().size() if gate.ok \
		else "%s：%s" % [str(gate.get("code", "")), str(gate.get("message", ""))]

func _request_region_departure() -> Dictionary:
	if not _region_departure_intent.is_empty(): return Runtime.fail("BUSY")
	var selected := RegionTravelSite.selected_departure(self)
	if not selected.ok: return selected
	var mode: Dictionary = region_slot.region_registry().modes.get(str(lab.terrain.site.id), {})
	if str(mode.get("mode", "")) != "live" or str(mode.get("backend", "")) != "gd": return Runtime.fail("REGION_MODE")
	var siege := RegionSaveSlot.RegionBattle.prepare_original_siege(lab)
	if not siege.ok or not siege.get("present", false): return Runtime.fail("IN_COMBAT", "非已准入的原攻城 owner")
	if RegionTravelSite.controlled_departure_step_remaining(self) <= 0.0: return Runtime.fail("BUSY", "受控本人沒有未完成的原已承諾步")
	var nonce := "depart_" + Crypto.new().generate_random_bytes(16).hex_encode()
	_region_departure_intent = {"nonce": nonce, "source": lab.terrain, "slot": region_slot, "lab": weakref(lab),
		"owner": str(lab.terrain.site.id), "selection": selected.selection, "people": selected.people.duplicate(), "candidate": {}}
	return Runtime.ok("等待本人已承諾操作抵達合法端點；再次整隊出發可取消", {"pending": true, "nonce": nonce})

func _cancel_region_departure(nonce: String) -> Dictionary:
	if _region_departure_intent.is_empty() or str(_region_departure_intent.nonce) != nonce: return Runtime.fail("STALE_REGION_INTENT")
	var prepared: Dictionary = _region_departure_intent.candidate
	if not prepared.is_empty():
		var discard: Variant = prepared.get("binding", {}).get("discard", Callable())
		if discard is Callable and discard.is_valid(): discard.call()
	_region_departure_intent.clear()
	return Runtime.ok("已取消離場意圖；原命令與已付進度繼續", {"cancelled": true, "nonce": nonce})

func _region_departure_capability(nonce: String) -> Dictionary:
	if _region_departure_intent.is_empty() or str(_region_departure_intent.nonce) != nonce: return Runtime.fail("STALE_REGION_INTENT")
	var intent: Dictionary = _region_departure_intent
	if intent.lab.get_ref() != lab or intent.source != lab.terrain or intent.slot != region_slot or str(intent.owner) != str(lab.terrain.site.id): return Runtime.fail("STALE_REGION_INTENT")
	var selected := RegionTravelSite.selected_departure(self)
	if not selected.ok: return selected
	if selected.selection != intent.selection: return Runtime.fail("STALE_REGION_INTENT")
	return selected

func _region_departure_defers_person(identity: int) -> bool:
	return not _region_departure_intent.is_empty() and _region_departure_intent.source == lab.terrain and _region_departure_intent.people.has(identity)

func _finish_region_departure() -> bool:
	if _region_departure_intent.is_empty(): return false
	var nonce := str(_region_departure_intent.nonce)
	var selected := _region_departure_capability(nonce)
	if not selected.ok:
		_cancel_region_departure(nonce)
		show_result(selected)
		return false
	if bool(selected.waiting): return false
	# A queued contact/P0/Fire boundary is consumed by its original zero owner.
	if not region_slot.region_player_barrier().is_empty() or not lab._region_point_pending.is_empty() or lab._region_point_consuming or lab._region_point_dispatching \
		or not lab._region_point_contacts.is_empty() or not lab._region_point_wakes.is_empty() or not lab._combat_contacts.is_empty() or not lab.terrain.get_meta(&"fire_boundary", {}).is_empty(): return false
	var prepared := region_slot.prepare_region_player_departure(self, nonce)
	if not prepared.ok:
		if str(prepared.get("code", "")) == "SAVE_IO":
			show_result(prepared)
			return false # Keep the nonce; no private candidate or ownership move.
		# An unsupported selected closure is an explicit refusal, never perpetual wait.
		_cancel_region_departure(nonce)
		show_result(prepared)
		return false
	_region_departure_intent.candidate = prepared
	var committed := region_slot.commit_region_player_departure(prepared)
	if not committed.ok:
		if not bool(committed.get("committed", false)):
			prepared.binding.discard.call()
			_region_departure_intent.candidate = {}
		else:
			_region_departure_intent.clear()
		show_result(committed)
		return bool(committed.get("committed", false))
	_region_departure_intent.clear()
	_auto_save_blocked = true
	RegionTravelSite.open_travel_map(self, str(region_slot.pin.world_instance_id), str(region_slot.pin.slot_id), _region_manifest_path)
	show_result(Runtime.ok("已由原完整端點整隊出發", {"token": committed.token, "generation": committed.generation}))
	return true

var _resume_region_party_map_button: Button

func _update_region_party_map_resume_button() -> void:
	if not is_instance_valid(_resume_region_party_map_button): return
	_resume_region_party_map_button.visible = region_slot != null and lab != null and lab.terrain != null \
		and lab.terrain.has_meta(&"region_party_owner") and not lab.restore_only
	if not _resume_region_party_map_button.visible: return
	if launcher_window != null and launcher_window.visible:
		var prepared := region_slot.prepare_region_party_map_resume(lab)
		_resume_region_party_map_button.disabled = not prepared.ok or prepared.get("already_map", false)
		_resume_region_party_map_button.tooltip_text = str(prepared.get("message", "在同一已付原端點繼續旅行"))

func _resume_region_party_map() -> void:
	if region_slot == null: return
	var accepted := region_slot.resume_region_party_map(lab)
	show_result(accepted)
	if not accepted.ok: return
	_auto_save_blocked = true
	# The ordinary production scene handoff follows the durable original graph.
	# Stop this scene's input loop immediately; the map supplies subsequent input.
	if RegionTravelSite.scene_handoff: lab.set_process(false)
	RegionTravelSite.open_travel_map(self, str(region_slot.pin.world_instance_id), str(region_slot.pin.slot_id), _region_manifest_path)

func _observe_original_food_result(kind: String, identity: String, at_game_seconds: float, result: Dictionary) -> void:
	# Read-only per-call exposure after the original owner published this result.
	if region_slot == null or _crowd_active(): return
	region_slot._observe_original_food_result(lab, kind, identity, at_game_seconds, result)

func _audio_build_controls(column: VBoxContainer) -> void:
	_label(column, "音效音量（0–100%）", 18)
	_audio_volume_slider = HSlider.new()
	_audio_volume_slider.name = "SFXVolume"
	_audio_volume_slider.min_value = 0.0
	_audio_volume_slider.max_value = 100.0
	_audio_volume_slider.step = 1.0
	_audio_volume_slider.tooltip_text = "玩家周圍的音效音量"
	column.add_child(_audio_volume_slider)
	_audio_mute_toggle = CheckButton.new()
	_audio_mute_toggle.name = "SFXMute"
	_audio_mute_toggle.text = "靜音"
	column.add_child(_audio_mute_toggle)
	_audio_volume_slider.value_changed.connect(func(value: float) -> void:
		if lab.audio_view != null: lab.audio_view.set_volume(value / 100.0))
	_audio_mute_toggle.toggled.connect(func(value: bool) -> void:
		if lab.audio_view != null: lab.audio_view.set_muted(value))
	if lab.audio_view != null:
		lab.audio_view.settings_changed.connect(_audio_settings_changed)
		var state: Dictionary = lab.audio_view.stats_snapshot()
		_audio_settings_changed(float(state.volume), bool(state.muted))
	else:
		_audio_volume_slider.editable = false
		_audio_mute_toggle.disabled = true


func _audio_settings_changed(volume: float, muted: bool) -> void:
	if is_instance_valid(_audio_volume_slider): _audio_volume_slider.set_value_no_signal(volume * 100.0)
	if is_instance_valid(_audio_mute_toggle): _audio_mute_toggle.set_pressed_no_signal(muted)

func _faction_label(faction_id: int) -> String:
	var view: Dictionary = region_slot.faction_display(faction_id) if region_slot != null else RegionFactionQuery.display({}, faction_id)
	return str(faction_id) if view.name == "勢力 %d" % faction_id else str(view.name)
