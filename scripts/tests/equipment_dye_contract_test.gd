extends SceneTree
const Dye = preload("res://scripts/ui/equipment_dye.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const OrderTest = preload("res://scripts/tests/site_equipment_orders_test.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_projection_guard_check()
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

# Same-call projection guard boundaries; the original dye contract above remains intact.
class ProjectionMutation:
	extends RefCounted
	var original: Dictionary
	var dye := false
	var calls := 0
	func _to_string() -> String:
		calls += 1
		if dye:
			original.equipment_dyes = {"helmet": "invalidf"}
			return "invalidf"
		original.parts.helmet = "not_a_catalog_asset"
		return "not_a_catalog_asset"

func _projection_fixture() -> Dictionary:
	var data := TerrainData.new()
	var original := HumanCharacter3DEditor.default_appearance()
	var helmet: String = original.parts.helmet
	for slot: String in Runtime.EQUIPMENT_SLOTS: original.parts[slot] = "none"
	original.parts.helmet = helmet
	var holder := Runtime.new_item_state("person:1")
	holder.item_ids.append("1")
	holder.equipped["helmet"] = "1"
	assert(Runtime._item_holder_shape(holder))
	data.site = {"item_records": {"1": {"definition": "helmet", "holder": holder.holder}},
		"item_definitions": {"helmet": {"slot": "helmet", "asset": helmet, "tint": [1.0, 1.0, 1.0, 1.0]}}}
	return {"data": data, "holder": holder, "original": original}

func _projection_guard_check() -> void:
	# A callback cannot change the catalogs that validated the saved fields.
	assert(HumanCharacter3DEditor.PART_SLOTS.is_read_only() and HumanCharacter3DEditor.HAIR_OPTIONS.is_read_only() and Dye.SLOTS.is_read_only())
	for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
		assert(slot.is_read_only() and slot.options.is_read_only())
		for option: Dictionary in slot.options: assert(option.is_read_only())
	for options: Array in HumanCharacter3DEditor.HAIR_OPTIONS:
		assert(options.is_read_only())
		for option: Dictionary in options: assert(option.is_read_only())
	var typed := _projection_fixture()
	var parts: Dictionary[String, String] = {}
	parts.assign(typed.original.parts)
	var dyes: Dictionary[String, String] = {"helmet": "123456ff"}
	typed.original.parts = parts
	typed.original.equipment_dyes = dyes
	typed.original.body = 0.0
	typed.data.site.item_records["1"].dye_color = "123456ff"
	parts.make_read_only()
	dyes.make_read_only()
	typed.original.make_read_only()
	var before := var_to_bytes([typed.original, typed.holder, typed.data.site])
	var projected := Runtime.equipment_appearance(typed.data, typed.holder, typed.original)
	assert(projected == typed.original and HumanCharacter3DEditor.valid_appearance(projected))
	projected.parts.helmet = "none"
	projected.equipment_dyes.helmet = "ff0000ff"
	assert(before == var_to_bytes([typed.original, typed.holder, typed.data.site]))
	var named := _projection_fixture()
	var named_parts: Dictionary[StringName, StringName] = {}
	for key: String in named.original.parts: named_parts[StringName(key)] = StringName(named.original.parts[key])
	named.original.parts = named_parts
	named.original.equipment_dyes = {}
	named.original.equipment_dyes.make_read_only()
	named_parts.make_read_only()
	projected = Runtime.equipment_appearance(named.data, named.holder, named.original)
	assert(not projected.is_empty() and HumanCharacter3DEditor.valid_appearance(projected) and projected.parts.helmet == named_parts.helmet and not projected.has("equipment_dyes"))
	var extra := _projection_fixture()
	var unread := ProjectionMutation.new()
	extra.original.extra = {"object": unread, "aliases": [unread]}
	projected = Runtime.equipment_appearance(extra.data, extra.holder, extra.original)
	assert(not projected.is_empty() and unread.calls == 0 and is_same(projected.extra.object, unread))
	for mutate_dye: bool in [false, true]:
		var fixture := _projection_fixture()
		var mutation := ProjectionMutation.new()
		mutation.original = fixture.original
		mutation.dye = mutate_dye
		if mutate_dye: fixture.data.site.item_records["1"].dye_color = mutation
		else: fixture.data.site.item_definitions.helmet.asset = mutation
		assert(Runtime.equipment_appearance(fixture.data, fixture.holder, fixture.original).is_empty())
		assert(mutation.calls == 1)
		assert(fixture.original.equipment_dyes.helmet == "invalidf" if mutate_dye else fixture.original.parts.helmet == "not_a_catalog_asset")
	print("EQUIPMENT PROJECTION GUARD PASS: immutable catalogs, typed/readonly fields, StringName, float body, empty dyes, clone isolation and callback mutation")
