class_name TerrainLab
extends Node2D

const MIN_ZOOM := 0.1
const MAX_ZOOM := 10.0
const ZOOM_STEP := 1.20
const ACTION_STEP := 1.0 / 120.0
const ACTION_TIME_EPSILON := 0.000000000001
const Site = preload("res://scripts/terrain_lab/site_controller.gd")
const SiteEnv = preload("res://scripts/terrain_lab/site_environment.gd")
const FatigueGeometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
var site_controller: Node
var pause_when_unfocused := true

var terrain: TerrainData
var renderer: TerrainRenderer
var character: TerrainTestCharacter
var npc: TerrainTestNPC
var army: TerrainArmy
var opposing_army: TerrainArmy
var combat_armies: Array[TerrainArmy] = []
var camera: Camera2D
var preset_dropdown: OptionButton
var seed_input: LineEdit
var generate_button: Button
var debug_toggle: CheckButton
var movement_toggle: CheckButton
var npc_command_dropdown: OptionButton
var npc_command_button: Button
var info: Label
var parameters_label: Label
var status: Label
var generation_ms: float = 0.0
var _dragging: bool = false
var _info_time: float = 0.0
var _held_directions: Dictionary = {}
var _last_direction_key: int = -1
var _move_cooldown: float = 0.0
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
var fatigue_zero_fast_path_enabled := false # Exact zero-effort Army row shortcut; opt-in measurement first.
var fatigue_zero_eligible_rows := 0 # Counts, not microseconds; profiling only.
var fatigue_zero_skipped_advances := 0
var fixed_action_steps_enabled := false # A/B: retain incomplete 120 Hz time, never clamp or discard it.
var _action_time_remainder := 0.0 # Lab clock phase only, not a second simulation/person state.
var exchange_enabled := true # 2026-09-14 approved rule replacement; false is historical geometry mode.
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

func _combat_profile_stage(stage: String, started: int) -> int:
	if not combat_profile_enabled:
		return 0
	var now := Time.get_ticks_usec()
	combat_profile_usec[stage] = int(combat_profile_usec.get(stage, 0)) + now - started
	return now

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_default_clear_color(Color("1d242b"))
	renderer = TerrainRenderer.new()
	renderer.name = "TerrainRenderer"
	add_child(renderer)
	character = TerrainTestCharacter.new()
	character.exchange_enabled = exchange_enabled
	character.name = "MovementTestCharacter"
	character.process_mode = Node.PROCESS_MODE_PAUSABLE
	character.z_index = 10
	add_child(character)
	character.initialize_visual()
	npc = TerrainTestNPC.new()
	npc.exchange_enabled = exchange_enabled
	npc.name = "CommandTestNPC"
	npc.process_mode = Node.PROCESS_MODE_PAUSABLE
	npc.z_index = 11
	add_child(npc)
	npc.initialize_visual()
	character.opponent = npc
	npc.opponent = character
	character.person_id = 1
	npc.person_id = 2
	npc.faction_id = 1
	npc.auto_face = true
	combat_actors.assign([character, npc])
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
	combat_armies.assign([army, opposing_army])
	army.external_blocker = func(cell: Vector2i) -> bool: return opposing_army.blocks_cell(cell)
	opposing_army.external_blocker = func(cell: Vector2i) -> bool: return army.blocks_cell(cell)
	for team: TerrainArmy in combat_armies:
		team.person_id_allocator = _allocate_army_person_ids
		team.exchange_enabled = exchange_enabled
		team.contact_query = _collect_unit_contacts
		team.enemy_query = _nearest_unit_enemy
		team.target_query = _army_target
		team.combat_target_query = _combat_target
		team.exchange_people_query = _exchange_people
		team.contact_sink = func(packet: Dictionary) -> void: _combat_contacts.append(packet)
	for actor: TerrainTestCharacter in combat_actors:
		actor.army_contacts = _collect_army_contacts
		actor.combat_target_query = _combat_target
		actor.combat_mode_query = has_combat_armies
		actor.training_query = _original_actor_training.bind(actor)
	character.cell_blocker = Callable(army, "blocks_cell")
	npc.cell_blocker = Callable(army, "blocks_cell")
	camera = Camera2D.new()
	camera.name = "LabCamera"
	add_child(camera)
	_build_ui()
	site_controller = Site.new()
	site_controller.name = "SiteController"
	add_child(site_controller)
	site_controller.setup(self)
	for team: TerrainArmy in combat_armies:
		team.roster_transfer_hook = Callable(site_controller, "move_team_supply_members")
		team.sustain_routed_query = Callable(site_controller, "team_is_routed")
		team.player_supply_hook = Callable(site_controller, "player_supply_change")
	generate_from_ui()
	if FileAccess.file_exists(site_controller.save_path):
		site_controller.load_current()
	site_controller.focus_camp()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and pause_when_unfocused:
		if site_controller != null and terrain != null and not terrain.site.is_empty() and not site_controller._exit_pending and not bool(terrain.site.paused):
			site_controller.toggle_pause()
			site_controller.message.text = "離開遊玩視窗，時間已暫停；按「繼續」恢復。"

