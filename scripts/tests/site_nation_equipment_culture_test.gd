extends SceneTree
## Existing nation owner, actual standards UI/Orders/holders and SiteStore; no atlas deployment.
const CapeTest = preload("res://scripts/tests/site_cape_role_policy_test.gd")
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUT := "res://output/equipment_limits_20260919/cape_role/culture"
const MIXED := {"helmet": "helmet_cloth_japanese_01", "armor": "armor_japanese_steel_01", "boots": "boots_japanese_leather_01", "shield": "shield_japanese_iron_01"}
const CUSTOM := {"helmet": "123456ff", "armor": "234567ff", "boots": "345678ff", "cape": "456789ff", "outfit": "56789aff"}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(1))
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	_rules_and_issue()
	_metadata_and_legacy()
	await _ui()
	_save_roundtrip()
	await process_frame
	print("SITE NATION EQUIPMENT CULTURE PASS: same nation optional fixed culture, original head/one-time UI, Editor metadata, mixed materials/strict alternatives, prepare+commit, foreign ownership/personal loot retained, 16 NPC/custom head palettes, actual SiteStore legacy and fixed roundtrip; no atlas/GPU proof")
	quit(0)

func _fixture() -> CapeTest.Fixture:
	var f := CapeTest.Fixture.new()
	f.terrain.site.equipment_nations = {"n1": {"military_head": 1, "members": [1, 2, 3, 4], "standards": {}}}
	for slot: String in MIXED: f.item(0, slot, MIXED[slot])
	f.item(0, "armor", "armor_japanese_iron_01")
	f.item(0, "armor", "armor_light_leather_01")
	f.item(0, "helmet", "helmet_leather_01")
	f.item(0, "boots", "boots_leather_01")
	f.item(0, "shield", "shield_western_steel_01")
	return f

func _requirements() -> Dictionary:
	var slots := {}
	for slot: String in MIXED: slots[slot] = {"definition": slot + ":" + str(MIXED[slot]), "alternatives": []}
	slots.armor.alternatives = ["armor:armor_japanese_iron_01"]
	return slots

