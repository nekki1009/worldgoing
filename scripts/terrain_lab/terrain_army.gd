class_name TerrainArmy
extends Node2D

const ExchangeTimings = preload("res://scripts/terrain_lab/character_exchange_timings.gd")
const TeamDeparture = preload("res://scripts/terrain_lab/site_team_departure.gd") # R6 S5: team officer-seat departure part.
const WagonRiderRecipe = preload("res://scripts/terrain_lab/site_wagon_rider_recipe.gd")
const SharedVisualSource = preload("res://scripts/terrain_lab/terrain_army_shared_visual_source.gd")
const SiegeWorkClips = preload("res://scripts/terrain_lab/site_siege_work_clips.gd")
const SiegeWorkAppend = preload("res://scripts/terrain_lab/site_siege_work_append.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const EXCHANGE_NATIVE_VISUAL_POSES := ["get_up", "down", "unconscious", "guard_break", "guard_raise", "guard_lower", "rescue"]

## Terrain Lab army: one grid-authoritative captain plus 99 soldiers.
## Ordinary soldiers use a shared baked atlas; simulation remains usable in
## headless contract tests and the captain keeps the live 3D presenter.

# Presentation only; never added to original rows/save/hash.
var audio_step_sink: Callable
var _audio_step_sources: Dictionary = {}
var audio_down_sink: Callable

func clear_audio_step_sources() -> void:
	_audio_step_sources.clear()

func _audio_begin_step(index: int, source: Vector2i, destination: Vector2i, running: bool) -> void:
	_audio_step_sources.erase(index)
	if not audio_step_sink.is_valid():
		return
	var identity := combat_identity(index)
	if identity <= 0:
		return
	var mounted: bool = vehicle_transport != null and vehicle_transport.occupies_own_horse(identity, source)
	_audio_step_sources[index] = {"identity": identity, "from": source, "to": destination, "running": running, "mounted": mounted}

func _audio_take_step(index: int, source: Vector2i, destination: Vector2i, duration: float) -> Dictionary:
	var marked: Dictionary = _audio_step_sources.get(index, {})
	_audio_step_sources.erase(index)
	if marked.is_empty() or not audio_step_sink.is_valid() or not is_finite(duration) or duration <= 0.0:
		return {}
	if int(marked.identity) != combat_identity(index) or marked.from != source or marked.to != destination:
		return {}
	if combat_enabled and (float(combat_hot_get(index, &"hp", 0.0)) <= 0.0 or float(combat_hot_get(index, &"ko", 0.0)) > 0.0 		or bool(combat_hot_get(index, &"departed", false)) or bool(combat_hot_get(index, &"site_exited", false))):
		return {}
	marked["duration"] = duration
	marked["ground"] = (Vector2(destination) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	return marked

func _audio_emit_step(candidate: Dictionary) -> void:
	if not candidate.is_empty() and audio_step_sink.is_valid():
		audio_step_sink.call(int(candidate.identity), Vector2(candidate.ground), float(candidate.duration), bool(candidate.running), bool(candidate.mounted))

enum Command { NONE, FOLLOW_PLAYER, MOVE_TO_EDGE }
enum UnitState { IDLE, MOVING, SWAPPING, WAITING, ARRIVED }
enum PathStatus { NONE, PENDING, FOUND, UNREACHABLE }
enum FormationMode { OPEN, COMPRESSING, COLUMN, REGROUPING }
enum Locomotion { IDLE, WALK, RUN }
enum PassagePhase { NONE, APPROACH, IN_PASSAGE, EXIT_CLEAR, RALLY, EXEMPT }

const SOLDIER_COUNT := 100
const MAX_ROSTER_SIZE := 200
const TROOP_TYPE_ID := &"melee_infantry"
const TROOP_TYPE_NAME := "近戰步兵"
const TROOP_COMBAT_ABILITY := 50.0
const _EMPTY_TROOP_DATA: Dictionary = {} # Read-only lookup default; no per-person temporary map.
static var _summary_asset_classes: Dictionary = {} # Immutable rule projection only; never people/items/Site state.
var roster_size := SOLDIER_COUNT
const SIM_STEP := 0.10
const MOVE_DURATION := CombatTimings.MOVE_DURATION
const RUN_DURATION := CombatTimings.RUN_DURATION
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
const FAILED_ROUTE_MAX_ENTRIES := 128
const FAILED_ROUTE_MAX_DEPENDENCIES := 512
const MAX_LOCAL_PATHS_PER_STEP := 4
const FORMATION_STRETCH_SLACK := 6
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
const CombatTimings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const CombatGeometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const ContactSource = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const EquipmentAtlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const VehicleRiderAtlas = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
const ShipDefinitions = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const HELD_LOCOMOTION := {"idle": "combat_idle", "walk": "combat_walk", "run": "combat_run"}
# Shared immutable bake, not one copy or one actor Node per soldier.
static var _combat_bake: Dictionary = {}
static var _contact_source: RefCounted
static var _body_contact_sources: Dictionary = {} # Same original query resource per additional body, never people/positions/clocks.
static var _captain_geometry_pool: Dictionary = {} # Body -> one original editor/proxy, never a person owner.
const IDLE_EXTENSION := "res://native/army_idle/army_idle.gdextension"
const COMBAT_HOT_FIELDS := {&"hp": true, &"ko": true, &"age": true, &"think": true, &"stun": true, &"grace": true,
	&"exchange_cooldown": true, &"exchange_stagger": true, &"exchange_skill_cooldown": true,
	&"ranged_cooldown": true, &"exchange_pose_duration": true, &"pose": true, &"attack": true,
	&"member": true, &"captive": true, &"departed": true, &"present": true,
	&"site_exited": true, &"surrender_pending": true, &"exchange_visual": true}
const COMBAT_HOT_NUMBERS := {&"hp": true, &"ko": true, &"age": true, &"think": true, &"stun": true, &"grace": true,
	&"exchange_cooldown": true, &"exchange_stagger": true, &"exchange_skill_cooldown": true,
	&"ranged_cooldown": true, &"exchange_pose_duration": true}
const COMBAT_HOT_COLUMN_FLAGS := {&"attack": true, &"member": true, &"captive": true, &"departed": true,
	&"present": true, &"site_exited": true, &"surrender_pending": true}
# Native reason codes are stable diagnostic-only ABI; ordinary FPS uses the
# original two-int advance result and does no per-barrier classification.
const COMBAT_HOT_OWNER_REASONS := ["none", "input_invalid", "state_invalid", "movement_invalid",
	"rescue", "visual_clear", "visual_expiry", "visual_invalid", "numeric_invalid",
	"attack_active", "pose_owner", "pose_expiry", "think_nonhold", "think_hold"]
static var _idle_kernel: RefCounted
static var _idle_kernel_checked := false
var native_idle_enabled := true # Same-owner A/B/fallback; never changes tick frequency.
var hold_empty_rescue_skip_enabled := true # Same-owner A/B: skip impossible HOLD rescue work in the formal Lab.
var hold_rescue_column_enabled := true # Same-owner A/B: read one HotStore column pair on a due HOLD review.
var hold_rescue_column_uses := 0 # Diagnostic coverage only; never saved/person state.
var native_hold_no_patient_enabled := true # Same-owner A/B: retain exact HOLD timers when rescue cannot start.
var native_hot_enabled := false # Enable only after canonical hot-field callers are closed.
var combat_hot_diagnostics_enabled := false
var native_idle_rows := 0 # Diagnostic count, not saved/person state.
var native_idle_calls := 0
var native_recovery_enabled := true
var native_recovery_rows := 0 # Diagnostic only, never saved.
var native_fatigue_rows := 0
var native_queries_enabled := true # Call-local read-only projections; no retained roster.
var native_summary_enabled := true # Same-owner summary A/B; no cached people, equipment or fatigue.
var native_move_intent_enabled := true # Same-owner stage projection; original GD remains the unsupported fallback.
var r3_prepare_enabled := true # Same-source r2/R2 comparison; one-phase geometry only.
var r3_fused_propose_enabled := true # Same-source r2/R1 comparison; Grid and Army still own all writes.
var r3_fused_propose_hits := 0
var r3_fused_propose_fallbacks := 0
var native_local_route_enabled := true
var native_movement_projection_enabled := true
var native_movement_projection_calls := 0
var native_movement_roster_calls := 0
var native_local_route_hits := 0
var native_move_intent_hits := 0 # Diagnostic count of members evaluated by one stage packet.
var native_front_enabled := true
var native_front_cells := 0 # Diagnostic only, never saved.
var native_presence_enabled := true
var native_presence_rows := 0 # Diagnostic only, never saved.
var native_presence_delta_enabled := true
var native_presence_delta_calls := 0
var native_presence_changed_rows := 0
var native_presence_geometry_rebuilds := 0
var native_presence_geometry_reuses := 0
var _presence_geometry_cache: Array = [] # Validated read-only projection, never person authority or saved.
var native_query_rows := 0 # Diagnostics only, never saved.
# Movement instrumentation counters (Task 0)
var route_calls: int = 0
var expanded_nodes: int = 0
var direct_route_hits: int = 0
var profiled_capped_step_eligible: int = 0
var profiled_capped_center_eligible: int = 0
var profiled_capped_side_eligible: int = 0
var profiled_capped_step_proposed: int = 0
var profiled_capped_step_accepted: int = 0
var profiled_capped_center_accepted: int = 0
var profiled_capped_side_accepted: int = 0
var profiled_deferred_step_eligible: int = 0
var profiled_deferred_step_proposed: int = 0
var profiled_deferred_step_accepted: int = 0
var profiled_route_successes: int = 0
var profiled_route_failures: int = 0
var profiled_retry12_successes: int = 0
var profiled_retry12_failures: int = 0
var profiled_repeated_retry12_failures: int = 0
var _profile_last_failed_route_query: Dictionary = {}
var profiled_search_cap_failures: int = 0
var profiled_scheduler_metrics: Dictionary = {}
var proposal_count: int = 0
var accepted_count: int = 0
var rejected_dependency_count: int = 0
var scheduler_deferred_count: int = 0

func reset_movement_metrics() -> void:
	route_calls = 0
	expanded_nodes = 0
	direct_route_hits = 0
	profiled_capped_step_eligible = 0
	profiled_capped_center_eligible = 0
	profiled_capped_side_eligible = 0
	profiled_capped_step_proposed = 0
	profiled_capped_step_accepted = 0
	profiled_capped_center_accepted = 0
	profiled_capped_side_accepted = 0
	profiled_deferred_step_eligible = 0
	profiled_deferred_step_proposed = 0
	profiled_deferred_step_accepted = 0
	profiled_route_successes = 0
	profiled_route_failures = 0
	profiled_retry12_successes = 0
	profiled_retry12_failures = 0
	profiled_repeated_retry12_failures = 0
	_profile_last_failed_route_query.clear()
	profiled_search_cap_failures = 0
	profiled_scheduler_metrics.clear()
	proposal_count = 0
	accepted_count = 0
	rejected_dependency_count = 0
	scheduler_deferred_count = 0

func get_movement_metrics() -> Dictionary:
	return {
		"route_calls": route_calls,
		"expanded_nodes": expanded_nodes,
		"direct_route_hits": direct_route_hits,
		"profiled_capped_step_eligible": profiled_capped_step_eligible,
		"profiled_capped_center_eligible": profiled_capped_center_eligible,
		"profiled_capped_side_eligible": profiled_capped_side_eligible,
		"profiled_capped_step_proposed": profiled_capped_step_proposed,
		"profiled_capped_step_accepted": profiled_capped_step_accepted,
		"profiled_capped_center_accepted": profiled_capped_center_accepted,
		"profiled_capped_side_accepted": profiled_capped_side_accepted,
		"profiled_deferred_step_eligible": profiled_deferred_step_eligible,
		"profiled_deferred_step_proposed": profiled_deferred_step_proposed,
		"profiled_deferred_step_accepted": profiled_deferred_step_accepted,
		"profiled_route_successes": profiled_route_successes,
		"profiled_route_failures": profiled_route_failures,
		"profiled_retry12_successes": profiled_retry12_successes,
		"profiled_retry12_failures": profiled_retry12_failures,
		"profiled_repeated_retry12_failures": profiled_repeated_retry12_failures,
		"profiled_search_cap_failures": profiled_search_cap_failures,
		"profiled_scheduler": profiled_scheduler_metrics.duplicate(),
		"proposal_count": proposal_count,
		"accepted_count": accepted_count,
		"rejected_dependency_count": rejected_dependency_count,
		"scheduler_deferred_count": scheduler_deferred_count,
	}

var combat_units: Array[Dictionary] = []
var _combat_hot_store: RefCounted
var _combat_hot_borrowed_index := -1
var _combat_identity_indices: Dictionary = {}
var _combat_identity_index_count := -1
var _combat_hot_dictionary_reads := 0
var _combat_hot_dictionary_writes := 0
var _combat_hot_dictionary_unscoped_reads := 0
var _combat_hot_dictionary_unscoped_writes := 0
var _combat_hot_materialized_rows := 0
var _combat_hot_native_calls := 0
var _combat_hot_native_rows := 0
var _combat_hot_barriers: Dictionary = {}
var _combat_hot_owner_reasons: Dictionary = {}
var _combat_hot_fallback_rows := 0
var _combat_hot_inclusive_usec := 0
var projectiles: Array[Dictionary] = [] # In-flight cell events only; Lab advances them after release.
static var _projectile_textures: Dictionary = {} # Same immutable arrow/bolt resources as the original actor.
var combat_enabled := false
var exchange_enabled := false # Lab selects adjacent exchanges; standalone legacy tests retain their mode.
var combat_attacking := false
var faction_id := 0
var team_id := 1
var garrison_feature_id := "" # Original roster container; people remain members while unformed.
var role := "combat" # Test purpose only; original rows remain the people owner.
var formation_preset_id := "auto"
var vehicle_transport: RefCounted # Borrows the Site's vehicles; no second movement clock.
var training := 0.0
# Decoupled v3 movement & deployment sub-plans (Task 1)
var _combat_move_plan: CombatMovePlan = null
var _combat_deployment_plan: CombatDeploymentPlan = null
var _formation_movement_profile: FormationMovementProfile = null
var _coordinator: Object = null

func set_coordinator(coord: Object) -> void:
	_coordinator = coord

func get_coordinator() -> Object:
	return _coordinator

var formation_runtime_id: int = 0
var formation_persistent_serial: int = 0
var current_logic_tick: int = 0
var _combat_batch_members: Dictionary = {} # member_id -> starting order until the shared completion barrier
var _capped_transit_steps: Dictionary = {} # member_id -> current-tick, one-edge fallback only
var _combat_absent_slots: Dictionary = {} # living KO member_id -> previous final slot
var _move_encounters: Dictionary = {} # Transient 10 Hz Lab contacts: member index -> enemy IDs.
var _move_landed_members: Dictionary = {} # Members whose completed step awaits the next contact query.
var _retreat_pair_pending: Dictionary = {} # One blocked front and one adjacent ally, submitted on the next grid tick.
var _retreat_pairs_used: Dictionary = {} # A forced pair may cross once per RETREAT order, never bounce back.
var _retreat_resolution: Dictionary = {} # Morale collapse, shared with the original combat order/physical cells.
var _retreat_paths: Dictionary = {} # Disposable routes; persisted positions and outcome stay on original rows.
var _retreat_path_revision := -1
var formation_intent_version := 0 # 1 permits a newly requested preset while the old physical plan finishes.
var _formation_change_pending := false
var _formation_retry_seconds := 0.0
var _corps_reposition_source: Dictionary = {} # Accepted issuer while the original MOVE runs.

func set_formation_id(id: int) -> void:
	formation_runtime_id = id

func get_formation_id() -> int:
	if formation_runtime_id > 0:
		return formation_runtime_id
	return team_id

func try_get_formation_id() -> int:
	return formation_runtime_id if formation_runtime_id > 0 else 0

func get_order_serial() -> int:
	if _combat_move_plan != null:
		return _combat_move_plan.order_serial
	if _combat_deployment_plan != null:
		return _combat_deployment_plan.order_serial
	return _current_order_serial

func _is_stall_clock_eligible() -> bool:
	if _fire_nav_context_current(): return false
	if _combat_move_plan == null:
		return false
	if _combat_deployment_plan != null and not _combat_deployment_plan.following_member_ids.is_empty():
		var assigned_unsettled := false
		for mid: int in _combat_deployment_plan.member_slot_map.keys():
			var index := index_for_identity(mid)
			if index >= 0 and combat_can_act(index) and (cells[index] != combat_slots[index] or moving_to[index] != INVALID_CELL):
				assigned_unsettled = true
				break
		if not assigned_unsettled:
			return false # Waiting for physical room must not cancel the order after twelve seconds.
	if _combat_move_plan.scheduler_deferred or _combat_move_plan.waiting_animation_only or _combat_move_plan.tactical_overlay == CombatMovementTypes.TacticalOverlay.ENGAGING:
		return false
	var active_mids := _get_active_member_ids()
	var any_member_unsettled := false
	var any_ready_and_blocked := false
	for mid in active_mids:
		var idx := index_for_identity(mid)
		if idx < 0 or not is_member(idx) or not combat_can_act(idx) or is_controlled_person(idx):
			continue
		if cells[idx] != combat_slots[idx]:
			any_member_unsettled = true
			if moving_to[idx] == INVALID_CELL and not _combat_action_blocks_step(idx):
				any_ready_and_blocked = true
				break
	if not any_member_unsettled:
		return false
	return any_ready_and_blocked

var _current_order_serial: int = 1
var _preserve_structure_order := false
var _active_member_scope := false
var _active_member_scope_valid := false
var _active_member_scope_ids: Array[int] = []
var _transit_static_candidates_cache: Dictionary = {}
var _shared_movement_blockers: Dictionary = {} # Coordinator's current-tick read view, never a cell owner.
var _shared_movement_blockers_tick := -1

func begin_combat_movement_read_scope() -> void:
	_active_member_scope = true
	_active_member_scope_valid = false
	_active_member_scope_ids.clear()
	_transit_static_candidates_cache.clear()
	_shared_movement_blockers.clear()
	_shared_movement_blockers_tick = -1

func set_shared_movement_blockers(blocked: Dictionary, tick: int) -> void:
	if not _active_member_scope or _coordinator == null or tick != int(_coordinator.current_logic_tick):
		return
	_shared_movement_blockers = blocked
	_shared_movement_blockers_tick = tick

func _shared_movement_blockers_valid() -> bool:
	return _active_member_scope and _coordinator != null \
		and _shared_movement_blockers_tick == int(_coordinator.current_logic_tick) \
		and current_logic_tick == _shared_movement_blockers_tick

func clear_shared_movement_blockers() -> void:
	_shared_movement_blockers.clear()
	_shared_movement_blockers_tick = -1

func end_combat_movement_read_scope() -> void:
	_active_member_scope = false
	_active_member_scope_valid = false
	_active_member_scope_ids.clear()
	_transit_static_candidates_cache.clear()
	clear_shared_movement_blockers()

func _invalidate_active_member_read_scope() -> void:
	_active_member_scope_valid = false
	_active_member_scope_ids.clear()

func _next_order_serial() -> int:
	_preserve_structure_order = false
	_current_order_serial += 1
	return _current_order_serial

func _get_active_member_ids() -> Array[int]:
	if _active_member_scope and _active_member_scope_valid:
		if combat_profile_enabled:
			profiled_scheduler_metrics["roster_scope_hits"] = int(profiled_scheduler_metrics.get("roster_scope_hits", 0)) + 1
		return _active_member_scope_ids.duplicate()
	var res: Array[int] = []
	var native_roster := _native_movement_roster(0)
	if native_roster.has("value"):
		res.assign(native_roster.value)
	for i in range(0 if native_roster.has("value") else combat_units.size()):
		if is_member(i) and combat_can_act(i) and not bool(combat_units[i].get("dead", false)) and not _siege_crew(i) and not _ship_embarked(i):
			res.append(combat_identity(i))
	if combat_profile_enabled:
		profiled_scheduler_metrics["roster_full_scans"] = int(profiled_scheduler_metrics.get("roster_full_scans", 0)) + 1
	if _active_member_scope:
		_active_member_scope_ids = res.duplicate()
		_active_member_scope_valid = true
	return res

func _get_active_members_medoid() -> Vector2i:
	var native_roster := _native_movement_roster(1)
	if native_roster.has("value"):
		return native_roster.value
	var sum_x: int = 0
	var sum_y: int = 0
	var count: int = 0
	for i in range(combat_units.size()):
		if is_member(i) and combat_can_act(i) and not bool(combat_units[i].get("dead", false)) and not _siege_crew(i) and not _ship_embarked(i):
			sum_x += cells[i].x
			sum_y += cells[i].y
			count += 1
	if count == 0:
		return Vector2i(command_reference.floor()) if command_reference_valid else Vector2i.ZERO
	return Vector2i(roundi(float(sum_x) / float(count)), roundi(float(sum_y) / float(count)))

func _native_movement_roster(operation: int) -> Dictionary:
	if not native_movement_projection_enabled or _team_has_embarked() or vehicle_transport != null and vehicle_transport.has_siege():
		return {}
	var reader := _native_movement_reader()
	if reader == null or not reader.has_method("movement_roster"):
		return {}
	var empty_medoid := Vector2i(command_reference.floor()) if command_reference_valid else Vector2i.ZERO
	var result: Dictionary = reader.movement_roster(combat_units, cells, _cell_owners, operation, empty_medoid)
	if result.has("value"):
		native_movement_roster_calls += 1
	return result

func _get_combat_route_anchor_cell() -> Vector2i:
	# Commander references are original row indices (or PLAYER_MEMBER), not IDs.
	# Physical anchor only: who may be current commander is already filtered by R1b in settle.
	if base_command_eligible(current_commander) and not _ship_embarked(current_commander):
		var cmd_cell: Vector2i = player_member.terrain_cell if current_commander == PLAYER_MEMBER else cells[current_commander]
		if data != null and data.is_walkable(cmd_cell):
			return cmd_cell
	var medoid := _get_active_members_medoid()
	if data != null and data.is_walkable(medoid):
		return medoid
	if data != null:
		for r in range(1, 4):
			for dir in TerrainData.DIRECTIONS:
				var candidate := medoid + dir * r
				if data.contains(candidate) and data.is_walkable(candidate):
					return candidate
	return medoid

func _resolve_combat_goal(goal: Vector2i, _profile: FormationMovementProfile) -> Dictionary:
	return _resolve_combat_goal_at(data, goal, _is_external_cell)

static func _resolve_combat_goal_at(map: TerrainData, goal: Vector2i, blocked: Callable) -> Dictionary:
	if map == null or not map.contains(goal):
		return { "ok": false, "code": "INVALID_TARGET" }
	if map.is_walkable(goal) and not blocked.call(goal):
		return { "ok": true, "cell": goal }
	var best_cell := INVALID_CELL
	var best_dist := INF
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var candidate := goal + Vector2i(dx, dy)
			if map.contains(candidate) and map.is_walkable(candidate) and not blocked.call(candidate):
				var d := float(dx * dx + dy * dy)
				if d < best_dist:
					best_dist = d
					best_cell = candidate
	if best_cell != INVALID_CELL:
		return { "ok": true, "cell": best_cell }
	return { "ok": false, "code": "INVALID_TARGET" }

func remove_member_from_combat_plans(member_id: int) -> void:
	_combat_absent_slots.erase(member_id)
	if _combat_move_plan != null:
		_combat_move_plan.remove_member(member_id, CombatMovementTypes.SlotVacancyReason.MEMBER_DEAD)
	elif _combat_deployment_plan != null:
		_combat_deployment_plan.remove_member(member_id, CombatMovementTypes.SlotVacancyReason.MEMBER_DEAD)
	_sync_combat_deployment_leases()

func _ship_embarked(index: int) -> bool:
	if index == PLAYER_MEMBER:
		return vehicle_transport != null and vehicle_transport.is_embarked(combat_identity(index))
	return index >= 0 and index < combat_units.size() and not str(combat_units[index].get("embarked_vehicle_id", "")).is_empty()

func _team_has_embarked() -> bool:
	for row: Dictionary in combat_units:
		if not str(row.get("embarked_vehicle_id", "")).is_empty(): return true
	return vehicle_transport != null and vehicle_transport.team_has_embarked(team_id)

func _team_ship_activity() -> bool:
	return _team_has_embarked() or vehicle_transport != null and vehicle_transport.team_has_ship_activity(team_id)

func _ship_vehicle_id(index: int) -> String:
	if index == PLAYER_MEMBER:
		return str(player_member.get("embarked_vehicle_id")) if is_instance_valid(player_member) else ""
	return str(combat_units[index].get("embarked_vehicle_id", "")) if index >= 0 and index < combat_units.size() else ""

func _ship_in_journey(index: int) -> bool:
	return _ship_identity_in_journey(combat_identity(index))

func _region_operation_pending() -> bool:
	return vehicle_transport != null and vehicle_transport.controller != null and vehicle_transport.controller.has_method("region_operation_pending") and bool(vehicle_transport.controller.call("region_operation_pending"))

func _ship_identity_in_journey(identity: int) -> bool:
	return identity > 0 and vehicle_transport != null and vehicle_transport.controller != null and vehicle_transport.controller.has_method("ship_person_in_journey") and bool(vehicle_transport.controller.call("ship_person_in_journey", identity))

func has_ship_journey() -> bool:
	for index in range(combat_units.size()):
		if _ship_in_journey(index): return true
	return is_instance_valid(player_member) and _ship_in_journey(PLAYER_MEMBER)

func _hide_journey_person(index: int) -> bool:
	if not _ship_in_journey(index): return false
	if vehicle_transport != null and vehicle_transport.has_region_ship_projection(_ship_vehicle_id(index)): return false
	if _batch_view != null: _batch_view.remove(index)
	if index >= 0 and index < _sprites.size() and _sprites[index] != null: _sprites[index].visible = false
	return true

func _ship_attack_allowed(index: int) -> bool:
	if _ship_in_journey(index): return false
	return not _ship_embarked(index) or vehicle_transport != null and vehicle_transport.ship_can_attack(combat_identity(index))

func _combat_attack_cell(index: int) -> Vector2i:
	return vehicle_transport.ship_person_cell(combat_identity(index)) if _ship_embarked(index) and vehicle_transport != null else cells[index]

func _combat_ship_pair(index: int, identity: int) -> bool:
	return _ship_embarked(index) or vehicle_transport != null and identity > 0 and vehicle_transport.is_embarked(identity)

func _combat_ship_contact(index: int, identity: int) -> bool:
	if _ship_in_journey(index): return false
	var other := index_for_identity(identity)
	if other >= 0 and _ship_in_journey(other): return false
	return identity > 0 and vehicle_transport != null and vehicle_transport.ship_combat_contact(combat_identity(index), identity)

func _combat_ranged_line_clear(index: int, source: Vector2i, target: Vector2i) -> bool:
	if not _ship_embarked(index): return SiteCombatRules.ranged_line_clear(data, source, target)
	# Water remains unwalkable. An afloat shooter retains the original ray and
	# height tests without interpreting the deck as a ground walking cell.
	if not _ship_attack_allowed(index) or data == null or not data.contains(source) or not data.contains(target): return false
	var ray := SiteCombatRules.ranged_cells(source, target)
	if ray.is_empty(): return false
	for cell: Vector2i in ray:
		if not SiteCombatRules.ranged_cell_clear(data, source, target, cell): return false
	return true

func _invalidate_ship_projection() -> void:
	if not _team_has_embarked(): return
	_presence_geometry_cache = []
	_contact_batch_inputs = []
	_contact_batch_pose_results = []
	for index in range(combat_units.size()):
		if _ship_embarked(index): _combat_pose_cache.erase(combat_identity(index))
	_command_dirty = true
	_visual_dirty = true

func _has_ship_presentation_state() -> bool:
	if _team_has_embarked(): return true
	for row: Dictionary in combat_units:
		if bool(row.get("ship_death_settled", false)): return true
	return false

func ship_boarded(index: int) -> void:
	assert(index >= 0 and index < combat_units.size() and _ship_embarked(index))
	movement_state[index] = UnitState.IDLE
	locomotion_mode[index] = Locomotion.IDLE
	ship_embarkation_changed(combat_identity(index))

func ship_disembarked(index: int, shore: Vector2i) -> void:
	# Transport owns the attachment commit and has already reserved this shore.
	assert(index >= 0 and index < combat_units.size() and not _ship_embarked(index))
	cells[index] = shore
	desired_cells[index] = shore
	combat_slots[index] = shore
	moving_to[index] = INVALID_CELL
	move_progress[index] = 0.0
	move_duration[index] = MOVE_DURATION
	move_curve[index] = 0
	movement_state[index] = UnitState.IDLE
	locomotion_mode[index] = Locomotion.IDLE
	blocked_time[index] = 0.0
	swap_partner[index] = -1
	ship_embarkation_changed(combat_identity(index))

func _rebuild_ground_cell_owners() -> void:
	_cell_owners.clear()
	for index in range(combat_units.size()):
		if _ship_in_journey(index) or _ship_embarked(index): continue
		if moving_to[index] != INVALID_CELL or float(combat_hot_get(index, &"hp", 0.0)) > 0.0 and float(combat_hot_get(index, &"ko", 0.0)) <= 0.0 and not bool(combat_hot_get(index, &"departed", false)) and not bool(combat_hot_get(index, &"site_exited", false)):
			_cell_owners[cells[index]] = index

func ship_embarkation_changed(person_id: int) -> void:
	# Called after the original Transport commits boarding, landing or death.
	# Physical ground steps already in flight retain their existing reservations.
	var index := index_for_identity(person_id)
	if index >= 0:
		_clear_follower_route(index)
		combat_units[index].target = -1
		combat_slots[index] = INVALID_CELL if _ship_embarked(index) else cells[index]
		for cell: Vector2i in _reserved_cells.keys():
			if int(_reserved_cells[cell]) == index: _reserved_cells.erase(cell)
		_move_encounters.erase(index)
		_retreat_paths.erase(person_id)
		_mark_visual_row(index)
		if bool(combat_units[index].get("ship_death_settled", false)) and _batch_view != null:
			_batch_view.remove(index)
	cancel_combat_deployment_for_forced_order()
	for member in range(combat_units.size()):
		_clear_follower_route(member)
		if _ship_embarked(member): combat_slots[member] = INVALID_CELL
	_formation_change_pending = false
	_formation_retry_seconds = 0.0
	_command_goal_pending = false
	_pending_command = -1
	_pending_command_epoch = -1
	command = Command.NONE
	_clear_navigation_paths()
	_stop_tactical_ai()
	if combat_order != CombatOrder.RETREAT:
		combat_order = CombatOrder.HOLD
		combat_attacking = false
		combat_goal = INVALID_CELL
		pursuit_target = -1
		pursuit_left = 0.0
		_clear_member_attack_targets()
	_rebuild_ground_cell_owners()
	_invalidate_active_member_read_scope()
	_presence_geometry_cache = []
	_command_dirty = true
	settle_combat_command()
	if _coordinator != null: _coordinator.request_occupancy_rebuild()
	_visual_dirty = true
	queue_redraw()

func _siege_crew(index: int) -> bool:
	return vehicle_transport != null and index >= 0 and index < combat_units.size() and vehicle_transport.is_siege_crew(combat_identity(index))

func siege_crew_assigned(member_id: int) -> void:
	# Only plans/leases change. Original roster, cells and physical reservations stay put.
	var index := index_for_identity(member_id)
	if index < 0 or moving_to[index] != INVALID_CELL: return
	_invalidate_active_member_read_scope()
	_combat_absent_slots.erase(member_id)
	if _combat_move_plan != null:
		_combat_move_plan.remove_member(member_id, CombatMovementTypes.SlotVacancyReason.MEMBER_REMOVED)
	elif _combat_deployment_plan != null:
		_combat_deployment_plan.remove_member(member_id, CombatMovementTypes.SlotVacancyReason.MEMBER_REMOVED)
	if _combat_deployment_plan != null:
		_combat_deployment_plan.shape_version = maxi(3, _combat_deployment_plan.shape_version)
	_sync_combat_deployment_leases()
	combat_slots[index] = cells[index]
	_clear_follower_route(index)
	_active_member_scope_valid = false
	_move_encounters.erase(index)
	if _coordinator != null: _coordinator.request_occupancy_rebuild()

func siege_crew_released(member_id: int) -> void:
	var index := index_for_identity(member_id)
	if index < 0: return
	_active_member_scope_valid = false
	combat_slots[index] = cells[index]
	_clear_follower_route(index)
	if not combat_can_act(index) or _combat_deployment_plan == null: return
	if combat_order == CombatOrder.MOVE:
		# Regenerate from current goal/preset, including people released after a
		# new MOVE was accepted while they operated. Committed edges stay owned.
		_formation_change_pending = true
		_formation_retry_seconds = 0.0
		_apply_pending_formation_change()
		if not _formation_change_pending: return
		# Failed expansion keeps the current MOVE intent and retries through
		# the existing planner; an undersized old shape owns no returning slot.
		_release_combat_deployment_lease()
		_combat_move_plan = null
		_combat_deployment_plan = null
		_combat_absent_slots.clear()
		for member in range(cells.size()):
			if is_member(member) and not _siege_crew(member): combat_slots[member] = moving_to[member] if moving_to[member] != INVALID_CELL else cells[member]
		command_status = "原操作人已解除；依目前軍令等待合法隊形"
		return
	if combat_order != CombatOrder.HOLD: return
	var registry: Object = _coordinator.deployment_registry if _coordinator != null else null
	var selected := INVALID_CELL
	for cell: Vector2i in _combat_deployment_plan.platform_slots + _combat_deployment_plan.approach_queue_slots:
		if _combat_deployment_plan.slot_owner_map.has(cell) or _combat_deployment_plan.slot_lease_timers.has(cell) or not data.is_walkable(cell) or _is_external_cell(cell): continue
		if registry != null and registry.is_slot_reserved(cell, team_id): continue
		selected = cell
		break
	if selected != INVALID_CELL:
		# Typed per branch: an untyped ternary literal cannot fill Array[Vector2i].
		var slots: Array[Vector2i] = []
		if registry != null: slots = registry.get_formation_reserved_slots(team_id)
		if not slots.has(selected): slots.append(selected)
		if registry != null and not bool(registry.try_replace_reservations(team_id, _combat_deployment_plan.order_serial, _combat_deployment_plan.order_serial, slots).get("ok", false)): selected = INVALID_CELL
	if selected != INVALID_CELL and _combat_deployment_plan.reassign_returning_member(member_id, selected, registry):
		combat_slots[index] = selected
		if _combat_move_plan != null:
			_combat_move_plan.member_sequence_rank[member_id] = _combat_move_plan.member_sequence_rank.size()
			_combat_move_plan.member_lane_map[member_id] = 0
			_combat_move_plan.member_row_map[member_id] = _combat_move_plan.member_sequence_rank[member_id]
			_combat_move_plan.member_path_s[member_id] = 0.0
			_combat_move_plan.member_defer_count[member_id] = 0
	else:
		# HOLD needs no speculative destination when the former shape is full
		# or blocked. Everyone remains at their original legal stop point.
		_release_combat_deployment_lease()
		_combat_move_plan = null
		_combat_deployment_plan = null
		_combat_absent_slots.clear()
	_sync_combat_deployment_leases()

func update_combat_deployment(delta: float, _registry: Object = null) -> void:
	if _combat_deployment_plan == null:
		return
	_combat_deployment_plan.update_leases(delta)
	for mid: int in _combat_absent_slots.keys():
		var index := index_for_identity(mid)
		if index < 0 or not is_member(index) or float(combat_hot_get(index, &"hp", 0.0)) <= 0.0 or bool(combat_hot_get(index, &"departed", false)):
			if _combat_move_plan != null:
				_combat_move_plan.remove_member(mid, CombatMovementTypes.SlotVacancyReason.MEMBER_DEAD)
			else:
				_combat_deployment_plan.remove_member(mid, CombatMovementTypes.SlotVacancyReason.MEMBER_DEAD)
			_combat_absent_slots.erase(mid)
		elif combat_can_act(index) and _combat_move_plan != null and combat_order == CombatOrder.MOVE and not _move_engaging():
			var previous_slot: Vector2i = _combat_absent_slots[mid]
			var registry: Object = _coordinator.deployment_registry if _coordinator != null and "deployment_registry" in _coordinator else null
			var selected_slot: Vector2i = _combat_deployment_plan.preview_returning_member_slot(mid, previous_slot, registry)
			if selected_slot == INVALID_CELL:
				continue
			var had_team_lease := false
			var reserved := true
			if registry != null:
				var all_slots: Array[Vector2i] = registry.get_formation_reserved_slots(team_id)
				had_team_lease = all_slots.has(selected_slot)
				if not had_team_lease:
					all_slots.append(selected_slot)
					var roles: Dictionary = {}
					for owner_id in _combat_deployment_plan.member_slot_map.keys():
						roles[_combat_deployment_plan.member_slot_map[owner_id]] = _combat_deployment_plan.member_role_map[owner_id]
					for lease_slot in _combat_deployment_plan.slot_lease_timers.keys():
						roles[lease_slot] = _combat_deployment_plan.slot_lease_role_map.get(lease_slot, CombatMovementTypes.CombatDestinationRole.PLATFORM)
					roles[selected_slot] = CombatMovementTypes.CombatDestinationRole.PLATFORM if _combat_deployment_plan.platform_slots.has(selected_slot) else CombatMovementTypes.CombatDestinationRole.APPROACH_QUEUE
					reserved = bool(registry.try_replace_reservations(team_id, _combat_deployment_plan.order_serial, _combat_deployment_plan.order_serial, all_slots, roles).get("ok", false))
			if not reserved:
				continue
			if _combat_deployment_plan.reassign_returning_member(mid, previous_slot, registry):
				_combat_absent_slots.erase(mid)
				combat_slots[index] = cells[index]
			elif registry != null and not had_team_lease:
				registry.release_slots(team_id, _combat_deployment_plan.order_serial, [selected_slot])
	for mid in _combat_deployment_plan.member_slot_map.keys():
		var idx := index_for_identity(mid)
		if idx < 0 or bool(combat_units[idx].get("dead", false)) or float(combat_hot_get(idx, &"hp", 1.0)) <= 0.0:
			if _combat_move_plan != null:
				_combat_move_plan.remove_member(mid, CombatMovementTypes.SlotVacancyReason.MEMBER_DEAD)
			else:
				_combat_deployment_plan.remove_member(mid, CombatMovementTypes.SlotVacancyReason.MEMBER_DEAD)
		elif float(combat_hot_get(idx, &"ko", 0.0)) > 0.0 or str(combat_hot_get(idx, &"pose", "")) == "get_up":
			_combat_absent_slots[mid] = _combat_deployment_plan.get_slot_for_member(mid)
			if _combat_move_plan != null:
				_combat_move_plan.remove_member(mid, CombatMovementTypes.SlotVacancyReason.TEMPORARY_ABSENCE)
			else:
				_combat_deployment_plan.remove_member(mid, CombatMovementTypes.SlotVacancyReason.TEMPORARY_ABSENCE)
	for mid in _combat_deployment_plan.following_member_ids.duplicate():
		var idx := index_for_identity(mid)
		if idx < 0 or not is_member(idx) or bool(combat_units[idx].get("dead", false)) or float(combat_hot_get(idx, &"hp", 0.0)) <= 0.0 or bool(combat_hot_get(idx, &"departed", false)) or bool(combat_hot_get(idx, &"site_exited", false)):
			if _combat_move_plan != null:
				_combat_move_plan.remove_member(mid, CombatMovementTypes.SlotVacancyReason.MEMBER_DEAD)
			else:
				_combat_deployment_plan.remove_member(mid, CombatMovementTypes.SlotVacancyReason.MEMBER_DEAD)
	if _combat_move_plan != null:
		_combat_move_plan.eligible_member_count = _get_active_member_ids().size()
	_sync_combat_deployment_leases()

func get_active_members_occupancy() -> Dictionary:
	var native_roster := _native_movement_roster(2)
	if native_roster.has("value"):
		return native_roster.value
	var occ: Dictionary = {}
	for i in range(combat_units.size()):
		# The original cell-owner map is the physical authority. An independent
		# former member still blocks; KO/death release only after a safe endpoint.
		if not _ship_embarked(i) and _cell_owners.get(cells[i], -1) == i:
			if bool(combat_hot_get(i, &"site_exited", false)):
				continue
			occ[combat_identity(i)] = cells[i]
	return occ

func get_active_movement_claims() -> Dictionary:
	var claims: Dictionary = {}
	for cell in _reserved_cells.keys():
		claims[cell] = true
	return claims

func _find_contiguous_egress_cursor(macro_path: Array[Vector2i], occ: Dictionary) -> int:
	return _find_contiguous_egress_cursor_at(data, macro_path, occ, _get_combat_route_anchor_cell())

static func _find_contiguous_egress_cursor_at(map: TerrainData, macro_path: Array[Vector2i], occ: Dictionary, anchor: Vector2i) -> int:
	if macro_path.is_empty():
		return 0
	if occ.is_empty():
		return 0
	var main_cluster: Dictionary = {}
	for c: Vector2i in occ.values():
		if absi(c.x - anchor.x) + absi(c.y - anchor.y) <= 20:
			main_cluster[c] = true
	if main_cluster.is_empty():
		var sum_x := 0; var sum_y := 0
		for c: Vector2i in occ.values(): sum_x += c.x; sum_y += c.y
		var med := Vector2i(roundi(float(sum_x) / float(occ.size())), roundi(float(sum_y) / float(occ.size())))
		for c: Vector2i in occ.values():
			if absi(c.x - med.x) + absi(c.y - med.y) <= 20:
				main_cluster[c] = true

	var exit_k := 0
	var gap := 0
	var allowed_gap := maxi(1, int(ceil(FormationTransitPlanner.MEMBER_SPACING)))
	var limit := mini(60, macro_path.size())
	const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

	for k in range(limit):
		var pt := macro_path[k]
		var in_or_adjacent := false
		if main_cluster.has(pt):
			in_or_adjacent = true
		else:
			for d in DIRS:
				var adj := pt + d
				if main_cluster.has(adj):
					if map == null or (map.has_method("can_step_static") and map.can_step_static(adj, pt)) or map.can_step(adj, pt):
						in_or_adjacent = true
						break
		if in_or_adjacent:
			exit_k = k
			gap = 0
		else:
			gap += 1
			if gap > allowed_gap:
				break # Strict break: first departure from camp footprint terminates egress prefix!
	return exit_k

func _build_egress_distance_field(macro_path: Array[Vector2i], exit_k: int, profile: Object = null, max_expansions: int = 4096) -> Dictionary:
	var fid := try_get_formation_id()
	if fid <= 0: fid = team_id
	var order_serial := get_order_serial()
	var terrain_rev := 0

	var search_state: CombatMovementTypes.EgressSearchState = null
	if _coordinator != null and _coordinator.has_method("get_egress_search_state"):
		search_state = _coordinator.get_egress_search_state(fid)

	if search_state == null or not search_state.is_valid_for(fid, order_serial, terrain_rev):
		search_state = _new_egress_search_state(fid, order_serial, terrain_rev, macro_path, exit_k, get_active_members_occupancy())
	var prof := profile if profile != null else _formation_movement_profile
	_advance_egress_distance_search(data, search_state, prof, max_expansions)

	if _coordinator != null and _coordinator.has_method("save_egress_search_state"):
		_coordinator.save_egress_search_state(fid, search_state)
		if not search_state.completed:
			_coordinator.queue_egress_retry(CombatMovementTypes.EgressRetryRequest.new(fid, order_serial, terrain_rev))
			if _combat_move_plan != null:
				_combat_move_plan.egress_rank_needs_retry = true

	return search_state.distances

static func _new_egress_search_state(fid: int, serial: int, terrain_rev: int, macro_path: Array[Vector2i], exit_k: int, occupancy: Dictionary) -> CombatMovementTypes.EgressSearchState:
	var search_state := CombatMovementTypes.EgressSearchState.new()
	search_state.formation_id = fid
	search_state.order_serial = serial
	search_state.terrain_revision = terrain_rev
	for k in range(exit_k + 1):
		var pt: Vector2i = macro_path[k]
		var initial_cost: int = exit_k - k
		if not search_state.distances.has(pt) or initial_cost < int(search_state.distances[pt]):
			search_state.distances[pt] = initial_cost
			if not search_state.buckets.has(initial_cost):
				search_state.buckets[initial_cost] = []
			search_state.buckets[initial_cost].append(pt)
			search_state.max_cost = maxi(search_state.max_cost, initial_cost)
	search_state.target_member_cells = occupancy.duplicate()
	return search_state

static func _advance_egress_distance_search(map: TerrainData, search_state: CombatMovementTypes.EgressSearchState, prof: Object, max_expansions: int) -> int:
	var max_step: int = int(prof.max_step_height) if prof != null and "max_step_height" in prof else 1
	var expansions := 0
	var has_targets := not search_state.target_member_cells.is_empty()
	var unsettled_targets: Dictionary = {}
	for cell: Vector2i in search_state.target_member_cells.values():
		if not search_state.settled_cells.has(cell):
			unsettled_targets[cell] = true

	while search_state.min_cost <= search_state.max_cost and expansions < max_expansions:
		if not search_state.buckets.has(search_state.min_cost) or search_state.buckets[search_state.min_cost].is_empty():
			search_state.min_cost += 1
			continue
		var curr: Vector2i = search_state.buckets[search_state.min_cost].pop_back()
		var curr_cost: int = search_state.min_cost
		if curr_cost > int(search_state.distances.get(curr, 999999)):
			continue
		search_state.settled_cells[curr] = true
		unsettled_targets.erase(curr)
		expansions += 1
		search_state.total_expansions += 1

		var curr_h: int = FormationTransitPlanner._height_of(map, curr)

		var neighbors = map.get_geometric_adjacent_cells(curr, prof) if map != null and map.has_method("get_geometric_adjacent_cells") else (
			[curr + Vector2i(0, -1), curr + Vector2i(1, 0), curr + Vector2i(0, 1), curr + Vector2i(-1, 0)]
		)
		for neighbor in neighbors:
			if map != null:
				if not map.contains(neighbor) or not map.is_walkable(neighbor):
					continue
				if map.has_method("can_step_static"):
					if not map.can_step_static(neighbor, curr, prof):
						continue
				elif not map.can_step(neighbor, curr):
					continue
				var n_h: int = FormationTransitPlanner._height_of(map, neighbor)
				if absi(curr_h - n_h) > max_step:
					continue
			var next_cost := curr_cost + 1
			if not search_state.distances.has(neighbor) or next_cost < int(search_state.distances[neighbor]):
				search_state.distances[neighbor] = next_cost
				if not search_state.buckets.has(next_cost):
					search_state.buckets[next_cost] = []
				search_state.buckets[next_cost].append(neighbor)
				search_state.max_cost = maxi(search_state.max_cost, next_cost)

		if has_targets and unsettled_targets.is_empty():
			break

	var all_settled := true
	for mid in search_state.target_member_cells.keys():
		var mc: Vector2i = search_state.target_member_cells[mid]
		if search_state.settled_cells.has(mc):
			search_state.reachability[mid] = CombatMovementTypes.EgressReachability.REACHABLE
		elif search_state.min_cost > search_state.max_cost:
			search_state.reachability[mid] = CombatMovementTypes.EgressReachability.DISCONNECTED
		else:
			search_state.reachability[mid] = CombatMovementTypes.EgressReachability.UNRESOLVED_BUDGET
			all_settled = false

	search_state.completed = all_settled or (search_state.min_cost > search_state.max_cost)

	return expansions

func step_egress_search(_req: Object, budget: int) -> int:
	if _coordinator == null:
		return 0
	var fid := try_get_formation_id()
	if fid <= 0: fid = team_id
	var search_state: CombatMovementTypes.EgressSearchState = _coordinator.get_egress_search_state(fid)
	if search_state == null or search_state.completed:
		return 0

	var expansions := _advance_egress_distance_search(data, search_state, _formation_movement_profile, budget)
	if search_state.completed and _combat_move_plan != null:
		_combat_move_plan.egress_rank_needs_retry = false
		_reorder_members_from_distance_field(search_state.distances, search_state.reachability)

	return expansions

func _reorder_members_from_distance_field(dist_field: Dictionary, reachability: Dictionary = {}) -> void:
	if _combat_move_plan == null:
		return
	var active_mids := _get_active_member_ids()
	var sorted_mids := active_mids.duplicate()
	sorted_mids.sort_custom(func(a: int, b: int) -> bool:
		var reach_a: int = int(reachability.get(a, 0))
		var reach_b: int = int(reachability.get(b, 0))
		if reach_a != reach_b:
			return reach_a < reach_b
		var idxa := index_for_identity(a)
		var idxb := index_for_identity(b)
		var ca: int = int(dist_field.get(cells[idxa] if idxa >= 0 else Vector2i.ZERO, 999999))
		var cb: int = int(dist_field.get(cells[idxb] if idxb >= 0 else Vector2i.ZERO, 999999))
		if ca != cb:
			return ca < cb
		var ra: int = int(_combat_move_plan.member_sequence_rank.get(a, 9999))
		var rb: int = int(_combat_move_plan.member_sequence_rank.get(b, 9999))
		if ra != rb:
			return ra < rb
		return a < b
	)
	for rank in range(sorted_mids.size()):
		_combat_move_plan.member_sequence_rank[sorted_mids[rank]] = rank

func _find_combat_route_after_rejection(member_id: int, start: Vector2i, goal: Vector2i, quota: int) -> Array[Vector2i]:
	var astar_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var retry_before := int(_combat_move_plan.member_route_retry_count.get(member_id, 0)) if combat_profile_enabled else 0
	var avoid_first := int(_combat_move_plan.member_reservation_wait_age.get(member_id, 0)) >= 3
	var query_key: Array = [start, goal, data.navigation_revision, avoid_first, quota] if combat_profile_enabled else []
	var route_status: Dictionary = {}
	var route: Array[Vector2i]
	if avoid_first:
		# Spend one bounded search on a genuinely free first step. If no route
		# exists, the next slice returns to the ordinary same-direction flow.
		_combat_move_plan.member_reservation_wait_age[member_id] = 0
		route = _find_local_route(start, goal, quota, true, -1, 0, false, _formation_movement_profile, true, route_status)
	else:
		route = _find_local_route(start, goal, quota, true, -1, 0, false, _formation_movement_profile, false, route_status)
	if route.is_empty() and bool(route_status.get("capped", false)):
		var index := index_for_identity(member_id)
		if index >= 0:
			var grid: Object = _coordinator.movement_reservation_grid if _coordinator != null else null
			var step := _capped_transit_centerline_step(member_id, index, start, goal, avoid_first, grid)
			if step != INVALID_CELL:
				var centerline := _capped_transit_centerline_k(member_id, start) >= 0
				var stamp := _capped_transit_step_stamp(member_id, start, goal, step, avoid_first)
				stamp["centerline"] = centerline
				_capped_transit_steps[member_id] = stamp
				if combat_profile_enabled:
					profiled_capped_step_eligible += 1
					if centerline:
						profiled_capped_center_eligible += 1
					else:
						profiled_capped_side_eligible += 1
	if combat_profile_enabled:
		if route.size() > 1:
			profiled_route_successes += 1
			if retry_before >= 12:
				profiled_retry12_successes += 1
			_profile_last_failed_route_query.erase(member_id)
		else:
			profiled_route_failures += 1
			if retry_before >= 12:
				profiled_retry12_failures += 1
				if _profile_last_failed_route_query.get(member_id, []) == query_key:
					profiled_repeated_retry12_failures += 1
			_profile_last_failed_route_query[member_id] = query_key
	_profile_combat_stage("move_astar", astar_started)
	return route

func _transit_static_candidates(here: Vector2i, field: Dictionary, distance: int) -> Array[Vector2i]:
	var use_scope: bool = _active_member_scope and data != null and data.get_script() == TerrainData \
		and _formation_movement_profile is FormationMovementProfile
	var key := [
		_combat_move_plan.get_instance_id(), _combat_move_plan.path_epoch,
		_combat_move_plan.terrain_revision, data.navigation_revision,
		int(_formation_movement_profile.get("profile_hash")), _combat_move_plan.macro_path.back(), here
	] if use_scope else []
	if use_scope and _transit_static_candidates_cache.has(here):
		var cached: Dictionary = _transit_static_candidates_cache[here]
		if cached.get("key", []) == key:
			if combat_profile_enabled:
				profiled_scheduler_metrics["field_static_hits"] = int(profiled_scheduler_metrics.get("field_static_hits", 0)) + 1
			return cached["candidates"]
	var candidates: Array[Vector2i] = []
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var next := here + direction
		if int(field.get(next, -1)) == distance - 1 \
			and FormationTransitPlanner._can_profile_step(data, here, next, _formation_movement_profile):
			candidates.append(next)
	if combat_profile_enabled:
		profiled_scheduler_metrics["field_static_builds"] = int(profiled_scheduler_metrics.get("field_static_builds", 0)) + 1
	if use_scope:
		_transit_static_candidates_cache[here] = {"key": key, "candidates": candidates}
	return candidates

## Transit has one shared static destination field. Choose only this tick's
## physical edge; the reservation grid remains the sole occupancy arbiter.
## An empty result means this member needs the existing local route instead.
func _transit_field_intent(mid: int, index: int, grid: Object, target_context: Dictionary = {}) -> Dictionary:
	if grid == null or _coordinator == null or _combat_move_plan == null or _combat_deployment_plan == null \
		or _combat_move_plan.short_translation \
		or _combat_move_plan.phase == CombatMovementTypes.CombatMovePhase.FAILED \
		or _combat_move_plan.terrain_revision != data.navigation_revision:
		return {}
	var target: Dictionary = FormationDestinationPlanner.resolve_member_target(
		_combat_move_plan, _combat_deployment_plan, mid, cells[index], target_context
	)
	if target.get("kind", "") != "transit":
		return {}
	var field := FormationTransitPlanner.get_transit_distance_field(
		_combat_move_plan, data, _formation_movement_profile
	)
	var here: Vector2i = cells[index]
	var distance: int = int(field.get(here, -1))
	if distance <= 0:
		return {}
	var fid := try_get_formation_id()
	if fid <= 0:
		fid = team_id
	var registry: Object = _coordinator.deployment_registry
	var best := INVALID_CELL
	var best_occupancy := 2
	var temporarily_blocked := false
	for next: Vector2i in _transit_static_candidates(here, field, distance):
		if _is_external_cell(next, mid) \
			or (registry != null and registry.is_slot_reserved(next, fid)):
			continue
		if _reserved_cells.has(next) or grid.blocked_destinations.has(next):
			temporarily_blocked = true
			continue
		var owner_index: int = int(_cell_owners.get(next, -1))
		if owner_index < 0 and grid.initial_occupancy.has(next):
			continue
		var occupancy_score := 0
		if owner_index >= 0:
			if moving_to[owner_index] != INVALID_CELL:
				temporarily_blocked = true
				continue
			if not is_member(owner_index) or not combat_can_act(owner_index) or is_controlled_person(owner_index):
				continue
			var owner_id := combat_identity(owner_index)
			var owner_target: Dictionary = FormationDestinationPlanner.resolve_member_target(
				_combat_move_plan, _combat_deployment_plan, owner_id, next, target_context
			)
			if owner_target.get("kind", "") != "transit":
				continue
			occupancy_score = 1
		if occupancy_score < best_occupancy:
			best = next
			best_occupancy = occupancy_score
	return {"handled": true, "step": best} if best != INVALID_CELL or temporarily_blocked else {}

func _native_movement_reader() -> Object:
	if get_script() != TerrainArmy or _combat_hot_borrowed_index != -1:
		return null
	return _combat_hot_store if combat_hot_active() else _get_idle_kernel()

func _native_movement_terrain(profile: Object) -> Array:
	var level_only: bool = profile != null and (not bool(profile.get("can_use_ramp")) or int(profile.get("max_step_height")) < 1)
	return [data.size, data.navigation_flags(), data.navigation_heights(), data.navigation_ramps(), data.static_blocked, level_only]

func _native_movement_external_maps() -> Array:
	# Borrow original maps once per synchronous query/stage. No person packet.
	if vehicle_transport != null and not vehicle_transport.records().is_empty():
		return []
	var maps: Array = []
	var shared_valid := _shared_movement_blockers_valid()
	if shared_valid:
		maps.append(_shared_movement_blockers)
	else:
		if not _common_route_pure_readers():
			return []
	if not shared_valid and external_blocker.is_valid():
		var external_owner: Object = external_blocker.get_object()
		var teams: Array = [external_owner] if external_owner is TerrainArmy else external_owner.combat_armies
		for team: TerrainArmy in teams:
			if team == self: continue
			if team.vehicle_transport != null and not team.vehicle_transport.records().is_empty(): return []
			maps.append(team._cell_owners)
			maps.append(team._reserved_cells)
	var actor_cells: Dictionary = {}
	for actor: Variant in [player, npc]:
		if actor != null and actor.hp > 0.0 and actor.knockout_left <= 0.0:
			actor_cells[actor.terrain_cell] = true
			if actor.is_moving(): actor_cells[actor.movement_from_cell] = true
	maps.append(actor_cells) # Nonempty outer array also marks successful admission.
	return maps

func _batch_transit_field_intents(member_ids: Array[int], grid: Object, target_context: Dictionary) -> Dictionary:
	var batch_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	if not native_move_intent_enabled or data == null or data.get_script() != TerrainData \
		or _combat_move_plan == null or _combat_move_plan.get_script() != CombatMovePlan \
		or _combat_deployment_plan == null or _combat_deployment_plan.get_script() != CombatDeploymentPlan \
		or _formation_movement_profile == null or _formation_movement_profile.get_script() != FormationMovementProfile \
		or _formation_movement_profile.max_step_height < 0 \
		or _combat_move_plan.short_translation or _combat_move_plan.phase == CombatMovementTypes.CombatMovePhase.FAILED \
		or _combat_move_plan.terrain_revision != data.navigation_revision \
		or grid == null or grid.get_script() != SiteMovementReservationGrid or _coordinator == null:
		return {}
	var kernel := _native_movement_reader()
	if kernel == null or not kernel.has_method("movement_field"): return {}
	if controlled_person_query.is_valid():
		var controller: Object = controlled_person_query.get_object()
		if not controller is TerrainLab or controller.get_script() != TerrainLab \
			or controlled_person_query.get_method() != &"controlled_person_id" or controlled_person_query.get_bound_arguments_count() != 0:
			return {}
	var external_maps := _native_movement_external_maps()
	if external_maps.is_empty(): return {}
	var registry: Object = _coordinator.deployment_registry
	if registry != null and registry.get_script() != SiteDeploymentReservationRegistry: return {}
	var context := target_context
	if context.is_empty(): context = _movement_target_context()
	var field := FormationTransitPlanner.get_transit_distance_field(_combat_move_plan, data, _formation_movement_profile)
	var controlled := int(controlled_person_query.call()) if controlled_person_query.is_valid() else -1
	var packet: Array = [combat_units, cells, moving_to, member_ids, context, field, _cell_owners, _reserved_cells,
		grid.blocked_destinations, grid.initial_occupancy, external_maps, registry.slot_owners if registry != null else {},
		[get_formation_id(), controlled], _native_movement_terrain(_formation_movement_profile)]
	var intents: Dictionary = kernel.movement_field(packet)
	native_move_intent_hits += intents.size()
	if combat_profile_enabled:
		profiled_scheduler_metrics["field_batch_usec"] = int(profiled_scheduler_metrics.get("field_batch_usec", 0)) + Time.get_ticks_usec() - batch_started
		profiled_scheduler_metrics["field_batch_members"] = int(profiled_scheduler_metrics.get("field_batch_members", 0)) + intents.size()
	return intents

func _transit_field_made_physical_progress(active_mids: Array[int], current_cells: Dictionary, target_context: Dictionary = {}) -> bool:
	if _combat_move_plan == null or _combat_deployment_plan == null:
		return false
	var field := FormationTransitPlanner.get_transit_distance_field(
		_combat_move_plan, data, _formation_movement_profile
	)
	var key := [_combat_move_plan.order_serial, _combat_move_plan.path_epoch, data.navigation_revision]
	var previous: Dictionary = _combat_move_plan.get_meta("_transit_physical_previous", {}) if _combat_move_plan.get_meta("_transit_physical_key", []) == key else {}
	var next_samples: Dictionary = {}
	var progressed := false
	for mid in active_mids:
		if not current_cells.has(mid):
			continue
		var cell: Vector2i = current_cells[mid]
		var distance: int = int(field.get(cell, -1))
		next_samples[mid] = [cell, distance]
		if distance < 0 or not previous.has(mid):
			continue
		var old_sample: Array = previous[mid]
		var old_cell: Vector2i = old_sample[0]
		if old_cell == cell or int(old_sample[1]) <= distance \
			or not FormationTransitPlanner._can_profile_step(data, old_cell, cell, _formation_movement_profile):
			continue
		var target: Dictionary = FormationDestinationPlanner.resolve_member_target(
			_combat_move_plan, _combat_deployment_plan, mid, cell, target_context
		)
		if target.get("kind", "") == "transit":
			progressed = true
	_combat_move_plan.set_meta("_transit_physical_key", key)
	_combat_move_plan.set_meta("_transit_physical_previous", next_samples)
	return progressed

func _capped_transit_centerline_step(mid: int, index: int, start: Vector2i, goal: Vector2i, avoid_first: bool, grid: Object) -> Vector2i:
	if grid == null or data == null or _coordinator == null or _formation_movement_profile == null \
		or _combat_move_plan == null or _combat_deployment_plan == null or combat_order != CombatOrder.MOVE \
		or _combat_move_plan.phase != CombatMovementTypes.CombatMovePhase.TRANSIT \
		or _combat_move_plan.destination_plan != _combat_deployment_plan or _combat_deployment_plan.approach_bottlenecked != 1 \
		or _combat_move_plan.order_serial != _combat_deployment_plan.order_serial \
		or _combat_move_plan.terrain_revision != data.navigation_revision \
		or index < 0 or not is_member(index) or not combat_can_act(index) or is_controlled_person(index) \
		or _combat_action_blocks_step(index) or moving_to[index] != INVALID_CELL \
		or cells[index] != start or int(_cell_owners.get(start, -1)) != index \
		or int(grid.initial_occupancy.get(start, -1)) != mid \
		or goal != _combat_move_plan.member_transit_slots.get(mid, INVALID_CELL):
		return INVALID_CELL
	var path: Array[Vector2i] = _combat_move_plan.macro_path
	var k := _capped_transit_centerline_k(mid, start)
	var centerline := k >= 0
	var row_lookup: Dictionary = {}
	if not centerline:
		row_lookup = _capped_transit_row_lookup()
		k = int(row_lookup.get(start, -1))
	if k < 0 or k + 1 >= path.size() \
		or float(_combat_move_plan.member_path_s.get(mid, -1.0)) <= float(k):
		return INVALID_CELL
	# Geometric translation keeps the same physical lane; static row membership rejects bends and narrowing.
	var next: Vector2i = start + path[k + 1] - path[k]
	if path[k + 1] - path[k] not in TerrainData.DIRECTIONS \
		or (path.count(next) != 1 if centerline else int(row_lookup.get(next, -1)) != k + 1) \
		or FormationTransitPlanner._find_furthest_verified_head_s(k, k + 1, _combat_move_plan, data, _formation_movement_profile) < float(k + 1) \
		or not FormationTransitPlanner._can_profile_step(data, start, next, _formation_movement_profile) \
		or _is_external_cell(next, mid) or _reserved_cells.has(next) or grid.blocked_destinations.has(next):
		return INVALID_CELL
	var fid := try_get_formation_id()
	if fid <= 0:
		fid = team_id
	if _coordinator.deployment_registry == null or _coordinator.deployment_registry.is_slot_reserved(next, fid):
		return INVALID_CELL
	var owner_index := int(_cell_owners.get(next, -1))
	var grid_owner := int(grid.initial_occupancy.get(next, -1))
	if owner_index < 0:
		return next if grid_owner < 0 else INVALID_CELL
	if avoid_first or owner_index >= combat_units.size() or not is_member(owner_index) \
		or not combat_can_act(owner_index) or is_controlled_person(owner_index) \
		or _combat_action_blocks_step(owner_index) or moving_to[owner_index] != INVALID_CELL \
		or cells[owner_index] != next or cells[owner_index] == combat_slots[owner_index] \
		or grid_owner != combat_identity(owner_index):
		return INVALID_CELL
	return next

func _capped_transit_centerline_k(mid: int, start: Vector2i) -> int:
	var path: Array[Vector2i] = _combat_move_plan.macro_path
	var k := int(_combat_move_plan.member_observed_path_k.get(mid, -1))
	return k if k >= 0 and k + 1 < path.size() and path[k] == start and path.count(start) == 1 else -1

func _capped_transit_row_lookup() -> Dictionary:
	var plan := _combat_move_plan
	var key := [plan.path_epoch, plan.terrain_revision, data.navigation_revision, _formation_movement_profile.profile_hash, plan.macro_path.size()]
	if plan.get_meta("_capped_step_rows_key", []) == key:
		return plan.get_meta("_capped_step_rows", {})
	var lookup: Dictionary = {}
	var rows: Array = FormationTransitPlanner._get_static_row_sections(plan, data, _formation_movement_profile)
	for k in range(rows.size()):
		for cell: Vector2i in rows[k]:
			if lookup.has(cell) and int(lookup[cell]) != k:
				lookup[cell] = -1
			elif not lookup.has(cell):
				lookup[cell] = k
	plan.set_meta("_capped_step_rows", lookup)
	plan.set_meta("_capped_step_rows_key", key)
	return lookup

func _capped_transit_step_stamp(mid: int, start: Vector2i, goal: Vector2i, step: Vector2i, avoid_first: bool) -> Dictionary:
	return {
		"tick": current_logic_tick, "from": start, "goal": goal, "to": step, "avoid_first": avoid_first,
		"order": _combat_move_plan.order_serial, "path_epoch": _combat_move_plan.path_epoch,
		"terrain": data.navigation_revision,
		"assignment": int(_combat_move_plan.member_assignment_epoch.get(mid, 0)),
		"soft_assignment": int(_combat_move_plan.member_soft_assignment_epoch.get(mid, 0)),
		"proposal_id": -1,
		"deferred": false,
	}

func _current_capped_transit_step(mid: int, index: int, goal: Vector2i, grid: Object) -> Vector2i:
	if not _capped_transit_steps.has(mid) or _combat_move_plan == null or data == null:
		return INVALID_CELL
	var stamp: Dictionary = _capped_transit_steps[mid]
	if int(stamp["tick"]) != current_logic_tick or stamp["from"] != cells[index] or stamp["goal"] != goal \
		or int(stamp["order"]) != _combat_move_plan.order_serial or int(stamp["path_epoch"]) != _combat_move_plan.path_epoch \
		or int(stamp["terrain"]) != data.navigation_revision \
		or int(stamp["assignment"]) != int(_combat_move_plan.member_assignment_epoch.get(mid, 0)) \
		or int(stamp["soft_assignment"]) != int(_combat_move_plan.member_soft_assignment_epoch.get(mid, 0)):
		return INVALID_CELL
	var step := _capped_transit_centerline_step(mid, index, cells[index], goal, bool(stamp["avoid_first"]), grid)
	return step if step == stamp["to"] else INVALID_CELL

func _profile_scheduler_route(pool: String, route: Array[Vector2i], quota: int, expanded_before: int, cap_before: int, billed_expansions: int) -> void:
	if not combat_profile_enabled:
		return
	profiled_scheduler_metrics[pool + "_calls"] = int(profiled_scheduler_metrics.get(pool + "_calls", 0)) + 1
	var outcome := "_success" if route.size() > 1 else "_fail"
	profiled_scheduler_metrics[pool + outcome] = int(profiled_scheduler_metrics.get(pool + outcome, 0)) + 1
	profiled_scheduler_metrics[pool + "_actual_expansions"] = int(profiled_scheduler_metrics.get(pool + "_actual_expansions", 0)) + expanded_nodes - expanded_before
	profiled_scheduler_metrics[pool + "_billed_expansions"] = int(profiled_scheduler_metrics.get(pool + "_billed_expansions", 0)) + billed_expansions
	profiled_scheduler_metrics[pool + "_cap_fail"] = int(profiled_scheduler_metrics.get(pool + "_cap_fail", 0)) + profiled_search_cap_failures - cap_before
	var quota_bucket := pool + "_quota_" + str(quota)
	profiled_scheduler_metrics[quota_bucket] = int(profiled_scheduler_metrics.get(quota_bucket, 0)) + 1

func _refresh_member_route_caches(route_budget: Object, target_context: Dictionary = {}, prepared_active_mids: Array[int] = []) -> void:
	if _combat_move_plan == null:
		return
	var route_cache_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var active_mids := prepared_active_mids if not prepared_active_mids.is_empty() else _get_active_member_ids()
	var needs_route: Array[int] = []
	var grid: Object = _coordinator.movement_reservation_grid if _coordinator != null else null
	var field_intents := _batch_transit_field_intents(active_mids, grid, target_context)

	for mid in active_mids:
		var idx := index_for_identity(mid)
		if idx < 0 or not is_member(idx) or not combat_can_act(idx) or is_controlled_person(idx):
			continue
		if moving_to[idx] != INVALID_CELL:
			continue
		# A target may change while its committed edge is in flight. Keep that
		# edge's route until arrival, then discard it before the field can handle
		# this member and bypass the ordinary route-current check below.
		if _combat_move_plan.member_paths.has(mid) and not _combat_move_plan.is_member_route_current(mid, combat_slots[idx]):
			_combat_move_plan.invalidate_member_route(mid)
		var field_intent: Dictionary = field_intents[mid] if field_intents.has(mid) else _transit_field_intent(mid, idx, grid, target_context)
		if bool(field_intent.get("handled", false)):
			continue
		var goal_cell: Vector2i = combat_slots[idx]
		if cells[idx] == goal_cell:
			continue
		var diff := goal_cell - cells[idx]
		if (absi(diff.x) + absi(diff.y) == 1) and int(_combat_move_plan.member_reservation_wait_age.get(mid, 0)) < 3 \
			and FormationTransitPlanner._can_profile_step(data, cells[idx], goal_cell, _formation_movement_profile):
			continue
		if _combat_move_plan.is_member_route_current(mid, goal_cell):
			var p: Array[Vector2i] = _combat_move_plan.member_paths[mid]
			if p.size() > 1 and p[0] == cells[idx] and p[-1] == goal_cell:
				continue
		_combat_move_plan.invalidate_member_route(mid)
		needs_route.append(mid)
	if combat_profile_enabled:
		profiled_scheduler_metrics["needs_route"] = int(profiled_scheduler_metrics.get("needs_route", 0)) + needs_route.size()

	if needs_route.is_empty():
		_profile_combat_stage("move_route_cache", route_cache_started)
		return

	var vanguard_cutoff: int = mini(8, maxi(2, _combat_move_plan.current_width * 2))
	var vanguard_candidates: Array[int] = []
	var rear_candidates: Array[int] = []

	for mid in needs_route:
		var rank: int = int(_combat_move_plan.member_sequence_rank.get(mid, 9999))
		if rank < vanguard_cutoff:
			vanguard_candidates.append(mid)
		else:
			rear_candidates.append(mid)
	if combat_profile_enabled:
		profiled_scheduler_metrics["rear_candidates"] = int(profiled_scheduler_metrics.get("rear_candidates", 0)) + rear_candidates.size()
		profiled_scheduler_metrics["front_candidates"] = int(profiled_scheduler_metrics.get("front_candidates", 0)) + vanguard_candidates.size()

	# Sort vanguard by rank ascending
	vanguard_candidates.sort_custom(func(a: int, b: int) -> bool:
		return int(_combat_move_plan.member_sequence_rank.get(a, 9999)) < int(_combat_move_plan.member_sequence_rank.get(b, 9999))
	)
	# Sort rear candidates by defer count descending (aging), then rank ascending
	rear_candidates.sort_custom(func(a: int, b: int) -> bool:
		var da: int = int(_combat_move_plan.member_defer_count.get(a, 0))
		var db: int = int(_combat_move_plan.member_defer_count.get(b, 0))
		if da != db:
			return da > db
		return int(_combat_move_plan.member_sequence_rank.get(a, 9999)) < int(_combat_move_plan.member_sequence_rank.get(b, 9999))
	)

	var fid := try_get_formation_id()
	if fid <= 0: fid = team_id

	# Determine total call & expansion budget and fair aging guarantee
	var total_calls := 8
	var total_expansions := 1024
	if route_budget != null:
		var alloc: Dictionary = route_budget.get_allocation(fid)
		total_calls = int(alloc.get("remaining_calls", 0))
		total_expansions = int(alloc.get("remaining_expansions", 0))
		if total_calls <= 0 and route_budget.can_request_route(fid):
			total_calls = 1

	const MIN_ROUTE_EXPANSIONS_PER_CALL := 64
	var aging_calls := 0
	var aging_expansions := 0
	if not rear_candidates.is_empty() and total_calls > 0:
		aging_calls = mini(total_calls, maxi(1, ceili(float(total_calls) / 2.0)))
		aging_expansions = mini(total_expansions, maxi(MIN_ROUTE_EXPANSIONS_PER_CALL, ceili(float(total_expansions) / 2.0)))
	var emergency_calls := total_calls - aging_calls
	var emergency_expansions := total_expansions - aging_expansions

	var scheduled_mids: Dictionary = {}
	var aging_calls_used := 0
	var aging_expansions_used := 0

	# Pass 1: Run AGING pool first (guaranteed calls + expansions)
	for mid in rear_candidates:
		if aging_calls_used >= aging_calls or (aging_expansions_used >= aging_expansions and aging_calls_used > 0):
			break
		if route_budget != null and not route_budget.can_request_route(fid):
			break
		var idx := index_for_identity(mid)
		var goal_cell: Vector2i = combat_slots[idx]
		var calls_left := aging_calls - aging_calls_used
		var rem_exp := aging_expansions - aging_expansions_used
		var quota: int = mini(256, rem_exp - (calls_left - 1) * 32)
		quota = clampi(quota, 32, rem_exp)
		if route_budget != null:
			quota = mini(quota, route_budget.request_route_budget(fid))
		var expanded_before := expanded_nodes
		var cap_before := profiled_search_cap_failures if combat_profile_enabled else 0
		var route := _find_combat_route_after_rejection(mid, cells[idx], goal_cell, quota)
		var used_exp := mini(quota, maxi(32, expanded_nodes - expanded_before))
		_profile_scheduler_route("pass1_rear", route, quota, expanded_before, cap_before, used_exp)
		if route_budget != null:
			route_budget.record_route_result(fid, 1, used_exp)
		if route.size() > 1:
			_combat_move_plan.member_paths[mid] = route.duplicate()
			_combat_move_plan.stamp_member_route(mid, goal_cell)
			_combat_move_plan.member_defer_count[mid] = 0
		else:
			_combat_move_plan.member_route_retry_count[mid] = int(_combat_move_plan.member_route_retry_count.get(mid, 0)) + 1
			if used_exp > 0:
				_combat_move_plan.member_defer_count[mid] = 0
		scheduled_mids[mid] = true
		aging_calls_used += 1
		aging_expansions_used += used_exp

	# Pass 2: Run EMERGENCY pool with emergency quota + unused aging quota
	var emergency_calls_avail := emergency_calls + (aging_calls - aging_calls_used)
	var emergency_expansions_avail := emergency_expansions + (aging_expansions - aging_expansions_used)
	var emergency_calls_used := 0
	var emergency_expansions_used := 0

	for mid in vanguard_candidates:
		if emergency_calls_used >= emergency_calls_avail or (emergency_expansions_used >= emergency_expansions_avail and emergency_calls_used > 0):
			break
		if route_budget != null and not route_budget.can_request_route(fid):
			break
		var idx := index_for_identity(mid)
		var goal_cell: Vector2i = combat_slots[idx]
		var calls_left := emergency_calls_avail - emergency_calls_used
		var rem_exp := emergency_expansions_avail - emergency_expansions_used
		var quota: int = mini(256, rem_exp - (calls_left - 1) * 32)
		quota = clampi(quota, 32, rem_exp)
		if route_budget != null:
			quota = mini(quota, route_budget.request_route_budget(fid))
		var expanded_before := expanded_nodes
		var cap_before := profiled_search_cap_failures if combat_profile_enabled else 0
		var route := _find_combat_route_after_rejection(mid, cells[idx], goal_cell, quota)
		var used_exp := mini(quota, maxi(32, expanded_nodes - expanded_before))
		_profile_scheduler_route("pass2_front", route, quota, expanded_before, cap_before, used_exp)
		if route_budget != null:
			route_budget.record_route_result(fid, 1, used_exp)
		if route.size() > 1:
			_combat_move_plan.member_paths[mid] = route.duplicate()
			_combat_move_plan.stamp_member_route(mid, goal_cell)
			_combat_move_plan.member_defer_count[mid] = 0
		else:
			_combat_move_plan.member_route_retry_count[mid] = int(_combat_move_plan.member_route_retry_count.get(mid, 0)) + 1
			if used_exp > 0:
				_combat_move_plan.member_defer_count[mid] = 0
		scheduled_mids[mid] = true
		emergency_calls_used += 1
		emergency_expansions_used += used_exp

	# Pass 3: Any remaining budget returns to remaining unserved candidates
	var remaining_calls := emergency_calls_avail - emergency_calls_used
	var remaining_exp := emergency_expansions_avail - emergency_expansions_used
	for mid in rear_candidates:
		if scheduled_mids.has(mid) or remaining_calls <= 0 or remaining_exp < 32:
			continue
		if route_budget != null and not route_budget.can_request_route(fid):
			break
		var idx := index_for_identity(mid)
		var goal_cell: Vector2i = combat_slots[idx]
		var quota: int = mini(256, remaining_exp - (remaining_calls - 1) * 32)
		quota = clampi(quota, 32, remaining_exp)
		if route_budget != null:
			quota = mini(quota, route_budget.request_route_budget(fid))
		var expanded_before := expanded_nodes
		var cap_before := profiled_search_cap_failures if combat_profile_enabled else 0
		var route := _find_combat_route_after_rejection(mid, cells[idx], goal_cell, quota)
		var used_exp := mini(quota, maxi(32, expanded_nodes - expanded_before))
		_profile_scheduler_route("pass3_rear", route, quota, expanded_before, cap_before, used_exp)
		if route_budget != null:
			route_budget.record_route_result(fid, 1, used_exp)
		if route.size() > 1:
			_combat_move_plan.member_paths[mid] = route.duplicate()
			_combat_move_plan.stamp_member_route(mid, goal_cell)
			_combat_move_plan.member_defer_count[mid] = 0
		else:
			_combat_move_plan.member_route_retry_count[mid] = int(_combat_move_plan.member_route_retry_count.get(mid, 0)) + 1
			if used_exp > 0:
				_combat_move_plan.member_defer_count[mid] = 0
		scheduled_mids[mid] = true
		remaining_calls -= 1
		remaining_exp -= used_exp
	# A member without a search slice may still take one verified physical row edge.
	# Probe unserved front first so a zero-budget formation cannot starve it behind rear members.
	# Keep the probe bounded and leave route allocation and aging unchanged.
	var deferred_order: Array[int] = vanguard_candidates.duplicate()
	deferred_order.append_array(rear_candidates)
	var deferred_inspections := 0
	var deferred_eligible := 0
	for mid in deferred_order:
		if deferred_inspections >= 16 or deferred_eligible >= 8:
			break
		if scheduled_mids.has(mid) or _capped_transit_steps.has(mid):
			continue
		var idx := index_for_identity(mid)
		if idx < 0 or _combat_move_plan.is_member_route_current(mid, combat_slots[idx]):
			continue
		deferred_inspections += 1
		var goal_cell: Vector2i = combat_slots[idx]
		var avoid_first := int(_combat_move_plan.member_reservation_wait_age.get(mid, 0)) >= 3
		var step := _capped_transit_centerline_step(mid, idx, cells[idx], goal_cell, avoid_first, grid)
		if step == INVALID_CELL:
			continue
		var stamp := _capped_transit_step_stamp(mid, cells[idx], goal_cell, step, avoid_first)
		stamp["deferred"] = true
		stamp["centerline"] = _capped_transit_centerline_k(mid, cells[idx]) >= 0
		_capped_transit_steps[mid] = stamp
		deferred_eligible += 1
		if combat_profile_enabled:
			profiled_deferred_step_eligible += 1

	# Age unserved candidates
	for mid in needs_route:
		if not scheduled_mids.has(mid):
			_combat_move_plan.member_defer_count[mid] = int(_combat_move_plan.member_defer_count.get(mid, 0)) + 1
	if combat_profile_enabled:
		var rear_backlog := 0
		var front_backlog := 0
		for mid in rear_candidates:
			if not scheduled_mids.has(mid):
				rear_backlog += 1
		for mid in vanguard_candidates:
			if not scheduled_mids.has(mid):
				front_backlog += 1
		profiled_scheduler_metrics["rear_backlog"] = int(profiled_scheduler_metrics.get("rear_backlog", 0)) + rear_backlog
		profiled_scheduler_metrics["front_backlog"] = int(profiled_scheduler_metrics.get("front_backlog", 0)) + front_backlog
	_profile_combat_stage("move_route_cache", route_cache_started)

func _retain_member_route_to_target(mid: int, index: int, target: Vector2i) -> bool:
	if _combat_move_plan == null or data == null or _combat_move_plan.terrain_revision != data.navigation_revision \
		or moving_to[index] != INVALID_CELL:
		return false
	var old_target: Vector2i = combat_slots[index]
	if not _combat_move_plan.is_member_route_current(mid, old_target):
		return false
	var path: Array[Vector2i] = _combat_move_plan.member_paths[mid]
	var target_index := path.find(target)
	if target_index <= 0 or path.size() < 2 or path[0] != cells[index] \
		or not FormationTransitPlanner._can_profile_step(data, path[0], path[1], _formation_movement_profile) \
		or _is_external_cell(path[1], mid) \
		or (_reserved_cells.has(path[1]) and int(_reserved_cells[path[1]]) != index):
		return false
	path.resize(target_index + 1)
	_combat_move_plan.member_paths[mid] = path
	_combat_move_plan.stamp_member_route(mid, target)
	return true

func _release_combat_deployment_lease() -> void:
	if _coordinator == null or not ("deployment_registry" in _coordinator):
		return
	var registry: Object = _coordinator.deployment_registry
	if registry != null:
		registry.release_order(team_id)

func cancel_combat_deployment_for_forced_order() -> void:
	# Sustain transitions bypass issue_combat_order. Preserve any physical batch.
	_corps_reposition_source.clear()
	_release_combat_deployment_lease()
	_move_encounters.clear()
	_move_landed_members.clear()
	_combat_move_plan = null
	_combat_deployment_plan = null
	_combat_absent_slots.clear()
	for index in range(cells.size()):
		if is_member(index) and not _ship_embarked(index):
			combat_slots[index] = moving_to[index] if moving_to[index] != INVALID_CELL else cells[index]

func _sync_combat_deployment_leases() -> void:
	if _combat_deployment_plan == null or _coordinator == null or not ("deployment_registry" in _coordinator):
		return
	var registry: Object = _coordinator.deployment_registry
	if registry == null:
		return
	var vacated: Array[Vector2i] = []
	for slot: Vector2i in registry.get_formation_reserved_slots(team_id):
		var protected_fire_lease := false
		if _fire_nav_context_current():
			for lease: Variant in _fire_navigation.leases.values():
				if lease != null and lease.cell == slot and is_same(registry.owner_of(slot), lease): protected_fire_lease = true; break
		if protected_fire_lease: continue
		if not _combat_deployment_plan.slot_owner_map.has(slot) and not _combat_deployment_plan.slot_lease_timers.has(slot):
			vacated.append(slot)
	if not vacated.is_empty():
		registry.release_slots(team_id, _combat_deployment_plan.order_serial, vacated)

func _finish_combat_absences() -> void:
	# Completed MOVE leaves the wounded in place until a new order. Its temporary
	# absence leases must end with the MOVE; HOLD saves have no absent-member list.
	if _combat_deployment_plan != null:
		_combat_deployment_plan.slot_lease_timers.clear()
		_combat_deployment_plan.slot_lease_owner_map.clear()
		_combat_deployment_plan.slot_lease_role_map.clear()
		_combat_deployment_plan.slot_lease_queue_index_map.clear()
	_combat_absent_slots.clear()
	_sync_combat_deployment_leases()

func _wait_for_structure_route() -> void:
	if _combat_move_plan == null: return
	var anchor := _get_combat_route_anchor_cell()
	_combat_move_plan.reset_path_coordinates([anchor])
	_combat_move_plan.structure_blocked = true
	_combat_move_plan.structure_roster_hash = _get_active_member_ids().hash()
	_combat_move_plan.terrain_revision = data.navigation_revision
	_combat_move_plan.active_vacancy_chain_actors.clear()
	_combat_move_plan.member_vacancy_chain_start_cell.clear()
	_combat_move_plan.member_vacancy_chain_target.clear()
	_combat_move_plan.member_recovery_vacated_cell.clear()
	_combat_move_plan.verified_chain_arrival_members.clear()
	_combat_move_plan.verified_chain_arrival_pending = false
	command_status = "結構毀損後暫無合法通路；保留原命令、目標與部署位置"

func _refresh_move_terrain_revision() -> bool:
	if _combat_move_plan == null or data == null or _combat_deployment_plan == null:
		return false
	var members_hash := _get_active_member_ids().hash()
	if _combat_move_plan.structure_blocked and _combat_move_plan.terrain_revision == data.navigation_revision and _combat_move_plan.structure_roster_hash == members_hash:
		return false
	if not _combat_move_plan.structure_blocked and _combat_move_plan.terrain_revision == data.navigation_revision:
		return true
	if _formation_movement_profile == null:
		_formation_movement_profile = FormationMovementProfile.from_members(_get_active_member_ids(), self)
	var new_path := FormationTransitPlanner.build_macro_path(data, _get_combat_route_anchor_cell(), _combat_deployment_plan.resolved_anchor, _formation_movement_profile)
	if not new_path.is_empty() and FormationDestinationPlanner.refresh_derived_ingress(_combat_deployment_plan, data, new_path, _formation_movement_profile):
		_combat_move_plan.reset_path_coordinates(new_path)
		_combat_move_plan.structure_blocked = false
		_combat_move_plan.terrain_revision = data.navigation_revision
		_combat_deployment_plan.terrain_revision = data.navigation_revision
		for mid in _get_active_member_ids():
			_combat_move_plan.invalidate_member_route(mid)
		return true
	if _preserve_structure_order:
		_wait_for_structure_route()
		return false
	_release_combat_deployment_lease()
	_combat_absent_slots.clear()
	combat_order = CombatOrder.HOLD
	command_status = "地形變更後無合法通路或部署位置；就地防禦，等待新令"
	_combat_move_plan = null
	_combat_deployment_plan = null
	for index in range(cells.size()):
		if is_member(index):
			combat_slots[index] = moving_to[index] if moving_to[index] != INVALID_CELL else cells[index]
	return false

func _refresh_recovery_path_coordinates(delta: float) -> bool:
	if _combat_move_plan == null or _combat_deployment_plan == null:
		return false
	if not FormationDestinationPlanner.refresh_derived_ingress(
		_combat_deployment_plan, data, _combat_move_plan.macro_path, _formation_movement_profile
	):
		if _preserve_structure_order:
			_wait_for_structure_route()
			return false
		_release_combat_deployment_lease()
		_combat_absent_slots.clear()
		combat_order = CombatOrder.HOLD
		command_status = "重新尋路後無合法部署進路；就地防禦，等待新令"
		_combat_move_plan = null
		_combat_deployment_plan = null
		for index in range(cells.size()):
			if is_member(index):
				combat_slots[index] = moving_to[index] if moving_to[index] != INVALID_CELL else cells[index]
		return false
	var occ := get_active_members_occupancy()
	FormationTransitPlanner.calculate_transit_slots(
		_combat_move_plan, data, _formation_movement_profile, _get_active_member_ids(), occ
	)
	FormationDestinationPlanner.update_movement_phase(
		_combat_move_plan, _combat_deployment_plan, occ, data, delta,
		_coordinator.deployment_registry if _coordinator != null and "deployment_registry" in _coordinator else null,
		_current_movement_blocked_destinations(), r3_prepare_enabled
	)
	for index in range(combat_units.size()):
		if not is_member(index) or not combat_can_act(index):
			continue
		var mid := combat_identity(index)
		var target: Dictionary = FormationDestinationPlanner.resolve_member_target(
			_combat_move_plan, _combat_deployment_plan, mid, cells[index]
		)
		combat_slots[index] = target.get("target", cells[index])
	return true

func _current_movement_blocked_destinations() -> Dictionary:
	if _coordinator != null and "movement_reservation_grid" in _coordinator:
		var grid: Object = _coordinator.movement_reservation_grid
		if grid != null and "blocked_destinations" in grid:
			return grid.blocked_destinations
	return {}

func _automatic_deployment_settled() -> bool:
	if _combat_deployment_plan == null or not _combat_deployment_plan.following_member_ids.is_empty():
		return false
	for mid in _combat_deployment_plan.member_slot_map.keys():
		var index := index_for_identity(mid)
		if index < 0:
			return false
		if index == PLAYER_MEMBER or is_controlled_person(index):
			continue
		if moving_to[index] != INVALID_CELL or cells[index] != _combat_deployment_plan.member_slot_map[mid]:
			return false
	return true

func _settled_deployment_leases_valid() -> bool:
	if _combat_deployment_plan == null:
		return false
	if _coordinator == null or not ("deployment_registry" in _coordinator):
		return true
	var registry: Object = _coordinator.deployment_registry
	for slot: Vector2i in _combat_deployment_plan.member_slot_map.values():
		var lease = registry.owner_of(slot)
		if lease == null or lease.formation_id != team_id or lease.order_serial != _combat_deployment_plan.order_serial:
			return false
	return true

func _orient_settled_combat_members() -> void:
	if _combat_deployment_plan == null:
		return
	for mid in _combat_deployment_plan.member_slot_map.keys():
		var index := index_for_identity(mid)
		if index < 0 or index == PLAYER_MEMBER or is_controlled_person(index) or moving_to[index] != INVALID_CELL \
			or cells[index] != _combat_deployment_plan.member_slot_map[mid]:
			continue
		facing[index] = _combat_deployment_plan.get_facing_for_slot(cells[index])
	_visual_dirty = true

func _movement_target_context() -> Dictionary:
	if _combat_move_plan == null or _combat_deployment_plan == null \
		or _combat_move_plan.get_script() != CombatMovePlan or _combat_deployment_plan.get_script() != CombatDeploymentPlan:
		return {}
	if native_move_intent_enabled:
		var kernel := _native_movement_reader()
		if kernel != null and kernel.has_method("movement_targets"):
			var context: Dictionary = kernel.movement_targets(combat_units, cells, _combat_move_plan, _combat_deployment_plan)
			if context.has("targets"): return context
	var footprint: Dictionary = {}
	for cell: Vector2i in _combat_deployment_plan.platform_footprint:
		footprint[cell] = true
	return {"footprint": footprint, "targets": {}}

func prepare_combat_movement_tick(delta: float, route_budget: Object, deployment_registry: Object) -> void:
	if has_ship_journey(): return # Coarse owner retains the original team order.
	_capped_transit_steps.clear()
	if not combat_enabled:
		return
	# Disjoint prepare sections. Existing transit/phase/route-cache timers are
	# siblings; route-cache still contains move_astar. No section spans returns.
	var life_deploy_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	if _coordinator != null and "current_logic_tick" in _coordinator:
		current_logic_tick = int(_coordinator.current_logic_tick)
	else:
		current_logic_tick += 1
	if _prepare_fire_navigation(route_budget, delta): return
	if _combat_deployment_plan != null:
		update_combat_deployment(delta, deployment_registry)
	_profile_combat_stage("move_prepare_life_deploy", life_deploy_started)
	_prepare_suppress_approach(route_budget)
	if _combat_move_plan == null or combat_order != CombatOrder.MOVE:
		return
	var contact_terrain_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	_probe_move_landing_contact()
	if not _refresh_move_terrain_revision():
		_profile_combat_stage("move_prepare_contact_terrain", contact_terrain_started)
		return
	_profile_combat_stage("move_prepare_contact_terrain", contact_terrain_started)

	if _order_delay > 0.0:
		_order_delay = maxf(0.0, _order_delay - delta)
		return
	if _move_engaging():
		return

	if _combat_move_plan.short_translation:
		# Keep the fixed translated targets. The shared reservation grid decides
		# which adjacent steps may start together and finishes them after 0.38 s.
		for mid in _combat_deployment_plan.member_slot_map.keys():
			var index := index_for_identity(mid)
			if index < 0:
				continue
			var target: Vector2i = _combat_deployment_plan.get_slot_for_member(mid)
			if moving_to[index] == INVALID_CELL and cells[index] == target:
				_combat_deployment_plan.mark_platform_member_settled(mid)
			elif combat_can_act(index) and not is_controlled_person(index):
				combat_slots[index] = target
		if not (_combat_batch_members.is_empty() and _automatic_deployment_settled()):
			return

	var occupancy_settled_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var occ := get_active_members_occupancy()
	if not _combat_deployment_plan.following_member_ids.is_empty():
		var following_active: Dictionary = {}
		for mid: int in _get_active_member_ids():
			if occ.has(mid):
				following_active[mid] = occ[mid]
		var candidates: Array[Vector2i] = []
		candidates.assign(_combat_deployment_plan.platform_footprint)
		var blocked := _deployment_blocked_cells(candidates, _get_active_member_ids())
		FormationDestinationPlanner.refresh_following_members(_combat_move_plan, _combat_deployment_plan, following_active, data, deployment_registry, blocked)
	var settled := _combat_batch_members.is_empty() and _automatic_deployment_settled()
	_profile_combat_stage("move_prepare_occupancy_settled", occupancy_settled_started)
	if settled:
		var settled_phase_started := Time.get_ticks_usec() if combat_profile_enabled else 0
		if not _combat_move_plan.short_translation:
			FormationDestinationPlanner.update_movement_phase(_combat_move_plan, _combat_deployment_plan, occ, data, delta, deployment_registry, _current_movement_blocked_destinations(), r3_prepare_enabled)
		_profile_combat_stage("move_phase", settled_phase_started)
		_orient_settled_combat_members()
		var absent_count := _combat_absent_slots.size()
		_finish_combat_absences()
		combat_order = CombatOrder.HOLD
		_corps_reposition_source.clear()
		_clear_member_attack_targets()
		command_status = "已抵達：平台部署 %d 人，進路待命 %d 人%s" % [
			_combat_deployment_plan.settled_platform_member_ids.size(),
			_combat_deployment_plan.queue_member_ids.size(),
			"；%d 名傷員原地待新令" % absent_count if absent_count > 0 else ""
		]
		_combat_move_plan = null
		return

	var ingress_width_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	FormationRecoveryController.set_engaging_overlay(_combat_move_plan, combat_attacking)
	FormationDestinationPlanner.update_ingress_gate(_combat_deployment_plan, occ)
	var cur_medoid := _get_active_members_medoid()

	var fwd := Vector2i(1, 0)
	if _combat_move_plan.macro_path.size() > 1:
		var c_idx: int = clampi(_combat_move_plan.macro_cursor, 0, _combat_move_plan.macro_path.size() - 2)
		fwd = _combat_move_plan.macro_path[c_idx + 1] - _combat_move_plan.macro_path[c_idx]
	var center_c: Vector2i = _combat_move_plan.macro_path[clampi(_combat_move_plan.macro_cursor, 0, _combat_move_plan.macro_path.size() - 1)]
	var detected_w := FormationTransitPlanner.detect_corridor_width(data, center_c, fwd, _formation_movement_profile)
	if _combat_move_plan.macro_cursor + 2 < _combat_move_plan.macro_path.size():
		var ahead_c: Vector2i = _combat_move_plan.macro_path[_combat_move_plan.macro_cursor + 2]
		var ahead_w := FormationTransitPlanner.detect_corridor_width(data, ahead_c, fwd, _formation_movement_profile)
		detected_w = mini(detected_w, ahead_w)
	FormationTransitPlanner.update_width_hysteresis(_combat_move_plan, detected_w)

	var active_mids := _get_active_member_ids()
	_profile_combat_stage("move_prepare_ingress_width", ingress_width_started)
	var transit_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	FormationTransitPlanner.calculate_transit_slots(_combat_move_plan, data, _formation_movement_profile, active_mids, occ)
	_profile_combat_stage("move_transit_slots", transit_started)
	var phase_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	FormationDestinationPlanner.update_movement_phase(_combat_move_plan, _combat_deployment_plan, occ, data, delta, deployment_registry, _current_movement_blocked_destinations(), r3_prepare_enabled)
	_profile_combat_stage("move_phase", phase_started)

	# These targets are pure until recovery below can change assignments/path.
	# Propose creates its own lookup after all formations have prepared.
	var target_context_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var target_context := _movement_target_context()
	_profile_combat_stage("move_prepare_target_context", target_context_started)
	var target_apply_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var prepared_targets: Dictionary = target_context.get("targets", {}) if r3_prepare_enabled else {}
	for idx in range(combat_units.size()):
		if not is_member(idx) or not combat_can_act(idx):
			continue
		var mid := combat_identity(idx)
		var target: Dictionary = {}
		if r3_prepare_enabled:
			var member_targets: Dictionary = prepared_targets.get(mid, {})
			if member_targets.has(cells[idx]):
				target = member_targets[cells[idx]]
		if target.is_empty():
			target = FormationDestinationPlanner.resolve_member_target(_combat_move_plan, _combat_deployment_plan, mid, cells[idx], target_context)
		var target_slot: Vector2i = target.get("target", cells[idx])
		if combat_slots[idx] != target_slot and moving_to[idx] == INVALID_CELL:
			if not _retain_member_route_to_target(mid, idx, target_slot):
				_combat_move_plan.invalidate_member_route(mid)
		combat_slots[idx] = target_slot
	_profile_combat_stage("move_prepare_target_apply", target_apply_started)

	if r3_prepare_enabled:
		_refresh_member_route_caches(route_budget, target_context, active_mids)
	else:
		_refresh_member_route_caches(route_budget, target_context)

	var progress_recovery_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var cur_med_s: float = float(_combat_move_plan.get_median_path_s())
	var field_progress := _transit_field_made_physical_progress(active_mids, occ, target_context)
	var had_prog := FormationRecoveryController.check_meaningful_progress(
		_combat_move_plan,
		cur_med_s,
		_combat_deployment_plan.settled_platform_member_ids.size(),
		_combat_deployment_plan.settled_queue_member_ids.size(),
		_combat_deployment_plan.promotion_count
	)
	if field_progress:
		had_prog = true
		_combat_move_plan.active_stall_total_sec = 0.0
		_combat_move_plan.stage_elapsed_sec = 0.0
		_combat_move_plan.recovery_stage = 0
	if not had_prog:
		if _is_stall_clock_eligible():
			FormationRecoveryController.update_stall_clock(_combat_move_plan, delta)
			var previous_path_epoch: int = _combat_move_plan.path_epoch
			var fail_code := FormationRecoveryController.process_recovery(
				_combat_move_plan,
				cur_medoid,
				data,
				_formation_movement_profile,
				Time.get_ticks_msec() / 1000.0
			)
			if _combat_move_plan != null and _combat_move_plan.path_epoch != previous_path_epoch:
				if not _refresh_recovery_path_coordinates(delta):
					_profile_combat_stage("move_prepare_progress_recovery", progress_recovery_started)
					return
			if fail_code == CombatMovementTypes.RuntimeMoveFailureCode.BLOCKED:
				cancel_combat_deployment_for_forced_order()
				combat_order = CombatOrder.HOLD
				_clear_member_attack_targets()
				command_status = "未找到合法通路；就地自衛，等待新令"
			elif fail_code == CombatMovementTypes.RuntimeMoveFailureCode.CONGESTED:
				cancel_combat_deployment_for_forced_order()
				combat_order = CombatOrder.HOLD
				_clear_member_attack_targets()
				command_status = "通道持續擁塞；就地防禦"
	_profile_combat_stage("move_prepare_progress_recovery", progress_recovery_started)

func combat_head_on_single_member_state() -> Dictionary:
	if _combat_move_plan != null and _combat_move_plan.structure_blocked:
		return {}
	if not combat_enabled or combat_order != CombatOrder.MOVE or _combat_move_plan == null \
		or _combat_deployment_plan == null or _order_delay > 0.0 or _move_engaging():
		return {}
	var members := _get_active_member_ids()
	if members.size() != 1:
		return {}
	var mid: int = members[0]
	var index := index_for_identity(mid)
	if index < 0 or is_controlled_person(index) or not combat_can_act(index) \
		or moving_to[index] != INVALID_CELL or _combat_action_blocks_step(index):
		return {}
	var final_slot: Vector2i = _combat_deployment_plan.get_slot_for_member(mid)
	if final_slot == INVALID_CELL or final_slot == cells[index]:
		return {}
	return {"member_id": mid, "cell": cells[index], "final": final_slot, "terrain": data, "team_id": team_id}

func propose_combat_side_pocket_yield(reservation_grid: Object, toward_other: Vector2i, deployment_registry: Object) -> bool:
	var state := combat_head_on_single_member_state()
	if state.is_empty() or reservation_grid.member_proposal_map.has(state.member_id):
		return false
	var index := index_for_identity(int(state.member_id))
	var pocket := _find_yield_cell(index, toward_other, reservation_grid, deployment_registry)
	if pocket == INVALID_CELL:
		return false
	var fid := try_get_formation_id()
	if fid <= 0: fid = team_id
	var mid: int = int(state.member_id)
	var wait_age: int = maxi(int(_combat_move_plan.member_defer_count.get(mid, 0)), int(_combat_move_plan.member_reservation_wait_age.get(mid, 0)))
	var pid: int = reservation_grid.propose_move(fid, mid, _combat_move_plan.order_serial, cells[index], pocket,
		1, wait_age, 0, int(_combat_move_plan.member_sequence_rank.get(mid, 100)), formation_persistent_serial)
	if pid < 0:
		return false
	_combat_move_plan.invalidate_member_route(mid)
	_combat_move_plan.member_pending_proposal_id[mid] = pid
	_combat_move_plan.member_pending_from_cell[mid] = cells[index]
	_combat_move_plan.member_pending_to_cell[mid] = pocket
	proposal_count += 1
	return true

func _r3_fused_move_proposals(reservation_grid: Object) -> Dictionary:
	if not native_move_intent_enabled or data == null or data.get_script() != TerrainData \
		or _combat_move_plan == null or _combat_move_plan.get_script() != CombatMovePlan \
		or _combat_deployment_plan == null or _combat_deployment_plan.get_script() != CombatDeploymentPlan \
		or _formation_movement_profile == null or _formation_movement_profile.get_script() != FormationMovementProfile \
		or _formation_movement_profile.max_step_height < 0 \
		or _combat_move_plan.short_translation or _combat_move_plan.phase == CombatMovementTypes.CombatMovePhase.FAILED \
		or _combat_move_plan.terrain_revision != data.navigation_revision \
		or reservation_grid == null or reservation_grid.get_script() != SiteMovementReservationGrid or _coordinator == null:
		return {}
	var reader := _native_movement_reader()
	if reader == null or not reader.has_method("movement_propose"):
		return {}
	if controlled_person_query.is_valid():
		var controller: Object = controlled_person_query.get_object()
		if not controller is TerrainLab or controller.get_script() != TerrainLab \
			or controlled_person_query.get_method() != &"controlled_person_id" or controlled_person_query.get_bound_arguments_count() != 0:
			return {}
	var external_maps := _native_movement_external_maps()
	if external_maps.is_empty():
		return {}
	var registry: Object = _coordinator.deployment_registry
	if registry != null and registry.get_script() != SiteDeploymentReservationRegistry:
		return {}
	var active_mids := _get_active_member_ids()
	active_mids.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = int(_combat_move_plan.member_sequence_rank.get(a, 9999))
		var rb: int = int(_combat_move_plan.member_sequence_rank.get(b, 9999))
		return ra < rb
	)
	var field := FormationTransitPlanner.get_transit_distance_field(_combat_move_plan, data, _formation_movement_profile)
	var controlled := int(controlled_person_query.call()) if controlled_person_query.is_valid() else -1
	var packet: Dictionary = reader.movement_propose([
		combat_units, cells, moving_to, combat_slots, active_mids, _combat_move_plan, _combat_deployment_plan, field,
		_cell_owners, _reserved_cells, reservation_grid.blocked_destinations, reservation_grid.initial_occupancy,
		reservation_grid.member_proposal_map, external_maps, registry.slot_owners if registry != null else {},
		[get_formation_id(), controlled, exchange_enabled], _native_movement_terrain(_formation_movement_profile)
	])
	if not packet.has("rows") or not packet.get("rows") is Array or not packet.get("field_count") is int:
		return {}
	var rows: Array = packet.rows
	if rows.size() % 4 != 0 or rows.size() > active_mids.size() * 4 \
		or int(packet.field_count) < 0 or int(packet.field_count) > active_mids.size():
		return {}
	var active_cursor := 0
	for offset in range(0, rows.size(), 4):
		if not rows[offset] is int or not rows[offset + 1] is int or not rows[offset + 2] is bool \
			or not rows[offset + 3] is Vector2i or int(rows[offset + 1]) < 0 or int(rows[offset + 1]) >= combat_units.size():
			return {}
		while active_cursor < active_mids.size() and active_mids[active_cursor] != int(rows[offset]):
			active_cursor += 1
		if active_cursor == active_mids.size():
			return {}
		active_cursor += 1
	native_move_intent_hits += int(packet.field_count)
	return packet

func propose_combat_moves(reservation_grid: Object) -> void:
	if _fire_nav_context_current():
		_propose_fire_navigation(reservation_grid)
		return
	_propose_suppress_approach(reservation_grid)
	if _combat_move_plan != null and _combat_move_plan.structure_blocked:
		return
	if combat_enabled and combat_order == CombatOrder.RETREAT and not _retreat_pair_pending.is_empty():
		var pair := _retreat_pair_pending
		_retreat_pair_pending = {}
		var front := int(pair.get("front", -1))
		var rear := int(pair.get("rear", -1))
		if _order_delay > 0.0 or int(pair.get("serial", -1)) != get_order_serial() \
			or not _retreat_pair_member_ready(front) or not _retreat_pair_member_ready(rear):
			return
		var source: Vector2i = pair["from"]
		var other: Vector2i = pair["to"]
		var first_id := combat_identity(front)
		var second_id := combat_identity(rear)
		if cells[front] != source or cells[rear] != other \
			or not data.can_step(source, other) or not data.can_step(other, source) \
			or _is_external_cell(source) or _is_external_cell(other) \
			or reservation_grid.initial_occupancy.get(source, -1) != first_id \
			or reservation_grid.initial_occupancy.get(other, -1) != second_id \
			or reservation_grid.blocked_destinations.has(source) or reservation_grid.blocked_destinations.has(other) \
			or reservation_grid.member_proposal_map.has(first_id) or reservation_grid.member_proposal_map.has(second_id):
			return
		var retreat_formation_id := get_formation_id()
		var first_pid: int = reservation_grid.propose_move(retreat_formation_id, first_id, get_order_serial(), source, other, 1)
		var second_pid: int = reservation_grid.propose_move(retreat_formation_id, second_id, get_order_serial(), other, source, 1)
		if first_pid >= 0 and second_pid >= 0:
			proposal_count += 2
		return
	if not combat_enabled or _combat_move_plan == null or combat_order != CombatOrder.MOVE or _order_delay > 0.0 or _move_engaging():
		return
	if r3_fused_propose_enabled:
		var fused_started := Time.get_ticks_usec() if combat_profile_enabled else 0
		var fused := _r3_fused_move_proposals(reservation_grid)
		_profile_combat_stage("move_propose_fused_compute", fused_started)
		if fused.has("rows"):
			r3_fused_propose_hits += 1
			var fused_submit_started := Time.get_ticks_usec() if combat_profile_enabled else 0
			var fused_fid := try_get_formation_id()
			if fused_fid <= 0: fused_fid = team_id
			var rows: Array = fused.rows
			for offset in range(0, rows.size(), 4):
				var mid: int = rows[offset]
				if reservation_grid.member_proposal_map.has(mid):
					continue # The coordinator may have offered a side-pocket step.
				var idx: int = rows[offset + 1]
				var field_handled: bool = rows[offset + 2]
				var next_step: Vector2i = rows[offset + 3]
				var capped_step := INVALID_CELL
				if next_step == INVALID_CELL and not field_handled:
					capped_step = _current_capped_transit_step(mid, idx, combat_slots[idx], reservation_grid)
					next_step = capped_step
				if next_step != INVALID_CELL and (reservation_grid.blocked_destinations.has(next_step) or _is_external_cell(next_step, mid)):
					var age := mini(3, int(_combat_move_plan.member_reservation_wait_age.get(mid, 0)) + 1)
					_combat_move_plan.member_reservation_wait_age[mid] = age
					if age >= 3:
						_combat_move_plan.invalidate_member_route(mid)
					continue
				if next_step == INVALID_CELL:
					continue
				proposal_count += 1
				var rank: int = _combat_move_plan.member_sequence_rank.get(mid, 100)
				var wait_age: int = maxi(int(_combat_move_plan.member_defer_count.get(mid, 0)), int(_combat_move_plan.member_reservation_wait_age.get(mid, 0)))
				var pid: int = reservation_grid.propose_move(fused_fid, mid, _combat_move_plan.order_serial,
					cells[idx], next_step, 0, wait_age, 0, rank, formation_persistent_serial)
				if pid >= 0:
					if field_handled and combat_profile_enabled:
						profiled_scheduler_metrics["field_proposed"] = int(profiled_scheduler_metrics.get("field_proposed", 0)) + 1
					_combat_move_plan.member_pending_proposal_id[mid] = pid
					_combat_move_plan.member_pending_from_cell[mid] = cells[idx]
					_combat_move_plan.member_pending_to_cell[mid] = next_step
					if capped_step != INVALID_CELL:
						var capped_stamp: Dictionary = _capped_transit_steps[mid]
						capped_stamp["proposal_id"] = pid
						if combat_profile_enabled:
							if bool(capped_stamp.get("deferred", false)):
								profiled_deferred_step_proposed += 1
							else:
								profiled_capped_step_proposed += 1
			_profile_combat_stage("move_propose_fused_submit", fused_submit_started)
			return
		r3_fused_propose_fallbacks += 1
	var target_context_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var target_context := _movement_target_context()
	_profile_combat_stage("move_propose_target_context", target_context_started)
	var active_mids := _get_active_member_ids()
	var rank_sort_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	active_mids.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = int(_combat_move_plan.member_sequence_rank.get(a, 9999))
		var rb: int = int(_combat_move_plan.member_sequence_rank.get(b, 9999))
		return ra < rb
	)
	_profile_combat_stage("move_rank_sort_propose", rank_sort_started)
	var fid := try_get_formation_id()
	if fid <= 0: fid = team_id
	var field_intents_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var field_intents := _batch_transit_field_intents(active_mids, reservation_grid, target_context)
	_profile_combat_stage("move_propose_field_intents", field_intents_started)
	var submit_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	for mid in active_mids:
		if reservation_grid.member_proposal_map.has(mid):
			continue # The coordinator already offered this person a legal side-pocket step.
		var idx := index_for_identity(mid)
		if idx < 0 or not is_member(idx) or not combat_can_act(idx) or is_controlled_person(idx):
			continue
		if moving_to[idx] != INVALID_CELL:
			continue
		if _combat_action_blocks_step(idx):
			continue
		var goal_cell: Vector2i = combat_slots[idx]
		var field_intent: Dictionary = field_intents[mid] if field_intents.has(mid) else _transit_field_intent(mid, idx, reservation_grid, target_context)
		var field_handled: bool = bool(field_intent.get("handled", false))
		var next_step: Vector2i = field_intent.get("step", INVALID_CELL)
		if field_handled and next_step == INVALID_CELL:
			continue
		if not field_handled:
			if cells[idx] == goal_cell:
				continue
			var diff := goal_cell - cells[idx]
			if _combat_move_plan.is_member_route_current(mid, goal_cell):
				var p: Array[Vector2i] = _combat_move_plan.member_paths[mid]
				if p.size() > 1 and p[0] == cells[idx] and p[-1] == goal_cell and FormationTransitPlanner._can_profile_step(data, cells[idx], p[1], _formation_movement_profile):
					next_step = p[1]
			if next_step == INVALID_CELL and (absi(diff.x) + absi(diff.y) == 1) and FormationTransitPlanner._can_profile_step(data, cells[idx], goal_cell, _formation_movement_profile):
				next_step = goal_cell
		var capped_step := INVALID_CELL
		if next_step == INVALID_CELL and not field_handled:
			capped_step = _current_capped_transit_step(mid, idx, goal_cell, reservation_grid)
			next_step = capped_step
		if next_step != INVALID_CELL and (reservation_grid.blocked_destinations.has(next_step) or _is_external_cell(next_step, mid)):
			var age := mini(3, int(_combat_move_plan.member_reservation_wait_age.get(mid, 0)) + 1)
			_combat_move_plan.member_reservation_wait_age[mid] = age
			if age >= 3:
				_combat_move_plan.invalidate_member_route(mid)
			continue
		if next_step != INVALID_CELL:
			proposal_count += 1
			var rank: int = _combat_move_plan.member_sequence_rank.get(mid, 100)
			var wait_age: int = maxi(int(_combat_move_plan.member_defer_count.get(mid, 0)), int(_combat_move_plan.member_reservation_wait_age.get(mid, 0)))
			var pid: int = reservation_grid.propose_move(
				fid,
				mid,
				_combat_move_plan.order_serial,
				cells[idx],
				next_step,
				0,
				wait_age,
				0,
				rank,
				formation_persistent_serial
			)
			if pid >= 0:
				if field_handled and combat_profile_enabled:
					profiled_scheduler_metrics["field_proposed"] = int(profiled_scheduler_metrics.get("field_proposed", 0)) + 1
				_combat_move_plan.member_pending_proposal_id[mid] = pid
				_combat_move_plan.member_pending_from_cell[mid] = cells[idx]
				_combat_move_plan.member_pending_to_cell[mid] = next_step
				if capped_step != INVALID_CELL:
					var capped_stamp: Dictionary = _capped_transit_steps[mid]
					capped_stamp["proposal_id"] = pid
					if combat_profile_enabled:
						if bool(capped_stamp.get("deferred", false)):
							profiled_deferred_step_proposed += 1
						else:
							profiled_capped_step_proposed += 1
	_profile_combat_stage("move_propose_submit", submit_started)

func finalize_combat_movement_tick(_delta: float, _reservation_grid: Object, _deployment_registry: Object) -> void:
	if _fire_nav_context_current():
		_finalize_fire_navigation(_reservation_grid)
		return
	if not combat_enabled or _combat_move_plan == null or combat_order != CombatOrder.MOVE:
		return
	for idx in range(combat_units.size()):
		if not is_member(idx):
			continue
		var mid := combat_identity(idx)
		if _combat_batch_members.has(mid):
			if combat_profile_enabled and _capped_transit_steps.has(mid) and _reservation_grid != null:
				var capped_stamp: Dictionary = _capped_transit_steps[mid]
				var capped_pid := int(capped_stamp.get("proposal_id", -1))
				var capped_proposal = _reservation_grid.proposal_lookup.get(capped_pid, null)
				if capped_proposal != null and capped_proposal.status == CombatMovementTypes.MoveProposalStatus.ACCEPTED \
					and moving_to[idx] == capped_stamp.get("to", INVALID_CELL):
					if bool(capped_stamp.get("deferred", false)):
						profiled_deferred_step_accepted += 1
					else:
						profiled_capped_step_accepted += 1
						if bool(capped_stamp.get("centerline", false)):
							profiled_capped_center_accepted += 1
						else:
							profiled_capped_side_accepted += 1
			continue
		var pid: int = int(_combat_move_plan.member_pending_proposal_id.get(mid, -1))
		var committed_to: Vector2i = _combat_move_plan.member_pending_to_cell.get(mid, INVALID_CELL)

		# A proposal starts a physical step. The route is consumed only by the
		# shared completion barrier after the original cell actually changes.
		var is_accepted := false
		var rejected_by_occupancy := false
		if pid >= 0 and _reservation_grid != null and "proposal_lookup" in _reservation_grid:
			var prop = _reservation_grid.proposal_lookup.get(pid, null)
			# Proposal ids restart every tick; an id kept from an earlier tick can
			# name another member's proposal. Only this member's own proposal counts.
			if prop != null and int(prop.member_id) == mid:
				is_accepted = prop.status == CombatMovementTypes.MoveProposalStatus.ACCEPTED
				rejected_by_occupancy = prop.status in [
					CombatMovementTypes.MoveProposalStatus.REJECTED_DEPENDENCY,
					CombatMovementTypes.MoveProposalStatus.REJECTED_CONFLICT,
					CombatMovementTypes.MoveProposalStatus.REJECTED_CYCLE
				]
		if is_accepted:
			_combat_move_plan.member_reservation_wait_age[mid] = 0
		elif rejected_by_occupancy:
			var age: int = mini(3, int(_combat_move_plan.member_reservation_wait_age.get(mid, 0)) + 1)
			_combat_move_plan.member_reservation_wait_age[mid] = age
			if age >= 3:
				_combat_move_plan.invalidate_member_route(mid)
		if not is_accepted or moving_to[idx] != committed_to:
			_combat_move_plan.member_pending_proposal_id.erase(mid)
			_combat_move_plan.member_pending_to_cell.erase(mid)
			_combat_move_plan.member_pending_from_cell.erase(mid)

		if _combat_move_plan.member_paths.has(mid):
			var p: Array[Vector2i] = _combat_move_plan.member_paths[mid]
			if is_accepted and committed_to != INVALID_CELL and moving_to[idx] != committed_to:
				push_error("MOVE_START_DESYNC: member " + str(mid) + " expected step " + str(committed_to))
				_combat_move_plan.member_paths.erase(mid)
				if _coordinator != null and _coordinator.has_method("request_occupancy_rebuild"):
					_coordinator.request_occupancy_rebuild()
			elif not is_accepted and pid >= 0:
				# Rejected or dependency blocked: do not pop, wait for next tick
				pass
			elif p.size() <= 1 or p[0] != cells[idx]:
				if cells[idx] == p[-1]:
					_combat_move_plan.member_paths.erase(mid)

	if _combat_move_plan.short_translation:
		return

	# Vanguard cohort quorum advance for macro_cursor
	var cursor_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var occ := get_active_members_occupancy()
	var path_size := _combat_move_plan.macro_path.size()
	if path_size > 0:
		var active_ranked_mids := _get_active_member_ids()
		# Both child timers below are included in move_cursor_finalize.
		var rank_sort_started := Time.get_ticks_usec() if combat_profile_enabled else 0
		active_ranked_mids.sort_custom(func(a: int, b: int) -> bool:
			var ra: int = int(_combat_move_plan.member_sequence_rank.get(a, 9999))
			var rb: int = int(_combat_move_plan.member_sequence_rank.get(b, 9999))
			return ra < rb
		)
		_profile_combat_stage("move_rank_sort_finalize", rank_sort_started)
		var lane_count := clampi(_combat_move_plan.current_width, 1, 4)
		var cohort_size := mini(active_ranked_mids.size(), maxi(lane_count * 3, 8))

		const MAX_ADVANCE := 3
		var current_k := _combat_move_plan.macro_cursor
		var max_search_k := mini(path_size - 1, current_k + MAX_ADVANCE)
		var flow_projected_k: Array[int] = []
		var cohort_projected_k: Array[int] = []
		var observation_key := [_combat_move_plan.path_epoch, _combat_move_plan.terrain_revision, data.navigation_revision]
		var same_projection: bool = _combat_move_plan.get_meta("_observed_projection_key", []) == observation_key
		_combat_move_plan.set_meta("_observed_projection_key", observation_key)

		# The same complete projection, reading original maps once per call.
		var projection_started := Time.get_ticks_usec() if combat_profile_enabled else 0
		var native_projection := _native_cursor_projection(active_ranked_mids, occ, same_projection)
		if not native_projection.is_empty():
			flow_projected_k.assign(native_projection.flow_projected_k)
		# Update dual local path projection for all active members (GD reference).
		for mid in active_ranked_mids if native_projection.is_empty() else []:
			if not occ.has(mid):
				continue
			var c: Vector2i = occ[mid]
			var checkpoint_cell: Vector2i = _combat_move_plan.member_checkpoint_cell.get(mid, INVALID_CELL)
			var observed_s := 0.0
			# The existing same-cell rule already keeps this result. Apply it
			# before rescanning the path; physical/version/phase changes still reproject.
			if _combat_move_plan.phase in [CombatMovementTypes.CombatMovePhase.TRANSIT, CombatMovementTypes.CombatMovePhase.INGRESS_STAGING] \
				and same_projection and c == checkpoint_cell and _combat_move_plan.member_observed_path_s.has(mid):
				observed_s = float(_combat_move_plan.member_observed_path_s[mid])
			else:
				var prev_k: int = int(_combat_move_plan.member_observed_path_k.get(mid, 0))

				# Priority 3: Local path window projection
				var window_min := maxi(0, mini(prev_k - 8, current_k - 4))
				var window_max := mini(path_size - 1, maxi(max_search_k, prev_k + 4))
				var best_k := prev_k
				var best_dist := 999999
				for k in range(window_min, window_max + 1):
					var pt := _combat_move_plan.macro_path[k]
					var dist: int = absi(pt.x - c.x) + absi(pt.y - c.y)
					if dist < best_dist and dist <= 3:
						best_dist = dist
						best_k = k
				if best_dist > 3:
					# Broader scan if not found in immediate window
					for k in range(0, mini(path_size - 1, max_search_k + 4) + 1):
						var pt := _combat_move_plan.macro_path[k]
						var dist: int = absi(pt.x - c.x) + absi(pt.y - c.y)
						if dist < best_dist and dist <= 3:
							best_dist = dist
							best_k = k
				if best_dist > 3:
					best_k = mini(prev_k, current_k)
				# Count only completed physical steps close to the verified centerline.
				# A changed soft assignment or projection window cannot advance this
				# high-water mark while the member remains on the same cell.
				var checkpoint_path_cell: Vector2i = _combat_move_plan.macro_path[best_k]
				var checkpoint_near_path: bool = best_dist == 0 or (best_dist == 1 and data.can_step_static(c, checkpoint_path_cell, _formation_movement_profile))
				if checkpoint_cell == INVALID_CELL:
					_combat_move_plan.member_checkpoint_cell[mid] = c
					_combat_move_plan.member_checkpoint_path_k[mid] = best_k if checkpoint_near_path else 0
					_combat_move_plan.member_checkpoint_best_k[mid] = int(_combat_move_plan.member_checkpoint_path_k[mid])
				elif c != checkpoint_cell:
					_combat_move_plan.member_checkpoint_cell[mid] = c
					if checkpoint_near_path and data.can_step_static(checkpoint_cell, c, _formation_movement_profile):
						var prior_checkpoint_k: int = int(_combat_move_plan.member_checkpoint_path_k.get(mid, 0))
						var next_checkpoint_k: int = mini(best_k, prior_checkpoint_k + 1)
						_combat_move_plan.member_checkpoint_path_k[mid] = next_checkpoint_k
						_combat_move_plan.member_checkpoint_best_k[mid] = maxi(int(_combat_move_plan.member_checkpoint_best_k.get(mid, 0)), next_checkpoint_k)

				observed_s = float(best_k)

				# Track-aware projection: priority rules per user specification
				var is_staging: bool = _combat_move_plan.pre_route_staging_slots.has(mid)
				var assigned_slot: Vector2i = _combat_move_plan.member_transit_slots.get(mid, INVALID_CELL)
				var assigned_s: float = float(_combat_move_plan.member_path_s.get(mid, -1.0))
				if not is_staging and assigned_slot != INVALID_CELL and assigned_s >= 0.0:
					# Case 1: Member currently at assigned slot
					if c == assigned_slot:
						observed_s = maxf(observed_s, assigned_s)
					# Case 2: Member has valid cached path ending at assigned slot
					elif _combat_move_plan.member_paths.has(mid):
						var p: Array = _combat_move_plan.member_paths[mid]
						if p.size() >= 1 and Vector2i(p[0]) == c and Vector2i(p[p.size() - 1]) == assigned_slot:
							var remaining_steps := p.size() - 1
							var slot_lower_bound_s := assigned_s - float(remaining_steps)
							observed_s = maxf(observed_s, slot_lower_bound_s)
					# Case 3: Fall back to local path window projection (best_k), no Manhattan across terrain

			observed_s = clampf(observed_s, 0.0, float(path_size - 1))
			var obs_k := floori(observed_s)
			_combat_move_plan.member_observed_path_s[mid] = observed_s
			_combat_move_plan.member_best_path_s[mid] = maxf(float(_combat_move_plan.member_best_path_s.get(mid, observed_s)), observed_s)
			_combat_move_plan.member_observed_path_k[mid] = obs_k
			_combat_move_plan.member_best_path_k[mid] = maxi(int(_combat_move_plan.member_best_path_k.get(mid, 0)), obs_k)
			_combat_move_plan.member_projected_path_k[mid] = obs_k
			flow_projected_k.append(obs_k)
		_profile_combat_stage("move_cursor_projection", projection_started)

		var sorted_k := flow_projected_k.duplicate()
		sorted_k.sort()
		sorted_k.reverse()
		for i in range(mini(cohort_size, sorted_k.size())):
			cohort_projected_k.append(sorted_k[i])
		var candidate_cursor := current_k
		var fwd := Vector2i(1, 0)
		if path_size > 1:
			var c_idx: int = clampi(current_k, 0, path_size - 2)
			fwd = _combat_move_plan.macro_path[c_idx + 1] - _combat_move_plan.macro_path[c_idx]
		for target_k in range(mini(path_size - 1, current_k + MAX_ADVANCE), current_k, -1):
			if cohort_size == 0:
				break
			var target_cell: Vector2i = _combat_move_plan.macro_path[target_k]
			var target_w := FormationTransitPlanner.detect_corridor_width(data, target_cell, fwd, _formation_movement_profile)
			var target_quorum: int
			if cohort_size <= 1:
				target_quorum = cohort_size
			else:
				target_quorum = clampi(maxi(2, mini(lane_count, target_w)), 2, cohort_size)
			var units_at_or_past := 0
			for val in cohort_projected_k:
				if val >= target_k:
					units_at_or_past += 1
			if units_at_or_past >= target_quorum or _can_release_saturated_front(current_k, target_k, target_quorum, units_at_or_past, cohort_projected_k, target_w):
				candidate_cursor = target_k
				break

		# Formation stretch guard: active only during TRANSIT and INGRESS_STAGING
		if _combat_move_plan.phase in [CombatMovementTypes.CombatMovePhase.TRANSIT, CombatMovementTypes.CombatMovePhase.INGRESS_STAGING]:
			if candidate_cursor > current_k and not flow_projected_k.is_empty():
				flow_projected_k.sort()
				var p25_idx := floori(float(flow_projected_k.size()) * 0.25)
				var percentile_25_k: int = flow_projected_k[p25_idx]
				var active_count: int = active_ranked_mids.size()
				# The tail may still be crossing a narrow pass after the head reaches
				# open ground. Use the bottleneck spanned by this convoy, rather than
				# the current head width, to bound its legitimate longitudinal length.
				var convoy_width := lane_count
				for k in range(maxi(0, percentile_25_k), candidate_cursor + 1):
					var path_cell: Vector2i = _combat_move_plan.macro_path[k]
					var path_forward := Vector2i.RIGHT
					if k + 1 < path_size:
						path_forward = _combat_move_plan.macro_path[k + 1] - path_cell
					elif k > 0:
						path_forward = path_cell - _combat_move_plan.macro_path[k - 1]
					convoy_width = mini(convoy_width, FormationTransitPlanner.detect_corridor_width(data, path_cell, path_forward, _formation_movement_profile))
					if convoy_width == 1:
						break
				var expected_head_to_p25_gap: int = int(ceil(
					(float(active_count) * 0.75 / float(maxi(convoy_width, 1))) * FormationTransitPlanner.MEMBER_SPACING
				))
				var actual_gap := candidate_cursor - percentile_25_k
				var excess_stretch := actual_gap - expected_head_to_p25_gap
				if excess_stretch > FORMATION_STRETCH_SLACK:
					candidate_cursor = current_k + 1 if _can_release_elastic_front(current_k, percentile_25_k, active_count, convoy_width, cohort_projected_k) else current_k

		_combat_move_plan.macro_cursor = maxi(current_k, candidate_cursor)
	_profile_combat_stage("move_cursor_finalize", cursor_started)

func _native_cursor_projection(active_mids: Array[int], occupancy: Dictionary, same_projection: bool) -> Dictionary:
	if not native_movement_projection_enabled or data == null or data.get_script() != TerrainData \
		or _combat_move_plan == null or _combat_move_plan.get_script() != CombatMovePlan \
		or _formation_movement_profile != null and (_formation_movement_profile.get_script() != FormationMovementProfile \
			or _formation_movement_profile.max_step_height < 0):
		return {}
	var reader := _native_movement_reader()
	if reader == null or not reader.has_method("movement_projection"):
		return {}
	# This original loop calls TerrainData.can_step_static, whose profile limit
	# is max_step_height; it does not test the planner's can_use_ramp flag.
	var level_only: bool = _formation_movement_profile != null and _formation_movement_profile.max_step_height < 1
	var terrain_input := [data.size, data.navigation_flags(), data.navigation_heights(), data.navigation_ramps(), data.static_blocked, level_only]
	var result: Dictionary = reader.movement_projection(_combat_move_plan, active_mids, occupancy, terrain_input, same_projection)
	const FIELDS := ["member_checkpoint_cell", "member_checkpoint_path_k", "member_checkpoint_best_k",
		"member_observed_path_s", "member_best_path_s", "member_observed_path_k", "member_best_path_k", "member_projected_path_k"]
	if not result.get("flow_projected_k") is Array:
		return {}
	for field: String in FIELDS:
		if not result.get(field) is Dictionary:
			return {}
	for field: String in FIELDS:
		var original: Dictionary = _combat_move_plan.get(field)
		original.assign(result[field])
	native_movement_projection_calls += 1
	return result

func _front_has_saturated_pair(current_k: int, cohort_projected_k: Array[int]) -> bool:
	if _combat_move_plan == null or _combat_move_plan.macro_path.is_empty():
		return false
	var lookahead := clampi(maxi(FormationTransitPlanner.MIN_TRANSIT_LOOKAHEAD_ROWS, _combat_move_plan.current_width), FormationTransitPlanner.MIN_TRANSIT_LOOKAHEAD_ROWS, FormationTransitPlanner.MAX_TRANSIT_LOOKAHEAD_ROWS)
	var saturated_k := mini(_combat_move_plan.macro_path.size() - 1, current_k + lookahead)
	var saturated_count := 0
	for observed_k in cohort_projected_k:
		if observed_k >= saturated_k:
			saturated_count += 1
	return saturated_count >= 2

func _front_has_adjacent_physical_pair(current_k: int) -> bool:
	if _combat_move_plan == null or data == null or _combat_move_plan.macro_path.is_empty():
		return false
	var lookahead := clampi(maxi(FormationTransitPlanner.MIN_TRANSIT_LOOKAHEAD_ROWS, _combat_move_plan.current_width), FormationTransitPlanner.MIN_TRANSIT_LOOKAHEAD_ROWS, FormationTransitPlanner.MAX_TRANSIT_LOOKAHEAD_ROWS)
	var saturated_k := mini(_combat_move_plan.macro_path.size() - 1, current_k + lookahead)
	if saturated_k <= 0:
		return false
	var lane_count := clampi(_combat_move_plan.current_width, 1, FormationTransitPlanner.MAX_TRANSIT_WIDTH)
	var front_row: Array[Vector2i] = FormationTransitPlanner._get_row_cross_section(_combat_move_plan, saturated_k, data, _formation_movement_profile, lane_count)
	var following_row: Array[Vector2i] = FormationTransitPlanner._get_row_cross_section(_combat_move_plan, saturated_k - 1, data, _formation_movement_profile, lane_count)
	if front_row.is_empty() or following_row.is_empty():
		return false
	var occupancy := get_active_members_occupancy()
	var front_found := false
	var following_found := false
	for mid in _get_active_member_ids():
		if not occupancy.has(mid):
			continue
		var cell: Vector2i = occupancy[mid]
		var observed_k: int = int(_combat_move_plan.member_observed_path_k.get(mid, -1))
		if front_row.has(cell) and observed_k >= saturated_k:
			front_found = true
		elif not front_row.has(cell) and following_row.has(cell) and observed_k >= saturated_k - 1:
			following_found = true
		if front_found and following_found:
			return true
	return false

func _front_has_one_step_physical_pair(current_k: int) -> bool:
	if _combat_move_plan == null or data == null or _combat_move_plan.phase != CombatMovementTypes.CombatMovePhase.TRANSIT \
		or _combat_move_plan.current_width != 1:
		return false
	var path: Array[Vector2i] = _combat_move_plan.macro_path
	if current_k < 0 or current_k + 2 >= path.size():
		return false
	var rear_cell: Vector2i = path[current_k]
	var front_cell: Vector2i = path[current_k + 1]
	var empty_cell: Vector2i = path[current_k + 2]
	if path.count(rear_cell) != 1 or path.count(front_cell) != 1 or path.count(empty_cell) != 1 \
		or not FormationTransitPlanner._can_profile_step(data, rear_cell, front_cell, _formation_movement_profile) \
		or not FormationTransitPlanner._can_profile_step(data, front_cell, empty_cell, _formation_movement_profile) \
		or _cell_owners.has(empty_cell) or _reserved_cells.has(empty_cell):
		return false
	var grid: Object = _coordinator.movement_reservation_grid if _coordinator != null else null
	if grid != null and (grid.initial_occupancy.has(empty_cell) or grid.blocked_destinations.has(empty_cell)):
		return false
	var rear_index := int(_cell_owners.get(rear_cell, -1))
	var front_index := int(_cell_owners.get(front_cell, -1))
	if rear_index < 0 or front_index < 0 or rear_index == front_index:
		return false
	for index in [rear_index, front_index]:
		if index >= combat_units.size() or not is_member(index) or not combat_can_act(index) \
			or is_controlled_person(index) or moving_to[index] != INVALID_CELL:
			return false
	var rear_mid := combat_identity(rear_index)
	var front_mid := combat_identity(front_index)
	var front_target := FormationDestinationPlanner.resolve_member_target(_combat_move_plan, _combat_deployment_plan, front_mid, front_cell)
	var fid := try_get_formation_id()
	if fid <= 0:
		fid = team_id
	if cells[rear_index] != rear_cell or cells[front_index] != front_cell \
		or int(_combat_move_plan.member_observed_path_k.get(rear_mid, -1)) < current_k \
		or int(_combat_move_plan.member_observed_path_k.get(front_mid, -1)) < current_k + 1 \
		or front_target.get("target", INVALID_CELL) != front_cell or front_target.get("wait_reason", "") != "FLOW_WAIT" \
		or _is_external_cell(empty_cell, front_mid) \
		or (_coordinator != null and _coordinator.deployment_registry != null \
			and _coordinator.deployment_registry.is_slot_reserved(empty_cell, fid)):
		return false
	return true

func _can_release_elastic_front(current_k: int, percentile_25_k: int, active_count: int, convoy_width: int, cohort_projected_k: Array[int]) -> bool:
	if _combat_move_plan == null or data == null or current_k + 1 >= _combat_move_plan.macro_path.size():
		return false
	if not _front_has_saturated_pair(current_k, cohort_projected_k):
		if convoy_width != 1 or cohort_projected_k.is_empty():
			return false
		if not _front_has_adjacent_physical_pair(current_k) and not _front_has_one_step_physical_pair(current_k):
			# A one-cell row may have only one leader. Keep the original narrow-row
			# proof when no adjacent pair of authoritative physical cells exists.
			var lookahead := clampi(maxi(FormationTransitPlanner.MIN_TRANSIT_LOOKAHEAD_ROWS, _combat_move_plan.current_width), FormationTransitPlanner.MIN_TRANSIT_LOOKAHEAD_ROWS, FormationTransitPlanner.MAX_TRANSIT_LOOKAHEAD_ROWS)
			var saturated_k := mini(_combat_move_plan.macro_path.size() - 1, current_k + lookahead)
			var front_observed := -1
			for observed_k in cohort_projected_k:
				front_observed = maxi(front_observed, observed_k)
			if front_observed < saturated_k:
				return false
			var saturated_cell: Vector2i = _combat_move_plan.macro_path[saturated_k]
			var forward := Vector2i.RIGHT
			if saturated_k + 1 < _combat_move_plan.macro_path.size():
				forward = _combat_move_plan.macro_path[saturated_k + 1] - saturated_cell
			elif saturated_k > 0:
				forward = saturated_cell - _combat_move_plan.macro_path[saturated_k - 1]
			if FormationTransitPlanner.detect_corridor_width(data, saturated_cell, forward, _formation_movement_profile) != 1:
				return false
	# The original percentile estimate is tight at bends; a saturated front may
	# use at most the physical length of the whole roster through the bottleneck.
	var physical_limit := ceili(float(active_count) / float(maxi(convoy_width, 1)) * FormationTransitPlanner.MEMBER_SPACING) + FORMATION_STRETCH_SLACK
	if current_k + 1 - percentile_25_k > physical_limit:
		return false
	return FormationTransitPlanner._find_furthest_verified_head_s(current_k, current_k + 1, _combat_move_plan, data, _formation_movement_profile) >= float(current_k + 1)

func _can_release_saturated_front(current_k: int, target_k: int, quorum: int, units_at_or_past: int, cohort_projected_k: Array[int], target_width: int = 4) -> bool:
	# A wide row can wait forever for its fourth soldier while its first two
	# already occupy the furthest soft row. Release one verified step only.
	if _combat_move_plan == null or data == null or target_k != current_k + 1 or units_at_or_past != quorum - 1:
		return false
	var path_size := _combat_move_plan.macro_path.size()
	if target_k >= path_size:
		return false
	if quorum >= 3:
		if not _front_has_saturated_pair(current_k, cohort_projected_k):
			return false
	elif quorum == 2:
		if _front_has_one_step_physical_pair(current_k):
			return FormationTransitPlanner._find_furthest_verified_head_s(current_k, target_k, _combat_move_plan, data, _formation_movement_profile) >= float(target_k)
		if target_width != 1:
			return false
		var target_cell: Vector2i = _combat_move_plan.macro_path[target_k]
		var target_forward: Vector2i = _combat_move_plan.macro_path[target_k + 1] - target_cell if target_k + 1 < path_size else target_cell - _combat_move_plan.macro_path[current_k]
		if FormationTransitPlanner.detect_corridor_width(data, target_cell, target_forward, _formation_movement_profile) != 1:
			return false
		var lookahead := clampi(maxi(FormationTransitPlanner.MIN_TRANSIT_LOOKAHEAD_ROWS, _combat_move_plan.current_width), FormationTransitPlanner.MIN_TRANSIT_LOOKAHEAD_ROWS, FormationTransitPlanner.MAX_TRANSIT_LOOKAHEAD_ROWS)
		var saturated_k := mini(path_size - 1, current_k + lookahead)
		var saturated_cell: Vector2i = _combat_move_plan.macro_path[saturated_k]
		var saturated_forward: Vector2i = _combat_move_plan.macro_path[saturated_k + 1] - saturated_cell if saturated_k + 1 < path_size else saturated_cell - _combat_move_plan.macro_path[saturated_k - 1]
		if FormationTransitPlanner.detect_corridor_width(data, saturated_cell, saturated_forward, _formation_movement_profile) != 1:
			return false
		var physical_front := false
		var occupancy := get_active_members_occupancy()
		for mid in occupancy:
			if occupancy[mid] == saturated_cell and int(_combat_move_plan.member_projected_path_k.get(mid, -1)) >= saturated_k:
				physical_front = true
				break
		if not physical_front:
			if not _front_has_one_step_physical_pair(current_k):
				return false
	else:
		return false
	return FormationTransitPlanner._find_furthest_verified_head_s(current_k, target_k, _combat_move_plan, data, _formation_movement_profile) >= float(target_k)

func get_active_move_plan() -> CombatMovePlan:
	return _combat_move_plan

func has_pending_retreat_pair() -> bool:
	return combat_order == CombatOrder.RETREAT and not _retreat_pair_pending.is_empty()

func get_active_deployment_plan() -> CombatDeploymentPlan:
	return _combat_deployment_plan

func get_formation_movement_profile() -> FormationMovementProfile:
	return _formation_movement_profile

func can_begin_committed_move(member_id: int, from_cell: Vector2i, to_cell: Vector2i, participants: Dictionary) -> bool:
	if _is_fire_proposal(member_id, from_cell, to_cell): return _can_begin_fire_move(member_id, from_cell, to_cell, participants)
	if _is_suppress_proposal(member_id, from_cell, to_cell):
		return _can_begin_suppress_move(member_id, from_cell, to_cell)
	if not garrison_feature_id.is_empty(): return false
	var index := index_for_identity(member_id)
	var retreat_pair := false
	if combat_order == CombatOrder.RETREAT and _combat_move_plan == null and _coordinator != null:
		var grid: Object = _coordinator.movement_reservation_grid
		var proposal = grid.proposal_lookup.get(grid.member_proposal_map.get(member_id, -1))
		retreat_pair = proposal != null and proposal.formation_id == get_formation_id() \
			and proposal.order_serial == get_order_serial() and proposal.from_cell == from_cell \
			and proposal.to_cell == to_cell and grid.is_same_formation_pair_swap(proposal)
	if index < 0 or _ship_embarked(index) or not is_member(index) or is_controlled_person(index) or not combat_can_act(index) \
		or not ((_combat_move_plan != null and combat_order == CombatOrder.MOVE) or retreat_pair) or _move_engaging() or _combat_action_blocks_step(index) \
		or moving_to[index] != INVALID_CELL or _unit_rescues.has(index) or cells[index] != from_cell \
		or _cell_owners.get(from_cell, -1) != index or _reserved_cells.has(to_cell) \
		or not (data.can_step(from_cell, to_cell) if retreat_pair else FormationTransitPlanner._can_profile_step(data, from_cell, to_cell, _formation_movement_profile)) \
		or _is_external_cell(to_cell, member_id):
		return false
	var occupant := int(_cell_owners.get(to_cell, -1))
	if occupant >= 0 and not participants.has(combat_identity(occupant)):
		return false
	# Vehicle movement has a swept footprint and its own transaction owner.
	return vehicle_transport == null or not vehicle_transport.is_operator(member_id)

func can_begin_siege_member_move(member_id: int, from_cell: Vector2i, to_cell: Vector2i, participants: Dictionary) -> bool:
	var index := index_for_identity(member_id)
	if index < 0 or not garrison_feature_id.is_empty() or not is_member(index) or is_controlled_person(index) or not combat_can_act(index) or _ship_embarked(index) or not _siege_crew(index) or _combat_action_blocks_step(index) or _unit_rescues.has(index) or moving_to[index] != INVALID_CELL or cells[index] != from_cell or _cell_owners.get(from_cell, -1) != index or _reserved_cells.has(to_cell) or not data.can_step(from_cell, to_cell): return false
	var occupant := int(_cell_owners.get(to_cell, -1))
	return occupant < 0 or participants.has(combat_identity(occupant))

func begin_committed_move(member_id: int, from_cell: Vector2i, to_cell: Vector2i, duration: float = MOVE_DURATION) -> void:
	var index := index_for_identity(member_id)
	# Only an already-admitted original vehicle transaction supplies slow duration.
	assert(is_equal_approx(duration, MOVE_DURATION) or vehicle_transport != null and vehicle_transport.siege_member_duration_matches(member_id, duration))
	if combat_order == CombatOrder.RETREAT:
		var other_index: int = int(_cell_owners.get(to_cell, -1))
		if other_index >= 0:
			var other_id: int = combat_identity(other_index)
			_retreat_pairs_used["%d:%d" % [mini(member_id, other_id), maxi(member_id, other_id)]] = true
	var intent_order := FIRE_HAZARD_STEP if _is_fire_proposal(member_id, from_cell, to_cell) else (CombatOrder.HOLD if _is_suppress_proposal(member_id, from_cell, to_cell) else (CombatOrder.RETREAT if combat_order == CombatOrder.RETREAT else CombatOrder.MOVE))
	_combat_batch_members[member_id] = _capture_committed_intent(member_id, intent_order)
	_reserved_cells[to_cell] = index
	moving_to[index] = to_cell
	move_progress[index] = 0.0
	move_duration[index] = duration
	move_curve[index] = 0
	locomotion_mode[index] = Locomotion.WALK
	movement_state[index] = UnitState.MOVING
	facing[index] = to_cell - from_cell
	combat_hot_set(index, &"pose", "walk")
	combat_hot_set(index, &"age", 0.0)
	if exchange_enabled:
		combat_hot_set(index, &"attack", false)
		combat_hot_set(index, &"exchange_pose_duration", 0.0)
	_mark_visual_row(index)
	accepted_count += 1
	_audio_begin_step(index, from_cell, to_cell, false)

func _committed_move_terrain_legal(member_id: int, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if vehicle_transport != null and vehicle_transport.is_siege_committed_member(member_id):
		return vehicle_transport.siege_member_terrain_legal(member_id, from_cell, to_cell)
	if _committed_intent_order(member_id) in [CombatOrder.RETREAT, CombatOrder.HOLD]:
		return data.can_step(from_cell, to_cell)
	return FormationTransitPlanner._can_profile_step(data, from_cell, to_cell, _committed_intent(member_id).get("movement_profile", _formation_movement_profile))

func can_finish_committed_move(member_id: int) -> bool:
	var index := index_for_identity(member_id)
	if index < 0 or not _combat_batch_members.has(member_id) or moving_to[index] == INVALID_CELL:
		return false
	if move_progress[index] >= 1.0 and not _committed_move_terrain_legal(member_id, cells[index], moving_to[index]):
		_movement_contract_error("combat batch terrain changed", index, cells[index], moving_to[index])
		return false
	return _combat_batch_members.has(member_id) and moving_to[index] != INVALID_CELL \
		and move_progress[index] >= 1.0 and _cell_owners.get(cells[index], -1) == index \
		and _reserved_cells.get(moving_to[index], -1) == index \
		and (vehicle_transport.siege_member_destination_clear(member_id, moving_to[index]) if vehicle_transport != null and vehicle_transport.is_siege_committed_member(member_id) else not _is_external_cell(moving_to[index], member_id))

func committed_move_terrain_invalid(member_id: int) -> bool:
	var index := index_for_identity(member_id)
	return index >= 0 and _combat_batch_members.has(member_id) and moving_to[index] != INVALID_CELL \
		and not _committed_move_terrain_legal(member_id, cells[index], moving_to[index])

func cancel_committed_move_to_source(member_id: int) -> void:
	var intent := _committed_intent(member_id)
	var consume_main := committed_move_can_change_main_order(member_id)
	var index := index_for_identity(member_id)
	if index < 0:
		return
	_audio_step_sources.erase(index)
	var destination: Vector2i = moving_to[index]
	if _reserved_cells.get(destination, -1) == index:
		_reserved_cells.erase(destination)
	_combat_batch_members.erase(member_id)
	if vehicle_transport != null: vehicle_transport.cancel_step(self, index)
	moving_to[index] = INVALID_CELL
	swap_partner[index] = -1
	move_progress[index] = 0.0
	move_duration[index] = MOVE_DURATION
	move_curve[index] = 0
	locomotion_mode[index] = Locomotion.IDLE
	movement_state[index] = UnitState.IDLE
	if combat_enabled and str(combat_hot_get(index, &"pose")) in ["walk", "run"]:
		combat_hot_set(index, &"pose", "idle")
		combat_hot_set(index, &"age", 0.0)
	if combat_enabled and (float(combat_hot_get(index, &"hp")) <= 0.0 or float(combat_hot_get(index, &"ko")) > 0.0):
		_cell_owners.erase(cells[index])
	if consume_main and _combat_move_plan != null:
		_combat_move_plan.member_pending_proposal_id.erase(member_id)
		_combat_move_plan.member_pending_to_cell.erase(member_id)
		_combat_move_plan.member_pending_from_cell.erase(member_id)
		_combat_move_plan.invalidate_member_route(member_id)
	_mark_visual_row(index)
	_finish_special_committed_intent(member_id, intent, cells[index], cells[index])

func hold_after_invalid_committed_batch() -> void:
	if _preserve_structure_order:
		if _combat_move_plan != null:
			_combat_move_plan.terrain_revision = -1
		command_status = "結構毀損；原命令與目標保留，重新查找合法通路"
		return
	_release_combat_deployment_lease()
	_combat_absent_slots.clear()
	combat_order = CombatOrder.HOLD
	_clear_member_attack_targets()
	command_status = "移動中地形變更；已退回原格就地防禦，等待新令"
	_combat_move_plan = null
	_combat_deployment_plan = null
	for index in range(cells.size()):
		if is_member(index):
			combat_slots[index] = moving_to[index] if moving_to[index] != INVALID_CELL else cells[index]

func finish_committed_move(member_id: int) -> void:
	var intent := _committed_intent(member_id)
	var consume_main := committed_move_can_change_main_order(member_id)
	var index := index_for_identity(member_id)
	var old_cell := cells[index]
	var next := moving_to[index]
	cells[index] = next
	_cell_owners[next] = index
	_reserved_cells.erase(next)
	_combat_batch_members.erase(member_id)
	_finish_move_state(index, old_cell, next, consume_main)
	_finish_special_committed_intent(member_id, intent, old_cell, next)
	if consume_main and combat_order == CombatOrder.MOVE and _combat_move_plan != null:
		_move_landed_members[member_id] = true
	if consume_main and _combat_move_plan != null:
		_combat_move_plan.member_pending_proposal_id.erase(member_id)
		_combat_move_plan.member_pending_to_cell.erase(member_id)
		_combat_move_plan.member_pending_from_cell.erase(member_id)
	if consume_main and _combat_move_plan != null and _combat_move_plan.member_paths.has(member_id):
		var path: Array[Vector2i] = _combat_move_plan.member_paths[member_id]
		if path.size() > 1 and path[0] == old_cell and path[1] == next:
			path.remove_at(0)
		else:
			_combat_move_plan.member_paths.erase(member_id)
	if _coordinator != null and _coordinator.has_method("request_occupancy_rebuild"):
		_coordinator.request_occupancy_rebuild()


var shared_fatigue_enabled := true # Formal exchange policy; legacy geometry keeps individual fatigue.
var team_fatigue: Dictionary = {}
var _fatigue_roster_size := -1
var individual_fatigue_indices: Array[int] = []
var person_id_allocator: Callable # Site owner supplies new IDs; transfers never allocate.
var roster_transfer_hook: Callable # Canonical Site supply owner settles/moves history before row commit.
var sustain_routed_query: Callable
var equipment_initializer: Callable # Explicit deployment only, never a query refill.
var equipment_appearance_query: Callable # (actual person ID) -> current read-only recipe.
var equipment_appearance_batch_query: Callable # Borrow the original owner's immutable publications.
var cape_retirement: Callable # (original IDs) -> atomic real-holder retirement before demotion.
var cape_departure_guard: Callable # Pure preflight before the existing feeding/roster transaction.
var person_busy_query: Callable
var controlled_person_query: Callable
var escort_step_guard: Callable
var external_blocker: Callable
var contact_query: Callable
var enemy_query: Callable
var ranged_tactics_query: Callable # Fresh original enemy/friendly-cell projection per command review.
var ranged_ammo_mode := "NORMAL"
var ranged_target: Dictionary = {}
var ranged_order_serial := 0
var ranged_order_issuer_id := 0
var ranged_enabled := false
var ranged_fire_policy: Dictionary = {} # Original command progress; estimates remain derived.
var ranged_target_validate: Callable # Pure original Lab query: (owner, typed target, ammo mode) -> {ok, cell}.
var _ranged_last_release_ids: Dictionary = {} # One physical release watermark per original person; bounded by the roster.
var contact_sink: Callable
signal combat_event(duration: float)
signal died(person_identity: int)
var _combat_geometry := CombatGeometry.new()
var combat_proxy: RefCounted # Explicit test injection only; production keeps native geometry.
var _combat_pose_cache: Dictionary = {}
var _contact_batch_inputs: Array = [] # Borrowed Lab targets, only between advance and resolution.
var _contact_batch_pose_results: Array = [] # Same Lab target slots, independently enabled; never saved or kept after resolution.
var lazy_weapon_queries_enabled := true # Same-owner exact A/B switch, not a sampling-rate change.
var combat_geometry_profile := {"ordinary_bounds_calls": 0, "ordinary_bounds_usec": 0,
	"pose_result_hits": 0, "pose_result_misses": 0,
	"sample_current_weapon_usec": 0, "sample_protection_usec": 0,
	"live_cache_misses": 0, "live_sync_usec": 0, "live_body_usec": 0, "live_weapon_usec": 0,
	"live_shield_usec": 0, "live_parry_usec": 0, "live_weapon_fills": 0,
	"live_weapon_omissions": 0, "live_partial_fills": 0}
enum CombatOrder { HOLD, ATTACK, MOVE, RETREAT, PURSUE, RETURN }
var combat_order: int = CombatOrder.HOLD
var tactical_ai_enabled := false
var tactical_ai_recovering := false
var tactical_ai_order_cooldown := 0.0
var tactical_ai_chase_cooldown := 0.0
var tactical_ai_status := "停用"
var tactical_ai_reason := ""
var tactical_ai_target_id := -1
var tactical_ai_decisions := 0
var tactical_ai_orders := 0
var _issuing_tactical_ai_order := false
var formal_commander := -1
# v2 plan R1b (user decision 2026-10-07, amended same day "文官也可以帶兵"):
# acting, succession and every command ability sum count only the formal captain
# plus 在任幹部 with officer qualification who hold any non-head seat, 文官 or
# 武官. Identity cache, rebuilt when dirty.
var _serving_ids: Dictionary = {}
var _serving_dirty := true
var _head_established := false # False only before a new team's first captain is chosen.
# Cadre list is derived from posts (R1b): non-head post holders are cadre; 武官
# holders also form the succession order. Seats seen last projection (transient).
var _last_holders: Dictionary = {}
# R2 §8.1: today's battle-casualty cohort {day, base: [person ids alive at day
# start or at formation]}; saved with the team, never a second roster.
var social_cohort: Dictionary = {}
var acting_commander := -1
var current_commander := -1
var officer_order: Array[int] = []
var officer_service: Array[int] = [] # Current service periods, chronological; same-event ties use person ID.
var offices: Dictionary = {} # SiteOffices team record; holders are person IDs, head derives from formal_commander.
var duty_traces: Array[Dictionary] = [] # Recent duty-AI decisions only; bounded, never saved.
var command_abilities: Dictionary = {}
var needs_attack_order := false
var command_notice := ""
var command_reference := Vector2.ZERO
var command_reference_valid := false
var command_radius := 8.0
var command_rng := RandomNumberGenerator.new()
var combat_slots: Array[Vector2i] = []
var combat_goal := INVALID_CELL
var pursuit_origin := Vector2.ZERO
var pursuit_left := 0.0
var pursuit_target := -1
var target_query: Callable
var combat_target_query: Callable
var exchange_people_query: Callable # Borrow original Lab people only during a command review.
var encirclement_steps := 0 # Diagnostics only; no second movement state or saved order.
var encirclement_reviews := 0
var geometry_prefilter_enabled := true
var geometry_prefilter_reviews := 0
var geometry_prefilter_skipped := 0
const ENCIRCLEMENT_DISTANCE := 8
const ENCIRCLEMENT_ROUTE_DISTANCE := 32
const ENCIRCLEMENT_CELLS := 1024
const ENCIRCLEMENT_STEPS := 32
var _command_dirty := false
var _command_elapsed := 0.0
var _order_delay := 0.0
var periodic_review_stagger_enabled := true
var _vacancy_assignments: Dictionary = {}
var _unit_rescues: Dictionary = {}
var _external_rescuers: Dictionary = {} # References only; actor snapshot owns its help timer.
const PLAYER_MEMBER := 1000000000 # Role reference only; never another soldier row.
var player_member: TerrainTestCharacter
var player_present := false
var player_goal := INVALID_CELL
var player_supply_hook: Callable # Existing original player's feeding history follows membership.
var membership_change_hook: Callable # (team, original person ID, joining); atomic feeding-owner commit.

func is_member(index: int) -> bool:
	if index == PLAYER_MEMBER:
		return is_instance_valid(player_member)
	return index >= 0 and index < combat_units.size() and bool(combat_hot_get(index, &"member", true))

func moving_member_count() -> int:
	var count := 0
	for index in range(combat_units.size()):
		count += int(is_member(index) and moving_to[index] != INVALID_CELL)
	return count

func sync_shared_fatigue(force: bool = false) -> void:
	if not force and _fatigue_roster_size == combat_units.size(): return
	_fatigue_roster_size = combat_units.size()
	var members: Array = []
	var active := bool(team_fatigue.get("active", false))
	individual_fatigue_indices.clear()
	for index in range(combat_units.size()):
		var row: Dictionary = combat_units[index]
		if shared_fatigue_enabled and exchange_enabled and is_member(index) and not member_gone(index):
			members.append(row)
		elif float(combat_hot_get(index, &"hp")) > 0.0:
			individual_fatigue_indices.append(index)
	if shared_fatigue_enabled and exchange_enabled and is_instance_valid(player_member) and player_member.hp > 0.0:
		members.append(player_member)
	# Taking control is not joining/leaving. Preserve the exact authority object
	# and value even when the control-switch caller requests a forced refresh.
	var same_members := not team_fatigue.is_empty() and int(team_fatigue.get("count", 0)) == members.size()
	for body: Variant in members:
		same_members = same_members and is_same(PersonFatigue.pool(body), team_fatigue)
	if same_members: return
	var value := 0.0
	var rested := PersonFatigue.REST_DELAY
	for body: Variant in members:
		value += PersonFatigue.read(body)
		rested = minf(rested, PersonFatigue.read(body, "fatigue_rest"))
		active = active or bool(PersonFatigue.pool(body).get("active", false))
	for row: Dictionary in combat_units: PersonFatigue.unbind(row)
	if is_instance_valid(player_member): PersonFatigue.unbind(player_member)
	team_fatigue = {}
	if not members.is_empty():
		team_fatigue = {"fatigue": value / members.size(), "fatigue_rest": rested, "count": members.size(), "active": active}
		for body: Variant in members: PersonFatigue.bind(body, team_fatigue)

func command_members() -> Array[int]:
	var members: Array[int] = []
	for index in range(combat_units.size()):
		if is_member(index):
			members.append(index)
	if is_instance_valid(player_member):
		members.append(PLAYER_MEMBER)
	return members

func member_gone(index: int) -> bool:
	if index == PLAYER_MEMBER:
		return not is_instance_valid(player_member) or player_member.hp <= 0.0
	return index < 0 or index >= combat_units.size() or float(combat_hot_get(index, &"hp")) <= 0.0 or bool(combat_hot_get(index, &"departed"))

static func troop_class(appearance: Dictionary) -> StringName:
	var parts: Variant = appearance.get("parts", _EMPTY_TROOP_DATA)
	if not parts is Dictionary: return &""
	return _troop_asset_class(StringName(str(parts.get("weapon", "none"))))

static func _troop_asset_class(weapon: StringName) -> StringName:
	var family := HumanCharacter3DEditor.WeaponMaterials.family(weapon)
	if family == &"none": return &""
	if family == &"bow_01": return &"bow"
	if family == &"crossbow_01": return &"crossbow"
	return TROOP_TYPE_ID

static func _combat_summary_classifier() -> Dictionary:
	if _summary_asset_classes.is_empty():
		var classes := {}
		for option: Dictionary in HumanCharacter3DEditor.WeaponMaterials.OPTIONS:
			var asset := str(option.id)
			classes[asset] = _troop_asset_class(StringName(asset))
		classes.make_read_only()
		_summary_asset_classes = classes
	return _summary_asset_classes

static func _troop_row_class(row: Dictionary, state: Dictionary) -> StringName:
	# Real equipment is authoritative; saved appearance is the original template.
	# An empty hand after loss/removal is neutral, not a second infantry class.
	if row.get("item_state") is Dictionary and row.item_state.has("equipped"):
		var held: Dictionary = row.item_state
		var equipped: Variant = held.get("equipped", _EMPTY_TROOP_DATA)
		var records: Variant = state.get("item_records", _EMPTY_TROOP_DATA)
		var definitions: Variant = state.get("item_definitions", _EMPTY_TROOP_DATA)
		if equipped is Dictionary and records is Dictionary and definitions is Dictionary:
			var record: Variant = records.get(str(equipped.get("weapon", "")), _EMPTY_TROOP_DATA)
			if record is Dictionary:
				var definition: Variant = definitions.get(str(record.get("definition", "")), _EMPTY_TROOP_DATA)
				if definition is Dictionary:
					return _troop_asset_class(StringName(str(definition.get("asset", "none"))))
		return &""
	var appearance: Variant = row.get("appearance", {"parts": {"weapon": "longsword_01"}})
	return troop_class(appearance) if appearance is Dictionary else &""

static func single_troop_class(rows: Array, map: TerrainData, exempt_ids: Array, actor: Dictionary = {}, proposed: Dictionary = {}, state: Dictionary = {}) -> StringName:
	var kind := &""
	var members := rows.duplicate()
	if not actor.is_empty(): members.append(actor)
	for row: Dictionary in members:
		if not bool(row.get("member", true)) or float(row.get("hp", 100.0)) <= 0.0 or bool(row.get("departed", false)) or exempt_ids.has(int(row.get("person_id", -1))):
			continue
		var identity := int(row.get("person_id", -1))
		var current := troop_class(proposed[identity]) if proposed.has(identity) else _troop_row_class(row, map.site if state.is_empty() else state)
		if current == &"": continue
		if kind != &"" and kind != current: return &"mixed"
		kind = current
	return kind

func _troop_exempt_ids() -> Array:
	# Captain plus every current cadre member, 文官 included (v2 plan §3.2).
	var identities: Array = [combat_identity(formal_commander)]
	for index: int in officer_service: identities.append(combat_identity(index))
	return identities

func _troop_actor(actor: TerrainTestCharacter) -> Dictionary:
	if not is_instance_valid(actor): return {}
	return {"person_id": actor.person_id, "hp": actor.hp, "appearance": actor._saved_appearance,
		"item_state": actor.item_state}

func single_troop_equipment_guard(index: int, appearance: Dictionary) -> Dictionary:
	if not garrison_feature_id.is_empty(): return SiteRuntime.ok()
	if not is_member(index): return SiteRuntime.ok()
	var proposed := {combat_identity(index): appearance}
	if single_troop_class(materialized_combat_rows(), data, _troop_exempt_ids(), _troop_actor(player_member), proposed) == &"mixed":
		return SiteRuntime.fail("MIXED_TROOP", "普通隊員須維持同一兵種（近戰／弓／弩）；隊長與現任幹部除外，未扣物")
	return SiteRuntime.ok()

func team_troop_equipment_guard(proposed: Dictionary) -> Dictionary:
	if not garrison_feature_id.is_empty(): return SiteRuntime.ok()
	if single_troop_class(materialized_combat_rows(), data, _troop_exempt_ids(), _troop_actor(player_member), proposed) == &"mixed":
		return SiteRuntime.fail("MIXED_TROOP", "整隊最終普通隊員須維持同一兵種（近戰／弓／弩）；隊長與現任幹部除外，未扣物")
	return SiteRuntime.ok()

## R6 S5 (plan 10.1 退隊): the team departure transaction. The officer seats the person holds are computed first (pure, site_team_departure);
## the roster leave (leave_row) runs next; the seats are written only after that succeeds. A refused departure changes neither the roster nor the seats.
func depart_member(person_id: int, authority: Dictionary = {}) -> Dictionary:
	var kind := str(authority.get("kind", ""))
	if kind != "npc_event" and kind != "controlled": return SiteRuntime.fail("NO_AUTHORITY", "離隊須為受控者明示或 NPC 離隊事件")
	var vacated: Dictionary = TeamDeparture.vacate_seats(team_offices(true), person_id)
	if not bool(vacated.get("ok", false)): return vacated
	var left: Dictionary = leave_row_by_event(person_id) if kind == "npc_event" else leave_row(person_id)
	if not bool(left.get("ok", false)): return left
	if bool(vacated.get("changed", false)): offices = vacated.offices
	left["seat_vacated"] = bool(vacated.get("seat_vacated", false))
	return left

## R6 S5D: a non-controlled member leaves through a declared NPC departure event. The same guards as leave_row apply, except the
## controlled-person authority check, which this path does not satisfy for the controlled person (it is refused).
func leave_row_by_event(person_id: int) -> Dictionary:
	return _change_row_membership(person_id, false, -1, true)

func leave_row(person_id: int) -> Dictionary:
	return _change_row_membership(person_id, false)

func join_row(person_id: int) -> Dictionary:
	return _change_row_membership(person_id, true)

## v2 plan 3.4 募兵, first source: a row that left this same team (member=false)
## is enlisted again by whoever exercises team.recruit now, with the person's
## consent: an NPC accepts when free and idle (the same guards as joining); the
## controlled person must confirm themselves through join_row. No row, body or
## item is created; other teams' rows, garrison soldiers and free Actors need
## their own transfer adapters and are not offered here.
func recruit_row(requester_id: int, person_id: int) -> Dictionary:
	var refused := duty_authority("team.recruit", requester_id)
	if not refused.is_empty(): return refused
	var index := index_for_identity(person_id)
	if index >= 0 and index != PLAYER_MEMBER and is_controlled_person(index):
		return SiteRuntime.fail("NEEDS_CONSENT", "此人目前由玩家控制：須由本人明示確認入隊")
	return _change_row_membership(person_id, true, requester_id)

## v2 plan 3.4 募兵, second source: a free original Actor (the lab's own
## character/worker, not in any team, same faction) joins through the original
## join_player path; recruiter authority and consent as above. No body is copied.
func recruit_actor(requester_id: int, actor: TerrainTestCharacter) -> Dictionary:
	var refused := duty_authority("team.recruit", requester_id)
	if not refused.is_empty(): return refused
	if not is_instance_valid(actor): return SiteRuntime.fail("NO_TARGET", "無合格原人物")
	if controlled_person_query.is_valid() and actor.person_id == int(controlled_person_query.call()):
		return SiteRuntime.fail("NEEDS_CONSENT", "此人目前由玩家控制：須由本人明示確認入隊")
	if actor.captive or actor.surrender_pending or actor.action_time > 0.0:
		return SiteRuntime.fail("BUSY", "原人物須清醒自由並收束動作")
	return join_player(actor)

## v2 plan 3.4 募兵, third source: a person who left another team of the same
## faction (a retired row in that container). Needs this team's recruit decider,
## the source team's 名冊 decider (an NPC accepts when its team is stopped; a
## controlled decider must be the requester) and the person's consent (NPC: free
## and idle). Everything is checked first; the row then moves (still retired)
## and joins here; if joining were refused, the row is moved back unchanged.
func recruit_from_team(source: TerrainArmy, requester_id: int, person_id: int) -> Dictionary:
	var refused := duty_authority("team.recruit", requester_id)
	if not refused.is_empty(): return refused
	if source == null or source == self or not is_instance_valid(source) or source.faction_id != faction_id or source.data != data or not source.garrison_feature_id.is_empty():
		return SiteRuntime.fail("INVALID_TEAM", "來源須是同地圖、同陣營的另一支隊伍")
	var controlled := int(controlled_person_query.call()) if controlled_person_query.is_valid() else -1
	var source_roster := source.duty_decider("team.roster")
	if source_roster <= 0 or source_roster == controlled and source_roster != requester_id:
		return SiteRuntime.fail("NEEDS_CONSENT", "來源隊的名冊負責者須同意（玩家須本人提出）")
	var index := source.index_for_identity(person_id)
	if index < 0 or index == PLAYER_MEMBER or source.is_member(index) or source.member_gone(index):
		return SiteRuntime.fail("NO_TARGET", "無合格原人物（須是來源隊已退隊的在世原人物）")
	if person_id == controlled: return SiteRuntime.fail("NEEDS_CONSENT", "此人目前由玩家控制：須由本人明示確認入隊")
	if not source.combat_can_act(index) or str(source.combat_hot_get(index, &"pose")) != "idle" or not source.combat_units[index].get("work_task", {}).is_empty():
		return SiteRuntime.fail("BUSY", "原人物須清醒自由並完成或取消作業")
	if not roster_change_ready() or not source.roster_change_ready():
		return SiteRuntime.fail("BUSY", "兩隊都須停止、HOLD 並脫戰")
	var proposed := materialized_combat_rows()
	var arriving: Dictionary = source.materialized_combat_rows()[index].duplicate()
	arriving.member = true
	proposed.append(arriving)
	if single_troop_class(proposed, data, _troop_exempt_ids(), _troop_actor(player_member)) == &"mixed":
		return SiteRuntime.fail("MIXED_TROOP", "入隊裝備與普通隊員兵種不同；原人物與持物未改")
	var moved := source.transfer_members_to(self, [person_id] as Array[int], source.index_for_identity(source_roster), index_for_identity(duty_decider("team.roster")), -1, true)
	if not bool(moved.get("ok", false)): return moved
	var joined := _change_row_membership(person_id, true, requester_id)
	if not bool(joined.get("ok", false)):
		transfer_members_to(source, [person_id] as Array[int], index_for_identity(duty_decider("team.roster")), source.index_for_identity(source_roster), -1, true)
		return joined
	return SiteRuntime.ok("已由 #%d 自隊伍 #%d 募入 #%d" % [requester_id, source.team_id, person_id])

## Former members of this team a recruiter can enlist now (the source above).
func recruit_candidates() -> Array[int]:
	var result: Array[int] = []
	for index: int in combat_units.size():
		if is_member(index) or member_gone(index) or is_controlled_person(index) or not combat_can_act(index): continue
		result.append(combat_identity(index))
	return result

## R7 C0: the leave/join refusals of one team row, verbatim from the former change body. Reads only; used by the change and by a batch phase 1.
func row_membership_refusal(person_id: int, joining: bool, recruiter_id: int = -1, npc_event: bool = false) -> Dictionary:
	if not garrison_feature_id.is_empty(): return SiteRuntime.fail("GARRISONED", "駐營人員沿軍營的編成或解編入口辦理")
	var index := index_for_identity(person_id)
	if not combat_enabled or index < 0 or index == PLAYER_MEMBER:
		return SiteRuntime.fail("NO_TARGET", "須為此原容器中的實際人物；不建立第二份隊員")
	# R6 S5D (plan 10.1/10.2): an NPC departure is a declared npc_event; the controlled person may not use it.
	if (npc_event and is_controlled_person(index)) or (not npc_event and recruiter_id < 0 and not is_controlled_person(index)) or (recruiter_id >= 0 and not joining):
		return SiteRuntime.fail("NO_AUTHORITY", "只有目前受控的原人物可自行入退队")
	if is_member(index) == joining:
		return SiteRuntime.fail("NO_TARGET", "已是此隊成員" if joining else "已正式退隊")
	var row: Dictionary = combat_units[index]
	if (is_inside_tree() and get_tree().paused) or bool(data.site.get("paused", false)) or not combat_can_act(index) or moving_to[index] != INVALID_CELL or bool(combat_hot_get(index, &"attack")) or str(combat_hot_get(index, &"pose")) != "idle" or _unit_rescues.has(index) or patient_has_rescuer(index) or not row.get("work_task", {}).is_empty():
		return SiteRuntime.fail("BUSY", "原人物須清醒自由並完成或取消移動、攻防、救助及作業")
	if vehicle_transport != null:
		var ship_guard: Dictionary = vehicle_transport.can_membership_change(person_id)
		if not bool(ship_guard.get("ok", false)): return ship_guard
	if joining:
		var proposed_rows := materialized_combat_rows()
		proposed_rows[index].member = true
		if single_troop_class(proposed_rows, data, _troop_exempt_ids(), _troop_actor(player_member)) == &"mixed":
			return SiteRuntime.fail("MIXED_TROOP", "入隊裝備與普通隊員兵種不同；原人物與持物未改")
	elif cape_departure_guard.is_valid():
		var cape_guard: Dictionary = cape_departure_guard.call(person_id)
		if not cape_guard.ok: return cape_guard
	return SiteRuntime.ok()

func _change_row_membership(person_id: int, joining: bool, recruiter_id: int = -1, npc_event: bool = false) -> Dictionary:
	var refusal: Dictionary = row_membership_refusal(person_id, joining, recruiter_id, npc_event)
	if not bool(refusal.get("ok", false)): return refusal
	var index := index_for_identity(person_id)
	# No body/cargo mutation precedes this hook. A failed hook must leave its
	# original supply owners untouched; after success only infallible state commits.
	# The hook checks active person jobs/deliveries; a stationary captivity guard
	# is a relationship, not a busy action, and follows the same original person.
	if membership_change_hook.is_valid():
		var supplied: Dictionary = membership_change_hook.call(self, person_id, joining)
		if not bool(supplied.get("ok", false)):
			return supplied
	return commit_row_membership_change(person_id, joining)

## R7 C1: the post-hook flip of one team row membership change. No refusal path: the check and the membership hook have run.
func commit_row_membership_change(person_id: int, joining: bool) -> Dictionary:
	var index := index_for_identity(person_id)
	if joining:
		var count := living_member_count()
		training = training * count / (count + 1.0)
	combat_hot_set(index, &"member", joining)
	sync_shared_fatigue(true)
	combat_hot_set(index, &"present", false)
	combat_slots[index] = INVALID_CELL if _ship_embarked(index) else cells[index]
	for slot: int in _vacancy_assignments.keys():
		if slot == index or int(_vacancy_assignments[slot]) == index:
			_vacancy_assignments.erase(slot)
	if not joining:
		if _combat_move_plan != null:
			_combat_move_plan.remove_member(person_id)
		if _combat_deployment_plan != null:
			_combat_deployment_plan.remove_member(person_id, CombatMovementTypes.SlotVacancyReason.MEMBER_REMOVED)
		_sync_combat_deployment_leases()
	if vehicle_transport != null: vehicle_transport.on_membership_changed(person_id)
	_command_dirty = true
	settle_combat_command()
	_mark_visual_row(index)
	queue_redraw()
	return SiteRuntime.ok("已回到原隊伍；原人物與持物不變" if joining else "已正式退隊；原人物仍在現場自主行動")

func join_player(actor: TerrainTestCharacter) -> Dictionary:
	if not garrison_feature_id.is_empty(): return SiteRuntime.fail("GARRISONED", "駐營容器不使用一般入隊入口")
	if is_inside_tree() and get_tree().paused:
		return SiteRuntime.fail("BUSY", "暫停時不處理入隊")
	if not combat_enabled or not is_instance_valid(actor) or actor not in [player, npc] or actor.person_id <= 0 or actor.faction_id != faction_id:
		return SiteRuntime.fail("NO_TARGET", "只能加入同陣營且已部署的隊伍")
	if is_instance_valid(player_member) or not actor.can_act() or actor.is_moving():
		return SiteRuntime.fail("BUSY", "已入隊或人物目前無法入隊")
	if single_troop_class(materialized_combat_rows(), data, _troop_exempt_ids(), _troop_actor(actor)) == &"mixed":
		return SiteRuntime.fail("MIXED_TROOP", "入隊裝備與普通隊員兵種不同；原人物與持物未改")
	if player_supply_hook.is_valid():
		var supplied: Dictionary = player_supply_hook.call(self, actor, true)
		if not supplied.ok:
			return supplied
	var members := 0
	for index in range(combat_units.size()):
		if is_member(index) and not member_gone(index):
			members += 1
	# The unaffiliated newcomer is an untrained batch of one, not a personal XP table.
	training = training * members / (members + 1.0)
	player_member = actor
	sync_shared_fatigue(true)
	player_goal = actor.terrain_cell
	player_present = false
	_command_dirty = true
	settle_combat_command()
	queue_redraw()
	return SiteRuntime.ok("已入隊；移動與攻擊仍由你自行操作")

func leave_player() -> Dictionary:
	if is_inside_tree() and get_tree().paused:
		return SiteRuntime.fail("BUSY", "暫停時不處理退隊")
	if not is_instance_valid(player_member):
		return SiteRuntime.fail("NO_TARGET", "尚未加入此隊")
	if cape_departure_guard.is_valid():
		var cape_guard: Dictionary = cape_departure_guard.call(player_member.person_id)
		if not cape_guard.ok: return cape_guard
	if player_supply_hook.is_valid():
		var supplied: Dictionary = player_supply_hook.call(self, player_member, false)
		if not supplied.ok:
			return supplied
	for index: int in _unit_rescues.keys():
		if int(_unit_rescues[index].patient) == PLAYER_MEMBER:
			_cancel_unit_rescue(index)
	if is_instance_valid(player_member): PersonFatigue.unbind(player_member)
	player_member = null
	sync_shared_fatigue(true)
	player_present = false
	player_goal = INVALID_CELL
	_command_dirty = true
	settle_combat_command()
	queue_redraw()
	return SiteRuntime.ok("已正式退隊；未搬動人物或更換裝備")

func _draw() -> void:
	for missile: Dictionary in projectiles:
		var kind := str(missile.get("visual", "arrow"))
		if not _projectile_textures.has(kind):
			var path := "res://assets/characters/human/q35/combat/" + kind + ".res"
			if ResourceLoader.exists(path):
				_projectile_textures[kind] = load(path)
		if _projectile_textures.has(kind):
			var texture := _projectile_textures[kind] as Texture2D
			var width := (0.39 if kind == "bolt" else 0.78) * CharacterRenderContract.MAP_PIXELS_PER_METRE
			var height := width * texture.get_height() / texture.get_width()
			draw_set_transform(to_local(missile.position), (missile.velocity as Vector2).angle())
			draw_texture_rect(texture, Rect2(-width, -height * 0.5, width, height), false)
			draw_set_transform(Vector2.ZERO)
	if is_instance_valid(player_member) and player_goal != INVALID_CELL:
		var point := (Vector2(player_goal) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		draw_arc(point, 14.0, 0, TAU, 24, Color(0.2, 1.0, 1.0, 0.95), 2.0)
		draw_line(point + Vector2(-7, 0), point + Vector2(7, 0), Color.CYAN, 2.0)
		draw_line(point + Vector2(0, -7), point + Vector2(0, 7), Color.CYAN, 2.0)

func _initialize_combat_command() -> void:
	combat_slots.assign(cells)
	command_rng.seed = data.seed_value * 1009 + team_id
	formal_commander = 0
	current_commander = 0
	acting_commander = -1
	var centre := Vector2.ZERO
	for cell: Vector2i in combat_slots:
		centre += Vector2(cell)
	centre /= combat_slots.size()
	command_radius = 8.0
	for cell: Vector2i in combat_slots:
		command_radius = maxf(command_radius, centre.distance_to(Vector2(cell)) + 2.0)
	_refresh_command_presence()
	_ensure_command_abilities(0)
	_command_dirty = true

func _refresh_command_presence() -> void:
	if has_ship_journey(): return # Coarse owner retains the original team order.
	# Commander hysteresis reads the presence that held before this refresh.
	var prior := {}
	for index: int in [formal_commander, acting_commander]:
		if index == PLAYER_MEMBER:
			prior[index] = player_present
		elif index >= 0 and index < combat_units.size():
			prior[index] = bool(combat_hot_get(index, &"present"))
	_refresh_reference_presence()
	_refresh_commander_presence(prior)

## Nekki 2026-10-13 (commander presence, option 1): a commander is present when
## within command_radius (with the same two-cell hysteresis) of the reference OR
## of any other living, free member of their own formation. The deployment keeps
## the commander's rear slot. Every other row keeps the reference presence. The
## commander rows are rewritten on every refresh, so a native delta cache can
## never leave a stale commander flag behind.
func _refresh_commander_presence(prior: Dictionary) -> void:
	var others: Array[Vector2] = []
	var owners: Array[int] = []
	for index: int in command_members():
		if member_gone(index) or (player_member.captive if index == PLAYER_MEMBER else bool(combat_hot_get(index, &"captive"))):
			continue
		others.append(combat_ground(index) / TerrainRenderer.CELL_PIXELS)
		owners.append(index)
	for index: int in prior:
		var radius := command_radius + (2.0 if bool(prior[index]) else 0.0)
		var able: bool
		if index == PLAYER_MEMBER:
			able = is_instance_valid(player_member) and player_member.can_act()
		else:
			able = is_member(index) and combat_can_act(index)
		var present := false
		if able:
			var own := combat_ground(index) / TerrainRenderer.CELL_PIXELS
			present = command_reference_valid and command_reference.distance_to(own) <= radius
			for at in range(owners.size()):
				if present: break
				if owners[at] != index and others[at].distance_to(own) <= radius: present = true
		if index == PLAYER_MEMBER: player_present = present
		else: combat_hot_set(index, &"present", present)

func _refresh_reference_presence() -> void:
	# Only the original pure Army methods qualify; live player hooks stay in GD.
	var embarked := _team_has_embarked()
	if embarked: _presence_geometry_cache = []
	var projection: Array = []
	if not embarked and native_presence_enabled and get_script() == TerrainArmy and not is_instance_valid(player_member) and moving_to.size() == combat_units.size() and TerrainRenderer.CELL_PIXELS == 64.0 and Vector2(16777217.0, 0.0).x == 16777216.0:
		var kernel := _combat_hot_store if combat_hot_active() else _get_idle_kernel()
		if kernel != null and kernel.has_method("command_presence"):
			var moving_positions := {}
			for index in range(moving_to.size()):
				if moving_to[index] != INVALID_CELL:
					moving_positions[index] = combat_ground(index) / TerrainRenderer.CELL_PIXELS
			if native_presence_delta_enabled and kernel.has_method("command_presence_delta"):
				var changes: Array = kernel.call("command_presence_delta", combat_units, cells, moving_positions, command_radius, _presence_geometry_cache)
				if changes.size() == 5:
					var reference: PackedVector2Array = changes[0]
					var indices: PackedInt32Array = changes[1]
					var values: PackedByteArray = changes[2]
					command_reference_valid = not reference.is_empty()
					if command_reference_valid: command_reference = reference[0]
					# The native projection rejects aliases; apply only changed original rows.
					for at in range(indices.size()):
						combat_hot_set(indices[at], &"present", values[at] != 0)
					_presence_geometry_cache = changes[3]
					_presence_geometry_cache.make_read_only()
					native_presence_delta_calls += 1
					native_presence_changed_rows += indices.size()
					native_presence_geometry_rebuilds += int(changes[4])
					native_presence_geometry_reuses += int(not changes[4])
					native_presence_rows += combat_units.size()
					return # Native presence projection applied by the original owner.
			projection = kernel.call("command_presence", combat_units, cells, moving_positions)
	if projection.size() == 2:
		var reference: PackedVector2Array = projection[0]
		var distances: PackedFloat64Array = projection[1]
		command_reference_valid = not reference.is_empty()
		if command_reference_valid: command_reference = reference[0]
		for index in range(combat_units.size()):
			# Read hysteresis immediately before this write, even for aliased rows.
			var radius := command_radius + (2.0 if bool(combat_hot_get(index, &"present")) else 0.0)
			combat_hot_set(index, &"present", distances[index] >= 0.0 and distances[index] <= radius)
		native_presence_rows += combat_units.size()
		return # Native presence projection applied by the original owner.
	var positions: Array[Vector2] = []
	var members: Array[int] = []
	for index: int in command_members():
		if member_gone(index) or (player_member.captive if index == PLAYER_MEMBER else bool(combat_hot_get(index, &"captive"))):
			continue
		var ground := combat_ground(index) / TerrainRenderer.CELL_PIXELS
		positions.append(ground)
		members.append(index)
	command_reference_valid = not members.is_empty()
	if command_reference_valid:
		var identities: Array[int] = []
		for index: int in members: identities.append(combat_identity(index))
		command_reference = _command_reference_from_positions(positions, identities)
	for index in range(combat_units.size()):
		var radius := command_radius + (2.0 if bool(combat_hot_get(index, &"present")) else 0.0)
		combat_hot_set(index, &"present", is_member(index) and command_reference_valid and combat_can_act(index) and command_reference.distance_to(combat_ground(index) / TerrainRenderer.CELL_PIXELS) <= radius)
	if is_instance_valid(player_member):
		var radius := command_radius + (2.0 if player_present else 0.0)
		player_present = command_reference_valid and player_member.can_act() and command_reference.distance_to(combat_ground(PLAYER_MEMBER) / TerrainRenderer.CELL_PIXELS) <= radius

static func _command_reference_from_positions(positions: Array[Vector2], identities: Array[int]) -> Vector2:
	var horizontal: Array[float] = []
	var vertical: Array[float] = []
	for member_position: Vector2 in positions:
		horizontal.append(member_position.x)
		vertical.append(member_position.y)
	horizontal.sort()
	vertical.sort()
	var middle := floori(float(positions.size()) / 2.0)
	var lower := floori(float(positions.size() - 1) / 2.0)
	var median_point := Vector2((horizontal[middle] + horizontal[lower]) * 0.5, (vertical[middle] + vertical[lower]) * 0.5)
	var reference := Vector2.ZERO
	var best := INF
	var best_identity := 2147483647
	# Stable row identity breaks ties; positions never swap on promotion.
	for position_index in range(positions.size()):
		var distance := positions[position_index].distance_squared_to(median_point)
		var identity: int = identities[position_index]
		if distance < best or distance == best and identity < best_identity:
			best = distance
			best_identity = identity
			reference = positions[position_index]
	return reference

func command_eligible(index: int) -> bool:
	if not base_command_eligible(index): return false
	return index == formal_commander or is_serving_military(index)

## The pre-R1b test: a present, able, ungarrisoned officer. Only for a new team's
## first captain and for naming officers who could be seated.
func base_command_eligible(index: int) -> bool:
	if not garrison_feature_id.is_empty() or military_role(index) != "officer": return false
	if index == PLAYER_MEMBER:
		return is_instance_valid(player_member) and player_member.can_act() and player_present
	return is_member(index) and combat_can_act(index) and bool(combat_hot_get(index, &"present"))

func is_serving_military(index: int) -> bool:
	if _serving_dirty: _rebuild_serving()
	return _serving_ids.has(combat_identity(index))

func _rebuild_serving() -> void:
	_serving_ids.clear()
	_serving_dirty = false
	for seat: Dictionary in offices.get("positions", []):
		if bool(seat.head) or int(seat.holder) <= 0: continue
		var index := index_for_identity(int(seat.holder))
		if index >= 0 and military_role(index) == "officer" and not member_gone(index): _serving_ids[int(seat.holder)] = true

func _mark_serving_dirty() -> void:
	_serving_dirty = true

func military_role(index: int) -> String:
	if index == PLAYER_MEMBER:
		return player_member.military_role if is_instance_valid(player_member) else "civilian"
	return str(combat_units[index].get("military_role", "soldier")) if index >= 0 and index < combat_units.size() else "civilian"

## Phase 1 (pure): may this person take `next_role`? Nothing changes here — no
## role, ability, RNG or settle. A post that needs no officer qualification (文官,
## without 訓練/軍團編成) is kept on demotion, which only ends command rights; a
## 武官 post, officer duty, captaincy or a postless cadre place needs the rank.
func prepare_military_role(person_id: int, next_role: String) -> Dictionary:
	if next_role not in ["officer", "soldier", "civilian"]:
		return SiteRuntime.fail("INVALID_ROLE", "軍職資料無效")
	var index := index_for_identity(person_id)
	if index < 0 or not is_member(index) or member_gone(index) or not roster_change_ready():
		return SiteRuntime.fail("BUSY", "軍職變更須為停止、脫戰的原成員")
	var seat := SiteOffices.position_of(offices, person_id)
	if next_role != "officer" and (index in [formal_commander, acting_commander, current_commander] \
		or not seat.is_empty() and SiteOffices.needs_officer(offices, seat) or seat.is_empty() and (officer_order.has(index) or officer_service.has(index))):
		return SiteRuntime.fail("HAS_APPOINTMENT", "請先解除現有隊長、武官職位或幹部職務")
	return SiteRuntime.ok("", {"index": index})

func _holds_civil_seat(index: int) -> bool:
	return str(SiteOffices.position_of(offices, combat_identity(index)).get("office_class", "")) == "civil"

func set_military_role(person_id: int, next_role: String) -> Dictionary:
	var prepared := prepare_military_role(person_id, next_role)
	if not prepared.ok: return prepared
	var index := int(prepared.index)
	if index == PLAYER_MEMBER: player_member.military_role = next_role
	else: combat_units[index].military_role = next_role
	if next_role == "officer": _ensure_command_abilities(index)
	# A garrisoned container has no command or posts in use: no auto-appointment there.
	if next_role == "officer" and index != formal_commander and garrison_feature_id.is_empty(): _auto_seat_officers([index])
	_sync_officer_order() # rank decides succession-order membership of post holders
	_mark_serving_dirty()
	_command_dirty = true
	settle_combat_command()
	return SiteRuntime.ok("已更新原人物軍官資格；能力與持物保留")

func set_garrison(feature_id: String, initialize_home: bool = false) -> void:
	var new_registration := garrison_feature_id != feature_id
	garrison_feature_id = feature_id
	if feature_id.is_empty(): return
	if new_registration or initialize_home: combat_slots.assign(cells)
	formal_commander = -1
	acting_commander = -1
	current_commander = -1
	officer_order.clear()
	officer_service.clear()
	_stop_tactical_ai()
	needs_attack_order = true
	combat_attacking = false
	combat_order = CombatOrder.HOLD
	command = Command.NONE
	_release_combat_deployment_lease()
	_combat_move_plan = null
	_combat_deployment_plan = null
	_vacancy_assignments.clear()
	_order_delay = 0.0
	combat_goal = INVALID_CELL
	pursuit_left = 0.0
	pursuit_target = -1
	_formation_change_pending = false
	_formation_retry_seconds = 0.0
	_clear_member_attack_targets()
	_refresh_command_presence() # Original life/presence projection still excludes KO/dead rows.
	_command_dirty = false

func _ensure_command_abilities(index: int) -> void:
	if index == PLAYER_MEMBER:
		if player_member.command_abilities.is_empty():
			player_member.command_abilities = {"tactics": command_rng.randi_range(0, 100), "leadership": command_rng.randi_range(0, 100), "coach": command_rng.randi_range(0, 100)}
		return
	if not command_abilities.has(index):
		command_abilities[index] = {"tactics": command_rng.randi_range(0, 100), "leadership": command_rng.randi_range(0, 100), "coach": command_rng.randi_range(0, 100)}

func command_effect(kind: String, cap: float) -> float:
	var total := 0.0
	if command_eligible(PLAYER_MEMBER):
		total += float(player_member.command_abilities.get(kind, 0))
	for index: int in command_abilities:
		if command_eligible(index):
			total += float(command_abilities[index].get(kind, 0))
	return SiteCombatRules.diminishing(total, cap)

func _select_commander(founding: bool = false) -> int:
	# founding: a new team's first captain may be any present officer (original rule).
	# Otherwise only 在任武官 can act or succeed (R1b); none means wait and self-defend.
	var eligible := func(index: int) -> bool: return base_command_eligible(index) if founding else command_eligible(index)
	for index: int in officer_order:
		if eligible.call(index):
			return index
	var candidates: Array[int] = []
	for index: int in command_members():
		if eligible.call(index):
			candidates.append(index)
	candidates.sort_custom(func(a: int, b: int) -> bool: return combat_identity(a) < combat_identity(b))
	return -1 if candidates.is_empty() else candidates[command_rng.randi_range(0, candidates.size() - 1)]

func record_officer_service(members: Array[int], appointed: bool) -> Dictionary:
	# Personnel-event integration, not a player appointment/sovereign-authority UI.
	if not combat_enabled or not garrison_feature_id.is_empty() or (is_inside_tree() and get_tree().paused):
		return SiteRuntime.fail("BUSY")
	var seen := {}
	for index: int in members:
		if appointed and military_role(index) != "officer":
			return SiteRuntime.fail("NOT_OFFICER", "須先明確晉任軍官才可擔任幹部")
		if not is_member(index) or member_gone(index) or index == formal_commander or seen.has(index):
			return SiteRuntime.fail("INVALID_MEMBER")
		seen[index] = true
	if not appointed:
		var exemptions := _troop_exempt_ids()
		for index: int in members: exemptions.erase(combat_identity(index))
		if single_troop_class(materialized_combat_rows(), data, exemptions, _troop_actor(player_member)) == &"mixed":
			return SiteRuntime.fail("MIXED_TROOP", "卸任後配裝須符合普通隊員兵種；職務與實物未改")
		if cape_retirement.is_valid():
			var retiring: Array[int] = []
			for index: int in members:
				retiring.append(combat_identity(index))
			var cape_guard: Dictionary = cape_retirement.call(retiring)
			if not cape_guard.ok: return cape_guard
	var batch := members.duplicate()
	batch.sort_custom(func(a: int, b: int) -> bool: return combat_identity(a) < combat_identity(b))
	if appointed:
		# Cadre = a post holder (R1b): every newly appointed officer needs a free 武官 post.
		var needed := 0
		for index: int in batch:
			if SiteOffices.position_of(team_offices(), combat_identity(index)).is_empty(): needed += 1
		if needed > _free_military_seats():
			return SiteRuntime.fail("NO_POSITION", "沒有足夠的空缺武官職位；請先在職位頁新增武官職位並分配職責")
	_sync_officer_order()
	for index: int in batch:
		if appointed:
			_ensure_command_abilities(index)
		else:
			officer_service.erase(index)
			officer_order.erase(index)
	if appointed: _auto_seat_officers(batch)
	else:
		# Leaving cadre service also ends the 武官 post (v2: a post is the appointment).
		var leaving := {}
		for index: int in batch: leaving[combat_identity(index)] = true
		SiteOffices.vacate_unless(team_offices(), func(holder: int) -> bool: return not leaving.has(holder))
	_mark_serving_dirty()
	_command_dirty = true
	settle_combat_command()
	return SiteRuntime.ok()

func _sync_officer_order() -> void:
	_project_cadre()
	# Old snapshots know only the prior ranking: keep it as their fixed fallback.
	for index: int in officer_order:
		if not officer_service.has(index):
			officer_service.append(index)
	for index: int in officer_service.duplicate():
		var civil := _holds_civil_seat(index)
		if not is_member(index) or member_gone(index) or index == formal_commander or military_role(index) != "officer" and not civil:
			officer_service.erase(index)
			officer_order.erase(index)
		elif military_role(index) != "officer":
			officer_order.erase(index) # 文官 cadre without officer rank: no succession place.
		elif not officer_order.has(index):
			officer_order.append(index)

## Cadre list follows posts (R1b). New holders join cadre (officer-qualified
## ones, 文官 or 武官, also the succession order); a holder who lost the post leaves both. Cadre without any
## post that were already there (pre-R1b saves beyond the free posts) are left as
## 待分職幹部 for the head to seat or release: see pending_cadre().
func _project_cadre() -> void:
	if offices.is_empty(): return
	var now := {}
	for seat: Dictionary in offices.get("positions", []):
		if bool(seat.head) or int(seat.holder) <= 0 or index_for_identity(int(seat.holder)) < 0: continue
		now[int(seat.holder)] = str(seat.get("office_class", "military"))
	for identity: int in _last_holders:
		if now.has(identity): continue
		var gone := index_for_identity(identity)
		if gone >= 0:
			officer_service.erase(gone)
			officer_order.erase(gone)
	var added: Array = now.keys()
	added.sort()
	for identity: int in added:
		var index := index_for_identity(identity)
		if index < 0 or index == formal_commander: continue
		if not officer_service.has(index): officer_service.append(index)
		if military_role(index) == "officer":
			_ensure_command_abilities(index)
			if not officer_order.has(index): officer_order.append(index)
		else:
			officer_order.erase(index)
	_last_holders = now

func _free_military_seats() -> int:
	var free := 0
	for seat: Dictionary in team_offices().positions:
		if not bool(seat.head) and int(seat.holder) <= 0 and str(seat.get("office_class", "military")) == "military" \
			and not SiteOffices.duties_of_position(offices, str(seat.id)).is_empty(): free += 1
	return free

## Pre-R1b cadre with no post (MIGRATION_REQUIRED): visible, without command
## rights (R1b), until the head appoints them to a post or releases them.
func pending_cadre() -> Array[int]:
	var pending: Array[int] = []
	for index: int in officer_service:
		if SiteOffices.position_of(team_offices(), combat_identity(index)).is_empty(): pending.append(combat_identity(index))
	return pending

func settle_combat_command() -> void:
	if has_ship_journey(): return # Coarse owner retains the original team order.
	if not garrison_feature_id.is_empty():
		if _command_dirty: set_garrison(garrison_feature_id)
		return
	if not combat_enabled or not _command_dirty or (is_inside_tree() and get_tree().paused):
		return
	_command_dirty = false
	_refresh_command_presence()
	_mark_serving_dirty()
	if formal_commander >= 0 and formal_commander != PLAYER_MEMBER and formal_commander < combat_units.size() or formal_commander == PLAYER_MEMBER:
		_head_established = true # Any captain ever assigned (deploy sets row 0 directly) ends founding.
	var old_formal := formal_commander
	var old_current := current_commander
	var old_acting := acting_commander
	_sync_officer_order()
	var permanent_vacancy := not is_member(formal_commander) or member_gone(formal_commander) or military_role(formal_commander) != "officer"
	if permanent_vacancy:
		formal_commander = acting_commander if command_eligible(acting_commander) else _select_commander(not _head_established)
		if formal_commander >= 0: _head_established = true
		acting_commander = -1
		current_commander = formal_commander
	elif command_eligible(formal_commander):
		current_commander = formal_commander
		acting_commander = -1
	else:
		if not command_eligible(acting_commander):
			acting_commander = _select_commander()
		current_commander = acting_commander
	if current_commander >= 0:
		_ensure_command_abilities(current_commander)
		officer_order.erase(formal_commander)
		officer_service.erase(formal_commander)
	else:
		needs_attack_order = true
		combat_attacking = false
		_clear_member_attack_targets()
		if combat_order != CombatOrder.RETREAT:
			_release_combat_deployment_lease()
			combat_order = CombatOrder.HOLD
			_combat_move_plan = null
			_combat_deployment_plan = null
			# Absence slots derive from the discarded plan; saves cannot retain orphan slots.
			_combat_absent_slots.clear()
			combat_goal = INVALID_CELL
			pursuit_left = 0.0
			_vacancy_assignments.clear()
	if old_formal != formal_commander or old_current != current_commander or old_acting != acting_commander:
		command_notice = "無合格指揮者；自衛並等候新令" if current_commander < 0 else ("正式隊長 %d 指揮" % combat_identity(current_commander) if acting_commander < 0 else "隊長 %d 暫時失格；%d 代理" % [combat_identity(formal_commander), combat_identity(acting_commander)])

## R2 (§8.1): a holder whose post ends through someone else's plan, without a
## new post in the same plan, records one +10 grievance event against this team.
## A move between seats, the holder's own request, death or leaving are not dismissals.
func _record_dismissals(before: Dictionary, after: Dictionary, requester_id: int) -> void:
	if data == null: return
	var site_id := str(data.site.get("id", ""))
	for seat: Dictionary in before.get("positions", []):
		var holder := int(seat.holder)
		if bool(seat.head) or holder <= 0 or holder == requester_id or not SiteOffices.position_of(after, holder).is_empty(): continue
		var index := index_for_identity(holder)
		if index < 0 or member_gone(index) or not is_member(index): continue
		var body: Variant = player_member if index == PLAYER_MEMBER else combat_units[index]
		SiteSocial.record(body, SiteSocial.team_ref(site_id, team_id), "dismissed", 10,
			"dismiss:%d:%d:%d" % [team_id, int(after.revision), holder], int(data.site.get("minute", 0)))

## v2 plan §3.3 「空缺隊長就任」: the captaincy is permanently vacant and no
## qualified 在任幹部 can succeed (settle found nobody). After the team has
## stopped and left combat, the controlled member of this team names a present,
## able officer of the team (no post or cadre service needed). One commit sets
## the formal captain (head projection), the cadre lists, and vacates that
## person's old post. Temporary KO/captivity never opens this entry.
func claim_vacant_captaincy(requester_id: int, candidate_id: int) -> Dictionary:
	if not combat_enabled or not garrison_feature_id.is_empty() or (is_inside_tree() and get_tree().paused):
		return SiteRuntime.fail("BUSY")
	_command_dirty = true
	settle_combat_command()
	if formal_commander >= 0:
		return SiteRuntime.fail("NOT_VACANT", "隊長在任或已由順位接任；暫時昏迷／被俘由代理規則處理")
	if not roster_change_ready():
		return SiteRuntime.fail("BUSY", "須先讓全隊停止、HOLD 並脫離交戰")
	var controlled := int(controlled_person_query.call()) if controlled_person_query.is_valid() else -1
	var requester := index_for_identity(requester_id)
	if requester_id != controlled or requester < 0 or not is_member(requester) or member_gone(requester):
		return SiteRuntime.fail("NO_AUTHORITY", "須由本隊目前受控的在世成員提交")
	var candidate := index_for_identity(candidate_id)
	if candidate < 0 or not is_member(candidate) or member_gone(candidate) or not base_command_eligible(candidate):
		return SiteRuntime.fail("NOT_ELIGIBLE", "人選須是本隊在場、可行動且具軍官資格的成員")
	# Commit once: old post vacant, cadre lists, captain, head projection.
	SiteOffices.vacate_unless(team_offices(), func(holder: int) -> bool: return holder != candidate_id)
	officer_service.erase(candidate)
	officer_order.erase(candidate)
	formal_commander = candidate
	acting_commander = -1
	current_commander = candidate
	_head_established = true
	_ensure_command_abilities(candidate)
	_mark_serving_dirty()
	_command_dirty = true
	settle_combat_command()
	command_notice = "%d 就任空缺隊長" % candidate_id
	return SiteRuntime.ok("已由 #%d 就任空缺隊長；原職位已空缺" % candidate_id)

func reorder_officers(requester: int, proposed: Array[int]) -> Dictionary:
	if is_inside_tree() and get_tree().paused:
		return SiteRuntime.fail("BUSY")
	_command_dirty = true
	settle_combat_command()
	if requester != formal_commander or requester != current_commander or not command_eligible(requester) or moving_member_count() > 0 or (is_instance_valid(player_member) and player_member.is_moving()) or float(data.site.get("combat_left", 0.0)) > 0.0 or combat_order != CombatOrder.HOLD or is_sustain_routed():
		return SiteRuntime.fail("BUSY", "僅在場正式隊長可於停止且脫戰時調整順位")
	var existing := officer_order.duplicate()
	var replacement := proposed.duplicate()
	existing.sort()
	replacement.sort()
	if existing != replacement:
		return SiteRuntime.fail("INVALID_ORDER", "須保留每位現任幹部恰好一次")
	officer_order.assign(proposed)
	return SiteRuntime.ok("已套用接任順位")

## Team offices (OFFICE_POSITIONS_AND_DUTIES_PLAN 6.3). Created on first use with
## the one-position-per-duty default; old saves get theirs from restore with
## duty AI off. Every vacant position is exercised by the head, so the default
## grants exactly the commander's original authority.
func team_offices(read_only: bool = false) -> Dictionary:
	if read_only:
		if offices.is_empty():
			var controlled := int(controlled_person_query.call()) if controlled_person_query.is_valid() else -1
			var head := combat_identity(formal_commander) if formal_commander >= 0 else -1
			return SiteOffices.default_offices("team", -1, head > 0 and head != controlled)
		if not SiteOffices.validate(offices, "team", false): return {}
		var current: Dictionary = offices
		var migration := int(current.version) < SiteOffices.VERSION
		for duty: String in SiteOffices.duty_ids("team"):
			migration = migration or not current.duties.has(duty)
		if migration:
			current = current.duplicate(true)
			SiteOffices.ensure_catalog(current, "team")
			SiteOffices.upgrade(current)
		return current
	if offices.is_empty():
		var controlled := int(controlled_person_query.call()) if controlled_person_query.is_valid() else -1
		var head := combat_identity(formal_commander) if formal_commander >= 0 else -1
		offices = SiteOffices.default_offices("team", -1, head > 0 and head != controlled)
	elif SiteOffices.ensure_catalog(offices, "team"):
		offices.revision = int(offices.revision) + 1
	SiteOffices.upgrade(offices)
	_vacate_unqualified_holders()
	_mark_serving_dirty()
	return offices

## A seat needing officer qualification (武官, or any seat with 訓練/軍團編成) needs
## an able officer; other 文官 seats (v2 plan R1a) any member, soldier or civilian.
## Officer rank, not the class, is what gives command rights (2026-10-07).
func office_holder_ok(person_id: int) -> bool:
	var index := index_for_identity(person_id)
	if index < 0: return false
	if _seat_needs_officer(person_id): return base_command_eligible(index) # v2 §3.2: rank, not prior cadre service.
	return _member_can_serve(index)

func _seat_needs_officer(person_id: int) -> bool:
	var seat := SiteOffices.position_of(offices, person_id)
	return not seat.is_empty() and SiteOffices.needs_officer(offices, seat)

func _member_can_serve(index: int) -> bool:
	if index == PLAYER_MEMBER: return is_instance_valid(player_member) and player_member.can_act() and player_present
	return is_member(index) and combat_can_act(index) and bool(combat_hot_get(index, &"present"))

func office_candidate_ok(person_id: int, office_class: String = "military") -> bool:
	var index := index_for_identity(person_id)
	if index < 0 or index == formal_commander or member_gone(index) or index != PLAYER_MEMBER and not is_member(index): return false
	return military_role(index) == "officer" if office_class == "military" else true

func _vacate_unqualified_holders() -> void:
	# Only appointment loss vacates: KO/captivity keep the seat (head acts meanwhile).
	SiteOffices.vacate_unless(offices, func(person_id: int) -> bool:
		var index := index_for_identity(person_id)
		if index < 0 or index == formal_commander: return false
		if _seat_needs_officer(person_id): return military_role(index) == "officer" and not member_gone(index)
		return not member_gone(index) and (index == PLAYER_MEMBER or is_member(index)))

## Who exercises `duty_id` for this team now: {ok, decider, position_id, acting, ...}.
func duty_resolve(duty_id: String, read_only: bool = false) -> Dictionary:
	if not read_only:
		team_offices()
		var head := combat_identity(current_commander) if current_commander >= 0 and command_eligible(current_commander) else -1
		return SiteOffices.resolve(offices, duty_id, head, office_holder_ok, acting_commander >= 0)
	var current := team_offices(true)
	if current.is_empty():
		return {"ok": false, "code": "INVALID_OFFICES", "duty_id": duty_id, "decider": -1,
			"message": "原隊伍職位資料不符合契約"}
	var head := -1
	if current_commander >= 0 and base_command_eligible(current_commander):
		var identity := combat_identity(current_commander)
		var seat := SiteOffices.position_of(current, identity)
		if current_commander == formal_commander or not seat.is_empty() and not bool(seat.head):
			head = identity
	return SiteOffices.resolve(current, duty_id, head, func(person_id: int) -> bool:
		var index := index_for_identity(person_id)
		if index < 0: return false
		var seat := SiteOffices.position_of(current, person_id)
		if not seat.is_empty() and SiteOffices.needs_officer(current, seat): return base_command_eligible(index)
		return _member_can_serve(index), acting_commander >= 0)

func duty_decider(duty_id: String) -> int:
	var resolved := duty_resolve(duty_id)
	return int(resolved.decider) if bool(resolved.ok) else -1

## Shared refusal (or {}) for an entry that requires `duty_id`.
func duty_authority(duty_id: String, requester_id: int) -> Dictionary:
	var resolved := duty_resolve(duty_id)
	if bool(resolved.ok) and int(resolved.decider) == requester_id and requester_id > 0: return {}
	return SiteOffices.refusal(resolved, requester_id, offices)

## Organization adjustment is the head's own power, not a duty (3.5): only the
## present formal commander, stopped and out of combat like reorder_officers.
func apply_office_plan(requester_id: int, expected_revision: int, ops: Array) -> Dictionary:
	if is_inside_tree() and get_tree().paused: return SiteRuntime.fail("BUSY")
	if not garrison_feature_id.is_empty(): return SiteRuntime.fail("NO_AUTHORITY", "駐營兵員須先編成")
	_command_dirty = true
	settle_combat_command()
	team_offices()
	var requester := index_for_identity(requester_id)
	if requester < 0 or requester != formal_commander or requester != current_commander or not command_eligible(requester):
		return SiteRuntime.fail("NO_AUTHORITY", "只有在場正式隊長可調整本隊職位")
	if moving_member_count() > 0 or (is_instance_valid(player_member) and player_member.is_moving()) or float(data.site.get("combat_left", 0.0)) > 0.0 or combat_order != CombatOrder.HOLD or is_sustain_routed():
		return SiteRuntime.fail("BUSY", "須於停止且脫戰時調整職位")
	# Two-phase (v2 §3.5): rank changes in the same plan are checked on a virtual
	# role map first; posts are validated against the final ranks; then both commit.
	var roles := {}
	var office_ops: Array = []
	for op: Variant in ops:
		if op is Dictionary and str(op.get("op", "")) == "set_role":
			var role_index := index_for_identity(int(op.get("person_id", -1)))
			var wanted := str(op.get("role", ""))
			if role_index < 0 or role_index == PLAYER_MEMBER or wanted not in ["officer", "soldier", "civilian"] or not is_member(role_index) or member_gone(role_index):
				return SiteRuntime.fail("INVALID_ROLE", "軍職變更須為本隊原成員")
			roles[role_index] = wanted
		else:
			office_ops.append(op)
	var role_of := func(index: int) -> String: return str(roles.get(index, military_role(index)))
	var candidate := func(person_id: int, office_class: String) -> bool:
		var index := index_for_identity(person_id)
		if index < 0 or index == formal_commander or member_gone(index) or index != PLAYER_MEMBER and not is_member(index): return false
		return office_class != "military" or role_of.call(index) == "officer"
	var result := SiteOffices.apply_plan(offices, "team", expected_revision, office_ops, candidate, false) if not office_ops.is_empty() \
		else {"ok": true, "offices": offices.duplicate(true), "refs": {}}
	if not bool(result.ok): return result
	for role_index: int in roles:
		var seat := SiteOffices.position_of(result.offices, combat_identity(role_index))
		if str(roles[role_index]) != "officer" and (role_index in [formal_commander, acting_commander, current_commander] \
			or not seat.is_empty() and SiteOffices.needs_officer(result.offices, seat) or seat.is_empty() and officer_service.has(role_index)):
			return SiteRuntime.fail("HAS_APPOINTMENT", "最終方案中此人仍需軍官資格（隊長、武官職位或幹部）")
	# Commit: ranks, then posts; the cadre projection and settle follow once.
	for role_index: int in roles:
		if role_index == PLAYER_MEMBER: player_member.military_role = str(roles[role_index])
		else: combat_units[role_index].military_role = str(roles[role_index])
		if str(roles[role_index]) == "officer": _ensure_command_abilities(role_index)
	if not office_ops.is_empty():
		_record_dismissals(offices, result.offices, requester_id)
		offices = result.offices
	else: offices.revision = int(offices.revision) + 1
	_sync_officer_order()
	_mark_serving_dirty()
	_command_dirty = true
	settle_combat_command()
	return SiteRuntime.ok("已套用本隊人事方案", {"revision": int(offices.revision), "refs": result.refs})

func set_duty_ai_enabled(requester_id: int, enabled: bool) -> Dictionary:
	team_offices()
	var requester := index_for_identity(requester_id)
	if requester < 0 or requester != formal_commander or requester != current_commander or not command_eligible(requester):
		return SiteRuntime.fail("NO_AUTHORITY", "職責 AI 開關屬首長的組織設定")
	offices.duty_ai = enabled
	return SiteRuntime.ok("已%s本隊職責 AI" % ("開啟" if enabled else "關閉"))

func record_duty_trace(trace: Dictionary) -> void:
	duty_traces.append(trace)
	while duty_traces.size() > 64: duty_traces.pop_front()

## R1b auto-appointment (user decision 2026-10-07, fixed behavior): an officer
## who becomes cadre or is promoted, and every officer of a save made before R1b,
## takes a vacant non-head 武官 seat that holds duties, so acting and succession
## work as before. Seats needing a 武官 (訓練) fill first, then position order.
## Never refills a seat the head emptied later; officers beyond the free seats
## stay unseated (no command rights) until the head appoints them.
func _auto_seat_officers(indices: Array[int], all_role_officers: bool = false) -> void:
	team_offices()
	var queue: Array[int] = []
	for index: int in indices:
		if not queue.has(index): queue.append(index)
	if all_role_officers:
		var extra: Array[int] = []
		for index: int in combat_units.size():
			if is_member(index) and not queue.has(index) and military_role(index) == "officer": extra.append(index)
		extra.sort_custom(func(a: int, b: int) -> bool: return combat_identity(a) < combat_identity(b))
		queue.append_array(extra)
	var changed := false
	for index: int in queue:
		var identity := combat_identity(index)
		if index == formal_commander or identity <= 0 or member_gone(index) or military_role(index) != "officer" \
			or not SiteOffices.position_of(offices, identity).is_empty():
			continue
		var free := {}
		for wanted_military_duty: bool in [true, false]:
			for seat: Dictionary in offices.positions:
				if bool(seat.head) or int(seat.holder) > 0 or str(seat.get("office_class", "military")) != "military": continue
				var duties := SiteOffices.duties_of_position(offices, str(seat.id))
				if duties.is_empty(): continue
				var needs_military := false
				for duty_id: String in duties: needs_military = needs_military or SiteOffices.MILITARY_DUTIES.has(duty_id)
				if needs_military == wanted_military_duty:
					free = seat
					break
			if not free.is_empty(): break
		if free.is_empty(): break
		_ensure_command_abilities(index)
		free["holder"] = identity
		changed = true
	if changed:
		offices.revision = int(offices.revision) + 1
		_project_cadre()
		_mark_serving_dirty()

func _capture_offices() -> Dictionary:
	# Always saved, so a read that first materializes the default (any duty
	# check) never makes two snapshots of an unchanged team differ.
	return team_offices().duplicate(true)

func _short_translation_deployment_plan(
	goal: Vector2i, anchor: Vector2i, final_facing: Vector2i, path: Array[Vector2i],
	member_ids: Array[int], serial: int, registry: Object, profile: Object
) -> CombatDeploymentPlan:
	# A one-cell command can preserve each person's place in the formation.
	# Every edge is checked before replacing the old destination leases.
	if _coordinator == null or not command_reference_valid or goal != anchor \
		or not (goal - Vector2i(command_reference.floor()) in TerrainData.DIRECTIONS) \
		or not _combat_batch_members.is_empty() or not _reserved_cells.is_empty():
		return null
	var step: Vector2i = goal - Vector2i(command_reference.floor())
	var footprint: Dictionary = FormationDestinationPlanner.build_platform_footprint(data, anchor, path, FormationDestinationPlanner.MAX_PLATFORM_RADIUS, profile)
	var platform_cells: Array = footprint.get("platform_cells", [])
	var other_claims: Dictionary = {}
	for other in _coordinator.get_active_formations():
		if other == self or not ("data" in other) or other.data != data:
			continue
		if other.has_method("get_active_members_occupancy"):
			for occupied: Vector2i in other.get_active_members_occupancy().values():
				other_claims[occupied] = true
		if other.has_method("get_active_movement_claims"):
			for claimed: Vector2i in other.get_active_movement_claims().keys():
				other_claims[claimed] = true
	var active_indices: Dictionary = {}
	for mid in member_ids:
		var index := index_for_identity(mid)
		if index < 0 or is_controlled_person(index) or not combat_can_act(index) \
			or moving_to[index] != INVALID_CELL or _cell_owners.get(cells[index], -1) != index:
			return null
		active_indices[index] = true
	for mid in member_ids:
		var index := index_for_identity(mid)
		var target: Vector2i = cells[index] + step
		var occupant: int = int(_cell_owners.get(target, -1))
		if not platform_cells.has(target) or not FormationTransitPlanner._can_profile_step(data, cells[index], target, profile) \
			or _is_external_cell(target) or other_claims.has(target) \
			or (registry != null and registry.is_slot_reserved(target, team_id)) \
			or (occupant >= 0 and not active_indices.has(occupant)):
			return null
	var plan := CombatDeploymentPlan.new()
	plan.formation_id = team_id
	plan.order_serial = serial
	plan.resolved_anchor = anchor
	plan.terrain_revision = data.navigation_revision
	plan.shape_version = 2
	plan.formation_preset_id = "auto"
	plan.final_facing = final_facing
	plan.requested_count = member_ids.size()
	plan.structural_platform_capacity = platform_cells.size()
	plan.available_platform_capacity = platform_cells.size()
	plan.ingress_cell = footprint.get("ingress_cell", anchor)
	for cell: Vector2i in platform_cells:
		plan.platform_footprint.append(cell)
	for mid in member_ids:
		var index := index_for_identity(mid)
		var target: Vector2i = cells[index] + step
		plan.platform_slots.append(target)
		plan.member_role_map[mid] = CombatMovementTypes.CombatDestinationRole.PLATFORM
		plan.member_slot_map[mid] = target
		plan.slot_owner_map[target] = mid
		plan.pending_platform_member_ids.append(mid)
		plan.slot_tactical_roles[target] = CombatMovementTypes.TacticalSlotRole.COMMANDER if index == current_commander else (CombatMovementTypes.TacticalSlotRole.OFFICER if officer_order.has(index) else CombatMovementTypes.TacticalSlotRole.FLEX)
	var side := Vector2i(-final_facing.y, final_facing.x)
	var lateral_columns: Dictionary = {}
	for cell in plan.platform_slots:
		lateral_columns[(cell.x - anchor.x) * side.x + (cell.y - anchor.y) * side.y] = true
	plan.final_width = mini(10, maxi(1, lateral_columns.size()))
	plan.final_depth = ceili(float(plan.platform_slots.size()) / float(plan.final_width))
	return plan

func _deployment_blocked_cells(candidates: Array[Vector2i], active_ids: Array[int]) -> Dictionary:
	var blocked: Dictionary = {}
	if _coordinator != null:
		for other in _coordinator.get_active_formations():
			if other == self or not ("data" in other) or other.data != data:
				continue
			if other.has_method("get_active_members_occupancy"):
				for cell: Vector2i in other.get_active_members_occupancy().values():
					blocked[cell] = true
			if other.has_method("get_active_movement_claims"):
				for cell: Vector2i in other.get_active_movement_claims().keys():
					blocked[cell] = true
	for index in range(combat_units.size()):
		if not active_ids.has(combat_identity(index)) and _cell_owners.get(cells[index], -1) == index:
			blocked[cells[index]] = true
	for cell: Vector2i in candidates:
		if _is_external_cell(cell):
			blocked[cell] = true
	return blocked

static func _prepare_combat_move_route(map: TerrainData, start: Vector2i, anchor: Vector2i, requested_facing: Vector2i, fallback_facing: Vector2i, profile: Object) -> Dictionary:
	var path: Array[Vector2i] = FormationTransitPlanner.build_macro_path(map, start, anchor, profile)
	if path.is_empty():
		return SiteRuntime.fail("BLOCKED", "未找到前往目標的宏觀路徑")
	var resolved_facing: Vector2i = requested_facing
	if resolved_facing == Vector2i.ZERO:
		for path_index in range(path.size() - 1, 0, -1):
			resolved_facing = path[path_index] - path[path_index - 1]
			if resolved_facing != Vector2i.ZERO: break
		if resolved_facing == Vector2i.ZERO: resolved_facing = fallback_facing
	if resolved_facing not in TerrainData.DIRECTIONS:
		return SiteRuntime.fail("INVALID_ORDER", "部署面向須為四個正方向之一")
	return {"ok": true, "path": path, "facing": resolved_facing}

static func _prepare_combat_move_destination(map: TerrainData, formation_id: int, serial: int, anchor: Vector2i, path: Array[Vector2i], active_mids: Array[int], registry: Object, officers: Array[int], occupancy: Dictionary, final_facing: Vector2i, profile: Object, preset: String, blocker_query: Callable) -> CombatDeploymentPlan:
	var footprint: Dictionary = FormationDestinationPlanner.build_platform_footprint(map, anchor, path, FormationDestinationPlanner.preset_footprint_radius(preset, active_mids.size()), profile)
	var candidates: Array[Vector2i] = []
	candidates.assign(footprint.get("platform_cells", []))
	candidates.append_array(path)
	if preset != "auto": candidates.append_array(FormationDestinationPlanner.shape_slots(preset, active_mids.size(), anchor, final_facing))
	var blocked: Dictionary = blocker_query.call(candidates, active_mids)
	return FormationDestinationPlanner.plan_deployment(formation_id, serial, map, anchor, path, active_mids, registry, officers, occupancy, final_facing, profile, preset, blocked)

func _preflight_combat_move(goal: Vector2i, requested_facing: Vector2i, serial: int, preset_id: String = "") -> Dictionary:
	if _team_ship_activity(): return SiteRuntime.fail("EMBARKED", "乘載或船岸作業中不能執行地面軍令")
	if not combat_enabled or data == null:
		return SiteRuntime.fail("NO_TARGET")
	if role != "combat" and not preset_id.is_empty():
		return SiteRuntime.fail("INVALID_ORDER", "只有戰鬥隊伍可選擇陣型")
	var selected_preset := formation_preset_id if preset_id.is_empty() else preset_id
	if not FormationDestinationPlanner.is_valid_preset(selected_preset):
		return SiteRuntime.fail("INVALID_ORDER", "未知陣型")
	if is_sustain_routed():
		return SiteRuntime.fail("ROUTED", "隊伍尚未完成安全整補與重新集結")
	var active_mids := _get_active_member_ids()
	if active_mids.is_empty():
		return SiteRuntime.fail("NO_TARGET", "隊伍無有效成員")
	var profile := FormationMovementProfile.from_members(active_mids, self)
	var resolved := _resolve_combat_goal(goal, profile)
	if not resolved.get("ok", false):
		return SiteRuntime.fail("BLOCKED", "目的地不是合法空地")
	var anchor: Vector2i = resolved["cell"]
	var macro_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var fallback_facing := facing[current_commander] if current_commander >= 0 and current_commander < facing.size() else Vector2i.ZERO
	var route := _prepare_combat_move_route(data, _get_combat_route_anchor_cell(), anchor, requested_facing, fallback_facing, profile)
	if combat_profile_enabled: _profile_combat_stage("order_macro_path", macro_started)
	if not bool(route.ok): return route
	var path: Array[Vector2i] = route.path
	var resolved_facing: Vector2i = route.facing
	var registry: Object = _coordinator.deployment_registry if _coordinator != null and "deployment_registry" in _coordinator else null
	var preferred_officers: Array[int] = []
	if is_member(current_commander):
		preferred_officers.append(combat_identity(current_commander))
	for officer_index in officer_order:
		if is_member(officer_index) and not preferred_officers.has(combat_identity(officer_index)):
			preferred_officers.append(combat_identity(officer_index))
	var allow_short_translation := selected_preset == "auto" and (_combat_deployment_plan == null or (_combat_deployment_plan.formation_preset_id == "auto" and _combat_deployment_plan.final_facing == resolved_facing))
	var deployment_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var plan := _short_translation_deployment_plan(goal, anchor, resolved_facing, path, active_mids, serial, registry, profile) if allow_short_translation else null
	var short_translation := plan != null
	if plan == null:
		plan = _prepare_combat_move_destination(data, team_id, serial, anchor, path, active_mids, registry, preferred_officers, get_active_members_occupancy(), resolved_facing, profile, selected_preset, _deployment_blocked_cells)
	if combat_profile_enabled: _profile_combat_stage("order_deployment", deployment_started)
	if plan == null:
		return SiteRuntime.fail("INSUFFICIENT_SPACE", "目的地空間不足以部署")
	# Platform and approach-queue slots are both final places. A destination whose
	# walkable footprint plus its queue cannot give every active member a slot is
	# refused here. Followers created only by temporary blocking (other people,
	# leases) on a large-enough footprint stay valid and wait (WAIT_SPACE).
	if plan.structural_platform_capacity + plan.queue_capacity < active_mids.size():
		return SiteRuntime.fail("INSUFFICIENT_SPACE", "目的地空間不足以部署")
	plan.terrain_revision = data.navigation_revision
	if selected_preset != "auto":
		var other_claims: Dictionary = {}
		if _coordinator != null:
			for other in _coordinator.get_active_formations():
				if other == self or not ("data" in other) or other.data != data:
					continue
				if other.has_method("get_active_members_occupancy"):
					for occupied: Vector2i in other.get_active_members_occupancy().values():
						other_claims[occupied] = true
				if other.has_method("get_active_movement_claims"):
					for claimed: Vector2i in other.get_active_movement_claims().keys():
						other_claims[claimed] = true
		var participants: Dictionary = {}
		for mid in active_mids:
			participants[index_for_identity(mid)] = true
		for slot: Vector2i in plan.platform_slots:
			var occupant: int = int(_cell_owners.get(slot, -1))
			var claim_owner: int = int(_reserved_cells.get(slot, -1))
			if _is_external_cell(slot) or other_claims.has(slot) or (occupant >= 0 and not participants.has(occupant)):
				return SiteRuntime.fail("BLOCKED", "陣型格位已被其他人物或車輛占用")
			if occupant >= 0 and is_controlled_person(occupant) and plan.get_slot_for_member(combat_identity(occupant)) != slot:
				return SiteRuntime.fail("BLOCKED", "受控隊員須先移開或站到自己的陣型格位")
			if claim_owner >= 0 and (not participants.has(claim_owner) or (is_controlled_person(claim_owner) and plan.get_slot_for_member(combat_identity(claim_owner)) != slot)):
				return SiteRuntime.fail("BLOCKED", "陣型格位已有其他隊員的在途移動")
	for slot: Vector2i in plan.member_slot_map.values():
		if registry != null and registry.is_slot_reserved(slot, team_id):
			return SiteRuntime.fail("RESERVATION_CONFLICT", "目的地槽位衝突")
	return {"ok": true, "anchor": anchor, "facing": resolved_facing, "path": path, "plan": plan, "profile": profile, "short_translation": short_translation, "preset_id": selected_preset}

## Pure projections for the existing Crowd -> ordinary owner handoff. The caller
## supplies final cells and owns the all-person placement/transaction boundary.
static func _handoff_actor(snapshot: Dictionary, actor_states: Dictionary) -> Dictionary:
	var identity: int = int(snapshot.get("player_member", {}).get("id", -1))
	var actor: Variant = actor_states.get(identity, {})
	return actor if actor is Dictionary else {}

static func _handoff_row_can_act(row: Dictionary) -> bool:
	return float(row.get("hp", 0.0)) > 0.0 and float(row.get("ko", 0.0)) <= 0.0 \
		and str(row.get("pose", "")) != "get_up" and not bool(row.get("captive", false)) \
		and not bool(row.get("departed", false)) and not bool(row.get("site_exited", false)) and not bool(row.get("surrender_pending", false))

static func _handoff_actor_can_act(actor: Dictionary) -> bool:
	return not actor.is_empty() and float(actor.get("hp", 0.0)) > 0.0 and float(actor.get("knockout_left", 0.0)) <= 0.0 \
		and not bool(actor.get("captive", false)) and not bool(actor.get("_getting_up", false)) \
		and not bool(actor.get("site_exited", false)) and not bool(actor.get("surrender_pending", false))

static func _handoff_route_anchor(snapshot: Dictionary, map: TerrainData, actor: Dictionary) -> Vector2i:
	var current: int = int(snapshot.get("current_commander", -1))
	if _combat_saved_eligible(snapshot, current, actor):
		var saved: Array = actor.cell if current == PLAYER_MEMBER else snapshot.units[current].cell
		var cell := Vector2i(int(saved[0]), int(saved[1]))
		if map.is_walkable(cell): return cell
	var total := Vector2i.ZERO
	var count := 0
	for row: Dictionary in snapshot.units:
		if bool(row.get("member", true)) and _handoff_row_can_act(row) and not bool(row.get("dead", false)):
			total += Vector2i(int(row.cell[0]), int(row.cell[1]))
			count += 1
	var medoid: Vector2i = Vector2i(roundi(float(total.x) / float(count)), roundi(float(total.y) / float(count))) if count > 0 else (Vector2i(floori(float(snapshot.reference[0])), floori(float(snapshot.reference[1]))) if bool(snapshot.command_reference_valid) else Vector2i.ZERO)
	if map.is_walkable(medoid): return medoid
	for radius in range(1, 4):
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var candidate: Vector2i = medoid + direction * radius
			if map.contains(candidate) and map.is_walkable(candidate): return candidate
	return medoid

static func prepare_handoff_geometry(snapshot: Dictionary, map: TerrainData, actor_states: Dictionary) -> Dictionary:
	if map == null or not snapshot.get("units") is Array or snapshot.units.is_empty():
		return SiteRuntime.fail("INVALID", "收兵名冊或地形不存在")
	var result: Dictionary = snapshot.duplicate(true)
	var actor: Dictionary = _handoff_actor(result, actor_states)
	if not result.get("player_member", {}).is_empty() and actor.is_empty():
		return SiteRuntime.fail("INVALID", "收兵隊員 Actor 缺少原人物快照")
	var positions: Array[Vector2] = []
	var identities: Array[int] = []
	for row: Dictionary in result.units:
		if not TerrainTestCharacter._saved_cell(row.get("cell"), map):
			return SiteRuntime.fail("INVALID", "收兵人物格位不合法")
		if bool(row.get("member", true)) and float(row.hp) > 0.0 and not bool(row.get("departed", false)) and not bool(row.get("captive", false)):
			positions.append(Vector2(float(row.cell[0]) + 0.5, float(row.cell[1]) + 0.5))
			identities.append(int(row.person_id))
	if not actor.is_empty() and float(actor.hp) > 0.0 and not bool(actor.captive):
		positions.append(Vector2(float(actor.position[0]), float(actor.position[1])) / TerrainRenderer.CELL_PIXELS)
		identities.append(int(actor.person_id))
	result["command_reference_valid"] = not positions.is_empty()
	var reference := Vector2(float(result.reference[0]), float(result.reference[1]))
	if bool(result.command_reference_valid):
		reference = _command_reference_from_positions(positions, identities)
		result["reference"] = [reference.x, reference.y]
	for row: Dictionary in result.units:
		var radius: float = float(result.command_radius) + (2.0 if bool(row.get("present", false)) else 0.0)
		var member_position := Vector2(float(row.cell[0]) + 0.5, float(row.cell[1]) + 0.5)
		row.present = bool(row.get("member", true)) and bool(result.command_reference_valid) and _handoff_row_can_act(row) and reference.distance_to(member_position) <= radius
	if not actor.is_empty():
		var radius: float = float(result.command_radius) + (2.0 if bool(result.player_member.present) else 0.0)
		var actor_position := Vector2(float(actor.position[0]), float(actor.position[1])) / TerrainRenderer.CELL_PIXELS
		result.player_member.present = bool(result.command_reference_valid) and _handoff_actor_can_act(actor) and reference.distance_to(actor_position) <= radius
	var formal: int = int(result.formal_commander)
	var acting: int = int(result.acting_commander)
	var current: int = int(result.current_commander)
	if current >= 0 and not _combat_saved_eligible(result, current, actor):
		return SiteRuntime.fail("PRESENCE_CONFLICT", "收兵配置使原指揮者不在有效指揮範圍")
	if acting >= 0 and (formal < 0 or acting == formal or current != acting or _combat_saved_eligible(result, formal, actor)):
		return SiteRuntime.fail("PRESENCE_CONFLICT", "收兵配置與原代理指揮關係不一致")
	if acting < 0 and current != (formal if _combat_saved_eligible(result, formal, actor) else -1):
		return SiteRuntime.fail("PRESENCE_CONFLICT", "收兵配置不可重新選擇指揮者")
	if current < 0 and (not bool(result.needs_attack_order) or bool(result.combat_attacking) or int(result.combat_order) not in [CombatOrder.HOLD, CombatOrder.RETREAT]):
		return SiteRuntime.fail("PRESENCE_CONFLICT", "收兵配置沒有原命令所需的有效指揮者")
	return {"ok": true, "snapshot": result, "anchor": _handoff_route_anchor(result, map, actor)}

## The caller already placed every person legally. Preserve that complete cell
## set while making the original commander relation valid; never elect a new one.
static func prepare_handoff_presence(snapshot: Dictionary, map: TerrainData, actor_states: Dictionary,
		fixed_cells: Dictionary, guarded_ids: Dictionary, original_positions: Dictionary,
		components: Dictionary = {}) -> Dictionary:
	var original: Dictionary = prepare_handoff_geometry(snapshot, map, actor_states)
	original["relocations"] = []
	original["presence_attempts"] = 0
	if original.ok or str(original.get("code", "")) != "PRESENCE_CONFLICT": return original
	var current: int = int(snapshot.current_commander)
	var formal: int = int(snapshot.formal_commander)
	var movable: Array[int] = []
	for index in range(snapshot.units.size()):
		var row: Dictionary = snapshot.units[index]
		if not _handoff_row_can_act(row) or not bool(row.get("member", true)) or guarded_ids.has(int(row.person_id)):
			continue
		if not original_positions.has(int(row.person_id)): continue
		movable.append(index)
	var pairs: Array[Vector2i] = []
	if current != formal and movable.has(current) and movable.has(formal): pairs.append(Vector2i(current, formal))
	for commander: int in [current, formal]:
		if not movable.has(commander): continue
		for other: int in movable:
			if other == commander: continue
			var pair := Vector2i(mini(commander, other), maxi(commander, other))
			if pairs.has(pair) or pairs.has(Vector2i(pair.y, pair.x)): continue
			pairs.append(pair)
	for pair: Vector2i in pairs:
		var left: Dictionary = snapshot.units[pair.x]
		var right: Dictionary = snapshot.units[pair.y]
		var left_cell := Vector2i(int(left.cell[0]), int(left.cell[1]))
		var right_cell := Vector2i(int(right.cell[0]), int(right.cell[1]))
		var left_source := Vector2i((original_positions[int(left.person_id)] as Vector2).floor())
		var right_source := Vector2i((original_positions[int(right.person_id)] as Vector2).floor())
		if not _handoff_presence_reachable(map, left_source, right_cell, fixed_cells, components) \
			or not _handoff_presence_reachable(map, right_source, left_cell, fixed_cells, components): continue
		var candidate: Dictionary = _handoff_presence_candidate(snapshot, map, actor_states, pair)
		original.presence_attempts += 1
		if candidate.ok:
			candidate["presence_attempts"] = original.presence_attempts
			return candidate
	# ponytail: one same-team swap only; larger placement changes remain BUSY.
	return original

static func _handoff_presence_candidate(snapshot: Dictionary, map: TerrainData, actor_states: Dictionary, pair: Vector2i) -> Dictionary:
	var candidate: Dictionary = snapshot.duplicate(true)
	for key: String in ["cell", "slot", "crowd_position"]:
		var saved: Variant = candidate.units[pair.x].get(key)
		candidate.units[pair.x][key] = candidate.units[pair.y].get(key)
		candidate.units[pair.y][key] = saved
	var result: Dictionary = prepare_handoff_geometry(candidate, map, actor_states)
	if not result.ok: return result
	var relocations: Array = []
	for index: int in [pair.x, pair.y]:
		var row: Dictionary = result.snapshot.units[index]
		relocations.append({"index": index, "person_id": int(row.person_id),
			"before": snapshot.units[index].cell.duplicate(), "cell": row.cell.duplicate()})
	result["relocations"] = relocations
	return result

static func _handoff_presence_reachable(map: TerrainData, source: Vector2i, target: Vector2i,
		fixed: Dictionary, components: Dictionary) -> bool:
	if not map.is_walkable(source) or not map.is_walkable(target) or fixed.has(target): return false
	if not components.has(target):
		var label: int = components.size()
		var pending: Array[Vector2i] = [target]
		components[target] = label
		var head: int = 0
		while head < pending.size():
			var cell: Vector2i = pending[head]
			head += 1
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next: Vector2i = cell + direction
				if components.has(next) or fixed.has(next) or not map.can_step(cell, next): continue
				components[next] = label
				pending.append(next)
	if components.get(source, -1) == components[target]: return true
	# Original layout permits a person to leave a foreign claimed source cell;
	# it may not enter or cross another fixed cell.
	if fixed.has(source):
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next: Vector2i = source + direction
			if components.get(next, -1) == components[target] and map.can_step(source, next): return true
	return false

static func prepare_handoff_move(snapshot: Dictionary, map: TerrainData, actor_states: Dictionary, blocked_cells: Dictionary, registry: SiteDeploymentReservationRegistry, controlled_person_id: int = -1) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	if int(result.get("combat_order", CombatOrder.HOLD)) != CombatOrder.MOVE:
		return {"ok": true, "snapshot": result}
	if map == null or not result.get("units") is Array or result.units.is_empty():
		return SiteRuntime.fail("INVALID", "收兵 MOVE 缺少原名冊或地形")
	var preset: String = str(result.get("formation_preset_id", "auto"))
	if not FormationDestinationPlanner.is_valid_preset(preset): return SiteRuntime.fail("INVALID_ORDER", "收兵陣型意圖無效")
	var actor: Dictionary = _handoff_actor(result, actor_states)
	var member_cells: Dictionary = {}
	var occupancy: Dictionary = {}
	var active_mids: Array[int] = []
	var blocked: Dictionary = blocked_cells.duplicate()
	var controlled_ids: Dictionary = {}
	for row: Dictionary in result.units:
		var identity: int = int(row.person_id)
		var cell := Vector2i(int(row.cell[0]), int(row.cell[1]))
		member_cells[identity] = cell
		var occupies: bool = float(row.hp) > 0.0 and float(row.ko) <= 0.0 and not bool(row.get("departed", false)) and not bool(row.get("site_exited", false))
		if occupies: occupancy[identity] = cell
		if bool(row.get("member", true)) and _handoff_row_can_act(row) and not bool(row.get("dead", false)):
			active_mids.append(identity)
			if identity == controlled_person_id: controlled_ids[identity] = true
		elif occupies:
			blocked[cell] = true
	# Actor members use their original independent movement owner. Their cells are
	# external blockers for ordinary Army slots, just like _is_external_cell.
	for saved_actor: Dictionary in actor_states.values():
		if float(saved_actor.hp) > 0.0 and float(saved_actor.knockout_left) <= 0.0 and not bool(saved_actor.get("site_exited", false)):
			blocked[Vector2i(int(saved_actor.cell[0]), int(saved_actor.cell[1]))] = true
	if active_mids.is_empty(): return SiteRuntime.fail("NO_TARGET", "收兵 MOVE 沒有可行動的原名冊成員")
	var profile: Object = FormationMovementProfile.from_members(active_mids, null)
	var goal := Vector2i(int(result.goal[0]), int(result.goal[1]))
	var resolved: Dictionary = _resolve_combat_goal_at(map, goal, func(cell: Vector2i) -> bool: return blocked.has(cell))
	if not bool(resolved.ok): return SiteRuntime.fail("BLOCKED", "收兵 MOVE 目的地沒有合法空地")
	var anchor: Vector2i = resolved.cell
	var start: Vector2i = _handoff_route_anchor(result, map, actor)
	var direction := Vector2i.ZERO
	if result.get("crowd_state") is Dictionary and result.crowd_state.has("goal_facing"):
		var continuous: Vector2 = Vector2.from_angle(float(result.crowd_state.goal_facing))
		direction = Vector2i(int(signf(continuous.x)), 0) if absf(continuous.x) > absf(continuous.y) else Vector2i(0, int(signf(continuous.y)))
	elif result.get("combat_deployment_plan") is Dictionary:
		var saved: Array = result.combat_deployment_plan.get("final_facing", [0, 0])
		direction = Vector2i(int(saved[0]), int(saved[1]))
	var fallback := Vector2i.RIGHT
	var current: int = int(result.current_commander)
	if current == PLAYER_MEMBER and not actor.is_empty(): fallback = Vector2i(int(actor.facing[0]), int(actor.facing[1]))
	elif current >= 0 and current < result.units.size(): fallback = Vector2i(int(result.units[current].facing[0]), int(result.units[current].facing[1]))
	var route: Dictionary = _prepare_combat_move_route(map, start, anchor, direction, fallback, profile)
	if not bool(route.ok): return route
	var path: Array[Vector2i] = route.path
	var final_facing: Vector2i = route.facing
	var officers: Array[int] = []
	for index: Variant in [current] + result.get("officers", []):
		var identity := -1
		if int(index) == PLAYER_MEMBER and not actor.is_empty(): identity = int(actor.person_id)
		elif int(index) >= 0 and int(index) < result.units.size() and bool(result.units[int(index)].get("member", true)): identity = int(result.units[int(index)].person_id)
		if identity >= 1 and not officers.has(identity): officers.append(identity)
	var serial: int = maxi(1, int(result.get("combat_order_serial", 1)))
	var team: int = int(result.team_id)
	var plan: CombatDeploymentPlan = _prepare_combat_move_destination(map, team, serial, anchor, path, active_mids, registry, officers, occupancy, final_facing, profile, preset, func(_candidates: Array[Vector2i], _members: Array[int]) -> Dictionary: return blocked)
	if plan == null: return SiteRuntime.fail("INSUFFICIENT_SPACE", "收兵 MOVE 無法建立原部署計畫")
	plan.terrain_revision = int(map.navigation_revision)
	for mid: int in plan.member_slot_map:
		var slot: Vector2i = plan.member_slot_map[mid]
		if not map.is_walkable(slot) or blocked.has(slot) or registry != null and registry.is_slot_reserved(slot, team):
			return SiteRuntime.fail("RESERVATION_CONFLICT", "收兵 MOVE 部署格與其他人物或租約衝突")
		if preset != "auto" and controlled_ids.has(mid) and member_cells[mid] != slot:
			return SiteRuntime.fail("CONTROLLED_SLOT_CONFLICT", "受控隊員須保留原位置，不能由收兵代走陣型格")
	var exit_k: int = _find_contiguous_egress_cursor_at(map, path, occupancy, start)
	var search: CombatMovementTypes.EgressSearchState = _new_egress_search_state(team, serial, int(map.navigation_revision), path, exit_k, occupancy)
	# Finite Site bound. The ordinary owner uses the identical resumable search;
	# the synchronous handoff must finish this preparation before publishing.
	_advance_egress_distance_search(map, search, profile, maxi(4096, map.size.x * map.size.y * 4))
	if not search.completed: return SiteRuntime.fail("SEARCH_LIMIT", "收兵 MOVE 出列排序搜尋尚未完成")
	var prepared := {"anchor": anchor, "path": path, "plan": plan, "profile": profile, "short_translation": false}
	var move: CombatMovePlan = _build_combat_move_plan(map, team, serial, goal, prepared, active_mids, member_cells, start, search.distances, exit_k, {}, controlled_ids)
	result["combat_order_serial"] = serial
	result["combat_deployment_plan"] = _serialize_deployment_plan(plan)
	result["combat_move_plan"] = _serialize_move_plan(move)
	for row: Dictionary in result.units: row.slot = row.cell.duplicate()
	if not result.get("player_member", {}).is_empty(): result.player_member.goal = result.goal.duplicate()
	# These derived initial transit fields deliberately are not in the disk schema.
	# Keep this original-owner plan through the synchronous handoff instead of
	# losing its BFS egress order in an ordinary save round trip.
	return {"ok": true, "snapshot": result, "runtime_move": move}

static func _handoff_move_signature(move: CombatMovePlan) -> String:
	return JSON.stringify({"move": _serialize_move_plan(move), "deployment": _serialize_deployment_plan(move.destination_plan),
		"sequence": move.member_sequence_rank, "staging": move.pre_route_staging_slots,
		"path_s": move.member_path_s, "defer": move.member_defer_count, "profile": move.movement_profile_hash}).sha256_text()

static func preflight_handoff_restore(snapshot: Dictionary, map: TerrainData, registry: SiteDeploymentReservationRegistry = null, runtime_move: CombatMovePlan = null) -> Dictionary:
	if map == null or not snapshot.get("units") is Array or snapshot.units.is_empty(): return SiteRuntime.fail("INVALID", "收兵 restore 缺少原名冊或地形")
	if not SiteStore._valid_combat_movement_snapshot(map, snapshot, {}): return SiteRuntime.fail("RESTORE_LAYOUT", "收兵移動快照不符合原 schema")
	var deployment: CombatDeploymentPlan = null
	if snapshot.has("combat_deployment_plan"):
		deployment = _deserialize_deployment_plan(snapshot.combat_deployment_plan)
		for slot: Vector2i in deployment.member_slot_map.values():
			if not map.is_walkable(slot) or registry != null and registry.is_slot_reserved(slot, int(snapshot.team_id)):
				return SiteRuntime.fail("RESERVATION_CONFLICT", "收兵 restore 部署租約衝突")
		for slot: Vector2i in deployment.slot_lease_timers:
			if not map.is_walkable(slot) or registry != null and registry.is_slot_reserved(slot, int(snapshot.team_id)):
				return SiteRuntime.fail("RESERVATION_CONFLICT", "收兵 restore 保留租約衝突")
	if snapshot.has("combat_move_plan"):
		if deployment == null: return SiteRuntime.fail("RESTORE_LAYOUT", "收兵 MOVE 缺少原部署計畫")
		var movement: CombatMovePlan = _deserialize_move_plan(snapshot.combat_move_plan, deployment)
		var active_mids: Array[int] = []
		for row: Dictionary in snapshot.units:
			if bool(row.get("member", true)) and _handoff_row_can_act(row) and not bool(row.get("dead", false)): active_mids.append(int(row.person_id))
		var profile: Object = FormationMovementProfile.from_members(active_mids, null)
		if not FormationDestinationPlanner.refresh_derived_ingress(deployment, map, movement.macro_path, profile):
			return SiteRuntime.fail("RESTORE_LAYOUT", "收兵 MOVE 入口重建失敗；保留原命令")
	if runtime_move != null and (runtime_move.destination_plan == null or not snapshot.has("combat_move_plan") \
		or _serialize_move_plan(runtime_move) != snapshot.combat_move_plan or _serialize_deployment_plan(runtime_move.destination_plan) != snapshot.combat_deployment_plan):
		return SiteRuntime.fail("RESTORE_LAYOUT", "收兵 MOVE 暫態計畫與候選不一致")
	return {"ok": true, "snapshot_sha256": JSON.stringify(snapshot).sha256_text(), "navigation_revision": int(map.navigation_revision), "map_id": map.get_instance_id(),
		"runtime_move": runtime_move, "runtime_signature": _handoff_move_signature(runtime_move) if runtime_move != null else ""}

func restore_handoff_state(snapshot: Dictionary, map: TerrainData, restored_player: Variant, restored_npc: Variant, prepared: Dictionary) -> Dictionary:
	if not bool(prepared.get("ok", false)) or map == null or int(prepared.get("map_id", -1)) != map.get_instance_id() \
		or int(prepared.get("navigation_revision", -1)) != int(map.navigation_revision) or str(prepared.get("snapshot_sha256", "")) != JSON.stringify(snapshot).sha256_text():
		return SiteRuntime.fail("STALE_HANDOFF", "收兵候選已改變，未安裝普通 owner")
	var runtime_move: CombatMovePlan = prepared.get("runtime_move")
	if runtime_move != null and (runtime_move.destination_plan == null or str(prepared.get("runtime_signature", "")) != _handoff_move_signature(runtime_move)):
		return SiteRuntime.fail("STALE_HANDOFF", "收兵 MOVE 暫態候選已改變，未安裝普通 owner")
	# The Site transaction publishes all leases together after every Army exists.
	# Ordinary restore remains unchanged; only this synchronous handoff defers its
	# coordinator callbacks. The caller retains the original rows for rollback.
	var previous_coordinator: Object = _coordinator
	var previous_runtime: int = formation_runtime_id
	var previous_native: bool = native_hot_enabled
	_coordinator = null
	native_hot_enabled = false
	restore_combat_state(snapshot, map, restored_player, restored_npc)
	_coordinator = previous_coordinator
	formation_runtime_id = previous_runtime
	native_hot_enabled = previous_native
	set_process(false)
	if combat_order != int(snapshot.combat_order) or cells.size() != snapshot.units.size():
		return SiteRuntime.fail("RESTORE_MISMATCH", "收兵 restore 未保留原命令或人物數量")
	if snapshot.has("combat_move_plan") and (_combat_move_plan == null or _combat_deployment_plan == null):
		return SiteRuntime.fail("RESTORE_MISMATCH", "收兵 MOVE 計畫未成功還原")
	if runtime_move != null:
		_combat_move_plan = runtime_move
		_combat_deployment_plan = runtime_move.destination_plan
	return SiteRuntime.ok()

func preview_combat_move(goal: Vector2i, final_facing: Vector2i = Vector2i.ZERO, preset_id: String = "") -> Dictionary:
	var preflight := _preflight_combat_move(goal, final_facing, _current_order_serial + 1, preset_id)
	if not bool(preflight.get("ok", false)):
		return preflight
	var plan: CombatDeploymentPlan = preflight["plan"]
	var platform_slots: Array[Vector2i] = []
	var queue_slots: Array[Vector2i] = []
	var slot_facing: Dictionary = {}
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.member_slot_map[mid]
		if int(plan.member_role_map.get(mid, CombatMovementTypes.CombatDestinationRole.PLATFORM)) == CombatMovementTypes.CombatDestinationRole.PLATFORM:
			platform_slots.append(slot)
			slot_facing[slot] = plan.get_facing_for_slot(slot)
		else:
			queue_slots.append(slot)
	return SiteRuntime.ok("可部署", {
		"resolved_anchor": preflight["anchor"],
		"final_facing": preflight["facing"],
		"final_width": plan.final_width,
		"final_depth": plan.final_depth,
		"formation_preset_id": preflight["preset_id"],
		"platform_slots": platform_slots,
		"approach_queue_slots": queue_slots,
		"following_member_ids": plan.following_member_ids.duplicate(),
		"slot_facing": slot_facing,
	})

func _formation_change_target() -> Dictionary:
	var goal := combat_goal if combat_order == CombatOrder.MOVE and combat_goal != INVALID_CELL else _get_combat_route_anchor_cell()
	var direction := Vector2i.ZERO
	if _combat_deployment_plan != null:
		direction = _combat_deployment_plan.final_facing
		if combat_order == CombatOrder.HOLD and _combat_move_plan == null:
			goal = _combat_deployment_plan.resolved_anchor
	return {"goal": goal, "direction": direction}

func preview_formation_change(preset_id: String) -> Dictionary:
	if _team_ship_activity(): return SiteRuntime.fail("EMBARKED", "乘載或船岸作業中不能變更地面陣型")
	if role != "combat" or not FormationDestinationPlanner.is_valid_preset(preset_id):
		return SiteRuntime.fail("INVALID_ORDER", "陣型不合法")
	if (is_inside_tree() and get_tree().paused) or (data != null and bool(data.site.get("paused", false))) or is_sustain_routed() or combat_order in [CombatOrder.RETREAT, CombatOrder.RETURN]:
		return SiteRuntime.ok("可接受新陣型；待可行動時展開", {"formation_preset_id": preset_id, "pending": true})
	var target := _formation_change_target()
	var preview := preview_combat_move(target.goal, target.direction, preset_id)
	if not bool(preview.get("ok", false)):
		return SiteRuntime.ok("可接受新陣型；空間暫不足時等待", {"formation_preset_id": preset_id, "pending": true})
	return preview

func issue_formation_change(requester: int, preset_id: String) -> Dictionary:
	if _team_ship_activity(): return SiteRuntime.fail("EMBARKED", "乘載或船岸作業中不能變更地面陣型")
	if role != "combat" or not FormationDestinationPlanner.is_valid_preset(preset_id):
		return SiteRuntime.fail("INVALID_ORDER", "陣型不合法")
	var paused := (is_inside_tree() and get_tree().paused) or (data != null and bool(data.site.get("paused", false)))
	if not paused:
		_command_dirty = true
		settle_combat_command()
	if requester != current_commander or not command_eligible(requester):
		return SiteRuntime.fail("NO_AUTHORITY", "只有當前在場指揮者可下令")
	if formation_preset_id == preset_id and not _formation_change_pending and _combat_deployment_plan != null \
		and _combat_deployment_plan.formation_preset_id == preset_id and _combat_deployment_plan.terrain_revision == data.navigation_revision \
		and _combat_deployment_plan.requested_count == _get_active_member_ids().size() and _settled_deployment_leases_valid():
		return SiteRuntime.ok("已選擇此陣型")
	formation_preset_id = preset_id
	formation_intent_version = 1
	_formation_change_pending = true
	_formation_retry_seconds = 2.0
	if not _issuing_tactical_ai_order:
		_stop_tactical_ai()
	if not paused:
		_apply_pending_formation_change()
	return SiteRuntime.ok("已接受陣型；依原命令逐步展開" if _formation_change_pending else "已接受陣型並開始展開")

func _apply_pending_formation_change() -> void:
	if _team_ship_activity(): return
	if not _formation_change_pending or is_sustain_routed() or combat_order == CombatOrder.RETREAT or (is_inside_tree() and get_tree().paused) or (data != null and bool(data.site.get("paused", false))):
		return
	var target := _formation_change_target()
	if combat_order in [CombatOrder.HOLD, CombatOrder.MOVE]:
		var preserve_move := combat_order == CombatOrder.MOVE
		var old_origin := pursuit_origin
		var old_delay := _order_delay
		var old_elapsed := _command_elapsed
		var old_source := _corps_reposition_source.duplicate()
		var result := issue_combat_order(current_commander, CombatOrder.MOVE, target.goal, -1, target.direction, formation_preset_id)
		if bool(result.get("ok", false)):
			_formation_change_pending = false
			if preserve_move:
				pursuit_origin = old_origin
				_order_delay = old_delay
				_command_elapsed = old_elapsed
				_corps_reposition_source = old_source
		return
	if combat_order in [CombatOrder.ATTACK, CombatOrder.PURSUE, CombatOrder.RETURN]:
		var preflight := _preflight_combat_move(target.goal, target.direction, _current_order_serial + 1, formation_preset_id)
		if not bool(preflight.get("ok", false)):
			return
		var plan: CombatDeploymentPlan = preflight.plan
		if not plan.following_member_ids.is_empty():
			return # Keep the tactical order until a full safe physical rearrangement is possible.
		var registry: Object = _coordinator.deployment_registry if _coordinator != null and "deployment_registry" in _coordinator else null
		if registry != null:
			var slots: Array[Vector2i] = []
			slots.assign(plan.member_slot_map.values())
			var old_serial := _combat_deployment_plan.order_serial if _combat_deployment_plan != null else (get_order_serial() if not _suppress_approaches.is_empty() or not _fire_navigation.is_empty() else 0)
			if not bool(registry.try_replace_reservations(team_id, old_serial, plan.order_serial, slots).get("ok", false)):
				return
		_current_order_serial = plan.order_serial
		_combat_deployment_plan = plan
		for mid: int in plan.member_slot_map.keys():
			var index := index_for_identity(mid)
			if index >= 0:
				combat_slots[index] = plan.get_slot_for_member(mid)
		_formation_change_pending = false

func _stop_tactical_ai() -> void:
	tactical_ai_enabled = false
	tactical_ai_recovering = false
	tactical_ai_order_cooldown = 0.0
	tactical_ai_chase_cooldown = 0.0
	tactical_ai_status = "停用"
	tactical_ai_reason = ""
	tactical_ai_target_id = -1

func set_tactical_ai_enabled(requester: int, enabled: bool) -> Dictionary:
	if enabled and _team_ship_activity(): return SiteRuntime.fail("EMBARKED", "乘載或船岸作業中不能啟用地面自動指揮")
	if not garrison_feature_id.is_empty(): return SiteRuntime.fail("GARRISONED", "駐營容器不接受戰術命令")
	if not combat_enabled:
		return SiteRuntime.fail("NO_TARGET")
	if (is_inside_tree() and get_tree().paused) or (data != null and bool(data.site.get("paused", false))):
		return SiteRuntime.fail("BUSY", "暫停時不切換自動指揮")
	if role != "combat":
		return SiteRuntime.fail("INVALID_ORDER", "只有戰鬥隊伍可啟用自動指揮")
	_command_dirty = true
	settle_combat_command()
	if requester != current_commander or not command_eligible(requester):
		return SiteRuntime.fail("NO_AUTHORITY", "只有當前在場指揮者可切換自動指揮")
	if tactical_ai_enabled != enabled:
		_stop_tactical_ai()
		tactical_ai_enabled = enabled
		tactical_ai_status = "待判斷" if enabled else "停用"
	return SiteRuntime.ok("已啟用自動指揮" if enabled else "已停用自動指揮")

func issue_tactical_ai_order(order_id: int, goal: Vector2i = INVALID_CELL, target_id: int = -1, retreat_threats: Array[Vector2i] = []) -> Dictionary:
	if not tactical_ai_enabled or role != "combat":
		return SiteRuntime.fail("INVALID_ORDER", "此隊伍未啟用自動指揮")
	if (is_inside_tree() and get_tree().paused) or (data != null and bool(data.site.get("paused", false))):
		return SiteRuntime.fail("BUSY", "暫停時不結算新命令")
	var retreat := {}
	var prior_slots: Array[Vector2i] = []
	var prior_player_goal := player_goal
	if order_id == CombatOrder.RETREAT:
		retreat = _preview_tactical_retreat(goal, retreat_threats)
		if not bool(retreat.get("ok", false)):
			return retreat
		prior_slots.assign(combat_slots)
	_issuing_tactical_ai_order = true
	var result := issue_combat_order(current_commander, order_id, goal, target_id)
	_issuing_tactical_ai_order = false
	if bool(result.get("ok", false)):
		if order_id == CombatOrder.RETREAT:
			# The original RETREAT advances these original slots. The planner is
			# disposable; accepted physical steps and their claims remain untouched.
			for index in range(combat_slots.size()):
				combat_slots[index] = retreat.slots.get(combat_identity(index), prior_slots[index])
			player_goal = prior_player_goal
			result["retreat_current_safety"] = retreat.current_safety
			result["retreat_planned_safety"] = retreat.planned_safety
		tactical_ai_orders += 1
	return result

func _preview_tactical_retreat(goal: Vector2i, threats: Array[Vector2i]) -> Dictionary:
	if not combat_enabled or data == null:
		return SiteRuntime.fail("NO_TARGET")
	if not data.is_walkable(goal) or _is_external_cell(goal):
		return SiteRuntime.fail("BLOCKED", "撤退集結點不是合法空地")
	var members: Array[int] = []
	var positions := {}
	for index in range(combat_units.size()):
		if is_member(index) and combat_can_act(index) and not is_controlled_person(index):
			var identity := combat_identity(index)
			members.append(identity)
			positions[identity] = cells[index]
	if members.is_empty():
		return SiteRuntime.fail("NO_TARGET", "沒有可自主撤退的原隊員")
	var profile := FormationMovementProfile.from_members(members, self)
	var origin: Vector2i = positions.get(combat_identity(current_commander), positions[members[0]])
	var path: Array[Vector2i] = FormationTransitPlanner.build_macro_path(data, origin, goal, profile)
	if path.is_empty():
		return SiteRuntime.fail("BLOCKED", "未找到前往撤退集結點的通路")
	var registry: Object = _coordinator.deployment_registry if _coordinator != null and "deployment_registry" in _coordinator else null
	var officers: Array[int] = []
	if positions.has(combat_identity(current_commander)):
		officers.append(combat_identity(current_commander))
	var plan := FormationDestinationPlanner.plan_deployment(team_id, _current_order_serial + 1, data, goal, path, members, registry, officers, positions, Vector2i.ZERO, profile, "auto")
	if plan == null or plan.member_slot_map.size() != members.size():
		return SiteRuntime.fail("INSUFFICIENT_SPACE", "撤退地形沒有足夠的合法集結格")
	var blocked := {}
	if _coordinator != null:
		for other in _coordinator.get_active_formations():
			if other == self or not ("data" in other) or other.data != data:
				continue
			for occupied: Vector2i in other.get_active_members_occupancy().values():
				blocked[occupied] = true
			for claimed: Vector2i in other.get_active_movement_claims():
				blocked[claimed] = true
	var used := {}
	var current_safety := 0.0
	var planned_safety := 0.0
	for identity: int in members:
		var slot: Vector2i = plan.member_slot_map[identity]
		var occupant := int(_cell_owners.get(slot, -1))
		var claimant := int(_reserved_cells.get(slot, -1))
		if used.has(slot) or not data.is_walkable(slot) or _is_external_cell(slot) or blocked.has(slot) \
			or (registry != null and registry.is_slot_reserved(slot, team_id)) \
			or (occupant >= 0 and not positions.has(combat_identity(occupant))) \
			or (claimant >= 0 and not positions.has(combat_identity(claimant))):
			return SiteRuntime.fail("BLOCKED", "撤退集結格被其他人物、車輛或部署占用")
		used[slot] = true
		var before := 14.0
		var after := 14.0
		for threat: Vector2i in threats:
			before = minf(before, Vector2i(positions[identity]).distance_to(threat))
			after = minf(after, slot.distance_to(threat))
		current_safety += before
		planned_safety += after
	current_safety /= members.size()
	planned_safety /= members.size()
	# Near the safety cap, demand half the remaining improvement instead of
	# making withdrawal mathematically impossible for an already distant rear.
	var required_gain := minf(0.5, (14.0 - current_safety) * 0.5)
	if not threats.is_empty() and planned_safety <= current_safety + required_gain:
		return SiteRuntime.fail("UNSAFE_RETREAT", "撤退集結後未增加隊員與敵軍的平均距離")
	return SiteRuntime.ok("撤退集結格已驗證", {"slots": plan.member_slot_map, "current_safety": current_safety, "planned_safety": planned_safety})

func _capture_tactical_ai_state() -> Dictionary:
	return {"version": 1, "enabled": tactical_ai_enabled, "recovering": tactical_ai_recovering,
		"order_cooldown": tactical_ai_order_cooldown, "chase_cooldown": tactical_ai_chase_cooldown}

func _restore_tactical_ai_state(saved: Dictionary) -> void:
	tactical_ai_enabled = bool(saved.get("enabled", false))
	tactical_ai_recovering = bool(saved.get("recovering", false))
	tactical_ai_order_cooldown = float(saved.get("order_cooldown", 0.0))
	tactical_ai_chase_cooldown = float(saved.get("chase_cooldown", 0.0))
	tactical_ai_status = "待判斷" if tactical_ai_enabled else "停用"

func issue_combat_order(requester: int, order_id: int, goal: Vector2i = INVALID_CELL, target_id: int = -1, final_facing: Vector2i = Vector2i.ZERO, preset_id: String = "") -> Dictionary:
	if not _issuing_tactical_ai_order and _region_operation_pending():
		return SiteRuntime.fail("BUSY", "原跨區操作仍待補算或交接；暫不能接受新命令")
	var prior_ranged_serial := ranged_order_serial
	var result := _issue_combat_order(requester, order_id, goal, target_id, final_facing, preset_id, false)
	# Accepted no-op retreat responses must also invalidate any unlaunched preparation.
	if bool(result.get("ok", false)) and ranged_order_serial == prior_ranged_serial: _invalidate_ranged_order()
	return result

func _ranged_order_guard(requester: int, stopping: bool = false) -> Dictionary:
	# Pure admission through the original command authority: do not settle/mutate
	# a rejected command just to discover whether its requester was eligible.
	if data == null or not exchange_enabled or not combat_enabled: return SiteRuntime.fail("NO_TARGET")
	if _region_operation_pending() or has_ship_journey(): return SiteRuntime.fail("BUSY", "原跨區或船隊交接尚未完成")
	if not garrison_feature_id.is_empty(): return SiteRuntime.fail("GARRISONED", "駐營人員須先由原軍官編成")
	if (is_inside_tree() and get_tree().paused) or bool(data.site.get("paused", false)):
		return SiteRuntime.fail("BUSY", "暫停時不接受射擊命令")
	if requester != current_commander or not command_eligible(requester):
		return SiteRuntime.fail("NO_AUTHORITY", "只有當前在場指揮者可下令")
	if not stopping and _team_ship_activity(): return SiteRuntime.fail("EMBARKED", "P1 射擊命令未准入船岸作業")
	if not stopping and is_sustain_routed(): return SiteRuntime.fail("ROUTED", "原隊伍須先完成安全整補")
	return SiteRuntime.ok()

func issue_ranged_order(requester: int, target: Dictionary, ammo_mode: String = "NORMAL") -> Dictionary:
	var guard := _ranged_order_guard(requester)
	if not guard.ok: return guard
	if ammo_mode not in ["NORMAL", "FIRE_ARROW"]: return SiteRuntime.fail("UNSUPPORTED_AMMO", "未支援的彈藥模式")
	var has_ranged := false
	var supported := false
	for index in range(combat_units.size()):
		if not is_member(index) or not combat_can_act(index) or _siege_crew(index) or _ship_embarked(index): continue
		if ranged_profile(index).is_empty(): continue
		has_ranged = true
		if not ranged_profile(index, ammo_mode).is_empty():
			supported = true
			break
	if not supported:
		return SiteRuntime.fail("UNSUPPORTED_AMMO" if has_ranged else "NO_TARGET", "沒有支援此彈藥模式的原隊員")
	if not ranged_target_validate.is_valid(): return SiteRuntime.fail("NO_TARGET", "原 Site 目標查詢尚未接入")
	var checked: Variant = ranged_target_validate.call(self, target, ammo_mode)
	if not checked is Dictionary or not checked.has("ok"): return SiteRuntime.fail("NO_TARGET")
	if not bool(checked.ok): return checked
	if not checked.get("cell") is Vector2i or not data.contains(checked.cell): return SiteRuntime.fail("NO_TARGET")
	# P1 only changes parameters of this original Army order. It preserves its
	# committed steps; the Lab additionally requires a stationary HOLD/ATTACK release.
	ranged_order_serial += 1
	ranged_order_issuer_id = combat_identity(requester)
	ranged_ammo_mode = ammo_mode
	ranged_target = target.duplicate(true)
	ranged_fire_policy = {}
	ranged_enabled = true
	return SiteRuntime.ok("已設定原隊伍射擊目標", {"order_serial": ranged_order_serial})

func stop_ranged_order(requester: int) -> Dictionary:
	var guard := _ranged_order_guard(requester, true)
	if not guard.ok: return guard
	_invalidate_ranged_order()
	return SiteRuntime.ok("已停止原隊伍射擊", {"order_serial": ranged_order_serial})

func _invalidate_ranged_order() -> void:
	ranged_order_serial += 1
	ranged_order_issuer_id = 0
	ranged_target = {}
	ranged_fire_policy.clear()
	ranged_enabled = false

func ranged_order_authorized(ignore_pause: bool = false) -> bool:
	if data == null or not exchange_enabled or not combat_enabled or not ranged_enabled: return false
	if not command_eligible(current_commander) or combat_identity(current_commander) != ranged_order_issuer_id: return false
	if not ignore_pause and ((is_inside_tree() and get_tree().paused) or bool(data.site.get("paused", false))): return false
	return garrison_feature_id.is_empty() and not _region_operation_pending() and not has_ship_journey() \
		and not _team_ship_activity() and not is_sustain_routed()

func _corps_original_person(identity: int) -> Dictionary:
	if _ship_identity_in_journey(identity): return {}
	if combat_target_query.is_valid():
		var found: Variant = combat_target_query.call(identity)
		if found is Dictionary and not found.is_empty():
			return found
	var formations: Array = _coordinator.get_active_formations() if _coordinator != null else [self]
	for formation in formations:
		if not formation is TerrainArmy or formation.data != data:
			continue
		var army: TerrainArmy = formation
		var index: int = army.index_for_identity(identity)
		if index >= 0 and index < army.combat_units.size() and not army._ship_in_journey(index):
			return {"owner": army, "unit": index}
		if is_instance_valid(army.player_member) and army.player_member.person_id == identity and not army._ship_in_journey(PLAYER_MEMBER):
			return {"owner": army.player_member, "unit": -1}
	return {}

func issue_corps_reposition(requester_person_id: int, goal: Vector2i, final_facing: Vector2i = Vector2i.ZERO) -> Dictionary:
	if _region_operation_pending():
		return SiteRuntime.fail("BUSY", "原跨區操作仍待補算或交接；暫不能接受軍團調位")
	var authority := SiteRuntime.authorize_corps_reposition(data, requester_person_id, self, _corps_original_person)
	if not bool(authority.get("ok", false)):
		return authority
	if is_sustain_routed():
		return SiteRuntime.fail("ROUTED", "士氣崩潰後只能執行潰退")
	var result := _issue_combat_order(requester_person_id, CombatOrder.MOVE, goal, -1, final_facing, "", true)
	if bool(result.get("ok", false)):
		_corps_reposition_source = {"version": 1, "corps_id": str(authority.corps_id), "commander_person_id": requester_person_id, "team_id": team_id}
		result["corps_id"] = authority.corps_id
	return result

static func _build_combat_move_plan(map: TerrainData, formation_id: int, serial: int, goal: Vector2i, prepared: Dictionary, active_mids: Array[int], current_cells: Dictionary, route_anchor: Vector2i, distances: Dictionary, exit_k: int, previous_ranks: Dictionary = {}, controlled_ids: Dictionary = {}) -> CombatMovePlan:
	var plan := CombatMovePlan.new()
	var path: Array[Vector2i] = prepared.path
	var profile: Object = prepared.profile
	plan.formation_id = formation_id
	plan.order_serial = serial
	plan.requested_goal = goal
	plan.terrain_revision = int(map.navigation_revision)
	plan.resolved_anchor = prepared.anchor
	plan.macro_path = path
	plan.phase = CombatMovementTypes.CombatMovePhase.TRANSIT
	plan.short_translation = bool(prepared.get("short_translation", false))
	plan.destination_plan = prepared.plan
	plan.eligible_member_count = active_mids.size()
	plan.macro_cursor = exit_k
	var init_fwd: Vector2i = path[mini(exit_k + 1, path.size() - 1)] - path[exit_k] if path.size() > 1 else Vector2i.RIGHT
	plan.current_width = mini(4, FormationTransitPlanner.detect_corridor_width(map, path[exit_k], init_fwd, profile))
	plan.pending_width = plan.current_width
	plan.width_confirm_counter = 0
	var costs: Dictionary = {}
	for mid: int in active_mids:
		var cell: Vector2i = current_cells.get(mid, path[0])
		costs[mid] = distances.get(cell, 999999)
	var ordered: Array[int] = active_mids.duplicate()
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var ca: int = int(costs[a])
		var cb: int = int(costs[b])
		if ca != cb: return ca < cb
		var ra: int = int(previous_ranks.get(a, 9999))
		var rb: int = int(previous_ranks.get(b, 9999))
		if ra != rb: return ra < rb
		var pa: int = int(controlled_ids.has(a))
		var pb: int = int(controlled_ids.has(b))
		if pa != pb: return pa > pb
		return a < b)
	for rank in range(ordered.size()):
		var mid: int = ordered[rank]
		plan.member_sequence_rank[mid] = rank
		plan.pre_route_staging_slots[mid] = current_cells.get(mid, route_anchor)
		plan.member_path_s[mid] = 0.0
		plan.member_defer_count[mid] = 0
	plan.previous_median_path_s = 0.0
	return plan

func _issue_combat_order(requester: int, order_id: int, goal: Vector2i, target_id: int, final_facing: Vector2i, preset_id: String, corps_authorized: bool) -> Dictionary:
	if has_ship_journey(): return SiteRuntime.fail("BUSY", "船隊旅程中不能改現場冷軍令")
	if not garrison_feature_id.is_empty(): return SiteRuntime.fail("GARRISONED", "駐營人員須先由軍官編成才可接受軍令")
	if not combat_enabled:
		return SiteRuntime.fail("NO_TARGET")
	if is_inside_tree() and get_tree().paused:
		return SiteRuntime.fail("BUSY", "暫停時不結算新命令")
	if order_id in [CombatOrder.MOVE, CombatOrder.RETURN, CombatOrder.ATTACK, CombatOrder.PURSUE] and _team_ship_activity():
		return SiteRuntime.fail("EMBARKED", "乘載或船岸作業中只接受守位停止或原潰退流程")
	# Nekki 2026-10-13 (retreat rule, option 3): with intact morale both the captain
	# and tactical AI may order an orderly RETREAT to a destination; after a Sustain
	# collapse the captain's RETREAT becomes the boundary morale retreat (below).
	# Without a destination an intact team cannot withdraw by order.
	if order_id == CombatOrder.RETREAT and not is_sustain_routed() and not _issuing_tactical_ai_order and goal == INVALID_CELL:
		return SiteRuntime.fail("NOT_ROUTED", "士氣尚未崩潰；有序撤退須指定目的地")
	_command_dirty = true
	settle_combat_command()
	if not corps_authorized and (requester != current_commander or not command_eligible(requester)):
		return SiteRuntime.fail("NO_AUTHORITY", "只有當前在場指揮者可下令")
	if order_id < CombatOrder.HOLD or order_id > CombatOrder.PURSUE:
		return SiteRuntime.fail("INVALID_ORDER")
	if order_id == CombatOrder.RETREAT and is_sustain_routed():
		return begin_morale_retreat()
	if _get_active_member_ids().is_empty() and not (order_id == CombatOrder.HOLD and _team_ship_activity()): return SiteRuntime.fail("NO_TARGET", "原隊員正操作器具；一般軍令沒有參與者")
	if combat_order == CombatOrder.RETREAT and str(_retreat_resolution.get("reason", "")) == "morale_collapse" and not morale_retreat_terminal():
		return SiteRuntime.fail("ROUTED", "潰退中不能取消離圖或避難；須先安全整補")
	if is_sustain_routed() and order_id in [CombatOrder.ATTACK, CombatOrder.PURSUE, CombatOrder.MOVE]:
		return SiteRuntime.fail("ROUTED", "隊伍尚未完成安全整補與重新集結；只能守位自衛或撤退")
	if order_id == CombatOrder.RETREAT and (not data.is_walkable(goal) or _is_external_cell(goal)):
		return SiteRuntime.fail("BLOCKED", "目的地不是合法空地")
	var target := {}
	if order_id == CombatOrder.PURSUE:
		if target_query.is_valid():
			target = target_query.call(self, target_id)
		if target.is_empty() or command_reference.distance_to(Vector2(target.cell) + Vector2.ONE * 0.5) > 20.0:
			return SiteRuntime.fail("NO_TARGET", "追擊需指定 20 格內可行動敵人")

	# MOVE specific transactional pre-validation
	var move_resolved_cell := INVALID_CELL
	var move_macro_path: Array[Vector2i] = []
	var move_dest_plan: CombatDeploymentPlan = null
	var move_profile: FormationMovementProfile = null
	var move_short_translation := false
	var move_serial := 0
	var selected_preset := formation_preset_id
	if order_id == CombatOrder.MOVE:
		var preflight_started := Time.get_ticks_usec() if combat_profile_enabled else 0
		var preflight := _preflight_combat_move(goal, final_facing, _current_order_serial + 1, preset_id)
		if combat_profile_enabled: _profile_combat_stage("order_preflight", preflight_started)
		if not bool(preflight.get("ok", false)):
			return preflight
		selected_preset = str(preflight["preset_id"])
		move_resolved_cell = preflight["anchor"]
		move_macro_path = preflight["path"]
		move_dest_plan = preflight["plan"]
		move_profile = preflight["profile"]
		move_short_translation = bool(preflight.get("short_translation", false))
		move_serial = _current_order_serial + 1
		var reg: Object = _coordinator.deployment_registry if _coordinator != null and "deployment_registry" in _coordinator else null
		if reg != null:
			var all_slots: Array[Vector2i] = []
			for slot: Vector2i in move_dest_plan.member_slot_map.values():
				if not all_slots.has(slot):
					all_slots.append(slot)
			var old_serial := _combat_deployment_plan.order_serial if _combat_deployment_plan != null else (get_order_serial() if not _suppress_approaches.is_empty() or not _fire_navigation.is_empty() else 0)
			var rep_res: Dictionary = reg.try_replace_reservations(team_id, old_serial, move_serial, all_slots)
			if not bool(rep_res.get("ok", false)):
				return SiteRuntime.fail("RESERVATION_CONFLICT", "目的地槽位衝突")
		_current_order_serial = move_serial
		_preserve_structure_order = false
		formation_preset_id = selected_preset
		_formation_change_pending = false

	# Only accepted commands discard unstarted common-order routes. The original
	# reservations and any in-flight edge still complete through their owner.
	for index: int in _follower_combat_route_stamps.keys():
		_clear_follower_route(index)
	_follower_failed_combat_routes.clear()
	_retreat_pair_pending.clear()
	_retreat_pairs_used.clear()
	if order_id == CombatOrder.RETREAT:
		_next_order_serial()
	if order_id != CombatOrder.MOVE:
		_release_combat_deployment_lease()
		_combat_move_plan = null
		_combat_deployment_plan = null
	_combat_absent_slots.clear()
	if not corps_authorized:
		_corps_reposition_source.clear()
	if order_id == CombatOrder.HOLD and vehicle_transport != null:
		vehicle_transport.stop_team_ships(team_id)
	combat_order = order_id
	_move_encounters.clear()
	_move_landed_members.clear()
	_clear_member_attack_targets()
	for index: int in _unit_rescues.keys():
		if is_member(index):
			_cancel_unit_rescue(index) # Explicit new orders interrupt members' help, never teleport.
	combat_attacking = order_id in [CombatOrder.ATTACK, CombatOrder.PURSUE]
	if combat_attacking:
		needs_attack_order = false
	combat_goal = goal
	pursuit_target = target_id if order_id == CombatOrder.PURSUE else -1
	pursuit_origin = command_reference
	pursuit_left = 20.0 if order_id == CombatOrder.PURSUE else 0.0
	_order_delay = 0.5 * (1.0 - command_effect("tactics", 0.20))
	_command_elapsed = 0.0
	_vacancy_assignments.clear()

	if order_id in [CombatOrder.HOLD, CombatOrder.ATTACK]:
		# A new battle-line order cannot resume destinations left by a previous
		# march/chase. Keep only the current committed step's safe endpoint.
		for index in range(cells.size()):
			if is_member(index) and not _siege_crew(index) and not _ship_embarked(index):
				combat_slots[index] = moving_to[index] if moving_to[index] != INVALID_CELL else cells[index]
		_combat_move_plan = null
	elif order_id == CombatOrder.MOVE:
		var active_mids := _get_active_member_ids()
		var occupancy := get_active_members_occupancy()
		var exit_k := _find_contiguous_egress_cursor(move_macro_path, occupancy)
		var egress_started := Time.get_ticks_usec() if combat_profile_enabled else 0
		var distances := _build_egress_distance_field(move_macro_path, exit_k, move_profile)
		if combat_profile_enabled: _profile_combat_stage("order_egress", egress_started)
		var member_cells: Dictionary = {}
		var controlled_ids: Dictionary = {}
		for mid: int in active_mids:
			var index := index_for_identity(mid)
			if index >= 0:
				member_cells[mid] = cells[index]
				if is_controlled_person(index): controlled_ids[mid] = true
		var previous_ranks: Dictionary = _combat_move_plan.member_sequence_rank if _combat_move_plan != null else {}
		var prepared := {"anchor": move_resolved_cell, "path": move_macro_path, "plan": move_dest_plan,
			"profile": move_profile, "short_translation": move_short_translation}
		_combat_move_plan = _build_combat_move_plan(data, team_id, move_serial, goal, prepared, active_mids, member_cells, _get_combat_route_anchor_cell(), distances, exit_k, previous_ranks, controlled_ids)
		for mid: int in active_mids:
			var index := index_for_identity(mid)
			if index >= 0: combat_slots[index] = cells[index]
		_combat_deployment_plan = move_dest_plan
		_formation_movement_profile = move_profile
	elif order_id == CombatOrder.RETREAT:
		_translate_combat_slots(goal)
		_combat_move_plan = null

	if is_instance_valid(player_member):
		player_goal = goal if order_id in [CombatOrder.MOVE, CombatOrder.RETREAT] else (Vector2i(target.cell) if order_id == CombatOrder.PURSUE else player_member.terrain_cell)
		queue_redraw()
	command_status = ["守位自衛", "維持戰線接敵", "隊伍機動", "撤退", "明確追擊"][order_id]
	if exchange_enabled and order_id == CombatOrder.ATTACK:
		command_status = "接敵；近戰尋找側後方空位"
	if not _issuing_tactical_ai_order: _stop_tactical_ai()
	return SiteRuntime.ok(command_status)

func _clear_member_attack_targets() -> void:
	_invalidate_ranged_order()
	for index in range(combat_units.size()):
		if is_member(index):
			combat_units[index].target = -1
	if is_instance_valid(player_member):
		player_member.attack_target_id = 0

func move_encounter_eligible(index: int) -> bool:
	return exchange_enabled and combat_enabled and combat_order == CombatOrder.MOVE and _combat_move_plan != null \
		and index >= 0 and index < combat_units.size() and is_member(index) and not is_controlled_person(index) \
		and combat_can_act(index) and not _siege_crew(index) and not _ship_embarked(index) and not is_sustain_routed() and not _unit_rescues.has(index) \
		and combat_units[index].get("work_task", {}).is_empty() \
		and not (person_busy_query.is_valid() and bool(person_busy_query.call(combat_identity(index))))

func publish_move_encounters(contacts: Dictionary) -> void:
	_move_encounters.clear()
	_move_landed_members.clear()
	for index: Variant in contacts:
		if typeof(index) != TYPE_INT or not move_encounter_eligible(int(index)):
			continue
		var enemies: Variant = contacts[index]
		if enemies is Dictionary and not enemies.is_empty():
			_move_encounters[index] = enemies.duplicate()
	if combat_order == CombatOrder.MOVE and _combat_move_plan != null:
		FormationRecoveryController.set_engaging_overlay(_combat_move_plan, not _move_encounters.is_empty())

func _move_engaging() -> bool:
	return combat_order == CombatOrder.MOVE and _combat_move_plan != null \
		and (not _move_encounters.is_empty() or _combat_move_plan.tactical_overlay == CombatMovementTypes.TacticalOverlay.ENGAGING)

func _probe_move_landing_contact() -> void:
	if _move_landed_members.is_empty() or _coordinator == null or _move_engaging():
		return
	var occupied: Dictionary = _coordinator._current_occupancy
	var owners: Dictionary = _coordinator._member_lookup
	var lab: TerrainLab = exchange_people_query.get_object() as TerrainLab if exchange_people_query.is_valid() else null
	for mid: int in _move_landed_members:
		var index := index_for_identity(mid)
		if not move_encounter_eligible(index):
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cells[index] + direction
			if not data.can_attack_across(cells[index], next):
				continue
			var other_id: int = int(occupied.get(next, -1))
			var other: Dictionary = owners.get(other_id, {})
			var army: TerrainArmy = other.get("formation") as TerrainArmy
			if army != null and army != self and army.faction_id != faction_id and army.exchange_enabled:
				var other_index := army.index_for_identity(other_id)
				if other_index >= 0 and army.combat_can_act(other_index):
					_combat_move_plan.tactical_overlay = CombatMovementTypes.TacticalOverlay.ENGAGING
					return
			if lab != null:
				for actor: TerrainTestCharacter in lab.combat_actors:
					if is_instance_valid(actor) and actor.faction_id != faction_id and actor.exchange_enabled \
						and actor.can_act() and actor.terrain_cell == next:
						_combat_move_plan.tactical_overlay = CombatMovementTypes.TacticalOverlay.ENGAGING
						return
	_move_landed_members.clear()

func exchange_initiates(index: int, other_id: int, melee: bool = false) -> bool:
	if _siege_crew(index) or not _ship_attack_allowed(index): return false
	if not garrison_feature_id.is_empty(): return false
	if index < 0 or index >= combat_units.size():
		return false
	# A controlled person's new explicit attack remains legal after a team order.
	# A remembered opponent from an earlier exchange is never a new team order.
	if is_controlled_person(index) or not is_member(index):
		return int(combat_units[index].target) == other_id
	if melee and move_encounter_eligible(index):
		return (_move_encounters.get(index, {}) as Dictionary).has(other_id)
	if melee and combat_order == CombatOrder.HOLD and not is_sustain_routed() and combat_units[index].get("work_task", {}).is_empty() \
		and not (person_busy_query.is_valid() and bool(person_busy_query.call(combat_identity(index)))):
		if needs_attack_order: return true
		# Original nonhelm boat defense uses the current physical contact only.
		if _ship_embarked(index) and current_commander >= 0 and command_eligible(current_commander) and _combat_ship_contact(index, other_id):
			var other: Dictionary = vehicle_transport.ship_person(other_id)
			return not other.is_empty() and vehicle_transport.is_embarked(other_id) and int(other.faction) != faction_id \
				and not bool(other.captive) and other.owner.combat_can_act(int(other.unit))
	return combat_attacking and combat_order in [CombatOrder.ATTACK, CombatOrder.PURSUE] \
		and current_commander >= 0 and not needs_attack_order and not is_sustain_routed()

func _translate_combat_slots(goal: Vector2i) -> void:
	var displacement := goal - Vector2i(command_reference.floor())
	for index in range(cells.size()):
		if is_member(index) and not _ship_embarked(index):
			combat_slots[index] = cells[index] + displacement

func _reserve_combat_step(index: int, next: Vector2i, escort_guard_id: int = 0, running: bool = false, garrison_return: bool = false, siege_work_step: bool = false, route_goal: Vector2i = INVALID_CELL) -> bool:
	if _ship_in_journey(index) or _ship_embarked(index): return false
	proposal_count += 1
	if index < 0 or index >= combat_units.size():
		rejected_dependency_count += 1
		return false
	if _siege_crew(index) and not siege_work_step: return false
	var escorted := bool(combat_hot_get(index, &"captive")) and escort_guard_id > 0 and escort_step_guard.is_valid() and bool(escort_step_guard.call(combat_identity(index), escort_guard_id, next))
	if not garrison_feature_id.is_empty() and not escorted and not (garrison_return and _garrison_return_home(index) != INVALID_CELL): return false
	var identity := combat_identity(index)
	var person_goal: Vector2i = route_goal if route_goal != INVALID_CELL else _follower_route_goals.get(index, combat_slots[index])
	var tower_exception: bool = vehicle_transport != null and vehicle_transport.person_path_exception(next, identity, cells[index], cells[index], person_goal)
	var own_blocked := _cell_owners.has(next) or _reserved_cells.has(next) if tower_exception or vehicle_transport != null and vehicle_transport.is_operator(identity) else blocks_person_cell(next)
	if (not combat_can_act(index) and not escorted) or _combat_action_blocks_step(index) or moving_to[index] != INVALID_CELL or not data.can_step(cells[index], next) or own_blocked or _is_external_cell(next, identity, cells[index], person_goal, cells[index]):
		rejected_dependency_count += 1
		return false
	if vehicle_transport != null and not vehicle_transport.before_step(self, index, next, person_goal):
		rejected_dependency_count += 1
		return false
	if vehicle_transport != null:
		vehicle_transport.commit_step_reservation(self, index, next)
	_reserved_cells[next] = index
	moving_to[index] = next
	move_progress[index] = 0.0
	move_duration[index] = RUN_DURATION if running and is_controlled_person(index) else MOVE_DURATION
	move_curve[index] = 0
	locomotion_mode[index] = Locomotion.RUN if running and is_controlled_person(index) else Locomotion.WALK
	movement_state[index] = UnitState.MOVING
	facing[index] = next - cells[index]
	combat_hot_set(index, &"pose", "run" if running and is_controlled_person(index) else "walk")
	combat_hot_set(index, &"age", 0.0)
	if exchange_enabled:
		combat_hot_set(index, &"attack", false) # A winning visual is not an action lock.
		combat_hot_set(index, &"exchange_pose_duration", 0.0)
		var visual: Dictionary = combat_hot_get(index, &"exchange_visual", {})
		if not visual.is_empty():
			if ExchangeTimings.reaction_priority(StringName(str(visual.pose))) == 0:
				visual["left"] = minf(float(visual.left), maxf(0.0, ExchangeTimings.MOVE_CORE_SECONDS - float(visual.age)))
				if float(visual.left) <= 0.000000001:
					combat_hot_erase(index, &"exchange_visual")
				else:
					combat_hot_set(index, &"exchange_visual", visual)
	_mark_visual_row(index)
	accepted_count += 1
	_audio_begin_step(index, cells[index], next, locomotion_mode[index] == Locomotion.RUN)
	return true

func _retreat_pair_member_ready(index: int) -> bool:
	if index < 0 or index >= combat_units.size() or _ship_embarked(index) or not is_member(index) or not combat_can_act(index) \
		or is_controlled_person(index) or moving_to[index] != INVALID_CELL or _combat_action_blocks_step(index) \
		or _unit_rescues.has(index) or _cell_owners.get(cells[index], -1) != index or _reserved_cells.has(cells[index]):
		return false
	return vehicle_transport == null or not vehicle_transport.is_operator(combat_identity(index))

func _find_blocked_retreat_pair() -> Dictionary:
	if _coordinator == null or combat_order != CombatOrder.RETREAT:
		return {}
	var component_by_cell: Dictionary = {}
	var next_component := 0
	for front in range(combat_units.size()):
		if not _retreat_pair_member_ready(front) or cells[front] == combat_slots[front]:
			continue
		var source: Vector2i = cells[front]
		var goal: Vector2i = combat_slots[front]
		var distance := absi(goal.x - source.x) + absi(goal.y - source.y)
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var other_cell := source + direction
			if absi(goal.x - other_cell.x) + absi(goal.y - other_cell.y) >= distance:
				continue
			var rear: int = int(_cell_owners.get(other_cell, -1))
			if rear == front or not _retreat_pair_member_ready(rear) \
				or not data.can_step(source, other_cell) or not data.can_step(other_cell, source) \
				or _is_external_cell(source) or _is_external_cell(other_cell):
				continue
			var first_id := combat_identity(front)
			var second_id := combat_identity(rear)
			var key := "%d:%d" % [mini(first_id, second_id), maxi(first_id, second_id)]
			if _retreat_pairs_used.has(key):
				continue
			# An ally can block the first edge, but a solid wall cannot justify
			# exchanging people. Cache static components for the whole review.
			if not component_by_cell.has(source):
				var pending: Array[Vector2i] = [source]
				component_by_cell[source] = next_component
				var head := 0
				while head < pending.size() and int(component_by_cell.get(goal, -1)) != next_component:
					var current: Vector2i = pending[head]
					head += 1
					for edge: Vector2i in TerrainData.DIRECTIONS:
						var neighbor := current + edge
						if component_by_cell.has(neighbor) or not data.can_step(current, neighbor):
							continue
						component_by_cell[neighbor] = next_component
						pending.append(neighbor)
				next_component += 1
			if component_by_cell.get(goal, -1) != component_by_cell[source]:
				continue
			return {"front": front, "rear": rear, "from": source, "to": other_cell,
				"serial": get_order_serial(), "key": key}
	return {}

func _garrison_return_home(index: int) -> Vector2i:
	if garrison_feature_id.is_empty() or data == null or index < 0 or index >= combat_units.size() or _ship_embarked(index) or not is_member(index) or not combat_can_act(index): return INVALID_CELL
	var layout := SiteRuntime.military_layout(data, garrison_feature_id)
	if not layout.ok or not bool(layout.get("complete", false)) or layout.walkable_cells.has(data.index(cells[index])): return INVALID_CELL
	return combat_slots[index] if layout.walkable_cells.has(data.index(combat_slots[index])) else INVALID_CELL

func _advance_garrison_returns(delta: float) -> void:
	_command_elapsed += delta
	if _command_elapsed < 0.5: return
	_command_elapsed = 0.0
	for index in range(combat_units.size()):
		if is_controlled_person(index) or moving_to[index] != INVALID_CELL or _combat_action_blocks_step(index) or not combat_units[index].get("work_task", {}).is_empty(): continue
		if person_busy_query.is_valid() and bool(person_busy_query.call(combat_identity(index))): continue
		var home := _garrison_return_home(index)
		if home == INVALID_CELL: continue
		var next := _common_order_route_step(index, home, 0)
		if next != INVALID_CELL: _reserve_combat_step(index, next, 0, false, true)

func _update_combat_orders(delta: float) -> void:
	if _fire_nav_context_current(): return
	if has_ship_journey(): return # Coarse owner retains the original team order.
	if not garrison_feature_id.is_empty():
		_advance_garrison_returns(delta)
		return
	var new_order_pending := _order_delay > 0.0
	_order_delay = maxf(0.0, _order_delay - delta)
	if combat_order == CombatOrder.PURSUE:
		pursuit_left = maxf(0.0, pursuit_left - delta)
		var target: Dictionary = target_query.call(self, pursuit_target) if target_query.is_valid() else {}
		var stop := pursuit_left <= 0.0 or target.is_empty() or command_reference.distance_to(pursuit_origin) >= 20.0
		if not target.is_empty():
			stop = stop or pursuit_origin.distance_to(Vector2(target.cell) + Vector2.ONE * 0.5) >= 20.0
		if stop:
			combat_order = CombatOrder.RETURN
			combat_attacking = false
			_clear_member_attack_targets()
			pursuit_left = 0.0
			combat_goal = Vector2i(pursuit_origin.floor())
			_translate_combat_slots(combat_goal)
			command_status = "追擊結束；合法回位自衛"
		elif combat_goal != target.cell:
			combat_goal = target.cell
			_translate_combat_slots(combat_goal)
	_command_elapsed += delta
	if _formation_change_pending:
		_formation_retry_seconds += delta
		if _formation_retry_seconds >= 2.0:
			_formation_retry_seconds = 0.0
			_apply_pending_formation_change()
		if _formation_change_pending and combat_order == CombatOrder.MOVE and _combat_move_plan == null:
			return # Keep the original goal while a released crew awaits legal replanning.
	if _command_elapsed < 0.5 * (1.0 - command_effect("tactics", 0.20)) or _order_delay > 0.0:
		return
	if combat_order == CombatOrder.RETREAT and str(_retreat_resolution.get("reason", "")) == "morale_collapse":
		_command_elapsed = 0.0
		_update_morale_retreat()
		return
	if not new_order_pending and _periodic_review_conflicts():
		return # Keep the due elapsed time; the next original action step reviews it.
	_command_elapsed = 0.0
	if combat_order == CombatOrder.HOLD:
		return
	if exchange_enabled and combat_order in [CombatOrder.ATTACK, CombatOrder.PURSUE] and (needs_attack_order or is_sustain_routed()):
		return # Loss of contact cannot route a broken team through the old vacancy fallback.
	_update_ranged_orders()
	if _try_exchange_encirclement():
		return # Engaged front holds; free melee members use the same original step claims.
	if combat_order == CombatOrder.ATTACK:
		_assign_combat_vacancy()
	if combat_order == CombatOrder.MOVE and _combat_move_plan != null:
		if _move_engaging():
			return
		if _coordinator != null:
			# The coordinator owns slots and infantry commits. Legacy vehicle
			# operators need the original person/vehicle swept-step transaction.
			if vehicle_transport != null:
				for index in range(combat_units.size()):
					if not is_member(index) or not combat_can_act(index) or is_controlled_person(index) or _siege_crew(index) or moving_to[index] != INVALID_CELL or _combat_action_blocks_step(index): continue
					var identity := combat_identity(index)
					if not vehicle_transport.is_operator(identity) or str(vehicle_transport._operated(identity).get("kind", "")) not in ["cart", "wagon"]: continue
					var goal: Vector2i = combat_slots[index]
					if cells[index] == goal: continue
					var next_step := _common_order_route_step(index, goal, identity)
					if next_step != INVALID_CELL: _reserve_combat_step(index, next_step)
			return

		var occ := get_active_members_occupancy()
		if not _combat_deployment_plan.following_member_ids.is_empty():
			var following_active: Dictionary = {}
			for mid: int in _get_active_member_ids():
				if occ.has(mid):
					following_active[mid] = occ[mid]
			var candidates: Array[Vector2i] = []
			candidates.assign(_combat_deployment_plan.platform_footprint)
			var blocked := _deployment_blocked_cells(candidates, _get_active_member_ids())
			FormationDestinationPlanner.refresh_following_members(_combat_move_plan, _combat_deployment_plan, following_active, data, null, blocked)
		var settled := _combat_batch_members.is_empty() and _automatic_deployment_settled()
		if settled:
			FormationDestinationPlanner.update_movement_phase(_combat_move_plan, _combat_deployment_plan, occ, data, delta, null, {}, r3_prepare_enabled)
			_orient_settled_combat_members()
			var absent_count := _combat_absent_slots.size()
			_finish_combat_absences()
			combat_order = CombatOrder.HOLD
			_corps_reposition_source.clear()
			_clear_member_attack_targets()
			command_status = "已抵達：平台部署 %d 人，進路待命 %d 人%s" % [
				_combat_deployment_plan.settled_platform_member_ids.size(),
				_combat_deployment_plan.queue_member_ids.size(),
				"；%d 名傷員原地待新令" % absent_count if absent_count > 0 else ""
			]
			_combat_move_plan = null
			return

		if not _refresh_move_terrain_revision():
			return
		FormationDestinationPlanner.update_ingress_gate(_combat_deployment_plan, occ)
		var cur_medoid := _get_active_members_medoid()
		FormationTransitPlanner.update_macro_cursor(_combat_move_plan, cur_medoid)

		var fwd := Vector2i(1, 0)
		if _combat_move_plan.macro_path.size() > 1:
			var c_idx: int = clampi(_combat_move_plan.macro_cursor, 0, _combat_move_plan.macro_path.size() - 2)
			fwd = _combat_move_plan.macro_path[c_idx + 1] - _combat_move_plan.macro_path[c_idx]
		var center_c: Vector2i = _combat_move_plan.macro_path[clampi(_combat_move_plan.macro_cursor, 0, _combat_move_plan.macro_path.size() - 1)]
		var detected_w := FormationTransitPlanner.detect_corridor_width(data, center_c, fwd, _formation_movement_profile)
		FormationTransitPlanner.update_width_hysteresis(_combat_move_plan, detected_w)

		var active_mids := _get_active_member_ids()
		FormationTransitPlanner.calculate_transit_slots(_combat_move_plan, data, _formation_movement_profile, active_mids, occ)
		FormationDestinationPlanner.update_movement_phase(_combat_move_plan, _combat_deployment_plan, occ, data, delta, null, {}, r3_prepare_enabled)

		for idx in range(combat_units.size()):
			if not is_member(idx) or not combat_can_act(idx):
				continue
			var mid := combat_identity(idx)
			var target: Dictionary = FormationDestinationPlanner.resolve_member_target(_combat_move_plan, _combat_deployment_plan, mid, cells[idx])
			var target_slot: Vector2i = target.get("target", cells[idx])
			if combat_slots[idx] != target_slot and moving_to[idx] == INVALID_CELL:
				_combat_move_plan.invalidate_member_route(mid)
			combat_slots[idx] = target_slot

		for idx in range(combat_units.size()):
			if not is_member(idx) or not combat_can_act(idx) or is_controlled_person(idx):
				continue
			var goal_cell: Vector2i = combat_slots[idx]
			if cells[idx] == goal_cell:
				continue
			if moving_to[idx] != INVALID_CELL:
				continue
			if _combat_action_blocks_step(idx):
				continue
			var mid := combat_identity(idx)
			var next_step := INVALID_CELL
			if _combat_move_plan.is_member_route_current(mid, goal_cell):
				var p: Array[Vector2i] = _combat_move_plan.member_paths[mid]
				if p.size() > 1 and p[0] == cells[idx] and p[-1] == goal_cell:
					next_step = p[1]
				else:
					_combat_move_plan.invalidate_member_route(mid)
			if next_step == INVALID_CELL:
				proposal_count += 1
				var route := _find_local_route(cells[idx], goal_cell, 256, false, -1, 0, false, _formation_movement_profile)
				if route.size() > 1:
					_combat_move_plan.member_paths[mid] = route.duplicate()
					_combat_move_plan.stamp_member_route(mid, goal_cell)
					next_step = route[1]
			if next_step != INVALID_CELL and FormationTransitPlanner._can_profile_step(data, cells[idx], next_step, _formation_movement_profile) and _reserve_combat_step(idx, next_step):
				if _combat_move_plan.member_paths.has(mid) and _combat_move_plan.member_paths[mid].size() > 1:
					_combat_move_plan.member_paths[mid].remove_at(0)

		var cur_med_s: float = float(_combat_move_plan.get_median_path_s())
		var had_prog := FormationRecoveryController.check_meaningful_progress(
			_combat_move_plan,
			cur_med_s,
			_combat_deployment_plan.settled_platform_member_ids.size(),
			_combat_deployment_plan.settled_queue_member_ids.size(),
			_combat_deployment_plan.promotion_count
		)
		if not had_prog:
			FormationRecoveryController.update_stall_clock(_combat_move_plan, 0.5)
			var previous_path_epoch: int = _combat_move_plan.path_epoch
			var fail_code := FormationRecoveryController.process_recovery(
				_combat_move_plan,
				cur_medoid,
				data,
				_formation_movement_profile,
				Time.get_ticks_msec() / 1000.0
			)
			if _combat_move_plan != null and _combat_move_plan.path_epoch != previous_path_epoch:
				if not _refresh_recovery_path_coordinates(0.5):
					return
			if fail_code == CombatMovementTypes.RuntimeMoveFailureCode.BLOCKED:
				cancel_combat_deployment_for_forced_order()
				combat_order = CombatOrder.HOLD
				_clear_member_attack_targets()
				command_status = "未找到合法通路；就地自衛，等待新令"
			elif fail_code == CombatMovementTypes.RuntimeMoveFailureCode.CONGESTED:
				cancel_combat_deployment_for_forced_order()
				combat_order = CombatOrder.HOLD
				_clear_member_attack_targets()
				command_status = "通道持續擁塞；就地防禦"
		return

	var arrived := true
	var made_progress := false
	for index in range(combat_units.size()):
		if not is_member(index) or not combat_can_act(index) or is_controlled_person(index) or _siege_crew(index) or _ship_embarked(index):
			continue
		if combat_order in [CombatOrder.ATTACK, CombatOrder.PURSUE] and _exchange_maneuver_blocked(index):
			continue
		var goal: Vector2i = combat_slots[index]
		if cells[index] == goal:
			continue
		arrived = false
		if moving_to[index] != INVALID_CELL:
			made_progress = true
			continue
		if _combat_action_blocks_step(index):
			made_progress = true
			continue
		if combat_order == CombatOrder.PURSUE:
			var offset := combat_goal - cells[index]
			if absi(offset.x) + absi(offset.y) <= (1 if exchange_enabled else 2) and SiteCombatRules.terrain_line_clear(data, cells[index], combat_goal):
				# Reaching melee range is engagement, not a failed movement path.
				# Never try to occupy the enemy's cell during recovery between blows.
				made_progress = true
				continue
		if not data.is_walkable(goal):
			continue
		# Reuse the existing legal local planner and original claim/commit arrays.
		var operator_id := combat_identity(index) if vehicle_transport != null and vehicle_transport.is_operator(combat_identity(index)) else 0
		var route_started := Time.get_ticks_usec() if combat_profile_enabled else 0
		var next_step := _common_order_route_step(index, goal, operator_id)
		_profile_combat_stage("common_order_route", route_started)
		if next_step != INVALID_CELL and _reserve_combat_step(index, next_step):
			made_progress = true
		elif _follower_combat_route_stamps.has(index):
			_clear_follower_route(index)
	if arrived and combat_order in [CombatOrder.MOVE, CombatOrder.RETREAT, CombatOrder.RETURN]:
		combat_order = CombatOrder.HOLD
		_clear_member_attack_targets()
		command_status = "到達；守位自衛"
	elif combat_order == CombatOrder.PURSUE and not made_progress and not arrived:
		pursuit_left = 0.0 # Next step closes the chase; no automatic new cycle.
	elif combat_order in [CombatOrder.MOVE, CombatOrder.RETREAT, CombatOrder.RETURN] and not made_progress:
		if _preserve_structure_order:
			command_status = "結構毀損後暫無合法通路；保留原命令與目標"
			return
		if combat_order == CombatOrder.RETREAT:
			var pair_started := Time.get_ticks_usec() if combat_profile_enabled else 0
			_retreat_pair_pending = _find_blocked_retreat_pair()
			_profile_combat_stage("blocked_retreat_pair", pair_started)
			if not _retreat_pair_pending.is_empty():
				return # The existing Grid owns this one physical, atomic exchange next tick.
		combat_order = CombatOrder.HOLD
		_clear_member_attack_targets()
		command_status = "未找到合法通路；就地自衛，等待新令"
		for index in range(cells.size()):
			if is_member(index):
				combat_slots[index] = moving_to[index] if moving_to[index] != INVALID_CELL else cells[index]

func _ranged_safe_cell(cell: Vector2i, enemies: Array, minimum_squared: float = 9.0) -> bool:
	for enemy: Dictionary in enemies:
		if cell.distance_squared_to(Vector2i(enemy.cell)) < minimum_squared:
			return false
	return combat_order != CombatOrder.PURSUE or pursuit_origin.distance_to(Vector2(cell) + Vector2.ONE * 0.5) < 20.0

func _ranged_can_shoot_from(cell: Vector2i, target: Vector2i, profile: Dictionary, friendly: Dictionary) -> bool:
	return SiteCombatRules.ranged_in_range(cell, target, float(profile.range)) \
		and SiteCombatRules.ranged_line_clear(data, cell, target) \
		and SiteCombatRules.ranged_friendly_clear(cell, target, friendly, data)

func _ranged_firing_step(index: int, target: Vector2i, profile: Dictionary, enemies: Array, friendly: Dictionary) -> Vector2i:
	var source := cells[index]
	var destination_friends := friendly.duplicate()
	destination_friends.erase(source) # This standing shooter leaves its old cell before firing from the candidate.
	var candidates: Array[Vector2i] = []
	# Local sidesteps first; fixed standoff candidates also let the original A*
	# walk around a wall. No per-person route, firing slot or threat map is kept.
	for distance in range(1, 4):
		for direction: Vector2i in TerrainData.DIRECTIONS:
			candidates.append(source + direction * distance)
	for radius: int in [3, floori(float(profile.range)) - 1]:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			candidates.append(target + direction * radius)
		var diagonal := maxi(2, floori(float(radius) / sqrt(2.0)))
		for direction: Vector2i in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			candidates.append(target + direction * diagonal)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return absi(a.x - source.x) + absi(a.y - source.y) < absi(b.x - source.x) + absi(b.y - source.y))
	var nearest := INF
	for enemy: Dictionary in enemies:
		nearest = minf(nearest, source.distance_squared_to(Vector2i(enemy.cell)))
	var searched := 0
	var checked := {}
	for candidate: Vector2i in candidates:
		if checked.has(candidate): continue
		checked[candidate] = true
		if candidate == source or not data.is_walkable(candidate) or blocks_cell(candidate) or _is_external_cell(candidate) \
			or not _ranged_safe_cell(candidate, enemies) or not _ranged_can_shoot_from(candidate, target, profile, destination_friends):
			continue
		var route := _find_local_route(source, candidate, 256)
		searched += 1
		if route.size() > 1 and _ranged_safe_cell(route[1], enemies, minf(9.0, nearest + 0.5)):
			return route[1]
		if searched >= MAX_LOCAL_PATHS_PER_STEP: break
	return INVALID_CELL

func _update_ranged_orders() -> void:
	if not exchange_enabled or not combat_attacking or combat_order not in [CombatOrder.ATTACK, CombatOrder.PURSUE] \
		or needs_attack_order or is_sustain_routed() or not ranged_tactics_query.is_valid():
		return
	# The original publication contains every effective weapon and is updated
	# synchronously on equipment changes. For the exact built-in pure readers,
	# an all-melee publication proves this review has no ranged work to do.
	if get_script() == TerrainArmy and equipment_appearance_query.is_valid() and equipment_appearance_batch_query.is_valid():
		var publication_owner: Object = equipment_appearance_batch_query.get_object()
		var publication_script: Script = publication_owner.get_script() as Script if publication_owner != null else null
		var pure_controlled := not controlled_person_query.is_valid()
		if not pure_controlled:
			var control_owner: Object = controlled_person_query.get_object()
			var control_script: Script = control_owner.get_script() as Script if control_owner != null else null
			pure_controlled = control_script != null and control_script.resource_path == "res://scripts/terrain_lab/terrain_lab.gd" \
				and controlled_person_query.get_method() == &"controlled_person_id" and controlled_person_query.get_bound_arguments_count() == 0
		if pure_controlled and publication_script != null and publication_script.resource_path == "res://scripts/terrain_lab/site_controller.gd" \
			and publication_owner == equipment_appearance_query.get_object() and equipment_appearance_query.get_method() == &"person_appearance" \
			and equipment_appearance_batch_query.get_method() == &"person_appearance_batch" and equipment_appearance_query.get_bound_arguments_count() == 0 \
			and equipment_appearance_batch_query.get_bound_arguments_count() == 0:
			var publications: Dictionary = equipment_appearance_batch_query.call(equipment_appearance_query)
			# Tri-state ABI: -1 unsupported, 0 all melee, 1 confirmed ranged.
			# Re-read the borrowed publication every review; aliases can replace rows.
			var publication_state := -1
			if native_queries_enabled and equipment_appearance_query.get_unbound_arguments_count() == 0 \
				and equipment_appearance_batch_query.get_unbound_arguments_count() == 0 \
				and (not controlled_person_query.is_valid() or controlled_person_query.get_unbound_arguments_count() == 0):
				var kernel := _get_idle_kernel()
				if kernel != null and kernel.has_method("publication_ranged_state"):
					var weapon_ranged_by_id := {}
					for option: Dictionary in SiteCombatRules.WeaponMaterials.OPTIONS:
						var weapon_id := str(option.id)
						weapon_ranged_by_id[weapon_id] = not SiteCombatRules.ranged_profile(weapon_id).is_empty()
					weapon_ranged_by_id["none"] = not SiteCombatRules.ranged_profile("none").is_empty()
					var native_state: Variant = kernel.publication_ranged_state(publications, weapon_ranged_by_id)
					if typeof(native_state) == TYPE_INT and native_state in [-1, 0, 1]:
						publication_state = int(native_state)
			if publication_state == 0:
				return
			if publication_state != 1:
				# Keep the entire original guard, including coercion and its short circuit.
				var any_ranged := false
				var weapon_ranged := {}
				for published: Variant in publications.values():
					if not published is Dictionary or not published.get("parts", {}) is Dictionary:
						any_ranged = true
						break
					var weapon := str(published.get("parts", {}).get("weapon", "none"))
					if not weapon_ranged.has(weapon):
						weapon_ranged[weapon] = not SiteCombatRules.ranged_profile(weapon).is_empty()
					if bool(weapon_ranged[weapon]):
						any_ranged = true
						break
				if not any_ranged:
					return
	var scene := {}
	var enemies: Array = []
	var friendly := {}
	var searched := 0
	var begin := _planning_cursor % maxi(1, combat_units.size())
	for offset in range(combat_units.size()):
		var index := (begin + offset) % combat_units.size()
		if not is_member(index) or not combat_can_act(index) or is_controlled_person(index) or _siege_crew(index) or _ship_embarked(index): continue
		var profile := ranged_profile(index)
		if profile.is_empty(): continue
		var unit: Dictionary = combat_units[index]
		if not unit.get("work_task", {}).is_empty() or (person_busy_query.is_valid() and bool(person_busy_query.call(combat_identity(index)))): continue
		if int(unit.get("cargo", {}).get(str(profile.ammo), 0)) < 1:
			unit["status"] = "彈藥耗盡；守位自衛，等待補給"
			continue
		if moving_to[index] != INVALID_CELL or _combat_action_blocks_step(index) or _unit_rescues.has(index): continue
		if scene.is_empty():
			scene = ranged_tactics_query.call(self)
			enemies = scene.get("enemies", [])
			friendly = scene.get("friendly_cells", {})
		var target := INVALID_CELL
		var nearest := INF
		var safe_shot := false
		for enemy: Dictionary in enemies:
			if combat_order == CombatOrder.PURSUE and int(enemy.id) != pursuit_target: continue
			var cell := Vector2i(enemy.cell)
			var distance := cells[index].distance_squared_to(cell)
			if distance > 20.0 * 20.0: continue
			if distance < nearest:
				nearest = distance
				target = cell
			if _ranged_can_shoot_from(cells[index], cell, profile, friendly): safe_shot = true
		if target == INVALID_CELL:
			unit["status"] = "附近沒有可接近的遠程目標"
			continue
		if safe_shot and _ranged_safe_cell(cells[index], enemies): continue
		var step := _ranged_firing_step(index, target, profile, enemies, friendly)
		searched += 1
		if step != INVALID_CELL and _reserve_combat_step(index, step):
			combat_slots[index] = step
			unit["status"] = "拉開射擊距離" if nearest < 9.0 else "前往安全射位"
		else:
			unit["status"] = "沒有合法安全射位；原地自衛"
		_planning_cursor = (index + 1) % combat_units.size()
		if searched >= PLANNING_BUDGET: break

func _periodic_review_conflicts() -> bool:
	# The already-updated first team has just reset its existing review clock.
	# Stagger only canonical periodic work; new orders and custom owners retain
	# their original timing. No second clock, saved phase or skipped movement.
	if not periodic_review_stagger_enabled or not exchange_enabled or combat_order == CombatOrder.HOLD or get_script() != TerrainArmy or not external_blocker.is_valid() or external_blocker.get_method() != &"blocks_cell":
		return false
	var other: Object = external_blocker.get_object()
	var lab: Object = exchange_people_query.get_object() if exchange_people_query.is_valid() else null
	return other is TerrainArmy and other.get_script() == TerrainArmy and other.data == data and other.combat_enabled and other.combat_order != CombatOrder.HOLD and other._command_elapsed == 0.0 and other._order_delay == 0.0 \
		and lab is TerrainLab and lab.get_script() == TerrainLab and lab.combat_armies.find(other) >= 0 and lab.combat_armies.find(self) > lab.combat_armies.find(other)

func _canonical_geometry_prefilter_safe(query_owner: Object) -> bool:
	# Only primitive canonical readers may be skipped. No cross-review trust flag.
	if not geometry_prefilter_enabled or _combat_hot_store == null or _combat_hot_borrowed_index != -1 \
			or cells.size() != combat_units.size():
		return false
	if _combat_hot_store.get_class() != "ArmyCombatHot" or _combat_hot_store.get_script() != null:
		return false
	if int(_combat_hot_store.row_count()) != combat_units.size():
		return false
	var lab := query_owner as TerrainLab
	if lab == null or lab.get_script() != TerrainLab or lab.terrain != data or lab.character != player \
			or not person_busy_query.is_valid() \
			or not equipment_appearance_query.is_valid() or not equipment_appearance_batch_query.is_valid() \
			or not controlled_person_query.is_valid():
		return false
	var controller := person_busy_query.get_object() as SiteController
	if controller == null or controller.get_script() != SiteController or controller != lab.site_controller \
			or controller.lab != lab or vehicle_transport != controller.vehicles:
		return false
	if person_busy_query.get_method() != &"_person_has_duty" or person_busy_query.get_bound_arguments_count() != 0 \
			or person_busy_query.get_unbound_arguments_count() != 0 \
			or equipment_appearance_query.get_object() != controller or equipment_appearance_query.get_method() != &"person_appearance" \
			or equipment_appearance_query.get_bound_arguments_count() != 0 or equipment_appearance_query.get_unbound_arguments_count() != 0 \
			or equipment_appearance_batch_query.get_object() != controller or equipment_appearance_batch_query.get_method() != &"person_appearance_batch" \
			or equipment_appearance_batch_query.get_bound_arguments_count() != 0 or equipment_appearance_batch_query.get_unbound_arguments_count() != 0 \
			or controlled_person_query.get_object() != lab or controlled_person_query.get_method() != &"controlled_person_id" \
			or controlled_person_query.get_bound_arguments_count() != 0 or controlled_person_query.get_unbound_arguments_count() != 0:
		return false
	if controller.person_actions == null or controller.work_team == null or controller.vehicles == null \
			or controller.person_actions.get_script() != SitePersonActions or controller.person_actions.lab != lab \
			or controller.work_team.get_script() != SiteWorkTeam or controller.work_team.lab != lab \
			or controller.vehicles.get_script() != SiteVehicleTransport or controller.vehicles.lab != lab \
			or controller.vehicles.controller != controller:
		return false
	var captivity: Variant = data.site.get("captivity", null)
	var named_captivity: Variant = data.site.get(&"captivity", null)
	var supply: Variant = data.site.get("team_supply", {})
	var vehicles: Variant = data.site.get("vehicles", {})
	if not captivity is Dictionary or not named_captivity is Dictionary \
			or not supply is Dictionary or not vehicles is Dictionary:
		return false
	if not controller.person_actions._jobs.is_empty() or not captivity.is_empty() or not named_captivity.is_empty() \
			or not supply.is_empty() or not vehicles.is_empty():
		return false
	if data.site.has("controlled_person_id") and typeof(data.site.get("controlled_person_id")) != TYPE_INT:
		return false
	var publications: Dictionary = controller._equipment_appearances
	if publications.is_typed():
		return false
	# Validate every row before skipping any callback. The hot store's native
	# load/set/absorb admission maintains primitive HP, pose and flags.
	for row: Dictionary in combat_units:
		if row.is_typed():
			return false
		var identity: Variant = row.get("person_id")
		var work_task: Variant = row.get("work_task", {})
		if typeof(identity) != TYPE_INT or typeof(row.get(&"person_id")) != TYPE_INT \
				or not work_task is Dictionary:
			return false
		var appearance: Variant = publications.get(identity, {})
		if not appearance is Dictionary or appearance.is_typed():
			return false
		var parts: Variant = appearance.get("parts", {})
		if not parts is Dictionary or parts.is_typed():
			return false
		if typeof(parts.get("weapon", "none")) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
	return true

func _try_exchange_encirclement() -> bool:
	if data == null or bool(data.site.get("paused", false)) or (is_inside_tree() and get_tree().paused) \
		or not exchange_enabled or not combat_attacking or combat_order not in [CombatOrder.ATTACK, CombatOrder.PURSUE] \
		or needs_attack_order or is_sustain_routed() or not exchange_people_query.is_valid():
		return false
	var enemies := {}
	var contact_cells: Array[Vector2i] = []
	var pinned := {}
	var query_owner: Object = exchange_people_query.get_object()
	var front: Array = []
	if get_script() == TerrainArmy and data.get_script() == TerrainData and not is_instance_valid(player_member) \
		and query_owner is TerrainLab and query_owner.get_script() == TerrainLab \
		and exchange_people_query.get_method() == &"_exchange_people" and exchange_people_query.get_bound_arguments() == [false] \
		and exchange_people_query.get_unbound_arguments_count() == 0:
		front = query_owner._exchange_encirclement_front(self)
	if front.size() == 3:
		enemies = front[0]
		contact_cells = front[1]
		pinned = front[2]
	else:
		# Preserve callback/coercion ordering for custom queries and player teams.
		var people: Array = exchange_people_query.call()
		for person: Dictionary in people:
			if int(person.faction) != faction_id:
				enemies[Vector2i(person.cell)] = true
		for person: Dictionary in people:
			var index := int(person.unit)
			if not (person.owner == self and index >= 0 and is_member(index)) \
				and not (is_instance_valid(player_member) and person.owner == player_member):
				continue
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next: Vector2i = person.cell + direction
				if enemies.has(next) and data.can_attack_across(person.cell, next):
					contact_cells.append(person.cell)
					if person.owner == self:
						pinned[index] = true
					break
	if contact_cells.is_empty():
		return false # No automatic long-distance pursuit just because ATTACK is selected.
	encirclement_reviews += 1
	# A single bounded reverse field serves this review, not a BFS per person/goal.
	# Contact stays local, but routes must reach the rear around a dense formation.
	var distance := {}
	var pending: Array[Vector2i] = []
	# Disposable contact buckets, not another movement/target owner. Exact
	# Manhattan checks still decide membership; enemy iteration/claim order stays.
	var contact_buckets := {}
	var enemy_cells := enemies.keys() # Same Dictionary insertion order.
	var near_mask := PackedByteArray()
	if native_front_enabled:
		var kernel := _get_idle_kernel()
		if kernel != null and kernel.has_method("near_front"):
			near_mask = kernel.call("near_front", enemy_cells, contact_cells, ENCIRCLEMENT_DISTANCE)
	var native_front := near_mask.size() == enemy_cells.size()
	if native_front: native_front_cells += enemy_cells.size()
	# Only the canonical readers are pure: reject own occupancy before geometry,
	# whose can_attack_across already includes goal walkability. Keep override order.
	var pure_seed_predicates: bool = get_script() == TerrainArmy and data.get_script() == TerrainData and (vehicle_transport == null or vehicle_transport.records().is_empty())
	var external_owner: Object = external_blocker.get_object() if external_blocker.is_valid() else null
	var pure_external: bool = pure_seed_predicates and external_owner is TerrainArmy \
		and external_owner.get_script() == TerrainArmy and external_blocker.get_method() == &"blocks_cell" \
		and external_blocker.get_bound_arguments_count() == 0 and external_blocker.get_unbound_arguments_count() == 0
	var pure_occupancy := pure_external
	for actor: Variant in [player, npc]:
		if actor != null and (not actor is TerrainTestCharacter or actor.get_script() not in [TerrainTestCharacter, TerrainTestNPC]):
			pure_occupancy = false
	var occupied := {}
	if pure_occupancy:
		# These exact readers cannot mutate the map during this synchronous
		# field build. Discard the union before any later review/claim changes.
		occupied = _cell_owners.duplicate()
		occupied.merge(_reserved_cells)
		occupied.merge(external_owner._cell_owners)
		occupied.merge(external_owner._reserved_cells)
		for actor: Variant in [player, npc]:
			if actor == null: continue
			if actor.occupies_cell(actor.terrain_cell): occupied[actor.terrain_cell] = true
			if actor.occupies_cell(actor.movement_from_cell): occupied[actor.movement_from_cell] = true
	var native_field := false
	if pure_occupancy and native_front:
		var kernel := _get_idle_kernel()
		if kernel != null and kernel.has_method("encirclement_field"):
			var packet: Array = kernel.encirclement_field(enemy_cells, near_mask, data.size, data.navigation_flags(), data.navigation_heights(), data.navigation_ramps(), data.static_blocked, occupied, ENCIRCLEMENT_CELLS, ENCIRCLEMENT_ROUTE_DISTANCE)
			if packet.size() == 1:
				distance = packet[0]
				native_field = true
	# A necessary Manhattan bound rejects distant rows before bucket ranges.
	# Keep scalar ints (not an expanded Vector2i) to avoid int32 edge wrapping.
	var min_x: int = contact_cells[0].x
	var max_x: int = min_x
	var min_y: int = contact_cells[0].y
	var max_y: int = min_y
	for contact: Vector2i in contact_cells:
		min_x = mini(min_x, contact.x)
		max_x = maxi(max_x, contact.x)
		min_y = mini(min_y, contact.y)
		max_y = maxi(max_y, contact.y)
		if native_front: continue
		var bucket := Vector2i(contact.x >> 3, contact.y >> 3)
		if not contact_buckets.has(bucket): contact_buckets[bucket] = []
		contact_buckets[bucket].append(contact)
	for enemy_index in range(0 if native_field else enemy_cells.size()):
		var enemy_cell: Vector2i = enemy_cells[enemy_index]
		if native_front and near_mask[enemy_index] == 0: continue
		if enemy_cell.x < min_x - ENCIRCLEMENT_DISTANCE or enemy_cell.x > max_x + ENCIRCLEMENT_DISTANCE \
			or enemy_cell.y < min_y - ENCIRCLEMENT_DISTANCE or enemy_cell.y > max_y + ENCIRCLEMENT_DISTANCE:
			continue
		var near_front := native_front
		for bucket_y in range(0) if native_front else range((enemy_cell.y - ENCIRCLEMENT_DISTANCE) >> 3, ((enemy_cell.y + ENCIRCLEMENT_DISTANCE) >> 3) + 1):
			for bucket_x in range((enemy_cell.x - ENCIRCLEMENT_DISTANCE) >> 3, ((enemy_cell.x + ENCIRCLEMENT_DISTANCE) >> 3) + 1):
				for contact: Vector2i in contact_buckets.get(Vector2i(bucket_x, bucket_y), []):
					if absi(enemy_cell.x - contact.x) + absi(enemy_cell.y - contact.y) <= ENCIRCLEMENT_DISTANCE:
						near_front = true
						break
				if near_front: break
			if near_front: break
		if not near_front:
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var goal := enemy_cell + direction
			if distance.has(goal) or pending.size() >= ENCIRCLEMENT_CELLS:
				continue
			if pure_occupancy:
				if occupied.has(goal) or not data.can_attack_across(goal, enemy_cell): continue
			elif pure_seed_predicates:
				# Occupied enemy interiors cannot be route seeds. With the exact
				# pure blocker, reject them before repeating terrain work four times.
				if blocks_cell(goal) or (pure_external and external_owner.blocks_cell(goal)) or not data.can_attack_across(goal, enemy_cell):
					continue
			elif not data.is_walkable(goal) or not data.can_attack_across(goal, enemy_cell) or blocks_cell(goal):
				continue
			if not pure_occupancy and _is_external_cell(goal):
				continue
			distance[goal] = 0
			pending.append(goal)
	var head := 0
	while head < pending.size():
		var cell := pending[head]
		head += 1
		if int(distance[cell]) >= ENCIRCLEMENT_ROUTE_DISTANCE - 1:
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if distance.has(next) or pending.size() >= ENCIRCLEMENT_CELLS \
				or not data.can_step(next, cell) or (occupied.has(next) if pure_occupancy else (blocks_cell(next) or _is_external_cell(next))):
				continue
			distance[next] = int(distance[cell]) + 1
			pending.append(next)
	# Conservative one-review origins only: a legal candidate must be one
	# cardinal step from this exact field. Keep original eligibility/order below.
	# Small rosters use the original scan when building the filter costs more
	# entries than there are people to scan. This never changes eligibility.
	var filter_origins := distance.size() * TerrainData.DIRECTIONS.size() < combat_units.size()
	var origins := {}
	if filter_origins:
		for step_cell: Vector2i in distance:
			for direction: Vector2i in TerrainData.DIRECTIONS:
				origins[step_cell - direction] = true
	# Large fields omit the origins set. Reject only rows with no adjacent
	# field cell, after proving every skipped original reader is canonical/pure.
	var geometry_prefilter := not filter_origins and front.size() == 3 and pure_occupancy \
		and _canonical_geometry_prefilter_safe(query_owner)
	if geometry_prefilter:
		geometry_prefilter_reviews += 1
	var candidates: Array[Dictionary] = []
	for index in range(combat_units.size()):
		if filter_origins and not origins.has(cells[index]):
			continue
		if geometry_prefilter:
			var reaches_field := false
			for direction: Vector2i in TerrainData.DIRECTIONS:
				if distance.has(cells[index] + direction):
					reaches_field = true
					break
			if not reaches_field:
				geometry_prefilter_skipped += 1
				continue
		if pinned.has(index) or not is_member(index) or is_controlled_person(index) or not combat_can_act(index) \
			or moving_to[index] != INVALID_CELL or _combat_action_blocks_step(index) or _unit_rescues.has(index) \
			or _exchange_maneuver_blocked(index):
			continue
		var best := INVALID_CELL
		var cost := ENCIRCLEMENT_ROUTE_DISTANCE
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cells[index] + direction
			if distance.has(next) and int(distance[next]) < cost and data.can_step(cells[index], next):
				best = next
				cost = int(distance[next])
		if best != INVALID_CELL:
			candidates.append({"unit": index, "id": combat_identity(index), "step": best, "cost": cost})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.cost) < int(b.cost) if int(a.cost) != int(b.cost) else int(a.id) < int(b.id))
	var issued := 0
	for candidate: Dictionary in candidates:
		if issued >= ENCIRCLEMENT_STEPS:
			break
		var index := int(candidate.unit)
		# Several people may follow the same route. Only their committed next
		# cells are exclusive; a distant shared goal must not starve the queue.
		if _reserve_combat_step(index, candidate.step):
			# Keep the accepted endpoint in the original order state: losing contact
			# must not send this person back to an obsolete pre-engagement slot.
			for slot_index: int in _vacancy_assignments.keys():
				if int(_vacancy_assignments[slot_index]) == index:
					_vacancy_assignments.erase(slot_index)
			combat_slots[index] = candidate.step
			issued += 1
			encirclement_steps += 1
	return true # A blocked flank waits; it never teleports, swaps bodies or forces allies aside.

func _exchange_maneuver_blocked(index: int) -> bool:
	# Also used by contact-free vacancy/pursuit fallback, not just active flanking.
	# Explicit MOVE/RETREAT orders keep their original command semantics.
	return _siege_crew(index) or exchange_enabled and (is_controlled_person(index) or not ranged_profile(index).is_empty() \
		or not combat_units[index].get("work_task", {}).is_empty() \
		or (person_busy_query.is_valid() and bool(person_busy_query.call(combat_identity(index)))))

func _assign_combat_vacancy() -> void:
	# The replacement can itself fall. Prune its old assignment, then reserve
	# each destination once even when two fallen rows now refer to the same slot.
	var claimed_goals := {}
	for slot_index: int in _vacancy_assignments.keys():
		var assigned := int(_vacancy_assignments[slot_index])
		if not is_member(slot_index) or not is_member(assigned) or not combat_can_act(assigned) or _exchange_maneuver_blocked(assigned) or combat_slots[assigned] != combat_slots[slot_index]:
			_vacancy_assignments.erase(slot_index)
		else:
			claimed_goals[combat_slots[slot_index]] = true
	for slot_index in range(combat_units.size()):
		if not is_member(slot_index) or combat_can_act(slot_index):
			continue
		var goal: Vector2i = combat_slots[slot_index]
		if claimed_goals.has(goal) or blocks_cell(goal) or _is_external_cell(goal):
			continue
		var best := -1
		var best_cost := 257
		for index in range(combat_units.size()):
			if not is_member(index) or not combat_can_act(index) or moving_to[index] != INVALID_CELL or _combat_action_blocks_step(index) or _vacancy_assignments.values().has(index) or _exchange_maneuver_blocked(index):
				continue
			var lower_bound := absi(cells[index].x - goal.x) + absi(cells[index].y - goal.y)
			if lower_bound >= best_cost:
				continue
			var route := _find_local_route(cells[index], goal, 256)
			if route.size() > 1 and route.size() - 1 < best_cost:
				best_cost = route.size() - 1
				best = index
		if best >= 0:
			# Reassign the destination only, never the person's physical cell.
			combat_slots[best] = goal
			_vacancy_assignments[slot_index] = best
			return # One reserved destination per review; deterministic cost / ID.

static func load_combat_bake() -> bool:
	if not _combat_bake.is_empty():
		return true
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOLDIER_MANIFEST_PATH))
	if not manifest is Dictionary or int(manifest.get("schema_version", 0)) != 2:
		return false
	# Baked collision remains an offline regression reference. Runtime collision
	# now comes from exact original animation poses, so do not load that second
	# full armor/geometry table merely to select presentation frames.
	var frames := {}
	var clips := {}
	for frame: Dictionary in manifest.frames:
		var key := "%s|%s|%d" % [frame.clip, frame.direction, int(frame.frame)]
		if frames.has(key) or int(frame.collision_index) < 0 or int(frame.collision_index) >= manifest.frames.size():
			return false
		frames[key] = frame
	for clip: Dictionary in manifest.clips:
		clips[str(clip.id)] = clip
	for pose: String in HELD_LOCOMOTION:
		var clip: String = HELD_LOCOMOTION[pose]
		if not clips.has(clip) or str(clips[clip].get("pose", "")) != pose or not bool(clips[clip].get("combat_ready", false)) or int(clips[clip].get("samples", 0)) <= 0:
			return false
		for direction: String in ["down", "left", "up", "right"]:
			for sample in range(int(clips[clip].samples)):
				if not frames.has("%s|%s|%d" % [clip, direction, sample]):
					return false
	if not clips.has("attack_jump_heavy") or int(clips.attack_jump_heavy.get("samples", 0)) != 12:
		return false # Big exchange wins require a real shared-atlas jump clip.
	for direction: String in ["down", "left", "up", "right"]:
		for sample in range(12):
			if not frames.has("attack_jump_heavy|%s|%d" % [direction, sample]):
				return false
	# Immutable atlas clock metadata, not a collision/pose table. Retain each
	# direction's actual endpoints and original alias; never quantize runtime time.
	var contact_clocks := {}
	for clip: String in clips:
		contact_clocks[clip] = {}
		for direction: String in ["down", "left", "up", "right"]:
			var first: Dictionary = frames.get("%s|%s|0" % [clip, direction], {})
			var last: Dictionary = frames.get("%s|%s|%d" % [clip, direction, int(clips[clip].samples) - 1], {})
			if first.is_empty() or last.is_empty():
				continue # Preserve existing loading checks and missing-frame failure.
			var samples: Array = []
			for frame_index in range(int(clips[clip].samples)):
				# References to original descriptors, not copied pixels/collision data.
				samples.append(frames.get("%s|%s|%d" % [clip, direction, frame_index]))
			contact_clocks[clip][direction] = [StringName(str(clips[first.clip].get("pose", first.clip))),
				float(first.duration), float(last.sample_time) < float(first.duration) - 0.000001, samples]
	_combat_bake = {"manifest": manifest, "frames": frames, "clips": clips, "contact_clocks": contact_clocks}
	return true

func enable_combat(attacking: bool = true, female_count: int = -1, troop_type: StringName = TROOP_TYPE_ID) -> bool:
	if female_count < -1 or female_count > roster_size or troop_type not in [TROOP_TYPE_ID, &"bow", &"crossbow"]:
		return false
	if not has_army() or moving_count() > 0 or command != Command.NONE or not load_combat_bake() or (not exchange_enabled and not load_contact_source(player.editor if is_instance_valid(player) else null)):
		return false
	if combat_units.is_empty():
		var allocated: Array = person_id_allocator.call(roster_size) if person_id_allocator.is_valid() else []
		if person_id_allocator.is_valid() and not valid_person_ids(allocated, roster_size):
			return false
		for index in range(roster_size):
			var female := index == 0
			if female_count >= 0:
				female = female_count > 0 if index == 0 else floori(float(index * maxi(0, female_count - 1)) / maxi(1, roster_size - 1)) > floori(float((index - 1) * maxi(0, female_count - 1)) / maxi(1, roster_size - 1))
			combat_units.append({"person_id": int(allocated[index]) if not allocated.is_empty() else 1000 + team_id * SOLDIER_COUNT + index,
				"visual_role": ("female_live" if female else "male_live") if index == 0 else ("female_atlas" if female else "male_atlas"), "hp": 100.0, "stun": 0.0, "grace": 0.0, "ko": 0.0,
				"fatigue": 0.0, "fatigue_rest": 0.0, "combat_ability": TROOP_COMBAT_ABILITY,
				"attack_reduction": 0.0, "attack_fatigue": 0.0,
				"pose": "idle", "age": 0.0, "attack": false, "blocked": false, "hits": {},
				"previous": [], "think": 0.0, "status": "Ready", "target": -1,
				"captive": false, "departed": false, "site_exited": false, "surrender_pending": false,
				"present": false, "member": true, "logistics": false, "military_role": "officer" if index == 0 else "soldier"})
			combat_units[index].appearance = EquipmentAtlas.female_appearance() if female else _combat_bake.manifest.appearance.duplicate(true)
			if troop_type != TROOP_TYPE_ID:
				combat_units[index].appearance.parts.weapon = "bow_01" if troop_type == &"bow" else "crossbow_01"
				combat_units[index].appearance.parts.shield = "none"
		_invalidate_combat_identity_cache()
		_initialize_combat_command()
	# Original public enable_combat can be called directly after deploy_at.
	# Prepare completed real row appearances before any contact/render query;
	# siege exact contact also needs them when ordinary exchange mode is on.
	for index in range(combat_units.size()):
		if _uses_live_contact_presenter(index): continue
		var appearance: Dictionary = equipment_appearance(index)
		if appearance.is_empty(): appearance = combat_units[index].get("appearance", {})
		if not prepare_contact_source_for(appearance, player.editor if is_instance_valid(player) else null): return false
	_move_encounters.clear()
	_move_landed_members.clear()
	combat_enabled = true
	sync_shared_fatigue(true)
	combat_attacking = attacking
	combat_order = CombatOrder.ATTACK if attacking else CombatOrder.HOLD
	settle_combat_command()
	command_status = "接敵；前排牽制、後排尋找側後方空位" if attacking else "守位"
	_refresh_deferred_captain()
	_ensure_live_presenters()
	if equipment_initializer.is_valid():
		equipment_initializer.call(self)
	_refresh_deferred_captain()
	_ensure_live_presenters()
	if native_hot_enabled: _try_install_combat_hot_store()
	if _batch_render_active() and _soldier_baked_ready:
		_rebuild_visual_instances()
	_visual_dirty = true
	return true

static func _retain_contact_sources_until_exit() -> void:
	if DisplayServer.get_name() == "headless": return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.root.tree_exiting.is_connected(release_contact_source):
		tree.root.tree_exiting.connect(release_contact_source, CONNECT_ONE_SHOT)

static func load_contact_source(reference: HumanCharacter3DEditor = null) -> bool:
	_retain_contact_sources_until_exit()
	if _contact_source != null and is_instance_valid(_contact_source.editor):
		return true
	if not load_combat_bake():
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	_contact_source = ContactSource.new()
	if not _contact_source.initialize(tree.root, _combat_bake.manifest.appearance, reference):
		release_contact_source()
		return false
	return true

static func prepare_contact_source_for(appearance: Dictionary, reference: HumanCharacter3DEditor = null) -> bool:
	# Deployment/load preparation only. Queries below never instantiate a rig.
	if not HumanCharacter3DEditor.valid_appearance(appearance) or bool(appearance.mounted): return false
	_retain_contact_sources_until_exit()
	var body := int(appearance.body)
	if body == 0:
		return load_contact_source(reference) and _contact_source.supports_appearance(appearance)
	var source: RefCounted = _body_contact_sources.get(body)
	if source != null and is_instance_valid(source.editor): return source.supports_appearance(appearance)
	if source != null: source.dispose()
	_body_contact_sources.erase(body)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return false
	source = ContactSource.new()
	if not source.initialize(tree.root, appearance, reference):
		source.dispose()
		return false
	_body_contact_sources[body] = source
	return true

static func contact_source_for(appearance: Dictionary) -> RefCounted:
	# Preserve the original strict same-body/mounted/part guard.
	if not HumanCharacter3DEditor.valid_appearance(appearance) or bool(appearance.mounted): return null
	var body := int(appearance.body)
	var source: RefCounted = _contact_source if body == 0 else _body_contact_sources.get(body)
	return source if source != null and source.supports_appearance(appearance) else null

static func clear_contact_samples() -> void:
	# Deployment/load preparation happens before queries; retain the original
	# lifetime for every same-body resource, including the existing male source.
	if _contact_source != null:
		_contact_source.clear_samples()
	for source: RefCounted in _body_contact_sources.values(): source.clear_samples()

static func begin_contact_step() -> void:
	if _contact_source != null:
		_contact_source.begin_contact_step()
	for source: RefCounted in _body_contact_sources.values(): source.begin_contact_step()

static func clear_contact_sources_for_bind() -> void:
	# Candidate/preflight already admitted these same-body root-owned resources.
	# They retain no person, position, Site or simulation clock. Clearing samples
	# preserves admission through atomic replacement without rebuilding a rig.
	clear_contact_samples()
	release_captain_geometry_pool()

static func release_contact_source() -> void:
	if _contact_source != null:
		_contact_source.dispose()
	_contact_source = null
	for source: RefCounted in _body_contact_sources.values(): source.dispose()
	_body_contact_sources.clear()
	release_captain_geometry_pool()

static func release_captain_geometry_pool() -> void:
	for entry: Dictionary in _captain_geometry_pool.values():
		var editor: Variant = entry.get("editor")
		if is_instance_valid(editor):
			if is_instance_valid(editor.preview_viewport): editor.preview_viewport.queue_free()
			editor.queue_free()
		var sprite: Variant = entry.get("sprite")
		if is_instance_valid(sprite): sprite.queue_free()
	_captain_geometry_pool.clear()

func combat_identity(index: int) -> int:
	if index == PLAYER_MEMBER and is_instance_valid(player_member):
		return player_member.combat_identity()
	return int(combat_units[index].person_id) if index >= 0 and index < combat_units.size() else -1

func _invalidate_combat_identity_cache() -> void:
	_combat_identity_indices.clear()
	_combat_identity_index_count = -1

func index_for_identity(identity: int) -> int:
	return combat_hot_index_for_identity(identity)

static func valid_person_ids(identities: Array, expected: int) -> bool:
	if identities.size() != expected:
		return false
	var seen := {}
	for identity: Variant in identities:
		if not _combat_saved_integer(identity, 1, 2147483647) or int(identity) == PLAYER_MEMBER or seen.has(int(identity)):
			return false
		seen[int(identity)] = true
	return true

static func normalize_roster_snapshot(original: Dictionary) -> Dictionary:
	var snapshot := original.duplicate(true)
	if not snapshot.has("garrison_feature_id"): snapshot["garrison_feature_id"] = ""
	var appointed: Array = [int(snapshot.get("formal_commander", -1)), int(snapshot.get("acting_commander", -1)), int(snapshot.get("current_commander", -1))]
	if snapshot.get("officers") is Array: appointed.append_array(snapshot.officers)
	if snapshot.get("officer_service") is Array: appointed.append_array(snapshot.officer_service)
	if snapshot.get("units") is Array:
		for index in range(snapshot.units.size()):
			if snapshot.units[index] is Dictionary and not snapshot.units[index].has("military_role"):
				snapshot.units[index].military_role = "officer" if appointed.has(index) else "soldier"
	if snapshot.get("schema") == 1 and snapshot.get("units") is Array:
		var legacy_ko_valid := true
		for row: Variant in snapshot.units:
			if not row is Dictionary or not TerrainTestCharacter._saved_number(row.get("ko"), 0.0, SiteCombatRules.LEGACY_KNOCKOUT_ACTION_SECONDS):
				legacy_ko_valid = false
				break
		if legacy_ko_valid:
			for row: Dictionary in snapshot.units:
				row.ko = float(row.ko) / SiteCombatRules.LEGACY_KNOCKOUT_ACTION_SECONDS * SiteCombatRules.KNOCKOUT_GAME_SECONDS
			snapshot["schema"] = 2
	if snapshot.get("units") is Array:
		for row: Variant in snapshot.units:
			# Old headless saves labelled the live captain female but stored the
			# male appearance. Preserve the actual body, not the obsolete label.
			if not snapshot.has("visual_version") and row is Dictionary and row.get("visual_role") == "female_live" and row.get("appearance") is Dictionary and row.appearance.get("body") == 0:
				row.visual_role = "male_live"
			if row is Dictionary and not row.has("member"):
				row["member"] = true # Existing original rows were all logical members.
			if row is Dictionary and not row.has("logistics"):
				row["logistics"] = false # Existing soldiers were not assigned logistics.
			if row is Dictionary and not row.has("site_exited"):
				row["site_exited"] = false
			if row is Dictionary and not row.has("surrender_pending"):
				row["surrender_pending"] = false
	if snapshot.has("roster_version"):
		return snapshot
	if not snapshot.get("units") is Array or snapshot.units.size() != SOLDIER_COUNT or not _combat_saved_integer(snapshot.get("team_id"), 1, 999999):
		return snapshot # Invalid legacy state stays invalid; never invent missing people.
	snapshot["roster_version"] = 1
	for index in range(snapshot.units.size()):
		if not snapshot.units[index] is Dictionary:
			return original.duplicate(true)
		snapshot.units[index].person_id = 1000 + int(snapshot.team_id) * SOLDIER_COUNT + index
		var appearance: Variant = snapshot.units[index].get("appearance", {})
		if not appearance is Dictionary:
			return original.duplicate(true)
		var body_value: Variant = appearance.get("body", 1 if index == 0 else 0)
		if not _combat_saved_integer(body_value, 0, 1):
			return original.duplicate(true)
		var body := int(body_value)
		snapshot.units[index].visual_role = ("female_live" if body == 1 else "male_live") if index == 0 else ("female_atlas" if body == 1 else "male_atlas")
	for field: String in ["formal_commander", "acting_commander", "current_commander"]:
		if snapshot.get(field) == SOLDIER_COUNT:
			snapshot[field] = PLAYER_MEMBER
	for field: String in ["officers", "officer_service"]:
		if snapshot.get(field) is Array:
			for index in range(snapshot[field].size()):
				if snapshot[field][index] == SOLDIER_COUNT:
					snapshot[field][index] = PLAYER_MEMBER
	if snapshot.get("rescues") is Array:
		for entry: Variant in snapshot.rescues:
			if entry is Dictionary and entry.get("patient") == SOLDIER_COUNT:
				entry.patient = PLAYER_MEMBER
	return snapshot

static func snapshot_person_ids(original: Dictionary) -> Array:
	var snapshot := normalize_roster_snapshot(original)
	var identities: Array = []
	for unit: Variant in snapshot.get("units", []):
		identities.append(unit.get("person_id", -1) if unit is Dictionary else -1)
	return identities

func living_member_count() -> int:
	var count := 0
	for index: int in command_members():
		count += int(not member_gone(index))
	return count

func roster_change_ready() -> bool:
	if _team_ship_activity(): return false
	if not combat_enabled or data == null or (is_inside_tree() and get_tree().paused) or moving_count() > 0 or command != Command.NONE or combat_order != CombatOrder.HOLD or float(data.site.get("combat_left", 0.0)) > 0.0 or not _unit_rescues.is_empty() or not _external_rescuers.is_empty():
		return false
	if is_instance_valid(player_member) and (player_member.is_moving() or player_member.action_time > 0.0 or player_member._rescue_left > 0.0):
		return false
	for index in range(combat_units.size()):
		if bool(combat_hot_get(index, &"attack")) or str(combat_hot_get(index, &"pose")) not in ["idle", "down", "unconscious"]:
			return false
	return true

func _roster_metadata() -> Dictionary:
	var metadata := {"formal": combat_identity(formal_commander), "acting": combat_identity(acting_commander),
		"current": combat_identity(current_commander), "officers": [], "service": [], "abilities": {},
		"facing": {}, "slots": {}, "rng": command_rng.state, "needs_order": needs_attack_order,
		"player": player_member, "player_goal": player_goal, "player_present": player_present,
		"formation_preset_id": formation_preset_id, "tactical_ai": _capture_tactical_ai_state(), "garrison_feature_id": garrison_feature_id}
	for index in range(combat_units.size()):
		metadata.facing[combat_identity(index)] = facing[index]
		metadata.slots[combat_identity(index)] = combat_slots[index]
	for index: int in command_abilities:
		metadata.abilities[combat_identity(index)] = command_abilities[index]
	for index: int in officer_order:
		metadata.officers.append(combat_identity(index))
	for index: int in officer_service:
		metadata.service.append(combat_identity(index))
	return metadata

func _install_roster(rows: Array[Dictionary], positions: Array[Vector2i], metadata: Dictionary, shared_training: float) -> void:
	# Only rebuild index-derived navigation; the actual person dictionaries move,
	# keeping item/cargo/task references, HP, KO clocks, fatigue and capabilities.
	# Offices belong to this team, not to the moved people: keep them (and their
	# duty_ai choice) across the rebuild. Holders who left are vacated on next use;
	# a brand-new team still starts from its own default (OFFICE plan 6.3, D17).
	var own_offices := offices
	clear()
	training = shared_training
	if rows.is_empty():
		return
	offices = own_offices
	garrison_feature_id = str(metadata.get("garrison_feature_id", ""))
	formation_preset_id = str(metadata.get("formation_preset_id", "auto"))
	_restore_tactical_ai_state(metadata.get("tactical_ai", {}))
	combat_units.assign(rows)
	_invalidate_combat_identity_cache()
	_deploy_selected(positions)
	combat_slots.assign(positions)
	combat_enabled = true
	command_rng.state = int(metadata.rng)
	player_member = metadata.get("player")
	player_goal = metadata.get("player_goal", INVALID_CELL)
	player_present = bool(metadata.get("player_present", false))
	_cell_owners.clear()
	for index in range(rows.size()):
		var identity := combat_identity(index)
		facing[index] = metadata.facing.get(identity, Vector2i.DOWN)
		combat_slots[index] = metadata.slots.get(identity, positions[index])
		if not _ship_embarked(index) and float(rows[index].hp) > 0.0 and float(rows[index].ko) <= 0.0 and not bool(rows[index].departed) and not bool(rows[index].get("site_exited", false)):
			_cell_owners[positions[index]] = index
		if metadata.abilities.has(identity):
			command_abilities[index] = metadata.abilities[identity]
	for identity: int in metadata.officers:
		var index := index_for_identity(identity)
		if index >= 0:
			officer_order.append(index)
	for identity: int in metadata.service:
		var index := index_for_identity(identity)
		if index >= 0:
			officer_service.append(index)
	formal_commander = index_for_identity(int(metadata.formal))
	acting_commander = index_for_identity(int(metadata.acting))
	current_commander = index_for_identity(int(metadata.current))
	_head_established = formal_commander >= 0 or bool(metadata.get("established", false)) # Split teams name theirs explicitly (3.5).
	_last_holders.clear()
	for seat: Dictionary in offices.get("positions", []):
		if not bool(seat.head) and int(seat.holder) > 0 and index_for_identity(int(seat.holder)) >= 0: _last_holders[int(seat.holder)] = str(seat.get("office_class", "military"))
	_mark_serving_dirty()
	needs_attack_order = bool(metadata.needs_order)
	command_radius = 8.0
	var centre := Vector2.ZERO
	var member_count := 0
	for index in range(positions.size()):
		if is_member(index):
			centre += Vector2(positions[index])
			member_count += 1
	centre /= maxf(1.0, member_count)
	for index in range(positions.size()):
		if is_member(index):
			command_radius = maxf(command_radius, centre.distance_to(Vector2(positions[index])) + 2.0)
	_command_dirty = true
	settle_combat_command()
	sync_shared_fatigue(true)
	if native_hot_enabled: _try_install_combat_hot_store()
	_refresh_deferred_captain()
	_rebuild_visual_instances()

## v2 plan 3.5: posts belong to the organization and never travel with people.
## Movers leave their source posts vacant and arrive as ordinary members; the
## receiving team's cadre comes only from its own posts. A new split team names
## its captain explicitly (`new_captain_id`, a moving officer); when omitted, the
## single moving officer is that captain, and with none the new captaincy stays
## vacant (no copied lists, no random founding).
func transfer_members_to(recipient: TerrainArmy, identities: Array[int], requester: int, recipient_requester: int = -1, new_captain_id: int = -1, retired_rows: bool = false) -> Dictionary:
	if not garrison_feature_id.is_empty() or recipient != null and not recipient.garrison_feature_id.is_empty():
		return SiteRuntime.fail("GARRISONED", "駐營名冊只能經原軍營編成交易轉移")
	if vehicle_transport != null and (vehicle_transport.has_team_vehicles(self) or recipient != null and vehicle_transport.has_team_vehicles(recipient)):
		return SiteRuntime.fail("VEHICLES_ATTACHED", "車隊首版不拆併；請先停泊並解除車輛歸隊，人物與貨物未修改")
	if recipient == null or recipient == self or identities.is_empty() or not roster_change_ready():
		return SiteRuntime.fail("BUSY", "須先停止、脫戰並收束人物動作")
	if requester < 0 or requester != PLAYER_MEMBER and not is_member(requester):
		return SiteRuntime.fail("NO_AUTHORITY", "只有當前合格指揮者可調整名冊")
	# team.roster may be a 文官 seat: the resolver checks fitness, not officer rank.
	var roster_refused := duty_authority("team.roster", combat_identity(requester))
	if not roster_refused.is_empty():
		return roster_refused
	var existing := recipient.has_army()
	if recipient.team_id < 1 or recipient.team_id > 999999 or recipient.team_id == team_id or recipient.faction_id != faction_id or existing and recipient.data != data or not existing and (not recipient.cells.is_empty() or not recipient.combat_units.is_empty()):
		return SiteRuntime.fail("INVALID_TEAM", "須指定同地圖、同陣營且不同編號的接收隊伍")
	if existing and (not recipient.roster_change_ready() or recipient_requester < 0 \
		or recipient.combat_identity(recipient_requester) != recipient.duty_decider("team.roster")):
		return SiteRuntime.fail("NO_AUTHORITY", "接收隊伍也須停止並由其名冊職責負責者確認")
	if not valid_person_ids(identities, identities.size()) or recipient.combat_units.size() + identities.size() > MAX_ROSTER_SIZE:
		return SiteRuntime.fail("INVALID_MEMBERS", "人物不能重複或超過單一 Site 的 200 人驗收上限")
	var selected := {}
	for identity: int in identities:
		var index := index_for_identity(identity)
		if index < 0 or index == PLAYER_MEMBER or is_member(index) == retired_rows or recipient.index_for_identity(identity) >= 0:
			return SiteRuntime.fail("INVALID_MEMBERS", "只能轉移原名冊中的 NPC；玩家沿原入退隊入口")
		selected[identity] = true
	if identities.size() == combat_units.size() and is_instance_valid(player_member):
		return SiteRuntime.fail("PLAYER_MEMBER", "請先自行處理玩家原入退隊身分，不能隨合併搬動玩家")
	var source_meta := _roster_metadata()
	var target_meta := recipient._roster_metadata() if existing else source_meta.duplicate(true)
	if not existing:
		target_meta["player"] = null
		target_meta["player_goal"] = INVALID_CELL
		target_meta["player_present"] = false
		target_meta.erase("tactical_ai") # A new split team never inherits automatic command consent.
		var captain := new_captain_id
		if captain < 0:
			var moving_officers: Array[int] = []
			for identity: int in identities:
				var index := index_for_identity(identity)
				if index >= 0 and military_role(index) == "officer" and not member_gone(index): moving_officers.append(identity)
			if moving_officers.size() > 1:
				return SiteRuntime.fail("NEEDS_CAPTAIN", "拆出名單有多名軍官：須明確指定新隊隊長")
			captain = moving_officers[0] if moving_officers.size() == 1 else -1
		elif not selected.has(captain) or military_role(index_for_identity(captain)) != "officer" or member_gone(index_for_identity(captain)):
			return SiteRuntime.fail("NOT_ELIGIBLE", "新隊隊長須是本次拆出的在世軍官")
		target_meta["formal"] = captain
		target_meta["acting"] = -1
		target_meta["current"] = captain
		target_meta["officers"] = []
		target_meta["service"] = []
		target_meta["established"] = true # No founding pick: vacant until a real claim.
	else:
		for field: String in ["facing", "slots", "abilities"]:
			target_meta[field].merge(source_meta[field], false)
	var kept: Array[Dictionary] = []
	var kept_cells: Array[Vector2i] = []
	var incoming: Array[Dictionary] = []
	var incoming_cells: Array[Vector2i] = []
	var incoming_living := 0
	for index in range(combat_units.size()):
		if selected.has(combat_identity(index)):
			incoming.append(combat_units[index])
			incoming_cells.append(cells[index])
			incoming_living += int(not member_gone(index) and is_member(index))
		else:
			kept.append(combat_units[index])
			kept_cells.append(cells[index])
	var target_rows := recipient.combat_units.duplicate()
	var target_cells := recipient.cells.duplicate()
	target_rows.append_array(incoming)
	target_cells.append_array(incoming_cells)
	var exemptions: Array = target_meta.officers.duplicate()
	exemptions.append(int(target_meta.formal))
	var guard_rows: Array[Dictionary] = []
	if existing: guard_rows = recipient.materialized_combat_rows()
	var source_logical_rows := materialized_combat_rows()
	for index in range(combat_units.size()):
		if selected.has(combat_identity(index)):
			guard_rows.append(source_logical_rows[index])
	if single_troop_class(guard_rows, data, exemptions, recipient._troop_actor(recipient.player_member) if existing else {}) == &"mixed":
		return SiteRuntime.fail("MIXED_TROOP", "接收後普通隊員將混合兵種；名冊、職務、供養與實物未改")
	if cape_departure_guard.is_valid():
		for identity: int in identities:
			if identity in [int(target_meta.formal), int(target_meta.current)] or target_meta.officers.has(identity) or target_meta.service.has(identity): continue
			var cape_guard: Dictionary = cape_departure_guard.call(identity)
			if not cape_guard.ok: return cape_guard
	var target_living := recipient.living_member_count()
	var target_training := training if not existing else (recipient.training * target_living + training * incoming_living) / maxf(1.0, target_living + incoming_living)
	var source_training := training
	if roster_transfer_hook.is_valid():
		var supply_result: Dictionary = roster_transfer_hook.call(self, recipient, identities)
		if not bool(supply_result.get("ok", false)):
			return supply_result
	# These original Dictionary objects move between rosters. Restore their hot
	# fields only after all fallible guards/hooks, immediately before the commit.
	_release_combat_hot_store(true)
	if existing: recipient._release_combat_hot_store(true)
	_transfer_presenters(recipient, identities)
	recipient.data = data
	recipient.player = player
	recipient.npc = npc
	_install_roster(kept, kept_cells, source_meta, source_training)
	recipient._install_roster(target_rows, target_cells, target_meta, target_training)
	return SiteRuntime.ok("已轉移 %d 名原人物；位置、生命與持物不變；隊伍疲勞按全體存活成員人數加權" % identities.size())

## R3 §6.3: political adoption moves ONE original row into a destination team
## of the adopting faction as a non-member (member=false: recruitment is a
## separate entry). SitePoliticalAdoption authorizes and preflights the whole
## transaction; this only checks containers. Ordinary same-faction transfer
## rules are untouched; no other row or team faction changes.
func adoption_row_check(recipient: TerrainArmy, person_id: int) -> Dictionary:
	if not garrison_feature_id.is_empty(): return SiteRuntime.fail("GARRISON_PENDING", "駐營原人政治移交尚未准入；保留拘押")
	if not roster_change_ready(): return SiteRuntime.fail("BUSY", "來源隊伍須停止、HOLD 並收束原作業")
	var index := index_for_identity(person_id)
	if index < 0 or index == PLAYER_MEMBER: return SiteRuntime.fail("NO_TARGET", "須為原名冊中的 NPC 原人物")
	if recipient == null or recipient == self or not recipient.has_army() or not recipient.combat_enabled \
		or not recipient.garrison_feature_id.is_empty() or recipient.data != data or recipient.has_ship_journey():
		return SiteRuntime.fail("INVALID_TEAM", "須有同地圖、未駐營、可用的原接收隊伍")
	if recipient.index_for_identity(person_id) >= 0 or recipient.combat_units.size() + 1 > MAX_ROSTER_SIZE:
		return SiteRuntime.fail("NO_SPACE", "接收隊伍名冊已滿或已有此人")
	if not recipient.roster_change_ready(): return SiteRuntime.fail("BUSY", "接收隊伍須停止、HOLD 並脫戰")
	return SiteRuntime.ok("", {"index": index})

## Commit half (no fallible step): rows, presenter and metadata move; the row
## arrives free (captive=false) and outside the roster (member=false).
func adopt_row_into(recipient: TerrainArmy, person_id: int) -> void:
	var source_meta := _roster_metadata()
	var target_meta := recipient._roster_metadata()
	var kept: Array[Dictionary] = []
	var kept_cells: Array[Vector2i] = []
	_release_combat_hot_store(true)
	recipient._release_combat_hot_store(true)
	var moving: Dictionary = {}
	var moving_cell := INVALID_CELL
	for index in range(combat_units.size()):
		if combat_identity(index) == person_id:
			moving = combat_units[index]
			moving_cell = cells[index]
		else:
			kept.append(combat_units[index])
			kept_cells.append(cells[index])
	moving.member = false
	moving.captive = false
	moving.present = false
	var target_rows := recipient.combat_units.duplicate()
	var target_cells := recipient.cells.duplicate()
	target_rows.append(moving)
	target_cells.append(moving_cell)
	var ids: Array[int] = [person_id]
	_transfer_presenters(recipient, ids)
	_install_roster(kept, kept_cells, source_meta, training)
	recipient._install_roster(target_rows, target_cells, target_meta, recipient.training)

func split_members_to(recipient: TerrainArmy, identities: Array[int], requester: int, new_captain_id: int = -1) -> Dictionary:
	if recipient == null or recipient.has_army():
		return SiteRuntime.fail("INVALID_TEAM", "拆分須使用空的接收隊伍")
	return transfer_members_to(recipient, identities, requester, -1, new_captain_id)

func merge_into(recipient: TerrainArmy, requester: int, recipient_requester: int) -> Dictionary:
	var identities: Array[int] = []
	for index in range(combat_units.size()):
		if is_member(index):
			identities.append(combat_identity(index))
	return transfer_members_to(recipient, identities, requester, recipient_requester)

func combat_can_act(index: int) -> bool:
	if index < 0 or index >= combat_units.size(): return false
	if bool(combat_hot_get(index, &"site_exited", false)) or bool(combat_hot_get(index, &"surrender_pending", false)): return false
	if combat_hot_active() and index != _combat_hot_borrowed_index and get_script() == TerrainArmy and _combat_hot_store.has_method("can_act"):
		return bool(_combat_hot_store.can_act(index))
	return float(combat_hot_get(index, &"hp")) > 0.0 and float(combat_hot_get(index, &"ko")) <= 0.0 and str(combat_hot_get(index, &"pose")) != "get_up" and not bool(combat_hot_get(index, &"captive")) and not bool(combat_hot_get(index, &"departed"))

func combat_hot_get(index: int, field: StringName, default: Variant = null) -> Variant:
	if _combat_hot_store != null and index != _combat_hot_borrowed_index and COMBAT_HOT_FIELDS.has(field):
		return _combat_hot_store.get_field(index, String(field), default)
	if combat_hot_diagnostics_enabled and COMBAT_HOT_FIELDS.has(field):
		_combat_hot_dictionary_reads += 1
		if index != _combat_hot_borrowed_index: _combat_hot_dictionary_unscoped_reads += 1
	return combat_units[index].get(String(field), default)

func combat_hot_has(index: int, field: StringName) -> bool:
	if _combat_hot_store != null and index != _combat_hot_borrowed_index and COMBAT_HOT_FIELDS.has(field):
		return bool(_combat_hot_store.has_field(index, String(field)))
	if combat_hot_diagnostics_enabled and COMBAT_HOT_FIELDS.has(field):
		_combat_hot_dictionary_reads += 1
		if index != _combat_hot_borrowed_index: _combat_hot_dictionary_unscoped_reads += 1
	return combat_units[index].has(String(field))

func combat_hot_set(index: int, field: StringName, value: Variant) -> void:
	if _active_member_scope and field in [&"member", &"hp", &"ko", &"pose", &"site_exited", &"surrender_pending"]:
		_invalidate_active_member_read_scope()
	if _combat_hot_store != null and index != _combat_hot_borrowed_index and COMBAT_HOT_FIELDS.has(field):
		var hot_stored: bool = bool(_combat_hot_store.set_field(index, field, value))
		assert(hot_stored)
		if field in [&"hp", &"ko", &"pose", &"attack", &"exchange_visual", &"member", &"departed", &"captive", &"site_exited", &"surrender_pending"]:
			_mark_visual_row(index)
		return
	if combat_hot_diagnostics_enabled and COMBAT_HOT_FIELDS.has(field):
		_combat_hot_dictionary_writes += 1
		if index != _combat_hot_borrowed_index: _combat_hot_dictionary_unscoped_writes += 1
	var row: Dictionary = combat_units[index]
	if index == _combat_hot_borrowed_index:
		# A borrowed owner can retain a String or StringName hot key. Reuse its
		# exact key type; a new dot-style field is a StringName.
		var key: Variant = field
		for existing: Variant in row.keys():
			if typeof(existing) in [TYPE_STRING, TYPE_STRING_NAME] and String(existing) == String(field):
				key = existing
				break
		row[key] = value
	else:
		var key: Variant = field
		if not (field in [&"exchange_visual", &"exchange_pose_duration"] and not row.has(String(field))):
			key = String(field)
		row[key] = value

func combat_hot_erase(index: int, field: StringName) -> void:
	if _active_member_scope and field in [&"member", &"hp", &"ko", &"pose", &"site_exited", &"surrender_pending"]:
		_invalidate_active_member_read_scope()
	if _combat_hot_store != null and index != _combat_hot_borrowed_index and COMBAT_HOT_FIELDS.has(field):
		var hot_erased: bool = bool(_combat_hot_store.erase_field(index, String(field)))
		assert(hot_erased)
		if field == &"exchange_visual": _mark_visual_row(index)
		return
	if combat_hot_diagnostics_enabled and COMBAT_HOT_FIELDS.has(field):
		_combat_hot_dictionary_writes += 1
		if index != _combat_hot_borrowed_index: _combat_hot_dictionary_unscoped_writes += 1
	combat_units[index].erase(field)
	combat_units[index].erase(String(field))

func combat_hot_active() -> bool:
	return _combat_hot_store != null and int(_combat_hot_store.row_count()) == combat_units.size()

func combat_hot_column(field: StringName) -> PackedFloat64Array:
	if not COMBAT_HOT_NUMBERS.has(field) and not COMBAT_HOT_COLUMN_FLAGS.has(field):
		return PackedFloat64Array()
	if _combat_hot_store != null:
		return _combat_hot_store.column(String(field))
	var values := PackedFloat64Array()
	values.resize(combat_units.size())
	for index in range(combat_units.size()):
		var value: Variant = combat_units[index].get(String(field), field == &"member")
		values[index] = (1.0 if bool(value) else 0.0) if COMBAT_HOT_COLUMN_FLAGS.has(field) else float(value)
	return values

func combat_hot_index_for_identity(identity: int) -> int:
	if is_instance_valid(player_member) and identity == player_member.person_id:
		return PLAYER_MEMBER
	# A legacy row may be edited in place. Only the admitted roster uses the
	# cached lookup; it still validates hits and rescans misses for that case.
	if not combat_hot_active():
		for index in range(combat_units.size()):
			if combat_identity(index) == identity:
				return index
		return -1
	if _combat_identity_index_count != combat_units.size():
		_invalidate_combat_identity_cache()
		for index in range(combat_units.size()):
			var key := combat_identity(index)
			if not _combat_identity_indices.has(key):
				_combat_identity_indices[key] = index
		_combat_identity_index_count = combat_units.size()
	var cached := int(_combat_identity_indices.get(identity, -1))
	if cached >= 0 and combat_identity(cached) == identity:
		return cached
	if cached >= 0:
		_invalidate_combat_identity_cache()
		return combat_hot_index_for_identity(identity)
	# Active rosters have stable person IDs until their explicit lifecycle
	# invalidation. Negative lookups are common across opposing armies.
	_combat_identity_indices[identity] = -1
	return -1

func materialized_combat_rows() -> Array[Dictionary]:
	assert(_combat_hot_borrowed_index < 0)
	var rows: Array[Dictionary] = []
	var hot: Array = _combat_hot_store.capture_rows() if combat_hot_active() else []
	for index in range(combat_units.size()):
		var row: Dictionary = combat_units[index].duplicate(true)
		if not hot.is_empty():
			row.merge(hot[index], true)
		rows.append(row)
	_combat_hot_materialized_rows += rows.size()
	return rows

func combat_hot_materialize(index: int) -> Dictionary:
	var row: Dictionary = combat_units[index].duplicate(true)
	if _combat_hot_store != null and index != _combat_hot_borrowed_index:
		row.merge(_combat_hot_store.capture_row(index), true)
	_combat_hot_materialized_rows += 1
	return row

func combat_hot_stats() -> Dictionary:
	# Source/caller coverage is recorded in this run's mutation_contract.md.
	# Runtime mechanism, exact replay and FPS remain separate gates.
	return {"active": combat_hot_active(), "coverage_complete": get_script() == TerrainArmy,
		"diagnostics_enabled": combat_hot_diagnostics_enabled,
		# Dictionary counters cover controlled API fallback calls. Direct `unit`
		# access inside one borrowed owner row is represented by fallback_rows.
		"hot_dictionary_reads": _combat_hot_dictionary_reads,
		"hot_dictionary_writes": _combat_hot_dictionary_writes,
		"hot_dictionary_unscoped_reads": _combat_hot_dictionary_unscoped_reads,
		"hot_dictionary_unscoped_writes": _combat_hot_dictionary_unscoped_writes,
		"materialized_rows": _combat_hot_materialized_rows,
		"native_calls": _combat_hot_native_calls, "native_rows": _combat_hot_native_rows,
		"barriers": _combat_hot_barriers.duplicate(), "owner_reasons": _combat_hot_owner_reasons.duplicate(),
		"fallback_rows": _combat_hot_fallback_rows,
		"inclusive_usec": _combat_hot_inclusive_usec}

func combat_hot_reset_stats() -> void:
	_combat_hot_dictionary_reads = 0
	_combat_hot_dictionary_writes = 0
	_combat_hot_dictionary_unscoped_reads = 0
	_combat_hot_dictionary_unscoped_writes = 0
	_combat_hot_materialized_rows = 0
	_combat_hot_native_calls = 0
	_combat_hot_native_rows = 0
	_combat_hot_barriers.clear()
	_combat_hot_owner_reasons.clear()
	_combat_hot_fallback_rows = 0
	_combat_hot_inclusive_usec = 0

func _try_install_combat_hot_store() -> bool:
	if not native_hot_enabled or get_script() != TerrainArmy or combat_units.is_empty() or _combat_hot_store != null:
		return false
	if _get_idle_kernel() == null or not ClassDB.class_exists(&"ArmyCombatHot"):
		return false
	var store: RefCounted = ClassDB.instantiate(&"ArmyCombatHot")
	if store == null or not bool(store.load_rows(combat_units)) or int(store.row_count()) != combat_units.size():
		return false
	# Admission is synchronous. No other owner can observe a partly stripped row.
	for row: Dictionary in combat_units:
		for field: StringName in COMBAT_HOT_FIELDS:
			row.erase(field)
			row.erase(String(field))
	_combat_hot_store = store
	_invalidate_combat_identity_cache()
	_visual_dirty = true # Prime a complete retained batch from the admitted rows.
	return true

func _release_combat_hot_store(materialize: bool) -> void:
	if _combat_hot_store == null:
		return
	if _combat_hot_borrowed_index >= 0:
		_return_combat_hot_row()
	if materialize:
		var hot: Array = _combat_hot_store.capture_rows()
		for index in range(combat_units.size()):
			combat_units[index].merge(hot[index], true)
		_combat_hot_materialized_rows += combat_units.size()
	_combat_hot_store = null

func _borrow_combat_hot_row(index: int) -> void:
	assert(_combat_hot_store != null and _combat_hot_borrowed_index == -1)
	var row: Dictionary = combat_units[index]
	row.merge(_combat_hot_store.capture_row(index), true)
	_combat_hot_borrowed_index = index
	if combat_hot_diagnostics_enabled:
		_combat_hot_fallback_rows += 1

func _return_combat_hot_row() -> void:
	assert(_combat_hot_store != null and _combat_hot_borrowed_index >= 0)
	var index := _combat_hot_borrowed_index
	var row: Dictionary = combat_units[index]
	var hot_absorbed: bool = bool(_combat_hot_store.absorb_row(index, row))
	assert(hot_absorbed)
	for field: StringName in COMBAT_HOT_FIELDS:
		row.erase(field)
		row.erase(String(field))
	_combat_hot_borrowed_index = -1

func capture_exchange_people(materialize: bool = false) -> Array:
	# Subclasses may override identity/eligibility/cell behavior. Never bypass
	# their queries; only the canonical owner's pure readers are implemented here.
	if not native_queries_enabled or _team_has_embarked() or get_script() != TerrainArmy: return []
	var kernel := _combat_hot_store if combat_hot_active() else _get_idle_kernel()
	var method := "capture_people" if materialize else "capture_columns"
	if kernel == null or not kernel.has_method(method): return []
	var packet: Array = kernel.call(method, combat_units, cells, self, faction_id) if materialize else kernel.call(method, combat_units, cells)
	if not packet.is_empty(): native_query_rows += packet.size() if materialize else packet[0].size()
	return packet

func _combat_action_blocks_step(index: int) -> bool:
	return (bool(combat_hot_get(index, &"attack")) and not exchange_enabled) or (exchange_enabled and float(combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0) or str(combat_hot_get(index, &"pose")) in ["guard_break", "guard_raise", "guard", "guard_lower", "rescue"]

func exchange_ready(index: int) -> bool:
	if _siege_crew(index) or not _ship_attack_allowed(index): return false
	if not garrison_feature_id.is_empty(): return false
	if not exchange_enabled or not combat_enabled or not combat_can_act(index) or moving_to[index] != INVALID_CELL or _unit_rescues.has(index):
		return false
	return float(combat_hot_get(index, &"exchange_stagger", 0.0)) <= 0.0 and float(combat_hot_get(index, &"exchange_cooldown", 0.0)) <= 0.0 and str(combat_hot_get(index, &"pose")) not in ["guard_break", "guard_raise", "guard_lower", "rescue"] and not (is_member(index) and not is_controlled_person(index) and is_sustain_routed() and combat_order != CombatOrder.HOLD)

func exchange_can_receive(index: int) -> bool:
	# Rescue, movement and recovery prevent initiating, not being attacked.
	# The shared per-person round still prevents several simultaneous losses.
	if _ship_in_journey(index): return false
	return exchange_enabled and combat_enabled and index >= 0 and index < combat_units.size() \
		and float(combat_hot_get(index, &"hp")) > 0.0 and float(combat_hot_get(index, &"ko")) <= 0.0 \
		and str(combat_hot_get(index, &"pose")) != "get_up" and not bool(combat_hot_get(index, &"captive")) \
		and not bool(combat_hot_get(index, &"departed")) and not bool(combat_hot_get(index, &"site_exited", false)) \
		and float(combat_hot_get(index, &"exchange_cooldown", 0.0)) <= 0.000000001

func exchange_stats(index: int) -> Dictionary:
	var unit: Dictionary = combat_units[index]
	var appearance := equipment_appearance(index)
	var parts: Dictionary = appearance.get("parts", {})
	var weapon_asset := str(parts.get("weapon", "none"))
	var armor_asset := str(parts.get("armor", "none"))
	var armor := SiteCombatRules.armor_profile(armor_asset)
	# Army rows share one troop-type base. Keep the legacy per-row field in
	# snapshots for compatibility/future officer traits, but it cannot silently
	# turn ordinary soldiers into individual combat classes.
	return {"ability": TROOP_COMBAT_ABILITY, "training": training if is_member(index) else 0.0,
		"fatigue": PersonFatigue.read(unit), "morale": 100.0,
		"armorbonus": float(armor.slash) * 0.25 + (4.0 if str(parts.get("shield", "none")) != "none" else 0.0),
		"weapon": weapon_asset, "armor": armor_asset, "skill": str(unit.get("exchange_skill", ""))}

func ranged_profile(index: int, ammo_mode: String = "NORMAL") -> Dictionary:
	if index < 0 or index >= combat_units.size():
		return {}
	return SiteCombatRules.fire_ranged_profile(str(equipment_appearance(index).get("parts", {}).get("weapon", "none")), ammo_mode)

func ranged_defense(index: int) -> Dictionary:
	if index < 0 or index >= combat_units.size():
		return {}
	var parts: Dictionary = equipment_appearance(index).get("parts", {})
	var ship_moving := false
	if _ship_embarked(index) and vehicle_transport != null:
		var boat: Dictionary = vehicle_transport.ship_for_person(combat_identity(index))
		ship_moving = not boat.get("move", {}).is_empty()
	return {"moving": moving_to[index] != INVALID_CELL or ship_moving, "shield": str(parts.get("shield", "none")) != "none",
		"armor": str(parts.get("armor", "none")),
		"armor_stab": float(SiteCombatRules.armor_profile(str(parts.get("armor", "none"))).stab),
		"skill": str(combat_units[index].get("exchange_skill", ""))}

func ranged_fire(index: int, target_cell: Vector2i, shot_id: int) -> bool:
	var flight := _ranged_release(index, target_cell, shot_id, "NORMAL", true)
	if flight.is_empty(): return false
	projectiles.append(flight)
	combat_event.emit(12.0)
	queue_redraw()
	return true

func ranged_release(index: int, target_cell: Vector2i, shot_id: int, ammo_mode: String = "NORMAL", auto_power: bool = false) -> Dictionary:
	# The original Lab owns capacity, preparation and the sole physical flight pool.
	var flight := _ranged_release(index, target_cell, shot_id, ammo_mode, false, auto_power)
	if not flight.is_empty():
		combat_event.emit(12.0)
		queue_redraw()
	return flight

func _ranged_release(index: int, target_cell: Vector2i, shot_id: int, ammo_mode: String, legacy: bool, auto_power: bool = false) -> Dictionary:
	if data == null or index < 0 or index >= combat_units.size() or not exchange_ready(index) or shot_id <= 0 \
		or (is_inside_tree() and get_tree().paused) or bool(data.site.get("paused", false)):
		return {}
	var identity := combat_identity(index)
	var unit: Dictionary = combat_units[index]
	if not legacy and (shot_id <= int(_ranged_last_release_ids.get(identity, 0)) or not unit.get("work_task", {}).is_empty() \
		or person_busy_query.is_valid() and bool(person_busy_query.call(identity))):
		return {}
	if float(combat_hot_get(index, &"ranged_cooldown", 0.0)) > 0.000000001:
		return {}
	var appearance := equipment_appearance(index)
	var weapon := str(appearance.get("parts", {}).get("weapon", "none"))
	var profile := SiteCombatRules.ranged_profile(weapon) if legacy else SiteCombatRules.fire_ranged_profile(weapon, ammo_mode)
	if profile.is_empty():
		if legacy: unit["status"] = "目前實裝不是遠程武器"
		return {}
	if not _uses_live_presenter(index) and not supports_equipment_recipe(appearance):
		if legacy:
			unit["status"] = "此遠程實裝尚未准入完整圖集；未射擊也未扣彈"
			_mark_visual_row(index)
		return {}
	var source_cell := _combat_attack_cell(index)
	if not legacy:
		# Physical flights launch from the shooter's real deck cell. An embarked shooter
		# must be afloat, admitted and not mid-journey; land shooters keep the walk gate.
		var embarked := _ship_embarked(index)
		if not data.contains(target_cell) or not data.contains(source_cell):
			return {}
		if embarked and not _ship_attack_allowed(index):
			return {}
		if not embarked and not data.is_walkable(source_cell):
			return {}
	var offset := target_cell - source_cell
	var distance := Vector2(offset).length()
	if not SiteCombatRules.ranged_in_range(source_cell, target_cell, float(profile.range)) \
		or legacy and not _combat_ranged_line_clear(index, source_cell, target_cell):
		return {}
	var ammunition := str(profile.ammo)
	if not unit.get("cargo") is Dictionary or int(unit.cargo.get(ammunition, 0)) < 1:
		if legacy: unit["status"] = "沒有本人實際攜帶的彈藥"
		return {}
	# Original skill authority stays intact, and every release refusal has
	# already run. A denied auto-power request does not cancel the legal shot.
	if not legacy and auto_power: activate_exchange_skill(index, "power")
	var shooter := exchange_stats(index).duplicate(true)
	var origin := combat_ground(index) - Vector2(0.0, 20.0) + data.surface_visual_offset(source_cell)
	var goal := (Vector2(target_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - Vector2(0.0, 20.0) + data.surface_visual_offset(target_cell)
	var flight := distance / float(profile.speed)
	if not legacy:
		_ranged_last_release_ids[identity] = shot_id
		if _ranged_last_release_ids.size() > combat_units.size():
			for prior_id: int in _ranged_last_release_ids.keys():
				if index_for_identity(prior_id) < 0: _ranged_last_release_ids.erase(prior_id)
	# Deduct and publish synchronously from the original holder. A miss, weapon
	# change or incapacitated shooter never refunds or retargets this event.
	unit.cargo[ammunition] = int(unit.cargo[ammunition]) - 1
	PersonFatigue.charge(unit, 1.0)
	if str(unit.get("exchange_skill", "")) == "power":
		unit["exchange_skill"] = ""
		combat_hot_set(index, &"exchange_skill_cooldown", SiteCombatRules.EXCHANGE_SKILL_COOLDOWN)
	facing[index] = Vector2i(signi(offset.x), 0) if absi(offset.x) >= absi(offset.y) else Vector2i(0, signi(offset.y))
	var attack_pose := "attack_crossbow" if HumanCharacter3DEditor.WeaponMaterials.family(StringName(weapon)) == &"crossbow_01" else "attack_bow"
	combat_hot_set(index, &"pose", attack_pose)
	combat_hot_set(index, &"attack", true)
	combat_hot_set(index, &"age", 0.0)
	unit["blocked"] = false
	unit["aim"] = []
	unit["hits"] = {}
	unit["previous"] = []
	combat_hot_set(index, &"exchange_pose_duration", 1.0)
	combat_hot_set(index, &"exchange_stagger", float(profile.hold))
	combat_hot_set(index, &"ranged_cooldown", float(profile.cooldown)) # Reload rate never grants melee immunity.
	unit["status"] = "射出弩矢" if ammunition == "bolt" else "射出箭矢"
	_begin_exchange_visual(index, attack_pose)
	var flight_data := {"mode": "cell", "source_cell": source_cell, "target_cell": target_cell,
		"source_eye": data.effective_height(source_cell) + 1.0, "goal_eye": data.effective_height(target_cell) + 1.0,
		"origin": origin, "position": origin, "goal": goal, "velocity": (goal - origin) / flight,
		"visual": ammunition, "left": flight, "total": flight, "shooter": shooter,
		"shooter_id": identity, "shot_id": shot_id, "faction": faction_id}
	if not legacy: flight_data["ammo_mode"] = ammo_mode
	_mark_visual_row(index)
	return flight_data

func ranged_apply_hit(index: int, _source_cell: Vector2i, packet: Dictionary) -> void:
	var region_sink: Variant = get_meta(&"region_effect_sink", Callable())
	if region_sink is Callable and region_sink.is_valid() and bool(region_sink.call(combat_identity(index), "ranged", {"source_cell": _source_cell, "packet": packet})):
		return
	if not exchange_enabled or index < 0 or index >= combat_units.size() or float(combat_hot_get(index, &"hp")) <= 0.0:
		return
	var unit: Dictionary = combat_units[index]
	if str(unit.get("exchange_skill", "")) == "brace" and not bool(packet.get("siege", false)):
		unit["exchange_skill"] = ""
		combat_hot_set(index, &"exchange_skill_cooldown", SiteCombatRules.EXCHANGE_SKILL_COOLDOWN)
	var result: Dictionary = packet.result.duplicate()
	result["guard_break"] = bool(result.get("guard_break", false))
	var original_packet := packet.duplicate()
	original_packet["result"] = result
	original_packet["shield"] = bool(packet.get("shield", false))
	apply_unit_contact(index, original_packet)
	if float(combat_hot_get(index, &"hp")) <= 0.0 or float(combat_hot_get(index, &"ko")) > 0.0 or str(combat_hot_get(index, &"pose")) == "get_up":
		return # Original death/KO/get-up pose and recovery age remain authoritative.
	if float(result.hp) <= 0.0:
		unit["status"] = "遠射落空" if str(result.get("kind", "")) == "miss" else str(unit.status)
		return
	_cancel_unit_rescue(index)
	var committed_left := maxf(0.0, (1.0 - move_progress[index]) * move_duration[index]) if moving_to[index] != INVALID_CELL else 0.0
	var stagger := maxf(float(combat_hot_get(index, &"exchange_stagger", 0.0)), committed_left + maxf(0.0, float(result.get("stagger", 0.0))))
	combat_hot_set(index, &"exchange_stagger", stagger)
	combat_hot_set(index, &"pose", "hit")
	combat_hot_set(index, &"attack", false)
	unit["blocked"] = false
	combat_hot_set(index, &"age", 0.0)
	unit["aim"] = []
	unit["hits"] = {}
	unit["previous"] = []
	combat_hot_set(index, &"exchange_pose_duration", maxf(0.1, stagger))
	unit["status"] = "箭矢命中"
	_begin_exchange_visual(index, "hit", true)
	_mark_visual_row(index)

func activate_exchange_skill(index: int, skill: String) -> bool:
	if not exchange_enabled or not combat_can_act(index) or not _ship_attack_allowed(index) or skill not in ["brace", "power"] or (is_inside_tree() and get_tree().paused):
		return false
	if not is_controlled_person(index) and index not in [current_commander, formal_commander, acting_commander] and not command_abilities.has(index):
		return false
	var unit: Dictionary = combat_units[index]
	if float(combat_hot_get(index, &"exchange_skill_cooldown", 0.0)) > 0.0 or not str(unit.get("exchange_skill", "")).is_empty():
		return false
	unit["exchange_skill"] = skill
	unit["status"] = "蓄勢猛攻" if skill == "power" else "準備架穩"
	return true

func apply_exchange(index: int, other_cell: Vector2i, outcome: Dictionary) -> void:
	var region_sink: Variant = get_meta(&"region_effect_sink", Callable())
	if region_sink is Callable and region_sink.is_valid() and bool(region_sink.call(combat_identity(index), "exchange", {"other_cell": other_cell, "outcome": outcome})):
		return
	var prepared := exchange_batch_prepare(index, other_cell, outcome)
	if prepared.is_empty():
		return
	exchange_batch_knockback(index, other_cell, outcome, prepared)
	exchange_batch_contact(index, outcome)
	exchange_batch_finish(index, other_cell, outcome, prepared)

func exchange_batch_prepare(index: int, other_cell: Vector2i, outcome: Dictionary) -> Dictionary:
	if _ship_in_journey(index) or not exchange_enabled or not combat_can_act(index):
		return {}
	if str(outcome.get("role", "")) not in ["winner", "loser", "draw"]:
		return {}
	for field: String in ["hp", "stun", "stagger", "fatigue"]:
		if not TerrainTestCharacter._saved_number(outcome.get(field, 0.0), 0.0, 1000000.0):
			return {}
	var source_cell := cells[index]
	var committed_left := maxf(0.0, (1.0 - move_progress[index]) * move_duration[index]) if moving_to[index] != INVALID_CELL else 0.0
	var offset := other_cell - _combat_attack_cell(index)
	var toward := facing[index]
	if offset != Vector2i.ZERO:
		toward = Vector2i(signi(offset.x), 0) if absi(offset.x) >= absi(offset.y) else Vector2i(0, signi(offset.y))
	var unit: Dictionary = combat_units[index]
	var prepared := {"identity": combat_identity(index), "source_cell": source_cell,
		"toward": toward, "committed_left": committed_left,
		"previous_stagger": float(combat_hot_get(index, &"exchange_stagger", 0.0))}
	if _unit_rescues.has(index):
		_cancel_unit_rescue(index) # Draw/win must also stop helping before replacing its animation.
	facing[index] = toward
	combat_hot_set(index, &"exchange_cooldown", SiteCombatRules.EXCHANGE_ROUND_SECONDS)
	if not str(unit.get("exchange_skill", "")).is_empty():
		combat_hot_set(index, &"exchange_skill_cooldown", SiteCombatRules.EXCHANGE_SKILL_COOLDOWN)
	unit["exchange_skill"] = ""
	# Receiving an exchange is self-defense, not a new persistent attack order.
	# Keep an existing explicit target; never replace it with this opponent.
	PersonFatigue.charge(unit, float(outcome.get("fatigue", 0.0)))
	unit["aim"] = []
	unit["previous"] = []
	unit["hits"] = {}
	combat_hot_set(index, &"attack", false)
	unit["blocked"] = false
	combat_event.emit(10.0)
	return prepared

func exchange_batch_knockback(index: int, _other_cell: Vector2i, outcome: Dictionary, prepared: Dictionary) -> void:
	if not _exchange_prepared_unit_matches(index, prepared):
		push_error("Exchange batch knockback lost the original Army person")
		return
	# Use the frozen source and old recovery. The reservation may itself start
	# a new movement, which must not be counted as the old committed step.
	if str(outcome.get("role", "")) == "loser" and bool(outcome.get("knockback", false)):
		combat_hot_set(index, &"pose", "idle") # A guard visual cannot veto an already resolved big loss.
		combat_hot_set(index, &"attack", false)
		combat_hot_set(index, &"exchange_stagger", 0.0) # Previous recovery cannot veto this newly resolved forced push.
		if _reserve_combat_step(index, Vector2i(prepared.source_cell) - Vector2i(prepared.toward)):
			_audio_step_sources.erase(index)
		facing[index] = Vector2i(prepared.toward)
	var stagger := maxf(0.0, float(outcome.get("stagger", 0.0)))
	combat_hot_set(index, &"exchange_stagger", maxf(float(prepared.previous_stagger), float(prepared.committed_left) + stagger if stagger > 0.0 else 0.0))

func exchange_batch_contact(index: int, outcome: Dictionary) -> void:
	if index < 0 or index >= combat_units.size():
		return
	apply_unit_contact(index, {"result": {"hp": float(outcome.get("hp", 0.0)), "stun": float(outcome.get("stun", 0.0)), "guard_break": false}, "shield": false,
		"attacker": outcome.get("attacker"), "attacker_unit": int(outcome.get("attacker_unit", -1))})

func exchange_batch_finish(index: int, _other_cell: Vector2i, outcome: Dictionary, prepared: Dictionary) -> void:
	if not _exchange_prepared_unit_matches(index, prepared):
		push_error("Exchange batch finish lost the original Army person")
		return
	var unit: Dictionary = combat_units[index]
	if float(combat_hot_get(index, &"hp")) <= 0.0 or float(combat_hot_get(index, &"ko")) > 0.0:
		combat_hot_set(index, &"exchange_pose_duration", 0.0)
		return
	var outcome_role := str(outcome.get("role", "draw"))
	var pose := ""
	if outcome_role == "winner":
		pose = "attack_jump_heavy" if str(outcome.get("kind", "")) == "big" else str(attack_clip(index))
		if pose in ["attack_bow", "attack_crossbow"]:
			pose = "attack_unarmed" # Melee only; no new ranged release rule.
		combat_hot_set(index, &"attack", true)
		combat_hot_set(index, &"exchange_pose_duration", SiteCombatRules.EXCHANGE_ROUND_SECONDS)
	elif outcome_role == "loser":
		pose = "knockback" if bool(outcome.get("knockback", false)) else "hit"
		combat_hot_set(index, &"exchange_pose_duration", maxf(0.1, float(combat_hot_get(index, &"exchange_stagger", 0.0))))
	else:
		pose = "guard"
		combat_hot_set(index, &"exchange_pose_duration", maxf(SiteCombatRules.EXCHANGE_DRAW_HOLD, float(combat_hot_get(index, &"exchange_stagger", 0.0))))
	combat_hot_set(index, &"pose", pose)
	combat_hot_set(index, &"age", 0.0)
	unit["status"] = "大勝" if outcome_role == "winner" and str(outcome.get("kind", "")) == "big" else ("小勝" if outcome_role == "winner" else ("平手防禦" if outcome_role == "draw" else "受擊硬直"))
	_begin_exchange_visual(index, pose)
	_mark_visual_row(index)

func _exchange_prepared_unit_matches(index: int, prepared: Dictionary) -> bool:
	return index >= 0 and index < combat_units.size() and not prepared.is_empty() \
		and combat_identity(index) == int(prepared.get("identity", -1)) \
		and cells[index] == Vector2i(prepared.get("source_cell", INVALID_CELL))

func _begin_exchange_visual(index: int, pose: String, merge_reaction: bool = false) -> void:
	# A disposable presentation facet of the original row, never an action lock.
	var previous: Dictionary = combat_hot_get(index, &"exchange_visual", {})
	var priority := ExchangeTimings.reaction_priority(StringName(pose))
	if merge_reaction and not previous.is_empty() and float(previous.left) > 0.0 \
		and ExchangeTimings.reaction_priority(StringName(str(previous.pose))) >= priority and priority > 0:
		return # Every arrow still applies its real damage/stagger above; no endless hit restart.
	var duration := ExchangeTimings.duration(StringName(pose))
	if duration <= 0.0:
		combat_hot_erase(index, &"exchange_visual")
		return
	var left := minf(duration, ExchangeTimings.MOVE_CORE_SECONDS) if moving_to[index] != INVALID_CELL and CombatTimings.ATTACKS.has(StringName(pose)) else duration
	combat_hot_set(index, &"exchange_visual", {"pose": pose, "age": 0.0, "left": left, "facing": facing[index]})

func _advance_exchange_visual(index: int, delta: float) -> void:
	if float(combat_hot_get(index, &"hp")) <= 0.0 or float(combat_hot_get(index, &"ko")) > 0.0 or str(combat_hot_get(index, &"pose")) in EXCHANGE_NATIVE_VISUAL_POSES:
		combat_hot_erase(index, &"exchange_visual")
		return
	var visual: Dictionary = combat_hot_get(index, &"exchange_visual", {})
	if visual.is_empty():
		return
	visual.age = float(visual.age) + delta
	visual["left"] = maxf(0.0, float(visual.left) - delta)
	if float(visual.left) <= 0.000000001:
		combat_hot_erase(index, &"exchange_visual")
	else:
		combat_hot_set(index, &"exchange_visual", visual)

func _exchange_visual_pose(index: int) -> String:
	var pose := str(combat_hot_get(index, &"pose"))
	if not exchange_enabled or float(combat_hot_get(index, &"hp")) <= 0.0 or float(combat_hot_get(index, &"ko")) > 0.0 \
		or pose in EXCHANGE_NATIVE_VISUAL_POSES:
		return pose
	var visual: Dictionary = combat_hot_get(index, &"exchange_visual", {})
	if not visual.is_empty():
		return str(visual.pose)
	if float(combat_hot_get(index, &"exchange_pose_duration", 0.0)) > 0.0:
		return "walk" if moving_to[index] != INVALID_CELL else "idle" # Never resume the old long result after the short visual has ended.
	return pose

func _exchange_visual_facing(index: int, resolved_pose: String = "") -> Vector2i:
	var visual: Dictionary = combat_hot_get(index, &"exchange_visual", {}) if exchange_enabled else {}
	if visual.is_empty():
		return facing[index]
	var pose := _exchange_visual_pose(index) if resolved_pose.is_empty() else resolved_pose
	return Vector2i(visual.facing) if pose == str(visual.pose) else facing[index]

func _advance_exchange_pose(index: int) -> void:
	var pose := str(combat_hot_get(index, &"pose"))
	var duration := float(combat_hot_get(index, &"exchange_pose_duration", 0.0))
	if pose == "get_up":
		duration = float(CombatTimings.POSE_SECONDS[&"get_up"])
	elif pose in ["guard_raise", "guard_lower"]:
		if float(combat_hot_get(index, &"age")) + 0.000000001 >= SiteCombatRules.GUARD_TRANSITION:
			combat_hot_set(index, &"pose", "guard" if pose == "guard_raise" else "idle")
			combat_hot_set(index, &"age", 0.0)
		return
	elif pose == "guard_break":
		duration = SiteCombatRules.GUARD_BREAK_SECONDS
	if duration > 0.0 and float(combat_hot_get(index, &"age")) + 0.000000001 >= duration:
		combat_hot_set(index, &"pose", "walk" if moving_to[index] != INVALID_CELL else "idle")
		combat_hot_set(index, &"attack", false)
		combat_hot_set(index, &"age", 0.0)
		combat_hot_set(index, &"exchange_pose_duration", 0.0)
		_command_dirty = true

func _exchange_animation_time(index: int, authored_duration: float, resolved_pose: String = "") -> float:
	var visual: Dictionary = combat_hot_get(index, &"exchange_visual", {})
	var pose := _exchange_visual_pose(index) if resolved_pose.is_empty() else resolved_pose
	if not visual.is_empty() and pose == str(visual.pose):
		return ExchangeTimings.sample_time(StringName(str(visual.pose)), float(visual.age), authored_duration)
	# The original pose may still own a gameplay cooldown after its short visual.
	return 0.0 if pose != str(combat_hot_get(index, &"pose")) else float(combat_hot_get(index, &"age"))

func is_controlled_person(index: int) -> bool:
	return controlled_person_query.is_valid() and combat_identity(index) == int(controlled_person_query.call())

func combat_ground(index: int) -> Vector2:
	if vehicle_transport != null:
		var ship_ground: Vector2 = vehicle_transport.ship_person_ground(combat_identity(index))
		if ship_ground != Vector2(-1, -1): return ship_ground
	if index == PLAYER_MEMBER:
		return player_member.position
	var ground := (Vector2(cells[index]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	if moving_to[index] != INVALID_CELL:
		var destination := (Vector2(moving_to[index]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		ground = ground.lerp(destination, CombatTimings.movement_weight(move_progress[index], move_curve[index] == 1))
	return ground

func combat_visual_ground(index: int) -> Vector2:
	var ground := combat_ground(index)
	if index == PLAYER_MEMBER or _ship_embarked(index) or moving_to[index] == INVALID_CELL:
		return ground
	var partner: int = int(_cell_owners.get(moving_to[index], -1))
	if partner < 0 or partner == index or moving_to[partner] != cells[index]:
		return ground
	# Opposite travel directions give opposite lateral offsets. The two sprites
	# pass beside each other while their authoritative cells commit together.
	var direction := Vector2(moving_to[index] - cells[index])
	var side := Vector2(-direction.y, direction.x)
	var weight := CombatTimings.movement_weight(move_progress[index], move_curve[index] == 1)
	return ground + side * TerrainRenderer.CELL_PIXELS * 0.42 * sin(PI * weight)

func combat_offset(index: int) -> Vector2:
	if _ship_embarked(index) or exchange_enabled or not combat_can_act(index) or moving_to[index] != INVALID_CELL:
		return Vector2.ZERO
	var next := cells[index] + facing[index]
	if not data.can_attack_across(cells[index], next) or _cell_owners.has(next):
		return Vector2.ZERO
	var step := 12.0
	var unit: Dictionary = combat_units[index]
	if bool(combat_hot_get(index, &"attack")):
		var duration := float(CombatTimings.events(attack_clip(index)).duration)
		var phase := CombatTimings.sample_time(attack_clip(index), float(combat_hot_get(index, &"age")), float(unit.get("attack_reduction", 0.0)), float(unit.get("attack_fatigue", 0.0))) / duration
		step += minf(float(TerrainTestCharacter.ATTACK_STEP_PIXELS[attack_clip(index)]), 31.5 - step) * CombatTimings.attack_step_weight(phase)
	# Stay inside this unit's own grid cell; never enter an ally's reservation.
	return Vector2(facing[index]) * minf(31.5, step)

func equipment_appearance(index: int) -> Dictionary:
	return equipment_appearance_query.call(combat_identity(index)) if equipment_appearance_query.is_valid() else {}

## The appearance a contact source is resolved for: the same rule enable_combat uses
## to prepare the sources (and _sync_pooled_captain to pose the pooled captain), so a
## row without an equipment query answer still finds its prepared same-body source.
func _contact_appearance(index: int) -> Dictionary:
	var appearance: Dictionary = equipment_appearance(index)
	return appearance if not appearance.is_empty() else combat_units[index].get("appearance", {})

func supports_equipment_recipe(appearance: Dictionary) -> bool:
	# Full baseline is already published. Missing-piece recipes are admitted only
	# after their complete original-animation atlas has passed the baker contract.
	if not HumanCharacter3DEditor.valid_appearance(appearance): return false
	if WagonRiderRecipe.matches(appearance): return EquipmentAtlas.supports(appearance)
	if not EquipmentAtlas.mixed_recipe(appearance).is_empty(): return EquipmentAtlas.supports(appearance)
	if appearance.body == 1: return EquipmentAtlas.supports(appearance)
	if not EquipmentAtlas.DyeAtlas.supports(appearance): return false
	return not _combat_bake.is_empty() and HumanCharacter3DEditor.EquipmentDye.geometry_appearance(appearance) == _combat_bake.manifest.appearance or EquipmentAtlas.supports(appearance)

func attack_clip(index: int) -> StringName:
	if bool(combat_hot_get(index, &"attack")):
		return StringName(str(combat_hot_get(index, &"pose")))
	var appearance := equipment_appearance(index)
	var weapon := str(appearance.get("parts", {}).get("weapon", "longsword_01"))
	return StringName(str(HumanCharacter3DEditor.WEAPON_ATTACK_MAP.get(HumanCharacter3DEditor.WeaponMaterials.family(StringName(weapon)), &"attack_unarmed")))

func _combat_clip(index: int, resolved_pose: String = "") -> String:
	# Presentation and collision share the original clip, not a rounded time.
	var pose := _exchange_visual_pose(index) if resolved_pose.is_empty() else resolved_pose
	if pose.begins_with("guard"):
		var appearance := equipment_appearance(index)
		if not appearance.is_empty() and str(appearance.parts.shield) == "none" and HumanCharacter3DEditor.WeaponMaterials.family(StringName(str(appearance.parts.weapon))) not in [&"none", &"bow_01", &"crossbow_01"]:
			var polearm := HumanCharacter3DEditor.WeaponMaterials.is_polearm(StringName(str(appearance.parts.weapon)))
			return ("guard_spear" if polearm else "guard_unshielded") if pose == "guard" else pose.replace("guard", "guard_polearm" if polearm else "guard_weapon")
	if pose == "walk" and moving_to[index] != INVALID_CELL and move_duration[index] <= RUN_DURATION + 0.000001:
		pose = "run"
	return str(HELD_LOCOMOTION.get(pose, pose))

func combat_frame(index: int) -> Dictionary:
	if not combat_enabled or _combat_bake.is_empty():
		return {}
	var unit: Dictionary = combat_units[index]
	var resolved_pose := _exchange_visual_pose(index)
	var clip := _combat_clip(index, resolved_pose)
	var clock: Array = _combat_bake.contact_clocks[clip][_soldier_direction_id(_exchange_visual_facing(index, resolved_pose))]
	var frames: Array = clock[3]
	var elapsed := float(combat_hot_get(index, &"age"))
	if exchange_enabled:
		elapsed = _exchange_animation_time(index, float(clock[1]), resolved_pose)
		if bool(clock[2]) and (combat_hot_get(index, &"exchange_visual", {}) as Dictionary).is_empty():
			elapsed = fposmod(elapsed, float(clock[1]))
	elif bool(combat_hot_get(index, &"attack")):
		elapsed = CombatTimings.sample_time(attack_clip(index), elapsed, float(unit.get("attack_reduction", 0.0)), float(unit.get("attack_fatigue", 0.0)))
	elif bool(clock[2]):
		elapsed = fposmod(elapsed, float(clock[1]))
	# Non-looping bakes include the final timestamp; looping bakes do not.
	# Select the actual preceding sample, never a future pose via count/duration.
	var low := 0
	var high := frames.size()
	while low + 1 < high:
		var middle := low + ((high - low) >> 1)
		var candidate: Dictionary = frames[middle]
		if float(candidate.sample_time) <= elapsed + 0.000000001:
			low = middle
		else:
			high = middle
	return frames[low]

func contact_sample(index: int) -> Array:
	var work := siege_work_state(index)
	if not work.is_empty(): return [StringName(str(work.clip)), fposmod(float(work.time), float(SiegeWorkClips.DURATIONS[str(work.clip)])), work.facing, Vector2.ZERO, 0.0]
	# Exact collision time does not need the atlas's preceding-frame search.
	var resolved_pose := _exchange_visual_pose(index)
	var clip := _combat_clip(index, resolved_pose)
	var display_facing := _exchange_visual_facing(index, resolved_pose)
	var direction := _soldier_direction_id(display_facing)
	var clock: Array = _combat_bake.contact_clocks[clip][direction]
	var unit: Dictionary = combat_units[index]
	var time := float(combat_hot_get(index, &"age"))
	if exchange_enabled:
		time = _exchange_animation_time(index, float(clock[1]), resolved_pose)
		if bool(clock[2]) and (combat_hot_get(index, &"exchange_visual", {}) as Dictionary).is_empty():
			time = fposmod(time, float(clock[1]))
		else:
			time = minf(time, float(clock[1]))
	elif bool(combat_hot_get(index, &"attack")):
		time = CombatTimings.sample_time(attack_clip(index), time, float(unit.get("attack_reduction", 0.0)), float(unit.get("attack_fatigue", 0.0)))
	else:
		time = fposmod(time, float(clock[1])) if bool(clock[2]) else minf(time, float(clock[1]))
	var aim := Vector2.ZERO
	var weight := 0.0
	var saved_aim: Array = unit.get("aim", [])
	if not exchange_enabled and bool(combat_hot_get(index, &"attack")) and facing[index] == Vector2i.DOWN and saved_aim.size() == 2:
		aim = Vector2(float(saved_aim[0]), float(saved_aim[1])) - combat_ground(index) - combat_offset(index)
		var fraction := time / float(clock[1])
		weight = smoothstep(0.18, 0.40, fraction) * (1.0 - smoothstep(0.65, 0.90, fraction))
	return [clock[0], time, display_facing, aim, weight]

func _needs_weapon_sample(index: int) -> bool:
	# Predict only work that sample_combat already performs in this same batch.
	# Keep its exact eligibility/window; blocked, windup and recovery need no weapon.
	if not combat_enabled or not contact_query.is_valid() or not combat_can_act(index):
		return false
	var unit: Dictionary = combat_units[index]
	if not bool(combat_hot_get(index, &"attack")) or bool(unit.blocked):
		return false
	var sample := CombatTimings.sample_time(attack_clip(index), float(combat_hot_get(index, &"age")), float(unit.attack_reduction), float(unit.attack_fatigue))
	var events := CombatTimings.events(attack_clip(index))
	return sample >= float(events.active_start) and sample <= float(events.active_end)

func _contact_inputs(index: int) -> Dictionary:
	# The Lab lends its existing target slots; no second cross-step cache. Keep
	# original contact_sample's subtraction order for DOWN aim and armor points.
	var target := {}
	if not _contact_batch_inputs.is_empty():
		if _contact_batch_inputs[index] == null:
			_contact_batch_inputs[index] = {}
		target = _contact_batch_inputs[index]
		if target.has("inputs"):
			return target.inputs
	var sample := contact_sample(index)
	var appearance := _contact_appearance(index)
	var ground := combat_ground(index)
	var offset := combat_offset(index)
	var inputs := {"sample": sample, "appearance": appearance,
		"ground": ground, "offset": offset, "origin": ground + offset}
	if not _contact_batch_inputs.is_empty():
		target["inputs"] = inputs
	return inputs

func _continuous_pose(index: int, include_weapon: bool = true) -> Dictionary:
	if combat_proxy != null:
		return combat_proxy.army_sample(self, index)
	var inputs := _contact_inputs(index) if not _contact_batch_inputs.is_empty() else {}
	var sample: Array = inputs.sample if not inputs.is_empty() else contact_sample(index)
	# An active target will need its own weapon later in the original team order.
	# Fill it now, avoiding a second restore of A after another person's pose B.
	include_weapon = include_weapon or not lazy_weapon_queries_enabled or _needs_weapon_sample(index)
	var appearance: Dictionary = inputs.appearance if not inputs.is_empty() else _contact_appearance(index)
	var source: RefCounted = contact_source_for(appearance)
	if source == null:
		push_error("MISSING_ASSET: original same-body combat contact source was not prepared")
		return {}
	if not source.same_batch_result_reuse_enabled or _contact_batch_pose_results.is_empty():
		return source.sample(sample[0], sample[1], sample[2], sample[3], sample[4], appearance, include_weapon)
	if _contact_batch_pose_results[index] == null:
		_contact_batch_pose_results[index] = {}
	var target: Dictionary = _contact_batch_pose_results[index]
	var retained: Dictionary = target.get("pose_result", {})
	# Match current values, never caller Dictionary identity. A Source clear
	# (including step/terminal overflow) must retain the original re-seek path.
	if not retained.is_empty() and int(retained.source_id) == source.get_instance_id() and int(retained.generation) == source.pose_cache_generation and retained.sample == sample and retained.appearance == appearance and (not include_weapon or retained.result.has("weapon")):
		combat_geometry_profile.pose_result_hits += 1
		return retained.result
	combat_geometry_profile.pose_result_misses += 1
	var result: Dictionary = source.sample(sample[0], sample[1], sample[2], sample[3], sample[4], appearance, include_weapon)
	if result.is_empty():
		target.erase("pose_result")
	else:
		# Source.sample can clear a pose cache while filling this result, so
		# retain the generation after the call. Public Source copy semantics
		# stay unchanged; Army only reads this private local geometry reference.
		target["pose_result"] = {"source_id": source.get_instance_id(),
			"generation": source.pose_cache_generation, "sample": sample.duplicate(true),
			"appearance": appearance.duplicate(true), "result": result}
	return result

func combat_shapes(index: int, kind: String) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if _ship_in_journey(index) or not combat_enabled or _combat_bake.is_empty():
		return result
	if combat_proxy != null:
		return CombatGeometry.shifted(_continuous_pose(index).get(kind, []), combat_ground(index) + combat_offset(index))
	if _uses_live_contact_presenter(index):
		# Deferred captains keep their original live geometry through one true
		# same-body editor; their atlas sprite is presentation only.
		var pooled := _uses_pooled_captain_geometry(index)
		var pooled_entry := _captain_geometry_entry(index) if pooled else {}
		var presenter: Variant = pooled_entry.editor if pooled else _unit_editor(index)
		if presenter == null or index >= _sprites.size():
			return result
		var inputs := _contact_inputs(index) if not _contact_batch_inputs.is_empty() else {}
		var key: Array = inputs.sample.duplicate() if not inputs.is_empty() else contact_sample(index)
		key.append(inputs.appearance if not inputs.is_empty() else equipment_appearance(index))
		var live_origin: Vector2 = inputs.origin if not inputs.is_empty() else combat_ground(index) + combat_offset(index)
		if pooled:
			key.append(presenter.get_instance_id()) # Invalidate after pool/site replacement.
			key.append(live_origin) # World projection can change ordered hull topology.
		var cache: Dictionary = _combat_pose_cache.get(combat_identity(index), {})
		var fresh: bool = cache.get("sample", []) != key
		var include_weapon := kind == "weapon" or not lazy_weapon_queries_enabled or _needs_weapon_sample(index)
		var geometry: Variant = pooled_entry.geometry if pooled else _combat_geometry
		var proxy := {"editor": presenter, "player_sprite": pooled_entry.sprite if pooled else _sprites[index]}
		var started := 0
		if fresh:
			combat_geometry_profile.live_cache_misses += 1
			var frame := combat_frame(index)
			started = Time.get_ticks_usec()
			if pooled:
				if not _sync_pooled_captain(index, pooled_entry, inputs): return result
			else: _sync_captain_combat(frame, index)
			combat_geometry_profile.live_sync_usec += Time.get_ticks_usec() - started
			cache = {"sample": key}
			_combat_pose_cache[combat_identity(index)] = cache
			started = Time.get_ticks_usec()
			cache["body"] = CombatGeometry.shifted(geometry.body_shapes(proxy), -live_origin)
			combat_geometry_profile.live_body_usec += Time.get_ticks_usec() - started
		if include_weapon and not cache.has("weapon"):
			if not fresh:
				# A later full request must restore this person's exact current pose,
				# just as the shared source does before filling an absent field.
				combat_geometry_profile.live_partial_fills += 1
				var frame := combat_frame(index)
				started = Time.get_ticks_usec()
				if pooled:
					if not _sync_pooled_captain(index, pooled_entry, inputs): return result
				else: _sync_captain_combat(frame, index)
				combat_geometry_profile.live_sync_usec += Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			cache["weapon"] = CombatGeometry.shifted(geometry.weapon_shapes(proxy, attack_clip(index)), -live_origin)
			combat_geometry_profile.live_weapon_usec += Time.get_ticks_usec() - started
			combat_geometry_profile.live_weapon_fills += 1
		elif fresh and not include_weapon:
			combat_geometry_profile.live_weapon_omissions += 1
		if fresh:
			started = Time.get_ticks_usec()
			cache["shield"] = CombatGeometry.shifted(geometry.shield_shapes(proxy), -live_origin)
			combat_geometry_profile.live_shield_usec += Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			cache["parry"] = []
			if str(combat_hot_get(index, &"pose")) == "guard" and cache.shield.is_empty() and attack_clip(index) not in [&"attack_unarmed", &"attack_bow", &"attack_crossbow"]:
				cache["parry"] = CombatGeometry.shifted(geometry.weapon_shapes(proxy, attack_clip(index), true), -live_origin)
			combat_geometry_profile.live_parry_usec += Time.get_ticks_usec() - started
		return CombatGeometry.shifted(cache.get(kind, []), live_origin)
	var pose := _continuous_pose(index, kind == "weapon")
	var origin: Vector2 = _contact_inputs(index).origin if not _contact_batch_inputs.is_empty() else combat_ground(index) + combat_offset(index)
	return CombatGeometry.shifted(pose.get(kind, []), origin)

func combat_bounds(index: int) -> Rect2:
	var bounds := Rect2()
	if combat_proxy != null:
		bounds = _continuous_pose(index).hurt_bounds
		bounds.position += combat_ground(index) + combat_offset(index)
		return bounds
	var started := 0
	if _uses_live_contact_presenter(index):
		# Prime the existing live-pose cache, preserving the female geometry.
		combat_shapes(index, "body")
		var cache: Dictionary = _combat_pose_cache.get(combat_identity(index), {})
		if not cache.has("hurt_bounds"):
			var points := PackedVector2Array()
			for kind: String in ["body", "shield", "parry"]:
				for shape: PackedVector2Array in cache.get(kind, []):
					points.append_array(shape)
			cache["hurt_bounds"] = CombatGeometry.polygon_bounds(points)
		bounds = cache.hurt_bounds
	else:
		combat_geometry_profile.ordinary_bounds_calls += 1
		started = Time.get_ticks_usec()
		bounds = _continuous_pose(index, false).get("hurt_bounds", Rect2())
	bounds.position += _contact_inputs(index).origin if not _contact_batch_inputs.is_empty() else combat_ground(index) + combat_offset(index)
	if started > 0:
		combat_geometry_profile.ordinary_bounds_usec += Time.get_ticks_usec() - started
	return bounds

func combat_query_bounds(index: int) -> Rect2:
	# A cheap enclosure can only reject. Public combat_bounds and all incoming
	# geometry remain exact. A static query never seeks, so an active person's
	# original weapon can still be filled once when the exact query needs it.
	if _uses_live_presenter(index):
		return combat_bounds(index)
	var unit: Dictionary = combat_units[index]
	if bool(combat_hot_get(index, &"attack")) and facing[index] == Vector2i.DOWN and unit.get("aim", []).size() == 2:
		return combat_bounds(index)
	var inputs := _contact_inputs(index) if not _contact_batch_inputs.is_empty() else {}
	var ground: Vector2 = inputs.ground if not inputs.is_empty() else combat_ground(index)
	if not ground.is_finite() or maxf(absf(ground.x), absf(ground.y)) > 16384.0:
		return combat_bounds(index)
	var sample: Array = inputs.sample if not inputs.is_empty() else contact_sample(index)
	var appearance: Dictionary = inputs.appearance if not inputs.is_empty() else _contact_appearance(index)
	var source: RefCounted = contact_source_for(appearance)
	if source == null or not source.cheap_query_bounds_enabled: return combat_bounds(index)
	var bounds: Rect2 = source.query_bounds(sample[0], sample[1], sample[2], sample[3], sample[4], appearance)
	bounds.position += inputs.origin if not inputs.is_empty() else ground + combat_offset(index)
	return bounds

func conservative_contact_radius(index: int) -> float:
	if combat_proxy != null:
		return 256.0 # Native exact-curve 128px proof does not cover coarse proxy boxes.
	# Original native body/all-shield curves include unaimed attacks. Guard/
	# parry, possible IK, live presenters and unknown clips keep the original
	# broad phase. Match contact_sample's aim gate without computing its time.
	if index == 0 or _uses_live_presenter(index):
		return 256.0
	var unit: Dictionary = combat_units[index]
	var saved_aim: Array = unit.get("aim", [])
	if bool(combat_hot_get(index, &"attack")) and facing[index] == Vector2i.DOWN and saved_aim.size() == 2:
		# Retain 256 throughout this aimed attack, even when its current native
		# windup/recovery weight is zero. No new phase/IK-bound assumption.
		return 256.0
	var clip := _combat_clip(index)
	if not _combat_bake.get("contact_clocks", {}).has(clip):
		return 256.0
	var clock: Array = _combat_bake.contact_clocks[clip][_soldier_direction_id(facing[index])]
	var appearance: Dictionary = _contact_appearance(index)
	var source: RefCounted = contact_source_for(appearance)
	return source.conservative_nonattack_radius(clock[0], appearance) if source != null and source.conservative_nonattack_bounds_enabled else 256.0

func incoming_geometry(index: int) -> Dictionary:
	# A read-only projection of this original person's current pose. The Lab may
	# retain it only inside the synchronous post-advance/pre-contact batch.
	if combat_proxy == null and _uses_live_contact_presenter(index):
		return {"body": combat_shapes(index, "body"), "shield": combat_shapes(index, "shield"),
			"parry": combat_shapes(index, "parry"), "bounds": combat_bounds(index)}
	var pose := _continuous_pose(index, false)
	if pose.is_empty(): return {"body": [], "shield": [], "parry": [], "bounds": Rect2()}
	var origin: Vector2 = _contact_inputs(index).origin if not _contact_batch_inputs.is_empty() else combat_ground(index) + combat_offset(index)
	var bounds: Rect2 = pose.hurt_bounds
	bounds.position += origin
	return {"body": CombatGeometry.shifted(pose.body, origin), "shield": CombatGeometry.shifted(pose.shield, origin),
		"parry": CombatGeometry.shifted(pose.parry, origin), "bounds": bounds}

func combat_contact(index: int, previous: Array[PackedVector2Array], current: Array[PackedVector2Array], ranged: bool = false, sampled_geometry: Dictionary = {}, prepared: Array = []) -> Dictionary:
	var bodies: Array[PackedVector2Array] = combat_shapes(index, "body") if sampled_geometry.is_empty() else sampled_geometry.body
	var shields: Array[PackedVector2Array] = combat_shapes(index, "shield") if sampled_geometry.is_empty() else sampled_geometry.shield
	if prepared.is_empty():
		prepared = CombatGeometry.prepare_sweeps(previous, current)
	var hit := CombatGeometry.person_contact(previous, current, bodies, shields, prepared)
	if not ranged:
		var parrying: Array[PackedVector2Array] = combat_shapes(index, "parry") if sampled_geometry.is_empty() else sampled_geometry.parry
		var parry := CombatGeometry.contact(previous, current, parrying, prepared)
		if not parry.is_empty() and (hit.is_empty() or float(parry.fraction) <= float(hit.fraction)):
			hit = parry
			hit["shield"] = true
			hit["block_kind"] = "parry"
	if not hit.is_empty():
		hit["target"] = self
		hit["target_unit"] = index
		hit["identity"] = combat_identity(index)
		hit["faction"] = faction_id
	return hit

func contact_protection(index: int, hit: Dictionary, profile: Dictionary) -> Vector2:
	if combat_proxy != null:
		var body_index := (5 if str(hit.get("block_kind", "shield")) == "parry" else 3) if bool(hit.shield) else int(hit.body)
		return combat_proxy.protection(equipment_appearance(index), body_index, str(profile.kind))
	var point: Vector2 = hit.point
	if bool(hit.shield):
		var bodies := combat_shapes(index, "body")
		var arm_index := 5 if str(hit.get("block_kind", "shield")) == "parry" else 3
		if bodies.size() > arm_index:
			point = Vector2.ZERO
			for vertex: Vector2 in bodies[arm_index]:
				point += vertex
			point /= bodies[arm_index].size()
	if _uses_live_contact_presenter(index):
		if _uses_pooled_captain_geometry(index):
			var entry := _captain_geometry_entry(index)
			var captain_inputs := _contact_inputs(index) if not _contact_batch_inputs.is_empty() else {}
			if not _sync_pooled_captain(index, entry, captain_inputs): return Vector2.ZERO
			return entry.geometry.armor_at({"editor": entry.editor, "player_sprite": entry.sprite}, point, str(profile.kind))
		var presenter: Variant = _unit_editor(index)
		if presenter == null or index >= _sprites.size(): return Vector2.ZERO
		# Stance moves between quantized animation frames. Armor is projected live,
		# so its origin must follow the same current origin as cached hurtboxes.
		_sync_captain_combat(combat_frame(index), index)
		return _combat_geometry.armor_at({"editor": presenter, "player_sprite": _sprites[index]}, point, str(profile.kind))
	var inputs := _contact_inputs(index) if not _contact_batch_inputs.is_empty() else {}
	var sample: Array = inputs.sample if not inputs.is_empty() else contact_sample(index)
	var local_point: Vector2 = point - inputs.ground - inputs.offset if not inputs.is_empty() else point - combat_ground(index) - combat_offset(index)
	var appearance: Dictionary = inputs.appearance if not inputs.is_empty() else _contact_appearance(index)
	var source: RefCounted = contact_source_for(appearance)
	if source == null:
		push_error("MISSING_ASSET: original same-body armor contact source was not prepared")
		return Vector2.ZERO
	return source.armor_at(sample[0], sample[1], sample[2], local_point, str(profile.kind), sample[3], sample[4], appearance)

func is_sustain_routed() -> bool:
	return sustain_routed_query.is_valid() and bool(sustain_routed_query.call(self))

func morale_retreat_terminal() -> bool:
	return bool(_retreat_resolution.get("terminal", false))

func begin_morale_retreat() -> Dictionary:
	if has_ship_journey(): return SiteRuntime.fail("BUSY", "原供養潰退狀態保留；旅程中不在歷史 Site 下地面退令")
	if not combat_enabled or not is_sustain_routed():
		return SiteRuntime.fail("NOT_ROUTED")
	if morale_retreat_terminal():
		return SiteRuntime.ok("潰退已結束")
	if str(_retreat_resolution.get("reason", "")) == "morale_collapse":
		return SiteRuntime.ok("正撤退中")
	if vehicle_transport != null: vehicle_transport.stop_team_ships(team_id)
	cancel_combat_deployment_for_forced_order()
	_next_order_serial()
	combat_order = CombatOrder.RETREAT
	combat_attacking = false
	needs_attack_order = true
	_clear_member_attack_targets()
	_stop_tactical_ai()
	_retreat_pair_pending.clear()
	_retreat_pairs_used.clear()
	_retreat_resolution = {"version": 1, "reason": "morale_collapse", "terminal": false}
	_retreat_paths.clear()
	_retreat_path_revision = -1
	command_status = "士氣崩潰；尋找離圖退路"
	return SiteRuntime.ok(command_status)

func finish_morale_retreat() -> void:
	if _retreat_resolution.is_empty() or morale_retreat_terminal():
		return
	_retreat_resolution.clear()
	_retreat_paths.clear()
	if combat_order == CombatOrder.RETREAT:
		combat_order = CombatOrder.HOLD
		command_status = "已完成整補；守位自衛"

func _retreat_refuge_cells() -> Dictionary:
	var refuges: Dictionary = {}
	if _coordinator != null:
		for other in _coordinator.get_active_formations():
			if other == self or not ("data" in other) or other.data != data or not ("faction_id" in other) or int(other.faction_id) != faction_id:
				continue
			if other.has_method("is_sustain_routed") and other.is_sustain_routed():
				continue
			if not other.has_method("get_active_members_occupancy"):
				continue
			for cell: Vector2i in other.get_active_members_occupancy().values():
				for direction: Vector2i in TerrainData.DIRECTIONS:
					var refuge := cell + direction
					if data.can_step(cell, refuge) and data.is_walkable(refuge):
						refuges[refuge] = {"kind": "ally", "target_id": int(other.team_id)}
	if data.site.has("features"):
		var hostile_occupancy := _retreat_hard_blockers()
		for key: Variant in data.site.features.keys():
			var feature: Dictionary = data.site.features[key]
			var kind := str(feature.get("kind", ""))
			# SOL P4-B: explicit completed facilities and cover; retain original entrance checks.
			if str(feature.get("stage", "")) != "complete" or kind not in ["house", "saltworks", "kiln", "charcoal", "smelter", "smithy", "tannery", "weaver", "fighting_position"] or not SiteRuntime.feature_usable(feature):
				continue
			var entrance_index := int(feature.get("entrance", -1))
			if entrance_index < 0 or entrance_index >= data.size.x * data.size.y:
				continue
			var entrance := data.cell_from_index(entrance_index)
			var hostile_actor_at_entrance := false
			for actor: Variant in [player, npc]:
				if actor != null and is_instance_valid(actor) and "faction_id" in actor and int(actor.faction_id) != faction_id \
					and (actor.occupies_cell(entrance) if actor.has_method("occupies_cell") else actor.terrain_cell == entrance):
					hostile_actor_at_entrance = true
			if not data.is_walkable(entrance) or hostile_occupancy.has(entrance) or hostile_actor_at_entrance:
				continue
			var approaches: Array[Vector2i] = [entrance]
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var near := entrance + direction
				if data.can_step(entrance, near):
					approaches.append(near)
			for approach: Vector2i in approaches:
				if not refuges.has(approach):
					refuges[approach] = {"kind": "building", "target_id": str(key)}
	return refuges

func _retreat_hard_blockers() -> Dictionary:
	var blocked: Dictionary = {}
	if _coordinator == null:
		return blocked
	for other in _coordinator.get_active_formations():
		if other == self or not ("faction_id" in other) or int(other.faction_id) == faction_id or not other.has_method("get_active_members_occupancy"):
			continue
		for cell: Vector2i in other.get_active_members_occupancy().values():
			blocked[cell] = true
	return blocked

func _retreat_static_route(start: Vector2i, refuges: Dictionary, blocked: Dictionary = {}, check_external: bool = true) -> Dictionary:
	if not data.is_walkable(start):
		return {"kind": "surrender", "path": []}
	var frontier: Array[Vector2i] = [start]
	var predecessor: Dictionary = {start: INVALID_CELL}
	var head := 0
	var first_refuge := INVALID_CELL
	var exit_cell := INVALID_CELL
	while head < frontier.size():
		var cell: Vector2i = frontier[head]
		head += 1
		if _edge_distance(cell) == 0:
			exit_cell = cell
			break # Full static reachability proves that no closer refuge outranks an edge.
		if first_refuge == INVALID_CELL and refuges.has(cell):
			first_refuge = cell
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not predecessor.has(next) and data.can_step(cell, next) and not blocked.has(next) \
				and (vehicle_transport == null or not vehicle_transport.blocks_cell(next)) and (not check_external or not _is_external_cell(next)):
				predecessor[next] = cell
				frontier.append(next)
	var target := exit_cell if exit_cell != INVALID_CELL else first_refuge
	if target == INVALID_CELL:
		return {"kind": "surrender", "path": []}
	var path: Array[Vector2i] = [target]
	while path[0] != start:
		path.push_front(predecessor[path[0]])
	var result: Dictionary = {"kind": "edge" if exit_cell != INVALID_CELL else str(refuges[target].kind), "target": target, "path": path}
	if exit_cell == INVALID_CELL:
		result["target_id"] = refuges[target].target_id
	return result

func _retreat_available_route(start: Vector2i, refuges: Dictionary, static_refuges: Dictionary, blocked: Dictionary, temporary_blocked: Dictionary = {}) -> Dictionary:
	var dynamic_blocked := blocked.duplicate()
	dynamic_blocked.merge(temporary_blocked, true)
	var route := _retreat_static_route(start, refuges, dynamic_blocked)
	if str(route.kind) == "surrender" and str(_retreat_static_route(start, static_refuges, blocked, false).kind) != "surrender":
		return {"kind": "wait", "path": []} # A transient actor/claim still has a reachable route once it clears.
	return route

func _finish_site_exit(index: int) -> void:
	if _ship_embarked(index): return
	if bool(combat_hot_get(index, &"site_exited", false)) or moving_to[index] != INVALID_CELL or _edge_distance(cells[index]) != 0:
		return
	if vehicle_transport != null and vehicle_transport.is_operator(combat_identity(index)):
		return
	if int(_cell_owners.get(cells[index], -1)) == index:
		_cell_owners.erase(cells[index])
	combat_hot_set(index, &"site_exited", true)
	combat_hot_set(index, &"present", false)
	combat_hot_set(index, &"attack", false)
	combat_units[index].target = -1
	combat_slots[index] = cells[index]
	_command_dirty = true
	settle_combat_command()
	_visual_dirty = true
	if _batch_view != null and _batch_view.has_method("remove"):
		_batch_view.remove(index)

func exit_controlled_site_retreat(index: int, direction: Vector2i) -> Dictionary:
	if _ship_embarked(index): return SiteRuntime.fail("EMBARKED", "船上人物須先依法靠岸離船，不能沿歷史岸格退場")
	if combat_order != CombatOrder.RETREAT or str(_retreat_resolution.get("reason", "")) != "morale_collapse" or not is_sustain_routed():
		return SiteRuntime.fail("NOT_ROUTED", "只有士氣崩潰後可離開地圖")
	if index != PLAYER_MEMBER and (index < 0 or index >= combat_units.size()):
		return SiteRuntime.fail("NO_TARGET")
	if index == PLAYER_MEMBER and not is_instance_valid(player_member):
		return SiteRuntime.fail("NO_TARGET")
	if not is_controlled_person(index) or direction not in TerrainData.DIRECTIONS:
		return SiteRuntime.fail("NO_AUTHORITY")
	var actor := index == PLAYER_MEMBER
	var cell: Vector2i = player_member.terrain_cell if actor else cells[index]
	if _edge_distance(cell) != 0 or data.contains(cell + direction):
		return SiteRuntime.fail("BLOCKED", "須先走到地圖邊界，再向外離開")
	if actor:
		if not player_member.can_act() or player_member.is_moving() or player_member.action_time > 0.0:
			return SiteRuntime.fail("BUSY", "先完成原人物動作")
		player_member.site_exited = true
		player_member.hide()
		player_present = false
		player_goal = INVALID_CELL
	else:
		if not combat_can_act(index) or moving_to[index] != INVALID_CELL or vehicle_transport != null and vehicle_transport.is_operator(combat_identity(index)):
			return SiteRuntime.fail("BUSY", "先完成原人物或載具步進")
		_finish_site_exit(index)
		var members: Dictionary = _retreat_resolution.get("members", {})
		members[str(combat_identity(index))] = {"kind": "edge", "target": [cell.x, cell.y], "status": "exited"}
		_retreat_resolution["members"] = members
	_command_dirty = true
	settle_combat_command()
	_refresh_morale_retreat_terminal()
	return SiteRuntime.ok("原人物已離開當前地圖")

func morale_retreat_sheltered() -> bool:
	if _team_has_embarked(): return false
	if combat_order != CombatOrder.RETREAT or str(_retreat_resolution.get("reason", "")) != "morale_collapse":
		return false
	var members: Dictionary = _retreat_resolution.get("members", {})
	var refuges := _retreat_refuge_cells()
	var sheltered := false
	for index in range(combat_units.size()):
		if not is_member(index) or float(combat_hot_get(index, &"hp", 0.0)) <= 0.0 or bool(combat_hot_get(index, &"departed", false)) \
			or bool(combat_hot_get(index, &"site_exited", false)) or bool(combat_hot_get(index, &"surrender_pending", false)) \
			or bool(combat_hot_get(index, &"captive", false)):
			continue
		var entry: Dictionary = members.get(str(combat_identity(index)), {})
		if str(entry.get("status", "")) != "sheltered" or not refuges.has(cells[index]):
			return false
		sheltered = true
	if is_instance_valid(player_member) and player_member.hp > 0.0 and not player_member.site_exited and not player_member.surrender_pending and not player_member.captive:
		if player_goal != player_member.terrain_cell or not refuges.has(player_member.terrain_cell):
			return false
		sheltered = true
	return sheltered

func _refresh_morale_retreat_terminal() -> void:
	for index in range(combat_units.size()):
		if is_member(index) and float(combat_hot_get(index, &"hp", 0.0)) > 0.0 and not bool(combat_hot_get(index, &"departed", false)) \
			and not bool(combat_hot_get(index, &"site_exited", false)) and not bool(combat_hot_get(index, &"surrender_pending", false)) \
			and not bool(combat_hot_get(index, &"captive", false)):
			_retreat_resolution["terminal"] = false
			return
	_retreat_resolution["terminal"] = not is_instance_valid(player_member) or player_member.hp <= 0.0 \
		or player_member.site_exited or player_member.surrender_pending or player_member.captive
	if bool(_retreat_resolution["terminal"]):
		command_status = "撤出完成；其餘原地待俘"

func _update_morale_retreat() -> void:
	if _retreat_path_revision != data.navigation_revision:
		_retreat_paths.clear()
		_retreat_path_revision = data.navigation_revision
	var refuges := _retreat_refuge_cells()
	var members: Dictionary = _retreat_resolution.get("members", {})
	var hard_blocked := _retreat_hard_blockers()
	var active: Array[int] = _get_active_member_ids()
	var temporary_blocked: Dictionary = {}
	for occupied_cell: Vector2i in _cell_owners.keys():
		var owner_index: int = int(_cell_owners[occupied_cell])
		if owner_index >= 0 and owner_index < combat_units.size() and not active.has(combat_identity(owner_index)):
			temporary_blocked[occupied_cell] = true
	var claimed_refuges: Dictionary = {}
	for raw_id in members.keys():
		if not active.has(int(raw_id)):
			continue
		var claim: Dictionary = members[raw_id]
		var coordinates: Array = claim.get("target", [])
		if str(claim.get("kind", "")) in ["ally", "building"] and str(claim.get("status", "")) in ["moving", "sheltered"] and coordinates.size() == 2:
			var claimed_cell := Vector2i(int(coordinates[0]), int(coordinates[1]))
			if refuges.has(claimed_cell):
				claimed_refuges[claimed_cell] = int(raw_id)
	for mid: int in active:
		var index := index_for_identity(mid)
		if index < 0 or _ship_embarked(index) or moving_to[index] != INVALID_CELL:
			continue # An accepted Grid edge reaches its endpoint before replanning.
		if bool(combat_hot_get(index, &"surrender_pending", false)) or bool(combat_hot_get(index, &"site_exited", false)):
			continue
		var previous: Dictionary = members.get(str(mid), {})
		if vehicle_transport != null and not vehicle_transport.prepare_morale_retreat(self, index):
			_retreat_paths.erase(mid)
			if vehicle_transport.morale_retreat_terrain_trapped(self, index):
				var prior_target: Array = previous.get("target", [])
				if prior_target.size() == 2:
					var prior_cell := Vector2i(int(prior_target[0]), int(prior_target[1]))
					if int(claimed_refuges.get(prior_cell, -1)) == mid:
						claimed_refuges.erase(prior_cell)
				combat_hot_set(index, &"surrender_pending", true)
				vehicle_transport.settle_operators()
				combat_slots[index] = cells[index]
				_command_dirty = true
				settle_combat_command()
				members[str(mid)] = {"kind": "surrender", "status": "surrendered"}
			continue # Preserve the original vehicle step or dismount before foot routing.
		if str(previous.get("status", "")) == "sheltered" and refuges.has(cells[index]):
			var reopened_edge := _retreat_static_route(cells[index], {}, hard_blocked)
			if str(reopened_edge.kind) != "edge":
				continue
			_retreat_paths[mid] = reopened_edge
		var available_refuges := refuges.duplicate()
		var blocked_for_member := hard_blocked.duplicate()
		for refuge_cell: Vector2i in claimed_refuges.keys():
			var claimant: int = int(claimed_refuges[refuge_cell])
			if claimant != mid:
				available_refuges.erase(refuge_cell)
				if str(members.get(str(claimant), {}).get("status", "")) == "sheltered":
					blocked_for_member[refuge_cell] = true
		for refuge_cell: Vector2i in available_refuges.keys():
			if hard_blocked.has(refuge_cell) or vehicle_transport != null and vehicle_transport.blocks_cell(refuge_cell):
				available_refuges.erase(refuge_cell)
		var static_refuges := available_refuges.duplicate()
		for refuge_cell: Vector2i in available_refuges.keys():
			if temporary_blocked.has(refuge_cell) or _is_external_cell(refuge_cell):
				available_refuges.erase(refuge_cell)
		var route: Dictionary = _retreat_paths.get(mid, {})
		var path: Array = route.get("path", [])
		var next_index := path.find(cells[index]) + 1
		var next_blocked := next_index > 0 and next_index < path.size() and (blocked_for_member.has(path[next_index]) or temporary_blocked.has(path[next_index]) or _is_external_cell(path[next_index]))
		if path.is_empty() or not path.has(cells[index]) or next_blocked or (str(route.get("kind", "")) in ["ally", "building"] and not available_refuges.has(route.get("target", INVALID_CELL))):
			route = _retreat_available_route(cells[index], available_refuges, static_refuges, blocked_for_member, temporary_blocked)
			_retreat_paths[mid] = route
			path = route.get("path", [])
		if str(route.kind) in ["surrender", "wait"]:
			if previous.get("target", []) is Array and (previous.get("target", []) as Array).size() == 2:
				var old_target: Array = previous.target
				var old_cell := Vector2i(int(old_target[0]), int(old_target[1]))
				if int(claimed_refuges.get(old_cell, -1)) == mid:
					claimed_refuges.erase(old_cell)
			if str(route.kind) == "wait":
				combat_slots[index] = cells[index]
				members[str(mid)] = {"kind": "wait", "status": "waiting"}
				continue
			combat_hot_set(index, &"surrender_pending", true)
			combat_slots[index] = cells[index]
			_command_dirty = true
			settle_combat_command()
			members[str(mid)] = {"kind": "surrender", "status": "surrendered"}
			continue
		var at := path.find(cells[index])
		if at > 0:
			path = path.slice(at)
			route["path"] = path
			_retreat_paths[mid] = route
		var target: Vector2i = route.target
		if previous.get("target", []) is Array and (previous.get("target", []) as Array).size() == 2:
			var prior_target: Array = previous.target
			var prior_cell := Vector2i(int(prior_target[0]), int(prior_target[1]))
			if prior_cell != target and int(claimed_refuges.get(prior_cell, -1)) == mid:
				claimed_refuges.erase(prior_cell)
		combat_slots[index] = target
		members[str(mid)] = {"kind": route.kind, "target": [target.x, target.y], "target_id": route.get("target_id", ""), "status": "moving"}
		if str(route.kind) in ["ally", "building"]:
			claimed_refuges[target] = mid
		if cells[index] == target:
			if str(route.kind) == "edge":
				if not is_controlled_person(index):
					_finish_site_exit(index)
					members[str(mid)].status = "exited"
			else:
				members[str(mid)].status = "sheltered"
		elif at >= 0 and at + 1 < path.size() and not is_controlled_person(index) and not _combat_action_blocks_step(index):
			_reserve_combat_step(index, path[at + 1])
	_retreat_resolution["members"] = members
	if is_instance_valid(player_member) and not _ship_embarked(PLAYER_MEMBER) and player_member.hp > 0.0 and not player_member.site_exited and not player_member.surrender_pending and not player_member.captive and not player_member.is_moving():
		if player_goal == player_member.terrain_cell and refuges.has(player_member.terrain_cell):
			var reopened_player_edge := _retreat_static_route(player_member.terrain_cell, {}, hard_blocked)
			if str(reopened_player_edge.kind) == "edge":
				_retreat_paths[player_member.person_id] = reopened_player_edge
		var player_refuges := refuges.duplicate()
		var player_blocked := hard_blocked.duplicate()
		for refuge_cell: Vector2i in claimed_refuges.keys():
			player_refuges.erase(refuge_cell)
			if str(members.get(str(claimed_refuges[refuge_cell]), {}).get("status", "")) == "sheltered":
				player_blocked[refuge_cell] = true
		for refuge_cell: Vector2i in player_refuges.keys():
			if hard_blocked.has(refuge_cell) or vehicle_transport != null and vehicle_transport.blocks_cell(refuge_cell):
				player_refuges.erase(refuge_cell)
		var player_static_refuges := player_refuges.duplicate()
		for refuge_cell: Vector2i in player_refuges.keys():
			if temporary_blocked.has(refuge_cell) or refuge_cell != player_member.terrain_cell and _is_external_cell(refuge_cell):
				player_refuges.erase(refuge_cell)
		var player_route: Dictionary = _retreat_paths.get(player_member.person_id, {})
		var player_path: Array = player_route.get("path", [])
		var player_next := player_path.find(player_member.terrain_cell) + 1
		var player_next_blocked := player_next > 0 and player_next < player_path.size() and (player_blocked.has(player_path[player_next]) or temporary_blocked.has(player_path[player_next]) or _is_external_cell(player_path[player_next]))
		if not player_path.has(player_member.terrain_cell) or player_next_blocked or (str(player_route.get("kind", "")) in ["ally", "building"] and not player_refuges.has(player_route.get("target", INVALID_CELL))):
			player_route = _retreat_available_route(player_member.terrain_cell, player_refuges, player_static_refuges, player_blocked, temporary_blocked)
			_retreat_paths[player_member.person_id] = player_route
		if str(player_route.kind) == "surrender":
			player_member.surrender_pending = true
			player_present = false
			_command_dirty = true
			settle_combat_command()
		elif str(player_route.kind) == "wait":
			player_goal = player_member.terrain_cell
		else:
			player_goal = player_route.target
	_refresh_morale_retreat_terminal()

func start_unit_attack(index: int, target_cell: Vector2i, identity: int = -1, self_defense: bool = false) -> bool:
	if _siege_crew(index) or not _ship_attack_allowed(index): return false
	if not garrison_feature_id.is_empty(): return false
	if is_inside_tree() and get_tree().paused:
		return false
	var source_cell := _combat_attack_cell(index)
	var ship_pair := _combat_ship_pair(index, identity)
	var ship_contact := ship_pair and _combat_ship_contact(index, identity)
	if exchange_enabled:
		if is_member(index) and not is_controlled_person(index) and is_sustain_routed() and (not self_defense or combat_order != CombatOrder.HOLD):
			return false
		if not exchange_ready(index):
			return false
		if ship_contact or not ship_pair and source_cell.distance_squared_to(target_cell) == 1:
			if not ship_pair and not data.can_attack_across(source_cell, target_cell):
				return false
		else:
			var profile := ranged_profile(index)
			if profile.is_empty() or not SiteCombatRules.ranged_in_range(source_cell, target_cell, float(profile.range)) or not _combat_ranged_line_clear(index, source_cell, target_cell):
				return false
		combat_units[index].target = identity
		var direction := target_cell - source_cell
		if direction != Vector2i.ZERO:
			facing[index] = Vector2i(signi(direction.x), 0) if absi(direction.x) >= absi(direction.y) else Vector2i(0, signi(direction.y))
		_mark_visual_row(index)
		return true # Lab owns the next adjacent exchange, never aim geometry.
	if is_member(index) and not is_controlled_person(index) and is_sustain_routed() and (not self_defense or combat_order != CombatOrder.HOLD):
		return false # No-route self-defense only; never replace a committed retreat.
	if not combat_can_act(index) or bool(combat_hot_get(index, &"attack")) or moving_to[index] != INVALID_CELL or str(combat_hot_get(index, &"pose")) in ["guard_break", "guard_raise", "guard", "guard_lower", "rescue"]:
		return false
	var offset := target_cell - source_cell
	if ship_pair and not ship_contact or not ship_pair and (offset == Vector2i.ZERO or absi(offset.x) + absi(offset.y) > 2 or not SiteCombatRules.terrain_line_clear(data, source_cell, target_cell)):
		return false
	if offset != Vector2i.ZERO:
		facing[index] = Vector2i(signi(offset.x), 0) if absi(offset.x) >= absi(offset.y) else Vector2i(0, signi(offset.y))
	var unit: Dictionary = combat_units[index]
	combat_hot_set(index, &"pose", str(attack_clip(index)))
	combat_hot_set(index, &"age", 0.0)
	combat_hot_set(index, &"attack", true)
	unit["blocked"] = false
	unit["hits"] = {}
	unit["previous"] = []
	unit["status"] = "Attacking"
	unit["attack_reduction"] = SiteCombatRules.diminishing(training if is_member(index) else 0.0, 0.15)
	unit["attack_fatigue"] = PersonFatigue.slowdown(PersonFatigue.read(unit))
	unit["target"] = identity
	unit["aim"] = []
	if identity > 0 and combat_target_query.is_valid():
		var target: Dictionary = combat_target_query.call(identity, true)
		if not target.is_empty():
			var shoulder := Vector2.INF
			if facing[index] == Vector2i.DOWN:
				var presenter: Variant = _unit_editor(index)
				if combat_proxy != null:
					shoulder = _continuous_pose(index).shoulder + combat_ground(index) + combat_offset(index)
				elif _uses_pooled_captain_geometry(index):
					var entry := _captain_geometry_entry(index)
					if _sync_pooled_captain(index, entry):
						var skeleton := entry.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
						shoulder = entry.geometry.project({"editor": entry.editor, "player_sprite": entry.sprite}, skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("J_Bip_R_UpperArm")).origin)
				elif presenter != null and index < _sprites.size():
					_sync_captain_combat(combat_frame(index), index)
					var skeleton := presenter.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
					shoulder = _combat_geometry.project({"editor": presenter, "player_sprite": _sprites[index]}, skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("J_Bip_R_UpperArm")).origin)
				elif not _uses_live_presenter(index):
					shoulder = _continuous_pose(index).shoulder + combat_ground(index) + combat_offset(index)
			var aim := CombatGeometry.attack_aim_point(target.bodies, target.position, shoulder)
			unit["aim"] = [aim.x, aim.y]
	combat_event.emit(CombatTimings.action_duration(attack_clip(index), float(unit.attack_reduction), float(unit.attack_fatigue)) + 10.0)
	return true

func set_unit_guard(index: int, enabled: bool) -> bool:
	if _siege_crew(index) or not _ship_attack_allowed(index): return false
	if is_inside_tree() and get_tree().paused:
		return false
	if not combat_can_act(index) or moving_to[index] != INVALID_CELL or bool(combat_hot_get(index, &"attack")) or (exchange_enabled and float(combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0) or str(combat_hot_get(index, &"pose")) in ["guard_break", "guard_raise", "guard_lower", "rescue"]:
		return false
	if exchange_enabled and combat_hot_has(index, &"exchange_visual"):
		combat_hot_erase(index, &"exchange_visual")
		_mark_visual_row(index) # An accepted explicit stance ends, rather than hides, the previous result.
	if (str(combat_hot_get(index, &"pose")) == "guard") == enabled:
		return true
	combat_hot_set(index, &"pose", "guard_raise" if enabled else "guard_lower")
	combat_hot_set(index, &"age", 0.0)
	_mark_visual_row(index)
	return true

func start_unit_rescue(index: int, patient: int) -> bool:
	if _siege_crew(index): return false
	if is_inside_tree() and get_tree().paused:
		return false
	if (player_member.knockout_left if patient == PLAYER_MEMBER and is_instance_valid(player_member) else (float(combat_hot_get(patient, &"ko")) if patient >= 0 and patient < combat_units.size() else 0.0)) <= SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS:
		return false
	if not combat_can_act(index) or (exchange_enabled and float(combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0) or index == patient or moving_to[index] != INVALID_CELL or str(combat_hot_get(index, &"pose")) != "idle" or not _rescue_reachable(index, patient):
		return false
	if patient_has_rescuer(patient):
		return false
	var offset := (player_member.terrain_cell if patient == PLAYER_MEMBER else cells[patient]) - cells[index]
	if _ship_embarked(index):
		var ship_offset := combat_ground(patient) - combat_ground(index)
		offset = Vector2i.RIGHT if ship_offset.x > 0.0 else Vector2i.LEFT
		if absf(ship_offset.y) >= absf(ship_offset.x): offset = Vector2i.DOWN if ship_offset.y > 0.0 else Vector2i.UP
	facing[index] = offset
	_unit_rescues[index] = {"patient": patient, "revision": player_member._received_effective_hit if patient == PLAYER_MEMBER else 0}
	if patient == PLAYER_MEMBER:
		player_member._army_rescuer = self
	combat_hot_set(index, &"pose", "rescue")
	combat_hot_set(index, &"age", 0.0)
	if exchange_enabled:
		combat_hot_erase(index, &"exchange_visual")
	_mark_visual_row(index)
	return true

func patient_has_rescuer(patient: int) -> bool:
	if _external_rescuers.has(patient):
		return true
	if patient == PLAYER_MEMBER and is_instance_valid(player_member) and (is_instance_valid(player_member._rescuer) or is_instance_valid(player_member._army_rescuer)):
		return true
	for entry: Dictionary in _unit_rescues.values():
		if int(entry.patient) == patient:
			return true
	return false

func _rescue_reachable(index: int, patient: int) -> bool:
	if _ship_in_journey(index) or _ship_in_journey(patient): return false
	if member_gone(patient):
		return false
	var cell: Vector2i
	if patient == PLAYER_MEMBER:
		if player_member.knockout_left <= 0.0 or player_member.is_moving():
			return false
		cell = player_member.terrain_cell
	else:
		if float(combat_hot_get(patient, &"ko")) <= 0.0 or moving_to[patient] != INVALID_CELL:
			return false
		cell = cells[patient]
	if _ship_embarked(index) or _ship_embarked(patient):
		return _ship_embarked(index) and _ship_embarked(patient) and _ship_vehicle_id(index) == _ship_vehicle_id(patient) and combat_ground(index).distance_to(combat_ground(patient)) <= TerrainRenderer.CELL_PIXELS + 0.000001
	var offset := cell - cells[index]
	return absi(offset.x) + absi(offset.y) == 1 and data.can_step(cells[index], cell)

func _cancel_unit_rescue(index: int) -> void:
	if _unit_rescues.has(index) and int(_unit_rescues[index].patient) == PLAYER_MEMBER and is_instance_valid(player_member) and player_member._army_rescuer == self:
		player_member._army_rescuer = null
	_unit_rescues.erase(index)
	if str(combat_hot_get(index, &"pose")) == "rescue":
		combat_hot_set(index, &"pose", "idle")
		combat_hot_set(index, &"age", 0.0)
		_mark_visual_row(index)

func _wake_unit(index: int) -> void:
	var region_sink: Variant = get_meta(&"region_wake_sink", Callable())
	if region_sink is Callable and region_sink.is_valid() and bool(region_sink.call(combat_identity(index))):
		return
	var unit: Dictionary = combat_units[index]
	var embarked := _ship_embarked(index)
	var rider: bool = vehicle_transport != null and vehicle_transport.occupies_own_horse(combat_identity(index), cells[index])
	var tower_origin: bool = vehicle_transport != null and vehicle_transport.person_origin_exception(combat_identity(index), cells[index])
	var occupied := _cell_owners.has(cells[index]) or _reserved_cells.has(cells[index]) if rider or tower_origin else blocks_person_cell(cells[index])
	var external_occupied: bool = _is_external_cell(cells[index], combat_identity(index), cells[index], INVALID_CELL, cells[index]) if tower_origin else _is_external_cell(cells[index], combat_identity(index) if rider else 0)
	if not embarked and (occupied or external_occupied):
		combat_hot_set(index, &"ko", 0.1)
		return
	combat_hot_set(index, &"ko", 0.0)
	unit["status"] = "Captive" if bool(combat_hot_get(index, &"captive")) else "Awake"
	if not embarked: _cell_owners[cells[index]] = index
	combat_hot_set(index, &"pose", "get_up")
	combat_hot_set(index, &"age", 0.0)
	combat_hot_set(index, &"stun", 30.0)
	combat_hot_set(index, &"grace", SiteCombatRules.STUN_GRACE)
	_command_dirty = true
	_mark_visual_row(index)

static func _get_idle_kernel() -> RefCounted:
	if _idle_kernel_checked: return _idle_kernel
	_idle_kernel_checked = true
	# Optional Windows x64 accelerator. Other builds retain the complete GD loop.
	if not OS.has_feature("windows") or not OS.has_feature("x86_64") or int(Engine.get_version_info().minor) < 4:
		return null
	if not FileAccess.file_exists("res://native/army_idle/bin/army_idle.windows.x86_64.dll"):
		return null
	if not GDExtensionManager.is_extension_loaded(IDLE_EXTENSION):
		if GDExtensionManager.load_extension(IDLE_EXTENSION) != GDExtensionManager.LOAD_STATUS_OK:
			return null
	if ClassDB.class_exists(&"ArmyIdleKernel"):
		_idle_kernel = ClassDB.instantiate(&"ArmyIdleKernel")
	return _idle_kernel

func _hold_empty_rescue_skip_admitted(query_owner: Object) -> bool:
	if not hold_empty_rescue_skip_enabled or get_script() != TerrainArmy or not query_owner is TerrainLab \
		or query_owner.get_script() != TerrainLab or enemy_query.get_method() != &"_nearest_unit_enemy" \
		or enemy_query.get_bound_arguments_count() != 0 or enemy_query.get_unbound_arguments_count() != 0:
		return false
	var lab := query_owner as TerrainLab
	if controlled_person_query.is_valid() and (controlled_person_query.get_object() != lab \
		or controlled_person_query.get_method() != &"controlled_person_id" \
		or controlled_person_query.get_bound_arguments_count() != 0 or controlled_person_query.get_unbound_arguments_count() != 0):
		return false
	if not person_busy_query.is_valid() and not sustain_routed_query.is_valid():
		return true
	var controller: SiteController = lab.site_controller
	if controller == null or controller.get_script() != SiteController or controller.lab != lab:
		return false
	if sustain_routed_query.is_valid() and (sustain_routed_query.get_object() != controller \
		or sustain_routed_query.get_method() != &"team_is_routed" \
		or sustain_routed_query.get_bound_arguments_count() != 0 or sustain_routed_query.get_unbound_arguments_count() != 0):
		return false
	if person_busy_query.is_valid() and (person_busy_query.get_object() != controller \
		or person_busy_query.get_method() != &"_person_has_duty" \
		or person_busy_query.get_bound_arguments_count() != 0 or person_busy_query.get_unbound_arguments_count() != 0 \
		or controller.person_actions == null or controller.person_actions.get_script() != SitePersonActions \
		or controller.work_team == null or controller.work_team.get_script() != SiteWorkTeam \
		or controller.vehicles == null or controller.vehicles.get_script() != SiteVehicleTransport):
		return false
	return true

func _hold_rescue_patient_from_columns() -> Variant:
	# null means use the original per-member reads. A bool is a complete answer.
	if not hold_rescue_column_enabled or not combat_hot_active() or _combat_hot_store.get_class() != "ArmyCombatHot" \
		or _combat_hot_store.get_script() != null:
		return null
	var count := combat_units.size()
	var members: PackedFloat64Array = combat_hot_column(&"member")
	var knockout: PackedFloat64Array = combat_hot_column(&"ko")
	if members.size() != count or knockout.size() != count:
		return null
	var borrowed := _combat_hot_borrowed_index
	if borrowed >= 0:
		if borrowed >= count or not _combat_hot_store.has_field(borrowed, "member") \
			or not _combat_hot_store.has_field(borrowed, "ko"):
			return null
		var live_ko := float(combat_hot_get(borrowed, &"ko"))
		if not is_finite(live_ko) or live_ko != knockout[borrowed] \
			or is_member(borrowed) != (members[borrowed] == 1.0):
			return null # The current borrowed Dictionary outranks the stored column.
	var possible := false
	for patient in range(count):
		if members[patient] != 0.0 and members[patient] != 1.0 \
			or not is_finite(knockout[patient]):
			return null
		if members[patient] == 1.0 and not (knockout[patient] <= SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS):
			possible = true
	if is_instance_valid(player_member):
		if not is_finite(player_member.knockout_left):
			return null
		possible = possible or not (player_member.knockout_left <= SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS)
	# Native column's absent member default is 1, exactly is_member(index)'s default.
	return possible

func _hold_no_patient_controlled_index() -> Variant:
	# This proof lives for one synchronous native prefix, never across an owner callback.
	if not native_hold_no_patient_enabled or not exchange_enabled or combat_order != CombatOrder.HOLD \
		or _combat_hot_borrowed_index >= 0 or not enemy_query.is_valid() \
		or not _hold_empty_rescue_skip_admitted(enemy_query.get_object()):
		return null
	var patient: Variant = _hold_rescue_patient_from_columns()
	if not patient is bool or bool(patient): return null
	hold_rescue_column_uses += 1
	if not controlled_person_query.is_valid(): return -1
	var controlled_id := int(controlled_person_query.call())
	var controlled_index := -1
	for index in range(combat_units.size()):
		if combat_identity(index) != controlled_id: continue
		if controlled_index >= 0: return null # Ambiguous control must keep the original per-row predicate.
		controlled_index = index
	return controlled_index

# HOLD candidates live only within one prepare_combat call. Claims stay live queries.
func _hold_rescue_candidates() -> Array[int]:
	var patients: Array[int] = []
	# Canonical hot readers are pure. Read member only for a possible patient;
	# retain ascending NPC indices, then PLAYER_MEMBER, exactly command_members order.
	for patient: int in range(combat_units.size()):
		if not (float(combat_hot_get(patient, &"ko")) <= SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS) and is_member(patient):
			patients.append(patient)
	if is_instance_valid(player_member) and not (player_member.knockout_left <= SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS):
		patients.append(PLAYER_MEMBER)
	return patients

func _hold_rescue_query_original(query: Callable, owner: Object, method: StringName) -> bool:
	return not query.is_valid() or query.get_object() == owner and query.get_method() == method and query.get_bound_arguments_count() == 0 and query.get_unbound_arguments_count() == 0

func _hold_rescue_candidate_cache_admitted() -> bool:
	if get_script() != TerrainArmy or data == null or data.get_script() != TerrainData:
		return false
	if _combat_hot_store != null and (_combat_hot_store.get_class() != "ArmyCombatHot" or _combat_hot_store.get_script() != null): return false
	if is_instance_valid(player_member) and player_member.get_script() not in [TerrainTestCharacter, TerrainTestNPC]: return false
	if not enemy_query.is_valid() and not controlled_person_query.is_valid(): return false
	var query_owner: Object = enemy_query.get_object() if enemy_query.is_valid() else controlled_person_query.get_object()
	if not query_owner is TerrainLab or query_owner.get_script() != TerrainLab: return false
	var lab: TerrainLab = query_owner
	if lab.terrain != data or not _hold_rescue_query_original(enemy_query, lab, &"_nearest_unit_enemy") or not _hold_rescue_query_original(controlled_person_query, lab, &"controlled_person_id"): return false
	if lab.site_controller != null and not lab.site_controller is SiteController: return false
	var controller: SiteController = lab.site_controller as SiteController
	if person_busy_query.is_valid() or sustain_routed_query.is_valid() or vehicle_transport != null:
		if controller == null or controller.lab != lab or not controller.get_script() is GDScript: return false
		if not _hold_rescue_query_original(person_busy_query, controller, &"_person_has_duty") or not _hold_rescue_query_original(sustain_routed_query, controller, &"team_is_routed"): return false
		if controller.person_actions == null or controller.person_actions.get_script() != SitePersonActions or controller.work_team == null or controller.work_team.get_script() != SiteWorkTeam or controller.vehicles == null or controller.vehicles.get_script() != SiteVehicleTransport: return false
		if controller.vehicles.lab != lab or controller.vehicles.controller != controller or controller.person_actions.lab != lab or controller.work_team.lab != lab: return false
		if vehicle_transport != null and vehicle_transport != controller.vehicles: return false
		if controller.get_script() != SiteController:
			# GDScript lists inherited declarations too; an override adds a second name.
			var readers: Dictionary = {&"_person_has_duty": 0, &"_is_delivering_person": 0, &"team_is_routed": 0, &"_supply_entry": 0, &"ship_person_in_journey": 0, &"ship_vehicle_in_journey": 0, &"ship_journey_active": 0, &"region_operation_pending": 0}
			var script: Script = controller.get_script()
			for entry: Dictionary in script.get_script_method_list():
				var method: StringName = StringName(entry.get("name", ""))
				if readers.has(method): readers[method] = int(readers[method]) + 1
			for count: int in readers.values():
				if count != 1: return false
	# The original nearest-enemy reader may call these owners. Unknown overrides keep the full scan.
	for team: TerrainArmy in lab.combat_armies:
		if team.get_script() != TerrainArmy or team._combat_hot_store != null and (team._combat_hot_store.get_class() != "ArmyCombatHot" or team._combat_hot_store.get_script() != null): return false
		# Original ship/person readers skip disabled armies; the journey reader
		# can only perform an empty identity lookup here. Unknown scripts/hot stores
		# were rejected above. Nonempty or PLAYER containers retain all guards.
		if not team.combat_enabled and team.combat_units.is_empty() and not is_instance_valid(team.player_member):
			continue
		if team.data != data or team.vehicle_transport != null and team.vehicle_transport != vehicle_transport: return false
	for actor: TerrainTestCharacter in lab.combat_actors:
		if actor.get_script() not in [TerrainTestCharacter, TerrainTestNPC]: return false
	return true

func prepare_combat(delta: float, game_seconds: float = -1.0) -> void:
	_invalidate_ship_projection()
	if not combat_enabled or delta <= 0.0 or (is_inside_tree() and get_tree().paused):
		return
	if game_seconds < 0.0:
		game_seconds = delta # Direct owner tests and previews use a 1:1 fallback.
	var hot_started := Time.get_ticks_usec() if combat_hot_diagnostics_enabled and combat_hot_active() else 0
	var profile_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	if is_instance_valid(player_member) or _team_has_embarked():
		_command_dirty = true # Observe independent player movement/KO on this same step.
	if _coordinator == null and _combat_deployment_plan != null:
		update_combat_deployment(delta)
	if combat_order in [CombatOrder.MOVE, CombatOrder.RETREAT, CombatOrder.RETURN]:
		for index in range(combat_units.size()):
			if is_member(index) and str(combat_hot_get(index, &"pose")) == "guard":
				set_unit_guard(index, false)
	_update_combat_orders(delta)
	profile_started = _profile_combat_stage("orders", profile_started)
	var hot_store := _combat_hot_store if native_idle_enabled and exchange_enabled and combat_hot_active() else null
	if combat_hot_active() and hot_store == null:
		_visual_full_dirty = true
	var kernel := _get_idle_kernel() if hot_store == null and native_idle_enabled and exchange_enabled else null
	# Recovery normally calls overridable visual/pose methods; custom scripts
	# retain those callbacks. The old zero-timer fast path is still available.
	var recovery_kernel: bool = kernel != null and native_recovery_enabled and game_seconds == delta and get_script() == TerrainArmy and kernel.has_method("advance_recovery_prefix")
	var end := combat_units.size() # Same fixed bound as the original range().
	var next := 0
	var hold_rescue_patient_checked := false
	var hold_rescue_patient_absent := false
	var hold_rescue_candidates_checked: bool = false
	var hold_rescue_cache_admission_checked: bool = false
	var hold_rescue_cache_admitted: bool = false
	var hold_rescue_candidates: Array[int] = []
	while next < end:
		var index := next
		# Finish each exceptional row BEFORE inspecting later rows: movement,
		# wake/rescue callbacks can change their state and the current order.
		if hot_store != null:
			var method := "advance_numeric_hold" if combat_order == CombatOrder.HOLD else "advance_numeric"
			if combat_hot_diagnostics_enabled: method += "_reason"
			var advanced: PackedInt32Array = hot_store.call(method, moving_to, move_progress, move_duration, _unit_rescues, index, end, delta, game_seconds, SiteCombatRules.STUN_RECOVERY)
			assert(advanced.size() == (3 if combat_hot_diagnostics_enabled else 2) and advanced[0] >= index and advanced[0] <= end)
			var native_calls := 1
			if advanced[1] == 3 and combat_order == CombatOrder.HOLD and native_hold_no_patient_enabled:
				var hold_method := "advance_numeric_hold_no_patient_reason" if combat_hot_diagnostics_enabled else "advance_numeric_hold_no_patient"
				if hot_store.has_method(hold_method):
					var controlled_index: Variant = _hold_no_patient_controlled_index()
					if controlled_index != null:
						var retry_start: int = advanced[0]
						advanced = hot_store.call(hold_method, moving_to, move_progress, move_duration, _unit_rescues, retry_start, end, delta, game_seconds, SiteCombatRules.STUN_RECOVERY, int(controlled_index))
						assert(advanced.size() == (3 if combat_hot_diagnostics_enabled else 2) and advanced[0] >= retry_start and advanced[0] <= end)
						native_calls += 1
			next = advanced[0]
			if combat_hot_diagnostics_enabled:
				_combat_hot_native_calls += native_calls
				_combat_hot_native_rows += next - index
				if advanced[1] != 0:
					_combat_hot_barriers[advanced[1]] = int(_combat_hot_barriers.get(advanced[1], 0)) + 1
					if advanced[1] == 3:
						var reason_code := int(advanced[2])
						var reason: String = COMBAT_HOT_OWNER_REASONS[reason_code] if reason_code > 0 and reason_code < COMBAT_HOT_OWNER_REASONS.size() else "unknown"
						_combat_hot_owner_reasons[reason] = int(_combat_hot_owner_reasons.get(reason, 0)) + 1
			if next >= end: break
			index = next
			# The owner completes this barrier row below. Any cross-row rescue or
			# contact mutation goes through combat_hot_set and marks that row too.
			_mark_visual_row(index)
		elif kernel != null and exchange_enabled and combat_order != CombatOrder.HOLD:
			if recovery_kernel:
				next = int(kernel.advance_recovery_prefix(combat_units, moving_to, _unit_rescues, index, end, delta, SiteCombatRules.STUN_RECOVERY))
				native_recovery_rows += next - index
			else:
				next = int(kernel.advance_prefix(combat_units, moving_to, _unit_rescues, index, end, delta))
			native_idle_calls += 1
			native_idle_rows += next - index
			if next >= end: break
			index = next
		next = index + 1 # Every original continue below consumes exactly one row.
		if _combat_hot_store != null:
			_borrow_combat_hot_row(index)
		var unit: Dictionary = combat_units[index]
		unit.age = float(unit.age) + delta
		# Original idle ATTACK rear ranks have no active recovery/movement work.
		# Normalize the same optional timers once, retain age/think exactly, and
		# leave all rescue/guard/hit/KO/moving rows on the complete owner path.
		if exchange_enabled and (combat_order != CombatOrder.HOLD or get_script() == TerrainArmy and not combat_hot_diagnostics_enabled \
			and (_combat_hot_store == null or _combat_hot_borrowed_index == index) and float(unit.think) > delta \
			and (not unit.has("exchange_visual") or unit.exchange_visual is Dictionary)) and unit.pose == "idle" and float(unit.hp) > 0.0 and float(unit.ko) <= 0.0 and moving_to[index] == INVALID_CELL and not _unit_rescues.has(index) \
			and unit.stun == 0.0 and unit.grace == 0.0 and (not unit.has("exchange_visual") or unit.exchange_visual.is_empty()) and unit.get("exchange_pose_duration", 0.0) == 0.0 \
			and unit.get("exchange_cooldown", 0.0) == 0.0 and unit.get("exchange_stagger", 0.0) == 0.0 and unit.get("exchange_skill_cooldown", 0.0) == 0.0 and unit.get("ranged_cooldown", 0.0) == 0.0:
			unit["exchange_cooldown"] = 0.0
			unit["exchange_stagger"] = 0.0
			unit["exchange_skill_cooldown"] = 0.0
			unit["ranged_cooldown"] = 0.0
			unit.grace = 0.0
			unit.stun = 0.0
			unit.think = maxf(0.0, float(unit.think) - delta)
			if _combat_hot_store != null: _return_combat_hot_row()
			continue
		if exchange_enabled:
			_advance_exchange_visual(index, delta)
			for field: String in ["exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown"]:
				var remaining := maxf(0.0, float(unit.get(field, 0.0)) - delta)
				unit[field] = 0.0 if remaining <= 0.000000001 else remaining
		if moving_to[index] != INVALID_CELL:
			move_progress[index] = CombatTimings.advance_movement_progress(move_progress[index], delta, move_duration[index])
			if move_progress[index] >= 1.0:
				hold_rescue_candidates_checked = false; hold_rescue_cache_admission_checked = false
				_complete_move(index)
		if float(unit.hp) <= 0.0:
			if _combat_hot_store != null: _return_combat_hot_row()
			continue
		if float(unit.ko) > 0.0:
			unit.ko = maxf(0.0, float(unit.ko) - game_seconds)
			if str(unit.pose) == "down" and float(unit.age) >= float(CombatTimings.POSE_SECONDS[&"down"]):
				unit.pose = "unconscious"
				unit.age = 0.0
			if float(unit.ko) <= 0.0:
				hold_rescue_candidates_checked = false; hold_rescue_cache_admission_checked = false
				_wake_unit(index)
			if _combat_hot_store != null: _return_combat_hot_row()
			continue
		if _unit_rescues.has(index):
			var entry: Dictionary = _unit_rescues[index]
			var patient := int(entry.patient)
			if not combat_can_act(index) or not _rescue_reachable(index, patient) or patient == PLAYER_MEMBER and int(entry.revision) != player_member._received_effective_hit:
				_cancel_unit_rescue(index)
			elif float(unit.age) >= float(CombatTimings.POSE_SECONDS[&"rescue"]):
				if patient == PLAYER_MEMBER:
					player_member.knockout_left = minf(player_member.knockout_left, SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS)
				else:
					combat_hot_set(patient, &"ko", minf(float(combat_hot_get(patient, &"ko")), SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS))
				_cancel_unit_rescue(index)
			if _combat_hot_store != null: _return_combat_hot_row()
			continue
		var decay := maxf(0.0, delta - float(unit.grace))
		unit.grace = maxf(0.0, float(unit.grace) - delta)
		unit.stun = maxf(0.0, float(unit.stun) - decay * SiteCombatRules.STUN_RECOVERY)
		if exchange_enabled:
			_advance_exchange_pose(index)
			unit.think = maxf(0.0, float(unit.think) - delta)
			# Keep existing automatic safe rescue in HOLD without any pose/body
			# sampling. Advancing combat units never run the old enemy scan.
			if float(unit.think) <= 0.0 and is_member(index) and combat_order == CombatOrder.HOLD and str(unit.pose) == "idle" and combat_can_act(index) and not is_controlled_person(index) and not _ship_in_journey(index):
				unit.think = 0.5
				if not is_sustain_routed() and not (person_busy_query.is_valid() and bool(person_busy_query.call(combat_identity(index)))) and (_ship_embarked(index) or enemy_query.is_valid()):
					if not hold_rescue_patient_checked:
						hold_rescue_patient_checked = true
						var query_owner: Object = enemy_query.get_object()
						if _hold_empty_rescue_skip_admitted(query_owner):
							var column_answer: Variant = _hold_rescue_patient_from_columns()
							if column_answer is bool:
								hold_rescue_column_uses += 1
								hold_rescue_patient_absent = not bool(column_answer)
							else:
								hold_rescue_patient_absent = true
								for patient: int in command_members():
									if patient == PLAYER_MEMBER:
										if is_instance_valid(player_member) and not (player_member.knockout_left <= SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS):
											hold_rescue_patient_absent = false
											break
									elif not (float(combat_hot_get(patient, &"ko")) <= SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS):
										hold_rescue_patient_absent = false
										break
					if not hold_rescue_patient_absent and (_ship_embarked(index) or (enemy_query.call(self, index) as Dictionary).is_empty()):
						if not hold_rescue_cache_admission_checked:
							hold_rescue_cache_admitted = _hold_rescue_candidate_cache_admitted()
							hold_rescue_cache_admission_checked = true
						if hold_rescue_cache_admitted and not hold_rescue_candidates_checked:
							hold_rescue_candidates = _hold_rescue_candidates()
							hold_rescue_candidates_checked = true
						var patients: Array[int] = hold_rescue_candidates if hold_rescue_cache_admitted else command_members()
						for patient: int in patients:
							if start_unit_rescue(index, patient):
								break
			if _combat_hot_store != null: _return_combat_hot_row()
			continue # Adjacency/ability decisions happen once in the Lab; no old targeting/aim queries.
		var finished := bool(unit.attack) and float(unit.age) >= CombatTimings.action_duration(attack_clip(index), float(unit.attack_reduction), float(unit.attack_fatigue))
		if str(unit.pose) in ["get_up", "guard_break"]:
			finished = float(unit.age) >= float(CombatTimings.POSE_SECONDS[StringName(str(unit.pose))])
		if str(unit.pose) in ["guard_raise", "guard_lower"] and float(unit.age) >= SiteCombatRules.GUARD_TRANSITION:
			unit.pose = "guard" if str(unit.pose) == "guard_raise" else "idle"
			unit.age = 0.0
		if finished:
			unit.pose = "idle"
			unit.age = 0.0
			unit.attack = false
			unit["previous"] = []
			unit.think = 0.5
			_command_dirty = true
		unit.think = maxf(0.0, float(unit.think) - delta)
		if garrison_feature_id.is_empty() and not bool(unit.attack) and float(unit.think) <= 0.0 and combat_can_act(index) and not is_controlled_person(index) and _ship_attack_allowed(index) and (not is_member(index) or _order_delay <= 0.0) and enemy_query.is_valid():
			unit.think = 0.5 * (1.0 - command_effect("tactics", 0.20)) if is_member(index) else 0.5
			var target: Dictionary = enemy_query.call(self, index)
			if is_member(index) and target.is_empty() and combat_order == CombatOrder.HOLD and str(unit.pose) == "idle" and not is_sustain_routed() and not (person_busy_query.is_valid() and bool(person_busy_query.call(combat_identity(index)))):
				for patient: int in command_members():
					if start_unit_rescue(index, patient):
						break
			if (not is_member(index) or not combat_attacking) and not target.is_empty() and bool(target.get("threat", false)):
				set_unit_guard(index, true)
				if _combat_hot_store != null: _return_combat_hot_row()
				continue
			if str(unit.pose) == "guard":
				set_unit_guard(index, false)
				if _combat_hot_store != null: _return_combat_hot_row()
				continue
			if not target.is_empty() and (is_member(index) and combat_attacking or bool(target.get("threat", false))):
				if start_unit_attack(index, target.cell, int(target.identity), bool(target.get("threat", false))):
					unit["target"] = int(target.identity)
		if _combat_hot_store != null: _return_combat_hot_row()
	# A former crew may wake after it was safely detached without a destination.
	# Derive missing participants from the current plan; retain no old slot copy.
	if vehicle_transport != null and vehicle_transport.has_siege() and _combat_deployment_plan != null:
		_invalidate_active_member_read_scope()
		for member_id: int in _get_active_member_ids():
			if _combat_deployment_plan == null: break
			if not _combat_deployment_plan.member_slot_map.has(member_id) and not _combat_deployment_plan.following_member_ids.has(member_id) and not _combat_absent_slots.has(member_id): siege_crew_released(member_id)
	_visual_prepare_only = true
	_visual_dirty = true
	_visual_prepare_only = false
	_profile_combat_stage("prepare_rows", profile_started)
	if hot_started > 0:
		_combat_hot_inclusive_usec += Time.get_ticks_usec() - hot_started

func sample_combat() -> void:
	if not garrison_feature_id.is_empty(): return
	if exchange_enabled or not combat_enabled or not contact_query.is_valid():
		return
	for index in range(combat_units.size()):
		var unit: Dictionary = combat_units[index]
		if _ship_in_journey(index) or not combat_can_act(index) or not bool(combat_hot_get(index, &"attack")) or bool(unit.blocked):
			continue
		var sample := CombatTimings.sample_time(attack_clip(index), float(combat_hot_get(index, &"age")), float(unit.attack_reduction), float(unit.attack_fatigue))
		var events := CombatTimings.events(attack_clip(index))
		# Outside active time the old current weapon was computed and discarded.
		# Keep the exact history boundary without sampling an unused projection.
		if sample < float(events.active_start) or sample > float(events.active_end):
			unit["previous"] = []
			continue
		var sample_started := Time.get_ticks_usec()
		var current := combat_shapes(index, "weapon")
		combat_geometry_profile.sample_current_weapon_usec += Time.get_ticks_usec() - sample_started
		var previous: Array[PackedVector2Array] = []
		previous.assign(unit.previous)
		var hits: Array[Dictionary] = contact_query.call(previous, current, _combat_attack_cell(index), combat_ground(index), self, index)
		for hit: Dictionary in hits:
			var identity := int(hit.identity)
			if unit.hits.has(identity):
				continue
			unit.hits[identity] = true
			if int(hit.faction) == faction_id:
				unit["blocked"] = true
				unit["status"] = "Ally obstructs melee"
				break
			var profile := SiteCombatRules.attack_profile(attack_clip(index))
			var protection: Vector2
			sample_started = Time.get_ticks_usec()
			if hit.target is TerrainArmy:
				protection = hit.target.contact_protection(int(hit.target_unit), hit, profile)
			else:
				protection = hit.target.contact_protection(hit, profile)
			combat_geometry_profile.sample_protection_usec += Time.get_ticks_usec() - sample_started
			var packet := {"target": hit.target, "target_unit": hit.get("target_unit", -1), "attacker": self, "attacker_unit": index,
				"result": SiteCombatRules.damage(profile, protection.x, protection.y, int(hit.body), bool(hit.shield)),
				"shield": bool(hit.shield), "fraction": float(hit.fraction), "block_kind": hit.block_kind}
			if contact_sink.is_valid():
				contact_sink.call(packet)
			if bool(hit.shield):
				unit["blocked"] = true
				break
		unit["previous"] = current

func apply_unit_contact(index: int, packet: Dictionary) -> void:
	var region_sink: Variant = get_meta(&"region_contact_sink", Callable())
	if region_sink is Callable and region_sink.is_valid() and bool(region_sink.call(combat_identity(index), packet)):
		return
	var unit: Dictionary = combat_units[index]
	var hp := float(combat_hot_get(index, &"hp"))
	if hp <= 0.0:
		return
	var ko := float(combat_hot_get(index, &"ko"))
	# Region deferral and hp admission above remain the original authority.
	var audio_old_hp := hp
	var audio_old_ko := ko
	var audio_source_data: TerrainData = data
	var audio_identity := combat_identity(index)
	var audio_ground := combat_ground(index)
	var audio_sink := audio_down_sink
	var stun := float(combat_hot_get(index, &"stun"))
	var result: Dictionary = packet.result
	var effective_hit := not bool(packet.get("environmental", false)) and (float(result.hp) > 0.0 or float(result.stun) > 0.0)
	if effective_hit:
		unit["hit_revision"] = int(unit.get("hit_revision", 0)) + 1
	if effective_hit or float(result.hp) >= hp:
		if _external_rescuers.has(index):
			(_external_rescuers[index] as TerrainTestCharacter)._cancel_rescue()
		for rescuer: int in _unit_rescues.keys():
			if rescuer == index or int(_unit_rescues[rescuer].patient) == index:
				_cancel_unit_rescue(rescuer)
	hp = maxf(0.0, hp - float(result.hp))
	combat_hot_set(index, &"hp", hp)
	_command_dirty = true
	if float(result.stun) > 0.0:
		stun += float(result.stun)
		combat_hot_set(index, &"stun", stun)
		combat_hot_set(index, &"grace", SiteCombatRules.STUN_GRACE)
		if ko > 0.0:
			ko = SiteCombatRules.KNOCKOUT_GAME_SECONDS
			combat_hot_set(index, &"ko", ko)
	if effective_hit:
		combat_event.emit(10.0)
	if hp <= 0.0 or (ko <= 0.0 and stun >= SiteCombatRules.STUN_LIMIT):
		ko = 0.0 if hp <= 0.0 else SiteCombatRules.KNOCKOUT_GAME_SECONDS
		combat_hot_set(index, &"ko", ko)
		combat_hot_set(index, &"pose", "down")
		combat_hot_set(index, &"age", 0.0)
		combat_hot_set(index, &"attack", false)
		unit["blocked"] = true
		combat_hot_erase(index, &"exchange_visual")
		unit["status"] = "Dead" if hp <= 0.0 else "Unconscious"
		if hp <= 0.0 and not bool(packet.get("environmental", false)) and data != null:
			unit["combat_death_minute"] = int(data.site.get("minute", 0)) # R2: a real battle death (not hunger/fire).
		if hp <= 0.0:
			var shared := PersonFatigue.pool(unit)
			if not shared.is_empty():
				shared.count = maxi(0, int(shared.count) - 1)
				PersonFatigue.unbind(unit)
			var dead_id := combat_identity(index)
			if _combat_move_plan != null:
				_combat_move_plan.remove_member(dead_id)
			if _combat_deployment_plan != null:
				_combat_deployment_plan.remove_member(dead_id, CombatMovementTypes.SlotVacancyReason.MEMBER_DEAD)
			_sync_combat_deployment_leases()
			died.emit(dead_id)
		# A committed step keeps its source/reservation until the legal endpoint.
		if moving_to[index] == INVALID_CELL and _cell_owners.get(cells[index], -1) == index:
			_cell_owners.erase(cells[index])
	elif bool(result.guard_break) and not bool(combat_hot_get(index, &"attack")):
		combat_hot_set(index, &"pose", "guard_break")
		combat_hot_set(index, &"age", 0.0)
		unit["status"] = "Guard broken"
	elif ko <= 0.0:
		unit["status"] = "Shield blocked" if bool(packet.shield) else ("Armor blocked" if float(result.hp) <= 0.0 else "Hurt")
	_mark_visual_row(index)
	if audio_old_hp > 0.0 and audio_old_ko <= 0.0 and (hp <= 0.0 or ko > 0.0) \
			and audio_sink.is_valid():
		audio_sink.call(audio_source_data, audio_identity, audio_ground)

class _CombatSummaryBatch:
	extends RefCounted
	# Call-local original references only. Workers never receive an Army/Actor.
	var requests: Array = []
	var values: Array = []
	var thread_ids: Array[int] = [0, 0, 0, 0]

	func collect() -> Array:
		values.resize(requests.size())
		var group := WorkerThreadPool.add_group_task(_read_chunk, 4, 4, true, "Army summaries")
		if group < 0: return []
		WorkerThreadPool.wait_for_group_task_completion(group)
		for value: Variant in values:
			if not value is Array or value.size() != 7: return []
		return values

	func _read_chunk(chunk: int) -> void:
		thread_ids[chunk] = OS.get_thread_caller_id()
		var first := floori(float(requests.size() * chunk) / 4.0)
		var last := floori(float(requests.size() * (chunk + 1)) / 4.0)
		for index in range(first, last):
			var request: Array = requests[index]
			var store: RefCounted = request[0]
			values[index] = store.read_summary(request[1], request[2], request[3], request[4], request[5], request[6])

func _combat_summary_batch_request() -> Array:
	# Called only after exact-script admission. Check every formatter/identity
	# coercion before calling any original getter; unfamiliar data stays serial.
	if not native_summary_enabled or _combat_hot_borrowed_index >= 0 or is_instance_valid(player_member) \
		or data == null or data.get_script() != TerrainData or data.site.is_typed(): return []
	if _combat_hot_store == null or _combat_hot_store.get_class() != &"ArmyCombatHot" \
		or _combat_hot_store.get_script() != null or not _combat_hot_store.has_method("read_summary") \
		or not combat_hot_active(): return []
	var records: Variant = data.site.get("item_records")
	var definitions: Variant = data.site.get("item_definitions")
	if not records is Dictionary or not definitions is Dictionary: return []
	var roles: Array[int] = [formal_commander, current_commander]
	roles.append_array(officer_order)
	for index: int in roles:
		if index < 0 or index >= combat_units.size(): continue
		var row: Dictionary = combat_units[index]
		if row.is_typed() or typeof(row.get("person_id")) != TYPE_INT: return []
	if command_abilities.is_typed() or team_fatigue.is_typed(): return []
	var captain: Variant = command_abilities.get(formal_commander, _EMPTY_TROOP_DATA)
	if not captain is Dictionary or captain.is_typed(): return []
	for field: String in ["tactics", "leadership", "coach"]:
		if typeof(captain.get(field, 0)) not in [TYPE_INT, TYPE_FLOAT]: return []
	if not team_fatigue.is_empty() and typeof(team_fatigue.get("fatigue")) not in [TYPE_INT, TYPE_FLOAT]: return []
	var request: Array = [_combat_hot_store, combat_units, records, definitions, _troop_exempt_ids(),
		_combat_summary_classifier(), PersonFatigue.THRESHOLD]
	request.make_read_only()
	return request

static func combat_summaries(teams: Array[TerrainArmy]) -> PackedStringArray:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	if teams.size() < 4: return []
	var batch := _CombatSummaryBatch.new()
	var rows := 0
	for team: TerrainArmy in teams:
		if not is_instance_valid(team) or team.get_script() != TerrainArmy: return []
		var request := team._combat_summary_batch_request()
		if request.is_empty(): return []
		batch.requests.append(request)
		rows += team.combat_units.size()
	if rows < 1024: return []
	batch.requests.make_read_only()
	var packets := batch.collect()
	# No fallback or formatting runs until every team admits. The caller keeps
	# its original prefix -> summary order when any team returns the [] barrier.
	if packets.is_empty(): return []
	var texts := PackedStringArray()
	for index in range(teams.size()):
		var team := teams[index]
		if team.combat_hot_diagnostics_enabled:
			team._combat_hot_native_calls += 1
			team._combat_hot_native_rows += team.combat_units.size()
		texts.append(team._format_combat_summary(packets[index], batch.requests[index][4], team.data.site))
	return texts

func combat_summary() -> String:
	var alive := 0
	var knocked := 0
	var dead := 0
	var total_fatigue := 0.0
	var living := 0
	var tired := 0
	var troop_kind := &""
	var exempt_ids := _troop_exempt_ids()
	var troop_site: Dictionary = data.site if data != null else {}
	var original_hot_owner: bool = get_script() == TerrainArmy and _combat_hot_borrowed_index < 0 and combat_hot_active() \
		and _combat_hot_store.get_class() == "ArmyCombatHot" and _combat_hot_store.get_script() == null
	var summary: Array = []
	if native_summary_enabled and original_hot_owner and _combat_hot_store.has_method("read_summary"):
		var records: Variant = troop_site.get("item_records")
		var definitions: Variant = troop_site.get("item_definitions")
		if records is Dictionary and definitions is Dictionary:
			summary = _combat_hot_store.read_summary(combat_units, records, definitions, exempt_ids, _combat_summary_classifier(), PersonFatigue.THRESHOLD)
	if summary.size() == 7:
		if combat_hot_diagnostics_enabled:
			_combat_hot_native_calls += 1
			_combat_hot_native_rows += combat_units.size()
	else:
		var hp_values := PackedFloat64Array()
		var ko_values := PackedFloat64Array()
		var departed_values := PackedFloat64Array()
		var member_values := PackedFloat64Array()
		# Columns are call-local reads of the same owner; a borrowed row outranks them.
		var use_columns: bool = original_hot_owner
		if use_columns:
			hp_values = combat_hot_column(&"hp")
			ko_values = combat_hot_column(&"ko")
			departed_values = combat_hot_column(&"departed")
			member_values = combat_hot_column(&"member")
			use_columns = hp_values.size() == combat_units.size() and ko_values.size() == combat_units.size() \
				and departed_values.size() == combat_units.size() and member_values.size() == combat_units.size()
		for index in range(combat_units.size()):
			var unit: Dictionary = combat_units[index]
			var hp := hp_values[index] if use_columns else float(combat_hot_get(index, &"hp"))
			var departed := departed_values[index] != 0.0 if use_columns else bool(combat_hot_get(index, &"departed"))
			if hp > 0.0 and not departed:
				living += 1
				var fatigue := PersonFatigue.read(unit)
				total_fatigue += fatigue
				tired += int(fatigue > PersonFatigue.THRESHOLD)
			# Read the original hot eligibility and real equipment without a saved-row copy.
			if troop_kind != &"mixed" and hp > 0.0 and not departed and (member_values[index] != 0.0 if use_columns else is_member(index)) and not exempt_ids.has(combat_identity(index)):
				var current := _troop_row_class(unit, troop_site)
				if current != &"": troop_kind = current if troop_kind == &"" or troop_kind == current else &"mixed"
			if hp <= 0.0:
				dead += 1
			elif (ko_values[index] if use_columns else float(combat_hot_get(index, &"ko"))) > 0.0:
				knocked += 1
			else:
				alive += 1
		summary = [alive, knocked, dead, total_fatigue, living, tired, troop_kind]
	return _format_combat_summary(summary, exempt_ids, troop_site)

func _format_combat_summary(summary: Array, exempt_ids: Array, troop_site: Dictionary) -> String:
	var alive := int(summary[0])
	var knocked := int(summary[1])
	var dead := int(summary[2])
	var total_fatigue := float(summary[3])
	var living := int(summary[4])
	var tired := int(summary[5])
	var troop_kind := StringName(summary[6])
	if is_instance_valid(player_member) and player_member.hp > 0.0:
		living += 1
		total_fatigue += player_member.fatigue
		tired += int(player_member.fatigue > PersonFatigue.THRESHOLD)
		if troop_kind != &"mixed" and not exempt_ids.has(player_member.person_id):
			var current := _troop_row_class(_troop_actor(player_member), troop_site)
			if current != &"": troop_kind = current if troop_kind == &"" or troop_kind == current else &"mixed"
	var fatigue_label := "平均疲勞" if team_fatigue.is_empty() else "隊伍共享疲勞"
	var displayed_fatigue := total_fatigue / maxi(1, living) if team_fatigue.is_empty() else float(team_fatigue.fatigue)
	var captain: Dictionary = command_abilities.get(formal_commander, {})
	var troop_name: String = {"melee_infantry": TROOP_TYPE_NAME, "bow": "弓兵", "crossbow": "弩兵", "mixed": "混合兵種（無法保存）"}.get(str(troop_kind), "未持武器")
	return "兵種 %s（基礎武力 %.0f）\n可戰 %d / 昏迷 %d / 死亡 %d\n%s %.1f / 疲憊 %d 人\n正式隊長 %s / 當前指揮 %s\n隊長能力：戰術 %d / 領導 %d / 教練 %d\n%s\n%s" % [troop_name, TROOP_COMBAT_ABILITY, alive, knocked, dead, fatigue_label, displayed_fatigue, tired,
		str(combat_identity(formal_commander)) if formal_commander >= 0 else "空缺", str(combat_identity(current_commander)) if current_commander >= 0 else "空缺",
		int(captain.get("tactics", 0)), int(captain.get("leadership", 0)), int(captain.get("coach", 0)), command_status, command_notice]

func _sync_captain_combat(frame: Dictionary, index: int = 0) -> void:
	if _hide_journey_person(index): return
	var live_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var presenter: Variant = _unit_editor(index)
	if presenter == null or index >= _sprites.size():
		return
	var work := siege_work_state(index)
	if not work.is_empty():
		if _sprites[index] != null and _sprites[index].has_meta("vehicle_rider_frame"): _clear_vehicle_rider_frame(index)
		_clear_siege_work_frame(index)
		if not SiegeWorkClips.sample(presenter, str(work.clip), float(work.time), Vector2i(work.facing)):
			_sprites[index].texture = null
			return
		_sprites[index].texture = presenter.preview_viewport.get_texture()
		_sprites[index].scale = Vector2.ONE * presenter.get_map_sprite_scale()
		_sprites[index].position = combat_visual_ground(index) + combat_offset(index) - _unit_anchor(index)
		presenter.preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	_clear_siege_work_frame(index)
	if _set_vehicle_rider_frame(index):
		if combat_profile_enabled:
			combat_profile_usec["render_live_calls"] = int(combat_profile_usec.get("render_live_calls", 0)) + 1
			_profile_combat_stage("render_live_presenter", live_started)
		return
	if _sprites[index].has_meta("vehicle_rider_frame"):
		_clear_vehicle_rider_frame(index)
		_sprites[index].texture = presenter.preview_viewport.get_texture()
		_sprites[index].scale = Vector2.ONE * presenter.get_map_sprite_scale()
	# Exchange sampling only reads the original row; reuse it for yaw and seek.
	# Historical geometry keeps its original post-readiness sampling order.
	var visual_sample: Array = contact_sample(index) if exchange_enabled else []
	presenter.set_preview_yaw_degrees(_captain_yaw_degrees(Vector2i(visual_sample[2]) if exchange_enabled else facing[index]))
	var readiness_changed: bool = not presenter.combat_ready
	presenter.combat_ready = true
	presenter.visual_state.combat_ready = true
	if readiness_changed:
		# An unchanged idle clip does not refresh equipped/stowed visibility.
		# Use the original model owner on every actual peace -> combat change,
		# including an original female presenter moved to a non-captain row.
		presenter._update_weapon_sheath_state()
		_combat_pose_cache.erase(combat_identity(index))
	var descriptor: Dictionary = _combat_bake.clips[str(frame.clip)]
	var pose := StringName(str(descriptor.get("pose", frame.clip)))
	if presenter.selected_animation != pose:
		# The private timeline is immediately sampled at the contact time below.
		# Avoid a second, intermediate seek from Range clamping during selection.
		var quiet_timeline: bool = exchange_enabled and presenter.get_script() == HumanCharacter3DEditor and not presenter.editor_root.visible and not presenter.is_mounted
		var signals_blocked: bool = presenter.timeline_slider.is_blocking_signals() if quiet_timeline else false
		if quiet_timeline: presenter.timeline_slider.set_block_signals(true)
		presenter.select_animation_by_id(pose)
		if quiet_timeline: presenter.timeline_slider.set_block_signals(signals_blocked)
	# The editor's preview loop preference must not wrap a resolved jump's
	# endpoint to frame zero. Only this presenter's private clip is changed.
	if exchange_enabled and pose == &"attack_jump_heavy":
		var jump: Animation = presenter.animation_player.get_animation(pose)
		if jump != null and jump.loop_mode != Animation.LOOP_NONE:
			jump.loop_mode = Animation.LOOP_NONE
	presenter.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var inputs := _contact_inputs(index) if not _contact_batch_inputs.is_empty() else {}
	var sample: Array = inputs.sample if not inputs.is_empty() else (visual_sample if exchange_enabled else contact_sample(index))
	presenter.animation_player.seek(float(sample[1]), true)
	var origin: Vector2 = inputs.origin if not inputs.is_empty() else combat_ground(index) + combat_offset(index)
	_sprites[index].position = origin - _unit_anchor(index)
	if not exchange_enabled and float(sample[4]) > 0.0:
		_combat_geometry.aim_weapon_attack({"editor": presenter, "player_sprite": _sprites[index]}, origin + sample[3], sample[4])
	if exchange_enabled:
		var editor_started := Time.get_ticks_usec() if combat_profile_enabled else 0
		presenter._process(0.0) # Same authored props/cloth/hair update; editor auto-process is disabled.
		_profile_combat_stage("render_live_editor", editor_started)
	else:
		presenter._update_scabbard_pose()
		presenter._update_combat_cloth()
	_sprites[index].position = origin - _unit_anchor(index)
	presenter.preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if exchange_enabled else SubViewport.UPDATE_ALWAYS
	if combat_profile_enabled:
		combat_profile_usec["render_live_calls"] = int(combat_profile_usec.get("render_live_calls", 0)) + 1
		_profile_combat_stage("render_live_presenter", live_started)

# JSON boundary for the existing fixed-loadout army. Shared atlas/collision data
# stays out of the save; state belongs to rows, never to presentation nodes.
const COMBAT_SAVED_INTS := ["team_id", "faction_id", "combat_order", "formal_commander", "acting_commander", "current_commander", "pursuit_target", "formation_persistent_serial"]
const COMBAT_SAVED_FLOATS := ["training", "command_radius", "pursuit_left", "_command_elapsed", "_order_delay"]
const COMBAT_SAVED_BOOLS := ["combat_attacking", "needs_attack_order", "command_reference_valid"]

func capture_combat_state() -> Dictionary:
	sync_shared_fatigue()
	var snapshot := {"schema": 2, "roster_version": 1, "visual_version": 1, "loadout": "standard_soldier_v2", "units": [], "abilities": [],
		"officers": officer_order.duplicate(), "officer_service": officer_service.duplicate(), "vacancies": [], "rng": str(command_rng.state),
		"reference": [command_reference.x, command_reference.y], "origin": [pursuit_origin.x, pursuit_origin.y],
		"goal": [combat_goal.x, combat_goal.y], "notice": command_notice, "status": command_status}
	snapshot["role"] = role
	snapshot["garrison_feature_id"] = garrison_feature_id
	snapshot["tactical_ai"] = _capture_tactical_ai_state()
	snapshot["cadre_seated"] = true # R1b auto-appointment already applied to this team.
	if not social_cohort.is_empty(): snapshot["social_cohort"] = social_cohort.duplicate(true)
	var saved_offices := _capture_offices()
	if not saved_offices.is_empty(): snapshot["offices"] = saved_offices
	snapshot["formation_preset_id"] = formation_preset_id
	if formation_intent_version > 0:
		snapshot["formation_intent_version"] = formation_intent_version
	if _formation_change_pending:
		snapshot["formation_change_pending"] = true
	snapshot["player_member"] = {"id": player_member.person_id, "present": player_present, "goal": [player_goal.x, player_goal.y]} if is_instance_valid(player_member) else {}
	if not team_fatigue.is_empty():
		snapshot["team_fatigue"] = {"version": 2, "fatigue": team_fatigue.fatigue, "fatigue_rest": team_fatigue.fatigue_rest, "active": team_fatigue.active}
	snapshot["rescues"] = []
	for index: int in _unit_rescues:
		snapshot.rescues.append({"unit": index, "patient": int(_unit_rescues[index].patient), "revision": int(_unit_rescues[index].revision)})
	for field: String in COMBAT_SAVED_INTS + COMBAT_SAVED_FLOATS + COMBAT_SAVED_BOOLS:
		snapshot[field] = get(field)
	snapshot["combat_order_serial"] = _current_order_serial
	if _preserve_structure_order and combat_order != CombatOrder.HOLD: snapshot["structure_waiting"] = true
	if not _retreat_pairs_used.is_empty():
		snapshot["retreat_pairs_used"] = _retreat_pairs_used.keys()
	if not _retreat_resolution.is_empty():
		snapshot["retreat_resolution"] = _retreat_resolution.duplicate(true)
	if not _corps_reposition_source.is_empty():
		snapshot["corps_reposition_source"] = _corps_reposition_source.duplicate()
	for index: int in command_abilities:
		snapshot.abilities.append({"unit": index, "values": command_abilities[index].duplicate()})
	for slot_index: int in _vacancy_assignments:
		snapshot.vacancies.append([slot_index, int(_vacancy_assignments[slot_index])])
	var logical_rows := materialized_combat_rows()
	for index in range(combat_units.size()):
		var unit: Dictionary = PersonFatigue.saved_body(logical_rows[index])
		if logical_rows[index].has("fire_body"): unit["fire_body"] = SiteCombatRules.fire_body_capture(logical_rows[index].fire_body)
		unit.erase("exchange_visual") # Short result visuals are not a second saved action/clock.
		unit["hits"] = logical_rows[index].hits.keys()
		unit["previous"] = []
		for polygon: PackedVector2Array in logical_rows[index].previous:
			var vertices: Array = []
			for point: Vector2 in polygon:
				vertices.append([point.x, point.y])
			unit.previous.append(vertices)
		unit["cell"] = [cells[index].x, cells[index].y]
		unit["slot"] = [combat_slots[index].x, combat_slots[index].y]
		unit["destination"] = [moving_to[index].x, moving_to[index].y]
		unit["facing"] = [facing[index].x, facing[index].y]
		unit["progress"] = float(move_progress[index])
		unit["duration"] = float(move_duration[index])
		unit["move_curve"] = "legacy_smoothstep" if move_curve[index] == 1 else "quad_out"
		if logical_rows[index].has("ship_deck_position"):
			unit["ship_deck_position"] = logical_rows[index].ship_deck_position.duplicate()
		if logical_rows[index].has("ship_guest"):
			unit["ship_guest"] = logical_rows[index].ship_guest
		snapshot.units.append(unit)
	if _combat_deployment_plan != null:
		snapshot["combat_deployment_plan"] = _serialize_deployment_plan(_combat_deployment_plan)
	if _combat_move_plan != null:
		snapshot["combat_move_plan"] = _serialize_move_plan(_combat_move_plan)
	if not _combat_absent_slots.is_empty():
		var absent_slots: Dictionary = {}
		for mid: int in _combat_absent_slots.keys():
			var slot: Vector2i = _combat_absent_slots[mid]
			absent_slots[str(mid)] = [slot.x, slot.y]
		snapshot["combat_absent_slots"] = absent_slots
	if _coordinator != null and _coordinator.has_method("get_inflight_batches_for_formation"):
		snapshot["combat_batches"] = _coordinator.get_inflight_batches_for_formation(self)
	var move_batch_members: Array[int] = []
	var retreat_batch_members: Array[int] = []
	for mid: int in _combat_batch_members:
		if _committed_intent_order(mid) == CombatOrder.RETREAT:
			retreat_batch_members.append(mid)
		else:
			move_batch_members.append(mid)
	if not move_batch_members.is_empty():
		snapshot["combat_batch_move_members"] = move_batch_members
	if not retreat_batch_members.is_empty():
		snapshot["combat_batch_retreat_members"] = retreat_batch_members
	if has_meta(&"crowd_return_handoff"):
		var handoff: Dictionary = get_meta(&"crowd_return_handoff")
		var store: Script = load("res://scripts/terrain_lab/site_store.gd")
		if str(handoff.get("sha256", "")).length() == 64 and str(handoff.sha256) == store._crowd_roster_source_sha256(snapshot):
			snapshot["crowd_state"] = handoff.formation.duplicate(true)
			snapshot["crowd_source_sha256"] = handoff.sha256
	return snapshot

static func _serialize_deployment_plan(plan: CombatDeploymentPlan) -> Dictionary:
	var d := {
		"formation_id": plan.formation_id,
		"order_serial": plan.order_serial,
		"resolved_anchor": [plan.resolved_anchor.x, plan.resolved_anchor.y],
		"terrain_revision": plan.terrain_revision,
		"final_facing": [plan.final_facing.x, plan.final_facing.y],
		"final_width": plan.final_width,
		"final_depth": plan.final_depth,
		"shape_version": plan.shape_version,
		"assignment_epoch": plan.assignment_epoch,
		"structural_platform_capacity": plan.structural_platform_capacity,
		"available_platform_capacity": plan.available_platform_capacity,
		"queue_capacity": plan.queue_capacity,
		"requested_count": plan.requested_count,
		"queue_released": plan.queue_released,
		"promotion_count": plan.promotion_count,
		"platform_slots": [],
		"approach_queue_slots": [],
		"member_role_map": {},
		"member_slot_map": {},
		"queue_member_ids": plan.queue_member_ids.duplicate(),
		"following_member_ids": plan.following_member_ids.duplicate(),
		"pending_platform_member_ids": plan.pending_platform_member_ids.duplicate(),
		"settled_platform_member_ids": plan.settled_platform_member_ids.duplicate(),
		"settled_queue_member_ids": plan.settled_queue_member_ids.duplicate(),
		"admitted_platform_member_ids": plan.admitted_platform_member_ids.duplicate(),
		"ever_admitted_platform_member_ids": plan.ever_admitted_platform_member_ids.keys(),
		"member_slot_locked": {},
		"slot_tactical_roles": {},
		"slot_lease_timers": {},
		"slot_lease_owner_map": {},
		"slot_lease_role_map": {},
		"slot_lease_queue_index_map": {}
	}
	if plan.shape_version >= 2:
		d["formation_preset_id"] = plan.formation_preset_id
	for s in plan.platform_slots:
		d["platform_slots"].append([s.x, s.y])
	for s in plan.approach_queue_slots:
		d["approach_queue_slots"].append([s.x, s.y])
	for mid in plan.member_role_map.keys():
		d["member_role_map"][str(mid)] = int(plan.member_role_map[mid])
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.member_slot_map[mid]
		d["member_slot_map"][str(mid)] = [slot.x, slot.y]
	for mid in plan.member_slot_locked.keys():
		d["member_slot_locked"][str(mid)] = bool(plan.member_slot_locked[mid])
	for slot in plan.slot_tactical_roles.keys():
		d["slot_tactical_roles"]["%d,%d" % [slot.x, slot.y]] = int(plan.slot_tactical_roles[slot])
	for slot in plan.slot_lease_timers.keys():
		d["slot_lease_timers"]["%d,%d" % [slot.x, slot.y]] = float(plan.slot_lease_timers[slot])
	for slot in plan.slot_lease_owner_map.keys():
		d["slot_lease_owner_map"]["%d,%d" % [slot.x, slot.y]] = int(plan.slot_lease_owner_map[slot])
	for slot in plan.slot_lease_role_map.keys():
		d["slot_lease_role_map"]["%d,%d" % [slot.x, slot.y]] = int(plan.slot_lease_role_map[slot])
	for slot in plan.slot_lease_queue_index_map.keys():
		d["slot_lease_queue_index_map"]["%d,%d" % [slot.x, slot.y]] = int(plan.slot_lease_queue_index_map[slot])
	return d

static func _deserialize_deployment_plan(d: Dictionary) -> CombatDeploymentPlan:
	var plan := CombatDeploymentPlan.new()
	plan.formation_id = int(d.get("formation_id", 0))
	plan.order_serial = int(d.get("order_serial", 0))
	var anc: Array = d.get("resolved_anchor", [0, 0])
	plan.resolved_anchor = Vector2i(int(anc[0]), int(anc[1]))
	plan.terrain_revision = int(d.get("terrain_revision", 0))
	var saved_facing: Array = d.get("final_facing", [1, 0])
	plan.final_facing = Vector2i(int(saved_facing[0]), int(saved_facing[1]))
	plan.final_width = int(d.get("final_width", 1))
	plan.final_depth = int(d.get("final_depth", 1))
	plan.shape_version = int(d.get("shape_version", 1))
	plan.formation_preset_id = str(d.get("formation_preset_id", "auto"))
	plan.assignment_epoch = int(d.get("assignment_epoch", 0))
	plan.structural_platform_capacity = int(d.get("structural_platform_capacity", 0))
	plan.available_platform_capacity = int(d.get("available_platform_capacity", 0))
	plan.queue_capacity = int(d.get("queue_capacity", 0))
	plan.requested_count = int(d.get("requested_count", 0))
	plan.queue_released = bool(d.get("queue_released", false))
	plan.promotion_count = int(d.get("promotion_count", 0))
	for arr in d.get("platform_slots", []):
		plan.platform_slots.append(Vector2i(int(arr[0]), int(arr[1])))
	for arr in d.get("approach_queue_slots", []):
		plan.approach_queue_slots.append(Vector2i(int(arr[0]), int(arr[1])))
	var roles: Dictionary = d.get("member_role_map", {})
	for k in roles.keys():
		plan.member_role_map[int(k)] = int(roles[k])
	var slots: Dictionary = d.get("member_slot_map", {})
	for k in slots.keys():
		var arr: Array = slots[k]
		var slot := Vector2i(int(arr[0]), int(arr[1]))
		plan.member_slot_map[int(k)] = slot
		plan.slot_owner_map[slot] = int(k)
	for k in d.get("member_slot_locked", {}).keys():
		plan.member_slot_locked[int(k)] = bool(d["member_slot_locked"][k])
	for key in d.get("slot_tactical_roles", {}).keys():
		var parts: PackedStringArray = str(key).split(",")
		plan.slot_tactical_roles[Vector2i(int(parts[0]), int(parts[1]))] = int(d["slot_tactical_roles"][key])
	for key in d.get("slot_lease_timers", {}).keys():
		var parts: PackedStringArray = str(key).split(",")
		plan.slot_lease_timers[Vector2i(int(parts[0]), int(parts[1]))] = float(d["slot_lease_timers"][key])
	for key in d.get("slot_lease_owner_map", {}).keys():
		var parts: PackedStringArray = str(key).split(",")
		plan.slot_lease_owner_map[Vector2i(int(parts[0]), int(parts[1]))] = int(d["slot_lease_owner_map"][key])
	for key in d.get("slot_lease_role_map", {}).keys():
		var parts: PackedStringArray = str(key).split(",")
		plan.slot_lease_role_map[Vector2i(int(parts[0]), int(parts[1]))] = int(d["slot_lease_role_map"][key])
	for key in d.get("slot_lease_queue_index_map", {}).keys():
		var parts: PackedStringArray = str(key).split(",")
		plan.slot_lease_queue_index_map[Vector2i(int(parts[0]), int(parts[1]))] = int(d["slot_lease_queue_index_map"][key])
	for mid in d.get("queue_member_ids", []):
		plan.queue_member_ids.append(int(mid))
	for mid in d.get("following_member_ids", []):
		plan.following_member_ids.append(int(mid))
	for mid in d.get("pending_platform_member_ids", []):
		plan.pending_platform_member_ids.append(int(mid))
	for mid in d.get("settled_platform_member_ids", []):
		plan.settled_platform_member_ids.append(int(mid))
	for mid in d.get("settled_queue_member_ids", []):
		plan.settled_queue_member_ids.append(int(mid))
	for mid in d.get("admitted_platform_member_ids", []):
		plan.admitted_platform_member_ids.append(int(mid))
	for mid in d.get("ever_admitted_platform_member_ids", d.get("admitted_platform_member_ids", [])):
		plan.ever_admitted_platform_member_ids[int(mid)] = true
	return plan

static func _serialize_move_plan(plan: CombatMovePlan) -> Dictionary:
	var d := {
		"formation_id": plan.formation_id,
		"order_serial": plan.order_serial,
		"requested_goal": [plan.requested_goal.x, plan.requested_goal.y],
		"resolved_anchor": [plan.resolved_anchor.x, plan.resolved_anchor.y],
		"terrain_revision": plan.terrain_revision,
		"roster_revision": plan.roster_revision,
		"structure_blocked": plan.structure_blocked,
		"path_epoch": plan.path_epoch,
		"assignment_epoch": plan.assignment_epoch,
		"macro_cursor": plan.macro_cursor,
		"phase": int(plan.phase),
		"short_translation": plan.short_translation,
		"tactical_overlay": int(plan.tactical_overlay),
		"current_width": plan.current_width,
		"eligible_member_count": plan.eligible_member_count,
		"platform_settled_highwater": plan.platform_settled_highwater,
		"member_recovery_vacated_cell": {},
		"macro_path": []
	}
	for mid in plan.member_recovery_vacated_cell:
		var vacated: Vector2i = plan.member_recovery_vacated_cell[mid]
		d["member_recovery_vacated_cell"][str(mid)] = [vacated.x, vacated.y]
	for pt in plan.macro_path:
		d["macro_path"].append([pt.x, pt.y])
	d["vacancy_chain_state"] = _serialize_vacancy_chain_state(plan)
	return d

static func _serialize_vacancy_chain_state(plan: CombatMovePlan) -> Dictionary:
	var chain := {
		"planning_time_sec": plan.planning_time_sec,
		"last_platform_progress_time_sec": plan.last_platform_progress_time_sec,
		"next_platform_recovery_time_sec": plan.next_platform_recovery_time_sec,
		"active": plan.active_vacancy_chain_actors.duplicate(),
		"queued": [],
		"waiting": plan.vacancy_waiting_id,
		"started_sec": plan.vacancy_chain_started_sec,
		"last_progress_sec": plan.vacancy_chain_last_progress_sec,
		"arrived_count": plan.vacancy_chain_arrived_count,
		"start_cells": {},
		"targets": {},
		"hold": plan.member_recovery_hold.keys(),
		"verified": plan.verified_chain_arrival_members.keys(),
		"verified_pending": plan.verified_chain_arrival_pending
	}
	for step: Dictionary in plan.queued_vacancy_steps:
		var from: Vector2i = step["from"]
		var target: Vector2i = step["to"]
		chain["queued"].append({"actor": int(step["actor"]), "from": [from.x, from.y], "to": [target.x, target.y]})
	for mid: int in plan.member_vacancy_chain_start_cell:
		var start: Vector2i = plan.member_vacancy_chain_start_cell[mid]
		chain["start_cells"][str(mid)] = [start.x, start.y]
	for mid: int in plan.member_vacancy_chain_target:
		var target: Vector2i = plan.member_vacancy_chain_target[mid]
		chain["targets"][str(mid)] = [target.x, target.y]
	return chain

static func _deserialize_move_plan(d: Dictionary, dest_plan: CombatDeploymentPlan) -> CombatMovePlan:
	var plan := CombatMovePlan.new()
	plan.formation_id = int(d.get("formation_id", 0))
	plan.order_serial = int(d.get("order_serial", 0))
	var g: Array = d.get("requested_goal", [0, 0])
	plan.requested_goal = Vector2i(int(g[0]), int(g[1]))
	var a: Array = d.get("resolved_anchor", [0, 0])
	plan.resolved_anchor = Vector2i(int(a[0]), int(a[1]))
	plan.terrain_revision = int(d.get("terrain_revision", 0))
	plan.roster_revision = int(d.get("roster_revision", 0))
	plan.structure_blocked = bool(d.get("structure_blocked", false))
	plan.path_epoch = int(d.get("path_epoch", 0))
	plan.assignment_epoch = int(d.get("assignment_epoch", 0))
	plan.macro_cursor = int(d.get("macro_cursor", 0))
	plan.phase = int(d.get("phase", 0))
	plan.short_translation = bool(d.get("short_translation", false))
	plan.tactical_overlay = int(d.get("tactical_overlay", 0))
	plan.current_width = int(d.get("current_width", 4))
	plan.pending_width = plan.current_width
	plan.eligible_member_count = int(d.get("eligible_member_count", 0))
	plan.platform_settled_highwater = maxi(int(d.get("platform_settled_highwater", 0)), dest_plan.settled_platform_member_ids.size())
	plan.destination_plan = dest_plan
	for key: String in d.get("member_recovery_vacated_cell", {}).keys():
		var vacated: Array = d["member_recovery_vacated_cell"][key]
		plan.member_recovery_vacated_cell[int(key)] = Vector2i(int(vacated[0]), int(vacated[1]))
	for pt in d.get("macro_path", []):
		plan.macro_path.append(Vector2i(int(pt[0]), int(pt[1])))
	var chain: Dictionary = d.get("vacancy_chain_state", {})
	if not chain.is_empty():
		plan.planning_time_sec = float(chain["planning_time_sec"])
		plan.last_platform_progress_time_sec = float(chain["last_platform_progress_time_sec"])
		plan.next_platform_recovery_time_sec = float(chain["next_platform_recovery_time_sec"])
		plan.vacancy_waiting_id = int(chain["waiting"])
		plan.vacancy_chain_started_sec = float(chain["started_sec"])
		plan.vacancy_chain_last_progress_sec = float(chain["last_progress_sec"])
		plan.vacancy_chain_arrived_count = int(chain["arrived_count"])
		plan.verified_chain_arrival_pending = bool(chain["verified_pending"])
		for mid: Variant in chain["active"]:
			plan.active_vacancy_chain_actors.append(int(mid))
		for step: Dictionary in chain["queued"]:
			plan.queued_vacancy_steps.append({"actor": int(step["actor"]), "from": Vector2i(int(step["from"][0]), int(step["from"][1])), "to": Vector2i(int(step["to"][0]), int(step["to"][1]))})
		for key: String in chain["start_cells"]:
			var cell: Array = chain["start_cells"][key]
			plan.member_vacancy_chain_start_cell[int(key)] = Vector2i(int(cell[0]), int(cell[1]))
		for key: String in chain["targets"]:
			var target: Array = chain["targets"][key]
			plan.member_vacancy_chain_target[int(key)] = Vector2i(int(target[0]), int(target[1]))
		for mid: Variant in chain["hold"]:
			plan.member_recovery_hold[int(mid)] = true
		for mid: Variant in chain["verified"]:
			plan.verified_chain_arrival_members[int(mid)] = true
	return plan

static func _combat_saved_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return TerrainTestCharacter._saved_number(value, minimum, maximum) and float(value) == floorf(float(value))

static func _saved_member_index(value: Variant, count: int, includes_player: bool, allow_missing: bool = false) -> bool:
	return _combat_saved_integer(value, -1 if allow_missing else 0, count - 1) or includes_player and _combat_saved_integer(value, PLAYER_MEMBER, PLAYER_MEMBER)

static func _combat_saved_eligible(snapshot: Dictionary, index: int, actor: Dictionary = {}) -> bool:
	if index < 0:
		return false
	if index == PLAYER_MEMBER:
		return not actor.is_empty() and not snapshot.get("player_member", {}).is_empty() and float(actor.hp) > 0.0 and float(actor.knockout_left) <= 0.0 and not bool(actor.captive) and not bool(actor.get("site_exited", false)) and not bool(actor.get("surrender_pending", false)) and not bool(actor.get("_getting_up", false)) and bool(snapshot.player_member.present)
	if index >= snapshot.units.size():
		return false
	var unit: Dictionary = snapshot.units[index]
	return bool(unit.get("member", true)) and float(unit.hp) > 0.0 and float(unit.ko) <= 0.0 and not bool(unit.captive) and not bool(unit.departed) and not bool(unit.get("site_exited", false)) and not bool(unit.get("surrender_pending", false)) and bool(unit.present) and str(unit.pose) != "get_up"

static func _saved_ship_rescue_reachable(rescuer: Dictionary, patient: Dictionary, map: TerrainData) -> bool:
	var vehicle_id := str(rescuer.get("embarked_vehicle_id", ""))
	if vehicle_id.is_empty() or vehicle_id != str(patient.get("embarked_vehicle_id", "")): return false
	var vehicles: Variant = map.site.get("vehicles", {})
	if not vehicles is Dictionary: return false
	var vehicle: Variant = vehicles.get(vehicle_id, {})
	if not vehicle is Dictionary or str(vehicle.get("kind", "")) != "ship": return false
	var kind := str(vehicle.get("ship_type", ""))
	var from := _saved_ship_deck_position(rescuer, kind)
	var to := _saved_ship_deck_position(patient, kind)
	return from.is_finite() and to.is_finite() and from.distance_to(to) <= 1.0 + 0.000001

static func _saved_ship_deck_position(body: Dictionary, kind: String) -> Vector2:
	if not body.has("ship_deck_position"):
		return ShipDefinitions.local_position(kind, int(body.get("berth_id", -1)))
	var saved: Variant = body.ship_deck_position
	if not saved is Array or saved.size() != 2 or not TerrainTestCharacter._saved_vector(saved): return Vector2.INF
	var point := Vector2(float(saved[0]), float(saved[1]))
	return point if ShipDefinitions.deck_contains(kind, point) else Vector2.INF

static func valid_saved_siege_compound(snapshot: Dictionary, map: TerrainData, vehicle: Dictionary) -> bool:
	# A slow row borrows only its original whole-crew transaction, never a free duration.
	if map == null or not _combat_saved_integer(snapshot.get("team_id"), 1, 999999) or not _combat_saved_integer(snapshot.get("formation_persistent_serial"), 0, 100000000): return false
	var definition: Dictionary = SiteRuntime.SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {})
	if definition.is_empty() or float(definition.move_speed) <= 0.0 or not snapshot.get("units") is Array: return false
	if not vehicle.get("id") is String or vehicle.get("phase") != "moving" or not _combat_saved_integer(vehicle.get("team_id"), int(snapshot.get("team_id", -1)), int(snapshot.get("team_id", -1))): return false
	var move: Variant = vehicle.get("move")
	var slots: Variant = vehicle.get("crew_slots")
	if not move is Dictionary or not slots is Dictionary or slots.size() < int(definition.min_crew) or slots.size() > int(definition.standard_crew): return false
	if move.get("mode") != "translate" or move.get("vehicle_id") != vehicle.id or move.get("command") != vehicle.get("command") or move.has("native_token"): return false
	if not _combat_saved_integer(move.get("formation_id"), 1, 2147483647) or not _combat_saved_integer(move.get("formation_serial"), int(snapshot.formation_persistent_serial), int(snapshot.formation_persistent_serial)): return false
	var compound: Variant = move.get("compound_id")
	var prefix: String = "siege:%s:" % str(vehicle.id)
	if not compound is String or not compound.begins_with(prefix): return false
	var tick: String = compound.trim_prefix(prefix)
	if not tick.is_valid_int() or int(tick) < 0 or str(int(tick)) != tick: return false
	if not _combat_saved_integer(move.get("from"), 0, map.size.x * map.size.y - 1) or move.get("from") != vehicle.get("cell") or not _combat_saved_integer(move.get("cell"), 0, map.size.x * map.size.y - 1): return false
	if not TerrainTestCharacter._saved_vector(move.get("facing")) or move.facing != vehicle.get("facing"): return false
	var facing: Vector2 = Vector2(float(move.facing[0]), float(move.facing[1]))
	var shift: Vector2i = map.cell_from_index(int(move.cell)) - map.cell_from_index(int(move.from))
	if facing not in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT] or shift not in TerrainData.DIRECTIONS: return false
	var reverse: float = 0.5 if facing.dot(Vector2(shift)) < 0.0 else 1.0
	var expected: float = 1.0 / (float(definition.move_speed) * SiteCombatRules.siege_crew_multiplier(slots.size(), int(definition.min_crew), int(definition.standard_crew)) * reverse)
	if not TerrainTestCharacter._saved_number(move.get("duration"), 0.000001, 1000000.0) or not is_equal_approx(float(move.duration), expected): return false
	var participants: Variant = move.get("participants")
	if not participants is Array or participants.size() != slots.size(): return false
	var rows: Dictionary = {}
	for row: Variant in snapshot.units:
		if not row is Dictionary or not _combat_saved_integer(row.get("person_id"), 1, 2147483647) or rows.has(int(row.person_id)): return false
		rows[int(row.person_id)] = row
	var seen: Dictionary = {}
	var progress: float = -1.0
	var deployment: Variant = snapshot.get("combat_deployment_plan", {})
	if not deployment is Dictionary or not deployment.get("member_slot_map", {}) is Dictionary or not deployment.get("slot_lease_owner_map", {}) is Dictionary: return false
	if deployment.has("formation_id") and deployment.formation_id != move.formation_id: return false
	var batch: Variant = snapshot.get("combat_batch_move_members", [])
	if not batch is Array: return false
	for member: Variant in participants:
		if not member is Dictionary or not member.get("slot") is String or not _combat_saved_integer(member.get("person_id"), 1, 2147483647): return false
		var identity: int = int(member.person_id)
		if not member.slot.is_valid_int() or str(int(member.slot)) != member.slot or int(member.slot) < 0 or int(member.slot) >= int(definition.standard_crew): return false
		if not _combat_saved_integer(slots.get(member.slot), identity, identity) or seen.has(identity) or not rows.has(identity) or not batch.has(identity): return false
		if deployment.get("member_slot_map", {}).has(str(identity)) or deployment.get("member_slot_map", {}).has(identity) or deployment.get("slot_lease_owner_map", {}).values().has(identity): return false
		if not _combat_saved_integer(member.get("from"), 0, map.size.x * map.size.y - 1) or not _combat_saved_integer(member.get("to"), 0, map.size.x * map.size.y - 1): return false
		var row: Dictionary = rows[identity]
		if not TerrainTestCharacter._saved_cell(row.get("cell"), map) or not TerrainTestCharacter._saved_cell(row.get("destination"), map): return false
		var source: Vector2i = map.cell_from_index(int(member.from))
		var destination: Vector2i = map.cell_from_index(int(member.to))
		if source != SiteRuntime.siege_crew_cell(map, vehicle, member.slot) or destination - source != shift or row.cell != [source.x, source.y] or row.destination != [destination.x, destination.y]: return false
		if row.get("move_curve") != "quad_out" or not TerrainTestCharacter._saved_number(row.get("duration"), 0.000001, 1000000.0) or float(row.duration) != float(move.duration): return false
		if not TerrainTestCharacter._saved_number(row.get("progress"), 0.0, 1.0): return false
		if progress >= 0.0 and float(row.progress) != progress: return false
		progress = float(row.progress)
		seen[identity] = true
	var batches: Variant = snapshot.get("combat_batches", [])
	if not batches is Array: return false
	for group: Variant in batches:
		if not group is Array or group.size() != seen.size(): continue
		var ids: Dictionary = {}
		for value: Variant in group:
			if _combat_saved_integer(value, 1, 2147483647) and seen.has(int(value)): ids[int(value)] = true
		if ids.size() == seen.size(): return true
	return false


static func valid_combat_state(snapshot: Variant, map: TerrainData, actor: Dictionary = {}, state: Dictionary = {}) -> bool:
	if snapshot is Dictionary and (not snapshot.get("garrison_feature_id", "") is String or str(snapshot.get("garrison_feature_id", "")).length() > 64): return false
	if snapshot is Dictionary and snapshot.get("role", "combat") not in ["combat", "logistics", "work"]:
		return false
	if not snapshot is Dictionary or not _combat_saved_integer(snapshot.get("schema"), 1, 2) or snapshot.get("loadout") != "standard_soldier_v2":
		return false
	if snapshot.has("formation_preset_id") and (not snapshot.formation_preset_id is String or not FormationDestinationPlanner.is_valid_preset(snapshot.formation_preset_id)):
		return false
	if snapshot.has("formation_intent_version") and not _combat_saved_integer(snapshot.formation_intent_version, 1, 1):
		return false
	if snapshot.has("formation_change_pending") and (snapshot.get("formation_change_pending") != true or int(snapshot.get("formation_intent_version", 0)) != 1):
		return false
	if snapshot.has("corps_reposition_source"):
		var source: Variant = snapshot.corps_reposition_source
		if not source is Dictionary or source.size() != 4 or not _combat_saved_integer(source.get("version"), 1, 1) \
			or not source.get("corps_id") is String or not _combat_saved_integer(source.get("commander_person_id"), 1, 2147483647) \
			or not _combat_saved_integer(source.get("team_id"), 1, 2147483647) or int(source.team_id) != int(snapshot.get("team_id", -1)) \
			or int(snapshot.get("combat_order", -1)) != CombatOrder.MOVE:
			return false
		var corps: Variant = state.get("corps", {})
		if not corps is Dictionary or not corps.has(source.corps_id) or not corps[source.corps_id] is Dictionary:
			return false
		var relation: Dictionary = corps[source.corps_id]
		var contains_team := false
		if relation.get("team_ids", []) is Array:
			for saved_team: Variant in relation.team_ids:
				if _combat_saved_integer(saved_team, 1, 2147483647) and int(saved_team) == int(source.team_id):
					contains_team = true
		if int(relation.get("commander_person_id", -1)) != int(source.commander_person_id) or not contains_team:
			return false
	if snapshot.has("retreat_resolution"):
		var retreat: Variant = snapshot.retreat_resolution
		if not retreat is Dictionary or int(snapshot.get("combat_order", -1)) != CombatOrder.RETREAT \
			or not _combat_saved_integer(retreat.get("version"), 1, 1) or retreat.get("reason") != "morale_collapse" \
			or not retreat.get("terminal") is bool or not retreat.get("members", {}) is Dictionary:
			return false
		if retreat.get("members", {}).size() > snapshot.get("units", []).size():
			return false
		for key: Variant in retreat.get("members", {}).keys():
			if not str(key).is_valid_int() or not retreat.members[key] is Dictionary:
				return false
			var entry: Dictionary = retreat.members[key]
			if entry.get("kind") not in ["edge", "ally", "building", "surrender", "wait"] or entry.get("status") not in ["moving", "sheltered", "exited", "surrendered", "waiting"]:
				return false
			if entry.kind in ["surrender", "wait"]:
				if entry.status != ("surrendered" if entry.kind == "surrender" else "waiting") or entry.has("target"):
					return false
			elif not entry.get("target") is Array or not TerrainTestCharacter._saved_vector(entry.target) \
				or not _combat_saved_integer(entry.target[0], 0, map.size.x - 1) or not _combat_saved_integer(entry.target[1], 0, map.size.y - 1):
				return false
	if snapshot.has("cadre_seated") and snapshot.cadre_seated != true: return false
	if snapshot.has("social_cohort"):
		var cohort: Variant = snapshot.social_cohort
		if not cohort is Dictionary or cohort.size() != 2 or not cohort.get("base") is Array or cohort.base.size() > MAX_ROSTER_SIZE 			or not (cohort.get("day") is int or cohort.get("day") is float) or float(cohort.day) < 0.0 or float(cohort.day) != floorf(float(cohort.day)): return false
		for identity: Variant in cohort.base:
			if not (identity is int or identity is float) or float(identity) <= 0.0: return false
	if snapshot.has("tactical_ai"):
		var ai: Variant = snapshot.tactical_ai
		if not ai is Dictionary or not _combat_saved_integer(ai.get("version"), 1, 1) \
			or not ai.get("enabled") is bool or not ai.get("recovering") is bool:
			return false
		if not TerrainTestCharacter._saved_number(ai.get("order_cooldown"), 0.0, 60.0) \
			or not TerrainTestCharacter._saved_number(ai.get("chase_cooldown"), 0.0, 60.0):
			return false
		if bool(ai.enabled) and snapshot.get("role", "combat") != "combat":
			return false
	snapshot = normalize_roster_snapshot(snapshot)
	if snapshot.has("visual_version") and not _combat_saved_integer(snapshot.visual_version, 1, 1):
		return false
	if not snapshot.get("units") is Array or snapshot.units.is_empty() or snapshot.units.size() > MAX_ROSTER_SIZE:
		return false
	for body: Variant in snapshot.units:
		if not body is Dictionary or body.get("military_role") not in ["officer", "soldier", "civilian"]: return false
		if body.has("personality") and not TerrainTestCharacter.PersonPersonality.valid(body.personality): return false
		if body.has("technology") and not TerrainTestCharacter.Technology.valid_person(body.technology): return false
		if body.has("social_state") and not TerrainTestCharacter.PersonSocial.valid(body.social_state): return false
		if body.has("fire_body") and not SiteCombatRules.fire_body_saved_valid(body.fire_body): return false
	var saved_count: int = snapshot.units.size()
	if snapshot.has("combat_order_serial") and not _combat_saved_integer(snapshot["combat_order_serial"], 1, 2147483647):
		return false
	for field: String in ["retreat_pairs_used", "combat_batch_move_members", "combat_batch_retreat_members"]:
		if snapshot.has(field) and (not snapshot[field] is Array or snapshot[field].size() > saved_count * saved_count):
			return false
	if not _combat_saved_integer(snapshot.get("roster_version"), 1, 1) or not valid_person_ids(snapshot_person_ids(snapshot), saved_count):
		return false
	var member: Variant = snapshot.get("player_member", {})
	if not member is Dictionary:
		return false
	if not member.is_empty():
		if not TerrainTestCharacter.valid_state(actor, map) or not _combat_saved_integer(member.get("id"), 1, 2147483647) or int(member.id) != int(actor.person_id) or not member.get("present") is bool or not TerrainTestCharacter._saved_cell(member.get("goal"), map):
			return false
		if not _combat_saved_integer(snapshot.get("faction_id"), 0, 100000000) or int(actor.faction_id) != int(snapshot.faction_id) or bool(member.present) and not _combat_saved_eligible(snapshot, PLAYER_MEMBER, actor):
			return false
	for field: String in COMBAT_SAVED_INTS:
		if field in ["formal_commander", "acting_commander", "current_commander"]:
			if not _saved_member_index(snapshot.get(field), saved_count, not member.is_empty(), true):
				return false
		elif not _combat_saved_integer(snapshot.get(field), -1 if field == "pursuit_target" else 0, 5 if field == "combat_order" else (2147483647 if field == "pursuit_target" else 100000000)):
			return false
	if int(snapshot.team_id) < 1 or int(snapshot.team_id) > 999999:
		return false
	for field: String in COMBAT_SAVED_FLOATS:
		if not TerrainTestCharacter._saved_number(snapshot.get(field), 0, 1000000):
			return false
	if float(snapshot.pursuit_left) > 20.0 or float(snapshot.command_radius) < 8.0:
		return false
	for field: String in COMBAT_SAVED_BOOLS:
		if not snapshot.get(field) is bool:
			return false
	for field: String in ["reference", "origin", "goal"]:
		if not TerrainTestCharacter._saved_vector(snapshot.get(field)):
			return false
	if not snapshot.get("rng") is String or not str(snapshot.rng).is_valid_int() or str(str(snapshot.rng).to_int()) != str(snapshot.rng):
		return false # Preserve all 64 RNG bits; never round through a JSON number.
	for field: String in ["notice", "status"]:
		if not snapshot.get(field) is String or str(snapshot[field]).length() > 256:
			return false
	var shared_version := 0
	var excluded_player := -1
	if snapshot.has("team_fatigue"):
		var shared: Variant = snapshot.team_fatigue
		if not shared is Dictionary or not _combat_saved_integer(shared.get("version"), 1, 2) or not shared.get("active") is bool: return false
		shared_version = int(shared.version)
		if shared_version == 1:
			if not _combat_saved_integer(shared.get("excluded_player_id"), 0, 2147483647): return false
			excluded_player = int(shared.excluded_player_id)
		elif shared.has("excluded_player_id"):
			return false # Version 2 has one authority for every living member.
		if not TerrainTestCharacter._saved_number(shared.get("fatigue"), 0.0, 100.0) or not TerrainTestCharacter._saved_number(shared.get("fatigue_rest"), 0.0, 30.0): return false
		if shared_version == 2 and not member.is_empty():
			if actor.has("mount_fatigue") or actor.has("mount_fatigue_rest"): return false
			if float(actor.hp) > 0.0 and (float(actor.get("fatigue", 0.0)) != float(shared.fatigue) or float(actor.get("fatigue_rest", 0.0)) != float(shared.fatigue_rest)):
				return false # The original member Actor borrows this exact same pool.
	var live_presenter_count := 0
	for index in range(saved_count):
		var unit: Variant = snapshot.units[index]
		if not unit is Dictionary or unit.has("_fatigue_pool"):
			return false
		var embarked_vehicle: Variant = unit.get("embarked_vehicle_id", "")
		if not embarked_vehicle is String or str(embarked_vehicle).length() > 128: return false
		if not str(embarked_vehicle).is_empty():
			if not _combat_saved_integer(unit.get("berth_id"), 0, 99) or bool(unit.get("site_exited", false)) or bool(unit.get("surrender_pending", false)) or bool(unit.get("departed", false)): return false
		elif unit.has("berth_id") and not _combat_saved_integer(unit.berth_id, -1, -1):
			return false
		if unit.has("ship_guest") and (not unit.ship_guest is bool or unit.ship_guest != true or str(embarked_vehicle).is_empty()): return false
		if unit.has("ship_deck_position"):
			if str(embarked_vehicle).is_empty(): return false
			var saved_boat: Variant = map.site.get("vehicles", {}).get(str(embarked_vehicle), {})
			if not saved_boat is Dictionary or str(saved_boat.get("kind", "")) != "ship" \
				or not _saved_ship_deck_position(unit, str(saved_boat.get("ship_type", ""))).is_finite(): return false
		if not _combat_saved_integer(unit.get("hit_revision", 0), 0, 2147483647):
			return false
		if not unit.get("work_resting", false) is bool:
			return false
		if str(unit.get("visual_role", "")) not in ["female_live", "male_live", "female_atlas", "male_atlas"]:
			return false
		if (snapshot.has("visual_version") or unit.visual_role == "female_atlas") and not unit.has("appearance"):
			return false # Current/female-atlas rows never used the legacy missing-template format.
		if unit.has("appearance") and (not HumanCharacter3DEditor.valid_appearance(unit.appearance) or str(unit.visual_role).begins_with("female") != (unit.appearance.body == 1)):
			return false
		live_presenter_count += int(unit.visual_role in ["female_live", "male_live"])
		if live_presenter_count > 3:
			return false # A merged roster may retain all three original Site captains.
		var aim: Variant = unit.get("aim", [])
		if not aim is Array or (not aim.is_empty() and not TerrainTestCharacter._saved_vector(aim)):
			return false
		for field: String in ["fatigue", "fatigue_rest", "attack_reduction", "attack_fatigue"]:
			var limit: float = {"fatigue": 100.0, "fatigue_rest": 30.0, "attack_reduction": 0.15, "attack_fatigue": 0.30}[field]
			if not TerrainTestCharacter._saved_number(unit.get(field, 0.0), 0.0, limit):
				return false
		if not TerrainTestCharacter._saved_number(unit.get("combat_ability", 50.0), 0.0, 100.0):
			return false
		for field: String in ["exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "exchange_pose_duration", "ranged_cooldown"]:
			if not TerrainTestCharacter._saved_number(unit.get(field, 0.0), 0.0, 3.0 if field == "ranged_cooldown" else 8.0):
				return false
		if unit.get("exchange_skill", "") not in ["", "brace", "power"]:
			return false
		for field: String in ["hp", "stun", "grace", "ko", "age", "think", "progress", "duration"]:
			if not TerrainTestCharacter._saved_number(unit.get(field), 0, 1000000):
				return false
		# PackedFloat32 durations are allowed within their actual precision.
		var curve: Variant = unit.get("move_curve", "legacy_smoothstep" if unit.get("destination", [-1, -1]) != [-1, -1] else "quad_out")
		if curve not in ["quad_out", "legacy_smoothstep"]:
			return false
		var valid_duration: bool = is_equal_approx(float(unit.duration), MOVE_DURATION) or is_equal_approx(float(unit.duration), RUN_DURATION) or is_equal_approx(float(unit.duration), 0.24) and (not unit.has("move_curve") or curve == "legacy_smoothstep")
		var duration_compound_seen: bool = false
		if state.get("vehicles") is Dictionary:
			for saved_vehicle: Variant in state.vehicles.values():
				if not saved_vehicle is Dictionary or not saved_vehicle.get("move") is Dictionary or saved_vehicle.move.is_empty() or not saved_vehicle.get("crew_slots") is Dictionary or not saved_vehicle.crew_slots.values().has(int(unit.person_id)): continue
				if duration_compound_seen: return false
				duration_compound_seen = true
				valid_duration = curve == "quad_out" and valid_saved_siege_compound(snapshot, map, saved_vehicle)
		if curve == "legacy_smoothstep" and not (is_equal_approx(float(unit.duration), 0.24) or is_equal_approx(float(unit.duration), RUN_DURATION)):
			return false
		if float(unit.hp) > 100.0 or float(unit.ko) > (SiteCombatRules.KNOCKOUT_GAME_SECONDS if int(snapshot.schema) == 2 else SiteCombatRules.LEGACY_KNOCKOUT_ACTION_SECONDS) or float(unit.progress) > 1.0 or not valid_duration:
			return false
		if snapshot.has("team_fatigue") and float(unit.hp) > 0.0 and bool(unit.get("member", true)) and not bool(unit.get("departed", false)):
			if (shared_version == 2 or int(unit.get("person_id", 0)) != excluded_player) and (float(unit.get("fatigue", 0.0)) != float(snapshot.team_fatigue.fatigue) or float(unit.get("fatigue_rest", 0.0)) != float(snapshot.team_fatigue.fatigue_rest)):
				return false # Reject two contradictory saved values for one shared authority.
		for field: String in ["attack", "blocked", "captive", "departed", "present", "member", "logistics"]:
			if not unit.get(field) is bool:
				return false
		for field: String in ["site_exited", "surrender_pending"]:
			if not unit.get(field, false) is bool:
				return false
		if bool(unit.get("surrender_pending", false)) and (bool(unit.captive) or bool(unit.get("site_exited", false))):
			return false
		if not _combat_saved_integer(unit.get("target"), -1, 2147483647) or not unit.get("status") is String or str(unit.status).length() > 256:
			return false
		var saved_attack_pose: bool = str(unit.get("pose", "")) in ["walk_slash", "attack_unarmed"] or unit.has("exchange_pose_duration") and str(unit.get("pose", "")) in ["attack_spear", "attack_axe", "attack_hammer", "attack_dagger", "attack_bow", "attack_crossbow", "attack_jump_heavy"]
		if not saved_attack_pose and str(unit.get("pose", "")) not in ["idle", "walk", "run", "down", "unconscious", "get_up", "guard_break", "guard_raise", "guard", "guard_lower", "rescue"] and not (unit.has("exchange_pose_duration") and str(unit.get("pose", "")) in ["hit", "knockback"]):
			return false
		if bool(unit.attack) != saved_attack_pose or bool(unit.attack) and (float(unit.hp) <= 0.0 or float(unit.ko) > 0.0 or bool(unit.captive) or bool(unit.departed)):
			return false
		if float(unit.hp) <= 0.0 and float(unit.ko) > 0.0 or bool(unit.present) and not _combat_saved_eligible(snapshot, index):
			return false
		if not TerrainTestCharacter._saved_cell(unit.get("cell"), map) or not TerrainTestCharacter._saved_vector(unit.get("slot")) or not TerrainTestCharacter._saved_vector(unit.get("destination")) or not TerrainTestCharacter._saved_vector(unit.get("facing")):
			return false
		if not str(embarked_vehicle).is_empty() and Vector2(float(unit.destination[0]), float(unit.destination[1])) != Vector2(-1, -1): return false
		if not unit.get("ship_death_settled", false) is bool: return false
		if bool(unit.get("ship_death_settled", false)) and (float(unit.hp) > 0.0 or not bool(unit.get("loot_settled", false)) or not str(embarked_vehicle).is_empty()): return false
		if bool(unit.get("site_exited", false)):
			var exit_cell := Vector2i(int(unit.cell[0]), int(unit.cell[1]))
			if exit_cell.x not in [0, map.size.x - 1] and exit_cell.y not in [0, map.size.y - 1]:
				return false
			if Vector2(float(unit.destination[0]), float(unit.destination[1])) != Vector2(-1, -1) or bool(unit.present) or bool(unit.attack):
				return false
		var direction := Vector2(float(unit.facing[0]), float(unit.facing[1]))
		if direction not in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			return false
		if Vector2(float(unit.destination[0]), float(unit.destination[1])) != Vector2(-1, -1) and not TerrainTestCharacter._saved_cell(unit.destination, map):
			return false
		if not unit.get("hits") is Array or unit.hits.size() > 10000 or not unit.get("previous") is Array or unit.previous.size() > 256:
			return false
		var seen := {}
		for identity: Variant in unit.hits:
			if not _combat_saved_integer(identity, 1, 2147483647) or seen.has(int(identity)):
				return false
			seen[int(identity)] = true
		for polygon: Variant in unit.previous:
			if not polygon is Array or polygon.size() > 512:
				return false
			for point: Variant in polygon:
				if not TerrainTestCharacter._saved_vector(point):
					return false
	var rescues: Variant = snapshot.get("rescues", [])
	if not rescues is Array or rescues.size() > saved_count:
		return false
	var rescuers := {}
	var patients := {}
	for entry: Variant in rescues:
		if not entry is Dictionary or not _combat_saved_integer(entry.get("unit"), 0, saved_count - 1) or not _saved_member_index(entry.get("patient"), saved_count, not member.is_empty()) or not _combat_saved_integer(entry.get("revision"), 0, 2147483647):
			return false
		var index := int(entry.unit)
		var patient := int(entry.patient)
		var rescuer: Dictionary = snapshot.units[index]
		if index == patient or rescuers.has(index) or patients.has(patient) or str(rescuer.pose) != "rescue" or float(rescuer.hp) <= 0.0 or float(rescuer.ko) > 0.0 or bool(rescuer.captive) or bool(rescuer.departed) or Vector2(float(rescuer.destination[0]), float(rescuer.destination[1])) != Vector2(-1, -1):
			return false
		var patient_cell: Array = actor.cell if patient == PLAYER_MEMBER else snapshot.units[patient].cell
		var patient_ko := float(actor.knockout_left) if patient == PLAYER_MEMBER else float(snapshot.units[patient].ko)
		var offset := Vector2(float(patient_cell[0]) - float(snapshot.units[index].cell[0]), float(patient_cell[1]) - float(snapshot.units[index].cell[1]))
		var patient_body: Dictionary = actor if patient == PLAYER_MEMBER else snapshot.units[patient]
		var ship_rescue := not str(rescuer.get("embarked_vehicle_id", "")).is_empty() or not str(patient_body.get("embarked_vehicle_id", "")).is_empty()
		var reachable := _saved_ship_rescue_reachable(rescuer, patient_body, map) if ship_rescue else absf(offset.x) + absf(offset.y) == 1.0
		if patient_ko <= 0.0 or not reachable or float(snapshot.units[index].age) > 4.0:
			return false
		if (float(actor.movement_left) > 0.0 if patient == PLAYER_MEMBER else Vector2(float(snapshot.units[patient].destination[0]), float(snapshot.units[patient].destination[1])) != Vector2(-1, -1)):
			return false
		rescuers[index] = true
		patients[patient] = true
	for index in range(saved_count):
		if (str(snapshot.units[index].pose) == "rescue") != rescuers.has(index):
			return false
	if not snapshot.get("abilities") is Array or snapshot.abilities.size() > saved_count or not snapshot.get("officers") is Array or snapshot.officers.size() > saved_count or not snapshot.get("vacancies") is Array or snapshot.vacancies.size() > saved_count:
		return false
	var abilities := {}
	for item: Variant in snapshot.abilities:
		if not item is Dictionary or not _combat_saved_integer(item.get("unit"), 0, saved_count - 1) or abilities.has(int(item.unit)) or not item.get("values") is Dictionary:
			return false
		for kind: String in ["tactics", "leadership", "coach"]:
			if not _combat_saved_integer(item["values"].get(kind), 0, 100):
				return false
		abilities[int(item.unit)] = true
	var officers := {}
	for index: Variant in snapshot.officers:
		if not _saved_member_index(index, saved_count, not member.is_empty()) or officers.has(int(index)) or int(index) == int(snapshot.formal_commander) or int(index) != PLAYER_MEMBER and not bool(snapshot.units[int(index)].member):
			return false
		officers[int(index)] = true
	var service: Variant = snapshot.get("officer_service", snapshot.officers)
	if not service is Array or service.size() < officers.size():
		return false
	var served := {}
	for index: Variant in service:
		# R1b: cadre may include 文官 post holders, so the succession order is a subset.
		if not _saved_member_index(index, saved_count, not member.is_empty()) or served.has(int(index)):
			return false
		served[int(index)] = true
	for index: int in officers:
		if not served.has(index): return false
	var vacancies := {}
	var fillers := {}
	for pair: Variant in snapshot.vacancies:
		if not pair is Array or pair.size() != 2 or not _combat_saved_integer(pair[0], 0, saved_count - 1) or not _combat_saved_integer(pair[1], 0, saved_count - 1) or int(pair[0]) == int(pair[1]) or vacancies.has(int(pair[0])) or fillers.has(int(pair[1])):
			return false
		if not bool(snapshot.units[int(pair[0])].member) or not bool(snapshot.units[int(pair[1])].member):
			return false
		vacancies[int(pair[0])] = true
		fillers[int(pair[1])] = true
	var formal := int(snapshot.formal_commander)
	var acting := int(snapshot.acting_commander)
	var current := int(snapshot.current_commander)
	if not member.is_empty() and not actor.get("command_abilities", {}).is_empty():
		abilities[PLAYER_MEMBER] = true
	if current >= 0 and (not _combat_saved_eligible(snapshot, current, actor) or not abilities.has(current)):
		return false
	for appointed: int in [formal, acting, current] + officers.keys():
		if appointed < 0: continue
		var military: String = str(actor.get("military_role", "officer")) if appointed == PLAYER_MEMBER else str(snapshot.units[appointed].military_role)
		if military != "officer": return false
	var formal_gone: bool = (member.is_empty() or float(actor.hp) <= 0.0) if formal == PLAYER_MEMBER else (formal >= 0 and (not bool(snapshot.units[formal].member) or float(snapshot.units[formal].hp) <= 0.0 or bool(snapshot.units[formal].departed)))
	if formal >= 0 and (formal_gone or not abilities.has(formal)):
		return false
	if acting >= 0 and (formal < 0 or acting == formal or current != acting or _combat_saved_eligible(snapshot, formal, actor)):
		return false
	if acting < 0 and current != (formal if _combat_saved_eligible(snapshot, formal, actor) else -1):
		return false
	if current < 0 and (not bool(snapshot.needs_attack_order) or bool(snapshot.combat_attacking) or int(snapshot.combat_order) not in [CombatOrder.HOLD, CombatOrder.RETREAT]):
		return false
	if bool(snapshot.needs_attack_order) and int(snapshot.combat_order) in [CombatOrder.ATTACK, CombatOrder.PURSUE]:
		return false
	if snapshot.has("retreat_resolution"):
		var retreat_members: Dictionary = snapshot.retreat_resolution.get("members", {})
		var saved_people: Dictionary = {}
		for unit: Dictionary in snapshot.units:
			saved_people[int(unit.person_id)] = unit
		for key: String in retreat_members.keys():
			if not _combat_saved_integer(int(key), 1, 2147483647) or not saved_people.has(int(key)):
				return false
			var entry: Dictionary = retreat_members[key]
			var saved_unit: Dictionary = saved_people[int(key)]
			if (entry.status == "exited") != bool(saved_unit.get("site_exited", false)) \
				or bool(saved_unit.get("surrender_pending", false)) and entry.status != "surrendered":
				return false
			if entry.kind == "edge" and entry.has("target"):
				var exit := Vector2i(int(entry.target[0]), int(entry.target[1]))
				if exit.x > 0 and exit.y > 0 and exit.x < map.size.x - 1 and exit.y < map.size.y - 1:
					return false
			if bool(snapshot.retreat_resolution.terminal) and entry.status == "moving":
				return false
	var exempt_ids: Array = []
	for index: int in [formal] + served.keys():
		if index >= 0:
			exempt_ids.append(int(actor.person_id) if index == PLAYER_MEMBER else int(snapshot.units[index].person_id))
	if str(snapshot.get("garrison_feature_id", "")).is_empty() and single_troop_class(snapshot.units, map, exempt_ids, actor if not member.is_empty() else {}, {}, state) == &"mixed":
		return false
	# Holders who lost their appointment elsewhere (e.g. a Crowd round trip) are
	# vacated on first use, never a load failure: automatic events only vacate.
	if snapshot.has("offices") and not SiteOffices.validate(snapshot.offices, "team", false):
		return false
	return true

func restore_crowd_command_source(snapshot: Dictionary, map: TerrainData, actors: Array[TerrainTestCharacter]) -> void:
	_audio_step_sources.clear()
	# CrowdSite owns simulation after load; this dormant source keeps only the
	# original team's command state and identity-to-row mapping.
	clear()
	data = map
	team_id = int(snapshot.get("team_id", -1))
	faction_id = int(snapshot.get("faction_id", 0))
	role = str(snapshot.get("role", "combat"))
	garrison_feature_id = str(snapshot.get("garrison_feature_id", ""))
	var rows: Array = snapshot.get("units", [])
	combat_units.assign(rows)
	for row: Dictionary in combat_units:
		if row.has("fire_body"): row.fire_body = SiteCombatRules.fire_body_restore(row.fire_body)
	for field: String in COMBAT_SAVED_INTS:
		if snapshot.has(field): set(field, int(snapshot[field]))
	for field: String in COMBAT_SAVED_FLOATS:
		if snapshot.has(field): set(field, float(snapshot[field]))
	for field: String in COMBAT_SAVED_BOOLS:
		if snapshot.has(field): set(field, bool(snapshot[field]))
	_current_order_serial = maxi(1, int(snapshot.get("combat_order_serial", 1)))
	for entry: Dictionary in snapshot.get("abilities", []):
		command_abilities[int(entry.unit)] = entry.values.duplicate(true)
	for entry: Dictionary in snapshot.get("rescues", []):
		_unit_rescues[int(entry.unit)] = {"patient": int(entry.patient), "revision": int(entry.revision)}
	var member: Dictionary = snapshot.get("player_member", {})
	var member_id := int(member.get("id", 0))
	for actor: TerrainTestCharacter in actors:
		if actor.person_id != member_id: continue
		player_member = actor
		player_present = bool(member.get("present", false))
		var goal: Array = member.get("goal", [0, 0])
		player_goal = Vector2i(int(goal[0]), int(goal[1]))
		break
	_invalidate_combat_identity_cache()
	combat_enabled = false
	set_process(false)
	hide()

func restore_combat_state(snapshot: Dictionary, map: TerrainData, restored_player: Variant, restored_npc: Variant) -> void:
	_audio_step_sources.clear()
	# Caller validates all teams and their cross-team claims before replacing Site.
	snapshot = normalize_roster_snapshot(snapshot)
	role = str(snapshot.get("role", "combat"))
	for saved_row: Dictionary in snapshot.units:
		if saved_row.has("fire_body"): saved_row.fire_body = SiteCombatRules.fire_body_restore(saved_row.fire_body)
		saved_row.erase("exchange_visual") # Also clear before the temporary roster is presented by deployment.
	clear()
	garrison_feature_id = str(snapshot.get("garrison_feature_id", ""))
	formation_preset_id = str(snapshot.get("formation_preset_id", "auto"))
	formation_intent_version = int(snapshot.get("formation_intent_version", 0))
	_formation_change_pending = bool(snapshot.get("formation_change_pending", false))
	_formation_retry_seconds = 2.0 if _formation_change_pending else 0.0
	_restore_tactical_ai_state(snapshot.get("tactical_ai", {}))
	# Old saves: one-position-per-duty default, duty AI off, behavior unchanged.
	var legacy_offices := not snapshot.has("offices")
	offices = snapshot.offices.duplicate(true) if not legacy_offices else SiteOffices.default_offices("team", -1, false)
	SiteOffices.normalize_numbers(offices)
	SiteOffices.upgrade(offices)
	_head_established = true # A restored team is never founded again by load.
	data = map
	player = restored_player
	npc = restored_npc
	if not snapshot.get("player_member", {}).is_empty():
		player_member = restored_player if int(snapshot.player_member.id) == restored_player.person_id else restored_npc
		player_present = bool(snapshot.player_member.present)
		player_goal = Vector2i(int(snapshot.player_member.goal[0]), int(snapshot.player_member.goal[1]))
	for field: String in COMBAT_SAVED_INTS:
		set(field, int(snapshot[field]))
	for field: String in COMBAT_SAVED_FLOATS:
		set(field, float(snapshot[field]))
	for field: String in COMBAT_SAVED_BOOLS:
		set(field, bool(snapshot[field]))
	_current_order_serial = maxi(1, int(snapshot.get("combat_order_serial", 1)))
	_preserve_structure_order = bool(snapshot.get("structure_waiting", false))
	_retreat_pair_pending.clear()
	_retreat_pairs_used.clear()
	_retreat_resolution = snapshot.get("retreat_resolution", {}).duplicate(true)
	_corps_reposition_source.clear()
	if snapshot.has("corps_reposition_source"):
		var saved_corps: Dictionary = snapshot.corps_reposition_source
		_corps_reposition_source = {"version": int(saved_corps.version), "corps_id": str(saved_corps.corps_id),
			"commander_person_id": int(saved_corps.commander_person_id), "team_id": int(saved_corps.team_id)}
	_retreat_paths.clear()
	_retreat_path_revision = -1
	var saved_retreat_pairs: Variant = snapshot.get("retreat_pairs_used", [])
	if saved_retreat_pairs is Array and combat_order == CombatOrder.RETREAT:
		for key: Variant in saved_retreat_pairs:
			_retreat_pairs_used[str(key)] = true
	command_rng.state = str(snapshot.rng).to_int()
	command_reference = Vector2(float(snapshot.reference[0]), float(snapshot.reference[1]))
	pursuit_origin = Vector2(float(snapshot.origin[0]), float(snapshot.origin[1]))
	combat_goal = Vector2i(int(snapshot.goal[0]), int(snapshot.goal[1]))
	command_notice = str(snapshot.notice)
	for item: Dictionary in snapshot.abilities:
		# JSON numbers are floats. These fields were validated as exact 0..100
		# integers; restore their runtime type without rerolling or truncating input.
		var values := {}
		for kind: String in ["tactics", "leadership", "coach"]:
			values[kind] = int(item["values"][kind])
		command_abilities[int(item.unit)] = values
	for index: Variant in snapshot.officers:
		officer_order.append(int(index))
	for index: Variant in snapshot.get("officer_service", snapshot.officers):
		officer_service.append(int(index))
	for pair: Array in snapshot.vacancies:
		_vacancy_assignments[int(pair[0])] = int(pair[1])
	for entry: Dictionary in snapshot.get("rescues", []):
		_unit_rescues[int(entry.unit)] = {"patient": int(entry.patient), "revision": int(entry.revision)}
		if int(entry.patient) == PLAYER_MEMBER and is_instance_valid(player_member):
			player_member._army_rescuer = self
	var selected: Array[Vector2i] = []
	for unit: Dictionary in snapshot.units:
		selected.append(Vector2i(int(unit.cell[0]), int(unit.cell[1])))
	combat_units.assign(snapshot.units)
	_invalidate_combat_identity_cache()
	_last_holders.clear()
	for seat: Dictionary in offices.get("positions", []):
		if not bool(seat.head) and int(seat.holder) > 0: _last_holders[int(seat.holder)] = str(seat.get("office_class", "military"))
	# Rows exist now (roles, identities). Saves made before R1b get their officers
	# auto-appointed once (user decision 2026-10-07); later saves carry the marker.
	social_cohort = {}
	if snapshot.get("social_cohort") is Dictionary:
		social_cohort = {"day": int(snapshot.social_cohort.day), "base": []}
		for identity: Variant in snapshot.social_cohort.base: social_cohort.base.append(int(identity))
	if not bool(snapshot.get("cadre_seated", false)):
		var officers_now: Array[int] = []
		for index: int in officer_order + officer_service:
			if not officers_now.has(index): officers_now.append(index)
		_auto_seat_officers(officers_now, true)
	_mark_serving_dirty()
	_deploy_selected(selected)
	combat_units.clear()
	_cell_owners.clear()
	for index in range(roster_size):
		var saved: Dictionary = snapshot.units[index]
		var unit: Dictionary = saved.duplicate(true)
		unit.erase("exchange_visual") # Ignore any transient presentation payload on restore.
		unit["fatigue"] = float(saved.get("fatigue", 0.0))
		unit["fatigue_rest"] = float(saved.get("fatigue_rest", 0.0))
		# Restore never invents a row field the saved body did not carry.
		if saved.has("work_resting"): unit["work_resting"] = bool(saved.work_resting)
		unit["attack_reduction"] = float(saved.get("attack_reduction", SiteCombatRules.diminishing(training if bool(saved.get("member", true)) else 0.0, 0.15)))
		unit["attack_fatigue"] = float(saved.get("attack_fatigue", 0.0))
		unit["hits"] = {}
		for identity: Variant in saved.hits:
			unit.hits[int(identity)] = true
		unit["previous"] = []
		for polygon: Array in saved.previous:
			var shape := PackedVector2Array()
			for point: Array in polygon:
				shape.append(Vector2(float(point[0]), float(point[1])))
			unit.previous.append(shape)
		# Packed per-row state (move_curve included) lives outside the row dictionary.
		for field: String in ["cell", "slot", "destination", "facing", "progress", "duration", "move_curve"]:
			unit.erase(field)
		combat_units.append(unit)
		combat_slots.append(Vector2i(int(saved.slot[0]), int(saved.slot[1])))
		moving_to[index] = Vector2i(int(saved.destination[0]), int(saved.destination[1]))
		facing[index] = Vector2i(int(saved.facing[0]), int(saved.facing[1]))
		move_progress[index] = float(saved.progress)
		move_duration[index] = float(saved.duration)
		move_curve[index] = int(str(saved.get("move_curve", "legacy_smoothstep" if moving_to[index] != INVALID_CELL else "quad_out")) == "legacy_smoothstep")
		if moving_to[index] == INVALID_CELL:
			move_duration[index] = MOVE_DURATION
			move_curve[index] = 0
		if _ship_embarked(index):
			combat_slots[index] = INVALID_CELL
		elif moving_to[index] != INVALID_CELL:
			_reserved_cells[moving_to[index]] = index
			_cell_owners[cells[index]] = index
			movement_state[index] = UnitState.MOVING
			locomotion_mode[index] = Locomotion.WALK
		elif float(unit.hp) > 0.0 and float(unit.ko) <= 0.0 and not bool(unit.departed) and not bool(unit.get("site_exited", false)):
			_cell_owners[cells[index]] = index
	combat_enabled = true
	var saved_shared: Dictionary = snapshot.get("team_fatigue", {})
	var migrate_shared := shared_fatigue_enabled and exchange_enabled and int(saved_shared.get("version", 0)) < 2
	var migrated_fatigue := float(saved_shared.get("fatigue", 0.0))
	var migrated_rest := float(saved_shared.get("fatigue_rest", PersonFatigue.REST_DELAY))
	if migrate_shared:
		# Read the old values BEFORE normal membership binding averages them.
		# Version 1 excluded its player; older saves had individual values only.
		# A one-time conservative merge must not refresh that player's fatigue.
		for index in range(combat_units.size()):
			if not is_member(index) or member_gone(index): continue
			migrated_fatigue = maxf(migrated_fatigue, PersonFatigue.read(combat_units[index]))
			migrated_rest = minf(migrated_rest, PersonFatigue.read(combat_units[index], "fatigue_rest"))
		if is_instance_valid(player_member) and player_member.hp > 0.0:
			# Actor.restore_state has already conservatively merged legacy horse data.
			migrated_fatigue = maxf(migrated_fatigue, player_member.fatigue)
			migrated_rest = minf(migrated_rest, player_member.fatigue_rest)
	sync_shared_fatigue(true)
	if not team_fatigue.is_empty():
		if migrate_shared:
			team_fatigue.fatigue = migrated_fatigue
			team_fatigue.fatigue_rest = migrated_rest
		elif not saved_shared.is_empty():
			# Version 2 was checked against every living member, including the
			# controlled body. Restore it exactly, independent of current control.
			team_fatigue.fatigue = float(saved_shared.fatigue)
			team_fatigue.fatigue_rest = float(saved_shared.fatigue_rest)
		if not saved_shared.is_empty(): team_fatigue.active = bool(saved_shared.active)
	command_status = str(snapshot.status)
	_presence_geometry_cache = []
	_command_dirty = false # No re-election or RNG draws on restore.
	_visual_dirty = true
	if snapshot.has("combat_deployment_plan"):
		_combat_deployment_plan = _deserialize_deployment_plan(snapshot["combat_deployment_plan"])
	if snapshot.has("combat_move_plan"):
		_combat_move_plan = _deserialize_move_plan(snapshot["combat_move_plan"], _combat_deployment_plan)
		_current_order_serial = maxi(_current_order_serial, _combat_move_plan.order_serial)
		_formation_movement_profile = FormationMovementProfile.from_members(_get_active_member_ids(), self)
		if _combat_deployment_plan != null:
			var saved_deployment: Dictionary = snapshot.get("combat_deployment_plan", {})
			if not saved_deployment.has("shape_version") or not saved_deployment.has("final_facing"):
				var inferred_facing := Vector2i.RIGHT
				for path_index in range(_combat_move_plan.macro_path.size() - 1, 0, -1):
					var step: Vector2i = _combat_move_plan.macro_path[path_index] - _combat_move_plan.macro_path[path_index - 1]
					if step != Vector2i.ZERO:
						inferred_facing = step
						break
				_combat_deployment_plan.final_facing = inferred_facing
			var deployment_anchor: Vector2i = _combat_deployment_plan.resolved_anchor
			if not data.contains(deployment_anchor) or not data.is_walkable(deployment_anchor):
				var move_anchor: Vector2i = _combat_move_plan.resolved_anchor
				if data.contains(move_anchor) and data.is_walkable(move_anchor):
					_combat_deployment_plan.resolved_anchor = move_anchor
		if _combat_move_plan.structure_blocked:
			_combat_move_plan.terrain_revision = -1 # First live query derives the current route, preserving the saved goal.
		elif not FormationDestinationPlanner.refresh_derived_ingress(_combat_deployment_plan, data, _combat_move_plan.macro_path, _formation_movement_profile):
			combat_order = CombatOrder.HOLD
			command_status = "讀檔後部署地形已失效；就地防禦，等待新令"
			_combat_move_plan = null
	_combat_absent_slots.clear()
	if _combat_move_plan != null and combat_order == CombatOrder.MOVE:
		var saved_absent: Dictionary = snapshot.get("combat_absent_slots", {})
		for key in saved_absent.keys():
			var slot: Array = saved_absent[key]
			_combat_absent_slots[int(key)] = Vector2i(int(slot[0]), int(slot[1]))
	if _coordinator != null and "deployment_registry" in _coordinator and _combat_deployment_plan != null:
		var reg: Object = _coordinator.deployment_registry
		if reg != null:
			var all_slots: Array[Vector2i] = []
			for slot: Vector2i in _combat_deployment_plan.member_slot_map.values():
				if not all_slots.has(slot):
					all_slots.append(slot)
			for slot: Vector2i in _combat_deployment_plan.slot_lease_timers.keys():
				if not all_slots.has(slot):
					all_slots.append(slot)
			reg.try_replace_reservations(team_id, 0, _combat_deployment_plan.order_serial, all_slots)
	formation_persistent_serial = int(snapshot.get("formation_persistent_serial", 0))
	formation_runtime_id = 0
	_combat_batch_members.clear()
	var saved_retreat_batch_members: Array = snapshot.get("combat_batch_retreat_members", [])
	var retreat_batch_lookup: Dictionary = {}
	for saved_mid in saved_retreat_batch_members:
		retreat_batch_lookup[int(saved_mid)] = true
	for mids: Array in snapshot.get("combat_batches", []):
		for mid: int in mids:
			_combat_batch_members[mid] = CombatOrder.RETREAT if retreat_batch_lookup.has(mid) else CombatOrder.MOVE
			if _combat_move_plan != null:
				var index := index_for_identity(mid)
				_combat_move_plan.member_pending_proposal_id[mid] = 0
				_combat_move_plan.member_pending_from_cell[mid] = cells[index]
				_combat_move_plan.member_pending_to_cell[mid] = moving_to[index]
	# Starting-order tags are serialized independently from completion batches.
	# Preserve their saved sequence without creating members absent from a batch.
	var ordered_batch_members: Dictionary = {}
	for field: String in ["combat_batch_move_members", "combat_batch_retreat_members"]:
		for saved_mid: Variant in snapshot.get(field, []):
			var mid := int(saved_mid)
			if _combat_batch_members.has(mid):
				ordered_batch_members[mid] = _combat_batch_members[mid]
	# Older snapshots may omit tags; retain the existing batch-derived fallback.
	for mid: int in _combat_batch_members:
		ordered_batch_members[mid] = _combat_batch_members[mid]
	_combat_batch_members = ordered_batch_members
	if _coordinator != null and _coordinator.has_method("register_formation"):
		_coordinator.register_formation(self)
		if _coordinator.has_method("restore_inflight_batches_for_formation"):
			_coordinator.restore_inflight_batches_for_formation(self, snapshot.get("combat_batches", []))
	if native_hot_enabled: _try_install_combat_hot_store()
	# _deploy_selected built presentation before combat_enabled and the restored
	# rows were installed. Recreate only the visual instances for the final state.
	if DisplayServer.get_name() != "headless":
		_refresh_deferred_captain()
		_rebuild_visual_instances()
	if snapshot.has("crowd_source_sha256"):
		set_meta(&"crowd_return_handoff", {"sha256": snapshot.crowd_source_sha256, "formation": snapshot.crowd_state.duplicate(true)})

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
var move_progress := PackedFloat64Array()
var move_duration := PackedFloat64Array()
var move_curve := PackedByteArray() # 0: shared quad-out, 1: finish one legacy step unchanged.
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
var _follower_combat_route_stamps: Dictionary = {} # Rebuildable context, never saved.
var _follower_failed_combat_routes: Dictionary = {} # Exhausted canonical searches only; never saved.
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
var _visual_dirty_value := true
var _visual_full_dirty := true
var _visual_prepare_only := false
var _visual_row_dirty: Dictionary = {}
var _visual_dirty: bool:
	get: return _visual_dirty_value
	set(value):
		_visual_dirty_value = value
		if value and not _visual_prepare_only:
			_visual_full_dirty = true

var _visual_warmup_frames := 0
var _soldier_anchor := Vector2.ZERO
var _captain_anchor := Vector2.ZERO
var _captain_last_clip := StringName()
var _captain_last_facing := Vector2i(999999, 999999)
var _soldier_editor: Variant
var _captain_editor: Variant
var _live_presenters: Dictionary = {} # Stable person ID -> original female presenter, never a new person.
var _live_anchors: Dictionary = {}
var _sprites: Array[Sprite2D] = []
var defer_captain_presenter := false # TerrainLab's dynamic team slots only; visual role stays live.
var _captain_presenter_selected := false
var _deferred_captain_ready := false
var batch_render_enabled := true # Sprite reference path remains available for A/B and small rosters.
var native_render_enabled := true # Presentation-only A/B/fallback; no simulation changes.
var _batch_view: Variant

func _batch_render_active() -> bool:
	return batch_render_enabled and exchange_enabled and combat_enabled and roster_size >= 64

func _mark_visual_row(index: int) -> void:
	_visual_row_dirty[index] = true
	var before := _visual_prepare_only
	_visual_prepare_only = true
	_visual_dirty = true
	_visual_prepare_only = before

func _new_person_sprite(index: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "ArmyCaptain" if index == 0 else "ArmySoldier_%03d" % index
	sprite.texture_filter = CharacterRenderContract.TEXTURE_FILTER
	sprite.z_as_relative = false
	add_child(sprite)
	return sprite

var _soldier_atlas: Texture2D
static var _static_soldier_atlas: Texture2D = null
static var _static_soldier_frame_textures: Dictionary = {}
static var _static_soldier_frame_anchors: Dictionary = {}
static var _static_soldier_clip_counts: Dictionary = {}
static var _static_soldier_clip_durations: Dictionary = {}
static var _static_soldier_map_scale: float = 1.0
static var _static_soldier_baked_ready: bool = false
var visual_pool_ready := false
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
var combat_render_usec := 0 # Cumulative measured presentation work; no simulation state.
var combat_profile_enabled := false
var combat_profile_usec: Dictionary = {}
var input_seconds := 0.0
var simulated_seconds := 0.0
var dropped_seconds := 0.0
var max_passage_expansions := 0

func _profile_combat_stage(stage: String, started: int) -> int:
	if not combat_profile_enabled: return 0
	var now := Time.get_ticks_usec()
	combat_profile_usec[stage] = int(combat_profile_usec.get(stage, 0)) + now - started
	return now

func _uses_live_presenter(index: int) -> bool:
	return str(combat_units[index].get("visual_role", "male_atlas")) in ["female_live", "male_live"] if index < combat_units.size() else index == 0

func _uses_live_contact_presenter(index: int) -> bool:
	# Headless foot queries use the already prepared original same-body rig.
	# Preserve GPU live geometry and the original mounted live domain.
	if not _uses_live_presenter(index): return false
	if DisplayServer.get_name() != "headless": return true
	var appearance: Dictionary = equipment_appearance(index)
	if appearance.is_empty(): appearance = combat_units[index].get("appearance", {})
	return bool(appearance.get("mounted", false))

func _renders_live_presenter(index: int) -> bool:
	return _uses_live_presenter(index) and not (defer_captain_presenter and not combat_enabled) and not (index == 0 and _deferred_captain_ready)

func _uses_pooled_captain_geometry(index: int) -> bool:
	return index == 0 and _deferred_captain_ready and DisplayServer.get_name() != "headless"

func _refresh_deferred_captain() -> void:
	_deferred_captain_ready = false
	if not defer_captain_presenter or _captain_presenter_selected or not combat_enabled or combat_units.is_empty() or not _uses_live_presenter(0) or DisplayServer.get_name() == "headless":
		return
	if not _soldier_baked_ready:
		_soldier_baked_ready = _load_baked_soldier()
		if _soldier_baked_ready: _soldier_visual_mode = "baked_atlas"
	if not _soldier_baked_ready:
		return
	var appearance: Dictionary = equipment_appearance(0)
	if appearance.is_empty(): appearance = combat_units[0].get("appearance", {})
	_deferred_captain_ready = not appearance.is_empty() and not bool(appearance.get("mounted", false)) and supports_equipment_recipe(appearance)

func _promote_deferred_captain() -> void:
	if not _deferred_captain_ready: return
	_deferred_captain_ready = false
	_ensure_live_presenters()
	if _sprites.is_empty(): return
	if _sprites[0] == null: _sprites[0] = _new_person_sprite(0)
	var editor: Variant = _unit_editor(0)
	if editor == null:
		push_error("TerrainArmy: captain atlas fallback could not create the original presenter")
		return
	_sprites[0].texture = editor.preview_viewport.get_texture()
	var sprite_scale: float = editor.get_map_sprite_scale()
	_sprites[0].scale = Vector2.ONE * sprite_scale
	_captain_anchor = editor.get_map_ground_offset_pixels() * sprite_scale
	_live_anchors[combat_identity(0)] = _captain_anchor
	_visual_dirty = true
	_combat_pose_cache.erase(combat_identity(0))

func _captain_geometry_entry(index: int) -> Dictionary:
	_retain_contact_sources_until_exit()
	var appearance: Dictionary = equipment_appearance(index)
	if appearance.is_empty(): appearance = combat_units[index].get("appearance", {})
	var body := int(appearance.get("body", 0))
	var entry: Dictionary = _captain_geometry_pool.get(body, {})
	if not entry.is_empty() and is_instance_valid(entry.get("editor")) and is_instance_valid(entry.get("sprite")):
		return entry
	if not entry.is_empty() and is_instance_valid(entry.get("sprite")): entry.sprite.queue_free()
	var editor: SharedVisualSource = _create_visual_source(body, "ArmyCaptainGeometryBody%d" % body)
	editor.preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var sprite := Sprite2D.new()
	sprite.visible = false
	get_tree().root.add_child(sprite)
	entry = {"editor": editor, "sprite": sprite, "geometry": CombatGeometry.new()}
	_captain_geometry_pool[body] = entry
	return entry

func _sync_pooled_captain(index: int, entry: Dictionary, inputs: Dictionary = {}) -> bool:
	var editor: SharedVisualSource = entry.editor
	var appearance: Dictionary = inputs.appearance if not inputs.is_empty() else equipment_appearance(index)
	if appearance.is_empty(): appearance = combat_units[index].get("appearance", {})
	var captured: Dictionary = editor.capture_appearance()
	if appearance.get("body") is float: captured["body"] = float(captured.body)
	if captured != appearance and not editor.restore_appearance(appearance):
		push_error("TerrainArmy: cannot restore exact pooled captain appearance")
		return false
	var sample: Array = inputs.sample if not inputs.is_empty() else contact_sample(index)
	if SiegeWorkClips.DURATIONS.has(str(sample[0])):
		if not SiegeWorkClips.sample(editor, str(sample[0]), float(sample[1]), Vector2i(sample[2])): return false
		var origin_point: Vector2 = inputs.origin if not inputs.is_empty() else combat_ground(index) + combat_offset(index)
		var map_sprite_scale: float = editor.get_map_sprite_scale()
		var anchor_offset: Vector2 = editor.get_map_ground_offset_pixels() * map_sprite_scale
		var entry_sprite: Sprite2D = entry.sprite
		entry_sprite.global_transform = global_transform * Transform2D(Vector2(map_sprite_scale, 0.0), Vector2(0.0, map_sprite_scale), origin_point - anchor_offset)
		editor.preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return true
	editor.set_preview_yaw_degrees(_captain_yaw_degrees(Vector2i(sample[2])))
	if not editor.combat_ready:
		editor.combat_ready = true
		editor.visual_state.combat_ready = true
		editor._update_weapon_sheath_state()
	var frame := combat_frame(index)
	var descriptor: Dictionary = _combat_bake.clips[str(frame.clip)]
	var pose := StringName(str(descriptor.get("pose", frame.clip)))
	if editor.selected_animation != pose: editor.select_animation_by_id(pose)
	if pose == &"attack_jump_heavy":
		var jump: Animation = editor.animation_player.get_animation(pose)
		if jump != null: jump.loop_mode = Animation.LOOP_NONE
	editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	editor.animation_player.seek(float(sample[1]), true)
	var origin: Vector2 = inputs.origin if not inputs.is_empty() else combat_ground(index) + combat_offset(index)
	var sprite_scale: float = editor.get_map_sprite_scale()
	var anchor: Vector2 = editor.get_map_ground_offset_pixels() * sprite_scale
	var sprite: Sprite2D = entry.sprite
	sprite.global_transform = global_transform * Transform2D(Vector2(sprite_scale, 0.0), Vector2(0.0, sprite_scale), origin - anchor)
	if exchange_enabled:
		editor._process(0.0)
	else:
		if float(sample[4]) > 0.0:
			entry.geometry.aim_weapon_attack({"editor": editor, "player_sprite": sprite}, origin + sample[3], sample[4])
		editor._update_scabbard_pose()
		editor._update_combat_cloth()
	editor.preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return true

func refresh_captain_presentation() -> void:
	if not defer_captain_presenter or DisplayServer.get_name() == "headless": return
	var before := _deferred_captain_ready
	_refresh_deferred_captain()
	if before == _deferred_captain_ready: return
	_ensure_live_presenters()
	if not combat_units.is_empty() and _sprites.size() == roster_size:
		_rebuild_visual_instances()
	_combat_pose_cache.clear()
	_visual_dirty = true

func set_captain_presenter_selected(selected: bool) -> void:
	if not defer_captain_presenter or _captain_presenter_selected == selected: return
	_captain_presenter_selected = selected
	refresh_captain_presentation()

func _unit_editor(index: int) -> Variant:
	if not _renders_live_presenter(index):
		return null
	return _live_presenters.get(combat_identity(index), _captain_editor if index == 0 else null)

func _unit_anchor(index: int) -> Vector2:
	return _live_anchors.get(combat_identity(index), _captain_anchor) if _renders_live_presenter(index) else (_soldier_sprite_anchors[index] if _soldier_baked_ready else _soldier_anchor)

func _all_visual_sources() -> Array:
	var sources: Array = []
	for editor: Variant in [_soldier_editor, _captain_editor] + _live_presenters.values():
		if is_instance_valid(editor) and not sources.has(editor):
			sources.append(editor)
	return sources

func _ensure_live_presenters() -> void:
	if DisplayServer.get_name() == "headless" or combat_units.is_empty():
		return
	var current_people := {}
	for index in range(combat_units.size()):
		if _renders_live_presenter(index):
			current_people[combat_identity(index)] = true
	for identity: int in _live_presenters.keys():
		if current_people.has(identity):
			continue
		var old_editor: Variant = _live_presenters[identity]
		_live_presenters.erase(identity)
		_live_anchors.erase(identity)
		if old_editor != _captain_editor or defer_captain_presenter:
			old_editor.preview_viewport.queue_free()
			old_editor.queue_free()
			if old_editor == _captain_editor: _captain_editor = null
	for index in range(combat_units.size()):
		if not _renders_live_presenter(index):
			continue
		var appearance: Dictionary = equipment_appearance(index)
		if appearance.is_empty(): appearance = combat_units[index].get("appearance", {})
		var body := int(appearance.get("body", 0 if combat_units[index].visual_role == "male_live" else 1))
		var editor: Variant = _live_presenters.get(combat_identity(index))
		if editor == null:
			editor = _captain_editor if _captain_editor != null and not _live_presenters.values().has(_captain_editor) else _create_visual_source(body, "ArmyPerson_%d" % combat_identity(index))
		if not appearance.is_empty() and editor.capture_appearance() != appearance:
			var appearance_restored: bool = bool(editor.restore_appearance(appearance))
			assert(appearance_restored)
		_live_presenters[combat_identity(index)] = editor
		_visual_sources_owned = true

func _transfer_presenters(recipient: TerrainArmy, identities: Array[int]) -> void:
	_ensure_live_presenters()
	for identity: int in identities:
		if not _live_presenters.has(identity):
			continue
		var editor: Variant = _live_presenters[identity]
		_live_presenters.erase(identity)
		_live_anchors.erase(identity)
		if editor == _captain_editor:
			_captain_editor = null
		if editor.get_parent() != recipient:
			editor.reparent(recipient)
		if editor.preview_viewport.get_parent() != recipient:
			editor.preview_viewport.reparent(recipient)
		editor.preview_host = recipient
		recipient._live_presenters[identity] = editor
		recipient._visual_sources_owned = true

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
	if _captain_editor == null and _live_presenters.is_empty() and (not defer_captain_presenter and combat_units.is_empty() or not combat_units.is_empty() and _renders_live_presenter(0)):
		_captain_editor = _create_visual_source(1, "ArmyCaptainVisualSource")
	_visual_sources_owned = true
	# The sources are created by editor.open(), so force the first transition
	# through the same pause path used after clearing an army.
	_visual_sources_active = true
	_set_visual_sources_active(false)

func visual_mode() -> String:
	return _soldier_visual_mode

func active_3d_source_count() -> int:
	return _all_visual_sources().size()

static func prewarm_soldier_atlas() -> bool:
	if _static_soldier_baked_ready and _static_soldier_atlas != null and not _static_soldier_frame_textures.is_empty():
		return true
	if not FileAccess.file_exists(ProjectSettings.globalize_path(SOLDIER_MANIFEST_PATH)):
		push_warning("TerrainArmy soldier atlas manifest is missing; using live fallback")
		return false
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
	_static_soldier_atlas = atlas
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
	_static_soldier_map_scale = float(manifest.get("map_scale", 1.0))
	_static_soldier_clip_counts.clear()
	_static_soldier_clip_durations.clear()
	_static_soldier_frame_textures.clear()
	_static_soldier_frame_anchors.clear()
	for clip_variant in manifest.get("clips", []):
		var clip: Dictionary = clip_variant
		_static_soldier_clip_counts[String(clip.get("id", ""))] = int(clip.get("samples", 1))
	for frame_variant in manifest.get("frames", []):
		var frame: Dictionary = frame_variant
		var clip_id := String(frame.get("clip", ""))
		var direction_id := String(frame.get("direction", "down"))
		var frame_id := int(frame.get("frame", 0))
		var key := "%s|%s|%d" % [clip_id, direction_id, frame_id]
		var rect_data: Dictionary = frame.get("rect", {})
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = atlas
		atlas_texture.region = Rect2(rect_data.get("x", 0), rect_data.get("y", 0), rect_data.get("w", 1), rect_data.get("h", 1))
		_static_soldier_frame_textures[key] = atlas_texture
		var anchor_data: Dictionary = frame.get("anchor_offset", {})
		_static_soldier_frame_anchors[key] = Vector2(float(anchor_data.get("x", 0.0)), float(anchor_data.get("y", 0.0))) * _static_soldier_map_scale
		_static_soldier_clip_durations[clip_id] = float(frame.get("duration", 1.0))
	if _static_soldier_frame_textures.is_empty():
		push_warning("TerrainArmy soldier atlas manifest has no frames; using live fallback")
		return false
	_static_soldier_baked_ready = true
	return true

static func reset_static_soldier_atlas() -> void:
	_static_soldier_atlas = null
	_static_soldier_frame_textures.clear()
	_static_soldier_frame_anchors.clear()
	_static_soldier_clip_counts.clear()
	_static_soldier_clip_durations.clear()
	_static_soldier_map_scale = 1.0
	_static_soldier_baked_ready = false

func prepare_captain_source() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _captain_editor != null:
		return
	_captain_editor = _create_visual_source(1, "ArmyCaptainVisualSource")
	_visual_sources_owned = true
	_visual_sources_active = true

func prepare_sprite_pool(count: int = SOLDIER_COUNT) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _sprites.size() >= count:
		return
	for index: int in range(_sprites.size(), count):
		var sprite := _new_person_sprite(index)
		sprite.visible = false
		_sprites.append(sprite)

func warmup_visual_step(step: int) -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	match step:
		0:
			var ok := prewarm_soldier_atlas()
			if ok:
				_load_baked_soldier()
				_soldier_baked_ready = true
				_soldier_visual_mode = "baked_atlas"
			return ok
		1:
			prepare_captain_source()
			return _captain_editor != null
		2:
			prepare_sprite_pool(roster_size)
			_set_visual_sources_active(false)
			visual_pool_ready = true
			return true
	return false

func is_visual_pool_ready() -> bool:
	return visual_pool_ready and _soldier_baked_ready and (_captain_editor != null or _deferred_captain_ready) and _sprites.size() >= roster_size

func _load_baked_soldier() -> bool:
	if not _static_soldier_baked_ready:
		if not prewarm_soldier_atlas():
			return false
	_soldier_atlas = _static_soldier_atlas
	_soldier_frame_textures = _static_soldier_frame_textures
	_soldier_frame_anchors = _static_soldier_frame_anchors
	_soldier_clip_counts = _static_soldier_clip_counts
	_soldier_clip_durations = _static_soldier_clip_durations
	_soldier_map_scale = _static_soldier_map_scale
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
	if locomotion_mode.size() == roster_size and locomotion_mode[index] == Locomotion.RUN:
		return "run"
	return "walk"

func _set_soldier_frame(index: int, force: bool = false) -> void:
	if _hide_journey_person(index): return
	if not _soldier_baked_ready or index < 0 or index >= _sprites.size() or _renders_live_presenter(index):
		return
	if _set_siege_work_frame(index): return
	_clear_siege_work_frame(index)
	if _set_vehicle_rider_frame(index): return
	if _sprites[index] != null and _sprites[index].has_meta("vehicle_rider_frame"):
		_clear_vehicle_rider_frame(index)
		_soldier_current_keys[index] = ""
	if _batch_view != null and _batch_render_active():
		var idle := str(combat_hot_get(index, &"pose")) == "idle" and not combat_hot_has(index, &"exchange_visual")
		var pose := "idle" if idle else _exchange_visual_pose(index)
		var clip: String = HELD_LOCOMOTION.idle if idle else _combat_clip(index, pose)
		var direction := _soldier_direction_id(facing[index] if idle else _exchange_visual_facing(index, pose))
		var sample := float(combat_hot_get(index, &"age"))
		var authored_duration := -1.0
		if not idle:
			var clock: Array = _combat_bake.contact_clocks[clip][direction]
			authored_duration = float(clock[1])
			sample = _exchange_animation_time(index, authored_duration, pose)
		if _batch_view.submit(index, combat_visual_ground(index), equipment_appearance(index), clip, direction, sample, authored_duration):
			if _sprites[index] != null:
				_sprites[index].queue_free()
				_sprites[index] = null
			return
	if _sprites[index] == null:
		_sprites[index] = _new_person_sprite(index)
		_sprites[index].scale = Vector2.ONE * _soldier_map_scale
	if combat_enabled:
		var appearance := equipment_appearance(index)
		if not appearance.is_empty() and not EquipmentAtlas.apply_dye(_sprites[index], appearance):
			if _uses_pooled_captain_geometry(index):
				_promote_deferred_captain()
				return
			_sprites[index].texture = null # No recolouring without an exact complete companion.
			return
		if not appearance.is_empty() and HumanCharacter3DEditor.EquipmentDye.geometry_appearance(appearance) != _combat_bake.manifest.appearance:
			var raw := contact_sample(index)
			var frame := EquipmentAtlas.frame(appearance, _combat_clip(index), _soldier_direction_id(Vector2i(raw[2])), float(raw[1]))
			if frame.is_empty():
				if _uses_pooled_captain_geometry(index):
					_promote_deferred_captain()
					return
				_sprites[index].texture = null # Missing assets must not show phantom full gear.
				return
			var equipment_key := "equipment|%s|%s|%s|%s|%d" % [str(appearance.body), str(appearance.parts), str(frame.clip), str(frame.direction), int(frame.frame)]
			if force or _soldier_current_keys[index] != equipment_key:
				_soldier_current_keys[index] = equipment_key
				_sprites[index].texture = frame.texture
				_soldier_sprite_anchors[index] = Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * float(frame.map_scale)
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
	if combat_enabled:
		var frame := combat_frame(index)
		key = _soldier_frame_key(str(frame.clip), str(frame.direction), int(frame.frame))
	if not force and _soldier_current_keys[index] == key:
		return
	var texture_variant = _soldier_frame_textures.get(key)
	if texture_variant == null:
		key = _soldier_frame_key("idle", direction_id, 0)
		texture_variant = _soldier_frame_textures.get(key)
	if texture_variant == null:
		if _uses_pooled_captain_geometry(index): _promote_deferred_captain()
		return
	_soldier_current_keys[index] = key
	_sprites[index].texture = texture_variant as Texture2D
	_soldier_sprite_anchors[index] = _soldier_frame_anchors.get(key, Vector2.ZERO)

# Presentation-only original crew handles; no pose/position/action clock is stored.
var _siege_work_visual_members: Dictionary = {}

func siege_work_state(index: int) -> Dictionary:
	return vehicle_transport.siege_work_pose(combat_identity(index)) if vehicle_transport != null and vehicle_transport.has_method("siege_work_pose") and combat_enabled and index >= 0 and index < combat_units.size() else {}

func _refresh_siege_work_visual_rows() -> void:
	var current := {}
	if vehicle_transport != null:
		for vehicle: Dictionary in vehicle_transport.records().values():
			if int(vehicle.get("team_id", -1)) != team_id or not vehicle_transport.is_siege(vehicle): continue
			for identity: int in vehicle.get("crew_slots", {}).values():
				var index := index_for_identity(identity)
				if index >= 0 and not siege_work_state(index).is_empty(): current[index] = true
	for index: int in _siege_work_visual_members:
		if index >= 0 and index < combat_units.size(): _mark_visual_row(index)
	for index: int in current: _mark_visual_row(index)
	_siege_work_visual_members = current

func _set_siege_work_frame(index: int) -> bool:
	var work := siege_work_state(index)
	if work.is_empty(): return false
	if _sprites[index] == null: _sprites[index] = _new_person_sprite(index)
	if _sprites[index].has_meta("vehicle_rider_frame"): _clear_vehicle_rider_frame(index)
	var appearance := equipment_appearance(index)
	var frame := SiegeWorkAppend.frame(appearance, str(work.clip), _soldier_direction_id(Vector2i(work.facing)), float(work.time))
	if frame.is_empty() or not SiegeWorkAppend.apply(_sprites[index], appearance, frame):
		_sprites[index].texture = null # Missing work assets never show an idle stand-in.
		return true
	_sprites[index].scale = Vector2.ONE * float(frame.map_scale)
	_soldier_sprite_anchors[index] = Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * float(frame.map_scale)
	_soldier_current_keys[index] = "siege_work|" + str(work.clip) + "|" + str(frame.frame)
	return true

func _clear_siege_work_frame(index: int) -> void:
	if _sprites[index] == null or not _sprites[index].has_meta("siege_work_frame"): return
	_sprites[index].remove_meta("siege_work_frame")
	_sprites[index].remove_meta("equipment_dye_appearance")
	_sprites[index].material = null
	_soldier_current_keys[index] = ""
	if not _renders_live_presenter(index): _sprites[index].scale = Vector2.ONE * _soldier_map_scale

func _vehicle_rider_state(index: int) -> Dictionary:
	return vehicle_transport.rider_state(combat_identity(index)) if vehicle_transport != null and combat_enabled and index >= 0 and index < combat_units.size() else {}

func _set_vehicle_rider_frame(index: int) -> bool:
	var state := _vehicle_rider_state(index)
	if state.is_empty(): return false
	if _sprites[index] == null: _sprites[index] = _new_person_sprite(index)
	var sprite := _sprites[index]
	var appearance := equipment_appearance(index)
	var frame := VehicleRiderAtlas.frame(appearance, _soldier_direction_id(state.facing), bool(state.moving), float(state.progress))
	if frame.is_empty() or not VehicleRiderAtlas.apply(sprite, appearance, frame):
		sprite.texture = null # Missing fixed rider visual must not show a walking body.
		return true
	sprite.set_meta("vehicle_rider_anchor", frame.anchor)
	sprite.set_meta("vehicle_rider_ground", Vector2(state.position) + Vector2(frame.horse_offset))
	sprite.set_meta("vehicle_rider_sort_ground", state.position)
	return true

func _clear_vehicle_rider_frame(index: int) -> void:
	var sprite := _sprites[index]
	for key: String in ["vehicle_rider_frame", "vehicle_rider_anchor", "vehicle_rider_ground", "vehicle_rider_sort_ground"]:
		sprite.remove_meta(key)
	sprite.material = null
	sprite.remove_meta("equipment_dye_appearance")
	if not _renders_live_presenter(index): sprite.scale = Vector2.ONE * _soldier_map_scale

func _sprite_sort_ground(index: int) -> Vector2:
	var sprite := _sprites[index]
	return sprite.get_meta("vehicle_rider_sort_ground") if sprite != null and sprite.has_meta("vehicle_rider_frame") else combat_ground(index)

func _update_soldier_frames(delta: float) -> void:
	if not _soldier_baked_ready or _sprites.size() != roster_size:
		return
	_soldier_animation_accumulator += delta
	if _soldier_animation_accumulator < SOLDIER_ANIMATION_TICK:
		return
	var elapsed := _soldier_animation_accumulator
	_soldier_animation_accumulator = fmod(_soldier_animation_accumulator, SOLDIER_ANIMATION_TICK)
	for index: int in range(roster_size):
		if _renders_live_presenter(index):
			continue
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
	for editor: Variant in _all_visual_sources():
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
	if _captain_editor.combat_ready:
		_captain_editor.combat_ready = false
		_captain_editor.visual_state.combat_ready = false
		force = true
	var direction := Vector2i.DOWN
	var clip := &"idle"
	if cells.size() > 0 and facing.size() > 0:
		direction = facing[0]
		if movement_state.size() > 0:
			var captain_state: int = movement_state[0]
			if captain_state == UnitState.MOVING or captain_state == UnitState.SWAPPING:
				clip = &"run" if locomotion_mode.size() == roster_size and locomotion_mode[0] == Locomotion.RUN else &"walk"
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
	var editor := SharedVisualSource.new()
	editor.name = source_name
	editor.preview_host = self
	editor.visual_state.body_index = body_index
	add_child(editor)
	editor.open()
	if not SiegeWorkClips.install(editor): push_error("TerrainArmy: original private work AnimationLibrary could not be prepared")
	if (source_name == "ArmyCaptainVisualSource" or source_name.begins_with("ArmyPerson_")) and ClassDB.class_has_method("AnimationPlayer", "set_clear_cache_on_stop_enabled"):
		# Keep this bound to the presenter, not its Army: presenters can transfer.
		editor.preview_pivot.child_entered_tree.connect(TerrainArmy._retain_visual_animation_cache.bind(editor))
		TerrainArmy._retain_visual_animation_cache(editor.model_root, editor)
	# Match the canonical map presenter setup used by TerrainTestCharacter.
	# Without this explicit post-open configuration, a lazily-created source
	# can keep an opaque clear color; 100 projected sprites then form a black
	# rectangle over the terrain.
	var viewport: SubViewport = editor.preview_viewport
	viewport.size = CharacterRenderContract.MAP_VIEWPORT_SIZE
	viewport.transparent_bg = true
	var preview_ground := editor.preview_world.get_node_or_null("PreviewGround") as Node3D
	if preview_ground != null:
		preview_ground.hide()
	for child: Node in editor.preview_world.get_children():
		if child is WorldEnvironment:
			(child as WorldEnvironment).environment.background_mode = Environment.BG_CLEAR_COLOR
	editor.select_animation_by_id(&"idle")
	editor.set_playing(true)
	if editor.editor_root != null:
		editor.editor_root.hide()
	if exchange_enabled:
		editor.set_process(false)
	return editor

static func _retain_visual_animation_cache(model: Node, editor: HumanCharacter3DEditor) -> void:
	if model == null or model != editor.model_root:
		return
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		# Whole-body reload creates fresh bindings. Partial target replacement must
		# still explicitly clear caches, as required by AnimationMixer itself.
		players[0].call("set_clear_cache_on_stop_enabled", false)

func clear(region_bind_token: String = "") -> void:
	social_cohort = {}
	if has_ship_journey() and not _region_trusted_bind_clear(region_bind_token):
		command_status = "BUSY | 船隊仍在跨區旅程中，不能清除原人物"
		return
	_audio_step_sources.clear()
	_invalidate_ranged_order()
	ranged_ammo_mode = "NORMAL"
	_ranged_last_release_ids.clear()
	garrison_feature_id = ""
	remove_meta(&"crowd_return_handoff")
	_stop_tactical_ai()
	tactical_ai_decisions = 0
	tactical_ai_orders = 0
	_issuing_tactical_ai_order = false
	_release_combat_hot_store(true)
	_fire_nav_reset()
	_fire_threat_last_end = -1.0
	_release_combat_deployment_lease()
	_suppress_approaches.clear()
	formation_preset_id = "auto"
	formation_intent_version = 0
	_formation_change_pending = false
	_formation_retry_seconds = 0.0
	_move_encounters.clear()
	_move_landed_members.clear()
	_combat_absent_slots.clear()
	_retreat_pair_pending.clear()
	_retreat_pairs_used.clear()
	_retreat_resolution.clear()
	_corps_reposition_source.clear()
	_retreat_paths.clear()
	_retreat_path_revision = -1
	if _coordinator != null and _coordinator.has_method("restore_inflight_batches_for_formation"):
		_coordinator.restore_inflight_batches_for_formation(self, [])
	_combat_batch_members.clear()
	for row: Dictionary in combat_units: PersonFatigue.unbind(row)
	if is_instance_valid(player_member): PersonFatigue.unbind(player_member)
	team_fatigue = {}
	_fatigue_roster_size = -1
	individual_fatigue_indices.clear()
	encirclement_steps = 0
	encirclement_reviews = 0
	geometry_prefilter_reviews = 0
	geometry_prefilter_skipped = 0
	roster_size = SOLDIER_COUNT
	projectiles.clear()
	for actor: TerrainTestCharacter in _external_rescuers.values():
		actor._cancel_rescue()
	_external_rescuers.clear()
	if is_instance_valid(player_member) and player_member._army_rescuer == self:
		player_member._army_rescuer = null
	_unit_rescues.clear()
	player_member = null
	player_present = false
	player_goal = INVALID_CELL
	queue_redraw()
	combat_enabled = false
	combat_attacking = false
	combat_units.clear()
	_deferred_captain_ready = false
	_invalidate_combat_identity_cache()
	_combat_pose_cache.clear()
	_contact_batch_inputs = []
	_contact_batch_pose_results = []
	combat_order = CombatOrder.HOLD
	formal_commander = -1
	acting_commander = -1
	current_commander = -1
	officer_order.clear()
	officer_service.clear()
	offices = {}
	duty_traces.clear()
	_serving_ids.clear()
	_serving_dirty = true
	_head_established = false
	_last_holders.clear()
	command_abilities.clear()
	combat_slots.clear()
	_vacancy_assignments.clear()
	needs_attack_order = false
	command_notice = ""
	command_reference_valid = false
	combat_goal = INVALID_CELL
	_presence_geometry_cache = []
	pursuit_left = 0.0
	pursuit_target = -1
	_combat_move_plan = null
	_combat_deployment_plan = null
	_formation_movement_profile = null
	_command_dirty = false
	_command_elapsed = 0.0
	_order_delay = 0.0
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
	combat_render_usec = 0
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
	_follower_combat_route_stamps.clear()
	_follower_failed_combat_routes.clear()
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
	move_curve.clear()
	blocked_time.clear()
	swap_partner.clear()
	facing.clear()
	edge_targets.clear()
	for sprite: Sprite2D in _sprites:
		if sprite != null: sprite.visible = false
	if _batch_view != null:
		_batch_view.release_sprites()
		_batch_view.queue_free()
		_batch_view = null
	_set_visual_sources_active(false)

func has_army() -> bool:
	return not cells.is_empty() and cells.size() == roster_size

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
		if selected.size() == roster_size:
			break
	if selected.size() != roster_size:
		clear()
		command_status = "Deploy rejected: only %d/%d legal cells" % [selected.size(), roster_size]
		return false
	# Put the captain near the centre of the initial reachable patch. Starting
	# on the outside made the first command look like a queue leaving a camp;
	# a central leader lets the first OPEN formation preserve the deployed body.
	var captain_position := mini(selected.size() - 1, floori(float(selected.size()) / 2.0))
	var captain_cell: Vector2i = selected[captain_position]
	selected.remove_at(captain_position)
	selected.push_front(captain_cell)
	return _deploy_selected(selected)

func deploy_at(new_data: TerrainData, new_player: Variant, new_npc: Variant, selected: Array[Vector2i]) -> bool:
	if has_army() or new_data == null or selected.size() != roster_size:
		return false
	var used := {}
	for cell: Vector2i in selected:
		if not new_data.is_walkable(cell) or used.has(cell) or (external_blocker.is_valid() and external_blocker.call(cell)):
			return false
		for actor: Variant in [new_player, new_npc]:
			if actor != null and actor.occupies_cell(cell):
				return false
		used[cell] = true
	data = new_data
	player = new_player
	npc = new_npc
	clear()
	return _deploy_selected(selected)

func _deploy_selected(selected: Array[Vector2i]) -> bool:
	if selected.is_empty() or selected.size() > MAX_ROSTER_SIZE:
		return false
	roster_size = selected.size()
	cells = selected.duplicate()
	for index: int in range(roster_size):
		desired_cells.append(cells[index])
		moving_to.append(INVALID_CELL)
		movement_state.append(UnitState.IDLE)
		locomotion_mode.append(Locomotion.IDLE)
		move_progress.append(0.0)
		move_duration.append(MOVE_DURATION)
		move_curve.append(0)
		blocked_time.append(0.0)
		swap_partner.append(-1)
		_push_lock.append(0)
		facing.append(Vector2i.DOWN)
		if not _ship_embarked(index): _cell_owners[cells[index]] = index
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
	_formation_anchor_height = int(data.navigation_heights()[data.index(cells[0])])
	formation_mode = FormationMode.OPEN
	_formation_width = FORMATION_COLUMNS
	_formation_slot_cells.resize(roster_size)
	_formation_offsets.resize(roster_size)
	for index: int in range(roster_size):
		_formation_slot_cells[index] = cells[index]
		_formation_offsets[index] = cells[index] - cells[0]
	formation_count_value = roster_size - 1
	_rebuild_visual_instances()
	_set_visual_sources_active(true)
	# A SubViewport publishes its first rendered texture after the current
	# frame. Keep the shared 3D sources alive for two draw frames so the map
	# sprites never capture the viewport's initial black clear texture.
	_visual_warmup_frames = 2
	command_status = "Deployed %d actual members" % roster_size
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
	if _team_ship_activity(): return false
	if not garrison_feature_id.is_empty(): return false
	if combat_enabled:
		command_status = "近戰測試尚未接入整隊移動；請先結束測試"
		return false
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
	if _team_ship_activity(): return
	if _pending_command < 0 or not has_army() or moving_count() > 0:
		return
	if _passage_active:
		for index: int in range(roster_size):
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
	average /= float(roster_size)
	_formation_anchor_cell = Vector2i(average.round())
	if not data.contains(_formation_anchor_cell) or not data.is_walkable(_formation_anchor_cell) or _is_external_cell(_formation_anchor_cell):
		_formation_anchor_cell = cells[0]
	_cancel_pending_pushes()
	_command_goal_pending = true
	# A command change invalidates unstarted follower detours and queued claims,
	# while a move already in progress is allowed to finish atomically.
	_follower_combat_route_stamps.clear()
	_follower_failed_combat_routes.clear()
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
	return _cell_owners.has(cell) and not _ship_in_journey(int(_cell_owners[cell])) or _reserved_cells.has(cell) and not _ship_in_journey(int(_reserved_cells[cell])) or vehicle_transport != null and vehicle_transport.team_blocks_cell(self, cell)

func blocks_person_cell(cell: Vector2i) -> bool:
	return _cell_owners.has(cell) or _reserved_cells.has(cell) or vehicle_transport != null and vehicle_transport.team_blocks_person_cell(self, cell)

func occupied_count() -> int:
	return _cell_owners.size()

func moving_count() -> int:
	return movement_state.count(UnitState.MOVING) + movement_state.count(UnitState.SWAPPING)

func swap_count() -> int:
	return _swap_count

func completed_steps() -> int:
	return _completed_steps

func has_active_swap() -> bool:
	return has_army() and swap_partner.size() == roster_size and swap_partner[0] >= 0

func arrived_count() -> int:
	if not has_army():
		return 0
	var count := 0
	for index: int in range(roster_size):
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
	if locomotion_mode.size() != roster_size:
		return 0
	var count := 0
	for index: int in range(roster_size):
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
	for index: int in range(1, roster_size):
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

func _is_external_cell(cell: Vector2i, ignore_operator: int = 0, from: Vector2i = INVALID_CELL, goal: Vector2i = INVALID_CELL, origin: Vector2i = INVALID_CELL) -> bool:
	var person_index := index_for_identity(ignore_operator) if ignore_operator > 0 else -1
	if person_index >= 0:
		if origin == INVALID_CELL: origin = cells[person_index]
		if from == INVALID_CELL: from = origin
		if goal == INVALID_CELL: goal = _follower_route_goals.get(person_index, combat_slots[person_index])
	if vehicle_transport != null and (vehicle_transport.blocks_person_step(ignore_operator, origin, from, cell, goal) if from != INVALID_CELL and goal != INVALID_CELL else vehicle_transport.blocks_person_cell(cell, ignore_operator)):
		return true
	var shared_valid := _shared_movement_blockers_valid()
	if shared_valid and _shared_movement_blockers.has(cell):
		return true
	if not shared_valid and external_blocker.is_valid():
		var exception: bool = vehicle_transport != null and vehicle_transport.person_path_exception(cell, ignore_operator, origin, from, goal)
		var blocker_owner: Object = external_blocker.get_object()
		if exception and blocker_owner is TerrainArmy and blocker_owner.get_script() == TerrainArmy and external_blocker.get_method() == &"blocks_cell":
			if blocker_owner._cell_owners.has(cell) or blocker_owner._reserved_cells.has(cell): return true
		elif exception and blocker_owner is TerrainLab and blocker_owner.get_script() == TerrainLab and external_blocker.get_method() == &"_armies_block_cell":
			for other: TerrainArmy in blocker_owner.combat_armies:
				if other != self and (other._cell_owners.has(cell) or other._reserved_cells.has(cell)): return true
		elif external_blocker.call(cell): return true
	var player_actor: Variant = player
	var npc_actor: Variant = npc
	if player_actor != null and (player_actor.occupies_cell(cell) if player_actor.has_method("occupies_cell") else player_actor.terrain_cell == cell):
		return true
	if npc_actor != null and (npc_actor.occupies_cell(cell) if npc_actor.has_method("occupies_cell") else npc_actor.terrain_cell == cell):
		return true
	return false

func reserves_terrain_cell(cell: Vector2i) -> bool:
	return blocks_cell(cell) or (has_army() and _passage_cell_is_protected(cell))

func cancel_invalid_structure_steps(lost_surfaces: Dictionary = {}) -> void:
	var cancelled := {}
	for index in range(cells.size()):
		if moving_to[index] == INVALID_CELL or _combat_batch_members.has(combat_identity(index)): continue
		if lost_surfaces.has(data.index(cells[index])) or lost_surfaces.has(data.index(moving_to[index])) or not data.can_step(cells[index], moving_to[index]): cancelled[index] = true
	# A cancelled source remains occupied: roll back its whole dependency chain,
	# including the original pair/batch, before releasing any destination lease.
	var changed := true
	while changed:
		changed = false
		for index in range(cells.size()):
			if moving_to[index] == INVALID_CELL or cancelled.has(index): continue
			for other: int in cancelled.keys():
				if moving_to[index] == cells[other] or swap_partner[index] == other:
					cancelled[index] = true
					changed = true
					break
		for batch: Dictionary in _formation_step_batches:
			var affected := false
			for index: int in batch.units:
				if cancelled.has(index): affected = true
			if not affected: continue
			for index: int in batch.units:
				if not cancelled.has(index):
					cancelled[index] = true
					changed = true
	if cancelled.is_empty(): return
	for index: int in cancelled.keys(): cancel_committed_move_to_source(combat_identity(index))
	var retained: Array[Dictionary] = []
	_formation_step_units.clear()
	for batch: Dictionary in _formation_step_batches:
		if not cancelled.has(int(batch.units[0])):
			retained.append(batch)
			_formation_step_units.append_array(batch.units)
	_formation_step_batches = retained
	if retained.is_empty(): _formation_step_direction = Vector2i.ZERO
	if cancelled.has(_follower_swap_a) or cancelled.has(_follower_swap_b):
		_follower_swap_a = -1
		_follower_swap_b = -1
	_cancel_pending_pushes()
	_prune_stale_reservations()
	if _coordinator != null: _coordinator.request_occupancy_rebuild()

func notify_terrain_changed() -> void:
	_visual_dirty = true
	if has_army() and command != Command.NONE:
		# The command queue drains existing steps and passage reservations first.
		issue_command(command)

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
				terminal_flat = terminal_flat and data.navigation_heights()[data.index(cell)] == data.navigation_heights()[data.index(passage.entry)]
			if not terminal_flat:
				for cell: Vector2i in passage.protected:
					protected[cell] = true
				protected[passage.exit] = true
		# Select a feasible front before publishing its immutable route. This
		# reuses the same local 100-cell builder; it is one command-level check,
		# not a search per soldier or a later drift of the requested goal.
		var layout := await _compact_boundary_layout(reachable, protected, candidate, heading, revision)
		if layout.size() == roster_size:
			return candidate
		for lateral_min: int in range(-FORMATION_COLUMNS + 1, 1):
			if lateral_min == -4:
				continue
			layout = await _compact_boundary_layout(reachable, protected, candidate, heading, revision, lateral_min)
			if layout.size() == roster_size:
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
			if result.size() >= roster_size - 1:
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
	if _captain_trail.size() < roster_size + 1:
		return false
	var remaining: Array[int] = []
	for index: int in range(1, roster_size):
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
	if _passage_active or not _formation_has_bottleneck or formation_mode != FormationMode.COLUMN or _captain_trail.size() < roster_size + 1:
		return
	if captain_at_boundary() and _exit_rally_assigned:
		return
	var slot_targets: Array[Vector2i] = []
	slot_targets.resize(roster_size)
	for index: int in range(roster_size):
		slot_targets[index] = desired_cells[index]
	if _assign_bottleneck_queue_targets(slot_targets):
		if captain_at_boundary() and not _exit_rally_targets(cells[0]).is_empty():
			_exit_rally_assigned = true
		_update_formation_status()

func _formation_all_settled() -> bool:
	if not has_army() or desired_cells.size() != roster_size:
		return false
	for index: int in range(1, roster_size):
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
		for unit: int in range(roster_size):
			if not _unit_has_cleared_group(unit):
				group_clear = false
				break
	for index: int in range(1, roster_size):
		bindings[desired_cells[index]] = index
	var changed := false
	for index: int in range(1, roster_size):
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
	if not has_army() or (_passage_active and not _formation_march_active) or formation_mode != FormationMode.OPEN or _formation_has_bottleneck or _formation_slot_cells.size() != roster_size:
		return false
	for index: int in range(1, roster_size):
		if int(_cell_owners.get(_formation_slot_cells[index], -1)) <= 0:
			return false
	return true

func _all_followers_on_captain_height() -> bool:
	if not has_army() or data == null:
		return false
	var captain_height := int(data.navigation_heights()[data.index(cells[0])])
	for index: int in range(1, roster_size):
		if not data.contains(cells[index]) or int(data.navigation_heights()[data.index(cells[index])]) != captain_height:
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
	if _exit_rally_slots.size() != roster_size - 1:
		return false
	var valid_slots := {}
	for slot: Vector2i in _exit_rally_slots:
		if not data.is_walkable(slot) or _is_external_cell(slot) or valid_slots.has(slot):
			return false
		valid_slots[slot] = true
	var captain_height := int(data.navigation_heights()[data.index(cells[0])])
	for index: int in range(1, roster_size):
		if movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING:
			return false
		if cells[index] != desired_cells[index] or not valid_slots.has(cells[index]):
			return false
		if not data.contains(cells[index]) or int(data.navigation_heights()[data.index(cells[index])]) != captain_height:
			return false
	return true

func _publish_exit_rally_targets() -> bool:
	if _exit_rally_slots.size() != roster_size - 1:
		return false
	var available: Array[int] = []
	for index: int in range(1, roster_size):
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
	_follower_combat_route_stamps.clear()
	_follower_failed_combat_routes.clear()
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
	_follower_combat_route_stamps.clear()
	_follower_failed_combat_routes.clear()
	_follower_routes.clear()
	_follower_route_goals.clear()
	_follower_route_cursors.clear()
	for index: int in range(1, roster_size):
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
	for index: int in range(roster_size):
		var phase_complete := not _passage_active
		if _passage_active and _unit_passage_phase.size() == roster_size:
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
			and _formation_slot_cells.has(cells[index]) and data.navigation_heights()[data.index(cells[index])] == data.navigation_heights()[data.index(cells[0])]:
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
		if formation_count_value < roster_size - 1:
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
		if initial_layout.size() != roster_size:
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
			average /= float(roster_size)
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
			if nearby.size() == roster_size and nearby_spread < old_spread:
				initial_layout = nearby
				initial_compact = true
		anchor = initial_layout[0]
	var height := int(data.navigation_heights()[data.index(anchor)])
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
	_formation_slot_cells.resize(roster_size)
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
		and _formation_offsets.size() == roster_size and not heading_changed \
		and (command == Command.NONE or _formation_march_active) and initial_layout.is_empty()
	var used := {anchor: true}
	# Reserve the captain's published destination as well as his current cell.
	# Without this, a follower can claim the edge/leader goal before the captain
	# arrives and turn a valid route into a self-blocking formation target.
	if data.contains(desired_cells[0]):
		used[desired_cells[0]] = true
	var slot_targets: Array[Vector2i] = []
	slot_targets.resize(roster_size)
	slot_targets[0] = anchor
	for slot_index: int in range(1, roster_size):
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
		for index: int in range(1, roster_size):
			desired_cells[index] = slot_targets[index]
			_formation_slot_cells[index] = slot_targets[index]
	elif force or mode != previous_mode or heading_changed:
		var available: Array[int] = []
		for index: int in range(1, roster_size):
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
				for slot_index: int in range(1, roster_size):
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
			for slot_index: int in range(1, roster_size):
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
		for slot_index: int in range(1, roster_size):
			if slot_targets[slot_index] != INVALID_CELL:
				available_slots.append(slot_index)
		for index: int in range(1, roster_size):
			if available_slots.is_empty():
				desired_cells[index] = INVALID_CELL
				_formation_slot_cells[index] = INVALID_CELL
				continue
			var previous_slot := cells[index]
			if _formation_slot_cells.size() == roster_size and _formation_slot_cells[index] != INVALID_CELL:
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
		_formation_offsets.resize(roster_size)
		_formation_offsets[0] = Vector2i.ZERO
		for index: int in range(1, roster_size):
			_formation_offsets[index] = desired_cells[index] - anchor if desired_cells[index] != INVALID_CELL else Vector2i.ZERO
	_formation_march_active = marching
	_update_formation_status()

func _formation_front_at_goal() -> bool:
	if _passage_active:
		if _passage_group_start < _passage_descriptors.size() or _formation_anchor_cell != _passage_final_captain_slot:
			return false
		for index: int in range(1, roster_size):
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
		for index: int in range(roster_size):
			units.append(index)
	elif not _formation_bend_active:
		return false
	var included := {}
	for index: int in units:
		if index < 0 or index >= roster_size or included.has(index):
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
		if data.navigation_heights()[data.index(source)] != data.navigation_heights()[data.index(destination)]:
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
		move_curve[index] = 0
		movement_state[index] = UnitState.MOVING
		locomotion_mode[index] = Locomotion.WALK
		blocked_time[index] = 0.0
		facing[index] = direction
		_audio_begin_step(index, cells[index], destination, false)
	_visual_dirty = true
	return true

func _complete_formation_batch(batch: Dictionary) -> bool:
	var direction: Vector2i = batch.direction
	var units: Array[int] = batch.units
	for index: int in units:
		var destination := moving_to[index]
		if _cell_owners.get(cells[index], -1) != index or destination != cells[index] + direction \
			or not data.can_step(cells[index], destination) or _reserved_cells.get(destination, -1) != index \
			or _is_external_cell(destination) or data.navigation_heights()[data.index(cells[index])] != data.navigation_heights()[data.index(destination)]:
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
		var audio_candidate := _audio_take_step(index, source, destination, move_duration[index])
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
		_audio_emit_step(audio_candidate)
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
		for index: int in range(roster_size):
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
		for index: int in range(roster_size):
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
	if _formation_final_reform or _passage_final_slots.size() != roster_size - 1:
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
	for index: int in range(1, roster_size):
		if available.has(cells[index]):
			desired_cells[index] = cells[index]
			available.erase(cells[index])
		else:
			remaining.append(index)
	for index: int in remaining:
		var nearest := 0
		for available_index: int in range(1, available.size()):
			if cells[index].distance_squared_to(available[available_index]) < cells[index].distance_squared_to(available[nearest]):
				nearest = available_index
		desired_cells[index] = available[nearest]
		available.remove_at(nearest)
	for index: int in range(roster_size):
		_formation_slot_cells[index] = desired_cells[index]
		_formation_offsets[index] = desired_cells[index] - layout[0]
		_clear_follower_route(index)
	_passage_binding_revision += 1

func _begin_bend_subset() -> bool:
	var started := false
	for direction: Vector2i in _formation_bend_order:
		var participants: Array[int] = []
		for index: int in range(roster_size):
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
		for index: int in range(roster_size):
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
		for route_index: int in range(route.size()):
			ribbon[route[route_index]] = route.size() - route_index - 1
			lateral[route[route_index]] = 0
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
		_formation_bend_span = maxi(farthest - nearest + 2, ceili(float(roster_size) / maxi(1, width)) + width * 2)
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
		for index: int in range(roster_size):
			source_owners[sources[index]] = index
		var detours: Array[Dictionary] = []
		for direction: Vector2i in TerrainData.DIRECTIONS:
			for index: int in range(roster_size):
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
			for index: int in range(roster_size):
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
	if best.size() == roster_size:
		var batch_order: Array[Vector2i] = []
		var frozen := {}
		var blocked := {}
		for index: int in range(roster_size):
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
				for index: int in range(roster_size):
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
	for index: int in range(roster_size):
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
	for index: int in range(roster_size):
		progress += _bend_cell_potential(sources[index], field, index) - _bend_cell_potential(targets[index], field, index)
	return progress

func _bend_cell_potential(cell: Vector2i, field: Dictionary, index: int) -> int:
	# Lateral closeness to the guide is not forward travel. Keep real legal
	# distances for span/protection, but do not funnel every rank onto its lane.
	if _passage_group_start >= _passage_descriptors.size():
		var target_field: Dictionary = _formation_final_fields.get("goal_component" if index == 0 else "goal_slot_component", {})
		var target_distance := int(target_field.get(cell, field[cell]))
		# Fill the fixed set away from its entrance, including lateral wings.
		# A point-front tie score pinned occupied rows beside empty side slots.
		return target_distance * target_distance * (roster_size * 2 + 1) - int(_passage_final_component.get(cell, 0))
	var distance := maxi(0, int(field[cell]) - int(_formation_bend_lateral.get(cell, 0)))
	return distance * distance * (roster_size * 2 + 1) + int(_formation_bend_lateral.get(cell, 0))

func _bend_candidate(sources: Array[Vector2i], direction: Vector2i, downhill_only: bool, field: Dictionary, neighbors: Dictionary, revision: int, frozen: Dictionary = {}, blocked: Dictionary = {}, positive_chains: bool = true) -> Array[Vector2i]:
	var targets: Array[Vector2i] = sources.duplicate()
	var occupied := {}
	var source_owners := {}
	var order: Array[int] = []
	for index: int in range(roster_size):
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
			or not data.can_step(source, next) or data.navigation_heights()[data.index(source)] != data.navigation_heights()[data.index(next)]:
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
		for index: int in range(roster_size):
			occupied[targets[index]] = index
	var connected := await _repair_bend_body(sources, targets, occupied, order, field, neighbors, revision)
	if revision != _structure_revision or connected.size() != roster_size:
		return []
	var nearest := 1 << 29
	var farthest := 0
	var guards := 0
	var rear := 0
	for index: int in range(roster_size):
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
	for _repair: int in range(roster_size):
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
		if connected.size() == roster_size and target_far - target_near <= _formation_bend_span and target_guards >= 20 and target_guards <= 70 and target_rear >= 20:
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
		var bridge_cost := roster_size + 1
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
		if connected.size() < roster_size and undo.is_empty():
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
		for order_index: int in range(order.size() - 1, -1, -1):
			var index := order[order_index]
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
			var front_rows := floori(float(ceili(float(roster_size) / float(candidate_width)) - 1) / 2.0)
			selected = await _passage_rally_rectangle(field, protected, _formation_anchor_cell + heading * front_rows, revision, heading, candidate_width, false, nearby)
			if selected.size() == roster_size:
				break
	if revision != _structure_revision:
		return
	if selected.size() == roster_size:
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
					or not data.can_step(source, destination) or data.navigation_heights()[data.index(source)] != data.navigation_heights()[data.index(destination)]:
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
	var current_height := int(data.navigation_heights()[data.index(cells[0])])
	var next_height := int(data.navigation_heights()[data.index(next)])
	if current_height != next_height:
		return false
	return _walkable_degree(cells[0]) >= 3

func _take_local_search(unit_index: int) -> bool:
	if _local_path_requests_remaining <= 0 or int(_local_search_tick.get(unit_index, -1)) == _passage_tick:
		return false
	_local_path_requests_remaining -= 1
	_local_search_tick[unit_index] = _passage_tick
	_local_path_cursor = unit_index % maxi(1, roster_size - 1) + 1
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
	var item_score := item.y + item.z
	while index > 0:
		var parent := (index - 1) >> 1
		var parent_item: Vector4i = heap[parent]
		var parent_score := parent_item.y + parent_item.z
		if not (item_score < parent_score or (item_score == parent_score \
			and (item.z < parent_item.z or (item.z == parent_item.z and item.w < parent_item.w)))):
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
		if child + 1 < heap.size():
			var left_item: Vector4i = heap[child]
			var right_item: Vector4i = heap[child + 1]
			var left_score := left_item.y + left_item.z
			var right_score := right_item.y + right_item.z
			if right_score < left_score or (right_score == left_score \
				and (right_item.z < left_item.z or (right_item.z == left_item.z and right_item.w < left_item.w))):
				child += 1
		var child_item: Vector4i = heap[child]
		var parent_item: Vector4i = heap[index]
		var child_score := child_item.y + child_item.z
		var parent_score := parent_item.y + parent_item.z
		if not (child_score < parent_score or (child_score == parent_score \
			and (child_item.z < parent_item.z or (child_item.z == parent_item.z and child_item.w < parent_item.w)))):
			break
		var value := heap[index]
		heap[index] = heap[child]
		heap[child] = value
		index = child
	return first

func _try_direct_combat_route(start: Vector2i, goal: Vector2i, profile: Object, avoid_occupied_first_step: bool, expansion_limit: int) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var blocked_first := _current_movement_blocked_destinations() if avoid_occupied_first_step else {}
	var distance := absi(goal.x - start.x) + absi(goal.y - start.y)
	if distance > 12 or expansion_limit < distance + 1:
		return empty
	for horizontal_first: bool in [true, false]:
		var route: Array[Vector2i] = [start]
		var current := start
		while current != goal:
			var delta := goal - current
			var horizontal := delta.x != 0 and (horizontal_first or delta.y == 0)
			var next := current + (Vector2i(signi(delta.x), 0) if horizontal else Vector2i(0, signi(delta.y)))
			if not FormationTransitPlanner._can_profile_step(data, current, next, profile) \
				or (avoid_occupied_first_step and current == start and (_cell_owners.has(next) or blocked_first.has(next) or _is_external_cell(next, 0, current, goal, start))) \
				or (_is_external_cell(next, 0, current, goal, start) and next != goal) \
				or (_reserved_cells.has(next) and int(_reserved_cells[next]) != -1) \
				or (_cell_owners.has(next) and next != goal):
				break
			route.append(next)
			current = next
		if current == goal:
			return route
	return empty

func _find_local_route(start: Vector2i, goal: Vector2i, expansion_limit: int = 256, allow_occupied: bool = false, moving_index: int = -1, vehicle_operator: int = 0, anticipate_vehicles: bool = false, profile: Object = null, avoid_occupied_first_step: bool = false, route_status: Variant = null, route_policy: Callable = Callable(), goal_test: Callable = Callable()) -> Array[Vector2i]:
	route_calls += 1
	var track_dynamic: bool = route_status is Dictionary and bool(route_status.get("track_dynamic", false))
	if route_status is Dictionary:
		route_status.clear()
		route_status["capped"] = false
		route_status["outcome"] = "invalid"
		if track_dynamic:
			route_status["dependencies"] = {}
			route_status["dependency_incomplete"] = false
	var empty: Array[Vector2i] = []
	if goal_test.is_valid() and not route_policy.is_valid(): return empty
	if data == null or not data.contains(start) or not data.contains(goal) or start == goal and not goal_test.is_valid():
		return empty
	if moving_index >= 0 and not _take_local_search(moving_index):
		if route_status is Dictionary: route_status["outcome"] = "deferred"
		return empty
	expansion_limit = mini(expansion_limit, LOCAL_PATH_EXPANSIONS)
	var canonical_foot_terrain: bool = data.get_script() == TerrainData
	if not route_policy.is_valid() and native_local_route_enabled and combat_enabled and moving_index == -1 and vehicle_operator == 0 and canonical_foot_terrain and (vehicle_transport == null or not vehicle_transport.has_siege()) \
		and (profile == null or profile.get_script() == FormationMovementProfile and int(profile.get("max_step_height")) >= 0):
		var packet := _native_local_route(start, goal, expansion_limit, allow_occupied, profile, avoid_occupied_first_step, track_dynamic)
		if packet.has("route"):
			var expansions := int(packet.head)
			expanded_nodes += expansions
			local_search_expansions += expansions
			max_local_search_expansions = maxi(max_local_search_expansions, expansions)
			if packet.outcome == "direct": direct_route_hits += 1
			if bool(packet.capped) and combat_profile_enabled: profiled_search_cap_failures += 1
			if route_status is Dictionary:
				route_status["outcome"] = packet.outcome
				route_status["capped"] = packet.capped
				if track_dynamic:
					route_status["dependencies"] = packet.dependencies
					route_status["dependency_incomplete"] = packet.dependency_incomplete
			var native_route: Array[Vector2i] = []
			native_route.assign(packet.route)
			native_local_route_hits += 1
			return native_route
	if not route_policy.is_valid() and combat_enabled and moving_index == -1 and vehicle_operator == 0 and canonical_foot_terrain \
		and (profile == null or profile is FormationMovementProfile):
		var direct := _try_direct_combat_route(start, goal, profile, avoid_occupied_first_step, expansion_limit)
		if not direct.is_empty():
			direct_route_hits += 1
			if route_status is Dictionary: route_status["outcome"] = "direct"
			return direct
	var vehicle_index := index_for_identity(vehicle_operator) if vehicle_operator > 0 and vehicle_transport != null else -1
	var siege_anchor_route: bool = vehicle_index >= 0 and vehicle_transport.is_siege_crew(vehicle_operator)
	var initial_facing := TerrainData.DIRECTIONS.find(vehicle_transport.operator_facing(vehicle_operator)) if vehicle_index >= 0 else -1
	if vehicle_index >= 0 and initial_facing < 0: return empty
	# Only a real operator adds four headings to this same bounded, ephemeral A*.
	var start_state: Variant = start
	if vehicle_index >= 0:
		start_state = Vector3i(start.x, start.y, initial_facing)
	var goal_state: Variant = goal
	var start_node := data.index(start) * 4 + initial_facing if vehicle_index >= 0 else data.index(start)
	var pending: Array[Vector4i] = [Vector4i(start_node, 0, 0 if goal_test.is_valid() else absi(start.x - goal.x) + absi(start.y - goal.y), 0)]
	var sequence := 1
	var previous := {start_state: INVALID_CELL}
	var costs := {start_state: 0}
	var closed := {}
	var head := 0
	var found := false
	var search_limit := maxi(1, floori(float(expansion_limit) / 2.0)) if vehicle_index >= 0 and not anticipate_vehicles else expansion_limit
	var profile_requires_level_step := profile != null and (not bool(profile.get("can_use_ramp")) or int(profile.get("max_step_height")) < 1)
	# Foot routes use the same stored-cell checks as TerrainData.can_step_static.
	# Null-profile infantry has the same canonical terrain rules. Keep dynamic
	# calls for vehicles, custom terrain/profile scripts, and negative limits.
	var fast_foot_route := vehicle_index < 0 and canonical_foot_terrain \
		and (profile == null or profile is FormationMovementProfile and int(profile.get("max_step_height")) >= 0)
	var blocked_first := _current_movement_blocked_destinations() if avoid_occupied_first_step else {}
	var cheap_moving_own_occupancy := combat_enabled and combat_order == CombatOrder.MOVE and moving_index == -1 \
		and fast_foot_route and profile is FormationMovementProfile and allow_occupied and _combat_move_plan != null \
		and _combat_move_plan.phase == CombatMovementTypes.CombatMovePhase.TRANSIT \
		and not _combat_move_plan.macro_path.is_empty() \
		and _combat_move_plan.destination_plan != null and _combat_move_plan.destination_plan == _combat_deployment_plan \
		and _combat_move_plan.destination_plan.approach_bottlenecked == 1 \
		and _combat_move_plan.terrain_revision == data.navigation_revision \
		and _combat_move_plan.order_serial == _combat_move_plan.destination_plan.order_serial
	var grid_width: int = data.size.x
	var grid_height: int = data.size.y
	var terrain_flags: PackedByteArray = data.navigation_flags() if fast_foot_route else PackedByteArray()
	var terrain_heights: PackedByteArray = data.navigation_heights() if fast_foot_route else PackedByteArray()
	var terrain_ramps: PackedByteArray = data.navigation_ramps() if fast_foot_route else PackedByteArray()
	var terrain_blocked: PackedByteArray = data.static_blocked if fast_foot_route else PackedByteArray()
	var has_static_blockers := fast_foot_route and not terrain_blocked.is_empty()
	while not pending.is_empty() and head < search_limit:
		var item := _frontier_pop(pending)
		var cell_index := floori(float(item.x) / 4.0) if vehicle_index >= 0 else item.x
		var current := Vector2i(cell_index % grid_width, floori(float(cell_index) / grid_width))
		var current_state: Variant = current
		if vehicle_index >= 0:
			current_state = Vector3i(current.x, current.y, item.x % 4)
		head += 1
		expanded_nodes += 1
		if closed.has(current_state):
			continue
		var current_cost: int = int(costs[current_state])
		if item.y != current_cost:
			continue
		closed[current_state] = true
		if bool(goal_test.call(current)) if goal_test.is_valid() else current == goal:
			found = true
			goal_state = current_state
			break
		for direction_index in range(TerrainData.DIRECTIONS.size()):
			var direction: Vector2i = TerrainData.DIRECTIONS[direction_index]
			var next := current + direction
			var next_cost := current_cost + 1
			if vehicle_index < 0 and closed.has(next):
				continue
			if next.x < 0 or next.y < 0 or next.x >= grid_width or next.y >= grid_height:
				continue
			var next_index := next.y * grid_width + next.x
			var terrain_step_legal: bool
			if fast_foot_route:
				var height_difference := absi(int(terrain_heights[cell_index]) - int(terrain_heights[next_index]))
				terrain_step_legal = (terrain_flags[cell_index] & TerrainData.Flag.WALKABLE) != 0 \
					and (terrain_flags[next_index] & TerrainData.Flag.WALKABLE) != 0 \
					and (not has_static_blockers or (terrain_blocked[cell_index] == 0 and terrain_blocked[next_index] == 0)) \
					and (terrain_ramps[cell_index] & (1 << (direction_index + 4))) == 0 \
					and (terrain_ramps[next_index] & (1 << (((direction_index + 2) % 4) + 4))) == 0 \
					and (height_difference == 0 or (height_difference == 1 and not profile_requires_level_step \
						and (terrain_ramps[cell_index] & (1 << direction_index)) != 0 \
						and (terrain_ramps[next_index] & (1 << ((direction_index + 2) % 4))) != 0))
			else:
				terrain_step_legal = data.can_step(current, next) if profile == null else data.can_step_static(current, next, profile)
				if terrain_step_legal and profile_requires_level_step:
					terrain_step_legal = data.navigation_heights()[cell_index] == data.navigation_heights()[next_index]
			if not terrain_step_legal:
				continue
			if route_policy.is_valid():
				var extra_cost: Variant = route_policy.call(current, next)
				if not extra_cost is int or int(extra_cost) < 0 or next_cost > 2147483647 - int(extra_cost): continue
				next_cost += int(extra_cost)
			if avoid_occupied_first_step and current == start and (_cell_owners.has(next) or blocked_first.has(next) or _is_external_cell(next, vehicle_operator, current, goal, start)):
				continue
			var next_state: Variant = next
			var next_node := next_index
			if vehicle_index >= 0:
				var planned: Dictionary = vehicle_transport.route_step(self, vehicle_index, current, next, TerrainData.DIRECTIONS[int(current_state.z)], anticipate_vehicles)
				if planned.is_empty() or planned.has("invalid"):
					continue
				var next_facing := TerrainData.DIRECTIONS.find(Vector2i(int(planned.facing[0]), int(planned.facing[1])))
				next_state = Vector3i(next.x, next.y, next_facing)
				next_node = next_index * 4 + next_facing
			if vehicle_index >= 0 and closed.has(next_state):
				continue
			if moving_index > 0 and current == start and not _push_preserves_open_slots(current, next):
				continue
			# Only future vehicle-route nodes may anticipate an able teammate vacating.
			# The route's first step and original reservation/commit stay strict.
			var vacating: bool = anticipate_vehicles and vehicle_index >= 0 and current != start and vehicle_transport.route_vacating_cell(self, next)
			# The same bounded vehicle route already checked the whole anchor-body
			# and all hypothetical crew stations. Its own current body is not an
			# external obstruction to the next anchor; Commit checks real owners.
			var externally_blocked := false if siege_anchor_route else _is_external_cell(next, vehicle_operator if vehicle_operator > 0 else (combat_identity(moving_index) if combat_enabled and moving_index >= 0 else 0), current, goal, start)
			if track_dynamic:
				var dependencies: Dictionary = route_status["dependencies"]
				if dependencies.has(next) or dependencies.size() < FAILED_ROUTE_MAX_DEPENDENCIES:
					dependencies[next] = [externally_blocked, _reserved_cells.get(next, null), _cell_owners.get(next, null)]
				else:
					route_status["dependency_incomplete"] = true
			if externally_blocked and next != goal and not vacating:
				continue
			if not siege_anchor_route and _reserved_cells.has(next) and int(_reserved_cells[next]) != moving_index and not vacating:
				continue
			if not siege_anchor_route and _cell_owners.has(next) and next != goal and not (vehicle_index >= 0 and int(_cell_owners[next]) == vehicle_index) and not vacating:
				var occ_idx: int = _cell_owners[next]
				if occ_idx >= 0 and occ_idx < combat_units.size():
					if cells[occ_idx] == combat_slots[occ_idx]:
						continue
					elif allow_occupied:
						next_cost += 1 if cheap_moving_own_occupancy else 3
					else:
						continue
				elif not allow_occupied:
					continue
			if route_policy.is_valid() and next_cost > 2147483647: continue
			if previous.has(next_state) and int(costs[next_state]) <= next_cost:
				continue
			var heuristic := 0 if goal_test.is_valid() else absi(next.x - goal.x) + absi(next.y - goal.y)
			_frontier_push(pending, Vector4i(next_node, next_cost, heuristic, sequence))
			sequence += 1
			previous[next_state] = current_state
			costs[next_state] = next_cost
			if next == goal: goal_state = next_state
	local_search_expansions += head
	max_local_search_expansions = maxi(max_local_search_expansions, head)
	if not found and (route_policy.is_valid() or not previous.has(goal_state)):
		if not pending.is_empty() and head >= search_limit:
			if route_status is Dictionary:
				route_status["capped"] = true
				route_status["outcome"] = "capped"
			if combat_profile_enabled:
				profiled_search_cap_failures += 1
		elif route_status is Dictionary:
			route_status["outcome"] = "exhausted"
		if vehicle_index >= 0 and not anticipate_vehicles and head < expansion_limit:
			return _find_local_route(start, goal, expansion_limit - head, allow_occupied, moving_index, vehicle_operator, true, profile, avoid_occupied_first_step, route_status, route_policy, goal_test)
		return empty
	if route_status is Dictionary: route_status["outcome"] = "success"
	var route: Array[Vector2i] = []
	var cursor: Variant = goal_state
	while previous.has(cursor):
		route.push_front(Vector2i(cursor.x, cursor.y))
		cursor = previous.get(cursor, INVALID_CELL)
	return route

func _native_local_route(start: Vector2i, goal: Vector2i, limit: int, allow: bool, profile: Object, avoid: bool, track: bool) -> Dictionary:
	var kernel := _native_movement_reader()
	if kernel == null or not kernel.has_method("movement_route"): return {}
	var external_maps := _native_movement_external_maps()
	if external_maps.is_empty(): return {}
	var cheap: bool = combat_order == CombatOrder.MOVE and profile is FormationMovementProfile and allow \
		and _combat_move_plan != null and _combat_move_plan.phase == CombatMovementTypes.CombatMovePhase.TRANSIT \
		and not _combat_move_plan.macro_path.is_empty() and _combat_move_plan.destination_plan != null \
		and _combat_move_plan.destination_plan == _combat_deployment_plan \
		and _combat_move_plan.destination_plan.approach_bottlenecked == 1 \
		and _combat_move_plan.terrain_revision == data.navigation_revision \
		and _combat_move_plan.order_serial == _combat_move_plan.destination_plan.order_serial
	return kernel.movement_route([_native_movement_terrain(profile), start, goal, _cell_owners, _reserved_cells, external_maps,
		_current_movement_blocked_destinations() if avoid else {}, cells, combat_slots, [limit, allow, avoid, cheap, track], true])

func _local_step_toward(start: Vector2i, goal: Vector2i, expansion_limit: int = 256, allow_occupied: bool = false, moving_index: int = -1) -> Vector2i:
	var route := _find_local_route(start, goal, expansion_limit, allow_occupied, moving_index)
	return route[1] if route.size() > 1 else INVALID_CELL

func _clear_follower_route(index: int) -> void:
	_follower_routes.erase(index)
	_follower_route_goals.erase(index)
	_follower_route_cursors.erase(index)
	_follower_route_allows_occupied.erase(index)
	_follower_combat_route_stamps.erase(index)
	_follower_failed_combat_routes.erase(index)

func _common_route_pure_readers() -> bool:
	# Tower access also depends on the original route origin/goal and action
	# state. Cell-only failure dependencies cannot stand in for those facts.
	if vehicle_transport != null and vehicle_transport.has_siege(): return false
	if get_script() != TerrainArmy or data.get_script() != TerrainData \
		or vehicle_transport != null and vehicle_transport.get_script() != SiteVehicleTransport:
		return false
	for actor: Variant in [player, npc]:
		if actor != null and (not actor is TerrainTestCharacter or actor.get_script() not in [TerrainTestCharacter, TerrainTestNPC]):
			return false
	if _shared_movement_blockers_valid():
		return true # Coordinator already admitted this exact callback and all source teams.
	if not external_blocker.is_valid():
		return true
	var external_owner: Object = external_blocker.get_object()
	if external_owner is TerrainArmy and external_owner.get_script() == TerrainArmy and external_owner.data == data:
		return external_blocker.get_method() == &"blocks_cell" and external_blocker.get_bound_arguments_count() == 0 \
			and (external_owner.vehicle_transport == null or external_owner.vehicle_transport.get_script() == SiteVehicleTransport)
	if external_owner is TerrainLab and external_owner.get_script() == TerrainLab and external_owner.terrain == data:
		if external_blocker.get_method() != &"_armies_block_cell" or external_blocker.get_bound_arguments() != [self] \
			or not external_owner.combat_armies.has(self):
			return false
		for team: TerrainArmy in external_owner.combat_armies:
			if not is_instance_valid(team) or team.get_script() != TerrainArmy or team.data != data \
				or team.vehicle_transport != null and team.vehicle_transport.get_script() != SiteVehicleTransport:
				return false
		return true
	return false

func _common_route_failure_unchanged(failed: Dictionary, key: Array) -> bool:
	if failed.get("key", []) != key:
		return false
	var dependencies: Dictionary = failed.get("dependencies", {})
	for cell: Vector2i in dependencies:
		var values: Array = dependencies[cell]
		if _reserved_cells.get(cell, null) != values[1] or _cell_owners.get(cell, null) != values[2] \
			or _is_external_cell(cell) != values[0]:
			return false
	return true

func _common_order_route_step(index: int, goal: Vector2i, operator_id: int) -> Vector2i:
	if _ship_embarked(index): return INVALID_CELL
	# Reuse only successful canonical infantry routes. Original physical commits
	# advance the existing follower cursor; every next edge keeps live checks.
	var reusable: bool = operator_id == 0 and data.get_script() == TerrainData \
		and combat_order in [CombatOrder.RETREAT, CombatOrder.RETURN, CombatOrder.PURSUE]
	var stamp := [get_order_serial(), combat_order, combat_identity(index), data.navigation_revision]
	if reusable and _follower_combat_route_stamps.get(index, []) == stamp:
		var stored: Array = _follower_routes.get(index, [])
		var cursor := int(_follower_route_cursors.get(index, 0))
		if _follower_route_goals.get(index, INVALID_CELL) == goal and cursor >= 1 and cursor < stored.size() \
			and stored[cursor - 1] == cells[index] and stored.back() == goal:
			var next: Vector2i = stored[cursor]
			if data.can_step(cells[index], next) and not blocks_cell(next) and not _is_external_cell(next, combat_identity(index)):
				return next
	# A changed goal/person/order/terrain or a newly blocked edge replans in this
	# same original review. Only a complete, pure infantry failure may be reused.
	if _follower_combat_route_stamps.has(index):
		_clear_follower_route(index)
	var pure_failure: bool = reusable and _common_route_pure_readers()
	var failure_key: Array = [data, external_blocker, vehicle_transport, player, npc, index,
		combat_identity(index), cells[index], goal, get_order_serial(), combat_order, data.navigation_revision, operator_id, 256]
	if pure_failure and _common_route_failure_unchanged(_follower_failed_combat_routes.get(index, {}), failure_key):
		return INVALID_CELL
	var capture_failure: bool = pure_failure and (_follower_failed_combat_routes.has(index)
		or _follower_failed_combat_routes.size() < FAILED_ROUTE_MAX_ENTRIES)
	_follower_failed_combat_routes.erase(index)
	var route_status: Dictionary = {}
	var status_arg: Variant = null
	if capture_failure:
		route_status["track_dynamic"] = true
		status_arg = route_status
	var route := _find_local_route(cells[index], goal, 256, false, -1, operator_id, false, null, false,
		status_arg)
	if route.size() < 2:
		if capture_failure and route_status.get("outcome", "") == "exhausted" \
			and not bool(route_status.get("dependency_incomplete", true)):
			_follower_failed_combat_routes[index] = {"key": failure_key, "dependencies": route_status["dependencies"]}
		return INVALID_CELL
	if reusable:
		_follower_routes[index] = route
		_follower_route_goals[index] = goal
		_follower_route_cursors[index] = 1
		_follower_route_allows_occupied[index] = false
		_follower_combat_route_stamps[index] = stamp
	return route[1]

func _follower_route_step(start: Vector2i, goal: Vector2i, index: int) -> Vector2i:
	if index < 0 or index >= roster_size:
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
	_follower_combat_route_stamps.erase(index)
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
	var start_height := int(data.navigation_heights()[data.index(start)])
	var goal_height := int(data.navigation_heights()[data.index(goal)])
	if start_height == goal_height:
		return goal
	var best := INVALID_CELL
	var best_distance := 1 << 30
	for trail_index: int in range(_captain_trail.size() - 1):
		var trail_cell: Vector2i = _captain_trail[trail_index]
		var next_trail_cell: Vector2i = _captain_trail[trail_index + 1]
		if not data.contains(trail_cell) or not data.contains(next_trail_cell):
			continue
		if int(data.navigation_heights()[data.index(trail_cell)]) != start_height:
			continue
		if int(data.navigation_heights()[data.index(next_trail_cell)]) == start_height:
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
		if _passage_descriptors[passage_index].get("rally_layout", []).size() == roster_size:
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
	if index < 0 or index >= roster_size or _unit_completed_exits.size() != roster_size:
		return false
	var group_end := _passage_group_end if _passage_group_end >= 0 else _passage_descriptors.size() - 1
	return _unit_completed_exits[index] > group_end and _unit_passage_exit_clear[index] != 0

func _publish_passage_group_targets() -> void:
	var layout: Array = _passage_descriptor(_passage_group_end).get("rally_layout", [])
	if layout.size() != roster_size:
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
	for index: int in range(roster_size):
		var ticket := int(_unit_passage_ticket[index])
		var layout_index := 0 if index == 0 else 1 + ticket - int(ticket > _unit_passage_ticket[0])
		desired_cells[index] = layout[layout_index]
		_formation_slot_cells[index] = desired_cells[index]
		_clear_follower_route(index)
	_passage_binding_revision += 1

func _passage_captain_ticket(group_end: int) -> int:
	var descriptor := _passage_descriptor(group_end)
	var layout: Array = descriptor.get("rally_layout", [])
	if layout.size() != roster_size:
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
	if layout.size() != roster_size:
		return
	# Ready tickets need not arrive in numeric order. At this physical admission
	# boundary assign the earliest unused receiving position. The first twenty
	# positions are guards; swap only upstream targets not yet physically used.
	var old_goal := desired_cells[index]
	var bindings := {}
	for other: int in range(1, roster_size):
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
	for index: int in range(1, roster_size):
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
	for ticket_position: int in range(roster_size):
		_unit_passage_ticket[_passage_ticket_order[ticket_position]] = ticket_position
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
	if descriptor.get("rally_layout", []).size() != roster_size:
		return
	for index: int in range(roster_size):
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
		for index: int in range(roster_size):
			_unit_passage[index] = _passage_group_start
			_unit_passage_phase[index] = PassagePhase.APPROACH
			_unit_passage_crossed[index] = 0
			_unit_passage_exit_clear[index] = 0
			_unit_passage_cursor[index] = 0
	_formation_anchor_cell = cells[0]
	_formation_heading = descriptor.get("rally_heading", _formation_heading)
	for index: int in range(roster_size):
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
	if _unit_passage_ticket.size() != roster_size or _unit_passage_ticket[0] < 0:
		return false
	var captain_ticket := int(_unit_passage_ticket[0])
	if unit_index == 0:
		for ticket_position: int in range(captain_ticket):
			var guard_index := _passage_ticket_order[ticket_position]
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
	var ticket := int(_unit_passage_ticket[unit_index]) if _unit_passage_ticket.size() == roster_size else -1
	if ticket < 0:
		return false
	for order_position: int in range(ticket):
		var other := _passage_ticket_order[order_position]
		if other < 0 or other >= roster_size or _unit_passage.size() != roster_size:
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
	if unit_index < 0 or unit_index >= roster_size or _unit_passage.size() != roster_size:
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
	if _passage_active and unit_index >= 0 and unit_index < roster_size \
		and _unit_passage_phase.size() == roster_size:
		var unit_phase := int(_unit_passage_phase[unit_index])
		var unit_passage_index := int(_unit_passage[unit_index])
		if unit_phase == PassagePhase.APPROACH:
			approach_component = _passage_descriptor(unit_passage_index).get("approach_component", {})
			approach_depth_limit = int(approach_component.get(start, 0)) + FORMATION_REFORM_DISTANCE
		final_egress_only = (unit_phase == PassagePhase.EXIT_CLEAR or unit_phase == PassagePhase.RALLY or unit_phase == PassagePhase.EXEMPT) \
			and unit_passage_index >= _passage_group_end
	if _passage_active and unit_index >= 0 and unit_index < roster_size \
		and _unit_passage_phase.size() == roster_size and _unit_passage_phase[unit_index] == PassagePhase.EXIT_CLEAR \
		and int(_unit_passage[unit_index]) < _passage_group_end:
		# Between gates remain on the cleared platform, within the original budget.
		platform_height = int(data.navigation_heights()[data.index(start)])
	var field_expansions := 0
	var rally_component := _active_rally_component()
	if final_egress_only and rally_component.has(start) and rally_component.has(goal):
		# Recover a shortest exit-tree route directly from the shared terrain
		# field. Long ridge detours must not require every exiting unit to search
		# the same thousand cells again. This recovery is charged to this request.
		var reverse_route: Array[Vector2i] = [goal]
		var recovery_cursor := goal
		while recovery_cursor != start and field_expansions < expansion_limit:
			field_expansions += 1
			var depth := int(rally_component[recovery_cursor])
			if depth <= int(rally_component[start]):
				break
			var parent := INVALID_CELL
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var candidate := recovery_cursor + direction
				if rally_component.get(candidate, -2) == depth - 1 and data.can_step(candidate, recovery_cursor) and not blocked.has(candidate):
					parent = candidate
					break
			if parent == INVALID_CELL:
				break
			reverse_route.append(parent)
			recovery_cursor = parent
		if recovery_cursor == start:
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
			if platform_height >= 0 and next != goal and int(data.navigation_heights()[data.index(next)]) != platform_height:
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
	if unit_index < 0 or unit_index >= roster_size or goal == INVALID_CELL:
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
		var shared_index := shared.find(cells[unit_index])
		if shared_index >= 0 and shared_index + 1 < shared.size():
			var shared_next: Vector2i = shared[shared_index + 1]
			if _passage_step_is_free(shared_next, unit_index) or _unit_passage_exit_clear[unit_index] == 0:
				return shared_next
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
				_follower_combat_route_stamps.erase(unit_index)
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
			for other_index: int in range(1, roster_size):
				if other_index != unit_index and desired_cells[other_index] == candidate:
					bound_elsewhere = true
					break
			if not bound_elsewhere and not _cell_owners.has(candidate) and not _reserved_cells.has(candidate) and candidate != cells[0] and not _is_external_cell(candidate):
				desired_cells[unit_index] = candidate
				if _formation_slot_cells.size() == roster_size:
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
		_follower_combat_route_stamps.erase(unit_index)
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
	if unit_index < 0 or unit_index >= roster_size or _unit_passage.size() != roster_size:
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
	if not _passage_active or index < 0 or index >= roster_size or _unit_passage.size() != roster_size:
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
	if not _passage_active or _passage_slot_capacity != roster_size - 1 or not has_army():
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
	for index: int in range(1, roster_size):
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
	if unique_slots.size() != roster_size - 1 or _push_lock[0] != 0:
		return false
	return _pending_pushes.is_empty() and _reserved_cells.is_empty() and not has_active_swap() and not _has_active_follower_swap()

func _repair_passage_slot_binding() -> bool:
	# When every follower has physically reached the published egress component,
	# a remaining identity permutation is a binding problem, not a terrain
	# problem. Re-pair only at an idle transaction boundary and only when every
	# current cell is already one of the 99 immutable final slots. This avoids
	# pushing a settled rank out of its slot merely to satisfy another identity.
	if not _passage_active or _passage_slot_capacity != roster_size - 1 or not has_army() or _formation_bend_active:
		return false
	if _repair_idle_slot_bindings():
		return true
	if moving_count() > 0 or not _pending_pushes.is_empty() or has_active_swap() or _has_active_follower_swap():
		return false
	var occupied_slots := {}
	var all_on_final_slots := true
	for index: int in range(1, roster_size):
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
	for index: int in range(1, roster_size):
		desired_cells[index] = cells[index]
		if _formation_slot_cells.size() == roster_size:
			_formation_slot_cells[index] = cells[index]
		if _unit_passage_phase[index] == PassagePhase.EXIT_CLEAR:
			_unit_passage_phase[index] = PassagePhase.RALLY
			_unit_passage_cursor[index] = -1
			_unit_passage_exit_clear[index] = 1
	_passage_service_owner.fill(-1)
	_follower_combat_route_stamps.clear()
	_follower_failed_combat_routes.clear()
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
	for index: int in range(roster_size):
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
	if first <= 0 or second <= 0 or first >= roster_size or second >= roster_size:
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
	if _unit_passage.size() == roster_size:
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
	# NONE can never satisfy the original completion predicate. Inspect the
	# packed column directly; subclasses retain their overridable predicate.
	if get_script() == TerrainArmy and _unit_passage_phase.count(PassagePhase.NONE) == _unit_passage_phase.size():
		return summary
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
	for side_sign: int in [-1, 1]:
		var previous_from := from
		var previous_to := to
		for offset: int in range(1, scan_radius + 1):
			var lane_from := from + side * side_sign * offset
			var lane_to := to + side * side_sign * offset
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
	for additional_start: Vector2i in additional_starts:
		if not result.has(additional_start) and data.is_walkable(additional_start) and not blocked.has(additional_start):
			result[additional_start] = 0
			pending.append(additional_start)
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
	if component.size() < roster_size:
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
		if compact.size() == roster_size:
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
		if layout.size() != roster_size:
			continue
		if not near_exit or not nearby.is_empty():
			return layout
		var distance := 0
		for slot: Vector2i in layout:
			distance = maxi(distance, int(component[slot]))
		if best.is_empty() or distance + FORMATION_REFORM_DISTANCE < best_distance:
			best = layout
			best_distance = distance
	return compact if compact.size() == roster_size else best

func _compact_rally_layout(component: Dictionary, protected: Dictionary, start: Vector2i, heading: Vector2i, revision: int) -> Array[Vector2i]:
	# A bent terrace can hold a compact connected body without admitting any
	# 100-cell rectangle. Follow its real same-height edges, including corners.
	var slots: Array[Vector2i] = [start]
	var seen := {start: true}
	var head := 0
	var height := int(data.navigation_heights()[data.index(start)])
	while head < slots.size() and slots.size() < roster_size:
		if not await _take_structure_expansion(revision):
			return []
		var current := slots[head]
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if seen.has(next) or not _passage_cell_is_egress_safe(next, component, protected) \
				or data.navigation_heights()[data.index(next)] != height or not data.can_step(current, next):
				continue
			seen[next] = true
			slots.append(next)
			if slots.size() == roster_size:
				break
	if slots.size() != roster_size:
		return []
	var average := Vector2.ZERO
	for slot: Vector2i in slots:
		average += Vector2(slot)
	average /= float(roster_size)
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
	var rows := ceili(float(roster_size) / float(width))
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
		for slot_index: int in range(roster_size):
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
		if slots.size() == roster_size:
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
	var height := int(data.navigation_heights()[data.index(front)])
	var side := Vector2i(-heading.y, heading.x)
	while head < slots.size() and slots.size() < roster_size:
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
				or data.navigation_heights()[data.index(next)] != height or not data.can_step(current, next):
				continue
			seen[next] = true
			slots.append(next)
			if slots.size() == roster_size:
				break
	if slots.size() != roster_size:
		return []
	var average := Vector2.ZERO
	for slot: Vector2i in slots:
		average += Vector2(slot)
	average /= float(roster_size)
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
			and (_unit_passage_phase.count(PassagePhase.APPROACH) == roster_size or _passage_descriptors.is_empty()):
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
		var terminal_height := int(data.navigation_heights()[data.index(terminal_entry)])
		var same_height := true
		for terminal_cell: Vector2i in terminal.corridor:
			if int(data.navigation_heights()[data.index(terminal_cell)]) != terminal_height:
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
					if capacity >= roster_size:
						break
			if capacity >= roster_size:
				terminal_rally_entry = terminal_entry
				segments.pop_back()
	var protected := {}
	for descriptor: Dictionary in segments:
		for cell: Vector2i in descriptor.get("protected", []):
			protected[cell] = true
	for index: int in range(1, roster_size):
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
		var approach_distances: Dictionary = segments.back().approach_component
		var safe_component := {}
		for candidate: Vector2i in component:
			if not await _take_structure_expansion(revision):
				return
			if not approach_distances.has(candidate) or int(component[candidate]) < int(approach_distances[candidate]):
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
	if available_capacity >= roster_size:
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
					if final_layout.size() == roster_size or revision != _structure_revision:
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
		if passage_index == segments.size() - 1 and pocket.size() == roster_size and final_layout.size() == roster_size:
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
	if final_layout.size() == roster_size:
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
	_passage_final_captain_slot = final_layout[0] if final_layout.size() == roster_size else INVALID_CELL
	desired_cells[0] = _passage_final_captain_slot
	# A compact front can have its tip off the captain's centre line. Preserve
	# the command's exact front goal; choosing another middle front cell here
	# would silently move a stationary FOLLOW/EDGE destination after planning.
	_passage_slot_capacity = _passage_final_slots.size()
	_passage_available_capacity = available_capacity
	_passage_failure_reason = ""
	if available_capacity < roster_size:
		_passage_failure_reason = "INSUFFICIENT_RALLY_CAPACITY"
	elif _passage_slot_capacity != roster_size - 1:
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
	for index: int in range(1, roster_size):
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
	_formation_slot_cells.resize(roster_size)
	_formation_slot_cells[0] = desired_cells[0]
	for index: int in range(roster_size):
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
	_exit_rally_assigned = _passage_slot_capacity == roster_size - 1
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
	if not has_army() or partner_index <= 0 or partner_index >= roster_size:
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
			for unit: int in range(roster_size):
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
	_mark_visual_row(0)
	_mark_visual_row(partner_index)
	_audio_begin_step(0, captain_cell, partner_cell, false)
	_audio_begin_step(partner_index, partner_cell, captain_cell, false)
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
		if reservation_owner >= 0 and reservation_owner < roster_size:
			if (movement_state[reservation_owner] == UnitState.MOVING or movement_state[reservation_owner] == UnitState.SWAPPING) and moving_to[reservation_owner] == cell:
				live = true
		if not live:
			stale.append(cell)
	for cell: Vector2i in stale:
		_reserved_cells.erase(cell)

func _has_active_follower_swap() -> bool:
	return _follower_swap_a > 0 and _follower_swap_b > 0

func _can_follower_swap(first: int, second: int) -> bool:
	if (formation_mode != FormationMode.COLUMN and formation_mode != FormationMode.OPEN) or first <= 0 or second <= 0 or first >= roster_size or second >= roster_size or first == second:
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
	move_curve[first] = 0
	move_duration[second] = MOVE_DURATION
	move_curve[second] = 0
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
	_mark_visual_row(first)
	_mark_visual_row(second)
	_audio_begin_step(first, first_cell, second_cell, false)
	_audio_begin_step(second, second_cell, first_cell, false)
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
	var audio_first := _audio_take_step(first, first_cell, second_cell, maxf(MOVE_DURATION, move_duration[first]))
	var audio_second := _audio_take_step(second, second_cell, first_cell, maxf(MOVE_DURATION, move_duration[first]))
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
		move_curve[index] = 0
		locomotion_mode[index] = Locomotion.IDLE
		blocked_time[index] = 0.0
		movement_state[index] = UnitState.ARRIVED if cells[index] == desired_cells[index] else UnitState.IDLE
	_follower_swap_a = -1
	_follower_swap_b = -1
	_swap_count += 1
	_completed_steps += 2
	_mark_visual_row(first)
	_mark_visual_row(second)
	_audio_emit_step(audio_first)
	_audio_emit_step(audio_second)

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
	var audio_duration := maxf(MOVE_DURATION, move_duration[0])
	var audio_captain := _audio_take_step(0, captain_cell, partner_cell, audio_duration)
	var audio_partner := _audio_take_step(partner_index, partner_cell, captain_cell, audio_duration)
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
		move_curve[index] = 0
		locomotion_mode[index] = Locomotion.IDLE
		blocked_time[index] = 0.0
		movement_state[index] = UnitState.IDLE
		if cells[index] == desired_cells[index] and command == Command.MOVE_TO_EDGE:
			movement_state[index] = UnitState.ARRIVED
	_swap_count += 1
	_completed_steps += 2
	_mark_visual_row(0)
	_mark_visual_row(partner_index)
	_audio_emit_step(audio_captain)
	_audio_emit_step(audio_partner)

func _unit_should_run(index: int, next: Vector2i = INVALID_CELL) -> bool:
	if index < 0 or index >= roster_size or desired_cells.size() != roster_size:
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
		and data.navigation_heights()[data.index(cells[index])] == data.navigation_heights()[data.index(next)] \
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

func _find_yield_cell(index: int, toward_other: Vector2i = Vector2i.ZERO, reservation_grid: Object = null, deployment_registry: Object = null) -> Vector2i:
	if index < 0 or index >= cells.size():
		return INVALID_CELL
	var directions: Array[Vector2i] = []
	if toward_other == Vector2i.ZERO:
		directions.assign(TerrainData.DIRECTIONS)
	elif toward_other in TerrainData.DIRECTIONS:
		directions.assign([Vector2i(-toward_other.y, toward_other.x), Vector2i(toward_other.y, -toward_other.x)])
	else:
		return INVALID_CELL
	for direction: Vector2i in directions:
		var candidate := cells[index] + direction
		if not FormationTransitPlanner._can_profile_step(data, cells[index], candidate, _formation_movement_profile) or _is_external_cell(candidate):
			continue
		if _cell_owners.has(candidate) or _reserved_cells.has(candidate):
			continue
		if reservation_grid != null and (reservation_grid.initial_occupancy.has(candidate) or reservation_grid.blocked_destinations.has(candidate)):
			continue
		if deployment_registry != null and deployment_registry.is_slot_reserved(candidate, team_id):
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
	if index < 0 or index >= roster_size or _unit_passage_phase.size() != roster_size:
		return false
	if _unit_completed_exits.size() != roster_size or _unit_completed_exits[index] != _passage_descriptors.size():
		return false
	return _unit_passage_phase[index] == PassagePhase.RALLY or _unit_passage_phase[index] == PassagePhase.EXEMPT \
		or (_unit_passage_phase[index] == PassagePhase.EXIT_CLEAR and _unit_passage[index] == _passage_descriptors.size() - 1 and _unit_passage_exit_clear[index] != 0)

func _passage_unit_may_be_pushed(index: int, destination: Vector2i, requester: int = -1) -> bool:
	if not _passage_active or index < 0 or index >= roster_size or _unit_passage_phase.size() != roster_size:
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
		var rally_requester := requester >= 0 and requester < roster_size \
			and _unit_has_cleared_group(requester) \
			and _rally_requester_may_displace(requester)
		return requester >= 0 and requester < roster_size \
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
	if requester < 0 or requester >= roster_size or _unit_passage_phase.size() != roster_size:
		return false
	if not _unit_has_cleared_group(requester) or cells[requester] == desired_cells[requester]:
		return false
	# Ordinary idle occupants can exchange bindings, but the captain's centre
	# is fixed. If displaced onto another slot, he must physically fill the
	# remaining centre vacancy through the same bounded push transaction.
	return _active_rally_component().has(cells[requester]) \
		and (requester == 0 or not _active_rally_slots().has(cells[requester]))

func _schedule_push_unit(index: int, destination: Vector2i, requester: int = -1) -> bool:
	if index < 0 or (index == 0 and not _passage_active) or index >= roster_size or movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING:
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
	var passage_exit_displacement := _passage_active and requester >= 0 and requester < roster_size \
		and _unit_passage_phase.size() == roster_size and _unit_passage_phase[requester] == PassagePhase.EXIT_CLEAR
	if _exit_rally_assigned and captain_at_boundary() and _exit_rally_slots.has(source) and not _exit_rally_slots.has(destination) and not passage_exit_displacement:
		return false
	if _is_external_cell(destination) or _cell_owners.has(destination) or (_reserved_cells.has(destination) and int(_reserved_cells[destination]) != index):
		return false
	_reserved_cells[destination] = index
	moving_to[index] = destination
	move_progress[index] = 0.0
	move_duration[index] = MOVE_DURATION
	move_curve[index] = 0
	locomotion_mode[index] = Locomotion.WALK
	blocked_time[index] = 0.0
	movement_state[index] = UnitState.MOVING
	facing[index] = destination - source
	_mark_visual_row(index)
	_audio_begin_step(index, source, destination, false)
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
		if unit < 0 or unit >= roster_size:
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
	if requester < 0 or requester >= roster_size or _push_lock[requester] == 0:
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
	if requester >= roster_size or movement_state.size() != roster_size or _push_lock.size() != roster_size:
		return false
	if movement_state[requester] == UnitState.MOVING or movement_state[requester] == UnitState.SWAPPING:
		return false
	if _passage_active and _unit_passage_phase.size() == roster_size:
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
			var unit_owner := int(units[path_index])
			if committed.has(unit_owner):
				continue
			var destination: Vector2i = pending_path[path_index + 1]
			if unit_owner < 0 or unit_owner >= roster_size:
				continue
			var in_flight := movement_state[unit_owner] == UnitState.MOVING or movement_state[unit_owner] == UnitState.SWAPPING
			if not in_flight or moving_to[unit_owner] != destination:
				_clear_reservation(destination, unit_owner)
	for unit_value: Variant in units:
		var unit := int(unit_value)
		if committed.has(unit):
			continue
		if unit < 0 or unit >= roster_size:
			continue
		if unit < _push_lock.size():
			_push_lock[unit] = 0
	var requester := int(pending.get("requester", -1))
	if requester >= 0 and requester < roster_size and not pending_path.is_empty():
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
	if requester < 0 or index < 0 or ((requester == 0 or index == 0) and not _passage_active) or index >= roster_size:
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
		return (a - _push_search_cursor + roster_size - 1) % maxi(1, roster_size - 1) < (b - _push_search_cursor + roster_size - 1) % maxi(1, roster_size - 1))
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
		_push_search_cursor = requester % maxi(1, roster_size - 1) + 1
		var path: Array[Vector2i] = []
		path.assign(result.get("path", []))
		push_search_queued += int(_queue_push_chain(requester, path))
	_push_search_ready.clear()

func _unit_is_before_bottleneck(index: int) -> bool:
	if not captain_at_boundary() or data == null or index <= 0 or index >= roster_size or not data.contains(cells[index]) or not data.contains(cells[0]):
		return false
	var captain_height := int(data.navigation_heights()[data.index(cells[0])])
	return int(data.navigation_heights()[data.index(cells[index])]) != captain_height

func _formation_planning_order(_heading: Vector2i) -> Array[int]:
	# One service cursor for every expensive follower route. Direct intents
	# still visit all 100 units; tickets separately arbitrate passage admission.
	var order: Array[int] = [0]
	for offset: int in range(roster_size - 1):
		order.append(1 + ((_local_path_cursor - 1 + offset) % maxi(1, roster_size - 1)))
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
		move_progress[0] = CombatTimings.advance_movement_progress(move_progress[0], delta, maxf(MOVE_DURATION, move_duration[0]))
		var partner_index := swap_partner[0]
		move_progress[partner_index] = move_progress[0]
		if move_progress[0] >= 1.0:
			_complete_swap()
	if _has_active_follower_swap():
		move_progress[_follower_swap_a] = CombatTimings.advance_movement_progress(move_progress[_follower_swap_a], delta, maxf(MOVE_DURATION, move_duration[_follower_swap_a]))
		move_progress[_follower_swap_b] = move_progress[_follower_swap_a]
		if move_progress[_follower_swap_a] >= 1.0:
			_complete_follower_swap()
	if _formation_step_direction != Vector2i.ZERO:
		var progress := CombatTimings.advance_movement_progress(move_progress[_formation_step_units[0]], delta, MOVE_DURATION)
		for index: int in _formation_step_units:
			move_progress[index] = progress
		if progress >= 1.0:
			_complete_formation_step()
	else:
		for index: int in range(roster_size):
			if movement_state[index] != UnitState.MOVING:
				continue
			move_progress[index] = CombatTimings.advance_movement_progress(move_progress[index], delta, maxf(0.001, move_duration[index]))
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
	if captain_follow_goal and formation_mode == FormationMode.OPEN and not _formation_has_bottleneck and formation_count_value < roster_size - 1:
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
		and formation_count_value < roster_size - 1:
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
	if command == Command.MOVE_TO_EDGE and captain_at_boundary() and _formation_has_bottleneck and formation_count_value == roster_size - 1 and _formation_all_settled():
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
		and formation_count_value < roster_size - 1 and _open_slot_set_is_occupied()
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
			if _passage_active and _unit_passage_phase.size() == roster_size:
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
		move_curve[index] = 0
		blocked_time[index] = 0.0
		movement_state[index] = UnitState.MOVING
		facing[index] = next - cells[index]
		_mark_visual_row(index)
		_audio_begin_step(index, cells[index], next, should_run)
	_service_push_search()
	_planning_cursor = (_planning_cursor + 1) % maxi(1, roster_size - 1)
	_update_formation_status()
	if captain_follow_goal and formation_count_value < roster_size - 1 and _formation_rebind_elapsed >= BLOCKED_REPORT:
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
	if _formation_step_units.has(index) or _combat_batch_members.has(combat_identity(index)):
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
	_finish_move_state(index, old_cell, next)

func _finish_move_state(index: int, old_cell: Vector2i, next: Vector2i, consume_routes: bool = true) -> void:
	var audio_candidate := _audio_take_step(index, old_cell, next, move_duration[index])
	if combat_enabled and (float(combat_hot_get(index, &"hp")) <= 0.0 or float(combat_hot_get(index, &"ko")) > 0.0):
		_cell_owners.erase(next)
	moving_to[index] = INVALID_CELL
	if vehicle_transport != null:
		vehicle_transport.complete_step(self, index)
	move_progress[index] = 0.0
	move_duration[index] = MOVE_DURATION
	move_curve[index] = 0
	locomotion_mode[index] = Locomotion.IDLE
	if combat_enabled:
		_command_dirty = true
		if str(combat_hot_get(index, &"pose")) in ["walk", "run"]:
			combat_hot_set(index, &"pose", "idle")
			combat_hot_set(index, &"age", 0.0)
	blocked_time[index] = 0.0
	movement_state[index] = UnitState.IDLE
	if consume_routes:
		_record_passage_commit(index, old_cell, next)
		_consume_path_route_step(index, next)
		_consume_follower_route_step(index, next)
	if index == 0:
		if _captain_trail.is_empty() or _captain_trail.back() != next:
			_captain_trail.append(next)
			_captain_trail_progress_cache.clear()
	_completed_steps += 1
	_mark_visual_row(index)
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
	_audio_emit_step(audio_candidate)

func _rebuild_visual_instances() -> void:
	if (_captain_editor == null and not defer_captain_presenter) or not _soldier_baked_ready:
		initialize_visual()
	# The simulation is deliberately independent of render targets.
	_ensure_live_presenters()
	if not _soldier_baked_ready and _soldier_editor == null:
		return
	if _batch_view != null:
		_batch_view.release_sprites()
		_batch_view.queue_free()
		_batch_view = null
	if _batch_render_active():
		_batch_view = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd").new()
		add_child(_batch_view)
		_batch_view.setup(self, roster_size)
		_batch_view.retained_enabled = combat_hot_active()
		_batch_view.begin()
	if _sprites.size() != roster_size:
		for sprite: Sprite2D in _sprites:
			if sprite != null: sprite.queue_free()
		_sprites.clear()
		for index: int in range(roster_size):
			_sprites.append(null if _batch_render_active() and not _renders_live_presenter(index) else _new_person_sprite(index))
	_soldier_animation_time.resize(roster_size)
	_soldier_current_keys.resize(roster_size)
	_soldier_sprite_anchors.resize(roster_size)
	for index: int in range(roster_size):
		if _sprites[index] == null and not _batch_render_active():
			_sprites[index] = _new_person_sprite(index)
		if _hide_journey_person(index): continue
		var sprite := _sprites[index]
		if _batch_render_active() and not _renders_live_presenter(index):
			_set_soldier_frame(index, true)
			continue
		sprite.modulate = Color.WHITE # Faction identity uses equipment dyes and the existing team markers.
		if _renders_live_presenter(index):
			var captain_source: Variant = _unit_editor(index)
			if captain_source == null:
				continue
			sprite.texture = captain_source.preview_viewport.get_texture()
			var captain_scale: float = captain_source.get_map_sprite_scale()
			sprite.scale = Vector2.ONE * captain_scale
			_captain_anchor = captain_source.get_map_ground_offset_pixels() * captain_scale
			_live_anchors[combat_identity(index)] = _captain_anchor
		else:
			if _soldier_baked_ready:
				sprite.scale = Vector2.ONE * _soldier_map_scale
				_set_soldier_frame(index, true)
			else:
				var soldier_source: Variant = _soldier_editor
				sprite.texture = soldier_source.preview_viewport.get_texture()
				var soldier_scale: float = soldier_source.get_map_sprite_scale()
				sprite.scale = Vector2.ONE * soldier_scale
				_soldier_anchor = soldier_source.get_map_ground_offset_pixels() * soldier_scale
	if _batch_view != null:
		for index in range(_sprites.size()):
			if not _ship_in_journey(index) and _sprites[index] != null: _batch_view.submit_sprite(index, _sprite_sort_ground(index), _sprites[index])
		_batch_view.flush()
		_visual_full_dirty = false
		_visual_row_dirty.clear()
	_sync_visual_positions()

func _sync_visual_positions() -> void:
	if _sprites.size() != roster_size:
		return
	if not _visual_dirty and moving_count() == 0:
		return
	for index: int in range(roster_size):
		if _hide_journey_person(index): continue
		var sprite := _sprites[index]
		if sprite == null: continue # This original person is drawn by the batch view.
		sprite.self_modulate = SiteCombatRules.fire_body_tint(fire_body_visual_code(index))
		if combat_enabled and (bool(combat_hot_get(index, &"site_exited", false)) or bool(combat_units[index].get("ship_death_settled", false))):
			sprite.visible = false
			continue
		if sprite.has_meta("vehicle_rider_frame"):
			sprite.position = Vector2(sprite.get_meta("vehicle_rider_ground")) - Vector2(sprite.get_meta("vehicle_rider_anchor")) + data.surface_visual_offset_at(_sprite_sort_ground(index))
			sprite.z_index = 10 + int(_sprite_sort_ground(index).y / TerrainRenderer.CELL_PIXELS)
			sprite.visible = true
			continue
		var progress := clampf(move_progress[index], 0.0, 1.0)
		if movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING:
			# Render the fractional remainder between fixed simulation ticks so
			# movement does not appear to advance in 10 Hz steps.
			progress = clampf(progress + _sim_accumulator / maxf(0.001, move_duration[index]), 0.0, 1.0)
		var map_position := (Vector2(cells[index]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		if movement_state[index] == UnitState.MOVING or movement_state[index] == UnitState.SWAPPING:
			var destination := (Vector2(moving_to[index]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			map_position = map_position.lerp(destination, CombatTimings.movement_weight(progress, move_curve[index] == 1))
		var anchor := _unit_anchor(index)
		if combat_enabled:
			map_position = combat_visual_ground(index) + combat_offset(index)
		sprite.position = map_position - anchor + data.surface_visual_offset_at(map_position)
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

func _advance_retained_combat_frame() -> bool:
	if _has_ship_presentation_state(): return false
	if _batch_view == null or _visual_full_dirty or not native_render_enabled or not _batch_render_active() or not combat_hot_active() \
			or not _combat_hot_store.has_method("retained_idle_mask") or not _batch_view.has_method("retained_source_duration") \
			or get_script() != TerrainArmy or _combat_hot_borrowed_index >= 0 \
			or _combat_hot_store.get_class() != "ArmyCombatHot" or _combat_hot_store.get_script() != null \
			or _batch_view.get_script() != preload("res://scripts/terrain_lab/terrain_army_batch_view.gd"):
		return false
	var ages: PackedFloat64Array = combat_hot_column(&"age")
	var exited: PackedFloat64Array = combat_hot_column(&"site_exited")
	var eligible: PackedByteArray = _combat_hot_store.retained_idle_mask()
	if exited.size() != _sprites.size(): return false
	if ages.size() != _sprites.size() or eligible.size() != _sprites.size() or not _batch_view.begin_retained():
		return false
	for index in range(_sprites.size()):
		if exited[index] != 0.0:
			eligible[index] = 0
			continue
		if eligible[index] != 0 or moving_to[index] != INVALID_CELL or _visual_row_dirty.has(index) \
				or _sprites[index] != null or _renders_live_presenter(index):
			continue
		var authored_duration := float(_batch_view.retained_source_duration(index))
		if authored_duration < 0.0: continue
		# The sequence/ground/descriptor were retained from the last exact submit.
		# Only the original exchange clock may have changed; pose, facing,
		# equipment, and movement invalidate that source through their dirty path.
		var sample := _exchange_animation_time(index, authored_duration)
		if not is_finite(sample) or sample < 0.0: continue
		ages[index] = sample
		eligible[index] = 1
	if _batch_view.sample_retained_animations(ages, eligible, exited) < 0:
		return false # The full path below resets the interrupted retained frame.
	for index in range(_sprites.size()):
		if exited[index] != 0.0:
			continue
		if eligible[index] != 0 and moving_to[index] == INVALID_CELL and not _visual_row_dirty.has(index) and _sprites[index] != null and _renders_live_presenter(index):
			# The live source still advances its animation, while its retained
			# sprite descriptor and ground have not changed on this Army tick.
			_sync_captain_combat(combat_frame(index), index)
			continue
		if eligible[index] != 0 and moving_to[index] == INVALID_CELL and _sprites[index] == null and not _visual_row_dirty.has(index):
			continue
		if _renders_live_presenter(index):
			_sync_captain_combat(combat_frame(index), index)
		else:
			_set_soldier_frame(index)
		if _sprites[index] != null:
			_batch_view.submit_sprite(index, _sprite_sort_ground(index), _sprites[index])
	_batch_view.flush_retained()
	_visual_row_dirty.clear()
	return true

func advance_frame(delta: float) -> void:
	_invalidate_ship_projection()
	if not has_army():
		return
	_refresh_siege_work_visual_rows()
	var frame_start_usec := Time.get_ticks_usec()
	if combat_enabled:
		var profile_started := frame_start_usec
		var update_batch := _batch_view != null and _visual_dirty
		if _batch_view != null:
			_batch_view.retained_enabled = combat_hot_active()
		if update_batch and not _batch_view.use_native_crowd() and _advance_retained_combat_frame():
			profile_started = _profile_combat_stage("render_submit", profile_started)
			profile_started = _profile_combat_stage("render_flush", profile_started)
			_sync_visual_positions()
			_profile_combat_stage("render_positions", profile_started)
			last_frame_cpu_usec = Time.get_ticks_usec() - frame_start_usec
			combat_render_usec += last_frame_cpu_usec
			return
		if update_batch: _batch_view.begin()
		if update_batch and native_render_enabled and _batch_render_active() and not _has_ship_presentation_state(): _batch_view.prepare_idle()
		var prepared_idle: bool = update_batch and not _batch_view._native_mask.is_empty()
		var grouped: bool = prepared_idle and get_script() == TerrainArmy and _batch_view.get_script() == preload("res://scripts/terrain_lab/terrain_army_batch_view.gd") and _batch_view.can_group_prepared()
		var indices: Variant = [] if exchange_enabled and not _visual_dirty else (_batch_view.prepared_exceptions() if grouped else range(_sprites.size()))
		for index: int in indices:
			if _hide_journey_person(index): continue
			if exchange_enabled and not _visual_dirty:
				continue
			if bool(combat_hot_get(index, &"site_exited", false)) or bool(combat_units[index].get("ship_death_settled", false)):
				continue
			if prepared_idle and not grouped and _batch_view.submit_prepared(index):
				continue
			if _renders_live_presenter(index):
				_sync_captain_combat(combat_frame(index), index)
			elif not exchange_enabled or _visual_dirty:
				_set_soldier_frame(index)
			if update_batch and _sprites[index] != null:
				_batch_view.submit_sprite(index, _sprite_sort_ground(index), _sprites[index])
		if grouped: _batch_view.finish_prepared_groups()
		profile_started = _profile_combat_stage("render_submit", profile_started)
		if update_batch:
			_batch_view.flush()
			_visual_full_dirty = false
			_visual_row_dirty.clear()
		profile_started = _profile_combat_stage("render_flush", profile_started)
		_sync_visual_positions()
		_profile_combat_stage("render_positions", profile_started)
		last_frame_cpu_usec = Time.get_ticks_usec() - frame_start_usec
		combat_render_usec += last_frame_cpu_usec
		return # All combat/movement time comes from TerrainLab's action step.
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
	for editor: Variant in _all_visual_sources():
		if editor == null:
			continue
		if editor.preview_viewport != null:
			editor.preview_viewport.queue_free()
		editor.queue_free()


# The original stable person row owns dose/status. Hot HP still uses its owner.
func fire_body_receive_contact(index: int, payload: Dictionary) -> bool:
	if index < 0 or index >= combat_units.size() or float(combat_hot_get(index, &"hp")) <= 0.0: return false
	if not combat_units[index].has("fire_body"): combat_units[index]["fire_body"] = {}
	return SiteCombatRules.fire_body_receive_contact(combat_units[index].fire_body, payload)

func advance_fire_exposure(index: int, sequence: int, action_begin: float, action_end: float, segments: Array[Dictionary]) -> Dictionary:
	if index < 0 or index >= combat_units.size() or float(combat_hot_get(index, &"hp")) <= 0.0: return {"ok": true, "active": false}
	if not combat_units[index].has("fire_body"): combat_units[index]["fire_body"] = {}
	var visual_before := fire_body_visual_code(index)
	var hp_before := float(combat_hot_get(index, &"hp"))
	var protection := 1.0 / (1.0 + SiteCombatRules.armor_level(str(ranged_defense(index).armor)))
	var result := SiteCombatRules.fire_body_advance(combat_units[index].fire_body, sequence, action_begin, action_end, segments, protection)
	if bool(result.ok) and not bool(result.get("duplicate", false)):
		if float(result.get("hp", 0.0)) > 0.0: apply_unit_contact(index, SiteCombatRules.fire_environment_packet(float(result.hp)))
		var body: Dictionary = combat_units[index].fire_body
		body["last_interval_fire_hp"] = hp_before - float(combat_hot_get(index, &"hp"))
		body["last_interval_fire_death"] = hp_before > 0.0 and float(combat_hot_get(index, &"hp")) <= 0.0
		result["applied_hp"] = float(body.last_interval_fire_hp)
		result["fire_death"] = bool(body.last_interval_fire_death)
		if fire_body_visual_code(index) != visual_before: _mark_visual_row(index)
	return result

func fire_body_visual_code(index: int) -> int:
	if index < 0 or index >= combat_units.size() or float(combat_hot_get(index, &"hp")) <= 0.0: return 0
	return SiteCombatRules.fire_body_visual_code(combat_units[index].get("fire_body", {}))

# P3 M1 original Army navigation only. PersonActions owns the job, time and supply.
# This is one transient local approach/cache, never another body, command or grid.







func _suppress_cell_safe(cell: Vector2i) -> bool:
	if data == null or not data.is_walkable(cell): return false
	var profile: Dictionary = SiteCombatRules.fire_suppression_profile()
	return SiteRuntime.fire_hazard_at(data, cell, "ground") <= float(profile.slot_risk_max)

func _suppress_step_allowed(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	return _suppress_cell_safe(from_cell) and _suppress_cell_safe(to_cell) \
		and not _coordinator.deployment_registry.is_slot_reserved(to_cell, team_id)

func _suppress_route_extra_cost(from_cell: Vector2i, to_cell: Vector2i) -> int:
	# Same optional original A* policy contract as future NORMAL/EMERGENCY:
	# nonnegative added integer cost, or -1 when this policy forbids an edge.
	return 0 if _suppress_step_allowed(from_cell, to_cell) else -1





func is_suppress_committed_move(member_id: int) -> bool:
	# This provenance lives in the existing original batch owner. It survives a
	# new command or cancellation until that already-committed physical edge ends.
	return _committed_intent_order(member_id) == CombatOrder.HOLD


const FIRE_HAZARD_STEP := -2
var _fire_navigation: Dictionary = {}
var _fire_navigation_epoch := 0
var _fire_threat_last_end := -1.0
signal fire_threat_summary_changed(summary: Dictionary)

func _fire_nav_now(snapshot: Dictionary) -> float:
	return float(data.get_meta(&"fire_completed_action_end", snapshot.get("completed_action_end", 0.0)))

func _fire_nav_risk(cell: Vector2i, snapshot: Dictionary = {}) -> float:
	if data == null or not data.contains(cell): return INF
	var view: Dictionary = _fire_navigation.get("snapshot", {}) if snapshot.is_empty() else snapshot
	if view.is_empty(): return 0.0
	return SiteRuntime.fire_path_hazard_at(view, cell, float(data.effective_height(cell)) + 0.5)

func _fire_nav_band(cell: Vector2i, snapshot: Dictionary = {}) -> int:
	return SiteCombatRules.fire_risk_band(_fire_nav_risk(cell, snapshot))

func _fire_nav_safe(cell: Vector2i) -> bool:
	return data != null and data.contains(cell) and data.is_walkable(cell) \
		and _fire_nav_band(cell) <= int(SiteCombatRules.fire_navigation_profile().normal_max_band)

func _fire_nav_intersects(snapshot: Dictionary) -> bool:
	if snapshot.get("cells", {}).is_empty(): return false
	for index in range(cells.size()):
		if not is_member(index) or not combat_can_act(index): continue
		if _fire_nav_band(cells[index], snapshot) > 0 or moving_to[index] != INVALID_CELL and _fire_nav_band(moving_to[index], snapshot) > 0: return true
		if index < combat_slots.size() and combat_slots[index] != INVALID_CELL and _fire_nav_band(combat_slots[index], snapshot) > 0: return true
	if _combat_deployment_plan != null:
		for slot: Vector2i in _combat_deployment_plan.member_slot_map.values():
			if _fire_nav_band(slot, snapshot) > 0: return true
	if _combat_move_plan != null:
		for cell: Vector2i in _combat_move_plan.macro_path:
			if _fire_nav_band(cell, snapshot) > 0: return true
	return false

func has_pending_fire_navigation() -> bool:
	if data == null or not combat_enabled or not exchange_enabled or _coordinator == null or not garrison_feature_id.is_empty() or has_ship_journey(): return false
	return not _fire_navigation.is_empty() or _fire_nav_intersects(SiteRuntime.fire_hazard_snapshot(data))

func _fire_nav_context_current() -> bool:
	return not _fire_navigation.is_empty() and is_same(data, _fire_navigation.terrain) \
		and is_same(data.site, _fire_navigation.site) and get_order_serial() == int(_fire_navigation.serial) \
		and ranged_order_serial == int(_fire_navigation.ranged_serial) and combat_order == int(_fire_navigation.order) \
		and is_same(_combat_move_plan, _fire_navigation.move_plan) and is_same(_combat_deployment_plan, _fire_navigation.deployment) \
		and _coordinator != null and is_same(_coordinator.deployment_registry, _fire_navigation.registry)

func _fire_nav_reset() -> void:
	if _fire_navigation.is_empty(): return
	# A later manual command may already have replaced every lease. Exact
	# reference checks prevent this old intent from touching that new command.
	var registry: Object = _fire_navigation.registry
	for mid: int in _fire_navigation.leases:
		var lease: Variant = _fire_navigation.leases[mid]
		var retained_by_plan: bool = _fire_nav_context_current() and _combat_deployment_plan != null \
			and _combat_deployment_plan.member_slot_map.get(mid, INVALID_CELL) == lease.cell
		if retained_by_plan: continue
		if lease != null and is_same(registry.owner_of(lease.cell), lease):
			registry.release_slots(lease.formation_id, lease.order_serial, [lease.cell])
	_fire_navigation.clear()

func _fire_nav_start(snapshot: Dictionary) -> void:
	_fire_navigation_epoch += 1
	_fire_navigation = {"terrain": data, "site": data.site, "serial": get_order_serial(),
		"ranged_serial": ranged_order_serial, "order": combat_order, "move_plan": _combat_move_plan,
		"deployment": _combat_deployment_plan, "registry": _coordinator.deployment_registry,
		"epoch": _fire_navigation_epoch, "snapshot": snapshot, "revision": -1,
		"navigation": data.navigation_revision, "assignment": -1, "last_replan": -INF,
		"cool_since": -1.0, "members": {}, "leases": {}, "unsafe": {}, "metrics": {}, "capacity": {},
		"replans": 0, "last_summary": {}, "status": "AVOIDING"}

func _fire_nav_suspend_unsafe() -> bool:
	var state := _fire_navigation
	var registry: SiteDeploymentReservationRegistry = state.registry
	var unsafe: Array[Vector2i] = []
	var expected: Array = []
	if _combat_deployment_plan != null:
		for slot: Vector2i in _combat_deployment_plan.member_slot_map.values():
			if not _fire_nav_safe(slot) and not unsafe.has(slot): unsafe.append(slot)
		for slot: Vector2i in _combat_deployment_plan.slot_lease_owner_map:
			if not _fire_nav_safe(slot) and not unsafe.has(slot): unsafe.append(slot)
	for lease: Variant in state.leases.values():
		if lease != null and is_same(registry.owner_of(lease.cell), lease) and not _fire_nav_safe(lease.cell) and not unsafe.has(lease.cell): unsafe.append(lease.cell)
	for slot: Vector2i in unsafe:
		state.unsafe[slot] = true
		var lease: Variant = registry.owner_of(slot)
		if lease != null and lease.formation_id == team_id and lease.order_serial == get_order_serial(): expected.append(lease)
	# Suspend before the special release/replace transaction; failure cannot
	# restore unsafe slots. Physical cells and committed claims are untouched.
	if _combat_deployment_plan != null:
		var affected := _combat_deployment_plan.fire_suspend_slots(unsafe)
		if _combat_move_plan != null:
			for mid: int in affected: _combat_move_plan.invalidate_member_route(mid)
	var released := registry.release_fire_unsafe_leases(team_id, get_order_serial(), expected)
	if not released.ok: state.status = "STALE_UNSAFE_LEASE"
	return not unsafe.is_empty()

func _fire_nav_capacity_replan() -> void:
	if _combat_deployment_plan == null: return
	var state := _fire_navigation
	var original_cells := get_active_members_occupancy()
	var protected: Array[Vector2i] = [] # Typed per branch, as above.
	if _combat_move_plan != null: protected = _combat_move_plan.macro_path
	var preview := FormationDestinationPlanner.fire_replacements(_combat_deployment_plan, data, state.registry,
		original_cells, _fire_nav_safe, protected)
	state.capacity = preview.capacity
	_combat_deployment_plan.fire_safe_platform_capacity = int(preview.capacity.safe_capacity)
	var assignments: Array = preview.assignments
	if assignments.is_empty() or not _combat_deployment_plan.can_publish_fire_assignments(assignments): return
	var committed: Dictionary = state.registry.try_replace_hazard_subset(team_id, get_order_serial(), [], assignments)
	if not committed.ok: state.status = str(committed.code); return
	_combat_deployment_plan.publish_fire_assignments(assignments)
	for mid: int in committed.leases: state.leases[mid] = committed.leases[mid]

func _fire_nav_working(index: int) -> bool:
	var mid := combat_identity(index)
	if _suppress_approaches.has(mid) and not bool(_suppress_approaches[mid].cancelled): return true
	return person_busy_query.is_valid() and bool(person_busy_query.call(mid))

func _fire_nav_update_members(now: float) -> void:
	var state := _fire_navigation
	var old: Dictionary = state.members
	var members := {}
	var profile := SiteCombatRules.fire_navigation_profile()
	for index in range(combat_units.size()):
		if not is_member(index) or not combat_can_act(index) or _ship_embarked(index) or _siege_crew(index): continue
		var mid := combat_identity(index)
		var entry: Dictionary = old.get(mid, {"route": [], "route_stamp": [], "target": INVALID_CELL,
			"policy": "NORMAL", "reason": "PENDING", "defer_age": 0, "wait_age": 0,
			"retry_at": 0.0, "proposal": -1, "next": INVALID_CELL, "lease": null})
		entry["index"] = index
		entry["band"] = _fire_nav_band(cells[index])
		entry["category"] = "safe_queue"
		entry["response"] = "NONE"
		var target := INVALID_CELL
		var lease: Variant = null
		var member_role := CombatMovementTypes.CombatDestinationRole.APPROACH_QUEUE
		if _combat_deployment_plan != null and _combat_deployment_plan.member_slot_map.has(mid):
			target = _combat_deployment_plan.member_slot_map[mid]
			member_role = _combat_deployment_plan.get_role_for_member(mid) as CombatMovementTypes.CombatDestinationRole
			lease = state.registry.owner_of(target)
			if lease == null or lease.formation_id != team_id or lease.order_serial != get_order_serial() or not _fire_nav_safe(target): target = INVALID_CELL; lease = null
		elif state.leases.has(mid):
			lease = state.leases[mid]
			if is_same(state.registry.owner_of(lease.cell), lease) and _fire_nav_safe(lease.cell): target = lease.cell
			else: lease = null
		var policy := "NORMAL"
		if int(entry.band) >= int(profile.evacuate_band):
			policy = "EMERGENCY_ESCAPE"
			var escape_lease: Variant = state.leases.get(mid)
			if str(entry.policy) == "EMERGENCY_ESCAPE" and escape_lease != null and is_same(state.registry.owner_of(escape_lease.cell), escape_lease) and _fire_nav_safe(escape_lease.cell):
				target = escape_lease.cell
				lease = escape_lease
			else:
				target = INVALID_CELL
				lease = null
			entry["category"] = "relocating"
			entry["response"] = "EVACUATING"
			if _suppress_approaches.has(mid):
				release_suppress_approach(mid, int(_suppress_approaches[mid].job_token))
		elif _fire_nav_working(index):
			entry["category"] = "working"
			entry["response"] = "SUPPRESSING"
			target = INVALID_CELL
		elif target != INVALID_CELL:
			entry["category"] = "safe_platform" if member_role == CombatMovementTypes.CombatDestinationRole.PLATFORM else "safe_queue"
			entry["response"] = "AVOIDING" if cells[index] != target else "NONE"
		elif combat_order != CombatOrder.MOVE and not state.unsafe.has(combat_slots[index]) and _fire_nav_safe(combat_slots[index]):
			target = combat_slots[index]
			entry["response"] = "AVOIDING" if cells[index] != target else "NONE"
		if is_controlled_person(index):
			entry["reason"] = "MANUAL_CONTROL"
			target = INVALID_CELL
			if int(entry.band) >= int(profile.evacuate_band): entry["category"] = "trapped"; entry["response"] = "TRAPPED"
		if target != entry.target or policy != str(entry.policy) or not is_same(lease, entry.lease):
			entry["route"] = []
			entry["route_stamp"] = []
			entry["retry_at"] = 0.0
			entry["reason"] = "PENDING"
		entry["target"] = target
		entry["policy"] = policy
		entry["lease"] = lease
		entry["role"] = member_role
		entry["next"] = INVALID_CELL
		entry["proposal"] = -1
		if target != INVALID_CELL and moving_to[index] == INVALID_CELL: combat_slots[index] = target
		if target == INVALID_CELL and policy == "NORMAL" and str(entry.category) == "safe_queue" \
			and not is_controlled_person(index) and _combat_deployment_plan != null \
			and _combat_deployment_plan.fire_suspended_members.has(mid):
			# No legal queue lease exists for this suspended original obligation.
			# Keep any original committed edge; report its endpoint before trapping.
			var settling := moving_to[index] != INVALID_CELL or _combat_batch_members.has(mid)
			entry["category"] = "relocating" if settling else "trapped"
			entry["response"] = "AVOIDING" if settling else "TRAPPED"
			entry["reason"] = "NO_SAFE_CAPACITY"
		if str(entry.reason) == "NO_SAFE_ROUTE" and str(policy) == "EMERGENCY_ESCAPE" and now < float(entry.retry_at):
			entry["category"] = "trapped"
			entry["response"] = "TRAPPED"
		members[mid] = entry
	for mid: int in old:
		if members.has(mid) or not state.leases.has(mid): continue
		var lease: Variant = state.leases[mid]
		if is_same(state.registry.owner_of(lease.cell), lease): state.registry.release_slots(team_id, lease.order_serial, [lease.cell])
		state.leases.erase(mid)
	state.members = members

func _fire_nav_route_stamp(entry: Dictionary) -> Array:
	return [get_order_serial(), ranged_order_serial, int(_fire_navigation.snapshot.revision), data.navigation_revision,
		entry.target, entry.policy, entry.lease, int(_fire_navigation.epoch)]

func _fire_nav_route_valid(entry: Dictionary) -> bool:
	var route: Array = entry.route
	var index := int(entry.index)
	if route.size() < 2 or route[0] != cells[index] or entry.route_stamp != _fire_nav_route_stamp(entry): return false
	for at in range(1, route.size()):
		if not FormationTransitPlanner._can_profile_step(data, route[at - 1], route[at], _formation_movement_profile) \
			or hazard_route_extra_cost(route[at - 1], route[at], str(entry.policy), combat_identity(index)) < 0: return false
	return true

func hazard_route_extra_cost(from_cell: Vector2i, to_cell: Vector2i, policy: String, member_id: int) -> int:
	if _fire_navigation.is_empty() or _coordinator == null or not data.contains(from_cell) or not data.contains(to_cell): return -1
	var profile := SiteCombatRules.fire_navigation_profile()
	var band := _fire_nav_band(to_cell)
	if policy == "NORMAL" and (band > int(profile.normal_max_band) or _fire_nav_band(from_cell) > int(profile.normal_max_band)): return -1
	var lease: Variant = _coordinator.deployment_registry.owner_of(to_cell)
	if lease != null and lease.formation_id != team_id: return -1
	if policy == "EMERGENCY_ESCAPE" and lease != null and lease.member_id > 0 and lease.member_id != member_id:
		return -1
	return int(profile.band_costs[clampi(band, 0, 3)])

func _fire_nav_escape_goal(cell: Vector2i, member_id: int) -> bool:
	if not data.is_walkable(cell) or _fire_nav_band(cell) > int(SiteCombatRules.fire_navigation_profile().safe_goal_band): return false
	var index := index_for_identity(member_id)
	if index < 0 or cell == cells[index] or _reserved_cells.has(cell) or _cell_owners.has(cell) or _is_external_cell(cell, member_id): return false
	if _coordinator.deployment_registry.owner_of(cell) != null: return false
	if _combat_deployment_plan != null and (_combat_deployment_plan.ingress_buffer_cells.has(cell) or cell == _combat_deployment_plan.ingress_cell): return false
	if _combat_deployment_plan != null and _combat_deployment_plan.fire_suspended_slots.has(cell): return false
	return true

func _fire_nav_local_goal(entry: Dictionary) -> Vector2i:
	var target: Vector2i = entry.target
	var source: Vector2i = cells[int(entry.index)]
	var limit := int(SiteCombatRules.fire_navigation_profile().route_lookahead)
	if target == INVALID_CELL or source.distance_squared_to(target) <= limit * limit or _combat_move_plan == null: return target
	var path: Array[Vector2i] = _combat_move_plan.macro_path
	var closest := -1
	var distance := INF
	for at in range(path.size()):
		var value := source.distance_squared_to(path[at])
		if value < distance: distance = value; closest = at
	if closest < 0: return target
	for at in range(mini(path.size() - 1, closest + limit), closest, -1):
		if path[at] != source and _fire_nav_safe(path[at]): return path[at]
	return target

func _fire_nav_publish_escape(member_id: int, target: Vector2i, entry: Dictionary) -> bool:
	var state := _fire_navigation
	var assignments: Array = [{"member_id": member_id, "cell": target, "role": CombatMovementTypes.CombatDestinationRole.APPROACH_QUEUE}]
	var needs_assignment := _combat_deployment_plan != null and not _combat_deployment_plan.member_slot_map.has(member_id)
	if needs_assignment and not _combat_deployment_plan.can_publish_fire_assignments(assignments): return false
	var previous: Array = []
	var old: Variant = state.leases.get(member_id)
	if old != null and is_same(state.registry.owner_of(old.cell), old): previous.append(old)
	var committed: Dictionary = state.registry.try_replace_hazard_subset(team_id, get_order_serial(), previous, assignments)
	if not committed.ok: entry["reason"] = str(committed.code); return false
	if needs_assignment: _combat_deployment_plan.publish_fire_assignments(assignments)
	state.leases[member_id] = committed.leases[member_id]
	entry["target"] = target
	entry["lease"] = committed.leases[member_id]
	return true

func _fire_nav_search(member_id: int, quota: int, route_budget: Object) -> void:
	var state := _fire_navigation
	var entry: Dictionary = state.members[member_id]
	var index := int(entry.index)
	var goal := _fire_nav_local_goal(entry)
	var goal_test := _fire_nav_escape_goal.bind(member_id) if str(entry.policy) == "EMERGENCY_ESCAPE" and entry.target == INVALID_CELL else Callable()
	var route_status := {"track_dynamic": true}
	var before := expanded_nodes
	var route := _find_local_route(cells[index], cells[index] if goal_test.is_valid() else goal,
		quota, true, -1, 0, false, _formation_movement_profile, int(entry.wait_age) >= 3,
		route_status, hazard_route_extra_cost.bind(str(entry.policy), member_id), goal_test)
	var used := maxi(0, expanded_nodes - before)
	var charge := mini(quota, maxi(int(SiteCombatRules.fire_navigation_profile().route_minimum_charge), used))
	route_budget.record_route_result(get_formation_id(), 1, charge)
	entry["last_actual_expansions"] = used
	entry["last_charged_expansions"] = charge
	entry["defer_age"] = 0
	entry["route"] = []
	entry["next"] = INVALID_CELL
	if route.size() >= 2:
		if goal_test.is_valid() and not _fire_nav_publish_escape(member_id, route[-1], entry):
			entry["retry_at"] = _fire_nav_now(state.snapshot) + float(SiteCombatRules.fire_navigation_profile().replan_seconds)
			return
		entry["route"] = route
		entry["route_stamp"] = _fire_nav_route_stamp(entry)
		entry["reason"] = "READY"
		entry["next"] = route[1]
		return
	if bool(route_status.get("capped", false)) or str(route_status.get("outcome", "")) == "deferred":
		entry["reason"] = "SEARCH_DEFERRED"
		return
	var dynamic := bool(route_status.get("dependency_incomplete", false))
	for values: Array in route_status.get("dependencies", {}).values():
		if bool(values[0]) or values[1] != null or values[2] != null: dynamic = true; break
	entry["reason"] = "WAIT_OCCUPANCY" if dynamic else "NO_SAFE_ROUTE"
	entry["retry_at"] = _fire_nav_now(state.snapshot) + float(SiteCombatRules.fire_navigation_profile().retry_seconds)
	if not dynamic and str(entry.policy) == "EMERGENCY_ESCAPE":
		entry["category"] = "trapped"
		entry["response"] = "TRAPPED"

func _fire_nav_request_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.age) != int(b.age): return int(a.age) > int(b.age)
	return int(a.member) < int(b.member)

func _fire_nav_run_pool(requests: Array, call_limit: int, expansion_limit: int, route_budget: Object,
		pool_name: String, served: Dictionary) -> Dictionary:
	var used_calls := 0
	var used_expansions := 0
	var actual_expansions := 0
	for request: Dictionary in requests:
		if served.has(request.member): continue
		if used_calls >= call_limit or used_expansions >= expansion_limit or not route_budget.can_request_route(get_formation_id()): break
		var left := expansion_limit - used_expansions
		var calls_left := call_limit - used_calls
		var quota := mini(256, mini(route_budget.request_route_budget(get_formation_id()), maxi(1, left - (calls_left - 1) * 32)))
		quota = mini(quota, left)
		if quota <= 0: break
		var calls_before := int(route_budget.site_calls_used)
		var charge_before := int(route_budget.site_expansions_used)
		var actual_before := expanded_nodes
		if bool(request.work): _prepare_suppress_approach(route_budget, quota, 32, int(request.member))
		else: _fire_nav_search(int(request.member), quota, route_budget)
		var calls := int(route_budget.site_calls_used) - calls_before
		var charge := int(route_budget.site_expansions_used) - charge_before
		used_calls += calls
		used_expansions += charge
		actual_expansions += maxi(0, expanded_nodes - actual_before)
		served[request.member] = true
		_fire_navigation.metrics.trace.append({"pool": pool_name, "member": request.member, "calls": calls, "charged": charge, "actual": maxi(0, expanded_nodes - actual_before)})
	return {"calls": used_calls, "charged": used_expansions, "actual": actual_expansions}

func _fire_nav_schedule(route_budget: Object, now: float) -> void:
	var state := _fire_navigation
	var aging: Array[Dictionary] = []
	var urgent: Array[Dictionary] = []
	var profile := SiteCombatRules.fire_navigation_profile()
	# Cached SUPPRESS motion is prepared without a search. Its uncached request
	# joins the SAME formation pools below, never consumes Aging quota first.
	_prepare_suppress_approach(null, 0)
	for mid: int in _suppress_approaches:
		var work: Dictionary = _suppress_approaches[mid]
		var query := suppress_approach_query(mid, int(work.job_token))
		var index := index_for_identity(mid)
		if query.ok and query.phase == "APPROACHING" and index >= 0 and moving_to[index] == INVALID_CELL and work.next == INVALID_CELL:
			aging.append({"member": mid, "work": true, "age": int(work.wait_age)})
	for mid: int in state.members:
		var entry: Dictionary = state.members[mid]
		var index := int(entry.index)
		if moving_to[index] != INVALID_CELL or _combat_batch_members.has(mid) or is_controlled_person(index) \
			or _combat_action_blocks_step(index) or str(entry.category) == "working" or now < float(entry.retry_at): continue
		if str(entry.policy) == "NORMAL" and (entry.target == INVALID_CELL or cells[index] == entry.target): continue
		if _fire_nav_route_valid(entry): entry["next"] = entry.route[1]; continue
		entry["route"] = []
		entry["route_stamp"] = []
		entry["next"] = INVALID_CELL
		var request := {"member": mid, "work": false, "age": int(entry.defer_age)}
		if int(entry.band) < int(profile.immediate_band) or int(entry.defer_age) >= int(profile.aging_ticks): aging.append(request)
		else: urgent.append(request)
	aging.sort_custom(_fire_nav_request_less)
	urgent.sort_custom(_fire_nav_request_less)
	var partition: Dictionary = route_budget.fire_aging_partition(get_formation_id(), not aging.is_empty())
	state.metrics = {"allocation_calls": partition.calls, "allocation_expansions": partition.expansions,
		"aging_reserved_calls": partition.aging_calls, "aging_reserved_expansions": partition.aging_expansions,
		"aging_demand": aging.size(), "urgent_demand": urgent.size(), "trace": []}
	var served := {}
	var first := _fire_nav_run_pool(aging, int(partition.aging_calls), int(partition.aging_expansions), route_budget, "AGING", served)
	var rest: Array = urgent.duplicate()
	for request: Dictionary in aging:
		if not served.has(request.member): rest.append(request)
	var second := _fire_nav_run_pool(rest, int(partition.calls) - int(first.calls), int(partition.expansions) - int(first.charged), route_budget, "AFTER_AGING", served)
	state.metrics.aging_used = first
	state.metrics.after_aging_used = second
	for request: Dictionary in aging + urgent:
		if served.has(request.member): continue
		if bool(request.work):
			var deferred_work: Dictionary = _suppress_approaches.get(int(request.member), {})
			if not deferred_work.is_empty():
				deferred_work["wait_age"] = mini(2147483647, int(deferred_work.wait_age) + 1)
				deferred_work["route_status"] = "SCHEDULER_DEFERRED"
		else:
			var entry: Dictionary = state.members[int(request.member)]
			entry["defer_age"] = mini(2147483647, int(entry.defer_age) + 1)
			entry["reason"] = "SCHEDULER_DEFERRED"
	# The original MOVE's stall/recovery never runs during this overlay. A
	# missed Site slice therefore cannot accumulate STATIC_BLOCKED time.
	if _combat_move_plan != null:
		_combat_move_plan.scheduler_deferred = int(partition.calls) == 0 and not (aging.is_empty() and urgent.is_empty())

func _fire_nav_finish_cooling() -> void:
	if _combat_move_plan != null:
		# Re-enter the original planner with current cells/leases. Never reuse an
		# old route whose body moved during evacuation, even under the same order.
		for mid: int in _get_active_member_ids(): _combat_move_plan.invalidate_member_route(mid)
		_combat_move_plan.member_pending_proposal_id.clear()
		_combat_move_plan.member_pending_from_cell.clear()
		_combat_move_plan.member_pending_to_cell.clear()
		_combat_move_plan.path_epoch += 1
		_combat_move_plan.scheduler_deferred = false
	if _combat_deployment_plan != null: _combat_deployment_plan.finish_fire_suspension()
	_fire_nav_reset()

func _prepare_fire_navigation(route_budget: Object, delta: float) -> bool:
	if data == null or not combat_enabled or not exchange_enabled or _coordinator == null or route_budget == null or not garrison_feature_id.is_empty(): return false
	if not _fire_navigation.is_empty() and not _fire_nav_context_current(): _fire_nav_reset()
	var snapshot := SiteRuntime.fire_hazard_snapshot(data)
	var relevant := _fire_nav_intersects(snapshot)
	if _fire_navigation.is_empty():
		if not relevant: return false
		_fire_nav_start(snapshot)
	var state := _fire_navigation
	state.snapshot = snapshot
	var now := _fire_nav_now(snapshot)
	var profile := SiteCombatRules.fire_navigation_profile()
	for cell: Vector2i in state.unsafe:
		if _fire_nav_band(cell) > 0: relevant = true; break
	var newly_unsafe := _fire_nav_suspend_unsafe()
	# Original death/KO/absence maintenance still runs, now that unsafe slots
	# have been removed from its promotion candidates. The original lease sync
	# preserves exact temporary escape handles while this overlay owns them.
	if _combat_deployment_plan != null: update_combat_deployment(delta, _coordinator.deployment_registry)
	var immediate := false
	for index in range(combat_units.size()):
		if is_member(index) and combat_can_act(index) and _fire_nav_band(cells[index]) >= int(profile.immediate_band): immediate = true; break
	var changed := int(state.revision) != int(snapshot.revision) or int(state.navigation) != data.navigation_revision \
		or _combat_deployment_plan != null and int(state.assignment) != _combat_deployment_plan.assignment_epoch
	if changed and (immediate or now - float(state.last_replan) + 0.00000001 >= float(profile.replan_seconds)):
		_fire_nav_capacity_replan()
		state.revision = int(snapshot.revision)
		state.navigation = data.navigation_revision
		state.assignment = _combat_deployment_plan.assignment_epoch if _combat_deployment_plan != null else -1
		state.last_replan = now
		state.replans = int(state.replans) + 1
		for entry: Dictionary in state.members.values(): entry.retry_at = 0.0
	if newly_unsafe: state.cool_since = -1.0
	if relevant: state.cool_since = -1.0
	elif float(state.cool_since) < 0.0: state.cool_since = now
	elif now - float(state.cool_since) + 0.00000001 >= float(profile.safe_seconds) and _combat_batch_members.is_empty():
		_fire_nav_finish_cooling()
		return false
	_fire_nav_update_members(now)
	_fire_nav_schedule(route_budget, now)
	return true

func _propose_fire_navigation(grid: Object) -> void:
	if not _fire_nav_context_current(): return
	_propose_suppress_approach(grid)
	for mid: int in _fire_navigation.members:
		var entry: Dictionary = _fire_navigation.members[mid]
		var index := int(entry.index)
		var next: Vector2i = entry.next
		if moving_to[index] != INVALID_CELL or next == INVALID_CELL or grid.member_proposal_map.has(mid): continue
		if not _fire_nav_route_valid(entry) or grid.blocked_destinations.has(next) or _is_external_cell(next, mid):
			entry["route"] = []
			entry["wait_age"] = mini(2147483647, int(entry.wait_age) + 1)
			entry["reason"] = "WAIT_OCCUPANCY"
			continue
		var occupant := int(grid.initial_occupancy.get(next, 0))
		if occupant > 0 and index_for_identity(occupant) < 0: continue
		entry["proposal"] = grid.propose_move(get_formation_id(), mid, get_order_serial(), cells[index], next,
			1 if str(entry.policy) == "EMERGENCY_ESCAPE" else 0, int(entry.wait_age), 0, 0, formation_persistent_serial)
		if int(entry.proposal) >= 0: proposal_count += 1

func _is_fire_proposal(member_id: int, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not _fire_nav_context_current() or not _fire_navigation.members.has(member_id): return false
	var entry: Dictionary = _fire_navigation.members[member_id]
	var grid: Object = _coordinator.movement_reservation_grid
	var proposal: Variant = grid.proposal_lookup.get(int(entry.proposal))
	return proposal != null and grid.member_proposal_map.get(member_id, -1) == int(entry.proposal) \
		and proposal.formation_id == get_formation_id() and proposal.order_serial == get_order_serial() \
		and proposal.from_cell == from_cell and proposal.to_cell == to_cell

func _can_begin_fire_move(member_id: int, from_cell: Vector2i, to_cell: Vector2i, participants: Dictionary) -> bool:
	var index := index_for_identity(member_id)
	if index < 0 or not garrison_feature_id.is_empty() or not is_member(index) or not combat_can_act(index) \
		or is_controlled_person(index) or _ship_embarked(index) or _siege_crew(index) or _combat_action_blocks_step(index) \
		or _unit_rescues.has(index) or moving_to[index] != INVALID_CELL or cells[index] != from_cell \
		or _cell_owners.get(from_cell, -1) != index or _reserved_cells.has(to_cell) \
		or not FormationTransitPlanner._can_profile_step(data, from_cell, to_cell, _formation_movement_profile) \
		or _is_external_cell(to_cell, member_id): return false
	var entry: Dictionary = _fire_navigation.members[member_id]
	if str(entry.category) == "working" or hazard_route_extra_cost(from_cell, to_cell, str(entry.policy), member_id) < 0: return false
	var lease: Variant = entry.lease
	if lease == null or not is_same(_coordinator.deployment_registry.owner_of(lease.cell), lease) \
		or lease.formation_id != team_id or lease.order_serial != get_order_serial(): return false
	var occupant := int(_cell_owners.get(to_cell, -1))
	if occupant >= 0 and not participants.has(combat_identity(occupant)): return false
	return vehicle_transport == null or not vehicle_transport.is_operator(member_id)

func _finalize_fire_navigation(grid: Object) -> void:
	if not _fire_nav_context_current(): return
	for mid: int in _fire_navigation.members:
		var entry: Dictionary = _fire_navigation.members[mid]
		var proposal: Variant = grid.proposal_lookup.get(int(entry.proposal))
		if proposal == null: continue
		if proposal.status == CombatMovementTypes.MoveProposalStatus.ACCEPTED: entry["wait_age"] = 0
		else:
			entry["wait_age"] = mini(2147483647, int(entry.wait_age) + 1)
			entry["reason"] = "WAIT_OCCUPANCY"
			entry["route"] = []

func _committed_intent_order(member_id: int) -> int:
	var value: Variant = _combat_batch_members.get(member_id, -1)
	return int(value.get("order", -1)) if value is Dictionary else int(value)

func _capture_committed_intent(member_id: int, order: int) -> Dictionary:
	return {"order": order, "serial": get_order_serial(), "ranged_serial": ranged_order_serial,
		"move_plan": _combat_move_plan, "deployment": _combat_deployment_plan,
		"movement_profile": _formation_movement_profile,
		"path_epoch": _combat_move_plan.path_epoch if _combat_move_plan != null else -1,
		"assignment_epoch": _combat_deployment_plan.assignment_epoch if _combat_deployment_plan != null else -1,
		"fire_epoch": int(_fire_navigation.get("epoch", -1)),
		"work_token": int(_suppress_approaches.get(member_id, {}).get("job_token", -1))}

func _committed_intent_current(intent: Dictionary) -> bool:
	return int(intent.get("serial", -1)) == get_order_serial() and int(intent.get("ranged_serial", -1)) == ranged_order_serial \
		and is_same(intent.get("move_plan"), _combat_move_plan) and is_same(intent.get("deployment"), _combat_deployment_plan) \
		and int(intent.get("path_epoch", -1)) == (_combat_move_plan.path_epoch if _combat_move_plan != null else -1) \
		and int(intent.get("assignment_epoch", -1)) == (_combat_deployment_plan.assignment_epoch if _combat_deployment_plan != null else -1)

func _committed_intent(member_id: int) -> Dictionary:
	var value: Variant = _combat_batch_members.get(member_id, -1)
	# Older snapshots contain only the original order. Their reconstructed plan
	# is the current owner; the P5 optional provenance replaces this on restore.
	return value if value is Dictionary else _capture_committed_intent(member_id, int(value))

func committed_move_can_change_main_order(member_id: int) -> bool:
	var intent := _committed_intent(member_id)
	return _fire_navigation.is_empty() and int(intent.order) not in [CombatOrder.HOLD, FIRE_HAZARD_STEP] and _committed_intent_current(intent)

func _finish_special_committed_intent(member_id: int, intent: Dictionary, old_cell: Vector2i, new_cell: Vector2i) -> void:
	if int(intent.order) == CombatOrder.HOLD:
		if int(intent.work_token) == int(_suppress_approaches.get(member_id, {}).get("job_token", -2)) \
			and _committed_intent_current(intent): _finish_suppress_move(member_id, old_cell, new_cell)
		return
	if int(intent.order) != FIRE_HAZARD_STEP or not _fire_nav_context_current() \
		or int(intent.fire_epoch) != int(_fire_navigation.epoch) or not _fire_navigation.members.has(member_id): return
	var entry: Dictionary = _fire_navigation.members[member_id]
	var route: Array = entry.route
	if route.size() > 1 and route[0] == old_cell and route[1] == new_cell: route.remove_at(0)
	else: entry["route"] = []
	entry["next"] = INVALID_CELL
	entry["proposal"] = -1
	entry["wait_age"] = 0

func fire_threat_summary(action_end: float = -1.0) -> Dictionary:
	var result := {"formation_id": get_formation_id(), "team_id": team_id, "order_serial": get_order_serial(),
		"action_end": action_end if action_end >= 0.0 else (float(data.get_meta(&"fire_completed_action_end", 0.0)) if data != null else 0.0),
		"active": 0, "threatened": 0, "burning": 0, "safe_platform": 0, "safe_queue": 0,
		"relocating": 0, "trapped": 0, "working": 0, "deferred": 0, "fire_hp_loss": 0.0, "fire_deaths": 0}
	if not combat_enabled: return result
	var snapshot := SiteRuntime.fire_hazard_snapshot(data) if data != null else {}
	for index in range(combat_units.size()):
		if not is_member(index): continue
		var body: Dictionary = combat_units[index].get("fire_body", {})
		if is_equal_approx(float(body.get("last_action_end", -1.0)), float(result.action_end)):
			result.fire_hp_loss += float(body.get("last_interval_fire_hp", 0.0))
			result.fire_deaths += 1 if bool(body.get("last_interval_fire_death", false)) else 0
		if not combat_can_act(index): continue
		result.active += 1
		if _fire_nav_band(cells[index], snapshot) > 0: result.threatened += 1
		if float(body.get("burn_left", 0.0)) > 0.0: result.burning += 1
		var entry: Dictionary = _fire_navigation.get("members", {}).get(combat_identity(index), {})
		if not entry.is_empty():
			result[str(entry.category)] += 1
			if str(entry.reason) in ["SEARCH_DEFERRED", "SCHEDULER_DEFERRED"]: result.deferred += 1
	return result

func _publish_fire_threat_summary(action_end: float) -> void:
	if action_end <= _fire_threat_last_end: return
	_fire_threat_last_end = action_end
	var summary := fire_threat_summary(action_end)
	if not _fire_navigation.is_empty(): _fire_navigation.last_summary = summary
	fire_threat_summary_changed.emit(summary)

# P4 extends the original Army's work-intent collection. PersonActions owns
# each job/time/supply; original Grid still owns every physical batch.
var _suppress_approaches: Dictionary = {} # persistent member ID -> original work approach

func begin_suppress_approach(member_id: int, job_token: int, slot: Vector2i, expected_order_serial: int) -> Dictionary:
	if _suppress_approaches.has(member_id): return SiteRuntime.fail("BUSY")
	var index := index_for_identity(member_id)
	if _coordinator == null or _coordinator.get_formation_by_id(get_formation_id()) != self: return SiteRuntime.fail("NO_ORIGINAL_COORDINATOR")
	if job_token <= 0 or index < 0 or data == null or not combat_enabled or not exchange_enabled \
		or combat_order != CombatOrder.HOLD or get_order_serial() != expected_order_serial \
		or _combat_move_plan != null or _combat_deployment_plan != null or not garrison_feature_id.is_empty() \
		or not is_member(index) or is_controlled_person(index) or not combat_can_act(index) \
		or is_sustain_routed() or moving_to[index] != INVALID_CELL or _combat_action_blocks_step(index) \
		or _unit_rescues.has(index) or patient_has_rescuer(index) or _ship_embarked(index) or _siege_crew(index) \
		or not combat_units[index].get("work_task", {}).is_empty() \
		or person_busy_query.is_valid() and bool(person_busy_query.call(member_id)): return SiteRuntime.fail("BUSY")
	if vehicle_transport != null and vehicle_transport.is_operator(member_id): return SiteRuntime.fail("BUSY")
	if not _suppress_cell_safe(cells[index]) or not _suppress_cell_safe(slot): return SiteRuntime.fail("NO_SAFE_WORK_SLOT")
	if slot != cells[index] and (_cell_owners.has(slot) or _reserved_cells.has(slot) or _is_external_cell(slot, member_id)): return SiteRuntime.fail("WORK_SLOT_BUSY")
	var registry: SiteDeploymentReservationRegistry = _coordinator.deployment_registry
	var reserved := registry.reserve_work_slot(team_id, expected_order_serial, member_id, slot)
	if not reserved.ok: return reserved
	_suppress_approaches[member_id] = {"member_id":member_id,"job_token":job_token,"slot":slot,
		"order_serial":expected_order_serial,"ranged_order_serial":ranged_order_serial,
		"terrain":data,"site_state":data.site,"registry":registry,"lease":reserved.lease,
		"cancelled":false,"reason":"","route":[],"navigation_revision":data.navigation_revision,
		"proposal_id":-1,"next":INVALID_CELL,"wait_age":0,"route_status":"PENDING"}
	return suppress_approach_query(member_id, job_token)

func suppress_approach_query(member_id: int, job_token: int) -> Dictionary:
	var state: Dictionary = _suppress_approaches.get(member_id, {})
	if state.is_empty():
		return {"ok":true,"phase":"DONE","done":true,"cell":INVALID_CELL,"slot":INVALID_CELL,
			"lease":null,"registry":_coordinator.deployment_registry if _coordinator != null else null,
			"order_serial":get_order_serial(),"ranged_order_serial":ranged_order_serial}
	if job_token != int(state.job_token): return SiteRuntime.fail("STALE_WORK_JOB")
	var index := index_for_identity(member_id)
	var moving := index >= 0 and (moving_to[index] != INVALID_CELL or _combat_batch_members.has(member_id))
	var code := str(state.reason) if bool(state.cancelled) else _suppress_context_code(index, state)
	var arrived := code.is_empty() and not moving and cells[index] == Vector2i(state.slot)
	return {"ok":code.is_empty(),"code":code,"phase":"SETTLING" if not code.is_empty() and moving else ("DONE" if not code.is_empty() else ("ARRIVED" if arrived else "APPROACHING")),
		"done":not code.is_empty() and not moving,"cell":cells[index] if index >= 0 else INVALID_CELL,
		"slot":state.slot,"lease":state.lease,"registry":state.registry,"owner_exists":index >= 0,
		"order_serial":state.order_serial,"ranged_order_serial":state.ranged_order_serial,"route_status":state.route_status}

func release_suppress_approach(member_id: int, job_token: int) -> Dictionary:
	var state: Dictionary = _suppress_approaches.get(member_id, {})
	if state.is_empty(): return suppress_approach_query(member_id, job_token)
	if job_token != int(state.job_token): return SiteRuntime.fail("STALE_WORK_JOB")
	state["cancelled"] = true
	if str(state.reason).is_empty(): state["reason"] = "CANCELLED"
	state.route.clear()
	state["next"] = INVALID_CELL
	state["proposal_id"] = -1
	state.registry.release_work_slot(state.lease)
	var result := suppress_approach_query(member_id, job_token)
	if bool(result.get("done", false)): _suppress_approaches.erase(member_id)
	return result

func has_pending_suppress_approach() -> bool:
	for mid: int in _suppress_approaches:
		var state: Dictionary = _suppress_approaches[mid]
		var index := index_for_identity(mid)
		if index >= 0 and (moving_to[index] != INVALID_CELL or _combat_batch_members.has(mid) \
			or not bool(state.cancelled) and cells[index] != Vector2i(state.slot)): return true
	return false

func _suppress_context_code(index: int, state: Dictionary) -> String:
	if index < 0: return "NO_PERSON"
	if not is_same(data, state.terrain) or not is_same(data.site, state.site_state): return "STALE_SITE"
	if _coordinator == null or _coordinator.get_formation_by_id(get_formation_id()) != self \
		or not is_same(_coordinator.deployment_registry, state.registry): return "STALE_MOVEMENT_OWNER"
	if not combat_enabled or not combat_can_act(index) or not is_member(index): return "NO_PERSON"
	if combat_order != CombatOrder.HOLD or get_order_serial() != int(state.order_serial) or ranged_order_serial != int(state.ranged_order_serial) \
		or _combat_move_plan != null or _combat_deployment_plan != null: return "STALE_ORDER"
	if is_sustain_routed() or not garrison_feature_id.is_empty() or _ship_embarked(index) or _siege_crew(index) or _unit_rescues.has(index) or patient_has_rescuer(index) \
		or _combat_action_blocks_step(index) or is_controlled_person(index): return "INTERRUPTED"
	if vehicle_transport != null and vehicle_transport.is_operator(int(state.member_id)): return "INTERRUPTED"
	if not is_same(state.registry.owner_of(state.slot), state.lease): return "STALE_WORK_LEASE"
	if not _suppress_cell_safe(state.slot) or not _suppress_cell_safe(cells[index]): return "NO_SAFE_WORK_SLOT"
	return ""

func _suppress_waiting_less(a: int, b: int) -> bool:
	var age_a := int(_suppress_approaches[a].wait_age)
	var age_b := int(_suppress_approaches[b].wait_age)
	return age_a > age_b if age_a != age_b else a < b

func _prepare_suppress_approach(route_budget: Object, quota_limit: int = 256, minimum_charge: int = 0, only_member: int = 0) -> void:
	var ids: Array = [only_member] if only_member > 0 else _suppress_approaches.keys()
	if only_member <= 0: ids.sort_custom(_suppress_waiting_less)
	for mid: int in ids:
		if _suppress_approaches.has(mid): _prepare_suppress_member(mid, route_budget, quota_limit, minimum_charge)

func _prepare_suppress_member(member_id: int, route_budget: Object, quota_limit: int, minimum_charge: int) -> void:
	var state: Dictionary = _suppress_approaches[member_id]
	var query := suppress_approach_query(member_id, int(state.job_token))
	if not query.ok:
		state["reason"] = str(query.code)
		release_suppress_approach(member_id, int(state.job_token))
		return
	var index := index_for_identity(member_id)
	if moving_to[index] != INVALID_CELL or _combat_batch_members.has(member_id) or query.phase == "ARRIVED": return
	state["next"] = INVALID_CELL
	state["proposal_id"] = -1
	var route: Array = state.route
	var current: bool = int(state.navigation_revision) == data.navigation_revision and route.size() > 1 \
		and route[0] == cells[index] and route[-1] == state.slot
	if current:
		for at in range(1, route.size()):
			if not data.can_step(route[at - 1], route[at]) or not _suppress_step_allowed(route[at - 1], route[at]): current = false; break
	if not current:
		state["route"] = []
		var fid := get_formation_id()
		if route_budget == null or not route_budget.can_request_route(fid):
			state["route_status"] = "SCHEDULER_DEFERRED"
			if route_budget != null: state["wait_age"] = mini(2147483647, int(state.wait_age) + 1)
			return
		var quota := mini(quota_limit, mini(256, int(route_budget.request_route_budget(fid))))
		if quota <= 0: state["route_status"] = "SCHEDULER_DEFERRED"; return
		var expanded_before := expanded_nodes
		var status := {}
		var found := _find_local_route(cells[index], state.slot, quota, false, -1, 0, false, null, true, status, _suppress_route_extra_cost)
		route_budget.record_route_result(fid, 1, mini(quota, maxi(minimum_charge, expanded_nodes - expanded_before)))
		state["navigation_revision"] = data.navigation_revision
		if found.size() < 2:
			state["route_status"] = "SCHEDULER_DEFERRED" if bool(status.get("capped", false)) or str(status.get("outcome", "")) == "deferred" else "NO_SAFE_ROUTE"
			state["wait_age"] = mini(2147483647, int(state.wait_age) + 1)
			return
		state["route"] = found
		route = found
	state["next"] = route[1]
	state["route_status"] = "READY_TO_PROPOSE"

func _propose_suppress_approach(grid: Object) -> void:
	var ids: Array = _suppress_approaches.keys()
	ids.sort()
	for mid: int in ids: _propose_suppress_member(mid, grid)

func _propose_suppress_member(member_id: int, grid: Object) -> void:
	var state: Dictionary = _suppress_approaches[member_id]
	var query := suppress_approach_query(member_id, int(state.job_token))
	if not query.ok or query.phase != "APPROACHING": return
	var index := index_for_identity(member_id)
	var next: Vector2i = state.next
	if moving_to[index] != INVALID_CELL or next == INVALID_CELL or grid.member_proposal_map.has(member_id): return
	if not _suppress_step_allowed(cells[index], next) or grid.blocked_destinations.has(next) \
		or grid.initial_occupancy.has(next) or _is_external_cell(next, member_id):
		state.route.clear()
		state["wait_age"] = mini(2147483647, int(state.wait_age) + 1)
		state["route_status"] = "WAIT_OCCUPANCY"
		return
	state["proposal_id"] = grid.propose_move(get_formation_id(), member_id, int(state.order_serial), cells[index], next,
		0, int(state.wait_age), 0, 0, formation_persistent_serial)
	if int(state.proposal_id) >= 0: proposal_count += 1

func _is_suppress_proposal(member_id: int, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var state: Dictionary = _suppress_approaches.get(member_id, {})
	if state.is_empty() or _coordinator == null: return false
	var grid: Object = _coordinator.movement_reservation_grid
	var proposal: Variant = grid.proposal_lookup.get(int(state.proposal_id))
	return proposal != null and grid.member_proposal_map.get(member_id, -1) == int(state.proposal_id) \
		and proposal.from_cell == from_cell and proposal.to_cell == to_cell and proposal.order_serial == int(state.order_serial)

func _can_begin_suppress_move(member_id: int, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var state: Dictionary = _suppress_approaches.get(member_id, {})
	if state.is_empty(): return false
	var query := suppress_approach_query(member_id, int(state.job_token))
	var index := index_for_identity(member_id)
	return query.ok and query.phase == "APPROACHING" and index >= 0 and moving_to[index] == INVALID_CELL \
		and cells[index] == from_cell and _cell_owners.get(from_cell, -1) == index and not _reserved_cells.has(to_cell) \
		and not _cell_owners.has(to_cell) and data.can_step(from_cell, to_cell) and _suppress_step_allowed(from_cell, to_cell) \
		and not _is_external_cell(to_cell, member_id) and (vehicle_transport == null or not vehicle_transport.is_operator(member_id))

func _finish_suppress_move(member_id: int, old_cell: Vector2i, new_cell: Vector2i) -> void:
	var state: Dictionary = _suppress_approaches.get(member_id, {})
	if state.is_empty(): return
	var route: Array = state.route
	if route.size() > 1 and route[0] == old_cell and route[1] == new_cell: route.remove_at(0)
	else: route.clear()
	state["next"] = INVALID_CELL
	state["proposal_id"] = -1
	state["wait_age"] = 0
	var query := suppress_approach_query(member_id, int(state.job_token))
	if not query.ok: release_suppress_approach(member_id, int(state.job_token))

# P5 optional snapshot extension. Original rows/cells/progress/batches/plans
# are restored first by their existing owner. This payload contains only intent.
func fire_navigation_save_guard() -> Dictionary:
	if not _fire_navigation.is_empty() and not _fire_nav_context_current(): return SiteRuntime.fail("BUSY", "火場意圖等待原指令世代收束")
	for mid: int in _suppress_approaches:
		var state: Dictionary = _suppress_approaches[mid]
		var index := index_for_identity(mid)
		if index < 0: return SiteRuntime.fail("BUSY", "工作人員移交尚未完成")
		if not bool(state.cancelled) and not _suppress_context_code(index,state).is_empty(): return SiteRuntime.fail("BUSY", "工作取消尚未收束")
		if moving_to[index] != INVALID_CELL and not _combat_batch_members.has(mid): return SiteRuntime.fail("BUSY", "工作移動尚未納入原批次")
	return {"ok":true}

func fire_navigation_snapshot() -> Dictionary:
	var work: Array[Dictionary] = []
	var ids: Array = _suppress_approaches.keys()
	ids.sort()
	for mid: int in ids:
		var state: Dictionary = _suppress_approaches[mid]
		work.append({"member_id":mid,"job_token":int(state.job_token),"slot":[state.slot.x,state.slot.y],
			"order_serial":int(state.order_serial),"ranged_serial":int(state.ranged_order_serial),
			"cancelled":bool(state.cancelled),"reason":str(state.reason),"wait_age":int(state.wait_age)})
	var hazard := {}
	if not _fire_navigation.is_empty():
		var state := _fire_navigation
		var members: Array[Dictionary] = []
		ids = state.members.keys()
		ids.sort()
		for mid: int in ids:
			var entry: Dictionary = state.members[mid]
			members.append({"member_id":mid,"target":[entry.target.x,entry.target.y],"policy":str(entry.policy),
				"category":str(entry.category),"response":str(entry.response),"reason":str(entry.reason),
				"defer_age":int(entry.defer_age),"wait_age":int(entry.wait_age),"retry_at":float(entry.retry_at)})
		var leases: Array[Dictionary] = []
		for mid: int in state.leases:
			var lease: Variant = state.leases[mid]
			if lease != null and is_same(state.registry.owner_of(lease.cell),lease):
				leases.append({"member_id":mid,"cell":[lease.cell.x,lease.cell.y]})
		var unsafe: Array = []
		for cell: Vector2i in state.unsafe: unsafe.append([cell.x,cell.y])
		hazard = {"serial":int(state.serial),"ranged_serial":int(state.ranged_serial),"order":int(state.order),
			"epoch":int(state.epoch),"last_replan":float(state.last_replan),"cool_since":float(state.cool_since),
			"replans":int(state.replans),"status":str(state.status),"members":members,"leases":leases,"unsafe":unsafe}
	var batches: Array[Dictionary] = []
	ids = _combat_batch_members.keys()
	ids.sort()
	for mid: int in ids:
		var intent := _committed_intent(mid)
		var profile: Variant = intent.get("movement_profile")
		var saved_profile: Array = [] if profile == null else [profile.allowed_terrain_mask,profile.max_step_height,profile.can_use_ramp,profile.footprint_cells]
		batches.append({"member_id":mid,"order":int(intent.order),"serial":int(intent.serial),"ranged_serial":int(intent.ranged_serial),
			"move_current":is_same(intent.move_plan,_combat_move_plan),"deployment_current":is_same(intent.deployment,_combat_deployment_plan),
			"path_epoch":int(intent.path_epoch),"assignment_epoch":int(intent.assignment_epoch),"fire_epoch":int(intent.fire_epoch),
			"work_token":int(intent.work_token),"profile":saved_profile})
	var deployment := {}
	if _combat_deployment_plan != null:
		var slots: Array = []
		var members: Array = []
		for cell: Vector2i in _combat_deployment_plan.fire_suspended_slots:
			slots.append([cell.x,cell.y,int(_combat_deployment_plan.fire_suspended_slots[cell])])
		for mid: int in _combat_deployment_plan.fire_suspended_members:
			var cell: Vector2i = _combat_deployment_plan.fire_suspended_members[mid]
			members.append([mid,cell.x,cell.y])
		deployment = {"slots":slots,"members":members,"safe_capacity":_combat_deployment_plan.fire_safe_platform_capacity}
	return {"version":1,"team_id":team_id,"serial":get_order_serial(),"ranged_serial":ranged_order_serial,
		"hazard_epoch":_fire_navigation_epoch,"threat_last_end":_fire_threat_last_end,
		"work":work,"hazard":hazard,"batches":batches,"deployment":deployment}

static func _fire_navigation_integer(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return SiteDeploymentReservationRegistry._fire_saved_integer(value,minimum,maximum)

static func _fire_navigation_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _fire_navigation_cell(value: Variant, invalid_allowed: bool = false) -> bool:
	if not value is Array or value.size() != 2: return false
	if invalid_allowed and value == [-1,-1]: return true
	return _fire_navigation_integer(value[0],0,data.size.x-1) and _fire_navigation_integer(value[1],0,data.size.y-1)

func _fire_navigation_restore_stamp() -> Array:
	return [data,data.site,_coordinator,_combat_move_plan,_combat_deployment_plan,get_order_serial(),ranged_order_serial,combat_order,
		cells.duplicate(),moving_to.duplicate(),move_progress.duplicate(),_cell_owners.duplicate(),_reserved_cells.duplicate(),
		_combat_batch_members.duplicate(),_suppress_approaches.duplicate(),_fire_navigation.duplicate()]

func prepare_fire_navigation_restore(saved: Dictionary, registry_candidate: SiteDeploymentReservationRegistry,
		job_tokens: Dictionary, completed_action_end: float) -> Dictionary:
	# Called on the original Army after its ordinary validated restoration. No
	# field, lease, position, batch, or authoritative timer is changed here.
	if data == null or _coordinator == null or registry_candidate == null or not _suppress_approaches.is_empty() \
		or not _fire_navigation.is_empty(): return SiteRuntime.fail("BUSY")
	if not is_finite(completed_action_end) or completed_action_end < 0.0: return SiteRuntime.fail("INVALID_FIRE_ACTION_END")
	if not _fire_navigation_integer(saved.get("version"),1,1) or not _fire_navigation_integer(saved.get("team_id"),team_id,team_id) \
		or not _fire_navigation_integer(saved.get("serial"),get_order_serial(),get_order_serial()) \
		or not _fire_navigation_integer(saved.get("ranged_serial")) \
		or not _fire_navigation_integer(saved.get("hazard_epoch")) \
		or not _fire_navigation_number(saved.get("threat_last_end"),-1.0,completed_action_end) \
		or not saved.get("work") is Array or not saved.get("hazard") is Dictionary \
		or not saved.get("batches") is Array or not saved.get("deployment") is Dictionary:
		return SiteRuntime.fail("INVALID_FIRE_NAVIGATION")
	if saved.work.size() > combat_units.size() or saved.batches.size() > combat_units.size(): return SiteRuntime.fail("INVALID_FIRE_NAVIGATION")
	var restored_ranged_serial := int(saved.ranged_serial)
	var work := {}
	var required_leases := {}
	for raw: Variant in saved.work:
		if not raw is Dictionary: return SiteRuntime.fail("INVALID_FIRE_WORK_NAVIGATION")
		var row: Dictionary = raw
		if not _fire_navigation_integer(row.get("member_id"),1) or not _fire_navigation_integer(row.get("job_token"),1) \
			or not _fire_navigation_integer(row.get("order_serial"),1) or not _fire_navigation_integer(row.get("ranged_serial")) \
			or not _fire_navigation_integer(row.get("wait_age")) or not _fire_navigation_cell(row.get("slot")) \
			or not row.get("cancelled") is bool or not row.get("reason") is String or str(row.reason).length() > 128:
			return SiteRuntime.fail("INVALID_FIRE_WORK_NAVIGATION")
		var mid := int(row.member_id)
		var index := index_for_identity(mid)
		var slot := Vector2i(int(row.slot[0]),int(row.slot[1]))
		if index < 0 or work.has(mid) or int(job_tokens.get(mid,-1)) != int(row.job_token): return SiteRuntime.fail("STALE_FIRE_WORK_JOB")
		var lease: Variant = registry_candidate.owner_of(slot)
		if not bool(row.cancelled):
			if combat_order != CombatOrder.HOLD or int(row.order_serial) != get_order_serial() or int(row.ranged_serial) != restored_ranged_serial \
				or not is_member(index) or not combat_can_act(index) or is_controlled_person(index) or not garrison_feature_id.is_empty() \
				or _combat_move_plan != null or _combat_deployment_plan != null or _ship_embarked(index) or _siege_crew(index) \
				or _unit_rescues.has(index) or patient_has_rescuer(index) or _combat_action_blocks_step(index) \
				or vehicle_transport != null and vehicle_transport.is_operator(mid): return SiteRuntime.fail("STALE_FIRE_WORK_CONTEXT")
			if lease == null or lease.formation_id != team_id or lease.order_serial != int(row.order_serial) \
				or lease.member_id != mid or lease.role != CombatMovementTypes.CombatDestinationRole.SUPPRESS_WORK:
				return SiteRuntime.fail("STALE_FIRE_WORK_LEASE")
			required_leases[slot] = lease
		elif moving_to[index] == INVALID_CELL or not _combat_batch_members.has(mid): return SiteRuntime.fail("STALE_FIRE_WORK_SETTLING")
		else: lease = null
		work[mid] = {"member_id":mid,"job_token":int(row.job_token),"slot":slot,"order_serial":int(row.order_serial),
			"ranged_order_serial":int(row.ranged_serial),"terrain":data,"site_state":data.site,"registry":registry_candidate,"lease":lease,
			"cancelled":bool(row.cancelled),"reason":str(row.reason),"route":[],"navigation_revision":-1,"proposal_id":-1,
			"next":INVALID_CELL,"wait_age":int(row.wait_age),"route_status":"PENDING"}
	# Every original same-team work lease must have the exact original job.
	for cell: Vector2i in registry_candidate.get_formation_reserved_slots(team_id):
		var lease: Variant = registry_candidate.owner_of(cell)
		if lease.role == CombatMovementTypes.CombatDestinationRole.SUPPRESS_WORK and not required_leases.has(cell): return SiteRuntime.fail("ORPHAN_FIRE_WORK_LEASE")
	var batches := {}
	for raw: Variant in saved.batches:
		if not raw is Dictionary: return SiteRuntime.fail("INVALID_FIRE_BATCH_INTENT")
		var row: Dictionary = raw
		for field: String in ["member_id","serial"]:
			if not _fire_navigation_integer(row.get(field),1): return SiteRuntime.fail("INVALID_FIRE_BATCH_INTENT")
		for field: String in ["ranged_serial"]:
			if not _fire_navigation_integer(row.get(field)): return SiteRuntime.fail("INVALID_FIRE_BATCH_INTENT")
		for field: String in ["path_epoch","assignment_epoch","fire_epoch","work_token"]:
			if not _fire_navigation_integer(row.get(field),-1): return SiteRuntime.fail("INVALID_FIRE_BATCH_INTENT")
		if not _fire_navigation_integer(row.get("order"),FIRE_HAZARD_STEP,CombatOrder.RETURN) \
			or int(row.order) not in [FIRE_HAZARD_STEP,CombatOrder.HOLD,CombatOrder.MOVE,CombatOrder.RETREAT] \
			or not row.get("move_current") is bool or not row.get("deployment_current") is bool or not row.get("profile") is Array:
			return SiteRuntime.fail("INVALID_FIRE_BATCH_INTENT")
		var mid := int(row.member_id)
		var index := index_for_identity(mid)
		if index < 0 or batches.has(mid) or not _combat_batch_members.has(mid) or moving_to[index] == INVALID_CELL \
			or _cell_owners.get(cells[index],-1) != index or _reserved_cells.get(moving_to[index],-1) != index:
			return SiteRuntime.fail("STALE_FIRE_BATCH_CLAIMS")
		var profile: FormationMovementProfile = null
		if not row.profile.is_empty():
			if row.profile.size() != 4 or not _fire_navigation_integer(row.profile[0]) or not _fire_navigation_integer(row.profile[1],0,255) \
				or not row.profile[2] is bool or not _fire_navigation_integer(row.profile[3],1,255): return SiteRuntime.fail("INVALID_FIRE_BATCH_PROFILE")
			profile = FormationMovementProfile.new(int(row.profile[0]),int(row.profile[1]),bool(row.profile[2]),int(row.profile[3]))
		if int(row.order) == CombatOrder.HOLD and (not work.has(mid) or int(work[mid].job_token) != int(row.work_token)):
			return SiteRuntime.fail("ORPHAN_FIRE_WORK_BATCH")
		if int(row.fire_epoch) > int(saved.hazard_epoch) or int(row.order) == FIRE_HAZARD_STEP and int(row.fire_epoch) <= 0:
			return SiteRuntime.fail("INVALID_FIRE_BATCH_EPOCH")
		batches[mid] = {"order":int(row.order),"serial":int(row.serial),"ranged_serial":int(row.ranged_serial),
			"move_plan":_combat_move_plan if bool(row.move_current) else null,"deployment":_combat_deployment_plan if bool(row.deployment_current) else null,
			"movement_profile":profile,"path_epoch":int(row.path_epoch),"assignment_epoch":int(row.assignment_epoch),
			"fire_epoch":int(row.fire_epoch),"work_token":int(row.work_token)}
	if batches.size() != _combat_batch_members.size(): return SiteRuntime.fail("INCOMPLETE_FIRE_BATCH_INTENT")
	for mid: int in work:
		var index := index_for_identity(mid)
		if moving_to[index] != INVALID_CELL and (not batches.has(mid) or int(batches[mid].order) != CombatOrder.HOLD): return SiteRuntime.fail("ORPHAN_FIRE_WORK_CLAIMS")
	var hazard_result := _prepare_fire_hazard_restore(saved.hazard,registry_candidate,required_leases,completed_action_end,restored_ranged_serial)
	if not hazard_result.ok: return hazard_result
	if not hazard_result.state.is_empty() and int(hazard_result.state.epoch) > int(saved.hazard_epoch): return SiteRuntime.fail("INVALID_FIRE_HAZARD_EPOCH")
	var deployment_result := _prepare_fire_deployment_restore(saved.deployment)
	if not deployment_result.ok: return deployment_result
	return {"ok":true,"stamp":_fire_navigation_restore_stamp(),"work":work,"hazard":hazard_result.state,
		"deployment":deployment_result,"batches":batches,"required_leases":required_leases,
		"hazard_epoch":int(saved.hazard_epoch),"threat_last_end":float(saved.threat_last_end),"ranged_serial":restored_ranged_serial}

func _prepare_fire_deployment_restore(saved: Dictionary) -> Dictionary:
	if saved.is_empty(): return {"ok":_combat_deployment_plan == null,"slots":{},"members":{},"capacity":0}
	if _combat_deployment_plan == null or not saved.get("slots") is Array or not saved.get("members") is Array \
		or not _fire_navigation_integer(saved.get("safe_capacity"),0,data.size.x*data.size.y): return SiteRuntime.fail("INVALID_FIRE_DEPLOYMENT")
	var slots := {}
	var members := {}
	if saved.slots.size() > data.size.x*data.size.y or saved.members.size() > combat_units.size(): return SiteRuntime.fail("INVALID_FIRE_DEPLOYMENT")
	for row: Variant in saved.slots:
		if not row is Array or row.size() != 3 or not _fire_navigation_cell([row[0],row[1]]) or not _fire_navigation_integer(row[2]): return SiteRuntime.fail("INVALID_FIRE_DEPLOYMENT")
		var cell := Vector2i(int(row[0]),int(row[1]))
		if slots.has(cell) or _combat_deployment_plan.slot_owner_map.has(cell): return SiteRuntime.fail("INVALID_FIRE_DEPLOYMENT")
		slots[cell] = int(row[2])
	for row: Variant in saved.members:
		if not row is Array or row.size() != 3 or not _fire_navigation_integer(row[0],1) or not _fire_navigation_cell([row[1],row[2]]): return SiteRuntime.fail("INVALID_FIRE_DEPLOYMENT")
		var mid := int(row[0])
		var cell := Vector2i(int(row[1]),int(row[2]))
		if index_for_identity(mid) < 0 or members.has(mid) or not slots.has(cell) or int(slots[cell]) != mid \
			or _combat_deployment_plan.member_slot_map.has(mid): return SiteRuntime.fail("INVALID_FIRE_DEPLOYMENT")
		members[mid] = cell
	return {"ok":true,"slots":slots,"members":members,"capacity":int(saved.safe_capacity)}

func _prepare_fire_hazard_restore(saved: Dictionary, registry: SiteDeploymentReservationRegistry,
		required_leases: Dictionary, completed_action_end: float, restored_ranged_serial: int) -> Dictionary:
	if saved.is_empty(): return {"ok":true,"state":{}}
	if not _fire_navigation_integer(saved.get("serial"),get_order_serial(),get_order_serial()) \
		or not _fire_navigation_integer(saved.get("ranged_serial"),restored_ranged_serial,restored_ranged_serial) \
		or not _fire_navigation_integer(saved.get("order"),combat_order,combat_order) or not _fire_navigation_integer(saved.get("epoch"),1) \
		or not _fire_navigation_integer(saved.get("replans")) or not _fire_navigation_number(saved.get("last_replan"),0.0,completed_action_end) \
		or not _fire_navigation_number(saved.get("cool_since"),-1.0,completed_action_end) \
		or not saved.get("status") is String or str(saved.status).length()>128 \
		or not saved.get("members") is Array or not saved.get("leases") is Array or not saved.get("unsafe") is Array:
		return SiteRuntime.fail("INVALID_FIRE_HAZARD_INTENT")
	if saved.members.size()>combat_units.size() or saved.leases.size()>combat_units.size() or saved.unsafe.size()>data.size.x*data.size.y: return SiteRuntime.fail("INVALID_FIRE_HAZARD_INTENT")
	var state := {"terrain":data,"site":data.site,"serial":get_order_serial(),"ranged_serial":restored_ranged_serial,"order":combat_order,
		"move_plan":_combat_move_plan,"deployment":_combat_deployment_plan,"registry":registry,"epoch":int(saved.epoch),
		"snapshot":{},"revision":-1,"navigation":data.navigation_revision,"assignment":-1,"last_replan":float(saved.last_replan),
		"cool_since":float(saved.cool_since),"members":{},"leases":{},"unsafe":{},"metrics":{},"capacity":{},
		"replans":int(saved.replans),"last_summary":{},"status":str(saved.status)}
	for raw: Variant in saved.leases:
		if not raw is Dictionary or not _fire_navigation_integer(raw.get("member_id"),1) or not _fire_navigation_cell(raw.get("cell")): return SiteRuntime.fail("INVALID_FIRE_ESCAPE_LEASE")
		var mid := int(raw.member_id)
		var cell := Vector2i(int(raw.cell[0]),int(raw.cell[1]))
		var lease: Variant = registry.owner_of(cell)
		if index_for_identity(mid)<0 or state.leases.has(mid) or lease==null or lease.formation_id!=team_id \
			or lease.order_serial!=get_order_serial() or lease.member_id!=mid or lease.role==CombatMovementTypes.CombatDestinationRole.SUPPRESS_WORK: return SiteRuntime.fail("INVALID_FIRE_ESCAPE_LEASE")
		state.leases[mid]=lease
		required_leases[cell]=lease
	for raw: Variant in saved.unsafe:
		if not _fire_navigation_cell(raw): return SiteRuntime.fail("INVALID_FIRE_UNSAFE_SLOT")
		var cell := Vector2i(int(raw[0]),int(raw[1]))
		if state.unsafe.has(cell): return SiteRuntime.fail("INVALID_FIRE_UNSAFE_SLOT")
		state.unsafe[cell]=true
	for raw: Variant in saved.members:
		if not raw is Dictionary: return SiteRuntime.fail("INVALID_FIRE_HAZARD_MEMBER")
		if not _fire_navigation_integer(raw.get("member_id"),1) or not _fire_navigation_cell(raw.get("target"),true) \
			or not _fire_navigation_integer(raw.get("defer_age")) or not _fire_navigation_integer(raw.get("wait_age")) \
			or not _fire_navigation_number(raw.get("retry_at"),0.0,completed_action_end+60.0) \
			or raw.get("policy") not in ["NORMAL","EMERGENCY_ESCAPE"] \
			or raw.get("category") not in ["safe_platform","safe_queue","relocating","trapped","working"] \
			or not raw.get("reason") is String or str(raw.reason).length()>128 \
			or raw.get("response") not in ["NONE","EVACUATING","SUPPRESSING","AVOIDING","TRAPPED"]: return SiteRuntime.fail("INVALID_FIRE_HAZARD_MEMBER")
		var mid := int(raw.member_id)
		var index := index_for_identity(mid)
		var target := Vector2i(int(raw.target[0]),int(raw.target[1]))
		if index<0 or state.members.has(mid): return SiteRuntime.fail("INVALID_FIRE_HAZARD_MEMBER")
		var lease: Variant = registry.owner_of(target) if target!=INVALID_CELL else null
		if target!=INVALID_CELL and lease!=null and (lease.formation_id!=team_id or lease.order_serial!=get_order_serial()): return SiteRuntime.fail("INVALID_FIRE_HAZARD_TARGET")
		if lease!=null: required_leases[target]=lease
		state.members[mid]={"index":index,"target":target,"policy":str(raw.policy),"category":str(raw.category),"response":str(raw.response),
			"reason":str(raw.reason),"defer_age":int(raw.defer_age),"wait_age":int(raw.wait_age),"retry_at":float(raw.retry_at),
			"route":[],"route_stamp":[],"next":INVALID_CELL,"proposal":-1,"lease":lease,"band":0,"role":CombatMovementTypes.CombatDestinationRole.APPROACH_QUEUE}
	return {"ok":true,"state":state}

func can_publish_fire_navigation_restore(prepared: Dictionary, registry: SiteDeploymentReservationRegistry) -> bool:
	if not bool(prepared.get("ok",false)) or not prepared.get("stamp") is Array or prepared.stamp != _fire_navigation_restore_stamp() \
		or _coordinator == null or not is_same(_coordinator.deployment_registry,registry): return false
	for cell: Vector2i in prepared.required_leases:
		if not is_same(registry.owner_of(cell),prepared.required_leases[cell]): return false
	return true

func publish_fire_navigation_restore(prepared: Dictionary, registry: SiteDeploymentReservationRegistry) -> Dictionary:
	if not can_publish_fire_navigation_restore(prepared,registry): return SiteRuntime.fail("STALE_FIRE_RESTORE")
	# Root publishes all prepared original Registry/Army/PersonActions together.
	# After preflight this stage only assigns metadata; no callback or physical
	# movement can fail, and no route search or time interval is replayed.
	_suppress_approaches = prepared.work
	ranged_order_serial = int(prepared.ranged_serial)
	for state: Dictionary in _suppress_approaches.values(): state.registry=registry
	_fire_navigation = prepared.hazard
	if not _fire_navigation.is_empty(): _fire_navigation.registry=registry
	_fire_navigation_epoch = int(prepared.hazard_epoch)
	_fire_threat_last_end = float(prepared.threat_last_end)
	_combat_batch_members = prepared.batches
	if _combat_deployment_plan != null:
		_combat_deployment_plan.fire_suspended_slots=prepared.deployment.slots
		_combat_deployment_plan.fire_suspended_members=prepared.deployment.members
		_combat_deployment_plan.fire_safe_platform_capacity=int(prepared.deployment.capacity)
	return {"ok":true}

func technology_work_consent(person_id: int, purpose: String, controlled_id: int, physical_context: Variant = null) -> Dictionary:
	# Runtime load avoids the existing Army / DutyAI preload dependency cycle.
	var policy: Script = load("res://scripts/terrain_lab/site_duty_ai.gd")
	return policy.technology_work_consent(self, person_id, purpose, controlled_id, physical_context)

func _region_trusted_bind_clear(token: String) -> bool:
	if token.is_empty() or vehicle_transport == null or vehicle_transport.lab == null: return false
	var original: Variant = vehicle_transport.lab
	if not original is TerrainLab or not original.combat_armies.has(self): return false
	var ticket: Dictionary = original._region_owner_bind_tickets.get(token, {})
	if ticket.is_empty() or not ticket.get("data") is TerrainData: return false
	var checked: Dictionary = original._region_bind_ticket_admission(ticket.data, {"region_bind_token": token})
	return checked.get("ok", false) and checked.get("trusted", false)


func duty_resolve_readonly(duty_id: String, physical_owner: Variant = null) -> Dictionary:
	var physical: Variant = self if physical_owner == null else physical_owner
	if physical == self: return duty_resolve(duty_id, true)
	if physical != self and (not physical is CrowdPersonOwner or physical.data != data or int(physical.team_id) != team_id \
		or not physical.crowd_site.owns_original_team(self) or not physical.has_army()): return SiteRuntime.fail("INVALID_OWNER")
	var current: Dictionary = offices
	if current.is_empty():
		current = SiteOffices.default_offices("team", -1, false)
	else:
		if not SiteOffices.validate(current, "team", false): return SiteRuntime.fail("INVALID_OWNER")
		var migration := int(current.version) < SiteOffices.VERSION
		for duty: String in SiteOffices.duty_ids("team"):
			migration = migration or not current.duties.has(duty)
		if migration:
			current = current.duplicate(true)
			if SiteOffices.ensure_catalog(current, "team"): current["revision"] = int(current.revision) + 1
			SiteOffices.upgrade(current)
	var head: int = physical.combat_identity(physical.current_commander) if physical.current_commander >= 0 and physical.command_eligible(physical.current_commander) else -1
	var holder_ok := func(identity: int) -> bool:
		var index: int = physical.index_for_identity(identity)
		var seat := SiteOffices.position_of(current, identity)
		if physical == self:
			return base_command_eligible(index) if SiteOffices.needs_officer(current, seat) else _member_can_serve(index)
		if index < 0 or not physical.is_member(index) or physical.member_gone(index) or not physical.combat_can_act(index): return false
		var source_index: int = index_for_identity(identity)
		if source_index == PLAYER_MEMBER:
			if not physical.actors.has(index) or not is_same(physical.actors[index], player_member): return false
		elif source_index < 0 or not is_member(source_index) or combat_identity(source_index) != identity \
			or not is_same(physical._command_owner(index), self): return false
		return not SiteOffices.needs_officer(current, seat) or garrison_feature_id.is_empty() and str(physical.combat_hot_get(index, &"military_role", "soldier")) == "officer"
	var acting: bool = acting_commander >= 0 if physical == self else head > 0 and (formal_commander < 0 or head != combat_identity(formal_commander))
	return SiteOffices.resolve(current, duty_id, head, holder_ok, acting)
