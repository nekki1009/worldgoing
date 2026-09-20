extends SceneTree

const Contract = preload("res://scripts/ui/character_render_contract.gd")
const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("=== RUNNING SCHEME C VIEWPORT DECOUPLING TEST ===")
	# 1. Contract verification
	assert(Contract.PREVIEW_VIEWPORT_SIZE == Vector2i(1280, 1536), "PREVIEW_VIEWPORT_SIZE constant intact")
	assert(Contract.EDITOR_VIEWPORT_SIZE == Vector2i(1280, 1536), "EDITOR_VIEWPORT_SIZE constant defined")
	assert(Contract.MAP_VIEWPORT_SIZE == Vector2i(256, 307), "MAP_VIEWPORT_SIZE constant defined as 256x307")

	var high_res_scale: float = Contract.sprite_scale(Contract.PREVIEW_VIEWPORT_SIZE, 7.856338)
	var low_res_scale: float = Contract.sprite_scale(Contract.MAP_VIEWPORT_SIZE, 7.856338)
	var high_res_height: float = float(Contract.PREVIEW_VIEWPORT_SIZE.y) * high_res_scale
	var low_res_height: float = float(Contract.MAP_VIEWPORT_SIZE.y) * low_res_scale
	print("Scale check: High-res height = %f, Low-res height = %f, diff = %f" % [high_res_height, low_res_height, absf(high_res_height - low_res_height)])
	assert(absf(high_res_height - low_res_height) < 0.2, "Map height mathematically invariant across resolutions")

	# 2. HumanCharacter3DEditor dynamic viewport methods
	var editor := HumanCharacter3DEditor.new()
	root.add_child(editor)
	editor.open()
	assert(editor.preview_viewport.size == Contract.PREVIEW_VIEWPORT_SIZE, "Editor opens with full high-res viewport by default")

	editor.preview_viewport.size = Contract.MAP_VIEWPORT_SIZE
	assert(editor.preview_viewport.size == Contract.MAP_VIEWPORT_SIZE, "preview_viewport switches to 256x307")
	assert(is_equal_approx(editor.get_map_sprite_scale(), low_res_scale), "Editor sprite scale matches low_res_scale")

	editor.preview_viewport.size = Contract.PREVIEW_VIEWPORT_SIZE
	assert(editor.preview_viewport.size == Contract.PREVIEW_VIEWPORT_SIZE, "preview_viewport switches to 1280x1536")
	assert(is_equal_approx(editor.get_map_sprite_scale(), high_res_scale), "Editor sprite scale matches high_res_scale")
	editor.queue_free()

	# 3. TerrainTestCharacter lifecycle
	var character := TerrainTestCharacter.new()
	root.add_child(character)
	character.initialize_visual()
	assert(character.editor.preview_viewport.size == Contract.MAP_VIEWPORT_SIZE, "Character map presenter initializes at 256x307")
	assert(is_equal_approx(character.player_sprite.scale.x, low_res_scale), "Character player_sprite.scale matches low_res_scale")

	# Open editor
	character.open_editor()
	assert(character.editor_window.visible, "Editor window opened")
	assert(character.editor.preview_viewport.size == Contract.PREVIEW_VIEWPORT_SIZE, "Editor viewport resized to 1280x1536 on open")
	assert(character.editor.preview_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Editor viewport is UPDATE_ALWAYS on open")

	# Close editor
	character._close_editor()
	assert(not character.editor_window.visible, "Editor window closed")
	assert(character.editor.preview_viewport.size == Contract.MAP_VIEWPORT_SIZE, "Viewport returned to 256x307 on close")
	assert(is_equal_approx(character.player_sprite.scale.x, low_res_scale), "Character player_sprite.scale restored to low_res_scale on close")

	# 4. Projection invariance check
	var collision := Collision.new()
	var test_point := Vector3(0.5, 1.2, -0.3)
	character.editor.preview_viewport.size = Contract.PREVIEW_VIEWPORT_SIZE
	character._sync_render_projection()
	var projected_high: Vector2 = collision.project(character, test_point)

	character.editor.preview_viewport.size = Contract.MAP_VIEWPORT_SIZE
	character._sync_render_projection()
	var projected_low: Vector2 = collision.project(character, test_point)
	var proj_diff := projected_high.distance_to(projected_low)
	print("Projection invariance: High = %s, Low = %s, distance diff = %f px" % [projected_high, projected_low, proj_diff])
	assert(proj_diff < 0.5, "Collision project() produces identical world coordinates regardless of viewport size")

	character.queue_free()

	# 5. TerrainArmy Captain presenter
	var army := TerrainArmy.new()
	root.add_child(army)
	var captain_source: HumanCharacter3DEditor = army._create_visual_source(1, "ArmyCaptainVisualSource")
	assert(captain_source.preview_viewport.size == Contract.MAP_VIEWPORT_SIZE, "Captain visual source created with MAP_VIEWPORT_SIZE")
	assert(is_equal_approx(captain_source.get_map_sprite_scale(), low_res_scale), "Captain scale is low_res_scale")
	army.queue_free()

	print("=== SCHEME C VIEWPORT DECOUPLING TEST: ALL CHECKS PASSED ===")
	quit(0)