func _rules_and_issue() -> void:
	var f := _fixture()
	var orders := f.controller.equipment_orders
	var before := f.stock()
	var nation: Dictionary = f.terrain.site.equipment_nations.n1
	assert(orders.set_nation_culture(1, "absent", "japanese").code == "NO_AUTHORITY")
	assert(f.terrain.site.equipment_nations.size() == 1)
	assert(orders.set_nation_culture(3, "n1", "japanese").code == "NO_AUTHORITY", "A real commander is not the national head")
	f.character.knockout_left = 10.0
	assert(orders.set_nation_culture(1, "n1", "japanese").code == "NO_AUTHORITY")
	f.character.knockout_left = 0.0
	nation.members.erase(1)
	assert(orders.set_nation_culture(1, "n1", "japanese").code == "NO_AUTHORITY")
	nation.members.append(1)
	assert(orders.set_nation_culture(1, "n1", "invented").code == "INVALID")
	assert(not nation.has("culture") and f.stock() == before)
	assert(orders.set_standard(1, "n1", "mixed", "日式・布盔鋼甲皮靴鐵盾", _requirements(), CUSTOM).ok)
	assert(orders.begin_issue(2, "n1", "mixed").code == "CULTURE_REQUIRED")
	assert(not nation.has("culture") and not f.controller.person_actions.is_busy(2) and f.stock() == before)
	assert(orders.set_nation_culture(1, "n1", "western").code == "CULTURE_MISMATCH")
	assert(orders.set_nation_culture(1, "n1", "japanese").ok)
	assert(is_same(f.terrain.site.equipment_nations.n1, nation) and nation.culture == "japanese")
	assert(orders.set_nation_culture(1, "n1", "western").code == "CULTURE_FIXED")
	assert(orders.set_nation_culture(1, "n1", "japanese").code == "NO_CHANGE")
	var original: Dictionary = nation.standards.duplicate(true)
	var cross := _requirements()
	cross.armor.alternatives.append("armor:armor_light_leather_01")
	assert(orders.set_standard(1, "n1", "mixed", "跨文化替代", cross).code == "CULTURE_MISMATCH")
	cross = _requirements()
	cross.armor.definition = "armor:armor_light_leather_01"
	assert(orders.set_standard(1, "n1", "mixed", "跨文化主要", cross).code == "CULTURE_MISMATCH")
	assert(nation.standards == original and f.stock() == before)
	var prepared := orders.prepare(2, {"mode": "issue", "nation_id": "n1", "standard_id": "mixed"})
	assert(prepared.ok, str(prepared))
	nation.culture = "western" # Simulated stale authority state; commit must not trust prepared approval.
	assert(orders.commit(prepared.order).code == "CULTURE_MISMATCH" and f.stock() == before)
	nation.culture = "japanese"
	var selected_armor := str(prepared.order.planned.armor)
	f.terrain.site.item_records[selected_armor].definition = "armor:armor_light_leather_01"
	var altered := f.stock()
	assert(orders.commit(prepared.order).code == "CULTURE_MISMATCH" and f.stock() == altered, "Recheck the actual item, not only the standard metadata")
	f.terrain.site.item_records[selected_armor].definition = "armor:armor_japanese_steel_01"
	assert(orders.begin_issue(2, "n1", "mixed").ok)
	f.controller.person_actions.advance(5.0)
	assert(f.controller.person_actions.settle_after_contacts()[0].ok)
	for slot: String in MIXED:
		assert(f.controller.person_appearance(2).parts[slot] == MIXED[slot])
	assert(not f.controller.person_can_wear_cape(2), "Ordinary original NPC, not a fabricated office")
	# Foreign possession and a player's own loot are not national-standard issuance.
	var foreign := f.item(1, "armor", "armor_light_leather_01")
	assert(orders.begin_personal(1, "armor", foreign).ok)
	f.controller.person_actions.advance(5.0)
	assert(f.controller.person_actions.settle_after_contacts()[0].ok and f.character.item_state.equipped.armor == foreign)
	assert(f.terrain.site.item_records[foreign].holder == "person:1" and nation.culture == "japanese")
	# Original palette policy is still the sole dye owner.
	nation.military_head = 2
	for index: int in 16:
		var palette := Orders.npc_palette_id(index)
		assert(orders.set_standard(2, "n1", "mixed", palette, _requirements(), palette).ok)
		assert(nation.standards.mixed.equipment_dyes == SiteRuntime.EquipmentDye.PRESETS[palette].colors)
	assert(orders.set_standard(2, "n1", "mixed", "NPC custom rejected", _requirements(), CUSTOM).code == "INVALID")
	f.source.controlled_id = 2
	assert(orders.set_standard(2, "n1", "mixed", "Actual controlled head", _requirements(), CUSTOM).ok)
	assert(nation.standards.mixed.equipment_dyes == CUSTOM)
	f.close()

func _metadata_and_legacy() -> void:
	var f := _fixture()
	var definitions: Dictionary = f.terrain.site.item_definitions
	assert(Orders.definition_culture(definitions["armor:armor_light_leather_01"]) == "western")
	assert(Orders.definition_culture({"slot": "weapon", "asset": "longsword_01"}).is_empty())
	assert(Orders.definition_culture({"slot": "outfit", "asset": "outfit_chinese_lining_01"}).is_empty(), "No culture guessed from a name without Editor metadata")
	var nation: Dictionary = f.terrain.site.equipment_nations.n1
	var orders := f.controller.equipment_orders
	var cross := _requirements()
	cross.armor.alternatives.append("armor:armor_light_leather_01")
	assert(orders.set_standard(1, "n1", "legacy", "原跨文化舊標準", cross).ok)
	assert(Orders.valid_nations(f.terrain.site.equipment_nations, definitions, {1: true, 2: true, 3: true, 4: true}))
	assert(not nation.has("culture"), "Reading/authoring legacy data never guesses a country style")
	assert(orders.set_nation_culture(1, "n1", "japanese").code == "CULTURE_MISMATCH")
	assert(orders.set_standard(1, "n1", "legacy", "首長明確修訂舊標準", _requirements()).ok)
	assert(orders.set_nation_culture(1, "n1", "japanese").ok)
	assert(Orders.valid_nations(JSON.parse_string(JSON.stringify(f.terrain.site.equipment_nations)), definitions, {1: true, 2: true, 3: true, 4: true}))
	nation.standards.legacy.slots.armor.alternatives.append("armor:armor_light_leather_01")
	assert(not Orders.valid_nations(f.terrain.site.equipment_nations, definitions, {1: true, 2: true, 3: true, 4: true}))
	nation.standards.legacy.slots = _requirements()
	for value: Variant in ["", "invented", 1, null]:
		nation.culture = value
		assert(not Orders.valid_nations(f.terrain.site.equipment_nations, definitions, {1: true, 2: true, 3: true, 4: true}))
	f.close()

