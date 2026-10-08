extends "res://scripts/tests/site_building_ui_test.gd"
## Duty AI reads the decider's real personality (military axes; missing = 50)
## and runs the three nation duties through the original entries
## (OFFICE plan A.2, NPC plan 7.8/8.4). One axis changes per case.

const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const PP = preload("res://scripts/terrain_lab/person_personality.gd")

func _mind(axis: String, value: int) -> Dictionary:
	var packet := PP.neutral()
	packet[axis] = value
	return packet

func _stock(data: TerrainData, slot: String, asset: String, count: int) -> void:
	for _i: int in range(count):
		var made := SiteRuntime.create_equipment(data, data.site.depot_items, slot + ":" + asset, {"slot": slot, "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, 1, "")
		assert(made.ok, str(made))

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var base := TerrainGenerator.generate(data.preset, data.seed_value, data.parameters)
	data.flags = base.flags.duplicate()
	data.ramp_edges = base.ramp_edges.duplicate()
	for y: int in range(8, 55):
		for x: int in range(8, 55):
			data.site.terrain_changes[str(data.index(Vector2i(x, y)))] = int(data.height_levels[data.index(Vector2i(x, y))])
	Runtime.rebuild_terrain_edges(data)
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
	data.site.army_next_team = team.team_id + 1
	var controlled: int = lab.controlled_person_id()
	var captain := team.combat_identity(team.current_commander)
	assert(_formal_feature(data, "training_ground", Vector2i(20, 20), Vector2i(10, 10)) != "")
	var entry: Dictionary = controller._enable_team_supply(team)
	entry.inventory.grain = 30

	# Missing packet reads neutral; a set packet is read from the Army row.
	assert(DutyAI.personality(captain, team) == PP.neutral())
	team.combat_units[team.current_commander].personality = _mind("achievement", 100)
	assert(int(DutyAI.personality(captain, team).achievement) == 100)

	# Training goal (好功): neutral goal 500 does not start at T=600; achievement 100 → goal 750 starts.
	team.combat_units[team.current_commander].erase("personality")
	team.training = 600.0
	team.team_fatigue.fatigue = 0.0
	assert(DutyAI.review_training(controller, team, controlled).is_empty(), "Neutral head keeps T=600 (goal 500)")
	team.combat_units[team.current_commander].personality = _mind("achievement", 100)
	var started := DutyAI.review_training(controller, team, controlled)
	assert(bool(started.get("ok", false)), "好功 head trains toward goal 750: " + str(started))
	assert(int(team.duty_traces[-1].knobs.goal) == 750 and int(team.duty_traces[-1].personality.achievement) == 100)
	assert(controller.order_team_training(team, team.current_commander, false).ok)

	# Logistics target (愛兵): neutral needs nobody; casualty 100 → 4 days → two carriers.
	team.combat_units[team.current_commander].erase("personality")
	assert(DutyAI.review_logistics(controller, team, controlled).is_empty(), "Neutral target 3 days is met")
	team.combat_units[team.current_commander].personality = _mind("casualty", 100)
	var carried := DutyAI.review_logistics(controller, team, controlled)
	assert(bool(carried.get("ok", false)) and is_equal_approx(float(team.duty_traces[-1].knobs.target_days), 4.0), str(carried))

	# Staffing taste: neutral head ranks by the duty ability (教練 coach); 愛兵 head weighs 統御 leadership.
	team.command_abilities[2] = {"tactics": 0, "leadership": 0, "coach": 60}
	team.command_abilities[3] = {"tactics": 0, "leadership": 100, "coach": 50}
	var pair: Array[int] = [team.combat_identity(2), team.combat_identity(3)]
	assert(DutyAI._best(team, pair, ["team.training"], PP.neutral()) == pair[0])
	assert(DutyAI._best(team, pair, ["team.training"], _mind("casualty", 100)) == pair[1])

	# Nation fixture: Japanese depot stock; untagged spears; a tool that must be ignored.
	_stock(data, "boots", "boots_japanese_leather_01", 3)
	_stock(data, "outfit", "outfit_underlayer_01", 3)
	_stock(data, "weapon", "spear_01", 3)
	_stock(data, "weapon", "wood_axe_01", 5)
	_stock(data, "helmet", "helmet_japanese_leather_01", 3)
	_stock(data, "shield", "shield_japanese_wood_01", 3)
	_stock(data, "armor", "armor_japanese_leather_01", 1)
	var keeper := team.combat_identity(1)
	var third := team.combat_identity(2)
	data.site.equipment_nations = {"n1": {"military_head": keeper, "members": [captain, keeper, third], "standards": {}}}
	var nation: Dictionary = data.site.equipment_nations.n1
	DutyAI.review(lab)
	assert(not nation.has("culture") and nation.standards.is_empty(), "Legacy military_head nations are never driven by duty AI")
	var orders: SiteEquipmentOrders = controller.equipment_orders
	assert(orders.appoint_nation_head("n1", captain).ok)
	nation = data.site.equipment_nations.n1
	assert(orders.set_nation_duty_ai(captain, "n1", true).ok)

	# Culture: rule based, the only culture with tagged stock.
	var culture := DutyAI.review_nation_culture(lab, "n1", nation, controlled)
	assert(bool(culture.get("ok", false)) and str(nation.culture) == "japanese", str(culture))
	assert(int(DutyAI.last_nation_trace.decider_person_id) == keeper and not bool(DutyAI.last_nation_trace.acting))

	# Standard: player exerciser is skipped; neutral keeper picks the light template; 謹慎 keeper the balanced one.
	assert(DutyAI.review_nation_standard(lab, "n1", nation, keeper).is_empty(), "Player-controlled exerciser only gets hints")
	var light := DutyAI.review_nation_standard(lab, "n1", nation, controlled)
	assert(bool(light.get("ok", false)), str(light))
	var standard: Dictionary = nation.standards[DutyAI.AI_STANDARD_ID]
	assert(standard.slots.keys().size() == 3 and str(standard.slots.weapon.definition) == "weapon:spear_01" and standard.slots.weapon.alternatives.is_empty(), str(standard.slots))
	assert(DutyAI.review_nation_standard(lab, "n1", nation, controlled).is_empty(), "Unchanged template is not rewritten")
	team.combat_units[1].personality = _mind("risk", 0)
	var heavier := DutyAI.review_nation_standard(lab, "n1", nation, controlled)
	assert(heavier.is_empty(), "Equal coverage is inside the hysteresis band: no churn")
	nation.standards.erase(DutyAI.AI_STANDARD_ID)
	var cautious := DutyAI.review_nation_standard(lab, "n1", nation, controlled)
	assert(bool(cautious.get("ok", false)) and nation.standards[DutyAI.AI_STANDARD_ID].slots.size() == 5, "謹慎 keeper prefers helmet+shield: " + str(nation.standards.get(DutyAI.AI_STANDARD_ID, {}).get("slots", {}).keys()))
	assert(float(DutyAI.last_nation_trace.knobs.heavy_bonus) > 0.0)
	assert(nation.standards[DutyAI.AI_STANDARD_ID].has("equipment_dyes"), "NPC author gets a preset palette")

	# Dye: one free member per round toward the AI palette.
	var holder: Dictionary = controller.person_actions._person(third).holder
	var worn_id := str(holder.equipped.get("outfit", ""))
	assert(not worn_id.is_empty(), "Fixture member wears an original outfit")
	var dyed := {}
	for _round: int in range(3):
		var step := DutyAI.review_nation_dye(lab, "n1", nation, controlled)
		if bool(step.get("ok", false)) and str(DutyAI.last_nation_trace.decision) == "dye %d" % third:
			dyed = step
			break
	assert(bool(dyed.get("ok", false)), "Dye AI reaches the member wearing an off-palette outfit")
	var palette: Dictionary = nation.standards[DutyAI.AI_STANDARD_ID].equipment_dyes
	assert(str(data.site.item_records[worn_id].get("dye_color", "")) == str(palette.outfit).to_lower())
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_DUTY_PERSONALITY_NATION_PASS: neutral fallback, achievement→training goal, casualty→logistics and staffing, legacy nation untouched, culture rule, player skip, light vs cautious template, hysteresis, NPC palette, dye")
	quit(0)
