class_name TerrainArmy
extends Node2D

## Terrain Lab army: one grid-authoritative captain plus 99 soldiers.
## Ordinary soldiers use a shared baked atlas; simulation remains usable in
## headless contract tests and the captain keeps the live 3D presenter.

enum Command { NONE, FOLLOW_PLAYER, MOVE_TO_EDGE }
enum UnitState { IDLE, MOVING, SWAPPING, WAITING, ARRIVED }
enum PathStatus { NONE, PENDING, FOUND, UNREACHABLE }
enum FormationMode { OPEN, COMPRESSING, COLUMN, REGROUPING }
enum Locomotion { IDLE, WALK, RUN }
enum PassagePhase { NONE, APPROACH, IN_PASSAGE, EXIT_CLEAR, RALLY, EXEMPT }

const SOLDIER_COUNT := 100
const SIM_STEP := 0.10
const MOVE_DURATION := 0.24
const RUN_DURATION := 0.18
const FOLLOW_REPLAN_INTERVAL := 0.50
const FOLLOW_DISTANCE := 3
const FOLLOW_TRIGGER := 5
const BLOCKED_REPORT := 5.0
const PLANNING_BUDGET := 8
const MAX_SIM_STEPS_PER_FRAME := 2
const MAX_ACCUMULATED_SIM_TIME := SIM_STEP * 3.0
const MAX_DETOUR_SEARCHES_PER_FRAME := 1
const PATH_EXPANSIONS_PER_STEP := 256
const LOCAL_PATH_EXPANSIONS := 1024
const MAX_LOCAL_PATHS_PER_STEP := 4
const SWAP_COOLDOWN := 0.50
const PUSH_TRANSACTION_TIMEOUT := 4.0
const FORMATION_REPLAN_DISTANCE := 3
const FORMATION_MAX_LAG := 12
const FORMATION_RECOVER_LAG := 8
const FORMATION_COLUMNS := 10
const FORMATION_RUN_LAG := 2
const CAPTAIN_FOLLOW_RUN_DISTANCE := 10
const CAPTAIN_EDGE_RUN_DISTANCE := 16
const FORMATION_REFORM_DISTANCE := 6
const BOTTLENECK_REFRESH_INTERVAL := 1.0
const FORMATION_REPAIR_DELAY := 5.0
const PASSAGE_MAX_NARROW_WIDTH := 2
const PASSAGE_EDGE_SCAN_RADIUS := 5
const PASSAGE_EGRESS_EXPANSIONS := 1024
const INVALID_CELL := Vector2i(-1, -1)
const SOLDIER_ATLAS_PATH := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.png"
const SOLDIER_ATLAS_RESOURCE_PATH := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.res"
const SOLDIER_MANIFEST_PATH := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"
const SOLDIER_DIRECTION_NAMES := {
	Vector2i.UP: "up",
	Vector2i.RIGHT: "right",
	Vector2i.DOWN: "down",
	Vector2i.LEFT: "left",
}
const SOLDIER_ANIMATION_TICK := 1.0 / 30.0

var data: TerrainData
var player: Variant
var npc: Variant
var command: int = Command.NONE
var command_status := "No army / 尚未部署"

var cells: Array[Vector2i] = []
var desired_cells: Array[Vector2i] = []
var moving_to: Array[Vector2i] = []
var movement_state := PackedByteArray()
var locomotion_mode := PackedByteArray()
var move_progress := PackedFloat32Array()
var move_duration := PackedFloat32Array()
var blocked_time := PackedFloat32Array()
var swap_partner := PackedInt32Array()
var _push_lock := PackedByteArray()
var facing: Array[Vector2i] = []
var edge_targets: Array[Vector2i] = []
var formation_mode: int = FormationMode.OPEN
var formation_count_value := 0

var _cell_owners: Dictionary = {}
var _reserved_cells: Dictionary = {}
var _sim_accumulator := 0.0
var _follow_elapsed := 0.0
var _last_follow_player_cell := INVALID_CELL
var _last_follow_leader_cell := INVALID_CELL
var _march_goal := INVALID_CELL
var _march_goal_valid := false
var _formation_anchor_cell := INVALID_CELL
var _formation_march_active := false
var _formation_step_direction := Vector2i.ZERO
var _formation_step_units: Array[int] = []
var _formation_step_batches: Array[Dictionary] = []
var _formation_bend_active := false
var _formation_bend_followup: Array[Vector2i] = []
var _formation_bend_order: Array[Vector2i] = []
var _formation_bend_preview := {}
var _formation_bend_span := 0
var _formation_bend_field: Dictionary = {}
var _formation_bend_lateral: Dictionary = {}
var _formation_guide_group := -1
var _formation_final_reform := false
var _activity_distance_tick := -1
var _activity_distances: Dictionary = {}
var formation_cohesion := {"lag": 0, "unknown": 0, "guards": 0, "runners": 0, "width": 10, "length": 10}
var formation_batch_steps := 0
var formation_bend_steps := 0
var _formation_heading := Vector2i.DOWN
var _formation_anchor_height := -1
var _formation_lagging := false
var _formation_width := FORMATION_COLUMNS
var _formation_passed_count := 0
var _formation_has_bottleneck := false
var _formation_bottleneck_width := FORMATION_COLUMNS
var _formation_rebind_elapsed := 0.0
var _bottleneck_refresh_elapsed := 0.0
var _captain_trail: Array[Vector2i] = []
var _captain_trail_progress_cache: Dictionary = {}
var _formation_offsets: Array[Vector2i] = []
var _formation_slot_cells: Array[Vector2i] = []
var _exit_rally_anchor := INVALID_CELL
var _exit_rally_slots: Array[Vector2i] = []
var _exit_rally_assigned := false
var _exit_rally_settled := false
var _follower_swap_a := -1
var _follower_swap_b := -1
var _pending_pushes: Array[Dictionary] = []
var _follower_routes: Dictionary = {}
var _follower_route_goals: Dictionary = {}
var _follower_route_cursors: Dictionary = {}
var _follower_route_allows_occupied: Dictionary = {}
var _planning_cursor := 0
var _distance_origin := INVALID_CELL
var _distance_values := PackedInt32Array()
var _path_status: int = PathStatus.NONE
var _path_start := INVALID_CELL
var _path_goal := INVALID_CELL
var _path_requester := -1
var _path_previous := PackedInt32Array()
var _path_frontier := PackedInt32Array()
var _path_head := 0
var _path_tail := 0
var _path_route: Array[Vector2i] = []
var _path_route_owner := -1
var _path_route_goal := INVALID_CELL
var _path_route_cursor := 0
var _swap_cooldown := 0.0
var _swap_count := 0
var _completed_steps := 0
var _visual_sources_active := false
var _visual_sources_owned := false
var _visual_dirty := true
var _visual_warmup_frames := 0
var _soldier_anchor := Vector2.ZERO
var _captain_anchor := Vector2.ZERO
var _captain_last_clip := StringName()
var _captain_last_facing := Vector2i(999999, 999999)
var _soldier_editor: Variant
var _captain_editor: Variant
var _sprites: Array[Sprite2D] = []
var _soldier_atlas: Texture2D
var _soldier_frame_textures: Dictionary = {}
var _soldier_frame_anchors: Dictionary = {}
var _soldier_clip_counts: Dictionary = {}
var _soldier_clip_durations: Dictionary = {}
var _soldier_map_scale := 1.0
var _soldier_animation_time := PackedFloat32Array()
var _soldier_current_keys: Array[String] = []
var _soldier_sprite_anchors: Array[Vector2] = []
var _soldier_animation_accumulator := 0.0
var _soldier_baked_ready := false
var _soldier_visual_mode := "uninitialized"
var _detour_searches_remaining := MAX_DETOUR_SEARCHES_PER_FRAME
var _detour_requests_remaining := PLANNING_BUDGET
var _local_path_requests_remaining := MAX_LOCAL_PATHS_PER_STEP
var _local_path_cursor := 1
var _local_search_tick: Dictionary = {}
var _local_occupied_retry: Dictionary = {}
var _push_searches_remaining := 1
var _push_search_ready: Dictionary = {}
var _push_search_cursor := 1
var push_search_requests := 0
var push_search_queued := 0
var local_search_expansions := 0
var push_search_expansions := 0
var max_local_search_expansions := 0
var max_push_search_expansions := 0
var _structure_expansions_remaining := PATH_EXPANSIONS_PER_STEP
var structure_search_expansions := 0
signal _structure_work_ready
var _structure_revision := 0
var _distance_job_origin := INVALID_CELL
var _distance_job_pending := false
var _distance_parents := PackedInt32Array()
var _command_goal_pending := false
var _passage_plan_pending := false
var _formation_target_pending := false
var _exit_rally_pending := false
var max_frame_structure_expansions := 0
var max_frame_local_expansions := 0
var max_frame_push_expansions := 0
var _frame_navigation_budget_active := false
var _command_epoch := 0
var _command_request_epoch := 0
var _pending_command := -1
var _pending_command_epoch := -1
var _route_revision := 0
var _path_route_snapshot: Array[Vector2i] = []
var _path_route_snapshot_revision := 0
var _passage_descriptors: Array[Dictionary] = []
var _passage_active := false
var _passage_group_start := 0
var _passage_group_end := -1
var _passage_route_revision := -1
var _passage_command_epoch := -1
var _passage_final_slots: Array[Vector2i] = []
var _passage_final_captain_slot := INVALID_CELL
var _passage_final_routes: Dictionary = {}
var _passage_final_component: Dictionary = {}
var _formation_final_fields: Dictionary = {}
var _passage_slot_set_revision := 0
var _passage_binding_revision := 0
var _passage_slot_capacity := 0
var _passage_available_capacity := 0
var _passage_failure_reason := ""
var _passage_ticket_order: Array[int] = []
var _passage_service_owner := PackedInt32Array()
var _unit_passage := PackedInt32Array()
var _unit_passage_phase := PackedByteArray()
var _unit_passage_cursor := PackedInt32Array()
var _unit_passage_ticket := PackedInt32Array()
var _unit_passage_crossed := PackedByteArray()
var _unit_passage_exit_clear := PackedByteArray()
var _unit_completed_exits := PackedInt32Array()
var _unit_initial_exempt_exits := PackedInt32Array()
var _passage_crossings := PackedInt32Array()
var _passage_clearings := PackedInt32Array()
var _unit_passage_last_commit_tick := PackedInt32Array()
var _passage_approach_topology_cache := {}
var _passage_tick := 0
var _passage_crossed_count := 0
var _passage_exempt_count := 0
var last_frame_cpu_usec := 0
var input_seconds := 0.0
var simulated_seconds := 0.0
var dropped_seconds := 0.0
var max_passage_expansions := 0

func initialize_visual() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _captain_editor != null and (_soldier_baked_ready or _soldier_editor != null):
		return
	_soldier_baked_ready = _load_baked_soldier()
	if _soldier_baked_ready:
		_soldier_visual_mode = "baked_atlas"
	else:
		# Explicit development fallback for a missing or stale generated atlas.
		# The HUD/test reports this mode so it cannot be mistaken for a perf pass.
		_soldier_editor = _create_visual_source(0, "ArmySoldierVisualSourceFallback")
		_soldier_visual_mode = "live_fallback"
	if _captain_editor == null:
		_captain_editor = _create_visual_source(1, "ArmyCaptainVisualSource")
	_visual_sources_owned = true
	# The sources are created by editor.open(), so force the first transition
	# through the same pause path used after clearing an army.
	_visual_sources_active = true
	_set_visual_sources_active(false)

func visual_mode() -> String:
	return _soldier_visual_mode

func active_3d_source_count() -> int:
	var count := 0
	if _captain_editor != null:
		count += 1
	if _soldier_editor != null:
		count += 1
	return count

func _load_baked_soldier() -> bool:
	_soldier_frame_textures.clear()
	_soldier_frame_anchors.clear()
	_soldier_clip_counts.clear()
	_soldier_clip_durations.clear()
	_soldier_atlas = null
	if not FileAccess.file_exists(ProjectSettings.globalize_path(SOLDIER_MANIFEST_PATH)):
		push_warning("TerrainArmy soldier atlas manifest is missing; using live fallback")
		return false
	# Prefer the imported texture for exports. The file-backed fallback keeps
	# editor/headless visual tests usable immediately after an offline bake,
	# before Godot has produced the PNG's .import sidecar.
	var atlas := ResourceLoader.load(SOLDIER_ATLAS_RESOURCE_PATH) as Texture2D
	if atlas == null:
		atlas = ResourceLoader.load(SOLDIER_ATLAS_PATH) as Texture2D
	if atlas == null:
		var atlas_image := Image.load_from_file(ProjectSettings.globalize_path(SOLDIER_ATLAS_PATH))
		if atlas_image == null or atlas_image.is_empty():
			push_warning("TerrainArmy soldier atlas failed to load; using live fallback")
			return false
		atlas = ImageTexture.create_from_image(atlas_image)
	if atlas == null:
		push_warning("TerrainArmy soldier atlas texture creation failed; using live fallback")
		return false
	_soldier_atlas = atlas
	var file := FileAccess.open(ProjectSettings.globalize_path(SOLDIER_MANIFEST_PATH), FileAccess.READ)
	if file == null:
		push_warning("TerrainArmy soldier atlas manifest failed to open; using live fallback")
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("TerrainArmy soldier atlas manifest is invalid; using live fallback")
		return false
	var manifest: Dictionary = parsed
	_soldier_map_scale = float(manifest.get("map_scale", 1.0))
	for clip_variant in manifest.get("clips", []):
		var clip: Dictionary = clip_variant
		_soldier_clip_counts[String(clip.get("id", ""))] = int(clip.get("samples", 1))
	for frame_variant in manifest.get("frames", []):
		var frame: Dictionary = frame_variant
		var clip_id := String(frame.get("clip", ""))
		var direction_id := String(frame.get("direction", "down"))
		var frame_id := int(frame.get("frame", 0))
		var key := _soldier_frame_key(clip_id, direction_id, frame_id)
		var rect_data: Dictionary = frame.get("rect", {})
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = atlas
		atlas_texture.region = Rect2(rect_data.get("x", 0), rect_data.get("y", 0), rect_data.get("w", 1), rect_data.get("h", 1))
		_soldier_frame_textures[key] = atlas_texture
		var anchor_data: Dictionary = frame.get("anchor_offset", {})
		_soldier_frame_anchors[key] = Vector2(float(anchor_data.get("x", 0.0)), float(anchor_data.get("y", 0.0))) * _soldier_map_scale
		_soldier_clip_durations[clip_id] = float(frame.get("duration", 1.0))
	if _soldier_frame_textures.is_empty():
		push_warning("TerrainArmy soldier atlas manifest has no frames; using live fallback")
		return false
	return true

func _soldier_frame_key(clip_id: String, direction_id: String, frame_id: int) -> String:
	return "%s|%s|%d" % [clip_id, direction_id, frame_id]

func _soldier_direction_id(direction: Vector2i) -> String:
	return String(SOLDIER_DIRECTION_NAMES.get(direction, "down"))

func _locomotion_clip(index: int) -> String:
	if index < 0 or index >= movement_state.size():
		return "idle"
	if movement_state[index] != UnitState.MOVING and movement_state[index] != UnitState.SWAPPING:
		return "idle"
	if locomotion_mode.size() == SOLDIER_COUNT and locomotion_mode[index] == Locomotion.RUN:
		return "run"
	return "walk"

func _set_soldier_frame(index: int, force: bool = false) -> void:
	if not _soldier_baked_ready or index <= 0 or index >= _sprites.size():
		return
	var clip_id := _locomotion_clip(index)
	if not _soldier_clip_counts.has(clip_id):
		clip_id = "walk" if _soldier_clip_counts.has("walk") else "idle"
	var direction_id := _soldier_direction_id(facing[index])
	var frame_count := maxi(1, int(_soldier_clip_counts.get(clip_id, 1)))
	var duration := maxf(0.001, float(_soldier_clip_durations.get(clip_id, 1.0)))
	var phase := fmod(maxf(0.0, _soldier_animation_time[index]), duration) / duration
	var frame_id := mini(frame_count - 1, floori(phase * frame_count))
	var key := _soldier_frame_key(clip_id, direction_id, frame_id)
	if not force and _soldier_current_keys[index] == key:
		return
	var texture_variant = _soldier_frame_textures.get(key)
	if texture_variant == null:
		key = _soldier_frame_key("idle", direction_id, 0)
		texture_variant = _soldier_frame_textures.get(key)
	if texture_variant == null:
		return
	_soldier_current_keys[index] = key
	_sprites[index].texture = texture_variant as Texture2D
	_soldier_sprite_anchors[index] = _soldier_frame_anchors.get(key, Vector2.ZERO)

func _update_soldier_frames(delta: float) -> void:
	if not _soldier_baked_ready or _sprites.size() != SOLDIER_COUNT:
		return
	_soldier_animation_accumulator += delta
	if _soldier_animation_accumulator < SOLDIER_ANIMATION_TICK:
		return
	var elapsed := _soldier_animation_accumulator
	_soldier_animation_accumulator = fmod(_soldier_animation_accumulator, SOLDIER_ANIMATION_TICK)
	for index: int in range(1, SOLDIER_COUNT):
		var clip_id := _locomotion_clip(index)
		if not _soldier_clip_counts.has(clip_id):
			clip_id = "walk" if _soldier_clip_counts.has("walk") else "idle"
		var current_key := _soldier_current_keys[index]
		if current_key.is_empty() or not current_key.begins_with(clip_id + "|"):
			_soldier_animation_time[index] = 0.0
		else:
			_soldier_animation_time[index] += elapsed
		_set_soldier_frame(index)

func _set_visual_sources_active(active: bool) -> void:
	if _visual_sources_active == active:
		return
	_visual_sources_active = active
	for editor: Variant in [_soldier_editor, _captain_editor]:
		if editor == null:
			continue
		editor.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		if editor.preview_viewport != null:
			editor.preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		editor.set_playing(active)
	_sync_captain_presentation(true)


func _captain_yaw_degrees(direction: Vector2i) -> float:
	# Keep the same world-to-preview mapping as TerrainTestCharacter. The
	# editor preview is the captain's presentation authority.
	match direction:
		Vector2i.UP:
			return 180.0
		Vector2i.LEFT:
			return -90.0
		Vector2i.RIGHT:
			return 90.0
		_:
			return 0.0


func _sync_captain_presentation(force: bool = false) -> void:
	if _captain_editor == null:
		return
	var direction := Vector2i.DOWN
	var clip := &"idle"
	if cells.size() > 0 and facing.size() > 0:
		direction = facing[0]
		if movement_state.size() > 0:
			var captain_state: int = movement_state[0]
			if captain_state == UnitState.MOVING or captain_state == UnitState.SWAPPING:
				clip = &"run" if locomotion_mode.size() == SOLDIER_COUNT and locomotion_mode[0] == Locomotion.RUN else &"walk"
	if force or direction != _captain_last_facing:
		_captain_editor.set_preview_yaw_degrees(_captain_yaw_degrees(direction))
		_captain_last_facing = direction
	if force or clip != _captain_last_clip:
		if not _captain_editor.select_animation_by_id(clip):
			# Keep a valid pose even when an imported body lacks locomotion.
			var fallback := &"idle"
			_captain_editor.select_animation_by_id(fallback)
			clip = fallback
		_captain_last_clip = clip


func captain_animation_id() -> StringName:
	if _captain_editor == null:
		return StringName()
	return _captain_editor.selected_animation


func captain_facing() -> Vector2i:
	if facing.size() == 0:
		return Vector2i.DOWN
	return facing[0]


func captain_yaw_degrees() -> float:
	return _captain_yaw_degrees(captain_facing())

func _create_visual_source(body_index: int, source_name: String) -> Variant:
	var editor := HumanCharacter3DEditor.new()
	editor.name = source_name
	editor.preview_host = self
	add_child(editor)
	editor.open()
	# Match the canonical map presenter setup used by TerrainTestCharacter.
	# Without this explicit post-open configuration, a lazily-created source
	# can keep an opaque clear color; 100 projected sprites then form a black
	# rectangle over the terrain.
	var viewport: SubViewport = editor.preview_viewport
	viewport.size = CharacterRenderContract.PREVIEW_VIEWPORT_SIZE
	viewport.transparent_bg = true
	var preview_ground := editor.preview_world.get_node_or_null("PreviewGround") as Node3D
	if preview_ground != null:
		preview_ground.hide()
	for child: Node in editor.preview_world.get_children():
		if child is WorldEnvironment:
			(child as WorldEnvironment).environment.background_mode = Environment.BG_CLEAR_COLOR
	if body_index != 0:
		editor._on_body_selected(body_index)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(true)
	if editor.editor_root != null:
		editor.editor_root.hide()
	return editor

func clear() -> void:
	_structure_revision += 1
	_structure_work_ready.emit()
	_distance_job_pending = false
	_distance_job_origin = INVALID_CELL
	_distance_parents.clear()
	_command_goal_pending = false
	_passage_plan_pending = false
	_formation_target_pending = false
	_exit_rally_pending = false
	_structure_expansions_remaining = 0
	max_frame_structure_expansions = 0
	max_frame_local_expansions = 0
	max_frame_push_expansions = 0
	structure_search_expansions = 0
	local_search_expansions = 0
	push_search_expansions = 0
	push_search_requests = 0
	push_search_queued = 0
	max_local_search_expansions = 0
	max_push_search_expansions = 0
	_local_search_tick.clear()
	_local_occupied_retry.clear()
	_follower_route_allows_occupied.clear()
	_push_search_ready.clear()
	_push_search_cursor = 1
	last_frame_cpu_usec = 0
	input_seconds = 0.0
	simulated_seconds = 0.0
	dropped_seconds = 0.0
	max_passage_expansions = 0
	command = Command.NONE
	command_status = "No army / 尚未部署"
	_command_epoch += 1
	_command_request_epoch = _command_epoch
	_pending_command = -1
	_pending_command_epoch = -1
	_sim_accumulator = 0.0
	_follow_elapsed = 0.0
	_last_follow_player_cell = INVALID_CELL
	_last_follow_leader_cell = INVALID_CELL
	_march_goal = INVALID_CELL
	_march_goal_valid = false
	formation_mode = FormationMode.OPEN
	formation_count_value = 0
	_formation_anchor_cell = INVALID_CELL
	_formation_march_active = false
	_formation_step_direction = Vector2i.ZERO
	_formation_step_units.clear()
	_formation_step_batches.clear()
	_formation_bend_active = false
	_formation_bend_followup.clear()
	_formation_bend_order.clear()
	_formation_bend_preview.clear()
	_formation_bend_span = 0
	_formation_bend_field.clear()
	_formation_bend_lateral.clear()
	_formation_guide_group = -1
	_formation_final_reform = false
	_activity_distance_tick = -1
	_activity_distances.clear()
	formation_batch_steps = 0
	formation_bend_steps = 0
	_formation_heading = Vector2i.DOWN
	_formation_anchor_height = -1
	_formation_lagging = false
	_formation_width = FORMATION_COLUMNS
	_formation_passed_count = 0
	_formation_has_bottleneck = false
	_formation_bottleneck_width = FORMATION_COLUMNS
	_formation_rebind_elapsed = 0.0
	_bottleneck_refresh_elapsed = 0.0
	_captain_trail.clear()
	_captain_trail_progress_cache.clear()
	_formation_offsets.clear()
	_formation_slot_cells.clear()
	_exit_rally_anchor = INVALID_CELL
	_exit_rally_slots.clear()
	_exit_rally_assigned = false
	_exit_rally_settled = false
	_follower_swap_a = -1
	_follower_swap_b = -1
	_pending_pushes.clear()
	_follower_routes.clear()
	_follower_route_goals.clear()
	_follower_route_cursors.clear()
	_push_lock.clear()
	_planning_cursor = 0
	_swap_cooldown = 0.0
	_swap_count = 0
	_completed_steps = 0
	_distance_origin = INVALID_CELL
	_distance_values.clear()
	_clear_path_job()
	_clear_path_route()
	_path_route_snapshot.clear()
	_path_route_snapshot_revision = 0
	_passage_descriptors.clear()
	_passage_active = false
	_passage_group_start = 0
	_passage_group_end = -1
	_passage_route_revision = -1
	_passage_command_epoch = -1
	_passage_final_slots.clear()
	_passage_final_captain_slot = INVALID_CELL
	_passage_final_routes.clear()
	_passage_final_component.clear()
	_formation_final_fields.clear()
	_passage_slot_capacity = 0
	_passage_available_capacity = 0
	_passage_failure_reason = ""
	_passage_ticket_order.clear()
	_passage_service_owner.clear()
	_unit_passage.clear()
	_unit_passage_phase.clear()
	_unit_passage_cursor.clear()
	_unit_passage_ticket.clear()
	_unit_passage_crossed.clear()
	_unit_passage_exit_clear.clear()
	_unit_completed_exits.clear()
	_unit_initial_exempt_exits.clear()
	_passage_crossings.clear()
	_passage_clearings.clear()
	_unit_passage_last_commit_tick.clear()
	_passage_approach_topology_cache.clear()
	_passage_tick = 0
	_passage_crossed_count = 0
	_passage_exempt_count = 0
	_visual_dirty = true
	_visual_warmup_frames = 0
	_soldier_animation_accumulator = 0.0
	_detour_requests_remaining = PLANNING_BUDGET
	_local_path_requests_remaining = MAX_LOCAL_PATHS_PER_STEP
	_local_path_cursor = 1
	_soldier_animation_time.clear()
	_soldier_current_keys.clear()
	_soldier_sprite_anchors.clear()
	_cell_owners.clear()
	_reserved_cells.clear()
	cells.clear()
	desired_cells.clear()
	moving_to.clear()
	movement_state.clear()
	locomotion_mode.clear()
	move_progress.clear()
	move_duration.clear()
	blocked_time.clear()
	swap_partner.clear()
	facing.clear()
	edge_targets.clear()
	for sprite: Sprite2D in _sprites:
		sprite.visible = false
	_set_visual_sources_active(false)

func has_army() -> bool:
	return cells.size() == SOLDIER_COUNT

func deploy(new_data: TerrainData, new_player: Variant, new_npc: Variant) -> bool:
	data = new_data
	player = new_player
	npc = new_npc
	clear()
	if data == null or player == null or not data.contains(player.terrain_cell):
		command_status = "Deploy rejected: player cell is invalid"
		return false
	# Do not pack the deployment around the PLAYER cell itself. The player and
	# NPC are external blockers, so a dense 10x10 seed centred on them can form
	# a closed ring before the first march tick. Start the same deterministic
	# reachable scan a few cells away, leaving an egress side for the formation
	# without changing the terrain or the army's authoritative cell model.
	var deployment_origin := _deployment_origin(player.terrain_cell)
	var candidates := _reachable_cells(deployment_origin)
	var selected: Array[Vector2i] = []
	for cell: Vector2i in candidates:
		if cell == player.terrain_cell or _is_external_cell(cell):
			continue
		selected.append(cell)
		if selected.size() == SOLDIER_COUNT:
			break
	if selected.size() != SOLDIER_COUNT:
		clear()
		command_status = "Deploy rejected: only %d/%d legal cells" % [selected.size(), SOLDIER_COUNT]
		return false
	# Put the captain near the centre of the initial reachable patch. Starting
	# on the outside made the first command look like a queue leaving a camp;
	# a central leader lets the first OPEN formation preserve the deployed body.
	var captain_position := mini(selected.size() - 1, floori(float(selected.size()) / 2.0))
	var captain_cell: Vector2i = selected[captain_position]
	selected.remove_at(captain_position)
	selected.push_front(captain_cell)
	cells = selected.duplicate()
	for index: int in range(SOLDIER_COUNT):
		desired_cells.append(cells[index])
		moving_to.append(INVALID_CELL)
		movement_state.append(UnitState.IDLE)
		locomotion_mode.append(Locomotion.IDLE)
		move_progress.append(0.0)
		move_duration.append(MOVE_DURATION)
		blocked_time.append(0.0)
		swap_partner.append(-1)
		_push_lock.append(0)
		facing.append(Vector2i.DOWN)
		_cell_owners[cells[index]] = index
		_unit_passage.append(-1)
		_unit_passage_phase.append(PassagePhase.NONE)
		_unit_passage_cursor.append(-1)
		_unit_passage_ticket.append(-1)
		_unit_passage_crossed.append(0)
		_unit_passage_exit_clear.append(0)
		_unit_completed_exits.append(0)
		_unit_initial_exempt_exits.append(0)
		_unit_passage_last_commit_tick.append(0)
	_captain_trail.append(cells[0])
	# Deployment is a stationary setup state. Do not immediately move the
	# followers into a new formation before the player issues FOLLOW or EDGE.
	# The live command rebuilds these slots through _update_formation_targets.
	_formation_anchor_cell = cells[0]
	_formation_heading = Vector2i.DOWN
	_formation_anchor_height = int(data.height_levels[data.index(cells[0])])
	formation_mode = FormationMode.OPEN
	_formation_width = FORMATION_COLUMNS
	_formation_slot_cells.resize(SOLDIER_COUNT)
	_formation_offsets.resize(SOLDIER_COUNT)
	for index: int in range(SOLDIER_COUNT):
		_formation_slot_cells[index] = cells[index]
		_formation_offsets[index] = cells[index] - cells[0]
	formation_count_value = SOLDIER_COUNT - 1
	_rebuild_visual_instances()
	_set_visual_sources_active(true)
	# A SubViewport publishes its first rendered texture after the current
	# frame. Keep the shared 3D sources alive for two draw frames so the map
	# sprites never capture the viewport's initial black clear texture.
	_visual_warmup_frames = 2
	command_status = "Deployed 100: captain + 99 soldiers"
	_visual_dirty = true
	queue_redraw()
	return true

func _deployment_origin(start: Vector2i) -> Vector2i:
	if data != null:
		var offsets: Array[Vector2i] = [Vector2i.RIGHT * 8, Vector2i.LEFT * 8, Vector2i.DOWN * 8, Vector2i.UP * 8, Vector2i(6, 6), Vector2i(-6, 6), Vector2i(6, -6), Vector2i(-6, -6)]
		for offset: Vector2i in offsets:
			var candidate := start + offset
			if data.contains(candidate) and data.is_walkable(candidate) and not _is_external_cell(candidate):
				return candidate
	return start

func issue_command(next_command: int) -> bool:
	if not has_army():
		command_status = "Command rejected: deploy the army first"
		return false
	if next_command != Command.FOLLOW_PLAYER and next_command != Command.MOVE_TO_EDGE:
		command_status = "Unknown army command"
		return false
	_command_request_epoch += 1
	_pending_command = next_command
	_pending_command_epoch = _command_request_epoch
	_cancel_pending_pushes()
	_push_search_ready.clear()
	_try_activate_pending_command()
	if _pending_command >= 0:
		command_status = "DRAIN | finish active edges and clear the old corridor before changing direction"
	return true

func _try_activate_pending_command() -> void:
	if _pending_command < 0 or not has_army() or moving_count() > 0:
		return
	if _passage_active:
		for index: int in range(SOLDIER_COUNT):
			if _unit_passage_phase[index] == PassagePhase.IN_PASSAGE \
				or (_unit_passage_phase[index] == PassagePhase.EXIT_CLEAR and _unit_passage_exit_clear[index] == 0):
				return
	var next_command := _pending_command
	var next_epoch := _pending_command_epoch
	_pending_command = -1
	_pending_command_epoch = -1
	_activate_command(next_command, next_epoch)

func _activate_command(next_command: int, next_epoch: int) -> void:
	_command_epoch = next_epoch
	command = next_command
	_clear_navigation_paths()
	_formation_march_active = false
	var average := Vector2.ZERO
	for cell: Vector2i in cells:
		average += Vector2(cell)
	average /= float(SOLDIER_COUNT)
	_formation_anchor_cell = Vector2i(average.round())
	if not data.contains(_formation_anchor_cell) or not data.is_walkable(_formation_anchor_cell) or _is_external_cell(_formation_anchor_cell):
		_formation_anchor_cell = cells[0]
	_cancel_pending_pushes()
	_command_goal_pending = true
	# A command change invalidates unstarted follower detours and queued claims,
	# while a move already in progress is allowed to finish atomically.
	_follower_routes.clear()
	_follower_route_goals.clear()
	_follower_route_cursors.clear()
	_follower_route_allows_occupied.clear()
	_local_occupied_retry.clear()
	_local_search_tick.clear()
	_push_search_ready.clear()
	_exit_rally_anchor = INVALID_CELL
	_exit_rally_slots.clear()
	_exit_rally_assigned = false
	_exit_rally_settled = false
	_follow_elapsed = FOLLOW_REPLAN_INTERVAL
	_march_goal = INVALID_CELL
	_march_goal_valid = false
	if command == Command.FOLLOW_PLAYER:
		_last_follow_player_cell = INVALID_CELL
		_last_follow_leader_cell = INVALID_CELL
		_replan_follow()
		command_status = "Following PLAYER"
	else:
		if not _choose_edge_targets():
			command = Command.NONE
			return
		command_status = "Formation marching to map edge"
	queue_redraw()

func blocks_cell(cell: Vector2i, _requester: Node = null) -> bool:
	return _cell_owners.has(cell) or _reserved_cells.has(cell)

func occupied_count() -> int:
	return _cell_owners.size()

func moving_count() -> int:
	var count := 0
	for state: int in movement_state:
		if state == UnitState.MOVING or state == UnitState.SWAPPING:
			count += 1
	return count

func swap_count() -> int:
	return _swap_count

func completed_steps() -> int:
	return _completed_steps

func has_active_swap() -> bool:
	return has_army() and swap_partner.size() == SOLDIER_COUNT and swap_partner[0] >= 0

func arrived_count() -> int:
	if not has_army():
		return 0
	var count := 0
	for index: int in range(SOLDIER_COUNT):
		if movement_state[index] == UnitState.ARRIVED and cells[index] == desired_cells[index]:
			count += 1
	return count

func captain_at_boundary() -> bool:
	if not has_army() or data == null:
		return false
	var cell := cells[0]
	return cell.x == 0 or cell.y == 0 or cell.x == data.size.x - 1 or cell.y == data.size.y - 1

func formation_count() -> int:
	return formation_count_value

func formation_mode_name() -> String:
	match formation_mode:
		FormationMode.COMPRESSING:
			return "COMPRESSING"
		FormationMode.COLUMN:
			return "COLUMN"
		FormationMode.REGROUPING:
			return "REGROUPING"
		_:
			return "OPEN"

func formation_width() -> int:
	return int(formation_cohesion.width) if _formation_march_active else _formation_width

func running_count() -> int:
	if locomotion_mode.size() != SOLDIER_COUNT:
		return 0
	var count := 0
	for index: int in range(SOLDIER_COUNT):
		if locomotion_mode[index] == Locomotion.RUN:
			count += 1
	return count

