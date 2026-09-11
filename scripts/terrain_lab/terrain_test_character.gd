class_name TerrainTestCharacter
extends Node2D

signal combat_event(duration: float)
var movement_from_cell := Vector2i(-1, -1)

var data: TerrainData
var terrain_cell := Vector2i(-1, -1)
var editor: HumanCharacter3DEditor
var visual_state: CharacterVisualState = CharacterVisualState.new()
var cell_blocker: Callable
var editor_window: Window
var player_sprite: Sprite2D
var _step_time: float = 0.0
var _movement_tween: Tween
var hp: int = 100
var action_time: float = 0.0
var guarding: bool = false
var facing := Vector2i.DOWN
var opponent: TerrainTestCharacter
var _strike_at: float = -1.0
var _attack_elapsed: float = 0.0
var _attack_range: int = 1
var _attack_damage: int = 20
var combat_status := "Ready"
var combat_ready := false
var _attack_clip: StringName
var _attack_duration := 0.0
var _did_hit := false
var _previous_weapon: Array[PackedVector2Array] = []
var collision_debug := false
var _collision_shapes: Array[PackedVector2Array] = []
var _projectile_position := Vector2.ZERO
var _projectile_velocity := Vector2.ZERO
var _projectile_remaining := 0.0
var _projectile_target: TerrainTestCharacter
var _attack_step := 0.0
var _attack_offset := Vector2.ZERO
var _stance_offset := Vector2.ZERO
var _attack_aim_point := Vector2.ZERO
const COMBAT_STANCE_PIXELS := 12.0
const ATTACK_STEP_PIXELS := {
	&"walk_slash": 22.0, &"attack_jump_heavy": 22.0, &"attack_axe": 22.0,
	&"attack_hammer": 29.0, &"attack_dagger": 31.5,
	&"attack_unarmed": 26.0, &"ride_slash": 31.5,
}
const WeaponCollision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
var _geometry := WeaponCollision.new()
const MOVE_DURATION: float = 0.38
const RUN_DURATION: float = 0.18

func initialize_visual() -> void:
	if DisplayServer.get_name() == "headless":
		return
	editor_window = Window.new()
	editor_window.title = "Terrain Lab — Player parts and animation"
	editor_window.size = Vector2i(1920, 1080)
	editor_window.min_size = Vector2i(1600, 900)
	editor_window.content_scale_size = Vector2i(1920, 1080)
	editor_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	editor_window.visible = false
	add_child(editor_window)
	editor = HumanCharacter3DEditor.new()
	editor.preview_host = self
	editor.visual_state = visual_state
	editor_window.add_child(editor)
	editor.open()
	# Long descriptions in the desktop editor must wrap in the Lab window.
	for node: Node in editor.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text.length() > 45:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = 240.0
	# One assembled character feeds both the map sprite and the editor preview.
	# The viewport is born under the player so its skeleton stays in one 3D world.
	var viewport: SubViewport = editor.preview_viewport
	viewport.size = CharacterRenderContract.PREVIEW_VIEWPORT_SIZE
	viewport.transparent_bg = true
	(editor.preview_world.get_node("PreviewGround") as Node3D).hide()
	for child: Node in editor.preview_world.get_children():
		if child is WorldEnvironment:
			(child as WorldEnvironment).environment.background_mode = Environment.BG_CLEAR_COLOR
	# The editor owns its clipped TextureRect display layer. Keep this map
	# presenter attached directly to the canonical viewport texture below.
	player_sprite = Sprite2D.new()
	player_sprite.texture = viewport.get_texture()
	player_sprite.texture_filter = CharacterRenderContract.TEXTURE_FILTER
	add_child(player_sprite)
	_sync_render_projection()
	editor_window.close_requested.connect(_close_editor)
	editor.closed.connect(_close_editor)
	editor.select_animation_by_id(&"idle")

func open_editor() -> void:
	if editor_window != null:
		_set_attack_offset(Vector2.ZERO)
		action_time = 0.0
		_strike_at = -1.0
		_previous_weapon.clear()
		editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		_step_time = 0.0
		editor_window.popup_centered()
		editor.open()

func _close_editor() -> void:
	editor_window.hide()
	# Preserve the selected test clip after closing the controls.
	editor.set_playing(true)

func _sync_render_projection() -> void:
	if editor == null or player_sprite == null:
		return
	player_sprite.scale = Vector2.ONE * editor.get_map_sprite_scale()
	_set_attack_offset(_attack_offset)

