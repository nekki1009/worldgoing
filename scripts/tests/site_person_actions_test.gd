extends SceneTree

const Actions = preload("res://scripts/terrain_lab/site_person_actions.gd")

class Fixture extends RefCounted:
	var terrain := TerrainData.new()
	var character := TerrainTestCharacter.new()
	var npc := TerrainTestNPC.new()
	var army := TerrainArmy.new()
	var actions := Actions.new()
	var threatened := false
	var controlled_id := 1
	var removal_allowed := true
	var captivity_allowed := true
	var changed: Array[int] = []
	var supply_commits: Array = []
	var ransom_source: Dictionary = {"grain": 100}
	var ransom_destination: Dictionary = {}
	var ransom_revisions := [0, 0]
	var ransom_alias := false
	func _init() -> void:
		terrain.allocate(Vector2i(12, 12))
		terrain.flags.fill(TerrainData.Flag.WALKABLE)
		terrain.site = {"minute": 0, "phase": 0.0, "paused": false, "manual": {"target": "", "cargo": {}}, "worker": {"target": "", "cargo": {}}}
		assert(SiteRuntime.initialize_item_storage(terrain.site).ok)
		character.person_id = 1
		npc.person_id = 2
		character.data = terrain
		npc.data = terrain
		character.terrain_cell = Vector2i(4, 4)
		npc.terrain_cell = Vector2i(5, 4)
		character.item_state = SiteRuntime.new_item_state("person:1")
		npc.item_state = SiteRuntime.new_item_state("person:2")
		character.ammo_inventory = terrain.site.manual.cargo
		npc.ammo_inventory = terrain.site.worker.cargo
		army.data = terrain
		army.faction_id = 0
		army.combat_enabled = true
		army.combat_units = [{"person_id": 3, "hp": 100.0, "ko": 0.0, "captive": false, "departed": false,
			"pose": "idle", "attack": false, "fatigue": 0.0, "fatigue_rest": 0.0, "work_resting": false,
			"hit_revision": 0, "cargo": {}, "item_state": SiteRuntime.new_item_state("person:3")}]
		army.cells = [Vector2i(5, 5)]
		army.moving_to = [Vector2i(-1, -1)]
		actions.init(self)
		actions.equipment_removal_guard = func(_person_id: int, _ids: Array) -> Dictionary:
			return SiteRuntime.ok() if removal_allowed else SiteRuntime.fail("UNSUPPORTED")
		actions.equipment_changed = func(person_id: int) -> void: changed.append(person_id)
		actions.captivity_change_guard = func(_target: int, _captor: int, _capturing: bool) -> Dictionary:
			return SiteRuntime.ok() if captivity_allowed else SiteRuntime.fail("SUPPLY")
		actions.captivity_supply_commit = func(target: int, captor: int, capturing: bool) -> void:
			assert(bool(_combat_target(target).owner.captive) == capturing)
			supply_commits.append([target, captor, capturing])
		actions.captivity_changed = func(_target: int, _captor: int, _capturing: bool) -> void: pass
		actions.ransom_exchange_query = func(_payer: int, _target: int, _representative: int) -> Dictionary:
			return SiteRuntime.ok("原隊伍食物庫存", {"source": ransom_source,
				"destination": ransom_source if ransom_alias else ransom_destination,
				"source_owner": "team:1", "destination_owner": "team:2",
				"source_revision": ransom_revisions[0], "destination_revision": ransom_revisions[1]})
		actions.ransom_exchange_committed = func(_query: Dictionary) -> void:
			ransom_revisions[0] += 1
			ransom_revisions[1] += 1
	func _combat_target(identity: int) -> Dictionary:
		for actor: TerrainTestCharacter in [character, npc]:
			if actor.person_id == identity:
				return {"owner": actor, "unit": -1, "cell": actor.terrain_cell, "hp": actor.hp}
		if identity == 3:
			return {"owner": army, "unit": 0, "cell": army.cells[0], "hp": army.combat_units[0].hp}
		return {}
	func controlled_person_id() -> int:
		return controlled_id
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return threatened
	func equip(slot: String, held_by: int = 2) -> String:
		var person: Variant = character if held_by == 1 else npc
		var definition := {"slot": slot, "asset": slot + "_fixture", "tint": [1.0, 1.0, 1.0, 1.0]}
		var result := SiteRuntime.create_equipment(terrain, person.item_state, slot + "_fixture", definition, held_by, slot)
		assert(result.ok)
		return str(result.item_id)
	func close() -> void:
		actions.lab = null
		actions.equipment_removal_guard = Callable()
		actions.equipment_changed = Callable()
		actions.captivity_change_guard = Callable()
		actions.captivity_supply_commit = Callable()
		actions.captivity_changed = Callable()
		actions.ransom_exchange_query = Callable()
		actions.ransom_exchange_committed = Callable()
		character.free()
		npc.free()
		army.free()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_check_loot()
	_check_interruptions()
	_check_fatigue_and_race()
	_check_captivity()
	_check_escape_and_ransom()
	print("SITE PERSON ACTIONS PASS: original cargo/item owners, KO/ground loot, versions, final-contact rejection, capacity, 80/50 work, capture/sealed/ally-unbind, 30s escape, 100-ration ransom; no UI or equipment rendering claim")
	quit(0)

