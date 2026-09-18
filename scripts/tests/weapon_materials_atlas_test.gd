extends "res://scripts/tests/terrain_army_ranged_atlas_test.gd"
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")

func _initialize() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.BASE_MANIFEST))
	var directory := Reader.BASE_MANIFEST.get_base_dir() + "/"
	assert(Reader.set_root_path("res://output/weapon_materials_npc_20260917/absent"))
	var count := 0
	var sources := Reader.fingerprints()
	for row: Dictionary in Reader.Materials.OPTIONS:
		if row.id == "none": continue
		var plan := Reader.plan(row.id, baseline)
		assert(not plan.is_empty() and plan.clips.any(func(clip: Dictionary) -> bool: return clip.id == "attack_jump_heavy"))
		assert(plan.appearance.parts.weapon == row.id and plan.appearance.parts.shield == "none")
		assert(Reader.recipe(plan.appearance).is_empty(), "Unbaked options must remain rejected")
		var batch := _fixture(baseline, plan, sources)
		var admitted := Reader.validate_batches(row.id, [batch], directory)
		assert(not admitted.is_empty() and admitted.sequences.size() == plan.clips.size() * plan.directions.size(), row.id)
		assert(admitted.sequences.has("attack_jump_heavy|down"))
		var attack: String = str(Reader.Materials.ATTACKS[Reader.Materials.family(StringName(row.id))])
		assert(admitted.sequences.has(attack + "|up"))
		assert(admitted.sequences["guard|down"][0].resolved_pose == Reader.guard_pose(row.id, "guard"))
		for guard: String in ["guard", "guard_raise", "guard_lower", "guard_break"]:
			assert(Atlas.normalized_clip(Reader.reference_clip(row.id, guard)) == guard)
		for failure in range(6):
			var wrong := batch.duplicate(true)
			match failure:
				0: wrong.appearance.parts.weapon = "axe_01_gold"
				1: wrong.appearance.parts.shield = "shield_heater_01"
				2: wrong.frames.pop_back(); wrong.batch.count -= 1
				3: wrong.frames[0].duration += .1
				4: wrong.frames[0].resolved_pose = "attack_spear"
				5: wrong.source_fingerprints[Reader.EXTRA_SOURCES[0]] = "stale"
			assert(Reader.validate_batches(row.id, [wrong], directory).is_empty())
		count += 1
		print("WEAPON_MATERIAL_ATLAS_CONTRACT_OPTION ", row.id)
	assert(count == 44 and not Reader.supports_weapon("none") and not Reader.supports_weapon("axe_01_gold"))
	print("WEAPON_MATERIAL_ATLAS_CONTRACT_PASS 44 exact recipes with dynamic frames including jump heavy; guard-family timing, incomplete/mixed/stale/unsupported rejection; metadata only")
	quit(0)