func _build_ui() -> void:
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
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.add_theme_font_size_override("font_size", 22)
	margin.add_child(column)
	_label(column, "TERRAIN GENERATOR LAB", 25)
	_label(column, "100 x 100 cells | 64 px per cell\nStandalone terrain / no world integration", 18)
	preset_dropdown = OptionButton.new()
	preset_dropdown.add_theme_font_size_override("font_size", 22)
	for preset_name: String in TerrainPreset.NAMES:
		preset_dropdown.add_item(preset_name)
	preset_dropdown.select(TerrainPreset.Kind.TERRACED_HIGHLAND)
	column.add_child(preset_dropdown)
	seed_input = LineEdit.new()
	seed_input.text = "12345"
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
	debug_toggle.add_theme_font_size_override("font_size", 20)
	column.add_child(debug_toggle)
	debug_toggle.toggled.connect(func(enabled: bool) -> void:
		renderer.debug_enabled = enabled
		renderer.redraw())
	movement_toggle = CheckButton.new()
	movement_toggle.text = "Movement test"
	movement_toggle.button_pressed = true
	movement_toggle.add_theme_font_size_override("font_size", 20)
	column.add_child(movement_toggle)
	movement_toggle.toggled.connect(func(enabled: bool) -> void:
		character.visible = enabled
		npc.visible = enabled
		npc.set_process(enabled)
		if not enabled:
			_clear_movement_input())
	_label(column, "NPC command test", 20)
	npc_command_dropdown = OptionButton.new()
	npc_command_dropdown.add_theme_font_size_override("font_size", 19)
	for command_name: String in TerrainTestNPC.COMMAND_NAMES:
		npc_command_dropdown.add_item(command_name)
	npc_command_dropdown.select(TerrainTestNPC.Command.MOVE_TO_CELL)
	column.add_child(npc_command_dropdown)
	npc_command_button = _button(column, "Issue NPC command", issue_npc_command)
	_label(column, "Move: issue command, then click a destination.", 16)
	_button(column, "NPC female parts / animation", npc.open_editor)
	_label(column, "COMBAT TEST | Space: attack | G: guard", 18)
	_button(column, "Attack NPC (equipped weapon)", func() -> void: character.start_attack(npc))
	selected_army_label = _label(column, "點選軍隊格位選中士兵；不會搬動玩家。", 16)
	_button(column, "攻擊選中的士兵（Space）", attack_selected_soldier)
	_button(column, "救助選中的友軍（相鄰四秒）", rescue_selected_soldier)
	_button(column, "NPC attacks player", func() -> void:
		npc.issue_command(TerrainTestNPC.Command.STOP)
		npc.start_attack(character))
	var retaliate := CheckButton.new()
	retaliate.text = "NPC auto counterattack (in reach)"
	column.add_child(retaliate)
	retaliate.toggled.connect(func(enabled: bool) -> void: npc_retaliates = enabled)
	_button(column, "Reset health / revive", func() -> void:
		character.reset_combat()
		npc.reset_combat())
	_button(column, "Rescue adjacent ally (4s)", func() -> void: character.start_rescue(npc))
	var allied := CheckButton.new()
	allied.text = "NPC is allied (melee obstruction / rescue test)"
	column.add_child(allied)
	allied.toggled.connect(func(enabled: bool) -> void:
		if character.action_time <= 0.0 and npc.action_time <= 0.0 and character.projectiles.is_empty() and npc.projectiles.is_empty():
			npc.faction_id = character.faction_id if enabled else 1
		else:
			allied.set_pressed_no_signal(npc.faction_id == character.faction_id))
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
		npc.collision_debug = enabled)
	var camera_row := HBoxContainer.new()
	_button(column, "Player parts / animation", character.open_editor)
	column.add_child(camera_row)
	_button(camera_row, "Fit map", fit_map)
	_button(camera_row, "64px / cell", func() -> void:
		camera.zoom = Vector2.ONE
		camera.position = character.position - Vector2(220, 0)
		camera.force_update_scroll())
	_label(column, "Click ground: place test character\nHold WASD / arrows: walk\nHold Shift + WASD: run\nF: mount / dismount\nWheel: mouse-centred zoom (up to 10x)\nHold right / middle mouse: drag camera\nBright arrow: ramp (points uphill)\nRock edge: blocked crossing", 18)
	info = _label(column, "", 20)
	status = _label(column, "", 18)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 380

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
	if seed_input.text.is_valid_int():
		seed_input.text = str(seed_input.text.to_int() + delta)
		generate_from_ui()

func generate_from_ui() -> void:
	if not seed_input.text.is_valid_int():
		status.text = "Seed must be an integer. Existing terrain was not changed."
		return
	if site_controller != null and not site_controller.archive_before_replace():
		return
	var started: int = Time.get_ticks_usec()
	var generated := TerrainGenerator.generate(preset_dropdown.selected, seed_input.text.to_int())
	SiteEnv.initialize(generated)
	generation_ms = float(Time.get_ticks_usec() - started) / 1000.0
	bind_terrain(generated)

func exchange_snapshot_guard(value: TerrainData) -> Dictionary:
	if exchange_enabled and value != null:
		for state: Dictionary in value.site.get("actors", {}).values():
			if not state.get("projectiles", []).is_empty():
				return SiteRuntime.fail("UNSUPPORTED_ACTIVE_PROJECTILES", "此舊快照仍有精確碰撞箭；不能改成新落點事件，原檔與現場保留")
	return SiteRuntime.ok()

func bind_terrain(value: TerrainData) -> void:
	if has_ranged_projectiles():
		if site_controller != null:
			site_controller.show_result(SiteRuntime.fail("BUSY", "箭矢仍在飛行，不能換場或遺失已扣彈藥的結算"))
		return
	var compatible := exchange_snapshot_guard(value)
	if not compatible.ok:
		if site_controller != null:
			site_controller.show_result(compatible)
		return # Defensive public boundary; loading commands preflight before any commit.
	_action_time_remainder = 0.0 # A replaced/loaded Site starts from its own saved simulation time.
	_exchange_phase = 0.0
	_exchange_round = 0
	ranged_shots = 0
	ranged_resolutions = 0
	for kind: String in ranged_results:
		ranged_results[kind] = 0
	army.clear()
	if opposing_army != null:
		opposing_army.clear()
	TerrainArmy.release_contact_source()
	_clear_movement_input()
	_npc_target_pending = false
	terrain = value
	character.terrain_cell = Vector2i(-1, -1)
	npc.terrain_cell = Vector2i(-1, -1)
	renderer.display(terrain)
	character.data = terrain
	character.place(terrain.cell_from_index(int(terrain.site.get("player_cell", terrain.index(terrain.spawn_cell)))), true)
	character.reset_combat()
	npc.set_data(terrain)
	var worker_cell := terrain.cell_from_index(int(terrain.site.worker.cell))
	if not terrain.is_walkable(worker_cell) or worker_cell == character.terrain_cell:
		worker_cell = _find_npc_spawn_cell()
	npc.place(worker_cell, true)
	npc.issue_command(TerrainTestNPC.Command.STOP)
	npc.reset_combat()
	var actor_states: Dictionary = terrain.site.get("actors", {})
	if not actor_states.is_empty():
		character.restore_state(actor_states.player)
		npc.restore_state(actor_states.npc)
	else:
		# New Site / explicit format-1 migration creates fresh test people.
		# Do not leak the previous map's body state into missing snapshots.
		for actor: TerrainTestCharacter in [character, npc]:
			actor.item_state.clear()
			actor.loot_settled = false
			actor.remains_id = ""
			actor.fatigue = 0.0
			actor.fatigue_rest = 0.0
			actor._fatigue_slowdown = 0.0
	var army_states: Array = terrain.site.get("armies", [])
	for index in range(army_states.size()):
		combat_armies[index].restore_combat_state(army_states[index], terrain, character, npc)
	if not actor_states.is_empty():
		var identities := {character.person_id: character, npc.person_id: npc}
		character.restore_links(actor_states.player, identities)
		npc.restore_links(actor_states.npc, identities)
	selected_army_target = 0
	seed_input.text = str(terrain.seed_value)
	preset_dropdown.select(terrain.preset)
	site_controller.bind()
	parameters_label.text = "PARAMETERS\n%s\nMax height: %d | Micro: %.3f" % [terrain.parameters["composition"], terrain.parameters["max_height"], terrain.parameters["micro_strength"]]
	status.text = "Ready. Click a platform to place the test character."
	fit_map()
	get_viewport().gui_release_focus()
	_update_info()
	_update_army_controls()

func _next_army_identity() -> int:
	var next_team := int(terrain.site.get("army_next_team", 1))
	for team: TerrainArmy in combat_armies:
		if team.has_army():
			next_team = maxi(next_team, team.team_id + 1)
	for identity: String in terrain.site.get("team_supply", {}):
		next_team = maxi(next_team, int(identity) + 1)
	return next_team

