extends SceneTree
## Formal generated mountain and original 100-person deployment; no fixture terrain edits.

const LAB_SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const PEAK := Vector2i(49, 37)
const FINAL_FACING := Vector2i.UP
const MEMBERS := 100
const STEP := 1.0 / 30.0
const ARRIVAL_SECONDS := 300.0
const STABLE_SECONDS := 5.0
const WALL_SECONDS := 240.0

var _lab: TerrainLab
var _army: TerrainArmy
var _plan: CombatDeploymentPlan
var _members: Array = []
var _tick := 0
var _wall_start := 0
var _previous: Array[Vector2i] = []
var _initial_platform := 0
var _initial_queue := 0
var _enemy_cells: Array[Vector2i] = []
var _initial_hp := {}
var _advance_us: Array[int] = []
var _profile_previous: Dictionary = {}
var _probe_last_cells: Dictionary = {}
var _probe_last_targets: Dictionary = {}
var _probe_last_retries: Dictionary = {}
var _probe_last_observed: Dictionary = {}
var _probe_last_rank: Dictionary = {}
var _probe_last_checkpoint: Dictionary = {}
var _probe_counts: Dictionary = {}
var _same_cell_observed_diag_buckets: Dictionary = {}

func _initialize() -> void:
	_wall_start = Time.get_ticks_msec()
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if not condition:
		_diagnose("FAIL")
		push_error("FORMAL MOUNTAIN FAIL simulated=%.3fs wall=%.3fs: %s" % [_tick * STEP, _wall_seconds(), message])
		if is_instance_valid(_lab): _lab.queue_free()
		quit(1)
	return condition

