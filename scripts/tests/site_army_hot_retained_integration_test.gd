extends SceneTree

const OUTPUT := "res://output/site_army_5k_hot_close_20260926/hot_retained_integration_smoke.json"

func _initialize() -> void:
	_run.call_deferred()

func _state(view: Node2D) -> PackedByteArray:
	var rows := {}
	var row_keys: Array = view._rows.keys()
	row_keys.sort()
	for row: int in row_keys: rows[row] = view._rows[row]
	var runs := {}
	var keys: Array = view._batches.keys()
	keys.sort()
	for key: Vector2i in keys:
		var node: MultiMeshInstance2D = view._batches[key]
		if node.visible: runs[key] = [node.multimesh.buffer, node.multimesh.custom_aabb]
	return var_to_bytes([view._positions, view._sequence, view._frames, view._page,
		view._palette, rows, runs, view.rendered_count, view.active_batches])

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _compare_with_full(army: TerrainArmy, label: String) -> bool:
	var retained := _state(army._batch_view)
	army._visual_full_dirty = true
	army._visual_dirty = true
	army.advance_frame(0.0)
	if retained != _state(army._batch_view):
		_fail("Retained/full presentation mismatch at " + label)
		return false
	return true

func _cached_clock_matches(army: TerrainArmy, index: int, label: String, require_distinct_page: bool = false) -> bool:
	var pose := army._exchange_visual_pose(index)
	var clip: String = army._combat_clip(index, pose)
	var direction: String = army._soldier_direction_id(army._exchange_visual_facing(index, pose))
	var expected := float(army._combat_bake.contact_clocks[clip][direction][1])
	var cached := float(army._batch_view.retained_source_duration(index))
	var page: Dictionary = army._batch_view._pages[army._batch_view._page[index]]
	var samples: Array = page.samples[army._batch_view._sequence[index]]
	if cached != expected or (require_distinct_page and is_equal_approx(expected, float(samples[0].duration))):
		_fail("Retained authored clock mismatch at %s: cached=%s expected=%s page=%s" % [label, cached, expected, samples[0].duration])
		return false
	return true

