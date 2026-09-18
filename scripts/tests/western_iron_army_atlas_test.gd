extends "res://scripts/tests/site_army_equipment_formal_visual_test.gd"
## Real holders, original equipment commands and TerrainArmy sprites. Pose
## fixtures inspect presentation, not combat damage or sustained FPS.
const IRON_OUTPUT := "res://output/western_iron_atlas_20260913/visual"

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var baseline := _formal_catalog()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.CATALOG))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.BASE_MANIFEST))
	var clips: Array[Dictionary] = []
	clips.assign(source.clips)
	var directions: Array[Dictionary] = []
	directions.assign(source.directions)
	var current_plan := Plan.build(PackedStringArray(["--recipe-mask=31", "--recipe-output=res://output/validation", "--recipe-clips=all", "--recipe-directions=all", "--recipe-first=0", "--recipe-count=1"]), clips, directions, baseline)
	assert(current_plan.ok)
	var sequences_per_recipe: int = current_plan.clips.size() * current_plan.directions.size()
	var samples_per_recipe := int(current_plan.recipe_total)
	assert(catalog.recipes.size() == 39)
	for iron in range(1, 8):
		var appearance := Plan.appearance_for(31, baseline, iron)
		assert(Reader.supports(appearance) and Reader._appearance_iron(appearance) == iron)
		assert(Reader._recipe(31, iron).sequences.size() == sequences_per_recipe)
	var unsupported := Plan.appearance_for(31, baseline, 7)
	unsupported.parts.helmet = "helmet_steel_01"
	assert(not Reader.supports(unsupported), "Steel must not silently use the iron atlas")
	root.size = Vector2i(1500, 1000)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(IRON_OUTPUT))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	for owner: Node in [lab, lab.character, lab.npc, lab.site_controller, lab.army, lab.opposing_army]:
		owner.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	Env.initialize(data, "western-iron-atlas-fixture")
	for key: String in data.resource_base:
		Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	var used := {}
	assert(lab.character.place(_take_cell(data, Vector2i(80, 80), used), true))
	assert(lab.npc.place(_take_cell(data, Vector2i(82, 80), used), true))
	var cells: Array[Vector2i] = [_take_cell(data, Vector2i(70, 70), used)]
	for index in range(1, 9):
		cells.append(_take_cell(data, Vector2i(30 + ((index - 1) % 4) * 3, 30 + floori(float(index - 1) / 4.0) * 4), used))
	for index in range(9, 100):
		cells.append(_take_cell(data, Vector2i(65 + (index % 10), 65 + floori(float(index) / 10.0)), used))
	var team: TerrainArmy = lab.army
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	assert(team.visual_mode() == "baked_atlas" and team.active_3d_source_count() == 1)
	var orders: Variant = lab.site_controller.equipment_orders
	var actions: Variant = lab.site_controller.person_actions
	var originals := {}
	var created := 0
	for iron in range(1, 8):
		var body: Dictionary = team.combat_units[iron]
		var identity := team.combat_identity(iron)
		originals[identity] = body.item_state.equipped.duplicate(true)
		assert(lab.site_controller._control_family_person(null, identity).ok)
		for bit in range(3):
			if (iron & (1 << bit)) == 0:
				continue
			var slot: String = Plan.IRON_PARTS.keys()[bit]
			var asset: String = Plan.IRON_PARTS[slot]
			var result := Runtime.create_equipment(data, body.item_state, slot + ":" + asset,
				{"slot": slot, "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, identity)
			assert(result.ok)
			created += 1
			var command: Dictionary = orders.begin_personal(identity, slot, str(result.item_id))
			assert(command.ok, str(command))
			actions.advance(5.0)
			assert(actions.settle_after_contacts()[0].ok)
		assert(team.equipment_appearance(iron) == Plan.appearance_for(31, baseline, iron))
		assert(team._unit_editor(iron) == null and not team._uses_live_presenter(iron))
		assert(float(body.hp) == 100.0)
	assert(lab.site_controller._control_family_person(null, lab.character.person_id).ok)
	var inventory := _inventory(lab)
	lab.site_controller._capture_positions()
	assert(Store.save(data, IRON_OUTPUT + "/equipment_save.json").ok)
	var restored := Store.load_site(IRON_OUTPUT + "/equipment_save.json")
	assert(restored.ok)
	lab.bind_terrain(restored.data)
	team = lab.army
	assert(_inventory(lab) == inventory)
	for iron in range(1, 8):
		assert(team.equipment_appearance(iron) == Plan.appearance_for(31, baseline, iron))
	lab.get_node("SiteUI").hide()
	lab.get_node("TerrainLabUI").hide()
	var overlay := CanvasLayer.new()
	lab.add_child(overlay)
	title = Label.new()
	title.position = Vector2(24, 16)
	title.add_theme_font_size_override("font_size", 24)
	overlay.add_child(title)
	var checked := 0
	for pose: String in ["idle", "walk", "run", "guard", "walk_slash", "hit", "down", "get_up", "rescue"]:
		for direction: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]:
			for iron in range(1, 9):
				_fixture_pose(team, iron, pose, 0.537, pose == "walk_slash")
				team.facing[iron] = direction
			team.advance_frame(0.0)
			for iron in range(1, 8):
				var raw := team.contact_sample(iron)
				var frame := Reader.frame(team.equipment_appearance(iron), team._combat_clip(iron), team._soldier_direction_id(direction), float(raw[1]))
				assert(not frame.is_empty() and team._sprites[iron].texture == frame.texture)
				assert(team._soldier_current_keys[iron].begins_with("equipment|"))
				var anchor := Vector2(frame.anchor_offset.x, frame.anchor_offset.y) * float(frame.map_scale)
				assert(team._sprites[iron].position.distance_to(team.combat_ground(iron) + team.combat_offset(iron) - anchor) < 0.0001)
				checked += 1
			await _iron_capture(lab, pose + "_" + team._soldier_direction_id(direction), team.combat_ground(7) + Vector2(0, -28), 4.0)
			if pose == "idle" and direction == Vector2i.DOWN:
				await _iron_capture(lab, "all_combinations", Vector2(34.5, 31.5) * 64, 1.25)
	# Explicitly compare actual iron protection, not the filename or color.
	var iron_profile := SiteCombatRules.armor_profile("armor_western_iron_01")
	assert(iron_profile == SiteCombatRules.armor_profile("armor_iron_01"))
	assert(iron_profile != SiteCombatRules.armor_profile("armor_steel_01"))
	_fixture_pose(team, 7, "guard", 0.073)
	team.facing[7] = Vector2i.DOWN
	var geometry := team._continuous_pose(7)
	assert(not geometry.body.is_empty() and not geometry.shield.is_empty())
	var point := Vector2.ZERO
	for vertex: Vector2 in geometry.body[0]:
		point += vertex
	point /= geometry.body[0].size()
	var raw := team.contact_sample(7)
	var protection: Vector2 = TerrainArmy._contact_source.armor_at(raw[0], raw[1], raw[2], point, "slash", raw[3], raw[4], team.equipment_appearance(7))
	assert(protection.x > 0.0)
	assert(team.active_3d_source_count() == 1 and _inventory(lab) == inventory)
	assert(Plan.fingerprints() == catalog.source_fingerprints)
	var file := FileAccess.open(IRON_OUTPUT + "/measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"recipes": 39, "samples": catalog.recipes.size() * samples_per_recipe, "ordinary_iron_combinations": 7,
		"actual_equip_commands": created, "save_load": true, "sprite_states_checked": checked,
		"live_female_presenters": 1, "iron_profile": iron_profile, "chest_protection": [protection.x, protection.y],
		"source_fingerprints": catalog.source_fingerprints, "scope": "Actual commands, holders, save/load and static original TerrainArmy sprites; not battle/FPS"}, "\t"))
	file.close()
	print("WESTERN IRON ARMY ATLAS PASS: 39 recipes / ", catalog.recipes.size() * samples_per_recipe, " samples; ", created, " actual equips; save/load; ", checked, " actual sprite states; iron != steel")
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)

func _iron_capture(lab: TerrainLab, label: String, location: Vector2, zoom_value: float) -> void:
	title.text = "WESTERN IRON | " + label + " | original TerrainArmy atlas sprite"
	lab.camera.position = location
	lab.camera.zoom = Vector2.ONE * zoom_value
	lab.camera.reset_smoothing()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(IRON_OUTPUT + "/" + label + ".png") == OK)
