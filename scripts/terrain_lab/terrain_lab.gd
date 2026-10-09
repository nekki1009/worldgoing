class_name TerrainLab
extends Node2D

const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const TechnologyArtisans = preload("res://scripts/terrain_lab/site_technology_artisans.gd")
const TechnologyPolicy = preload("res://scripts/terrain_lab/site_technology_policy.gd")
const MIN_ZOOM := 0.1
const MAX_ZOOM := 10.0
const ZOOM_STEP := 1.20
const ACTION_STEP := 1.0 / 120.0
const ACTION_FRAME_BUDGET_USEC := 20000 # Leave rendering time while bounded catch-up repays slow frames.
const ACTION_TIME_EPSILON := 0.000000000001
const SIMULATION_SPEEDS: Array[float] = [0.5, 1.0, 2.0, 4.0]
const Site = preload("res://scripts/terrain_lab/site_controller.gd")
const SiteEnv = preload("res://scripts/terrain_lab/site_environment.gd")
const FatigueGeometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const ExchangeSnapshot = preload("res://scripts/terrain_lab/site_exchange_snapshot.gd")
const CombatMovementCoordinatorScript = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const FireMovementTypes = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const TacticalAI = preload("res://scripts/terrain_lab/site_army_ai.gd")
const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const CrowdSiteScript = preload("res://scripts/terrain_lab/crowd_site.gd") # crowd10k test copy: --crowd
var crowd_site: Node = null # Native hot state; Site retains original person/item records.
var _native_begin_ranged_prepared: Dictionary = {}
var _native_begin_ranged_validation: Dictionary = {}
var crowd_startup_requested := false
# Includes original shared-tail work; excludes the native simulation call itself.
var crowd_host_cost_count := 0
var crowd_host_cost_total_us := 0
var crowd_host_cost_max_us := 0
var crowd_host_cost_last_us := 0
var _tactical_ai_elapsed := 0.0
var _duty_ai_elapsed := 0.0 # Game seconds toward the next duty-AI round; cadence only, not saved.
var site_controller: Node
var site_test_window: Window
var pause_when_unfocused := true
var simulation_speed := 1.0
var restore_only := false # Original cold Site scene; no frame/input/autosave publisher.
var _region_formula_active := false # The original formula interval uses its accepted melee receipt.
var _replay_target := -1.0 # Fixed command target, never a second simulation clock.
var _fire_replay_tracking := false
var _fire_replay_epoch := ""
var _fire_replay_keep_tactical := false
var _fire_replay_segments: Array[Dictionary] = []
var _fire_replay_segment_index := 0
var _fire_replay_segment_offset := 0
var _fire_replay_end_sequence := -1
var _fire_replay_end_action := 0.0
var _fire_replay_end_game := 0.0
var _cold_replay_lab: TerrainLab
var _cold_replay_id := ""
var _cold_replay_target := -1.0
var _cold_replay_signature := ""
var movement_input_enabled := true
var test_placement_enabled := false

var terrain: TerrainData
var _region_bound_data: TerrainData
var _region_bind_receipt_value: Dictionary = {}
var renderer: TerrainRenderer
var character: TerrainTestCharacter
var npc: TerrainTestNPC
var army: TerrainArmy
var opposing_army: TerrainArmy
var third_army: TerrainArmy
var combat_armies: Array[TerrainArmy] = []
var _trial_formation_failure: Dictionary = {}
var combat_movement_coordinator: SiteCombatMovementCoordinator = null
var camera: Camera2D
var preset_dropdown: OptionButton
var seed_input: LineEdit
var generate_button: Button
var debug_toggle: CheckButton
var movement_toggle: CheckButton
var npc_command_dropdown: OptionButton
var npc_command_button: Button
var npc_allied_toggle: CheckButton
var info: Label
var parameters_label: Label
var status: Label
var generation_ms: float = 0.0
var _dragging: bool = false
var _info_time: float = 0.0
var _held_directions: Dictionary = {}
var _last_direction_key: int = -1
var _movement_input_actor: TerrainTestCharacter
var _run_held: bool = false
var _npc_target_pending := false
var npc_retaliates := false
var combat_info: Label
var army_info: Label
var deploy_army_button: Button
var follow_army_button: Button
var edge_army_button: Button
var clear_army_button: Button
var combat_actors: Array[TerrainTestCharacter] = []
var _combat_contacts: Array[Dictionary] = []
var _sampling_army_contacts := false
var _army_contact_geometry: Dictionary = {}
var contact_input_reuse_enabled := false # Reuse exact inputs only in the original synchronous batch.
var contact_buckets_enabled := false # Opt-in broad-phase only; all original rows remain authoritative.
var contact_candidate_profile_enabled := false
var contact_candidate_profile := {"queries": 0, "rows_before": 0, "rows_visited": 0,
	"anchor_passed": 0, "bounds_built": 0, "geometry_built": 0, "narrow_calls": 0,
	"bucket_builds": 0, "bucket_build_usec": 0, "candidate_usec": 0}
var batch_actor_bounds_enabled := true # Exact same-batch rejection; false is the original contact path for A/B.
var selected_army_target := 0
var selected_army_label: Label
var _fatigue_work_seconds: Dictionary = {} # This frame only; not a second person state.
var combat_profile_enabled := false # Optional counters only; never a simulation clock.
var combat_profile_usec: Dictionary = {}
var fatigue_two_hop_witness_enabled := true # Exact positive proof only; false keeps the original BFS entry.
var fatigue_zero_fast_path_enabled := true # Exact zero-effort shortcut, compared against V0.41R.
var fatigue_zero_eligible_rows := 0 # Counts, not microseconds; profiling only.
var fatigue_zero_skipped_advances := 0
var fixed_action_steps_enabled := false # A/B: retain incomplete 120 Hz time, never clamp or discard it.
var _action_time_remainder := 0.0 # Original clock's pending time and fractional phase.
var action_elapsed_measure_enabled := false # Formal fixture only; record the input actually accepted by this clock.
var action_elapsed_input_sum := 0.0
var action_elapsed_input_count := 0
var _process_sample_usec := -1
var _process_sample_frame := -1
var _process_sample_active := false
var _process_use_wall_elapsed := not OS.get_cmdline_args().has("--fixed-fps") and Engine.get_write_movie_path().is_empty()
var exchange_enabled := true # 2026-09-14 approved rule replacement; false is historical geometry mode.
var exchange_batch_enabled := true # Call-local query columns; false retains phase-two A/B.
var _exchange_kernel: RefCounted
var _exchange_kernel_checked := false
const EXCHANGE_ACTION_STEP := 1.0 / 30.0
const EXCHANGE_QUERY_STEP := 0.1
var _exchange_phase := 0.0
var _exchange_round := 0
var exchange_count := 0
var exchange_results := {"draw": 0, "small": 0, "big": 0}
signal exchange_resolved(a_id: int, b_id: int, result: Dictionary)
var ranged_shots := 0
var ranged_resolutions := 0
var ranged_results := {"miss": 0, "graze": 0, "hit": 0, "empty": 0, "blocked": 0}
signal ranged_resolved(shooter_id: int, target_id: int, result: Dictionary)

# Released siege flights outlive their source vehicle. Person HP and item state
# remain in their original owners; these are disposable combat events only.
var siege_projectiles: Array[Dictionary] = []
# Synchronous contacts only; cleared before returning from the original action step.
var _siege_contact_batch: Array[Dictionary] = []
var _siege_collect_contacts := false
var siege_shots := 0
var siege_contacts := 0

func _combat_profile_stage(stage: String, started: int) -> int:
	if not combat_profile_enabled:
		return 0
	var now := Time.get_ticks_usec()
	combat_profile_usec[stage] = int(combat_profile_usec.get(stage, 0)) + now - started
	return now

func _enter_tree() -> void:
	add_to_group(&"terrain_lab_contact_source_users")

func _ready() -> void:
	var duty_scope := _region_duty_enter()
	_region_original_ready()
	_region_duty_leave(duty_scope)

func _region_original_ready() -> void:
	if not restore_only and OS.get_cmdline_user_args().has("--site-fire-lab"):
		restore_only = true
		set_meta(&"fire_lab_fixture", {"version": FIRE_LAB_FIXTURE_VERSION, "seed": 12345})
		set_meta(&"fire_lab_boot", true)
	crowd_startup_requested = not restore_only and CrowdSiteScript.requested()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not restore_only: RenderingServer.set_default_clear_color(Color("1d242b"))
	renderer = TerrainRenderer.new()
	renderer.name = "TerrainRenderer"
	add_child(renderer)
	_fire_view = FirePresentation.new()
	_fire_view.name = "FirePresentation"
	_fire_view.lab = self
	_fire_view.z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 1
	add_child(_fire_view)
	character = TerrainTestCharacter.new()
	character.exchange_enabled = exchange_enabled
	character.name = "MovementTestCharacter"
	character.process_mode = Node.PROCESS_MODE_PAUSABLE
	character.z_index = 10
	add_child(character)
	character.initialize_visual()
	character.person_id = 1
	combat_actors.assign([character])
	# The formal scene has no default camp worker. A command-test fixture may
	# explicitly supply its own NPC before entering the tree.
	if is_instance_valid(npc):
		npc.exchange_enabled = exchange_enabled
		npc.name = "CommandTestNPC"
		npc.process_mode = Node.PROCESS_MODE_PAUSABLE
		npc.z_index = 11
		npc.visual_state.body_index = 1
		add_child(npc)
		character.opponent = npc
		npc.opponent = character
		npc.person_id = 2
		npc.faction_id = character.faction_id
		npc.auto_face = true
		combat_actors.append(npc)
	for actor: TerrainTestCharacter in combat_actors:
		actor.combat_driven_by_lab = true
		actor.exchange_enabled = exchange_enabled
		actor.exchange_skill_authorized = func() -> bool: return actor.person_id == controlled_person_id()
		actor.combatants = func() -> Array[TerrainTestCharacter]: return combat_actors
		actor.contact_sink = func(packet: Dictionary) -> void: _combat_contacts.append(packet)
	army = TerrainArmy.new()
	army.name = "DemoArmy"
	army.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(army)
	army.player = character
	army.npc = npc
	opposing_army = TerrainArmy.new()
	opposing_army.name = "OpposingArmy"
	opposing_army.process_mode = Node.PROCESS_MODE_PAUSABLE
	opposing_army.team_id = 2
	opposing_army.faction_id = 1
	add_child(opposing_army)
	third_army = TerrainArmy.new()
	third_army.name = "ThirdArmy"
	third_army.process_mode = Node.PROCESS_MODE_PAUSABLE
	third_army.team_id = 3
	third_army.faction_id = 2
	add_child(third_army)
	combat_armies.assign([army, opposing_army, third_army])
	combat_movement_coordinator = CombatMovementCoordinatorScript.new()
	for team: TerrainArmy in combat_armies:
		combat_movement_coordinator.register_formation(team)
	_configure_army_blockers()
	for team: TerrainArmy in combat_armies:
		_configure_combat_army(team)
	for actor: TerrainTestCharacter in combat_actors:
		actor.army_contacts = _collect_army_contacts
		actor.combat_target_query = _combat_target_in_site
		actor.combat_mode_query = has_combat_armies
		actor.training_query = _original_actor_training.bind(actor)
	character.cell_blocker = _armies_block_cell
	if is_instance_valid(npc): npc.cell_blocker = _armies_block_cell
	camera = Camera2D.new()
	camera.name = "LabCamera"
	add_child(camera)
	site_controller = Site.new()
	site_controller.name = "SiteController"
	add_child(site_controller)
	site_controller.setup(self)
	if restore_only:
		visible = false
		movement_input_enabled = false
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		for actor: TerrainTestCharacter in combat_actors: actor.set_process(false)
		if bool(get_meta(&"fire_lab_boot", false)):
			var fixture := _initialize_fire_lab_fixture(12345, true)
			if not fixture.ok: site_controller.show_result(fixture)
		return # No default save load or implicit fixture in an ordinary scene.
	if crowd_startup_requested:
		crowd_site = CrowdSiteScript.new()
		crowd_site.name = "CrowdSite"
		add_child(crowd_site)
		crowd_site.setup(self)
	# A main-menu/Region request opens its fixed world over this placeholder;
	# a direct scene run keeps the original default Site and save.
	var world_request: Dictionary = {} if crowd_startup_requested else RegionEntry.take_pending()
	generate_terrain(TerrainPreset.Kind.TERRACED_HIGHLAND, 12345)
	if not world_request.is_empty():
		site_controller.enter_requested_world(world_request)
	elif FileAccess.file_exists(site_controller.save_path):
		await site_controller.load_current()
	site_controller.focus_camp()
	if OS.get_cmdline_user_args().has("--site-test-ui"):
		var test_path := "res://scripts/terrain_lab/site_test_window.gd"
		if ResourceLoader.exists(test_path):
			site_test_window = load(test_path).new()
			add_child(site_test_window)
			site_test_window.call("setup", self)
		else:
			push_warning("Site test UI is unavailable; continuing with the formal UI.")
			show_status("Site 測試工具不可用；正式介面已啟動。")
	if exchange_enabled and exchange_batch_enabled:
		_prepare_exchange_kernel(true)
	call_deferred("_start_army_visual_warmup")

func _configure_combat_army(team: TerrainArmy) -> void:
	team.native_hot_enabled = scene_file_path == "res://scenes/terrain_lab/TerrainLab.tscn"
	team.person_id_allocator = _allocate_army_person_ids
	team.exchange_enabled = exchange_enabled
	team.contact_query = _collect_unit_contacts
	team.enemy_query = _nearest_unit_enemy
	team.target_query = _army_target
	team.combat_target_query = _combat_target_in_site
	team.exchange_people_query = _exchange_people.bind(false)
	team.ranged_tactics_query = _ranged_tactics
	team.contact_sink = func(packet: Dictionary) -> void: _combat_contacts.append(packet)

func _ensure_army_slots(count: int) -> void:
	while combat_armies.size() < count:
		var team := TerrainArmy.new()
		team.name = "TrialArmy%d" % combat_armies.size()
		team.defer_captain_presenter = true
		team.process_mode = Node.PROCESS_MODE_PAUSABLE
		team.team_id = _next_army_identity() + combat_armies.size()
		add_child(team)
		combat_armies.append(team)
		combat_movement_coordinator.register_formation(team)
		_configure_combat_army(team)
		site_controller.wire_combat_team(team)
	_configure_army_blockers()

func _trim_empty_army_slots() -> void:
	while combat_armies.size() > 3 and not combat_armies.back().has_army():
		var team: TerrainArmy = combat_armies.pop_back()
		combat_movement_coordinator.unregister_formation(team)
		team.queue_free()
	_configure_army_blockers()

func _start_army_visual_warmup() -> void:
	if DisplayServer.get_name() == "headless" or army == null:
		return
	army.warmup_visual_step(0)
	await get_tree().process_frame
	if is_instance_valid(army):
		army.warmup_visual_step(1)
	await get_tree().process_frame
	if is_instance_valid(army):
		army.warmup_visual_step(2)

func _notification(what: int) -> void:
	if not pause_when_unfocused:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		call_deferred("_pause_if_application_unfocused")
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_pause_if_application_unfocused(true)

func _pause_if_application_unfocused(application_paused: bool = false) -> void:
	if not pause_when_unfocused:
		return
	if not application_paused:
		for window_id: int in DisplayServer.get_window_list():
			if DisplayServer.window_is_focused(window_id):
				return
	_clear_movement_input()
	_dragging = false
	if site_controller != null and terrain != null and not terrain.site.is_empty() and not site_controller._exit_pending and not bool(terrain.site.paused):
		site_controller.toggle_pause()
		show_status("離開遊玩視窗，時間已暫停；按「繼續」恢復。")

func _build_ui(parent: Control = null) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.add_theme_font_size_override("font_size", 22)
	if parent != null:
		parent.add_child(column)
	else:
		var ui := CanvasLayer.new()
		ui.name = "TerrainLabUI"
		add_child(ui)
		var panel := PanelContainer.new()
		panel.position = Vector2(20, 20)
		panel.size = Vector2(450, get_viewport_rect().size.y - 40)
		var background := StyleBoxFlat.new()
		background.bg_color = Color("20272f")
		panel.add_theme_stylebox_override("panel", background)
		ui.add_child(panel)
		var margin := MarginContainer.new()
		for side: String in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 18)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(scroll)
		scroll.add_child(margin)
		margin.add_child(column)
	_label(column, "TERRAIN GENERATOR LAB", 25)
	_label(column, "100 x 100 cells | 64 px per cell\nStandalone terrain / no world integration", 18)
	preset_dropdown = OptionButton.new()
	preset_dropdown.add_theme_font_size_override("font_size", 22)
	for preset_name: String in TerrainPreset.NAMES:
		preset_dropdown.add_item(preset_name)
	preset_dropdown.select(terrain.preset if terrain != null else TerrainPreset.Kind.TERRACED_HIGHLAND)
	column.add_child(preset_dropdown)
	seed_input = LineEdit.new()
	seed_input.text = str(terrain.seed_value) if terrain != null else "12345"
	seed_input.placeholder_text = "Integer seed"
	seed_input.add_theme_font_size_override("font_size", 22)
	column.add_child(seed_input)
	seed_input.text_submitted.connect(func(_text: String) -> void: generate_from_ui())
	var seed_row := HBoxContainer.new()
	column.add_child(seed_row)
	_button(seed_row, "Previous", func() -> void: _change_seed(-1))
	_button(seed_row, "Next", func() -> void: _change_seed(1))
	_button(seed_row, "Random", func() -> void:
		seed_input.text = str(randi_range(0, 2147483647))
		generate_from_ui())
	generate_button = _button(column, "Generate", generate_from_ui)
	parameters_label = _label(column, "", 18)
	parameters_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parameters_label.custom_minimum_size.x = 380
	debug_toggle = CheckButton.new()
	debug_toggle.text = "Debug: grid + height labels"
	debug_toggle.button_pressed = renderer.debug_enabled
	debug_toggle.add_theme_font_size_override("font_size", 20)
	column.add_child(debug_toggle)
	debug_toggle.toggled.connect(func(enabled: bool) -> void:
		renderer.debug_enabled = enabled
		renderer.redraw())
	movement_toggle = CheckButton.new()
	movement_toggle.text = "Movement test"
	movement_toggle.button_pressed = movement_input_enabled
	movement_toggle.add_theme_font_size_override("font_size", 20)
	column.add_child(movement_toggle)
	movement_toggle.toggled.connect(func(enabled: bool) -> void:
		movement_input_enabled = enabled
		if not enabled:
			_clear_movement_input())
	if is_instance_valid(npc):
		_label(column, "工人命令測試", 20)
		npc_command_dropdown = OptionButton.new()
		npc_command_dropdown.add_theme_font_size_override("font_size", 19)
		for command_name: String in TerrainTestNPC.COMMAND_NAMES:
			npc_command_dropdown.add_item(command_name)
		npc_command_dropdown.select(TerrainTestNPC.Command.MOVE_TO_CELL)
		column.add_child(npc_command_dropdown)
		npc_command_button = _button(column, "下達工人命令", issue_npc_command)
		_label(column, "Move: issue command, then click a destination.", 16)
	_label(column, "COMBAT TEST | Space: attack | G: guard", 18)
	if is_instance_valid(npc): _button(column, "Attack NPC (equipped weapon)", func() -> void: character.start_attack(npc))
	selected_army_label = _label(column, "點選軍隊格位選中士兵；不會搬動玩家。", 16)
	_button(column, "攻擊選中的士兵（Space）", attack_selected_soldier)
	_button(column, "救助選中的友軍（相鄰施救四秒，縮短昏迷等待）", rescue_selected_soldier)
	if is_instance_valid(npc):
		_button(column, "NPC attacks player", func() -> void:
			npc.issue_command(TerrainTestNPC.Command.STOP)
			npc.start_attack(character))
		var retaliate := CheckButton.new()
		retaliate.text = "NPC auto counterattack (in reach)"
		column.add_child(retaliate)
		retaliate.toggled.connect(func(enabled: bool) -> void: npc_retaliates = enabled)
	_button(column, "Reset health / revive", func() -> void:
		character.reset_combat()
		if is_instance_valid(npc): npc.reset_combat())
	if is_instance_valid(npc):
		_button(column, "Rescue adjacent ally (4s)", func() -> void: character.start_rescue(npc))
		npc_allied_toggle = CheckButton.new()
		npc_allied_toggle.name = "NPCAllied"
		npc_allied_toggle.text = "NPC is allied (melee obstruction / rescue test)"
		npc_allied_toggle.button_pressed = npc.faction_id == character.faction_id
		column.add_child(npc_allied_toggle)
		npc_allied_toggle.toggled.connect(func(enabled: bool) -> void:
			if character.action_time <= 0.0 and npc.action_time <= 0.0 and character.projectiles.is_empty() and npc.projectiles.is_empty():
				npc.faction_id = character.faction_id if enabled else 1
			else:
				npc_allied_toggle.set_pressed_no_signal(npc.faction_id == character.faction_id))
	combat_info = _label(column, "", 18)
	_label(column, "ARMY TEST | 1 captain + 99 soldiers", 18)
	deploy_army_button = _button(column, "Deploy 100-person army", deploy_army)
	follow_army_button = _button(column, "Army: follow PLAYER", func() -> void: issue_army_command(TerrainArmy.Command.FOLLOW_PLAYER))
	edge_army_button = _button(column, "Army: formation march to map edge", func() -> void: issue_army_command(TerrainArmy.Command.MOVE_TO_EDGE))
	clear_army_button = _button(column, "Clear army", clear_army)
	army_info = _label(column, "No army / 尚未部署", 18)
	army_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	army_info.custom_minimum_size.x = 380
	var collision_toggle := CheckButton.new()
	collision_toggle.text = "Show weapon / body hitboxes"
	column.add_child(collision_toggle)
	collision_toggle.toggled.connect(func(enabled: bool) -> void:
		character.collision_debug = enabled
		if is_instance_valid(npc): npc.collision_debug = enabled)
	var camera_row := HBoxContainer.new()
	_button(column, "Player parts / animation", character.open_editor)
	column.add_child(camera_row)
	_button(camera_row, "Fit map", fit_map)
	_button(camera_row, "64px / cell", func() -> void:
		camera.zoom = Vector2.ONE
		camera.position = character.position + get_viewport_rect().size * 0.5 - camera_usable_rect().get_center()
		camera.force_update_scroll())
	_label(column, "Click ground: place test character\nHold WASD / arrows: walk\nHold Shift + WASD: run\nF: mount / dismount\nWheel: mouse-centred zoom (up to 10x)\nHold right / middle mouse: drag camera\nConnected ground through cliff: ramp\nRock edge: blocked crossing", 18)
	info = _label(column, "", 20)
	status = _label(column, "", 18)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 380
	if terrain != null:
		parameters_label.text = "PARAMETERS\n%s\nMax height: %d | Micro: %.3f" % [terrain.parameters["composition"], terrain.parameters["max_height"], terrain.parameters["micro_strength"]]
	_update_army_controls()
	return column

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = text.to_pascal_case()
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _change_seed(delta: int) -> void:
	if is_instance_valid(seed_input) and seed_input.text.is_valid_int():
		seed_input.text = str(seed_input.text.to_int() + delta)
		generate_from_ui()

func generate_from_ui() -> void:
	if not is_instance_valid(seed_input) or not is_instance_valid(preset_dropdown):
		return
	if not seed_input.text.is_valid_int():
		show_status("Seed must be an integer. Existing terrain was not changed.")
		return
	generate_terrain(preset_dropdown.selected, seed_input.text.to_int())

func generate_terrain(preset_id: int, seed_value: int) -> void:
	if preset_id < 0 or preset_id >= TerrainPreset.NAMES.size():
		show_status("Unknown terrain preset. Existing terrain was not changed.")
		return
	if site_controller != null and not site_controller.archive_before_replace():
		return
	var started: int = Time.get_ticks_usec()
	var generated := TerrainGenerator.generate(preset_id, seed_value)
	SiteEnv.initialize(generated, "crowd_test_" + site_controller.crowd_test_run_id if site_controller != null and not site_controller.crowd_test_run_id.is_empty() else "")
	generation_ms = float(Time.get_ticks_usec() - started) / 1000.0
	bind_terrain(generated)

func exchange_snapshot_guard(value: TerrainData) -> Dictionary:
	if exchange_enabled and value != null:
		for state: Dictionary in value.site.get("actors", {}).values():
			if not state.get("projectiles", []).is_empty():
				return SiteRuntime.fail("UNSUPPORTED_ACTIVE_PROJECTILES", "此舊快照仍有精確碰撞箭；不能改成新落點事件，原檔與現場保留")
	if value != null:
		# This guard runs before any Site replacement, including Controller load.
		for original: Dictionary in value.site.get("armies", []):
			if bool(original.get("crowd", false)): continue
			for unit: Dictionary in TerrainArmy.normalize_roster_snapshot(original).units:
				if str(unit.get("visual_role", "")).ends_with("live") and DisplayServer.get_name() != "headless": continue
				var appearance: Dictionary = unit.get("appearance", {})
				if appearance.is_empty():
					if not TerrainArmy.load_combat_bake(): return SiteRuntime.fail("MISSING_ASSET", "原人物碰撞素材缺失；未替換現場")
					appearance = TerrainArmy.EquipmentAtlas.female_appearance() if str(unit.get("visual_role", "")).begins_with("female") else TerrainArmy._combat_bake.manifest.appearance
				if unit.has("item_state"):
					var holder: Dictionary = unit.item_state
					if float(unit.hp) <= 0.0 and bool(unit.get("loot_settled", false)):
						holder = value.site.get("ground_loot", {}).get(str(unit.get("remains_id", "")), SiteRuntime.new_item_state("empty-remains"))
					appearance = SiteRuntime.equipment_appearance(value, holder, appearance)
				# The ordinary CPU source admits foot bodies only; keep mounted LIVE unchanged.
				if str(unit.get("visual_role", "")).ends_with("live") and bool(appearance.get("mounted", false)): continue
				if not TerrainArmy.prepare_contact_source_for(appearance):
					return SiteRuntime.fail("MISSING_ASSET", "原人物同素體碰撞素材缺失；未替換現場")
	return SiteRuntime.ok()

func prepare_crowd_load(value: TerrainData, native_candidate: Variant = null) -> Dictionary:
	if value == null: return SiteRuntime.fail("NO_TARGET")
	if not value.site.has("crowd"): return SiteRuntime.ok("", {"crowd_site": null})
	# prepare_load retains every public guard. A same-transaction detached native
	# candidate is reused only after invariants and exact blob equality pass.
	var candidate := CrowdSiteScript.new()
	candidate.setup(self)
	var prepared: Dictionary = candidate.prepare_load(value, native_candidate)
	if not prepared.ok:
		candidate.free()
		return prepared
	return SiteRuntime.ok("", {"crowd_site": candidate})

func actor_present(actor: TerrainTestCharacter) -> bool:
	return is_instance_valid(actor) and actor.person_id > 0 and actor in combat_actors

func _bind_actor_presence(value: TerrainData, states: Dictionary) -> void:
	# Explicit absence belongs to the saved Site. Retain the original visual
	# node as a template, without registering a replacement person in this Site.
	var explicit := int(value.site.get("actor_presence_version", 0)) == 1
	combat_actors.clear()
	var templates: Array[TerrainTestCharacter] = [character]
	if is_instance_valid(npc): templates.append(npc)
	for actor: TerrainTestCharacter in templates:
		var key := "player" if actor == character else "npc"
		var present := not explicit or states.has(key)
		actor.visible = present
		actor.set_process(present)
		actor.data = value
		if present:
			if actor.person_id <= 0: actor.person_id = 1 if actor == character else 2
			combat_actors.append(actor)
		else:
			actor.release_movement_intent()
			actor.reset_combat()
			actor.person_id = 0
			actor.terrain_cell = TerrainArmy.INVALID_CELL
			actor.movement_from_cell = TerrainArmy.INVALID_CELL
			actor._movement_duration = 0.0
			actor._movement_elapsed = 0.0
			# The previous Site's original holders may still be aliased here.
			# Detach the absent template; never erase its cold Site's goods.
			actor.item_state = {}
			actor.ammo_inventory = {}
			if actor is TerrainTestNPC: actor.issue_command(TerrainTestNPC.Command.STOP)

func fire_transport_bind_guard(value: TerrainData, native_candidate_active: bool = false) -> Dictionary:
	if value == null: return SiteRuntime.fail("NO_TARGET")
	var fire_state: Variant = value.site.get("fire", {})
	if not fire_state is Dictionary: return SiteRuntime.fail("CORRUPT_FIRE_SNAPSHOT")
	var checked := SiteStore._validate_fire_transport_snapshot(value, fire_state, value.site.get("fire_transport", {}))
	if not checked.ok: return checked
	var transport: Dictionary = checked.state
	if transport.is_empty() or not bool(transport.get("physical_ranged_enabled", false)): return SiteRuntime.ok()
	for order: Dictionary in transport.get("orders", {}).values():
		if not bool(order.get("enabled", false)): continue
		if native_candidate_active: return SiteRuntime.fail("UNSUPPORTED_AMMO", "Native 火攻尚未准入；保留原場景與 Fire 命令")
		if not exchange_enabled: return SiteRuntime.fail("UNSUPPORTED_AMMO", "目前射擊模式不能接手已保存的 Fire 命令；保留原場景")
	return SiteRuntime.ok()

func bind_terrain(value: TerrainData, prepared: Dictionary = {}) -> void:
	var duty_scope := _region_duty_enter()
	_region_bind_original_terrain(value, prepared)
	_region_duty_leave(duty_scope)

func _region_bind_original_terrain(value: TerrainData, prepared: Dictionary = {}) -> void:
	var region_admission := _region_bind_ticket_admission(value, prepared)
	if not region_admission.ok:
		if site_controller != null: site_controller.show_result(region_admission)
		return
	var trusted_region := bool(region_admission.get("trusted", false))
	if not trusted_region:
		if not fire_save_guard().ok: return
		if not SiteStore.fire_event_guard(value).ok: return
		var journey_guard := _ship_journey_guard()
		if not journey_guard.ok:
			if site_controller != null: site_controller.show_result(journey_guard)
			return
		if has_unpersisted_ranged_projectiles():
			if site_controller != null:
				site_controller.show_result(SiteRuntime.fail("BUSY", "箭矢仍在飛行，不能換場或遺失已扣彈藥的結算"))
			return
		var compatible := exchange_snapshot_guard(value)
		if not compatible.ok:
			if site_controller != null: site_controller.show_result(compatible)
			return
	if not is_instance_valid(npc) and not trusted_region:
		var retired := SiteStore.retire_default_worker(value)
		if not retired.ok:
			if site_controller != null:
				site_controller._auto_save_blocked = true
				site_controller.show_result(retired)
			return
	if prepared.is_empty(): prepared = prepare_crowd_load(value)
	if not bool(prepared.get("ok", false)):
		if site_controller != null: site_controller.show_result(prepared)
		return
	var transport_guard := SiteRuntime.ok() if trusted_region else fire_transport_bind_guard(value,
		is_instance_valid(prepared.get("crowd_site")) or crowd_startup_requested)
	if not transport_guard.ok:
		if site_controller != null: site_controller.show_result(transport_guard)
		return
	# All guards and native staging have succeeded; only now retire the old world.
	if crowd_site != null:
		crowd_site.discard_on_replace()
		crowd_site.queue_free()
		crowd_site = null
	_reset_action_elapsed_input()
	_action_time_remainder = 0.0 # A replaced/loaded Site starts from its own saved simulation time.
	_exchange_phase = 0.0
	_tactical_ai_elapsed = 0.0
	_duty_ai_elapsed = 0.0
	DutyAI.reset_site_state() # F02: AI rounds, waits and traces belong to one Site.
	if site_controller != null: site_controller.captive_escort.reset_site_state()
	_exchange_round = 0
	ranged_shots = 0
	ranged_resolutions = 0
	for kind: String in ranged_results:
		ranged_results[kind] = 0
	for team: TerrainArmy in combat_armies:
		team.clear()
	if combat_movement_coordinator != null:
		combat_movement_coordinator.reset_for_site_replacement()
	_trim_empty_army_slots()
	if not restore_only: TerrainArmy.clear_contact_sources_for_bind()
	_clear_movement_input()
	_npc_target_pending = false
	_region_bound_data = null
	_region_bind_receipt_value = {"ok": false, "complete": false, "code": "REGION_BIND_PENDING"}
	terrain = value
	# Resume the original completed Fire interval from its persisted Site owner.
	var saved_fire_settlement: Dictionary = terrain.site.get("fire_settlement", {})
	var saved_fire: Dictionary = terrain.site.get("fire", {})
	var saved_transport: Dictionary = terrain.site.get("fire_transport", {})
	fire_action_cursor = float(terrain.get_meta(&"fire_completed_action_end", saved_fire_settlement.get("action_seconds",
		saved_fire.get("observed_action_end", saved_transport.get("action_cursor", 0.0)))))
	terrain.set_meta(&"fire_completed_action_end", fire_action_cursor)
	_wire_fire_ranged()
	terrain.set_meta(&"site_garrison_lab", weakref(self))
	terrain.set_meta(&"region_life_consumer", Callable(self, "consume_region_life_events"))
	_region_point_pending.clear()
	_region_point_contacts.clear()
	_region_point_wakes.clear()
	_region_point_consuming = false
	var actor_states: Dictionary = terrain.site.get("actors", {})
	_bind_actor_presence(terrain, actor_states)
	renderer.display(terrain)
	if actor_present(character):
		character.terrain_cell = Vector2i(-1, -1)
		character.place(terrain.cell_from_index(int(terrain.site.get("player_cell", terrain.index(terrain.spawn_cell)))), true)
		character.reset_combat()
	if actor_present(npc):
		npc.terrain_cell = Vector2i(-1, -1)
		npc.set_data(terrain)
		var worker_cell := terrain.cell_from_index(int(terrain.site.worker.cell))
		if not terrain.is_walkable(worker_cell) or worker_cell == character.terrain_cell:
			worker_cell = _find_npc_spawn_cell()
		npc.place(worker_cell, true)
		npc.issue_command(TerrainTestNPC.Command.STOP)
		npc.reset_combat()
	if not actor_states.is_empty():
		if actor_present(character) and actor_states.has("player"): character.restore_state(actor_states.player)
		if actor_present(npc) and actor_states.has("npc"): npc.restore_state(actor_states.npc)
	else:
		# New Site / explicit format-1 migration creates fresh test people.
		# Do not leak the previous map's body state into missing snapshots.
		for actor: TerrainTestCharacter in combat_actors:
			actor.item_state.clear()
			actor.loot_settled = false
			actor.remains_id = ""
			actor.fatigue = 0.0
			actor.fatigue_rest = 0.0
			actor._fatigue_slowdown = 0.0
	for actor: TerrainTestCharacter in combat_actors:
		if actor.has_meta(&"crowd_handoff"): actor.remove_meta(&"crowd_handoff")
		var snapshot: Dictionary = actor_states.get("player" if actor == character else "npc", {})
		if snapshot.has("crowd_handoff"):
			var handoff: Dictionary = snapshot.crowd_handoff.duplicate(true)
			actor.set_meta(&"crowd_handoff", handoff)
			actor.exchange_stagger = float(handoff.stagger)
			actor.exchange_cooldown = float(handoff.exch_cd)
			actor.ranged_cooldown = float(handoff.ranged_cd)
			actor.exchange_skill_cooldown = float(handoff.skill_cd)
	var army_states: Array = terrain.site.get("armies", []).duplicate()
	var active_army_count := 0
	for roster: Dictionary in army_states:
		if not bool(roster.get("crowd", false)): active_army_count += 1
	_ensure_army_slots(army_states.size())
	_configure_army_blockers(active_army_count > 2)
	for index in range(army_states.size()):
		if bool(army_states[index].get("crowd", false)):
			combat_armies[index].restore_crowd_command_source(army_states[index], terrain, combat_actors)
		else:
			combat_armies[index].restore_combat_state(army_states[index], terrain, character, npc)
	var prepared_fire_transport := _prepare_fire_transport_restore()
	if not prepared_fire_transport.ok:
		if site_controller != null: site_controller.show_result(prepared_fire_transport)
		return
	if not actor_states.is_empty():
		var identities := {}
		for actor: TerrainTestCharacter in combat_actors: identities[actor.person_id] = actor
		if actor_present(character) and actor_states.has("player"): character.restore_links(actor_states.player, identities)
		if actor_present(npc) and actor_states.has("npc"): npc.restore_links(actor_states.npc, identities)
	selected_army_target = 0
	if is_instance_valid(npc) and is_instance_valid(npc_allied_toggle):
		npc_allied_toggle.set_pressed_no_signal(npc.faction_id == character.faction_id)
	if is_instance_valid(seed_input): seed_input.text = str(terrain.seed_value)
	if is_instance_valid(preset_dropdown): preset_dropdown.select(terrain.preset)
	if is_instance_valid(prepared.get("crowd_site")):
		crowd_site = prepared.crowd_site
		crowd_site.name = "CrowdSite"
		add_child(crowd_site)
		crowd_site.activate_loaded()
	elif crowd_startup_requested:
		crowd_site = CrowdSiteScript.new()
		crowd_site.name = "CrowdSite"
		add_child(crowd_site)
		crowd_site.setup(self)
	site_controller.bind()
	# Fire work snapshots use the original ranged-order serials stored by transport.
	var restored_fire_transport := _publish_fire_transport_restore(prepared_fire_transport.prepared)
	if not restored_fire_transport.ok:
		site_controller.show_result(restored_fire_transport)
		return
	var restored_fire_owners := _restore_fire_owners()
	if not restored_fire_owners.ok:
		site_controller.show_result(restored_fire_owners)
		return
	# Restore the original cadence before applying the complete owner graph;
	# graph restoration may legitimately restore its exact in-progress counter.
	_duty_ai_elapsed = DutyAI.restore_cadence(self)
	var region_restored := _region_finish_bind_ticket(region_admission) if trusted_region else _restore_region_owners()
	if not region_restored.ok:
		site_controller.show_result(region_restored)
		return
	_wire_region_point_owners()
	_region_bound_data = terrain
	if _region_owner_restore_receipt.is_empty():
		_region_owner_restore_receipt = {"ok": true, "owners_restored": true, "effects_complete": true, "bind_complete": false}
	_region_bind_receipt_value = {"ok": true, "complete": not bool(region_admission.get("projection", false)), "owners_restored": bool(region_restored.get("owners_restored", true)),
		"effects_complete": bool(region_restored.get("effects_complete", true)), "zero_world_only": bool(region_restored.get("zero_world_only", false)), "owner": str(terrain.site.get("id", "")),
		"mode": "cold_exact" if restore_only else "live", "consumer": "original_replay" if restore_only else "original_site",
		"backend": "native" if crowd_site != null and crowd_site.active else "gd",
		"generation": int(site_controller.region_slot._marker.get("generation", 0)) if site_controller.region_slot != null else 0,
		"session": str(OS.get_process_id()) + ":" + str(get_instance_id()),
		"parts": ["actors", "armies", "movement", "items", "supply", "controller", "fire_transport", "fire_owners", "region_owners"]}
	terrain.set_meta(&"region_bind_receipt", Callable(self, "region_bind_receipt"))
	if not restore_only and site_controller.region_slot != null:
		var activated: Dictionary = site_controller.region_slot.acknowledge_region_bind(terrain, region_bind_receipt(terrain))
		if not activated.ok:
			_region_bind_receipt_value = activated
			site_controller.show_result(activated)
			return
	if is_instance_valid(parameters_label):
		parameters_label.text = "PARAMETERS\n%s\nMax height: %d | Micro: %.3f" % [terrain.parameters["composition"], terrain.parameters["max_height"], terrain.parameters["micro_strength"]]
	show_status("地圖已就緒。點選查看，使用方向鍵移動人物。")
	fit_map()
	get_viewport().gui_release_focus()
	_update_info()
	_update_army_controls()

func region_bind_receipt(data: TerrainData) -> Dictionary:
	if terrain != data or _region_bound_data != data or _region_bind_receipt_value.get("complete") != true:
		return SiteRuntime.fail("REGION_BIND_INCOMPLETE", "原人物／物品／租約／controller 尚未完整綁定")
	var result := _region_bind_receipt_value.duplicate(true)
	result.generation = int(site_controller.region_slot._marker.get("generation", 0)) if site_controller != null and site_controller.region_slot != null else 0
	return result

func _next_army_identity() -> int:
	var next_team := int(terrain.site.get("army_next_team", 1))
	for team: TerrainArmy in combat_armies:
		if team.has_army():
			next_team = maxi(next_team, team.team_id + 1)
	for identity: String in terrain.site.get("team_supply", {}):
		next_team = maxi(next_team, int(identity) + 1)
	return next_team

func _armies_block_cell(cell: Vector2i, ignored: Variant = null) -> bool:
	for team: TerrainArmy in combat_armies:
		if team != ignored and team.blocks_cell(cell, ignored):
			return true
	return false

func _configure_army_blockers(with_third: bool = false) -> void:
	# Preserve the original pair's canonical fast readers while the third slot is empty.
	var three := with_third or combat_armies.size() > 3 or third_army != null and third_army.has_army()
	for team: TerrainArmy in combat_armies:
		if three or team == third_army:
			team.external_blocker = _armies_block_cell.bind(team)
		else:
			team.external_blocker = opposing_army.blocks_cell if team == army else army.blocks_cell

func _next_army_person_id() -> int:
	return _next_army_person_id_for(terrain, combat_actors, combat_armies)

func _can_allocate_army_person_ids(count: int) -> bool:
	var next_person := _next_army_person_id()
	if next_person <= TerrainArmy.PLAYER_MEMBER and next_person + count >= TerrainArmy.PLAYER_MEMBER:
		next_person = TerrainArmy.PLAYER_MEMBER + 1
	return count >= 0 and next_person + count <= 2147483647

func _allocate_army_person_ids(count: int) -> Array[int]:
	return _allocate_army_person_ids_for(count, terrain, combat_actors, combat_armies)

func deploy_army() -> void:
	if army == null or terrain == null or army.has_army():
		return
	var next_team := _next_army_identity()
	if next_team >= 999999:
		show_status("軍隊身分序號已用盡；未生成新人物。")
		return
	army.team_id = next_team
	var start_usec := Time.get_ticks_usec()
	var deployed := army.deploy(terrain, character, npc)
	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	if deployed:
		terrain.site["army_next_team"] = next_team + 1
		print("ARMY_DEPLOY_BENCHMARK: deployed %d members in %.2f ms" % [army.roster_size, elapsed_ms])
	show_status(army.command_status)
	_update_army_controls()
	_update_info()
	if not deployed:
		return

func clear_army() -> void:
	var journey_guard := _ship_journey_guard()
	if not journey_guard.ok:
		if site_controller != null: site_controller.show_result(journey_guard)
		return
	if crowd_site != null and crowd_site.active:
		var result: Dictionary = crowd_site.clear()
		site_controller.show_result(result)
		if bool(result.ok): site_controller.clear_team_info_report()
		return
	if army == null:
		return
	for team: TerrainArmy in combat_armies:
		if not team.garrison_feature_id.is_empty() and not team.combat_units.is_empty():
			site_controller.show_result(SiteRuntime.fail("BUSY", "軍營仍有原兵員，不能用清除測試隊伍刪除；請先編成出營"))
			return
	if site_controller != null and terrain != null and not terrain.site.is_empty():
		var guard: Dictionary = site_controller.before_clear_team_items()
		if not guard.ok:
			site_controller.show_result(guard)
			return
	if terrain != null and not terrain.site.is_empty():
		terrain.site["army_next_team"] = _next_army_identity()
		_allocate_army_person_ids(0)
		if site_controller != null:
			for team: TerrainArmy in combat_armies:
				site_controller.before_clear_team_supply(team)
	selected_army_target = 0
	for actor: TerrainTestCharacter in combat_actors:
		var target := _combat_target(actor.attack_target_id)
		if not target.is_empty() and target.owner is TerrainArmy:
			actor.attack_target_id = 0
	for team: TerrainArmy in combat_armies:
		team.clear()
	TerrainArmy.release_captain_geometry_pool()
	_trim_empty_army_slots()
	_configure_army_blockers()
	if terrain != null and not terrain.site.is_empty():
		terrain.site["army_trial_active"] = false
		terrain.site["armies"] = []
		terrain.site["corps"] = {} # All referenced trial teams were just removed.
	if site_controller != null: site_controller.clear_team_info_report()
	show_status("Army cleared.")
	_update_army_controls()
	_update_info()

func issue_army_command(command_id: int) -> bool:
	if site_controller != null and site_controller._region_player_input_blocks(): return false
	if army == null:
		return false
	var accepted := army.issue_command(command_id)
	show_status(army.command_status)
	_update_army_controls()
	_update_info()
	return accepted

func _exit_tree() -> void:
	_clear_shared_work_step()
	remove_from_group(&"terrain_lab_contact_source_users")
	if get_tree().get_nodes_in_group(&"terrain_lab_contact_source_users").is_empty():
		TerrainArmy.release_contact_source()

func _update_army_controls() -> void:
	var active := army != null and army.has_army()
	if is_instance_valid(deploy_army_button):
		deploy_army_button.disabled = active
	if is_instance_valid(follow_army_button):
		follow_army_button.disabled = not active
	if is_instance_valid(edge_army_button):
		edge_army_button.disabled = not active
	if is_instance_valid(clear_army_button):
		clear_army_button.disabled = not active

func _find_npc_spawn_cell() -> Vector2i:
	if terrain == null:
		return Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var candidate := terrain.spawn_cell + direction
		if terrain.can_step(terrain.spawn_cell, candidate):
			return candidate
	for radius: int in range(2, 12):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				var candidate := terrain.spawn_cell + Vector2i(x, y)
				if terrain.is_walkable(candidate):
					return candidate
	return terrain.spawn_cell

func fit_map() -> void:
	if terrain == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var extent := Vector2(terrain.size) * TerrainRenderer.CELL_PIXELS
	var area := camera_usable_rect()
	var fit: float = minf(area.size.x / extent.x, area.size.y / extent.y)
	camera.zoom = Vector2.ONE * maxf(0.1, fit)
	camera.position = extent * 0.5 + (viewport_size * 0.5 - area.get_center()) / camera.zoom.x
	camera.force_update_scroll()

func camera_usable_rect() -> Rect2:
	if site_controller != null and site_controller.has_method("camera_usable_rect"):
		return site_controller.camera_usable_rect()
	return get_viewport_rect()

func show_status(text: String) -> void:
	if is_instance_valid(status):
		status.text = text
	if site_controller != null and is_instance_valid(site_controller.message):
		site_controller.message.text = text

func issue_npc_command(command_id: int = -1, requested_target: Vector2i = Vector2i(-1, -1)) -> bool:
	if not actor_present(npc) or terrain == null:
		return false
	if site_controller != null:
		site_controller.release_worker()
	var selected_command := npc_command_dropdown.selected if command_id < 0 and is_instance_valid(npc_command_dropdown) else command_id
	var target := requested_target
	if selected_command == TerrainTestNPC.Command.MOVE_TO_CELL and target == Vector2i(-1, -1):
		_npc_target_pending = true
		show_status("Click map to choose NPC destination.")
		get_viewport().gui_release_focus()
		return true
	_npc_target_pending = false
	if target == Vector2i(-1, -1):
		target = renderer.pick_cell(get_viewport().get_mouse_position())
	var accepted := npc.issue_command(selected_command, target, character)
	show_status("NPC: %s" % npc.command_status)
	return accepted

func zoom_at(viewport_point: Vector2, factor: float) -> void:
	var before: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * viewport_point
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.force_update_scroll()
	var after: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * viewport_point
	camera.position += before - after
	camera.force_update_scroll()

func _direction_for_key(key: int) -> Vector2i:
	match key:
		KEY_W, KEY_UP:
			return Vector2i.UP
		KEY_D, KEY_RIGHT:
			return Vector2i.RIGHT
		KEY_S, KEY_DOWN:
			return Vector2i.DOWN
		KEY_A, KEY_LEFT:
			return Vector2i.LEFT
	return Vector2i.ZERO

func _event_key(event: InputEventKey) -> int:
	return event.physical_keycode if event.physical_keycode != 0 else event.keycode

func _is_shift_key(event: InputEventKey) -> bool:
	return event.keycode == KEY_SHIFT or event.physical_keycode == KEY_SHIFT

func _held_direction() -> Vector2i:
	if _held_directions.has(_last_direction_key):
		return _held_directions[_last_direction_key]
	for direction: Variant in _held_directions.values():
		return direction
	return Vector2i.ZERO

func _clear_movement_input() -> void:
	_held_directions.clear()
	_last_direction_key = -1
	_run_held = false
	_release_movement_input_actor()
	if crowd_site != null and crowd_site.active:
		crowd_site.engage = false
		crowd_site.set_input(Vector2.ZERO, false)
	else:
		var person := controlled_target()
		if not person.is_empty():
			var guarding: bool = str(person.owner.combat_hot_get(int(person.unit), &"pose")) == "guard" if int(person.unit) >= 0 else bool(person.owner.guarding)
			if guarding:
				controlled_guard(false)
	if is_instance_valid(site_controller):
		site_controller.drag_start = Vector2i(-1, -1)

func _release_movement_input_actor() -> void:
	if is_instance_valid(_movement_input_actor):
		_movement_input_actor.release_movement_intent()
	_movement_input_actor = null

func _advance_movement_input() -> void:
	# The original body owns its committed step. Input is sampled once per shared
	# action tick, never once per rendered frame or with a second move cooldown.
	if not movement_input_enabled:
		_clear_movement_input()
		if crowd_site != null and crowd_site.active:
			crowd_site.set_input(Vector2.ZERO, false)
		return
	if crowd_site != null and crowd_site.active:
		# the player is a crowd soldier: held keys are only his wish to walk (all held keys combined)
		var wish := Vector2.ZERO
		for held: Vector2i in _held_directions.values():
			wish += Vector2(held)
		if wish != Vector2.ZERO and site_controller != null and site_controller.person_actions.intercept_housing_input(controlled_person_id()):
			crowd_site.set_input(Vector2.ZERO, false)
			return
		crowd_site.set_input(wish, _run_held)
		return
	var direction := _held_direction()
	if direction != Vector2i.ZERO and site_controller != null and site_controller.person_actions.intercept_housing_input(controlled_person_id()): return
	var person := controlled_target()
	if direction == Vector2i.ZERO or person.is_empty():
		_release_movement_input_actor()
		return
	if int(person.unit) >= 0:
		_release_movement_input_actor()
		if person.owner.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL:
			return
	else:
		if is_instance_valid(_movement_input_actor) and _movement_input_actor != person.owner:
			_release_movement_input_actor()
		_movement_input_actor = person.owner
		if person.owner.is_moving():
			# Facing can be changed by combat auto-face; only the committed edge
			# describes travel. Finish that edge before reserving a new direction.
			if direction != person.owner.terrain_cell - person.owner.movement_from_cell:
				person.owner.steer_movement_intent(direction)
			return
	# A blocked attempt is bounded to this one tick and adds no full-step delay.
	_try_move(direction)

func controlled_person_id() -> int:
	var original_id: int = character.person_id if is_instance_valid(character) else 0
	return int(terrain.site.get("controlled_person_id", original_id)) if terrain != null else original_id

func controlled_target() -> Dictionary:
	return _combat_target(controlled_person_id())

func controlled_member_index(team: TerrainArmy) -> int:
	if team == null:
		return -1
	if is_instance_valid(team.player_member) and team.player_member.person_id == controlled_person_id():
		return TerrainArmy.PLAYER_MEMBER
	for index in range(team.combat_units.size()):
		if team.combat_identity(index) == controlled_person_id() and team.is_member(index):
			return index
	return -1

func controlled_attack(target_id: int) -> bool:
	if _region_operation_pending(): return false
	if _ship_person_in_journey(controlled_person_id()): return false
	if site_controller != null and site_controller.person_actions.intercept_housing_input(controlled_person_id()): return false
	if crowd_site != null and crowd_site.active and crowd_site.contains_person(controlled_person_id()):
		var crowd_target: Dictionary = crowd_site.combat_target(target_id)
		if crowd_target.is_empty() or target_id == controlled_person_id(): return false
		crowd_site.engage = true
		return true
	if _ship_embarked(controlled_person_id()) and not site_controller.vehicles.ship_can_attack(controlled_person_id()): return false
	var person := controlled_target()
	var target := _combat_target_in_site(target_id)
	if person.is_empty() or target.is_empty() or target_id == controlled_person_id():
		return false
	if int(person.unit) >= 0:
		return person.owner.start_unit_attack(int(person.unit), target.cell, target_id)
	return person.owner.start_attack_unit(target.owner, int(target.unit)) if int(target.unit) >= 0 else person.owner.start_attack(target.owner)

func controlled_guard(enabled: bool) -> void:
	if _region_operation_pending(): return
	if _ship_person_in_journey(controlled_person_id()): return
	if site_controller != null and site_controller.person_actions.intercept_housing_input(controlled_person_id()): return
	if crowd_site != null and crowd_site.active:
		show_status("群眾戰鬥由戰場規則防禦；按住空白鍵出手")
		return
	if _ship_embarked(controlled_person_id()) and not site_controller.vehicles.ship_can_attack(controlled_person_id()): return
	var person := controlled_target()
	if person.is_empty():
		return
	if int(person.unit) >= 0:
		person.owner.set_unit_guard(int(person.unit), enabled)
	else:
		person.owner.set_guard(enabled)

func controlled_exchange_skill(skill: String) -> bool:
	if _region_operation_pending(): return false
	if _ship_person_in_journey(controlled_person_id()): return false
	if crowd_site != null and crowd_site.active:
		show_status("群眾戰鬥中此技能尚不支援；人物狀態未改")
		return false
	if not exchange_enabled or get_tree().paused:
		return false
	if _ship_embarked(controlled_person_id()) and not site_controller.vehicles.ship_can_attack(controlled_person_id()): return false
	var person := controlled_target()
	if person.is_empty():
		return false
	var accepted: bool = person.owner.activate_exchange_skill(int(person.unit), skill) if int(person.unit) >= 0 else person.owner.activate_exchange_skill(skill)
	show_status(("穩守：下次交鋒能力 +15，抵抗擊退" if skill == "brace" else "強攻：下次交鋒能力 +15，勝出多加 10 暈眩") if accepted else "技能尚未冷卻或人物無法行動")
	return accepted

func _report_move(moved: bool) -> void:
	if moved:
		var person := controlled_target()
		var i: int = terrain.index(person.cell)
		show_status("Moved to %s, height %d" % [person.cell, terrain.height_levels[i]])
	else:
		show_status("Blocked: water, cliff edge or map boundary. Use a marked ramp.")

func _try_move(direction: Vector2i) -> void:
	if _region_operation_pending(): return
	if _ship_person_in_journey(controlled_person_id()): return
	if site_controller != null and (site_controller.ground_crossing_blocks_input() or site_controller.region_operation_pending()): return
	if site_controller != null and site_controller.person_actions.intercept_housing_input(controlled_person_id()): return
	if crowd_site != null and crowd_site.active:
		crowd_site.set_input(Vector2(direction), _run_held)
		return
	if _ship_embarked(controlled_person_id()): return # Boarding relation never creates a land step.
	var running := _run_held
	var person := controlled_target()
	if person.is_empty() or get_tree().paused or bool(terrain.site.get("paused", false)):
		return
	if not terrain.contains(Vector2i(person.cell) + direction):
		var team := player_army()
		if team != null:
			var exit_result: Dictionary = team.exit_controlled_site_retreat(controlled_member_index(team), direction)
			if bool(exit_result.get("ok", false)):
				_clear_movement_input()
				show_status(str(exit_result.message))
				return
		elif int(person.unit) < 0 and site_controller != null:
			var crossing: Dictionary = site_controller.begin_ground_crossing(controlled_person_id(), direction)
			site_controller.show_result(crossing)
			return
	if int(person.unit) >= 0:
		_report_move(person.owner._reserve_combat_step(int(person.unit), Vector2i(person.cell) + direction, 0, running))
	else:
		if is_instance_valid(_movement_input_actor) and _movement_input_actor != person.owner:
			_release_movement_input_actor()
		_movement_input_actor = person.owner
		var moved: bool = person.owner.step(direction, running)
		if not moved:
			person.owner.release_movement_intent()
		_report_move(moved)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		_dragging = false
	if is_instance_valid(site_test_window) and bool(site_test_window.call("handle_shortcut", event)):
		return
	if get_viewport().gui_get_focus_owner() != null:
		_clear_movement_input()
		if crowd_site != null and crowd_site.active:
			crowd_site.engage = false
			crowd_site.set_input(Vector2.ZERO, false)
	# GUI controls consume mouse releases before _unhandled_input sees them.
	if site_controller != null:
		site_controller.cancel_facing_move_on_gui_input(event)

func _unhandled_input(event: InputEvent) -> void:
	if site_controller != null and (site_controller.ground_crossing_blocks_input() or site_controller.region_operation_pending()):
		_clear_movement_input()
		return
	if event is InputEventKey and get_viewport().gui_get_focus_owner() != null:
		_clear_movement_input()
		return
	if character.is_editor_open() or (is_instance_valid(npc) and npc.is_editor_open()):
		_clear_movement_input()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().gui_release_focus()
	if site_controller != null and site_controller.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if (get_tree().paused or terrain != null and bool(terrain.site.get("paused", false))) and event is InputEventKey:
		_clear_movement_input()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mouse.pressed
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(mouse.position, ZOOM_STEP)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(mouse.position, 1.0 / ZOOM_STEP)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and movement_input_enabled:
			if get_tree().paused:
				return
			var cell := renderer.pick_cell(mouse.position)
			if _npc_target_pending:
				issue_npc_command(TerrainTestNPC.Command.MOVE_TO_CELL, cell)
				return
			if select_army_target(cell):
				return
			if crowd_site != null and crowd_site.active:
				return # the crowd owns the player's body; no teleport by click
			if not test_placement_enabled:
				return
			if not actor_present(character) or controlled_person_id() != character.person_id or (actor_present(npc) and npc.occupies_cell(cell)) or character.action_time > 0 or not character.can_act():
				return
			var placed: bool = character.place(renderer.pick_cell(mouse.position))
			show_status("Placed on platform." if placed else "Cannot place on water / outside the map.")
	elif event is InputEventMouseMotion and _dragging:
		camera.position -= (event as InputEventMouseMotion).relative / camera.zoom
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		var key := _event_key(key_event)
		if exchange_enabled and key in [KEY_Q, KEY_E] and key_event.pressed and not key_event.echo:
			controlled_exchange_skill("brace" if key == KEY_Q else "power")
			get_viewport().set_input_as_handled()
			return
		if crowd_site != null and crowd_site.active and key == KEY_SPACE and not key_event.echo:
			crowd_site.engage = key_event.pressed and movement_input_enabled # hold Space: fight whoever is in reach
			get_viewport().set_input_as_handled()
			return
		if key == KEY_SPACE and key_event.pressed and not key_event.echo and movement_input_enabled:
			if selected_army_target > 0:
				attack_selected_soldier()
			else:
				show_status("請先點選敵方軍隊人物；工人不再是預設攻擊目標。")
			get_viewport().set_input_as_handled()
			return
		if key == KEY_G and not key_event.echo:
			controlled_guard(key_event.pressed)
			get_viewport().set_input_as_handled()
			return
		if _is_shift_key(key_event):
			_run_held = key_event.pressed
			get_viewport().set_input_as_handled()
			return
		var direction := _direction_for_key(key)
		if direction != Vector2i.ZERO:
			if key_event.pressed and not key_event.echo and movement_input_enabled:
				_held_directions[key] = direction
				_last_direction_key = key
			elif not key_event.pressed:
				_held_directions.erase(key)
				if _held_directions.is_empty():
					_release_movement_input_actor()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F and key_event.pressed and not key_event.echo and movement_input_enabled:
			var person := controlled_target()
			if person.is_empty() or int(person.unit) >= 0:
				show_status("目前接管人物不支援原騎乘快捷測試")
			else:
				var was_mounted: bool = person.owner.is_mounted()
				person.owner.toggle_mount()
				var mounted: bool = person.owner.is_mounted()
				show_status("移動或忙碌中，請停下再上下馬" if mounted == was_mounted else ("Mounted horse. Ride with WASD + Shift." if mounted else "Dismounted."))
			get_viewport().set_input_as_handled()

func _reset_action_elapsed_input() -> void:
	_process_sample_usec = -1
	_process_sample_frame = -1
	_process_sample_active = false

func _action_elapsed_input(delta: float) -> float:
	if site_controller != null and (site_controller.ground_crossing_blocks_clock() or site_controller.region_operation_pending()):
		_reset_action_elapsed_input()
		return 0.0
	# Godot caps process delta after slow frames. Recover elapsed only between
	# consecutive live callbacks; disabled/manual, paused and movie steps keep
	# their supplied delta. This feeds the original retained clock below.
	# ponytail: current callers skip frames while disabled; a future same-frame
	# disable/re-enable caller must explicitly reset this input sample.
	var now := Time.get_ticks_usec()
	var frame := Engine.get_process_frames()
	var active := is_inside_tree() and is_processing() and not get_tree().paused \
		and (terrain == null or not bool(terrain.site.get("paused", false)))
	var elapsed := delta
	if _process_use_wall_elapsed and active and _process_sample_active and frame == _process_sample_frame + 1:
		elapsed = float(now - _process_sample_usec) / 1000000.0 * Engine.time_scale
	_process_sample_usec = now
	_process_sample_frame = frame
	_process_sample_active = active
	if action_elapsed_measure_enabled:
		action_elapsed_input_sum += elapsed
		action_elapsed_input_count += 1
	return elapsed

func _process(delta: float) -> void:
	if restore_only: return
	var process_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	delta = _action_elapsed_input(delta)
	_combat_profile_stage("process_input", process_started)
	_fatigue_work_seconds.clear()
	if get_tree().paused:
		if site_controller != null:
			site_controller.tick(delta)
		_combat_profile_stage("process_total", process_started)
		return
	var live_clock := _process_use_wall_elapsed and _process_sample_active
	var action_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	if not live_clock or Engine.time_scale > 0.0:
		_advance_action_time(delta, ACTION_FRAME_BUDGET_USEC if live_clock else 0)
	_combat_profile_stage("action_outer", action_started)
	if crowd_site != null and crowd_site.active:
		crowd_site.render(delta)
	if get_tree().paused:
		_combat_profile_stage("process_total", process_started)
		return
	var finish_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	if site_controller != null:
		site_controller.finish_tick()
	_combat_profile_stage("finish_tick_outer", finish_started)
	if site_controller != null and (site_controller.ground_crossing_blocks_clock() or site_controller.region_operation_pending()): return
	var retaliation_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	if actor_present(npc) and actor_present(character) and npc.person_id != controlled_person_id() and npc_retaliates and movement_input_enabled and npc.can_act() and character.can_act() and npc.faction_id != character.faction_id:
		var offset := character.terrain_cell - npc.terrain_cell
		if absi(offset.x) + absi(offset.y) == 1 and terrain.can_step(npc.terrain_cell, character.terrain_cell):
			npc.start_attack(character)
	_combat_profile_stage("retaliation_outer", retaliation_started)
	_info_time += delta
	var info_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	if _info_time >= 0.1:
		_info_time = 0.0
		_update_info()
	_combat_profile_stage("update_info_outer", info_started)
	_combat_profile_stage("process_total", process_started)

func change_simulation_speed(direction: int) -> float:
	var index := SIMULATION_SPEEDS.find(simulation_speed)
	if index < 0:
		index = 1
	index = clampi(index + signi(direction), 0, SIMULATION_SPEEDS.size() - 1)
	simulation_speed = SIMULATION_SPEEDS[index]
	if site_controller != null:
		site_controller.update_ui()
	return simulation_speed

# Insert on ORIGINAL TerrainLab. Replaces only _advance_action_time; its
# original _advance_combat continues to own every fatigue/supply/death phase.
func _advance_action_time(delta: float, budget_usec: int = 0) -> void:
	if restore_only or not is_finite(delta) or delta <= 0.0:
		return
	if (is_inside_tree() and get_tree().paused) or (terrain != null and bool(terrain.site.get("paused", false))):
		return
	if site_controller != null and (site_controller.ground_crossing_blocks_clock() or site_controller.region_operation_pending()): return
	var deadline := Time.get_ticks_usec() + budget_usec if budget_usec > 0 else 0
	var step := EXCHANGE_ACTION_STEP if exchange_enabled else ACTION_STEP
	if exchange_enabled or fixed_action_steps_enabled:
		_action_time_remainder += delta
		while _action_time_remainder + ACTION_TIME_EPSILON >= step:
			var source_before_step: TerrainData = terrain
			var result := _advance_original_shared_step(step)
			if bool(result.get("completed", false)) and terrain != source_before_step: return
			# Body time is consumed even when its AFTER-step publisher reports an
			# error. Never run completed work a second time on the next frame.
			if bool(result.get("completed", false)):
				_action_time_remainder -= float(result.get("action_seconds", step))
			if str(result.get("status", "")) in ["FIRE_SYNC_PENDING", "REGION_EVENT_PENDING"]: return
			if not bool(result.get("ok", false)):
				if site_controller != null: site_controller.show_result(result)
				return
			if site_controller.ground_crossing_blocks_clock() or site_controller.region_operation_pending(): return
			if (is_inside_tree() and get_tree().paused) or bool(terrain.site.get("paused", false)):
				return
			if deadline > 0 and Time.get_ticks_usec() >= deadline:
				return
		return
	# Retain the existing nonfixed 120 Hz mode's render-boundary fraction.
	var remaining := delta + _action_time_remainder
	_action_time_remainder = 0.0
	while remaining > 0.0:
		var elapsed := minf(remaining, step)
		var source_before_step: TerrainData = terrain
		var result := _advance_original_shared_step(elapsed)
		if str(result.get("status", "")) in ["FIRE_SYNC_PENDING", "REGION_EVENT_PENDING"]:
			if bool(result.get("completed", false)): remaining = maxf(0.0, remaining - float(result.get("action_seconds", elapsed)))
			_action_time_remainder += remaining
			return
		if not bool(result.get("ok", false)):
			if site_controller != null: site_controller.show_result(result)
			return
		if terrain != source_before_step: return
		remaining -= float(result.get("action_seconds", elapsed))
		if site_controller.ground_crossing_blocks_clock() or site_controller.region_operation_pending():
			_action_time_remainder += remaining
			return
		if (is_inside_tree() and get_tree().paused) or bool(terrain.site.get("paused", false)):
			return

func _advance_original_shared_step(elapsed: float, replay_target: float = -1.0,
		fire_replay_interval: Dictionary = {}, formula_interval: bool = false) -> Dictionary:
	if terrain == null or terrain.site.is_empty() or site_controller == null:
		return SiteRuntime.fail("NO_SITE", "原 Site 尚未還原")
	if not is_finite(elapsed) or elapsed <= 0.0 or not is_finite(simulation_speed) or simulation_speed <= 0.0:
		return SiteRuntime.fail("INVALID_TIME", "原共同步進時間非法")
	if elapsed > (EXCHANGE_ACTION_STEP if exchange_enabled else ACTION_STEP) + ACTION_TIME_EPSILON:
		return SiteRuntime.fail("INVALID_TIME", "呼叫者須提供一個原共同步進")
	var party_body := terrain.has_meta(&"region_party_owner")
	if party_body and not _region_owner_interval_active:
		return _region_advance_live_party_host(elapsed)
	var party_consuming := party_body and _region_owner_interval_active and not fire_replay_interval.is_empty()
	var replaying := replay_target >= 0.0
	var fault: Dictionary = site_controller.original_step_fault_guard()
	if not fault.ok: return fault
	if not replaying:
		if site_controller.ground_crossing_blocks_clock() or site_controller.region_operation_pending(): return SiteRuntime.fail("BUSY", "原跨界或船隊目的地補算等待中")
	if replaying != restore_only and not party_consuming:
		return SiteRuntime.fail("INVALID_MODE", "活動步進與還原補算模式不同")
	if bool(terrain.site.get("paused", false)):
		return SiteRuntime.fail("PAUSED_SITE", "原地點模擬暫停；保留補算欠秒")
	if is_inside_tree() and get_tree().paused:
		return SiteRuntime.fail("PAUSED_WORLD", "原世界暫停；保留補算欠秒")
	var fire_step_guard := _fire_step_guard()
	if not fire_step_guard.ok: return fire_step_guard
	if not _region_point_pending.is_empty():
		var prior_point := consume_region_point()
		if not prior_point.ok: return prior_point
		if not bool(prior_point.get("complete", false)): return {"ok": true, "completed": false, "status": "REGION_EVENT_PENDING", "action_seconds": 0.0, "game_seconds": 0.0}
	if not replaying and site_controller.region_slot != null and not site_controller.region_slot.pending_region_events().is_empty():
		var due: Dictionary = site_controller.region_slot.consume_due_region_events()
		if not due.ok: return due
		if not bool(due.get("complete", false)) and not bool(due.get("restricted_settlement", false)): return {"ok": true, "completed": false, "status": "REGION_EVENT_PENDING", "action_seconds": 0.0, "game_seconds": 0.0}
		if terrain == null or terrain != _region_bound_data or get_tree().paused or bool(terrain.site.get("paused", false)): return {"ok": true, "completed": false, "status": "REGION_EVENT_PENDING", "action_seconds": 0.0, "game_seconds": 0.0}
	var native_begin: Dictionary = {}
	var original_site := terrain
	var permit := {}
	var region_joint_interval: Dictionary = {}
	var region_gameplay_prepared: Dictionary = {}
	var region_originals: Array[TerrainLab] = []
	var gd_original: bool = crowd_site == null or not crowd_site.active
	var region_callers: bool = gd_original and not replaying and site_controller.region_slot != null and site_controller.region_slot.source != null and not site_controller.region_slot.pin.is_empty()
	# Ship owns the permission schema and publisher. A valid permit captures
	# eligibility BEFORE work/death can open the family pause UI.
	if not replaying and site_controller.region_slot != null and not region_callers:
		permit = site_controller.region_slot.begin_active_step(terrain.site)
		if not bool(permit.get("unpaused", false)): return permit
	var fire_active_at_start := _fire_activity()
	var indexed_fire_grace := false
	if not replaying and site_controller.region_slot != null:
		indexed_fire_grace = bool(site_controller.region_slot.control.get("fire_clock", {}).get("index", {}).get(str(terrain.site.id), {}).get("fire_active", false))

	# Native BEGIN first settles this existing zero-time interruption. The
	# collector then captures the original post-cancellation manual/source refs.
	# mark_combat retains its original cancellation semantics; no preserved fake
	# task is passed to a later cost/material or fatigue publisher.
	if not gd_original and not formula_interval and _siege_tactical_active():
		SiteRuntime.mark_combat(terrain, 10.0)
		if terrain != original_site or terrain.site.is_empty() or site_controller == null:
			return SiteRuntime.fail("STALE_SOURCE", "原器械 BEGIN 零端點後來源已替換")
	var pre_step_combat_left := float(terrain.site.get("combat_left", 0.0))
	if bool(permit.get("cold_fire_active", false)): pre_step_combat_left = maxf(pre_step_combat_left, elapsed)
	if _siege_tactical_active(): pre_step_combat_left = maxf(pre_step_combat_left, 10.0)
	if fire_active_at_start: pre_step_combat_left = maxf(pre_step_combat_left, SiteRuntime.COMBAT_GRACE)
	if region_callers:
		var joint := _prepare_region_main_interval(elapsed, pre_step_combat_left)
		if not joint.get("ok", false): return joint
		if joint.get("pending", false):
			var due: Dictionary = site_controller.region_slot.consume_due_region_events()
			if not due.ok: return due
			return {"ok": true, "completed": false, "status": "REGION_EVENT_PENDING", "action_seconds": 0.0, "game_seconds": 0.0}
		region_joint_interval = joint.interval
		region_gameplay_prepared = joint.prepared
		region_originals.assign(joint.originals)
		permit = joint.permit
		elapsed = float(region_joint_interval.action_end) - float(region_joint_interval.action_begin)
		pre_step_combat_left = float(region_joint_interval.tactical_seconds)
	if formula_interval:
		pre_step_combat_left = float(fire_replay_interval.get("tactical_seconds", 0.0))
	if not gd_original and not formula_interval:
		native_begin = _prepare_native_begin_shared_window(elapsed, pre_step_combat_left)
		if not native_begin.ok: return _region_preflight_failure(region_originals, native_begin)
		elapsed = float(native_begin.action_seconds)
		pre_step_combat_left = float(native_begin.combat_begin)
	# Classify/clip before the first body/work mutation. All consumers below
	# receive exactly the same accepted original action and game interval.
	# P0's original capture timer clips at its real completion before work/body.
	var capture_sample: Dictionary = site_controller.Settlement.capture_sample(self)
	var capture_game_window := SiteRuntime.game_seconds(elapsed, pre_step_combat_left) * simulation_speed
	var capture_limit: float = site_controller.Settlement.capture_interval_limit(terrain, capture_sample, capture_game_window)
	if capture_limit <= ACTION_TIME_EPSILON:
		_region_clear_shared_work_plans(region_originals)
		var settled_capture: Dictionary = site_controller.settle_settlement_endpoint()
		if not settled_capture.ok: return settled_capture
		return {"ok": true, "completed": false, "status": "REGION_EVENT_PENDING", "action_seconds": 0.0, "game_seconds": 0.0}
	if capture_limit < capture_game_window:
		if region_callers or formula_interval:
			return _region_preflight_failure(region_originals, SiteRuntime.fail("REGION_UNCLIPPED_CAPTURE"))
		elapsed = RegionSaveSlot.GameplayClock.action_for_game(capture_limit, simulation_speed, minf(elapsed, pre_step_combat_left))
	if gd_original and not region_callers and not formula_interval:
		var work_prefix: Dictionary = _prepare_shared_work_step(elapsed, SiteRuntime.game_seconds(elapsed, pre_step_combat_left) * simulation_speed, minf(elapsed, pre_step_combat_left))
		if not work_prefix.get("ok", false): return _region_preflight_failure(region_originals, work_prefix)
		elapsed = float(work_prefix.action_seconds)
	var completed_game_seconds := SiteRuntime.game_seconds(elapsed, pre_step_combat_left) * simulation_speed
	if not is_finite(completed_game_seconds) or completed_game_seconds <= 0.0:
		return _region_preflight_failure(region_originals, SiteRuntime.fail("INVALID_TIME", "原步進遊戲秒不可表示"))
	var fire_clock_step := {}
	var region_interval := {}
	if not replaying and site_controller.region_slot != null and site_controller.region_slot.source != null and not site_controller.region_slot.pin.is_empty():
		var coordinate: Dictionary = site_controller.region_slot._coordinate(terrain)
		if not coordinate.ok: return _region_preflight_failure(region_originals, coordinate)
		fire_clock_step = {"action_seconds": elapsed, "tactical_seconds": minf(elapsed, pre_step_combat_left),
			"scale": simulation_speed, "coordinate": [coordinate.site.x, coordinate.site.y], "fire_active": false}
		var fire_clock_interval: Dictionary = region_joint_interval if not region_joint_interval.is_empty() else RegionSaveSlot.preview_fire_interval(site_controller.region_slot.control.get("fire_clock", {}),
			float(site_controller.region_slot.control.logical_game_seconds), elapsed, simulation_speed,
			minf(elapsed, pre_step_combat_left))
		if not fire_clock_interval.ok: return _region_preflight_failure(region_originals, fire_clock_interval)
		region_interval = fire_clock_interval
		var expected_game_end := float(site_controller.region_slot.control.logical_game_seconds) + completed_game_seconds
		if absf(float(fire_clock_interval.game_end) - expected_game_end) > maxf(0.00000001, expected_game_end * 0.000000001):
			return _region_preflight_failure(region_originals, SiteRuntime.fail("CLOCK_CONTRACT", "原火攻與 shared-step 雙時鐘預檢不一致"))
	if replaying and not party_consuming:
		var window := RegionSaveSlot.validate_settlement(terrain.site, replay_target)
		if not window.ok: return _region_preflight_failure(region_originals, window)
		var pending_game_seconds := float(window.pending)
		var time_tolerance := maxf(0.00000001, pending_game_seconds * 0.000000001)
		if completed_game_seconds - pending_game_seconds > time_tolerance:
			return _region_preflight_failure(region_originals, SiteRuntime.fail("INVALID_TIME", "補算原步進超過固定目標"))
		completed_game_seconds = minf(completed_game_seconds, pending_game_seconds)
	if formula_interval:
		if not replaying or not _region_owner_interval_active or fire_replay_interval.is_empty(): return _region_preflight_failure(region_originals, SiteRuntime.fail("REGION_FORMULA_CONTRACT"))
		region_interval = fire_replay_interval.duplicate(true)
		if absf(completed_game_seconds - (float(region_interval.game_end) - float(region_interval.game_begin))) > 0.00000001: return _region_preflight_failure(region_originals, SiteRuntime.fail("REGION_FORMULA_CLOCK"))
	if not native_begin.is_empty() and (elapsed != float(native_begin.action_seconds) or completed_game_seconds != float(native_begin.game_seconds)):
		return _region_preflight_failure(region_originals, SiteRuntime.fail("NATIVE_BEGIN_WINDOW_CHANGED"))
	if gd_original and not formula_interval and _gd_mesh_work_needed():
		var mesh_work: Dictionary = _prepare_gd_mesh_work_point(completed_game_seconds)
		if not mesh_work.ok: return _region_preflight_failure(region_originals, mesh_work)
	# All remaining guards passed before the first original body mutation.
	if (gd_original or formula_interval) and _siege_tactical_active(): SiteRuntime.mark_combat(terrain, 10.0)
	if fire_active_at_start: SiteRuntime.mark_combat(terrain, SiteRuntime.COMBAT_GRACE, true)
	if bool(permit.get("cold_fire_active", false)): terrain.site.combat_left = maxf(float(terrain.site.get("combat_left", 0.0)), elapsed)
	if (not replaying or formula_interval) and not region_interval.is_empty() and gd_original:
		_region_point_pending = region_interval.duplicate(true)
		_region_point_pending.fire_action_begin = fire_action_cursor
		_region_point_pending.fire_action_end = fire_action_cursor + elapsed
		_region_point_pending.interval_complete = false
	var fire_boundary := _begin_fire_boundary(fire_action_cursor + elapsed)
	if not fire_boundary.ok:
		_region_point_pending.clear()
		_region_clear_shared_work_plans(region_originals)
		return _latch_fire_boundary_error(fire_boundary)
	if not native_begin.is_empty():
		var native_gate: Dictionary = validate_native_begin_shared_window(native_begin)
		if not native_gate.ok: return _region_preflight_failure(region_originals, native_gate)
		_region_point_pending = {"fire_action_begin": fire_action_cursor, "fire_action_end": fire_action_cursor + elapsed,
			"interval_complete": false, "native_checked": {}, "game_begin": SiteRuntime.now(terrain) * 60.0,
			"game_end": SiteRuntime.now(terrain) * 60.0 + completed_game_seconds}
		_publish_native_begin_shared_window(native_begin)
	var site_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	site_controller.prepare_settlement_interval()
	site_controller.tick(elapsed, completed_game_seconds)
	_combat_profile_stage("site_tick", site_started)
	# An unexpected pre-body interruption is an error, never a completed step.
	if terrain != original_site or bool(terrain.site.get("paused", false)) or get_tree().paused:
		var interrupted: Dictionary = SiteRuntime.fail("INTERRUPTED_STEP", "原工作階段後身體步進未完成")
		site_controller.latch_original_step_fault(interrupted)
		return interrupted
	var movement_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	if not replaying and not _shared_movement_prepared: _advance_movement_input()
	_combat_profile_stage("movement_input", movement_started)
	_advance_combat(elapsed, pre_step_combat_left)
	_fatigue_work_seconds.clear()
	fault = site_controller.original_step_fault_guard()
	if not fault.ok: return site_controller.latch_original_step_fault(fault)
	if region_callers:
		var advanced: Dictionary = site_controller.region_slot.advance_prepared_region_formula_progress(region_gameplay_prepared)
		if not advanced.get("ok", false): return site_controller.latch_original_step_fault(advanced)
	# _advance_combat already settled fatigue, food, contacts, remains, orders
	# and family. Its AFTER-step family pause cannot erase elapsed game time.
	var recorded: Dictionary
	if party_consuming:
		recorded = SiteRuntime.ok("", {"complete": true})
	elif replaying:
		recorded = RegionSaveSlot.record_completed_replay_step(terrain.site, replay_target, completed_game_seconds)
		if recorded.ok and not fire_replay_interval.is_empty():
			RegionSaveSlot.record_completed_fire_replay(terrain.site, fire_replay_interval)
		if _fire_replay_tracking:
			_fire_replay_keep_tactical = _fire_activity() or (_fire_replay_keep_tactical or fire_active_at_start) \
				and float(terrain.site.get("combat_left", 0.0)) > 0.0
	else:
		if not fire_clock_step.is_empty():
			fire_clock_step.fire_active = _fire_activity() or (indexed_fire_grace or fire_active_at_start) \
				and float(terrain.site.get("combat_left", 0.0)) > 0.0
		recorded = site_controller.record_completed_region_step(elapsed, completed_game_seconds, permit, fire_clock_step)
	if recorded.get("ok", false) and region_callers:
		var accepted: Dictionary = site_controller.region_slot.commit_region_gameplay_progress(region_gameplay_prepared)
		if not accepted.get("ok", false): recorded = site_controller.latch_original_step_fault(accepted)
	if not bool(recorded.get("ok", false)): site_controller.latch_original_step_fault(recorded)
	if bool(recorded.get("ok", false)) and not _region_point_pending.is_empty():
		_region_point_pending.interval_complete = true
		if not formula_interval:
			var consumed_point := consume_region_point()
			if not consumed_point.ok: site_controller.latch_original_step_fault(consumed_point)
			if not consumed_point.ok: recorded = consumed_point
			elif not bool(consumed_point.get("complete", false)): recorded.status = "REGION_EVENT_PENDING"
	if recorded.get("ok", false) and _region_point_pending.is_empty(): _clear_shared_work_step()
	recorded.completed = true
	recorded.action_seconds = elapsed
	recorded.game_seconds = completed_game_seconds
	return recorded


# New flag belongs to ORIGINAL TerrainLab. The existing _region_formula_active
# controls only melee suppression, not permission to run a deferred owner interval.

func _next_fire_replay_interval() -> Dictionary:
	while _fire_replay_segment_index < _fire_replay_segments.size():
		var row: Dictionary = _fire_replay_segments[_fire_replay_segment_index]
		var offset := _fire_replay_segment_offset
		if offset >= int(row.steps):
			_fire_replay_segment_index += 1
			_fire_replay_segment_offset = 0
			continue
		var steps := int(row.steps)
		var action_per_step := (float(row.action_end) - float(row.action_begin)) / steps
		var game_per_step := (float(row.game_end) - float(row.game_begin)) / steps
		var tactical_per_step := float(row.tactical_seconds) / steps
		var action_begin := float(row.action_begin) + action_per_step * offset
		var action_end := float(row.action_end) if offset + 1 == steps else float(row.action_begin) + action_per_step * (offset + 1)
		var game_begin := float(row.game_begin) + game_per_step * offset
		var game_end := float(row.game_end) if offset + 1 == steps else float(row.game_begin) + game_per_step * (offset + 1)
		return {"epoch": _fire_replay_epoch, "sequence": int(row.first_sequence) + offset,
			"action_begin": action_begin, "action_end": action_end, "game_begin": game_begin, "game_end": game_end,
			"scale": float(row.scale), "tactical_seconds": tactical_per_step,
			"segment_index": _fire_replay_segment_index, "segment_offset": offset}
	return {}

func replay_site_to(target_game_seconds: float, budget_usec: int = 0, max_steps: int = 0) -> Dictionary:
	if not restore_only or terrain == null or not is_inside_tree():
		return SiteRuntime.fail("INVALID_MODE", "補算只接受已還原的原 TerrainLab")
	# A latched original step fault outranks the point it left pending.
	if site_controller != null:
		var step_fault: Dictionary = site_controller.original_step_fault_guard()
		if not step_fault.ok: return step_fault
	if not _region_point_pending.is_empty() or _region_point_consuming: return SiteRuntime.fail("REGION_EFFECTS_PENDING")
	var fire_guard := SiteRuntime.ok() if terrain.site.has("region_snapshot") else SiteStore.fire_event_guard(terrain)
	if not fire_guard.ok: return fire_guard
	if not is_finite(target_game_seconds) or target_game_seconds < 0.0 or budget_usec < 0 or max_steps < 0:
		return SiteRuntime.fail("INVALID_TIME", "補算固定目標或預算非法")
	if not is_finite(simulation_speed) or simulation_speed <= 0.0:
		return SiteRuntime.fail("INVALID_TIME", "補算原模擬速度非法")
	if _replay_target >= 0.0 and target_game_seconds != _replay_target:
		return SiteRuntime.fail("BUSY", "原補算目標仍固定；先完成既有欠秒")
	var window := RegionSaveSlot.replay_window(terrain.site, target_game_seconds)
	if not window.ok: return window
	_replay_target = target_game_seconds
	var deadline := Time.get_ticks_usec() + budget_usec if budget_usec > 0 else 0
	var completed_steps := 0
	var pending := _replay_pending_residue(float(window.pending))
	while pending > 0.0:
		var fire_interval := _next_fire_replay_interval() if _fire_replay_tracking else {}
		if _fire_replay_tracking and fire_interval.is_empty():
			return SiteRuntime.fail("MISSING_FIRE_HISTORY", "Site 尚有共同時間欠秒，但原火攻 journal 已耗盡")
		# Recreate the world-wide tactical permit recorded by this original interval.
		if _fire_replay_tracking:
			terrain.site.combat_left = maxf(float(terrain.site.get("combat_left", 0.0)), float(fire_interval.tactical_seconds))
		var combat_left := float(terrain.site.get("combat_left", 0.0))
		if _siege_active(): combat_left = maxf(combat_left, 10.0)
		if _fire_activity(): combat_left = maxf(combat_left, SiteRuntime.COMBAT_GRACE)
		var action_step: float
		if _fire_replay_tracking:
			action_step = float(fire_interval.action_end) - float(fire_interval.action_begin)
			simulation_speed = float(fire_interval.scale)
			var journal_game_seconds := (float(fire_interval.tactical_seconds)
				+ (action_step - float(fire_interval.tactical_seconds)) * 60.0) * simulation_speed
			var site_game_seconds := SiteRuntime.game_seconds(action_step, combat_left) * simulation_speed
			var tolerance := maxf(0.00000001, journal_game_seconds * 0.000000001)
			if absf(journal_game_seconds - (float(fire_interval.game_end) - float(fire_interval.game_begin))) > tolerance \
					or absf(site_game_seconds - journal_game_seconds) > tolerance \
					or absf(fire_action_cursor - float(fire_interval.action_begin)) > 0.00000001:
				return SiteRuntime.fail("CLOCK_CONTRACT", "冷火場的原 combat_left／action／倍率與已發布 journal 不一致")
			if site_game_seconds > pending + tolerance:
				return SiteRuntime.fail("CLOCK_CONTRACT", "已發布火攻區間超過固定冷地點目標")
		else:
			# Invert the SAME existing action->game conversion, then pass action
			# seconds to original Runtime.advance. Never feed it game seconds.
			var unscaled := pending / simulation_speed
			var until_target := unscaled if unscaled <= combat_left else combat_left + (unscaled - combat_left) / 60.0
			action_step = minf(EXCHANGE_ACTION_STEP if exchange_enabled else ACTION_STEP, until_target)
			while SiteRuntime.game_seconds(action_step, combat_left) * simulation_speed > pending:
				action_step *= 1.0 - ACTION_TIME_EPSILON
		if action_step <= 0.0 or not is_finite(action_step):
			return SiteRuntime.fail("INVALID_TIME", "原補算時間不可表示")
		var result := _advance_original_shared_step(action_step, _replay_target, fire_interval)
		if not bool(result.get("ok", false)): return result
		if not result.has("pending"):
			return SiteRuntime.fail("CLOCK_CONTRACT", "補算步進未完成且無欠秒：" + str(result.get("status", "")))
		if _fire_replay_tracking: _fire_replay_segment_offset += 1
		completed_steps += 1
		pending = _replay_pending_residue(float(result.pending))
		if pending > 0.0 and ((max_steps > 0 and completed_steps >= max_steps) or (deadline > 0 and Time.get_ticks_usec() >= deadline)):
			return SiteRuntime.ok("原地點仍有補算欠秒", {"status": "PENDING", "target": _replay_target,
				"pending": pending, "steps": completed_steps, "data": terrain})
	if _fire_replay_tracking:
		var final_interval := _next_fire_replay_interval()
		var final_settlement: Dictionary = terrain.site.get("fire_settlement", {})
		if not final_interval.is_empty() or int(final_settlement.get("sequence", -1)) != _fire_replay_end_sequence \
				or absf(float(final_settlement.get("action_seconds", -1.0)) - _fire_replay_end_action) > 0.00000001 \
			or absf(float(final_settlement.get("game_seconds", -1.0)) - _fire_replay_end_game) > 0.00000001:
			return SiteRuntime.fail("CLOCK_CONTRACT", "冷火場未消費完整固定 journal 端點")
	var parent: TerrainLab = get_parent() as TerrainLab
	if parent != null and parent.site_controller != null and parent.site_controller.region_slot != null or terrain.site.has("region_snapshot"):
		var region_completed := _region_finish_cold_replay(target_game_seconds)
		if not region_completed.ok: return region_completed
		_replay_target = -1.0
		return SiteRuntime.ok("原地點補算完成", {"status": "COMPLETE", "target": target_game_seconds, "pending": 0.0, "steps": completed_steps, "data": region_completed.data})
	var transport_capture := capture_fire_transport()
	if not transport_capture.ok: return transport_capture
	if transport_capture.state.is_empty(): terrain.site.erase("fire_transport")
	else: terrain.site.fire_transport = transport_capture.state
	var owner_capture := capture_fire_owner_state()
	if not owner_capture.ok: return owner_capture
	if owner_capture.state.is_empty(): terrain.site.erase("fire_owners")
	else: terrain.site.fire_owners = owner_capture.state
	# Persistable state is captured by the original owners, never a projection.
	var guard: Dictionary = site_controller.supply_save_guard(false, _fire_replay_tracking)
	if not guard.ok: return guard
	var captured: Dictionary = site_controller._capture_for_save()
	if not captured.ok: return captured
	var validation := SiteStore._validate_state(terrain, terrain.site)
	if not validation.ok: return validation
	_replay_target = -1.0
	return SiteRuntime.ok("原地點補算完成", {"status": "COMPLETE", "target": target_game_seconds,
		"pending": 0.0, "steps": completed_steps, "data": terrain})

func _replay_pending_residue(pending: float) -> float:
	# Clipped fixed steps can leave a float residue below one ACTION_TIME_EPSILON
	# of action time; it cannot be stepped, so it counts as complete.
	var tolerance: float = SiteRuntime.game_seconds(ACTION_TIME_EPSILON, float(terrain.site.get("combat_left", 0.0))) * simulation_speed
	return 0.0 if pending <= tolerance else pending

func _advance_combat(delta: float, combat_clock: float = -1.0) -> void:
	# Shared action-time steps, independent of peaceful game-minute acceleration.
	# All actors generate a sample before contact resolution, allowing real trades.
	if delta <= 0.0 or (is_inside_tree() and get_tree().paused):
		return
	if terrain != null and bool(terrain.site.get("paused", false)):
		return
	var fire_step_guard := _fire_step_guard()
	if not fire_step_guard.ok:
		_latch_fire_boundary_error(fire_step_guard)
		return
	var supplied_shared_clock := combat_clock >= 0.0
	if combat_clock < 0.0:
		combat_clock = float(terrain.site.get("combat_left", 0.0)) if terrain != null else 0.0
	var remaining := delta
	while remaining > ACTION_TIME_EPSILON:
		var elapsed := minf(remaining, EXCHANGE_ACTION_STEP if exchange_enabled else ACTION_STEP)
		remaining -= elapsed
		var fire_action_begin := fire_action_cursor
		var completed_fire_end := fire_action_begin + elapsed
		var fire_boundary := _begin_fire_boundary(completed_fire_end)
		if not fire_boundary.ok:
			_latch_fire_boundary_error(fire_boundary)
			return
		if _fire_activity():
			SiteRuntime.mark_combat(terrain, SiteRuntime.COMBAT_GRACE, true)
			if not supplied_shared_clock: combat_clock = maxf(combat_clock, SiteRuntime.COMBAT_GRACE)
		if not supplied_shared_clock and _siege_active():
			SiteRuntime.mark_combat(terrain, 10.0)
			combat_clock = maxf(combat_clock, 10.0)
		var game_seconds := SiteRuntime.game_seconds(elapsed, combat_clock) * simulation_speed
		var stage_started := Time.get_ticks_usec() if combat_profile_enabled else 0
		combat_clock = maxf(0.0, combat_clock - elapsed)
		var crowd_host_started := 0
		var crowd_step_us := 0
		var crowd_events_us := 0
		if site_controller != null:
			site_controller.person_actions.advance_fire_jobs(fire_action_begin, completed_fire_end, game_seconds)
			site_controller.person_actions.advance_housing_jobs(elapsed)
			site_controller.person_actions.advance_structure_attacks(elapsed)
		if crowd_site != null and crowd_site.active:
			crowd_host_started = Time.get_ticks_usec()
			if not bool(_native_begin_shared_window_prepared.get("published", false)):
				site_controller.latch_original_step_fault(SiteRuntime.fail("CLOCK_NOT_READY", "原Native共同區間未接受；不走legacy charge"))
				return
			_capture_fire_motion()
			var crowd_step_started := Time.get_ticks_usec()
			var prior_step_error: Dictionary = crowd_site.last_event_error
			if not crowd_site.step(elapsed, game_seconds, combat_clock):
				var rejected: Dictionary = crowd_site.last_event_error.duplicate(true)
				if rejected.is_empty() or bool(rejected.get("ok", true)) or is_same(crowd_site.last_event_error, prior_step_error):
					rejected = SiteRuntime.fail("ORIGINAL_CROWD_STEP_FAILED", "原生身體步進拒絕；原共同步進僅部分執行")
					rejected["prior_owner_error"] = crowd_site.last_event_error.duplicate(true)
				site_controller.latch_original_step_fault(rejected)
				return
			crowd_step_us = Time.get_ticks_usec() - crowd_step_started
			crowd_events_us = int(crowd_site.event_cost_last_us)
			for actor: TerrainTestCharacter in combat_actors:
				if not is_instance_valid(actor) or crowd_site.contains_person(actor.person_id): continue
				if actor is TerrainTestNPC and actor.combat_driven_by_lab and actor.person_id != controlled_person_id(): actor.advance_navigation()
				actor.advance_combat(elapsed, true, game_seconds)
			siege_begin_contact_batch()
			_advance_siege(elapsed)
			if crowd_site.fire_host_active(): _advance_ranged(elapsed)
		else:
			if site_controller != null: site_controller.vehicles.update_siege(elapsed)
			if site_controller != null:
				var ladder_work: Dictionary = site_controller.work_team.advance_ladder_actions(elapsed, game_seconds, _shared_work_plan)
				for identity: int in ladder_work:
					site_controller._crew_handled[identity] = float(site_controller._crew_handled.get(identity, 0.0)) + float(ladder_work[identity])
			# Commit only at the start of this original action slice; include newborn arrows in its motion snapshot.
			_commit_fire_releases()
			_capture_fire_motion()
			_combat_contacts.clear()
			if not exchange_enabled:
				TerrainArmy.begin_contact_step()
			for actor: TerrainTestCharacter in combat_actors:
				if not _shared_movement_prepared and actor is TerrainTestNPC and actor.combat_driven_by_lab and actor.person_id != controlled_person_id():
					(actor as TerrainTestNPC).advance_navigation()
			# Both held player input and autonomous NPC intent have now committed.
			# Charge the same game-time slice before physically advancing either body.
			if _gd_mesh_work_point.is_empty(): _advance_fatigue(game_seconds)
			else: _advance_fatigue(game_seconds, true) # Original uncovered recovery once; covered effort awaits genuine contacts.
			if site_controller != null:
				site_controller.vehicles.update_ships(elapsed)
				site_controller.person_actions.advance_ship_jobs(elapsed)
			_advance_tactical_ai(elapsed)
			_advance_duty_ai(game_seconds)
			var movement_started := Time.get_ticks_usec() if combat_profile_enabled else 0
			if combat_movement_coordinator != null:
				combat_movement_coordinator.combat_logic_tick_if_needed(elapsed, _combat_actor_blocked_cells())
			_combat_profile_stage("movement_coordinator", movement_started)
			var prepare_started := Time.get_ticks_usec() if combat_profile_enabled else 0
			_enemy_query_owner_cell_window = enemy_query_owner_cells_enabled and _enemy_query_owner_cells_admitted()
			for team: TerrainArmy in combat_armies:
				team.prepare_combat(elapsed, game_seconds)
			_enemy_query_owner_cell_window = false
			_combat_profile_stage("army_prepare", prepare_started)
			stage_started = _combat_profile_stage("navigation_and_team_prepare", stage_started)
			for actor: TerrainTestCharacter in combat_actors:
				if is_instance_valid(actor):
					actor.advance_combat(elapsed, true, game_seconds)
			if combat_movement_coordinator != null:
				combat_movement_coordinator.complete_committed_moves()
			stage_started = _combat_profile_stage("actors_advance", stage_started)
			siege_begin_contact_batch()
			_advance_siege(elapsed)
			# All live actors have advanced. Their poses stay fixed until this batch
			# is collected; discard projections before contacts can change a pose.
			if exchange_enabled:
				_advance_ranged(elapsed) # Existing owners keep flights; only due events query cells.
				_exchange_phase += elapsed
				if _exchange_phase + ACTION_TIME_EPSILON >= EXCHANGE_QUERY_STEP:
					_exchange_phase -= EXCHANGE_QUERY_STEP
					if not _region_formula_active: _resolve_exchanges()
			elif not _region_formula_active:
				_army_contact_geometry.clear()
				_sampling_army_contacts = true
				_begin_army_contact_inputs()
				for actor: TerrainTestCharacter in combat_actors:
					if is_instance_valid(actor):
						actor.sample_combat()
				stage_started = _combat_profile_stage("actors_sample", stage_started)
				for team: TerrainArmy in combat_armies:
					team.sample_combat()
				stage_started = _combat_profile_stage("teams_sample", stage_started)
				_end_army_contact_inputs()
				_sampling_army_contacts = false
				_army_contact_geometry.clear()
				_resolve_combat_contacts()
				if not _gd_mesh_work_point.is_empty(): _finish_gd_mesh_work_point()
			stage_started = _combat_profile_stage("resolve", stage_started)
		if (crowd_site == null or not crowd_site.active or crowd_site.fire_host_active()) \
			and not _settle_fire_exposure(fire_action_begin, completed_fire_end): return
		if crowd_site != null and crowd_site.active:
			if not _finish_native_checked_body_prefixes(fire_action_begin, completed_fire_end, game_seconds): return
		if site_controller != null and not _region_deferring_endpoint():
			for result: Dictionary in site_controller.person_actions.settle_after_contacts():
				site_controller.collect_ground_boundary_result(result)
				site_controller.show_result(result)
		if not _finish_fire_boundary(fire_action_begin, completed_fire_end): return
		siege_flush_contact_batch()
		if site_controller != null:
			if crowd_site != null and crowd_site.active: crowd_site.settle_external_contacts()
			if _region_deferring_endpoint(): site_controller.advance_person_death_timers(elapsed)
			else: site_controller.settle_person_deaths(elapsed)
			if not _region_deferring_endpoint(): site_controller.settle_supply_deliveries()
			var capture_done: Dictionary = SiteRuntime.ok() if _region_deferring_endpoint() else site_controller.settle_settlement_endpoint()
			if not capture_done.ok: site_controller.latch_original_step_fault(capture_done)
			SiteRuntime.advance_gate_operations(terrain, elapsed, site_controller._building_person_query, site_controller.reserves_cell)
		if not _region_deferring_endpoint():
			for team: TerrainArmy in combat_armies: team.settle_combat_command()
			if site_controller != null: site_controller.check_family_death()
		if crowd_host_started > 0:
			crowd_host_cost_last_us = maxi(0, Time.get_ticks_usec() - crowd_host_started - crowd_step_us + crowd_events_us)
			crowd_host_cost_count += 1
			crowd_host_cost_total_us += crowd_host_cost_last_us
			crowd_host_cost_max_us = maxi(crowd_host_cost_max_us, crowd_host_cost_last_us)
		if site_controller != null and is_inside_tree() and get_tree().paused:
			return
		_combat_profile_stage("settle_life_orders_family", stage_started)
	_combat_contacts.clear()

## Non-combat duties run on the game-minute clock (NPC plan 8.3); tactical
## command keeps its own 0.5 action-second review above.
func _advance_duty_ai(game_seconds: float) -> void:
	var duty_scope := _region_duty_enter()
	_region_advance_original_duty_ai(game_seconds)
	_region_duty_leave(duty_scope)

func _region_advance_original_duty_ai(game_seconds: float) -> void:
	if game_seconds <= 0.0 or terrain == null or site_controller == null or bool(terrain.site.get("paused", false)) 		or (is_inside_tree() and get_tree().paused):
		return
	site_controller.captive_escort.start_arrived_releases() # Supply for this step is settled by now.
	_duty_ai_elapsed += game_seconds
	if _duty_ai_elapsed + ACTION_TIME_EPSILON < DutyAI.REVIEW_GAME_SECONDS:
		DutyAI.capture_cadence(self, _duty_ai_elapsed)
		return
	_duty_ai_elapsed = fmod(_duty_ai_elapsed, DutyAI.REVIEW_GAME_SECONDS)
	DutyAI.capture_cadence(self, _duty_ai_elapsed)
	DutyAI.review(self)

func _advance_tactical_ai(delta: float) -> void:
	if delta <= 0.0 or terrain == null or bool(terrain.site.get("paused", false)) \
		or (is_inside_tree() and get_tree().paused):
		return
	var enabled := false
	for team: TerrainArmy in combat_armies:
		if team.combat_enabled and team.tactical_ai_enabled:
			enabled = true
			break
	if crowd_site != null and crowd_site.active:
		for owner_ref: CrowdPersonOwner in crowd_site.person_owners():
			if bool(crowd_site.formation_state(owner_ref.formation_index).get("ai_enabled", false)):
				enabled = true
				break
	if not enabled:
		_tactical_ai_elapsed = 0.0
		return
	_tactical_ai_elapsed += delta
	if _tactical_ai_elapsed + ACTION_TIME_EPSILON >= TacticalAI.REVIEW_SECONDS:
		var elapsed := _tactical_ai_elapsed
		_tactical_ai_elapsed = 0.0
		var started := Time.get_ticks_usec() if combat_profile_enabled else 0
		TacticalAI.review(self, elapsed)
		_combat_profile_stage("tactical_ai", started)

func _combat_actor_blocked_cells() -> Dictionary:
	var blocked := {}
	for actor: TerrainTestCharacter in combat_actors:
		if not is_instance_valid(actor):
			continue
		if actor.occupies_cell(actor.terrain_cell):
			blocked[actor.terrain_cell] = true
		if actor.is_moving() and actor.occupies_cell(actor.movement_from_cell):
			blocked[actor.movement_from_cell] = true
	return blocked

func fatigue_work_minutes(manual: bool, minutes: float) -> float:
	if not _shared_work_plan.is_empty():
		var key := "manual" if manual else "worker"
		if _shared_runtime_consumed.has(key): return 0.0
		_shared_runtime_consumed[key] = true
		var allocation: Dictionary = _shared_work_plan.jobs.get("runtime", {}).get(key, {})
		if allocation.is_empty(): return 0.0
		var original: TerrainTestCharacter = character if manual else npc
		var actual := float(allocation.get("participant_seconds", {}).get(original.person_id, 0.0))
		_fatigue_work_seconds[original] = float(_fatigue_work_seconds.get(original, 0.0)) + actual
		if original.person_id != controlled_person_id(): original.work_resting = str(allocation.get("paused", "")) == "REST"
		return float(allocation.get("effective_seconds", 0.0)) / 60.0
	var actor: TerrainTestCharacter = character if manual else npc
	if not actor_present(actor): return 0.0
	var autonomous := actor.person_id != controlled_person_id()
	var seconds := minutes * 60.0
	var work_rate := PersonFatigue.effort_rate(actor)
	if autonomous:
		actor.work_resting = PersonFatigue.needs_work_rest(actor.fatigue, actor.work_resting)
		if actor.work_resting:
			return 0.0
		# Commit only the effort before 80; unfinished progress/cargo stays put.
		seconds = minf(seconds, maxf(0.0, PersonFatigue.WORK_REST_AT - actor.fatigue) / work_rate)
	var productive := PersonFatigue.work_seconds(actor.fatigue, seconds, work_rate)
	var state := PersonFatigue.advance(actor.fatigue, actor.fatigue_rest, seconds, work_rate, false)
	actor.fatigue = state[0]
	actor.fatigue_rest = state[1]
	if autonomous and actor.fatigue >= PersonFatigue.WORK_REST_AT - 0.000000001:
		actor.fatigue = PersonFatigue.WORK_REST_AT
		actor.work_resting = true
	_fatigue_work_seconds[actor] = float(_fatigue_work_seconds.get(actor, 0.0)) + seconds
	return productive / 60.0

func resolve_structure_change(result: Dictionary) -> void:
	if not bool(result.get("ok", false)): return
	var lost: Dictionary = result.get("lost_surfaces", {})
	var surface_changed: bool = not lost.is_empty() or not result.get("lost_cells", {}).is_empty()
	if crowd_site != null and crowd_site.active:
		if not crowd_site.sync_terrain(): push_error("STRUCTURE_NATIVE_TERRAIN_REJECTED")
	# Keep the existing command and deployment owners, then cancel only edges
	# invalidated by the new surface. The original source remains authoritative.
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue # Crowd retains the cold source in this list.
		if surface_changed and team.combat_order != TerrainArmy.CombatOrder.HOLD:
			team._preserve_structure_order = true
	if combat_movement_coordinator != null:
		combat_movement_coordinator.complete_committed_moves()
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		team.cancel_invalid_structure_steps(lost)
	for actor: TerrainTestCharacter in combat_actors:
		if crowd_site != null and crowd_site.active and crowd_site.contains_person(actor.person_id): continue
		actor.cancel_invalid_structure_step(lost)
	var falling: Array[Dictionary] = []
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		for index in range(team.cells.size()):
			if _ship_embarked(team.combat_identity(index)): continue
			var cell: Vector2i = _army_effective_cell(team, index)
			var drop := int(lost.get(terrain.index(cell), terrain.effective_height(cell))) - terrain.effective_height(cell)
			if drop > 0: falling.append({"id": team.combat_identity(index), "owner": team, "unit": index, "drop": drop})
	for actor: TerrainTestCharacter in combat_actors:
		if crowd_site != null and crowd_site.active and crowd_site.contains_person(actor.person_id): continue
		var cell := actor.movement_from_cell if actor.is_moving() else actor.terrain_cell
		var drop := int(lost.get(terrain.index(cell), terrain.effective_height(cell))) - terrain.effective_height(cell)
		if drop > 0: falling.append({"id": actor.person_id, "owner": actor, "unit": -1, "drop": drop})
	falling.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	for person: Dictionary in falling:
		var packet := {"environmental": true, "shield": false, "result": {"hp": 15.0 * int(person.drop), "stun": 100.0, "guard_break": false}}
		if int(person.unit) >= 0: person.owner.apply_unit_contact(int(person.unit), packet)
		else: person.owner.apply_contact(packet)
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		team.notify_terrain_changed()
		if team._preserve_structure_order and team._combat_move_plan != null:
			team._refresh_move_terrain_revision()
	if combat_movement_coordinator != null:
		combat_movement_coordinator.request_occupancy_rebuild()
	queue_redraw()

func _advance_fatigue(seconds: float, accepted_prefix_only: bool = false) -> void:
	if terrain == null or seconds <= 0.0:
		return
	var fatigue_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	for team: TerrainArmy in combat_armies:
		if crowd_site != null and crowd_site.active and _native_original_army(team): continue
		if team.combat_enabled: team.sync_shared_fatigue()
	var training_seconds := {}
	if site_controller != null:
		if not accepted_prefix_only: training_seconds = site_controller.consume_crew_work()
		site_controller.advance_person_supply(seconds)
		if crowd_site != null and crowd_site.active and not accepted_prefix_only: site_controller.advance_crowd_sustain(seconds)
		for team: TerrainArmy in combat_armies:
			if crowd_site != null and crowd_site.active and _native_original_army(team): continue
			if team.combat_enabled:
				var handled: Dictionary = site_controller.advance_team_sustain(team, seconds).handled_seconds
				for identity: int in handled:
					training_seconds[identity] = float(training_seconds.get(identity, 0.0)) + float(handled[identity])
		var action_seconds: Dictionary = {}
		if not accepted_prefix_only:
			action_seconds = site_controller.person_actions.advance(seconds, {"jobs": _shared_work_plan.get("jobs", {}).get("person_actions", {})} if not _shared_work_plan.is_empty() else {}).handled_seconds
		# Escort and release walks advance once per accepted interval in both branches
		# (GD mesh prefix and native checked prefix). Work/fatigue prefixes stay single-consumption.
		site_controller.captive_escort.advance(seconds)
		if not accepted_prefix_only:
			for identity: int in action_seconds:
				training_seconds[identity] = float(training_seconds.get(identity, 0.0)) + float(action_seconds[identity])
			var guard_seconds: Dictionary = site_controller.advance_guard_work(seconds)
			for identity: int in guard_seconds:
				training_seconds[identity] = float(training_seconds.get(identity, 0.0)) + float(guard_seconds[identity])

	if _gd_mesh_work_point.is_empty(): _commit_shared_work_pools()
	fatigue_started = _combat_profile_stage("fatigue_providers", fatigue_started)
	# Only this synchronous step shares the read-only threat candidates.
	var enemies := {}
	for actor: TerrainTestCharacter in combat_actors:
		if crowd_site != null and crowd_site.active and crowd_site.contains_person(actor.person_id): continue
		if not is_instance_valid(actor) or not actor._fatigue_pool.is_empty():
			continue
		var worked := minf(seconds, float(_fatigue_work_seconds.get(actor, 0.0)))
		_fatigue_work_seconds[actor] = maxf(0.0, float(_fatigue_work_seconds.get(actor, 0.0)) - worked)
		var available := maxf(0.0, seconds - worked - float(training_seconds.get(actor.person_id, 0.0)))
		if available <= 0.0:
			continue
		if _shared_pool_has_effort(actor): continue
		var moving := actor.is_moving()
		var can_act := actor.can_act()
		var rate := 0.0
		if can_act:
			if not exchange_enabled and actor.action_time > 0.0 and actor._strike_at >= 0.0:
				rate = PersonFatigue.ATTACK_RATE
			elif not exchange_enabled and (actor.guarding or actor.guard_transition_left > 0.0):
				rate = PersonFatigue.GUARD_RATE
			elif actor.riding_fatigue_rate() > 0.0:
				rate = actor.riding_fatigue_rate()
			elif moving and actor.combat_ready and actor._movement_duration <= TerrainTestCharacter.RUN_DURATION + 0.000001:
				rate = PersonFatigue.RUN_RATE
		var captive_rest: bool = site_controller != null and site_controller.person_actions.captive_work_rest_allowed(actor.person_id)
		var idle := (can_act or captive_rest) and not moving and actor.action_time <= 0.0 and not actor.guarding and actor.guard_transition_left <= 0.0 and actor.guard_break_left <= 0.0 and actor._rescue_left <= 0.0
		if actor == npc and (bool(terrain.site.get("worker_enabled", false)) or bool(terrain.site.worker.get("manual_control", false))) and not actor.work_resting and not str(terrain.site.get("worker", {}).get("target", "")).is_empty():
			idle = false # Assigned travel/work/input waits do not double as a rest break.
		var safe := idle and actor.fatigue <= 0.0 and float(terrain.site.get("combat_left", 0.0)) <= 0.0
		if idle and (actor.fatigue > 0.0 or safe):
			var threat_started := Time.get_ticks_usec() if combat_profile_enabled else 0
			safe = captive_rest or not _fatigue_threat(actor.terrain_cell, actor.faction_id, actor, -1, enemies)
			_combat_profile_stage("fatigue_threat", threat_started)
		var housing_multiplier: float = Site.Housing.recovery_multiplier(self, [actor]) if safe else 1.0
		var state := PersonFatigue.advance(actor.fatigue, actor.fatigue_rest, available, rate, safe, housing_multiplier)
		actor.fatigue = state[0]
		actor.fatigue_rest = state[1]
	for team: TerrainArmy in combat_armies:
		if crowd_site != null and crowd_site.active and _native_original_army(team): continue
		if not team.combat_enabled:
			continue
		if not team.team_fatigue.is_empty(): _advance_team_fatigue(team, seconds, training_seconds, enemies)
		var shared := not team.team_fatigue.is_empty()
		var indices: Array = team.individual_fatigue_indices if shared else range(team.combat_units.size())
		var kernel := TerrainArmy._get_idle_kernel() if not shared and team.native_idle_enabled and not (site_controller != null and site_controller.vehicles.team_has_embarked(team.team_id)) and fatigue_zero_fast_path_enabled and exchange_enabled else null
		var end := indices.size()
		var next := 0
		while next < end:
			var index := int(indices[next])
			# Work/supply has already settled above. Only a no-work, stationary
			# zero prefix can bypass per-person formula/queries, in original order.
			if kernel != null and fatigue_zero_fast_path_enabled and exchange_enabled and training_seconds.is_empty():
				next = int(kernel.fatigue_prefix(team.combat_units, team.moving_to, index, end))
				team.native_fatigue_rows += next - index
				if combat_profile_enabled:
					fatigue_zero_eligible_rows += next - index
					fatigue_zero_skipped_advances += next - index
				if next >= end: break
				index = next
			next += 1
			var unit: Dictionary = team.combat_units[index]
			if _shared_pool_has_effort(unit): continue
			var available := seconds if training_seconds.is_empty() else maxf(0.0, seconds - float(training_seconds.get(team.combat_identity(index), 0.0)))
			if available <= 0.0:
				continue
			var moving := team.moving_to[index] != TerrainArmy.INVALID_CELL
			var crew_work := _ship_crew_work(team.combat_identity(index))
			# In exchange mode only running accrues continuous effort. An exact
			# zero walking/stationary row needs no eligibility/rest/formula query.
			if fatigue_zero_fast_path_enabled and exchange_enabled and not crew_work and float(unit.fatigue) == 0.0 and (not moving or team.move_duration[index] > TerrainArmy.RUN_DURATION + 0.000001):
				unit.fatigue = float(unit.fatigue)
				unit.fatigue_rest = 0.0
				if combat_profile_enabled:
					fatigue_zero_eligible_rows += 1
					fatigue_zero_skipped_advances += 1
				continue
			var can_act := team.combat_can_act(index)
			var rate := 0.0
			if can_act:
				if crew_work:
					rate = PersonFatigue.WORK_RATE
				elif not exchange_enabled and bool(team.combat_hot_get(index, &"attack")):
					rate = PersonFatigue.ATTACK_RATE
				elif not exchange_enabled and str(team.combat_hot_get(index, &"pose")) in ["guard", "guard_raise", "guard_lower"]:
					rate = PersonFatigue.GUARD_RATE
				elif moving and team.move_duration[index] <= TerrainArmy.RUN_DURATION + 0.000001:
					rate = PersonFatigue.RUN_RATE
			if (fatigue_zero_fast_path_enabled or combat_profile_enabled) and rate == 0.0 and float(unit.fatigue) == 0.0:
				if combat_profile_enabled:
					fatigue_zero_eligible_rows += 1
				if fatigue_zero_fast_path_enabled:
					# Original safe=false path returns [float(value), +0.0]. Keep
					# the incoming fatigue's signed zero/type conversion, not a new zero.
					unit.fatigue = float(unit.fatigue)
					unit.fatigue_rest = 0.0
					if combat_profile_enabled:
						fatigue_zero_skipped_advances += 1
					continue
			var captive_rest: bool = site_controller != null and site_controller.person_actions.captive_work_rest_allowed(team.combat_identity(index))
			var idle := (can_act or captive_rest) and not moving and not crew_work and str(team.combat_hot_get(index, &"pose")) == "idle"
			if site_controller != null and site_controller.person_actions.blocks_fatigue_rest(team.combat_identity(index)): idle = false
			if not unit.get("work_task", {}).is_empty() and str(unit.work_task.get("mode", "")) != "rest":
				idle = false # Pending work/input/path waits are not a rest break.
			var safe := false
			if idle and float(unit.fatigue) > 0.0:
				var threat_started := Time.get_ticks_usec() if combat_profile_enabled else 0
				safe = captive_rest or not _fatigue_threat(_army_effective_cell(team, index), team.faction_id, team, index, enemies)
				_combat_profile_stage("fatigue_threat", threat_started)
			var housing_multiplier: float = Site.Housing.recovery_multiplier(self, [unit]) if safe else 1.0
			var state := PersonFatigue.advance(float(unit.fatigue), float(unit.fatigue_rest), available, rate, safe, housing_multiplier)
			unit.fatigue = state[0]
			unit.fatigue_rest = state[1]
	# Inclusive of fatigue_threat; do not add that nested counter a second time.
	_combat_profile_stage("fatigue_people_inclusive", fatigue_started)

func _advance_team_fatigue(team: TerrainArmy, seconds: float, handled: Dictionary, enemies: Dictionary) -> void:
	var shared := team.team_fatigue
	for row: Dictionary in team.combat_units:
		if is_same(PersonFatigue.pool(row), shared) and _shared_pool_has_effort(row):
			shared.active = false
			return
	var effort := 0.0
	var npc_moving := false
	# Reuse actual committed movement claims, not a second moving-person list.
	for destination: Vector2i in team._reserved_cells:
		var index := int(team._reserved_cells[destination])
		var row: Dictionary = team.combat_units[index]
		if not is_same(PersonFatigue.pool(row), shared) or team.moving_to[index] != destination: continue
		npc_moving = true
		if team.combat_can_act(index) and team.move_duration[index] <= TerrainArmy.RUN_DURATION + 0.000001:
			effort += maxf(0.0, seconds - float(handled.get(team.combat_identity(index), 0.0))) * PersonFatigue.RUN_RATE
	for index in range(team.combat_units.size()):
		var row: Dictionary = team.combat_units[index]
		if not is_same(PersonFatigue.pool(row), shared): continue
		var identity := team.combat_identity(index)
		if _ship_crew_work(identity): effort += maxf(0.0, seconds - float(handled.get(identity, 0.0))) * PersonFatigue.WORK_RATE
		if _ship_person_in_journey(identity) or site_controller != null and _ship_embarked(identity) and (not site_controller.vehicles.ships_stopped_for_team(team.team_id) or site_controller.person_actions.is_busy(identity)): npc_moving = true
	if is_instance_valid(team.player_member) and is_same(team.player_member._fatigue_pool, shared):
		var actor := team.player_member
		var actor_rate := actor.riding_fatigue_rate()
		if actor.can_act() and actor.is_moving() and not actor.is_mounted() and actor._movement_duration <= TerrainTestCharacter.RUN_DURATION + 0.000000001:
			actor_rate = PersonFatigue.RUN_RATE
		var worked := minf(seconds, float(_fatigue_work_seconds.get(actor, 0.0)))
		_fatigue_work_seconds[actor] = maxf(0.0, float(_fatigue_work_seconds.get(actor, 0.0)) - worked)
		var available := maxf(0.0, seconds - float(handled.get(actor.person_id, 0.0)) - worked)
		effort += available * actor_rate
	var safe := not bool(shared.active) and effort == 0.0 and not npc_moving and team.combat_order == TerrainArmy.CombatOrder.HOLD \
		and (float(terrain.site.get("combat_left", 0.0)) <= 0.0 or SiteRuntime.fire_active(terrain))
	if safe and float(shared.fatigue) > 0.0:
		# Recovery is a whole-team decision. Any busy/threatened NPC prevents it.
		for index in range(team.combat_units.size()):
			var row: Dictionary = team.combat_units[index]
			if not is_same(PersonFatigue.pool(row), shared): continue
			var captive_rest: bool = site_controller != null and site_controller.person_actions.captive_work_rest_allowed(team.combat_identity(index))
			if str(team.combat_hot_get(index, &"pose")) != "idle" or site_controller != null and site_controller.person_actions.blocks_fatigue_rest(team.combat_identity(index)) or team._unit_rescues.has(index) or (not row.get("work_task", {}).is_empty() and str(row.work_task.get("mode", "")) != "rest" and not bool(row.get("work_resting", false))) or (not captive_rest and _fatigue_threat(_army_effective_cell(team, index), team.faction_id, team, index, enemies)):
				safe = false
				break
		if safe and is_instance_valid(team.player_member) and is_same(team.player_member._fatigue_pool, shared):
			var actor := team.player_member
			var captive_rest: bool = site_controller != null and site_controller.person_actions.captive_work_rest_allowed(actor.person_id)
			safe = (actor.can_act() or captive_rest) and not actor.is_moving() and actor.action_time <= 0.0 and not actor.guarding \
				and actor.guard_transition_left <= 0.0 and actor.guard_break_left <= 0.0 and actor.exchange_stagger <= 0.0 \
				and actor._rescue_left <= 0.0 and (captive_rest or not _fatigue_threat(actor.terrain_cell, team.faction_id, actor, -1, enemies))
	var rate := effort / seconds / maxf(1.0, float(shared.count))
	var recovery_multiplier: float = Site.Garrison.recovery_multiplier(self, team.garrison_feature_id, team.faction_id, team.combat_units) if safe and float(shared.fatigue) > 0.0 else 1.0
	if safe and float(shared.fatigue) > 0.0: recovery_multiplier = maxf(recovery_multiplier, Site.Housing.shared_multiplier(self, team))
	var state := PersonFatigue.advance(float(shared.fatigue), float(shared.fatigue_rest), seconds, rate, safe, recovery_multiplier)
	shared.fatigue = state[0]
	shared.fatigue_rest = state[1]
	shared.active = false

func _fatigue_threat(cell: Vector2i, faction: int, rest_owner: Variant, unit_index: int, candidates: Dictionary) -> bool:
	if SiteRuntime.fire_hazard_at(terrain, cell) > 0.0: return true
	if rest_owner is TerrainArmy and unit_index >= 0 and _ship_embarked(rest_owner.combat_identity(unit_index)):
		return _ship_fatigue_threat(rest_owner.combat_identity(unit_index), faction, candidates)
	if not terrain.is_walkable(cell):
		return true
	if exchange_enabled:
		return _exchange_rest_threat(cell, faction, candidates)
	if not candidates.has(faction):
		var cells := {}
		for actor: TerrainTestCharacter in combat_actors:
			if actor.faction_id != faction and actor.can_act():
				cells[actor.terrain_cell] = true
				if actor.is_moving():
					cells[actor.movement_from_cell] = true
		for team: TerrainArmy in combat_armies:
			if not team.combat_enabled or team.faction_id == faction:
				continue
			for index in range(team.combat_units.size()):
				if not team._ship_in_journey(index) and team.combat_can_act(index):
					cells[_army_effective_cell(team, index)] = true
					if team.moving_to[index] != TerrainArmy.INVALID_CELL:
						cells[team.moving_to[index]] = true
		candidates[faction] = {"cells": cells}
	var threat: Dictionary = candidates[faction]
	# Exact distance-zero/one witnesses from the same directed walk graph.
	# Only a positive proof bypasses the original eight-step search; obstacles,
	# distant enemies and projectiles keep their existing path below.
	if threat.cells.has(cell):
		return true
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var enemy := cell + direction
		if threat.cells.has(enemy) and terrain.can_step(enemy, cell):
			return true
	if fatigue_two_hop_witness_enabled:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var middle := cell + direction
			for source_direction: Vector2i in TerrainData.DIRECTIONS:
				var enemy := middle + source_direction
				if threat.cells.has(enemy) and terrain.can_step(enemy, middle) and terrain.can_step(middle, cell):
					return true # Reverse enumeration, but both edges prove the original forward path.
	var nearby := false
	for enemy: Vector2i in threat.cells:
		var offset := enemy - cell
		if absi(offset.x) + absi(offset.y) <= 8:
			nearby = true
			break
	if nearby:
		if not threat.has("reachable"):
			# One original multi-source frontier per faction in this synchronous
			# step. Pause once this target is found; later targets resume it.
			var distances := {}
			var pending: Array[Vector2i] = []
			for enemy: Vector2i in threat.cells:
				distances[enemy] = 0
				pending.append(enemy)
			threat["reachable"] = distances
			threat["pending"] = pending
			threat["cursor"] = 0
		var frontier_distances: Dictionary = threat.reachable
		var frontier_pending: Array[Vector2i] = threat.pending
		var cursor: int = threat.cursor
		while not frontier_distances.has(cell) and cursor < frontier_pending.size():
			var current := frontier_pending[cursor]
			cursor += 1
			if int(frontier_distances[current]) >= 8:
				continue
			# Complete all four edges before pausing, so resuming never skips
			# the rest of the original node. Negative queries exhaust the frontier.
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next := current + direction
				if not frontier_distances.has(next) and terrain.can_step(current, next):
					frontier_distances[next] = int(frontier_distances[current]) + 1
					frontier_pending.append(next)
		threat.cursor = cursor
		if threat.reachable.has(cell):
			return true
	for actor: TerrainTestCharacter in combat_actors:
		for arrow: Dictionary in actor.projectiles:
			if float(arrow.remaining) <= 0.0:
				continue
			if not SiteCombatRules.terrain_line_clear(terrain, Vector2i((arrow.ground as Vector2) / TerrainRenderer.CELL_PIXELS), cell):
				continue
			if rest_owner is TerrainTestCharacter and rest_owner.editor == null:
				return true # No projection in a headless fixture: conservatively forbid rest, never fabricate a hit.
			var bodies: Array[PackedVector2Array] = rest_owner.combat_shapes(unit_index, "body") if rest_owner is TerrainArmy else rest_owner._geometry.body_shapes(rest_owner)
			var end: Vector2 = arrow.position + (arrow.velocity as Vector2).normalized() * float(arrow.remaining)
			var sweep := FatigueGeometry.capsule(arrow.position, end, 1.0)
			for body: PackedVector2Array in bodies:
				if not Geometry2D.intersect_polygons(sweep, body).is_empty():
					return true
	return false

func _exchange_rest_threat(cell: Vector2i, faction: int, candidates: Dictionary) -> bool:
	# Query the existing authoritative claims lazily. This synchronous fatigue
	# pass changes no positions/KO; only its queried cell answers are memoized.
	if not candidates.has(faction):
		var actor_cells := {}
		for actor: TerrainTestCharacter in combat_actors:
			if actor.faction_id != faction and actor.can_act():
				actor_cells[actor.terrain_cell] = true
				if actor.is_moving(): actor_cells[actor.movement_from_cell] = true
		var ship_cells := {}
		for team: TerrainArmy in combat_armies:
			if not team.combat_enabled or team.faction_id == faction: continue
			for index in range(team.combat_units.size()):
				if not team._ship_in_journey(index) and _ship_embarked(team.combat_identity(index)) and team.combat_can_act(index): ship_cells[_army_effective_cell(team, index)] = true
		var teams: Array[TerrainArmy] = []
		for team: TerrainArmy in combat_armies:
			if team.combat_enabled and team.faction_id != faction: teams.append(team)
		candidates[faction] = {"actors": actor_cells, "ships": ship_cells, "teams": teams, "probes": {}}
	if not candidates.has("flight_cells"):
		var flight_cells := {}
		for source: Node2D in _ranged_owners():
			for flight: Dictionary in source.projectiles:
				if str(flight.get("mode", "")) == "cell":
					for crossed: Vector2i in SiteCombatRules.ranged_cells(flight.source_cell, flight.target_cell):
						flight_cells[crossed] = true
		candidates["flight_cells"] = flight_cells
	if candidates.flight_cells.has(cell): return true
	var snapshot: Dictionary = candidates[faction]
	var probes: Dictionary = snapshot.probes
	for distance in range(9):
		for dx in range(-distance, distance + 1):
			var dy := distance - absi(dx)
			for sign_y in range(1 if dy == 0 else 2):
				var probe := cell + Vector2i(dx, dy if sign_y == 0 else -dy)
				if not probes.has(probe):
					var awake := bool(snapshot.actors.get(probe, false)) or bool(snapshot.ships.get(probe, false))
					for team: TerrainArmy in snapshot.teams:
						if awake: break
						var at_source := int(team._cell_owners.get(probe, -1))
						var at_destination := int(team._reserved_cells.get(probe, -1))
						awake = team.combat_can_act(at_source) or team.combat_can_act(at_destination)
					probes[probe] = awake
				if bool(probes[probe]): return true
	return false

func _exchange_people(readiness: bool = true) -> Array[Dictionary]:
	# Disposable references to original owners, never a second roster or HP store.
	var people: Array[Dictionary] = []
	for actor: TerrainTestCharacter in combat_actors:
		if ExchangeSnapshot.actor_body_available(actor):
			people.append({"owner": actor, "unit": -1, "id": actor.person_id,
				"cell": actor.terrain_cell, "faction": actor.faction_id, "ready": actor.exchange_ready(), "receive": actor.exchange_can_receive()})
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled:
			continue
		if not readiness:
			var projected := team.capture_exchange_people(true)
			if not projected.is_empty():
				people.append_array(projected)
				continue
		for index in range(team.combat_units.size()):
			if not team._ship_in_journey(index) and ExchangeSnapshot.army_body_available(team, index):
				var ready_value: Variant = null
				var receive_value: Variant = null
				if readiness:
					ready_value = team.exchange_ready(index)
					receive_value = team.exchange_can_receive(index)
				people.append({"owner": team, "unit": index, "id": team.combat_identity(index),
					"cell": _army_effective_cell(team, index), "faction": team.faction_id, "ready": ready_value, "receive": receive_value})
	return people

func _exchange_encirclement_front(team: TerrainArmy) -> Array:
	if has_ship_journey(): return [] # Original dictionary fallback filters absent people.
	# The same fresh snapshot as melee. Materialize no per-person dictionaries
	# for command geometry; retain original enemy/contact order and terrain checks.
	# Custom readers can mutate another person's faction while capturing. Keep
	# their original full query and predicate order instead of broad-phase pruning.
	for actor: TerrainTestCharacter in combat_actors:
		if is_instance_valid(actor) and actor.get_script() not in [TerrainTestCharacter, TerrainTestNPC]: return []
	for army_owner: TerrainArmy in combat_armies:
		if army_owner.get_script() != TerrainArmy: return []
	var snapshot := ExchangeSnapshot.new()
	snapshot.capture(combat_actors, combat_armies)
	var enemies := {}
	var order := PackedInt32Array()
	var kernel := TerrainArmy._get_idle_kernel()
	var packet: Array = []
	if team.native_queries_enabled and team.native_front_enabled and kernel != null and kernel.has_method("encirclement_front"):
		packet = kernel.encirclement_front(snapshot.xs, snapshot.ys, snapshot.factions, snapshot.owner_slots, snapshot.owners.find(team), team.faction_id)
	if packet.size() == 2:
		enemies = packet[0]
		order = packet[1]
	else:
		for ordinal in range(snapshot.units.size()):
			if snapshot.factions[ordinal] != team.faction_id:
				enemies[Vector2i(snapshot.xs[ordinal], snapshot.ys[ordinal])] = true
		order = snapshot.front_order(0, _exchange_kernel)
	var contacts: Array[Vector2i] = []
	var pinned := {}
	for ordinal in order:
		var index: int = snapshot.units[ordinal]
		if snapshot.owners[snapshot.owner_slots[ordinal]] != team or index < 0 or not team.is_member(index):
			continue
		var cell := Vector2i(snapshot.xs[ordinal], snapshot.ys[ordinal])
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if enemies.has(next) and team.data.can_attack_across(cell, next):
				contacts.append(cell)
				pinned[index] = true
				break
	return [enemies, contacts, pinned]

func _exchange_initiates(person: Dictionary, other_id: int, melee: bool = false) -> bool:
	if int(person.unit) >= 0:
		var owner_ref: Variant = person.owner
		if owner_ref is CrowdPersonOwner:
			var source: Variant = owner_ref._command_owner(int(person.unit))
			var source_index: int = owner_ref._command_index(int(person.unit))
			if source is TerrainArmy: return source.exchange_initiates(source_index, other_id, melee)
			if source is TerrainTestCharacter: return source.attack_target_id == other_id or (npc_retaliates and source == npc)
			return false
		if owner_ref is TerrainArmy: return owner_ref.exchange_initiates(int(person.unit), other_id, melee)
		return false
	var actor: TerrainTestCharacter = person.owner
	return actor.attack_target_id == other_id or (npc_retaliates and actor == npc)

func _combat_has_ship_people() -> bool:
	for team: TerrainArmy in combat_armies:
		if team.combat_enabled and team._team_has_embarked(): return true
	return false

func _combat_ship_pair(first_id: int, second_id: int) -> bool:
	return _ship_embarked(first_id) or _ship_embarked(second_id)

func _combat_melee_clear(first_id: int, second_id: int, source: Vector2i, target: Vector2i, exact: bool = false) -> bool:
	if _ship_person_in_journey(first_id) or _ship_person_in_journey(second_id): return false
	if _combat_ship_pair(first_id, second_id):
		return site_controller != null and site_controller.vehicles.ship_combat_contact(first_id, second_id)
	return SiteCombatRules.terrain_line_clear(terrain, source, target) if exact else terrain.can_attack_across(source, target)

func _exchange_candidate_cells(cell: Vector2i, naval: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in range(4): result.append(cell + TerrainData.DIRECTIONS[(offset + _exchange_round) % 4])
	# Original deck positions can share a terrain cell or straddle its corner.
	# These extra broad-phase candidates still require actual ship contact.
	if naval:
		result.append(cell)
		for offset: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]: result.append(cell + offset)
	return result

func _person_ranged_line_clear(identity: int, source: Vector2i, target: Vector2i, observe_goal_surface: bool = false) -> bool:
	if not SiteRuntime.fire_smoke_visible(terrain, source, target): return false
	if _ship_person_in_journey(identity): return false
	if _ship_embarked(identity):
		if site_controller == null or not site_controller.vehicles.ship_can_attack(identity) or not terrain.contains(source) or not terrain.contains(target): return false
	elif not observe_goal_surface: return SiteCombatRules.ranged_line_clear(terrain, source, target)
	elif terrain == null or not terrain.is_walkable(source) or not terrain.contains(target): return false
	var ray := SiteCombatRules.ranged_cells(source, target)
	if ray.is_empty(): return false
	for cell: Vector2i in ray:
		# An exposed target surface is visible; an intervening solid still hides it.
		if observe_goal_surface and cell == target: continue
		if not SiteCombatRules.ranged_cell_clear(terrain, source, target, cell): return false
	return true

func _exchange_context(person: Dictionary, occupied: Dictionary) -> Dictionary:
	var sectors := 0
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var next: Vector2i = person.cell + direction
		for other: Dictionary in occupied.get(next, []):
			if int(other.faction) != int(person.faction) and _combat_melee_clear(int(person.id), int(other.id), person.cell, next):
				sectors += 1
				break
	var person_owner: Variant = person.owner
	var index := int(person.unit)
	# Only named command-capable people use automatic skills. The controlled
	# person chooses Q/E, so AI never consumes their pending choice or cooldown.
	if int(person.id) != controlled_person_id():
		if index >= 0:
			if person_owner.command_abilities.has(index):
				person_owner.activate_exchange_skill(index, "brace" if sectors >= 2 else "power")
		elif not person_owner.command_abilities.is_empty():
			person_owner.activate_exchange_skill("brace" if sectors >= 2 else "power")
	var stats: Dictionary = person_owner.exchange_stats(index) if index >= 0 else person_owner.exchange_stats()
	stats.encirclement = sectors
	stats.facility = SiteRuntime.exchange_facility_bonus(terrain, person.cell)
	if site_controller != null:
		# Read the real feeding owner, including independent people and captives;
		# an empty former personal/team pool must not supply stale morale.
		stats.morale = _exchange_morale(int(person.id))
	return stats

func _exchange_morale(identity: int) -> float:
	for entry: Dictionary in terrain.site.get("team_supply", {}).values():
		for cohort: Dictionary in entry.sustain.cohorts:
			if identity in cohort.ids:
				return float(entry.sustain.morale)
	for pool: Dictionary in terrain.site.get("person_supply", {}).values():
		for cohort: Dictionary in pool.cohorts:
			if identity in cohort.ids:
				return float(pool.morale)
	return 100.0

func _prepare_exchange_kernel(warm: bool = false) -> void:
	if _exchange_kernel_checked:
		return
	_exchange_kernel_checked = true
	if ClassDB.class_exists("CSharpScript"):
		var kernel_script: Script = load("res://scripts/terrain_lab/compiled_exchange_candidates.cs")
		if kernel_script != null and kernel_script.can_instantiate(): _exchange_kernel = kernel_script.new()
	if warm and _exchange_kernel != null:
		# Exercise only disposable integer geometry during scene loading, not
		# the first hit. No actual people, terrain, RNG or combat clock is read.
		_exchange_kernel.FrontOrder(PackedInt32Array([0, 0, 1]), PackedInt32Array([0, 0, 0]), PackedInt64Array([0, 1, 1]), 0)

func _resolve_exchanges() -> void:
	if terrain == null:
		return
	_exchange_round += 1
	var profile_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var snapshot: RefCounted
	var people: Array[Dictionary] = []
	var order := PackedInt32Array()
	var occupied := {}
	var naval_people := _combat_has_ship_people()
	if exchange_batch_enabled and not naval_people:
		if not _exchange_kernel_checked:
			_prepare_exchange_kernel()
		snapshot = ExchangeSnapshot.new()
		snapshot.capture(combat_actors, combat_armies)
		order = snapshot.front_order(_exchange_round, _exchange_kernel)
		var natural_order := order.duplicate()
		natural_order.sort() # Same-cell occupants retain original roster order.
		for ordinal: int in natural_order:
			var person: Dictionary = snapshot.person(ordinal)
			if not occupied.has(person.cell): occupied[person.cell] = []
			occupied[person.cell].append(person)
	else:
		people = _exchange_people(false)
		for person: Dictionary in people:
			if not occupied.has(person.cell): occupied[person.cell] = []
			occupied[person.cell].append(person)
		for offset in range(people.size()): order.append((offset + _exchange_round) % people.size())
	profile_started = _combat_profile_stage("exchange_people_index", profile_started)
	var move_encounters := {}
	for team: TerrainArmy in combat_armies:
		if team.combat_enabled and team.combat_order == TerrainArmy.CombatOrder.MOVE:
			move_encounters[team] = {}
	if not move_encounters.is_empty():
		# Encounter is a proximity fact, independent of attack cooldown/readiness.
		for ordinal: int in order:
			var a: Dictionary = snapshot.person(ordinal) if snapshot != null else people[ordinal]
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next: Vector2i = a.cell + direction
				for b: Dictionary in occupied.get(next, []):
					if int(a.id) == int(b.id) or int(a.faction) == int(b.faction):
						continue
					if not bool(a.owner.exchange_enabled) or not bool(b.owner.exchange_enabled):
						continue
					var a_move: bool = int(a.unit) >= 0 and move_encounters.has(a.owner) and a.owner.move_encounter_eligible(int(a.unit))
					var b_move: bool = int(b.unit) >= 0 and move_encounters.has(b.owner) and b.owner.move_encounter_eligible(int(b.unit))
					if not a_move and not b_move:
						continue
					if not terrain.can_attack_across(a.cell, next):
						continue
					if a_move:
						var a_contacts: Dictionary = move_encounters[a.owner]
						var a_enemies: Dictionary = a_contacts.get(int(a.unit), {})
						a_enemies[int(b.id)] = true
						a_contacts[int(a.unit)] = a_enemies
					if b_move:
						var b_contacts: Dictionary = move_encounters[b.owner]
						var b_enemies: Dictionary = b_contacts.get(int(b.unit), {})
						b_enemies[int(a.id)] = true
						b_contacts[int(b.unit)] = b_enemies
	for team: TerrainArmy in combat_armies:
		team.publish_move_encounters(move_encounters.get(team, {}))
	var seen_pairs := {}
	var contexts := {}
	var pending: Array[Dictionary] = []
	# All eligible adjacent enemies meet in this round; only the same unordered
	# pair is skipped when the opposite endpoint appears later in front order.
	for ordinal: int in order:
		var a: Dictionary = snapshot.person(ordinal) if snapshot != null else people[ordinal]
		if a.receive == false:
			continue
		for next: Vector2i in _exchange_candidate_cells(a.cell, naval_people):
			for b: Dictionary in occupied.get(next, []):
				if int(a.id) == int(b.id) or int(a.faction) == int(b.faction):
					continue
				var low := mini(int(a.id), int(b.id))
				var high := maxi(int(a.id), int(b.id))
				var pair_key := "%d:%d" % [low, high]
				if seen_pairs.has(pair_key): continue
				if a.receive == null: a.receive = a.owner.exchange_can_receive(int(a.unit))
				if b.receive == null: b.receive = b.owner.exchange_can_receive(int(b.unit))
				if not bool(a.receive) or not bool(b.receive): continue
				# Distant people never need readiness or numerical context.
				if a.ready == null: a.ready = a.owner.exchange_ready(int(a.unit))
				if b.ready == null: b.ready = b.owner.exchange_ready(int(b.unit))
				if not (bool(a.ready) and _exchange_initiates(a, int(b.id), true)) and not (bool(b.ready) and _exchange_initiates(b, int(a.id), true)):
					continue # Peaceful worker/player neighbours do not spontaneously duel.
				if not _combat_melee_clear(int(a.id), int(b.id), a.cell, next):
					continue # Pure geometry is only needed for a viable opposing pair.
				if not contexts.has(int(a.id)): contexts[int(a.id)] = _exchange_context(a, occupied)
				if not contexts.has(int(b.id)): contexts[int(b.id)] = _exchange_context(b, occupied)
				var stats_a: Dictionary = contexts[int(a.id)]
				var stats_b: Dictionary = contexts[int(b.id)]
				var noise := (low * 73856093) ^ (high * 19349663) ^ (_exchange_round * 83492791) ^ terrain.seed_value
				var roll := float(posmod(noise, 21) - 10) * (1.0 if int(a.id) == low else -1.0)
				pending.append({"a": a, "b": b, "stats_a": stats_a, "stats_b": stats_b,
					"result": SiteCombatRules.exchange_result(stats_a, stats_b, roll)})
				seen_pairs[pair_key] = true
	# Every edge sees pre-resolution abilities/positions. Each original person
	# pays, receives and presents one merged outcome for the whole round.
	profile_started = _combat_profile_stage("exchange_pair_context", profile_started)
	if not _settle_exchange_batch(pending): return
	for pair: Dictionary in pending:
		exchange_count += 1
		exchange_results[str(pair.result.kind)] += 1
		exchange_resolved.emit(int(pair.a.id), int(pair.b.id), pair.result)
	profile_started = _combat_profile_stage("exchange_apply", profile_started)
	_resolve_ranged_fire(snapshot.ranged_people() if snapshot != null else people)
	_combat_profile_stage("exchange_ranged", profile_started)

func _ranged_owners() -> Array[Node2D]:
	var owners: Array[Node2D] = []
	for actor: TerrainTestCharacter in combat_actors:
		if is_instance_valid(actor):
			owners.append(actor)
	for team: TerrainArmy in combat_armies:
		if is_instance_valid(team):
			owners.append(team)
	return owners

func _fire_transport_owners() -> Array[Node2D]:
	var owners: Array[Node2D] = []
	for owner_ref: Node2D in _ranged_owners():
		if owner_ref is TerrainArmy:
			var saved := false
			for saved_team: Dictionary in terrain.site.get("armies", []):
				if int(saved_team.get("team_id", 0)) == owner_ref.team_id:
					saved = true
					break
			if saved or owner_ref.combat_enabled: owners.append(owner_ref)
		elif owner_ref is TerrainTestCharacter and actor_present(owner_ref):
			owners.append(owner_ref)
	return owners

func has_ranged_projectiles() -> bool:
	if not fire_projectiles.is_empty() or not fire_reservations.is_empty(): return true
	return has_unpersisted_ranged_projectiles()

func has_unpersisted_ranged_projectiles() -> bool:
	if has_siege_projectiles(): return true
	if crowd_site != null and crowd_site.active and crowd_site.has_ranged_projectiles(): return true
	if not exchange_enabled:
		return false # Historical exact mode keeps its original save/action guards.
	for projectile_owner: Node2D in _ranged_owners():
		if not projectile_owner.projectiles.is_empty():
			return true
	return false

func has_siege_projectiles() -> bool:
	return not siege_projectiles.is_empty() or not _siege_contact_batch.is_empty()

func siege_save_guard() -> Dictionary:
	if has_siege_projectiles(): return SiteRuntime.fail("BUSY", "攻城彈體仍在飛行；原現場與存檔保留")
	if site_controller != null: return site_controller.vehicles.siege_save_guard()
	return SiteRuntime.ok()

func _siege_tactical_active() -> bool:
	if has_siege_projectiles(): return true
	if site_controller == null or terrain == null: return false
	for vehicle: Dictionary in terrain.site.get("vehicles", {}).values():
		if _ship_vehicle_in_journey(str(vehicle.get("id", ""))): continue
		if not SiteRuntime.SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or float(vehicle.get("hp", 0.0)) <= 0.0: continue
		var stage := str(vehicle.get("action", {}).get("stage", ""))
		if stage in ["loading", "aiming", "preparing", "collision", "recovering"]: return true
		var rule := SiteCombatRules.siege_attack(str(vehicle.kind))
		if str(vehicle.get("command", {}).get("type", "")) == "attack" and not rule.is_empty() and (str(rule.ammo).is_empty() or int(vehicle.cargo.get(str(rule.ammo), 0)) > 0) and site_controller.vehicles.crew_ready(vehicle): return true
	return false

func _siege_active() -> bool:
	if has_siege_projectiles(): return true
	if site_controller == null or terrain == null: return false
	for vehicle: Dictionary in terrain.site.get("vehicles", {}).values():
		if _ship_vehicle_in_journey(str(vehicle.get("id", ""))): continue
		if not SiteRuntime.SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or float(vehicle.get("hp", 0.0)) <= 0.0: continue
		if not vehicle.get("action", {}).is_empty(): return true
		var rule := SiteCombatRules.siege_attack(str(vehicle.kind))
		if str(vehicle.get("command", {}).get("type", "")) == "attack" and not rule.is_empty() \
			and (str(rule.ammo).is_empty() or int(vehicle.cargo.get(str(rule.ammo), 0)) > 0) and site_controller.vehicles.crew_ready(vehicle): return true
	return false

func siege_muzzle(vehicle: Dictionary) -> Vector2:
	var facing := Vector2(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var size: Vector2i = SiteRuntime.SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {}).get("size", Vector2i(2, 3))
	return Vector2(terrain.cell_from_index(int(vehicle.cell))) + Vector2.ONE * 0.5 \
		+ facing * (2.3 if str(vehicle.kind) == "ballista" else float(size.y) - 0.7) + Vector2(-facing.y, facing.x) * float(size.x - 1) * 0.5

func siege_target(target: Dictionary) -> Dictionary:
	match str(target.get("type", "")):
		"person":
			if _ship_person_in_journey(int(target.get("person_id", 0))): return {}
			var person: Dictionary = site_controller.person_actions._person(int(target.get("person_id", 0)))
			if person.is_empty() or float(person.hp) <= 0.0: return {}
			var ground: Vector2 = person.owner.combat_ground(int(person.unit)) if int(person.unit) >= 0 else person.owner.position
			return {"point": ground / TerrainRenderer.CELL_PIXELS, "height": float(terrain.effective_height(person.cell)) + 1.0}
		"vehicle":
			if _ship_vehicle_in_journey(str(target.get("vehicle_id", ""))): return {}
			var vehicle: Dictionary = terrain.site.get("vehicles", {}).get(str(target.get("vehicle_id", "")), {})
			if vehicle.is_empty(): return {}
			var cell := terrain.cell_from_index(int(vehicle.cell))
			return {"point": Vector2(cell) + Vector2.ONE * 0.5, "height": float(terrain.effective_height(cell)) + 0.8}
		"structure":
			var feature: Dictionary = terrain.site.get("features", {}).get(str(target.get("feature_id", "")), {})
			if str(feature.get("stage", "")) != "complete": return {}
			var part: Dictionary = SiteRuntime.feature_geometry(terrain, feature).parts.get(str(target.get("part_id", "")), {})
			if part.is_empty() or float(part.hp) <= 0.0: return {}
			if str(part.role) == "leaf" and bool(feature.get("gate", {}).get("open", false)): return {}
			var cell := terrain.cell_from_index(int(part.cells[0]))
			var point: Vector3 = part.get("aim_point", Vector3(cell.x + 0.5, cell.y + 0.5, float(feature.get("level", 0)) + 0.8))
			return {"point": Vector2(point.x, point.y), "height": point.z}
		"ground":
			var value: Array = target.get("cell", [])
			if value.size() != 2: return {}
			var cell := Vector2i(int(value[0]), int(value[1]))
			if not terrain.contains(cell): return {}
			return {"point": Vector2(cell) + Vector2.ONE * 0.5, "height": float(terrain.effective_height(cell)) + 1.0}
	return {}

func siege_fire_preview(vehicle: Dictionary, target: Dictionary, include_friends: bool = true) -> Dictionary:
	var aim := siege_target(target)
	if aim.is_empty(): return SiteRuntime.fail("NO_TARGET", "原目標已不存在或無有效接觸部件")
	var kind := str(vehicle.get("kind", ""))
	var rule := SiteCombatRules.siege_attack(kind)
	if rule.is_empty(): return SiteRuntime.fail("INVALID")
	if kind == "ram": return siege_ram_preview(vehicle, target, include_friends)
	var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var origin := siege_muzzle(vehicle)
	var distance: float = origin.distance_to(aim.point)
	if distance < float(rule.minimum) - 0.000001 or distance > float(rule.range) + 0.000001:
		return SiteRuntime.fail("RANGE", "發射口射程為 %d–%d 格" % [int(rule.minimum), int(rule.range)])
	if not SiteCombatRules.siege_in_range(origin, aim.point, facing, kind):
		return SiteRuntime.fail("FACING", "目標在正前方 ±45° 外；請先讓原操作班轉向")
	var friends: Array[int] = []
	if not include_friends: return SiteRuntime.ok("射界合法", {"aim": aim, "friendly_ids": friends})
	if str(rule.projectile) == "stone":
		var flight := _siege_flight_snapshot(vehicle, aim, Vector2.ZERO)
		# Endpoint scatter grows from the fixed launch along the same visible curve.
		var preview_scatter := float(rule.scatter) * distance / float(rule.range)
		for event: Dictionary in _siege_stone_person_events(flight, 0.0, 1.0, _siege_people(), preview_scatter):
			if int(event.person.faction) == _siege_faction(vehicle) and not friends.has(int(event.person.id)): friends.append(int(event.person.id))
	else:
		for row: Dictionary in _siege_people():
			if int(row.faction) != _siege_faction(vehicle): continue
			var offset: Vector2 = row.ground / TerrainRenderer.CELL_PIXELS - origin
			var axis: Vector2 = (aim.point - origin).normalized()
			if offset.dot(axis) > 0.0 and offset.dot(axis) < distance and absf(offset.cross(axis)) < 0.5: friends.append(int(row.id))
	friends.sort()
	return SiteRuntime.ok("射線／石體可能傷及友軍：%s" % str(friends) if not friends.is_empty() else "射界合法", {"aim": aim, "friendly_ids": friends})

func _siege_faction(vehicle: Dictionary) -> int:
	for team: TerrainArmy in combat_armies:
		if team.team_id == int(vehicle.team_id): return team.faction_id
	return -1

func _advance_siege(delta: float) -> void:
	if terrain == null or site_controller == null or delta < 0.0 or delta == 0.0 and not _region_point_consuming or bool(terrain.site.get("paused", false)): return
	site_controller.person_actions.settle_fire_pot_trials()
	var own_batch := not _siege_collect_contacts
	if own_batch: siege_begin_contact_batch()
	if delta > 0.0:
		_advance_siege_projectiles(delta)
		site_controller.vehicles.advance_ram_actions(delta)
	if own_batch: siege_flush_contact_batch()
	for vehicle: Dictionary in terrain.site.get("vehicles", {}).values():
		if _ship_vehicle_in_journey(str(vehicle.get("id", ""))): continue
		var rule := SiteCombatRules.siege_attack(str(vehicle.get("kind", "")))
		if rule.is_empty() or str(rule.projectile) not in ["bolt", "stone"] or float(vehicle.get("hp", 0.0)) <= 0.0: continue
		if str(vehicle.get("phase", "")) in ["turning", "moving", "deploying"]: continue
		var action: Dictionary = vehicle.get("action", {})
		if str(action.get("stage", "")) == "recovering":
			action.elapsed = float(action.elapsed) + delta * float(action.multiplier)
			if float(action.elapsed) + 0.000000001 >= float(rule.recovering) and not _region_deferring_endpoint():
				vehicle.action = {}
				vehicle.phase = "ready" if str(vehicle.command.get("type", "")) == "attack" else "idle"
			continue
		if str(vehicle.get("command", {}).get("type", "")) != "attack":
			if str(action.get("stage", "")) in ["loading", "aiming"]: vehicle.action = {}; vehicle.phase = "idle"
			continue
		var preview := siege_fire_preview(vehicle, vehicle.command.target, bool(vehicle.command.get("ai", false)))
		if action.is_empty() and not site_controller.vehicles.crew_ready(vehicle): continue
		if not site_controller.vehicles.crew_ready(vehicle) or not preview.ok:
			vehicle.action = {}
			vehicle.phase = "disabled"
			vehicle.command = {"type": "stop", "reason": "操作班未在位" if not site_controller.vehicles.crew_ready(vehicle) else str(preview.message)}
			continue
		if bool(vehicle.command.get("ai", false)) and not preview.friendly_ids.is_empty():
			vehicle.phase = "disabled"
			continue # Original elapsed/ammunition/RNG remain uncommitted while friends pass.
		var ammo := str(vehicle.command.get("ammo", rule.ammo))
		if not SiteRuntime.siege_ammo_valid(str(vehicle.kind), ammo): continue
		if ammo == "fire_pot":
			var admission: Dictionary = site_controller.person_actions.fire_pot_ammo_guard(vehicle, int(vehicle.command.get("operator_id", 0)), vehicle.command.get("tech_trial", {}))
			if not admission.ok: vehicle.action = {}; vehicle.phase = "disabled"; continue
			if _fire_release_sequence >= 2147483647 or siege_projectiles.size() + fire_projectiles.size() >= fire_projectile_capacity: continue
		if action.is_empty():
			if delta == 0.0: continue
			if int(vehicle.cargo.get(ammo, 0)) < 1:
				vehicle.phase = "ready"
				continue
			action = {"stage": "loading", "elapsed": 0.0, "cargo_version": int(vehicle.holder.version),
				"rng_state": int(vehicle.rng_state), "multiplier": site_controller.vehicles.crew_multiplier(vehicle), "target": vehicle.command.target.duplicate(true)}
			vehicle.action = action
			if not _charge_siege_round(vehicle):
				vehicle.action = {}; vehicle.phase = "disabled"
				vehicle.command = {"type": "stop", "reason": "原隊攻城消耗未通過；本輪未開始"}
				continue
		if str(action.stage) != "recovering" and (int(action.cargo_version) != int(vehicle.holder.version) or int(action.rng_state) != int(vehicle.rng_state)):
			vehicle.action = {}; vehicle.phase = "ready"
			continue
		action.multiplier = site_controller.vehicles.crew_multiplier(vehicle)
		action.elapsed = float(action.elapsed) + delta * float(action.multiplier)
		vehicle.phase = str(action.stage)
		for _transition in range(3):
			var duration := float(rule[str(action.stage)])
			if float(action.elapsed) + 0.000000001 < duration or _region_deferring_endpoint(): break
			action.elapsed = maxf(0.0, float(action.elapsed) - duration)
			if str(action.stage) == "loading": action.stage = "aiming"
			elif str(action.stage) == "aiming":
				var release := SiteRuntime.release_siege_ammo(terrain, str(vehicle.id), int(action.cargo_version), int(action.rng_state), ammo)
				if not release.ok: vehicle.action = {}; vehicle.phase = "ready"; break
				_launch_siege_projectile(vehicle, preview.aim, str(release.attack_id), release.get("scatter_unit", Vector2.ZERO), ammo, str(release.get("technology_payment_id", "")))
				action.stage = "recovering"
			else: vehicle.action = {}; vehicle.phase = "ready"; break
			vehicle.phase = str(action.stage)

func _launch_siege_projectile(vehicle: Dictionary, aim: Dictionary, attack_id: String, scatter_unit: Vector2 = Vector2.ZERO, ammo: String = "", technology_payment_id: String = "") -> void:
	var flight := _siege_flight_snapshot(vehicle, aim, scatter_unit)
	flight.attack_id = attack_id
	if ammo == "fire_pot":
		_fire_release_sequence += 1
		flight.merge({"ammo": ammo, "projectile_id": _fire_release_sequence, "fire_profile": SiteCombatRules.fire_pot_profile(),
			"spawn_action": fire_action_cursor, "fire_resolved": false, "tech_trial": vehicle.command.get("tech_trial", {}),
			"source_member_id": int(vehicle.command.get("operator_id", 0)), "technology_payment_id": technology_payment_id})
		_fire_unsaved = true
	siege_projectiles.append(flight)
	if ammo == "fire_pot": site_controller.person_actions.record_fire_pot_release(vehicle, flight)
	siege_shots += 1
	SiteRuntime.mark_combat(terrain, 10.0)

func _siege_flight_snapshot(vehicle: Dictionary, aim: Dictionary, scatter_unit: Vector2) -> Dictionary:
	var kind := str(vehicle.kind)
	var rule := SiteCombatRules.siege_attack(kind)
	var origin := siege_muzzle(vehicle)
	var source_cell := terrain.cell_from_index(int(vehicle.cell))
	var start_height := float(terrain.effective_height(source_cell)) + 1.0
	var stone := str(rule.projectile) == "stone"
	var distance: float = origin.distance_to(aim.point)
	var goal: Vector2 = aim.point + (scatter_unit * float(rule.get("scatter", 0.0)) * distance / float(rule.range) if stone else Vector2.ZERO)
	var goal_cell := Vector2i(floori(goal.x), floori(goal.y))
	var raw_ground := float(terrain.height_levels[terrain.index(goal_cell)]) if terrain.contains(goal_cell) else float(aim.height) - 1.0
	var goal_height := raw_ground + float(rule.radius_cells) if stone else float(aim.height)
	var start_screen := origin * TerrainRenderer.CELL_PIXELS + terrain.surface_visual_offset(source_cell) - Vector2(0.0, 48.0)
	var goal_screen := goal * TerrainRenderer.CELL_PIXELS - Vector2(0.0, 48.0 * (goal_height - raw_ground))
	return {"kind": kind, "rule": rule.duplicate(true), "rule_version": 1, "source_vehicle": str(vehicle.id), "source_cell": source_cell,
		"faction": _siege_faction(vehicle), "origin": Vector3(origin.x, origin.y, start_height), "goal": Vector3(goal.x, goal.y, goal_height),
		"screen_origin": start_screen, "screen_goal": goal_screen, "position": start_screen, "elapsed": 0.0,
		"total": maxf(0.000001, origin.distance_to(goal) / float(rule.speed)), "budget": 100.0,
		"people": {}, "shields": {}, "bodies": {}, "parts": {}, "ended": false}

func _siege_world_at(flight: Dictionary, fraction: float) -> Vector3:
	return FatigueGeometry.arc_position(flight.origin, flight.goal, float(flight.get("rule", {}).get("arc", 0.0)), fraction)

func _siege_screen_at(flight: Dictionary, fraction: float) -> Vector2:
	return flight.screen_origin.lerp(flight.screen_goal, fraction) - Vector2(0.0, 192.0 * float(flight.get("rule", {}).get("arc", 0.0)) * fraction * (1.0 - fraction))

func _siege_stone_shape(position_pixels: Vector2, radius: float) -> Array[PackedVector2Array]:
	var points := PackedVector2Array()
	# This is the same ellipse the original VehicleView must render: projection
	# of a navigation sphere (64 XY pixels, 48 vertical pixels per original unit).
	for vertex in range(32):
		var angle := TAU * float(vertex) / 32.0
		points.append(position_pixels + Vector2(cos(angle) * 64.0, sin(angle) * 80.0) * radius)
	return [points]

func _siege_stone_person_events(flight: Dictionary, begin: float, end: float, people: Array[Dictionary], preview_scatter: float = 0.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var radius := float(flight.rule.radius_cells)
	# Preview keeps its existing conservative full-scatter height guard; impacts use exactly radius.
	var height_radius := radius if preview_scatter <= 0.0 else radius + preview_scatter
	# Each complete curved sweep stays within .01 screen pixel of the quadratic;
	# slow frames add subdivisions, so they cannot skip a thin body or shield.
	var subdivisions := maxi(1, ceili(sqrt(48.0 * float(flight.rule.arc) / 0.01) * (end - begin)))
	var geometries := {}
	var geometry_bounds := {} # One same-call union of the original body/shield polygon bounds.
	for person: Dictionary in people:
		if flight.people.has(int(person.id)): continue
		var geometry: Dictionary = person.owner.incoming_geometry(int(person.unit)) if int(person.unit) >= 0 else person.owner.incoming_geometry(true)
		geometries[int(person.id)] = geometry
		var bounds := Rect2()
		var has_polygon := false
		for kind: String in ["body", "shield"]:
			for polygon: PackedVector2Array in geometry[kind]:
				if polygon.is_empty(): continue
				var original_bounds: Rect2 = FatigueGeometry.polygon_bounds(polygon)
				bounds = bounds.merge(original_bounds) if has_polygon else original_bounds
				has_polygon = true
		if has_polygon: geometry_bounds[int(person.id)] = bounds.grow(0.001)
	for section in range(subdivisions):
		var first := lerpf(begin, end, float(section) / float(subdivisions))
		var last := lerpf(begin, end, float(section + 1) / float(subdivisions))
		var sweep_radius := radius
		if preview_scatter > 0.0:
			# Enclose every t in this section. The 32-gon needs sec(pi/32) to contain the scatter disk.
			sweep_radius += preview_scatter * last / cos(PI / 32.0)
		var previous := _siege_stone_shape(_siege_screen_at(flight, first), sweep_radius)
		var current := _siege_stone_shape(_siege_screen_at(flight, last), sweep_radius)
		var prepared := FatigueGeometry.prepare_sweeps(previous, current)
		var sweep_bounds: Rect2 = prepared[0].bounds # Original sole stone hull, already padded by0.001.
		for person: Dictionary in people:
			if not geometries.has(int(person.id)): continue
			# A hit requires overlap with at least one original polygon. Keep
			# touching boundaries in the unchanged exact body/shield contact path.
			if not geometry_bounds.has(int(person.id)) or not sweep_bounds.intersects(geometry_bounds[int(person.id)], true): continue
			var geometry: Dictionary = geometries[int(person.id)]
			var hit := FatigueGeometry.person_contact(previous, current, geometry.body, geometry.shield, prepared)
			if hit.is_empty(): continue
			var fraction := lerpf(first, last, float(hit.fraction))
			var height := _siege_world_at(flight, fraction).z
			var base := float(terrain.effective_height(person.cell))
			if height + height_radius < base or height - height_radius > base + 1.8: continue
			hit.fraction = fraction
			hit.merge({"flight": flight, "type": "person", "person": person, "stable": "person:%012d" % int(person.id)})
			var profile := SiteCombatRules.siege_hit_profile(str(flight.kind))
			hit["protection"] = person.owner.contact_protection(int(person.unit), hit, profile) if int(person.unit) >= 0 else person.owner.contact_protection(hit, profile)
			result.append(hit)
			geometries.erase(int(person.id)) # One original person/flight; no three-person limit.
	return result

func _siege_prism_hit(flight: Dictionary, from: Vector3, to: Vector3, begin: float, end: float, bounds: Rect2, lower: float, upper: float) -> Dictionary:
	if str(flight.get("kind", "ballista")) != "ballista":
		return FatigueGeometry.arc_prism_contact(flight.origin, flight.goal, float(flight.rule.arc), begin, end, bounds, lower, upper, float(flight.rule.radius_cells))
	var hit := FatigueGeometry.bolt_prism_contact(from, to, bounds, lower, upper)
	if not hit.is_empty(): hit.fraction = lerpf(begin, end, float(hit.fraction))
	return hit

func _siege_boundary_event(flight: Dictionary, begin: float, end: float) -> Dictionary:
	var start: Vector3 = flight.origin
	var goal: Vector3 = flight.goal
	var fraction := INF
	for axis in range(2):
		var boundary := 0.0 if goal[axis] < 0.0 else float(terrain.size[axis])
		if goal[axis] >= 0.0 and goal[axis] < float(terrain.size[axis]): continue
		if absf(goal[axis] - start[axis]) > 0.00000001: fraction = minf(fraction, (boundary - start[axis]) / (goal[axis] - start[axis]))
	if fraction >= begin - 0.00000001 and fraction <= end + 0.00000001:
		return {"flight": flight, "type": "blocked", "fraction": clampf(fraction, begin, end), "stable": "boundary"}
	return {}

func siege_begin_contact_batch() -> void:
	if _siege_collect_contacts: return
	_siege_contact_batch.clear()
	_siege_collect_contacts = true

func siege_flush_contact_batch() -> Dictionary:
	if _region_deferring_endpoint(): return SiteRuntime.ok("", {"complete": false, "pending": true})
	_siege_collect_contacts = false
	var result := _resolve_siege_projectile_events(_siege_contact_batch)
	_siege_contact_batch.clear()
	return result

func siege_queue_damage(parts: Dictionary, vehicles: Dictionary, original_person_id: int) -> Dictionary:
	if not _siege_collect_contacts: return siege_apply_damage_batch(parts, vehicles)
	var flight := {"attack_id": "ordinary:%012d" % original_person_id}
	for key: String in parts:
		var part: Dictionary = parts[key]
		_siege_contact_batch.append({"type": "direct_structure", "feature": part.feature, "part": part.part,
			"damage": float(part.damage), "fire_request": part.duplicate(true) if part.has("generation") else {}, "flight": flight, "stable": key, "contact_seconds": 1.0})
	for key: String in vehicles:
		if _ship_vehicle_in_journey(key): continue
		_siege_contact_batch.append({"type": "direct_vehicle", "vehicle": key, "damage": float(vehicles[key]),
			"flight": flight, "stable": "vehicle:" + key, "contact_seconds": 1.0})
	return SiteRuntime.ok("原普通接觸攻擊已進本輪唯一結構批次")

func siege_apply_damage_batch(parts: Dictionary, vehicles: Dictionary) -> Dictionary:
	# ponytail: bounded 100x100 Site snapshot; use dependency-indexed cells only
	# if a larger formal Site is introduced. This is one post-contact batch.
	var heights := terrain.navigation_heights().duplicate()
	var walkable := PackedByteArray()
	walkable.resize(terrain.size.x * terrain.size.y)
	for index in range(walkable.size()): walkable[index] = int(terrain.is_walkable(terrain.cell_from_index(index)))
	var results := {}
	var keys: Array = parts.keys()
	keys.sort()
	for key: String in keys:
		var damage: Dictionary = parts[key]
		var guard := SiteRuntime.fire_structure_request_guard(terrain, damage)
		results[key] = SiteRuntime.damage_structure_part(terrain, str(damage.feature), str(damage.part), float(damage.damage)) if guard.ok else guard
		SiteRuntime.fire_structure_outcome(terrain, damage, results[key])
	keys = vehicles.keys()
	keys.sort()
	for key: String in keys:
		if _ship_vehicle_in_journey(key): continue
		var vehicle: Dictionary = terrain.site.get("vehicles", {}).get(key, {})
		results["vehicle:" + key] = SiteRuntime.damage_ship_vehicle(terrain, key, float(vehicles[key])) if str(vehicle.get("kind", "")) == "ship" else SiteRuntime.damage_siege_vehicle(terrain, key, float(vehicles[key]))
	SiteRuntime.invalidate_siege_tower_supports(terrain)
	var lost := {}
	var lost_cells := {}
	for index in range(walkable.size()):
		var cell := terrain.cell_from_index(index)
		if int(heights[index]) > terrain.effective_height(cell): lost[index] = int(heights[index])
		if bool(walkable[index]) and not terrain.is_walkable(cell): lost_cells[index] = true
	var result := SiteRuntime.ok("同輪部件及器具命中已結算", {"lost_surfaces": lost, "lost_cells": lost_cells, "results": results})
	resolve_structure_change(result)
	SiteRuntime.mark_combat(terrain, 10.0)
	return result

func _siege_ram_shapes(vehicle: Dictionary, fraction: float) -> Array[PackedVector2Array]:
	var direction := Vector2(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var side := Vector2(-direction.y, direction.x)
	var definition: Dictionary = SiteRuntime.SIEGE_DEFINITIONS[str(vehicle.kind)]
	var size: Vector2i = definition.size
	var ground := Vector2(terrain.cell_from_index(int(vehicle.cell))) + Vector2.ONE * 0.5 \
		+ direction * (float(size.y) - 0.5 + clampf(fraction, 0.0, 1.0)) + side * float(size.x - 1) * 0.5
	var center := ground * TerrainRenderer.CELL_PIXELS + terrain.surface_visual_offset(terrain.cell_from_index(int(vehicle.cell))) - Vector2(0, 48)
	var width := side * 19.2
	var length := direction * 9.6
	return [PackedVector2Array([center - width - length, center + width - length, center + width + length, center - width + length])]

func siege_ram_preview(vehicle: Dictionary, target: Dictionary, include_friends: bool = true) -> Dictionary:
	if str(target.get("type", "")) != "structure": return SiteRuntime.fail("INVALID", "衝車只准指定真門扇／牆部件")
	var feature: Dictionary = terrain.site.get("features", {}).get(str(target.get("feature_id", "")), {})
	var part: Dictionary = SiteRuntime.feature_geometry(terrain, feature).parts.get(str(target.get("part_id", "")), {})
	if str(feature.get("stage", "")) != "complete" or part.is_empty() or float(part.hp) <= 0.0 or str(part.role) not in ["leaf", "wall"]: return SiteRuntime.fail("NO_TARGET")
	if str(part.role) == "leaf" and bool(feature.get("gate", {}).get("open", false)): return SiteRuntime.fail("NO_TARGET")
	var facing := Vector2(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var side := Vector2(-facing.y, facing.x)
	var size: Vector2i = SiteRuntime.SIEGE_DEFINITIONS[str(vehicle.kind)].size
	var center := Vector2(terrain.cell_from_index(int(vehicle.cell))) + Vector2.ONE * 0.5 + facing * (float(size.y) - 0.5) + side * float(size.x - 1) * 0.5
	var height := float(terrain.effective_height(terrain.cell_from_index(int(vehicle.cell)))) + 1.0
	for value: int in part.cells:
		var cell := terrain.cell_from_index(value)
		var hit := FatigueGeometry.segment_prism_contact(Vector3(center.x, center.y, height), Vector3(center.x + facing.x, center.y + facing.y, height), Rect2(Vector2(cell), Vector2.ONE), float(feature.get("level", 0)), maxf(float(part.height), float(feature.get("level", 0)) + 2.0))
		if not hit.is_empty():
			var friends: Array[int] = []
			if not include_friends: return SiteRuntime.ok("真撞頭可接觸指定部件；友軍危險：%s" % str(friends), {"aim": siege_target(target), "friendly_ids": friends})
			var previous := _siege_ram_shapes(vehicle, 0.0)
			var current := _siege_ram_shapes(vehicle, 1.0)
			var prepared := FatigueGeometry.prepare_sweeps(previous, current)
			for person: Dictionary in _siege_people():
				if int(person.faction) != _siege_faction(vehicle): continue
				var geometry: Dictionary = person.owner.incoming_geometry(int(person.unit)) if int(person.unit) >= 0 else person.owner.incoming_geometry(true)
				var contact := FatigueGeometry.person_contact(previous, current, geometry.body, geometry.shield, prepared)
				var base := float(terrain.effective_height(person.cell))
				if not contact.is_empty() and height >= base and height <= base + 1.8: friends.append(int(person.id))
			friends.sort()
			return SiteRuntime.ok("真撞頭可接觸指定部件；友軍危險：%s" % str(friends), {"aim": siege_target(target), "friendly_ids": friends})
	return SiteRuntime.fail("RANGE", "撞頭無法真接觸指定部件")

func siege_ram_hit(vehicle: Dictionary, target: Dictionary, attack_id: String, previous_phase: float = 0.0, current_phase: float = 1.0) -> Dictionary:
	var preview := siege_ram_preview(vehicle, target, false)
	if not preview.ok:
		if not str(vehicle.get("action", {}).get("attack_id", "")).is_empty(): return SiteRuntime.ok("原部件已失效；本輪撞頭安全收束", {"hit": false})
		return preview
	var previous := _siege_ram_shapes(vehicle, previous_phase)
	var current := _siege_ram_shapes(vehicle, current_phase)
	var prepared := FatigueGeometry.prepare_sweeps(previous, current)
	var events: Array[Dictionary] = []
	for person: Dictionary in _siege_people():
		if not _siege_person_sweep_candidate(person, prepared[0].bounds): continue
		var geometry: Dictionary = person.owner.incoming_geometry(int(person.unit)) if int(person.unit) >= 0 else person.owner.incoming_geometry(true)
		var hit := FatigueGeometry.person_contact(previous, current, geometry.body, geometry.shield, prepared)
		if hit.is_empty(): continue
		var base := float(terrain.effective_height(terrain.cell_from_index(int(vehicle.cell))))
		if terrain.effective_height(person.cell) > base + 1.0 or terrain.effective_height(person.cell) + 1.8 < base + 1.0: continue
		hit.merge({"type": "person", "person": person, "stable": "person:%012d" % int(person.id)})
		var profile := SiteCombatRules.siege_hit_profile("ram")
		hit["protection"] = person.owner.contact_protection(int(person.unit), hit, profile) if int(person.unit) >= 0 else person.owner.contact_protection(hit, profile)
		events.append(hit)
	events.append_array(_siege_ram_prism_events(vehicle, previous_phase, current_phase))
	if events.is_empty(): return SiteRuntime.ok("撞頭尚未接觸", {"hit": false})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.fraction) < float(b.fraction) if not is_equal_approx(float(a.fraction), float(b.fraction)) else str(a.stable) < str(b.stable))
	var action: Dictionary = vehicle.action
	if str(action.get("attack_id", "")).is_empty():
		var commit := SiteRuntime.commit_siege_impact(terrain, str(vehicle.id), int(vehicle.next_attack_seq))
		if not commit.ok: return commit
		action["attack_id"] = str(commit.attack_id)
		attack_id = str(commit.attack_id)
	if attack_id != str(action.attack_id): return SiteRuntime.fail("STALE_SOURCE")
	if not action.has("people"): action.people = {}
	if not action.has("parts"): action.parts = {}

	var event: Dictionary = events[0]
	if str(action.get("blocked_by", "")) == "person" and str(event.type) != "person":
		return SiteRuntime.ok("真人仍擋住本輪撞頭", {"hit": true, "attack_id": attack_id, "blocked": true})
	var flight := {"kind": "ram", "attack_id": attack_id, "people": action.people, "parts": action.parts,
		"source_cell": terrain.cell_from_index(int(vehicle.cell)), "ended": false, "position": current[0][0],
		"screen_origin": Vector2.ZERO, "screen_goal": Vector2.ZERO, "rule": SiteCombatRules.siege_attack("ram")}
	if str(event.type) == "person":
		action["blocked_by"] = "person"
		if action.people.has(int(event.person.id)): return SiteRuntime.ok("同原人本撞已結算", {"hit": true, "attack_id": attack_id, "blocked": true})
	else:
		var key := str(event.get("feature", "")) + "|" + str(event.get("part", ""))
		if action.parts.has(key): return SiteRuntime.ok("同原部件本撞已結算", {"hit": true, "attack_id": attack_id})
	event["flight"] = flight
	var multiplier := maxf(0.00000001, float(action.get("multiplier", 1.0)))
	event["contact_seconds"] = float(action.get("contact_step_offset", 0.0)) + float(event.fraction) * (current_phase - previous_phase) * 0.25 / multiplier
	if _siege_collect_contacts: _siege_contact_batch.append(event)
	else: _resolve_siege_projectile_events([event])
	return SiteRuntime.ok("原撞頭真接觸已結算", {"hit": true, "attack_id": attack_id, "blocked": str(event.type) == "person"})

func _siege_ram_prism_events(vehicle: Dictionary, begin: float, end: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var direction := Vector2(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var side := Vector2(-direction.y, direction.x)
	var size: Vector2i = SiteRuntime.SIEGE_DEFINITIONS[str(vehicle.kind)].size
	var anchor := terrain.cell_from_index(int(vehicle.cell))
	var center := Vector2(anchor) + Vector2.ONE * 0.5 + direction * (float(size.y) - 0.5) + side * float(size.x - 1) * 0.5
	var height := float(terrain.effective_height(anchor)) + 1.0
	var from := Vector3(center.x + direction.x * begin, center.y + direction.y * begin, height)
	var to := Vector3(center.x + direction.x * end, center.y + direction.y * end, height)
	var extent := direction.abs() * 0.15 + side.abs() * 0.3
	for key: String in terrain.site.get("features", {}):
		var feature: Dictionary = terrain.site.features[key]
		if str(feature.get("stage", "")) != "complete": continue
		var geometry := SiteRuntime.feature_geometry(terrain, feature)
		for part_id: String in geometry.parts:
			var part: Dictionary = geometry.parts[part_id]
			if float(part.hp) <= 0.0 or str(part.role) == "leaf" and bool(feature.get("gate", {}).get("open", false)): continue
			var base := float(part.get("lower", feature.get("level", 0)))
			var top := float(part.get("upper", maxf(base + 0.5, float(part.height)) if str(part.role) in ["wall", "stairs"] else base + 2.0))
			for value: int in part.cells:
				var cell := terrain.cell_from_index(value)
				var bounds := Rect2(Vector2(cell) - extent, Vector2.ONE + extent * 2.0)
				var hit := FatigueGeometry.segment_prism_contact(from, to, bounds, base - 0.125, top + 0.125)
				if hit.is_empty(): continue
				hit.merge({"type": "structure" if str(part.role) in ["leaf", "wall"] else "blocked", "feature": key, "part": part_id,
					"material": str(part.get("material", "wood" if str(part.role) == "leaf" else str(feature.get("material", "wood")))), "stable": "structure:" + key + ":" + part_id})
				result.append(hit)
		if geometry.parts.is_empty():
			for value: int in geometry.blocked:
				var cell := terrain.cell_from_index(value)
				var hit := FatigueGeometry.segment_prism_contact(from, to, Rect2(Vector2(cell) - extent, Vector2.ONE + extent * 2.0), float(feature.get("level", 0)) - 0.125, float(feature.get("level", 0)) + 2.125)
				if not hit.is_empty(): hit.merge({"type": "blocked", "stable": "blocked:" + key}); result.append(hit)
	for key: String in terrain.site.get("vehicles", {}):
		if _ship_vehicle_in_journey(key): continue
		if key == str(vehicle.id): continue
		for cell: Vector2i in SiteVehicleTransport.footprint(terrain, terrain.site.vehicles[key]):
			var base := float(terrain.effective_height(cell))
			var hit := FatigueGeometry.segment_prism_contact(from, to, Rect2(Vector2(cell) - extent, Vector2.ONE + extent * 2.0), base - 0.125, base + 1.125)
			if not hit.is_empty(): hit.merge({"type": "blocked", "stable": "vehicle:" + key}); result.append(hit)
	return result

func _resolve_siege_projectile_events(events: Array[Dictionary]) -> Dictionary:
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.contact_seconds), float(b.contact_seconds)): return float(a.contact_seconds) < float(b.contact_seconds)
		if str(a.flight.attack_id) != str(b.flight.attack_id): return str(a.flight.attack_id) < str(b.flight.attack_id)
		return str(a.stable) < str(b.stable))
	var part_damage := {}
	var vehicle_damage := {}
	for event: Dictionary in events:
		if str(event.type) in ["direct_vehicle", "vehicle"] and _ship_vehicle_in_journey(str(event.get("vehicle", ""))): continue
		if str(event.type) == "direct_structure":
			var key := str(event.feature) + "|" + str(event.part)
			if not part_damage.has(key): part_damage[key] = {"feature": event.feature, "part": event.part, "damage": 0.0}
			part_damage[key].damage += float(event.damage)
			var fire_request: Dictionary = event.get("fire_request", {})
			if not fire_request.is_empty():
				part_damage[key]["generation"] = int(fire_request.generation)
				part_damage[key]["fire_damage"] = float(part_damage[key].get("fire_damage", 0.0)) + float(fire_request.fire_damage)
				part_damage[key]["collapse_generation"] = maxi(int(part_damage[key].get("collapse_generation", 0)), int(fire_request.collapse_generation))
			continue
		if str(event.type) == "direct_vehicle":
			vehicle_damage[event.vehicle] = float(vehicle_damage.get(event.vehicle, 0.0)) + float(event.damage)
			continue
		var flight: Dictionary = event.flight
		var kind := str(flight.get("kind", "ballista"))
		# A stone can contact several original parts at its one first impact.
		if bool(flight.ended) and (kind == "ballista" or absf(float(event.fraction) - float(flight.get("stop_fraction", -1.0))) > 0.00000001): continue
		if flight.get("ammo") == "fire_pot" and not bool(flight.get("fire_resolved", false)):
			_settle_siege_fire_pot_impact(flight, event)
			flight.ended = true
			flight["stop_fraction"] = float(event.fraction)
			flight.position = _siege_screen_at(flight, float(event.fraction))
		if str(event.type) in ["body", "shield", "person"]:
			_siege_person_contact(flight, event)
			continue
		if not bool(flight.ended):
			flight.ended = true
			flight["stop_fraction"] = float(event.fraction)
			flight.position = _siege_screen_at(flight, float(event.fraction))
		if str(event.type) == "structure":
			var key := str(event.feature) + "|" + str(event.part)
			if flight.get("parts", {}).has(key): continue
			if not flight.has("parts"): flight.parts = {}
			flight.parts[key] = true
			if not part_damage.has(key): part_damage[key] = {"feature": event.feature, "part": event.part, "damage": 0.0}
			part_damage[key].damage += SiteCombatRules.structure_damage("", str(event.material), kind)
		elif str(event.type) == "vehicle":
			var key := "vehicle:" + str(event.vehicle)
			if flight.get("parts", {}).has(key): continue
			if not flight.has("parts"): flight.parts = {}
			flight.parts[key] = true
			vehicle_damage[event.vehicle] = float(vehicle_damage.get(event.vehicle, 0.0)) + SiteCombatRules.structure_damage("", "wood", kind)
	var settled := SiteRuntime.ok("原結構批次沒有接觸", {"results": {}})
	if not part_damage.is_empty() or not vehicle_damage.is_empty(): settled = siege_apply_damage_batch(part_damage, vehicle_damage)
	for index in range(siege_projectiles.size() - 1, -1, -1):
		var flight: Dictionary = siege_projectiles[index]
		if bool(flight.ended) or float(flight.elapsed) >= float(flight.total): siege_projectiles.remove_at(index)
	return settled

func _charge_siege_round(vehicle: Dictionary) -> bool:
	var count: int = site_controller.vehicles.crew_count(vehicle, true)
	if crowd_site != null and crowd_site.active:
		var members := PackedInt32Array()
		for identity: int in vehicle.crew_slots.values():
			var owner_ref: Variant = crowd_site.person_owner(identity)
			if owner_ref == null or not owner_ref.combat_can_act(owner_ref.index_for_identity(identity)): return false
			members.append(owner_ref.index_for_identity(identity))
		return members.size() == count and count > 0 and bool(crowd_site.crowd.charge_siege_round(members, SiteCombatRules.EXCHANGE_FATIGUE))
	for identity: int in vehicle.crew_slots.values():
		var person: Dictionary = site_controller.person_actions._person(identity)
		if person.is_empty() or int(person.unit) < 0: continue
		PersonFatigue.charge(person.body, SiteCombatRules.EXCHANGE_FATIGUE * count)
		return true
	return false

func _siege_people() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if crowd_site != null and crowd_site.active:
		for owner_ref: CrowdPersonOwner in crowd_site.person_owners():
			for index: int in owner_ref.combat_units:
				var values: PackedFloat64Array = owner_ref._soldier_values(index)
				if values.size() != 27 or values[0] <= 0.0 or bool(owner_ref.combat_hot_get(index, &"site_exited", false)): continue
				var ground := Vector2(values[14], values[15]) * TerrainRenderer.CELL_PIXELS
				result.append({"owner": owner_ref, "unit": index, "id": owner_ref.combat_identity(index),
					"faction": owner_ref.faction_id, "ground": ground, "cell": Vector2i((ground / TerrainRenderer.CELL_PIXELS).floor())})
		for actor: TerrainTestCharacter in combat_actors:
			if not is_instance_valid(actor) or crowd_site.contains_person(actor.person_id) or actor.hp <= 0.0 or actor.site_exited: continue
			result.append({"owner": actor, "unit": -1, "id": actor.person_id, "faction": actor.faction_id,
				"ground": actor.position, "cell": actor.terrain_cell})
		return result
	for owner_ref: Node2D in _ranged_owners():
		var count: int = owner_ref.combat_units.size() if owner_ref is TerrainArmy else 1
		for index in range(count):
			if owner_ref is TerrainArmy and owner_ref._ship_in_journey(index): continue
			var hp: float = float(owner_ref.combat_hot_get(index, &"hp")) if owner_ref is TerrainArmy else float(owner_ref.hp)
			var exited: bool = bool(owner_ref.combat_hot_get(index, &"site_exited", false)) if owner_ref is TerrainArmy else owner_ref.site_exited
			if hp <= 0.0 or exited: continue
			var ground: Vector2 = owner_ref.combat_ground(index) if owner_ref is TerrainArmy else owner_ref.position
			var cell := Vector2i(floori(ground.x / TerrainRenderer.CELL_PIXELS), floori(ground.y / TerrainRenderer.CELL_PIXELS))
			result.append({"owner": owner_ref, "unit": index if owner_ref is TerrainArmy else -1,
				"id": owner_ref.combat_identity(index) if owner_ref is TerrainArmy else owner_ref.combat_identity(),
				"faction": owner_ref.faction_id, "ground": ground, "cell": cell})
	return result

func _siege_bolt_shape(position_pixels: Vector2, direction: Vector2) -> Array[PackedVector2Array]:
	var side := Vector2(-direction.y, direction.x) * float(SiteCombatRules.BALLISTA.radius)
	var tip := direction * 6.0
	return [PackedVector2Array([position_pixels - tip - side, position_pixels + tip - side,
		position_pixels + tip + side, position_pixels - tip + side])]

func _siege_person_sweep_candidate(person: Dictionary, sweep_bounds: Rect2) -> bool:
	# Reject only with the original Source proof; all unknown/current work/live
	# domains retain the exact body/shield owner below. No projected shape cache.
	if not sweep_bounds.position.is_finite() or not sweep_bounds.end.is_finite() or maxf(maxf(absf(sweep_bounds.position.x), absf(sweep_bounds.position.y)), maxf(absf(sweep_bounds.end.x), absf(sweep_bounds.end.y))) > 16384.0: return true
	var unit := int(person.unit)
	var inputs: Dictionary = {}
	var source: RefCounted
	if person.owner is TerrainArmy:
		var army_team: TerrainArmy = person.owner
		if unit <= 0 or unit >= army_team.combat_units.size() or army_team.combat_proxy != null or army_team._uses_live_presenter(unit): return true
		var row: Dictionary = army_team.combat_units[unit]
		if bool(army_team.combat_hot_get(unit, &"attack")) and army_team.facing[unit] == Vector2i.DOWN and row.get("aim", []).size() == 2: return true
		inputs = army_team._contact_inputs(unit)
		source = TerrainArmy.contact_source_for(inputs.appearance)
	elif person.owner is CrowdPersonOwner:
		var native_owner: CrowdPersonOwner = person.owner
		# Original Actors keep their live/foot route. Do not pre-sample a mounted
		# Actor just to discover that its bound must fall back.
		if native_owner.crowd_site == null or native_owner.crowd_site._actors.has(int(person.id)): return true
		inputs = native_owner._siege_contact_inputs(unit)
		if inputs.has("actor"): return true
		source = inputs.get("source")
	else: return true
	if source == null or inputs.is_empty(): return true
	var sample: Array = inputs.get("sample", [])
	var appearance: Dictionary = inputs.get("appearance", {})
	var origin: Vector2 = inputs.get("origin", Vector2(INF, INF))
	if sample.size() < 3 or str(sample[0]).begins_with("siege_") or not origin.is_finite() or maxf(absf(origin.x), absf(origin.y)) > 16384.0: return true
	if sample.size() >= 5 and (sample[3] != Vector2.ZERO or float(sample[4]) != 0.0): return true
	if appearance.is_empty() or not is_finite(float(sample[1])) or float(sample[1]) < 0.0 or not source.supports_appearance(appearance): return true
	var animation: Animation = source.editor.animation_player.get_animation(StringName(sample[0]))
	if animation == null or float(sample[1]) > animation.length: return true
	# Reuse query_bounds' warm original face guard. Cold first fitting remains
	# in incoming_geometry, at its original pose and original traversal order.
	var component: Dictionary = source.editor._component_definition(&"face", StringName(str(appearance.parts.face)))
	var nodes: Array = source.editor._find_component_nodes(component.get("prefixes", []))
	if nodes.size() != 1 or not nodes[0] is MeshInstance3D or not source.geometry._head_bounds.has(nodes[0].get_instance_id()): return true
	var radius: float = source.conservative_nonattack_radius(StringName(sample[0]), appearance)
	if not is_finite(radius) or radius <= 0.0 or radius >= 256.0: return true
	# Native inputs already carry the actual surface offset; Army inputs carry
	# their exact combat origin. The original radius includes its roundoff pad.
	return sweep_bounds.intersects(Rect2(origin - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), true)

func _advance_siege_projectiles(delta: float) -> void:
	if siege_projectiles.is_empty() or delta <= 0.0: return
	var events: Array[Dictionary] = []
	var people := _siege_people()
	for flight: Dictionary in siege_projectiles:
		var before := clampf(float(flight.elapsed) / float(flight.total), 0.0, 1.0)
		flight.elapsed = minf(float(flight.total), float(flight.elapsed) + delta)
		var after := clampf(float(flight.elapsed) / float(flight.total), 0.0, 1.0)
		var from := _siege_world_at(flight, before)
		var to := _siege_world_at(flight, after)
		var collected: Array[Dictionary] = []
		if str(flight.get("kind", "ballista")) == "ballista":
			var direction: Vector2 = (flight.screen_goal - flight.screen_origin).normalized()
			var previous := _siege_bolt_shape(_siege_screen_at(flight, before), direction)
			var current := _siege_bolt_shape(_siege_screen_at(flight, after), direction)
			var prepared := FatigueGeometry.prepare_sweeps(previous, current)
			for person: Dictionary in people:
				if not _siege_person_sweep_candidate(person, prepared[0].bounds): continue
				var geometry: Dictionary = person.owner.incoming_geometry(int(person.unit)) if int(person.unit) >= 0 else person.owner.incoming_geometry(true)
				for kind: String in ["shield", "body"]:
					if (flight.shields if kind == "shield" else flight.bodies).has(int(person.id)): continue
					var hit: Dictionary = FatigueGeometry.contact(previous, current, geometry[kind], prepared)
					if hit.is_empty(): continue
					var fraction := lerpf(before, after, float(hit.fraction))
					var height := _siege_world_at(flight, fraction).z
					var base := float(terrain.effective_height(person.cell))
					if height < base or height > base + 1.8: continue
					hit.merge({"flight": flight, "type": kind, "person": person, "stable": "person:%012d:%s" % [int(person.id), "0" if kind == "shield" else "1"], "shield": kind == "shield"})
					hit.fraction = fraction
					hit["protection"] = person.owner.contact_protection(int(person.unit), hit, SiteCombatRules.siege_profile(100.0)) if int(person.unit) >= 0 else person.owner.contact_protection(hit, SiteCombatRules.siege_profile(100.0))
					collected.append(hit)
		else: collected.append_array(_siege_stone_person_events(flight, before, after, people))
		collected.append_array(_siege_prism_events(flight, from, to, before, after))
		var boundary := _siege_boundary_event(flight, before, after)
		if not boundary.is_empty(): collected.append(boundary)
		if flight.get("ammo") == "fire_pot" and after >= 1.0 and not bool(flight.get("fire_resolved", false)):
			collected.append({"flight": flight, "type": "ground", "fraction": 1.0, "stable": "ground:%d:%d" % [floori(flight.goal.x), floori(flight.goal.y)]})
		for event: Dictionary in collected:
			event["contact_seconds"] = (float(event.fraction) - before) * float(flight.total)
			events.append(event)
		flight.position = _siege_screen_at(flight, after)
	if _siege_collect_contacts:
		_siege_contact_batch.append_array(events)
	else: _resolve_siege_projectile_events(events)

func _siege_person_contact(flight: Dictionary, event: Dictionary) -> void:
	var person: Dictionary = event.person
	var identity := int(person.id)
	var kind := str(flight.get("kind", "ballista"))
	if kind != "ballista":
		if flight.people.has(identity): return
		flight.people[identity] = true
		var profile := SiteCombatRules.siege_hit_profile(kind)
		var protection: Vector2 = event.protection
		var damage := SiteCombatRules.damage(profile, protection.x, protection.y, int(event.body), bool(event.shield))
		damage["stagger"] = 0.35
		var packet := {"result": damage, "siege": true, "shield": bool(event.shield), "attacker": null, "ranged": true}
		if int(person.unit) >= 0: person.owner.ranged_apply_hit(int(person.unit), flight.source_cell, packet)
		else: person.owner.ranged_apply_hit(flight.source_cell, packet)
		siege_contacts += 1
		SiteRuntime.mark_combat(terrain, 10.0)
		return
	if not flight.people.has(identity):
		if flight.people.size() >= int(SiteCombatRules.BALLISTA.people_limit): flight.ended = true; return
		flight.people[identity] = true
	if str(event.type) == "shield":
		if flight.shields.has(identity): return
		flight.shields[identity] = true
		var appearance: Dictionary = person.owner.equipment_appearance(int(person.unit)) if int(person.unit) >= 0 else site_controller.person_appearance(identity)
		flight.budget = maxf(0.0, float(flight.budget) - SiteCombatRules.siege_shield_resistance(str(appearance.get("parts", {}).get("shield", ""))))
	else:
		if flight.bodies.has(identity): return
		flight.bodies[identity] = true
		var profile := SiteCombatRules.siege_profile(float(flight.budget))
		var protection: Vector2 = event.protection
		var damage := SiteCombatRules.damage(profile, protection.x, protection.y, int(event.body), false)
		damage["stagger"] = 0.35
		var packet := {"result": damage, "siege": true, "shield": false, "attacker": null, "ranged": true}
		if int(person.unit) >= 0: person.owner.ranged_apply_hit(int(person.unit), flight.source_cell, packet)
		else: person.owner.ranged_apply_hit(flight.source_cell, packet)
		flight.budget = maxf(0.0, float(flight.budget) - float(SiteCombatRules.BALLISTA.body_resistance))
		siege_contacts += 1
		SiteRuntime.mark_combat(terrain, 10.0)
	if float(flight.budget) <= 0.0: flight.ended = true

func _siege_prism_events(flight: Dictionary, from: Vector3, to: Vector3, begin: float = 0.0, end: float = 1.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var radius := float(flight.get("rule", {}).get("radius_cells", float(SiteCombatRules.BALLISTA.radius) / TerrainRenderer.CELL_PIXELS))
	for key: String in terrain.site.get("features", {}):
		var feature: Dictionary = terrain.site.features[key]
		if str(feature.get("stage", "")) != "complete": continue
		var geometry := SiteRuntime.feature_geometry(terrain, feature)
		for part_id: String in geometry.parts:
			var part: Dictionary = geometry.parts[part_id]
			if float(part.hp) <= 0.0 or str(part.role) == "leaf" and bool(feature.get("gate", {}).get("open", false)): continue
			var base := float(part.get("lower", feature.get("level", 0)))
			var top := float(part.get("upper", maxf(base + 0.5, float(part.height)) if str(part.role) in ["wall", "stairs"] else base + 2.0))
			for value: int in part.cells:
				var cell := terrain.cell_from_index(value)
				var hit := _siege_prism_hit(flight, from, to, begin, end, Rect2(Vector2(cell), Vector2.ONE), base, top)
				if hit.is_empty(): continue
				hit.merge({"flight": flight, "type": "structure", "feature": key, "part": part_id, "material": str(part.get("material", "wood" if str(part.role) == "leaf" else feature.get("material", "wood"))), "stable": "structure:" + key + ":" + part_id})
				result.append(hit)
		if geometry.parts.is_empty():
			for value: int in geometry.blocked:
				var cell := terrain.cell_from_index(value)
				var hit := _siege_prism_hit(flight, from, to, begin, end, Rect2(Vector2(cell), Vector2.ONE), float(feature.get("level", 0)), float(feature.get("level", 0)) + 2.0)
				if not hit.is_empty(): hit.merge({"flight": flight, "type": "blocked", "stable": "blocked:" + key}); result.append(hit)
	for identity: String in terrain.site.get("vehicles", {}):
		if _ship_vehicle_in_journey(identity): continue
		if identity == str(flight.source_vehicle): continue
		var vehicle: Dictionary = terrain.site.vehicles[identity]
		for cell: Vector2i in SiteVehicleTransport.footprint(terrain, vehicle):
			var base := float(terrain.effective_height(cell))
			var hit := _siege_prism_hit(flight, from, to, begin, end, Rect2(Vector2(cell), Vector2.ONE), base, base + 1.0)
			if hit.is_empty(): continue
			hit.merge({"flight": flight, "type": "vehicle", "vehicle": identity, "stable": "vehicle:" + identity})
			result.append(hit)
	var bounds := Rect2(Vector2(from.x, from.y), Vector2.ZERO).expand(Vector2(to.x, to.y)).grow(radius)
	for y in range(maxi(0, floori(bounds.position.y)), mini(terrain.size.y, ceili(bounds.end.y) + 1)):
		for x in range(maxi(0, floori(bounds.position.x)), mini(terrain.size.x, ceili(bounds.end.x) + 1)):
			var cell := Vector2i(x, y)
			var natural_top := float(terrain.height_levels[terrain.index(cell)])
			if terrain.static_blocked[terrain.index(cell)] != 0 and int(terrain.feature_at[terrain.index(cell)]) == 0: natural_top += 2.0
			var hit := _siege_prism_hit(flight, from, to, begin, end, Rect2(Vector2(cell), Vector2.ONE), -1000.0, natural_top)
			if not hit.is_empty(): hit.merge({"flight": flight, "type": "blocked", "stable": "terrain:%d" % terrain.index(cell)}); result.append(hit)
	return result

func _resolve_ranged_fire(people: Array[Dictionary]) -> void:
	if physical_ranged_enabled:
		_resolve_physical_ranged_fire(people)
		return
	var friendly_cells := {}
	var occupancy_read := false
	for person: Dictionary in people:
		var shooter_owner: Variant = person.owner
		var index := int(person.unit)
		var profile: Dictionary = shooter_owner.ranged_profile(index) if index >= 0 else shooter_owner.ranged_profile()
		if profile.is_empty():
			continue # Non-ranged people need no readiness, rout or ammunition query.
		# Pair resolution may have consumed readiness since this disposable list was built.
		if not (shooter_owner.exchange_ready(index) if index >= 0 else shooter_owner.exchange_ready()):
			continue
		if (float(shooter_owner.combat_hot_get(index, &"ranged_cooldown", 0.0)) if index >= 0 else shooter_owner.ranged_cooldown) > 0.0:
			continue
		if index >= 0 and shooter_owner.is_member(index) and not shooter_owner.is_controlled_person(index) and shooter_owner.is_sustain_routed():
			continue # A rout does not become a new automatic ranged attack order.
		var ammunition: Dictionary = shooter_owner.combat_units[index].get("cargo", {}) if index >= 0 else shooter_owner.ammo_inventory
		if int(ammunition.get(str(profile.ammo), 0)) < 1:
			continue # Empty quivers neither scan all targets nor reserve an automatic skill.
		if not occupancy_read:
			friendly_cells = _ranged_friendly_cells()
			occupancy_read = true
		var allies: Dictionary = friendly_cells.get(int(person.faction), {})
		var selected := {}
		var nearest := INF
		var close_threat := false
		for other: Dictionary in people:
			if int(person.faction) == int(other.faction):
				continue
			var separation: Vector2i = other.cell - person.cell
			var distance := Vector2(separation).length_squared()
			# Geometry cannot make an out-of-range person a firing candidate.
			# Keep every adjacent threat, even after finding a nearer legal target.
			if distance > maxf(1.0, float(profile.range) * float(profile.range)):
				continue
			if not (other.owner.combat_can_act(int(other.unit)) if int(other.unit) >= 0 else other.owner.can_act()):
				continue # A melee result in this same decision tick may have incapacitated them.
			if _combat_melee_clear(int(person.id), int(other.id), person.cell, other.cell):
				close_threat = true
				break # A nearby opponent forces close combat even while that opponent cools down.
			if distance <= 1.0 or distance >= nearest:
				continue
			if not _exchange_initiates(person, int(other.id)):
				continue
			if SiteCombatRules.ranged_friendly_clear(person.cell, other.cell, allies, terrain) \
				and _person_ranged_line_clear(int(person.id), person.cell, other.cell):
				selected = other
				nearest = distance
		if close_threat or selected.is_empty():
			continue
		if int(person.id) != controlled_person_id():
			if index >= 0 and shooter_owner.command_abilities.has(index):
				shooter_owner.activate_exchange_skill(index, "power")
			elif index < 0 and not shooter_owner.command_abilities.is_empty():
				shooter_owner.activate_exchange_skill("power")
		var fired: bool = shooter_owner.ranged_fire(index, selected.cell, ranged_shots + 1) if index >= 0 else shooter_owner.ranged_fire(selected.cell, ranged_shots + 1)
		if fired:
			ranged_shots += 1

func _ranged_friendly_cells() -> Dictionary:
	# A disposable projection of the same real ground positions used at impact.
	# Include unconscious friends; reservations are not bodies already at the goal.
	var factions := {}
	for occupants: Array in _ranged_occupants().values():
		for person: Dictionary in occupants:
			var faction: int = person.owner.faction_id
			if not factions.has(faction): factions[faction] = {}
			factions[faction][person.cell] = true
	return factions

func _ranged_tactics(team: TerrainArmy) -> Dictionary:
	var enemies: Array[Dictionary] = []
	for person: Dictionary in _exchange_people(false):
		if int(person.faction) != team.faction_id:
			enemies.append({"id": int(person.id), "cell": person.cell})
	return {"enemies": enemies, "friendly_cells": _ranged_friendly_cells().get(team.faction_id, {})}

func _ranged_occupants() -> Dictionary:
	# Living and unconscious original bodies for fire discipline and arrival, never skeletons.
	# While a legal step is in progress, the nearest rendered ground cell is occupied.
	var occupied := {}
	if crowd_site != null and crowd_site.fire_host_active():
		for person: Dictionary in _siege_people():
			if float(person.get("hp", 0.0)) <= 0.0: continue
			var cell := Vector2i(((person.ground as Vector2) / TerrainRenderer.CELL_PIXELS).floor())
			if not occupied.has(cell): occupied[cell] = []
			occupied[cell].append({"owner": person.owner, "unit": int(person.unit), "id": int(person.id), "cell": cell})
		return occupied
	for occupant_owner: Node2D in _ranged_owners():
		var count: int = occupant_owner.combat_units.size() if occupant_owner is TerrainArmy else 1
		for index in range(count):
			if occupant_owner is TerrainArmy and occupant_owner._ship_in_journey(index): continue
			var exited: bool = bool(occupant_owner.combat_hot_get(index, &"site_exited", false)) if occupant_owner is TerrainArmy else occupant_owner.site_exited
			if exited: continue
			var hp: float = float(occupant_owner.combat_hot_get(index, &"hp")) if occupant_owner is TerrainArmy else occupant_owner.hp
			if hp <= 0.0:
				continue
			var ground: Vector2 = occupant_owner.combat_ground(index) if occupant_owner is TerrainArmy else occupant_owner.position
			var cell := Vector2i((ground / TerrainRenderer.CELL_PIXELS).floor())
			if not occupied.has(cell):
				occupied[cell] = []
			occupied[cell].append({"owner": occupant_owner, "unit": index if occupant_owner is TerrainArmy else -1,
				"id": occupant_owner.combat_identity(index) if occupant_owner is TerrainArmy else occupant_owner.combat_identity(), "cell": cell})
	return occupied

func _advance_ranged(delta: float) -> void:
	if physical_ranged_enabled or not fire_projectiles.is_empty(): _advance_physical_ranged(delta)
	var due: Array[Dictionary] = []
	for projectile_owner: Node2D in _ranged_owners():
		var changed := false
		for index in range(projectile_owner.projectiles.size() - 1, -1, -1):
			var flight: Dictionary = projectile_owner.projectiles[index]
			if str(flight.get("mode", "")) != "cell":
				continue # Historical geometry arrows remain rejected at the load boundary.
			flight.left = maxf(0.0, float(flight.left) - delta)
			flight.position = (flight.origin as Vector2).lerp(flight.goal, 1.0 - float(flight.left) / float(flight.total))
			changed = true
			if float(flight.left) <= ACTION_TIME_EPSILON:
				due.append({"owner": projectile_owner, "flight": flight})
				projectile_owner.projectiles.remove_at(index)
		if changed:
			projectile_owner.queue_redraw()
	if due.is_empty():
		return
	# All shots due in this common step see one occupancy snapshot; no per-shot all-person scan.
	var occupied := _ranged_occupants()
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.flight.shot_id) < int(b.flight.shot_id))
	for arrival: Dictionary in due:
		_resolve_ranged_arrival(arrival.owner, arrival.flight, occupied)

func _resolve_ranged_arrival(shooter_owner: Node2D, flight: Dictionary, occupied: Dictionary) -> void:
	if _region_queue_original_endpoint("legacy_ranged", {"owner": shooter_owner, "flight": flight}): return
	var result := {"kind": "empty", "hp": 0.0, "stun": 0.0, "stagger": 0.0, "knockback": false, "guard_break": false}
	var target := {}
	var source_eye := float(flight.get("source_eye", terrain.effective_height(flight.source_cell) + 1.0))
	var goal_eye := float(flight.get("goal_eye", terrain.effective_height(flight.target_cell) + 1.0))
	for cell: Vector2i in SiteCombatRules.ranged_cells(flight.source_cell, flight.target_cell):
		if not SiteCombatRules.ranged_cell_clear(terrain, flight.source_cell, flight.target_cell, cell, source_eye, goal_eye):
			result.kind = "blocked"
			break
		if not SiteCombatRules.ranged_body_intersects(terrain, flight.source_cell, flight.target_cell, cell, source_eye, goal_eye): continue
		for person: Dictionary in occupied.get(cell, []):
			if int(person.id) != int(flight.shooter_id):
				target = person
				break
		if not target.is_empty(): break
	if not target.is_empty():
		var target_owner: Variant = target.owner
		var index := int(target.unit)
		var defense: Dictionary = target_owner.ranged_defense(index) if index >= 0 else target_owner.ranged_defense()
		defense.facility = SiteRuntime.exchange_facility_bonus(terrain, target.cell) > 0.0
		var noise := (int(flight.shooter_id) * 73856093) ^ (int(flight.shot_id) * 83492791) ^ (int(target.id) * 19349663) ^ terrain.seed_value
		result = SiteCombatRules.ranged_result(flight.shooter, defense, Vector2(flight.target_cell - flight.source_cell).length(), float(posmod(noise, 10000)) / 100.0)
		var shooter_index: int = shooter_owner.index_for_identity(int(flight.shooter_id)) if shooter_owner is TerrainArmy else -1
		var packet := {"attacker": shooter_owner, "attacker_unit": shooter_index, "shield": false, "result": result}
		if index >= 0:
			target_owner.ranged_apply_hit(index, flight.source_cell, packet)
		else:
			target_owner.ranged_apply_hit(flight.source_cell, packet)
	ranged_resolutions += 1
	ranged_results[str(result.kind)] += 1
	ranged_resolved.emit(int(flight.shooter_id), int(target.get("id", 0)), result)

func _exchange_side_outcome(other: Dictionary, result: Dictionary, stats: Dictionary, side: int) -> Dictionary:
	var role := "draw" if int(result.winner) == 0 else "winner" if int(result.winner) == side else "loser"
	var stagger := float(result.hold) if role == "draw" else float(result.stagger) if role == "loser" else 0.0
	if role == "loser" and str(result.kind) == "big" and float(stats.facility) > 0.0:
		stagger = maxf(0.0, stagger - 0.15)
	var hp_field := "hp_a" if side == 1 else "hp_b"
	var stun_field := "stun_a" if side == 1 else "stun_b"
	var received_hp := float(result.get(hp_field, result.hp if role == "loser" else 0.0))
	var received_stun := float(result.get(stun_field, result.stun if role == "loser" else 0.0))
	var outcome := {"role": role, "kind": str(result.kind), "hp": received_hp,
		"stun": received_stun, "stagger": stagger,
		"knockback": role == "loser" and bool(result.knockback), "skill": str(stats.get("skill", "")),
		"fatigue": float(result.fatigue_a if side == 1 else result.fatigue_b),
		"other_identity": int(other.id), "attacker": other.owner, "attacker_unit": int(other.unit)}
	return outcome

func _apply_exchange_side(person: Dictionary, other: Dictionary, result: Dictionary, stats: Dictionary, side: int) -> void:
	# Retain the direct one-to-one entry used by authored visual checks.
	var outcome := _exchange_side_outcome(other, result, stats, side)
	if int(person.unit) >= 0:
		person.owner.apply_exchange(int(person.unit), other.cell, outcome)
	else:
		person.owner.apply_exchange(other.cell, outcome)

func _exchange_reaction_better(candidate: Dictionary, current: Dictionary) -> bool:
	if current.is_empty(): return true
	if bool(candidate.knockback) != bool(current.knockback): return bool(candidate.knockback)
	if int(candidate.rank) != int(current.rank): return int(candidate.rank) > int(current.rank)
	if float(candidate.hp) != float(current.hp): return float(candidate.hp) > float(current.hp)
	if float(candidate.margin) != float(current.margin): return float(candidate.margin) > float(current.margin)
	return int(candidate.other_id) < int(current.other_id)

func _collect_exchange_batch_side(batches: Dictionary, person: Dictionary, other: Dictionary,
		result: Dictionary, stats: Dictionary, side: int) -> void:
	var id := int(person.id)
	var side_outcome := _exchange_side_outcome(other, result, stats, side)
	if not batches.has(id):
		var initial_outcome := side_outcome.duplicate()
		initial_outcome.hp = 0.0
		initial_outcome.stun = 0.0
		initial_outcome.fatigue = 0.0
		initial_outcome.stagger = 0.0
		initial_outcome.knockback = false
		batches[id] = {"person": person, "outcome": initial_outcome, "count": 0,
			"losses": 0, "draws": 0, "big_wins": 0, "big_losses": 0, "reaction": {}}
	var entry: Dictionary = batches[id]
	var total: Dictionary = entry.outcome
	entry.count += 1
	total.hp += float(side_outcome.hp)
	total.stun += float(side_outcome.stun)
	total.fatigue += float(side_outcome.fatigue)
	total.stagger = maxf(float(total.stagger), float(side_outcome.stagger))
	total.knockback = bool(total.knockback) or bool(side_outcome.knockback)
	match str(side_outcome.role):
		"loser":
			entry.losses += 1
			if str(side_outcome.kind) == "big": entry.big_losses += 1
		"draw": entry.draws += 1
		"winner":
			if str(side_outcome.kind) == "big": entry.big_wins += 1
	var candidate := {"knockback": bool(side_outcome.knockback),
		"rank": 2 if str(side_outcome.role) == "loser" else 1 if str(side_outcome.role) == "draw" else 0,
		"hp": float(side_outcome.hp), "margin": absf(float(result.margin)),
		"other_id": int(other.id), "other_cell": other.cell,
		"attacker": other.owner, "attacker_unit": int(other.unit)}
	if _exchange_reaction_better(candidate, entry.reaction): entry.reaction = candidate

func _exchange_batch_person_matches(person: Dictionary) -> bool:
	if not is_instance_valid(person.owner): return false
	var index := int(person.unit)
	if index < 0:
		return person.owner is TerrainTestCharacter and int(person.owner.person_id) == int(person.id)
	return person.owner is TerrainArmy and index < person.owner.combat_units.size() \
		and int(person.owner.combat_identity(index)) == int(person.id)

func _exchange_batch_outcome_valid(outcome: Dictionary) -> bool:
	if str(outcome.get("role", "")) not in ["winner", "loser", "draw"]: return false
	for field: String in ["hp", "stun", "fatigue", "stagger"]:
		var value: Variant = outcome.get(field)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0:
			return false
	return true

func _exchange_batch_phase_current(entry: Dictionary, phase: String) -> bool:
	if _exchange_batch_person_matches(entry.person): return true
	push_error("Exchange batch " + phase + " lost the original person")
	return false

func _settle_exchange_batch(pending: Array[Dictionary]) -> bool:
	if pending.is_empty(): return true
	if _region_queue_original_endpoint("exchange_batch", {"batch": pending.duplicate(true)}): return true
	var batches := {}
	for pair: Dictionary in pending:
		_collect_exchange_batch_side(batches, pair.a, pair.b, pair.result, pair.stats_a, 1)
		_collect_exchange_batch_side(batches, pair.b, pair.a, pair.result, pair.stats_b, -1)
	var identities: Array = batches.keys()
	identities.sort()
	# Preflight the complete call-local batch before charging or moving anyone.
	for id: Variant in identities:
		var entry: Dictionary = batches[id]
		var total: Dictionary = entry.outcome
		var reaction: Dictionary = entry.reaction
		var all_won := int(entry.losses) == 0 and int(entry.draws) == 0
		total.role = "winner" if all_won else "draw" if int(entry.count) == 1 and int(entry.draws) == 1 else "loser"
		total.kind = "big" if (all_won and int(entry.big_wins) > 0) or (not all_won and int(entry.big_losses) > 0) \
			else "draw" if int(entry.losses) == 0 and int(entry.draws) > 0 else "small"
		total.other_identity = int(reaction.other_id)
		total.attacker = reaction.attacker
		total.attacker_unit = int(reaction.attacker_unit)
		entry.other_cell = reaction.other_cell
		if not _exchange_batch_person_matches(entry.person) or not _exchange_batch_outcome_valid(total):
			push_error("Exchange batch participant changed or aggregate effect is invalid")
			return false
	# Costs and skills use pre-death shared-pool membership. No contact occurs
	# until every owner has prepared, and no final pose is chosen until all life
	# effects are committed.
	for id: Variant in identities:
		var entry: Dictionary = batches[id]
		if not _exchange_batch_phase_current(entry, "prepare"): return false
		entry.prepared = entry.person.owner.exchange_batch_prepare(int(entry.person.unit), entry.other_cell, entry.outcome) \
			if int(entry.person.unit) >= 0 else entry.person.owner.exchange_batch_prepare(entry.other_cell, entry.outcome)
		if (entry.prepared as Dictionary).is_empty():
			push_error("Exchange batch owner rejected a preflighted participant")
			return false
	for id: Variant in identities:
		var entry: Dictionary = batches[id]
		if not _exchange_batch_phase_current(entry, "knockback"): return false
		if int(entry.person.unit) >= 0:
			entry.person.owner.exchange_batch_knockback(int(entry.person.unit), entry.other_cell, entry.outcome, entry.prepared)
		else:
			entry.person.owner.exchange_batch_knockback(entry.other_cell, entry.outcome, entry.prepared)
	for id: Variant in identities:
		var entry: Dictionary = batches[id]
		if not _exchange_batch_phase_current(entry, "contact"): return false
		if int(entry.person.unit) >= 0:
			entry.person.owner.exchange_batch_contact(int(entry.person.unit), entry.outcome)
		else:
			entry.person.owner.exchange_batch_contact(entry.outcome)
	for id: Variant in identities:
		var entry: Dictionary = batches[id]
		if not _exchange_batch_phase_current(entry, "finish"): return false
		if int(entry.person.unit) >= 0:
			entry.person.owner.exchange_batch_finish(int(entry.person.unit), entry.other_cell, entry.outcome, entry.prepared)
		else:
			entry.person.owner.exchange_batch_finish(entry.other_cell, entry.outcome, entry.prepared)
	return true

func _resolve_combat_contacts() -> void:
	_combat_contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.fraction) < float(b.fraction))
	var cursor := 0
	while cursor < _combat_contacts.size():
		var group_end := cursor + 1
		while group_end < _combat_contacts.size() and is_equal_approx(float(_combat_contacts[group_end].fraction), float(_combat_contacts[cursor].fraction)):
			group_end += 1
		_advance_gd_mesh_work_to(float(_combat_contacts[cursor].fraction))
		var eligible := {}
		for index in range(cursor, group_end):
			var packet: Dictionary = _combat_contacts[index]
			var attacker: Variant = packet.attacker
			if is_instance_valid(attacker):
				var unit := int(packet.get("attacker_unit", -1))
				var identity := "%d:%d" % [attacker.get_instance_id(), unit]
				eligible[identity] = attacker.combat_can_act(unit) if attacker is TerrainArmy else attacker.can_act()
		var previous_consuming: bool = _region_point_consuming
		if not _gd_mesh_work_point.is_empty(): _region_point_consuming = true
		for index in range(cursor, group_end):
			var packet: Dictionary = _combat_contacts[index]
			var attacker: Variant = packet.attacker
			var identity := "%d:%d" % [attacker.get_instance_id(), int(packet.get("attacker_unit", -1))] if is_instance_valid(attacker) else ""
			var may_hit := bool(packet.get("ranged", false)) or bool(eligible.get(identity, false))
			var victim: Variant = packet.target
			if may_hit and is_instance_valid(victim):
				if victim is TerrainArmy:
					victim.apply_unit_contact(int(packet.target_unit), packet)
				else:
					victim.apply_contact(packet)
		if not _gd_mesh_work_point.is_empty():
			site_controller.settle_gd_mesh_supply_contact(_gd_mesh_work_point.supply)
		_region_point_consuming = previous_consuming
		cursor = group_end

func has_combat_armies() -> bool:
	for team: TerrainArmy in combat_armies:
		if team.combat_enabled:
			return true
	return false

func _original_actor_training(actor: TerrainTestCharacter) -> float:
	for team: TerrainArmy in combat_armies:
		if team.combat_enabled and team.player_member == actor:
			return team.training
	return actor.training

func player_army() -> TerrainArmy:
	for team: TerrainArmy in combat_armies:
		if controlled_member_index(team) >= 0:
			return team
	return null

func join_player_army() -> Dictionary:
	if player_army() != null:
		return SiteRuntime.fail("BUSY", "已加入隊伍，不能重複入隊")
	if is_inside_tree() and get_tree().paused:
		return SiteRuntime.fail("BUSY", "暫停時不處理入隊")
	var person := controlled_target()
	if person.is_empty():
		return SiteRuntime.fail("NO_TARGET", "原人物不存在")
	if int(person.unit) >= 0:
		return person.owner.join_row(controlled_person_id())
	return army.join_player(person.owner)

func leave_player_army() -> Dictionary:
	var team := player_army()
	var person := controlled_target()
	if team == null or person.is_empty():
		return SiteRuntime.fail("NO_TARGET", "本人目前沒有隊伍")
	if int(person.unit) >= 0:
		return team.leave_row(controlled_person_id())
	if team.player_member != person.owner:
		return SiteRuntime.fail("NO_AUTHORITY", "不能替另一個原人物退出")
	if not person.owner.can_act() or person.owner.is_moving() or person.owner.action_time > 0.0:
		return SiteRuntime.fail("BUSY", "本人須清醒自由且完成原動作")
	return team.leave_player()

func issue_player_army_order(order_id: int, goal: Vector2i = Vector2i(-1, -1), target_id: int = -1, final_facing: Vector2i = Vector2i.ZERO, preset_id: String = "") -> Dictionary:
	if _ship_person_in_journey(controlled_person_id()): return SiteRuntime.fail("BUSY", "旅程中的原人物不能下現場地面軍令")
	var team := player_army()
	if team == null:
		return SiteRuntime.fail("NO_AUTHORITY", "尚未加入隊伍")
	return team.issue_combat_order(controlled_member_index(team), order_id, goal, target_id, final_facing, preset_id)

func issue_player_corps_reposition(target_team_id: int, goal: Vector2i) -> Dictionary:
	if _ship_person_in_journey(controlled_person_id()): return SiteRuntime.fail("BUSY", "旅程中的原人物不能下現場地面軍令")
	for team: TerrainArmy in combat_armies:
		if team.team_id == target_team_id:
			return team.issue_corps_reposition(controlled_person_id(), goal)
	return SiteRuntime.fail("NO_TARGET", "指定隊伍不在目前地圖")

func _forget_corps_team(team_id: int) -> void:
	if terrain == null or not terrain.site.get("corps", {}) is Dictionary:
		return
	var corps: Dictionary = terrain.site.get("corps", {}).duplicate(true)
	for key: String in corps.keys():
		corps[key].team_ids.erase(team_id)
		if corps[key].team_ids.is_empty():
			corps.erase(key)
	terrain.site["corps"] = corps

func issue_player_formation_change(preset_id: String) -> Dictionary:
	if _ship_person_in_journey(controlled_person_id()): return SiteRuntime.fail("BUSY", "旅程中的原人物不能下現場地面軍令")
	var team := player_army()
	if team == null:
		return SiteRuntime.fail("NO_AUTHORITY", "尚未加入隊伍")
	return team.issue_formation_change(controlled_member_index(team), preset_id)

func split_selected_soldier() -> Dictionary:
	var source := player_army()
	var selected := _combat_target(selected_army_target)
	if source == null or selected.is_empty() or selected.owner != source or int(selected.unit) < 0:
		return SiteRuntime.fail("NO_AUTHORITY", "須選中自己隊伍的 NPC，並由當前合格指揮者下令")
	var identities: Array[int] = [selected_army_target]
	return transfer_player_roster(identities)

func transfer_player_roster(identities: Array[int], merge_all: bool = false, receiver_confirmation: Dictionary = {}) -> Dictionary:
	var source := player_army()
	if source == null or source.current_commander != controlled_member_index(source) or not source.command_eligible(controlled_member_index(source)):
		return SiteRuntime.fail("NO_AUTHORITY", "須由本隊當前合格指揮者本人提出")
	var recipient: TerrainArmy
	for team: TerrainArmy in combat_armies:
		if team == source:
			continue
		if not receiver_confirmation.is_empty():
			if team.team_id == int(receiver_confirmation.get("team_id", -1)):
				recipient = team
				break
		elif not merge_all and not team.has_army():
			recipient = team
			break
		elif team.has_army() and team.faction_id == source.faction_id:
			if recipient != null:
				return SiteRuntime.fail("NO_TARGET", "有多個接收隊，請明確選擇本次對象")
			recipient = team
	if recipient == null:
		return SiteRuntime.fail("NO_SPACE", "目前保留三隊保存上限；沒有可用隊伍槽，不會清除另一隊")
	if recipient.has_army():
		if not receiver_confirmation.has("commander_id"):
			return SiteRuntime.fail("NO_AUTHORITY", "既有接收隊還須由現任合格指揮者確認；玩家不代獲對方指揮權")
		var member_ids: Array[int] = []
		for index: int in source.command_members():
			member_ids.append(source.combat_identity(index))
		var recipient_roster := recipient.index_for_identity(recipient.duty_decider("team.roster"))
		if int(receiver_confirmation.get("team_id", -1)) != recipient.team_id or int(receiver_confirmation.get("commander_id", -1)) != recipient.duty_decider("team.roster") or int(receiver_confirmation.get("source_team_id", -1)) != source.team_id or int(receiver_confirmation.get("source_commander_id", -1)) != controlled_person_id() or receiver_confirmation.get("member_ids", []) != member_ids or not merge_all and receiver_confirmation.get("selected_ids", []) != identities:
			return SiteRuntime.fail("STALE", "原接收指揮者或本次名冊已變更，須重新確認")
		if merge_all:
			var merge_result := source.merge_into(recipient, controlled_member_index(source), recipient_roster)
			if bool(merge_result.get("ok", false)) and not source.has_army():
				_forget_corps_team(source.team_id)
			return merge_result
		return source.transfer_members_to(recipient, identities, controlled_member_index(source), recipient_roster)
	if merge_all:
		return SiteRuntime.fail("NO_TARGET", "合併須有既有接收隊；空隊槽請用拆分")
	var next_team := _next_army_identity()
	if next_team >= 999999:
		return SiteRuntime.fail("ID_EXHAUSTED")
	var previous_team := recipient.team_id
	var previous_faction := recipient.faction_id
	recipient.team_id = next_team
	recipient.faction_id = source.faction_id
	recipient.data = terrain
	var result := source.split_members_to(recipient, identities, controlled_member_index(source))
	if result.ok:
		terrain.site["army_next_team"] = next_team + 1
		_configure_army_blockers()
	else:
		recipient.team_id = previous_team
		recipient.faction_id = previous_faction
	return result

func _melee_trial_formation(anchor: Vector2i, count: int, friendly: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var behind := Vector2i.LEFT if friendly else Vector2i.RIGHT
	for depth in range(ceili(float(count) / 10.0)):
		for row in range(10):
			if cells.size() == count:
				return cells
			cells.append(anchor + behind * depth + Vector2i.DOWN * row)
	return cells

func _melee_trial_formation_legal(cells: Array[Vector2i], claimed: Dictionary) -> bool:
	if cells.is_empty():
		return false
	var local := {}
	for cell: Vector2i in cells:
		if not terrain.is_walkable(cell) or claimed.has(cell) or local.has(cell) \
			or character.occupies_cell(cell) or (is_instance_valid(npc) and npc.occupies_cell(cell)) \
			or site_controller != null and site_controller.vehicles.blocks_cell(cell):
			return false
		local[cell] = true
	var reached := {cells[0]: true}
	var pending: Array[Vector2i] = [cells[0]]
	while not pending.is_empty():
		var current: Vector2i = pending.pop_front()
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if local.has(next) and not reached.has(next) and terrain.can_step(current, next):
				reached[next] = true
				pending.append(next)
	return reached.size() == cells.size()

func _melee_trial_layout_legal(friendly: Array[Vector2i], enemy: Array[Vector2i]) -> bool:
	if not _melee_trial_formation_legal(friendly, {}):
		return false
	var claimed := {}
	for cell: Vector2i in friendly:
		claimed[cell] = true
	return _melee_trial_formation_legal(enemy, claimed)

func _melee_trial_front_legal(friendly: Array[Vector2i], enemy: Array[Vector2i], ranged_range: float = 0.0) -> bool:
	var shared_front := mini(10, mini(friendly.size(), enemy.size()))
	if shared_front <= 0:
		return false
	for row in range(shared_front):
		if ranged_range > 0.0:
			if not _trial_ranged_front_reachable(friendly[row], enemy[row], ranged_range):
				return false
		elif not terrain.can_step(friendly[row], enemy[row]):
			return false
	return true

func _trial_ranged_front_reachable(source: Vector2i, target: Vector2i, maximum_range: float) -> bool:
	if SiteCombatRules.ranged_in_range(source, target, maximum_range) and SiteCombatRules.ranged_line_clear(terrain, source, target):
		return true
	if absi(target.x - source.x) + absi(target.y - source.y) > 20:
		return false
	# Deployment validation only: the original map path query checks a local
	# approach when manually placing fronts beyond firing range or behind cover.
	var route := terrain.path_between(source, target, func(cell: Vector2i) -> bool:
		return (absi(cell.x - source.x) + absi(cell.y - source.y) > 20 or character.occupies_cell(cell) or (is_instance_valid(npc) and npc.occupies_cell(cell))
			or site_controller != null and site_controller.vehicles.blocks_cell(cell)))
	return not route.is_empty() and route.size() <= 20

func _third_trial_formation(anchor: Vector2i, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for index in range(count):
		cells.append(anchor + Vector2i(index % 10, -floori(float(index) / 10.0)))
	return cells

func _trial_front_touches(cells: Array[Vector2i], others: Dictionary, ranged_range: float = 0.0) -> bool:
	for cell: Vector2i in cells:
		if ranged_range > 0.0:
			for other: Vector2i in others:
				if _trial_ranged_front_reachable(cell, other, ranged_range):
					return true
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			if others.has(cell + direction) and terrain.can_step(cell, cell + direction):
				return true
	return false

func _third_trial_layout(cells: Array[Vector2i], friendly: Array[Vector2i], enemy: Array[Vector2i], ranged_range: float = 0.0) -> bool:
	var claimed := {}
	for cell: Vector2i in friendly + enemy:
		claimed[cell] = true
	return _melee_trial_formation_legal(cells, claimed) and _trial_front_touches(cells, claimed, ranged_range)

func _trial_connected_formation(seed_cell: Vector2i, count: int, claimed: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if claimed.has(seed_cell) or not terrain.is_walkable(seed_cell) or character.occupies_cell(seed_cell) or (is_instance_valid(npc) and npc.occupies_cell(seed_cell)) or site_controller != null and site_controller.vehicles.blocks_cell(seed_cell):
		return cells
	cells.append(seed_cell)
	var seen := {seed_cell: true}
	var cursor := 0
	while cursor < cells.size() and cells.size() < count:
		var current := cells[cursor]
		cursor += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if seen.has(next) or claimed.has(next) or not terrain.can_step(current, next) or character.occupies_cell(next) or (is_instance_valid(npc) and npc.occupies_cell(next)) or site_controller != null and site_controller.vehicles.blocks_cell(next):
				continue
			seen[next] = true
			cells.append(next)
			if cells.size() == count:
				break
	if cells.size() != count:
		cells.clear()
	return cells

func _auto_third_trial_formation(count: int, friendly: Array[Vector2i], enemy: Array[Vector2i], ranged_range: float = 0.0) -> Array[Vector2i]:
	var gap := 6 if ranged_range > 0.0 else 1
	var compact := _third_trial_formation(friendly[0] + Vector2i(-mini(4, count - 1), -gap), count)
	if _third_trial_layout(compact, friendly, enemy, ranged_range):
		return compact
	var claimed := {}
	var friendly_claims := {}
	var enemy_claims := {}
	for cell: Vector2i in friendly:
		claimed[cell] = true
		friendly_claims[cell] = true
	for cell: Vector2i in enemy:
		claimed[cell] = true
		enemy_claims[cell] = true
	var tried := {}
	# Auto placement may follow a plateau edge rather than require a new 20x20 flat block.
	# The original two fronts remain intact; this one deployment BFS owns no runtime paths.
	for front: Vector2i in friendly + enemy:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var seed_cell := front + direction * gap
			if claimed.has(seed_cell) or tried.has(seed_cell):
				continue
			tried[seed_cell] = true
			var cells := _trial_connected_formation(seed_cell, count, claimed)
			if cells.is_empty():
				continue
			if count > 1 and (not _trial_front_touches(cells, friendly_claims, ranged_range) or not _trial_front_touches(cells, enemy_claims, ranged_range)):
				continue
			return cells
	return []

static func _normalize_direction(val: Variant) -> String:
	var s := str(val).strip_edges().to_lower()
	if s in ["0", "east", "東", "東方"]:
		return "east"
	elif s in ["1", "south", "南", "南方"]:
		return "south"
	elif s in ["2", "west", "西", "西方"]:
		return "west"
	elif s in ["3", "north", "北", "北方"]:
		return "north"
	return ""

func _vertical_melee_trial_formation(anchor: Vector2i, count: int, top_side: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var behind := Vector2i.UP if top_side else Vector2i.DOWN
	for depth in range(ceili(float(count) / 10.0)):
		for col in range(10):
			if cells.size() == count:
				return cells
			cells.append(anchor + behind * depth + Vector2i.RIGHT * col)
	return cells

func _vertical_melee_trial_front_legal(top_team: Array[Vector2i], bottom_team: Array[Vector2i], ranged_range: float = 0.0) -> bool:
	var shared_front := mini(10, mini(top_team.size(), bottom_team.size()))
	if shared_front <= 0:
		return false
	for col in range(shared_front):
		if ranged_range > 0.0:
			if not _trial_ranged_front_reachable(top_team[col], bottom_team[col], ranged_range):
				return false
		elif not terrain.can_step(top_team[col], bottom_team[col]):
			return false
	return true

func _directional_third_trial_formation(count: int, friendly: Array[Vector2i], enemy: Array[Vector2i], t_dir: String, ranged_range: float = 0.0) -> Array[Vector2i]:
	if count <= 0:
		return []
	var gap := 6 if ranged_range > 0.0 else 1
	var claimed := {}
	var friendly_claims := {}
	var enemy_claims := {}
	for cell: Vector2i in friendly:
		claimed[cell] = true
		friendly_claims[cell] = true
	for cell: Vector2i in enemy:
		claimed[cell] = true
		enemy_claims[cell] = true

	var candidates: Array[Vector2i] = []
	for front: Vector2i in friendly + enemy:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var seed_cell := front + direction * gap
			if not claimed.has(seed_cell) and not candidates.has(seed_cell) and terrain.is_walkable(seed_cell):
				candidates.append(seed_cell)

	match t_dir:
		"north":
			candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
		"south":
			candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y if a.y != b.y else a.x < b.x)
		"west":
			candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x if a.x != b.x else a.y < b.y)
		"east":
			candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x > b.x if a.x != b.x else a.y < b.y)

	for seed_cell in candidates:
		var compact := _third_trial_formation(seed_cell, count)
		if _third_trial_layout(compact, friendly, enemy, ranged_range):
			return compact
		var cells := _trial_connected_formation(seed_cell, count, claimed)
		if not cells.is_empty():
			if count > 1 and (not _trial_front_touches(cells, friendly_claims, ranged_range) or not _trial_front_touches(cells, enemy_claims, ranged_range)):
				continue
			return cells

	return _auto_third_trial_formation(count, friendly, enemy, ranged_range)

func _find_directional_team_formation(dir: String, count: int, claimed: Dictionary, anchor_target: Vector2i = Vector2i(-1, -1)) -> Array[Vector2i]:
	if terrain == null or count <= 0 or dir not in ["west", "east", "north", "south"]:
		return []
	var unavailable := claimed.duplicate()
	for team: TerrainArmy in combat_armies:
		unavailable.merge(team._cell_owners)
		unavailable.merge(team._reserved_cells)
	if combat_movement_coordinator != null:
		for cell: Vector2i in combat_movement_coordinator.deployment_registry.slot_owners:
			unavailable[cell] = true
	var vertical_edge := dir in ["west", "east"]
	var edge_length := terrain.size.y if vertical_edge else terrain.size.x
	var depth_length := terrain.size.x if vertical_edge else terrain.size.y
	var middle := (edge_length - 1) >> 1
	# The chosen entry is a district extending inward, not only its 100 edge
	# cells. Fifty teams cannot each own a distinct edge cell on this Site.
	for depth in range(depth_length):
		for order in range(edge_length):
			var offset := middle - (order >> 1) if order % 2 == 0 else middle + ((order + 1) >> 1)
			var seed_cell := Vector2i(depth if dir == "west" else terrain.size.x - 1 - depth, offset) if vertical_edge \
				else Vector2i(offset, depth if dir == "north" else terrain.size.y - 1 - depth)
			if unavailable.has(seed_cell) or not terrain.is_walkable(seed_cell):
				continue
			if anchor_target != TerrainArmy.INVALID_CELL and terrain.path_between(seed_cell, anchor_target).is_empty():
				continue
			var cells := _trial_connected_formation(seed_cell, count, unavailable)
			if cells.size() == count:
				return cells
	return []

func find_melee_trial_layout(friendly_count: int, enemy_count: int, friendly_spawn: Vector2i = TerrainArmy.INVALID_CELL, enemy_spawn: Vector2i = TerrainArmy.INVALID_CELL, third_count: int = 0, third_spawn: Vector2i = TerrainArmy.INVALID_CELL, ranged_range: float = 0.0, third_ranged_range: float = 0.0, entry_direction: String = "", friendly_entry: String = "", enemy_entry: String = "", third_entry: String = "") -> Dictionary:
	if terrain == null or friendly_count < 1 or friendly_count > 100 or enemy_count < 1 or enemy_count > 100:
		return {}
	if third_count < 0 or third_count > 100:
		return {}
	var custom := friendly_spawn != TerrainArmy.INVALID_CELL and enemy_spawn != TerrainArmy.INVALID_CELL
	if custom:
		var friendly_custom := _melee_trial_formation(friendly_spawn, friendly_count, true)
		var enemy_custom := _melee_trial_formation(enemy_spawn, enemy_count, false)
		if not _melee_trial_layout_legal(friendly_custom, enemy_custom) or not _melee_trial_front_legal(friendly_custom, enemy_custom, ranged_range):
			return {}
		var custom_layout := {"friendly": friendly_custom, "enemy": enemy_custom}
		if third_count > 0:
			if third_spawn == TerrainArmy.INVALID_CELL:
				return {}
			var third_custom := _third_trial_formation(third_spawn, third_count)
			if not _third_trial_layout(third_custom, friendly_custom, enemy_custom, third_ranged_range):
				return {}
			custom_layout.third = third_custom
		return custom_layout
	if friendly_spawn != TerrainArmy.INVALID_CELL or enemy_spawn != TerrainArmy.INVALID_CELL or third_spawn != TerrainArmy.INVALID_CELL:
		return {}

	var f_dir := _normalize_direction(friendly_entry)
	var e_dir := _normalize_direction(enemy_entry)
	var t_dir := _normalize_direction(third_entry)
	for value: String in [friendly_entry, enemy_entry, third_entry, entry_direction]:
		if not value.strip_edges().is_empty() and _normalize_direction(value).is_empty():
			return {}
	if f_dir == "" and e_dir == "":
		var legacy_dir := _normalize_direction(entry_direction)
		if legacy_dir != "":
			f_dir = "west" if legacy_dir in ["east", "south"] else "east"
			e_dir = legacy_dir
			if t_dir.is_empty():
				t_dir = "north" if legacy_dir in ["east", "west"] else "east"

	# If no direction specified at all, retain original legacy adjacent-front search contract
	if f_dir == "" and e_dir == "" and t_dir == "":
		var friendly_depth := ceili(float(friendly_count) / 10.0)
		var enemy_depth := ceili(float(enemy_count) / 10.0)
		var gap := 6 if ranged_range > 0.0 else 1
		var height := mini(10, maxi(friendly_count, enemy_count))
		for y in range(1, terrain.size.y - height):
			for x in range(1, terrain.size.x - friendly_depth - enemy_depth - gap + 1):
				var origin := Vector2i(x, y)
				var friendly_auto := _melee_trial_formation(origin + Vector2i(friendly_depth - 1, 0), friendly_count, true)
				var enemy_auto := _melee_trial_formation(origin + Vector2i(friendly_depth + gap - 1, 0), enemy_count, false)
				if _melee_trial_layout_legal(friendly_auto, enemy_auto) and _melee_trial_front_legal(friendly_auto, enemy_auto, ranged_range):
					var auto_layout := {"friendly": friendly_auto, "enemy": enemy_auto}
					if third_count > 0:
						var third_auto := _auto_third_trial_formation(third_count, friendly_auto, enemy_auto, third_ranged_range)
						if third_auto.is_empty():
							continue
						auto_layout.third = third_auto
					return auto_layout
		return {}

	# Directional independent deployment from designated entry edges
	f_dir = "west" if f_dir.is_empty() else f_dir
	e_dir = "east" if e_dir.is_empty() else e_dir
	t_dir = "north" if t_dir.is_empty() else t_dir
	var friendly_cells := _find_directional_team_formation(f_dir, friendly_count, {})
	if friendly_cells.size() != friendly_count:
		return {}

	var claimed := {}
	for c: Vector2i in friendly_cells:
		claimed[c] = true

	var f_center: Vector2i = friendly_cells[0]
	var enemy_cells := _find_directional_team_formation(e_dir, enemy_count, claimed, f_center)
	if enemy_cells.size() != enemy_count:
		return {}

	for c: Vector2i in enemy_cells:
		claimed[c] = true

	var result := {"friendly": friendly_cells, "enemy": enemy_cells}

	if third_count > 0:
		var third_cells := _find_directional_team_formation(t_dir, third_count, claimed, friendly_cells[0])
		if third_cells.size() != third_count:
			return {}
		result.third = third_cells

	return result

func _trial_camp_access() -> Array[Vector2i]:
	var camp := terrain.cell_from_index(int(terrain.site.depot_cell))
	var cells: Array[Vector2i] = [camp]
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if terrain.can_step(camp + direction, camp):
			cells.append(camp + direction)
	return cells

func _independent_trial_formations(sides: Array[Dictionary]) -> Array:
	# Support teams use the same original rows and terrain, but not a forced enemy front.
	_trial_formation_failure.clear()
	var claimed := {}
	var placed: Array[Dictionary] = []
	var camp_access := _trial_camp_access()
	# Auto support spawns must leave usable depot approaches, not merely an
	# unoccupied person spawn. Explicit positions remain the player's choice.
	placed.append({"faction": character.faction_id, "cells": camp_access})
	for team: TerrainArmy in combat_armies:
		claimed.merge(team._cell_owners)
		claimed.merge(team._reserved_cells)
		if team.has_army():
			placed.append({"faction": team.faction_id, "cells": team.cells})
	for actor: TerrainTestCharacter in combat_actors:
		if actor.can_act():
			placed.append({"faction": actor.faction_id, "cells": [actor.terrain_cell]})
	var formations: Array = []
	formations.resize(sides.size())
	# Reserve all explicit positions first so an earlier automatic team cannot steal them.
	for index in range(sides.size()):
		var side: Dictionary = sides[index]
		if side.spawn == TerrainArmy.INVALID_CELL:
			continue
		var cells := _third_trial_formation(side.spawn, side.count) if side.prefix == "third" else _melee_trial_formation(side.spawn, side.count, side.prefix == "friendly")
		if not _melee_trial_formation_legal(cells, claimed):
			_trial_formation_failure = {"team": index + 1, "reason": "explicit position invalid"}
			return []
		formations[index] = cells
		for cell: Vector2i in cells:
			claimed[cell] = true
		placed.append({"faction": side.faction, "cells": cells})
	for index in range(sides.size()):
		if formations[index] != null:
			continue
		var side: Dictionary = sides[index]
		var unavailable := claimed.duplicate()
		for cell: Vector2i in camp_access:
			unavailable[cell] = true
		for other: Dictionary in placed:
			if int(other.faction) == int(side.faction):
				continue
			for cell: Vector2i in other.cells:
				for dx in range(-8, 9):
					for dy in range(-8 + absi(dx), 9 - absi(dx)):
						unavailable[cell + Vector2i(dx, dy)] = true
		var found: Array[Vector2i] = []
		if not str(side.get("entry", "")).is_empty():
			found = _find_directional_team_formation(side.entry, side.count, unavailable)
		else:
			var origins: Array[Vector2i] = []
			# Unspecified legacy support spawns still prefer the original camp area.
			for y in range(terrain.size.y):
				for x in range(terrain.size.x):
					var cell := Vector2i(x, y)
					if not unavailable.has(cell) and terrain.is_walkable(cell):
						origins.append(cell)
			var camp := terrain.cell_from_index(int(terrain.site.depot_cell))
			origins.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				var distance_a := absi(a.x - camp.x) + absi(a.y - camp.y)
				var distance_b := absi(b.x - camp.x) + absi(b.y - camp.y)
				return distance_a < distance_b if distance_a != distance_b else terrain.index(a) < terrain.index(b))
			for origin: Vector2i in origins:
				found = _trial_connected_formation(origin, side.count, unavailable)
				if not found.is_empty():
					break
		if found.is_empty():
			var free_cells := 0
			for y in range(terrain.size.y):
				for x in range(terrain.size.x):
					var cell := Vector2i(x, y)
					if not unavailable.has(cell) and terrain.is_walkable(cell):
						free_cells += 1
			_trial_formation_failure = {"team": index + 1, "faction": side.faction,
				"free_cells": free_cells, "required_cells": side.count, "entry": side.entry}
			return []
		formations[index] = found
		for cell: Vector2i in found:
			claimed[cell] = true
		placed.append({"faction": side.faction, "cells": found})
	return formations

func deploy_trial_armies(setups: Array[Dictionary]) -> Dictionary:
	var journey_guard := _ship_journey_guard()
	if not journey_guard.ok: return journey_guard
	if setups.is_empty() or setups.size() > SiteStore.MAX_ARMIES:
		return SiteRuntime.fail("INVALID", "隊伍數須在 1 至 %d 隊之間" % SiteStore.MAX_ARMIES)
	for team: TerrainArmy in combat_armies:
		if team.has_army() and not (crowd_site != null and not crowd_site.active):
			return SiteRuntime.fail("BUSY", "請先清除現有隊伍；原人物未修改")
	var sides: Array[Dictionary] = []
	for setup: Dictionary in setups:
		var normalized := {"third_faction": setup.get("faction", -1)}
		for field: String in ["count", "role", "troop_type", "entry", "cart_count", "wagon_count", "female_percent", "training", "tactics", "leadership", "coach", "attack", "ai_enabled", "spawn"]:
			if setup.has(field):
				normalized["third_" + field] = setup[field]
		var parsed := _trial_side_settings(normalized, "third")
		if not parsed.ok:
			return parsed
		sides.append(parsed.side)
	var formations := _independent_trial_formations(sides)
	if formations.size() != sides.size():
		return SiteRuntime.fail("NO_SPACE", "沒有足夠合法格位容納全部隊伍（%s）；原人物與地形未修改" % str(_trial_formation_failure))
	return _deploy_trial_teams(sides, formations, 0)

func start_melee_trial(setup: Dictionary = {}) -> Dictionary:
	var journey_guard := _ship_journey_guard()
	if not journey_guard.ok: return journey_guard
	for team: TerrainArmy in combat_armies:
		if team.has_army() and not (crowd_site != null and not crowd_site.active):
			return SiteRuntime.fail("BUSY", "請先清除現有測試隊伍；不會搬動既有人物")
	var third_enabled: Variant = setup.get("third_enabled", false)
	if not third_enabled is bool:
		return SiteRuntime.fail("INVALID", "第三隊選項須為開啟或關閉")
	var sides: Array[Dictionary] = []
	for prefix: String in (["friendly", "enemy", "third"] if third_enabled else ["friendly", "enemy"]):
		var parsed := _trial_side_settings(setup, prefix)
		if not parsed.ok:
			return parsed
		sides.append(parsed.side)
	var has_support := false
	for side: Dictionary in sides:
		has_support = has_support or side.role != "combat"
	if has_support:
		var support_formations := _independent_trial_formations(sides)
		if support_formations.is_empty():
			return SiteRuntime.fail("NO_SPACE", "找不到合法的獨立隊伍位置；工作／後勤自動位置須避開敵軍八格，未改地形或既有人物")
		return _deploy_trial_teams(sides, support_formations, 0)
	for side: Dictionary in sides:
		if (side.spawn == TerrainArmy.INVALID_CELL) != (sides[0].spawn == TerrainArmy.INVALID_CELL):
			return SiteRuntime.fail("INVALID", "請同時設定所有啟用隊伍的位置，或讓所有隊伍自動尋找")
	# Only deploy on existing legal ground. Never flatten terrain or delete props.
	var ranged_range := maxf(_trial_ranged_range(sides[0]), _trial_ranged_range(sides[1]))
	var entry_dir: String = str(setup.get("entry_direction", ""))
	var f_entry: String = sides[0].entry
	var e_entry: String = sides[1].entry
	var t_entry: String = sides[2].entry if third_enabled else ""
	var layout := find_melee_trial_layout(sides[0].count, sides[1].count, sides[0].spawn, sides[1].spawn,
		sides[2].count if third_enabled else 0, sides[2].spawn if third_enabled else TerrainArmy.INVALID_CELL,
		ranged_range, _trial_ranged_range(sides[2]) if third_enabled else 0.0,
		entry_dir, f_entry, e_entry, t_entry)
	if layout.is_empty():
		return SiteRuntime.fail("NO_SPACE", "找不到所需的連通交戰空地；隊形不得重疊、占用人物格或跨越不可通行地勢，未修改地形")
	var formations: Array = [layout.friendly, layout.enemy]
	if third_enabled:
		formations.append(layout.third)
	return _deploy_trial_teams(sides, formations, 0)

func _trial_ranged_range(side: Dictionary) -> float:
	return float(SiteCombatRules.ranged_profile(str(side.troop_type) + "_01").get("range", 0.0))

func _trial_side_settings(setup: Dictionary, prefix: String) -> Dictionary:
	var count: Variant = setup.get(prefix + "_count", TerrainArmy.SOLDIER_COUNT)
	if not count is int or count < 1 or count > 100:
		return SiteRuntime.fail("INVALID", "每隊總名額須為 1–100 的整數")
	var role: Variant = setup.get(prefix + "_role", "combat")
	if not role is String or role not in ["combat", "work", "logistics"]:
		return SiteRuntime.fail("INVALID", "隊伍用途須為戰鬥、工作或後勤")
	var troop_type: Variant = setup.get(prefix + "_troop_type", "melee_infantry")
	if not troop_type is String or troop_type not in ["melee_infantry", "bow", "crossbow"] or role != "combat" and troop_type != "melee_infantry":
		return SiteRuntime.fail("INVALID", "戰鬥隊兵種須為近戰、弓或弩；工作／後勤維持原近戰配裝")
	var side := {"prefix": prefix, "count": count, "slot_count": count, "role": role, "troop_type": troop_type, "abilities": {}, "faction": 0 if prefix == "friendly" else 1}
	var entry: Variant = setup.get(prefix + "_entry", "")
	if not entry is String or not entry.strip_edges().is_empty() and _normalize_direction(entry).is_empty():
		return SiteRuntime.fail("INVALID", "進場方位須為東、南、西或北")
	side.entry = _normalize_direction(entry)
	for field: String in ["cart_count", "wagon_count"]:
		var vehicles: Variant = setup.get(prefix + "_" + field, 0)
		if not vehicles is int or vehicles < 0 or vehicles > 99 or role != "logistics" and vehicles > 0:
			return SiteRuntime.fail("INVALID", "車輛數須為 0–99 的整數，只有後勤隊可配置")
		side[field] = vehicles
		side.count -= vehicles
	if int(side.count) < 1:
		return SiteRuntime.fail("INVALID", "人員與車各占一個名額，至少須保留一名真正人員")
	for field: String in ["female_percent", "training", "tactics", "leadership", "coach"]:
		if field in ["tactics", "leadership", "coach"] and not setup.has(prefix + "_" + field):
			continue
		var value: Variant = setup.get(prefix + "_" + field, 50 if field == "female_percent" else 0)
		var maximum := 1000 if field == "training" else 100
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)) or float(value) < 0.0 or float(value) > maximum:
			return SiteRuntime.fail("INVALID", "%s 須為 0–%d 的整數" % [field, maximum])
		if field in ["tactics", "leadership", "coach"]:
			side.abilities[field] = int(value)
		else:
			side[field] = int(value)
	side.female_count = roundi(float(side.count) * float(side.female_percent) / 100.0)
	side.attack = setup.get(prefix + "_attack", role == "combat")
	if not side.attack is bool:
		return SiteRuntime.fail("INVALID", "初始命令須為守位或接敵")
	side.ai_enabled = setup.get(prefix + "_ai_enabled", false)
	if not side.ai_enabled is bool or bool(side.ai_enabled) and role != "combat":
		return SiteRuntime.fail("INVALID", "自主戰術 AI 僅限戰鬥隊，設定須為開啟或停用")
	side.spawn = setup.get(prefix + "_spawn", TerrainArmy.INVALID_CELL)
	if not side.spawn is Vector2i:
		return SiteRuntime.fail("INVALID", "出現位置須為地圖格位")
	if prefix == "third":
		var faction: Variant = setup.get("third_faction", 2)
		if not faction is int or faction < 0 or faction > 2:
			return SiteRuntime.fail("INVALID", "第三隊須選擇我方、敵方或第三勢力")
		side.faction = faction
	return SiteRuntime.ok("", {"side": side})

func add_melee_trial_team(setup: Dictionary = {}) -> Dictionary:
	var journey_guard := _ship_journey_guard()
	if not journey_guard.ok: return journey_guard
	if not army.combat_enabled or not opposing_army.combat_enabled or third_army.has_army():
		return SiteRuntime.fail("BUSY", "須已有兩隊測試軍隊且第三隊槽為空；未移動或清除既有人物")
	var parsed := _trial_side_settings(setup, "third")
	if not parsed.ok:
		return parsed
	var side: Dictionary = parsed.side
	if side.role != "combat" or army.role != "combat" or opposing_army.role != "combat":
		var support_formations := _independent_trial_formations([side])
		if support_formations.is_empty():
			return SiteRuntime.fail("NO_SPACE", "找不到合法追加位置，原兩隊與物資未修改")
		return _deploy_trial_teams([side], support_formations, 2)
	var ranged_range := _trial_ranged_range(side)
	var gap := 6 if ranged_range > 0.0 else 1
	var claimed := {}
	var hostile := {}
	var hostile_fronts: Array[Dictionary] = []
	for team: TerrainArmy in combat_armies:
		claimed.merge(team._cell_owners)
		claimed.merge(team._reserved_cells)
		if team.faction_id != int(side.faction):
			var front := {}
			for index in range(team.combat_units.size()):
				if team.combat_can_act(index):
					hostile[_army_effective_cell(team, index)] = true
					front[_army_effective_cell(team, index)] = true
			if not front.is_empty():
				hostile_fronts.append(front)
	if side.spawn == TerrainArmy.INVALID_CELL and not str(side.entry).is_empty():
		var formation := _find_directional_team_formation(side.entry, side.count, claimed, army.cells[0])
		if formation.is_empty():
			return SiteRuntime.fail("NO_SPACE", "指定方位沒有足夠合法連通入口；未改邊或修改原兩隊")
		return _deploy_trial_teams([side], [formation], 2)
	var candidates: Array[Vector2i] = []
	if side.spawn != TerrainArmy.INVALID_CELL:
		candidates.append(side.spawn)
	else:
		var seen := {}
		# Try an upper front spanning the original divide before other legal perimeter anchors.
		var first := army.cells[0] + Vector2i(-mini(4, int(side.count) - 1), -gap)
		candidates.append(first)
		seen[first] = true
		for cell: Vector2i in hostile:
			for direction: Vector2i in TerrainData.DIRECTIONS:
				for column in range(mini(10, int(side.count))):
					var anchor := cell + direction * gap - Vector2i(column, 0)
					if not seen.has(anchor):
						seen[anchor] = true
						candidates.append(anchor)
	var fallback: Array[Vector2i] = []
	for anchor: Vector2i in candidates:
		var formation := _third_trial_formation(anchor, side.count)
		if _melee_trial_formation_legal(formation, claimed) and _trial_front_touches(formation, hostile, ranged_range):
			if side.spawn != TerrainArmy.INVALID_CELL or hostile_fronts.size() < 2 or _trial_front_touches(formation, hostile_fronts[0], ranged_range) and _trial_front_touches(formation, hostile_fronts[1], ranged_range):
				return _deploy_trial_teams([side], [formation], 2)
			if fallback.is_empty():
				fallback = formation
	if side.spawn == TerrainArmy.INVALID_CELL:
		for anchor: Vector2i in candidates:
			var formation := _trial_connected_formation(anchor, side.count, claimed)
			if not formation.is_empty() and _trial_front_touches(formation, hostile, ranged_range):
				if hostile_fronts.size() < 2 or _trial_front_touches(formation, hostile_fronts[0], ranged_range) and _trial_front_touches(formation, hostile_fronts[1], ranged_range):
					return _deploy_trial_teams([side], [formation], 2)
				if fallback.is_empty():
					fallback = formation
	if not fallback.is_empty():
		return _deploy_trial_teams([side], [fallback], 2)
	return SiteRuntime.fail("NO_SPACE", "第三隊須置於敵軍旁，或遠程隊伍可在二十步內接近的合法連通空地；原兩隊及地形未修改")

func _deploy_trial_teams(sides: Array[Dictionary], formations: Array, first_slot: int) -> Dictionary:
	var journey_guard := _ship_journey_guard()
	if not journey_guard.ok: return journey_guard
	if crowd_site != null:
		return crowd_site.deploy(sides, formations) # same sides and cells, one native crowd
	if sides.is_empty() or formations.size() != sides.size() or first_slot < 0 or first_slot + sides.size() > SiteStore.MAX_ARMIES:
		return SiteRuntime.fail("INVALID", "隊伍部署清單或容量不合法")
	# Every caller enters the same original typed vehicle/Army deployment API.
	# Normalize nested literal arrays before any equipment/ID/vehicle mutation.
	var typed_formations: Array = []
	for raw: Variant in formations:
		if not raw is Array: return SiteRuntime.fail("INVALID", "隊伍部署格陣列非法")
		for cell: Variant in raw:
			if not cell is Vector2i: return SiteRuntime.fail("INVALID", "隊伍部署格型別非法")
		var typed_cells: Array[Vector2i] = []
		typed_cells.assign(raw)
		typed_formations.append(typed_cells)
	formations = typed_formations
	for index in range(first_slot, mini(first_slot + sides.size(), combat_armies.size())):
		if combat_armies[index].has_army():
			return SiteRuntime.fail("BUSY", "目標隊伍位置已有在場人物")
	var total := 0
	for side: Dictionary in sides:
		total += int(side.count)
	var existing_rows := 0
	for team: TerrainArmy in combat_armies:
		existing_rows += team.combat_units.size()
	if existing_rows + total > SiteStore.MAX_ARMY_ROWS:
		return SiteRuntime.fail("NO_SPACE", "目前 Site 上限為 %d 列軍隊人物；未新增人物" % SiteStore.MAX_ARMY_ROWS)
	if not _can_allocate_army_person_ids(total):
		return SiteRuntime.fail("NO_IDS", "人物序號已用盡；未建立或修改測試隊伍")
	var next_team := _next_army_identity()
	if next_team + sides.size() > 999999:
		return SiteRuntime.fail("ID_EXHAUSTED", "軍隊身分序號已用盡")
	if not TerrainArmy.load_combat_bake():
		return SiteRuntime.fail("MISSING_ASSET", "交戰圖集／碰撞資料不可用，未部署")
	for side: Dictionary in sides:
		var appearances: Array[Dictionary] = []
		if int(side.female_count) < int(side.count):
			appearances.append(TerrainArmy._combat_bake.manifest.appearance.duplicate(true))
		if int(side.female_count) > 0:
			appearances.append(TerrainArmy.EquipmentAtlas.female_appearance())
		for appearance: Dictionary in appearances:
			if appearance.is_empty():
				return SiteRuntime.fail("MISSING_ASSET", "所選人物基準素材不可用，未部署")
			if str(side.troop_type) != "melee_infantry":
				appearance.parts.weapon = "bow_01" if str(side.troop_type) == "bow" else "crossbow_01"
				appearance.parts.shield = "none"
			if not TerrainArmy.prepare_contact_source_for(appearance):
				return SiteRuntime.fail("MISSING_ASSET", "所選原人物同素體碰撞素材不可用，未部署")
			if not army.supports_equipment_recipe(SiteController._initial_uniform(appearance, side.faction)):
				return SiteRuntime.fail("MISSING_ASSET", "所選男女兵種圖集／染色資料不可用，未部署")
	var vehicle_plans: Array = []
	var planned_claims := {}
	for side: Dictionary in sides:
		if side.role != "combat":
			for cell: Vector2i in _trial_camp_access():
				planned_claims[cell] = true
			break
	for team: TerrainArmy in combat_armies:
		planned_claims.merge(team._cell_owners)
		planned_claims.merge(team._reserved_cells)
	for cells: Array in formations:
		for cell: Vector2i in cells:
			planned_claims[cell] = true
	for index in range(sides.size()):
		var side: Dictionary = sides[index]
		var planned: Dictionary = site_controller.vehicles.plan_team(next_team + index, side.cart_count, side.wagon_count, formations[index], planned_claims)
		if not planned.ok:
			return planned
		vehicle_plans.append(planned.plan)
		planned_claims.merge(site_controller.vehicles.plan_claims(planned.plan))
	var original_vehicles: Dictionary = site_controller.vehicles.checkpoint()
	# A rejected deployment is not a clear-army command: do not create loot or consume IDs.
	# Deployment only appends equipment and consumes the two allocators. Keep
	# every existing Site/holder/cargo/supply alias (including live ammunition).
	var original_site := terrain.site.duplicate()
	var original_items := {"item_records": terrain.site.item_records.duplicate(),
		"item_definitions": terrain.site.item_definitions.duplicate()}
	var original_appearances: Dictionary = site_controller._equipment_appearances.duplicate()
	var original_slot_count := combat_armies.size()
	_ensure_army_slots(first_slot + sides.size())
	var original_slots: Array[Dictionary] = []
	for index in range(sides.size()):
		var team: TerrainArmy = combat_armies[first_slot + index]
		original_slots.append({"team_id": team.team_id, "faction": team.faction_id, "training": team.training, "role": team.role})
	_configure_army_blockers(first_slot + sides.size() == 3)
	for index in range(sides.size()):
		var side: Dictionary = sides[index]
		var team: TerrainArmy = combat_armies[first_slot + index]
		team.team_id = next_team + index
		team.faction_id = side.faction
		team.roster_size = side.count
		team.training = float(side.training)
		var failure_stage := "deploy_at"
		var deployed := team.deploy_at(terrain, character, npc, formations[index])
		team.role = side.role
		if deployed:
			failure_stage = "enable_combat"
			deployed = team.enable_combat(side.attack, side.female_count, StringName(side.troop_type))
		if deployed:
			failure_stage = "equipment"
			for unit: Dictionary in team.combat_units:
				if unit.get("item_state", {}).is_empty():
					deployed = false # The original equipment initializer rejected its complete recipe.
					break
				if str(side.troop_type) != "melee_infantry":
					# Explicit test-deployment stock only; combat never refills this original cargo.
					unit.cargo["arrow" if str(side.troop_type) == "bow" else "bolt"] = 20
					if SiteRuntime.carried_size(unit.cargo, unit.item_state) > SiteRuntime.CARRY_CAPACITY:
						deployed = false
						break
		if deployed:
			failure_stage = "vehicles"
			var vehicle_result: Dictionary = site_controller.vehicles.deploy_plan(team, vehicle_plans[index])
			deployed = bool(vehicle_result.ok)
		if deployed:
			failure_stage = "work_team"
			for row: Dictionary in team.combat_units:
				row.logistics = side.role == "logistics"
			if side.role == "work" and not side.attack:
				var workers: Array[int] = []
				for unit in range(1, team.combat_units.size()):
					workers.append(team.combat_identity(unit))
				if not workers.is_empty():
					deployed = bool(site_controller.work_team.assign(team, workers, team.combat_identity(team.current_commander)).ok)
		if not deployed:
			site_controller.vehicles.rollback(original_vehicles)
			for rollback in range(sides.size()):
				var reverted: TerrainArmy = combat_armies[first_slot + rollback]
				for row: Dictionary in reverted.combat_units:
					site_controller.work_team.cancel(int(row.person_id))
				reverted.clear()
				reverted.team_id = original_slots[rollback].team_id
				reverted.faction_id = original_slots[rollback].faction
				reverted.training = original_slots[rollback].training
				reverted.role = original_slots[rollback].role
			for field: String in original_items:
				terrain.site[field].clear()
				terrain.site[field].merge(original_items[field])
			for field: String in ["next_item", "next_person_id"]:
				if original_site.has(field): terrain.site[field] = original_site[field]
				else: terrain.site.erase(field)
			site_controller._equipment_appearances.clear()
			site_controller._equipment_appearances.merge(original_appearances)
			if combat_armies.size() > original_slot_count:
				_trim_empty_army_slots()
			_configure_army_blockers()
			return SiteRuntime.fail("DEPLOY_FAILED", "第 %d 隊在 %s 部署失敗；原人物、物品、地形及序號未修改" % [index + 1, failure_stage])
		var abilities: Dictionary = team.command_abilities.get(team.formal_commander, {}).duplicate()
		abilities.merge(side.abilities, true)
		team.command_abilities[team.formal_commander] = abilities
		# Initial setup may be accepted while paused, like the existing attack
		# choice. Runtime decisions still wait for the original action clock.
		team.tactical_ai_enabled = bool(side.ai_enabled)
		team.tactical_ai_status = "待判斷" if team.tactical_ai_enabled else "停用"
	for index in range(sides.size()):
		var team: TerrainArmy = combat_armies[first_slot + index]
		var center_self := Vector2.ZERO
		for cell: Vector2i in team.cells:
			center_self += Vector2(cell)
		center_self /= maxf(1.0, float(team.cells.size()))

		var center_other := Vector2.ZERO
		var nearest_distance := INF
		for candidate: TerrainArmy in combat_armies:
			if candidate == team or not candidate.has_army() or candidate.faction_id == team.faction_id:
				continue
			var candidate_center := Vector2.ZERO
			for cell: Vector2i in candidate.cells:
				candidate_center += Vector2(cell)
			candidate_center /= float(candidate.cells.size())
			var distance := center_self.distance_squared_to(candidate_center)
			if distance < nearest_distance:
				nearest_distance = distance
				center_other = candidate_center
		if nearest_distance == INF:
			center_other = center_self

		var diff := center_other - center_self
		var face := Vector2i.RIGHT
		if absf(diff.x) >= absf(diff.y):
			face = Vector2i.RIGHT if diff.x >= 0.0 else Vector2i.LEFT
		else:
			face = Vector2i.DOWN if diff.y >= 0.0 else Vector2i.UP
		for unit in range(team.cells.size()):
			team.facing[unit] = face
		team._visual_dirty = true
	terrain.site["army_trial_active"] = true
	terrain.site["army_next_team"] = next_team + sides.size()
	var minimum: Vector2i = formations[0][0]
	var maximum := minimum
	for team: TerrainArmy in combat_armies:
		for cell: Vector2i in team.cells:
			minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
			maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	var support_view := false
	for side: Dictionary in sides:
		support_view = support_view or side.role != "combat"
	for plan: Array in vehicle_plans:
		for cell: Vector2i in site_controller.vehicles.plan_claims(plan):
			minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
			maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	var screen := get_viewport_rect().size
	var area := camera_usable_rect()
	var extent := Vector2(maximum - minimum + Vector2i(5, 5)) * TerrainRenderer.CELL_PIXELS
	var zoom := clampf(minf(0.9, minf(area.size.x / extent.x, area.size.y / extent.y)), MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2.ONE * zoom
	camera.position = (Vector2(minimum + maximum) + Vector2.ONE) * 0.5 * TerrainRenderer.CELL_PIXELS
	camera.position += (screen * 0.5 - area.get_center()) / zoom
	camera.force_update_scroll()
	var values := {"troop_type": str(sides[0].troop_type)}
	var summaries: Array[String] = []
	for index in range(sides.size()):
		var side: Dictionary = sides[index]
		values[side.prefix + "_spawn"] = formations[index][0]
		values[side.prefix + "_count"] = side.count
		values[side.prefix + "_slot_count"] = side.slot_count
		values[side.prefix + "_role"] = side.role
		values[side.prefix + "_troop_type"] = side.troop_type
		if str(side.troop_type) != str(values.troop_type): values.troop_type = "per_team"
		values[side.prefix + "_cart_count"] = side.cart_count
		values[side.prefix + "_wagon_count"] = side.wagon_count
		values[side.prefix + "_female_count"] = side.female_count
		summaries.append("%s：%s／%s，男 %d／女 %d，物資車 %d／馬車 %d，共 %d 名額" % [{"friendly": "我方", "enemy": "敵方", "third": "第三隊"}[side.prefix], {"combat": "戰鬥隊", "work": "工作隊", "logistics": "後勤隊"}[side.role], {"melee_infantry": "近戰步兵", "bow": "弓兵", "crossbow": "弩兵"}[side.troop_type], int(side.count) - int(side.female_count), int(side.female_count), int(side.cart_count), int(side.wagon_count), int(side.slot_count)])
	values["third_enabled"] = third_army.has_army()
	values["third_faction"] = third_army.faction_id
	return SiteRuntime.ok("測試隊伍已部署（含隊長）：%s；玩家仍自行操作。" % "、".join(summaries), values)

var enemy_query_owner_cells_enabled := true # A/B: only the verified synchronous prepare window uses original cell owners.
var enemy_query_owner_cell_hits := 0
var _enemy_query_owner_cell_window := false

func _enemy_query_owner_cells_admitted() -> bool:
	# A direct caller may have changed cells without updating Army claims. Admit
	# only a complete, unique original-owner map for this one prepare window.
	var claimed: Dictionary = {}
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled:
			continue
		if team.get_script() != TerrainArmy or team.data != terrain or team._cell_owners.size() != team.combat_units.size() \
			or team.vehicle_transport != null and not team.vehicle_transport.records().is_empty():
			return false
		for target_index in range(team.combat_units.size()):
			var cell: Vector2i = _army_effective_cell(team, target_index)
			if team._cell_owners.get(cell, -1) != target_index or claimed.has(cell):
				return false
			claimed[cell] = true
	return true

func _nearest_unit_enemy(source: TerrainArmy, index: int) -> Dictionary:
	if not source._ship_attack_allowed(index): return {}
	var best := {}
	var best_distance := 3
	var retained := int(source.combat_units[index].target)
	var indexed := enemy_query_owner_cells_enabled and _enemy_query_owner_cell_window
	if indexed:
		enemy_query_owner_cell_hits += 1
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled or team.faction_id == source.faction_id:
			continue
		var nearby_indices: Array[int] = []
		if indexed:
			for dx in range(-2, 3):
				for dy in range(-2 + absi(dx), 3 - absi(dx)):
					var cell := _army_effective_cell(source, index) + Vector2i(dx, dy)
					var candidate_index: int = int(team._cell_owners.get(cell, -1))
					if candidate_index >= 0:
						nearby_indices.append(candidate_index)
			nearby_indices.sort() # Preserve the original team's roster order, including retained precedence.
		var candidate_count := nearby_indices.size() if indexed else team.combat_units.size()
		for ordinal in range(candidate_count):
			var target_index: int = nearby_indices[ordinal] if indexed else ordinal
			if team._ship_in_journey(target_index): continue
			var offset := _army_effective_cell(team, target_index) - _army_effective_cell(source, index)
			var distance := absi(offset.x) + absi(offset.y)
			if distance > 2 or not team.combat_can_act(target_index) or not _combat_melee_clear(source.combat_identity(index), team.combat_identity(target_index), _army_effective_cell(source, index), _army_effective_cell(team, target_index), true):
				continue
			var identity := team.combat_identity(target_index)
			var threat := bool(team.combat_hot_get(target_index, &"attack")) and int(team.combat_units[target_index].target) == source.combat_identity(index)
			var candidate := {"cell": _army_effective_cell(team, target_index), "identity": identity, "threat": threat}
			if identity == retained:
				return candidate
			if not best.is_empty() and (bool(best.threat) and not threat or bool(best.threat) == threat and (distance > best_distance or distance == best_distance and identity > int(best.identity))):
				continue
			best_distance = distance
			best = candidate
	for actor: TerrainTestCharacter in combat_actors:
		if actor.faction_id == source.faction_id or not actor.can_act():
			continue
		var offset := actor.terrain_cell - _army_effective_cell(source, index)
		var distance := absi(offset.x) + absi(offset.y)
		if distance > 2 or not _combat_melee_clear(source.combat_identity(index), actor.combat_identity(), _army_effective_cell(source, index), actor.terrain_cell, true):
			continue
		var identity := actor.combat_identity()
		var threat := actor.action_time > 0.0 and actor._strike_at >= 0.0
		var candidate := {"cell": actor.terrain_cell, "identity": identity, "threat": threat}
		if identity == retained:
			return candidate
		if not best.is_empty() and (bool(best.threat) and not threat or bool(best.threat) == threat and (distance > best_distance or distance == best_distance and identity > int(best.identity))):
			continue
		best_distance = distance
		best = candidate
	return best

func _army_target(source: TerrainArmy, identity: int) -> Dictionary:
	if _ship_person_in_journey(identity): return {}
	for actor: TerrainTestCharacter in combat_actors:
		if actor.combat_identity() == identity and actor.faction_id != source.faction_id and actor.can_act():
			return {"cell": actor.terrain_cell, "identity": identity}
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled or team.faction_id == source.faction_id:
			continue
		var index := team.index_for_identity(identity)
		if team.combat_can_act(index):
			return {"cell": _army_effective_cell(team, index), "identity": identity}
	return {}

func _combat_target(identity: int, with_bodies: bool = false) -> Dictionary:
	if _ship_person_in_journey(identity): return {}
	return _original_person_target(identity, with_bodies)

func _original_person_target(identity: int, with_bodies: bool = false) -> Dictionary:
	if crowd_site != null and crowd_site.active and crowd_site.contains_person(identity):
		return crowd_site.combat_target(identity, with_bodies)
	# Read the original owner on demand. No surrogate actor or copied HP/position.
	for actor: TerrainTestCharacter in combat_actors:
		if actor.combat_identity() == identity:
			return {"owner": actor, "unit": -1, "position": actor.position, "cell": actor.terrain_cell, "hp": actor.hp,
				"bodies": actor._geometry.body_shapes(actor) if with_bodies and actor.editor != null else []}
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled:
			continue
		var index := team.index_for_identity(identity)
		if index >= 0 and index < team.combat_units.size():
			return {"owner": team, "unit": index, "position": team.combat_ground(index), "cell": _army_effective_cell(team, index),
				"hp": float(team.combat_hot_get(index, &"hp")), "bodies": team.combat_shapes(index, "body") if with_bodies else []}
	return {}

func _combat_target_in_site(identity: int, with_bodies: bool = false) -> Dictionary:
	var person := _combat_target(identity)
	if person.is_empty(): return {}
	var exited: bool = bool(person.owner.combat_hot_get(int(person.unit), &"site_exited", false)) if int(person.unit) >= 0 else person.owner.site_exited
	if exited: return {}
	return _combat_target(identity, true) if with_bodies else person

func select_army_target(cell: Vector2i) -> bool:
	if crowd_site != null and crowd_site.active:
		for crowd_owner: RefCounted in crowd_site.person_owners():
			for index: int in crowd_owner.combat_units:
				var person: Dictionary = crowd_owner.person(index)
				if person.cell == cell and float(person.hp) > 0.0:
					selected_army_target = int(person.person_id)
					show_status("選中群眾人物 #%d" % selected_army_target)
					if is_instance_valid(selected_army_label): selected_army_label.text = "選中群眾人物 #%d" % selected_army_target
					return true
		return false
	var controlled := controlled_target()
	var faction: int = controlled.owner.faction_id if not controlled.is_empty() else character.faction_id
	for team: TerrainArmy in combat_armies:
		for index in range(team.combat_units.size()):
			if team._ship_in_journey(index): continue
			if _army_effective_cell(team, index) == cell and not team.member_gone(index) and not bool(team.combat_hot_get(index, &"site_exited", false)):
				selected_army_target = team.combat_identity(index)
				var selection_text := "選中人物 #%d（%s）" % [selected_army_target, "友軍" if team.faction_id == faction else "敵軍"]
				show_status(selection_text)
				if is_instance_valid(selected_army_label): selected_army_label.text = selection_text
				return true
	return false

func attack_selected_soldier() -> bool:
	return controlled_attack(selected_army_target)

func rescue_selected_soldier() -> bool:
	var target := _combat_target_in_site(selected_army_target)
	var person := controlled_target()
	if person.is_empty() or target.is_empty() or not target.owner is TerrainArmy:
		return false
	if int(person.unit) >= 0:
		return person.owner == target.owner and person.owner.start_unit_rescue(int(person.unit), int(target.unit))
	return person.owner.start_rescue_unit(target.owner, int(target.unit))

func _contact_hit_exclusions(source: Variant, source_unit: int, ranged: bool = false) -> Dictionary:
	if ranged or not FatigueGeometry.strict_contact_order_enabled or not FatigueGeometry.melee_hit_cull_enabled:
		return {}
	if not source is Object or not is_instance_valid(source):
		return {}
	if source is TerrainArmy and source_unit >= 0 and source_unit < source.combat_units.size():
		var row: Dictionary = source.combat_units[source_unit]
		if row.get("hits") is Dictionary:
			return row.hits # Original synchronous swing state, never copied or mutated here.
	elif source is TerrainTestCharacter and source_unit == -1:
		return source._attack_hits
	return {}

func _begin_army_contact_inputs() -> void:
	var reuse_pose: bool = TerrainArmy._contact_source != null and TerrainArmy._contact_source.same_batch_result_reuse_enabled
	if not _sampling_army_contacts or not (contact_input_reuse_enabled or reuse_pose):
		return
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled:
			continue
		var key := ["targets", team.get_instance_id()]
		if not _army_contact_geometry.has(key):
			var targets: Array = []
			targets.resize(team.combat_units.size())
			_army_contact_geometry[key] = targets
		if contact_input_reuse_enabled:
			team._contact_batch_inputs = _army_contact_geometry[key]
		if reuse_pose:
			team._contact_batch_pose_results = _army_contact_geometry[key]

func _end_army_contact_inputs() -> void:
	for team: TerrainArmy in combat_armies:
		team._contact_batch_inputs = [] # Release before hits can change original state.
		team._contact_batch_pose_results = []

static func _build_contact_buckets(grounds: Array[Vector2]) -> Dictionary:
	# Transient index of the existing raw ground anchors, NOT the occupied-cell
	# map: dead/KO rows and coincident/moving people must all remain candidates.
	var buckets := {}
	for index in grounds.size():
		var point := grounds[index]
		if not point.is_finite() or maxf(absf(point.x), absf(point.y)) > 1048576.0:
			return {} # Unknown numerical domain retains the original linear scan.
		if index == 0:
			continue # Captain is always queried by the original collector.
		var cell := Vector2i(floori(point.x / 256.0), floori(point.y / 256.0))
		if not buckets.has(cell):
			buckets[cell] = [] as Array[int]
		buckets[cell].append(index)
	return buckets

static func _contact_bucket_candidates(bounds: Rect2, grounds: Array[Vector2], buckets: Dictionary) -> Array[int]:
	if buckets.is_empty() or not bounds.position.is_finite() or not bounds.end.is_finite() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or maxf(maxf(absf(bounds.position.x), absf(bounds.position.y)), maxf(absf(bounds.end.x), absf(bounds.end.y))) > 1048576.0:
		return Array(range(grounds.size()), TYPE_INT, &"", null)
	var first := Vector2i(floori(bounds.position.x / 256.0), floori(bounds.position.y / 256.0))
	var last := Vector2i(floori(bounds.end.x / 256.0), floori(bounds.end.y / 256.0))
	if (last.x - first.x + 1) * (last.y - first.y + 1) > 4096:
		return Array(range(grounds.size()), TYPE_INT, &"", null)
	var result: Array[int] = []
	if not grounds.is_empty():
		result.append(0)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if buckets.has(cell):
				result.append_array(buckets[cell])
	result.sort() # Preserve original row/Source/ordered-contact history.
	return result # Superset only: original exact anchor test still follows.

func _collect_army_contacts(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], source_cell: Vector2i, source_position: Vector2, source: Variant, source_unit: int, ranged: bool = false, prepared: Array = []) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if current.is_empty():
		return hits
	var excluded := _contact_hit_exclusions(source, source_unit, ranged)
	if prepared.is_empty():
		prepared = FatigueGeometry.prepare_sweeps(previous, current)
	var bounds := Rect2(current[0][0], Vector2.ZERO)
	for shapes: Array in [previous, current]:
		for shape: PackedVector2Array in shapes:
			for vertex: Vector2 in shape:
				bounds = bounds.expand(vertex)
	# Baked body/shield extents are checked by the focused data test. Broad phase
	# only excludes distant ground anchors; narrow phase always uses real shapes.
	var anchor_bounds := bounds.grow(256.0)
	bounds = bounds.grow(0.001)
	var finite_map_sweep := bounds.position.is_finite() and bounds.end.is_finite() and maxf(maxf(absf(bounds.position.x), absf(bounds.position.y)), maxf(absf(bounds.end.x), absf(bounds.end.y))) <= 16384.0
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled:
			continue
		var grounds: Array[Vector2] = []
		var targets: Array = []
		if _sampling_army_contacts:
			# Same post-advance batch as exact geometry, cleared before resolution.
			# Keep raw original anchors; the optional index never changes them.
			var ground_key := ["grounds", team.get_instance_id()]
			if not _army_contact_geometry.has(ground_key):
				for target_index in range(team.combat_units.size()):
					grounds.append(team.combat_ground(target_index))
				_army_contact_geometry[ground_key] = grounds
			else:
				grounds = _army_contact_geometry[ground_key]
			# No roster changes occur between post-advance sampling and the cache
			# clear before resolution. Use original row indices only in this batch,
			# avoiding an allocated identity-pair/hash for every nearby candidate.
			var targets_key := ["targets", team.get_instance_id()]
			if not _army_contact_geometry.has(targets_key):
				targets.resize(team.combat_units.size()) # Null slots, not one shared Dictionary.
				_army_contact_geometry[targets_key] = targets
			else:
				targets = _army_contact_geometry[targets_key]
		var candidate_started := Time.get_ticks_usec() if contact_candidate_profile_enabled else 0
		var candidates: Array
		if contact_buckets_enabled and _sampling_army_contacts:
			var bucket_key := ["contact_buckets", team.get_instance_id()]
			if not _army_contact_geometry.has(bucket_key):
				var build_started := Time.get_ticks_usec() if contact_candidate_profile_enabled else 0
				_army_contact_geometry[bucket_key] = _build_contact_buckets(grounds)
				if contact_candidate_profile_enabled:
					contact_candidate_profile.bucket_builds += 1
					contact_candidate_profile.bucket_build_usec += Time.get_ticks_usec() - build_started
			candidates = _contact_bucket_candidates(anchor_bounds, grounds, _army_contact_geometry[bucket_key])
		else:
			candidates = range(team.combat_units.size())
		if contact_candidate_profile_enabled:
			contact_candidate_profile.queries += 1
			contact_candidate_profile.rows_before += team.combat_units.size()
			contact_candidate_profile.rows_visited += candidates.size()
			contact_candidate_profile.candidate_usec += Time.get_ticks_usec() - candidate_started
		for index: int in candidates:
			if team._ship_in_journey(index): continue
			if bool(team.combat_hot_get(index, &"site_exited", false)): continue
			if team == source and index == source_unit:
				continue
			if index != 0:
				var ground: Vector2 = grounds[index] if _sampling_army_contacts else team.combat_ground(index)
				if not anchor_bounds.has_point(ground):
					continue
				if contact_candidate_profile_enabled:
					contact_candidate_profile.anchor_passed += 1
				var radius: float
				if _sampling_army_contacts:
					if targets[index] == null:
						targets[index] = {}
					if not targets[index].has("anchor_radius"):
						targets[index]["anchor_radius"] = team.conservative_contact_radius(index)
					radius = targets[index].anchor_radius
				else:
					radius = team.conservative_contact_radius(index)
				# The native float32 enclosure includes the final original map
				# translations only inside its explicit numerical domain.
				if radius < 256.0 and finite_map_sweep and ground.is_finite() and maxf(absf(ground.x), absf(ground.y)) <= 16384.0 and not bounds.grow(radius).has_point(ground):
					continue
			if not excluded.is_empty() and excluded.has(team.combat_identity(index)):
				continue # Same once-per-swing skip; distant anchors need no ID lookup.
			if finite_map_sweep and TerrainArmy._contact_source != null and TerrainArmy._contact_source.cheap_query_bounds_enabled:
				var query_bounds: Rect2
				var query_started := Time.get_ticks_usec() if combat_profile_enabled else 0
				if _sampling_army_contacts:
					if targets[index] == null:
						targets[index] = {}
					if not targets[index].has("query_bounds"):
						targets[index]["query_bounds"] = team.combat_query_bounds(index)
					query_bounds = targets[index].query_bounds
				else:
					query_bounds = team.combat_query_bounds(index)
				_combat_profile_stage("collect_query_bounds", query_started)
				if not bounds.intersects(query_bounds, true):
					continue
			var geometry := {}
			var target_bounds: Rect2
			if _sampling_army_contacts:
				# Same existing batch as the two original Actors; no cross-step or
				# projectile cache, and no alteration of candidates/exact polygons.
				if targets[index] == null:
					targets[index] = {}
				if not targets[index].has("bounds"):
					var geometry_started := Time.get_ticks_usec() if combat_profile_enabled else 0
					# Use the very same exact posed bound first. Most distant targets
					# need no allocation/translation of all original limb polygons.
					targets[index]["bounds"] = team.combat_bounds(index)
					if contact_candidate_profile_enabled:
						contact_candidate_profile.bounds_built += 1
					_combat_profile_stage("collect_geometry", geometry_started)
				geometry = targets[index]
				target_bounds = geometry.bounds
			else:
				target_bounds = team.combat_bounds(index)
			var source_id: int = source.combat_identity(source_unit) if source is TerrainArmy else source.combat_identity()
			if not bounds.intersects(target_bounds, true) or not _combat_melee_clear(source_id, team.combat_identity(index), source_cell, _army_effective_cell(team, index), true):
				continue
			if _sampling_army_contacts and not geometry.has("body"):
				var geometry_started := Time.get_ticks_usec() if combat_profile_enabled else 0
				geometry.merge(team.incoming_geometry(index))
				if contact_candidate_profile_enabled:
					contact_candidate_profile.geometry_built += 1
				_combat_profile_stage("collect_geometry", geometry_started)
			var narrow_started := Time.get_ticks_usec() if combat_profile_enabled else 0
			var hit := team.combat_contact(index, previous, current, ranged, geometry, prepared)
			if contact_candidate_profile_enabled:
				contact_candidate_profile.narrow_calls += 1
			_combat_profile_stage("collect_narrow", narrow_started)
			if not hit.is_empty():
				hit["distance"] = source_position.distance_squared_to(hit.point)
				hits.append(hit)
	_sort_contacts(hits)
	return hits

func _collect_unit_contacts(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], source_cell: Vector2i, source_position: Vector2, source: Variant, source_unit: int) -> Array[Dictionary]:
	# This attack sweep is identical for every original target in this one call.
	# Discard it on return; no time, person state or hit result is retained.
	var prepared := FatigueGeometry.prepare_sweeps(previous, current)
	var hits := _collect_army_contacts(previous, current, source_cell, source_position, source, source_unit, false, prepared)
	var excluded := _contact_hit_exclusions(source, source_unit)
	for actor: TerrainTestCharacter in combat_actors:
		if actor.site_exited: continue
		if not excluded.is_empty() and excluded.has(actor.combat_identity()):
			continue
		var geometry := {}
		if _sampling_army_contacts:
			var identity := actor.get_instance_id()
			if not _army_contact_geometry.has(identity):
				var geometry_started := Time.get_ticks_usec() if combat_profile_enabled else 0
				geometry = actor.incoming_geometry()
				var points := PackedVector2Array()
				for kind: String in ["body", "shield", "parry"]:
					for polygon: PackedVector2Array in geometry[kind]:
						points.append_array(polygon)
				geometry["bounds"] = FatigueGeometry.polygon_bounds(points)
				_army_contact_geometry[identity] = geometry
				_combat_profile_stage("actor_collect_geometry", geometry_started)
			geometry = _army_contact_geometry[identity]
			if batch_actor_bounds_enabled:
				# Union of the actual post-advance polygons, not a cell/radius
				# approximation. Reuse the original padded full-sweep bounds.
				var overlaps := false
				for sweep: Dictionary in prepared:
					if (sweep.bounds as Rect2).intersects(geometry.bounds, true):
						overlaps = true
						break
				if not overlaps:
					continue
		var narrow_started := Time.get_ticks_usec() if combat_profile_enabled else 0
		var hit := actor.incoming_contact(previous, current, false, geometry, prepared)
		_combat_profile_stage("actor_collect_narrow", narrow_started)
		var source_id: int = source.combat_identity(source_unit) if source is TerrainArmy else source.combat_identity()
		if not hit.is_empty() and _combat_melee_clear(source_id, actor.combat_identity(), source_cell, actor.terrain_cell, true):
			hit["target"] = actor
			hit["identity"] = actor.combat_identity()
			hit["faction"] = actor.faction_id
			hit["distance"] = source_position.distance_squared_to(hit.point)
			hits.append(hit)
	_sort_contacts(hits)
	return hits

func _sort_contacts(hits: Array[Dictionary]) -> void:
	hits.sort_custom(FatigueGeometry.contact_precedes)

func _update_info() -> void:
	if terrain == null or not is_instance_valid(info) or not info.is_visible_in_tree() or not is_instance_valid(combat_info):
		return
	if is_instance_valid(site_test_window) and not site_test_window.visible:
		return
	combat_info.text = "Player HP %.1f | stun %.1f | 疲勞 %.1f | %s" % [character.hp, character.stun, character.fatigue, character.combat_status]
	if is_instance_valid(npc): combat_info.text += "\nNPC HP %.1f | stun %.1f | 疲勞 %.1f | %s" % [npc.hp, npc.stun, npc.fatigue, npc.combat_status]
	if exchange_enabled:
		combat_info.text += "\n遠程 %d 發／正中 %d／擦傷 %d\n玩家箭 %d／弩矢 %d" % [ranged_shots, ranged_results.hit, ranged_results.graze,
			int(character.ammo_inventory.get("arrow", 0)), int(character.ammo_inventory.get("bolt", 0))]
		if is_instance_valid(npc): combat_info.text += "；NPC 箭 %d／弩矢 %d" % [int(npc.ammo_inventory.get("arrow", 0)), int(npc.ammo_inventory.get("bolt", 0))]
	if crowd_site != null and crowd_site.active and army_info != null:
		army_info.text = crowd_site.summary()
	elif army_info != null and army != null:
		var captain_goal := "-"
		if army.has_army():
			captain_goal = str(army.desired_cells[0])
		army_info.text = "%s\nRender: %s | live 3D sources: %d\nFront goal: %s | guide: %s\nCaptain: %s -> local slot %s\nFormation: %s width=%d %d/99 | occupied: %d | moving: %d\nLegal lag: %d | unknown: %d | RUN: %d | front guards: %d\nSwaps: %d | completed steps: %d" % [army.command_status, army.visual_mode(), army.active_3d_source_count(), army._march_goal, army._formation_anchor_cell, str(army.cells[0]) if army.has_army() else "-", captain_goal, army.formation_mode_name(), army.formation_width(), army.formation_count(), army.occupied_count(), army.moving_count(), army.formation_cohesion.lag, army.formation_cohesion.unknown, army.formation_cohesion.runners, army.formation_cohesion.guards, army.swap_count(), army.completed_steps()]
		var passage := army.passage_summary()
		army_info.text += "\nPassage: waiting %d | core/egress %d | all cleared %d/99" % [passage.waiting, passage.clearing, passage.completed]
	var cell: Vector2i = renderer.pick_cell(get_viewport().get_mouse_position())
	var details: String = "Hovered: outside map"
	if terrain.contains(cell):
		var i: int = terrain.index(cell)
		details = "Hovered cell: %s\nHeight: %d | %s\nWalkable top: %s\nCliff edge: %s | Ramp: %s" % [cell, terrain.height_levels[i], TerrainData.SURFACE_NAMES[terrain.surface_types[i]], terrain.is_walkable(cell), (terrain.flags[i] & TerrainData.Flag.CLIFF) != 0, terrain.ramp_edges[i] != 0]
	info.text = "%s\nSeed: %d\n%s\nCharacter cell: %s\nZoom: %.3f | FPS: %d\nGenerate: %.2f ms" % [TerrainPreset.NAMES[terrain.preset], terrain.seed_value, details, character.terrain_cell, camera.zoom.x, Engine.get_frames_per_second(), generation_ms]
	if is_instance_valid(npc): info.text += "\nNPC cell: %s\nNPC command: %s" % [npc.terrain_cell, npc.command_status]


func _region_operation_pending() -> bool:
	return site_controller != null and site_controller.has_method("region_operation_pending") and bool(site_controller.call("region_operation_pending"))

func _ship_person_in_journey(identity: int) -> bool:
	return identity > 0 and site_controller != null and site_controller.has_method("ship_person_in_journey") and bool(site_controller.call("ship_person_in_journey", identity))

func has_ship_journey() -> bool:
	for team: TerrainArmy in combat_armies:
		if team.has_ship_journey(): return true
	return false

func _ship_journey_guard() -> Dictionary:
	return SiteRuntime.fail("BUSY", "船隊仍在跨區旅程中；請先完成或取消原旅程") if has_ship_journey() else SiteRuntime.ok()

func _ship_vehicle_in_journey(identity: String) -> bool:
	return not identity.is_empty() and site_controller != null and site_controller.has_method("ship_vehicle_in_journey") and bool(site_controller.call("ship_vehicle_in_journey", identity))

func _ship_embarked(identity: int) -> bool:
	return site_controller != null and site_controller.vehicles.is_embarked(identity)

func _ship_crew_work(identity: int) -> bool:
	return site_controller != null and site_controller.vehicles.ship_person_crew_work(identity)

func _army_effective_cell(team: TerrainArmy, index: int) -> Vector2i:
	var identity := team.combat_identity(index)
	return site_controller.vehicles.ship_person_cell(identity) if _ship_embarked(identity) else team.cells[index]

func _ship_fatigue_threat(identity: int, faction: int, candidates: Dictionary) -> bool:
	if _ship_person_in_journey(identity): return true # Coarse travel never authorizes Site rest.
	var boat: Dictionary = site_controller.vehicles.ship_for_person(identity)
	if boat.is_empty() or not boat.move.is_empty() or not site_controller.vehicles.ship_job(str(boat.id)).is_empty() or float(terrain.site.get("combat_left", 0.0)) > 0.0: return true
	# Read original incoming flights. V1 conservatively delays boat rest while a
	# projectile is active; it never infers shore safety from historical cells.
	for source: Node2D in _ranged_owners():
		if not source.projectiles.is_empty(): return true
	var boat_candidates: Dictionary = candidates.get("ship_rest", {})
	candidates["ship_rest"] = boat_candidates
	return _exchange_rest_threat(site_controller.vehicles.ship_person_cell(identity), faction, boat_candidates)

# Insert on ORIGINAL TerrainLab. The retained child is the original runtime
# for one pending cold Site, not a second person/food/economy implementation.
func restore_original_site(data: TerrainData) -> Dictionary:
	if not restore_only or not is_inside_tree() or data == null:
		return SiteRuntime.fail("INVALID_MODE", "先以還原模式建立原 TerrainLab")
	if data.site.has("region_snapshot"):
		var detached := _region_detached_bind_data(data)
		var region_restore := _region_bootstrap_bind_child(self, detached)
		if not region_restore.ok: return region_restore
		var region_ecology := SiteStore.prepare_ecology_candidate(terrain, region_restore.context)
		if not region_ecology.ok: return region_ecology
		if bool(region_ecology.changed):
			var projected := _region_project_original_bind_child(self, region_ecology.data, region_restore.context)
			if not projected.ok: return projected
		return SiteRuntime.ok("原人物／實物已還原", {"data": terrain, "owners_restored": true, "effects_complete": bool(region_restore.context.get("effects_complete", true))})
	var fire_guard := SiteStore.fire_event_guard(data)
	if not fire_guard.ok: return fire_guard
	# navigation_for_state shares natural-ground arrays by design. Simulation
	# may clear/level terrain, so detach every mutable base array as well.
	var restored_data := SiteEnv.navigation_for_state(data, data.site.duplicate(true))
	for field: String in ["height_levels", "surface_types", "flags", "cliff_drops", "ramp_edges", "detail_variation",
		"fertility", "moisture", "drainage", "foundation", "groundwater", "water_kind", "water_body"]:
		restored_data.set(field, data.get(field).duplicate())
	restored_data.parameters = data.parameters.duplicate(true)
	restored_data.resource_base = data.resource_base.duplicate(true)
	var validation := SiteStore._validate_state(restored_data, restored_data.site)
	if not validation.ok: return validation
	var ecology := SiteStore.prepare_ecology_candidate(restored_data)
	if not ecology.ok: return ecology
	restored_data = ecology.data
	# Old saves without actor snapshots have no evidence of real body state.
	# Ordinary new-site migration stays unchanged; cold replay cannot invent it.
	if int(restored_data.site.get("actor_presence_version", 0)) != 1 and restored_data.site.get("actors", {}).is_empty():
		return SiteRuntime.fail("SAVE_VERSION", "冷地點缺少原人物存在快照；原檔保留")
	if restored_data.site.get("actors", {}).has("npc") and not is_instance_valid(npc):
		return SiteRuntime.fail("RESTORE_PRESENTER", "原 NPC 快照須由原 NPC 節點還原，不能移除真實人物")
	if not is_instance_valid(npc):
		var retired := SiteStore.retire_default_worker(restored_data)
		if not retired.ok: return retired
	var prepared := prepare_crowd_load(restored_data, validation.get("crowd_native"))
	if not prepared.ok: return prepared
	bind_terrain(restored_data, prepared)
	if terrain != restored_data:
		return SiteRuntime.fail("RESTORE_FAILED", "原 TerrainLab 未接受候選快照")
	# Restore may reactivate a visual body. Only the common step drives it here.
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	_clear_movement_input()
	for actor: TerrainTestCharacter in combat_actors:
		actor.set_process(false)
		actor.set_process_input(false)
		actor.set_process_unhandled_input(false)
	for team: TerrainArmy in combat_armies: team.set_process(false)
	return SiteRuntime.ok("原人物／實物已還原", {"data": terrain})

func cold_source_identity(data: TerrainData, target_seconds: float) -> Dictionary:
	if data == null or not is_finite(target_seconds) or target_seconds < 0.0:
		return SiteRuntime.fail("INVALID_TIME", "冷來源／固定目標非法")
	var digest := HashingContext.new()
	var started := digest.start(HashingContext.HASH_SHA256)
	if started != OK: return SiteRuntime.fail("SOURCE_HASH", "冷來源校验未啟動")
	# Hash the normalized COMPLETE saved state and verified original base.
	# No 32-bit Dictionary.hash identity, mtime, or separate people/item mirror.
	var encoded := var_to_bytes([data.site, data.parameters.get("fixed_base", {}), data.fingerprint()])
	if digest.update(encoded) != OK: return SiteRuntime.fail("SOURCE_HASH", "冷來源校验未完成")
	return SiteRuntime.ok("", {"site_id": str(data.site.get("id", "")), "source_sha256": digest.finish().hex_encode(),
		"target_game_seconds": target_seconds})

func advance_cold_site(data: TerrainData, target_seconds: float) -> Dictionary:
	var duty := _region_capture_duty_cache()
	var result := _region_advance_original_cold_site(data, target_seconds)
	_region_restore_duty_cache(duty)
	return result

func _region_advance_original_cold_site(data: TerrainData, target_seconds: float) -> Dictionary:
	if data == null or not is_finite(target_seconds) or target_seconds < 0.0:
		return SiteRuntime.fail("INVALID_TIME", "冷地點或固定目標非法")
	var fire_guard := SiteStore.validate_region_snapshot(data, {}) if data.site.has("region_snapshot") else SiteStore.fire_event_guard(data)
	if not fire_guard.ok:
		if str(fire_guard.get("code", "")) == "CORRUPT_REGION_SNAPSHOT": # Diagnostic tags only.
			fire_guard["source"] = "cold_settle"
			fire_guard["site_id"] = str(data.site.get("id", ""))
		return fire_guard
	if get_tree().paused:
		return SiteRuntime.fail("PAUSED_WORLD", "原世界暫停；不建立或推進冷地點候選")
	var source := cold_source_identity(data, target_seconds)
	if not source.ok: return source
	var identity := str(source.site_id)
	var signature := str(source.source_sha256)
	var fire_replay := {}
	if is_instance_valid(_cold_replay_lab):
		if _cold_replay_id != identity or _cold_replay_target != target_seconds or _cold_replay_signature != signature:
			return SiteRuntime.fail("BUSY", "另一原地點／來源／固定目標補算尚未完成")
	else:
		if data.site.has("fire_settlement"):
			if site_controller == null or site_controller.region_slot == null:
				return SiteRuntime.fail("MISSING_FIRE_HISTORY", "冷火場補算缺少原 RegionSaveSlot 時鐘")
			fire_replay = RegionSaveSlot.fire_replay_segments(data.site,
				site_controller.region_slot.control.get("fire_clock", {}), target_seconds)
			if not fire_replay.ok: return fire_replay
		elif not data.site.get("fire", {}).is_empty() or not data.site.get("fire_owners", {}).is_empty():
			return SiteRuntime.fail("MISSING_FIRE_HISTORY", "既有火攻狀態缺少可驗證的雙時間水印")
		var original := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
		if original == null: return SiteRuntime.fail("NO_RUNTIME", "原 TerrainLab 場景不可用")
		_cold_replay_lab = original.instantiate() as TerrainLab
		if data.site.get("actors", {}).has("npc"):
			_cold_replay_lab.npc = TerrainTestNPC.new() # Presenter for this exact saved body; no new person or inventory.
		_cold_replay_lab.restore_only = true
		_cold_replay_lab.simulation_speed = simulation_speed
		_cold_replay_lab.exchange_enabled = exchange_enabled
		_cold_replay_lab.fixed_action_steps_enabled = fixed_action_steps_enabled
		_cold_replay_lab.pause_when_unfocused = false
		_cold_replay_lab.visible = false
		add_child(_cold_replay_lab)
		var restored := _cold_replay_lab.restore_original_site(data)
		if not restored.ok:
			_cold_replay_lab.free()
			_cold_replay_lab = null
			return restored
		_cold_replay_lab._fire_replay_tracking = data.site.has("fire_settlement")
		_cold_replay_lab._fire_replay_epoch = str(data.site.get("fire_settlement", {}).get("epoch", ""))
		var indexed_fire_site: Dictionary = site_controller.region_slot.control.get("fire_clock", {}).get("index", {}).get(identity, {}) if _cold_replay_lab._fire_replay_tracking else {}
		_cold_replay_lab._fire_replay_keep_tactical = bool(indexed_fire_site.get("fire_active", false)) or _cold_replay_lab._fire_activity()
		var replay_segments: Array[Dictionary] = []
		for segment: Variant in fire_replay.get("segments", []):
			if not segment is Dictionary:
				_cold_replay_lab.free()
				_cold_replay_lab = null
				return SiteRuntime.fail("CORRUPT_FIRE_JOURNAL", "原火攻回放區間格式非法")
			replay_segments.append(segment)
		_cold_replay_lab._fire_replay_segments = replay_segments
		_cold_replay_lab._fire_replay_segment_index = 0
		_cold_replay_lab._fire_replay_segment_offset = 0
		_cold_replay_lab._fire_replay_end_sequence = int(fire_replay.get("to_sequence", -1))
		_cold_replay_lab._fire_replay_end_action = float(site_controller.region_slot.control.get("fire_clock", {}).get("action_seconds", 0.0)) if _cold_replay_lab._fire_replay_tracking else 0.0
		_cold_replay_lab._fire_replay_end_game = target_seconds if _cold_replay_lab._fire_replay_tracking else 0.0
		_cold_replay_id = identity
		_cold_replay_target = target_seconds
		_cold_replay_signature = signature
	var advanced: Dictionary = _cold_replay_lab.advance_region_cold_actual_fixed(data, target_seconds, ACTION_FRAME_BUDGET_USEC) \
		if site_controller != null and site_controller.region_slot != null \
		else _cold_replay_lab.replay_site_to(target_seconds, ACTION_FRAME_BUDGET_USEC)
	var cold_receipt := {"method": str(advanced.get("method", "original_shared_exact")),
		"prefix_steps": int(advanced.get("prefix_steps", 0)), "exact_steps": int(advanced.get("exact_steps", advanced.get("steps", 0))),
		"processing_usec": int(advanced.get("processing_usec", 0)), "source_sha256": signature, "target": target_seconds}
	if advanced.ok and str(advanced.status) == "PENDING":
		return {"ok": false, "code": "PENDING", "message": "原地點補算續作中；旅程尚未提交",
			"pending": advanced.pending, "target": target_seconds, "site_id": identity, "source_sha256": signature, "cold_replay": cold_receipt}
	if not advanced.ok:
		if str(advanced.get("code", "")) != "PENDING":
			_cold_replay_lab.free()
			_cold_replay_lab = null
			_cold_replay_id = ""
			_cold_replay_target = -1.0
			_cold_replay_signature = ""
		return advanced
	var completed_data: TerrainData = advanced.data
	if completed_data.site.has("region_snapshot") and site_controller.region_slot != null:
		var admitted := _region_register_replayed_bind_source(data, completed_data, site_controller.region_slot, _cold_replay_lab)
		if not admitted.ok: return admitted
	completed_data.set_meta(&"region_fire_active", _cold_replay_lab._fire_replay_keep_tactical or _cold_replay_lab._fire_activity())
	# Replay already captured and checked the original live save guards.
	# The plain completed candidate must not keep links to the retiring scene.
	for hook: StringName in [&"siege_event_guard", &"fire_event_guard", &"fire_transport_snapshot", &"fire_owner_snapshot",
		&"fire_owner_checkpoint", &"fire_pending_projectile_query", &"site_garrison_lab", &"ship_journey_active",
		&"region_operation_pending", &"ship_vehicle_in_journey"]:
		if completed_data.has_meta(hook): completed_data.remove_meta(hook)
	_cold_replay_lab.free()
	_cold_replay_lab = null
	_cold_replay_id = ""
	_cold_replay_target = -1.0
	_cold_replay_signature = ""
	return SiteRuntime.ok("冷地點已沿原步進結算", {"data": completed_data, "cold_replay": cold_receipt})

func cancel_cold_site_replay(source_sha256: String) -> Dictionary:
	# Only the original pending transaction may retire its uncommitted scene.
	# Input Site/committed files/arriving original crew were never modified.
	if not is_instance_valid(_cold_replay_lab): return SiteRuntime.ok()
	if source_sha256 != _cold_replay_signature:
		return SiteRuntime.fail("STALE_SOURCE", "取消不是這個原冷來源候選")
	_cold_replay_lab.free()
	_cold_replay_lab = null
	_cold_replay_id = ""
	_cold_replay_target = -1.0
	_cold_replay_signature = ""
	return SiteRuntime.ok("已撤回未提交的原補算候選")

# One pool on the original Lab action clock. Owners retain people and cargo.
var physical_ranged_enabled := true
var fire_projectile_capacity := 8192
var fire_projectiles: Array[Dictionary] = []
var fire_reservations: Dictionary = {}
var fire_impact_recorder: Array[Dictionary] = [] # P1 recorder, bounded; P2 consumes ignition.
var fire_ignition_sink: Callable
var fire_action_cursor := 0.0 # Progress on completed original action intervals only.
var _fire_save_guard_active := false
var _fire_release_sequence := 0
var _fire_round_robin := 0
var _fire_member_cursor: Dictionary = {}
var _fire_committing := false
var _fire_advancing := false
var fire_scheduler_result: Dictionary = {} # Last finite admission window; observable without a second queue.
const FIRE_RELEASE_WINDOW_SECONDS := 0.25
var _fire_motion: Dictionary = {}
var _fire_motion_delta := 0.0
var _fire_body_buckets: Dictionary = {}
var _fire_static_buckets: Dictionary = {}

func fire_save_guard(allow_dirty_fire_save: bool = false) -> Dictionary:
	if _fire_save_guard_active: return SiteRuntime.ok()
	_fire_save_guard_active = true
	var result: Dictionary = _fire_save_guard_impl(allow_dirty_fire_save)
	_fire_save_guard_active = false
	return result

func _fire_save_guard_impl(allow_dirty_fire_save: bool) -> Dictionary:
	var history := SiteRuntime.fire_save_guard(terrain)
	if not history.ok: return history
	if terrain == null: return SiteRuntime.ok()
	if not _fire_boundary_error.is_empty(): return _fire_boundary_error.duplicate(true)
	if _fire_committing or _fire_advancing:
		return SiteRuntime.fail("BUSY", "火攻結果尚未到原保存邊界；現場與存檔保留")
	if not allow_dirty_fire_save and (_fire_unsaved or not fire_reservations.is_empty()):
		return SiteRuntime.fail("BUSY", "原 Fire 事件或射擊準備尚未正式保存；保留目前現場與存檔")
	var checkpointed_fire_owners := not allow_dirty_fire_save and fire_owner_snapshot_matches_checkpoint()
	if crowd_site != null and crowd_site.active:
		var crowd_guard: Dictionary = crowd_site.save_guard()
		if not crowd_guard.ok: return crowd_guard
	if site_controller != null:
		var job_guard: Dictionary = site_controller.person_actions.fire_jobs_save_guard(fire_action_cursor) \
			if allow_dirty_fire_save or checkpointed_fire_owners else site_controller.person_actions.save_guard()
		if not job_guard.ok: return job_guard
	if has_unpersisted_ranged_projectiles():
		return SiteRuntime.fail("BUSY", "原非 Fire 投射物仍未到保存邊界")
	for team: TerrainArmy in combat_armies:
		var intent: Dictionary = team.fire_navigation_snapshot()
		if not allow_dirty_fire_save and not checkpointed_fire_owners and team.has_pending_fire_navigation(): return SiteRuntime.fail("BUSY", "原 Army 火場導航尚未具備保存恢復")
		if not allow_dirty_fire_save and not checkpointed_fire_owners \
			and (not intent.get("work", []).is_empty() or not intent.get("hazard", {}).is_empty() or not intent.get("deployment", {}).is_empty()):
			return SiteRuntime.fail("BUSY", "原 Army 火場意圖尚未具備保存恢復")
		if not allow_dirty_fire_save and not checkpointed_fire_owners:
			for batch: Dictionary in intent.get("batches", []):
				if int(batch.get("fire_epoch", 0)) > 0: return SiteRuntime.fail("BUSY", "原 Army 火場移動批次尚未具備保存恢復")
	for owner_ref: Node2D in _fire_transport_owners():
		var fire_owner: Variant = fire_owner_view(owner_ref)
		if fire_owner.ranged_enabled and not fire_owner.ranged_order_authorized(true):
			return SiteRuntime.fail("BUSY", "原射擊命令的指揮權已變更；先收束或重新下令")
	var transport := capture_fire_transport()
	if not transport.ok: return transport
	if allow_dirty_fire_save:
		var fire_owners := capture_fire_owner_state()
		if not fire_owners.ok: return fire_owners
	return SiteRuntime.ok()

func fire_owner_snapshot_matches_checkpoint() -> bool:
	if terrain == null: return false
	var saved: Variant = terrain.get_meta(&"fire_owner_checkpoint", {})
	var captured := capture_fire_owner_state()
	if not captured.ok: return false
	if captured.state.is_empty(): return saved is Dictionary and saved.is_empty()
	if not saved is Dictionary: return false
	var saved_json: Variant = JSON.parse_string(JSON.stringify(saved))
	var captured_json: Variant = JSON.parse_string(JSON.stringify(captured.state))
	return saved_json is Dictionary and captured_json is Dictionary and captured_json == saved_json

func _wire_fire_ranged() -> void:
	if terrain == null: return
	terrain.set_meta(&"fire_event_guard", fire_save_guard)
	terrain.set_meta(&"fire_transport_snapshot", capture_fire_transport)
	terrain.set_meta(&"region_fire_transport_snapshot", capture_region_fire_transport)
	terrain.set_meta(&"fire_owner_snapshot", capture_fire_owner_state)
	terrain.set_meta(&"fire_pending_projectile_query", fire_pending_projectile_query)
	for owner_ref: Node2D in _ranged_owners(): owner_ref.ranged_target_validate = fire_target_validate

func capture_fire_owner_state() -> Dictionary:
	if terrain == null or site_controller == null or not is_instance_valid(site_controller): return SiteRuntime.ok("", {"state":{}})
	var captured_jobs: Dictionary = site_controller.person_actions.export_fire_jobs(fire_action_cursor)
	if not captured_jobs.ok: return captured_jobs
	var by_team := {}
	var team_ids: Array[int] = []
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		var snapshot: Dictionary = team.fire_navigation_snapshot()
		var active: bool = not snapshot.work.is_empty() or not snapshot.hazard.is_empty() or not snapshot.deployment.is_empty()
		for batch: Dictionary in snapshot.batches:
			active = active or int(batch.get("fire_epoch", 0)) > 0
		if team.has_pending_fire_navigation() and not active:
			return SiteRuntime.fail("BUSY", "原 Army 火場導航尚未形成可保存快照")
		if active:
			by_team[team.team_id] = snapshot
			team_ids.append(team.team_id)
	if crowd_site != null and crowd_site.active:
		for owner_ref: CrowdPersonOwner in crowd_site.person_owners():
			if not owner_ref.has_army(): continue
			var snapshot: Dictionary = owner_ref.fire_navigation_snapshot()
			if snapshot.work.is_empty(): continue
			if by_team.has(owner_ref.team_id): return SiteRuntime.fail("DUPLICATE_FIRE_OWNER")
			var guarded: Dictionary = owner_ref.fire_navigation_save_guard()
			if not guarded.ok: return guarded
			by_team[owner_ref.team_id] = snapshot
			team_ids.append(owner_ref.team_id)
	for identity: int in captured_jobs.job_tokens:
		var person: Dictionary = site_controller.person_actions._person(identity, false)
		var owner_ref: Variant = person.get("owner")
		if person.is_empty() or not (owner_ref is TerrainArmy or owner_ref is CrowdPersonOwner): return SiteRuntime.fail("STALE_FIRE_JOB_PERSON")
		if not by_team.has(owner_ref.team_id):
			by_team[owner_ref.team_id] = owner_ref.fire_navigation_snapshot()
			team_ids.append(owner_ref.team_id)
		var matched := false
		for work: Dictionary in by_team[owner_ref.team_id].get("work", []):
			if int(work.get("member_id", -1)) == identity and int(work.get("job_token", -1)) == int(captured_jobs.job_tokens[identity]):
				matched = true
				break
		if not matched:
			return SiteRuntime.fail("MISSING_FIRE_JOB_NAVIGATION")
	if team_ids.is_empty() and captured_jobs.job_tokens.is_empty(): return SiteRuntime.ok("", {"state":{}})
	if combat_movement_coordinator == null: return SiteRuntime.fail("BUSY", "原 Fire Registry 尚未就緒")
	var registry: SiteDeploymentReservationRegistry = combat_movement_coordinator.deployment_registry
	var all_leases: Dictionary = registry.fire_lease_snapshot()
	for lease: Dictionary in all_leases.leases:
		if int(lease.role) != FireMovementTypes.CombatDestinationRole.SUPPRESS_WORK: continue
		var team_id := int(lease.team_id)
		if by_team.has(team_id): continue
		for team: TerrainArmy in combat_armies:
			if team.combat_enabled and team.team_id == team_id:
				by_team[team_id] = team.fire_navigation_snapshot()
				team_ids.append(team_id)
				break
		if not by_team.has(team_id) and crowd_site != null and crowd_site.active:
			for owner_ref: CrowdPersonOwner in crowd_site.person_owners():
				if owner_ref.has_army() and owner_ref.team_id == team_id:
					by_team[team_id] = owner_ref.fire_navigation_snapshot()
					team_ids.append(team_id)
					break
		if not by_team.has(team_id): return SiteRuntime.fail("ORPHAN_FIRE_WORK_LEASE")
		var matching_work := false
		for work: Dictionary in by_team[team_id].get("work", []):
			var identity := int(work.get("member_id", -1))
			if identity == int(lease.member_id) and work.get("slot") == lease.cell \
				and int(work.get("job_token", -1)) == int(captured_jobs.job_tokens.get(identity, -2)):
				matching_work = true
				break
		if not matching_work: return SiteRuntime.fail("ORPHAN_FIRE_WORK_LEASE")
	for snapshot: Dictionary in by_team.values():
		for work: Dictionary in snapshot.get("work", []):
			if not captured_jobs.job_tokens.has(int(work.get("member_id", -1))): return SiteRuntime.fail("ORPHAN_FIRE_JOB_NAVIGATION")
	team_ids.sort()
	if team_ids.is_empty(): return SiteRuntime.ok("", {"state":{}})
	var navigation: Array[Dictionary] = []
	for team_id: int in team_ids: navigation.append({"team_id":team_id,"snapshot":by_team[team_id]})
	var state := {"version":1,"site_id":str(terrain.site.id),"action_cursor":fire_action_cursor,
		"teams":team_ids,"leases":registry.fire_lease_snapshot(team_ids),
		"jobs":captured_jobs.state,"navigation":navigation}
	if not SiteRuntime._fire_snapshot_json(state): return SiteRuntime.fail("CORRUPT_FIRE_OWNER_SNAPSHOT")
	return SiteRuntime.ok("", {"state":state})

func _restore_fire_owners() -> Dictionary:
	var raw: Variant = terrain.site.get("fire_owners", {})
	if not raw is Dictionary or raw.is_empty(): return SiteRuntime.ok()
	var checked := SiteStore._validate_fire_owner_snapshot(terrain, terrain.site, raw, fire_action_cursor)
	if not checked.ok: return checked
	if site_controller == null or combat_movement_coordinator == null: return SiteRuntime.fail("BIND_GUARD", "Fire owner 缺少原 Site/Registry")
	var state: Dictionary = checked.state
	var teams := {}
	for team: TerrainArmy in combat_armies:
		if team.combat_enabled:
			if teams.has(team.team_id): return SiteRuntime.fail("CORRUPT_FIRE_OWNER")
			teams[team.team_id] = team
	if crowd_site != null and crowd_site.active:
		for owner_ref: CrowdPersonOwner in crowd_site.person_owners():
			if not owner_ref.has_army(): continue
			if teams.has(owner_ref.team_id): return SiteRuntime.fail("CORRUPT_FIRE_OWNER")
			teams[owner_ref.team_id] = owner_ref
	var returning: Array = state.teams.duplicate()
	for team_id: int in returning:
		if not teams.has(team_id): return SiteRuntime.fail("CORRUPT_FIRE_OWNER", "Fire 導航失去原隊伍")
	var registry: SiteDeploymentReservationRegistry = combat_movement_coordinator.deployment_registry
	var leases: Dictionary = registry.prepare_fire_lease_restore(state.leases, returning, terrain)
	if not leases.ok: return SiteRuntime.fail(str(leases.get("reason", "INVALID_FIRE_LEASE_SNAPSHOT")))
	var jobs_checked: Dictionary = site_controller.person_actions.validate_fire_jobs_snapshot(state.jobs, fire_action_cursor)
	if not jobs_checked.ok: return jobs_checked
	var prepared_by_team := {}
	for row: Dictionary in state.navigation:
		var team: Variant = teams[int(row.team_id)]
		var prepared: Dictionary = team.prepare_fire_navigation_restore(row.snapshot, leases.candidate,
			registry, jobs_checked.job_tokens, fire_action_cursor) if team is CrowdPersonOwner \
			else team.prepare_fire_navigation_restore(row.snapshot, leases.candidate, jobs_checked.job_tokens, fire_action_cursor)
		if not prepared.ok: return prepared
		prepared_by_team[int(row.team_id)] = prepared
	var prepared_jobs: Dictionary = site_controller.person_actions.prepare_restore_fire_jobs(state.jobs,
		prepared_by_team, leases.candidate, fire_action_cursor)
	if not prepared_jobs.ok: return prepared_jobs
	var published_registry: Dictionary = registry.publish_handoff(leases)
	if not published_registry.ok: return SiteRuntime.fail(str(published_registry.get("reason", "FIRE_REGISTRY_PUBLISH")))
	for team_id: int in state.teams:
		if not teams[team_id].can_publish_fire_navigation_restore(prepared_by_team[team_id], registry):
			registry.restore_handoff_state(published_registry.rollback)
			return SiteRuntime.fail("STALE_FIRE_RESTORE")
	if not site_controller.person_actions.can_publish_restore_fire_jobs(prepared_jobs, registry):
		registry.restore_handoff_state(published_registry.rollback)
		return SiteRuntime.fail("STALE_FIRE_JOB_RESTORE")
	for team_id: int in state.teams:
		var restored: Dictionary = teams[team_id].publish_fire_navigation_restore(prepared_by_team[team_id], registry)
		if not restored.ok: return restored
	var restored_jobs: Dictionary = site_controller.person_actions.publish_restore_fire_jobs(prepared_jobs, registry)
	if restored_jobs.ok: terrain.set_meta(&"fire_owner_checkpoint", state.duplicate(true))
	return restored_jobs

func _prepare_fire_transport_restore() -> Dictionary:
	var fire_state: Variant = terrain.site.get("fire", {})
	var pending_action_cursor := -1.0
	if terrain.site.has("region_snapshot"):
		var region: Dictionary = RegionCheckpoint.validate(terrain.site, terrain.site.region_snapshot)
		if not region.ok: return region
		pending_action_cursor = SiteStore._region_pending_fire_cursor(terrain.site, region.context, region.owners)
	var checked := SiteStore._validate_fire_transport_snapshot(terrain, fire_state if fire_state is Dictionary else {}, terrain.site.get("fire_transport", {}), pending_action_cursor)
	if not checked.ok: return checked
	var state: Dictionary = checked.state
	if state.is_empty(): return SiteRuntime.ok("", {"prepared": {}})
	var owners := {}
	for owner_ref: Node2D in _fire_transport_owners():
		var group := int(owner_ref.team_id) if owner_ref is TerrainArmy else -int(owner_ref.combat_identity())
		if owners.has(group): return SiteRuntime.fail("CORRUPT_FIRE_OWNER")
		owners[group] = owner_ref
	if owners.size() != state.orders.size(): return SiteRuntime.fail("CORRUPT_FIRE_OWNER", "原射擊命令與保存的人物名冊不相符")
	for group: int in state.orders:
		if not owners.has(group): return SiteRuntime.fail("CORRUPT_FIRE_OWNER", "原射擊命令失去人物／隊伍擁有者")
		var owner_ref: Node2D = owners[group]
		var order: Dictionary = state.orders[group]
		if owner_ref is TerrainTestCharacter and bool(order.enabled) and int(order.issuer_id) != owner_ref.person_id:
			return SiteRuntime.fail("CORRUPT_FIRE_ORDER_AUTHORITY")
		if owner_ref is TerrainArmy:
			for identity: int in order.release_ids:
				if owner_ref.index_for_identity(identity) < 0: return SiteRuntime.fail("CORRUPT_FIRE_RELEASE_OWNER")
		else:
			for identity: int in order.release_ids:
				if identity != owner_ref.combat_identity(): return SiteRuntime.fail("CORRUPT_FIRE_RELEASE_OWNER")
		if bool(order.enabled) and bool(state.physical_ranged_enabled):
			var target := fire_target_validate(owner_ref, order.target, str(order.mode))
			if not target.ok: return target
		if owner_ref is TerrainArmy and not order.ranged_fire_policy.is_empty() \
			and int(order.ranged_fire_policy.main_serial) != owner_ref.get_order_serial():
			return SiteRuntime.fail("CORRUPT_FIRE_POLICY_OWNER")
	var people := {}
	if not state.reservations.is_empty():
		for person: Dictionary in _siege_people(): people[int(person.id)] = person
	var restored_reservations := {}
	for identity: int in state.reservations:
		var reservation: Dictionary = state.reservations[identity]
		if not people.has(identity): return SiteRuntime.fail("CORRUPT_FIRE_PREPARATION_OWNER")
		var person: Dictionary = people[identity]
		var owner_ref: Node2D = person.owner
		var expected_team := int(owner_ref.team_id) if owner_ref is TerrainArmy else 0
		if expected_team != int(reservation.formation_id) or _fire_holder_stamp(person) != reservation.stamp \
			or not _fire_person_ready(person, true): return SiteRuntime.fail("STALE_FIRE_PREPARATION")
		var order_group := expected_team if expected_team > 0 else -identity
		var order: Dictionary = state.orders.get(order_group, {})
		if order.is_empty() or not bool(order.enabled) or int(order.serial) != int(reservation.serial) \
			or str(order.mode) != str(reservation.mode) or order.target != reservation.target:
			return SiteRuntime.fail("STALE_FIRE_PREPARATION")
		var runtime_reservation := reservation.duplicate(true)
		runtime_reservation["person"] = person.duplicate()
		restored_reservations[identity] = runtime_reservation
	return SiteRuntime.ok("", {"prepared": {"state": state, "owners": owners, "reservations": restored_reservations}})

func _publish_fire_transport_restore(prepared: Dictionary) -> Dictionary:
	if not prepared.is_empty() and (not prepared.get("state") is Dictionary or not prepared.get("owners") is Dictionary
		or not prepared.get("reservations") is Dictionary): return SiteRuntime.fail("INVALID_FIRE_TRANSPORT_RESTORE")
	fire_projectiles.clear()
	fire_reservations.clear()
	physical_ranged_enabled = true
	_fire_release_sequence = 0
	_fire_exposure_sequence = 0
	_fire_round_robin = 0
	_fire_member_cursor.clear()
	if prepared.is_empty(): return SiteRuntime.ok()
	var state: Dictionary = prepared.state
	var owners: Dictionary = prepared.owners
	for group: int in state.orders:
		var owner_ref: Node2D = owners[group]
		var order: Dictionary = state.orders[group]
		owner_ref.ranged_order_serial = int(order.serial)
		owner_ref.ranged_order_issuer_id = int(order.issuer_id)
		owner_ref.ranged_enabled = bool(order.enabled)
		owner_ref.ranged_ammo_mode = str(order.mode)
		owner_ref.ranged_target = order.target.duplicate(true)
		owner_ref.ranged_fire_policy = order.ranged_fire_policy.duplicate(true)
		if owner_ref is TerrainArmy:
			owner_ref._ranged_last_release_ids = order.release_ids.duplicate()
		else:
			owner_ref._ranged_last_release_id = int(order.release_ids.get(owner_ref.combat_identity(), 0))
	physical_ranged_enabled = bool(state.physical_ranged_enabled)
	fire_action_cursor = float(state.action_cursor)
	terrain.set_meta(&"fire_completed_action_end", fire_action_cursor)
	for flight: Dictionary in state.projectiles: fire_projectiles.append(flight.duplicate(true))
	for identity: int in prepared.reservations: fire_reservations[identity] = prepared.reservations[identity]
	_fire_release_sequence = int(state.release_sequence)
	_fire_exposure_sequence = int(state.exposure_sequence)
	_fire_round_robin = int(state.round_robin)
	_fire_member_cursor = state.member_cursor.duplicate()
	return SiteRuntime.ok()

func fire_owner_view(source_owner: Variant) -> Variant:
	if not source_owner is TerrainArmy or crowd_site == null or not crowd_site.fire_host_active(): return source_owner
	for person_owner: CrowdPersonOwner in crowd_site.person_owners():
		if is_same(person_owner._order_owner(), source_owner): return person_owner
	return source_owner

func _fire_owner_source(owner_ref: Variant) -> Variant:
	return owner_ref._order_owner() if owner_ref is CrowdPersonOwner else owner_ref

func issue_fire_order(requester: int, owner_ref: Node2D, target: Dictionary, ammo_mode: String = "NORMAL", policy: String = "CONTINUOUS", service: String = "") -> Dictionary:
	if owner_ref not in _ranged_owners(): return SiteRuntime.fail("NO_TARGET")
	if policy not in ["CONTINUOUS", "IGNITE_ONLY", "DESTROY_FUNCTION"] or service not in ["", "lodging", "intake", "production", "water", "garrison", "recovery", "training"]: return SiteRuntime.fail("INVALID_FIRE_POLICY")
	if policy != "CONTINUOUS" and (ammo_mode != "FIRE_ARROW" or str(target.get("type", "")) not in ["structure", "ground", "area"]): return SiteRuntime.fail("INVALID_FIRE_POLICY")
	if policy == "DESTROY_FUNCTION" and str(target.get("type", "")) != "structure": return SiteRuntime.fail("INVALID_FIRE_POLICY")
	_wire_fire_ranged()
	var fire_owner: Variant = fire_owner_view(owner_ref)
	var result: Dictionary = fire_owner.issue_ranged_order(requester, target, ammo_mode) if fire_owner is TerrainArmy or fire_owner is CrowdPersonOwner else fire_owner.issue_ranged_order(target, ammo_mode)
	if result.ok and policy != "CONTINUOUS":
		var source: Variant = _fire_owner_source(fire_owner)
		fire_owner.ranged_fire_policy = {"version": "fire_policy_v1", "serial": int(fire_owner.ranged_order_serial),
			"main_serial": source.get_order_serial() if source is TerrainArmy else 0, "mode": policy, "service": service,
			"last_decision_step": -1, "allow": true, "reason": "EVALUATING", "confirmations": {},
			"wait_deadline": fire_action_cursor, "pending_threshold": 100.0 if str(target.type) == "structure" else 40.0,
			"pending_estimate": {}}
	return result

func stop_fire_order(requester: int, owner_ref: Node2D) -> Dictionary:
	if owner_ref not in _ranged_owners(): return SiteRuntime.fail("NO_TARGET")
	var fire_owner: Variant = fire_owner_view(owner_ref)
	var result: Dictionary = fire_owner.stop_ranged_order(requester) if fire_owner is TerrainArmy or fire_owner is CrowdPersonOwner else fire_owner.stop_ranged_order()
	if result.ok:
		for identity: int in fire_reservations.keys():
			if is_same(_fire_owner_source(fire_reservations[identity].person.owner), owner_ref): fire_reservations.erase(identity)
	return result

func fire_target_validate(_owner: Variant, target: Dictionary, ammo_mode: String) -> Dictionary:
	if not physical_ranged_enabled or not exchange_enabled or terrain == null: return SiteRuntime.fail("UNSUPPORTED_AMMO")
	if crowd_site != null and crowd_site.active and not crowd_site.fire_host_active(): return SiteRuntime.fail("UNSUPPORTED_AMMO", "原生新箭矢尚未准入，原人與原物保留")
	if ammo_mode not in ["NORMAL", "FIRE_ARROW"]: return SiteRuntime.fail("UNSUPPORTED_AMMO")
	var aim := _fire_target_aim(target)
	return SiteRuntime.fail("NO_VALID_AIM_POINT") if aim.is_empty() else SiteRuntime.ok("", {"cell": aim.cell})

func _fire_target_aim(target: Dictionary, identity: int = 0) -> Dictionary:
	if terrain == null: return {}
	var kind := str(target.get("type", ""))
	if kind == "area":
		var values: Variant = target.get("cells")
		if not values is Array or values.is_empty() or values.size() > 256: return {}
		for value: Variant in values:
			if not value is Array or value.size() != 2 or not value[0] is int or not value[1] is int or not terrain.contains(Vector2i(value[0], value[1])): return {}
		var value: Array = values[posmod(identity, values.size())]
		var cell := Vector2i(value[0], value[1])
		return {"cell": cell, "point": Vector3(cell.x + 0.5, cell.y + 0.5, float(terrain.height_levels[terrain.index(cell)]) + 0.05), "moving": false, "key": "ground:%d" % terrain.index(cell)}
	if kind == "person":
		if not target.get("person_id") is int or int(target.person_id) <= 0: return {}
		var person := _combat_target(int(target.person_id))
		if person.is_empty() or _ship_person_in_journey(int(target.person_id)): return {}
		var owner_ref: Variant = person.owner
		var unit := int(person.unit)
		if not is_instance_valid(owner_ref): return {}
		var hp := float(owner_ref.combat_hot_get(unit, &"hp", 0.0)) if unit >= 0 else float(owner_ref.hp)
		if hp <= 0.0: return {}
		var ground: Vector2 = owner_ref.combat_ground(unit) if unit >= 0 else owner_ref.position
		var cell := Vector2i((ground / TerrainRenderer.CELL_PIXELS).floor())
		if not terrain.contains(cell): return {}
		var defense: Dictionary = owner_ref.ranged_defense(unit) if unit >= 0 else owner_ref.ranged_defense()
		return {"cell": cell, "point": Vector3(ground.x / TerrainRenderer.CELL_PIXELS, ground.y / TerrainRenderer.CELL_PIXELS, _fire_surface_height(ground) + 1.0),
			"moving": bool(defense.get("moving", false)), "key": "person:%d" % int(target.person_id)}
	if kind in ["ground", "structure"]:
		if kind == "ground":
			var values: Variant = target.get("cell")
			if not values is Array or values.size() != 2 or not values[0] is int or not values[1] is int: return {}
		if kind == "structure" and (not target.get("feature_id") is String or not target.get("part_id") is String): return {}
		var aim := siege_target(target)
		if aim.is_empty(): return {}
		var cell := Vector2i((aim.point as Vector2).floor())
		if not terrain.contains(cell): return {}
		var height := float(aim.height)
		if kind == "ground": height = float(terrain.height_levels[terrain.index(cell)]) + 0.05
		return {"cell": cell, "point": Vector3(aim.point.x, aim.point.y, height), "moving": false,
			"key": "structure:%s:%s" % [target.feature_id, target.part_id] if kind == "structure" else "ground:%d" % terrain.index(cell)}
	return {}

func _fire_person_ready(person: Dictionary, ignore_pause: bool = false) -> bool:
	var owner_ref: Variant = person.get("owner")
	var unit := int(person.get("unit", -2))
	var identity := int(person.get("id", 0))
	if not is_instance_valid(owner_ref) or terrain == null or owner_ref.data != terrain: return false
	if owner_ref is CrowdPersonOwner:
		if unit < 0 or not owner_ref.is_member(unit) or owner_ref.combat_identity(unit) != identity: return false
	elif owner_ref is TerrainArmy:
		if unit < 0 or unit >= owner_ref.combat_units.size() or owner_ref.combat_identity(unit) != identity: return false
	elif not owner_ref is TerrainTestCharacter or unit != -1 or owner_ref.combat_identity() != identity:
		return false
	if not ignore_pause and (bool(terrain.site.get("paused", false)) or is_inside_tree() and get_tree().paused): return false
	if owner_ref.ranged_enabled and not owner_ref.ranged_order_authorized(ignore_pause): return false
	if not (owner_ref.exchange_ready(unit) if unit >= 0 else owner_ref.exchange_ready()): return false
	if (float(owner_ref.combat_hot_get(unit, &"ranged_cooldown", 0.0)) if unit >= 0 else float(owner_ref.ranged_cooldown)) > ACTION_TIME_EPSILON: return false
	if unit >= 0 and (owner_ref.combat_order in [TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.RETREAT, TerrainArmy.CombatOrder.RETURN] or owner_ref.is_sustain_routed()): return false
	if site_controller != null and site_controller._person_has_duty(identity): return false
	if owner_ref is CrowdPersonOwner and site_controller != null and site_controller.native_held_actual_work_person(identity): return false
	return true

func _fire_holder_stamp(person: Dictionary) -> Dictionary:
	var owner_ref: Variant = person.owner
	var holder: Dictionary = owner_ref.combat_hot_get(int(person.unit), &"item_state", {}) if owner_ref is CrowdPersonOwner else (owner_ref.combat_units[int(person.unit)].get("item_state", {}) if int(person.unit) >= 0 else owner_ref.item_state)
	var cargo: Dictionary = owner_ref.combat_hot_get(int(person.unit), &"cargo", {}) if owner_ref is CrowdPersonOwner else (owner_ref.combat_units[int(person.unit)].get("cargo", {}) if int(person.unit) >= 0 else owner_ref.ammo_inventory)
	return {"holder": str(holder.get("holder", "")), "version": int(holder.get("version", 0)), "cargo": cargo.duplicate(true)}

func request_fire_release(person: Dictionary, target: Dictionary, draft: Dictionary = {}) -> Dictionary:
	if site_controller != null and site_controller._region_departure_defers_person(int(person.get("id", 0))): return SiteRuntime.fail("SCHEDULER_DEFERRED", "離場意圖僅暫緩新射擊預約")
	if _fire_committing or _fire_advancing: return SiteRuntime.fail("SCHEDULER_DEFERRED", "原發射／接觸提交中；下個原決策窗口再試")
	if draft.is_empty(): _wire_fire_ranged()
	var reservations: Dictionary = fire_reservations if draft.is_empty() else draft.reservations
	var identity := int(person.get("id", 0))
	if identity <= 0 or reservations.has(identity): return SiteRuntime.fail("SCHEDULER_DEFERRED")
	if not _fire_person_ready(person): return SiteRuntime.fail("SCHEDULER_DEFERRED")
	if not _fire_policy_allows(person, target, draft):
		_fire_policy_cancel_unreleased(person.owner, draft)
		return SiteRuntime.fail("POLICY_WAIT", "依射擊目標暫停下一輪；已發箭繼續飛行")
	var owner_ref: Variant = person.owner
	var mode := str(owner_ref.ranged_ammo_mode)
	var valid := fire_target_validate(owner_ref, target, mode)
	if not valid.ok: return valid
	var shooter: Dictionary = owner_ref.exchange_stats(int(person.unit)) if int(person.unit) >= 0 else owner_ref.exchange_stats()
	var profile := SiteCombatRules.fire_ranged_profile(str(shooter.weapon), mode)
	if profile.is_empty(): return SiteRuntime.fail("UNSUPPORTED_AMMO")
	var aim := _fire_target_aim(target, identity)
	if aim.is_empty(): return SiteRuntime.fail("NO_VALID_AIM_POINT")
	var source: Vector2i = owner_ref._combat_attack_cell(int(person.unit)) if int(person.unit) >= 0 else owner_ref.terrain_cell
	if not SiteCombatRules.ranged_in_range(source, aim.cell, float(profile.range)): return SiteRuntime.fail("OUT_OF_RANGE")
	var stamp := _fire_holder_stamp(person)
	if int(stamp.cargo.get(str(profile.ammo), 0)) < 1: return SiteRuntime.fail("NO_AMMO")
	if fire_projectiles.size() + reservations.size() >= fire_projectile_capacity: return SiteRuntime.fail("CAPACITY_DEFERRED")
	reservations[identity] = {"person": person.duplicate(), "target": target.duplicate(true), "mode": mode,
		"serial": int(owner_ref.ranged_order_serial), "stamp": stamp, "source": source,
		"ready_at": fire_action_cursor + float(profile.prepare), "deadline": fire_action_cursor + float(profile.prepare) + FIRE_RELEASE_WINDOW_SECONDS}
	return SiteRuntime.ok("已準備；尚未扣本人彈藥", {"person_id": identity, "ready_at": reservations[identity].ready_at, "deadline": reservations[identity].deadline})

func _resolve_physical_ranged_fire(people: Array[Dictionary], draft: Dictionary = {}) -> Dictionary:
	if _fire_committing or _fire_advancing: return SiteRuntime.fail("SCHEDULER_DEFERRED", "原提交中；未新增預約")
	if draft.is_empty(): _wire_fire_ranged()
	var reservations: Dictionary = fire_reservations if draft.is_empty() else draft.reservations
	var member_cursor: Dictionary = _fire_member_cursor if draft.is_empty() else draft.member_cursor
	var round_robin: int = _fire_round_robin if draft.is_empty() else int(draft.round_robin)
	if not physical_ranged_enabled or terrain == null or crowd_site != null and crowd_site.active and not crowd_site.fire_host_active():
		return SiteRuntime.fail("UNSUPPORTED_AMMO")
	_advance_fire_policy_decisions(people, draft)
	var groups := {}
	var present_groups := {}
	for person: Dictionary in people:
		var owner_ref: Variant = person.owner
		var group := int(owner_ref.team_id) if owner_ref is TerrainArmy or owner_ref is CrowdPersonOwner and owner_ref.has_army() else -int(person.id)
		present_groups[group] = true
		if site_controller != null and site_controller._region_departure_defers_person(int(person.id)): continue
		if reservations.has(int(person.id)) or not _fire_person_ready(person): continue
		var profile: Dictionary = owner_ref.ranged_profile(int(person.unit), str(owner_ref.ranged_ammo_mode)) if int(person.unit) >= 0 else owner_ref.ranged_profile(str(owner_ref.ranged_ammo_mode))
		if profile.is_empty(): continue
		var cargo: Dictionary = owner_ref.combat_hot_get(int(person.unit), &"cargo", {}) if owner_ref is CrowdPersonOwner else (owner_ref.combat_units[int(person.unit)].get("cargo", {}) if int(person.unit) >= 0 else owner_ref.ammo_inventory)
		if int(cargo.get(str(profile.ammo), 0)) < 1: continue
		if not groups.has(group): groups[group] = []
		groups[group].append(person)
	for group: int in member_cursor.keys():
		if not present_groups.has(group): member_cursor.erase(group)
	var keys: Array = groups.keys()
	keys.sort()
	var starts := {}
	var scanned := {}
	var remaining := 0
	for group: int in keys:
		var members: Array = groups[group]
		members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
		var start := 0
		while start < members.size() and int(members[start].id) <= int(member_cursor.get(group, -1)): start += 1
		starts[group] = start % members.size()
		scanned[group] = 0
		remaining += members.size()
	var summary := {"granted": 0, "deferred": 0, "codes": {}, "window_begin": fire_action_cursor,
		"window_end": fire_action_cursor + FIRE_RELEASE_WINDOW_SECONDS}
	var friendly := _ranged_friendly_cells()
	while remaining > 0:
		if fire_projectiles.size() + reservations.size() >= fire_projectile_capacity:
			summary.deferred += remaining
			summary.codes["CAPACITY_DEFERRED"] = int(summary.codes.get("CAPACITY_DEFERRED", 0)) + remaining
			break
		var group_start := round_robin % keys.size()
		for turn in range(keys.size()):
			var group_index := (group_start + turn) % keys.size()
			var group: int = keys[group_index]
			var members: Array = groups[group]
			while int(scanned[group]) < members.size():
				if fire_projectiles.size() + reservations.size() >= fire_projectile_capacity: break
				var person: Dictionary = members[(int(starts[group]) + int(scanned[group])) % members.size()]
				scanned[group] = int(scanned[group]) + 1
				remaining -= 1
				var owner_ref: Variant = person.owner
				var profile: Dictionary = owner_ref.ranged_profile(int(person.unit), str(owner_ref.ranged_ammo_mode)) if int(person.unit) >= 0 else owner_ref.ranged_profile(str(owner_ref.ranged_ammo_mode))
				if profile.is_empty() or not _fire_person_ready(person): continue
				var target: Dictionary = owner_ref.ranged_target.duplicate(true) if owner_ref.ranged_enabled else {}
				if target.is_empty():
					var nearest := INF
					var adjacent := false
					var selected := {}
					var allies: Dictionary = friendly.get(int(person.faction), {})
					for other: Dictionary in people:
						if int(other.faction) == int(person.faction): continue
						var distance := Vector2(other.cell - person.cell).length_squared()
						if distance > maxf(1.0, float(profile.range) * float(profile.range)): continue
						if not (other.owner.combat_can_act(int(other.unit)) if int(other.unit) >= 0 else other.owner.can_act()): continue
						if _combat_melee_clear(int(person.id), int(other.id), person.cell, other.cell): adjacent = true; break
						if distance <= 1.0 or distance >= nearest or not _exchange_initiates(person, int(other.id)): continue
						if not SiteCombatRules.ranged_friendly_clear(person.cell, other.cell, allies, terrain) or not _person_ranged_line_clear(int(person.id), person.cell, other.cell): continue
						selected = other
						nearest = distance
					if adjacent or selected.is_empty(): continue
					target = {"type": "person", "person_id": int(selected.id)}
				var result := request_fire_release(person, target, draft)
				if result.ok:
					summary.granted += 1
					member_cursor[group] = int(person.id)
					round_robin = (group_index + 1) % keys.size()
					break # One grant per group before another group gets its turn.
				summary.deferred += 1
				var code := str(result.get("code", "SCHEDULER_DEFERRED"))
				summary.codes[code] = int(summary.codes.get(code, 0)) + 1
	var result: Dictionary = SiteRuntime.ok("原有限射擊窗口已排程", summary)
	if draft.is_empty():
		_fire_round_robin = round_robin
		fire_scheduler_result = result
	else:
		draft.round_robin = round_robin
		draft.scheduler_result = result
	return result.duplicate(true)

func _commit_fire_releases(draft: Dictionary = {}) -> void:
	if _fire_committing or _fire_advancing or not physical_ranged_enabled or terrain == null: return
	if draft.is_empty(): _fire_committing = true
	var reservations: Dictionary = fire_reservations if draft.is_empty() else draft.reservations
	var sequence: int = _fire_release_sequence if draft.is_empty() else int(draft.sequence)
	var ids: Array = reservations.keys()
	ids.sort()
	for identity: int in ids:
		if not reservations.has(identity): continue
		var reservation: Dictionary = reservations[identity]
		var person: Dictionary = reservation.person
		var owner_ref: Variant = person.owner
		if _fire_person_ready(person) and not _fire_policy_allows(person, reservation.target, draft):
			_fire_policy_cancel_unreleased(owner_ref, draft)
			continue
		if not _fire_person_ready(person) or int(owner_ref.ranged_order_serial) != int(reservation.serial) or str(owner_ref.ranged_ammo_mode) != str(reservation.mode) or _fire_holder_stamp(person) != reservation.stamp:
			reservations.erase(identity)
			continue
		if owner_ref.ranged_enabled:
			if owner_ref.ranged_target != reservation.target: reservations.erase(identity); continue
		elif str(reservation.target.get("type", "")) != "person" or not _exchange_initiates(person, int(reservation.target.person_id)):
			reservations.erase(identity)
			continue
		if fire_action_cursor > float(reservation.deadline) + ACTION_TIME_EPSILON: reservations.erase(identity); continue
		if fire_action_cursor + ACTION_TIME_EPSILON < float(reservation.ready_at): continue
		# Runtime receipts use signed 32-bit positive projectile IDs. Cancel only
		# this ready reservation before any original skill/ammo/cooldown commit.
		if sequence >= 2147483647:
			reservations.erase(identity)
			var exhausted: Dictionary = SiteRuntime.fail("PROJECTILE_ID_EXHAUSTED", "原投射物識別已達收據上限；未扣彈")
			exhausted.person_id = identity
			if draft.is_empty(): fire_scheduler_result = exhausted
			else: draft.scheduler_result = exhausted
			continue
		if fire_projectiles.size() + (0 if draft.is_empty() else draft.releases.size()) >= fire_projectile_capacity: continue
		var source: Vector2i = owner_ref._combat_attack_cell(int(person.unit)) if int(person.unit) >= 0 else owner_ref.terrain_cell
		if source != reservation.source: reservations.erase(identity); continue
		var geometry: Dictionary = _prepare_fire_release_flight(person, reservation, sequence + 1)
		if geometry.is_empty(): reservations.erase(identity); continue
		var aim: Dictionary = geometry.aim
		var profile: Dictionary = geometry.profile
		var flight: Dictionary = geometry.flight
		var origin: Vector3 = geometry.origin
		var nominal: Vector3 = geometry.nominal
		var right: Vector3 = geometry.right
		var up: Vector3 = geometry.up
		var offset: Vector2
		var auto_power: bool = bool(geometry.auto_power)
		var ground: Vector2 = geometry.ground
		if not draft.is_empty():
			if not owner_ref is CrowdPersonOwner:
				draft.error = SiteRuntime.fail("NATIVE_BEGIN_NON_NATIVE_RELEASE")
				return
			var release: Dictionary = owner_ref.prepare_host_ranged_release(int(person.unit), aim.cell, sequence + 1, str(reservation.mode), auto_power)
			if not release.ok:
				draft.error = release
				return
			draft.releases.append({"identity": identity, "person": person, "reservation": reservation,
				"release": release, "geometry": geometry})
			reservations.erase(identity)
			sequence += 1
			continue
		# The original owner performs its final guards, optional skill and ammo commit together.
		# Remove this reservation before its callback; the guard prevents reentrant admissions.
		reservations.erase(identity)
		var released: Dictionary = owner_ref.ranged_release(int(person.unit), aim.cell, sequence + 1, str(reservation.mode), auto_power) if int(person.unit) >= 0 else owner_ref.ranged_release(aim.cell, sequence + 1, str(reservation.mode), auto_power)
		if released.is_empty(): continue
		# Preflight already validated the finite trajectory inputs. Power only changes scatter;
		# use the actual original-owner shooter snapshot after its atomic commit.
		offset = SiteCombatRules.fire_aim_offset(released.shooter, float(profile.nominal_distance), bool(aim.moving), terrain.seed_value, identity, int(reservation.serial), sequence + 1, float(profile.scatter_multiplier))
		flight.velocity = (nominal + right * offset.x + up * offset.y - origin) / float(flight.total) + Vector3(0, 0, 0.5 * float(profile.gravity) * float(flight.total))
		sequence += 1
		var source_formation_id := int(owner_ref.team_id) if owner_ref is TerrainArmy or owner_ref is CrowdPersonOwner and owner_ref.has_army() else 0
		flight.merge({"projectile_id": sequence, "source_member_id": identity, "source_formation_id": source_formation_id,
			"order_serial": int(reservation.serial), "spawn_action": fire_action_cursor, "source_cell": reservation.source,
			"shooter": released.shooter, "profile": profile, "elapsed": 0.0, "ember": float(profile.ember), "resolved": false,
			"aim_key": str(aim.key), "position": origin, "config_version": str(profile.config_version)})
		fire_projectiles.append(flight)
		_fire_unsaved = true
		ranged_shots += 1
	if draft.is_empty():
		_fire_release_sequence = sequence
		_fire_committing = false
		queue_redraw()
	else: draft.sequence = sequence

func _fire_screen(point: Vector3, source_ground: float) -> Vector2:
	return Vector2(point.x, point.y) * TerrainRenderer.CELL_PIXELS - Vector2(0, 48.0 * (point.z - source_ground))

func _fire_surface_height(ground: Vector2, natural: bool = false) -> float:
	# Match the original surface interpolation across legal navigation edges.
	var grid := ground / TerrainRenderer.CELL_PIXELS
	var cell := Vector2i(grid.floor())
	if not terrain.contains(cell): return -1.0
	var base := float(terrain.height_levels[terrain.index(cell)]) if natural else float(terrain.effective_height(cell))
	var height := base
	var local := grid - Vector2(cell) - Vector2.ONE * 0.5
	for offset: Vector2i in [Vector2i(int(signf(local.x)), 0), Vector2i(0, int(signf(local.y)))]:
		if offset != Vector2i.ZERO and terrain.can_step(cell, cell + offset):
			var neighbor := float(terrain.height_levels[terrain.index(cell + offset)]) if natural else float(terrain.effective_height(cell + offset))
			height += (neighbor - base) * (absf(local.x) if offset.x != 0 else absf(local.y))
	return height

func _fire_owner_motion(person: Dictionary) -> Dictionary:
	var owner_ref: Variant = person.owner
	var unit := int(person.unit)
	if owner_ref is CrowdPersonOwner:
		return {"native_segment": PackedVector2Array()}
	if unit >= 0:
		if owner_ref.moving_to[unit] == TerrainArmy.INVALID_CELL: return {}
		return {"from": (Vector2(owner_ref.cells[unit]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS,
			"to": (Vector2(owner_ref.moving_to[unit]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS,
			"progress": float(owner_ref.move_progress[unit]), "duration": float(owner_ref.move_duration[unit]),
			"curve": int(owner_ref.move_curve[unit]), "linear": false, "ride": false}
	if not owner_ref.is_moving(): return {}
	return {"from": owner_ref._movement_start, "to": (Vector2(owner_ref.terrain_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS,
		"progress": float(owner_ref._movement_elapsed) / float(owner_ref._movement_duration), "duration": float(owner_ref._movement_duration),
		"curve": 0, "linear": bool(owner_ref._movement_linear), "ride": bool(owner_ref._movement_ride),
		"start_speed": float(owner_ref._ride_start_speed), "end_speed": float(owner_ref._ride_end_speed)}

func _fire_motion_ground(person: Dictionary, fraction: float) -> Vector2:
	var motion: Dictionary = person.motion
	if motion.is_empty(): return (person.ground as Vector2).lerp(person.get("end_ground", person.ground), fraction)
	if motion.has("native_segment"):
		var segment: PackedVector2Array = motion.native_segment
		return segment[0].lerp(segment[1], fraction)
	var progress := TerrainArmy.CombatTimings.advance_movement_progress(float(motion.progress), _fire_motion_delta * fraction, float(motion.duration))
	var weight := progress if bool(motion.linear) else TerrainArmy.CombatTimings.movement_weight(progress, int(motion.curve) == 1)
	if bool(motion.ride):
		weight = TerrainTestCharacter.riding_weight(progress, float(motion.start_speed), float(motion.end_speed), float(motion.duration), (motion.from as Vector2).distance_to(motion.to) / TerrainRenderer.CELL_PIXELS)
	return (motion.from as Vector2).lerp(motion.to, weight)

func _capture_fire_motion() -> void:
	_fire_motion.clear()
	_fire_body_buckets.clear()
	_fire_motion_delta = 0.0
	_capture_fire_exposure_candidates()
	if fire_projectiles.is_empty(): return
	for person: Dictionary in _siege_people():
		var geometry: Dictionary = person.owner.incoming_geometry(int(person.unit)) if int(person.unit) >= 0 else person.owner.incoming_geometry(true)
		var radius := 0.0
		# Army incoming geometry uses its original navigation origin; the Actor's
		# live sprite projection already includes its original surface offset.
		var anchor: Vector2 = person.ground + (terrain.surface_visual_offset_at(person.ground) if int(person.unit) < 0 else Vector2.ZERO)
		for kind: String in ["body", "shield"]:
			for polygon: PackedVector2Array in geometry[kind]:
				for vertex: Vector2 in polygon: radius = maxf(radius, vertex.distance_to(anchor))
		if radius <= 0.0: continue
		person["geometry"] = geometry
		person["anchor"] = anchor
		person["radius"] = radius
		person["motion"] = _fire_owner_motion(person)
		person["exposure"] = _fire_motion.has(int(person.id))
		_fire_motion[int(person.id)] = person

func _finish_fire_motion(delta: float) -> void:
	_fire_motion_delta = delta
	_fire_body_buckets.clear()
	for identity: int in _fire_motion:
		var person: Dictionary = _fire_motion[identity]
		var owner_ref: Variant = person.owner
		var ground: Vector2 = owner_ref.combat_ground(int(person.unit)) if int(person.unit) >= 0 else owner_ref.position
		person["end_ground"] = ground
		# One navigation-space broadphase serves every original owner, including
		# Native bodies whose exact segment is supplied below.
		if float(person.radius) > 0.0:
			var bounds := Rect2(person.ground, Vector2.ZERO).expand(ground).grow(float(person.radius) + 1.8 * 48.0 + 1.0)
			for y in range(floori(bounds.position.y / 128.0), floori(bounds.end.y / 128.0) + 1):
				for x in range(floori(bounds.position.x / 128.0), floori(bounds.end.x / 128.0) + 1):
					var key := Vector2i(x, y)
					if not _fire_body_buckets.has(key): _fire_body_buckets[key] = []
					_fire_body_buckets[key].append(identity)
		if owner_ref is CrowdPersonOwner:
			var native: PackedFloat64Array = crowd_site.fire_motion_segment(int(person.unit))
			if native.size() != 4:
				person["motion"] = {}
				_latch_fire_boundary_error(SiteRuntime.fail("MISSING_NATIVE_FIRE_MOTION", "原 Native solver 未回報已完成動作段"))
				continue
			var from := Vector2(native[0], native[1]) * TerrainRenderer.CELL_PIXELS
			var to := Vector2(native[2], native[3]) * TerrainRenderer.CELL_PIXELS
			if from.distance_squared_to(person.ground) > 0.00000001 or to.distance_squared_to(ground) > 0.00000001:
				person["motion"] = {}
				_latch_fire_boundary_error(SiteRuntime.fail("NATIVE_FIRE_MOTION_MISMATCH", "原 Native 動作段端點與本步身體位置不符"))
				continue
			person["motion"] = {"native_segment": PackedVector2Array([from, to])}
			continue
		# Navigation may have admitted the step after the pre-body snapshot.
		# Recover its original progress, without advancing or changing that owner.
		if person.motion.is_empty() and ground.distance_squared_to(person.ground) > 0.00000001:
			var admitted := _fire_owner_motion(person)
			if not admitted.is_empty():
				admitted.progress = maxf(0.0, float(admitted.progress) - delta / float(admitted.duration))
				person.motion = admitted

func _fire_relative_screen(person: Dictionary, point: Vector3, fraction: float) -> Vector2:
	var ground := _fire_motion_ground(person, fraction)
	return Vector2(point.x, point.y) * TerrainRenderer.CELL_PIXELS - ground + (person.anchor as Vector2) - Vector2(0, 48.0 * (point.z - _fire_surface_height(ground)))

func _capture_fire_static() -> void:
	_fire_static_buckets.clear()
	for feature_id: String in terrain.site.get("features", {}):
		var feature: Dictionary = terrain.site.features[feature_id]
		if str(feature.get("stage", "")) != "complete": continue
		var geometry := SiteRuntime.feature_geometry(terrain, feature)
		if geometry.parts.is_empty():
			for value: int in geometry.blocked:
				var cell := terrain.cell_from_index(value)
				if not _fire_static_buckets.has(cell): _fire_static_buckets[cell] = []
				_fire_static_buckets[cell].append({"type": "blocked", "feature": feature_id, "part": "", "cell": cell,
					"stable": "blocked:%s:%012d" % [feature_id, value], "bounds": Rect2(Vector2(cell), Vector2.ONE),
					"lower": float(feature.get("level", 0)), "upper": float(feature.get("level", 0)) + 2.0})
		for part_id: String in geometry.parts:
			var part: Dictionary = geometry.parts[part_id]
			if float(part.hp) <= 0.0 or str(part.role) == "leaf" and bool(feature.get("gate", {}).get("open", false)): continue
			for value: int in part.cells:
				var cell := terrain.cell_from_index(value)
				var record := {"type": "structure", "feature": feature_id, "part": part_id, "material": str(part.get("material", "wood" if str(part.role) == "leaf" else str(feature.get("material", "wood")))),
					"stable": "structure:" + feature_id + ":" + part_id, "bounds": Rect2(Vector2(cell), Vector2.ONE), "lower": float(part.get("lower", feature.get("level", 0))),
					"upper": float(part.get("upper", maxf(float(feature.get("level", 0)) + 0.5, float(part.height)) if str(part.role) in ["wall", "stairs"] else float(feature.get("level", 0)) + 2.0))}
				if not _fire_static_buckets.has(cell): _fire_static_buckets[cell] = []
				_fire_static_buckets[cell].append(record)
	for vehicle_id: String in terrain.site.get("vehicles", {}):
		if _ship_vehicle_in_journey(vehicle_id): continue
		var vehicle: Dictionary = terrain.site.vehicles[vehicle_id]
		for cell: Vector2i in SiteVehicleTransport.footprint(terrain, vehicle):
			var base := float(terrain.effective_height(cell))
			if not _fire_static_buckets.has(cell): _fire_static_buckets[cell] = []
			_fire_static_buckets[cell].append({"type": "vehicle", "vehicle": vehicle_id, "material": "wood", "stable": "vehicle:" + vehicle_id,
				"bounds": Rect2(Vector2(cell), Vector2.ONE), "lower": base, "upper": base + 1.0})

func _fire_polygon_normal(polygon: PackedVector2Array, point: Vector2) -> Vector2:
	var best := INF
	var normal := Vector2.ZERO
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		var witness := Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance := witness.distance_squared_to(point)
		if distance < best:
			best = distance
			var separation := point - witness
			if separation.length_squared() > 0.000000000001:
				normal = separation.normalized()
			else:
				var edge := (b - a).normalized()
				normal = Vector2(-edge.y, edge.x)
	return normal

func _fire_first_contact(flight: Dictionary, from: Vector3, to: Vector3, interval_begin: float, interval_end: float, include_people: bool = true) -> Dictionary:
	var events: Array[Dictionary] = []
	var candidates := {}
	var navigation_bounds := Rect2(Vector2(from.x, from.y) * TerrainRenderer.CELL_PIXELS, Vector2.ZERO).expand(Vector2(to.x, to.y) * TerrainRenderer.CELL_PIXELS).grow(1.0)
	for y in range(floori(navigation_bounds.position.y / 128.0), floori(navigation_bounds.end.y / 128.0) + 1):
		for x in range(floori(navigation_bounds.position.x / 128.0), floori(navigation_bounds.end.x / 128.0) + 1):
			for identity: int in _fire_body_buckets.get(Vector2i(x, y), []): candidates[identity] = true
	for identity: int in (candidates if include_people else {}):
		# Only the source's necessary short birth interval is excluded.
		if identity == int(flight.source_member_id) and float(flight.elapsed) < 0.05: continue
		var person: Dictionary = _fire_motion[identity]
		# A moving body follows its original quadratic/cubic curve. Refine this
		# arrow segment until relative chord error is below a quarter screen pixel.
		var spans: Array[Vector2] = [Vector2(0.0, 1.0)]
		var cursor := 0
		while cursor < spans.size():
			var span := spans[cursor]
			var relative_first := _fire_relative_screen(person, from.lerp(to, span.x), lerpf(interval_begin, interval_end, span.x))
			var relative_last := _fire_relative_screen(person, from.lerp(to, span.y), lerpf(interval_begin, interval_end, span.y))
			var error := 0.0
			for part: float in [0.25, 0.5, 0.75]:
				var at := lerpf(span.x, span.y, part)
				error = maxf(error, _fire_relative_screen(person, from.lerp(to, at), lerpf(interval_begin, interval_end, at)).distance_to(relative_first.lerp(relative_last, part)))
			if error > 0.25 and spans.size() < 64:
				var middle := (span.x + span.y) * 0.5
				spans[cursor] = Vector2(span.x, middle)
				spans.insert(cursor + 1, Vector2(middle, span.y))
				continue
			cursor += 1
			var previous: Array[PackedVector2Array] = [FatigueGeometry.capsule(relative_first, relative_first, 0.75)]
			var current: Array[PackedVector2Array] = [FatigueGeometry.capsule(relative_last, relative_last, 0.75)]
			var prepared := FatigueGeometry.prepare_sweeps(previous, current)
			for kind: String in ["shield", "body"]:
				var shapes: Array[PackedVector2Array] = []
				shapes.assign(person.geometry[kind])
				var hit := FatigueGeometry.contact(previous, current, shapes, prepared)
				if hit.is_empty(): continue
				var fraction := lerpf(span.x, span.y, float(hit.fraction))
				var person_base := _fire_surface_height(_fire_motion_ground(person, lerpf(interval_begin, interval_end, fraction)))
				var height := lerpf(from.z, to.z, fraction)
				if height < person_base or height > person_base + 1.8: continue
				# Use the contacting arrow centre's nearest bone edge as the witness;
				# the overlap polygon centroid is not a contact-normal authority.
				var witness := relative_first.lerp(relative_last, float(hit.fraction))
				var normal := _fire_polygon_normal(shapes[int(hit.body)], witness)
				var before := maxf(0.0, fraction - 0.0001)
				var after := minf(1.0, fraction + 0.0001)
				var velocity := _fire_relative_screen(person, from.lerp(to, after), lerpf(interval_begin, interval_end, after)) - _fire_relative_screen(person, from.lerp(to, before), lerpf(interval_begin, interval_end, before))
				var incidence := absf(velocity.normalized().dot(normal))
				events.append({"type": "person", "person": person, "shield": kind == "shield", "fraction": fraction, "incidence": incidence,
					"stable": "person:%012d:%s" % [identity, "0" if kind == "shield" else "1"]})
	var bounds := Rect2(Vector2(from.x, from.y), Vector2.ZERO).expand(Vector2(to.x, to.y)).grow(0.015)
	for y in range(floori(bounds.position.y), floori(bounds.end.y) + 1):
		for x in range(floori(bounds.position.x), floori(bounds.end.x) + 1):
			var cell := Vector2i(x, y)
			if not terrain.contains(cell): continue
			for collider: Dictionary in _fire_static_buckets.get(cell, []):
				var hit_value := FatigueGeometry.segment_prism_contact(from, to, collider.bounds, float(collider.lower), float(collider.upper), 0.015)
				if not hit_value.is_empty():
					var event := collider.duplicate()
					event.fraction = float(hit_value.fraction)
					events.append(event)
			var top := float(terrain.height_levels[terrain.index(cell)])
			if terrain.static_blocked[terrain.index(cell)] != 0 and int(terrain.feature_at[terrain.index(cell)]) == 0: top += 2.0
			var hit := FatigueGeometry.segment_prism_contact(from, to, Rect2(Vector2(cell), Vector2.ONE), -1000.0, top, 0.015)
			if not hit.is_empty(): events.append({"type": "ground", "cell": cell, "fraction": float(hit.fraction), "stable": "ground:%012d" % terrain.index(cell)})
	if not terrain.contains(Vector2i(floori(to.x), floori(to.y))):
		var hit := FatigueGeometry.segment_prism_contact(to, from, Rect2(Vector2.ZERO, Vector2(terrain.size)), -1000.0, 1000.0)
		events.append({"type": "boundary", "fraction": 1.0 - float(hit.get("fraction", 0.0)), "stable": "boundary"})
	if events.is_empty(): return {}
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.fraction) < float(b.fraction) if float(a.fraction) != float(b.fraction) else str(a.stable) < str(b.stable))
	return events[0]

func _settle_fire_impact(flight: Dictionary, event: Dictionary) -> void:
	if bool(flight.resolved): return
	if _region_queue_original_endpoint("fire_impact", {"flight": flight, "event": event}): return
	flight.resolved = true
	var result := {"kind": "empty", "hp": 0.0, "stun": 0.0, "stagger": 0.0, "heat_transfer": 1.0, "contact_scale": 1.0}
	var target_id := 0
	if str(event.type) == "person":
		var person: Dictionary = event.person
		target_id = int(person.id)
		var defense: Dictionary = person.owner.ranged_defense(int(person.unit)) if int(person.unit) >= 0 else person.owner.ranged_defense()
		result = SiteCombatRules.fire_contact_result(flight.shooter, defense, float(event.incidence), bool(event.shield), float(flight.profile.kinetic_multiplier))
		var packet := {"result": result, "shield": bool(event.shield), "ranged": true, "attacker": null, "attacker_unit": -1}
		if int(person.unit) >= 0: person.owner.ranged_apply_hit(int(person.unit), flight.source_cell, packet)
		else: person.owner.ranged_apply_hit(flight.source_cell, packet)
	elif str(event.type) == "blocked":
		result.kind = "blocked"
	elif str(event.type) in ["structure", "vehicle"]:
		result.kind = "blocked"
		var damage := SiteCombatRules.structure_damage(str(flight.shooter.weapon), str(event.material)) * float(flight.profile.kinetic_multiplier)
		if str(event.type) == "structure":
			var parts := {str(event.feature) + "|" + str(event.part): {"feature": event.feature, "part": event.part, "damage": damage}}
			siege_queue_damage(parts, {}, int(flight.source_member_id))
		else: siege_queue_damage({}, {str(event.vehicle): damage}, int(flight.source_member_id))
	var budget := float(flight.ember)
	if str(event.type) == "boundary": budget = 0.0
	if str(event.type) == "ground" and terrain.water_kind[terrain.index(event.cell)] != 0: budget = 0.0
	var payload := {"site_id": str(terrain.site.id), "event_id": "arrow:%d" % int(flight.projectile_id), "projectile_id": int(flight.projectile_id), "target_key": str(event.stable),
		"type": str(event.type), "action_time": float(event.get("action_time", fire_action_cursor)), "position": flight.position, "remaining_heat_budget": budget,
		"heat_rate": float(flight.profile.contact_rate), "max_seconds": float(flight.profile.contact_seconds),
		"heat_transfer": float(result.get("heat_transfer", 1.0)), "contact_scale": float(result.get("contact_scale", 1.0))}
	if event.has("cell"): payload["cell"] = event.cell
	if event.has("feature"): payload["feature"] = event.feature; payload["part"] = event.part
	if target_id > 0: payload["person_id"] = target_id
	# Every original terminal event closes its receipt, including zero heat.
	# The optional P1 ignition observer remains a heat-only observer.
	var received := SiteRuntime.fire_receive_impact(terrain, payload)
	if not received.ok: _latch_fire_boundary_error(received)
	elif target_id > 0 and not bool(received.get("duplicate", false)):
		_receive_fire_body_contact(event.person, payload)
	fire_impact_recorder.append(payload)
	if fire_impact_recorder.size() > 256: fire_impact_recorder.pop_front()
	if fire_ignition_sink.is_valid() and budget > 0.0: fire_ignition_sink.call(payload)
	ranged_resolutions += 1
	var result_kind := str(result.kind)
	ranged_results[result_kind if ranged_results.has(result_kind) else "blocked"] += 1
	ranged_resolved.emit(int(flight.source_member_id), target_id, result)

func _advance_physical_ranged(delta: float) -> void:
	if terrain == null or delta <= 0.0 or bool(terrain.site.get("paused", false)) or is_inside_tree() and get_tree().paused: return
	if not is_finite(delta) or delta > EXCHANGE_ACTION_STEP + ACTION_TIME_EPSILON:
		push_error("Physical ranged requires one original completed action slice; advance the original Lab clock for larger deltas")
		return
	if _fire_committing or _fire_advancing: return
	if fire_projectiles.is_empty():
		_finish_fire_motion(delta)
		fire_action_cursor += delta
		return
	_fire_advancing = true
	_finish_fire_motion(delta)
	_capture_fire_static()
	var events: Array[Dictionary] = []
	for flight: Dictionary in fire_projectiles:
		var before := float(flight.elapsed)
		var after := minf(float(flight.life), before + delta)
		# g*dt^2/8 <= .02 navigation cells for every curve segment.
		var subdivisions := maxi(1, ceili((after - before) * sqrt(float(flight.gravity) / (8.0 * 0.02))))
		var contacted := false
		for section in range(subdivisions):
			var a := lerpf(before, after, float(section) / float(subdivisions))
			var b := lerpf(before, after, float(section + 1) / float(subdivisions))
			var from := SiteCombatRules.fire_position(flight, a)
			var to := SiteCombatRules.fire_position(flight, b)
			var event := _fire_first_contact(flight, from, to, (a - before) / delta, (b - before) / delta)
			var actual := b if event.is_empty() else lerpf(a, b, float(event.fraction))
			var middle := SiteCombatRules.fire_position(flight, (a + actual) * 0.5)
			var rain_loss := SiteRuntime.fire_rain_integral(terrain, fire_action_cursor + a - before, fire_action_cursor + actual - before)
			rain_loss *= SiteRuntime.fire_point_rain_exposure(terrain, middle) * float(flight.profile.get("rain_decay", 0.0))
			flight.ember = maxf(0.0, float(flight.ember) - float(flight.profile.air_decay) * (actual - a) - rain_loss)
			flight.position = SiteCombatRules.fire_position(flight, actual)
			flight.elapsed = actual
			if not event.is_empty():
				event["flight"] = flight
				event["action_time"] = fire_action_cursor + actual - before
				events.append(event)
				contacted = true
				break
		if not contacted and after >= float(flight.life):
			events.append({"type": "boundary", "stable": "expiry", "flight": flight, "action_time": fire_action_cursor + after - before})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.action_time) != float(b.action_time): return float(a.action_time) < float(b.action_time)
		if int(a.flight.projectile_id) != int(b.flight.projectile_id): return int(a.flight.projectile_id) < int(b.flight.projectile_id)
		return str(a.stable) < str(b.stable))
	for event: Dictionary in events: _settle_fire_impact(event.flight, event)
	for index in range(fire_projectiles.size() - 1, -1, -1):
		if bool(fire_projectiles[index].resolved): fire_projectiles.remove_at(index)
	fire_action_cursor += delta
	# The original completed motion survives through post-contact exposure.
	_fire_advancing = false
	queue_redraw()

class FirePresentation extends Node2D:
	var lab: Node2D
	func _draw() -> void: lab._draw_fire_presentation(self)

var _fire_view: Node2D

func _draw() -> void:
	if is_instance_valid(_fire_view): _fire_view.queue_redraw()

func _draw_fire_presentation(canvas: Node2D) -> void:
	if terrain == null: return
	_draw_fire_smoke(canvas)
	_draw_fire_state(canvas)
	for flight: Dictionary in fire_projectiles:
		var ground := Vector2(flight.position.x, flight.position.y) * TerrainRenderer.CELL_PIXELS
		var base := _fire_surface_height(ground)
		var point := _fire_screen(flight.position, base) + terrain.surface_visual_offset_at(ground)
		var before := SiteCombatRules.fire_position(flight, maxf(0.0, float(flight.elapsed) - 0.02))
		var previous_ground := Vector2(before.x, before.y) * TerrainRenderer.CELL_PIXELS
		var previous := _fire_screen(before, _fire_surface_height(previous_ground)) + terrain.surface_visual_offset_at(previous_ground)
		var color := Color(1.0, 0.45, 0.1) if float(flight.ember) > 0.0 else Color(0.8, 0.7, 0.45)
		canvas.draw_line(previous, point, color, 2.0)

# Original Lab only records the completion of its existing action slice.
# An error is latched here for direct owner calls without an attached Controller.
var _fire_boundary_error: Dictionary = {}
var _fire_unsaved := false

func fire_pending_projectile_query(_unit_key: String) -> bool:
	if _fire_committing: return true
	for flight: Dictionary in fire_projectiles:
		if str(flight.get("profile", {}).get("mode", "NORMAL")) == "FIRE_ARROW" and not bool(flight.resolved): return true
	for flight: Dictionary in siege_projectiles:
		if flight.get("ammo") == "fire_pot" and not bool(flight.get("fire_resolved", false)): return true
	return false

func _fire_activity() -> bool:
	return SiteRuntime.fire_active(terrain) or fire_pending_projectile_query("") or not _fire_body_active.is_empty()

func _latch_fire_boundary_error(result: Dictionary) -> Dictionary:
	if _fire_boundary_error.is_empty(): _fire_boundary_error = result.duplicate(true)
	if site_controller != null: site_controller.latch_original_step_fault(result)
	else: push_error("Original fire boundary rejected: " + str(result))
	return result

func _fire_step_guard() -> Dictionary:
	if _fire_exposure_sequence >= 2147483647: return SiteRuntime.fail("FIRE_EXPOSURE_SEQUENCE_LIMIT")
	if not _fire_boundary_error.is_empty(): return _fire_boundary_error.duplicate(true)
	if site_controller != null:
		var fault: Dictionary = site_controller.original_step_fault_guard()
		if not fault.ok: return fault
	_wire_fire_ranged()
	if crowd_site != null and crowd_site.active and not crowd_site.fire_host_active():
		# Keep the original admission boundary; no P2 fire simulation on Native.
		var native_guard := SiteStore.fire_event_guard(terrain)
		if not native_guard.ok: return native_guard
	if not exchange_enabled and (not fire_projectiles.is_empty() or not fire_reservations.is_empty()):
		return SiteRuntime.fail("BUSY", "原物理箭矢須由已准入共同動作路徑完成")
	return SiteRuntime.ok()

func _begin_fire_boundary(completed_action_end: float) -> Dictionary:
	if terrain == null or terrain.site.is_empty(): return SiteRuntime.ok()
	# Original Native admission rejects all P2 history/flight state. Its clean
	# legacy work must not be deferred into a fire barrier it cannot simulate.
	if crowd_site != null and crowd_site.active and not crowd_site.fire_host_active(): return SiteRuntime.ok()
	var boundary: Dictionary = terrain.get_meta(&"fire_boundary", {})
	if not boundary.is_empty():
		# Shared-step opened this exact boundary before Controller.tick. Direct
		# entry reuses it without a second barrier clock or duplicate completion.
		if str(boundary.get("site_id", "")) == str(terrain.site.id) \
			and absf(float(boundary.get("action_end", -1.0)) - completed_action_end) <= ACTION_TIME_EPSILON:
			return SiteRuntime.ok()
		return SiteRuntime.fail("STALE_FIRE_BOUNDARY")
	return SiteRuntime.fire_begin_boundary(terrain, completed_action_end, _region_deferring_endpoint())

func _finish_fire_boundary(action_begin: float, completed_action_end: float) -> bool:
	if _region_deferring_endpoint(): return true
	if terrain == null or terrain.site.is_empty(): return true
	if not _fire_boundary_error.is_empty(): return false
	# Physical ranged already publishes this same completed slice. Legacy and
	# admissible empty Native slices publish once here after their real contacts.
	var needs_publication := absf(fire_action_cursor - action_begin) <= ACTION_TIME_EPSILON
	if not needs_publication and absf(fire_action_cursor - completed_action_end) > ACTION_TIME_EPSILON:
		_latch_fire_boundary_error(SiteRuntime.fail("FIRE_TIME_MISMATCH", "原共同動作完成端點不一致"))
		return false
	var prefix := _fire_release_sequence
	for flight: Dictionary in fire_projectiles: prefix = mini(prefix, int(flight.projectile_id) - 1)
	for flight: Dictionary in siege_projectiles:
		if flight.get("ammo") == "fire_pot" and not bool(flight.get("fire_resolved", false)): prefix = mini(prefix, int(flight.projectile_id) - 1)
	var guardian := Callable()
	if site_controller != null: guardian = site_controller.fire_resource_owner_guard
	var result := SiteRuntime.fire_finish_boundary(terrain, completed_action_end, prefix, siege_queue_damage, guardian)
	if not result.ok:
		_latch_fire_boundary_error(result)
		return false
	if needs_publication: fire_action_cursor = completed_action_end
	if site_controller != null: site_controller.person_actions.settle_fire_pot_trials()
	if _fire_release_sequence > 0 or SiteRuntime.fire_active(terrain): _fire_unsaved = true
	if int(result.get("boundaries", 0)) > 0: queue_redraw()
	return true

func _draw_fire_state(presentation: Node2D) -> void:
	# One Lab-owned canvas draws the bounded batch above terrain/resource rows.
	# No per-fire/per-arrow node, visual clock or writable fuel mirror.
	# ponytail: one overlay, authored depth/LOD belongs to the P6 visual gate.
	var state: Dictionary = terrain.site.get("fire", {})
	var units: Dictionary = state.get("units", {})
	var active: Dictionary = state.get("active", {})
	var seen := {}
	var inspected := 0
	var drawn := 0
	var viewport := get_viewport_rect().grow(32.0)
	var canvas := presentation.get_global_transform_with_canvas()
	# Current heat has priority over cold history within the presentation budget.
	for collection: Dictionary in [active, units]:
		for key: String in collection:
			if inspected >= 1024 or drawn >= 256: return
			if seen.has(key): continue
			seen[key] = true
			inspected += 1
			var unit: Dictionary = units.get(key, {})
			var heat := maxf(0.0, float(unit.get("heat", 0.0)))
			var scorch := clampf(float(unit.get("scorch", 0.0)), 0.0, 1.0)
			if unit.is_empty() or heat <= 0.0 and scorch <= 0.0: continue
			var descriptor := SiteRuntime._fire_descriptor(terrain, unit)
			if descriptor.is_empty(): continue
			var cell: Vector2i = descriptor.cell
			var ground := (Vector2(cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			var point := ground + terrain.surface_visual_offset_at(ground)
			if not viewport.has_point(canvas * point): continue
			var hazard_cell := terrain.cell_from_index(int(descriptor.hazard_cells[0])) if not descriptor.hazard_cells.is_empty() else cell
			var hazard := SiteRuntime.fire_hazard_at(terrain, hazard_cell, str(unit.surface_id))
			if scorch > 0.0: presentation.draw_circle(point, 11.0 + scorch * 5.0, Color(0.10, 0.07, 0.04, 0.20 + scorch * 0.35))
			if heat > 0.0:
				var strength := clampf(maxf(hazard, heat / 100.0), 0.0, 1.0)
				presentation.draw_circle(point, 7.0 + strength * 9.0, Color(1.0, 0.28 + strength * 0.18, 0.04, 0.20 + strength * 0.45))
			drawn += 1


# P3-A references only: this bounded set never owns a second person/HP record.
var _fire_body_active: Dictionary = {}
var _fire_exposure_snapshot: Dictionary = {}
var _fire_exposure_sequence := 0

func _fire_exposure_chunk(cell: Vector2i) -> bool:
	return _fire_exposure_snapshot.get("chunks", {}).has(Vector2i(floori(float(cell.x) / 16.0), floori(float(cell.y) / 16.0)))

func _fire_add_exposure_person(owner_ref: Variant, unit: int, identity: int, inside_site: bool = true) -> void:
	if _fire_motion.has(identity):
		_fire_motion[identity]["exposure"] = true
		return
	var ground: Vector2 = owner_ref.combat_ground(unit) if unit >= 0 else owner_ref.position
	var person := {"owner": owner_ref, "unit": unit, "id": identity, "ground": ground, "exposure": true,
		"inside_site": inside_site, "radius": 0.0, "geometry": {"body": [], "shield": []}}
	person["motion"] = _fire_owner_motion(person) if inside_site else {}
	_fire_motion[identity] = person

func _capture_fire_exposure_candidates() -> void:
	_fire_exposure_snapshot = SiteRuntime.fire_hazard_snapshot(terrain)
	if not _fire_exposure_snapshot.chunks.is_empty():
		if crowd_site != null and crowd_site.fire_host_active():
			for owner_ref: CrowdPersonOwner in crowd_site.person_owners():
				for unit: int in owner_ref.combat_units:
					var person: Dictionary = owner_ref.person(unit, false)
					if person.is_empty() or float(person.hp) <= 0.0 or bool(owner_ref.combat_hot_get(unit, &"site_exited", false)): continue
					var cell: Vector2i = person.cell
					var near_fire_chunk := false
					for y in range(cell.y - 1, cell.y + 2):
						for x in range(cell.x - 1, cell.x + 2):
							if _fire_exposure_chunk(Vector2i(x, y)): near_fire_chunk = true
					if near_fire_chunk: _fire_add_exposure_person(owner_ref, unit, owner_ref.combat_identity(unit))
		for team: TerrainArmy in combat_armies:
			if not team.combat_enabled: continue
			# Raw original cell arrays are the coarse query. KO rows absent from the
			# occupancy map remain eligible; no mesh, Near promotion or body query.
			for unit in range(team.cells.size()):
				if not _fire_exposure_chunk(team.cells[unit]) and (team.moving_to[unit] == TerrainArmy.INVALID_CELL or not _fire_exposure_chunk(team.moving_to[unit])): continue
				if team._ship_embarked(unit) or team._ship_in_journey(unit) or bool(team.combat_hot_get(unit, &"site_exited", false)) or float(team.combat_hot_get(unit, &"hp")) <= 0.0: continue
				_fire_add_exposure_person(team, unit, team.combat_identity(unit))
		for actor: TerrainTestCharacter in combat_actors:
			if not is_instance_valid(actor) or actor.hp <= 0.0 or actor.site_exited: continue
			if _fire_exposure_chunk(actor.terrain_cell) or _fire_exposure_chunk(Vector2i((actor.position / TerrainRenderer.CELL_PIXELS).floor())):
				_fire_add_exposure_person(actor, -1, actor.combat_identity())
	for identity: int in _fire_body_active.keys():
		# Even after a retreat exit, the original owner's finite body status
		# finishes. An exited/embarked owner receives no new terrain exposure.
		var person := _original_person_target(identity)
		if person.is_empty() or float(person.hp) <= 0.0:
			_fire_body_active.erase(identity)
			continue
		var inside := not bool(person.owner.combat_hot_get(int(person.unit), &"site_exited", false)) if int(person.unit) >= 0 else not bool(person.owner.site_exited)
		if int(person.unit) >= 0 and _ship_embarked(identity): inside = false
		_fire_add_exposure_person(person.owner, int(person.unit), identity, inside)
	if not _fire_motion.is_empty():
		_fire_exposure_sequence += 1 # Only actual original-person exposure intervals consume a sequence.

func _fire_exposure_wet(cell: Vector2i, height: float, natural_height: float = INF) -> bool:
	if not terrain.contains(cell): return false
	var value := terrain.index(cell)
	# Water underneath a raised bridge/platform is not a person's water contact.
	return terrain.water_kind[value] != 0 and terrain.surface_types[value] == TerrainData.Surface.WATER \
		and height <= (natural_height if is_finite(natural_height) else float(terrain.height_levels[value])) + 0.00000001

func _fire_exposure_height(person: Dictionary, fraction: float, relative_ground: bool) -> float:
	var ground := _fire_motion_ground(person, fraction)
	return _fire_surface_height(ground) - (_fire_surface_height(ground, true) if relative_ground else 0.0)

func _fire_curve_crossing(person: Dictionary, begin: float, end: float, axis: int, boundary: float, height_axis: bool = false, relative_ground: bool = false) -> float:
	var first := _fire_exposure_height(person, begin, relative_ground) if height_axis else _fire_motion_ground(person, begin)[axis] / TerrainRenderer.CELL_PIXELS
	var last := _fire_exposure_height(person, end, relative_ground) if height_axis else _fire_motion_ground(person, end)[axis] / TerrainRenderer.CELL_PIXELS
	var increasing := last > first
	for iteration in range(24):
		var middle := (begin + end) * 0.5
		var value := _fire_exposure_height(person, middle, relative_ground) if height_axis else _fire_motion_ground(person, middle)[axis] / TerrainRenderer.CELL_PIXELS
		if (value < boundary) == increasing: begin = middle
		else: end = middle
	return (begin + end) * 0.5

func _fire_exposure_segments(person: Dictionary, action_begin: float, action_end: float) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	if not bool(person.get("inside_site", true)):
		return [{"begin": action_begin, "end": action_end, "risk": 0.0, "wet": false}]
	var first := _fire_motion_ground(person, 0.0) / TerrainRenderer.CELL_PIXELS
	var last := _fire_motion_ground(person, 1.0) / TerrainRenderer.CELL_PIXELS
	var knots: Array[float] = [0.0, 1.0]
	for axis in range(2):
		# Original surface interpolation changes slope at both cell edges and
		# centres. Split those half-cell knots before solving vertical crossings.
		for value in range(floori(minf(first[axis], last[axis]) * 2.0) + 1, ceili(maxf(first[axis], last[axis]) * 2.0)):
			knots.append(_fire_curve_crossing(person, 0.0, 1.0, axis, float(value) * 0.5))
	knots.sort()
	var vertical: Array[float] = knots.duplicate()
	for index in range(knots.size() - 1):
		var begin := knots[index]
		var end := knots[index + 1]
		if end - begin <= 0.0000000001: continue
		var middle := _fire_motion_ground(person, (begin + end) * 0.5)
		var cell := Vector2i((middle / TerrainRenderer.CELL_PIXELS).floor())
		if not terrain.contains(cell): continue
		var natural := float(terrain.height_levels[terrain.index(cell)])
		var boundaries: Array[Dictionary] = [{"level": 0.0, "relative": true}]
		for entry: Dictionary in _fire_exposure_snapshot.cells.get(terrain.index(cell), []):
			var relative := bool(entry.get("ground", false))
			for endpoint: float in [float(entry.get("thermal_lower", entry.lower)), float(entry.get("thermal_upper", entry.upper))]: boundaries.append({"level": endpoint - (natural if relative else 0.0), "relative": relative})
		for boundary: Dictionary in boundaries:
			var relative := bool(boundary.relative)
			var low := _fire_exposure_height(person, begin, relative)
			var high := _fire_exposure_height(person, end, relative)
			if float(boundary.level) > minf(low, high) and float(boundary.level) < maxf(low, high): vertical.append(_fire_curve_crossing(person, begin, end, 0, float(boundary.level), true, relative))
	vertical.sort()
	for index in range(vertical.size() - 1):
		var begin := vertical[index]
		var end := vertical[index + 1]
		if end <= begin: continue
		var ground := _fire_motion_ground(person, (begin + end) * 0.5)
		var cell := Vector2i((ground / TerrainRenderer.CELL_PIXELS).floor())
		var height := _fire_surface_height(ground)
		var natural_height := _fire_surface_height(ground, true)
		var ground_offset := natural_height - float(terrain.height_levels[terrain.index(cell)]) if terrain.contains(cell) else 0.0
		segments.append({"begin": lerpf(action_begin, action_end, begin), "end": lerpf(action_begin, action_end, end),
			"risk": SiteRuntime.fire_exposure_at(_fire_exposure_snapshot, cell, height, ground_offset) if terrain.contains(cell) else 0.0,
			"wet": _fire_exposure_wet(cell, height, natural_height)})
	return segments

func _receive_fire_body_contact(person: Dictionary, payload: Dictionary) -> void:
	var accepted: bool = person.owner.fire_body_receive_contact(int(person.unit), payload) if int(person.unit) >= 0 else person.owner.fire_body_receive_contact(payload)
	if accepted:
		_fire_body_active[int(person.id)] = true
		person["exposure"] = true

func _settle_fire_exposure(action_begin: float, action_end: float) -> bool:
	if _fire_motion_delta <= 0.0: _finish_fire_motion(action_end - action_begin)
	if not _fire_boundary_error.is_empty(): return false
	var identities: Array = _fire_motion.keys()
	identities.sort()
	# Validate original motion before applying any person's environment packet.
	for identity: int in identities:
		var person: Dictionary = _fire_motion[identity]
		if not bool(person.get("exposure", false)) or not bool(person.get("inside_site", true)): continue
		if person.motion.is_empty() and (person.ground as Vector2).distance_squared_to(person.end_ground) > 0.00000001:
			_latch_fire_boundary_error(SiteRuntime.fail("MISSING_ORIGINAL_FIRE_MOTION", "原身體移動缺少已完成曲線；不以直線猜測暴露"))
			return false
	for identity: int in identities:
		var person: Dictionary = _fire_motion[identity]
		if not bool(person.get("exposure", false)): continue
		var segments := _fire_exposure_segments(person, action_begin, action_end)
		var result: Dictionary = person.owner.advance_fire_exposure(int(person.unit), _fire_exposure_sequence, action_begin, action_end, segments) if int(person.unit) >= 0 else person.owner.advance_fire_exposure(_fire_exposure_sequence, action_begin, action_end, segments)
		if not bool(result.ok):
			_latch_fire_boundary_error(result)
			return false
		if bool(result.get("active", false)): _fire_body_active[identity] = true
		else: _fire_body_active.erase(identity)
	for team: TerrainArmy in combat_armies:
		team._publish_fire_threat_summary(action_end)
	_fire_motion.clear()
	_fire_body_buckets.clear()
	_fire_exposure_snapshot = {}
	if crowd_site != null and crowd_site.fire_host_active() and not crowd_site.sync_fire_visuals():
		_latch_fire_boundary_error(SiteRuntime.fail("INVALID_FIRE_VISUAL", "原 Native 火體外觀投影失敗"))
		return false
	return true


# Explicit isolated fixture adapter on the ORIGINAL Lab. The scene itself and
# its existing owners remain authoritative; no parallel projectile/person clock.
const FIRE_LAB_FIXTURE_VERSION := 1

static func create_fire_lab_fixture(parent: Node, seed_value: int = 12345, show_window: bool = true) -> Dictionary:
	if parent == null or not parent.is_inside_tree() or seed_value < 0 or seed_value > 2147483646:
		return SiteRuntime.fail("INVALID_FIRE_LAB_FIXTURE")
	var scene := TerrainLab.new()
	scene.restore_only = true # Existing initializer: no default load, save or generation.
	scene.set_meta(&"fire_lab_fixture", {"version": FIRE_LAB_FIXTURE_VERSION, "seed": seed_value})
	parent.add_child(scene)
	var initialized := scene._initialize_fire_lab_fixture(seed_value, show_window)
	if not initialized.ok:
		scene.queue_free()
		return initialized
	return SiteRuntime.ok("隔離火場已建立；使用原人物、物資、移動與火攻入口", {"lab": scene})

func _fire_lab_fixture_guard() -> Dictionary:
	var marker: Variant = get_meta(&"fire_lab_fixture", {})
	if not marker is Dictionary or marker.get("version") != FIRE_LAB_FIXTURE_VERSION \
		or terrain == null or not terrain.get_meta(&"fire_lab_fixture", false) or site_controller == null \
		or site_controller.region_slot != null or crowd_site != null or restore_only:
		return SiteRuntime.fail("NOT_FIRE_LAB_FIXTURE", "此操作只開放於明確建立的隔離火場")
	return SiteRuntime.ok()

func _initialize_fire_lab_fixture(seed_value: int, show_window: bool) -> Dictionary:
	if not has_meta(&"fire_lab_fixture") or not restore_only or terrain != null or not is_inside_tree():
		return SiteRuntime.fail("NOT_EMPTY_FIRE_LAB_FIXTURE")
	var data := TerrainData.new()
	data.allocate(Vector2i(64, 64))
	data.seed_value = seed_value
	data.preset = TerrainPreset.Kind.PLAINS
	data.parameters = {"composition": "fire_lab_m1_v2", "max_height": 1, "micro_strength": 0.0}
	data.spawn_cell = Vector2i(6, 6)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "fire-lab-%d" % seed_value)
	data.height_levels.fill(0)
	data.ramp_edges.fill(0)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.foundation.fill(80)
	data.groundwater.fill(80)
	data.moisture.fill(10)
	data.resource_base.clear()
	data.site.changes.clear()
	data.site.inventory = {}
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 100
	data.site.capacity = 100000
	data.site.depot_cell = data.index(Vector2i(8, 8))
	data.site.manual.cell = data.index(data.spawn_cell)
	data.site.worker.cell = data.index(Vector2i(8, 9))
	SiteEnvironment._add_resource(data, SiteEnvironment.Kind.TIMBER, data.index(Vector2i(20, 20)), 12, 0)
	SiteEnvironment._add_resource(data, SiteEnvironment.Kind.TIMBER, data.index(Vector2i(21, 20)), 12, 0)
	# Explicit M1 terrain genesis finishes before any original person is deployed.
	# The same TerrainData/Environment owners provide soil, water and height.
	for y: int in range(27, 33):
		for x: int in range(16, 22): data.surface_types[data.index(Vector2i(x, y))] = TerrainData.Surface.DIRT
	for y: int in range(35, 41):
		for x: int in range(7, 13):
			var index := data.index(Vector2i(x, y))
			data.surface_types[index] = TerrainData.Surface.WATER
			data.flags[index] = 0
			data.moisture[index] = 100
	SiteEnvironment._generate_water(data)
	for y: int in range(44, 54):
		for x: int in range(42, 56): data.height_levels[data.index(Vector2i(x, y))] = 1
	for y: int in range(40, 50):
		for x: int in [47, 50]:
			var index := data.index(Vector2i(x, y))
			data.surface_types[index] = TerrainData.Surface.ROCK
			data.flags[index] = 0 # Authored two-cell passage at x48..49.
	var up_ramp := TerrainData.DIRECTIONS.find(Vector2i.DOWN)
	for x: int in [48, 49]:
		data.ramp_edges[data.index(Vector2i(x, 43))] |= 1 << up_ramp
		data.ramp_edges[data.index(Vector2i(x, 44))] |= 1 << ((up_ramp + 2) % 4)
	for x: int in range(22, 26):
		SiteEnvironment._add_resource(data, SiteEnvironment.Kind.TIMBER, data.index(Vector2i(x, 15)), 12, 0)
	SiteRuntime.rebuild_terrain_edges(data) # Original cliff/ramp/shore projection before bind.
	SiteEnvironment.rebuild_indexes(data)
	var initialized := SiteRuntime.initialize_item_storage(data.site)
	if not initialized.ok: return initialized
	# Every component is paid and completed by the existing construction owner.
	# A stone gate already authors separate stone frames and combustible leaves.
	var construction_specs: Array[Dictionary] = [
		{"tag": "house", "kind": "house", "anchor": Vector2i(23, 27), "extent": Vector2i.ONE, "material": "wood"},
		{"tag": "gate", "kind": "gate", "anchor": Vector2i(47, 35), "extent": Vector2i.ONE, "material": "stone"},
		{"tag": "wall_left", "kind": "stone_wall", "anchor": Vector2i(42, 36), "extent": Vector2i(5, 1), "material": "stone"},
		{"tag": "wall_right", "kind": "stone_wall", "anchor": Vector2i(51, 36), "extent": Vector2i(6, 1), "material": "stone"}]
	var fixture_features := {}
	for definition: Dictionary in construction_specs:
		var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1, "material": str(definition.material)}
		var layout := SiteRuntime.building_cells(data, str(definition.kind), definition.anchor, definition.extent, options)
		if not layout.ok: return layout
		var built := SiteRuntime.request_build(data, str(definition.kind), layout.cells, Callable(), options)
		if not built.ok: return built
		var feature: Dictionary = data.site.features[str(built.feature)]
		var construction := {"target": "feature:" + str(built.feature), "action": "construct", "cell": int(feature.entrance), "mode": "work", "status": "", "progress": 0.0}
		SiteRuntime._feature_work(data, str(built.feature), float(feature.work), Callable(), Callable(), construction, {}, SiteRuntime.CARRY_CAPACITY, 1)
		if str(feature.stage) != "complete": return SiteRuntime.fail("FIRE_LAB_CONSTRUCTION", "原付費建築尚未完成")
		fixture_features[str(definition.tag)] = str(built.feature)
	data.set_meta(&"fire_lab_fixture", true)
	data.set_meta(&"fire_lab_house", fixture_features.house)
	data.set_meta(&"fire_lab_features", fixture_features)
	site_controller._auto_save_blocked = true
	pause_when_unfocused = false
	bind_terrain(data)
	if terrain != data: return SiteRuntime.fail("FIRE_LAB_BIND", "原隔離場景初始化未接受地圖")
	restore_only = false
	visible = true
	var formal_ui := get_node_or_null("SiteUI") as CanvasLayer
	if formal_ui != null: formal_ui.visible = true
	get_tree().root.gui_embed_subwindows = true
	get_tree().root.size_changed.connect(site_controller._layout)
	site_controller._layout()
	movement_input_enabled = true
	set_process_input(true)
	set_process_unhandled_input(true)
	for actor: TerrainTestCharacter in combat_actors: actor.set_process(false)
	var settings := {"friendly_count": 100, "friendly_troop_type": "bow", "friendly_training": 100,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_tactics": 0,
		"enemy_count": 100, "enemy_troop_type": "melee_infantry", "enemy_training": 100,
		"enemy_female_percent": 0, "enemy_attack": false, "enemy_tactics": 0,
		"third_count": 2, "third_role": "work", "third_faction": 1, "third_training": 100,
		"third_female_percent": 0, "third_attack": false, "third_tactics": 0}
	var sides: Array[Dictionary] = []
	for prefix: String in ["friendly", "enemy", "third"]:
		var parsed := _trial_side_settings(settings, prefix)
		if not parsed.ok: return parsed
		sides.append(parsed.side)
	# Keep the original two tree-facing shooters and eight house-facing shooters;
	# ninety real rows extend behind them, with no extra person or fake collision.
	var archers: Array[Vector2i] = [Vector2i(12, 20), Vector2i(11, 22)]
	# Keep the original eight-cell threat guard clear of the east work approach.
	for y: int in range(30, 34):
		for x: int in [18, 19]: archers.append(Vector2i(x, y))
	for y: int in range(12, 22):
		for x: int in range(3, 12): archers.append(Vector2i(x, y))
	var infantry: Array[Vector2i] = []
	for y: int in range(20, 30):
		for x: int in range(28, 38): infantry.append(Vector2i(x, y))
	var house: Dictionary = terrain.site.features[str(terrain.get_meta(&"fire_lab_house"))]
	infantry[99] = terrain.cell_from_index(int(house.entrance)) # Real defender of the original entrance.
	var deployed := _deploy_trial_teams(sides, [archers, infantry, [Vector2i(23, 22), Vector2i(24, 22)]], 0)
	if not deployed.ok: return deployed
	for row: Dictionary in army.combat_units:
		row.cargo.arrow = 20
		row.cargo.fire_arrow = 20 # Explicit finite genesis in each original holder.
	for row: Dictionary in third_army.combat_units:
		if site_controller.work_team.is_assigned(int(row.person_id)):
			var cancelled: Dictionary = site_controller.work_team.cancel(int(row.person_id))
			if not cancelled.ok: return cancelled
		row.item_state["fire_lab_suppression_q"] = int(SiteCombatRules.fire_suppression_profile().supply_cap_q)
		row.item_state["fire_lab_ignition_q"] = int(SiteCombatRules.fire_work_profile("IGNITE").supply_cap_q)
	var window_script: Script = load("res://scripts/terrain_lab/site_test_window.gd")
	site_test_window = window_script.new()
	add_child(site_test_window)
	site_test_window.setup(self)
	if show_window: site_test_window.open()
	terrain.site.paused = true
	set_process(true)
	_reset_action_elapsed_input()
	return SiteRuntime.ok()

func step_fire_lab_fixture() -> Dictionary:
	var checked := _fire_lab_fixture_guard()
	if not checked.ok: return checked
	if not bool(terrain.site.get("paused", false)) and not get_tree().paused:
		return SiteRuntime.fail("NOT_PAUSED", "先暫停隔離火場再單步")
	var original_data := terrain
	var site_paused := bool(original_data.site.get("paused", false))
	var world_paused := get_tree().paused
	var pending := _action_time_remainder
	# Synchronous temporary admission. There is one call and one cleanup path;
	# every returned failure also restores both pauses and the original remainder.
	original_data.site.paused = false
	get_tree().paused = false
	var result := _advance_original_shared_step(EXCHANGE_ACTION_STEP if exchange_enabled else ACTION_STEP)
	original_data.site.paused = site_paused
	get_tree().paused = world_paused
	_action_time_remainder = pending
	_reset_action_elapsed_input()
	site_controller.update_ui()
	if is_instance_valid(site_test_window): site_test_window.refresh()
	return result

func reset_fire_lab_fixture(seed_value: int) -> Dictionary:
	var checked := _fire_lab_fixture_guard()
	if not checked.ok: return checked
	var result := TerrainLab.create_fire_lab_fixture(get_parent(), seed_value, true)
	if not result.ok: return result # Failed replacement leaves original fixture alive.
	var replacement: TerrainLab = result.lab
	if get_tree().current_scene == self: get_tree().current_scene = replacement
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	if is_instance_valid(site_test_window): site_test_window.hide_window()
	queue_free() # Discards only this explicitly isolated test scene and its owners.
	return result

# OUTPUT ONLY / NOT RUN. Append to original Lab, with original owner order fields.
# Estimates are derived from already-paid flights; never write heat/fuel/HP.
func _fire_policy_group(owner_ref: Variant) -> int:
	if owner_ref is TerrainArmy or owner_ref is CrowdPersonOwner and owner_ref.has_army(): return int(owner_ref.team_id)
	return -int(owner_ref.combat_identity(owner_ref.current_commander)) if owner_ref is CrowdPersonOwner else -int(owner_ref.person_id)

func _fire_policy_target_key(target: Dictionary) -> String:
	if str(target.get("type", "")) == "structure": return "structure:%s:%s" % [target.feature_id, target.part_id]
	if str(target.get("type", "")) == "ground": return "ground:%d" % terrain.index(Vector2i(int(target.cell[0]), int(target.cell[1])))
	return ""

func _fire_policy_observed(person: Dictionary, target: Dictionary) -> Dictionary:
	var aim := _fire_target_aim(target, int(person.id))
	# The original aim rejects destroyed colliders; their exposed footprint
	# remains observable for deciding whether the commanded service has failed.
	if aim.is_empty() and str(target.get("type", "")) == "structure":
		var feature: Dictionary = terrain.site.features.get(str(target.feature_id), {})
		var geometry := SiteRuntime.feature_geometry(terrain, feature)
		var part: Dictionary = geometry.get("parts", {}).get(str(target.part_id), {})
		if not part.is_empty() and not part.cells.is_empty() and float(part.get("rain_exposure", 1.0)) > 0.0:
			aim = {"cell": terrain.cell_from_index(int(part.cells[0]))}
	if aim.is_empty(): return {}
	var source: Vector2i = person.owner._combat_attack_cell(int(person.unit)) if int(person.unit) >= 0 else person.owner.terrain_cell
	if not _person_ranged_line_clear(int(person.id), source, aim.cell, true): return {}
	var key := _fire_policy_target_key(target)
	var unit_key := ""
	if str(target.type) == "structure":
		var feature: Dictionary = terrain.site.features.get(str(target.feature_id), {})
		var geometry := SiteRuntime.feature_geometry(terrain, feature)
		var part: Dictionary = geometry.get("parts", {}).get(str(target.part_id), {})
		if part.is_empty(): return {}
		# Covered interior heat is not observable merely because its XY is visible.
		if float(part.get("rain_exposure", 1.0)) == 0.0: return {}
		unit_key = "feature:%s:%s" % [target.feature_id, target.part_id]
	elif str(target.type) == "ground":
		for resource_key: String in terrain.resources_at.get(terrain.index(aim.cell), []):
			var resource := SiteEnvironment.resource(terrain, resource_key)
			if int(resource.kind) == SiteEnvironment.Kind.TIMBER:
				unit_key = "resource:" + resource_key
				break
	if unit_key.is_empty(): return {}
	var unit: Dictionary = terrain.site.get("fire", {}).get("units", {}).get(unit_key, {})
	return {"key": key, "unit_key": unit_key, "burning": str(unit.get("state", "")) == "BURNING",
		"thermal_step": int(terrain.site.get("fire", {}).get("step_index", 0)), "cell": aim.cell}

func fire_pending_ignition_estimate(owner_ref: Variant, targets: Array[Dictionary]) -> Dictionary:
	var amounts := {}
	for target: Dictionary in targets:
		var key := _fire_policy_target_key(target)
		if not key.is_empty(): amounts[key] = 0.0
	if amounts.is_empty(): return amounts
	_capture_fire_static() # Original immutable collider projection, same sweep owner.
	var group := _fire_policy_group(owner_ref)
	for flight: Dictionary in fire_projectiles:
		var source_group := int(flight.source_formation_id) if int(flight.source_formation_id) > 0 else -int(flight.source_member_id)
		if source_group != group or int(flight.order_serial) != owner_ref.ranged_order_serial \
			or str(flight.profile.mode) != "FIRE_ARROW" or bool(flight.resolved) or float(flight.ember) <= 0.0: continue
		var begin := float(flight.elapsed)
		var end := minf(float(flight.life), float(flight.total) + 0.2)
		if end <= begin: continue
		# ponytail: at most 64 original static sweeps per owned paid flight;
		# cache forecasts by collision revision if formal scaling later requires it.
		var count := mini(64, maxi(1, ceili((end - begin) * sqrt(float(flight.gravity) / (8.0 * 0.02)))))
		for index in range(count):
			var a := lerpf(begin, end, float(index) / count)
			var b := lerpf(begin, end, float(index + 1) / count)
			# Static forecast only: moving people and future weather can intercept
			# or exhaust these arrows; the finite observation deadline rechecks.
			var hit := _fire_first_contact(flight, SiteCombatRules.fire_position(flight, a), SiteCombatRules.fire_position(flight, b), 0.0, 0.0, false)
			if hit.is_empty(): continue
			var key := "structure:%s:%s" % [hit.feature, hit.part] if str(hit.type) == "structure" else ("ground:%d" % terrain.index(hit.cell) if str(hit.type) == "ground" else "")
			if amounts.has(key):
				var time := lerpf(a, b, float(hit.fraction)) - begin
				var remaining := maxf(0.0, float(flight.ember) - float(flight.profile.air_decay) * time)
				amounts[key] += minf(remaining, float(flight.profile.contact_rate) * float(flight.profile.contact_seconds))
			break # First original static contact ends this forecast, even an occluder.
	return amounts

func _fire_policy_targets(target: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if str(target.get("type", "")) == "area":
		for cell: Array in target.cells: result.append({"type": "ground", "cell": cell.duplicate()})
	elif str(target.get("type", "")) in ["ground", "structure"]: result.append(target.duplicate(true))
	return result

func _fire_policy_allows(person: Dictionary, target: Dictionary, draft: Dictionary = {}) -> bool:
	var owner_ref: Variant = person.owner
	var policy: Dictionary = owner_ref.ranged_fire_policy if draft.is_empty() else _native_begin_policy(draft, owner_ref)
	if policy.is_empty(): return true
	var source: Variant = _fire_owner_source(owner_ref)
	if int(policy.serial) != owner_ref.ranged_order_serial or source is TerrainArmy and int(policy.main_serial) != source.get_order_serial():
		if draft.is_empty(): owner_ref.ranged_fire_policy = {}
		else: policy.clear()
		return true
	var step := floori((fire_action_cursor + SiteRuntime.FIRE_EPS) * SiteRuntime.FIRE_HZ)
	if step == int(policy.last_decision_step): return bool(policy.allow)
	policy.last_decision_step = step
	policy.allow = true
	policy.reason = "EVALUATING"
	if str(policy.mode) == "DESTROY_FUNCTION":
		var feature: Dictionary = terrain.site.features.get(str(target.get("feature_id", "")), {})
		var observation := _fire_policy_observed(person, target)
		if feature.is_empty(): policy.allow = false; policy.reason = "TARGET_INVALIDATED"
		elif not observation.is_empty() and SiteRuntime.feature_function_state(feature, str(policy.service)) in ["DISABLED", "DESTROYED"]:
			policy.allow = false
			policy.reason = "OBSERVED_FUNCTION_DISABLED"
		return bool(policy.allow)
	var targets := _fire_policy_targets(target)
	var forecasts := fire_pending_ignition_estimate(owner_ref, targets)
	policy.pending_estimate = forecasts # Disposable original-flight projection only.
	var all_stable := not targets.is_empty()
	var pending := 0.0
	for part_target: Dictionary in targets:
		var key := _fire_policy_target_key(part_target)
		var observation := _fire_policy_observed(person, part_target)
		var prior: Dictionary = policy.confirmations.get(key, {"step": -1, "count": 0})
		if not observation.is_empty() and int(observation.thermal_step) != int(prior.step):
			prior.count = mini(3, int(prior.count) + 1) if bool(observation.burning) and int(observation.thermal_step) == int(prior.step) + 1 else (1 if bool(observation.burning) else 0)
			prior.step = int(observation.thermal_step)
			policy.confirmations[key] = prior
		if observation.is_empty() or int(prior.count) < 3: all_stable = false
		pending += float(forecasts.get(key, 0.0))
	if all_stable:
		policy.allow = false
		policy.reason = "OBSERVED_STABLE_BURNING"
	elif pending >= float(policy.pending_threshold):
		if fire_action_cursor >= float(policy.wait_deadline): policy.wait_deadline = fire_action_cursor + 4.2
		policy.allow = false
		policy.reason = "PAID_FLIGHTS_PENDING"
	elif fire_action_cursor < float(policy.wait_deadline):
		policy.allow = false
		policy.reason = "OBSERVATION_WAIT"
	return bool(policy.allow)

func _fire_policy_cancel_unreleased(owner_ref: Variant, draft: Dictionary = {}) -> void:
	var reservations: Dictionary = fire_reservations if draft.is_empty() else draft.reservations
	for identity: int in reservations.keys():
		if is_same(reservations[identity].person.owner, owner_ref): reservations.erase(identity)

func _advance_fire_policy_decisions(people: Array[Dictionary], draft: Dictionary = {}) -> void:
	# The original release scheduler supplies the completed action cursor.
	# Observation continues during cooldown or LOS rejection, without releasing.
	var seen := {}
	for person: Dictionary in people:
		var owner_ref: Variant = person.get("owner")
		if not is_instance_valid(owner_ref) or owner_ref.data != terrain or not owner_ref.ranged_enabled or owner_ref.ranged_fire_policy.is_empty(): continue
		var unit := int(person.unit)
		if not (owner_ref.combat_can_act(unit) if unit >= 0 else owner_ref.can_act()): continue
		var group := _fire_policy_group(owner_ref)
		if seen.has(group): continue
		seen[group] = true
		if not _fire_policy_allows(person, owner_ref.ranged_target, draft): _fire_policy_cancel_unreleased(owner_ref, draft)

func _draw_fire_smoke(presentation: Node2D) -> void:
	# ponytail: basic bounded smoke discs; authored emitter/LOD is the P6 gate.
	# Read the original logical smoke field, with no visual simulation or clock.
	var smoke: Dictionary = terrain.site.get("fire", {}).get("smoke", {})
	var viewport := presentation.get_viewport_rect().grow(48.0)
	var canvas := presentation.get_global_transform_with_canvas()
	var span := float(SiteCombatRules.fire_environment_profile().smoke_vertical_span)
	var inspected := 0
	var drawn := 0
	for key: String in smoke:
		if inspected >= 1024 or drawn >= 256: return
		inspected += 1
		var entry: Dictionary = smoke[key]
		var density := maxf(0.0, float(entry.density))
		if density <= 0.0001: continue
		var cell := terrain.cell_from_index(int(entry.cell))
		var ground := (Vector2(cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		var point := _fire_screen(Vector3(cell.x + 0.5, cell.y + 0.5, int(entry.layer) * span + 0.75), _fire_surface_height(ground)) + terrain.surface_visual_offset_at(ground)
		if not viewport.has_point(canvas * point): continue
		presentation.draw_circle(point, 18.0 + minf(20.0, sqrt(density) * 3.0), Color(0.22, 0.22, 0.23, minf(0.55, density / 6.0)))
		drawn += 1

# OUTPUT ONLY / NOT RUN. Original Lab transport helpers; no independent save owner.
const FIRE_TRANSPORT_FIELDS := ["version", "config_version", "action_cursor", "release_sequence", "exposure_sequence", "round_robin", "member_cursor", "physical_ranged_enabled", "projectiles", "reservations", "orders"]
const FIRE_FLIGHT_FIELDS := ["origin", "velocity", "gravity", "total", "life", "projectile_id", "source_member_id", "source_formation_id", "order_serial", "spawn_action", "source_cell", "shooter", "profile", "elapsed", "ember", "resolved", "aim_key", "position", "config_version"]
const FIRE_SHOOTER_FIELDS := ["ability", "training", "fatigue", "morale", "armorbonus", "weapon", "armor", "skill"]
const FIRE_PREPARATION_FIELDS := ["person_id", "formation_id", "target", "mode", "serial", "stamp", "source", "ready_at", "deadline"]
const FIRE_ORDER_FIELDS := ["group", "serial", "issuer_id", "enabled", "mode", "target", "release_ids", "ranged_fire_policy"]
const FIRE_POLICY_FIELDS := ["version", "serial", "main_serial", "mode", "service", "last_decision_step", "allow", "reason", "confirmations", "wait_deadline", "pending_threshold"]

static func _fire_transport_fields(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size(): return false
	for field: String in fields:
		if not value.has(field): return false
	return true

static func _fire_transport_whole(value: Variant, low: int = 0, high: int = 2147483647) -> bool:
	return TerrainTestCharacter._saved_number(value, low, high) and float(value) == floorf(float(value))

static func _fire_transport_cell(data: TerrainData, value: Variant) -> bool:
	return value is Array and value.size() == 2 and _fire_transport_whole(value[0], 0, data.size.x - 1) and _fire_transport_whole(value[1], 0, data.size.y - 1)

static func _fire_transport_vector(value: Variant, maximum: float) -> bool:
	if not value is Array or value.size() != 3: return false
	for component: Variant in value:
		if not TerrainTestCharacter._saved_number(component, -maximum, maximum): return false
	return true

static func _fire_transport_time_epsilon(action_cursor: float) -> float:
	# The original cursor and each flight accumulate the same small intervals.
	# Keep a sub-microsecond allowance at the admitted signed-32-bit 5 Hz limit.
	return maxf(0.00000001, absf(action_cursor) * 0.000000000000002)

static func _fire_transport_profile(raw: Variant, weapon: String) -> Dictionary:
	if not raw is Dictionary or not raw.get("mode") is String: return SiteRuntime.fail("CORRUPT_FIRE_PROFILE")
	var expected := SiteCombatRules.fire_ranged_profile(weapon, str(raw.mode))
	if expected.is_empty(): return SiteRuntime.fail("CORRUPT_FIRE_PROFILE")
	var fields: Array = expected.keys()
	fields.append_array(["nominal_distance", "smoke_optical_depth"])
	if not _fire_transport_fields(raw, fields) \
		or not TerrainTestCharacter._saved_number(raw.nominal_distance, 0.000000001, float(expected.range) + sqrt(2.0)) \
		or not (raw.smoke_optical_depth is int or raw.smoke_optical_depth is float) \
		or not is_finite(float(raw.smoke_optical_depth)) or float(raw.smoke_optical_depth) < 0.0: return SiteRuntime.fail("CORRUPT_FIRE_PROFILE")
	# P4 records the optical depth of the ORIGINAL release ray. Recomputing from
	# today's smoke would silently change an already paid flight after load.
	var environment := SiteCombatRules.fire_environment_profile()
	if expected.get("environment_config_version") != environment.config_version: return SiteRuntime.fail("CORRUPT_FIRE_PROFILE_VERSION")
	var multiplier := float(expected.scatter_multiplier) * clampf(1.0 + float(raw.smoke_optical_depth) * float(environment.smoke_scatter_per_depth), 1.0, float(environment.smoke_scatter_max))
	if not TerrainTestCharacter._saved_number(raw.scatter_multiplier, 0.0, float(expected.scatter_multiplier) * float(environment.smoke_scatter_max)) \
		or absf(float(raw.scatter_multiplier) - multiplier) > 0.000000001: return SiteRuntime.fail("CORRUPT_FIRE_SMOKE_SCATTER")
	for field: String in expected:
		if field == "scatter_multiplier": continue
		if expected[field] is int or expected[field] is float:
			if not TerrainTestCharacter._saved_number(raw[field], float(expected[field]), float(expected[field])): return SiteRuntime.fail("CORRUPT_FIRE_PROFILE")
		elif not raw[field] is String or raw[field] != expected[field]: return SiteRuntime.fail("CORRUPT_FIRE_PROFILE")
	expected.nominal_distance = float(raw.nominal_distance)
	expected.smoke_optical_depth = float(raw.smoke_optical_depth)
	expected.scatter_multiplier = float(raw.scatter_multiplier)
	return SiteRuntime.ok("", {"profile": expected})

static func _fire_transport_target(data: TerrainData, value: Variant, empty_allowed: bool = false) -> Dictionary:
	if not value is Dictionary: return SiteRuntime.fail("CORRUPT_FIRE_TARGET")
	if value.is_empty(): return SiteRuntime.ok("", {"target": {}}) if empty_allowed else SiteRuntime.fail("CORRUPT_FIRE_TARGET")
	var target: Dictionary = value.duplicate(true)
	match target.get("type"):
		"person":
			if not _fire_transport_fields(target, ["type", "person_id"]) or not _fire_transport_whole(target.person_id, 1): return SiteRuntime.fail("CORRUPT_FIRE_TARGET")
			target.person_id = int(target.person_id)
		"structure":
			if not _fire_transport_fields(target, ["type", "feature_id", "part_id"]): return SiteRuntime.fail("CORRUPT_FIRE_TARGET")
			for field: String in ["feature_id", "part_id"]:
				if not target[field] is String or target[field].is_empty() or target[field].length() > 128: return SiteRuntime.fail("CORRUPT_FIRE_TARGET")
		"ground":
			if not _fire_transport_fields(target, ["type", "cell"]) or not _fire_transport_cell(data, target.cell): return SiteRuntime.fail("CORRUPT_FIRE_TARGET")
			target.cell = [int(target.cell[0]), int(target.cell[1])]
		"area":
			if not _fire_transport_fields(target, ["type", "cells"]) or not target.cells is Array or target.cells.is_empty() or target.cells.size() > 256: return SiteRuntime.fail("CORRUPT_FIRE_TARGET")
			var seen := {}
			for index in range(target.cells.size()):
				var cell: Variant = target.cells[index]
				if not _fire_transport_cell(data, cell): return SiteRuntime.fail("CORRUPT_FIRE_TARGET")
				var key := Vector2i(int(cell[0]), int(cell[1]))
				if seen.has(key): return SiteRuntime.fail("CORRUPT_FIRE_TARGET")
				seen[key] = true
				target.cells[index] = [key.x, key.y]
		_: return SiteRuntime.fail("CORRUPT_FIRE_TARGET")
	# Target existence is checked by the original next decision, not save admission:
	# an already paid flight survives the original death/removal of its target/source.
	return SiteRuntime.ok("", {"target": target})

static func _fire_transport_policy(data: TerrainData, raw: Variant, order: Dictionary, action_cursor: float) -> Dictionary:
	if not raw is Dictionary: return SiteRuntime.fail("CORRUPT_FIRE_POLICY")
	if raw.is_empty(): return SiteRuntime.ok("", {"policy": {}}) # Original CONTINUOUS policy.
	var step := floori((action_cursor + SiteRuntime.FIRE_EPS) * SiteRuntime.FIRE_HZ)
	var epsilon := _fire_transport_time_epsilon(action_cursor)
	if not _fire_transport_fields(raw, FIRE_POLICY_FIELDS) or raw.version != "fire_policy_v1" \
		or not bool(order.enabled) or order.mode != "FIRE_ARROW" or order.target.get("type") not in ["structure", "ground", "area"] \
		or not _fire_transport_whole(raw.serial, 1) or int(raw.serial) != int(order.serial) \
		or not _fire_transport_whole(raw.main_serial) or int(order.group) < 0 and int(raw.main_serial) != 0 \
		or raw.mode not in ["IGNITE_ONLY", "DESTROY_FUNCTION"] \
		or raw.service not in ["", "lodging", "intake", "production", "water", "garrison", "recovery", "training"] \
		or not _fire_transport_whole(raw.last_decision_step, -1, step) or not raw.allow is bool \
		or raw.reason not in ["EVALUATING", "OBSERVED_FUNCTION_DISABLED", "TARGET_INVALIDATED", "OBSERVED_STABLE_BURNING", "PAID_FLIGHTS_PENDING", "OBSERVATION_WAIT"] \
		or not raw.confirmations is Dictionary or raw.confirmations.size() > 256 \
		or not TerrainTestCharacter._saved_number(raw.wait_deadline, 0.0, action_cursor + 4.2 + epsilon): return SiteRuntime.fail("CORRUPT_FIRE_POLICY")
	var threshold := 100.0 if order.target.type == "structure" else 40.0
	if not TerrainTestCharacter._saved_number(raw.pending_threshold, threshold, threshold) \
		or bool(raw.allow) != (raw.reason == "EVALUATING"): return SiteRuntime.fail("CORRUPT_FIRE_POLICY_PROGRESS")
	if raw.mode == "DESTROY_FUNCTION":
		if order.target.type != "structure" or not raw.confirmations.is_empty() \
			or raw.reason not in ["EVALUATING", "OBSERVED_FUNCTION_DISABLED", "TARGET_INVALIDATED"] \
			or float(raw.wait_deadline) > action_cursor + epsilon: return SiteRuntime.fail("CORRUPT_FIRE_POLICY_PROGRESS")
	elif raw.reason not in ["EVALUATING", "OBSERVED_STABLE_BURNING", "PAID_FLIGHTS_PENDING", "OBSERVATION_WAIT"]:
		return SiteRuntime.fail("CORRUPT_FIRE_POLICY_PROGRESS")
	if int(raw.last_decision_step) == -1 and (raw.reason != "EVALUATING" or not raw.confirmations.is_empty() \
		or float(raw.wait_deadline) > action_cursor + epsilon): return SiteRuntime.fail("CORRUPT_FIRE_POLICY_PROGRESS")
	# Derive allowed keys solely from the validated typed command. No live heat,
	# target existence, flight forecast, ammunition, or ownership is changed here.
	var targets := {}
	match order.target.type:
		"structure": targets["structure:%s:%s" % [order.target.feature_id, order.target.part_id]] = true
		"ground": targets["ground:%d" % data.index(Vector2i(int(order.target.cell[0]), int(order.target.cell[1])))] = true
		"area":
			for cell: Array in order.target.cells:
				targets["ground:%d" % data.index(Vector2i(int(cell[0]), int(cell[1])))] = true
	var policy: Dictionary = raw.duplicate(true)
	for key: Variant in raw.confirmations:
		var confirmation: Variant = raw.confirmations[key]
		if not key is String or not targets.has(key) or not _fire_transport_fields(confirmation, ["step", "count"]) \
			or not _fire_transport_whole(confirmation.step, 0, int(raw.last_decision_step)) \
			or not _fire_transport_whole(confirmation.count, 0, 3): return SiteRuntime.fail("CORRUPT_FIRE_POLICY_CONFIRMATION")
		policy.confirmations[key] = {"step": int(confirmation.step), "count": int(confirmation.count)}
	if raw.reason == "OBSERVED_STABLE_BURNING":
		for key: String in targets:
			if int(policy.confirmations.get(key, {}).get("count", 0)) != 3: return SiteRuntime.fail("CORRUPT_FIRE_POLICY_CONFIRMATION")
	if raw.reason in ["PAID_FLIGHTS_PENDING", "OBSERVATION_WAIT"] \
		and float(raw.wait_deadline) <= float(raw.last_decision_step) / SiteRuntime.FIRE_HZ: return SiteRuntime.fail("CORRUPT_FIRE_POLICY_PROGRESS")
	for field: String in ["serial", "main_serial", "last_decision_step"]: policy[field] = int(raw[field])
	policy.wait_deadline = float(raw.wait_deadline)
	policy.pending_threshold = threshold
	policy.pending_estimate = {} # Recomputed by the original next policy decision.
	# Root physical validation compares main_serial with the prepared original Army.
	return SiteRuntime.ok("", {"policy": policy})

static func validate_fire_transport(data: TerrainData, raw: Variant) -> Dictionary:
	if data == null: return SiteRuntime.fail("CORRUPT_FIRE_TRANSPORT")
	if not SiteRuntime._fire_snapshot_json(raw):
		if raw is Dictionary:
			for field: Variant in raw:
				if not SiteRuntime._fire_snapshot_json(raw[field]):
					if field == "projectiles" and raw[field] is Array:
						for index in range(raw[field].size()):
							if not raw[field][index] is Dictionary:
								return SiteRuntime.fail("CORRUPT_FIRE_TRANSPORT", "Invalid projectile row")
							for flight_field: Variant in raw[field][index]:
								if not SiteRuntime._fire_snapshot_json(raw[field][index][flight_field]):
									return SiteRuntime.fail("CORRUPT_FIRE_TRANSPORT", "Non-JSON flight field: " + str(flight_field))
					return SiteRuntime.fail("CORRUPT_FIRE_TRANSPORT", "Non-JSON transport field: " + str(field))
		return SiteRuntime.fail("CORRUPT_FIRE_TRANSPORT", "Transport contains a non-JSON value")
	if not _fire_transport_fields(raw, FIRE_TRANSPORT_FIELDS) or not _fire_transport_whole(raw.version, 1, 1) \
		or raw.config_version != SiteCombatRules.FIRE_RANGED_CONFIG_VERSION or not TerrainTestCharacter._saved_number(raw.action_cursor, 0.0, float(SiteRuntime.FIRE_MAX_STEP) / SiteRuntime.FIRE_HZ) \
		or not _fire_transport_whole(raw.release_sequence) or not _fire_transport_whole(raw.exposure_sequence) \
		or not _fire_transport_whole(raw.round_robin, 0, 20000) or not raw.physical_ranged_enabled is bool \
		or not raw.projectiles is Array or not raw.reservations is Array or raw.projectiles.size() + raw.reservations.size() > 8192 \
		or not raw.member_cursor is Array or raw.member_cursor.size() > 20000 or not raw.orders is Array or raw.orders.size() > 20000:
		return SiteRuntime.fail("CORRUPT_FIRE_TRANSPORT")
	var state: Dictionary = raw.duplicate(true)
	var time_epsilon := _fire_transport_time_epsilon(float(raw.action_cursor))
	for field: String in ["version", "release_sequence", "exposure_sequence", "round_robin"]: state[field] = int(raw[field])
	state.action_cursor = float(raw.action_cursor)
	var ids := {}
	for index in range(state.projectiles.size()):
		var flight: Variant = state.projectiles[index]
		if not _fire_transport_fields(flight, FIRE_FLIGHT_FIELDS) or not _fire_transport_whole(flight.projectile_id, 1, int(raw.release_sequence)) \
			or ids.has(int(flight.projectile_id)) or not _fire_transport_whole(flight.source_member_id, 1) \
			or not _fire_transport_whole(flight.source_formation_id) or not _fire_transport_whole(flight.order_serial) \
			or not _fire_transport_cell(data, flight.source_cell) or not flight.resolved is bool or flight.resolved != false \
			or not flight.aim_key is String or flight.aim_key.is_empty() or flight.aim_key.length() > 256 or flight.config_version != raw.config_version \
			or not _fire_transport_fields(flight.shooter, FIRE_SHOOTER_FIELDS): return SiteRuntime.fail("CORRUPT_FIRE_FLIGHT")
		for field: String in ["ability", "fatigue", "morale"]:
			if not TerrainTestCharacter._saved_number(flight.shooter[field], 0.0, 100.0): return SiteRuntime.fail("CORRUPT_FIRE_SHOOTER")
		if not TerrainTestCharacter._saved_number(flight.shooter.training, 0.0, 1000000000000.0): return SiteRuntime.fail("CORRUPT_FIRE_SHOOTER")
		if not TerrainTestCharacter._saved_number(flight.shooter.armorbonus, 0.0, 1000.0) or not flight.shooter.weapon is String \
			or flight.shooter.weapon.is_empty() or flight.shooter.weapon.length() > 128 or not flight.shooter.armor is String \
			or flight.shooter.armor.length() > 128 or flight.shooter.skill not in ["", "power", "brace"]: return SiteRuntime.fail("CORRUPT_FIRE_SHOOTER")
		var profile_result := _fire_transport_profile(flight.profile, str(flight.shooter.weapon))
		if not profile_result.ok: return profile_result
		var expected: Dictionary = profile_result.profile
		if not TerrainTestCharacter._saved_number(flight.gravity, float(expected.gravity), float(expected.gravity)) \
			or not TerrainTestCharacter._saved_number(flight.life, float(expected.life), float(expected.life)) \
			or not TerrainTestCharacter._saved_number(flight.total, 0.000000001, float(expected.life)) \
			or absf(float(flight.total) - float(expected.nominal_distance) / float(expected.speed)) > 0.000000001 \
			or not TerrainTestCharacter._saved_number(flight.elapsed, 0.0, float(expected.life)) \
			or float(flight.elapsed) >= float(expected.life) \
			or not TerrainTestCharacter._saved_number(flight.spawn_action, 0.0, float(raw.action_cursor)) \
			or absf(float(flight.spawn_action) + float(flight.elapsed) - float(raw.action_cursor)) > time_epsilon \
			or not TerrainTestCharacter._saved_number(flight.ember, 0.0, float(expected.ember)): return SiteRuntime.fail("CORRUPT_FIRE_FLIGHT_TIME")
		# Past cover can change. Validate conservative physical bounds, preserving
		# the original consumed ember; never recalculate rain from today's roof.
		var ember_max := maxf(0.0, float(expected.ember) - float(expected.air_decay) * float(flight.elapsed))
		var ember_min := maxf(0.0, float(expected.ember) - (float(expected.air_decay) + float(expected.rain_decay)) * float(flight.elapsed))
		if float(flight.ember) > ember_max + time_epsilon or float(flight.ember) + time_epsilon < ember_min: return SiteRuntime.fail("CORRUPT_FIRE_EMBER")
		for field: String in ["origin", "position"]:
			if not _fire_transport_vector(flight[field], 10000000.0): return SiteRuntime.fail("CORRUPT_FIRE_FLIGHT_VECTOR")
		if not _fire_transport_vector(flight.velocity, 10000.0): return SiteRuntime.fail("CORRUPT_FIRE_FLIGHT_VECTOR")
		for field: String in ["origin", "position", "velocity"]:
			var components: Array = flight[field]
			flight[field] = Vector3(float(components[0]), float(components[1]), float(components[2]))
		for field: String in ["origin", "position"]:
			var point: Vector3 = flight[field]
			if point.x < 0.0 or point.y < 0.0 or point.x >= data.size.x or point.y >= data.size.y: return SiteRuntime.fail("CORRUPT_FIRE_FLIGHT_POSITION")
		if SiteCombatRules.fire_position(flight, float(flight.elapsed)).distance_to(flight.position) > 0.00001: return SiteRuntime.fail("CORRUPT_FIRE_FLIGHT_POSITION")
		for field: String in ["projectile_id", "source_member_id", "source_formation_id", "order_serial"]: flight[field] = int(flight[field])
		for field: String in ["gravity", "total", "life", "spawn_action", "elapsed", "ember"]: flight[field] = float(flight[field])
		for field: String in ["ability", "training", "fatigue", "morale", "armorbonus"]: flight.shooter[field] = float(flight.shooter[field])
		flight.profile = expected
		flight.source_cell = Vector2i(int(flight.source_cell[0]), int(flight.source_cell[1]))
		ids[int(flight.projectile_id)] = true
	var orders := {}
	for order: Variant in state.orders:
		if not _fire_transport_fields(order, FIRE_ORDER_FIELDS) or not _fire_transport_whole(order.group, -2147483647) or int(order.group) == 0 \
			or orders.has(int(order.group)) or not _fire_transport_whole(order.serial) or not _fire_transport_whole(order.issuer_id) \
			or not order.enabled is bool or order.mode not in ["NORMAL", "FIRE_ARROW"] or not order.release_ids is Array or order.release_ids.size() > 20000: return SiteRuntime.fail("CORRUPT_FIRE_ORDER")
		var target := _fire_transport_target(data, order.target, not bool(order.enabled))
		if not target.ok or not bool(order.enabled) and not target.target.is_empty() \
			or bool(order.enabled) and (int(order.issuer_id) <= 0 or int(order.serial) <= 0) \
			or not bool(order.enabled) and int(order.issuer_id) != 0: return SiteRuntime.fail("CORRUPT_FIRE_ORDER")
		if int(order.group) < 0 and bool(order.enabled) and int(order.issuer_id) != -int(order.group): return SiteRuntime.fail("CORRUPT_FIRE_ORDER")
		order.target = target.target
		var policy := _fire_transport_policy(data, order.ranged_fire_policy, order, float(raw.action_cursor))
		if not policy.ok: return policy
		order.ranged_fire_policy = policy.policy
		var released := {}
		for pair: Variant in order.release_ids:
			if not pair is Array or pair.size() != 2 or not _fire_transport_whole(pair[0], 1) or not _fire_transport_whole(pair[1], 0, int(raw.release_sequence)) or released.has(int(pair[0])): return SiteRuntime.fail("CORRUPT_FIRE_RELEASE_WATERMARK")
			released[int(pair[0])] = int(pair[1])
		order.release_ids = released
		for field: String in ["group", "serial", "issuer_id"]: order[field] = int(order[field])
		orders[int(order.group)] = order
	var prepared := {}
	for reservation: Variant in state.reservations:
		if not _fire_transport_fields(reservation, FIRE_PREPARATION_FIELDS) or not _fire_transport_whole(reservation.person_id, 1) \
			or prepared.has(int(reservation.person_id)) or not _fire_transport_whole(reservation.formation_id) or not _fire_transport_whole(reservation.serial) \
			or reservation.mode not in ["NORMAL", "FIRE_ARROW"] or not _fire_transport_cell(data, reservation.source) \
			or not _fire_transport_fields(reservation.stamp, ["holder", "version", "cargo"]) \
			or reservation.stamp.holder != "person:%d" % int(reservation.person_id) or not _fire_transport_whole(reservation.stamp.version) \
			or not reservation.stamp.cargo is Dictionary or reservation.stamp.cargo.size() > 256 \
			or not TerrainTestCharacter._saved_number(reservation.ready_at, 0.0, float(raw.action_cursor) + 0.8 + time_epsilon) \
			or not TerrainTestCharacter._saved_number(reservation.deadline, 0.0, float(raw.action_cursor) + 1.05 + time_epsilon) \
			or absf(float(reservation.deadline) - (float(reservation.ready_at) + FIRE_RELEASE_WINDOW_SECONDS)) > time_epsilon: return SiteRuntime.fail("CORRUPT_FIRE_PREPARATION")
		var prepare_seconds := float(SiteCombatRules.fire_ranged_profile("bow_01", str(reservation.mode)).prepare)
		if float(reservation.ready_at) + time_epsilon < prepare_seconds or float(reservation.ready_at) > float(raw.action_cursor) + prepare_seconds + time_epsilon \
			or float(reservation.deadline) + EXCHANGE_ACTION_STEP + time_epsilon < float(raw.action_cursor): return SiteRuntime.fail("CORRUPT_FIRE_PREPARATION_TIME")
		for ammo: Variant in reservation.stamp.cargo:
			if not ammo is String or not SiteEnvironment.ITEM_NAMES.has(ammo) or not _fire_transport_whole(reservation.stamp.cargo[ammo], 0, 1000000): return SiteRuntime.fail("CORRUPT_FIRE_PREPARATION")
			reservation.stamp.cargo[ammo] = int(reservation.stamp.cargo[ammo])
		var target := _fire_transport_target(data, reservation.target)
		if not target.ok: return target
		reservation.target = target.target
		var group := int(reservation.formation_id) if int(reservation.formation_id) > 0 else -int(reservation.person_id)
		var order: Dictionary = orders.get(group, {})
		if order.is_empty() or int(order.serial) != int(reservation.serial) or str(order.mode) != str(reservation.mode) \
			or bool(order.enabled) and order.target != reservation.target or not bool(order.enabled) and reservation.target.type != "person":
			return SiteRuntime.fail("CORRUPT_FIRE_PREPARATION_ORDER", "order=%s/%s enabled=%s target=%s reservation=%s/%s target=%s" % [
				str(order.get("serial", -1)), str(order.get("mode", "")), str(order.get("enabled", false)),
				str(order.get("target", {})), str(reservation.get("serial", -1)), str(reservation.get("mode", "")),
				str(reservation.get("target", {}))])
		for field: String in ["person_id", "formation_id", "serial"]: reservation[field] = int(reservation[field])
		for field: String in ["ready_at", "deadline"]: reservation[field] = float(reservation[field])
		reservation.stamp.version = int(reservation.stamp.version)
		reservation.source = Vector2i(int(reservation.source[0]), int(reservation.source[1]))
		prepared[int(reservation.person_id)] = reservation
	var members := {}
	for pair: Variant in state.member_cursor:
		if not pair is Array or pair.size() != 2 or not _fire_transport_whole(pair[0], -2147483647) or int(pair[0]) == 0 \
			or members.has(int(pair[0])) or not _fire_transport_whole(pair[1], 1): return SiteRuntime.fail("CORRUPT_FIRE_FAIRNESS")
		members[int(pair[0])] = int(pair[1])
	state.orders = orders
	state.reservations = prepared
	state.member_cursor = members
	return SiteRuntime.ok("", {"state": state})

func capture_fire_transport() -> Dictionary:
	if terrain == null or _fire_committing or _fire_advancing or not _fire_boundary_error.is_empty() \
		or _siege_collect_contacts or not _siege_contact_batch.is_empty() or not terrain.get_meta(&"fire_boundary", {}).is_empty() \
		or terrain.has_meta(&"fire_structure_step"): return SiteRuntime.fail("BUSY", "原 shared barrier 尚未完成")
	return _capture_fire_transport_payload()

func _capture_fire_transport_payload() -> Dictionary:
	var state := {"version": 1, "config_version": SiteCombatRules.FIRE_RANGED_CONFIG_VERSION,
		"action_cursor": fire_action_cursor, "release_sequence": _fire_release_sequence,
		"exposure_sequence": _fire_exposure_sequence, "round_robin": _fire_round_robin,
		"member_cursor": [], "physical_ranged_enabled": physical_ranged_enabled,
		"projectiles": [], "reservations": [], "orders": []}
	for group: int in _fire_member_cursor:
		state.member_cursor.append([group, int(_fire_member_cursor[group])])
	for current: Dictionary in fire_projectiles:
		var flight := current.duplicate(true)
		for field: String in ["origin", "position", "velocity"]:
			var vector: Vector3 = current[field]
			flight[field] = [vector.x, vector.y, vector.z]
		var cell: Vector2i = current.source_cell
		flight.source_cell = [cell.x, cell.y]
		var profile: Dictionary = flight.profile
		var json_profile := {}
		for field: Variant in profile: json_profile[str(field)] = profile[field]
		flight.profile = json_profile
		var json_flight: Variant = SiteRuntime._fire_snapshot_json_copy(flight)
		if not json_flight is Dictionary or not SiteRuntime._fire_snapshot_json(json_flight):
			return SiteRuntime.fail("CORRUPT_FIRE_TRANSPORT", "Fire flight is not JSON-safe")
		state.projectiles.append(json_flight)
	for identity: int in fire_reservations:
		var current: Dictionary = fire_reservations[identity]
		var person: Dictionary = current.person
		var owner_ref: Variant = person.owner
		if not is_instance_valid(owner_ref): return SiteRuntime.fail("BUSY", "原射擊準備失去人物擁有者")
		if not _fire_person_ready(person, true): return SiteRuntime.fail("BUSY", "原射手權限或活動狀態尚未收束")
		if int(owner_ref.ranged_order_serial) != int(current.serial) or str(owner_ref.ranged_ammo_mode) != str(current.mode):
			return SiteRuntime.fail("BUSY", "原射擊命令世代尚待取消邊界")
		if _fire_holder_stamp(person) != current.stamp: return SiteRuntime.fail("BUSY", "原本人彈藥持有人版本已變更")
		var source: Vector2i = current.source
		state.reservations.append({"person_id": identity, "formation_id": int(owner_ref.team_id) if owner_ref is TerrainArmy or owner_ref is CrowdPersonOwner and owner_ref.has_army() else 0,
			"target": current.target.duplicate(true), "mode": str(current.mode), "serial": int(current.serial),
			"stamp": current.stamp.duplicate(true), "source": [source.x, source.y],
			"ready_at": float(current.ready_at), "deadline": float(current.deadline)})
	for owner_ref: Node2D in _fire_transport_owners():
		var release_ids: Array = []
		var group := int(owner_ref.team_id) if owner_ref is TerrainArmy else -int(owner_ref.person_id)
		if owner_ref is TerrainArmy:
			for identity: int in owner_ref._ranged_last_release_ids:
				release_ids.append([identity, int(owner_ref._ranged_last_release_ids[identity])])
		else: release_ids.append([int(owner_ref.person_id), int(owner_ref._ranged_last_release_id)])
		var policy: Dictionary = owner_ref.ranged_fire_policy.duplicate(true)
		if not policy.is_empty():
			var native_fields: Array = FIRE_POLICY_FIELDS.duplicate()
			native_fields.append("pending_estimate")
			if not _fire_transport_fields(policy, native_fields) or not policy.pending_estimate is Dictionary: return SiteRuntime.fail("CORRUPT_FIRE_POLICY")
			policy.erase("pending_estimate") # Only the capture clone loses this derived cache.
		state.orders.append({"group": group, "serial": int(owner_ref.ranged_order_serial), "issuer_id": int(owner_ref.ranged_order_issuer_id),
			"enabled": bool(owner_ref.ranged_enabled), "mode": str(owner_ref.ranged_ammo_mode),
			"target": owner_ref.ranged_target.duplicate(true), "release_ids": release_ids, "ranged_fire_policy": policy})
	var valid := validate_fire_transport(terrain, state)
	return valid if not valid.ok else SiteRuntime.ok("", {"state": state})

# Original accepted life effects are consumed by the original body owners.
func consume_region_life_events() -> Dictionary:
	var events: Variant = terrain.site.get("region_life_events", [])
	if not events is Array: return SiteRuntime.fail("INVALID_REGION_LIFE_EVENTS")
	var targets := {}
	var previous := 0
	for event: Dictionary in events:
		var identity := int(event.get("person_id", -1))
		if int(event.sequence) <= previous: return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
		previous = int(event.sequence)
		if str(event.status) == "complete": continue
		var target := _original_person_target(identity)
		if target.is_empty(): return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
		var hp := float(target.owner.combat_hot_get(int(target.unit), &"hp")) if int(target.unit) >= 0 else float(target.owner.hp)
		if hp <= 0.0: return SiteRuntime.fail("STALE_REGION_LIFE_OWNER", "原人物已死亡；不能重送或喚醒")
		if str(event.kind) == "supply_damage" and absf(hp - float(event.old_hp)) > 0.0000001:
			return SiteRuntime.fail("STALE_REGION_LIFE_OWNER", "端點前生命與原供養收據不同")
		targets[identity] = target
	# Every original reference is checked before the first accepted effect.
	for event: Dictionary in events:
		if str(event.status) == "complete": continue
		var target: Dictionary = targets[int(event.person_id)]
		match str(event.kind):
			"supply_damage":
				var hp: float = site_controller._apply_supply_damage(int(event.person_id), float(event.loss))
				if absf(hp - float(event.ending_hp)) > 0.0000001:
					return site_controller.latch_original_step_fault(SiteRuntime.fail("REGION_LIFE_CONTRACT", "原環境傷害結果與已接受供養端點不同"))
			"wake":
				if int(target.unit) >= 0: target.owner._wake_unit(int(target.unit))
				else: target.owner._wake_up()
			_: return SiteRuntime.fail("INVALID_REGION_LIFE_EVENTS")
		event.status = "complete"
		if site_controller.region_slot != null:
			var token := str(site_controller.region_slot._marker.get("transfer_token", ""))
			var completed: Dictionary = site_controller.region_slot.complete_region_event("travel:%s:life:%d" % [token, int(event.sequence)])
			if not completed.ok: return site_controller.latch_original_step_fault(completed)
	terrain.site.erase("region_life_events")
	for team: TerrainArmy in combat_armies:
		if team.combat_enabled: team.settle_combat_command()
	# Pending original down/movement intervals retain their own legal completion.
	site_controller.settle_person_deaths(0.0)
	return SiteRuntime.ok("原旅行生命端點已消費", {"effects_complete": true})

# Original Lab interval progress and endpoint consumption share one owner.
var _region_point_pending: Dictionary = {}
var _region_point_contacts: Array[Dictionary] = []
var _region_point_wakes: Array[int] = []
var _region_point_consuming := false
var _region_point_dispatching := false # Ephemeral call-stack guard; no local effect is running during P0 handoff.

func _region_deferring_endpoint() -> bool:
	return not _region_point_pending.is_empty() and not _region_point_consuming

func _wire_region_point_owners() -> void:
	for owner: Node2D in combat_actors + combat_armies:
		if not is_instance_valid(owner): continue
		owner.set_meta(&"region_contact_sink", Callable(self, "_region_defer_contact"))
		owner.set_meta(&"region_wake_sink", Callable(self, "_region_defer_wake"))
		owner.set_meta(&"region_effect_sink", Callable(self, "_region_defer_body_effect"))
	terrain.set_meta(&"region_point_deferring", Callable(self, "_region_deferring_endpoint"))
	terrain.set_meta(&"region_point_consuming", Callable(self, "_region_consuming_endpoint"))

func _region_consuming_endpoint() -> bool:
	return _region_point_consuming

func _region_defer_contact(identity: int, packet: Dictionary) -> bool:
	return _region_defer_body_effect(identity, "contact", packet)

func _region_defer_body_effect(identity: int, kind: String, packet: Dictionary) -> bool:
	if not _region_deferring_endpoint(): return false
	if _original_person_target(identity).is_empty():
		site_controller.latch_original_step_fault(SiteRuntime.fail("STALE_REGION_LIFE_OWNER"))
		return true
	_region_point_contacts.append({"kind": kind, "person_id": identity, "packet": packet.duplicate(true)})
	return true

func _region_defer_wake(identity: int) -> bool:
	if not _region_deferring_endpoint(): return false
	if identity not in _region_point_wakes: _region_point_wakes.append(identity)
	return true

func _region_queue_original_endpoint(kind: String, packet: Dictionary) -> bool:
	if not _region_deferring_endpoint(): return false
	_region_point_contacts.append({"kind": kind, "person_id": 0, "packet": packet})
	return true

func _region_point_effect(event: Dictionary) -> Dictionary:
	var packet: Dictionary = event.packet
	if str(event.kind) == "native_environment":
		var identity: int = int(event.person_id)
		if crowd_site == null or not crowd_site.active or not crowd_site.contains_person(identity): return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
		var owner: Variant = crowd_site.person_owner(identity)
		if owner != packet.owner or int(owner.index_for_identity(identity)) != int(packet.unit) \
			or not is_same(owner.combat_units.get(int(packet.unit)), packet.body): return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
		crowd_site.apply_environment_damage(identity, float(packet.loss))
		return site_controller.original_step_fault_guard()
	if str(event.kind) == "native_manual_combat":
		# Original contact interruption, now at the SAME zero endpoint. Never
		# cancel a replaced/retargeted manual command issued after this capture.
		if is_same(packet.get("site"), terrain.site) and is_same(packet.get("manual"), terrain.site.get("manual")) \
			and str(packet.manual.get("target", "")) == str(packet.target) \
			and str(packet.manual.get("action", "")) == str(packet.action):
			SiteRuntime.mark_combat(terrain, 0.0, false)
		return SiteRuntime.ok()
	match str(event.kind):
		"exchange_batch":
			return SiteRuntime.ok() if _settle_exchange_batch(packet.batch) else SiteRuntime.fail("REGION_EXCHANGE_ENDPOINT")
		"legacy_ranged":
			_resolve_ranged_arrival(packet.owner, packet.flight, _ranged_occupants())
			return SiteRuntime.ok()
		"siege_fire_pot_impact":
			_settle_siege_fire_pot_impact(packet.flight, packet.event)
			return _fire_boundary_error if not _fire_boundary_error.is_empty() else SiteRuntime.ok()
		"fire_impact":
			_settle_fire_impact(packet.flight, packet.event)
			return _fire_boundary_error if not _fire_boundary_error.is_empty() else SiteRuntime.ok()
	var person := _original_person_target(int(event.person_id))
	if person.is_empty(): return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
	if str(event.kind) == "contact":
		if int(person.unit) >= 0: person.owner.apply_unit_contact(int(person.unit), packet)
		else: person.owner.apply_contact(packet)
	elif str(event.kind) == "ranged":
		if int(person.unit) >= 0: person.owner.ranged_apply_hit(int(person.unit), packet.source_cell, packet.packet)
		else: person.owner.ranged_apply_hit(packet.source_cell, packet.packet)
	elif str(event.kind) == "exchange":
		if int(person.unit) >= 0: person.owner.apply_exchange(int(person.unit), packet.other_cell, packet.outcome)
		else: person.owner.apply_exchange(packet.other_cell, packet.outcome)
	else: return SiteRuntime.fail("INVALID_REGION_ENDPOINT")
	return SiteRuntime.ok()

## No time advances here. Already-paid projectiles and original completed work
## stay in the original queues until this one consumer acknowledges them.
func consume_region_point(dispatch_world: bool = true) -> Dictionary:
	if _region_point_pending.is_empty(): return SiteRuntime.ok("", {"complete": true})
	if _region_point_consuming or dispatch_world and _region_point_dispatching: return SiteRuntime.fail("REENTRANT_REGION_ENDPOINT")
	if not bool(_region_point_pending.get("interval_complete", false)): return SiteRuntime.fail("REGION_INTERVAL_INCOMPLETE")
	if get_tree().paused or bool(terrain.site.get("paused", false)): return SiteRuntime.fail("PAUSED_WORLD")
	var original := terrain
	# The original world dispatcher sorts player/death events before the other
	# exact same-time events. It cannot issue a positive-time shared step.
	if dispatch_world and site_controller.region_slot != null and site_controller.region_slot.has_method("consume_due_region_events"):
		_region_point_dispatching = true
		var dispatched: Dictionary = site_controller.region_slot.call("consume_due_region_events")
		var restricted := false
		if dispatched.get("restricted_settlement") == true:
			var down: Dictionary = site_controller.region_slot._region_player_down_settlement()
			restricted = not down.is_empty() and down.lab == self and bool(down.point_pending)
		_region_point_dispatching = false
		if not dispatched.ok or terrain != original or bool(dispatched.get("player_barrier", false)) and not restricted: return dispatched
	# A world handoff may have legitimately drained this old owner's point.
	if _region_point_pending.is_empty(): return SiteRuntime.ok("", {"complete": true})
	_region_point_consuming = true
	# Environmental player life effects are consumed before autonomous contacts.
	var player_id := controlled_person_id()
	var ordered: Array[Dictionary] = []
	for event: Dictionary in _region_point_contacts:
		if int(event.person_id) == player_id and str(event.kind) == "contact" and bool(event.packet.get("environmental", false)): ordered.append(event)
	for event: Dictionary in _region_point_contacts:
		if not (int(event.person_id) == player_id and str(event.kind) == "contact" and bool(event.packet.get("environmental", false))): ordered.append(event)
	for event: Dictionary in ordered:
		var applied := _region_point_effect(event)
		if not applied.ok:
			_region_point_consuming = false
			return applied
		_region_point_contacts.erase(event)
		if int(event.person_id) == player_id:
			site_controller.check_family_death()
			if get_tree().paused or bool(terrain.site.get("paused", false)):
				_region_point_consuming = false
				return SiteRuntime.ok("", {"complete": false, "player_barrier": true})
	for identity: int in _region_point_wakes.duplicate():
		var target := _original_person_target(identity)
		if target.is_empty():
			_region_point_consuming = false
			return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
		var hp: float = float(target.owner.combat_hot_get(int(target.unit), &"hp")) if int(target.unit) >= 0 else float(target.owner.hp)
		if hp > 0.0:
			if int(target.unit) >= 0: target.owner._wake_unit(int(target.unit))
			else: target.owner._wake_up()
		_region_point_wakes.erase(identity)
	var checked_end: Dictionary = _settle_native_checked_point_endpoint()
	if not checked_end.ok:
		_region_point_consuming = false
		return checked_end
	# Original stages revalidate crews/materials/targets at the point. Passing
	# zero only completes previously integrated stages; it never starts a round.
	_advance_siege(0.0)
	for result: Dictionary in site_controller.person_actions.settle_after_contacts():
		site_controller.collect_ground_boundary_result(result)
		site_controller.show_result(result)
	for index: int in range(fire_projectiles.size() - 1, -1, -1):
		if bool(fire_projectiles[index].get("resolved", false)): fire_projectiles.remove_at(index)
	var fire_begin := float(_region_point_pending.fire_action_begin)
	var fire_end := float(_region_point_pending.fire_action_end)
	if not _finish_fire_boundary(fire_begin, fire_end):
		_region_point_consuming = false
		return _fire_boundary_error
	var siege_result := siege_flush_contact_batch()
	if not siege_result.ok:
		_region_point_consuming = false
		return siege_result
	var death_slot: RegionSaveSlot = site_controller.region_slot
	var down_proof: Dictionary = death_slot._region_player_down_settlement() if death_slot != null else {}
	site_controller.settle_person_deaths(0.0)
	site_controller.settle_supply_deliveries()
	SiteRuntime.advance_gate_operations(terrain, 0.0, site_controller._building_person_query, site_controller.reserves_cell)
	if site_controller.work_team.has_method("settle_shared_endpoints"):
		var work_end: Dictionary = site_controller.work_team.call("settle_shared_endpoints")
		if not work_end.ok:
			_region_point_consuming = false
			return work_end
	var capture_done: Dictionary = site_controller.settle_settlement_endpoint()
	if not capture_done.ok:
		_region_point_consuming = false
		return capture_done
	for team: TerrainArmy in combat_armies: team.settle_combat_command()
	_region_point_pending.clear()
	_region_point_consuming = false
	_clear_shared_work_step()
	# The proof was captured before the ORIGINAL death owner erased its timer.
	# A completed remains transaction is checkpointed before Family pauses UI.
	if not down_proof.is_empty() and down_proof.get("lab") == self and down_proof.get("point_pending") == true \
		and not site_controller._pending_deaths.has(int(down_proof.person_id)):
		if death_slot != site_controller.region_slot or int(down_proof.person_id) != player_id \
			or int(death_slot._marker.generation) != int(down_proof.generation) \
			or int(death_slot.region_registry().revision) != int(down_proof.revision):
			return SiteRuntime.fail("STALE_REGION_EVENT")
		var settled_person: Dictionary = site_controller.person_actions._person(player_id)
		if settled_person.is_empty() or float(settled_person.hp) > 0.0 \
			or not bool(site_controller.person_actions._body_get(settled_person, "loot_settled")):
			return SiteRuntime.fail("REGION_DEATH_ENDPOINT_INCOMPLETE")
		for accepted_id: String in down_proof.event_ids:
			var held := false
			for accepted: Dictionary in death_slot.region_registry().events:
				if str(accepted.id) == accepted_id:
					held = str(accepted.status) == "pending" and death_slot._region_mapped_player_death(accepted)
					break
			if not held: return SiteRuntime.fail("STALE_REGION_EVENT")
		var checkpoint: Dictionary = _region_gameplay_endpoint_checkpoint()
		if not checkpoint.ok: return checkpoint
	# Every original endpoint has completed before the final Family review.
	site_controller.check_family_death()
	if not restore_only and not get_tree().paused and not bool(terrain.site.get("paused", false)):
		site_controller._finish_ship_journey_tick()
	return SiteRuntime.ok("", {"complete": true})

## Clip known original action completions before mutating their state. Fine
## contact geometry is still queried by the original bounded action solver.
func _region_owner_action_limit(maximum: float, combat_left: float) -> float:
	var limit := maximum
	for remaining: float in site_controller._pending_deaths.values():
		if remaining > ACTION_TIME_EPSILON: limit = minf(limit, remaining)
	var game_limit := (1.0 - float(terrain.site.get("phase", 0.0))) * 60.0
	limit = minf(limit, RegionSaveSlot.GameplayClock.action_for_game(game_limit, simulation_speed, minf(maximum, combat_left)))
	for actor: TerrainTestCharacter in combat_actors:
		if not actor_present(actor): continue
		if actor.is_moving(): limit = minf(limit, maxf(ACTION_TIME_EPSILON, actor._movement_duration - actor._movement_elapsed))
		if actor.knockout_left > 0.0:
			limit = minf(limit, RegionSaveSlot.GameplayClock.action_for_game(actor.knockout_left, simulation_speed, minf(maximum, combat_left)))
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		if float(team._order_delay) > ACTION_TIME_EPSILON: limit = minf(limit, float(team._order_delay))
		for destination: Vector2i in team._reserved_cells:
			var index := int(team._reserved_cells[destination])
			if team.moving_to[index] == destination: limit = minf(limit, maxf(ACTION_TIME_EPSILON, float(team.move_duration[index]) * (1.0 - float(team.move_progress[index]))))
		for row: Dictionary in team.combat_units:
			if float(row.get("ko", 0.0)) > 0.0:
				limit = minf(limit, RegionSaveSlot.GameplayClock.action_for_game(float(row.ko), simulation_speed, minf(maximum, combat_left)))
	for vehicle: Dictionary in terrain.site.get("vehicles", {}).values():
		var remaining: float = site_controller.vehicles.region_siege_action_remaining(vehicle)
		if is_finite(remaining): limit = minf(limit, maxf(ACTION_TIME_EPSILON, remaining))
	for flight: Dictionary in siege_projectiles: limit = minf(limit, maxf(ACTION_TIME_EPSILON, float(flight.total) - float(flight.elapsed)))
	for feature: Dictionary in terrain.site.get("features", {}).values():
		if not str(feature.get("gate", {}).get("pending", "")).is_empty(): limit = minf(limit, maxf(ACTION_TIME_EPSILON, SiteRuntime.GATE_SECONDS - float(feature.gate.progress)))
		if not str(feature.get("ladder", {}).get("pending", "")).is_empty():
			var duration := 12.0 if str(feature.ladder.pending) == "deploy" else 8.0
			limit = minf(limit, maxf(ACTION_TIME_EPSILON, duration - float(feature.ladder.progress)))
	return limit


## Formula progress reuses the original complete Site stages. Its local replay
## receipt is not a publication of World time; the Slot publishes once only
## after every prepared original has reached the same accepted endpoint.
func advance_region_formula_stages(interval: Dictionary) -> Dictionary:
	return _advance_region_original_stages(interval, true)

var _shared_work_plan: Dictionary = {}
var _shared_work_requests: Array = []
var _shared_work_action_seconds := 0.0
var _shared_work_game_seconds := 0.0
var _shared_work_pools_committed := false
var _shared_movement_prepared := false
var _shared_runtime_consumed: Dictionary = {}

func _clear_shared_work_step() -> void:
	_gd_mesh_work_point = {}
	if site_controller != null: site_controller.person_actions.finish_gd_contact_job_prefix()
	if site_controller != null: site_controller.discard_checked_runtime_work_prefix()
	if crowd_site != null: crowd_site.clear_work_fatigue_interval()
	_shared_native_combat_begin = -1.0
	_native_begin_shared_window_prepared = {}
	discard_native_begin_ranged()
	_shared_vehicle_groups.clear()
	_shared_work_plan.clear()
	_shared_work_requests.clear()
	_shared_work_action_seconds = 0.0
	_shared_work_game_seconds = 0.0
	_shared_work_pools_committed = false
	_shared_movement_prepared = false
	_shared_runtime_consumed.clear()
	if site_controller != null:
		if site_controller.work_team != null: site_controller.work_team.discard_prepared_interval()
		site_controller._shared_worker_inputs.clear()
		site_controller._shared_work_plan.clear()

func _prepare_shared_work_step(action_seconds: float, game_seconds: float, tactical_seconds: float, native_combat_begin: float = -1.0) -> Dictionary:
	if not _shared_work_plan.is_empty(): return SiteRuntime.fail("SHARED_WORK_PENDING")
	if terrain == null or site_controller == null:
		return SiteRuntime.fail("SHARED_WORK_OWNER_UNAVAILABLE")
	if not is_finite(action_seconds) or action_seconds <= 0.0 or not is_finite(game_seconds) or game_seconds <= 0.0:
		return SiteRuntime.fail("INVALID_TIME")
	var collected: Dictionary = _collect_original_shared_work_requests(action_seconds, game_seconds, tactical_seconds, native_combat_begin)
	if not collected.ok: return collected
	action_seconds = float(collected.action_seconds)
	game_seconds = float(collected.game_seconds)
	var native_active: bool = crowd_site != null and crowd_site.active
	var limit := minf(game_seconds, _shared_production_event_limit(game_seconds))
	var selected_retry := float(site_controller.work_team.prepared_retry_endpoint())
	if is_finite(selected_retry) and selected_retry > ACTION_TIME_EPSILON: limit = minf(limit, selected_retry)
	var movement_limit := _region_owner_action_limit(action_seconds, tactical_seconds)
	limit = minf(limit, SiteRuntime.game_seconds(movement_limit, tactical_seconds) * simulation_speed)
	var planned := _plan_shared_vehicle_work_interval(_shared_work_requests, game_seconds)
	if not planned.ok: return planned
	for group: Dictionary in planned.pools:
		for segment: Dictionary in group.segments:
			var ending := float(segment.begin) + float(segment.seconds)
			if ending > ACTION_TIME_EPSILON: limit = minf(limit, ending)
			if float(segment.rate) > 0.0:
				var beginning := PersonFatigue.read(group.body)
				if beginning < 30.0 - ACTION_TIME_EPSILON: limit = minf(limit, (30.0 - beginning) / float(segment.rate))
				elif beginning < 100.0 - ACTION_TIME_EPSILON: limit = minf(limit, (100.0 - beginning) / float(segment.rate))
			break
	limit = minf(limit, _shared_rest_event_limit(game_seconds, planned))
	if native_active:
		var native_rest: float = crowd_site.work_fatigue_idle_limit(game_seconds, planned, maxf(0.0, _shared_native_combat_begin - action_seconds))
		if not is_finite(native_rest) or native_rest <= 0.0: return SiteRuntime.fail("INVALID_NATIVE_REST_LIMIT")
		limit = minf(limit, native_rest)
	if limit + ACTION_TIME_EPSILON < game_seconds:
		return _retime_shared_work_step(action_seconds * limit / game_seconds, limit)
	if native_active:
		var accepted: Dictionary = crowd_site.prepare_work_fatigue_plan(planned, _shared_work_requests, action_seconds, game_seconds, maxf(0.0, _shared_native_combat_begin - action_seconds))
		if not accepted.ok: return accepted
	_shared_work_plan = planned
	site_controller._shared_work_plan = planned
	return SiteRuntime.ok("", {"action_seconds": action_seconds, "game_seconds": game_seconds, "work_plan": planned})

func _retime_shared_work_step(action_seconds: float, game_seconds: float) -> Dictionary:
	if _shared_work_game_seconds <= 0.0 or game_seconds <= 0.0 or game_seconds > _shared_work_game_seconds + ACTION_TIME_EPSILON \
		or absf(action_seconds - _shared_work_action_seconds * game_seconds / _shared_work_game_seconds) > ACTION_TIME_EPSILON:
		return SiteRuntime.fail("SHARED_WORK_RETIME")
	var retimed: Dictionary = site_controller.work_team.retime_prepared_interval(game_seconds, action_seconds)
	if not retimed.ok: return retimed
	var planned := _plan_shared_vehicle_work_interval(_shared_work_requests, game_seconds)
	if not planned.ok: return planned
	if crowd_site != null and crowd_site.active:
		var accepted: Dictionary = crowd_site.prepare_work_fatigue_plan(planned, _shared_work_requests, action_seconds, game_seconds, maxf(0.0, _shared_native_combat_begin - action_seconds))
		if not accepted.ok: return accepted
	_shared_work_action_seconds = action_seconds
	_shared_work_game_seconds = game_seconds
	_shared_work_plan = planned
	site_controller._shared_work_plan = planned
	return SiteRuntime.ok("", {"action_seconds": action_seconds, "game_seconds": game_seconds, "work_plan": planned})

func _reserve_shared_work_payments(requests: Array) -> Dictionary:
	var sources: Array = []
	var batches := {}
	for request: Dictionary in requests:
		var payment: Dictionary = request.get("payment", {})
		if payment.is_empty() or not str(request.get("paused", "")).is_empty(): continue
		var source: Dictionary = request.get("payment_source", {})
		if source.is_empty(): return SiteRuntime.fail("WORK_PAYMENT_SOURCE")
		var index := -1
		for i: int in sources.size():
			if is_same(sources[i].source, source): index = i; break
		if index < 0:
			index = sources.size()
			sources.append({"source": source, "available": source.duplicate(true)})
		var batch := str(request.get("payment_key", str(request.provider) + ":" + str(request.key)))
		if batch.begins_with("feature:") and batch.ends_with(":operate"): batch = batch.trim_suffix(":operate")
		var key := str(index) + ":" + batch
		if batches.has(key): continue
		if not SiteRuntime.can_pay(sources[index].available, payment):
			request.paused = "MATERIALS"
			if str(request.provider) == "runtime": site_controller._shared_worker_inputs[str(request.key) + "_ready"] = false
			continue
		SiteRuntime.add_items(sources[index].available, payment, -1)
		batches[key] = true
	return SiteRuntime.ok()

func _shared_movement_requests(seconds: float, requests: Array) -> Array:
	var result: Array = []
	var assigned := {}
	for request: Dictionary in requests:
		for person: Dictionary in request.participants: assigned[int(person.person_id)] = true
	for actor: TerrainTestCharacter in combat_actors:
		if not actor_present(actor) or assigned.has(actor.person_id) or not actor.can_act(): continue
		var rate := actor.riding_fatigue_rate()
		if not exchange_enabled and actor.action_time > 0.0 and actor._strike_at >= 0.0: rate = PersonFatigue.ATTACK_RATE
		elif not exchange_enabled and (actor.guarding or actor.guard_transition_left > 0.0): rate = PersonFatigue.GUARD_RATE
		elif actor.is_moving() and actor.combat_ready and not actor.is_mounted() and actor._movement_duration <= TerrainTestCharacter.RUN_DURATION + 0.000001: rate = PersonFatigue.RUN_RATE
		if _ship_crew_work(actor.person_id): rate = PersonFatigue.WORK_RATE
		if rate <= 0.0: continue
		result.append(_shared_raw_effort(actor.person_id, actor, rate, seconds))
		assigned[actor.person_id] = true
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		for index: int in team.combat_units.size():
			var identity := team.combat_identity(index)
			if assigned.has(identity) or not team.combat_can_act(index): continue
			var rate := 0.0
			if _ship_crew_work(identity): rate = PersonFatigue.WORK_RATE
			elif not exchange_enabled and bool(team.combat_hot_get(index, &"attack")): rate = PersonFatigue.ATTACK_RATE
			elif not exchange_enabled and str(team.combat_hot_get(index, &"pose")) in ["guard", "guard_raise", "guard_lower"]: rate = PersonFatigue.GUARD_RATE
			elif team.moving_to[index] != TerrainArmy.INVALID_CELL and team.move_duration[index] <= TerrainArmy.RUN_DURATION + 0.000001: rate = PersonFatigue.RUN_RATE
			if rate > 0.0: result.append(_shared_raw_effort(identity, team.combat_units[index], rate, seconds))
	return result

func _shared_raw_effort(identity: int, body: Variant, rate: float, seconds: float) -> Dictionary:
	return {"provider": "movement", "key": str(identity), "participants": [{"person_id": identity, "body": body,
		"effort_rate": PersonFatigue.effort_rate(body, rate), "rest_limited": false}], "remaining": seconds,
		"productive_kind": "raw", "progress_multiplier": 1.0, "max_game_seconds": seconds}

func _shared_rest_event_limit(maximum: float, planned: Dictionary) -> float:
	var limit := maximum
	var seen: Array = []
	for actor: TerrainTestCharacter in combat_actors:
		if actor_present(actor): seen.append(actor)
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		for row: Dictionary in team.combat_units: seen.append(row)
	for body: Variant in seen:
		if _shared_pool_has_effort(body, planned): continue
		var fatigue := PersonFatigue.read(body)
		if fatigue <= 0.0: continue
		var rest := PersonFatigue.REST_DELAY - PersonFatigue.read(body, "fatigue_rest")
		if rest > ACTION_TIME_EPSILON: limit = minf(limit, rest)
		else:
			var target := 50.0 if fatigue > 50.0 and bool(body.get("work_resting")) else 0.0
			limit = minf(limit, maxf(ACTION_TIME_EPSILON, (fatigue - target) / PersonFatigue.RECOVERY_RATE))
	return limit

func _shared_pool_has_effort(body: Variant, planned: Dictionary = {}) -> bool:
	if planned.is_empty(): planned = _shared_work_plan
	var original := PersonFatigue.pool(body)
	for group: Dictionary in planned.get("pools", []):
		if float(group.effort_seconds) <= 0.0: continue
		if not original.is_empty() and is_same(original, group.original_pool) or original.is_empty() and is_same(body, group.body): return true
	return false

func _commit_shared_work_pools() -> void:
	if _shared_work_plan.is_empty() or _shared_work_pools_committed: return
	_shared_work_pools_committed = true
	for group: Dictionary in _shared_work_plan.pools:
		if float(group.effort_seconds) <= 0.0: continue
		if crowd_site != null and crowd_site.active and crowd_site.is_work_fatigue_pool(group.original_pool): continue
		PersonFatigue.write(group.body, "fatigue", float(group.fatigue))
		PersonFatigue.write(group.body, "fatigue_rest", float(group.fatigue_rest))

# Internal Region checkpoints are captured and applied by the original Lab.
# UI and derived collision/search caches are rebuilt by the original bind.
const RegionOwnerSnapshot = preload("res://scripts/terrain_lab/site_region_owner_snapshot.gd")
const RegionCheckpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
const REGION_LAB_FIELDS := ["_action_time_remainder", "_exchange_phase", "_exchange_round", "_tactical_ai_elapsed", "_duty_ai_elapsed",
	"_region_point_pending", "_region_point_contacts", "_region_point_wakes", "_region_point_consuming", "exchange_count", "exchange_results", "ranged_shots", "ranged_resolutions", "ranged_results", "siege_shots", "siege_contacts",
	"siege_projectiles", "_siege_contact_batch", "_siege_collect_contacts", "_fire_body_active", "_fire_exposure_sequence", "_fire_unsaved", "fire_action_cursor", "_fire_boundary_error", "_fire_motion", "_fire_motion_delta", "_fire_exposure_snapshot", "_fire_body_buckets"]
const REGION_CONTROLLER_FIELDS := ["_work_elapsed", "_settlement_elapsed", "_settlement_game_seconds", "_save_elapsed",
	"_pending_deaths", "_supply_rout_review", "_settlement_capture_sample", "_crew_handled", "_ground_crossing", "_ship_journey", "_family_wait"]
const REGION_ACTION_FIELDS := ["_jobs", "_results", "_next_fire_job_token"]
const REGION_WORK_FIELDS := ["_active_ids", "_retry_left", "_working", "_manual_hits"]
const REGION_ESCORT_FIELDS := ["_check_left", "_release_walks", "last_release_result"]
const REGION_ARMY_FIELDS := ["projectiles", "_formation_retry_seconds", "_combat_batch_members", "_move_landed_members",
	"_retreat_pair_pending", "_retreat_pairs_used", "_combat_absent_slots", "_suppress_approaches", "current_logic_tick", "_follow_elapsed", "_formation_rebind_elapsed", "_bottleneck_refresh_elapsed", "_fire_navigation", "_fire_navigation_epoch", "_fire_threat_last_end"]
const REGION_ACTOR_FIELDS := ["projectiles", "_exchange_pending_skill", "_exchange_guard_hold", "_ranged_hold_left", "_step_time", "_rescue_target", "_rescuer", "_army_rescuer", "_rescue_army", "_rescue_unit", "_rescue_left", "_getting_up", "_reload_left", "_rescue_hit_revision", "_rescue_target_hit_revision"]
const REGION_COORDINATOR_FIELDS := ["current_logic_tick", "_next_formation_runtime_id", "_current_occupancy", "_retained_occupancy",
	"_member_lookup", "_occupancy_rebuild_pending", "_inflight_batches"]
var _region_owner_restore_receipt: Dictionary = {}

func _region_owner_references() -> Dictionary:
	var refs := {"lab": self, "controller": site_controller, "data": terrain,
		"actions": site_controller.person_actions, "work": site_controller.work_team,
		"vehicles": site_controller.vehicles, "escort": site_controller.captive_escort,
		"callback:occupied": Callable(site_controller, "reserves_cell"),
		"callback:fire_resource_owner": Callable(site_controller, "fire_resource_owner_guard"),
		"callback:siege_damage": Callable(self, "siege_queue_damage"), "callback:siege_occupied": Callable(site_controller, "_siege_people_occupied"), "callback:army_occupied": Callable(self, "_armies_block_cell")}
	if combat_movement_coordinator != null:
		refs["coordinator"] = combat_movement_coordinator
		refs["deployment_registry"] = combat_movement_coordinator.deployment_registry
	for index: int in combat_armies.size():
		var team: TerrainArmy = combat_armies[index]
		if not team.combat_enabled:
			refs["army_slot:" + str(index)] = team
			continue
		refs["team:" + str(team.team_id)] = team
		if team._combat_move_plan != null: refs["team:" + str(team.team_id) + ":move"] = team._combat_move_plan
		if team._combat_deployment_plan != null: refs["team:" + str(team.team_id) + ":deployment"] = team._combat_deployment_plan
		if team._formation_movement_profile != null: refs["team:" + str(team.team_id) + ":profile"] = team._formation_movement_profile
		refs["team:" + str(team.team_id) + ":fire_navigation"] = team._fire_navigation
		refs["team:" + str(team.team_id) + ":fatigue"] = team.team_fatigue
		for row: Dictionary in team.combat_units:
			var identity := int(row.person_id)
			var person: Dictionary = site_controller.person_actions._person(identity, false)
			if not person.is_empty():
				RegionOwnerSnapshot.register_person(refs, identity, person)
				if person.body is Dictionary: RegionOwnerSnapshot.register_tree(refs, "person:" + str(identity) + ":body", person.body)
	for actor: TerrainTestCharacter in combat_actors:
		if not actor_present(actor): continue
		var person: Dictionary = site_controller.person_actions._person(actor.person_id, false)
		if not person.is_empty(): RegionOwnerSnapshot.register_person(refs, actor.person_id, person)
	for flight: Dictionary in fire_projectiles:
		refs["fire_flight:" + str(int(flight.projectile_id))] = flight
	RegionOwnerSnapshot.register_tree(refs, "site", terrain.site)
	return refs

static func _region_fields(owner: Object, fields: Array) -> Dictionary:
	var result := {}
	for field: String in fields:
		var value: Variant = owner.get(field)
		result[field] = value.duplicate() if field == "_fire_navigation" and value is Dictionary else value
	return result

static func _region_plan_values(plan: Object) -> Dictionary:
	var result := {}
	if plan == null: return result
	for property: Dictionary in plan.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
		var field := str(property.name)
		if field.begins_with("platform_bfs_cache_"): continue # Original bounded search cache only.
		var value: Variant = plan.get(field)
		if value is float and (value == -INF or value == INF):
			value = {"region_plan_sentinel": "negative_infinity" if value == -INF else "positive_infinity"}
		result[field] = value
	return result

func capture_region_owner_state(context: Dictionary) -> Dictionary:
	var duty_scope := _region_duty_enter()
	var captured := _region_capture_original_owner_state(context)
	_region_duty_leave(duty_scope)
	return captured

func _region_capture_original_owner_state(context: Dictionary) -> Dictionary:
	if terrain == null or site_controller == null: return SiteRuntime.fail("NO_TARGET")
	if crowd_site != null and crowd_site.active: return SiteRuntime.fail("REGION_BACKEND_UNADMITTED")
	if _region_point_consuming: return SiteRuntime.fail("REGION_EFFECT_RUNNING")
	var checked := RegionCheckpoint.validate_context(context)
	if not checked.ok: return checked
	if restore_only and str(context.mode) == "cold_exact":
		var person_guard: Dictionary = site_controller.person_actions.cold_technology_checkpoint_guard()
		if not person_guard.ok: return person_guard
		var work_guard: Dictionary = site_controller.work_team.cold_technology_work_checkpoint_guard()
		if not work_guard.ok: return work_guard
	if str(context.mode) not in ["live", "cold_exact", "formula_active", "materializing", "dematerializing"]:
		return SiteRuntime.fail("REGION_MODE")
	var original_boundary: Dictionary = terrain.get_meta(&"fire_boundary", {})
	var pending_fire := not bool(context.effects_complete) and not original_boundary.is_empty() and absf(float(original_boundary.get("action_end", -1.0)) - float(context.action_seconds)) <= SiteRuntime.FIRE_EPS and float(context.action_seconds) >= fire_action_cursor
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot != null:
		var registry: Dictionary = slot.region_registry()
		var mode: Dictionary = registry.modes.get(str(terrain.site.id), {})
		var expected := {"source_generation": int(slot._marker.get("generation", 0)), "runtime_revision": int(registry.revision),
			"game_seconds": float(slot.control.logical_game_seconds), "action_seconds": float(slot.control.fire_clock.action_seconds),
			"fire_epoch": str(slot.control.fire_clock.epoch), "fire_sequence": int(slot.control.fire_clock.sequence),
			"mode_revision": int(mode.get("revision", 0))}
		var clock_checked := RegionCheckpoint.validate_context(context, expected)
		if not clock_checked.ok: return clock_checked
	var settled := RegionSaveSlot.validate_settlement(terrain.site, context.game_seconds)
	if not settled.ok or not bool(settled.legacy) and float(settled.pending) > 0.00000001:
		return SiteRuntime.fail("STALE_REGION_OWNER", "Original Site has an incomplete global interval")
	if absf(float(context.action_seconds) - fire_action_cursor) > 0.00000001 and not pending_fire:
		return SiteRuntime.fail("STALE_REGION_OWNER", "Original action cursor does not match this complete interval")
	var roots := {"version": 1, "site_id": str(terrain.site.id), "lab": _region_fields(self, REGION_LAB_FIELDS),
		"controller": _region_fields(site_controller, REGION_CONTROLLER_FIELDS),
		"actions": _region_fields(site_controller.person_actions, REGION_ACTION_FIELDS),
		"work": _region_fields(site_controller.work_team, REGION_WORK_FIELDS),
		"escort": _region_fields(site_controller.captive_escort, REGION_ESCORT_FIELDS),
		"army_hot": {}, "actor_hot": {}, "plans": {}, "coordinator": {}, "registry": {}, "fire_meta": {}, "fatigue_work": [], "deliveries": {}, "duty": {"round": DutyAI.review_round, "seat_waits": DutyAI._seat_waits.duplicate(true), "inmate_since": DutyAI._inmate_since.duplicate(true), "settlement_traces": DutyAI.settlement_traces.duplicate(true), "nation_traces": DutyAI.nation_traces.duplicate(true), "last_nation_trace": DutyAI.last_nation_trace.duplicate(true)}}
	for team_id: String in terrain.site.get("team_supply", {}):
		var job: Dictionary = terrain.site.team_supply[team_id].get("delivery", {})
		if not job.is_empty(): roots.deliveries[team_id] = job.duplicate()
	for actor: Variant in _fatigue_work_seconds:
		if not actor is TerrainTestCharacter: return SiteRuntime.fail("INVALID_REGION_WORK_OWNER")
		roots.fatigue_work.append([actor.person_id, float(_fatigue_work_seconds[actor])])
	for meta: StringName in [&"fire_boundary", &"fire_structure_step"]:
		if terrain.has_meta(meta): roots.fire_meta[str(meta)] = terrain.get_meta(meta)
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		roots.army_hot[str(team.team_id)] = _region_fields(team, REGION_ARMY_FIELDS)
		roots.plans[str(team.team_id)] = {"move": _region_plan_values(team._combat_move_plan),
			"deployment": _region_plan_values(team._combat_deployment_plan), "profile": _region_plan_values(team._formation_movement_profile), "runtime_id": team.formation_runtime_id}
	for actor: TerrainTestCharacter in combat_actors:
		if actor_present(actor): roots.actor_hot[str(actor.person_id)] = _region_fields(actor, REGION_ACTOR_FIELDS)
	if combat_movement_coordinator != null:
		var original := combat_movement_coordinator
		roots.coordinator = _region_fields(original, REGION_COORDINATOR_FIELDS)
		roots.coordinator.grid_committed_occupancy = original.movement_reservation_grid.committed_occupancy.duplicate()
		roots.coordinator.egress = {}
		for identity: int in original._egress_search_states:
			roots.coordinator.egress[identity] = _region_plan_values(original._egress_search_states[identity])
		roots.coordinator.egress_retry = []
		for request: Variant in original._egress_retry_queue: roots.coordinator.egress_retry.append(_region_plan_values(request))
		var registry := original.deployment_registry
		roots.registry = {"next_token": registry.next_token, "formation_slots": registry._formation_slots, "leases": []}
		for cell: Vector2i in registry.slot_owners:
			var lease: Variant = registry.slot_owners[cell]
			roots.registry.leases.append([cell, [] if lease == null else registry._lease_values(lease)])
	var references := _region_owner_references()
	roots["reference_objects"] = _region_reference_objects(references)
	var captured := RegionOwnerSnapshot.capture(roots, references, context)
	if not captured.ok: return captured
	var result := context.duplicate(true)
	result.ok = true
	result.state = captured.state
	result.owner_states = {"scene": captured.state}
	var boundary: Dictionary = roots.fire_meta.get("fire_boundary", {})
	if not boundary.is_empty():
		if bool(context.effects_complete) or boundary.get("flushing") != false or boundary.get("site_id") != str(terrain.site.id) or not boundary.get("resources") is Array or not boundary.get("features") is Array or absf(float(boundary.get("action_end", -1.0)) - float(context.action_seconds)) > SiteRuntime.FIRE_EPS:
			return SiteRuntime.fail("INVALID_REGION_FIRE_BOUNDARY")
		result.owner_states["fire_boundary_receipt"] = {"site_id": str(terrain.site.id), "action_end": float(boundary.action_end), "resource_count": boundary.resources.size(), "feature_count": boundary.features.size(), "token": str(context.token), "action_start_cursor": fire_action_cursor}
	if roots.fire_meta.has("fire_structure_step"): return SiteRuntime.fail("REGION_STRUCTURE_EFFECT_RUNNING")
	return result

static func _region_typed_array(original: Array, values: Array) -> bool:
	if not original.is_typed(): return true
	var expected := original.get_typed_builtin()
	for value: Variant in values:
		if typeof(value) != expected: return false
		if expected == TYPE_OBJECT and value != null:
			var script: Variant = original.get_typed_script()
			if script != null and value.get_script() != script: return false
	return true

static func _region_compatible(old: Variant, value: Variant) -> bool:
	if typeof(old) != typeof(value):
		if old is float and value is int: return true
		return false
	if value is float and not is_finite(value): return false
	if old is Array and not _region_typed_array(old, value): return false
	return true

static func _region_valid_fields(values: Variant, owner: Object, fields: Array) -> bool:
	if not values is Dictionary or values.size() != fields.size(): return false
	for field: String in fields:
		if not values.has(field): return false
		var old: Variant = owner.get(field)
		var value: Variant = values[field]
		# Serialized Actor links do not expose Army patients. The original Nodes
		# are supplied by the reference index before any owner is assigned.
		if owner is TerrainTestCharacter and field in ["_rescue_army", "_army_rescuer"]:
			if value != null and not value is TerrainArmy: return false
			continue
		if owner is TerrainTestCharacter and field in ["_rescue_target", "_rescuer"]:
			if value != null and not value is TerrainTestCharacter: return false
			continue
		if not _region_compatible(old, value): return false
	return true

static func _region_prepare_plan(values: Dictionary, plan: Object) -> Dictionary:
	if values.is_empty(): return {"ok": plan == null, "values": {}}
	if plan == null: return SiteRuntime.fail("MISSING_REGION_PLAN")
	var schema := _region_plan_values(plan)
	if values.size() != schema.size(): return SiteRuntime.fail("INVALID_REGION_PLAN")
	var prepared := {}
	for field: String in schema:
		if not values.has(field): return SiteRuntime.fail("INVALID_REGION_PLAN")
		var value: Variant = values[field]
		var old: Variant = plan.get(field)
		if value is Dictionary and value.size() == 1 and value.has("region_plan_sentinel"):
			if not old is float or field not in ["previous_median_path_s", "previous_upper_quartile_path_s", "last_macro_replan_time_sec"] or value.region_plan_sentinel not in ["negative_infinity", "positive_infinity"]:
				return SiteRuntime.fail("INVALID_REGION_PLAN")
			value = -INF if value.region_plan_sentinel == "negative_infinity" else INF
		elif not _region_compatible(old, value):
			return SiteRuntime.fail("INVALID_REGION_PLAN")
		prepared[field] = value
	return {"ok": true, "values": prepared}

func prepare_restore_region_owner_state(owners: Dictionary, context: Dictionary,
		coordinate_references: Dictionary = {}, coordinate_domain: TerrainData = null) -> Dictionary:
	if not owners.has("scene") or owners.size() != 1 + int(owners.has("fire_boundary_receipt")): return SiteRuntime.fail("INVALID_REGION_OWNERS")
	var current_refs := _region_owner_references()
	var refs := current_refs.duplicate()
	if not coordinate_references.is_empty():
		if coordinate_domain == null or coordinate_references.size() != current_refs.size(): return SiteRuntime.fail("STALE_REGION_MAP_MOTION")
		var same: Array = current_refs.values()
		for key: String in coordinate_references:
			if not key.begins_with("lease:") and (not current_refs.has(key) or not is_same(current_refs[key], coordinate_references[key])): return SiteRuntime.fail("STALE_REGION_MAP_MOTION", key)
			var found := -1
			for index: int in same.size():
				if is_same(same[index], coordinate_references[key]): found = index; break
			if found < 0: return SiteRuntime.fail("STALE_REGION_MAP_MOTION", key)
			same.remove_at(found)
		refs = coordinate_references.duplicate()
	var domain: TerrainData = terrain if coordinate_domain == null else coordinate_domain
	if str(domain.site.id) != str(terrain.site.id): return SiteRuntime.fail("WRONG_SITE")
	var social_schema := SiteStore._validate_unadmitted_social_state(domain.site)
	if not social_schema.ok: return social_schema
	var original_refs := current_refs.duplicate()
	var reference_values := RegionOwnerSnapshot.peek_values(owners.scene, "reference_objects", context)
	if not reference_values.ok: return reference_values
	var object_restore := _region_prepare_reference_objects(reference_values.value, refs)
	if not object_restore.ok: return object_restore
	var decoded := RegionOwnerSnapshot.prepare_restore(owners.scene, refs, context)
	if not decoded.ok: return decoded
	var roots: Dictionary = decoded.roots
	const ROOTS := ["version", "site_id", "lab", "controller", "actions", "work", "escort", "army_hot", "actor_hot", "plans", "coordinator", "registry", "fire_meta", "fatigue_work", "deliveries", "duty", "reference_objects"]
	if roots.size() != ROOTS.size() or not RegionCheckpoint.integer(roots.get("version"), 1) or int(roots.version) != 1 or str(roots.get("site_id", "")) != str(terrain.site.id):
		return SiteRuntime.fail("INVALID_REGION_OWNERS")
	for field: String in ROOTS:
		if not roots.has(field): return SiteRuntime.fail("INVALID_REGION_OWNERS")
	var legacy := _region_validate_legacy_roots(domain, roots, terrain.get_meta(&"region_party_runtime_mapping", {}))
	if not legacy.ok: return legacy
	for group: Array in [["lab", self, REGION_LAB_FIELDS], ["controller", site_controller, REGION_CONTROLLER_FIELDS],
		["actions", site_controller.person_actions, REGION_ACTION_FIELDS], ["work", site_controller.work_team, REGION_WORK_FIELDS],
		["escort", site_controller.captive_escort, REGION_ESCORT_FIELDS]]:
		if not _region_valid_fields(roots[group[0]], group[1], group[2]): return SiteRuntime.fail("INVALID_REGION_OWNER_FIELDS", str(group[0]))
	if roots.lab._region_point_consuming != false: return SiteRuntime.fail("REGION_EFFECT_RUNNING")
	var team_count := 0
	var plans := {}
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		team_count += 1
		var key := str(team.team_id)
		if not roots.army_hot.has(key) or not roots.plans.has(key) or not _region_valid_fields(roots.army_hot[key], team, REGION_ARMY_FIELDS):
			return SiteRuntime.fail("INVALID_REGION_ARMY")
		var move_owner: Object = refs.get("team:" + key + ":move")
		var deployment_owner: Object = refs.get("team:" + key + ":deployment")
		var move := _region_prepare_plan(roots.plans[key].get("move", {}), move_owner)
		var deployment := _region_prepare_plan(roots.plans[key].get("deployment", {}), deployment_owner)
		var profile_values: Dictionary = roots.plans[key].get("profile", {})
		var profile_owner: Object = refs.get("team:" + key + ":profile")
		for field: String in ["move", "deployment", "profile"]:
			if roots.plans[key].get(field, {}) != roots.reference_objects.get("team:" + key + ":" + field, {}).get("values", {}):
				return SiteRuntime.fail("INVALID_REGION_PLAN", "Original current plan descriptor differs")
		var profile := {"ok": true, "values": {}} if profile_values.is_empty() else _region_prepare_plan(profile_values, profile_owner)
		if not move.ok or not deployment.ok or not profile.ok: return SiteRuntime.fail("INVALID_REGION_PLAN")
		if not RegionCheckpoint.integer(roots.plans[key].get("runtime_id"), 1): return SiteRuntime.fail("INVALID_REGION_FORMATION")
		plans[key] = {"team": team, "move": move.values, "move_owner": move_owner, "deployment": deployment.values, "deployment_owner": deployment_owner, "profile": profile.values, "profile_owner": profile_owner if not profile_values.is_empty() else null, "runtime_id": int(roots.plans[key].runtime_id)}
	if roots.army_hot.size() != team_count or roots.plans.size() != team_count: return SiteRuntime.fail("INVALID_REGION_ARMY")
	var actor_count := 0
	for actor: TerrainTestCharacter in combat_actors:
		if not actor_present(actor): continue
		actor_count += 1
		if not roots.actor_hot.has(str(actor.person_id)) or not _region_valid_fields(roots.actor_hot[str(actor.person_id)], actor, REGION_ACTOR_FIELDS):
			return SiteRuntime.fail("INVALID_REGION_ACTOR")
	if roots.actor_hot.size() != actor_count: return SiteRuntime.fail("INVALID_REGION_ACTOR")
	var egress := {}
	var retries: Array = []
	var registry := {"slot_owners": {}, "formation_slots": {}, "next_token": 1, "lease_values": {}}
	if not roots.coordinator.is_empty():
		if combat_movement_coordinator == null or not roots.coordinator.get("egress") is Dictionary or not roots.coordinator.get("egress_retry") is Array:
			return SiteRuntime.fail("INVALID_REGION_MOVEMENT")
		var values: Dictionary = roots.coordinator.duplicate()
		values.erase("egress"); values.erase("egress_retry"); values.erase("grid_committed_occupancy")
		if not _region_valid_fields(values, combat_movement_coordinator, REGION_COORDINATOR_FIELDS): return SiteRuntime.fail("INVALID_REGION_MOVEMENT")
		for identity: Variant in roots.coordinator.egress:
			if not identity is int: return SiteRuntime.fail("INVALID_REGION_MOVEMENT")
			var state := FireMovementTypes.EgressSearchState.new()
			var prepared := _region_prepare_plan(roots.coordinator.egress[identity], state)
			if not prepared.ok: return prepared
			_region_apply_values(state, prepared.values)
			egress[identity] = state
		for values_retry: Dictionary in roots.coordinator.egress_retry:
			var request := FireMovementTypes.EgressRetryRequest.new()
			var prepared := _region_prepare_plan(values_retry, request)
			if not prepared.ok: return prepared
			_region_apply_values(request, prepared.values)
			retries.append(request)
		if not roots.registry.get("leases") is Array or not roots.registry.get("formation_slots") is Dictionary \
			or not RegionCheckpoint.integer(roots.registry.get("next_token"), 1): return SiteRuntime.fail("INVALID_REGION_REGISTRY")
		registry.next_token = int(roots.registry.next_token)
		registry.formation_slots = roots.registry.formation_slots
		for row: Variant in roots.registry.leases:
			if not row is Array or row.size() != 2 or not row[0] is Vector2i or not row[1] is Array or registry.slot_owners.has(row[0]):
				return SiteRuntime.fail("INVALID_REGION_LEASE")
			var cell: Vector2i = row[0]
			if not domain.contains(cell): return SiteRuntime.fail("INVALID_REGION_LEASE")
			if row[1].is_empty(): registry.slot_owners[cell] = null; continue
			var value: Array = row[1]
			if value.size() != 6 or value[4] != cell or not RegionCheckpoint.integer(value[0], 1) \
				or not RegionCheckpoint.integer(value[1], 1) or not RegionCheckpoint.integer(value[2]) \
				or not RegionCheckpoint.integer(value[3]) or not RegionCheckpoint.time(value[5]): return SiteRuntime.fail("INVALID_REGION_LEASE")
			var reference: Dictionary = object_restore.objects.get("lease:%d:%d" % [cell.x, cell.y], {})
			if reference.is_empty(): return SiteRuntime.fail("INVALID_REGION_LEASE")
			var lease_values: Dictionary = reference.values
			if [lease_values.formation_id, lease_values.order_serial, lease_values.member_id, lease_values.role, lease_values.cell, lease_values.temporary_absence_remaining_sec] != value:
				return SiteRuntime.fail("INVALID_REGION_LEASE", "Original lease descriptor differs")
			registry.slot_owners[cell] = reference.owner
			registry.lease_values[cell] = value
	if not roots.deliveries is Dictionary or not roots.duty is Dictionary or roots.duty.size() != 6 or not RegionCheckpoint.integer(roots.duty.get("round")) or not roots.duty.get("seat_waits") is Dictionary or not roots.duty.get("inmate_since") is Dictionary or not roots.duty.get("settlement_traces") is Array or not roots.duty.get("nation_traces") is Dictionary or not roots.duty.get("last_nation_trace") is Dictionary:
		return SiteRuntime.fail("INVALID_REGION_DUTY")
	for trace: Variant in roots.duty.settlement_traces:
		if not trace is Dictionary: return SiteRuntime.fail("INVALID_REGION_DUTY")
	for counts: Dictionary in [roots.duty.seat_waits, roots.duty.inmate_since]:
		for key: Variant in counts:
			if not key is String or not RegionCheckpoint.integer(counts[key]): return SiteRuntime.fail("INVALID_REGION_DUTY")
	var delivery_count := 0
	for team_id: String in terrain.site.get("team_supply", {}):
		var original: Dictionary = terrain.site.team_supply[team_id].get("delivery", {})
		if original.is_empty(): continue
		delivery_count += 1
		if not roots.deliveries.has(team_id) or not roots.deliveries[team_id] is Dictionary: return SiteRuntime.fail("INVALID_REGION_DELIVERY")
		var restored: Dictionary = roots.deliveries[team_id]
		for field: String in ["player_id", "representative_id", "requester_id", "source_spec", "player_hit", "target_hit", "source_version", "quantity", "left", "pending", "items", "open_amount", "target_location"]:
			if original.get(field) != restored.get(field): return SiteRuntime.fail("STALE_REGION_DELIVERY", field)
		for field: String in ["source_owner", "receiver_owner", "source_body", "receiver_body", "source_cargo", "source_holder", "source_open"]:
			if not restored.has(field): return SiteRuntime.fail("INVALID_REGION_DELIVERY", field)
	if roots.deliveries.size() != delivery_count: return SiteRuntime.fail("INVALID_REGION_DELIVERY")
	if not roots.coordinator.is_empty():
		if not roots.coordinator.get("grid_committed_occupancy") is Dictionary: return SiteRuntime.fail("INVALID_REGION_MOVEMENT")
		for cell: Variant in roots.coordinator.grid_committed_occupancy:
			if not cell is Vector2i or not domain.contains(cell) or not RegionCheckpoint.integer(roots.coordinator.grid_committed_occupancy[cell], 1): return SiteRuntime.fail("INVALID_REGION_MOVEMENT")
	if not roots.fire_meta is Dictionary or not roots.fatigue_work is Array: return SiteRuntime.fail("INVALID_REGION_OWNERS")
	for meta: String in roots.fire_meta:
		if meta not in ["fire_boundary", "fire_structure_step"]: return SiteRuntime.fail("INVALID_REGION_OWNERS")
	var boundary: Dictionary = roots.fire_meta.get("fire_boundary", {})
	if not boundary.is_empty():
		var receipt: Variant = owners.get("fire_boundary_receipt", {})
		if not receipt is Dictionary or receipt.size() != 6 or bool(context.effects_complete) or boundary.get("site_id") != str(terrain.site.id) or boundary.get("flushing") != false or not boundary.get("resources") is Array or not boundary.get("features") is Array or receipt.get("site_id") != str(terrain.site.id) or receipt.get("token") != context.token or receipt.get("action_end") != boundary.get("action_end") or not RegionCheckpoint.time(receipt.get("action_start_cursor")) or absf(float(receipt.action_start_cursor) - float(roots.lab.fire_action_cursor)) > SiteRuntime.FIRE_EPS or float(receipt.action_start_cursor) > float(boundary.action_end) or receipt.get("resource_count") != boundary.resources.size() or receipt.get("feature_count") != boundary.features.size() or absf(float(boundary.get("action_end", -1.0)) - float(context.action_seconds)) > SiteRuntime.FIRE_EPS:
			return SiteRuntime.fail("INVALID_REGION_FIRE_BOUNDARY")
	elif owners.has("fire_boundary_receipt"): return SiteRuntime.fail("INVALID_REGION_FIRE_BOUNDARY")
	if roots.fire_meta.has("fire_structure_step"): return SiteRuntime.fail("REGION_STRUCTURE_EFFECT_RUNNING")
	for work: Variant in roots.fatigue_work:
		if not work is Array or work.size() != 2 or not RegionCheckpoint.integer(work[0], 1) or not RegionCheckpoint.time(work[1]) \
			or not refs.has("person:" + str(int(work[0])) + ":owner") or not refs["person:" + str(int(work[0])) + ":owner"] is TerrainTestCharacter:
			return SiteRuntime.fail("INVALID_REGION_WORK_OWNER")
	return {"ok": true, "roots": roots, "references": refs, "original_references": original_refs, "reference_objects": object_restore.objects, "plans": plans, "registry": registry,
		"egress": egress, "retries": retries, "context": decoded.context, "data": terrain}

static func _region_apply_values(owner: Object, values: Dictionary) -> void:
	for field: String in values:
		var original: Variant = owner.get(field)
		if original is Array and original.is_typed() and values[field] is Array:
			original.assign(values[field])
		else: owner.set(field, values[field])

func publish_restore_region_owner_state(prepared: Dictionary) -> Dictionary:
	var duty_scope := _region_duty_enter()
	var result := _region_publish_original_owner_state(prepared)
	_region_duty_leave(duty_scope)
	return result

func _region_publish_original_owner_state(prepared: Dictionary) -> Dictionary:
	if not bool(prepared.get("ok", false)) or not is_same(prepared.get("data"), terrain): return SiteRuntime.fail("STALE_REGION_RESTORE")
	var refs := _region_owner_references()
	if refs.size() != prepared.original_references.size(): return SiteRuntime.fail("STALE_REGION_RESTORE")
	for key: String in refs:
		if not prepared.original_references.has(key) or not is_same(refs[key], prepared.original_references[key]): return SiteRuntime.fail("STALE_REGION_RESTORE", key)
	for key: String in prepared.reference_objects:
		var object_state: Dictionary = prepared.reference_objects[key]
		_region_apply_values(object_state.owner, object_state.values)
	refs = prepared.references
	var roots: Dictionary = prepared.roots
	_region_apply_values(self, roots.lab)
	_region_apply_values(site_controller, roots.controller)
	_region_apply_values(site_controller.person_actions, roots.actions)
	_region_apply_values(site_controller.work_team, roots.work)
	_region_apply_values(site_controller.captive_escort, roots.escort)
	site_controller.work_team._routes.clear() # Derived local paths keep original target/retry progress.
	for key: String in prepared.plans:
		var plan: Dictionary = prepared.plans[key]
		var team: TerrainArmy = plan.team
		_region_apply_values(team, roots.army_hot[key])
		team.formation_runtime_id = int(plan.runtime_id)
		team._combat_move_plan = plan.move_owner
		if team._combat_move_plan != null: _region_apply_values(team._combat_move_plan, plan.move)
		team._combat_deployment_plan = plan.deployment_owner
		if team._combat_deployment_plan != null: _region_apply_values(team._combat_deployment_plan, plan.deployment)
		team._formation_movement_profile = plan.profile_owner
		if team._formation_movement_profile != null: _region_apply_values(team._formation_movement_profile, plan.profile)
	for actor: TerrainTestCharacter in combat_actors:
		if actor_present(actor): _region_apply_values(actor, roots.actor_hot[str(actor.person_id)])
	if not roots.coordinator.is_empty():
		var values: Dictionary = roots.coordinator.duplicate()
		values.erase("egress"); values.erase("egress_retry"); values.erase("grid_committed_occupancy")
		_region_apply_values(combat_movement_coordinator, values)
		combat_movement_coordinator.movement_reservation_grid.committed_occupancy.clear()
		combat_movement_coordinator.movement_reservation_grid.committed_occupancy.merge(roots.coordinator.grid_committed_occupancy)
		combat_movement_coordinator._egress_search_states = prepared.egress
		combat_movement_coordinator._egress_retry_queue = prepared.retries
		combat_movement_coordinator.deployment_registry.restore_handoff_state(prepared.registry)
		combat_movement_coordinator._registered_formations.clear()
		combat_movement_coordinator._formation_by_id.clear()
		for team: TerrainArmy in combat_armies:
			if not team.combat_enabled: continue
			combat_movement_coordinator._registered_formations[team.get_instance_id()] = team.formation_runtime_id
			combat_movement_coordinator._formation_by_id[team.formation_runtime_id] = team
	for team_id: String in roots.deliveries: terrain.site.team_supply[team_id].delivery = roots.deliveries[team_id]
	DutyAI.review_round = int(roots.duty.round)
	DutyAI._seat_waits.clear(); DutyAI._seat_waits.merge(roots.duty.seat_waits)
	DutyAI._inmate_since.clear(); DutyAI._inmate_since.merge(roots.duty.inmate_since)
	DutyAI.settlement_traces.assign(roots.duty.settlement_traces)
	DutyAI.nation_traces.clear(); DutyAI.nation_traces.merge(roots.duty.nation_traces)
	DutyAI.last_nation_trace = roots.duty.last_nation_trace
	var cadence: Dictionary = DutyAI._cadence_state(self)
	if not cadence.is_empty():
		cadence.round = int(roots.duty.round)
		cadence.elapsed = float(_duty_ai_elapsed)
		cadence.seat_waits = DutyAI._seat_waits.duplicate(true)
		cadence.inmate_since = DutyAI._inmate_since.duplicate(true)
	_fatigue_work_seconds.clear()
	for work: Array in roots.fatigue_work: _fatigue_work_seconds[refs["person:" + str(int(work[0])) + ":owner"]] = float(work[1])
	for meta: StringName in [&"fire_boundary", &"fire_structure_step"]:
		if terrain.has_meta(meta): terrain.remove_meta(meta)
	for meta: String in roots.fire_meta: terrain.set_meta(StringName(meta), roots.fire_meta[meta])
	var receipt: Dictionary = prepared.context.duplicate(true)
	receipt.ok = true
	receipt.owners_restored = true
	receipt.effects_complete = bool(prepared.context.effects_complete)
	receipt.bind_complete = false
	_region_owner_restore_receipt = receipt
	return receipt

func _restore_region_owners() -> Dictionary:
	if not terrain.site.has("region_snapshot"): return SiteRuntime.ok()
	var snapshot := RegionCheckpoint.validate(terrain.site, terrain.site.region_snapshot)
	if not snapshot.ok: return snapshot
	var prepared := prepare_restore_region_owner_state(snapshot.owners, snapshot.context)
	if not prepared.ok: return prepared
	return publish_restore_region_owner_state(prepared)

static func _region_reference_kind(owner: Object) -> String:
	if owner is CombatMovePlan: return "move"
	if owner is CombatDeploymentPlan: return "deployment"
	if owner is FormationMovementProfile: return "profile"
	if owner is FireMovementTypes.DeploymentSlotLease: return "lease"
	return ""

static func _region_register_reference_object(refs: Dictionary, descriptors: Dictionary, key: String, owner: Object) -> void:
	if owner == null: return
	var kind := _region_reference_kind(owner)
	if kind.is_empty(): return
	for existing: String in refs:
		if is_same(refs[existing], owner):
			key = existing
			break
	refs[key] = owner
	if not descriptors.has(key): descriptors[key] = {"kind": kind, "values": _region_plan_values(owner)}

func _region_reference_objects(refs: Dictionary) -> Dictionary:
	var descriptors := {}
	if combat_movement_coordinator != null:
		for cell: Vector2i in combat_movement_coordinator.deployment_registry.slot_owners:
			var lease: Variant = combat_movement_coordinator.deployment_registry.slot_owners[cell]
			if lease != null: _region_register_reference_object(refs, descriptors, "lease:%d:%d" % [cell.x, cell.y], lease)
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		var prefix := "team:" + str(team.team_id)
		_region_register_reference_object(refs, descriptors, prefix + ":move", team._combat_move_plan)
		_region_register_reference_object(refs, descriptors, prefix + ":deployment", team._combat_deployment_plan)
		_region_register_reference_object(refs, descriptors, prefix + ":profile", team._formation_movement_profile)
		for identity: int in team._combat_batch_members:
			var intent := team._committed_intent(identity)
			for field: String in ["move_plan", "deployment", "movement_profile"]:
				_region_register_reference_object(refs, descriptors, prefix + ":batch:" + str(identity) + ":" + field, intent.get(field))
		for identity: int in team._fire_navigation.get("leases", {}):
			_region_register_reference_object(refs, descriptors, prefix + ":fire_lease:" + str(identity), team._fire_navigation.leases[identity])
	return descriptors

func _region_prepare_reference_objects(raw: Variant, refs: Dictionary, candidate: TerrainData = null) -> Dictionary:
	if not raw is Dictionary or raw.size() > 100000: return SiteRuntime.fail("INVALID_REGION_REFERENCE_VALUES")
	var domain := candidate if candidate != null else terrain
	var objects := {}
	for key: Variant in raw:
		var descriptor: Variant = raw[key]
		if not key is String or not (str(key).begins_with("team:") or str(key).begins_with("lease:")) or not descriptor is Dictionary or descriptor.size() != 2 or not descriptor.get("values") is Dictionary:
			return SiteRuntime.fail("INVALID_REGION_REFERENCE_VALUES")
		var kind := str(descriptor.get("kind", ""))
		var owner: Variant = refs.get(key)
		if owner != null and (not owner is Object or _region_reference_kind(owner) != kind): return SiteRuntime.fail("INVALID_REGION_REFERENCE_VALUES")
		if owner == null:
			match kind:
				"move": owner = CombatMovePlan.new()
				"deployment": owner = CombatDeploymentPlan.new()
				"profile": owner = FormationMovementProfile.new()
				"lease": owner = FireMovementTypes.DeploymentSlotLease.new()
				_: return SiteRuntime.fail("INVALID_REGION_REFERENCE_VALUES")
		var prepared := _region_prepare_plan(descriptor.values, owner)
		if not prepared.ok: return prepared
		if kind == "lease" and (domain == null or not prepared.values.get("cell") is Vector2i or not domain.contains(prepared.values.cell) or not RegionCheckpoint.integer(prepared.values.get("formation_id"), 1) or not RegionCheckpoint.integer(prepared.values.get("member_id")) or not RegionCheckpoint.integer(prepared.values.get("order_serial"), 1) or not RegionCheckpoint.integer(prepared.values.get("role")) or int(prepared.values.role) > FireMovementTypes.CombatDestinationRole.SUPPRESS_WORK or not RegionCheckpoint.time(prepared.values.get("temporary_absence_remaining_sec"))):
			return SiteRuntime.fail("INVALID_REGION_LEASE")
		refs[key] = owner
		objects[key] = {"owner": owner, "values": prepared.values}
	return SiteRuntime.ok("", {"objects": objects})

## Read-only admission of a validated original Store body and its owner graph.
## Original Nodes are bound later by prepare_restore/publish_restore.
func validate_region_owner_bind_payload(data: TerrainData, owners: Dictionary, context: Dictionary) -> Dictionary:
	if data == null or data.site.is_empty() or site_controller == null or not owners.has("scene") or owners.size() != 1 + int(owners.has("fire_boundary_receipt")):
		return SiteRuntime.fail("INVALID_REGION_OWNERS")
	var social_schema := SiteStore._validate_unadmitted_social_state(data.site)
	if not social_schema.ok: return social_schema
	var checked := RegionCheckpoint.validate_context(context)
	if not checked.ok: return checked
	if data.site.has("region_snapshot"):
		var metadata := RegionCheckpoint.validate(data.site, data.site.region_snapshot, context)
		if not metadata.ok: return metadata
		if RegionCheckpoint.state_hash({"owners": metadata.owners}) != RegionCheckpoint.state_hash({"owners": owners}): return SiteRuntime.fail("STALE_REGION_OWNERS")
	var descriptors := RegionOwnerSnapshot.peek_values(owners.scene, "reference_objects", context)
	if not descriptors.ok: return descriptors
	var objects := _region_prepare_reference_objects(descriptors.value, {}, data)
	if not objects.ok: return objects
	var people := {}
	var teams := {}
	for key: String in data.site.get("actors", {}):
		var body: Dictionary = data.site.actors[key]
		people[int(body.get("person_id", 0))] = {"body": body, "actor": true, "key": key}
	for army: Dictionary in data.site.get("armies", []):
		var team_id := int(army.get("team_id", 0))
		teams[team_id] = army
		for body: Dictionary in army.get("units", []): people[int(body.get("person_id", 0))] = {"body": body, "actor": false, "team_id": team_id}
	var validate_reference := func(key: String, kind: int) -> bool:
		return _region_validate_bind_reference(data, key, kind, people, teams, objects.objects)
	var graph := RegionOwnerSnapshot.validate_for_bind(owners.scene, validate_reference, context)
	if not graph.ok: return graph
	var roots: Dictionary = graph.roots
	const ROOTS := ["version", "site_id", "lab", "controller", "actions", "work", "escort", "army_hot", "actor_hot", "plans", "coordinator", "registry", "fire_meta", "fatigue_work", "deliveries", "duty", "reference_objects"]
	if roots.size() != ROOTS.size() or not RegionCheckpoint.integer(roots.get("version"), 1) or int(roots.version) != 1 or roots.get("site_id") != str(data.site.id): return SiteRuntime.fail("INVALID_REGION_OWNERS")
	for field: String in ROOTS:
		if not roots.has(field): return SiteRuntime.fail("INVALID_REGION_OWNERS")
	var legacy := _region_validate_legacy_roots(data, roots, data.get_meta(&"region_party_runtime_mapping", {}))
	if not legacy.ok: return legacy
	for group: Array in [["lab", self, REGION_LAB_FIELDS], ["controller", site_controller, REGION_CONTROLLER_FIELDS], ["actions", site_controller.person_actions, REGION_ACTION_FIELDS], ["work", site_controller.work_team, REGION_WORK_FIELDS], ["escort", site_controller.captive_escort, REGION_ESCORT_FIELDS]]:
		if not _region_valid_bind_fields(roots[group[0]], group[1], group[2], graph.symbols): return SiteRuntime.fail("INVALID_REGION_OWNER_FIELDS", str(group[0]))
	if roots.lab._region_point_consuming != false: return SiteRuntime.fail("REGION_EFFECT_RUNNING")
	if not roots.army_hot is Dictionary or not roots.actor_hot is Dictionary or not roots.plans is Dictionary or roots.army_hot.size() != teams.size() or roots.plans.size() != teams.size(): return SiteRuntime.fail("INVALID_REGION_ARMY")
	var team_schema := TerrainArmy.new()
	for team_id: int in teams:
		var key := str(team_id)
		if not roots.army_hot.has(key) or not _region_valid_bind_fields(roots.army_hot[key], team_schema, REGION_ARMY_FIELDS, graph.symbols) or not roots.plans.get(key) is Dictionary or roots.plans[key].size() != 4 or not RegionCheckpoint.integer(roots.plans[key].get("runtime_id"), 1):
			team_schema.free()
			return SiteRuntime.fail("INVALID_REGION_ARMY")
		for field: String in ["move", "deployment", "profile"]:
			if not roots.plans[key].get(field) is Dictionary or roots.plans[key][field] != descriptors.value.get("team:" + key + ":" + field, {}).get("values", {}):
				team_schema.free()
				return SiteRuntime.fail("INVALID_REGION_PLAN")
	team_schema.free()
	var actor_schema := TerrainTestCharacter.new()
	var actor_count := 0
	for identity: int in people:
		if not people[identity].actor: continue
		actor_count += 1
		if not roots.actor_hot.has(str(identity)) or not _region_valid_bind_fields(roots.actor_hot[str(identity)], actor_schema, REGION_ACTOR_FIELDS, graph.symbols):
			actor_schema.free()
			return SiteRuntime.fail("INVALID_REGION_ACTOR")
	actor_schema.free()
	if roots.actor_hot.size() != actor_count: return SiteRuntime.fail("INVALID_REGION_ACTOR")
	if not roots.coordinator is Dictionary or not roots.registry is Dictionary or not roots.deliveries is Dictionary or not roots.fire_meta is Dictionary or not roots.fatigue_work is Array or not roots.duty is Dictionary: return SiteRuntime.fail("INVALID_REGION_OWNERS")
	for row: Variant in roots.fatigue_work:
		if not row is Array or row.size() != 2 or not RegionCheckpoint.integer(row[0], 1) or not RegionCheckpoint.time(row[1]) or not people.has(int(row[0])) or not people[int(row[0])].actor: return SiteRuntime.fail("INVALID_REGION_WORK_OWNER")
	if roots.fire_meta.has("fire_structure_step"): return SiteRuntime.fail("REGION_STRUCTURE_EFFECT_RUNNING")
	if roots.fire_meta.has("fire_boundary") != owners.has("fire_boundary_receipt"): return SiteRuntime.fail("INVALID_REGION_FIRE_BOUNDARY")
	return SiteRuntime.ok("", {"graph_prepared": true, "owners_restored": false, "bind_complete": false, "context": checked.context, "graph_hash": graph.graph_hash})

static func _region_bind_type(value: Variant, symbols: Dictionary) -> int:
	if value is Dictionary and value.has("@region_reference"):
		var key := str(value["@region_reference"])
		if symbols.has(key) and is_same(value, symbols[key]): return int(value.type)
	return typeof(value)

static func _region_valid_bind_fields(values: Variant, owner: Object, fields: Array, symbols: Dictionary) -> bool:
	if not values is Dictionary or values.size() != fields.size(): return false
	for field: String in fields:
		if not values.has(field): return false
		var value: Variant = values[field]
		var old: Variant = owner.get(field)
		var kind := _region_bind_type(value, symbols)
		if owner is TerrainTestCharacter and field in ["_rescue_army", "_army_rescuer", "_rescue_target", "_rescuer"]:
			if kind not in [TYPE_NIL, TYPE_OBJECT]: return false
			continue
		if kind != typeof(old) and not (old is float and kind == TYPE_INT): return false
		if value is float and not is_finite(value): return false
		if old is Array and old.is_typed() and value is Array:
			for entry: Variant in value:
				if _region_bind_type(entry, symbols) != old.get_typed_builtin(): return false
	return true

static func _region_bind_path(value: Variant, encoded: String, kind: int) -> bool:
	var raw: Variant = JSON.parse_string(encoded)
	if not RegionCheckpoint.valid_wire(raw): return false
	var path: Variant = RegionCheckpoint.unwire(raw)
	if not path is Array or path.size() > 48: return false
	for key: Variant in path:
		if value is Dictionary and value.has(key): value = value[key]
		elif value is Array and key is int and key >= 0 and key < value.size(): value = value[key]
		else: return false
	return typeof(value) == kind and kind in [TYPE_DICTIONARY, TYPE_ARRAY]

static func _region_validate_bind_reference(data: TerrainData, key: String, kind: int, people: Dictionary, teams: Dictionary, objects: Dictionary) -> bool:
	if key in ["lab", "controller", "data", "actions", "work", "vehicles", "escort", "coordinator", "deployment_registry"]: return kind == TYPE_OBJECT
	if key in ["callback:occupied", "callback:fire_resource_owner", "callback:siege_damage", "callback:siege_occupied", "callback:army_occupied"]: return kind == TYPE_CALLABLE
	if key.begins_with("site:"): return _region_bind_path(data.site, key.substr(5), kind)
	if objects.has(key): return kind == TYPE_OBJECT
	var parts := key.split(":")
	if parts.size() == 2 and parts[0] == "fire_flight" and parts[1].is_valid_int():
		for flight: Dictionary in data.site.get("fire_transport", {}).get("projectiles", []):
			if int(flight.get("projectile_id", 0)) == int(parts[1]): return kind == TYPE_DICTIONARY
		return false
	if parts.size() == 2 and parts[0] == "army_slot": return parts[1].is_valid_int() and int(parts[1]) >= 0 and int(parts[1]) < 32 and kind == TYPE_OBJECT
	if parts.size() >= 2 and parts[0] == "team" and parts[1].is_valid_int() and teams.has(int(parts[1])):
		if parts.size() == 2: return kind == TYPE_OBJECT
		return parts.size() == 3 and parts[2] in ["fatigue", "fire_navigation"] and kind == TYPE_DICTIONARY
	if parts.size() < 3 or parts[0] != "person" or not parts[1].is_valid_int() or not people.has(int(parts[1])): return false
	var person: Dictionary = people[int(parts[1])]
	if parts.size() == 3:
		if parts[2] == "owner": return kind == TYPE_OBJECT
		if parts[2] == "body": return kind == (TYPE_OBJECT if person.actor else TYPE_DICTIONARY)
		if parts[2] == "holder": return kind == TYPE_DICTIONARY and person.body.get("item_state") is Dictionary
		if parts[2] == "cargo": return kind == TYPE_DICTIONARY
	if parts[2] == "body" and not person.actor:
		return _region_bind_path(person.body, key.substr(key.find(":body:") + 6), kind)
	return false

func _prepare_region_main_interval(maximum: float, local_tactical: float, travelling: bool = false) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if travelling and (not restore_only or not str(slot.control.active_site_id).is_empty() or slot._region_original_labs.get(str(terrain.site.id)) != self): return SiteRuntime.fail("INVALID_TRAVEL_HOST")
	if not slot.region_owner_lab.is_valid():
		var wired := _wire_region_gameplay_adapters(slot)
		if not wired.ok: return wired
	# Bind every actual referenced original BEFORE one positive-time mutation.
	var battle_owners := {}
	for battle: Dictionary in slot.region_registry().battles.values():
		if str(battle.get("phase", "")) == "finished" or str(battle.site_id) == str(slot.control.active_site_id): continue
		var bound: Dictionary = slot.region_owner_lab.call(str(battle.site_id), "formula_active")
		if not bound.get("ok", false): return bound
		battle_owners[str(battle.site_id)] = true
	for owner: String in slot.control.fire_clock.get("index", {}):
		if owner == str(slot.control.active_site_id) or not slot.control.fire_clock.index[owner].get("fire_active", false): continue
		if not slot._region_original_labs.has(owner):
			var bound: Dictionary = slot.region_owner_lab.call(owner, "cold_exact")
			if not bound.get("ok", false): return bound
	var originals: Array[TerrainLab] = [self]
	for owner: String in slot._region_original_labs:
		if owner == str(slot.control.active_site_id): continue
		var original: TerrainLab = slot._region_original_labs[owner]
		if not is_instance_valid(original): return SiteRuntime.fail("COMMITTED_UNBOUND")
		if original == self: continue
		if not battle_owners.has(owner) and str(slot.region_registry().modes.get(owner, {}).get("mode", "")) == "formula_active":
			var changed: Dictionary = slot.region_owner_lab.call(owner, "cold_exact")
			if not changed.get("ok", false): return changed
		original.simulation_speed = simulation_speed
		originals.append(original)
		# Old cold Fire synchronization reads this same original runtime, never
		# reopens a stale durable body while the original cached graph is current.
		if slot.control.fire_clock.get("index", {}).has(owner):
			var coordinate: Dictionary = slot._coordinate(original.terrain)
			if not coordinate.ok: return coordinate
			slot._fire_cold_candidates[owner] = {"data": original.terrain, "coordinate": coordinate.site,
				"target": float(slot.control.logical_game_seconds), "sequence": int(slot.control.fire_clock.sequence), "epoch": str(slot.control.fire_clock.epoch)}
	var permit: Dictionary = {}
	if not travelling:
		permit = slot.begin_active_step(terrain.site)
		if not permit.get("unpaused", false): return {"ok": permit.get("ok", true), "pending": true, "source": permit}
	# Restore every real NPC party before selecting an ACTION prefix. Travel's
	# pure upkeep is the GAME consumer; these originals own get-up/down timers.
	for token: String in slot.region_registry().parties:
		if str(slot.region_registry().parties[token].get("phase", "")) != "travelling": continue
		var selected_party := slot._region_npc_party(token)
		if not selected_party.ok: return selected_party
		var party_original := prepare_region_party_original_owner(token, selected_party.party, slot)
		if not party_original.ok: return party_original
		maximum = minf(maximum, party_original.lab._region_party_original_action_limit(maximum))
	if maximum <= ACTION_TIME_EPSILON: return SiteRuntime.fail("REGION_ZERO_ENDPOINT_REQUIRED")
	var action_begin := float(slot.control.fire_clock.action_seconds)
	for original: TerrainLab in originals:
		var demand := minf(maximum, float(original.terrain.site.get("combat_left", 0.0)))
		if original._siege_tactical_active() or original._fire_activity() or original._region_melee_tactical_demand(): demand = maximum
		var demanded := slot.set_region_tactical_demand(str(original.terrain.site.id), action_begin + demand)
		if not demanded.ok: return demanded
	var tactical := slot.GameplayClock.tactical_seconds(slot.region_registry(), action_begin, maximum, minf(maximum, local_tactical))
	var forecast := RegionSaveSlot.preview_fire_interval(slot.control.fire_clock, float(slot.control.logical_game_seconds), maximum, simulation_speed, tactical)
	if not forecast.ok: return forecast
	var queued := slot.queue_region_gameplay_endpoints(float(forecast.game_end), forecast)
	if not queued.ok: return queued
	var interval: Dictionary = slot.preview_region_interval(maximum, simulation_speed, tactical)
	if not interval.get("ok", false) or interval.get("pending", false): return interval
	var accepted_action := float(interval.action_end) - float(interval.action_begin)
	var accepted_game := float(interval.game_end) - float(interval.game_begin)
	var limited := accepted_action
	# Check every source and due capture BEFORE preparing any future work.
	for original: TerrainLab in originals:
		var guarded := original._region_original_interval_guard(interval)
		if not guarded.ok: return _region_preflight_failure(originals, guarded)
		limited = minf(limited, original._region_owner_action_limit(accepted_action, float(interval.tactical_seconds)))
		var capture_sample: Dictionary = original.site_controller.Settlement.capture_sample(original)
		var capture_game: float = original.site_controller.Settlement.capture_interval_limit(original.terrain, capture_sample, accepted_game)
		if capture_game <= ACTION_TIME_EPSILON:
			_region_clear_shared_work_plans(originals)
			var due_capture: Dictionary = original.site_controller.settle_settlement_endpoint()
			if not due_capture.ok: return due_capture
			return {"ok": true, "pending": true, "status": "REGION_EVENT_PENDING"}
		limited = minf(limited, slot.GameplayClock.action_for_game(capture_game, simulation_speed, float(interval.tactical_seconds)))
	for original: TerrainLab in originals:
		var work: Dictionary = original._prepare_shared_work_step(accepted_action, accepted_game, float(interval.tactical_seconds))
		if not work.get("ok", false): return _region_preflight_failure(originals, work)
		limited = minf(limited, float(work.action_seconds))
	if limited <= ACTION_TIME_EPSILON: return _region_preflight_failure(originals, SiteRuntime.fail("REGION_ZERO_ENDPOINT_REQUIRED"))
	if limited < accepted_action - ACTION_TIME_EPSILON:
		interval = slot.preview_region_interval(limited, simulation_speed, minf(limited, tactical))
		if not interval.get("ok", false) or interval.get("pending", false): return _region_preflight_failure(originals, interval)
		accepted_action = float(interval.action_end) - float(interval.action_begin)
		accepted_game = float(interval.game_end) - float(interval.game_begin)
		for original: TerrainLab in originals:
			var retimed: Dictionary = original._retime_shared_work_step(accepted_action, accepted_game)
			if not retimed.get("ok", false): return _region_preflight_failure(originals, retimed)
	var prepared: Dictionary = slot.prepare_region_gameplay_interval(interval)
	if not prepared.get("ok", false): return _region_preflight_failure(originals, prepared)
	return {"ok": true, "pending": false, "interval": interval, "prepared": prepared, "permit": permit, "originals": originals}

func _region_clear_shared_work_plans(originals: Array[TerrainLab]) -> void:
	if originals.is_empty(): _clear_shared_work_step()
	for original: TerrainLab in originals:
		if is_instance_valid(original): original._clear_shared_work_step()

func _region_preflight_failure(originals: Array[TerrainLab], result: Dictionary) -> Dictionary:
	_region_clear_shared_work_plans(originals)
	return result

# Validate the original source before future work/body integration. This also
# prevents a supplied tactical prefix from being silently expanded downstream.

func _region_original_interval_guard(interval: Dictionary) -> Dictionary:
	if terrain == null or site_controller == null or crowd_site != null and crowd_site.active: return SiteRuntime.fail("REGION_OWNER_MODE")
	for field: String in ["action_begin", "action_end", "game_begin", "game_end", "tactical_seconds", "scale"]:
		if not interval.has(field) or not RegionSaveSlot.GameplayClock.seconds(interval[field]): return SiteRuntime.fail("REGION_OWNER_CLOCK")
	var elapsed := float(interval.action_end) - float(interval.action_begin)
	var tactical := float(interval.tactical_seconds)
	if elapsed <= 0.0 or tactical > elapsed + ACTION_TIME_EPSILON or float(interval.scale) != simulation_speed: return SiteRuntime.fail("REGION_OWNER_CLOCK")
	if absf(SiteRuntime.game_seconds(elapsed, tactical) * simulation_speed - (float(interval.game_end) - float(interval.game_begin))) > 0.00000001: return SiteRuntime.fail("REGION_OWNER_CLOCK")
	var party_owner := terrain.has_meta(&"region_party_owner")
	if party_owner:
		var slot: RegionSaveSlot = site_controller.region_slot
		if slot == null: return SiteRuntime.fail("NO_REGION_SLOT")
		var actual: Dictionary = slot.region_travel_party() if str(slot.region_travel_journey().get("token", "")) == _region_party_token else slot._region_npc_party(_region_party_token)
		if not actual.ok: return actual
		var current: Dictionary = slot.region_original_party_runtime_proof(_region_party_token, actual.party)
		if not current.ok or current.get("lab") != self: return current if not current.ok else SiteRuntime.fail("REGION_OWNER_SOURCE")
		var clock: Dictionary = slot.control.fire_clock
		if str(interval.get("epoch", "")) != str(clock.epoch) \
			or int(interval.get("sequence", -1)) != int(clock.sequence) + 1 \
			or absf(float(interval.game_begin) - float(slot.control.logical_game_seconds)) > ACTION_TIME_EPSILON \
			or absf(float(interval.action_begin) - float(clock.action_seconds)) > ACTION_TIME_EPSILON:
			return SiteRuntime.fail("REGION_OWNER_FIRE_SOURCE")
	else:
		var settled := RegionSaveSlot.validate_settlement(terrain.site, float(interval.game_begin))
		if not settled.ok or settled.get("legacy", true) or float(settled.get("pending", INF)) > ACTION_TIME_EPSILON: return SiteRuntime.fail("REGION_OWNER_SOURCE")
	if not _region_point_pending.is_empty() or not terrain.get_meta(&"fire_boundary", {}).is_empty(): return SiteRuntime.fail("REGION_ENDPOINT_PENDING")
	if not is_finite(fire_action_cursor) or absf(fire_action_cursor - float(interval.action_begin)) > ACTION_TIME_EPSILON: return SiteRuntime.fail("REGION_OWNER_FIRE_SOURCE")
	var fire: Dictionary = terrain.site.get("fire_settlement", {})
	if not party_owner and (fire.is_empty() or str(fire.get("epoch", "")) != str(interval.get("epoch", "")) or int(fire.get("sequence", -1)) != int(interval.get("sequence", 0)) - 1 or absf(float(fire.get("action_seconds", -1.0)) - float(interval.action_begin)) > ACTION_TIME_EPSILON or absf(float(fire.get("game_seconds", -1.0)) - float(interval.game_begin)) > ACTION_TIME_EPSILON): return SiteRuntime.fail("REGION_OWNER_FIRE_SOURCE")
	var fire_guard := _fire_step_guard()
	if not fire_guard.ok: return fire_guard
	var demand := minf(elapsed, maxf(0.0, float(terrain.site.get("combat_left", 0.0))))
	if _fire_activity() or _siege_tactical_active() or _region_melee_tactical_demand(): demand = elapsed
	if demand > tactical + ACTION_TIME_EPSILON: return SiteRuntime.fail("REGION_UNCLIPPED_TACTICAL")
	return SiteRuntime.ok()

func _region_melee_tactical_demand() -> bool:
	var people := _exchange_people(false)
	for source: Dictionary in people:
		var ready: bool = source.owner.exchange_ready(int(source.unit)) if int(source.unit) >= 0 else source.owner.exchange_ready()
		if not ready: continue
		for target: Dictionary in people:
			if int(source.faction) == int(target.faction): continue
			var receiving: bool = target.owner.exchange_can_receive(int(target.unit)) if int(target.unit) >= 0 else target.owner.exchange_can_receive()
			if not receiving or not _exchange_initiates(source, int(target.id), true): continue
			var gap: Vector2i = target.cell - source.cell
			if absi(gap.x) + absi(gap.y) != 1 and not _combat_ship_pair(int(source.id), int(target.id)): continue
			if _combat_melee_clear(int(source.id), int(target.id), source.cell, target.cell): return true
	return false

# Replace the prior formula wrapper with these two original driver entries.

func advance_region_cold_stages(interval: Dictionary) -> Dictionary:
	return _advance_region_original_stages(interval, false)

func _advance_region_original_stages(interval: Dictionary, suppress_melee: bool) -> Dictionary:
	if not restore_only or _region_owner_interval_active or terrain == null or crowd_site != null and crowd_site.active:
		return SiteRuntime.fail("REGION_OWNER_MODE")
	var source_guard := _region_original_interval_guard(interval)
	if not source_guard.ok: return _region_preflight_failure([], source_guard)
	var elapsed := float(interval.action_end) - float(interval.action_begin)
	if _region_owner_action_limit(elapsed, float(interval.tactical_seconds)) + ACTION_TIME_EPSILON < elapsed: return _region_preflight_failure([], SiteRuntime.fail("REGION_OWNER_UNCLIPPED_ENDPOINT"))
	_region_owner_interval_active = true
	_region_formula_active = suppress_melee
	var result := _advance_original_shared_step(elapsed, float(interval.game_end), interval, true)
	_region_formula_active = false
	_region_owner_interval_active = false
	result.complete = result.get("ok", false) and result.get("completed", false)
	return result

var _region_owner_interval_active := false

func _wire_region_gameplay_adapters(slot: RegionSaveSlot) -> Dictionary:
	if slot == null or site_controller == null: return SiteRuntime.fail("NO_REGION_SLOT")
	slot.region_owner_lab = Callable(self, "_region_gameplay_owner_lab")
	slot.region_bind_candidate = Callable(self, "_region_gameplay_bind_candidate")
	slot.region_formula_progress = Callable(self, "_region_gameplay_formula_progress")
	slot.region_original_travel_interval = Callable(self, "_region_advance_original_travel_interval")
	slot.region_original_party_progress = Callable(self, "_region_gameplay_party_progress")
	slot.region_original_party_zero = Callable(self, "_region_gameplay_party_zero_points")
	slot.region_original_party_endpoint = Callable(self, "_region_gameplay_party_endpoint")
	slot.region_original_endpoint_checkpoint = Callable(self, "_region_gameplay_endpoint_checkpoint")
	slot.region_original_player_materialize = Callable(self, "_region_gameplay_player_materialize")
	slot.region_contact_active_data = Callable(self, "_region_gameplay_contact_active_data")
	slot.region_party_life_consumer = Callable(self, "_region_gameplay_party_life")
	slot.region_formula_effect_owners = Callable(self, "_region_gameplay_effect_owners")
	slot.region_dispatch_intents = Callable(self, "_region_gameplay_dispatch_intents")
	if slot.has_method("consume_region_player_event"):
		slot.region_player_event_consumer = Callable(slot, "consume_region_player_event")
	else:
		return SiteRuntime.fail("MISSING_PLAYER_EVENT_CONSUMER")
	if terrain != null and terrain.has_meta(&"region_party_owner"):
		var party: Dictionary = slot.region_travel_party()
		if not party.ok: return party
		var current: Dictionary = slot.region_original_party_runtime_proof(_region_party_token, party.party)
		return SiteRuntime.ok("", {"complete": true}) if current.ok and current.lab == self else current
	var owner := str(slot.control.active_site_id)
	if owner.is_empty():
		if terrain == null or terrain.site.is_empty() or not restore_only: return SiteRuntime.fail("MISSING_TRAVEL_HOST")
		owner = str(terrain.site.id)
		if slot._region_original_labs.has(owner) and slot._region_original_labs[owner] != self: return SiteRuntime.fail("DUPLICATE_REGION_OWNER")
		slot._region_original_labs[owner] = self
	var scheduled := _region_gameplay_schedule_evaluation(slot, owner)
	if not scheduled.ok: return scheduled
	return SiteRuntime.ok("", {"complete": true})

func _region_gameplay_owner_lab(site_id: String, requested_mode: String) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null or requested_mode not in ["live", "cold_exact", "formula_active"]:
		return SiteRuntime.fail("INVALID_REGION_OWNER")
	if site_id == str(slot.control.active_site_id):
		if requested_mode != "live" or terrain == null or str(terrain.site.id) != site_id:
			return SiteRuntime.fail("PLAYER_BARRIER")
		var live_receipt := region_bind_receipt(terrain)
		return {"ok": true, "lab": self, "activation": live_receipt} if live_receipt.get("complete", false) else live_receipt
	if requested_mode == "live": return SiteRuntime.fail("WRONG_REGION_MODE")
	var prefix := str(slot.pin.atlas_id) + ":"
	if not site_id.begins_with(prefix): return SiteRuntime.fail("WRONG_SITE")
	var parts := site_id.trim_prefix(prefix).split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return SiteRuntime.fail("WRONG_SITE")
	var coordinate := Vector2i(parts[0].to_int(), parts[1].to_int())
	if RegionGrid.site_id(str(slot.pin.atlas_id), coordinate) != site_id: return SiteRuntime.fail("WRONG_SITE")
	var original: TerrainLab = slot._region_original_labs.get(site_id)
	if not is_instance_valid(original):
		var opened: Dictionary = slot.open_site(coordinate)
		if not opened.get("ok", false): return opened
		var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
		if scene == null: return SiteRuntime.fail("MISSING_ORIGINAL_SCENE")
		original = scene.instantiate() as TerrainLab
		if opened.data.site.get("actors", {}).has("npc"): original.npc = TerrainTestNPC.new()
		original.restore_only = true
		original.visible = false
		original.simulation_speed = simulation_speed
		original.exchange_enabled = exchange_enabled
		original.fixed_action_steps_enabled = fixed_action_steps_enabled
		original.pause_when_unfocused = false
		add_child(original)
		original.site_controller.region_slot = slot
		original.site_controller._auto_save_blocked = true
		var restored: Dictionary
		if opened.get("created", false):
			var guard := original.exchange_snapshot_guard(opened.data)
			if not guard.ok:
				original.free()
				return guard
			original.bind_terrain(opened.data)
			restored = original.region_bind_receipt(opened.data)
		else:
			restored = original.restore_original_site(opened.data)
		if not restored.get("ok", false) or not original.region_bind_receipt(original.terrain).get("complete", false):
			original.free()
			return restored if not restored.get("ok", false) else SiteRuntime.fail("REGION_BIND_INCOMPLETE")
		slot._region_original_labs[site_id] = original
		var scheduled := _region_gameplay_schedule_evaluation(slot, site_id)
		if not scheduled.ok: return scheduled
	if original.terrain == null or str(original.terrain.site.id) != site_id or not original.restore_only:
		return SiteRuntime.fail("STALE_REGION_OWNER")
	var receipt := original.region_bind_receipt(original.terrain)
	if not receipt.get("complete", false): return receipt
	if str(receipt.get("backend", "")) != "gd": return SiteRuntime.fail("REGION_BACKEND_UNADMITTED")
	receipt.mode = requested_mode
	receipt.consumer = "original_formula_site" if requested_mode == "formula_active" else "original_replay"
	receipt.generation = int(slot._marker.get("generation", 0))
	var mode: Dictionary = slot.region_registry().modes.get(site_id, {})
	if str(mode.get("mode", "")) != requested_mode or int(mode.get("generation", -1)) != receipt.generation or not mode.get("activation", {}).get("complete", false):
		var activated := slot.activate_region_mode(site_id, requested_mode, str(receipt.consumer), receipt)
		if not activated.ok: return activated
	return {"ok": true, "lab": original, "activation": receipt}

func _region_gameplay_bind_candidate(original: TerrainLab, candidate: TerrainData, requested_mode: String) -> Dictionary:
	if original == null or not original.has_method("prepare_region_owner_bind"):
		return SiteRuntime.fail("MISSING_REGION_BIND_PREFLIGHT")
	return original.call("prepare_region_owner_bind", candidate, requested_mode, site_controller.region_slot)

func _region_gameplay_formula_progress(original: TerrainLab, battle: Dictionary, interval: Dictionary) -> Dictionary:
	if battle.is_empty():
		if original == null or not original.has_method("advance_region_cold_stages"):
			return SiteRuntime.fail("MISSING_COLD_PROGRESS")
		return original.call("advance_region_cold_stages", interval)
	if original == null or original.terrain == null or str(original.terrain.site.id) != str(battle.site_id):
		return SiteRuntime.fail("WRONG_BATTLE_SITE")
	if not original.has_method("advance_region_formula_stages"):
		return SiteRuntime.fail("MISSING_FORMULA_PROGRESS")
	return original.call("advance_region_formula_stages", interval)

func _region_gameplay_effect_owners(original: TerrainLab, battle: Dictionary) -> Dictionary:
	var rules: Script = load("res://scripts/region_lab/region_gameplay_battle.gd")
	var actual: Dictionary = rules.owner_callbacks(original, battle)
	# Original apply_contact must consume now instead of entering the deferred
	# endpoint queue again. Preserve an outer original consumer's flag.
	var wrapped := {}
	for kind: String in ["damage", "fatigue"]:
		var owner: Callable = actual[kind]
		wrapped[kind] = func(effect: Dictionary) -> Dictionary:
			var consuming := original._region_point_consuming
			original._region_point_consuming = true
			var result: Dictionary = owner.call(effect)
			original._region_point_consuming = consuming
			return result
	wrapped.siege_round = func(_effect: Dictionary) -> Dictionary:
		if original._region_point_consuming:
			# This exact original consumer already owns the point. Complete only
			# the previously integrated siege stage; its outer tail handles the
			# remaining original queues without a reentrant consumer.
			original._advance_siege(0.0)
			return original.siege_flush_contact_batch()
		return original.consume_region_point(false)
	wrapped.order = func(effect: Dictionary) -> Dictionary:
		return original._region_gameplay_original_order(battle, effect)
	return wrapped

func _region_gameplay_original_order(battle: Dictionary, effect: Dictionary) -> Dictionary:
	if str(effect.get("order", "")) != "RETREAT" or str(effect.get("side", "")) not in ["attackers", "defenders"]:
		return SiteRuntime.fail("INVALID_REGION_ORDER")
	var side: Array = battle[str(effect.side)]
	var policy: Script = load("res://scripts/region_lab/region_gameplay_ai.gd")
	var army_policy: Script = load("res://scripts/terrain_lab/site_army_ai.gd")
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null: return SiteRuntime.fail("NO_REGION_SLOT")
	var ordered: Array[Dictionary] = []
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled or not team.command_eligible(team.current_commander): continue
		var commander := team.combat_identity(team.current_commander)
		if not side.has(commander): continue
		if commander == controlled_person_id(): return SiteRuntime.fail("PLAYER_HOLDER")
		var known: Dictionary = policy.view(slot.region_registry(), commander, float(slot.control.logical_game_seconds),
			str(terrain.site.id), policy.person_ref(terrain.site, commander))
		var enemies: Array[Dictionary] = []
		for object: String in known:
			var receipt: Dictionary = known[object]
			if str(receipt.id) != str(effect.get("known_receipt", "")): continue
			# Local enemy cells belong only to their original observed Site.
			# A lawful remote report retains its old source geometry and age.
			if str(receipt.get("object_scope", "")) != str(terrain.site.id): continue
			var seen: Array[Dictionary] = []
			for person: Dictionary in receipt.get("value", {}).get("people", []):
				if not person.get("cell") is Array or person.cell.size() != 2: return SiteRuntime.fail("INVALID_INTEL")
				seen.append({"id": int(person.get("id", -1)), "cell": Vector2i(int(person.cell[0]), int(person.cell[1]))})
			if not seen.is_empty(): enemies.append({"people": seen})
		if enemies.is_empty(): return SiteRuntime.fail("UNKNOWN_TARGET")
		if army_policy._withdraw(team, enemies):
			ordered.append({"team_id": team.team_id, "order": "RETREAT", "status": team.tactical_ai_status})
		else:
			var held: Dictionary = team.issue_tactical_ai_order(TerrainArmy.CombatOrder.HOLD)
			if not held.ok: return held
			ordered.append(held)
	return SiteRuntime.ok("", {"complete": true, "orders": ordered}) if not ordered.is_empty() else SiteRuntime.fail("NO_COMMANDER")

func _region_gameplay_dispatch_intents(original: TerrainLab, scoped_intel: Dictionary, at: float) -> Dictionary:
	var policy: Script = load("res://scripts/region_lab/region_gameplay_ai.gd")
	var selected: Dictionary = policy.dispatch_candidates(original, scoped_intel, at)
	if not selected.get("ok", false): return selected
	var slot: RegionSaveSlot = original.site_controller.region_slot
	var coordinate: Dictionary = slot._coordinate(original.terrain)
	if not coordinate.get("ok", false): return coordinate
	var travel_site: Script = load("res://scripts/region_lab/region_travel_site.gd")
	var intents: Array[Dictionary] = []
	for intent: Dictionary in selected.intents:
		var team: TerrainArmy = null
		for candidate: TerrainArmy in original.combat_armies:
			if candidate.team_id == int(intent.team_id):
				team = candidate
				break
		if team == null or not team.command_eligible(team.current_commander): continue
		var commander := team.combat_identity(team.current_commander)
		var person: Dictionary = original._combat_target_in_site(commander)
		if person.is_empty(): continue
		var sea: bool = bool(original.site_controller.vehicles.is_embarked(commander))
		intent.start_component = 0 if sea else travel_site.start_component(slot, coordinate.site, person.cell, original.terrain)
		if int(intent.start_component) < 0: continue
		intent.steps = [] # Slot runs the original resolver after this selected intent.
		intents.append(intent)
	return {"ok": true, "intents": intents}

func _region_gameplay_schedule_evaluation(slot: RegionSaveSlot, site_id: String) -> Dictionary:
	if site_id.is_empty(): return SiteRuntime.fail("WRONG_SITE")
	var next := (floorf(float(slot.control.logical_game_seconds) / slot.REGION_EVALUATION_SECONDS) + 1.0) * slot.REGION_EVALUATION_SECONDS
	return slot.queue_region_event("evaluation:%s:%.6f" % [site_id, next], "evaluation", next, site_id)

func _refresh_shared_work_preflight() -> Dictionary:
	if not site_controller.work_team.has_method("apply_shared_preflight"):
		return SiteRuntime.fail("WORK_SHARED_PREFLIGHT")
	# Every pass can only remove one of these original held requests. No
	# selector, positive clock, material payment or replacement worker runs.
	for iteration: int in range(_shared_work_requests.size() + 1):
		var camp: Dictionary = terrain.site.worker
		var camp_admitted := false
		for request: Dictionary in _shared_work_requests:
			if str(request.provider) == "runtime" and str(request.key) == "worker":
				camp_admitted = is_same(request.get("task", {}), camp) and str(request.get("paused", "")).is_empty()
		terrain.set_meta(&"site_camp_operating_task", camp if camp_admitted else {})
		var updated: Variant = site_controller.work_team.apply_shared_preflight(_shared_work_requests)
		if not updated is Array or updated.size() != _shared_work_requests.size():
			return SiteRuntime.fail("WORK_SHARED_PREFLIGHT")
		_shared_work_requests = updated
		var removed := false
		for request: Dictionary in _shared_work_requests:
			if str(request.provider) != "runtime" or not str(request.get("paused", "")).is_empty(): continue
			var name := str(request.key)
			if name not in ["worker", "manual"] or not is_same(request.get("task", {}), terrain.site[name]):
				return SiteRuntime.fail("WORK_SHARED_PREFLIGHT")
			var actor: TerrainTestCharacter = character if name == "manual" else npc
			var task: Dictionary = request.task
			var checked := SiteRuntime.work_preflight(terrain, task, task.cargo,
				int(site_controller._shared_worker_inputs.get(name + "_limit", 0)), actor.faction_id,
				actor.person_id, site_controller.reserves_cell)
			if not checked.ok:
				request.paused = str(checked.code)
				site_controller._shared_worker_inputs[name + "_ready"] = false
				removed = true
				continue
			request.remaining = float(checked.remaining)
			request["runtime_productivity"] = float(checked.productivity)
			var feature: Dictionary = terrain.site.features.get(str(task.target).trim_prefix("feature:"), {})
			if str(task.get("action", "")) == "operate" and int(task.get("work_slot", -1)) >= 0 and str(feature.get("kind", "")) in SiteRuntime.FARM_KINDS + SiteRuntime.PASTURE_KINDS:
				# Runtime consumes unweighted base seconds and applies the true
				# original slot productivity itself; WorkTeam sums output seconds.
				request.remaining = float(request.remaining) / float(checked.productivity)
		if not removed: return SiteRuntime.ok()
	return SiteRuntime.fail("WORK_SHARED_PREFLIGHT")

func _shared_production_event_limit(seconds: float) -> float:
	var rates := {}
	for request: Dictionary in _shared_work_requests:
		if not str(request.get("paused", "")).is_empty(): continue
		var target := ""
		var rate := 0.0
		if str(request.provider) == "runtime":
			var task: Dictionary = request.get("task", {})
			if str(task.get("action", "")) != "operate": continue
			target = str(task.get("target", ""))
			rate = float(request.get("runtime_productivity", 1.0))
		elif str(request.provider) == "work_team" and str(request.productive_kind) == "sum" and str(request.key).ends_with(":operate"):
			target = str(request.key).trim_suffix(":operate")
			for person: Dictionary in request.participants: rate += float(person.get("progress_multiplier", 1.0))
		if not target.begins_with("feature:") or rate <= 0.0: continue
		rates[target] = float(rates.get(target, 0.0)) + rate
	var limit := seconds
	for target: String in rates:
		var feature: Dictionary = terrain.site.features.get(target.trim_prefix("feature:"), {})
		var definition := SiteRuntime.feature_recipe(feature) if not feature.is_empty() else {}
		if not definition.has("cycle"): continue
		var left := maxf(0.0, float(definition.cycle) - float(feature.get("production", 0.0))) * 60.0
		# Actual fatigue productivity is <= 1. This conservative prefix cannot
		# pass the shared original batch endpoint even with multiple providers.
		if left > ACTION_TIME_EPSILON: limit = minf(limit, left / float(rates[target]))
	return maxf(ACTION_TIME_EPSILON, limit)

# Merge into ORIGINAL TerrainLab. Tickets are private preparation receipts;
# body, items, movement, work and the persisted marker retain their owners.
var _region_owner_bind_tickets: Dictionary = {}
var _region_party_bind_candidates: Dictionary = {}
var _region_owner_source_receipts: Dictionary = {}

static func _region_detached_bind_data(data: TerrainData) -> TerrainData:
	var copy := SiteEnv.navigation_for_state(data, data.site.duplicate(true))
	for field: String in ["height_levels", "surface_types", "flags", "cliff_drops", "ramp_edges", "detail_variation", "fertility", "moisture", "drainage", "foundation", "groundwater", "water_kind", "water_body"]:
		copy.set(field, data.get(field).duplicate())
	copy.parameters = data.parameters.duplicate(true)
	copy.resource_base = data.resource_base.duplicate(true)
	if data.has_meta(&"region_party_runtime_mapping"):
		copy.set_meta(&"region_party_runtime_mapping", data.get_meta(&"region_party_runtime_mapping").duplicate(true))
	return copy

func _region_selected_bind_source(data: TerrainData, slot: RegionSaveSlot) -> Dictionary:
	if data == null or slot == null: return SiteRuntime.fail("NO_REGION_SOURCE")
	var proof: Dictionary = slot.region_bind_proof(data) # A selected cold owner need not be active.
	if proof.is_empty(): return SiteRuntime.fail("UNSELECTED_REGION_SOURCE")
	var path := slot.folder.path_join(str(proof.path))
	if FileAccess.get_sha256(path) != str(proof.sha256): return SiteRuntime.fail("STALE_REGION_SOURCE")
	var coordinate: Dictionary = slot._coordinate(data)
	if not coordinate.ok: return coordinate
	var readback: Dictionary = slot._load_checked(path, coordinate.site)
	if not readback.ok: return readback
	var body_hash := RegionCheckpoint.state_hash(data.site)
	var producer: Variant = data.get_meta(&"site_garrison_lab") if data.has_meta(&"site_garrison_lab") else null
	if producer is WeakRef: producer = producer.get_ref()
	if producer is TerrainLab and is_instance_valid(producer) and producer.terrain == data:
		var canonical := _region_verify_canonical_bind_source(data, slot, readback.data)
		if not canonical.ok: return canonical
		canonical["proof"] = proof
		return canonical
	if RegionCheckpoint.state_hash(readback.data.site) == body_hash:
		return SiteRuntime.ok("", {"proof": proof, "body_hash": body_hash, "canonical_data": readback.data})
	var accepted: Dictionary = _region_owner_source_receipts.get(data.get_instance_id(), {})
	if accepted.is_empty() or accepted.proof != proof or accepted.body_hash != body_hash or accepted.get("data") != data:
		return SiteRuntime.fail("STALE_REGION_SOURCE", "Source must be the selected snapshot or this original Lab's completed replay")
	return SiteRuntime.ok("", {"proof": proof, "body_hash": body_hash, "replayed": true, "canonical_data": data})

## Call before the original retained replay child is freed. This is a receipt
## for its actual completed body, not a metadata switch that admits a caller copy.
func _region_register_replayed_bind_source(input_source: TerrainData, accepted: TerrainData,
		slot: RegionSaveSlot, producer: TerrainLab) -> Dictionary:
	if producer == null or not producer.restore_only or producer.get_parent() != self or producer.terrain == null or accepted == null or str(producer.terrain.site.id) != str(accepted.site.id):
		return SiteRuntime.fail("INVALID_REGION_REPLAY_SOURCE")
	var selected := _region_selected_bind_source(input_source, slot)
	if not selected.ok: return selected
	var settlement := RegionSaveSlot.validate_settlement(accepted.site, slot.control.logical_game_seconds)
	if not settlement.ok or bool(settlement.legacy) or float(settlement.pending) > ACTION_TIME_EPSILON: return SiteRuntime.fail("REGION_REPLAY_PENDING")
	var metadata := SiteStore.validate_region_snapshot(accepted, {})
	if not metadata.ok: return metadata
	var original_receipt: Dictionary = producer._region_owner_restore_receipt
	if original_receipt.get("owners_restored") != true or producer._region_point_consuming or not producer._region_point_pending.is_empty():
		return SiteRuntime.fail("REGION_REPLAY_PENDING")
	var graph := producer.validate_region_owner_bind_payload(accepted, metadata.owners, metadata.context)
	if not graph.ok: return graph
	var actual := producer.capture_region_owner_state(metadata.context)
	if not actual.ok: return actual
	var payload := SiteStore.capture_region_snapshot(producer.terrain, metadata.context, actual.owner_states)
	if not payload.ok or RegionCheckpoint.state_hash(payload.state) != RegionCheckpoint.state_hash(accepted.site) or RegionCheckpoint.state_hash({"owners": payload.owners}) != RegionCheckpoint.state_hash({"owners": metadata.owners}): return SiteRuntime.fail("STALE_REGION_REPLAY_SOURCE")
	_region_owner_source_receipts[accepted.get_instance_id()] = {"data": accepted, "proof": selected.proof,
		"body_hash": RegionCheckpoint.state_hash(accepted.site), "graph_hash": graph.graph_hash}
	return SiteRuntime.ok()

func _region_new_bind_child(data: TerrainData) -> Dictionary:
	if not is_inside_tree(): return SiteRuntime.fail("REGION_BIND_NO_TREE")
	var original := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if original == null: return SiteRuntime.fail("NO_RUNTIME")
	var child := original.instantiate() as TerrainLab
	if child == null: return SiteRuntime.fail("NO_RUNTIME")
	if data.site.get("actors", {}).has("npc"): child.npc = TerrainTestNPC.new()
	child.restore_only = true
	child.exchange_enabled = exchange_enabled
	child.simulation_speed = simulation_speed
	child.fixed_action_steps_enabled = fixed_action_steps_enabled
	child.pause_when_unfocused = false
	child.visible = false
	add_child(child)
	return SiteRuntime.ok("", {"child": child})

func _region_bootstrap_bind_child(child: TerrainLab, data: TerrainData) -> Dictionary:
	var context := {}
	var owners := {}
	if data.site.has("region_snapshot"):
		var saved := SiteStore.validate_region_snapshot(data, {})
		if not saved.ok: return saved
		var graph := child.validate_region_owner_bind_payload(data, saved.owners, saved.context)
		if not graph.ok: return graph
		context = saved.context
		owners = saved.owners
	else:
		var checked := SiteStore._validate_state(data, data.site.duplicate(true))
		if not checked.ok: return checked
	var token := "region_restore_" + Crypto.new().generate_random_bytes(16).hex_encode()
	child._region_owner_bind_tickets[token] = {"kind": "bootstrap", "data": data,
		"body_hash": RegionCheckpoint.state_hash(data.site), "context": context, "owners": owners}
	child.bind_terrain(data, {"ok": true, "crowd_site": null, "region_bind_token": token})
	var receipt: Dictionary = child._region_bind_receipt_value
	child._region_owner_bind_tickets.erase(token)
	if child.terrain != data or child._region_bound_data != data or receipt.get("owners_restored") != true:
		return SiteRuntime.fail("REGION_CHILD_BIND_FAILED")
	child.set_process(false)
	child.set_process_input(false)
	child.set_process_unhandled_input(false)
	for actor: TerrainTestCharacter in child.combat_actors: actor.set_process(false)
	for team: TerrainArmy in child.combat_armies: team.set_process(false)
	return SiteRuntime.ok("", {"context": context, "owners": owners})

## Called at bind_terrain's first line, before any original clear/reset.
func _region_bind_ticket_admission(data: TerrainData, prepared: Dictionary) -> Dictionary:
	if data != null:
		var social_schema := SiteStore._validate_unadmitted_social_state(data.site)
		if not social_schema.ok: return social_schema
	var token := str(prepared.get("region_bind_token", ""))
	if token.is_empty():
		return SiteRuntime.fail("REGION_BIND_TICKET_REQUIRED") if data != null and data.site.has("region_snapshot") else SiteRuntime.ok("", {"trusted": false})
	var ticket: Dictionary = _region_owner_bind_tickets.get(token, {})
	if ticket.is_empty() or ticket.get("data") != data or ticket.body_hash != RegionCheckpoint.state_hash(data.site): return SiteRuntime.fail("STALE_REGION_BIND_TICKET")
	if ticket.kind in ["bootstrap", "projection"]:
		if not restore_only: return SiteRuntime.fail("INVALID_REGION_BIND_TICKET")
	elif ticket.kind == "published":
		var selected := _region_committed_bind_ticket(ticket, data)
		if not selected.ok: return selected
	elif ticket.kind == "selected":
		var selected := _region_check_selected_restore_ticket(ticket, data)
		if not selected.ok: return selected
	else: return SiteRuntime.fail("INVALID_REGION_BIND_TICKET")
	return SiteRuntime.ok("", {"trusted": true, "token": token, "context": ticket.context,
		"projection": ticket.kind == "projection"})

## Invoke after original Fire owner restoration and before recording complete.
func _region_finish_bind_ticket(admission: Dictionary) -> Dictionary:
	if not bool(admission.get("trusted", false)): return SiteRuntime.ok("", {"owners_restored": true, "effects_complete": true})
	var ticket: Dictionary = _region_owner_bind_tickets.get(str(admission.token), {})
	if ticket.is_empty() or terrain != ticket.data: return SiteRuntime.fail("STALE_REGION_BIND_TICKET")
	if ticket.kind == "selected":
		var selected := _region_check_selected_restore_ticket(ticket, terrain)
		if not selected.ok: return selected
	if ticket.kind == "projection": return SiteRuntime.ok("", {"owners_restored": false, "effects_complete": false})
	if not ticket.context.is_empty():
		var restored := prepare_restore_region_owner_state(ticket.owners, ticket.context)
		if not restored.ok: return restored
		var published := publish_restore_region_owner_state(restored)
		if not published.ok: return published
	if ticket.kind == "selected": _region_owner_bind_tickets.erase(str(admission.token))
	return SiteRuntime.ok("", {"owners_restored": true, "effects_complete": bool(ticket.context.get("effects_complete", true)),
		"zero_world_only": not bool(ticket.context.get("effects_complete", true))})

static func _region_capture_duty_cache() -> Dictionary:
	return {"round": DutyAI.review_round, "seat_waits": DutyAI._seat_waits.duplicate(true), "inmate_since": DutyAI._inmate_since.duplicate(true),
		"settlement_traces": DutyAI.settlement_traces.duplicate(true), "nation_traces": DutyAI.nation_traces.duplicate(true), "last_nation_trace": DutyAI.last_nation_trace.duplicate(true)}

static func _region_restore_duty_cache(value: Dictionary) -> void:
	DutyAI.review_round = int(value.round)
	DutyAI._seat_waits.clear(); DutyAI._seat_waits.merge(value.seat_waits)
	DutyAI._inmate_since.clear(); DutyAI._inmate_since.merge(value.inmate_since)
	DutyAI.settlement_traces.assign(value.settlement_traces)
	DutyAI.nation_traces.clear(); DutyAI.nation_traces.merge(value.nation_traces)
	DutyAI.last_nation_trace = value.last_nation_trace

func prepare_region_owner_bind(candidate: TerrainData, mode: String, slot: RegionSaveSlot) -> Dictionary:
	var duty := _region_capture_duty_cache()
	var result := _region_prepare_original_bind(candidate, mode, slot)
	_region_restore_duty_cache(duty)
	return result

func _region_prepare_original_bind(candidate: TerrainData, mode: String, slot: RegionSaveSlot) -> Dictionary:
	if candidate == null or slot == null or mode not in ["live", "cold_exact", "materializing", "dematerializing"] or candidate.site.has("crowd"):
		return SiteRuntime.fail("INVALID_REGION_BIND")
	var source: TerrainData = candidate.get_meta(&"region_bind_source", candidate)
	if candidate.has_meta(&"region_bind_source"): candidate.remove_meta(&"region_bind_source")
	if source == null or str(source.site.get("id", "")) != str(candidate.site.get("id", "")): return SiteRuntime.fail("INVALID_REGION_BIND_SOURCE")
	var selected := _region_selected_bind_source(source, slot)
	if not selected.ok: return selected
	var canonical_source: TerrainData = selected.get("canonical_data", source)
	var source_copy := _region_detached_bind_data(canonical_source)
	var target := _region_detached_bind_data(candidate)
	var deliveries := SiteStore._region_prepare_deliveries(target.site)
	if not deliveries.ok: return deliveries
	var created := _region_new_bind_child(source_copy)
	if not created.ok: return created
	var child: TerrainLab = created.child
	var restored := _region_bootstrap_bind_child(child, source_copy)
	if not restored.ok: child.free(); return restored
	var context: Dictionary = restored.context
	if context.is_empty():
		var settlement: Dictionary = source_copy.site.get("simulation_settlement", {})
		var fire: Dictionary = source_copy.site.get("fire_settlement", {})
		context = {"purpose": "region_materialize", "mode": mode, "source_generation": int(slot._marker.get("generation", 0)),
			"runtime_revision": int(slot.region_registry().revision), "token": "region_bind_" + Crypto.new().generate_random_bytes(16).hex_encode(),
			"game_seconds": float(settlement.get("last_settled_game_seconds", slot.control.logical_game_seconds)), "action_seconds": child.fire_action_cursor,
			"fire_epoch": str(fire.get("epoch", slot.control.fire_clock.epoch)), "fire_sequence": int(fire.get("sequence", 0)),
			"interval_complete": true, "effects_complete": true, "mode_revision": int(slot.region_registry().modes.get(str(source_copy.site.id), {}).get("revision", 0)),
			"backend": "gd", "events": [], "endpoint_payload": {}}
	# The selected source and its original owner graph were authenticated
	# above. Incoming changes make the target's old checkpoint obsolete.
	target.site.erase("region_snapshot")
	var ecology := SiteStore.prepare_ecology_candidate(target, context)
	if not ecology.ok: child.free(); return ecology
	target = ecology.data
	var transformed := RegionCheckpoint.state_hash(source_copy.site) != RegionCheckpoint.state_hash(target.site)
	if transformed:
		var projection := _region_project_original_bind_child(child, target, context)
		if not projection.ok: child.free(); return projection
	else:
		target = child.terrain
	context = context.duplicate(true)
	context.purpose = "region_materialize" if mode == "live" or mode == "materializing" else "region_dematerialize"
	context.mode = mode
	context.source_generation = int(slot._marker.get("generation", 0))
	context.runtime_revision = int(slot.region_registry().revision)
	context.mode_revision = int(slot.region_registry().modes.get(str(target.site.id), {}).get("revision", 0))
	context.token = "region_bind_" + Crypto.new().generate_random_bytes(16).hex_encode()
	child.site_controller._capture_positions()
	var actual := child.capture_region_owner_state(context)
	if not actual.ok: child.free(); return actual
	var capture := SiteStore.capture_region_snapshot(target, context, actual.owner_states)
	if not capture.ok: child.free(); return capture
	# The child retains its actual Site aliases while the ticket carries the
	# ordinary validated Store payload. Replacing child.site would orphan jobs.
	target = _region_detached_bind_data(target)
	target.site = capture.state
	var final_graph := child.validate_region_owner_bind_payload(target, capture.owners, context)
	if not final_graph.ok: child.free(); return final_graph
	var token := str(context.token)
	_region_owner_bind_tickets[token] = {"kind": "prepared", "data": target, "child": child, "slot": slot, "source": source,
		"proof": selected.proof, "source_hash": selected.body_hash, "body_hash": RegionCheckpoint.state_hash(target.site),
		"graph_hash": final_graph.graph_hash, "context": context, "owners": capture.owners, "mode": mode,
		"generation": int(slot._marker.get("generation", 0)), "revision": int(slot.region_registry().revision), "saved_path": "", "saved_sha256": ""}
	return SiteRuntime.ok("", {"data": target, "context": context, "token": token, "graph_hash": final_graph.graph_hash,
		"can_publish": _region_can_publish_bind.bind(token), "save_candidate": _region_save_bind_candidate.bind(token),
		"publish": _region_publish_bind_candidate.bind(token),
		"resolve_battle_people": _region_resolve_prepared_battle_people.bind(token),
		"discard": _region_discard_bind_candidate.bind(token)})

func _region_can_publish_bind(token: String) -> bool:
	return bool(_region_check_bind_candidate(token).get("ok", false))

func _region_check_bind_candidate(token: String) -> Dictionary:
	var ticket: Dictionary = _region_owner_bind_tickets.get(token, {})
	if ticket.is_empty() or ticket.kind != "prepared": return SiteRuntime.fail("STALE_REGION_BIND_TICKET")
	var slot: RegionSaveSlot = ticket.slot
	if int(slot._marker.get("generation", 0)) != int(ticket.generation) or int(slot.region_registry().revision) != int(ticket.revision): return SiteRuntime.fail("STALE_REGION_BIND_TICKET")
	var source := _region_selected_bind_source(ticket.source, slot)
	if not source.ok or source.proof != ticket.proof or source.body_hash != ticket.source_hash: return SiteRuntime.fail("STALE_REGION_BIND_SOURCE")
	if RegionCheckpoint.state_hash(ticket.data.site) != ticket.body_hash: return SiteRuntime.fail("STALE_REGION_BIND_BODY")
	var graph := validate_region_owner_bind_payload(ticket.data, ticket.owners, ticket.context)
	if not graph.ok or graph.graph_hash != ticket.graph_hash: return SiteRuntime.fail("STALE_REGION_BIND_GRAPH")
	return SiteRuntime.ok("", {"generation": ticket.generation, "graph_hash": ticket.graph_hash})

func _region_save_bind_candidate(data: TerrainData, path: String, token: String) -> Dictionary:
	var duty := _region_capture_duty_cache()
	var ticket: Dictionary = _region_owner_bind_tickets.get(token, {})
	if ticket.is_empty(): return SiteRuntime.fail("STALE_REGION_BIND_TICKET")
	var captured := RegionOwnerSnapshot.peek_values(ticket.owners.scene, "duty", ticket.context)
	if not captured.ok: return captured
	_region_restore_duty_cache(captured.value)
	var result := _region_write_bind_candidate(data, path, token)
	_region_restore_duty_cache(duty)
	return result

func _region_write_bind_candidate(data: TerrainData, path: String, token: String) -> Dictionary:
	var admitted := _region_check_bind_candidate(token)
	if not admitted.ok: return admitted
	var ticket: Dictionary = _region_owner_bind_tickets[token]
	if data == null or path.is_empty() or RegionCheckpoint.state_hash(data.site) != ticket.body_hash: return SiteRuntime.fail("STALE_REGION_BIND_BODY")
	var child: TerrainLab = ticket.child
	if not is_instance_valid(child) or child.terrain == null: return SiteRuntime.fail("STALE_REGION_BIND_PRODUCER")
	# Capture from the child that owns the original restored aliases. The
	# detached ticket body is only the validated persistence candidate.
	var saved := SiteStore.save_region_snapshot(child.terrain, path, ticket.context, ticket.owners)
	if not saved.ok: return saved
	var slot: RegionSaveSlot = ticket.slot
	var coordinate: Dictionary = slot._coordinate(ticket.data)
	if not coordinate.ok: return coordinate
	var check: Dictionary = slot._load_checked(path, coordinate.site)
	if not check.ok or RegionCheckpoint.state_hash(check.data.site) != ticket.body_hash:
		return SiteRuntime.fail("STALE_REGION_BIND_BODY")
	ticket.saved_path = path
	ticket.saved_sha256 = FileAccess.get_sha256(path)
	return SiteRuntime.ok("", {"data": ticket.data, "path": path, "sha256": ticket.saved_sha256})

func _region_committed_bind_ticket(ticket: Dictionary, data: TerrainData) -> Dictionary:
	var slot: RegionSaveSlot = ticket.slot
	if int(slot._marker.get("generation", 0)) != int(ticket.generation) + 1 or ticket.saved_path.is_empty() or FileAccess.get_sha256(ticket.saved_path) != ticket.saved_sha256:
		return SiteRuntime.fail("STALE_REGION_BIND_COMMIT")
	var proof: Dictionary = slot.region_bind_proof(data)
	if proof.is_empty() or slot.folder.path_join(str(proof.path)) != str(ticket.saved_path) or str(proof.sha256) != str(ticket.saved_sha256) or int(proof.generation) != int(ticket.generation) + 1:
		return SiteRuntime.fail("STALE_REGION_BIND_COMMIT")
	if RegionCheckpoint.state_hash(data.site) != ticket.body_hash: return SiteRuntime.fail("STALE_REGION_BIND_BODY")
	var graph := validate_region_owner_bind_payload(data, ticket.owners, ticket.context)
	if not graph.ok or graph.graph_hash != ticket.graph_hash: return SiteRuntime.fail("STALE_REGION_BIND_GRAPH")
	return SiteRuntime.ok()

func _region_publish_bind_candidate(data: TerrainData, token: String) -> Dictionary:
	var ticket: Dictionary = _region_owner_bind_tickets.get(token, {})
	if ticket.is_empty(): return SiteRuntime.fail("STALE_REGION_BIND_TICKET")
	var committed := _region_committed_bind_ticket(ticket, data)
	if not committed.ok: return committed
	ticket.data = data # Exact readback was checked against the marker, body and full graph.
	ticket.kind = "published"
	bind_terrain(data, {"ok": true, "crowd_site": null, "region_bind_token": token})
	var result: Dictionary = _region_bind_receipt_value.duplicate(true)
	if terrain != data or _region_bound_data != data or result.get("owners_restored") != true:
		return SiteRuntime.fail("COMMITTED_UNBOUND", "Selected complete marker remains resumable; replay no transfer")
	if is_instance_valid(ticket.child): ticket.child.free()
	_region_owner_bind_tickets.erase(token)
	return result

func _region_project_original_bind_child(child: TerrainLab, target: TerrainData, source_context: Dictionary) -> Dictionary:
	var pending_guard := _region_pending_projection_guard(child, target, source_context)
	if not pending_guard.ok: return pending_guard
	var controlled_before := int(child.terrain.site.get("controlled_person_id", 0))
	var context := source_context.duplicate(true)
	context.mode = "cold_exact"
	target.site.erase("region_snapshot") # Private candidate, after full original source restore.
	var core := SiteStore._validate_state(target, target.site.duplicate(true), 1, null, context)
	if not core.ok: return core
	var retained_teams := {}
	var retained_people := {}
	for army: Dictionary in target.site.get("armies", []):
		retained_teams[int(army.team_id)] = true
		for body: Dictionary in army.units: retained_people[int(body.person_id)] = true
	for body: Dictionary in target.site.get("actors", {}).values(): retained_people[int(body.person_id)] = true
	var removed: Array = []
	for team: TerrainArmy in child.combat_armies:
		if team.combat_enabled and not retained_teams.has(team.team_id): removed.append(team)
	var batch_guard: Dictionary = child.combat_movement_coordinator.validate_handoff_formations(removed)
	if not batch_guard.get("ok", false): return SiteRuntime.fail("REGION_BATCH_DEPENDENCY")
	# A departing body cannot take an unfinished PA transaction or erase its
	# already paid precise projectile owner. Retained people's jobs stay alive.
	for job: Dictionary in child.site_controller.person_actions._jobs.values():
		if not retained_people.has(int(job.get("executor_id", 0))) or int(job.get("target_id", 0)) > 0 and not retained_people.has(int(job.target_id)):
			return SiteRuntime.fail("REGION_ACTIVE_DEPENDENCY")
	for actor: TerrainTestCharacter in child.combat_actors:
		if not retained_people.has(actor.person_id) and not actor.projectiles.is_empty(): return SiteRuntime.fail("REGION_FLIGHT_DEPENDENCY")
	for team: TerrainArmy in removed:
		if not team.projectiles.is_empty(): return SiteRuntime.fail("REGION_FLIGHT_DEPENDENCY")
		child.combat_movement_coordinator.unregister_formation(team)
		team.clear()
	var original := child.capture_region_owner_state(context)
	if not original.ok: return original
	var old_refs := child._region_owner_references()
	child._region_reference_objects(old_refs)
	var old_graph := RegionOwnerSnapshot.prepare_restore(original.state, old_refs, context)
	if not old_graph.ok: return old_graph
	var old: Dictionary = old_graph.roots
	# Reuse the original core binding/clear/restore APIs in this private child.
	# It has no complete owner receipt until the surviving graph is rehydrated.
	var token := "region_projection_" + Crypto.new().generate_random_bytes(16).hex_encode()
	child._region_owner_bind_tickets[token] = {"kind": "projection", "data": target, "body_hash": RegionCheckpoint.state_hash(target.site),
		"context": context, "owners": {}}
	child.bind_terrain(target, {"ok": true, "crowd_site": null, "region_bind_token": token})
	child._region_owner_bind_tickets.erase(token)
	if child.terrain != target: return SiteRuntime.fail("REGION_CHILD_PROJECTION_FAILED")
	# The core skeleton carries no old deferred queue until the full merge.
	var baseline_context := context.duplicate(true)
	baseline_context.purpose = "region_materialize"
	baseline_context.action_seconds = child.fire_action_cursor
	baseline_context.effects_complete = true
	baseline_context.events = []
	baseline_context.endpoint_payload = {}
	var baseline_capture := child.capture_region_owner_state(baseline_context)
	if not baseline_capture.ok: return baseline_capture
	var fresh_refs := child._region_owner_references()
	child._region_reference_objects(fresh_refs)
	var baseline := RegionOwnerSnapshot.prepare_restore(baseline_capture.state, fresh_refs, baseline_context)
	if not baseline.ok: return baseline
	var merged: Dictionary = baseline.roots
	for field: String in ["lab", "controller", "actions", "work", "escort", "duty", "fatigue_work", "fire_meta"]:
		merged[field] = old[field]
	if int(child.terrain.site.get("controlled_person_id", 0)) != controlled_before:
		merged.controller._family_wait = false
	for key: String in merged.army_hot:
		if old.army_hot.has(key):
			merged.army_hot[key] = old.army_hot[key]
			merged.plans[key] = old.plans[key]
	for key: String in merged.actor_hot:
		if old.actor_hot.has(key): merged.actor_hot[key] = old.actor_hot[key]
	for key: String in old.deliveries:
		if not target.site.get("team_supply", {}).has(key) or target.site.team_supply[key].get("delivery", {}).is_empty(): return SiteRuntime.fail("REGION_DELIVERY_DEPENDENCY")
		merged.deliveries[key] = old.deliveries[key]
	var maximum_runtime := int(old.coordinator.get("_next_formation_runtime_id", 1))
	for key: String in merged.plans:
		if old.plans.has(key): continue
		merged.plans[key].runtime_id = maximum_runtime
		maximum_runtime += 1
	if not old.coordinator.is_empty():
		var movement := _region_merge_projected_movement(old, merged, retained_people)
		if not movement.ok: return movement
		merged.coordinator = movement.coordinator
		merged.coordinator._next_formation_runtime_id = maximum_runtime
		merged.registry = movement.registry
	# Every surviving original script object keeps its original captured values.
	# Added teams retain only descriptors from their original restored core.
	for key: String in old.reference_objects:
		var parts := key.split(":")
		if parts[0] == "team" and (parts.size() < 2 or not retained_teams.has(int(parts[1]))): continue
		merged.reference_objects[key] = old.reference_objects[key]
	var refs := old_refs.duplicate()
	for key: String in fresh_refs:
		if not refs.has(key): refs[key] = fresh_refs[key]
	var wire := RegionOwnerSnapshot.capture(merged, refs, context)
	if not wire.ok: return wire
	var owner_states := {"scene": wire.state}
	if original.owner_states.has("fire_boundary_receipt"):
		owner_states["fire_boundary_receipt"] = original.owner_states.fire_boundary_receipt
	var prepared := child.prepare_restore_region_owner_state(owner_states, context)
	if not prepared.ok: return prepared
	var restored := child.publish_restore_region_owner_state(prepared)
	if not restored.ok: return restored
	child._region_bound_data = target
	child._region_bind_receipt_value = {"ok": true, "complete": true, "owners_restored": true, "owner": str(target.site.id),
		"effects_complete": bool(context.effects_complete), "zero_world_only": not bool(context.effects_complete),
		"mode": "cold_exact", "backend": "gd", "consumer": "original_replay", "session": str(OS.get_process_id()) + ":" + str(child.get_instance_id()),
		"parts": ["actors", "armies", "movement", "items", "supply", "controller", "fire_transport", "fire_owners", "region_owners"]}
	child.set_process(false)
	for actor: TerrainTestCharacter in child.combat_actors: actor.set_process(false)
	for team: TerrainArmy in child.combat_armies: team.set_process(false)
	return SiteRuntime.ok("", {"data": target})

## Keep the old accepted work and movement while adding the core binder's
## new formations. A shared-cell conflict rejects this disposable child.
static func _region_merge_projected_movement(old: Dictionary, fresh: Dictionary, people: Dictionary) -> Dictionary:
	var coordinator: Dictionary = old.coordinator.duplicate()
	for field: String in ["_current_occupancy", "_retained_occupancy", "grid_committed_occupancy"]:
		var cells: Dictionary = {}
		for cell: Vector2i in old.coordinator[field]:
			var identity := int(old.coordinator[field][cell])
			if people.has(identity): cells[cell] = identity
		for cell: Vector2i in fresh.coordinator[field]:
			var identity := int(fresh.coordinator[field][cell])
			if old.coordinator._member_lookup.has(identity): continue
			if cells.has(cell) and int(cells[cell]) != identity: return SiteRuntime.fail("REGION_OCCUPANCY_CONFLICT")
			cells[cell] = identity
		coordinator[field] = cells
	coordinator._member_lookup = old.coordinator._member_lookup.duplicate()
	for identity: int in coordinator._member_lookup.keys():
		if not people.has(identity): coordinator._member_lookup.erase(identity)
	for identity: int in fresh.coordinator._member_lookup:
		if not coordinator._member_lookup.has(identity): coordinator._member_lookup[identity] = fresh.coordinator._member_lookup[identity]
	var registry: Dictionary = old.registry.duplicate()
	registry.formation_slots = old.registry.formation_slots.duplicate()
	registry.leases = old.registry.leases.duplicate()
	registry.next_token = maxi(int(old.registry.next_token), int(fresh.registry.next_token))
	var leased := {}
	for row: Array in registry.leases: leased[row[0]] = row[1]
	for team_id: int in fresh.registry.formation_slots:
		if old.plans.has(str(team_id)): continue
		if registry.formation_slots.has(team_id): return SiteRuntime.fail("REGION_LEASE_CONFLICT")
		registry.formation_slots[team_id] = fresh.registry.formation_slots[team_id]
	for row: Array in fresh.registry.leases:
		if not row[1].is_empty() and old.plans.has(str(int(row[1][0]))): continue
		if leased.has(row[0]):
			if not row[1].is_empty() and leased[row[0]] != row[1]: return SiteRuntime.fail("REGION_LEASE_CONFLICT")
			continue
		registry.leases.append(row)
		leased[row[0]] = row[1]
	return SiteRuntime.ok("", {"coordinator": coordinator, "registry": registry})

func _region_finish_cold_replay(target_game_seconds: float) -> Dictionary:
	var parent: TerrainLab = get_parent() as TerrainLab
	var slot: RegionSaveSlot = site_controller.region_slot if site_controller != null else null
	if slot == null and parent != null and parent.site_controller != null: slot = parent.site_controller.region_slot
	if not restore_only or terrain == null or terrain != _region_bound_data or _replay_target != target_game_seconds \
		or absf(SiteRuntime.now(terrain) * 60.0 - target_game_seconds) > ACTION_TIME_EPSILON \
		or _region_point_consuming or not _region_point_pending.is_empty(): return SiteRuntime.fail("REGION_REPLAY_PENDING")
	var settled := RegionSaveSlot.validate_settlement(terrain.site, target_game_seconds)
	if not settled.ok or settled.legacy or float(settled.pending) > ACTION_TIME_EPSILON: return SiteRuntime.fail("REGION_REPLAY_PENDING")
	var context: Dictionary
	var fire: Dictionary = terrain.site.get("fire_settlement", {})
	if slot != null:
		if absf(float(slot.control.logical_game_seconds) - target_game_seconds) > ACTION_TIME_EPSILON: return SiteRuntime.fail("REGION_REPLAY_PENDING")
		var registry: Dictionary = slot.region_registry()
		context = {"purpose": "region_checkpoint", "mode": "cold_exact", "source_generation": int(slot._marker.get("generation", 0)),
			"runtime_revision": int(registry.revision), "token": "region_replay_" + Crypto.new().generate_random_bytes(16).hex_encode(),
			"game_seconds": target_game_seconds, "action_seconds": fire_action_cursor, "fire_epoch": str(fire.get("epoch", slot.control.fire_clock.epoch)),
			"fire_sequence": int(fire.get("sequence", 0)), "interval_complete": true, "effects_complete": true,
			"mode_revision": int(registry.modes.get(str(terrain.site.id), {}).get("revision", 0)), "backend": "gd", "events": [], "endpoint_payload": {}}
	else:
		# SAME original Store snapshot was validated before the original full graph
		# bind. Work has since changed its body hash; the existing restore receipt
		# retains that verified context without creating another source authority.
		var bound := region_bind_receipt(terrain)
		var snapshot: Variant = terrain.site.get("region_snapshot")
		if not bound.ok or bound.get("mode") != "cold_exact" or bound.get("backend") != "gd" \
			or not snapshot is Dictionary or snapshot.size() != 4 or not RegionCheckpoint.integer(snapshot.get("version"), 1) or int(snapshot.version) != 1 \
			or not snapshot.get("state_hash") is String or not RegionCheckpoint.valid_wire(snapshot.get("owners")) or _region_owner_restore_receipt.get("owners_restored") != true \
			or _region_owner_restore_receipt.get("effects_complete") != true: return SiteRuntime.fail("NO_REGION_SLOT")
		var checked := RegionCheckpoint.validate_context(snapshot.get("context"))
		if not checked.ok: return checked
		for field: String in RegionCheckpoint.FIELDS:
			if checked.context[field] != _region_owner_restore_receipt.get(field): return SiteRuntime.fail("STALE_REGION_CONTEXT", field)
		context = checked.context.duplicate(true)
		# Source generations/revisions remain the original selected values. Only
		# the original completed shared endpoint publishes new clock evidence.
		context.merge({"purpose": "region_checkpoint", "mode": "cold_exact", "token": "region_replay_" + Crypto.new().generate_random_bytes(16).hex_encode(),
			"game_seconds": target_game_seconds, "action_seconds": fire_action_cursor, "fire_epoch": str(fire.get("epoch", checked.context.fire_epoch)),
			"fire_sequence": int(fire.get("sequence", checked.context.fire_sequence)), "interval_complete": true, "effects_complete": true,
			"events": [], "endpoint_payload": {}}, true)
	site_controller._capture_positions()
	var actual := capture_region_owner_state(context)
	if not actual.ok: return actual
	var payload := SiteStore.capture_region_snapshot(terrain, context, actual.owner_states)
	if not payload.ok: return payload
	var candidate := _region_detached_bind_data(terrain)
	candidate.site = payload.state
	return SiteRuntime.ok("", {"data": candidate, "context": context})

func _next_army_person_id_for(source_data: TerrainData, source_actors: Array, source_teams: Array) -> int:
	var next_person := int(source_data.site.get("next_person_id", 1))
	for actor: TerrainTestCharacter in source_actors: next_person = maxi(next_person, actor.person_id + 1)
	for team: TerrainArmy in source_teams:
		for unit: Dictionary in team.combat_units: next_person = maxi(next_person, int(unit.person_id) + 1)
	for record: Dictionary in source_data.site.get("item_records", {}).values(): next_person = maxi(next_person, int(record.original_owner) + 1)
	for container: Dictionary in source_data.site.get("ground_loot", {}).values(): next_person = maxi(next_person, int(container.original_owner) + 1)
	for relation: Dictionary in source_data.site.get("captivity", {}).values(): next_person = maxi(next_person, maxi(int(relation.captor_id), int(relation.guard_id)) + 1)
	return next_person

func _allocate_army_person_ids_for(count: int, source_data: TerrainData, source_actors: Array, source_teams: Array) -> Array[int]:
	var next_person := _next_army_person_id_for(source_data, source_actors, source_teams)
	if next_person <= TerrainArmy.PLAYER_MEMBER and next_person + count >= TerrainArmy.PLAYER_MEMBER: next_person = TerrainArmy.PLAYER_MEMBER + 1
	var result: Array[int] = []
	if count < 0 or next_person + count > 2147483647: return result
	for offset: int in count: result.append(next_person + offset)
	source_data.site["next_person_id"] = next_person + count
	return result

func _initial_artisan_birth_dispose(staging: Node, result: Dictionary) -> Dictionary:
	staging.free() # Temporary ORIGINAL Actor/Army owners, never published twice.
	return result

func _initial_artisan_birth_ground(data: TerrainData, start: Vector2i) -> Array[Vector2i]:
	# The original directed walk graph; no obstacle edits/navigation owner.
	var result: Array[Vector2i] = []
	if not data.is_walkable(start): return result
	var seen := {start: true}
	var pending: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < pending.size():
		var cell := pending[cursor]
		cursor += 1
		result.append(cell)
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if seen.has(next) or not data.contains(next) or not data.can_step(cell, next): continue
			seen[next] = true
			pending.append(next)
	return result

func _initial_artisan_birth_positions(ground: Array[Vector2i], count: int, faction: int, prior: Array[Dictionary]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in ground:
		var available := true
		for source: Dictionary in prior:
			var other: Vector2i = source.cell
			var distance := absi(cell.x - other.x) + absi(cell.y - other.y)
			# Original fatigue/engagement witness scans up to eight cells. A
			# hostile birth must not start inside that range or over an Actor.
			if distance == 0 or int(source.faction_id) != faction and distance <= 8: available = false; break
		if not available: continue
		result.append(cell)
		if result.size() == count: return result
	result.clear() # No partial deployment/fallback faction or terrain changes.
	return result

## Query/preparation only. ORIGINAL create_new + original Slot first-generation
## guard is REQUIRED for publication. Calling this method cannot commit a world.
## It uses disposable genuine original body owners, then original bind restores
## the SAME born people from their validated cold records into the _ready teams.

func prepare_initial_artisan_birth(new_data: TerrainData, scenario_id: String, admitted_categories: Array) -> Dictionary:
	if new_data == null or new_data.site.is_empty(): return SiteRuntime.fail("NO_TARGET")
	if scenario_id.is_empty(): return SiteRuntime.ok("原開局未指定工匠情境", {"data": new_data, "changed": false})
	var config := TechnologyArtisans.scenario_config(scenario_id)
	if config.is_empty(): return SiteRuntime.fail("UNKNOWN_OR_CHANGED_SCENARIO")
	if new_data.site.has("technology_artisans"):
		return SiteRuntime.ok("原出生已記錄，不補發", {"data": new_data, "changed": false}) if TechnologyArtisans.validate_receipt(new_data.site.technology_artisans, new_data.site) else SiteRuntime.fail("INVALID_ARTISAN_RECEIPT")
	var pin: Variant = new_data.site.get("world_pin")
	if not pin is Dictionary or not SiteStore._integer(pin.get("format"), 2, 2): return SiteRuntime.fail("NOT_NEW_WORLD_FORMAT")
	var policy := TechnologyPolicy.candidate(pin)
	if not policy.ok: return policy
	var admitted := TechnologyPolicy.new_policy(admitted_categories)
	if not admitted.ok: return admitted
	for category: String in policy.policy.categories:
		if not admitted.policy.categories.has(category): return SiteRuntime.fail("CATEGORY_NOT_ADMITTED")
	# Explicit original scenario population is independent of admitted skills.
	# An empty frozen policy still births the finite 5/15 original NPCs below;
	# the pure artisan helper grants nothing and writes no artisan receipt.
	# Fresh original scenario only, never retrofit an existing/runtime namespace.
	if not new_data.site.get("actors", {}) is Dictionary or not new_data.site.get("actors", {}).is_empty() \
		or not new_data.site.get("armies", []) is Array or not new_data.site.get("armies", []).is_empty() \
		or new_data.site.has("family") or new_data.site.has("crowd") or not new_data.site.get("captivity", {}).is_empty() \
		or not new_data.site.get("vehicles", {}).is_empty() or not new_data.site.get("item_records", {}).is_empty() \
		or int(new_data.site.get("minute", -1)) != 0 or float(new_data.site.get("phase", -1.0)) != 0.0 \
		or bool(new_data.site.get("paused", false)) or float(new_data.site.get("combat_left", 0.0)) != 0.0:
		return SiteRuntime.fail("NOT_INITIAL_SCENARIO", "原已出生或已進行世界不補發人物／技藝")
	var start := new_data.cell_from_index(int(new_data.site.get("player_cell", new_data.index(new_data.spawn_cell))))
	var ground := _initial_artisan_birth_ground(new_data, start)
	if ground.is_empty(): return SiteRuntime.fail("NO_BIRTH_GROUND")
	var sources: Array[Dictionary] = []
	for assignment: Dictionary in config.assignments:
		var found := false
		for source: Dictionary in sources:
			if source.source_slot == assignment.source_slot: found = true
		if not found: sources.append({"source_slot": assignment.source_slot, "faction_id": assignment.faction_id})
	var prior: Array[Dictionary] = [{"cell": start, "faction_id": 0}]
	for source: Dictionary in sources:
		source["cells"] = _initial_artisan_birth_positions(ground, 5, int(source.faction_id), prior)
		if source.cells.size() != 5: return SiteRuntime.fail("NO_BIRTH_GROUND", "原起點不足以合法安置本情境具名隊伍")
		for cell: Vector2i in source.cells: prior.append({"cell": cell, "faction_id": int(source.faction_id)})
	var candidate := SiteEnv.navigation_for_state(new_data, new_data.site.duplicate(true))
	candidate.site["actors"] = {}
	candidate.site["armies"] = []
	candidate.site["actor_presence_version"] = 1
	candidate.site["controlled_person_id"] = 1
	candidate.site["player_cell"] = candidate.index(start)
	var staging := Node2D.new()
	staging.name = "InitialArtisanBirthCandidate"
	staging.visible = false
	staging.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(staging)
	# Same ORIGINAL starter Actor type/identity as _ready, in a NEW namespace.
	# Capturing it avoids carrying old-world hp/faction/skills/personality/items.
	var starter := TerrainTestCharacter.new()
	starter.person_id = 1
	starter.data = candidate
	staging.add_child(starter)
	starter.set_process(false)
	starter.initialize_visual()
	if not starter.place(start, true): return _initial_artisan_birth_dispose(staging, SiteRuntime.fail("NO_BIRTH_GROUND"))
	var starter_state := starter.capture_state()
	# This newly born civilian has no military appointment. Choose lawful
	# starting clothes before the original owner creates any equipment.
	starter_state.appearance.parts.cape = "none"
	starter.restore_state(starter_state)
	var starter_items := SiteRuntime.seed_person_equipment(candidate, starter.item_state, starter.person_id, starter_state.appearance)
	if not starter_items.ok: return _initial_artisan_birth_dispose(staging, starter_items)
	candidate.site.actors["player"] = starter.capture_state()
	var born_teams: Array[TerrainArmy] = []
	var selected: Array = []
	for source: Dictionary in sources:
		var team := TerrainArmy.new()
		team.name = str(source.source_slot)
		team.team_id = born_teams.size() + 1
		team.faction_id = int(source.faction_id)
		team.roster_size = 5 # Original commander row 0, four explicit NPC slots.
		team.exchange_enabled = exchange_enabled
		team.person_id_allocator = _allocate_army_person_ids_for.bind(candidate, [starter], born_teams)
		staging.add_child(team)
		team.set_process(false)
		born_teams.append(team)
		var positions: Array[Vector2i] = []
		positions.assign(source.cells)
		if not team.deploy_at(candidate, starter, null, positions) or not team.enable_combat(false): return _initial_artisan_birth_dispose(staging, SiteRuntime.fail("BIRTH_DEPLOY_FAILED"))
		for index: int in team.combat_units.size():
			var body: Dictionary = team.combat_units[index]
			body.cargo = {}
			body.item_state = {}
			var initial_items := SiteRuntime.seed_person_equipment(candidate, body.item_state, team.combat_identity(index), body.appearance)
			if not initial_items.ok: return _initial_artisan_birth_dispose(staging, initial_items)
		for assignment: Dictionary in config.assignments:
			if assignment.source_slot == source.source_slot:
				selected.append({"slot_id": assignment.slot_id, "owner": team, "unit_index": assignment.unit_index, "person_id": team.combat_identity(int(assignment.unit_index))})
		candidate.site.armies.append(team.capture_combat_state())
	candidate.site["army_next_team"] = born_teams.size() + 1
	var selection := {"version": 1, "context": "initial_scenario_birth", "world_id": str(pin.get("world_instance_id", "")),
		"site_id": str(candidate.site.id), "scenario_id": scenario_id, "sources": selected}
	var seeded := TechnologyArtisans.prepare(candidate.site, config, admitted_categories, selection)
	if not seeded.ok: return _initial_artisan_birth_dispose(staging, seeded)
	candidate.site = seeded.state
	var actors_checked := SiteStore._validate_actors(candidate, candidate.site)
	if not actors_checked.ok: return _initial_artisan_birth_dispose(staging, actors_checked)
	var allocator_checked := SiteStore._validate_person_allocator(candidate.site)
	if not allocator_checked.ok: return _initial_artisan_birth_dispose(staging, allocator_checked)
	var armies_checked := SiteStore._validate_armies(candidate, candidate.site, true)
	if not armies_checked.ok: return _initial_artisan_birth_dispose(staging, armies_checked)
	var items_checked := SiteStore._validate_items(candidate, candidate.site)
	if not items_checked.ok: return _initial_artisan_birth_dispose(staging, items_checked)
	var cape_checked := SiteStore._validate_cape_roles(candidate.site)
	if not cape_checked.ok: return _initial_artisan_birth_dispose(staging, cape_checked)
	for roster: Dictionary in candidate.site.armies:
		if not TerrainArmy.valid_combat_state(roster, candidate, {}, candidate.site): return _initial_artisan_birth_dispose(staging, SiteRuntime.fail("INVALID_BIRTH_ROSTER"))
	return _initial_artisan_birth_dispose(staging, SiteRuntime.ok("有限原情境人物出生候選已備妥", {"data": candidate, "changed": true, "skills_changed": bool(seeded.changed), "scenario_id": scenario_id}))

# Merge into the original Lab. This is the captured roots.duty transient
# context around the original static consumer, never another policy owner.
var _region_duty_transient: Dictionary = {}
var _region_duty_depth := 0

func _region_duty_enter() -> Dictionary:
	_region_duty_depth += 1
	if _region_duty_depth > 1: return {"nested": true}
	var previous := _region_capture_duty_cache()
	if _region_duty_transient.is_empty():
		if restore_only:
			DutyAI.reset_site_state()
			_region_duty_transient = _region_capture_duty_cache()
		else:
			_region_duty_transient = previous.duplicate(true)
	_region_restore_duty_cache(_region_duty_transient)
	return {"nested": false, "previous": previous}

func _region_duty_leave(scope: Dictionary) -> void:
	assert(_region_duty_depth > 0)
	_region_duty_depth -= 1
	if bool(scope.get("nested", false)): return
	assert(_region_duty_depth == 0)
	_region_duty_transient = _region_capture_duty_cache()
	if restore_only: _region_restore_duty_cache(scope.previous)

func review_region_duty(game_time: float, registry: Dictionary) -> void:
	var scope := _region_duty_enter()
	DutyAI.review(self, game_time, registry)
	_region_duty_leave(scope)

## A source with live delivery/holder aliases is admitted only through its
## actual original producer and the currently selected canonical Store file.
func _region_verify_canonical_bind_source(data: TerrainData, slot: RegionSaveSlot, readback: TerrainData) -> Dictionary:
	var producer: Variant = data.get_meta(&"site_garrison_lab") if data.has_meta(&"site_garrison_lab") else null
	if producer is WeakRef: producer = producer.get_ref()
	if not producer is TerrainLab or not is_instance_valid(producer) or producer.terrain != data or producer.site_controller == null or producer.site_controller.region_slot != slot:
		return SiteRuntime.fail("REGION_SOURCE_PRODUCER_REQUIRED")
	if producer != self and slot._region_original_labs.get(str(data.site.id)) != producer:
		return SiteRuntime.fail("REGION_SOURCE_PRODUCER_REQUIRED")
	var saved := SiteStore.validate_region_snapshot(readback, {})
	if not saved.ok: return saved
	var context: Dictionary = saved.context.duplicate(true)
	var registry: Dictionary = slot.region_registry()
	context.source_generation = int(slot._marker.get("generation", 0))
	context.runtime_revision = int(registry.revision)
	context.mode_revision = int(registry.modes.get(str(data.site.id), {}).get("revision", 0))
	# capture_region_owner_state itself verifies every current original clock.
	# Only generation/revision advance across publishing the same frozen frame.
	var actual: Dictionary = producer.capture_region_owner_state(context)
	if not actual.ok: return actual
	var captured := SiteStore.capture_region_snapshot(data, context, actual.owner_states)
	if not captured.ok: return captured
	if RegionCheckpoint.state_hash(captured.state) != RegionCheckpoint.state_hash(readback.site): return SiteRuntime.fail("STALE_REGION_SOURCE_BODY")
	var reference_shape := func(key: String, kind: int) -> bool:
		return not key.is_empty() and kind in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_DICTIONARY, TYPE_ARRAY]
	var before := RegionOwnerSnapshot.validate_for_bind(saved.owners.scene, reference_shape, saved.context)
	if not before.ok: return before
	var current := RegionOwnerSnapshot.validate_for_bind(captured.owners.scene, reference_shape, context)
	if not current.ok: return current
	if RegionCheckpoint.state_hash({"roots": before.roots}) != RegionCheckpoint.state_hash({"roots": current.roots}):
		return SiteRuntime.fail("STALE_REGION_SOURCE_OWNERS")
	return SiteRuntime.ok("", {"body_hash": RegionCheckpoint.state_hash(readback.site), "canonical_data": readback,
		"producer": producer, "producer_data": data, "graph_hash": before.graph_hash})

const RegionPartyTravel = preload("res://scripts/region_lab/region_travel.gd")
const RegionPartyRuntime = preload("res://scripts/terrain_lab/site_region_party_runtime_mapping.gd")

const RegionPartyGrid = preload("res://scripts/region_lab/region_grid.gd")

const RegionPartyEnv = preload("res://scripts/terrain_lab/site_environment.gd")

var _region_party_token := ""

var _region_party_input_hash := ""

static func _region_party_hash(party: Dictionary) -> String:
	return Marshalls.raw_to_base64(var_to_bytes(party)).sha256_text()


func prepare_region_party_original_owner(token: String, party: Dictionary, slot: RegionSaveSlot = null) -> Dictionary:
	if slot == null and site_controller != null: slot = site_controller.region_slot
	if slot == null or token != str(party.get("party_id", "")) or not RegionPartyTravel.validate_identity(party.get("content", {}).get("travel_identity")):
		return SiteRuntime.fail("INVALID_PARTY_OWNER")
	if absf(float(party.get("upkeep", {}).get("at", -1.0)) - float(slot.control.logical_game_seconds)) > 0.00000001:
		return SiteRuntime.fail("UNSETTLED_PARTY")
	var selected_owner := _region_selected_party_owner(token, party, slot)
	if not selected_owner.ok or bool(selected_owner.get("handled", false)): return selected_owner
	var cached: Dictionary = slot.get_meta(&"region_party_owner_labs", {})
	var original: TerrainLab = cached.get(token)
	var fingerprint := _region_party_hash(party)
	if is_instance_valid(original) and original._region_party_input_hash == fingerprint:
		var receipt := original.region_bind_receipt(original.terrain)
		return {"ok": true, "lab": original, "receipt": receipt} if receipt.get("complete", false) else receipt
	var prefix := str(slot.pin.atlas_id) + ":"
	var origin := str(party.get("origin_site_id", ""))
	if not origin.begins_with(prefix): return SiteRuntime.fail("WRONG_SITE")
	var parts := origin.trim_prefix(prefix).split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return SiteRuntime.fail("WRONG_SITE")
	var coordinate := Vector2i(int(parts[0]), int(parts[1]))
	if RegionPartyGrid.site_id(str(slot.pin.atlas_id), coordinate) != origin: return SiteRuntime.fail("WRONG_SITE")
	var selected := slot.effective_site_path(coordinate)
	if not selected.ok: return selected
	# Borrow only original physical navigation. The authoritative party file
	# supplies its exact bodies, holders, supply and original stable references.
	var opened := slot._load_checked(str(selected.path), coordinate)
	if not opened.ok: return opened
	var content: Dictionary = party.content
	var view: Dictionary = opened.data.site.duplicate(true)
	# The old Site's complete graph belongs to its own original Lab. It cannot
	# describe this extracted party or authorize this ordinary original bind.
	for field: String in ["region_snapshot", "region_life_events", "fire_owners", "fire", "fire_settlement", "initial_scenario"]:
		view.erase(field)
	for field: String in ["features", "changes", "terrain_changes", "inventory", "water_status", "water_links", "building_economy", "housing", "captivity", "escort_orders"]:
		view[field] = {}
	view.zones = []
	view.notices = []
	view.total_produced = 0
	view.combat_left = 0.0
	for field: String in RegionPartyTravel.CONTENT_DICTS: view[field] = content.get(field, {}).duplicate(true)
	view.armies = content.get("armies", []).duplicate(true)
	view.id = "travel:" + token
	view.actor_presence_version = 1
	view.controlled_person_id = int(content.get("controlled_person_id", -1 if str(party.controller) == "npc" else party.leader_person_id))
	view.army_trial_active = not view.armies.is_empty()
	view.travel_identity = content.travel_identity.duplicate(true)
	view.organization_refs = content.get("organization_refs", SiteEquipmentOrders._portable_empty()).duplicate(true)
	view.housing = {}
	view.captivity = {}
	view.escort_orders = {}
	view.manual.cargo = content.get("manual_cargo", {}).duplicate(true) if view.actors.has("player") else {}
	view.worker.cargo = content.get("manual_cargo", {}).duplicate(true) if view.actors.has("npc") else {}
	view.manual.target = ""
	view.manual.progress = 0.0
	view.worker.target = ""
	view.worker.progress = 0.0
	view.worker_enabled = false
	view.paused = false
	view.erase("family")
	if content.has("family"):
		view.family = content.family.duplicate(true)
		for member: Dictionary in view.family.members:
			if str(member.site_id) not in [origin, view.id] or int(member.person_id) not in party.person_ids: continue
			var old := JSON.stringify([str(member.site_id), int(member.person_id)])
			var reference: Dictionary = view.travel_identity.get("family_members", {}).get(old, {})
			member.site_id = view.id
			member.path = ""
			view.travel_identity.family_members.erase(old)
			if not reference.is_empty(): view.travel_identity.family_members[JSON.stringify([member.site_id, int(member.person_id)])] = reference
	for field: String in ["next_person_id", "army_next_team", "next_vehicle", "next_item", "next_loot"]:
		view[field] = int(content.get("counters", {}).get(field, view.get(field, 1)))
	view.erase("fire_owners")
	view.erase("region_life_events")
	var transport: Dictionary = content.get("fire_template", {}).duplicate(true)
	if not transport.is_empty():
		if not transport.get("projectiles", []).is_empty() or not transport.get("reservations", []).is_empty():
			return SiteRuntime.fail("PARTY_ACTION_OPEN", "原出發不能遺失已接受射擊／彈體進度")
		transport.orders = content.get("fire_orders", []).duplicate(true)
		transport.member_cursor = content.get("fire_member_cursor", []).duplicate(true)
		view.fire_transport = transport
	else: view.erase("fire_transport")
	# Borrow derived physical navigation only. No resource/feature/body/work
	# owner from the historical origin is published or stepped by this graph.
	var data := RegionPartyEnv.navigation_for_state(opened.data, opened.data.site)
	data.site = view
	data.resource_base = {}
	data.resources_at = {}
	data.feature_at.fill(0)
	data.facility_cells.fill(0)
	for hook: StringName in [&"region_snapshot_capture", &"region_bind_receipt", &"site_garrison_lab", &"region_checkpoint_context",
		&"siege_event_guard", &"fire_event_guard", &"fire_owner_snapshot", &"fire_transport_snapshot", &"ship_journey_active",
		&"region_operation_pending", &"ship_vehicle_in_journey"]:
		if data.has_meta(hook): data.remove_meta(hook)
	data.set_meta(&"region_party_owner", {"token": token, "physical_source": origin, "party_hash": fingerprint})
	data.set_meta(&"region_party_physical_source", opened.data)
	data.set_meta(&"fire_completed_action_end", float(party.upkeep.get("owner_action_seconds", slot.control.fire_clock.action_seconds)))
	# A straddled hull is NEVER inserted into this physical Site. Its accepted
	# original route cursor is retained verbatim; death locations remain original
	# vehicle/local-position references, independent of a historical shore cell.
	data.set_meta(&"region_party_sea_cursor", party.get("upkeep", {}).get("sea_cursor", {}).duplicate(true))
	if str(party.get("mode", "land")) == "sea" and party.upkeep.has("sea_cursor"):
		var plan: Dictionary = slot.region_travel_plan() if str(slot.region_travel_journey().get("token", "")) == token else slot._region_npc_plan(token)
		if not plan.ok: return plan
		var projection: Dictionary = slot.region_sea_pose_projection(plan.plan, party)
		if not projection.ok: return projection
		data.set_meta(&"region_party_hull_poses", projection.poses)
		var frame_guard := SiteVehicleTransport.validate_region_ship_projection(data)
		if not frame_guard.ok: return frame_guard
	if not is_instance_valid(original):
		var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
		if scene == null: return SiteRuntime.fail("MISSING_ORIGINAL_SCENE")
		original = scene.instantiate() as TerrainLab
		original.restore_only = true
		original.visible = false
		original.pause_when_unfocused = false
		original.process_mode = Node.PROCESS_MODE_DISABLED
		if view.actors.has("npc"): original.npc = TerrainTestNPC.new()
		add_child(original)
		original.site_controller.region_slot = slot
		original.site_controller._auto_save_blocked = true
	# bind_terrain is the original body/link/ship/item/supply/controller restore;
	# this domain view is not passed to SiteStore or published as a fake Site.
	original.bind_terrain(data)
	var bound := original.region_bind_receipt(data)
	if not bound.get("complete", false): return bound
	if RegionPartyTravel._body_records(data.site).keys().size() != party.person_ids.size(): return SiteRuntime.fail("PARTY_BODY_CLOSURE")
	for identity: Variant in party.person_ids:
		if original._original_person_target(int(identity)).is_empty(): return SiteRuntime.fail("PARTY_BODY_CLOSURE")
	original._region_party_token = token
	original._region_party_input_hash = fingerprint
	var pending: Dictionary = party.upkeep.get("original_deaths", {})
	for identity: String in pending: original.site_controller._pending_deaths[int(identity)] = float(pending[identity])
	cached[token] = original
	slot.set_meta(&"region_party_owner_labs", cached)
	original.site_controller.family_continuity.resolve_owner = func(reference: Dictionary) -> Dictionary:
		return _region_original_family_reference(slot, original, reference)
	original.site_controller.family_continuity.commit_control_transition = func(reference: Dictionary, source: Dictionary, family: Dictionary) -> Dictionary:
		if not slot.has_method("commit_region_party_family_control"): return SiteRuntime.fail("MISSING_FAMILY_TRANSITION")
		return slot.call("commit_region_party_family_control", token, reference, source, family)
	var activated := slot.acknowledge_region_original_party_bind(token, party, original, bound)
	if not activated.ok: return activated
	return {"ok": true, "lab": original, "receipt": bound}

# Call this on the actual restored party Lab before the common host prepares
# positive work. KO/Sustain boundaries are the original Travel candidate's
# GAME endpoints; get-up/down/grace are the original bodies' ACTION endpoints.


func _region_party_original_action_limit(maximum: float) -> float:
	var limit := maximum
	for remaining: Variant in site_controller._pending_deaths.values():
		if float(remaining) > ACTION_TIME_EPSILON: limit = minf(limit, float(remaining))
	for actor: TerrainTestCharacter in combat_actors:
		if not actor_present(actor): continue
		if actor._getting_up and actor.action_time > ACTION_TIME_EPSILON: limit = minf(limit, float(actor.action_time))
		if actor.stun_grace > ACTION_TIME_EPSILON: limit = minf(limit, float(actor.stun_grace))
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		for row: Dictionary in team.materialized_combat_rows():
			if str(row.get("pose", "")) == "get_up":
				var remaining := float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]) - float(row.get("age", 0.0))
				if remaining > ACTION_TIME_EPSILON: limit = minf(limit, remaining)
			if float(row.get("grace", 0.0)) > ACTION_TIME_EPSILON: limit = minf(limit, float(row.grace))
	return limit


func _region_gameplay_party_progress(token: String, before: Dictionary, after: Dictionary, interval: Dictionary) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null or absf(float(before.upkeep.at) - float(interval.game_begin)) > 0.00000001 \
			or absf(float(after.upkeep.at) - float(interval.game_end)) > 0.00000001:
		return SiteRuntime.fail("CLOCK_CONTRACT")
	var restored := prepare_region_party_original_owner(token, before, slot)
	if not restored.ok: return restored
	var original: TerrainLab = restored.lab
	if str(before.upkeep.get("live", {}).get("upkeep", "")) == "liveBody":
		return _region_advance_original_party_body(original, before, interval)
	var elapsed := float(interval.action_end) - float(interval.action_begin)
	if elapsed <= 0.0 or original._region_party_original_action_limit(elapsed) < elapsed - ACTION_TIME_EPSILON:
		return SiteRuntime.fail("REGION_UNCLIPPED_ENDPOINT")
	# All traveling bodies were accepted idle by the original departure guard.
	# Keep original tactical orders intact. The original query reports their
	# assigned transit role as busy, preventing a second rescue/work assignment.
	for team: TerrainArmy in original.combat_armies:
		if not team.combat_enabled: continue
		if team.combat_order != TerrainArmy.CombatOrder.HOLD or not team._unit_rescues.is_empty(): return SiteRuntime.fail("PARTY_ACTION_OPEN")
		var busy: Callable = team.person_busy_query
		team.person_busy_query = func(_person: int) -> bool: return true
		team.prepare_combat(elapsed, 0.0)
		team.person_busy_query = busy
	for actor: TerrainTestCharacter in original.combat_actors:
		if original.actor_present(actor): actor.advance_combat(elapsed, true, 0.0)
	# Advance the ORIGINAL timer only. Original remains/contact/Family effects
	# occur after the unique accepted world record, behind P0 ordering.
	if not original.site_controller.has_method("advance_person_death_timers"):
		return SiteRuntime.fail("MISSING_REGION_DEATH_PROGRESS")
	original.site_controller.advance_person_death_timers(elapsed)
	var upkeep: Dictionary = _region_publish_original_party_upkeep(original, after)
	if not upkeep.ok: return upkeep
	var captured: Dictionary
	if str(before.upkeep.get("live", {}).get("upkeep", "")) == "mapBody":
		if original._region_map_motion_proposal.is_empty(): return SiteRuntime.fail("MISSING_REGION_MAP_MOTION")
		captured = original.publish_region_party_map_motion(after, original._region_map_motion_proposal, float(interval.game_end), float(interval.action_end))
	else: captured = _region_capture_original_party(original, after, slot, float(interval.game_end), float(interval.action_end))
	if not captured.ok: return captured
	var result := after.duplicate(true)
	result.content = captured.party.content
	result.upkeep.original_deaths = captured.party.upkeep.original_deaths
	result.upkeep.owner_action_seconds = float(interval.action_end)
	if str(before.upkeep.get("live", {}).get("upkeep", "")) == "mapBody": result.upkeep.live = captured.party.upkeep.live
	# The accepted actual capture retains the same original runtime graph.
	original._region_party_input_hash = _region_party_hash(result)
	var meta: Dictionary = original.terrain.get_meta(&"region_party_owner", {})
	meta.party_hash = original._region_party_input_hash
	original.terrain.set_meta(&"region_party_owner", meta)
	return {"ok": true, "party": result, "complete": true, "token": token,
		"game_seconds": float(interval.game_end), "action_seconds": float(interval.action_end)}


func _region_capture_original_party(original: TerrainLab, party: Dictionary, slot: RegionSaveSlot,
		game_seconds: float = -1.0, action_seconds: float = -1.0) -> Dictionary:
	original.site_controller._capture_positions()
	var result := party.duplicate(true)
	var content: Dictionary = result.content
	for field: String in RegionPartyTravel.CONTENT_DICTS: content[field] = original.terrain.site.get(field, {}).duplicate(true)
	content.armies = original.terrain.site.armies.duplicate(true)
	content.controlled_person_id = int(original.terrain.site.controlled_person_id) if str(party.controller) == "player" else -1
	content.manual_cargo = original.terrain.site.manual.cargo.duplicate(true) if content.actors.has("player") else original.terrain.site.worker.cargo.duplicate(true)
	if party.content.has("family"): content.family = original.terrain.site.family.duplicate(true)
	content.travel_identity = original.terrain.site.travel_identity.duplicate(true)
	for field: String in ["next_person_id", "army_next_team", "next_vehicle", "next_item", "next_loot"]: content.counters[field] = int(original.terrain.site.get(field, content.counters.get(field, 1)))
	var identified := RegionPartyTravel.prepare_identity(content)
	if not identified.ok: return identified
	content.travel_identity = identified.state.travel_identity
	RegionPartyTravel._retain_identity(content)
	if RegionPartyTravel.census(result).people != RegionPartyTravel.census(party).people: return SiteRuntime.fail("PARTY_BODY_CLOSURE")
	result.upkeep.original_deaths = {}
	for identity: int in original.site_controller._pending_deaths: result.upkeep.original_deaths[str(identity)] = float(original.site_controller._pending_deaths[identity])
	result.upkeep.at = float(slot.control.logical_game_seconds) if game_seconds < 0.0 else game_seconds
	result.upkeep.owner_action_seconds = float(slot.control.fire_clock.action_seconds) if action_seconds < 0.0 else action_seconds
	if not result.upkeep.get("live", {}).is_empty():
		var refreshed := _region_refresh_original_live_frame(result, original, slot, float(result.upkeep.at), float(result.upkeep.owner_action_seconds))
		if not refreshed.ok: return refreshed
		result = refreshed.party
	original._region_party_input_hash = _region_party_hash(result)
	var meta: Dictionary = original.terrain.get_meta(&"region_party_owner", {})
	meta.party_hash = original._region_party_input_hash
	original.terrain.set_meta(&"region_party_owner", meta)
	return {"ok": true, "party": result}


func _region_gameplay_party_endpoint(token: String, party: Dictionary, event: Dictionary) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	var payload: Dictionary = event.get("payload", {}).get("event", event.get("payload", {}))
	var accepted: Dictionary = {}
	for record: Dictionary in party.upkeep.events:
		if int(record.sequence) == int(payload.get("sequence", -1)): accepted = record
	if accepted.is_empty() or str(accepted.kind) != str(payload.get("kind", "")) or int(accepted.person_id) != int(payload.get("person_id", -1)):
		return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
	var restored := prepare_region_party_original_owner(token, party, slot)
	if not restored.ok: return restored
	var original: TerrainLab = restored.lab
	var target := original._original_person_target(int(accepted.person_id))
	if target.is_empty(): return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
	var hp: float = float(target.owner.combat_hot_get(int(target.unit), &"hp")) if int(target.unit) >= 0 else float(target.owner.hp)
	if str(accepted.status) != "complete":
		if hp <= 0.0 or str(accepted.kind) == "supply_damage" and absf(hp - float(accepted.old_hp)) > 0.0000001: return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
		original._region_point_consuming = true
		match str(accepted.kind):
			"supply_damage":
				var ending: float = original.site_controller._apply_supply_damage(int(accepted.person_id), float(accepted.loss))
				if absf(ending - float(accepted.ending_hp)) > 0.0000001:
					original._region_point_consuming = false
					return original.site_controller.latch_original_step_fault(SiteRuntime.fail("REGION_LIFE_CONTRACT"))
			"wake":
				if int(target.unit) >= 0: target.owner._wake_unit(int(target.unit))
				else: target.owner._wake_up()
			_: original._region_point_consuming = false; return SiteRuntime.fail("INVALID_REGION_LIFE_EVENTS")
		original._region_point_consuming = false
		for team: TerrainArmy in original.combat_armies:
			if team.combat_enabled: team.settle_combat_command()
		for effect: Dictionary in original.site_controller.person_actions.settle_after_contacts():
			original.site_controller.collect_ground_boundary_result(effect)
		original.site_controller.settle_person_deaths(0.0)
	var captured := _region_capture_original_party(original, party, slot)
	if not captured.ok: return captured
	for record: Dictionary in captured.party.upkeep.events:
		if int(record.sequence) == int(accepted.sequence): record.status = "complete"
	var controlled_death := bool(accepted.get("controlled", false)) and bool(accepted.get("death", false))
	var continuity_complete := not controlled_death
	if controlled_death:
		# Original death work must settle before the original Family UI opens.
		# The immutable death event stays queued while a genuine heir/failure
		# decision is pending; saving cannot fabricate completion.
		original.site_controller.check_family_death()
		var current := original._original_person_target(original.controlled_person_id())
		continuity_complete = not current.is_empty() and float(current.hp) > 0.0
	return {"ok": true, "party": captured.party, "receipt": {"token": token,
		"game_seconds": float(slot.control.logical_game_seconds), "action_seconds": float(slot.control.fire_clock.action_seconds),
		"effects_complete": true, "continuity_complete": continuity_complete, "complete": continuity_complete}}


func _region_original_family_reference(slot: RegionSaveSlot, original: TerrainLab, reference: Dictionary) -> Dictionary:
	if str(reference.get("site_id", "")) == "travel:" + original._region_party_token:
		var person: Dictionary = original.site_controller.family_continuity._current_person(int(reference.person_id))
		return SiteRuntime.ok("", {"local": true, "person": person, "lab": original}) if not person.is_empty() else SiteRuntime.fail("NO_PERSON")
	# This is a explicitly registered family reference. The original selected
	# Site/party owner must catch up and prove its full bind at the current epoch.
	if slot.has_method("resolve_region_family_owner"): return slot.call("resolve_region_family_owner", reference)
	return SiteRuntime.fail("MISSING_FAMILY_OWNER", "跨Site原家人須原共同控制交易，不讀歷史ID冒充當前身體")

# Add these assignments to the ORIGINAL _wire_region_gameplay_adapters:
# slot.region_original_party_endpoint = Callable(self,"_region_gameplay_party_endpoint")
# slot.region_original_endpoint_checkpoint = Callable(self,"_region_gameplay_endpoint_checkpoint")
# slot.region_original_player_materialize = Callable(self,"_region_gameplay_player_materialize")
# slot.region_contact_active_data = Callable(self,"_region_gameplay_contact_active_data")


func prepare_fresh_initial_population(new_data: TerrainData) -> Dictionary:
	if new_data == null or new_data.site.is_empty(): return SiteRuntime.fail("NO_TARGET")
	var pin: Variant = new_data.site.get("world_pin")
	if not pin is Dictionary or int(pin.get("format", 0)) != 2: return SiteRuntime.fail("NOT_NEW_WORLD_FORMAT")
	var policy := TechnologyPolicy.candidate(pin)
	if not policy.ok: return policy
	if not policy.policy.categories.is_empty(): return SiteRuntime.fail("TECH_POLICY_CONFLICT")
	if not new_data.site.get("actors", {}).is_empty() or not new_data.site.get("armies", []).is_empty() or new_data.site.has("family") or new_data.site.has("crowd") or new_data.site.has("initial_scenario") or not new_data.site.get("captivity", {}).is_empty() or not new_data.site.get("vehicles", {}).is_empty() or not new_data.site.get("item_records", {}).is_empty() or int(new_data.site.get("minute", -1)) != 0 or float(new_data.site.get("phase", -1.0)) != 0.0 or bool(new_data.site.get("paused", false)) or float(new_data.site.get("combat_left", 0.0)) != 0.0: return SiteRuntime.fail("NOT_INITIAL_SCENARIO")
	var candidate := SiteEnv.navigation_for_state(new_data, new_data.site.duplicate(true))
	var start := candidate.cell_from_index(int(candidate.site.get("player_cell", candidate.index(candidate.spawn_cell))))
	if not candidate.is_walkable(start): return SiteRuntime.fail("NO_BIRTH_GROUND")
	var staging := Node2D.new()
	staging.name = "InitialWorldStarterCandidate"
	staging.visible = false
	staging.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(staging)
	var starter := TerrainTestCharacter.new()
	starter.person_id = 1
	starter.data = candidate
	staging.add_child(starter)
	starter.set_process(false)
	starter.initialize_visual()
	if not starter.place(start, true): return _initial_artisan_birth_dispose(staging, SiteRuntime.fail("NO_BIRTH_GROUND"))
	var snapshot := starter.capture_state()
	# This newly born civilian has no military appointment. Choose lawful
	# starting clothes before the original owner creates any equipment.
	snapshot.appearance.parts.cape = "none"
	starter.restore_state(snapshot)
	var equipped := SiteRuntime.seed_person_equipment(candidate, starter.item_state, 1, snapshot.appearance)
	if not equipped.ok: return _initial_artisan_birth_dispose(staging, equipped)
	candidate.site["actors"] = {"player": starter.capture_state()}
	candidate.site["armies"] = []
	candidate.site["actor_presence_version"] = 1
	candidate.site["controlled_person_id"] = 1
	candidate.site["next_person_id"] = maxi(2, int(candidate.site.get("next_person_id", 1)))
	candidate.site["army_next_team"] = maxi(1, int(candidate.site.get("army_next_team", 1)))
	for checked: Dictionary in [SiteStore._validate_actors(candidate, candidate.site), SiteStore._validate_person_allocator(candidate.site), SiteStore._validate_items(candidate, candidate.site), SiteStore._validate_cape_roles(candidate.site)]:
		if not checked.ok: return _initial_artisan_birth_dispose(staging, checked)
	return _initial_artisan_birth_dispose(staging, SiteRuntime.ok("", {"data": candidate, "changed": true}))



## Reopen an already-selected complete checkpoint. No candidate save or new marker.
func prepare_selected_region_owner_restore(data: TerrainData, slot: RegionSaveSlot) -> Dictionary:
	var duty := _region_capture_duty_cache()
	var result := _region_prepare_selected_owner_restore(data, slot)
	_region_restore_duty_cache(duty)
	return result

func _region_prepare_selected_owner_restore(data: TerrainData, slot: RegionSaveSlot) -> Dictionary:
	if data == null or slot == null or not data.site.has("region_snapshot") or data.site.has("crowd"):
		return SiteRuntime.fail("INVALID_SELECTED_REGION_RESTORE")
	var selected := _region_selected_bind_source(data, slot)
	if not selected.ok: return selected
	var proof: Dictionary = selected.proof
	var path := slot.folder.path_join(str(proof.path))
	var coordinate: Dictionary = slot._coordinate(data)
	if not coordinate.ok: return coordinate
	# Read this precise selected file; a completed replay is not selected reopen.
	var readback: Dictionary = slot._load_checked(path, coordinate.site)
	if not readback.ok: return readback
	var canonical: TerrainData = readback.data
	if not canonical.site.has("region_snapshot"): return SiteRuntime.fail("MISSING_SELECTED_REGION_OWNERS")
	if RegionCheckpoint.state_hash(canonical.site) != str(selected.body_hash): return SiteRuntime.fail("STALE_SELECTED_REGION_BODY")
	if not restore_only and str(slot.control.active_site_id) != str(canonical.site.id): return SiteRuntime.fail("REGION_BIND_WRONG_ACTIVE")
	var snapshot := SiteStore.validate_region_snapshot(canonical, {})
	if not snapshot.ok: return snapshot
	var created := _region_new_bind_child(canonical)
	if not created.ok: return created
	var child: TerrainLab = created.child
	var candidate := _region_detached_bind_data(canonical)
	var restored := _region_bootstrap_bind_child(child, candidate)
	if not restored.ok:
		child.free()
		return restored
	if RegionCheckpoint.state_hash(candidate.site) != RegionCheckpoint.state_hash(canonical.site):
		child.free()
		return SiteRuntime.fail("SELECTED_REGION_BIND_NORMALIZATION", "Original disposable bind changed the selected durable body; retain the selected marker")
	var graph := child.validate_region_owner_bind_payload(canonical, snapshot.owners, snapshot.context)
	child.free()
	if not graph.ok: return graph
	if slot.region_bind_proof(canonical) != proof or FileAccess.get_sha256(path) != str(proof.sha256): return SiteRuntime.fail("STALE_SELECTED_REGION_COMMIT")
	var token := "region_selected_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var clock: Dictionary = slot.control.fire_clock
	var ticket := {"kind": "selected", "data": canonical, "slot": slot, "proof": proof.duplicate(true),
		"saved_path": path, "saved_sha256": str(proof.sha256), "generation": int(proof.generation),
		"revision": int(slot.region_registry().revision), "game_seconds": float(slot.control.logical_game_seconds),
		"action_seconds": float(clock.action_seconds), "fire_epoch": str(clock.epoch), "fire_sequence": int(clock.sequence),
		"body_hash": RegionCheckpoint.state_hash(canonical.site), "graph_hash": graph.graph_hash,
		"context": snapshot.context, "owners": snapshot.owners}
	var checked := _region_check_selected_restore_ticket(ticket, canonical)
	if not checked.ok: return checked
	_region_owner_bind_tickets[token] = ticket
	return SiteRuntime.ok("", {"data": canonical, "region_bind_token": token, "crowd_site": null,
		"selected": true, "source_generation": int(proof.generation),
		"effects_complete": bool(snapshot.context.effects_complete), "zero_world_only": not bool(snapshot.context.effects_complete)})

func _region_check_selected_restore_ticket(ticket: Dictionary, data: TerrainData) -> Dictionary:
	var slot: RegionSaveSlot = ticket.slot
	if slot == null or ticket.get("data") != data or int(slot._marker.get("generation", 0)) != int(ticket.generation) \
		or int(slot.region_registry().revision) != int(ticket.revision): return SiteRuntime.fail("STALE_SELECTED_REGION_COMMIT")
	if slot.region_bind_proof(data) != ticket.proof or FileAccess.get_sha256(str(ticket.saved_path)) != str(ticket.saved_sha256):
		return SiteRuntime.fail("STALE_SELECTED_REGION_COMMIT")
	if not restore_only and str(slot.control.active_site_id) != str(data.site.id): return SiteRuntime.fail("REGION_BIND_WRONG_ACTIVE")
	var clock: Dictionary = slot.control.fire_clock
	if float(slot.control.logical_game_seconds) != float(ticket.game_seconds) or float(clock.action_seconds) != float(ticket.action_seconds) \
		or str(clock.epoch) != str(ticket.fire_epoch) or int(clock.sequence) != int(ticket.fire_sequence): return SiteRuntime.fail("STALE_SELECTED_REGION_CLOCK")
	if RegionCheckpoint.state_hash(data.site) != ticket.body_hash: return SiteRuntime.fail("STALE_SELECTED_REGION_BODY")
	var snapshot := SiteStore.validate_region_snapshot(data, {})
	if not snapshot.ok: return snapshot
	if RegionCheckpoint.state_hash({"owners": snapshot.owners}) != RegionCheckpoint.state_hash({"owners": ticket.owners}) \
		or RegionCheckpoint.state_hash({"context": snapshot.context}) != RegionCheckpoint.state_hash({"context": ticket.context}):
		return SiteRuntime.fail("STALE_SELECTED_REGION_GRAPH")
	var graph := validate_region_owner_bind_payload(data, ticket.owners, ticket.context)
	if not graph.ok or graph.graph_hash != ticket.graph_hash: return SiteRuntime.fail("STALE_SELECTED_REGION_GRAPH")
	return SiteRuntime.ok()

## Read-only original geometry admission before one joint Slot marker.
func _region_resolve_prepared_battle_people(battle: Dictionary, token: String) -> Dictionary:
	var checked := _region_check_bind_candidate(token)
	if not checked.ok: return checked
	var ticket: Dictionary = _region_owner_bind_tickets[token]
	var child: TerrainLab = ticket.child
	if not is_instance_valid(child) or child.get_parent() != self or child.terrain == null or str(child.terrain.site.id) != str(ticket.data.site.id):
		return SiteRuntime.fail("STALE_REGION_BIND_CHILD")
	var rules: Script = load("res://scripts/region_lab/region_gameplay_battle.gd")
	return rules.resolve_people(child, battle)
## The same original Lab coordinates travel. All Site and party original
## consumers finish one accepted dual-clock interval before Slot records it.
func _region_advance_original_travel_interval(request: Dictionary) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot if site_controller != null else null
	var live_body := bool(request.get("live_body", false))
	var party_host := terrain != null and terrain.has_meta(&"region_party_owner")
	if slot == null or terrain == null or not str(slot.control.active_site_id).is_empty() or not party_host and (not restore_only or slot._region_original_labs.get(str(terrain.site.id)) != self):
		return SiteRuntime.fail("INVALID_TRAVEL_HOST")
	var token := str(request.get("token", ""))
	var selected := slot.region_travel_party()
	if not selected.ok: return selected
	if token != str(slot.region_travel_journey().get("token", "")) or not is_same(request.get("party"), selected.party):
		return SiteRuntime.fail("STALE_PARTY_OWNER")
	if not request.get("scale") is float or (float(request.scale) != simulation_speed if live_body else float(request.scale) != RegionPartyTravel.STEP_SCALE) or not request.get("maximum_action_seconds") is float or not is_finite(float(request.maximum_action_seconds)) or float(request.maximum_action_seconds) <= 0.0 or float(request.maximum_action_seconds) > (EXCHANGE_ACTION_STEP if live_body else RegionPartyTravel.STEP_ACTION_SECONDS):
		return SiteRuntime.fail("INVALID_TRAVEL_INTERVAL")
	if not request.get("candidate") is Callable or not request.candidate.is_valid() or request.candidate.get_object() != slot or not request.get("party_progress") is Callable or not request.party_progress.is_valid() or request.party_progress != slot.region_original_party_progress:
		return SiteRuntime.fail("INVALID_TRAVEL_ADAPTER")
	if get_tree().paused or bool(terrain.site.get("paused", false)): return SiteRuntime.fail("PAUSED_WORLD")
	var before_data := terrain
	var due := slot.consume_due_region_events()
	if not due.ok: return due
	var down: Dictionary = slot._region_player_down_settlement() if live_body else {}
	var restricted: bool = live_body and due.get("restricted_settlement", false) == true and not down.is_empty() \
		and down.get("lab") == self and down.get("point_pending") == false
	if not due.get("complete", false) and not restricted: return {"ok": true, "pending": true, "source": due}
	if token != str(slot.region_travel_journey().get("token", "")) or not str(slot.control.active_site_id).is_empty():
		return {"ok": true, "pending": true, "handoff": true, "source": due}
	selected = slot.region_travel_party()
	if not selected.ok: return selected
	if live_body:
		var current: Dictionary = slot.region_original_party_runtime_proof(token, selected.party)
		if not current.ok: return current
		if current.lab != self or terrain != before_data:
			return {"ok": true, "pending": true, "handoff": true, "source": due}
	var bound := prepare_region_party_original_owner(token, selected.party, slot)
	if not bound.ok: return bound
	var party_original: TerrainLab = bound.lab
	if party_host and party_original != self: return SiteRuntime.fail("INVALID_TRAVEL_HOST")
	if live_body != (str(selected.party.upkeep.get("live", {}).get("upkeep", "")) == "liveBody"): return SiteRuntime.fail("REGION_PARTY_MODE")
	var maximum := party_original._region_party_original_action_limit(float(request.maximum_action_seconds))
	if restricted: maximum = minf(maximum, float(down.remaining_action_seconds))
	if maximum <= ACTION_TIME_EPSILON: return SiteRuntime.fail("REGION_ZERO_ENDPOINT_REQUIRED")
	simulation_speed = float(request.scale)
	var local_tactical := minf(maximum, float(party_original.terrain.site.get("combat_left", 0.0))) if live_body else 0.0
	if live_body and (party_original._fire_activity() or party_original._siege_tactical_active() or party_original._region_melee_tactical_demand()): local_tactical = maximum
	var joint := _prepare_region_main_interval(maximum, local_tactical, true)
	if not joint.get("ok", false): return joint
	if joint.get("pending", false): return {"ok": true, "pending": true, "source": joint}
	var originals: Array[TerrainLab] = []
	originals.assign(joint.originals)
	var interval: Dictionary = joint.interval
	var prepared: Dictionary = joint.prepared
	prepared.travel_host = self
	prepared.travel_party = party_original
	var mode: Dictionary = slot.region_registry().modes.get("travel:" + token, {})
	var player_permit: Dictionary = slot.GameplayClock.begin_permit(slot.region_registry(), "travel:" + token, str(mode.get("mode", "")), int(slot._marker.generation),
		float(interval.game_begin), float(interval.action_begin), str(mode.get("consumer", "")), slot._region_positive_player_death_ids())
	if not player_permit.ok: return _region_preflight_failure(originals, player_permit)
	prepared.permits["travel:" + token] = player_permit
	var outcome: Variant = slot._region_live_party_candidate(interval, selected.party) if live_body else request.candidate.call(interval)
	if not outcome is Dictionary or not outcome.get("ok", false):
		return _region_preflight_failure(originals, outcome if outcome is Dictionary else SiteRuntime.fail("INVALID_TRAVEL_CANDIDATE"))
	var accepted := float(interval.action_end) - float(interval.action_begin)
	if not outcome.get("action_seconds") is float or not is_finite(float(outcome.action_seconds)) or float(outcome.action_seconds) < 0.0 or float(outcome.action_seconds) > accepted + ACTION_TIME_EPSILON:
		return _region_preflight_failure(originals, SiteRuntime.fail("UNCLIPPED_TRAVEL_ENDPOINT"))
	if float(outcome.action_seconds) <= ACTION_TIME_EPSILON:
		_region_clear_shared_work_plans(originals)
		return {"ok": true, "pending": true, "outcome": outcome}
	if float(outcome.action_seconds) < accepted - ACTION_TIME_EPSILON:
		interval = slot.preview_region_interval(float(outcome.action_seconds), simulation_speed, minf(float(outcome.action_seconds), float(interval.tactical_seconds)))
		if not interval.get("ok", false) or interval.get("pending", false): return _region_preflight_failure(originals, interval)
		accepted = float(interval.action_end) - float(interval.action_begin)
		var game := float(interval.game_end) - float(interval.game_begin)
		for original: TerrainLab in originals:
			var retimed := original._retime_shared_work_step(accepted, game)
			if not retimed.ok: return _region_preflight_failure(originals, retimed)
		prepared = slot.prepare_region_gameplay_interval(interval)
		if not prepared.ok: return _region_preflight_failure(originals, prepared)
		prepared.travel_host = self
		prepared.travel_party = party_original
		prepared.permits["travel:" + token] = player_permit
		outcome = slot._region_live_party_candidate(interval, selected.party) if live_body else request.candidate.call(interval)
		if not outcome is Dictionary or not outcome.get("ok", false):
			return _region_preflight_failure(originals, outcome if outcome is Dictionary else SiteRuntime.fail("INVALID_TRAVEL_CANDIDATE"))
	if not outcome.get("party") is Dictionary or str(outcome.party.party_id) != token or absf(float(outcome.get("at", -1.0)) - float(interval.game_end)) > 0.00000001 or absf(float(outcome.action_seconds) - accepted) > ACTION_TIME_EPSILON:
		return _region_preflight_failure(originals, SiteRuntime.fail("TRAVEL_CLOCK_CONTRACT"))
	# The host is included among the true cold consumers. It is never ticked
	# separately, and the party original does not run Site work or Sustain again.
	party_original.simulation_speed = float(interval.scale)
	var party_guard := party_original._region_original_interval_guard(interval)
	if not party_guard.ok: return _region_preflight_failure(originals, party_guard)
	var progressed := slot.advance_prepared_region_formula_progress(prepared)
	if not progressed.ok: return site_controller.latch_original_step_fault(progressed)
	var body: Variant = request.party_progress.call(token, selected.party, outcome.party, interval)
	if not body is Dictionary or not body.get("ok", false) or not body.get("complete", false):
		return site_controller.latch_original_step_fault(body if body is Dictionary else SiteRuntime.fail("INCOMPLETE_PARTY_PROGRESS"))
	if body.get("token") != token or absf(float(body.get("game_seconds", -1.0)) - float(interval.game_end)) > 0.00000001 or absf(float(body.get("action_seconds", -1.0)) - float(interval.action_end)) > ACTION_TIME_EPSILON:
		return site_controller.latch_original_step_fault(SiteRuntime.fail("TRAVEL_CLOCK_CONTRACT"))
	outcome.party = body.party
	var recorded := slot.record_completed_region_travel_step(token, prepared, outcome)
	if not recorded.ok: return site_controller.latch_original_step_fault(recorded)
	var committed := slot.commit_region_gameplay_progress(prepared)
	if not committed.ok: return site_controller.latch_original_step_fault(committed)
	if live_body and not party_original._region_point_pending.is_empty():
		var point: Dictionary = party_original.consume_region_point()
		if not point.ok: return site_controller.latch_original_step_fault(point)
		var captured: Dictionary = _region_capture_original_party(party_original, outcome.party, slot)
		if not captured.ok: return site_controller.latch_original_step_fault(captured)
		outcome.party = captured.party
		slot._travel_party_runtime = captured.party
		slot._travel_party_runtime_token = token
	return SiteRuntime.ok("", {"complete": true, "interval": interval, "outcome": outcome})

## Original down/remains settlement for NPC parties follows P0, at zero time.
func _region_gameplay_party_zero_points() -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null: return SiteRuntime.fail("NO_REGION_SLOT")
	for token: String in slot.region_registry().parties:
		if str(slot.region_registry().parties[token].get("phase", "")) not in ["travelling", "pending_life"]: continue
		var selected := slot._region_npc_party(token)
		if not selected.ok: return selected
		var bound := prepare_region_party_original_owner(token, selected.party, slot)
		if not bound.ok: return bound
		var original: TerrainLab = bound.lab
		original.site_controller.settle_person_deaths(0.0)
		var captured := _region_capture_original_party(original, selected.party, slot)
		if not captured.ok: return captured
		slot._region_npc_party_runtime[token] = captured.party
	return SiteRuntime.ok("", {"complete": true})


## Cancel only this original Lab's uncommitted detached candidate.
func _region_discard_bind_candidate(token: String) -> Dictionary:
	var ticket: Dictionary = _region_owner_bind_tickets.get(token, {})
	if ticket.is_empty() or ticket.get("kind") != "prepared": return SiteRuntime.fail("REGION_BIND_NOT_CANCELLABLE")
	var slot: RegionSaveSlot = ticket.slot
	if slot == null or int(slot._marker.get("generation", 0)) != int(ticket.generation):
		return SiteRuntime.fail("REGION_BIND_COMMIT_SELECTED", "Retain any possibly committed original owner for selected-marker recovery")
	var child: TerrainLab = ticket.child
	if not is_instance_valid(child) or child.get_parent() != self: return SiteRuntime.fail("STALE_REGION_BIND_CHILD")
	child.free()
	_region_owner_bind_tickets.erase(token)
	return SiteRuntime.ok("", {"discarded": true})

## A same-time additive arrival may restore before existing point effects.
## Existing people and their owning team/body must remain exactly the captured
## originals. Removal or mutation at this fence needs its own original endpoint.
func _region_pending_projection_guard(child: TerrainLab, target: TerrainData, context: Dictionary) -> Dictionary:
	if child._region_point_consuming: return SiteRuntime.fail("REGION_EFFECT_RUNNING")
	if bool(context.get("effects_complete", true)):
		return SiteRuntime.ok() if child._region_point_pending.is_empty() else SiteRuntime.fail("REGION_EFFECTS_PENDING")
	if not child._region_point_pending.is_empty() and child._region_point_pending.get("interval_complete") != true:
		return SiteRuntime.fail("REGION_INTERVAL_INCOMPLETE")
	# Other owners' pending events do not imply local body effects.
	if child._region_point_pending.is_empty(): return SiteRuntime.ok()
	var previous := _region_projection_original_people(child.terrain.site)
	var arriving := _region_projection_original_people(target.site)
	if not previous.ok: return previous
	if not arriving.ok: return arriving
	for identity: int in previous.people:
		if not arriving.people.has(identity) or RegionCheckpoint.state_hash(previous.people[identity]) != RegionCheckpoint.state_hash(arriving.people[identity]):
			return SiteRuntime.fail("REGION_PENDING_BODY_CHANGED", "Additive arrival must retain every original pending body and owner")
	return SiteRuntime.ok()

static func _region_projection_original_people(state: Dictionary) -> Dictionary:
	var people := {}
	for key: String in state.get("actors", {}):
		var body: Dictionary = state.actors[key]
		var identity := int(body.get("person_id", 0))
		if identity <= 0 or people.has(identity): return SiteRuntime.fail("INVALID_REGION_PERSON")
		people[identity] = {"kind": "actor", "owner": key, "body": body}
	for team: Dictionary in state.get("armies", []):
		for body: Dictionary in team.get("units", []):
			var identity := int(body.get("person_id", 0))
			if identity <= 0 or people.has(identity): return SiteRuntime.fail("INVALID_REGION_PERSON")
			people[identity] = {"kind": "army", "owner": int(team.team_id), "body": body}
	return SiteRuntime.ok("", {"people": people})
func _region_gameplay_active_player_lab() -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null or str(slot.control.active_site_id).is_empty(): return SiteRuntime.fail("NO_ACTIVE_SITE")
	var active: TerrainLab = self if terrain != null and str(terrain.site.id) == str(slot.control.active_site_id) else slot._region_original_labs.get(str(slot.control.active_site_id))
	if not is_instance_valid(active) or active.terrain == null or active.site_controller.region_slot != slot:
		return SiteRuntime.fail("COMMITTED_UNBOUND", "選定原玩家Site尚未接入真完整Lab")
	var receipt := active.region_bind_receipt(active.terrain)
	if receipt.get("complete") != true or str(receipt.get("owner", "")) != str(slot.control.active_site_id) \
			or int(receipt.get("generation", -1)) != int(slot._marker.get("generation", 0)):
		return SiteRuntime.fail("COMMITTED_UNBOUND", "選定原玩家Lab收據不是本次世代")
	return {"ok": true, "lab": active, "receipt": receipt}


func _region_gameplay_contact_active_data() -> Dictionary:
	var selected := _region_gameplay_active_player_lab()
	if not selected.ok: return selected
	var active: TerrainLab = selected.lab
	var identity := active.controlled_person_id()
	var person := active._original_person_target(identity)
	if person.is_empty(): return SiteRuntime.fail("NO_PERSON")
	var mode := "sea" if active.site_controller.vehicles.is_embarked(identity) else "land"
	var cell: Vector2i = active.site_controller.vehicles.ship_person_cell(identity) if mode == "sea" else person.cell
	if cell.x < 0 or cell.y < 0: return SiteRuntime.fail("MISSING_ORIGINAL_POSITION")
	return {"ok": true, "data": active.terrain, "cell": cell, "person_id": identity, "mode": mode, "receipt": selected.receipt}


func _region_gameplay_endpoint_checkpoint(payload: Dictionary = {}) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null: return SiteRuntime.fail("NO_REGION_SLOT")
	if str(slot.control.active_site_id).is_empty(): return slot.checkpoint_region_travel()
	var selected := _region_gameplay_active_player_lab()
	if not selected.ok: return selected
	var active: TerrainLab = selected.lab
	return active.site_controller.checkpoint_region_internal("region_barrier", active._region_point_pending.is_empty() and active.site_controller._pending_deaths.is_empty() and slot.pending_region_events().is_empty(), payload)


func _region_gameplay_player_materialize(event: Dictionary) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null or float(event.get("at", INF)) > float(slot.control.logical_game_seconds) + 0.00000001:
		return SiteRuntime.fail("STALE_REGION_EVENT")
	if float(event.at) < float(slot.control.logical_game_seconds) - 0.00000001 and not slot._region_mapped_player_death(event):
		return SiteRuntime.fail("STALE_REGION_EVENT")
	var queued: Dictionary = {}
	for original: Dictionary in slot.region_registry().events:
		if str(original.id) == str(event.id): queued = original
	if queued.is_empty() or queued.status != "pending": return SiteRuntime.fail("STALE_REGION_EVENT")
	var npc_token := str(queued.payload.get("token", ""))
	var status := slot.region_travel_status()
	if not status.ok: return status
	var activated: TerrainLab = null
	if bool(status.get("pending", false)):
		var raw: Variant = queued.payload.get("site", [status.site.x, status.site.y])
		if not raw is Array or raw.size() != 2: return SiteRuntime.fail("INVALID_JOINT_ENDPOINT")
		var coordinate := Vector2i(int(raw[0]), int(raw[1]))
		var identity := RegionPartyGrid.site_id(str(slot.pin.atlas_id), coordinate)
		var owner: Dictionary = slot.region_owner_lab.call(identity, "cold_exact")
		if not owner.get("ok", false) or not owner.get("lab") is TerrainLab: return owner
		activated = owner.lab
		var window: Dictionary = slot.validate_settlement(activated.terrain.site, slot.control.logical_game_seconds)
		if not window.ok or bool(window.get("legacy", true)) or float(window.get("pending", INF)) > 0.00000001:
			return SiteRuntime.fail("UNSETTLED_SITE")
		var captured: Dictionary = activated.site_controller.capture_region_checkpoint("region_barrier", false, {"player_event": str(queued.id)})
		if not captured.ok: return captured
		var player := slot.region_travel_party()
		if not player.ok: return player
		var player_location: Dictionary = slot._region_player_endpoint_location(status, player.party, coordinate, queued)
		if not player_location.ok: return player_location
		var endpoint := {"event": queued.duplicate(true), "site": coordinate, "player_location": player_location}
		if not npc_token.is_empty() and str(slot.region_registry().parties.get(npc_token, {}).get("phase", "")) == "travelling":
			var npc_location: Dictionary = slot._region_npc_endpoint_location(npc_token, coordinate, queued)
			if not npc_location.ok: return npc_location
			endpoint.npc_token = npc_token
			endpoint.npc_location = npc_location
		var bind := func(candidate: TerrainData) -> Dictionary:
			return activated.prepare_region_owner_bind(candidate, "live", slot)
		var entered := slot.commit_region_arrival(activated.terrain, bind, endpoint)
		if not entered.ok: return entered
		slot._region_original_labs[identity] = activated
		var wired := activated._wire_region_gameplay_adapters(slot)
		if not wired.ok: return wired
	else:
		var selected := _region_gameplay_active_player_lab()
		if not selected.ok: return selected
		activated = selected.lab
		if not npc_token.is_empty() and str(slot.region_registry().parties.get(npc_token, {}).get("phase", "")) == "travelling":
			var prepared := slot.prepare_npc_region_arrival(queued)
			if not prepared.ok: return prepared
			var joined := slot.commit_npc_region_arrival(prepared)
			if not joined.ok: return joined
	# Publication replaces the registry and remaps current references. Resolve
	# the accepted event again, rather than retaining its pre-marker dictionary.
	queued = {}
	for original: Dictionary in slot.region_registry().events:
		if str(original.id) == str(event.id): queued = original
	if queued.is_empty(): return SiteRuntime.fail("STALE_REGION_EVENT")
	if str(queued.kind) in ["life", "player_death"]:
		var original_destination := str(queued.payload.get("destination_site", activated.terrain.site.id))
		if original_destination != str(activated.terrain.site.id):
			if not slot._region_mapped_player_death(queued): return SiteRuntime.fail("WRONG_SITE")
		else:
			var life := activated._region_gameplay_site_life_effect(queued)
			if not life.ok: return life
	activated.site_controller.settle_person_deaths(0.0)
	# Save the true full graph and accepted effect receipt together. The event
	# itself stays pending until actual visible bind and original continuity.
	var checkpoint := activated._region_gameplay_endpoint_checkpoint({"player_event": str(queued.id), "effects_complete": true})
	if not checkpoint.ok: return checkpoint
	if activated.restore_only:
		var location: Dictionary = slot._coordinate(activated.terrain)
		if not location.ok: return location
		slot.set_meta(&"region_player_materialized", {"site": location.site, "generation": int(slot._marker.generation), "event_id": str(queued.id)})
		return {"ok": true, "receipt": {"complete": false, "effects_complete": true,
			"player_materialized": true, "owner": str(activated.terrain.site.id), "generation": int(slot._marker.generation)}}
	activated.site_controller.check_family_death()
	var controlled := activated._original_person_target(activated.controlled_person_id())
	var living: bool = not controlled.is_empty() and float(controlled.hp) > 0.0
	var controlled_death: bool = bool(queued.payload.get("controlled", false)) and bool(queued.payload.get("death", false))
	var complete := not controlled_death or living
	return {"ok": true, "receipt": {"complete": complete, "effects_complete": true, "continuity_complete": complete,
		"restricted_settlement": not complete and activated.site_controller._pending_deaths.has(activated.controlled_person_id()),
		"owner": str(activated.terrain.site.id), "generation": int(slot._marker.generation),
		"game_seconds": float(slot.control.logical_game_seconds), "action_seconds": float(slot.control.fire_clock.action_seconds)}}


func _region_gameplay_site_life_effect(event: Dictionary) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	var record: Dictionary = event.payload.get("event", event.payload)
	if str(record.get("kind", "")) not in ["supply_damage", "wake"] or not RegionSaveSlot.GameplayClock.whole(record.get("person_id"), 1):
		return SiteRuntime.fail("INVALID_REGION_LIFE_EVENTS")
	var identity := int(record.person_id)
	if terrain.has_meta(&"region_party_owner") or event.payload.has("entered_party"):
		var actual := slot._region_life_original_owner(event)
		if not actual.ok: return actual
		if actual.get("family_complete", false) or actual.lab != self: return SiteRuntime.fail("WRONG_LIFE_OWNER")
		identity = int(actual.person_id)
	else:
		var destination := str(event.payload.get("destination_site", event.payload.get("entered_site", terrain.site.id)))
		if destination != str(terrain.site.id): return SiteRuntime.fail("WRONG_SITE")
	var person := _original_person_target(identity)
	if person.is_empty(): return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
	var prior: Dictionary = event.payload.get("effect_receipt", {})
	if not prior.is_empty():
		if not slot._region_life_effect_receipt(event):
			return SiteRuntime.fail("INVALID_REGION_RECEIPT")
		return SiteRuntime.ok("", {"effects_complete": true, "duplicate": true})
	var hp := float(person.hp)
	if hp <= 0.0 or str(record.kind) == "supply_damage" and absf(hp - float(record.old_hp)) > 0.0000001:
		return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
	var consuming := _region_point_consuming
	_region_point_consuming = true
	match str(record.kind):
		"supply_damage":
			var ending: float = site_controller._apply_supply_damage(identity, float(record.loss))
			if absf(ending - float(record.ending_hp)) > 0.0000001:
				_region_point_consuming = consuming
				return site_controller.latch_original_step_fault(SiteRuntime.fail("REGION_LIFE_CONTRACT"))
		"wake":
			if int(person.unit) >= 0: person.owner._wake_unit(int(person.unit))
			else: person.owner._wake_up()
	_region_point_consuming = consuming
	for team: TerrainArmy in combat_armies:
		if team.combat_enabled: team.settle_combat_command()
	for effect: Dictionary in site_controller.person_actions.settle_after_contacts(): site_controller.collect_ground_boundary_result(effect)
	site_controller.settle_person_deaths(0.0)
	event.payload.effect_receipt = {"event_id": str(event.id), "person_id": int(record.person_id), "effects_complete": true,
		"game_seconds": float(event.at), "action_seconds": float(slot.control.fire_clock.action_seconds)}
	for accepted: Dictionary in terrain.site.get("region_life_events", []):
		if int(accepted.sequence) == int(record.get("sequence", -1)) and int(accepted.person_id) == identity: accepted.status = "complete"
	if terrain.site.get("region_life_events", []).all(func(accepted: Dictionary) -> bool: return str(accepted.status) == "complete"):
		terrain.site.erase("region_life_events")
	return SiteRuntime.ok("", {"effects_complete": true})


func _region_gameplay_party_life(token: String, life: Dictionary, party: Dictionary) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null: return SiteRuntime.fail("NO_REGION_SLOT")
	var queued: Dictionary = {}
	for event: Dictionary in slot.region_registry().events:
		if str(event.status) == "pending" and str(event.kind) == "life" and str(event.payload.get("token", "")) == token \
				and int(event.payload.get("event", {}).get("sequence", -1)) == int(life.get("sequence", -2)): queued = event
	if queued.is_empty(): return SiteRuntime.fail("STALE_REGION_LIFE_OWNER")
	if queued.payload.has("entered_site"):
		var identity := str(queued.payload.entered_site)
		var original: Dictionary = slot.region_owner_lab.call(identity, "live" if identity == str(slot.control.active_site_id) else "cold_exact")
		if not original.get("ok", false): return original
		var active: TerrainLab = original.lab
		var applied := active._region_gameplay_site_life_effect(queued)
		if not applied.ok: return applied
		var saved := _region_gameplay_endpoint_checkpoint({"npc_life": str(queued.id)})
		if not saved.ok: return saved
		return {"ok": true, "party": party, "receipt": {"complete": true, "effects_complete": true}}
	var consumed := slot.consume_region_party_endpoint(queued)
	if not consumed.ok: return consumed
	var captured := slot._region_npc_party(token)
	if not captured.ok: return captured
	return {"ok": true, "party": captured.party, "receipt": consumed.receipt}

# Add to the EXISTING _wire_region_gameplay_adapters after its Slot check:
# slot.region_original_party_endpoint = Callable(self,"_region_gameplay_party_endpoint")
# slot.region_original_party_progress = Callable(self,"_region_gameplay_party_progress")
# slot.region_original_endpoint_checkpoint = Callable(self,"_region_gameplay_endpoint_checkpoint")
# slot.region_original_player_materialize = Callable(self,"_region_gameplay_player_materialize")
# slot.region_contact_active_data = Callable(self,"_region_gameplay_contact_active_data")
# slot.region_party_life_consumer = Callable(self,"_region_gameplay_party_life")


# Same original encoder as ordinary capture. This adapter proves the exact
# actual owner snapshot/context before permitting a durable pending boundary.
func capture_region_fire_transport(context: Dictionary, expected_owners: Dictionary) -> Dictionary:
	if terrain == null or site_controller == null or _region_bound_data != terrain \
			or _fire_committing or _fire_advancing or not _fire_boundary_error.is_empty() or _region_point_consuming \
			or _siege_collect_contacts and not _region_completed_contact_capture(context) \
			or terrain.has_meta(&"fire_structure_step") \
			or not _region_point_pending.is_empty() and _region_point_pending.get("interval_complete") != true:
		var refused := SiteRuntime.fail("REGION_FIRE_EFFECT_RUNNING")
		refused.capture_guard = {"owner": str(terrain.site.get("id", "")) if terrain != null else "",
			"bound": terrain != null and _region_bound_data == terrain, "fire_committing": _fire_committing,
			"fire_advancing": _fire_advancing, "fire_error": str(_fire_boundary_error.get("code", "")),
			"point_consuming": _region_point_consuming, "point_dispatching": _region_point_dispatching,
			"siege_collect_contacts": _siege_collect_contacts, "completed_contact_capture": _region_completed_contact_capture(context),
			"structure_running": terrain != null and terrain.has_meta(&"fire_structure_step"),
			"point_interval_complete": _region_point_pending.get("interval_complete"), "point_game_end": _region_point_pending.get("game_end"),
			"point_action_begin": _region_point_pending.get("action_begin"), "point_action_end": _region_point_pending.get("action_end"),
			"fire_action_cursor": fire_action_cursor, "boundary": terrain.get_meta(&"fire_boundary", {}) if terrain != null else {},
			"capture_interval_complete": context.get("interval_complete"), "capture_effects_complete": context.get("effects_complete"),
			"capture_game_seconds": context.get("game_seconds"), "capture_action_seconds": context.get("action_seconds")}
		return refused
	var original: Variant = terrain.get_meta(&"site_garrison_lab") if terrain.has_meta(&"site_garrison_lab") else null
	if original is WeakRef: original = original.get_ref()
	if original != self: return SiteRuntime.fail("STALE_REGION_FIRE_OWNER")
	var actual := capture_region_owner_state(context)
	if not actual.ok: return actual
	if not expected_owners.get("scene") is Dictionary \
			or RegionCheckpoint.state_hash({"graph": actual.state}) != RegionCheckpoint.state_hash({"graph": expected_owners.scene}) \
			or actual.owner_states.get("fire_boundary_receipt", {}) != expected_owners.get("fire_boundary_receipt", {}):
		return SiteRuntime.fail("STALE_REGION_FIRE_OWNER")
	var pending_guard := SiteStore._region_fire_guard(terrain, {"context": context, "owners": actual.owner_states})
	if not pending_guard.ok: return pending_guard
	var captured := _capture_fire_transport_payload()
	if not captured.ok: return captured
	var receipt := context.duplicate(true)
	receipt.ok = true; receipt.state = captured.state
	receipt.owner_graph_hash = RegionCheckpoint.state_hash({"graph": actual.state})
	return receipt

## R2 original-owner calibration plus guarded formal fixed-target caller.
## Formal installation is gated on actual isolated S01/S02 comparisons.
## This retains the same original Lab, Actor and TerrainData throughout; the
## safety helper never becomes a second saved body or a clock publisher.
var _region_cold_isolated: Dictionary = {}
var _region_cold_formal: Dictionary = {} # Original retained replay transaction only.

func region_cold_original_inputs() -> Dictionary:
	if terrain == null or site_controller == null or not restore_only or _region_bound_data != terrain:
		return SiteRuntime.fail("COLD_ORIGINAL_OWNER_REQUIRED")
	var fault: Dictionary = site_controller.original_step_fault_guard()
	if not fault.ok: return fault
	var bind := region_bind_receipt(terrain)
	if bind.get("complete") != true or bind.get("owners_restored") != true or str(bind.get("backend")) != "gd":
		return SiteRuntime.fail("COLD_ORIGINAL_OWNER_REQUIRED")
	var captured: Dictionary = site_controller._capture_for_save()
	if not captured.ok: return captured
	# These are actual call-local owner facts. No caller supplies either bool or G.
	var p0_stable: bool = not get_tree().paused and not bool(terrain.site.get("paused", false)) \
		and _region_point_pending.is_empty() and _region_point_contacts.is_empty() and _region_point_wakes.is_empty() \
		and not _region_point_consuming and not _region_point_dispatching and _combat_contacts.is_empty() and site_controller._pending_deaths.is_empty() \
		and not is_instance_valid(site_controller._family_dialog)
	var actions_stable: bool = _shared_work_plan.is_empty() and not _shared_movement_prepared \
		and _fatigue_work_seconds.is_empty() and site_controller.person_actions._jobs.is_empty() \
		and site_controller.work_team.active_ids().is_empty() and site_controller._ship_journey.is_empty() \
		and site_controller._ground_crossing.is_empty() and fire_projectiles.is_empty() and fire_reservations.is_empty() \
		and terrain.get_meta(&"fire_boundary", {}).is_empty() and not _fire_committing and not _fire_advancing
	for actor: TerrainTestCharacter in combat_actors:
		if not actor_present(actor): continue
		actions_stable = actions_stable and not actor.is_moving() and actor.action_time <= 0.0 \
			and actor.knockout_left <= 0.0 and actor._rescue_left <= 0.0 and actor._reload_left <= 0.0 \
			and not actor.guarding and actor.guard_transition_left <= 0.0 and actor.guard_break_left <= 0.0 \
			and actor.projectiles.is_empty() and not site_controller.person_actions.is_busy(actor.person_id)
		p0_stable = p0_stable and actor.hp > 0.0
	for team: TerrainArmy in combat_armies:
		if team.has_army(): actions_stable = false
	var formal_slot: RegionSaveSlot = _region_cold_formal.get("slot")
	var generation := int(formal_slot._marker.get("generation", -1)) if formal_slot != null else int(bind.get("generation", -1))
	return SiteRuntime.ok("", {"inputs": {"p0_stable": p0_stable, "actions_stable": actions_stable,
		"owner_generation": generation, "source_owner_id": get_instance_id(),
		"site_id": str(terrain.site.id), "backend": str(bind.backend)}})

func _region_cold_quiet_admission() -> Dictionary:
	var original := region_cold_original_inputs()
	if not original.ok: return original
	if original.inputs.p0_stable != true or original.inputs.actions_stable != true:
		return SiteRuntime.fail("COLD_INPUT_EVENT")
	var idle_fire := _region_cold_idle_fire_proof(terrain)
	if not idle_fire.ok: return idle_fire
	# Politics/technology/production have no offline rate contract here. A saved
	# body carrying any such owner keeps the complete original exact consumer.
	if site_controller.region_slot != null or terrain.site.has("region_snapshot") or terrain.site.has("fire_settlement"):
		var formal := _region_cold_formal_admission()
		if not formal.ok: return formal
	for key: String in ["family", "equipment_nations", "corps", "settlement", "features", "fire", "captivity", "marine", "vehicles", "armies", "team_supply"]:
		if not terrain.site.get(key, {}).is_empty(): return SiteRuntime.fail("COLD_UNSUPPORTED_OWNER", key)
	if bool(terrain.site.get("worker_enabled", false)) or bool(terrain.site.get("worker", {}).get("manual_control", false)):
		return SiteRuntime.fail("COLD_INPUT_EVENT")
	var cold_script: Script = load("res://scripts/terrain_lab/site_region_cold.gd")
	terrain.set_meta(&"region_cold_inputs", original.inputs)
	var empty: bool = cold_script._summary_safe(terrain)
	var resident: Dictionary = cold_script._resident_inputs(terrain)
	if not empty and not resident.ok: return resident
	return SiteRuntime.ok("", {"inputs": original.inputs, "kind": "resource_events" if empty else "resident_sustain_fatigue"})

## A disabled original order is still real saved metadata. Admit only the
## current actual producer after the unchanged original strict validators.
## Serial, owner, release IDs, cursor, targets and raw saved fields are retained.
func _region_cold_idle_fire_proof(data: TerrainData) -> Dictionary:
	if data != terrain or data != _region_bound_data or not restore_only or site_controller == null:
		return SiteRuntime.fail("COLD_ORIGINAL_OWNER_REQUIRED")
	if not terrain.site.get("fire", {}).is_empty() or not fire_projectiles.is_empty() or not fire_reservations.is_empty() \
		or not siege_projectiles.is_empty() or _fire_committing or _fire_advancing:
		return SiteRuntime.fail("COLD_ACTIVE_FIRE")
	var captured := capture_fire_transport()
	if not captured.ok: return captured
	var checked := SiteStore._validate_fire_transport_snapshot(terrain, terrain.site.get("fire", {}), captured.state)
	if not checked.ok: return checked
	var owners := SiteStore._validate_fire_transport_owners(terrain, terrain.site, checked.state)
	if not owners.ok: return owners
	var transport: Dictionary = checked.state
	if not transport.projectiles.is_empty() or not transport.reservations.is_empty() \
		or int(transport.release_sequence) > 0 or int(transport.exposure_sequence) > 0:
		return SiteRuntime.fail("COLD_ACTIVE_FIRE")
	for order: Dictionary in transport.orders.values():
		if order.enabled or not order.ranged_fire_policy.is_empty(): return SiteRuntime.fail("COLD_ACTIVE_FIRE")
	var actual_owners := capture_fire_owner_state()
	if not actual_owners.ok: return actual_owners
	var owner_check := SiteStore._validate_fire_owner_snapshot(terrain, terrain.site, actual_owners.state, fire_action_cursor)
	if not owner_check.ok: return owner_check
	if not actual_owners.state.is_empty(): return SiteRuntime.fail("COLD_ACTIVE_FIRE_OWNER")
	return SiteRuntime.ok()

## This one-minute prefix consumes the actual original providers once. It
## skips only physical idle sampling, whose absence the real owner proves.
## A minute cap retains every original daily-duty boundary; no day-count
## policy events, speculative political interval or fixed production rate.
func _region_advance_original_quiet_minute(target: float, game_seconds: float) -> Dictionary:
	var admitted := _region_cold_quiet_admission()
	if not admitted.ok: return admitted
	if not is_finite(game_seconds) or game_seconds <= 0.0 or game_seconds > 60.0 + ACTION_TIME_EPSILON:
		return SiteRuntime.fail("INVALID_TIME")
	var combat_left := float(terrain.site.get("combat_left", 0.0))
	if combat_left > 0.0 or _fire_activity() or _siege_active(): return SiteRuntime.fail("COLD_INPUT_EVENT")
	var fire_guard := _fire_step_guard()
	if not fire_guard.ok: return fire_guard
	var action_seconds := game_seconds / (60.0 * simulation_speed)
	if not is_finite(action_seconds) or action_seconds <= 0.0 \
		or absf(SiteRuntime.game_seconds(action_seconds, combat_left) * simulation_speed - game_seconds) > ACTION_TIME_EPSILON:
		return SiteRuntime.fail("CLOCK_CONTRACT")
	var original := terrain
	var action_begin := fire_action_cursor
	var action_end := action_begin + action_seconds
	var opened := _begin_fire_boundary(action_end)
	if not opened.ok: return opened
	site_controller.prepare_settlement_interval()
	site_controller.tick(action_seconds, game_seconds)
	if terrain != original or get_tree().paused or bool(terrain.site.get("paused", false)):
		return site_controller.latch_original_step_fault(SiteRuntime.fail("INTERRUPTED_STEP"))
	_advance_fatigue(game_seconds)
	_advance_tactical_ai(action_seconds)
	_advance_duty_ai(game_seconds)
	for actor: TerrainTestCharacter in combat_actors:
		if actor_present(actor): actor.advance_combat(action_seconds, true, game_seconds)
	if exchange_enabled:
		_advance_ranged(action_seconds)
		_exchange_phase += action_seconds
		while _exchange_phase + ACTION_TIME_EPSILON >= EXCHANGE_QUERY_STEP:
			_exchange_phase -= EXCHANGE_QUERY_STEP
			_resolve_exchanges()
	else:
		TerrainArmy.begin_contact_step()
		for actor: TerrainTestCharacter in combat_actors:
			if actor_present(actor): actor.sample_combat()
		_resolve_combat_contacts()
	if not _combat_contacts.is_empty() or not site_controller._pending_deaths.is_empty():
		return site_controller.latch_original_step_fault(SiteRuntime.fail("COLD_UNEXPECTED_P0"))
	if not _finish_fire_boundary(action_begin, action_end): return _fire_boundary_error
	_fatigue_work_seconds.clear()
	var fault: Dictionary = site_controller.original_step_fault_guard()
	if not fault.ok: return fault
	var recorded := RegionSaveSlot.record_completed_replay_step(terrain.site, target, game_seconds)
	if not recorded.ok: return recorded
	return SiteRuntime.ok("", {"game_seconds": game_seconds, "action_seconds": action_seconds, "at": float(recorded.at)})

func _region_cold_quiet_limit(maximum: float) -> float:
	var limit := minf(60.0, maximum)
	if _duty_ai_elapsed > ACTION_TIME_EPSILON:
		limit = minf(limit, maxf(0.0, DutyAI.REVIEW_GAME_SECONDS - _duty_ai_elapsed))
	for supply: Dictionary in terrain.site.get("person_supply", {}).values():
		var at := float(supply.at) # The original personal Sustain clock can differ from World/Site.
		for cohort: Dictionary in supply.cohorts:
			var meal := float(cohort.meal_until)
			if meal > at + ACTION_TIME_EPSILON: limit = minf(limit, meal - at)
			var deficit := 1.0 - float(cohort.coverage)
			if deficit > 0.0: limit = minf(limit, maxf(0.0, 48.0 - float(cohort.hunger)) / deficit * SiteStore.Sustain.HOUR)
	return limit

func region_cold_actual_progress() -> Dictionary:
	if terrain == null: return {}
	var window := RegionSaveSlot.validate_settlement(terrain.site, (float(terrain.site.minute) + float(terrain.site.phase)) * 60.0)
	var bind := region_bind_receipt(terrain)
	return {"site_id": str(terrain.site.id), "game_seconds": float(window.get("last", -1.0)),
		"action_seconds": fire_action_cursor, "owner_generation": int(bind.get("generation", -1)),
		"exchange_phase": _exchange_phase, "exchange_round": _exchange_round,
		"tactical_elapsed": _tactical_ai_elapsed, "duty_elapsed": _duty_ai_elapsed,
		"work_elapsed": site_controller._work_elapsed, "settlement_elapsed": site_controller._settlement_elapsed,
		"save_elapsed": site_controller._save_elapsed, "original_pending_deaths": site_controller._pending_deaths.duplicate(true),
		"point_pending": not _region_point_pending.is_empty(), "published": false}

func advance_isolated_region_cold(target: float, budget_usec: int = 4000, max_steps: int = 128,
		tail_seconds: float = 7200.0) -> Dictionary:
	if not restore_only or terrain == null or site_controller == null or site_controller.region_slot != null:
		return SiteRuntime.fail("COLD_ISOLATED_SCOPE")
	if not _region_cold_formal.is_empty(): return SiteRuntime.fail("COLD_ISOLATED_SCOPE")
	return _region_advance_original_cold_budget(target, budget_usec, max_steps, tail_seconds)

func _region_advance_original_cold_budget(target: float, budget_usec: int, max_steps: int,
		tail_seconds: float) -> Dictionary:
	if not is_finite(target) or target < 0.0 or not is_finite(tail_seconds) or tail_seconds < 0.0 or budget_usec < 1 or max_steps < 1:
		return SiteRuntime.fail("INVALID_TIME")
	var started := Time.get_ticks_usec()
	if _region_cold_isolated.is_empty():
		var source := cold_source_identity(terrain, target)
		var window := RegionSaveSlot.replay_window(terrain.site, target)
		if not source.ok: return source
		if not window.ok: return window
		var original := region_cold_original_inputs()
		if not original.ok: return original
		_region_cold_isolated = {"data": terrain, "target": target, "tail": tail_seconds,
			"source_sha256": str(_region_cold_formal.get("source_sha256", source.source_sha256)), "owner_generation": int(original.inputs.owner_generation),
			"prefix_end": maxf(float(window.from), target - tail_seconds), "prefix_steps": 0, "exact_steps": 0,
			"prefix_game_seconds": 0.0, "prefix_action_seconds": 0.0, "fallback": ""}
	if _region_cold_isolated.data != terrain or float(_region_cold_isolated.target) != target or float(_region_cold_isolated.tail) != tail_seconds:
		return SiteRuntime.fail("BUSY", "原隔離來源／固定目標仍在補算")
	var steps := 0
	var deadline := started + budget_usec
	var window := RegionSaveSlot.replay_window(terrain.site, target)
	if not window.ok: return window
	while float(window.from) + ACTION_TIME_EPSILON < float(_region_cold_isolated.prefix_end) \
		and steps < max_steps and Time.get_ticks_usec() < deadline and str(_region_cold_isolated.fallback).is_empty():
		var admitted := _region_cold_quiet_admission()
		if not admitted.ok:
			_region_cold_isolated.fallback = str(admitted.get("code", "COLD_UNSUPPORTED_OWNER"))
			break
		var game := _region_cold_quiet_limit(float(_region_cold_isolated.prefix_end) - float(window.from))
		var journal := _region_cold_quiet_journal(game) if not _region_cold_formal.is_empty() else {}
		if not _region_cold_formal.is_empty():
			if not journal.get("ok", false):
				if str(journal.get("code", "")) == "COLD_EXACT_REMAINDER":
					var quantum := _next_fire_replay_interval()
					var exact := _advance_original_shared_step(float(quantum.action_end) - float(quantum.action_begin), target, quantum)
					if not exact.get("ok", false) or not exact.get("completed", false): return exact
					_fire_replay_segment_offset += 1
					steps += 1
					_region_cold_isolated.exact_steps = int(_region_cold_isolated.exact_steps) + 1
					window = RegionSaveSlot.replay_window(terrain.site, target)
					if not window.ok: return window
					continue
				_region_cold_isolated.fallback = str(journal.get("code", "COLD_EXACT_JOURNAL"))
				break
			game = float(journal.game_end) - float(journal.game_begin)
		if game <= ACTION_TIME_EPSILON:
			_region_cold_isolated.fallback = "COLD_LIFE_ENDPOINT"
			break
		var advanced := _region_advance_original_quiet_minute(target, game)
		if not advanced.ok: return advanced
		if not journal.is_empty():
			# The actual original providers and physical Fire completion just ran.
			# Consume their existing accepted journal endpoint; never publish world time.
			if absf(fire_action_cursor - float(journal.action_end)) > ACTION_TIME_EPSILON:
				return site_controller.latch_original_step_fault(SiteRuntime.fail("CLOCK_CONTRACT"))
			RegionSaveSlot.record_completed_fire_replay(terrain.site, journal)
			_fire_replay_segment_offset += int(journal.consumed_steps)
		steps += 1
		_region_cold_isolated.prefix_steps = int(_region_cold_isolated.prefix_steps) + 1
		_region_cold_isolated.prefix_game_seconds = float(_region_cold_isolated.prefix_game_seconds) + float(advanced.game_seconds)
		_region_cold_isolated.prefix_action_seconds = float(_region_cold_isolated.prefix_action_seconds) + float(advanced.action_seconds)
		window = RegionSaveSlot.replay_window(terrain.site, target)
		if not window.ok: return window
	var replay: Dictionary = SiteRuntime.ok("", {"status": "PENDING", "pending": float(window.pending), "steps": 0, "data": terrain})
	if (float(window.from) + ACTION_TIME_EPSILON >= float(_region_cold_isolated.prefix_end) or not str(_region_cold_isolated.fallback).is_empty()) \
		and steps < max_steps and Time.get_ticks_usec() < deadline:
		replay = replay_site_to(target, maxi(1, deadline - Time.get_ticks_usec()), max_steps - steps)
		if not replay.ok: return replay
		steps += int(replay.steps)
		_region_cold_isolated.exact_steps = int(_region_cold_isolated.exact_steps) + int(replay.steps)
	var progress := region_cold_actual_progress()
	var complete := str(replay.status) == "COMPLETE"
	return SiteRuntime.ok("", {"status": "COMPLETE" if complete else "PENDING", "target": target,
		"pending": maxf(0.0, target - float(progress.game_seconds)), "steps": steps,
		"processing_usec": Time.get_ticks_usec() - started, "cpu_budget_usec": budget_usec,
		"process_cpu_seconds": null, "process_cpu_source": "canonical host measurement required",
		"method": "quiet_original_minute_prefix_exact_tail" if int(_region_cold_isolated.prefix_steps) > 0 else "original_shared_exact",
		"prefix_steps": int(_region_cold_isolated.prefix_steps), "exact_steps": int(_region_cold_isolated.exact_steps),
		"prefix_game_seconds": float(_region_cold_isolated.prefix_game_seconds), "prefix_action_seconds": float(_region_cold_isolated.prefix_action_seconds),
		"fallback": str(_region_cold_isolated.fallback), "source_sha256": str(_region_cold_isolated.source_sha256),
		"owner_generation": int(_region_cold_isolated.owner_generation), "progress": progress, "data": terrain,
		"interval_complete": complete, "effects_complete": complete, "published": false})

## This is called only by the existing parent's retained _cold_replay_lab.
## Source/body/marker provenance is verified through that original Slot.
## An unavailable capability keeps the whole original bounded-exact consumer.
func advance_region_cold_actual_fixed(source_data: TerrainData, target: float,
		budget_usec: int = 4000, max_steps: int = 128, tail_seconds: float = 7200.0) -> Dictionary:
	var parent := get_parent() as TerrainLab
	if parent == null or parent.site_controller == null or parent._cold_replay_lab != self \
		or parent.site_controller.region_slot == null or not restore_only or source_data == null:
		return SiteRuntime.fail("COLD_ORIGINAL_TRANSACTION_REQUIRED")
	var slot: RegionSaveSlot = parent.site_controller.region_slot
	var identity := parent.cold_source_identity(source_data, target)
	if not identity.ok: return identity
	if parent._cold_replay_id != str(identity.site_id) or parent._cold_replay_signature != str(identity.source_sha256) \
		or parent._cold_replay_target != target or absf(float(slot.control.logical_game_seconds) - target) > ACTION_TIME_EPSILON:
		return SiteRuntime.fail("STALE_COLD_TRANSACTION")
	if _region_cold_formal.is_empty():
		var selected := parent._region_selected_bind_source(source_data, slot)
		if not selected.ok: return replay_site_to(target, budget_usec, max_steps)
		_region_cold_formal = {"slot": slot, "parent": parent, "source_data": source_data,
			"source_sha256": str(identity.source_sha256), "selected_proof": selected.proof.duplicate(true),
			"generation": int(slot._marker.get("generation", -1)), "target": target}
	elif _region_cold_formal.get("source_data") != source_data or _region_cold_formal.get("slot") != slot \
		or str(_region_cold_formal.source_sha256) != str(identity.source_sha256):
		return SiteRuntime.fail("STALE_COLD_TRANSACTION")
	return _region_advance_original_cold_budget(target, budget_usec, max_steps, tail_seconds)

func _region_cold_formal_admission() -> Dictionary:
	if _region_cold_formal.is_empty() or not _fire_replay_tracking:
		return SiteRuntime.fail("COLD_FORMAL_PROOF_REQUIRED")
	var slot: RegionSaveSlot = _region_cold_formal.slot
	var parent: TerrainLab = _region_cold_formal.parent
	if slot == null or not is_instance_valid(parent) or parent._cold_replay_lab != self \
		or parent.site_controller.region_slot != slot or parent._cold_replay_target != float(_region_cold_formal.target) \
		or int(slot._marker.get("generation", -1)) != int(_region_cold_formal.generation) \
		or str(parent._cold_replay_signature) != str(_region_cold_formal.source_sha256):
		return SiteRuntime.fail("STALE_COLD_TRANSACTION")
	var proof: Dictionary = slot.region_bind_proof(_region_cold_formal.source_data)
	if proof != _region_cold_formal.selected_proof \
		or FileAccess.get_sha256(slot.folder.path_join(str(proof.get("path", "")))) != str(proof.get("sha256", "")):
		return SiteRuntime.fail("STALE_REGION_SOURCE")
	var site_id := str(terrain.site.id)
	if str(slot.control.active_site_id) == site_id: return SiteRuntime.fail("PLAYER_BARRIER")
	var mode: Dictionary = slot.region_registry().modes.get(site_id, {})
	var activation: Dictionary = mode.get("activation", {})
	if str(mode.get("mode", "")) != "cold_exact" or str(mode.get("backend", "")) != "gd" \
		or str(mode.get("consumer", "")) != "original_replay" or int(mode.get("generation", -1)) != int(_region_cold_formal.generation) \
		or activation.get("complete") != true or activation.get("owners_restored") != true \
		or str(activation.get("owner", "")) != site_id or int(activation.get("generation", -1)) != int(_region_cold_formal.generation):
		return SiteRuntime.fail("COLD_FORMAL_MODE_REQUIRED")
	if _region_owner_restore_receipt.get("owners_restored") != true or _region_owner_restore_receipt.get("effects_complete") != true \
		or bool(_region_bind_receipt_value.get("zero_world_only", false)):
		return SiteRuntime.fail("COLD_EFFECTS_PENDING")
	# A deferred original world endpoint is never swept through by an idle macro.
	for event: Dictionary in slot.pending_region_events():
		if float(event.get("at", INF)) <= float(_region_cold_formal.target) + ACTION_TIME_EPSILON:
			return SiteRuntime.fail("COLD_WORLD_ENDPOINT_PENDING")
	var fire: Dictionary = terrain.site.get("fire_settlement", {})
	var interval := _next_fire_replay_interval()
	if interval.is_empty() or str(fire.get("epoch", "")) != str(interval.get("epoch", "")) \
		or int(fire.get("sequence", -1)) != int(interval.get("sequence", 0)) - 1 \
		or absf(float(fire.get("action_seconds", -1.0)) - fire_action_cursor) > ACTION_TIME_EPSILON:
		return SiteRuntime.fail("COLD_EXACT_JOURNAL")
	return SiteRuntime.ok()

func _region_cold_quiet_journal(maximum_game_seconds: float) -> Dictionary:
	var admitted := _region_cold_formal_admission()
	if not admitted.ok: return admitted
	var first := _next_fire_replay_interval()
	if float(first.tactical_seconds) > ACTION_TIME_EPSILON or float(first.scale) != simulation_speed:
		return SiteRuntime.fail("COLD_EXACT_JOURNAL")
	var row: Dictionary = _fire_replay_segments[_fire_replay_segment_index]
	var remaining := int(row.steps) - _fire_replay_segment_offset
	var game_step := (float(row.game_end) - float(row.game_begin)) / int(row.steps)
	var action_step := (float(row.action_end) - float(row.action_begin)) / int(row.steps)
	if game_step <= 0.0 or action_step <= 0.0 or float(row.tactical_seconds) > ACTION_TIME_EPSILON:
		return SiteRuntime.fail("COLD_EXACT_JOURNAL")
	var count := mini(remaining, floori((maximum_game_seconds + ACTION_TIME_EPSILON) / game_step))
	# Keep a short remainder on the exact path. No rounding beyond a paid meal.
	if count < 2: return SiteRuntime.fail("COLD_EXACT_REMAINDER")
	var result := first.duplicate(true)
	result.sequence = int(first.sequence) + count - 1
	result.action_end = float(row.action_end) if count == remaining else float(first.action_begin) + action_step * count
	result.game_end = float(row.game_end) if count == remaining else float(first.game_begin) + game_step * count
	result.tactical_seconds = 0.0
	result.consumed_steps = count
	if float(result.game_end) - float(result.game_begin) > maximum_game_seconds + ACTION_TIME_EPSILON \
		or absf((float(result.action_end) - float(result.action_begin)) * 60.0 * simulation_speed \
			- (float(result.game_end) - float(result.game_begin))) > ACTION_TIME_EPSILON:
		return SiteRuntime.fail("CLOCK_CONTRACT")
	return SiteRuntime.ok("", result)

# A completed Region point can retain its original paid siege contact batch.
# It is captured during the original dispatcher before that zero-time consumer
# resumes. Running body/fire/structure work still has no serializable endpoint.
func _region_completed_contact_capture(context: Dictionary) -> bool:
	if terrain == null or site_controller == null or site_controller.region_slot == null \
			or _region_point_consuming or _region_point_pending.is_empty() \
			or context.get("interval_complete") != true or context.get("effects_complete") != false \
			or terrain.has_meta(&"fire_structure_step") or _fire_advancing or _fire_committing:
		return false
	var slot: RegionSaveSlot = site_controller.region_slot
	if not slot.region_original_player_materialize.is_valid(): return false
	var dispatcher: Object = slot.region_original_player_materialize.get_object()
	if not dispatcher is TerrainLab or dispatcher.site_controller == null or dispatcher.site_controller.region_slot != slot \
			or dispatcher.terrain == null or dispatcher._region_bound_data != dispatcher.terrain \
			or not dispatcher._region_point_dispatching or dispatcher._region_point_consuming:
		return false
	var expected := str(slot.control.active_site_id)
	if expected.is_empty(): expected = "travel:" + str(slot.region_travel_journey().get("token", ""))
	var receipt: Dictionary = dispatcher.region_bind_receipt(dispatcher.terrain)
	if str(dispatcher.terrain.site.id) != expected or receipt.get("complete") != true \
			or receipt.get("owners_restored") != true or receipt.get("owner") != expected \
			or int(receipt.get("generation", -1)) != int(slot._marker.get("generation", 0)):
		return false
	if dispatcher != self and slot._region_original_labs.get(str(terrain.site.id)) != self: return false
	var point: Dictionary = _region_point_pending
	for endpoint: Dictionary in [point, dispatcher._region_point_pending]:
		if endpoint.get("interval_complete") != true or endpoint.get("epoch") != context.get("fire_epoch") \
				or int(endpoint.get("sequence", -1)) != int(context.get("fire_sequence", -2)) \
				or absf(float(endpoint.get("game_end", -1.0)) - float(context.get("game_seconds", -2.0))) > ACTION_TIME_EPSILON \
				or absf(float(endpoint.get("action_end", -1.0)) - float(context.get("action_seconds", -2.0))) > ACTION_TIME_EPSILON \
				or absf(float(endpoint.get("fire_action_end", -1.0)) - float(context.get("action_seconds", -2.0))) > ACTION_TIME_EPSILON:
			return false
	if absf(float(context.get("game_seconds", -1.0)) - float(slot.control.logical_game_seconds)) > ACTION_TIME_EPSILON \
			or absf(float(context.get("action_seconds", -1.0)) - float(slot.control.fire_clock.action_seconds)) > ACTION_TIME_EPSILON:
		return false
	var boundary: Variant = terrain.get_meta(&"fire_boundary", {})
	return boundary is Dictionary and boundary.size() == 5 and boundary.get("flushing") == false \
		and str(boundary.get("site_id", "")) == str(terrain.site.id) \
		and absf(float(boundary.get("action_end", -1.0)) - float(context.action_seconds)) <= ACTION_TIME_EPSILON \
		and (absf(fire_action_cursor - float(point.get("fire_action_begin", -1.0))) <= ACTION_TIME_EPSILON \
			or absf(fire_action_cursor - float(point.get("fire_action_end", -1.0))) <= ACTION_TIME_EPSILON)

func _region_advance_live_party_host(maximum_action_seconds: float) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null or terrain == null or not terrain.has_meta(&"region_party_owner"):
		return SiteRuntime.fail("INVALID_TRAVEL_HOST")
	var token := str(terrain.get_meta(&"region_party_owner").get("token", ""))
	var selected: Dictionary = slot.region_travel_party()
	if not selected.ok: return selected
	var current: Dictionary = slot.region_original_party_runtime_proof(token, selected.party)
	if not current.ok or current.get("lab") != self: return current if not current.ok else SiteRuntime.fail("INVALID_TRAVEL_HOST")
	# Wire the SAME original host before copying its callback into the request.
	if not slot.region_owner_lab.is_valid() or not slot.region_original_travel_interval.is_valid() or not slot.region_original_party_progress.is_valid():
		var wired: Dictionary = _wire_region_gameplay_adapters(slot)
		if not wired.ok: return wired
	var live_body := str(selected.party.upkeep.get("live", {}).get("upkeep", "")) == "liveBody"
	var candidate: Callable = slot._region_live_party_candidate.bind(selected.party)
	if not live_body:
		var status: Dictionary = slot.region_travel_status()
		if not status.ok: return status
		candidate = func(interval: Dictionary) -> Dictionary: return slot._region_player_land_candidate(selected.party, status, interval)
	var accepted: Dictionary = _region_advance_original_travel_interval({"token": token, "party": selected.party,
		"maximum_action_seconds": maximum_action_seconds, "scale": simulation_speed, "live_body": live_body,
		"candidate": candidate, "party_progress": slot.region_original_party_progress})
	if not accepted.ok or accepted.get("pending", false): return accepted
	var committed: Dictionary = slot._region_accept_player_travel_interval(token, accepted)
	if not committed.ok: return committed
	committed.completed = bool(committed.get("complete", false))
	committed.action_seconds = float(accepted.interval.action_end) - float(accepted.interval.action_begin)
	committed.game_seconds = float(accepted.interval.game_end) - float(accepted.interval.game_begin)
	return committed

func _region_advance_original_party_body(original: TerrainLab, before: Dictionary, interval: Dictionary) -> Dictionary:
	var guarded: Dictionary = original._region_original_interval_guard(interval)
	if not guarded.ok: return guarded
	original._region_owner_interval_active = true
	var result: Dictionary = original._advance_original_shared_step(float(interval.action_end) - float(interval.action_begin),
		float(interval.game_end), interval, true)
	original._region_owner_interval_active = false
	if not result.ok or not result.get("completed", false): return result
	var captured: Dictionary = _region_capture_original_party(original, before, site_controller.region_slot,
		float(interval.game_end), float(interval.action_end))
	if not captured.ok: return captured
	return {"ok": true, "party": captured.party, "complete": true, "token": str(before.party_id),
		"game_seconds": float(interval.game_end), "action_seconds": float(interval.action_end)}

func _region_can_publish_party_bind(nonce: String) -> bool:
	var ticket: Dictionary = _region_owner_bind_tickets.get(nonce, {})
	if ticket.get("kind") != "party-prepared" or not is_instance_valid(ticket.get("child")): return false
	var slot: RegionSaveSlot = ticket.slot
	if int(slot._marker.get("generation", 0)) != int(ticket.generation) or int(slot.region_registry().revision) != int(ticket.revision): return false
	for source: Dictionary in ticket.sources:
		var selected: Dictionary = slot.validate_region_live_party_proof(str(source.party.party_id), source.party, source.proof)
		if not selected.ok: return false
	if ticket.has("family_takeover"):
		var takeover: Dictionary = slot.validate_region_family_takeover_transition(str(ticket.party.party_id), ticket.party,
			ticket.source_proof, ticket.family_takeover)
		if not takeover.ok: return false
	elif ticket.has("family_departure"):
		var departure: Dictionary = slot.validate_region_family_departure_transition(str(ticket.party.party_id), ticket.party,
			ticket.source_proof, ticket.family_departure)
		if not departure.ok: return false
	elif ticket.has("family_transition"):
		var family: Dictionary = slot.validate_region_family_party_transition(str(ticket.party.party_id), ticket.party,
			ticket.source_proof, ticket.family_transition)
		if not family.ok: return false
	else:
		var raw_sources: Array = []
		for source: Dictionary in ticket.sources:
			var collected: Dictionary = RegionPartyRuntime.collect_source(source.party, source.roots, source.transport, source.fire,
				int(source.proof.generation), source.party.upkeep.get("original_runtime_mapping", {}))
			if not collected.ok: return false
			raw_sources.append(collected.source)
		var allocated: Dictionary = RegionPartyRuntime.allocate(raw_sources, str(ticket.party.content.travel_identity.namespace), int(ticket.generation) + 1)
		if not allocated.ok or var_to_bytes(allocated.mapping) != var_to_bytes(ticket.runtime_mapping): return false
	if _region_party_hash(ticket.party) != ticket.party_hash or RegionCheckpoint.state_hash(ticket.data.site) != ticket.body_hash \
			or RegionCheckpoint.state_hash({"graph": ticket.graph}) != ticket.graph_hash: return false
	return bool(_region_validate_party_graph(ticket.data, ticket.party, ticket.graph).get("ok", false))

func _region_discard_party_bind(nonce: String) -> void:
	var ticket: Dictionary = _region_owner_bind_tickets.get(nonce, {})
	if ticket.get("kind") != "party-prepared": return
	_region_discard_party_child(ticket.child)
	_region_owner_bind_tickets.erase(nonce)

func _region_discard_party_child(child: TerrainLab) -> void:
	if not is_instance_valid(child): return
	_region_party_bind_candidates.erase(child.get_instance_id())
	child.free()

func _region_discard_party_children(children: Array) -> void:
	for child: TerrainLab in children: _region_discard_party_child(child)

func _region_gameplay_live_party_materialize(event: Dictionary) -> Dictionary:
	if str(event.get("payload", {}).get("contact_receipt", {}).get("kind", "")) == "npc_sea_sweep_boundary": return _region_gameplay_npc_sea_materialize(event)
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null: return SiteRuntime.fail("NO_REGION_SLOT")
	var current := slot.region_travel_party()
	if not current.ok: return current
	var incoming_token := str(event.get("payload", {}).get("token", ""))
	var incoming := not incoming_token.is_empty() and incoming_token != str(current.party.party_id) \
		and str(slot.region_registry().parties.get(incoming_token, {}).get("phase", "")) == "travelling"
	if not current.party.get("upkeep", {}).get("live", {}).is_empty() and not incoming:
		var original := slot.region_original_party_runtime_proof(str(current.party.party_id), current.party)
		if not original.ok: return original
		return original.lab._region_gameplay_finish_live_life(event)
	var prepared := slot.prepare_region_live_party(event)
	if not prepared.ok: return prepared
	var binding := prepare_region_party_live_bind(prepared.token, prepared.party, slot, prepared.proof)
	if not binding.ok: return binding
	var committed := slot.commit_region_live_party(prepared.token, prepared.party, prepared.proof, binding, prepared.incoming)
	if not committed.ok:
		if committed.get("code") != "COMMITTED_UNBOUND": binding.discard.call()
		return committed
	return _region_gameplay_finish_live_life(event)

static func _region_merge_original_party_values(current: Dictionary, accepted: Dictionary) -> void:
	for key: Variant in current.keys():
		if not accepted.has(key): current.erase(key)
	for key: Variant in accepted:
		if current.get(key) is Dictionary and accepted[key] is Dictionary:
			_region_merge_original_party_values(current[key], accepted[key])
		else: current[key] = accepted[key].duplicate(true) if accepted[key] is Dictionary or accepted[key] is Array else accepted[key]

func _region_party_bind_admission(ticket: Dictionary, data: TerrainData) -> Dictionary:
	var slot: RegionSaveSlot = ticket.get("slot")
	if slot == null or not ticket.get("party") is Dictionary or ticket.get("data") != data:
		return SiteRuntime.fail("STALE_REGION_PARTY_BIND")
	var token := str(ticket.party.get("party_id", ""))
	if ticket.kind == "party-candidate":
		var host := get_parent() as TerrainLab
		var record: Dictionary = host._region_party_bind_candidates.get(get_instance_id(), {}) if host != null else {}
		if not restore_only or record.get("child") != self or record.get("data") != data \
				or record.get("party_hash") != _region_party_hash(ticket.party) or record.get("graph") != ticket.graph:
			return SiteRuntime.fail("STALE_REGION_PARTY_BIND")
		for source: Dictionary in ticket.sources:
			var selected: Dictionary = slot.validate_region_live_party_proof(str(source.party.party_id), source.party, source.proof)
			if not selected.ok: return selected
	elif ticket.kind in ["party-bootstrap", "party-published"]:
		var selected: Dictionary = slot.validate_region_live_party_proof(token, ticket.party, ticket.proof)
		if not selected.ok: return selected
		if ticket.kind == "party-bootstrap":
			var host := get_parent() as TerrainLab
			var record: Dictionary = host._region_party_bind_candidates.get(get_instance_id(), {}) if host != null else {}
			if not restore_only or record.get("child") != self or record.get("data") != data \
					or record.get("proof") != ticket.proof: return SiteRuntime.fail("STALE_REGION_PARTY_BIND")
		elif selected.original_live_graph != ticket.graph: return SiteRuntime.fail("STALE_REGION_PARTY_GRAPH")
	else: return SiteRuntime.fail("INVALID_REGION_PARTY_BIND")
	if not ticket.graph.is_empty():
		var graph := _region_validate_party_graph(data, ticket.party, ticket.graph)
		if not graph.ok: return graph
	return SiteRuntime.ok()

func _region_party_bootstrap_child(token: String, party: Dictionary, slot: RegionSaveSlot,
		proof: Dictionary, graph: Dictionary) -> Dictionary:
	if graph.is_empty() and party.get("upkeep", {}).has("live"):
		return SiteRuntime.fail("MISSING_ORIGINAL_PARTY_GRAPH", "Selected live party cannot be restored from a fresh skeleton")
	var view := _region_party_domain_view(token, party, slot, graph)
	if not view.ok: return view
	var data: TerrainData = view.data
	if not graph.is_empty():
		var validated := _region_validate_party_graph(data, party, graph)
		if not validated.ok: return validated
	var created := _region_new_bind_child(data)
	if not created.ok: return created
	var child: TerrainLab = created.child
	child.site_controller.region_slot = slot
	child.site_controller._auto_save_blocked = true
	child._region_party_token = token
	child._region_party_input_hash = _region_party_hash(party)
	var record := {"child": child, "slot": slot, "data": data, "proof": proof.duplicate(true), "party": party,
		"party_hash": child._region_party_input_hash, "graph": graph}
	_region_party_bind_candidates[child.get_instance_id()] = record
	var context: Dictionary = graph.get("context", {})
	var owners := _region_party_scene_owners(graph.owners) if not graph.is_empty() else {}
	var nonce := "party_bootstrap_" + Crypto.new().generate_random_bytes(16).hex_encode()
	child._region_owner_bind_tickets[nonce] = {"kind": "party-bootstrap", "data": data,
		"body_hash": RegionCheckpoint.state_hash(data.site), "context": context, "owners": owners,
		"slot": slot, "proof": proof.duplicate(true), "party": party, "graph": graph}
	child.bind_terrain(data, {"ok": true, "crowd_site": null, "region_bind_token": nonce})
	var bound: Dictionary = child._region_bind_receipt_value.duplicate(true)
	child._region_owner_bind_tickets.erase(nonce)
	if child.terrain != data or child._region_bound_data != data or bound.get("owners_restored") != true:
		_region_party_bind_candidates.erase(child.get_instance_id())
		child.free()
		return SiteRuntime.fail("REGION_CHILD_BIND_FAILED", str(bound))
	child.set_process(false)
	child.set_process_input(false)
	child.set_process_unhandled_input(false)
	for actor: TerrainTestCharacter in child.combat_actors: actor.set_process(false)
	for team: TerrainArmy in child.combat_armies: team.set_process(false)
	# Ordinary departure guard proved an idle graph. The complete selected graph
	# supplies all pending deaths when present; no empty timer replaces it.
	if graph.is_empty():
		for identity: String in party.upkeep.get("original_deaths", {}):
			child.site_controller._pending_deaths[int(identity)] = float(party.upkeep.original_deaths[identity])
	return SiteRuntime.ok("", {"child": child, "data": data, "record": record, "receipt": bound})

func _region_party_capture_clock(context: Dictionary) -> Dictionary:
	if terrain == null or not terrain.has_meta(&"region_party_owner"):
		return SiteRuntime.ok("", {"party": false})
	var owner: Variant = terrain.get_meta(&"region_party_owner")
	var slot: RegionSaveSlot = site_controller.region_slot
	if not owner is Dictionary or slot == null or str(owner.get("token", "")).is_empty() \
			or str(terrain.site.get("id", "")) != "travel:" + str(owner.token) \
			or _region_party_token != str(owner.token) or _region_party_input_hash != str(owner.get("party_hash", "")):
		return SiteRuntime.fail("STALE_REGION_PARTY_OWNER")
	var actual: Dictionary = slot.get_meta(&"region_party_owner_labs", {})
	if actual.get(str(owner.token)) != self:
		var host := get_parent() as TerrainLab
		var accepted: Dictionary = host._region_party_bind_candidates.get(get_instance_id(), {}) if host != null else {}
		if not restore_only or accepted.get("child") != self or accepted.get("slot") != slot \
				or accepted.get("data") != terrain or accepted.get("party_hash") != _region_party_input_hash:
			return SiteRuntime.fail("INVALID_REGION_PARTY_CAPTURE")
	var registry: Dictionary = slot.region_registry()
	var mode: Dictionary = registry.modes.get("travel:" + str(owner.token), {})
	var expected := {"source_generation": int(slot._marker.get("generation", 0)), "runtime_revision": int(registry.revision),
		"game_seconds": float(slot.control.logical_game_seconds), "action_seconds": float(slot.control.fire_clock.action_seconds),
		"fire_epoch": str(slot.control.fire_clock.epoch), "fire_sequence": int(slot.control.fire_clock.sequence),
		"mode_revision": int(mode.get("revision", 0))}
	var checked := RegionCheckpoint.validate_context(context, expected)
	if not checked.ok: return checked
	return SiteRuntime.ok("", {"party": true, "token": str(owner.token)})

func _region_party_capture_fire_state(context: Dictionary) -> Dictionary:
	if terrain.has_meta(&"fire_structure_step"): return SiteRuntime.fail("REGION_STRUCTURE_EFFECT_RUNNING")
	var raw: Dictionary = terrain.site.get("fire", {}).duplicate(true)
	if not raw.is_empty():
		if not raw.get("receipt_ids") is Dictionary: return SiteRuntime.fail("INVALID_FIRE_RECEIPT")
		var receipts := {}
		for identity: Variant in raw.receipt_ids: receipts[str(identity)] = raw.receipt_ids[identity]
		raw.receipt_ids = receipts
	var normalized: Variant = SiteRuntime._fire_snapshot_json_copy(raw)
	if not normalized is Dictionary or not SiteRuntime._fire_snapshot_json(normalized): return SiteRuntime.fail("INVALID_FIRE_SNAPSHOT")
	var valid := SiteRuntime.validate_fire_snapshot(terrain, normalized, fire_action_cursor)
	return SiteRuntime.ok("", {"state": normalized}) if valid.ok else valid

func _region_party_domain_view(token: String, party: Dictionary, slot: RegionSaveSlot,
		graph: Dictionary = {}) -> Dictionary:
	if token != str(party.get("party_id", "")) or not RegionPartyTravel.validate_identity(party.get("content", {}).get("travel_identity")):
		return SiteRuntime.fail("INVALID_PARTY_OWNER")
	var live: Dictionary = party.get("upkeep", {}).get("live", {})
	var physical := str(party.get("origin_site_id", ""))
	var opened := {}
	var geometry := {}
	var data: TerrainData
	if not live.is_empty():
		geometry = slot.region_live_party_geometry(party, live.get("geometry_proof", {}))
		if not geometry.ok: return geometry
		data = geometry.data
		var leader: Dictionary = live.frame.people.get(str(int(party.leader_person_id)), {})
		if not leader.get("world_cell") is Array or leader.world_cell.size() != 2: return SiteRuntime.fail("INVALID_REGION_PARTY_FRAME")
		var coordinate := Vector2i(floori(float(leader.world_cell[0]) / 100.0), -floori(float(leader.world_cell[1]) / 100.0))
		physical = RegionPartyGrid.site_id(str(slot.pin.atlas_id), coordinate)
		for source: Dictionary in geometry.sources:
			if source.site == [coordinate.x, coordinate.y]: opened = {"data": source.data}; break
		if opened.is_empty(): return SiteRuntime.fail("MISSING_REGION_PARTY_GEOMETRY")
	else:
		var prefix := str(slot.pin.atlas_id) + ":"
		if not physical.begins_with(prefix): return SiteRuntime.fail("WRONG_SITE")
		var parts := physical.trim_prefix(prefix).split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return SiteRuntime.fail("WRONG_SITE")
		var coordinate := Vector2i(int(parts[0]), int(parts[1]))
		var selected := slot.effective_site_path(coordinate)
		if not selected.ok: return selected
		opened = slot._load_checked(str(selected.path), coordinate)
		if not opened.ok: return opened
		data = RegionPartyEnv.navigation_for_state(opened.data, opened.data.site)
	var content: Dictionary = party.content
	var view: Dictionary = opened.data.site.duplicate(true)
	for field: String in ["region_snapshot", "region_life_events", "fire_owners", "fire", "fire_settlement", "initial_scenario", "family"]:
		view.erase(field)
	for field: String in ["features", "changes", "terrain_changes", "inventory", "water_status", "water_links", "building_economy", "housing", "captivity", "escort_orders"]:
		view[field] = {}
	view.zones = []; view.notices = []; view.total_produced = 0; view.combat_left = 0.0
	for field: String in RegionPartyTravel.CONTENT_DICTS: view[field] = content.get(field, {}).duplicate(true)
	view.armies = content.get("armies", []).duplicate(true)
	view.id = "travel:" + token
	# Derived view of the SAME party GAME clock; never a Site publication.
	var game := float(party.upkeep.at)
	view.minute = floori(game / 60.0)
	view.phase = game / 60.0 - float(view.minute)
	view.actor_presence_version = 1
	view.controlled_person_id = int(content.get("controlled_person_id", party.leader_person_id))
	view.army_trial_active = not view.armies.is_empty()
	view.travel_identity = content.travel_identity.duplicate(true)
	view.organization_refs = content.get("organization_refs", SiteEquipmentOrders._portable_empty()).duplicate(true)
	view.manual.cargo = content.get("manual_cargo", {}).duplicate(true) if view.actors.has("player") else {}
	view.worker.cargo = content.get("manual_cargo", {}).duplicate(true) if view.actors.has("npc") else {}
	for clocked: Dictionary in [view.manual, view.worker]: clocked.target = ""; clocked.progress = 0.0
	view.worker_enabled = false; view.paused = false
	if content.has("family"): view.family = content.family.duplicate(true)
	for field: String in ["next_person_id", "army_next_team", "next_vehicle", "next_item", "next_loot"]:
		view[field] = int(content.get("counters", {}).get(field, view.get(field, 1)))
	var transport: Dictionary = content.get("fire_template", {}).duplicate(true)
	if not graph.is_empty(): transport = graph.owners.transport.fire_transport.duplicate(true)
	elif not transport.is_empty():
		transport.orders = content.get("fire_orders", []).duplicate(true)
		transport.member_cursor = content.get("fire_member_cursor", []).duplicate(true)
	if transport.is_empty(): view.erase("fire_transport")
	else: view.fire_transport = transport
	data.site = view
	data.set_meta(&"region_party_runtime_mapping", party.upkeep.get("original_runtime_mapping", {}).duplicate(true))
	data.resource_base = {}; data.resources_at = {}
	for hook: StringName in [&"region_snapshot_capture", &"region_bind_receipt", &"site_garrison_lab", &"region_checkpoint_context", &"siege_event_guard", &"fire_event_guard", &"fire_owner_snapshot", &"fire_transport_snapshot", &"region_fire_transport_snapshot", &"fire_boundary", &"fire_structure_step", &"ship_journey_active", &"region_operation_pending", &"ship_vehicle_in_journey"]:
		if data.has_meta(hook): data.remove_meta(hook)
	var fingerprint := _region_party_hash(party)
	data.set_meta(&"region_party_owner", {"token": token, "physical_source": physical, "party_hash": fingerprint})
	data.set_meta(&"region_party_physical_source", opened.data)
	data.set_meta(&"fire_completed_action_end", float(transport.get("action_cursor", party.upkeep.get("owner_action_seconds", slot.control.fire_clock.action_seconds))))
	data.set_meta(&"region_party_sea_cursor", party.upkeep.get("sea_cursor", {}).duplicate(true))
	if not live.is_empty():
		data.set_meta(&"region_party_world_frame", live.frame.duplicate(true))
		data.set_meta(&"region_party_geometry_sources", geometry.sources)
		data.set_meta(&"region_party_geometry_proof", geometry.geometry_proof)
	if not graph.is_empty():
		var lab_cursor := RegionOwnerSnapshot.peek_values(graph.owners.scene, "lab", graph.context)
		if not lab_cursor.ok: return lab_cursor
		var fire := SiteRuntime.validate_fire_snapshot(data, graph.owners.transport.fire_state, float(lab_cursor.value.fire_action_cursor))
		if not fire.ok: return fire
		if not fire.state.is_empty(): data.site.fire = fire.state
	if str(party.get("mode", "land")) == "sea" and party.upkeep.has("sea_cursor"):
		var plan: Dictionary = slot.region_travel_plan() if str(slot.region_travel_journey().get("token", "")) == token else slot._region_npc_plan(token)
		if not plan.ok: return plan
		var projection: Dictionary = slot.region_sea_pose_projection(plan.plan, party)
		if not projection.ok: return projection
		data.set_meta(&"region_party_hull_poses", projection.poses)
	var original_vehicles := SiteStore._validate_vehicles(data, view, true, graph.get("context", {}))
	if not original_vehicles.ok: return original_vehicles
	var hull := SiteVehicleTransport.validate_region_ship_projection(data)
	if not hull.ok: return hull
	if RegionPartyTravel._body_records(view).size() != party.person_ids.size(): return SiteRuntime.fail("PARTY_BODY_CLOSURE")
	if view.actors.size() > 2 or view.actors.keys().any(func(key: Variant) -> bool: return str(key) not in ["player", "npc"]):
		return SiteRuntime.fail("PARTY_ACTOR_CAPACITY")
	return SiteRuntime.ok("", {"data": data})

static func _region_party_scene_owners(owners: Dictionary) -> Dictionary:
	var scene := {"scene": owners.scene}
	if owners.has("fire_boundary_receipt"): scene.fire_boundary_receipt = owners.fire_boundary_receipt
	return scene

func _region_prepare_party_graph_bind(token: String, candidate: Dictionary, slot: RegionSaveSlot,
		accepted: Dictionary, purpose: String) -> Dictionary:
	var source_proof: Dictionary = accepted.sources[0].proof
	var selected_rows: Array = []
	for source: Dictionary in accepted.sources: selected_rows.append(source.proof)
	if selected_rows.size() not in [1, 2]: return SiteRuntime.fail("INVALID_REGION_PARTY_SOURCES")
	var sources: Array = []
	var children: Array = []
	var raw_sources: Array = []
	var effects_complete := true
	for index: int in accepted.sources.size():
		var selected: Dictionary = accepted.sources[index]
		var selected_proof: Dictionary = selected.proof
		var source_token := str(selected_proof.token)
		var maps: Dictionary = selected.maps
		var projection: Dictionary = selected.coordinate_projection
		var projected := {"party": selected.projected_party}
		var restored := _region_party_bootstrap_child(source_token, selected.party, slot, selected_proof, selected.original_live_graph)
		if not restored.ok: _region_discard_party_children(children); return restored
		var child: TerrainLab = restored.child
		children.append(child)
		# A selected snapshot describes its captured point. A newly queued
		# canonical endpoint still belongs to this materialization barrier.
		var source_effects := bool(selected.original_live_graph.get("context", {}).get("effects_complete", true)) \
			and child._region_point_pending.is_empty() and not child._region_point_consuming and slot.pending_region_events().is_empty()
		var source_context: Dictionary = slot.region_party_checkpoint_context(source_token, "region_barrier", source_effects, {"party_source": source_token})
		if not source_context.ok: _region_discard_party_children(children); return source_context
		var captured := child.capture_region_party_owner_graph(source_token, selected.party, slot, source_context.context)
		if not captured.ok: _region_discard_party_children(children); return captured
		var graph: Dictionary = captured.original_live_graph
		var symbolic := RegionOwnerSnapshot.validate_for_bind(graph.owners.scene, func(_key: String, _kind: int) -> bool: return true, graph.context)
		if not symbolic.ok: _region_discard_party_children(children); return symbolic
		var legacy := child._region_project_legacy_noise(symbolic.roots, selected.party, selected_proof)
		if not legacy.ok: _region_discard_party_children(children); return legacy
		symbolic.roots = legacy.roots
		var raw: Dictionary = RegionPartyRuntime.collect_source(selected.party, symbolic.roots, graph.owners.transport.fire_transport,
			graph.owners.transport.fire_state, int(selected_proof.generation), selected.party.upkeep.get("original_runtime_mapping", {}))
		if not raw.ok: _region_discard_party_children(children); return raw
		raw_sources.append(raw.source)
		sources.append({"party": selected.party, "proof": selected_proof, "projected": projected.party, "projection": projection,
			"maps": maps, "roots": symbolic.roots, "transport": graph.owners.transport.fire_transport,
			"fire": graph.owners.transport.fire_state, "graph": graph, "raw_runtime": raw.source})
		effects_complete = effects_complete and bool(graph.context.effects_complete)
	var allocated: Dictionary = RegionPartyRuntime.allocate(raw_sources, str(candidate.content.travel_identity.namespace), int(source_proof.generation) + 1)
	if not allocated.ok: _region_discard_party_children(children); return allocated
	var mapping: Dictionary = allocated.mapping
	var composed: Dictionary = RegionPartyRuntime.compose_candidate(candidate, sources, mapping)
	if not composed.ok: _region_discard_party_children(children); return composed
	candidate = composed.party
	var context: Dictionary = slot.region_party_checkpoint_context(token, purpose, effects_complete, {"party_live": token})
	if not context.ok: _region_discard_party_children(children); return context
	var roots: Array = []
	var transports: Array = []
	for index: int in sources.size():
		var source: Dictionary = sources[index]
		var coordinates := RegionPartyTravel.project_owner_coordinates(source.roots, source.projection)
		if not coordinates.ok: _region_discard_party_children(children); return coordinates
		var army_indices := {}
		for old_index: int in source.projected.content.armies.size():
			var current_team := int(source.maps.get("team", {}).get(str(int(source.projected.content.armies[old_index].team_id)),
				int(source.projected.content.armies[old_index].team_id)))
			for target_index: int in candidate.content.armies.size():
				if int(candidate.content.armies[target_index].team_id) == current_team: army_indices[str(old_index)] = target_index
		var remapped: Dictionary = RegionPartyRuntime.remap_owner_roots(coordinates.roots, mapping.sources[index], source.maps,
			{"source_owner": str(source.proof.owner), "destination_owner": "travel:" + token, "army_indices": army_indices,
				"default_offset": source.projection.default_offset, "next": mapping.next})
		if not remapped.ok: _region_discard_party_children(children); return remapped
		roots.append(remapped.roots)
		var projected_transport: Dictionary = RegionPartyRuntime.project_transport(source.transport, source.projection)
		if not projected_transport.ok: _region_discard_party_children(children); return projected_transport
		var remapped_transport: Dictionary = RegionPartyRuntime.remap_transport(projected_transport.transport, mapping, str(source.proof.owner),
			str(source.party.content.travel_identity.namespace), str(source.proof.party_hash), source.maps)
		if not remapped_transport.ok: _region_discard_party_children(children); return remapped_transport
		transports.append(remapped_transport.transport)
	var merged: Dictionary = RegionPartyRuntime.merge_owner_roots(roots, "travel:" + token)
	if not merged.ok: _region_discard_party_children(children); return merged
	var transport: Dictionary = RegionPartyRuntime.merge_transports(transports)
	if not transport.ok: _region_discard_party_children(children); return transport
	var fire: Dictionary = RegionPartyRuntime.merge_fire_states(sources, mapping, "travel:" + token)
	if not fire.ok: _region_discard_party_children(children); return fire
	var wire := RegionOwnerSnapshot.capture_bind_roots(merged.roots, context.context)
	if not wire.ok: _region_discard_party_children(children); return wire
	var owners := {"scene": wire.state, "transport": {"version": 1, "fire_transport": transport.transport, "fire_state": fire.state}}
	var boundary: Dictionary = merged.roots.fire_meta.get("fire_boundary", {})
	if not boundary.is_empty():
		owners.fire_boundary_receipt = {"site_id": "travel:" + token, "action_end": float(boundary.action_end),
			"resource_count": boundary.resources.size(), "feature_count": boundary.features.size(),
			"token": str(context.context.token), "action_start_cursor": float(merged.roots.lab.fire_action_cursor)}
	var graph := {"version": 1, "token": token, "party_hash": _region_party_hash(candidate), "context": context.context, "owners": owners}
	var target := _region_party_domain_view(token, candidate, slot, graph)
	if not target.ok: _region_discard_party_children(children); return target
	var graph_checked := _region_validate_party_graph(target.data, candidate, graph)
	if not graph_checked.ok: _region_discard_party_children(children); return graph_checked
	var created := _region_new_bind_child(target.data)
	if not created.ok: _region_discard_party_children(children); return created
	var child: TerrainLab = created.child
	child.site_controller.region_slot = slot
	child.site_controller._auto_save_blocked = true
	child._region_party_token = token
	child._region_party_input_hash = _region_party_hash(candidate)
	var record := {"child": child, "slot": slot, "data": target.data, "party": candidate,
		"party_hash": child._region_party_input_hash, "graph": graph, "sources": sources, "proofs": selected_rows}
	_region_party_bind_candidates[child.get_instance_id()] = record
	var bootstrap := "party_candidate_" + Crypto.new().generate_random_bytes(16).hex_encode()
	child._region_owner_bind_tickets[bootstrap] = {"kind": "party-candidate", "data": target.data,
		"body_hash": RegionCheckpoint.state_hash(target.data.site), "context": context.context, "owners": _region_party_scene_owners(owners),
		"slot": slot, "party": candidate, "graph": graph, "proofs": selected_rows, "sources": sources}
	child.bind_terrain(target.data, {"ok": true, "crowd_site": null, "region_bind_token": bootstrap})
	child._region_owner_bind_tickets.erase(bootstrap)
	_region_discard_party_children(children)
	if child.terrain != target.data or child._region_bound_data != target.data or child._region_bind_receipt_value.get("owners_restored") != true:
		_region_discard_party_child(child); return SiteRuntime.fail("REGION_CHILD_BIND_FAILED", str(child._region_bind_receipt_value))
	child.set_process(false); child.set_process_input(false); child.set_process_unhandled_input(false)
	for actor: TerrainTestCharacter in child.combat_actors: actor.set_process(false)
	for team: TerrainArmy in child.combat_armies: team.set_process(false)
	var captured := child.capture_region_party_owner_graph(token, candidate, slot, context.context)
	if not captured.ok: _region_discard_party_child(child); return captured
	graph = captured.original_live_graph
	var nonce := "party_live_" + Crypto.new().generate_random_bytes(16).hex_encode()
	_region_owner_bind_tickets[nonce] = {"kind": "party-prepared", "data": target.data, "child": child, "slot": slot,
		"source_party": sources[0].party, "source_proof": source_proof, "proofs": selected_rows, "sources": sources,
		"runtime_mapping": mapping.duplicate(true), "raw_sources": raw_sources.duplicate(true),
		"party": candidate, "party_hash": _region_party_hash(candidate), "graph": graph,
		"graph_hash": RegionCheckpoint.state_hash({"graph": graph}), "body_hash": RegionCheckpoint.state_hash(target.data.site),
		"generation": int(source_proof.generation), "revision": int(source_proof.revision),
		"context": graph.context, "owners": _region_party_scene_owners(graph.owners)}
	return SiteRuntime.ok("", {"data": target.data, "party": candidate, "original_live_graph": graph, "token": nonce,
		"runtime_mapping": mapping, "can_publish": _region_can_publish_party_bind.bind(nonce),
		"publish": _region_publish_party_departure_bind.bind(nonce) if candidate.get("controller") == "npc" else _region_publish_party_bind.bind(nonce), "discard": _region_discard_party_bind.bind(nonce)})

func _region_publish_original_party_upkeep(original: TerrainLab, candidate: Dictionary) -> Dictionary:
	var content: Dictionary = candidate.get("content", {})
	var people: Dictionary = RegionPartyTravel._body_records(content)
	var targets := {}
	for identity: int in people:
		var target: Dictionary = original._original_person_target(identity)
		if target.is_empty() or absf(float(target.hp) - float(people[identity].hp)) > ACTION_TIME_EPSILON:
			return SiteRuntime.fail("PARTY_BODY_CLOSURE")
		targets[identity] = target
	for field: String in ["team_supply", "person_supply"]:
		var current: Dictionary = original.terrain.site.get(field, {})
		var accepted: Dictionary = content.get(field, {})
		if current.keys().size() != accepted.keys().size(): return SiteRuntime.fail("PARTY_SUPPLY_CLOSURE")
		for key: Variant in accepted:
			if not current.has(key): return SiteRuntime.fail("PARTY_SUPPLY_CLOSURE")
	# All ownership checks precede changes. Preserve stock/holder Dictionary
	# identity because original inventory and feeding queries retain those links.
	for field: String in ["team_supply", "person_supply"]:
		_region_merge_original_party_values(original.terrain.site[field], content.get(field, {}))
	for identity: int in people:
		var body: Dictionary = people[identity]
		var target: Dictionary = targets[identity]
		var owner: Variant = target.owner
		var unit := int(target.unit)
		var actual: Variant = owner.combat_units[unit] if unit >= 0 else owner
		for field: String in ["fatigue", "fatigue_rest"]:
			if body.has(field): PersonFatigue.write(actual, field, float(body[field]))
		if unit >= 0:
			if body.has("ko"): owner.combat_hot_set(unit, &"ko", float(body.ko))
			if body.has("work_resting"): actual.work_resting = bool(body.work_resting)
			if body.has("cargo"): _region_merge_original_party_values(actual.cargo, body.cargo)
			if body.has("item_state"): _region_merge_original_party_values(actual.item_state, body.item_state)
		else:
			if body.has("knockout_left"): owner.knockout_left = float(body.knockout_left)
			if body.has("work_resting"): owner.work_resting = bool(body.work_resting)
			if body.has("item_state"): _region_merge_original_party_values(owner.item_state, body.item_state)
	for saved: Dictionary in content.get("armies", []):
		if not saved.has("team_fatigue"): continue
		for team: TerrainArmy in original.combat_armies:
			if int(team.team_id) == int(saved.team_id) and not team.team_fatigue.is_empty():
				for field: String in ["fatigue", "fatigue_rest", "active"]:
					if saved.team_fatigue.has(field): team.team_fatigue[field] = saved.team_fatigue[field]
	var cargo: Dictionary = original.terrain.site.manual.cargo if content.get("actors", {}).has("player") else original.terrain.site.worker.cargo
	_region_merge_original_party_values(cargo, content.get("manual_cargo", {}))
	return SiteRuntime.ok()

func _region_publish_party_bind(proof: Dictionary, nonce: String) -> Dictionary:
	var ticket: Dictionary = _region_owner_bind_tickets.get(nonce, {})
	if ticket.get("kind") != "party-prepared": return SiteRuntime.fail("STALE_REGION_PARTY_BIND")
	var slot: RegionSaveSlot = ticket.slot
	var token := str(ticket.party.party_id)
	var selected: Dictionary = slot.validate_region_live_party_proof(token, ticket.party, proof)
	if not selected.ok: return selected
	if int(proof.generation) != int(ticket.generation) + 1 or str(proof.party_hash) != ticket.party_hash \
			or selected.original_live_graph != ticket.graph \
			or RegionCheckpoint.state_hash(ticket.data.site) != ticket.body_hash:
		return SiteRuntime.fail("STALE_REGION_PARTY_COMMIT")
	var graph := _region_validate_party_graph(ticket.data, ticket.party, ticket.graph)
	if not graph.ok: return graph
	ticket.kind = "party-published"
	ticket.proof = proof.duplicate(true)
	_region_party_token = token
	_region_party_input_hash = ticket.party_hash
	bind_terrain(ticket.data, {"ok": true, "crowd_site": null, "region_bind_token": nonce})
	var bound: Dictionary = _region_bind_receipt_value.duplicate(true)
	if terrain != ticket.data or _region_bound_data != ticket.data or bound.get("owners_restored") != true:
		return SiteRuntime.fail("COMMITTED_UNBOUND", "Selected party and full original graph remain resumable")
	_region_publish_party_owner_index(slot, token)
	_region_discard_party_child(ticket.child)
	_region_owner_bind_tickets.erase(nonce)
	bound.owner = "travel:" + token
	bound.generation = int(proof.generation)
	bound.mode = "live"
	bound.backend = "gd"
	bound.consumer = "original_party"
	
	return bound

func _region_publish_party_owner_index(slot: RegionSaveSlot, token: String) -> void:
	# The true selected Site file remains its own authority. A re-used Lab may
	# consume one party; it cannot remain listed as that cold Site's body owner.
	for key: String in slot._region_original_labs.keys():
		if slot._region_original_labs[key] == self: slot._region_original_labs.erase(key)
	var cached: Dictionary = slot.get_meta(&"region_party_owner_labs", {})
	var old: TerrainLab = cached.get(token)
	cached[token] = self
	slot.set_meta(&"region_party_owner_labs", cached)
	if is_instance_valid(old) and old != self and old.get_parent() == self:
		_region_party_bind_candidates.erase(old.get_instance_id())
		old.free()

func _region_validate_party_graph(data: TerrainData, party: Dictionary, graph: Dictionary) -> Dictionary:
	if graph.size() != 5 or graph.get("version") != 1 or graph.get("token") != party.get("party_id") \
			or graph.get("party_hash") != _region_party_hash(party) or not graph.get("owners") is Dictionary:
		return SiteRuntime.fail("INVALID_REGION_PARTY_GRAPH")
	var context: Variant = graph.get("context")
	var checked := RegionCheckpoint.validate_context(context)
	if not checked.ok: return checked
	var runtime_mapping: Variant = party.upkeep.get("original_runtime_mapping", {})
	if not runtime_mapping is Dictionary or not runtime_mapping.is_empty() and not RegionPartyRuntime.valid(runtime_mapping, str(party.content.travel_identity.namespace)):
		return SiteRuntime.fail("INVALID_REGION_RUNTIME_MAPPING")
	var owners: Dictionary = graph.owners
	if not owners.get("scene") is Dictionary or not owners.get("transport") is Dictionary \
			or owners.size() != 2 + int(owners.has("fire_boundary_receipt")):
		return SiteRuntime.fail("INVALID_REGION_PARTY_GRAPH")
	var transport: Dictionary = owners.transport
	if transport.size() != 3 or transport.get("version") != 1 or not transport.get("fire_transport") is Dictionary \
			or not transport.get("fire_state") is Dictionary:
		return SiteRuntime.fail("INVALID_REGION_PARTY_GRAPH")
	data = _region_detached_bind_data(data)
	data.site.fire_transport = transport.fire_transport.duplicate(true)
	var fire_transport := validate_fire_transport(data, transport.fire_transport)
	if not fire_transport.ok: return fire_transport
	var lab_cursor := RegionOwnerSnapshot.peek_values(owners.scene, "lab", context)
	if not lab_cursor.ok: return lab_cursor
	var fire := SiteRuntime.validate_fire_snapshot(data, transport.fire_state, float(lab_cursor.value.fire_action_cursor))
	if not fire.ok: return fire
	if absf(float(party.upkeep.get("at", -1.0)) - float(context.game_seconds)) > ACTION_TIME_EPSILON \
			or absf(float(party.upkeep.get("owner_action_seconds", -1.0)) - float(context.action_seconds)) > ACTION_TIME_EPSILON:
		return SiteRuntime.fail("UNSETTLED_PARTY_GRAPH")
	var scene := validate_region_owner_bind_payload(data, _region_party_scene_owners(owners), context)
	if not scene.ok: return scene
	return SiteRuntime.ok("", {"graph_hash": RegionCheckpoint.state_hash({"graph": graph}),
		"scene_owners": _region_party_scene_owners(owners), "context": checked.context})

func bind_selected_region_party(token: String, party: Dictionary, slot: RegionSaveSlot, proof: Dictionary) -> Dictionary:
	var duty := _region_capture_duty_cache()
	var result := _region_bind_selected_party(token, party, slot, proof)
	_region_restore_duty_cache(duty)
	return result

func capture_region_party_owner_graph(token: String, party: Dictionary, slot: RegionSaveSlot,
		context: Dictionary) -> Dictionary:
	if slot == null or site_controller.region_slot != slot or token != _region_party_token \
			or token != str(party.get("party_id", "")) or _region_party_hash(party) != _region_party_input_hash:
		return SiteRuntime.fail("STALE_REGION_PARTY_OWNER")
	var clock := _region_party_capture_clock(context)
	if not clock.ok or not clock.party: return clock if not clock.ok else SiteRuntime.fail("INVALID_REGION_PARTY_CAPTURE")
	if absf(float(party.get("upkeep", {}).get("at", -1.0)) - float(context.game_seconds)) > ACTION_TIME_EPSILON \
			or absf(float(party.upkeep.get("owner_action_seconds", -1.0)) - float(context.action_seconds)) > ACTION_TIME_EPSILON:
		return SiteRuntime.fail("UNSETTLED_PARTY")
	# Verify the actual ORIGINAL sparse body/holder closure before serialization.
	# _capture_positions records existing bodies and does not progress any work.
	var old_hash := _region_party_input_hash
	var old_owner: Dictionary = terrain.get_meta(&"region_party_owner", {}).duplicate(true)
	var original := _region_capture_original_party(self, party, slot)
	_region_party_input_hash = old_hash
	terrain.set_meta(&"region_party_owner", old_owner)
	if not original.ok: return original
	if var_to_bytes(original.party) != var_to_bytes(party):
		return SiteRuntime.fail("STALE_REGION_PARTY_BODY", "Original body/holder closure differs from submitted party")
	var scene := capture_region_owner_state(context)
	if not scene.ok: return scene
	var transport := capture_region_fire_transport(context, scene.owner_states)
	if not transport.ok: return transport
	var fire := _region_party_capture_fire_state(context)
	if not fire.ok: return fire
	var owners: Dictionary = scene.owner_states.duplicate(true)
	owners["transport"] = {"version": 1, "fire_transport": transport.state, "fire_state": fire.state}
	var graph := {"version": 1, "token": token, "party_hash": _region_party_hash(party),
		"context": context.duplicate(true), "owners": owners}
	var checked := _region_validate_party_graph(terrain, party, graph)
	if not checked.ok: return checked
	return SiteRuntime.ok("", {"party": original.party, "original_live_graph": graph})

func prepare_region_party_live_bind(token: String, candidate: Dictionary, slot: RegionSaveSlot,
		proof: Dictionary) -> Dictionary:
	var duty := _region_capture_duty_cache()
	var result := _region_prepare_party_live_bind(token, candidate, slot, proof)
	_region_restore_duty_cache(duty)
	return result

func _region_bind_selected_party(token: String, party: Dictionary, slot: RegionSaveSlot, proof: Dictionary) -> Dictionary:
	if slot == null or not is_inside_tree(): return SiteRuntime.fail("INVALID_PARTY_OWNER")
	var selected: Dictionary = slot.validate_region_live_party_proof(token, party, proof)
	if not selected.ok: return selected
	if selected.original_live_graph.is_empty(): return SiteRuntime.fail("MISSING_ORIGINAL_PARTY_GRAPH")
	var target := _region_party_domain_view(token, party, slot, selected.original_live_graph)
	if not target.ok: return target
	var checked := _region_validate_party_graph(target.data, party, selected.original_live_graph)
	if not checked.ok: return checked
	var generation := int(slot._marker.generation)
	var nonce := "party_selected_" + Crypto.new().generate_random_bytes(16).hex_encode()
	_region_owner_bind_tickets[nonce] = {"kind": "party-published", "data": target.data,
		"body_hash": RegionCheckpoint.state_hash(target.data.site), "context": selected.original_live_graph.context,
		"owners": _region_party_scene_owners(selected.original_live_graph.owners), "slot": slot,
		"party": party, "graph": selected.original_live_graph, "proof": proof}
	_region_party_token = token
	_region_party_input_hash = _region_party_hash(party)
	site_controller.region_slot = slot
	bind_terrain(target.data, {"ok": true, "crowd_site": null, "region_bind_token": nonce})
	var bound: Dictionary = _region_bind_receipt_value.duplicate(true)
	if int(slot._marker.generation) != generation or terrain != target.data or _region_bound_data != target.data \
			or bound.get("owners_restored") != true:
		return SiteRuntime.fail("COMMITTED_UNBOUND", "Selected original party graph remains the only resumable body")
	_region_owner_bind_tickets.erase(nonce)
	_region_publish_party_owner_index(slot, token)
	bound.owner = "travel:" + token; bound.generation = generation; bound.mode = "live"
	bound.backend = "gd"; bound.consumer = "original_party"
	bound.proof = proof.duplicate(true)
	# Fresh open invalidates persisted activations. This complete original bind
	# acknowledges only the already-selected live GD Party in this process.
	var mode: Dictionary = slot.region_registry().modes.get(str(bound.owner), {})
	if bound.get("complete") == true and mode.get("mode") == "live" and mode.get("backend") == "gd" \
			and mode.get("consumer") == "original_party" and int(mode.get("generation", -1)) == generation \
			and mode.get("activation", {}).get("complete") != true:
		var enabled := slot.activate_region_mode(str(bound.owner), "live", "original_party", bound, "gd")
		if not enabled.ok: return enabled
	return bound

static func _region_legacy_flights(roots: Dictionary) -> Array:
	var flights: Array = []
	for group: String in ["actor_hot", "army_hot"]:
		if not roots.get(group) is Dictionary:
			flights.append({"flight": {}, "kind": group, "owner": ""}); continue
		for key: Variant in roots[group]:
			var hot: Variant = roots[group][key]
			if not hot is Dictionary or not hot.get("projectiles") is Array:
				flights.append({"flight": {}, "kind": group, "owner": str(key)}); continue
			for flight: Variant in hot.projectiles:
				if flight is Dictionary and flight.get("mode") == "cell":
					flights.append({"flight": flight, "kind": group, "owner": str(key)})
	if not roots.get("lab") is Dictionary or not roots.lab.get("_region_point_contacts") is Array:
		flights.append({"flight": {}, "kind": "endpoint", "owner": null}); return flights
	for event: Variant in roots.lab._region_point_contacts:
		if not event is Dictionary or event.get("kind") != "legacy_ranged": continue
		if not event.get("packet") is Dictionary or not event.packet.get("flight") is Dictionary:
			flights.append({"flight": {}, "kind": "endpoint", "owner": null})
		else: flights.append({"flight": event.packet.flight, "kind": "endpoint", "owner": event.packet.get("owner")})
	return flights

func _region_legacy_noise(flight: Dictionary, target_id: int) -> int:
	var shooter_id := int(flight.shooter_id)
	var seed := terrain.seed_value
	if flight.has("_region_legacy_noise"):
		var lineage: Dictionary = flight._region_legacy_noise
		shooter_id = int(lineage.shooter_id)
		seed = int(lineage.seed)
		var target_ref: Variant = terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(target_id))
		if target_ref is Dictionary:
			target_id = int(lineage.targets.get(RegionPartyTravel.stable_key(target_ref), target_id))
	return (shooter_id * 73856093) ^ (int(flight.shot_id) * 83492791) ^ (target_id * 19349663) ^ seed

static func _region_legacy_scope(scope: Variant, mapping: Dictionary) -> bool:
	if not scope is Dictionary or scope.size() != 5 or not scope.get("namespace") is String \
		or str(scope.namespace).is_empty() or not scope.get("owner") is String or not str(scope.owner).begins_with("travel:") \
		or not scope.get("token") is String or scope.owner != "travel:" + str(scope.token) \
		or not RegionCheckpoint.integer(scope.get("source_generation")) or not scope.get("party_hash") is String \
		or str(scope.party_hash).length() != 64: return false
	if mapping.is_empty(): return false
	var epochs: Array = [mapping]
	for row: Dictionary in mapping.get("sources", []): epochs.append_array(row.get("prior", {}).get("epochs", []))
	for epoch: Dictionary in epochs:
		for source: Dictionary in epoch.get("sources", []):
			var matches := true
			for field: String in scope:
				if source.get(field) != scope[field]: matches = false; break
			if matches: return true
	return false

func _region_prepare_party_live_bind(token: String, candidate: Dictionary, slot: RegionSaveSlot,
		proof: Dictionary) -> Dictionary:
	if slot == null or not is_inside_tree() or str(candidate.get("party_id", "")) != token:
		return SiteRuntime.fail("INVALID_PARTY_OWNER")
	var accepted: Dictionary = slot.region_live_party_candidate_proof(token, candidate, proof)
	if not accepted.ok: return accepted
	return _region_prepare_party_graph_bind(token, candidate, slot, accepted, "region_materialize")

func _region_project_legacy_noise(roots: Dictionary, party: Dictionary, proof: Dictionary) -> Dictionary:
	var mapping: Dictionary = party.upkeep.get("original_runtime_mapping", {})
	var checked := _region_validate_legacy_roots(terrain, roots, mapping)
	if not checked.ok: return checked
	if proof.get("party_hash") != _region_party_hash(party) or str(proof.get("owner", "")) != "travel:" + str(party.party_id) \
		or proof.get("token") != party.party_id or not RegionCheckpoint.integer(proof.get("generation")):
		return SiteRuntime.fail("STALE_REGION_LEGACY_SOURCE")
	if not RegionPartyTravel.validate_identity(party.content.travel_identity) or party.content.travel_identity != terrain.site.get("travel_identity", {}): return SiteRuntime.fail("INVALID_REGION_LEGACY_SOURCE")
	var copy: Dictionary = RegionPartyRuntime._clone(roots, [], [])
	var refs: Dictionary = party.content.travel_identity.refs.person
	var targets := {}
	for current: String in refs: targets[RegionPartyTravel.stable_key(refs[current])] = int(current)
	var scope := {"namespace": str(party.content.travel_identity.namespace), "owner": str(proof.owner),
		"token": str(party.party_id), "source_generation": int(proof.generation), "party_hash": str(proof.party_hash)}
	for row: Dictionary in _region_legacy_flights(copy):
		var flight: Dictionary = row.flight
		if not refs.has(str(int(flight.shooter_id))): return SiteRuntime.fail("INVALID_REGION_LEGACY_SOURCE")
		if not flight.has("_region_legacy_noise"):
			flight["_region_legacy_noise"] = {"version": 1, "seed": terrain.seed_value, "shooter_id": int(flight.shooter_id),
				"shot_id": int(flight.shot_id), "shooter_ref": refs[str(int(flight.shooter_id))].duplicate(true),
				"targets": targets, "geometry": {"cells": flight.target_cell - flight.source_cell, "pixels": flight.goal - flight.origin,
					"eyes": [flight.source_eye, flight.goal_eye], "total": flight.total, "shooter_hash": RegionCheckpoint.state_hash(flight.shooter)},
				"source": scope}
		else:
			for key: String in targets:
				if not flight._region_legacy_noise.targets.has(key): flight._region_legacy_noise.targets[key] = targets[key]
	return SiteRuntime.ok("", {"roots": copy})

func _region_publish_party_departure_bind(proof: Dictionary, nonce: String) -> Dictionary:
	var ticket: Dictionary = _region_owner_bind_tickets.get(nonce, {})
	var npc_frame: bool = ticket.get("party", {}).get("controller") == "npc" and not ticket.get("party", {}).get("upkeep", {}).get("live", {}).is_empty() \
		and ticket.get("sources", []).size() == 2 and ticket.sources.all(func(source: Dictionary) -> bool: return source.party.get("controller") == "npc")
	if ticket.get("kind") != "party-prepared" or not ticket.has("family_departure") and not npc_frame or not is_instance_valid(ticket.get("child")):
		return SiteRuntime.fail("STALE_REGION_PARTY_BIND")
	var slot: RegionSaveSlot = ticket.slot
	var token := str(ticket.party.party_id)
	var selected: Dictionary = slot.validate_region_live_party_proof(token, ticket.party, proof)
	if not selected.ok: return selected
	if ticket.party.get("controller") != "npc" or int(ticket.party.content.get("controlled_person_id", 0)) != -1 \
			or int(proof.generation) != int(ticket.generation) + 1 or str(proof.party_hash) != ticket.party_hash \
			or selected.original_live_graph != ticket.graph or RegionCheckpoint.state_hash(ticket.data.site) != ticket.body_hash:
		return SiteRuntime.fail("STALE_REGION_PARTY_COMMIT")
	var graph := _region_validate_party_graph(ticket.data, ticket.party, ticket.graph)
	if not graph.ok: return graph
	var child: TerrainLab = ticket.child
	if child.terrain != ticket.data or child._region_bound_data != ticket.data or child._region_party_input_hash != ticket.party_hash:
		return SiteRuntime.fail("COMMITTED_UNBOUND", "Selected NPC source graph remains resumable")
	var actual := child.region_bind_receipt(ticket.data)
	if not actual.ok or actual.get("owners_restored") != true or actual.get("complete") != true:
		return SiteRuntime.fail("COMMITTED_UNBOUND", "Prepared original NPC owners are incomplete")
	var cached: Dictionary = slot.get_meta(&"region_party_owner_labs", {})
	var old: TerrainLab = cached.get(token)
	# Index the private complete original scene. Never bind/free the main scene;
	# it is retained for the separately committed remote heir target publication.
	cached[token] = child
	slot.set_meta(&"region_party_owner_labs", cached)
	child._region_bind_receipt_value.owner = "travel:" + token
	child._region_bind_receipt_value.mode = "live"
	child._region_bind_receipt_value.consumer = "original_party"
	var record: Dictionary = _region_party_bind_candidates.get(child.get_instance_id(), {})
	record.proof = proof.duplicate(true)
	record.graph = ticket.graph
	_region_party_bind_candidates[child.get_instance_id()] = record
	if is_instance_valid(old) and old != self and old != child and old.get_parent() == self: _region_discard_party_child(old)
	_region_owner_bind_tickets.erase(nonce)
	var bound := child.region_bind_receipt(ticket.data)
	bound.proof = proof.duplicate(true)
	return bound

func _region_selected_party_owner(token: String, party: Dictionary, slot: RegionSaveSlot) -> Dictionary:
	var current: Dictionary = slot.region_original_party_runtime_proof(token, party)
	if current.ok:
		var lab: TerrainLab = current.lab
		var receipt: Dictionary = lab.region_bind_receipt(lab.terrain)
		return SiteRuntime.ok("", {"handled": true, "lab": lab, "receipt": receipt, "proof": current.proof,
			"complete": bool(receipt.get("complete", false)), "token": token, "owner": "travel:" + token,
			"generation": int(current.proof.generation), "consumer": "original_party",
			"effects_complete": bool(receipt.get("effects_complete", true)),
			"zero_world_only": bool(receipt.get("zero_world_only", false))})
	var selected: Dictionary = slot.validate_region_live_party_proof(token, party,
		slot.region_live_party_proof(token).get("proof", {}))
	if not selected.ok: return selected.merged({"handled": true}, true)
	if selected.original_live_graph.is_empty():
		return SiteRuntime.fail("MISSING_ORIGINAL_PARTY_GRAPH").merged({"handled": true}, true) \
			if party.get("upkeep", {}).has("live") else {"ok": true, "handled": false}
	var cached: Dictionary = slot.get_meta(&"region_party_owner_labs", {})
	var original: TerrainLab = cached.get(token)
	if is_instance_valid(original) and original._region_party_token == token \
			and original._region_party_input_hash == _region_party_hash(party) and original._region_bound_data == original.terrain \
			and original._region_bind_receipt_value.get("owners_restored") == true:
		return SiteRuntime.ok("", {"handled": true, "lab": original, "receipt": original.region_bind_receipt(original.terrain), "complete": bool(original._region_bind_receipt_value.get("complete", false)), "token": token,
			"owner": "travel:" + token, "generation": int(selected.proof.generation), "consumer": "original_party",
			"effects_complete": bool(original._region_bind_receipt_value.get("effects_complete", true)),
			"zero_world_only": bool(original._region_bind_receipt_value.get("zero_world_only", false))})
	var restored := _region_party_bootstrap_child(token, party, slot, selected.proof, selected.original_live_graph)
	if not restored.ok: return restored.merged({"handled": true}, true)
	cached[token] = restored.child
	slot.set_meta(&"region_party_owner_labs", cached)
	if is_instance_valid(original) and original != restored.child and original.get_parent() == self: _region_discard_party_child(original)
	return SiteRuntime.ok("", {"handled": true, "lab": restored.child, "receipt": restored.receipt, "complete": bool(restored.receipt.get("complete", false)), "token": token,
		"owner": "travel:" + token, "generation": int(selected.proof.generation), "consumer": "original_party",
		"effects_complete": bool(restored.receipt.get("effects_complete", true)),
		"zero_world_only": bool(restored.receipt.get("zero_world_only", false))})

static func _region_validate_legacy_roots(data: TerrainData, roots: Dictionary, mapping: Dictionary = {}) -> Dictionary:
	var people := {}
	var teams := {}
	for body: Dictionary in data.site.get("actors", {}).values():
		people[int(body.get("person_id", 0))] = "actor_hot"
	for team: Dictionary in data.site.get("armies", []):
		for body: Dictionary in team.get("units", []):
			people[int(body.get("person_id", 0))] = "army_hot"
			teams[int(body.get("person_id", 0))] = str(int(team.get("team_id", 0)))
	var refs: Dictionary = data.site.get("travel_identity", {}).get("refs", {}).get("person", {})
	for row: Dictionary in _region_legacy_flights(roots):
		var flight: Dictionary = row.flight
		const FIELDS := ["mode", "source_cell", "target_cell", "source_eye", "goal_eye", "origin", "position", "goal", "velocity",
			"visual", "left", "total", "shooter", "shooter_id", "shot_id", "faction"]
		if flight.size() != FIELDS.size() + int(flight.has("_region_legacy_noise")) or flight.get("mode") != "cell":
			return SiteRuntime.fail("INVALID_REGION_LEGACY_FLIGHT")
		for field: String in FIELDS:
			if not flight.has(field): return SiteRuntime.fail("INVALID_REGION_LEGACY_FLIGHT")
		if not RegionCheckpoint.integer(flight.shooter_id, 1) or not people.has(int(flight.shooter_id)) \
			or not RegionCheckpoint.integer(flight.shot_id, 1) or not flight.faction is int \
			or not flight.source_cell is Vector2i or not flight.target_cell is Vector2i \
			or not data.contains(flight.source_cell) or not data.contains(flight.target_cell) \
			or flight.visual not in ["arrow", "bolt"] or not flight.shooter is Dictionary or flight.shooter.size() != 8 \
			or not RegionCheckpoint.supported(flight.shooter):
			return SiteRuntime.fail("INVALID_REGION_LEGACY_FLIGHT")
		for field: String in ["ability", "training", "fatigue", "morale", "armorbonus"]:
			if not (flight.shooter.get(field) is float or flight.shooter.get(field) is int) or not is_finite(float(flight.shooter[field])):
				return SiteRuntime.fail("INVALID_REGION_LEGACY_SHOOTER")
		for field: String in ["weapon", "armor", "skill"]:
			if not flight.shooter.get(field) is String: return SiteRuntime.fail("INVALID_REGION_LEGACY_SHOOTER")
		for field: String in ["source_eye", "goal_eye"]:
			if not (flight[field] is float or flight[field] is int) or not is_finite(float(flight[field])):
				return SiteRuntime.fail("INVALID_REGION_LEGACY_GEOMETRY")
		for field: String in ["origin", "position", "goal", "velocity"]:
			if not flight[field] is Vector2 or not (flight[field] as Vector2).is_finite():
				return SiteRuntime.fail("INVALID_REGION_LEGACY_GEOMETRY")
		if not RegionCheckpoint.time(flight.left) or not RegionCheckpoint.time(flight.total) or float(flight.total) <= 0.0 \
			or float(flight.left) > float(flight.total) or Vector2(flight.target_cell - flight.source_cell).length() <= 1.0 \
			or Vector2(flight.target_cell - flight.source_cell).length() > SiteCombatRules.RANGED_MAX_RANGE \
			or not (flight.velocity as Vector2).is_equal_approx((flight.goal - flight.origin) / float(flight.total)) \
			or not (flight.position as Vector2).is_equal_approx((flight.origin as Vector2).lerp(flight.goal, 1.0 - float(flight.left) / float(flight.total))):
			return SiteRuntime.fail("INVALID_REGION_LEGACY_GEOMETRY")
		var identity := int(flight.shooter_id)
		if row.kind == "actor_hot" and (people[identity] != "actor_hot" or int(row.owner) != identity) \
			or row.kind == "army_hot" and (people[identity] != "army_hot" or teams.get(identity) != row.owner):
			return SiteRuntime.fail("INVALID_REGION_LEGACY_OWNER")
		if row.kind == "endpoint":
			var owner: Variant = row.owner
			if owner is Dictionary:
				var expected := "person:" + str(identity) + ":owner" if people[identity] == "actor_hot" else "team:" + str(teams[identity])
				if owner.get("@region_reference") != expected: return SiteRuntime.fail("INVALID_REGION_LEGACY_OWNER")
			elif owner is TerrainTestCharacter:
				if owner.combat_identity() != identity: return SiteRuntime.fail("INVALID_REGION_LEGACY_OWNER")
			elif owner is TerrainArmy:
				if owner.index_for_identity(identity) < 0: return SiteRuntime.fail("INVALID_REGION_LEGACY_OWNER")
			else: return SiteRuntime.fail("INVALID_REGION_LEGACY_OWNER")
		if not flight.has("_region_legacy_noise"): continue
		var noise: Variant = flight._region_legacy_noise
		if not noise is Dictionary or noise.size() != 8 or noise.get("version") != 1 or not noise.get("seed") is int \
			or not RegionCheckpoint.integer(noise.get("shooter_id"), 1) or noise.get("shot_id") != flight.shot_id \
			or not noise.get("shooter_ref") is Dictionary or noise.shooter_ref != refs.get(str(identity)) \
			or not noise.get("targets") is Dictionary or noise.targets.is_empty() or noise.targets.size() > 100000 \
			or not noise.get("geometry") is Dictionary or noise.geometry.size() != 5 \
			or not _region_legacy_scope(noise.get("source"), mapping):
			return SiteRuntime.fail("INVALID_REGION_LEGACY_NOISE")
		var geometry: Dictionary = noise.geometry
		if geometry.get("cells") != flight.target_cell - flight.source_cell or not geometry.get("pixels") is Vector2 \
			or not (geometry.pixels as Vector2).is_equal_approx(flight.goal - flight.origin) \
			or geometry.get("eyes") != [flight.source_eye, flight.goal_eye] or geometry.get("total") != flight.total \
			or geometry.get("shooter_hash") != RegionCheckpoint.state_hash(flight.shooter):
			return SiteRuntime.fail("INVALID_REGION_LEGACY_NOISE")
		for key: Variant in noise.targets:
			var parsed: Variant = JSON.parse_string(str(key))
			if not key is String or not parsed is Array or parsed.size() != 3 or parsed[0] != "person" \
				or not parsed[1] is String or str(parsed[1]).is_empty() or not RegionCheckpoint.integer(parsed[2], 1) \
				or key != RegionPartyTravel.stable_key({"type": parsed[0], "namespace": parsed[1], "lineage": parsed[2]}) \
				or not RegionCheckpoint.integer(noise.targets[key], 1):
				return SiteRuntime.fail("INVALID_REGION_LEGACY_NOISE")
		var shooter_key := RegionPartyTravel.stable_key(noise.shooter_ref)
		if noise.targets.get(shooter_key) != noise.shooter_id: return SiteRuntime.fail("INVALID_REGION_LEGACY_NOISE")
	return SiteRuntime.ok()

func _region_prepare_party_family_bind(token: String, candidate: Dictionary, slot: RegionSaveSlot,
		source_proof: Dictionary, transition: Dictionary, family_kind: String = "local") -> Dictionary:
	if slot == null or not is_inside_tree(): return SiteRuntime.fail("INVALID_PARTY_OWNER")
	var authorized: Dictionary
	match family_kind:
		"departure": authorized = slot.validate_region_family_departure_transition(token, candidate, source_proof, transition)
		"takeover": authorized = slot.validate_region_family_takeover_transition(token, candidate, source_proof, transition)
		"local": authorized = slot.validate_region_family_party_transition(token, candidate, source_proof, transition)
		_: return SiteRuntime.fail("INVALID_REGION_FAMILY_TRANSITION")
	if not authorized.ok: return authorized
	var source: Dictionary = slot.validate_region_live_party_proof(token, authorized.source_party, authorized.source_proof)
	if not source.ok: return source
	if source.original_live_graph.is_empty() and family_kind != "takeover":
		return SiteRuntime.fail("MISSING_ORIGINAL_PARTY_GRAPH")
	var restored := _region_party_bootstrap_child(token, source.party, slot, source.proof, source.original_live_graph)
	if not restored.ok: return restored
	var original: TerrainLab = restored.child
	var source_effects: bool = bool(source.original_live_graph.get("context", {}).get("effects_complete", true)) \
		and slot.pending_region_events().is_empty() and original._region_point_pending.is_empty() \
		and original.site_controller._pending_deaths.is_empty()
	var context: Dictionary = slot.region_party_checkpoint_context(token, "region_family",
		source_effects, {"family_control": transition.duplicate(true)})
	if not context.ok: _region_discard_party_child(original); return context
	var full := original.capture_region_party_owner_graph(token, source.party, slot, context.context)
	if not full.ok: _region_discard_party_child(original); return full
	var graph: Dictionary = full.original_live_graph.duplicate(true)
	graph.party_hash = _region_party_hash(candidate)
	# Original input/UI is applied only after the joint marker. This durable
	# control state prevents a selected continuation from restoring the old wait.
	var symbolic := RegionOwnerSnapshot.validate_for_bind(graph.owners.scene, func(_key: String, _kind: int) -> bool: return true, graph.context)
	if not symbolic.ok: _region_discard_party_child(original); return symbolic
	symbolic.roots.controller._family_wait = false
	var wire := RegionOwnerSnapshot.capture_bind_roots(symbolic.roots, graph.context)
	if not wire.ok: _region_discard_party_child(original); return wire
	graph.owners.scene = wire.state
	var target := _region_party_domain_view(token, candidate, slot, graph)
	if not target.ok: _region_discard_party_child(original); return target
	var checked := _region_validate_party_graph(target.data, candidate, graph)
	if not checked.ok: _region_discard_party_child(original); return checked
	var created := _region_new_bind_child(target.data)
	if not created.ok: _region_discard_party_child(original); return created
	var child: TerrainLab = created.child
	child.site_controller.region_slot = slot
	child.site_controller._auto_save_blocked = true
	child._region_party_token = token
	child._region_party_input_hash = _region_party_hash(candidate)
	var sources := [{"party": source.party, "proof": source.proof}]
	_region_party_bind_candidates[child.get_instance_id()] = {"child": child, "slot": slot, "data": target.data,
		"party": candidate, "party_hash": child._region_party_input_hash, "graph": graph, "sources": sources}
	var bootstrap := "party_family_" + Crypto.new().generate_random_bytes(16).hex_encode()
	child._region_owner_bind_tickets[bootstrap] = {"kind": "party-candidate", "data": target.data,
		"body_hash": RegionCheckpoint.state_hash(target.data.site), "context": graph.context,
		"owners": _region_party_scene_owners(graph.owners), "slot": slot, "party": candidate, "graph": graph, "sources": sources}
	child.bind_terrain(target.data, {"ok": true, "crowd_site": null, "region_bind_token": bootstrap})
	child._region_owner_bind_tickets.erase(bootstrap)
	_region_discard_party_child(original)
	if child.terrain != target.data or child._region_bound_data != target.data or child._region_bind_receipt_value.get("owners_restored") != true:
		_region_discard_party_child(child); return SiteRuntime.fail("REGION_CHILD_BIND_FAILED")
	child.set_process(false); child.set_process_input(false); child.set_process_unhandled_input(false)
	for actor: TerrainTestCharacter in child.combat_actors: actor.set_process(false)
	for team: TerrainArmy in child.combat_armies: team.set_process(false)
	var captured := child.capture_region_party_owner_graph(token, candidate, slot, context.context)
	if not captured.ok: _region_discard_party_child(child); return captured
	graph = captured.original_live_graph
	var nonce := "party_family_bind_" + Crypto.new().generate_random_bytes(16).hex_encode()
	_region_owner_bind_tickets[nonce] = {"kind": "party-prepared", "data": target.data, "child": child, "slot": slot,
		"source_party": source.party, "source_proof": source.proof, "proofs": [source.proof], "sources": sources,
		"party": candidate, "party_hash": _region_party_hash(candidate), "graph": graph,
		"graph_hash": RegionCheckpoint.state_hash({"graph": graph}), "body_hash": RegionCheckpoint.state_hash(target.data.site),
		"generation": int(source.proof.generation), "revision": int(source.proof.revision),
		"context": graph.context, "owners": _region_party_scene_owners(graph.owners), "family_transition": transition.duplicate(true)}
	if family_kind == "departure": _region_owner_bind_tickets[nonce]["family_departure"] = transition.duplicate(true)
	if family_kind == "takeover": _region_owner_bind_tickets[nonce]["family_takeover"] = transition.duplicate(true)
	var publication: Callable = _region_publish_party_departure_bind.bind(nonce) if family_kind == "departure" else _region_publish_party_bind.bind(nonce)
	return SiteRuntime.ok("", {"data": target.data, "party": candidate, "original_live_graph": graph, "token": nonce,
		"can_publish": _region_can_publish_party_bind.bind(nonce), "publish": publication,
		"discard": _region_discard_party_bind.bind(nonce)})

func _region_refresh_original_live_frame(party: Dictionary, original: TerrainLab,
		slot: RegionSaveSlot, game_seconds: float = -1.0, action_seconds: float = -1.0) -> Dictionary:
	var result := party.duplicate(true)
	var live: Dictionary = result.upkeep.get("live", {})
	if live.is_empty(): return {"ok": true, "party": result}
	var frame: Dictionary = live.get("frame", {})
	if not RegionPartyTravel._frame_pair(frame.get("world_origin")) or not RegionPartyTravel._frame_pair(frame.get("size")) \
			or original.terrain.size.x != int(frame.size[0]) or original.terrain.size.y != int(frame.size[1]):
		return SiteRuntime.fail("INVALID_PARTY_FRAME")
	var origin := Vector2i(int(frame.world_origin[0]), int(frame.world_origin[1]))
	var refs: Dictionary = result.content.travel_identity.refs
	var people := {}
	var bodies := RegionPartyTravel._body_records(result.content)
	for identity: Variant in bodies:
		var body: Dictionary = bodies[identity]
		var cell: Variant = body.get("cell")
		if not RegionPartyTravel._frame_pair(cell) or not refs.person.has(str(identity)): return SiteRuntime.fail("PARTY_BODY_CLOSURE")
		var at := origin + Vector2i(int(cell[0]), int(cell[1]))
		people[str(identity)] = {"reference": refs.person[str(identity)].duplicate(), "world_cell": [at.x, at.y]}
	var vehicles := {}
	for identity: String in result.content.get("vehicles", {}):
		var vehicle: Dictionary = result.content.vehicles[identity]
		if not vehicle.get("cell") is int or not refs.vehicle.has(identity): return SiteRuntime.fail("PARTY_BODY_CLOSURE")
		var at := origin + original.terrain.cell_from_index(int(vehicle.cell))
		var record := {"reference": refs.vehicle[identity].duplicate(), "world_cell": [at.x, at.y], "pose": {}}
		if str(vehicle.get("kind", "")) == "ship":
			var actual: Dictionary = original.site_controller.vehicles.ship_render_pose(vehicle)
			if not actual.get("anchor") is Vector2 or not actual.get("direction") is Vector2: return SiteRuntime.fail("MISSING_ORIGINAL_SHIP_POSE")
			var world: Vector2 = actual.anchor + Vector2(origin)
			var pose := {"world_anchor": [world.x, world.y], "facing": vehicle.facing.duplicate(), "moving": bool(actual.moving)}
			var move: Dictionary = vehicle.get("move", {})
			if not move.is_empty():
				var start := origin + original.terrain.cell_from_index(int(move.from_cell))
				var end := origin + original.terrain.cell_from_index(int(move.cell))
				pose.merge({"action": str(move.action), "from": [start.x, start.y], "to": [end.x, end.y],
					"from_facing": move.from_facing.duplicate(), "to_facing": move.facing.duplicate(),
					"weight": float(actual.progress), "elapsed_action_seconds": float(move.elapsed),
					"duration_action_seconds": float(move.duration)}, true)
			record.pose = pose
		vehicles[identity] = record
	frame.people = people
	frame.vehicles = vehicles
	frame.game_seconds = float(slot.control.logical_game_seconds) if game_seconds < 0.0 else game_seconds
	frame.action_seconds = float(slot.control.fire_clock.action_seconds) if action_seconds < 0.0 else action_seconds
	live.upkeep = str(live.get("upkeep", "liveBody"))
	result.upkeep.at = frame.game_seconds
	result.upkeep.owner_action_seconds = frame.action_seconds
	# Region route distance and sea_cursor remain their exact historical values.
	original.terrain.set_meta(&"region_party_world_frame", frame.duplicate(true))
	var poses := {}
	for identity: String in vehicles:
		if not vehicles[identity].pose.is_empty(): poses[identity] = vehicles[identity].pose.duplicate(true)
	original.terrain.set_meta(&"region_party_hull_poses", poses)
	return {"ok": true, "party": result}

func prepare_region_party_family_bind(token: String, candidate: Dictionary, slot: RegionSaveSlot,
		source_proof: Dictionary, transition: Dictionary) -> Dictionary:
	var duty := _region_capture_duty_cache()
	var result := _region_prepare_party_family_bind(token, candidate, slot, source_proof, transition)
	_region_restore_duty_cache(duty)
	return result

func prepare_region_party_family_depart_bind(token: String, candidate: Dictionary, slot: RegionSaveSlot,
		source_proof: Dictionary, transition: Dictionary) -> Dictionary:
	var duty := _region_capture_duty_cache()
	var result := _region_prepare_party_family_bind(token, candidate, slot, source_proof, transition, "departure")
	_region_restore_duty_cache(duty)
	return result

func prepare_region_party_family_takeover_bind(token: String, candidate: Dictionary, slot: RegionSaveSlot,
		source_proof: Dictionary, transition: Dictionary) -> Dictionary:
	var duty := _region_capture_duty_cache()
	var result := _region_prepare_party_family_bind(token, candidate, slot, source_proof, transition, "takeover")
	_region_restore_duty_cache(duty)
	return result

func _region_gameplay_finish_live_life(event: Dictionary) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null: return SiteRuntime.fail("NO_REGION_SLOT")
	var current := slot.region_travel_party()
	if not current.ok: return current
	var token := str(current.party.party_id)
	var selected := slot.region_original_party_runtime_proof(token, current.party)
	if not selected.ok or selected.lab != self: return selected if not selected.ok else SiteRuntime.fail("STALE_REGION_PARTY_OWNER")
	var queued: Dictionary = {}
	for original: Dictionary in slot.region_registry().events:
		if original.id == event.get("id"): queued = original
	if queued.is_empty() or queued.status != "pending": return SiteRuntime.fail("STALE_REGION_EVENT")
	if queued.payload.has("family_control_transition"): return slot._region_gameplay_family_life_complete(queued)
	if str(queued.kind) in ["life", "player_death"]:
		# Refuse unrelated body/holder drift before the original typed effect.
		var closure := slot._region_capture_party_graph(token, current.party, {"life_event": str(queued.id)})
		if not closure.ok: return closure
		var life := _region_gameplay_site_life_effect(queued)
		if not life.ok: return life
		if str(queued.owner) == "travel:" + token:
			var record: Dictionary = queued.payload.get("event", queued.payload)
			for accepted: Dictionary in current.party.upkeep.events:
				if int(accepted.sequence) == int(record.get("sequence", -1)) and int(accepted.person_id) == int(record.get("person_id", -1)):
					accepted.status = "complete"
	site_controller.settle_person_deaths(0.0)
	# Publish the accepted zero-time original body closure to its existing cache
	# before checkpoint I/O; a paid retry keeps this same body and holder.
	var captured := _region_capture_original_party(self, current.party, slot)
	if not captured.ok: return captured
	slot._travel_party_runtime = captured.party
	slot._travel_party_runtime_token = token
	var checkpoint := slot.checkpoint_region_travel()
	if not checkpoint.ok: return checkpoint
	# The checkpoint serializes this SAME body's full graph. A body restore here
	# would replace its live presenter and its already-paid movement/down timer.
	if restore_only:
		var accepted := slot.region_live_party_proof(token)
		if not accepted.ok: return accepted
		var frame: Dictionary = accepted.party.upkeep.live.frame
		var body: Dictionary = frame.people.get(str(int(accepted.party.leader_person_id)), {})
		if not RegionPartyTravel._frame_pair(body.get("world_cell")): return SiteRuntime.fail("INVALID_PARTY_FRAME")
		var coordinate := Vector2i(RegionPartyGrid.floor_div(int(body.world_cell[0]), 100), -RegionPartyGrid.floor_div(int(body.world_cell[1]), 100))
		slot.set_meta(&"region_player_materialized", {"site": coordinate, "party_token": token,
			"generation": int(slot._marker.generation), "event_id": str(queued.id)})
		return {"ok": true, "receipt": {"complete": false, "effects_complete": true,
			"player_materialized": true, "owner": "travel:" + token, "generation": int(slot._marker.generation)}}
	site_controller.check_family_death()
	queued = {}
	for original: Dictionary in slot.region_registry().events:
		if original.id == event.get("id"): queued = original
	if queued.is_empty(): return SiteRuntime.fail("STALE_REGION_EVENT")
	if queued.payload.has("family_control_transition"): return slot._region_gameplay_family_life_complete(queued)
	var controlled := _original_person_target(controlled_person_id())
	var living: bool = not controlled.is_empty() and float(controlled.hp) > 0.0
	var controlled_death: bool = bool(queued.payload.get("controlled", false)) and bool(queued.payload.get("death", false))
	var complete := not controlled_death or living
	return {"ok": true, "receipt": {"complete": complete, "effects_complete": true, "continuity_complete": complete,
		"restricted_settlement": not complete and site_controller._pending_deaths.has(controlled_person_id()),
		"owner": str(terrain.site.id), "generation": int(slot._marker.generation),
		"game_seconds": float(slot.control.logical_game_seconds), "action_seconds": float(slot.control.fire_clock.action_seconds)}}

func _region_gameplay_npc_sea_materialize(event: Dictionary) -> Dictionary:
	# Same original full graph bind, published to its complete private NPC child.
	# The actual controlled Actor and its active Site remain in the main Lab.
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null: return SiteRuntime.fail("NO_REGION_SLOT")
	var guarded := slot._region_validate_npc_sea_pair_event(event)
	if not guarded.ok: return guarded
	if not guarded.get("valid", false): return {"ok": true, "receipt": {"complete": true, "effect": "none", "reason": "original current NPC geometry changed"}}
	var active := str(slot.control.active_site_id)
	var controlled := controlled_person_id()
	var terrain_before := terrain
	var prepared := slot.prepare_region_live_party(event)
	if not prepared.ok: return prepared
	var binding := prepare_region_party_live_bind(prepared.token, prepared.party, slot, prepared.proof)
	if not binding.ok: return binding
	var committed := slot.commit_region_live_party(prepared.token, prepared.party, prepared.proof, binding, prepared.incoming)
	if not committed.ok:
		if committed.get("code") != "COMMITTED_UNBOUND": binding.discard.call()
		return committed
	if terrain != terrain_before or controlled_person_id() != controlled or str(slot.control.active_site_id) != active: return SiteRuntime.fail("NPC_PARTY_AUTHORITY")
	return {"ok": true, "receipt": {"complete": true, "owner": "travel:" + str(prepared.token), "generation": int(slot._marker.generation), "effect": "original_npc_live_frame"}}

func prepare_region_party_map_motion(before: Dictionary, after: Dictionary, target: Dictionary) -> Dictionary:
	var guarded := region_party_map_resume_guard(before)
	if not guarded.ok: return guarded
	var slot: RegionSaveSlot = site_controller.region_slot
	if str(before.upkeep.get("live", {}).get("upkeep", "")) != "mapBody" \
			or str(after.party_id) != str(before.party_id): return SiteRuntime.fail("INVALID_PARTY_OWNER")
	var old_frame: Dictionary = before.upkeep.live.frame
	var frame: Dictionary = old_frame.duplicate(true)
	var leader: Dictionary = old_frame.people.get(str(int(before.leader_person_id)), {})
	if not RegionPartyTravel._frame_pair(leader.get("world_cell")) \
			or not RegionPartyTravel._frame_pair(target.get("world_cell")):
		return SiteRuntime.fail("MISSING_ORIGINAL_POSITION")
	var old_world := Vector2i(int(leader.world_cell[0]), int(leader.world_cell[1]))
	var next_world := Vector2i(int(target.world_cell[0]), int(target.world_cell[1]))
	var movement := next_world - old_world
	# A rigid original formation is the accepted foot/straight-carrier slice.
	# An unproved turn must obtain the original vehicle path proof, not a rotate.
	for identity: String in before.content.get("vehicles", {}):
		var vehicle: Dictionary = before.content.vehicles[identity]
		var pose: Dictionary = target.get("vehicle_poses", {}).get(identity, {})
		if str(vehicle.kind) == "ship" or pose.is_empty() or pose.get("facing") != vehicle.get("facing"):
			return SiteRuntime.fail("ORIGINAL_VEHICLE_MOTION_REQUIRED")
		var actual: Dictionary = old_frame.vehicles.get(identity, {})
		if not RegionPartyTravel._frame_pair(pose.get("world_anchor")) \
				or not RegionPartyTravel._frame_pair(actual.get("world_cell")):
			return SiteRuntime.fail("MISSING_ORIGINAL_POSITION")
		if Vector2i(int(pose.world_anchor[0]), int(pose.world_anchor[1])) - Vector2i(int(actual.world_cell[0]), int(actual.world_cell[1])) != movement:
			return SiteRuntime.fail("NONRIGID_ORIGINAL_FORMATION")
	var low := Vector2i(2147483647, 2147483647)
	var high := Vector2i(-2147483648, -2147483648)
	for group: String in ["people", "vehicles"]:
		for identity: String in frame[group]:
			var row: Dictionary = frame[group][identity]
			if not RegionPartyTravel._frame_pair(row.get("world_cell")): return SiteRuntime.fail("INVALID_PARTY_FRAME")
			var at := Vector2i(int(row.world_cell[0]), int(row.world_cell[1])) + movement
			row.world_cell = [at.x, at.y]
			low = low.min(at).min(at - movement); high = high.max(at).max(at - movement)
	var old_origin := Vector2i(int(old_frame.world_origin[0]), int(old_frame.world_origin[1]))
	var sweep: Array[Vector2i] = []
	for row: Dictionary in old_frame.people.values(): sweep.append(Vector2i(int(row.world_cell[0]), int(row.world_cell[1])))
	for vehicle: Dictionary in terrain.site.get("vehicles", {}).values():
		for cell: Vector2i in SiteVehicleTransport.footprint(terrain, vehicle):
			var at := old_origin + cell
			sweep.append(at)
			low = low.min(at).min(at + movement); high = high.max(at).max(at + movement)
	var origin := Vector2i(RegionPartyGrid.floor_div(low.x, 100) * 100, RegionPartyGrid.floor_div(low.y, 100) * 100)
	var size := Vector2i((RegionPartyGrid.floor_div(high.x, 100) + 1) * 100 - origin.x,
		(RegionPartyGrid.floor_div(high.y, 100) + 1) * 100 - origin.y)
	if size.x not in [100, 200] or size.y not in [100, 200]: return SiteRuntime.fail("PARTY_FRAME_BOUNDS")
	frame.world_origin = [origin.x, origin.y]; frame.size = [size.x, size.y]
	var projected: Dictionary = RegionPartyTravel.project_party_frame(before, frame)
	if not projected.ok: return projected
	var context: Dictionary = slot.prepare_region_route_context(null, before)
	if not context.ok: return context
	var geometry: Dictionary = RegionRoute.party_frame_geometry(slot.source, frame, context.context)
	if not geometry.ok: return geometry
	var proposed: TerrainData = geometry.data
	proposed.site = terrain.site.duplicate(true)
	for field: String in RegionPartyTravel.CONTENT_DICTS: proposed.site[field] = projected.party.content.get(field, {}).duplicate(true)
	proposed.site.armies = projected.party.content.armies.duplicate(true)
	var people: Dictionary = RegionPartyTravel._body_records(projected.party.content)
	for identity: Variant in people:
		var cell: Variant = people[identity].get("cell")
		if not RegionPartyTravel._frame_pair(cell) or movement != Vector2i.ZERO and not proposed.is_terrain_walkable(Vector2i(int(cell[0]), int(cell[1]))):
			return SiteRuntime.fail("WALL_EDGE")
	# Every actual person and hull cell follows one original legal cardinal
	# sweep. A blocked cell leaves the paid native pose intact; no endpoint-only
	# projection skips a wall or invalid ramp between the two cells.
	for at: Vector2i in sweep:
		var cell := at - origin
		for axis: int in 2:
			var direction := Vector2i(signi(movement.x), 0) if axis == 0 else Vector2i(0, signi(movement.y))
			var count := absi(movement.x) if axis == 0 else absi(movement.y)
			for _step: int in count:
				if not proposed.can_step(cell, cell + direction): return SiteRuntime.fail("WALL_EDGE")
				cell += direction
	var vehicles: Dictionary = SiteStore._validate_vehicles(proposed, proposed.site, movement != Vector2i.ZERO)
	if not vehicles.ok: return vehicles
	var accepted := SiteRuntime.ok("", {"token": str(before.party_id), "body_hash": _region_party_input_hash,
		"generation": int(slot._marker.generation), "runtime_revision": int(slot.region_registry().revision),
		"game_begin": float(slot.control.logical_game_seconds), "action_begin": float(slot.control.fire_clock.action_seconds),
		"bind_token": str(_region_bind_receipt_value.get("token", "")), "frame": frame,
		"projection": projected.projection, "geometry": geometry, "native_references": guarded.native_references})
	_region_map_motion_proposal = accepted
	return accepted

func region_party_map_resume_guard(party: Dictionary) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null or terrain == null or not terrain.has_meta(&"region_party_owner"):
		return SiteRuntime.fail("INVALID_TRAVEL_HOST")
	var current: Dictionary = slot.region_original_party_runtime_proof(str(party.get("party_id", "")), party)
	if not current.ok or current.get("lab") != self:
		return current if not current.ok else SiteRuntime.fail("INVALID_TRAVEL_HOST")
	if _region_owner_interval_active or _region_point_consuming or not _region_point_pending.is_empty() \
			or not slot.pending_region_events().is_empty(): return SiteRuntime.fail("PENDING_EVENT")
	var fault: Dictionary = site_controller.original_step_fault_guard()
	if not fault.ok: return fault
	if site_controller._crowd_active(): return SiteRuntime.fail("UNSUPPORTED_BACKEND")
	if has_unpersisted_ranged_projectiles() or not fire_projectiles.is_empty() or not siege_projectiles.is_empty(): return SiteRuntime.fail("PARTY_ACTION_OPEN")
	var actions: Dictionary = site_controller.person_actions.save_guard()
	if not actions.ok: return actions
	if not site_controller._ground_crossing.is_empty() or site_controller.ship_journey_active():
		return SiteRuntime.fail("PARTY_ACTION_OPEN")
	if combat_movement_coordinator != null and (not combat_movement_coordinator._egress_search_states.is_empty() \
			or not combat_movement_coordinator._egress_retry_queue.is_empty() \
			or not combat_movement_coordinator._inflight_batches.is_empty()): return SiteRuntime.fail("PARTY_ACTION_OPEN")
	var controlled := controlled_target()
	if controlled.is_empty(): return SiteRuntime.fail("NO_TARGET")
	var faction: int = controlled.owner.faction_id
	var cells: Array[Vector2i] = []
	for actor: TerrainTestCharacter in combat_actors:
		if not actor_present(actor): continue
		if actor.faction_id == faction: cells.append(actor.terrain_cell)
		if actor.is_moving() or actor.action_time > ACTION_TIME_EPSILON and not actor._getting_up \
				or is_instance_valid(actor._rescue_target) or is_instance_valid(actor._rescue_army) \
				or not actor._exchange_pending_skill.is_empty() or actor._exchange_visual_active or not actor.projectiles.is_empty():
			return SiteRuntime.fail("PARTY_ACTION_OPEN")
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		if team.faction_id == faction: cells.append_array(team.cells)
		if team.combat_order != TerrainArmy.CombatOrder.HOLD or not team._unit_rescues.is_empty() \
				or not team.projectiles.is_empty() or not team._combat_batch_members.is_empty() \
				or team._path_status == TerrainArmy.PathStatus.PENDING or not team._pending_pushes.is_empty() \
				or team._formation_march_active or team._formation_bend_active:
			return SiteRuntime.fail("PARTY_ACTION_OPEN")
		for index: int in team.combat_units.size():
			if team.moving_to[index] != TerrainArmy.INVALID_CELL \
					or str(team.combat_hot_get(index, &"pose", "")) in ["attack", "shoot", "reload", "rescue"]:
				return SiteRuntime.fail("PARTY_ACTION_OPEN")
	if RegionTravelSite._hostile_near(self, faction, cells): return SiteRuntime.fail("IN_COMBAT")
	# Pending original deaths/down/get-up are retained. Only an unpaid action
	# blocks handoff; this does not reuse the old all-awake extraction guard.
	return SiteRuntime.ok("", {"lab": self, "token": str(party.party_id), "body_hash": _region_party_input_hash,
		"bind_token": str(_region_bind_receipt_value.get("token", "")), "native_references": _region_owner_references()})


func _prepare_gd_mesh_work_point(seconds: float) -> Dictionary:
	if not _gd_mesh_work_point.is_empty() or not is_finite(seconds) or seconds <= 0.0: return SiteRuntime.fail("CLOCK_NOT_READY")
	# Unsupported real side-effect lanes refuse BEFORE this point's first
	# material/body/clock cost. Ordinary no-contact work is untouched.
	if _fire_activity() or _siege_active(): return SiteRuntime.fail("CONTACT_EFFECT_PREFIX_NOT_PREPARED")
	for team: TerrainArmy in combat_armies:
		if not team.projectiles.is_empty(): return SiteRuntime.fail("CONTACT_EFFECT_PREFIX_NOT_PREPARED")
		for index: int in team.combat_units.size():
			if bool(team.combat_hot_get(index, &"attack")) and not team.ranged_profile(index).is_empty(): return SiteRuntime.fail("CONTACT_RANGED_PREFIX_NOT_PREPARED")
	for actor: TerrainTestCharacter in combat_actors:
		if not actor.projectiles.is_empty(): return SiteRuntime.fail("CONTACT_EFFECT_PREFIX_NOT_PREPARED")
		if actor.action_time > 0.0 and not actor.ranged_profile().is_empty(): return SiteRuntime.fail("CONTACT_RANGED_PREFIX_NOT_PREPARED")
	for provider: String in _shared_work_plan.jobs:
		if provider in ["work_team", "movement", "person_actions", "runtime", "training", "delivery"]: continue
		for allocation: Dictionary in _shared_work_plan.jobs[provider].values():
			if float(allocation.actual_seconds) > 0.0: return SiteRuntime.fail("CONTACT_PROVIDER_PREFIX_NOT_PREPARED", provider)
	# Maps alone never imply a cost. The original preclipped positive window
	# contains no new meal debit; due meals settled at the existing BEGIN zero.
	var supply: Dictionary = site_controller.prepare_gd_mesh_supply_window(seconds)
	if not supply.ok: return supply
	var training: Dictionary = site_controller.prepare_gd_contact_training_window(supply, _shared_work_requests, _shared_work_plan)
	if not training.ok: return training
	var delivery: Dictionary = site_controller.prepare_gd_contact_delivery_window(supply, _shared_work_requests, _shared_work_plan)
	if not delivery.ok: return delivery
	var captured: Dictionary = site_controller.prepare_shared_runtime_work_prefix(_shared_work_requests, seconds)
	if not captured.ok: return captured
	var runtime_priors: Array = []
	var jobs: Dictionary = site_controller.person_actions.prepare_gd_contact_job_prefix(_shared_work_requests, seconds)
	if not jobs.ok: return jobs
	var nonwork: Dictionary = site_controller.person_actions.prepare_shared_nonwork_timers(seconds)
	if not nonwork.ok: return nonwork
	var original: Dictionary = site_controller.work_team.prepare_shared_work_prefix(seconds)
	if not original.ok: return original
	var upper: Dictionary = _shared_work_plan.duplicate(false)
	upper.jobs = {}
	for provider: String in _shared_work_plan.jobs:
		upper.jobs[provider] = {}
		for key: String in _shared_work_plan.jobs[provider]:
			var allocation: Dictionary = _shared_work_plan.jobs[provider][key].duplicate(false)
			allocation.participant_effective_seconds = allocation.participant_seconds.duplicate()
			upper.jobs[provider][key] = allocation
	var runtime_registered: Dictionary = site_controller.prepare_shared_runtime_prefix_allocations(captured, upper, runtime_priors)
	if not runtime_registered.ok: return runtime_registered
	var wt_registered: Dictionary = site_controller.work_team.prepare_shared_work_prefix_allocations(original, upper, runtime_priors)
	if not wt_registered.ok: return wt_registered
	var pa_admitted: Dictionary = site_controller.person_actions.validate_shared_work_prefix(jobs.prepared, upper, _shared_work_requests)
	if not pa_admitted.ok: return pa_admitted
	var pa_registered: Dictionary = site_controller.person_actions.prepare_checked_controlled_prefix_allocations(pa_admitted, runtime_priors)
	if not pa_registered.ok: return pa_registered
	# All three original providers are registered before any named/master check.
	var runtime: Dictionary = site_controller.prepare_gd_contact_runtime_prefix(captured, _shared_work_plan, runtime_priors, runtime_registered)
	if not runtime.ok: return runtime
	var work: Dictionary = site_controller.work_team.prepare_gd_contact_work_prefix(original, _shared_work_plan, runtime_priors, wt_registered)
	if not work.ok: return work
	var controlled: Dictionary = site_controller.person_actions.prepare_gd_contact_controlled_prefix(pa_registered)
	if not controlled.ok: return controlled
	var all_envelopes: Array = []
	all_envelopes.append_array(runtime.envelopes)
	all_envelopes.append_array(work.envelopes)
	all_envelopes.append_array(jobs.controlled_envelopes)
	for first: int in all_envelopes.size():
		for second: int in range(first + 1, all_envelopes.size()):
			var a: Dictionary = all_envelopes[first]
			var b: Dictionary = all_envelopes[second]
			if not is_same(a.unit, b.unit) or a.prepared.field != b.prepared.field: continue
			var group: Dictionary = a.prepared.prefix_ref.get("shared_vehicle_group", {})
			if group.get("owner") != self or not is_same(group, b.prepared.prefix_ref.get("shared_vehicle_group")) or not is_same(group.work_unit, a.unit) or group.field != a.prepared.field: return SiteRuntime.fail("CONTACT_SHARED_PHYSICAL_UNIT_NOT_PREPARED")
	var ship_versions: Dictionary = _gd_mesh_ship_repair_version_budget(all_envelopes, runtime_priors)
	if not ship_versions.ok: return ship_versions
	var participants := {}
	for request: Dictionary in _shared_work_requests:
		for participant: Dictionary in request.participants:
			var body: Variant = participant.body
			var source: Dictionary = PersonFatigue.pool(body)
			participants[int(participant.person_id)] = {"original": participant, "body": body,
				"base_rate": float(participant.effort_rate) * maxf(1.0, float(source.get("count", 1))),
				"provider": str(request.provider)}
	_gd_mesh_work_point = {"owner": self, "site": terrain.site, "seconds": seconds, "elapsed": 0.0,
		"participants": participants, "work": work, "supply": supply, "jobs": jobs, "nonwork": nonwork, "runtime": runtime, "published_priors": [], "sources": [], "requests": _shared_work_requests,
		"nominal_plan": _shared_work_plan, "remaining": {}, "finished": false, "upper_priors": runtime_priors, "upper_envelopes": all_envelopes}
	for request: Dictionary in _shared_work_requests:
		_gd_mesh_work_point.remaining[str(request.provider) + ":" + str(request.key)] = float(request.remaining)
	for group: Dictionary in _shared_vehicle_groups:
		_gd_mesh_work_point.remaining[group.key] = float(group.remaining)
		for source: Dictionary in group.sources: _gd_mesh_work_point.sources.append(source)
	var terminal: Dictionary = site_controller.person_actions.prepare_gd_ranged_terminal_upper(runtime_priors)
	if not terminal.ok:
		_gd_mesh_work_point = {}
		return terminal
	return SiteRuntime.ok("原mesh/work起点与材料上界均已纯核")

func _advance_gd_mesh_work_to(fraction: float) -> void:
	if _gd_mesh_work_point.is_empty(): return
	var end: float = float(_gd_mesh_work_point.seconds) * clampf(fraction, 0.0, 1.0)
	var begin: float = float(_gd_mesh_work_point.elapsed)
	var seconds: float = end - begin
	if seconds <= 0.0: return
	var projection := {}
	for identity: int in _gd_mesh_work_point.participants:
		var source: Dictionary = _gd_mesh_work_point.participants[identity]
		var participant: Dictionary = source.original.duplicate(false)
		var person: Dictionary = site_controller.person_actions._person(identity)
		var live: bool = not person.is_empty() and is_same(person.body, source.body) \
			and (person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act())
		if source.provider == "work_team": live = live and site_controller.work_team.gd_contact_work_person_ready(identity)
		elif source.provider == "person_actions": live = live and site_controller.person_actions.gd_contact_job_person_ready(identity)
		elif source.provider == "runtime": live = live and site_controller.gd_contact_runtime_person_ready(identity)
		elif source.provider == "training": live = live and site_controller.gd_contact_training_person_ready(identity)
		elif source.provider == "delivery": live = live and site_controller.gd_contact_delivery_person_ready(identity)
		participant.effort_rate = PersonFatigue.effort_rate(source.body, float(source.base_rate)) if live else 0.0
		participant.active_until_game_seconds = seconds if live else 0.0
		projection[identity] = participant
	# Actual original bodies/counts after the PREVIOUS contact are the only
	# fatigue inputs. No temporary HP, forged alive row, proxy pool, or seed.
	var planned: Dictionary = _plan_shared_vehicle_work_interval(_shared_work_requests, seconds, projection)
	assert(planned.ok) # Finite subset of the original preflight, not an admission guard.
	_gd_mesh_work_point["segment_plan"] = planned
	_gd_mesh_work_point["segment_priors"] = _gd_mesh_work_point.published_priors.duplicate(false)
	var runtime: Dictionary = site_controller.prepare_gd_contact_runtime_segment(planned, seconds, true)
	assert(runtime.ok)
	var work: Dictionary = site_controller.work_team.prepare_gd_contact_work_segment(planned, seconds, true)
	assert(work.ok)
	var jobs: Dictionary = site_controller.person_actions.prepare_gd_contact_job_segment(planned, seconds, true)
	assert(jobs.ok)
	runtime = site_controller.validate_gd_contact_runtime_segment(runtime.segment)
	assert(runtime.ok)
	work = site_controller.work_team.validate_gd_contact_work_segment(work.segment)
	assert(work.ok)
	jobs = site_controller.person_actions.validate_gd_contact_job_runtime_segment(jobs.segment)
	assert(jobs.ok)
	var training: Dictionary = site_controller.prepare_gd_contact_training_segment(planned, seconds)
	assert(training.ok)
	var delivery: Dictionary = site_controller.prepare_gd_contact_delivery_segment(planned, seconds)
	assert(delivery.ok)
	var delivery_valid: Dictionary = site_controller.validate_gd_contact_delivery_segment(delivery.segment)
	assert(delivery_valid.ok)
	# Work effort is written BEFORE the original death decrements/unbinds its
	# shared pool. Each disjoint interval commits once, never the full plan.
	for pool: Dictionary in planned.pools:
		if float(pool.effort_seconds) <= 0.0: continue
		PersonFatigue.write(pool.body, "fatigue", float(pool.fatigue))
		PersonFatigue.write(pool.body, "fatigue_rest", float(pool.fatigue_rest))
	site_controller.publish_gd_contact_runtime_segment(runtime.segment)
	site_controller.work_team.publish_gd_contact_work_segment(work.segment)
	for candidate: Dictionary in runtime.segment.runtime: _gd_mesh_work_point.published_priors.append(candidate)
	for candidate: Dictionary in work.segment.runtime: _gd_mesh_work_point.published_priors.append(candidate)
	site_controller.person_actions.publish_gd_contact_job_segment(jobs.segment)
	for candidate: Dictionary in jobs.segment.runtime: _gd_mesh_work_point.published_priors.append(candidate)
	site_controller.publish_gd_contact_delivery_segment(delivery.segment)
	site_controller.publish_gd_mesh_supply_segment(_gd_mesh_work_point.supply, seconds)
	site_controller.publish_gd_contact_training_segment(training.segment)
	var accounted := {}
	for provider: String in planned.jobs:
		for key: String in planned.jobs[provider]:
			var allocation: Dictionary = planned.jobs[provider][key]
			var group: Dictionary = allocation.get("shared_vehicle_group", {})
			var remaining_key: String = str(group.key) if not group.is_empty() else provider + ":" + key
			if accounted.has(remaining_key): continue
			accounted[remaining_key] = true
			var consumed: float = float(allocation.effective_seconds)
			if not group.is_empty():
				consumed = 0.0
				for original_source: Dictionary in group.sources:
					for participant: Dictionary in original_source.request.participants:
						consumed += float(allocation.participant_effective_seconds.get(int(participant.person_id), 0.0)) * float(participant.get("progress_multiplier", 1.0))
			_gd_mesh_work_point.remaining[remaining_key] = maxf(0.0, float(_gd_mesh_work_point.remaining[remaining_key]) - consumed)
	_gd_mesh_work_point.elapsed = end
	_gd_mesh_work_point.erase("segment_plan")
	_gd_mesh_work_point.erase("segment_priors")

func _finish_gd_mesh_work_point() -> void:
	if _gd_mesh_work_point.is_empty() or bool(_gd_mesh_work_point.finished): return
	_advance_gd_mesh_work_to(1.0)
	_gd_mesh_work_point.finished = true
	_shared_work_pools_committed = true
	site_controller.finish_gd_contact_runtime_prefix()
	site_controller.work_team.finish_gd_contact_work_prefix()
	site_controller.person_actions.finish_gd_contact_job_prefix()
	site_controller.person_actions.finish_shared_nonwork_timers(_gd_mesh_work_point.nonwork)
	site_controller.finish_gd_contact_training_window(_gd_mesh_work_point.supply)
	site_controller.finish_gd_contact_delivery_window(_gd_mesh_work_point.supply)
	site_controller.finish_shared_runtime_clock()
	_gd_mesh_work_point = {}

func _capture_shared_vehicle_groups(requests: Array) -> Dictionary:
	_shared_vehicle_groups.clear()
	for request: Dictionary in requests:
		var owner: Variant = site_controller.work_team if request.get("provider") == "work_team" else site_controller.person_actions if request.get("provider") == "person_actions" else site_controller if request.get("provider") == "runtime" else null
		if owner == null or str(request.get("paused", "")) not in ["", "REST", "SHARED_MASTER"]: continue
		var facts: Dictionary = owner.shared_vehicle_work_request_facts(request)
		if facts.is_empty(): continue
		var group: Dictionary = {}
		for existing: Dictionary in _shared_vehicle_groups:
			if is_same(existing.target_ref, facts.target_ref) and is_same(existing.work_unit, facts.work_unit) and existing.action == facts.action and existing.field == facts.field: group = existing; break
		if group.is_empty():
			var key: String = "shared_vehicle:" + str(facts.unit_key)
			for existing: Dictionary in _shared_vehicle_groups:
				if existing.key == key: return SiteRuntime.fail("STALE_SHARED_WORK", "同名稱卻不同原工作部位不能合併")
			group = {"owner": self, "site": terrain.site, "key": key, "target_ref": facts.target_ref, "work_unit": facts.work_unit,
				"target_id": facts.target_id, "action": facts.action, "field": facts.field, "sources": [], "person_ids": [],
				"required_skills": [], "eligible_by_id": {}, "remaining": float(facts.physical_remaining)}
			_shared_vehicle_groups.append(group)
		if not is_finite(float(facts.physical_remaining)) or float(facts.physical_remaining) < 0.0 or absf(float(group.remaining) - float(facts.physical_remaining)) > PersonFatigue.WORK_PLAN_EPS: return SiteRuntime.fail("STALE_SHARED_WORK")
		for identity: int in facts.person_ids:
			if group.person_ids.has(identity): return SiteRuntime.fail("DUPLICATE_SHARED_WORKER")
			group.person_ids.append(identity)
			group.eligible_by_id[identity] = facts.eligible_by_id[identity]
		for skill: String in facts.required_skills:
			if not group.required_skills.has(skill): group.required_skills.append(skill)
		group.sources.append({"owner": owner, "request": request, "facts": facts})
	return SiteRuntime.ok()

func checked_shared_vehicle_prefix_for_task(task: Dictionary, identity: int) -> Dictionary:
	if identity <= 0 or site_controller == null: return {}
	var owners: Array = [site_controller.work_team, site_controller.person_actions, site_controller]
	var source: Dictionary = {}
	for owner: Variant in owners:
		for prefix: Dictionary in owner.owned_checked_work_prefixes():
			if is_same(prefix.task, task): source = prefix; break
	if source.is_empty(): return {}
	var group: Dictionary = source.get("shared_vehicle_group", {})
	if group.get("owner") != self or not is_same(group.get("site"), terrain.site) or not is_same(group.get("target_ref"), source.target_ref) or not is_same(group.get("work_unit"), source.work_unit) or not group.get("person_ids", []).has(identity): return {}
	var actual_group := false
	for held: Dictionary in _shared_vehicle_groups: actual_group = actual_group or is_same(held, group)
	if not actual_group: return {}
	for owner: Variant in owners:
		for prefix: Dictionary in owner.owned_checked_work_prefixes():
			if int(prefix.person_id) != identity or not is_same(prefix.get("shared_vehicle_group"), group) or not is_same(prefix.plan, source.plan) or prefix.plan_key != source.plan_key or not is_same(prefix.target_ref, source.target_ref) or not is_same(prefix.work_unit, source.work_unit): continue
			if float(prefix.actual_seconds) <= 0.0 or float(prefix.productive_seconds) <= 0.0 or float(prefix.actual_seconds) + PersonFatigue.WORK_PLAN_EPS < float(source.group_actual_seconds): continue
			# Exact local task/id lookup wins before the owner's foreign fallback,
			# therefore this registry validation cannot recurse through this reader.
			if owner.valid_checked_work_prefix(prefix.task, identity, prefix): return prefix
	return {}

func gd_mesh_work_upper_priors() -> Array:
	if _gd_mesh_work_point.is_empty() or bool(_gd_mesh_work_point.finished) or not is_same(_gd_mesh_work_point.site, terrain.site): return []
	return _gd_mesh_work_point.get("upper_priors", [])

func gd_mesh_work_upper_candidate(candidate: Dictionary) -> bool:
	if _gd_mesh_work_point.is_empty() or bool(_gd_mesh_work_point.finished) or not is_same(_gd_mesh_work_point.site, terrain.site): return false
	for envelope: Dictionary in _gd_mesh_work_point.get("upper_envelopes", []):
		if is_same(envelope.prepared, candidate): return true
	return false

func _gd_mesh_ship_repair_version_budget(envelopes: Array, priors: Array) -> Dictionary:
	# This is only finite item-version headroom, never a predicted contact,
	# work qualification, fraction, selector, pool count or progress source.
	# Original Army.sample_combat and Actor._resolve_melee_contacts mark each
	# target identity once; the original Lab samples each body once per point.
	# Counting ALL original bodies also covers attacks begun in prepare_combat.
	var bodies: int = 0
	for team: TerrainArmy in combat_armies:
		if is_instance_valid(team): bodies += int(team.combat_units.size())
	for actor: TerrainTestCharacter in combat_actors:
		if is_instance_valid(actor): bodies += 1
	var segment_bound: int = bodies * bodies + 1
	var holders: Array[Dictionary] = []
	var targets: Array[Dictionary] = []
	for envelope: Dictionary in envelopes:
		if envelope.prepared.endpoint != "ship_repair": continue
		var target_row: Dictionary = {}
		for existing: Dictionary in targets:
			if is_same(existing.target, envelope.target): target_row = existing; break
		if target_row.is_empty():
			target_row = {"target": envelope.target, "begin": int(envelope.ship_revision_begin), "workers": 0}
			targets.append(target_row)
		if int(target_row.begin) != int(envelope.ship_revision_begin): return SiteRuntime.fail("STALE_SOURCE")
		if float(envelope.prepared.prefix_ref.actual_seconds) <= 0.0: continue
		target_row.workers = int(target_row.workers) + 1
		var row: Dictionary = {}
		for existing: Dictionary in holders:
			if is_same(existing.holder, envelope.ship_holder): row = existing; break
		if row.is_empty():
			row = {"holder": envelope.ship_holder, "cargo": envelope.ship_cargo, "begin": int(envelope.ship_holder_begin), "workers": 0}
			holders.append(row)
		if not is_same(row.cargo, envelope.ship_cargo) or int(row.begin) != int(envelope.ship_holder_begin): return SiteRuntime.fail("STALE_SOURCE")
		row.workers = int(row.workers) + 1
	for row: Dictionary in holders:
		var ordinary_payments: int = 0
		for prior: Dictionary in priors:
			if not prior.get("payment", {}).is_empty() and is_same(prior.payment.holder, row.holder): ordinary_payments += 1
		if int(row.begin) + ordinary_payments + int(row.workers) * segment_bound > 2147483646:
			return SiteRuntime.fail("CONTACT_REPAIR_VERSION_EXHAUSTED", "原真接觸段可能超過本船物品版本餘額；尚未移身／付款／工時")
	for row: Dictionary in targets:
		# Every original prefix increments THIS vehicle, and a genuinely
		# completed retained receipt needs one original zero cleanup.
		if int(row.begin) < 1 or int(row.begin) + int(row.workers) * segment_bound + 1 > 2147483647:
			return SiteRuntime.fail("CONTACT_REPAIR_REVISION_EXHAUSTED", "原真船前綴與清理可能超過本船版本餘額；尚未移身／付款／工時")
	return SiteRuntime.ok("原船修理接觸段物品與船版本空間已純核")

func gd_mesh_work_segment_plan() -> Dictionary:
	return _gd_mesh_work_point.get("segment_plan", {}) if not _gd_mesh_work_point.is_empty() and not bool(_gd_mesh_work_point.finished) else {}

func gd_mesh_work_segment_priors() -> Array:
	return _gd_mesh_work_point.get("segment_priors", [])

func gd_mesh_work_prior_candidate(candidate: Dictionary, priors: Array) -> bool:
	if _gd_mesh_work_point.is_empty() or not _gd_mesh_work_point.has("segment_priors") \
		or not is_same(priors, _gd_mesh_work_point.segment_priors): return false
	for actual: Dictionary in _gd_mesh_work_point.published_priors:
		if is_same(actual, candidate): return true
	return site_controller.gd_contact_runtime_candidate(candidate) or site_controller.work_team.gd_contact_work_candidate(candidate) or site_controller.person_actions.gd_contact_job_runtime_candidate(candidate)

func _plan_shared_vehicle_work_interval(requests: Array, seconds: float, projection: Dictionary = {}) -> Dictionary:
	var union_requests: Array = []
	var retained: Array = []
	for group: Dictionary in _shared_vehicle_groups:
		var participants: Array = []
		var maximum := seconds
		for source: Dictionary in group.sources:
			if not _gd_mesh_group_source_accepted(source) and not source.owner.valid_shared_vehicle_work_request_facts(source.request, source.facts): return SiteRuntime.fail("STALE_SHARED_WORK")
			for participant: Dictionary in source.request.participants:
				participants.append(projection.get(int(participant.person_id), participant))
			maximum = minf(maximum, maxf(0.0, float(source.request.max_game_seconds) - float(_gd_mesh_work_point.get("elapsed", 0.0))))
			retained.append(source.request)
		var master_groups: Array = []
		var missing := false
		for skill: String in group.required_skills:
			var ids: Array[int] = []
			for identity: int in group.person_ids:
				if group.eligible_by_id[identity].has(skill): ids.append(identity)
			if ids.is_empty(): missing = true
			else: master_groups.append(ids)
		union_requests.append({"provider": "shared_vehicle", "key": group.key, "participants": participants, "remaining": float(_gd_mesh_work_point.get("remaining", {}).get(str(group.key), group.remaining)),
			"productive_kind": "sum", "progress_multiplier": 1.0, "max_game_seconds": maximum, "required_all_any_ids": master_groups,
			"paused": "MASTER" if missing else ""})
	for request: Dictionary in requests:
		var grouped := false
		for source: Dictionary in retained: grouped = grouped or is_same(source, request)
		if not grouped:
			if projection.is_empty(): union_requests.append(request)
			else:
				var projected: Dictionary = request.duplicate(false)
				projected.remaining = float(_gd_mesh_work_point.get("remaining", {}).get(str(request.provider) + ":" + str(request.key), request.remaining))
				projected.max_game_seconds = maxf(0.0, float(request.max_game_seconds) - float(_gd_mesh_work_point.get("elapsed", 0.0)))
				projected.participants = []
				for participant: Dictionary in request.participants: projected.participants.append(projection.get(int(participant.person_id), participant))
				union_requests.append(projected)
	var planned: Dictionary = PersonFatigue.plan_work_interval(union_requests, seconds)
	if not planned.ok: return planned
	for group: Dictionary in _shared_vehicle_groups:
		var allocation: Dictionary = planned.jobs.shared_vehicle[group.key]
		for source: Dictionary in group.sources:
			var request: Dictionary = source.request
			var projected: Dictionary = allocation.duplicate(false)
			projected["shared_vehicle_group"] = group
			# Keep actual participant maps for real cross-provider master witnesses.
			# Each original owner consumes only its own original person's base work.
			var local_effective := 0.0
			for participant: Dictionary in request.participants:
				local_effective += float(allocation.participant_effective_seconds.get(int(participant.person_id), 0.0)) * float(participant.get("progress_multiplier", 1.0))
			projected.effective_seconds = local_effective
			if not planned.jobs.has(str(request.provider)): planned.jobs[str(request.provider)] = {}
			planned.jobs[str(request.provider)][str(request.key)] = projected
		planned.jobs.shared_vehicle.erase(group.key)
	if planned.jobs.has("shared_vehicle") and planned.jobs.shared_vehicle.is_empty(): planned.jobs.erase("shared_vehicle")
	return planned

func _gd_mesh_group_source_accepted(source: Dictionary) -> bool:
	if _gd_mesh_work_point.is_empty() or bool(_gd_mesh_work_point.finished) or not is_same(_gd_mesh_work_point.site, terrain.site): return false
	for actual: Dictionary in _gd_mesh_work_point.sources:
		if is_same(actual, source): return is_same(source.request, actual.request) and is_same(source.facts, actual.facts)
	return false

var _shared_vehicle_groups: Array[Dictionary] = []

# INSERT actual calls into ORIGINAL TerrainLab point path, Region sole-writer.
# No new World scheduler/owner. All inputs are SAME previously prepared refs.

var _shared_native_combat_begin: float = -1.0

var _native_begin_shared_window_prepared: Dictionary = {}

var _gd_mesh_work_point: Dictionary = {}

func _gd_mesh_work_needed() -> bool:
	if exchange_enabled or _region_formula_active or crowd_site != null and crowd_site.active or _shared_work_plan.is_empty(): return false
	var work := false
	for provider: String in _shared_work_plan.get("jobs", {}):
		if provider == "movement": continue
		for allocation: Dictionary in _shared_work_plan.jobs[provider].values(): work = work or float(allocation.actual_seconds) > 0.0
	if not work: return false
	# Actual original attack intents only. No enemy forecast, target choice,
	# invented contact, second attack selector, or sample_combat side effects.
	for actor: TerrainTestCharacter in combat_actors:
		if actor.can_act() and actor.action_time > 0.0 and actor._strike_at >= 0.0 and actor.ranged_profile().is_empty(): return true
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		for index: int in team.combat_units.size():
			if team.combat_can_act(index) and bool(team.combat_hot_get(index, &"attack")) and team.ranged_profile(index).is_empty(): return true
	return false

func _prepare_native_begin_shared_window(maximum: float, combat_begin: float) -> Dictionary:
	_wire_fire_ranged()
	var input_batches: Array[Dictionary] = []
	for owner_ref: CrowdPersonOwner in crowd_site.owners:
		var inputs: Dictionary = owner_ref.prepare_host_ranged_ammo_inputs()
		if not inputs.ok: return inputs
		input_batches.append({"owner": owner_ref, "rows": inputs.rows})
	for inputs: Dictionary in input_batches: inputs.owner.publish_host_ranged_ammo_inputs(inputs.rows)
	var game_maximum: float = SiteRuntime.game_seconds(maximum, combat_begin) * simulation_speed
	var held: Dictionary = _collect_original_shared_work_requests(maximum, game_maximum, minf(maximum, combat_begin), combat_begin)
	if not held.ok: return held
	maximum = float(held.action_seconds)
	var original_requests: Array = _shared_work_requests.duplicate(false)
	var without_query: Dictionary = prepare_native_begin_ranged(maximum, false, 0)
	if not without_query.ok: return without_query
	var without: Dictionary = _native_begin_bound(original_requests, maximum, combat_begin, without_query.prepared.preview)
	if not without.ok: return without
	# A hypothetical later query is not today's command/permission. When the
	# actual no-query prefix ends before that original boundary, keep it legal
	# without probing/refusing a future GD release or changing fair cursors.
	var query_gap: float = EXCHANGE_QUERY_STEP - _exchange_phase
	var with_query: Dictionary = without_query
	var with_pulse: Dictionary = without
	if float(without.action_seconds) + ACTION_TIME_EPSILON >= query_gap:
		with_query = prepare_native_begin_ranged(maximum, false, 1)
		if not with_query.ok: return with_query
		with_pulse = _native_begin_bound(original_requests, maximum, combat_begin, with_query.prepared.preview)
		if not with_pulse.ok: return with_pulse
	var witness: Dictionary = _native_begin_transition_witness(original_requests, without, with_pulse, without_query.prepared.preview, with_query.prepared.preview)
	var window: Dictionary = _native_begin_ranged_window(_exchange_phase, maximum, float(without.action_seconds), float(with_pulse.action_seconds),
		float(witness.get("transition", -1.0)), float(witness.get("minimum_next_fatigue", NAN)), float(witness.get("transition_at", NAN)))
	if not window.ok: return window
	var ranged: Dictionary = prepare_native_begin_ranged(float(window.action_seconds))
	if not ranged.ok: return ranged
	var accepted: Dictionary = _native_begin_bound(original_requests, float(window.action_seconds), combat_begin, ranged.prepared.preview)
	if not accepted.ok: return accepted
	# No looping/reselection. A mismatch is rejected before the first shot cost.
	if float(accepted.action_seconds) != float(window.action_seconds): return SiteRuntime.fail("NATIVE_BEGIN_WINDOW_CHANGED")
	var validated: Dictionary = validate_native_begin_ranged(ranged.prepared)
	if not validated.ok: return validated
	var result: Dictionary = SiteRuntime.ok("原BEGIN与同held prefix已純預驗", {"owner": self, "site": terrain.site,
		"ranged": ranged.prepared, "ranged_check": validated.check,
		"requests": accepted.requests, "action_seconds": float(window.action_seconds), "game_seconds": float(accepted.game_seconds),
		"combat_begin": float(accepted.combat_begin), "query_due": bool(window.query_due), "pre_query_transition": bool(window.pre_query_transition),
		"held_action_seconds": _shared_work_action_seconds, "held_game_seconds": _shared_work_game_seconds,
		"projected_jobs": accepted.lower.jobs, "projected_plan": accepted.lower, "projection": accepted.projection, "published": false})
	_native_begin_shared_window_prepared = result
	var retimed: Dictionary = site_controller.work_team.retime_prepared_begin_interval(float(result.game_seconds), float(result.action_seconds), result)
	if not retimed.ok: return retimed
	var training_retime: Dictionary = site_controller.retime_shared_native_training_begin(float(result.game_seconds), result.requests, result)
	if not training_retime.ok: return training_retime
	_shared_work_action_seconds = float(result.action_seconds)
	_shared_work_game_seconds = float(result.game_seconds)
	_shared_work_requests = result.requests
	# Capture actual original qualifications before the first shot cost. These
	# real refs cannot be replaced by the numerical preview's participant bodies.
	var captured: Dictionary = _capture_original_shared_prefixes(result.requests, float(result.game_seconds))
	if not captured.ok: return captured
	result["captured"] = captured
	var supplies: Dictionary = site_controller.prepare_native_sustain_point(float(result.game_seconds), result.requests, accepted.lower)
	if not supplies.ok: return supplies
	var supply_check: Dictionary = site_controller.validate_native_sustain_point(supplies)
	if not supply_check.ok: return supply_check
	result["sustain"] = supplies
	var body: Dictionary = crowd_site.prepare_native_begin_work_point(accepted.lower, result.requests, float(result.action_seconds),
		float(result.game_seconds), maxf(0.0, float(result.combat_begin) - float(result.action_seconds)), ranged.prepared.native_inputs,
		ranged.prepared.preview, accepted.projection)
	if not body.ok: return body
	result["body"] = body
	return result

func _publish_native_begin_shared_window(prepared: Dictionary) -> Dictionary:
	# The final original source/whole-body gates ran BEFORE this first shot cost.
	# No selection, late CAS, user callback, predicate or failure follows here.
	publish_validated_native_begin_ranged(prepared.ranged, prepared.ranged_check)
	crowd_site.publish_native_begin_work_point(prepared.body)
	var seconds: float = float(prepared.game_seconds)
	var action: float = float(prepared.action_seconds)
	_shared_native_combat_begin = float(prepared.combat_begin)
	_shared_work_game_seconds = seconds
	_shared_work_action_seconds = action
	_shared_work_requests = prepared.requests
	_shared_work_plan = prepared.projected_plan
	site_controller._shared_work_plan = _shared_work_plan
	prepared.captured.runtime.clock.combat_left = float(terrain.site.combat_left)
	site_controller.publish_native_sustain_inputs(prepared.sustain)
	_exchange_phase += action
	if _exchange_phase + ACTION_TIME_EPSILON >= EXCHANGE_QUERY_STEP: _exchange_phase = fposmod(_exchange_phase, EXCHANGE_QUERY_STEP)
	prepared.published = true
	return SiteRuntime.ok("", {"captured": prepared.captured, "plan": _shared_work_plan})

func validate_native_begin_shared_window(prepared: Dictionary) -> Dictionary:
	if not valid_native_begin_shared_window(prepared): return SiteRuntime.fail("STALE_NATIVE_BEGIN")
	var ranged: Dictionary = validate_native_begin_ranged(prepared.ranged)
	if not ranged.ok: return ranged
	prepared.ranged_check = ranged.check
	# SAME original captures and pure material candidates are rechecked BEFORE
	# any arrow pulse debit. This is not accepted consumption or a World flag.
	for held: Dictionary in prepared.captured.person_actions.held.values():
		var current: Dictionary = site_controller.person_actions._job_context(held.job)
		if not current.ok: return current
	var priors: Array = []
	var prefixes: Dictionary = _check_original_shared_prefixes(prepared.captured, prepared.projected_plan, prepared.requests, priors, true)
	if not prefixes.ok:
		priors.clear()
		_discard_pure_prefix_registrations()
		return prefixes
	var supplies: Dictionary = site_controller.validate_native_sustain_point(prepared.sustain, priors)
	# Pure candidates are not accepted consumption. Break the same-array prior
	# reference after checking; final actual allocations are prepared afresh.
	priors.clear()
	_discard_pure_prefix_registrations()
	if not supplies.ok: return supplies
	var body: Dictionary = prepared.body
	if not crowd_site.crowd.validate_step_clock_work_plan_after_host_ranged(float(body.action_seconds), float(body.game_seconds),
		float(body.combat_left), int(body.tick), body.packet, prepared.ranged.native_inputs, prepared.ranged.preview):
		return SiteRuntime.fail("STALE_NATIVE_BEGIN_WORK_PLAN")
	return SiteRuntime.ok()

func _region_mark_native_work_combat(mark: float) -> void:
	# Called only by the ORIGINAL CrowdSite contact-forwarder. Ordinary calls
	# retain their original immediate manual interruption. No new queue/clock.
	if crowd_site == null or not crowd_site.work_fatigue_point_active() or not _region_deferring_endpoint():
		SiteRuntime.mark_combat(terrain, mark)
		return
	SiteRuntime.mark_combat(terrain, mark, true)
	var manual: Dictionary = terrain.site.manual
	if str(manual.get("target", "")).is_empty(): return
	for event: Dictionary in _region_point_contacts:
		if str(event.kind) == "native_manual_combat" and is_same(event.packet.get("site"), terrain.site) \
			and is_same(event.packet.get("manual"), manual): return
	_region_point_contacts.append({"kind": "native_manual_combat", "person_id": 0,
		"packet": {"site": terrain.site, "manual": manual, "target": str(manual.target), "action": str(manual.action)}})

func _discard_pure_prefix_registrations() -> void:
	# The before-body preflight registers Runtime/WT/PA prefix allocations for a
	# projected plan only. Drop those registrations (never the captures or shared
	# vehicle facts) so the post-body finish registers afresh for the real point.
	site_controller._checked_runtime_work_preparing = {}
	site_controller._checked_runtime_work_admission = {}
	site_controller.work_team._preparing_shared_prefix = {}
	site_controller.work_team._checked_work_prefix_admission = {}
	site_controller.person_actions._checked_controlled_prefixes = {}

func _finish_native_checked_body_prefixes(action_begin: float, action_end: float, seconds: float) -> bool:
	if crowd_site == null or not crowd_site.work_fatigue_point_active() \
		or not bool(_native_begin_shared_window_prepared.get("published", false)) or not _region_deferring_endpoint():
		site_controller.latch_original_step_fault(SiteRuntime.fail("CLOCK_NOT_READY"))
		return false
	var point: Dictionary = _prepare_native_shared_point_finish(_shared_work_requests, action_begin, action_end, seconds)
	if not point.ok:
		site_controller.latch_original_step_fault(point)
		return false
	var runtime_priors: Array = []
	var checked: Dictionary = _check_original_shared_prefixes(_native_begin_shared_window_prepared.captured, point.plan, point.requests, runtime_priors)
	if not checked.ok:
		site_controller.latch_original_step_fault(checked)
		return false
	var supplies: Dictionary = site_controller.validate_native_sustain_point(_native_begin_shared_window_prepared.sustain, runtime_priors)
	if not supplies.ok:
		site_controller.latch_original_step_fault(supplies)
		return false
	var ready: Dictionary = crowd_site.prepare_work_fatigue_point_finish(point.plan, point.requests, action_end - action_begin, seconds)
	if not ready.ok:
		site_controller.latch_original_step_fault(ready)
		return false
	_shared_work_plan = point.plan
	site_controller._shared_work_plan = point.plan
	_commit_shared_work_pools()
	# Every real finite source/Runtime/P5/Sustain/Native guard precedes this tail.
	_publish_original_shared_prefixes(checked)
	site_controller.person_actions.publish_native_fire_point(point.fire)
	crowd_site.publish_work_fatigue_point()
	site_controller.publish_native_sustain_point(supplies)
	# All native supply is already paid by this accepted point. Preserve only
	# original uncovered GD supply/recovery; no native legacy charge or setter.
	_advance_fatigue(seconds, true)
	site_controller.finish_shared_runtime_clock()
	_region_point_pending.native_checked = {"checked": checked, "fire": point.fire, "finished": false}
	return true

func discard_native_begin_ranged() -> void:
	_native_begin_ranged_prepared = {}
	_native_begin_ranged_validation = {}

func _capture_original_shared_prefixes(requests: Array, seconds: float) -> Dictionary:
	var runtime: Dictionary = site_controller.prepare_shared_runtime_work_prefix(requests, seconds)
	if not runtime.ok: return runtime
	var wt: Dictionary = site_controller.work_team.prepare_shared_work_prefix(seconds)
	if not wt.ok: return wt
	var ladders: Dictionary = site_controller.work_team.prepare_shared_ladder_prefix(seconds, _shared_work_action_seconds)
	if not ladders.ok: return ladders
	var pa: Dictionary = site_controller.person_actions.prepare_shared_work_prefix(requests, seconds)
	if not pa.ok: return pa
	var nonwork: Dictionary = site_controller.person_actions.prepare_shared_nonwork_timers(seconds)
	if not nonwork.ok: return nonwork
	return SiteRuntime.ok("原provider合法起点已捕捉", {"runtime": runtime, "work_team": wt, "person_actions": pa, "nonwork": nonwork, "ladders": ladders})

func _collect_original_shared_work_requests(action_seconds: float, game_seconds: float, tactical_seconds: float, native_combat_begin: float = -1.0) -> Dictionary:
	# A segment has one exact action/game ratio. Stop at the original tactical
	# boundary before a held ladder timer can be retimed proportionally.
	if tactical_seconds > ACTION_TIME_EPSILON and tactical_seconds < action_seconds:
		action_seconds = tactical_seconds
		game_seconds = SiteRuntime.game_seconds(action_seconds, tactical_seconds) * simulation_speed
	var supplies: Dictionary = site_controller.shared_supply_event_limit(game_seconds)
	if not supplies.ok: return supplies
	game_seconds = minf(game_seconds, float(supplies.game_seconds))
	var retry := float(site_controller.work_team.next_work_event_seconds())
	if is_finite(retry) and retry > ACTION_TIME_EPSILON: game_seconds = minf(game_seconds, retry)
	if 0.5 - site_controller._work_elapsed > ACTION_TIME_EPSILON:
		action_seconds = minf(action_seconds, 0.5 - site_controller._work_elapsed)
	game_seconds = minf(game_seconds, SiteRuntime.game_seconds(action_seconds, tactical_seconds) * simulation_speed)
	action_seconds = RegionSaveSlot.GameplayClock.action_for_game(game_seconds, simulation_speed, tactical_seconds)
	var native_active: bool = crowd_site != null and crowd_site.active
	if native_active:
		if native_combat_begin < 0.0: return SiteRuntime.fail("NATIVE_COMBAT_INPUT")
		_shared_native_combat_begin = native_combat_begin
		if crowd_site._work_fatigue_tick < 0:
			var snapshot: Dictionary = crowd_site.begin_work_fatigue_interval()
			if not snapshot.ok: return snapshot
	if not restore_only: _advance_movement_input()
	for actor: TerrainTestCharacter in combat_actors:
		if native_active and crowd_site.contains_person(actor.person_id): continue
		if actor is TerrainTestNPC and actor.combat_driven_by_lab and actor.person_id != controlled_person_id(): actor.advance_navigation()
	_shared_movement_prepared = true
	site_controller._shared_worker_inputs = site_controller._prepare_original_work_inputs()
	var owners: Array = site_controller.prepare_shared_owner_work_requests(game_seconds)
	# Keep original caller order for the shared inventory reservation.
	for request: Dictionary in owners:
		if str(request.provider) == "runtime": _shared_work_requests.append(request)
	var pa_requests: Array = site_controller.person_actions.work_requests(game_seconds)
	_shared_work_requests.append_array(site_controller.work_team.prepare_work_requests(game_seconds, action_seconds, pa_requests))
	_shared_work_requests.append_array(pa_requests)
	for request: Dictionary in owners:
		if str(request.provider) != "runtime": _shared_work_requests.append(request)
	var admitted := _reserve_shared_work_payments(_shared_work_requests)
	if not admitted.ok: return admitted
	var refreshed := _refresh_shared_work_preflight()
	if not refreshed.ok: return refreshed
	var groups := _capture_shared_vehicle_groups(_shared_work_requests)
	if not groups.ok: return groups
	var moving := _shared_movement_requests(game_seconds, _shared_work_requests)
	_shared_work_requests.append_array(moving)
	if native_active:
		var runners: Dictionary = crowd_site.work_fatigue_run_requests(game_seconds, _shared_work_requests)
		if not runners.ok: return runners
		_shared_work_requests.append_array(runners.requests)
		var recovery: Dictionary = crowd_site.prepare_work_fatigue_recovery_inputs()
		if not recovery.ok: return recovery
	_shared_work_action_seconds = action_seconds
	_shared_work_game_seconds = game_seconds
	return SiteRuntime.ok("", {"action_seconds": action_seconds, "game_seconds": game_seconds})

func _native_begin_bound(requests: Array, maximum: float, combat_begin: float, preview: PackedFloat64Array) -> Dictionary:
	var combat: float = combat_begin
	for offset: int in range(0, preview.size(), 10): combat = maxf(combat, float(preview[offset + 9]))
	var action: float = minf(maximum, _region_owner_action_limit(maximum, combat))
	if combat > 0.0 and combat < action: action = combat
	var seconds: float = SiteRuntime.game_seconds(action, combat) * simulation_speed
	var supplies: Dictionary = site_controller.native_checked_supply_interval_limit(seconds)
	if not supplies.ok: return supplies
	var limit: float = minf(seconds, float(supplies.game_seconds))
	var capture: Dictionary = site_controller.Settlement.capture_sample(self)
	limit = minf(limit, site_controller.Settlement.capture_interval_limit(terrain, capture, seconds))
	limit = minf(limit, _shared_production_event_limit(seconds))
	var retry: float = float(site_controller.work_team.prepared_retry_endpoint())
	if is_finite(retry) and retry > 0.0: limit = minf(limit, retry)
	var envelope: Dictionary = site_controller.person_actions.native_fire_point_envelope_requests(seconds)
	if not envelope.ok: return envelope
	var interval_requests: Array = _native_begin_interval_requests(requests, action, seconds, combat)
	var maximum_requests: Array = interval_requests.duplicate(false)
	maximum_requests.append_array(envelope.requests)
	var run_bound: Dictionary = crowd_site.work_fatigue_run_bound_requests(seconds, maximum_requests)
	if not run_bound.ok: return run_bound
	maximum_requests.append_array(run_bound.requests)
	var projection: Dictionary = _native_begin_participant_projection(maximum_requests, preview)
	var lower: Dictionary = _plan_shared_vehicle_work_interval(interval_requests, seconds, projection)
	if not lower.ok: return lower
	var upper: Dictionary = _plan_shared_vehicle_work_interval(maximum_requests, seconds, projection)
	if not upper.ok: return upper
	for planned: Dictionary in [lower, upper]:
		for group: Dictionary in planned.pools:
			for segment: Dictionary in group.segments:
				var end: float = float(segment.begin) + float(segment.seconds)
				if end > 0.0: limit = minf(limit, end)
				var rate: float = float(segment.rate)
				var start: float = PersonFatigue.read(group.body)
				if rate > 0.0 and start < 30.0: limit = minf(limit, (30.0 - start) / rate)
				elif rate > 0.0 and start < 100.0: limit = minf(limit, (100.0 - start) / rate)
				break
	# A successful pulse sets the original formation's charged_this_step flag;
	# safe_fatigue_rest is therefore false for that pool in the actual next step.
	# Other native pools keep their exact original no-pulse rest-limit query.
	var pulsed: Dictionary = {}
	for offset: int in range(0, preview.size(), 10): pulsed[int(preview[offset + 1])] = true
	for snapshot: Dictionary in crowd_site._work_fatigue_snapshots.values():
		if pulsed.has(int(snapshot.formation)): continue
		var worked: bool = false
		for request: Dictionary in interval_requests:
			var allocation: Dictionary = lower.jobs.get(str(request.provider), {}).get(str(request.key), {})
			for participant: Dictionary in request.participants:
				if participant.get("native_snapshot") == snapshot and float(allocation.get("participant_seconds", {}).get(int(participant.person_id), 0.0)) > 0.0: worked = true
		if worked: continue
		var target: float = 0.0
		for unit: int in snapshot.owner.combat_units:
			if bool(snapshot.owner.combat_hot_get(unit, &"work_resting", false)) and float(snapshot.pool.fatigue) > 50.0: target = 50.0; break
		var idle: float = float(crowd_site.crowd.work_fatigue_rest_limit(int(snapshot.formation), target, limit, maxf(0.0, combat - action)))
		if not is_finite(idle) or idle <= 0.0: return SiteRuntime.fail("INVALID_NATIVE_REST_LIMIT")
		limit = minf(limit, idle)
	if not is_finite(limit) or limit <= 0.0: return SiteRuntime.fail("ZERO_NATIVE_BEGIN_WINDOW")
	var accepted_action: float = RegionSaveSlot.GameplayClock.action_for_game(limit, simulation_speed, minf(action, combat))
	return SiteRuntime.ok("", {"action_seconds": accepted_action, "game_seconds": limit,
		"combat_begin": combat, "lower": lower, "upper": upper, "projection": projection, "requests": interval_requests})

func _native_begin_ranged_window(phase: float, maximum: float, without_pulse: float,
		with_pulse: float, pulse_transition: float = -1.0,
		minimum_next_fatigue: float = NAN, transition_at: float = NAN) -> Dictionary:
	# Bounds are pure original-owner results, already expressed as action seconds
	# under their real no-shot/post-shot combat clocks. No game/action ratio shortcut.
	# pulse_transition is a PROVEN post-pulse fatigue band/REST boundary; never an
	# arbitrary small delta or a source/payment/capacity retry boundary.
	# The original caller must prove minimum_next_fatigue from SAME qualified
	# held WORK effort and the actual unpulsed clock, plus exact previewed pulses.
	# Unknown future RUN/P5 upper bounds provide NO minimum-effort witness.
	for value: float in [phase,maximum,without_pulse,with_pulse]:
		if not is_finite(value) or value<0.0: return SiteRuntime.fail("INVALID_NATIVE_BEGIN_WINDOW")
	if maximum<=0.0 or maximum>EXCHANGE_ACTION_STEP+ACTION_TIME_EPSILON \
		or without_pulse>maximum or with_pulse>maximum:
		return SiteRuntime.fail("INVALID_NATIVE_BEGIN_WINDOW")
	var no_due: bool = (phase+without_pulse)+ACTION_TIME_EPSILON>=EXCHANGE_QUERY_STEP
	var pulse_due: bool = (phase+with_pulse)+ACTION_TIME_EPSILON>=EXCHANGE_QUERY_STEP
	if not no_due:
		if without_pulse<=0.0: return SiteRuntime.fail("ZERO_NATIVE_BEGIN_WINDOW")
		return SiteRuntime.ok("", {"action_seconds": without_pulse,"query_due": false,"pre_query_transition": false})
	if pulse_due:
		if with_pulse<=0.0: return SiteRuntime.fail("ZERO_NATIVE_BEGIN_WINDOW")
		return SiteRuntime.ok("", {"action_seconds": with_pulse,"query_due": true,"pre_query_transition": false})
	# Feedback case: no-shot would query, but its true shot shortens before query.
	# End an unpulsed original prefix AT that previewed fatigue boundary instead.
	# Its actual phase comparator remains FALSE. The next shot reaches/crosses the
	# band's boundary at its true BEGIN, enabling original rest/reclassification.
	# Never tweak phase, subtract epsilon, force due, charge/rollback or rerun time.
	if not is_finite(pulse_transition) or pulse_transition<=0.0 \
		or pulse_transition!=with_pulse or pulse_transition>without_pulse \
		or not is_finite(minimum_next_fatigue) or not is_finite(transition_at) \
		or transition_at not in [30.0,PersonFatigue.WORK_REST_AT,100.0] \
		or minimum_next_fatigue<transition_at or minimum_next_fatigue>100.0 \
		or (phase+pulse_transition)+ACTION_TIME_EPSILON>=EXCHANGE_QUERY_STEP:
		return SiteRuntime.fail("NATIVE_BEGIN_TRANSITION_PROOF_REQUIRED")
	return SiteRuntime.ok("", {"action_seconds": pulse_transition,"query_due": false,"pre_query_transition": true})

func _native_begin_transition_witness(requests: Array, without: Dictionary, with_pulse: Dictionary,
		before_preview: PackedFloat64Array, after_preview: PackedFloat64Array) -> Dictionary:
	# Only SAME actual held WORK gives this minimum. Unknown RUN and post-contact
	# P5 give upper bounds, never a witness for terminating a feedback prefix.
	var no_pulse_pools: Dictionary = {}
	var next_pulse_pools: Dictionary = {}
	for offset: int in range(0, before_preview.size(), 10): no_pulse_pools[int(before_preview[offset + 1])] = float(before_preview[offset + 6])
	for offset: int in range(0, after_preview.size(), 10): next_pulse_pools[int(after_preview[offset + 1])] = float(after_preview[offset + 6])
	var action: float = float(with_pulse.action_seconds)
	var no_pulse_game: float = SiteRuntime.game_seconds(action, float(without.combat_begin)) * simulation_speed
	for snapshot: Dictionary in crowd_site._work_fatigue_snapshots.values():
		var formation: int = int(snapshot.formation)
		if not next_pulse_pools.has(formation): continue
		var start: float = float(next_pulse_pools[formation])
		var rate: float = 0.0
		var rest_limited: bool = false
		for request: Dictionary in requests:
			if not str(request.get("paused", "")).is_empty(): continue
			var allocation: Dictionary = with_pulse.lower.jobs.get(str(request.provider), {}).get(str(request.key), {})
			for participant: Dictionary in request.participants:
				if not is_same(participant.get("native_snapshot"), snapshot) or str(participant.get("native_effort_kind", "work")) != "work": continue
				if float(allocation.get("participant_seconds", {}).get(int(participant.person_id), 0.0)) <= 0.0: continue
				rate += float(participant.effort_rate)
				rest_limited = rest_limited or bool(participant.rest_limited)
		if rate <= 0.0: continue
		var band: float = 30.0 if start < 30.0 else PersonFatigue.WORK_REST_AT if rest_limited and start < PersonFatigue.WORK_REST_AT else 100.0
		var seconds: float = (band - start) / rate
		if seconds <= 0.0: continue
		var transition: float = RegionSaveSlot.GameplayClock.action_for_game(seconds, simulation_speed, minf(action, float(with_pulse.combat_begin)))
		if transition != action: continue
		var minimum: float = minf(100.0, start + no_pulse_game * rate)
		if minimum >= band: return {"transition": transition, "minimum_next_fatigue": minimum, "transition_at": band}
	return {}

func prepare_native_begin_ranged(action_seconds: float, register_candidate: bool = true, query_override: int = -1) -> Dictionary:
	if crowd_site == null or not crowd_site.active or crowd_site.crowd == null: return SiteRuntime.fail("CLOCK_NOT_READY")
	if _fire_committing or _fire_advancing or terrain == null or not physical_ranged_enabled \
		or not exchange_enabled or not is_finite(action_seconds) or action_seconds <= 0.0 \
		or action_seconds > EXCHANGE_ACTION_STEP + ACTION_TIME_EPSILON: return SiteRuntime.fail("INVALID_NATIVE_BEGIN_WINDOW")
	if query_override not in [-1, 0, 1] or register_candidate and query_override != -1: return SiteRuntime.fail("INVALID_NATIVE_BEGIN_WINDOW")
	var people: Array[Dictionary] = _siege_people()
	var draft: Dictionary = {"owner": self, "data": terrain, "site": terrain.site,
		"crowd_site": crowd_site, "world": crowd_site.crowd, "action_seconds": action_seconds,
		"phase": _exchange_phase, "action_cursor": fire_action_cursor,
		"query_due": _exchange_phase + action_seconds + ACTION_TIME_EPSILON >= EXCHANGE_QUERY_STEP,
		"original_reservations": fire_reservations, "reservation_refs": fire_reservations.duplicate(),
		"reservation_values": fire_reservations.duplicate(true), "reservations": fire_reservations.duplicate(true),
		"original_member_cursor": _fire_member_cursor, "cursor_values": _fire_member_cursor.duplicate(),
		"member_cursor": _fire_member_cursor.duplicate(), "original_round_robin": _fire_round_robin,
		"round_robin": _fire_round_robin, "original_sequence": _fire_release_sequence,
		"sequence": _fire_release_sequence, "original_projectiles": fire_projectiles,
		"projectile_values": fire_projectiles.duplicate(true), "capacity": fire_projectile_capacity,
		"policies": {}, "releases": [], "scheduler_result": {}, "error": {}, "published": false}
	if query_override >= 0: draft.query_due = query_override == 1
	if bool(draft.query_due):
		var selected: Dictionary = _resolve_physical_ranged_fire(people, draft)
		if not selected.ok: return selected
	# Original prior reservations are examined even if no new query is due.
	_commit_fire_releases(draft)
	if not draft.error.is_empty(): return draft.error
	var native_inputs: PackedInt64Array = PackedInt64Array()
	for row: Dictionary in draft.releases:
		var release: Dictionary = row.release
		native_inputs.append_array(PackedInt64Array([int(release.unit), int(release.amount),
			1 if str(release.mode) == "FIRE_ARROW" else 0, int(release.shot_id), release.target.x, release.target.y]))
	var preview: PackedFloat64Array = PackedFloat64Array()
	if not native_inputs.is_empty():
		# D gated only Native shooting on a fire host. A host-less Crowd site with
		# no releases keeps an empty preview instead of stalling the shared step.
		if not crowd_site.fire_host_active() or not crowd_site.crowd.has_method("preview_host_ranged_batch"): return SiteRuntime.fail("CLOCK_NOT_READY")
		preview = crowd_site.crowd.preview_host_ranged_batch(native_inputs)
		if preview.size() != draft.releases.size() * 10: return SiteRuntime.fail("STALE_NATIVE_BEGIN")
		for index: int in draft.releases.size():
			var row: Dictionary = draft.releases[index]
			var shooter: Dictionary = row.geometry.shooter.duplicate(true)
			# Original ordered sibling pulses change this shooter's pre-release
			# fatigue, and therefore its original finite pre-power trajectory.
			shooter.fatigue = float(preview[index * 10 + 4])
			row.geometry = _prepare_fire_release_flight(row.person, row.reservation, int(row.release.shot_id), shooter)
			if row.geometry.is_empty(): return SiteRuntime.fail("NO_VALID_TRAJECTORY")
	draft["native_inputs"] = native_inputs
	draft["preview"] = preview
	if register_candidate:
		_native_begin_ranged_prepared = draft
		_native_begin_ranged_validation = {}
	return SiteRuntime.ok("原射擊候選未扣彈／疲勞／時間", {"prepared": draft})

func validate_native_begin_ranged(prepared: Dictionary) -> Dictionary:
	_native_begin_ranged_validation = {}
	if not is_same(prepared, _native_begin_ranged_prepared) or prepared.get("published") != false \
		or prepared.get("owner") != self or prepared.get("data") != terrain \
		or not is_same(prepared.get("site"), terrain.site) or prepared.get("crowd_site") != crowd_site \
		or prepared.get("world") != crowd_site.crowd: return SiteRuntime.fail("STALE_NATIVE_BEGIN")
	if prepared.phase != _exchange_phase or prepared.action_cursor != fire_action_cursor \
		or int(prepared.original_sequence) != _fire_release_sequence or int(prepared.original_round_robin) != _fire_round_robin \
		or int(prepared.capacity) != fire_projectile_capacity \
		or not is_same(prepared.original_reservations, fire_reservations) or fire_reservations != prepared.reservation_values \
		or not is_same(prepared.original_member_cursor, _fire_member_cursor) or _fire_member_cursor != prepared.cursor_values \
		or not is_same(prepared.original_projectiles, fire_projectiles) or fire_projectiles != prepared.projectile_values: return SiteRuntime.fail("STALE_NATIVE_BEGIN")
	for identity: int in prepared.reservation_refs:
		if not is_same(fire_reservations.get(identity), prepared.reservation_refs[identity]): return SiteRuntime.fail("STALE_NATIVE_BEGIN")
	for policy: Dictionary in prepared.policies.values():
		if not is_instance_valid(policy.owner) or not is_same(policy.owner.ranged_fire_policy, policy.original) \
			or policy.owner.ranged_fire_policy != policy.values: return SiteRuntime.fail("STALE_NATIVE_BEGIN")
	for row: Dictionary in prepared.releases:
		if not row.release.owner.valid_prepared_host_ranged_release(row.release): return SiteRuntime.fail("STALE_NATIVE_BEGIN")
	var repeated: Dictionary = prepare_native_begin_ranged(float(prepared.action_seconds), false)
	if not repeated.ok or repeated.prepared != prepared: return SiteRuntime.fail("STALE_NATIVE_BEGIN")
	_native_begin_ranged_validation = {"owner": self, "prepared": prepared, "published": false}
	return SiteRuntime.ok("全原參照與 Native 整批只讀預檢成立", {"check": _native_begin_ranged_validation})

func publish_validated_native_begin_ranged(prepared: Dictionary, check: Dictionary) -> void:
	if bool(prepared.get("published", false)): return
	assert(is_same(prepared, _native_begin_ranged_prepared) and is_same(check, _native_begin_ranged_validation)
		and is_same(check.prepared, prepared) and check.owner == self and not bool(check.published))
	# All actual original owner/Native/source/flight guards passed before first
	# cost. No callback/yield, selector, failed guard or clock advance in this tail.
	_fire_committing = true
	for policy: Dictionary in prepared.policies.values():
		policy.owner.ranged_fire_policy = policy.projected
	fire_reservations.clear()
	fire_reservations.merge(prepared.reservations)
	_fire_member_cursor.clear()
	_fire_member_cursor.merge(prepared.member_cursor)
	_fire_round_robin = int(prepared.round_robin)
	if not prepared.scheduler_result.is_empty(): fire_scheduler_result = prepared.scheduler_result
	for index: int in prepared.releases.size():
		var row: Dictionary = prepared.releases[index]
		var release: Dictionary = row.release
		var receipt: PackedFloat64Array = crowd_site.crowd.commit_host_ranged(int(release.unit), int(release.amount),
			1 if str(release.mode) == "FIRE_ARROW" else 0, int(release.shot_id), release.target.x, release.target.y, bool(release.auto_power))
		assert(receipt.size() == 5)
		var released: Dictionary = release.owner.publish_validated_host_ranged_release(release, receipt)
		var geometry: Dictionary = row.geometry
		var profile: Dictionary = geometry.profile
		var flight: Dictionary = geometry.flight
		var offset: Vector2 = SiteCombatRules.fire_aim_offset(released.shooter, float(profile.nominal_distance), bool(geometry.aim.moving),
			terrain.seed_value, int(row.identity), int(row.reservation.serial), int(release.shot_id), float(profile.scatter_multiplier))
		flight.velocity = (geometry.nominal + geometry.right * offset.x + geometry.up * offset.y - geometry.origin) / float(flight.total) \
			+ Vector3(0, 0, 0.5 * float(profile.gravity) * float(flight.total))
		var source_formation_id: int = int(release.owner.team_id) if release.owner.has_army() else 0
		flight.merge({"projectile_id": int(release.shot_id), "source_member_id": int(row.identity), "source_formation_id": source_formation_id,
			"order_serial": int(row.reservation.serial), "spawn_action": fire_action_cursor, "source_cell": row.reservation.source,
			"shooter": released.shooter, "profile": profile, "elapsed": 0.0, "ember": float(profile.ember), "resolved": false,
			"aim_key": str(geometry.aim.key), "position": geometry.origin, "config_version": str(profile.config_version)})
		fire_projectiles.append(flight)
		_fire_unsaved = true
		ranged_shots += 1
	_fire_release_sequence = int(prepared.sequence)
	prepared.published = true
	check.published = true
	_fire_committing = false
	if not prepared.releases.is_empty():
		# True accepted BEGIN combat mark classifies this body's original clock.
		# Contacts may refresh it later without replaying accepted time.
		var grace: float = 0.0
		for offset: int in range(0, prepared.preview.size(), 10): grace = maxf(grace, float(prepared.preview[offset + 9]))
		SiteRuntime.mark_combat(terrain, grace, true)
	queue_redraw()

func _settle_native_checked_point_endpoint() -> Dictionary:
	var endpoint: Dictionary = _region_point_pending.get("native_checked", {})
	if endpoint.is_empty() or bool(endpoint.get("finished", false)): return SiteRuntime.ok()
	# Original queue life effects have now committed. Current alive/scope/source
	# authority decides products/receipts; it cannot erase paid positive prefix.
	if not crowd_site.finish_work_fatigue_point_events(): return crowd_site.last_event_error
	site_controller.person_actions.finish_native_fire_point(endpoint.fire)
	_finish_original_shared_prefixes(endpoint.checked, false)
	endpoint.finished = true
	return SiteRuntime.ok()

func _check_original_shared_prefixes(captured: Dictionary, planned: Dictionary, requests: Array, runtime_priors: Array, before_body: bool = false) -> Dictionary:
	# Pure source/material candidates may also be checked before BEGIN.
	# Only the real post-body call attaches training to the original World point.
	# ORIGINAL Runtime camp/manual checked-prefix candidates prepare first.
	var runtime: Dictionary = site_controller.validate_shared_runtime_work_prefix(captured.runtime, planned, runtime_priors)
	if not runtime.ok: return runtime
	# WT and PA receive the SAME finite source ledger and preserve original order.
	var pa: Dictionary = site_controller.person_actions.validate_shared_work_prefix(captured.person_actions, planned, requests)
	if not pa.ok: return pa
	var wt_registered: Dictionary = site_controller.work_team.prepare_shared_work_prefix_allocations(captured.work_team, planned, runtime_priors)
	if not wt_registered.ok: return wt_registered
	var pa_registered: Dictionary = site_controller.person_actions.prepare_checked_controlled_prefix_allocations(pa, runtime_priors)
	if not pa_registered.ok: return pa_registered
	# BOTH original owners register true allocations before any master/Runtime check.
	var wt: Dictionary = site_controller.work_team.validate_shared_work_runtime_prefixes(wt_registered)
	if not wt.ok: return wt
	var controlled: Dictionary = site_controller.person_actions.validate_checked_controlled_runtime_prefixes(pa_registered)
	if not controlled.ok: return controlled
	var ladders: Dictionary = site_controller.work_team.validate_shared_ladder_prefix(captured.ladders, planned)
	if not ladders.ok: return ladders
	var training: Dictionary = site_controller.validate_shared_native_training_prefix(planned, requests)
	if not training.ok: return training
	# Preparing training must precede Native final READY. This attaches it to
	# the ORIGINAL World point; the fatigue final gate then revalidates both.
	if not before_body:
		var native_training: Dictionary = crowd_site.prepare_work_training_point(training.checked)
		if not native_training.ok: return native_training
	return SiteRuntime.ok("原同held消费者均已纯预验", {"runtime": runtime, "work_team": wt, "person_actions": pa,
		"controlled": controlled, "training": training, "runtime_priors": runtime_priors, "nonwork": captured.nonwork, "ladders": ladders})

func valid_native_begin_shared_window(prepared: Dictionary) -> bool:
	return is_same(prepared, _native_begin_shared_window_prepared) and prepared.get("owner") == self \
		and is_same(prepared.get("site"), terrain.site) and prepared.get("published") == false \
		and is_same(prepared.get("ranged"), _native_begin_ranged_prepared) \
		and is_same(prepared.get("ranged_check"), _native_begin_ranged_validation) \
		and float(prepared.get("action_seconds", -1.0)) > 0.0 and float(prepared.get("game_seconds", -1.0)) > 0.0

func _native_original_army(team: TerrainArmy) -> bool:
	if crowd_site == null or not crowd_site.active: return false
	for plan: Dictionary in crowd_site._original_team_plans:
		if is_same(plan.get("source"), team): return true
	return false

func _prepare_fire_release_flight(person: Dictionary, reservation: Dictionary, shot_id: int,
        shooter_override: Dictionary = {}) -> Dictionary:
	var identity: int = int(person.id)
	var owner_ref: Variant = person.owner
	var aim := _fire_target_aim(reservation.target, identity)
	if aim.is_empty(): return {}
	var shooter: Dictionary = shooter_override if not shooter_override.is_empty() else (owner_ref.exchange_stats(int(person.unit)) if int(person.unit) >= 0 else owner_ref.exchange_stats())
	var profile := SiteCombatRules.fire_ranged_profile(str(shooter.weapon), str(reservation.mode))
	if profile.is_empty() or not SiteCombatRules.ranged_in_range(reservation.source, aim.cell, float(profile.range)): return {}
	var ground: Vector2 = owner_ref.combat_ground(int(person.unit)) if int(person.unit) >= 0 else owner_ref.position
	var origin := Vector3(ground.x / TerrainRenderer.CELL_PIXELS, ground.y / TerrainRenderer.CELL_PIXELS, _fire_surface_height(ground) + 1.0)
	var nominal: Vector3 = aim.point
	profile.nominal_distance = Vector2(nominal.x - origin.x, nominal.y - origin.y).length()
	profile["smoke_optical_depth"] = SiteRuntime.fire_smoke_optical_depth(terrain, origin, nominal)
	profile.scatter_multiplier = float(profile.scatter_multiplier) * SiteRuntime.fire_smoke_scatter_scale(terrain, origin, nominal)
	var offset := SiteCombatRules.fire_aim_offset(shooter, float(profile.nominal_distance), bool(aim.moving), terrain.seed_value, identity, int(reservation.serial), shot_id, float(profile.scatter_multiplier))
	var forward := (nominal - origin).normalized()
	var right := forward.cross(Vector3(0, 0, 1)).normalized()
	if right.length_squared() < 0.5: right = Vector3(1, 0, 0)
	var up := right.cross(forward).normalized()
	var flight := SiteCombatRules.fire_trajectory(origin, nominal + right * offset.x + up * offset.y, profile)
	if flight.is_empty(): return {}
	var auto_power: bool = identity != controlled_person_id() and (owner_ref.command_abilities.has(int(person.unit)) if int(person.unit) >= 0 else not owner_ref.command_abilities.is_empty())
	return {"aim": aim, "shooter": shooter, "profile": profile, "flight": flight,
		"origin": origin, "nominal": nominal, "right": right, "up": up, "ground": ground, "auto_power": auto_power}

func _prepare_native_shared_point_finish(held_requests: Array, action_begin: float, action_end: float, game_seconds: float) -> Dictionary:
	# Called AFTER the actual original Native World/contact endpoint, BEFORE
	# any actual Runtime/WT/PA/training cost/progress. Never prepare/select again.
	var classified: Dictionary = site_controller.person_actions.native_fire_point_candidates(action_begin, action_end, game_seconds)
	if not classified.ok: return classified
	var requests: Array = []
	for request: Dictionary in held_requests:
		if str(request.provider) != "native_run": requests.append(request) # Replace old flags with original point's true union.
	# Copies only scalar request limits; original participants/bodies/pools stay
	# SAME refs. No real _jobs/pending/holder/formation are copied or modified.
	for request: Dictionary in classified.requests: requests.append(request.duplicate(false))
	var actual_run: Dictionary = crowd_site.work_fatigue_point_run_requests(game_seconds, requests)
	if not actual_run.ok: return actual_run
	requests.append_array(actual_run.requests)
	var previous_limits := {}
	# Original finite integer source/heat quota can only decrease. Each retry
	# makes at least one job's admitted integer quantity fall; finite bound is
	# all actual requested quantities + number of jobs, not elapsed-time polling.
	var remaining_reductions: int = classified.requests.size() + 1
	for row: Dictionary in classified.records:
		if str(row.status) != "WORK": continue
		var profile: Dictionary = SiteCombatRules.fire_work_profile(str(row.job.get("fire_work_mode", "SUPPRESS")))
		remaining_reductions += ceili(float(row.limit) / float(row.ratio) * int(profile.supply_q_per_second) + float(row.job.fraction_q))
	while remaining_reductions > 0:
		remaining_reductions -= 1
		var planned: Dictionary = _plan_shared_vehicle_work_interval(requests, game_seconds)
		if not planned.ok: return planned
		var fire: Dictionary = site_controller.person_actions.prepare_native_fire_point(classified.records, planned)
		if not fire.ok: return fire
		if not bool(fire.get("needs_replan", false)):
			return SiteRuntime.ok("原同點真接觸結果與有限供給已純預驗", {
				"plan": planned, "requests": requests, "fire": fire,
				"action_seconds": action_end - action_begin, "game_seconds": game_seconds})
		var reduced := false
		for request: Dictionary in requests:
			if str(request.provider) != "fire_suppress" or not fire.limits.has(str(request.key)): continue
			var key: String = str(request.key)
			var next: float = float(fire.limits[key])
			var old: float = float(request.max_game_seconds)
			if not is_finite(next) or next < 0.0 or next >= old - PersonFatigue.WORK_PLAN_EPS \
				or previous_limits.has(key) and next >= float(previous_limits[key]) - PersonFatigue.WORK_PLAN_EPS:
				return SiteRuntime.fail("INVALID_FIRE_REPLAN", "有限配額未嚴格縮減；尚未支付")
			request.max_game_seconds = next
			request.remaining = next
			previous_limits[key] = next
			reduced = true
		if not reduced: return SiteRuntime.fail("INVALID_FIRE_REPLAN")
	return SiteRuntime.fail("INVALID_FIRE_REPLAN", "有限整數配額未收斂；尚未支付")

func _publish_original_shared_prefixes(checked: Dictionary) -> void:
	# Native is already READY; no more predicates/callbacks/allocations/cost checks.
	site_controller.publish_shared_runtime_work_prefix(checked.runtime)
	site_controller.work_team.publish_shared_work_prefix(checked.work_team)
	site_controller.work_team.publish_shared_ladder_prefix(checked.ladders)
	site_controller.person_actions.begin_shared_work_prefix_consumption(checked.person_actions)
	site_controller.person_actions.publish_checked_controlled_prefixes(checked.controlled)
	site_controller.person_actions.publish_shared_job_prefix_timers(checked.person_actions)
	site_controller.person_actions.end_shared_work_prefix_consumption()
	# Caller next publishes prevalidated P5 fire, then ORIGINAL CrowdSite point.
	# Training is already staged INSIDE that same World publisher, not a setter.

func _native_begin_interval_requests(requests: Array, action_seconds: float, game_seconds: float, combat: float) -> Array:
	# Clock classification changes ONLY these interval quantities. Every real
	# body/pool/task/authority reference remains the original collector's ref.
	var result: Array = []
	for request: Dictionary in requests:
		var current: Dictionary = request
		if str(request.provider) == "work_team" and str(request.key).begins_with("ladder:"):
			var key: String = str(request.key).trim_prefix("ladder:")
			var held: Dictionary = site_controller.work_team._prepared_ladders.get(key, {})
			if not held.is_empty():
				current = request.duplicate(false)
				var duration: float = 12.0 if str(held.pending) == "deploy" else 8.0
				current.remaining = maxf(0.0, duration - float(held.progress)) * game_seconds / action_seconds
				current.max_game_seconds = game_seconds
		elif str(request.provider) == "training":
			current = request.duplicate(false)
			current.remaining = game_seconds
			current.max_game_seconds = game_seconds
			# An actual successful BEGIN pulse establishes combat BEFORE this
			# interval. It never grants peaceful training after that real event.
			if combat > 0.0 and str(current.get("paused", "")).is_empty(): current.paused = "COMBAT"
		result.append(current)
	return result

func _native_begin_participant_projection(requests: Array, preview: PackedFloat64Array) -> Dictionary:
	var pools: Dictionary = {}
	for offset: int in range(0, preview.size(), 10):
		var formation: int = int(preview[offset + 1])
		pools[formation] = {"fatigue": float(preview[offset + 6]), "fatigue_rest": float(preview[offset + 7]),
			"count": int(preview[offset + 3]), "active": false}
	var projected: Dictionary = {}
	for request: Dictionary in requests:
		for participant: Dictionary in request.participants:
			if not participant.has("native_snapshot"): continue
			var formation: int = int(participant.native_snapshot.formation)
			if not pools.has(formation): continue
			var person: Dictionary = participant.duplicate(false)
			person.body = {"_fatigue_pool": pools[formation], "work_resting": bool(participant.body.get("work_resting", false))}
			projected[int(person.person_id)] = person
	return projected

func _settle_siege_fire_pot_impact(flight: Dictionary, event: Dictionary) -> void:
	if flight.get("ammo") != "fire_pot" or bool(flight.get("fire_resolved", false)): return
	if _region_queue_original_endpoint("siege_fire_pot_impact", {"flight": flight, "event": event}): return
	flight.fire_resolved = true
	var fraction := float(event.fraction)
	var position := _siege_world_at(flight, fraction)
	var elapsed := fraction * float(flight.total)
	var profile: Dictionary = flight.fire_profile
	var heat := maxf(0.0, float(profile.ember) - elapsed * float(profile.air_decay)
		- SiteRuntime.fire_rain_integral(terrain, float(flight.spawn_action), float(flight.spawn_action) + elapsed) * float(profile.rain_decay))
	var terminal := str(event.type)
	var thermal := {"heat_transfer": 1.0, "contact_scale": 1.0}
	if event.has("person"):
		terminal = "person"
		var person: Dictionary = event.person
		var defense: Dictionary = person.owner.ranged_defense(int(person.unit)) if int(person.unit) >= 0 else person.owner.ranged_defense()
		thermal = SiteCombatRules.fire_contact_result({}, defense, float(event.get("incidence", 1.0)), bool(event.get("shield", false)), 1.0, true)
	var cell := Vector2i(floori(position.x), floori(position.y))
	if not terrain.contains(cell) or terminal == "ground" and terrain.water_kind[terrain.index(cell)] != 0 or str(event.stable) == "boundary": heat = 0.0
	var payload := {"site_id": str(terrain.site.id), "event_id": "arrow:%d" % int(flight.projectile_id),
		"projectile_id": int(flight.projectile_id), "target_key": str(event.stable), "type": terminal,
		"action_time": float(flight.spawn_action) + elapsed, "position": position, "remaining_heat_budget": heat,
		"heat_rate": float(profile.contact_rate), "max_seconds": float(profile.contact_seconds),
		"heat_transfer": float(thermal.get("heat_transfer", 1.0)), "contact_scale": float(thermal.get("contact_scale", 1.0)), "cell": cell}
	if event.has("feature"): payload.feature = event.feature; payload.part = event.part
	if event.has("person"): payload.person_id = int(event.person.id)
	var received := SiteRuntime.fire_receive_impact(terrain, payload)
	if not received.ok: _latch_fire_boundary_error(received)
	elif event.has("person") and not bool(received.get("duplicate", false)): _receive_fire_body_contact(event.person, payload)
	fire_impact_recorder.append(payload)
	if fire_impact_recorder.size() > 256: fire_impact_recorder.pop_front()
	if fire_ignition_sink.is_valid() and heat > 0.0: fire_ignition_sink.call(payload)
	if not flight.get("tech_trial", {}).is_empty(): site_controller.person_actions.record_fire_pot_impact(flight, received, float(payload.action_time))

func _finish_original_shared_prefixes(checked: Dictionary, finish_clock: bool = true) -> void:
	# AFTER actual Native common publisher; current endpoints still original.
	site_controller.finish_shared_runtime_work_prefix(checked.runtime)
	site_controller.work_team.finish_shared_ladder_prefix(checked.ladders)
	site_controller.work_team.finish_shared_work_prefix(checked.work_team)
	site_controller.person_actions.finish_shared_job_prefix_timers(checked.person_actions)
	site_controller.person_actions.finish_shared_nonwork_timers(checked.nonwork)
	site_controller.person_actions.finish_checked_controlled_prefixes(checked.controlled)
	site_controller.person_actions.finish_shared_work_prefix(checked.person_actions)
	site_controller.finish_shared_native_training_prefix(checked.training)
	if finish_clock: site_controller.finish_shared_runtime_clock()
	_shared_vehicle_groups.clear()
	checked.runtime_priors.clear() # Original endpoint has used every candidate; break transient ledger cycles.
	# Original settle_after_contacts/current product/receipt/life/death handoff
	# follows. Never rerun elapsed Runtime.advance/World.step or retry selection.

func _native_begin_policy(draft: Dictionary, owner_ref: Variant) -> Dictionary:
	var key: int = int(owner_ref.get_instance_id())
	if not draft.policies.has(key):
		var original: Dictionary = owner_ref.ranged_fire_policy
		draft.policies[key] = {"owner": owner_ref, "original": original,
			"values": original.duplicate(true), "projected": original.duplicate(true)}
	return draft.policies[key].projected

func _region_defer_native_environment_damage(identity: int, loss: float) -> bool:
	if not _region_deferring_endpoint() or crowd_site == null or not crowd_site.active \
		or not crowd_site.contains_person(identity) or not is_finite(loss) or loss < 0.0: return false
	var owner: Variant = crowd_site.person_owner(identity)
	if not owner is CrowdPersonOwner: return false
	var unit := int(owner.index_for_identity(identity))
	if unit < 0 or not owner.combat_units.has(unit): return false
	# Store original refs; never duplicate the original body/people map.
	_region_point_contacts.append({"kind": "native_environment", "person_id": identity,
		"packet": {"owner": owner, "unit": unit, "body": owner.combat_units[unit], "loss": loss, "environmental": true}})
	return true

func native_checked_forecast_hp(identity: int) -> float:
	# Read actual native HP and only the SAME original point's accepted Sustain
	# loss candidate. This read grants no work/start/receipt permission.
	if crowd_site == null or not crowd_site.contains_person(identity): return 0.0
	var hp: float = crowd_site.work_fatigue_forecast_hp(identity)
	var prepared: Dictionary = _native_begin_shared_window_prepared.get("sustain", {})
	if prepared.is_empty() or bool(prepared.get("published", false)): return hp
	for row: Dictionary in prepared.rows:
		hp = maxf(0.0, hp - float(row.input.damage.get(identity, 0.0)))
	return hp

var _region_map_motion_proposal: Dictionary = {}

func publish_region_party_map_motion(candidate: Dictionary, motion: Dictionary,
		game_seconds: float, action_seconds: float) -> Dictionary:
	var slot: RegionSaveSlot = site_controller.region_slot
	if slot == null or motion.get("token") != _region_party_token \
			or motion.get("body_hash") != _region_party_input_hash \
			or motion.get("bind_token") != str(_region_bind_receipt_value.get("token", "")) \
			or int(motion.get("generation", -1)) != int(slot._marker.generation) \
			or int(motion.get("runtime_revision", -1)) != int(slot.region_registry().revision) \
			or absf(float(motion.get("game_begin", -1.0)) - float(slot.control.logical_game_seconds)) > ACTION_TIME_EPSILON \
			or absf(float(motion.get("action_begin", -1.0)) - float(slot.control.fire_clock.action_seconds)) > ACTION_TIME_EPSILON \
			or game_seconds <= float(motion.game_begin) or action_seconds <= float(motion.action_begin):
		return SiteRuntime.fail("STALE_REGION_MAP_MOTION")
	var refs := _region_owner_references()
	if refs.size() != motion.native_references.size(): return SiteRuntime.fail("STALE_REGION_MAP_MOTION")
	for key: String in refs:
		if not motion.native_references.has(key) or not is_same(refs[key], motion.native_references[key]):
			return SiteRuntime.fail("STALE_REGION_MAP_MOTION", key)
	# Capture the already paid original timer state. Projecting an earlier graph
	# would overwrite its down/get-up/death timers with unpaid historical values.
	var actual: Dictionary = _region_capture_original_party(self, candidate, slot, game_seconds, action_seconds)
	if not actual.ok: return actual
	var navigation: Dictionary = slot.prepare_region_route_context(null, actual.party)
	if not navigation.ok: return navigation
	var current_geometry: Dictionary = RegionRoute.party_frame_geometry(slot.source, motion.frame, navigation.context)
	if not current_geometry.ok: return current_geometry
	var prepared_sources: Array = motion.geometry.geometry_proof.sources
	var current_sources: Array = current_geometry.geometry_proof.sources
	if prepared_sources.size() != current_sources.size(): return SiteRuntime.fail("STALE_REGION_MAP_GEOMETRY")
	for index: int in prepared_sources.size():
		for field: String in ["site", "offset", "visited", "navigation_hash"]:
			if prepared_sources[index].get(field) != current_sources[index].get(field): return SiteRuntime.fail("STALE_REGION_MAP_GEOMETRY", field)
	motion.geometry = current_geometry
	var projected: Dictionary = RegionPartyTravel.project_party_frame(actual.party, motion.frame)
	if not projected.ok: return projected
	motion.geometry.data.site = terrain.site.duplicate(true)
	for field: String in RegionPartyTravel.CONTENT_DICTS: motion.geometry.data.site[field] = projected.party.content.get(field, {}).duplicate(true)
	motion.geometry.data.site.armies = projected.party.content.armies.duplicate(true)
	var checkpoint := slot.region_party_checkpoint_context(_region_party_token, "region_barrier", false, {"map_motion": _region_party_token})
	if not checkpoint.ok: return checkpoint
	var context: Dictionary = checkpoint.context.duplicate(true)
	var owners := capture_region_owner_state(context)
	if not owners.ok: return owners
	var decoded: Dictionary = RegionOwnerSnapshot.validate_for_bind(owners.owner_states.scene,
		func(key: String, kind: int) -> bool: return refs.has(key) and typeof(refs[key]) == kind, context)
	if not decoded.ok: return decoded
	var shifted: Dictionary = RegionPartyTravel.project_owner_coordinates(decoded.roots, projected.projection)
	if not shifted.ok: return shifted
	var renamed := refs.duplicate()
	var lease_keys := {}
	var key_map := {}
	for key: String in decoded.roots.reference_objects:
		if not key.begins_with("lease:"): continue
		var value: Dictionary = decoded.roots.reference_objects[key].values
		var offset := RegionPartyTravel._frame_offset(projected.projection, "people", value.member_id,
			Vector2i(int(projected.projection.default_offset[0]), int(projected.projection.default_offset[1])))
		var cell: Vector2i = value.cell + offset
		var next_key := "lease:%d:%d" % [cell.x, cell.y]
		key_map[key] = next_key
		if lease_keys.has(next_key): return SiteRuntime.fail("AMBIGUOUS_FRAME_ALIAS")
		lease_keys[next_key] = refs[key]
		renamed.erase(key)
	for key: String in lease_keys:
		if renamed.has(key) and not is_same(renamed[key], lease_keys[key]): return SiteRuntime.fail("AMBIGUOUS_FRAME_ALIAS")
		renamed[key] = lease_keys[key]
	_region_map_reference_keys(shifted.roots, key_map, [])
	var scene: Dictionary = RegionOwnerSnapshot.capture_bind_roots(shifted.roots, context)
	if not scene.ok: return scene
	var restore: Dictionary = prepare_restore_region_owner_state({"scene": scene.state}, context, renamed, motion.geometry.data)
	if not restore.ok: return restore
	# The preflight resolves every old lease/plan to the very same native Object.
	# Its stale guard compares the current original table before publication.
	restore.original_references = refs
	var fields := _region_map_native_coordinate_values(projected.projection)
	if not fields.ok: return fields
	var old_geometry := _region_map_geometry_values(terrain)
	var old_receipt := _region_owner_restore_receipt.duplicate(true)
	var old_bound := _region_bind_receipt_value.duplicate(true)
	_region_map_publish_geometry(terrain, _region_map_geometry_values(motion.geometry.data))
	for row: Dictionary in fields.rows: _region_map_apply_native_values(row.owner, row.next)
	var published := publish_restore_region_owner_state(restore)
	if not published.ok:
		for row: Dictionary in fields.rows: _region_map_apply_native_values(row.owner, row.before)
		_region_map_publish_geometry(terrain, old_geometry)
		return published
	# This operation retains the original bind; its pre-existing full receipt
	# still names the SAME lab/data/Objects. No new bind token is manufactured.
	_region_owner_restore_receipt = old_receipt; _region_bind_receipt_value = old_bound
	var frame: Dictionary = motion.frame.duplicate(true)
	frame.game_seconds = game_seconds; frame.action_seconds = action_seconds
	var result: Dictionary = candidate.duplicate(true)
	result.upkeep.live.frame = frame
	result.upkeep.live.upkeep = "mapBody"
	result.upkeep.live.geometry_proof = motion.geometry.geometry_proof.duplicate(true)
	terrain.set_meta(&"region_party_world_frame", frame.duplicate(true))
	terrain.set_meta(&"region_party_geometry_sources", motion.geometry.sources)
	terrain.set_meta(&"region_party_geometry_proof", motion.geometry.geometry_proof)
	var captured := _region_capture_original_party(self, result, slot, game_seconds, action_seconds)
	if not captured.ok: return captured
	_region_map_motion_proposal = {}
	return SiteRuntime.ok("", {"party": captured.party, "same_original_body": true})

func _region_map_native_coordinate_values(projection: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	for actor: TerrainTestCharacter in combat_actors:
		if not actor_present(actor): continue
		var offset := RegionPartyTravel._frame_offset(projection, "people", actor.person_id, Vector2i.ZERO)
		var previous := {"terrain_cell": actor.terrain_cell, "movement_from_cell": actor.movement_from_cell,
			"position": actor.position, "_movement_start": actor._movement_start}
		if actor is TerrainTestNPC: previous.merge({"target_cell": actor.target_cell, "_path": actor._path.duplicate()})
		var next := previous.duplicate(true)
		for key: String in next:
			if key == "_path":
				for index: int in next[key].size(): next[key][index] = RegionPartyTravel._frame_point(next[key][index], offset)
			else: next[key] = RegionPartyTravel._frame_point(next[key], offset, key in ["position", "_movement_start"])
		rows.append({"owner": actor, "before": previous, "next": next})
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled: continue
		var previous := {}
		var next := {}
		var offset := RegionPartyTravel._frame_offset(projection, "teams", team.team_id, Vector2i.ZERO)
		for field: String in ["cells", "combat_slots", "moving_to", "desired_cells", "edge_targets"]:
			var original: Array = team.get(field)
			if original.size() != team.combat_units.size(): return SiteRuntime.fail("PARTY_BODY_CLOSURE", field)
			previous[field] = original.duplicate()
			var points := original.duplicate()
			for index: int in points.size():
				var person_offset := RegionPartyTravel._frame_offset(projection, "people", team.combat_identity(index), offset)
				points[index] = RegionPartyTravel._frame_point(points[index], person_offset)
			next[field] = points
		for field: String in ["command_reference", "pursuit_origin", "combat_goal", "player_goal",
			"_last_follow_player_cell", "_last_follow_leader_cell", "_march_goal", "_path_start", "_path_goal", "_path_route_goal",
			"_formation_anchor_cell", "_exit_rally_anchor", "_distance_origin"]:
			previous[field] = team.get(field)
			next[field] = RegionPartyTravel._frame_point(previous[field], offset)
		for field: String in ["_captain_trail", "_formation_slot_cells", "_exit_rally_slots", "_path_route", "_path_route_snapshot", "_formation_bend_followup", "_formation_bend_order"]:
			var points: Array = team.get(field)
			previous[field] = points.duplicate()
			var moved: Array = points.duplicate()
			for index: int in moved.size(): moved[index] = RegionPartyTravel._frame_point(moved[index], offset)
			next[field] = moved
		for field: String in ["_cell_owners", "_reserved_cells", "_captain_trail_progress_cache"]:
			var owners: Dictionary = team.get(field)
			previous[field] = owners.duplicate()
			var moved := {}
			for cell: Variant in owners:
				if not cell is Vector2i: return SiteRuntime.fail("INVALID_REGION_MOVEMENT")
				moved[RegionPartyTravel._frame_point(cell, offset)] = owners[cell]
			next[field] = moved
		rows.append({"owner": team, "before": previous, "next": next})
		for index: int in team.combat_units.size():
			var row: Dictionary = team.combat_units[index]
			var person_offset := RegionPartyTravel._frame_offset(projection, "people", team.combat_identity(index), offset)
			var old_shapes: Array = row.get("previous", [])
			var moved_shapes: Array[PackedVector2Array] = []
			for polygon: PackedVector2Array in old_shapes:
				var shifted := polygon.duplicate()
				for vertex: int in shifted.size(): shifted[vertex] += Vector2(person_offset) * TerrainRenderer.CELL_PIXELS
				moved_shapes.append(shifted)
			rows.append({"owner": row, "before": {"previous": old_shapes.duplicate()}, "next": {"previous": moved_shapes}})
	# Vehicle records are original Dictionary owners, never fabricated hull poses.
	for identity: String in terrain.site.get("vehicles", {}):
		var vehicle: Dictionary = terrain.site.vehicles[identity]
		var proposal: Dictionary = projection.vehicles.get(identity, {})
		if not vehicle.get("move", {}).is_empty() or not proposal.has("to_index"):
			return SiteRuntime.fail("ORIGINAL_VEHICLE_MOTION_REQUIRED")
		rows.append({"owner": vehicle, "before": {"cell": int(vehicle.cell)}, "next": {"cell": int(proposal.to_index)}})
	return SiteRuntime.ok("", {"rows": rows})

static func _region_map_reference_keys(value: Variant, maps: Dictionary, seen: Array) -> void:
	if not (value is Dictionary or value is Array): return
	for old: Variant in seen:
		if is_same(old, value): return
	seen.append(value)
	if value is Dictionary:
		if value.size() == 2 and value.get("@region_reference") is String:
			var key := str(value["@region_reference"])
			if maps.has(key): value["@region_reference"] = maps[key]
			return
		for next: Variant in value.values(): _region_map_reference_keys(next, maps, seen)
	else:
		for next: Variant in value: _region_map_reference_keys(next, maps, seen)

static func _region_map_apply_native_values(owner: Variant, values: Dictionary) -> void:
	for field: String in values:
		var old: Variant = owner.get(field)
		if old is Array and values[field] is Array: old.assign(values[field])
		elif old is Dictionary and values[field] is Dictionary:
			old.clear(); old.merge(values[field])
		elif owner is Dictionary: owner[field] = values[field]
		else: owner.set(field, values[field])

static func _region_map_geometry_values(data: TerrainData) -> Dictionary:
	var values := {}
	for field: String in ["size", "height_levels", "surface_types", "flags", "ramp_edges", "detail_variation",
		"fertility", "moisture", "drainage", "foundation", "groundwater", "water_kind", "water_body", "static_blocked",
		"feature_at", "facility_cells", "walk_height_levels", "bridge_walkable", "bridge_navigation_flags", "walk_ramp_edges",
		"cliff_drops", "has_raised_surfaces", "has_navigation_overrides", "navigation_revision", "environment_revision"]:
		values[field] = data.get(field)
	return values

static func _region_map_publish_geometry(data: TerrainData, values: Dictionary) -> void:
	for field: String in values: data.set(field, values[field])
