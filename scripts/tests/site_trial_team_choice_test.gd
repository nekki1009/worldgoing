extends SceneTree

class TestLab extends Node2D:
	var combat_armies: Array[TerrainArmy] = []

func _initialize() -> void:
	var lab := TestLab.new()
	var controller := SiteController.new()
	controller.lab = lab
	controller.trial_command_team = OptionButton.new()
	var teams: Array[TerrainArmy] = []
	for id in [11, 22, 33, 44]:
		var team := TerrainArmy.new()
		team.team_id = id
		team.faction_id = id % 3
		lab.combat_armies.append(team)
		teams.append(team)
	controller._sync_trial_team_choices()
	assert(controller.trial_command_team.item_count == 4)
	controller.trial_command_team.select(3)
	assert(controller._selected_trial_team() == lab.combat_armies[3])
	lab.combat_armies.remove_at(1)
	controller._sync_trial_team_choices()
	assert(controller.trial_command_team.selected == 2)
	assert(controller._selected_trial_team().team_id == 44)
	lab.combat_armies.remove_at(2)
	controller._sync_trial_team_choices()
	assert(controller.trial_command_team.selected == -1)
	assert(controller._selected_trial_team() == null)
	controller.trial_command_team.free()
	controller.free()
	lab.free()
	for team in teams:
		team.free()
	await process_frame
	print("site_trial_team_choice_test PASS")
	quit(0)
