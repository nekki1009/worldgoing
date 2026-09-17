extends SceneTree
const Materials = preload("res://scripts/ui/weapon_materials.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(Materials.OPTIONS.size() == 45)
	for legacy in [&"longsword_01", &"spear_01", &"axe_01", &"wood_axe_01", &"hammer_01", &"dagger_01", &"bow_01", &"crossbow_01"]:
		assert(Materials.material(legacy) == "iron")
		assert(Materials.family(legacy) == legacy)
	assert(Materials.material(&"wood_axe_01_wood") == "wood")
	assert(Materials.family(&"wood_axe_01_wood") == &"wood_axe_01")
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS,714,{"size":Vector2i(32,32)})
	Env.initialize(data,"weapon-materials-test")
	assert(Runtime.initialize_item_storage(data.site).ok)
	data.site.next_person_id = 89
	data.site.actors = {}
	data.site.armies = []
	var cell := Vector2i.ZERO
	for index in range(data.size.x*data.size.y):
		if data.is_walkable(data.cell_from_index(index)):
			cell = data.cell_from_index(index)
			break
	var person_id := 0
	var counts := {"wood":0,"stone":0,"iron":0,"steel":0}
	for body in range(2):
		for row: Dictionary in Materials.OPTIONS:
			if row.id == "none":continue
			person_id += 1
			counts[row.material] += 1
			var appearance := HumanCharacter3DEditor.default_appearance(body)
			appearance.parts.weapon = row.id
			assert(HumanCharacter3DEditor.valid_appearance(appearance))
			var holder := {}
			assert(Runtime.seed_person_equipment(data,holder,person_id,appearance).ok)
			var identity: String = holder.equipped.weapon
			assert(data.site.item_records[identity].definition == "weapon:"+row.id)
			assert(data.site.item_records[identity].original_owner == person_id)
			assert(Runtime.equipment_appearance(data,holder,appearance).parts.weapon == row.id)
			var family := Materials.family(StringName(row.id))
			assert(Materials.ATTACKS.has(family))
			assert(Materials.material(StringName(row.id)) == row.material)
			if Materials.is_ranged(StringName(row.id)):
				assert(SiteCombatRules.ranged_profile(row.id) == SiteCombatRules.ranged_profile(str(family)))
			assert(Runtime.leave_ground_loot(data,holder,{},person_id,cell,"remains",{},holder.item_ids.duplicate(),holder.version).ok)
	assert(counts == {"wood":22,"stone":22,"iron":22,"steel":22})
	assert(Store._validate_items(data,data.site).ok)
	var path := "res://output/weapon_materials_20260917/equipment_save.json"
	assert(Store.save(data,path).ok)
	var loaded := Store.load_site(path)
	assert(loaded.ok and loaded.data.site.item_records == data.site.item_records)
	assert(loaded.data.site.item_definitions == data.site.item_definitions)
	var invalid := HumanCharacter3DEditor.default_appearance(0)
	invalid.parts.weapon = "wood_axe_01_gold"
	assert(not HumanCharacter3DEditor.valid_appearance(invalid))
	print("WEAPON_MATERIAL_DATA_PASS 44 options x 2 bodies; old IDs iron; family/material distinct; item identity/owner and full save-load; no balance changes")
	quit(0)
