extends SceneTree
## Revalidate semantic-only source changes without pretending to rebake pixels.
const ROOT := "res://assets/characters/terrain_lab_army/standard_soldier/"
const BEFORE := "res://output/site_army_scale_phase18_20260915/baseline/assets/"
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const OLD_EDITOR := "res://output/site_army_scale_phase18_20260915/baseline/human_character_3d_editor.gd.txt"
const FILES := ["standard_soldier_atlas.json", "ranged/v1/bow_01/manifest.json", "ranged/v1/crossbow_01/manifest.json", "dyes/v1/base.json", "dyes/v1/bow_01.json", "dyes/v1/crossbow_01.json"]
const Dye = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Ranged = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(25.0).timeout.connect(func() -> void: quit(1))
	var before_source := FileAccess.get_file_as_string(OLD_EDITOR).replace("\r", "")
	var after_source := FileAccess.get_file_as_string(EDITOR).replace("\r", "")
	var old_block := "\tif animation != null:\n\t\tanimation.loop_mode = Animation.LOOP_LINEAR if loop_toggle == null or loop_toggle.button_pressed else Animation.LOOP_NONE"
	var new_block := "\t# Rewriting the same Resource value needlessly invalidates animation caches.\n\t# Read the actual value, so UI changes and shared-resource edits still apply.\n\tvar requested_loop := Animation.LOOP_LINEAR if loop_toggle == null or loop_toggle.button_pressed else Animation.LOOP_NONE\n\tif animation != null and animation.loop_mode != requested_loop:\n\t\tanimation.loop_mode = requested_loop"
	assert(before_source.count(old_block) == 1 and after_source.count(new_block) == 1)
	assert(before_source.replace(old_block, new_block) == after_source, "Only the proven loop setter change can use this revalidation")
	for relative: String in FILES:
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BEFORE + relative))
		var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + relative))
		assert(after.animation_loop_revalidation.previous_editor_md5 == FileAccess.get_md5(OLD_EDITOR) and after.animation_loop_revalidation.rebaked == false)
		for path: String in after.source_fingerprints:
			assert(after.source_fingerprints[path] == FileAccess.get_md5(path), "Keep strict current source fingerprints: " + path)
		for path: String in before.source_fingerprints:
			assert(before.source_fingerprints[path] == FileAccess.get_md5(OLD_EDITOR if path == EDITOR else path), "Never admit an already stale unrelated source")
		if after.has("source_manifest"):
			assert(after.source_manifest_md5 == FileAccess.get_md5(after.source_manifest), "Current parent manifest hash: " + relative)
			assert(before.source_manifest_md5 == FileAccess.get_md5(BEFORE + str(before.source_manifest).trim_prefix(ROOT)))
		if after.has("mask_path"):
			assert(after.mask_md5 == FileAccess.get_md5(after.mask_path))
		after.erase("animation_loop_revalidation")
		after.source_fingerprints[EDITOR] = before.source_fingerprints[EDITOR]
		if after.has("source_manifest_md5"): after.source_manifest_md5 = before.source_manifest_md5
		assert(after == before, "Only provenance changes; preserve every frame/rect/anchor/timing/appearance/resource hash: " + relative)
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + FILES[0]))
	for weapon: String in ["longsword_01", "bow_01", "crossbow_01"]:
		var appearance: Dictionary = baseline.appearance.duplicate(true)
		appearance.parts.weapon = weapon
		if weapon != "longsword_01": appearance.parts.shield = "none"
		appearance.equipment_dyes = {"armor": "123456ff"}
		assert(Dye.supports(appearance) and not Dye.entry(appearance).is_empty())
		if weapon != "longsword_01": assert(not Ranged.recipe(appearance).is_empty())
	print("LOOP_ATLAS_REVALIDATION_PASS six provenance-only manifests, all current/previous sources and parent/mask hashes, original frames unchanged, three dyed loadouts admitted; no rebake")
	quit(0)