func is_formation_complete() -> bool:
	if _pending_command >= 0 or _command_goal_pending or _passage_plan_pending or _formation_target_pending:
		return false
	if _passage_active:
		return _passage_complete()
	if _formation_march_active and not _formation_front_at_goal():
		return false
	if not has_army() or formation_mode == FormationMode.REGROUPING:
		return false
	if cells[0] != desired_cells[0] or moving_count() > 0 or not _reserved_cells.is_empty() or not _pending_pushes.is_empty():
		return false
	for lock: int in _push_lock:
		if lock != 0:
			return false
	for index: int in range(1, SOLDIER_COUNT):
		if cells[index] != desired_cells[index]:
			return false
		if movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING:
			return false
	return true

func _reachable_cells(start: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var visited := {start: true}
	var pending: Array[Vector2i] = [start]
	var head := 0
	while head < pending.size():
		var cell: Vector2i = pending[head]
		head += 1
		if cell != start and not _is_external_cell(cell):
			result.append(cell)
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not data.contains(next) or visited.has(next) or not data.can_step(cell, next):
				continue
			visited[next] = true
			pending.append(next)
	return result

func _is_external_cell(cell: Vector2i) -> bool:
	return (player != null and player.terrain_cell == cell) or (npc != null and npc.terrain_cell == cell)

func _replan_follow() -> bool:
	if player == null or not data.contains(player.terrain_cell):
		return false
	# One stable front goal follows PLAYER; every member, including the
	# captain, receives its own current formation or receiving slot.
	var player_target_changed: bool = player.terrain_cell != _last_follow_player_cell
	if not player_target_changed and not _command_goal_pending:
		return true
	if player_target_changed and not _command_goal_pending:
		# PLAYER motion is a new request too. It must use the same atomic
		# handoff as an explicit button press while an old corridor is occupied.
		return issue_command(Command.FOLLOW_PLAYER)
	if _formation_target_pending:
		return true
	if not _ensure_distance_map(_formation_anchor_cell):
		command_status = "PLANNING | shared navigation field"
		return true
	if not _command_goal_pending:
		return true
	var revision := _structure_revision
	_formation_target_pending = true
	var leader_goal := await _find_follow_goal(revision)
	if revision != _structure_revision:
		return false
	_formation_target_pending = false
	if leader_goal == INVALID_CELL:
		# The player may still be inside the initial deployment ring. Keep the
		# command live and wait for the next legal opening instead of rejecting it.
		leader_goal = cells[0]
	_march_goal = leader_goal
	_march_goal_valid = leader_goal != cells[0]
	desired_cells[0] = leader_goal
	_command_goal_pending = false
	_publish_distance_route(leader_goal)
	_update_formation_targets(true if player_target_changed else false)
	_last_follow_player_cell = player.terrain_cell
	_last_follow_leader_cell = cells[0]
	return true

func _find_follow_goal(revision: int) -> Vector2i:
	var leader := _formation_anchor_cell
	if not _ensure_distance_map(leader):
		return INVALID_CELL
	var candidates: Array[Vector2i] = []
	for y: int in range(-FOLLOW_TRIGGER, FOLLOW_TRIGGER + 1):
		for x: int in range(-FOLLOW_TRIGGER, FOLLOW_TRIGGER + 1):
			var manhattan := absi(x) + absi(y)
			if manhattan < FOLLOW_DISTANCE or manhattan > FOLLOW_TRIGGER:
				continue
			var candidate: Vector2i = player.terrain_cell + Vector2i(x, y)
			if not data.contains(candidate) or not data.is_walkable(candidate) or _is_external_cell(candidate):
				continue
			if _cell_owners.has(candidate) and candidate != leader:
				var occupant := int(_cell_owners[candidate])
				if not _can_captain_swap_with(occupant):
					continue
			var path_distance := _distance_to_cell(candidate)
			if path_distance < 0:
				continue
			candidates.append(candidate)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := _distance_to_cell(a)
		var db := _distance_to_cell(b)
		return da < db if da != db else (a.y < b.y if a.y != b.y else a.x < b.x))
	var reachable := {}
	for cell_index: int in range(_distance_values.size()):
		if not await _take_structure_expansion(revision):
			return INVALID_CELL
		if _distance_values[cell_index] >= 0:
			reachable[Vector2i(cell_index % data.size.x, floori(float(cell_index) / data.size.x))] = _distance_values[cell_index]
	for candidate: Vector2i in candidates:
		var parent_index := _distance_parents[data.index(candidate)]
		var parent := Vector2i(parent_index % data.size.x, floori(float(parent_index) / data.size.x))
		var heading := candidate - parent
		if heading == Vector2i.ZERO:
			heading = _formation_heading
		var route: Array[Vector2i] = [candidate]
		var route_index := data.index(candidate)
		while route_index != data.index(leader):
			if not await _take_structure_expansion(revision):
				return INVALID_CELL
			route_index = _distance_parents[route_index]
			route.push_front(Vector2i(route_index % data.size.x, floori(float(route_index) / data.size.x)))
		var passages := await _route_passage_segments(route, revision)
		var protected := {}
		for passage: Dictionary in passages:
			# The same terminal indentation exception used by the actual plan:
			# its front may occupy the tip, but an incoming gate/egress may not
			# be counted as spare footprint capacity across the separating wall.
			var terminal_flat := int(passage.last_edge) == route.size() - 2
			for cell: Vector2i in passage.corridor:
				terminal_flat = terminal_flat and data.height_levels[data.index(cell)] == data.height_levels[data.index(passage.entry)]
			if not terminal_flat:
				for cell: Vector2i in passage.protected:
					protected[cell] = true
				protected[passage.exit] = true
		# Select a feasible front before publishing its immutable route. This
		# reuses the same local 100-cell builder; it is one command-level check,
		# not a search per soldier or a later drift of the requested goal.
		var layout := await _compact_boundary_layout(reachable, protected, candidate, heading, revision)
		if layout.size() == SOLDIER_COUNT:
			return candidate
		for lateral_min: int in range(-FORMATION_COLUMNS + 1, 1):
			if lateral_min == -4:
				continue
			layout = await _compact_boundary_layout(reachable, protected, candidate, heading, revision, lateral_min)
			if layout.size() == SOLDIER_COUNT:
				return candidate
		if revision != _structure_revision:
			return INVALID_CELL
	# Let the normal plan publish its typed capacity/layout failure if none of
	# the reachable front candidates can hold the whole body. Never scout.
	return candidates[0] if not candidates.is_empty() else INVALID_CELL

func _captain_heading() -> Vector2i:
	if _path_route_cursor < _path_route.size():
		var next := _path_route[_path_route_cursor]
		var route_direction := next - _formation_anchor_cell
		if route_direction in TerrainData.DIRECTIONS:
			return route_direction
	if facing.size() > 0 and facing[0] in TerrainData.DIRECTIONS:
		return facing[0]
	if _march_goal_valid:
		var delta := _march_goal - cells[0]
		if absi(delta.x) >= absi(delta.y) and delta.x != 0:
			return Vector2i(signi(delta.x), 0)
		if delta.y != 0:
			return Vector2i(0, signi(delta.y))
	return Vector2i.DOWN

func _walkable_degree(cell: Vector2i) -> int:
	var degree := 0
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if data.can_step(cell, cell + direction):
			degree += 1
	return degree

func _route_width() -> int:
	if data == null or not has_army() or _path_route.is_empty():
		return FORMATION_COLUMNS
	var minimum_width := FORMATION_COLUMNS
	var previous := cells[0]
	var inspected := 0
	for route_index: int in range(_path_route_cursor, mini(_path_route.size(), _path_route_cursor + 12)):
		var route_cell: Vector2i = _path_route[route_index]
		if not data.contains(route_cell):
			continue
		var width := _route_edge_width(previous, route_cell)
		minimum_width = mini(minimum_width, width)
		previous = route_cell
		inspected += 1
	return FORMATION_COLUMNS if inspected == 0 else clampi(minimum_width, 1, FORMATION_COLUMNS)

func _route_is_narrow() -> bool:
	return _route_width() < FORMATION_COLUMNS

func _formation_preferred_cell(index: int, anchor: Vector2i, heading: Vector2i) -> Vector2i:
	var behind := -heading
	var side := Vector2i(-heading.y, heading.x)
	if formation_mode == FormationMode.COMPRESSING or formation_mode == FormationMode.COLUMN:
		var width := maxi(1, _formation_width)
		var compact_slot := index - 1
		var compact_column := compact_slot % width
		var side_offset := compact_column - floori(float(width - 1) / 2.0)
		var compact_rank := floori(float(compact_slot) / float(width)) + 1
		if formation_mode == FormationMode.COLUMN and _formation_has_bottleneck and not _captain_trail.is_empty():
			var trail_index := _captain_trail.size() - 1 - compact_rank
			if trail_index >= 0:
				return _captain_trail[trail_index] + side * side_offset
		return anchor + behind * compact_rank + side * side_offset
	var slot := index - 1
	var column := slot % FORMATION_COLUMNS - 4
	var rank := floori(float(slot) / float(FORMATION_COLUMNS)) + 1
	return anchor + behind * rank + side * column

func _captain_trail_progress(cell: Vector2i) -> int:
	if _captain_trail.is_empty():
		return -1
	if _captain_trail_progress_cache.has(cell):
		return int(_captain_trail_progress_cache[cell])
	var best_index := 0
	var best_distance := 1 << 30
	for trail_index: int in range(_captain_trail.size()):
		var trail_cell: Vector2i = _captain_trail[trail_index]
		if trail_cell == cell:
			_captain_trail_progress_cache[cell] = trail_index
			return trail_index
		var distance := absi(cell.x - trail_cell.x) + absi(cell.y - trail_cell.y)
		# Prefer the later trail cell when a unit is beside a straight
		# corridor. That keeps the queue moving forward instead of sending a
		# unit back to the earlier side of a ramp.
		if distance < best_distance or (distance == best_distance and trail_index > best_index):
			best_index = trail_index
			best_distance = distance
	_captain_trail_progress_cache[cell] = best_index
	return best_index

func _exit_rally_targets(anchor: Vector2i) -> Array[Vector2i]:
	if data == null or not data.contains(anchor):
		return []
	if anchor == _exit_rally_anchor and not _exit_rally_slots.is_empty():
		return _exit_rally_slots.duplicate()
	if not _exit_rally_pending:
		_exit_rally_pending = true
		_build_exit_rally_targets(anchor, _structure_revision)
	return []

func _build_exit_rally_targets(anchor: Vector2i, revision: int) -> void:
	var result: Array[Vector2i] = []
	var protected := {}
	for trail_cell: Vector2i in _captain_trail:
		protected[trail_cell] = true
	var pending: Array[Vector2i] = [anchor]
	var visited := {anchor: true}
	var head := 0
	while head < pending.size() and pending.size() <= 4096:
		if not await _take_structure_expansion(revision):
			return
		var current: Vector2i = pending[head]
		head += 1
		if current != anchor and not protected.has(current) and not _is_external_cell(current):
			result.append(current)
			if result.size() >= SOLDIER_COUNT - 1:
				break
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if visited.has(next) or not data.contains(next) or not data.can_step(current, next):
				continue
			visited[next] = true
			pending.append(next)
	_exit_rally_anchor = anchor
	_exit_rally_slots = result.duplicate()
	_exit_rally_pending = false

func _assign_bottleneck_queue_targets(slot_targets: Array[Vector2i]) -> bool:
	# Once the captain has laid down a complete route behind the passage, use
	# that route as a single-file queue. Units are ranked by their current
	# progress and receive monotonically decreasing trail slots; this prevents
	# a unit that already cleared the ramp from being reassigned to a slot on
	# the lower side, which was the source of the pass deadlock.
	if _captain_trail.size() < SOLDIER_COUNT + 1:
		return false
	var remaining: Array[int] = []
	for index: int in range(1, SOLDIER_COUNT):
		remaining.append(index)
	var previous_target_index := _captain_trail.size() - 1
	var exit_targets: Array[Vector2i] = []
	if captain_at_boundary():
		exit_targets = _exit_rally_targets(cells[0])
	# Use every legal exit-side slot that exists. Leaving a fixed number of
	# soldiers on the captain trail makes the passage self-blocking once the
	# first ranks settle; a small platform naturally yields fewer slots and
	# remains a real formation-capacity limit.
	var exit_slot_count := exit_targets.size()
	for exit_order: int in range(remaining.size()):
		var best_position := 0
		var best_progress := -1
		for candidate_position: int in range(remaining.size()):
			var candidate_index: int = remaining[candidate_position]
			var candidate_progress := _captain_trail_progress(cells[candidate_index])
			if candidate_progress > best_progress or (candidate_progress == best_progress and candidate_index < remaining[best_position]):
				best_position = candidate_position
				best_progress = candidate_progress
		var unit_index: int = remaining[best_position]
		remaining.remove_at(best_position)
		if exit_order < exit_slot_count:
			desired_cells[unit_index] = exit_targets[exit_order]
			_formation_slot_cells[unit_index] = exit_targets[exit_order]
			continue
		var trail_position := exit_order - exit_slot_count
		var target_index := mini(previous_target_index - 1, _captain_trail.size() - 2 - trail_position)
		if best_progress >= 0:
			target_index = maxi(target_index, best_progress)
		# Preserve a strict queue order. There is one target per rank, so a
		# follower can never be assigned behind a unit that is already ahead of
		# it on the captain route.
		target_index = mini(target_index, previous_target_index - 1)
		target_index = maxi(target_index, 1)
		var target := _captain_trail[target_index]
		if not data.contains(target) or not data.is_walkable(target) or _is_external_cell(target):
			target = slot_targets[unit_index] if unit_index < slot_targets.size() else cells[unit_index]
		desired_cells[unit_index] = target
		_formation_slot_cells[unit_index] = target
		previous_target_index = target_index
	return true

func _refresh_bottleneck_queue_targets() -> void:
	if _passage_active or not _formation_has_bottleneck or formation_mode != FormationMode.COLUMN or _captain_trail.size() < SOLDIER_COUNT + 1:
		return
	if captain_at_boundary() and _exit_rally_assigned:
		return
	var slot_targets: Array[Vector2i] = []
	slot_targets.resize(SOLDIER_COUNT)
	for index: int in range(SOLDIER_COUNT):
		slot_targets[index] = desired_cells[index]
	if _assign_bottleneck_queue_targets(slot_targets):
		if captain_at_boundary() and not _exit_rally_targets(cells[0]).is_empty():
			_exit_rally_assigned = true
		_update_formation_status()

func _formation_all_settled() -> bool:
	if not has_army() or desired_cells.size() != SOLDIER_COUNT:
		return false
	for index: int in range(1, SOLDIER_COUNT):
		if desired_cells[index] == INVALID_CELL or cells[index] != desired_cells[index]:
			return false
		if movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING:
			return false
	return true

func _repair_idle_slot_bindings() -> bool:
	# An idle occupant may keep an existing published slot by exchanging only
	# its binding with that slot's idle owner. Never rematch unrelated identities
	# or touch an in-flight/claimed destination.
	if not has_army() or _formation_bend_active:
		return false
	if not _passage_active and (formation_mode != FormationMode.OPEN or _formation_has_bottleneck):
		return false
	var bindings := {}
	var group_clear := _passage_active
	if group_clear:
		for unit: int in range(SOLDIER_COUNT):
			if not _unit_has_cleared_group(unit):
				group_clear = false
				break
	for index: int in range(1, SOLDIER_COUNT):
		bindings[desired_cells[index]] = index
	var changed := false
	for index: int in range(1, SOLDIER_COUNT):
		var current := cells[index]
		var other := int(bindings.get(current, -1))
		if other <= 0 or other == index:
			continue
		var old_goal := desired_cells[index]
		if _passage_active and not group_clear and not _active_rally_slots().has(cells[other]):
			# Do not give an early arrival the first slot it walks through while
			# handing its deeper target back to somebody still outside the layout.
			continue
		var safe := true
		for unit: int in [index, other]:
			if _passage_active and not _formation_march_active and not _unit_has_cleared_group(unit):
				safe = false
			if movement_state[unit] == UnitState.MOVING or movement_state[unit] == UnitState.SWAPPING or _push_lock[unit] != 0:
				safe = false
			if _reserved_cells.has(cells[unit]) or _reserved_cells.has(desired_cells[unit]):
				safe = false
		if not safe:
			continue
		desired_cells[index] = current
		desired_cells[other] = old_goal
		_formation_slot_cells[index] = current
		_formation_slot_cells[other] = old_goal
		if _formation_march_active:
			_formation_offsets[index] = current - _formation_anchor_cell
			_formation_offsets[other] = old_goal - _formation_anchor_cell
		if _passage_active and _unit_passage_phase[index] == PassagePhase.EXIT_CLEAR:
			_unit_passage_phase[index] = PassagePhase.RALLY
		bindings[current] = index
		bindings[old_goal] = other
		_clear_follower_route(index)
		_clear_follower_route(other)
		changed = true
	if changed:
		if _passage_active:
			_passage_binding_revision += 1
		_update_formation_status()
	return changed

func _open_slot_set_is_occupied() -> bool:
	if not has_army() or (_passage_active and not _formation_march_active) or formation_mode != FormationMode.OPEN or _formation_has_bottleneck or _formation_slot_cells.size() != SOLDIER_COUNT:
		return false
	for index: int in range(1, SOLDIER_COUNT):
		if int(_cell_owners.get(_formation_slot_cells[index], -1)) <= 0:
			return false
	return true

func _all_followers_on_captain_height() -> bool:
	if not has_army() or data == null:
		return false
	var captain_height := int(data.height_levels[data.index(cells[0])])
	for index: int in range(1, SOLDIER_COUNT):
		if not data.contains(cells[index]) or int(data.height_levels[data.index(cells[index])]) != captain_height:
			return false
	return true

func _all_followers_in_exit_rally() -> bool:
	if _passage_active:
		return _passage_complete()
	var rally_anchor_valid := command == Command.MOVE_TO_EDGE and captain_at_boundary()
	if command == Command.FOLLOW_PLAYER and has_army() and cells[0] == desired_cells[0]:
		rally_anchor_valid = true
	if not has_army() or not rally_anchor_valid or data == null or not data.contains(cells[0]):
		return false
	if _exit_rally_slots.size() != SOLDIER_COUNT - 1:
		return false
	var valid_slots := {}
	for slot: Vector2i in _exit_rally_slots:
		if not data.is_walkable(slot) or _is_external_cell(slot) or valid_slots.has(slot):
			return false
		valid_slots[slot] = true
	var captain_height := int(data.height_levels[data.index(cells[0])])
	for index: int in range(1, SOLDIER_COUNT):
		if movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING:
			return false
		if cells[index] != desired_cells[index] or not valid_slots.has(cells[index]):
			return false
		if not data.contains(cells[index]) or int(data.height_levels[data.index(cells[index])]) != captain_height:
			return false
	return true

func _publish_exit_rally_targets() -> bool:
	if _exit_rally_slots.size() != SOLDIER_COUNT - 1:
		return false
	var available: Array[int] = []
	for index: int in range(1, SOLDIER_COUNT):
		available.append(index)
	var assigned_slots := {}
	# Keep any follower already occupying a published slot. Only identities are
	# re-paired; the terrain-derived exit slot set never changes here.
	for slot: Vector2i in _exit_rally_slots:
		var occupant := int(_cell_owners.get(slot, -1))
		if occupant <= 0 or not available.has(occupant):
			continue
		desired_cells[occupant] = slot
		_formation_slot_cells[occupant] = slot
		assigned_slots[slot] = true
		available.erase(occupant)
	for slot: Vector2i in _exit_rally_slots:
		if assigned_slots.has(slot) or available.is_empty():
			continue
		var best_position := 0
		var best_distance := 1 << 30
		for available_position: int in range(available.size()):
			var index: int = available[available_position]
			var distance := absi(cells[index].x - slot.x) + absi(cells[index].y - slot.y)
			if distance < best_distance or (distance == best_distance and index < available[best_position]):
				best_position = available_position
				best_distance = distance
		var assigned_index: int = available[best_position]
		desired_cells[assigned_index] = slot
		_formation_slot_cells[assigned_index] = slot
		available.remove_at(best_position)
	_follower_routes.clear()
	_follower_route_goals.clear()
	_follower_route_cursors.clear()
	return available.is_empty()

func _settle_exit_rally() -> void:
	if _passage_active:
		_finish_passage()
		return
	if _exit_rally_settled or not _all_followers_in_exit_rally():
		return
	# Every follower is already on a unique, published exit-side slot. Do not
	# cancel motion or copy current cells into desired slots here: both actions
	# can manufacture a 99/99 result before the passage was consumed.
	_follower_routes.clear()
	_follower_route_goals.clear()
	_follower_route_cursors.clear()
	for index: int in range(1, SOLDIER_COUNT):
		movement_state[index] = UnitState.ARRIVED if command == Command.MOVE_TO_EDGE else UnitState.IDLE
		locomotion_mode[index] = Locomotion.IDLE
		blocked_time[index] = 0.0
	formation_mode = FormationMode.OPEN
	_formation_width = FORMATION_COLUMNS
	_formation_lagging = false
	_exit_rally_settled = true
	_update_formation_status()
	command_status = "Exit rally assembled %d/99" % formation_count_value

func _cancel_pending_pushes() -> void:
	for pending: Dictionary in _pending_pushes:
		_release_push_transaction(pending, true)
	_pending_pushes.clear()

func _desired_formation_mode() -> int:
	var route_width := clampi(_route_width(), 1, FORMATION_COLUMNS)
	_formation_width = route_width
	if route_width < FORMATION_COLUMNS:
		if not _formation_has_bottleneck:
			_cancel_pending_pushes()
		_formation_bottleneck_width = mini(_formation_bottleneck_width, route_width)
		_formation_has_bottleneck = true
		return FormationMode.COMPRESSING if formation_mode == FormationMode.OPEN else FormationMode.COLUMN
	if _formation_has_bottleneck and not _formation_all_settled():
		# Keep the queue contract after the captain has cleared the visible
		# bottleneck; otherwise followers on the far side would be assigned a
		# broad slot before they have crossed the same ramp.
		_formation_width = maxi(1, _formation_bottleneck_width)
		return FormationMode.COLUMN
	if _formation_has_bottleneck:
		# The entire body has reached the post-ramp rally slots. A subsequent
		# OPEN replan may widen the body again, but the narrow width is retained
		# while any member is still crossing the corridor.
		_formation_has_bottleneck = false
		_formation_bottleneck_width = FORMATION_COLUMNS
	if formation_mode == FormationMode.COLUMN or formation_mode == FormationMode.COMPRESSING:
		return FormationMode.OPEN if _formation_all_settled() else FormationMode.REGROUPING
	if formation_mode == FormationMode.REGROUPING:
		return FormationMode.OPEN if _formation_all_settled() else FormationMode.REGROUPING
	return FormationMode.OPEN

func _update_formation_status() -> void:
	if not has_army():
		formation_count_value = 0
		return
	var count := 0
	var max_lag := 0
	var unknown := 0
	var guards := 0
	var runners := 0
	var side := Vector2i(-_formation_heading.y, _formation_heading.x)
	var min_side := 1 << 29
	var max_side := -(1 << 29)
	var min_front := 1 << 29
	var max_front := -(1 << 29)
	for index: int in range(SOLDIER_COUNT):
		var phase_complete := not _passage_active
		if _passage_active and _unit_passage_phase.size() == SOLDIER_COUNT:
			phase_complete = _formation_march_active or _unit_passage_phase[index] == PassagePhase.RALLY or _unit_passage_phase[index] == PassagePhase.EXEMPT
		if index > 0 and phase_complete and desired_cells[index] != INVALID_CELL and cells[index] == desired_cells[index] and movement_state[index] != UnitState.MOVING and movement_state[index] != UnitState.SWAPPING:
			count += 1
		var distance := _activity_distance(index)
		unknown += int(distance < 0)
		max_lag = maxi(max_lag, distance)
		runners += int(locomotion_mode[index] == Locomotion.RUN)
		var offset := cells[index] - cells[0]
		var actual_forward := offset.x * _formation_heading.x + offset.y * _formation_heading.y
		var assigned_offset := desired_cells[index] - desired_cells[0]
		if index > 0 and actual_forward > 0 and assigned_offset.x * _formation_heading.x + assigned_offset.y * _formation_heading.y > 0 \
			and _formation_slot_cells.has(cells[index]) and data.height_levels[data.index(cells[index])] == data.height_levels[data.index(cells[0])]:
			guards += 1
		var lateral := offset.x * side.x + offset.y * side.y
		min_side = mini(min_side, lateral)
		max_side = maxi(max_side, lateral)
		min_front = mini(min_front, actual_forward)
		max_front = maxi(max_front, actual_forward)
	formation_cohesion = {"lag": max_lag, "unknown": unknown, "guards": guards, "runners": runners, "width": max_side - min_side + 1, "length": max_front - min_front + 1}
	formation_count_value = count
	if _pending_command >= 0:
		command_status = "DRAIN | old corridor is clearing; latest command queued"
		return
	if _command_goal_pending or _passage_plan_pending or _formation_target_pending:
		command_status = "PLANNING | bounded route, passage and formation analysis"
		return
	if _passage_active and not _passage_failure_reason.is_empty():
		command_status = "%s | available=%d required=100" % [_passage_failure_reason, _passage_available_capacity]
		return
	var external_wait := _passage_external_blocker()
	if external_wait != INVALID_CELL:
		command_status = "WAIT_EXTERNAL | blocked cell %s" % external_wait
		return
	if _formation_march_active:
		_formation_lagging = max_lag > 1 or unknown > 0
		var activity := "MARCH_TOGETHER" if _formation_step_direction != Vector2i.ZERO else "HOLD_FOR_REAR"
		if _formation_final_reform:
			activity = "LOCAL_REFORM"
		if is_formation_complete():
			activity = "FORMATION_AT_GOAL"
		command_status = "%s | front goal %s | guide %s | local settled %d/99 | legal lag %d (unknown %d)" % [activity, _march_goal, _formation_anchor_cell, count, max_lag, unknown]
		return
	if _passage_active:
		command_status = "LOCAL_PASSAGE / RECEIVING | group %d-%d | local settled %d/99 | legal lag %d (unknown %d)" % [_passage_group_start + 1, _passage_group_end + 1, count, max_lag, unknown]
		return
	if max_lag > FORMATION_MAX_LAG:
		_formation_lagging = true
	elif max_lag <= FORMATION_RECOVER_LAG:
		_formation_lagging = false
	if formation_mode == FormationMode.REGROUPING and _formation_all_settled():
		formation_mode = FormationMode.OPEN
		_formation_width = FORMATION_COLUMNS
	if command == Command.MOVE_TO_EDGE and captain_at_boundary():
		if is_formation_complete():
			command_status = "CAPTAIN_AT_BOUNDARY | formation assembled 99/99"
		else:
			command_status = "CAPTAIN_AT_BOUNDARY | gathering %d/99" % formation_count_value
	elif command == Command.FOLLOW_PLAYER:
		if formation_count_value < SOLDIER_COUNT - 1:
			command_status = "Following PLAYER | gathering %d/99" % formation_count_value
		else:
			command_status = "Following PLAYER | formation assembled 99/99"

func _update_formation_targets(force: bool = false) -> void:
	if _formation_target_pending or _command_goal_pending or _passage_plan_pending:
		return
	# The passage already owns its published targets. The fixed tick refreshes
	# the summary after movement; an unchanged target check must not scan the
	# 100-person body twice more through the builder and its completion hook.
	if (_formation_march_active or _passage_active) and not force:
		return
	_formation_target_pending = true
	var revision := _structure_revision
	await _build_formation_targets(force, revision)
	if revision == _structure_revision:
		_formation_target_pending = false
		_update_formation_status()

func _build_formation_targets(force: bool, revision: int) -> void:
	if not has_army() or data == null:
		return
	if _command_goal_pending or _passage_plan_pending:
		return
	# A published passage owns the final slot set and per-unit phase goals.
	# Ordinary formation replanning must not replace those slots with the
	# captain's short trail or make a waiting entrance unit look assembled.
	if _passage_active and not _formation_march_active:
		_update_formation_status()
		return
	# NONE is also used by deterministic movement fixtures and by the short
	# post-deploy idle window. Do not silently replace explicit slots until a
	# live command owns the formation again.
	if not force and command == Command.NONE:
		_update_formation_status()
		return
	# A validated edge-side rally owns its published slots after settlement.
	# Do not let the ordinary OPEN planner rebuild a second slot set on the next
	# tick; command changes clear the settled flag before planning resumes.
	if not force and command == Command.MOVE_TO_EDGE and captain_at_boundary() and _exit_rally_settled:
		_update_formation_status()
		return
	if not force and command == Command.FOLLOW_PLAYER and cells[0] == desired_cells[0] and _exit_rally_settled:
		# A completed passage owns its validated exit slots until the player
		# actually changes the follow target. Do not let the narrow route width
		# trigger an ordinary OPEN/COMPRESSING replan on the next tick.
		_update_formation_status()
		return
	var anchor := _formation_anchor_cell if command != Command.NONE else cells[0]
	var heading := _captain_heading()
	var initial_layout: Array[Vector2i] = []
	var initial_compact := false
	if _passage_active and force:
		var approach := _passage_march_field()
		var protected := _passage_route_protected_cells()
		initial_layout = await _passage_rally_layout(approach, protected, anchor + heading * 4, revision, heading)
		if initial_layout.size() != SOLDIER_COUNT:
			_formation_march_active = false
			_publish_passage_group_targets()
			return
		var initial_min := 1 << 29
		var initial_max := -(1 << 29)
		for slot: Vector2i in initial_layout:
			var forward := slot.x * heading.x + slot.y * heading.y
			initial_min = mini(initial_min, forward)
			initial_max = maxi(initial_max, forward)
		if initial_max - initial_min >= FORMATION_COLUMNS or absi(initial_layout[0].x - anchor.x) + absi(initial_layout[0].y - anchor.y) > FORMATION_REFORM_DISTANCE:
			# A narrow terrace may fit its first rectangle far from the deployed
			# body. Reuse the existing connected-layout builder near the actual
			# soldiers before asking all 100 to travel backwards just to line up.
			var average := Vector2.ZERO
			for cell: Vector2i in cells:
				average += Vector2(cell)
			average /= float(SOLDIER_COUNT)
			var start := cells[0]
			for cell: Vector2i in cells:
				if Vector2(cell).distance_squared_to(average) < Vector2(start).distance_squared_to(average):
					start = cell
			var nearby := await _compact_rally_layout(approach, protected, start, heading, revision)
			var old_spread := 0.0
			var nearby_spread := 0.0
			for slot: Vector2i in initial_layout:
				old_spread += Vector2(slot).distance_squared_to(average)
			for slot: Vector2i in nearby:
				nearby_spread += Vector2(slot).distance_squared_to(average)
			if nearby.size() == SOLDIER_COUNT and nearby_spread < old_spread:
				initial_layout = nearby
				initial_compact = true
		anchor = initial_layout[0]
	var height := int(data.height_levels[data.index(anchor)])
	var moved_far := _formation_anchor_cell == INVALID_CELL or absi(anchor.x - _formation_anchor_cell.x) + absi(anchor.y - _formation_anchor_cell.y) >= FORMATION_REPLAN_DISTANCE
	var height_changed := _formation_anchor_height != height
	var previous_mode := formation_mode
	var heading_changed := heading != _formation_heading
	var marching := command != Command.NONE and not _exit_rally_settled
	var mode := FormationMode.OPEN if marching else _desired_formation_mode()
	if marching:
		_formation_width = FORMATION_COLUMNS
		_formation_has_bottleneck = false
		desired_cells[0] = anchor
	if not force and not moved_far and not height_changed and heading == _formation_heading and mode == formation_mode:
		_update_formation_status()
		return
	_formation_anchor_cell = anchor
	_formation_heading = heading
	_formation_anchor_height = height
	formation_mode = mode
	# Reachability is invariant while the command's terrain field is live.
	# Moving its origin at every anchor would repeat an entire map flood.
	_formation_slot_cells.resize(SOLDIER_COUNT)
	_formation_slot_cells[0] = anchor
	if initial_compact:
		_assign_local_formation_layout(initial_layout)
		_formation_march_active = marching
		_update_formation_status()
		return
	# Do not carry stationary deployment offsets into a live command or across a
	# route heading change: they can place a follower on a future captain-route
	# cell. Once the route has a stable heading, preserving relative slots avoids
	# needless identity churn.
	var preserve_open_offsets := mode == FormationMode.OPEN and previous_mode == FormationMode.OPEN \
		and _formation_offsets.size() == SOLDIER_COUNT and not heading_changed \
		and (command == Command.NONE or _formation_march_active) and initial_layout.is_empty()
	var used := {anchor: true}
	# Reserve the captain's published destination as well as his current cell.
	# Without this, a follower can claim the edge/leader goal before the captain
	# arrives and turn a valid route into a self-blocking formation target.
	if data.contains(desired_cells[0]):
		used[desired_cells[0]] = true
	var slot_targets: Array[Vector2i] = []
	slot_targets.resize(SOLDIER_COUNT)
	slot_targets[0] = anchor
	for slot_index: int in range(1, SOLDIER_COUNT):
		if not await _take_structure_expansion(revision):
			return
		var preferred := anchor + _formation_offsets[slot_index] if preserve_open_offsets else _formation_preferred_cell(slot_index, anchor, heading)
		if marching and not preserve_open_offsets:
			# The captain occupies row 5 / column 5 of the same 100-cell body.
			var body_slot := slot_index - 1
			if body_slot >= 44:
				body_slot += 1
			preferred = anchor + heading * (4 - floori(float(body_slot) / 10.0)) + Vector2i(-heading.y, heading.x) * (body_slot % 10 - 4)
			if not initial_layout.is_empty():
				preferred = initial_layout[slot_index]
		var target := INVALID_CELL
		if data.contains(preferred) and data.is_walkable(preferred) and not used.has(preferred) and not _is_external_cell(preferred):
			target = preferred
		else:
			target = await _nearest_walkable(preferred, used, revision)
		if target == INVALID_CELL:
			# Keep the data contract explicit. A duplicate fallback would make a
			# visually plausible but physically impossible formation.
			target = await _find_unused_reachable_cell(used, revision)
		if target == INVALID_CELL:
			slot_targets[slot_index] = INVALID_CELL
			continue
		slot_targets[slot_index] = target
		used[target] = true
	# At a command or width transition, preserve the existing body of the
	# formation by pairing nearby soldiers with nearby slots. During ordinary
	# straight travel slot identity remains stable, so soldiers do not churn.
	if preserve_open_offsets:
		# These targets were generated from each unit's own relative offset.
		# Re-matching against old absolute cells pins the front ranks in place
		# and sends the rear ranks through them whenever the anchor translates.
		for index: int in range(1, SOLDIER_COUNT):
			desired_cells[index] = slot_targets[index]
			_formation_slot_cells[index] = slot_targets[index]
	elif force or mode != previous_mode or heading_changed:
		var available: Array[int] = []
		for index: int in range(1, SOLDIER_COUNT):
			available.append(index)
		if mode == FormationMode.OPEN:
			# Pair lanes in spatial order, then pair front-to-back inside each
			# lane. Slot-by-slot nearest matching creates crossing permutations
			# through the packed body when a command changes heading.
			var side := Vector2i(-heading.y, heading.x)
			available.sort_custom(func(a: int, b: int) -> bool:
				var sa := cells[a].x * side.x + cells[a].y * side.y
				var sb := cells[b].x * side.x + cells[b].y * side.y
				return sa < sb if sa != sb else a < b)
			var ordered_slots: Array[Vector2i] = slot_targets.slice(1)
			ordered_slots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				var sa := a.x * side.x + a.y * side.y
				var sb := b.x * side.x + b.y * side.y
				return sa < sb if sa != sb else a.x * heading.x + a.y * heading.y > b.x * heading.x + b.y * heading.y)
			var lane_start := 0
			while lane_start < ordered_slots.size():
				var lane_end := lane_start + 1
				while lane_end < ordered_slots.size() and Vector2(ordered_slots[lane_end]).dot(Vector2(side)) == Vector2(ordered_slots[lane_start]).dot(Vector2(side)):
					lane_end += 1
				var lane_units: Array[int] = available.slice(lane_start, lane_end)
				lane_units.sort_custom(func(a: int, b: int) -> bool:
					var da := cells[a].x * heading.x + cells[a].y * heading.y
					var db := cells[b].x * heading.x + cells[b].y * heading.y
					return da > db if da != db else a < b)
				for lane_index: int in range(lane_units.size()):
					var unit := lane_units[lane_index]
					desired_cells[unit] = ordered_slots[lane_start + lane_index]
					_formation_slot_cells[unit] = desired_cells[unit]
				lane_start = lane_end
		elif mode == FormationMode.COLUMN and _formation_has_bottleneck:
			# Match the existing body to the nearest trail slot first. This keeps
			# the queue locally coherent while the captain crosses the passage.
			for available_position: int in range(available.size()):
				var candidate_index: int = available[available_position]
				var best_slot := -1
				var best_distance := 1 << 30
				for slot_index: int in range(1, SOLDIER_COUNT):
					var slot_target: Vector2i = slot_targets[slot_index]
					if slot_target == INVALID_CELL:
						continue
					var distance := absi(cells[candidate_index].x - slot_target.x) + absi(cells[candidate_index].y - slot_target.y)
					if distance < best_distance or (distance == best_distance and (best_slot < 0 or slot_index < best_slot)):
						best_slot = slot_index
						best_distance = distance
				if best_slot >= 0:
					desired_cells[candidate_index] = slot_targets[best_slot]
					_formation_slot_cells[candidate_index] = slot_targets[best_slot]
					slot_targets[best_slot] = INVALID_CELL
		else:
			for slot_index: int in range(1, SOLDIER_COUNT):
				var slot_target: Vector2i = slot_targets[slot_index]
				if slot_target == INVALID_CELL or available.is_empty():
					continue
				var best_position := 0
				var best_distance := 1 << 30
				for candidate_position: int in range(available.size()):
					var candidate_index: int = available[candidate_position]
					var distance := absi(cells[candidate_index].x - slot_target.x) + absi(cells[candidate_index].y - slot_target.y)
					if cells[candidate_index] == slot_target:
						best_position = candidate_position
						best_distance = 0
						break
					if distance < best_distance or (distance == best_distance and candidate_index < available[best_position]):
						best_position = candidate_position
						best_distance = distance
				var assigned_index: int = available[best_position]
				available.remove_at(best_position)
				desired_cells[assigned_index] = slot_target
				_formation_slot_cells[assigned_index] = slot_target
	else:
		if mode == FormationMode.COLUMN and _formation_has_bottleneck and _assign_bottleneck_queue_targets(slot_targets):
			_update_formation_status()
			return
		# Keep the unit-to-slot assignment stable while a column is moving
		# through a pass. Reassigning slot_targets[index] on every captain step
		# creates permutation cycles (a soldier can be asked to occupy a slot
		# already held by a unit farther down the column), which looks like a
		# deadlock even though every individual edge is legal. Match each unit's
		# previously published slot to the nearest new slot once per replan.
		var available_slots: Array[int] = []
		for slot_index: int in range(1, SOLDIER_COUNT):
			if slot_targets[slot_index] != INVALID_CELL:
				available_slots.append(slot_index)
		for index: int in range(1, SOLDIER_COUNT):
			if available_slots.is_empty():
				desired_cells[index] = INVALID_CELL
				_formation_slot_cells[index] = INVALID_CELL
				continue
			var previous_slot := cells[index]
			if _formation_slot_cells.size() == SOLDIER_COUNT and _formation_slot_cells[index] != INVALID_CELL:
				previous_slot = _formation_slot_cells[index]
			var best_position := 0
			var best_distance := 1 << 30
			for available_slot_position: int in range(available_slots.size()):
				var slot_index: int = available_slots[available_slot_position]
				var target: Vector2i = slot_targets[slot_index]
				var distance := absi(previous_slot.x - target.x) + absi(previous_slot.y - target.y)
				if distance < best_distance or (distance == best_distance and slot_index < available_slots[best_position]):
					best_position = available_slot_position
					best_distance = distance
			var assigned_slot: int = available_slots[best_position]
			available_slots.remove_at(best_position)
			desired_cells[index] = slot_targets[assigned_slot]
			_formation_slot_cells[index] = slot_targets[assigned_slot]
	if mode == FormationMode.OPEN and not preserve_open_offsets:
		_formation_offsets.resize(SOLDIER_COUNT)
		_formation_offsets[0] = Vector2i.ZERO
		for index: int in range(1, SOLDIER_COUNT):
			_formation_offsets[index] = desired_cells[index] - anchor if desired_cells[index] != INVALID_CELL else Vector2i.ZERO
	_formation_march_active = marching
	_update_formation_status()

