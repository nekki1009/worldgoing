extends "res://scripts/tests/site_bridge_contract_test.gd"
## GPU fixture only. Uses original D5 and native movement, never mirrored GD motion.
const CrowdHost = preload("res://scripts/terrain_lab/crowd_site.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 240000
	var args := OS.get_cmdline_user_args()
	assert(args.has("--crowd-test") and args.has("--crowd-atlas-root") and not args.has("--crowd"))
	assert(DisplayServer.get_name() != "headless")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_bridge_output("crowd")
	root.size = Vector2i(1440, 960)
	root.content_scale_size = root.size
	for material: String in ["wood", "stone"]:
		await _native_bridge(material)
	TerrainArmy.release_contact_source()
	print("SITE_BRIDGE_CROWD_PASS: wood/stone real native two-person crossings after original D5, reserved demolition refusal, same original records/holders/cargo, 1/4-worker snapshot parity, native terrain flags, two formal renderer captures; no travel/performance claim")
	quit(0)

func _native_bridge(material: String) -> void:
	var data := _bridge_fixture()
	var base := _bridge_base(data)
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var key := _formal_feature(data, "bridge", Vector2i(20, 20), Vector2i(1, 4), {"material": material})
	var source: TerrainArmy = lab.army
	source.roster_size = 2
	source.faction_id = 1
	assert(source.deploy_at(data, lab.character, lab.npc, [Vector2i(20, 24), Vector2i(20, 25)]))
	assert(source.enable_combat(false, 0))
	source.set_process(false)
	source.settle_combat_command()
	var team := source.team_id
	var originals := {}
	for row: Dictionary in source.combat_units:
		originals[int(row.person_id)] = {"row": row, "holder": row.item_state, "cargo": row.cargo}
	var first := int(originals.keys()[0])
	var appearance := Runtime.equipment_appearance(data, originals[first].holder, originals[first].row.appearance)
	assert(await CrowdHost.prepare_captivity_recipe(lab, appearance))
	lab.crowd_site = CrowdHost.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	var entered: Dictionary = lab.deploy_trial_armies([{"faction": 1, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(40, 40)}])
	assert(entered.ok, str(entered))
	var host: Node = lab.crowd_site
	assert(host.active and host.issue_order(team, TerrainArmy.CombatOrder.MOVE, Vector2i(20, 17)).ok)
	var seen := {}
	var tested_reservation := false
	var arrived := false
	for frame: int in range(3600):
		assert(Time.get_ticks_msec() < deadline)
		lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
		arrived = true
		for identity: int in originals:
			var state: Dictionary = host.soldier_state(int(host.crowd.soldier_index(identity)))
			var cell := Vector2i(floori(float(state.px)), floori(float(state.py)))
			if cell.y >= 20: arrived = false
			if cell.x == 20 and cell.y >= 20 and cell.y <= 23:
				seen[identity] = true
				assert(data.is_walkable(cell) and not data.can_navigate_water(cell))
				assert(controller.reserves_cell(cell))
				if not tested_reservation:
					var native_before: PackedByteArray = host.crowd.save_state()
					var feature_before := JSON.stringify(data.site.features)
					assert(not Runtime.cancel_feature(data, key, controller.reserves_cell, 1).ok)
					assert(host.crowd.save_state() == native_before and JSON.stringify(data.site.features) == feature_before)
					tested_reservation = true
		if arrived and seen.size() == 2: break
		if frame % 30 == 0: await process_frame
	assert(arrived and seen.size() == 2 and tested_reservation, str({"arrived": arrived, "seen": seen, "reserved": tested_reservation}))
	assert(host.issue_order(team, TerrainArmy.CombatOrder.HOLD).ok)
	for _settle: int in range(30): lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
	for identity: int in originals:
		assert(is_same(host._records[identity], originals[identity].row))
		var person: Dictionary = controller.person_actions._person(identity)
		assert(is_same(person.holder, originals[identity].holder) and is_same(person.cargo, originals[identity].cargo))
	assert(controller._capture_for_save().ok)
	var one: Dictionary = Store._validate_crowd(data, data.site, 1)
	var four: Dictionary = Store._validate_crowd(data, data.site, 4)
	assert(one.ok and four.ok, str({"one": one, "four": four}))
	assert(one.native.save_state() == host.crowd.save_state() and four.native.save_state() == host.crowd.save_state())
	var path := bridge_output.path_join(material + "_native.json")
	assert(Store.save(data, path).ok)
	var loaded := Store.load_site(path, _bridge_loader(base))
	assert(loaded.ok and loaded.data.navigation_flags() == data.navigation_flags(), str(loaded))
	assert(Store._validate_crowd(loaded.data, loaded.data.site, 1).ok)
	controller.view.refresh()
	lab.get_node("SiteUI").hide()
	controller.hide_tool_windows()
	# The fixture freezes Lab processing; run its original Native presentation explicitly.
	host.render(0.0)
	var presented := 0
	for node: MultiMeshInstance2D in host.nodes.values():
		if node.visible and node.texture != null and node.multimesh != null:
			presented += node.multimesh.instance_count if node.multimesh.visible_instance_count < 0 else node.multimesh.visible_instance_count
	assert(presented >= originals.size(), "Original Native people must be rendered before the bridge capture")
	lab.camera.position = Vector2(20.5, 21.5) * TerrainRenderer.CELL_PIXELS
	lab.camera.zoom = Vector2.ONE * 1.8
	lab.camera.reset_smoothing()
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(bridge_output.path_join(material + "_bridge.png")) == OK)
	assert(Runtime.cancel_feature(data, key, controller.reserves_cell, 1).ok)
	assert(data.can_navigate_water(Vector2i(20, 21)) and not data.is_walkable(Vector2i(20, 21)))
	host.sync_terrain()
	assert(controller._capture_for_save().ok and Store._validate_crowd(data, data.site, 1).ok)
	lab.free()
	await process_frame
