extends "res://scripts/tests/site_building_ui_test.gd"
## Duty AI through the real controller entries (OFFICE plan P1/P1-AI, NPC plan 8.4):
## an appointed 教頭 owns training authority (head refused), the training pilot
## starts/stops through order_team_training as that holder, the logistics pilot
## assigns through order_team_logistics, and one full scheduler round runs.

const Ground = preload("res://scripts/terrain_lab/site_training_ground.gd")
const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var base := TerrainGenerator.generate(data.preset, data.seed_value, data.parameters)
	data.flags = base.flags.duplicate()
	data.ramp_edges = base.ramp_edges.duplicate()
	for y: int in range(8, 55):
		for x: int in range(8, 55):
			var cell := Vector2i(x, y)
			data.site.terrain_changes[str(data.index(cell))] = int(data.height_levels[data.index(cell)])
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
	assert(captain != controlled, "Fixture head must be an NPC")
	var coach := team.combat_identity(2)
	assert(team.set_military_role(coach, "officer").ok)
	assert(team.record_officer_service([2], true).ok)
	var field := _formal_feature(data, "training_ground", Vector2i(20, 20), Vector2i(10, 10))
	assert(not field.is_empty())
	var entry: Dictionary = controller._enable_team_supply(team)
	entry.inventory.grain = 30

	# Appoint the coach; authority moves with the duty, the head is refused.
	var offices := team.team_offices()
	var seat := str(offices.duties["team.training"])
	var plan := team.apply_office_plan(captain, int(offices.revision), [{"op": "appoint", "position_id": seat, "person_id": coach}])
	assert(plan.ok, str(plan))
	var refused := controller.order_team_training(team, team.current_commander, true)
	assert(str(refused.code) == "NO_AUTHORITY" and str(refused.message).contains("教頭"), str(refused))

	# Training pilot: neutral goal 500, starts as the holder (not acting).
	team.training = 0.0
	team.team_fatigue.fatigue = 0.0
	var started := DutyAI.review_training(controller, team, controlled)
	assert(bool(started.get("ok", false)), "Pilot starts training: " + str(started) + " " + str(Ground.inspect(controller, team.team_id)))
	assert(entry.training_order and int(entry.training_requester) == coach)
	var trace: Dictionary = team.duty_traces[-1]
	assert(str(trace.duty_id) == "team.training" and int(trace.decider_person_id) == coach and not bool(trace.acting), str(trace))
	assert(DutyAI.review_training(controller, team, controlled).is_empty(), "Hysteresis: no second order")
	var before := team.training
	lab._process(0.1)
	assert(entry.training_order and team.training > before, "Holder-issued order keeps training on the common clock")
	team.team_fatigue.fatigue = 85.0
	var stopped := DutyAI.review_training(controller, team, controlled)
	assert(bool(stopped.get("ok", false)) and not entry.training_order, "Pilot stops on the fatigue line: " + str(stopped))
	team.team_fatigue.fatigue = 0.0

	# Holder KO: head acts with the head's own decision record.
	team.apply_unit_contact(2, {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false})
	team.settle_combat_command()
	var acting := team.duty_resolve("team.training")
	assert(int(acting.decider) == captain and bool(acting.acting), str(acting))

	# Logistics pilot (vacant seat, head acts): a KO member lowers capacity.
	var before_capacity := controller.team_food_capacity(team)
	var assigned := DutyAI.review_logistics(controller, team, controlled)
	assert(bool(assigned.get("ok", false)), "Logistics pilot assigns: " + str(assigned) + " capacity " + str(before_capacity))
	assert(controller.team_food_capacity(team) > before_capacity)
	assert(bool(team.duty_traces[-1].acting) and str(team.duty_traces[-1].duty_id) == "team.logistics")

	# One whole scheduler round runs without touching the player.
	DutyAI.review(lab)
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_DUTY_AI_LAB_PASS: holder authority, head refused, training pilot start/stop through original entry, KO acting, logistics pilot, scheduler round")
	quit(0)