func _run() -> void:
	if not _require(DisplayServer.get_name() == "headless", "Use the bounded headless verifier for this simulation test"): return
	_lab = LAB_SCENE.instantiate() as TerrainLab
	_lab.pause_when_unfocused = false
	root.add_child(_lab)
	current_scene = _lab
	# _ready normally creates this preset but may load a user save. Explicitly bind
	# a fresh generated Site so previous runs cannot choose the acceptance terrain.
	_lab.set_process(false)
	_lab.site_controller.set_process(false)
	for actor: TerrainTestCharacter in _lab.combat_actors:
		actor.set_process(false)
	for team: TerrainArmy in _lab.combat_armies:
		team.set_process(false)
	var data := TerrainGenerator.generate(TerrainPreset.Kind.TERRACED_HIGHLAND, 12345)
	SiteEnvironment.initialize(data, "formal-mountain-arrival-fixture")
	_lab.bind_terrain(data)
	if not _require(_lab.terrain == data and data.preset == TerrainPreset.Kind.TERRACED_HIGHLAND and data.seed_value == 12345 and data.is_walkable(PEAK), "Fresh formal mountain Site or peak differs from the required fixture"): return
	var original_heights := data.height_levels.duplicate()
	var original_blockers := data.static_blocked.duplicate()
	var original_ramps := data.ramp_edges.duplicate()
	# Preserve the original default friendly starting formation. Choose the other
	# 100-person formation on verified, unchanged ground away from its mountain route.
	var default_layout: Dictionary = _lab.find_melee_trial_layout(MEMBERS, MEMBERS)
	if not _require(not default_layout.is_empty(), "Generated mountain has no default legal 100-person starting formation"): return
	var friendly_cells: Array[Vector2i] = default_layout.friendly
	var route := Transit.build_macro_path(data, friendly_cells[0], PEAK)
	if not _require(not route.is_empty(), "Default friendly start has no static mountain route"): return
	var enemy_spawn := _find_distant_enemy_spawn(friendly_cells, route)
	if not _require(enemy_spawn != TerrainArmy.INVALID_CELL, "No legal distant 100-person enemy formation clear of the mountain route; terrain remains untouched"): return
	var config := {"friendly_count": MEMBERS, "enemy_count": MEMBERS,
		"friendly_attack": false, "enemy_attack": false, "enemy_role": "logistics",
		"friendly_spawn": friendly_cells[0], "enemy_spawn": enemy_spawn}
	print("FORMAL_MOUNTAIN_TRIAL_CONFIG ", config, " omitted fields retain formal defaults; no terrain or faction changes")
	var result: Dictionary = _lab.start_melee_trial(config)
	if not _require(bool(result.get("ok", false)), "Formal start_melee_trial failed: " + str(result)): return
	_army = _lab.army
	if not _require(_army.combat_units.size() == MEMBERS and _lab.opposing_army.combat_units.size() == MEMBERS, "Default deployment must preserve both original 100-person armies"): return
	_army.combat_profile_enabled = true
	_enemy_cells = _lab.opposing_army.cells.duplicate()
	for team: TerrainArmy in [_army, _lab.opposing_army]:
		for index in range(MEMBERS):
			_initial_hp[team.combat_identity(index)] = float(team.combat_hot_get(index, &"hp"))
	_army.reset_movement_metrics()
	var order: Dictionary = _army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, PEAK, -1, FINAL_FACING)
	if not _require(bool(order.get("ok", false)) and _army.combat_order == TerrainArmy.CombatOrder.MOVE, "Formal MOVE rejected: " + str(order)): return
	_army.get_active_move_plan().set_meta("_transit_soft_debug_enabled", true)
	_plan = _army.get_active_deployment_plan()
	if not _require(_plan != null and _plan.member_slot_map.size() == MEMBERS and _plan.final_facing == FINAL_FACING, "The order must automatically assign all 100 members and the requested facing"): return
	_members = _plan.member_slot_map.keys()
	_initial_platform = _plan.platform_slots.size()
	_initial_queue = _plan.approach_queue_slots.size()
	_previous = _army.cells.duplicate()
	# Verify against the real accepted command as well as the pre-deployment route.
	var accepted_route: Array[Vector2i] = _army.get_active_move_plan().macro_path
	var middle: int = floori(accepted_route.size() / 2.0)
	print("FORMAL_MOUNTAIN_ROUTE size=", accepted_route.size(),
		" first=", accepted_route.slice(0, mini(12, accepted_route.size())),
		" middle=", accepted_route.slice(maxi(0, middle - 6), mini(accepted_route.size(), middle + 6)),
		" last=", accepted_route.slice(maxi(0, accepted_route.size() - 12)),
		" ingress=", _plan.ingress_cell, " buffer=", _plan.ingress_buffer_cells)
	for enemy_cell: Vector2i in _enemy_cells:
		for path_cell: Vector2i in accepted_route:
			if not _require(_distance(enemy_cell, path_cell) > 8, "Distant enemy fixture obstructs the actual accepted mountain route"): return
		for slot: Vector2i in _plan.member_slot_map.values():
			if not _require(_distance(enemy_cell, slot) > 8, "Distant enemy fixture threatens or obstructs a final slot"): return
	if not _check_assignments_and_leases(): return
	print("FORMAL_MOUNTAIN_SETUP scene=TerrainLab.tscn preset=TERRACED_HIGHLAND seed=12345 peak=", PEAK,
		" requested_members=100 platform=", _initial_platform, " queue=", _initial_queue,
		" final_facing=", FINAL_FACING, " MOVE_DURATION=", TerrainArmy.MOVE_DURATION,
		" action_step=", STEP, " max_simulated_seconds=", ARRIVAL_SECONDS,
		" enemy_order=HOLD enemy_role=logistics self_defence=unchanged terrain_edits=false")
	_diagnose("START")
	var arrived_at := -1.0
	for step in range(roundi(ARRIVAL_SECONDS / STEP)):
		if not _advance(): return
		if _tick % 300 == 0:
			if not _check_assignments_and_leases(): return
			_report_advance_cost("PROGRESS")
			_report_target_probe("PROGRESS")
			_diagnose("PROGRESS")
			_diagnose_stretch_front()
			_diagnose_cursor_157_guard()
			if _tick == 600 or _tick == 2400 or _tick == 3000 or _tick == 3300 or _tick == 4800 or _tick == 5100 or _tick == 6000 or _tick == 7200 or _tick == 7500 or _tick == 8100:
				_diagnose_targets()
			await process_frame
		if _army.combat_order != TerrainArmy.CombatOrder.MOVE:
			if not _check_final(): return
			arrived_at = _tick * STEP
			break
	if not _require(arrived_at >= 0.0, "Not all original automatically assigned members reached final HOLD within 300 simulated seconds"): return
	var final_cells: Array[Vector2i] = _army.cells.duplicate()
	var final_slots: Dictionary = _plan.member_slot_map.duplicate()
	for step in range(roundi(STABLE_SECONDS / STEP)):
		if not _advance(): return
		if not _require(_army.cells == final_cells and _plan.member_slot_map == final_slots, "Final cells or assignment drifted during five simulated seconds"): return
		if not _check_final(): return
	if not _require(data.height_levels == original_heights and data.static_blocked == original_blockers and data.ramp_edges == original_ramps, "Formal mountain geometry changed during the movement acceptance run"): return
	_diagnose("FINAL")
	_report_advance_cost("FINAL")
	_report_target_probe("FINAL")
	print("COMBAT MOVEMENT FORMAL MOUNTAIN ARRIVAL PASS: arrived=", arrived_at, "s stable=", STABLE_SECONDS,
		"s members=100 platform=", _initial_platform, " queue=", _initial_queue, " wall=", _wall_seconds(), "s")
	_lab.clear_army()
	_lab.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _advance() -> bool:
	if not _require(_wall_seconds() < WALL_SECONDS, "240-second wall-clock deadline reached; investigate the bounded diagnostics"): return false
	# This runs real fatigue, movement arbitration, original step progress,
	# coordinator completion, combat contacts and order settlement in their Lab order.
	var advance_started := Time.get_ticks_usec()
	var finalize_us_before: int = int(_army.combat_profile_usec.get("move_cursor_finalize", 0))
	_lab._advance_combat(STEP)
	_advance_us.append(Time.get_ticks_usec() - advance_started)
	_tick += 1
	_sample_target_probe(int(_army.combat_profile_usec.get("move_cursor_finalize", 0)) > finalize_us_before)
	if not _require(_lab.opposing_army.cells == _enemy_cells, "Held distant enemy moved and contaminated the pathfinding fixture"): return false
	for team: TerrainArmy in [_army, _lab.opposing_army]:
		for index in range(MEMBERS):
			if not _require(team.combat_can_act(index) and float(team.combat_hot_get(index, &"hp")) == float(_initial_hp[team.combat_identity(index)]), "Casualty or combat damage contaminated the isolated movement case; member count is not reduced"): return false
	var sources := {}
	var claims := {}
	for index in range(MEMBERS):
		var identity := _army.combat_identity(index)
		var cell: Vector2i = _army.cells[index]
		if not _require(_members.has(identity) and _army.is_member(index) and not _army.member_gone(index), "An original assigned person was lost; the test must not reduce its denominator"): return false
		if not _require(not _lab.opposing_army._cell_owners.has(cell), "Friendly physical occupancy overlapped the distant enemy"): return false
		if not _require(_army.data.is_walkable(cell) and not sources.has(cell) and _army._cell_owners.get(cell, -1) == index, "Illegal, duplicate or unowned source cell for person %d at %s" % [identity, cell]): return false
		sources[cell] = true
		if cell != _previous[index] and not _require(_army.data.can_step(_previous[index], cell), "Person %d skipped a legal physical edge: %s -> %s" % [identity, _previous[index], cell]): return false
		var target: Vector2i = _army.moving_to[index]
		if target != TerrainArmy.INVALID_CELL:
			if not _require(_army.data.can_step(cell, target) and not claims.has(target) and not _lab.opposing_army._cell_owners.has(target), "Illegal, blocked or duplicate in-flight destination for person " + str(identity)): return false
			claims[target] = true
	_previous = _army.cells.duplicate()
	return true

