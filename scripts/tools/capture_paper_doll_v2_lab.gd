extends SceneTree

const OUTPUT_DIR := "res://.visual_captures/paper_doll_v2"
const SHARE_DIR := "res://preview/paper_doll_v2"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/ui/PaperDollV2Lab.tscn") as PackedScene
	if packed == null:
		push_error("PAPER_DOLL_V2_LAB_CAPTURE_FAIL: scene missing")
		quit(1)
		return
	var lab := packed.instantiate() as PaperDollV2Lab
	get_root().add_child(lab)
	await _settle()
	if lab.catalog == null or not lab.catalog.last_issues.is_empty():
		push_error("PAPER_DOLL_V2_LAB_CAPTURE_FAIL: %s" % lab.catalog.last_issues)
		quit(1)
		return
	# Captures are evidence, not animation demos. Freeze every output on the
	# canonical front pose so a timer tick or side-facing row cannot hide a
	# facial alignment regression.
	_set_front_pose(lab)
	if not _save_root(lab, "paper_doll_v2_lab_on_foot.png"):
		quit(1)
		return
	lab._on_mounted_toggled(true)
	await _settle()
	_set_front_pose(lab)
	if not _save_root(lab, "paper_doll_v2_lab_mounted.png"):
		quit(1)
		return
	lab._on_mounted_toggled(false)
	lab._on_gender_selected(PaperDollV2Contract.Gender.FEMALE)
	await _settle()
	_set_front_pose(lab)
	if not _save_root(lab, "paper_doll_v2_lab_female_on_foot.png"):
		quit(1)
		return
	lab._on_mounted_toggled(true)
	await _settle()
	_set_front_pose(lab)
	if not _save_root(lab, "paper_doll_v2_lab_female_mounted.png"):
		quit(1)
		return
	print("PAPER_DOLL_V2_LAB_CAPTURE_PASS outputs=4")
	quit(0)

func _save_root(_lab: PaperDollV2Lab, file_name: String) -> bool:
	var image := get_root().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("PAPER_DOLL_V2_LAB_CAPTURE_FAIL: empty root capture")
		return false
	var path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if image.save_png(path) != OK:
		push_error("PAPER_DOLL_V2_LAB_CAPTURE_FAIL: save failed %s" % path)
		return false
	var share_path := ProjectSettings.globalize_path(SHARE_DIR.path_join(file_name))
	DirAccess.make_dir_recursive_absolute(share_path.get_base_dir())
	if image.save_png(share_path) != OK:
		push_error("PAPER_DOLL_V2_LAB_CAPTURE_FAIL: share save failed %s" % share_path)
		return false
	return true

func _set_front_pose(lab: PaperDollV2Lab) -> void:
	lab.playing = false
	if lab.animation_timer != null:
		lab.animation_timer.stop()
	lab._set_facing(PaperDollV2Contract.Facing.DOWN)
	lab._on_frame_changed(0)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
