extends "res://scripts/tests/site_building_ui_test.gd"
## F05 (v2 plan R0): the culture AI first keeps only cultures every existing
## standard (and its alternatives) fits, then compares stock. A Japanese
## standard with more Chinese stock still gets Japanese; with no legal culture
## the AI waits visibly and never edits the player's standards.

const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")

func _stock(data: TerrainData, slot: String, asset: String, count: int) -> void:
	for _i: int in range(count):
		var made := SiteRuntime.create_equipment(data, data.site.depot_items, slot + ":" + asset, {"slot": slot, "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, 1, "")
		assert(made.ok, str(made))

func _standard(definition: String) -> Dictionary:
	return {"display_name": definition, "slots": {"boots": {"definition": definition, "alternatives": []}}}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var lab := _building_lab(data)
	lab.fixed_action_steps_enabled = false
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	assert(team.deploy_at(data, lab.character, lab.npc, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26), Vector2i(26, 26)]))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	var controlled: int = lab.controlled_person_id()
	var captain := team.combat_identity(team.current_commander)
	var keeper := team.combat_identity(1)
	# More Chinese than Japanese boots; outfit and weapon untagged (shared).
	_stock(data, "boots", "boots_japanese_leather_01", 3)
	_stock(data, "boots", "boots_chinese_leather_01", 5)
	_stock(data, "outfit", "outfit_underlayer_01", 5)
	_stock(data, "weapon", "spear_01", 5)
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var jp := "boots:boots_japanese_leather_01"
	var cn := "boots:boots_chinese_leather_01"
	data.site.equipment_nations = {
		"n1": {"military_head": keeper, "members": [captain, keeper], "standards": {"player_jp": _standard(jp)}},
		"n2": {"military_head": keeper, "members": [captain, keeper], "standards": {"player_jp": _standard(jp), "player_cn": _standard(cn)}}}
	for nation_id: String in ["n1", "n2"]:
		assert(orders.appoint_nation_head(nation_id, captain).ok)
		assert(orders.set_nation_duty_ai(captain, nation_id, true).ok)
	var n1: Dictionary = data.site.equipment_nations.n1
	var n2: Dictionary = data.site.equipment_nations.n2
	DutyAI.review_round = 0
	var picked := DutyAI.review_nation_culture(lab, "n1", n1, controlled)
	assert(bool(picked.get("ok", false)) and str(n1.get("culture", "")) == "japanese", "Legal Japanese despite more Chinese stock: %s" % str(picked))
	var n2_before: Dictionary = n2.standards.duplicate(true)
	DutyAI.review_round = 0
	var waited := DutyAI.review_nation_culture(lab, "n2", n2, controlled)
	assert(waited.is_empty() and not n2.has("culture") and n2.standards == n2_before, "No legal culture: no change")
	assert(str(DutyAI.nation_traces["n2"][-1].decision).begins_with("wait") and str(DutyAI.nation_traces["n2"][-1].issued.code) == "CULTURE_MISMATCH", str(DutyAI.nation_traces["n2"][-1]))
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_DUTY_CULTURE_LEGAL_PASS: culture AI filters by existing standards before stock (Japanese kept over more Chinese stock), no legal culture waits visibly and keeps the player's standards")
	quit(0)
