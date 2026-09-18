extends "res://scripts/tests/site_vehicle_route_review_test.gd"
## Headless owner/atlas contract; optional GPU main-scene captures and frozen
## Sprite/MultiMesh RGBA comparison. Neither mode measures performance.
const Rider = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
const Recipe = preload("res://scripts/terrain_lab/site_wagon_rider_recipe.gd")
const VISUAL_OUT := "res://output/site_wagon_rider_display_20260918/batch_visual"

func _gear_bytes(lab: TerrainLab, team: TerrainArmy) -> PackedByteArray:
	var people := []
	for index in range(team.combat_units.size()):
		var body: Dictionary = team.combat_units[index]
		var items := {}
		for identity: String in body.item_state.item_ids:
			items[identity] = lab.terrain.site.item_records[identity]
		people.append([body.appearance, team.equipment_appearance(index), body.item_state, body.cargo, items])
	return var_to_bytes(people)

func _capture_batch_scene(lab: TerrainLab, name: String) -> Image:
	for team: TerrainArmy in lab.combat_armies: team.advance_frame(0.0)
	lab.site_controller.vehicle_view.refresh()
	# Settle the original captain's transparent viewport without moving people.
	for frame in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(picture.save_png(VISUAL_OUT + "/" + name + ".png") == OK)
	return picture

