extends "res://scripts/tests/site_garrison_test.gd"
## User decision 2026-10-08: a barracks inside a settlement's jurisdiction
## answers to the settlement's 營務官 (settlement.garrison); the head acts while
## the seat is vacant. Old settlement records gain the vacant seat; once an NPC
## holds it, the controlled head is refused and the holder decides.
## (Prepared in output/…/wip; moves to scripts/tests in the next D window.)

const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

func _center_cells(data: TerrainData, anchor: Vector2i) -> Array[int]:
	var placement := Runtime.building_cells(data, "settlement_center", anchor, Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	assert(placement.ok, str(placement))
	var cells: Array[int] = []
	cells.assign(placement.cells)
	return cells

func _run() -> void:
	deadline = Time.get_ticks_msec() + 240000
	var data := _building_fixture()
	var lab := _building_lab(data)
	var player: TerrainTestCharacter = lab.character
	var player_id := player.person_id
	data.site.inventory.wood = maxi(int(data.site.inventory.get("wood", 0)), 200)
	data.site.inventory.stone = maxi(int(data.site.inventory.get("stone", 0)), 200)
	assert(player.place(Vector2i(26, 22), true))
	var founded := Settlement.found(lab, player_id, _center_cells(data, Vector2i(20, 20)), {"layout_version": 1, "quarter": 0}, Callable(), "測試聚落")
	assert(founded.ok, str(founded))
	_complete_key(data, str(founded.feature))
	var key := _formal_feature(data, "barracks", Vector2i(26, 26), Vector2i(10, 10))
	data.site.features[key].owner_faction = player.faction_id
	assert(Settlement.garrison_governed(lab, key), "Same-faction barracks in jurisdiction is governed")
	var offices := Settlement.offices(lab)
	assert(offices.duties.has("settlement.garrison") and int(SiteOffices.position(offices, str(offices.duties["settlement.garrison"])).holder) == -1, "Vacant 營務官 seat")
	# Two same-faction teams standing in the barracks; one provides the 營務官.
	var source: TerrainArmy = lab.army
	var keeper_team: TerrainArmy = lab.opposing_army
	_make_garrison_team(lab, source, [Vector2i(29, 32), Vector2i(30, 32)])
	_make_garrison_team(lab, keeper_team, [Vector2i(30, 33), Vector2i(31, 33)])
	source.faction_id = player.faction_id
	keeper_team.faction_id = player.faction_id
	for team: TerrainArmy in [source, keeper_team]: assert(not lab.site_controller._enable_team_supply(team).is_empty())
	var keeper := keeper_team.combat_identity(1)
	# Vacant seat: the controlled head acts.
	assert(Settlement.garrison_authority(lab, key, player_id).is_empty(), "Head acts while 營務官 is vacant")
	# 文武官 W2: a 文官 seat needs a 文吏 (a 武官 seat an officer); the fixture qualifies its holder first.
	keeper_team.combat_units[1]["military_role"] = "officer"
	assert(Settlement.apply_office_plan(lab, player_id, int(offices.revision), [{"op": "appoint", "position_id": str(offices.duties["settlement.garrison"]), "person_id": keeper}]).ok)
	var refused := Garrison.admit(lab, key, source.team_id)
	assert(str(refused.code) == "NO_AUTHORITY" and str(refused.message).contains("營務官"), "The controlled head is refused once 營務官 is held: %s" % str(refused))
	assert(source.garrison_feature_id.is_empty(), "Refusal changes nothing")
	data.site.controlled_person_id = keeper
	var admitted := Garrison.admit(lab, key, source.team_id)
	assert(admitted.ok, "營務官 garrisons the team: %s" % str(admitted))
	data.site.erase("controlled_person_id")
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_GARRISON_GOVERNED_PASS: settlement 營務官 seat added vacant, head acts while vacant, holder decides and the head is refused, refusal changes nothing")
	quit(0)
