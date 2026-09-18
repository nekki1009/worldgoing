extends SceneTree
## Actual current published pages; no synthetic complete-frame metadata.
const Reader = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const CATALOG := Reader.CATALOG

func _initialize() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.BASE_MANIFEST))
	var unarmed := Plan.appearance_for(0, baseline.appearance)
	assert(Reader.set_catalog_path(CATALOG))
	assert(Reader.supports(unarmed), "Published m00 batches must form one complete current-source recipe")
	assert(Reader._pages.is_empty(), "Admitting complete metadata must not eagerly decode pages")
	for mask: int in range(32):
		assert(Reader.supports(Plan.appearance_for(mask, baseline.appearance)), "Every published equipment recipe must be current and complete")
	var wake := Reader.frame(unarmed, "get_up", "right", 999.0)
	assert(wake.frame == 11 and wake.resolved_pose == "get_up" and wake.texture is AtlasTexture)
	var same := Reader.frame(unarmed, "get_up", "right", 999.0)
	assert(wake.texture == same.texture and Reader._pages.size() == 1)
	var rescue := Reader.frame(unarmed, "rescue", "right", 999.0)
	assert(rescue.frame == 11 and rescue.resolved_pose == "rescue" and rescue.texture is AtlasTexture and Reader._pages.size() == 1)
	assert(Reader.frame(unarmed, "walk_slash", "down", 0.0).is_empty())
	assert(Reader.frame(unarmed, "attack_unarmed", "down", 0.0).frame == 0)
	var jump := Reader.frame(unarmed, "attack_jump_heavy", "right", 999.0)
	assert(jump.frame == 11 and jump.resolved_pose == "attack_jump_heavy" and jump.texture is AtlasTexture and Reader._pages.size() == 2)
	Reader.set_catalog_path(Reader.CATALOG)
	print("TERRAIN ARMY ACTUAL BATCH ADMISSION PASS: 32 current-source recipes ready, jump/wake/rescue actual compressed pages loaded only on demand")
	quit(0)
