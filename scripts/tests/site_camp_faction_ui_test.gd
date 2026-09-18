extends SceneTree
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUT := "res://output/site_support_teams_20260918/camp_ui"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 25000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Camp faction UI deadline")
		quit(1)
	return false

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var lab := TerrainLab.new()
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	assert(lab.npc.faction_id == lab.character.faction_id and lab.npc_allied_toggle.button_pressed)
	for allied: bool in [false, true]:
		lab.npc_allied_toggle.button_pressed = allied
		assert((lab.npc.faction_id == lab.character.faction_id) == allied)
		lab.site_controller._capture_positions()
		var path := OUT + ("/allied.json" if allied else "/hostile.json")
		var saved := Store.save(lab.terrain, path)
		assert(saved.ok, str(saved))
		lab.npc_allied_toggle.button_pressed = not allied
		var loaded := Store.load_site(path)
		assert(loaded.ok, str(loaded))
		lab.bind_terrain(loaded.data)
		assert((lab.npc.faction_id == lab.character.faction_id) == allied and lab.npc_allied_toggle.button_pressed == allied, "Restore checkbox from the saved original faction, never rewrite that faction")
	print("SITE_CAMP_FACTION_UI_PASS: default original camp worker allied, actual checkbox changes faction, hostile and allied Store/bind both retain faction and synchronize the same checkbox")
	lab.queue_free()
	await process_frame
	quit(0)