func _map_anchor_offset() -> Vector2:
	if editor == null or player_sprite == null:
		return Vector2.ZERO
	return editor.get_map_ground_offset_pixels() * player_sprite.scale.x

func _process(delta: float) -> void:
	z_index = 10 + int(position.y / TerrainRenderer.CELL_PIXELS)
	if editor != null and player_sprite != null:
		var expected_scale := editor.get_map_sprite_scale()
		if not is_equal_approx(player_sprite.scale.x, expected_scale):
			_sync_render_projection()
	queue_redraw()
	_update_projectile(delta)
	if hp <= 0:
		return
	_update_combat_ready()
	if action_time > 0.0:
		action_time = maxf(0.0, action_time - delta)
		if _strike_at >= 0.0:
			_sample_attack(delta)
		if action_time == 0.0:
			_strike_at = -1.0
			_previous_weapon.clear()
			_collision_shapes.clear()
			if combat_status == "Attacking":
				combat_status = "Miss"
			play_pose(&"guard" if guarding else &"idle")
		return
	if _step_time <= 0.0 or editor == null:
		return
	_step_time -= delta
	if _step_time <= 0.0:
		play_pose(&"idle")

func _update_combat_ready() -> void:
	var distance := position.distance_to(opponent.position) / TerrainRenderer.CELL_PIXELS if is_instance_valid(opponent) and opponent.hp > 0 else INF
	var ready_now := distance <= (4.0 if combat_ready else 3.0)
	if combat_ready == ready_now:
		if ready_now and action_time <= 0.0 and not is_moving() and not guarding:
			face_target(opponent)
			_set_attack_offset(_attack_offset)
		return
	combat_ready = ready_now
	_stance_offset = Vector2.ZERO
	if editor != null:
		editor.combat_ready = ready_now
		editor.visual_state.combat_ready = ready_now
		editor._update_weapon_sheath_state()
	if action_time <= 0.0 and not is_moving():
		if ready_now:
			face_target(opponent)
		play_pose(&"idle")

func face_target(target: TerrainTestCharacter) -> void:
	var offset := target.terrain_cell - terrain_cell
	facing = Vector2i(signi(offset.x), 0) if absi(offset.x) > absi(offset.y) else Vector2i(0, signi(offset.y))
	if combat_ready:
		_stance_offset = Vector2(facing) * COMBAT_STANCE_PIXELS
	if editor != null:
		editor.set_preview_yaw_degrees({Vector2i.DOWN: 0.0, Vector2i.UP: 180.0, Vector2i.LEFT: -90.0, Vector2i.RIGHT: 90.0}.get(facing, 0.0))

func get_move_interval(running: bool = false) -> float:
	return RUN_DURATION if running else MOVE_DURATION

func toggle_mount() -> bool:
	if editor == null or hp <= 0 or action_time > 0.0:
		return false
	var mounted := not editor.is_mounted
	editor.set_mount_enabled(mounted)
	_sync_render_projection()
	editor.select_animation_by_id(&"ride_idle" if mounted else &"idle")
	_step_time = 0.0
	return mounted

