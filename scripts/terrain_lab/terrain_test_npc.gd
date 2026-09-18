class_name TerrainTestNPC
extends TerrainTestCharacter

enum Command { STOP, MOVE_TO_CELL, FOLLOW_PLAYER }
const COMMAND_NAMES: Array[String] = ["STOP / 停止", "MOVE / 點選目的地", "FOLLOW PLAYER / 跟隨玩家"]

var command: int = Command.STOP
var target_cell := Vector2i(-1, -1)
var command_status := "Idle / 待命"
var _follow_target: TerrainTestCharacter
var _path: Array[Vector2i] = []

func initialize_visual() -> void:
	visual_state.body_index = 1
	super.initialize_visual()
	if editor != null:
		editor._on_body_selected(1)
		editor.select_animation_by_id(&"idle")
		editor_window.title = "Terrain Lab — NPC female parts and animation"

func set_data(value: TerrainData) -> void:
	data = value
	_path.clear()
	if data == null:
		terrain_cell = Vector2i(-1, -1)
		return
	if not data.is_walkable(terrain_cell):
		place(data.spawn_cell, true)
	queue_redraw()

func issue_command(command_id: int, requested_target: Vector2i = Vector2i(-1, -1), follow_target: TerrainTestCharacter = null) -> bool:
	if data == null or not data.is_walkable(terrain_cell):
		command_status = "No valid NPC cell"
		return false
	if command_id < Command.STOP or command_id > Command.FOLLOW_PLAYER:
		command_status = "Unknown command"
		return false
	_path.clear()
	command = command_id
	_follow_target = follow_target
	if command == Command.STOP:
		target_cell = terrain_cell
		command_status = "Stopped / 已停止"
		queue_redraw()
		return true
	if command == Command.FOLLOW_PLAYER:
		if _follow_target == null or not is_instance_valid(_follow_target):
			command = Command.STOP
			command_status = "Follow rejected: player missing"
			queue_redraw()
			return false
		target_cell = _follow_target.terrain_cell
		_rebuild_path(target_cell)
		command_status = "Following player / 跟隨玩家"
		queue_redraw()
		return true
	if not data.contains(requested_target) or not data.is_walkable(requested_target):
		command = Command.STOP
		command_status = "Move rejected: target is not walkable"
		queue_redraw()
		return false
	target_cell = requested_target
	_rebuild_path(target_cell)
	if target_cell != terrain_cell and _path.is_empty():
		command = Command.STOP
		command_status = "Move rejected: no legal terrain route"
		queue_redraw()
		return false
	command_status = "Moving to %s" % target_cell
	queue_redraw()
	return true

func _process(delta: float) -> void:
	super._process(delta)
	queue_redraw()
	if combat_driven_by_lab:
		return
	advance_navigation()

func advance_navigation() -> void:
	if is_inside_tree() and get_tree().paused:
		return
	if not can_act() or action_time > 0.0 or guarding or _rescue_left > 0.0:
		return
	if data == null or not data.is_walkable(terrain_cell):
		return
	if is_moving():
		return
	if command == Command.FOLLOW_PLAYER:
		if _follow_target == null or not is_instance_valid(_follow_target):
			issue_command(Command.STOP)
			return
		var follow_cell := _follow_target.terrain_cell
		if follow_cell != target_cell:
			target_cell = follow_cell
			_rebuild_path(target_cell)
	if _path.is_empty():
		if command == Command.MOVE_TO_CELL and terrain_cell == target_cell:
			command = Command.STOP
			command_status = "Arrived at %s" % terrain_cell
			queue_redraw()
			return
		if command not in [Command.MOVE_TO_CELL, Command.FOLLOW_PLAYER]: return
		_rebuild_path(target_cell)
		if _path.is_empty():
			command_status = "Blocked / 等待前往 %s 的合法路徑" % target_cell
			return # Keep the original order; an empty route is not an arrival.
	var next_cell: Vector2i = _path[0]
	if is_instance_valid(opponent) and opponent.occupies_cell(next_cell):
		if command != Command.FOLLOW_PLAYER or next_cell != target_cell:
			_rebuild_path(target_cell)
		return
	if not data.can_step(terrain_cell, next_cell):
		_rebuild_path(target_cell)
		queue_redraw()
		return
	if step(next_cell - terrain_cell):
		_path.pop_front()
		command_status = "Following player / 跟隨玩家" if command == Command.FOLLOW_PLAYER else "Moving to %s" % target_cell
	else:
		_rebuild_path(target_cell)
	queue_redraw()

func _rebuild_path(goal: Vector2i) -> void:
	_path.clear()
	if data == null or not data.contains(goal) or not data.is_walkable(goal) or goal == terrain_cell:
		return
	# Only following's actual player goal may be occupied, not its whole route.
	# An occupied MOVE goal cannot be reached; avoid scanning the map to prove it.
	if command != Command.FOLLOW_PLAYER and not can_enter_cell(goal): return
	var blocked := func(cell: Vector2i) -> bool: return not (command == Command.FOLLOW_PLAYER and cell == goal) and not can_enter_cell(cell)
	_path = data.path_between(terrain_cell, goal, blocked)

func capture_state() -> Dictionary:
	var state := super.capture_state()
	var route: Array = []
	for cell: Vector2i in _path:
		route.append([cell.x, cell.y])
	state["navigation"] = {"command": command, "target": [target_cell.x, target_cell.y], "path": route, "status": command_status}
	return state

func restore_state(state: Dictionary) -> void:
	super.restore_state(state)
	var navigation: Dictionary = state.navigation
	command = int(navigation.command)
	target_cell = Vector2i(int(navigation.target[0]), int(navigation.target[1]))
	command_status = str(navigation.status)
	_follow_target = opponent if command == Command.FOLLOW_PLAYER else null
	_path.clear()
	for cell: Array in navigation.path:
		_path.append(Vector2i(int(cell[0]), int(cell[1])))

func _draw() -> void:
	if player_sprite != null:
		super._draw()
		draw_string(ThemeDB.fallback_font, Vector2(-16, -72), "工人", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f4dfb5"))
		return
	draw_circle(Vector2(0.0, 7.0), 15.0, Color(0.03, 0.05, 0.08, 0.55))
	draw_circle(Vector2.ZERO, 12.0, Color("c49a62"))
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 24, Color("f4dfb5"), 2.0)
	draw_circle(Vector2(3.0, -3.0), 2.5, Color("352b24"))
	draw_line(Vector2(0.0, -12.0), Vector2(0.0, -23.0), Color("f4dfb5"), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-5.0, -22.0), Vector2(5.0, -19.0), Vector2(-5.0, -16.0)]), Color("f4dfb5"))
	if target_cell != Vector2i(-1, -1) and data != null:
		var target_position := (Vector2(target_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - position
		draw_rect(Rect2(target_position - Vector2(12.0, 12.0), Vector2.ONE * 24.0), Color(0.94, 0.73, 0.35, 0.8), false, 3.0)
	for cell: Vector2i in _path:
		var path_position := (Vector2(cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - position
		draw_circle(path_position, 4.0, Color(0.94, 0.73, 0.35, 0.65))
	draw_string(ThemeDB.fallback_font, Vector2(-18.0, -29.0), "工人", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color("f4dfb5"))
