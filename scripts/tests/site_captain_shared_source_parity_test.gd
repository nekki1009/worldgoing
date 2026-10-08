extends SceneTree
## Diagnostic only: compare original live captains with one query source per body.
## This does not switch any production combat or presentation path.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const SharedVisualSource = preload("res://scripts/terrain_lab/terrain_army_shared_visual_source.gd")
const OUT := "res://output/site_captain_shared_source_parity_20260929"
const DEADLINE_USEC := 180000000

var started := 0
var results: Array[Dictionary] = []
var live_snapshots: Array[Dictionary] = []
var faults: Array[String] = []
var sources := {}
var pooled_editors := {}
var pooled_sprites := {}
var pooled_geometry := {}
var teams: Array[TerrainArmy] = []

func _initialize() -> void:
	started = Time.get_ticks_usec()
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_usec() - started > DEADLINE_USEC:
		faults.append("180-second internal deadline")
		_finish()
	return false

func _make_team(data: TerrainData, body: int, troop: StringName, cell: Vector2i) -> TerrainArmy:
	var team := TerrainArmy.new()
	team.team_id = teams.size() + 1
	team.roster_size = 1
	team.exchange_enabled = true
	root.add_child(team)
	team.set_process(false)
	if not team.deploy_at(data, null, null, [cell]) or not team.enable_combat(false, body, troop):
		faults.append("Cannot deploy original %s body %d" % [troop, body])
		return team
	var appearance: Dictionary = team.combat_units[0].appearance
	var editor: HumanCharacter3DEditor = team._unit_editor(0)
	if editor == null or not editor.restore_appearance(appearance):
		faults.append("Cannot restore original captain appearance body %d" % body)
		return team
	var row: Dictionary = team.combat_units[0]
	row.item_state = {}
	row.cargo = {}
	var seeded := Runtime.seed_person_equipment(data, row.item_state, team.combat_identity(0), appearance)
	if not bool(seeded.get("ok", false)):
		faults.append("Cannot seed actual equipment body %d troop %s: %s" % [body, troop, seeded])
		return team
	team.equipment_appearance_query = func(identity: int) -> Dictionary:
		return Runtime.equipment_appearance(data, row.item_state, row.appearance) if identity == team.combat_identity(0) else {}
	team._combat_pose_cache.clear()
	teams.append(team)
	return team

func _shape_difference(actual: Array, expected: Array) -> Dictionary:
	if actual.size() != expected.size():
		return {"actual_polygons": actual.size(), "source_polygons": expected.size()}
	for polygon in range(actual.size()):
		var left: PackedVector2Array = actual[polygon]
		var right: PackedVector2Array = expected[polygon]
		if left.size() != right.size():
			return {"polygon": polygon, "actual_vertices": left.size(), "source_vertices": right.size()}
		for vertex in range(left.size()):
			if left[vertex] != right[vertex]:
				return {"polygon": polygon, "vertex": vertex, "actual": [left[vertex].x, left[vertex].y],
					"source": [right[vertex].x, right[vertex].y], "distance": left[vertex].distance_to(right[vertex])}
	return {}

