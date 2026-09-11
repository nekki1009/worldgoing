extends SceneTree

const MAIN := "res://scenes/terrain_lab/TerrainLab.tscn"
const OUTPUT := "res://.visual_captures/v03r_release"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(ProjectSettings.get_setting("application/run/main_scene") == MAIN)
	assert(ProjectSettings.get_setting("application/config/version") == "V0.3R")
	for retired: String in [
		"scenes/Main.tscn", "scenes/world/WorldMap.tscn",
		"scenes/world/ContinuousWorldMap.tscn", "scenes/region/RegionMap.tscn",
		"scenes/site/SiteMap.tscn", "scenes/site/BattleSite.tscn",
		"scenes/ui/CharacterCreator.tscn", "scenes/ui/PaperDollV6Lab.tscn",
		"scripts/core/game_session.gd", "scripts/ui/paper_doll_composer.gd",
	]:
		assert(not FileAccess.file_exists("res://" + retired), "Retired entry remains: " + retired)
	for required: String in [
		HumanCharacter3DEditor.MALE_MODEL_PATH, HumanCharacter3DEditor.FEMALE_MODEL_PATH,
		MountHorse3D.HORSE_MODEL_PATH, TerrainArmy.SOLDIER_ATLAS_RESOURCE_PATH,
		"res://assets/map/site/cliffs/cliff_face_inland_highres_v2.png",
		"res://assets/map/terrain_lab/terrain_lab_grass_v2.png",
		"res://assets/map/terrain_lab/terrain_lab_water_v2.png",
		"res://assets/map/terrain_lab/terrain_lab_sand_v2.png",
	]:
		assert(ResourceLoader.exists(required), "Required runtime resource missing: " + required)
	var visual := DisplayServer.get_name() != "headless"
	if visual:
		DisplayServer.window_set_size(Vector2i(1600, 900))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 60
	var lab := load(MAIN).instantiate() as TerrainLab
	assert(lab != null)
	root.add_child(lab)
	await _settle(8)
	assert(lab.terrain.size == Vector2i(100, 100))
	assert(lab.terrain.is_walkable(lab.character.terrain_cell))
	assert(lab.terrain.is_walkable(lab.npc.terrain_cell))
	assert(lab.character.terrain_cell != lab.npc.terrain_cell)
	assert(lab.renderer.grass_texture != null and lab.renderer.cliff_texture != null)
	if visual:
		for actor: TerrainTestCharacter in [lab.character, lab.npc]:
			assert(actor.editor != null and actor.player_sprite.texture != null)
			assert(actor.editor.animation_player.has_animation(&"run"))
			assert(actor.editor.part_options[&"hair"].item_count == 9)
			assert(actor.editor.mount_horse != null)
		await _capture("01_site")
	lab.deploy_army()
	assert(lab.army.has_army() and lab.army.cells.size() == 100)
	var occupied: Dictionary = {}
	for cell: Vector2i in lab.army.cells:
		assert(lab.terrain.is_walkable(cell) and not occupied.has(cell))
		occupied[cell] = true
	if visual:
		assert(lab.army.visual_mode() == "baked_atlas")
		await _settle(12)
		await _capture("02_army")
	lab.clear_army()
	assert(not lab.army.has_army())
	lab.queue_free()
	await _settle(5)
	print("V03R_CLEANUP_PASS main=TerrainLab grid=100x100 actors=2 army=100 visual=", visual)
	quit(0)

func _settle(frames: int) -> void:
	for frame: int in frames:
		await process_frame

func _capture(label: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT.path_join(label + ".png")) == OK)