func _formation_front_at_goal() -> bool:
	if _passage_active:
		if _passage_group_start < _passage_descriptors.size() or _formation_anchor_cell != _passage_final_captain_slot:
			return false
		for index: int in range(1, SOLDIER_COUNT):
			if not _passage_final_slots.has(desired_cells[index]):
				return false
		return true
	var front_offset := 0
	for offset: Vector2i in _formation_offsets:
		front_offset = maxi(front_offset, offset.x * _formation_heading.x + offset.y * _formation_heading.y)
	var goal_offset := _march_goal - _formation_anchor_cell
	return _march_goal != INVALID_CELL and _formation_slot_cells.has(_march_goal) \
		and goal_offset.x * _formation_heading.x + goal_offset.y * _formation_heading.y == front_offset

func _begin_formation_step(direction: Vector2i, participants: Array[int] = []) -> bool:
	return _start_formation_batch(direction, participants, false)

func _append_formation_batch(direction: Vector2i, participants: Array[int]) -> bool:
	return _start_formation_batch(direction, participants, true)

func _start_formation_batch(direction: Vector2i, participants: Array[int], append: bool) -> bool:
	# One same-direction, flat-footprint transaction. Claims and interpolation
	# are the ordinary movement fields; only the commit boundary is collective.
	if not _formation_march_active or direction not in TerrainData.DIRECTIONS \
		or not _pending_pushes.is_empty():
		return false
	if append:
		if not _formation_bend_active or _formation_step_units.is_empty() or moving_count() != _formation_step_units.size() \
			or move_progress[_formation_step_units[0]] > 0.0 or _reserved_cells.size() != _formation_step_units.size():
			return false
		for claim: Vector2i in _reserved_cells:
			if int(_reserved_cells[claim]) not in _formation_step_units:
				return false
	elif moving_count() > 0 or not _reserved_cells.is_empty():
		return false
	var units: Array[int] = participants.duplicate()
	if units.is_empty():
		for index: int in range(SOLDIER_COUNT):
			units.append(index)
	elif not _formation_bend_active:
		return false
	var included := {}
	for index: int in units:
		if index < 0 or index >= SOLDIER_COUNT or included.has(index):
			return false
		included[index] = true
	for index: int in units:
		var source := cells[index]
		var destination := source + direction
		var expected := destination if _formation_bend_active else source
		if expected != desired_cells[index] or _push_lock[index] != 0 or _cell_owners.get(source, -1) != index \
			or moving_to[index] != INVALID_CELL or _reserved_cells.has(source) or _reserved_cells.has(destination) \
			or not data.can_step(source, destination) or _is_external_cell(destination):
			return false
		if data.height_levels[data.index(source)] != data.height_levels[data.index(destination)]:
			return false
		if _passage_active and (_passage_cell_is_protected(destination) or not _passage_march_field().has(destination)):
			return false
		var occupant := int(_cell_owners.get(destination, -1))
		if occupant >= 0 and (not included.has(occupant) or cells[occupant] != destination):
			return false
	if not append:
		_formation_step_direction = direction
		_formation_step_units.clear()
		_formation_step_batches.clear()
	_formation_step_units.append_array(units)
	_formation_step_batches.append({"direction": direction, "units": units})
	for index: int in units:
		var destination := cells[index] + direction
		desired_cells[index] = destination
		_formation_slot_cells[index] = destination
		_reserved_cells[destination] = index
		moving_to[index] = destination
		move_progress[index] = 0.0
		move_duration[index] = MOVE_DURATION
		movement_state[index] = UnitState.MOVING
		locomotion_mode[index] = Locomotion.WALK
		blocked_time[index] = 0.0
		facing[index] = direction
	_visual_dirty = true
	return true

func _complete_formation_batch(batch: Dictionary) -> bool:
	var direction: Vector2i = batch.direction
	var units: Array[int] = batch.units
	for index: int in units:
		var destination := moving_to[index]
		if _cell_owners.get(cells[index], -1) != index or destination != cells[index] + direction \
			or not data.can_step(cells[index], destination) or _reserved_cells.get(destination, -1) != index \
			or _is_external_cell(destination) or data.height_levels[data.index(cells[index])] != data.height_levels[data.index(destination)]:
			_movement_contract_error("formation batch", index, cells[index], destination)
			return false
		var occupant := int(_cell_owners.get(destination, -1))
		if occupant >= 0 and (occupant not in units or cells[occupant] != destination or moving_to[occupant] != destination + direction):
			_movement_contract_error("formation batch destination", index, cells[index], destination)
			return false
	for index: int in units:
		_cell_owners.erase(cells[index])
	for index: int in units:
		var source := cells[index]
		var destination := moving_to[index]
		cells[index] = destination
		_cell_owners[destination] = index
		_clear_reservation(destination, index)
		moving_to[index] = INVALID_CELL
		move_progress[index] = 0.0
		movement_state[index] = UnitState.IDLE
		locomotion_mode[index] = Locomotion.IDLE
		_record_passage_commit(index, source, destination)
		_consume_follower_route_step(index, destination)
		_completed_steps += 1
	return true

func _complete_formation_step() -> void:
	# Independent transactions commit separately in their proven order. No
	# batch can consume an occupied source or a claim from another batch.
	for batch: Dictionary in _formation_step_batches:
		if not _complete_formation_batch(batch):
			return
	if _formation_bend_active:
		formation_bend_steps += 1
		# Complete the fixed local intent before evaluating another turn. A
		# sideways batch can open a vacancy for the following direction; dropping
		# that second half permitted a repeated sideways/backwards oscillation.
		var finished := true
		for index: int in range(SOLDIER_COUNT):
			finished = finished and desired_cells[index] == cells[index]
		if finished:
			_formation_anchor_cell = cells[0]
			_formation_bend_active = false
			if not _formation_bend_preview.is_empty():
				if _formation_bend_preview.sources != cells:
					push_error("formation preview source mismatch")
					return
				_publish_bend_intent(_formation_bend_preview.targets, _formation_bend_preview.order)
				_formation_bend_followup = _formation_bend_preview.followup
				_formation_bend_preview.clear()
			elif not _formation_bend_followup.is_empty():
				_publish_bend_intent(_formation_bend_followup)
				_formation_bend_followup.clear()
	else:
		_formation_anchor_cell += _formation_step_direction
		if _path_route_cursor < _path_route.size() and _path_route[_path_route_cursor] == _formation_anchor_cell:
			_path_route_cursor += 1
		formation_batch_steps += 1
	_captain_trail.append(cells[0])
	_captain_trail_progress_cache.clear()
	_formation_step_direction = Vector2i.ZERO
	_formation_step_units.clear()
	_formation_step_batches.clear()
	_visual_dirty = true

func _advance_formation_march() -> bool:
	if not _formation_march_active or _pending_command >= 0 or (not _passage_active and _formation_front_at_goal()):
		return false
	if _passage_active:
		if moving_count() > 0 or not _pending_pushes.is_empty() or not _reserved_cells.is_empty():
			return false
		if _formation_bend_active:
			return _begin_bend_subset()
		for index: int in range(SOLDIER_COUNT):
			if cells[index] != desired_cells[index]:
				return false
		_formation_bend_active = false
		if _formation_final_reform:
			_formation_anchor_cell = cells[0]
			return false
		if _formation_guide_group != _passage_group_start:
			_formation_target_pending = true
			_build_formation_guide(_structure_revision)
			return false
		if _path_route_cursor < _path_route.size():
			var next_direction := _path_route[_path_route_cursor] - _formation_anchor_cell
			if _begin_formation_step(next_direction):
				_formation_heading = next_direction
				return true
			return false
		if _passage_group_start < _passage_descriptors.size():
			var approach: Dictionary = _passage_descriptor(_passage_group_start).get("approach_component", {})
			var at_mouth := false
			for cell: Vector2i in cells:
				# The point entry can lie just beyond the last full-body shape.
				# Two proven legal approach edges are local, not a distant scout leg.
				if int(approach.get(cell, 1 << 29)) <= 2:
					at_mouth = true
					break
			if at_mouth:
				_begin_passage_group()
			else:
				# After a local bend, try the immediate full-body downhill edge.
				# Do not repeat a whole-platform footprint search for every cell.
				var field := _passage_march_field()
				for direction: Vector2i in TerrainData.DIRECTIONS:
					if _formation_bend_span == 0 and _formation_bend_field.is_empty() and int(field.get(_formation_anchor_cell + direction, -2)) == int(field.get(_formation_anchor_cell, -1)) - 1 \
						and _begin_formation_step(direction):
						_formation_heading = direction
						return true
				_formation_target_pending = true
				_bend_formation_step(_structure_revision)
		else:
			_publish_final_formation_targets()
		return false
	if _path_route_cursor >= _path_route.size():
		return false
	var direction := _path_route[_path_route_cursor] - _formation_anchor_cell
	if _begin_formation_step(direction):
		_formation_heading = direction
		return true
	return false

func _publish_final_formation_targets(max_local_lag: int = 1) -> void:
	# The whole body has approached as far as its present footprint permits.
	# Only this local, idle boundary may reshape it to the immutable final set.
	if _formation_final_reform or _passage_final_slots.size() != SOLDIER_COUNT - 1:
		return
	if not _final_reform_ready(cells, max_local_lag):
		_formation_target_pending = true
		if _passage_descriptors.is_empty() and _formation_bend_field.is_empty():
			_reform_narrow_march(_structure_revision)
		else:
			_bend_formation_step(_structure_revision)
		return
	var layout: Array[Vector2i] = [_passage_final_captain_slot]
	layout.append_array(_passage_final_slots)
	# A last local sideways step is not the final formation's facing. Publish
	# the immutable route's final heading together with these final offsets.
	_formation_heading = _path_route_snapshot[-1] - _path_route_snapshot[-2]
	_assign_local_formation_layout(layout)
	_formation_final_reform = true
	_passage_group_end = -1
	# The final set is now authoritative. The earlier narrow bend ribbon can
	# omit a legal wing slot; keeping it would reject its local vacancy chain.
	_formation_bend_field.clear()
	_formation_bend_lateral.clear()
	_formation_bend_span = 0

func _final_reform_ready(body: Array[Vector2i], max_local_lag: int = 1) -> bool:
	var captain_field: Dictionary = _formation_final_fields.get("goal_component", {})
	if _passage_group_start < _passage_descriptors.size() or int(captain_field.get(body[0], 1 << 29)) > FORMATION_REFORM_DISTANCE:
		return false
	var slots_field: Dictionary = _formation_final_fields.get("goal_slot_component", {})
	for cell: Vector2i in body:
		if int(slots_field.get(cell, 1 << 29)) > max_local_lag:
			return false
	return true

func _assign_local_formation_layout(layout: Array[Vector2i]) -> void:
	var available := layout.slice(1)
	desired_cells[0] = layout[0]
	_formation_slot_cells[0] = desired_cells[0]
	# Preserve identities already on a final slot, then match only the remainder.
	var remaining: Array[int] = []
	for index: int in range(1, SOLDIER_COUNT):
		if available.has(cells[index]):
			desired_cells[index] = cells[index]
			available.erase(cells[index])
		else:
			remaining.append(index)
	for index: int in remaining:
		var nearest := 0
		for position: int in range(1, available.size()):
			if cells[index].distance_squared_to(available[position]) < cells[index].distance_squared_to(available[nearest]):
				nearest = position
		desired_cells[index] = available[nearest]
		available.remove_at(nearest)
	for index: int in range(SOLDIER_COUNT):
		_formation_slot_cells[index] = desired_cells[index]
		_formation_offsets[index] = desired_cells[index] - layout[0]
		_clear_follower_route(index)
	_passage_binding_revision += 1

func _begin_bend_subset() -> bool:
	var started := false
	for direction: Vector2i in _formation_bend_order:
		var participants: Array[int] = []
		for index: int in range(SOLDIER_COUNT):
			if desired_cells[index] == cells[index] + direction:
				participants.append(index)
		if participants.is_empty():
			continue
		var accepted := _append_formation_batch(direction, participants) if started else _begin_formation_step(direction, participants)
		if not accepted:
			break
		started = true
	if started and _formation_bend_followup.is_empty() and not _formation_bend_field.is_empty() and not _formation_target_pending:
		var complete_intent := true
		var near_mouth := false
		var approach: Dictionary = _passage_descriptor(_passage_group_start).get("approach_component", {})
		for index: int in range(SOLDIER_COUNT):
			complete_intent = complete_intent and (cells[index] == desired_cells[index] or moving_to[index] == desired_cells[index])
			near_mouth = near_mouth or int(approach.get(desired_cells[index], 1 << 29)) <= 2
		if _passage_group_start >= _passage_descriptors.size():
			near_mouth = _final_reform_ready(desired_cells)
		if complete_intent and not near_mouth:
			# Read-only planning overlaps the current WALK. Publish only after
			# these exact physical sources have committed, never mid-transaction.
			_formation_target_pending = true
			_bend_formation_step(_structure_revision, desired_cells.duplicate())
	return started

func _bend_formation_step(revision: int, prospective_sources: Array[Vector2i] = []) -> void:
	var sources: Array[Vector2i] = cells.duplicate() if prospective_sources.is_empty() else prospective_sources
	# Evaluate four coherent one-edge shears, not a different shortest-path
	# direction for every member. Interleaved UP/RIGHT intents made a staircase
	# of single-unit dependencies even though a whole rank could move together.
	var field := _passage_march_field()
	if _formation_bend_field.is_empty() and _passage_group_start >= _passage_descriptors.size():
		# At the last platform the fixed front rank, not a one-cell guide tip,
		# defines protection. Its existing legal distance field includes the
		# final wings without inventing a narrow centre-line ribbon through them.
		_formation_bend_field = field.duplicate()
	if _formation_bend_field.is_empty():
		# Pick ONE branch around an obstacle. A goal-distance flood alone sends
		# front and rear ranks around opposite halves of a ring at its watershed.
		# Project onto the nearest cell of this shared legal route. Lateral
		# distance is NOT progress: adding it funnels every rank onto one lane.
		var route: Array[Vector2i] = [sources[0]]
		while int(field.get(route.back(), 0)) > 0:
			if not await _take_structure_expansion(revision):
				return
			var current: Vector2i = route.back()
			var next := INVALID_CELL
			for direction: Vector2i in TerrainData.DIRECTIONS:
				if field.get(current + direction, -2) == int(field[current]) - 1 and data.can_step(current, current + direction):
					next = current + direction
					break
			if next == INVALID_CELL:
				break
			route.append(next)
		var rear_extent := 0
		for cell: Vector2i in sources:
			var offset := cell - sources[0]
			rear_extent = maxi(rear_extent, -offset.x * _formation_heading.x - offset.y * _formation_heading.y)
		for _rear: int in range(rear_extent):
			var next := route[0] - _formation_heading
			if not field.has(next) or not data.can_step(next, route[0]) or _passage_cell_is_protected(next):
				break
			route.push_front(next)
		var ribbon := {}
		var lateral := {}
		var frontier: Array[Vector2i] = route.duplicate()
		for position: int in range(route.size()):
			ribbon[route[position]] = route.size() - position - 1
			lateral[route[position]] = 0
		var head := 0
		while head < frontier.size():
			if not await _take_structure_expansion(revision):
				return
			var current := frontier[head]
			head += 1
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next := current + direction
				if field.has(next) and not ribbon.has(next) and data.can_step(current, next):
					ribbon[next] = int(ribbon[current])
					lateral[next] = int(lateral[current]) + 1
					frontier.append(next)
		var side_limit := 0
		for cell: Vector2i in sources:
			side_limit = maxi(side_limit, int(lateral[cell]))
		for cell: Vector2i in ribbon.keys():
			if int(lateral[cell]) > side_limit + 1:
				ribbon.erase(cell)
		# The ribbon chooses the same side of the obstacle for the whole body.
		# Its projection labels are NOT travel distances: near a bend they can
		# collapse a remote tail onto the captain's depth. Flood legal edges in
		# that fixed corridor once, so rear progress cannot disappear on rebase.
		var distances := {route.back(): 0}
		frontier = [route.back()]
		head = 0
		while head < frontier.size():
			if not await _take_structure_expansion(revision):
				return
			var current := frontier[head]
			head += 1
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next := current + direction
				if ribbon.has(next) and not distances.has(next) and data.can_step(current, next):
					distances[next] = int(distances[current]) + 1
					frontier.append(next)
		_formation_bend_field = distances
		_formation_bend_lateral = lateral
		field = distances
	var farthest := 0
	var nearest := 1 << 29
	for cell: Vector2i in sources:
		farthest = maxi(farthest, int(field[cell]))
		nearest = mini(nearest, int(field[cell]))
	if _formation_bend_span == 0:
		# Fix the permitted guide span once per platform. Recomputing it from
		# each newly stretched shape would let the front ratchet away forever.
		var width := FORMATION_COLUMNS
		var cursor := sources[0]
		while int(field.get(cursor, 0)) > 3:
			if not await _take_structure_expansion(revision):
				return
			var next := INVALID_CELL
			for step: Vector2i in TerrainData.DIRECTIONS:
				if field.get(cursor + step, -2) == int(field[cursor]) - 1 and data.can_step(cursor, cursor + step):
					next = cursor + step
					break
			if next == INVALID_CELL:
				break
			width = mini(width, _route_edge_width(cursor, next, FORMATION_COLUMNS))
			cursor = next
		_formation_bend_span = maxi(farthest - nearest + 2, ceili(float(SOLDIER_COUNT) / maxi(1, width)) + width * 2)
	var best: Array[Vector2i] = []
	var followup: Array[Vector2i] = []
	var best_progress := 0
	var body_neighbors := {}
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var targets := await _bend_candidate(sources, direction, false, field, body_neighbors, revision)
		if revision != _structure_revision:
			return
		if targets.is_empty():
			continue
		var progress := _bend_progress(sources, targets, field)
		if progress > best_progress:
			best = targets
			best_progress = progress
	var advancing_members := 0
	for index: int in range(best.size()):
		advancing_members += int(best[index] != sources[index])
	var direct_progress := best_progress
	if advancing_members < FORMATION_COLUMNS:
		# Only local vacancy chains that unblock another downhill member can
		# justify a temporary retreat. Test at most twelve, with one fixed
		# forward followup; never move unrelated uphill rows with the chain.
		# Also compare them with a tiny remaining step: sending one rear soldier
		# through an entire row before freeing the turn is progress, but strands
		# the other 99 for many avoidable movement cycles.
		var source_owners := {}
		for index: int in range(SOLDIER_COUNT):
			source_owners[sources[index]] = index
		var detours: Array[Dictionary] = []
		for direction: Vector2i in TerrainData.DIRECTIONS:
			for index: int in range(SOLDIER_COUNT):
				var next := sources[index] + direction
				if not field.has(next) or source_owners.has(next) or not data.can_step(sources[index], next):
					continue
				var members: Array[int] = [index]
				var cursor := sources[index] - direction
				while source_owners.has(cursor) and data.can_step(cursor, cursor + direction):
					members.append(source_owners[cursor])
					cursor -= direction
				var vacancy := sources[members.back()]
				var demand := 0
				for incoming: Vector2i in TerrainData.DIRECTIONS:
					var neighbor := vacancy + incoming
					if source_owners.has(neighbor) and source_owners[neighbor] not in members and data.can_step(neighbor, vacancy) and int(field[neighbor]) > int(field[vacancy]):
						demand += 1
				if demand > 0:
					detours.append({"direction": direction, "members": members, "demand": demand, "depth": int(field[vacancy])})
		detours.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.demand != b.demand:
				return a.demand > b.demand
			return a.members.size() < b.members.size() if a.members.size() != b.members.size() else a.depth > b.depth)
		# If a legal direct step already exists, spend only a small part of
		# the shared budget looking for a better two-edge turn. The full twelve
		# alternatives are reserved for a body with no direct progress at all.
		for detour: Dictionary in detours.slice(0, 12 if best.is_empty() else 4):
			var frozen := {}
			for index: int in range(SOLDIER_COUNT):
				if index not in detour.members:
					frozen[index] = true
			var first := await _bend_candidate(sources, detour.direction, false, field, body_neighbors, revision, frozen, {}, false)
			if revision != _structure_revision:
				return
			if first.is_empty() or first == sources:
				continue
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var second := await _bend_candidate(first, direction, false, field, body_neighbors, revision)
				if revision != _structure_revision:
					return
				if second.is_empty():
					continue
				var progress := _bend_progress(sources, second, field)
				if progress > best_progress and progress > direct_progress * 2:
					best = first
					followup = second
					best_progress = progress
					# Compare two committed edges with two direct steps. Once the
					# first bounded alternative beats that rate, serve it instead of
					# spending many idle frames exhaustively ranking similar chains.
					break
			if not followup.is_empty():
				break
	if best.size() == SOLDIER_COUNT:
		var batch_order: Array[Vector2i] = []
		var frozen := {}
		var blocked := {}
		for index: int in range(SOLDIER_COUNT):
			if best[index] != sources[index]:
				var direction := best[index] - sources[index]
				if direction not in batch_order:
					batch_order.append(direction)
				frozen[index] = true
				blocked[sources[index]] = true
				blocked[best[index]] = true
		if followup.is_empty():
			for direction: Vector2i in TerrainData.DIRECTIONS:
				if direction in batch_order:
					continue
				# Independent portions of a curved body can walk at the same
				# time. Neither their source nor destination can touch another
				# batch, and every ordered intermediate body is checked separately.
				var combined := await _bend_candidate(best, direction, false, field, body_neighbors, revision, frozen, blocked)
				if revision != _structure_revision:
					return
				if combined.is_empty() or _bend_progress(best, combined, field) <= 0:
					continue
				for index: int in range(SOLDIER_COUNT):
					if combined[index] != best[index]:
						frozen[index] = true
						blocked[best[index]] = true
						blocked[combined[index]] = true
				best = combined
				batch_order.append(direction)
		if moving_count() > 0:
			_formation_bend_preview = {"sources": sources, "targets": best, "order": batch_order, "followup": followup}
		elif cells == sources:
			_publish_bend_intent(best, batch_order)
			_formation_bend_followup = followup
		else:
			push_error("formation planner source mismatch")
	elif _final_reform_ready(sources, FORMATION_REFORM_DISTANCE):
		# Continue safe collective movement as far as the whole body permits,
		# rather than switching to serial slot pushes six cells too early. A
		# prospective stop is published only after its in-flight sources commit.
		if moving_count() == 0 and cells == sources:
			_publish_final_formation_targets(FORMATION_REFORM_DISTANCE)
	else:
		_passage_failure_reason = "LOCAL_FORMATION_TURN_UNAVAILABLE span=%d minmax=%s captain_distance=%d" % [_formation_bend_span, str([nearest, farthest]), int(field[sources[0]])]
	_formation_target_pending = false
	_update_formation_status()

func _publish_bend_intent(targets: Array[Vector2i], batch_order: Array[Vector2i] = []) -> void:
	_formation_bend_order = batch_order.duplicate()
	for index: int in range(SOLDIER_COUNT):
		var direction := targets[index] - cells[index]
		if direction != Vector2i.ZERO and direction not in _formation_bend_order:
			_formation_bend_order.append(direction)
		desired_cells[index] = targets[index]
		_formation_slot_cells[index] = targets[index]
		_formation_offsets[index] = targets[index] - targets[0]
		_clear_follower_route(index)
	_formation_anchor_cell = targets[0]
	_formation_guide_group = _passage_group_start
	_path_route.clear()
	_path_route_cursor = 0
	_formation_bend_active = true
	_passage_binding_revision += 1

func _bend_progress(sources: Array[Vector2i], targets: Array[Vector2i], field: Dictionary) -> int:
	var progress := 0
	for index: int in range(SOLDIER_COUNT):
		progress += _bend_cell_potential(sources[index], field, index) - _bend_cell_potential(targets[index], field, index)
	return progress

func _bend_cell_potential(cell: Vector2i, field: Dictionary, index: int) -> int:
	# Lateral closeness to the guide is not forward travel. Keep real legal
	# distances for span/protection, but do not funnel every rank onto its lane.
	if _passage_group_start >= _passage_descriptors.size():
		var target_field: Dictionary = _formation_final_fields.get("goal_component" if index == 0 else "goal_slot_component", {})
		var distance := int(target_field.get(cell, field[cell]))
		# Fill the fixed set away from its entrance, including lateral wings.
		# A point-front tie score pinned occupied rows beside empty side slots.
		return distance * distance * (SOLDIER_COUNT * 2 + 1) - int(_passage_final_component.get(cell, 0))
	var distance := maxi(0, int(field[cell]) - int(_formation_bend_lateral.get(cell, 0)))
	return distance * distance * (SOLDIER_COUNT * 2 + 1) + int(_formation_bend_lateral.get(cell, 0))

func _bend_candidate(sources: Array[Vector2i], direction: Vector2i, downhill_only: bool, field: Dictionary, neighbors: Dictionary, revision: int, frozen: Dictionary = {}, blocked: Dictionary = {}, positive_chains: bool = true) -> Array[Vector2i]:
	var targets: Array[Vector2i] = sources.duplicate()
	var occupied := {}
	var source_owners := {}
	var order: Array[int] = []
	for index: int in range(SOLDIER_COUNT):
		occupied[sources[index]] = index
		source_owners[sources[index]] = index
		if not frozen.has(index):
			order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		var front_a := sources[a].x * direction.x + sources[a].y * direction.y
		var front_b := sources[b].x * direction.x + sources[b].y * direction.y
		# Geometry, not which soldier was bound to a receiving slot, decides
		# which equal-length bridge chain stays behind at a bend.
		return front_a > front_b if front_a != front_b else (sources[a].y < sources[b].y if sources[a].y != sources[b].y else sources[a].x < sources[b].x))
	for index: int in order:
		if not await _take_structure_expansion(revision):
			return []
		var source := sources[index]
		var next := source + direction
		if not field.has(next) or occupied.has(next) or blocked.has(next) or _passage_cell_is_protected(next) or _is_external_cell(next) \
			or not data.can_step(source, next) or data.height_levels[data.index(source)] != data.height_levels[data.index(next)]:
			continue
		if downhill_only and int(field[next]) > int(field[source]):
			continue
		targets[index] = next
		occupied.erase(source)
		occupied[next] = index
	if not downhill_only and positive_chains:
		# Score independent same-direction vacancy chains, not all lateral
		# movers on the platform together. One uphill vacancy can release two
		# downhill members in its row; unrelated uphill rows need not move.
		var chain_for := {}
		var chains := {}
		var gains := {}
		for index: int in order:
			if targets[index] == sources[index]:
				continue
			var ahead := int(source_owners.get(targets[index], -1))
			var chain := int(chain_for.get(ahead, index))
			chain_for[index] = chain
			if not chains.has(chain):
				chains[chain] = []
				gains[chain] = 0
			chains[chain].append(index)
			gains[chain] += _bend_cell_potential(sources[index], field, index) - _bend_cell_potential(targets[index], field, index)
		for chain: int in chains:
			if int(gains[chain]) <= 0:
				for index: int in chains[chain]:
					targets[index] = sources[index]
		occupied.clear()
		for index: int in range(SOLDIER_COUNT):
			occupied[targets[index]] = index
	var connected := await _repair_bend_body(sources, targets, occupied, order, field, neighbors, revision)
	if revision != _structure_revision or connected.size() != SOLDIER_COUNT:
		return []
	var nearest := 1 << 29
	var farthest := 0
	var guards := 0
	var rear := 0
	for index: int in range(SOLDIER_COUNT):
		var depth := int(field[targets[index]])
		nearest = mini(nearest, depth)
		farthest = maxi(farthest, depth)
		guards += int(index > 0 and depth < int(field[targets[0]]))
		rear += int(index > 0 and depth > int(field[targets[0]]))
	if guards >= 20 and guards <= 70 and rear >= 20 and farthest - nearest <= _formation_bend_span:
		return targets
	return []

