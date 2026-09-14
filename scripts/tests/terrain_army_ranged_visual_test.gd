extends SceneTree
## Actual published frames through the production EquipmentAtlas lookup.
const Reader = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")
const EquipmentAtlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const CAPTURE := "res://output/site_ranged_20260914/ranged_poses.png"
const DIRECTIONS := ["down", "left", "up", "right"]
const POSES := ["idle", "combat_walk", "attack_release", "guard", "hit", "unconscious"]
const LABELS := ["待機", "戰鬥行走", "射出附近", "防禦", "受擊", "昏迷"]
var _deadline := 0

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 15000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline:
		push_error("Ranged pose capture exceeded its 15-second deadline")
		quit(2)
	return false

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Ranged contact sheet needs a GPU-backed window")
	root.size = Vector2i(1280, 1040)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("151d28"))
	assert(Reader.set_root_path(Reader.ROOT))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	_label(scene, "弓／弩正式圖集 · 四方向與六種動作", Vector2(24, 14), 27)
	_label(scene, "原角色、原武器、無盾；正式 EquipmentAtlas 路由。僅放大檢視，不替代戰鬥效能驗收。", Vector2(24, 52), 16)
	var sprites := 0
	for weapon_index in range(2):
		var weapon: String = Reader.WEAPONS[weapon_index]
		var published: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.ROOT + "/" + weapon + "/manifest.json"))
		assert(EquipmentAtlas.supports(published.appearance))
		var recipe := Reader.recipe(published.appearance)
		assert(recipe.sequences.size() == 76)
		for direction_index in range(4):
			var direction: String = DIRECTIONS[direction_index]
			var x := 156.0 + float(weapon_index * 4 + direction_index) * 138.0
			_label(scene, ("弓 " if weapon_index == 0 else "弩 ") + direction, Vector2(x + 8, 83), 17)
			for row in range(POSES.size()):
				var y := 114.0 + float(row) * 149.0
				var background := ColorRect.new()
				background.position = Vector2(x, y)
				background.size = Vector2(132, 143)
				background.color = Color("253141") if weapon_index == 0 else Color("29373a")
				scene.add_child(background)
				if weapon_index == 0 and direction_index == 0:
					_label(scene, LABELS[row] + "\n" + POSES[row], Vector2(20, y + 49), 17)
				var clip: String = POSES[row]
				var sample_time := 0.0
				if clip == "attack_release":
					clip = "attack_bow" if weapon_index == 0 else "attack_crossbow"
					sample_time = float(Timings.events(StringName(clip)).release)
				elif clip in ["combat_walk", "guard", "hit"]:
					sample_time = float(recipe.sequences[clip + "|" + direction][1].sample_time)
				var frame := EquipmentAtlas.frame(published.appearance, clip, direction, sample_time)
				assert(not frame.is_empty() and frame.texture is AtlasTexture)
				var sprite := Sprite2D.new()
				sprite.texture = frame.texture
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				var zoom := minf(float(frame.map_scale) * 1.8, minf(126.0 / float(sprite.texture.get_width()), 137.0 / float(sprite.texture.get_height())))
				sprite.scale = Vector2.ONE * zoom
				sprite.position = Vector2(x + 66, y + 129) - Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * zoom
				scene.add_child(sprite)
				sprites += 1
	assert(sprites == 48 and EquipmentAtlas.page_load_count == 2, "Both actual pages are shared by all 48 pose sprites")
	await process_frame
	await RenderingServer.frame_post_draw
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE.get_base_dir())) == OK)
	assert(root.get_texture().get_image().save_png(CAPTURE) == OK)
	print("TERRAIN ARMY RANGED VISUAL CAPTURE PASS: 48 actual published frames, 2 shared pages -> ", CAPTURE)
	scene.queue_free()
	await process_frame
	quit(0)

func _label(parent: Node, text: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