func _sample_target_probe(finalized_this_tick: bool) -> void:
	var move: CombatMovePlan = _army.get_active_move_plan()
	if move == null or _plan == null:
		return
	for mid in [101, 91]:
		var index: int = _army.index_for_identity(mid)
		if index < 0:
			continue
		var cell: Vector2i = _army.cells[index]
		var resolved: Dictionary = Destination.resolve_member_target(move, _plan, mid, cell)
		var target: Vector2i = resolved.get("target", cell)
		var retry: int = int(move.member_route_retry_count.get(mid, 0))
		var observed: float = float(move.member_observed_path_s.get(mid, -1.0))
		var rank: int = int(move.member_sequence_rank.get(mid, -1))
		var cell_unchanged: bool = _probe_last_cells.has(mid) and _probe_last_cells[mid] == cell
		var checkpoint: Vector2i = move.member_checkpoint_cell.get(mid, Vector2i(-1, -1))
		var checkpoint_confirmed: bool = cell_unchanged and _probe_last_checkpoint.get(mid, Vector2i(-1, -1)) == cell and checkpoint == cell
		var counts: Dictionary = _probe_counts.get(mid, {"cell_changes": 0, "target_changes": 0, "target_changes_same_cell": 0, "observed_changes_same_cell": 0, "observed_changes_confirmed_same_checkpoint": 0, "rank_changes_same_cell": 0, "moving_samples": 0, "retry_increases": 0, "current_route_samples": 0, "samples": 0})
		if _probe_last_cells.has(mid) and not cell_unchanged:
			counts["cell_changes"] = int(counts["cell_changes"]) + 1
		if _probe_last_targets.has(mid) and _probe_last_targets[mid] != target:
			counts["target_changes"] = int(counts["target_changes"]) + 1
			if cell_unchanged:
				counts["target_changes_same_cell"] = int(counts["target_changes_same_cell"]) + 1
		if cell_unchanged and _probe_last_observed.has(mid) and not is_equal_approx(float(_probe_last_observed[mid]), observed):
			counts["observed_changes_same_cell"] = int(counts["observed_changes_same_cell"]) + 1
			if checkpoint_confirmed:
				counts["observed_changes_confirmed_same_checkpoint"] = int(counts["observed_changes_confirmed_same_checkpoint"]) + 1
			var bucket := floori(_tick / 300.0)
			if move.phase == 0 and bucket < 24 and not _same_cell_observed_diag_buckets.has(bucket):
				_same_cell_observed_diag_buckets[bucket] = true
				print("FORMAL_MOUNTAIN_SAME_CELL_OBS tick=", _tick, " mid=", mid, " cell=", cell,
					" phase=", move.phase, " path_epoch=", move.path_epoch,
					" terrain_rev=", move.terrain_revision, "/", _army.data.navigation_revision,
					" prior_checkpoint=", _probe_last_checkpoint.get(mid, Vector2i(-1, -1)),
					" checkpoint=", checkpoint, " confirmed_same_checkpoint=", checkpoint_confirmed,
					" prior_s=", _probe_last_observed[mid], " observed_s=", observed,
					" prior_rank=", _probe_last_rank.get(mid, -1), " rank=", rank,
					" finalized_this_tick=", finalized_this_tick,
					" projection_key=", move.get_meta("_observed_projection_key", []))
		if cell_unchanged and _probe_last_rank.has(mid) and int(_probe_last_rank[mid]) != rank:
			counts["rank_changes_same_cell"] = int(counts["rank_changes_same_cell"]) + 1
		if _army.moving_to[index] != TerrainArmy.INVALID_CELL:
			counts["moving_samples"] = int(counts["moving_samples"]) + 1
		if _probe_last_retries.has(mid):
			counts["retry_increases"] = int(counts["retry_increases"]) + maxi(0, retry - int(_probe_last_retries[mid]))
		if move.is_member_route_current(mid, target):
			counts["current_route_samples"] = int(counts["current_route_samples"]) + 1
		counts["samples"] = int(counts["samples"]) + 1
		_probe_counts[mid] = counts
		_probe_last_cells[mid] = cell
		_probe_last_targets[mid] = target
		_probe_last_retries[mid] = retry
		_probe_last_observed[mid] = observed
		_probe_last_rank[mid] = rank
		_probe_last_checkpoint[mid] = checkpoint

