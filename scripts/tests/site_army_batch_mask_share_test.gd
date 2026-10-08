extends SceneTree

const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	assert(TerrainArmy.load_combat_bake() and army._load_baked_soldier())
	var first := Batch.new()
	var second := Batch.new()
	root.add_child(first)
	root.add_child(second)
	first.setup(army, 1)
	second.setup(army, 1)
	var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	var first_page: Dictionary = first._describe(appearance)
	var second_page: Dictionary = second._describe(appearance)
	assert(not first_page.is_empty() and not second_page.is_empty())
	var shared: ImageTexture = first._pages[int(first_page.page)].mask_texture
	var duplicate: ImageTexture = second._pages[int(second_page.page)].mask_texture
	assert(shared == duplicate and shared.get_rid() == duplicate.get_rid())
	var another := appearance.duplicate(true)
	another.parts.weapon = "bow_01"
	another.parts.shield = "none"
	var other_page: Dictionary = second._describe(another)
	assert(not other_page.is_empty())
	var other: ImageTexture = second._pages[int(other_page.page)].mask_texture
	assert(other != shared and other.get_rid() != shared.get_rid())
	var shared_ref: WeakRef = weakref(shared)
	var other_ref: WeakRef = weakref(other)
	shared = null
	duplicate = null
	other = null
	first.queue_free()
	second.queue_free()
	await process_frame
	await process_frame
	assert(shared_ref.get_ref() == null and other_ref.get_ref() == null)
	print("SITE_ARMY_BATCH_MASK_SHARE_PASS same mask shares RID; distinct mask stays distinct; freed views release textures")
	quit()
