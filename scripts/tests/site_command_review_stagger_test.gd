extends "res://scripts/tests/site_army_scale_rules_test.gd"

const STEP := 1.0 / 30.0

func _run() -> void:
	create_timer(12.0).timeout.connect(func() -> void: quit(1))
	for tactics in [0, 50, 100]:
		var lab := _fixture(false, 10, true)
		for team: TerrainArmy in lab.combat_armies:
			team.command_abilities[team.current_commander]["tactics"] = tactics
		var reviews := [[], []]
		for tick in range(180):
			_step(lab, reviews, tick)
		assert(reviews[0].size() >= 10 and reviews[1].size() >= 10)
		for i in range(mini(reviews[0].size(), reviews[1].size())):
			assert(reviews[1][i] == reviews[0][i] + 1, "Only one original action step of phase offset")
			if i > 0:
				assert(reviews[1][i] - reviews[1][i - 1] == reviews[0][i] - reviews[0][i - 1], "Review frequency must not decrease")
		# An explicit command keeps the original initial delay, even when both
		# orders arrive together; subsequent periodic reviews separate again.
		for team: TerrainArmy in lab.combat_armies:
			assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.ATTACK).ok)
		reviews = [[], []]
		for tick in range(60): _step(lab, reviews, tick)
		assert(reviews[0][0] == reviews[1][0], "First execution of a new order must stay unchanged")
		assert(reviews[1][1] == reviews[0][1] + 1)
		# Existing serialized elapsed/delay values retain the phase. No new
		# saved field is needed; real restore then resumes matching reviews.
		var restored := _fixture(false, 10, true)
		for side in range(2):
			var saved := lab.combat_armies[side].capture_combat_state()
			assert(TerrainArmy.valid_combat_state(saved, lab.terrain))
			restored.combat_armies[side].restore_combat_state(saved, restored.terrain, null, null)
		var resumed := [[], []]
		reviews = [[], []]
		for tick in range(60):
			_step(lab, reviews, tick)
			_step(restored, resumed, tick)
		assert(reviews == resumed, "Saved phase must resume identically")
		var phase := [lab.combat_armies[0]._command_elapsed, lab.combat_armies[1]._command_elapsed]
		lab.terrain.site.paused = true
		lab._advance_combat(1.0)
		assert(phase == [lab.combat_armies[0]._command_elapsed, lab.combat_armies[1]._command_elapsed])
		print("COMMAND_STAGGER_PASS tactics=", tactics, " one-step phase, unchanged period/new-order execution, actual save/restore, paused clock")
		_dispose(restored)
		_dispose(lab)
	quit(0)

func _step(lab: TerrainLab, reviews: Array, tick: int) -> void:
	for side in range(2):
		var team: TerrainArmy = lab.combat_armies[side]
		team._update_combat_orders(STEP)
		if team._command_elapsed == 0.0: reviews[side].append(tick)