func _report_target_probe(label: String) -> void:
	var move: CombatMovePlan = _army.get_active_move_plan()
	print("FORMAL_MOUNTAIN_TARGET_CHURN ", label, " simulated=", _tick * STEP, " per_10s=", _probe_counts,
		" soft_reject_cumulative=", move.get_meta("_transit_soft_reject_counts", {}) if move != null else {})
	_probe_counts.clear()

func _report_advance_cost(label: String) -> void:
	if _advance_us.is_empty():
		return
	var recent := _advance_us.slice(maxi(0, _advance_us.size() - 300), _advance_us.size())
	recent.sort()
	var profile_delta: Dictionary = {}
	for key in ["move_astar", "move_route_cache", "move_transit_slots", "move_phase", "move_cursor_finalize"]:
		var cumulative := int(_army.combat_profile_usec.get(key, 0))
		profile_delta[key] = cumulative - int(_profile_previous.get(key, 0))
		_profile_previous[key] = cumulative
	print("FORMAL_MOUNTAIN_COST ", label, " simulated=", _tick * STEP,
		" advance_us_p50=", recent[floori(float(recent.size()) / 2.0)],
		" p95=", recent[mini(recent.size() - 1, ceili(float(recent.size()) * 0.95) - 1)],
		" max=", recent[-1], " measured_steps=", recent.size(),
		" move_stage_us_10s=", profile_delta)

