extends SceneTree
## Admit only the pixel-verified prefix lookup; no rebake or weaker fingerprint rule.
const ROOT := "res://assets/characters/terrain_lab_army/standard_soldier/"
const BASE := "res://output/site_army_weapon_prefix_20260916/before/"
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const FILES := ["standard_soldier_atlas.json", "ranged/v1/bow_01/manifest.json", "ranged/v1/crossbow_01/manifest.json", "dyes/v1/base.json", "dyes/v1/bow_01.json", "dyes/v1/crossbow_01.json"]
const Dye = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Ranged = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(1))
	var old_editor := BASE + "human_character_3d_editor.gd.txt"
	var before_source := FileAccess.get_file_as_string(old_editor).replace("\r", "")
	var after_source := FileAccess.get_file_as_string(EDITOR).replace("\r", "")
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func _weapon_component_groups\\([^\\n]*\\n.*?(?=^func )") == OK)
	assert(matcher.search_all(before_source).size() == 1 and matcher.search_all(after_source).size() == 1)
	assert(after_source.replace(matcher.search(after_source).get_string(), matcher.search(before_source).get_string()) == before_source, "Only the verified prefix lookup changed")
	for relative: String in FILES:
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "assets/" + relative))
		var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + relative))
		assert(after.weapon_prefix_revalidation.previous_editor_md5 == FileAccess.get_md5(old_editor) and after.weapon_prefix_revalidation.rebaked == false)
		for path: String in before.source_fingerprints:
			assert(before.source_fingerprints[path] == FileAccess.get_md5(old_editor if path == EDITOR else path), "Reject unrelated source drift: " + path)
		for path: String in after.source_fingerprints:
			assert(after.source_fingerprints[path] == FileAccess.get_md5(path))
		if after.has("source_manifest"):
			assert(after.source_manifest_md5 == FileAccess.get_md5(after.source_manifest))
			assert(before.source_manifest_md5 == FileAccess.get_md5(BASE + "assets/" + str(before.source_manifest).trim_prefix(ROOT)))
		if after.has("mask_path"): assert(after.mask_md5 == FileAccess.get_md5(after.mask_path))
		after.erase("weapon_prefix_revalidation")
		after.source_fingerprints[EDITOR] = before.source_fingerprints[EDITOR]
		if after.has("source_manifest_md5"): after.source_manifest_md5 = before.source_manifest_md5
		assert(after == before, "No atlas pixels/frame/rect/anchor/timing/appearance change: " + relative)
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + FILES[0]))
	for weapon: String in ["longsword_01", "bow_01", "crossbow_01"]:
		var appearance: Dictionary = baseline.appearance.duplicate(true)
		appearance.parts.weapon = weapon
		if weapon != "longsword_01": appearance.parts.shield = "none"
		appearance.equipment_dyes = {"armor": "123456ff"}
		assert(Dye.supports(appearance) and not Dye.entry(appearance).is_empty())
		if weapon != "longsword_01": assert(not Ranged.recipe(appearance).is_empty())
	print("WEAPON_PREFIX_ATLAS_PASS one lookup; six provenance-only manifests; strict old/current/parent/mask hashes; three dyed loadouts; no rebake")
	quit(0)
