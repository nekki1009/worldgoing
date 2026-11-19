extends "res://scripts/terrain_lab/terrain_army_atlas_capture.gd"
## Isolated append job using the original capture, RGBA/dye and publication path.
const WorkClips = preload("site_siege_work_clips.gd")

func _make_editor(appearance: Dictionary, masks: bool) -> bool:
	if not super._make_editor(appearance, masks): return false
	if not WorkClips.install(_editor): return _reject("Original male/female rig could not install all three private work clips")
	return true