func _repair_bend_body(sources: Array[Vector2i], targets: Array[Vector2i], occupied: Dictionary, order: Array[int], field: Dictionary, body_neighbors: Dictionary, revision: int) -> Dictionary:
	var connected := {}
	for _repair: int in range(SOLDIER_COUNT):
		if not await _take_structure_expansion(revision):
			return {}
		connected = await _bend_body_component(targets, occupied, body_neighbors, revision)
		if revision != _structure_revision:
			return {}
		var target_far := 0
		var target_near := 1 << 29
		var target_guards := 0
		var target_rear := 0
		for target: Vector2i in targets:
			target_far = maxi(target_far, int(field[target]))
			target_near = mini(target_near, int(field[target]))
			if target != targets[0]:
				target_guards += int(int(field[target]) < int(field[targets[0]]))
				target_rear += int(int(field[target]) > int(field[targets[0]]))
		if connected.size() == SOLDIER_COUNT and target_far - target_near <= _formation_bend_span and target_guards >= 20 and target_guards <= 70 and target_rear >= 20:
			break
		var undo := {}
		# Hold departing bridges as well as detached movers. The tail may
		# stay still while a front move would create its first excessive gap.
		var tail_neighbors := {}
		for target: Vector2i in targets:
			if connected.has(target):
				continue
			if not body_neighbors.has(target):
				body_neighbors[target] = _bend_body_neighbors(target)
			for neighbor: Vector2i in body_neighbors[target]:
				tail_neighbors[neighbor] = true
		var bridge := -1
		var bridge_cost := SOLDIER_COUNT + 1
		for index: int in order:
			if targets[index] == sources[index] or not tail_neighbors.has(sources[index]):
				continue
			if not body_neighbors.has(sources[index]):
				body_neighbors[sources[index]] = _bend_body_neighbors(sources[index])
			for neighbor: Vector2i in body_neighbors[sources[index]]:
				if connected.has(neighbor):
					var held := {index: true}
					var cursor := index
					while occupied.has(sources[cursor]) and not held.has(occupied[sources[cursor]]):
						cursor = int(occupied[sources[cursor]])
						held[cursor] = true
					if held.size() < bridge_cost:
						bridge = index
						bridge_cost = held.size()
					break
		if bridge >= 0:
			# Hold the smallest departing bridge chain, then recompute. Holding
			# every possible bridge at once also pinned otherwise free turn lanes.
			undo[bridge] = true
		if connected.size() < SOLDIER_COUNT and undo.is_empty():
			# No departing bridge can reconnect this proposal. Only then undo
			# detached movers; freezing them first also froze the whole rear.
			for index: int in order:
				if targets[index] != sources[index] and not connected.has(targets[index]):
					undo[index] = true
		if (target_guards < 20 or target_guards > 70) and targets[0] != sources[0]:
			undo[0] = true
		for index: int in order:
			# Measure the simultaneous destination body, not the old tail.
			# Otherwise a full column at its span bound cannot move even
			# when front and rear would both advance in the same transaction.
			if int(field[targets[index]]) < target_far - _formation_bend_span and targets[index] != sources[index]:
				undo[index] = true
			if index > 0 and target_guards > 70 and int(field[sources[index]]) >= int(field[targets[0]]) and int(field[targets[index]]) < int(field[targets[0]]):
				undo[index] = true
				target_guards -= 1
			# Hold only the ranks that would remove the last front/rear
			# protection. Other columns can still vacate the captain's turn.
			if index > 0 and target_rear < 20 and int(field[sources[index]]) > int(field[targets[0]]) and int(field[targets[index]]) <= int(field[targets[0]]):
				undo[index] = true
				target_rear += 1
			if index > 0 and target_guards < 20 and int(field[sources[index]]) < int(field[targets[0]]) and int(field[targets[index]]) >= int(field[targets[0]]):
				undo[index] = true
				target_guards += 1
		for index: int in order:
			if undo.has(index) and occupied.has(sources[index]):
				undo[int(occupied[sources[index]])] = true
		var removed := 0
		for position: int in range(order.size() - 1, -1, -1):
			var index := order[position]
			if not undo.has(index) or targets[index] == sources[index]:
				continue
			occupied.erase(targets[index])
			targets[index] = sources[index]
			occupied[targets[index]] = index
			removed += 1
		if removed == 0:
			break
	return connected


func _bend_body_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var middle := cell + direction
		if not data.can_step(cell, middle):
			continue
		result.append(middle)
		for second: Vector2i in TerrainData.DIRECTIONS:
			var next := middle + second
			if data.can_step(middle, next):
				result.append(next)
	return result

func _bend_body_component(targets: Array[Vector2i], occupied: Dictionary, neighbors: Dictionary, revision: int) -> Dictionary:
	# Transient body connectivity, not a second terrain/navigation field.
	# One empty legal cell is allowed between members while rounding a corner.
	var connected := {targets[0]: true}
	var queue: Array[Vector2i] = [targets[0]]
	var head := 0
	while head < queue.size():
		if not await _take_structure_expansion(revision):
			return {}
		var source := queue[head]
		head += 1
		if not neighbors.has(source):
			neighbors[source] = _bend_body_neighbors(source)
		for next: Vector2i in neighbors[source]:
			if occupied.has(next) and not connected.has(next):
				connected[next] = true
				queue.append(next)
	return connected


func _reform_narrow_march(revision: int) -> void:
	# A real 3..9-wide straight corridor can carry a narrower whole body.
	# Do not reshape an open final platform merely because its slots differ.
	var field: Dictionary = _formation_final_fields.get("goal_component", {})
	var protected := _passage_route_protected_cells()
	var heading := _formation_heading
	var cursor := _formation_anchor_cell
	var width := FORMATION_COLUMNS
	for step: int in range(FORMATION_COLUMNS * 2):
		var next := INVALID_CELL
		for direction: Vector2i in TerrainData.DIRECTIONS:
			if field.get(cursor + direction, -2) == int(field.get(cursor, -1)) - 1 and data.can_step(cursor, cursor + direction):
				next = cursor + direction
				break
		if next == INVALID_CELL:
			break
		if step == 0:
			heading = next - cursor
		width = mini(width, _route_edge_width(cursor, next, FORMATION_COLUMNS - 1))
		cursor = next
	var selected: Array[Vector2i] = []
	if width > PASSAGE_MAX_NARROW_WIDTH and width < mini(FORMATION_COLUMNS, int(formation_cohesion.width)):
		var nearby := await _flood_passage_component(_formation_anchor_cell, protected, revision, FORMATION_REFORM_DISTANCE)
		for candidate_width: int in range(width, PASSAGE_MAX_NARROW_WIDTH, -1):
			var front_rows := floori(float(ceili(float(SOLDIER_COUNT) / float(candidate_width)) - 1) / 2.0)
			selected = await _passage_rally_rectangle(field, protected, _formation_anchor_cell + heading * front_rows, revision, heading, candidate_width, false, nearby)
			if selected.size() == SOLDIER_COUNT:
				break
	if revision != _structure_revision:
		return
	if selected.size() == SOLDIER_COUNT:
		_assign_local_formation_layout(selected)
		_formation_anchor_cell = selected[0]
		_formation_heading = heading
		_formation_guide_group = -1
		_formation_target_pending = false
		_update_formation_status()
	else:
		await _bend_formation_step(revision)

func _build_formation_guide(revision: int) -> void:
	# One shared footprint search per platform; reuse the consumable guide,
	# keeping the immutable all-gate snapshot intact. No per-soldier search.
	var field := _passage_march_field()
	var final_reform_radius := FORMATION_REFORM_DISTANCE
	if _passage_group_start >= _passage_descriptors.size():
		# This search moves the centre of the complete footprint. The front's
		# boundary cell cannot be a centre, so searching until that distance is
		# zero needlessly exhausts the whole final platform before any move.
		field = _formation_final_fields.get("goal_component", field)
		var same_footprint := true
		for offset: Vector2i in _formation_offsets:
			var slot := _passage_final_captain_slot + offset
			if slot != _passage_final_captain_slot and not _passage_final_slots.has(slot):
				same_footprint = false
				break
		if same_footprint:
			final_reform_radius = 0
	var start := _formation_anchor_cell
	var best := start
	var previous := {start: INVALID_CELL}
	var frontier: Array[Vector4i] = [Vector4i(data.index(start), 0, int(field.get(start, 0)), 0)]
	var costs := {start: 0}
	var sequence := 1
	var mouth: Vector2i = _passage_descriptor(_passage_group_start).get("entry", INVALID_CELL)
	while not frontier.is_empty():
		var item := _frontier_pop(frontier)
		var center := Vector2i(item.x % data.size.x, floori(float(item.x) / data.size.x))
		if int(field.get(center, 1 << 29)) < int(field.get(best, 1 << 29)):
			best = center
		if field.get(best, -1) == 0:
			break
		if _passage_group_start >= _passage_descriptors.size() \
			and int(field.get(best, 1 << 29)) <= final_reform_radius:
			# A different final footprint can require local reform even when its
			# centre cannot accept the incoming rectangle. Stop at the existing
			# reform radius; the whole-body readiness check still owns publication.
			break
		var at_mouth := false
		for direction: Vector2i in TerrainData.DIRECTIONS:
			if _formation_offsets.has(mouth - center - direction) and data.can_step(mouth - direction, mouth):
				at_mouth = true
		if at_mouth:
			best = center
			break
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := center + direction
			if previous.has(next) or not field.has(next):
				continue
			var legal := true
			for offset: Vector2i in _formation_offsets:
				if not await _take_structure_expansion(revision):
					return
				var source := center + offset
				var destination := next + offset
				if not field.has(destination) or _passage_cell_is_protected(destination) or _is_external_cell(destination) \
					or not data.can_step(source, destination) or data.height_levels[data.index(source)] != data.height_levels[data.index(destination)]:
					legal = false
					break
			if legal:
				previous[next] = center
				costs[next] = int(costs[center]) + 1
				_frontier_push(frontier, Vector4i(data.index(next), int(costs[next]), int(field[next]), sequence))
				sequence += 1
	if revision != _structure_revision:
		return
	_path_route.clear()
	var route_cell := best
	while route_cell != start:
		_path_route.push_front(route_cell)
		route_cell = previous[route_cell]
	_path_route_cursor = 0
	_formation_guide_group = _passage_group_start
	_formation_target_pending = false
	_update_formation_status()

func _captain_should_wait() -> bool:
	# EDGE is a leader-led travel command. The captain must not deadlock at a
	# broad platform while the initial deployment patch is re-forming; the
	# bottleneck state below still serializes the group when width is limited.
	# FOLLOW has the same requirement: the player goal is the leader's command
	# anchor, not a barrier that can be held forever by a rear-rank slot. The old
	# lag gate stopped the captain on an empty cell once formation reassignment
	# made the body lagging, leaving every remaining follower waiting behind a
	# goal that could no longer move.
	if command == Command.FOLLOW_PLAYER:
		return false
	if command == Command.NONE or command == Command.MOVE_TO_EDGE or not _formation_lagging or formation_mode == FormationMode.COLUMN:
		return false
	if _path_route_cursor >= _path_route.size():
		return false
	var next := _path_route[_path_route_cursor]
	var current_height := int(data.height_levels[data.index(cells[0])])
	var next_height := int(data.height_levels[data.index(next)])
	if current_height != next_height:
		return false
	return _walkable_degree(cells[0]) >= 3

func _take_local_search(unit_index: int) -> bool:
	if _local_path_requests_remaining <= 0 or int(_local_search_tick.get(unit_index, -1)) == _passage_tick:
		return false
	_local_path_requests_remaining -= 1
	_local_search_tick[unit_index] = _passage_tick
	_local_path_cursor = unit_index % (SOLDIER_COUNT - 1) + 1
	return true

func _frontier_less(a: Vector4i, b: Vector4i) -> bool:
	var a_score := a.y + a.z
	var b_score := b.y + b.z
	if a_score != b_score:
		return a_score < b_score
	return a.z < b.z if a.z != b.z else a.w < b.w

func _frontier_push(heap: Array[Vector4i], item: Vector4i) -> void:
	# GDScript has no priority queue; this bounded heap replaces the per-node
	# linear scan, without changing the four-request/1024-expansion contract.
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) >> 1
		if not _frontier_less(heap[index], heap[parent]):
			break
		var value := heap[parent]
		heap[parent] = heap[index]
		heap[index] = value
		index = parent

func _frontier_pop(heap: Array[Vector4i]) -> Vector4i:
	var first := heap[0]
	var last: Vector4i = heap.pop_back()
	if heap.is_empty():
		return first
	heap[0] = last
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and _frontier_less(heap[child + 1], heap[child]):
			child += 1
		if not _frontier_less(heap[child], heap[index]):
			break
		var value := heap[index]
		heap[index] = heap[child]
		heap[child] = value
		index = child
	return first

func _find_local_route(start: Vector2i, goal: Vector2i, expansion_limit: int = 256, allow_occupied: bool = false, moving_index: int = -1) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if data == null or not data.contains(start) or not data.contains(goal) or start == goal:
		return empty
	if moving_index >= 0 and not _take_local_search(moving_index):
		return empty
	expansion_limit = mini(expansion_limit, LOCAL_PATH_EXPANSIONS)
	var pending: Array[Vector4i] = [Vector4i(data.index(start), 0, absi(start.x - goal.x) + absi(start.y - goal.y), 0)]
	var sequence := 1
	var previous := {start: INVALID_CELL}
	var costs := {start: 0}
	var closed := {}
	var head := 0
	var found := false
	while not pending.is_empty() and head < expansion_limit:
		var item := _frontier_pop(pending)
		var current := Vector2i(item.x % data.size.x, floori(float(item.x) / data.size.x))
		head += 1
		if closed.has(current) or item.y != int(costs[current]):
			continue
		closed[current] = true
		if current == goal:
			found = true
			break
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			var next_cost := int(costs[current]) + 1
			if closed.has(next) or (previous.has(next) and int(costs[next]) <= next_cost) or not data.contains(next) or not data.can_step(current, next):
				continue
			if moving_index > 0 and current == start and not _push_preserves_open_slots(current, next):
				continue
			if _is_external_cell(next) and next != goal:
				continue
			if _reserved_cells.has(next) and int(_reserved_cells[next]) != moving_index:
				continue
			if _cell_owners.has(next) and next != goal and not allow_occupied:
				continue
			var heuristic := absi(next.x - goal.x) + absi(next.y - goal.y)
			_frontier_push(pending, Vector4i(data.index(next), next_cost, heuristic, sequence))
			sequence += 1
			previous[next] = current
			costs[next] = next_cost
	local_search_expansions += head
	max_local_search_expansions = maxi(max_local_search_expansions, head)
	if not found and not previous.has(goal):
		return empty
	var route: Array[Vector2i] = []
	var cursor := goal
	while cursor != INVALID_CELL:
		route.push_front(cursor)
		cursor = previous.get(cursor, INVALID_CELL)
	return route

func _local_step_toward(start: Vector2i, goal: Vector2i, expansion_limit: int = 256, allow_occupied: bool = false, moving_index: int = -1) -> Vector2i:
	var route := _find_local_route(start, goal, expansion_limit, allow_occupied, moving_index)
	return route[1] if route.size() > 1 else INVALID_CELL

func _clear_follower_route(index: int) -> void:
	_follower_routes.erase(index)
	_follower_route_goals.erase(index)
	_follower_route_cursors.erase(index)
	_follower_route_allows_occupied.erase(index)

func _follower_route_step(start: Vector2i, goal: Vector2i, index: int) -> Vector2i:
	if index < 0 or index >= SOLDIER_COUNT:
		return INVALID_CELL
	var route: Array = _follower_routes.get(index, [])
	var cursor := int(_follower_route_cursors.get(index, 0))
	var stored_goal: Vector2i = _follower_route_goals.get(index, INVALID_CELL)
	if stored_goal != goal or route.size() < 2 or cursor < 1 or cursor >= route.size() or route[cursor - 1] != start:
		_clear_follower_route(index)
		return INVALID_CELL
	if not _push_preserves_open_slots(start, route[cursor]):
		_clear_follower_route(index)
		return INVALID_CELL
	return route[cursor]

func _start_follower_route(start: Vector2i, goal: Vector2i, index: int, expansion_limit: int, allow_occupied: bool = false) -> Vector2i:
	var route := _find_local_route(start, goal, expansion_limit, allow_occupied, index)
	if route.size() < 2:
		_clear_follower_route(index)
		return INVALID_CELL
	_follower_routes[index] = route
	_follower_route_goals[index] = goal
	_follower_route_cursors[index] = 1
	_follower_route_allows_occupied[index] = allow_occupied
	return route[1]

func _consume_follower_route_step(index: int, cell: Vector2i) -> void:
	var route: Array = _follower_routes.get(index, [])
	var cursor := int(_follower_route_cursors.get(index, 0))
	if route.size() < 2 or cursor < 1 or cursor >= route.size() or route[cursor] != cell:
		return
	cursor += 1
	if cursor >= route.size():
		_clear_follower_route(index)
	else:
		_follower_route_cursors[index] = cursor

func _follower_navigation_goal(start: Vector2i, goal: Vector2i) -> Vector2i:
	# A follower must reach the next captain-trail height transition before it
	# can make progress toward a slot on another plateau. Steering directly at a
	# far-side slot makes Manhattan movement press against a cliff forever.
	if data == null or not data.contains(start) or not data.contains(goal) or _captain_trail.size() < 2:
		return goal
	var start_height := int(data.height_levels[data.index(start)])
	var goal_height := int(data.height_levels[data.index(goal)])
	if start_height == goal_height:
		return goal
	var best := INVALID_CELL
	var best_distance := 1 << 30
	for trail_index: int in range(_captain_trail.size() - 1):
		var trail_cell: Vector2i = _captain_trail[trail_index]
		var next_trail_cell: Vector2i = _captain_trail[trail_index + 1]
		if not data.contains(trail_cell) or not data.contains(next_trail_cell):
			continue
		if int(data.height_levels[data.index(trail_cell)]) != start_height:
			continue
		if int(data.height_levels[data.index(next_trail_cell)]) == start_height:
			continue
		if trail_cell == start:
			# The follower is standing on the ramp's source cell. Its next legal
			# step is the captain-trail transition itself, not a detour back onto
			# the already-cleared plateau.
			return next_trail_cell
		var distance := absi(start.x - trail_cell.x) + absi(start.y - trail_cell.y)
		if distance < best_distance:
			best = trail_cell
			best_distance = distance
	return best if best != INVALID_CELL else goal


func _next_follower_step(start: Vector2i, goal: Vector2i, moving_index: int) -> Vector2i:
	if _passage_active and not _formation_march_active and moving_index >= 0:
		return _next_passage_step(moving_index)
	var navigation_goal := _follower_navigation_goal(start, goal)
	# Once a follower has paid for a local search, consume that route in order.
	# Do not fall back to Manhattan after the first detour step; that was the
	# source of legal U-turns at walls and repeated two-cell oscillations.
	var published_step := _follower_route_step(start, navigation_goal, moving_index)
	if published_step != INVALID_CELL:
		if not _cell_owners.has(published_step) or bool(_follower_route_allows_occupied.get(moving_index, false)):
			return published_step
		# A cached free route is not permission to push a new occupant. Replan
		# around it using the same paid request as any other blocked free route.
		_clear_follower_route(moving_index)
	var directions: Array[Vector2i] = []
	var delta := navigation_goal - start
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		directions.append(Vector2i(signi(delta.x), 0))
		if delta.y != 0:
			directions.append(Vector2i(0, signi(delta.y)))
	else:
		if delta.y != 0:
			directions.append(Vector2i(0, signi(delta.y)))
		if delta.x != 0:
			directions.append(Vector2i(signi(delta.x), 0))
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if direction not in directions:
			directions.append(direction)
	var current_goal_distance := absi(navigation_goal.x - start.x) + absi(navigation_goal.y - start.y)
	var best := INVALID_CELL
	var best_goal_distance := 1 << 30
	var best_field_distance := 1 << 30
	var blocked_best := INVALID_CELL
	var blocked_goal_distance := 1 << 30
	for direction: Vector2i in directions:
		var candidate := start + direction
		if not data.can_step(start, candidate) or _is_external_cell(candidate) or (_reserved_cells.has(candidate) and int(_reserved_cells[candidate]) != moving_index):
			continue
		if not _push_preserves_open_slots(start, candidate):
			continue
		var candidate_goal_distance := absi(navigation_goal.x - candidate.x) + absi(navigation_goal.y - candidate.y)
		var goal_progress := candidate_goal_distance < current_goal_distance
		if _cell_owners.has(candidate):
			var occupant := int(_cell_owners[candidate])
			var swap_requested := _can_follower_swap(moving_index, occupant) and _follower_swap_requested(moving_index, occupant)
			if not swap_requested:
				# Return the best legal occupied step to the fixed-tick scheduler.
				# The scheduler can then build a push chain. Dropping the occupied
				# candidate here made a follower wait forever at a one-cell pass.
				# Pushes are a passage contract, not a general open-field formation
				# operation. In an open rank, an occupied greedy step is normally a
				# transient slot permutation; returning it as a push request makes the
				# flat formation shove settled soldiers out of their ranks.
				if goal_progress and candidate_goal_distance < blocked_goal_distance:
					blocked_best = candidate
					blocked_goal_distance = candidate_goal_distance
				continue
		if not goal_progress:
			continue
		var candidate_field_distance := _distance_to_cell(candidate)
		# Followers normally solve their own slot, not the captain's position.
		# The shared field is only a bounded fallback when a legal local detour
		# is needed; it must never make a settled rear rank walk toward the front.
		if candidate_goal_distance < best_goal_distance or (candidate_goal_distance == best_goal_distance and candidate_field_distance < best_field_distance):
			best = candidate
			best_goal_distance = candidate_goal_distance
			best_field_distance = candidate_field_distance
	if best != INVALID_CELL:
		return best
	# A packed open formation can have no route made solely of free cells even
	# though an occupied-cell corridor leads to the target. Once a unit has
	# waited for a real planning window, publish that bounded route and let the
	# common blocker transaction move its occupants. The old rotating-window
	# gate could deny the last ranks forever after the first few units consumed
	# the four local searches.
	if blocked_time[moving_index] >= SIM_STEP * 3.0 and _local_path_requests_remaining > 0:
		var use_occupied: bool = _local_occupied_retry.get(moving_index, INVALID_CELL) == navigation_goal
		var detour := _start_follower_route(start, navigation_goal, moving_index, LOCAL_PATH_EXPANSIONS, use_occupied)
		if detour != INVALID_CELL:
			_local_occupied_retry.erase(moving_index)
			return detour
		if int(_local_search_tick.get(moving_index, -1)) == _passage_tick:
			_local_occupied_retry[moving_index] = INVALID_CELL if use_occupied else navigation_goal
	if blocked_best != INVALID_CELL:
		# A packed deployment or a one-cell ramp can temporarily have every
		# greedy step occupied. Before asking the push transaction to move a
		# whole chain, give this follower a bounded free-cell detour. This is
		# still grid-authoritative and never crosses a cliff; it simply uses the
		# open cells around the queue to prevent a permanent jam.
		return blocked_best
	if _local_path_requests_remaining <= 0 or blocked_time[moving_index] < SIM_STEP * 3.0:
		return INVALID_CELL
	return INVALID_CELL

func _passage_descriptor(index: int) -> Dictionary:
	if index < 0 or index >= _passage_descriptors.size():
		return {}
	return _passage_descriptors[index]

func _next_rally_group_end(start: int) -> int:
	for passage_index: int in range(start, _passage_descriptors.size()):
		if _passage_descriptors[passage_index].get("rally_layout", []).size() == SOLDIER_COUNT:
			return passage_index
	return _passage_descriptors.size() - 1

func _active_rally_slots() -> Array:
	if _formation_march_active:
		return _formation_slot_cells
	return _passage_descriptor(_passage_group_end).get("rally_slots", _passage_final_slots)

func _active_rally_component() -> Dictionary:
	return _passage_descriptor(_passage_group_end).get("rally_component", _passage_final_component)

func _active_rally_routes() -> Dictionary:
	return _passage_descriptor(_passage_group_end).get("rally_routes", _passage_final_routes)

func _unit_has_cleared_group(index: int) -> bool:
	if index < 0 or index >= SOLDIER_COUNT or _unit_completed_exits.size() != SOLDIER_COUNT:
		return false
	var group_end := _passage_group_end if _passage_group_end >= 0 else _passage_descriptors.size() - 1
	return _unit_completed_exits[index] > group_end and _unit_passage_exit_clear[index] != 0

func _publish_passage_group_targets() -> void:
	var layout: Array = _passage_descriptor(_passage_group_end).get("rally_layout", [])
	if layout.size() != SOLDIER_COUNT:
		return
	# Keep twenty real receiving guards first, then fill both halves from the
	# far side of the outlet. Filling every near front slot before any rear slot
	# can seal a bent terrace's only route to its rear half.
	var descriptor := _passage_descriptor(_passage_group_end)
	var component: Dictionary = descriptor.rally_component
	var heading: Vector2i = descriptor.rally_heading
	var captain: Vector2i = layout[0]
	var ordered: Array = layout.slice(1)
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return int(component[a]) > int(component[b]) if component[a] != component[b] else (a.y < b.y if a.y != b.y else a.x < b.x))
	var guards: Array = []
	for slot: Vector2i in ordered:
		var offset := slot - captain
		if guards.size() < 20 and offset.x * heading.x + offset.y * heading.y > 0:
			guards.append(slot)
	for slot: Vector2i in guards:
		ordered.erase(slot)
	layout = [captain] + guards + ordered
	descriptor.rally_layout = layout
	for index: int in range(SOLDIER_COUNT):
		var ticket := int(_unit_passage_ticket[index])
		var position := 0 if index == 0 else 1 + ticket - int(ticket > _unit_passage_ticket[0])
		desired_cells[index] = layout[position]
		_formation_slot_cells[index] = desired_cells[index]
		_clear_follower_route(index)
	_passage_binding_revision += 1

func _passage_captain_ticket(group_end: int) -> int:
	var descriptor := _passage_descriptor(group_end)
	var layout: Array = descriptor.get("rally_layout", [])
	if layout.size() != SOLDIER_COUNT:
		return 40
	var heading: Vector2i = descriptor.rally_heading
	var guards := 0
	for slot: Vector2i in layout:
		var offset := slot - Vector2i(layout[0])
		guards += int(offset.x * heading.x + offset.y * heading.y > 0)
	return guards

func _bind_receiving_arrival(index: int) -> void:
	if index <= 0 or int(_unit_passage[index]) != _passage_group_end:
		return
	var descriptor := _passage_descriptor(_passage_group_end)
	var layout: Array = descriptor.get("rally_layout", [])
	if layout.size() != SOLDIER_COUNT:
		return
	# Ready tickets need not arrive in numeric order. At this physical admission
	# boundary assign the earliest unused receiving position. The first twenty
	# positions are guards; swap only upstream targets not yet physically used.
	var old_goal := desired_cells[index]
	var bindings := {}
	for other: int in range(1, SOLDIER_COUNT):
		bindings[desired_cells[other]] = other
	for slot: Vector2i in layout.slice(1):
		if slot == old_goal:
			return
		var other := int(bindings.get(slot, -1))
		if other <= 0:
			continue
		if _unit_passage[other] != _passage_group_end or _unit_passage_phase[other] != PassagePhase.APPROACH \
			or _unit_passage_crossed[other] != 0:
			continue
		# Both receiving bindings are still future work: this unit has just
		# entered the core and the other is upstream. A different soldier may
		# transit either cell; keep that physical owner/claim untouched instead
		# of skipping the far slot and assigning it to the last arriving tail.
		desired_cells[index] = slot
		desired_cells[other] = old_goal
		_formation_slot_cells[index] = slot
		_formation_slot_cells[other] = old_goal
		_passage_binding_revision += 1
		return

func _begin_passage_group() -> void:
	# Called only after the complete open footprint has reached the mouth's
	# local restriction. Reorder ready ranks once, then keep those tickets.
	var approach: Dictionary = _passage_descriptor(_passage_group_start).get("approach_component", {})
	_passage_ticket_order.clear()
	for index: int in range(1, SOLDIER_COUNT):
		_ticket_insert(index, approach)
	# Admission order belongs to this physical approach body, not the future
	# receiving rectangle. Otherwise soldiers already ahead of the captain
	# receive rear tickets and must block the captain they are waiting for.
	_ticket_insert(0, approach)
	var physical_ticket := _passage_ticket_order.find(0)
	_passage_ticket_order.erase(0)
	# A point-distance tie can put a protected rectangular captain too early
	# in the queue. Keep the declared 21..71 admission bound, not a floor
	# derived from another rectangle on the opposite side of the passage.
	_passage_ticket_order.insert(clampi(physical_ticket, 20, 70), 0)
	for position: int in range(SOLDIER_COUNT):
		_unit_passage_ticket[_passage_ticket_order[position]] = position
	_formation_march_active = false
	_formation_has_bottleneck = true
	_formation_width = int(_passage_descriptor(_passage_group_start).get("width", 1))
	formation_mode = FormationMode.COLUMN
	_publish_passage_group_targets()

func _advance_passage_group() -> void:
	if not _passage_active or _formation_march_active or _passage_group_end < 0 \
		or _passage_group_start >= _passage_descriptors.size() \
		or moving_count() > 0 or not _pending_pushes.is_empty() or not _reserved_cells.is_empty():
		return
	var descriptor := _passage_descriptor(_passage_group_end)
	if descriptor.get("rally_layout", []).size() != SOLDIER_COUNT:
		return
	for index: int in range(SOLDIER_COUNT):
		if not _unit_has_cleared_group(index) or cells[index] != desired_cells[index] or _push_lock[index] != 0:
			return
	descriptor["rally_completed_tick"] = _passage_tick
	_passage_group_start = _passage_group_end + 1
	_formation_bend_span = 0
	_formation_bend_field.clear()
	_formation_bend_lateral.clear()
	_formation_bend_followup.clear()
	_formation_bend_preview.clear()
	_formation_bend_order.clear()
	if _passage_group_start < _passage_descriptors.size():
		_passage_group_end = _next_rally_group_end(_passage_group_start)
		for index: int in range(SOLDIER_COUNT):
			_unit_passage[index] = _passage_group_start
			_unit_passage_phase[index] = PassagePhase.APPROACH
			_unit_passage_crossed[index] = 0
			_unit_passage_exit_clear[index] = 0
			_unit_passage_cursor[index] = 0
	_formation_anchor_cell = cells[0]
	_formation_heading = descriptor.get("rally_heading", _formation_heading)
	for index: int in range(SOLDIER_COUNT):
		_formation_offsets[index] = desired_cells[index] - _formation_anchor_cell
		_clear_follower_route(index)
	_formation_march_active = true
	_formation_has_bottleneck = false
	_formation_width = FORMATION_COLUMNS
	formation_mode = FormationMode.OPEN
	_update_formation_status()

func _passage_march_field() -> Dictionary:
	if _formation_march_active and not _formation_bend_field.is_empty():
		return _formation_bend_field
	if _passage_group_start < _passage_descriptors.size():
		return _passage_descriptor(_passage_group_start).get("approach_component", {})
	return _formation_final_fields.get("front_component", _passage_final_component)

func _passage_order_hold(unit_index: int, passage_index: int) -> bool:
	if _unit_passage_ticket.size() != SOLDIER_COUNT or _unit_passage_ticket[0] < 0:
		return false
	var captain_ticket := int(_unit_passage_ticket[0])
	if unit_index == 0:
		for position: int in range(captain_ticket):
			var guard_index := _passage_ticket_order[position]
			if _unit_completed_exits[guard_index] <= passage_index \
				and not (_unit_passage[guard_index] == passage_index and _unit_passage_crossed[guard_index] != 0):
				return true
	elif _unit_passage_ticket[unit_index] > captain_ticket:
		return _unit_completed_exits[0] <= passage_index \
			and not (_unit_passage[0] == passage_index and _unit_passage_crossed[0] != 0)
	return false

func _passage_approach_floor(unit_index: int, passage_index: int) -> int:
	if not _passage_order_hold(unit_index, passage_index):
		return 0
	var approach: Dictionary = _passage_descriptor(passage_index).get("approach_component", {})
	var predecessors: Array[int] = [0]
	if unit_index == 0:
		predecessors = _passage_ticket_order.slice(0, int(_unit_passage_ticket[0]))
	var queue_floor := 0
	for predecessor: int in predecessors:
		if _unit_completed_exits[predecessor] > passage_index or (_unit_passage[predecessor] == passage_index and _unit_passage_crossed[predecessor] != 0):
			continue
		if not approach.has(cells[predecessor]):
			return 1 << 29
		queue_floor = maxi(queue_floor, int(approach[cells[predecessor]]) + 1)
	return queue_floor

func _passage_ready_for_entry(unit_index: int, passage_index: int) -> bool:
	if unit_index < 0 or passage_index < 0 or passage_index >= _passage_descriptors.size():
		return false
	if _passage_order_hold(unit_index, passage_index):
		return false
	var corridor: Array = _passage_descriptor(passage_index).get("corridor", [])
	if corridor.size() < 2:
		return false
	var first_core: Vector2i = corridor[1]
	if _cell_owners.has(first_core) or (_reserved_cells.has(first_core) and int(_reserved_cells[first_core]) != unit_index):
		return false
	var ticket := int(_unit_passage_ticket[unit_index]) if _unit_passage_ticket.size() == SOLDIER_COUNT else -1
	if ticket < 0:
		return false
	for order_position: int in range(ticket):
		var other := _passage_ticket_order[order_position]
		if other < 0 or other >= SOLDIER_COUNT or _unit_passage.size() != SOLDIER_COUNT:
			continue
		var other_passage := int(_unit_passage[other])
		if other_passage > passage_index:
			continue
		# Tickets order ready arrivals only. Once the first core is vacated,
		# a predecessor farther inside cannot monopolize an entire long corridor.
		if other_passage == passage_index and _unit_passage_phase[other] == PassagePhase.APPROACH \
			and cells[other] == _passage_descriptor(passage_index).get("entry", INVALID_CELL):
			return false
	return true

func _passage_step_is_free(cell: Vector2i, unit_index: int) -> bool:
	return data != null and data.contains(cell) and data.is_walkable(cell) and not _is_external_cell(cell) \
		and not _cell_owners.has(cell) and (not _reserved_cells.has(cell) or int(_reserved_cells[cell]) == unit_index)

func _passage_approach_topology_reachable(unit_index: int) -> bool:
	if unit_index < 0 or unit_index >= SOLDIER_COUNT or _unit_passage.size() != SOLDIER_COUNT:
		return false
	var passage_index := int(_unit_passage[unit_index])
	if passage_index < 0 or passage_index >= _passage_descriptors.size():
		return false
	var approach: Dictionary = _passage_descriptor(passage_index).get("approach_component", {})
	return approach.has(cells[unit_index])

func _passage_approach_must_wait(unit_index: int) -> bool:
	return not _passage_approach_topology_reachable(unit_index)