func _check_assignments_and_leases() -> bool:
	if not _require(_army.get_active_deployment_plan() == _plan and _plan.member_slot_map.size() == MEMBERS and _plan.slot_owner_map.size() == MEMBERS, "The original order lost its 100 unique final assignments"): return false
	if not _require(_plan.platform_slots.size() == _initial_platform and _plan.approach_queue_slots.size() == _initial_queue, "The automatically selected platform/queue capacity changed"): return false
	var registry := _lab.combat_movement_coordinator.deployment_registry
	var reserved: Array[Vector2i] = registry.get_formation_reserved_slots(_army.team_id)
	if not _require(reserved.size() == MEMBERS, "Every assigned final must retain one deployment lease"): return false
	for identity: int in _members:
		var slot: Vector2i = _plan.get_slot_for_member(identity)
		if not _require(_army.data.is_walkable(slot) and _plan.slot_owner_map.get(slot, -1) == identity and reserved.has(slot), "Final assignment lost its unique reverse owner or registry entry for person " + str(identity)): return false
		var lease = registry.owner_of(slot)
		if not _require(lease != null and lease.formation_id == _army.team_id and lease.order_serial == _plan.order_serial and lease.cell == slot, "Wrong or stale deployment lease at " + str(slot)): return false
	return true

func _check_final() -> bool:
	if not _require(_army.combat_order == TerrainArmy.CombatOrder.HOLD and _army.command_status.begins_with("已抵達"), "MOVE aborted or did not settle into successful HOLD: " + _army.command_status): return false
	if not _check_assignments_and_leases(): return false
	if not _require(Destination.is_settled(_plan, _army.get_active_members_occupancy()), "Every assigned platform and queue member must occupy its exact final slot"): return false
	if not _require(_army.get_active_movement_claims().is_empty() and _lab.combat_movement_coordinator.get_inflight_batches_for_formation(_army).is_empty(), "Final HOLD retained physical destination claims or a completion batch"): return false
	for identity: int in _members:
		var index := _army.index_for_identity(identity)
		if not _require(index >= 0 and _army.cells[index] == _plan.get_slot_for_member(identity) and _army.moving_to[index] == TerrainArmy.INVALID_CELL and _army.facing[index] == FINAL_FACING, "Final physical cell, in-flight state or facing differs for person " + str(identity)): return false
	return true

