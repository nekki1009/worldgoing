extends SceneTree
## Actual published female frames, with independent bow/crossbow dye masks.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const OUT := "res://output/ranged_behavior_fix_20260918/female/visual"
const POSES := ["idle", "combat_walk", "attack", "attack_unarmed", "hit", "unconscious"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	create_timer(30.0).timeout.connect(func() -> void: push_error("Female ranged preview deadline"); quit(1))
	root.size = Vector2i(1280, 1040)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("151d28"))
	var scene := Node2D.new()
	root.add_child(scene)
	_label(scene, "女性弓兵／弩兵 · 正式 2D 圖集與各自染色遮罩", Vector2(24, 14), 27)
	_label(scene, "原女性模型、原武器與骨架、無盾；四方向六種姿態。", Vector2(24, 52), 17)
	var count := 0
	for weapon_index in range(2):
		var weapon: String = Atlas.RangedAtlas.WEAPONS[weapon_index]
		var appearance: Dictionary = Atlas.female_ranged_plan(weapon).appearance
		appearance.equipment_dyes = {"armor": "76a92dff" if weapon_index == 0 else "8453b1ff", "outfit": "f4ca78ff", "boots": "bd5d36ff"}
		assert(Atlas.supports(appearance))
		var recipe := Atlas.female_recipe(appearance)
		for direction_index in range(4):
			var direction: String = ["down", "left", "up", "right"][direction_index]
			var x := 156.0 + (weapon_index * 4 + direction_index) * 138.0
			_label(scene, ("弓 " if weapon_index == 0 else "弩 ") + direction, Vector2(x + 8, 83), 17)
			for row in range(POSES.size()):
				var y := 114.0 + row * 149.0
				var background := ColorRect.new()
				background.position = Vector2(x, y)
				background.size = Vector2(132, 143)
				background.color = Color("253141") if weapon_index == 0 else Color("29373a")
				scene.add_child(background)
				if weapon_index == 0 and direction_index == 0:
					_label(scene, ["待機", "戰鬥行走", "射擊", "貼身徒手", "受擊", "昏迷"][row], Vector2(20, y + 49), 19)
				var clip: String = POSES[row]
				var elapsed := 0.0
				if clip == "attack":
					clip = "attack_bow" if weapon_index == 0 else "attack_crossbow"
					elapsed = float(Timings.events(StringName(clip)).release)
				elif clip in ["combat_walk", "attack_unarmed", "hit"]:
					elapsed = float(recipe.sequences[clip + "|" + direction][2].sample_time)
				var frame := Atlas.frame(appearance, clip, direction, elapsed)
				assert(not frame.is_empty())
				var sprite := Sprite2D.new()
				sprite.texture = frame.texture
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				var zoom := minf(float(frame.map_scale) * 1.8, minf(126.0 / sprite.texture.get_width(), 137.0 / sprite.texture.get_height()))
				sprite.scale = Vector2.ONE * zoom
				sprite.position = Vector2(x + 66, y + 129) - Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * zoom
				scene.add_child(sprite)
				assert(Atlas.apply_dye(sprite, appearance))
				count += 1
	assert(count == 48 and Atlas.page_load_count == 2)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	assert(root.get_texture().get_image().save_png(OUT + "/female_ranged_poses.png") == OK)
	print("FEMALE RANGED VISUAL PASS: 48 published/dyed sprites / 2 shared pages")
	quit()

func _label(parent: Node, value: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