func _run() -> void:
	create_timer(25.0).timeout.connect(func() -> void: _fail("Hot retained integration timed out"))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "army-hot-retained-integration")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	army.roster_size = 64
	army.native_hot_enabled = true
	army.exchange_enabled = true
	var cells: Array[Vector2i] = []
	for index in range(64): cells.append(Vector2i(20 + index % 8, 20 + floori(float(index) / 8.0)))
	if not army.deploy_at(data, null, null, cells) or not army.enable_combat(false):
		_fail("Formal deploy/enable failed")
		return
	# Headless deliberately skips visual-source startup. Prime the same baked
	# presenter used by the real scene, then exercise Army.advance_frame itself.
	if not army._load_baked_soldier():
		_fail("Baked soldier atlas unavailable")
		return
	army._soldier_baked_ready = true
	army._rebuild_visual_instances()
	if not army.combat_hot_active() or army._batch_view == null:
		_fail("Formal roster did not activate hot BatchView: hot=%s batch=%s" % [army.combat_hot_active(), army._batch_view != null])
		return
	army.combat_order = TerrainArmy.CombatOrder.ATTACK
	for index in range(64): army.combat_hot_set(index, &"think", 5.0)
	army._batch_view.mechanism_enabled = true
	army.combat_hot_diagnostics_enabled = true
	army.combat_hot_reset_stats()
	army.prepare_combat(1.0 / 3000.0)
	army.advance_frame(0.0)
	var stable_stats: Dictionary = army._batch_view.mechanism_stats()
	if int(stable_stats.static_observations) != 0 or int(stable_stats.ground_projections) != 0 or int(stable_stats.row_rebuilds) != 0 or int(stable_stats.run_rebuilds) != 0 or int(stable_stats.packed_instances) != 0:
		_fail("Stable hot tick rebuilt static presentation: " + str(stable_stats))
		return
	if not _compare_with_full(army, "stable tick"): return
	army.prepare_combat(1.0 / 3000.0)
	army.prepare_combat(1.0 / 3000.0)
	army.advance_frame(0.0)
	var catchup_stats: Dictionary = army._batch_view.mechanism_stats()
	if int(catchup_stats.static_observations) != 0 or int(catchup_stats.ground_projections) != 0 or int(catchup_stats.row_rebuilds) != 0 or int(catchup_stats.run_rebuilds) != 0 or int(catchup_stats.packed_instances) != 0:
		_fail("Two action steps rebuilt static presentation: " + str(catchup_stats))
		return
	if not _compare_with_full(army, "two action steps, one render"): return
	army.combat_hot_set(5, &"ko", 2.0)
	army.combat_hot_set(5, &"pose", "unconscious")
	army.combat_hot_set(5, &"age", 0.0)
	army.advance_frame(0.0)
	var local_stats: Dictionary = army._batch_view.mechanism_stats()
	if int(local_stats.static_observations) > 1 or int(local_stats.ground_projections) > 1 or int(local_stats.row_rebuilds) > 2:
		_fail("One-row mutation rebuilt too many sources: " + str(local_stats))
		return
	if not _compare_with_full(army, "single-row KO"): return
	if not army._reserve_combat_step(7, army.cells[7] + Vector2i.RIGHT):
		_fail("Original Army movement reservation was rejected")
		return
	army.move_progress[7] = 0.35
	army.advance_frame(0.0)
	var moving_stats: Dictionary = army._batch_view.mechanism_stats()
	if int(moving_stats.static_observations) > 1 or int(moving_stats.ground_projections) > 1:
		_fail("One-row movement rebuilt too many sources: " + str(moving_stats))
		return
	if not _compare_with_full(army, "single-row movement"): return
	army._complete_move(7)
	if army.moving_to[7] != TerrainArmy.INVALID_CELL:
		_fail("Movement fixture did not settle before stationary visual checks")
		return
	army.advance_frame(0.0)
	if not _compare_with_full(army, "movement settled"): return
	var native_stats: Dictionary = army.combat_hot_stats()
	if int(native_stats.native_calls) != 3 or int(native_stats.native_rows) != 192 or int(native_stats.fallback_rows) != 0:
		_fail("Formal path missed native no-barrier advance: " + str(native_stats))
		return
	army.combat_hot_set(6, &"exchange_visual", {"pose": "hit", "age": 0.2, "left": 0.8, "facing": army.facing[6]})
	army.advance_frame(0.0)
	army.combat_hot_reset_stats()
	army.prepare_combat(1.0 / 30.0)
	var visual_dirty_before: Array = army._visual_row_dirty.keys()
	var visual_mask_before: PackedByteArray = army._combat_hot_store.retained_idle_mask()
	var visual_cached_before: float = army._batch_view.retained_source_duration(6)
	army.advance_frame(0.0)
	var visual_stats: Dictionary = army.combat_hot_stats()
	var visual_render_stats: Dictionary = army._batch_view.mechanism_stats()
	if int(visual_stats.native_calls) != 1 or int(visual_stats.native_rows) != 64 \
			or not (visual_stats.barriers as Dictionary).is_empty() or int(visual_stats.fallback_rows) != 0:
		_fail("Pure visual fell back to owner: " + str(visual_stats))
		return
	if int(visual_render_stats.static_observations) != 0 or int(visual_render_stats.ground_projections) != 0:
		_fail("Pure visual resubmitted static source: %s dirty=%s mask6=%s duration6=%s" % [visual_render_stats, visual_dirty_before, visual_mask_before[6], visual_cached_before])
		return
	if not _cached_clock_matches(army, 6, "active exchange visual"): return
	if not _compare_with_full(army, "native pure exchange visual"): return
	army.combat_hot_set(8, &"pose", "attack_unarmed")
	army.combat_hot_set(8, &"attack", true)
	army.combat_hot_set(8, &"exchange_pose_duration", 1.0)
	army.combat_hot_set(8, &"exchange_visual", {"pose": "attack_unarmed", "age": 0.2, "left": 0.8, "facing": army.facing[8]})
	army.combat_hot_set(9, &"pose", "hit")
	army.combat_hot_set(9, &"think", 0.0)
	army.advance_frame(0.0)
	army.combat_hot_reset_stats()
	army.prepare_combat(1.0 / 30.0)
	army.prepare_combat(1.0 / 30.0)
	army.advance_frame(0.0)
	var attack_stats: Dictionary = army.combat_hot_stats()
	var attack_render_stats: Dictionary = army._batch_view.mechanism_stats()
	if int(attack_stats.native_calls) != 2 or int(attack_stats.native_rows) != 128 \
			or not (attack_stats.barriers as Dictionary).is_empty() or int(attack_stats.fallback_rows) != 0:
		_fail("Attack/think two-step catch-up fell back to owner: " + str(attack_stats))
		return
	if int(attack_render_stats.static_observations) != 0 or int(attack_render_stats.ground_projections) != 0:
		_fail("Attack/visual two-step resubmitted static source: " + str(attack_render_stats))
		return
	if not _cached_clock_matches(army, 8, "attack exchange visual"): return
	if not _compare_with_full(army, "native attack/visual two-step catch-up"): return
	army.combat_hot_set(11, &"pose", "hit")
	army.combat_hot_set(11, &"exchange_pose_duration", 1.0)
	army.combat_hot_erase(11, &"exchange_visual")
	army.advance_frame(0.0)
	army.prepare_combat(1.0 / 30.0)
	army.advance_frame(0.0)
	var ended_visual_stats: Dictionary = army._batch_view.mechanism_stats()
	if int(ended_visual_stats.static_observations) != 0 or int(ended_visual_stats.ground_projections) != 0:
		_fail("Ended visual with live pose timer resubmitted source: " + str(ended_visual_stats))
		return
	if not _cached_clock_matches(army, 11, "ended visual with pose timer"): return
	if not _compare_with_full(army, "ended visual with pose timer"): return
	army.facing[10] = Vector2i.LEFT
	army._mark_visual_row(10)
	army.advance_frame(0.0)
	var facing_stats: Dictionary = army._batch_view.mechanism_stats()
	if int(facing_stats.static_observations) > 1 or int(facing_stats.ground_projections) > 1:
		_fail("One-row facing change resubmitted unrelated sources: " + str(facing_stats))
		return
	if not _compare_with_full(army, "single-row facing change"): return
	var attack_pose := army._exchange_visual_pose(8)
	var attack_clip: String = army._combat_clip(8, attack_pose)
	var attack_direction: String = army._soldier_direction_id(army._exchange_visual_facing(8, attack_pose))
	var attack_clock: Array = army._combat_bake.contact_clocks[attack_clip][attack_direction]
	var attack_page: Dictionary = army._batch_view._pages[army._batch_view._page[8]]
	var attack_samples: Array = attack_page.samples[army._batch_view._sequence[8]]
	attack_clock[1] = float(attack_samples[0].duration) * 0.5
	army._mark_visual_row(8)
	army.advance_frame(0.0)
	if not _cached_clock_matches(army, 8, "distinct authored/page duration", true): return
	army.prepare_combat(1.0 / 30.0)
	army.advance_frame(0.0)
	var distinct_clock_stats: Dictionary = army._batch_view.mechanism_stats()
	if int(distinct_clock_stats.static_observations) != 0 or int(distinct_clock_stats.ground_projections) != 0:
		_fail("Distinct authored/page duration resubmitted source: " + str(distinct_clock_stats))
		return
	if not _compare_with_full(army, "distinct authored/page duration"): return
	if army._sprites[0] == null or not army._uses_live_presenter(0):
		_fail("Live Sprite fixture is unavailable")
		return
	army.combat_hot_set(0, &"pose", "hit")
	army.combat_hot_set(0, &"exchange_pose_duration", 1.0)
	army.advance_frame(0.0)
	army.prepare_combat(1.0 / 30.0)
	army.advance_frame(0.0)
	var live_sprite_stats: Dictionary = army._batch_view.mechanism_stats()
	if int(live_sprite_stats.static_observations) != 0 or int(live_sprite_stats.ground_projections) != 0:
		_fail("Unchanged live Sprite row was projected again: " + str(live_sprite_stats))
		return
	var live_sprite: Sprite2D = army._sprites[0]
	var live_position := live_sprite.position
	var live_z := live_sprite.z_index
	var live_visible := live_sprite.visible
	var live_texture: Texture2D = live_sprite.texture
	if not _compare_with_full(army, "unchanged live Sprite row"): return
	if live_sprite.position != live_position or live_sprite.z_index != live_z \
			or live_sprite.visible != live_visible or live_sprite.texture != live_texture:
		_fail("Retained live Sprite disagrees with full presentation")
		return
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if output == null:
		_fail("Cannot write hot retained result")
		return
	output.store_string(JSON.stringify({"checks": {"formal_admission": true, "stable_no_rebuild": true,
		"stable_exact_full": true, "two_step_single_frame_exact": true,
		"local_ko_bounded_exact": true, "moving_bounded_exact": true,
		"native_no_barrier": true, "visual_pure_retained_exact": true,
		"attack_visual_two_step_retained_exact": true, "nonidle_visual_zero_static": true,
		"nonidle_attack_two_step_zero_static": true, "ended_visual_pose_timer_exact": true,
		"local_facing_bounded_exact": true, "authored_duration_distinct_page_exact": true,
		"unchanged_live_sprite_zero_ground_exact": true},
		"stable": stable_stats, "catchup": catchup_stats, "local": local_stats,
		"moving": moving_stats, "native": native_stats, "visual": visual_stats,
		"visual_render": visual_render_stats, "attack_two_step": attack_stats,
		"attack_render": attack_render_stats, "ended_visual": ended_visual_stats,
		"facing": facing_stats, "distinct_clock": distinct_clock_stats,
		"live_sprite": live_sprite_stats,
		"army_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
		"batch_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_batch_view.gd"),
		"dll_sha256": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll"),
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_hot_retained_integration_test.gd")}))
	output.close()
	print("ARMY_HOT_RETAINED_INTEGRATION_PASS")
	army.free()
	quit(0)
