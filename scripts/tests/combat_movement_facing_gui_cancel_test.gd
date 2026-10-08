extends SceneTree
## A GUI-consumed release must cancel the facing drag before unhandled map input.
## Injected root-view events verify cancellation contracts, not OS input across native windows.

const LAB_SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")
const GOAL := Vector2i(34, 26)

var _lab: TerrainLab
var _deadline := 0

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 30000
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline:
		_fail("Facing GUI cancellation test timed out")
	return false

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _require(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition

func _mouse(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event

func _map_point(cell: Vector2i) -> Vector2:
	return _lab.get_viewport().get_canvas_transform() * _lab.renderer.cell_center(cell)

func _run() -> void:
	if not _require(OS.get_cmdline_user_args().has("--site-test-ui"), "Explicit test formation controls require --site-test-ui"): return
	root.size = Vector2i(1280, 720)
	_lab = LAB_SCENE.instantiate() as TerrainLab
	_lab.pause_when_unfocused = false
	root.add_child(_lab)
	current_scene = _lab
	_lab.set_process(false)
	_lab.site_controller.set_process(false)
	_lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in _lab.combat_actors:
		actor.set_process(false)
	for team: TerrainArmy in _lab.combat_armies:
		team.set_process(false)
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "facing-gui-cancel-fixture")
	data.resource_base.clear()
	data.resources_at.clear()
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	_lab.bind_terrain(data)
	_lab.character.place(Vector2i(60, 60), true)
	var deployed: Dictionary = _lab.start_melee_trial({"friendly_count": 4, "enemy_count": 1,
		"friendly_spawn": Vector2i(24, 25), "enemy_spawn": Vector2i(75, 75),
		"friendly_attack": false, "enemy_attack": false, "enemy_role": "logistics"})
	if not _require(bool(deployed.get("ok", false)), "Cannot deploy the four-person UI fixture: " + str(deployed)): return
	_lab.camera.position = _lab.renderer.cell_center(GOAL)
	_lab.camera.force_update_scroll()
	_lab.site_controller._layout()
	await process_frame
	var controller: SiteController = _lab.site_controller
	var army: TerrainArmy = _lab.army
	var slower := _lab.find_child("SlowerSite", true, false) as Button
	if not _require(slower != null and slower.is_visible_in_tree(), "Top GUI button is unavailable"): return
	var ui_point := slower.get_global_rect().get_center()
	var map_point := _map_point(GOAL)
	if not _require(controller.camera_usable_rect().has_point(map_point), "Map fixture is outside the shared usable map rectangle"): return
	controller._use_formation_controls("test")
	if not _require(controller.formation_command_source != null, "Explicit test formation controls were not installed"): return
	controller.formation_command_source.select(1)
	controller._formation_context_changed()
	if not _require(controller._formation_source() == "test", "Fixture must use the explicitly selected test-command source"): return
	controller.formation_preset_choice.select(1)
	var old_preset := army.formation_preset_id
	var selection_serial := army.get_order_serial()
	controller._select_formation_candidate(1)
	if not _require(controller._formation_candidate_id == "square" and army.formation_preset_id == old_preset
		and army.get_order_serial() == selection_serial, "Choosing a candidate changed the Army before issuing an order"): return
	var preview_signature := controller._formation_preview_signature
	var registry: SiteDeploymentReservationRegistry = _lab.combat_movement_coordinator.deployment_registry
	var external_id := 987654
	var extra_lease := registry.try_replace_reservations(external_id, -1, 1, [Vector2i(95, 95)])
	if not _require(bool(extra_lease.get("ok", false)), "Cannot set an external preview lease fixture"): return
	controller._update_formation_controls()
	if not _require(controller._formation_preview_signature != preview_signature,
		"External lease change did not refresh the candidate preview"): return
	registry.release_order(external_id)
	controller._update_formation_controls()
	controller._begin_facing_move("test")
	if not _require(controller.handle_input(_mouse(map_point, true)), "Map press was not handled"): return
	var drag := InputEventMouseMotion.new()
	drag.position = _map_point(GOAL + Vector2i.UP * 2)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	if not _require(controller.handle_input(drag) and controller.view.combat_preview_facing == Vector2i.UP, "Map drag did not create a facing preview"): return
	var old_serial := army.get_order_serial()
	# _input sees the release, while the visible Button can consume it before
	# TerrainLab._unhandled_input. Do not consume the GUI button's own action.
	_lab._input(_mouse(ui_point, false))
	if not _require(controller._facing_order_source.is_empty() and controller._facing_order_anchor == Vector2i(-1, -1)
		and controller._formation_candidate_id.is_empty() and army.formation_preset_id == old_preset
		and controller.view.combat_preview_platform_slots.is_empty() and controller.view.combat_preview_queue_slots.is_empty(),
		"Releasing over top GUI left a pending facing gesture or preview"): return
	controller.handle_input(_mouse(map_point, false))
	if not _require(army.get_order_serial() == old_serial and army.combat_order != TerrainArmy.CombatOrder.MOVE,
		"A later map release issued a stale facing MOVE"): return
	controller._begin_facing_move("test")
	_lab._input(_mouse(ui_point, true))
	if not _require(controller._facing_order_source.is_empty(), "Starting a top GUI click left facing mode armed"): return
	controller._begin_facing_move("test")
	if not _require(controller.handle_input(_mouse(map_point, true)), "Second map press was not handled"): return
	if not _require(controller.handle_input(drag), "Second map drag was not handled"): return
	var map_release := _mouse(drag.position, false)
	_lab._input(map_release)
	if not _require(controller._facing_order_source == "test", "Ordinary map release was canceled as GUI input"): return
	if not _require(controller.handle_input(map_release), "Ordinary map release was not handled"): return
	var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	if not _require(army.combat_order == TerrainArmy.CombatOrder.MOVE and plan != null and plan.final_facing == Vector2i.UP
		and controller._facing_order_source.is_empty(), "Ordinary map drag no longer issues a facing MOVE"): return
	controller.formation_preset_choice.select(1)
	controller._select_formation_candidate(1)
	if not _require(army.formation_preset_id == old_preset, "Second candidate selection changed the committed preset"): return
	controller._begin_facing_move("test")
	if not _require(controller.handle_input(_mouse(map_point, true)) and controller.handle_input(_mouse(map_point, false)),
		"Point-and-release order was not handled"): return
	plan = army.get_active_deployment_plan()
	if not _require(plan != null and plan.formation_preset_id == "square" and army.formation_preset_id == "square",
		"Point-and-release did not commit the selected formation preset"): return
	for tick in range(1200):
		if army.combat_order == TerrainArmy.CombatOrder.HOLD:
			break
		_lab._advance_combat(0.05)
		if tick % 30 == 0: await process_frame
	if not _require(army.combat_order == TerrainArmy.CombatOrder.HOLD and army.get_active_deployment_plan() == plan
		and plan.requested_count == 4 and plan.member_slot_map.size() == 4 and army._automatic_deployment_settled()
		and army._settled_deployment_leases_valid() and army.get_active_movement_claims().is_empty(),
		"Four-person formation did not reach a valid settled HOLD before the missing-member status check: " + army.command_status): return
	var missing_index := army.combat_units.size() - 1
	var missing_id := army.combat_identity(missing_index)
	army.combat_units[missing_index].hp = 0.0
	army.combat_units[missing_index].dead = true
	army._cell_owners.erase(army.cells[missing_index])
	army.remove_member_from_combat_plans(missing_id)
	if not _require(army.combat_order == TerrainArmy.CombatOrder.HOLD and plan.requested_count == 4
		and plan.member_slot_map.size() == 3 and army._automatic_deployment_settled()
		and army._settled_deployment_leases_valid(), "Remaining automatic members lost their settled HOLD or leases"): return
	controller._update_formation_controls()
	var status: String = controller.formation_status_label.text
	if not _require((status.begins_with("可動隊員已整隊；缺員") or status.begins_with("自動隊員已到位；缺員"))
		and status.contains("缺員 1"), "Settled missing-member status must name the settled survivors and one absence: " + status): return
	print("COMBAT MOVEMENT FACING GUI CANCEL PASS: injected root-view GUI/map events, original formation reservations and stale-release rejection; real OS/native-window input is not verified")
	_lab.queue_free()
	quit(0)
