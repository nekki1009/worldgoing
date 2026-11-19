extends SceneTree
## Temporary GPU approval preview; reads output PNGs, publishes no formal art.
const Ships = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const PeopleAtlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const OUT := "res://output/site_ship_close_20261004/proportion_v4_tower_preview"
const REGIONS := "res://output/site_ship_close_20261004/preview_regions_v4_tower.json"
const REFERENCES := "res://output/site_ship_close_20261004/ship_reference_metadata_v4_tower.json"
const CELL_PIXELS := 18.0
const CANVAS_SIZE := Vector2i(2480, 4580)
var deadline := 0
var run_completed := false

class Board extends Node2D:
	var frames: Array[Dictionary] = []
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(2480, 4580)), Color("122c39"))
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(24, 28), "TEMPORARY SHIP ART / ORIGINAL PERSON SPRITES / 2 metres per cell", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color.WHITE)
		draw_string(font, Vector2(24, 52), "V4 tower / unchanged v3 fleet whole-hull reference / 18 px per physical cell / original people and positions / cyan = original claims, orange = full PNG including exterior oars. NEW IMAGE APPROVAL PENDING.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("cae4ee"))
		for frame: Dictionary in frames:
			var panel: Rect2 = frame.panel
			draw_rect(panel, Color("1c3b49"))
			draw_rect(panel, Color("3a6478"), false, 1.0)
			draw_texture_rect(frame.texture, frame.image_rect, false)
			draw_rect(frame.image_rect, Color(1.0, 0.65, 0.2, 0.4), false, 0.6)
			for cell: Vector2i in frame.cells:
				var position: Vector2 = frame.origin + (Vector2(cell) - Vector2.ONE * 0.5) * 18.0
				draw_rect(Rect2(position, Vector2.ONE * 18.0), Color(0.2, 0.85, 0.98, 0.4), false, 0.6)
			var kind_label: String = str(frame.kind) + (" (raised tower)" if str(frame.kind) == "tower" else "")
			draw_string(font, panel.position + Vector2(12, 22), "%s / %s / %d x %d m / %d people" % [kind_label, frame.direction, int(frame.width) * 2, int(frame.length) * 2, int(frame.people)], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
			if str(frame.kind) == "tower": draw_string(font, panel.position + Vector2(12, 44), "高架望塔候選；遮擋待畫面驗收", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("cae4ee"))
			var point: Vector2 = panel.position + Vector2(panel.size.x - 35, 35)
			var facing: Vector2 = frame.facing
			draw_line(point, point + facing * 20.0, Color("f0d488"), 2.0)
			draw_circle(point + facing * 20.0, 3.0, Color("f0d488"))

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not run_completed and Time.get_ticks_msec() > deadline:
		push_error("SHIP ART PROPORTION preview did not complete")
		quit(1)
	return false

func _require(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SHIP_ART_PREVIEW_FAIL: " + message)
	quit(1)
	return false

func _run() -> void:
	if not _require(DisplayServer.get_name() != "headless", "This preview requires a GPU viewport"): return
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGIONS))
	if not _require(document is Dictionary and document.get("version") == 1 and document.get("ships") is Dictionary, "Missing original PNG region metadata"): return
	var references: Variant = JSON.parse_string(FileAccess.get_file_as_string(REFERENCES))
	if not _require(references is Dictionary and references.get("version") == 1 and references.get("ships") is Dictionary, "Missing source hull/deck reference metadata"): return
	var base: Variant = JSON.parse_string(FileAccess.get_file_as_string(PeopleAtlas.BASE_MANIFEST))
	if not _require(base is Dictionary and base.get("appearance") is Dictionary, "Missing original person atlas appearance"): return
	var appearances: Array[Dictionary] = [base.appearance, PeopleAtlas.female_appearance()]
	var people := {}
	var directions: Array[String] = ["up", "right", "down", "left"]
	for direction: String in directions:
		for body: int in range(2):
			var frame: Dictionary = PeopleAtlas.frame(appearances[body], "idle", direction, 0.0)
			if not _require(not frame.is_empty() and frame.get("texture") is AtlasTexture, "Original person sprite not admitted: " + direction + "/" + str(body)): return
			people["%s:%d" % [direction, body]] = frame
	var viewport := SubViewport.new()
	viewport.size = CANVAS_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var board := Board.new()
	board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # Same formal render contract; no transparent RGB bilinear fringe.
	viewport.add_child(board)
	var report: Array[Dictionary] = []
	for row: int in range(Ships.KINDS.size()):
		var kind: String = Ships.KINDS[row]
		var spec: Dictionary = Ships.definition(kind)
		var source: Dictionary = document.ships.get(kind, {})
		var path := str(source.get("source", ""))
		var image := Image.load_from_file(path)
		if not _require(path.begins_with("res://output/site_ship_close_20261004/art_preview/") and not image.is_empty(), "Preview only reads approved staging locations: " + kind): return
		if not _require(FileAccess.get_sha256(path).to_upper() == str(source.get("sha256", "")) and references.ships.get(kind, {}).get("sha256", "") == source.get("sha256", ""), "Unmodified v3 PNG must match its recorded source hash: " + kind): return
		var dimensions: Variant = source.get("size", [])
		if not _require(dimensions is Array and dimensions.size() == 2
			and (dimensions[0] is int or dimensions[0] is float) and float(dimensions[0]) == float(image.get_width())
			and (dimensions[1] is int or dimensions[1] is float) and float(dimensions[1]) == float(image.get_height()), "Recorded v3 source dimensions must match unchanged image: " + kind): return
		var page := ImageTexture.create_from_image(image)
		for quarter: int in range(4):
			var direction: String = directions[quarter]
			var region: Array = source.regions.get(direction, [])
			if not _require(region.size() == 4, "All four original source directions must exist: " + kind): return
			var reference: Dictionary = references.ships.get(kind, {}).get("frames", {}).get(direction, {})
			if not _require(reference.get("source_region", []) == region and reference.get("hull_reference_region", []).size() == 4 and reference.get("walkdeck_reference_region", []) == reference.get("hull_reference_region", []), "Whole hull must map to original footprint; do not expand art using a smaller middle deck: " + kind + "/" + direction): return
			var deck_values: Array = reference.walkdeck_reference_region
			var deck: Rect2 = Rect2(float(deck_values[0]), float(deck_values[1]), float(deck_values[2]), float(deck_values[3]))
			if not _require(Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3])).encloses(deck) and deck.has_area(), "Deck reference must be inside the unmodified source frame"): return
			var atlas := AtlasTexture.new()
			atlas.atlas = page
			atlas.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
			atlas.filter_clip = true
			var facing: Vector2i = TerrainData.DIRECTIONS[quarter]
			var cells: Array[Vector2i] = Ships.footprint(kind, Vector2i.ZERO, facing)
			if not _require(cells.size() == int(spec.width) * int(spec.length), "Footprint must use the current pure definition"): return
			var minimum: Vector2i = cells[0]
			var maximum: Vector2i = cells[0]
			for cell: Vector2i in cells:
				minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
				maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
			var bounds := Rect2i(minimum, maximum - minimum + Vector2i.ONE)
			var panel := Rect2(Vector2(quarter * 620 + 8, row * 750 + 76), Vector2(604, 738))
			var size := Vector2(bounds.size) * CELL_PIXELS
			var art_scale: Vector2 = size / deck.size
			var image_size: Vector2 = Vector2(float(region[2]), float(region[3])) * art_scale
			var image_rect: Rect2 = Rect2(panel.get_center() + Vector2(0, 16) - image_size * 0.5, image_size)
			var hull: Rect2 = Rect2(image_rect.position + (deck.position - Vector2(float(region[0]), float(region[1]))) * art_scale, size)
			if not _require(panel.encloses(image_rect), "Panel must show the full source art, including oars and both ends: " + kind + "/" + direction): return
			var origin := hull.position - (Vector2(bounds.position) - Vector2.ONE * 0.5) * CELL_PIXELS
			board.frames.append({"kind": kind, "direction": direction, "facing": Vector2(facing), "texture": atlas,
				"panel": panel, "hull": hull, "image_rect": image_rect, "origin": origin, "cells": cells, "width": int(spec.width), "length": int(spec.length), "people": int(spec.max_people)})
			var minimum_foot_alpha: float = 1.0
			for berth: int in range(int(spec.max_people)):
				var person: Dictionary = people["%s:%d" % [direction, berth % 2]]
				var sprite := Sprite2D.new()
				sprite.texture = person.texture
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				sprite.centered = false
				sprite.offset = -Vector2(float(person.anchor_offset.x), float(person.anchor_offset.y))
				sprite.scale = Vector2.ONE * float(person.map_scale) * CELL_PIXELS / float(TerrainRenderer.CELL_PIXELS)
				sprite.position = origin + Ships.world_position(Vector2i.ZERO, facing, Ships.local_position(kind, berth)) * CELL_PIXELS
				if not _require(hull.has_point(sprite.position), "Original berth must remain within whole physical hull: " + kind + "/" + direction + "/" + str(berth)): return
				var source_foot: Vector2 = Vector2(float(region[0]), float(region[1])) + (sprite.position - image_rect.position) / art_scale
				var foot_alpha: float = image.get_pixel(clampi(floori(source_foot.x), 0, image.get_width() - 1), clampi(floori(source_foot.y), 0, image.get_height() - 1)).a
				minimum_foot_alpha = minf(minimum_foot_alpha, foot_alpha)
				if not _require(foot_alpha >= 0.25, "Original berth foot must hit actual hull pixels, not transparent water/oar gap: " + kind + "/" + direction + "/" + str(berth)): return
				sprite.z_index = 1 + berth
				board.add_child(sprite)
			report.append({"ship_type": kind, "direction": direction, "source": path, "atlas_region": region,
				"walkdeck_reference_region": deck_values, "hull_reference_region": reference.hull_reference_region,
				"full_art_pixels": [image_size.x, image_size.y], "physical_claim_pixels": [size.x, size.y],
				"footprint_cells": cells.size(), "width_metres": int(spec.width) * 2, "length_metres": int(spec.length) * 2,
				"original_person_sprites": int(spec.max_people), "pixels_per_cell": CELL_PIXELS,
				"minimum_original_berth_source_alpha": minimum_foot_alpha, "source_sha256": source.sha256,
				"visual_form": "Elevated tower with upper chamber/roof and open undercroft; original-owner GPU occlusion pending" if kind == "tower" else "rectangular open hull",
				"capture": kind + "_" + direction + ".png"})
	board.queue_redraw()
	for _frame: int in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	if not _require(report.size() == 24 and board.frames.size() == 24 and not picture.is_empty(), "All six types and four actual atlas directions must render"): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if not _require(picture.save_png(OUT + "/six_types_four_directions.png") == OK, "GPU preview screenshot could not be saved"): return
	for index: int in report.size():
		var frame: Dictionary = board.frames[index]
		var panel: Rect2 = frame.panel
		var capture: Image = picture.get_region(Rect2i(Vector2i(panel.position), Vector2i(panel.size)))
		if not _require(capture.save_png(OUT + "/" + str(report[index].capture)) == OK, "Each of the 24 approval screenshot panels must be retained"): return
	var file := FileAccess.open(OUT + "/preview_capture.json", FileAccess.WRITE)
	if not _require(file != null, "GPU preview report could not be saved"): return
	file.store_string(JSON.stringify({"status": "SITE_SHIP_ART_PROPORTION_PREVIEW_PASS", "captures": report,
		"image": "six_types_four_directions.png", "scope": "NEW V4 TOWER AND V3 FLEET REQUIRE HUMAN APPROVAL. Whole actual wooden hull maps to original rectangular ShipDefinitions claims; original person positions, berths and map scale retained. Exterior oars/flags/rope fittings may extend outside collision rectangle. All original berth feet hit source hull alpha. These are atlas approval screenshots; no actual owner/person/vehicle instances, front-rail occlusion, formal publication, performance or user approval claim."}, "\t"))
	file.close()
	run_completed = true
	viewport.queue_free()
	print("SITE_SHIP_ART_PROPORTION_PREVIEW_PASS: 24 whole-hull source regions / new raised tower / unchanged original berths and person scale / 24 retained approval panels; NEW IMAGE APPROVAL PENDING")
	quit(0)
