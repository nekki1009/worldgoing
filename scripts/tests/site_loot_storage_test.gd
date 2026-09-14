extends SceneTree

const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "loot-storage-fixture")
	assert(SiteRuntime.initialize_item_storage(data.site).ok)
	var source := SiteRuntime.new_item_state("person:21")
	var cargo := {"wood": 3, "grain": 2, "arrow": 0}
	var original_cargo := cargo
	var sword := SiteRuntime.create_equipment(data, source, "test-sword", {"slot": "weapon", "asset": "longsword_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 21, "weapon")
	var armor := SiteRuntime.create_equipment(data, source, "test-armor", {"slot": "armor", "asset": "armor_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 21, "armor")
	assert(sword.ok and armor.ok and SiteRuntime.carried_size(cargo, source) == 5)
	var second := SiteRuntime.new_item_state("person:22")
	var second_cargo := {}
	var snapshot := JSON.stringify([source, cargo, second, second_cargo, data.site.item_records])
	var rejected := SiteRuntime.transfer_items(data, source, cargo, second, second_cargo, {"wood": 3}, [sword.item_id], int(source.version), 0, 3)
	assert(not rejected.ok and rejected.code == "STORAGE_FULL")
	assert(JSON.stringify([source, cargo, second, second_cargo, data.site.item_records]) == snapshot)
	var previous_version := int(source.version)
	assert(SiteRuntime.transfer_items(data, source, cargo, second, second_cargo, {"wood": 1}, [sword.item_id], previous_version, 0).ok)
	assert(original_cargo.wood == 2 and not source.equipped.has("weapon") and second.equipped.is_empty())
	assert(str(data.site.item_records[sword.item_id].holder) == "person:22")
	assert(not SiteRuntime.transfer_items(data, source, cargo, second, second_cargo, {"wood": 1}, [], previous_version, int(second.version)).ok)
	var fake_source := source.duplicate(true)
	fake_source.item_ids.append(sword.item_id)
	var third := SiteRuntime.new_item_state("person:23")
	var stolen := SiteRuntime.transfer_items(data, fake_source, cargo, third, {}, {}, [sword.item_id], int(fake_source.version), 0)
	assert(not stolen.ok and stolen.code == "STALE_SOURCE")
	var cell := data.spawn_cell
	cargo["arrow"] = 0 # The original ranged release retains a spent zero stack.
	var first_drop := SiteRuntime.leave_ground_loot(data, source, cargo, 21, cell, "remains", cargo, source.item_ids, int(source.version))
	assert(first_drop.ok and cargo.is_empty() and source.item_ids.is_empty() and source.equipped.is_empty())
	assert(not SiteRuntime.leave_ground_loot(data, source, cargo, 21, cell, "remains", {}, [], int(source.version)).ok)
	var second_drop := SiteRuntime.leave_ground_loot(data, second, second_cargo, 22, cell, "sealed", second_cargo.duplicate(), second.item_ids.duplicate(), int(second.version))
	assert(second_drop.ok and data.ground_loot_at[data.index(cell)].size() == 2)
	var first: Dictionary = data.site.ground_loot[first_drop.container_id]
	assert(first.cargo == {"wood": 2, "grain": 2}, "Take-all request may alias source cargo but must not lose resources")
	assert(first.equipped.armor == armor.item_id)
	assert(not SiteRuntime.clear_empty_ground_loot(data, first_drop.container_id).ok)
	assert(SiteStore._validate_items(data, data.site).ok)
	data.site["next_person_id"] = 22
	assert(not SiteStore._validate_person_allocator(data.site).ok)
	data.site.next_person_id = TerrainArmy.PLAYER_MEMBER
	assert(not SiteStore._validate_person_allocator(data.site).ok)
	data.site.next_person_id = 23
	assert(SiteStore._validate_person_allocator(data.site).ok)
	var path := "res://.godot-temp/site_resources_contract/loot_storage.json"
	assert(SiteStore.save(data, path).ok)
	var old_hash := FileAccess.get_sha256(path)
	var loaded := SiteStore.load_site(path)
	assert(loaded.ok)
	assert(loaded.data.site.next_person_id is int and loaded.data.site.next_person_id == 23)
	assert(JSON.stringify(loaded.data.site.ground_loot, "", true) == JSON.stringify(data.site.ground_loot, "", true))
	assert(loaded.data.ground_loot_at[data.index(cell)].size() == 2)
	assert(loaded.data.site.item_records[sword.item_id].original_owner == 21)
	var loaded_first: Dictionary = loaded.data.site.ground_loot[first_drop.container_id]
	assert(loaded_first.version is int and loaded_first.cargo.wood is int)
	assert(SiteRuntime.transfer_items(loaded.data, loaded_first, loaded_first.cargo, loaded.data.site.depot_items, loaded.data.site.inventory, loaded_first.cargo, loaded_first.item_ids, int(loaded_first.version), int(loaded.data.site.depot_items.version), int(loaded.data.site.capacity)).ok)
	assert(SiteStore._validate_items(loaded.data, loaded.data.site).ok)
	var duplicate := data.site.duplicate(true)
	duplicate.ground_loot[second_drop.container_id].item_ids.append(armor.item_id)
	assert(not SiteStore._validate_items(data, duplicate).ok)
	var broken := data.site.duplicate(true)
	broken.item_records[armor.item_id].definition = "missing"
	assert(not SiteStore._validate_items(data, broken).ok)
	broken = data.site.duplicate(true)
	broken.ground_loot[first_drop.container_id].equipped.weapon = armor.item_id
	assert(not SiteStore._validate_items(data, broken).ok)
	broken = data.site.duplicate(true)
	broken.ground_loot[first_drop.container_id].cell = -1
	assert(not SiteStore._validate_items(data, broken).ok)
	data.site.item_records[armor.item_id].definition = "missing"
	assert(not SiteStore.save(data, path).ok and FileAccess.get_sha256(path) == old_hash)
	data.site.item_records[armor.item_id].definition = "test-armor"
	assert(SiteRuntime.transfer_items(data, first, first.cargo, data.site.depot_items, data.site.inventory, first.cargo.duplicate(), first.item_ids.duplicate(), int(first.version), int(data.site.depot_items.version), int(data.site.capacity)).ok)
	assert(SiteRuntime.clear_empty_ground_loot(data, first_drop.container_id).ok)
	assert(data.ground_loot_at[data.index(cell)].size() == 1 and data.site.ground_loot.has(second_drop.container_id))
	data.site["armies"] = [] # Removing a roster never removes unrelated ground containers.
	assert(SiteStore.save(data, path).ok and SiteStore.load_site(path).ok)
	assert(data.site.depot_items.equipped.is_empty())
	var migrated := {}
	assert(SiteRuntime.initialize_item_storage(migrated).ok)
	assert(SiteRuntime.initialize_item_storage(migrated).ok and migrated.item_records.is_empty())
	assert(not SiteRuntime.initialize_item_storage({"ground_loot": {}}).ok)
	migrated.erase("item_records")
	assert(not SiteRuntime.initialize_item_storage(migrated).ok)
	# Retired roster food remains physical stock; it may not be inherited by an ID reuse.
	data.site["team_supply"] = {"7": _supply_entry()}
	data.site.team_supply["7"].inventory.grain = 4
	assert(data.site.team_supply["7"].inventory.keys()[0] is StringName, "Godot dot assignment uses an interned resource key")
	data.site.team_supply["7"].sustain.open_rations = 0.25
	data.site["army_next_team"] = 8
	var orphan_save := SiteStore.save(data, path)
	if not orphan_save.ok:
		push_error("Orphan supply save rejected: " + str(orphan_save) + " entry=" + str(data.site.team_supply["7"]))
		quit(1)
		return
	var with_supply := SiteStore.load_site(path)
	assert(with_supply.ok and with_supply.data.site.team_supply["7"].inventory.grain is int)
	assert(with_supply.data.site.team_supply["7"].sustain.open_rations == 0.25)
	old_hash = FileAccess.get_sha256(path)
	data.site.team_supply["7"].delivery = {"unfinished": true}
	var busy := SiteStore.save(data, path)
	assert(not busy.ok and busy.code == "BUSY" and FileAccess.get_sha256(path) == old_hash)
	data.site.team_supply["7"].delivery = {}
	data.site.army_next_team = 7
	assert(not SiteStore._validate_supply(data.site).ok)
	data.site.army_next_team = 8
	data.site.team_supply["7"].sustain.at = 1.0
	assert(not SiteStore._validate_supply(data.site).ok)
	data.site.team_supply["7"].sustain.at = 0.0
	var ownership := {"actors": {"player": {"person_id": 1, "hp": 100.0}}, "armies": [
		{"roster_version": 1, "team_id": 1, "units": []}, {"roster_version": 1, "team_id": 2, "units": []}],
		"minute": 0, "phase": 0.0, "army_next_team": 3, "team_supply": {"1": _supply_entry(), "2": _supply_entry()}}
	# Isolated feeding-owner schema check, not a valid combat snapshot fixture.
	for entry: Dictionary in ownership.team_supply.values():
		assert(Sustain.add_members(entry.sustain, {1: {"hp": 100.0}}, [1]).ok)
		entry.life_checkpoint["1"] = 0
	var duplicate_owner := SiteStore._validate_supply(ownership)
	assert(not duplicate_owner.ok and duplicate_owner.message.contains("重複供養"))
	var lagged_team: Dictionary = ownership.duplicate(true)
	lagged_team.phase = 1.0 / 60.0
	assert(SiteStore._validate_supply(lagged_team).message.contains("時鐘落後"))
	ownership.team_supply["2"] = _supply_entry()
	var private_meal := Sustain.create()
	assert(Sustain.add_members(private_meal, {1: {"hp": 100.0}}, [1]).ok)
	ownership["person_supply"] = {"1": private_meal}
	assert(not SiteStore._validate_supply(ownership).ok, "Private and team feeding cannot duplicate one original person")
	ownership.team_supply["1"] = _supply_entry()
	assert(SiteStore._validate_supply(ownership).ok)
	var decoded_meal: Dictionary = JSON.parse_string(JSON.stringify(private_meal))
	SiteStore._normalize_sustain(decoded_meal)
	assert(decoded_meal.version is int and decoded_meal.cohorts[0].ids[0] is int)
	ownership.person_supply["2"] = Sustain.create()
	assert(not SiteStore._validate_supply(ownership).ok, "Unknown private food owner must reject")
	ownership.person_supply.erase("2")
	private_meal.at = 1.0
	private_meal.cohorts[0].meal_until = 1.0
	assert(SiteStore._validate_supply(ownership).message.contains("時鐘超前"))
	_check_supply_clock_save()
	# No actor Nodes, images, or per-frame simulation; stress only sparse data/index and JSON.
	for amount: int in [1000, 9000]:
		var stress := TerrainGenerator.generate(0, 582)
		SiteEnvironment.initialize(stress, "loot-stress-%d" % amount)
		assert(SiteRuntime.initialize_item_storage(stress.site).ok)
		var started := Time.get_ticks_usec()
		for index in range(amount):
			var person := SiteRuntime.new_item_state("person:" + str(index + 100))
			var goods := {"wood": 1}
			assert(SiteRuntime.leave_ground_loot(stress, person, goods, index + 100, stress.spawn_cell, "cargo", {"wood": 1}, [], 0).ok)
		var create_ms := float(Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		assert(SiteStore._validate_items(stress, stress.site).ok)
		SiteRuntime.rebuild_loot_index(stress)
		var validate_index_ms := float(Time.get_ticks_usec() - started) / 1000.0
		assert(stress.ground_loot_at[stress.index(stress.spawn_cell)].size() == amount)
		var stress_path := "res://.godot-temp/site_resources_contract/loot_storage_%d.json" % amount
		started = Time.get_ticks_usec()
		assert(SiteStore.save(stress, stress_path).ok)
		var save_ms := float(Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		var restored := SiteStore.load_site(stress_path)
		assert(restored.ok and restored.data.site.ground_loot.size() == amount)
		var load_ms := float(Time.get_ticks_usec() - started) / 1000.0
		var saved_file := FileAccess.open(stress_path, FileAccess.READ)
		var saved_bytes := saved_file.get_length()
		saved_file.close()
		print("LOOT DATA %d: create_ms=%.3f validate_index_ms=%.3f save_ms=%.3f load_ms=%.3f file_bytes=%d" % [amount, create_ms, validate_index_ms, save_ms, load_ms, saved_bytes])
	print("SITE LOOT STORAGE PASS: atomic actual-item/resource transfer, stale/capacity refusal, single remaining drop, save uniqueness, empty-only cleanup, legacy-empty migration, orphan supply stock and unique feeding owners; data-only, not interactive looting or battle FPS")
	quit(0)

func _supply_entry() -> Dictionary:
	return {"version": 1, "sustain": Sustain.create(), "inventory": {}, "training_order": false,
		"training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": {}}

func _check_supply_clock_save() -> void:
	var data := TerrainGenerator.generate(0, 583)
	SiteEnvironment.initialize(data, "supply-clock-save")
	var player := TerrainTestCharacter.new()
	var worker := TerrainTestNPC.new()
	player.person_id = 1
	worker.person_id = 2
	player.data = data
	worker.data = data
	assert(player.place(data.spawn_cell, true))
	var second_cell := Vector2i(-1, -1)
	for index in range(data.size.x * data.size.y):
		var cell := data.cell_from_index(index)
		if cell != data.spawn_cell and data.is_walkable(cell):
			second_cell = cell
			break
	assert(worker.place(second_cell, true))
	data.site.player_cell = data.index(player.terrain_cell)
	data.site.worker.cell = data.index(worker.terrain_cell)
	data.site["actors"] = {"player": player.capture_state(), "npc": worker.capture_state()}
	data.site.phase = 1.0 / 60.0
	var personal := Sustain.create(1.0)
	assert(Sustain.add_members(personal, {1: {"hp": player.hp}}, [1]).ok)
	data.site["person_supply"] = {"1": personal}
	var path := "res://.godot-temp/site_resources_contract/supply_clock_boundary.json"
	var saved := SiteStore.save(data, path)
	assert(saved.ok, str(saved))
	assert(SiteStore.load_site(path).ok)
	var original_hash := FileAccess.get_sha256(path)
	personal.at = 0.0 # Still structurally valid, but lags one real Site second.
	var rejected := SiteStore.save(data, path)
	assert(not rejected.ok and rejected.message.contains("時鐘落後"))
	assert(FileAccess.get_sha256(path) == original_hash)
	var decoded := SiteStore._read(path)
	assert(decoded.ok)
	var payload: Dictionary = decoded.payload
	payload.state.person_supply["1"].at = 0.0
	var body := JSON.stringify(payload, "", true, true)
	var malformed := FileAccess.open(path + ".lag", FileAccess.WRITE)
	malformed.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	malformed.close()
	var loaded := SiteStore.load_site(path + ".lag")
	assert(not loaded.ok and loaded.message.contains("時鐘落後") and not loaded.has("data"))
	assert(FileAccess.get_sha256(path) == original_hash and personal.at == 0.0 and player.hp == 100.0)
	personal.at = 1.0 - 0.000005
	assert(SiteStore._validate_supply(data.site).ok, "Preserve the existing 1e-5 rounding tolerance")
	# Empty private stock has no elapsed feeding cohort to skip or refill.
	personal.cohorts = []
	personal.at = 0.0
	personal.open_rations = 0.25
	assert(SiteStore.save(data, path).ok)
	loaded = SiteStore.load_site(path)
	assert(loaded.ok and loaded.data.site.person_supply["1"].at == 0.0)
	assert(loaded.data.site.person_supply["1"].open_rations == 0.25)
	player.free()
	worker.free()
