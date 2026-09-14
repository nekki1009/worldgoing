extends SceneTree
## Actual raw Actor shapes, original contact solver and the real Lab collector.
## GPU --body=0 or --body=1; internal 23 seconds / canonical helper 25 seconds.
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

class ObservedActor extends TerrainTestCharacter:
	var geometry_calls := 0
	var narrow_calls := 0
	func incoming_geometry(ranged: bool = false) -> Dictionary:
		geometry_calls += 1
		return super.incoming_geometry(ranged)
	func incoming_contact(previous: Array[PackedVector2Array], shapes: Array[PackedVector2Array], ranged: bool = false, sampled_geometry: Dictionary = {}, prepared: Array = []) -> Dictionary:
		narrow_calls += 1
		return super.incoming_contact(previous, shapes, ranged, sampled_geometry, prepared)

var body := 0
var comparisons := 0
var positive_contacts := 0
var skipped_narrow := 0
var pose_count := 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--body="):
			body = argument.trim_prefix("--body=").to_int()
	call_deferred("run")

func _compare(lab: TerrainLab, actor: ObservedActor, requests: Array) -> void:
	var expected: Array = []
	var original_narrow := 0
	for enabled: bool in [false, true]:
		lab.batch_actor_bounds_enabled = enabled
		lab._army_contact_geometry.clear()
		lab._sampling_army_contacts = true
		var geometry_before := actor.geometry_calls
		var narrow_before := actor.narrow_calls
		for index: int in requests.size():
			var request: Array = requests[index]
			var found := lab._collect_unit_contacts(request[0], request[1], actor.terrain_cell, actor.position, lab, -1)
			if enabled:
				assert(found == expected[index], "Exact original identity/faction/fraction/point/body/block/distance/order: %d/%d" % [pose_count, index])
				comparisons += 1
				positive_contacts += found.size()
			else:
				expected.append(found.duplicate(true))
		assert(actor.geometry_calls - geometry_before == 1, "One actual post-advance geometry per same-step batch")
		if enabled:
			assert(actor.narrow_calls - narrow_before < original_narrow, "Provably disjoint sweeps skip the original narrow phase")
			skipped_narrow += original_narrow - (actor.narrow_calls - narrow_before)
		else:
			original_narrow = actor.narrow_calls - narrow_before
		lab._sampling_army_contacts = false
		lab._army_contact_geometry.clear()
	# Direct/outside-batch queries still use the original live geometry immediately.
	var direct_before := actor.geometry_calls
	for index: int in requests.size():
		var request: Array = requests[index]
		assert(lab._collect_unit_contacts(request[0], request[1], actor.terrain_cell, actor.position, lab, -1) == expected[index])
	assert(actor.geometry_calls - direct_before == requests.size() and lab._army_contact_geometry.is_empty())
	pose_count += 1

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() != "headless" and body in [0, 1])
	var data := TerrainGenerator.generate(0, 581, {"size": Vector2i(48, 48)})
	SiteEnvironment.initialize(data, "actual-actor-batch-bounds")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	var lab := TerrainLab.new()
	lab.terrain = data
	var actor := ObservedActor.new()
	actor.visual_state.body_index = body
	root.add_child(actor)
	actor.set_process(false)
	actor.data = data
	actor.terrain_cell = Vector2i(20, 20)
	actor.position = Vector2(400.0, 650.0) # Explicit projection fixture, not an alternate world-coordinate owner.
	actor.initialize_visual()
	assert(actor.editor != null)
	actor.editor.set_process(false)
	actor.editor.set_playing(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	var appearance := HumanCharacter3DEditor.default_appearance(body)
	assert(actor.editor.restore_appearance(appearance))
	lab.combat_actors.assign([actor])
	var cases: Array = [[&"walk_slash", 0.517], [&"down", 0.773], [&"get_up", 0.337],
		[&"guard", 0.093], [&"rescue", 1.137]]
	for direction: Vector2i in TerrainData.DIRECTIONS:
		actor.facing = direction
		actor.editor.set_preview_yaw_degrees({Vector2i.DOWN: 0.0, Vector2i.UP: 180.0, Vector2i.LEFT: -90.0, Vector2i.RIGHT: 90.0}[direction])
		for request: Array in cases:
			for shield: bool in [true, false]:
				assert(actor.editor.select_part_by_id(&"shield", StringName(str(appearance.parts.shield)) if shield else &"none"))
				actor.play_pose(request[0])
				actor.editor.animation_player.seek(request[1], true)
				actor.editor.animation_player.advance(0.0)
				actor.editor._update_combat_props()
				actor.editor._update_scabbard_pose()
				actor.editor._update_combat_cloth()
				actor._sync_render_projection()
				actor.guarding = request[0] == &"guard"
				actor.guard_break_left = 0.0
				actor.guard_transition_left = 0.0
				var geometry := actor.incoming_geometry()
				if actor.guarding and not shield:
					assert(not geometry.parry.is_empty(), "Include the actual shieldless weapon parry")
				var requests: Array = []
				for kind: String in ["body", "shield", "parry"]:
					for polygon: PackedVector2Array in geometry[kind]:
						var current: Array[PackedVector2Array] = [polygon]
						var previous := Geometry.shifted(current, Vector2(-20.0, 0.0))
						requests.append([previous, current])
						requests.append([Geometry.shifted(previous, Vector2(10000.0, 10000.0)), Geometry.shifted(current, Vector2(10000.0, 10000.0))])
						# First misses, second actually intersects: never reject from only the first sweep.
						var multi := Geometry.shifted(current, Vector2(-10000.0, 0.0))
						multi.append(polygon)
						requests.append([multi, multi])
				_compare(lab, actor, requests)
	# Existing coordinator owns and clears the snapshot; it never survives a real step.
	lab._advance_combat(1.0 / 120.0)
	assert(not lab._sampling_army_contacts and lab._army_contact_geometry.is_empty())
	assert(comparisons > 1000 and positive_contacts > 0 and skipped_narrow > 0)
	var report := {"body": body, "poses": pose_count, "exact_contacts": comparisons, "positive_contacts": positive_contacts,
		"skipped_narrow": skipped_narrow, "maximum_error": 0.0, "lab_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_lab.gd"),
		"scope": "Actual raw actor limb/shield/parry projections; same-batch enabled/disabled and uncached original contacts exactly equal. Not FPS or visual acceptance."}
	var path := "res://output/site_combat_performance_20260913/actor_batch_bounds/body_%d_%d.json" % [body, int(Time.get_unix_time_from_system())]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	lab.combat_actors.clear()
	lab.free()
	actor.queue_free()
	await process_frame
	print("SITE ACTOR BATCH BOUNDS PASS ", JSON.stringify(report))
	quit(0)
