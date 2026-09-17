extends SceneTree
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const OrdersTest = preload("res://scripts/tests/site_equipment_orders_test.gd")
const Dye = preload("res://scripts/ui/equipment_dye.gd")
const Rules = preload("res://scripts/terrain_lab/site_combat_rules.gd")
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(Dye.PRESETS.size() == 16)
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581, {"size": Vector2i(32, 32)})
	Env.initialize(data, "medieval-cloth-test")
	assert(Runtime.initialize_item_storage(data.site).ok)
	data.site.next_person_id = 7
	data.site.actors = {}
	data.site.armies = []
	var person_id := 0
	var holders: Array[Dictionary] = []
	for gender in range(2):
		for style: String in ["chinese", "japanese", "european"]:
			person_id += 1
			var appearance := HumanCharacter3DEditor.default_appearance(gender)
			appearance.parts.armor = "outfit_medieval_" + style + "_01"
			assert(Rules.armor_profile(appearance.parts.armor) == {"slash": 1.0, "stab": 0.0, "blunt": 0.0, "cushion": 2.0}, "Cloth must keep the existing cloth protection, not leather/iron protection")
			assert(HumanCharacter3DEditor.valid_appearance(appearance))
			var holder := {}
			assert(Runtime.seed_person_equipment(data, holder, person_id, appearance).ok)
			var item: String = holder.equipped.armor
			assert(data.site.item_definitions[data.site.item_records[item].definition].slot == "armor")
			var underwear: String = holder.equipped.outfit
			assert(underwear != item and data.site.item_definitions[data.site.item_records[underwear].definition].asset == "outfit_underlayer_01")
			var before: Dictionary = data.site.item_records[item].duplicate(true)
			for palette: String in Dye.PRESETS:
				assert(Runtime.dye_equipment(data, holder, {"armor": Dye.PRESETS[palette].colors.armor}, holder.version).ok)
				assert(Runtime.equipment_appearance(data, holder, appearance).equipment_dyes.armor == Dye.PRESETS[palette].colors.armor)
			assert(Runtime.dye_equipment(data, holder, {"armor": "27ab83ff"}, holder.version).ok)
			assert(not data.site.item_records[underwear].has("dye_color"), "Cloth armor dye changed original underwear item")
			assert(data.site.item_records[item].original_owner == before.original_owner and data.site.item_records[item].holder == before.holder)
			holders.append(holder)
	var cell := Vector2i.ZERO
	for index in range(data.size.x * data.size.y):
		if data.is_walkable(data.cell_from_index(index)):
			cell = data.cell_from_index(index)
			break
	for holder in holders:
		assert(Runtime.leave_ground_loot(data, holder, {}, int(str(holder.holder).trim_prefix("person:")), cell, "remains", {}, holder.item_ids.duplicate(), holder.version).ok)
	assert(Store._validate_items(data, data.site).ok)
	var path := "res://output/medieval_cloth_armor_20260916/cloth_save.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	assert(Store.save(data, path).ok)
	var loaded := Store.load_site(path)
	assert(loaded.ok and loaded.data.site.item_records == data.site.item_records)
	var harness := OrdersTest.new()
	var fixture := harness._fixture()
	harness._nation(fixture)
	for style: String in ["chinese", "japanese", "european"]:
		var asset := "outfit_medieval_"+style+"_01"
		assert(not Orders.valid_definition("outfit:"+asset, {"slot": "outfit", "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}), "Cloth armor still admitted as an underwear item")
		harness._item(fixture.lab, fixture.lab.npc.item_state, "armor", asset, 2)
		var slots := {"armor": {"definition": "armor:"+asset}}
		for palette: String in Dye.PRESETS:
			assert(fixture.orders.set_standard(2, "n1", "cloth", "布衣", slots, palette).ok)
		assert(not fixture.orders.set_standard(2, "n1", "cloth", "布甲", slots, {"armor": "27ab83ff"}).ok)
		fixture.lab.terrain.site.equipment_nations.n1.military_head = 1
		assert(fixture.orders.set_standard(1, "n1", "cloth", "玩家布甲", slots, {"armor": "27ab83ff"}).ok)
		fixture.lab.terrain.site.equipment_nations.n1.military_head = 2
	harness._close(fixture)
	harness.free()
	print("MEDIEVAL_CLOTH_DATA_PASS six armor appearances, 96 armor palette/item applications, custom colors, independent original underwear, exact save-load/ownership; NPC heads restricted to 16 presets, player head freely colored")
	quit(0)
