extends SceneTree
## Keep strict source guards after the proven empty-query-only change.
const ROOT := "res://assets/characters/terrain_lab_army/standard_soldier/"
const BASE := "res://output/site_army_exchange_spikes_20260915/baseline/"
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const FILES := ["standard_soldier_atlas.json", "ranged/v1/bow_01/manifest.json", "ranged/v1/crossbow_01/manifest.json", "dyes/v1/base.json", "dyes/v1/bow_01.json", "dyes/v1/crossbow_01.json"]
const Dye = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Ranged = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(1))
	var old_editor := BASE + "human_character_3d_editor.gd.baseline"
	var before_source := FileAccess.get_file_as_string(old_editor).replace("\r", "")
	var after_source := FileAccess.get_file_as_string(EDITOR).replace("\r", "")
	var original := "func _find_component_nodes(prefixes: Array) -> Array:\n\tvar result: Array = []\n\tif model_root == null:"
	assert(before_source.count(original) == 1)
	assert(before_source.replace(original, original.trim_suffix(":") + " or prefixes.is_empty():") == after_source)
	for relative: String in FILES:
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "assets/" + relative))
		var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + relative))
		assert(after.empty_component_revalidation.previous_editor_md5 == FileAccess.get_md5(old_editor) and after.empty_component_revalidation.rebaked == false)
		for path: String in before.source_fingerprints:
			assert(before.source_fingerprints[path] == FileAccess.get_md5(old_editor if path == EDITOR else path))
		for path: String in after.source_fingerprints:
			assert(after.source_fingerprints[path] == FileAccess.get_md5(path))
		if after.has("source_manifest"):
			assert(after.source_manifest_md5 == FileAccess.get_md5(after.source_manifest))
			assert(before.source_manifest_md5 == FileAccess.get_md5(BASE + "assets/" + str(before.source_manifest).trim_prefix(ROOT)))
		if after.has("mask_path"): assert(after.mask_md5 == FileAccess.get_md5(after.mask_path))
		after.erase("empty_component_revalidation")
		after.source_fingerprints[EDITOR] = before.source_fingerprints[EDITOR]
		if after.has("source_manifest_md5"): after.source_manifest_md5 = before.source_manifest_md5
		assert(after == before, "Preserve all frames/pixels/rects/anchors/timing/loadouts: " + relative)
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + FILES[0]))
	for weapon: String in ["longsword_01", "bow_01", "crossbow_01"]:
		var appearance: Dictionary = baseline.appearance.duplicate(true)
		appearance.parts.weapon = weapon
		if weapon != "longsword_01": appearance.parts.shield = "none"
		appearance.equipment_dyes = {"armor": "123456ff"}
		assert(Dye.supports(appearance) and not Dye.entry(appearance).is_empty())
		if weapon != "longsword_01": assert(not Ranged.recipe(appearance).is_empty())
	print("EMPTY_COMPONENT_ATLAS_PASS one-line-only source change; six provenance-only manifests; all previous/current/parent/mask hashes; three dyed loadouts; no rebake")
	quit(0)
