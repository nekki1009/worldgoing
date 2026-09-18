extends "res://scripts/tests/site_vehicle_route_review_test.gd"
## Fixed cloth is a mounted-only presentation, never an equipment transaction.
## Original TerrainLab generation/items/boarding/Store integration. No GPU proof.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Recipe = preload("res://scripts/terrain_lab/site_wagon_rider_recipe.gd")
const Rider = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
const CLOTH_OUT := "res://output/site_wagon_rider_display_20260918/runtime"

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 50000
	_run.call_deferred()

func _lab() -> TerrainLab:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	return lab

func _state(lab: TerrainLab) -> Dictionary:
	var teams := []
	for team: TerrainArmy in lab.combat_armies:
		teams.append(team.capture_combat_state() if team.combat_enabled else {})
	return {"site": lab.terrain.site.duplicate(true), "teams": teams}

func _settle(team: TerrainArmy) -> void:
	for tick in range(30): team.prepare_combat(1.0 / 30.0)
	assert(team.moving_count() == 0)

func _walk_beside(team: TerrainArmy, index: int, horse: Vector2i) -> bool:
	# Use the original bounded route and original step claims. This is a legal
	# boarding fixture, not evidence that a new autonomous transport order exists.
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var goal := horse + direction
		if team.cells[index] == goal: return true
		team.prepare_combat(1.0 / 30.0)
		var route := team._find_local_route(team.cells[index], goal, 256, false, index)
		if route.size() < 2: continue
		for next: Vector2i in route.slice(1):
			assert(team._reserve_combat_step(index, next), "Original boarding approach step refused")
			_settle(team)
		return team.cells[index] == goal
	return false

func _kit(lab: TerrainLab, team: TerrainArmy, index: int) -> int:
	var row: Dictionary = team.combat_units[index]
	var actual := SiteRuntime.equipment_appearance(lab.terrain, row.item_state, row.appearance)
	var base: Dictionary = TerrainArmy.EquipmentAtlas.female_appearance() if int(actual.body) == 1 else TerrainArmy._combat_bake.manifest.appearance
	var expected := SiteController._initial_uniform(base, team.faction_id)
	assert(not Recipe.matches(row.appearance) and not Recipe.matches(actual))
	assert(actual.parts == expected.parts and actual.get("equipment_dyes", {}) == expected.get("equipment_dyes", {}))
	assert(team.supports_equipment_recipe(actual) and Rider.supports(actual))
	var count := 0
	for slot: String in SiteRuntime.EQUIPMENT_SLOTS:
		if str(expected.parts[slot]) == "none":
			assert(not row.item_state.equipped.has(slot))
			continue
		count += 1
		var item := str(row.item_state.equipped[slot])
		var record: Dictionary = lab.terrain.site.item_records[item]
		var definition: Dictionary = lab.terrain.site.item_definitions[record.definition]
		assert(record.holder == "person:%d" % team.combat_identity(index))
		assert(definition.slot == slot and definition.asset == expected.parts[slot])
		assert(SiteRuntime.item_dye(record, definition) == str(expected.get("equipment_dyes", {}).get(slot, "")))
	assert(row.item_state.item_ids.size() == count and row.item_state.equipped.size() == count)
	assert(TerrainArmy.single_troop_class(team.combat_units, lab.terrain, team._troop_exempt_ids()) == TerrainArmy.TROOP_TYPE_ID)
	return count

func _gear(lab: TerrainLab) -> Dictionary:
	var people := {}
	for team: TerrainArmy in lab.combat_armies:
		for row: Dictionary in team.combat_units:
			people[int(row.person_id)] = {"holder": row.item_state.duplicate(true), "appearance": row.appearance.duplicate(true),
				"actual": team.equipment_appearance(team.index_for_identity(int(row.person_id))).duplicate(true)}
	return {"people": people, "items": lab.terrain.site.item_records.duplicate(true), "definitions": lab.terrain.site.item_definitions.duplicate(true), "next_item": lab.terrain.site.next_item}

