extends SceneTree

const Dye = preload("res://scripts/ui/equipment_dye.gd")
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const OrderTest = preload("res://scripts/tests/site_equipment_orders_test.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const CUSTOM := {"helmet": "123456ff", "armor": "76a92dff", "boots": "8453b1ff", "cape": "a83467ff", "outfit": "f4ca78ff"}
const OUT := "res://output/equipment_palette_policy_20260914"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _contract():
		quit(1)
		return
	if "--visual" in OS.get_cmdline_user_args() and not await _visual():
		quit(1)
		return
	print("EQUIPMENT PALETTE POLICY PASS: NPC 16 presets, stable initial choices, controlled leader free five-slot colours, succession preservation, authority, atomic refusal", "; real UI/save/load/capture" if "--visual" in OS.get_cmdline_user_args() else "; data only")
	quit()

func _contract() -> bool:
	var harness := OrderTest.new()
	var fixture := harness._fixture()
	var lab: Variant = fixture.lab
	var orders: Variant = fixture.orders
	orders.equipment_dye_guard = func(_identity: int, _changes: Dictionary) -> Dictionary: return Runtime.ok()
	harness._nation(fixture)
	var nation: Dictionary = lab.terrain.site.equipment_nations.n1
	var slots := {"weapon": {"definition": "weapon:spear_01"}}
	var appearance := HumanCharacter3DEditor.default_appearance()
	for slot: String in Dye.SLOTS:
		harness._item(lab, lab.character.item_state, slot, appearance.parts[slot], 1, true)
	var initial: Dictionary = nation.standards.line.equipment_dyes.duplicate()
	assert(Orders._is_preset(initial))
	assert(orders.set_standard(2, "n1", "line", "保留原選色", slots).ok)
	assert(nation.standards.line.equipment_dyes == initial)
	var seen := {}
	for index in range(16):
		var key := Orders.npc_palette_id(index)
		seen[key] = true
		var colors: Dictionary = Dye.PRESETS[key].colors
		var records: Dictionary = lab.terrain.site.item_records.duplicate(true)
		assert(orders.set_standard(2, "n1", "line", key, slots, key).ok)
		assert(nation.standards.line.equipment_dyes == colors and lab.terrain.site.item_records == records)
		assert(orders.apply_standard_dyes(2, 1, "n1", "line").ok)
		assert(Runtime.equipment_appearance(lab.terrain, lab.character.item_state, appearance).equipment_dyes == colors)
		var uniform := SiteController._initial_uniform(appearance, index)
		assert(uniform.equipment_dyes == colors and not appearance.has("equipment_dyes"))
		assert(SiteController._initial_uniform(uniform, index + 1) == uniform)
	assert(seen.size() == 16 and Orders.npc_palette_id(-1) == Orders.npc_palette_id(15))
	assert(Orders.npc_palette_id(2147483647) in Dye.PRESETS)
	var before := JSON.stringify([nation, lab.terrain.site.item_records, lab.character.item_state])
	assert(orders.set_standard(2, "n1", "line", "不准 NPC 自由配", slots, CUSTOM).code == "INVALID")
	assert(orders.set_standard(2, "n1", "line", "無效預設", slots, "missing").code == "INVALID")
	assert(orders.dye_person(2, 1, CUSTOM).code == "INVALID")
	assert(orders.dye_person(2, 1, {"armor": Dye.PRESETS.red.colors.armor}).code == "INVALID")
	assert(orders.set_standard(1, "n1", "line", "非首長", slots, CUSTOM).code == "NO_AUTHORITY")
	assert(JSON.stringify([nation, lab.terrain.site.item_records, lab.character.item_state]) == before)
	# The actual controlled identity matters, not which original actor node owns it.
	lab.controlled_id = 2
	assert(orders.set_standard(2, "n1", "line", "玩家自由配", slots, CUSTOM).ok)
	assert(orders.dye_person(2, 1, CUSTOM).ok)
	assert(orders.set_standard(2, "n1", "sparse", "玩家只配一槽", slots, {"cape": "012345ff"}).ok)
	assert(orders.set_standard(2, "n1", "clear", "玩家不指定染色", slots, {}).ok)
	assert(not nation.standards.clear.has("equipment_dyes"))
	var authored := appearance.duplicate(true)
	authored.equipment_dyes = CUSTOM.duplicate()
	assert(SiteController._initial_uniform(authored, 0) == authored)
	authored.equipment_dyes = {}
	assert(SiteController._initial_uniform(authored, 0) == authored)
	lab.controlled_id = 1
	assert(orders.set_standard(2, "n1", "line", "NPC 接任只改名稱", slots).ok)
	assert(nation.standards.line.equipment_dyes == CUSTOM)
	assert(orders.apply_standard_dyes(2, 1, "n1", "line").ok)
	assert(Orders.valid_nations(JSON.parse_string(JSON.stringify(lab.terrain.site.equipment_nations)), lab.terrain.site.item_definitions, {1: true, 2: true, 3: true}))
	lab.npc.captive = true
	assert(orders.set_standard(2, "n1", "line", "被俘不繞權限", slots, "red").code == "NO_AUTHORITY")
	orders.equipment_dye_guard = Callable()
	harness._close(fixture)
	harness.free()
	return true

func _visual() -> bool:
	assert(DisplayServer.get_name() != "headless")
	root.size = Vector2i(1400, 1000)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(0, 581)
	Env.initialize(data, "equipment-palette-policy")
	data.site.worker_enabled = false
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	var controller: SiteController = lab.site_controller
	var player_id := lab.character.person_id
	var npc_id := lab.npc.person_id
	# Explicit political fixture only; production UI must never manufacture an office.
	data.site.equipment_nations = {"policy": {"military_head": player_id, "members": [player_id, npc_id], "standards": {}}}
	controller._open_equipment_standards()
	var dialog := lab.get_node("SiteUI/EquipmentStandardsDialog") as AcceptDialog
	var choice := dialog.find_child("StandardPalette", true, false) as OptionButton
	assert(choice.item_count == 16)
	for index in range(16):
		choice.select(index)
		(dialog.find_child("LoadStandardPalette", true, false) as Button).pressed.emit()
		for slot: String in Dye.SLOTS:
			assert((dialog.find_child("StandardDye_" + slot, true, false) as ColorPickerButton).color.to_html() == Dye.PRESETS[str(choice.get_item_metadata(index))].colors[slot])
	for slot: String in Dye.SLOTS:
		var picker := dialog.find_child("StandardDye_" + slot, true, false) as ColorPickerButton
		assert(not picker.disabled and not picker.edit_alpha)
		picker.color = Color.from_string(CUSTOM[slot], Color.WHITE)
	(dialog.find_child("StandardName", true, false) as LineEdit).text = "玩家領導者 · 五部位自由配色"
	var armor_choice := dialog.find_child("StandardSlot_armor", true, false) as OptionButton
	assert(armor_choice.item_count > 1)
	armor_choice.select(1)
	var original_items: Dictionary = data.site.item_records.duplicate(true)
	(dialog.find_child("CommitStandard", true, false) as Button).pressed.emit()
	assert(data.site.equipment_nations.policy.standards.unit_1.equipment_dyes == CUSTOM, controller.message.text)
	assert(data.site.item_records == original_items)
	for tick in range(5):
		await process_frame
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/player_free_palette.png") == OK)
	# A stale window cannot submit as a newly controlled leader or into a replaced nation.
	data.site.controlled_person_id = npc_id
	data.site.equipment_nations.policy.military_head = npc_id
	var before: Dictionary = data.site.equipment_nations.duplicate(true)
	(dialog.find_child("CommitStandard", true, false) as Button).pressed.emit()
	assert(controller.message.text == Runtime.fail("STALE_SOURCE", "原人物／地圖／國別已變更，請重開標準面板").message, controller.message.text)
	assert(data.site.equipment_nations == before)
	dialog.free()
	# Relinquish control: the NPC may apply the saved player-authored colours without rewriting them.
	data.site.controlled_person_id = player_id
	var applied := controller.equipment_orders.apply_standard_dyes(npc_id, player_id, "policy", "unit_1")
	assert(applied.ok, str(applied))
	assert(controller.person_appearance(player_id).equipment_dyes == CUSTOM)
	controller._capture_positions()
	assert(Store.save(data, OUT + "/saved.json").ok)
	var loaded := Store.load_site(OUT + "/saved.json")
	assert(loaded.ok, str(loaded))
	assert(loaded.data.site.equipment_nations == data.site.equipment_nations)
	assert(loaded.data.site.item_records == data.site.item_records)
	lab.bind_terrain(loaded.data)
	assert(controller.person_appearance(player_id).equipment_dyes == CUSTOM)
	# Exercise the actual new-row initializer beyond the old blue/red pair.
	for team_index in range(2):
		var team: TerrainArmy = lab.combat_armies[team_index]
		team.faction_id = [2, 15][team_index]
		team.team_id = team_index + 1
		team.roster_size = 2
		var cells: Array[Vector2i] = []
		for index in range(lab.terrain.size.x * lab.terrain.size.y):
			var cell := lab.terrain.cell_from_index(index)
			if lab.terrain.is_walkable(cell) and not lab.character.occupies_cell(cell) and not lab.npc.occupies_cell(cell) and not team.external_blocker.call(cell):
				cells.append(cell)
				if cells.size() == 2: break
		assert(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false))
		var colors: Dictionary = Dye.PRESETS[Orders.npc_palette_id(team.faction_id)].colors
		for index in range(2):
			var look := team.equipment_appearance(index)
			assert(not look.get("equipment_dyes", {}).is_empty(), "New row %d/%d: %s; unit=%s; message=%s" % [team_index, index, look, team.combat_units[index], controller.message.text])
			for slot: String in look.equipment_dyes: assert(look.equipment_dyes[slot] == colors[slot])
			if not team._uses_live_presenter(index):
				assert(team.supports_equipment_recipe(look))
				team._set_soldier_frame(index, true)
				assert(team._sprites[index].texture != null and team._sprites[index].material != null)
		var records: Dictionary = lab.terrain.site.item_records.duplicate(true)
		team.faction_id += 1
		controller.initialize_team_items(team)
		assert(lab.terrain.site.item_records == records, "Faction change or rebind must not repaint existing items")
		team.faction_id -= 1
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	return true
