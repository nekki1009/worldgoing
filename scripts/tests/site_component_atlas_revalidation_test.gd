extends SceneTree
## Revalidate semantic-only source changes without pretending to rebake pixels.
const ROOT := "res://assets/characters/terrain_lab_army/standard_soldier/"
const BEFORE := "res://output/site_army_scale_phase13_20260915/before_assets/"
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const OLD_EDITOR := "res://output/site_army_scale_phase13_20260915/before_source/human_character_3d_editor.gd.txt"
const FILES := ["standard_soldier_atlas.json", "ranged/v1/bow_01/manifest.json", "ranged/v1/crossbow_01/manifest.json", "dyes/v1/base.json", "dyes/v1/bow_01.json", "dyes/v1/crossbow_01.json"]
const Dye = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Ranged = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func _find_component_nodes\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
	var before_source := FileAccess.get_file_as_string(OLD_EDITOR).replace("\r", "")
	var after_source := FileAccess.get_file_as_string(EDITOR).replace("\r", "")
	assert(matcher.search_all(before_source).size() == 1 and matcher.search_all(after_source).size() == 1)
	assert(matcher.sub(before_source, "") == matcher.sub(after_source, ""), "Other editor changes cannot use this equivalence proof")
	assert(matcher.search(before_source).get_string().strip_edges() == FileAccess.get_file_as_string("res://scripts/tests/fixtures/human_editor_components_phase12.gd.txt").strip_edges())
	for relative: String in FILES:
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BEFORE + relative))
		var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + relative))
		assert(after.source_equivalence_revalidation.previous_editor_md5 == FileAccess.get_md5(OLD_EDITOR) and after.source_equivalence_revalidation.rebaked == false)
		for path: String in after.source_fingerprints:
			assert(after.source_fingerprints[path] == FileAccess.get_md5(path), "Keep strict current source fingerprints: " + path)
		for path: String in before.source_fingerprints:
			assert(before.source_fingerprints[path] == FileAccess.get_md5(OLD_EDITOR if path == EDITOR else path), "Never admit an already stale unrelated source")
		if after.has("source_manifest"):
			assert(after.source_manifest_md5 == FileAccess.get_md5(after.source_manifest))
			assert(before.source_manifest_md5 == FileAccess.get_md5(BEFORE + str(before.source_manifest).trim_prefix(ROOT)))
		if after.has("mask_path"):
			assert(after.mask_md5 == FileAccess.get_md5(after.mask_path))
		after.erase("source_equivalence_revalidation")
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
	print("COMPONENT_ATLAS_REVALIDATION_PASS six provenance-only manifests, all current/previous sources and parent/mask hashes, original frames unchanged, three dyed loadouts admitted; no rebake")
	quit(0)
