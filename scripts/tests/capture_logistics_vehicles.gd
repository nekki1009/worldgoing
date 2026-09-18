extends SceneTree

## Asset inspection boards, not a substitute for the actual main-scene test.
const OUT := "res://output/logistics_vehicles_v1/visual/"
const ASSETS := "res://assets/vehicles/logistics/v1/"

class Board extends Node2D:
	var atlas: Texture2D
	var manifest: Dictionary
	var kind := "cart"
	var native_scale := false
	var soldier_texture: Texture2D
	var soldier_manifest: Dictionary
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 2048, 1120), Color("27333a"))
		var directions := ["down", "left", "up", "right"]
		for index in range(4):
			var origin := Vector2(24 + (index % 2) * 1024, 80 + floori(float(index) / 2.0) * 510)
			var foot := origin + Vector2(500, 370)
			draw_string(ThemeDB.fallback_font, origin, "%s / %s / %s" % [kind, directions[index], "MAP 1:1" if native_scale else "SOURCE DETAIL"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
			if native_scale:
				for x in range(0, 15):
					for y in range(0, 6):
						draw_rect(Rect2(origin + Vector2(x*64, y*64+24), Vector2(64,64)), Color("52654c") if (x+y)%2 == 0 else Color("4c5d47"))
			for frame: Dictionary in manifest.frames:
				if frame.kind != kind or frame.clip != "idle" or frame.direction != directions[index]: continue
				var size := Vector2(float(frame.rect[2]), float(frame.rect[3]))
				var scale_value := float(manifest.map_scale) if native_scale else minf(0.90, 920.0 / size.x)
				var anchor := Vector2(float(frame.anchor[0]), float(frame.anchor[1]))
				if not native_scale: foot.x = origin.x + 490 - (size.x * 0.5 - anchor.x) * scale_value
				draw_texture_rect_region(atlas, Rect2(foot-anchor*scale_value, size*scale_value), Rect2(float(frame.rect[0]), float(frame.rect[1]), size.x, size.y))
			if native_scale:
				for frame: Dictionary in soldier_manifest.frames:
					if frame.clip != "idle" or frame.direction != directions[index] or int(frame.frame) != 0: continue
					var size := Vector2(float(frame.rect.w), float(frame.rect.h))
					var anchor := size*0.5 + Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y))
					var scale_value := float(soldier_manifest.map_scale)
					draw_texture_rect_region(soldier_texture, Rect2(foot+Vector2(200,0)-anchor*scale_value,size*scale_value), Rect2(float(frame.rect.x),float(frame.rect.y),size.x,size.y))
				draw_circle(foot, 2.5, Color("f5d278"))
		draw_string(ThemeDB.fallback_font, Vector2(24, 1090), "Ground anchor = chassis centre | 37.1284 map pixels/metre | Horse source unchanged", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("b9c9d4"))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2048, 1120)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var board := Board.new()
	board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	board.atlas = load(ASSETS + "vehicles_atlas.res")
	board.manifest = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "vehicles_atlas.json"))
	board.soldier_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"))
	board.soldier_texture = load(str(board.soldier_manifest.atlas.resource_path))
	viewport.add_child(board)
	for kind: String in ["cart", "wagon"]:
		for native: bool in [false, true]:
			board.kind = kind
			board.native_scale = native
			board.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			assert(viewport.get_texture().get_image().save_png(OUT + kind + ("_map_scale.png" if native else "_four_views.png")) == OK)
	print("LOGISTICS VEHICLE BOARDS PASS art=2 native_scale=2")
	quit(0)