func place(cell: Vector2i, instant: bool = false, duration: float = MOVE_DURATION) -> bool:
	if not can_enter_cell(cell):
		return false
	movement_from_cell = cell if instant else terrain_cell
	terrain_cell = cell
	var destination := (Vector2(terrain_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	if _movement_tween != null and _movement_tween.is_valid():
		_movement_tween.kill()
	_movement_tween = null
	if instant or player_sprite == null or DisplayServer.get_name() == "headless":
		position = destination
	else:
		_movement_tween = create_tween()
		_movement_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_movement_tween.tween_property(self, "position", destination, duration)
	queue_redraw()
	return true

func step(direction: Vector2i, running: bool = false) -> bool:
	if is_inside_tree() and get_tree().paused:
		return false
	if hp <= 0 or action_time > 0.0 or guarding or is_moving():
		return false
	if is_instance_valid(opponent) and opponent.terrain_cell == terrain_cell + direction:
		return false
	if data == null or not data.can_step(terrain_cell, terrain_cell + direction) or not can_enter_cell(terrain_cell + direction):
		return false
	var duration := get_move_interval(running)
	_stance_offset = Vector2.ZERO
	_set_attack_offset(Vector2.ZERO)
	facing = direction
	var moved: bool = place(terrain_cell + direction, false, duration)
	if moved and editor != null:
		editor.set_preview_yaw_degrees({Vector2i.DOWN: 0.0, Vector2i.UP: 180.0, Vector2i.LEFT: -90.0, Vector2i.RIGHT: 90.0}.get(direction, 0.0))
		var locomotion := &"run" if running else &"walk"
		if editor.is_mounted:
			locomotion = &"ride_run" if running else &"ride_walk"
		editor.select_animation_by_id(locomotion)
		_step_time = duration + 0.12
	return moved

func can_enter_cell(cell: Vector2i) -> bool:
	if data == null or not data.is_walkable(cell):
		return false
	if cell_blocker.is_valid() and bool(cell_blocker.call(cell, self)):
		return false
	return true

func is_moving() -> bool:
	return _movement_tween != null and _movement_tween.is_running()

func occupies_cell(cell: Vector2i) -> bool:
	return terrain_cell == cell or (is_moving() and movement_from_cell == cell)

func play_pose(clip: StringName) -> void:
	_step_time = 0.0
	_set_attack_offset(Vector2.ZERO)
	if editor != null:
		editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		if clip == &"idle" and editor.is_mounted:
			clip = &"ride_idle"
		elif clip == &"idle" and combat_ready:
			clip = &"guard"
		editor.select_animation_by_id(clip)

func start_attack(target: TerrainTestCharacter) -> bool:
	if is_inside_tree() and get_tree().paused:
		return false
	if hp <= 0 or action_time > 0.0 or guarding or is_moving() or not is_instance_valid(target) or target.hp <= 0:
		return false
	opponent = target
	_update_combat_ready()
	target._update_combat_ready()
	face_target(target)
	var clip: StringName = &"attack_unarmed"
	if editor != null:
		var weapon_option := editor.part_options.get(&"weapon") as OptionButton
		var weapon: StringName = &"none"
		if weapon_option != null:
			weapon = StringName(str(weapon_option.get_item_metadata(weapon_option.selected)))
		clip = HumanCharacter3DEditor.WEAPON_ATTACK_MAP.get(weapon, &"attack_unarmed")
		if editor.is_mounted:
			clip = &"ride_thrust" if weapon == &"spear_01" else &"ride_slash"
		if not editor.select_animation_by_id(clip):
			return false
		if clip in [&"attack_spear", &"ride_thrust"]:
			# A long spear needs room to extend; draw the leading foot back
			# inside its cell while short weapons use the close fighting stance.
			_stance_offset = Vector2(facing) * 4.0
			_set_attack_offset(Vector2.ZERO)
		editor.speed_slider.value = 1.0
		editor.set_playing(true)
		editor._reset_animation()
		editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_step_time = 0.0
	_attack_range = 6 if clip in [&"attack_bow", &"attack_crossbow"] else (2 if clip in [&"attack_spear", &"ride_thrust"] else 1)
	_attack_damage = 30 if clip in [&"attack_jump_heavy", &"attack_axe", &"attack_hammer"] else 20
	action_time = maxf(0.35, editor._animation_length()) if editor != null else 0.8
	if can_hit(target, _attack_range):
		combat_event.emit(action_time + 10.0)
	_strike_at = action_time * 0.45
	_attack_duration = action_time
	_attack_clip = clip
	_attack_aim_point = target.position
	if target.editor != null:
		var bodies: Array[PackedVector2Array] = _geometry.body_shapes(target)
		if not bodies.is_empty():
			# A rider's shorter sword reaches the upper body, not the waist.
			var aim_body := bodies[1] if clip == &"ride_slash" and bodies.size() > 1 else bodies[0]
			_attack_aim_point = Vector2.ZERO
			for point: Vector2 in aim_body:
				_attack_aim_point += point
			_attack_aim_point /= aim_body.size()
			if facing == Vector2i.DOWN:
				# Screen-down targets expose their head/upper limbs first. Aim at
				# the closest body surface, not a waist hidden below our reach.
				var skeleton := editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
				var shoulder := skeleton.find_bone("J_Bip_R_UpperArm")
				var origin := _geometry.project(self, skeleton.global_transform * skeleton.get_bone_global_pose(shoulder).origin)
				var nearest := INF
				for body: PackedVector2Array in bodies:
					var centre := Vector2.ZERO
					for point: Vector2 in body:
						centre += point
					centre /= body.size()
					for point: Vector2 in body:
						var inset := point.move_toward(centre, 0.5)
						if origin.distance_squared_to(inset) < nearest:
							nearest = origin.distance_squared_to(inset)
							_attack_aim_point = inset
	_attack_step = 0.0
	if data != null and data.can_step(terrain_cell, target.terrain_cell):
		_attack_step = float(ATTACK_STEP_PIXELS.get(clip, 0.0))
	_did_hit = false
	_previous_weapon.clear()
	_attack_elapsed = 0.0
	combat_status = "Attacking"
	return true

func _set_attack_offset(value: Vector2) -> void:
	_attack_offset = value
	if player_sprite != null:
		player_sprite.position = -_map_anchor_offset() + value + _stance_offset

func _update_attack_step(fraction: float) -> void:
	# Imported clips lock planar root motion. Restore a visible in-cell step,
	# shared by the sprite and its projected colliders; never enlarge hitboxes.
	var weight := smoothstep(0.0, 0.20, fraction) * (1.0 - smoothstep(0.72, 1.0, fraction))
	_set_attack_offset(Vector2(facing) * minf(_attack_step, 31.5 - _stance_offset.length()) * weight)

func _sample_attack(delta: float) -> void:
	if editor == null or not is_instance_valid(opponent) or opponent.editor == null:
		return
	# Sample the actual pose at 120 Hz even on a slow rendered frame. No fixed
	# distance-to-target damage fallback; empty/unavailable geometry cannot hit.
	var end_time := minf(_attack_elapsed + delta, _attack_duration)
	while _attack_elapsed < end_time:
		_attack_elapsed = minf(_attack_elapsed + 1.0 / 120.0, end_time)
		_update_attack_step(_attack_elapsed / _attack_duration)
		editor.animation_player.seek(_attack_elapsed, true)
		if _attack_clip in [&"ride_slash", &"ride_thrust"] or (facing == Vector2i.DOWN and _attack_clip not in [&"attack_unarmed", &"attack_bow", &"attack_crossbow"]):
			var fraction := _attack_elapsed / _attack_duration
			var aim_weight := smoothstep(0.18, 0.40, fraction) * (1.0 - smoothstep(0.65, 0.90, fraction))
			_geometry.aim_weapon_attack(self, _attack_aim_point, aim_weight)
		if _attack_clip in [&"attack_bow", &"attack_crossbow"]:
			if not _did_hit and _attack_elapsed >= _attack_duration * 0.45:
				_did_hit = true
				_launch_projectile()
			continue
		var shapes: Array[PackedVector2Array] = _geometry.weapon_shapes(self, _attack_clip)
		var active := _attack_elapsed >= _attack_duration * 0.20 and _attack_elapsed <= _attack_duration * 0.80
		_collision_shapes = shapes
		if active and not _did_hit and _terrain_contact_clear(opponent):
			var hurtboxes: Array[PackedVector2Array] = _geometry.body_shapes(opponent)
			if WeaponCollision.swept_contact(_previous_weapon, shapes, hurtboxes):
				_did_hit = true
				opponent.receive_hit(_attack_damage, self)
				combat_status = "Hit"
		if active:
			_previous_weapon = shapes
		else:
			_previous_weapon.clear()

func _launch_projectile() -> void:
	if not _terrain_contact_clear(opponent):
		return
	var skeleton := editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var hand := skeleton.find_bone("J_Bip_R_Hand")
	if hand < 0:
		return
	skeleton.force_update_all_bone_transforms()
	_projectile_position = _geometry.project(self, skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin)
	var bodies: Array[PackedVector2Array] = _geometry.body_shapes(opponent)
	if bodies.is_empty():
		return
	var aim := Vector2.ZERO
	for point: Vector2 in bodies[0]:
		aim += point
	aim /= bodies[0].size()
	_projectile_velocity = (aim - _projectile_position).normalized() * 420.0
	_projectile_remaining = 6.0 * TerrainRenderer.CELL_PIXELS
	_projectile_target = opponent

func _update_projectile(delta: float) -> void:
	if _projectile_remaining <= 0.0 or not is_instance_valid(_projectile_target):
		return
	var old := _projectile_position
	var travel := minf(_projectile_velocity.length() * delta, _projectile_remaining)
	_projectile_position += _projectile_velocity.normalized() * travel
	_projectile_remaining -= travel
	var sweep: Array[PackedVector2Array] = [WeaponCollision.capsule(old, _projectile_position, 1.0)]
	if _terrain_contact_clear(_projectile_target) and WeaponCollision.swept_contact([], sweep, _geometry.body_shapes(_projectile_target)):
		_projectile_target.receive_hit(_attack_damage, self)
		_projectile_remaining = 0.0
		combat_status = "Projectile hit"

func _terrain_contact_clear(target: TerrainTestCharacter) -> bool:
	if target.hp <= 0 or data == null:
		return false
	# Supercover-style cardinal edge walk: diagonal screen overlap never allows
	# a weapon through a blocked height edge or water.
	var cell := terrain_cell
	var goal := target.terrain_cell
	while cell != goal:
		var step_x := Vector2i(signi(goal.x - cell.x), 0)
		var step_y := Vector2i(0, signi(goal.y - cell.y))
		if step_x != Vector2i.ZERO:
			if not data.can_attack_across(cell, cell + step_x):
				return false
			cell += step_x
		if step_y != Vector2i.ZERO:
			if not data.can_attack_across(cell, cell + step_y):
				return false
			cell += step_y
	return true

func can_hit(target: TerrainTestCharacter, reach: int) -> bool:
	if not is_instance_valid(target) or target.hp <= 0 or data == null:
		return false
	var offset := target.terrain_cell - terrain_cell
	if offset == Vector2i.ZERO or absi(offset.x) + absi(offset.y) > reach:
		return false
	if offset.x != 0 and offset.y != 0:
		return false
	var direction := Vector2i(signi(offset.x), signi(offset.y))
	if direction != facing:
		return false
	var cell := terrain_cell
	while cell != target.terrain_cell:
		if not data.can_attack_across(cell, cell + direction):
			return false
		cell += direction
	return true

func set_guard(enabled: bool) -> void:
	if not enabled:
		guarding = false
	if hp <= 0 or action_time > 0.0 or is_moving():
		return
	guarding = enabled
	play_pose(&"guard" if enabled else &"idle")

func receive_hit(damage: int, attacker: TerrainTestCharacter) -> void:
	if hp <= 0:
		return
	combat_event.emit(10.0)
	var offset := attacker.terrain_cell - terrain_cell
	var blocked := guarding and Vector2(facing).dot(Vector2(offset)) > 0.0
	hp = maxi(0, hp - (int(damage * 0.2) if blocked else damage))
	_strike_at = -1.0
	action_time = 0.35 if hp > 0 else 0.0
	combat_status = "Down" if hp == 0 else ("Blocked" if blocked else "Hurt")
	play_pose(&"down" if hp == 0 else (&"guard" if blocked else &"hit"))
	if hp == 0 and editor != null:
		editor.loop_toggle.set_pressed_no_signal(false)
		editor._play_selected_animation()
	queue_redraw()

func reset_combat() -> void:
	hp = 100
	action_time = 0.0
	_strike_at = -1.0
	_projectile_remaining = 0.0
	_previous_weapon.clear()
	_collision_shapes.clear()
	guarding = false
	combat_status = "Ready"
	play_pose(&"idle")

func _draw() -> void:
	if _projectile_remaining > 0.0:
		draw_line(to_local(_projectile_position), to_local(_projectile_position - _projectile_velocity.normalized() * 12.0), Color("eee3bf"), 1.5)
	if collision_debug:
		if editor != null:
			for shape: PackedVector2Array in _geometry.body_shapes(self):
				var local_body := PackedVector2Array()
				for point: Vector2 in shape:
					local_body.append(to_local(point))
				if local_body.size() > 2:
					local_body.append(local_body[0])
					draw_polyline(local_body, Color(0.2, 0.8, 1.0, 0.7), 1.0)
		for shape: PackedVector2Array in _collision_shapes:
			var local := PackedVector2Array()
			for point: Vector2 in shape:
				local.append(to_local(point))
			if local.size() > 2:
				local.append(local[0])
				draw_polyline(local, Color(1, 0.3, 0.1, 0.9), 1.0)
	draw_rect(Rect2(-20, -66, 40, 5), Color("51282d"))
	draw_rect(Rect2(-20, -66, 40.0 * hp / 100.0, 5), Color("66cf86"))
	draw_circle(Vector2(0, 3) + _attack_offset + _stance_offset, 14.0, Color(0.05, 0.07, 0.08, 0.6))
	if player_sprite != null:
		return
	draw_circle(Vector2.ZERO, 11.0, Color("fff3ca"))
	draw_arc(Vector2.ZERO, 11, 0, TAU, 24, Color("303b47"), 2.0)
	draw_circle(Vector2(3, -3), 2.5, Color("303b47"))
