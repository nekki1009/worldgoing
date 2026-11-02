extends SceneTree
## Original person jobs and inventory/vehicle owners; rendering is verified separately.
const PersonTest = preload("res://scripts/tests/site_person_actions_test.gd")

class CrowdFixture extends RefCounted:
	var active := true
	func contains_person(identity: int) -> bool: return identity == 3
	func person_owner(_identity: int) -> Variant: return null # No crowd owner registered in this fixture; real lookup misses too.
	func reserves_cell(_cell: Vector2i) -> bool: return false

class Fixture extends Node2D:
	var source := PersonTest.Fixture.new()
	var terrain: TerrainData = source.terrain
	var character: TerrainTestCharacter = source.character
	var npc: TerrainTestNPC = source.npc
	var army: TerrainArmy = source.army
	var combat_armies: Array[TerrainArmy] = [army]
	var combat_actors: Array[TerrainTestCharacter] = [character, npc]
	var crowd_site: RefCounted
	var site_controller := SiteController.new()
	var actions: SitePersonActions = source.actions
	var cells: Array[int] = []
	func _init() -> void:
		terrain.spawn_cell = Vector2i(2, 2)
		SiteEnvironment.initialize(terrain, "tent-logistics-contract")
		terrain.resource_base.clear()
		terrain.site.changes.clear()
		terrain.flags.fill(TerrainData.Flag.WALKABLE)
		terrain.height_levels.fill(0)
		terrain.ramp_edges.fill(0)
		terrain.water_kind.fill(0)
		terrain.water_body.fill(-1)
		terrain.surface_types.fill(TerrainData.Surface.GRASS)
		terrain.foundation.fill(80)
		terrain.site.inventory = {"cloth": 8, "wood": 8, "fiber": 8, "tools": 1}
		terrain.site.depot_cell = terrain.index(Vector2i(4, 4))
		assert(SiteRuntime.initialize_item_storage(terrain.site).ok)
		SiteEnvironment.rebuild_indexes(terrain)
		character.terrain_cell = Vector2i(1, 1)
		npc.terrain_cell = Vector2i(1, 2)
		character.ammo_inventory = terrain.site.manual.cargo
		npc.ammo_inventory = terrain.site.worker.cargo
		army.team_id = 1
		army.roster_size = 1
		army.current_commander = 0
		army.formal_commander = 0
		army.role = "logistics"
		army.combat_units[0].merge({"member": true, "present": true, "military_role": "officer", "logistics": true})
		source.controlled_id = 3
		move_person(Vector2i(4, 5))
		site_controller.lab = self
		site_controller.person_actions = actions
		site_controller.work_team.init(self)
		site_controller.vehicles.init(site_controller)
		actions.init(self)
		var layout := SiteRuntime.building_cells(terrain, "tent", Vector2i(5, 5), Vector2i(3, 3))
		assert(layout.ok)
		cells.assign(layout.cells)
	func _combat_target(identity: int) -> Dictionary:
		var index := army.index_for_identity(identity)
		if index >= 0: return {"owner": army, "unit": index, "cell": army.cells[index], "hp": army.combat_units[index].hp}
		return source._combat_target(identity)
	func _original_person_target(identity: int) -> Dictionary:
		return _combat_target(identity)
	func controlled_person_id() -> int: return source.controlled_id
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return source.threatened
	func move_person(cell: Vector2i) -> void:
		army.cells[0] = cell
		army._cell_owners.clear()
		army._cell_owners[cell] = 0
	func cargo() -> Dictionary: return army.combat_units[0].cargo
	func holder() -> Dictionary: return army.combat_units[0].item_state
	func goods() -> Array:
		return [terrain.site.inventory.duplicate(true), terrain.site.depot_items.duplicate(true), cargo().duplicate(true),
			holder().duplicate(true), terrain.site.features.duplicate(true), terrain.site.next_feature, terrain.site.vehicles.duplicate(true)]
	func finish() -> Array[Dictionary]:
		actions.advance(60.0)
		return actions.settle_after_contacts()
	func provide_paid_package() -> void:
		var before: Dictionary = terrain.site.inventory.duplicate()
		assert(actions.begin_ranged_craft(3, "camp_tent").ok)
		actions.advance(150.0)
		assert(terrain.site.inventory == before)
		var results := actions.settle_after_contacts()
		assert(results.size() == 1 and results[0].ok)
		assert(terrain.site.inventory.camp_tent == 1 and terrain.site.inventory.cloth == before.cloth - 4)
		var collected := actions.begin_loot(3, "depot", "depot", {"camp_tent": 1}, [])
		assert(collected.ok)
		assert(finish()[0].ok and cargo().camp_tent == 1)
	func deploy() -> String:
		assert(actions.begin_tent_deploy(3, cells).ok)
		var results := finish()
		assert(results.size() == 1 and results[0].ok, str(results))
		return str(results[0].feature)
	func close() -> void:
		actions.cancel(3)
		site_controller.work_team.lab = null
		site_controller.vehicles.controller = null
		site_controller.vehicles.lab = null
		site_controller.lab = null
		site_controller.free()
		source.close()
		queue_free()

