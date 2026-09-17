extends SceneTree
const ROOT := "res://assets/characters/terrain_lab_army/standard_soldier/"
const BASE := "res://output/site_army_actor_spikes_20260916/before/"
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
	assert(matcher.search_all(after_source).size() == 1)
	var restored := after_source.replace(matcher.search(after_source).get_string(), "")
	restored = restored.replace("\tvar weapon_components: Array = _part_definition(&\"weapon\").get(\"options\", [])\n\tvar weapon_groups := _weapon_component_groups(weapon_components)\n\tfor component_index in weapon_components.size():\n\t\tvar component: Dictionary = weapon_components[component_index]", "\tfor component: Dictionary in _part_definition(&\"weapon\").get(\"options\", []):")
	restored = restored.replace("\t\tfor node in weapon_groups[component_index]:", "\t\tfor node in _find_component_nodes(component.get(\"prefixes\", [])):")
	assert(restored == before_source, "No other editor behavior changed")
	for relative: String in FILES:
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "assets/" + relative))
		var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + relative))
		assert(after.weapon_group_revalidation.previous_editor_md5 == FileAccess.get_md5(old_editor) and after.weapon_group_revalidation.rebaked == false)
		for path: String in before.source_fingerprints:
			assert(before.source_fingerprints[path] == FileAccess.get_md5(old_editor if path == EDITOR else path), "Never admit stale unrelated source: " + path)
		for path: String in after.source_fingerprints:
			assert(after.source_fingerprints[path] == FileAccess.get_md5(path))
		if after.has("source_manifest"):
			assert(after.source_manifest_md5 == FileAccess.get_md5(after.source_manifest))
			assert(before.source_manifest_md5 == FileAccess.get_md5(BASE + "assets/" + str(before.source_manifest).trim_prefix(ROOT)))
		if after.has("mask_path"): assert(after.mask_md5 == FileAccess.get_md5(after.mask_path))
		after.erase("weapon_group_revalidation")
		after.source_fingerprints[EDITOR] = before.source_fingerprints[EDITOR]
		if after.has("source_manifest_md5"): after.source_manifest_md5 = before.source_manifest_md5
		assert(after == before, "Preserve all atlas pixels/frame/rect/anchor/timing/appearance values: " + relative)
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + FILES[0]))
	for weapon: String in ["longsword_01", "bow_01", "crossbow_01"]:
		var appearance: Dictionary = baseline.appearance.duplicate(true)
		appearance.parts.weapon = weapon
		if weapon != "longsword_01": appearance.parts.shield = "none"
		appearance.equipment_dyes = {"armor": "123456ff"}
		assert(Dye.supports(appearance) and not Dye.entry(appearance).is_empty())
		if weapon != "longsword_01": assert(not Ranged.recipe(appearance).is_empty())
	print("WEAPON_GROUPS_ATLAS_PASS grouping-only source change; six provenance-only manifests; strict old/current/parent/mask hashes; three dyed loadouts; no rebake")
	quit(0)
