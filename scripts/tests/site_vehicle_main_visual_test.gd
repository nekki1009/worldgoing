extends SceneTree
## Actual formal scene, original UI and original Army MOVE, on untouched generated terrain.
const OUT := "res://output/site_wagon_rider_display_20260918/main_visual"
const RiderAtlas = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
var deadline := 0
var lab: TerrainLab
var _output := OUT
var _original_gear := {}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 65000
	_run.call_deferred()

func _remember_original_gear() -> void:
	for team: TerrainArmy in lab.combat_armies:
		for index in range(team.combat_units.size()):
			var row: Dictionary = team.combat_units[index]
			var appearance := team.equipment_appearance(index)
			assert(not RiderAtlas.ClothRecipe.matches(appearance) and appearance.parts.armor == "armor_light_leather_01" and appearance.parts.weapon == "longsword_01" and appearance.parts.shield == "shield_heater_01", "Logistics must keep its original team equipment, including people who start mounted")
			var records := {}
			for item: String in row.item_state.equipped.values(): records[item] = lab.terrain.site.item_records[item].duplicate(true)
			_original_gear[team.combat_identity(index)] = {"appearance": appearance.duplicate(true), "holder": row.item_state,
				"equipped": row.item_state.equipped.duplicate(), "records": records}

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Vehicle main visual deadline")
		quit(1)
	return false

func _press(ui: SiteController, name: String) -> void:
	var button := ui.combat_window.find_child(name, true, false) as Button
	assert(button != null, name)
	button.pressed.emit()

func _patch() -> Vector2i:
	for y in range(1, lab.terrain.size.y - 10):
		for x in range(1, lab.terrain.size.x - 10):
			var legal := true
			for row in range(10):
				for column in range(10):
					var cell := Vector2i(x + column, y + row)
					if not lab.terrain.is_walkable(cell) or lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell): legal = false
					if column > 0 and not lab.terrain.can_step(cell - Vector2i.RIGHT, cell) or row > 0 and not lab.terrain.can_step(cell - Vector2i.DOWN, cell): legal = false
			if legal: return Vector2i(x, y)
	return TerrainArmy.INVALID_CELL

func _capture(name: String) -> void:
	# Army combat-mode frame updates are presentation only; the Lab owns time.
	for team: TerrainArmy in lab.combat_armies: team.advance_frame(0.0)
	lab.site_controller.vehicle_view.refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	for team: TerrainArmy in lab.combat_armies:
		if not team.has_army(): continue
		for index in range(team.combat_units.size()):
			var appearance := team.equipment_appearance(index)
			var row: Dictionary = team.combat_units[index]
			var original: Dictionary = _original_gear[team.combat_identity(index)]
			assert(appearance == original.appearance and row.item_state.equipped == original.equipped and is_same(row.item_state, original.holder), "Mounting/dismounting cannot replace original gear, colors, equipped IDs or holder")
			assert(SiteRuntime.equipment_appearance(lab.terrain, row.item_state, row.appearance) == original.appearance, "Real equipment and cached appearance must still agree")
			for item: String in original.records:
				assert(lab.terrain.site.item_records[item] == original.records[item] and row.item_state.item_ids.has(item), "Original equipment instances, owners and dyes remain unchanged")
			var sprite: Sprite2D = team._sprites[index]
			assert(sprite != null and sprite.texture != null)
			var state := team._vehicle_rider_state(index)
			if state.is_empty():
				assert(not sprite.has_meta("vehicle_rider_frame"))
				assert(sprite.position.is_equal_approx(team.combat_ground(index) + team.combat_offset(index) - team._unit_anchor(index)), "Original walking person must follow its real position")
			else:
				var frame := RiderAtlas.frame(appearance, team._soldier_direction_id(state.facing), state.moving, state.progress)
				var fixed := RiderAtlas.frame(RiderAtlas.ClothRecipe.appearance(int(appearance.body)), team._soldier_direction_id(state.facing), state.moving, state.progress)
				assert(not frame.is_empty() and sprite.get_meta("vehicle_rider_frame", "") == frame.key)
				assert(is_same(sprite.texture, fixed.texture) and is_same(frame.texture, fixed.texture) and sprite.material == null, "Only the mounted image uses fixed undyed cloth by sex, regardless of real gear")
				assert(sprite.position.is_equal_approx(Vector2(state.position) + Vector2(frame.horse_offset) - Vector2(frame.anchor)), "Original rider must meet the actual horse, not the logical cell or the vehicle rear")
				assert(sprite.z_index == 10 + int(Vector2(state.position).y / TerrainRenderer.CELL_PIXELS))
	assert(root.get_texture().get_image().save_png(_output + "/" + name + ".png") == OK)

func _select_vehicle(ui: SiteController, identity: String) -> void:
	ui._refresh_vehicle_controls()
	for index in range(ui.vehicle_choice.item_count):
		if str(ui.vehicle_choice.get_item_metadata(index)) == identity:
			ui.vehicle_choice.select(index)
			ui._refresh_vehicle_details()
			return
	assert(false, "Actual vehicle missing from original popup")