func _check_loot() -> void:
	var fixture := Fixture.new()
	var actions := fixture.actions
	var source: Dictionary = fixture.terrain.site.worker.cargo
	var cargo: Dictionary = fixture.terrain.site.manual.cargo
	source["wood"] = 3
	var sword := fixture.equip("weapon")
	var armor := fixture.equip("armor")
	assert(not actions.lootable(1, "person", "2").ok, "Awake bodies are not loot sources")
	fixture.npc.knockout_left = 30.0
	var queried := actions.lootable(1, "person", "2")
	assert(queried.ok and queried.equipped.weapon == sword)
	queried.resources.clear()
	assert(source.wood == 3, "A panel cannot mutate original cargo")
	assert(not actions.begin_loot(1, "person", "2", {"wood": 1}, [sword]).ok)
	fixture.removal_allowed = false
	assert(not actions.begin_loot(1, "person", "2", {}, [sword]).ok)
	fixture.removal_allowed = true
	assert(actions.begin_loot(1, "person", "2", {}, [sword]).seconds == 5.0)
	assert(not actions.save_guard().ok and not fixture.terrain.site.has("person_actions"))
	actions.advance(4.999)
	assert(actions.settle_after_contacts().is_empty() and fixture.npc.item_state.item_ids.has(sword))
	actions.advance(0.001)
	assert(actions.settle_after_contacts()[0].ok)
	assert(actions.settle_after_contacts().is_empty(), "Duplicate finish never repeats transfers")
	assert(not fixture.npc.item_state.equipped.has("weapon") and fixture.npc.item_state.equipped.armor == armor)
	assert(fixture.character.item_state.item_ids == [sword] and fixture.character.item_state.equipped.is_empty())
	assert(is_same(fixture.character.ammo_inventory, cargo) and is_same(fixture.npc.ammo_inventory, source))
	assert(actions.begin_loot(1, "person", "2", {"wood": 3}, []).seconds == 2.6)
	fixture.terrain.site.paused = true
	actions.advance(100.0)
	assert(actions.job_for(1).elapsed == 0.0)
	fixture.terrain.site.paused = false
	actions.advance(2.6)
	assert(actions.settle_after_contacts()[0].ok and cargo.wood == 3 and source.is_empty())
	assert(actions.save_guard().ok and not actions.begin_loot(1, "person", "2", {}, [sword]).ok)
	var drop := SiteRuntime.leave_ground_loot(fixture.terrain, fixture.npc.item_state, source, 2, fixture.npc.terrain_cell, "remains", {}, [armor], int(fixture.npc.item_state.version))
	assert(drop.ok)
	assert(actions.begin_loot(1, "ground", drop.container_id, {}, [armor]).ok)
	fixture.removal_allowed = false
	actions.advance(5.0)
	assert(not actions.settle_after_contacts()[0].ok, "Corpse worn gear uses original-owner removal guard")
	fixture.removal_allowed = true
	assert(actions.begin_loot(1, "ground", drop.container_id, {}, [armor]).ok)
	actions.advance(5.0)
	assert(actions.settle_after_contacts()[0].ok and fixture.terrain.site.ground_loot.is_empty())
	fixture.close()

