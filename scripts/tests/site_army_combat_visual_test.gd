extends SceneTree

const OUTPUT := "res://.visual_captures/site_army_combat"

class ProfiledLab extends TerrainLab:
	var army_contact_us := 0
	var all_contact_us := 0
	var contact_queries := 0
	func _collect_army_contacts(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], source_cell: Vector2i, source_position: Vector2, source: Variant, source_unit: int, ranged: bool = false, prepared: Array = []) -> Array[Dictionary]:
		var started := Time.get_ticks_usec()
		var hits := super._collect_army_contacts(previous, current, source_cell, source_position, source, source_unit, ranged, prepared)
		army_contact_us += Time.get_ticks_usec() - started
		return hits
	func _collect_unit_contacts(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], source_cell: Vector2i, source_position: Vector2, source: Variant, source_unit: int) -> Array[Dictionary]:
		var started := Time.get_ticks_usec()
		var hits := super._collect_unit_contacts(previous, current, source_cell, source_position, source, source_unit)
		all_contact_us += Time.get_ticks_usec() - started
		contact_queries += 1
		return hits

func _initialize() -> void:
	stage("script initialized")
	call_deferred("run")

func stage(label: String) -> void:
	print("ARMY VISUAL STAGE ", Time.get_ticks_msec(), "ms: ", label)

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	root.size = Vector2i(1400, 900)
	stage("construct full TerrainLab")
	var lab := ProfiledLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	stage("TerrainLab ready")
	assert(lab.character.editor._body_index == 0 and lab.npc.editor._body_index == 1)
	current_scene = lab
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "army-visual-fixture")
	data.resource_base.clear()
	data.resources_at.clear()
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	stage("fixture terrain bound")
	lab.character.place(Vector2i(50, 50), true)
	lab.npc.place(Vector2i(52, 50), true)
	assert(TerrainArmy.load_combat_bake())
	stage("collision bake loaded")
	# The same idempotent initializers used by deployment, split here only to
	# distinguish asset loading from deployment and real contact sampling.
	for team: TerrainArmy in lab.combat_armies:
		team.initialize_visual()
		assert(team._captain_editor._body_index == 1)
		stage("visual ready: " + team.name)
	var result := lab.start_melee_trial()
	stage("bake loaded and two armies deployed")
	assert(result.ok, str(result))
	assert(TerrainArmy._contact_source.editor.preview_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	lab.get_node("SiteUI").hide()
	lab.get_node("TerrainLabUI").hide()
	lab.camera.zoom = Vector2.ONE * 0.85
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
		assert(team.active_3d_source_count() == 1 and team.visual_mode() == "baked_atlas")
		assert(team._sprites.size() == 100, "Preserve the existing presenter; no per-soldier 3D rig")
		team.advance_frame(0.0)
		assert(team.combat_frame(1).clip == "combat_idle" and team.combat_units[1].pose == "idle")
		assert(team.captain_animation_id() == &"idle" and team._captain_editor.combat_ready)
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor._update_combat_ready()
		assert(actor.combat_ready and actor.editor.combat_ready and not actor.guarding)
	await capture("01_deployed.png")
	for tick in range(180):
		lab._advance_combat(1.0 / 120.0)
		if tick % 30 == 0:
			stage("combat tick %d; queries=%d army=%dus live=%dus" % [tick, lab.contact_queries, lab.army_contact_us, lab.all_contact_us - lab.army_contact_us])
	stage("combat complete; queries=%d army=%dus live=%dus" % [lab.contact_queries, lab.army_contact_us, lab.all_contact_us - lab.army_contact_us])
	for team: TerrainArmy in lab.combat_armies:
		team.advance_frame(0.0)
		var frame := team.combat_frame(1)
		assert(team._soldier_current_keys[1] == "%s|%s|%d" % [frame.clip, frame.direction, int(frame.frame)], "Presentation must select the tile containing the current continuous time")
		assert(team._sprites[1].position.is_equal_approx(team.combat_ground(1) + team.combat_offset(1) - team._soldier_sprite_anchors[1]))
		assert(team.captain_animation_id() == &"walk_slash", "Live captain uses the combat pose too")
	await capture("02_contact.png")
	var contacts := 0
	for team: TerrainArmy in lab.combat_armies:
		for unit: Dictionary in team.combat_units:
			contacts += unit.hits.size()
	assert(contacts > 0, "Rendered army combat must generate actual contacts")
	for team: TerrainArmy in lab.combat_armies:
		assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	var down := {"result": {"hp": 7.5, "stun": 110.0, "guard_break": false}, "shield": false}
	lab.army.apply_unit_contact(1, down)
	lab.army.apply_unit_contact(0, down)
	lab.army.combat_attacking = false
	lab.opposing_army.combat_attacking = false
	for team: TerrainArmy in lab.combat_armies:
		team.prepare_combat(3.0)
		team.settle_combat_command()
		team.advance_frame(0.0)
	assert(not lab.army.blocks_cell(lab.army.cells[1]))
	assert(lab.army.captain_animation_id() == &"unconscious")
	await capture("03_down.png")
	lab.character.place(lab.army.cells[0] + Vector2i.UP, true)
	assert(lab.join_player_army().ok and lab.army.player_member == lab.character)
	assert(lab.army.combat_units.size() == 100 and lab.army._sprites.size() == 100, "Joining adds no substitute player soldier")
	lab.camera.position = lab.character.position + Vector2(0, 80)
	lab.camera.zoom = Vector2.ONE * 2.5
	await capture("04_member_and_down_close.png")
	print("SITE ARMY COMBAT VISUAL PASS: 200 displayed units / 2 captain rigs plus 1 shared non-rendering contact rig, continuous contact and presentation anchor, live and baked down poses; contacts=", contacts)
	lab.clear_army()
	lab.queue_free()
	await process_frame
	await process_frame
	quit(0)

func capture(filename: String) -> void:
	stage("wait for draw: " + filename)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	assert(root.get_texture().get_image().save_png(OUTPUT + "/" + filename) == OK)
	stage("saved: " + filename)