func _diagnose(stage: String) -> void:
	if not is_instance_valid(_army):
		print("FORMAL_MOUNTAIN_", stage, " before army deployment; wall=", _wall_seconds())
		return
	var move: CombatMovePlan = _army.get_active_move_plan()
	var unsettled: Array[String] = []
	var settled := 0
	if _plan != null:
		for identity: int in _members:
			var index := _army.index_for_identity(identity)
			var slot: Vector2i = _plan.get_slot_for_member(identity)
			if index >= 0 and _army.cells[index] == slot and _army.moving_to[index] == TerrainArmy.INVALID_CELL:
				settled += 1
			elif unsettled.size() < 12:
				unsettled.append("%d cell=%s final=%s moving=%s p=%.3f route=%d ever=%s pending=%s retry=%d" % [identity,
					str(_army.cells[index] if index >= 0 else TerrainArmy.INVALID_CELL), str(slot),
					str(_army.moving_to[index] if index >= 0 else TerrainArmy.INVALID_CELL),
					_army.move_progress[index] if index >= 0 else -1.0,
					int(move.member_route_status.get(identity, -1)) if move != null else -1,
					str(_plan.ever_admitted_platform_member_ids.has(identity)), str(_plan.pending_platform_member_ids.has(identity)),
					int(move.member_route_retry_count.get(identity, 0)) if move != null else 0])
	print("FORMAL_MOUNTAIN_", stage, " simulated=", _tick * STEP, " wall=", _wall_seconds(), " order=", _army.combat_order,
		" phase=", move.phase if move != null else -1, " cursor=", move.macro_cursor if move != null else -1,
		" route_size=", move.macro_path.size() if move != null else -1,
		" path_epoch=", move.path_epoch if move != null else -1,
		" replans=", move.macro_replan_count if move != null else -1,
		" stall_sec=", move.active_stall_total_sec if move != null else -1.0,
		" recovery_stage=", move.recovery_stage if move != null else -1,
		" median_highwater=", move.previous_median_path_s if move != null else -1.0,
		" upper_quartile_highwater=", move.previous_upper_quartile_path_s if move != null else -1.0,
		" settled=", settled, "/100 claims=", _army.get_active_movement_claims().size(),
		" pending=", _plan.pending_platform_member_ids.size() if _plan != null else -1,
		" never_crossed=", Destination._never_crossed_platform_count(_plan, _army.get_active_members_occupancy()) if _plan != null else -1,
		" ever_pending=", _count_ever_pending(),
		" status=", _army.command_status,
		" metrics=", _army.get_movement_metrics(), " unresolved_max12=", unsettled)

func _count_ever_pending() -> int:
	if _plan == null:
		return 0
	var count := 0
	for mid in _plan.pending_platform_member_ids:
		if _plan.ever_admitted_platform_member_ids.has(mid):
			count += 1
	return count

func _diagnose_stretch_front() -> void:
	var move: CombatMovePlan = _army.get_active_move_plan()
	if move == null or move.macro_path.size() < 2 or move.phase != CombatMovementTypes.CombatMovePhase.TRANSIT:
		return
	var occupancy: Dictionary = _army.get_active_members_occupancy()
	var projected: Array[int] = []
	for mid in _army._get_active_member_ids():
		if occupancy.has(mid):
			projected.append(int(move.member_projected_path_k.get(mid, 0)))
	if projected.is_empty():
		return
	projected.sort()
	var p25_k: int = projected[floori(float(projected.size()) * 0.25)]
	var current_k: int = move.macro_cursor
	var candidate_k: int = mini(move.macro_path.size() - 1, current_k + 1)
	var convoy_width: int = clampi(move.current_width, 1, 4)
	var profile: FormationMovementProfile = _army.get_formation_movement_profile()
	for k in range(maxi(0, p25_k), candidate_k + 1):
		var path_cell: Vector2i = move.macro_path[k]
		var forward := Vector2i.RIGHT
		if k + 1 < move.macro_path.size():
			forward = move.macro_path[k + 1] - path_cell
		elif k > 0:
			forward = path_cell - move.macro_path[k - 1]
		convoy_width = mini(convoy_width, Transit.detect_corridor_width(_army.data, path_cell, forward, profile))
		if convoy_width == 1:
			break
	var expected_gap: int = ceili(float(projected.size()) * 0.75 / float(maxi(1, convoy_width)))
	var physical_limit: int = ceili(float(projected.size()) / float(maxi(1, convoy_width))) + _army.FORMATION_STRETCH_SLACK
	var lookahead: int = clampi(maxi(Transit.MIN_TRANSIT_LOOKAHEAD_ROWS, move.current_width), Transit.MIN_TRANSIT_LOOKAHEAD_ROWS, Transit.MAX_TRANSIT_LOOKAHEAD_ROWS)
	var saturated_k: int = mini(move.macro_path.size() - 1, current_k + lookahead)
	var rows: Array[String] = []
	for row_k in [saturated_k, maxi(0, saturated_k - 1)]:
		var row_cells: Array[Vector2i] = Transit._get_row_cross_section(move, row_k, _army.data, profile, clampi(move.current_width, 1, 4))
		var occupants: Array[String] = []
		for mid in occupancy:
			var cell: Vector2i = occupancy[mid]
			if cell not in row_cells:
				continue
			var index: int = _army.index_for_identity(mid)
			occupants.append("%d@%s owner=%s checkpoint=%s/%s best=%s observed=%s moving=%s" % [mid, cell,
				_army._cell_owners.get(cell, -1) == index, move.member_checkpoint_cell.get(mid, TerrainArmy.INVALID_CELL),
				move.member_checkpoint_path_k.get(mid, -1), move.member_checkpoint_best_k.get(mid, -1),
				move.member_observed_path_k.get(mid, -1), _army.moving_to[index]])
		rows.append("k=%d cells=%s occupants=%s" % [row_k, row_cells, occupants])
	print("FORMAL_MOUNTAIN_STRETCH_FRONT tick=", _tick, " cursor=", current_k, " candidate=", candidate_k,
		" p25=", p25_k, " convoy_width=", convoy_width, " expected_gap=", expected_gap,
		" actual_gap=", candidate_k - p25_k, " physical_limit=", physical_limit,
		" saturated_k=", saturated_k, " rows=", rows)

