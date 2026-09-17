extends SceneTree
## Provenance-only revalidation after exact original/candidate actor checks.
const ROOT := "res://assets/characters/terrain_lab_army/standard_soldier/"
const BEFORE := "res://output/site_appearance_restore_20260917/before/"
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const Candidate = preload("res://scripts/tests/fixtures/appearance_weapon_batch_install.gd")
const Dye = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Ranged = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")
var digests := {}

func _initialize() -> void:
	_run.call_deferred()

func _digest(path: String) -> String:
	if not digests.has(path): digests[path] = FileAccess.get_md5(path)
	assert(str(digests[path]).length() == 32)
	return digests[path]

func _run() -> void:
	create_timer(55.0).timeout.connect(func() -> void: push_error("Atlas revalidation deadline"); quit(1))
	var lining_batch := "--lining-batch" in OS.get_cmdline_user_args()
	var before_root := "res://output/site_appearance_lining_20260917/before/" if lining_batch else BEFORE
	var provenance := "appearance_lining_revalidation" if lining_batch else "appearance_restore_revalidation"
	var old_editor := before_root + "human_character_3d_editor.gd.txt"
	var before_source := FileAccess.get_file_as_string(old_editor).replace("\r", "")
	var expected_source := preload("res://scripts/tests/fixtures/appearance_lining_batch_install.gd").candidate_source(before_source) if lining_batch else Candidate.candidate_source(before_source)
	assert(FileAccess.get_file_as_string(EDITOR).replace("\r", "") == expected_source, "Only the tested narrow restore change is allowed")
	var files: Array[String] = ["standard_soldier_atlas.json", "dyes/v1/base.json"]
	for option: Dictionary in Ranged.Materials.OPTIONS:
		if option.id == &"none": continue
		files.append("ranged/v1/%s/manifest.json" % option.id)
		files.append("dyes/v1/%s.json" % option.id)
	assert(files.size() == 90)
	for relative: String in files:
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(before_root + "assets/" + relative))
		var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + relative))
		assert(after[provenance].previous_editor_md5 == _digest(old_editor) and after[provenance].rebaked == false)
		for path: String in before.source_fingerprints:
			assert(before.source_fingerprints[path] == _digest(old_editor if path == EDITOR else path), "Stale unrelated source: " + path)
		for path: String in after.source_fingerprints:
			assert(after.source_fingerprints[path] == _digest(path), "Current fingerprint mismatch: " + path)
		if after.has("source_manifest"):
			assert(after.source_manifest_md5 == _digest(after.source_manifest))
			assert(before.source_manifest_md5 == _digest(before_root + "assets/" + str(before.source_manifest).trim_prefix(ROOT)))
		if after.has("mask_path"): assert(after.mask_md5 == _digest(after.mask_path))
		after.erase(provenance)
		after.source_fingerprints[EDITOR] = before.source_fingerprints[EDITOR]
		if after.has("source_manifest_md5"): after.source_manifest_md5 = before.source_manifest_md5
		assert(after == before, "Pixels/frame/rect/anchor/timing/appearance metadata changed: " + relative)
		if relative.begins_with("ranged/"):
			var weapon := str(after.appearance.parts.weapon)
			assert(not Ranged.recipe(after.appearance).is_empty(), "Published recipe must remain admitted: " + weapon)
			assert(Ranged.validate_batches(weapon, [before], ROOT + relative.get_base_dir() + "/").is_empty(), "Stale source must still be rejected")
		elif relative.begins_with("dyes/"):
			var appearance: Dictionary = after.appearance.duplicate(true)
			appearance.equipment_dyes = {"armor": "123456ff"}
			assert(Dye.supports(appearance) and not Dye.entry(appearance).is_empty(), "Published dye mask must remain admitted: " + relative)
	print("APPEARANCE_RESTORE_ATLAS_PASS 90 provenance-only manifests; 44 exact recipes; 45 dye masks; old/current/parent hashes; stale-source rejection; no rebake")
	quit(0)
