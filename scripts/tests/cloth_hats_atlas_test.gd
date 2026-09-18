extends SceneTree
## Current real atlas admission, with unchanged data and stale-source rejection.
var OUT := "res://output/cloth_hats_20260918/"
var stamp := "cloth_hats_additive_revalidation"
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Ranged = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")
const Dyes = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Rider = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
var hashes := {}

func _initialize() -> void:
	_run.call_deferred()

func digest(path: String) -> String:
	if not hashes.has(path): hashes[path] = FileAccess.get_md5(path)
	assert(str(hashes[path]).length() == 32)
	return hashes[path]

func _run() -> void:
	if "--neutral-faces" in OS.get_cmdline_user_args():
		OUT = "res://output/neutral_faces_20260918/"
		stamp = "neutral_faces_additive_revalidation"
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT+"atlas_snapshot.json"))
	var manifest_count := 0
	for path: String in snapshot.active:
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT+"atlas_before/"+path.trim_prefix("res://")))
		var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert(current[stamp].rebaked == false)
		for source: String in current.source_fingerprints:
			assert(current.source_fingerprints[source] == digest(source),source)
			current.source_fingerprints[source] = old.source_fingerprints[source]
		if current.has("source_manifest_md5"):
			assert(current.source_manifest_md5 == digest(current.get("source_manifest", Atlas.BASE_MANIFEST)),path)
			current.source_manifest_md5 = old.source_manifest_md5
		if current.has("mask_path"): assert(current.mask_md5 == digest(current.mask_path))
		current.erase(stamp)
		assert(current == old,"Existing frame/pose/page/dye/anchor data changed: "+path)
		manifest_count += 1
	assert(manifest_count == 254)
	for mask in range(32):
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT+"atlas_before/assets/characters/terrain_lab_army/standard_soldier/recipes/v1/m%02d/000_128/manifest.json" % mask))
		assert(before.batch.recipe_total == 584 and before.clips.any(func(c: Dictionary) -> bool: return c.id == "attack_jump_heavy"))
		assert(Atlas.Plan.COMMON_CLIPS.has("attack_jump_heavy"))
		assert(not Atlas._recipe(mask).is_empty(),"Original equipment mask must remain admitted: %d" % mask)
	for option: Dictionary in Ranged.Materials.OPTIONS:
		if option.id == &"none": continue
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT+"atlas_before/assets/characters/terrain_lab_army/standard_soldier/ranged/v1/"+str(option.id)+"/manifest.json"))
		var appearance: Dictionary = before.appearance.duplicate(true)
		appearance.equipment_dyes = {"armor":"396fbbff"}
		assert(Atlas.supports(appearance) and not Dyes.entry(appearance).is_empty(),str(option.id))
		assert(not Atlas.frame(appearance,"run","down",.2).is_empty())
		assert(Ranged.validate_batches(str(option.id),[before],Ranged.ROOT+"/"+str(option.id)+"/").is_empty(),"Old source must still be rejected")
	var female := Atlas.female_appearance()
	female.equipment_dyes = {"armor":"396fbbff"}
	assert(Atlas.supports(female) and not Atlas.dye_entry(female).is_empty())
	assert(not Atlas.frame(female,"run","down",.2).is_empty())
	assert(Rider._load_manifest())
	for appearance: Dictionary in Rider._manifest.appearances:
		assert(Rider.supports(appearance))
		assert(not Rider.frame(appearance,"down",true,.3).is_empty())
		if stamp == "neutral_faces_additive_revalidation":
			for number in range(5,9):
				var new_face := appearance.duplicate(true)
				new_face.parts.face = "face_standard_%02d" % number
				assert(not Atlas.supports(new_face) and not Rider.supports(new_face),"New faces require their own actual NPC bake")
		for style in ["chinese","japanese","western"]:
			var unbaked := appearance.duplicate(true)
			unbaked.parts.helmet = "helmet_cloth_"+style+"_01"
			assert(not Atlas.supports(unbaked) and not Rider.supports(unbaked),"New hats need their own actual NPC bake")
	print("CLOTH_HATS_ATLAS_PASS 254 provenance-only manifests; 32 original equipment recipes admitted; 44 materials + dyes; female + both riders; stale/new-unbaked hats rejected")
	quit(0)
