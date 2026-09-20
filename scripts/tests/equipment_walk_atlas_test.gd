extends SceneTree
## Re-admission through unchanged real readers, never through a test bypass.
const DIR := "res://output/equipment_walk_fix_20260919/atlas/"
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Ranged = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")
const Dyes = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Rider = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
var hashes := {}

func digest(path: String) -> String:
	if not hashes.has(path): hashes[path] = FileAccess.get_md5(path)
	assert(str(hashes[path]).length() == 32)
	return hashes[path]

func _initialize() -> void:
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR+"snapshot.json"))
	var publication: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR+"publication.json"))
	assert(publication.published and publication.manifests == 260)
	var count := 0
	for path: String in snapshot.active:
		assert(digest(path) == publication.published_md5[path])
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR+"manifest_before/"+path.trim_prefix("res://")))
		var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert(current.equipment_walk_revalidation.rebaked == false)
		for source: String in current.source_fingerprints:
			assert(current.source_fingerprints[source] == digest(source),source)
		current.source_fingerprints = before.source_fingerprints
		if current.has("source_manifest_md5"):
			assert(current.source_manifest_md5 == digest(current.get("source_manifest",Atlas.BASE_MANIFEST)))
			current.source_manifest_md5 = before.source_manifest_md5
		current.erase("equipment_walk_revalidation")
		assert(current == before,"Existing data changed: "+path)
		count += 1
	assert(count == 260)
	for path: String in snapshot.payloads:
		assert(digest(path) == snapshot.payloads[path].md5,"Original page/mask changed")
	for mask in range(32): assert(not Atlas._recipe(mask).is_empty(),"Original recipe rejected")
	for option: Dictionary in Ranged.Materials.OPTIONS:
		if option.id == &"none": continue
		var source := Ranged.ROOT+"/"+str(option.id)+"/manifest.json"
		var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR+"manifest_before/"+source.trim_prefix("res://")))
		var appearance: Dictionary = original.appearance.duplicate(true)
		appearance.equipment_dyes = {"armor":"396fbbff"}
		assert(Atlas.supports(appearance) and not Dyes.entry(appearance).is_empty())
		assert(not Atlas.frame(appearance,"run","down",.2).is_empty())
		assert(Ranged.validate_batches(str(option.id),[original],Ranged.ROOT+"/"+str(option.id)+"/").is_empty(),"Stale sources admitted")
	var female := Atlas.female_appearance()
	female.equipment_dyes = {"armor":"396fbbff"}
	assert(Atlas.supports(female) and not Atlas.dye_entry(female).is_empty())
	assert(not Atlas.frame(female,"walk","down",.25).is_empty())
	assert(not Rider._load_manifest(),"Historical armed rider falsely admitted")
	assert(Rider._load_manifest(true))
	for body in [0,1]:
		var appearance := Rider.ClothRecipe.appearance(body)
		assert(Atlas.supports(appearance))
		for clip in ["idle","walk","run"]: assert(not Atlas.frame(appearance,clip,"down",.2).is_empty())
	for path: String in snapshot.excluded: assert(digest(path) == snapshot.excluded[path].file.md5)
	print("EQUIPMENT_WALK_ATLAS_READERS_PASS ",count," manifests; unchanged original payloads; stale sources rejected")
	quit(0)
