extends SceneTree
## GPU-only captures of the real main scene and original people/vehicle owners.
# The formal entry point is the main menu since ef39140 (World / Region / Site layers). This fixture
# drives the original TerrainLab scene directly and only checks that the entry was not changed.
const FORMAL_ENTRY_SCENE := "res://scenes/main_menu/MainMenu.tscn"
const ORIGINAL_SITE_SCENE := "res://scenes/terrain_lab/TerrainLab.tscn"
const OUT := "res://output/site_siege_generated_art_20261003/integration/legacy_visual"
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
var deadline := 0
var lab: TerrainLab
var team: TerrainArmy
var captures: Array[Dictionary] = []
var identity := ""
var anchor := Vector2i(24, 22)

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 75000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Siege formal visual deadline")
		quit(1)
	return false

func _tick(seconds: float = 1.0 / 30.0) -> void:
	assert(Time.get_ticks_msec() < deadline, "Siege visual fixture exceeded its deadline")
	lab._process(seconds)

func _capture(name_value: String, details: Dictionary = {}) -> void:
	for army: TerrainArmy in lab.combat_armies: army.advance_frame(0.0)
	lab.site_controller.view.refresh()
	lab.site_controller.vehicle_view.refresh()
	for _frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(OUT + "/" + name_value + ".png") == OK)
	details.merge({"file": name_value + ".png", "original_people": team.combat_units.size(),
		"vehicle_id": identity, "anchor": [anchor.x, anchor.y]}, true)
	captures.append(details)
	assert(Time.get_ticks_msec() < deadline)

func _focus(point: Vector2, zoom: float = 1.6) -> void:
	lab.camera.zoom = Vector2.ONE * zoom
	lab.camera.position = point
	lab.camera.reset_smoothing()
	lab.camera.force_update_scroll()

func _show_control(window: Window, control_name: String) -> Control:
	var control := window.find_child(control_name, true, false) as Control
	assert(control != null, "Missing original UI control: " + control_name)
	var parent := control.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	assert(parent != null, "Original UI control must retain its scrollable tool window")
	(parent as ScrollContainer).ensure_control_visible(control)
	return control

func _select_vehicle() -> void:
	var ui: SiteController = lab.site_controller
	var form: Dictionary = ui._vehicle_forms.formal
	ui._refresh_vehicle_controls(form)
	for index in range(form.choice.item_count):
		if str(form.choice.get_item_metadata(index)) == identity:
			form.choice.select(index)
			ui._refresh_vehicle_details(form)
			return
	assert(false, "Original transport popup lost the actual ballista")

func _walk(index: int, goal: Vector2i) -> void:
	var route := team._find_local_route(team.cells[index], goal, 256, false, index)
	assert(not route.is_empty() or team.cells[index] == goal)
	for next: Vector2i in route.slice(1):
		assert(team._reserve_combat_step(index, next), "The fixture worker must use original single-cell reservations")
		for _step in range(60):
			_tick()
			if team.moving_to[index] == TerrainArmy.INVALID_CELL: break
		assert(team.cells[index] == next and team.moving_to[index] == TerrainArmy.INVALID_CELL)

