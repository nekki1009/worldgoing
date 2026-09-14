extends SceneTree

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUTPUT := "res://output/site_ground_loot_scale/"
const SAVE_ROOT := "res://.godot-temp/site_ground_loot_scale/"
const SWORD := {"slot": "weapon", "asset": "longsword_01", "tint": [1.0, 1.0, 1.0, 1.0]}
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 18000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SITE GROUND LOOT SCALE bounded deadline exceeded")
		quit(1)
	return false

func _count_argument() -> int:
	var count := 1000
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--count="):
			count = int(argument.trim_prefix("--count="))
	assert(count in [1000, 9000], "Only the requested bounded scale cases are admitted")
	return count

func _write_report(name: String, result: Dictionary) -> void:
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK)
	var file := FileAccess.open(OUTPUT + name + ".json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(result, "\t", true, true))
	file.close()

func _fixture(count: int) -> Dictionary:
	var generation_start := Time.get_ticks_usec()
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581, {"size": Vector2i(128, 128)})
	Env.initialize(data, "ground-loot-scale-%d" % count)
	assert(Runtime.initialize_item_storage(data.site).ok)
	data.site.next_person_id = count + 1
	data.site.actors = {}
	data.site.armies = []
	var cells: Array[Vector2i] = []
	for offset in range(data.size.x * data.size.y):
		var cell := data.cell_from_index(offset)
		if data.is_walkable(cell):
			cells.append(cell)
	assert(cells.size() >= 1000)
	# Deterministic, spatially spread original legal cells; the first two drops
	# deliberately share a cell, exercising the original count marker.
	var rng := RandomNumberGenerator.new()
	rng.seed = 912731
	for index in range(cells.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var saved: Vector2i = cells[index]
		cells[index] = cells[other]
		cells[other] = saved
	var generation_ms := (Time.get_ticks_usec() - generation_start) / 1000.0
	var start := Time.get_ticks_usec()
	var nodes_before := get_node_count()
	for index in range(count):
		# Explicit fixture inventory creation, no production person/rig generation.
		var owner_id := index + 1
		var holder := Runtime.new_item_state("person:%d" % owner_id)
		var cargo := {"grain": 1}
		assert(Runtime.create_equipment(data, holder, "scale-sword", SWORD, owner_id, "weapon").ok)
		var cell := cells[0 if index == 1 else index % cells.size()]
		var drop := Runtime.leave_ground_loot(data, holder, cargo, owner_id, cell, "remains", cargo, holder.item_ids.duplicate(), int(holder.version))
		assert(drop.ok and holder.item_ids.is_empty() and cargo.is_empty())
		assert(Time.get_ticks_msec() < deadline, "Container setup exceeded the original bounded test deadline")
	assert(get_node_count() == nodes_before, "One container must not allocate one scene node")
	assert(data.site.ground_loot.size() == count and data.site.item_records.size() == count)
	assert(data.ground_loot_at[data.index(cells[0])].size() >= 2)
	return {"data": data, "shared_cell": cells[0], "generation_ms": generation_ms,
		"drop_creation_ms": (Time.get_ticks_usec() - start) / 1000.0, "nodes_added_for_containers": get_node_count() - nodes_before}

func _run() -> void:
	var count := _count_argument()
	var memory_before := OS.get_static_memory_usage()
	var setup := _fixture(count)
	var data: TerrainData = setup.data
	var report := {"scope": "Real sparse ground containers and original item ledger, not living soldiers or combat",
		"count": count, "unique_cells": data.ground_loot_at.size(), "generation_ms": setup.generation_ms,
		"drop_creation_ms": setup.drop_creation_ms, "nodes_added_for_containers": setup.nodes_added_for_containers,
		"static_memory_before_bytes": memory_before, "static_memory_after_creation_bytes": OS.get_static_memory_usage()}
	assert(Store._validate_items(data, data.site).ok)
	var original_loot := JSON.stringify(data.site.ground_loot, "", true, true)
	var original_items := JSON.stringify(data.site.item_records, "", true, true)
	var path := SAVE_ROOT + "%d.json" % count
	var start := Time.get_ticks_usec()
	var saved := Store.save(data, path)
	assert(saved.ok, str(saved))
	report.save_ms = (Time.get_ticks_usec() - start) / 1000.0
	var file := FileAccess.open(path, FileAccess.READ)
	report.saved_bytes = file.get_length()
	file.close()
	start = Time.get_ticks_usec()
	var loaded := Store.load_site(path)
	assert(loaded.ok, str(loaded))
	report.load_ms = (Time.get_ticks_usec() - start) / 1000.0
	assert(JSON.stringify(loaded.data.site.ground_loot, "", true, true) == original_loot)
	assert(JSON.stringify(loaded.data.site.item_records, "", true, true) == original_items)
	assert(loaded.data.ground_loot_at.size() == data.ground_loot_at.size())
	assert(loaded.data.ground_loot_at[data.index(setup.shared_cell)].size() == data.ground_loot_at[data.index(setup.shared_cell)].size())
	assert(int(loaded.data.site.next_person_id) == count + 1)
	report.static_memory_with_roundtrip_copy_bytes = OS.get_static_memory_usage()
	# Empty sources must not create phantom bags; a nonempty bag cannot be erased.
	var empty := Runtime.new_item_state("person:1")
	var next_loot := int(data.site.next_loot)
	assert(str(Runtime.leave_ground_loot(data, empty, {}, 1, setup.shared_cell, "cargo", {}, [], 0).code) == "EMPTY")
	assert(int(data.site.next_loot) == next_loot)
	assert(str(Runtime.clear_empty_ground_loot(data, "1").code) == "BUSY")
	# Original Army.clear owns only its existing roster state, never Site loot.
	# This isolated owner check is not the full deployed-army UI retirement test.
	var army := TerrainArmy.new()
	army.data = data
	army.cells.assign([setup.shared_cell])
	army.combat_units.assign([{"person_id": 1}])
	army.clear()
	assert(army.combat_units.is_empty() and army.cells.is_empty())
	assert(JSON.stringify(data.site.ground_loot, "", true, true) == original_loot)
	assert(JSON.stringify(data.site.item_records, "", true, true) == original_items)
	army.free()
	var first: Dictionary = loaded.data.site.ground_loot["1"]
	var shared_before: int = loaded.data.ground_loot_at[int(first.cell)].size()
	assert(Runtime.transfer_items(loaded.data, first, first.cargo, loaded.data.site.depot_items, loaded.data.site.inventory,
		first.cargo, first.item_ids.duplicate(), int(first.version), int(loaded.data.site.depot_items.version), int(loaded.data.site.capacity)).ok)
	assert(Runtime.clear_empty_ground_loot(loaded.data, "1").ok)
	assert(loaded.data.site.ground_loot.size() == count - 1 and loaded.data.ground_loot_at[data.index(setup.shared_cell)].size() == shared_before - 1)
	assert(loaded.data.site.ground_loot.has("2") and Store._validate_items(loaded.data, loaded.data.site).ok)
	if "--boundary" in OS.get_cmdline_user_args():
		# Exact byte-limit fixture, NOT typical content-size/performance evidence.
		# Existing Site ID is a schema-valid string; one ASCII byte adds one byte
		# to the real saved envelope. Never add a production padding field.
		var boundary_path := SAVE_ROOT + "%d_boundary.json" % count
		var original_id := str(data.site.id)
		var padding := Store.MAX_BYTES - int(report.saved_bytes)
		assert(padding > 0)
		data.site.id = original_id + "x".repeat(padding)
		assert(Store.save(data, boundary_path).ok, "Exactly 8 MiB should be admitted")
		file = FileAccess.open(boundary_path, FileAccess.READ)
		assert(file.get_length() == Store.MAX_BYTES)
		file.close()
		var previous_hash := FileAccess.get_sha256(boundary_path)
		data.site.id += "x"
		var rejected := Store.save(data, boundary_path)
		assert(not rejected.ok and str(rejected.code) == "SAVE_TOO_LARGE")
		assert(FileAccess.get_sha256(boundary_path) == previous_hash)
		assert(data.site.ground_loot.size() == count and data.site.item_records.size() == count)
		data.site.id = original_id
		report.boundary = {"synthetic_site_id_padding": true, "accepted_bytes": Store.MAX_BYTES,
			"rejected_bytes": Store.MAX_BYTES + 1, "original_file_hash_preserved": true, "nonempty_containers_preserved": count}
	assert(Time.get_ticks_msec() < deadline)
	_write_report("%d_data" % count, report)
	print("SITE GROUND LOOT SCALE PASS: ", JSON.stringify(report, "", true, true))
	quit(0)