func _check_interruptions() -> void:
	for reason: String in ["wake", "death", "source_hit", "executor_hit", "move", "captive", "version", "full", "wall"]:
		var fixture := Fixture.new()
		fixture.npc.knockout_left = 30.0
		fixture.terrain.site.worker.cargo["wood"] = 2
		assert(fixture.actions.begin_loot(1, "person", "2", {"wood": 1}, []).ok)
		fixture.actions.advance(3.0)
		match reason:
			"wake": fixture.npc.knockout_left = 0.0
			"death": fixture.npc.apply_contact({"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
			"source_hit": fixture.npc.apply_contact({"result": {"hp": 0.0, "stun": 1.0, "guard_break": false}, "shield": false})
			"executor_hit": fixture.character.apply_contact({"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
			"move": fixture.character.terrain_cell = Vector2i(4, 5)
			"captive": fixture.npc.captive = true
			"version": fixture.npc.item_state.version += 1
			"full": fixture.terrain.site.manual.cargo["stone"] = 20
			"wall": fixture.terrain.height_levels[fixture.terrain.index(fixture.npc.terrain_cell)] = 2
		var results := fixture.actions.settle_after_contacts()
		assert(results.size() == 1 and not results[0].ok, reason)
		assert(fixture.terrain.site.worker.cargo.wood == 2 and not fixture.terrain.site.manual.cargo.has("wood"), reason)
		fixture.close()

func _check_fatigue_and_race() -> void:
	var fixture := Fixture.new()
	var actions := fixture.actions
	fixture.npc.knockout_left = 30.0
	fixture.terrain.site.worker.cargo["wood"] = 3
	assert(actions.begin_loot(1, "person", "2", {"wood": 1}, []).ok)
	assert(actions.begin_loot(3, "person", "2", {"wood": 1}, []).ok)
	actions.advance(3.0)
	var results := actions.settle_after_contacts()
	assert(results.size() == 2 and results[0].ok and not results[1].ok)
	assert(fixture.terrain.site.worker.cargo.wood == 2 and fixture.army.combat_units[0].cargo.is_empty())
	var unit: Dictionary = fixture.army.combat_units[0]
	unit.fatigue = 80.0
	assert(actions.begin_loot(3, "person", "2", {"wood": 1}, []).ok)
	assert(actions.advance(10.0).handled_seconds.is_empty() and actions.job_for(3).paused == "REST")
	unit.fatigue = 50.1
	actions.advance(1.0)
	assert(actions.job_for(3).elapsed == 0.0)
	unit.fatigue = 50.0
	fixture.threatened = true
	actions.advance(1.0)
	assert(actions.job_for(3).paused == "THREAT" and not unit.work_resting)
	fixture.threatened = false
	var handled: Dictionary = actions.advance(1.0).handled_seconds
	assert(handled[3] > 0 and unit.fatigue > 50.0 and unit.fatigue_rest == 0.0)
	assert(actions.job_for(3).elapsed > 0.0 and actions.job_for(3).elapsed < 1.0)
	assert(actions.cancel(3).ok and not actions.is_busy(3))
	assert(actions.begin_loot(3, "person", "2", {"wood": 1}, []).ok)
	actions.advance(3.0)
	fixture.threatened = true
	assert(actions.settle_after_contacts().is_empty() and actions.job_for(3).elapsed == 0.0)
	assert(fixture.terrain.site.worker.cargo.wood == 2, "A new same-step threat beats NPC pickup completion")
	fixture.threatened = false
	assert(actions.cancel(3).ok)
	unit.fatigue = 79.999
	unit.work_resting = false
	assert(actions.begin_loot(3, "person", "2", {"wood": 1}, []).ok)
	handled = actions.advance(10.0).handled_seconds
	assert(handled[3] < 1.0 and unit.fatigue == 80.0 and unit.work_resting)
	assert(actions.job_for(3).paused == "REST" and fixture.terrain.site.worker.cargo.wood == 2)
	fixture.close()

func _check_captivity() -> void:
	var fixture := Fixture.new()
	var actions := fixture.actions
	fixture.npc.knockout_left = 30.0
	var sword := fixture.equip("weapon")
	var shield := fixture.equip("shield")
	var armor := fixture.equip("armor")
	fixture.terrain.site.worker.cargo.merge({"arrow": 3, "wood": 2})
	fixture.captivity_allowed = false
	assert(not actions.begin_capture(1, 2, 1).ok and fixture.terrain.site.ground_loot.is_empty())
	fixture.captivity_allowed = true
	fixture.army.combat_units[0].erase("hit_revision") # Original Army only writes this after an effective hit.
	assert(actions.begin_capture(1, 2, 1).ok)
	assert(actions.begin_capture(3, 2, 3).ok)
	actions.advance(4.0)
	assert(not fixture.npc.captive and fixture.terrain.site.ground_loot.is_empty())
	var results := actions.settle_after_contacts()
	assert(results.size() == 2 and not results[1].ok, "Only one simultaneous captor commits")
	var result: Dictionary = results[0]
	assert(result.ok and fixture.npc.captive and actions.is_guarding(1))
	assert(fixture.supply_commits == [[2, 1, true]])
	var bag: Dictionary = fixture.terrain.site.ground_loot[result.container_id]
	assert(bag.kind == "sealed" and bag.original_owner == 2 and bag.item_ids.size() == 2)
	assert(bag.item_ids.has(sword) and bag.item_ids.has(shield) and bag.cargo == {"arrow": 3})
	assert(fixture.npc.item_state.item_ids == [armor] and fixture.terrain.site.worker.cargo == {"wood": 2})
	assert(not actions.begin_capture(3, 2, 3).ok and not actions.begin_loot(1, "person", "2", {"wood": 1}, []).ok)
	fixture.army.faction_id = 1
	assert(not actions.begin_unbind(3, 2).ok)
	fixture.army.faction_id = 0
	assert(actions.begin_unbind(3, 2).ok)
	actions.advance(4.0)
	assert(actions.settle_after_contacts()[0].ok)
	assert(not fixture.npc.captive and fixture.npc.knockout_left == 30.0 and fixture.npc.hp == 100.0)
	assert(fixture.terrain.site.ground_loot[result.container_id] == bag and fixture.npc.item_state.item_ids == [armor])
	assert(fixture.supply_commits == [[2, 1, true], [2, 1, false]])
	for identity: int in range(10, 14):
		fixture.terrain.site.captivity[str(identity)] = {"guard_id": 1}
	assert(not actions.begin_capture(1, 2, 1).ok, "At most four recorded captives per original guard")
	fixture.terrain.site.captivity.clear()
	fixture.army.cells[0] = Vector2i(10, 10)
	assert(not actions.begin_capture(1, 2, 3).ok, "No remote guards")
	assert(actions.begin_capture(1, 2, 1).ok)
	actions.advance(4.0)
	fixture.npc.apply_contact({"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	assert(not actions.settle_after_contacts()[0].ok and not fixture.npc.captive)
	assert(fixture.terrain.site.ground_loot.size() == 1 and fixture.supply_commits.size() == 2)
	fixture.close()

func _check_escape_and_ransom() -> void:
	var fixture := Fixture.new()
	var actions := fixture.actions
	fixture.npc.knockout_left = 30.0
	assert(actions.begin_capture(1, 2, 1).ok)
	actions.advance(4.0)
	assert(actions.settle_after_contacts()[0].ok)
	assert(not actions.begin_escape(2).ok, "An unconscious person cannot initiate escape")
	fixture.npc.knockout_left = 0.0
	assert(actions.begin_escape(2).ok)
	actions.advance(100.0)
	assert(actions.job_for(2).elapsed == 0.0 and fixture.npc.captive, "An effective nearby guard prevents escape")
	fixture.character.terrain_cell = Vector2i(10, 10)
	actions.advance(29.0)
	assert(actions.settle_after_contacts().is_empty() and fixture.npc.captive)
	fixture.threatened = true
	actions.advance(1.0)
	assert(actions.job_for(2).elapsed == 0.0)
	fixture.threatened = false
	actions.advance(30.0)
	fixture.npc.apply_contact({"result": {"hp": 0.0, "stun": 1.0, "guard_break": false}, "shield": false})
	assert(actions.settle_after_contacts().is_empty() and fixture.npc.captive and actions.job_for(2).elapsed == 0.0)
	actions.advance(30.0)
	assert(actions.settle_after_contacts()[0].ok and not fixture.npc.captive)
	assert(fixture.npc.hp == 100.0 and fixture.terrain.site.captivity.is_empty())
	fixture.close()
	for outcome: String in ["success", "consumed", "alias", "hit", "death"]:
		fixture = Fixture.new()
		actions = fixture.actions
		fixture.npc.captive = true
		fixture.army.faction_id = 1
		fixture.army.cells[0] = Vector2i(4, 5)
		fixture.terrain.site.captivity["2"] = {"version": 1, "captor_id": 3, "guard_id": 3,
			"captor_faction": 1, "sealed_container": ""}
		var source: Dictionary = fixture.ransom_source
		var destination: Dictionary = fixture.ransom_destination
		if outcome == "alias":
			fixture.ransom_alias = true
			assert(not actions.begin_ransom(1, 2, 3).ok)
		else:
			assert(actions.begin_ransom(1, 2, 3).ok)
			actions.advance(9.999)
			assert(actions.settle_after_contacts().is_empty() and source.grain == 100 and destination.is_empty())
			actions.advance(0.001)
			match outcome:
				"consumed": source.grain = 99 # Existing supply may consume without an item revision.
				"hit": fixture.army.combat_units[0].hit_revision += 1
				"death": fixture.npc.hp = 0.0
			var result: Dictionary = actions.settle_after_contacts()[0]
			if outcome == "success":
				assert(result.ok and source.is_empty() and destination.grain == 100 and not fixture.npc.captive)
				assert(fixture.ransom_revisions == [1, 1] and fixture.supply_commits == [[2, 3, false]])
				assert(fixture.terrain.site.manual.cargo.is_empty(), "Team ransom never bypasses the person's 20-item bag")
			else:
				assert(not result.ok and destination.is_empty() and fixture.npc.captive)
				assert(fixture.supply_commits.is_empty() and fixture.ransom_revisions == [0, 0])
		assert(is_same(source, fixture.ransom_source) and is_same(destination, fixture.ransom_destination))
		fixture.close()
