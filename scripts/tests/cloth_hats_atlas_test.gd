extends SceneTree
## Current real atlas admission, with unchanged data and stale-source rejection.
var OUT := "res://output/cloth_hats_20260918/"
var stamp := "cloth_hats_additive_revalidation"
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Ranged = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")
const Dyes = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Rider = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
var hashes := {}
var matrix := false
var limits := false

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
	if "--equipment-matrix" in OS.get_cmdline_user_args():
		OUT = "res://output/equipment_matrix_20260918/"
		stamp = "equipment_matrix_additive_revalidation"
		matrix = true
	if "--equipment-limits" in OS.get_cmdline_user_args():
		OUT = "res://output/equipment_limits_20260919/"
		stamp = "equipment_limits_revalidation"
		matrix = true
		limits = true
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT+"atlas_snapshot.json"))
	if stamp == "equipment_matrix_additive_revalidation":
		var supplement: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT+"atlas_wagon_snapshot.json"))
		assert(supplement.active.size() == 3)
		snapshot.active.merge(supplement.active)
	var manifest_count := 0
	for path: String in snapshot.active:
		if limits and path == Rider.ROOT + "manifest.json":
			assert(digest(path) == snapshot.active[path], "Historical armed rider must not be falsely recertified")
			continue
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
	assert(manifest_count == (260 if limits else (261 if matrix else 254)))
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
	assert(not Rider._load_manifest() if limits else Rider._load_manifest())
	if matrix:
		assert(Rider._load_manifest(true))
		for body in [0,1]:
			var cloth := Rider.ClothRecipe.appearance(body)
			assert(Atlas.supports(cloth), "Original cloth foot recipe must remain admitted")
			for clip in ["idle","walk","run"]:
				assert(not Atlas.frame(cloth,clip,"down",.2).is_empty())
	var rider_inputs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Rider.ROOT + "manifest.json")) if limits else Rider._manifest
	for appearance: Dictionary in rider_inputs.appearances:
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
			assert(not Atlas.supports(unbaked),"New hats need their own actual ordinary NPC bake")
			if matrix: fixed_cloth_rider(unbaked, appearance)
			else: assert(not Rider.supports(unbaked))
		if matrix:
			var rejected := 0
			for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
				for option: Dictionary in slot.options:
					if not option.get("prefixes", []).any(func(prefix: String) -> bool: return prefix in HumanCharacter3DEditor.AUTHORED_MATRIX_PREFIXES): continue
					var unbaked := appearance.duplicate(true)
					unbaked.parts[str(slot.id)] = str(option.id)
					assert(not Atlas.supports(unbaked), "New matrix part needs a real ordinary NPC recipe: " + str(option.id))
					fixed_cloth_rider(unbaked, appearance)
					rejected += 1
			assert(rejected == 27)
			var invalid := appearance.duplicate(true)
			invalid.parts.armor = "__nonexistent_armor"
			assert(not Atlas.supports(invalid) and not Rider.supports(invalid))
	print("CLOTH_HATS_ATLAS_PASS ", manifest_count, " provenance-only manifests; 32 original equipment recipes admitted; 44 materials + dyes; female; fixed-cloth riders + foot; stale/new ordinary equipment rejected")
	quit(0)

func fixed_cloth_rider(actual: Dictionary, original: Dictionary) -> void:
	# Existing user policy: wagon-mounted display is fixed cloth by gender,
	# independent of valid real gear; this never admits the new ordinary atlas.
	var unchanged := actual.duplicate(true)
	assert(Rider.supports(actual))
	var base := Rider.frame(original,"down",true,.3)
	var shown := Rider.frame(actual,"down",true,.3)
	assert(not shown.is_empty() and shown.key == base.key and shown.texture == base.texture)
	assert(actual == unchanged, "Mounted display must not mutate actual equipment")