func _diagnose_cursor_157_guard() -> void:
	var move: CombatMovePlan = _army.get_active_move_plan()
	if move == null or move.macro_cursor != 157 or _tick < 3300 or _tick > 4500 or move.macro_path.size() <= 159:
		return
	var grid: Object = _army._coordinator.movement_reservation_grid if _army._coordinator != null else null
	var registry: Object = _army._coordinator.deployment_registry if _army._coordinator != null else null
	var fid := _army.try_get_formation_id()
	if fid <= 0:
		fid = _army.team_id
	var profile: FormationMovementProfile = _army.get_formation_movement_profile()
	var row: Array[String] = []
	for k in [157, 158, 159]:
		var cell: Vector2i = move.macro_path[k]
		var index := int(_army._cell_owners.get(cell, -1))
		var mid := _army.combat_identity(index) if index >= 0 else -1
		row.append("k%d cell=%s owner_index=%d mid=%d grid_owner=%s claim=%s lease=%s observed=%s checkpoint=%s moving=%s" % [
			k, cell, index, mid, grid.initial_occupancy.get(cell, -1) if grid != null else -1,
			grid.blocked_destinations.has(cell) if grid != null else false,
			registry.is_slot_reserved(cell, fid) if registry != null else false,
			move.member_observed_path_k.get(mid, -1), move.member_checkpoint_path_k.get(mid, -1),
			_army.moving_to[index] if index >= 0 else TerrainArmy.INVALID_CELL])
	var rear_cell: Vector2i = move.macro_path[157]
	var front_cell: Vector2i = move.macro_path[158]
	var empty_cell: Vector2i = move.macro_path[159]
	var rear_index := int(_army._cell_owners.get(rear_cell, -1))
	var front_index := int(_army._cell_owners.get(front_cell, -1))
	var rear_mid := _army.combat_identity(rear_index) if rear_index >= 0 else -1
	var front_mid := _army.combat_identity(front_index) if front_index >= 0 else -1
	var resolved: Dictionary = Destination.resolve_member_target(move, _plan, front_mid, front_cell) if front_index >= 0 else {}
	var guards := {
		"phase_transit": move.phase == CombatMovementTypes.CombatMovePhase.TRANSIT,
		"unique_cells": move.macro_path.count(rear_cell) == 1 and move.macro_path.count(front_cell) == 1 and move.macro_path.count(empty_cell) == 1,
		"rear_to_front_static": Transit._can_profile_step(_army.data, rear_cell, front_cell, profile),
		"front_to_empty_static": Transit._can_profile_step(_army.data, front_cell, empty_cell, profile),
		"front_width_one": Transit.detect_corridor_width(_army.data, front_cell, empty_cell - front_cell, profile) == 1,
		"two_owners": rear_index >= 0 and front_index >= 0 and rear_index != front_index,
		"rear_authority": rear_index >= 0 and _army.cells[rear_index] == rear_cell,
		"front_authority": front_index >= 0 and _army.cells[front_index] == front_cell,
		"rear_can_act": rear_index >= 0 and _army.is_member(rear_index) and _army.combat_can_act(rear_index) and _army.moving_to[rear_index] == TerrainArmy.INVALID_CELL,
		"front_can_act": front_index >= 0 and _army.is_member(front_index) and _army.combat_can_act(front_index) and _army.moving_to[front_index] == TerrainArmy.INVALID_CELL,
		"rear_observed": rear_index >= 0 and int(move.member_observed_path_k.get(rear_mid, -1)) >= 157,
		"front_observed": front_index >= 0 and int(move.member_observed_path_k.get(front_mid, -1)) >= 158,
		"front_flow_wait": resolved.get("target", TerrainArmy.INVALID_CELL) == front_cell and resolved.get("wait_reason", "") == "FLOW_WAIT",
		"empty_army": not _army._cell_owners.has(empty_cell),
		"empty_grid": grid == null or not grid.initial_occupancy.has(empty_cell),
		"unclaimed": grid == null or not grid.blocked_destinations.has(empty_cell),
		"unreserved": not _army._reserved_cells.has(empty_cell),
		"foreign_lease_free": registry == null or not registry.is_slot_reserved(empty_cell, fid),
		"external_free": front_index >= 0 and not _army._is_external_cell(empty_cell, front_mid),
		"helper": _army._front_has_one_step_physical_pair(157),
	}
	print("FORMAL_MOUNTAIN_CURSOR_157_GUARD tick=", _tick, " rows=", row, " front_resolved=", resolved, " guards=", guards)