func _select(choice: OptionButton, metadata: String) -> void:
	for index: int in choice.item_count:
		if str(choice.get_item_metadata(index)) == metadata:
			choice.select(index)
			return
	assert(false, "Missing UI choice: " + metadata)

func _ui() -> void:
	if DisplayServer.get_name() != "headless":
		root.gui_embed_subwindows = true # Capture the actual dialogs/popups in the root, at the configured window size.
	var f := _fixture()
	var layer := CanvasLayer.new()
	layer.name = "SiteUI"
	f.add_child(layer)
	root.add_child(f)
	var controller := f.controller
	controller._open_equipment_standards()
	var dialog := layer.get_node("EquipmentStandardsDialog") as AcceptDialog
	var culture := dialog.find_child("NationCulture", true, false) as OptionButton
	assert(culture.item_count == 4 and culture.selected == 0 and not f.terrain.site.equipment_nations.n1.has("culture"))
	if DisplayServer.get_name() != "headless":
		await process_frame
		culture.show_popup()
		await _capture_ui("00_initial_culture_choices", culture.get_popup())
		culture.get_popup().hide()
	var before := f.stock()
	_select(culture, "japanese")
	(dialog.find_child("CommitNationCulture", true, false) as Button).pressed.emit()
	assert(controller.last_result.ok and culture.disabled and f.stock() == before)
	assert(f.terrain.site.equipment_nations.n1.culture == "japanese")
	for slot: String in MIXED:
		var choice := dialog.find_child("StandardSlot_" + slot, true, false) as OptionButton
		for index: int in range(1, choice.item_count):
			var definition: Dictionary = f.terrain.site.item_definitions[str(choice.get_item_metadata(index))]
			assert(Orders.definition_culture(definition) == "japanese")
		_select(choice, slot + ":" + str(MIXED[slot]))
	await _capture_ui("01_fixed_culture_mixed_materials", dialog)
	if DisplayServer.get_name() != "headless":
		var armor_choice := dialog.find_child("StandardSlot_armor", true, false) as OptionButton
		armor_choice.show_popup()
		await _capture_ui("02_armor_material_choices", armor_choice.get_popup())
		armor_choice.get_popup().hide()
	(dialog.find_child("StandardAlternatives_armor", true, false) as Button).pressed.emit()
	var alternatives := dialog.get_node("StandardAlternativesDialog") as AcceptDialog
	var list := alternatives.find_child("StandardAlternativeItems", true, false) as ItemList
	assert(list.item_count == 1 and str(list.get_item_metadata(0)) == "armor:armor_japanese_iron_01")
	list.select(0)
	await _capture_ui("03_armor_material_alternatives", alternatives)
	alternatives.confirmed.emit()
	(dialog.find_child("StandardName", true, false) as LineEdit).text = "原UI日式混材"
	assert((dialog.find_child("StandardPalette", true, false) as OptionButton).item_count == 16)
	for slot: String in CUSTOM:
		(dialog.find_child("StandardDyeEnabled_" + slot, true, false) as CheckBox).button_pressed = true
		(dialog.find_child("StandardDye_" + slot, true, false) as ColorPickerButton).color = Color.from_string(CUSTOM[slot], Color.WHITE)
	(dialog.find_child("CommitStandard", true, false) as Button).pressed.emit()
	assert(controller.last_result.ok, str(controller.last_result))
	var nation: Dictionary = f.terrain.site.equipment_nations.n1
	assert(nation.standards.unit_1.slots == _requirements() and nation.standards.unit_1.equipment_dyes == CUSTOM)
	assert(f.stock() == before)
	dialog.queue_free()
	await process_frame
	controller._open_equipment_standards()
	dialog = layer.get_node("EquipmentStandardsDialog") as AcceptDialog
	assert((dialog.find_child("NationCulture", true, false) as OptionButton).disabled)
	assert((dialog.find_child("CommitNationCulture", true, false) as Button).disabled)
	# Equal-valued replacement of the original nation invalidates the original window.
	f.terrain.site.equipment_nations.n1 = nation.duplicate(true)
	(dialog.find_child("CommitNationCulture", true, false) as Button).pressed.emit()
	assert(controller.last_result.code == "STALE_SOURCE")
	(dialog.find_child("CommitStandard", true, false) as Button).pressed.emit()
	assert(controller.last_result.code == "STALE_SOURCE")
	f.close()
	await process_frame