func _find_passage_route(start: Vector2i, goal: Vector2i, unit_index: int, allow_occupied: bool = false, ignore_reservations: bool = false) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if data == null or not data.contains(start) or not data.contains(goal) or start == goal:
		return empty
	if not _take_local_search(unit_index):
		return empty
	var blocked := _passage_route_protected_cells()
	blocked.erase(start)
	blocked.erase(goal)
	var has_final_edge := false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var predecessor := goal + direction
		if blocked.has(predecessor) or not data.can_step(predecessor, goal):
			continue
		if predecessor != start and (_is_external_cell(predecessor) \
			or (not allow_occupied and _cell_owners.has(predecessor)) \
			or (not ignore_reservations and _reserved_cells.has(predecessor) and int(_reserved_cells[predecessor]) != unit_index)):
			continue
		has_final_edge = true
		break
	# Occupied shared routes may include a future claim that clears before
	# arrival; only free-cell searches require an immediately usable final edge.
	if not has_final_edge and not allow_occupied:
		return empty
	var expansion_limit := PASSAGE_EGRESS_EXPANSIONS
	var platform_height := -1
	var final_egress_only := false
	var approach_component := {}
	var approach_depth_limit := 0
	if _passage_active and unit_index >= 0 and unit_index < SOLDIER_COUNT \
		and _unit_passage_phase.size() == SOLDIER_COUNT:
		var unit_phase := int(_unit_passage_phase[unit_index])
		var unit_passage_index := int(_unit_passage[unit_index])
		if unit_phase == PassagePhase.APPROACH:
			approach_component = _passage_descriptor(unit_passage_index).get("approach_component", {})
			approach_depth_limit = int(approach_component.get(start, 0)) + FORMATION_REFORM_DISTANCE
		final_egress_only = (unit_phase == PassagePhase.EXIT_CLEAR or unit_phase == PassagePhase.RALLY or unit_phase == PassagePhase.EXEMPT) \
			and unit_passage_index >= _passage_group_end
	if _passage_active and unit_index >= 0 and unit_index < SOLDIER_COUNT \
		and _unit_passage_phase.size() == SOLDIER_COUNT and _unit_passage_phase[unit_index] == PassagePhase.EXIT_CLEAR \
		and int(_unit_passage[unit_index]) < _passage_group_end:
		# Between gates remain on the cleared platform, within the original budget.
		platform_height = int(data.height_levels[data.index(start)])
	var field_expansions := 0
	var rally_component := _active_rally_component()
	if final_egress_only and rally_component.has(start) and rally_component.has(goal):
		# Recover a shortest exit-tree route directly from the shared terrain
		# field. Long ridge detours must not require every exiting unit to search
		# the same thousand cells again. This recovery is charged to this request.
		var reverse_route: Array[Vector2i] = [goal]
		var cursor := goal
		while cursor != start and field_expansions < expansion_limit:
			field_expansions += 1
			var depth := int(rally_component[cursor])
			if depth <= int(rally_component[start]):
				break
			var parent := INVALID_CELL
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var candidate := cursor + direction
				if rally_component.get(candidate, -2) == depth - 1 and data.can_step(candidate, cursor) and not blocked.has(candidate):
					parent = candidate
					break
			if parent == INVALID_CELL:
				break
			reverse_route.append(parent)
			cursor = parent
		if cursor == start:
			reverse_route.reverse()
			var usable := true
			for offset: int in range(1, reverse_route.size()):
				var next := reverse_route[offset]
				var inspect_transient := not allow_occupied or offset == 1
				if (offset == 1 and not _push_preserves_open_slots(start, next)) \
					or (inspect_transient and (next == cells[0] or _is_external_cell(next))) \
					or (inspect_transient and not ignore_reservations and _reserved_cells.has(next) and int(_reserved_cells[next]) != unit_index) \
					or (not allow_occupied and next != goal and _cell_owners.has(next)):
					usable = false
					break
			if usable:
				local_search_expansions += field_expansions
				max_local_search_expansions = maxi(max_local_search_expansions, field_expansions)
				max_passage_expansions = maxi(max_passage_expansions, field_expansions)
				return reverse_route
		expansion_limit -= field_expansions
	# A transient far-end claim does not invalidate the known occupied route
	# above. A new search, however, cannot reach a currently forbidden goal.
	# Charge any field recovery already attempted; never cache this as permanent.
	if _is_external_cell(goal) or (not ignore_reservations and _reserved_cells.has(goal) and int(_reserved_cells[goal]) != unit_index):
		local_search_expansions += field_expansions
		max_local_search_expansions = maxi(max_local_search_expansions, field_expansions)
		max_passage_expansions = maxi(max_passage_expansions, field_expansions)
		return empty
	var pending: Array[Vector4i] = [Vector4i(data.index(start), 0, absi(start.x - goal.x) + absi(start.y - goal.y), 0)]
	var sequence := 1
	var previous := {start: INVALID_CELL}
	var costs := {start: 0}
	var closed := {}
	var head := 0
	while not pending.is_empty() and head < expansion_limit:
		var item := _frontier_pop(pending)
		var current := Vector2i(item.x % data.size.x, floori(float(item.x) / data.size.x))
		head += 1
		if closed.has(current) or item.y != int(costs[current]):
			continue
		closed[current] = true
		if current == goal:
			break
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			var next_cost := int(costs[current]) + 1
			if closed.has(next) or (previous.has(next) and int(costs[next]) <= next_cost) or blocked.has(next) or not data.contains(next) or not data.can_step(current, next):
				continue
			if final_egress_only and next == cells[0] and next != goal:
				# The captain owns the boundary goal while the final rally is still
				# active. A follower must route around that cell, never queue into it
				# as an occupied intermediate waypoint.
				continue
			if final_egress_only and next != goal and not _passage_final_egress_cell(next):
				continue
			if not approach_component.is_empty() and (not approach_component.has(next) or int(approach_component[next]) > approach_depth_limit):
				continue
			if final_egress_only and not _push_preserves_open_slots(current, next):
				continue
			if platform_height >= 0 and next != goal and int(data.height_levels[data.index(next)]) != platform_height:
				continue
			if _is_external_cell(next) or (not ignore_reservations and _reserved_cells.has(next) and int(_reserved_cells[next]) != unit_index):
				continue
			if _cell_owners.has(next) and next != goal and not allow_occupied:
				continue
			var heuristic := absi(next.x - goal.x) + absi(next.y - goal.y)
			if final_egress_only and rally_component.has(next) and rally_component.has(goal):
				heuristic = maxi(heuristic, absi(int(rally_component[next]) - int(rally_component[goal])))
			_frontier_push(pending, Vector4i(data.index(next), next_cost, heuristic, sequence))
			sequence += 1
			previous[next] = current
			costs[next] = next_cost
	max_passage_expansions = maxi(max_passage_expansions, head + field_expansions)
	local_search_expansions += head + field_expansions
	max_local_search_expansions = maxi(max_local_search_expansions, head + field_expansions)
	if not previous.has(goal):
		return empty
	var route: Array[Vector2i] = []
	var cursor := goal
	while cursor != INVALID_CELL:
		route.push_front(cursor)
		cursor = previous.get(cursor, INVALID_CELL)
	return route

func _passage_step_to_goal(unit_index: int, goal: Vector2i, allow_occupied: bool = false) -> Vector2i:
	if unit_index < 0 or unit_index >= SOLDIER_COUNT or goal == INVALID_CELL:
		return INVALID_CELL
	if cells[unit_index] == goal:
		return INVALID_CELL
	if _passage_active and goal == desired_cells[unit_index] \
		and _follower_route_goals.get(unit_index, INVALID_CELL) != goal \
		and int(_unit_passage[unit_index]) >= _passage_group_end \
		and _unit_passage_phase[unit_index] in [PassagePhase.EXIT_CLEAR, PassagePhase.RALLY, PassagePhase.EXEMPT]:
		# The structure owner already recovered these terrain-valid exit routes.
		# Reuse them like inter-gate connections; local-search fairness must not
		# leave each new arrival sitting on the exit for up to 25 service ticks.
		var shared: Array = _active_rally_routes().get(goal, [])
		var position := shared.find(cells[unit_index])
		if position >= 0 and position + 1 < shared.size():
			var next: Vector2i = shared[position + 1]
			if _passage_step_is_free(next, unit_index) or _unit_passage_exit_clear[unit_index] == 0:
				return next
			# Once clear of the exit, try a bounded free detour before turning
			# a long row of settled ranks into another sequential push chain.
	allow_occupied = allow_occupied or _local_occupied_retry.get(unit_index, INVALID_CELL) == goal
	if _passage_active and _unit_passage_phase[unit_index] == PassagePhase.EXIT_CLEAR:
		var passage_index := int(_unit_passage[unit_index])
		if passage_index + 1 < _passage_descriptors.size():
			var next_descriptor: Dictionary = _passage_descriptors[passage_index + 1]
			var route_start := int(_passage_descriptors[passage_index].last_edge) + 2
			var route_end := int(next_descriptor.first_edge)
			var route_position := _path_route_snapshot.find(cells[unit_index], route_start)
			if goal == next_descriptor.entry and route_position >= route_start and route_position < route_end:
				# Share the captain's proven connection; each follower owns only
				# its cursor. Occupied next cells are queued by the usual scheduler.
				_follower_routes[unit_index] = _path_route_snapshot
				_follower_route_goals[unit_index] = goal
				_follower_route_cursors[unit_index] = route_position + 1
				return _path_route_snapshot[route_position + 1]
	if not allow_occupied and _cell_owners.has(goal) and int(_cell_owners[goal]) != unit_index and not _passage_active:
		# Keep the published slot set but repair only this unstarted binding. A
		# different unit may already stand on the chosen slot after an egress
		# detour; sending a push chain into a settled slot would deadlock the
		# passage or eject a unit back toward the core.
		for candidate: Vector2i in _passage_final_slots:
			var bound_elsewhere := false
			for other_index: int in range(1, SOLDIER_COUNT):
				if other_index != unit_index and desired_cells[other_index] == candidate:
					bound_elsewhere = true
					break
			if not bound_elsewhere and not _cell_owners.has(candidate) and not _reserved_cells.has(candidate) and candidate != cells[0] and not _is_external_cell(candidate):
				desired_cells[unit_index] = candidate
				if _formation_slot_cells.size() == SOLDIER_COUNT:
					_formation_slot_cells[unit_index] = candidate
				_passage_binding_revision += 1
				goal = candidate
				_clear_follower_route(unit_index)
				break
	var route: Array = _follower_routes.get(unit_index, [])
	var cursor := int(_follower_route_cursors.get(unit_index, 0))
	var stored_goal: Vector2i = _follower_route_goals.get(unit_index, INVALID_CELL)
	var rebuild: bool = stored_goal != goal or route.size() < 2 or cursor < 1 or cursor >= route.size() or route[cursor - 1] != cells[unit_index]
	if not rebuild:
		var cached_next: Vector2i = route[cursor]
		rebuild = not data.can_step(cells[unit_index], cached_next) or (not allow_occupied and not _passage_step_is_free(cached_next, unit_index))
	if rebuild:
		if int(_local_search_tick.get(unit_index, -1)) == _passage_tick:
			return INVALID_CELL
		route = _find_passage_route(cells[unit_index], goal, unit_index, allow_occupied)
		if route.size() < 2:
			if int(_local_search_tick.get(unit_index, -1)) == _passage_tick:
				_local_occupied_retry[unit_index] = INVALID_CELL if allow_occupied else goal
			_clear_follower_route(unit_index)
			return INVALID_CELL
		_local_occupied_retry.erase(unit_index)
		_follower_routes[unit_index] = route
		_follower_route_goals[unit_index] = goal
		_follower_route_cursors[unit_index] = 1
		cursor = 1
	var next: Vector2i = route[cursor]
	if not data.can_step(cells[unit_index], next):
		return INVALID_CELL
	if _unit_has_cleared_group(unit_index) and not _push_preserves_open_slots(cells[unit_index], next):
		_clear_follower_route(unit_index)
		return INVALID_CELL
	if not allow_occupied and not _passage_step_is_free(next, unit_index):
		# Search may legitimately finish at an occupied goal. That is a ready
		# displacement intent, not a failed route to repeat forever. Scheduling
		# still checks the real owner, claims, phase and atomic push contract.
		if next != goal or not _cell_owners.has(next) or _reserved_cells.has(next) or _is_external_cell(next):
			_local_occupied_retry[unit_index] = goal
			return INVALID_CELL
	return next

func _advance_unreachable_approach(unit_index: int) -> Vector2i:
	# Initial downstream exemptions are established at atomic plan publication.
	# Missing approach topology cannot create new passage history during play.
	command_status = "PASSAGE_UNRESOLVED | no proven approach for unit %s" % unit_index
	return INVALID_CELL

func _next_passage_step(unit_index: int) -> Vector2i:
	if unit_index < 0 or unit_index >= SOLDIER_COUNT or _unit_passage.size() != SOLDIER_COUNT:
		return INVALID_CELL
	var phase := int(_unit_passage_phase[unit_index])
	if phase == PassagePhase.NONE:
		return INVALID_CELL
	var current: Vector2i = cells[unit_index]
	if phase == PassagePhase.EXEMPT or phase == PassagePhase.RALLY:
		return _passage_step_to_goal(unit_index, desired_cells[unit_index])
	var passage_index := int(_unit_passage[unit_index])
	var descriptor := _passage_descriptor(passage_index)
	var corridor: Array = descriptor.get("corridor", [])
	if corridor.size() < 2:
		return INVALID_CELL
	if phase == PassagePhase.APPROACH:
		var entry: Vector2i = descriptor.get("entry", INVALID_CELL)
		var approach: Dictionary = descriptor.get("approach_component", {})
		var queue_floor := _passage_approach_floor(unit_index, passage_index)
		if _passage_order_hold(unit_index, passage_index) and int(approach.get(current, -1)) <= queue_floor:
			return INVALID_CELL
		if current != entry:
			var approach_step := _passage_step_to_goal(unit_index, entry, true)
			if approach_step != INVALID_CELL:
				if int(approach.get(approach_step, -1)) < queue_floor:
					return INVALID_CELL
				return approach_step
			if queue_floor > 0:
				return INVALID_CELL
			if _local_path_requests_remaining <= 0:
				return INVALID_CELL
			var advanced_approach := _advance_unreachable_approach(unit_index)
			if advanced_approach != INVALID_CELL:
				return advanced_approach
			# A structurally unreachable entry is not an invitation to oscillate
			# between arbitrary free neighbours. Let the topology-proven bypass
			# accumulate its bounded wait instead; ordinary temporary queue blocks
			# retain the legacy staging escape below.
			if _passage_approach_must_wait(unit_index):
				return INVALID_CELL
			# A temporary queue blockage may need one legal free staging step to open
			# the approach; topology-proven bypasses are handled above.
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var escape := current + direction
				if _passage_cell_is_protected(escape):
					continue
				if data.can_step(current, escape) and _passage_step_is_free(escape, unit_index):
					return escape
			return INVALID_CELL
		if not _passage_ready_for_entry(unit_index, passage_index):
			return INVALID_CELL
		var core: Vector2i = corridor[1]
		return core if _passage_step_is_free(core, unit_index) and data.can_step(current, core) else INVALID_CELL
	if phase == PassagePhase.IN_PASSAGE:
		var cursor := -1
		for route_index: int in range(corridor.size()):
			if corridor[route_index] == current:
				cursor = route_index
				break
		if cursor < 0:
			return INVALID_CELL
		_unit_passage_cursor[unit_index] = cursor
		if cursor + 1 >= corridor.size():
			return INVALID_CELL
		var next: Vector2i = corridor[cursor + 1]
		# The corridor itself is the only route an IN_PASSAGE unit may use. If
		# its next cell is occupied, return that legal forward edge so the common
		# push transaction can move the blocker instead of freezing the queue.
		return next if data.can_step(current, next) else INVALID_CELL
	if phase == PassagePhase.EXIT_CLEAR:
		if passage_index < _passage_group_end:
			var next_descriptor: Dictionary = _passage_descriptors[passage_index + 1]
			var next_entry: Vector2i = next_descriptor.get("entry", INVALID_CELL)
			if current == next_entry:
				var next_corridor: Array = next_descriptor.get("corridor", [])
				if next_corridor.size() >= 2 and _passage_ready_for_entry(unit_index, passage_index + 1):
					var next_core: Vector2i = next_corridor[1]
					return next_core if _passage_step_is_free(next_core, unit_index) and data.can_step(current, next_core) else INVALID_CELL
				return INVALID_CELL
			return _passage_step_to_goal(unit_index, next_entry, true)
		# The route owner alternates free/occupied searches on separate service
		# turns. PENDING never means take an arbitrary escape and lose the route.
		return _passage_step_to_goal(unit_index, desired_cells[unit_index])
	return INVALID_CELL

func _record_passage_commit(index: int, old_cell: Vector2i, new_cell: Vector2i) -> void:
	if not _passage_active or index < 0 or index >= SOLDIER_COUNT or _unit_passage.size() != SOLDIER_COUNT:
		return
	var passage_index := int(_unit_passage[index])
	var phase := int(_unit_passage_phase[index])
	if phase == PassagePhase.EXEMPT or phase == PassagePhase.RALLY or passage_index < 0:
		return
	var descriptor := _passage_descriptor(passage_index)
	var corridor: Array = descriptor.get("corridor", [])
	if corridor.size() < 2:
		return
	var entry: Vector2i = descriptor.get("entry", INVALID_CELL)
	var core: Vector2i = corridor[1]
	var exit_cell: Vector2i = descriptor.get("exit", corridor.back())
	# Reaching the entry only queues the follower at the mouth. It has not
	# consumed the gate until the authoritative commit crosses entry -> core;
	# promoting on entry would let an in-flight pre-plan move bypass ticket order.
	if phase == PassagePhase.APPROACH and new_cell == entry:
		_unit_passage_cursor[index] = 0
	elif phase == PassagePhase.APPROACH and old_cell == entry and new_cell == core:
		_unit_passage_phase[index] = PassagePhase.IN_PASSAGE
		_unit_passage_cursor[index] = 1
		phase = PassagePhase.IN_PASSAGE
	if phase == PassagePhase.IN_PASSAGE:
		if old_cell == core and new_cell != core and _passage_service_owner.size() > passage_index and _passage_service_owner[passage_index] == index:
			_passage_service_owner[passage_index] = -1
		if old_cell == entry and new_cell == core and _unit_passage_crossed[index] == 0:
			_unit_passage_crossed[index] = 1
			_bind_receiving_arrival(index)
			_passage_crossings[passage_index] += int(index > 0)
			if index > 0 and passage_index == _passage_descriptors.size() - 1:
				_passage_crossed_count += 1
			if _passage_service_owner.size() > passage_index:
				_passage_service_owner[passage_index] = index
		for route_index: int in range(corridor.size()):
			if corridor[route_index] == new_cell:
				_unit_passage_cursor[index] = route_index
				break
		if new_cell == exit_cell:
			_unit_passage_phase[index] = PassagePhase.EXIT_CLEAR
			_unit_passage_exit_clear[index] = 0
			phase = PassagePhase.EXIT_CLEAR
	if phase == PassagePhase.EXIT_CLEAR:
		if old_cell == exit_cell and new_cell != exit_cell and _unit_completed_exits[index] <= passage_index:
			_unit_completed_exits[index] = passage_index + 1
			_passage_clearings[passage_index] += int(index > 0)
		if passage_index < _passage_group_end:
			var next_descriptor: Dictionary = _passage_descriptors[passage_index + 1]
			var next_entry: Vector2i = next_descriptor.get("entry", INVALID_CELL)
			if new_cell == next_entry:
				_unit_passage[index] = passage_index + 1
				_unit_passage_phase[index] = PassagePhase.APPROACH
				_unit_passage_cursor[index] = 0
				_unit_passage_crossed[index] = 0
				_unit_passage_exit_clear[index] = 0
				if _passage_service_owner.size() > passage_index and _passage_service_owner[passage_index] == index:
					_passage_service_owner[passage_index] = -1
				return
		if new_cell != exit_cell:
			_unit_passage_exit_clear[index] = 1
			if _passage_service_owner.size() > passage_index and _passage_service_owner[passage_index] == index:
				_passage_service_owner[passage_index] = -1
			if passage_index == _passage_group_end and new_cell == desired_cells[index] and _unit_passage_exit_clear[index] != 0:
				_unit_passage_phase[index] = PassagePhase.RALLY
				_unit_passage_cursor[index] = -1
		_unit_passage_last_commit_tick[index] = _passage_tick

func _passage_complete() -> bool:
	if not _passage_active or _passage_slot_capacity != SOLDIER_COUNT - 1 or not has_army():
		return false
	# A collective step may land exactly on the final set before the next
	# planning tick publishes its final facing/bindings. Do not finish the
	# passage in that intermediate state and strand a sideways-facing command.
	if not _formation_final_reform:
		return false
	if _passage_group_start < _passage_descriptors.size() or cells[0] != _passage_final_captain_slot:
		return false
	if cells[0] != desired_cells[0] or movement_state[0] == UnitState.MOVING or movement_state[0] == UnitState.SWAPPING:
		return false
	if not _unit_has_cleared_passages(0) or not _passage_final_egress_cell(cells[0]):
		return false
	for index: int in range(1, SOLDIER_COUNT):
		if _unit_passage_phase[index] != PassagePhase.RALLY and _unit_passage_phase[index] != PassagePhase.EXEMPT:
			return false
		if _unit_completed_exits[index] != _passage_descriptors.size() or _push_lock[index] != 0:
			return false
		if cells[index] != desired_cells[index] or movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING:
			return false
		if not _passage_final_slots.has(cells[index]) or not _passage_final_egress_cell(cells[index]):
			return false
	var unique_slots := {}
	for slot: Vector2i in _passage_final_slots:
		if unique_slots.has(slot) or not data.is_walkable(slot) or _is_external_cell(slot):
			return false
		unique_slots[slot] = true
	if unique_slots.size() != SOLDIER_COUNT - 1 or _push_lock[0] != 0:
		return false
	return _pending_pushes.is_empty() and _reserved_cells.is_empty() and not has_active_swap() and not _has_active_follower_swap()

func _repair_passage_slot_binding() -> bool:
	# When every follower has physically reached the published egress component,
	# a remaining identity permutation is a binding problem, not a terrain
	# problem. Re-pair only at an idle transaction boundary and only when every
	# current cell is already one of the 99 immutable final slots. This avoids
	# pushing a settled rank out of its slot merely to satisfy another identity.
	if not _passage_active or _passage_slot_capacity != SOLDIER_COUNT - 1 or not has_army() or _formation_bend_active:
		return false
	if _repair_idle_slot_bindings():
		return true
	if moving_count() > 0 or not _pending_pushes.is_empty() or has_active_swap() or _has_active_follower_swap():
		return false
	var occupied_slots := {}
	var all_on_final_slots := true
	for index: int in range(1, SOLDIER_COUNT):
		if not _unit_has_cleared_group(index):
			return false
		var current := cells[index]
		if not _active_rally_slots().has(current):
			all_on_final_slots = false
		elif occupied_slots.has(current):
			return false
		occupied_slots[current] = true
	# Do not rebind while any unit is still on a staging cell. Once every
	# crossed unit is in the published slot set, repair only the remaining RALLY
	# identity-to-slot matching at this idle transaction boundary.
	if not all_on_final_slots:
		return false
	for index: int in range(1, SOLDIER_COUNT):
		desired_cells[index] = cells[index]
		if _formation_slot_cells.size() == SOLDIER_COUNT:
			_formation_slot_cells[index] = cells[index]
		if _unit_passage_phase[index] == PassagePhase.EXIT_CLEAR:
			_unit_passage_phase[index] = PassagePhase.RALLY
			_unit_passage_cursor[index] = -1
			_unit_passage_exit_clear[index] = 1
	_passage_service_owner.fill(-1)
	_follower_routes.clear()
	_follower_route_goals.clear()
	_follower_route_cursors.clear()
	_passage_binding_revision += 1
	_update_formation_status()
	return true

func _finish_passage() -> void:
	if not _passage_complete():
		return
	_passage_active = false
	_formation_anchor_cell = cells[0]
	for index: int in range(SOLDIER_COUNT):
		_formation_offsets[index] = cells[index] - _formation_anchor_cell
	_exit_rally_settled = true
	_exit_rally_assigned = true
	_formation_has_bottleneck = false
	_formation_bottleneck_width = FORMATION_COLUMNS
	_formation_width = FORMATION_COLUMNS
	formation_mode = FormationMode.OPEN
	_formation_lagging = false
	_update_formation_status()
	command_status = "Passage cleared | formation assembled 99/99"

func _follower_swap_requested(first: int, second: int) -> bool:
	if first <= 0 or second <= 0 or first >= SOLDIER_COUNT or second >= SOLDIER_COUNT:
		return false
	if not (formation_mode == FormationMode.COLUMN or formation_mode == FormationMode.OPEN):
		return false
	if desired_cells[first] == cells[second] and desired_cells[second] == cells[first]:
		return true
	if formation_mode != FormationMode.COLUMN or not _formation_has_bottleneck:
		return false
	# Repair an out-of-order queue only when the requester has demonstrably
	# progressed farther along the captain trail than the blocker. This avoids
	# arbitrary rank swapping while allowing a front soldier to pass a stale
	# lower-rank occupant on a two-way section of the ramp.
	var first_progress := _captain_trail_progress(cells[first])
	var second_progress := _captain_trail_progress(cells[second])
	return first_progress > second_progress and _captain_trail_progress(desired_cells[first]) > second_progress


func _nearest_walkable(preferred: Vector2i, used: Dictionary, revision: int) -> Vector2i:
	var pending: Array[Vector2i] = [preferred]
	var visited := {preferred: true}
	var head := 0
	while head < pending.size() and head < 2048:
		if not await _take_structure_expansion(revision):
			return INVALID_CELL
		var candidate: Vector2i = pending[head]
		head += 1
		if data.contains(candidate) and not used.has(candidate) and not _is_external_cell(candidate) \
			and data.is_walkable(candidate) and _distance_to_cell(candidate) >= 0:
			return candidate
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := candidate + direction
			if data.contains(next) and not visited.has(next):
				visited[next] = true
				pending.append(next)
	return INVALID_CELL

func _find_unused_reachable_cell(used: Dictionary, revision: int) -> Vector2i:
	if data == null or _distance_values.is_empty():
		return INVALID_CELL
	var best := INVALID_CELL
	var best_distance := 1 << 30
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			if not await _take_structure_expansion(revision):
				return INVALID_CELL
			var candidate := Vector2i(x, y)
			if used.has(candidate) or _is_external_cell(candidate) or not data.is_walkable(candidate):
				continue
			var distance := _distance_to_cell(candidate)
			if distance >= 0 and distance < best_distance:
				best = candidate
				best_distance = distance
	return best

func _choose_edge_targets() -> bool:
	if not _ensure_distance_map(_formation_anchor_cell):
		command_status = "PLANNING | shared navigation field"
		return true
	if not _command_goal_pending:
		return true
	# The edge command is a captain command, not one destination per soldier.
	# Enumerate the actual map boundary in a stable order and choose the nearest
	# reachable opening. Followers are assigned by _update_formation_targets.
	var boundary: Array[Vector2i] = []
	for x: int in range(data.size.x):
		boundary.append(Vector2i(x, 0))
		if data.size.y > 1:
			boundary.append(Vector2i(x, data.size.y - 1))
	for y: int in range(1, maxi(1, data.size.y - 1)):
		boundary.append(Vector2i(0, y))
		if data.size.x > 1:
			boundary.append(Vector2i(data.size.x - 1, y))
	var best := INVALID_CELL
	var best_distance := 1 << 30
	for cell: Vector2i in boundary:
		if _is_external_cell(cell) or not data.is_walkable(cell):
			continue
		var distance := _distance_to_cell(cell)
		if distance >= 0 and distance < best_distance:
			best = cell
			best_distance = distance
	edge_targets.clear()
	if best == INVALID_CELL:
		command_status = "Edge command rejected: no reachable boundary opening"
		return false
	edge_targets.append(best)
	_march_goal = best
	_march_goal_valid = true
	desired_cells[0] = best
	_command_goal_pending = false
	_publish_distance_route(best)
	_update_formation_targets(true)
	return true

func _edge_distance(cell: Vector2i) -> int:
	return mini(mini(cell.x, data.size.x - 1 - cell.x), mini(cell.y, data.size.y - 1 - cell.y))

func _clear_navigation_paths() -> void:
	# The navigation field is shared by the formation. External blockers can
	# move independently, so invalidate it when a command target is rebuilt.
	_structure_revision += 1
	_structure_work_ready.emit()
	_distance_job_pending = false
	_distance_job_origin = INVALID_CELL
	_distance_parents.clear()
	_passage_plan_pending = false
	_formation_target_pending = false
	_exit_rally_pending = false
	_distance_origin = INVALID_CELL
	_distance_values.clear()
	_clear_path_job()
	_clear_path_route()
	_path_route_snapshot.clear()
	_path_route_snapshot_revision = 0
	_clear_passage_plan()

func _clear_passage_plan() -> void:
	_formation_final_fields.clear()
	_formation_bend_active = false
	_formation_bend_span = 0
	_formation_bend_followup.clear()
	_formation_bend_preview.clear()
	_formation_bend_order.clear()
	_formation_bend_field.clear()
	_formation_bend_lateral.clear()
	_formation_guide_group = -1
	_formation_final_reform = false
	_passage_descriptors.clear()
	_passage_active = false
	_passage_group_start = 0
	_passage_group_end = -1
	_passage_route_revision = -1
	_passage_command_epoch = -1
	_passage_final_slots.clear()
	_passage_final_captain_slot = INVALID_CELL
	_passage_final_routes.clear()
	_passage_slot_capacity = 0
	_passage_available_capacity = 0
	_passage_failure_reason = ""
	_passage_ticket_order.clear()
	_passage_service_owner.clear()
	_passage_crossed_count = 0
	_passage_exempt_count = 0
	_passage_crossings.clear()
	_passage_clearings.clear()
	_passage_tick = 0
	if _unit_passage.size() == SOLDIER_COUNT:
		_unit_passage.fill(-1)
		_unit_passage_phase.fill(PassagePhase.NONE)
		_unit_passage_cursor.fill(-1)
		_unit_passage_ticket.fill(-1)
		_unit_passage_crossed.fill(0)
		_unit_passage_exit_clear.fill(0)
		_unit_completed_exits.fill(0)
		_unit_initial_exempt_exits.fill(0)
		_unit_passage_last_commit_tick.fill(0)

func passage_active() -> bool:
	return _passage_active

func passage_crossed_count() -> int:
	return _passage_crossed_count

func passage_slot_capacity() -> int:
	return _passage_slot_capacity

func passage_summary() -> Dictionary:
	var summary := {"waiting": 0, "clearing": 0, "completed": 0}
	for index: int in range(1, _unit_passage_phase.size()):
		var phase := int(_unit_passage_phase[index])
		if phase == PassagePhase.APPROACH:
			summary.waiting += 1
		elif phase == PassagePhase.IN_PASSAGE or (phase == PassagePhase.EXIT_CLEAR and _unit_passage_exit_clear[index] == 0):
			summary.clearing += 1
		elif _unit_has_cleared_passages(index):
			summary.completed += 1
		elif phase == PassagePhase.EXIT_CLEAR:
			summary.waiting += 1
	return summary

func _passage_external_blocker() -> Vector2i:
	if not _passage_active:
		return INVALID_CELL
	# Only two external actors can block this snapshot. Native membership
	# checks avoid querying both objects for every corridor/slot every tick.
	for actor: Variant in [player, npc]:
		if actor == null:
			continue
		var cell: Vector2i = actor.terrain_cell
		for descriptor: Dictionary in _passage_descriptors:
			if descriptor.get("corridor", []).has(cell):
				return cell
		if _passage_final_slots.has(cell):
			return cell
	return INVALID_CELL

func _route_edge_width(from: Vector2i, to: Vector2i, scan_radius: int = PASSAGE_EDGE_SCAN_RADIUS) -> int:
	if data == null or not data.contains(from) or not data.contains(to):
		return 0
	var heading := to - from
	if heading not in TerrainData.DIRECTIONS or not data.can_step(from, to):
		return 0
	var side := Vector2i(-heading.y, heading.x)
	# Count one contiguous strip of lanes. A walkable platform beside a cliff is
	# not a parallel lane unless both ends connect laterally to the previously
	# accepted lane. This is the distinction the old independent scan missed.
	var width := 1
	for sign: int in [-1, 1]:
		var previous_from := from
		var previous_to := to
		for offset: int in range(1, scan_radius + 1):
			var lane_from := from + side * sign * offset
			var lane_to := to + side * sign * offset
			if not data.contains(lane_from) or not data.contains(lane_to) or not data.can_step(lane_from, lane_to):
				break
			if not data.can_step(previous_from, lane_from) or not data.can_step(previous_to, lane_to):
				break
			width += 1
			previous_from = lane_from
			previous_to = lane_to
	return width

func _passage_route_protected_cells() -> Dictionary:
	var protected := {}
	for descriptor: Dictionary in _passage_descriptors:
		for cell: Vector2i in descriptor.get("protected", []):
			protected[cell] = true
	return protected

func _passage_cell_is_protected(cell: Vector2i) -> bool:
	# A point query must not rebuild the whole mask. Searches still obtain a
	# private dictionary above because they reopen their own start/goal cells.
	for descriptor: Dictionary in _passage_descriptors:
		if descriptor.get("protected", []).has(cell):
			return true
	return false

func _passage_final_egress_cell(cell: Vector2i) -> bool:
	if not _active_rally_component().has(cell) or data == null or not data.contains(cell):
		return false
	return _passage_group_start >= _passage_descriptors.size() \
		or int(_active_rally_component()[cell]) <= int(_passage_descriptor(_passage_group_end).get("rally_distance_limit", 1 << 29))

func _flood_passage_component(start: Vector2i, blocked: Dictionary, revision: int, max_distance: int = -1, additional_starts: Array[Vector2i] = []) -> Dictionary:
	var result := {}
	if data == null or not data.contains(start) or not data.is_walkable(start) or blocked.has(start):
		return result
	var pending: Array[Vector2i] = [start]
	result[start] = 0
	for seed: Vector2i in additional_starts:
		if not result.has(seed) and data.is_walkable(seed) and not blocked.has(seed):
			result[seed] = 0
			pending.append(seed)
	var head := 0
	while head < pending.size() and pending.size() <= data.size.x * data.size.y:
		if not await _take_structure_expansion(revision):
			return {}
		var current: Vector2i = pending[head]
		head += 1
		var current_distance := int(result[current])
		if max_distance >= 0 and current_distance >= max_distance:
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if result.has(next) or blocked.has(next) or not data.contains(next) or not data.can_step(current, next):
				continue
			result[next] = current_distance + 1
			pending.append(next)
	return result

func _passage_cell_is_egress_safe(cell: Vector2i, component: Dictionary, protected: Dictionary) -> bool:
	return component.has(cell) and not protected.has(cell) and not _is_external_cell(cell) \
		and data.is_walkable(cell)

func _sort_cells_by_depth(candidates: Array[Vector2i], distances: Dictionary, anchor: Vector2i = INVALID_CELL, farthest_first: bool = true) -> Array[Vector2i]:
	# Preserve the exact published ordering without quadratic selection sorting.
	var sorted: Array[Vector2i] = candidates.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if anchor != INVALID_CELL:
			var da := absi(a.x - anchor.x) + absi(a.y - anchor.y)
			var db := absi(b.x - anchor.x) + absi(b.y - anchor.y)
			if da != db:
				return da < db
		var depth_a := int(distances.get(a, -1))
		var depth_b := int(distances.get(b, -1))
		if depth_a != depth_b:
			return depth_a > depth_b if farthest_first else depth_a < depth_b
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return sorted

