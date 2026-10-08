extends SceneTree
## Real publications only. Removed-gear male is an acceptance gate, not a fallback to dressed pixels.
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Node = load("res://scripts/terrain_lab/site_controller.gd").new()
	var configured: Dictionary = paths.configure_test_paths(OS.get_cmdline_user_args())
	paths.free()
	if not configured.ok:
		printerr("CROWD_RECIPE_GATE invalid isolated atlas path: ", configured)
		quit(1)
		return
	print("CROWD_RECIPE_GATE atlas_root=", Atlas._mixed_root)
	if DisplayServer.get_name() == "headless":
		printerr("CROWD_RECIPE_GATE requires the bounded GPU verifier")
		quit(1)
		return
	create_timer(60.0).timeout.connect(func() -> void: printerr("CROWD_RECIPE_GATE deadline"); quit(2))
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	if not TerrainArmy.load_combat_bake() or not army._load_baked_soldier():
		printerr("CROWD_RECIPE_GATE baseline publication missing")
		quit(1)
		return
	var view := Batch.new()
	root.add_child(view)
	view.setup(army, 16)
	var base: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	var cases: Array[Dictionary] = [{"name": "male_base", "appearance": base},
		{"name": "female_base", "appearance": Atlas.female_appearance()}]
	for body in range(2):
		for weapon: String in ["bow_01", "crossbow_01"]:
			var ranged: Dictionary = (base if body == 0 else Atlas.female_appearance()).duplicate(true)
			ranged.parts.weapon = weapon
			ranged.parts.shield = "none"
			cases.append({"name": "%s_%s" % ["male" if body == 0 else "female", weapon], "appearance": ranged})
	var removed := base.duplicate(true)
	for slot: String in ["weapon", "shield", "helmet"]: removed.parts[slot] = "none"
	removed.equipment_dyes = {"armor": "b6433aff", "boots": "49332fff", "outfit": "e3d5baff"}
	cases.append({"name": "male_removed_gear_m28", "appearance": removed})
	var failures := 0
	for row: Dictionary in cases:
		var appearance: Dictionary = row.appearance
		var before := appearance.duplicate(true)
		var descriptor: Dictionary = view._describe(appearance)
		var geometry: Dictionary = Atlas.DyeAtlas.Dye.geometry_appearance(appearance)
		var dye: Dictionary = Atlas.dye_entry(geometry)
		var mixed: Dictionary = Atlas.mixed_recipe(geometry)
		print("CROWD_RECIPE_GATE ", row.name, " admitted=", not descriptor.is_empty(),
			" dye=", not dye.is_empty(), " mixed=", not mixed.is_empty(), " mask=", Atlas._appearance_mask(geometry))
		if descriptor.is_empty() or appearance != before:
			failures += 1
			continue
		var page: Dictionary = view._pages[int(descriptor.page)]
		if not page.sequences.has("combat_idle|down") or page.texture == null or page.mask_texture == null:
			failures += 1
	# Invalid appearance/dye must never borrow the baseline page.
	var bad := base.duplicate(true)
	bad.parts.weapon = "missing_recipe_weapon"
	if not view._describe(bad).is_empty(): failures += 1
	bad = base.duplicate(true)
	bad.equipment_dyes = {"weapon": "not_a_color"}
	if not view._describe(bad).is_empty(): failures += 1
	print("CROWD_RECIPE_GATE cases=", cases.size(), " failures=", failures)
	quit(0 if failures == 0 else 1)