func _pooled_case(team: TerrainArmy, sample: Array, appearance: Dictionary, entry: Dictionary) -> void:
	var body := int(appearance.body)
	var editor: SharedVisualSource = pooled_editors[body]
	var sprite: Sprite2D = pooled_sprites[body]
	var geometry: Variant = pooled_geometry[body]
	if editor.capture_appearance() != appearance and not editor.restore_appearance(appearance):
		entry.pool_differences["appearance"] = "Cannot restore exact original appearance"
		return
	var direction := Vector2i(sample[2])
	editor.set_preview_yaw_degrees(team._captain_yaw_degrees(direction))
	if not editor.combat_ready:
		editor.combat_ready = true
		editor.visual_state.combat_ready = true
		editor._update_weapon_sheath_state()
	var frame: Dictionary = team.combat_frame(0)
	var descriptor: Dictionary = TerrainArmy._combat_bake.clips[str(frame.clip)]
	var pose := StringName(str(descriptor.get("pose", frame.clip)))
	if editor.selected_animation != pose:
		editor.select_animation_by_id(pose)
	if pose == &"attack_jump_heavy":
		var jump: Animation = editor.animation_player.get_animation(pose)
		if jump != null: jump.loop_mode = Animation.LOOP_NONE
	editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	editor.animation_player.seek(float(sample[1]), true)
	editor._process(0.0)
	editor.preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var origin := team.combat_ground(0) + team.combat_offset(0)
	var scale: float = editor.get_map_sprite_scale()
	var anchor: Vector2 = editor.get_map_ground_offset_pixels() * scale
	sprite.scale = Vector2.ONE * scale
	sprite.position = team.to_global(origin - anchor)
	var actual_transform: Transform2D = team._sprites[0].global_transform
	if sprite.global_transform != actual_transform:
		entry.pool_differences["virtual_sprite_transform"] = {"actual": str(actual_transform), "predicted": str(sprite.global_transform)}
	# Compare the rig independently of transform construction. Production must
	# pass the virtual-transform check above before it may use this path.
	sprite.global_transform = actual_transform
	var proxy := {"editor": editor, "player_sprite": sprite}
	var generated := {"body": geometry.body_shapes(proxy), "weapon": geometry.weapon_shapes(proxy, team.attack_clip(0)),
		"shield": geometry.shield_shapes(proxy), "parry": []}
	if str(team.combat_hot_get(0, &"pose")) == "guard" and generated.shield.is_empty() \
			and team.attack_clip(0) not in [&"attack_unarmed", &"attack_bow", &"attack_crossbow"]:
		generated.parry = geometry.weapon_shapes(proxy, team.attack_clip(0), true)
	# The live captain caches polygons relative to the origin, then shifts them
	# back for callers. Replicate that same float32 round trip in the pool.
	var local_shapes := {}
	for kind: String in ["body", "shield", "parry", "weapon"]:
		local_shapes[kind] = Geometry.shifted(generated[kind], -origin)
		var world_shapes: Array[PackedVector2Array] = Geometry.shifted(local_shapes[kind], origin)
		var difference := _shape_difference(team.combat_shapes(0, kind), world_shapes)
		if not difference.is_empty(): entry.pool_differences[kind] = difference
	var points := PackedVector2Array()
	for kind: String in ["body", "shield", "parry"]:
		for shape: PackedVector2Array in local_shapes[kind]: points.append_array(shape)
	var bounds: Rect2 = Geometry.polygon_bounds(points)
	bounds.position += origin
	if bounds != team.combat_bounds(0):
		entry.pool_differences["hurt_bounds"] = {"actual": str(team.combat_bounds(0)), "pool": str(bounds)}
	var live_bodies: Array[PackedVector2Array] = team.combat_shapes(0, "body")
	if not live_bodies.is_empty() and not live_bodies[0].is_empty():
		var point := live_bodies[0][0]
		for damage_kind: String in ["slash", "stab"]:
			var hit := {"point": point, "body": 0, "shield": false}
			var actual := team.contact_protection(0, hit, {"kind": damage_kind})
			var pooled: Vector2 = geometry.armor_at(proxy, point, damage_kind)
			if actual != pooled:
				entry.pool_differences["armor_" + damage_kind] = {"actual": str(actual), "pool": str(pooled)}