func _passage_rally_layout(component: Dictionary, protected: Dictionary, anchor: Vector2i, revision: int, heading: Vector2i = Vector2i.ZERO, near_exit: bool = false) -> Array[Vector2i]:
	if component.size() < SOLDIER_COUNT:
		return []
	if heading == Vector2i.ZERO:
		heading = _path_route_snapshot[-1] - _path_route_snapshot[-2]
	var compact: Array[Vector2i] = []
	var nearby := {}
	if near_exit:
		var candidates: Array[Vector2i] = []
		candidates.assign(component.keys())
		candidates = _sort_cells_by_depth(candidates, component, INVALID_CELL, false)
		for start: Vector2i in candidates:
			if _passage_cell_is_egress_safe(start, component, protected):
				compact = await _compact_rally_layout(component, protected, start, heading, revision)
				break
		if revision != _structure_revision:
			return []
		if compact.size() == SOLDIER_COUNT:
			var farthest := 0
			for slot: Vector2i in compact:
				farthest = maxi(farthest, int(component[slot]))
			# Wider ranks may use the existing six-cell local reform allowance.
			# No farther rectangle can improve this proven nearby 100-cell body.
			for cell: Vector2i in component:
				if int(component[cell]) <= farthest + FORMATION_REFORM_DISTANCE:
					nearby[cell] = true
	var best: Array[Vector2i] = []
	var best_distance := 1 << 29
	for width: int in range(FORMATION_COLUMNS, 1, -1):
		var layout := await _passage_rally_rectangle(component, protected, anchor, revision, heading, width, near_exit, nearby)
		if revision != _structure_revision:
			return []
		if layout.size() != SOLDIER_COUNT:
			continue
		if not near_exit or not nearby.is_empty():
			return layout
		var distance := 0
		for slot: Vector2i in layout:
			distance = maxi(distance, int(component[slot]))
		if best.is_empty() or distance + FORMATION_REFORM_DISTANCE < best_distance:
			best = layout
			best_distance = distance
	return compact if compact.size() == SOLDIER_COUNT else best

func _compact_rally_layout(component: Dictionary, protected: Dictionary, start: Vector2i, heading: Vector2i, revision: int) -> Array[Vector2i]:
	# A bent terrace can hold a compact connected body without admitting any
	# 100-cell rectangle. Follow its real same-height edges, including corners.
	var slots: Array[Vector2i] = [start]
	var seen := {start: true}
	var head := 0
	var height := int(data.height_levels[data.index(start)])
	while head < slots.size() and slots.size() < SOLDIER_COUNT:
		if not await _take_structure_expansion(revision):
			return []
		var current := slots[head]
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if seen.has(next) or not _passage_cell_is_egress_safe(next, component, protected) \
				or data.height_levels[data.index(next)] != height or not data.can_step(current, next):
				continue
			seen[next] = true
			slots.append(next)
			if slots.size() == SOLDIER_COUNT:
				break
	if slots.size() != SOLDIER_COUNT:
		return []
	var average := Vector2.ZERO
	for slot: Vector2i in slots:
		average += Vector2(slot)
	average /= float(SOLDIER_COUNT)
	var captain := INVALID_CELL
	var best_distance := INF
	for candidate: Vector2i in slots:
		if not await _take_structure_expansion(revision):
			return []
		var guards := 0
		var rear := 0
		for slot: Vector2i in slots:
			var forward := (slot - candidate).x * heading.x + (slot - candidate).y * heading.y
			guards += int(forward > 0)
			rear += int(forward < 0)
		var distance := Vector2(candidate).distance_squared_to(average)
		if guards >= 20 and guards <= 70 and rear >= 20 and distance < best_distance:
			captain = candidate
			best_distance = distance
	if captain == INVALID_CELL:
		return []
	slots.erase(captain)
	slots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var front_a := (a - captain).x * heading.x + (a - captain).y * heading.y
		var front_b := (b - captain).x * heading.x + (b - captain).y * heading.y
		if (front_a > 0) != (front_b > 0):
			return front_a > 0
		return int(component[a]) > int(component[b]) if component[a] != component[b] else (a.y < b.y if a.y != b.y else a.x < b.x))
	slots.push_front(captain)
	return slots

func _passage_rally_rectangle(component: Dictionary, protected: Dictionary, anchor: Vector2i, revision: int, heading: Vector2i, width: int, near_exit: bool, center_region: Dictionary = {}) -> Array[Vector2i]:
	var side := Vector2i(-heading.y, heading.x)
	var rows := ceili(float(SOLDIER_COUNT) / float(width))
	var front_rows := floori(float(rows - 1) / 2.0)
	var half_width := floori(float(width - 1) / 2.0)
	var wanted_center := anchor - heading * front_rows
	var candidates: Array[Vector2i] = []
	candidates.assign(center_region.keys() if not near_exit and not center_region.is_empty() else component.keys())
	candidates = _sort_cells_by_depth(candidates, component, wanted_center)
	if near_exit:
		# A geometrically close cell across a ridge may be a hundred legal
		# edges away. Receiving work is anchored to the actual exit distance.
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if int(component[a]) != int(component[b]):
				return int(component[a]) < int(component[b])
			var da := absi(a.x - wanted_center.x) + absi(a.y - wanted_center.y)
			var db := absi(b.x - wanted_center.x) + absi(b.y - wanted_center.y)
			return da < db if da != db else (a.y < b.y if a.y != b.y else a.x < b.x))
	for center: Vector2i in candidates:
		if not center_region.is_empty() and not center_region.has(center):
			continue
		var slots: Array[Vector2i] = []
		var accepted := {}
		for slot_index: int in range(SOLDIER_COUNT):
			if not await _take_structure_expansion(revision):
				return []
			var slot := center + heading * (front_rows - floori(float(slot_index) / float(width))) + side * (slot_index % width - half_width)
			if near_exit and not center_region.is_empty() and not center_region.has(slot):
				break
			if not _passage_cell_is_egress_safe(slot, component, protected):
				break
			var legal := true
			for neighbor: Vector2i in [slot - side, slot + heading]:
				if accepted.has(neighbor) and not data.can_step(neighbor, slot):
					legal = false
			if not legal:
				break
			slots.append(slot)
			accepted[slot] = true
		if slots.size() == SOLDIER_COUNT:
			slots.erase(center)
			# The guards occupy the actual front ranks before
			# the captain takes the centre. A diamond/depth ordering left front
			# goals behind the captain's occupied middle lane for the late tail.
			slots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				var front_a := a.x * heading.x + a.y * heading.y
				var front_b := b.x * heading.x + b.y * heading.y
				var captain_front := center.x * heading.x + center.y * heading.y
				if (front_a > captain_front) != (front_b > captain_front):
					return front_a > captain_front
				# Keep guards before the captain, but fill each half from the
				# farthest legal receiving route first. Filling near rear rows
				# first sealed the outlet and required 20-person vacancy chains.
				if int(component[a]) != int(component[b]):
					return int(component[a]) > int(component[b])
				if front_a != front_b:
					return front_a > front_b
				var side_a := absi((a - center).x * side.x + (a - center).y * side.y)
				var side_b := absi((b - center).x * side.x + (b - center).y * side.y)
				return side_a > side_b if side_a != side_b else (a.y < b.y if a.y != b.y else a.x < b.x))
			slots.push_front(center)
			return slots
	return []

func _layout_front_cell(layout: Array[Vector2i], heading: Vector2i) -> Vector2i:
	if layout.is_empty():
		return INVALID_CELL
	var front := layout[0]
	var side := Vector2i(-heading.y, heading.x)
	for slot: Vector2i in layout:
		var forward := (slot - front).x * heading.x + (slot - front).y * heading.y
		var lateral := absi((slot - layout[0]).x * side.x + (slot - layout[0]).y * side.y)
		var old_lateral := absi((front - layout[0]).x * side.x + (front - layout[0]).y * side.y)
		if forward > 0 or (forward == 0 and lateral < old_lateral):
			front = slot
	return front

func _compact_boundary_layout(component: Dictionary, protected: Dictionary, front: Vector2i, heading: Vector2i, revision: int, lateral_min: int = -4) -> Array[Vector2i]:
	# A short same-height boundary spur is a front-rank indentation, not a
	# captain-only destination. Grow one connected compact body from its tip.
	if not _passage_cell_is_egress_safe(front, component, protected):
		return []
	var slots: Array[Vector2i] = [front]
	var seen := {front: true}
	var head := 0
	var height := int(data.height_levels[data.index(front)])
	var side := Vector2i(-heading.y, heading.x)
	while head < slots.size() and slots.size() < SOLDIER_COUNT:
		if not await _take_structure_expansion(revision):
			return []
		var current := slots[head]
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			var offset := next - front
			var lateral := offset.x * side.x + offset.y * side.y
			if seen.has(next) or not _passage_cell_is_egress_safe(next, component, protected) \
				or offset.x * heading.x + offset.y * heading.y > 0 \
				or lateral < lateral_min or lateral >= lateral_min + FORMATION_COLUMNS \
				or data.height_levels[data.index(next)] != height or not data.can_step(current, next):
				continue
			seen[next] = true
			slots.append(next)
			if slots.size() == SOLDIER_COUNT:
				break
	if slots.size() != SOLDIER_COUNT:
		return []
	var average := Vector2.ZERO
	for slot: Vector2i in slots:
		average += Vector2(slot)
	average /= float(SOLDIER_COUNT)
	var captain := INVALID_CELL
	var best_distance := INF
	for candidate: Vector2i in slots:
		var guards := 0
		var rear := 0
		for slot: Vector2i in slots:
			var forward := (slot - candidate).x * heading.x + (slot - candidate).y * heading.y
			guards += int(forward > 0)
			rear += int(forward < 0)
		var distance := Vector2(candidate).distance_squared_to(average)
		if guards >= 20 and rear >= 20 and distance < best_distance:
			captain = candidate
			best_distance = distance
	if captain == INVALID_CELL:
		return []
	slots.erase(captain)
	slots.push_front(captain)
	return slots

func _rally_routes_for_layout(layout: Array[Vector2i], component: Dictionary, exit_cell: Vector2i, revision: int) -> Dictionary:
	var routes := {}
	for slot: Vector2i in layout:
		var route: Array[Vector2i] = [slot]
		var cursor := slot
		var difference := exit_cell - slot
		var parent_directions: Array[Vector2i] = [Vector2i(signi(difference.x), 0) if absi(difference.x) >= absi(difference.y) else Vector2i(0, signi(difference.y))]
		for direction: Vector2i in TerrainData.DIRECTIONS:
			if not parent_directions.has(direction):
				parent_directions.append(direction)
		while cursor != exit_cell:
			if not await _take_structure_expansion(revision):
				return {}
			var parent := INVALID_CELL
			var depth := int(component.get(cursor, -1))
			for direction: Vector2i in parent_directions:
				var candidate := cursor + direction
				if component.get(candidate, -2) == depth - 1 and data.can_step(candidate, cursor):
					parent = candidate
					break
			if parent == INVALID_CELL:
				route.clear()
				break
			route.append(parent)
			cursor = parent
		if not route.is_empty():
			route.reverse()
			routes[slot] = route
	return routes

func _passage_descriptor_for_segment(route: Array[Vector2i], first_edge: int, last_edge: int, width: int) -> Dictionary:
	var corridor: Array[Vector2i] = []
	var corridor_end := mini(route.size() - 1, last_edge + 2)
	for route_index: int in range(first_edge, corridor_end + 1):
		corridor.append(route[route_index])
	var core: Array[Vector2i] = []
	for route_index: int in range(first_edge + 1, mini(route.size(), last_edge + 2)):
		core.append(route[route_index])
	var protected: Array[Vector2i] = []
	protected.append(route[first_edge])
	protected.append_array(core)
	return {
		"first_edge": first_edge,
		"last_edge": last_edge,
		"width": width,
		"corridor": corridor,
		"entry": route[first_edge],
		"core": core,
		"exit": route[corridor_end],
		"protected": protected,
	}

func _ticket_insert(unit_index: int, entry_distances: Dictionary) -> void:
	var distance := int(entry_distances.get(cells[unit_index], 1 << 29))
	var insert_position := _passage_ticket_order.size()
	for ticket_position: int in range(_passage_ticket_order.size()):
		var other := _passage_ticket_order[ticket_position]
		var other_distance := int(entry_distances.get(cells[other], 1 << 29))
		if distance < other_distance or (distance == other_distance and unit_index < other):
			insert_position = ticket_position
			break
	_passage_ticket_order.insert(insert_position, unit_index)

func _ensure_passage_plan() -> void:
	# Helper/idle movement may publish a short route without a march command.
	# That route must not start a 100-person passage and replace its targets.
	if command == Command.NONE or not has_army() or data == null or _passage_active or _passage_plan_pending:
		return
	if _path_route_snapshot_revision <= 0 or _path_route_snapshot.size() < 3:
		return
	if _passage_route_revision == _path_route_snapshot_revision:
		return
	_passage_plan_pending = true
	var revision := _structure_revision
	await _build_passage_plan(revision)
	if revision == _structure_revision:
		_passage_plan_pending = false
		if not _passage_active and command != Command.NONE:
			_update_formation_targets(true)
		elif _passage_active and _passage_failure_reason.is_empty() \
			and (_unit_passage_phase.count(PassagePhase.APPROACH) == SOLDIER_COUNT or _passage_descriptors.is_empty()):
			_formation_march_active = true
			_update_formation_targets(true)

func _route_passage_segments(route: Array[Vector2i], revision: int) -> Array[Dictionary]:
	var narrow_edges: Array[int] = []
	var widths: Array[int] = []
	for edge_index: int in range(route.size() - 1):
		if not await _take_structure_expansion(revision):
			return []
		var width := _route_edge_width(route[edge_index], route[edge_index + 1])
		widths.append(width)
		if width > 0 and width <= PASSAGE_MAX_NARROW_WIDTH:
			narrow_edges.append(edge_index)
	var segments: Array[Dictionary] = []
	var first_edge := narrow_edges[0] if not narrow_edges.is_empty() else -1
	var last_edge := first_edge
	var segment_width := widths[first_edge] if first_edge >= 0 else FORMATION_COLUMNS
	for narrow_position: int in range(1, narrow_edges.size()):
		var edge_index: int = narrow_edges[narrow_position]
		if edge_index != last_edge + 1:
			segments.append(_passage_descriptor_for_segment(route, first_edge, last_edge, segment_width))
			first_edge = edge_index
			segment_width = widths[edge_index]
		last_edge = edge_index
		segment_width = mini(segment_width, widths[edge_index])
	if first_edge >= 0:
		segments.append(_passage_descriptor_for_segment(route, first_edge, last_edge, segment_width))
	return segments

func _build_passage_plan(revision: int) -> void:
	var segments := await _route_passage_segments(_path_route_snapshot, revision)
	if revision != _structure_revision:
		return
	var segment_width := int(segments[-1].width) if not segments.is_empty() else FORMATION_COLUMNS
	var terminal_rally_entry := INVALID_CELL
	var terminal: Dictionary = segments.back() if not segments.is_empty() else {}
	if command in [Command.MOVE_TO_EDGE, Command.FOLLOW_PLAYER] and int(terminal.get("last_edge", -1)) == _path_route_snapshot.size() - 2:
		var terminal_entry: Vector2i = terminal.entry
		var terminal_height := int(data.height_levels[data.index(terminal_entry)])
		var same_height := true
		for terminal_cell: Vector2i in terminal.corridor:
			if int(data.height_levels[data.index(terminal_cell)]) != terminal_height:
				same_height = false
		if same_height:
			# A same-height boundary indentation may belong to the final compact
			# footprint. It is not an all-person through-gate, nor a captain scout.
			# A final ramp or undersized platform retains its capacity failure.
			var platform_blocked := {}
			for segment: Dictionary in segments:
				for cell: Vector2i in segment.protected:
					platform_blocked[cell] = true
			platform_blocked.erase(terminal_entry)
			var platform := await _flood_passage_component(terminal_entry, platform_blocked, revision)
			var capacity := 0
			for candidate: Vector2i in platform:
				if not await _take_structure_expansion(revision):
					return
				if _passage_cell_is_egress_safe(candidate, platform, platform_blocked):
					capacity += 1
					if capacity >= SOLDIER_COUNT:
						break
			if capacity >= SOLDIER_COUNT:
				terminal_rally_entry = terminal_entry
				segments.pop_back()
	var protected := {}
	for descriptor: Dictionary in segments:
		for cell: Vector2i in descriptor.get("protected", []):
			protected[cell] = true
	for index: int in range(1, SOLDIER_COUNT):
		# Finish a pre-plan follower move before publishing ownership of a gate.
		# Otherwise an ordinary formation step aimed at entry/core would be
		# mistaken for a passage commit and bypass the ticket contract.
		if movement_state[index] == UnitState.MOVING and protected.has(moving_to[index]):
			return
	var final_exit: Vector2i = segments.back().get("exit", INVALID_CELL) if not segments.is_empty() else terminal_rally_entry
	if final_exit == INVALID_CELL:
		final_exit = _formation_anchor_cell
	var component_blocked := protected.duplicate()
	var component := await _flood_passage_component(final_exit, component_blocked, revision)
	var downstream_components: Array[Dictionary] = []
	for descriptor: Dictionary in segments:
		var downstream_exit: Vector2i = descriptor.get("exit", INVALID_CELL)
		downstream_components.append(component if downstream_exit == final_exit else await _flood_passage_component(downstream_exit, protected, revision))
		var approach_blocked := protected.duplicate()
		approach_blocked.erase(descriptor.entry)
		descriptor["approach_component"] = await _flood_passage_component(descriptor.entry, approach_blocked, revision)
		descriptor["separating"] = not descriptor.approach_component.has(downstream_exit)
	if not segments.is_empty() and not bool(segments.back().separating):
		# Conservative NON_SEPARATING policy: keep the selected corridor
		# mandatory. Only final slots on the exit-nearer side of the sealed
		# terrain graph are safe; this never grants an initial exemption.
		var entry_distances: Dictionary = segments.back().approach_component
		var safe_component := {}
		for candidate: Vector2i in component:
			if not await _take_structure_expansion(revision):
				return
			if not entry_distances.has(candidate) or int(component[candidate]) < int(entry_distances[candidate]):
				safe_component[candidate] = component[candidate]
		component = safe_component
	var available_capacity := 0
	var rally_protected := protected.duplicate()
	for descriptor: Dictionary in segments:
		rally_protected[descriptor.exit] = true
	for candidate: Vector2i in component:
		if not await _take_structure_expansion(revision):
			return
		if _passage_cell_is_egress_safe(candidate, component, rally_protected):
			available_capacity += 1
	var final_layout: Array[Vector2i] = []
	var final_heading := _path_route_snapshot[-1] - _path_route_snapshot[-2]
	if available_capacity >= SOLDIER_COUNT:
		# The front goal is fixed. A rectangle elsewhere would be discarded
		# immediately, so test its one valid full-width centre before the compact
		# boundary layout instead of searching every centre on the platform.
		var final_center := _march_goal - final_heading * 4
		final_layout = await _passage_rally_rectangle(component, rally_protected, _march_goal, revision, final_heading, FORMATION_COLUMNS, false, {final_center: true})
		if _layout_front_cell(final_layout, final_heading) != _march_goal:
			final_layout = await _compact_boundary_layout(component, rally_protected, _march_goal, final_heading, revision)
			# The requested front cell need not be in the middle column. Keep
			# the same ten-column bound while fitting a boundary indentation.
			if final_layout.is_empty():
				for lateral_min: int in range(-FORMATION_COLUMNS + 1, 1):
					if lateral_min == -4:
						continue
					final_layout = await _compact_boundary_layout(component, rally_protected, _march_goal, final_heading, revision, lateral_min)
					if final_layout.size() == SOLDIER_COUNT or revision != _structure_revision:
						break
	var final_slots: Array[Vector2i] = final_layout.slice(1)
	var final_routes := await _rally_routes_for_layout(final_layout, component, final_exit, revision)
	for passage_index: int in range(segments.size()):
		var descriptor: Dictionary = segments[passage_index]
		var rally_component: Dictionary = component if passage_index == segments.size() - 1 else downstream_components[passage_index]
		var rally_exit: Vector2i = descriptor.exit
		var exit_heading: Vector2i = descriptor.corridor[-1] - descriptor.corridor[-2]
		var rally_heading := final_heading
		if passage_index + 1 < segments.size():
			# Look one body-width along the real outgoing route: a one-cell
			# corner or a far gate through a cliff must not reverse the whole body.
			var exit_position := mini(_path_route_snapshot.size() - 2, int(descriptor.last_edge) + 2)
			var near_leg := _path_route_snapshot[mini(_path_route_snapshot.size() - 1, exit_position + FORMATION_COLUMNS)] - _path_route_snapshot[exit_position]
			rally_heading = Vector2i(signi(near_leg.x), 0) if absi(near_leg.x) >= absi(near_leg.y) else Vector2i(0, signi(near_leg.y))
			if rally_heading == Vector2i.ZERO:
				rally_heading = exit_heading
		var pocket := await _passage_rally_layout(rally_component, rally_protected, rally_exit + exit_heading * 6 + rally_heading * 4, revision, rally_heading, true)
		if passage_index == segments.size() - 1 and pocket.size() == SOLDIER_COUNT and final_layout.size() == SOLDIER_COUNT:
			var pocket_distance := 0
			var final_distance := 0
			for slot: Vector2i in pocket:
				pocket_distance = maxi(pocket_distance, int(rally_component[slot]))
			for slot: Vector2i in final_layout:
				final_distance = maxi(final_distance, int(rally_component[slot]))
			# When the final body is already inside the existing local receiving
			# allowance, use that proven layout once. A distant endpoint still
			# requires its separate nearby rally and a subsequent collective march.
			if final_distance <= pocket_distance + FORMATION_REFORM_DISTANCE:
				pocket = final_layout.duplicate()
		descriptor["rally_layout"] = pocket
		descriptor["rally_slots"] = pocket.slice(1)
		descriptor["rally_component"] = rally_component
		descriptor["rally_routes"] = await _rally_routes_for_layout(pocket, rally_component, rally_exit, revision)
		var rally_distance_limit := 0
		for cell: Vector2i in pocket:
			rally_distance_limit = maxi(rally_distance_limit, int(rally_component[cell]))
		# Receiving detours stay near the proven layout. A temporarily occupied
		# rank is not permission to send a soldier around the entire mountain.
		descriptor["rally_distance_limit"] = rally_distance_limit + FORMATION_REFORM_DISTANCE
		descriptor["rally_heading"] = rally_heading
		descriptor["rally_capacity"] = rally_component.size()
		descriptor["rally_completed_tick"] = -1
	# These three command-level fields also serve routes with zero gates.
	# They are not owned by a fictitious final passage, and are published once.
	var final_fields := {}
	if final_layout.size() == SOLDIER_COUNT:
		final_fields["goal_component"] = await _flood_passage_component(final_layout[0], protected, revision)
		var front_rank: Array[Vector2i] = []
		var front_projection := _march_goal.x * final_heading.x + _march_goal.y * final_heading.y
		for slot: Vector2i in final_layout:
			if slot.x * final_heading.x + slot.y * final_heading.y == front_projection:
				front_rank.append(slot)
		final_fields["front_component"] = await _flood_passage_component(_march_goal, protected, revision, -1, front_rank)
		final_fields["goal_slot_component"] = await _flood_passage_component(final_layout[0], protected, revision, -1, final_layout)
		if segments.is_empty():
			component = final_fields.goal_component
			final_routes.clear()
	if revision != _structure_revision:
		return
	# Everything above is private working data. Publish topology, final layout,
	# phases and target ownership together after the bounded work is complete.
	_passage_route_revision = _path_route_snapshot_revision
	_passage_descriptors = segments
	_passage_final_component = component
	_formation_final_fields = final_fields
	_passage_final_slots = final_slots
	_passage_final_routes = final_routes
	_passage_final_captain_slot = final_layout[0] if final_layout.size() == SOLDIER_COUNT else INVALID_CELL
	desired_cells[0] = _passage_final_captain_slot
	# A compact front can have its tip off the captain's centre line. Preserve
	# the command's exact front goal; choosing another middle front cell here
	# would silently move a stationary FOLLOW/EDGE destination after planning.
	_passage_slot_capacity = _passage_final_slots.size()
	_passage_available_capacity = available_capacity
	_passage_failure_reason = ""
	if available_capacity < SOLDIER_COUNT:
		_passage_failure_reason = "INSUFFICIENT_RALLY_CAPACITY"
	elif _passage_slot_capacity != SOLDIER_COUNT - 1:
		_passage_failure_reason = "RALLY_LAYOUT_UNAVAILABLE"
	# Keep the legacy exit-slot view as an alias of the published egress set.
	# EDGE may reach the boundary while the passage is still active, so any
	# compatibility caller must see the same immutable slots rather than an
	# empty second policy.
	_exit_rally_slots = _passage_final_slots.duplicate()
	_passage_slot_set_revision += 1
	_passage_binding_revision += 1
	_passage_ticket_order.clear()
	_passage_approach_topology_cache.clear()
	var entry_distances: Dictionary = _passage_descriptors[0].get("approach_component", {}) if not _passage_descriptors.is_empty() else component
	for index: int in range(1, SOLDIER_COUNT):
		_ticket_insert(index, entry_distances)
	_passage_ticket_order.insert(_passage_captain_ticket(_next_rally_group_end(0)), 0)
	_passage_service_owner.resize(_passage_descriptors.size())
	_passage_service_owner.fill(-1)
	_passage_crossings.resize(_passage_descriptors.size())
	_passage_crossings.fill(0)
	_passage_clearings.resize(_passage_descriptors.size())
	_passage_clearings.fill(0)
	var final_component := component
	var final_slot_set := {}
	for slot: Vector2i in _passage_final_slots:
		final_slot_set[slot] = true
	# A plan may be published after ordinary movement has carried a follower
	# beyond one or more gates. Build downstream platform components once so
	# initial phase assignment uses structural evidence without running a
	# multi-gate route search for every soldier.
	_formation_slot_cells.resize(SOLDIER_COUNT)
	_formation_slot_cells[0] = desired_cells[0]
	for index: int in range(SOLDIER_COUNT):
		var assigned_passage := 0
		var corridor_position := -1
		var initial_completed := 0
		# A follower may have committed an ordinary move before the asynchronous
		# passage plan was published. Preserve that authoritative corridor cell;
		# otherwise the new APPROACH phase would send it back across the same gate.
		for passage_index: int in range(_passage_descriptors.size()):
			var passage_corridor: Array = _passage_descriptors[passage_index].get("corridor", [])
			var found_position := passage_corridor.find(cells[index])
			if found_position >= 0:
				assigned_passage = passage_index
				corridor_position = found_position
				initial_completed = passage_index
				break
		if corridor_position < 0:
			for downstream_index: int in range(downstream_components.size()):
				if bool(_passage_descriptors[downstream_index].get("separating", false)) and downstream_components[downstream_index].has(cells[index]):
					assigned_passage = mini(downstream_index + 1, _passage_descriptors.size() - 1)
					initial_completed = downstream_index + 1
					break
		_unit_completed_exits[index] = initial_completed
		_unit_initial_exempt_exits[index] = initial_completed
		_unit_passage[index] = assigned_passage
		_unit_passage_cursor[index] = maxi(0, corridor_position)
		_unit_passage_ticket[index] = _passage_ticket_order.find(index)
		_unit_passage_crossed[index] = 1 if corridor_position >= 1 else 0
		_unit_passage_exit_clear[index] = 0
		_unit_passage_last_commit_tick[index] = _passage_tick
		var assigned_slot := INVALID_CELL
		var ticket := _unit_passage_ticket[index]
		var follower_slot := ticket - int(ticket > _unit_passage_ticket[0])
		if index == 0:
			assigned_slot = desired_cells[0]
		elif follower_slot >= 0 and follower_slot < _passage_final_slots.size():
			assigned_slot = _passage_final_slots[follower_slot]
		desired_cells[index] = assigned_slot
		_formation_slot_cells[index] = assigned_slot
		if corridor_position < 0 and initial_completed == _passage_descriptors.size() and final_component.has(cells[index]) and not protected.has(cells[index]):
			_unit_passage_phase[index] = PassagePhase.EXEMPT
			_unit_passage[index] = _passage_descriptors.size() - 1
			_unit_passage_crossed[index] = 0
			_unit_passage_exit_clear[index] = 1
			_passage_exempt_count += int(index > 0)
		elif corridor_position >= 1 and cells[index] == _passage_descriptor(assigned_passage).get("exit", INVALID_CELL):
			_unit_passage_phase[index] = PassagePhase.EXIT_CLEAR
		elif corridor_position >= 1:
			_unit_passage_phase[index] = PassagePhase.IN_PASSAGE
		else:
			_unit_passage_phase[index] = PassagePhase.APPROACH
	_passage_active = true
	_formation_march_active = false
	_passage_group_start = 0
	var initial_join_after := 0
	for completed: int in _unit_initial_exempt_exits:
		initial_join_after = maxi(initial_join_after, completed - 1)
	_passage_group_end = _next_rally_group_end(initial_join_after)
	_passage_command_epoch = _command_epoch
	_formation_has_bottleneck = true
	_formation_bottleneck_width = maxi(1, segment_width)
	_formation_width = _formation_bottleneck_width
	formation_mode = FormationMode.COLUMN
	_exit_rally_assigned = _passage_slot_capacity == SOLDIER_COUNT - 1
	_exit_rally_settled = false
	_publish_passage_group_targets()
	_update_formation_status()

func _ensure_distance_map(start: Vector2i) -> bool:
	if data == null or not data.contains(start):
		return false
	var cell_count := data.size.x * data.size.y
	if _distance_origin == start and _distance_values.size() == cell_count:
		return true
	if not _distance_job_pending:
		_distance_job_pending = true
		_distance_job_origin = start
		_build_distance_map(start, _structure_revision)
	return _distance_origin == start and _distance_values.size() == cell_count

func _take_structure_expansion(revision: int) -> bool:
	while revision == _structure_revision and _structure_expansions_remaining <= 0:
		await _structure_work_ready
	if revision != _structure_revision:
		return false
	_structure_expansions_remaining -= 1
	structure_search_expansions += 1
	return true

func _build_distance_map(start: Vector2i, revision: int) -> void:
	var cell_count := data.size.x * data.size.y
	var distances := PackedInt32Array()
	distances.resize(cell_count)
	distances.fill(-1)
	var parents := PackedInt32Array()
	parents.resize(cell_count)
	parents.fill(-1)
	var pending := PackedInt32Array()
	pending.resize(cell_count)
	var head := 0
	var tail := 1
	pending[0] = data.index(start)
	distances[pending[0]] = 0
	parents[pending[0]] = pending[0]
	var goal_published := false
	while head < tail:
		# Once a nearest goal layer is proven, route classification has priority
		# over finishing the optional remainder of the reachability field.
		while goal_published and (_passage_plan_pending or _formation_target_pending) and revision == _structure_revision:
			await _structure_work_ready
		if not await _take_structure_expansion(revision):
			return
		var current_index: int = pending[head]
		head += 1
		var current := Vector2i(current_index % data.size.x, floori(float(current_index) / float(data.size.x)))
		var current_distance := distances[current_index]
		if command == Command.MOVE_TO_EDGE and not goal_published and _command_goal_pending and _is_command_goal_candidate(current, start):
			# BFS has already discovered the entire nearest distance layer. The
			# normal goal selector retains its stable tie-break and parent route.
			_distance_origin = start
			_distance_values = distances
			_distance_parents = parents
			goal_published = true
			_advance_command_goal()
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			# The command route is terrain topology. A temporary NPC may block
			# execution, but cannot turn a reachable goal into cached UNREACHABLE.
			if not data.contains(next) or not data.can_step(current, next):
				continue
			var next_index := data.index(next)
			if distances[next_index] >= 0:
				continue
			distances[next_index] = current_distance + 1
			parents[next_index] = current_index
			pending[tail] = next_index
			tail += 1
	_distance_origin = start
	_distance_values = distances
	_distance_parents = parents
	_distance_job_pending = false

func _is_command_goal_candidate(cell: Vector2i, leader: Vector2i) -> bool:
	if _is_external_cell(cell):
		return false
	if command == Command.MOVE_TO_EDGE:
		return _edge_distance(cell) == 0
	if command != Command.FOLLOW_PLAYER or player == null:
		return false
	var distance: int = absi(cell.x - player.terrain_cell.x) + absi(cell.y - player.terrain_cell.y)
	if distance < FOLLOW_DISTANCE or distance > FOLLOW_TRIGGER:
		return false
	return cell == leader or not _cell_owners.has(cell) or _can_captain_swap_with(int(_cell_owners[cell]))

func _publish_distance_route(goal: Vector2i) -> void:
	if _distance_origin != _formation_anchor_cell or _distance_parents.is_empty() or _distance_to_cell(goal) < 0:
		return
	_path_route.clear()
	var start_index := data.index(_formation_anchor_cell)
	var cursor := data.index(goal)
	while cursor != start_index:
		_path_route.append(Vector2i(cursor % data.size.x, floori(float(cursor) / data.size.x)))
		cursor = _distance_parents[cursor]
	_path_route.reverse()
	_path_route_owner = 0
	_path_route_goal = goal
	_path_route_cursor = 0
	_path_route_snapshot = [_formation_anchor_cell]
	_path_route_snapshot.append_array(_path_route)
	_route_revision += 1
	_path_route_snapshot_revision = _route_revision
	_ensure_passage_plan()

func _distance_to_cell(cell: Vector2i) -> int:
	if data == null or not data.contains(cell) or _distance_values.is_empty():
		return -1
	return _distance_values[data.index(cell)]

func _clear_path_job() -> void:
	_path_status = PathStatus.NONE
	_path_start = INVALID_CELL
	_path_goal = INVALID_CELL
	_path_requester = -1
	_path_previous.clear()
	_path_frontier.clear()
	_path_head = 0
	_path_tail = 0

func _clear_path_route() -> void:
	_path_route.clear()
	_path_route_owner = -1
	_path_route_goal = INVALID_CELL
	_path_route_cursor = 0
	_path_route_snapshot.clear()
	_path_route_snapshot_revision = 0

func _consume_path_route_step(index: int, cell: Vector2i) -> void:
	if _formation_march_active or _passage_active:
		return
	if index != _path_route_owner or _path_route_cursor >= _path_route.size():
		return
	if _path_route[_path_route_cursor] != cell:
		return
	_path_route_cursor += 1
	# Keep the published route after the captain reaches its goal. Followers
	# consume the same immutable corridor snapshot; clearing it here made a
	# short one-cell passage indistinguishable from ordinary open formation.

func _route_next_step(start: Vector2i, goal: Vector2i, moving_index: int) -> Vector2i:
	if moving_index != _path_route_owner or goal != _path_route_goal:
		return INVALID_CELL
	while _path_route_cursor < _path_route.size() and _path_route[_path_route_cursor] == start:
		_path_route_cursor += 1
	if _path_route_cursor >= _path_route.size():
		return INVALID_CELL
	var next := _path_route[_path_route_cursor]
	if not data.can_step(start, next):
		return INVALID_CELL
	return next