func _fixed_frame(actual: Dictionary) -> void:
	var before := actual.duplicate(true)
	var cloth := Recipe.appearance(int(actual.body))
	var sprite := Sprite2D.new()
	root.add_child(sprite)
	for direction: String in ["down", "left", "up", "right"]:
		for moving: bool in [false, true]:
			for sample in range(8 if moving else 1):
				var progress := float(sample) / 8.0
				var displayed := Rider.frame(actual, direction, moving, progress)
				var fixed := Rider.frame(cloth, direction, moving, progress)
				assert(not displayed.is_empty() and not fixed.is_empty())
				assert(displayed.texture == fixed.texture and displayed.anchor == fixed.anchor and displayed.horse_offset == fixed.horse_offset,
					"Every valid real kit must display the same cloth frame for this gender")
				for slot: String in Rider.DyeAtlas.Dye.SLOTS: sprite.set_instance_shader_parameter(slot + "_dye", Vector4.ONE)
				assert(Rider.apply(sprite, actual, displayed))
				if sprite.material != null:
					for slot: String in Rider.DyeAtlas.Dye.SLOTS: assert(sprite.get_instance_shader_parameter(slot + "_dye") == Vector4.ZERO)
	assert(actual == before, "Rendering must not mutate the true appearance or its dyes")
	sprite.queue_free()

func _roundtrip(lab: TerrainLab, name: String) -> void:
	lab.site_controller._capture_positions()
	var items: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var cars: Dictionary = lab.site_controller.vehicles.records().duplicate(true)
	var saved := Store.save(lab.terrain, CLOTH_OUT + "/" + name + ".json")
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(CLOTH_OUT + "/" + name + ".json")
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	assert(lab.terrain.site.item_records == items and lab.site_controller.vehicles.records() == cars)