func _allocate_army_person_ids(count: int) -> Array[int]:
	# A Site-scoped monotonic sequence also includes past owners whose ground
	# items remain after a test team is cleared. Never derive new IDs from slots.
	var next_person := int(terrain.site.get("next_person_id", 1))
	for actor: TerrainTestCharacter in combat_actors:
		next_person = maxi(next_person, actor.person_id + 1)
	for team: TerrainArmy in combat_armies:
		for unit: Dictionary in team.combat_units:
			next_person = maxi(next_person, int(unit.person_id) + 1)
	for record: Dictionary in terrain.site.get("item_records", {}).values():
		next_person = maxi(next_person, int(record.original_owner) + 1)
	for container: Dictionary in terrain.site.get("ground_loot", {}).values():
		next_person = maxi(next_person, int(container.original_owner) + 1)
	for relation: Dictionary in terrain.site.get("captivity", {}).values():
		next_person = maxi(next_person, maxi(int(relation.captor_id), int(relation.guard_id)) + 1)
	if next_person <= TerrainArmy.PLAYER_MEMBER and next_person + count >= TerrainArmy.PLAYER_MEMBER:
		next_person = TerrainArmy.PLAYER_MEMBER + 1
	var result: Array[int] = []
	if count < 0 or next_person + count > 2147483647:
		return result
	for offset in range(count):
		result.append(next_person + offset)
	terrain.site["next_person_id"] = next_person + count
	return result

func deploy_army() -> void:
	if army == null or terrain == null or army.has_army():
		return
	var next_team := _next_army_identity()
	if next_team >= 999999:
		status.text = "軍隊身分序號已用盡；未生成新人物。"
		return
	army.team_id = next_team
	var deployed := army.deploy(terrain, character, npc)
	if deployed:
		terrain.site["army_next_team"] = next_team + 1
	status.text = army.command_status
	_update_army_controls()
	_update_info()
	if not deployed:
		return

func clear_army() -> void:
	if army == null:
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
	army.clear()
	if opposing_army != null:
		opposing_army.clear()
	if terrain != null and not terrain.site.is_empty():
		terrain.site["army_trial_active"] = false
		terrain.site["armies"] = []
	status.text = "Army cleared."
	_update_army_controls()
	_update_info()

func issue_army_command(command_id: int) -> bool:
	if army == null:
		return false
	var accepted := army.issue_command(command_id)
	status.text = army.command_status
	_update_army_controls()
	_update_info()
	return accepted

func _exit_tree() -> void:
	TerrainArmy.release_contact_source()

func _update_army_controls() -> void:
	var active := army != null and army.has_army()
	if deploy_army_button != null:
		deploy_army_button.disabled = active
	if follow_army_button != null:
		follow_army_button.disabled = not active
	if edge_army_button != null:
		edge_army_button.disabled = not active
	if clear_army_button != null:
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
	var left := 500.0 if get_node("TerrainLabUI").visible else 0.0
	var right := Site.PANEL_SPACE if site_controller != null else 0.0
	var fit: float = minf((viewport_size.x - left - right) / extent.x, (viewport_size.y - 80.0) / extent.y)
	camera.zoom = Vector2.ONE * maxf(0.1, fit)
	camera.position = extent * 0.5 - Vector2((left - right) * 0.5 / camera.zoom.x, 0)
	camera.force_update_scroll()

func issue_npc_command(command_id: int = -1, requested_target: Vector2i = Vector2i(-1, -1)) -> bool:
	if npc == null or terrain == null:
		return false
	if site_controller != null:
		site_controller.release_worker()
	var selected_command := npc_command_dropdown.selected if command_id < 0 and npc_command_dropdown != null else command_id
	var target := requested_target
	if selected_command == TerrainTestNPC.Command.MOVE_TO_CELL and target == Vector2i(-1, -1):
		_npc_target_pending = true
		status.text = "Click map to choose NPC destination."
		get_viewport().gui_release_focus()
		return true
	_npc_target_pending = false
	if target == Vector2i(-1, -1):
		target = renderer.pick_cell(get_viewport().get_mouse_position())
	var accepted := npc.issue_command(selected_command, target, character)
	status.text = "NPC: %s" % npc.command_status
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
	_move_cooldown = 0.0
	_run_held = false

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
	var person := controlled_target()
	var target := _combat_target(target_id)
	if person.is_empty() or target.is_empty() or target_id == controlled_person_id():
		return false
	if int(person.unit) >= 0:
		return person.owner.start_unit_attack(int(person.unit), target.cell, target_id)
	return person.owner.start_attack_unit(target.owner, int(target.unit)) if int(target.unit) >= 0 else person.owner.start_attack(target.owner)

func controlled_guard(enabled: bool) -> void:
	var person := controlled_target()
	if person.is_empty():
		return
	if int(person.unit) >= 0:
		person.owner.set_unit_guard(int(person.unit), enabled)
	else:
		person.owner.set_guard(enabled)

func controlled_exchange_skill(skill: String) -> bool:
	if not exchange_enabled or get_tree().paused:
		return false
	var person := controlled_target()
	if person.is_empty():
		return false
	var accepted: bool = person.owner.activate_exchange_skill(int(person.unit), skill) if int(person.unit) >= 0 else person.owner.activate_exchange_skill(skill)
	status.text = ("穩守：下次交鋒能力 +15，抵抗擊退" if skill == "brace" else "強攻：下次交鋒能力 +15，勝出多加 10 暈眩") if accepted else "技能尚未冷卻或人物無法行動"
	return accepted

func _report_move(moved: bool) -> void:
	if moved:
		var person := controlled_target()
		var i: int = terrain.index(person.cell)
		status.text = "Moved to %s, height %d" % [person.cell, terrain.height_levels[i]]
	else:
		status.text = "Blocked: water, cliff edge or map boundary. Use a marked ramp."

func _try_move(direction: Vector2i) -> void:
	var running := _run_held
	var person := controlled_target()
	if person.is_empty():
		return
	if int(person.unit) >= 0:
		_report_move(person.owner._reserve_combat_step(int(person.unit), Vector2i(person.cell) + direction, 0, running))
		_move_cooldown = TerrainArmy.RUN_DURATION if running else TerrainArmy.MOVE_DURATION
	else:
		_report_move(person.owner.step(direction, running))
		_move_cooldown = person.owner.get_move_interval(running)

