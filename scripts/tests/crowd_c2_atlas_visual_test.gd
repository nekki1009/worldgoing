extends SceneTree
## First GPU draw of original pages/shader. This samples poses, never rebakes an oracle.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const Site = preload("res://scripts/terrain_lab/site_controller.gd")
const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const TASK := "res://output/crowd_c2_c3_b_atlas_20261001"
const DIRECTIONS := ["down", "left", "up", "right"]
const CELL_SIZE := Vector2i(136, 142)
const PALETTES := [{"helmet": "e58049ff", "armor": "ea584dff", "outfit": "dcb95fff", "boots": "446cbfff", "cape": "ce714bff"},
	{"helmet": "46b2e0ff", "armor": "42ca92ff", "outfit": "62b8e0ff", "boots": "d671dfff", "cape": "866cd8ff"}]
var output := ""
var checks := 0
var results: Array[Dictionary] = []
var clip_owner: Node
var army: TerrainArmy
var current_case := "startup"
var started := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	if not value:
		printerr("CROWD_ATLAS_VISUAL_FAIL ", current_case, " ", label)
		_write(false)
		quit(1)
		assert(value, label)
	checks += 1

func _write(complete: bool) -> void:
	if output.is_empty(): return
	var file := FileAccess.open(output + "/result.json", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"complete": complete, "checks": checks, "current": current_case,
		"seconds": float(Time.get_ticks_msec() - started) / 1000.0, "atlas_root": Atlas._mixed_root,
		"namespace": Atlas._mixed_namespace, "cases": results,
		"scope": "19 acceptance cases, four directions/six selected poses/two palettes; first transparent GPU draw and displayed grid; original frame admission and alpha/colour checks. Some gates intentionally share a recipe. Sampled GPU poses, not all-pose pixel equivalence or gameplay/FPS acceptance."}, "\t"))
	file.close()

func _cases() -> Array[Dictionary]:
	var base: Dictionary = TerrainArmy._combat_bake.manifest.appearance
	var rows: Array[Dictionary] = [{"name": "male_base", "appearance": base.duplicate(true)},
		{"name": "female_base", "appearance": Atlas.female_appearance()}]
	for body in range(2):
		for weapon: String in ["bow_01", "crossbow_01"]:
			var appearance: Dictionary = (base if body == 0 else Atlas.female_appearance()).duplicate(true)
			appearance.parts.weapon = weapon
			appearance.parts.shield = "none"
			rows.append({"name": "%s_%s" % ["male" if body == 0 else "female", weapon], "appearance": appearance})
	var removed := base.duplicate(true)
	for slot: String in ["weapon", "shield", "helmet"]: removed.parts[slot] = "none"
	rows.append({"name": "male_removed_gear_m28", "appearance": removed})
	var publication: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TASK + "/publication/revalidation.json"))
	_check(publication.publications.size() == 14 and publication.namespace == Atlas._mixed_namespace, "use the frozen new source namespace")
	for row: Dictionary in publication.publications:
		if row.kind == "mixed": rows.append({"name": row.name, "appearance": row.appearance.duplicate(true)})
	_check(rows.size() == 19, "exact seven formal plus twelve captivity cases")
	return rows

func _palette(appearance: Dictionary, index: int) -> Dictionary:
	var result := appearance.duplicate(true)
	result.erase("equipment_dyes")
	var colors := {}
	for slot: String in Atlas.DyeAtlas.Dye.SLOTS:
		if str(result.parts.get(slot, "none")) != "none": colors[slot] = PALETTES[index][slot]
	_check(not colors.is_empty(), "case has real dyeable clothing")
	result.equipment_dyes = colors
	return result