func _diagnose_targets() -> void:
	var move: CombatMovePlan = _army.get_active_move_plan()
	var first_three: Array[String] = []
	for identity: int in _members.slice(0, 3):
		var index := _army.index_for_identity(identity)
		var here: Vector2i = _army.cells[index]
		first_three.append("%d cell=%s observed=%s path_s=%s soft=%s resolved=%s" % [identity,
			str(here), str(move.member_observed_path_s.get(identity, null)),
			str(move.member_path_s.get(identity, null)),
			str(move.member_transit_slots.get(identity, null)),
			str(Destination.resolve_member_target(move, _plan, identity, here))])
	var progress: Array[float] = []
	var ranked: Array = []
	for identity: int in _members:
		var observed: float = float(move.member_observed_path_s.get(identity, -1.0))
		progress.append(observed)
		ranked.append({"identity": identity, "observed": observed})
	progress.sort()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.observed) > float(b.observed))
	var lead: Array[String] = []
	for entry: Dictionary in ranked.slice(0, 8):
		var identity: int = entry.identity
		var index := _army.index_for_identity(identity)
		var here: Vector2i = _army.cells[index]
		lead.append("%d@%s observed=%s soft=%s resolved=%s" % [identity, str(here),
			str(entry.observed), str(move.member_transit_slots.get(identity, null)),
			str(Destination.resolve_member_target(move, _plan, identity, here))])
	var center: Variant = null
	if move.macro_cursor >= 0 and move.macro_cursor < move.macro_path.size():
		center = move.macro_path[move.macro_cursor]
	print("FORMAL_MOUNTAIN_TARGETS tick=", _tick, " cursor_cell=", center,
		" width=", move.current_width, " staging=", move.pre_route_staging_slots.size(),
		" p25=", progress[25], " p50=", progress[50], " p75=", progress[75], " p90=", progress[90], " max=", progress[-1],
		" first=", first_three, " lead=", lead)

func _wall_seconds() -> float:
	return float(Time.get_ticks_msec() - _wall_start) / 1000.0

func _find_distant_enemy_spawn(friendly_cells: Array[Vector2i], route: Array[Vector2i]) -> Vector2i:
	var protected := {}
	var anchors: Array[Vector2i] = friendly_cells.duplicate()
	anchors.append_array(route)
	for anchor: Vector2i in anchors:
		for dx in range(-16, 17):
			for dy in range(-16 + absi(dx), 17 - absi(dx)):
				protected[anchor + Vector2i(dx, dy)] = true
	# Descending coordinates give a reproducible far-side choice. Legality and
	# connectivity come from the original formal deployment validator.
	for y in range(_lab.terrain.size.y - 10, 0, -1):
		for x in range(_lab.terrain.size.x - 10, 0, -1):
			var anchor := Vector2i(x, y)
			var cells: Array[Vector2i] = _lab._melee_trial_formation(anchor, MEMBERS, false)
			if _lab._melee_trial_formation_legal(cells, protected): return anchor
	return TerrainArmy.INVALID_CELL

func _distance(first: Vector2i, second: Vector2i) -> int:
	return absi(first.x - second.x) + absi(first.y - second.y)