func _unhandled_input(event: InputEvent) -> void:
	if (character.editor_window != null and character.editor_window.visible) or (npc.editor_window != null and npc.editor_window.visible):
		_clear_movement_input()
		return
	if site_controller != null and site_controller.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused and event is InputEventKey:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mouse.pressed
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(mouse.position, ZOOM_STEP)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(mouse.position, 1.0 / ZOOM_STEP)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and movement_toggle.button_pressed:
			if get_tree().paused:
				return
			get_viewport().gui_release_focus()
			var cell := renderer.pick_cell(mouse.position)
			if _npc_target_pending:
				issue_npc_command(TerrainTestNPC.Command.MOVE_TO_CELL, cell)
				return
			if select_army_target(cell):
				return
			if controlled_person_id() != character.person_id or npc.occupies_cell(cell) or character.action_time > 0 or not character.can_act():
				return
			var placed: bool = character.place(renderer.pick_cell(mouse.position))
			status.text = "Placed on platform." if placed else "Cannot place on water / outside the map."
	elif event is InputEventMouseMotion and _dragging:
		camera.position -= (event as InputEventMouseMotion).relative / camera.zoom
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		var key := _event_key(key_event)
		if exchange_enabled and key in [KEY_Q, KEY_E] and key_event.pressed and not key_event.echo:
			controlled_exchange_skill("brace" if key == KEY_Q else "power")
			get_viewport().set_input_as_handled()
			return
		if key == KEY_SPACE and key_event.pressed and not key_event.echo and movement_toggle.button_pressed:
			if selected_army_target > 0:
				attack_selected_soldier()
			else:
				controlled_attack(npc.person_id if controlled_person_id() != npc.person_id else character.person_id)
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
			if key_event.pressed and not key_event.echo and movement_toggle.button_pressed:
				_held_directions[key] = direction
				_last_direction_key = key
				if _move_cooldown <= 0.0:
					_try_move(direction)
			elif not key_event.pressed:
				_held_directions.erase(key)
				if _held_directions.is_empty():
					_move_cooldown = 0.0
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F and key_event.pressed and not key_event.echo and movement_toggle.button_pressed:
			var person := controlled_target()
			var mounted: bool = not person.is_empty() and int(person.unit) < 0 and person.owner.toggle_mount()
			status.text = "Mounted horse. Ride with WASD + Shift." if mounted else "Dismounted."
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_fatigue_work_seconds.clear()
	if get_tree().paused:
		if site_controller != null:
			site_controller.tick(delta)
		return
	_advance_action_time(delta)
	if get_tree().paused:
		return
	if site_controller != null:
		site_controller.finish_tick()
	if npc.person_id != controlled_person_id() and npc_retaliates and movement_toggle != null and movement_toggle.button_pressed and npc.can_act() and character.can_act() and npc.faction_id != character.faction_id:
		var offset := character.terrain_cell - npc.terrain_cell
		if absi(offset.x) + absi(offset.y) == 1 and terrain.can_step(npc.terrain_cell, character.terrain_cell):
			npc.start_attack(character)
	if movement_toggle != null and movement_toggle.button_pressed:
		_move_cooldown = maxf(0.0, _move_cooldown - delta)
		var held_direction := _held_direction()
		if held_direction != Vector2i.ZERO and _move_cooldown <= 0.0:
			_try_move(held_direction)
	else:
		_clear_movement_input()
	_info_time += delta
	if _info_time >= 0.1:
		_info_time = 0.0
		_update_info()

func _advance_action_time(delta: float) -> void:
	# Site work/time and original bodies still share the same 120 Hz step. A
	# hit can change the next step's clock, even inside one slow render frame.
	# Fixed mode carries the sub-step fraction into the next frame instead of
	# introducing a different tiny action step at every render-frame boundary.
	if (is_inside_tree() and get_tree().paused) or (terrain != null and bool(terrain.site.get("paused", false))):
		return
	var remaining := maxf(0.0, delta)
	if exchange_enabled:
		# One retained common clock, now 30 Hz; rendering is still every frame.
		# No debt clamp, hidden time scale or per-person simulation replacement.
		_action_time_remainder += remaining
		while _action_time_remainder + ACTION_TIME_EPSILON >= EXCHANGE_ACTION_STEP:
			_action_time_remainder -= EXCHANGE_ACTION_STEP
			var previous_clock := float(terrain.site.get("combat_left", 0.0)) if terrain != null else 0.0
			if site_controller != null:
				site_controller.tick(EXCHANGE_ACTION_STEP)
			if is_inside_tree() and get_tree().paused:
				return
			_advance_combat(EXCHANGE_ACTION_STEP, previous_clock)
			_fatigue_work_seconds.clear()
			if is_inside_tree() and get_tree().paused:
				return
		return
	if fixed_action_steps_enabled:
		_action_time_remainder += remaining
		remaining = _action_time_remainder
	while (fixed_action_steps_enabled and remaining + ACTION_TIME_EPSILON >= ACTION_STEP) or (not fixed_action_steps_enabled and remaining > 0.0):
		var elapsed := ACTION_STEP if fixed_action_steps_enabled else minf(remaining, ACTION_STEP)
		remaining -= elapsed
		if fixed_action_steps_enabled:
			# A boundary rounding error may leave a tiny negative phase. Retain it
			# too, so the next frame repays it; never silently clamp elapsed time.
			_action_time_remainder = remaining
		var combat_clock := float(terrain.site.get("combat_left", 0.0)) if terrain != null else 0.0
		if site_controller != null:
			site_controller.tick(elapsed)
		if is_inside_tree() and get_tree().paused:
			return
		_advance_combat(elapsed, combat_clock)
		_fatigue_work_seconds.clear()
		if is_inside_tree() and get_tree().paused:
			return

func _advance_combat(delta: float, combat_clock: float = -1.0) -> void:
	# Shared action-time steps, independent of peaceful game-minute acceleration.
	# All actors generate a sample before contact resolution, allowing real trades.
	if delta <= 0.0 or (is_inside_tree() and get_tree().paused):
		return
	if terrain != null and bool(terrain.site.get("paused", false)):
		return
	if combat_clock < 0.0:
		combat_clock = float(terrain.site.get("combat_left", 0.0)) if terrain != null else 0.0
	var remaining := delta
	while remaining > 0.0:
		var elapsed := minf(remaining, EXCHANGE_ACTION_STEP if exchange_enabled else ACTION_STEP)
		remaining -= elapsed
		_advance_fatigue(SiteRuntime.game_seconds(elapsed, combat_clock))
		var stage_started := Time.get_ticks_usec() if combat_profile_enabled else 0
		combat_clock = maxf(0.0, combat_clock - elapsed)
		_combat_contacts.clear()
		if not exchange_enabled:
			TerrainArmy.begin_contact_step()
		for actor: TerrainTestCharacter in combat_actors:
			if actor is TerrainTestNPC and actor.combat_driven_by_lab and actor.person_id != controlled_person_id():
				(actor as TerrainTestNPC).advance_navigation()
		for team: TerrainArmy in combat_armies:
			team.prepare_combat(elapsed)
		stage_started = _combat_profile_stage("navigation_and_team_prepare", stage_started)
		for actor: TerrainTestCharacter in combat_actors:
			if is_instance_valid(actor):
				actor.advance_combat(elapsed, true)
		stage_started = _combat_profile_stage("actors_advance", stage_started)
		# All live actors have advanced. Their poses stay fixed until this batch
		# is collected; discard projections before contacts can change a pose.
		if exchange_enabled:
			_advance_ranged(elapsed) # Existing owners keep flights; only due events query cells.
			_exchange_phase += elapsed
			if _exchange_phase + ACTION_TIME_EPSILON >= EXCHANGE_QUERY_STEP:
				_exchange_phase -= EXCHANGE_QUERY_STEP
				_resolve_exchanges()
		else:
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
		stage_started = _combat_profile_stage("resolve", stage_started)
		if site_controller != null:
			site_controller.settle_person_deaths(elapsed)
			for result: Dictionary in site_controller.person_actions.settle_after_contacts():
				site_controller.show_result(result)
			site_controller.settle_supply_deliveries()
		for team: TerrainArmy in combat_armies:
			team.settle_combat_command()
		if site_controller != null:
			site_controller.check_family_death()
			if get_tree().paused:
				return
		_combat_profile_stage("settle_life_orders_family", stage_started)
	_combat_contacts.clear()