func _case(team: TerrainArmy, pose: String, age: float, facing: Vector2i, attacking: bool) -> void:
	var index := 0
	var row: Dictionary = team.combat_units[index]
	row.pose = pose
	row.age = age
	row.attack = attacking
	row.attack_reduction = 0.0
	row.attack_fatigue = 0.0
	row.aim = []
	team.facing[index] = facing
	team._combat_pose_cache.clear()
	var appearance := team.equipment_appearance(index)
	var sample: Array = team.contact_sample(index)
	var source: Variant = sources[int(appearance.body)]
	source.begin_contact_step()
	var query: Dictionary = source.sample(sample[0], sample[1], sample[2], sample[3], sample[4], appearance)
	var entry := {"body": int(appearance.body), "troop": str(team.attack_clip(index)), "pose": pose,
		"age": age, "facing": [facing.x, facing.y], "sample": [str(sample[0]), sample[1], str(sample[2])],
		"appearance": appearance, "source_differences": {}, "pool_differences": {}, "product_differences": {}}
	if query.is_empty():
		entry.source_differences["source"] = "Empty source sample"
	var origin: Vector2 = team.combat_ground(index) + team.combat_offset(index)
	if not query.is_empty():
		for kind: String in ["body", "shield", "parry", "weapon"]:
			var live: Array[PackedVector2Array] = team.combat_shapes(index, kind)
			var projected: Array[PackedVector2Array] = Geometry.shifted(query.get(kind, []), origin)
			var difference := _shape_difference(live, projected)
			if not difference.is_empty(): entry.source_differences[kind] = difference
		var live_bounds := team.combat_bounds(index)
		var source_bounds: Rect2 = query.hurt_bounds
		source_bounds.position += origin
		if live_bounds != source_bounds:
			entry.source_differences["hurt_bounds"] = {"actual": str(live_bounds), "source": str(source_bounds)}
	var bodies: Array[PackedVector2Array] = team.combat_shapes(index, "body")
	if not bodies.is_empty() and not bodies[0].is_empty():
		var point := bodies[0][0]
		for damage_kind: String in ["slash", "stab"]:
			var hit := {"point": point, "body": 0, "shield": false}
			var live_armor := team.contact_protection(index, hit, {"kind": damage_kind})
			if not query.is_empty():
				var source_armor: Vector2 = source.armor_at(sample[0], sample[1], sample[2], point - origin,
					damage_kind, sample[3], sample[4], appearance)
				if live_armor != source_armor:
					entry.source_differences["armor_" + damage_kind] = {"actual": str(live_armor), "source": str(source_armor)}
	_pooled_case(team, sample, appearance, entry)
	var baseline_shapes := {}
	for kind: String in ["body", "shield", "parry", "weapon"]:
		baseline_shapes[kind] = team.combat_shapes(index, kind)
	var baseline_armor := {}
	var baseline_bodies: Array[PackedVector2Array] = baseline_shapes.body
	if not baseline_bodies.is_empty() and not baseline_bodies[0].is_empty():
		var point := baseline_bodies[0][0]
		for damage_kind: String in ["slash", "stab"]:
			baseline_armor[damage_kind] = team.contact_protection(index,
				{"point": point, "body": 0, "shield": false}, {"kind": damage_kind})
	live_snapshots.append({"team": team, "pose": pose, "age": age, "facing": facing,
		"attacking": attacking, "shapes": baseline_shapes, "bounds": team.combat_bounds(index),
		"armor": baseline_armor, "entry": entry})
	results.append(entry)

func _product_case(snapshot: Dictionary) -> void:
	var team: TerrainArmy = snapshot.team
	var row: Dictionary = team.combat_units[0]
	row.pose = snapshot.pose
	row.age = snapshot.age
	row.attack = snapshot.attacking
	row.attack_reduction = 0.0
	row.attack_fatigue = 0.0
	row.aim = []
	team.facing[0] = snapshot.facing
	team._combat_pose_cache.clear()
	var entry: Dictionary = snapshot.entry
	if not team._uses_pooled_captain_geometry(0):
		entry.product_differences["admission"] = "Original visual_role did not route to the shared true-editor pool"
		return
	for kind: String in ["body", "shield", "parry", "weapon"]:
		var difference := _shape_difference(snapshot.shapes[kind], team.combat_shapes(0, kind))
		if not difference.is_empty(): entry.product_differences[kind] = difference
	var bounds: Rect2 = team.combat_bounds(0)
	if bounds != snapshot.bounds:
		entry.product_differences["hurt_bounds"] = {"actual": str(snapshot.bounds), "product": str(bounds)}
	var bodies: Array[PackedVector2Array] = snapshot.shapes.body
	if not bodies.is_empty() and not bodies[0].is_empty():
		for damage_kind: String in ["slash", "stab"]:
			var actual: Vector2 = team.contact_protection(0,
				{"point": bodies[0][0], "body": 0, "shield": false}, {"kind": damage_kind})
			if actual != snapshot.armor[damage_kind]:
				entry.product_differences["armor_" + damage_kind] = {"actual": str(snapshot.armor[damage_kind]), "product": str(actual)}

