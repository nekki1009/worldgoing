extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(1))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 64)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -25, 0)
	light.light_energy = 2.0
	viewport.add_child(light)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file(HumanCharacter3DEditor.COMBAT_PROPS_PATH, state) == OK)
	var props := document.generate_scene(state) as Node3D
	viewport.add_child(props)
	for name in ["Arrow", "Bolt"]:
		for node in props.get_children():
			(node as Node3D).visible = str(node.name) == name
		var missile := props.get_node(name) as Node3D
		missile.rotation.y = PI / 2.0
		var centre := Vector3(.39 if name == "Arrow" else .195, 0, 0)
		camera.size = 0.25 if name == "Arrow" else 0.14
		camera.position = centre + Vector3(0, 1.5, 0)
		camera.look_at(centre, Vector3.FORWARD)
		await process_frame
		await RenderingServer.frame_post_draw
		var rendered := viewport.get_texture().get_image()
		var bounds := rendered.get_used_rect()
		assert(bounds.has_area())
		var texture := rendered.get_region(bounds)
		var path: String = "res://assets/characters/human/q35/combat/" + str(name).to_lower()
		assert(texture.save_png(path + ".png") == OK)
		assert(ResourceSaver.save(ImageTexture.create_from_image(texture), path + ".res") == OK)
	viewport.queue_free()
	await process_frame
	print("SITE_COMBAT_PROJECTILE_BAKE_PASS")
	quit(0)
