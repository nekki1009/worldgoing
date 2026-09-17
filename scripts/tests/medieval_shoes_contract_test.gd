extends SceneTree
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const OrdersTest = preload("res://scripts/tests/site_equipment_orders_test.gd")
const Dye = preload("res://scripts/ui/equipment_dye.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(Dye.PRESETS.size() == 16)
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 714, {"size":Vector2i(32,32)})
	Env.initialize(data,"medieval-shoes-test")
	assert(Runtime.initialize_item_storage(data.site).ok)
	data.site.next_person_id = 7
	data.site.actors = {}
	data.site.armies = []
	var person_id := 0
	var holders: Array[Dictionary] = []
	for gender in range(2):
		for style: String in ["chinese","japanese","european"]:
			person_id += 1
			var appearance := HumanCharacter3DEditor.default_appearance(gender)
			appearance.parts.armor = "outfit_medieval_"+style+"_01"
			appearance.parts.boots = "boots_medieval_"+style+"_01"
			assert(HumanCharacter3DEditor.valid_appearance(appearance))
			var holder := {}
			assert(Runtime.seed_person_equipment(data,holder,person_id,appearance).ok)
			var item: String = holder.equipped.boots
			var armor: String = holder.equipped.armor
			var underwear: String = holder.equipped.outfit
			var before: Dictionary = data.site.item_records[item].duplicate(true)
			var before_armor: Dictionary = data.site.item_records[armor].duplicate(true)
			var before_underwear: Dictionary = data.site.item_records[underwear].duplicate(true)
			for palette: String in Dye.PRESETS:
				assert(Runtime.dye_equipment(data,holder,{"boots":Dye.PRESETS[palette].colors.boots},holder.version).ok)
				assert(Runtime.equipment_appearance(data,holder,appearance).equipment_dyes.boots == Dye.PRESETS[palette].colors.boots)
			assert(Runtime.dye_equipment(data,holder,{"boots":"29be89ff"},holder.version).ok)
			assert(data.site.item_records[armor] == before_armor and data.site.item_records[underwear] == before_underwear)
			assert(data.site.item_records[item].original_owner == before.original_owner and data.site.item_records[item].holder == before.holder)
			holders.append(holder)
	var cell := Vector2i.ZERO
	for index in range(data.size.x*data.size.y):
		if data.is_walkable(data.cell_from_index(index)):
			cell = data.cell_from_index(index)
			break
	for holder in holders:
		assert(Runtime.leave_ground_loot(data,holder,{},int(str(holder.holder).trim_prefix("person:")),cell,"remains",{},holder.item_ids.duplicate(),holder.version).ok)
	assert(Store._validate_items(data,data.site).ok)
	var path := "res://output/medieval_shoes_20260916/shoe_save.json"
	assert(Store.save(data,path).ok)
	var loaded := Store.load_site(path)
	assert(loaded.ok and loaded.data.site.item_records == data.site.item_records)
	var harness := OrdersTest.new()
	var fixture := harness._fixture()
	harness._nation(fixture)
	for style: String in ["chinese","japanese","european"]:
		var asset := "boots_medieval_"+style+"_01"
		harness._item(fixture.lab,fixture.lab.npc.item_state,"boots",asset,2)
		var slots := {"boots":{"definition":"boots:"+asset}}
		for palette: String in Dye.PRESETS:
			assert(fixture.orders.set_standard(2,"n1","shoes","布甲鞋",slots,palette).ok)
		assert(not fixture.orders.set_standard(2,"n1","shoes","布甲鞋",slots,{"boots":"29be89ff"}).ok)
		fixture.lab.terrain.site.equipment_nations.n1.military_head = 1
		assert(fixture.orders.set_standard(1,"n1","shoes","玩家布甲鞋",slots,{"boots":"29be89ff"}).ok)
		fixture.lab.terrain.site.equipment_nations.n1.military_head = 2
	harness._close(fixture)
	harness.free()
	print("MEDIEVAL_SHOES_DATA_PASS six appearances, 96 shoe dyes, independent armor/underwear, item ownership and save-load, NPC16/player free")
	quit(0)
