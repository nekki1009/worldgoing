extends SceneTree
## CAV-3b completeness contract for the mounted ordinary-soldier atlas reader (v2: rider + horse layers).
## Fixture manifests cover: valid, missing family, missing clip, missing horse frame, complete=false,
## wrong source fingerprint, wrong asset md5, old v1 manifest. The real manifest, when baked, must
## contain every family x clip x direction x frame for both bodies in both layers, load its pages
## from .res only (no editor import), and compose a crowd page per body/family.
const Reader = preload("res://scripts/terrain_lab/site_mounted_soldier_atlas.gd")
const FIXTURE := "user://mounted_soldier_atlas_fixture/"
const SELF_PATH := "res://scripts/tests/site_mounted_soldier_atlas_test.gd"
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)

func _appearance(body: int, weapon: String) -> Dictionary:
	var value := HumanCharacter3DEditor.default_appearance(body)
	value.mounted = true
	value.parts.weapon = weapon
	return value

func _weapon_for_family(family: String) -> String:
	return family

func _write_fixture(name: String, mutate: Callable) -> String:
	var root := FIXTURE + name + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var assets := {"colour_000.res": "colour", "dye_000.res": "dye", "colour_001.res": "horse", "dye_001.res": "horse dye"}
	var asset_md5 := {}
	for asset_name: String in assets:
		var file := FileAccess.open(root + asset_name, FileAccess.WRITE)
		file.store_string(str(assets[asset_name]))
		file.close()
		asset_md5[asset_name] = FileAccess.get_md5(root + asset_name)
	var frames: Array[Dictionary] = []
	var frame_counts := {}
	var horse_frames: Array[Dictionary] = []
	var durations := {}
	for clip: String in Reader.CLIP_FRAMES:
		durations[clip] = 1.0
		for direction: String in Reader.DIRECTIONS:
			for index: int in range(int(Reader.CLIP_FRAMES[clip])):
				horse_frames.append({"clip": clip, "direction": direction, "frame": index, "page": 1, "rect": [index * 4, 0, 4, 4], "anchor": [0.0, 0.0]})
	for family: String in Reader.FAMILY_CLIPS:
		var clip_counts := {}
		for clip: String in Reader.FAMILY_CLIPS[family]:
			clip_counts[clip] = int(Reader.CLIP_FRAMES[clip])
			for body: int in Reader.BODIES:
				for direction: String in Reader.DIRECTIONS:
					for index: int in range(int(Reader.CLIP_FRAMES[clip])):
						frames.append({"body": body, "family": family, "clip": clip, "direction": direction, "frame": index,
							"page": 0, "rect": [index * 4, 0, 4, 4], "anchor": [0.0, 0.0], "horse_offset": [0.0, 0.0]})
		frame_counts[family] = clip_counts
	var manifest := {"version": 2, "complete": true, "kind": "mounted_soldier_atlas", "bodies": [0, 1],
		"directions": ["down", "left", "up", "right"], "frame_counts": frame_counts, "horse_clips": Reader.HORSE_CLIPS.duplicate(),
		"clip_durations": durations,
		"pages": [{"page": 0, "group": "0/all", "colour_res": "colour_000.res", "dye_res": "dye_000.res", "width": 4, "height": 4},
			{"page": 1, "group": Reader.HORSE_GROUP, "colour_res": "colour_001.res", "dye_res": "dye_001.res", "width": 4, "height": 4}],
		"asset_md5": asset_md5, "frames": frames, "horse_frames": horse_frames, "map_scale": 1.0,
		"source_fingerprints": {SELF_PATH: FileAccess.get_md5(SELF_PATH)}}
	mutate.call(manifest)
	var file := FileAccess.open(root + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	return root

# Crowd page: one composed frame per clip/direction/frame, inside one texture, with the batch-view frame shape.
func _check_crowd_recipe(appearance: Dictionary, family: String) -> void:
	var recipe := Reader.crowd_recipe(appearance)
	var label := "crowd recipe %d/%s" % [int(appearance.body), family]
	if not _check_ok(not recipe.is_empty(), label + ": built"): return
	var texture: Texture2D = recipe.texture
	var dye: Texture2D = recipe.dye
	_check(texture != null and dye != null and texture.get_size() == dye.get_size(), label + ": colour and dye pages match")
	var expected := 0
	for clip: String in Reader.FAMILY_CLIPS[family]: expected += Reader.DIRECTIONS.size()
	_check(recipe.sequences.size() == expected, label + ": one sequence per clip and direction")
	for sequence_key: String in recipe.sequences:
		var frames: Array = recipe.sequences[sequence_key]
		var clip := sequence_key.get_slice("|", 0)
		_check(frames.size() == int(Reader.CLIP_FRAMES[clip]), label + ": frame count " + sequence_key)
		for frame: Dictionary in frames:
			var rect: Dictionary = frame.rect
			_check(int(rect.x) + int(rect.w) <= texture.get_width() and int(rect.y) + int(rect.h) <= texture.get_height(), label + ": rect inside page " + sequence_key)
			_check(float(frame.sample_time) <= float(frame.duration) and float(frame.duration) > 0.0, label + ": clock " + sequence_key)
	_check(is_same(Reader.crowd_recipe(appearance).texture, texture), label + ": cached")

func _check_ok(condition: bool, message: String) -> bool:
	_check(condition, message)
	return condition

# Layer placement: both layers share one ground point, so the composite anchor puts each where the bake saw it.
func _check_layout() -> void:
	var layout := Reader.compose_layout(Vector2i(10, 20), Vector2(0.0, 8.0), Vector2i(30, 16), Vector2(2.0, 0.0))
	# rider corner = (-5, -18), horse corner = (-17, -8): base (-17, -18)
	_check(layout.size == Vector2i(30, 26) and layout.rider == Vector2i(12, 0) and layout.horse == Vector2i(0, 10), "layout: union and offsets %s" % str(layout))
	var anchor: Vector2 = layout.anchor
	_check(anchor.is_equal_approx(Vector2(2.0, 5.0)), "layout: composite anchor keeps the ground point %s" % str(anchor))

func _drop_family(manifest: Dictionary, family: String) -> void:
	manifest.frame_counts.erase(family)
	manifest.frames = manifest.frames.filter(func(item: Dictionary) -> bool: return item.family != family)

func _run() -> void:
	var valid := _write_fixture("valid", func(_manifest: Dictionary) -> void: pass)
	Reader.set_root_for_test(valid)
	_check(Reader.available(_appearance(0, "longsword_01")), "valid: longsword body 0 must be admitted")
	_check(Reader.available(_appearance(1, "crossbow_01")), "valid: crossbow body 1 must be admitted")
	_check(Reader.available(_appearance(0, "bow_01")), "valid: bow body 0 must be admitted")
	_check(Reader.available(_appearance(0, "spear_01")), "valid: spear body 0 must be admitted")
	var foot := _appearance(0, "longsword_01")
	foot.mounted = false
	_check(not Reader.available(foot), "valid: a foot appearance is never admitted by the riding atlas")
	_check(not Reader.available(_appearance(0, "wood_axe_01")), "valid: a tool family is not a soldier family")

	Reader.set_root_for_test(_write_fixture("missing_family", func(manifest: Dictionary) -> void: _drop_family(manifest, "bow_01")))
	_check(not Reader.available(_appearance(0, "bow_01")), "missing family: bow_01 must be refused")
	_check(Reader.available(_appearance(0, "longsword_01")), "missing family: other families stay admitted")

	Reader.set_root_for_test(_write_fixture("missing_clip", func(manifest: Dictionary) -> void:
		manifest.frames = manifest.frames.filter(func(item: Dictionary) -> bool: return not (item.family == "longsword_01" and item.clip == "ride_walk"))))
	_check(not Reader.available(_appearance(0, "longsword_01")), "missing clip: longsword without ride_walk must be refused")
	_check(Reader.available(_appearance(0, "spear_01")), "missing clip: spear stays admitted")

	Reader.set_root_for_test(_write_fixture("missing_horse", func(manifest: Dictionary) -> void:
		manifest.horse_frames = manifest.horse_frames.filter(func(item: Dictionary) -> bool: return not (item.clip == "ride_run" and item.direction == "left" and item.frame == 3))))
	_check(not Reader.available(_appearance(0, "longsword_01")), "missing horse frame: a rider without its horse layer must be refused")

	Reader.set_root_for_test(_write_fixture("old_v1", func(manifest: Dictionary) -> void: manifest.version = 1))
	_check(not Reader.available(_appearance(0, "longsword_01")), "a v1 (rider-only) manifest must be refused")

	Reader.set_root_for_test(_write_fixture("incomplete", func(manifest: Dictionary) -> void: manifest.complete = false))
	_check(not Reader.available(_appearance(0, "longsword_01")), "complete=false must be refused")

	Reader.set_root_for_test(_write_fixture("wrong_source_md5", func(manifest: Dictionary) -> void:
		manifest.source_fingerprints[SELF_PATH] = "00000000000000000000000000000000"))
	_check(not Reader.available(_appearance(0, "longsword_01")), "wrong source md5 must be refused")

	Reader.set_root_for_test(_write_fixture("wrong_asset_md5", func(manifest: Dictionary) -> void:
		manifest.asset_md5["colour_001.res"] = "00000000000000000000000000000000"))
	_check(not Reader.available(_appearance(0, "longsword_01")), "wrong asset md5 (horse page) must be refused")

	_check_layout()

	Reader.set_root_for_test(Reader.ROOT)
	if FileAccess.file_exists(Reader.ROOT + "manifest.json"):
		for body: int in Reader.BODIES:
			for family: String in Reader.FAMILY_CLIPS:
				var appearance := _appearance(body, _weapon_for_family(family))
				_check(Reader.available(appearance), "real manifest: body %d family %s not complete" % [body, family])
				for clip: String in Reader.FAMILY_CLIPS[family]:
					var count := int(Reader.CLIP_FRAMES[clip])
					for direction: String in Reader.DIRECTIONS:
						for index: int in range(count):
							var value := Reader.frame(appearance, clip, direction, (float(index) + 0.5) / float(count))
							_check(not value.is_empty() and value.frame == index and value.get("horse", {}).get("texture") is AtlasTexture, "real manifest: missing %d/%s/%s/%s/%d" % [body, family, clip, direction, index])
				_check_crowd_recipe(appearance, family)
		var dyed := _appearance(0, "longsword_01")
		dyed["equipment_dyes"] = {"armor": "ff0000ff"}
		_check(Reader.crowd_key(dyed) == Reader.crowd_key(_appearance(0, "longsword_01")), "real manifest: dyes share one crowd page (the palette carries them)")
		_check(Reader.crowd_clip("attack", _appearance(0, "spear_01")) == "ride_thrust" and Reader.crowd_clip("shoot", _appearance(1, "crossbow_01")) == "attack_crossbow" and Reader.crowd_clip("shoot", _appearance(0, "axe_01")) == "", "crowd slot clips")
		print("MOUNTED SOLDIER ATLAS REAL MANIFEST CHECKED")
	else:
		print("MOUNTED SOLDIER ATLAS REAL MANIFEST SKIPPED: not baked yet")

	if _failures.is_empty():
		print("SITE MOUNTED SOLDIER ATLAS TEST PASS")
		quit(0)
	else:
		for failure: String in _failures: print("FAIL: ", failure)
		quit(1)