func fatigue_work_minutes(manual: bool, minutes: float) -> float:
	var actor: TerrainTestCharacter = character if manual else npc
	var autonomous := actor.person_id != controlled_person_id()
	var seconds := minutes * 60.0
	if autonomous:
		actor.work_resting = PersonFatigue.needs_work_rest(actor.fatigue, actor.work_resting)
		if actor.work_resting:
			return 0.0
		# Commit only the effort before 80; unfinished progress/cargo stays put.
		seconds = minf(seconds, maxf(0.0, PersonFatigue.WORK_REST_AT - actor.fatigue) / PersonFatigue.WORK_RATE)
	var productive := PersonFatigue.work_seconds(actor.fatigue, seconds)
	var state := PersonFatigue.advance(actor.fatigue, actor.fatigue_rest, seconds, PersonFatigue.WORK_RATE, false)
	actor.fatigue = state[0]
	actor.fatigue_rest = state[1]
	if autonomous and actor.fatigue >= PersonFatigue.WORK_REST_AT - 0.000000001:
		actor.fatigue = PersonFatigue.WORK_REST_AT
		actor.work_resting = true
	_fatigue_work_seconds[actor] = float(_fatigue_work_seconds.get(actor, 0.0)) + seconds
	return productive / 60.0

func _advance_fatigue(seconds: float) -> void:
	if terrain == null or seconds <= 0.0:
		return
	var fatigue_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var training_seconds := {}
	if site_controller != null:
		training_seconds = site_controller.consume_crew_work()
		site_controller.advance_person_supply(seconds)
		for team: TerrainArmy in combat_armies:
			if team.combat_enabled:
				var handled: Dictionary = site_controller.advance_team_sustain(team, seconds).handled_seconds
				for identity: int in handled:
					training_seconds[identity] = float(training_seconds.get(identity, 0.0)) + float(handled[identity])
		var action_seconds: Dictionary = site_controller.person_actions.advance(seconds).handled_seconds
		site_controller.captive_escort.advance(seconds)
		for identity: int in action_seconds:
			training_seconds[identity] = float(training_seconds.get(identity, 0.0)) + float(action_seconds[identity])
		var guard_seconds: Dictionary = site_controller.advance_guard_work(seconds)
		for identity: int in guard_seconds:
			training_seconds[identity] = float(training_seconds.get(identity, 0.0)) + float(guard_seconds[identity])
	fatigue_started = _combat_profile_stage("fatigue_providers", fatigue_started)
	# Only this synchronous step shares the read-only threat candidates.
	var enemies := {}
	for actor: TerrainTestCharacter in combat_actors:
		if not is_instance_valid(actor):
			continue
		var worked := minf(seconds, float(_fatigue_work_seconds.get(actor, 0.0)))
		_fatigue_work_seconds[actor] = maxf(0.0, float(_fatigue_work_seconds.get(actor, 0.0)) - worked)
		var available := maxf(0.0, seconds - worked - float(training_seconds.get(actor.person_id, 0.0)))
		if available <= 0.0:
			continue
		var moving := actor.is_moving()
		var can_act := actor.can_act()
		var rate := 0.0
		if can_act:
			if not exchange_enabled and actor.action_time > 0.0 and actor._strike_at >= 0.0:
				rate = PersonFatigue.ATTACK_RATE
			elif not exchange_enabled and (actor.guarding or actor.guard_transition_left > 0.0):
				rate = PersonFatigue.GUARD_RATE
			elif moving and actor.combat_ready and actor._movement_duration <= TerrainTestCharacter.RUN_DURATION + 0.000001:
				rate = PersonFatigue.RUN_RATE
		var idle := can_act and not moving and actor.action_time <= 0.0 and not actor.guarding and actor.guard_transition_left <= 0.0 and actor.guard_break_left <= 0.0 and actor._rescue_left <= 0.0
		if actor == npc and (bool(terrain.site.get("worker_enabled", false)) or bool(terrain.site.worker.get("manual_control", false))) and not actor.work_resting and not str(terrain.site.get("worker", {}).get("target", "")).is_empty():
			idle = false # Assigned travel/work/input waits do not double as a rest break.
		var safe := false
		if idle and actor.fatigue > 0.0:
			var threat_started := Time.get_ticks_usec() if combat_profile_enabled else 0
			safe = not _fatigue_threat(actor.terrain_cell, actor.faction_id, actor, -1, enemies)
			_combat_profile_stage("fatigue_threat", threat_started)
		var state := PersonFatigue.advance(actor.fatigue, actor.fatigue_rest, available, rate, safe)
		actor.fatigue = state[0]
		actor.fatigue_rest = state[1]
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled:
			continue
		for index in range(team.combat_units.size()):
			var unit: Dictionary = team.combat_units[index]
			var available := maxf(0.0, seconds - float(training_seconds.get(team.combat_identity(index), 0.0)))
			if available <= 0.0:
				continue
			var moving := team.moving_to[index] != TerrainArmy.INVALID_CELL
			var can_act := team.combat_can_act(index)
			var rate := 0.0
			if can_act:
				if not exchange_enabled and bool(unit.attack):
					rate = PersonFatigue.ATTACK_RATE
				elif not exchange_enabled and str(unit.pose) in ["guard", "guard_raise", "guard_lower"]:
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
			var idle := can_act and not moving and str(unit.pose) == "idle"
			if not unit.get("work_task", {}).is_empty() and str(unit.work_task.get("mode", "")) != "rest":
				idle = false # Pending work/input/path waits are not a rest break.
			var safe := false
			if idle and float(unit.fatigue) > 0.0:
				var threat_started := Time.get_ticks_usec() if combat_profile_enabled else 0
				safe = not _fatigue_threat(team.cells[index], team.faction_id, team, index, enemies)
				_combat_profile_stage("fatigue_threat", threat_started)
			var state := PersonFatigue.advance(float(unit.fatigue), float(unit.fatigue_rest), available, rate, safe)
			unit.fatigue = state[0]
			unit.fatigue_rest = state[1]
	# Inclusive of fatigue_threat; do not add that nested counter a second time.
	_combat_profile_stage("fatigue_people_inclusive", fatigue_started)