func _select_operator(ui: SiteController, identity: int) -> void:
	for index in range(ui.vehicle_operator_choice.item_count):
		if int(ui.vehicle_operator_choice.get_item_metadata(index)) == identity:
			ui.vehicle_operator_choice.select(index)
			return
	assert(false, "Original operator missing from original popup")

func _walk_person(team: TerrainArmy, index: int, goal: Vector2i) -> void:
	var route := team._find_local_route(team.cells[index], goal, 256, false, index)
	assert(not route.is_empty() or team.cells[index] == goal, "Real person needs a legal path beside the horse")
	# The original path includes its starting cell; it is not a new step.
	for next: Vector2i in route.slice(1):
		assert(team._reserve_combat_step(index, next))
		for tick in range(30):
			lab._process(1.0 / 30.0)
			if team.moving_to[index] == TerrainArmy.INVALID_CELL: break
		assert(team.cells[index] == next)
	assert(team.cells[index] == goal)

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	assert(DirAccess.make_dir_recursive_absolute(_output) == OK)
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn")
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var main: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = main.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	var ui: SiteController = lab.site_controller
	ui._auto_save_blocked = true
	ui.release_worker()
	var origin := _patch()
	assert(origin != TerrainArmy.INVALID_CELL)
	for prefix: String in ["friendly", "enemy"]:
		ui.trial_roles[prefix].select(2)
		ui.trial_roles[prefix].item_selected.emit(2)
	ui.trial_friendly_count.value = 2
	ui.trial_enemy_count.value = 3 # Original female captain and ordinary male, plus one wagon.
	ui.trial_friendly_female_percent.value = 0
	ui.trial_enemy_female_percent.value = 50
	ui.trial_carts.friendly.value = 1
	ui.trial_wagons.enemy.value = 1
	ui.trial_friendly_spawn = origin + Vector2i(3, 3)
	ui.trial_enemy_spawn = origin + Vector2i(3, 7)
	_press(ui, "StartMeleeTrial")
	assert(ui.vehicles.records().size() == 2, ui.message.text)
	_remember_original_gear()
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	ui._refresh_vehicle_controls()
	ui._open_combat_window()
	await _capture("vehicle_settings")
	var controls := ui.combat_window.find_child("TrialVehicleControls", true, false) as Control
	var parent: Node = controls.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	assert(parent != null)
	(parent as ScrollContainer).ensure_control_visible(controls)
	await _capture("vehicle_operations")
	ui.combat_window.hide()
	lab.camera.zoom = Vector2.ONE * 1.35
	lab.camera.position = (Vector2(origin) + Vector2(6, 5)) * TerrainRenderer.CELL_PIXELS + Vector2(250, 120) / 1.35
	lab.camera.force_update_scroll()
	var initial := ui.vehicles.records().duplicate(true)
	var positions := [lab.army.cells[0], lab.opposing_army.cells[0]]
	await _capture("vehicles_before")
	for index in range(2):
		ui.trial_command_team.select(index)
		ui.selected = positions[index] + Vector2i.RIGHT * 3
		_press(ui, "TrialTeamMove")
		assert(lab.combat_armies[index].combat_order == TerrainArmy.CombatOrder.MOVE, ui.message.text)
	var observed := {}
	var frames := {}
	var rider_frames := {}
	for step in range(120):
		lab._process(0.05)
		for team: TerrainArmy in lab.combat_armies: team.advance_frame(0.0)
		ui.vehicle_view.refresh()
		for identity: String in ui.vehicles.records():
			var vehicle: Dictionary = ui.vehicles.records()[identity]
			if not vehicle.move.is_empty():
				observed[vehicle.kind] = true
				var sprite: Sprite2D = ui.vehicle_view._sprites[identity]
				frames[str(sprite.get_meta("vehicle_frame"))] = true
		for team: TerrainArmy in lab.combat_armies:
			for sprite: Sprite2D in team._sprites:
				if sprite != null and sprite.has_meta("vehicle_rider_frame"):
					rider_frames[str(sprite.get_meta("vehicle_rider_frame"))] = true
		if step in [12, 20]: await _capture("vehicles_moving_%d" % step)
		if step % 30 == 0: await process_frame
	assert(observed.has("cart") and observed.has("wagon") and frames.size() >= 8, str(frames))
	assert(rider_frames.size() >= 5, "Rider must use the original shared movement progress, not a static riding picture")
	for index in range(2):
		assert(lab.combat_armies[index].cells[0] == positions[index] + Vector2i.RIGHT * 3)
	for vehicle: Dictionary in ui.vehicles.records().values():
		assert(vehicle.facing == [1, 0] and vehicle.move.is_empty())
	await _capture("vehicles_arrived")
	var cart: Dictionary = ui.vehicles.records()[ui.vehicle_choice.get_item_metadata(0)]
	assert(cart.kind == "cart")
	ui.vehicle_choice.select(0)
	ui._refresh_vehicle_details()
	_press(ui, "ParkTrialVehicle")
	assert(int(cart.operator_id) == 0)
	var parked := cart.duplicate(true)
	ui.trial_command_team.select(0)
	ui.selected = lab.army.cells[0] + Vector2i.DOWN
	_press(ui, "TrialTeamMove")
	for step in range(50): lab._process(0.05)
	assert(cart == parked, "Without an operator a cart must not follow its original team")
	ui.selected = lab.terrain.cell_from_index(int(cart.cell)) - Vector2i.RIGHT
	_press(ui, "TrialTeamMove")
	for step in range(50): lab._process(0.05)
	_press(ui, "AssignTrialVehicleOperator")
	assert(int(cart.operator_id) == lab.army.combat_identity(0), ui.message.text)
	var wagon: Dictionary = {}
	for vehicle: Dictionary in ui.vehicles.records().values():
		if vehicle.kind == "wagon": wagon = vehicle
	assert(not wagon.is_empty())
	var team := lab.opposing_army
	assert(team.combat_units.size() == 2 and team.equipment_appearance(0).body == 1 and team.equipment_appearance(1).body == 0)
	ui.trial_command_team.select(1)
	_press(ui, "TrialTeamHold")
	_select_vehicle(ui, wagon.id)
	var parked_wagon_cell: int = wagon.cell
	var horse_cell := ui.vehicles.operator_cell(wagon)
	assert(team.cells[0] == horse_cell and int(wagon.operator_id) == team.combat_identity(0))
	_press(ui, "ParkTrialVehicle")
	assert(wagon.move.get("dismount", false) and team.moving_to[0] != TerrainArmy.INVALID_CELL)
	lab._process(0.1)
	await _capture("wagon_dismounting")
	for step in range(30): lab._process(1.0 / 30.0)
	assert(int(wagon.operator_id) == 0 and int(wagon.cell) == parked_wagon_cell and team.cells[0] != horse_cell)
	await _capture("wagon_dismounted")
	await _capture("female_original_gear")
	_select_vehicle(ui, wagon.id)
	_select_operator(ui, team.combat_identity(0))
	_press(ui, "AssignTrialVehicleOperator")
	assert(wagon.move.get("boarding", false) and team.moving_to[0] == horse_cell)
	lab._process(0.1)
	await _capture("wagon_boarding")
	for step in range(30): lab._process(1.0 / 30.0)
	assert(team.cells[0] == horse_cell and int(wagon.cell) == parked_wagon_cell and wagon.move.is_empty())
	await _capture("wagon_female_rider")
	await _capture("female_cloth_rider")
	# The same real wagon also accepts an ordinary male member, not a duplicate driver.
	_select_vehicle(ui, wagon.id)
	_press(ui, "ParkTrialVehicle")
	for step in range(30): lab._process(1.0 / 30.0)
	await _capture("female_original_gear_restored")
	var beside_horse := team.cells[0]
	_walk_person(team, 0, origin + Vector2i(9, 9))
	assert(team.cells[0] == origin + Vector2i(9, 9))
	_walk_person(team, 1, beside_horse)
	assert(team.cells[1] == beside_horse)
	await _capture("male_original_gear")
	_select_vehicle(ui, wagon.id)
	_select_operator(ui, team.combat_identity(1))
	_press(ui, "AssignTrialVehicleOperator")
	assert(wagon.move.get("boarding", false))
	for step in range(30): lab._process(1.0 / 30.0)
	assert(int(wagon.operator_id) == team.combat_identity(1) and team.cells[1] == horse_cell and int(wagon.cell) == parked_wagon_cell)
	assert(team.combat_units.size() + ui.vehicles.team_vehicle_count(team) == 3, "One rider and one wagon still occupy two distinct slots; the former rider remains his/her original person")
	await _capture("wagon_ordinary_male_rider")
	await _capture("male_cloth_rider")
	_select_vehicle(ui, wagon.id)
	_press(ui, "ParkTrialVehicle")
	for step in range(30): lab._process(1.0 / 30.0)
	assert(int(wagon.operator_id) == 0 and team.cells[1] != horse_cell and team.moving_to[1] == TerrainArmy.INVALID_CELL)
	await _capture("male_original_gear_restored")
	var report := {"passed": true, "main_scene": ProjectSettings.get_setting("application/run/main_scene"),
		"original_people": 3, "vehicles": 2, "original_terrain": true, "ui_move_three_cells": true,
		"moving_kinds": observed.keys(), "observed_animation_frames": frames.keys(),
		"observed_rider_frames": rider_frames.keys(), "wagon_original_step_boarding_dismount": true,
		"female_captain_and_ordinary_male_riders": true, "rider_and_vehicle_separate_slots": true,
		"cloth_is_mounted_display_only": true, "original_gear_colors_items_preserved": true, "both_genders_original_cloth_original_cycle": true,
		"unassign_stays_parked": true, "original_person_walks_back_and_reassigns": true, "initial": initial, "final": ui.vehicles.records()}
	var file := FileAccess.open(_output + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE_VEHICLE_MAIN_VISUAL_PASS ", JSON.stringify(report))
	lab.queue_free()
	await process_frame
	quit(0)