func _finish() -> void:
	if get_meta(&"finished", false): return
	set_meta(&"finished", true)
	var source_mismatches := 0
	var pool_mismatches := 0
	var product_mismatches := 0
	for entry: Dictionary in results:
		source_mismatches += int(not entry.source_differences.is_empty())
		pool_mismatches += int(not entry.pool_differences.is_empty())
		product_mismatches += int(not entry.product_differences.is_empty())
	var report := {"scope": "Original live captain versus one same-body ContactSource and one true SharedVisualSource pool per body; diagnostic only, not FPS or changed production behavior",
		"display_server": DisplayServer.get_name(), "elapsed_seconds": float(Time.get_ticks_usec() - started) / 1000000.0,
		"cases": results, "source_mismatches": source_mismatches, "pool_mismatches": pool_mismatches,
		"product_mismatches": product_mismatches, "pool_editor_count": TerrainArmy._captain_geometry_pool.size(),
		"faults": faults,
		"source_hashes": {"army": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
			"source": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
			"shared_visual": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_shared_visual_source.gd"),
			"test": FileAccess.get_sha256("res://scripts/tests/site_captain_shared_source_parity_test.gd")}}
	var directory := "%s/run_%d_%d" % [OUT, int(Time.get_unix_time_from_system()), started]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory + "/measurements.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		faults.append("Cannot save report")
	print("SITE_CAPTAIN_SHARED_SOURCE_PARITY_%s %s" % ["PASS" if faults.is_empty() and pool_mismatches == 0 and product_mismatches == 0 else "FAIL", directory])
	quit(0 if faults.is_empty() and pool_mismatches == 0 and product_mismatches == 0 else 1)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		faults.append("GPU visual run required")
		_finish()
		return
	var data := TerrainGenerator.generate(0, 581, {"size": Vector2i(48, 48)})
	Env.initialize(data, "captain-shared-source-parity")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	if not bool(Runtime.initialize_item_storage(data.site).get("ok", false)):
		faults.append("Actual item storage initialization failed")
		_finish()
		return
	for body in [0, 1]:
		for troop: StringName in [&"melee_infantry", &"bow"]:
			var team := _make_team(data, body, troop, Vector2i(10 + teams.size() * 4, 12))
			if not faults.is_empty():
				_finish()
				return
			if not sources.has(body):
				var source := Source.new()
				if not source.initialize(root, team.equipment_appearance(0)):
					faults.append("Shared source initialization failed for body %d" % body)
					_finish()
					return
				sources[body] = source
				var editor: SharedVisualSource = team._create_visual_source(body, "PooledCaptainGeometryBody%d" % body)
				editor.preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
				pooled_editors[body] = editor
				var proxy_sprite := Sprite2D.new()
				root.add_child(proxy_sprite)
				pooled_sprites[body] = proxy_sprite
				pooled_geometry[body] = Geometry.new()
	# Interleave same-body A -> B -> A with different equipment and cells.
	var order: Array[TerrainArmy] = [teams[0], teams[1], teams[0], teams[2], teams[3], teams[2]]
	for case: Array in [["idle", 0.173, Vector2i.DOWN, false],
		["walk", 0.333, Vector2i.RIGHT, false], ["guard", 0.073, Vector2i.LEFT, false],
		["attack", 0.71, Vector2i.DOWN, true], ["down", 1.13, Vector2i.UP, false]]:
		for team: TerrainArmy in order:
			var pose := str(team.attack_clip(0)) if case[0] == "attack" else str(case[0])
			_case(team, pose, case[1], case[2], case[3])
	for team: TerrainArmy in teams:
		team.defer_captain_presenter = true
		team.refresh_captain_presentation()
		if not team._deferred_captain_ready or team._unit_editor(0) != null or team._sprites[0] == null or team._sprites[0].texture == null:
			faults.append("Original captain did not switch to a visible supported atlas sprite, body %d troop %s" % [int(team.combat_units[0].appearance.body), team.attack_clip(0)])
	if faults.is_empty():
		for snapshot: Dictionary in live_snapshots:
			_product_case(snapshot)
		var target: TerrainArmy = teams[0]
		var bodies: Array[PackedVector2Array] = target.combat_shapes(0, "body")
		var hit := target.combat_contact(0, [bodies[0]], [bodies[0]]) if not bodies.is_empty() else {}
		if hit.is_empty() or int(hit.get("identity", -1)) != target.combat_identity(0) or hit.get("target") != target:
			faults.append("Deferred captain's original contact query did not return its original identity")
	_finish()