func _fatigue_threat(cell: Vector2i, faction: int, rest_owner: Variant, unit_index: int, candidates: Dictionary) -> bool:
	if not terrain.is_walkable(cell):
		return true
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
				if team.combat_can_act(index):
					cells[team.cells[index]] = true
					if team.moving_to[index] != TerrainArmy.INVALID_CELL:
						cells[team.moving_to[index]] = true
		candidates[faction] = {"cells": cells}
	var threat: Dictionary = candidates[faction]
	if exchange_enabled:
		if not candidates.has("flight_cells"):
			var flight_cells := {}
			for source: Node2D in _ranged_owners():
				for flight: Dictionary in source.projectiles:
					if str(flight.get("mode", "")) == "cell":
						for crossed: Vector2i in SiteCombatRules.ranged_cells(flight.source_cell, flight.target_cell):
							flight_cells[crossed] = true
			candidates["flight_cells"] = flight_cells
		if candidates.flight_cells.has(cell):
			return true # Incoming arrows, including friendly ones, prevent safe rest.
		# New rest rule: an awake enemy within eight cardinal cells prevents
		# rest even behind cover. No geometry or repeated reachability search.
		for enemy: Vector2i in threat.cells:
			var distance := enemy - cell
			if absi(distance.x) + absi(distance.y) <= 8:
				return true
		return false
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

func _exchange_people() -> Array[Dictionary]:
	# Disposable references to original owners, never a second roster or HP store.
	var people: Array[Dictionary] = []
	for actor: TerrainTestCharacter in combat_actors:
		if is_instance_valid(actor) and actor.can_act():
			people.append({"owner": actor, "unit": -1, "id": actor.person_id,
				"cell": actor.terrain_cell, "faction": actor.faction_id, "ready": actor.exchange_ready(), "receive": actor.exchange_can_receive()})
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled:
			continue
		for index in range(team.combat_units.size()):
			if team.combat_can_act(index):
				people.append({"owner": team, "unit": index, "id": team.combat_identity(index),
					"cell": team.cells[index], "faction": team.faction_id, "ready": team.exchange_ready(index), "receive": team.exchange_can_receive(index)})
	return people

func _exchange_initiates(person: Dictionary, other_id: int) -> bool:
	if int(person.unit) >= 0:
		var team: TerrainArmy = person.owner
		return team.combat_attacking or int(team.combat_units[int(person.unit)].target) == other_id
	var actor: TerrainTestCharacter = person.owner
	return actor.attack_target_id == other_id or (npc_retaliates and actor == npc)

func _exchange_context(person: Dictionary, occupied: Dictionary) -> Dictionary:
	var sectors := 0
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var next: Vector2i = person.cell + direction
		if not terrain.can_attack_across(person.cell, next):
			continue
		for other: Dictionary in occupied.get(next, []):
			if int(other.faction) != int(person.faction):
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

func _resolve_exchanges() -> void:
	if terrain == null:
		return
	_exchange_round += 1
	var people := _exchange_people()
	if people.is_empty():
		return
	var occupied := {}
	for person: Dictionary in people:
		if not occupied.has(person.cell):
			occupied[person.cell] = []
		occupied[person.cell].append(person)
	var used := {}
	var pending: Array[Dictionary] = []
	# Rotate priority to avoid a permanent low-ID advantage in a crowded line.
	for offset in range(people.size()):
		var a: Dictionary = people[(offset + _exchange_round) % people.size()]
		if not bool(a.receive) or used.has(a.id):
			continue
		var matched := false
		for direction_offset in range(4):
			var next: Vector2i = a.cell + TerrainData.DIRECTIONS[(direction_offset + _exchange_round) % 4]
			if not terrain.can_attack_across(a.cell, next):
				continue
			for b: Dictionary in occupied.get(next, []):
				if not bool(b.receive) or used.has(b.id) or int(a.faction) == int(b.faction):
					continue
				if not (bool(a.ready) and _exchange_initiates(a, int(b.id))) and not (bool(b.ready) and _exchange_initiates(b, int(a.id))):
					continue # Peaceful worker/player neighbours do not spontaneously duel.
				var stats_a := _exchange_context(a, occupied)
				var stats_b := _exchange_context(b, occupied)
				var low := mini(int(a.id), int(b.id))
				var high := maxi(int(a.id), int(b.id))
				var noise := (low * 73856093) ^ (high * 19349663) ^ (_exchange_round * 83492791) ^ terrain.seed_value
				var roll := float(posmod(noise, 21) - 10) * (1.0 if int(a.id) == low else -1.0)
				pending.append({"a": a, "b": b, "stats_a": stats_a, "stats_b": stats_b,
					"result": SiteCombatRules.exchange_result(stats_a, stats_b, roll)})
				used[a.id] = true
				used[b.id] = true
				matched = true
				break
			if matched:
				break
	# Every pairing sees pre-resolution abilities/positions; each original
	# person participates once. Knockback still commits through original owners.
	for pair: Dictionary in pending:
		_apply_exchange_side(pair.a, pair.b, pair.result, pair.stats_a, 1)
		_apply_exchange_side(pair.b, pair.a, pair.result, pair.stats_b, -1)
		exchange_count += 1
		exchange_results[str(pair.result.kind)] += 1
		exchange_resolved.emit(int(pair.a.id), int(pair.b.id), pair.result)
	_resolve_ranged_fire(people)

func _ranged_owners() -> Array[Node2D]:
	var owners: Array[Node2D] = []
	for actor: TerrainTestCharacter in combat_actors:
		if is_instance_valid(actor):
			owners.append(actor)
	for team: TerrainArmy in combat_armies:
		if is_instance_valid(team):
			owners.append(team)
	return owners

func has_ranged_projectiles() -> bool:
	if not exchange_enabled:
		return false # Historical exact mode keeps its original save/action guards.
	for projectile_owner: Node2D in _ranged_owners():
		if not projectile_owner.projectiles.is_empty():
			return true
	return false

