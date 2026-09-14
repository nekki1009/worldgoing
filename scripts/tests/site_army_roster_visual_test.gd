extends "res://scripts/tests/site_army_roster_test.gd"

const OUTPUT := "res://.visual_captures/site_army_roster"

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	root.size = Vector2i(1200, 800)
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "roster-visual-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	var first := make_team(data, 1, Vector2i(40, 40))
	var second := make_team(data, 2, Vector2i(60, 40))
	# Fixture setup puts the two original women and one ordinary man in view.
	# The following real roster operations must preserve these positions.
	set_fixture_cell(first, 0, Vector2i(20, 20))
	set_fixture_cell(first, 1, Vector2i(22, 23))
	set_fixture_cell(second, 0, Vector2i(24, 20))
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.position = (Vector2(22, 21) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	camera.zoom = Vector2.ONE * 4.0
	for army: TerrainArmy in [first, second]:
		army.command_radius = 100.0 # Fixture command presence includes the distant data rows.
		army._command_dirty = true
		army.settle_combat_command()
		army._ensure_live_presenters()
		army.advance_frame(0.0)
	assert(first.active_3d_source_count() == 1 and second.active_3d_source_count() == 1)
	var first_id := first.combat_identity(0)
	var second_id := second.combat_identity(0)
	var male_id := first.combat_identity(1)
	var first_editor: Variant = first._unit_editor(0)
	var second_editor: Variant = second._unit_editor(0)
	var first_appearance: Dictionary = first_editor.capture_appearance()
	var second_appearance: Dictionary = second_editor.capture_appearance()
	assert(first_editor.combat_ready and second_editor.combat_ready)
	assert(first_editor.is_selected_shield_held() and second_editor.is_selected_shield_held(), "Both original women must display their actual held shield before any geometry query")
	first._sprites[0].modulate = Color.WHITE
	second._sprites[0].modulate = Color.WHITE
	await capture_roster("01_before.png")
	assert(second.merge_into(first, second.current_commander, first.current_commander).ok)
	assert(first.active_3d_source_count() == 2 and second.active_3d_source_count() == 0)
	assert(first._unit_editor(first.index_for_identity(first_id)) == first_editor)
	assert(first._unit_editor(first.index_for_identity(second_id)) == second_editor)
	assert(first_editor._body_index == 1 and second_editor._body_index == 1)
	assert(first.cells[first.index_for_identity(first_id)] == Vector2i(20, 20))
	assert(first.cells[first.index_for_identity(second_id)] == Vector2i(24, 20))
	var split := TerrainArmy.new()
	root.add_child(split)
	split.set_process(false)
	split.team_id = 3
	assert(first.split_members_to(split, [male_id], first.current_commander).ok)
	assert(split.roster_size == 1 and not split._uses_live_presenter(0))
	assert(split.active_3d_source_count() == 0 and split._sprites.size() == 1)
	for army: TerrainArmy in [first, split]:
		army.advance_frame(0.0)
	assert(first.active_3d_source_count() + split.active_3d_source_count() == 2, "No extra rigs from male split / female merge")
	assert(first_editor.combat_ready and second_editor.combat_ready)
	assert(first_editor.is_selected_shield_held() and second_editor.is_selected_shield_held(), "Roster order may not change held equipment visibility")
	assert(first_editor.capture_appearance() == first_appearance and second_editor.capture_appearance() == second_appearance)
	first._sprites[first.index_for_identity(first_id)].modulate = Color.WHITE
	first._sprites[first.index_for_identity(second_id)].modulate = Color.WHITE
	split._sprites[0].modulate = Color.WHITE
	# Capture first: a geometry query must not silently repair the presentation.
	await capture_roster("02_merged_and_split.png")
	assert(first.combat_shapes(first.index_for_identity(first_id), "body").size() > 0)
	assert(first.combat_shapes(first.index_for_identity(second_id), "body").size() > 0)
	assert(split.combat_shapes(0, "body").size() > 0)
	assert(first.combat_shapes(first.index_for_identity(first_id), "shield").size() > 0)
	assert(first.combat_shapes(first.index_for_identity(second_id), "shield").size() > 0)
	for army: TerrainArmy in [first, second, split]:
		army.free()
	camera.free()
	TerrainArmy.release_contact_source()
	print("SITE_ARMY_ROSTER_VISUAL_PASS: same two original female presenters, no added male rig, original cells, 1-person split, actual geometry")
	quit(0)

func set_fixture_cell(army: TerrainArmy, index: int, cell: Vector2i) -> void:
	army._cell_owners.erase(army.cells[index])
	army.cells[index] = cell
	army.desired_cells[index] = cell
	army.combat_slots[index] = cell
	army._cell_owners[cell] = index
	army._visual_dirty = true

func capture_roster(filename: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	assert(root.get_texture().get_image().save_png(OUTPUT.path_join(filename)) == OK)