func _run() -> void:
	var visual := DisplayServer.get_name() != "headless"
	if visual:
		deadline = Time.get_ticks_msec() + 70000
		assert(DirAccess.make_dir_recursive_absolute(VISUAL_OUT) == OK)
		root.size = Vector2i(1800, 1100)
		root.content_scale_size = root.size
		root.gui_embed_subwindows = true
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	var origin := _patch(lab)
	assert(origin != TerrainArmy.INVALID_CELL)
	if visual:
		lab.site_controller.combat_window.hide()
		lab.camera.zoom = Vector2.ONE * 1.35
		lab.camera.position = (Vector2(origin) + Vector2(5, 5)) * TerrainRenderer.CELL_PIXELS + Vector2(250, 120) / 1.35
		lab.camera.force_update_scroll()
	var team := lab.army
	team.team_id = lab._next_army_identity()
	team.role = "logistics"
	team.roster_size = 64
	var riding_cell := origin + Vector2i(6, 5)
	var formation: Array[Vector2i] = [origin, riding_cell]
	var spare := [riding_cell - Vector2i.RIGHT * 2, riding_cell - Vector2i.RIGHT, riding_cell + Vector2i.UP, riding_cell + Vector2i.RIGHT, riding_cell + Vector2i.DOWN]
	for y in range(10):
		for x in range(10):
			var cell := origin + Vector2i(x, y)
			if not formation.has(cell) and not spare.has(cell) and formation.size() < 64: formation.append(cell)
	assert(formation.size() == 64)
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, formation) and team.enable_combat(false, 32))
	var original_source_count := team.active_3d_source_count()
	var original_presenters := team._live_presenters.duplicate()
	var female_count := 0
	var dyed_people := 0
	for index in range(team.combat_units.size()):
		var kit := team.equipment_appearance(index)
		assert(not Recipe.matches(kit), "Logistics membership must not replace the original soldier equipment with display-only cloth")
		assert(kit.parts.armor == "armor_light_leather_01" and kit.parts.weapon == "longsword_01" and kit.parts.shield == "shield_heater_01")
		assert(kit == SiteRuntime.equipment_appearance(lab.terrain, team.combat_units[index].item_state, team.combat_units[index].appearance))
		dyed_people += int(not kit.get("equipment_dyes", {}).is_empty())
		female_count += int(kit.body == 1)
	assert(female_count == 32 and dyed_people > 0, "Both original bodies and real team equipment dyes are exercised")
	var original_gear := _gear_bytes(lab, team)
	var transport = lab.site_controller.vehicles
	var identity := team.combat_identity(1)
	var appearance := team.equipment_appearance(1)
	assert(Rider.supports(appearance) and not Recipe.matches(appearance) and int(appearance.body) == 0)
	# Actual original gear is only an input; the mounted image is fixed by sex.
	assert(Rider.supports(Rider.EquipmentAtlas.female_appearance()))
	var before := appearance.duplicate(true)
	assert(not Rider.supports({}) and Rider.frame({}, "down", false, 0.0).is_empty())
	var unsupported := appearance.duplicate(true)
	unsupported.parts.weapon = "not_a_real_weapon"
	var unsupported_before := unsupported.duplicate(true)
	assert(not Rider.supports(unsupported) and Rider.frame(unsupported, "down", false, 0.0).is_empty())
	assert(unsupported == unsupported_before and appearance == before, "Rejected appearance reads must not replace original equipment")
	var dyed := appearance.duplicate(true)
	dyed.equipment_dyes = {"armor": "ab4545ff", "outfit": "2b579aff", "boots": "847652ff"}
	var dyed_before := dyed.duplicate(true)
	assert(not Recipe.matches(dyed) and Rider.supports(dyed))
	var fixed_male := Rider.frame(Recipe.appearance(0), "right", false, 0.0)
	assert(is_same(Rider.frame(dyed, "right", false, 0.0).texture, fixed_male.texture))
	assert(dyed == dyed_before, "Ignoring dyes for mounted presentation must not erase actual equipment colors")
	var frame_keys := {}
	for body: Dictionary in [Recipe.appearance(0), Recipe.appearance(1)]:
		assert(Rider.supports(body))
		for direction: String in ["down", "left", "up", "right"]:
			var idle_frame := Rider.frame(body, direction, false, 0.0)
			assert(not idle_frame.is_empty())
			frame_keys[idle_frame.key] = true
			for index in range(8):
				var moving_frame := Rider.frame(body, direction, true, float(index) / 8.0)
				assert(not moving_frame.is_empty() and int(moving_frame.frame) == index)
				frame_keys[moving_frame.key] = true
	assert(frame_keys.size() == 72, "Two cloth bodies each expose four directions of idle plus eight moving frames")
	assert(transport.deploy_plan(team, [{"kind": "wagon", "team_id": team.team_id,
		"cell": lab.terrain.index(Vehicles.anchor_from_operator("wagon", riding_cell, Vector2i.RIGHT)), "facing": [1, 0], "operator_index": 1}]).ok)
	assert(_gear_bytes(lab, team) == original_gear, "Boarding cannot rewrite any person's original equipment, dyes, item versions or cargo")
	var wagon: Dictionary = transport.records().values()[0]
	var body: Dictionary = team.combat_units[1]
	var original_holder: Dictionary = body.item_state
	var original_cargo: Dictionary = body.cargo
	var original_role: String = body.visual_role
	# Headless intentionally skips editor/visual startup. Enable only the same
	# original published atlas reader and existing Army Sprite/Batch projection.
	team._soldier_baked_ready = team._load_baked_soldier()
	assert(team._soldier_baked_ready and team._batch_render_active())
	team._rebuild_visual_instances()
	team._visual_dirty = true
	team.advance_frame(0.0)
	var sprite: Sprite2D = team._sprites[1]
	assert(sprite != null and sprite.has_meta("vehicle_rider_frame"))
	assert(sprite.get_meta("vehicle_rider_frame") == "0/ride_idle/right/0")
	assert(team._batch_view._native_mask[1] == 0 and team._batch_view._page[1] == -1)
	assert(team._batch_view.rendered_count == 62, "All 62 ordinary on-foot people keep their original equipment batch beside the captain and cloth rider")
	assert(is_same(team._batch_view._original_sprites[1], sprite), "The ordinary non-captain rider must occur only on its original Sprite")
	var state: Dictionary = transport.rider_state(identity)
	var frame := Rider.frame(appearance, "right", false, 0.0)
	assert(is_same(frame.texture, fixed_male.texture) and is_same(sprite.texture, fixed_male.texture), "Original armed rider must display the fixed cloth texture, not the original leather atlas")
	assert(sprite.position.is_equal_approx(Vector2(state.position) + Vector2(frame.horse_offset) - Vector2(frame.anchor)))
	var original_texture := sprite.texture
	var original_material := sprite.material
	var original_scale := sprite.scale
	assert(Rider.apply(sprite, dyed, frame), "Real equipment dyes remain legal but must not tint the fixed mounted display")
	assert(is_same(sprite.texture, original_texture) and is_same(sprite.material, original_material) and sprite.scale == original_scale and sprite.get_meta("vehicle_rider_frame") == frame.key)
	assert(Rider.apply(sprite, appearance, frame))
	assert(sprite.material == null, "Fixed mounted cloth must not inherit the original equipment's dye shader")
	assert(dyed == dyed_before and _gear_bytes(lab, team) == original_gear)
	assert(team.active_3d_source_count() == original_source_count and team._live_presenters == original_presenters and not team._live_presenters.has(identity), "The ordinary rider cannot add or replace any original live 3D source")
	if not visual: assert(original_source_count == 0 and team._live_presenters.is_empty())
	assert(is_same(body, team.combat_units[1]) and is_same(body.item_state, original_holder) and is_same(body.cargo, original_cargo) and body.visual_role == original_role)
	if visual: await _capture_batch_scene(lab, "mounted")
	assert(transport.unassign_operator(str(wagon.id), identity, true).ok)
	assert(wagon.move.get("dismount", false) and transport.rider_state(identity).is_empty())
	team._visual_dirty = true
	team.advance_frame(0.0)
	assert(team._sprites[1] == null or not team._sprites[1].has_meta("vehicle_rider_frame"), "Original walking body returns as soon as the real dismount starts")
	for tick in range(25): team.prepare_combat(1.0 / 30.0)
	assert(int(wagon.operator_id) == 0 and team.cells[1] != riding_cell and team.moving_to[1] == TerrainArmy.INVALID_CELL)
	team._visual_dirty = true
	team.advance_frame(0.0)
	assert(team._batch_view._page[1] >= 0 and not team._batch_view._original_sprites.has(1), "Dismounted ordinary soldier returns to the original atlas batch, not a stale rider Sprite")
	assert(team._batch_view.rendered_count == 63, "All 63 ordinary people must return to their original equipment batch")
	assert(is_same(body.item_state, original_holder) and is_same(body.cargo, original_cargo) and body.visual_role == original_role and team.combat_units.size() == 64)
	assert(_gear_bytes(lab, team) == original_gear, "Dismount preserves exactly the original male/female gear and colors")
	if visual:
		var owner_before := var_to_bytes([team.combat_units, team.cells, team.moving_to, team.move_progress, team.move_duration, team.facing, team._reserved_cells, team._cell_owners, team.command_rng.state, transport.records()])
		var batched := await _capture_batch_scene(lab, "dismounted")
		# Reuse the Army's existing original-Sprite reference switch. All inputs,
		# camera, people, equipment, vehicles, time and UI remain the same.
		team.batch_render_enabled = false
		team._rebuild_visual_instances()
		team._visual_dirty = true
		team.advance_frame(0.0)
		assert(team._batch_view == null and not team._batch_render_active())
		var reference := await _capture_batch_scene(lab, "dismounted_sprites")
		assert(owner_before == var_to_bytes([team.combat_units, team.cells, team.moving_to, team.move_progress, team.move_duration, team.facing, team._reserved_cells, team._cell_owners, team.command_rng.state, transport.records()]), "Presentation comparison cannot mutate original simulation owners")
		if batched.get_data() != reference.get_data():
			push_error("Original-equipment main-scene batch/Sprite full RGBA mismatch; compare dismounted.png and dismounted_sprites.png")
			quit(1)
			return
		print("SITE VEHICLE RIDER BATCH GPU PASS: actual 1800x1100 mounted/dismounted main scenes, 62/63 foot batch people, frozen Sprite/MultiMesh complete RGBA equal; no FPS claim")
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE VEHICLE RIDER BATCH PASS: 64 original equipped people (32 women), one display-only fixed-cloth rider, unchanged real gear/dyes/items, native batch exclusion, exact horse anchor, both display bodies/four directions/72 frames, original foot batch restored after dismount; GPU comparison=" + str(visual))
	quit(0)