func _legacy() -> void:
	var lab := _lab()
	var origin := _patch(lab)
	assert(origin != TerrainArmy.INVALID_CELL)
	var team := lab.army
	team.team_id = lab._next_army_identity()
	team.roster_size = 2
	var horse := origin + Vector2i(5, 5)
	var formation: Array[Vector2i] = [horse, horse + Vector2i.DOWN]
	# A real existing legacy team keeps its gear; only its mounted Sprite changes.
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, formation) and team.enable_combat(false, 1))
	team.role = "logistics"
	for row: Dictionary in team.combat_units: row.logistics = true
	var records: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var holder: Dictionary = team.combat_units[0].item_state
	var held_before := holder.duplicate(true)
	assert(not Recipe.matches(team.equipment_appearance(0)) and Rider.supports(team.equipment_appearance(0)))
	assert(team.enable_combat(false, 1)) # Existing rows must not be re-uniformed.
	lab.site_controller.initialize_team_items(team)
	assert(is_same(holder, team.combat_units[0].item_state) and holder == held_before and lab.terrain.site.item_records == records)
	var transport = lab.site_controller.vehicles
	assert(transport.deploy_plan(team, [{"kind": "wagon", "team_id": team.team_id,
		"cell": lab.terrain.index(Vehicles.anchor_from_operator("wagon", horse, Vector2i.RIGHT)),
		"facing": [1, 0], "operator_index": 0}]).ok)
	_roundtrip(lab, "legacy_leather")
	assert(lab.army.combat_units[0].item_state == held_before and lab.terrain.site.item_records == records)
	assert(not Recipe.matches(lab.army.equipment_appearance(0)) and Rider.supports(lab.army.equipment_appearance(0)))
	lab.queue_free()
	await process_frame

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	assert(DirAccess.make_dir_recursive_absolute(CLOTH_OUT) == OK)
	var lab := _lab()
	var ui := lab.site_controller
	var old_items: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var old_holder: Dictionary = lab.character.item_state
	var original_player_items := old_holder.duplicate(true)
	var setup := {"friendly_role": "logistics", "friendly_count": 3, "friendly_wagon_count": 1,
		"enemy_role": "logistics", "enemy_count": 3, "enemy_wagon_count": 1,
		"third_role": "logistics", "third_count": 3, "third_wagon_count": 1,
		"friendly_female_percent": 50, "enemy_female_percent": 50, "third_female_percent": 50,
		"friendly_faction": 0, "enemy_faction": 1, "third_faction": 2}
	var started := lab.start_melee_trial(setup)
	assert(started.ok, str(started))
	# Late append allocation failure must preserve already generated standard gear,
	# physical items, vehicle ownership and every borrowed live holder reference.
	var site_alias := lab.terrain.site
	var record_alias: Dictionary = lab.terrain.site.item_records
	var row_alias: Dictionary = lab.army.combat_units[1]
	var row_holder: Dictionary = row_alias.item_state
	var car_alias: Dictionary = ui.vehicles.records().values()[0]
	var next_item := int(lab.terrain.site.next_item)
	lab.terrain.site.next_item = 2147483646
	var before := _state(lab)
	assert(lab.add_melee_trial_team(setup).code == "DEPLOY_FAILED")
	assert(_state(lab) == before and is_same(site_alias, lab.terrain.site) and is_same(record_alias, lab.terrain.site.item_records))
	assert(is_same(row_alias, lab.army.combat_units[1]) and is_same(row_holder, row_alias.item_state))
	assert(is_same(car_alias, ui.vehicles.records()[car_alias.id]))
	lab.terrain.site.next_item = next_item
	assert(lab.add_melee_trial_team(setup).ok)
	assert(ui.vehicles.records().size() == 3)
	assert(is_same(old_holder, lab.character.item_state) and old_holder == original_player_items)
	for item: String in old_items: assert(lab.terrain.site.item_records[item] == old_items[item])
	var expected_new_items := 0
	for faction in range(3):
		var team: TerrainArmy = lab.combat_armies[faction]
		assert(team.faction_id == faction and team.combat_units.size() == 2)
		var bodies := []
		for index in range(2):
			expected_new_items += _kit(lab, team, index)
			_fixed_frame(team.equipment_appearance(index))
			bodies.append(int(team.combat_units[index].appearance.body))
		bodies.sort()
		assert(bodies == [0, 1])
	assert(lab.terrain.site.item_records.size() == old_items.size() + expected_new_items)
	var equipment_before := _gear(lab)
	var wagon: Dictionary = ui.vehicles.records().values()[0]
	var team := lab.army
	var rider_id := int(wagon.operator_id)
	var rider_index := team.index_for_identity(rider_id)
	assert(rider_index >= 0)
	var rider_holder: Dictionary = team.combat_units[rider_index].item_state
	var vehicle_id := str(wagon.id)
	var horse: Vector2i = ui.vehicles.operator_cell(wagon)
	assert(ui.vehicles.unassign_operator(vehicle_id, rider_id, true).ok)
	_settle(team)
	assert(int(wagon.operator_id) == 0)
	assert(_gear(lab) == equipment_before and is_same(rider_holder, team.combat_units[rider_index].item_state))
	var replacement := 1 - rider_index
	assert(_walk_beside(team, replacement, horse))
	var replacement_id := team.combat_identity(replacement)
	assert(ui.vehicles.assign_operator(vehicle_id, replacement_id, team.combat_identity(team.current_commander), true).ok)
	assert(wagon.move.get("boarding", false) and ui.vehicles.rider_state(replacement_id).is_empty())
	_settle(team)
	assert(int(wagon.operator_id) == replacement_id and team.cells[replacement] == horse and not ui.vehicles.rider_state(replacement_id).is_empty())
	assert(team.combat_units.size() == 2 and _gear(lab) == equipment_before)
	_fixed_frame(team.equipment_appearance(replacement))
	_roundtrip(lab, "mounted_display_three_factions")
	assert(int(ui.vehicles.records()[vehicle_id].operator_id) == replacement_id)
	assert(_gear(lab) == equipment_before, "Store/bind must preserve original equipment, versions and appearance for riders and non-riders")
	for restored: TerrainArmy in lab.combat_armies:
		for index in range(restored.combat_units.size()): _kit(lab, restored, index)
	team = lab.army
	team._soldier_baked_ready = team._load_baked_soldier()
	assert(team._soldier_baked_ready)
	team._rebuild_visual_instances()
	team._set_soldier_frame(replacement, true)
	var original_sprite: Sprite2D = team._sprites[replacement]
	assert(original_sprite != null and original_sprite.has_meta("vehicle_rider_frame"))
	assert(ui.vehicles.unassign_operator(vehicle_id, team.combat_identity(team.current_commander), true).ok)
	team._set_soldier_frame(replacement, true)
	assert(not original_sprite.has_meta("vehicle_rider_frame") and original_sprite.texture != null)
	_settle(team)
	team._set_soldier_frame(replacement, true)
	assert(int(ui.vehicles.records()[vehicle_id].operator_id) == 0 and not original_sprite.has_meta("vehicle_rider_frame"))
	assert(original_sprite.get_meta("equipment_dye_appearance", {}) == team.equipment_appearance(replacement), "Dismount restores the original equipped/dyed foot Sprite")
	assert(_gear(lab) == equipment_before, "Dismount cannot issue, remove, recolour or replace a real item")
	lab.queue_free()
	await process_frame
	await _legacy()
	print("SITE_WAGON_CLOTH_PASS: original three-faction standard gear/dyes untouched; both genders display fixed cloth only while riding; no real item/appearance/version changes; late append rollback/aliases; real different-person boarding; Store/bind; dismount restores original foot Sprite/dyes; legacy gear unchanged")
	quit(0)