func _ram_proportion_proposal() -> void:
	# Pure approved-art display; the original vehicle/navigation records stay unchanged.
	var vehicles_before: Dictionary = lab.terrain.site.vehicles.duplicate(true)
	var proposal := Node2D.new()
	proposal.name = "RamApprovedArtPreviewOnly"
	proposal.position = (Vector2(anchor + Vector2i(-4, 3)) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	proposal.z_index = 100
	lab.add_child(proposal)
	var sprite: Sprite2D = lab.site_controller.vehicle_view.show_pure_preview("ram", Vector2i.RIGHT, proposal, Vector2(64, 32))
	assert(sprite != null and sprite.get_meta("siege_art_frame") == "ram/right")
	var caption := Label.new()
	caption.text = "衝車生圖已接入；P2玩法待續\n2×3格（4×6m）；旁側為原Army人物比例參考。"
	caption.add_theme_font_override("font", lab.site_controller.details.get_theme_font("font"))
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color("f1e6bd"))
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	caption.position = Vector2(-180, -340)
	proposal.add_child(caption)
	_focus((Vector2(anchor) + Vector2(-1, 2)) * TerrainRenderer.CELL_PIXELS, 1.0)
	await _capture("08_ram_proportion_proposal", {"proposal_only": true, "kind": "ram", "envelope_cells": [2, 3],
		"envelope_metres": [4, 6], "minimum_crew_reference": 2,
		"original_reference_ids": [team.combat_identity(0), team.combat_identity(1)],
		"implementation": "Approved imagegen Sprite through original VehicleView; P2 mechanics pending"})
	assert(lab.terrain.site.vehicles == vehicles_before, "Ram art preview must not create or alter formal vehicle records")

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "This test needs the GPU viewport")
	assert(ProjectSettings.get_setting("application/run/main_scene") == FORMAL_ENTRY_SCENE)
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var main: PackedScene = load(ORIGINAL_SITE_SCENE)
	lab = main.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	# Explicit flat-map/material fixture; no production asset or gameplay owner is replaced.
	var data := Helper.build_flat_map(60, 44)
	data.spawn_cell = Vector2i(4, 4)
	data.site.player_cell = data.index(data.spawn_cell)
	data.site.manual.cell = data.site.player_cell
	data.site.worker.cell = data.index(Vector2i(4, 3))
	data.site.depot_cell = data.index(Vector2i(3, 4))
	data.site.capacity = 1000000
	data.site.inventory = {"wood": 240, "iron": 120, "fiber": 100, "tools": 20, "siege_bolt": 20}
	lab.bind_terrain(data)
	assert(lab.terrain == data)
	var ui: SiteController = lab.site_controller
	ui._auto_save_blocked = true
	ui.release_worker()
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	team = lab.army
	team.team_id = lab._next_army_identity()
	team.roster_size = 2
	var initial: Array[Vector2i] = [anchor - Vector2i(3, 0), anchor - Vector2i(3, -1)]
	assert(team.deploy_at(data, lab.character, lab.npc, initial) and team.enable_combat(false, 0))
	team.set_process(false)
	var built := Runtime.begin_siege_build(data, "ballista", anchor, Vector2i.RIGHT, team.team_id,
		team.combat_identity(0), ui.reserves_cell)
	assert(built.ok and int(data.site.inventory.wood) == 216, str(built))
	identity = str(built.vehicle)
	var vehicle: Dictionary = data.site.vehicles[identity]
	assert(vehicle.phase == "building")
	_focus((Vector2(anchor) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS)
	ui.hide_tool_windows()
	await _capture("01_building", {"phase": vehicle.phase, "paid_materials": true})
	ui.open_window("construction")
	await process_frame
	var construction_control := _show_control(ui.formal_windows.construction, "SiegeBuildPreview")
	await _capture("02_formal_construction_ui", {"formal_construction": true})
	assert(construction_control.is_visible_in_tree() and ui.formal_windows.construction.visible)
	ui.hide_tool_windows()
	var station: Dictionary = Runtime.siege_work_slots(data, vehicle)[0]
	_walk(0, data.cell_from_index(int(station.cell)))
	assert(Runtime.advance_siege_work(data, identity, "construct", float(vehicle.build.total_work),
		team.cells[0], int(station.slot), team.team_id).ok)
	assert(vehicle.phase == "idle" and vehicle.build.is_empty() and float(vehicle.hp) == 140.0)
	# Visual crew commit requires each crew member's published appearance and prepared siege work
	# assets, exactly as the UI crew path prepares them (headless verifies mechanics only).
	var crew_ids: Array = [team.combat_identity(0), team.combat_identity(1)]
	for crew_id: Variant in crew_ids: ui.equipment_changed(int(crew_id))
	var crew_assets_ready: bool = await ui._prepare_siege_work_people(crew_ids)
	assert(crew_assets_ready, "Original Controller prepares the actual crew work assets before assignment")
	await process_frame # Leave the preparation's completion signal before continuing.
	for slot in range(2):
		var crew_assigned: Dictionary = ui.vehicles.assign_crew(identity, team.combat_identity(slot), str(slot), team.combat_identity(0), true)
		assert(crew_assigned.ok, str(crew_assigned))
	for _step in range(600):
		_tick()
		if ui.vehicles.crew_ready(vehicle) and vehicle.command.get("type", "") == "stop": break
	if not ui.vehicles.crew_ready(vehicle) or vehicle.phase != "ready":
		var rows: Array[Dictionary] = []
		for index in range(team.cells.size()):
			rows.append({"id": team.combat_identity(index), "cell": str(team.cells[index]), "moving_to": str(team.moving_to[index]), "progress": team.move_progress[index], "pose": team.combat_hot_get(index, &"pose"), "hp": team.combat_hot_get(index, &"hp"), "goal": str(ui.vehicles.crew_cell(vehicle, str(index)))})
		push_error("SIEGE_VISUAL_CREW_DIAGNOSTIC " + JSON.stringify({"rows": rows, "vehicle": vehicle, "paused": data.site.paused, "tree_paused": paused, "commander": team.current_commander, "eligible": team.command_eligible(team.current_commander), "armies": lab.combat_armies.size()}))
		quit(1)
		return
	for quarter in range(4):
		if quarter > 0:
			var old := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
			var next := Vector2i(-old.y, old.x)
			assert(ui.vehicles.order_siege(identity, "turn", {"facing": [next.x, next.y]}, team.combat_identity(0), true).ok)
			for _step in range(1000):
				_tick()
				if vehicle.action.is_empty() and vehicle.phase == "ready": break
			assert(vehicle.action.is_empty() and vehicle.phase == "ready" and ui.vehicles.crew_ready(vehicle))
			assert(vehicle.facing == [next.x, next.y])
		assert(int(vehicle.cell) == data.index(anchor), "Real turns must preserve the original pivot")
		assert(Runtime.siege_cells(data, vehicle).size() == 6)
		var node: Node2D = ui.vehicle_view._siege_nodes.get(identity)
		ui.vehicle_view.refresh()
		node = ui.vehicle_view._siege_nodes[identity]
		var body: Sprite2D = node.get_node("Body")
		var frame: Dictionary = ui.vehicle_view.siege_art_frame("ballista", Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])))
		assert(node.get_meta("siege_generated_art", false) and is_zero_approx(node.rotation))
		assert(body.texture == frame.texture and body.region_rect == frame.region and body.offset == -frame.pivot and is_zero_approx(body.rotation))
		await _capture("03_ready_q%d" % quarter, {"phase": vehicle.phase, "facing": vehicle.facing.duplicate(),
			"real_crew_cells": [[team.cells[0].x, team.cells[0].y], [team.cells[1].x, team.cells[1].y]],
			"solid_cells": 6, "pivot_stable": true})
	_select_vehicle()
	assert(ui._vehicle_forms.formal.status.text.contains("固定重弩") and ui._vehicle_forms.formal.status.text.contains("140"))
	ui.open_window("transport")
	await process_frame
	var attack_control := _show_control(ui.formal_windows.transport, "SiegeAttack")
	await _capture("04_formal_transport_ui", {"formal_transport": true, "status": ui._vehicle_forms.formal.status.text})
	assert(attack_control.is_visible_in_tree() and ui.formal_windows.transport.visible)
	ui.hide_tool_windows()
	assert(Runtime.damage_siege_vehicle(data, identity, 70.0).ok)
	assert(float(vehicle.hp) == 70.0 and bool(vehicle.ever_hp_damaged))
	_select_vehicle()
	await _capture("05_damaged", {"hp": vehicle.hp, "ever_hp_damaged": vehicle.ever_hp_damaged})
	# The fixture puts two real rounds in the original holder; release must debit it once.
	vehicle.cargo = {"siege_bolt": 2}
	vehicle.holder.version = int(vehicle.holder.version) + 1
	var target := {"type": "ground", "cell": [anchor.x, anchor.y - 16]}
	assert(lab.siege_fire_preview(vehicle, target).ok)
	assert(ui.vehicles.order_siege(identity, "attack", target, team.combat_identity(0), true).ok)
	for _step in range(600):
		_tick()
		if lab.has_siege_projectiles(): break
	assert(lab.has_siege_projectiles() and int(vehicle.cargo.siege_bolt) == 1 and int(vehicle.next_attack_seq) == 2)
	assert(ui.vehicles.order_siege(identity, "stop", {}, team.combat_identity(0), true).ok)
	var flight: Dictionary = lab.siege_projectiles[0]
	lab._advance_siege_projectiles(float(flight.total) * 0.4)
	_focus((Vector2(anchor) + Vector2(0, -7)) * TerrainRenderer.CELL_PIXELS, 0.85)
	await _capture("06_released_flight", {"original_round_debited_once": true, "attack_id": flight.attack_id})
	assert(Runtime.damage_siege_vehicle(data, identity, 999.0).ok)
	_tick()
	assert(vehicle.phase == "wrecked" and bool(vehicle.ever_hp_damaged) and int(vehicle.cargo.siege_bolt) == 1)
	assert(lab.has_siege_projectiles(), "Destroying the source must keep its released round alive")
	_focus((Vector2(anchor) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS)
	_select_vehicle()
	await _capture("07_wreck", {"hp": vehicle.hp, "cargo_preserved": vehicle.cargo.duplicate(), "released_round_survives": true})
	assert(vehicle.crew_slots.is_empty(), "Proposal people must already be safely released from the destroyed ballista")
	await _ram_proportion_proposal()
	var report := FileAccess.open(OUT + "/captures.json", FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify({"status": "SITE_SIEGE_FORMAL_VISUAL_PASS", "captures": captures,
		"scope": "Actual TerrainLab main scene captures: original SiteController/VehicleView/Army, paid Runtime build and completion, four real turns with physical crew cells, formal construction/transport UI, damage/wreck and one paid released round. Approved generated ballista and bolt art replace greybox geometry; the ram image is presentation only. Flat ground and initial cargo are explicit fixtures; visual review, other kinds gameplay and performance acceptance remain separate."}, "\t"))
	report.close()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_FORMAL_VISUAL_PASS: ", captures.size(), " original GPU captures")
	quit(0)