func _start_path_job(start: Vector2i, goal: Vector2i, requester: int) -> void:
	var cell_count := data.size.x * data.size.y
	_path_start = start
	_path_goal = goal
	_path_requester = requester
	_path_previous.resize(cell_count)
	_path_previous.fill(-1)
	_path_frontier.resize(cell_count)
	_path_frontier.fill(-1)
	_path_head = 0
	_path_tail = 1
	_path_frontier[0] = data.index(start)
	_path_previous[data.index(start)] = data.index(start)
	_path_status = PathStatus.PENDING

func _advance_path_job(expansion_budget: int) -> void:
	if _path_status != PathStatus.PENDING:
		return
	expansion_budget = mini(expansion_budget, _structure_expansions_remaining)
	var expansions := 0
	var goal_index := data.index(_path_goal)
	while _path_head < _path_tail and expansions < expansion_budget:
		var search_index: int = _path_frontier[_path_head]
		_path_head += 1
		expansions += 1
		_structure_expansions_remaining -= 1
		structure_search_expansions += 1
		if search_index == goal_index:
			_path_status = PathStatus.FOUND
			return
		var cell := Vector2i(search_index % data.size.x, floori(float(search_index) / float(data.size.x)))
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not data.contains(next) or not data.can_step(cell, next):
				continue
			if _is_external_cell(next) and next != _path_goal:
				continue
			var next_index := data.index(next)
			if _path_previous[next_index] >= 0:
				continue
			_path_previous[next_index] = search_index
			if _path_tail < _path_frontier.size():
				_path_frontier[_path_tail] = next_index
				_path_tail += 1
	if _path_head >= _path_tail:
		_path_status = PathStatus.UNREACHABLE

func _path_result() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if _path_status != PathStatus.FOUND:
		return result
	var start_index := data.index(_path_start)
	var current_index := data.index(_path_goal)
	while current_index != start_index:
		result.append(Vector2i(current_index % data.size.x, floori(float(current_index) / float(data.size.x))))
		current_index = _path_previous[current_index]
		if current_index < 0:
			result.clear()
			return result
	result.reverse()
	return result

func _find_path(start: Vector2i, goal: Vector2i, moving_index: int) -> Array[Vector2i]:
	# The captain owns the one asynchronous route job. Followers never launch
	# or replace it, including the trivial start==goal case.
	if moving_index != 0:
		return []
	if data == null or not data.contains(start) or not data.contains(goal):
		_path_status = PathStatus.UNREACHABLE
		return []
	if start == goal:
		# A zero-length route is a successful terminal state, not an unreachable
		# request. Keep the request metadata so callers can distinguish an
		# already-satisfied goal from a failed search.
		_clear_path_route()
		_path_start = start
		_path_goal = goal
		_path_requester = moving_index
		_path_status = PathStatus.FOUND
		return []
	var same_request := _path_start == start and _path_goal == goal and _path_requester == moving_index and _path_status != PathStatus.NONE
	if not same_request:
		_clear_path_route()
		_start_path_job(start, goal, moving_index)
	if _frame_navigation_budget_active and _detour_searches_remaining <= 0:
		return []
	if _frame_navigation_budget_active:
		_detour_searches_remaining -= 1
	_advance_path_job(PATH_EXPANSIONS_PER_STEP)
	if _path_status == PathStatus.FOUND:
		if _path_route_owner != moving_index or _path_route_goal != goal or _path_route.is_empty():
			_path_route = _path_result()
			_path_route_owner = moving_index
			_path_route_goal = goal
			_path_route_cursor = 0
			_path_route_snapshot = [_path_start]
			_path_route_snapshot.append_array(_path_route)
			_route_revision += 1
			_path_route_snapshot_revision = _route_revision
		return _path_result()
	return []

func _can_captain_swap_with(partner_index: int) -> bool:
	if not has_army() or partner_index <= 0 or partner_index >= SOLDIER_COUNT:
		return false
	var approach_yield := false
	if _passage_active and not _formation_march_active:
		if _unit_passage_phase[0] == PassagePhase.APPROACH and _unit_passage_phase[partner_index] == PassagePhase.APPROACH \
			and _unit_passage[0] == _unit_passage[partner_index] and not _passage_order_hold(0, _unit_passage[0]) \
			and _unit_passage_ticket[partner_index] > _unit_passage_ticket[0]:
			var approach: Dictionary = _passage_descriptor(_unit_passage[0]).get("approach_component", {})
			approach_yield = approach.has(cells[0]) and approach.has(cells[partner_index]) \
				and int(approach[cells[partner_index]]) == int(approach[cells[0]]) - 1 \
				and not _passage_cell_is_protected(cells[0]) and not _passage_cell_is_protected(cells[partner_index])
		# No guard is bypassed: all assigned guards have already crossed, and
		# this later ticket ends one legal approach edge BEHIND the captain.
		# Otherwise only a completely cleared receiving body may exchange.
		if not approach_yield:
			for unit: int in range(SOLDIER_COUNT):
				if not _unit_has_cleared_group(unit):
					return false
			for cell: Vector2i in [cells[0], cells[partner_index]]:
				if cell != desired_cells[0] and not _active_rally_slots().has(cell):
					return false
	if _push_lock[0] != 0 or _push_lock[partner_index] != 0:
		return false
	if has_active_swap() or _swap_cooldown > 0.0:
		return false
	if movement_state[0] == UnitState.MOVING or movement_state[0] == UnitState.SWAPPING:
		return false
	if movement_state[partner_index] == UnitState.MOVING or movement_state[partner_index] == UnitState.SWAPPING:
		return false
	var captain_cell := cells[0]
	var partner_cell := cells[partner_index]
	if _cell_owners.get(captain_cell, -1) != 0 or _cell_owners.get(partner_cell, -1) != partner_index:
		return false
	if absi(captain_cell.x - partner_cell.x) + absi(captain_cell.y - partner_cell.y) != 1:
		return false
	if not data.can_step(captain_cell, partner_cell) or not data.can_step(partner_cell, captain_cell):
		return false
	if _is_external_cell(captain_cell) or _is_external_cell(partner_cell):
		return false
	if _passage_active and not approach_yield and not _passage_unit_may_be_pushed(partner_index, captain_cell, 0):
		# A cleared follower must not be exchanged back onto its protected core.
		return false
	if _reserved_cells.has(captain_cell) or _reserved_cells.has(partner_cell):
		return false
	return true

func _begin_captain_swap(partner_index: int) -> bool:
	if not _can_captain_swap_with(partner_index):
		return false
	var captain_cell := cells[0]
	var partner_cell := cells[partner_index]
	swap_partner[0] = partner_index
	swap_partner[partner_index] = 0
	moving_to[0] = partner_cell
	moving_to[partner_index] = captain_cell
	move_progress[0] = 0.0
	move_progress[partner_index] = 0.0
	blocked_time[0] = 0.0
	blocked_time[partner_index] = 0.0
	movement_state[0] = UnitState.SWAPPING
	movement_state[partner_index] = UnitState.SWAPPING
	facing[0] = partner_cell - captain_cell
	facing[partner_index] = captain_cell - partner_cell
	# Reserve both destinations as a pair. No third unit may enter either
	# source cell while the atomic exchange is in progress.
	_reserved_cells[captain_cell] = partner_index
	_reserved_cells[partner_cell] = 0
	_swap_cooldown = SWAP_COOLDOWN
	_visual_dirty = true
	return true

func _clear_reservation(cell: Vector2i, reservation_owner: int) -> void:
	if _reserved_cells.has(cell) and int(_reserved_cells[cell]) == reservation_owner:
		_reserved_cells.erase(cell)

func _prune_stale_reservations() -> void:
	# A reservation is live only for an in-flight destination, an atomic swap,
	# or a waiting requester whose published target is the occupied source. This
	# removes claims left by a cancelled blocker without touching other units'
	# destinations.
	var stale: Array[Vector2i] = []
	for cell: Vector2i in _reserved_cells:
		var reservation_owner := int(_reserved_cells[cell])
		var live := false
		for pending: Dictionary in _pending_pushes:
			var pending_path: Array = pending.get("cells", [])
			if int(pending.get("requester", -1)) == reservation_owner and not pending_path.is_empty() and pending_path[0] == cell:
				live = true
				break
			var pending_units: Array = pending.get("units", [])
			for pending_index: int in range(pending_units.size()):
				if int(pending_units[pending_index]) == reservation_owner and pending_index + 1 < pending_path.size() and pending_path[pending_index + 1] == cell:
					live = true
					break
			if live:
				break
		if reservation_owner >= 0 and reservation_owner < SOLDIER_COUNT:
			if (movement_state[reservation_owner] == UnitState.MOVING or movement_state[reservation_owner] == UnitState.SWAPPING) and moving_to[reservation_owner] == cell:
				live = true
		if not live:
			stale.append(cell)
	for cell: Vector2i in stale:
		_reserved_cells.erase(cell)

func _has_active_follower_swap() -> bool:
	return _follower_swap_a > 0 and _follower_swap_b > 0

func _can_follower_swap(first: int, second: int) -> bool:
	if (formation_mode != FormationMode.COLUMN and formation_mode != FormationMode.OPEN) or first <= 0 or second <= 0 or first >= SOLDIER_COUNT or second >= SOLDIER_COUNT or first == second:
		return false
	if _push_lock[first] != 0 or _push_lock[second] != 0:
		return false
	if has_active_swap() or _has_active_follower_swap() or _swap_cooldown > 0.0:
		return false
	if movement_state[first] != UnitState.IDLE and movement_state[first] != UnitState.WAITING:
		return false
	if movement_state[second] != UnitState.IDLE and movement_state[second] != UnitState.WAITING:
		return false
	var first_cell := cells[first]
	var second_cell := cells[second]
	if _cell_owners.get(first_cell, -1) != first or _cell_owners.get(second_cell, -1) != second:
		return false
	if _passage_active and (not _passage_unit_may_be_pushed(first, second_cell, first) or not _passage_unit_may_be_pushed(second, first_cell, second)):
		return false
	if absi(first_cell.x - second_cell.x) + absi(first_cell.y - second_cell.y) != 1:
		return false
	if not data.can_step(first_cell, second_cell) or not data.can_step(second_cell, first_cell):
		return false
	if _is_external_cell(first_cell) or _is_external_cell(second_cell):
		return false
	if _reserved_cells.has(first_cell) or _reserved_cells.has(second_cell):
		return false
	# Either adjacent queue rank may exchange when the existing deployment has
	# folded around a ramp. The fixed planning order plus cooldown prevents an
	# oscillating pair while allowing a trapped rank to reach the next opening.
	return true

func _begin_follower_swap(first: int, second: int) -> bool:
	if not _can_follower_swap(first, second):
		return false
	var first_cell := cells[first]
	var second_cell := cells[second]
	_follower_swap_a = first
	_follower_swap_b = second
	swap_partner[first] = second
	swap_partner[second] = first
	moving_to[first] = second_cell
	moving_to[second] = first_cell
	move_progress[first] = 0.0
	move_progress[second] = 0.0
	move_duration[first] = MOVE_DURATION
	move_duration[second] = MOVE_DURATION
	locomotion_mode[first] = Locomotion.WALK
	locomotion_mode[second] = Locomotion.WALK
	blocked_time[first] = 0.0
	blocked_time[second] = 0.0
	movement_state[first] = UnitState.SWAPPING
	movement_state[second] = UnitState.SWAPPING
	facing[first] = second_cell - first_cell
	facing[second] = first_cell - second_cell
	_reserved_cells[first_cell] = second
	_reserved_cells[second_cell] = first
	_swap_cooldown = SWAP_COOLDOWN
	_visual_dirty = true
	return true

func _complete_follower_swap() -> void:
	if not _has_active_follower_swap():
		return
	var first := _follower_swap_a
	var second := _follower_swap_b
	var first_cell := cells[first]
	var second_cell := cells[second]
	if not data.can_step(first_cell, second_cell) or not data.can_step(second_cell, first_cell):
		_movement_contract_error("follower swap", first, first_cell, second_cell)
		return
	if _cell_owners.get(first_cell, -1) != first or _cell_owners.get(second_cell, -1) != second:
		_movement_contract_error("follower swap", first, first_cell, second_cell)
		return
	cells[first] = second_cell
	cells[second] = first_cell
	_cell_owners[first_cell] = second
	_cell_owners[second_cell] = first
	_record_passage_commit(first, first_cell, second_cell)
	_record_passage_commit(second, second_cell, first_cell)
	_clear_reservation(first_cell, second)
	_clear_reservation(second_cell, first)
	for index: int in [first, second]:
		swap_partner[index] = -1
		moving_to[index] = INVALID_CELL
		move_progress[index] = 0.0
		move_duration[index] = MOVE_DURATION
		locomotion_mode[index] = Locomotion.IDLE
		blocked_time[index] = 0.0
		movement_state[index] = UnitState.ARRIVED if cells[index] == desired_cells[index] else UnitState.IDLE
	_follower_swap_a = -1
	_follower_swap_b = -1
	_swap_count += 1
	_completed_steps += 2
	_visual_dirty = true

func _complete_swap() -> void:
	if not has_active_swap():
		return
	var partner_index := swap_partner[0]
	var captain_cell := cells[0]
	var partner_cell := cells[partner_index]
	if not data.can_step(captain_cell, partner_cell) or not data.can_step(partner_cell, captain_cell):
		_movement_contract_error("captain swap", 0, captain_cell, partner_cell)
		return
	if _cell_owners.get(captain_cell, -1) != 0 or _cell_owners.get(partner_cell, -1) != partner_index:
		_movement_contract_error("captain swap", 0, captain_cell, partner_cell)
		return
	# Commit both owner changes together. There is no intermediate frame in
	# which the captain occupies the partner's cell while the partner still
	# owns it, so uniqueness remains true for every simulation observation.
	cells[0] = partner_cell
	cells[partner_index] = captain_cell
	_record_passage_commit(0, captain_cell, partner_cell)
	_record_passage_commit(partner_index, partner_cell, captain_cell)
	_consume_path_route_step(0, partner_cell)
	if _captain_trail.is_empty() or _captain_trail.back() != partner_cell:
		_captain_trail.append(partner_cell)
		_captain_trail_progress_cache.clear()
	_cell_owners[captain_cell] = partner_index
	_cell_owners[partner_cell] = 0
	_clear_reservation(captain_cell, partner_index)
	_clear_reservation(partner_cell, 0)
	for index: int in [0, partner_index]:
		swap_partner[index] = -1
		moving_to[index] = INVALID_CELL
		move_progress[index] = 0.0
		move_duration[index] = MOVE_DURATION
		locomotion_mode[index] = Locomotion.IDLE
		blocked_time[index] = 0.0
		movement_state[index] = UnitState.IDLE
		if cells[index] == desired_cells[index] and command == Command.MOVE_TO_EDGE:
			movement_state[index] = UnitState.ARRIVED
	_swap_count += 1
	_completed_steps += 2
	_visual_dirty = true

func _unit_should_run(index: int, next: Vector2i = INVALID_CELL) -> bool:
	if index < 0 or index >= SOLDIER_COUNT or desired_cells.size() != SOLDIER_COUNT:
		return false
	if _passage_active and (_unit_passage_phase[index] == PassagePhase.IN_PASSAGE \
		or (_unit_passage_phase[index] == PassagePhase.EXIT_CLEAR and _unit_passage_exit_clear[index] == 0)):
		return false
	var goal := _activity_goal(index)
	if goal == INVALID_CELL:
		return false
	var lag := _activity_distance(index)
	if lag < FORMATION_RUN_LAG:
		return false
	if next == INVALID_CELL:
		var difference := goal - cells[index]
		next = cells[index] + (Vector2i(signi(difference.x), 0) if difference.x != 0 else Vector2i(0, signi(difference.y)))
	# A distant endpoint never gives the captain a sprint privilege. Running
	# means a legal local catch-up edge, including a rear unit after a long wait.
	if index == 0 and not _formation_march_active and not _passage_active:
		return false
	return data.can_step(cells[index], next) and not _is_external_cell(next) \
		and (not _cell_owners.has(next) or int(_cell_owners[next]) == index) \
		and (not _reserved_cells.has(next) or int(_reserved_cells[next]) == index) \
		and data.height_levels[data.index(cells[index])] == data.height_levels[data.index(next)] \
		and _route_edge_width(cells[index], next) > PASSAGE_MAX_NARROW_WIDTH

func _activity_goal(index: int) -> Vector2i:
	if _passage_active and not _formation_march_active and _unit_passage_phase[index] == PassagePhase.APPROACH:
		return _passage_descriptor(_unit_passage[index]).get("entry", INVALID_CELL)
	return desired_cells[index]

func _activity_distance(index: int) -> int:
	# Reuse the paid route, or verify at most two short rectilinear paths.
	# Unknown is not zero/one: a neighbour across a wall never means caught up.
	var goal := _activity_goal(index)
	var source := cells[index]
	if goal == INVALID_CELL:
		return -1
	if source == goal:
		return 0
	if _passage_active and not _formation_march_active and _unit_passage_phase[index] == PassagePhase.APPROACH:
		var approach: Dictionary = _passage_descriptor(_unit_passage[index]).get("approach_component", {})
		return int(approach.get(source, -1))
	if _activity_distance_tick != _passage_tick:
		_activity_distance_tick = _passage_tick
		_activity_distances.clear()
	var key := Vector4i(source.x, source.y, goal.x, goal.y)
	if _activity_distances.has(key):
		return int(_activity_distances[key])
	var route: Array = _follower_routes.get(index, [])
	var cursor := int(_follower_route_cursors.get(index, 0))
	if _follower_route_goals.get(index, INVALID_CELL) == goal and cursor >= 1 and cursor < route.size() and route[cursor - 1] == source:
		var remaining := route.size() - cursor
		_activity_distances[key] = remaining
		return remaining
	var length := absi(source.x - goal.x) + absi(source.y - goal.y)
	if length <= FORMATION_REFORM_DISTANCE * 2:
		for horizontal_first: bool in [true, false]:
			var current := source
			while current != goal:
				var difference := goal - current
				var horizontal := difference.x != 0 and (horizontal_first or difference.y == 0)
				var next := current + (Vector2i(signi(difference.x), 0) if horizontal else Vector2i(0, signi(difference.y)))
				if not data.can_step(current, next):
					break
				current = next
			if current == goal:
				_activity_distances[key] = length
				return length
	_activity_distances[key] = -1
	return -1

func _step_duration_for(index: int) -> float:
	return RUN_DURATION if _unit_should_run(index) else MOVE_DURATION

func _find_yield_cell(index: int) -> Vector2i:
	if index <= 0 or index >= SOLDIER_COUNT:
		return INVALID_CELL
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var candidate := cells[index] + direction
		if not data.can_step(cells[index], candidate) or _is_external_cell(candidate):
			continue
		if _cell_owners.has(candidate) or _reserved_cells.has(candidate):
			continue
		return candidate
	return INVALID_CELL

func _find_push_chain(start_cell: Vector2i, avoid_index: int) -> Array[Vector2i]:
	var result := _search_push_requests({avoid_index: start_cell})
	var path: Array[Vector2i] = []
	path.assign(result.get("path", []))
	return path

func _search_push_requests(requests: Dictionary) -> Dictionary:
	# One multi-source breadth-first search, one <=512 expansion budget, and
	# at most one selected transaction. A blocked first requester cannot hide a
	# shorter ready vacancy chain elsewhere in the same packed formation.
	if data == null or _push_searches_remaining <= 0:
		return {}
	_push_searches_remaining -= 1
	push_search_requests += 1
	var pending: Array[Vector2i] = [] # (terrain cell index, requester id)
	var previous := {}
	var rally_min := Vector2i(1 << 29, 1 << 29)
	var rally_max := Vector2i(-(1 << 29), -(1 << 29))
	var limit_open_endpoints := not _passage_active and not _formation_has_bottleneck and command != Command.NONE and has_army() and cells[0] == desired_cells[0]
	if limit_open_endpoints:
		for slot: Vector2i in _formation_slot_cells.slice(1):
			if slot != INVALID_CELL:
				rally_min = rally_min.min(slot)
				rally_max = rally_max.max(slot)
	for requester: int in requests:
		var source: Vector2i = requests[requester]
		if not data.contains(source):
			continue
		var key := Vector2i(data.index(source), requester)
		pending.append(key)
		previous[key] = INVALID_CELL
	var head := 0
	var terminal_key := INVALID_CELL
	var terminal_cell := INVALID_CELL
	while head < pending.size() and head < 512:
		var key := pending[head]
		head += 1
		var current := Vector2i(key.x % data.size.x, floori(float(key.x) / data.size.x))
		var requester := key.y
		var current_owner := int(_cell_owners.get(current, -1))
		if current_owner < 0 or (current_owner == 0 and not _passage_active) or current_owner == requester or _push_lock[current_owner] != 0 or movement_state[current_owner] == UnitState.MOVING or movement_state[current_owner] == UnitState.SWAPPING:
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if not data.contains(next) or not data.can_step(current, next) or _is_external_cell(next) or _reserved_cells.has(next):
				continue
			var next_key := Vector2i(data.index(next), requester)
			if previous.has(next_key) or not _push_preserves_open_slots(current, next):
				continue
			if _passage_active and not _passage_unit_may_be_pushed(current_owner, next, requester):
				continue
			var next_owner := int(_cell_owners.get(next, -1))
			if next_owner < 0:
				var endpoint_allowed := _push_endpoint_allowed(next)
				var root_cell: Vector2i = requests[requester]
				if _passage_active and _passage_final_egress_cell(root_cell) and not _passage_final_egress_cell(next):
					endpoint_allowed = false
				if limit_open_endpoints:
					var root_offset := (root_cell - root_cell.clamp(rally_min, rally_max)).abs()
					var endpoint_offset := (next - next.clamp(rally_min, rally_max)).abs()
					var root_distance := root_offset.x + root_offset.y
					if root_distance > 0 and endpoint_offset.x + endpoint_offset.y >= root_distance:
						endpoint_allowed = false
				if endpoint_allowed:
					terminal_key = key
					terminal_cell = next
					break
				# A vacancy is terminal even when it is forbidden as an endpoint.
				continue
			if (next_owner == 0 and not _passage_active) or next_owner == requester or _push_lock[next_owner] != 0 or movement_state[next_owner] == UnitState.MOVING or movement_state[next_owner] == UnitState.SWAPPING:
				continue
			previous[next_key] = key
			pending.append(next_key)
		if terminal_key != INVALID_CELL:
			break
	push_search_expansions += head
	max_push_search_expansions = maxi(max_push_search_expansions, head)
	if terminal_key == INVALID_CELL:
		return {}
	var selected_requester := terminal_key.y
	var path: Array[Vector2i] = [terminal_cell]
	while terminal_key != INVALID_CELL:
		path.push_front(Vector2i(terminal_key.x % data.size.x, floori(float(terminal_key.x) / data.size.x)))
		terminal_key = previous[terminal_key]
	return {"requester": selected_requester, "path": path}

func _push_endpoint_allowed(cell: Vector2i) -> bool:
	if data == null or not data.contains(cell) or not data.is_walkable(cell) or _cell_owners.has(cell) or _reserved_cells.has(cell) or _is_external_cell(cell):
		return false
	if _passage_active and _passage_cell_is_protected(cell):
		return false
	# While a passage is active, intermediate platform pushes may end outside
	# the final rally set. The passage/component checks below own that boundary;
	# the legacy exit-slot filter only applies after the passage is gone.
	if not _passage_active and _exit_rally_assigned and captain_at_boundary() and not _exit_rally_slots.has(cell):
		return false
	return true

func _push_preserves_open_slots(source: Vector2i, destination: Vector2i) -> bool:
	if _passage_active:
		# The published ordinary slot list has 99 entries; the captain's fixed
		# centre is the hundredth legal receiving cell, not outside the body.
		var source_inside := source == desired_cells[0] or _active_rally_slots().has(source)
		return not source_inside or destination == desired_cells[0] or _active_rally_slots().has(destination)
	if _formation_has_bottleneck or command == Command.NONE or not has_army() or cells[0] != desired_cells[0]:
		return true
	return not _formation_slot_cells.has(source) or _formation_slot_cells.has(destination)

func _unit_has_cleared_passages(index: int) -> bool:
	if index < 0 or index >= SOLDIER_COUNT or _unit_passage_phase.size() != SOLDIER_COUNT:
		return false
	if _unit_completed_exits.size() != SOLDIER_COUNT or _unit_completed_exits[index] != _passage_descriptors.size():
		return false
	return _unit_passage_phase[index] == PassagePhase.RALLY or _unit_passage_phase[index] == PassagePhase.EXEMPT \
		or (_unit_passage_phase[index] == PassagePhase.EXIT_CLEAR and _unit_passage[index] == _passage_descriptors.size() - 1 and _unit_passage_exit_clear[index] != 0)

func _passage_unit_may_be_pushed(index: int, destination: Vector2i, requester: int = -1) -> bool:
	if not _passage_active or index < 0 or index >= SOLDIER_COUNT or _unit_passage_phase.size() != SOLDIER_COUNT:
		return true
	if _formation_march_active:
		return not _passage_cell_is_protected(destination) and _passage_march_field().has(destination)
	var phase := int(_unit_passage_phase[index])
	var unit_passage_index := int(_unit_passage[index])
	if phase == PassagePhase.APPROACH:
		if requester >= 0 and _unit_passage_phase[requester] == PassagePhase.APPROACH and _passage_order_hold(requester, unit_passage_index) \
			and _unit_passage_ticket[index] < _unit_passage_ticket[requester]:
			return false
		if _passage_order_hold(index, unit_passage_index):
			var approach: Dictionary = _passage_descriptor(unit_passage_index).get("approach_component", {})
			var floor_depth := _passage_approach_floor(index, unit_passage_index)
			# A predecessor's legal detour can move the queue floor behind an
			# already waiting member. Let a push retreat one edge toward that
			# floor; requiring it to reach the new floor in one edge deadlocks it.
			var minimum_depth := mini(floor_depth, int(approach.get(cells[index], -1)) + 1)
			if int(approach.get(destination, -1)) < minimum_depth:
				return false
	if phase == PassagePhase.IN_PASSAGE:
		# An in-passage blocker can only be displaced along its own corridor's
		# next edge. This keeps a queued unit moving forward without opening a
		# path that could eject it back across a protected gate.
		var passage_index := int(_unit_passage[index])
		var descriptor := _passage_descriptor(passage_index)
		var corridor: Array = descriptor.get("corridor", [])
		var cursor := -1
		for route_index: int in range(corridor.size()):
			if corridor[route_index] == cells[index]:
				cursor = route_index
				break
		if cursor < 0 or cursor + 1 >= corridor.size():
			return false
		return destination == corridor[cursor + 1]
	var authorized_entry := false
	if phase == PassagePhase.APPROACH and requester == index and unit_passage_index >= 0:
		var entry: Vector2i = _passage_descriptor(unit_passage_index).get("entry", INVALID_CELL)
		authorized_entry = destination == entry and not _passage_order_hold(index, unit_passage_index)
	elif phase == PassagePhase.EXIT_CLEAR and requester == index and unit_passage_index < _passage_group_end:
		# In a merged small-platform group the old exit may be adjacent to
		# the next entry. Claiming that vacant mouth is not a core admission;
		# requiring the NEXT core to be empty here deadlocked an already
		# committed vacancy transaction behind its own downstream queue.
		var next_passage := unit_passage_index + 1
		authorized_entry = destination == _passage_descriptor(next_passage).get("entry", INVALID_CELL) \
			and not _passage_order_hold(index, next_passage)
	if _passage_cell_is_protected(destination) and not authorized_entry:
		return false
	if phase == PassagePhase.APPROACH:
		# A downstream spawn whose current entry is structurally unreachable is
		# intentionally held until the rest of the queue has cleared that gate;
		# pushing it toward the protected entry would make it occupy the gate and
		# block otherwise eligible tickets.
		return not _passage_approach_must_wait(index)
	if phase != PassagePhase.EXIT_CLEAR and phase != PassagePhase.RALLY and phase != PassagePhase.EXEMPT:
		return false
	# A follower already sitting on its assigned final slot is settled. Do not
	# eject it to satisfy another identity; the idle binding repair handles a
	# complete permutation without moving terrain-valid occupants.
	if phase == PassagePhase.RALLY or phase == PassagePhase.EXEMPT:
		# RALLY identities solve a remaining permutation by free-cell routing or
		# the idle binding repair. A mismatched RALLY requester may also displace a
		# settled rally unit when its own published slot is the only vacancy; the
		# bounded push opens that slot without changing the slot set.
		var rally_requester := requester >= 0 and requester < SOLDIER_COUNT \
			and _unit_has_cleared_group(requester) \
			and _rally_requester_may_displace(requester)
		return requester >= 0 and requester < SOLDIER_COUNT \
			and (_unit_passage_phase[requester] == PassagePhase.EXIT_CLEAR or rally_requester) \
			and _active_rally_component().has(cells[index]) and _active_rally_component().has(destination) \
			and not _passage_cell_is_protected(cells[index])
	# Use the published terrain distance to the next entry, not height or a
	# nearest-trail guess. A legal displacement must not undo inter-gate progress.
	if unit_passage_index < _passage_group_end:
		var approach: Dictionary = _passage_descriptor(unit_passage_index + 1).get("approach_component", {})
		return approach.has(cells[index]) and approach.has(destination) \
			and int(approach[destination]) <= int(approach[cells[index]])
	return _passage_final_egress_cell(cells[index]) and _passage_final_egress_cell(destination)

func _rally_requester_may_displace(requester: int) -> bool:
	if requester < 0 or requester >= SOLDIER_COUNT or _unit_passage_phase.size() != SOLDIER_COUNT:
		return false
	if not _unit_has_cleared_group(requester) or cells[requester] == desired_cells[requester]:
		return false
	# Ordinary idle occupants can exchange bindings, but the captain's centre
	# is fixed. If displaced onto another slot, he must physically fill the
	# remaining centre vacancy through the same bounded push transaction.
	return _active_rally_component().has(cells[requester]) \
		and (requester == 0 or not _active_rally_slots().has(cells[requester]))

func _schedule_push_unit(index: int, destination: Vector2i, requester: int = -1) -> bool:
	if index < 0 or (index == 0 and not _passage_active) or index >= SOLDIER_COUNT or movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING:
		return false
	if _push_lock[index] != 0:
		var authorized := false
		for pending: Dictionary in _pending_pushes:
			if int(pending.requester) != requester:
				continue
			if index == requester:
				authorized = destination == pending.cells[0]
			else:
				var member: int = pending.units.find(index)
				authorized = member >= 0 and destination == pending.cells[member + 1]
			break
		if not authorized:
			return false
	if _passage_active and not _passage_unit_may_be_pushed(index, destination, requester):
		return false
	var source := cells[index]
	if _cell_owners.get(source, -1) != index or not data.can_step(source, destination):
		return false
	if not _push_preserves_open_slots(source, destination):
		return false
	# Once the exit-side set is published, a push may rearrange identities inside
	# that set or bring a unit into an empty slot, but it must not eject a unit
	# that has already cleared the passage back onto the protected trail.
	var passage_exit_displacement := _passage_active and requester >= 0 and requester < SOLDIER_COUNT \
		and _unit_passage_phase.size() == SOLDIER_COUNT and _unit_passage_phase[requester] == PassagePhase.EXIT_CLEAR
	if _exit_rally_assigned and captain_at_boundary() and _exit_rally_slots.has(source) and not _exit_rally_slots.has(destination) and not passage_exit_displacement:
		return false
	if _is_external_cell(destination) or _cell_owners.has(destination) or (_reserved_cells.has(destination) and int(_reserved_cells[destination]) != index):
		return false
	_reserved_cells[destination] = index
	moving_to[index] = destination
	move_progress[index] = 0.0
	move_duration[index] = MOVE_DURATION
	locomotion_mode[index] = Locomotion.WALK
	blocked_time[index] = 0.0
	movement_state[index] = UnitState.MOVING
	facing[index] = destination - source
	_visual_dirty = true
	return true

func _has_pending_push(requester: int) -> bool:
	for pending: Dictionary in _pending_pushes:
		if int(pending.get("requester", -1)) == requester:
			return true
	return false

func _pending_push_matches_claims(pending: Dictionary) -> bool:
	var path: Array = pending.get("cells", [])
	var units: Array = pending.get("units", [])
	if path.size() < 2 or units.size() != path.size() - 1:
		return false
	var cursor := int(pending.get("cursor", -1))
	var committed: Dictionary = pending.get("committed", {})
	for unit_position: int in range(units.size()):
		var unit := int(units[unit_position])
		if unit < 0 or unit >= SOLDIER_COUNT:
			return false
		if committed.has(unit):
			continue
		var expected_destination: Vector2i = path[unit_position + 1]
		if movement_state[unit] == UnitState.MOVING or movement_state[unit] == UnitState.SWAPPING:
			if moving_to[unit] != expected_destination:
				return false
		if _push_lock[unit] == 0:
			return false
		if unit_position <= cursor and _cell_owners.get(path[unit_position], -1) != unit and movement_state[unit] != UnitState.MOVING:
			return false
	var requester := int(pending.get("requester", -1))
	if requester < 0 or requester >= SOLDIER_COUNT or _push_lock[requester] == 0:
		return false
	if movement_state[requester] == UnitState.MOVING or movement_state[requester] == UnitState.SWAPPING:
		if moving_to[requester] != path[0]:
			return false
	return cursor >= -1 and cursor < units.size()

