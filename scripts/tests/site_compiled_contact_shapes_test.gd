extends SceneTree

const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const ShapesDescriptor = preload("res://scripts/terrain_lab/terrain_army_shapes_descriptor.gd")
var discrepancies: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(45.0).timeout.connect(func() -> void: quit(1))
	assert(TerrainArmy.load_combat_bake())
	var source := Source.new()
	assert(source.initialize(root, TerrainArmy._combat_bake.manifest.appearance))
	var compiled: RefCounted = load("res://scripts/terrain_lab/compiled_contact_shapes.cs").new()
	var cases := 0
	var rejected := 0
	var native_usec := 0
	var candidate_usec := 0
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT]:
		for clip: StringName in [&"idle", &"walk_slash"]:
			for time: float in [0.0, 0.0713, 0.217, 0.513, 0.517, 0.731]:
				source.clear_samples()
				var expected := source.sample(clip, time, direction)
				var descriptor := ShapesDescriptor.capture(source)
				var setup: Dictionary = compiled.Compile(descriptor)
				if not setup.ok:
					rejected += 1
					print("SHAPES REJECT ", clip, " ", time, ": ", setup.error)
					continue
				var bones := ShapesDescriptor.global_poses(source)
				var began := Time.get_ticks_usec()
				var actual: Dictionary = compiled.Evaluate(bones, true)
				candidate_usec += Time.get_ticks_usec() - began
				assert(actual.ok, str(actual))
				for kind: String in ["body", "weapon", "shield", "parry", "hurt_bounds", "shoulder"]:
					if exact_bytes(actual[kind]) != exact_bytes(expected[kind]):
						if discrepancies.size() < 12:
							discrepancies.append({"clip": str(clip), "time": time, "direction": direction, "field": kind, "expected": expected[kind], "actual": actual[kind]})
				began = Time.get_ticks_usec()
				var proxy := {"editor": source.editor, "player_sprite": source.sprite}
				source.geometry.body_shapes(proxy)
				source.geometry.weapon_shapes(proxy, source.editor._resolve_weapon_attack_animation())
				source.geometry.shield_shapes(proxy)
				native_usec += Time.get_ticks_usec() - began
				for point: Vector2 in [Vector2.ZERO, expected.hurt_bounds.get_center()]:
					var protection := source.geometry.armor_at(proxy, point, "slash")
					var candidate: Dictionary = compiled.ArmorAt(bones, point, "slash")
					assert(candidate.ok)
					if var_to_bytes(candidate.protection) != var_to_bytes(protection) and discrepancies.size() < 12:
						discrepancies.append({"clip": str(clip), "time": time, "field": "armor", "expected": protection, "actual": candidate.protection})
				cases += 1
	var report := {"cases": cases, "rejected": rejected, "discrepancies": discrepancies, "native_geometry_usec": native_usec, "candidate_geometry_usec": candidate_usec,
		"note": "Native pose inputs; no pose evaluator, input export, setup or gameplay timing included. Not FPS or full pipeline acceptance."}
	DirAccess.make_dir_recursive_absolute("res://output/site_compiled_contact")
	var file := FileAccess.open("res://output/site_compiled_contact/shapes.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("COMPILED SHAPES REPORT ", JSON.stringify(report))
	source.dispose()
	await process_frame
	if cases != 24 or not discrepancies.is_empty():
		push_error("Compiled geometry gate failed; candidate remains test-only")
		quit(1)
		return
	print("SITE COMPILED CONTACT SHAPES PASS")
	quit(0)

func exact_bytes(value: Variant) -> PackedByteArray:
	if value is Array:
		var plain: Array = []
		plain.assign(value)
		return var_to_bytes(plain)
	return var_to_bytes(value)
