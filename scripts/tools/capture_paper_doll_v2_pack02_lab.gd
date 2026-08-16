extends SceneTree

## Opens the actual Pack 02 lab scene and captures the four required states.
## This is deliberately a scene-level smoke test: the contact-sheet builder
## proves the composer, while this probe proves that the deliverable can be
## instantiated by Godot and that its controls drive the same recipe path.

const OUTPUT_DIR := "res://preview/paper_doll_v2/pack_02"

var _failures: PackedStringArray = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/ui/PaperDollV2Pack02Lab.tscn") as PackedScene
	_check(packed != null, "Pack02 lab scene could not be loaded")
	if packed == null:
		_finish()
		return
	# Keep this probe dynamically typed.  The scene script is intentionally a
	# local UI entry point and does not need to participate in global class-name
	# registration for the headless project scan.
	var lab = packed.instantiate()
	_check(lab != null, "Pack02 lab scene did not instantiate")
	if lab == null:
		_finish()
		return
	get_root().add_child(lab)
	await _settle()
	_check(lab.catalog != null, "Pack02 lab catalog is null")
	_check(lab.catalog != null and lab.catalog.last_issues.is_empty(), "Pack02 lab catalog issues: %s" % (lab.catalog.last_issues if lab.catalog != null else []))
	_check(lab.slot_options.size() == 11, "Pack02 lab slot surface is %d, expected 11" % lab.slot_options.size())
	_check(lab.composer != null and lab.composer.visible, "Pack02 lab composer is not visible")
	_check(lab.composer != null and lab.composer.visible_sprite_count() > 0, "Pack02 lab has no visible layers")
	_check(_save_root("pack02_lab_male_on_foot.png"), "male on-foot capture failed")

	lab._on_mounted_toggled(true)
	await _settle()
	_check(lab.state == PaperDollV2Contract.RenderState.MOUNTED, "mounted toggle did not change state")
	_check(lab.composer.visible_sprite_count() > 0, "mounted Pack02 preview is empty")
	_check(_save_root("pack02_lab_male_mounted.png"), "male mounted capture failed")

	lab._on_gender_selected(PaperDollV2Contract.Gender.FEMALE)
	await _settle()
	_check(lab.gender == PaperDollV2Contract.Gender.FEMALE, "female selection did not change gender")
	_check(lab._body_visual_id() == &"body_female_default_mounted_unisex", "female mounted body route is %s" % lab._body_visual_id())
	_check(_save_root("pack02_lab_female_mounted.png"), "female mounted capture failed")

	lab._on_mounted_toggled(false)
	await _settle()
	_check(lab._body_visual_id() == &"body_female_default_on_foot_unisex", "female on-foot body route is %s" % lab._body_visual_id())
	_check(_save_root("pack02_lab_female_on_foot.png"), "female on-foot capture failed")

	if _failures.is_empty():
		print("PAPER_DOLL_V2_PACK02_LAB_CAPTURE_PASS outputs=4 slots=%d" % lab.slot_options.size())
	else:
		for failure: String in _failures:
			push_error("PAPER_DOLL_V2_PACK02_LAB_CAPTURE_FAIL: %s" % failure)
		print("PAPER_DOLL_V2_PACK02_LAB_CAPTURE_FAIL failures=%d" % _failures.size())
	_finish()

func _save_root(file_name: String) -> bool:
	var image := get_root().get_texture().get_image()
	if image == null or image.is_empty():
		return false
	var path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return image.save_png(path) == OK

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	quit(0 if _failures.is_empty() else 1)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
