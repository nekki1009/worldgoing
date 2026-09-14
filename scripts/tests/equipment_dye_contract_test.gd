extends SceneTree
const Dye = preload("res://scripts/ui/equipment_dye.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const OrderTest = preload("res://scripts/tests/site_equipment_orders_test.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var appearance := HumanCharacter3DEditor.default_appearance()
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581, {"size": Vector2i(32, 32)})
	Env.initialize(data, "equipment-dye-test")
	assert(Runtime.initialize_item_storage(data.site).ok)
	data.site.next_person_id = 4
	data.site.actors = {}
	data.site.armies = []
	var first := {}
	var second := {}
	assert(Runtime.seed_person_equipment(data, first, 1, appearance).ok)
	assert(Runtime.seed_person_equipment(data, second, 2, appearance).ok)
	var definitions: Dictionary = data.site.item_definitions.duplicate(true)
	var original_owner := data.site.item_records[first.equipped.armor].original_owner as int
	var colors: Dictionary = Dye.PRESETS.blue.colors
	assert(Runtime.dye_equipment(data, first, colors, first.version).ok)
	assert(Runtime.equipment_appearance(data, first, appearance).equipment_dyes == colors)
	assert(not Runtime.equipment_appearance(data, second, appearance).has("equipment_dyes"))
	assert(data.site.item_definitions == definitions and data.site.item_records[first.equipped.armor].original_owner == original_owner)
	var before: Dictionary = data.site.item_records.duplicate(true)
	for bad in [{"armor": "ff000000"}, {"armor": "NaN"}, {"weapon": "ff0000ff"}, {"cape": "#ff0000"}]:
		assert(not Runtime.dye_equipment(data, first, bad, first.version).ok)
	assert(Runtime.dye_equipment(data, first, colors, first.version - 1).code == "STALE_SOURCE")
	assert(data.site.item_records == before)
	var third := {}
	var colored := appearance.duplicate(true)
	colored.equipment_dyes = colors.duplicate()
	assert(Runtime.seed_person_equipment(data, third, 3, colored).ok)
	assert(Runtime.equipment_appearance(data, third, appearance).equipment_dyes == colors)
	var held_armor := str(first.equipped.armor)
	assert(Runtime.transfer_items(data, first, {}, data.site.depot_items, data.site.inventory, {}, [held_armor], first.version, data.site.depot_items.version, 999).ok)
	assert(data.site.item_records[held_armor].dye_color == colors.armor)
	assert(not Runtime.equipment_appearance(data, first, colored).get("equipment_dyes", {}).has("armor"))
	assert(Runtime.transfer_items(data, data.site.depot_items, data.site.inventory, third, {}, {}, [held_armor], data.site.depot_items.version, third.version).ok)
	assert(data.site.item_records[held_armor].holder == "person:3" and data.site.item_records[held_armor].original_owner == 1)
	var cell := Vector2i.ZERO
	for index in range(data.size.x * data.size.y):
		if data.is_walkable(data.cell_from_index(index)):
			cell = data.cell_from_index(index)
			break
	for holder: Dictionary in [first, second, third]:
		assert(Runtime.leave_ground_loot(data, holder, {}, int(str(holder.holder).trim_prefix("person:")), cell, "remains", {}, holder.item_ids.duplicate(), holder.version).ok)
	assert(Store._validate_items(data, data.site).ok)
	var path := "res://output/equipment_dye_20260914/dye_save.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	assert(Store.save(data, path).ok)
	var loaded := Store.load_site(path)
	assert(loaded.ok, str(loaded))
	assert(loaded.data.site.item_records == data.site.item_records)
	var record: Dictionary = loaded.data.site.item_records[held_armor]
	assert(record.dye_color == colors.armor and record.original_owner == 1)
	record.dye_color = "ffffff00"
	assert(not Store._validate_items(loaded.data, loaded.data.site).ok)
	var harness := OrderTest.new()
	var fixture := harness._fixture()
	var orders: Variant = fixture.orders
	var lab: Variant = fixture.lab
	var armor := harness._item(lab, lab.character.item_state, "armor", "armor_light_leather_01", 1, true)
	orders.equipment_dye_guard = func(_identity: int, _changes: Dictionary) -> Dictionary: return Runtime.ok() if lab.removal_allowed else Runtime.fail("UNSUPPORTED")
	assert(orders.dye_person(1, 1, {"armor": "334499ff"}).ok)
	assert(orders.dye_person(2, 1, {"armor": "991122ff"}).code == "NO_AUTHORITY")
	lab.removal_allowed = false
	assert(orders.dye_person(1, 1, {"armor": "991122ff"}).code == "UNSUPPORTED")
	assert(lab.terrain.site.item_records[armor].dye_color == "334499ff")
	lab.removal_allowed = true
	harness._nation(fixture)
	assert(orders.set_standard(2, "n1", "line", "藍軍", {"weapon": {"definition": "weapon:spear_01"}}, "blue").ok)
	assert(lab.terrain.site.item_records[armor].dye_color == "334499ff", "Standard edit repainted an item")
	assert(orders.apply_standard_dyes(2, 1, "n1", "line").ok)
	assert(lab.terrain.site.item_records[armor].dye_color == Dye.PRESETS.blue.colors.armor)
	lab.npc.captive = true
	assert(not orders.dye_person(2, 1, {"armor": "991122ff"}).ok)
	lab.npc.captive = false
	assert(orders.dye_person(1, 1, {"armor": ""}).ok)
	assert(not lab.terrain.site.item_records[armor].has("dye_color"))
	assert(orders.valid_nations(lab.terrain.site.equipment_nations, lab.terrain.site.item_definitions, {1: true, 2: true, 3: true}))
	orders.equipment_dye_guard = Callable()
	harness._close(fixture)
	harness.free()
	print("EQUIPMENT DYE CONTRACT PASS: five slots, isolated instances, defaults, strict invalid input, stale atomic refusal, original identity, transfer/loot/save/load, nationality authority, explicit presets, reset")
	quit()
