extends "res://scripts/tests/site_army_component_lookup_test.gd"
## Original private-query playback versus manual cache reuse, plus the original
## HumanEditor reference. Run the inherited six bounded equipment groups.

var original_pose_us := 0
var reused_pose_us := 0
var animation_cases := 0

func _bones(source: Variant) -> Array:
	var result := []
	for index: int in source.skeleton.get_bone_count():
		result.append([source.skeleton.get_bone_pose(index), source.skeleton.get_bone_global_pose(index)])
	return result

func compare_pose(source: Variant, actor: TerrainTestCharacter, appearance: Dictionary, clip: StringName, time: float, direction: Vector2i) -> Dictionary:
	assert(source.editor.get("manual_query_playback_enabled") != null)
	var editor: Variant = source.editor
	editor.manual_query_playback_enabled = false
	var started: int = int(source.profile_usec.pose)
	var original := super.compare_pose(source, actor, appearance, clip, time, direction)
	original_pose_us += int(source.profile_usec.pose) - started
	var original_bones := _bones(source)
	var original_armor := _armor_vertices(source, appearance)
	editor.manual_query_playback_enabled = true
	started = int(source.profile_usec.pose)
	var reused := super.compare_pose(source, actor, appearance, clip, time, direction)
	reused_pose_us += int(source.profile_usec.pose) - started
	assert(reused == original, "Manual animation cache reuse preserves every exact projected sample field")
	assert(_bones(source) == original_bones, "Every original local/global bone transform remains exactly equal")
	assert(_armor_vertices(source, appearance) == original_armor, "All worn original morph/armor vertices remain exactly equal")
	assert(editor.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	animation_cases += 1
	return reused

func run() -> void:
	await super.run()
	assert(animation_cases > 0)
	var report := {"group": group, "paired_cases": animation_cases, "original_pose_usec": original_pose_us,
		"reused_pose_usec": reused_pose_us, "exact": true,
		"source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"scope": "Same-source original/manual playback exact pose and armor comparison; raw HumanEditor reference retained; not FPS"}
	var path := "res://output/site_combat_performance_20260913/animation_cache/group_%d.json" % group
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE_ARMY_ANIMATION_CACHE_PASS ", JSON.stringify(report))
