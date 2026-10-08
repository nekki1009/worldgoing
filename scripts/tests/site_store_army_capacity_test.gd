extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/army-capacity.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(Store.MAX_ARMIES == 50 and Store.MAX_ARMY_ROWS == 5000)
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581, {"size": Vector2i(128, 128)})
	SiteEnvironment.initialize(data, "army-capacity-fixture")
	var available: Array[Vector2i] = []
	for y in range(data.size.y):
		for x in range(data.size.x):
			var cell := Vector2i(x, y)
			if data.is_walkable(cell) and cell != data.spawn_cell:
				available.append(cell)
	assert(available.size() >= Store.MAX_ARMY_ROWS + 1)
	var snapshots: Array = []
	for index in range(Store.MAX_ARMIES):
		var selected: Array[Vector2i] = []
		for cell_index in range(index * 100, (index + 1) * 100):
			selected.append(available[cell_index])
		snapshots.append(_team_snapshot(data, index + 1, 100, selected))
	data.site["actors"] = {}
	data.site["armies"] = snapshots
	data.site["army_trial_active"] = true
	data.site["army_next_team"] = Store.MAX_ARMIES + 1
	data.site["next_person_id"] = 1000 + (Store.MAX_ARMIES + 1) * 100
	var saved: Dictionary = Store.save(data, SAVE)
	assert(saved.ok, str(saved))
	var loaded: Dictionary = Store.load_site(SAVE)
	assert(loaded.ok, str(loaded))
	assert(loaded.data.site.armies.size() == Store.MAX_ARMIES)
	var people := {}
	for snapshot: Dictionary in loaded.data.site.armies:
		assert(snapshot.units.size() == 100)
		for unit: Dictionary in snapshot.units:
			assert(not people.has(int(unit.person_id)))
			people[int(unit.person_id)] = true
	assert(people.size() == Store.MAX_ARMY_ROWS)
	var original_checksum := FileAccess.get_file_as_string(SAVE).sha256_text()
	var one_extra: Array[Vector2i] = [available[Store.MAX_ARMY_ROWS]]
	data.site.armies.append(_team_snapshot(data, Store.MAX_ARMIES + 1, 1, one_extra))
	data.site.army_next_team = Store.MAX_ARMIES + 2
	data.site.next_person_id = 1000 + (Store.MAX_ARMIES + 2) * 100
	assert(not Store.save(data, SAVE).ok, "The 51st team must be rejected")
	assert(FileAccess.get_file_as_string(SAVE).sha256_text() == original_checksum)
	data.site.armies.pop_back()
	var extra_cells: Array[Vector2i] = []
	for cell_index in range((Store.MAX_ARMIES - 1) * 100, Store.MAX_ARMY_ROWS + 1):
		extra_cells.append(available[cell_index])
	data.site.armies[Store.MAX_ARMIES - 1] = _team_snapshot(data, Store.MAX_ARMIES, 101, extra_cells)
	data.site.army_next_team = Store.MAX_ARMIES + 1
	data.site.next_person_id = 1000 + (Store.MAX_ARMIES + 1) * 100 + 1
	assert(not Store.save(data, SAVE).ok, "The 5001st roster row must be rejected")
	assert(FileAccess.get_file_as_string(SAVE).sha256_text() == original_checksum)
	print("SITE_STORE_ARMY_CAPACITY_PASS teams=50 rows=5000 roundtrip=true 51st_team_rejected=true 5001st_row_rejected=true bytes=%d" % FileAccess.get_file_as_bytes(SAVE).size())
	quit(0)

func _team_snapshot(data: TerrainData, identity: int, count: int, cells: Array[Vector2i]) -> Dictionary:
	assert(cells.size() == count)
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = identity
	team.faction_id = 1 if identity <= 25 else 2
	team.roster_size = count
	team.exchange_enabled = true # Formal TerrainLab resolves adjacent exchanges; avoid legacy 3D ContactSource in headless tests.
	assert(team.deploy_at(data, null, null, cells))
	assert(team.enable_combat(false))
	var snapshot: Dictionary = team.capture_combat_state()
	team.free()
	return snapshot