func _recipe(appearance: Dictionary) -> Dictionary:
	var geometry := Atlas.DyeAtlas.Dye.geometry_appearance(appearance)
	if geometry == TerrainArmy._combat_bake.manifest.appearance:
		var sequences := {}
		for clip: String in TerrainArmy._combat_bake.contact_clocks:
			for direction: String in TerrainArmy._combat_bake.contact_clocks[clip]:
				sequences[clip + "|" + direction] = TerrainArmy._combat_bake.contact_clocks[clip][direction][3]
		return {"sequences": sequences, "baseline": true}
	var recipe := Atlas.mixed_recipe(appearance)
	if recipe.is_empty(): recipe = Atlas.female_recipe(appearance) if geometry.body == 1 else Atlas.RangedAtlas.recipe(appearance)
	if recipe.is_empty():
		var mask := Atlas._appearance_mask(geometry)
		if mask >= 0: recipe = Atlas._recipe(mask, Atlas._appearance_iron(geometry))
	return recipe

func _frame(appearance: Dictionary, recipe: Dictionary, clip: String, direction: String, index: int) -> Dictionary:
	var frame: Dictionary = recipe.sequences[clip + "|" + direction][index]
	var selected: Dictionary
	if bool(recipe.get("baseline", false)):
		# Match the original Army/Batch baseline branch. Atlas.frame(base) is a
		# different multi-page m31 recipe and must not borrow the base dye mask.
		selected = frame.duplicate(false)
		selected.texture = TerrainArmy._static_soldier_frame_textures["%s|%s|%d" % [clip, direction, int(frame.frame)]]
		selected.map_scale = TerrainArmy._static_soldier_map_scale
	else: selected = Atlas.frame(appearance, clip, direction, float(frame.sample_time))
	_check(not selected.is_empty() and selected.clip == frame.clip and selected.direction == frame.direction and selected.frame == frame.frame
		and selected.rect == frame.rect and selected.anchor_offset == frame.anchor_offset and selected.sample_time == frame.sample_time,
		"selected original frame retains clip/direction/index/rect/anchor/time")
	_check(selected.texture is AtlasTexture and selected.texture.get_width() == int(frame.rect.w) and selected.texture.get_height() == int(frame.rect.h), "selected page texture fits the original frame rectangle")
	return selected

func _full_frames(appearance: Dictionary, recipe: Dictionary) -> int:
	_check(not recipe.is_empty() and not recipe.sequences.is_empty(), "complete original recipe admitted")
	var count := 0
	for key: String in recipe.sequences:
		var frames: Array = recipe.sequences[key]
		_check(not frames.is_empty(), "every original sequence is nonempty")
		for index in range(frames.size()):
			_frame(appearance, recipe, str(frames[index].clip), str(frames[index].direction), index)
			count += 1
	return count

func _sample_index(clip: String, frames: Array) -> int:
	if clip in ["combat_idle", "unconscious", "guard"]: return 0
	var events := Timings.events(StringName(clip))
	if not events.is_empty():
		var elapsed: float = events.release if float(events.release) >= 0.0 else events.active_start
		var selected := 0
		for index in range(frames.size()):
			if float(frames[index].sample_time) <= elapsed + 0.000000001: selected = index
		return selected
	return mini(2, frames.size() - 1)

func _pixels(first: Image, second: Image) -> Dictionary:
	var a := first.get_data()
	var b := second.get_data()
	_check(a.size() == b.size() and first.get_format() == Image.FORMAT_RGBA8 and second.get_format() == Image.FORMAT_RGBA8, "compare actual RGBA8 GPU tiles")
	var occupied := 0
	var opaque := 0
	var colored := 0
	var changed := 0
	var same_alpha := true
	for index in range(0, a.size(), 4):
		same_alpha = same_alpha and a[index + 3] == b[index + 3]
		if a[index + 3] == 0: continue
		occupied += 1
		if a[index + 3] >= 250: opaque += 1
		if maxi(a[index], maxi(a[index + 1], a[index + 2])) > 12: colored += 1
		if a[index] != b[index] or a[index + 1] != b[index + 1] or a[index + 2] != b[index + 2]: changed += 1
	_check(same_alpha, "palette preserves the actual rendered alpha silhouette")
	_check(occupied > 25 and opaque > 20 and colored > 5 and changed > 0, "nonempty actual colour/alpha pixels and a real shader palette change")
	return {"nonzero_alpha": occupied, "opaque_alpha": opaque, "colored_pixels": colored, "palette_changed_pixels": changed}

