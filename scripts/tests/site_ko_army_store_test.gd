extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/ko-army-new.json"

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		TerrainArmy.release_contact_source()
		quit(1))
	_run.call_deferred()

func _run() -> void:
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "ko-army-store")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var team := TerrainArmy.new()
	team.team_id = 1
	team.roster_size = 1
	root.add_child(team)
	team.set_process(false)
	var cell := Vector2i(25, 25)
	var selected: Array[Vector2i] = [cell]
	var _army_action_check_1: bool = data.is_walkable(cell) and team.deploy_at(data, null, null, selected) and team.enable_combat(false)
	assert(_army_action_check_1)
	team.apply_unit_contact(0, {"shield": false, "result": {"hp": 1.0, "stun": 110.0, "guard_break": false}})
	team.settle_combat_command()
	data.site.army_trial_active = true
	data.site.army_next_team = 2
	data.site.actors = {}
	data.site.armies = [JSON.parse_string(JSON.stringify(team.capture_combat_state()))]
	var saved := Store.save(data, SAVE)
	if not saved.ok:
		_fail("New Army KO could not save: " + str(saved) + " roster=" + str(TerrainArmy.valid_combat_state(data.site.armies[0], data)) + " armies=" + str(Store._validate_armies(data, data.site)))
		return
	var original_hash := FileAccess.get_sha256(SAVE)
	var original := Store._read(SAVE)
	var payload: Dictionary = original.payload.duplicate(true)
	payload.state.armies[0].schema = 1
	payload.state.armies[0].units[0].ko = 17.0
	_write(SAVE + ".legacy", payload)
	var loaded := Store.load_site(SAVE + ".legacy")
	if not loaded.ok or loaded.data.site.armies[0].schema != 2 or loaded.data.site.armies[0].units[0].ko != 8160.0 or "舊版昏迷" not in str(loaded.message):
		_fail("Full SiteStore Army schema-1 KO migration failed: " + str(loaded))
		return
	if not Store.save(loaded.data, SAVE + ".resaved").ok:
		_fail("Migrated Army KO could not resave")
		return
	var reloaded := Store.load_site(SAVE + ".resaved")
	if not reloaded.ok or reloaded.data.site.armies[0].units[0].ko != 8160.0:
		_fail("Army KO migration repeated on second SiteStore load")
		return
	payload.state.armies[0].schema = 2
	_write(SAVE + ".short_new", payload)
	var short_new := Store.load_site(SAVE + ".short_new")
	if not short_new.ok or short_new.data.site.armies[0].units[0].ko != 17.0:
		_fail("Schema-2 Army KO of 17 game seconds was converted as legacy")
		return
	payload.state.armies[0].schema = 1
	payload.state.armies[0].units[0].ko = 31.0
	_write(SAVE + ".invalid", payload)
	if Store.load_site(SAVE + ".invalid").ok or FileAccess.get_sha256(SAVE) != original_hash:
		_fail("Invalid legacy Army KO changed the valid save")
		return
	team.free()
	TerrainArmy.release_contact_source()
	print("SITE_KO_ARMY_STORE_PASS")
	quit(0)

func _write(path: String, payload: Dictionary) -> void:
	var body := JSON.stringify(payload, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()

func _fail(message: String) -> void:
	push_error(message)
	TerrainArmy.release_contact_source()
	quit(1)
