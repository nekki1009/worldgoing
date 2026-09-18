extends SceneTree
const Atlas = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
const OUT := "res://output/site_wagon_rider_display_20260918/visual/"
var _started := Time.get_ticks_msec()

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started > 20000:
		push_error("Rider composition capture deadline")
		quit(1)
	return false

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var vehicle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vehicles/logistics/v1/vehicles_atlas.json"))
	var vehicle_texture: Texture2D = load("res://assets/vehicles/logistics/v1/vehicles_atlas.res")
	var appearance: Array[Dictionary] = [JSON.parse_string(FileAccess.get_file_as_string(Atlas.EquipmentAtlas.BASE_MANIFEST)).appearance, Atlas.EquipmentAtlas.female_appearance()]
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2560, 960)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("52654c")
	background.size = Vector2(viewport.size)
	viewport.add_child(background)
	for moving: bool in [false, true]:
		var board := Node2D.new()
		board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		viewport.add_child(board)
		for body in range(2):
			for index in range(4):
				var direction: String = ["down", "left", "up", "right"][index]
				var panel := Node2D.new()
				panel.position = Vector2(320 + index * 640, 385 + body * 470)
				panel.scale = Vector2.ONE * 2.8
				board.add_child(panel)
				var label := Label.new()
				label.text = ("MALE" if body == 0 else "FEMALE") + " / " + direction + (" / MOVE 3" if moving else " / IDLE")
				label.position = Vector2(32 + index * 640, 22 + body * 470)
				label.add_theme_font_size_override("font_size", 26)
				board.add_child(label)
				var source := {}
				for item: Dictionary in vehicle.frames:
					if item.kind == "wagon" and item.direction == direction and item.clip == ("move" if moving else "idle") and int(item.frame) == (3 if moving else 0): source = item
				assert(not source.is_empty())
				var cart := Sprite2D.new()
				cart.texture = vehicle_texture
				cart.region_enabled = true
				cart.region_rect = Rect2(source.rect[0], source.rect[1], source.rect[2], source.rect[3])
				cart.centered = false
				cart.offset = -Vector2(source.anchor[0], source.anchor[1])
				cart.scale = Vector2.ONE * float(vehicle.map_scale)
				panel.add_child(cart)
				var rider := Sprite2D.new()
				panel.add_child(rider)
				var look: Dictionary = appearance[body].duplicate(true)
				# Deliberately armed/dyed inputs: only their sex selects the fixed
				# display. This composition never edits any real holder or person.
				look.equipment_dyes = {"armor": "2b579aff", "outfit": "847652ff"} if body == 1 else {"armor": "ab4545ff"}
				var original := look.duplicate(true)
				assert(not Atlas.ClothRecipe.matches(look) and look.parts.weapon == "longsword_01")
				var frame := Atlas.frame(look, direction, moving, 3.0 / 8.0)
				var fixed := Atlas.frame(Atlas.ClothRecipe.appearance(body), direction, moving, 3.0 / 8.0)
				assert(Atlas.apply(rider, look, frame))
				assert(look == original and is_same(rider.texture, fixed.texture) and rider.material == null, "Mounted cloth display must ignore original equipment/dyes without rewriting them")
				rider.position = Vector2(frame.horse_offset) - Vector2(frame.anchor)
				var vehicle_bounds := Rect2(cart.offset * cart.scale, Vector2(source.rect[2], source.rect[3]) * cart.scale)
				var rider_size := Vector2(rider.texture.get_size()) * rider.scale
				var bounds := vehicle_bounds.merge(Rect2(rider.position - rider_size * 0.5, rider_size))
				assert(bounds.size.x * panel.scale.x < 608.0, "Complete horse and wagon must fit the inspection panel")
				panel.position.x -= bounds.get_center().x * panel.scale.x
		await process_frame
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().save_png(OUT + ("mounted_move_four_views.png" if moving else "mounted_idle_four_views.png")) == OK)
		board.queue_free()
		await process_frame
	print("LOGISTICS RIDER COMPOSITION PASS: original wagon + display-only fixed male/female cloth, all four views, original armed/dyed inputs unchanged; isolated composition, not main-scene or item-owner evidence")
	quit(0)