func _label(parent: Node, text: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)

func _draw_case(row: Dictionary, ordinal: int) -> void:
	current_case = row.name
	var before: Dictionary = row.appearance.duplicate(true)
	var variants: Array[Dictionary] = [_palette(before, 0), _palette(before, 1)]
	var recipe := _recipe(variants[0])
	var frame_count := _full_frames(variants[0], recipe)
	var batch := Batch.new()
	root.add_child(batch)
	batch.setup(army, 16)
	var sources: Array[Dictionary] = []
	for appearance: Dictionary in variants:
		_check(Atlas.supports(appearance), "original source/palette runtime admission")
		var descriptor: Dictionary = batch._describe(appearance)
		_check(not descriptor.is_empty(), "original Batch page/mask/dimensions admission")
		var dye := Atlas.dye_entry(appearance)
		sources.append({"source_manifest": dye.source_manifest, "manifest_md5": dye.source_manifest_md5, "mask": dye.mask_path, "mask_md5": dye.mask_md5})
	batch.free()
	var slots: Array[String] = ["idle", "walk", "attack", "shoot" if str(before.parts.weapon) in ["bow_01", "crossbow_01"] else "guard", "hit", "unconscious"]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(CELL_SIZE.x * 8, CELL_SIZE.y * 6)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)
	var records: Array[Dictionary] = []
	for pose in range(slots.size()):
		var clip: String = clip_owner._clip_for(slots[pose], before)
		clip = Atlas.normalized_clip(clip)
		_check(not clip.is_empty(), "Crowd chooses an actual original animation")
		for direction in range(DIRECTIONS.size()):
			var sequence: Array = recipe.sequences[clip + "|" + DIRECTIONS[direction]]
			var index := _sample_index(clip, sequence)
			var frame := _frame(variants[0], recipe, clip, DIRECTIONS[direction], index)
			for palette in range(2):
				var sprite := Sprite2D.new()
				sprite.texture = frame.texture
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				var anchor := Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y))
				var size := Vector2(sprite.texture.get_size())
				var zoom := minf(float(frame.map_scale) * 1.8, minf(62.0 / maxf(1.0, size.x * 0.5 + absf(anchor.x)), minf(126.0 / maxf(1.0, size.y * 0.5 + anchor.y), 10.0 / maxf(1.0, size.y * 0.5 - anchor.y))))
				sprite.scale = Vector2.ONE * zoom
				sprite.position = Vector2((direction * 2 + palette) * CELL_SIZE.x + 68, pose * CELL_SIZE.y + 130) - anchor * zoom
				viewport.add_child(sprite)
				_check(Atlas.apply_dye(sprite, variants[palette]), "original dye shader bound to the exact source mask")
			var texture := frame.texture as AtlasTexture
			records.append({"slot": slots[pose], "clip": clip, "direction": DIRECTIONS[direction], "frame": frame.frame,
				"sample_time": frame.sample_time, "rect": frame.rect, "anchor_offset": frame.anchor_offset,
				"page_resource": texture.atlas.resource_path, "row": pose, "direction_index": direction})
	# Capture the first real draw. No warm-up draws or CPU-generated coloured oracle.
	await process_frame
	await RenderingServer.frame_post_draw
	var actual := viewport.get_texture().get_image()
	_check(actual != null and not actual.is_empty(), "first GPU draw produced an image")
	actual.convert(Image.FORMAT_RGBA8)
	for record: Dictionary in records:
		var a := Rect2i(int(record.direction_index) * CELL_SIZE.x * 2, int(record.row) * CELL_SIZE.y, CELL_SIZE.x, CELL_SIZE.y)
		var b := Rect2i(a.position + Vector2i(CELL_SIZE.x, 0), a.size)
		record.pixel_metrics = _pixels(actual.get_region(a), actual.get_region(b))
	var stem := "%02d_%s" % [ordinal + 1, current_case]
	_check(actual.save_png(output + "/" + stem + "_transparent.png") == OK, "preserve the first transparent GPU image")
	var gallery := Node2D.new()
	root.add_child(gallery)
	_label(gallery, current_case + " · 原圖集四方向／六姿態", Vector2(24, 14), 26)
	_label(gallery, "A：赤／金／藍　B：綠／青／紫 · 同 frame、原 page 與 dye shader", Vector2(24, 50), 17)
	for direction in range(4):
		for palette in range(2): _label(gallery, DIRECTIONS[direction] + (" A" if palette == 0 else " B"), Vector2(180 + (direction * 2 + palette) * CELL_SIZE.x, 86), 17)
	for pose in range(6):
		_label(gallery, slots[pose], Vector2(24, 150 + pose * CELL_SIZE.y), 17)
		for column in range(8):
			var background := ColorRect.new()
			background.position = Vector2(160 + column * CELL_SIZE.x, 112 + pose * CELL_SIZE.y)
			background.size = Vector2(CELL_SIZE - Vector2i(2, 2))
			background.color = Color("253141") if column % 2 == 0 else Color("29373a")
			gallery.add_child(background)
	var image := TextureRect.new()
	image.position = Vector2(160, 112)
	image.texture = viewport.get_texture()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gallery.add_child(image)
	_label(gallery, "首幀 GPU：24 組 A/B 像素皆非空、遮罩染色有實際色差；完整原 frame 校驗 " + str(frame_count), Vector2(24, 985), 17)
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output + "/" + stem + ".png") == OK, "preserve the labelled display screenshot")
	_check(row.appearance == before, "original caller appearance remains unchanged")
	results.append({"name": current_case, "screenshot": output + "/" + stem + ".png", "first_gpu_image": output + "/" + stem + "_transparent.png",
		"appearance": before, "palettes": [variants[0].equipment_dyes, variants[1].equipment_dyes], "sources": sources,
		"validated_original_frames": frame_count, "sampled_sprites": 48, "first_draw": true, "samples": records})
	_write(false)
	print("CROWD_ATLAS_VISUAL_CASE ", ordinal + 1, "/19 ", current_case, " frames=", frame_count, " 48 first-draw sprites")
	gallery.free()
	viewport.free()

