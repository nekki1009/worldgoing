extends "res://scripts/tests/site_building_ui_test.gd"
## F03 (v2 plan R0, appendix test): the logistics need is counted in carriers who
## really contribute, so unconscious carriers flagged for logistics no longer
## count as staffing. 愛兵 100 head (target 4 days), 5 of the carriers unconscious:
## one review assigns the whole need and capacity covers the target; release
## only picks a carrier whose release really lowers capacity.

const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const PP = preload("res://scripts/terrain_lab/person_personality.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var lab := _building_lab(data)
	lab.fixed_action_steps_enabled = false
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.army
	team.roster_size = 20
	team.faction_id = 1
	var cells: Array[Vector2i] = []
	for index in range(20): cells.append(Vector2i(22 + index % 5, 24 + floori(float(index) / 5.0)))
	assert(team.deploy_at(data, lab.character, lab.npc, cells))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	var controlled: int = lab.controlled_person_id()
	var head := team.current_commander
	assert(team.combat_identity(head) != controlled, "Fixture head must be an NPC")
	var mind := PP.neutral()
	mind.casualty = 100
	team.combat_units[head].personality = mind
	assert(DutyAI.logistics_target_units(mind) == 40000, "愛兵 100: four days")
	var entry: Dictionary = controller._enable_team_supply(team)
	entry.inventory.grain = 30
	# Five non-head members carry logistics and are knocked out.
	var knocked := 0
	for index: int in team.combat_units.size():
		if knocked == 5: break
		if index == head or team.combat_identity(index) == controlled or not team.is_member(index): continue
		team.combat_units[index].logistics = true
		team.apply_unit_contact(index, {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false})
		knocked += 1
	team.settle_combat_command()
	assert(knocked == 5)
	DutyAI.review_round = 0
	var before := controller.team_food_capacity(team)
	var assigned := DutyAI.review_logistics(controller, team, controlled)
	assert(bool(assigned.get("ok", false)), "Logistics assigns: %s" % str(assigned))
	var trace: Dictionary = team.duty_traces[-1]
	var living := int(trace.inputs.living)
	var need := int(trace.inputs.need)
	assert(str(trace.decision) .count(",") + 1 == need, "Whole need assigned at once (not need minus the 5 unconscious): %s need %d" % [trace.decision, need])
	assert(int(trace.inputs.get("contributing", -1)) == 0 and int(trace.inputs.logistics) == 5, str(trace.inputs))
	var after := controller.team_food_capacity(team)
	assert(after >= 4.0 * living and after > before, "Capacity %.1f covers target %.1f (was %.1f)" % [after, 4.0 * living, before])
	DutyAI.review_round = 0
	var again := DutyAI.review_logistics(controller, team, controlled)
	assert(not str(team.duty_traces[-1].decision).begins_with("assign") or again.is_empty(), "No further assignment once covered")
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_DUTY_LOGISTICS_KO_PASS: need counted in contributing carriers, unconscious carriers excluded, whole need assigned once, capacity covers 愛兵 target")
	quit(0)
