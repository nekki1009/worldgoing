extends SceneTree
## Canonical bounded GPU helper must launch this script; never self-launches.
const Work = preload("../terrain_lab/site_siege_work_append.gd")
const Clips = preload("../terrain_lab/site_siege_work_clips.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Baker = preload("res://scripts/tools/bake_terrain_army_soldier.gd")
var _started := 0
var _output := ""
var _old_fingerprints := {}
var _completed := 0

func _initialize() -> void:
	_started = Time.get_ticks_msec()
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1 or not arguments[0].begins_with("--output=res://output/"):
		push_error("Work append bake requires one fresh --output=res://output/<named-stage>")
		quit(2)
		return
	_output = arguments[0].trim_prefix("--output=").simplify_path().trim_suffix("/")
	if DirAccess.dir_exists_absolute(_output) or DisplayServer.get_name() == "headless":
		push_error("Work append needs a fresh directory and the shared GPU lease")
		quit(2)
		return
	_old_fingerprints = Baker.RecipePlan.fingerprints()
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error(message)
	quit(1)
	return false

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started > 220000:
		push_error("Work append exceeded its explicit 220-second deadline")
		quit(90)
	return false

func _run() -> void:
	if not _check(Atlas._load_base(), "Original base atlas manifest missing"): return
	for body in range(2):
		var appearance: Dictionary = Atlas._base.appearance.duplicate(true) if body == 0 else Atlas.female_appearance()
		appearance.body = float(body)
		if not _check(HumanCharacter3DEditor.valid_appearance(appearance), "Original body recipe missing"): return
		var stage := _output + ("/male" if body == 0 else "/female")
		if not _check(await Work.prepare(root, appearance, stage), "Original RGBA/dye work capture failed for body " + str(body)): return
		var editor := HumanCharacter3DEditor.new()
		editor.preview_host = root
		editor.visual_state.body_index = body
		root.add_child(editor)
		editor.open()
		if not _check(editor.restore_appearance(appearance), "Work asset verification changed the real equipment recipe"): return
		var library := editor.animation_player.get_animation_library(&"")
		var original: Dictionary = {}
		for name: StringName in library.get_animation_list(): original[name] = library.get_animation(name)
		if not _check(Clips.install(editor), "Private original library installation failed"): return
		library = editor.animation_player.get_animation_library(&"")
		for name: StringName in original:
			if not _check(is_same(original[name], library.get_animation(name)), "Required original clip resource was replaced: " + str(name)): return
		var appendix := AnimationLibrary.new()
		for clip: String in Clips.DURATIONS:
			var animation := library.get_animation(StringName(clip))
			var arm := Clips._track(animation, "J_Bip_L_UpperArm")
			if not _check(arm >= 0 and animation.track_get_key_count(arm) == 9 and not animation.rotation_track_interpolate(arm, 0.0).is_equal_approx(animation.rotation_track_interpolate(arm, animation.length * 0.25)), "Work clip lacks real authored arm motion: " + clip): return
			if not _check(appendix.add_animation(StringName(clip), animation.duplicate(true)) == OK, "Work asset library append failed"): return
			for direction: String in ["down", "left", "up", "right"]:
				var first := Work.frame(appearance, clip, direction, 0.0)
				var later := Work.frame(appearance, clip, direction, animation.length * 0.5)
				if not _check(not first.is_empty() and not later.is_empty() and first.frame != later.frame, "Work atlas did not advance its native frame: " + clip + "/" + direction): return
				var a: Image = first.texture.get_image()
				var b: Image = later.texture.get_image()
				if not _check(a != null and b != null and a.get_data() != b.get_data(), "Work GPU image stayed unchanged: " + clip + "/" + direction): return
				if direction == "down":
					if not _check(a.save_png(stage + "/" + clip + "_start.png") == OK and b.save_png(stage + "/" + clip + "_middle.png") == OK, "Could not preserve work visual proof"): return
		if not _check(ResourceSaver.save(appendix, stage + "/work_clips.tres") == OK, "Could not save the three explicit AnimationLibrary assets"): return
		if not _check(Atlas.supports(appearance) and Baker.RecipePlan.fingerprints() == _old_fingerprints, "An existing mandatory source or atlas was invalidated"): return
		var viewport: SubViewport = editor.preview_viewport
		editor.free()
		if is_instance_valid(viewport): viewport.free()
		_completed += 1
	if not _check(_completed == 2, "Both original bodies must complete work capture before PASS"): return
	print("SITE_SIEGE_WORK_APPEND_BAKE_PASS: original male/female private work AnimationLibrary, three moving clips/four directions, untouched required clip resources and source fingerprints, original GPU RGBA+dye capture and unchanged required EquipmentAtlas admission; asset proof only, no formal gameplay/native claim")
	quit(0)