func _run() -> void:
	started = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var paths := Site.new()
	var configured: Dictionary = paths.configure_test_paths(args)
	paths.free()
	_check(configured.ok and args.has("--crowd-test") and args.has("--crowd-atlas-root") and DisplayServer.get_name() != "headless", "explicit isolated new-root GPU run")
	create_timer(160.0).timeout.connect(func() -> void: printerr("CROWD_ATLAS_VISUAL_FAIL deadline ", current_case); _write(false); quit(2))
	_check(TerrainArmy.load_combat_bake() and TerrainArmy.prewarm_soldier_atlas(), "original formal baseline owner loaded")
	Atlas.refresh_female_sources()
	Atlas._mixed_directory("visual_namespace")
	output = TASK + "/visual/" + Atlas._mixed_namespace + "/" + args[args.find("--crowd-test") + 1]
	_check(not DirAccess.dir_exists_absolute(output), "never overwrite previous visual evidence")
	_check(DirAccess.make_dir_recursive_absolute(output) == OK, "create explicit fresh visual namespace")
	root.size = Vector2i(1280, 1040)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("151d28"))
	army = TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	_check(army._load_baked_soldier(), "original instance references the prewarmed baseline page")
	clip_owner = Crowd.new()
	root.add_child(clip_owner)
	var cases := _cases()
	var appearances: Array = []
	for row: Dictionary in cases: appearances.append(_palette(row.appearance, 0))
	_check(Atlas.admit_crowd_appearances(appearances).ok, "all nineteen required exact appearances admitted")
	for index in range(cases.size()): await _draw_case(cases[index], index)
	_write(true)
	print("CROWD_ATLAS_VISUAL_PASS 19 cases / 912 sampled GPU sprites / four directions / six poses / two palettes; images=", output)
	quit(0)
