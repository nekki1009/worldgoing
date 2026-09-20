extends SceneTree
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Editor = preload("res://scripts/ui/human_character_3d_editor.gd")
var checks := 0

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("Mixed atlas test did not finish"); quit(1))
	_run.call_deferred()

func option(slot_id: String, material: String, culture: String) -> String:
	for slot: Dictionary in Editor.PART_SLOTS:
		if str(slot.id) != slot_id: continue
		for part: Dictionary in slot.options:
			if part.get("material") == material and part.get("culture") == culture: return str(part.id)
	return ""

func _run() -> void:
	var keys := {}
	for body in range(2):
		for culture: String in ["chinese", "japanese", "western"]:
			for head: String in ["cloth", "leather", "iron", "steel"]:
				for armor: String in ["cloth", "leather", "iron", "steel"]:
					for boots: String in ["cloth", "leather", "iron", "steel"]:
						for shield: String in ["wood", "stone", "iron", "steel"]:
							var appearance := Editor.default_appearance(body)
							for slot: String in ["helmet", "armor", "boots", "shield"]:
								appearance.parts[slot] = option(slot, {"helmet": head, "armor": armor, "boots": boots, "shield": shield}[slot], culture)
							var plan := Atlas.mixed_plan(appearance)
							assert(not plan.is_empty())
							assert(str(plan.key).length() == 64)
							assert(JSON.parse_string(JSON.stringify(plan.appearance)) == JSON.parse_string(JSON.stringify(appearance)), "Plan preserves every actual appearance field")
							assert(plan.recipe_total == 632 and plan.clips.size() == 20, str(plan.recipe_total))
							assert(not keys.has(plan.key), "Each independent material mixture has its exact picture key")
							keys[plan.key] = true
							appearance.equipment_dyes = Editor.EquipmentDye.PRESETS.values()[checks % 16].colors.duplicate()
							appearance.equipment_dyes.erase("cape")
							assert(Atlas.mixed_plan(appearance).key == plan.key, "Colors share geometry; never need sixteen copies")
							checks += 1
	for body in range(2):
		for weapon: Dictionary in Editor.WeaponMaterials.OPTIONS:
			for shield: String in ["none", "shield_heater_01"]:
				var appearance := Editor.default_appearance(body)
				appearance.parts.weapon = str(weapon.id)
				appearance.parts.shield = shield
				var plan := Atlas.mixed_plan(appearance)
				assert(not plan.is_empty())
				var ids := {}
				for clip: Dictionary in plan.clips:
					assert(not clip.has("weapon") and not clip.has("shield"))
					ids[clip.id] = true
					if str(clip.id).begins_with("guard"):
						var expected := str(clip.id)
						if shield == "none" and str(weapon.id) != "none": expected = Atlas.RangedAtlas.guard_pose(str(weapon.id), expected)
						assert(str(clip.get("pose", clip.id)) == expected)
				assert(ids.has(str(Editor.WeaponMaterials.ATTACKS[Editor.WeaponMaterials.family(StringName(weapon.id))])))
				assert(ids.has("attack_unarmed") and ids.has("attack_jump_heavy"))
				if Editor.WeaponMaterials.is_ranged(StringName(weapon.id)):
					assert(ids.has("reload_bow" if Editor.WeaponMaterials.family(StringName(weapon.id)) == &"bow_01" else "reload_crossbow"))
				assert(plan.key == Atlas.mixed_plan(JSON.parse_string(JSON.stringify(appearance))).key)
				checks += 1
	var rejected := Editor.default_appearance(0)
	rejected.parts.helmet = "not_a_real_item"
	assert(Atlas.mixed_plan(rejected).is_empty())
	rejected = Editor.default_appearance(0)
	rejected.mounted = true
	assert(Atlas.mixed_plan(rejected).is_empty(), "Mixed foot recipes never impersonate riders")
	var cached := Editor.default_appearance(0)
	var cached_key := Atlas._mixed_key(cached)
	Atlas._mixed[cached_key] = {"source_manifest": "res://output/cache-negative/manifest.json"}
	Atlas._female_dye["res://output/cache-negative"] = {"complete": true}
	cached.equipment_dyes = {"weapon": "not_a_color"}
	assert(not Atlas.supports(cached) and Atlas.dye_entry(cached).is_empty() and Atlas.mixed_recipe(cached).is_empty(), "Cache hits never bypass appearance/dye validation")
	Atlas._mixed.erase(cached_key)
	Atlas._female_dye.erase("res://output/cache-negative")
	print("EQUIPMENT_MIXED_PLAN_PASS ", checks, " cases; three cultures, independent materials, both sexes, all weapons, original full clips")
	quit()