func _resolve_ranged_fire(people: Array[Dictionary]) -> void:
	for person: Dictionary in people:
		var shooter_owner: Variant = person.owner
		var index := int(person.unit)
		# Pair resolution may have consumed readiness since this disposable list was built.
		if not (shooter_owner.exchange_ready(index) if index >= 0 else shooter_owner.exchange_ready()):
			continue
		if (float(shooter_owner.combat_units[index].get("ranged_cooldown", 0.0)) if index >= 0 else shooter_owner.ranged_cooldown) > 0.0:
			continue
		if index >= 0 and shooter_owner.is_member(index) and not shooter_owner.is_controlled_person(index) and shooter_owner.is_sustain_routed():
			continue # A rout does not become a new automatic ranged attack order.
		var profile: Dictionary = shooter_owner.ranged_profile(index) if index >= 0 else shooter_owner.ranged_profile()
		if profile.is_empty():
			continue
		var ammunition: Dictionary = shooter_owner.combat_units[index].get("cargo", {}) if index >= 0 else shooter_owner.ammo_inventory
		if int(ammunition.get(str(profile.ammo), 0)) < 1:
			continue # Empty quivers neither scan all targets nor reserve an automatic skill.
		var selected := {}
		var nearest := INF
		var close_threat := false
		for other: Dictionary in people:
			if int(person.faction) == int(other.faction):
				continue
			if not (other.owner.combat_can_act(int(other.unit)) if int(other.unit) >= 0 else other.owner.can_act()):
				continue # A melee result in this same decision tick may have incapacitated them.
			var separation: Vector2i = other.cell - person.cell
			if absi(separation.x) + absi(separation.y) <= 1 and terrain.can_attack_across(person.cell, other.cell):
				close_threat = true
				break # A nearby opponent forces close combat even while that opponent cools down.
			if not _exchange_initiates(person, int(other.id)):
				continue
			var distance := Vector2(separation).length_squared()
			if distance <= 1.0 or distance > float(profile.range) * float(profile.range) or distance >= nearest:
				continue
			if SiteCombatRules.ranged_line_clear(terrain, person.cell, other.cell):
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

func _ranged_occupants() -> Dictionary:
	# Arrival-only snapshot: living and unconscious original bodies, never skeletons.
	# While a legal step is in progress, the nearest rendered ground cell is occupied.
	var occupied := {}
	for occupant_owner: Node2D in _ranged_owners():
		var count: int = occupant_owner.combat_units.size() if occupant_owner is TerrainArmy else 1
		for index in range(count):
			var hp: float = float(occupant_owner.combat_units[index].hp) if occupant_owner is TerrainArmy else occupant_owner.hp
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
	var result := {"kind": "empty", "hp": 0.0, "stun": 0.0, "stagger": 0.0, "knockback": false, "guard_break": false}
	var target := {}
	var passed := {flight.source_cell: true}
	var offset: Vector2i = flight.target_cell - flight.source_cell
	var incoming: Array[Vector2i] = [Vector2i(-signi(offset.x), 0), Vector2i(0, -signi(offset.y))]
	# Single arrival-time supercover query. The first body intercepts, even an ally;
	# a missed/intercepted arrow never continues through a line of people.
	for cell: Vector2i in SiteCombatRules.ranged_cells(flight.source_cell, flight.target_cell):
		# Check the original ray's crossed edges. Re-aiming at each intermediate
		# cell would describe a different ray and invent off-path obstructions.
		for direction: Vector2i in incoming:
			var previous := cell + direction
			if direction != Vector2i.ZERO and passed.has(previous) and not terrain.can_attack_across(previous, cell):
				result.kind = "blocked"
		if str(result.kind) == "blocked":
			break
		passed[cell] = true
		for person: Dictionary in occupied.get(cell, []):
			if int(person.id) != int(flight.shooter_id):
				target = person
				break
		if not target.is_empty():
			break
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

func _apply_exchange_side(person: Dictionary, other: Dictionary, result: Dictionary, stats: Dictionary, side: int) -> void:
	var role := "draw" if int(result.winner) == 0 else "winner" if int(result.winner) == side else "loser"
	var stagger := float(result.hold) if role == "draw" else float(result.stagger) if role == "loser" else 0.0
	if role == "loser" and str(result.kind) == "big" and float(stats.facility) > 0.0:
		stagger = maxf(0.0, stagger - 0.15)
	var outcome := {"role": role, "kind": str(result.kind), "hp": float(result.hp) if role == "loser" else 0.0,
		"stun": float(result.stun) if role == "loser" else 0.0, "stagger": stagger,
		"knockback": role == "loser" and bool(result.knockback), "skill": str(stats.get("skill", "")),
		"fatigue": float(result.fatigue_a if side == 1 else result.fatigue_b),
		"other_identity": int(other.id), "attacker": other.owner, "attacker_unit": int(other.unit)}
	if int(person.unit) >= 0:
		person.owner.apply_exchange(int(person.unit), other.cell, outcome)
	else:
		person.owner.apply_exchange(other.cell, outcome)

func _resolve_combat_contacts() -> void:
	_combat_contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.fraction) < float(b.fraction))
	var cursor := 0
	while cursor < _combat_contacts.size():
		var group_end := cursor + 1
		while group_end < _combat_contacts.size() and is_equal_approx(float(_combat_contacts[group_end].fraction), float(_combat_contacts[cursor].fraction)):
			group_end += 1
		var eligible := {}
		for index in range(cursor, group_end):
			var packet: Dictionary = _combat_contacts[index]
			var attacker: Variant = packet.attacker
			if is_instance_valid(attacker):
				var unit := int(packet.get("attacker_unit", -1))
				var identity := "%d:%d" % [attacker.get_instance_id(), unit]
				eligible[identity] = attacker.combat_can_act(unit) if attacker is TerrainArmy else attacker.can_act()
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

func issue_player_army_order(order_id: int, goal: Vector2i = Vector2i(-1, -1), target_id: int = -1) -> Dictionary:
	var team := player_army()
	if team == null:
		return SiteRuntime.fail("NO_AUTHORITY", "尚未加入隊伍")
	return team.issue_combat_order(controlled_member_index(team), order_id, goal, target_id)

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
		if team != source:
			recipient = team
	if recipient == null:
		return SiteRuntime.fail("NO_SPACE", "首版保留兩隊保存上限；沒有空隊伍槽，不會清除另一隊")
	if recipient.has_army():
		if receiver_confirmation.is_empty():
			return SiteRuntime.fail("NO_AUTHORITY", "既有接收隊還須由現任合格指揮者確認；玩家不代獲對方指揮權")
		var member_ids: Array[int] = []
		for index: int in source.command_members():
			member_ids.append(source.combat_identity(index))
		if int(receiver_confirmation.get("team_id", -1)) != recipient.team_id or int(receiver_confirmation.get("commander_id", -1)) != recipient.combat_identity(recipient.current_commander) or int(receiver_confirmation.get("source_team_id", -1)) != source.team_id or int(receiver_confirmation.get("source_commander_id", -1)) != controlled_person_id() or receiver_confirmation.get("member_ids", []) != member_ids or not merge_all and receiver_confirmation.get("selected_ids", []) != identities:
			return SiteRuntime.fail("STALE", "原接收指揮者或本次名冊已變更，須重新確認")
		if merge_all:
			return source.merge_into(recipient, controlled_member_index(source), recipient.current_commander)
		return source.transfer_members_to(recipient, identities, controlled_member_index(source), recipient.current_commander)
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
	else:
		recipient.team_id = previous_team
		recipient.faction_id = previous_faction
	return result