var completed := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(35.0).timeout.connect(func() -> void: quit(1))
	_paid_roundtrip()
	for reason: String in ["cancel", "hit", "ko", "move", "control", "logistics", "holder", "cargo", "version", "site", "occupied", "crowd"]:
		_deploy_interruption(reason)
	_pack_revalidation()
	_vehicle_transfers()
	_competing_original_people()
	assert(completed == 16, "Every tent logistics contract must finish")
	await process_frame
	print("SITE_TENT_LOGISTICS_PASS: paid camp-tent craft/collection, original 30-second deploy/pack post-contact commit, cancellation/hit/KO/movement/control/logistics/holder/cargo/version/site/occupancy/Crowd refusal, pack capacity/occupants, original vehicle-person cargo/version/authority/distance conservation; no native concurrent jobs or visual claim")
	quit(0)

func _paid_roundtrip() -> void:
	var f := Fixture.new()
	assert(not f.terrain.site.inventory.has("camp_tent") and f.cargo().is_empty(), "Formal initialization never seeds a tent package")
	f.provide_paid_package()
	var before := f.goods()
	assert(f.actions.begin_tent_deploy(3, f.cells, 2).ok)
	assert(not f.actions.begin_tent_deploy(3, f.cells, 2).ok and not f.actions.save_guard().ok)
	assert(f.goods() == before, "Starting twice must not consume or mint a package")
	f.actions.advance(60.0)
	assert(f.goods() == before, "Elapsed work waits for original contact settlement")
	var result := f.actions.settle_after_contacts()
	assert(result.size() == 1 and result[0].ok and f.actions.save_guard().ok)
	var key := str(result[0].feature)
	assert(not f.cargo().has("camp_tent") and f.terrain.site.features.size() == 1)
	assert(int(f.terrain.site.features[key].quarter) == 2 and not bool(f.terrain.site.features[key].solid))
	assert(f.actions.settle_after_contacts().is_empty())
	before = f.goods()
	assert(f.actions.begin_tent_pack(3, key).ok)
	assert(f.goods() == before and not f.actions.begin_tent_pack(3, key).ok)
	assert(f.finish()[0].ok and f.cargo().camp_tent == 1 and f.terrain.site.features.is_empty())
	assert(not f.actions.begin_tent_pack(3, key).ok and f.actions.settle_after_contacts().is_empty())
	f.close()
	completed += 1

func _deploy_interruption(reason: String) -> void:
	var f := Fixture.new()
	f.provide_paid_package()
	assert(f.actions.begin_tent_deploy(3, f.cells).ok)
	f.actions.advance(60.0)
	match reason:
		"cancel": assert(f.actions.cancel(3).ok)
		"hit": f.army.combat_units[0].hit_revision += 1
		"ko": f.army.combat_units[0].ko = 10.0
		"move": f.move_person(Vector2i(3, 5))
		"control": f.source.controlled_id = 2
		"logistics": f.army.combat_units[0].logistics = false
		"holder": f.army.combat_units[0].item_state = f.holder().duplicate(true)
		"cargo": f.army.combat_units[0].cargo = f.cargo().duplicate(true)
		"version": f.holder().version += 1
		"site": f.terrain.site = f.terrain.site.duplicate(true)
		"occupied": f.character.terrain_cell = Vector2i(5, 5)
		"crowd": f.crowd_site = CrowdFixture.new()
	var before := f.goods()
	var results := f.actions.settle_after_contacts()
	assert(results.is_empty() if reason == "cancel" else results.size() == 1 and not results[0].ok, reason)
	assert(f.goods() == before and f.cargo().camp_tent == 1 and f.terrain.site.features.is_empty(), reason)
	assert(f.actions.save_guard().ok and f.actions.settle_after_contacts().is_empty())
	f.close()
	completed += 1

func _pack_revalidation() -> void:
	var f := Fixture.new()
	f.provide_paid_package()
	var key := f.deploy()
	f.character.terrain_cell = Vector2i(6, 6)
	var before := f.goods()
	assert(not f.actions.begin_tent_pack(3, key).ok and f.goods() == before, "An actual occupant prevents pack")
	f.character.terrain_cell = Vector2i(1, 1)
	f.cargo().wood = 20
	before = f.goods()
	assert(not f.actions.begin_tent_pack(3, key).ok and f.goods() == before, "Pack cannot exceed original 20-piece personal cargo")
	f.cargo().erase("wood")
	assert(f.actions.begin_tent_pack(3, key).ok)
	f.actions.advance(60.0)
	f.character.terrain_cell = Vector2i(5, 5)
	before = f.goods()
	var results := f.actions.settle_after_contacts()
	assert(results.size() == 1 and not results[0].ok and f.goods() == before, "New final-contact occupancy prevents pack without returning a package")
	f.character.terrain_cell = Vector2i(1, 1)
	assert(f.actions.begin_tent_pack(3, key).ok and f.finish()[0].ok)
	assert(f.cargo().camp_tent == 1 and f.terrain.site.features.is_empty())
	f.close()
	completed += 1

