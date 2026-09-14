extends SceneTree
## Actual first-eight staging outputs; no synthetic complete-frame metadata.
const Reader = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const CATALOG := "res://output/terrain_army_missing_gear_20260913/full/admission_catalog.json"

func _initialize() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.BASE_MANIFEST))
	var unarmed := Plan.appearance_for(0, baseline.appearance)
	assert(Reader.set_catalog_path(CATALOG))
	assert(Reader.supports(unarmed), "All five actual m00 batches must form one complete 536-key recipe")
	assert(Reader._pages.is_empty(), "Admitting complete metadata must not eagerly decode pages")
	assert(not Reader.supports(Plan.appearance_for(1, baseline.appearance)), "Three actual m01 batches must remain unavailable")
	var wake := Reader.frame(unarmed, "get_up", "right", 999.0)
	assert(wake.frame == 11 and wake.resolved_pose == "get_up" and wake.texture is AtlasTexture)
	var same := Reader.frame(unarmed, "get_up", "right", 999.0)
	assert(wake.texture == same.texture and Reader._pages.size() == 1)
	var rescue := Reader.frame(unarmed, "rescue", "right", 999.0)
	assert(rescue.frame == 11 and rescue.resolved_pose == "rescue" and Reader._pages.size() == 2)
	assert(Reader.frame(unarmed, "walk_slash", "down", 0.0).is_empty())
	assert(Reader.frame(unarmed, "attack_unarmed", "down", 0.0).frame == 0)
	Reader.set_catalog_path(Reader.CATALOG)
	print("TERRAIN ARMY ACTUAL BATCH ADMISSION PASS: m00=536 ready, m01=384 rejected, wake/rescue actual compressed pages loaded only on demand")
	quit(0)