func _capture_ui(label: String, window: Window) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(is_instance_valid(window) and window.visible, "Capture requires the actual open UI: " + label)
	var picture := root.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(OUT + "/" + label + ".png") == OK)
	print("NATION CULTURE UI CAPTURE (inspection pending): ", OUT + "/" + label + ".png")

func _save_roundtrip() -> void:
	var f := _fixture()
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "nation-culture-fixture")
	assert(SiteRuntime.initialize_item_storage(data.site).ok)
	for actor: TerrainTestCharacter in [f.character, f.npc]:
		actor.data = data
		actor.terrain_cell = data.spawn_cell
		actor.movement_from_cell = data.spawn_cell
		actor.position = (Vector2(data.spawn_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		actor._movement_start = actor.position
		actor.item_state = SiteRuntime.new_item_state("person:%d" % actor.person_id)
	data.site.player_cell = data.index(data.spawn_cell)
	data.site.worker.cell = data.index(data.spawn_cell)
	var foreign := SiteRuntime.create_equipment(data, f.npc.item_state, "armor:armor_light_leather_01",
		{"slot": "armor", "asset": "armor_light_leather_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 2, "armor")
	assert(foreign.ok)
	assert(SiteRuntime.create_equipment(data, data.site.depot_items, "armor:armor_japanese_steel_01",
		{"slot": "armor", "asset": "armor_japanese_steel_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 1).ok)
	f.npc._saved_appearance.parts.armor = "armor_light_leather_01"
	data.site.actors = {"player": f.character.capture_state(), "npc": f.npc.capture_state()}
	data.site.equipment_nations = {"n1": {"military_head": 1, "members": [1, 2], "standards": {}}}
	var path := OUT + "/legacy.json"
	assert(Store.save(data, path).ok)
	var loaded := Store.load_site(path)
	assert(loaded.ok and not loaded.data.site.equipment_nations.n1.has("culture"), str(loaded))
	assert(loaded.data.site.item_records == data.site.item_records)
	data.site.equipment_nations.n1.culture = "japanese"
	path = OUT + "/fixed.json"
	assert(Store.save(data, path).ok, "An ordinary NPC's already owned foreign wear is not confiscated or a save blocker")
	loaded = Store.load_site(path)
	assert(loaded.ok and loaded.data.site.equipment_nations.n1.culture == "japanese", str(loaded))
	assert(loaded.data.site.actors.npc.item_state == f.npc.item_state and loaded.data.site.item_records == data.site.item_records)
	var digest := FileAccess.get_sha256(path)
	data.site.equipment_nations.n1.standards = {"bad": {"name": "cross", "revision": 1,
		"slots": {"armor": {"definition": "armor:armor_japanese_steel_01", "alternatives": ["armor:armor_light_leather_01"]}}}}
	assert(Store.save(data, path).code == "CORRUPT_SAVE" and FileAccess.get_sha256(path) == digest)
	var payload: Dictionary = Store._read(path).payload
	payload.state.equipment_nations.n1.standards = data.site.equipment_nations.n1.standards.duplicate(true)
	var body := JSON.stringify(payload, "", true, true)
	var rejected := OUT + "/rejected_fixed_standard.json"
	var file := FileAccess.open(rejected, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()
	var incoming_digest := FileAccess.get_sha256(rejected)
	assert(Store.load_site(rejected).code == "CORRUPT_SAVE" and FileAccess.get_sha256(rejected) == incoming_digest)
	data.site.equipment_nations.n1.erase("culture")
	path = OUT + "/legacy_standard.json"
	assert(Store.save(data, path).ok and Store.load_site(path).ok, "Legacy mixed standard stays unguessed and readable")
	f.close()