func _vehicle_transfers() -> void:
	var f := Fixture.new()
	f.provide_paid_package()
	var v: SiteVehicleTransport = f.site_controller.vehicles
	# Explicit fixture vehicle; all transfers use the production owner/API.
	f.terrain.site.vehicles["1"] = {"id": "1", "kind": "cart", "cell": f.terrain.index(Vector2i(3, 5)), "facing": [1, 0],
		"team_id": 1, "operator_id": 0, "holder": SiteRuntime.new_item_state("vehicle:1"), "cargo": {}, "move": {}, "stop_pending": false}
	var car: Dictionary = f.terrain.site.vehicles["1"]
	var transfer := v.transfer("person:3", "1", {"camp_tent": 1}, [], int(f.holder().version), int(car.holder.version), 3)
	assert(transfer.ok and not f.cargo().has("camp_tent") and car.cargo.camp_tent == 1)
	var before := f.goods()
	assert(not v.transfer("1", "person:3", {"camp_tent": 1}, [], int(car.holder.version) - 1, int(f.holder().version), 3).ok)
	assert(f.goods() == before)
	f.army.combat_units[0].ko = 10.0
	assert(not v.transfer("1", "person:3", {"camp_tent": 1}, [], int(car.holder.version), int(f.holder().version), 3).ok and f.goods() == before)
	f.army.combat_units[0].ko = 0.0
	f.crowd_site = CrowdFixture.new()
	assert(v.transfer("1", "person:3", {"camp_tent": 1}, [], int(car.holder.version), int(f.holder().version), 3).code == "CROWD_ACTIVE" and f.goods() == before)
	f.crowd_site = null
	f.cargo().wood = 20
	before = f.goods()
	assert(not v.transfer("1", "person:3", {"camp_tent": 1}, [], int(car.holder.version), int(f.holder().version), 3).ok and f.goods() == before)
	f.cargo().erase("wood")
	f.move_person(Vector2i(8, 8))
	before = f.goods()
	assert(not v.transfer("1", "person:3", {"camp_tent": 1}, [], int(car.holder.version), int(f.holder().version), 3).ok and f.goods() == before)
	f.move_person(Vector2i(4, 5))
	f.source.controlled_id = 2
	before = f.goods()
	assert(not v.transfer("1", "person:3", {"camp_tent": 1}, [], int(car.holder.version), int(f.holder().version), 2).ok and f.goods() == before)
	f.source.controlled_id = 3
	assert(v.transfer("1", "person:3", {"camp_tent": 1}, [], int(car.holder.version), int(f.holder().version), 3).ok)
	assert(f.cargo().camp_tent == 1 and not car.cargo.has("camp_tent"))
	before = f.goods()
	assert(not v.transfer("1", "person:3", {"camp_tent": 1}, [], int(car.holder.version), int(f.holder().version), 3).ok and f.goods() == before)
	var key := f.deploy()
	assert(f.actions.begin_tent_pack(3, key).ok and f.finish()[0].ok and f.cargo().camp_tent == 1)
	f.close()
	completed += 1

func _competing_original_people() -> void:
	var f := Fixture.new()
	f.provide_paid_package()
	var row: Dictionary = f.army.combat_units[0].duplicate(true)
	row.person_id = 4
	row.item_state = SiteRuntime.new_item_state("person:4")
	row.cargo = {}
	f.army.combat_units.append(row)
	f.army.cells.append(Vector2i(3, 4))
	f.army.moving_to.append(TerrainArmy.INVALID_CELL)
	f.army.roster_size = 2
	f.army._cell_owners[Vector2i(3, 4)] = 1
	assert(f.actions.begin_ranged_craft(4, "camp_tent").ok)
	f.actions.advance(150.0)
	assert(f.actions.settle_after_contacts()[0].ok)
	assert(f.actions.begin_loot(4, "depot", "depot", {"camp_tent": 1}, []).ok)
	assert(f.finish()[0].ok and row.cargo.camp_tent == 1)
	f.army._cell_owners.erase(Vector2i(3, 4))
	f.army.cells[1] = Vector2i(4, 6)
	f.army._cell_owners[Vector2i(4, 6)] = 1
	assert(f.actions.begin_tent_deploy(3, f.cells).ok and f.actions.begin_tent_deploy(4, f.cells).ok)
	var results := f.finish()
	assert(results.size() == 2 and results[0].ok and not results[1].ok, "Only one original job can commit the shared footprint")
	assert(f.terrain.site.features.size() == 1 and not f.cargo().has("camp_tent") and row.cargo.camp_tent == 1)
	var key := str(results[0].feature)
	assert(f.actions.begin_tent_pack(3, key).ok and f.actions.begin_tent_pack(4, key).ok)
	results = f.finish()
	assert(results.size() == 2 and results[0].ok and not results[1].ok, "Only one original person receives the same packed tent")
	assert(f.terrain.site.features.is_empty() and f.cargo().camp_tent == 1 and row.cargo.camp_tent == 1)
	assert(f.actions.settle_after_contacts().is_empty() and f.actions.save_guard().ok)
	f.close()
	completed += 1
