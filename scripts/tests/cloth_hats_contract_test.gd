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
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS,918,{"size":Vector2i(32,32)})
	Env.initialize(data,"cloth-hats-test")
	assert(Runtime.initialize_item_storage(data.site).ok)
	data.site.next_person_id = 7
	data.site.actors = {}
	data.site.armies = []
	var person := 0
	var holders: Array[Dictionary] = []
	for gender in range(2):
		for style in ["chinese","japanese","western"]:
			person += 1
			var appearance := HumanCharacter3DEditor.default_appearance(gender)
			appearance.parts.helmet = "helmet_cloth_"+style+"_01"
			assert(HumanCharacter3DEditor.valid_appearance(appearance))
			var holder := {}
			assert(Runtime.seed_person_equipment(data,holder,person,appearance).ok)
			var item: String = holder.equipped.helmet
			var original: Dictionary = data.site.item_records[item].duplicate(true)
			var other := {}
			for slot: String in holder.equipped:
				if slot != "helmet": other[slot] = data.site.item_records[holder.equipped[slot]].duplicate(true)
			for palette: String in Dye.PRESETS:
				var color: String = Dye.PRESETS[palette].colors.helmet
				assert(Runtime.dye_equipment(data,holder,{"helmet":color},holder.version).ok)
				assert(Runtime.equipment_appearance(data,holder,appearance).equipment_dyes.helmet == color)
			assert(Runtime.dye_equipment(data,holder,{"helmet":"29be89ff"},holder.version).ok)
			for slot: String in other: assert(data.site.item_records[holder.equipped[slot]] == other[slot])
			assert(data.site.item_records[item].original_owner == original.original_owner and data.site.item_records[item].holder == original.holder)
			holders.append(holder)
	var cell := Vector2i.ZERO
	for index in range(data.size.x*data.size.y):
		if data.is_walkable(data.cell_from_index(index)):
			cell = data.cell_from_index(index)
			break
	for holder in holders:
		assert(Runtime.leave_ground_loot(data,holder,{},int(str(holder.holder).trim_prefix("person:")),cell,"remains",{},holder.item_ids.duplicate(),holder.version).ok)
	assert(Store._validate_items(data,data.site).ok)
	var save := "res://output/cloth_hats_20260918/hat_save.json"
	assert(Store.save(data,save).ok)
	var loaded := Store.load_site(save)
	assert(loaded.ok and loaded.data.site.item_records == data.site.item_records)
	var harness := OrdersTest.new()
	var fixture := harness._fixture()
	harness._nation(fixture)
	for style in ["chinese","japanese","western"]:
		var id: String = "helmet_cloth_"+style+"_01"
		harness._item(fixture.lab,fixture.lab.npc.item_state,"helmet",id,2)
		var slots := {"helmet":{"definition":"helmet:"+id}}
		for palette: String in Dye.PRESETS:
			assert(fixture.orders.set_standard(2,"n1","cloth_hat","布帽",slots,palette).ok)
		assert(not fixture.orders.set_standard(2,"n1","cloth_hat","布帽",slots,{"helmet":"29be89ff"}).ok)
		fixture.lab.terrain.site.equipment_nations.n1.military_head = 1
		assert(fixture.orders.set_standard(1,"n1","cloth_hat","玩家布帽",slots,{"helmet":"29be89ff"}).ok)
		fixture.lab.terrain.site.equipment_nations.n1.military_head = 2
	harness._close(fixture)
	harness.free()
	print("CLOTH_HATS_DATA_PASS six appearances; 96 item dyes; independent other equipment; ownership; SiteStore save/load; NPC16/player free")
	quit(0)