func _queue_push_chain(requester: int, path: Array[Vector2i]) -> bool:
	# Passage admission remains serialized; independent OPEN vacancy chains
	# are safe to overlap only after every participant and claim is checked.
	if requester < 0 or (requester == 0 and not _passage_active) or path.size() < 2 or _has_pending_push(requester):
		return false
	if _passage_active and not _formation_march_active and not _pending_pushes.is_empty() and not _unit_has_cleared_group(requester):
		return false
	if requester >= SOLDIER_COUNT or movement_state.size() != SOLDIER_COUNT or _push_lock.size() != SOLDIER_COUNT:
		return false
	if movement_state[requester] == UnitState.MOVING or movement_state[requester] == UnitState.SWAPPING:
		return false
	if _passage_active and _unit_passage_phase.size() == SOLDIER_COUNT:
		var requester_phase := int(_unit_passage_phase[requester])
		if requester_phase in [PassagePhase.EXEMPT, PassagePhase.RALLY] and not _rally_requester_may_displace(requester):
			# Once the requester has cleared the corridor, settle or rebind the
			# published exit slots; only a mismatched unit with an empty slot may
			# start a bounded final-egress displacement.
			return false
	if not data.can_step(cells[requester], path[0]) or absi(cells[requester].x - path[0].x) + absi(cells[requester].y - path[0].y) != 1:
		return false
	if _passage_active and not _passage_unit_may_be_pushed(requester, path[0], requester):
		return false
	if not _push_endpoint_allowed(path.back()):
		return false
	var seen_cells := {}
	var units: Array[int] = []
	for path_index: int in range(path.size() - 1):
		var source: Vector2i = path[path_index]
		var destination: Vector2i = path[path_index + 1]
		if not _push_preserves_open_slots(source, destination):
			return false
		if seen_cells.has(source) or not data.contains(source) or not data.is_walkable(source) or not data.can_step(source, destination):
			return false
		seen_cells[source] = true
		var blocking_owner := int(_cell_owners.get(path[path_index], -1))
		if blocking_owner < 0:
			return false
		if blocking_owner == requester or (blocking_owner == 0 and not _passage_active):
			return false
		if blocking_owner >= _push_lock.size() or _push_lock[blocking_owner] != 0:
			return false
		if movement_state[blocking_owner] == UnitState.MOVING or movement_state[blocking_owner] == UnitState.SWAPPING:
			return false
		if _reserved_cells.has(source):
			return false
		if _passage_active and not _passage_unit_may_be_pushed(blocking_owner, destination, requester):
			return false
		units.append(blocking_owner)
	if seen_cells.has(path.back()) or not data.contains(path.back()) or not data.is_walkable(path.back()):
		return false
	seen_cells[path.back()] = true
	if requester >= _push_lock.size() or _push_lock[requester] != 0:
		return false
	# The first occupied cell belongs to the requester for the whole
	# transaction. This prevents a second queue or ordinary move from filling
	# the only cell that the requester is waiting to consume.
	_reserved_cells[path[0]] = requester
	for path_index: int in range(units.size()):
		var destination := path[path_index + 1]
		var unit_owner := units[path_index]
		if _reserved_cells.has(destination) and int(_reserved_cells[destination]) != unit_owner:
			_clear_reservation(path[0], requester)
			for previous_index: int in range(path_index):
				_clear_reservation(path[previous_index + 1], units[previous_index])
			return false
		_reserved_cells[destination] = unit_owner
	var last_unit: int = units.back()
	if not _schedule_push_unit(last_unit, path.back(), requester):
		_clear_reservation(path[0], requester)
		for path_index: int in range(units.size()):
			_clear_reservation(path[path_index + 1], units[path_index])
		return false
	for unit: int in units:
		_push_lock[unit] = 1
	_push_lock[requester] = 1
	_pending_pushes.append({
		"requester": requester,
		"cells": path,
		"units": units,
		"cursor": units.size() - 2,
		"age": 0.0,
		"committed": {},
		"command_epoch": _command_epoch,
		"route_revision": _route_revision,
	})
	return true

func _release_push_transaction(pending: Dictionary, _cancel_moving: bool = false) -> void:
	var units: Array = pending.get("units", [])
	var pending_path: Array = pending.get("cells", [])
	var committed: Dictionary = pending.get("committed", {})
	for path_index: int in range(units.size()):
		if path_index + 1 < pending_path.size():
			var owner := int(units[path_index])
			if committed.has(owner):
				continue
			var destination: Vector2i = pending_path[path_index + 1]
			if owner < 0 or owner >= SOLDIER_COUNT:
				continue
			var in_flight := movement_state[owner] == UnitState.MOVING or movement_state[owner] == UnitState.SWAPPING
			if not in_flight or moving_to[owner] != destination:
				_clear_reservation(destination, owner)
	for unit_value: Variant in units:
		var unit := int(unit_value)
		if committed.has(unit):
			continue
		if unit < 0 or unit >= SOLDIER_COUNT:
			continue
		if unit < _push_lock.size():
			_push_lock[unit] = 0
	var requester := int(pending.get("requester", -1))
	if requester >= 0 and requester < SOLDIER_COUNT and not pending_path.is_empty():
		var in_flight := movement_state[requester] == UnitState.MOVING or movement_state[requester] == UnitState.SWAPPING
		if not in_flight or moving_to[requester] != pending_path[0]:
			_clear_reservation(pending_path[0], requester)
	if requester >= 0 and requester < _push_lock.size():
		_push_lock[requester] = 0

func _advance_pending_pushes() -> void:
	for pending_index: int in range(_pending_pushes.size() - 1, -1, -1):
		var pending: Dictionary = _pending_pushes[pending_index]
		pending["age"] = float(pending.get("age", 0.0)) + SIM_STEP
		if int(pending.get("command_epoch", _command_epoch)) != _command_epoch \
			or int(pending.get("route_revision", _route_revision)) != _route_revision \
			or not _pending_push_matches_claims(pending):
			# A command change or an invalidated stale claim must not leave a
			# requester locked behind a different ordinary move. In-flight moves
			# keep their own destination claim; only this transaction's unstarted
			# locks are released.
			_release_push_transaction(pending, false)
			_pending_pushes.remove_at(pending_index)
			continue
		if float(pending["age"]) >= PUSH_TRANSACTION_TIMEOUT:
			# Only real commits reset age. Cancellation already preserves active
			# edges and their claims, so a slow/in-flight member is no exemption.
			_release_push_transaction(pending, false)
			_pending_pushes.remove_at(pending_index)
			continue
		var cursor := int(pending.get("cursor", -1))
		if cursor < 0:
			# All blockers have shifted one cell. The transaction is not complete
			# until its requester consumes the newly released source cell; releasing
			# the lock here leaves the requester waiting behind the same queue and
			# recreates the one-cell passage deadlock.
			var requester := int(pending.get("requester", -1))
			var request_path: Array = pending.get("cells", [])
			if requester >= 0 and request_path.size() >= 2:
				if movement_state[requester] == UnitState.MOVING or movement_state[requester] == UnitState.SWAPPING:
					_pending_pushes[pending_index] = pending
					continue
				if cells[requester] == request_path[0]:
					_release_push_transaction(pending)
					_pending_pushes.remove_at(pending_index)
					continue
				if not data.can_step(cells[requester], request_path[0]) or _is_external_cell(request_path[0]):
					_release_push_transaction(pending, true)
					_pending_pushes.remove_at(pending_index)
					continue
				if _cell_owners.has(request_path[0]) or (_reserved_cells.has(request_path[0]) and int(_reserved_cells[request_path[0]]) != requester):
					_pending_pushes[pending_index] = pending
					continue
				if _schedule_push_unit(requester, request_path[0], requester):
					pending["requester_scheduled"] = true
					_pending_pushes[pending_index] = pending
					continue
				_pending_pushes[pending_index] = pending
				continue
			_release_push_transaction(pending, true)
			_pending_pushes.remove_at(pending_index)
			continue
		var path: Array = pending.get("cells", [])
		var units: Array = pending.get("units", [])
		if cursor + 2 >= path.size() or cursor + 1 >= units.size():
			_release_push_transaction(pending)
			_pending_pushes.remove_at(pending_index)
			continue
		var downstream_unit := int(units[cursor + 1])
		var committed: Dictionary = pending.get("committed", {})
		if not committed.has(downstream_unit):
			continue
		var index := int(units[cursor])
		var source: Vector2i = path[cursor]
		var destination: Vector2i = path[cursor + 1]
		if cells[index] != source or _cell_owners.get(source, -1) != index:
			_release_push_transaction(pending, true)
			_pending_pushes.remove_at(pending_index)
			continue
		var pending_requester := int(pending.get("requester", -1))
		if _schedule_push_unit(index, destination, pending_requester):
			cursor -= 1
			pending["cursor"] = cursor
			_pending_pushes[pending_index] = pending

func _schedule_follower_blocker(index: int, _delta: float, _visiting: Dictionary, _depth: int = 0, requester: int = -1) -> bool:
	if requester < 0 or index < 0 or ((requester == 0 or index == 0) and not _passage_active) or index >= SOLDIER_COUNT:
		return false
	if movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING or _push_lock[index] != 0:
		return false
	if not _passage_active and not _formation_has_bottleneck and cells[0] != desired_cells[0]:
		return false
	_push_search_ready[requester] = cells[index]
	return true

func _service_push_search() -> void:
	# Gather requests before serving one: a cached, unsatisfiable route must not
	# win the sole push search every tick merely by appearing first in the local
	# path loop. The cursor advances after success AND failure.
	var ordered: Array[int] = []
	for requester: int in _push_search_ready:
		ordered.append(requester)
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var pa := 2 if _passage_active and _unit_passage_phase[a] == PassagePhase.EXIT_CLEAR and _unit_passage_exit_clear[a] == 0 else 0
		var pb := 2 if _passage_active and _unit_passage_phase[b] == PassagePhase.EXIT_CLEAR and _unit_passage_exit_clear[b] == 0 else 0
		if pa != pb:
			return pa > pb
		return (a - _push_search_cursor + SOLDIER_COUNT - 1) % (SOLDIER_COUNT - 1) < (b - _push_search_cursor + SOLDIER_COUNT - 1) % (SOLDIER_COUNT - 1))
	var requests := {}
	for requester: int in ordered:
		var source: Vector2i = _push_search_ready[requester]
		var blocker := int(_cell_owners.get(source, -1))
		if blocker < 0 or (blocker == 0 and not _passage_active) or _push_lock[blocker] != 0 or _push_lock[requester] != 0:
			continue
		if movement_state[requester] == UnitState.MOVING or movement_state[requester] == UnitState.SWAPPING or movement_state[blocker] == UnitState.MOVING or movement_state[blocker] == UnitState.SWAPPING:
			continue
		if _reserved_cells.has(source) or not data.can_step(cells[requester], source):
			continue
		if _passage_active and not _formation_march_active and not _pending_pushes.is_empty() and not _unit_has_cleared_group(requester):
			continue
		requests[requester] = source
	# A shared BFS chooses the shortest chain, not the first root. Merely
	# sorting EXIT_CLEAR first let endless one-cell upstream pushes starve a
	# longer, legal outlet vacancy chain. Serve the urgent outlet class first.
	var urgent := {}
	for requester: int in requests:
		if _passage_active and _unit_passage_phase[requester] == PassagePhase.EXIT_CLEAR and _unit_passage_exit_clear[requester] == 0:
			urgent[requester] = requests[requester]
	if urgent.is_empty() and _passage_active and not _formation_march_active:
		# Held rear ranks must not win endless short vacancy chains while the
		# last eligible guard needs a longer one to open the actual entrance.
		for requester: int in requests:
			if _unit_passage_phase[requester] == PassagePhase.APPROACH \
				and not _passage_order_hold(requester, int(_unit_passage[requester])):
				urgent[requester] = requests[requester]
	if not urgent.is_empty():
		requests = urgent
	if not requests.is_empty():
		var result := _search_push_requests(requests)
		var requester := int(result.get("requester", requests.keys()[0]))
		_push_search_cursor = requester % (SOLDIER_COUNT - 1) + 1
		var path: Array[Vector2i] = []
		path.assign(result.get("path", []))
		push_search_queued += int(_queue_push_chain(requester, path))
	_push_search_ready.clear()

func _unit_is_before_bottleneck(index: int) -> bool:
	if not captain_at_boundary() or data == null or index <= 0 or index >= SOLDIER_COUNT or not data.contains(cells[index]) or not data.contains(cells[0]):
		return false
	var captain_height := int(data.height_levels[data.index(cells[0])])
	return int(data.height_levels[data.index(cells[index])]) != captain_height

func _formation_planning_order(_heading: Vector2i) -> Array[int]:
	# One service cursor for every expensive follower route. Direct intents
	# still visit all 100 units; tickets separately arbitrate passage admission.
	var order: Array[int] = [0]
	for offset: int in range(SOLDIER_COUNT - 1):
		order.append(1 + ((_local_path_cursor - 1 + offset) % (SOLDIER_COUNT - 1)))
	return order

func _simulate_step(delta: float) -> void:
	if not has_army():
		return
	if not _frame_navigation_budget_active:
		_structure_expansions_remaining = PATH_EXPANSIONS_PER_STEP
		_structure_work_ready.emit()
		_advance_command_goal()
	_passage_tick += 1
	_push_searches_remaining = 1
	_swap_cooldown = maxf(0.0, _swap_cooldown - delta)
	if command == Command.FOLLOW_PLAYER and _pending_command < 0:
		_follow_elapsed += delta
		if _follow_elapsed >= FOLLOW_REPLAN_INTERVAL:
			_follow_elapsed = 0.0
			_replan_follow()
	if has_active_swap():
		move_progress[0] += delta / maxf(MOVE_DURATION, move_duration[0])
		var partner_index := swap_partner[0]
		move_progress[partner_index] = move_progress[0]
		if move_progress[0] >= 1.0:
			_complete_swap()
	if _has_active_follower_swap():
		move_progress[_follower_swap_a] += delta / maxf(MOVE_DURATION, move_duration[_follower_swap_a])
		move_progress[_follower_swap_b] = move_progress[_follower_swap_a]
		if move_progress[_follower_swap_a] >= 1.0:
			_complete_follower_swap()
	if _formation_step_direction != Vector2i.ZERO:
		var progress := move_progress[_formation_step_units[0]] + delta / MOVE_DURATION
		for index: int in _formation_step_units:
			move_progress[index] = progress
		if progress >= 1.0:
			_complete_formation_step()
	else:
		for index: int in range(SOLDIER_COUNT):
			if movement_state[index] != UnitState.MOVING:
				continue
			move_progress[index] += delta / maxf(0.001, move_duration[index])
			if move_progress[index] >= 1.0:
				_complete_move(index)
	_advance_pending_pushes()
	_prune_stale_reservations()
	_try_activate_pending_command()
	if _formation_step_direction != Vector2i.ZERO:
		_update_formation_status()
		return
	if _pending_command >= 0 and not _passage_active:
		command_status = "DRAIN | finish in-flight edges before command activation"
		return
	# The captain route is published asynchronously. Analyse it as soon as the
	# immutable snapshot exists; this does not wait for a long trail or for the
	# captain to reach the boundary.
	_ensure_passage_plan()
	if _command_goal_pending or _passage_plan_pending or _formation_target_pending:
		_update_formation_status()
		return
	if _passage_active and not _passage_failure_reason.is_empty() and _pending_command < 0:
		# A failed 100-person destination cannot admit a scout or a partial army.
		# Existing moves/transactions were serviced above; no new admission starts.
		_update_formation_status()
		return
	var captain_follow_goal := (command == Command.FOLLOW_PLAYER or _formation_march_active) and cells[0] == desired_cells[0]
	if captain_follow_goal and formation_mode == FormationMode.OPEN and not _formation_has_bottleneck and formation_count_value < SOLDIER_COUNT - 1:
		# Measure a real formation stall independently of whether one ordinary
		# move is still interpolating. Otherwise a cyclic push can keep resetting
		# the old timer forever and never leave an idle boundary for re-pairing.
		_formation_rebind_elapsed += delta
	else:
		_formation_rebind_elapsed = 0.0
	# Repair a settled open formation at the first genuinely idle boundary
	# between transactions. Waiting until the end of the tick let the global
	# vacancy queue start a new cyclic push in the same tick, so the repair hook
	# was never reached while eight units rotated forever.
	if captain_follow_goal and formation_mode == FormationMode.OPEN and not _formation_has_bottleneck \
		and formation_count_value < SOLDIER_COUNT - 1:
		if _repair_idle_slot_bindings():
			_formation_rebind_elapsed = 0.0
	# Reaching the map edge only completes the captain's route. Keep a narrow
	# passage active until every follower has consumed its legal corridor and
	# reached a published rally slot; never turn scattered current cells into
	# new desired slots as a timeout recovery.
	# The captain may have advanced far enough to require a new local rally
	# target. This is deliberately done once per fixed tick, not once per unit.
	_update_formation_targets(false)
	if _passage_active:
		_repair_passage_slot_binding()
		_advance_passage_group()
	if _passage_active and _passage_complete():
		_finish_passage()
	# Once the captain has cleared a passage, shift the queue targets as each
	# front rank reaches the exit. The corridor remains active, but its slots
	# must not freeze at the positions published when the captain entered it.
	_bottleneck_refresh_elapsed += delta
	if _bottleneck_refresh_elapsed >= BOTTLENECK_REFRESH_INTERVAL:
		_bottleneck_refresh_elapsed = 0.0
		_refresh_bottleneck_queue_targets()
	# A column can reach a stable pause with most followers already occupying
	# published exit slots while the remaining identities still point at those
	# same slots in a cyclic order. Re-pair only when no move or transaction is
	# in flight; this preserves the terrain-derived slot set and does not cancel
	# an in-progress edge. The next planning tick then owns a stable identity
	# mapping instead of repeatedly asking the queue to swap its own ranks.
	if command == Command.MOVE_TO_EDGE and captain_at_boundary() and not _passage_active and _exit_rally_assigned and not _exit_rally_settled \
		and moving_count() == 0 and _pending_pushes.is_empty() and not has_active_swap() and not _has_active_follower_swap():
		_publish_exit_rally_targets()
		_update_formation_status()
	if command == Command.MOVE_TO_EDGE and captain_at_boundary() and _formation_has_bottleneck and formation_count_value == SOLDIER_COUNT - 1 and _formation_all_settled():
		# The last follower has crossed the height transition. Only now release
		# the corridor contract and build ordinary exit-side formation slots.
		_cancel_pending_pushes()
		_formation_has_bottleneck = false
		_formation_bottleneck_width = FORMATION_COLUMNS
		formation_mode = FormationMode.REGROUPING
		_formation_anchor_cell = INVALID_CELL
		# Keep the already published exit-side targets across the width
		# transition. Rebuilding ordinary slots here would discard the validated
		# exit set and create a second permutation problem.
	var follow_goal_reached := command == Command.FOLLOW_PLAYER and cells[0] == desired_cells[0]
	if not _formation_has_bottleneck and ((command == Command.MOVE_TO_EDGE and formation_mode == FormationMode.REGROUPING) or follow_goal_reached):
		_settle_exit_rally()
	# Direct one-cell intents are cheap. Evaluate every unit each fixed tick so
	# followers do not wait behind an arbitrary eight-unit planning quota. The
	# separate detour budget below still caps expensive BFS work.
	_detour_requests_remaining = PLANNING_BUDGET
	_local_path_requests_remaining = MAX_LOCAL_PATHS_PER_STEP
	var planning_heading := _captain_heading()
	if _advance_formation_march():
		_update_formation_status()
		return
	if _formation_target_pending:
		_update_formation_status()
		return
	if _formation_bend_active:
		# Published one-edge intents are serviced only by their directional
		# subsets; ordinary slot repair/push must not change this local contract.
		_update_formation_status()
		return
	var push_paused_for_repair := (not _passage_active or _formation_march_active) and captain_follow_goal \
		and formation_count_value < SOLDIER_COUNT - 1 and _open_slot_set_is_occupied()
	for index: int in _formation_planning_order(planning_heading):
		if _pending_command >= 0:
			# Close old admissions, but let everyone already inside leave in the
			# old direction. Their bounded push requests may clear idle blockers.
			if (_unit_passage_phase[index] != PassagePhase.IN_PASSAGE \
				and not (_unit_passage_phase[index] == PassagePhase.EXIT_CLEAR and _unit_passage_exit_clear[index] == 0)):
				continue
		if push_paused_for_repair:
			continue
		if index < _push_lock.size() and _push_lock[index] != 0:
			continue
		var slot_is_terminal := cells[index] == desired_cells[index] and (not _passage_active or _formation_march_active or _unit_has_cleared_group(index))
		if movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING or slot_is_terminal:
			if slot_is_terminal and movement_state[index] != UnitState.MOVING and movement_state[index] != UnitState.SWAPPING:
				movement_state[index] = UnitState.ARRIVED if command == Command.MOVE_TO_EDGE else UnitState.IDLE
			continue
		if index > 0 and (not _passage_active or _formation_march_active) and command != Command.NONE and not _formation_has_bottleneck and formation_mode == FormationMode.OPEN \
			and cells[0] == desired_cells[0] and _formation_slot_cells.has(cells[index]):
			# Occupying a published slot is physical progress, even while its old
			# identity owner is still in flight. Wait for safe binding repair instead
			# of starting another internal permutation push. An outside requester
			# may still displace this unit through the atomic vacancy transaction.
			movement_state[index] = UnitState.WAITING
			continue
		# Resolve an explicit adjacent slot exchange before asking the route
		# chooser for a step. A published route can otherwise hide the direct
		# reciprocal intent behind a stale first step and leave both units waiting.
		if (not _passage_active or _formation_march_active) and index > 0 and desired_cells[index] != INVALID_CELL and _cell_owners.has(desired_cells[index]):
			var desired_occupant := int(_cell_owners[desired_cells[index]])
			if desired_occupant > 0 and _follower_swap_requested(index, desired_occupant) and _begin_follower_swap(index, desired_occupant):
				continue
		var next := _next_step(cells[index], desired_cells[index], index)
		if next == INVALID_CELL:
			movement_state[index] = UnitState.WAITING
			blocked_time[index] += delta
			if blocked_time[index] >= BLOCKED_REPORT:
				command_status = "Army blocked: waiting for a legal opening"
			continue
		if (_reserved_cells.has(next) and int(_reserved_cells[next]) != index) or _is_external_cell(next):
			movement_state[index] = UnitState.WAITING
			blocked_time[index] += delta
			continue
		if _cell_owners.has(next):
			var occupant := int(_cell_owners[next])
			if _passage_active and _unit_passage_phase.size() == SOLDIER_COUNT:
				var passage_phase := int(_unit_passage_phase[index])
				var rally_mismatch := _unit_has_cleared_group(index) and cells[index] != desired_cells[index]
				if passage_phase != PassagePhase.APPROACH and passage_phase != PassagePhase.IN_PASSAGE and passage_phase != PassagePhase.EXIT_CLEAR and not rally_mismatch:
					movement_state[index] = UnitState.WAITING
					blocked_time[index] += delta
					continue
			if index == 0 and _begin_captain_swap(occupant):
				continue
			if index > 0 and occupant > 0 and _follower_swap_requested(index, occupant) and _begin_follower_swap(index, occupant):
				continue
			if index > 0 and _formation_has_bottleneck and _unit_is_before_bottleneck(index) and not _passage_active:
				# A narrow passage is ordered front-to-back only on the source
				# plateau. Once a unit is on the captain's exit height, the open
				# rally may use the existing bounded push transaction to resolve
				# slot permutations without closing the ramp behind it.
				movement_state[index] = UnitState.WAITING
				blocked_time[index] += delta
				continue
			if (index > 0 or _passage_active) and not push_paused_for_repair:
				# The blocked follower is the requester. Passing it into the
				# blocker planner is what lets the planner build an atomic push
				# chain to the next free cell instead of merely marking the
				# occupant as waiting at the pass.
				_schedule_follower_blocker(occupant, delta, {index: true}, 0, index)
			movement_state[index] = UnitState.WAITING
			blocked_time[index] += delta
			continue
		_reserved_cells[next] = index
		moving_to[index] = next
		move_progress[index] = 0.0
		var should_run := _unit_should_run(index, next)
		locomotion_mode[index] = Locomotion.RUN if should_run else Locomotion.WALK
		move_duration[index] = RUN_DURATION if should_run else MOVE_DURATION
		blocked_time[index] = 0.0
		movement_state[index] = UnitState.MOVING
		facing[index] = next - cells[index]
		_visual_dirty = true
	_service_push_search()
	_planning_cursor = (_planning_cursor + 1) % (SOLDIER_COUNT - 1)
	_update_formation_status()
	if captain_follow_goal and formation_count_value < SOLDIER_COUNT - 1 and _formation_rebind_elapsed >= BLOCKED_REPORT:
		# Keep the published targets and expose the actual blocker. A stalled
		# formation must be diagnosable, never made complete by retargeting it
		# to its current scattered cells. Existing transactions are allowed to
		# finish; no new cyclic push is started after this ceiling.
		command_status = "Army blocked: formation has no legal opening"

func _next_step(start: Vector2i, goal: Vector2i, moving_index: int) -> Vector2i:
	if moving_index >= 0 and _passage_active and (not _formation_march_active or _formation_final_reform):
		# A previous binding at the current cell cannot finish a passage.
		# Final local reform still belongs to the sealed downstream component;
		# an ordinary follower detour must not walk back through an old gate.
		return _next_passage_step(moving_index)
	if start == goal:
		return INVALID_CELL
	if moving_index != 0 or _formation_march_active:
		return _next_follower_step(start, goal, moving_index)
	if _captain_should_wait():
		return INVALID_CELL
	var routed := _route_next_step(start, goal, moving_index)
	if routed != INVALID_CELL:
		return routed
	# The captain owns one exact, incremental BFS route. A Manhattan fallback
	# could enter a cul-de-sac and backtrack before BFS was requested (18 steps
	# for a 10-step U-shaped route). Start or advance that job here, keeping the
	# source cell frozen until the route is published.
	if _path_status == PathStatus.UNREACHABLE and _path_start == start and _path_goal == goal:
		return INVALID_CELL
	if _detour_requests_remaining <= 0 and _frame_navigation_budget_active:
		return INVALID_CELL
	_find_path(start, goal, moving_index)
	if _path_status != PathStatus.FOUND:
		return INVALID_CELL
	return _route_next_step(start, goal, moving_index)

func _movement_contract_error(action: String, unit: int, source: Vector2i, destination: Vector2i) -> void:
	if not command_status.begins_with("INVARIANT_FAILURE"):
		command_status = "INVARIANT_FAILURE | %s unit=%s %s -> %s source_owner=%s destination_owner=%s claim=%s" % [action, unit, source, destination, _cell_owners.get(source), _cell_owners.get(destination), _reserved_cells.get(destination)]
		push_error(command_status)

func _complete_move(index: int) -> void:
	# A batch owns its entire commit boundary, including front members whose
	# destination is currently empty. Ordinary completion cannot split it.
	if _formation_step_units.has(index):
		return
	var old_cell := cells[index]
	var next := moving_to[index]
	if next == INVALID_CELL:
		return
	# An invalid commit is an explicit invariant failure, never a silent rewind.
	if _cell_owners.get(old_cell, -1) != index or not data.can_step(old_cell, next) \
		or (_cell_owners.has(next) and int(_cell_owners[next]) != index) \
		or _reserved_cells.get(next, -1) != index:
		_movement_contract_error("move", index, old_cell, next)
		return
	_cell_owners.erase(old_cell)
	_reserved_cells.erase(next)
	cells[index] = next
	_cell_owners[next] = index
	moving_to[index] = INVALID_CELL
	move_progress[index] = 0.0
	move_duration[index] = MOVE_DURATION
	locomotion_mode[index] = Locomotion.IDLE
	blocked_time[index] = 0.0
	movement_state[index] = UnitState.IDLE
	_record_passage_commit(index, old_cell, next)
	_consume_path_route_step(index, next)
	_consume_follower_route_step(index, next)
	if index == 0:
		if _captain_trail.is_empty() or _captain_trail.back() != next:
			_captain_trail.append(next)
			_captain_trail_progress_cache.clear()
	_completed_steps += 1
	_visual_dirty = true
	if index == 0 and cells[index] == desired_cells[index] and command != Command.NONE and not _formation_march_active:
		movement_state[index] = UnitState.ARRIVED if command == Command.MOVE_TO_EDGE else UnitState.IDLE
		# A captain reaching a command target is a stable rally point. Reassign
		# the settled body once, so a small permutation cycle cannot leave the
		# last ranks mutually occupying one another forever.
		# Keep column slot identity through a bottleneck. Re-pairing the whole
		# body when the captain reaches the edge can swap near-ramp soldiers with
		# far-rank soldiers and create a permutation cycle at the exit.
		_update_formation_targets(not _formation_has_bottleneck)
	# Refresh a push transaction only after this unit really committed a cell.
	# Scheduling a future edge is not progress and must not hide a stalled chain.
	for pending_index: int in range(_pending_pushes.size()):
		var pending: Dictionary = _pending_pushes[pending_index]
		var pending_units: Array = pending.get("units", [])
		var pending_requester := int(pending.get("requester", -1))
		var path: Array = pending.get("cells", [])
		var committed: Dictionary = pending.get("committed", {})
		var unit_position := pending_units.find(index)
		if unit_position >= 0 and not committed.has(index) and unit_position + 1 < path.size() and old_cell == path[unit_position] and next == path[unit_position + 1]:
			# This member's edge is finished. Its old source remains claimed by
			# the upstream member, but its own lock is no longer a dependency.
			committed[index] = true
			pending["committed"] = committed
			_push_lock[index] = 0
			pending["age"] = 0.0
			_pending_pushes[pending_index] = pending
		elif index == pending_requester and not path.is_empty() and next == path[0]:
			pending["age"] = 0.0
			_pending_pushes[pending_index] = pending

func _rebuild_visual_instances() -> void:
	if _captain_editor == null and not _soldier_baked_ready:
		initialize_visual()
	# The simulation is deliberately independent of render targets.
	if _captain_editor == null or (not _soldier_baked_ready and _soldier_editor == null):
		return
	if _sprites.size() != SOLDIER_COUNT:
		for sprite: Sprite2D in _sprites:
			sprite.queue_free()
		_sprites.clear()
		for index: int in range(SOLDIER_COUNT):
			var sprite := Sprite2D.new()
			sprite.name = "ArmyCaptain" if index == 0 else "ArmySoldier_%03d" % index
			sprite.texture_filter = CharacterRenderContract.TEXTURE_FILTER
			sprite.z_as_relative = false
			add_child(sprite)
			_sprites.append(sprite)
	_soldier_animation_time.resize(SOLDIER_COUNT)
	_soldier_current_keys.resize(SOLDIER_COUNT)
	_soldier_sprite_anchors.resize(SOLDIER_COUNT)
	for index: int in range(SOLDIER_COUNT):
		var sprite := _sprites[index]
		sprite.modulate = Color("ffd780") if index == 0 else Color.WHITE
		if index == 0:
			var captain_source: Variant = _captain_editor
			sprite.texture = captain_source.preview_viewport.get_texture()
			var captain_scale: float = captain_source.get_map_sprite_scale()
			sprite.scale = Vector2.ONE * captain_scale
			_captain_anchor = captain_source.get_map_ground_offset_pixels() * captain_scale
		else:
			if _soldier_baked_ready:
				sprite.scale = Vector2.ONE * _soldier_map_scale
				_set_soldier_frame(index, true)
				_soldier_sprite_anchors[index] = _soldier_frame_anchors.get(_soldier_current_keys[index], Vector2.ZERO)
			else:
				var soldier_source: Variant = _soldier_editor
				sprite.texture = soldier_source.preview_viewport.get_texture()
				var soldier_scale: float = soldier_source.get_map_sprite_scale()
				sprite.scale = Vector2.ONE * soldier_scale
				_soldier_anchor = soldier_source.get_map_ground_offset_pixels() * soldier_scale
	_sync_visual_positions()

func _sync_visual_positions() -> void:
	if _sprites.size() != SOLDIER_COUNT:
		return
	if not _visual_dirty and moving_count() == 0:
		return
	for index: int in range(SOLDIER_COUNT):
		var sprite := _sprites[index]
		var progress := clampf(move_progress[index], 0.0, 1.0)
		if movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING:
			# Render the fractional remainder between fixed simulation ticks so
			# movement does not appear to advance in 10 Hz steps.
			progress = clampf(progress + _sim_accumulator / maxf(0.001, move_duration[index]), 0.0, 1.0)
		var map_position := (Vector2(cells[index]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		if movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING:
			var destination := (Vector2(moving_to[index]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			map_position = map_position.lerp(destination, smoothstep(0.0, 1.0, progress))
		var anchor := _captain_anchor if index == 0 else (_soldier_sprite_anchors[index] if _soldier_baked_ready else _soldier_anchor)
		sprite.position = map_position - anchor
		sprite.z_index = 10 + int(map_position.y / TerrainRenderer.CELL_PIXELS)
		sprite.visible = true
	_visual_dirty = false

func _advance_command_goal() -> void:
	if not _command_goal_pending or _pending_command >= 0:
		return
	if command == Command.FOLLOW_PLAYER:
		_replan_follow()
	elif command == Command.MOVE_TO_EDGE:
		if not _choose_edge_targets():
			_command_goal_pending = false
			command = Command.NONE

func advance_frame(delta: float) -> void:
	if not has_army():
		return
	var frame_start_usec := Time.get_ticks_usec()
	var structure_before := structure_search_expansions
	var local_before := local_search_expansions
	var push_before := push_search_expansions
	input_seconds += delta
	_detour_searches_remaining = MAX_DETOUR_SEARCHES_PER_FRAME
	_frame_navigation_budget_active = true
	_structure_expansions_remaining = PATH_EXPANSIONS_PER_STEP
	_structure_work_ready.emit()
	_advance_command_goal()
	# The shared search quota is per rendered/input frame, not per 10 Hz
	# movement tick. Keep the same job alive and advance it between sim ticks.
	_advance_path_job(_structure_expansions_remaining)
	_sim_accumulator += delta
	dropped_seconds += maxf(0.0, _sim_accumulator - MAX_ACCUMULATED_SIM_TIME)
	# Cap catch-up work. Without this guard a slow frame schedules four more
	# expensive formation updates, creating a self-reinforcing frame spiral.
	_sim_accumulator = minf(_sim_accumulator, MAX_ACCUMULATED_SIM_TIME)
	var iterations := 0
	# Treat a one-tick floating-point remainder as elapsed simulation time. The
	# public 60 Hz path must not silently drop the 1800th fixed step at a
	# decimal boundary.
	while _sim_accumulator + 0.000001 >= SIM_STEP and iterations < MAX_SIM_STEPS_PER_FRAME:
		_sim_accumulator -= SIM_STEP
		_simulate_step(SIM_STEP)
		simulated_seconds += SIM_STEP
		iterations += 1
	_update_soldier_frames(delta)
	if moving_count() > 0:
		_set_visual_sources_active(true)
	_sync_captain_presentation()
	_sync_visual_positions()
	if _visual_warmup_frames > 0:
		_visual_warmup_frames -= 1
		_set_visual_sources_active(true)
	elif moving_count() == 0:
		_set_visual_sources_active(false)
	_frame_navigation_budget_active = false
	_structure_expansions_remaining = 0
	max_frame_structure_expansions = maxi(max_frame_structure_expansions, structure_search_expansions - structure_before)
	max_frame_local_expansions = maxi(max_frame_local_expansions, local_search_expansions - local_before)
	max_frame_push_expansions = maxi(max_frame_push_expansions, push_search_expansions - push_before)
	last_frame_cpu_usec = Time.get_ticks_usec() - frame_start_usec

func _process(delta: float) -> void:
	advance_frame(delta)

func _exit_tree() -> void:
	if not _visual_sources_owned:
		return
	for editor: Variant in [_soldier_editor, _captain_editor]:
		if editor == null:
			continue
		if editor.preview_viewport != null:
			editor.preview_viewport.queue_free()
		editor.queue_free()
