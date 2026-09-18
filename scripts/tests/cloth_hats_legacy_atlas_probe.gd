extends SceneTree
## Replay the unchanged production validator against exact pre-task metadata.
const BEFORE := "res://output/cloth_hats_20260918/atlas_before/"
const OWNER := "res://scripts/terrain_lab/terrain_army_equipment_atlas.gd"
const BASE := "assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"
const RECIPES := "assets/characters/terrain_lab_army/standard_soldier/recipes/v1/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var validator := GDScript.new()
	validator.source_code = FileAccess.get_file_as_string(OWNER).replace('const BASE_MANIFEST := "res://'+BASE+'"', 'const BASE_MANIFEST := "'+BEFORE+BASE+'"')
	if validator.reload() != OK:
		quit(1)
		return
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BEFORE+RECIPES+"catalog.json"))
	validator.set("_sources", catalog.source_fingerprints)
	var passed := 0
	for mask in range(32):
		var batches: Array[Dictionary] = []
		for path: String in catalog.recipes[validator.Plan.recipe_key(mask)]:
			batches.append(JSON.parse_string(FileAccess.get_file_as_string(BEFORE+path.trim_prefix("res://"))))
		var result: Dictionary = validator.validate_batches(mask, batches, "res://"+RECIPES)
		print("CLOTH_HATS_LEGACY_REPLAY mask=",mask," admitted=",not result.is_empty())
		if not result.is_empty(): passed += 1
	print("CLOTH_HATS_LEGACY_REPLAY_TOTAL ",passed,"/32")
	quit(0 if passed == 32 else 1)