func start_melee_trial() -> Dictionary:
	if army.has_army() or opposing_army.has_army():
		return SiteRuntime.fail("BUSY", "請先清除現有測試隊伍；不會搬動既有人物")
	# Only deploy on existing legal ground. Never flatten terrain or delete props.
	var origin := Vector2i(-1, -1)
	for y in range(1, terrain.size.y - 10):
		for x in range(1, terrain.size.x - 20):
			var legal := true
			for row in range(10):
				for column in range(20):
					var cell := Vector2i(x + column, y + row)
					if not terrain.is_walkable(cell) or character.occupies_cell(cell) or npc.occupies_cell(cell) \
						or (column > 0 and not terrain.can_step(cell, cell + Vector2i.LEFT)) \
						or (row > 0 and not terrain.can_step(cell, cell + Vector2i.UP)):
						legal = false
						break
				if not legal:
					break
			if legal:
				origin = Vector2i(x, y)
				break
		if origin.x >= 0:
			break
	if origin.x < 0:
		return SiteRuntime.fail("NO_SPACE", "找不到兩隊所需的連通 20×10 空地；未修改地形")
	if not TerrainArmy.load_combat_bake():
		return SiteRuntime.fail("MISSING_ASSET", "交戰圖集／碰撞資料不可用，未部署")
	var next_team := _next_army_identity()
	if next_team > 999997:
		return SiteRuntime.fail("ID_EXHAUSTED", "軍隊身分序號已用盡")
	army.team_id = next_team
	opposing_army.team_id = next_team + 1
	army.faction_id = 0
	opposing_army.faction_id = 1
	for team: TerrainArmy in combat_armies:
		var selected: Array[Vector2i] = []
		for depth in range(10):
			for row in range(10):
				selected.append(origin + Vector2i(9 - depth if team == army else 10 + depth, row))
		if not team.deploy_at(terrain, character, npc, selected) or not team.enable_combat():
			clear_army()
			return SiteRuntime.fail("DEPLOY_FAILED", "測試部署失敗；已撤銷本次新隊伍")
		for index in range(TerrainArmy.SOLDIER_COUNT):
			team.facing[index] = Vector2i.RIGHT if team == army else Vector2i.LEFT
		team._visual_dirty = true
	terrain.site["army_trial_active"] = true
	terrain.site["army_next_team"] = next_team + 2
	camera.position = (Vector2(origin) + Vector2(10, 5)) * TerrainRenderer.CELL_PIXELS
	camera.zoom = Vector2.ONE * 0.9
	return SiteRuntime.ok("兩隊近戰測試已部署；玩家仍自行操作。脫戰後保存包含兩隊傷亡與指揮狀態。")

func _nearest_unit_enemy(source: TerrainArmy, index: int) -> Dictionary:
	var best := {}
	var best_distance := 3
	var retained := int(source.combat_units[index].target)
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled or team.faction_id == source.faction_id:
			continue
		for target_index in range(team.combat_units.size()):
			var offset := team.cells[target_index] - source.cells[index]
			var distance := absi(offset.x) + absi(offset.y)
			if distance > 2 or not team.combat_can_act(target_index) or not SiteCombatRules.terrain_line_clear(terrain, source.cells[index], team.cells[target_index]):
				continue
			var identity := team.combat_identity(target_index)
			var threat := bool(team.combat_units[target_index].attack) and int(team.combat_units[target_index].target) == source.combat_identity(index)
			var candidate := {"cell": team.cells[target_index], "identity": identity, "threat": threat}
			if identity == retained:
				return candidate
			if not best.is_empty() and (bool(best.threat) and not threat or bool(best.threat) == threat and (distance > best_distance or distance == best_distance and identity > int(best.identity))):
				continue
			best_distance = distance
			best = candidate
	for actor: TerrainTestCharacter in combat_actors:
		if actor.faction_id == source.faction_id or not actor.can_act():
			continue
		var offset := actor.terrain_cell - source.cells[index]
		var distance := absi(offset.x) + absi(offset.y)
		if distance > 2 or not SiteCombatRules.terrain_line_clear(terrain, source.cells[index], actor.terrain_cell):
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
	for actor: TerrainTestCharacter in combat_actors:
		if actor.combat_identity() == identity and actor.faction_id != source.faction_id and actor.can_act():
			return {"cell": actor.terrain_cell, "identity": identity}
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled or team.faction_id == source.faction_id:
			continue
		var index := team.index_for_identity(identity)
		if team.combat_can_act(index):
			return {"cell": team.cells[index], "identity": identity}
	return {}

func _combat_target(identity: int, with_bodies: bool = false) -> Dictionary:
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
			return {"owner": team, "unit": index, "position": team.combat_ground(index), "cell": team.cells[index],
				"hp": float(team.combat_units[index].hp), "bodies": team.combat_shapes(index, "body") if with_bodies else []}
	return {}

func select_army_target(cell: Vector2i) -> bool:
	var controlled := controlled_target()
	var faction: int = controlled.owner.faction_id if not controlled.is_empty() else character.faction_id
	for team: TerrainArmy in combat_armies:
		for index in range(team.combat_units.size()):
			if team.cells[index] == cell and not team.member_gone(index):
				selected_army_target = team.combat_identity(index)
				selected_army_label.text = "選中人物 #%d（%s）" % [selected_army_target, "友軍" if team.faction_id == faction else "敵軍"]
				return true
	return false

func attack_selected_soldier() -> bool:
	return controlled_attack(selected_army_target)

func rescue_selected_soldier() -> bool:
	var target := _combat_target(selected_army_target)
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
			if not bounds.intersects(target_bounds, true) or not SiteCombatRules.terrain_line_clear(terrain, source_cell, team.cells[index]):
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
		if not hit.is_empty() and SiteCombatRules.terrain_line_clear(terrain, source_cell, actor.terrain_cell):
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
	if terrain == null or info == null:
		return
	combat_info.text = "Player HP %.1f | stun %.1f | 疲勞 %.1f | %s\nNPC HP %.1f | stun %.1f | 疲勞 %.1f | %s" % [character.hp, character.stun, character.fatigue, character.combat_status, npc.hp, npc.stun, npc.fatigue, npc.combat_status]
	if exchange_enabled:
		combat_info.text += "\n遠程 %d 發／正中 %d／擦傷 %d\n玩家箭 %d／弩矢 %d；NPC 箭 %d／弩矢 %d" % [ranged_shots, ranged_results.hit, ranged_results.graze,
			int(character.ammo_inventory.get("arrow", 0)), int(character.ammo_inventory.get("bolt", 0)), int(npc.ammo_inventory.get("arrow", 0)), int(npc.ammo_inventory.get("bolt", 0))]
	if army_info != null and army != null:
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
	info.text = "%s\nSeed: %d\n%s\nCharacter cell: %s\nNPC cell: %s\nNPC command: %s\nZoom: %.3f | FPS: %d\nGenerate: %.2f ms" % [TerrainPreset.NAMES[terrain.preset], terrain.seed_value, details, character.terrain_cell, npc.terrain_cell, npc.command_status, camera.zoom.x, Engine.get_frames_per_second(), generation_ms]
